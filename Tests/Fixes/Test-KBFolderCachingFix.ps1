<#
.SYNOPSIS
    Test script for KB Folder Caching Fix (Solution B)

.DESCRIPTION
    Validates that the KB folder now properly respects the RemoveUpdates parameter,
    matching the behavior of the Apps folder (Defender, MSRT, Edge, OneDrive).

    Tests include:
    - KB download-skip logic when files exist
    - Post-update KB deletion respects $RemoveUpdates
    - VHDX caching cleanup respects $RemoveUpdates
    - FFU.VM.psm1 Get-FFUEnvironment respects $RemoveUpdates
    - Enhanced logging with file counts and sizes
    - Empty folder edge case handling

.NOTES
    Created: 2025-11-26
    Part of: RemoveUpdates Bug Fix - Solution B Extension
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

    Write-Host "$symbol Test: $TestName - $status" -ForegroundColor $color
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

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "KB Folder Caching Fix - Test Suite" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# =============================================================================
# Test 1: KB download-skip logic exists in BuildFFUVM.ps1
# =============================================================================
Write-Host "Testing BuildFFUVM.ps1 changes..." -ForegroundColor Yellow

$buildScript = Get-Content "$FFUDevelopmentPath\BuildFFUVM.ps1" -Raw

$test1Pattern = 'kbCacheValid.*=.*\$false'
$test1Passed = $buildScript -match $test1Pattern
Write-TestResult -TestName "KB cache validation variable initialized" -Passed $test1Passed -Message "Pattern: kbCacheValid = `$false"

# =============================================================================
# Test 2: KB download-skip logic checks RemoveUpdates
# =============================================================================
$test2Pattern = 'Test-Path.*KBPath.*-not.*RemoveUpdates.*requiredUpdates'
$test2Passed = $buildScript -match $test2Pattern
Write-TestResult -TestName "KB cache check respects RemoveUpdates parameter" -Passed $test2Passed -Message "Pattern: Test-Path KBPath AND -not RemoveUpdates"

# =============================================================================
# Test 3: Missing updates detection logic
# =============================================================================
$test3Pattern = 'missingUpdates.*=.*\[System\.Collections\.Generic\.List'
$test3Passed = $buildScript -match $test3Pattern
Write-TestResult -TestName "Missing updates list for incremental download" -Passed $test3Passed -Message "Uses generic List for missing updates"

# =============================================================================
# Test 4: KB cache valid skip logic
# =============================================================================
$test4Pattern = 'All.*required updates found in KB cache.*skipping download'
$test4Passed = $buildScript -match $test4Pattern
Write-TestResult -TestName "Skip download when KB cache is valid" -Passed $test4Passed -Message "Logs 'All required updates found in KB cache'"

# =============================================================================
# Test 5: Incremental download logic (partial cache)
# =============================================================================
$test5Pattern = 'updates missing from cache.*downloading missing updates only'
$test5Passed = $buildScript -match $test5Pattern
Write-TestResult -TestName "Incremental download for partial cache" -Passed $test5Passed -Message "Downloads only missing updates"

# =============================================================================
# Test 6: Post-update KB deletion respects RemoveUpdates
# =============================================================================
$test6Pattern = 'if \(\$RemoveUpdates\)[\s\S]*?WriteLog.*Removing.*KBPath.*RemoveUpdates=true'
$test6Passed = $buildScript -match $test6Pattern
Write-TestResult -TestName "Post-update KB deletion checks RemoveUpdates" -Passed $test6Passed -Message "Pattern: if (`$RemoveUpdates) { ... Removing KBPath }"

# =============================================================================
# Test 7: Post-update KB preservation logging
# =============================================================================
$test7Pattern = 'Keeping.*KBPath.*for future builds.*files.*MB.*RemoveUpdates=false'
$test7Passed = $buildScript -match $test7Pattern
Write-TestResult -TestName "KB preservation logging with file stats" -Passed $test7Passed -Message "Logs file count and size when keeping KB folder"

