# Using Full Flash Update (FFU) files to speed up Windows deployment

This repo contains the full FFU process that we use in US Education at Microsoft to help customers with large deployments of Windows as they prepare for the new school year. This process isn't limited to only large deployments at the start of the year, but is the most common.

This process will copy Windows in about 2-3 minutes to the target device, optionally copy drivers, provisioning packages, Autopilot, etc. School technicians have even given the USB sticks to teachers and teachers calling them their "Magic USB sticks" to quickly get student devices reimaged in the event of an issue with their Windows PC.

While we use this in Education at Microsoft, other industries can use it as well. We esepcially see a need for something like this with partners who do re-imaging on behalf of customers. The difference in Education is that they typically have large deployments that tend to happen at the beginning of the school year and any amount of time saved is helpful. Microsoft Deployment Toolkit, Configuration Manager, and other community solutions are all great solutions, but are typically slower due to WIM deployments being file-based while FFU files are sector-based.

# Updates

**2404.3**
- Fixed an issue where the latest Windows CU wasn't downloading properly [Commit](https://github.com/rbalsleyMSFT/FFU/commit/ae59183a199f39b310c79b31c9b4980fafdeb79b)

**2404.2**

- If setting -installdrivers to $true and -logicalsectorsizebytes to 4096, the script will now set $copyDrivers to $true. This will create a drivers folder on the deploy partition of the USB drive with the drivers that were supposed to be added to the FFU. There's currently a bug with servicing FFUs with 4096 logical sector byte sizes. Prior to this fix, the script would tell the user to manually set -copydrivers to $true as workaround. This fix just does the workaround automatically. 

**2404.1**

There's a big change with this release related to the ADK. The ADK will now be automatically updated to the latest ADK release. This is required in order to fix an issue with optimized FFUs not applying due to an issue with DISM/FFUProvider.dll. The FFUProvider.dll fix was added to the Sept 2023 ADK. Since we now have the ability to auto upgrade the ADK, I'm more confident in having the BuildFFUVM script creating a complete FFU now (prior it was only creating 3 partitions instead of 4 with the recovery partition - at deployment time, the ApplyFFU.ps1 script would create an empty recovery partition and Windows would populate it on first boot). Please open an issue if this creates a problem for you. I do realize that any new ADK release can have it's own challenges and issues and I do suspect we'll see a new ADK released later this year. 

