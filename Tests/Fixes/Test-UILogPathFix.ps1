<#
.SYNOPSIS
    Test script to verify fix for null $mainLogPath in BuildFFUVM_UI.ps1 timer handler

.DESCRIPTION
    This test verifies that the timer's Tick handler correctly uses script-scoped
    variables instead of local variables that are out of scope when the timer fires.

    The bug was:
    - Line 686 used $config.FFUDevelopmentPath inside the Timer Tick handler
    - But $config is a local variable from the button click handler
    - When the timer fires after job completion, $config is no longer accessible
    - This caused $mainLogPath to be empty, showing error "expected at )"

    The fix:
    - Use $script:uiState.FFUDevelopmentPath instead (already exists at script level)

.NOTES
    Created: 2025-11-26
    Fix: Replace $config.FFUDevelopmentPath with $script:uiState.FFUDevelopmentPath in timer handler
#>

param()

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
Write-Host "UI Log Path Null Fix Test" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Tests that timer handler uses script-scoped variables correctly`n" -ForegroundColor Yellow

# =============================================================================
# Test 1: Verify the fix is in place - uses $script:uiState.FFUDevelopmentPath
# =============================================================================
Write-Host "--- Verifying Code Fix ---`n" -ForegroundColor Cyan

$uiScript = Get-Content "$PSScriptRoot\BuildFFUVM_UI.ps1" -Raw

# Check that the FIXED line exists (uses $script:uiState.FFUDevelopmentPath)
$fixedLinePattern = '\$mainLogPath\s*=\s*Join-Path\s+\$script:uiState\.FFUDevelopmentPath\s+[''"]FFUDevelopment\.log[''"]'
$hasFixedLine = $uiScript -match $fixedLinePattern
Write-TestResult -TestName "Timer handler uses script:uiState.FFUDevelopmentPath" -Passed $hasFixedLine `
    -Message $(if ($hasFixedLine) { "Found correct path variable usage" } else { "Missing or incorrect path variable" })

# Check that the BUGGY line is gone (uses $config.FFUDevelopmentPath in timer context)
# We need to be careful here - $config.FFUDevelopmentPath is VALID outside the timer handler
# The bug is specifically when it's used INSIDE the Add_Tick scriptblock
$addTickStart = $uiScript.IndexOf('$script:uiState.Data.pollTimer.Add_Tick({')
$addTickEnd = $uiScript.IndexOf('})', $addTickStart)
if ($addTickStart -gt 0 -and $addTickEnd -gt $addTickStart) {
    $tickHandlerCode = $uiScript.Substring($addTickStart, $addTickEnd - $addTickStart)
    $buggyLineInTimer = $tickHandlerCode -match '\$config\.FFUDevelopmentPath'
    Write-TestResult -TestName "Timer handler does NOT use out-of-scope \$config" -Passed (-not $buggyLineInTimer) `
        -Message $(if (-not $buggyLineInTimer) { "No references to \$config in timer handler" } else { "BUGGY: Timer handler still uses \$config (out of scope)" })
} else {
    Write-TestResult -TestName "Timer handler does NOT use out-of-scope \$config" -Passed $false `
        -Message "Could not locate Add_Tick handler in script"
}

# Check that there's a comment explaining the fix
$hasExplanatoryComment = $uiScript -match '# NOTE:.*\$config.*out of scope|# NOTE:.*script-scoped.*uiState\.FFUDevelopmentPath'
Write-TestResult -TestName "Fix includes explanatory comment" -Passed $hasExplanatoryComment `
    -Message $(if ($hasExplanatoryComment) { "Comment documents the scope issue" } else { "Missing explanatory comment" })

# =============================================================================
# Test 2: Verify $script:uiState.FFUDevelopmentPath is defined at script level
# =============================================================================
Write-Host "`n--- Verifying Script-Level Variable ---`n" -ForegroundColor Cyan

$stateDefinitionPattern = '\$script:uiState\s*=\s*\[PSCustomObject\]@\{[\s\S]*?FFUDevelopmentPath\s*='
$hasStateDefinition = $uiScript -match $stateDefinitionPattern
Write-TestResult -TestName "script:uiState.FFUDevelopmentPath is defined at script level" -Passed $hasStateDefinition `
    -Message $(if ($hasStateDefinition) { "Variable defined in state object initialization" } else { "Variable not found in state definition" })

# =============================================================================
# Test 3: Simulate the scope issue to prove it would have failed
# =============================================================================
Write-Host "`n--- Simulating Scope Behavior ---`n" -ForegroundColor Cyan

# Create script-level state (like the UI does)
$script:testUiState = [PSCustomObject]@{
    FFUDevelopmentPath = $PSScriptRoot
}

# Create a local config (like button click handler does)
$localConfig = @{
    FFUDevelopmentPath = $PSScriptRoot
}

# Simulate timer handler accessing script-level variable
$timerScriptBlock = {
    # This would work (script scope is accessible)
    $path1 = $script:testUiState.FFUDevelopmentPath

    # This would fail (local variable from outer function is out of scope)
    # We can't actually test this failing because $localConfig IS accessible in this immediate context
    # The real issue is when the scriptblock is invoked LATER by the timer

    return $path1
}

$scriptLevelPath = & $timerScriptBlock
Write-TestResult -TestName "Script-scoped variable accessible from scriptblock" -Passed ($scriptLevelPath -eq $PSScriptRoot) `
    -Message $(if ($scriptLevelPath -eq $PSScriptRoot) { "Path: $scriptLevelPath" } else { "Got: $scriptLevelPath" })

# =============================================================================
# Test 4: Verify Join-Path produces valid path with script-level variable
# =============================================================================
Write-Host "`n--- Verifying Path Construction ---`n" -ForegroundColor Cyan

$testPath = Join-Path $script:testUiState.FFUDevelopmentPath "FFUDevelopment.log"
$isValidPath = -not [string]::IsNullOrEmpty($testPath) -and $testPath -match 'FFUDevelopment\.log$'
Write-TestResult -TestName "Join-Path produces valid log path" -Passed $isValidPath `
    -Message $(if ($isValidPath) { "Path: $testPath" } else { "Invalid path: '$testPath'" })

# =============================================================================
# Test 5: Verify all timer handler variable accesses use script scope
# =============================================================================
Write-Host "`n--- Verifying Timer Handler Variable Patterns ---`n" -ForegroundColor Cyan

if ($addTickStart -gt 0 -and $addTickEnd -gt $addTickStart) {
    $tickHandlerCode = $uiScript.Substring($addTickStart, $addTickEnd - $addTickStart)

    # Count script-scoped variable accesses
    $scriptScopedAccesses = [regex]::Matches($tickHandlerCode, '\$script:uiState\.')
    Write-TestResult -TestName "Timer handler uses script scope consistently" -Passed ($scriptScopedAccesses.Count -gt 10) `
        -Message "Found $($scriptScopedAccesses.Count) script-scoped variable accesses"

    # Check specifically for $config which was the buggy pattern
    # Other local variables are fine (they're defined within the timer handler itself)
    $configReferences = [regex]::Matches($tickHandlerCode, '\$config\b')

    Write-TestResult -TestName "No \$config references in timer handler" -Passed ($configReferences.Count -eq 0) `
        -Message $(if ($configReferences.Count -eq 0) { "No \$config variable used (which would be out of scope)" } else { "Found \$config references that will be out of scope!" })
}

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
    Write-Host "  - Timer handler uses script-scoped variable" -ForegroundColor Cyan
    Write-Host "  - No references to out-of-scope local variables" -ForegroundColor Cyan
    Write-Host "  - Path construction works correctly" -ForegroundColor Cyan
} else {
    Write-Host "`nSome tests failed! Review the issues above." -ForegroundColor Red
}

