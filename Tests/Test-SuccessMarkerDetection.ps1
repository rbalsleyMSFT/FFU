<#
.SYNOPSIS
    Test script for FFU Build success marker detection

.DESCRIPTION
    Verifies that:
    1. BuildFFUVM.ps1 outputs a success marker PSCustomObject at completion
    2. BuildFFUVM_UI.ps1 correctly detects the success marker
    3. Success marker takes priority over non-terminating errors

    This addresses the issue where the UI reported failure even when builds
    completed successfully, due to non-terminating errors in the error stream.

.NOTES
    Run this script to verify the success marker implementation is correct.
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
Write-Host "Success Marker Detection Tests" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Determine paths
if (-not (Test-Path $FFUDevelopmentPath)) {
    $FFUDevelopmentPath = Join-Path (Split-Path $PSScriptRoot -Parent) "FFUDevelopment"
}

Write-Host "FFUDevelopment path: $FFUDevelopmentPath" -ForegroundColor Gray

# ============================================================================
# Test 1: BuildFFUVM.ps1 contains success marker output
# ============================================================================
Write-Host "`n--- BuildFFUVM.ps1 Success Marker Tests ---" -ForegroundColor Yellow

$buildScript = Join-Path $FFUDevelopmentPath "BuildFFUVM.ps1"
if (Test-Path $buildScript) {
    $content = Get-Content $buildScript -Raw

    Test-Assertion "BuildFFUVM.ps1: Contains FFUBuildSuccess property" {
        $content -match 'FFUBuildSuccess\s*=\s*\$true'
    } "BuildFFUVM.ps1 should output FFUBuildSuccess = `$true"

    Test-Assertion "BuildFFUVM.ps1: Contains success message" {
        $content -match 'Message\s*=\s*"FFU build completed successfully"'
    } "BuildFFUVM.ps1 should output success message"

    Test-Assertion "BuildFFUVM.ps1: Contains Duration property" {
        $content -match 'Duration\s*=\s*\$runTimeFormatted'
    } "BuildFFUVM.ps1 should output Duration"

    Test-Assertion "BuildFFUVM.ps1: Contains Timestamp property" {
        $content -match 'Timestamp\s*=\s*Get-Date'
    } "BuildFFUVM.ps1 should output Timestamp"

    Test-Assertion "BuildFFUVM.ps1: Success marker is PSCustomObject" {
        $content -match '\[PSCustomObject\]@\s*\{[\s\S]*FFUBuildSuccess'
    } "Success marker should be a PSCustomObject"

    Test-Assertion "BuildFFUVM.ps1: Success marker is at end of script" {
        # Check that the success marker is near the end (after 'Script complete' log)
        $scriptCompletePos = $content.LastIndexOf("WriteLog 'Script complete'")
        $successMarkerPos = $content.IndexOf("FFUBuildSuccess")
        $successMarkerPos -gt $scriptCompletePos
    } "Success marker should be output after 'Script complete' log"
}
else {
    Write-TestResult "BuildFFUVM.ps1 tests" -Status 'Skipped' -Message "File not found: $buildScript"
}

# ============================================================================
# Test 2: BuildFFUVM_UI.ps1 contains success marker detection
# ============================================================================
Write-Host "`n--- BuildFFUVM_UI.ps1 Success Marker Detection Tests ---" -ForegroundColor Yellow

$uiScript = Join-Path $FFUDevelopmentPath "BuildFFUVM_UI.ps1"
if (Test-Path $uiScript) {
    $content = Get-Content $uiScript -Raw

    Test-Assertion "BuildFFUVM_UI.ps1: Checks for FFUBuildSuccess property" {
        $content -match "PSObject\.Properties\['FFUBuildSuccess'\]"
    } "UI should check for FFUBuildSuccess property"

    Test-Assertion "BuildFFUVM_UI.ps1: Checks FFUBuildSuccess equals true" {
        $content -match 'FFUBuildSuccess\s*-eq\s*\$true'
    } "UI should verify FFUBuildSuccess equals `$true"

    Test-Assertion "BuildFFUVM_UI.ps1: Sets hasErrors to false on success marker" {
        $content -match 'if\s*\(\$successMarker\)[\s\S]*?\$hasErrors\s*=\s*\$false'
    } "UI should set hasErrors to false when success marker found"

    Test-Assertion "BuildFFUVM_UI.ps1: Logs success marker detection" {
        $content -match 'WriteLog\s*"Success marker detected'
    } "UI should log when success marker is detected"

    Test-Assertion "BuildFFUVM_UI.ps1: Falls back to error stream check" {
        $content -match 'else\s*\{[\s\S]*?\$hasErrors\s*=\s*\(\$jobErrors\.Count'
    } "UI should fall back to error stream check when no success marker"

    Test-Assertion "BuildFFUVM_UI.ps1: Checks object type before property access" {
        $content -match '\$_\s*-is\s*\[PSCustomObject\]'
    } "UI should verify object is PSCustomObject before checking properties"
}
else {
    Write-TestResult "BuildFFUVM_UI.ps1 tests" -Status 'Skipped' -Message "File not found: $uiScript"
}

