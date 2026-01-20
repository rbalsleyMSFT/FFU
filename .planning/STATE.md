# Project State: FFU Builder

## Project Reference

See: .planning/PROJECT.md (updated 2026-01-20)

**Core value:** Enable rapid, reliable Windows deployment through pre-configured FFU images
**Current focus:** v1.8.1 Bug Fixes

## Current Position

**Milestone:** v1.8.1 Bug Fixes
**Phase:** 12 - VHDX Drive Letter Stability (in progress)
**Plan:** 01 of 3 complete
**Status:** Plan 12-01 complete, ready for 12-02
**Last activity:** 2026-01-20 - Completed 12-01-PLAN.md

Progress: 67% (1/2 phases complete, 1/3 plans in phase 12)

## Completed Milestones

| Milestone | Status | Phases | Date |
|-----------|--------|--------|------|
| v1.8.0 Codebase Health | SHIPPED | 1-10 (33 plans) | 2026-01-20 |

## Recent Activity

- 2026-01-20: **PLAN 12-01 COMPLETE** - Set-OSPartitionDriveLetter Utility
  - New centralized function in FFU.Imaging for drive letter assignment
  - Handles already-assigned and missing drive letter cases
  - Preferred letter (W) with Z-to-D fallback
  - Retry logic (3 attempts) for transient failures
  - 17 unit tests passing
  - Commits: dd4f0e4, c5ddefa, 92df108
- 2026-01-20: **PHASE 11 COMPLETE** - Windows Update Preview Filtering
  - 2 plans executed, verification passed
  - Config schema with IncludePreviewUpdates (default: false)
  - Config migration adds property to existing configs
  - UI checkbox in Updates tab
  - Build script filtering logic for CU and .NET searches
  - Commits: 99ecc47, d086bbe, 262a459, 20c7754, be1f628, b7ba336, e3ac4b4
- 2026-01-20: **ROADMAP CREATED** for v1.8.1
  - Phase 11: Windows Update Preview Filtering (UPD-01 to UPD-04)
  - Phase 12: VHDX Drive Letter Stability (VHDX-01 to VHDX-03)
- 2026-01-20: **MILESTONE v1.8.1 STARTED**
  - Windows Update Preview Filtering
  - OS Partition Drive Letter Stability
- 2026-01-20: **MILESTONE v1.8.0 SHIPPED**
  - Archived to `.planning/milestones/v1.8.0-ROADMAP.md`
  - Tagged: v1.8.0

## Key Decisions from v1.8.1

| ID | Decision | Rationale | Plan |
|----|----------|-----------|------|
| D-11-01-01 | Place IncludePreviewUpdates after UpdatePreviewCU | Logical grouping with update settings | 11-01 |
| D-11-02-01 | Apply -preview exclusion filter to search query string | Microsoft Update Catalog search supports negative keywords | 11-02 |
| D-11-02-02 | UpdatePreviewCU explicit request is NOT filtered | When user explicitly wants preview CU, do not exclude | 11-02 |
| D-12-01-01 | Place function after New-RecoveryPartition in FFU.Imaging.psm1 | Logical grouping with partition functions | 12-01 |
| D-12-01-02 | Use GPT type for OS partition detection | More reliable than labels which can change | 12-01 |
| D-12-01-03 | Default preferred letter to W | Consistent with New-OSPartition initial assignment | 12-01 |

## Open Issues

**Deferred bugs (not in v1.8.1 scope):**
- HP Driver extraction exit code 1168 (all HP models)
- Dell CatalogPC.xml missing
- expand.exe fails on large MSU files (fallback works)

## Blockers

None.

## Session Continuity

**Last session:** 2026-01-20
**Stopped at:** Plan 12-01 complete
**Resume file:** None
**Next action:** Execute plan 12-02 (BuildFFUVM.ps1 integration)

---
*State updated: 2026-01-20*
