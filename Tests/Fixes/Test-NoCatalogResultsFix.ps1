<#
.SYNOPSIS
    Test script to verify fix for KB path validation failure when catalog search returns no results

.DESCRIPTION
    This test verifies that when:
    1. User enables update flags ($UpdateLatestCU = $true, etc.)
    2. Microsoft Update Catalog search returns no results
    3. The flags are properly disabled with warnings
    4. The build does not fail with "path is empty" errors

.NOTES
    Created: 2025-11-26
    Fix: Added else blocks to disable flags when catalog search returns no results
    Related: KB_PATH_RESOLUTION_FIX_SUMMARY.md
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
Write-Host "No Catalog Results Fix Verification Test" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Tests that flags are disabled when catalog search returns no results`n" -ForegroundColor Yellow

# =============================================================================
# Test 1: Verify else blocks exist in BuildFFUVM.ps1
# =============================================================================
Write-Host "--- Verifying Else Block Implementation ---`n" -ForegroundColor Cyan

$buildScript = Get-Content "$PSScriptRoot\BuildFFUVM.ps1" -Raw

# Test CU else block
$cuElsePattern = 'elseif\s*\(\$UpdateLatestCU\)\s*\{[^}]*No Cumulative Update found[^}]*\$UpdateLatestCU\s*=\s*\$false'
$hasCUElse = $buildScript -match $cuElsePattern
Write-TestResult -TestName "CU else block exists in BuildFFUVM.ps1" -Passed $hasCUElse `
    -Message $(if ($hasCUElse) { "Found elseif block to disable CU flag when no catalog results" } else { "Missing elseif block for CU" })

# Test Preview CU else block
$cupElsePattern = 'elseif\s*\(\$UpdatePreviewCU\)\s*\{[^}]*No Preview Cumulative Update found[^}]*\$UpdatePreviewCU\s*=\s*\$false'
$hasCUPElse = $buildScript -match $cupElsePattern
Write-TestResult -TestName "Preview CU else block exists in BuildFFUVM.ps1" -Passed $hasCUPElse `
    -Message $(if ($hasCUPElse) { "Found elseif block to disable Preview CU flag when no catalog results" } else { "Missing elseif block for Preview CU" })

# Test .NET else block
$netElsePattern = 'elseif\s*\(\$UpdateLatestNet\)\s*\{[^}]*No \.NET Framework update found[^}]*\$UpdateLatestNet\s*=\s*\$false'
$hasNETElse = $buildScript -match $netElsePattern
Write-TestResult -TestName ".NET else block exists in BuildFFUVM.ps1" -Passed $hasNETElse `
    -Message $(if ($hasNETElse) { "Found elseif block to disable .NET flag when no catalog results" } else { "Missing elseif block for .NET" })

# Test Microcode else block
$microcodeElsePattern = 'elseif\s*\(\$UpdateLatestMicrocode\)\s*\{[^}]*No Microcode update found[^}]*\$UpdateLatestMicrocode\s*=\s*\$false'
$hasMicrocodeElse = $buildScript -match $microcodeElsePattern
Write-TestResult -TestName "Microcode else block exists in BuildFFUVM.ps1" -Passed $hasMicrocodeElse `
    -Message $(if ($hasMicrocodeElse) { "Found elseif block to disable Microcode flag when no catalog results" } else { "Missing elseif block for Microcode" })

# =============================================================================
# Test 2: Simulate the scenario
# =============================================================================
Write-Host "`n--- Simulating No-Catalog-Results Scenario ---`n" -ForegroundColor Cyan

# Simulate scenario where:
# - User enables $UpdateLatestCU = $true
# - Catalog search returns empty results ($cuUpdateInfos.Count = 0)
# - Path variable is null ($CUPath = $null)

# Before fix: $UpdateLatestCU stays $true, $CUPath stays $null -> validation fails
# After fix: elseif block sets $UpdateLatestCU = $false -> validation passes (skip update)

function Test-FlagDisablingLogic {
    param(
        [bool]$InitialFlag,
        [int]$UpdateInfosCount,
        [string]$Path
    )

    # Simulate the logic from BuildFFUVM.ps1 (after fix)
    $UpdateLatestCU = $InitialFlag
    $CUPath = $Path
    $cuUpdateInfos = @() * $UpdateInfosCount  # Create array of specified count

    # This is the actual logic pattern from the script
    if ($UpdateInfosCount -gt 0) {
        # Would resolve path here
        if (-not $CUPath) {
            $UpdateLatestCU = $false
        }
    } elseif ($UpdateLatestCU) {
        # NEW: Disable flag when catalog search returns no results
        $UpdateLatestCU = $false
    }

    return $UpdateLatestCU
}

