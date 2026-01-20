---
phase: "08"
plan: "03"
subsystem: "checkpoint/resume"
tags: ["checkpoint", "resume", "phase-skip", "testing"]
dependency-graph:
  requires: ["08-02"]
  provides: ["resume-detection", "phase-skip-logic"]
  affects: ["08-04"]
tech-stack:
  added: []
  patterns: ["phase-ordering-map", "checkpoint-validation"]
key-files:
  created: []
  modified:
    - "FFUDevelopment/Modules/FFU.Checkpoint/FFU.Checkpoint.psm1"
    - "FFUDevelopment/Modules/FFU.Checkpoint/FFU.Checkpoint.psd1"
    - "FFUDevelopment/BuildFFUVM.ps1"
    - "Tests/Unit/FFU.Checkpoint.Tests.ps1"
decisions:
  - id: "08-03-001"
    decision: "Phase ordering implemented as hashtable map with numeric values"
    rationale: "Simple comparison logic, supports aliases for related phases"
  - id: "08-03-002"
    decision: "UI mode auto-resumes, CLI mode prompts user"
    rationale: "UI can implement own dialog; CLI needs interactive choice"
  - id: "08-03-003"
    decision: "Skip checks use Test-PhaseAlreadyComplete with checkpoint"
    rationale: "Centralized logic in module function, consistent across all phases"
metrics:
  duration: "~15 minutes"
  completed: "2026-01-20"
---

# Phase 8 Plan 3: Resume Detection and Phase Skip Logic Summary

**One-liner:** Resume detection with user prompt and phase skip logic using ordering map with alias support.

## What Was Built

### 1. Resume Helper Functions (FFU.Checkpoint v1.1.0)

**Test-CheckpointArtifacts:**
- Validates artifacts marked as created still exist on disk
- Checks VHDX, DriversFolder, FFUCaptureLocation, AppsISO paths
- Hyper-V VM existence validation when vmCreated=true
- Returns false if any required artifact is missing

**Test-PhaseAlreadyComplete:**
- Phase ordering map with 13 phases and 3 aliases
- Compares current phase against checkpoint's lastCompletedPhase
- Alias support: WindowsDownload=UpdatesDownload, VMCreation=VMSetup, VMExecution=VMStart
- Logs "RESUME: Phase X already completed" via WriteLog if available

### 2. Resume Detection in BuildFFUVM.ps1

**-NoResume Parameter:**
- Forces fresh build even when checkpoint exists
- Removes existing checkpoint before proceeding

**Checkpoint Detection Logic (after logging init):**
- Detects checkpoint at `.ffubuilder/checkpoint.json`
- Validates checkpoint structure with Test-FFUBuildCheckpoint
- Validates artifacts exist with Test-CheckpointArtifacts
- CLI mode: Interactive prompt with [R]esume / [N]ew options
- UI mode: Auto-resumes (MessagingContext indicates UI)

**Resume State Variables:**
- `$script:ResumeCheckpoint` - loaded checkpoint hashtable
- `$script:IsResuming` - boolean flag for skip checks
- `$script:ResumedVHDXPath`, `$script:ResumedVMPath`, `$script:ResumedDriversFolder`

### 3. Phase Skip Checks Throughout BuildFFUVM.ps1

| Phase | Lines | Skip Logic |
|-------|-------|------------|
| PreflightValidation | 1789-1797 | Wraps pre-flight validation block |
| DriverDownload | 2444-2459 | Restores DriversFolder, skips download |
| VHDXCreation | 3476-3495 | Restores VHDXPath/VMPath, simulates cache |
| FFUCapture | 4655-4868 | Wraps entire capture try/catch block |
| DeploymentMedia | 4912-4952 | Adds -not $skipDeploymentMedia condition |
| USBCreation | 4970-5008 | Adds -not $skipUSBCreation condition |

### 4. Test Coverage

**66 tests total (100% pass rate):**
- 11 tests for Test-CheckpointArtifacts
- 13 tests for Test-PhaseAlreadyComplete
- 42 existing tests for other checkpoint functions

**Test Categories:**
- Null/invalid input handling
- Artifact existence validation (files, directories)
- Phase ordering comparisons
- Alias phase handling
- Sequential phase progression

## Commits

| Hash | Type | Description |
|------|------|-------------|
| f5d38e6 | feat | Add resume helper functions to FFU.Checkpoint |
| 5b2d41b | feat | Add resume detection to BuildFFUVM.ps1 BEGIN block |
| d590284 | feat | Add phase skip checks throughout BuildFFUVM.ps1 |
| 3e59d6f | test | Add comprehensive tests for resume functions |

## Implementation Details

### Phase Ordering Map

```powershell
$phaseOrder = @{
    'PreflightValidation' = 1
    'DriverDownload'      = 2
    'UpdatesDownload'     = 3
    'WindowsDownload'     = 3   # Alias
    'AppsPreparation'     = 4
    'VHDXCreation'        = 5
    'WindowsUpdates'      = 6
    'VMSetup'             = 7
    'VMCreation'          = 7   # Alias
    'VMStart'             = 8
    'VMExecution'         = 8   # Alias
    'AppInstallation'     = 9
    'VMShutdown'          = 10
    'FFUCapture'          = 11
    'DeploymentMedia'     = 12
    'USBCreation'         = 13
}
```

### CLI Resume Prompt

```
========================================
  INTERRUPTED BUILD DETECTED
========================================

  Checkpoint from: 2026-01-20T01:30:00Z
  Last completed phase: VHDXCreation
  Progress: 35% complete

  [R] Resume from checkpoint
  [N] Start a fresh build

Enter choice (R/N):
```

## Verification Results

```powershell
# Test execution
Invoke-Pester -Path 'Tests/Unit/FFU.Checkpoint.Tests.ps1'
# Result: 66 tests passed, 0 failed
```

## Deviations from Plan

None - plan executed exactly as written.

## Next Phase Readiness

- Resume detection and phase skip logic complete
- Ready for 08-04: UI Integration for checkpoint display
- UI can now receive MessagingContext to indicate auto-resume mode
- All resume state variables available for UI status updates
