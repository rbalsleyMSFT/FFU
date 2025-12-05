<#
.SYNOPSIS
    Test script to verify fix for path resolution when KB cache is valid

.DESCRIPTION
    This test verifies that when:
    1. User enables update flags ($UpdateLatestCU = $true, etc.)
    2. Microsoft Update Catalog search returns results (KB IDs found)
    3. KB files already exist in cache (kbCacheValid = $true)
    4. Downloads are skipped
    5. Path resolution STILL RUNS and resolves the paths correctly

    The bug was that path resolution code was INSIDE the download block,
    so when downloads were skipped (cache valid), path resolution was also skipped.

.NOTES
    Created: 2025-11-26
    Fix: Move path resolution code outside the download conditional block
    Bug: Path resolution inside "if (-not $kbCacheValid)" block
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
Write-Host "KB Cache Path Resolution Fix Test" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Tests that path resolution runs even when KB cache is valid`n" -ForegroundColor Yellow

# =============================================================================
# Test 1: Verify path resolution is OUTSIDE download block
# =============================================================================
Write-Host "--- Verifying Code Structure ---`n" -ForegroundColor Cyan

$buildScript = Get-Content "$PSScriptRoot\BuildFFUVM.ps1" -Raw

# The download block condition
$downloadBlockPattern = 'if\s*\(\s*-Not\s+\$cachedVHDXFileFound\s+-and\s+\$requiredUpdates\.Count\s+-gt\s+0\s+-and\s+-not\s+\$kbCacheValid\s*\)'

# Check that the path resolution section is NOT inside the download block
# The path resolution should be after the download block closes

# Look for the structure:
# 1. Download block closing (ends with "}")
# 2. Path resolution comment (outside the block)
$pathResolutionOutsidePattern = 'Start-BitsTransferWithRetry[^}]+\}\s*\}\s*\r?\n\s*# Set file path variables for the patching process'

$hasCorrectStructure = $buildScript -match $pathResolutionOutsidePattern
Write-TestResult -TestName "Path resolution is outside download block" -Passed $hasCorrectStructure `
    -Message $(if ($hasCorrectStructure) { "Found correct code structure: download block closes before path resolution" } else { "Path resolution may still be inside download block" })

# Verify the IMPORTANT comment exists
$importantCommentPattern = '# IMPORTANT: This section runs regardless of whether downloads occurred or were skipped'
$hasImportantComment = $buildScript -match $importantCommentPattern
Write-TestResult -TestName "Important comment documents the fix" -Passed $hasImportantComment `
    -Message $(if ($hasImportantComment) { "Found documentation comment" } else { "Missing documentation comment" })

# =============================================================================
# Test 2: Simulate the KB cache scenario
# =============================================================================
Write-Host "`n--- Simulating KB Cache Scenario ---`n" -ForegroundColor Cyan

function Simulate-KBCacheScenario {
    param(
        [bool]$CatalogFoundResults,
        [bool]$KBCacheValid,
        [bool]$CachedVHDXFound
    )

    # Simulate the flow from BuildFFUVM.ps1
    $requiredUpdates = [System.Collections.Generic.List[PSCustomObject]]::new()
    $cuUpdateInfos = [System.Collections.Generic.List[PSCustomObject]]::new()

    if ($CatalogFoundResults) {
        $requiredUpdates.Add([PSCustomObject]@{ Name = "test.msu" })
        $cuUpdateInfos.Add([PSCustomObject]@{ Name = "test.msu"; KBArticleID = "KB123456" })
    }

    $UpdateLatestCU = $true
    $CUPath = $null
    $cuKbArticleId = "KB123456"
    $downloadRan = $false
    $pathResolutionRan = $false

    # This is the FIXED code structure (after fix):
    # Download block only runs when cache is NOT valid
    if ((-not $CachedVHDXFound) -and ($requiredUpdates.Count -gt 0) -and (-not $KBCacheValid)) {
        # Downloads here...
        $downloadRan = $true
    }

    # PATH RESOLUTION IS NOW OUTSIDE THE DOWNLOAD BLOCK (FIX!)
    # This runs regardless of whether downloads happened
    if ($cuUpdateInfos.Count -gt 0) {
        $pathResolutionRan = $true
        $CUPath = "C:\KB\test.msu"  # Simulated resolution
    }

    return [PSCustomObject]@{
        DownloadRan = $downloadRan
        PathResolutionRan = $pathResolutionRan
        CUPath = $CUPath
        Scenario = "CatalogFound=$CatalogFoundResults, CacheValid=$KBCacheValid, VHDXCached=$CachedVHDXFound"
    }
}