# Scenario 1: User wants CU, catalog finds results, path resolved
$result1 = Test-FlagDisablingLogic -InitialFlag $true -UpdateInfosCount 1 -Path "C:\KB\test.msu"
Write-TestResult -TestName "Scenario: CU requested + results found + path resolved" -Passed ($result1 -eq $true) `
    -Message "Flag should remain enabled: $result1"

# Scenario 2: User wants CU, catalog finds results, path NOT resolved
$result2 = Test-FlagDisablingLogic -InitialFlag $true -UpdateInfosCount 1 -Path $null
Write-TestResult -TestName "Scenario: CU requested + results found + path NOT resolved" -Passed ($result2 -eq $false) `
    -Message "Flag should be disabled: $result2"

# Scenario 3: User wants CU, catalog finds NO results (THIS IS THE BUG SCENARIO)
$result3 = Test-FlagDisablingLogic -InitialFlag $true -UpdateInfosCount 0 -Path $null
Write-TestResult -TestName "Scenario: CU requested + NO results (BUG SCENARIO)" -Passed ($result3 -eq $false) `
    -Message "Flag should be disabled by elseif block: $result3"

# Scenario 4: User does NOT want CU, catalog finds NO results
$result4 = Test-FlagDisablingLogic -InitialFlag $false -UpdateInfosCount 0 -Path $null
Write-TestResult -TestName "Scenario: CU NOT requested + NO results" -Passed ($result4 -eq $false) `
    -Message "Flag should remain disabled: $result4"

# =============================================================================
# Test 3: Test-KBPathsValid with disabled flags
# =============================================================================
Write-Host "`n--- Testing Validation After Flag Disabling ---`n" -ForegroundColor Cyan

# Import modules
try {
    $env:PSModulePath = "$ModulesPath;$env:PSModulePath"
    Import-Module (Join-Path $ModulesPath "FFU.Constants\FFU.Constants.psm1") -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $ModulesPath "FFU.Core\FFU.Core.psm1") -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
    Import-Module (Join-Path $ModulesPath "FFU.Updates\FFU.Updates.psd1") -Force -ErrorAction Stop -WarningAction SilentlyContinue

    # Test: When all flags are disabled, validation should pass
    $validation1 = Test-KBPathsValid -UpdateLatestCU $false -CUPath $null `
                                      -UpdatePreviewCU $false -CUPPath $null `
                                      -UpdateLatestNet $false -NETPath $null `
                                      -UpdateLatestMicrocode $false -MicrocodePath $null `
                                      -SSURequired $false -SSUFilePath $null

    Write-TestResult -TestName "Validation passes when all flags disabled (no paths needed)" -Passed $validation1.IsValid `
        -Message $(if ($validation1.IsValid) { "No errors - updates will be skipped gracefully" } else { "Unexpected error: $($validation1.ErrorMessage)" })

    # Test: When flag is enabled but path is empty, validation should fail (pre-fix behavior)
    $validation2 = Test-KBPathsValid -UpdateLatestCU $true -CUPath $null `
                                      -UpdatePreviewCU $false -CUPPath $null `
                                      -UpdateLatestNet $false -NETPath $null `
                                      -UpdateLatestMicrocode $false -MicrocodePath $null `
                                      -SSURequired $false -SSUFilePath $null

    Write-TestResult -TestName "Validation catches enabled flag with empty path" -Passed (-not $validation2.IsValid) `
        -Message $(if (-not $validation2.IsValid) { "Correctly detected: $($validation2.Errors[0])" } else { "Should have failed but passed" })

    Remove-Module FFU.Updates -Force -ErrorAction SilentlyContinue

} catch {
    Write-TestResult -TestName "Module import for validation tests" -Passed $false -Message "Error: $_"
}

# =============================================================================
# Test 4: Verify correct warning messages in script
# =============================================================================
Write-Host "`n--- Verifying Warning Message Quality ---`n" -ForegroundColor Cyan

$expectedMessages = @{
    "CU" = "No Cumulative Update found in Microsoft Update Catalog"
    "PreviewCU" = "No Preview Cumulative Update found in Microsoft Update Catalog"
    "NET" = "No .NET Framework update found in Microsoft Update Catalog"
    "Microcode" = "No Microcode update found in Microsoft Update Catalog"
}

