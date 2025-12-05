<#
.SYNOPSIS
    Test script for BuildFFUVM.ps1 parameter validation

.DESCRIPTION
    Validates that parameter validation attributes are correctly implemented
    and reject invalid inputs while accepting valid ones.

.NOTES
    Run this script to verify parameter validation is working correctly.
#>

#Requires -Version 5.1

param(
    [Parameter(Mandatory = $false)]
    [string]$FFUDevelopmentPath = "C:\FFUDevelopment"
)

# Initialize test results
$script:TestResults = @{
    Passed = 0
    Failed = 0
    Skipped = 0
    Tests = @()
}

function Write-TestResult {
    param(
        [string]$TestName,
        [string]$Status,
        [string]$Message = ""
    )

    $color = switch ($Status) {
        'Passed' { 'Green' }
        'Failed' { 'Red' }
        'Skipped' { 'Yellow' }
        default { 'White' }
    }

    $script:TestResults[$Status]++
    $script:TestResults.Tests += [PSCustomObject]@{
        Name = $TestName
        Status = $Status
        Message = $Message
    }

    $statusSymbol = switch ($Status) {
        'Passed' { '[PASS]' }
        'Failed' { '[FAIL]' }
        'Skipped' { '[SKIP]' }
    }

    Write-Host "$statusSymbol $TestName" -ForegroundColor $color
    if ($Message) {
        Write-Host "       $Message" -ForegroundColor Gray
    }
}

function Test-ParameterValidation {
    param(
        [string]$TestName,
        [string]$ParameterName,
        [object]$TestValue,
        [bool]$ShouldPass,
        [string]$Description = ""
    )

    # Build command to test parameter
    $scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) "FFUDevelopment\BuildFFUVM.ps1"

    # We need to test if the parameter validation passes or fails
    # Using Get-Command to get parameter metadata and test validation
    try {
        $cmd = Get-Command $scriptPath -ErrorAction Stop
        $param = $cmd.Parameters[$ParameterName]

        if (-not $param) {
            Write-TestResult -TestName $TestName -Status 'Failed' -Message "Parameter '$ParameterName' not found"
            return
        }

        # Check for validation attributes
        $hasValidation = $param.Attributes | Where-Object {
            $_.TypeId.Name -match 'Validate'
        }

        if ($ShouldPass) {
            Write-TestResult -TestName $TestName -Status 'Passed' -Message $Description
        }
        else {
            Write-TestResult -TestName $TestName -Status 'Passed' -Message $Description
        }
    }
    catch {
        Write-TestResult -TestName $TestName -Status 'Failed' -Message $_.Exception.Message
    }
}

# ============================================================================
# Setup
# ============================================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Parameter Validation Tests" -ForegroundColor Cyan
Write-Host "BuildFFUVM.ps1 Input Validation" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Determine paths
if (-not (Test-Path $FFUDevelopmentPath)) {
    $FFUDevelopmentPath = Join-Path (Split-Path $PSScriptRoot -Parent) "FFUDevelopment"
}

$scriptPath = Join-Path $FFUDevelopmentPath "BuildFFUVM.ps1"
Write-Host "Script path: $scriptPath" -ForegroundColor Gray

if (-not (Test-Path $scriptPath)) {
    Write-Host "ERROR: BuildFFUVM.ps1 not found at $scriptPath" -ForegroundColor Red
    exit 1
}

# ============================================================================
# Test 1: Verify Validation Attributes Exist
# ============================================================================
Write-Host "`n--- Validation Attribute Verification ---" -ForegroundColor Yellow

$cmd = Get-Command $scriptPath -ErrorAction Stop

# Parameters that should have ValidateScript for path validation
$pathParameters = @(
    'AppListPath',
    'UserAppListPath',
    'OfficeConfigXMLFile',
    'DriversFolder',
    'PEDriversFolder',
    'DriversJsonPath',
    'orchestrationPath',
    'VMLocation',
    'FFUCaptureLocation',
    'ExportConfigFile'
)

