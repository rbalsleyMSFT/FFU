# Project State: FFU Builder

## Project Reference

See: .planning/PROJECT.md (updated 2026-01-20)

**Core value:** Enable rapid, reliable Windows deployment through pre-configured FFU images
**Current focus:** v1.8.1 Bug Fixes — COMPLETE

## Current Position

**Milestone:** v1.8.1 Bug Fixes
**Phase:** 13 - Fix UI Default for IncludePreviewUpdates (COMPLETE)
**Plan:** 1 of 1 (COMPLETE)
**Status:** Milestone complete
**Last activity:** 2026-01-20 — Completed 13-01-PLAN.md

Progress: 100% (3/3 phases complete)
[##########] 100%

## Completed Milestones

| Milestone | Status | Phases | Date |
|-----------|--------|--------|------|
| v1.8.0 Codebase Health | SHIPPED | 1-10 (33 plans) | 2026-01-20 |
| v1.8.1 Bug Fixes | SHIPPED | 11-13 (5 plans) | 2026-01-20 |

## Recent Activity

- 2026-01-20: **PHASE 13 COMPLETE** - UI Default Fix
  - 1 plan executed, gap closure complete
  - Added `IncludePreviewUpdates = $false` to Get-GeneralDefaults
  - Phase 11 E2E flow now passes completely (all 9 steps)
  - Commit: 24600cd
- 2026-01-20: **PHASE 12 COMPLETE** - VHDX Drive Letter Stability
  - 2 plans executed, verification passed (8/8 must-haves)
  - Set-OSPartitionDriveLetter utility function in FFU.Imaging
  - Integrated into Invoke-MountScratchDisk with NoteProperty attachment
  - HyperVProvider MountVirtualDisk with retry and validation
  - VMwareProvider MountVirtualDisk with validation
  - 17 unit tests passing
  - Commits: dd4f0e4, c5ddefa, 92df108, e37b34a, cd557bd, e833763, 5c370cd, 8e24e24, dc7e5df
- 2026-01-20: **PHASE 11 COMPLETE** - Windows Update Preview Filtering
  - 2 plans executed, verification passed
  - Config schema with IncludePreviewUpdates (default: false)
  - Config migration adds property to existing configs
  - UI checkbox in Updates tab
  - Build script filtering logic for CU and .NET searches
  - Commits: 99ecc47, d086bbe, 262a459, 20c7754, be1f628, b7ba336, e3ac4b4
- 2026-01-20: **MILESTONE v1.8.1 STARTED**

## Key Decisions from v1.8.1

| ID | Decision | Rationale | Plan |
|----|----------|-----------|------|
| D-11-01-01 | Place IncludePreviewUpdates after UpdatePreviewCU | Logical grouping with update settings | 11-01 |
| D-11-02-01 | Apply -preview exclusion filter to search query string | Microsoft Update Catalog search supports negative keywords | 11-02 |
| D-11-02-02 | UpdatePreviewCU explicit request is NOT filtered | When user explicitly wants preview CU, do not exclude | 11-02 |
| D-12-01-01 | Place function after New-RecoveryPartition in FFU.Imaging.psm1 | Logical grouping with partition functions | 12-01 |
| D-12-01-02 | Use GPT type for OS partition detection | More reliable than labels which can change | 12-01 |
| D-12-01-03 | Default preferred letter to W | Consistent with New-OSPartition initial assignment | 12-01 |
| D-12-02-01 | Use NoteProperty to attach drive letter to disk object | Maintains backward compatibility | 12-02 |
| D-12-02-02 | Add retry logic with exponential backoff to HyperVProvider | Handles transient failures during disk operations | 12-02 |
| D-12-02-03 | Add drive letter normalization to VMwareProvider | Ensures consistent X:\ format | 12-02 |
| D-13-01-01 | Place IncludePreviewUpdates after UpdatePreviewCU in defaults | Consistent with D-11-01-01 logical grouping | 13-01 |

## Open Issues

**Deferred bugs (not in v1.8.1 scope):**
- HP Driver extraction exit code 1168 (all HP models)
- Dell CatalogPC.xml missing
- expand.exe fails on large MSU files (fallback works)

## Blockers

None.

## Session Continuity

**Last session:** 2026-01-20
**Stopped at:** Completed 13-01-PLAN.md - Milestone v1.8.1 complete
**Resume file:** None
**Next action:** Ready for next milestone planning

---
*State updated: 2026-01-20*
