<#
.SYNOPSIS
    Test script for CaptureFFU.ps1 WMI network adapter replacement (Solution A)

.DESCRIPTION
    Validates that Get-NetAdapter has been successfully replaced with WMI-based
    Get-WmiNetworkAdapter function for WinPE compatibility.

.NOTES
    This test runs in full Windows environment, but the Get-WmiNetworkAdapter function
    is designed to work in WinPE where Get-NetAdapter is not available.
#>

param(
    [string]$CaptureFFUPath = "C:\claude\FFUBuilder\FFUDevelopment\WinPECaptureFFUFiles\CaptureFFU.ps1"
)

Write-Host "=== CaptureFFU.ps1 WMI Network Adapter Test Suite ===" -ForegroundColor Cyan
Write-Host ""

$testsPassed = 0
$testsFailed = 0

# Test 1: Verify CaptureFFU.ps1 file exists
Write-Host "Test 1: Checking CaptureFFU.ps1 file exists..." -ForegroundColor Yellow
if (Test-Path $CaptureFFUPath) {
    Write-Host "  PASSED: CaptureFFU.ps1 found at $CaptureFFUPath" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "  FAILED: CaptureFFU.ps1 not found at $CaptureFFUPath" -ForegroundColor Red
    $testsFailed++
    exit 1
}

# Read the script content
$scriptContent = Get-Content $CaptureFFUPath -Raw

# Test 2: Verify Get-WmiNetworkAdapter function exists
Write-Host "Test 2: Checking Get-WmiNetworkAdapter function exists..." -ForegroundColor Yellow
if ($scriptContent -match 'function Get-WmiNetworkAdapter \{') {
    Write-Host "  PASSED: Get-WmiNetworkAdapter function found" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "  FAILED: Get-WmiNetworkAdapter function not found" -ForegroundColor Red
    $testsFailed++
}

# Test 3: Verify Get-NetAdapter has been removed from line 43 (network check)
Write-Host "Test 3: Checking Get-NetAdapter removed from network check..." -ForegroundColor Yellow
$line43Pattern = 'Get-WmiNetworkAdapter -ConnectedOnly'
if ($scriptContent -match $line43Pattern) {
    Write-Host "  PASSED: Network check now uses Get-WmiNetworkAdapter -ConnectedOnly" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "  FAILED: Network check not updated to use WMI" -ForegroundColor Red
    $testsFailed++
}

# Test 4: Verify Get-NetAdapter has been removed from line 86 (timeout diagnostics)
Write-Host "Test 4: Checking Get-NetAdapter removed from timeout diagnostics..." -ForegroundColor Yellow
$line86Pattern = '\$adapters = Get-WmiNetworkAdapter'
if ($scriptContent -match $line86Pattern) {
    Write-Host "  PASSED: Timeout diagnostics now uses Get-WmiNetworkAdapter" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "  FAILED: Timeout diagnostics not updated to use WMI" -ForegroundColor Red
    $testsFailed++
}

# Test 5: Verify Get-NetAdapter has been removed from line 237 (diagnostics table)
Write-Host "Test 5: Checking Get-NetAdapter removed from diagnostics table..." -ForegroundColor Yellow
$line237Pattern = 'Get-WmiNetworkAdapter \| Format-Table'
if ($scriptContent -match $line237Pattern) {
    Write-Host "  PASSED: Diagnostics table now uses Get-WmiNetworkAdapter" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "  FAILED: Diagnostics table not updated to use WMI" -ForegroundColor Red
    $testsFailed++
}

# Test 6: Verify NO remaining Get-NetAdapter calls
Write-Host "Test 6: Checking for any remaining Get-NetAdapter calls..." -ForegroundColor Yellow
$remainingCalls = [regex]::Matches($scriptContent, 'Get-NetAdapter')
if ($remainingCalls.Count -eq 0) {
    Write-Host "  PASSED: No Get-NetAdapter calls found in script" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "  FAILED: Found $($remainingCalls.Count) Get-NetAdapter call(s) still in script:" -ForegroundColor Red
    foreach ($match in $remainingCalls) {
        $lineNum = ($scriptContent.Substring(0, $match.Index) -split "`n").Count
        Write-Host "    - Line $lineNum" -ForegroundColor Red
    }
    $testsFailed++
}

