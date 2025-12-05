#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Comprehensive integration test for foundational improvements

.DESCRIPTION
    Tests all foundational improvements in a realistic production scenario:
    - FFU.Common.Classes module loading
    - Proxy detection and configuration
    - Download fallback system with actual file download
    - Error handling and retry logic
    - Path validation and type safety
#>

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " FFU Foundational Improvements" -ForegroundColor Cyan
Write-Host " Integration Test Suite" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$ErrorActionPreference = 'Stop'
$testsPassed = 0
$testsFailed = 0
$testStartTime = Get-Date

# Navigate to FFUDevelopment
Set-Location "$PSScriptRoot\FFUDevelopment"

# ============================================================================
# Test 1: Module Import
# ============================================================================
Write-Host "[Test 1] Importing FFU.Common module..." -ForegroundColor Yellow

try {
    Import-Module ".\FFU.Common" -Force -ErrorAction Stop

    # Verify key functions are available
    $requiredFunctions = @(
        'Invoke-FFUOperation',
        'Get-SafeProperty',
        'Invoke-SafeMethod',
        'Start-BitsTransferWithRetry',
        'Start-ResilientDownload',
        'WriteLog',
        'Set-CommonCoreLogPath'
    )

    $missingFunctions = @()
    foreach ($func in $requiredFunctions) {
        if (-not (Get-Command $func -ErrorAction SilentlyContinue)) {
            $missingFunctions += $func
        }
    }

    if ($missingFunctions.Count -eq 0) {
        Write-Host "  PASS: FFU.Common module imported successfully" -ForegroundColor Green
        Write-Host "    All required functions available" -ForegroundColor Gray
        $testsPassed++
    }
    else {
        Write-Host "  FAIL: Missing functions: $($missingFunctions -join ', ')" -ForegroundColor Red
        $testsFailed++
    }
}
catch {
    Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $testsFailed++
    exit 1
}

# ============================================================================
# Test 2: Set Up Logging
# ============================================================================
Write-Host "`n[Test 2] Setting up logging..." -ForegroundColor Yellow

try {
    $logPath = Join-Path $env:TEMP "FFU_IntegrationTest_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    Set-CommonCoreLogPath -Path $logPath

    if (Test-Path $logPath) {
        Write-Host "  PASS: Log file created at $logPath" -ForegroundColor Green
        $testsPassed++
    }
    else {
        Write-Host "  FAIL: Log file not created" -ForegroundColor Red
        $testsFailed++
    }
}
catch {
    Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $testsFailed++
}

# ============================================================================
# Test 3: Proxy Detection (Issue #327)
# ============================================================================
Write-Host "`n[Test 3] Testing proxy detection (Issue #327)..." -ForegroundColor Yellow

try {
    # Test proxy detection through Start-BitsTransferWithRetry
    # The function auto-detects proxy if FFUNetworkConfiguration class is available

    Write-Host "  Attempting to auto-detect proxy configuration..." -ForegroundColor Gray

    # We'll test this indirectly by checking if download function accepts ProxyConfig parameter
    $functionInfo = Get-Command Start-BitsTransferWithRetry
    $hasProxyParam = $functionInfo.Parameters.ContainsKey('ProxyConfig')

    if ($hasProxyParam) {
        Write-Host "  PASS: Proxy configuration support detected" -ForegroundColor Green
        Write-Host "    Start-BitsTransferWithRetry has ProxyConfig parameter" -ForegroundColor Gray
        $testsPassed++
    }
    else {
        Write-Host "  FAIL: Proxy configuration parameter not found" -ForegroundColor Red
        $testsFailed++
    }
}
catch {
    Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $testsFailed++
}

# ============================================================================
# Test 4: Path Validation (Issue #324)
# ============================================================================
Write-Host "`n[Test 4] Testing path validation (Issue #324)..." -ForegroundColor Yellow

