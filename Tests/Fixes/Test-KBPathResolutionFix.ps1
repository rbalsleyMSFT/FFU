<#
.SYNOPSIS
    Test script for KB path resolution fix

.DESCRIPTION
    Validates the fix for "Cannot bind argument to parameter 'PackagePath'
    because it is an empty string" error during Windows Update application.

    Tests:
    1. Resolve-KBFilePath function with various input patterns
    2. Test-KBPathsValid validation function
    3. Integration with BuildFFUVM.ps1 path resolution logic
    4. Edge cases: empty paths, missing files, pattern mismatches

.NOTES
    Created: 2025-11-26
    Part of: KB Path Resolution Fix
#>

param(
    [string]$FFUDevelopmentPath = $PSScriptRoot
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

    $status = if ($Passed) { "PASSED" } else { "FAILED" }
    $color = if ($Passed) { "Green" } else { "Red" }
    $symbol = if ($Passed) { "[+]" } else { "[-]" }

    Write-Host "$symbol $TestName - $status" -ForegroundColor $color
    if ($Message) {
        Write-Host "    $Message" -ForegroundColor Gray
    }

    $script:testResults += [PSCustomObject]@{
        Test = $TestName
        Status = $status
        Message = $Message
    }

    if ($Passed) { $script:passCount++ } else { $script:failCount++ }
}

Write-Host "`n===========================================" -ForegroundColor Cyan
Write-Host "KB Path Resolution Fix Test Suite" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "This test validates the fix for 'PackagePath empty string' errors`n" -ForegroundColor Yellow

# Create test environment
$testKBPath = Join-Path $env:TEMP "FFU_KB_Test_$(Get-Random)"
New-Item -Path $testKBPath -ItemType Directory -Force | Out-Null

# Create mock KB files
$mockCU = Join-Path $testKBPath "windows11.0-kb5046613-x64_97f3b66ece1b0c03a76d44b0c68d61c81dce2f1f.msu"
$mockNET = Join-Path $testKBPath "windows11.0-kb5046625-ndp481-x64_abc123.msu"
$mockSSU = Join-Path $testKBPath "ssu-19041.4842-x64.msu"

# Create empty files to simulate downloaded KBs
"" | Out-File $mockCU
"" | Out-File $mockNET
"" | Out-File $mockSSU

Write-Host "Test KB folder: $testKBPath" -ForegroundColor Gray
Write-Host "Mock files created:`n  - $(Split-Path $mockCU -Leaf)`n  - $(Split-Path $mockNET -Leaf)`n  - $(Split-Path $mockSSU -Leaf)`n" -ForegroundColor Gray

# Import the FFU.Updates module
$modulePath = Join-Path $FFUDevelopmentPath "Modules\FFU.Updates\FFU.Updates.psm1"
if (Test-Path $modulePath) {
    # Need to import FFU.Core first (dependency)
    $corePath = Join-Path $FFUDevelopmentPath "Modules\FFU.Core\FFU.Core.psm1"
    $constantsPath = Join-Path $FFUDevelopmentPath "Modules\FFU.Constants\FFU.Constants.psm1"

    Import-Module $constantsPath -Force -ErrorAction SilentlyContinue
    Import-Module $corePath -Force -ErrorAction SilentlyContinue
    Import-Module $modulePath -Force -ErrorAction Stop
    Write-Host "FFU.Updates module loaded successfully`n" -ForegroundColor Green
} else {
    Write-Host "ERROR: FFU.Updates module not found at $modulePath" -ForegroundColor Red
    exit 1
}

# =============================================================================
# Test 1: Resolve-KBFilePath function exists
# =============================================================================
$test1 = Get-Command Resolve-KBFilePath -ErrorAction SilentlyContinue
Write-TestResult -TestName "Resolve-KBFilePath function exists" -Passed ($null -ne $test1)

# =============================================================================
# Test 2: Test-KBPathsValid function exists
# =============================================================================
$test2 = Get-Command Test-KBPathsValid -ErrorAction SilentlyContinue
Write-TestResult -TestName "Test-KBPathsValid function exists" -Passed ($null -ne $test2)

# =============================================================================
# Test 3: Resolve-KBFilePath finds file by exact filename
# =============================================================================
$resolvedPath = Resolve-KBFilePath -KBPath $testKBPath -FileName "windows11.0-kb5046613-x64_97f3b66ece1b0c03a76d44b0c68d61c81dce2f1f.msu" -UpdateType "CU"
# Compare filenames since paths may differ due to 8.3 name expansion
$test3 = ($null -ne $resolvedPath) -and ((Split-Path $resolvedPath -Leaf) -eq (Split-Path $mockCU -Leaf))
Write-TestResult -TestName "Resolve-KBFilePath finds by exact filename" -Passed $test3 -Message "Found: $resolvedPath"

