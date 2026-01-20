---
phase: 12-vhdx-drive-letter
plan: 02
subsystem: storage
tags: [vhdx, drive-letter, mount, hypervisor, storage]
dependency-graph:
  requires:
    - 12-01 (Set-OSPartitionDriveLetter utility)
    - FFU.Imaging module
    - FFU.Hypervisor module
  provides:
    - Invoke-MountScratchDisk with guaranteed drive letter
    - HyperVProvider.MountVirtualDisk with validation
    - VMwareProvider.MountVirtualDisk with validation
  affects:
    - 12-03 (Call-site integration)
    - All mount operations now return verified drive letters
tech-stack:
  added: []
  patterns:
    - NoteProperty attachment to disk objects
    - Drive letter accessibility verification
    - Retry with exponential backoff
key-files:
  created: []
  modified:
    - FFUDevelopment/BuildFFUVM.ps1
    - FFUDevelopment/Modules/FFU.Hypervisor/Providers/HyperVProvider.ps1
    - FFUDevelopment/Modules/FFU.Hypervisor/Providers/VMwareProvider.ps1
decisions:
  - id: D-12-02-01
    decision: Use NoteProperty to attach drive letter to disk object
    rationale: Maintains backward compatibility - callers receive disk object as before, but now with OSPartitionDriveLetter property
  - id: D-12-02-02
    decision: Add retry logic with exponential backoff to HyperVProvider
    rationale: Transient failures during drive letter assignment are common during system disk operations
  - id: D-12-02-03
    decision: Add drive letter normalization to VMwareProvider
    rationale: Ensures consistent X:\ format regardless of Mount-VHDWithDiskpart return format
metrics:
  duration: 4m
  completed: 2026-01-20
---

# Phase 12 Plan 02: BuildFFUVM.ps1 Integration Summary

**One-liner:** Integrated Set-OSPartitionDriveLetter into all mount operations with drive letter accessibility verification.

## What Was Built

Modified three files to guarantee drive letter stability across mount operations:

### 1. BuildFFUVM.ps1 - Invoke-MountScratchDisk

Added Set-OSPartitionDriveLetter calls to both VHD and VHDX code paths:

```powershell
# After mount completes:
$driveLetter = Set-OSPartitionDriveLetter -Disk $disk -PreferredLetter 'W'
$disk | Add-Member -NotePropertyName 'OSPartitionDriveLetter' -NotePropertyValue $driveLetter -Force
WriteLog "Guaranteed OS partition drive letter: $driveLetter"
return $disk
```

**Key Design:** Disk object now has `OSPartitionDriveLetter` property for callers to use.

### 2. HyperVProvider.MountVirtualDisk

Enhanced with:
- Retry logic (3 attempts with exponential backoff)
- Preferred letter W with Z-downward fallback
- Test-Path verification for accessibility
- Wait-and-retry if path not immediately accessible
- Clear exception messages on failure

### 3. VMwareProvider.MountVirtualDisk

Enhanced with:
- Null/empty check for returned drive letter
- Drive letter format normalization (ensures X:\ format)
- Test-Path verification for accessibility
- Wait-and-retry if path not immediately accessible
- Clear exception messages on failure

## Commits

| Hash | Type | Description |
|------|------|-------------|
| cd557bd | feat | Integrate Set-OSPartitionDriveLetter into Invoke-MountScratchDisk |
| e833763 | feat | Enhance HyperVProvider MountVirtualDisk with validation |
| 5c370cd | feat | Enhance VMwareProvider MountVirtualDisk with validation |
| 8e24e24 | fix | Move maxRetries declaration to method scope |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Variable scope error in HyperVProvider**

- **Found during:** Verification 3 (module import)
- **Issue:** `$maxRetries` variable was defined inside `if` block but used in `throw` statement outside the block
- **Fix:** Moved `$maxRetries = 3` declaration to method scope
- **Files modified:** HyperVProvider.ps1
- **Commit:** 8e24e24

## Verification Results

| Check | Result |
|-------|--------|
| BuildFFUVM.ps1 integrates Set-OSPartitionDriveLetter | PASS (2 calls) |
| HyperVProvider has Test-Path verification | PASS |
| VMwareProvider has Test-Path verification | PASS |
| FFU.Imaging module imports | PASS |
| FFU.Hypervisor module imports | PASS |
| DriveLetterStability tests pass | PASS (17/17) |

## Existing Defensive Code

The existing workaround at BuildFFUVM.ps1 lines 4221-4259 remains in place as defensive backup. This code:
- Detects if OS partition lacks a drive letter
- Assigns one using Z-downward fallback
- Logs detailed partition information for debugging

With the Invoke-MountScratchDisk changes, this code will rarely execute, but serves as an additional safety layer.

## Next Phase Readiness

### Checklist for 12-03 (Provider Integration)

- [x] Invoke-MountScratchDisk returns disk with OSPartitionDriveLetter property
- [x] Both providers validate and verify drive letters
- [x] Retry logic handles transient failures
- [x] Clear exceptions on permanent failures
- [x] Logging supports troubleshooting

### Usage Pattern

```powershell
# After Invoke-MountScratchDisk:
$disk = Invoke-MountScratchDisk -DiskPath $vhdxPath
$driveLetter = $disk.OSPartitionDriveLetter  # Guaranteed to be valid
Copy-Item -Path $source -Destination "$($driveLetter):\"
```

## Files Changed

### Modified
- `FFUDevelopment/BuildFFUVM.ps1` - Added Set-OSPartitionDriveLetter calls (12 lines)
- `FFUDevelopment/Modules/FFU.Hypervisor/Providers/HyperVProvider.ps1` - Enhanced MountVirtualDisk (50 lines)
- `FFUDevelopment/Modules/FFU.Hypervisor/Providers/VMwareProvider.ps1` - Enhanced MountVirtualDisk (26 lines)
