<#
.SYNOPSIS
    Regression test for Get-ShortenedWindowsSKU function and empty SKU parameter handling

.DESCRIPTION
    Tests that Get-ShortenedWindowsSKU never returns empty strings and handles all scenarios:
    1. All known SKU mappings work correctly
    2. Empty/null parameters are rejected with clear error messages
    3. Unknown SKUs return original name with warning (graceful fallback)
    4. Whitespace is properly trimmed before matching
    5. Pre-flight validation in BuildFFUVM.ps1 catches empty SKUs early
    6. New-FFU parameter validation provides defense-in-depth

    Prevents regression of: "Cannot bind argument to parameter 'ShortenedWindowsSKU' because it is an empty string"

.NOTES
    Author: FFU Builder Team
    Date: 2025-11-24
    Related: EMPTY_SHORTENED_SKU_ANALYSIS.md
#>

#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
$testResults = @()
$totalTests = 0
$passedTests = 0
$failedTests = 0

function Write-TestHeader {
    param([string]$Message)
    Write-Host "`n===============================================" -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "===============================================`n" -ForegroundColor Cyan
}

function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Message = ""
    )

    $script:totalTests++

    if ($Passed) {
        $script:passedTests++
        Write-Host "[PASS] $TestName" -ForegroundColor Green
        if ($Message) {
            Write-Host "       $Message" -ForegroundColor Gray
        }
        $script:testResults += [PSCustomObject]@{
            Test = $TestName
            Status = "PASS"
            Message = $Message
        }
    }
    else {
        $script:failedTests++
        Write-Host "[FAIL] $TestName" -ForegroundColor Red
        if ($Message) {
            Write-Host "       $Message" -ForegroundColor Yellow
        }
        $script:testResults += [PSCustomObject]@{
            Test = $TestName
            Status = "FAIL"
            Message = $Message
        }
    }
}

Write-TestHeader "Get-ShortenedWindowsSKU Regression Tests"
Write-Host "Current PowerShell: $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition) Edition)`n" -ForegroundColor Cyan