# =============================================================================
# Test 4: Resolve-KBFilePath finds file by KB article ID pattern
# =============================================================================
$resolvedPath = Resolve-KBFilePath -KBPath $testKBPath -KBArticleId "5046613" -UpdateType "CU"
# Compare filenames since paths may differ due to 8.3 name expansion
$test4 = ($null -ne $resolvedPath) -and ((Split-Path $resolvedPath -Leaf) -eq (Split-Path $mockCU -Leaf))
Write-TestResult -TestName "Resolve-KBFilePath finds by KB article ID" -Passed $test4 -Message "Found: $resolvedPath"

# =============================================================================
# Test 5: Resolve-KBFilePath finds file with KB prefix pattern
# =============================================================================
$resolvedPath = Resolve-KBFilePath -KBPath $testKBPath -KBArticleId "5046625" -UpdateType ".NET"
# Compare filenames since paths may differ due to 8.3 name expansion
$test5 = ($null -ne $resolvedPath) -and ((Split-Path $resolvedPath -Leaf) -eq (Split-Path $mockNET -Leaf))
Write-TestResult -TestName "Resolve-KBFilePath finds by numeric ID pattern" -Passed $test5 -Message "Found: $resolvedPath"

# =============================================================================
# Test 6: Resolve-KBFilePath returns null for missing file
# =============================================================================
$resolvedPath = Resolve-KBFilePath -KBPath $testKBPath -FileName "nonexistent.msu" -KBArticleId "9999999" -UpdateType "Test"
$test6 = $null -eq $resolvedPath
Write-TestResult -TestName "Resolve-KBFilePath returns null for missing file" -Passed $test6 -Message "Result: $resolvedPath"

# =============================================================================
# Test 7: Resolve-KBFilePath handles empty KB path gracefully
# =============================================================================
$resolvedPath = Resolve-KBFilePath -KBPath "C:\NonExistentPath\KB" -KBArticleId "5046613" -UpdateType "CU"
$test7 = $null -eq $resolvedPath
Write-TestResult -TestName "Resolve-KBFilePath handles missing KB folder" -Passed $test7

# =============================================================================
# Test 8: Test-KBPathsValid passes with valid paths
# =============================================================================
$validation = Test-KBPathsValid -UpdateLatestCU $true -CUPath $mockCU -UpdateLatestNet $false -UpdatePreviewCU $false
$test8 = $validation.IsValid -eq $true
Write-TestResult -TestName "Test-KBPathsValid passes with valid CU path" -Passed $test8 -Message "Errors: $($validation.Errors.Count)"

# =============================================================================
# Test 9: Test-KBPathsValid fails with empty path
# =============================================================================
$validation = Test-KBPathsValid -UpdateLatestCU $true -CUPath "" -UpdateLatestNet $false -UpdatePreviewCU $false
$test9 = $validation.IsValid -eq $false -and $validation.Errors.Count -gt 0
Write-TestResult -TestName "Test-KBPathsValid fails with empty CU path" -Passed $test9 -Message "Errors: $($validation.Errors -join '; ')"

# =============================================================================
# Test 10: Test-KBPathsValid fails with null path
# =============================================================================
$validation = Test-KBPathsValid -UpdateLatestCU $true -CUPath $null -UpdateLatestNet $false -UpdatePreviewCU $false
$test10 = $validation.IsValid -eq $false
Write-TestResult -TestName "Test-KBPathsValid fails with null CU path" -Passed $test10 -Message "IsValid: $($validation.IsValid)"

# =============================================================================
# Test 11: Test-KBPathsValid fails with non-existent file
# =============================================================================
$validation = Test-KBPathsValid -UpdateLatestCU $true -CUPath "C:\NonExistent\fake.msu" -UpdateLatestNet $false
$test11 = $validation.IsValid -eq $false
Write-TestResult -TestName "Test-KBPathsValid fails with non-existent file" -Passed $test11 -Message "ErrorMessage: $($validation.ErrorMessage)"

# =============================================================================
# Test 12: Test-KBPathsValid validates multiple paths
# =============================================================================
$validation = Test-KBPathsValid -UpdateLatestCU $true -CUPath $mockCU `
                                -UpdateLatestNet $true -NETPath $mockNET `
                                -UpdatePreviewCU $false
$test12 = $validation.IsValid -eq $true
Write-TestResult -TestName "Test-KBPathsValid validates multiple valid paths" -Passed $test12 -Message "All paths valid"

# =============================================================================
# Test 13: Test-KBPathsValid catches multiple errors
# =============================================================================
$validation = Test-KBPathsValid -UpdateLatestCU $true -CUPath "" `
                                -UpdateLatestNet $true -NETPath "" `
                                -UpdatePreviewCU $true -CUPPath ""
