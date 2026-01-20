# Project State: FFU Builder

## Project Reference

See: .planning/PROJECT.md (updated 2026-01-20)

**Core value:** Enable rapid, reliable Windows deployment through pre-configured FFU images
**Current focus:** v1.8.1 Bug Fixes

## Current Position

**Milestone:** v1.8.1 Bug Fixes
**Phase:** 11 - Windows Update Preview Filtering (in progress)
**Plan:** 02 of 4 complete
**Status:** In progress
**Last activity:** 2026-01-20 - Completed 11-02-PLAN.md (UI checkbox and build script filtering)

Progress: [##------] 25% (2/8 total plans: 2/4 phase 11 + 0/4 phase 12)

## Completed Milestones

| Milestone | Status | Phases | Date |
|-----------|--------|--------|------|
| v1.8.0 Codebase Health | SHIPPED | 1-10 (33 plans) | 2026-01-20 |

## Recent Activity

- 2026-01-20: **PLAN 11-02 COMPLETE** - UI checkbox and build script filtering logic
  - Added chkIncludePreviewUpdates checkbox to Updates tab
  - Wired checkbox to config save/load
  - Added IncludePreviewUpdates parameter and -preview filter to build script
  - Commits: 20c7754, be1f628, b7ba336
- 2026-01-20: **PLAN 11-01 COMPLETE** - Config schema and migration for IncludePreviewUpdates
  - Added IncludePreviewUpdates boolean property to schema (default: false)
  - Updated FFU.ConfigMigration to v1.1 with migration support
  - Commits: 99ecc47, d086bbe
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

## Open Issues

**Deferred bugs (not in v1.8.1 scope):**
- HP Driver extraction exit code 1168 (all HP models)
- Dell CatalogPC.xml missing
- expand.exe fails on large MSU files (fallback works)

## Blockers

None.

## Session Continuity

**Last session:** 2026-01-20
**Stopped at:** Completed 11-02-PLAN.md
**Resume file:** None
**Next action:** Execute 11-03-PLAN.md (Test coverage for preview filter)

---
*State updated: 2026-01-20*
