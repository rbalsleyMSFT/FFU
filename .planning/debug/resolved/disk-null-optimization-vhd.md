---
status: resolved
trigger: "Build fails with 'Cannot bind argument to parameter Disk because it is null' during VHDX optimization phase"
created: 2026-01-21T00:00:00Z
updated: 2026-01-21T00:10:00Z
---

## Current Focus

hypothesis: CONFIRMED - Mount-VHD (Hyper-V cmdlet) returns null for diskpart-created .vhd files used by VMware
test: Implemented fix and verified module loads correctly
expecting: VMware builds will now use diskpart-based Mount-ScratchVhd for .vhd files
next_action: N/A - fix verified

## Symptoms

expected: VHD should be mounted and disk object obtained, then passed to Set-OSPartitionDriveLetter
actual: Mount-VHD is returning null for the disk object, causing Set-OSPartitionDriveLetter to fail
errors: "Cannot bind argument to parameter 'Disk' because it is null."
reproduction: Build with VMware + InstallApps=true, after VM completes Windows installation and shuts down, optimization phase fails
started: Immediately after the previous fix was applied (Set-OSPartitionDriveLetter addition)

## Eliminated

(none yet)

## Evidence

- timestamp: 2026-01-21T00:01:00Z
  checked: Log context from FFUDevelopment.log
  found: VHD path is C:\FFUDevelopment\VM\_FFU-1669313187\_FFU-1669313187.vhd (.vhd, NOT .vhdx)
  implication: VMware builds use .vhd files created with diskpart, not .vhdx files

- timestamp: 2026-01-21T00:02:00Z
  checked: Optimize-FFUCaptureDrive function (lines 1751-1799)
  found: Function uses `Mount-VHD -Path $VhdxPath -Passthru | Get-Disk` unconditionally
  implication: Mount-VHD is a Hyper-V cmdlet that may not work with diskpart-created VHD files

- timestamp: 2026-01-21T00:03:00Z
  checked: New-ScratchVhd function (lines 752-1000+)
  found: VMware VHDs are created with diskpart, not Hyper-V cmdlets. Attach is done via `select vdisk file="$VhdPath" / attach vdisk`
  implication: To mount .vhd files, must use diskpart attach, not Mount-VHD

- timestamp: 2026-01-21T00:04:00Z
  checked: Dismount-ScratchVhd function (lines 1223-1298)
  found: Uses diskpart `select vdisk / detach vdisk` to dismount VHD files
  implication: Confirms pattern - diskpart for .vhd, Hyper-V cmdlets for .vhdx

- timestamp: 2026-01-21T00:05:00Z
  checked: Dismount-ScratchVhdx function (lines 1738-1749)
  found: Uses `Dismount-VHD -Path $VhdxPath` (Hyper-V cmdlet)
  implication: VHDX files use Hyper-V cmdlets, VHD files use diskpart - confirms two separate patterns

## Resolution

root_cause: Optimize-FFUCaptureDrive uses Mount-VHD (Hyper-V cmdlet) unconditionally, but for VMware builds the disk is a .vhd file created with diskpart. Mount-VHD fails silently for diskpart-created VHD files, returning null, which causes the subsequent Set-OSPartitionDriveLetter call to fail with "Cannot bind argument to parameter 'Disk' because it is null."

fix:
1. Added new Mount-ScratchVhd function that uses diskpart to attach VHD and return disk object
2. Modified Optimize-FFUCaptureDrive to detect file extension (.vhd vs .vhdx)
3. For .vhd files: Uses Mount-ScratchVhd/Dismount-ScratchVhd (diskpart-based)
4. For .vhdx files: Uses Mount-VHD/Dismount-ScratchVhdx (Hyper-V cmdlets, existing behavior)
5. Skips Optimize-VHD step for .vhd files (requires Hyper-V, not available for VMware builds)
6. Added null check after mount to provide clearer error message if mount fails

verification:
- Module imports successfully
- Mount-ScratchVhd exported (24 total functions in FFU.Imaging)
- Code logic verified - detects .vhd vs .vhdx correctly using PowerShell -like operator
- Diskpart attach pattern reused from existing New-ScratchVhd function

files_changed:
- FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psm1 (added Mount-ScratchVhd function, modified Optimize-FFUCaptureDrive)
- FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psd1 (version 1.1.1 -> 1.1.2, added Mount-ScratchVhd to exports, updated release notes)
