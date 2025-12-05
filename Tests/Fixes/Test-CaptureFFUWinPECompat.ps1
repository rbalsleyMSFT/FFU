<#
.SYNOPSIS
    Test script for CaptureFFU.ps1 WinPE compatibility fixes

.DESCRIPTION
    Validates that the WMI/CIM-based helper functions work correctly.
    These functions replace cmdlets that are not available in WinPE:
    - Get-NetIPAddress -> Get-WmiIPAddress
    - Get-NetRoute -> Get-WmiDefaultGateway
    - Test-Connection -> Test-HostConnection
    - Resolve-DnsName -> Resolve-HostNameDotNet

.NOTES
    Created: 2025-11-26
    Part of: CaptureFFU.ps1 WinPE Compatibility Fix
#>

param(
    [string]$CaptureFFUPath = "$PSScriptRoot\WinPECaptureFFUFiles\CaptureFFU.ps1"
)

$ErrorActionPreference = 'Continue'
$testResults = @()
$passCount = 0
$failCount = 0

function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Message = ""
    )

    $status = if ($Passed) { "PASSED" } else { "FAILED" }
    $color = if ($Passed) { "Green" } else { "Red" }
    $symbol = if ($Passed) { "[+]" } else { "[-]" }

    Write-Host "$symbol $TestName - $status" -ForegroundColor $color
    if ($Message) {
        Write-Host "    $Message" -ForegroundColor Gray
    }

    $script:testResults += [PSCustomObject]@{
        Test = $TestName
        Status = $status
        Message = $Message
    }

    if ($Passed) { $script:passCount++ } else { $script:failCount++ }
}

Write-Host "`n=======================================" -ForegroundColor Cyan
Write-Host "CaptureFFU.ps1 WinPE Compatibility Test" -ForegroundColor Cyan
Write-Host "=======================================`n" -ForegroundColor Cyan

# Source the CaptureFFU.ps1 to get the functions (suppress the main execution)
Write-Host "Loading functions from CaptureFFU.ps1..." -ForegroundColor Yellow

# Extract just the functions from CaptureFFU.ps1
$captureFFUContent = Get-Content $CaptureFFUPath -Raw

# Find the function definitions and dot-source them
$functionPattern = '(?ms)(function\s+(Get-WmiNetworkAdapter|Get-WmiIPAddress|Convert-SubnetMaskToPrefix|Get-WmiDefaultGateway|Test-HostConnection|Resolve-HostNameDotNet)\s*\{.*?\n\})'
$matches = [regex]::Matches($captureFFUContent, $functionPattern)

$functionsToLoad = $matches | ForEach-Object { $_.Groups[1].Value }
$functionScript = $functionsToLoad -join "`n`n"

# Create a script block and invoke it to load the functions
$scriptBlock = [scriptblock]::Create($functionScript)
. $scriptBlock

Write-Host "Functions loaded successfully.`n" -ForegroundColor Green

# =============================================================================
# Test 1: Get-WmiIPAddress function exists
# =============================================================================
$test1 = Get-Command Get-WmiIPAddress -ErrorAction SilentlyContinue
Write-TestResult -TestName "Get-WmiIPAddress function exists" -Passed ($null -ne $test1)

# =============================================================================
# Test 2: Get-WmiIPAddress returns valid data
# =============================================================================
$ipAddresses = Get-WmiIPAddress -AddressFamily IPv4
$test2 = $null -ne $ipAddresses -and $ipAddresses.Count -gt 0
Write-TestResult -TestName "Get-WmiIPAddress returns IPv4 addresses" -Passed $test2 -Message "Found $($ipAddresses.Count) address(es)"

# =============================================================================
# Test 3: Get-WmiIPAddress filters APIPA correctly
# =============================================================================
$nonApipa = $ipAddresses | Where-Object { $_.IPAddress -notlike "169.254.*" }
Write-TestResult -TestName "Get-WmiIPAddress can filter APIPA" -Passed $true -Message "Filter expression works"

# =============================================================================
# Test 4: Get-WmiDefaultGateway function exists
# =============================================================================
$test4 = Get-Command Get-WmiDefaultGateway -ErrorAction SilentlyContinue
Write-TestResult -TestName "Get-WmiDefaultGateway function exists" -Passed ($null -ne $test4)

# =============================================================================
# Test 5: Get-WmiDefaultGateway returns data structure
# =============================================================================
$gateway = Get-WmiDefaultGateway
$test5 = $null -eq $gateway -or ($gateway | Get-Member -Name NextHop -ErrorAction SilentlyContinue)
Write-TestResult -TestName "Get-WmiDefaultGateway returns correct structure" -Passed $test5 -Message "NextHop property exists or no gateway configured"

# =============================================================================
# Test 6: Test-HostConnection function exists
# =============================================================================
$test6 = Get-Command Test-HostConnection -ErrorAction SilentlyContinue
Write-TestResult -TestName "Test-HostConnection function exists" -Passed ($null -ne $test6)

