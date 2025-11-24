#Requires -RunAsAdministrator

Write-Host "=== Testing Config File Loading with Parameter Validation ===" -ForegroundColor Green

# Create test config directory
$testConfigDir = Join-Path $PSScriptRoot "test_config_temp"
New-Item -ItemType Directory -Path $testConfigDir -Force | Out-Null

try {
    # Test 1: Config file with Server SKU
    Write-Host "`nTest 1: Config file with WindowsRelease=2022 and WindowsSKU='Standard'" -ForegroundColor Cyan
    $config1 = @{
        WindowsRelease = 2022
        WindowsSKU = "Standard"
        VMSwitchName = "Test Switch"
        VMHostIPAddress = "192.168.1.100"
    }
    $config1Path = Join-Path $testConfigDir "test1.json"
    $config1 | ConvertTo-Json | Out-File $config1Path

    Write-Host "   Created config: $config1Path"
    Write-Host "   Config contains: WindowsRelease=2022, WindowsSKU='Standard'"
    Write-Host "   Testing if script validates AFTER loading config..."

    # This should NOT fail because validation happens after config loading
    $testScript = @"
using module .\Modules\FFU.Constants\FFU.Constants.psm1
`$ErrorActionPreference = 'Stop'
. '$PSScriptRoot\BuildFFUVM.ps1' -ConfigFile '$config1Path' -WhatIf 2>&1 | Out-Null
if (`$?) {
    Write-Host '   ✅ PASS: Script validated config correctly' -ForegroundColor Green
} else {
    Write-Host '   ❌ FAIL: Script rejected valid config' -ForegroundColor Red
    exit 1
}
"@

    $result = powershell.exe -ExecutionPolicy Bypass -Command $testScript
    Write-Host $result

    # Test 2: Command line WindowsRelease + Config WindowsSKU
    Write-Host "`nTest 2: Command line WindowsRelease=2022 + Config file WindowsSKU='Standard'" -ForegroundColor Cyan
    Write-Host "   This previously FAILED because BEGIN block validated before config load"
    Write-Host "   Should now PASS because validation happens after config load"

    $testScript2 = @"
using module .\Modules\FFU.Constants\FFU.Constants.psm1
`$ErrorActionPreference = 'Stop'
try {
    # Dot-source to load parameters, but don't execute
    . '$PSScriptRoot\BuildFFUVM.ps1' -WindowsRelease 2022 -ConfigFile '$config1Path' -WhatIf 2>&1 | Out-Null
    Write-Host '   ✅ PASS: Script accepted WindowsRelease from command line + WindowsSKU from config' -ForegroundColor Green
} catch {
    Write-Host '   ❌ FAIL: Script rejected valid combination' -ForegroundColor Red
    Write-Host "   Error: `$(`$_.Exception.Message)" -ForegroundColor Red
    exit 1
}
"@

    $result2 = powershell.exe -ExecutionPolicy Bypass -Command $testScript2
    Write-Host $result2

    # Test 3: Invalid SKU should still be rejected
    Write-Host "`nTest 3: Invalid SKU should still be rejected after config load" -ForegroundColor Cyan
    $config3 = @{
        WindowsRelease = 2022
        WindowsSKU = "Pro"  # Invalid for Server 2022
    }
    $config3Path = Join-Path $testConfigDir "test3.json"
    $config3 | ConvertTo-Json | Out-File $config3Path

    Write-Host "   Config contains: WindowsRelease=2022, WindowsSKU='Pro' (INVALID)"
    Write-Host "   Should be rejected..."

    $testScript3 = @"
using module .\Modules\FFU.Constants\FFU.Constants.psm1
`$ErrorActionPreference = 'Stop'
try {
    . '$PSScriptRoot\BuildFFUVM.ps1' -ConfigFile '$config3Path' -WhatIf 2>&1 | Out-Null
    Write-Host '   ❌ FAIL: Script accepted invalid SKU' -ForegroundColor Red
    exit 1
} catch {
    if (`$_.Exception.Message -like '*not valid for Windows Server*' -or `$_.Exception.Message -like '*requires one of these SKUs*') {
        Write-Host '   ✅ PASS: Script correctly rejected invalid SKU' -ForegroundColor Green
    } else {
        Write-Host '   ❌ FAIL: Wrong error message' -ForegroundColor Red
        Write-Host "   Error: `$(`$_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}
"@

    $result3 = powershell.exe -ExecutionPolicy Bypass -Command $testScript3
    Write-Host $result3

    Write-Host "`n=== All Config File Validation Tests Complete ===" -ForegroundColor Green
}
finally {
    # Cleanup
    if (Test-Path $testConfigDir) {
        Remove-Item $testConfigDir -Recurse -Force
        Write-Host "`nCleaned up test files" -ForegroundColor Gray
    }
}
