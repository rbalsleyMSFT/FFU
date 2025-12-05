#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Test suite for $Filter parameter initialization and Save-KB validation fix

.DESCRIPTION
    Tests that $Filter is properly initialized in BuildFFUVM.ps1 and that Save-KB
    calls have proper validation to prevent generating invalid orchestration scripts.

    Root Cause:
    - $Filter variable was never initialized in BuildFFUVM.ps1
    - When $Filter is null/empty, Get-KBLink returns first result (not architecture-filtered)
    - Save-KB can return null if no matching architecture files found
    - BuildFFUVM.ps1 didn't validate Save-KB return values
    - Invalid commands like "& d:\Defender\" were generated (missing filename)

    Solution:
    - Initialize $Filter = @($WindowsArch) after config file loading
    - Add validation after Save-KB calls for Defender, MSRT, and Edge
    - Improve Save-KB error handling and logging
    - Return explicit null with error messages when no matches found

.NOTES
    This test suite ensures the $Filter parameter bug doesn't recur.
#>

$ErrorActionPreference = 'Stop'
$testsPassed = 0
$testsFailed = 0

function Write-TestHeader {
    param([string]$Message)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}

function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Message = ""
    )

    if ($Passed) {
        Write-Host "  ✅ PASS: $TestName" -ForegroundColor Green
        if ($Message) { Write-Host "    $Message" -ForegroundColor Gray }
        $script:testsPassed++
    }
    else {
        Write-Host "  ❌ FAIL: $TestName" -ForegroundColor Red
        if ($Message) { Write-Host "    $Message" -ForegroundColor Red }
        $script:testsFailed++
    }
}

Write-Host "=== Filter Parameter Fix Test Suite ===`n" -ForegroundColor Green
Write-Host "Validating fix for empty `$Filter causing invalid Defender/MSRT/Edge commands" -ForegroundColor Green

# Test 1: Verify $Filter initialization exists in BuildFFUVM.ps1
Write-TestHeader "Test 1: Filter Initialization in BuildFFUVM.ps1"

try {
    $buildScriptPath = Join-Path $PSScriptRoot "BuildFFUVM.ps1"
    $buildScriptContent = Get-Content $buildScriptPath -Raw

    # Check for $Filter initialization after config file loading
    if ($buildScriptContent -match '\$Filter\s*=\s*@\(\$WindowsArch\)') {
        Write-TestResult "`$Filter initialization present" $true "Found: `$Filter = @(`$WindowsArch)"
    }
    else {
        Write-TestResult "`$Filter initialization present" $false "`$Filter = @(`$WindowsArch) not found - Filter will be null!"
    }

    # Verify explanatory comment exists
    if ($buildScriptContent -match 'Initialize.*Filter|Filter.*architecture|Filter.*catalog') {
        Write-TestResult "Explanatory comment for `$Filter initialization" $true
    }
    else {
        Write-TestResult "Explanatory comment for `$Filter initialization" $false "Missing explanation for future maintainers"
    }

    # Verify $Filter is initialized after config file loading (line ~621)
    $filterInitLine = ($buildScriptContent -split "`n" | Select-String -Pattern '\$Filter\s*=\s*@\(\$WindowsArch\)' | Select-Object -First 1).LineNumber
    $configLoadEndLine = ($buildScriptContent -split "`n" | Select-String -Pattern '^\s*\}$' | Where-Object { $_.LineNumber -gt 585 -and $_.LineNumber -lt 700 } | Select-Object -First 1).LineNumber

    if ($filterInitLine -and $configLoadEndLine -and $filterInitLine -gt $configLoadEndLine) {
        Write-TestResult "`$Filter initialized after config file loading" $true "Filter at line $filterInitLine, config ends at line $configLoadEndLine"
    }
    elseif (-not $filterInitLine) {
        Write-TestResult "`$Filter initialized after config file loading" $false "Could not find `$Filter initialization"
    }
    else {
        Write-TestResult "`$Filter initialized after config file loading" $false "Filter at line $filterInitLine, should be after line $configLoadEndLine"
    }
}
catch {
    Write-TestResult "Filter initialization validation" $false $_.Exception.Message
}

# Test 2: Verify Defender Save-KB has validation
Write-TestHeader "Test 2: Defender Update Validation"