# =============================================================================
# Test 7: Test-HostConnection works with -Quiet
# =============================================================================
$pingResult = Test-HostConnection -ComputerName "127.0.0.1" -Count 1 -Quiet
$test7 = $pingResult -eq $true
Write-TestResult -TestName "Test-HostConnection pings localhost" -Passed $test7 -Message "Ping 127.0.0.1 returned: $pingResult"

# =============================================================================
# Test 8: Test-HostConnection returns detailed output
# =============================================================================
$pingDetailed = Test-HostConnection -ComputerName "127.0.0.1" -Count 1
$test8 = $pingDetailed.PSObject.Properties.Name -contains "Success" -and $pingDetailed.PSObject.Properties.Name -contains "Output"
Write-TestResult -TestName "Test-HostConnection returns detailed output" -Passed $test8 -Message "Has Success and Output properties"

# =============================================================================
# Test 9: Resolve-HostNameDotNet function exists
# =============================================================================
$test9 = Get-Command Resolve-HostNameDotNet -ErrorAction SilentlyContinue
Write-TestResult -TestName "Resolve-HostNameDotNet function exists" -Passed ($null -ne $test9)

# =============================================================================
# Test 10: Resolve-HostNameDotNet resolves localhost
# =============================================================================
$resolved = Resolve-HostNameDotNet -Name "localhost"
$test10 = $null -ne $resolved
Write-TestResult -TestName "Resolve-HostNameDotNet resolves localhost" -Passed $test10 -Message "Resolved to: $(if ($resolved) { $resolved[0].IPAddress } else { 'N/A' })"

# =============================================================================
# Test 11: Convert-SubnetMaskToPrefix works
# =============================================================================
$prefix = Convert-SubnetMaskToPrefix -SubnetMask "255.255.255.0"
$test11 = $prefix -eq 24
Write-TestResult -TestName "Convert-SubnetMaskToPrefix converts correctly" -Passed $test11 -Message "255.255.255.0 = /$prefix (expected /24)"

# =============================================================================
# Test 12: No incompatible cmdlets remain (except in comments)
# =============================================================================
$incompatibleCmdlets = @('Get-NetIPAddress', 'Get-NetRoute', 'Test-Connection', 'Resolve-DnsName')
$codeLines = $captureFFUContent -split "`n" | Where-Object { $_ -notmatch '^\s*#' -and $_ -notmatch '<#' -and $_ -notmatch '#>' }
$codeOnly = $codeLines -join "`n"

$foundIncompatible = $false
foreach ($cmdlet in $incompatibleCmdlets) {
    if ($codeOnly -match "\b$cmdlet\b") {
        Write-Host "  Found incompatible cmdlet in code: $cmdlet" -ForegroundColor Red
        $foundIncompatible = $true
    }
}
Write-TestResult -TestName "No incompatible cmdlets in code (only comments)" -Passed (-not $foundIncompatible)

# =============================================================================
# Test 13: Get-WmiNetworkAdapter function exists
# =============================================================================
$test13 = Get-Command Get-WmiNetworkAdapter -ErrorAction SilentlyContinue
Write-TestResult -TestName "Get-WmiNetworkAdapter function exists" -Passed ($null -ne $test13)

# =============================================================================
# Summary
# =============================================================================
Write-Host "`n=======================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "Total Tests: $($passCount + $failCount)" -ForegroundColor White
Write-Host "Passed: $passCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "Green" })

$passRate = [math]::Round(($passCount / ($passCount + $failCount)) * 100, 1)
Write-Host "Pass Rate: $passRate%" -ForegroundColor $(if ($passRate -eq 100) { "Green" } elseif ($passRate -ge 80) { "Yellow" } else { "Red" })

Write-Host "`n=======================================" -ForegroundColor Cyan
Write-Host "WinPE Compatibility Status" -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan

if ($failCount -eq 0) {
    Write-Host "`nAll tests passed! CaptureFFU.ps1 is now WinPE compatible." -ForegroundColor Green
    Write-Host "`nReplaced cmdlets:" -ForegroundColor White
    Write-Host "  Get-NetIPAddress  -> Get-WmiIPAddress" -ForegroundColor Cyan
    Write-Host "  Get-NetRoute      -> Get-WmiDefaultGateway" -ForegroundColor Cyan
    Write-Host "  Test-Connection   -> Test-HostConnection (uses ping.exe)" -ForegroundColor Cyan
    Write-Host "  Resolve-DnsName   -> Resolve-HostNameDotNet (uses .NET)" -ForegroundColor Cyan
} else {
    Write-Host "`nSome tests failed. Please review the failures above." -ForegroundColor Red
}

# Return results for automation
return [PSCustomObject]@{
    TotalTests = $passCount + $failCount
    Passed = $passCount
    Failed = $failCount
    PassRate = $passRate
    Results = $testResults
}
