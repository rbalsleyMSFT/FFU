---
title: Prerequisites
nav_order: 1
prev_url: /
prev_label: Home
next_url: /quickstart.html
next_label: Quick Start
---
# Prerequisites

## Recommendations

If possible, use an unmanaged Windows 11 or Windows Server machine. In some environments we see security software (AV, EDR, Firewall, etc.) get in the way and cause issues with FFU Builder successfully completing a build.

### Disk space

FFU Builder creates a 50GB dynamic VHDX disk by default which can be configured larger if that's not big enough. When the latest updated Windows media is installed to the VHDX, the VHDX size by itself will be about 15GB or so. If you service the media with the latest CU, that could grow the VHDX by double (~30GB in this case). If you install Office, additional applications, drivers, etc. the VHDX can get large quick. The FFU capture process will compress the size significantly, but between the VHDX size, the Windows media, the application and driver source content, the captured FFU, WinPE, etc. you can easily have over 100GB of used space.

So err on the side of having more free disk space. **Recommended to have at least 100GB free disk space**. 

## Enable Hyper-V

Follow the guide linked below to install Hyper-V on Windows client or Server

[Install Hyper-V in Windows and Windows Server \| Microsoft Learn](https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/get-started/Install-Hyper-V?tabs=gui&pivots=windows)

## Install PowerShell 7

PowerShell 7 is required as of releases 2507+ onward.

[Installing PowerShell on Windows - PowerShell \| Microsoft Learn
](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows)

Recommended to use winget to install

`winget install --id Microsoft.PowerShell --source winget`

If you can't use winget, [download the MSI](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows#installing-the-msi-package)

**Do not** use the Windows Store version as it has some [known limitations](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.5#known-limitations)

## Create Hyper-V Switch

Once Hyper-V has been enabled and you have rebooted, create either an external or internal switch. An external switch is preferred, but an internal switch can be used.

## Download and Extract the Latest Release

If you haven't [downloaded the latest release yet, do so](https://github.com/rbalsleyMSFT/FFU/releases)

Once downloaded, extract the zip file to `C:\FFUDevelopment`. You can use another location, just be sure set your FFUDevelopmentPath to the new location (e.g. `D:\FFUDevelopment`).

After extraction, you most likely will need to unblock the files as they'll be tagged with the mark of the web. In PowerShell run:

`dir "C:\FFUDevelopment" -Recurse | Unblock-File`

Replace `C:\FFUDevelopment` with the path you extracted the files to.

## Running BuildFFUVM_UI.ps1

Either run Terminal as Admin, making sure to select PowerShell, not Windows PowerShell, or PowerShell 7.5+ as Admin and run `C:\FFUDevelopment\BuildFFUVM_UI.ps1`

If all went well, you should see the FFU Builder UI

![1759527337644](image/Prerequisites/1759527337644.png)

{% include page_nav.html %}
