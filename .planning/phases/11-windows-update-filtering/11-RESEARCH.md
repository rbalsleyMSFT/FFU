# Phase 11: Windows Update Preview Filtering - Research

**Researched:** 2026-01-20
**Domain:** Windows Update Catalog Search, Microsoft Update Naming Conventions, PowerShell UI Integration
**Confidence:** HIGH

## Summary

Implementing Windows Update preview filtering for FFU Builder requires modifying the search query logic to exclude preview updates by default, adding a UI checkbox for opt-in, persisting the setting in configuration, and updating the config migration module. The codebase already has:

1. **Existing preview CU support** - `UpdatePreviewCU` parameter and search logic in BuildFFUVM.ps1 (lines 3500-3505)
2. **Microsoft Update Catalog integration** - Get-KBLink, Save-KB functions in FFU.Updates module
3. **Config migration infrastructure** - FFU.ConfigMigration module with versioning (v1.0)
4. **UI checkbox patterns** - Updates tab in XAML with existing checkboxes for update types

The implementation is straightforward because preview updates have a distinct naming convention in Microsoft Update Catalog: they include "Preview" in the title. The search queries in BuildFFUVM.ps1 can be modified to use `-preview` as a negative filter (exclude) by default, with an `IncludePreviewUpdates` config option to disable this exclusion.

**Primary recommendation:** Add `IncludePreviewUpdates` boolean to config schema (default: false), modify search queries in BuildFFUVM.ps1 to append `-preview` exclusion when false, add checkbox to Updates tab in XAML, handle checkbox state in FFUUI.Core.Handlers.psm1, and update FFU.ConfigMigration to handle the new property.

## Current State Analysis

### What Already Exists

| Component | Location | Reusability |
|-----------|----------|-------------|
| Update search logic | BuildFFUVM.ps1 lines 3478-3546 | HIGH - Add filter parameter |
| Get-KBLink function | FFU.Updates.psm1 lines 340-509 | HIGH - Already supports Filter parameter |
| Get-UpdateFileInfo function | FFU.Updates.psm1 lines 511-604 | HIGH - Already supports Filter parameter |
| Updates tab in UI | BuildFFUVM_UI.xaml lines 268-282 | HIGH - Add checkbox |
| Update checkbox handlers | FFUUI.Core.Handlers.psm1 lines 354-403 | HIGH - Pattern to follow |
| Config schema | ffubuilder-config.schema.json | HIGH - Add new property |
| Config migration module | FFU.ConfigMigration.psm1 | HIGH - Add migration for new property |
| Test-FFUConfiguration | FFU.Core.psm1 | HIGH - Will auto-validate new property |

### What Is Missing

| Gap | Impact | Required Work |
|-----|--------|---------------|
| IncludePreviewUpdates config property | Cannot persist user preference | Add to schema, default false |
| Preview exclusion in search queries | Preview updates currently included | Modify search logic |
| UI checkbox | No user control over behavior | Add checkbox to Updates tab |
| Handler for new checkbox | State not connected to config | Add event handlers |
| Config migration for new property | Existing configs won't have property | Add migration default |

### Microsoft Update Catalog Naming Conventions