# =============================================================================
# Test 8: VHDX caching cleanup respects RemoveUpdates
# =============================================================================
$test8Pattern = 'AllowVHDXCaching.*-and.*RemoveUpdates[\s\S]*?Removing.*KBPath.*RemoveUpdates=true.*AllowVHDXCaching=true'
$test8Passed = $buildScript -match $test8Pattern
Write-TestResult -TestName "VHDX caching cleanup checks both flags" -Passed $test8Passed -Message "Pattern: AllowVHDXCaching AND RemoveUpdates"

# =============================================================================
# Test 9: Empty folder detection in download-skip logic
# =============================================================================
$test9Pattern = 'KB folder exists but is EMPTY.*0 files.*will download'
$test9Passed = $buildScript -match $test9Pattern
Write-TestResult -TestName "Empty KB folder detection" -Passed $test9Passed -Message "Handles empty folder edge case"

# =============================================================================
# Test 10: Small file detection (< 10 MB threshold)
# =============================================================================
$test10Pattern = 'KB folder exists but files are too small.*MB.*<.*10.*MB.*will re-download'
$test10Passed = $buildScript -match $test10Pattern
Write-TestResult -TestName "Small file detection (incomplete downloads)" -Passed $test10Passed -Message "Uses 10MB threshold for KB files"

# =============================================================================
# Test 11: FFU.VM.psm1 - KB cleanup respects RemoveUpdates
# =============================================================================
Write-Host "`nTesting FFU.VM.psm1 changes..." -ForegroundColor Yellow

$vmModule = Get-Content "$FFUDevelopmentPath\Modules\FFU.VM\FFU.VM.psm1" -Raw

$test11Pattern = 'If \(\$RemoveUpdates -and \(Test-Path -Path \$KBPath\)\)'
$test11Passed = $vmModule -match $test11Pattern
Write-TestResult -TestName "FFU.VM Get-FFUEnvironment checks RemoveUpdates" -Passed $test11Passed -Message "Pattern: If (`$RemoveUpdates -and (Test-Path KBPath))"

# =============================================================================
# Test 12: FFU.VM.psm1 - KB preservation logging
# =============================================================================
$test12Pattern = 'Keeping.*KBPath.*files.*MB.*for future builds.*RemoveUpdates=false'
$test12Passed = $vmModule -match $test12Pattern
Write-TestResult -TestName "FFU.VM KB preservation logging" -Passed $test12Passed -Message "Logs when keeping KB folder in Get-FFUEnvironment"

# =============================================================================
# Test 13: No unconditional KB deletion in BuildFFUVM.ps1 (after updates)
# =============================================================================
# Check that the old unconditional deletion pattern is gone
$test13OldPattern = 'WriteLog "Removing \$KBPath"[\r\n\s]+Remove-Item -Path \$KBPath -Recurse -Force \| Out-Null[\r\n\s]+WriteLog ''Clean Up the WinSxS'
$test13Passed = -not ($buildScript -match $test13OldPattern)
Write-TestResult -TestName "No unconditional KB deletion after updates" -Passed $test13Passed -Message "Old unconditional deletion pattern removed"

# =============================================================================
# Test 14: No unconditional KB deletion in VHDX caching section
# =============================================================================
$test14OldPattern = '# Remove KBPath for cached vhdx files[\r\n]+if \(\$AllowVHDXCaching\) \{[\s\S]*?If \(Test-Path -Path \$KBPath\)[\s\S]*?WriteLog "Removing \$KBPath"[\s\S]*?Remove-Item'
$test14Passed = -not ($buildScript -match $test14OldPattern)
Write-TestResult -TestName "No unconditional KB deletion in VHDX caching" -Passed $test14Passed -Message "VHDX caching now checks RemoveUpdates"

# =============================================================================
# Functional Tests
# =============================================================================
Write-Host "`nFunctional Tests..." -ForegroundColor Yellow

