---
phase: 04-performance-optimization
plan: 02
subsystem: hypervisor
tags: [performance, event-driven, cim, hyper-v, vm-monitoring]

dependency-graph:
  requires:
    - "Phase 1 (tech debt cleanup)"
    - "FFU.Hypervisor module (v1.2.9+)"
  provides:
    - "Event-driven VM state monitoring for Hyper-V"
    - "Wait-VMStateChange function with CIM event subscription"
    - "HyperVProvider.WaitForState method"
    - "IHypervisorProvider.WaitForState interface method"
  affects:
    - "BuildFFUVM.ps1 VM polling loops (can be refactored to use WaitForState)"
    - "Future VM state monitoring code"

tech-stack:
  added: []
  patterns:
    - "CIM event subscription (Register-CimIndicationEvent)"
    - "WQL queries for Msvm_ComputerSystem state changes"
    - "Event-driven polling replacement pattern"

key-files:
  created:
    - "FFUDevelopment/Modules/FFU.Hypervisor/Public/Wait-VMStateChange.ps1"
    - "Tests/Unit/FFU.Hypervisor.EventDriven.Tests.ps1"
  modified:
    - "FFUDevelopment/Modules/FFU.Hypervisor/Providers/HyperVProvider.ps1"
    - "FFUDevelopment/Modules/FFU.Hypervisor/Classes/IHypervisorProvider.ps1"
    - "FFUDevelopment/Modules/FFU.Hypervisor/FFU.Hypervisor.psd1"
    - "FFUDevelopment/Modules/FFU.Hypervisor/FFU.Hypervisor.psm1"
    - "Tests/Unit/FFU.Hypervisor.Tests.ps1"

decisions:
  - key: "cim-over-wmi"
    choice: "Use Register-CimIndicationEvent instead of Register-WmiEvent"
    rationale: "CIM is the modern standard, better cross-platform support, available in PowerShell Core"
  - key: "within-2-polling"
    choice: "WITHIN 2 in WQL query (2-second internal polling)"
    rationale: "Balance between responsiveness and CPU usage; lower values cause high WmiPrvSE CPU"
  - key: "defense-in-depth-check"
    choice: "Direct Get-VM state check as fallback during event wait"
    rationale: "WMI events can occasionally be dropped; direct check ensures correctness"
  - key: "string-type-check"
    choice: "Use GetType().FullName string matching instead of -is operator"
    rationale: "Avoids type resolution issues when Hyper-V module isn't loaded"
  - key: "vmware-keeps-polling"
    choice: "VMware provider does not implement event-driven monitoring"
    rationale: "VMware lacks CIM event support; vmrun CLI has no event subscription capability"

metrics:
  duration: "7 minutes"
  completed: "2026-01-19"
  tests-added: 23
  tests-total: 142
  commits: 3
---

# Phase 4 Plan 02: Event-Driven VM State Monitoring Summary

**One-liner:** CIM event subscription for Hyper-V VM state monitoring via Register-CimIndicationEvent with fallback polling and cleanup guarantees

## What Was Done

### Task 1: Created Wait-VMStateChange Function
Created `FFUDevelopment/Modules/FFU.Hypervisor/Public/Wait-VMStateChange.ps1`:
- Uses `Register-CimIndicationEvent` to subscribe to `Msvm_ComputerSystem` state changes
- Targets Hyper-V WMI namespace `root\virtualization\v2`
- Maps VM states to EnabledState values (Running=2, Off=3, Paused=32768, Saved=32769)
- Early exit when VM already at target state
- Configurable timeout (default 1 hour) and poll interval (default 500ms)
- Defense-in-depth direct state check during wait loop
- Cleanup in `finally` block (Unregister-Event, Remove-Job, Remove-Variable)
- Progress logging every 30 seconds

### Task 2: Added WaitForState Method to Providers
**HyperVProvider.ps1:**
- Added `[bool] WaitForState([object]$VM, [string]$TargetState, [int]$TimeoutSeconds)` method
- Delegates to `Wait-VMStateChange` function
- Uses string-based type checking to avoid type resolution issues

**IHypervisorProvider.ps1:**
- Added interface method definition with documentation
- Notes that VMware falls back to polling (no CIM support)

**FFU.Hypervisor.psd1:**
- Version bumped to 1.3.0
- Added `Wait-VMStateChange` to FunctionsToExport
- Added release notes documenting the changes

