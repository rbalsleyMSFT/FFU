# Change Log

# 2509.1 UI Preview

## What's Changed

### [Refactor: Enhance artifact cleanup for disabled features](https://github.com/rbalsleyMSFT/FFU/commit/1ab4093d54b7d9bda9f47d7819694e66ae8de357)

  Renames `Remove-DisabledUpdates` to `Remove-DisabledArtifacts` to better reflect its expanded scope.

  This function now also removes Office installation scripts and downloaded content if the Office installation is disabled via the `$InstallOffice` flag.

  The function call is moved to run before app installations to ensure artifacts are removed prior to the installation phase.

### [Removes the VM workaround for MCT ESD builds](https://github.com/rbalsleyMSFT/FFU/commit/dc5877f398316969299ee03800f3d07c7d98a9ab)

  Comments out the logic that forces app installation when building from a downloaded ESD file. This workaround was implemented to prevent an OOBE reboot loop but is no longer required. This should speed up scenarios where you want to download the ESD media, install the latest CU and .NET CU, and capture the FFU.

### [Update default disk size to 50GB in FFU scripts and UI](https://github.com/rbalsleyMSFT/FFU/commit/372360d7392ad945be0db889a68e1fff0ed3b5d6)

  Changed the default disk size parameter from 30GB to 50GB in BuildFFUVM.ps1 and FFUUI.Core.psm1 to accommodate larger virtual machines.
  Updated tooltip and default value in the UI XAML file to reflect the new disk size.

### [Adds auto-loading of previous configuration on startup](https://github.com/rbalsleyMSFT/FFU/commit/3ef26f2918977906ebe14e328f015ce4f1941dc3)

Implements a new feature to automatically load the previously saved environment when the UI is launched.

This improves user experience by restoring the last saved configuration, including selected applications and drivers, eliminating the need to manually reload them on each run.

The process loads the main `FFUConfig.json` and then proceeds to load associated Winget, BYO App, and Driver lists if they are defined. UI elements and checkboxes are updated accordingly to reflect the loaded state.

### [Improves UI state after environment autoload](https://github.com/rbalsleyMSFT/FFU/commit/bdf1b63833c83171aed63e8fc16702078ccd577b)

Updates the visibility of UI panels for Winget and drivers when a previous environment is automatically loaded.

This ensures that if Winget apps or driver models are present, their corresponding UI sections are made visible. Additionally, it updates the "select all" checkbox state for Winget results and attempts to pre-select the hardware make for loaded drivers.

### [Add restore defaults and centralize cleanup logic](https://github.com/rbalsleyMSFT/FFU/commit/f3316a017b73bf12cf1a66e3d03a63e29c437cb1)

Introduces a "Restore Defaults" feature in the UI to reset the environment. This action removes generated configuration files, ISOs, downloaded apps, updates, drivers, and FFUs.

The post-build cleanup logic is refactored from the main build script into a new common function. This new function is used by both the standard build process and the new restore defaults feature, promoting code reuse and simplifying maintenance.

### [Add option to dynamically build PE drivers](https://github.com/rbalsleyMSFT/FFU/commit/e2ccd11f07217b389f1622a69794224412e046e1)

Thanks to @JonasKloseBW for the original code for this in https://github.com/rbalsleyMSFT/FFU/pull/115

Introduces a new parameter, `UseDriversAsPEDrivers`, that allows WinPE drivers to be sourced directly from the main driver repository.

When enabled, the script scans all available drivers, parses their INF files, and copies only the essential driver types (e.g., storage, mouse, keyboard, touchpad, system devices) needed for WinPE. This eliminates the need to maintain a separate, manually curated `PEDrivers` folder.

The UI is updated with a new checkbox that becomes visible when "Copy PE Drivers" is selected, making this a sub-option. Parameter validation is also adjusted to support this new workflow.

### [Improve model name normalization for driver mapping](https://github.com/rbalsleyMSFT/FFU/commit/50713188bffcb64f1b0c1f9eb89e02a300e3de98)

Enhances the model name normalization function to better handle variations in hardware model strings. This change introduces specific rules to canonicalize "All-in-One" and screen size variants (e.g., "-in" or "inch") for more reliable matching against driver mapping rules.

Additionally, optimizes performance by normalizing the system model once before the comparison loop. Logging is also added to show the original and normalized model strings for easier debugging.

### [Defer cleanup of compressed driver source folders](https://github.com/rbalsleyMSFT/FFU/commit/c30ed923b68b933f719b9a2941043b813bf4fd3f)

Implements a deferred cleanup mechanism for driver source folders when they are compressed to a WIM and also used for WinPE.

When drivers are compressed, the original source folders are now preserved if they are also needed for WinPE driver injection. A marker file is created in these preserved folders.

A new cleanup step is added after the WinPE media creation to remove these preserved folders, ensuring they are available when needed but not left behind permanently.

### [Refactor config loading and improve error handling](https://github.com/rbalsleyMSFT/FFU/commit/8d7e4d106620761d0ae1a5133f6d6ba301131471)

Extracts the logic for importing supplemental assets (Winget, BYO, Drivers) into a new reusable function. This function is now called by both the manual and automatic configuration loaders, reducing code duplication.

Enhances the manual configuration loading process with more robust error handling. It now provides specific user-facing error messages for file read failures, empty files, and invalid JSON, improving the user experience when loading a malformed configuration.

When loading a configuration, if optional supplemental files like AppList.json are referenced but not found, an informational message is now displayed to the user instead of failing silently.

### [Add robust sanitization for names used in paths](https://github.com/rbalsleyMSFT/FFU/commit/cb14e84a26acaf5863aa3bb094dbf18424798875)

Introduces a new common function, `ConvertTo-SafeName`, to sanitize strings by removing characters that are invalid in Windows file paths.

This function is now used consistently when creating directory and file names for drivers (Dell, HP, Lenovo, Microsoft) and applications to prevent path-related errors. It replaces several ad-hoc sanitization methods with a single, more robust implementation.

### [Includes exit code fields when using Copy Apps button](https://github.com/rbalsleyMSFT/FFU/commit/f37647599a318da29b62154bebff8c8a857d3002)

Adds persistence of AdditionalExitCodes and IgnoreNonZeroExitCodes when exporting the UI list to prevent losing custom exit handling settings and maintain parity with the primary save routine.

### [Sanitizes app names for storage and paths](https://github.com/rbalsleyMSFT/FFU/commit/d1ca1231045e38316733495e1fdb8590a225be67)

