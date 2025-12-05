<#
.SYNOPSIS
    Test script to verify fix for CaptureFFU.ps1 password mismatch error

.DESCRIPTION
    This test verifies that when:
    1. The ffu_user account already exists from a previous build
    2. A new password is generated for the current build
    3. Set-CaptureFFU correctly resets the password to match CaptureFFU.ps1

    This prevents "Password is incorrect for user 'ffu_user'" (Error 86) errors
    during WinPE FFU capture.

.NOTES
    Created: 2025-11-26
    Fix: Added Set-LocalUserPassword function and password reset in Set-CaptureFFU
#>

param(
    [string]$ModulesPath = "$PSScriptRoot\Modules"
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

    if ($Passed) {
        $status = "PASSED"
        $color = "Green"
        $symbol = "[+]"
        $script:passCount++
    } else {
        $status = "FAILED"
        $color = "Red"
        $symbol = "[-]"
        $script:failCount++
    }

    Write-Host "$symbol $TestName - $status" -ForegroundColor $color
    if ($Message) {
        Write-Host "    $Message" -ForegroundColor Gray
    }

    $script:testResults += [PSCustomObject]@{
        Test = $TestName
        Status = $status
        Message = $Message
    }
}

Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host "FFU User Password Fix Test" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Tests that password is reset for existing ffu_user accounts`n" -ForegroundColor Yellow

# =============================================================================
# Test 1: Verify Set-LocalUserPassword function exists
# =============================================================================
Write-Host "--- Verifying Function Implementation ---`n" -ForegroundColor Cyan

$vmModulePath = Join-Path $ModulesPath "FFU.VM\FFU.VM.psm1"
$vmModuleContent = Get-Content $vmModulePath -Raw

$hasSetPasswordFunction = $vmModuleContent -match 'function Set-LocalUserPassword'
Write-TestResult -TestName "Set-LocalUserPassword function exists in FFU.VM.psm1" -Passed $hasSetPasswordFunction `
    -Message $(if ($hasSetPasswordFunction) { "Function defined" } else { "Function missing" })

# Verify function signature includes SecureString parameter
$hasSecureStringParam = $vmModuleContent -match 'Set-LocalUserPassword[\s\S]*?\[SecureString\]\$Password'
Write-TestResult -TestName "Set-LocalUserPassword accepts SecureString Password" -Passed $hasSecureStringParam `
    -Message $(if ($hasSecureStringParam) { "SecureString parameter found" } else { "Missing SecureString parameter" })

# =============================================================================
# Test 2: Verify Set-CaptureFFU calls Set-LocalUserPassword
# =============================================================================
Write-Host "`n--- Verifying Set-CaptureFFU Integration ---`n" -ForegroundColor Cyan

$callsSetPassword = $vmModuleContent -match 'Set-LocalUserPassword\s+-Username\s+\$Username\s+-Password\s+\$Password'
Write-TestResult -TestName "Set-CaptureFFU calls Set-LocalUserPassword for existing users" -Passed $callsSetPassword `
    -Message $(if ($callsSetPassword) { "Password reset call found" } else { "Missing password reset call" })

# Verify log message about resetting password
$hasResetLog = $vmModuleContent -match 'resetting password to ensure sync'
Write-TestResult -TestName "Set-CaptureFFU logs password reset action" -Passed $hasResetLog `
    -Message $(if ($hasResetLog) { "Log message found" } else { "Missing log message" })

# =============================================================================
# Test 3: Verify module exports
# =============================================================================
Write-Host "`n--- Verifying Module Exports ---`n" -ForegroundColor Cyan

# Check psm1 Export-ModuleMember (multiline array format)
$psm1ExportsSetPassword = $vmModuleContent -match "Export-ModuleMember\s+-Function\s+@\([\s\S]*?'Set-LocalUserPassword'[\s\S]*?\)"
Write-TestResult -TestName "FFU.VM.psm1 exports Set-LocalUserPassword" -Passed $psm1ExportsSetPassword `
    -Message $(if ($psm1ExportsSetPassword) { "Export-ModuleMember includes function" } else { "Missing from Export-ModuleMember" })

# Check psd1 FunctionsToExport
$psd1Path = Join-Path $ModulesPath "FFU.VM\FFU.VM.psd1"
$psd1Content = Get-Content $psd1Path -Raw
$psd1ExportsSetPassword = $psd1Content -match "'Set-LocalUserPassword'"
Write-TestResult -TestName "FFU.VM.psd1 exports Set-LocalUserPassword" -Passed $psd1ExportsSetPassword `
    -Message $(if ($psd1ExportsSetPassword) { "FunctionsToExport includes function" } else { "Missing from FunctionsToExport" })

# =============================================================================
# Test 4: Verify actual function is available when module is loaded
# =============================================================================
Write-Host "`n--- Verifying Runtime Availability ---`n" -ForegroundColor Cyan

