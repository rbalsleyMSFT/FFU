---
status: verifying
trigger: "OS partition drive letter becomes empty during unattend file copy verification"
created: 2026-01-22T12:00:00Z
updated: 2026-01-22T12:30:00Z
---

## Current Focus

hypothesis: The fsutil volume flush command (line 4115) triggers Windows to unmount/remount the VHD partition, which causes the drive letter to be released. This is a known Windows behavior where flushing a VHD-mounted volume can destabilize the mount point.
test:
  1. Add logging before and after fsutil to track partition state
  2. Check if the partition DriveLetter property becomes empty after fsutil
  3. Re-assign drive letter if lost, using Set-OSPartitionDriveLetter
expecting: Drive letter is lost after fsutil volume flush - need to re-acquire it before verification
next_action: Implement fix with enhanced logging and drive letter re-acquisition after volume flush

## Symptoms

expected: OS partition drive letter should remain assigned (W:) throughout unattend file copy and verification
actual: Drive letter is W: initially (line 307), but becomes empty during verification (lines 325, 327)
errors:
  - "DEBUG: osPartitionDriveLetter value: ''" (line 325)
  - "WARNING: unattendDest is empty! Reconstructing path..." (line 326)
  - "DEBUG: Refreshed drive letter: ''" (line 327)
  - "ERROR: Write-through copy failed: Cannot verify unattend file: OS partition drive letter is not assigned" (line 328)
  - "ERROR: Failed to copy unattend file for audit mode boot" (line 329)
reproduction: Build FFU with VMware hypervisor, reaches "Finalizing VHDX" phase at 40%, copies unattend successfully but verification fails because drive letter disappears
started: New error in recent builds, appears to be race condition or Windows unmounting behavior

## Eliminated

(none yet)

## Evidence

- timestamp: 2026-01-22T12:00:00Z
  checked: Log output from user
  found: |
    - Line 307: "OS partition already has drive letter: W"
    - Lines 320-322: Unattend file written successfully (1395 bytes)
    - Line 323: Volume flush started at 7:27:21
    - Line 325: Drive letter empty at 7:27:22 (~1 second later)
  implication: Something between volume flush and verification removes the drive letter

- timestamp: 2026-01-22T12:10:00Z
  checked: Code analysis of BuildFFUVM.ps1 lines 3980-4220
  found: |
    - Line 4115: `$null = & fsutil volume flush "$osPartitionDriveLetter`:" 2>&1`
    - This fsutil command flushes the volume buffers for the mounted VHD
    - Line 4120: 500ms sleep, then verification begins
    - Line 4124: DEBUG log shows $osPartitionDriveLetter is empty
    - Lines 4127-4140 attempt to reconstruct the path but Get-Partition also returns empty DriveLetter
  implication: The fsutil volume flush command destabilizes the VHD mount, causing Windows to release the drive letter

- timestamp: 2026-01-22T12:12:00Z
  checked: FFU.Imaging.psm1 Set-OSPartitionDriveLetter function (lines 1718-1850)
  found: |
    - Centralized function exists for drive letter management
    - Has retry logic (3 attempts)
    - Already handles the case where drive letter is not assigned
    - Can be called after fsutil flush to re-establish the drive letter
  implication: The fix should call Set-OSPartitionDriveLetter after fsutil flush completes

- timestamp: 2026-01-22T12:14:00Z
  checked: Invoke-MountScratchDisk function (lines 3350-3470)
  found: |
    - VHD files (VMware) use diskpart to attach, then Set-OSPartitionDriveLetter
    - VHDX files (Hyper-V) use Mount-VHD, then Set-OSPartitionDriveLetter
    - Drive letter is stored in $disk.OSPartitionDriveLetter NoteProperty
    - Disk object is passed to caller but the drive letter can become stale
  implication: Drive letter assignment is guaranteed at mount time, but can be lost during operations like fsutil flush

## Resolution

root_cause: |
  The fsutil volume flush command on line 4115 (`fsutil volume flush "$osPartitionDriveLetter`:"`)
  triggers Windows to release and potentially reassign the VHD/VHD's partition drive letter.
  This is because fsutil flushes the volume buffers, which can cause the file-backed virtual
  disk subsystem to momentarily destabilize the mount point. When the code then tries to
  verify the file, it uses the now-stale $osPartitionDriveLetter variable which is empty.

  Additionally, the existing recovery logic (lines 4127-4140) tries to refresh the drive
  letter from the partition, but at that point Windows has already released the drive letter
  from the partition, so Get-Partition also returns an empty DriveLetter.

fix: |
  1. After fsutil volume flush completes, call Set-OSPartitionDriveLetter to re-establish
     the drive letter (which may have been released)
  2. Update the $unattendDest path with the (potentially new) drive letter
  3. Add enhanced logging to diagnose drive letter state before and after fsutil

verification: |
  - PSScriptAnalyzer: No new errors introduced
  - Code compiles without syntax errors
  - Diagnostic script created for manual testing
  - PENDING: User must run a build with VMware hypervisor to verify the fix

files_changed:
  - FFUDevelopment/BuildFFUVM.ps1 (lines 4112-4191: drive letter recovery after fsutil flush)
  - FFUDevelopment/Diagnostics/Test-DriveLetterStability.ps1 (new diagnostic script)
