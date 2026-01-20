# Project State: FFU Builder

## Project Reference

See: .planning/PROJECT.md (updated 2026-01-20)

**Core value:** Enable rapid, reliable Windows deployment through pre-configured FFU images
**Current focus:** v1.8.1 Bug Fixes — Gap closure in progress

## Current Position

**Milestone:** v1.8.1 Bug Fixes
**Phase:** 13 - Fix UI Default for IncludePreviewUpdates (planned)
**Plan:** —
**Status:** Gap closure phase added from audit
**Last activity:** 2026-01-20 — Phase 13 created from audit gaps

Progress: 67% (2/3 phases complete)

## Completed Milestones

| Milestone | Status | Phases | Date |
|-----------|--------|--------|------|
| v1.8.0 Codebase Health | SHIPPED | 1-10 (33 plans) | 2026-01-20 |

## Recent Activity

- 2026-01-20: **PHASE 13 CREATED** - Gap closure from audit
  - UPD-02 gap: Get-GeneralDefaults missing IncludePreviewUpdates
  - Single task: Add `IncludePreviewUpdates = $false` to defaults
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
- 2026-01-20: **ROADMAP CREATED** for v1.8.1
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

## Open Issues

**Deferred bugs (not in v1.8.1 scope):**
- HP Driver extraction exit code 1168 (all HP models)
- Dell CatalogPC.xml missing
- expand.exe fails on large MSU files (fallback works)

## Blockers

None.

## Session Continuity

**Last session:** 2026-01-20
**Stopped at:** Phase 13 created from audit gaps
**Resume file:** None
**Next action:** `/gsd:plan-phase 13` to plan the gap closure fix

---
*State updated: 2026-01-20*