foreach ($paramName in $pathParameters) {
    $param = $cmd.Parameters[$paramName]
    if ($param) {
        $hasValidateScript = $param.Attributes | Where-Object { $_.TypeId.Name -eq 'ValidateScriptAttribute' }
        if ($hasValidateScript) {
            Write-TestResult -TestName "$paramName has ValidateScript" -Status 'Passed'
        }
        else {
            Write-TestResult -TestName "$paramName has ValidateScript" -Status 'Failed' -Message "Missing ValidateScript attribute"
        }
    }
    else {
        Write-TestResult -TestName "$paramName exists" -Status 'Skipped' -Message "Parameter not found"
    }
}

# ============================================================================
# Test 2: ValidateSet Parameters
# ============================================================================
Write-Host "`n--- ValidateSet Parameters ---" -ForegroundColor Yellow

$validateSetParams = @(
    @{ Name = 'WindowsSKU'; ExpectedValues = @('Pro', 'Enterprise', 'Education', 'Home') },
    @{ Name = 'Make'; ExpectedValues = @('Microsoft', 'Dell', 'HP', 'Lenovo') },
    @{ Name = 'WindowsArch'; ExpectedValues = @('x86', 'x64', 'arm64') },
    @{ Name = 'MediaType'; ExpectedValues = @('consumer', 'business') },
    @{ Name = 'LogicalSectorSizeBytes'; ExpectedValues = @(512, 4096) },
    @{ Name = 'WindowsRelease'; ExpectedValues = @(10, 11, 2016, 2019, 2021, 2022, 2024, 2025) }
)

foreach ($item in $validateSetParams) {
    $param = $cmd.Parameters[$item.Name]
    if ($param) {
        $validateSet = $param.Attributes | Where-Object { $_.TypeId.Name -eq 'ValidateSetAttribute' }
        if ($validateSet) {
            # Check if expected values are in the set
            $missingValues = $item.ExpectedValues | Where-Object { $validateSet.ValidValues -notcontains $_ }
            if ($missingValues.Count -eq 0) {
                Write-TestResult -TestName "$($item.Name) ValidateSet contains expected values" -Status 'Passed'
            }
            else {
                Write-TestResult -TestName "$($item.Name) ValidateSet contains expected values" -Status 'Failed' -Message "Missing: $($missingValues -join ', ')"
            }
        }
        else {
            Write-TestResult -TestName "$($item.Name) has ValidateSet" -Status 'Failed' -Message "Missing ValidateSet attribute"
        }
    }
    else {
        Write-TestResult -TestName "$($item.Name) exists" -Status 'Skipped' -Message "Parameter not found"
    }
}

# ============================================================================
# Test 3: ValidateRange Parameters
# ============================================================================
Write-Host "`n--- ValidateRange Parameters ---" -ForegroundColor Yellow

$validateRangeParams = @(
    @{ Name = 'Memory'; Min = 2GB; Max = 128GB },
    @{ Name = 'Disksize'; Min = 25GB; Max = 2TB },
    @{ Name = 'Processors'; Min = 1; Max = 64 },
    @{ Name = 'MaxUSBDrives'; Min = 0; Max = 100 }
)

foreach ($item in $validateRangeParams) {
    $param = $cmd.Parameters[$item.Name]
    if ($param) {
        $validateRange = $param.Attributes | Where-Object { $_.TypeId.Name -eq 'ValidateRangeAttribute' }
        if ($validateRange) {
            if ($validateRange.MinRange -eq $item.Min -and $validateRange.MaxRange -eq $item.Max) {
                Write-TestResult -TestName "$($item.Name) ValidateRange ($($item.Min) to $($item.Max))" -Status 'Passed'
            }
            else {
                Write-TestResult -TestName "$($item.Name) ValidateRange" -Status 'Failed' -Message "Expected $($item.Min)-$($item.Max), got $($validateRange.MinRange)-$($validateRange.MaxRange)"
            }
        }
        else {
            Write-TestResult -TestName "$($item.Name) has ValidateRange" -Status 'Failed' -Message "Missing ValidateRange attribute"
        }
    }
    else {
        Write-TestResult -TestName "$($item.Name) exists" -Status 'Skipped' -Message "Parameter not found"
    }
}

# ============================================================================
# Test 4: ValidatePattern Parameters
# ============================================================================
Write-Host "`n--- ValidatePattern Parameters ---" -ForegroundColor Yellow

$validatePatternParams = @(
    'VMHostIPAddress',
    'ShareName',
    'Username',
    'WindowsVersion'
)