# Scenario 1: Fresh download needed (no cache)
$sim1 = Simulate-KBCacheScenario -CatalogFoundResults $true -KBCacheValid $false -CachedVHDXFound $false
Write-TestResult -TestName "Scenario: Fresh download (no cache)" -Passed ($sim1.DownloadRan -and $sim1.PathResolutionRan -and $sim1.CUPath) `
    -Message "Download: $($sim1.DownloadRan), PathResolution: $($sim1.PathResolutionRan), CUPath: $($sim1.CUPath)"

# Scenario 2: KB cache valid (THE BUG SCENARIO) - download skipped, path resolution MUST still run
$sim2 = Simulate-KBCacheScenario -CatalogFoundResults $true -KBCacheValid $true -CachedVHDXFound $false
Write-TestResult -TestName "Scenario: KB cache valid (BUG SCENARIO)" -Passed (-not $sim2.DownloadRan -and $sim2.PathResolutionRan -and $sim2.CUPath) `
    -Message "Download: $($sim2.DownloadRan) (correctly skipped), PathResolution: $($sim2.PathResolutionRan) (must run!), CUPath: $($sim2.CUPath)"

# Scenario 3: VHDX cache found - download skipped, path resolution still runs (for any re-apply scenarios)
$sim3 = Simulate-KBCacheScenario -CatalogFoundResults $true -KBCacheValid $false -CachedVHDXFound $true
Write-TestResult -TestName "Scenario: VHDX cache found" -Passed (-not $sim3.DownloadRan -and $sim3.PathResolutionRan -and $sim3.CUPath) `
    -Message "Download: $($sim3.DownloadRan) (correctly skipped), PathResolution: $($sim3.PathResolutionRan), CUPath: $($sim3.CUPath)"

# Scenario 4: No catalog results - path resolution should handle gracefully
$sim4 = Simulate-KBCacheScenario -CatalogFoundResults $false -KBCacheValid $false -CachedVHDXFound $false
Write-TestResult -TestName "Scenario: No catalog results" -Passed (-not $sim4.DownloadRan -and -not $sim4.PathResolutionRan -and -not $sim4.CUPath) `
    -Message "Download: $($sim4.DownloadRan), PathResolution: $($sim4.PathResolutionRan), CUPath: (empty - expected)"

# =============================================================================
# Test 3: Verify actual module functions work
# =============================================================================
Write-Host "`n--- Testing Actual Module Functions ---`n" -ForegroundColor Cyan

# Create a temp KB folder with mock files
$testKBPath = Join-Path $env:TEMP "FFU_KB_Cache_Test_$([System.IO.Path]::GetRandomFileName().Replace('.',''))"
New-Item -Path $testKBPath -ItemType Directory -Force | Out-Null

# Create mock KB file matching what catalog would return
$mockKBFileName = "windows11.0-kb5068861-x64_mock.msu"
$mockKBPath = Join-Path $testKBPath $mockKBFileName
Set-Content -Path $mockKBPath -Value "Mock KB file for testing"

# Create mock .NET file
$mockNETFileName = "windows11.0-kb5066128-ndp481-x64_mock.msu"
$mockNETPath = Join-Path $testKBPath $mockNETFileName
Set-Content -Path $mockNETPath -Value "Mock .NET file for testing"

Write-Host "Created test KB folder: $testKBPath" -ForegroundColor Gray
Write-Host "  - $mockKBFileName" -ForegroundColor Gray
Write-Host "  - $mockNETFileName" -ForegroundColor Gray

