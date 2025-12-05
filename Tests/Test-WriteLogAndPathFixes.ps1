<#
.SYNOPSIS
    Test script for WriteLog null/empty handling and path validation fixes

.DESCRIPTION
    Verifies that:
    1. WriteLog function handles null/empty values gracefully without throwing
    2. Get-ErrorMessage helper function properly extracts error messages
    3. Invoke-Process temp file cleanup validates paths before Remove-Item
    4. All WriteLog $_ calls have been updated to use proper error extraction

    These fixes address:
    - "Cannot bind argument to parameter 'LogText' because it is an empty string"
    - "Value cannot be null. (Parameter 'The provided Path argument was null or an empty collection.')"

.NOTES
    Run this script to verify the WriteLog and path validation fixes are in place.
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
Write-Host "WriteLog & Path Validation Fixes Tests" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Determine paths
$modulePath = Join-Path $FFUDevelopmentPath "Modules"
if (-not (Test-Path $modulePath)) {
    $modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) "FFUDevelopment\Modules"
}

$ffuCommonPath = Join-Path $FFUDevelopmentPath "FFU.Common"
if (-not (Test-Path $ffuCommonPath)) {
    $ffuCommonPath = Join-Path (Split-Path $PSScriptRoot -Parent) "FFUDevelopment\FFU.Common"
}

if (-not (Test-Path $FFUDevelopmentPath)) {
    $FFUDevelopmentPath = Join-Path (Split-Path $PSScriptRoot -Parent) "FFUDevelopment"
}

Write-Host "FFUDevelopment path: $FFUDevelopmentPath" -ForegroundColor Gray

# ============================================================================
# Test 1: FFU.Common.Core WriteLog Function
# ============================================================================
Write-Host "`n--- FFU.Common.Core WriteLog Tests ---" -ForegroundColor Yellow

$coreModule = Join-Path $ffuCommonPath "FFU.Common.Core.psm1"
if (Test-Path $coreModule) {
    $content = Get-Content $coreModule -Raw

    Test-Assertion "WriteLog has [AllowNull()] attribute" {
        $content -match '\[AllowNull\(\)\]'
    } "WriteLog should have [AllowNull()] attribute"

    Test-Assertion "WriteLog has [AllowEmptyString()] attribute" {
        $content -match '\[AllowEmptyString\(\)\]'
    } "WriteLog should have [AllowEmptyString()] attribute"

    Test-Assertion "WriteLog has null/empty check with early return" {
        $content -match 'if\s*\(\[string\]::IsNullOrWhiteSpace\(\$LogText\)\)'
    } "WriteLog should check for null/empty and return early"

    Test-Assertion "Get-ErrorMessage helper function exists" {
        $content -match 'function Get-ErrorMessage'
    } "Get-ErrorMessage helper function should exist"

    Test-Assertion "Get-ErrorMessage handles ErrorRecord objects" {
        $content -match '\$ErrorRecord\s+-is\s+\[System\.Management\.Automation\.ErrorRecord\]'
    } "Get-ErrorMessage should handle ErrorRecord objects"

    Test-Assertion "Get-ErrorMessage handles Exception objects" {
        $content -match '\$ErrorRecord\s+-is\s+\[System\.Exception\]'
    } "Get-ErrorMessage should handle Exception objects"

    Test-Assertion "Invoke-Process uses Get-ErrorMessage for error logging" {
        $content -match 'WriteLog\s*\(Get-ErrorMessage\s+\$_\)'
    } "Invoke-Process should use Get-ErrorMessage"

    Test-Assertion "Invoke-Process validates paths before Remove-Item" {
        $content -match 'Where-Object.*IsNullOrWhiteSpace' -and $content -match '\$pathsToRemove\.Count\s*-gt\s*0'
    } "Invoke-Process should validate paths before Remove-Item"
}
else {
    Write-TestResult "FFU.Common.Core.psm1 tests" -Status 'Skipped' -Message "File not found: $coreModule"
}

