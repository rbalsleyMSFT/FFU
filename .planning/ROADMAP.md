# Roadmap: FFU Builder v1.8.1

**Created:** 2026-01-20
**Milestone:** v1.8.1 Bug Fixes
**Goal:** Fix critical bugs discovered during v1.8.0 testing

## Phase Summary

| Phase | Name | Requirements | Plans | Status |
|-------|------|--------------|-------|--------|
| 11 | Windows Update Preview Filtering | UPD-01, UPD-02, UPD-03, UPD-04 | 2 | ✓ Complete |
| 12 | VHDX Drive Letter Stability | VHDX-01, VHDX-02, VHDX-03 | 2 | ✓ Complete |

**Total:** 2 phases covering 7 requirements

## Phases

### Phase 11: Windows Update Preview Filtering

**Goal:** Exclude preview/beta Windows Updates by default with opt-in capability

**Requirements:**
- UPD-01: Build process excludes preview/beta Windows Updates by default (GA releases only)
- UPD-02: User can opt-in to include preview updates via UI checkbox in Updates tab
- UPD-03: `IncludePreviewUpdates` setting persisted in configuration file
- UPD-04: Config migration handles new `IncludePreviewUpdates` property (defaults to false)

**Plans:** 2 plans

Plans:
- [x] 11-01-PLAN.md - Config schema and migration for IncludePreviewUpdates
- [x] 11-02-PLAN.md - UI checkbox and build script filtering logic

**Success Criteria:**
- [x] Windows Update search excludes preview versions unless explicitly requested
- [x] Updates tab in UI has checkbox for "Include Preview Updates"
- [x] Checkbox state persists in config file as `IncludePreviewUpdates` boolean
- [x] Config migration adds property with `false` default for existing configs
- [ ] Tests verify filtering logic works correctly

**Completed:** 2026-01-20

**Key Files:**
- `BuildFFUVM.ps1` - Update search logic
- `BuildFFUVM_UI.xaml` - Add checkbox to Updates tab
- `FFUUI.Core.Config.psm1` - Handle checkbox state
- `config/ffubuilder-config.schema.json` - Schema update
- `FFU.ConfigMigration` - Migration handler

**Directory:** `.planning/phases/11-windows-update-filtering/`

---

### Phase 12: VHDX Drive Letter Stability

**Goal:** Fix OS partition drive letter lost during unattend file copy and verification

**Requirements:**
- VHDX-01: OS partition drive letter persists through unattend file copy and verification
- VHDX-02: Drive letter stability works with Hyper-V provider
- VHDX-03: Drive letter stability works with VMware provider

**Plans:** 2 plans

Plans:
- [x] 12-01-PLAN.md - Create Set-OSPartitionDriveLetter utility function in FFU.Imaging
- [x] 12-02-PLAN.md - Integrate drive letter guarantee into mount functions and verify providers

**Success Criteria:**
- [x] Drive letter remains assigned throughout unattend copy workflow
- [x] Verification step can access the same drive letter used for copy
- [x] Works correctly with Hyper-V VHDX mounting
- [x] Works correctly with VMware VMDK/VHDX mounting
- [x] Tests verify drive letter persistence

**Completed:** 2026-01-20

**Key Files:**
- `BuildFFUVM.ps1` - Drive letter assignment and retention
- `FFU.Imaging` - Partition/volume operations
- `FFU.Hypervisor` - Provider-specific mounting

**Directory:** `.planning/phases/12-vhdx-drive-letter/`

---

## Requirement Coverage

| Requirement | Phase | Description |
|-------------|-------|-------------|
| UPD-01 | 11 | Exclude preview/beta updates by default |
| UPD-02 | 11 | UI checkbox for preview opt-in |
| UPD-03 | 11 | Config persistence for setting |
| UPD-04 | 11 | Config migration support |
| VHDX-01 | 12 | Drive letter persistence |
| VHDX-02 | 12 | Hyper-V provider support |
| VHDX-03 | 12 | VMware provider support |

**Coverage:** 7/7 requirements mapped (100%)

---
*Roadmap created: 2026-01-20*
*Phase 11 planned: 2026-01-20*
*Phase 11 complete: 2026-01-20*
*Phase 12 planned: 2026-01-20*
*Phase 12 complete: 2026-01-20*
