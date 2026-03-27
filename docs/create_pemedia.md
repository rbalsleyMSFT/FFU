---
title: Create PE Media
nav_order: 1
prev_url: /helper_scripts.html
prev_label: Helper Scripts
next_url: /usb_imaging_tool_creator.html
next_label: USB Imaging Tool Creator
parent: Helper Scripts
---
# Create PE Media

`Create-PEMedia.ps1` is a standalone helper script that creates WinPE deployment ISO files outside the main build flow.

This is useful when admins need to quickly generate a deploy ISO for a share (or local staging folder) that technicians will use with `USBImagingToolCreator.ps1`.

## Common use case

If your staging location does not already have a deployment ISO, run `Create-PEMedia.ps1` to generate one, then copy that ISO to the staging folder used by your technicians.

## Prerequisites

- Run from an elevated PowerShell session.
- Windows ADK + WinPE add-on must be installed (default path: `C:\Program Files (x86)\Windows Kits\10\`).
- Script should be run from the `FFUDevelopment` folder (or provide explicit paths via parameters).

## Quick start (deploy ISO)

From `FFUDevelopment`, this creates a deploy ISO by default:

```powershell
.\Create-PEMedia.ps1
```

Default output file:

- `.\WinPE_FFU_Deploy_x64.iso`

## Useful commands

Create deploy ISO for x64:

```powershell
.\Create-PEMedia.ps1 -WindowsArch 'x64'
```

Create deploy ISO for ARM64:

```powershell
.\Create-PEMedia.ps1 -WindowsArch 'arm64' -DeployISO "$PSScriptRoot\WinPE_FFU_Deploy_arm64.iso"
```

Create deploy ISO and include PE drivers from `.\PEDrivers`:

```powershell
.\Create-PEMedia.ps1 -CopyPEDrivers $true
```

## Stage output for USB imaging

After creating the deploy ISO, place it in the same staging root used for USB media creation.

Example:

```text
\\Server\FFUStaging\
  WinPE_FFU_Deploy_x64.iso
  FFU\
    <image files>.ffu
  Drivers\
    <optional driver content>
```

Then technicians can run:

```powershell
.\USBImagingToolCreator.ps1 -DeployISOPath "\\Server\FFUStaging\WinPE_FFU_Deploy_x64.iso" -DisableAutoPlay
```

## Logging

`Create-PEMedia.ps1` writes log output to:

- `.\Create-PEMedia.log` (or custom path via `-LogFile`)

{% include page_nav.html %}