# ============================================================================
# Test 3: Functional Tests - Success Marker Object Structure
# ============================================================================
Write-Host "`n--- Functional Tests ---" -ForegroundColor Yellow

Test-Assertion "Success marker object has correct structure" {
    $successMarker = [PSCustomObject]@{
        FFUBuildSuccess = $true
        Message = "FFU build completed successfully"
        Duration = "Duration: 30 min 00 sec"
        Timestamp = Get-Date
    }

    $successMarker.FFUBuildSuccess -eq $true -and
    $successMarker.Message -eq "FFU build completed successfully" -and
    $successMarker.PSObject.Properties['Duration'] -and
    $successMarker.PSObject.Properties['Timestamp']
} "Success marker object should have all required properties"

Test-Assertion "Success marker detection logic works correctly" {
    # Simulate job output with success marker
    $jobOutput = @(
        "Some log output",
        [PSCustomObject]@{ FFUBuildSuccess = $true; Message = "FFU build completed successfully" },
        "More output"
    )

    $successMarker = $jobOutput | Where-Object {
        $_ -is [PSCustomObject] -and $_.PSObject.Properties['FFUBuildSuccess'] -and $_.FFUBuildSuccess -eq $true
    } | Select-Object -Last 1

    $null -ne $successMarker -and $successMarker.FFUBuildSuccess -eq $true
} "Detection logic should find success marker in mixed output"

Test-Assertion "Detection handles output without success marker" {
    # Simulate job output without success marker
    $jobOutput = @(
        "Some log output",
        "Error occurred",
        [PSCustomObject]@{ SomeOtherProperty = "value" }
    )

    $successMarker = $jobOutput | Where-Object {
        $_ -is [PSCustomObject] -and $_.PSObject.Properties['FFUBuildSuccess'] -and $_.FFUBuildSuccess -eq $true
    } | Select-Object -Last 1

    $null -eq $successMarker
} "Detection should return null when no success marker present"

Test-Assertion "Detection handles null/empty job output" {
    $jobOutput = $null
    $successMarker = $null

    if ($jobOutput) {
        $successMarker = $jobOutput | Where-Object {
            $_ -is [PSCustomObject] -and $_.PSObject.Properties['FFUBuildSuccess'] -and $_.FFUBuildSuccess -eq $true
        } | Select-Object -Last 1
    }

    $null -eq $successMarker
} "Detection should handle null job output gracefully"

Test-Assertion "Detection ignores FFUBuildSuccess=false" {
    $jobOutput = @(
        [PSCustomObject]@{ FFUBuildSuccess = $false; Message = "Build failed" }
    )

    $successMarker = $jobOutput | Where-Object {
        $_ -is [PSCustomObject] -and $_.PSObject.Properties['FFUBuildSuccess'] -and $_.FFUBuildSuccess -eq $true
    } | Select-Object -Last 1

    $null -eq $successMarker
} "Detection should ignore markers with FFUBuildSuccess=false"

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

# Show explanation
Write-Host "`n--- Solution Explanation ---" -ForegroundColor Yellow
Write-Host @"
This solution addresses the "Value cannot be null" error that caused the UI
to report failure even when builds completed successfully.

The Problem:
- Any non-terminating error written to the error stream during the build
  would be captured by Receive-Job -ErrorVariable
- The UI checked ($jobErrors.Count -gt 0) to determine failure
- Cleanup operations (Remove-Item, etc.) could produce non-terminating errors
  that didn't affect the build but caused false failure reports

The Solution:
- BuildFFUVM.ps1 now outputs an explicit success marker PSCustomObject:
  [PSCustomObject]@{
      FFUBuildSuccess = `$true
      Message = "FFU build completed successfully"
      Duration = `$runTimeFormatted
      Timestamp = Get-Date
  }

- BuildFFUVM_UI.ps1 checks for this success marker FIRST
- If the success marker is found, the build is considered successful
  regardless of non-terminating errors in the error stream
- This provides positive confirmation of success rather than relying
  on the absence of errors

Files Modified:
  - BuildFFUVM.ps1 (added success marker output at end of script)
  - BuildFFUVM_UI.ps1 (added success marker detection logic)
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
