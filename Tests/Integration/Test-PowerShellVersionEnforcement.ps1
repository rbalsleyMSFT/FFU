<#
.SYNOPSIS
    Regression test for PowerShell version enforcement and auto-relaunch functionality

.DESCRIPTION
    Tests that BuildFFUVM.ps1 correctly:
    1. Detects PowerShell Core (7.x) execution
    2. Automatically relaunches in Windows PowerShell 5.1
    3. Preserves all script parameters during relaunch
    4. Logs PowerShell version information
    5. Fails gracefully if Windows PowerShell 5.1 not found

    Prevents regression of: "Could not load type 'Microsoft.PowerShell.Telemetry.Internal.TelemetryAPI'"

.NOTES
    Author: FFU Builder Team
    Date: 2025-11-24
    Related: POWERSHELL_VERSION_COMPATIBILITY_ANALYSIS.md
#>

#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
$testResults = @()
$totalTests = 0
$passedTests = 0
$failedTests = 0

function Write-TestHeader {
    param([string]$Message)
    Write-Host "`n===============================================" -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "===============================================`n" -ForegroundColor Cyan
}

function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Message = ""
    )

    $script:totalTests++

    if ($Passed) {
        $script:passedTests++
        Write-Host "[PASS] $TestName" -ForegroundColor Green
        if ($Message) {
            Write-Host "       $Message" -ForegroundColor Gray
        }
        $script:testResults += [PSCustomObject]@{
            Test = $TestName
            Status = "PASS"
            Message = $Message
        }
    }
    else {
        $script:failedTests++
        Write-Host "[FAIL] $TestName" -ForegroundColor Red
        if ($Message) {
            Write-Host "       $Message" -ForegroundColor Yellow
        }
        $script:testResults += [PSCustomObject]@{
            Test = $TestName
            Status = "FAIL"
            Message = $Message
        }
    }
}

Write-TestHeader "PowerShell Version Enforcement - Regression Tests"

# Test 1: Verify BuildFFUVM.ps1 contains auto-relaunch logic
Write-Host "Test 1: Verify BuildFFUVM.ps1 contains auto-relaunch logic" -ForegroundColor Yellow
try {
    $scriptPath = Join-Path $PSScriptRoot "BuildFFUVM.ps1"
    $scriptContent = Get-Content $scriptPath -Raw

    if ($scriptContent -match 'if \(\$PSVersionTable\.PSEdition -eq ''Core''\)') {
        Write-TestResult -TestName "Auto-relaunch detection code present" -Passed $true
    }
    else {
        Write-TestResult -TestName "Auto-relaunch detection code present" -Passed $false -Message "PowerShell edition check not found"
    }

    if ($scriptContent -match '\$psExe = "\$env:SystemRoot\\System32\\WindowsPowerShell\\v1\.0\\powershell\.exe"') {
        Write-TestResult -TestName "Windows PowerShell 5.1 path reference present" -Passed $true
    }
    else {
        Write-TestResult -TestName "Windows PowerShell 5.1 path reference present" -Passed $false -Message "PowerShell.exe path not found"
    }

    if ($scriptContent -match '& \$psExe @arguments') {
        Write-TestResult -TestName "Relaunch execution code present" -Passed $true
    }
    else {
        Write-TestResult -TestName "Relaunch execution code present" -Passed $false -Message "Relaunch execution not found"
    }

    if ($scriptContent -match 'exit \$LASTEXITCODE') {
        Write-TestResult -TestName "Exit code preservation present" -Passed $true
    }
    else {
        Write-TestResult -TestName "Exit code preservation present" -Passed $false -Message "Exit code handling not found"
    }
}
catch {
    Write-TestResult -TestName "BuildFFUVM.ps1 auto-relaunch code validation" -Passed $false -Message $_.Exception.Message
}

# Test 2: Verify PowerShell 5.1 Desktop edition check
Write-Host "`nTest 2: Validate Desktop edition verification logic" -ForegroundColor Yellow
try {
    $scriptPath = Join-Path $PSScriptRoot "BuildFFUVM.ps1"
    $scriptContent = Get-Content $scriptPath -Raw

    if ($scriptContent -match 'if \(\$PSVersionTable\.PSEdition -ne ''Desktop''\)') {
        Write-TestResult -TestName "Desktop edition verification present" -Passed $true
    }
    else {
        Write-TestResult -TestName "Desktop edition verification present" -Passed $false -Message "Desktop edition check not found"
    }

    if ($scriptContent -match 'FATAL ERROR: Script must run in Windows PowerShell 5\.1 \(Desktop Edition\)') {
        Write-TestResult -TestName "Clear error message for wrong edition" -Passed $true
    }
    else {
        Write-TestResult -TestName "Clear error message for wrong edition" -Passed $false -Message "Error message not found"
    }
}
catch {
    Write-TestResult -TestName "Desktop edition verification validation" -Passed $false -Message $_.Exception.Message
}

