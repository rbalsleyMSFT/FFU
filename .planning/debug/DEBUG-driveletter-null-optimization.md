---
status: verifying
trigger: "Build fails with 'Cannot validate argument on parameter DriveLetter. The argument is null' during VHDX optimization phase after VM completes app installation."
created: 2026-01-21T00:00:00Z
updated: 2026-01-21T00:06:00Z
---

## Current Focus

hypothesis: CONFIRMED AND FIXED - Optimize-FFUCaptureDrive did not call Set-OSPartitionDriveLetter after mounting VHD
test: Verify fix by running VMware + InstallApps=true build
expecting: VHDX optimization phase will succeed with assigned drive letter
next_action: User verification of fix with actual VM build

## Symptoms

expected: VHD should be mounted and drive letter obtained for defragmentation before FFU capture
actual: VHD is mounted but drive letter is null, causing Optimize-Volume to fail with validation error
errors: "Cannot validate argument on parameter 'DriveLetter'. The argument is null. Provide a valid value for the argument, and then try running the command again."
reproduction: Build with VMware + InstallApps=true, after VM completes Windows installation and shuts down, optimization phase fails
started: Occurs at "[PROGRESS] 65 | Optimizing VHDX before capture..." phase

## Eliminated

## Evidence

- timestamp: 2026-01-21T00:00:00Z
  checked: Log context provided in ticket
  found: VHD was dismounted at line 356, VM ran lines 557-598, optimization fails at lines 617-620. VHD path is C:\FFUDevelopment\VM\_FFU-1558669454\_FFU-1558669454.vhd
  implication: VHD needs to be re-mounted after VM shutdown but drive letter retrieval is failing

- timestamp: 2026-01-21T00:01:00Z
  checked: Optimize-FFUCaptureDrive function in FFU.Imaging.psm1 (lines 1751-1775)
  found: |
    Function does:
    1. Mount-VHD -Path $VhdxPath -Passthru | Get-Disk
    2. Get-Partition where GptType matches basic data partition GUID
    3. Calls Optimize-Volume -DriveLetter $osPartition.DriveLetter

    The issue: Mount-VHD does NOT automatically assign drive letters to partitions.
    It mounts the disk but partitions have no drive letter unless explicitly assigned.
    The partition object is found (GptType filter works), but $osPartition.DriveLetter is null.
  implication: Need to explicitly assign a drive letter after mounting the VHD before calling Optimize-Volume

- timestamp: 2026-01-21T00:02:00Z
  checked: Set-OSPartitionDriveLetter function (FFU.Imaging.psm1 lines 1544-1677)
  found: |
    Function exists specifically for this purpose - it:
    1. Finds OS partition by GPT type
    2. Checks if drive letter already assigned (returns if so)
    3. Finds available drive letter (prefers 'W', falls back to Z-D)
    4. Assigns letter with retry logic (3 attempts)
    5. Verifies assignment before returning
    Function is exported in FFU.Imaging.psd1 (line 58)
  implication: The fix is simple - call Set-OSPartitionDriveLetter after mounting and use returned letter

- timestamp: 2026-01-21T00:02:30Z
  checked: FFU.Imaging.psd1 exports
  found: Set-OSPartitionDriveLetter is exported and available for use within the module
  implication: Fix is straightforward internal module change

## Resolution

root_cause: Optimize-FFUCaptureDrive function mounts VHD but relies on $osPartition.DriveLetter which is null because Mount-VHD does not automatically assign drive letters. The Set-OSPartitionDriveLetter function exists specifically to handle this but is not being called.

fix: |
  Modified Optimize-FFUCaptureDrive function (FFU.Imaging.psm1 lines 1751-1799) to:
  1. After Mount-VHD, call Set-OSPartitionDriveLetter -Disk $mountedDisk -PreferredLetter 'W'
  2. Use the returned drive letter ($driveLetter) for both Optimize-Volume calls
  3. Added proper documentation explaining the Mount-VHD behavior
  4. Removed the manual $osPartition lookup since Set-OSPartitionDriveLetter handles it internally

verification: |
  - Module parses without syntax errors: PASS
  - Optimize-FFUCaptureDrive function exists: PASS
  - Function contains Set-OSPartitionDriveLetter call: PASS
  - Module manifest valid (version 1.1.1): PASS
  - Runtime verification requires actual VM build (user must test)

files_changed:
  - FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psm1 (Optimize-FFUCaptureDrive function)
  - FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psd1 (version 1.1.0 -> 1.1.1)
  - FFUDevelopment/version.json (1.8.4 -> 1.8.5, FFU.Imaging 1.1.0 -> 1.1.1)