**FFU.Hypervisor.psm1:**
- Added `Wait-VMStateChange` to Export-ModuleMember

### Task 3: Added Pester Tests
Created `Tests/Unit/FFU.Hypervisor.EventDriven.Tests.ps1` with 23 tests:
- **Context: When VM is already in target state** (2 tests) - Early exit behavior
- **Context: When VM does not exist** (1 test) - Error handling
- **Context: CIM Event Registration** (3 tests) - Correct namespace, VM name in query, Msvm_ComputerSystem class
- **Context: Cleanup** (2 tests) - Unregister-Event and Remove-Job called
- **Context: State Mapping** (5 tests) - All valid states accepted, invalid states rejected
- **Context: Timeout Behavior** (2 tests) - Returns false on timeout, writes warning
- **Context: HyperVProvider.WaitForState Integration** (4 tests) - Method exists, function exported, version check
- **Context: Wait-VMStateChange Function Structure** (4 tests) - CmdletBinding, OutputType, Register-CimIndicationEvent, finally block

Updated `Tests/Unit/FFU.Hypervisor.Tests.ps1`:
- Changed version check from exact "1.2.7" to ">= 1.3.0"

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed type resolution error in HyperVProvider.WaitForState**
- **Found during:** Task 2 verification
- **Issue:** Using `-is [Microsoft.HyperV.PowerShell.VirtualMachine]` causes type resolution error when Hyper-V module isn't loaded
- **Fix:** Changed to string-based type check using `GetType().FullName -like '*HyperV*VirtualMachine*'`
- **Files modified:** HyperVProvider.ps1
- **Commit:** f75cde4

## Technical Details

### WQL Query Structure
```sql
SELECT * FROM __InstanceModificationEvent WITHIN 2
WHERE TargetInstance ISA 'Msvm_ComputerSystem'
AND TargetInstance.ElementName = '$VMName'
```

### State Mapping (Msvm_ComputerSystem.EnabledState)
| State | EnabledState Value | Description |
|-------|-------------------|-------------|
| Running | 2 | Enabled |
| Off | 3 | Disabled |
| Paused | 32768 | Paused |
| Saved | 32769 | Suspended |

### Why Event-Driven Matters
- **Current polling:** Start-Sleep loops check VM state every 2-5 seconds
- **Event-driven:** CIM subscription notifies immediately on state change
- **Benefit:** Reduced CPU usage, faster response to state changes

### Why WITHIN 2 (Not WITHIN 1)
Lower WITHIN values cause higher CPU usage in WmiPrvSE.exe. WITHIN 2 provides:
- Sufficient granularity for VM state changes (VMs don't change state multiple times per second)
- Lower CPU overhead
- Acceptable response time (worst case 2 seconds)

## Verification Results

All verification criteria met:
- [x] Wait-VMStateChange function created using Register-CimIndicationEvent
- [x] HyperVProvider has WaitForState method using new function
- [x] Event subscription cleanup in finally block (no leaks)
- [x] Module version incremented to 1.3.0 with release notes
- [x] Function exported from FFU.Hypervisor module
- [x] 23 Pester tests pass for event-driven monitoring
- [x] 119 existing FFU.Hypervisor tests still pass (142 total)

## Commits

| Hash | Type | Description |
|------|------|-------------|
| dec2afd | feat | Add Wait-VMStateChange function with CIM event subscription |
| f75cde4 | feat | Add WaitForState method to HyperVProvider and IHypervisorProvider |
| 3c861d9 | test | Add Pester tests for event-driven VM state monitoring |

## Next Phase Readiness

This plan is **complete**. The event-driven monitoring infrastructure is in place.

**Future integration opportunities:**
- BuildFFUVM.ps1 VM startup polling (lines 4292-4310) can call `$provider.WaitForState($VM, 'Running', 3600)`
- BuildFFUVM.ps1 VM shutdown polling (lines 4379-4411) can call `$provider.WaitForState($VM, 'Off', 3600)`
- These changes would require updating BuildFFUVM.ps1 to use the provider pattern more extensively

**Dependencies resolved:**
- Wait-VMStateChange is available for any Hyper-V VM state monitoring
- HyperVProvider.WaitForState provides object-oriented access
- Interface allows future VMware implementation if vmrest gains event support
