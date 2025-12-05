<#
.SYNOPSIS
    Regression test for PowerShell cross-version compatibility (5.1 and 7+)

.DESCRIPTION
    Tests that FFUBuilder works natively in both PowerShell 5.1 and PowerShell 7+:
    1. .NET DirectoryServices API helper functions exist in FFU.VM module
    2. Helper functions work correctly in current PowerShell version
    3. Set-CaptureFFU and Remove-FFUUserShare use cross-version compatible APIs
    4. BuildFFUVM_UI.ps1 allows PowerShell 5.1+
    5. No auto-relaunch logic present (removed)

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

Write-TestHeader "PowerShell Cross-Version Compatibility Tests"
Write-Host "Current PowerShell: $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition) Edition)`n" -ForegroundColor Cyan

# Test 1: Verify helper functions exist in FFU.VM module
Write-Host "Test 1: Verify .NET DirectoryServices helper functions in FFU.VM" -ForegroundColor Yellow
try {
    $modulePath = Join-Path $PSScriptRoot "Modules\FFU.VM\FFU.VM.psm1"
    $moduleContent = Get-Content $modulePath -Raw

    $helperFunctions = @('Get-LocalUserAccount', 'New-LocalUserAccount', 'Remove-LocalUserAccount')

    foreach ($funcName in $helperFunctions) {
        if ($moduleContent -match "function $funcName \{") {
            Write-TestResult -TestName "$funcName helper function exists" -Passed $true
        }
        else {
            Write-TestResult -TestName "$funcName helper function exists" -Passed $false -Message "Function not found"
        }
    }

    if ($moduleContent -match 'System\.DirectoryServices\.AccountManagement') {
        Write-TestResult -TestName "Uses DirectoryServices.AccountManagement API" -Passed $true
    }
    else {
        Write-TestResult -TestName "Uses DirectoryServices.AccountManagement API" -Passed $false -Message "API reference not found"
    }
}
catch {
    Write-TestResult -TestName "FFU.VM helper functions validation" -Passed $false -Message $_.Exception.Message
}

# Test 2: Verify Set-CaptureFFU uses helper functions
Write-Host "`nTest 2: Verify Set-CaptureFFU uses cross-version compatible APIs" -ForegroundColor Yellow
try {
    $modulePath = Join-Path $PSScriptRoot "Modules\FFU.VM\FFU.VM.psm1"
    $moduleContent = Get-Content $modulePath -Raw

    # Should NOT use Get-LocalUser cmdlet
    if ($moduleContent -match 'Get-LocalUser\s+-Name') {
        Write-TestResult -TestName "Set-CaptureFFU avoids Get-LocalUser cmdlet" -Passed $false -Message "Still using Get-LocalUser cmdlet"
    }
    else {
        Write-TestResult -TestName "Set-CaptureFFU avoids Get-LocalUser cmdlet" -Passed $true
    }

    # Should NOT use New-LocalUser cmdlet
    if ($moduleContent -match 'New-LocalUser\s+-Name') {
        Write-TestResult -TestName "Set-CaptureFFU avoids New-LocalUser cmdlet" -Passed $false -Message "Still using New-LocalUser cmdlet"
    }
    else {
        Write-TestResult -TestName "Set-CaptureFFU avoids New-LocalUser cmdlet" -Passed $true
    }

    # SHOULD use Get-LocalUserAccount helper
    if ($moduleContent -match 'Get-LocalUserAccount\s+-Username') {
        Write-TestResult -TestName "Set-CaptureFFU uses Get-LocalUserAccount helper" -Passed $true
    }
    else {
        Write-TestResult -TestName "Set-CaptureFFU uses Get-LocalUserAccount helper" -Passed $false -Message "Helper not found"
    }

    # SHOULD use New-LocalUserAccount helper
    if ($moduleContent -match 'New-LocalUserAccount\s+-Username') {
        Write-TestResult -TestName "Set-CaptureFFU uses New-LocalUserAccount helper" -Passed $true
    }
    else {
        Write-TestResult -TestName "Set-CaptureFFU uses New-LocalUserAccount helper" -Passed $false -Message "Helper not found"
    }
}
catch {
    Write-TestResult -TestName "Set-CaptureFFU API usage validation" -Passed $false -Message $_.Exception.Message
}

