<#
.SYNOPSIS
    Test script for Windows 11 24H2/25H2 Checkpoint Cumulative Update fix (error 0x80070228)

.DESCRIPTION
    Verifies that the direct CAB application fix is correctly implemented to prevent
    the DISM error 0x80070228 "Failed getting the download request" which occurs when
    UUP (Unified Update Platform) packages try to download content from Windows Update.

    Root Cause:
    - Windows 11 24H2/25H2 uses Checkpoint Cumulative Updates (UUP packages)
    - When DISM applies MSU files, the UpdateAgent tries to download additional content
    - Offline mounted images have no network access to Windows Update
    - DISM fails with error 0x80070228 "Failed getting the download request"

    The Fix:
    - Extract the MSU using expand.exe to get the CAB files
    - Apply the CAB files directly instead of the MSU
    - CAB files don't trigger the UpdateAgent mechanism
    - Completely bypasses the UUP download requirement

.NOTES
    Run this script to verify the checkpoint update fix is correctly implemented.

    References:
    - https://learn.microsoft.com/en-us/answers/questions/3855149/
#>

#Requires -Version 5.1

param(
    [Parameter(Mandatory = $false)]
    [string]$FFUDevelopmentPath = "C:\FFUDevelopment"
)

# Initialize test results
$script:TestResults = @{
    Passed = 0
    Failed = 0
    Skipped = 0
    Tests = @()
}

function Write-TestResult {
    param(
        [string]$TestName,
        [string]$Status,
        [string]$Message = ""
    )

    $color = switch ($Status) {
        'Passed' { 'Green' }
        'Failed' { 'Red' }
        'Skipped' { 'Yellow' }
        default { 'White' }
    }

    $script:TestResults[$Status]++
    $script:TestResults.Tests += [PSCustomObject]@{
        Name = $TestName
        Status = $Status
        Message = $Message
    }

    $statusSymbol = switch ($Status) {
        'Passed' { '[PASS]' }
        'Failed' { '[FAIL]' }
        'Skipped' { '[SKIP]' }
    }

    Write-Host "$statusSymbol $TestName" -ForegroundColor $color
    if ($Message) {
        Write-Host "       $Message" -ForegroundColor Gray
    }
}

function Test-Assertion {
    param(
        [string]$TestName,
        [scriptblock]$Test,
        [string]$FailMessage = "Assertion failed"
    )

    try {
        $result = & $Test
        if ($result) {
            Write-TestResult -TestName $TestName -Status 'Passed'
            return $true
        }
        else {
            Write-TestResult -TestName $TestName -Status 'Failed' -Message $FailMessage
            return $false
        }
    }
    catch {
        Write-TestResult -TestName $TestName -Status 'Failed' -Message $_.Exception.Message
        return $false
    }
}

# ============================================================================
# Setup
# ============================================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Checkpoint Cumulative Update Fix Tests" -ForegroundColor Cyan
Write-Host "Error 0x80070228 Prevention" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Determine paths
if (-not (Test-Path $FFUDevelopmentPath)) {
    $FFUDevelopmentPath = Join-Path (Split-Path $PSScriptRoot -Parent) "FFUDevelopment"
}

Write-Host "FFUDevelopment path: $FFUDevelopmentPath" -ForegroundColor Gray

# ============================================================================
# Test 1: FFU.Updates Module - Direct CAB Application
# ============================================================================
Write-Host "`n--- FFU.Updates Module - Direct CAB Fix ---" -ForegroundColor Yellow

