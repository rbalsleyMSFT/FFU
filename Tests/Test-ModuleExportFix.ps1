<#
.SYNOPSIS
    Test script for module export fix - verifies Remove-SensitiveCaptureMedia is exported

.DESCRIPTION
    Validates that the FFU.VM module correctly exports all required functions,
    specifically the credential security functions that were missing from Export-ModuleMember.

    Root Cause (Fixed):
    - Functions were defined in FFU.VM.psm1 and listed in FFU.VM.psd1 FunctionsToExport
    - But NOT included in the Export-ModuleMember statement
    - Export-ModuleMember explicitly restricts exports, hiding unlisted functions

.NOTES
    Run this script to verify the module export fix is correctly implemented.
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
Write-Host "Module Export Fix Tests" -ForegroundColor Cyan
Write-Host "FFU.VM Function Export Verification" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Determine paths
if (-not (Test-Path $FFUDevelopmentPath)) {
    $FFUDevelopmentPath = Join-Path (Split-Path $PSScriptRoot -Parent) "FFUDevelopment"
}

$modulesPath = Join-Path $FFUDevelopmentPath "Modules"
Write-Host "Modules path: $modulesPath" -ForegroundColor Gray

# ============================================================================
# Test 1: Source Code Verification
# ============================================================================
Write-Host "`n--- Source Code Verification ---" -ForegroundColor Yellow

$vmModulePath = Join-Path $modulesPath "FFU.VM\FFU.VM.psm1"
if (Test-Path $vmModulePath) {
    $content = Get-Content $vmModulePath -Raw

    Test-Assertion "Remove-SensitiveCaptureMedia function exists" {
        $content -match 'function Remove-SensitiveCaptureMedia'
    } "Function definition not found in FFU.VM.psm1"

    Test-Assertion "Set-LocalUserAccountExpiry function exists" {
        $content -match 'function Set-LocalUserAccountExpiry'
    } "Function definition not found in FFU.VM.psm1"

    Test-Assertion "Remove-SensitiveCaptureMedia in Export-ModuleMember" {
        $content -match "Export-ModuleMember[\s\S]*'Remove-SensitiveCaptureMedia'"
    } "Function not in Export-ModuleMember list"

    Test-Assertion "Set-LocalUserAccountExpiry in Export-ModuleMember" {
        $content -match "Export-ModuleMember[\s\S]*'Set-LocalUserAccountExpiry'"
    } "Function not in Export-ModuleMember list"
}
else {
    Write-TestResult "FFU.VM.psm1 source tests" -Status 'Skipped' -Message "File not found: $vmModulePath"
}

# ============================================================================
# Test 2: Module Manifest Verification
# ============================================================================
Write-Host "`n--- Module Manifest Verification ---" -ForegroundColor Yellow

$vmManifestPath = Join-Path $modulesPath "FFU.VM\FFU.VM.psd1"
if (Test-Path $vmManifestPath) {
    $content = Get-Content $vmManifestPath -Raw

    Test-Assertion "Remove-SensitiveCaptureMedia in FunctionsToExport" {
        $content -match "'Remove-SensitiveCaptureMedia'"
    } "Function not in manifest FunctionsToExport"

    Test-Assertion "Set-LocalUserAccountExpiry in FunctionsToExport" {
        $content -match "'Set-LocalUserAccountExpiry'"
    } "Function not in manifest FunctionsToExport"
}
else {
    Write-TestResult "FFU.VM.psd1 manifest tests" -Status 'Skipped' -Message "File not found: $vmManifestPath"
}

# ============================================================================
# Test 3: Module Import and Export Verification
# ============================================================================
Write-Host "`n--- Module Import Verification ---" -ForegroundColor Yellow

try {
    # Add modules path to PSModulePath
    if ($env:PSModulePath -notlike "*$modulesPath*") {
        $env:PSModulePath = "$modulesPath;$env:PSModulePath"
    }

    # Import FFU.Core first (dependency)
    Import-Module FFU.Core -Force -ErrorAction Stop
    Write-TestResult -TestName "FFU.Core module imports" -Status 'Passed'

    # Import FFU.VM
    Import-Module FFU.VM -Force -ErrorAction Stop
    Write-TestResult -TestName "FFU.VM module imports" -Status 'Passed'

    # Get exported commands
    $exportedCommands = Get-Command -Module FFU.VM | Select-Object -ExpandProperty Name

    Test-Assertion "Remove-SensitiveCaptureMedia is exported" {
        $exportedCommands -contains 'Remove-SensitiveCaptureMedia'
    } "Function not in exported commands: $($exportedCommands -join ', ')"

    Test-Assertion "Set-LocalUserAccountExpiry is exported" {
        $exportedCommands -contains 'Set-LocalUserAccountExpiry'
    } "Function not in exported commands: $($exportedCommands -join ', ')"

    # Verify all expected functions are exported
    $expectedFunctions = @(
        'Get-LocalUserAccount',
        'New-LocalUserAccount',
        'Remove-LocalUserAccount',
        'Set-LocalUserPassword',
        'Set-LocalUserAccountExpiry',
        'New-FFUVM',
        'Remove-FFUVM',
        'Get-FFUEnvironment',
        'Set-CaptureFFU',
        'Remove-FFUUserShare',
        'Update-CaptureFFUScript',
        'Remove-SensitiveCaptureMedia'
    )

    Test-Assertion "All 12 expected functions are exported" {
        $missingFunctions = $expectedFunctions | Where-Object { $exportedCommands -notcontains $_ }
        $missingFunctions.Count -eq 0
    } "Missing functions: $($missingFunctions -join ', ')"

    # List all exported functions for reference
    Write-Host "`n  Exported functions from FFU.VM:" -ForegroundColor Gray
    $exportedCommands | Sort-Object | ForEach-Object { Write-Host "    - $_" -ForegroundColor Gray }
}
catch {
    Write-TestResult -TestName "Module import" -Status 'Failed' -Message $_.Exception.Message
}

# ============================================================================
# Test 4: Function Callable Verification
# ============================================================================
Write-Host "`n--- Function Callable Verification ---" -ForegroundColor Yellow

Test-Assertion "Remove-SensitiveCaptureMedia is callable (Get-Command)" {
    $cmd = Get-Command Remove-SensitiveCaptureMedia -ErrorAction SilentlyContinue
    $null -ne $cmd
} "Get-Command failed to find Remove-SensitiveCaptureMedia"

Test-Assertion "Set-LocalUserAccountExpiry is callable (Get-Command)" {
    $cmd = Get-Command Set-LocalUserAccountExpiry -ErrorAction SilentlyContinue
    $null -ne $cmd
} "Get-Command failed to find Set-LocalUserAccountExpiry"

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
Write-Host "`n--- Module Export Fix Summary ---" -ForegroundColor Yellow
Write-Host @"
This test validates the fix for missing function exports.

ERROR CAUSE:
- Functions defined in FFU.VM.psm1 and listed in FFU.VM.psd1 FunctionsToExport
- BUT NOT included in Export-ModuleMember statement in .psm1
- Export-ModuleMember explicitly restricts what's exported
- Functions not listed become private to the module

THE FIX:
- Added 'Set-LocalUserAccountExpiry' to Export-ModuleMember
- Added 'Remove-SensitiveCaptureMedia' to Export-ModuleMember
- Both manifest and Export-ModuleMember now synchronized

PATTERN TO FOLLOW:
When adding new functions to a module:
1. Define function in .psm1
2. Add to FunctionsToExport in .psd1 manifest
3. Add to Export-ModuleMember in .psm1 (CRITICAL!)
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
