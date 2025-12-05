#Requires -Version 5.1
<#
.SYNOPSIS
    Tests the architecture-agnostic update detection in FFU.Updates module.

.DESCRIPTION
    Validates that the Save-KB function correctly identifies updates that don't have
    architecture indicators in their Microsoft Update Catalog titles and skips the
    filter for these updates.

    Updates like Defender, Edge, and Windows Security Platform don't have x64/x86/ARM64
    in their catalog titles, which caused filter mismatches and download failures.

    This test was created after discovering that the filter @('x64') failed for:
    - "Update for Microsoft Defender Antivirus antimalware platform"
    - "Windows Security Platform"
    - Microsoft Edge updates

.NOTES
    Version: 1.0.0
    Created to prevent regression of architecture-agnostic update detection
#>

param(
    [switch]$Verbose
)

$script:PassCount = 0
$script:FailCount = 0
$script:TestResults = @()

function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Message = ""
    )

    $script:TestResults += [PSCustomObject]@{
        TestName = $TestName
        Passed   = $Passed
        Message  = $Message
    }

    if ($Passed) {
        $script:PassCount++
        Write-Host "  [PASS] $TestName" -ForegroundColor Green
    } else {
        $script:FailCount++
        Write-Host "  [FAIL] $TestName" -ForegroundColor Red
        if ($Message) {
            Write-Host "         $Message" -ForegroundColor Yellow
        }
    }
}

$FFUDevelopmentPath = Split-Path $PSScriptRoot -Parent
$ModulesPath = Join-Path $FFUDevelopmentPath "Modules"
$UpdatesModule = Join-Path $ModulesPath "FFU.Updates\FFU.Updates.psm1"

Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host "Architecture-Agnostic Update Detection Tests" -ForegroundColor Cyan
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host ""
Write-Host "Purpose: Ensure Defender, Edge, and Security Platform updates bypass the architecture filter" -ForegroundColor Gray
Write-Host ""

# =============================================================================
# Test 1: Verify the fix is present in FFU.Updates module
# =============================================================================
Write-Host "Testing FFU.Updates module contains the fix..." -ForegroundColor Yellow

try {
    $content = Get-Content -Path $UpdatesModule -Raw -ErrorAction Stop

    # Check for the architecture-agnostic detection pattern
    $hasArchAgnosticDetection = $content -match '\$isArchAgnosticUpdate\s*=\s*\$kb\s+-match\s+[''"]Defender\|Edge\|Security Platform[''"]'
    Write-TestResult -TestName "Has architecture-agnostic update detection pattern" -Passed $hasArchAgnosticDetection -Message $(if (-not $hasArchAgnosticDetection) { "Expected pattern matching Defender|Edge|Security Platform" })

    # Check for filter bypass logic
    $hasFilterBypass = $content -match 'if\s*\(\s*\$isArchAgnosticUpdate\s+-and\s+\$Filter'
    Write-TestResult -TestName "Has filter bypass logic for architecture-agnostic updates" -Passed $hasFilterBypass

    # Check for explanatory comment
    $hasComment = $content -match "# Architecture-agnostic updates:.*Defender.*Edge.*Security Platform"
    Write-TestResult -TestName "Has explanatory comment about architecture-agnostic updates" -Passed $hasComment

    # Check that empty filter is passed for arch-agnostic updates
    $hasEmptyFilterCall = $content -match 'Get-KBLink.*-Filter\s+@\(\)'
    Write-TestResult -TestName "Passes empty filter for architecture-agnostic updates" -Passed $hasEmptyFilterCall
}
catch {
    Write-TestResult -TestName "Reading FFU.Updates module" -Passed $false -Message $_.Exception.Message
}

# =============================================================================
# Test 2: Verify pattern matching for architecture-agnostic updates
# =============================================================================
Write-Host ""
Write-Host "Testing architecture-agnostic update pattern matching..." -ForegroundColor Yellow

# Test cases: update names that should be detected as architecture-agnostic
$archAgnosticUpdates = @(
    "Update for Microsoft Defender Antivirus antimalware platform",
    "Windows Security Platform",
    "Microsoft Edge Update",
    "Defender Platform Update",
    "Edge Stable Channel Update"
)

foreach ($updateName in $archAgnosticUpdates) {
    $isArchAgnostic = $updateName -match 'Defender|Edge|Security Platform'
    Write-TestResult -TestName "Detects '$updateName' as architecture-agnostic" -Passed $isArchAgnostic
}

# Test cases: update names that should NOT be detected as architecture-agnostic (should use filter)
$regularUpdates = @(
    "2024-12 Cumulative Update for Windows 11",
    "Cumulative Update for .NET Framework",
    "Security Update for Microsoft Office",
    "Servicing Stack Update for Windows 11"
)

foreach ($updateName in $regularUpdates) {
    $isArchAgnostic = $updateName -match 'Defender|Edge|Security Platform'
    Write-TestResult -TestName "Does NOT detect '$updateName' as architecture-agnostic" -Passed (-not $isArchAgnostic)
}

# =============================================================================
# Test 3: Verify Save-KB function structure
# =============================================================================
Write-Host ""
Write-Host "Testing Save-KB function structure..." -ForegroundColor Yellow

