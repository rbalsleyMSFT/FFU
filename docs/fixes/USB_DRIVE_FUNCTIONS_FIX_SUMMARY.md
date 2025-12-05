# USB Drive Functions Fix Summary

## Problem Description

**Error Message:**
```
Building USB deployment drive failed with error The term 'New-DeploymentUSB' is not recognized
as a name of a cmdlet, function, script file, or executable program.
Check the spelling of the name, or if a path was included, verify that the path is correct and try again.
```

**Log Pattern:**
```
11/27/2025 10:42:08 AM ISO created successfully
11/27/2025 10:42:08 AM Cleaning up C:\FFUDevelopment\WinPE
11/27/2025 10:42:08 AM Cleanup complete
11/27/2025 10:42:08 AM [PROGRESS] 95 | Building USB drive...
11/27/2025 10:42:09 AM Building USB deployment drive failed with error The term 'New-DeploymentUSB' is not recognized...
```

## Root Cause Analysis

During the modularization of `BuildFFUVM.ps1`, two functions were **accidentally omitted**:

1. **Get-USBDrive** (lines 4823-4969 in original, ~147 lines)
   - Discovers and validates USB drives for deployment
   - Supports removable media and external hard disk detection
   - Called at line 1083: `$USBDrives, $USBDrivesCount = Get-USBDrive`

2. **New-DeploymentUSB** (lines 4970-5148 in original, ~179 lines)
   - Creates bootable USB deployment drives
   - Uses `ForEach-Object -Parallel` for multi-drive processing
   - Called at line 2917: `New-DeploymentUSB -CopyFFU -FFUFilesToCopy $ffuFilesToCopy`

**Why it wasn't caught earlier:** The functions are only called when `$BuildUSBDrive = $true`, which may not be tested in every build scenario.

## Solution Considered

### Solution A: Add functions to FFU.Media module
Extract both functions to FFU.Media with explicit parameters for all dependencies.

**Rejected because:**
- `New-DeploymentUSB` uses `ForEach-Object -Parallel` with 14+ `$using:` variables
- Would require passing 14+ parameters explicitly
- Complex refactoring with high risk of breaking functionality

### Solution B: Keep functions in BuildFFUVM.ps1 (SELECTED)
Add both functions back to BuildFFUVM.ps1 where they can access script-scope variables naturally.

**Why this is correct:**
- `ForEach-Object -Parallel` with `$using:` works naturally with script-scope variables
- These functions are only used by BuildFFUVM.ps1 (not reusable)
- Minimal risk, restores original behavior exactly
- Properly documented why not modularized

## Implementation

### Code Added to BuildFFUVM.ps1 (lines 720-1080)

```powershell
# =============================================================================
# USB Drive Functions
# These functions were intentionally kept in BuildFFUVM.ps1 (not modularized)
# because New-DeploymentUSB uses ForEach-Object -Parallel with many $using:
# script-scope variables, which doesn't work well with module encapsulation.
# =============================================================================

Function Get-USBDrive { ... }      # ~157 lines
Function New-DeploymentUSB { ... } # ~192 lines

# =============================================================================
# End USB Drive Functions
# =============================================================================
```

### Variables Used by $using: in Parallel Block

| Variable | Purpose |
|----------|---------|
| `$PSScriptRoot` | Script root for module imports |
| `$LogFile` | Log file path for thread logging |
| `$ISOMountPoint` | Mounted ISO drive letter |
| `$CopyFFU` | Switch to copy FFU files |
| `$SelectedFFUFile` | FFU file(s) to copy |
| `$CopyDrivers` | Switch to copy drivers |
| `$DriversFolder` | Drivers source path |
| `$CopyPPKG` | Switch to copy PPKGs |
| `$PPKGFolder` | PPKG source path |
| `$CopyUnattend` | Switch to copy unattend |
| `$UnattendFolder` | Unattend source path |
| `$WindowsArch` | x64 or arm64 |
| `$CopyAutopilot` | Switch to copy Autopilot |
| `$AutopilotFolder` | Autopilot source path |

## Files Modified

| File | Change |
|------|--------|
| `BuildFFUVM.ps1` | Added Get-USBDrive (lines 727-882) and New-DeploymentUSB (lines 885-1076) functions |

## Test Coverage

**Test Script:** `Test-USBDriveFunctionsFix.ps1`

13 tests covering:
- Get-USBDrive function existence and documentation
- New-DeploymentUSB function existence and parameters
- Correct function call patterns
- Functions NOT in modules (intentional)
- Explanation comment presence
- All 14 `$using:` variables in parallel block
- Script syntax validation

**Results:** 100% pass rate (13/13 tests)

## New Behavior

### Before Fix
```
[PROGRESS] 95 | Building USB drive...
Building USB deployment drive failed with error The term 'New-DeploymentUSB' is not recognized...
```

### After Fix
```
[PROGRESS] 95 | Building USB drive...
Checking for USB drives
Found 2 Removable USB drives
Starting parallel creation for 2 USB drive(s).
Using USB drive throttle limit: 2
Disk 3 partitioned. Boot: E:\, Deploy: F:\
Copying WinPE files...
Copying FFU files...
USB Drives completed
```

## Why Not Modularized

These functions were **intentionally kept in BuildFFUVM.ps1** because:

1. **ForEach-Object -Parallel scoping**: The parallel block uses 14+ `$using:` variables that reference script-scope variables
2. **Module encapsulation breaks `$using:`**: Moving to a module would require explicit parameters for all variables
3. **Single consumer**: Only BuildFFUVM.ps1 uses these functions
4. **Complexity vs benefit**: Modularizing would add complexity without improving maintainability

## Date
November 27, 2025