$test13 = $validation.IsValid -eq $false -and $validation.Errors.Count -eq 3
Write-TestResult -TestName "Test-KBPathsValid catches multiple empty paths" -Passed $test13 -Message "Detected $($validation.Errors.Count) errors"

# =============================================================================
# Test 14: Test-KBPathsValid handles SSU requirement
# =============================================================================
$validation = Test-KBPathsValid -SSURequired $true -SSUFilePath $mockSSU -UpdateLatestCU $false
$test14 = $validation.IsValid -eq $true
Write-TestResult -TestName "Test-KBPathsValid validates SSU when required" -Passed $test14

# =============================================================================
# Test 15: Test-KBPathsValid fails on missing required SSU
# =============================================================================
$validation = Test-KBPathsValid -SSURequired $true -SSUFilePath "" -UpdateLatestCU $false
$test15 = $validation.IsValid -eq $false -and ($validation.Errors -join ' ') -match 'SSU'
Write-TestResult -TestName "Test-KBPathsValid fails on missing required SSU" -Passed $test15

# =============================================================================
# Test 16: Verify BuildFFUVM.ps1 contains path validation code
# =============================================================================
$buildScript = Get-Content "$FFUDevelopmentPath\BuildFFUVM.ps1" -Raw
$test16 = $buildScript -match 'Test-KBPathsValid'
Write-TestResult -TestName "BuildFFUVM.ps1 contains path validation" -Passed $test16

# =============================================================================
# Test 17: Verify BuildFFUVM.ps1 contains robust path resolution
# =============================================================================
$test17 = $buildScript -match 'Resolve-KBFilePath'
Write-TestResult -TestName "BuildFFUVM.ps1 uses robust path resolution" -Passed $test17

# =============================================================================
# Test 18: Verify BuildFFUVM.ps1 disables flags on resolution failure
# =============================================================================
$test18 = $buildScript -match 'Could not resolve.*path.*will be skipped' -and $buildScript -match '\$UpdateLatestCU = \$false'
Write-TestResult -TestName "BuildFFUVM.ps1 disables flags on resolution failure" -Passed $test18

# =============================================================================
# Test 19: Module syntax validation
# =============================================================================
$moduleContent = Get-Content $modulePath -Raw
$errors = $null
[void][System.Management.Automation.PSParser]::Tokenize($moduleContent, [ref]$errors)
$test19 = $errors.Count -eq 0
Write-TestResult -TestName "FFU.Updates module has valid PowerShell syntax" -Passed $test19 -Message "Errors: $($errors.Count)"

# =============================================================================
# Cleanup
# =============================================================================
Write-Host "`nCleaning up test files..." -ForegroundColor Gray
Remove-Item -Path $testKBPath -Recurse -Force -ErrorAction SilentlyContinue

# =============================================================================
# Summary
# =============================================================================
Write-Host "`n===========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "Total Tests: $($passCount + $failCount)" -ForegroundColor White
Write-Host "Passed: $passCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "Green" })

$passRate = [math]::Round(($passCount / ($passCount + $failCount)) * 100, 1)
Write-Host "Pass Rate: $passRate%" -ForegroundColor $(if ($passRate -eq 100) { "Green" } elseif ($passRate -ge 80) { "Yellow" } else { "Red" })

Write-Host "`n===========================================" -ForegroundColor Cyan
Write-Host "Fix Summary" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan

if ($failCount -eq 0) {
    Write-Host "`nAll tests passed!" -ForegroundColor Green
    Write-Host "`nThe fix addresses:" -ForegroundColor White
    Write-Host "  1. Empty PackagePath errors during KB application" -ForegroundColor Cyan
    Write-Host "  2. Unreliable file pattern matching in Get-ChildItem" -ForegroundColor Cyan
    Write-Host "  3. Missing pre-flight validation before DISM operations" -ForegroundColor Cyan
    Write-Host "  4. Silent failures when KB files cannot be located" -ForegroundColor Cyan
    Write-Host "`nNew behavior:" -ForegroundColor White
    Write-Host "  - Multiple fallback patterns for file resolution" -ForegroundColor Cyan
    Write-Host "  - Clear error messages when files cannot be found" -ForegroundColor Cyan
    Write-Host "  - Auto-disable update flags if paths unresolvable" -ForegroundColor Cyan
    Write-Host "  - Pre-validation catches issues before DISM starts" -ForegroundColor Cyan
} else {
    Write-Host "`nSome tests failed. Please review the failures above." -ForegroundColor Red
}

# Return results for automation
return [PSCustomObject]@{
    TotalTests = $passCount + $failCount
    Passed = $passCount
    Failed = $failCount
    PassRate = $passRate
    Results = $testResults
}
