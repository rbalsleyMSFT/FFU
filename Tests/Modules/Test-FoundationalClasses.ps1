#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Test script for FFU.Common.Classes foundational improvements

.DESCRIPTION
    Tests the new classes and functions:
    - FFUConstants
    - FFUPaths (Issue #324 fix)
    - FFUNetworkConfiguration (Issue #327 fix)
    - Invoke-FFUOperation (Issue #319 fix)
#>

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " FFU Foundational Classes Test Suite" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Set location and import module
Set-Location "$PSScriptRoot\FFUDevelopment"
Import-Module ".\FFU.Common" -Force

$testsPassed = 0
$testsFailed = 0

# ============================================================================
# Test 1: FFUConstants Class
# ============================================================================
Write-Host "[Test 1] Testing FFUConstants class..." -ForegroundColor Yellow

try {
    $regPath = [FFUConstants]::REGISTRY_FILESYSTEM
    $minRetries = [FFUConstants]::DEFAULT_MAX_RETRIES
    $minSpace = [FFUConstants]::MIN_FREE_SPACE_GB

    if ($regPath -and $minRetries -eq 3 -and $minSpace -eq 50) {
        Write-Host "  PASS: FFUConstants accessible and values correct" -ForegroundColor Green
        $testsPassed++
    }
    else {
        Write-Host "  FAIL: FFUConstants values incorrect" -ForegroundColor Red
        $testsFailed++
    }
}
catch {
    Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $testsFailed++
}

# ============================================================================
# Test 2: FFUPaths - Boolean Rejection (Issue #324)
# ============================================================================
Write-Host "`n[Test 2] Testing FFUPaths boolean rejection (Issue #324)..." -ForegroundColor Yellow

try {
    # Should throw error for boolean values
    $shouldFail = $false
    try {
        [FFUPaths]::ValidatePathNotBoolean('False', 'TestPath')
        $shouldFail = $true
    }
    catch {
        # Expected to throw
    }

    if (-not $shouldFail) {
        Write-Host "  PASS: FFUPaths correctly rejects boolean 'False' as path" -ForegroundColor Green
        $testsPassed++
    }
    else {
        Write-Host "  FAIL: FFUPaths did not reject boolean value" -ForegroundColor Red
        $testsFailed++
    }
}
catch {
    Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $testsFailed++
}

# ============================================================================
# Test 3: FFUPaths - Valid Path Expansion
# ============================================================================
Write-Host "`n[Test 3] Testing FFUPaths path expansion..." -ForegroundColor Yellow

try {
    $expandedPath = [FFUPaths]::ExpandPath('.\FFU.Common', 'TestPath')

    if ($expandedPath -and [System.IO.Path]::IsPathRooted($expandedPath)) {
        Write-Host "  PASS: FFUPaths correctly expanded relative path to absolute" -ForegroundColor Green
        Write-Host "    Expanded to: $expandedPath" -ForegroundColor Gray
        $testsPassed++
    }
    else {
        Write-Host "  FAIL: Path expansion did not produce absolute path" -ForegroundColor Red
        $testsFailed++
    }
}
catch {
    Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $testsFailed++
}

# ============================================================================
# Test 4: FFUNetworkConfiguration - Proxy Detection (Issue #327)
# ============================================================================
Write-Host "`n[Test 4] Testing FFUNetworkConfiguration proxy detection (Issue #327)..." -ForegroundColor Yellow

try {
    $proxyConfig = [FFUNetworkConfiguration]::DetectProxySettings()

    if ($null -ne $proxyConfig) {
        Write-Host "  PASS: FFUNetworkConfiguration created successfully" -ForegroundColor Green

        if ($proxyConfig.ProxyServer) {
            Write-Host "    Proxy detected: $($proxyConfig.ProxyServer)" -ForegroundColor Gray
        }
        else {
            Write-Host "    No proxy configured (direct connection)" -ForegroundColor Gray
        }

        $testsPassed++
    }
    else {
        Write-Host "  FAIL: FFUNetworkConfiguration returned null" -ForegroundColor Red
        $testsFailed++
    }
}
catch {
    Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $testsFailed++
}

# ============================================================================
# Test 5: FFUNetworkConfiguration - BITS Proxy Usage
# ============================================================================
Write-Host "`n[Test 5] Testing FFUNetworkConfiguration BITS proxy settings..." -ForegroundColor Yellow

try {
    $proxyConfig = [FFUNetworkConfiguration]::DetectProxySettings()
    $proxyUsage = $proxyConfig.GetBITSProxyUsage()
    $proxyList = $proxyConfig.GetBITSProxyList()

    if ($proxyUsage) {
        Write-Host "  PASS: FFUNetworkConfiguration BITS proxy usage: $proxyUsage" -ForegroundColor Green

        if ($proxyList) {
            Write-Host "    Proxy list: $($proxyList -join ', ')" -ForegroundColor Gray
        }

        $testsPassed++
    }
    else {
        Write-Host "  FAIL: GetBITSProxyUsage returned null" -ForegroundColor Red
        $testsFailed++
    }
}
catch {
    Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $testsFailed++
}

# ============================================================================
# Test 6: Invoke-FFUOperation - Success Case (Issue #319)
# ============================================================================
Write-Host "`n[Test 6] Testing Invoke-FFUOperation success case (Issue #319)..." -ForegroundColor Yellow

try {
    $result = Invoke-FFUOperation -Operation {
        return "Success"
    } -OperationName "Test Operation" -MaxRetries 3

    if ($result -eq "Success") {
        Write-Host "  PASS: Invoke-FFUOperation executed successfully" -ForegroundColor Green
        $testsPassed++
    }
    else {
        Write-Host "  FAIL: Invoke-FFUOperation returned unexpected result: $result" -ForegroundColor Red
        $testsFailed++
    }
}
catch {
    Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $testsFailed++
}

# ============================================================================
# Test 7: Invoke-FFUOperation - Non-Critical Failure
# ============================================================================
Write-Host "`n[Test 7] Testing Invoke-FFUOperation non-critical failure..." -ForegroundColor Yellow

try {
    $result = Invoke-FFUOperation -Operation {
        throw "Intentional test error"
    } -OperationName "Test Failure" -MaxRetries 1

    if ($null -eq $result) {
        Write-Host "  PASS: Invoke-FFUOperation returned null for non-critical failure" -ForegroundColor Green
        $testsPassed++
    }
    else {
        Write-Host "  FAIL: Should have returned null for non-critical failure" -ForegroundColor Red
        $testsFailed++
    }
}
catch {
    Write-Host "  FAIL: Unexpected exception: $($_.Exception.Message)" -ForegroundColor Red
    $testsFailed++
}

# ============================================================================
# Test 8: Get-SafeProperty - Null Object Handling (Issue #319)
# ============================================================================
Write-Host "`n[Test 8] Testing Get-SafeProperty null handling (Issue #319)..." -ForegroundColor Yellow

try {
    $nullObject = $null
    $result = Get-SafeProperty -Object $nullObject -PropertyName "SomeProperty" -DefaultValue "DefaultValue"

    if ($result -eq "DefaultValue") {
        Write-Host "  PASS: Get-SafeProperty correctly handled null object" -ForegroundColor Green
        $testsPassed++
    }
    else {
        Write-Host "  FAIL: Get-SafeProperty returned unexpected value: $result" -ForegroundColor Red
        $testsFailed++
    }
}
catch {
    Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $testsFailed++
}

# ============================================================================
# Test 9: Invoke-SafeMethod - Null Object Handling (Issue #319)
# ============================================================================
Write-Host "`n[Test 9] Testing Invoke-SafeMethod null handling (Issue #319)..." -ForegroundColor Yellow

try {
    $nullObject = $null
    $result = Invoke-SafeMethod -Object $nullObject -MethodName "SomeMethod" -DefaultValue "DefaultValue"

    if ($result -eq "DefaultValue") {
        Write-Host "  PASS: Invoke-SafeMethod correctly handled null object" -ForegroundColor Green
        $testsPassed++
    }
    else {
        Write-Host "  FAIL: Invoke-SafeMethod returned unexpected value: $result" -ForegroundColor Red
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
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Test Summary" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Tests Passed: $testsPassed" -ForegroundColor Green
Write-Host "Tests Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -eq 0) { 'Green' } else { 'Red' })
Write-Host "Total Tests:  $($testsPassed + $testsFailed)`n"

if ($testsFailed -eq 0) {
    Write-Host "SUCCESS: All foundational classes are working correctly!" -ForegroundColor Green
    Write-Host "`nThe following issues have been addressed:" -ForegroundColor Cyan
    Write-Host "  - Issue #319: Null reference exception handling" -ForegroundColor White
    Write-Host "  - Issue #324: Boolean path validation" -ForegroundColor White
    Write-Host "  - Issue #327: Proxy support for downloads`n" -ForegroundColor White
    exit 0
}
else {
    Write-Host "FAILURE: Some tests failed. Please review the errors above.`n" -ForegroundColor Red
    exit 1
}
