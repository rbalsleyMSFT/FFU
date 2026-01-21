# Phase 14: VMware UI Settings - Research

**Researched:** 2026-01-20
**Domain:** WPF UI Controls, PowerShell Configuration Management, Schema Migration
**Confidence:** HIGH

## Summary

This phase adds VMware network configuration dropdowns (NetworkType, NicType) to the FFU Builder UI, following the established Phase 11 (IncludePreviewUpdates) implementation pattern. The codebase already has all the infrastructure needed - Update-HypervisorStatus handles VMware control visibility, ConfigMigration handles schema upgrades, and the config save/load pipeline is well-established.

The implementation is straightforward because:
1. The Update-HypervisorStatus function already has VMware-specific visibility logic
2. The ConfigMigration module has a clear pattern for adding new properties with defaults
3. The UI already has hypervisor-type conditional controls (VM Switch for Hyper-V)

**Primary recommendation:** Follow the Phase 11 IncludePreviewUpdates pattern exactly - add UI controls, wire to config save/load, add migration defaults, update Get-GeneralDefaults.

## Standard Stack

No new libraries required. This phase uses existing infrastructure:

### Core
| Component | Location | Purpose | Why Standard |
|-----------|----------|---------|--------------|
| WPF XAML | BuildFFUVM_UI.xaml | UI control definitions | Existing UI framework |
| FFUUI.Core.Config | FFUUI.Core.Config.psm1 | Config save/load wiring | Established pattern |
| FFU.ConfigMigration | FFU.ConfigMigration.psm1 | Schema migration | Handles v1.x → v1.y upgrades |
| FFUUI.Core.Shared | FFUUI.Core.Shared.psm1 | Update-HypervisorStatus | Conditional control visibility |

### Supporting
| Component | Location | Purpose | When to Use |
|-----------|----------|---------|-------------|
| FFUUI.Core.psm1 | Get-GeneralDefaults | Fresh launch defaults | UI initialization |
| ffubuilder-config.schema.json | config/ | Schema definition | Documentation only |

## Architecture Patterns

### Pattern 1: Phase 11 IncludePreviewUpdates Reference

**What:** The exact pattern to follow for adding new UI settings with config persistence
**When to use:** Any new UI setting that needs save/load and migration support
**Source:** Phase 11 implementation (v1.8.1)

**Implementation steps (from Phase 11):**
1. Add UI control to XAML
2. Register control in FFUUI.Core.Initialize.psm1
3. Add config property to save/load in FFUUI.Core.Config.psm1
4. Add migration default in FFU.ConfigMigration.psm1
5. Add default to Get-GeneralDefaults in FFUUI.Core.psm1
6. Update schema version to 1.2

### Pattern 2: Conditional Control Enable/Disable

**What:** Enable/disable controls based on hypervisor selection
**When to use:** VMware-specific controls that should be disabled when Hyper-V is selected
**Source:** FFUUI.Core.Shared.psm1 Update-HypervisorStatus (lines 968-1156)

**Existing code pattern:**
```powershell
# From Update-HypervisorStatus in FFUUI.Core.Shared.psm1
$showVMwareControls = ($hypervisorType -eq 'VMware')
$vmwareVisibility = if ($showVMwareControls) { 'Visible' } else { 'Collapsed' }

# Apply to VMware-specific controls
if ($null -ne $State.Controls.txtVMwareWorkstationPath) {
    $State.Controls.txtVMwareWorkstationPath.IsEnabled = $showVMwareControls
}
```

**For new VMware dropdowns, add:**
```powershell
# Enable/disable VMware network dropdowns
if ($null -ne $State.Controls.cmbVMwareNetworkType) {
    $State.Controls.cmbVMwareNetworkType.IsEnabled = $showVMwareControls
}
if ($null -ne $State.Controls.cmbVMwareNicType) {
    $State.Controls.cmbVMwareNicType.IsEnabled = $showVMwareControls
}
```

### Pattern 3: Config Migration with Defaults

**What:** Add new properties to existing configs during schema migration
**When to use:** When adding new config properties (schema version bump)
**Source:** FFU.ConfigMigration.psm1 (lines 81-86)

**Existing pattern:**
```powershell
#region Migration: Add IncludePreviewUpdates default (v1.1)
if (-not $migrated.ContainsKey('IncludePreviewUpdates')) {
    $migrated['IncludePreviewUpdates'] = $false
    $changes += "Added default 'IncludePreviewUpdates=false' (preview updates excluded by default)"
}
#endregion
```

**For VMwareSettings:**
```powershell
#region Migration: Add VMwareSettings defaults (v1.2)
if (-not $migrated.ContainsKey('VMwareSettings')) {
    $migrated['VMwareSettings'] = @{
        NetworkType = 'nat'
        NicType = 'e1000e'
    }
    $changes += "Added default 'VMwareSettings' (NetworkType=nat, NicType=e1000e)"
}
#endregion
```