# Import FFU.Core module
try {
    $modulePath = Join-Path $PSScriptRoot "Modules\FFU.Core\FFU.Core.psm1"
    Import-Module $modulePath -Force -Global -ErrorAction Stop
    Write-Host "[INFO] FFU.Core module imported successfully`n" -ForegroundColor Cyan
}
catch {
    Write-Host "[FATAL] Failed to import FFU.Core module: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Test 1: All known SKU mappings
Write-Host "Test 1: Verify all known Windows SKU mappings" -ForegroundColor Yellow

$knownSKUs = @{
    'Core' = 'Home'
    'Home' = 'Home'
    'Pro' = 'Pro'
    'Enterprise' = 'Ent'
    'Education' = 'Edu'
    'Professional' = 'Pro'
    'ProfessionalEducation' = 'Pro_Edu'
    'ProfessionalWorkstation' = 'Pro_WKS'
    'ProfessionalWorkstationN' = 'Pro_WKS_N'
    'EnterpriseS' = 'Ent_LTSC'
    'EnterpriseN' = 'Ent_N'
    'CoreN' = 'Home_N'
    'CoreSingleLanguage' = 'Home_SL'
    'ProfessionalN' = 'Pro_N'
    'ProfessionalEducationN' = 'Pro_Edu_N'
    'EducationN' = 'Edu_N'
    'EnterpriseSN' = 'Ent_N_LTSC'
    'IoTEnterpriseS' = 'IoT_Ent_LTSC'
    'ServerDatacenter' = 'Srv_Dtc'
    'ServerStandard' = 'Srv_Std'
    'Datacenter' = 'Srv_Dtc'
    'Standard' = 'Srv_Std'
    'Standard (Desktop Experience)' = 'Srv_Std_DE'
    'Datacenter (Desktop Experience)' = 'Srv_Dtc_DE'
}

foreach ($sku in $knownSKUs.GetEnumerator()) {
    try {
        $result = Get-ShortenedWindowsSKU -WindowsSKU $sku.Key
        if ($result -eq $sku.Value) {
            Write-TestResult -TestName "SKU mapping: '$($sku.Key)' -> '$($sku.Value)'" -Passed $true
        }
        else {
            Write-TestResult -TestName "SKU mapping: '$($sku.Key)' -> '$($sku.Value)'" -Passed $false -Message "Got '$result' instead"
        }
    }
    catch {
        Write-TestResult -TestName "SKU mapping: '$($sku.Key)' -> '$($sku.Value)'" -Passed $false -Message $_.Exception.Message
    }
}

# Test 2: Empty parameter validation
Write-Host "`nTest 2: Verify empty parameter is rejected" -ForegroundColor Yellow

try {
    $result = Get-ShortenedWindowsSKU -WindowsSKU ""
    Write-TestResult -TestName "Empty string parameter rejected" -Passed $false -Message "Function should have thrown but returned: '$result'"
}
catch {
    if ($_.Exception.Message -match 'Cannot validate argument|is null or empty|Cannot bind argument') {
        Write-TestResult -TestName "Empty string parameter rejected" -Passed $true -Message "Correctly threw validation error"
    }
    else {
        Write-TestResult -TestName "Empty string parameter rejected" -Passed $false -Message "Wrong error: $($_.Exception.Message)"
    }
}

# Test 3: Null parameter validation
Write-Host "`nTest 3: Verify null parameter is rejected" -ForegroundColor Yellow

try {
    $result = Get-ShortenedWindowsSKU -WindowsSKU $null
    Write-TestResult -TestName "Null parameter rejected" -Passed $false -Message "Function should have thrown but returned: '$result'"
}
catch {
    if ($_.Exception.Message -match 'Cannot validate argument|is null or empty|Cannot bind argument') {
        Write-TestResult -TestName "Null parameter rejected" -Passed $true -Message "Correctly threw validation error"
    }
    else {
        Write-TestResult -TestName "Null parameter rejected" -Passed $false -Message "Wrong error: $($_.Exception.Message)"
    }
}

# Test 4: Unknown SKU returns original name (graceful fallback)
Write-Host "`nTest 4: Verify unknown SKUs return original name" -ForegroundColor Yellow

$unknownSKUs = @(
    'CustomEdition',
    'Windows 11 Home for Workstations',
    'Windows 11 Pro for Gamers',
    'InsiderPreview',
    'OEM Special Edition'
)

foreach ($unknownSKU in $unknownSKUs) {
    try {
        $result = Get-ShortenedWindowsSKU -WindowsSKU $unknownSKU -WarningAction SilentlyContinue
        if ($result -eq $unknownSKU) {
            Write-TestResult -TestName "Unknown SKU fallback: '$unknownSKU'" -Passed $true -Message "Returned original name"
        }
        else {
            Write-TestResult -TestName "Unknown SKU fallback: '$unknownSKU'" -Passed $false -Message "Expected '$unknownSKU', got '$result'"
        }
    }
    catch {
        Write-TestResult -TestName "Unknown SKU fallback: '$unknownSKU'" -Passed $false -Message $_.Exception.Message
    }
}

# Test 5: Whitespace trimming
Write-Host "`nTest 5: Verify whitespace is trimmed before matching" -ForegroundColor Yellow

$whitespaceTests = @{
    '  Pro  ' = 'Pro'
    "`tEnterprise`t" = 'Ent'
    " Education`n" = 'Edu'
    "`r`nProfessional`r`n" = 'Pro'
}

foreach ($test in $whitespaceTests.GetEnumerator()) {
    try {
        $result = Get-ShortenedWindowsSKU -WindowsSKU $test.Key
        if ($result -eq $test.Value) {
            Write-TestResult -TestName "Whitespace trim: '$($test.Key.Replace("`t", '\t').Replace("`n", '\n').Replace("`r", '\r'))'" -Passed $true
        }
        else {
            Write-TestResult -TestName "Whitespace trim: '$($test.Key.Replace("`t", '\t').Replace("`n", '\n').Replace("`r", '\r'))'" -Passed $false -Message "Expected '$($test.Value)', got '$result'"
        }
    }
    catch {
        Write-TestResult -TestName "Whitespace trim: '$($test.Key.Replace("`t", '\t').Replace("`n", '\n').Replace("`r", '\r'))'" -Passed $false -Message $_.Exception.Message
    }
}

# Test 6: Function never returns empty string
Write-Host "`nTest 6: Verify function never returns empty string" -ForegroundColor Yellow

$testCases = @('Pro', 'Enterprise', 'UnknownSKU', 'CustomEdition')

foreach ($testCase in $testCases) {
    try {
        $result = Get-ShortenedWindowsSKU -WindowsSKU $testCase -WarningAction SilentlyContinue
        if ([string]::IsNullOrWhiteSpace($result)) {
            Write-TestResult -TestName "Non-empty result for '$testCase'" -Passed $false -Message "Function returned empty/null: '$result'"
        }
        else {
            Write-TestResult -TestName "Non-empty result for '$testCase'" -Passed $true -Message "Returned: '$result'"
        }
    }
    catch {
        Write-TestResult -TestName "Non-empty result for '$testCase'" -Passed $false -Message $_.Exception.Message
    }
}

# Test 7: Verify pre-flight validation exists in BuildFFUVM.ps1
Write-Host "`nTest 7: Verify pre-flight validation in BuildFFUVM.ps1" -ForegroundColor Yellow

try {
    $buildScriptPath = Join-Path $PSScriptRoot "BuildFFUVM.ps1"
    $buildScriptContent = Get-Content $buildScriptPath -Raw

    # Check for validation before Get-ShortenedWindowsSKU call
    if ($buildScriptContent -match '\[string\]::IsNullOrWhiteSpace\(\$WindowsSKU\)') {
        Write-TestResult -TestName "Pre-flight validation exists" -Passed $true -Message "Found WindowsSKU validation check"
    }
    else {
        Write-TestResult -TestName "Pre-flight validation exists" -Passed $false -Message "Validation check not found"
    }

    # Check for Get-ShortenedWindowsSKU call
    if ($buildScriptContent -match 'Get-ShortenedWindowsSKU\s+-WindowsSKU') {
        Write-TestResult -TestName "Get-ShortenedWindowsSKU called correctly" -Passed $true
    }
    else {
        Write-TestResult -TestName "Get-ShortenedWindowsSKU called correctly" -Passed $false -Message "Function call not found"
    }

    # Check for enhanced logging
    if ($buildScriptContent -match "Shortening Windows SKU.*'.*WindowsSKU") {
        Write-TestResult -TestName "Enhanced logging with quoted values" -Passed $true
    }
    else {
        Write-TestResult -TestName "Enhanced logging with quoted values" -Passed $false -Message "Enhanced logging not found"
    }
}
catch {
    Write-TestResult -TestName "BuildFFUVM.ps1 validation check" -Passed $false -Message $_.Exception.Message
}

# Test 8: Verify New-FFU parameter validation
Write-Host "`nTest 8: Verify New-FFU parameter validation (defense-in-depth)" -ForegroundColor Yellow

try {
    $imagingModulePath = Join-Path $PSScriptRoot "Modules\FFU.Imaging\FFU.Imaging.psm1"
    $imagingModuleContent = Get-Content $imagingModulePath -Raw

    # Check for ValidateNotNullOrEmpty on ShortenedWindowsSKU parameter
    if ($imagingModuleContent -match '\[ValidateNotNullOrEmpty\(\)\]\s*\[string\]\$ShortenedWindowsSKU') {
        Write-TestResult -TestName "New-FFU has parameter validation" -Passed $true -Message "Found [ValidateNotNullOrEmpty()] attribute"
    }
    else {
        Write-TestResult -TestName "New-FFU has parameter validation" -Passed $false -Message "Validation attribute not found"
    }

    # Check parameter is still mandatory
    if ($imagingModuleContent -match '\[Parameter\(Mandatory\s*=\s*\$true\)\]\s*\[ValidateNotNullOrEmpty\(\)\]\s*\[string\]\$ShortenedWindowsSKU') {
        Write-TestResult -TestName "ShortenedWindowsSKU is mandatory" -Passed $true
    }
    else {
        Write-TestResult -TestName "ShortenedWindowsSKU is mandatory" -Passed $false -Message "Mandatory attribute not found or incorrect order"
    }
}
catch {
    Write-TestResult -TestName "New-FFU parameter validation check" -Passed $false -Message $_.Exception.Message
}

# Test 9: Verify Get-ShortenedWindowsSKU has parameter validation
Write-Host "`nTest 9: Verify Get-ShortenedWindowsSKU function attributes" -ForegroundColor Yellow

try {
    $coreModulePath = Join-Path $PSScriptRoot "Modules\FFU.Core\FFU.Core.psm1"
    $coreModuleContent = Get-Content $coreModulePath -Raw

    # Check for [CmdletBinding()]
    if ($coreModuleContent -match 'function Get-ShortenedWindowsSKU\s*\{[^\}]*\[CmdletBinding\(\)\]') {
        Write-TestResult -TestName "Function has [CmdletBinding()]" -Passed $true
    }
    else {
        Write-TestResult -TestName "Function has [CmdletBinding()]" -Passed $false -Message "Attribute not found"
    }

    # Check for parameter validation
    if ($coreModuleContent -match 'function Get-ShortenedWindowsSKU[^\}]*\[ValidateNotNullOrEmpty\(\)\]') {
        Write-TestResult -TestName "Function has parameter validation" -Passed $true
    }
    else {
        Write-TestResult -TestName "Function has parameter validation" -Passed $false -Message "Validation not found"
    }

    # Check for default case
    if ($coreModuleContent -match 'default\s*\{\s*Write-Warning') {
        Write-TestResult -TestName "Function has default case" -Passed $true
    }
    else {
        Write-TestResult -TestName "Function has default case" -Passed $false -Message "Default case not found"
    }

    # Check for .Trim() call
    if ($coreModuleContent -match '\$WindowsSKU\s*=\s*\$WindowsSKU\.Trim\(\)') {
        Write-TestResult -TestName "Function trims whitespace" -Passed $true
    }
    else {
        Write-TestResult -TestName "Function trims whitespace" -Passed $false -Message "Trim() call not found"
    }

    # Check for warning in default case
    if ($coreModuleContent -match 'Write-Warning\s+"Unknown Windows SKU') {
        Write-TestResult -TestName "Function logs warning for unknown SKUs" -Passed $true
    }
    else {
        Write-TestResult -TestName "Function logs warning for unknown SKUs" -Passed $false -Message "Warning log not found"
    }
}
catch {
    Write-TestResult -TestName "Get-ShortenedWindowsSKU function attributes check" -Passed $false -Message $_.Exception.Message
}

# Test 10: Edge case testing
Write-Host "`nTest 10: Edge case handling" -ForegroundColor Yellow

# Test with very long SKU name
try {
    $longSKU = "Windows 11 Enterprise Special OEM Custom Edition with Advanced Security Features"
    $result = Get-ShortenedWindowsSKU -WindowsSKU $longSKU -WarningAction SilentlyContinue
    if ($result -eq $longSKU) {
        Write-TestResult -TestName "Very long unknown SKU handled" -Passed $true -Message "Returned original: $($longSKU.Substring(0, 30))..."
    }
    else {
        Write-TestResult -TestName "Very long unknown SKU handled" -Passed $false -Message "Unexpected result: '$result'"
    }
}
catch {
    Write-TestResult -TestName "Very long unknown SKU handled" -Passed $false -Message $_.Exception.Message
}

# Test with special characters
try {
    $specialSKU = "Pro-N_Special/Edition (x64)"
    $result = Get-ShortenedWindowsSKU -WindowsSKU $specialSKU -WarningAction SilentlyContinue
    if ($result -eq $specialSKU) {
        Write-TestResult -TestName "Special characters in SKU handled" -Passed $true
    }
    else {
        Write-TestResult -TestName "Special characters in SKU handled" -Passed $false -Message "Expected '$specialSKU', got '$result'"
    }
}
catch {
    Write-TestResult -TestName "Special characters in SKU handled" -Passed $false -Message $_.Exception.Message
}

# Test case sensitivity
try {
    $lowerSKU = "pro"
    $result = Get-ShortenedWindowsSKU -WindowsSKU $lowerSKU
    # PowerShell switch is case-insensitive by default, so "pro" should match "Pro"
    if ($result -eq "Pro") {
        Write-TestResult -TestName "Case-insensitive matching works" -Passed $true -Message "Lowercase 'pro' matched to 'Pro'"
    }
    else {
        Write-TestResult -TestName "Case-insensitive matching works" -Passed $false -Message "Expected 'Pro', got '$result'"
    }
}
catch {
    Write-TestResult -TestName "Case-insensitive matching works" -Passed $false -Message $_.Exception.Message
}

# Summary
Write-TestHeader "Test Summary"

Write-Host "Total Tests: $totalTests" -ForegroundColor White
Write-Host "Passed: $passedTests" -ForegroundColor Green
Write-Host "Failed: $failedTests" -ForegroundColor $(if ($failedTests -gt 0) { 'Red' } else { 'Green' })
$passRate = if ($totalTests -gt 0) { [math]::Round(($passedTests / $totalTests) * 100, 1) } else { 0 }
Write-Host "Pass Rate: $passRate%`n" -ForegroundColor $(if ($passRate -eq 100) { 'Green' } elseif ($passRate -ge 80) { 'Yellow' } else { 'Red' })

if ($failedTests -gt 0) {
    Write-Host "`nFailed Tests:" -ForegroundColor Red
    $testResults | Where-Object { $_.Status -eq "FAIL" } | Format-Table -AutoSize
    Write-Host "`n[OVERALL: FAIL] Some Get-ShortenedWindowsSKU tests failed" -ForegroundColor Red
    Write-Host "The empty SKU fix may not work correctly. Review failures above.`n" -ForegroundColor Yellow
    exit 1
}
else {
    Write-Host "`n[OVERALL: PASS] All Get-ShortenedWindowsSKU tests passed!`n" -ForegroundColor Green
    Write-Host "Key validations:" -ForegroundColor White
    Write-Host "  [OK] All $($knownSKUs.Count) known SKU mappings work correctly" -ForegroundColor Green
    Write-Host "  [OK] Empty/null parameters are rejected with clear errors" -ForegroundColor Green
    Write-Host "  [OK] Unknown SKUs return original name (graceful fallback)" -ForegroundColor Green
    Write-Host "  [OK] Whitespace is trimmed before matching" -ForegroundColor Green
    Write-Host "  [OK] Function never returns empty string" -ForegroundColor Green
    Write-Host "  [OK] Pre-flight validation in BuildFFUVM.ps1" -ForegroundColor Green
    Write-Host "  [OK] Defense-in-depth validation in New-FFU parameter" -ForegroundColor Green
    Write-Host "  [OK] Edge cases handled correctly (long names, special chars, case)" -ForegroundColor Green
    Write-Host "`nThe empty ShortenedWindowsSKU parameter bug is fixed and validated!`n" -ForegroundColor Cyan
    exit 0
}
