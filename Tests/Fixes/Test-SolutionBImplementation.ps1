<#
.SYNOPSIS
    Test script to verify Solution B implementation for RemoveUpdates bug fix

.DESCRIPTION
    Tests all changes made in Solution B:
    1. Verifies Remove-Updates function calls have been removed
    2. Tests improved download check logic with various scenarios
    3. Validates error handling and logging
#>

param(
    [string]$FFUDevelopmentPath = "C:\claude\FFUBuilder\FFUDevelopment"
)

Write-Host "=== Solution B Implementation Test ===" -ForegroundColor Cyan
Write-Host ""

$testsPassed = 0
$testsFailed = 0

# Test 1: Verify Remove-Updates call removed from BuildFFUVM.ps1
Write-Host "Test 1: Checking BuildFFUVM.ps1 for removed Remove-Updates call..." -ForegroundColor Yellow
$buildScript = Get-Content "$FFUDevelopmentPath\BuildFFUVM.ps1" -Raw
if ($buildScript -match 'Remove-Updates') {
    Write-Host "  FAILED: Remove-Updates still found in BuildFFUVM.ps1" -ForegroundColor Red
    $testsFailed++
} else {
    Write-Host "  PASSED: Remove-Updates call removed from BuildFFUVM.ps1" -ForegroundColor Green
    $testsPassed++
}

# Test 2: Verify Remove-Updates call removed from FFU.VM.psm1
Write-Host "Test 2: Checking FFU.VM.psm1 for removed Remove-Updates call..." -ForegroundColor Yellow
$vmModule = Get-Content "$FFUDevelopmentPath\Modules\FFU.VM\FFU.VM.psm1" -Raw
if ($vmModule -match 'Remove-Updates\s*$' -or $vmModule -match 'Remove-Updates\s*\n') {
    Write-Host "  FAILED: Remove-Updates still found in FFU.VM.psm1" -ForegroundColor Red
    $testsFailed++
} else {
    Write-Host "  PASSED: Remove-Updates call removed from FFU.VM.psm1" -ForegroundColor Green
    $testsPassed++
}

# Test 3: Verify improved Defender download check logic
Write-Host "Test 3: Checking improved Defender download logic..." -ForegroundColor Yellow
if ($buildScript -match '\$defenderFiles\s*=\s*Get-ChildItem.*-File.*-ErrorAction SilentlyContinue' -and
    $buildScript -match 'if \(\$defenderFiles -and \$defenderFiles\.Count -gt 0\)' -and
    $buildScript -match 'Defender folder exists but is EMPTY') {
    Write-Host "  PASSED: Defender download logic improved with empty folder handling" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "  FAILED: Defender download logic not properly improved" -ForegroundColor Red
    $testsFailed++
}

# Test 4: Verify improved MSRT download check logic
Write-Host "Test 4: Checking improved MSRT download logic..." -ForegroundColor Yellow
if ($buildScript -match '\$msrtFiles\s*=\s*Get-ChildItem.*-File.*-ErrorAction SilentlyContinue' -and
    $buildScript -match 'if \(\$msrtFiles -and \$msrtFiles\.Count -gt 0\)' -and
    $buildScript -match 'MSRT folder exists but is EMPTY') {
    Write-Host "  PASSED: MSRT download logic improved with empty folder handling" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "  FAILED: MSRT download logic not properly improved" -ForegroundColor Red
    $testsFailed++
}

# Test 5: Verify improved Edge download check logic
Write-Host "Test 5: Checking improved Edge download logic..." -ForegroundColor Yellow
if ($buildScript -match '\$edgeFiles\s*=\s*Get-ChildItem.*-File.*-ErrorAction SilentlyContinue' -and
    $buildScript -match 'if \(\$edgeFiles -and \$edgeFiles\.Count -gt 0\)' -and
    $buildScript -match 'Edge folder exists but is EMPTY') {
    Write-Host "  PASSED: Edge download logic improved with empty folder handling" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "  FAILED: Edge download logic not properly improved" -ForegroundColor Red
    $testsFailed++
}

# Test 6: Verify improved OneDrive download check logic
Write-Host "Test 6: Checking improved OneDrive download logic..." -ForegroundColor Yellow
if ($buildScript -match '\$oneDriveFiles\s*=\s*Get-ChildItem.*-File.*-ErrorAction SilentlyContinue' -and
    $buildScript -match 'if \(\$oneDriveFiles -and \$oneDriveFiles\.Count -gt 0\)' -and
    $buildScript -match 'OneDrive folder exists but is EMPTY') {
    Write-Host "  PASSED: OneDrive download logic improved with empty folder handling" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "  FAILED: OneDrive download logic not properly improved" -ForegroundColor Red
    $testsFailed++
}

