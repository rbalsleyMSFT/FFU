# WinPE boot.wim Creation Failures Fix

**Status:** FIXED
**Date:** November 2025
**Severity:** Critical
**Test:** `Test-ADKValidation.ps1`

## Symptoms

- Build fails with "Boot.wim not found at expected path" when creating WinPE capture media
- Silent failure during WinPE media creation with no clear error message
- ADK tools fail without indicating which component is missing

## Root Cause

Missing Windows ADK or Windows PE add-on installation. The build process attempted to create WinPE media without first validating that all required ADK components were present.

## Solution Implemented

Automatic ADK pre-flight validation now detects missing components before build starts.

### Validation Checks

- ADK installation presence (registry and file system)
- Deployment Tools feature
- Windows PE add-on
- Critical files:
  - `copype.cmd`
  - `oscdimg.exe`
  - Boot files (etfsboot.com, Efisys.bin, Efisys_noprompt.bin)

### Error Handling

- Clear error messages with specific missing components
- Direct links to Microsoft download pages
- Automatic installation when `-UpdateADK $true` is set
- Detailed logging with severity levels (Info, Success, Warning, Error, Critical)

## Usage

### Automatic Validation

When `-CreateCaptureMedia` or `-CreateDeploymentMedia` is enabled, the system performs comprehensive pre-flight checks:

```powershell
# Automatically triggered when creating WinPE media
.\BuildFFUVM.ps1 -CreateCaptureMedia $true -UpdateADK $true
```

### Manual Validation

```powershell
# Explicitly validate ADK prerequisites
$validation = Test-ADKPrerequisites -WindowsArch 'x64' -AutoInstall $false -ThrowOnFailure $false

if (-not $validation.IsValid) {
    Write-Host "ADK validation failed:"
    $validation.Errors | ForEach-Object { Write-Host "  - $_" }
}
```

## Resolution Steps

If ADK validation fails:

1. Check error message for specific missing components
2. Run with `-UpdateADK $true` for automatic installation
3. Or manually install from https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install
   - Install "Windows ADK" with "Deployment Tools" feature
   - Install "Windows PE add-on"

## Files Modified

- `FFU.ADK.psm1` - Added `Test-ADKPrerequisites` function
- `BuildFFUVM.ps1` - Added pre-flight validation calls

## Behavior Change

| Before | After |
|--------|-------|
| Silent failure during WinPE media creation | Early detection with actionable error messages |
