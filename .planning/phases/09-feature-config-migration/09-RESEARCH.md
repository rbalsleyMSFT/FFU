# Phase 9: Feature - Config Migration - Research

**Researched:** 2026-01-19
**Domain:** JSON Configuration Schema Versioning, Migration Patterns, Backward Compatibility
**Confidence:** HIGH

## Summary

Implementing config migration for FFU Builder requires adding a version field to the JSON schema, creating transformation functions for deprecated/renamed properties, and integrating migration prompts into the config loading flow. The codebase already has strong foundations:

1. **JSON Schema validation** - Test-FFUConfiguration in FFU.Core validates configs against schema
2. **Deprecated property handling** - Schema marks 7 properties as deprecated with descriptions
3. **Auto-load pattern** - Invoke-AutoLoadPreviousEnvironment reads configs at UI startup
4. **PS5.1/PS7+ compatibility** - ConvertTo-HashtableRecursive helper already exists in FFU.Checkpoint

The primary challenges are: (1) the schema currently lacks a version field, (2) no migration logic exists to transform old configs, and (3) deprecated properties are ignored but not actively migrated to new equivalents.

**Primary recommendation:** Add a `configSchemaVersion` field to the schema (starting at "1.0"), create an FFU.ConfigMigration module with `Invoke-FFUConfigMigration` function that transforms deprecated properties to their modern equivalents, and hook migration into both the UI auto-load flow and CLI config loading in BuildFFUVM.ps1.

## Current State Analysis

### What Already Exists

| Component | Location | Reusability |
|-----------|----------|-------------|
| JSON Schema with validation | config/ffubuilder-config.schema.json | HIGH - Add version field |
| Test-FFUConfiguration | FFU.Core.psm1 lines 1807-2099 | HIGH - Validate pre/post migration |
| 7 deprecated properties in schema | schema lines 531-567 | HIGH - Migration targets defined |
| Invoke-AutoLoadPreviousEnvironment | FFUUI.Core.Config.psm1 line 914 | HIGH - Hook point for UI migration |
| Config loading in BuildFFUVM.ps1 | Lines 710-712 | HIGH - Hook point for CLI migration |
| ConvertTo-HashtableRecursive | FFU.Checkpoint.psm1 lines 104-151 | HIGH - PS5.1 compatibility helper |
| Update-UIFromConfig | FFUUI.Core.Config.psm1 lines 376-758 | MEDIUM - Handles legacy property names |

### What Is Missing

| Gap | Impact | Required Work |
|-----|--------|---------------|
| Schema version field | Cannot detect outdated configs | Add `configSchemaVersion` property |
| Migration functions | Old configs stay with deprecated fields | Create transformation logic |
| Version comparison logic | Cannot determine if migration needed | Compare config vs current schema |
| Migration prompts | User not informed of changes | Add UI dialog / CLI prompt |
| Migration history | Cannot track applied migrations | Consider migration log |

### Deprecated Properties and Their Replacements

| Deprecated Property | Replacement | Migration Action |
|---------------------|-------------|------------------|
| `AppsPath` | Derived from FFUDevelopmentPath | Remove (computed dynamically) |
| `CopyOfficeConfigXML` | `OfficeConfigXMLFile` | If true, prompt for path |
| `DownloadDrivers` | `Make` and `Model` parameters | If true, set Make to prompt value |
| `InstallWingetApps` | `InstallApps` and `AppListPath` | If true, set InstallApps=true |
| `OfficePath` | Derived from FFUDevelopmentPath | Remove (computed dynamically) |
| `Threads` | Automatic parallel processing | Remove (ignored) |
| `Verbose` | CLI `-Verbose` switch | Remove (use switch instead) |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ConvertFrom-Json | PowerShell built-in | Parse config JSON | Native, cross-version |
| ConvertTo-Json | PowerShell built-in | Write migrated config | Native, -Depth 10 for nested |
| Test-FFUConfiguration | FFU.Core v1.0.10+ | Validate before/after migration | Already exists, tested |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| ConvertTo-HashtableRecursive | FFU.Checkpoint v1.0.0 | PS5.1 JSON conversion | When -AsHashtable unavailable |
| System.Version | .NET built-in | Version comparison | Compare schema versions |
| Copy-Item | PowerShell built-in | Backup before migration | Preserve original config |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| In-place migration | New file with suffix | In-place cleaner, backup original |
| Schema version string | Semantic version object | String simpler, sufficient for this use |
| Per-property migrations | Full transformation function | Property-based allows incremental updates |