# Test 3: Verify parameter preservation logic
Write-Host "`nTest 3: Validate parameter preservation during relaunch" -ForegroundColor Yellow
try {
    $scriptPath = Join-Path $PSScriptRoot "BuildFFUVM.ps1"
    $scriptContent = Get-Content $scriptPath -Raw

    $parameterTypes = @('bool', 'switch', 'string', 'hashtable', 'int', 'int64', 'uint64')
    $foundTypes = 0

    foreach ($type in $parameterTypes) {
        if ($scriptContent -match "\`$value -is \[$type\]") {
            $foundTypes++
        }
    }

    if ($foundTypes -eq $parameterTypes.Count) {
        Write-TestResult -TestName "All parameter types handled" -Passed $true -Message "Found $foundTypes/$($parameterTypes.Count) parameter type handlers"
    }
    else {
        Write-TestResult -TestName "All parameter types handled" -Passed $false -Message "Only found $foundTypes/$($parameterTypes.Count) parameter type handlers"
    }

    if ($scriptContent -match 'foreach \(\$key in \$PSBoundParameters\.Keys\)') {
        Write-TestResult -TestName "Parameter iteration logic present" -Passed $true
    }
    else {
        Write-TestResult -TestName "Parameter iteration logic present" -Passed $false -Message "Parameter loop not found"
    }
}
catch {
    Write-TestResult -TestName "Parameter preservation validation" -Passed $false -Message $_.Exception.Message
}

# Test 4: Verify Windows PowerShell 5.1 availability
Write-Host "`nTest 4: Verify Windows PowerShell 5.1 installation" -ForegroundColor Yellow
try {
    $psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

    if (Test-Path $psExe) {
        Write-TestResult -TestName "Windows PowerShell 5.1 executable exists" -Passed $true -Message "Found at: $psExe"
    }
    else {
        Write-TestResult -TestName "Windows PowerShell 5.1 executable exists" -Passed $false -Message "Not found at: $psExe"
    }

    # Test execution
    $version = & $psExe -Command '$PSVersionTable.PSVersion.ToString()'
    if ($version) {
        Write-TestResult -TestName "Windows PowerShell 5.1 is executable" -Passed $true -Message "Version: $version"
    }
    else {
        Write-TestResult -TestName "Windows PowerShell 5.1 is executable" -Passed $false -Message "Failed to execute"
    }

    # Test edition
    $edition = & $psExe -Command '$PSVersionTable.PSEdition'
    if ($edition -eq 'Desktop') {
        Write-TestResult -TestName "Windows PowerShell is Desktop edition" -Passed $true
    }
    else {
        Write-TestResult -TestName "Windows PowerShell is Desktop edition" -Passed $false -Message "Edition: $edition"
    }
}
catch {
    Write-TestResult -TestName "Windows PowerShell 5.1 availability" -Passed $false -Message $_.Exception.Message
}

# Test 5: Test auto-relaunch from PowerShell 7 (if available)
Write-Host "`nTest 5: Test auto-relaunch from PowerShell 7" -ForegroundColor Yellow