try {
    $content = Get-Content -Path $UpdatesModule -Raw -ErrorAction Stop

    # Verify Save-KB exists
    $hasSaveKB = $content -match 'function\s+Save-KB'
    Write-TestResult -TestName "Save-KB function exists" -Passed $hasSaveKB

    # Verify Save-KB has Filter parameter
    $hasFilterParam = $content -match 'function\s+Save-KB[\s\S]*?\[string\[\]\]\$Filter'
    Write-TestResult -TestName "Save-KB has Filter parameter" -Passed $hasFilterParam

    # Verify Save-KB calls Get-KBLink
    $callsGetKBLink = $content -match 'Save-KB[\s\S]*?Get-KBLink\s+-Name'
    Write-TestResult -TestName "Save-KB calls Get-KBLink" -Passed $callsGetKBLink

    # Verify architecture detection logic exists (for files without arch in URL)
    $hasArchDetection = $content -match 'Get-PEArchitecture'
    Write-TestResult -TestName "Has PE architecture detection fallback" -Passed $hasArchDetection

    # Verify logging for architecture-agnostic updates
    $hasLogging = $content -match 'WriteLog.*architecture-agnostic.*Skipping.*filter'
    Write-TestResult -TestName "Logs when skipping filter for arch-agnostic updates" -Passed $hasLogging
}
catch {
    Write-TestResult -TestName "Analyzing Save-KB structure" -Passed $false -Message $_.Exception.Message
}

# =============================================================================
# Test 4: Verify Get-KBLink filter behavior
# =============================================================================
Write-Host ""
Write-Host "Testing Get-KBLink filter behavior..." -ForegroundColor Yellow

try {
    $content = Get-Content -Path $UpdatesModule -Raw -ErrorAction Stop

    # Verify Get-KBLink applies filter when provided
    $hasFilterLogic = $content -match 'Get-KBLink[\s\S]*?if\s*\(\s*\$Filter\s+-and\s+\$Filter\.Count\s+-gt\s+0\s*\)'
    Write-TestResult -TestName "Get-KBLink applies filter when provided" -Passed $hasFilterLogic

    # Verify Get-KBLink returns all results when no filter
    $hasNoFilterLogic = $content -match 'Get-KBLink[\s\S]*?else\s*\{[\s\S]*?# No filter - return first matching result'
    Write-TestResult -TestName "Get-KBLink returns first result when no filter" -Passed $hasNoFilterLogic
}
catch {
    Write-TestResult -TestName "Analyzing Get-KBLink filter behavior" -Passed $false -Message $_.Exception.Message
}

# =============================================================================
# Test 5: Functional test - simulate architecture-agnostic detection logic
# =============================================================================
Write-Host ""
Write-Host "Testing functional architecture detection..." -ForegroundColor Yellow

try {
    # Simulate the exact logic from Save-KB
    $testCases = @(
        @{ Name = "Update for Microsoft Defender Antivirus antimalware platform"; Expected = $true },
        @{ Name = "Windows Security Platform"; Expected = $true },
        @{ Name = "Microsoft Edge Update"; Expected = $true },
        @{ Name = "2024-12 Cumulative Update for Windows 11"; Expected = $false },
        @{ Name = "Servicing Stack Update"; Expected = $false }
    )

    foreach ($test in $testCases) {
        $kb = $test.Name
        $isArchAgnosticUpdate = $kb -match 'Defender|Edge|Security Platform'
        $expectedResult = $test.Expected

        $matches = $isArchAgnosticUpdate -eq $expectedResult
        Write-TestResult -TestName "Detection for '$kb' = $isArchAgnosticUpdate (expected $expectedResult)" -Passed $matches
    }

    # Simulate filter bypass logic
    $Filter = @('x64')
    $kb = "Update for Microsoft Defender Antivirus antimalware platform"
    $isArchAgnosticUpdate = $kb -match 'Defender|Edge|Security Platform'

    $shouldBypassFilter = $isArchAgnosticUpdate -and $Filter -and $Filter.Count -gt 0
    Write-TestResult -TestName "Filter bypass triggered for Defender with Filter=@('x64')" -Passed $shouldBypassFilter

    # Regular update should NOT bypass filter
    $kb = "2024-12 Cumulative Update for Windows 11"
    $isArchAgnosticUpdate = $kb -match 'Defender|Edge|Security Platform'
    $shouldNotBypassFilter = -not ($isArchAgnosticUpdate -and $Filter -and $Filter.Count -gt 0)
    Write-TestResult -TestName "Filter NOT bypassed for Cumulative Update" -Passed $shouldNotBypassFilter
}
catch {
    Write-TestResult -TestName "Functional architecture detection" -Passed $false -Message $_.Exception.Message
}

# =============================================================================
# Test Summary
# =============================================================================
Write-Host ""
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host "Total Tests: $($script:PassCount + $script:FailCount)" -ForegroundColor White
Write-Host "Passed: $script:PassCount" -ForegroundColor Green
Write-Host "Failed: $script:FailCount" -ForegroundColor $(if ($script:FailCount -gt 0) { "Red" } else { "Green" })
Write-Host ""

if ($script:FailCount -eq 0) {
    Write-Host "All tests passed! Architecture-agnostic update detection is correctly implemented." -ForegroundColor Green
    Write-Host ""
    Write-Host "Expected behavior:" -ForegroundColor Gray
    Write-Host "  - Defender, Edge, Security Platform updates: Skip architecture filter" -ForegroundColor Gray
    Write-Host "  - Other updates: Use architecture filter as specified" -ForegroundColor Gray
    Write-Host "  - Architecture is validated after download for arch-agnostic updates" -ForegroundColor Gray
    exit 0
} else {
    Write-Host "CRITICAL: Some tests failed!" -ForegroundColor Red
    Write-Host "Defender and Edge updates may fail to download due to filter mismatch." -ForegroundColor Red
    exit 1
}
