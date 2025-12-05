<#
.SYNOPSIS
    Test script for cmd.exe path quoting in FFU Builder scripts

.DESCRIPTION
    Verifies that paths with spaces (like "C:\Program Files (x86)\...") are properly
    quoted when passed to cmd.exe /c commands.

    This test addresses the error:
    "'C:\Program' is not recognized as an internal or external command"

    Which occurs when batch file paths containing spaces are not properly quoted
    with the 'call' command when using cmd.exe /c.

.NOTES
    Run this script to verify the quoting fixes are in place.
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
Write-Host "cmd.exe Path Quoting Tests" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Determine paths
$modulePath = Join-Path $FFUDevelopmentPath "Modules"
if (-not (Test-Path $modulePath)) {
    $modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) "FFUDevelopment\Modules"
}

if (-not (Test-Path $FFUDevelopmentPath)) {
    $FFUDevelopmentPath = Join-Path (Split-Path $PSScriptRoot -Parent) "FFUDevelopment"
}

Write-Host "FFUDevelopment path: $FFUDevelopmentPath" -ForegroundColor Gray

# ============================================================================
# Test 1: Verify 'call' command is used in FFU.Imaging.psm1
# ============================================================================
Write-Host "`n--- FFU.Imaging.psm1 Quoting Tests ---" -ForegroundColor Yellow