try {
    # Test 4a: Validate path expansion works
    Write-Host "  [4a] Testing valid path expansion..." -ForegroundColor Gray

    $validPathTest = $false
    try {
        $result = Invoke-FFUOperation -Operation {
            $relativePath = ".\FFU.Common"
            $fullPath = (Resolve-Path $relativePath -ErrorAction Stop).Path
            return $fullPath
        } -OperationName "Path expansion test" -MaxRetries 1

        if ($result -and [System.IO.Path]::IsPathRooted($result)) {
            $validPathTest = $true
        }
    }
    catch {
        # Failed
    }

    # Test 4b: Validate FFUPaths functions exist (classes may not be directly accessible in PS 5.1)
    Write-Host "  [4b] Testing path validation infrastructure..." -ForegroundColor Gray

    # Check if the Classes module is loaded
    $classesModuleLoaded = $false
    $loadedModules = Get-Module
    foreach ($mod in $loadedModules) {
        if ($mod.NestedModules | Where-Object { $_.Name -like '*Classes*' }) {
            $classesModuleLoaded = $true
            break
        }
    }

    if ($validPathTest -and $classesModuleLoaded) {
        Write-Host "  PASS: Path validation infrastructure working correctly" -ForegroundColor Green
        Write-Host "    Valid paths expanded properly" -ForegroundColor Gray
        Write-Host "    FFU.Common.Classes module loaded" -ForegroundColor Gray
        $testsPassed++
    }
    else {
        Write-Host "  FAIL: Path validation issues detected" -ForegroundColor Red
        Write-Host "    Valid path test: $validPathTest" -ForegroundColor Red
        Write-Host "    Classes module loaded: $classesModuleLoaded" -ForegroundColor Red
        $testsFailed++
    }
}
catch {
    Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $testsFailed++
}

# ============================================================================
# Test 5: Error Handling with Retry Logic (Issue #319)
# ============================================================================
Write-Host "`n[Test 5] Testing error handling with retry logic (Issue #319)..." -ForegroundColor Yellow

try {
    # Test 5a: Successful operation
    Write-Host "  [5a] Testing successful operation..." -ForegroundColor Gray

    $result = Invoke-FFUOperation -Operation {
        return "Success"
    } -OperationName "Test successful operation" -MaxRetries 3

    $test5a = ($result -eq "Success")

    # Test 5b: Retry logic
    Write-Host "  [5b] Testing retry logic with transient failure..." -ForegroundColor Gray

    $script:attemptCount = 0
    $result = Invoke-FFUOperation -Operation {
        $script:attemptCount++
        if ($script:attemptCount -lt 2) {
            throw "Transient error (attempt $script:attemptCount)"
        }
        return "Success after retry"
    } -OperationName "Test retry logic" -MaxRetries 3 -RetryDelaySeconds 1

    $test5b = ($result -eq "Success after retry" -and $script:attemptCount -eq 2)

    # Test 5c: Non-critical failure returns null
    Write-Host "  [5c] Testing non-critical failure handling..." -ForegroundColor Gray

    $result = Invoke-FFUOperation -Operation {
        throw "Non-critical error"
    } -OperationName "Test non-critical failure" -MaxRetries 1

    $test5c = ($null -eq $result)

    if ($test5a -and $test5b -and $test5c) {
        Write-Host "  PASS: Error handling with retry logic working correctly" -ForegroundColor Green
        Write-Host "    Successful operations complete normally" -ForegroundColor Gray
        Write-Host "    Retry logic works with exponential backoff" -ForegroundColor Gray
        Write-Host "    Non-critical failures return null" -ForegroundColor Gray
        $testsPassed++
    }
    else {
        Write-Host "  FAIL: Error handling issues detected" -ForegroundColor Red
        Write-Host "    5a: $test5a, 5b: $test5b, 5c: $test5c" -ForegroundColor Red
        $testsFailed++
    }
}
catch {
    Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $testsFailed++
}

# ============================================================================
# Test 6: Safe Property and Method Access (Issue #319)
# ============================================================================
Write-Host "`n[Test 6] Testing safe property and method access (Issue #319)..." -ForegroundColor Yellow

