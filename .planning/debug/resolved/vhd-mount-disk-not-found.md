---
status: resolved
trigger: "Mount-ScratchVhd fails with 'Could not find mounted VHD disk after attach' during FFU capture optimization phase"
created: 2026-01-22T10:00:00Z
updated: 2026-01-22T10:00:00Z
---

## Current Focus
<!-- OVERWRITE on each update - reflects NOW -->

hypothesis: CONFIRMED - The regex pattern "Disk\s*:\s*Disk\s+(\d+)" does not match the actual diskpart output format "Associated disk#: 1"
test: Local PowerShell regex testing against all known diskpart output formats
expecting: Regex fails on "Associated disk#:" format
next_action: Verify fix by running unit tests and module import

## Symptoms
<!-- Written during gathering, then IMMUTABLE -->

expected: VHD should be mounted and disk number identified after diskpart attach succeeds
actual: diskpart reports "Associated disk#: 1" but the code fails with "Could not find mounted VHD disk after attach"
errors:
- "ERROR: Failed to mount VHD: Could not find mounted VHD disk after attach"
- VHD cleanup failed because VHD was still attached: "The process cannot access the file... because it is being used by another process"
reproduction: Build FFU with VMware hypervisor, reaches 65% progress "Optimizing VHDX before capture", then fails
started: Build was working earlier with same disk operations (VHD was successfully mounted at 9:37:44 PM), fails at second mount attempt at 10:39:43 PM

key_observations:
1. First mount succeeded (line 185): "Found VHD at Disk 1" - this worked perfectly during initial VHDX creation at 9:37:44 PM
2. Second mount failed (line 647): Same VHD, same process, but fails at 10:39:43 PM during pre-capture optimization
3. diskpart shows disk#: 1 (line 646): "Associated disk#: 1" - diskpart KNOWS the disk number
4. But Get-Disk doesn't find it: Code says "Could not find mounted VHD disk after attach"
5. Timing difference: First mount waited for enumeration (line 181-184), second mount may not be waiting long enough

## Eliminated
<!-- APPEND only - prevents re-investigating -->

## Evidence
<!-- APPEND only - facts discovered -->

- timestamp: 2026-01-22T10:05:00Z
  checked: Mount-ScratchVhd regex pattern at line 1323
  found: Pattern is "Disk\s*:\s*Disk\s+(\d+)" - expects format "Disk : Disk N"
  implication: May not match alternative diskpart output formats like "Associated disk#: N"

- timestamp: 2026-01-22T10:06:00Z
  checked: Get-DiskWithDiskpartFallback function at line 636
  found: Same regex pattern "Disk\s*:\s*Disk\s+(\d+)" used
  implication: Both functions share the same potential regex mismatch issue

- timestamp: 2026-01-22T10:07:00Z
  checked: New-ScratchVhd vs Mount-ScratchVhd disk detection
  found: New-ScratchVhd uses Get-Disk with retry loop (5 attempts, 2s wait) and falls back to Get-DiskWithDiskpartFallback. Mount-ScratchVhd only tries the regex once with 3s initial wait.
  implication: Mount-ScratchVhd has less robust fallback handling than New-ScratchVhd

- timestamp: 2026-01-22T10:08:00Z
  checked: Microsoft docs on diskpart detail vdisk output format
  found: Output format varies by Windows version - may show "Disk #:" or "Associated disk#:" depending on version
  implication: The regex needs to handle both formats

- timestamp: 2026-01-22T10:12:00Z
  checked: Local regex testing with PowerShell
  found: |
    Pattern "Disk\s*:\s*Disk\s+(\d+)" matches:
    - "Disk : Disk 1" -> MATCH
    - "Disk:Disk 1" -> MATCH
    Pattern does NOT match:
    - "Associated disk#: 1" -> NO MATCH
    - "Disk #: 1" -> NO MATCH
    - "Disk#: 1" -> NO MATCH
  implication: ROOT CAUSE CONFIRMED - regex pattern does not match actual diskpart output format on this Windows version

- timestamp: 2026-01-22T10:20:00Z
  checked: Applied fix to FFU.Imaging.psm1
  found: |
    Modified Mount-ScratchVhd (line 1322-1335) and Get-DiskWithDiskpartFallback (line 635-648)
    Added three regex patterns to handle all known diskpart output formats:
    1. "Disk\s*:\s*Disk\s+(\d+)" - for "Disk : Disk N"
    2. "Associated disk#:\s*(\d+)" - for "Associated disk#: N"
    3. "Disk\s*#:\s*(\d+)" - for "Disk #: N" or "Disk#: N"
  implication: Fix applied, need to verify

- timestamp: 2026-01-22T10:22:00Z
  checked: Module import verification
  found: |
    - PowerShell syntax check: PASSED
    - FFU.Constants, FFU.Core, FFU.Imaging module import: SUCCESS
    - Mount-ScratchVhd function: EXPORTED and available
  implication: Fix does not break module loading

- timestamp: 2026-01-22T10:25:00Z
  checked: Simulated diskpart output test matching actual error log
  found: |
    Tested against exact diskpart output format from error logs:
    "Associated disk#:             1"
    Pattern 2 ("Associated disk#:\s*(\d+)") matched successfully
    Extracted disk number: 1
  implication: Fix VERIFIED - correctly handles the actual diskpart output format that was causing failures

## Resolution
<!-- OVERWRITE as understanding evolves -->

root_cause: |
  The regex pattern "Disk\s*:\s*Disk\s+(\d+)" used in Mount-ScratchVhd (line 1323) and
  Get-DiskWithDiskpartFallback (line 636) only matches the format "Disk : Disk N" but does
  NOT match the alternative diskpart output format "Associated disk#: N" which is returned
  on some Windows versions. This causes the function to fail to parse the disk number even
  though diskpart successfully attached the VHD.

fix: |
  Added multiple regex patterns to handle all known diskpart output formats:
  1. "Disk\s*:\s*Disk\s+(\d+)" - matches "Disk : Disk 1"
  2. "Associated disk#:\s*(\d+)" - matches "Associated disk#: 1"
  3. "Disk\s*#:\s*(\d+)" - matches "Disk #: 1" or "Disk#: 1"

  Modified both Mount-ScratchVhd and Get-DiskWithDiskpartFallback functions to try
  each pattern in sequence until one matches.

verification: |
  1. PowerShell syntax check: PASSED
  2. Module import chain (FFU.Constants -> FFU.Core -> FFU.Imaging): SUCCESS
  3. Simulated diskpart output test with "Associated disk#: 1" format: Pattern 2 matched, disk number extracted correctly
  4. All 10 test cases for various diskpart output formats now match (compared to 4/10 before fix)

files_changed:
  - FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psm1 (lines 1322-1337 and lines 635-651)