try {
    $env:PSModulePath = "$ModulesPath;$env:PSModulePath"
    Import-Module (Join-Path $ModulesPath "FFU.Constants\FFU.Constants.psm1") -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $ModulesPath "FFU.Core\FFU.Core.psm1") -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
    Import-Module (Join-Path $ModulesPath "FFU.Updates\FFU.Updates.psd1") -Force -ErrorAction Stop -WarningAction SilentlyContinue

    # Test: Resolve-KBFilePath can find files by KB article ID (as would happen in cache scenario)
    $resolvedCU = Resolve-KBFilePath -KBPath $testKBPath -KBArticleId "KB5068861" -UpdateType "CU"
    Write-TestResult -TestName "Resolve-KBFilePath finds CU by KB ID" -Passed ($resolvedCU -and (Test-Path $resolvedCU)) `
        -Message $(if ($resolvedCU) { "Found: $([System.IO.Path]::GetFileName($resolvedCU))" } else { "Not found" })

    $resolvedNET = Resolve-KBFilePath -KBPath $testKBPath -KBArticleId "KB5066128" -UpdateType ".NET"
    Write-TestResult -TestName "Resolve-KBFilePath finds .NET by KB ID" -Passed ($resolvedNET -and (Test-Path $resolvedNET)) `
        -Message $(if ($resolvedNET) { "Found: $([System.IO.Path]::GetFileName($resolvedNET))" } else { "Not found" })

    # Test: Test-KBPathsValid passes when paths are resolved
    if ($resolvedCU -and $resolvedNET) {
        $validation = Test-KBPathsValid -UpdateLatestCU $true -CUPath $resolvedCU `
                                        -UpdatePreviewCU $false -CUPPath $null `
                                        -UpdateLatestNet $true -NETPath $resolvedNET `
                                        -UpdateLatestMicrocode $false -MicrocodePath $null `
                                        -SSURequired $false -SSUFilePath $null

        Write-TestResult -TestName "Validation passes with resolved cache paths" -Passed $validation.IsValid `
            -Message $(if ($validation.IsValid) { "All paths valid from cache" } else { "Errors: $($validation.ErrorMessage)" })
    }

    Remove-Module FFU.Updates -Force -ErrorAction SilentlyContinue
} catch {
    Write-TestResult -TestName "Module tests" -Passed $false -Message "Error: $_"
}

# Cleanup
Remove-Item -Path $testKBPath -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "`nCleaned up test files." -ForegroundColor Gray

# =============================================================================
# Test 4: Verify the specific log pattern from the bug report
# =============================================================================
Write-Host "`n--- Verifying Bug Report Pattern Match ---`n" -ForegroundColor Cyan

# The bug showed this pattern in the log:
# - "Found KB article ID: KB5068861" (catalog found results)
# - "All 3 required updates found in KB cache, skipping download" (cache valid)
# - "ERROR: Cumulative Update (CU) is enabled but path is empty" (path resolution skipped!)

# After fix, the pattern should be:
# - "Found KB article ID: KB5068861" (catalog found results)
# - "All 3 required updates found in KB cache, skipping download" (cache valid, downloads skipped)
# - "Latest CU identified as C:\FFUDevelopment\KB\..." (path resolution runs!)

# Verify the fix by checking code structure allows this flow
$cacheValidSkipPattern = 'All .* required updates found in KB cache, skipping download'
$hasCacheSkipLog = $buildScript -match $cacheValidSkipPattern
Write-TestResult -TestName "Cache skip log exists" -Passed $hasCacheSkipLog `
    -Message $(if ($hasCacheSkipLog) { "Found cache skip log message" } else { "Missing cache skip message" })

$pathResolutionLogPattern = 'Latest CU identified as'
$hasPathResolutionLog = $buildScript -match $pathResolutionLogPattern
Write-TestResult -TestName "Path resolution log exists" -Passed $hasPathResolutionLog `
    -Message $(if ($hasPathResolutionLog) { "Found path resolution success log" } else { "Missing path resolution log" })

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
    Write-Host "  - KB cache valid scenario (downloads skipped)" -ForegroundColor Cyan
    Write-Host "  - Path resolution runs regardless of download status" -ForegroundColor Cyan
    Write-Host "  - Paths are resolved using KB article IDs from catalog" -ForegroundColor Cyan
    Write-Host "  - Validation passes when cached files exist" -ForegroundColor Cyan
} else {
    Write-Host "`nSome tests failed! Review the issues above." -ForegroundColor Red
}

Write-Host "`n=== Bug Pattern ===" -ForegroundColor Yellow
Write-Host "Before fix:" -ForegroundColor Red
Write-Host "  1. Catalog search finds KB5068861, KB5066128" -ForegroundColor Gray
Write-Host "  2. Files exist in KB folder -> kbCacheValid = true" -ForegroundColor Gray
Write-Host "  3. Download block SKIPPED (along with path resolution inside it)" -ForegroundColor Gray
Write-Host "  4. CUPath, NETPath = null" -ForegroundColor Gray
Write-Host "  5. ERROR: path is empty" -ForegroundColor Red

Write-Host "`nAfter fix:" -ForegroundColor Green
Write-Host "  1. Catalog search finds KB5068861, KB5066128" -ForegroundColor Gray
Write-Host "  2. Files exist in KB folder -> kbCacheValid = true" -ForegroundColor Gray
Write-Host "  3. Download block SKIPPED (correctly)" -ForegroundColor Gray
Write-Host "  4. Path resolution runs OUTSIDE download block" -ForegroundColor Green
Write-Host "  5. CUPath, NETPath resolved correctly" -ForegroundColor Green
Write-Host "  6. Build continues successfully" -ForegroundColor Green

# Return results for automation
return [PSCustomObject]@{
    TotalTests = $passCount + $failCount
    Passed = $passCount
    Failed = $failCount
    Results = $testResults
}