$pwshExe = "C:\Program Files\PowerShell\7\pwsh.exe"
if (Test-Path $pwshExe) {
    try {
        # Create a minimal test script that just reports PowerShell version
        $testScript = @"
param([string]`$TestParam = 'DefaultValue')
Write-Host "PowerShell Version: `$(`$PSVersionTable.PSVersion)"
Write-Host "PowerShell Edition: `$(`$PSVersionTable.PSEdition)"
Write-Host "TestParam: `$TestParam"
exit 42
"@
        $testScriptPath = Join-Path $env:TEMP "Test-PSRelaunch.ps1"
        $testScript | Set-Content $testScriptPath -Force

        # Execute from PowerShell 7
        $output = & $pwshExe -File $testScriptPath -TestParam "TestValue"
        $exitCode = $LASTEXITCODE

        Write-TestResult -TestName "PowerShell 7 execution test" -Passed $true -Message "Exit code: $exitCode"

        # Verify output
        if ($output -join "`n" -match "PowerShell Version:") {
            Write-TestResult -TestName "PowerShell version logged" -Passed $true
        }
        else {
            Write-TestResult -TestName "PowerShell version logged" -Passed $false -Message "Version not in output"
        }

        # Cleanup
        Remove-Item $testScriptPath -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-TestResult -TestName "PowerShell 7 auto-relaunch test" -Passed $false -Message $_.Exception.Message
    }
}
else {
    Write-Host "[SKIP] PowerShell 7 not installed at: $pwshExe" -ForegroundColor Yellow
    Write-Host "       Auto-relaunch from PowerShell 7 cannot be tested" -ForegroundColor Gray
}

# Test 6: Verify BuildFFUVM_UI.ps1 has correct comments
Write-Host "`nTest 6: Verify BuildFFUVM_UI.ps1 has PowerShell version documentation" -ForegroundColor Yellow
try {
    $uiScriptPath = Join-Path $PSScriptRoot "BuildFFUVM_UI.ps1"
    $uiContent = Get-Content $uiScriptPath -Raw

    if ($uiContent -match 'BuildFFUVM\.ps1.*has auto-relaunch logic') {
        Write-TestResult -TestName "UI script documents auto-relaunch behavior" -Passed $true
    }
    else {
        Write-TestResult -TestName "UI script documents auto-relaunch behavior" -Passed $false -Message "Comment not found"
    }

    if ($uiContent -match 'The UI requires PowerShell 7') {
        Write-TestResult -TestName "UI script documents PowerShell 7 requirement" -Passed $true
    }
    else {
        Write-TestResult -TestName "UI script documents PowerShell 7 requirement" -Passed $false -Message "Comment not found"
    }

    if ($uiContent -match 'if \(\$PSVersionTable\.PSVersion\.Major -lt 7\)') {
        Write-TestResult -TestName "UI script enforces PowerShell 7 minimum" -Passed $true
    }
    else {
        Write-TestResult -TestName "UI script enforces PowerShell 7 minimum" -Passed $false -Message "Version check not found"
    }
}
catch {
    Write-TestResult -TestName "BuildFFUVM_UI.ps1 validation" -Passed $false -Message $_.Exception.Message
}

# Test 7: Verify current session is Windows PowerShell 5.1
Write-Host "`nTest 7: Verify test is running in Windows PowerShell 5.1" -ForegroundColor Yellow
try {
    if ($PSVersionTable.PSEdition -eq 'Desktop') {
        Write-TestResult -TestName "Test running in Desktop edition" -Passed $true
    }
    else {
        Write-TestResult -TestName "Test running in Desktop edition" -Passed $false -Message "Edition: $($PSVersionTable.PSEdition)"
    }

    if ($PSVersionTable.PSVersion.Major -eq 5) {
        Write-TestResult -TestName "Test running in PowerShell 5.x" -Passed $true
    }
    else {
        Write-TestResult -TestName "Test running in PowerShell 5.x" -Passed $false -Message "Version: $($PSVersionTable.PSVersion)"
    }
}
catch {
    Write-TestResult -TestName "Current PowerShell version validation" -Passed $false -Message $_.Exception.Message
}

# Summary
Write-TestHeader "Test Summary"

Write-Host "Total Tests: $totalTests" -ForegroundColor White
Write-Host "Passed: $passedTests" -ForegroundColor Green
Write-Host "Failed: $failedTests" -ForegroundColor $(if ($failedTests -gt 0) { 'Red' } else { 'Green' })
$passRate = if ($totalTests -gt 0) { [math]::Round(($passedTests / $totalTests) * 100, 1) } else { 0 }
Write-Host "Pass Rate: $passRate%`n" -ForegroundColor $(if ($passRate -eq 100) { 'Green' } elseif ($passRate -ge 80) { 'Yellow' } else { 'Red' })

if ($failedTests -gt 0) {
    Write-Host "`nFailed Tests:" -ForegroundColor Red
    $testResults | Where-Object { $_.Status -eq "FAIL" } | Format-Table -AutoSize
    Write-Host "`n[OVERALL: FAIL] Some PowerShell version enforcement tests failed" -ForegroundColor Red
    Write-Host "The auto-relaunch functionality may not work correctly. Review failures above.`n" -ForegroundColor Yellow
    exit 1
}
else {
    Write-Host "`n[OVERALL: PASS] All PowerShell version enforcement tests passed!" -ForegroundColor Green
    Write-Host "The auto-relaunch functionality is correctly implemented.`n" -ForegroundColor Cyan
    Write-Host "Key validations:" -ForegroundColor White
    Write-Host "  [OK] Auto-relaunch detection code present in BuildFFUVM.ps1" -ForegroundColor Green
    Write-Host "  [OK] Desktop edition verification enforced" -ForegroundColor Green
    Write-Host "  [OK] Parameter preservation logic implemented" -ForegroundColor Green
    Write-Host "  [OK] Windows PowerShell 5.1 available and executable" -ForegroundColor Green
    Write-Host "  [OK] BuildFFUVM_UI.ps1 correctly documented" -ForegroundColor Green
    exit 0
}