## Architecture Patterns

### Recommended Schema Version Field

Add to `ffubuilder-config.schema.json`:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "properties": {
    "configSchemaVersion": {
      "type": "string",
      "pattern": "^[0-9]+\\.[0-9]+$",
      "default": "1.0",
      "description": "Schema version of this configuration file. Used for automatic migration of older configs."
    },
    // ... existing properties
  }
}
```

### Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-01-19 | Initial versioned schema, 7 deprecated properties |
| Future | TBD | New deprecations, breaking changes |

### Migration Function Pattern

```powershell
function Invoke-FFUConfigMigration {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config,

        [Parameter()]
        [string]$TargetVersion = "1.0",

        [Parameter()]
        [switch]$CreateBackup,

        [Parameter()]
        [string]$ConfigPath  # For backup creation
    )

    $currentVersion = $Config['configSchemaVersion']
    if ([string]::IsNullOrEmpty($currentVersion)) {
        $currentVersion = "0.0"  # Pre-versioning configs
    }

    # Version comparison
    $current = [System.Version]::Parse($currentVersion)
    $target = [System.Version]::Parse($TargetVersion)

    if ($current -ge $target) {
        WriteLog "Config already at version $currentVersion (target: $TargetVersion)"
        return $Config
    }

    WriteLog "Migrating config from version $currentVersion to $TargetVersion"

    # Create backup if path provided
    if ($CreateBackup -and $ConfigPath) {
        $backupPath = "$ConfigPath.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item -Path $ConfigPath -Destination $backupPath
        WriteLog "Created backup at $backupPath"
    }

    $migrated = $Config.Clone()
    $changes = @()

    # Migration: Remove deprecated path properties (computed dynamically)
    foreach ($prop in @('AppsPath', 'OfficePath')) {
        if ($migrated.ContainsKey($prop)) {
            $migrated.Remove($prop)
            $changes += "Removed deprecated property '$prop' (now computed from FFUDevelopmentPath)"
        }
    }

    # Migration: Verbose -> removed (use CLI switch)
    if ($migrated.ContainsKey('Verbose')) {
        $migrated.Remove('Verbose')
        $changes += "Removed deprecated property 'Verbose' (use -Verbose CLI switch instead)"
    }

    # Migration: Threads -> removed (automatic)
    if ($migrated.ContainsKey('Threads')) {
        $migrated.Remove('Threads')
        $changes += "Removed deprecated property 'Threads' (parallel processing now automatic)"
    }

    # Migration: InstallWingetApps -> InstallApps
    if ($migrated.ContainsKey('InstallWingetApps') -and $migrated['InstallWingetApps']) {
        $migrated['InstallApps'] = $true
        $migrated.Remove('InstallWingetApps')
        $changes += "Migrated 'InstallWingetApps' to 'InstallApps=true'"
    }

    # Migration: DownloadDrivers -> prompt for Make (cannot auto-migrate)
    if ($migrated.ContainsKey('DownloadDrivers') -and $migrated['DownloadDrivers']) {
        if (-not $migrated.ContainsKey('Make') -or [string]::IsNullOrEmpty($migrated['Make'])) {
            $changes += "WARNING: 'DownloadDrivers' was true but 'Make' not specified - set Make/Model manually"
        }
        $migrated.Remove('DownloadDrivers')
    }

    # Migration: CopyOfficeConfigXML -> prompt for path (cannot auto-migrate)
    if ($migrated.ContainsKey('CopyOfficeConfigXML') -and $migrated['CopyOfficeConfigXML']) {
        if (-not $migrated.ContainsKey('OfficeConfigXMLFile') -or [string]::IsNullOrEmpty($migrated['OfficeConfigXMLFile'])) {
            $changes += "WARNING: 'CopyOfficeConfigXML' was true but 'OfficeConfigXMLFile' not specified - set path manually"
        }
        $migrated.Remove('CopyOfficeConfigXML')
    }

    # Set new version
    $migrated['configSchemaVersion'] = $TargetVersion

    # Log changes
    foreach ($change in $changes) {
        WriteLog "Migration: $change"
    }

    return @{
        Config = $migrated
        Changes = $changes
        FromVersion = $currentVersion
        ToVersion = $TargetVersion
    }
}
```

### Integration Point: UI Auto-Load

```powershell
# In Invoke-AutoLoadPreviousEnvironment, before Update-UIFromConfig:
$migrationResult = Invoke-FFUConfigMigration -Config $configContent -TargetVersion "1.0"