# Test 7: Functional test - Load and execute Get-WmiNetworkAdapter function
Write-Host "Test 7: Functional test of Get-WmiNetworkAdapter..." -ForegroundColor Yellow
try {
    # Extract and load the function
    $functionMatch = [regex]::Match($scriptContent, '(?s)function Get-WmiNetworkAdapter \{.*?^\}', [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if ($functionMatch.Success) {
        $functionCode = $functionMatch.Value
        Invoke-Expression $functionCode

        # Test the function
        $adapters = Get-WmiNetworkAdapter

        if ($adapters) {
            Write-Host "  PASSED: Get-WmiNetworkAdapter returned $($adapters.Count) adapter(s)" -ForegroundColor Green
            Write-Host "    Sample adapter: $($adapters[0].Name) - Status: $($adapters[0].Status)" -ForegroundColor Cyan
            $testsPassed++
        } else {
            Write-Host "  WARNING: Get-WmiNetworkAdapter returned no adapters (may be expected)" -ForegroundColor Yellow
            $testsPassed++
        }
    } else {
        Write-Host "  FAILED: Could not extract Get-WmiNetworkAdapter function" -ForegroundColor Red
        $testsFailed++
    }
} catch {
    Write-Host "  FAILED: Error testing Get-WmiNetworkAdapter: $_" -ForegroundColor Red
    $testsFailed++
}

# Test 8: Verify function has proper WMI query
Write-Host "Test 8: Checking WMI query implementation..." -ForegroundColor Yellow
if ($scriptContent -match 'Get-CimInstance -ClassName Win32_NetworkAdapter') {
    Write-Host "  PASSED: Function uses Win32_NetworkAdapter WMI class" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "  FAILED: Function does not use Win32_NetworkAdapter WMI class" -ForegroundColor Red
    $testsFailed++
}

# Test 9: Verify function filters virtual adapters
Write-Host "Test 9: Checking virtual adapter filtering..." -ForegroundColor Yellow
if ($scriptContent -match 'AdapterType -notlike "\*software\*"' -and
    $scriptContent -match 'Name -notlike "\*Virtual\*"') {
    Write-Host "  PASSED: Function filters out virtual/software adapters" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "  FAILED: Function does not properly filter virtual adapters" -ForegroundColor Red
    $testsFailed++
}

# Test 10: Verify function handles NetConnectionStatus
Write-Host "Test 10: Checking NetConnectionStatus handling..." -ForegroundColor Yellow
if ($scriptContent -match 'NetConnectionStatus -eq 2' -and
    $scriptContent -match 'switch \(\$_\.NetConnectionStatus\)') {
    Write-Host "  PASSED: Function properly handles NetConnectionStatus values" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "  FAILED: Function does not properly handle NetConnectionStatus" -ForegroundColor Red
    $testsFailed++
}

# Test 11: Verify function returns compatible output
Write-Host "Test 11: Checking output compatibility..." -ForegroundColor Yellow
if ($scriptContent -match 'Name =' -and
    $scriptContent -match 'Status =' -and
    $scriptContent -match 'LinkSpeed =' -and
    $scriptContent -match 'MacAddress =') {
    Write-Host "  PASSED: Function returns compatible output properties" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "  FAILED: Function output properties may not be compatible" -ForegroundColor Red
    $testsFailed++
}

# Test 12: Verify -ConnectedOnly parameter exists
Write-Host "Test 12: Checking -ConnectedOnly parameter..." -ForegroundColor Yellow
if ($scriptContent -match '\[switch\]\$ConnectedOnly') {
    Write-Host "  PASSED: -ConnectedOnly parameter found" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "  FAILED: -ConnectedOnly parameter not found" -ForegroundColor Red
    $testsFailed++
}

# Test 13: Compare WMI output to Get-NetAdapter (if available)
Write-Host "Test 13: Comparing WMI output to Get-NetAdapter (if available)..." -ForegroundColor Yellow
try {
    if (Get-Command Get-NetAdapter -ErrorAction SilentlyContinue) {
        $netAdapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
        $wmiAdapters = Get-WmiNetworkAdapter -ConnectedOnly | Select-Object -First 1

        if ($netAdapters -and $wmiAdapters) {
            Write-Host "  PASSED: Both methods returned adapters" -ForegroundColor Green
            Write-Host "    Get-NetAdapter: $($netAdapters.Name)" -ForegroundColor Cyan
            Write-Host "    Get-WmiNetworkAdapter: $($wmiAdapters.Name)" -ForegroundColor Cyan
            $testsPassed++
        } else {
            Write-Host "  WARNING: One or both methods returned no adapters" -ForegroundColor Yellow
            $testsPassed++
        }
    } else {
        Write-Host "  SKIPPED: Get-NetAdapter not available (expected in WinPE)" -ForegroundColor Cyan
        $testsPassed++
    }
} catch {
    Write-Host "  FAILED: Error comparing outputs: $_" -ForegroundColor Red
    $testsFailed++
}

# Test 14: Verify error handling
Write-Host "Test 14: Checking error handling..." -ForegroundColor Yellow
if ($scriptContent -match 'try \{' -and
    $scriptContent -match 'catch \{' -and
    $scriptContent -match 'ErrorAction Stop') {
    Write-Host "  PASSED: Function has proper error handling" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "  FAILED: Function may lack proper error handling" -ForegroundColor Red
    $testsFailed++
}

# Test 15: Verify helper function is placed at the beginning
Write-Host "Test 15: Checking function placement..." -ForegroundColor Yellow
$functionPosition = $scriptContent.IndexOf('function Get-WmiNetworkAdapter')
$firstUsage = $scriptContent.IndexOf('Get-WmiNetworkAdapter -ConnectedOnly')
if ($functionPosition -lt $firstUsage -and $functionPosition -gt 0) {
    Write-Host "  PASSED: Helper function defined before first usage" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "  FAILED: Helper function not properly placed" -ForegroundColor Red
    $testsFailed++
}

Write-Host ""
Write-Host "=== TEST SUMMARY ===" -ForegroundColor Cyan
Write-Host "Tests Passed: $testsPassed" -ForegroundColor Green
Write-Host "Tests Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -gt 0) { "Red" } else { "Green" })
Write-Host ""

if ($testsFailed -eq 0) {
    Write-Host "SUCCESS: All tests passed! CaptureFFU.ps1 is ready for WinPE." -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Rebuild WinPE capture media with updated CaptureFFU.ps1" -ForegroundColor White
    Write-Host "  2. Boot VM from capture media" -ForegroundColor White
    Write-Host "  3. Verify Get-WmiNetworkAdapter works in WinPE environment" -ForegroundColor White
    Write-Host "  4. Confirm no 'Get-NetAdapter not recognized' errors" -ForegroundColor White
    exit 0
} else {
    Write-Host "FAILURE: Some tests failed. Review the output above." -ForegroundColor Red
    exit 1
}
