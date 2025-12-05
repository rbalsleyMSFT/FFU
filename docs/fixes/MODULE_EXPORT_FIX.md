# FFU.VM Module Export Fix

**Status:** FIXED (v1.0.3)
**Date:** December 2025
**Severity:** High
**Test:** `Tests/Test-ModuleExportFix.ps1` (13 test cases)
**Module:** `FFU.VM`

## Symptoms

Build job fails with warning:
```
WARNING: Sensitive capture media cleanup failed (non-critical): The term 'Remove-SensitiveCaptureMedia' is not recognized as the name of a cmdlet, function, script file, or operable program.
```

Similar errors may occur for `Set-LocalUserAccountExpiry`.

## Root Cause

PowerShell modules have **two** export mechanisms that must be synchronized:

1. **Module Manifest (.psd1)**: `FunctionsToExport` array declares what functions the module *intends* to export
2. **Module Script (.psm1)**: `Export-ModuleMember` statement *actually* controls what's exported at runtime

**The Problem:**
- Functions were defined in `FFU.VM.psm1`
- Functions were listed in `FFU.VM.psd1` under `FunctionsToExport`
- Functions were **NOT** included in the `Export-ModuleMember` statement

When `Export-ModuleMember` is present, it **explicitly restricts** exports to only the listed functions. Any function not in that list becomes private to the module, even if declared in the manifest.

## Solution Implemented

Added the missing credential security functions to the `Export-ModuleMember` statement in `FFU.VM.psm1`:

```powershell
# Export module members
Export-ModuleMember -Function @(
    'Get-LocalUserAccount',
    'New-LocalUserAccount',
    'Remove-LocalUserAccount',
    'Set-LocalUserPassword',
    'Set-LocalUserAccountExpiry',    # Was missing - added
    'New-FFUVM',
    'Remove-FFUVM',
    'Get-FFUEnvironment',
    'Set-CaptureFFU',
    'Remove-FFUUserShare',
    'Update-CaptureFFUScript',
    'Remove-SensitiveCaptureMedia'   # Was missing - added
)
```

## Testing

```powershell
# Run test suite
.\Tests\Test-ModuleExportFix.ps1 -FFUDevelopmentPath "C:\FFUDevelopment"
```

Test categories:
- Source Code Verification (function definitions and Export-ModuleMember)
- Module Manifest Verification (FunctionsToExport)
- Module Import Verification (actual exported commands)
- Function Callable Verification (Get-Command tests)

All 13 tests pass, confirming all 12 expected functions are exported.

## Files Modified

- `Modules/FFU.VM/FFU.VM.psm1` - Added functions to Export-ModuleMember

## Pattern to Follow

When adding new functions to a PowerShell module:

1. **Define** the function in the `.psm1` file
2. **Add** to `FunctionsToExport` array in `.psd1` manifest
3. **Add** to `Export-ModuleMember` statement in `.psm1` (CRITICAL!)

All three steps are required. Missing step 3 is a common oversight that causes functions to be silently unavailable.

## Verification Commands

```powershell
# Check what a module actually exports
Import-Module FFU.VM -Force
Get-Command -Module FFU.VM | Select-Object Name

# Verify specific function is callable
Get-Command Remove-SensitiveCaptureMedia -ErrorAction SilentlyContinue
```

## Behavior Change

| Before | After |
|--------|-------|
| Remove-SensitiveCaptureMedia not found | Function exported and callable |
| Set-LocalUserAccountExpiry not found | Function exported and callable |
| Credential security features silently fail | All 12 functions properly exported |