if ($migrationResult.Changes.Count -gt 0) {
    # UI mode: Show migration dialog
    $changeText = $migrationResult.Changes -join "`n"
    $msg = "Your configuration file has been migrated from version $($migrationResult.FromVersion) to $($migrationResult.ToVersion).`n`nChanges:`n$changeText"
    [System.Windows.MessageBox]::Show($msg, "Configuration Migrated", "OK", "Information")

    # Apply migrated config
    $configContent = $migrationResult.Config
}
```

### Integration Point: CLI Config Load

```powershell
# In BuildFFUVM.ps1, after loading config (around line 711):
if ($ConfigFile -and (Test-Path -Path $ConfigFile)) {
    $configData = Get-Content $ConfigFile -Raw | ConvertFrom-Json

    # Convert to hashtable for migration
    $configHashtable = ConvertTo-HashtableRecursive -InputObject $configData

    # Check if migration needed
    $migrationResult = Invoke-FFUConfigMigration -Config $configHashtable -TargetVersion "1.0" -CreateBackup -ConfigPath $ConfigFile

    if ($migrationResult.Changes.Count -gt 0) {
        WriteLog "Configuration migrated from v$($migrationResult.FromVersion) to v$($migrationResult.ToVersion)"
        foreach ($change in $migrationResult.Changes) {
            WriteLog "  - $change"
        }

        # In CLI mode, prompt to save migrated config
        $response = Read-Host "Save migrated configuration? (Y/N)"
        if ($response -eq 'Y') {
            $migrationResult.Config | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigFile -Encoding UTF8
            WriteLog "Migrated configuration saved to $ConfigFile"
        }
    }

    $configData = $migrationResult.Config
    # Continue with existing key processing...
}
```

### Recommended Project Structure

```
Modules/
  FFU.ConfigMigration/
    FFU.ConfigMigration.psd1
    FFU.ConfigMigration.psm1   # Invoke-FFUConfigMigration, Test-FFUConfigVersion
