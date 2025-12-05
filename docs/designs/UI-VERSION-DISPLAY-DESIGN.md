# UI Version Display Design Specification

**Status: IMPLEMENTED** (December 2, 2025)

## Overview
Add version information display to BuildFFUVM_UI.ps1 to help users identify which version of FFU Builder they are running.

## Current State Analysis

### Window Structure
- **Title**: "FFU Builder UI" (static text in XAML line 3)
- **Layout**: Grid with TabControl (left-side tabs) + bottom action buttons
- **Existing Tabs**: Home, Hyper-V Settings, Windows Settings, Updates, Applications, M365 Apps/Office, Drivers, Build, Monitor (9 tabs)

### Existing Version Data
The UI already maintains `$script:uiState.Data.versionData` (line 47) for internal purposes.

### Module Versions
Current module versions in the codebase:
- FFU.Core: 1.0.0
- FFU.ADK: 1.0.0
- FFU.Apps: 1.0.0
- FFU.Drivers: 1.0.0
- FFU.Imaging: 1.0.0
- FFU.Media: 1.0.0
- FFU.Updates: 1.0.0
- FFU.VM: 1.0.0

## Design Options

### Option 1: Title Bar Version Display (RECOMMENDED)

**Implementation**: Modify window title to include version string.

**Example**: `"FFU Builder UI v1.0.0"` or `"FFU Builder UI - Version 1.0.0"`

**XAML Change** (line 3):
```xml
<!-- Before -->
<Window ... Title="FFU Builder UI">

<!-- After - Use binding for dynamic version -->
<Window ... Title="FFU Builder UI" x:Name="MainWindow">
```

**PowerShell Change** (during window initialization):
```powershell
# Define version constant
$script:FFUBuilderVersion = "1.0.0"

# After XAML load, update window title
$window.Title = "FFU Builder UI v$script:FFUBuilderVersion"
```

**Pros**:
- Always visible regardless of which tab is active
- Minimal UI changes (no new tabs or controls)
- Standard practice for desktop applications
- No additional screen space required
- Simple implementation (~5 lines of code)

**Cons**:
- Limited space for additional information
- Cannot display detailed version info (build date, etc.)

---

### Option 2: About Tab

**Implementation**: Add new "About" tab with version details, credits, and links.

**XAML Addition** (after Monitor tab, line 834):
```xml
<!-- TAB: About -->
<TabItem Header="About" Padding="20">
    <ScrollViewer VerticalScrollBarVisibility="Auto">
        <StackPanel Margin="20">
            <TextBlock Text="FFU Builder" FontSize="24" FontWeight="Bold" Margin="0,0,0,10"/>
            <TextBlock x:Name="txtVersion" FontSize="16" Margin="0,0,0,20"/>
            <TextBlock Text="Build Date:" FontWeight="Bold"/>
            <TextBlock x:Name="txtBuildDate" Margin="0,0,0,10"/>
            <TextBlock Text="Description" FontWeight="Bold" Margin="0,10,0,5"/>
            <TextBlock TextWrapping="Wrap" Margin="0,0,0,20">
                Windows deployment acceleration tool that creates pre-configured
                Windows 11 images deployable in under 2 minutes.
            </TextBlock>
            <TextBlock Text="Links" FontWeight="Bold" Margin="0,10,0,5"/>
            <TextBlock>
                <Hyperlink x:Name="lnkGitHub" NavigateUri="https://github.com/rbalsleyMSFT/FFU">
                    GitHub Repository
                </Hyperlink>
            </TextBlock>
            <TextBlock Text="Credits" FontWeight="Bold" Margin="0,20,0,5"/>
            <TextBlock Text="Original Author: rbalsleyMSFT"/>
            <TextBlock Text="License: MIT"/>
        </StackPanel>
    </ScrollViewer>
</TabItem>
```

**PowerShell Changes**:
```powershell
# Version info
$script:FFUBuilderVersion = "1.0.0"
$script:FFUBuilderBuildDate = "December 2025"

# After XAML load
$txtVersion = $window.FindName("txtVersion")
$txtVersion.Text = "Version $script:FFUBuilderVersion"

$txtBuildDate = $window.FindName("txtBuildDate")
$txtBuildDate.Text = $script:FFUBuilderBuildDate

# Hyperlink click handler
$lnkGitHub = $window.FindName("lnkGitHub")
$lnkGitHub.Add_RequestNavigate({
    Start-Process $_.Uri.AbsoluteUri
    $_.Handled = $true
})
```

**Pros**:
- Rich display with multiple pieces of information
- Room for credits, links, changelog
- Professional appearance
- Dedicated space for future additions

**Cons**:
- Requires navigating to tab to see version
- More complex implementation (~50 lines)
- Adds 10th tab to already full tab bar

---

## Recommendation: Hybrid Approach

Implement **both** options for optimal user experience:

1. **Title bar** shows version for quick reference (always visible)
2. **About tab** provides detailed information when needed

This provides:
- Immediate version visibility in title bar
- Detailed information accessible in About tab
- Professional application feel

## Implementation Plan

### Phase 1: Title Bar (Quick Win)
1. Add `$script:FFUBuilderVersion` constant to BuildFFUVM_UI.ps1
2. Update window title after XAML load
3. Test version display

### Phase 2: About Tab (Enhancement)
1. Add About TabItem to BuildFFUVM_UI.xaml
2. Add version info controls to About tab
3. Add PowerShell initialization for About tab controls
4. Add hyperlink click handler
5. Test About tab functionality

## Version String Format

**Recommended Format**: `Major.Minor.Patch` (Semantic Versioning)

- **Major**: Breaking changes or major feature releases
- **Minor**: New features, backward compatible
- **Patch**: Bug fixes, backward compatible

**Initial Version**: `1.0.0`

## Version Source Location

Store version in a single location to ensure consistency:

**Option A**: PowerShell constant in BuildFFUVM_UI.ps1
```powershell
$script:FFUBuilderVersion = "1.0.0"
```

**Option B**: Version file (version.txt or version.json)
```json
{
    "version": "1.0.0",
    "buildDate": "2025-12-02",
    "channel": "stable"
}
```

**Recommendation**: Option A for simplicity. A version file adds complexity without significant benefit for this project size.

## Testing Checklist

- [ ] Version displays correctly in title bar
- [ ] Version format is consistent (v1.0.0)
- [ ] About tab displays all information correctly
- [ ] Hyperlinks open in default browser
- [ ] Version is visible at all window sizes
- [ ] Version survives window minimize/restore

## Files to Modify

| File | Changes |
|------|---------|
| BuildFFUVM_UI.xaml | Add About TabItem (if implementing Option 2) |
| BuildFFUVM_UI.ps1 | Add version constant, update title, About tab handlers |

## Estimated Effort

- **Option 1 only**: ~15 minutes
- **Option 2 only**: ~45 minutes
- **Hybrid (both)**: ~1 hour