- Allow for ISOs with single index WIMs to work [Issue 10](https://github.com/rbalsleyMSFT/FFU/issues/10) - [Commit](https://github.com/rbalsleyMSFT/FFU/commit/9e2da741d53652e6e600ca19cfd38f507bd01fde)
- Added more robust ADK handling. Will now check for the latest ADK and download it if not installed. Thanks to [Zehadi Alam](https://github.com/zehadialam) [PR 18](https://github.com/rbalsleyMSFT/FFU/pull/18)
- Revert code back to allow optimized FFUs to be applied via ApplyFFU.ps1 now that Sept 2023 ADK release has FFUProvider.dll fix. [Commit](https://github.com/rbalsleyMSFT/FFU/commit/79364e334d6d09ff150e70dab7bfb2637d0ad8a8)
- Changed how the script searches for the latest CU. Instead of relying on the Windows release info page to grab the KB number, will just use the MU Catalog, the same as what we do for the .NET Framework. Windows release info page is updated manually and is unknown as to when it will be updated. [Commit](https://github.com/rbalsleyMSFT/FFU/commit/6fd5a4a41fd9ce2f842f43dc3a69bda264c29fa6)
- Added fix to not allow computer names with spaces. Thanks to [JoeMama54 (Rob)](https://github.com/JoeMama54) [PR 20](https://github.com/rbalsleyMSFT/FFU/pull/20)

**2403.1**

Fixed an issue with the SecurityHealthSetup.exe file giving an error when building the VM if -UpdateLatestDefender was set to $true. A new update for this came out on 3/21 which included a x64 and ARM64 binary. This file doesn't have an architecture designation to it, so it's impossible to know which file is for which architecture. Investigating to see if we can fix this in the Microsoft Update catalog. There is a web site to pull this from, but the support article is out of date.

Included ADK functions from Zehadi Alam [Introduce Automated ADK Retrieval and Installation Functions #14](https://github.com/rbalsleyMSFT/FFU/pull/14) to automate the installation of the ADK if it's not present. Thanks, Zehadi!

**2402.1**

**New functionality**

* If -BuildUSBDrve $true, script will now check for USB drive before continuing. If not present, script exits
* Added a number of new parameters.

| Parameter            | Type | Description                                                                                                                                                              |
| -------------------- | ---- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| CopyPEDrivers        | Bool | When set to\$true, will copy the drivers from the \$FFUDevelopmentPath\PEDrivers folder to the WinPE deployment media. Default is \$false.                               |
| RemoveFFU            | Bool | When set to\$true, will remove the FFU file from the\$FFUDevelopmentPath\FFU folder after it has been copied to the USB drive. Default is \$false.                       |
| UpdateLatestCU       | Bool | When set to\$true, will download and install the latest cumulative update for Windows 10/11. Default is \$false.                                                         |
| UpdateLatestNet      | Bool | When set to\$true, will download and install the latest .NET Framework for Windows 10/11. Default is \$false.                                                            |
| UpdateLatestDefender | Bool | When set to\$true, will download and install the latest Windows Defender definitions and Defender platform update. Default is \$false.                                   |
| UpdateEdge           | Bool | When set to\$true, will download and install the latest Microsoft Edge for Windows 10/11. Default is \$false.                                                            |
| UpdateOneDrive       | Bool | When set to\$true, will download and install the latest OneDrive for Windows 10/11 and install it as a per machine installation instead of per user. Default is \$false. |
| CopyPPKG             | Bool | When set to\$true, will copy the provisioning package from the \$FFUDevelopmentPath\PPKG folder to the Deployment partition of the USB drive. Default is \$false.        |
| CopyUnattend         | Bool | When set to\$true, will copy the \$FFUDevelopmentPath\Unattend folder to the Deployment partition of the USB drive. Default is \$false.                                  |
| CopyAutopilot        | Bool | When set to\$true, will copy the \$FFUDevelopmentPath\Autopilot folder to the Deployment partition of the USB drive. Default is \$false.                                 |
| CompactOS            | Bool | When set to\$true, will compact the OS when building the FFU. Default is \$true.                                                                                         |
| CleanupCaptureISO    | Bool | When set to\$true, will remove the WinPE capture ISO after the FFU has been captured. Default is \$true.                                                                 |
| CleanupDeployISO     | Bool | When set to\$true, will remove the WinPE deployment ISO after the FFU has been captured. Default is \$true.                                                              |
| CleanupAppsISO       | Bool | When set to\$true, will remove the Apps ISO after the FFU has been captured. Default is \$true.                                                                          |

* Updated the docs with the new variables and made some minor modifications.
* Changed version variable to 2402.1

**2401.1**

- Added -CopyDrivers boolean parameter to control the ability to copy drivers to the USB drive in the deploy partition drivers folder.
- Changed version varaible to 2401.1
- When creating the scratch VHDX, switched it to create a dynamic VHDX instead of fixed
- Fixed an issue where adding drivers to the FFU would sometimes fail and would cause the script to exit unexpectedly
- Added -optimize boolean parameter to control whether the FFU is optimized or not. This defaults to $true and in most cases should be left this way.
- Fixed an issue where if the script failed to create the FFU and the old VM was left behind, it wouldn't clean it up if the VM was in the running state. Will now turn off any running VM with a name prefix of _FFU- and then remove any VMs with a name _FFU- if the environment is flagged as dirty.
- Fixed an issue where devices that ship with UFS drives were unable to image due to the script setting a LogicalSectorSizeBytes value of 512. If you're creating a FFU for devices that have UFS drives, you'll need to set -LogicalSectorSizeBytes 4096.
- There's a known issue where adding drivers to a FFU that has a LogicalSectorSizeBytes value of 4096. Added some code to prevent allowing this to happen. Please use -copydrivers $true as a workaround for now. We're investigating whether this is a bug or not.
- Fixed an issue where VHDX only captures (i.e. where -installapps $false) would not install Windows updates.
- Changed Office deployment to use Current channel instead of Monthly enterprise. If you want to change to Monthly Enterprise channel, it's recommended to leverage Intune.

**2309.2**

New Features

**Multiple USB Drive Support**

You can now plug in multiple USB drives (even using a USB hub) to create multiple USB drives for deployment. This is great for partners or customers who need to provide USB drives to their employees to image a large number of devices. It will copy the content to one USB drive at a time. The most USB drives we've seen created so far is 23 via a USB hub. Open an issue if you see any problems with this.

**Robocopy support**

Replaced Copy-Item with Robocopy when copying content to the USB drive(s). Copy-Item uses buffered IO, which can take a long time to copy large files. Robocopy with the /J switch allows for unbuffered IO support, which reduces the amount of time to copy.

**Better error handling**

Prior to 2309.2, if the script failed or you manually killed the script (ctrl+c, or closing the PowerShell window), the environment would end up in a bad state and you had to do a number of things to manually clean up the environment. Added a new function called Get-FFUEnvironment and a new text file called dirty.txt that gets created in the FFUDevelopment folder. When the script starts, it checks for the dirty.txt file and if it sees it, Get-FFUEnvironment runs and cleans out a number of things to help ensure the next run will complete successfully. Open an issue if you still see problems when the script fails and the next run of the script fails. 

Bug Fixes

- In 2309.1, added a 15 second sleep to allow for the registry to unload to fix a Critical Process Died error on deployment. In this build, increased that to 60 seconds.
- Fixed an issue where the script was incorrectly detecting the USB drive boot and deploy drive letters which caused issues when attempting to copy the WinPE files to the boot partition.

**2309.1**

- Fixed an issue with a Critical Process Died BSOD that would happen when using -installapps $false. More detailed information in the [commit](https://github.com/rbalsleyMSFT/FFU/pull/2/commits/34efbda7ec56dc7cb43ac42b058725d56c8b8899)

**2306.1.2**

- Fixed an issue where manually entering a name wouldn't name the computer as expected

**2306.1.1**

- Included some better error handling if defining optionalfeatures that require source folders (netfx3). ESD files don't have source folders like ISO media, which means installing .net 3.5 as an optional feature would fail. Also cleaned up some formatting.

**2306.1**

- Added support to automatically download the latest Windows 10 or 11 media via the media creation tool (thanks to [Michael](https://oofhours.com/2022/09/14/want-your-own-windows-11-21h2-arm64-isos/) for the idea). This also allows for different architecture, language, and media type support. If you omit the -ISOPath, the script will download the Windows 11 x64 English (US) consumer media.

  An example command to download Windows 11 Pro x64 English (US) consumer media with Office and install drivers (it won't download drivers, you'll put those in your c:\FFUDevelopment\Drivers folder)

  .\BuildFFUVM.ps1 -WindowsSKU 'Pro' -Installapps $true -InstallOffice $true -InstallDrivers $true -VMSwitchName 'Name of your VM Switch in Hyper-V' -VMHostIPAddress 'Your IP Address' -CreateCaptureMedia $true -CreateDeploymentMedia $true -BuildUSBDrive $true -verbose

  An example command to download Windows 11 Pro x64 French (CA) consumer media with Office and install drivers

  .\BuildFFUVM.ps1 -WindowsSKU 'Pro' -Installapps $true -InstallOffice $true -InstallDrivers $true -VMSwitchName 'Name of your VM Switch in Hyper-V' -VMHostIPAddress 'Your IP Address' -CreateCaptureMedia $true -CreateDeploymentMedia $true -BuildUSBDrive $true -WindowsRelease 11 -WindowsArch 'x64' -WindowsLang 'fr-ca' -MediaType 'consumer' -verbose
- Changed default size of System/EFI partition to 260MB from 256MB to accomodate 4Kn drives. 4Kn support needs more testing. I'm not confident yet that this can be done with VMs and FFUs.
- Added versioning with a new version parameter. Using YYMM as the format followed by a point release.

# Getting Started

If you're not familiar with Github, you can click the Green code button above and select download zip. Extract the zip file and make sure to copy the FFUDevelopment folder to the root of your C: drive. That will make it easy to follow the guide and allow the scripts to work properly.

If extracted correctly, your c:\FFUDevelopment folder should look like the following. If it does, go to c:\FFUDevelopment\Docs\BuildDeployFFU.docx to get started.

![image](https://github.com/rbalsleyMSFT/FFU/assets/53497092/5400a203-9c2e-42b2-b24c-ab8dfd922ba1)