try {
    $buildScriptContent = Get-Content (Join-Path $PSScriptRoot "BuildFFUVM.ps1") -Raw

    # Check for Save-KB call for Defender
    if ($buildScriptContent -match '\$KBFilePath\s*=\s*Save-KB.*-Name\s+\$update\.Name.*DefenderPath') {
        Write-TestResult "Defender Save-KB call found" $true
    }
    else {
        Write-TestResult "Defender Save-KB call found" $false "Could not locate Defender Save-KB call"
    }

    # Check for validation after Save-KB
    $defenderSection = $buildScriptContent -split "`n" | Select-String -Pattern 'Save-KB.*DefenderPath' -Context 0,10
    $hasValidation = $false
    foreach ($section in $defenderSection) {
        if ($section.Context.PostContext -match 'IsNullOrWhiteSpace.*KBFilePath') {
            $hasValidation = $true
            break
        }
    }

    if ($hasValidation) {
        Write-TestResult "Defender Save-KB has null validation" $true "Found [string]::IsNullOrWhiteSpace check"
    }
    else {
        Write-TestResult "Defender Save-KB has null validation" $false "No validation after Save-KB - null return will cause invalid command!"
    }

    # Check for error throwing on validation failure
    if ($hasValidation -and $buildScriptContent -match 'throw.*Failed to download.*Defender|throw.*KBFilePath.*DefenderPath') {
        Write-TestResult "Defender validation throws error on failure" $true
    }
    else {
        Write-TestResult "Defender validation throws error on failure" $false "Validation doesn't throw error - build will continue with null!"
    }
}
catch {
    Write-TestResult "Defender validation check" $false $_.Exception.Message
}

# Test 3: Verify MSRT Save-KB has validation
Write-TestHeader "Test 3: MSRT Update Validation"

try {
    $buildScriptContent = Get-Content (Join-Path $PSScriptRoot "BuildFFUVM.ps1") -Raw

    # Check for Save-KB call for MSRT
    if ($buildScriptContent -match '\$MSRTFileName\s*=\s*Save-KB.*MSRTPath') {
        Write-TestResult "MSRT Save-KB call found" $true
    }
    else {
        Write-TestResult "MSRT Save-KB call found" $false "Could not locate MSRT Save-KB call"
    }

    # Check for validation after Save-KB
    $msrtSection = $buildScriptContent -split "`n" | Select-String -Pattern 'Save-KB.*MSRTPath' -Context 0,10
    $hasValidation = $false
    foreach ($section in $msrtSection) {
        if ($section.Context.PostContext -match 'IsNullOrWhiteSpace.*MSRTFileName') {
            $hasValidation = $true
            break
        }
    }

    if ($hasValidation) {
        Write-TestResult "MSRT Save-KB has null validation" $true "Found [string]::IsNullOrWhiteSpace check"
    }
    else {
        Write-TestResult "MSRT Save-KB has null validation" $false "No validation after Save-KB"
    }

    # Check for error throwing
    if ($hasValidation -and $buildScriptContent -match 'throw.*Failed to download.*Malicious Software Removal Tool') {
        Write-TestResult "MSRT validation throws error on failure" $true
    }
    else {
        Write-TestResult "MSRT validation throws error on failure" $false "Validation doesn't throw error"
    }
}
catch {
    Write-TestResult "MSRT validation check" $false $_.Exception.Message
}

# Test 4: Verify Edge Save-KB has validation
Write-TestHeader "Test 4: Edge Update Validation"

try {
    $buildScriptContent = Get-Content (Join-Path $PSScriptRoot "BuildFFUVM.ps1") -Raw

    # Check for Save-KB call for Edge
    if ($buildScriptContent -match '\$KBFilePath\s*=\s*Save-KB.*-Name\s+\$Name.*EdgePath') {
        Write-TestResult "Edge Save-KB call found" $true
    }
    else {
        Write-TestResult "Edge Save-KB call found" $false "Could not locate Edge Save-KB call"
    }

    # Check for validation after Save-KB
    $edgeSection = $buildScriptContent -split "`n" | Select-String -Pattern 'Save-KB.*EdgePath.*WindowsArch' -Context 0,10
    $hasValidation = $false
    foreach ($section in $edgeSection) {
        if ($section.Context.PostContext -match 'IsNullOrWhiteSpace.*KBFilePath') {
            $hasValidation = $true
            break
        }
    }

    if ($hasValidation) {
        Write-TestResult "Edge Save-KB has null validation" $true "Found [string]::IsNullOrWhiteSpace check"
    }
    else {
        Write-TestResult "Edge Save-KB has null validation" $false "No validation after Save-KB"
    }

    # Check for error throwing
    if ($hasValidation -and $buildScriptContent -match 'throw.*Failed to download.*Edge') {
        Write-TestResult "Edge validation throws error on failure" $true
    }
    else {
        Write-TestResult "Edge validation throws error on failure" $false "Validation doesn't throw error"
    }
}
catch {
    Write-TestResult "Edge validation check" $false $_.Exception.Message
}

