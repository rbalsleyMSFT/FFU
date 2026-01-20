---
phase: 10
plan: 01
subsystem: hypervisor
tags: [vmware, fallback, resilience, preflight]

dependency-graph:
  requires: []
  provides:
    - VMX filesystem search fallback
    - vmxtoolkit optional preflight
    - VMware provider resilience
  affects:
    - VMware builds without vmxtoolkit

tech-stack:
  added: []
  patterns:
    - Filesystem fallback for VM discovery
    - Warning vs Failed for optional dependencies

key-files:
  created:
    - Tests/Unit/FFU.Hypervisor.VMwareFallback.Tests.ps1
  modified:
    - FFUDevelopment/Modules/FFU.Hypervisor/Providers/VMwareProvider.ps1
    - FFUDevelopment/Modules/FFU.Preflight/FFU.Preflight.psm1
    - FFUDevelopment/Modules/FFU.Preflight/FFU.Preflight.psd1

decisions:
  - key: vmxtoolkit-optional
    choice: Return Warning not Failed when vmxtoolkit missing
    rationale: vmrun.exe handles all VM operations; vmxtoolkit is enhancement only

metrics:
  duration: 7m25s
  completed: 2026-01-20
---

# Phase 10 Plan 01: VMware vmxtoolkit Fallback Summary

VMware provider now works fully without vmxtoolkit via vmrun.exe and filesystem search fallback.

## One-liner

SearchVMXFilesystem method enables VM discovery without vmxtoolkit; pre-flight treats vmxtoolkit as optional.

## Commits

| Hash | Type | Description |
|------|------|-------------|
| 1213a20 | feat | Add VMX filesystem search fallback to VMwareProvider |
| c09587e | feat | Make vmxtoolkit optional in pre-flight validation |
| d401873 | test | Add Pester tests for VMware fallback behavior |

## Changes Made

### Task 1: VMX Filesystem Search Fallback

Added `SearchVMXFilesystem` hidden method to VMwareProvider that scans common VM storage locations:

```powershell
hidden [string[]] SearchVMXFilesystem([string]$VMName = $null) {
    # Search locations:
    # 1. VMware preferences.ini default VM path
    # 2. Documents\Virtual Machines
    # 3. C:\VMs, D:\VMs
    # Returns array of VMX file paths
}
```

Updated `GetVM` to use filesystem search as fallback after vmrun list check:
- Finds stopped VMs that aren't in vmrun list
- Uses Get-VMwarePowerStateWithVmrun for accurate state

Updated `GetAllVMs` to combine vmrun list with filesystem search:
- Deduplicates VMs found in both sources
- Returns complete VM list including stopped VMs

### Task 2: vmxtoolkit Optional in Pre-flight

Changed `Test-FFUVmxToolkit` to return Warning instead of Failed:

```powershell
# Before
return New-FFUCheckResult -Status 'Failed' -Message 'vmxtoolkit required'

# After
return New-FFUCheckResult -Status 'Warning' `
    -Message 'vmxtoolkit not installed (optional - vmrun.exe fallback available)' `
    -Details @{ FallbackAvailable = $true }
```

Updated `Invoke-FFUPreflight` to handle vmxtoolkit warnings as non-blocking:
- Adds to warnings list, not errors
- Does not set `IsValid = $false`
- Build proceeds with vmrun.exe fallback

### Task 3: Pester Tests

Created comprehensive test suite (363 lines, 18 tests):

**SearchVMXFilesystem tests:**
- Returns empty array when no VMs found
- Finds VMX files in Documents\Virtual Machines
- Filters by VM name when parameter provided
- Handles missing directories gracefully
- Reads preferences.ini for default VM path

**GetVM/GetAllVMs fallback tests:**
- Returns VM info from vmrun list when running
- Returns VM info from filesystem search when vmrun misses
- Returns null when VM not found anywhere
- Deduplicates VMs found in multiple sources

**Test-FFUVmxToolkit warning tests:**
- Returns Passed when vmxtoolkit installed
- Returns Warning (not Failed) when missing
- Message indicates vmrun.exe fallback available
- Details include FallbackAvailable = $true

## Verification Results

| Check | Status | Notes |
|-------|--------|-------|
| SearchVMXFilesystem exists | PASS | Hidden method in VMwareProvider |
| Test-FFUVmxToolkit returns Warning | PASS | Status: Warning when module missing |
| Pester tests pass | PASS | 18/18 tests passing |
| VMware builds work without vmxtoolkit | PASS | vmrun.exe fallback functional |

## Decisions Made

| Decision | Rationale |
|----------|-----------|
| vmxtoolkit is optional | vmrun.exe handles all VM operations (start, stop, state) |
| Filesystem search depth 2 | Balance thoroughness vs performance for common VM paths |
| Warning not Failed for optional deps | Blocking on optional deps frustrates users unnecessarily |

## Deviations from Plan

None - plan executed exactly as written.

## Next Phase Readiness

**Ready for:** Plan 10-02 (Lenovo catalogv2.xml fallback) or 10-03 (WimMount recovery)

**Dependencies satisfied:**
- VMware provider is now resilient to missing vmxtoolkit
- Pre-flight validation passes with only vmrun.exe available

**No blockers identified.**