# ============================================================================
# Test 2: FFU.ADK WriteLog Calls
# ============================================================================
Write-Host "`n--- FFU.ADK WriteLog Tests ---" -ForegroundColor Yellow

$adkModule = Join-Path $modulePath "FFU.ADK\FFU.ADK.psm1"
if (Test-Path $adkModule) {
    $content = Get-Content $adkModule -Raw

    Test-Assertion "FFU.ADK: No direct WriteLog `$_ calls" {
        -not ($content -match 'WriteLog\s+\$_\s*$' -or $content -match 'WriteLog\s+\$_\s*[\r\n]')
    } "Should not have direct WriteLog `$_ calls"

    Test-Assertion "FFU.ADK: Uses Get-ErrorMessage or string interpolation" {
        $content -match 'Get-ErrorMessage\s+\$_' -or $content -match '\$\(\$_\.Exception\.Message\)'
    } "Should use Get-ErrorMessage or `$_.Exception.Message"
}
else {
    Write-TestResult "FFU.ADK.psm1 tests" -Status 'Skipped' -Message "File not found: $adkModule"
}

# ============================================================================
# Test 3: Standalone Scripts WriteLog Functions
# ============================================================================
Write-Host "`n--- Standalone Scripts WriteLog Tests ---" -ForegroundColor Yellow

$createPEMedia = Join-Path $FFUDevelopmentPath "Create-PEMedia.ps1"
if (Test-Path $createPEMedia) {
    $content = Get-Content $createPEMedia -Raw

    Test-Assertion "Create-PEMedia.ps1: WriteLog has null check" {
        # Check that WriteLog function body contains IsNullOrWhiteSpace check
        $content -match 'function WriteLog' -and $content -match 'IsNullOrWhiteSpace\(\$LogText\)'
    } "WriteLog should check for null/empty"

    Test-Assertion "Create-PEMedia.ps1: No direct WriteLog `$_ call" {
        -not ($content -match 'WriteLog\s+\$_\s*$' -or $content -match 'WriteLog\s+\$_\s*[\r\n]')
    } "Should not have direct WriteLog `$_ calls"
}
else {
    Write-TestResult "Create-PEMedia.ps1 tests" -Status 'Skipped' -Message "File not found: $createPEMedia"
}

$applyFFU = Join-Path $FFUDevelopmentPath "WinPEDeployFFUFiles\ApplyFFU.ps1"
if (Test-Path $applyFFU) {
    $content = Get-Content $applyFFU -Raw

    Test-Assertion "ApplyFFU.ps1: WriteLog has null check" {
        # Check that WriteLog function body contains IsNullOrWhiteSpace check
        $content -match 'function WriteLog' -and $content -match 'IsNullOrWhiteSpace\(\$LogText\)'
    } "WriteLog should check for null/empty"

    Test-Assertion "ApplyFFU.ps1: No direct WriteLog `$_ call" {
        -not ($content -match 'WriteLog\s+\$_\s*$' -or $content -match 'WriteLog\s+\$_\s*[\r\n]')
    } "Should not have direct WriteLog `$_ calls"
}
else {
    Write-TestResult "ApplyFFU.ps1 tests" -Status 'Skipped' -Message "File not found: $applyFFU"
}

$usbCreator = Join-Path $FFUDevelopmentPath "USBImagingToolCreator.ps1"
if (Test-Path $usbCreator) {
    $content = Get-Content $usbCreator -Raw

    Test-Assertion "USBImagingToolCreator.ps1: WriteLog has null check" {
        # Check that WriteLog function body contains IsNullOrWhiteSpace check
        $content -match 'function WriteLog' -and $content -match 'IsNullOrWhiteSpace\(\$LogText\)'
    } "WriteLog should check for null/empty"
}
else {
    Write-TestResult "USBImagingToolCreator.ps1 tests" -Status 'Skipped' -Message "File not found: $usbCreator"
}