Write-Host "`n=== Bug Pattern ===" -ForegroundColor Yellow
Write-Host "Before fix:" -ForegroundColor Red
Write-Host "  1. User clicks 'Build FFU' button" -ForegroundColor Gray
Write-Host "  2. \$config = Get-UIConfig (local variable in button handler)" -ForegroundColor Gray
Write-Host "  3. Timer Tick handler created with reference to \$config" -ForegroundColor Gray
Write-Host "  4. Build job runs for 57+ minutes, button handler scope ends" -ForegroundColor Gray
Write-Host "  5. Timer fires: \$config is null/inaccessible" -ForegroundColor Gray
Write-Host "  6. Join-Path \$null 'FFUDevelopment.log' = empty path" -ForegroundColor Red
Write-Host "  7. Error: 'expected at )' with empty path shown" -ForegroundColor Red

Write-Host "`nAfter fix:" -ForegroundColor Green
Write-Host "  1. User clicks 'Build FFU' button" -ForegroundColor Gray
Write-Host "  2. Timer Tick handler uses \$script:uiState.FFUDevelopmentPath" -ForegroundColor Gray
Write-Host "  3. Build job runs for 57+ minutes" -ForegroundColor Gray
Write-Host "  4. Timer fires: \$script:uiState is always accessible (script scope)" -ForegroundColor Green
Write-Host "  5. Join-Path produces valid path" -ForegroundColor Green
Write-Host "  6. Log file found, success message shown!" -ForegroundColor Green

# Return results for automation
return [PSCustomObject]@{
    TotalTests = $passCount + $failCount
    Passed = $passCount
    Failed = $failCount
    Results = $testResults
}