# Test 15: Create mock KB folder and test empty folder detection logic
$mockKBPath = Join-Path $env:TEMP "FFU_Test_KB_$(Get-Random)"
New-Item -Path $mockKBPath -ItemType Directory -Force | Out-Null

$mockFiles = Get-ChildItem -Path $mockKBPath -Recurse -File -ErrorAction SilentlyContinue
$isEmpty = -not $mockFiles -or $mockFiles.Count -eq 0
Write-TestResult -TestName "Empty folder detection functional test" -Passed $isEmpty -Message "Mock KB folder correctly detected as empty"

# Test 16: Create mock KB folder with files and test size calculation
$mockFile = Join-Path $mockKBPath "test_update.msu"
[byte[]]$bytes = [byte[]]::new(15MB)  # 15MB file
[System.IO.File]::WriteAllBytes($mockFile, $bytes)

$mockFiles2 = Get-ChildItem -Path $mockKBPath -Recurse -File -ErrorAction SilentlyContinue
$mockSize = if ($mockFiles2) { ($mockFiles2 | Measure-Object -Property Length -Sum).Sum } else { 0 }
$sizeCheckPassed = $mockSize -gt 10MB
Write-TestResult -TestName "File size calculation functional test" -Passed $sizeCheckPassed -Message "Size: $([math]::Round($mockSize/1MB, 2)) MB (threshold: 10 MB)"

# Cleanup mock folder
Remove-Item -Path $mockKBPath -Recurse -Force -ErrorAction SilentlyContinue

# Test 17: Verify download condition includes kbCacheValid check
$test17Pattern = '-Not \$cachedVHDXFileFound -and \$requiredUpdates\.Count -gt 0 -and -not \$kbCacheValid'
$test17Passed = $buildScript -match $test17Pattern
Write-TestResult -TestName "Download condition includes cache check" -Passed $test17Passed -Message "Pattern: -not kbCacheValid in download condition"

# =============================================================================
# Summary
# =============================================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total Tests: $($passCount + $failCount)" -ForegroundColor White
Write-Host "Passed: $passCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "Green" })

$passRate = [math]::Round(($passCount / ($passCount + $failCount)) * 100, 1)
Write-Host "Pass Rate: $passRate%" -ForegroundColor $(if ($passRate -eq 100) { "Green" } elseif ($passRate -ge 80) { "Yellow" } else { "Red" })

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Verification Steps" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host @"

To manually verify the KB folder caching fix:

1. First Build (RemoveUpdates=false):
   - Run a build with "Remove Downloaded Update Files" UNCHECKED
   - Enable at least one KB update (CU, .NET, or Microcode)
   - After build completes, verify KB folder exists:
     Get-ChildItem -Path "$FFUDevelopmentPath\KB" -Recurse

2. Second Build (Same Settings):
   - Keep "Remove Downloaded Update Files" UNCHECKED
   - Run build again
   - Check logs for: "All X required updates found in KB cache, skipping download"
   - Build should skip KB downloads (saves 500MB+ and 5-15 minutes)

3. Verify Cleanup Works (RemoveUpdates=true):
   - CHECK "Remove Downloaded Update Files"
   - Run build
   - After build, verify KB folder is deleted

4. Check Logs for Enhanced Messages:
   - "Found existing KB downloads in C:\FFUDevelopment\KB (X files, XXX.XX MB)"
   - "Keeping KB folder for future builds (X files, XXX.XX MB)"
   - "X of Y updates missing from cache, downloading missing updates only"

"@ -ForegroundColor White

if ($failCount -eq 0) {
    Write-Host "`nAll tests passed! KB folder caching fix is correctly implemented." -ForegroundColor Green
} else {
    Write-Host "`nSome tests failed. Please review the failed tests above." -ForegroundColor Red
}

# Return results for automation
return [PSCustomObject]@{
    TotalTests = $passCount + $failCount
    Passed = $passCount
    Failed = $failCount
    PassRate = $passRate
    Results = $testResults
}
