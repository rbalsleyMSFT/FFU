# Parameter Validation Enhancement

**Status:** IMPLEMENTED (v1.0.4)
**Date:** December 2025
**Severity:** High (Reliability)
**Test:** `Tests/Test-ParameterValidation.ps1` (37 test cases)
**File:** `BuildFFUVM.ps1`

## Problem

BuildFFUVM.ps1 had minimal parameter validation. Invalid inputs caused:
- Late failures after hours of build time
- Cryptic error messages
- Wasted resources
- Poor user experience

Example failure scenarios:
- Invalid path causes failure after 30 minutes
- Invalid driver folder causes failure during image mounting
- Invalid VM settings cause Hyper-V errors mid-build

## Solution Implemented

Added comprehensive validation attributes to 15+ parameters following PowerShell best practices.

### Validation Types Added

| Type | Parameters | Purpose |
|------|------------|---------|
| ValidateScript | 10 path parameters | Verify file/folder exists when specified |
| ValidatePattern | 4 parameters | Regex validation for format |
| ValidateRange | 1 parameter | Numeric bounds validation |
| ValidateNotNullOrEmpty | 5 parameters | Prevent empty strings |
| Array validation | 1 parameter | Validate each array element |

### Parameters Now Validated

#### Path Parameters (ValidateScript)
```powershell
# File must exist if specified
[ValidateScript({ [string]::IsNullOrWhiteSpace($_) -or (Test-Path $_ -PathType Leaf) })]
[string]$AppListPath,
[string]$UserAppListPath,
[string]$OfficeConfigXMLFile,
[string]$DriversJsonPath,

# Directory must exist if specified
[ValidateScript({ [string]::IsNullOrWhiteSpace($_) -or (Test-Path $_ -PathType Container) })]
[string]$DriversFolder,
[string]$PEDriversFolder,
[string]$orchestrationPath,

# Parent directory must exist (for output paths)
[ValidateScript({ [string]::IsNullOrWhiteSpace($_) -or (Test-Path (Split-Path $_ -Parent) -PathType Container) })]
[string]$VMLocation,
[string]$FFUCaptureLocation,
[string]$ExportConfigFile,
```

#### Pattern Parameters (ValidatePattern)
```powershell
# Share name: alphanumeric, underscore, hyphen, $
[ValidatePattern('^[a-zA-Z0-9_\-$]+$')]
[string]$ShareName = "FFUCaptureShare",

# Username: alphanumeric, underscore, hyphen
[ValidatePattern('^[a-zA-Z0-9_\-]+$')]
[string]$Username = "ffu_user",

# Windows version: 4 digits OR ##H# format OR LTSC
[ValidatePattern('^(\d{4}|[12][0-9][hH][12]|LTSC|ltsc)$')]
[string]$WindowsVersion = '25h2',
```

#### Range Parameters (ValidateRange)
```powershell
[ValidateRange(0, 100)]
[int]$MaxUSBDrives = 5,
```

#### Array Parameters (ValidateScript)
```powershell
[ValidateScript({
    if ($null -eq $_ -or $_.Count -eq 0) { return $true }
    foreach ($file in $_) {
        if (-not (Test-Path $file -PathType Leaf)) {
            throw "AdditionalFFUFiles: File not found: $file"
        }
    }
    return $true
})]
[string[]]$AdditionalFFUFiles,
```

### Previously Existing Validation (Preserved)

The following parameters already had strong validation:
- `ISOPath` - ValidateScript for path exists
- `WindowsSKU` - ValidateSet (20 values)
- `FFUDevelopmentPath` - ValidateNotNullOrEmpty
- `Memory` - ValidateRange (2GB-128GB)
- `Disksize` - ValidateRange (25GB-2TB)
- `Processors` - ValidateRange (1-64)
- `VMHostIPAddress` - ValidatePattern (IP regex)
- `WindowsRelease` - ValidateSet (10, 11, 2016, 2019, 2021, 2022, 2024, 2025)
- `WindowsArch` - ValidateSet (x86, x64, arm64)
- `WindowsLang` - ValidateScript (38 languages)
- `MediaType` - ValidateSet (consumer, business)
- `LogicalSectorSizeBytes` - ValidateSet (512, 4096)
- `Make` - ValidateSet (Microsoft, Dell, HP, Lenovo)
- `ConfigFile` - ValidateScript (null or exists)
- `OptionalFeatures` - ValidateScript (allowed features list)

### Cross-Parameter Validation (BEGIN block)

These dependencies are validated before script execution:
1. `InstallApps` requires `VMSwitchName` and `VMHostIPAddress`
2. `Make` requires `Model`
3. `InstallDrivers` requires `DriversFolder` or `Make`

## Testing

```powershell
# Run test suite
.\Tests\Test-ParameterValidation.ps1 -FFUDevelopmentPath "C:\FFUDevelopment"
```

Test categories:
- Validation Attribute Verification (10 tests)
- ValidateSet Parameters (6 tests)
- ValidateRange Parameters (4 tests)
- ValidatePattern Parameters (4 tests)
- ValidateNotNullOrEmpty Parameters (5 tests)
- Array Parameter Validation (1 test)
- Cross-Parameter Validation (3 tests)
- Existing Strong Validation (4 tests)

All 37 tests pass.

## Behavior Change

| Before | After |
|--------|-------|
| Invalid path fails after 30+ minutes | Fails immediately with clear message |
| Cryptic DISM/Hyper-V errors | Clear parameter validation errors |
| No format validation for names | ShareName, Username validated |
| No bounds on MaxUSBDrives | Limited to 0-100 |
| Array files not validated | Each file verified to exist |

## Pattern to Follow

When adding new parameters:

1. **String paths (files):** Use `[ValidateScript({ [string]::IsNullOrWhiteSpace($_) -or (Test-Path $_ -PathType Leaf) })]`
2. **String paths (folders):** Use `[ValidateScript({ [string]::IsNullOrWhiteSpace($_) -or (Test-Path $_ -PathType Container) })]`
3. **Fixed values:** Use `[ValidateSet('value1', 'value2')]`
4. **Numeric ranges:** Use `[ValidateRange(min, max)]`
5. **Format validation:** Use `[ValidatePattern('regex')]`
6. **Required strings:** Add `[ValidateNotNullOrEmpty()]`
7. **Cross-parameter dependencies:** Validate in BEGIN block with helpful error messages