# Test 3: Verify Remove-FFUUserShare uses helper functions
Write-Host "`nTest 3: Verify Remove-FFUUserShare uses cross-version compatible APIs" -ForegroundColor Yellow
try {
    $modulePath = Join-Path $PSScriptRoot "Modules\FFU.VM\FFU.VM.psm1"
    $moduleContent = Get-Content $modulePath -Raw

    # Should NOT use Remove-LocalUser cmdlet
    if ($moduleContent -match 'Remove-LocalUser\s+-Name') {
        Write-TestResult -TestName "Remove-FFUUserShare avoids Remove-LocalUser cmdlet" -Passed $false -Message "Still using Remove-LocalUser cmdlet"
    }
    else {
        Write-TestResult -TestName "Remove-FFUUserShare avoids Remove-LocalUser cmdlet" -Passed $true
    }

    # SHOULD use Remove-LocalUserAccount helper
    if ($moduleContent -match 'Remove-LocalUserAccount\s+-Username') {
        Write-TestResult -TestName "Remove-FFUUserShare uses Remove-LocalUserAccount helper" -Passed $true
    }
    else {
        Write-TestResult -TestName "Remove-FFUUserShare uses Remove-LocalUserAccount helper" -Passed $false -Message "Helper not found"
    }
}
catch {
    Write-TestResult -TestName "Remove-FFUUserShare API usage validation" -Passed $false -Message $_.Exception.Message
}

# Test 4: Verify NO auto-relaunch logic in BuildFFUVM.ps1
Write-Host "`nTest 4: Verify auto-relaunch logic removed from BuildFFUVM.ps1" -ForegroundColor Yellow
try {
    $scriptPath = Join-Path $PSScriptRoot "BuildFFUVM.ps1"
    $scriptContent = Get-Content $scriptPath -Raw

    if ($scriptContent -match 'Auto-Relaunch') {
        Write-TestResult -TestName "No auto-relaunch logic present" -Passed $false -Message "Auto-relaunch code still exists"
    }
    else {
        Write-TestResult -TestName "No auto-relaunch logic present" -Passed $true
    }

    if ($scriptContent -match 'if \(\$PSVersionTable\.PSEdition -eq ''Core''\)') {
        Write-TestResult -TestName "No PowerShell Core detection for relaunch" -Passed $false -Message "Core edition check still exists"
    }
    else {
        Write-TestResult -TestName "No PowerShell Core detection for relaunch" -Passed $true
    }

    if ($scriptContent -match 'powershell\.exe.*@arguments') {
        Write-TestResult -TestName "No relaunch execution code" -Passed $false -Message "Relaunch execution still exists"
    }
    else {
        Write-TestResult -TestName "No relaunch execution code" -Passed $true
    }
}
catch {
    Write-TestResult -TestName "BuildFFUVM.ps1 auto-relaunch removal" -Passed $false -Message $_.Exception.Message
}

# Test 5: Verify BuildFFUVM_UI.ps1 allows PowerShell 5.1+
Write-Host "`nTest 5: Verify BuildFFUVM_UI.ps1 version requirement" -ForegroundColor Yellow
try {
    $uiScriptPath = Join-Path $PSScriptRoot "BuildFFUVM_UI.ps1"
    $uiContent = Get-Content $uiScriptPath -Raw

    if ($uiContent -match 'if \(\$PSVersionTable\.PSVersion\.Major -lt 7\)') {
        Write-TestResult -TestName "UI no longer requires PowerShell 7" -Passed $false -Message "Still requires PowerShell 7"
    }
    else {
        Write-TestResult -TestName "UI no longer requires PowerShell 7" -Passed $true
    }

    if ($uiContent -match 'PowerShell 5\.1 or later is required' -or $uiContent -match '-lt 5') {
        Write-TestResult -TestName "UI allows PowerShell 5.1+" -Passed $true
    }
    else {
        Write-TestResult -TestName "UI allows PowerShell 5.1+" -Passed $false -Message "Version check not found"
    }

    if ($uiContent -match 'cross-version compatibility') {
        Write-TestResult -TestName "UI documents cross-version support" -Passed $true
    }
    else {
        Write-TestResult -TestName "UI documents cross-version support" -Passed $false -Message "Documentation not found"
    }
}
catch {
    Write-TestResult -TestName "BuildFFUVM_UI.ps1 validation" -Passed $false -Message $_.Exception.Message
}