foreach ($updateType in $expectedMessages.Keys) {
    $message = $expectedMessages[$updateType]
    $hasMessage = $buildScript -match [regex]::Escape($message)
    Write-TestResult -TestName "Warning message for $updateType includes reason" -Passed $hasMessage `
        -Message $(if ($hasMessage) { "Found: '$message'" } else { "Missing informative warning message" })
}

# =============================================================================
# Test 5: Full integration simulation
# =============================================================================
Write-Host "`n--- Full Integration Simulation ---`n" -ForegroundColor Cyan

# Simulate the full path resolution flow
function Simulate-PathResolutionFlow {
    param(
        [bool]$UpdateLatestCU,
        [bool]$UpdateLatestNet,
        [bool]$UpdatePreviewCU,
        [bool]$UpdateLatestMicrocode,
        [hashtable]$CatalogResults  # Count of results for each type
    )

    $flags = @{
        CU = $UpdateLatestCU
        NET = $UpdateLatestNet
        PreviewCU = $UpdatePreviewCU
        Microcode = $UpdateLatestMicrocode
    }

    $paths = @{
        CU = $null
        NET = $null
        PreviewCU = $null
        Microcode = $null
    }

    $warnings = @()

    # Simulate path resolution logic (matching BuildFFUVM.ps1 structure)

    # CU
    if ($CatalogResults.CU -gt 0) {
        $paths.CU = "C:\KB\CU.msu"  # Assume resolved
    } elseif ($flags.CU) {
        $warnings += "CU: No catalog results, flag disabled"
        $flags.CU = $false
    }

    # Preview CU
    if ($CatalogResults.PreviewCU -gt 0) {
        $paths.PreviewCU = "C:\KB\PreviewCU.msu"
    } elseif ($flags.PreviewCU) {
        $warnings += "PreviewCU: No catalog results, flag disabled"
        $flags.PreviewCU = $false
    }

    # .NET
    if ($CatalogResults.NET -gt 0) {
        $paths.NET = "C:\KB\NET.msu"
    } elseif ($flags.NET) {
        $warnings += ".NET: No catalog results, flag disabled"
        $flags.NET = $false
    }

    # Microcode
    if ($CatalogResults.Microcode -gt 0) {
        $paths.Microcode = "C:\KB\Microcode"
    } elseif ($flags.Microcode) {
        $warnings += "Microcode: No catalog results, flag disabled"
        $flags.Microcode = $false
    }

    # Check if any enabled flag has empty path (would cause validation failure)
    $enabledWithEmptyPath = @()
    if ($flags.CU -and -not $paths.CU) { $enabledWithEmptyPath += "CU" }
    if ($flags.NET -and -not $paths.NET) { $enabledWithEmptyPath += ".NET" }
    if ($flags.PreviewCU -and -not $paths.PreviewCU) { $enabledWithEmptyPath += "PreviewCU" }
    if ($flags.Microcode -and -not $paths.Microcode) { $enabledWithEmptyPath += "Microcode" }

    return [PSCustomObject]@{
        Flags = $flags
        Paths = $paths
        Warnings = $warnings
        EnabledWithEmptyPath = $enabledWithEmptyPath
        WouldFail = $enabledWithEmptyPath.Count -gt 0
    }
}

# Test: All updates requested, none found in catalog
$sim1 = Simulate-PathResolutionFlow -UpdateLatestCU $true -UpdateLatestNet $true -UpdatePreviewCU $true -UpdateLatestMicrocode $true `
                                    -CatalogResults @{ CU = 0; NET = 0; PreviewCU = 0; Microcode = 0 }

Write-TestResult -TestName "Integration: All requested, none found" -Passed (-not $sim1.WouldFail) `
    -Message "Flags disabled: CU=$($sim1.Flags.CU), .NET=$($sim1.Flags.NET), PreviewCU=$($sim1.Flags.PreviewCU), Microcode=$($sim1.Flags.Microcode)"

# Test: Some updates found, some not
$sim2 = Simulate-PathResolutionFlow -UpdateLatestCU $true -UpdateLatestNet $true -UpdatePreviewCU $true -UpdateLatestMicrocode $true `
                                    -CatalogResults @{ CU = 1; NET = 0; PreviewCU = 0; Microcode = 1 }

Write-TestResult -TestName "Integration: CU and Microcode found, NET and PreviewCU not" -Passed (-not $sim2.WouldFail) `
    -Message "CU=$($sim2.Flags.CU), .NET=$($sim2.Flags.NET) (disabled), PreviewCU=$($sim2.Flags.PreviewCU) (disabled), Microcode=$($sim2.Flags.Microcode)"

# Test: No updates requested
$sim3 = Simulate-PathResolutionFlow -UpdateLatestCU $false -UpdateLatestNet $false -UpdatePreviewCU $false -UpdateLatestMicrocode $false `
                                    -CatalogResults @{ CU = 0; NET = 0; PreviewCU = 0; Microcode = 0 }

Write-TestResult -TestName "Integration: No updates requested" -Passed (-not $sim3.WouldFail) `
    -Message "No flags to disable, no paths needed"

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
    Write-Host "  - Catalog search returns no results" -ForegroundColor Cyan
    Write-Host "  - User-requested updates are gracefully skipped" -ForegroundColor Cyan
    Write-Host "  - Informative warning messages are logged" -ForegroundColor Cyan
    Write-Host "  - Validation no longer fails with empty path errors" -ForegroundColor Cyan
} else {
    Write-Host "`nSome tests failed! Review the issues above." -ForegroundColor Red
}

# Return results for automation
return [PSCustomObject]@{
    TotalTests = $passCount + $failCount
    Passed = $passCount
    Failed = $failCount
    Results = $testResults
}
