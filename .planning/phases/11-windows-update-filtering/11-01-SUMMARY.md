---
phase: 11
plan: 01
subsystem: config
tags: [config-schema, migration, preview-updates]

dependency-graph:
  requires: []
  provides: [IncludePreviewUpdates-schema, config-migration-v1.1]
  affects: [11-02, 11-03, 11-04]

tech-stack:
  added: []
  patterns: [config-schema-versioning, migration-with-defaults]

key-files:
  created: []
  modified:
    - FFUDevelopment/config/ffubuilder-config.schema.json
    - FFUDevelopment/Modules/FFU.ConfigMigration/FFU.ConfigMigration.psm1
    - FFUDevelopment/Modules/FFU.ConfigMigration/FFU.ConfigMigration.psd1

decisions:
  - id: D-11-01-01
    decision: Place IncludePreviewUpdates after UpdatePreviewCU in schema
    rationale: Logical grouping with other update-related settings

metrics:
  duration: ~10 minutes
  completed: 2026-01-20
---

# Phase 11 Plan 01: Config Schema and Migration for IncludePreviewUpdates Summary

**One-liner:** Added IncludePreviewUpdates boolean property (default: false) to config schema v1.1 with automatic migration for existing configs.

## What Was Built

### Task 1: Config Schema Update

Added the `IncludePreviewUpdates` property to `ffubuilder-config.schema.json`:

```json
"IncludePreviewUpdates": {
    "type": "boolean",
    "default": false,
    "description": "When set to true, allows preview/optional updates in Windows Update searches. When false (default), search queries exclude preview updates to ensure only GA (Generally Available) releases are downloaded. Affects Cumulative Updates and .NET Framework updates."
}
```

- Property type: boolean
- Default value: false (exclude preview updates)
- Placement: After UpdatePreviewCU for logical grouping

### Task 2: Config Migration Module Update

Updated `FFU.ConfigMigration` module:

1. **Schema version bump:** `1.0` -> `1.1`
2. **Migration logic added:** Configs without `IncludePreviewUpdates` get default value `false`
3. **Module version bump:** `1.0.0` -> `1.0.1`
4. **Preservation behavior:** Existing configs with property already set are not modified

Migration region code:
```powershell
#region Migration: Add IncludePreviewUpdates default (v1.1)
if (-not $migrated.ContainsKey('IncludePreviewUpdates')) {
    $migrated['IncludePreviewUpdates'] = $false
    $changes += "Added default 'IncludePreviewUpdates=false' (preview updates excluded by default)"
}
#endregion
```

## Commits

| Commit | Type | Description |
|--------|------|-------------|
| 99ecc47 | feat | Add IncludePreviewUpdates property to config schema |
| d086bbe | feat | Add config migration for IncludePreviewUpdates property |

## Verification Results

All verification checks passed:

1. **Schema validation:** IncludePreviewUpdates property exists with correct type and default
2. **Migration test:** Old configs (v1.0) correctly migrated to v1.1 with `IncludePreviewUpdates=false`
3. **Preservation test:** Existing configs with `IncludePreviewUpdates=true` preserved correctly
4. **Module import:** FFU.ConfigMigration imports without errors

## Deviations from Plan

None - plan executed exactly as written.

## Dependencies for Next Plans

This plan provides the foundation for:

- **11-02:** UI checkbox can now reference `IncludePreviewUpdates` property
- **11-03:** Build logic can read `IncludePreviewUpdates` from config
- **11-04:** Integration testing can verify end-to-end flow

## Success Criteria Status

- [x] ffubuilder-config.schema.json contains IncludePreviewUpdates property
- [x] Property type is boolean with default false
- [x] FFU.ConfigMigration schema version bumped to 1.1
- [x] Migration adds IncludePreviewUpdates=false for configs without it
- [x] Existing configs with IncludePreviewUpdates are not modified
- [x] Module imports without errors
