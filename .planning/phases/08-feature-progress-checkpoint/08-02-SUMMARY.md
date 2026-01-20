---
phase: 08
plan: 02
subsystem: checkpoint
tags: [checkpoint, persistence, buildffuvm, integration]

dependency-graph:
  requires:
    - 08-01 (FFU.Checkpoint module)
  provides:
    - BuildFFUVM.ps1 checkpoint persistence
    - 9 checkpoint save locations
    - Checkpoint cleanup on success
  affects:
    - 08-03 (Resume detection logic)

tech-stack:
  added: []
  patterns:
    - Checkpoint-guarded persistence calls
    - Conditional checkpoint save based on flow path

file-tracking:
  key-files:
    created: []
    modified:
      - FFUDevelopment/BuildFFUVM.ps1

decisions:
  - decision: "9 checkpoint locations (8 named, checkpoint 6 has two paths)"
    date: 2026-01-20
    rationale: "Both InstallApps and non-InstallApps paths need checkpoint persistence before FFU capture"
  - decision: "No passwords in checkpoint data"
    date: 2026-01-20
    rationale: "Security requirement - FFUCaptureUsername/Password must never be persisted"
  - decision: "$script:CheckpointEnabled control flag"
    date: 2026-01-20
    rationale: "Allows checkpoint persistence to be disabled if needed without code changes"

metrics:
  duration: "4 minutes"
  completed: "2026-01-20"
---

# Phase 8 Plan 02: BuildFFUVM.ps1 Checkpoint Integration Summary

**One-liner:** Added 9 Save-FFUBuildCheckpoint calls at cancellation checkpoint locations with cleanup on success

## What Was Done

Integrated the FFU.Checkpoint module into BuildFFUVM.ps1 to persist build state at strategic phase boundaries.

### Task 1: Add FFU.Checkpoint module import

Added at line 828:
- `Import-Module "FFU.Checkpoint"` - early in module import list (no dependencies)
- `$script:CheckpointEnabled = $true` - control flag for checkpoint persistence

### Task 2: Add checkpoint saves at existing checkpoint locations

Added 9 `Save-FFUBuildCheckpoint` calls matching the existing cancellation checkpoints:

| # | Phase | Line | CompletedPhase | Key Artifacts |
|---|-------|------|----------------|---------------|
| 1 | After Pre-flight | ~1733 | PreflightValidation | preflightValidated |
| 2 | Before Driver Download | ~2378 | DriverDownload | driversDownloadStarted |
| 3 | Before VHDX Creation | ~3604 | WindowsDownload | windowsImageReady, driversDownloaded |
| 4 | After VHDX Creation | ~3914 | VHDXCreation | vhdxCreated |
| 5 | Before VM Start | ~4411 | VMCreation | vmCreated |
| 6a | Before FFU Capture (non-InstallApps) | ~4512 | VMExecution | vmReady |
| 6b | After VM Shutdown (InstallApps) | ~4637 | VMExecution | appsInstalled, vmShutdown |
| 7 | Before Deployment Media | ~4758 | FFUCapture | ffuCaptured |
| 8 | Before USB Creation | ~4808 | DeploymentMedia | deploymentMediaCreated |

Each checkpoint saves:
- **Configuration**: Build parameters (WindowsRelease, WindowsSKU, etc.)
- **Artifacts**: Boolean flags for completed work (vhdxCreated, ffuCaptured, etc.)
- **Paths**: File paths for resume (VHDXPath, DriversFolder, FFUCaptureLocation, etc.)

**Security**: No passwords or credentials included in any checkpoint call.

### Task 3: Add checkpoint cleanup on successful completion

Added at line ~4976:
```powershell
if ($script:CheckpointEnabled) {
    Remove-FFUBuildCheckpoint -FFUDevelopmentPath $FFUDevelopmentPath
    WriteLog "Build completed successfully - checkpoint removed"
}
```

This ensures:
- Successful builds don't leave stale checkpoints
- Only interrupted/failed builds have checkpoints for resume

## Commits

| Commit | Type | Description |
|--------|------|-------------|
| d4b3340 | feat | Integrate checkpoint persistence into BuildFFUVM.ps1 |

## Key Files

| File | Purpose |
|------|---------|
| `FFUDevelopment/BuildFFUVM.ps1` | Core build script with checkpoint integration |

## Deviations from Plan

**Minor clarification:** The plan mentions "8 strategic locations" but the actual implementation has 9 checkpoint calls because cancellation checkpoint 6 appears twice in the code (for InstallApps and non-InstallApps paths). Both paths need checkpoint persistence.

## Verification Results

| Check | Result |
|-------|--------|
| FFU.Checkpoint import present | PASS |
| 9 Save-FFUBuildCheckpoint calls | PASS |
| No passwords in checkpoints | PASS |
| Remove-FFUBuildCheckpoint on success | PASS |
| Script parses without errors | PASS |

## Checkpoint Data Summary

**What is saved:**
- Build configuration parameters (WindowsRelease, WindowsSKU, VMName, etc.)
- Artifact completion flags (vhdxCreated, ffuCaptured, etc.)
- File paths (VHDXPath, DriversFolder, FFUCaptureLocation)

**What is NOT saved:**
- FFUCaptureUsername
- FFUCapturePassword
- Any SecureString or credential objects

## Next Phase Readiness

**Ready for Plan 03:** Resume detection logic
- Checkpoints are now being saved at 9 locations
- Checkpoint file created at `$FFUDevelopmentPath\.ffubuilder-checkpoint.json`
- Get-FFUBuildCheckpoint can detect existing checkpoint
- Resume logic can skip completed phases based on lastCompletedPhase value