Applies name sanitization when persisting the app list and when building/checking Win32 and Store download directories.
Prevents invalid characters in folder names, aligns persisted names with on-disk structure, and improves detection of existing content to avoid redundant downloads and errors.

### [Adds exit-code overrides and UI for winget apps](https://github.com/rbalsleyMSFT/FFU/commit/d9c0c9c68ee1769230c9789b5c7cb84bcff4d642)

Adds per-app control for additional accepted exit codes and ignoring non‑zero exit codes to improve handling of installers with nonstandard returns.

Exposes editable fields in the app list UI, persists them across search defaults, import/export, and pre-download save, and applies overrides during app resolution to honor configured behavior.

### [Adds UI/CLI to copy additional FFUs to USB build](https://github.com/rbalsleyMSFT/FFU/commit/15a5b16b39887b71ae545c638d57183c97bdf629)

- Enables selecting multiple existing FFU images to include on the deployment USB for easier distribution and testing.
- Adds a UI option with selectable, sortable list from the capture folder, refresh support, and persisted selections.
- Validates that selections exist when the option is enabled to prevent empty runs.
- Supports unattended/CLI flows by prompting early or accepting a preselected list for USB creation; deduplicates and logs chosen files.
- Always includes the just-built (or latest available) FFU as a base.
- Improves no-FFU handling and streamlines multi-FFU selection workflow.

### [Standardizes JSON output: depth, UTF-8, key order](https://github.com/rbalsleyMSFT/FFU/commit/6562d16ce500197b428b51915332c6649df302df)

- Sorts top-level config keys before serialization for deterministic files and cleaner diffs.
- Increases JSON depth to 10 to retain nested settings.
- Writes JSON as UTF-8 via Set-Content for consistent encoding.
- Applies across config export and UI save flows.

### [Adds Windows 11 25H2 mapping](https://github.com/rbalsleyMSFT/FFU/commit/eaa3e1e6af5c25e0f8b185f8107e017782b0f00f)

Extends supported Windows 11 releases to include 25H2. Default is still 24H2.

* Update USBImagingToolCreator.ps1 by @jrollmann in https://github.com/rbalsleyMSFT/FFU/pull/262

## New Contributors

* @jrollmann made their first contribution in https://github.com/rbalsleyMSFT/FFU/pull/262

# 2507.1 UI Preview

Waaay too many to list. Just watch the Youtube video in the Readme :)

# 2505.1

Highly recommended that you upgrade to this release. Fixes the issue with the May 2025 cumulative update and some SKU naming issues for SKUs other than Pro.

# Support for Windows LTSB/LTSC

Thanks to @zehadialam for the code to allow support for LTSB and LTSC. This has been a requested feature from a number of customers and some might be opting for LTSC when Windows 10 support ends in October. We support LTSB 2016, LTSC 2019, 2021, 2024 including the N and IoT variants. Extensive testing has gone into validating CU and .net support. File an issue if you see any weird behavior.

# Support for automating computer naming via CSV

Thanks to @JonasKloseBW for PR #150

- Allows setting the computer name with a predefined list (SerialComputerNames.csv) of serial numbers and matching computer names
- Defaults to FFU-{Random} if no matching serial number is found in list so FFU deployment can continue without user input

# Fixes

- Thanks to @JonasKloseBW for PR #129 for adding the -AppListPath parameter
- Fixed an issue where if AppsScriptVariables was configured in a config file, the hashtable wasn't being created by the script when setting the variable.
- Fixed a crash where shortening the Windows SKU was creating duplicate shortened names for certain SKUs (EDU mainly, but others too)
- Fix an issue with checkpoint CUs and May 2025-05B CU. Should future proof new checkpoint CUs in the future.

# Additional Fixes

BuildFFUVM.ps1

- Added parameter definitions that were missing:
  - AppListPath - Path to a JSON file containing a list of applications to install using WinGet. Default is $FFUDevelopmentPath\Apps\AppList.json.
  - PEDriversFolder - Path to the folder containing drivers to be injected into the WinPE deployment media. Default is $FFUDevelopmentPath\PEDrivers.
- Added two new parameters:
  - UpdateLatestMicrocode - This is used for Windows 10/Server. When set to $true, will download and install the latest microcode updates for applicable Windows releases (e.g., Windows Server 2016/2019, Windows 10 LTSC 2016/2019) into the FFU. Default is $false.
  - UpdateADK - Added for airgapped scenarios where you've manually updated the ADK and don't need it to continually check. When set to $true, the script will check for and install the latest Windows ADK and WinPE add-on if they are not already installed or up-to-date. Default is $true.
