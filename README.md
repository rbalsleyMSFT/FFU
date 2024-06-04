# Using Full Flash Update (FFU) files to speed up Windows deployment

This repo contains the full FFU process that we use at Central Bucks School District to assist us in maintaining over 19k windows devices. This process isn't limited to only large deployments; we use it daily to support our fleet.

This process will copy Windows in about 2-3 minutes to the target device, optionally Install drivers, provisioning packages, Autopilot, etc. School technicians have even given the USB sticks to teachers and teachers calling them their "Magic USB sticks" to quickly get student devices reimaged in the event of an issue with their Windows PC.

While this is used for Education at Microsoft, other industries can use it as well. The difference in Education is that they typically have large deployments that tend to happen at the beginning of the school year and any amount of time saved is helpful. Microsoft Deployment Toolkit, Configuration Manager, and other community solutions are all great solutions, but are typically slower due to WIM deployments being file-based while FFU files are sector-based.

My goal in adding all of this functionality was to make it easier to adjust what the script does and put it in a scheduled task that runs once a month. So we always have an updated image that just needs to be tested on some devices.

![image](https://github.com/MKellyCBSD/ImagingTool/assets/167896478/0475889a-6a1e-4ac1-9026-7fdddb52e2c2)

# Instructions
### Edit the config.ini file to adjust what features your full flash update image will have.
### Any bool field left blank in the config.ini file will be considered false.
  1 = $True | 0 = $False
  
  **Config.ini**
| Parameter            | Type | Description                                                                                                                                                              |
| -------------------- | ---- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| ISOPath        | String | When left blank downloads latest ESD from Microsoft or Install ESD provided at ESDPath. do not use quotes: **C:\FFUDevelopment\Win11_22H2_English_x64.iso**                             |
| ESDPath            | String | When left blsnk downloads latest ESD from Microsoft. if path to ESD is provided offline ESD will be used do not use quotes: **C:\FFUDevelopment\Windows11.esd**                  |
| WindowsSKU       | String | Edition of Windows 10/11 to be installed, e.g., accepted values are: 'Home', 'Home N', 'Home Single Language', 'Education', 'Education N', 'Pro', 'Pro N', 'Pro Education', 'Pro Education N', 'Pro for Workstations', 'Pro N for Workstations', 'Enterprise', 'Enterprise N'. Do not use Single quotes.  
| WindowsRelease       | Integer | Integer value of 10 or 11. This is used to identify which release of Windows to download. Default is 11.  |
| WindowsVersion      | String | String value of the Windows version to download. This is used to identify which version of Windows to download. Default is 23H2.    |
| WindowsArch | String | String value of x86 or x64. This is used to identify which architecture of Windows to download. Default is x64.    |
| WindowsLang           | String | String value in language-region format (e.g. en-us). This is used to identify which language of media to download. Default is en-us.       |
| MediaType       | String | String value of either business or consumer. This is used to identify which media type to download. Default is consumer. |
| DisableAutoPlay             | Bool | When set to 1, Will disable autoplay in the windows registry and re-enable after script is complete. This prevents file explorer from opening multiple windows with **Location not available** errors when create new partitions. Default is 0       |
| CompactOS         | Bool | When set to 1, will compact the OS when building the FFU. Default is 1.                                 |
| UpdateLatestCU        | Bool | When set to 1, will download and install the latest cumulative update for Windows 10/11. Default is 0.                                 |
| UpdateLatestNet            | Bool | When set to 1, will download and install the latest .NET Framework for Windows 10/11. Default is 0.     |
| OptionalFeatures    | String | Provide a semi-colon separated list of Windows optional features you want to include in the FFU (e.g. netfx3;TFTP). NOTE: **Cannot enable netfx3 when ESD is used**  |
| ProductKey     | String | Product key for the Windows 10/11 edition specified in WindowsSKU. This will overwrite whatever SKU is entered for WindowsSKU. Recommended to use if you want to use a MAK or KMS key to activate Enterprise or Education. If using VL media instead of consumer media, you'll want to enter a MAK or KMS key here.                         |
| VMLocation       | String | Default is $FFUDevelopmentPath\VM. This is the location of the VHDX that gets created where Windows will be installed to.                    |
| FFUPrefix   | String | Prefix for the generated FFU file. Default is _FFU.                               |
| ShareName            | String | Name of the shared folder for FFU capture. The default is FFUCaptureShare. This share will be created with rights for the user account. When finished, the share will be removed.                       |
| Username       | String | Username for accessing the shared folder. The default is ffu_user. The script will auto create the account and password. When finished, it will remove the account.                     |
| Memory       | Integer | Amount of memory to allocate for the virtual machine. Recommended to use 8GB if possible, especially for Windows 11. Use 4GB if necesary.                     |
| Disksize        | Integer | Size of the virtual hard disk for the virtual machine. Default is a 30GB dynamic disk.                               |
| Processors            | Integer | Number of virtual processors for the virtual machine. Recommended to use at least 4.                       |
| VMSwitchName       | String | Name of the Hyper-V virtual switch. If $InstallApps is set to $true, this must be set. This is required to capture the FFU from the VM. The default is *external*, but you will likely need to change this.   |
| VMHostIPAddress      | String | IP address of the Hyper-V host for FFU capture. **If $InstallApps is set to 1, this parameter must be configured**. You must manually configure this. The script will not auto detect your IP (depending on your network adapters, it may not find the correct IP). |
| LogicalSectorSizeBytes | Integer | Unit32 value of 512 or 4096. Not recommended to change from 512. Might be useful for 4kn drives, but needs more testing. Default is 512. 
| Installapps | Bool |When set to 1, the script will create an Apps.iso file from the $FFUDevelopmentPath\Apps folder. It will also create a VM, mount the Apps.ISO, install the Apps, sysprep, and capture the VM. When set to 0, the FFU is created from a VHDX file. No VM is created. |
| InstallOffice           | Bool | Install Microsoft Office if set to 1. The script will download the latest ODT and Office files in the $FFUDevelopmentPath\Apps\Office folder and install Office in the FFU via VM. Default is 0  |
| InstallDrivers       | Bool | Install device drivers from the specified $FFUDevelopmentPath\Drivers folder if set to 1. Download the drivers and put them in the Drivers folder. The script will recurse the drivers folder and add the drivers to the FFU. Default is 0  |
| UpdateEdge             | Bool | When set to 1, will download and install the latest Microsoft Edge for Windows 10/11. Default is 0.        |
| UpdateLatestDefender         | Bool | When set to 1, will download and install the latest Windows Defender definitions and Defender platform update. Default is 0.                                  |
| UpdateOneDrive        | Bool | When set to 1, will download and install the latest OneDrive for Windows 10/11 and install it as a per machine installation instead of per user. Default is 0.                                 |
| UpdateWinGet            | Bool | When set to 1, will update WinGet to the latest version available. Default is 0.                                                                                         |
| InstallRedistributables    | Bool | When set to 1, download and install latest version of visual C++ reditributables for x86 and x64. Default is 0.                                                                 |
| InstallTeams     | Bool | When set to 1, will download and install latest version of New Teams x64. Default is 0.                                                              |
| CopyDrivers       | Bool | When set to 1, will copy the drivers from the $FFUDevelopmentPath\Drivers folder to the Drivers folder on the deploy partition of the USB drive. Default is 0. 
| CopyPEDrivers           | Bool | When set to 1, will copy the drivers from the $FFUDevelopmentPath\PEDrivers folder to the WinPE deployment media. Default is 0.  |
| CreateCaptureMedia       | Bool | When set to 1, this will create WinPE capture media for use when $InstallApps is set to 1. This capture media will be automatically attached to the VM and the boot order will be changed to automate the capture of the FFU. Default is 1 |
| FFUCaptureLocation             | String | Path to the folder where the captured FFU will be stored. Default is $FFUDevelopmentPath\FFU if not path is specified |
| CreateDeploymentMedia         | Bool | When set to $true, this will create WinPE deployment media for use when deploying to a physical device.                                  |
| ImageAgeLimit        | Integer | Image age limit is the time days you want FFU images to be valid for. Any image older than what is set here will not show as available on the apply image tool. Default is 60.                                 |
| BuildUSBDrive            | Bool | When set to 1, will partition and format a USB drive and copy the captured FFU to the drive. If you'd like to customize the drive to add drivers, provisioning packages, name prefix, etc. You'll need to do that afterward. Default is 0|
| CopyPPKG    | Bool | When set to 1, will copy the provisioning package from the $FFUDevelopmentPath\PPKG folder to the Deployment partition of the USB drive. Default is 0.                                                                 |
| CopyUnattend     | Bool | When set to 1, will copy the $FFUDevelopmentPath\Unattend folder to the Deployment partition of the USB drive. Default is 0.                                                              |
| CopyAutopilot       | Bool | When set to 1, will copy the $FFUDevelopmentPath\Autopilot folder to the Deployment partition of the USB drive. Default is 0.
| CleanupCaptureISO    | Bool | When set to 1, will remove the WinPE capture ISO after the FFU has been captured. Default is 0.  |
| CleanupCaptureShare     | Bool | When set to 1, will remove FFU capture share used to capture images to a local drive. Default is 1.            |
| CleanupDeployISO    | Bool | When set to 1, will remove the WinPE deployment ISO after the FFU has been captured. Default is 0.  |
| CleanupAppsISO       | Bool | When set to 1, will remove the Apps ISO after the FFU has been captured. Default is 1.
| Optimize     | Bool | When set to 1, will optimize the FFU file. Default is 1. |
| RemoveVM     | Bool | When set to 1, will remove the VM created from this script. Default is 1. |
| RemoveFFU       | Bool | When set to 1, will remove the FFU file from the $FFUDevelopmentPath\FFU folder after it has been copied to the USB drive. Default is 0.
## Then run the script
    .\BuildFFUVM.ps1 -ConfigPath "C:\FFUDevelopment\Config.ini" -Verbose
# Updates
### **2024.6**

**BuildFFUVM.ps1**

- Rebuilt how the scripts many switches (50) are utilized with a config.ini file. 1 is True, 0 is False. All file paths must be **without** starting and ending quotes.
- Added Clear-InstallAppsandSysprep function to Get-FFUEnvironment function.
- Added code to download the latest Winget package manager.
- Added code to install the latest Winget package manager to the InstallAppsandSysprep.cmd.
- Added code to download the latest Visual C++ Redistributables.
- Added code to install the latest latest Visual C++ Redistributables to the InstallAppsandSysprep.cmd
- Added code to download and install the latest version of Teams.
- Added code to install the latest version of Teams to the InstallAppsandSysprep.cmd
- Added code to auto generate InstallAppsandSysprep.cmd if it is not present.
- Moved the dism clean up of the WinSxS folder to the scratch vhdx. This makes the final FFU file smaller (reduced ~650MB).
- Added code to reference the images age limit set in the config.ini file
- Replaced Invoke-WebRequest with Start-BitsTrasfer for all large file downloads.
- Added code to disable autoplay in the windows registry while the script runs and re-enables it when the script completes. this is to prevent "Location not available" errors to prevent many file explorer windows from opening automatically when creating new partitions while the script is running.
- Added code so FFUCaptureLocation can be specified in config.ini file.
  
**BuildUSBDrives.ps1**
- Added code to build a diskpart.txt script for formating volumes and use it to build usb drives.
- Added code to close all file explorer windows related to this tool when building usb drives is completed.
- An option has been added to choose either one or all USB drives that are currently inserted.
- Simultaneous creation of multiple drives is supported, which significantly reduces the time required. For instance, the time required to create three 128GB drives is reduced from 21 minutes to approximately 8-9 minutes, depending on the USB specification, USB controller, and USB drive write speed.
- A progress bar has been added. It advances in segments, so it may appear to be frozen at times, but it is functioning correctly. Please be patient while it progresses.
- During the creation of the USB drives, image and driver files are automatically copied to the drives. If the Images and Drivers folders exist in the same folder as the CBSD IT-Base-June2024.iso file and contain files, those folders will also be copied to the USB drives.
  
**CaptureFFU.ps1**
- Removed startnet.cmd and switched to winpeshl.ini for launching the capture and deployment scripts.
  - Startnet.cmd works fine however winpeshl.ini is a different approch that only loads the powershell script. | https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpeshlini-reference-launching-an-app-when-winpe-starts?view=windows-11

**ApplyFFU.ps1**
- Added code to only show images updated within the number of days set for ImageAgeLimit in the config.ini file.

**Known Issues**
- No issues currently known. still needs more validation that all of the config file switches work properly with the config.ini file.

### **2024.5**
 
**BuildFFUVM.ps1**
- Resolved an issue with -UpdateLatestCU where it was not locating the latest monthly cumulative update for windows
- Added code to clean up the deployment flash drive .iso when other languages aren't being used.
  - A large number of unused language folders are created by default. This clears them out when a language isn't specified
- Added code to preserve the specified language folder when other languages are being utilized.
  - When a language other than en-us is specified; all other unused folders including en-us are cleared out and the specified language folder is preserved.
- Added code that creates an Images and Drivers folder on the root of the .iso.
- 
  

**ApplyFFU.ps1**
- Removed driver selection menu in place of auto installing drivers based off of the model number. (Lenovo model types are truncated down to the first 4 charactars)
  - This change allows a large number of driver folders so you can use one flash drive for all of your device models. As long as the model matches the driver folder name.
- Added code for detecting wether a main drive is available to apply the OS to. If the drive isn't detected the console will show red (shown below)
- Added code that looks to \Images for device images.
- Added code that looks to \Drivers for device drivers
- Removed startnet.cmd and switched to winpeshl.ini for launching the capture and deployment scripts.
  - Startnet.cmd works fine however winpeshl.ini is a different approch that only loads the powershell script. | https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpeshlini-reference-launching-an-app-when-winpe-starts?view=windows-11
- Added code to display device information:
  - System Time
  - Serial Number
  - Model
  - System Family
  - Manufacturer
  - OS Drive Model
  - Battery Charge Level
 
 **BuildUSBDrives.ps1**
 - Added open file dialog for selecting deployment .iso files
 - Added warning that all currently connected USB flash drives will be erased
 - Build flash drives from deployment .iso files created by BuildFFUVM.ps1

  
**Everything below was developed by Microsoft:**
- https://github.com/zehadialam
- https://github.com/JoeMama54
- https://github.com/rbalsleyMSFT

  *From this Github Repo:*
  https://github.com/rbalsleyMSFT/FFU
  
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