### Pattern 4: ComboBox with ItemsSource Binding

**What:** Dropdown with predefined options
**When to use:** Selection from fixed list of values
**Source:** BuildFFUVM_UI.xaml existing ComboBox patterns

**XAML pattern:**
```xml
<ComboBox x:Name="cmbVMwareNetworkType"
          Width="200"
          Margin="5,0,0,0"
          IsEnabled="False">
    <ComboBoxItem Content="NAT" Tag="nat" IsSelected="True"/>
    <ComboBoxItem Content="Bridged" Tag="bridged"/>
    <ComboBoxItem Content="Host-Only" Tag="hostonly"/>
</ComboBox>
```

### Anti-Patterns to Avoid

- **Don't create separate VMware settings panel:** Integrate into existing VM Settings section
- **Don't hardcode values in multiple places:** Use constants or single source of truth
- **Don't skip migration:** Existing configs MUST get defaults or they will have null values

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Config migration | Manual JSON manipulation | FFU.ConfigMigration module | Handles versioning, validation, backup |
| Control visibility toggle | Custom visibility logic | Update-HypervisorStatus | Already handles VMware visibility |
| Config save/load | Direct file I/O | FFUUI.Core.Config functions | Handles serialization, validation |

**Key insight:** All infrastructure already exists. This is pure wiring, not new functionality.

## Common Pitfalls

### Pitfall 1: Forgetting to Update Schema Version
**What goes wrong:** Migration doesn't trigger because version check passes
**Why it happens:** Schema version not bumped from 1.1 to 1.2
**How to avoid:** Update `$script:CurrentConfigSchemaVersion = "1.2"` in FFU.ConfigMigration.psm1
**Warning signs:** Existing configs don't get VMwareSettings after load

### Pitfall 2: Control Name Mismatch
**What goes wrong:** Controls not found, null reference errors
**Why it happens:** XAML control name doesn't match code reference
**How to avoid:** Use consistent naming: `cmbVMwareNetworkType`, `cmbVMwareNicType`
**Warning signs:** "Cannot index into a null array" errors

### Pitfall 3: Missing Get-GeneralDefaults Entry
**What goes wrong:** Fresh UI launch has no VMware defaults
**Why it happens:** Get-GeneralDefaults not updated with new properties
**How to avoid:** Add VMwareSettings to Get-GeneralDefaults hashtable
**Warning signs:** VMware dropdowns empty on fresh launch

### Pitfall 4: Not Wiring Save/Load
**What goes wrong:** Settings reset after save/load cycle
**Why it happens:** Config save/load functions don't handle new properties
**How to avoid:** Add VMwareSettings to both Save-GeneralConfiguration and config load
**Warning signs:** Settings don't persist between sessions

### Pitfall 5: ComboBox SelectedItem vs Tag Value
**What goes wrong:** Wrong value saved to config (display text instead of tag)
**Why it happens:** Using SelectedItem.Content instead of SelectedItem.Tag
**How to avoid:** Use Tag property for config values: `$State.Controls.cmbVMwareNetworkType.SelectedItem.Tag`
**Warning signs:** Config contains "NAT" instead of "nat"

## Code Examples

### 1. XAML ComboBox Definition
```xml
<!-- Source: BuildFFUVM_UI.xaml pattern -->
<StackPanel Orientation="Horizontal" Margin="0,5,0,0">
    <TextBlock Text="VMware Network Type:" Width="150" VerticalAlignment="Center"/>
    <ComboBox x:Name="cmbVMwareNetworkType"
              Width="200"
              Margin="5,0,0,0"
              IsEnabled="False">
        <ComboBoxItem Content="NAT" Tag="nat" IsSelected="True"/>
        <ComboBoxItem Content="Bridged" Tag="bridged"/>
        <ComboBoxItem Content="Host-Only" Tag="hostonly"/>
    </ComboBox>
</StackPanel>

<StackPanel Orientation="Horizontal" Margin="0,5,0,0">
    <TextBlock Text="VMware NIC Type:" Width="150" VerticalAlignment="Center"/>
    <ComboBox x:Name="cmbVMwareNicType"
              Width="200"
              Margin="5,0,0,0"
              IsEnabled="False">
        <ComboBoxItem Content="E1000E" Tag="e1000e" IsSelected="True"/>
        <ComboBoxItem Content="VMXNET3" Tag="vmxnet3"/>
        <ComboBoxItem Content="E1000" Tag="e1000"/>
    </ComboBox>
</StackPanel>
```