```

### Anti-Patterns to Avoid

- **Silent migration without backup:** Always preserve the original config before modifying
- **Losing data on unknown properties:** Preserve properties not in schema for forward compatibility
- **Hard-coding version in multiple places:** Define current schema version in one location
- **Mixing migration with validation:** Keep migration separate from Test-FFUConfiguration

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Version comparison | String comparison | System.Version | Handles 1.0 < 1.10 correctly |
| JSON parsing | Manual parsing | ConvertFrom-Json | Robust, handles edge cases |
| Backup naming | Random suffix | Timestamp suffix | Chronological, identifiable |
| PS5.1 hashtable conversion | Manual property iteration | ConvertTo-HashtableRecursive | Already exists in FFU.Checkpoint |

**Key insight:** The migration logic should be transformation-based (apply changes) rather than replacement-based (new config from scratch), to preserve any user customizations.

## Common Pitfalls

### Pitfall 1: Breaking Forward Compatibility
**What goes wrong:** New FFU Builder version cannot read configs from newer versions
**Why it happens:** Strict validation rejects unknown properties from future schemas
**How to avoid:** Allow additionalProperties or warn but continue on unknown properties
**Warning signs:** "Unknown property" errors on valid configs

### Pitfall 2: Losing User Customizations
**What goes wrong:** Migration overwrites user-specific settings
**Why it happens:** Migration assumes defaults instead of preserving values
**How to avoid:** Only modify properties that need migration, preserve everything else
**Warning signs:** Users report settings "reset" after migration

### Pitfall 3: Circular Migration
**What goes wrong:** Config gets migrated repeatedly on each load
**Why it happens:** Version not updated in config file after migration
**How to avoid:** Set configSchemaVersion in migrated config, save to disk
**Warning signs:** "Migration applied" message every time config loads

### Pitfall 4: Breaking Change Without Migration Path
**What goes wrong:** Property renamed without migration, old configs fail
**Why it happens:** Schema updated but no migration function for the change
**How to avoid:** Every schema change must have corresponding migration code
**Warning signs:** "Missing required property" errors on old configs

### Pitfall 5: PS5.1 vs PS7 Compatibility Issues
**What goes wrong:** Migration works in PS7, fails in PS5.1
**Why it happens:** Using -AsHashtable (PS7 only) without fallback
**How to avoid:** Use ConvertTo-HashtableRecursive from FFU.Checkpoint
**Warning signs:** "Invalid parameter" errors in Windows PowerShell 5.1

## Code Examples

### Example 1: Test-FFUConfigVersion Function

```powershell
# Source: New function for FFU.ConfigMigration module
function Test-FFUConfigVersion {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$ConfigPath,

        [Parameter(Mandatory, ParameterSetName = 'Object')]
        [hashtable]$Config,

        [Parameter()]
        [string]$CurrentSchemaVersion = "1.0"
    )

    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        $content = Get-Content $ConfigPath -Raw
        $configData = $content | ConvertFrom-Json

        # Convert to hashtable
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            $Config = $content | ConvertFrom-Json -AsHashtable
        } else {
            $Config = ConvertTo-HashtableRecursive -InputObject $configData
        }
    }

    $configVersion = $Config['configSchemaVersion']
    if ([string]::IsNullOrEmpty($configVersion)) {
        $configVersion = "0.0"  # Pre-versioning
    }

    $current = [System.Version]::Parse($CurrentSchemaVersion)
    $config = [System.Version]::Parse($configVersion)

    [PSCustomObject]@{
        ConfigVersion = $configVersion
        CurrentSchemaVersion = $CurrentSchemaVersion
        NeedsMigration = $config -lt $current
        VersionDifference = $current.CompareTo($config)
    }
}
```

### Example 2: Schema Version Constant

```powershell
# Source: Add to FFU.Constants or FFU.ConfigMigration
[string]$script:CurrentConfigSchemaVersion = "1.0"

