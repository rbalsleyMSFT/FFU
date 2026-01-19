---
phase: 02-bug-fixes-critical
plan: 01
subsystem: driver-management
tags: [dell, drivers, timeout, process-management, bug-fix]
dependency-graph:
  requires: []
  provides: [timeout-based-driver-extraction, process-tree-termination]
  affects: [02-02, 02-03, 02-04]
tech-stack:
  added: []
  patterns: [WaitForExit-timeout, Get-CimInstance-process-discovery]
key-files:
  created: []
  modified:
    - FFUDevelopment/Modules/FFU.Constants/FFU.Constants.psm1
    - FFUDevelopment/Modules/FFU.Drivers/FFU.Drivers.psm1
    - FFUDevelopment/Modules/FFU.Constants/FFU.Constants.psd1
    - FFUDevelopment/Modules/FFU.Drivers/FFU.Drivers.psd1
decisions:
  - id: TIMEOUT_30S
    summary: "30-second timeout calibrated for 5-15s typical extraction with safety margin"
    rationale: "Driver extraction typically completes in 5-15 seconds; 30 seconds provides generous margin without excessive wait"
metrics:
  duration: "~10 minutes"
  completed: 2026-01-19
---

# Phase 2 Plan 1: Fix Dell Chipset Driver Extraction Hang Summary

**One-liner:** Timeout-based Dell driver extraction using WaitForExit() with proper process tree termination

## What Was Done

### Task 1: Add Timeout Constant
Added `DRIVER_EXTRACTION_TIMEOUT_SECONDS = 30` to FFU.Constants module in the "Wait/Sleep Times" section. This constant provides a configurable timeout for Dell/Intel driver extraction processes that may spawn GUI windows and hang indefinitely.

### Task 2: Implement Timeout-Based Extraction
Refactored Get-DellDrivers function in FFU.Drivers module:

**Before (problematic):**
```powershell
$process = Invoke-Process -FilePath $driverFilePath -ArgumentList $arguments -Wait $false
Start-Sleep -Seconds ([FFUConstants]::DRIVER_EXTRACTION_WAIT)  # Fixed 5-second wait
$childProcesses = Get-ChildProcesses $process.Id
```

**After (fixed):**
```powershell
$process = Start-Process -FilePath $driverFilePath -ArgumentList $arguments -PassThru -NoNewWindow
$timeoutSeconds = [FFUConstants]::DRIVER_EXTRACTION_TIMEOUT_SECONDS
$completed = $process.WaitForExit($timeoutSeconds * 1000)

if (-not $completed) {
    # Kill child processes first (Intel GUI windows)
    $childProcesses = Get-CimInstance Win32_Process -Filter "ParentProcessId = $($process.Id)"
    foreach ($child in $childProcesses) {
        Stop-Process -Id $child.ProcessId -Force
    }
    # Kill parent process
    Stop-Process -Id $process.Id -Force
}
```

**Key improvements:**
1. `WaitForExit(timeout)` - Proper timeout instead of blind sleep
2. `Get-CimInstance Win32_Process` - More reliable child process discovery than `Get-ChildProcesses`
3. Kill children before parent - Prevents orphaned GUI windows
4. Detailed logging - Logs timeout events and exit codes

### Task 3: Update Module Versions
- FFU.Drivers: 1.0.5 -> 1.0.6
- FFU.Constants: 1.1.1 -> 1.1.2
- Added detailed release notes documenting BUG-04 fix

## Commits

| Hash | Type | Description |
|------|------|-------------|
| eb058e0 | feat | Add DRIVER_EXTRACTION_TIMEOUT_SECONDS constant |
| d09f625 | fix | Add timeout-based Dell driver extraction |
| 117b6ed | chore | Bump module versions for BUG-04 fix |

## Verification Results

| Check | Status |
|-------|--------|
| Module loads without errors | PASS |
| Timeout constant returns 30 | PASS |
| WaitForExit pattern present | PASS |
| Module manifest valid | PASS |

## Decisions Made

| Decision | Rationale |
|----------|-----------|
| 30-second timeout | Typical extraction: 5-15s; 30s provides generous safety margin |
| Get-CimInstance over Get-ChildProcesses | More reliable WMI-based process discovery |
| Kill children before parent | Prevents orphaned Intel GUI windows |
| Keep SERVICE_STARTUP_WAIT after kill | Allow 1-second cleanup before file operations |

## Deviations from Plan

None - plan executed exactly as written.

## Next Phase Readiness

- FFU.Drivers module enhanced with timeout protection
- DRIVER_EXTRACTION_TIMEOUT_SECONDS constant available for future use
- Pattern can be applied to other OEM driver extractors if similar issues arise

## Files Modified

1. `FFUDevelopment/Modules/FFU.Constants/FFU.Constants.psm1` - Added timeout constant
2. `FFUDevelopment/Modules/FFU.Drivers/FFU.Drivers.psm1` - Refactored extraction logic
3. `FFUDevelopment/Modules/FFU.Constants/FFU.Constants.psd1` - Version bump + release notes
4. `FFUDevelopment/Modules/FFU.Drivers/FFU.Drivers.psd1` - Version bump + release notes