# ============================================================================
# Test 4: Functional Tests - Get-ErrorMessage
# ============================================================================
Write-Host "`n--- Functional Tests ---" -ForegroundColor Yellow

# Import the module to test Get-ErrorMessage
try {
    Import-Module $ffuCommonPath -Force -ErrorAction Stop

    Test-Assertion "Get-ErrorMessage handles null gracefully" {
        $result = Get-ErrorMessage $null
        $result -eq "[No error details available]"
    }

    Test-Assertion "Get-ErrorMessage handles empty string" {
        $result = Get-ErrorMessage ""
        $result -ne $null -and $result.Length -gt 0
    }

    Test-Assertion "Get-ErrorMessage extracts message from Exception" {
        try { throw "Test error message" } catch { $result = Get-ErrorMessage $_ }
        $result -match "Test error message"
    }

    Test-Assertion "Get-ErrorMessage handles exception with empty message" {
        try {
            $ex = [System.Exception]::new("")
            throw $ex
        } catch {
            $result = Get-ErrorMessage $_
        }
        $result -ne $null -and $result.Length -gt 0
    }
}
catch {
    Write-TestResult "Functional tests" -Status 'Skipped' -Message "Could not import FFU.Common module: $_"
}

# ============================================================================
# Test 5: WriteLog Null/Empty Handling
# ============================================================================
Write-Host "`n--- WriteLog Null/Empty Handling Tests ---" -ForegroundColor Yellow

try {
    # Create a temp log file for testing
    $testLogFile = Join-Path $env:TEMP "WriteLogTest_$(Get-Random).log"
    Set-CommonCoreLogPath -Path $testLogFile

    Test-Assertion "WriteLog with null does not throw" {
        try {
            WriteLog $null
            $true
        }
        catch {
            $false
        }
    }

    Test-Assertion "WriteLog with empty string does not throw" {
        try {
            WriteLog ""
            $true
        }
        catch {
            $false
        }
    }

    Test-Assertion "WriteLog with whitespace does not throw" {
        try {
            WriteLog "   "
            $true
        }
        catch {
            $false
        }
    }

    Test-Assertion "WriteLog with valid message works" {
        try {
            WriteLog "Test message"
            (Get-Content $testLogFile -Raw) -match "Test message"
        }
        catch {
            $false
        }
    }

    # Cleanup
    Remove-Item $testLogFile -Force -ErrorAction SilentlyContinue
}
catch {
    Write-TestResult "WriteLog null/empty tests" -Status 'Skipped' -Message "Could not set up test: $_"
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

# Show explanation of the fixes
Write-Host "`n--- Fix Explanation ---" -ForegroundColor Yellow
Write-Host @"
These fixes address two errors that occurred during FFU builds:

ERROR 1: "Cannot bind argument to parameter 'LogText' because it is an empty string"
  - Cause: WriteLog function called with null/empty value from exception handling
  - Fix: Added [AllowNull()], [AllowEmptyString()] attributes and early return for empty values
  - Also added Get-ErrorMessage helper function for safe exception message extraction

ERROR 2: "Value cannot be null. (Parameter 'The provided Path argument was null or an empty collection.')"
  - Cause: Remove-Item called with null path variables
  - Fix: Validate paths before passing to Remove-Item using Where-Object filter

Files modified:
  - FFU.Common\FFU.Common.Core.psm1 (WriteLog function, Get-ErrorMessage helper, Invoke-Process)
  - Modules\FFU.ADK\FFU.ADK.psm1 (4 WriteLog $_ calls updated)
  - Create-PEMedia.ps1 (WriteLog function and error handling)
  - WinPEDeployFFUFiles\ApplyFFU.ps1 (WriteLog function and error handling)
  - USBImagingToolCreator.ps1 (WriteLog function)
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
