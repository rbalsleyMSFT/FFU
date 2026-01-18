---
phase: 01-tech-debt-cleanup
plan: 02
subsystem: FFU.Constants module
tags: [tech-debt, deprecated-code, cleanup, refactoring]

dependency-graph:
  requires: []
  provides:
    - Clean FFU.Constants module without deprecated properties
    - Modern GetDefault*Dir() methods as sole path API
  affects:
    - 01-03 (may reference FFU.Constants patterns)

tech-stack:
  added: []
  patterns:
    - Dynamic path resolution via GetDefault*Dir() methods
    - Environment variable overrides for path customization

key-files:
  created: []
  modified:
    - FFUDevelopment/Modules/FFU.Constants/FFU.Constants.psm1
    - FFUDevelopment/Modules/FFU.Constants/FFU.Constants.psd1
    - FFUDevelopment/version.json
    - Tests/Modules/Test-FFUConstants.ps1
    - Tests/Unit/FFU.Constants.DynamicPaths.Tests.ps1

decisions:
  - id: deprecated-removal-safe
    description: Confirmed no production code references deprecated properties before removal
    rationale: Grep search found only definitions in FFU.Constants.psm1 and test files

metrics:
  duration: ~10 minutes
  completed: 2026-01-17
---

# Phase 1 Plan 2: Remove Deprecated FFU.Constants Properties Summary

**One-liner:** Removed 6 deprecated static path properties and 3 legacy wrapper methods from FFU.Constants, reducing module from 586 to 509 lines.

## What Was Done

### Task 1: Verify No External Usage (Completed)
- Searched entire codebase for deprecated property references
- Confirmed: Only FFU.Constants.psm1 and test files reference deprecated code
- No production scripts or modules depend on deprecated properties

### Task 2: Remove Deprecated Code (Completed)
- Removed `#region Static Path Properties (for backward compatibility)`:
  - `$DEFAULT_WORKING_DIR`
  - `$DEFAULT_VM_DIR`
  - `$DEFAULT_CAPTURE_DIR`
  - `$DEFAULT_DRIVERS_DIR`
  - `$DEFAULT_APPS_DIR`
  - `$DEFAULT_UPDATES_DIR`
- Removed `#region Legacy Helper Methods (backward compatibility)`:
  - `GetWorkingDirectory()` wrapper
  - `GetVMDirectory()` wrapper
  - `GetCaptureDirectory()` wrapper
- Updated test files to use modern GetDefault*Dir() methods
- Removed backward compatibility tests that tested removed functionality

### Task 3: Update Versions and Run Tests (Completed)
- Incremented FFU.Constants module version: 1.1.0 -> 1.1.1
- Incremented FFUBuilder main version: 1.7.20 -> 1.7.21
- Added release notes documenting the deprecated code removal
- All 22 Pester tests pass

## Commits

| Commit | Type | Description |
|--------|------|-------------|
| 51d276b | refactor | Remove deprecated FFU.Constants path properties |
| a6351dc | chore | Update FFU.Constants version to 1.1.1 |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Updated test files to remove deprecated references**
- **Found during:** Task 2
- **Issue:** Test files referenced deprecated properties and legacy methods
- **Fix:** Updated Tests/Modules/Test-FFUConstants.ps1 and Tests/Unit/FFU.Constants.DynamicPaths.Tests.ps1
- **Files modified:** Tests/Modules/Test-FFUConstants.ps1, Tests/Unit/FFU.Constants.DynamicPaths.Tests.ps1
- **Commit:** 51d276b

## Key Metrics

| Metric | Before | After |
|--------|--------|-------|
| FFU.Constants.psm1 lines | 586 | 509 |
| Deprecated markers | 6 | 0 |
| Legacy wrapper methods | 3 | 0 |
| Pester tests | 22 | 22 (all pass) |

## Files Modified

1. **FFUDevelopment/Modules/FFU.Constants/FFU.Constants.psm1**
   - Removed deprecated static properties (lines 251-279)
   - Removed legacy wrapper methods (lines 506-551)

2. **FFUDevelopment/Modules/FFU.Constants/FFU.Constants.psd1**
   - Version: 1.1.0 -> 1.1.1
   - Added release notes for v1.1.1

3. **FFUDevelopment/version.json**
   - Main version: 1.7.20 -> 1.7.21
   - FFU.Constants version: 1.1.0 -> 1.1.1
   - Updated description

4. **Tests/Modules/Test-FFUConstants.ps1**
   - Updated to use GetDefault*Dir() methods instead of deprecated properties

5. **Tests/Unit/FFU.Constants.DynamicPaths.Tests.ps1**
   - Removed backward compatibility tests for removed methods
   - Updated method existence check list

## Verification Results

- [x] No external references to deprecated properties
- [x] FFU.Constants.psm1 has 0 DEPRECATED markers
- [x] Modern GetDefault*Dir() methods work correctly
- [x] Module manifest version incremented (1.1.1)
- [x] version.json updated (1.7.21)
- [x] All 22 Pester tests pass

## Next Phase Readiness

**Ready for:** Plans that depend on FFU.Constants (01-03)

**No blockers:** This plan completes DEBT-01 from the research document.

**Recommended next:** Continue with Wave 2 plans (01-03, 01-04, 01-05) which can now proceed.