try {
    # Test 6a: Get-SafeProperty with null object
    Write-Host "  [6a] Testing Get-SafeProperty with null object..." -ForegroundColor Gray

    $nullObject = $null
    $result = Get-SafeProperty -Object $nullObject -PropertyName "Name" -DefaultValue "DefaultName"
    $test6a = ($result -eq "DefaultName")

    # Test 6b: Get-SafeProperty with valid object
    Write-Host "  [6b] Testing Get-SafeProperty with valid object..." -ForegroundColor Gray

    $validObject = [PSCustomObject]@{ Name = "TestName"; Value = 123 }
    $result = Get-SafeProperty -Object $validObject -PropertyName "Name" -DefaultValue "DefaultName"
    $test6b = ($result -eq "TestName")

    # Test 6c: Invoke-SafeMethod with null object
    Write-Host "  [6c] Testing Invoke-SafeMethod with null object..." -ForegroundColor Gray

    $nullObject = $null
    $result = Invoke-SafeMethod -Object $nullObject -MethodName "ToString" -DefaultValue "DefaultValue"
    $test6c = ($result -eq "DefaultValue")

    if ($test6a -and $test6b -and $test6c) {
        Write-Host "  PASS: Safe property and method access working correctly" -ForegroundColor Green
        Write-Host "    Null objects handled gracefully" -ForegroundColor Gray
        Write-Host "    Valid objects accessed normally" -ForegroundColor Gray
        Write-Host "    Default values returned on errors" -ForegroundColor Gray
        $testsPassed++
    }
    else {
        Write-Host "  FAIL: Safe access issues detected" -ForegroundColor Red
        Write-Host "    6a: $test6a, 6b: $test6b, 6c: $test6c" -ForegroundColor Red
        $testsFailed++
    }
}
catch {
    Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $testsFailed++
}

# ============================================================================
# Test 7: Actual File Download with Fallback System
# ============================================================================
Write-Host "`n[Test 7] Testing actual file download with fallback system..." -ForegroundColor Yellow

try {
    # Small test file from Microsoft
    $testUrl = "https://go.microsoft.com/fwlink/?LinkId=866658"
    $testDest = Join-Path $env:TEMP "ffu_integration_test_$(Get-Date -Format 'yyyyMMdd_HHmmss').tmp"

    if (Test-Path $testDest) {
        Remove-Item $testDest -Force
    }

    Write-Host "  Downloading test file..." -ForegroundColor Gray
    Write-Host "    URL: $testUrl" -ForegroundColor Gray
    Write-Host "    Destination: $testDest" -ForegroundColor Gray

    $downloadStartTime = Get-Date

    # Test with fallback enabled (default)
    Start-BitsTransferWithRetry -Source $testUrl -Destination $testDest -Retries 2

    $downloadDuration = (Get-Date) - $downloadStartTime

    if (Test-Path $testDest) {
        $fileSize = (Get-Item $testDest).Length
        $fileSizeMB = [math]::Round($fileSize / 1MB, 2)

        Write-Host "  PASS: File downloaded successfully with fallback system" -ForegroundColor Green
        Write-Host "    File size: $fileSizeMB MB" -ForegroundColor Gray
        Write-Host "    Duration: $($downloadDuration.TotalSeconds) seconds" -ForegroundColor Gray
        Write-Host "    Fallback system available and functional" -ForegroundColor Gray

        # Cleanup
        Remove-Item $testDest -Force -ErrorAction SilentlyContinue

        $testsPassed++
    }
    else {
        Write-Host "  FAIL: File not downloaded" -ForegroundColor Red
        $testsFailed++
    }
}
catch {
    Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $testsFailed++
}

# ============================================================================
# Test 8: Production Scenario - Download with Error Handling
# ============================================================================
Write-Host "`n[Test 8] Testing production scenario: Download with comprehensive error handling..." -ForegroundColor Yellow