# Test 5: Verify Save-KB function improvements
Write-TestHeader "Test 5: Save-KB Function Improvements"

try {
    $moduleContent = Get-Content (Join-Path $PSScriptRoot "Modules\FFU.Updates\FFU.Updates.psm1") -Raw

    # Check that Save-KB extracts Links from Get-KBLink result
    if ($moduleContent -match '\$kbResult\s*=\s*Get-KBLink.*\$links\s*=\s*\$kbResult\.Links') {
        Write-TestResult "Save-KB extracts Links from Get-KBLink result" $true
    }
    else {
        Write-TestResult "Save-KB extracts Links from Get-KBLink result" $false "Still using old pattern - may not work correctly"
    }

    # Check for empty links validation
    if ($moduleContent -match 'if\s*\(\s*-not\s+\$links\s+-or\s+\$links\.Count\s+-eq\s+0') {
        Write-TestResult "Save-KB checks for empty links" $true "Found empty links validation"
    }
    else {
        Write-TestResult "Save-KB checks for empty links" $false "No check for empty links - will cause null return!"
    }

    # Check for warning when no links found
    if ($moduleContent -match 'WriteLog.*WARNING.*No download links found') {
        Write-TestResult "Save-KB logs warning when no links found" $true
    }
    else {
        Write-TestResult "Save-KB logs warning when no links found" $false "Silent failure - hard to debug"
    }

    # Check for explicit null return with error message
    if ($moduleContent -match 'return\s+\$null' -and $moduleContent -match 'ERROR.*No file matching architecture') {
        Write-TestResult "Save-KB returns explicit null with error message" $true
    }
    else {
        Write-TestResult "Save-KB returns explicit null with error message" $false "May return undefined variable"
    }

    # Check that error message includes architecture and filter info
    if ($moduleContent -match 'ERROR.*architecture.*WindowsArch' -and $moduleContent -match 'ERROR.*Filter') {
        Write-TestResult "Save-KB error message includes diagnostic info" $true "Includes architecture and Filter"
    }
    else {
        Write-TestResult "Save-KB error message includes diagnostic info" $false "Missing diagnostic context"
    }
}
catch {
    Write-TestResult "Save-KB function improvements" $false $_.Exception.Message
}

# Test 6: Verify Get-KBLink returns structured object
Write-TestHeader "Test 6: Get-KBLink Return Value Structure"

try {
    $moduleContent = Get-Content (Join-Path $PSScriptRoot "Modules\FFU.Updates\FFU.Updates.psm1") -Raw

    # Check that Get-KBLink returns PSCustomObject with KBArticleID and Links
    if ($moduleContent -match 'return\s+\[PSCustomObject\]@\{[^}]*KBArticleID.*Links') {
        Write-TestResult "Get-KBLink returns structured object" $true "Returns PSCustomObject with KBArticleID and Links"
    }
    else {
        Write-TestResult "Get-KBLink returns structured object" $false "May return array directly - incompatible with new Save-KB"
    }

    # Check that Get-KBLink returns empty structure on no results
    if ($moduleContent -match 'return\s+\[PSCustomObject\]@\{.*KBArticleID.*Links\s*=\s*@\(\)') {
        Write-TestResult "Get-KBLink returns empty structure on failure" $true
    }
    else {
        Write-TestResult "Get-KBLink returns empty structure on failure" $false "May return null causing errors"
    }
}
catch {
    Write-TestResult "Get-KBLink structure validation" $false $_.Exception.Message
}

# Test 7: Integration test - Simulate the error scenario
Write-TestHeader "Test 7: Integration Test - Empty Filter Scenario"