Based on [official Microsoft documentation](https://learn.microsoft.com/en-us/windows/deployment/update/release-cycle), Windows Update titles follow predictable patterns:

| Update Type | Title Pattern | Example |
|-------------|---------------|---------|
| Security (GA) | "Cumulative Update for Windows {Release} Version {Version}" | "Cumulative Update for Windows 11 Version 24H2" |
| Preview (Optional) | "Cumulative Update Preview for Windows {Release} Version {Version}" | "Cumulative Update Preview for Windows 11 Version 24H2" |
| .NET GA | "Cumulative Update for .NET Framework..." | "Cumulative Update for .NET Framework 3.5 and 4.8.1" |
| .NET Preview | "Cumulative Update Preview for .NET Framework..." | "Cumulative Update Preview for .NET Framework..." |

**Key insight:** The word "Preview" appears in the title for optional non-security updates. This is consistent across Windows OS updates and .NET Framework updates.

### Current Search Query Examples

From BuildFFUVM.ps1:

```powershell
# Line 3480 - GA Cumulative Update search (when UpdateLatestCU is true)
$Name = """Cumulative update for Windows $WindowsRelease Version $WindowsVersion for $WindowsArch"""

# Line 3502 - Preview CU search (when UpdatePreviewCU is true)
$Name = """Cumulative update Preview for Windows $WindowsRelease Version $WindowsVersion for $WindowsArch"""

# Line 3530 - .NET Framework (includes "-preview" in some versions)
$Name = "Cumulative update for .NET framework windows $WindowsRelease $WindowsVersion $WindowsArch -preview"
```

**Note:** The `-preview` suffix in .NET searches is used as a negative filter (exclude preview from results).

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Get-KBLink | FFU.Updates v1.0.3 | Catalog search with filters | Already supports `-preview` exclusion |
| Get-UpdateFileInfo | FFU.Updates v1.0.3 | Get download URLs | Passes Filter to Get-KBLink |
| ConvertFrom-Json | PowerShell built-in | Parse config | Native, cross-version |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| FFU.ConfigMigration | v1.0.0 | Handle missing property | When loading old configs |
| Test-FFUConfiguration | FFU.Core v1.0.10+ | Validate new property | After schema update |
| System.Windows.Controls.CheckBox | WPF built-in | UI control | New checkbox element |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Config boolean | CLI switch only | Config allows persistence, CLI is one-time |
| Exclude by default | Include by default | Exclude safer for production builds |
| Single checkbox | Radio buttons (GA/Preview) | Checkbox simpler, existing UpdatePreviewCU handles explicit opt-in |

## Architecture Patterns

### Recommended Config Schema Addition

Add to `ffubuilder-config.schema.json` (after `UpdatePreviewCU` around line 410):

```json
"IncludePreviewUpdates": {
    "type": "boolean",
    "default": false,
    "description": "When set to true, includes preview/optional updates in Windows Update searches. When false (default), search queries exclude preview updates to ensure only GA (Generally Available) releases are downloaded. This affects Cumulative Updates, .NET Framework updates, and other updates that have preview versions."
}
```

### UI Control Addition

Add to `BuildFFUVM_UI.xaml` in Updates tab (line 279, after chkUpdatePreviewCU):

```xml
<CheckBox x:Name="chkIncludePreviewUpdates"
          Content="Include Preview Updates"
          Margin="5"
          VerticalAlignment="Center"
          ToolTip="When checked, allows preview/optional updates to be included in update searches. When unchecked (default), only GA (Generally Available) releases are downloaded."/>
```

### Event Handler Pattern

Add to `FFUUI.Core.Handlers.psm1` (follow existing checkbox patterns):

```powershell
# No special handler needed - checkbox state flows through config save/load
# The existing checkbox pattern in Build-ConfigFromUI handles boolean checkboxes automatically
```

### Search Query Modification Pattern

Modify BuildFFUVM.ps1 search logic to apply exclusion filter when `IncludePreviewUpdates` is false:

```powershell
# Before line 3478, add preview exclusion logic
$PreviewFilter = if ($IncludePreviewUpdates -eq $false) { "-preview" } else { "" }

# Modify CU search (line 3480)
if ($WindowsRelease -in 10, 11) {
    $Name = """Cumulative update for Windows $WindowsRelease Version $WindowsVersion for $WindowsArch"" $PreviewFilter"
}

# Similar modifications for other search queries
```

### Config Migration Addition

Add to `FFU.ConfigMigration.psm1` in the migration regions (after line 417):

```powershell
#region Migration: Add IncludePreviewUpdates default (v1.1)
if (-not $migrated.ContainsKey('IncludePreviewUpdates')) {
    $migrated['IncludePreviewUpdates'] = $false
    $changes += "Added default 'IncludePreviewUpdates=false' (preview updates excluded by default)"
}
#endregion
```

**Note:** Bump schema version from "1.0" to "1.1" for this migration.

### Recommended Flow

```
1. User checks "Include Preview Updates" checkbox (default: unchecked)
2. On Build FFU click, config value flows to BuildFFUVM.ps1 via parameters
3. BuildFFUVM.ps1 applies preview filter to search queries based on config value
4. Search queries use:
   - Default (unchecked): "Cumulative update for Windows..." -preview
   - Checked: "Cumulative update for Windows..." (no exclusion)
5. Update Catalog returns only GA updates by default
```

### Anti-Patterns to Avoid

- **Hardcoded preview filter:** Use config value, not hardcoded exclusion
- **Complex preview detection:** Simply append `-preview` exclusion, don't parse update titles
- **Breaking UpdatePreviewCU:** Keep existing explicit preview CU option separate
- **Silent behavior change:** Log when preview filter is applied

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Preview detection | Parse update titles | `-preview` search exclusion | Catalog supports exclusion natively |
| Config persistence | Manual file writes | Existing config save/load | Already handles all config properties |
| UI checkbox binding | Custom binding code | Standard checkbox pattern | XAML/handler pattern established |
| Default value | Hardcode in multiple places | Schema default + migration | Single source of truth |

**Key insight:** Microsoft Update Catalog search already supports negative filters using `-term` syntax. The existing .NET search (line 3530) demonstrates this pattern with `-preview`.

## Common Pitfalls

### Pitfall 1: Breaking UpdatePreviewCU Behavior
**What goes wrong:** IncludePreviewUpdates conflicts with UpdatePreviewCU checkbox
**Why it happens:** Both settings affect preview updates, unclear precedence
**How to avoid:** IncludePreviewUpdates is a *filter* setting; UpdatePreviewCU is an *explicit opt-in* for preview CU. When UpdatePreviewCU is true, the explicit preview search is used regardless of IncludePreviewUpdates.
**Warning signs:** Preview CU checkbox stops working

### Pitfall 2: Filter Syntax Errors
**What goes wrong:** Search queries fail or return no results
**Why it happens:** Incorrect placement of `-preview` filter in query string
**How to avoid:** Test filter syntax on catalog.update.microsoft.com manually first; place filter after quoted search term
**Warning signs:** "No download links found" errors for known-good updates

### Pitfall 3: Config Schema Version Not Bumped
**What goes wrong:** Migration doesn't apply to existing configs
**Why it happens:** Forgot to increment configSchemaVersion from "1.0" to "1.1"
**How to avoid:** Always bump schema version when adding new properties that need migration
**Warning signs:** Old configs don't get IncludePreviewUpdates default

### Pitfall 4: Preview Filter Applied to Non-Applicable Updates
**What goes wrong:** Some update types don't have preview versions, filter may exclude valid results
**Why it happens:** Blanket application of `-preview` to all searches
**How to avoid:** Only apply to update types that have preview variants (CU, .NET); skip for Defender, MSRT, Edge
**Warning signs:** "No updates found" for updates that don't have preview versions

### Pitfall 5: Inconsistent Default Value
**What goes wrong:** Default is true in schema but false in migration
**Why it happens:** Defaults defined in multiple places
**How to avoid:** Define default once in schema, migration reads from schema or matches explicitly
**Warning signs:** Behavior differs between new configs and migrated configs

## Code Examples

### Example 1: Search Query with Preview Filter

```powershell
# Source: BuildFFUVM.ps1 modification pattern
# Apply preview exclusion filter when IncludePreviewUpdates is false
$PreviewFilter = if ($IncludePreviewUpdates -eq $false) { " -preview" } else { "" }

# CU search with filter
if ($UpdateLatestCU -and -not $UpdatePreviewCU) {
    WriteLog "`$UpdateLatestCU is set to true, checking for latest CU"
    if ($WindowsRelease -in 10, 11) {
        $Name = """Cumulative update for Windows $WindowsRelease Version $WindowsVersion for $WindowsArch""$PreviewFilter"
    }
    # ... other Windows versions
    WriteLog "Searching for $Name from Microsoft Update Catalog"
    WriteLog "Preview updates filter: $($IncludePreviewUpdates -eq $false ? 'Excluded' : 'Included')"
}
```

### Example 2: Update Types That Need Preview Filter

```powershell
# Source: Decision matrix for preview filter application
$UpdateTypesWithPreview = @(
    'CumulativeUpdate',      # OS cumulative updates
    'DotNetFramework'        # .NET Framework updates
)

$UpdateTypesWithoutPreview = @(
    'Defender',              # Windows Defender - no preview variant
    'MSRT',                  # Malicious Software Removal Tool - no preview
    'Edge',                  # Microsoft Edge - no preview in catalog
    'OneDrive',              # OneDrive - no preview
    'Microcode'              # Intel microcode - no preview
)
```

### Example 3: Config Property in Build-ConfigFromUI

```powershell
# Source: FFUUI.Core.Config.psm1 pattern (Build-ConfigFromUI function)
# Add to existing checkbox mappings around line 300-400
IncludePreviewUpdates = $localState.Controls.chkIncludePreviewUpdates.IsChecked
```

### Example 4: Config Property in Update-UIFromConfig

```powershell
# Source: FFUUI.Core.Config.psm1 pattern (Update-UIFromConfig function)
# Add to existing checkbox property mappings
if ($config.ContainsKey('IncludePreviewUpdates')) {
    Set-CheckBoxState -CheckBox $localState.Controls.chkIncludePreviewUpdates -Value $config.IncludePreviewUpdates
}
```

### Example 5: Parameter Declaration in BuildFFUVM.ps1

```powershell
# Source: BuildFFUVM.ps1 param block (add after UpdatePreviewCU)
[Parameter()]
[bool]$IncludePreviewUpdates = $false  # Default: exclude preview updates
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| No preview filtering | All updates returned | Pre-v1.8.1 | May include optional preview updates |
| Manual exclusion | Config-driven exclusion | v1.8.1 | User controls preview inclusion |

**Deprecated/outdated:**
- Assuming all catalog results are GA: Preview updates can appear in search results
- Hardcoded preview exclusion: Use config-driven approach for flexibility

## Relationship with Existing UpdatePreviewCU

The existing `UpdatePreviewCU` parameter serves a **different purpose**:

| Setting | Purpose | When to Use |
|---------|---------|-------------|
| `UpdatePreviewCU` | **Explicitly** download Preview Cumulative Update | When user wants the latest preview CU specifically |
| `IncludePreviewUpdates` | **Allow** preview updates in search results | When user wants all update types to potentially include previews |

**Interaction Matrix:**

| UpdatePreviewCU | IncludePreviewUpdates | Behavior |
|-----------------|----------------------|----------|
| false | false (default) | Only GA updates downloaded |
| false | true | GA updates + any previews that match search |
| true | false | Explicit preview CU + GA for other updates |
| true | true | Explicit preview CU + all previews included |

## Open Questions

### 1. Should .NET Preview Exclusion Be Changed?
- **What we know:** Line 3530 already uses `-preview` for .NET searches
- **What's unclear:** Is this intentional or should it follow IncludePreviewUpdates?
- **Recommendation:** Make it consistent - .NET should follow IncludePreviewUpdates setting

### 2. UI Placement: Updates Tab or Build Tab?
- **What we know:** Other update settings are in Updates tab
- **What's unclear:** This is more of a "behavior" setting than update selection
- **Recommendation:** Keep in Updates tab for consistency with update-related settings

### 3. Warning When Preview Exclusion Active?
- **What we know:** Silent behavior change could confuse users
- **What's unclear:** Should we log a warning every time preview filter is applied?
- **Recommendation:** Log once at start of update search phase: "Preview updates excluded (default)"

## Sources

### Primary (HIGH confidence)
- BuildFFUVM.ps1 lines 3478-3546 - Current update search logic
- FFU.Updates.psm1 - Get-KBLink, Save-KB functions with Filter support
- BuildFFUVM_UI.xaml lines 268-282 - Updates tab structure
- ffubuilder-config.schema.json - Config schema for new property
- FFU.ConfigMigration.psm1 - Migration pattern for new properties
- [Microsoft Learn: Update release cycle](https://learn.microsoft.com/en-us/windows/deployment/update/release-cycle) - Official update naming documentation

### Secondary (MEDIUM confidence)
- [Microsoft Learn: Checkpoint cumulative updates](https://learn.microsoft.com/en-us/windows/deployment/update/catalog-checkpoint-cumulative-updates) - Catalog search behavior
- [Windows monthly updates explained](https://techcommunity.microsoft.com/blog/windows-itpro-blog/windows-monthly-updates-explained/3773544) - Preview vs GA update definitions

### Tertiary (LOW confidence)
- Manual testing of catalog.update.microsoft.com search syntax

## Metadata

**Confidence breakdown:**
- Search query modification: HIGH - Pattern exists in .NET search (line 3530)
- Config schema addition: HIGH - Clear pattern from existing properties
- UI checkbox addition: HIGH - Multiple existing examples in Updates tab
- Config migration: HIGH - FFU.ConfigMigration module is well-established
- Preview filter effectiveness: MEDIUM - Based on catalog search behavior observation

**Research date:** 2026-01-20
**Valid until:** 60 days (Microsoft may change catalog search behavior)
