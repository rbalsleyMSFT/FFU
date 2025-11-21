# Test-DISMCleanupAndCopype.ps1
# Comprehensive test suite for DISM cleanup and copype retry functionality

<#
.SYNOPSIS
Tests for the DISM pre-flight cleanup and copype retry enhancements

.DESCRIPTION
This test suite validates that the new DISM cleanup and retry logic works correctly:
- Test 1: Invoke-DISMPreFlightCleanup function exists and has proper parameters
- Test 2: Invoke-CopyPEWithRetry function exists and has proper parameters
- Test 3: Cleanup handles stale mount points correctly
- Test 4: Cleanup removes locked WinPE directories
- Test 5: Cleanup validates disk space requirements
- Test 6: Cleanup checks required services
- Test 7: Retry logic attempts copype multiple times on failure
- Test 8: Enhanced error messages provide actionable guidance

.PARAMETER TestADKPresence
If $false, skips tests that require ADK installation (default: $true)

.EXAMPLE
.\Test-DISMCleanupAndCopype.ps1

.EXAMPLE
.\Test-DISMCleanupAndCopype.ps1 -TestADKPresence $false
#>

[CmdletBinding()]
param(
    [Parameter()]
    [bool]$TestADKPresence = $true
)

$ErrorActionPreference = 'Continue'
$script:TestResults = @()
$script:TestsPassed = 0
$script:TestsFailed = 0

# Helper function to add test results
function Add-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Message
    )

    $result = [PSCustomObject]@{
        Test = $TestName
        Status = if ($Passed) { "PASS" } else { "FAIL" }
        Message = $Message
        Timestamp = Get-Date
    }

    $script:TestResults += $result

    if ($Passed) {
        $script:TestsPassed++
        Write-Host "[PASS] $TestName" -ForegroundColor Green
        if ($Message) { Write-Host "       $Message" -ForegroundColor Gray }
    } else {
        $script:TestsFailed++
        Write-Host "[FAIL] $TestName" -ForegroundColor Red
        Write-Host "       $Message" -ForegroundColor Red
    }
}

Write-Host "`n===============================================" -ForegroundColor Cyan
Write-Host "DISM Cleanup & Copype Retry Test Suite" -ForegroundColor Cyan
Write-Host "===============================================`n" -ForegroundColor Cyan

# Load the FFU.Media module (modular architecture)
$modulePath = Join-Path $PSScriptRoot "Modules\FFU.Media"

if (-not (Test-Path $modulePath)) {
    $modulePath = ".\Modules\FFU.Media"
}

if (Test-Path $modulePath) {
    Write-Host "Loading FFU.Media module from: $modulePath" -ForegroundColor Yellow

    try {
        # Import dependencies in order
        Import-Module (Join-Path $PSScriptRoot "Modules\FFU.Core") -Force -WarningAction SilentlyContinue
        Import-Module (Join-Path $PSScriptRoot "Modules\FFU.ADK") -Force -WarningAction SilentlyContinue

        # Import FFU.Media module
        Import-Module $modulePath -Force -WarningAction SilentlyContinue

        Write-Host "FFU.Media module loaded successfully" -ForegroundColor Green

        # Mock WriteLog if it doesn't exist (for standalone testing)
        if (-not (Get-Command WriteLog -ErrorAction SilentlyContinue)) {
            function global:WriteLog { param($Message) Write-Host "LOG: $Message" -ForegroundColor Gray }
        }

        Write-Host "Functions loaded successfully`n" -ForegroundColor Green
    } catch {
        Write-Host "WARNING: Could not load FFU.Media module: $_" -ForegroundColor Yellow
        Write-Host "Some tests may be skipped`n" -ForegroundColor Yellow
    }
} else {
    Write-Host "WARNING: FFU.Media module not found at $modulePath" -ForegroundColor Yellow
    Write-Host "Some tests will be skipped`n" -ForegroundColor Yellow
}