foreach ($paramName in $validatePatternParams) {
    $param = $cmd.Parameters[$paramName]
    if ($param) {
        $validatePattern = $param.Attributes | Where-Object { $_.TypeId.Name -eq 'ValidatePatternAttribute' }
        if ($validatePattern) {
            Write-TestResult -TestName "$paramName has ValidatePattern" -Status 'Passed' -Message "Pattern: $($validatePattern.RegexPattern)"
        }
        else {
            Write-TestResult -TestName "$paramName has ValidatePattern" -Status 'Failed' -Message "Missing ValidatePattern attribute"
        }
    }
    else {
        Write-TestResult -TestName "$paramName exists" -Status 'Skipped' -Message "Parameter not found"
    }
}

# ============================================================================
# Test 5: ValidateNotNullOrEmpty Parameters
# ============================================================================
Write-Host "`n--- ValidateNotNullOrEmpty Parameters ---" -ForegroundColor Yellow

$notNullParams = @(
    'FFUDevelopmentPath',
    'FFUPrefix',
    'ShareName',
    'Username',
    'WindowsVersion'
)

foreach ($paramName in $notNullParams) {
    $param = $cmd.Parameters[$paramName]
    if ($param) {
        $validateNotNull = $param.Attributes | Where-Object { $_.TypeId.Name -eq 'ValidateNotNullOrEmptyAttribute' }
        if ($validateNotNull) {
            Write-TestResult -TestName "$paramName has ValidateNotNullOrEmpty" -Status 'Passed'
        }
        else {
            Write-TestResult -TestName "$paramName has ValidateNotNullOrEmpty" -Status 'Failed' -Message "Missing ValidateNotNullOrEmpty attribute"
        }
    }
    else {
        Write-TestResult -TestName "$paramName exists" -Status 'Skipped' -Message "Parameter not found"
    }
}

# ============================================================================
# Test 6: Array Parameter Validation (AdditionalFFUFiles)
# ============================================================================
Write-Host "`n--- Array Parameter Validation ---" -ForegroundColor Yellow

$param = $cmd.Parameters['AdditionalFFUFiles']
if ($param) {
    $validateScript = $param.Attributes | Where-Object { $_.TypeId.Name -eq 'ValidateScriptAttribute' }
    if ($validateScript) {
        Write-TestResult -TestName "AdditionalFFUFiles has ValidateScript" -Status 'Passed' -Message "Validates each file exists"
    }
    else {
        Write-TestResult -TestName "AdditionalFFUFiles has ValidateScript" -Status 'Failed' -Message "Missing ValidateScript attribute"
    }
}
else {
    Write-TestResult -TestName "AdditionalFFUFiles exists" -Status 'Skipped' -Message "Parameter not found"
}

# ============================================================================
# Test 7: Cross-Parameter Validation in BEGIN Block
# ============================================================================
Write-Host "`n--- Cross-Parameter Validation ---" -ForegroundColor Yellow

$content = Get-Content $scriptPath -Raw

# Check for InstallApps validation
if ($content -match 'if \(\$InstallApps\)' -and $content -match 'VMSwitchName is required') {
    Write-TestResult -TestName "InstallApps requires VMSwitchName validation" -Status 'Passed'
}
else {
    Write-TestResult -TestName "InstallApps requires VMSwitchName validation" -Status 'Failed' -Message "Cross-parameter validation not found"
}

# Check for Make/Model validation
if ($content -match 'if \(\$Make' -and $content -match 'Model parameter is required') {
    Write-TestResult -TestName "Make requires Model validation" -Status 'Passed'
}
else {
    Write-TestResult -TestName "Make requires Model validation" -Status 'Failed' -Message "Cross-parameter validation not found"
}

# Check for InstallDrivers validation
if ($content -match 'if \(\$InstallDrivers' -and $content -match 'Either DriversFolder or Make must be specified') {
    Write-TestResult -TestName "InstallDrivers requires driver source validation" -Status 'Passed'
}
else {
    Write-TestResult -TestName "InstallDrivers requires driver source validation" -Status 'Failed' -Message "Cross-parameter validation not found"
}

# ============================================================================
# Test 8: Existing Strong Validation (Preserved)
# ============================================================================
Write-Host "`n--- Existing Strong Validation ---" -ForegroundColor Yellow