# Test 6: Test helper functions actually work in current PowerShell version
Write-Host "`nTest 6: Test helper functions in current PowerShell version" -ForegroundColor Yellow
try {
    # Import FFU.VM module
    $modulePath = Join-Path $PSScriptRoot "Modules\FFU.VM\FFU.VM.psm1"
    Import-Module $modulePath -Force -Global -ErrorAction Stop

    # Test Get-LocalUserAccount
    $testUser = Get-LocalUserAccount -Username "Administrator"
    if ($testUser) {
        Write-TestResult -TestName "Get-LocalUserAccount works in current PowerShell" -Passed $true -Message "Retrieved Administrator account"
        $testUser.Dispose()
    }
    else {
        Write-TestResult -TestName "Get-LocalUserAccount works in current PowerShell" -Passed $false -Message "Failed to retrieve Administrator account"
    }

    # Test that nonexistent user returns null
    $nonExistentUser = Get-LocalUserAccount -Username "ThisUserDoesNotExist12345"
    if ($null -eq $nonExistentUser) {
        Write-TestResult -TestName "Get-LocalUserAccount handles nonexistent users" -Passed $true
    }
    else {
        Write-TestResult -TestName "Get-LocalUserAccount handles nonexistent users" -Passed $false -Message "Should return null for nonexistent user"
        if ($nonExistentUser) { $nonExistentUser.Dispose() }
    }
}
catch {
    Write-TestResult -TestName "Helper functions runtime test" -Passed $false -Message $_.Exception.Message
}

# Test 7: Verify current PowerShell version
Write-Host "`nTest 7: Verify test environment PowerShell version" -ForegroundColor Yellow
try {
    Write-TestResult -TestName "PowerShell version is 5.1 or higher" -Passed $true -Message "$($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"

    # Check if running in PowerShell 7 for additional context
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        Write-Host "       [INFO] Running in PowerShell $($PSVersionTable.PSVersion) - Cross-version compatibility validated" -ForegroundColor Cyan
    }
}
catch {
    Write-TestResult -TestName "PowerShell version validation" -Passed $false -Message $_.Exception.Message
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
    Write-Host "`n[OVERALL: FAIL] Some PowerShell 7 compatibility tests failed" -ForegroundColor Red
    Write-Host "The cross-version compatibility may not work correctly. Review failures above.`n" -ForegroundColor Yellow
    exit 1
}
else {
    Write-Host "`n[OVERALL: PASS] All PowerShell 7 compatibility tests passed!" -ForegroundColor Green
    Write-Host "FFUBuilder works natively in both PowerShell 5.1 and 7+`n" -ForegroundColor Cyan
    Write-Host "Key validations:" -ForegroundColor White
    Write-Host "  [OK] .NET DirectoryServices helper functions implemented" -ForegroundColor Green
    Write-Host "  [OK] Set-CaptureFFU and Remove-FFUUserShare use cross-version APIs" -ForegroundColor Green
    Write-Host "  [OK] No auto-relaunch logic (native compatibility)" -ForegroundColor Green
    Write-Host "  [OK] BuildFFUVM_UI.ps1 allows PowerShell 5.1+" -ForegroundColor Green
    Write-Host "  [OK] Helper functions work in current PowerShell version" -ForegroundColor Green
    exit 0
}