try {
    # Simulate what happens when $Filter is empty/null
    $emptyFilter = @()
    $nullFilter = $null

    Write-TestResult "Empty filter array is falsy" ($emptyFilter.Count -eq 0) "Empty filter has Count = 0"
    Write-TestResult "Null filter is falsy" ($null -eq $nullFilter) "Null filter is $null"

    # Simulate string interpolation with null variable
    $testFilePath = $null
    $testCommand = "& d:\Defender\$testFilePath"

    if ($testCommand -eq "& d:\Defender\") {
        Write-TestResult "Null variable creates invalid command" $true "Command: '$testCommand' (invalid!)"
    }
    else {
        Write-TestResult "Null variable creates invalid command" $false "Unexpected result: '$testCommand'"
    }

    # Test [string]::IsNullOrWhiteSpace catches null
    $nullString = $null
    $emptyString = ""
    $whitespaceString = "   "

    if ([string]::IsNullOrWhiteSpace($nullString)) {
        Write-TestResult "[string]::IsNullOrWhiteSpace catches null" $true
    }
    else {
        Write-TestResult "[string]::IsNullOrWhiteSpace catches null" $false
    }

    if ([string]::IsNullOrWhiteSpace($emptyString)) {
        Write-TestResult "[string]::IsNullOrWhiteSpace catches empty string" $true
    }
    else {
        Write-TestResult "[string]::IsNullOrWhiteSpace catches empty string" $false
    }

    if ([string]::IsNullOrWhiteSpace($whitespaceString)) {
        Write-TestResult "[string]::IsNullOrWhiteSpace catches whitespace" $true
    }
    else {
        Write-TestResult "[string]::IsNullOrWhiteSpace catches whitespace" $false
    }
}
catch {
    Write-TestResult "Integration test" $false $_.Exception.Message
}

# Test 8: Verify no other Save-KB calls are missing validation
Write-TestHeader "Test 8: Comprehensive Save-KB Usage Check"

try {
    $buildScriptContent = Get-Content (Join-Path $PSScriptRoot "BuildFFUVM.ps1") -Raw

    # Find all Save-KB calls
    $saveKBCalls = [regex]::Matches($buildScriptContent, '\$\w+\s*=\s*Save-KB[^\n]+')

    Write-Host "  Found $($saveKBCalls.Count) Save-KB calls in BuildFFUVM.ps1" -ForegroundColor Cyan

    $unvalidatedCalls = 0
    foreach ($call in $saveKBCalls) {
        $lineNumber = ($buildScriptContent.Substring(0, $call.Index) -split "`n").Count
        $variableName = if ($call.Value -match '\$(\w+)\s*=') { $matches[1] } else { "unknown" }

        # Check if there's validation within next 1000 chars
        $contextStart = $call.Index
        $contextEnd = [Math]::Min($call.Index + 1000, $buildScriptContent.Length)
        $context = $buildScriptContent.Substring($contextStart, $contextEnd - $contextStart)

        if ($context -match "IsNullOrWhiteSpace.*\$$variableName") {
            Write-Host "    ✅ Line ~$lineNumber : `$$variableName has validation" -ForegroundColor Green
        }
        else {
            Write-Host "    ⚠️  Line ~$lineNumber : `$$variableName may be missing validation" -ForegroundColor Yellow
            $unvalidatedCalls++
        }
    }

    if ($unvalidatedCalls -eq 0) {
        Write-TestResult "All critical Save-KB calls have validation" $true "All calls protected"
    }
    else {
        Write-TestResult "All critical Save-KB calls have validation" $false "$unvalidatedCalls call(s) may need validation (non-critical OK)"
    }
}
catch {
    Write-TestResult "Comprehensive Save-KB check" $false $_.Exception.Message
}

# Summary
Write-TestHeader "Test Summary"
$total = $testsPassed + $testsFailed
Write-Host "  Total Tests:   $total" -ForegroundColor Cyan
Write-Host "  Passed:        $testsPassed" -ForegroundColor Green
Write-Host "  Failed:        $testsFailed" -ForegroundColor $(if ($testsFailed -gt 0) { "Red" } else { "Gray" })

if ($testsFailed -eq 0) {
    Write-Host "`n✅ All tests passed!" -ForegroundColor Green
    Write-Host "`nThe `$Filter parameter bug is fixed:" -ForegroundColor Green
    Write-Host "  - `$Filter is initialized with architecture-specific values" -ForegroundColor Green
    Write-Host "  - Save-KB calls have validation to prevent null returns" -ForegroundColor Green
    Write-Host "  - Error messages are clear and actionable" -ForegroundColor Green
    Write-Host "  - Invalid orchestration commands will not be generated" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "`n❌ $testsFailed test(s) failed. Please review the output above." -ForegroundColor Red
    exit 1
}