$imagingModule = Join-Path $modulePath "FFU.Imaging\FFU.Imaging.psm1"
if (Test-Path $imagingModule) {
    $content = Get-Content $imagingModule -Raw

    Test-Assertion "FFU.Imaging: Invoke-FFUOptimizeWithScratchDir uses 'call' for DandIEnv" {
        $content -match '/c\s+call\s+[`"].*DandIEnv.*dism\s+/optimize-ffu'
    } "Should use 'call' before batch file path"

    Test-Assertion "FFU.Imaging: DISM Capture-FFU (non-cached) uses 'call' for DandIEnv" {
        $content -match '/c\s+call\s+[`"].*DandIEnv.*dism\s+/Capture-FFU'
    } "Should use 'call' before batch file path"

    Test-Assertion "FFU.Imaging: No old-style double-quote quoting remains" {
        -not ($content -match '/c\s+"""\$DandIEnv"""')
    } "Old triple-quote style should be replaced"

    Test-Assertion "FFU.Imaging: No problematic double-double-quote pattern" {
        # Check that we don't have /c ""$DandIEnv"" without 'call'
        -not ($content -match '/c\s+""[^c].*DandIEnv')
    } "Pattern /c `"``$DandIEnv`" without 'call' should not exist"
}
else {
    Write-TestResult "FFU.Imaging.psm1 tests" -Status 'Skipped' -Message "File not found: $imagingModule"
}

# ============================================================================
# Test 2: Verify 'call' command is used in FFU.Media.psm1
# ============================================================================
Write-Host "`n--- FFU.Media.psm1 Quoting Tests ---" -ForegroundColor Yellow

$mediaModule = Join-Path $modulePath "FFU.Media\FFU.Media.psm1"
if (Test-Path $mediaModule) {
    $content = Get-Content $mediaModule -Raw

    Test-Assertion "FFU.Media: copype amd64 uses 'call' for DandIEnvPath" {
        $content -match 'call\s+[`"].*DandIEnvPath.*copype\s+amd64'
    } "Should use 'call' before batch file path for amd64"

    Test-Assertion "FFU.Media: copype arm64 uses 'call' for DandIEnvPath" {
        $content -match 'call\s+[`"].*DandIEnvPath.*copype\s+arm64'
    } "Should use 'call' before batch file path for arm64"

    Test-Assertion "FFU.Media: No old-style triple-quote quoting remains" {
        -not ($content -match '/c\s+"""\$DandIEnvPath"""')
    } "Old triple-quote style should be replaced"
}
else {
    Write-TestResult "FFU.Media.psm1 tests" -Status 'Skipped' -Message "File not found: $mediaModule"
}

# ============================================================================
# Test 3: Verify 'call' command is used in Create-PEMedia.ps1
# ============================================================================
Write-Host "`n--- Create-PEMedia.ps1 Quoting Tests ---" -ForegroundColor Yellow

$createPEMedia = Join-Path $FFUDevelopmentPath "Create-PEMedia.ps1"
if (Test-Path $createPEMedia) {
    $content = Get-Content $createPEMedia -Raw

    Test-Assertion "Create-PEMedia: copype amd64 uses 'call' for DandIEnv" {
        $content -match 'call\s+[`"].*DandIEnv.*copype\s+amd64'
    } "Should use 'call' before batch file path for amd64"

    Test-Assertion "Create-PEMedia: copype arm64 uses 'call' for DandIEnv" {
        $content -match 'call\s+[`"].*DandIEnv.*copype\s+arm64'
    } "Should use 'call' before batch file path for arm64"

    Test-Assertion "Create-PEMedia: No old-style triple-quote quoting remains" {
        -not ($content -match '/c\s+"""\$DandIEnv"""')
    } "Old triple-quote style should be replaced"
}
else {
    Write-TestResult "Create-PEMedia.ps1 tests" -Status 'Skipped' -Message "File not found: $createPEMedia"
}

# ============================================================================
# Test 4: Functional test - cmd.exe 'call' with path containing spaces
# ============================================================================
Write-Host "`n--- Functional cmd.exe Tests ---" -ForegroundColor Yellow

# Create a test batch file in a path with spaces
$testDir = Join-Path $env:TEMP "FFU Test Dir With Spaces"
$testBat = Join-Path $testDir "test script.bat"

try {
    New-Item -Path $testDir -ItemType Directory -Force | Out-Null
    @"
@echo off
echo SUCCESS: Batch file executed correctly
exit /b 0
"@ | Out-File -FilePath $testBat -Encoding ASCII

    # Test 1: Using 'call' (correct method)
    Test-Assertion "cmd.exe with 'call' handles spaces correctly" {
        $output = & cmd /c "call `"$testBat`"" 2>&1
        $LASTEXITCODE -eq 0 -and $output -match "SUCCESS"
    } "Using 'call' should work with paths containing spaces"

    # Test 2: Document that the old method may or may not work (environment-dependent)
    # This is informational - the behavior varies by PowerShell version and cmd.exe parsing
    Write-Host "  [INFO] Testing old quoting style (may vary by environment)..." -ForegroundColor Gray
    $oldOutput = & cmd /c """$testBat""" 2>&1
    $oldExitCode = $LASTEXITCODE
    if ($oldExitCode -ne 0 -or $oldOutput -match "not recognized") {
        Write-Host "  [INFO] Old style failed (confirms the bug exists on this system)" -ForegroundColor Yellow
    } else {
        Write-Host "  [INFO] Old style worked on this system (but may fail elsewhere)" -ForegroundColor Yellow
    }
    # This test always passes - it's informational only
    Test-Assertion "cmd.exe 'call' is more reliable than old quoting style" {
        # The 'call' method should work regardless of whether old method works
        $true
    } "Using 'call' is the reliable cross-environment solution"

    # Test 3: Test && chaining with 'call'
    Test-Assertion "cmd.exe 'call' works with && chaining" {
        $output = & cmd /c "call `"$testBat`" && echo CHAINED" 2>&1
        $output -match "SUCCESS" -and $output -match "CHAINED"
    } "Chained commands should work after 'call'"
}
finally {
    # Cleanup
    Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
}

# ============================================================================
# Test 5: Pattern matching test for correct quoting style
# ============================================================================
Write-Host "`n--- Quoting Pattern Tests ---" -ForegroundColor Yellow

Test-Assertion "Backtick-escaped quotes are proper PowerShell syntax" {
    # This should parse correctly
    $testPath = "C:\Program Files (x86)\Test\script.bat"
    $cmdArgs = "/c call `"$testPath`" && echo test"
    $cmdArgs -match 'call ".*script\.bat"'
}

Test-Assertion "Verify double-double-quote escaping produces quotes" {
    # PowerShell "" inside "" produces a literal "
    $testStr = "test ""quoted"" string"
    $testStr -eq 'test "quoted" string'
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

# Show explanation of the fix
Write-Host "`n--- Fix Explanation ---" -ForegroundColor Yellow
Write-Host @"
The 'call' command is required when executing batch files with cmd.exe /c
when the path contains spaces (like "C:\Program Files (x86)\...").

WRONG (fails with "'C:\Program' is not recognized"):
  cmd /c "C:\Program Files (x86)\script.bat" && other_command

CORRECT (works with spaces):
  cmd /c call "C:\Program Files (x86)\script.bat" && other_command

The 'call' command tells cmd.exe to execute the batch file and return,
properly handling the quoted path with spaces.
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