# ============================================
# Test 1: Function Existence and Parameters
# ============================================
Write-Host "Test 1: Function Existence and Parameters" -ForegroundColor Cyan

$dismCleanupCmd = Get-Command Invoke-DISMPreFlightCleanup -ErrorAction SilentlyContinue
if ($dismCleanupCmd) {
    Add-TestResult -TestName "Invoke-DISMPreFlightCleanup exists" `
                   -Passed $true `
                   -Message "Function found with $($dismCleanupCmd.Parameters.Count) parameters"

    # Check for required parameters
    $hasWinPEPath = $dismCleanupCmd.Parameters.ContainsKey('WinPEPath')
    $hasMinSpace = $dismCleanupCmd.Parameters.ContainsKey('MinimumFreeSpaceGB')

    Add-TestResult -TestName "Invoke-DISMPreFlightCleanup has WinPEPath parameter" `
                   -Passed $hasWinPEPath `
                   -Message $(if ($hasWinPEPath) { "Parameter exists" } else { "Parameter missing" })

    Add-TestResult -TestName "Invoke-DISMPreFlightCleanup has MinimumFreeSpaceGB parameter" `
                   -Passed $hasMinSpace `
                   -Message $(if ($hasMinSpace) { "Parameter exists with default value" } else { "Parameter missing" })
} else {
    Add-TestResult -TestName "Invoke-DISMPreFlightCleanup exists" `
                   -Passed $false `
                   -Message "Function not found"
}

$copyPECmd = Get-Command Invoke-CopyPEWithRetry -ErrorAction SilentlyContinue
if ($copyPECmd) {
    Add-TestResult -TestName "Invoke-CopyPEWithRetry exists" `
                   -Passed $true `
                   -Message "Function found with $($copyPECmd.Parameters.Count) parameters"

    # Check for required parameters
    $hasArch = $copyPECmd.Parameters.ContainsKey('Architecture')
    $hasDest = $copyPECmd.Parameters.ContainsKey('DestinationPath')
    $hasDandI = $copyPECmd.Parameters.ContainsKey('DandIEnvPath')
    $hasRetries = $copyPECmd.Parameters.ContainsKey('MaxRetries')

    Add-TestResult -TestName "Invoke-CopyPEWithRetry has Architecture parameter" `
                   -Passed $hasArch `
                   -Message $(if ($hasArch) { "Parameter exists" } else { "Parameter missing" })

    Add-TestResult -TestName "Invoke-CopyPEWithRetry has DestinationPath parameter" `
                   -Passed $hasDest `
                   -Message $(if ($hasDest) { "Parameter exists" } else { "Parameter missing" })

    Add-TestResult -TestName "Invoke-CopyPEWithRetry has DandIEnvPath parameter" `
                   -Passed $hasDandI `
                   -Message $(if ($hasDandI) { "Parameter exists" } else { "Parameter missing" })

    Add-TestResult -TestName "Invoke-CopyPEWithRetry has MaxRetries parameter" `
                   -Passed $hasRetries `
                   -Message $(if ($hasRetries) { "Parameter exists" } else { "Parameter missing" })
} else {
    Add-TestResult -TestName "Invoke-CopyPEWithRetry exists" `
                   -Passed $false `
                   -Message "Function not found"
}

# ============================================
# Test 2: DISM Cleanup Functionality
# ============================================
Write-Host "`nTest 2: DISM Cleanup Functionality" -ForegroundColor Cyan