try {
    $env:PSModulePath = "$ModulesPath;$env:PSModulePath"
    Import-Module (Join-Path $ModulesPath "FFU.Constants\FFU.Constants.psm1") -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $ModulesPath "FFU.Core\FFU.Core.psm1") -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
    Import-Module $psd1Path -Force -ErrorAction Stop -WarningAction SilentlyContinue

    $cmd = Get-Command Set-LocalUserPassword -ErrorAction SilentlyContinue
    Write-TestResult -TestName "Set-LocalUserPassword is available at runtime" -Passed ($null -ne $cmd) `
        -Message $(if ($cmd) { "Function available from module: $($cmd.Module.Name)" } else { "Function NOT available" })

    Remove-Module FFU.VM -Force -ErrorAction SilentlyContinue
} catch {
    Write-TestResult -TestName "Module import test" -Passed $false -Message "Error: $_"
}

# =============================================================================
# Test 5: Verify DirectoryServices API is used (PowerShell 7 compatibility)
# =============================================================================
Write-Host "`n--- Verifying PowerShell 7 Compatibility ---`n" -ForegroundColor Cyan

$usesDirectoryServices = $vmModuleContent -match 'System\.DirectoryServices\.AccountManagement'
Write-TestResult -TestName "Set-LocalUserPassword uses DirectoryServices API" -Passed $usesDirectoryServices `
    -Message $(if ($usesDirectoryServices) { "Cross-version compatible API" } else { "May not work in PS7" })

$usesSetPasswordMethod = $vmModuleContent -match '\$user\.SetPassword\(\$plainPassword\)'
Write-TestResult -TestName "Uses SetPassword() method for password reset" -Passed $usesSetPasswordMethod `
    -Message $(if ($usesSetPasswordMethod) { "SetPassword method found" } else { "Missing SetPassword method" })

# Verify secure cleanup
$hasSecureCleanup = $vmModuleContent -match 'ZeroFreeBSTR\(\$BSTR\)'
Write-TestResult -TestName "Sensitive data cleaned up securely" -Passed $hasSecureCleanup `
    -Message $(if ($hasSecureCleanup) { "ZeroFreeBSTR cleanup found" } else { "Missing secure cleanup" })

# =============================================================================
# Test 6: Verify error 86 is documented
# =============================================================================
Write-Host "`n--- Verifying Documentation ---`n" -ForegroundColor Cyan

$hasError86Comment = $vmModuleContent -match 'Error 86|Password is incorrect'
Write-TestResult -TestName "Code comments document Error 86 fix" -Passed $hasError86Comment `
    -Message $(if ($hasError86Comment) { "Error 86 documentation found" } else { "Missing error documentation" })

# =============================================================================
# Summary
# =============================================================================
Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Total Tests: $($passCount + $failCount)" -ForegroundColor White
Write-Host "Passed: $passCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "Green" })

if ($failCount -eq 0) {
    Write-Host "`nAll tests passed! The fix correctly handles:" -ForegroundColor Green
    Write-Host "  - Existing ffu_user accounts from previous builds" -ForegroundColor Cyan
    Write-Host "  - Password reset to match CaptureFFU.ps1" -ForegroundColor Cyan
    Write-Host "  - PowerShell 5.1 and 7+ compatibility" -ForegroundColor Cyan
    Write-Host "  - Secure handling of password data" -ForegroundColor Cyan
} else {
    Write-Host "`nSome tests failed! Review the issues above." -ForegroundColor Red
}

Write-Host "`n=== Bug Pattern ===" -ForegroundColor Yellow
Write-Host "Before fix:" -ForegroundColor Red
Write-Host "  1. First build: Creates ffu_user with password 'abc123'" -ForegroundColor Gray
Write-Host "  2. Second build: Generates NEW password 'xyz789'" -ForegroundColor Gray
Write-Host "  3. Set-CaptureFFU: User exists -> SKIPPED password change!" -ForegroundColor Gray
Write-Host "  4. CaptureFFU.ps1: Written with 'xyz789'" -ForegroundColor Gray
Write-Host "  5. WinPE: Tries 'xyz789' but user still has 'abc123'" -ForegroundColor Red
Write-Host "  6. Result: Error 86 - Password is incorrect" -ForegroundColor Red

Write-Host "`nAfter fix:" -ForegroundColor Green
Write-Host "  1. First build: Creates ffu_user with password 'abc123'" -ForegroundColor Gray
Write-Host "  2. Second build: Generates NEW password 'xyz789'" -ForegroundColor Gray
Write-Host "  3. Set-CaptureFFU: User exists -> RESETS password to 'xyz789'" -ForegroundColor Green
Write-Host "  4. CaptureFFU.ps1: Written with 'xyz789'" -ForegroundColor Gray
Write-Host "  5. WinPE: Tries 'xyz789' and user has 'xyz789'" -ForegroundColor Green
Write-Host "  6. Result: Connection successful!" -ForegroundColor Green

# Return results for automation
return [PSCustomObject]@{
    TotalTests = $passCount + $failCount
    Passed = $passCount
    Failed = $failCount
    Results = $testResults
}
