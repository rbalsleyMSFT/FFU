---
phase: 11
plan: 02
subsystem: ui-build
tags: [ui-checkbox, config-binding, preview-filter, windows-update]

dependency-graph:
  requires: [11-01]
  provides: [ui-preview-checkbox, config-persistence, build-script-filtering]
  affects: [11-03, 11-04]

tech-stack:
  added: []
  patterns: [xaml-checkbox-binding, config-save-load, search-query-filter]

key-files:
  created: []
  modified:
    - FFUDevelopment/BuildFFUVM_UI.xaml
    - FFUDevelopment/FFUUI.Core/FFUUI.Core.Initialize.psm1
    - FFUDevelopment/FFUUI.Core/FFUUI.Core.Config.psm1
    - FFUDevelopment/BuildFFUVM.ps1

decisions:
  - id: D-11-02-01
    decision: Apply -preview exclusion filter to search query string
    rationale: Microsoft Update Catalog search supports negative keywords for filtering
  - id: D-11-02-02
    decision: UpdatePreviewCU explicit request is NOT filtered
    rationale: When user explicitly wants preview CU, do not exclude preview results

metrics:
  duration: ~4 minutes
  completed: 2026-01-20
---

# Phase 11 Plan 02: UI Checkbox and Build Script Filtering Logic Summary

**One-liner:** Implemented Include Preview Updates checkbox in Updates tab with config persistence and build script filtering that appends "-preview" to exclude preview updates by default.

## What Was Built

### Task 1: UI Checkbox in Updates Tab

Added `chkIncludePreviewUpdates` checkbox to BuildFFUVM_UI.xaml:

```xml
<CheckBox x:Name="chkIncludePreviewUpdates"
          Content="Include Preview Updates in Search"
          Margin="5"
          VerticalAlignment="Center"
          ToolTip="When checked, allows preview/optional updates to appear in update searches. When unchecked (default), only GA (Generally Available) releases are found. This affects Cumulative Updates and .NET Framework updates."/>
```

Updated FFUUI.Core.Initialize.psm1:
- Control registration: `$State.Controls.chkIncludePreviewUpdates = $window.FindName('chkIncludePreviewUpdates')`
- Default initialization: `$State.Controls.chkIncludePreviewUpdates.IsChecked = $State.Defaults.generalDefaults.IncludePreviewUpdates`

### Task 2: Config Save/Load Wiring

Updated FFUUI.Core.Config.psm1:

1. **Build-ConfigFromUI:** Added checkbox state to config hash
   ```powershell
   IncludePreviewUpdates = $State.Controls.chkIncludePreviewUpdates.IsChecked
   ```

2. **Update-UIFromConfig:** Added Set-UIValue binding
   ```powershell
   Set-UIValue -ControlName 'chkIncludePreviewUpdates' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'IncludePreviewUpdates' -State $State
   ```

### Task 3: Build Script Filtering Logic

Updated BuildFFUVM.ps1:

1. **Parameter added:**
   ```powershell
   [bool]$IncludePreviewUpdates,
   ```

2. **Help documentation added:**
   ```
   .PARAMETER IncludePreviewUpdates
   When set to $true, allows preview/optional updates in Windows Update searches. When $false (default), search queries exclude preview updates to ensure only GA (Generally Available) releases are downloaded. Affects Cumulative Updates and .NET Framework updates.
   ```

3. **PreviewFilter variable:**
   ```powershell
   $PreviewFilter = if ($IncludePreviewUpdates -eq $false) { " -preview" } else { "" }
   ```
   - When `$false`: Appends ` -preview` to exclude preview results
   - When `$true`: Empty string, no filtering

4. **Applied to CU searches:**
   - Windows 10/11: `"Cumulative update for Windows $WindowsRelease..."$PreviewFilter`
   - Server 2025/2022: `"Cumulative Update for Microsoft server operating system..."$PreviewFilter`
   - Server 2016/2019: `"Cumulative update for Windows Server..."$PreviewFilter`
   - LTSC versions: All LTSC-specific CU searches

5. **Applied to .NET searches:**
   - Windows 10/11/LTSC 2024: `"Cumulative update for .NET framework..."$PreviewFilter`
   - Server 2025: `"Cumulative Update for .NET Framework..."$PreviewFilter`

6. **NOT applied to (intentional):**
   - UpdatePreviewCU explicit request (user wants preview CU)
   - Defender, MSRT, Edge, OneDrive, Microcode (no preview variants)

## Commits

| Commit | Type | Description |
|--------|------|-------------|
| 20c7754 | feat | Add Include Preview Updates checkbox to Updates tab |
| be1f628 | feat | Wire IncludePreviewUpdates to config save/load |
| b7ba336 | feat | Add IncludePreviewUpdates filtering logic to build script |

## Verification Results

All verification checks passed:

1. **XAML parses successfully:** Checkbox element found with correct Name and Content
2. **Control registration:** Found in FFUUI.Core.Initialize.psm1
3. **Default initialization:** Found using generalDefaults.IncludePreviewUpdates
4. **Config save mapping:** Build-ConfigFromUI includes IncludePreviewUpdates
5. **Config load mapping:** Update-UIFromConfig includes Set-UIValue for checkbox
6. **Parameter exists:** IncludePreviewUpdates in BuildFFUVM.ps1 param block
7. **PreviewFilter logic:** Correctly set based on IncludePreviewUpdates value
8. **CU searches filtered:** PreviewFilter appended to search queries
9. **.NET searches filtered:** Replaced hardcoded -preview with PreviewFilter
10. **UpdatePreviewCU preserved:** Explicit preview request not affected

## Deviations from Plan

None - plan executed exactly as written.

## Dependencies for Next Plans

This plan provides:

- **11-03:** Test coverage can verify filter logic
- **11-04:** Integration testing can verify end-to-end checkbox -> config -> build flow

## Success Criteria Status

- [x] chkIncludePreviewUpdates checkbox visible in Updates tab
- [x] Checkbox tooltip explains GA vs preview behavior
- [x] Checkbox state included in Build-ConfigFromUI output
- [x] Update-UIFromConfig loads IncludePreviewUpdates from saved config
- [x] BuildFFUVM.ps1 has IncludePreviewUpdates parameter
- [x] Build script applies -preview filter when IncludePreviewUpdates=$false
- [x] Build script skips filter when IncludePreviewUpdates=$true
- [x] UpdatePreviewCU explicit search is NOT affected by filter
- [x] .NET searches use config setting instead of hardcoded -preview