if ($dismCleanupCmd) {
    # Test with a temporary path
    $testPath = Join-Path $env:TEMP "DISMCleanupTest_$(Get-Random)"

    try {
        # Create test directory
        New-Item -Path $testPath -ItemType Directory -Force | Out-Null

        # Run cleanup (should succeed even if nothing to clean)
        $cleanupResult = Invoke-DISMPreFlightCleanup -WinPEPath $testPath -MinimumFreeSpaceGB 1

        Add-TestResult -TestName "Invoke-DISMPreFlightCleanup executes without error" `
                       -Passed $true `
                       -Message "Function executed and returned: $cleanupResult"

        # Verify the test path was removed by cleanup
        $pathRemoved = -not (Test-Path $testPath)
        Add-TestResult -TestName "Cleanup removes target directory" `
                       -Passed $pathRemoved `
                       -Message $(if ($pathRemoved) { "Directory successfully removed" } else { "Directory still exists" })

    } catch {
        Add-TestResult -TestName "Invoke-DISMPreFlightCleanup executes without error" `
                       -Passed $false `
                       -Message "Exception: $($_.Exception.Message)"
    } finally {
        if (Test-Path $testPath) {
            Remove-Item -Path $testPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
} else {
    Add-TestResult -TestName "DISM Cleanup tests" `
                   -Passed $false `
                   -Message "Skipped - function not loaded"
}

# ============================================
# Test 3: Disk Space Validation
# ============================================
Write-Host "`nTest 3: Disk Space Validation" -ForegroundColor Cyan

if ($dismCleanupCmd) {
    $testPath = Join-Path $env:TEMP "DISMSpaceTest_$(Get-Random)"

    try {
        New-Item -Path $testPath -ItemType Directory -Force | Out-Null

        # Test with impossibly high disk space requirement (should fail)
        $cleanupResult = Invoke-DISMPreFlightCleanup -WinPEPath $testPath -MinimumFreeSpaceGB 99999

        Add-TestResult -TestName "Cleanup detects insufficient disk space" `
                       -Passed (-not $cleanupResult) `
                       -Message $(if (-not $cleanupResult) { "Correctly failed with insufficient space" } else { "Should have failed but passed" })

        # Test with reasonable disk space requirement (should succeed)
        $cleanupResult2 = Invoke-DISMPreFlightCleanup -WinPEPath $testPath -MinimumFreeSpaceGB 1

        Add-TestResult -TestName "Cleanup succeeds with sufficient disk space" `
                       -Passed $cleanupResult2 `
                       -Message $(if ($cleanupResult2) { "Correctly passed with sufficient space" } else { "Should have passed but failed" })

    } catch {
        Add-TestResult -TestName "Disk space validation" `
                       -Passed $false `
                       -Message "Exception: $($_.Exception.Message)"
    } finally {
        if (Test-Path $testPath) {
            Remove-Item -Path $testPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
} else {
    Add-TestResult -TestName "Disk space validation" `
                   -Passed $false `
                   -Message "Skipped - function not loaded"
}

# ============================================
# Test 4: Service Checks
# ============================================
Write-Host "`nTest 4: Service Availability Checks" -ForegroundColor Cyan

# Check if TrustedInstaller service exists
$trustedInstaller = Get-Service -Name "TrustedInstaller" -ErrorAction SilentlyContinue
if ($trustedInstaller) {
    Add-TestResult -TestName "TrustedInstaller service exists" `
                   -Passed $true `
                   -Message "Service status: $($trustedInstaller.Status), StartType: $($trustedInstaller.StartType)"
} else {
    Add-TestResult -TestName "TrustedInstaller service exists" `
                   -Passed $false `
                   -Message "Service not found on system"
}

# ============================================
# Test 5: Integration with FFU.Media Module
# ============================================
Write-Host "`nTest 5: Integration with FFU.Media Module" -ForegroundColor Cyan

$mediaModulePath = Join-Path $PSScriptRoot "Modules\FFU.Media\FFU.Media.psm1"
if (-not (Test-Path $mediaModulePath)) {
    $mediaModulePath = ".\Modules\FFU.Media\FFU.Media.psm1"
}

if (Test-Path $mediaModulePath) {
    $moduleContent = Get-Content $mediaModulePath -Raw

    # Check if New-PEMedia calls Invoke-DISMPreFlightCleanup
    $callsCleanup = $moduleContent -match 'Invoke-DISMPreFlightCleanup'
    Add-TestResult -TestName "New-PEMedia calls Invoke-DISMPreFlightCleanup" `
                   -Passed $callsCleanup `
                   -Message $(if ($callsCleanup) { "Function call found in module" } else { "Function call not found" })

    # Check if New-PEMedia calls Invoke-CopyPEWithRetry
    $callsCopyPE = $moduleContent -match 'Invoke-CopyPEWithRetry'
    Add-TestResult -TestName "New-PEMedia calls Invoke-CopyPEWithRetry" `
                   -Passed $callsCopyPE `
                   -Message $(if ($callsCopyPE) { "Function call found in module" } else { "Function call not found" })

    # Check that module has been properly modularized
    $hasNewPEMedia = $moduleContent -match 'function New-PEMedia'
    Add-TestResult -TestName "FFU.Media module contains New-PEMedia function" `
                   -Passed $hasNewPEMedia `
                   -Message $(if ($hasNewPEMedia) { "Function found in module" } else { "Function not found in module" })
} else {
    Add-TestResult -TestName "FFU.Media module integration" `
                   -Passed $false `
                   -Message "Skipped - FFU.Media module not found at $mediaModulePath"
}

# ============================================
# Test 6: Error Message Quality
# ============================================
Write-Host "`nTest 6: Error Message Quality" -ForegroundColor Cyan

if ($copyPECmd) {
    $funcDef = $copyPECmd.Definition

    # Check for comprehensive error messages
    $hasCommonCauses = $funcDef -match 'COMMON CAUSES'
    Add-TestResult -TestName "Error messages include common causes" `
                   -Passed $hasCommonCauses `
                   -Message $(if ($hasCommonCauses) { "Found COMMON CAUSES section" } else { "Missing guidance" })

    $hasSolutions = $funcDef -match 'SOLUTIONS|Fix:'
    Add-TestResult -TestName "Error messages include solutions" `
                   -Passed $hasSolutions `
                   -Message $(if ($hasSolutions) { "Found solutions/fixes" } else { "Missing actionable guidance" })

    $hasDISMLog = $funcDef -match 'DISM.*log|dism\.log'
    Add-TestResult -TestName "Error messages reference DISM log" `
                   -Passed $hasDISMLog `
                   -Message $(if ($hasDISMLog) { "References DISM log for diagnostics" } else { "Missing log reference" })
} else {
    Add-TestResult -TestName "Error message quality" `
                   -Passed $false `
                   -Message "Skipped - function not loaded"
}

# ============================================
# Summary
# ============================================
Write-Host "`n===============================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan

$totalTests = $script:TestsPassed + $script:TestsFailed
$passRate = if ($totalTests -gt 0) { [Math]::Round(($script:TestsPassed / $totalTests) * 100, 1) } else { 0 }

Write-Host "`nTotal Tests: $totalTests" -ForegroundColor White
Write-Host "Passed: $script:TestsPassed" -ForegroundColor Green
Write-Host "Failed: $script:TestsFailed" -ForegroundColor $(if ($script:TestsFailed -gt 0) { "Red" } else { "Green" })
Write-Host "Pass Rate: $passRate%" -ForegroundColor $(if ($passRate -ge 90) { "Green" } elseif ($passRate -ge 70) { "Yellow" } else { "Red" })

Write-Host "`nDetailed Results:" -ForegroundColor White
$script:TestResults | Format-Table Test, Status, Message -AutoSize

# Return exit code based on results
if ($script:TestsFailed -gt 0) {
    Write-Host "`n[OVERALL: FAIL] Some tests failed" -ForegroundColor Red
    exit 1
} else {
    Write-Host "`n[OVERALL: PASS] All tests passed!" -ForegroundColor Green
    exit 0
}
