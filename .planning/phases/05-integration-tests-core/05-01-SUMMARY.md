---
phase: 05-integration-tests-core
plan: 01
subsystem: testing
tags: [pester, integration-tests, ffu-vm, hyper-v, mocking]

dependency-graph:
  requires:
    - FFU.VM module (existing)
    - Pester 5.x framework (existing)
  provides:
    - FFU.VM integration test suite
    - Mock-based testing patterns for Hyper-V cmdlets
    - Infrastructure detection pattern
  affects:
    - Future integration test plans (05-02, 05-03)
    - CI/CD test pipeline

tech-stack:
  added: []
  patterns:
    - Global stub functions for unavailable modules
    - Module-scoped mocking with -ModuleName
    - Tag-based conditional test execution
    - Add-Member for Dispose method mocking

key-files:
  created:
    - Tests/Integration/FFU.VM.Integration.Tests.ps1
  modified: []

decisions:
  - decision: "Stub functions for WriteLog and FFU.Core dependencies"
    rationale: "FFU.VM calls WriteLog which is defined in FFU.Common; stubs allow mocking"
  - decision: "Return null from Get-VMHardDiskDrive mock"
    rationale: "Avoids Hyper-V type validation errors with Set-VMFirmware"
  - decision: "Test HGS Guardian instead of Enable-VMTPM"
    rationale: "TPM config is non-critical try/catch; Guardian is the entry point"
  - decision: "Add-Member ScriptMethod for Dispose mocking"
    rationale: "PSCustomObject doesn't have Dispose; Add-Member adds it"

metrics:
  duration: "~15 minutes"
  completed: 2026-01-19
---

# Phase 5 Plan 1: FFU.VM Integration Tests Summary

**One-liner:** 22 mock-based Pester integration tests for FFU.VM module covering VM lifecycle, capture setup, and environment cleanup operations

## What Was Built

Created comprehensive integration test suite for FFU.VM module at `Tests/Integration/FFU.VM.Integration.Tests.ps1` with:

1. **Infrastructure Detection** - Automatic Hyper-V availability detection
2. **Stub Functions** - Global stubs for WriteLog, Hyper-V cmdlets, DISM cmdlets, and FFU.Core dependencies
3. **New-FFUVM Tests** - VM creation workflow, parameter passing, error handling
4. **Remove-FFUVM Tests** - VM removal, HGS Guardian cleanup, graceful handling
5. **Set-CaptureFFU Tests** - User creation, SMB share, access control, expiry
6. **Get-FFUEnvironment Tests** - FFU VM detection, stopping running VMs
7. **Real Infrastructure Tests** - Tagged 'RealInfra' for conditional execution

## Test Coverage

| Describe Block | Tests | Coverage |
|----------------|-------|----------|
| Infrastructure Detection | 2 | Hyper-V availability check |
| New-FFUVM Integration | 7 | VM creation workflow, errors |
| Remove-FFUVM Integration | 4 | VM removal, cleanup |
| Set-CaptureFFU Integration | 5 | User/share creation |
| Get-FFUEnvironment Integration | 2 | Environment cleanup |
| Real Infrastructure Tests | 2 | Conditional real tests |
| **Total** | **22** | **All FFU.VM functions** |

## Key Patterns Established

### Stub Function Pattern
```powershell
# Create stubs before module import
function global:WriteLog { param($LogText) }

if (-not (Get-Module -Name Hyper-V -ListAvailable)) {
    function global:New-VM { param($Name, ...) }
}
```

### Module-Scoped Mocking
```powershell
Mock WriteLog { } -ModuleName 'FFU.VM'
Mock New-VM { return [PSCustomObject]@{ Name = $Name } } -ModuleName 'FFU.VM'
```

### Add-Member for Dispose
```powershell
Mock Get-LocalUserAccount {
    $mockUser = [PSCustomObject]@{ Name = 'ffu_user' }
    $mockUser | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value { }
    return $mockUser
} -ModuleName 'FFU.VM'
```

### Conditional Real Infrastructure Tests
```powershell
Describe 'Real Infrastructure Tests' -Tag 'RealInfra' {
    It 'Should query actual VMs' -Skip:(-not $script:HyperVAvailable) {
        # Real test code
    }
}
```

## Commits

| Hash | Description |
|------|-------------|
| b615394 | Add FFU.VM integration test infrastructure (Task 1-2) |
| cbf2cda | Add Remove-FFUVM, Set-CaptureFFU, Get-FFUEnvironment tests (Task 3) |

## Verification Results

```
Total: 22 | Passed: 20 | Failed: 0 | Skipped: 0 | NotRun: 2
```

- 20 mock-based tests pass on any machine
- 2 real infrastructure tests tagged 'RealInfra' (skip when Hyper-V unavailable)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] WriteLog command not found**
- **Found during:** Task 2 initial test run
- **Issue:** Mock WriteLog failed because command didn't exist
- **Fix:** Added global WriteLog stub function before module import
- **Files modified:** Tests/Integration/FFU.VM.Integration.Tests.ps1

**2. [Rule 3 - Blocking] Hyper-V type validation errors**
- **Found during:** Task 2 test execution
- **Issue:** Set-VMFirmware -FirstBootDevice has strict type checking
- **Fix:** Return null from Get-VMHardDiskDrive mock to bypass type check
- **Files modified:** Tests/Integration/FFU.VM.Integration.Tests.ps1

**3. [Rule 1 - Bug] Dispose method not found**
- **Found during:** Task 3 test execution
- **Issue:** PSCustomObject doesn't have Dispose method
- **Fix:** Use Add-Member to add ScriptMethod Dispose to mock object
- **Files modified:** Tests/Integration/FFU.VM.Integration.Tests.ps1

## Next Steps

- Execute 05-02-PLAN.md for FFU.Drivers integration tests
- Execute 05-03-PLAN.md for FFU.Imaging integration tests
- Apply same patterns (stubs, module-scoped mocking, conditional tags)