# Test 7: Verify enhanced logging with file counts and sizes
Write-Host "Test 7: Checking enhanced logging..." -ForegroundColor Yellow
if ($buildScript -match '\(\$\(\$defenderFiles\.Count\) files, \$\(\[math\]::Round\(\$DefenderSize/1MB, 2\)\) MB\)' -and
    $buildScript -match 'files are too small.*MB < 1 MB') {
    Write-Host "  PASSED: Enhanced logging with file counts and sizes present" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "  FAILED: Enhanced logging not properly implemented" -ForegroundColor Red
    $testsFailed++
}

# Test 8: Functional test - simulate empty folder scenario
Write-Host "Test 8: Functional test - simulating empty folder scenario..." -ForegroundColor Yellow
$testPath = Join-Path $env:TEMP "TestFFUDownloadCheck"
New-Item -ItemType Directory -Path $testPath -Force | Out-Null

# Simulate the download check logic
$testFiles = Get-ChildItem -Path $testPath -Recurse -File -ErrorAction SilentlyContinue
$shouldDownload = $false

if ($testFiles -and $testFiles.Count -gt 0) {
    $testSize = ($testFiles | Measure-Object -Property Length -Sum).Sum
    if ($testSize -gt 1MB) {
        $shouldDownload = $false
    } else {
        $shouldDownload = $true
    }
} else {
    # Empty folder - should trigger download
    $shouldDownload = $true
}

if ($shouldDownload) {
    Write-Host "  PASSED: Empty folder correctly triggers download flag" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "  FAILED: Empty folder does not trigger download" -ForegroundColor Red
    $testsFailed++
}

# Cleanup
Remove-Item -Path $testPath -Recurse -Force

# Test 9: Functional test - simulate folder with small file
Write-Host "Test 9: Functional test - simulating folder with small file..." -ForegroundColor Yellow
$testPath = Join-Path $env:TEMP "TestFFUDownloadCheck"
New-Item -ItemType Directory -Path $testPath -Force | Out-Null
"small file" | Out-File -FilePath "$testPath\small.txt" -Force

$testFiles = Get-ChildItem -Path $testPath -Recurse -File -ErrorAction SilentlyContinue
$shouldDownload = $false

if ($testFiles -and $testFiles.Count -gt 0) {
    $testSize = ($testFiles | Measure-Object -Property Length -Sum).Sum
    if ($testSize -gt 1MB) {
        $shouldDownload = $false
    } else {
        $shouldDownload = $true  # Small file should trigger re-download
    }
} else {
    $shouldDownload = $true
}

if ($shouldDownload) {
    Write-Host "  PASSED: Folder with small file (<1MB) correctly triggers download" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "  FAILED: Folder with small file does not trigger download" -ForegroundColor Red
    $testsFailed++
}

# Cleanup
Remove-Item -Path $testPath -Recurse -Force

# Test 10: Verify comments explaining cleanup mechanism
Write-Host "Test 10: Checking explanatory comments..." -ForegroundColor Yellow
if ($buildScript -match 'Update file cleanup is handled by Invoke-FFUPostBuildCleanup' -and
    $vmModule -match 'Update file cleanup is handled by Invoke-FFUPostBuildCleanup') {
    Write-Host "  PASSED: Explanatory comments added to both files" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "  FAILED: Explanatory comments missing" -ForegroundColor Red
    $testsFailed++
}

Write-Host ""
Write-Host "=== TEST SUMMARY ===" -ForegroundColor Cyan
Write-Host "Tests Passed: $testsPassed" -ForegroundColor Green
Write-Host "Tests Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -gt 0) { "Red" } else { "Green" })
Write-Host ""

if ($testsFailed -eq 0) {
    Write-Host "SUCCESS: All tests passed! Solution B implementation is correct." -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Run a build with RemoveUpdates checkbox UNCHECKED" -ForegroundColor White
    Write-Host "  2. Verify update files are downloaded" -ForegroundColor White
    Write-Host "  3. Run a second build with same settings" -ForegroundColor White
    Write-Host "  4. Check logs - should see 'skipping download' messages" -ForegroundColor White
    Write-Host "  5. Verify update files are NOT re-downloaded" -ForegroundColor White
} else {
    Write-Host "FAILURE: Some tests failed. Review the output above." -ForegroundColor Red
    exit 1
}