### 2. Update-HypervisorStatus Addition
```powershell
# Source: FFUUI.Core.Shared.psm1 Update-HypervisorStatus pattern
# Add after existing VMware control handling (~line 1100)

# Enable/disable VMware network dropdowns based on hypervisor selection
if ($null -ne $State.Controls.cmbVMwareNetworkType) {
    $State.Controls.cmbVMwareNetworkType.IsEnabled = $showVMwareControls
}
if ($null -ne $State.Controls.cmbVMwareNicType) {
    $State.Controls.cmbVMwareNicType.IsEnabled = $showVMwareControls
}
```

### 3. ConfigMigration Default Addition
```powershell
# Source: FFU.ConfigMigration.psm1 pattern
# Add to Invoke-FFUConfigMigration after IncludePreviewUpdates section

#region Migration: Add VMwareSettings defaults (v1.2)
if (-not $migrated.ContainsKey('VMwareSettings')) {
    $migrated['VMwareSettings'] = @{
        NetworkType = 'nat'
        NicType = 'e1000e'
    }
    $changes += "Added default 'VMwareSettings' (NetworkType=nat, NicType=e1000e)"
}
#endregion
```

### 4. Get-GeneralDefaults Addition
```powershell
# Source: FFUUI.Core.psm1 Get-GeneralDefaults pattern
# Add to defaults hashtable

VMwareSettings = @{
    NetworkType = 'nat'
    NicType = 'e1000e'
}
```

### 5. Config Save Addition
```powershell
# Source: FFUUI.Core.Config.psm1 Save-GeneralConfiguration pattern
# Add to config hashtable before ConvertTo-Json

VMwareSettings = @{
    NetworkType = $State.Controls.cmbVMwareNetworkType.SelectedItem.Tag
    NicType = $State.Controls.cmbVMwareNicType.SelectedItem.Tag
}
```

### 6. Config Load Addition
```powershell
# Source: FFUUI.Core.Config.psm1 config load pattern
# Add after loading config JSON

if ($config.VMwareSettings) {
    # Find and select matching ComboBoxItem by Tag
    $networkItem = $State.Controls.cmbVMwareNetworkType.Items |
        Where-Object { $_.Tag -eq $config.VMwareSettings.NetworkType }
    if ($networkItem) {
        $State.Controls.cmbVMwareNetworkType.SelectedItem = $networkItem
    }

    $nicItem = $State.Controls.cmbVMwareNicType.Items |
        Where-Object { $_.Tag -eq $config.VMwareSettings.NicType }
    if ($nicItem) {
        $State.Controls.cmbVMwareNicType.SelectedItem = $nicItem
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Hardcoded VMware settings | UI-configurable | v1.8.2 (this phase) | User flexibility |
| No schema migration | Versioned migration | v1.8.1 | Config forward-compat |

**Current state:**
- Schema version: 1.1 (IncludePreviewUpdates added)
- VMware network settings: Hardcoded in FFU.Hypervisor module
- Migration module: Ready for v1.2 upgrade

## Open Questions

None - all implementation details are clear from existing patterns.

## Sources

### Primary (HIGH confidence)
- FFU.ConfigMigration.psm1 - Complete migration module reviewed
- FFUUI.Core.Shared.psm1 - Update-HypervisorStatus function (lines 968-1156)
- FFUUI.Core.Config.psm1 - Config save/load wiring
- BuildFFUVM_UI.xaml - UI control patterns
- Phase 11 PLAN.md files - Reference implementation pattern

### Secondary (MEDIUM confidence)
- ffubuilder-config.schema.json - Schema structure (documentation only)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All existing infrastructure
- Architecture: HIGH - Clear patterns from Phase 11
- Pitfalls: HIGH - Based on actual codebase analysis

**Research date:** 2026-01-20
**Valid until:** 2026-02-20 (stable infrastructure, unlikely to change)

---

## Implementation Checklist

Files requiring modification:

| File | Change | Requirement |
|------|--------|-------------|
| BuildFFUVM_UI.xaml | Add cmbVMwareNetworkType, cmbVMwareNicType | VMUI-01, VMUI-02 |
| FFUUI.Core.Initialize.psm1 | Register new controls | VMUI-01, VMUI-02 |
| FFUUI.Core.Shared.psm1 | Update-HypervisorStatus enable/disable | VMUI-04 |
| FFUUI.Core.Config.psm1 | Save/load VMwareSettings | VMUI-03 |
| FFUUI.Core.psm1 | Get-GeneralDefaults VMwareSettings | VMUI-06 |
| FFU.ConfigMigration.psm1 | Add VMwareSettings defaults, bump to v1.2 | VMUI-05 |
| ffubuilder-config.schema.json | Add VMwareSettings schema (optional docs) | VMUI-03 |

**Default values:**
- NetworkType: `nat` (NAT networking)
- NicType: `e1000e` (Intel E1000E adapter)