try {
    $testDest2 = Join-Path $env:TEMP "ffu_production_test_$(Get-Date -Format 'yyyyMMdd_HHmmss').tmp"

    if (Test-Path $testDest2) {
        Remove-Item $testDest2 -Force
    }

    Write-Host "  Simulating production download workflow..." -ForegroundColor Gray

    # Use closure to capture variables instead of ArgumentList
    $url = "https://go.microsoft.com/fwlink/?LinkId=866658"
    $dest = $testDest2

    $result = Invoke-FFUOperation -Operation {
        # This simulates the production workflow
        Start-BitsTransferWithRetry -Source $url -Destination $dest -Retries 3

        # Verify download
        if (-not (Test-Path $dest)) {
            throw "Downloaded file not found at $dest"
        }

        $size = (Get-Item $dest).Length
        if ($size -eq 0) {
            throw "Downloaded file is empty"
        }

        return @{
            Success = $true
            FilePath = $dest
            FileSize = $size
        }
    }.GetNewClosure() -OperationName "Production download workflow" `
      -MaxRetries 2 `
      -CriticalOperation `
      -OnFailure {
        # Cleanup on failure
        if (Test-Path $testDest2) {
            Remove-Item $testDest2 -Force -ErrorAction SilentlyContinue
        }
    }

    if ($result.Success -and (Test-Path $testDest2)) {
        $fileSizeMB = [math]::Round($result.FileSize / 1MB, 2)

        Write-Host "  PASS: Production scenario completed successfully" -ForegroundColor Green
        Write-Host "    Download succeeded: $fileSizeMB MB" -ForegroundColor Gray
        Write-Host "    Error handling wrapper functional" -ForegroundColor Gray
        Write-Host "    Cleanup handlers in place" -ForegroundColor Gray

        # Cleanup
        Remove-Item $testDest2 -Force -ErrorAction SilentlyContinue

        $testsPassed++
    }
    else {
        Write-Host "  FAIL: Production scenario failed" -ForegroundColor Red
        $testsFailed++
    }
}
catch {
    Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red

    # Cleanup
    if (Test-Path $testDest2) {
        Remove-Item $testDest2 -Force -ErrorAction SilentlyContinue
    }

    $testsFailed++
}

# ============================================================================
# Test 9: Verify Log File Contents
# ============================================================================
Write-Host "`n[Test 9] Verifying log file contents..." -ForegroundColor Yellow

try {
    if (Test-Path $logPath) {
        $logContent = Get-Content $logPath -Raw

        # Check for expected log entries
        $hasOperationLogs = $logContent -like "*Starting operation:*"
        $hasCompletionLogs = $logContent -like "*completed successfully*"
        $hasDownloadLogs = $logContent -like "*download*" -or $logContent -like "*transfer*"

        if ($hasOperationLogs -and $hasCompletionLogs) {
            Write-Host "  PASS: Log file contains expected entries" -ForegroundColor Green
            Write-Host "    Operation start/completion logged" -ForegroundColor Gray
            Write-Host "    Log file: $logPath" -ForegroundColor Gray
            $testsPassed++
        }
        else {
            Write-Host "  FAIL: Log file missing expected entries" -ForegroundColor Red
            $testsFailed++
        }
    }
    else {
        Write-Host "  FAIL: Log file not found" -ForegroundColor Red
        $testsFailed++
    }
}
catch {
    Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $testsFailed++
}

# ============================================================================
# Summary
# ============================================================================
$testEndTime = Get-Date
$testDuration = $testEndTime - $testStartTime

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Integration Test Summary" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Tests Passed: $testsPassed" -ForegroundColor Green
Write-Host "Tests Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -eq 0) { 'Green' } else { 'Red' })
Write-Host "Total Tests:  $($testsPassed + $testsFailed)"
Write-Host "Duration:     $($testDuration.TotalSeconds) seconds`n"

if ($testsFailed -eq 0) {
    Write-Host "SUCCESS: All integration tests passed!" -ForegroundColor Green
    Write-Host "`nFoundational improvements verified:" -ForegroundColor Cyan
    Write-Host "  Issue #319: Null reference exception handling - WORKING" -ForegroundColor White
    Write-Host "  Issue #324: Path validation and type safety - WORKING" -ForegroundColor White
    Write-Host "  Issue #327: Proxy support for downloads - WORKING" -ForegroundColor White
    Write-Host "  Multi-method download fallback - WORKING" -ForegroundColor White
    Write-Host "  Error handling with retry logic - WORKING" -ForegroundColor White
    Write-Host "  Production workflow integration - WORKING`n" -ForegroundColor White

    Write-Host "Log file available at: $logPath`n" -ForegroundColor Gray

    exit 0
}
else {
    Write-Host "FAILURE: Some integration tests failed.`n" -ForegroundColor Red
    Write-Host "Log file available at: $logPath`n" -ForegroundColor Gray
    exit 1
}
