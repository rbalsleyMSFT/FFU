# WriteLog Empty String and Path Validation Errors Fix

**Status:** FIXED
**Date:** November 2025
**Severity:** High
**Test:** `Tests/Test-WriteLogAndPathFixes.ps1` (23 test cases)

## Symptoms

Build job fails with one of these errors:

1. `Cannot bind argument to parameter 'LogText' because it is an empty string`
2. `Value cannot be null. (Parameter 'The provided Path argument was null or an empty collection.')`

## Root Causes

### Root Cause #1 (LogText Error)

When exception handling calls `WriteLog $_`, the exception object converts to an empty string in certain cases (e.g., exceptions with no message), causing parameter binding failure.

### Root Cause #2 (Path Error)

When `Remove-Item -Path $var1, $var2` is called with null/empty path variables, PowerShell throws a validation error.

## Solution Implemented

### 1. WriteLog Function Hardened (FFU.Common.Core.psm1)

- Added `[AllowNull()]` and `[AllowEmptyString()]` attributes
- Added early return for null/empty values
- Function gracefully ignores empty log entries instead of throwing

### 2. New Get-ErrorMessage Helper Function (FFU.Common.Core.psm1)

- Safely extracts error messages from ErrorRecord, Exception, or any object
- Always returns a non-empty string (provides fallback messages)
- Used by Invoke-Process and available for all modules

### 3. Path Validation Before Remove-Item (FFU.Common.Core.psm1)

- Invoke-Process now filters null/empty paths before cleanup
- Uses `Where-Object { -not [string]::IsNullOrWhiteSpace($_) }`

### 4. Standalone Scripts Updated

All scripts with WriteLog functions updated:
- `Create-PEMedia.ps1` - WriteLog null check added
- `ApplyFFU.ps1` - WriteLog null check added
- `USBImagingToolCreator.ps1` - WriteLog null check added

## Usage

### Old Pattern (Could Fail)

```powershell
catch {
    WriteLog $_  # May fail if $_ converts to empty string
}
```

### New Pattern (Safe)

```powershell
catch {
    WriteLog (Get-ErrorMessage $_)  # Always returns non-empty string
}
```

### Get-ErrorMessage Function

```powershell
# Handles various error types safely
$message = Get-ErrorMessage $_
$message = Get-ErrorMessage $exception
$message = Get-ErrorMessage $errorRecord
```

## Testing

```powershell
# Run test suite
.\Tests\Test-WriteLogAndPathFixes.ps1
```

- 23 test cases covering null/empty handling and path validation
- 100% pass rate validates all fixes

## Files Modified

- `FFU.Common.Core.psm1` - WriteLog hardening, Get-ErrorMessage function, path validation
- `Create-PEMedia.ps1` - WriteLog null check
- `ApplyFFU.ps1` - WriteLog null check
- `USBImagingToolCreator.ps1` - WriteLog null check

## Behavior Change

| Before | After |
|--------|-------|
| Build fails with parameter binding errors | Empty/null values handled gracefully |
| Exception objects cause failures | Get-ErrorMessage extracts safe strings |
| Null paths cause Remove-Item failures | Paths filtered before cleanup |