$updatesModulePath = Join-Path $FFUDevelopmentPath "Modules\FFU.Updates\FFU.Updates.psm1"
if (Test-Path $updatesModulePath) {
    $content = Get-Content $updatesModulePath -Raw

    Test-Assertion "Has UUP checkpoint update documentation" {
        $content -match 'UUP.*Unified Update Platform'
    } "Should document UUP packages as root cause"

    Test-Assertion "References error 0x80070228" {
        $content -match '0x80070228'
    } "Should reference the error code being fixed"

    Test-Assertion "References Microsoft documentation" {
        $content -match 'learn\.microsoft\.com.*3855149'
    } "Should reference the Microsoft Q&A about this issue"

    Test-Assertion "Documents UpdateAgent bypass" {
        # Text spans two lines, so check both parts separately
        ($content -match "CAB files don't trigger") -and ($content -match "UpdateAgent mechanism")
    } "Should explain CAB files bypass UpdateAgent"

    Test-Assertion "Finds CAB files in extracted MSU" {
        $content -match 'Get-ChildItem.*extractPath.*\.cab'
    } "Should search for CAB files in extracted MSU"

    Test-Assertion "Excludes WSUSSCAN.cab" {
        $content -match 'WSUSSCAN'
    } "Should exclude WSUSSCAN.cab metadata file"

    Test-Assertion "Applies CAB directly" {
        $content -match 'Add-WindowsPackage.*cabFile\.FullName'
    } "Should apply CAB files directly"

    Test-Assertion "Logs CAB application" {
        $content -match 'Applying CAB.*Size:'
    } "Should log CAB file details"

    Test-Assertion "Has fallback to isolated MSU" {
        $content -match 'falling back to isolated MSU method'
    } "Should have fallback if no CAB files found"

    Test-Assertion "Handles already installed packages" {
        $content -match 'CBS_E_ALREADY_INSTALLED' -or $content -match '0x800f081e'
    } "Should gracefully handle already installed packages"

    Test-Assertion "Logs success via direct CAB method" {
        $content -match 'applied successfully via direct CAB method'
    } "Should log success with method used"

    Test-Assertion "Cleans up isolated directory in finally block" {
        $content -match 'finally\s*\{[^}]*isolatedApplyPath'
    } "Should use finally block for cleanup"
}
else {
    Write-TestResult "FFU.Updates module tests" -Status 'Skipped' -Message "File not found: $updatesModulePath"
}

# ============================================================================
# Summary
# ============================================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Passed:  $($script:TestResults.Passed)" -ForegroundColor Green
Write-Host "Failed:  $($script:TestResults.Failed)" -ForegroundColor Red
Write-Host "Skipped: $($script:TestResults.Skipped)" -ForegroundColor Yellow
Write-Host "Total:   $($script:TestResults.Tests.Count)" -ForegroundColor White

$overallResult = if ($script:TestResults.Failed -eq 0) { "PASS" } else { "FAIL" }
$overallColor = if ($script:TestResults.Failed -eq 0) { "Green" } else { "Red" }
Write-Host "`nOverall: $overallResult" -ForegroundColor $overallColor

# Show fix summary
Write-Host "`n--- Checkpoint Update Fix Summary ---" -ForegroundColor Yellow
Write-Host @"
This test validates the fix for DISM error 0x80070228.

ERROR CAUSE (Windows 11 24H2/25H2):
- UUP (Unified Update Platform) packages like KB5043080 checkpoint updates
- When DISM applies MSU files, the UpdateAgent tries to download content
- Offline mounted images have no network access to Windows Update
- DISM fails with "Failed getting the download request" (0x80070228)

THE FIX (Direct CAB Application):
- Extract MSU using expand.exe to get CAB files
- Apply CAB files directly instead of the MSU
- CAB files don't trigger the UpdateAgent mechanism
- Completely bypasses the UUP download requirement

IMPLEMENTATION:
1. Expand MSU to temporary directory (already done for unattend.xml)
2. Find CAB files (excluding WSUSSCAN.cab metadata)
3. Apply each CAB directly with Add-WindowsPackage
4. Fall back to isolated MSU if no CAB files found

WHY THIS WORKS:
- MSU files are containers that include CAB + WSUSSCAN.cab + metadata
- When DISM processes MSU, it uses UpdateAgent which may need network
- CAB files are pure package content - no UpdateAgent involvement
- Direct CAB application is equivalent but bypasses UUP mechanism

References:
- https://learn.microsoft.com/en-us/answers/questions/3855149/
"@ -ForegroundColor Gray

# Exit with appropriate code
if ($script:TestResults.Failed -gt 0) {
    Write-Host "`nFailed tests:" -ForegroundColor Red
    $script:TestResults.Tests | Where-Object Status -eq 'Failed' | ForEach-Object {
        Write-Host "  - $($_.Name): $($_.Message)" -ForegroundColor Red
    }
    exit 1
}
else {
    Write-Host "`nAll tests passed!" -ForegroundColor Green
    exit 0
}
