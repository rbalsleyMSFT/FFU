# Phase 14 Plan 01: VMware Settings UI Summary

## One-liner
VMware Network Type (NAT/Bridged/Host-Only) and NIC Type (E1000E/VMXNET3/E1000) dropdowns with config save/load support

## Execution Details

| Metric | Value |
|--------|-------|
| Duration | 6m 27s |
| Tasks Completed | 4/4 |
| Commits | 4 |
| Files Modified | 8 |

## Commits

| Hash | Type | Description |
|------|------|-------------|
| adb1b6e | feat | Add VMware NetworkType and NicType dropdown controls |
| 78d640e | feat | Wire VMware NetworkType/NicType UI controls |
| 79b8c34 | feat | Add VMware NetworkType/NicType to config files |
| 14c114f | chore | Bump FFUUI.Core to v0.0.12 and FFU Builder to v1.8.3 |

## Changes Made

### Task 1: XAML Dropdown Controls
- Added `cmbVMwareNetworkType` ComboBox with NAT/Bridged/Host-Only options
- Added `cmbVMwareNicType` ComboBox with E1000E/VMXNET3/E1000 options
- Both start with `Visibility="Collapsed"` and `IsEnabled="False"`
- Added StackPanel labels for both controls
- Increased grid RowDefinitions from 14 to 16 rows
- Updated Grid.Row indices for rows 6-15 (shifted by 2)

### Task 2: UI Control Wiring
- **FFUUI.Core.Initialize.psm1**: Registered controls in State.Controls
- **FFUUI.Core.Shared.psm1**: Added visibility/enable logic in Update-HypervisorStatus
  - Controls visible only when VMware selected
  - Controls enabled when showVMwareControls is true
- **FFUUI.Core.Config.psm1**:
  - Get-UIConfig: Extract Tag value from selected ComboBoxItem
  - Update-UIFromConfig: Select ComboBoxItem by matching Tag value

### Task 3: Test Config Updates
- **test-minimal.json**: Added HypervisorType, VMwareNetworkType, VMwareNicType
- **test-standard.json**: Added HypervisorType, VMwareNetworkType, VMwareNicType
- **ffubuilder-config.schema.json**: Added flat property definitions with enums

### Task 4: Version Updates
- FFUUI.Core: v0.0.11 -> v0.0.12
- FFU Builder: v1.8.2 -> v1.8.3 (PATCH for module update)
- Updated buildDate to 2026-01-21

## Files Modified

| File | Changes |
|------|---------|
| BuildFFUVM_UI.xaml | Added 2 ComboBox controls, 2 StackPanel labels, 2 grid rows |
| FFUUI.Core.Initialize.psm1 | Registered 4 new controls in State.Controls |
| FFUUI.Core.Shared.psm1 | Added visibility/enable logic (~22 lines) |
| FFUUI.Core.Config.psm1 | Added save (~16 lines) and load (~38 lines) logic |
| test-minimal.json | Added 3 new properties |
| test-standard.json | Added 3 new properties |
| ffubuilder-config.schema.json | Added 2 new property definitions |
| FFUUI.Core.psd1 | Version bump, release notes |
| version.json | Version bump, description update |

## Verification

### Tests Executed
- FFU.Media.Tests.ps1: 28/28 passed
- Module import test: FFUUI.Core v0.0.12 imports successfully
- JSON validation: All config files valid

### Success Criteria Met
- [x] Dropdowns appear in VM Settings tab when VMware selected
- [x] Dropdowns are disabled when VMware not selected
- [x] Config save preserves selected values
- [x] Config load restores selected values
- [x] Test configs updated with new properties
- [x] JSON schema includes new property definitions
- [x] Version manifest updated

## Deviations from Plan

None - plan executed exactly as written.

## Next Steps

The VMware network settings are now configurable via UI but not yet passed to the FFU.Hypervisor module during VM creation. A future task should:
1. Update BuildFFUVM.ps1 to read VMwareNetworkType and VMwareNicType from config
2. Pass these values to the VMwareProvider via VMConfiguration
3. The FFU.Hypervisor module already supports these settings in its VMConfiguration class
