# FFU Optimization Failure - Error 1167 "Device Not Connected" Fix

**Status:** FIXED
**Date:** November 2025
**Severity:** High
**Module:** `FFU.Imaging.psm1`

## Symptoms

FFU optimization fails with DISM error 1167 "The device is not connected" (0x8007048f) or related errors:

- `IOWorkerCallback failed with 0x8007048f`
- `CAbstractDisk::SetDiskOfflineAttribute failed with 0x800701b1`
- `Failed to detach VHD/X (0x80070015)` - Device not ready
- `Failed to delete backing VHD/X file (0x80070020)` - Sharing violation

## Root Cause

During FFU optimization, DISM creates a temporary VHD in `%TEMP%` folder (`_ffumount*.vhd`). This VHD gets locked by:

1. **Windows Defender / Antivirus** real-time scanning
2. **Windows Search Indexer** indexing temporary files
3. **Stale DISM mount points** from previous failed operations
4. **Other processes** accessing the temp folder

## Solution Implemented

New function `Invoke-FFUOptimizeWithScratchDir` uses dedicated scratch directory outside `%TEMP%`.

### Key Features

- DISM `/ScratchDir` parameter redirects temporary files to controlled location
- Comprehensive pre-flight cleanup
- Automatic retry logic (up to 2 attempts)
- Detailed diagnostic output on failure

### Pre-flight Cleanup Steps

1. Clean stale DISM mount points (`dism /Cleanup-Mountpoints`)
2. Dismount orphaned `_ffumount*.vhd` files in temp folder
3. Create/clean dedicated scratch directory in FFUDevelopment folder
4. Verify FFU file is not locked before optimization
5. Check disk space (warns if <10GB free)
6. Wait for file system to settle

## Usage

### Automatic Usage

```powershell
# Automatically used by New-FFU when $Optimize = $true
.\BuildFFUVM.ps1 -OptimizeFFU $true
```

### Direct Function Call

```powershell
Invoke-FFUOptimizeWithScratchDir -FFUFile "C:\FFU\Win11.ffu" `
                                 -DandIEnv "C:\Program Files (x86)\...\DandISetEnv.bat" `
                                 -FFUDevelopmentPath "C:\FFUDevelopment"
```

## Recommended Pre-emptive Fix

Run once on build host to prevent issues:

```powershell
# Add Windows Defender exclusions
Add-MpPreference -ExclusionPath "C:\FFUDevelopment"
Add-MpPreference -ExclusionExtension ".vhd"
Add-MpPreference -ExclusionExtension ".ffu"
Add-MpPreference -ExclusionProcess "dism.exe"
```

## Files Modified

- `FFU.Imaging.psm1` - Added `Invoke-FFUOptimizeWithScratchDir` function

## Behavior Change

| Before | After |
|--------|-------|
| FFU optimization fails with cryptic error 1167 | Automatic scratch directory management |
| No retry mechanism | Up to 2 attempts with cleanup between |
| Requires manual cleanup | Stale VHD cleanup automatic |
| No diagnostic info | Detailed diagnostics with remediation steps |