- Reorganized the WindowsSKU validateset to make it easier to read and added in 2016 LTSB releases
- Changed version to 2505.1
- Reorganized the releasetoMapping SKUs to make it easier to read
- Omitted Defender/Edge from reporting KB ID since neither includes it
- Updated Save-KB with some enhancements from the UI branch which will handle KBs that don't have an architecture defined in their file name that will leverage a new function Get-PEArchitecture that can interrogate the file name and determine the correct architecture
- Updated Get-ShortenedWindowsSKU with LTSB/LTSC SKUs
- Updated New-FFUFileName to use $winverinfo.Name for $WindowsRelease for client OSes to which will set $WindowsRelease to using Win10 or Win11. This fixes a bug where you might see 10 or 11 instead of Win10 or Win11 for FFU builds that use only the VHDX (e.g. `-InstallApps $false`. This keeps the naming consistent with FFUs built via VM.
- Updated Get-WindowsVersionInfo to fix an issue with naming LTSC 2019
- Added Get-PEArchitecture function
- Commented out the Windows Security Platform Update code since the URL is dead for the content. This is fixed in the UI branch and will be reintroduced in Dev and Main at a later date when the UI work is complete.
- Created a new variable `$isLTSC`
- Modified and reorganized the search strings for the various .net framework components. LTSC introduced some complexity with handling the various .net releases.
- VHDXCaching will now recurse the KBPath folder when finding downloaded KBs to include in its config file

Sample_default.json

- Added new/missing parameters
  - ApplistPath
  - UpdateADK
  - UpdateLatestMicrocode

CaptureFFU.ps1

- `$WindowsVersion` 2016 and 2019 for LTSC releases
- Changed some SKU spacing to make things more consistent and included Enterprise N LTSC

ApplyFFU.ps1

- Updated version to 2505.1

# 2412.1

This is a major release with a number of quality-of-life improvements that will reduce the time it takes to create FFUs. I highly recommend you update to this release.

## Windows Server Support

Thanks to [JonasKloseBW](https://github.com/JonasKloseBW) we have added support for Windows Server! This includes support for Windows Server 2016 through 2025 and supports both core and desktop experience. It will require you to provide your own Server ISO
using the `-ISOPath` parameter since we can't automatically download it like we can with client. You also will want to set the `-WindowsSKU` parameter to either `'Standard', 'Datacenter', 'Standard (Desktop Experience)', or 'Datacenter (Desktop Experience)'` depending on your needs.

Cumulative Updates for Windows and .NET should work as expected. Defender updates should work too. If you notice anything that doesn't work, open an issue.

## VHDX Caching Support

Thanks again to Jonas for adding VHDX caching support #89. For those of you that might be making many FFUs for different configurations, instead of building the VHDX every time, you can cache the VHDX and re-use it for your next build. In testing, this seems to save about 10 minutes, depending on how you're installing Windows (via MCT download, or your own ISO and how old your media is).

The way this works is a VHDXCache folder is created in the FFUDevelopment folder. If `-AllowVHDXCaching $true`, we store the VHDX file and a config file that keeps track of the following info

```
{
  "VhdxFileName": "_FFU-808829869.vhdx",
  "LogicalSectorSizeBytes": 512,
  "WindowsSKU": "Pro",
  "WindowsRelease": "11",
  "WindowsVersion": "24H2",
  "OptionalFeatures": "",
  "IncludedUpdates": [
    {
      "Name": "windows11.0-kb5043080-x64_953449672073f8fb99badb4cc6d5d7849b9c83e8.msu"
    },
    {
      "Name": "windows11.0-kb5045934-x64-ndp481_fa9c3adfb0532eb8f4e521f4fb92a179380184c5.msu"
    },
    {
      "Name": "windows11.0-kb5048667-x64_d4ad0ca69de9a02bc356757581e0e0d6960c9f93.msu"
    }
  ]
}
```

The VHDX files are cached before boot, so they've never been sysprepped. On subsequent runs, if `-AllowVHDXCaching $true` is set, we search the VHDXCache folder, loop through any config files, and look to see if we find one that matches the build information you've passed to the script. If a match is found, robocopy copies in the VHDX and uses the cached VHDX to build the FFU VM.

## Configuration File Support

A configuration file can now be used to configure the parameters in lieu of, or in conjunction with, parameters specified on the command line. Configuration files are especially helpful for those making FFUs for different models, Windows releases, application sets, and more.

To use, run:
`.\BuildFFUVM.ps1 -ConfigFile 'C:\FFUDevelopment\config\Sample_default.json' -verbose`

### Creating your own Configuration Json file

If you have a command line that you’ve been using for awhile and would like to convert it to a json file automatically, run your command line like normal, adding
`-exportConfigFile 'C:\FFUDevelopment\config\YourConfigFile.json'`
to the end of the command. Doing this will generate a well-formatted json file with your configuration settings.

You can also temporarily overwrite parameters while using a config file. Using the following sample command:

`.\BuildFFUVM.ps1 -ConfigFile 'C:\FFUDevelopment\config\Sample_default.json' -verbose`

If you’d like to not include Office (the Sample_default.json file installs Office), you’d add `-InstallOffice $False` to the command line

`.\BuildFFUVM.ps1 -ConfigFile 'C:\FFUDevelopment\config\Sample_default.json' -verbose -InstallOffice $False`

Doing this will temporarily overwrite whatever is in the json for the `InstallOffice` parameter. It will not modify the json file. If you would like to change the json file, you can add `-exportConfigFile 'C:\FFUDevelopment\config\Sample_default.json'` and that will overwrite the json file with the new parameter.

`.\BuildFFUVM.ps1 -ConfigFile 'C:\FFUDevelopment\config\Sample_default.json' -verbose -InstallOffice $False -exportConfigFile 'C:\FFUDevelopment\config\Sample_default.json'`

## Custom FFU Naming Support

Thanks to Jonas, we now have custom FFU naming support. A new parameter -CustomFFUNameTemplate has been added.

This parameter sets a custom FFU output name with placeholders. Allowed placeholders are:

`{WindowsRelease}, {WindowsVersion}, {SKU}, {BuildDate}, {yyyy}, {MM}, {dd}, {H}, {hh}, {mm}, {tt}`

And below is a description of what to expect when you use each placeholder.

```
{WindowsRelease} = 10, 11, 2016, 2019, 2022, 2025
{WindowsVersion} = 1607, 1809, 21h2, 22h2, 23h2, 24h2, etc
{SKU} = Home, Home N, Home Single Language, Education, Education N, Pro, Pro N, Pro Education, Pro Education N, Pro for Workstations, Pro N for Workstations, Enterprise, Enterprise N, Standard, Standard (Desktop Experience), Datacenter, Datacenter (Desktop Experience)
{BuildDate} = e.g. Dec2024
{yyyy} = e.g. 2024
{MM} = 2 digit month format (e.g. 12 for December)
{dd} = Day of the month in 2 digit format (19)
{HH} = Current hour in 24-hour format (e.g., 14 for 2 PM)
{hh} = Current hour in 12-hour format (e.g., 02 for 2 PM)
{mm} = Current minute in 2-digit format (e.g., 09)
{tt} = Current AM/PM designator (e.g., AM or PM)
```

An example for Windows 11 24h2 Pro built today would be:

`-CustomFFUNameTemplate '{WindowsRelease}_{WindowsVersion}_{SKU}_{yyyy}-{MM}-{dd}_{HH}{mm}'`

Would result in a FFU file name of:

`Win11_24h2_Pro_2024-12-20_1225.ffu`

You can also mix in static text in the name

`-CustomFFUNameTemplate '{WindowsRelease}_{WindowsVersion}_{SKU}_Office_{yyyy}-{MM}-{dd}_{HH}{mm}'`

Would result in:

`Win11_24h2_Pro_Office_2024-12-20_1225.ffu`

## Additional PRs added

#79 Includes the latest Microsoft Software Removal Tool from `@zehadialam` - use `-UpdateLatestMSRT $true`

#72 Includes some Unattend Sample files from @HedgeComp in the `$FFUDevelopment\Unattend` folder

#74 Includes some improvements to the USBImagingToolCreator.ps1 file from @w0

#103 Includes some additional improvements to the USBImagingToolCreator.ps1 file from @MKellyCBSD

## Misc Fixes

- Added server skus to validateset for $WindowsSKU
- Added new variable $installationType which uses $WindowsRelease to determine Server or Client. If $installationType is Server, $WindowsRelease version is used to set $WindowsVersion to the appropriate version (1607, 1809, 21H2)
- Fixed an issue where the recovery partition wouldn't be created on server OSes due to winre.wim being hidden. Never saw this on client OSes even though it also was hidden IIRC.
- Removed verbosity for Optimize-Volume as it was outputting when -verbose was not specified.
- Modified some search strings for .NET CUs when installing on Server OS
- Included SSU for Windows Server 2016 as it's mandatory
- Added some error checking for Server 2019 and 2022 CU installations when CU fails due to lack of SSU. If you run into this error, you're using old media and should use the latest. Always use the latest ISO if you can.
- $WindowsVersion set to 24h2, can override by using -WindowsVersion 23H2 if you want the old behavior
- Removed the "Downloading information GUID" messages when downloading content from the Microsoft Update Catalog while -verbose was specified in the command line
- In Get-KBLink, made a change to just grab the first result returned instead of the entire results page. This removes the need to use a break statement in Save-KB when downloading updates. This fixed an issue with the new 24H2 Checkpoint Cumulative Updates in Win11 and Server 2025.
- Changed Windows MSRT search string for x64 and x86. This was mainly to get x64 to the top of the search results. x86 won't actually download since the code isn't in place for content from the MU Catalog to download x86 content (no idea if anyone actually builds x86 FFUs for Win10 - I hope not)
- If not passing an ISO, hardcoded WindowsVersion of 22H2 for Windows 10 or 24H2 for Windows 11 since the ESD media only provides those two versions. Not doing this allowed for unnecessary VHDX creation since it checks the WindowsVersion via the json file. This also fixes an issue where CUs could be searched for that didn’t exist, but the media would still download
- Added some additional logging entries
- Removed verbose output of the Optimize-Volume command
- Fixed an issue where not passing an ISO caused the script to fail
- Cleaned up the KBPath folder at the end of the run
- Changed some minor formatting items
- Added Get-Childprocesses function to return child processes of parent process
- Added a new -Wait boolean parameter to Invoke-Process function. This is to control whether Invoke-Process should wait in order to track stdout and stderr output. This is needed for processes that may hang, waiting for user input and there isn't a way to bypass (some Intel drivers provided by Dell leave dialog windows even when running silently)
  -Invoke-Process now returns process information (returns $cmd). This allows for process tracking when calling the function.
- Since Invoke-Process now returns the process information, also needed to add Out-Null to the majority of the Invoke-Process references to prevent Invoke-Process from writing to the terminal
- Refactored a lot of the Get-DellDrivers function due to inconsistencies with how driver extraction behaves between client and server devices. For client, /s /e seemed to work fine, but for server it would only extract the driver installer content and other dell related files, rather than the driver files themselves. We have since switched to using /s /drivers= which will extract the driver content. Not all drivers support /drivers= and may output some information to the terminal that looks like help documentation. If a driver doesn't support /drivers, the script falls back to using /s /e to do the extraction. If this doesn't work for you, you can always provide your own drivers that you manually download from Dell's website.
- Updated Malicious Software Removal Tool (MSRT) code to handle Windows Server
- Refactored the Get-ODTURL function to fix recent download issues. Also added some better error handling
- Moved the odtsetup.exe download to the FFUDevelopment folder and will clean it up after office has downloaded
  Updated parameter definition block to be alphabetized (not to be confused by the param block, which is not alphabetized)
- Added $PEDriversFolder script variable to the param block (for some reason it was missing)
- Added ConfigFile and ExportConfigFile parameters to support json config files
- Changed Version to 2412.1
- Modified vhdxCacheItem class to include $LogicalSectorSizeBytes
- Added new function Get-Parameters to help with new config and export config file functionality
- Fixed Get-MicrosoftDrivers function to not require the HTMLFILE COM object, which isn't available in Windows 11. It seems to be installed with Office, which is what was allowing downloads to work and masked the issue.
- Added long path support to prevent issues with oscdimg creating the Apps.iso.
- Fixed an issue where the $PEDriversFolder variable wasn't being used (instead $FFUDevelopment\PEDrivers was used)
- Created a new function New-FFUFileName - this works in conjunction with the new $CustomFFUNameTemplate. The function was needed to support both scenarios where $InstallApps is either $true or $false.
- Added new function Export-ConfigFile. When passing -ExportConfigFile 'Path\To\ConfigFile.json' the script will generate a parameter dump of all of the configured parameters
- Added driver folder validation to throw an error if spaces are detected in the folder name of the drivers folder (e.g. C:\FFUDevelopment\Drivers\Dell 3190). This is due to an issue with Dell drivers and their inability to handle paths with spaces consistently.
- Added back the Windows Security Platform update which grabs it from the web instead of the Microsoft update catalog
- Fixed an issue where the Drivers folder was being completely deleted instead of its sub-folders
- Removed the Requires -PSEdition Desktop. The script works with both Desktop and Core, so pwsh 7 is fine.
- Created a new config folder to hold config files. A new sample_default.json file is provided to show what the format looks like.
- You can now set the computername in the unattend.xml file where ever you want. Prior it required that the computername was the first component element.

## **2409.1**

### Fixes

- Fix an issue with removal of Defender/OneDrive/Edge after FFU is complete
- Migrate Winget downloads to use [Export-WingetPackage cmdlet](https://github.com/microsoft/winget-cli/blob/master/doc/specs/%23658%20-%20WinGet%20Download.md#winget-powershell-cmdlet) as per issue #50
- Add support for preview updates https://github.com/rbalsleyMSFT/FFU/pull/51 - thanks to @HedgeComp
- Refactor validation of Unattend/prefixes, PPKG, Autopilot to check for these files early in the process, similar to how we check for drivers
- Add better logging when unable to find HDD when applying FFU. Will inform to add WinPE drivers to Deployment Media if HDD not found.
- Remove ValidateScript on InstallDrivers and break it out in a validation block so -Make and -Model can be specified anywhere in the command line
- Add validation for VMHostIPAddress and VMSwtichName and inform the user if these don't match. Should prevent issues where the FFU isn't getting created.
- Removed installation of the Windows Security Platform Update as it has been removed from the MU Catalog. See issue #58
- Thanks to w0 for PR #54 to change the validation set for WindowsSKU
- Thanks to @zehadialam for PR #60 to fix an issue with Windows boot loader for certain devices where Windows Boot Manager is not the first boot entry after the FFU is applied.
- Thanks to @HedgeComp  for PR #64 and PR #65

## **2408.1**

### External Drive Support

Up until now, the USB build process has supported using drives identified by Windows as removable drives. Most USB sticks will identify as removable, however faster drives may show up as external hard disk media. You may also have a smaller, portable SSD drive that you'd like to use for imaging since these are typically much faster than regular USB 3.x thumb drives.

In adding this support, I do realize that there is potential for data loss for those that might have external hard drives attached to their machines.

To handle this, with help from [HedgeComp](https://github.com/HedgeComp), we've refactored the `Get-USBDrives` function. Two new variables have been created:

| Parameter                   | Type | Description                                                                                                                                                                                                                                                                                                                                    |
| --------------------------- | ---- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| AllowExternalHardDiskMedia  | Bool | If `$true`, will allow the use of media identified as External Hard Disk media via WMI class Win32_DiskDrive. Default is not defined.                                                                                                                                                                                                        |
| PromptExternalHardDiskMedia | Bool | If `$true` and AllowExternalHardDiskMedia is `$true`, the script will prompt to select which drive to use. When set to `$true`, only a single drive will be created. If `$false`, the script won't prompt for which external hard disk to use and can use multiple external hard disks, similar to how removable USB drives function. |

By default, this functionality won't effect previous USB drive creation behavior. However if you want to take advantage of the new functionality, set `-AllowExternalHardDiskMedia $true`

Fixes/misc

- Fixed a display issue where if multiple FFU files were in the FFU folder, the script wouldn't display which FFUs to choose from when running the script without -verbose. This will now display a table with the last modified date whether you run with the -verbose switch or not.
- Added start/end/duration time (thanks [HedgeComp](https://github.com/HedgeComp))
- Fixed an issue where deployment media wasn't prompting for a key to be pressed as expected
- Fixed an issue when creating the USB drive and the drive had a RAW partition style that clear-disk would generate an error
- Cleaned up some commented code
- Added Create-PEMedia.ps1 as a helper script to quickly generate Deploy or Capture media
- Fixed an issue with clean up of Defender/OneDrive/Edge
- Fixed an issue with the formatting of InstallAppsandSysprep.cmd file
- Updated parameter documentation in the script to include newly added parameters

## **2407.1**

This is another major release that includes:

* Initial ARM64 support
* Winget support

### ARM64 Support

To support the newly released Copilot+ PCs, we now support the creation and deployment of FFUs created with ARM64 media. There are some caveats to this:

* The -WindowsArch parameter must be set to ARM64 (by default this parameter is set to x64)
* If you do not pass -ISOPath with a path to the ARM64 ISO, it will download an ARM64 ESD file from the Media Creation Tool (which is about 7-8 months old now). ARM64 ISOs are available via VLSC, but are not available via Visual Studio Downloads (Yet - unknown if they will ever be made available).
* The host machine you're building the FFU from must be ARM64
* Office/M365 apps don't currently support installing the ARM64 native bits from an offline system. If you pass `-InstallOffice $true`  the script will change the value to false. You can install office after the fact when connected to the internet. I'm investigating this behavior and will issue a fix if/when this gets resolved. I still don't recommend building the FFU VM on the internet.
* The [Defender Updates Site](https://www.microsoft.com/en-us/wdsi/defenderupdates) provides download links for Defender definitions. The ARM link doesn't work for ARM64 and mpam-fe.exe fails to install. However there might be an undocumented ARM64 URL that may work. I've included it, but haven't tested it as I'm writing these notes. So we'll see if that works out.
* Drivers - Surface Laptop 7 and Pro 11 don't have ARM64 drivers available yet (there are entries, but they just point to a .txt file). Other OEMs may have drivers available.

In all, testing has gone very well.

### Winget Support

Big thanks to [Zehadi Alam](https://github.com/zehadialam) for his contributions to get this added to the project. You can now add any application in the msstore or winget source via the Winget command line utility. In the 1.8 Winget release the ability to download apps from the msstore source was added, which means being able to download apps like the Company Portal. For those of you that have been asking for Company Portal to be inbox in Windows, this is the next best thing. The script will check if Winget 1.8 is installed and if not, it'll install it.

The way this works is if `-InstallApps $true`  and the FFUDevelopment\Apps\AppList.json file exists, whatever apps defined in that json file will be downloaded via Winget and will be installed in the FFU VM prior to capture. We've included two files: AppList_InboxAppsSample.json and AppList_Sample.json. The AppList_InboxAppsSample.json contains all of the apps that are installed in Windows by default and are searchable via `winget search AppID` . Some of these apps do not download and we're investigating why they come up via search, but fail to download. The AppList_Sample.json has Company Portal and New Teams.

![1721678632154](image/ChangeLog/1721678632154.png)

In sticking with the idea of having the most up to date Windows build, inbox store/UWP apps are notoriously out of date and use a lot of bandwidth. By updating all of the UWP apps, bandwidth reductions of ~70% can be achieved.

|                                                                 | Total Data usage before updating store apps | Total Data usage after updating store apps | Total Data usage after updating Windows Update |
| --------------------------------------------------------------- | ------------------------------------------- | ------------------------------------------ | ---------------------------------------------- |
| July 2024 Windows 11 23H2 Stock ISO Captured as FFU (7.5GB FFU) | 261MB                                       | 1.82GB                                     | 2.09GB                                         |
| July 2024 Windows 11 23H2 Updated FFU (10.5GB)                  | 13MB                                        | 558MB                                      | 646MB                                          |

Updated means latest .NET, Defender (definition and platform updates), Edge, OneDrive, and all updates available via Winget for Store Apps have been provisioned in the FFU. The numbers in the table are cumulative, meaning the FFU was laid down, store apps were updated via running Get Apps from the Microsoft Store app and data usage was gathered from Settings, then Windows Update was manually kicked off via Settings and data usage was gathered.

In order to get apps to help build your AppList.json file, just run `winget search "AppName"`

![1721679421727](image/ChangeLog/1721679421727.png)

In this example we see that Firefox is published to both the msstore and winget sources. It's up to you which one you'd like to pick (I assume the msstore and the 128 version from the winget source are both the same version, but that may not be the case). You'll want to use the Name, ID, and Source values to help create your AppList.json file.

When downloading msstore apps, it does require an Entra ID. If you're building your FFUs from a machine that is not signed in with an Entra ID, you will be prompted for credentials for each app you download AND for the license file for each app (2 prompts per app). If downloading many store apps is something you plan on doing, I highly recommend signing in with an Entra ID to prevent the authentication prompts.

Other improvements

* [mhaley](https://github.com/mhaley) made their first contribution to [assign the drive letter to the recovery partition when copying in a custom WinRE.wim](https://github.com/rbalsleyMSFT/FFU/pull/35)
* [MKellyCBSD](https://github.com/MKellyCBSD) submitted a PR for a stand-alone USBImagingToolCreator.ps1 script which will create USB drives separate from the main BuildFUVM.ps1 script. This is helpful if you have technicans that need to build USB drives, or would like to make concurrent USB drives at the same time instead of one at a time. [His PR has all the details.](https://github.com/rbalsleyMSFT/FFU/pull/36)
* The WinPE_FFU_Deploy.iso will now work on VMs. This made ARM64 testing a lot easier :) If you're looking to test your FFU on a VM, you'll want to build a new VHDX and add your FFU to it and boot from the WinPE_FFU_Deploy.iso. Make sure to eject the VHDX before adding/booting the new VM. When attaching the new VHDX with your FFU on it, make sure it's not the first SCSI device (it should be 1 or 2, most likely 2 as 0 should be the hard drive you want to install Windows to, and 1 will be the DVD drive). By default the WinPE_FFU_Deploy.iso file is removed after the script completes. Make sure to set `-CreateDeploymentMedia $true` and `-CleanupDeployISO $false` so the ISO remains in the FFUDevelopment folder after the script completes.

  The below screenshot should help in understanding what the SCSI config should look like.

  ![1721681140638](image/ChangeLog/1721681140638.png)
* Cleaned up some old commented code from the ApplyFFU.ps1 file and other files.

## **2406.1**

This is a major release that includes the ability to download drivers from the 4 major OEMs (Microsoft, Dell, HP, Lenovo) by simply passing the -Make and -Model parameters to the command line.

For Dell, HP, and Lenovo, the script leverages a similar process to their corresponding tools that automate driver downloads (Dell SupportAssist, HP Image Assistant, Lenovo System Update/Update Retriever). For Microsoft Surface, it scrapes the Surface Downloads page for the appropriate MSI file to download. Using this method, the drivers that are downloaded will be the latest provided by the OEM, unlike other tools that download out of date enteprise CAB files that are made for ConfigMgr.

The script supports lookups using the -model parameter. For example, if you want to download the drivers for a Surface Laptop Go 3, but don't know the exact model name, you could set -Make 'Microsoft' -Model 'Laptop Go' and it'll give you a list of Surface devices to pick from. If you know the exact name, it'll use that and not prompt.

![FFU Build Command Line that includes -make 'Microsoft' and -model 'Laptop Go' demonstrating how to use the new parameters to download drivers](image/ChangeLog/image-1.png)

The goal here is to make it easy to discover the drivers you want to download without having to know the exact model names.

There are likely going to be bugs with this, but in my testing things seem to work well for the makes and models that I've tried. If you notice something, please fill out an issue in the repro and I'll take a look. If you want to fix whatever issue you're running into, submit a pull request.

### New parameters

| Parameter      | Type      | Description                                                                                                                                                                                                                                                                                                                               |
| -------------- | --------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Make           | String    | Used for automatically downloading drivers. Valid values are 'Microsoft', 'Dell', 'HP', 'Lenovo'. The script will throw an error if any other string value is used.                                                                                                                                                                       |
| Model          | String    | Used for automatically downloading drivers with the Make parameter.                                                                                                                                                                                                                                                                       |
| DriversFolder  | String    | Location where Drivers will either be downloaded, and/or the location of the drivers you wish to be added to the FFU, or copied to the deploy partition of the USB drive. The default location is $FFUDevelopmentPath\Drivers (e.g. C:\FFUDevelopmentPath\Drivers                                                                         |
| CleanupDrivers | Bool      | Used to delete the drivers folders underneath the `$DriversFolder` path (e.g. C:\FFUDevelopmentPath\Drivers\HP) after the FFU has been built. Default is `$true`true                                                                                                                                                                  |
| UserAgent      | String    | The useragent string is used when invoking Invoke-Webrequest or Invoke-RestMethod. This has been helpful when interacting with the Microsoft Download Center and preventing intermittent errors. Default is Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36 Edg/125.0.0.0 |
| Headers        | Hashtable | This hash table is used in conjunction with the Useragent when invoking Invoke-Webrequest or Invoke-RestMethod. This has been helpful when interacting with the Microsoft Download Center and preventing intermittent errors. If interested in the default value, reference the script itself.                                            |

### New Functions

### `Test-URL`

Simple function that accepts \$URL parameter to test if a URL is accessible.

### `Start-BitsTransferWithRetry`

This is simply Start-BITSTransfer with some retry logic and setting `$VerbosePreference` and `$ProgressPreference` to SilentlyContinue. The retry logic was needed due to certain driver files randomly failing to download. The function is hardcoded to retry 3 times before failing and will wait 5 seconds between each retry attempt.

### `Get-MicrosoftDrivers`

For Microsoft Surface, the driver files are hosted on the Microsoft download center. The script will scrape and parse the [Download Surface Drivers and Firmware](https://support.microsoft.com/en-us/surface/download-drivers-and-firmware-for-surface-09bb2e09-2a4b-cb69-0951-078a7739e120) page to get the latest list of Surface devices.

This function accepts -Make, -Model, and -WindowsRelease parameters. Make and Model are both string parameters and WindowsRelease is an integer parameter. If the model parameter doesn't contain an exact match of a known Surface model, it'll give you a list of Surface models to pick from.

The following command line says that we want to download the drivers for a Microsoft Laptop Go for Windows 10.

`.\BuildFFUVM.ps1 -make 'Microsoft' -model 'Laptop Go' -WindowsSKU 'Pro' -Installapps $true -InstallOffice $true -InstallDrivers $true -VMSwitchName 'external' -VMHostIPAddress '192.168.1.158' -CreateDeploymentMedia $true -BuildUSBDrive $true -UpdateLatestCU $true -UpdateLatestNet $true -UpdateLatestDefender $true -UpdateEdge $true -UpdateOneDrive $true -verbose -RemoveFFU $true -WindowsRelease 10`

![Screenshot of the FFU script displaying a list of Surface models to download drivers for](image/ChangeLog/1718826099739.png)

If you want to build an FFU for Surface Laptop Go 3, enter 18 and it'll download the MSI and extract the drivers to the .\FFUDevelopment\Drivers\Microsoft\Surface Laptop Go 3 folder.

If you would have provided the exact model string instead of just Laptop Go (e.g. -Model 'Surface Laptop Go 3'), the script wouldn't prompt you to enter a valid model.

### `Get-HPDrivers`

For HP, the script uses the same process as the HP Image Assistant tool to automate the downloading of drivers. This function accepts the -Make, -Model, -WindowsArch, -WindowsRelease, and -WindowsVersion parameters. HP is the only vendor that uses -WindowsVersion (e.g. 23h2) for its drivers. This is because their XML files contain the -WindowsVersion value in the file name. By default, the script uses 23h2 for the -WindowsVersion parameter. You can override that for whatever -WindowsVersion you wish to use.

The following command line says that we want to download HP x360 drivers for Windows 10 version 22h2.

`.\BuildFFUVM.ps1 -make 'HP' -model 'x360' -WindowsSKU 'Pro' -Installapps $true -InstallOffice $true -InstallDrivers $true -VMSwitchName 'external' -VMHostIPAddress '192.168.1.158' -CreateDeploymentMedia $true -CreateCaptureMedia $true -BuildUSBDrive $true -UpdateLatestCU $true -UpdateLatestNet $true -UpdateLatestDefender $true -UpdateEdge $true -UpdateOneDrive $true -RemoveFFU $true -WindowsRelease 10 -WindowsVersion '22h2' -Verbose`

![Screenshot of the output of running the above command to download HP x360 drivers](image/ChangeLog/1718824392698.png)

HP has 40 models that contain the string x360 in the model name. I want to select the HP ProBook x360 11 G7 Education Edition Notebook PC which is number 25. The below screenshot shows the output of selecting the HP ProBook x360 11 G7 Education Edition Notebook PC

![Screenshot of the script downloading drivers for an HP ProBook x360 11 G7 Education Edition Notebook PC](image/ChangeLog/1718824500798.png)

If you were to enter the exact model name (e.g. -model 'HP ProBook x360 11 G7 Education Edition Notebook PC'), the script wouldn't prompt you to select from a list of models.

### `Get-LenovoDrivers`

For Lenovo, the script uses the same process Lenovo System Update/Update Retriever use. It uses the Get-LenovoDrivers function which accepts -Model, -WindowsArch, -WindowsRelease parameters.

Lenovo as a company doesn't use model like other companies do. Lenovo prefers to use a Machine Type value instead of Model number. The Machine Type value can be found on the bottom of your device as the first four characters of the MTM: value. Since most people don't know what the machine type value is, when passing the -model parameter, you can pass either the machine type or the "friendly" model number.

The following command line says that we want to download Lenovo 500w drivers for Windows 10.

`.\BuildFFUVM.ps1 -make 'Lenovo' -model '500w' -WindowsSKU 'Pro' -Installapps $true -InstallOffice $true -InstallDrivers $true -VMSwitchName 'external' -VMHostIPAddress '192.168.1.158' -CreateDeploymentMedia $true -BuildUSBDrive $true -UpdateLatestCU $true -UpdateLatestNet $true -UpdateLatestDefender $true -UpdateEdge $true -UpdateOneDrive $true -RemoveFFU $true -WindowsRelease 10 -Verbose`

The script will go out to the [Lenovo PSREF](https://psref.lenovo.com/search) page to figure out the Machine Type value and if multiple Machine Types are found (there are usually multiples found for different configuration types).

![A screenshot of the different models and their machine types found from the Lenovo PSREF page and a selection prompt for the end user to pick which machine type they wish to use](image/ChangeLog/1718824806444.png)

The Machine Type is the value in parenthesis. On the bottom of my device, the MTM value is MTM:**82VR**ZAKXXX. I would want to pick number 4 from the list since it includes (82VR). The below screenshot shows the script downloading the appropriate drivers for a Lenovo 500w.

![The output of the script downloading Lenovo drivers](image/ChangeLog/1718824932640.png)

If you use the Machine Type value for the -Model parameter (e.g. -model '82VR') the script will automatically download the drivers without prompting you to select the model.

### `Get-DellDrivers`

For Dell, the script uses the [Dell CatalogPC Cab file](http://downloads.dell.com/catalog/CatalogPC.cab) which is used in Dell Support Assist and possibly other Dell tools to download drivers. The cab consists of an XML file that the script parses to search for drivers applicable for the model you wish to create a FFU for.

The script calls the Get-DellDrivers function which accepts the -Model and -WindowsArch parameters.

Unlike Microsoft Surface drivers, Dell doesn't give a list to pick from when the -model parameter isn't an exact match. This is due to how the CatalogPC XML file lists drivers. It treats the driver as the primary element and lists what models that driver can be installed on.

The following command line says that we want to download Dell 3190 drivers for Windows 10.

`.\BuildFFUVM.ps1 -make 'Dell' -model '3190' -WindowsSKU 'Pro' -Installapps $true -InstallOffice $true -InstallDrivers $true -VMSwitchName 'external' -VMHostIPAddress '192.168.1.158' -CreateDeploymentMedia $true -CreateCaptureMedia $true -BuildUSBDrive $true -UpdateLatestCU $true -UpdateLatestNet $true -UpdateLatestDefender $true -UpdateEdge $true -UpdateOneDrive $true -RemoveFFU $true -WindowsRelease 10 -Verbose`

The script will find every driver that is tagged with 3190 and download the latest available version. It strips out any firmware or other non-driver file types. You may notice that it will download multiple video or audio drivers. This is due to each model having variants with different video cards or other hardware. This would make the FFU a bit larger, but not excessively so.

Below is a screenshot of what the verbose output of the script looks like when downloading the drivers for a Dell 3190.

![a screenshot of what the verbose output of the script looks like when downloading the drivers for a Dell 3190](image/ChangeLog/1718825319847.png)

* Added -Headers \$Headers -UserAgent \$UserAgent to most Invoke-Webrequest or Invoke-RestMethod commands to solve for intermittent download failures when downloading drivers or Office
* Fixed some minor logging issues
* Updated the BuildDeployFFU.docx with new driver information and cleaned up some sections that were out of date
* Added Changelog.md to keep track of changes and not clutter up the readme.md

## **2405.1**

- Moved the resetbase command from within the VM to after servicing the VHDX. This will make it so the FFU size is smaller after the latest CU or .NET framework are installed. (Thanks to Mike Kelly for the PR [Commit](https://github.com/rbalsleyMSFT/FFU/pull/24))
- Some additional FFU size reduction enhancements (Thanks Zehadi Alam [Commit](https://github.com/rbalsleyMSFT/FFU/pull/25)):
  - Disk cleanup is now run before sysprep to help reduce FFU file size
  - Before FFU capture, Optimize-FFU is run to defrag and slabconsolidate the VHDX

## **2404.3**

- Fixed an issue where the latest Windows CU wasn't downloading properly [Commit](https://github.com/rbalsleyMSFT/FFU/commit/ae59183a199f39b310c79b31c9b4980fafdeb79b)

## **2404.2**

- If setting `-installdrivers to $true` and `-logicalsectorsizebytes to 4096`, the script will now set `$copyDrivers to $true`. This will create a drivers folder on the deploy partition of the USB drive with the drivers that were supposed to be added to the FFU. There's currently a bug with servicing FFUs with 4096 logical sector byte sizes. Prior to this fix, the script would tell the user to manually set `-copydrivers to $true` as workaround. This fix just does the workaround automatically.

## **2404.1**

There's a big change with this release related to the ADK. The ADK will now be automatically updated to the latest ADK release. This is required in order to fix an issue with optimized FFUs not applying due to an issue with DISM/FFUProvider.dll. The FFUProvider.dll fix was added to the Sept 2023 ADK. Since we now have the ability to auto upgrade the ADK, I'm more confident in having the BuildFFUVM script creating a complete FFU now (prior it was only creating 3 partitions instead of 4 with the recovery partition - at deployment time, the ApplyFFU.ps1 script would create an empty recovery partition and Windows would populate it on first boot). Please open an issue if this creates a problem for you. I do realize that any new ADK release can have it's own challenges and issues and I do suspect we'll see a new ADK released later this year.

- Allow for ISOs with single index WIMs to work [Issue 10](https://github.com/rbalsleyMSFT/FFU/issues/10) - [Commit](https://github.com/rbalsleyMSFT/FFU/commit/9e2da741d53652e6e600ca19cfd38f507bd01fde)
- Added more robust ADK handling. Will now check for the latest ADK and download it if not installed. Thanks to [Zehadi Alam](https://github.com/zehadialam) [PR 18](https://github.com/rbalsleyMSFT/FFU/pull/18)
- Revert code back to allow optimized FFUs to be applied via ApplyFFU.ps1 now that Sept 2023 ADK release has FFUProvider.dll fix. [Commit](https://github.com/rbalsleyMSFT/FFU/commit/79364e334d6d09ff150e70dab7bfb2637d0ad8a8)
- Changed how the script searches for the latest CU. Instead of relying on the Windows release info page to grab the KB number, will just use the MU Catalog, the same as what we do for the .NET Framework. Windows release info page is updated manually and is unknown as to when it will be updated. [Commit](https://github.com/rbalsleyMSFT/FFU/commit/6fd5a4a41fd9ce2f842f43dc3a69bda264c29fa6)
- Added fix to not allow computer names with spaces. Thanks to [JoeMama54 (Rob)](https://github.com/JoeMama54) [PR 20](https://github.com/rbalsleyMSFT/FFU/pull/20)

## **2403.1**

Fixed an issue with the SecurityHealthSetup.exe file giving an error when building the VM if -UpdateLatestDefender was set to $true. A new update for this came out on 3/21 which included a x64 and ARM64 binary. This file doesn't have an architecture designation to it, so it's impossible to know which file is for which architecture. Investigating to see if we can fix this in the Microsoft Update catalog. There is a web site to pull this from, but the support article is out of date.

Included ADK functions from Zehadi Alam [Introduce Automated ADK Retrieval and Installation Functions #14](https://github.com/rbalsleyMSFT/FFU/pull/14) to automate the installation of the ADK if it's not present. Thanks, Zehadi!

## **2402.1**

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

## **2401.1**

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

## **2309.2**

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

## **2309.1**

- Fixed an issue with a Critical Process Died BSOD that would happen when using -installapps $false. More detailed information in the [commit](https://github.com/rbalsleyMSFT/FFU/pull/2/commits/34efbda7ec56dc7cb43ac42b058725d56c8b8899)

## **2306.1.2**

- Fixed an issue where manually entering a name wouldn't name the computer as expected

## **2306.1.1**

- Included some better error handling if defining optionalfeatures that require source folders (netfx3). ESD files don't have source folders like ISO media, which means installing .net 3.5 as an optional feature would fail. Also cleaned up some formatting.

## **2306.1**

- Added support to automatically download the latest Windows 10 or 11 media via the media creation tool (thanks to [Michael](https://oofhours.com/2022/09/14/want-your-own-windows-11-21h2-arm64-isos/) for the idea). This also allows for different architecture, language, and media type support. If you omit the -ISOPath, the script will download the Windows 11 x64 English (US) consumer media.

  An example command to download Windows 11 Pro x64 English (US) consumer media with Office and install drivers (it won't download drivers, you'll put those in your c:\FFUDevelopment\Drivers folder)

  .\BuildFFUVM.ps1 -WindowsSKU 'Pro' -Installapps $true -InstallOffice $true -InstallDrivers $true -VMSwitchName 'Name of your VM Switch in Hyper-V' -VMHostIPAddress 'Your IP Address' -CreateCaptureMedia $true -CreateDeploymentMedia $true -BuildUSBDrive $true -verbose

  An example command to download Windows 11 Pro x64 French (CA) consumer media with Office and install drivers

  .\BuildFFUVM.ps1 -WindowsSKU 'Pro' -Installapps $true -InstallOffice $true -InstallDrivers $true -VMSwitchName 'Name of your VM Switch in Hyper-V' -VMHostIPAddress 'Your IP Address' -CreateCaptureMedia $true -CreateDeploymentMedia $true -BuildUSBDrive $true -WindowsRelease 11 -WindowsArch 'x64' -WindowsLang 'fr-ca' -MediaType 'consumer' -verbose
- Changed default size of System/EFI partition to 260MB from 256MB to accomodate 4Kn drives. 4Kn support needs more testing. I'm not confident yet that this can be done with VMs and FFUs.
- Added versioning with a new version parameter. Using YYMM as the format followed by a point release.