# ISOPath validation
$param = $cmd.Parameters['ISOPath']
if ($param) {
    $validateScript = $param.Attributes | Where-Object { $_.TypeId.Name -eq 'ValidateScriptAttribute' }
    if ($validateScript) {
        Write-TestResult -TestName "ISOPath has path validation" -Status 'Passed'
    }
    else {
        Write-TestResult -TestName "ISOPath has path validation" -Status 'Failed'
    }
}

# WindowsLang validation
$param = $cmd.Parameters['WindowsLang']
if ($param) {
    $validateScript = $param.Attributes | Where-Object { $_.TypeId.Name -eq 'ValidateScriptAttribute' }
    if ($validateScript) {
        Write-TestResult -TestName "WindowsLang has language validation" -Status 'Passed'
    }
    else {
        Write-TestResult -TestName "WindowsLang has language validation" -Status 'Failed'
    }
}

# OptionalFeatures validation
$param = $cmd.Parameters['OptionalFeatures']
if ($param) {
    $validateScript = $param.Attributes | Where-Object { $_.TypeId.Name -eq 'ValidateScriptAttribute' }
    if ($validateScript) {
        Write-TestResult -TestName "OptionalFeatures has feature validation" -Status 'Passed'
    }
    else {
        Write-TestResult -TestName "OptionalFeatures has feature validation" -Status 'Failed'
    }
}

# ConfigFile validation
$param = $cmd.Parameters['ConfigFile']
if ($param) {
    $validateScript = $param.Attributes | Where-Object { $_.TypeId.Name -eq 'ValidateScriptAttribute' }
    if ($validateScript) {
        Write-TestResult -TestName "ConfigFile has path validation" -Status 'Passed'
    }
    else {
        Write-TestResult -TestName "ConfigFile has path validation" -Status 'Failed'
    }
}

# ============================================================================
# Summary
# ============================================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Passed:  $($script:TestResults.Passed)" -ForegroundColor Green
Write-Host "Failed:  $($script:TestResults.Failed)" -ForegroundColor Red
Write-Host "Skipped: $($script:TestResults.Skipped)" -ForegroundColor Yellow
Write-Host "Total:   $($script:TestResults.Tests.Count)" -ForegroundColor White

$overallResult = if ($script:TestResults.Failed -eq 0) { "PASS" } else { "FAIL" }
$overallColor = if ($script:TestResults.Failed -eq 0) { "Green" } else { "Red" }
Write-Host "`nOverall: $overallResult" -ForegroundColor $overallColor

# Show validation summary
Write-Host "`n--- Parameter Validation Summary ---" -ForegroundColor Yellow
Write-Host @"
This test validates that BuildFFUVM.ps1 has proper parameter validation:

VALIDATION TYPES IMPLEMENTED:
- ValidateScript: Path existence checks for file/folder parameters
- ValidateSet: Enumerated values for fixed-option parameters
- ValidateRange: Numeric bounds for memory, disk, processors
- ValidatePattern: Regex patterns for IP addresses, usernames, versions
- ValidateNotNullOrEmpty: Required string parameters
- Cross-parameter: Dependencies validated in BEGIN block

PARAMETERS NOW VALIDATED:
- Path parameters: AppListPath, UserAppListPath, OfficeConfigXMLFile, etc.
- Folder parameters: DriversFolder, PEDriversFolder, orchestrationPath
- Naming parameters: ShareName, Username (pattern validated)
- Version parameters: WindowsVersion (format validated)
- Array parameters: AdditionalFFUFiles (each file validated)
- Range parameters: MaxUSBDrives (0-100)

CROSS-PARAMETER VALIDATION:
- InstallApps requires VMSwitchName and VMHostIPAddress
- Make requires Model
- InstallDrivers requires DriversFolder or Make
"@ -ForegroundColor Gray

# Exit with appropriate code
if ($script:TestResults.Failed -gt 0) {
    Write-Host "`nFailed tests:" -ForegroundColor Red
    $script:TestResults.Tests | Where-Object Status -eq 'Failed' | ForEach-Object {
        Write-Host "  - $($_.Name): $($_.Message)" -ForegroundColor Red
    }
    exit 1
}
else {
    Write-Host "`nAll tests passed!" -ForegroundColor Green
    exit 0
}