function Get-FFUConfigSchemaVersion {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    return $script:CurrentConfigSchemaVersion
}
```

### Example 3: Migration Prompt for UI

```powershell
# Source: Pattern for FFUUI.Core.Config.psm1
function Show-ConfigMigrationDialog {
    param(
        [Parameter(Mandatory)]
        [hashtable]$MigrationResult
    )

    if ($MigrationResult.Changes.Count -eq 0) {
        return $true  # No migration needed
    }

    $changesList = $MigrationResult.Changes | ForEach-Object {
        if ($_ -like "WARNING:*") {
            "  [!] $_"
        } else {
            "  [+] $_"
        }
    }
    $changesText = $changesList -join "`n"

    $message = @"
Your configuration file was created with an older version of FFU Builder.

From version: $($MigrationResult.FromVersion)
To version: $($MigrationResult.ToVersion)

The following changes will be applied:
$changesText

A backup of your original configuration will be created.

Do you want to continue with the migration?
"@

    $result = [System.Windows.MessageBox]::Show(
        $message,
        "Configuration Migration Required",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )

    return ($result -eq [System.Windows.MessageBoxResult]::Yes)
}
```

### Example 4: Preserving Unknown Properties

```powershell
# Source: Pattern for forward compatibility
function Invoke-FFUConfigMigration {
    # ... parameter block ...

    # Start with a COPY of the original config
    # This preserves any properties we don't know about (future versions)
    $migrated = @{}
    foreach ($key in $Config.Keys) {
        $migrated[$key] = $Config[$key]
    }

    # Apply known migrations (remove deprecated, transform values)
    # Unknown properties are preserved as-is

    # ...migration logic...

    return @{
        Config = $migrated
        Changes = $changes
        # ...
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| No versioning | Schema version field | This phase | Enables migration tracking |
| Silent deprecation | Migration with notification | This phase | Users understand changes |
| Breaking changes | Backward-compatible migration | Industry standard | Old configs keep working |

**Deprecated/outdated:**
- Accepting unversioned configs indefinitely: Mark as legacy, encourage migration
- Hardcoded property transforms: Use schema-driven migration rules

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Config corruption during migration | LOW | HIGH | Backup before migration, atomic writes |
| Missing migration for property | MEDIUM | MEDIUM | Comprehensive test coverage for each deprecated property |
| PS5.1 compatibility issues | LOW | MEDIUM | Use ConvertTo-HashtableRecursive, test on both versions |
| User confusion on migration | LOW | LOW | Clear dialog messages explaining changes |

## Open Questions

### 1. Where to Store Current Schema Version?
- **What we know:** Need a single source of truth
- **What's unclear:** FFU.Constants? FFU.ConfigMigration? Schema file itself?
- **Recommendation:** Define in FFU.ConfigMigration module; schema file just documents it

### 2. Auto-Save vs Prompt After Migration?
- **What we know:** UI context different from CLI context
- **What's unclear:** Should UI auto-save migrated config? Always prompt?
- **Recommendation:** UI shows dialog and auto-saves if user confirms; CLI prompts

### 3. Migration History/Audit Trail?
- **What we know:** Backup files created before migration
- **What's unclear:** Should we log all migrations to a history file?
- **Recommendation:** WriteLog is sufficient; backup files provide rollback capability

### 4. Handling Configs with Multiple Missing Properties?
- **What we know:** Some deprecated properties require user input (Make, OfficeConfigXMLFile path)
- **What's unclear:** Batch prompt or individual prompts?
- **Recommendation:** Show all warnings at once, let user fix manually

## Sources

### Primary (HIGH confidence)
- ffubuilder-config.schema.json - Current schema with 7 deprecated properties (lines 531-567)
- FFU.Core.psm1 - Test-FFUConfiguration implementation (lines 1807-2099)
- FFUUI.Core.Config.psm1 - Config loading flow (lines 914-958 for auto-load)
- BuildFFUVM.ps1 - CLI config loading (lines 710-714)
- FFU.Checkpoint.psm1 - ConvertTo-HashtableRecursive (lines 104-151)

### Secondary (MEDIUM confidence)
- [Microsoft Learn: JSON Schema](https://json-schema.org/understanding-json-schema/) - Schema versioning patterns
- [Semantic Versioning](https://semver.org/) - Version format standard

### Tertiary (LOW confidence)
- General configuration management best practices from industry experience

## Metadata

**Confidence breakdown:**
- Current state analysis: HIGH - Based on direct codebase examination
- Architecture patterns: HIGH - Follows existing codebase conventions
- Migration logic: HIGH - Clear transformation rules from deprecated property descriptions
- Integration points: HIGH - Identified specific code locations

**Research date:** 2026-01-19
**Valid until:** 90 days (stable domain, JSON patterns well-established)
