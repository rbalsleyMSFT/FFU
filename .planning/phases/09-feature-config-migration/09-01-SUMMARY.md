---
phase: 09-feature-config-migration
plan: 01
subsystem: configuration
tags: [json-schema, migration, versioning, backward-compatibility]

dependency-graph:
  requires:
    - "FFU.Checkpoint (ConvertTo-HashtableRecursive pattern)"
  provides:
    - "FFU.ConfigMigration module"
    - "configSchemaVersion field in schema"
    - "Deprecated property migration"
  affects:
    - "09-02: UI integration"
    - "09-03: CLI integration"

tech-stack:
  added:
    - "FFU.ConfigMigration v1.0.0"
  patterns:
    - "Schema versioning (major.minor format)"
    - "Pre-versioning detection (0.0)"
    - "Forward compatibility (unknown properties preserved)"
    - "Backup before migration (timestamp suffix)"

key-files:
  created:
    - "FFUDevelopment/Modules/FFU.ConfigMigration/FFU.ConfigMigration.psd1"
    - "FFUDevelopment/Modules/FFU.ConfigMigration/FFU.ConfigMigration.psm1"
    - "Tests/Unit/FFU.ConfigMigration.Tests.ps1"
  modified:
    - "FFUDevelopment/config/ffubuilder-config.schema.json"

decisions:
  - id: "schema-version-format"
    choice: "major.minor string format"
    rationale: "Simple, sufficient for versioning, pattern-validated"
  - id: "pre-version-detection"
    choice: "No configSchemaVersion = version 0.0"
    rationale: "Distinguishes legacy configs from versioned ones"
  - id: "module-dependency"
    choice: "FFU.Checkpoint for ConvertTo-HashtableRecursive"
    rationale: "Reuse existing PS5.1 compatibility helper"
  - id: "forward-compatibility"
    choice: "Preserve unknown properties"
    rationale: "Newer configs work with older tool versions"

metrics:
  duration: "5m 34s"
  completed: "2026-01-20"
  tests-added: 59
  files-created: 3
  files-modified: 1
---

# Phase 09 Plan 01: FFU.ConfigMigration Module Summary

**One-liner:** Config schema versioning with migration functions for 7 deprecated properties, 59 Pester tests

## What Was Built

Created the FFU.ConfigMigration module that provides automatic detection and migration of older configuration files to the current schema format.

### Schema Version Support
- Added `configSchemaVersion` property to JSON schema
- Pattern validation: `^[0-9]+\.[0-9]+$` (major.minor format)
- Default value: "1.0" (current schema version)
- Pre-versioning configs (no field) treated as "0.0"

### Module Functions (4 exported)

| Function | Purpose |
|----------|---------|
| `Get-FFUConfigSchemaVersion` | Returns current schema version ("1.0") |
| `Test-FFUConfigVersion` | Detects if config needs migration |
| `Invoke-FFUConfigMigration` | Transforms deprecated properties |
| `ConvertTo-HashtableRecursive` | PS5.1 compatibility helper |

### Deprecated Property Migrations (7 total)

| Property | Migration Action | Notes |
|----------|------------------|-------|
| AppsPath | Removed | Computed from FFUDevelopmentPath |
| OfficePath | Removed | Computed from FFUDevelopmentPath |
| Verbose | Removed | Use -Verbose CLI switch |
| Threads | Removed | Automatic parallel processing |
| InstallWingetApps | Migrated to InstallApps | When true, sets InstallApps=true |
| DownloadDrivers | Removed with WARNING | Requires Make/Model configuration |
| CopyOfficeConfigXML | Removed with WARNING | Requires OfficeConfigXMLFile path |

## Implementation Details

### Version Comparison
Uses `[System.Version]::Parse()` for correct comparison (1.0 < 1.10), not string comparison.

### Backup Creation
When `-CreateBackup` is specified with `-ConfigPath`, creates backup with timestamp suffix:
```
config.json.backup-20260120-044505
```

### Forward Compatibility
Unknown properties in config are preserved during migration. This allows newer configs to work with older tool versions.

### PS5.1 Compatibility
`ConvertTo-HashtableRecursive` handles PowerShell 5.1's lack of `-AsHashtable` parameter on `ConvertFrom-Json`.

## Test Coverage

59 comprehensive Pester tests covering:
- Module import and exports (3 tests)
- Get-FFUConfigSchemaVersion (4 tests)
- Test-FFUConfigVersion (12 tests)
- ConvertTo-HashtableRecursive (8 tests)
- Invoke-FFUConfigMigration (32 tests)
  - Version handling (5)
  - Each deprecated property (18)
  - Forward compatibility (2)
  - Backup functionality (4)
  - Changes array (3)

## Commits

| Commit | Type | Description |
|--------|------|-------------|
| 06786c4 | feat | Add configSchemaVersion to JSON schema |
| 0550ada | feat | Create FFU.ConfigMigration module |
| 407d1a3 | test | Add FFU.ConfigMigration Pester tests (59 tests) |

## Deviations from Plan

None - plan executed exactly as written.

## Next Steps (Phase 9 Plans 02-03)

1. **Plan 02:** UI Integration - Hook migration into `Invoke-AutoLoadPreviousEnvironment`
2. **Plan 03:** CLI Integration - Hook migration into `BuildFFUVM.ps1` config loading

## Success Criteria Verification

- [x] configSchemaVersion property exists in schema with default "1.0"
- [x] FFU.ConfigMigration module exports 4 functions
- [x] Get-FFUConfigSchemaVersion returns "1.0"
- [x] Test-FFUConfigVersion correctly identifies pre-versioning configs
- [x] Invoke-FFUConfigMigration transforms all 7 deprecated properties
- [x] All Pester tests pass (59 tests, minimum was 20)
