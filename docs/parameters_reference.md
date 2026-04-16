---
title: Parameters Reference
nav_order: 1
parent: Reference
prev_url: /reference.html
prev_label: Reference
---
# BuildFFUVM.ps1 Parameter Reference

This table lists all top-level parameters in BuildFFUVM.ps1.

<style>
.parameters-reference-table th:first-child,
.parameters-reference-table td:first-child {
    white-space: nowrap;
}
</style>

| Parameter | Type | UI Control | Description |
| --- | --- | --- | --- |
| -AdditionalFFUFiles | string[] | Copy Additional FFU Files + Additional FFU Files list | Array of full file paths to existing FFU files that should also be copied to the deployment USB when -CopyAdditionalFFUFiles is set to $true. |
| -AllowExternalHardDiskMedia | bool | Allow External Hard Disk Media | When set to $true, will allow the use of media identified as External Hard Disk media via WMI class Win32_DiskDrive. Default is not defined. |
| -AllowVHDXCaching | bool | Allow VHDX Caching | When set to $true, will cache the VHDX file to the $FFUDevelopmentPath\VHDXCache folder and create a config json file that will keep track of the Windows build information, the updates installed, and the logical sector byte size information. Default is $false. |
| -AppListPath | string | AppList.json Path | Path to a JSON file containing a list of applications to install using WinGet. Default is $FFUDevelopmentPath\Apps\AppList.json. |
| -AppsScriptVariables | hashtable | Define Apps Script Variables + Apps Script Variables list | When passed a hashtable, the script will create an AppsScriptVariables.json file in the OrchestrationPath. This file will be used to pass variables to the Apps script. The hashtable should contain key-value pairs where the key is the variable name and the value is the variable value. |
| -BitsPriority | string | BITS Priority | BITS transfer priority used for downloads. Accepted values are 'Foreground', 'High', 'Normal', and 'Low'. Default is 'Normal'. |
| -BuildUSBDrive | bool | Build USB Drive | When set to $true, will partition and format a USB drive and copy the captured FFU to the drive. |
| -Cleanup | switch | Monitor cancel build action (no direct control) | Switch to run cleanup-only mode. When specified, the script performs cleanup and exits without starting a new build. |
| -CleanupAppsISO | bool | Cleanup Apps ISO | When set to $true, will remove the Apps ISO after the FFU has been captured. Default is $true. |
| -CleanupCurrentRunDownloads | bool | Monitor cancel prompt option (no direct control) | When set to $true, cleanup mode will remove downloads created during the current run and restore backed up run JSON files. Default is $false. |
| -CleanupDeployISO | bool | Cleanup Deploy ISO | When set to $true, will remove the WinPE deployment ISO after the FFU has been captured. Default is $true. |
| -CleanupDrivers | bool | Cleanup Drivers | When set to $true, will remove the drivers folder after the FFU has been captured. Default is $true. |
| -CompactOS | bool | Compact OS | When set to $true, will compact the OS when building the FFU. Default is $true. |
| -CompressDownloadedDriversToWim | bool | Compress Driver Model Folder to WIM | When set to $true, compresses downloaded drivers into a WIM file. Default is $false. |
| -ConfigFile | string | Load Config File | Path to a JSON file containing parameters to use for the script. Default is $null. |
| -CopyAdditionalFFUFiles | bool | Copy Additional FFU Files | When set to $true, enables copying additional FFU files from $FFUDevelopmentPath\FFU to the deployment USB alongside the current build output. |
| -CopyAutopilot | bool | Copy Autopilot Profile | When set to $true, will copy the $FFUDevelopmentPath\Autopilot folder to the Deployment partition of the USB drive. Default is $false. |
| -CopyDrivers | bool | Copy Drivers to USB drive | When set to $true, will copy the drivers from the $FFUDevelopmentPath\Drivers folder to the Drivers folder on the deploy partition of the USB drive. Default is $false. |
| -CopyPEDrivers | bool | Copy PE Drivers | When set to $true, enables adding WinPE drivers. By default copies drivers from $FFUDevelopmentPath\PEDrivers to the WinPE deployment media unless -UseDriversAsPEDrivers is also $true. |
| -CopyPPKG | bool | Copy Provisioning Package | When set to $true, will copy the provisioning package from the $FFUDevelopmentPath\PPKG folder to the Deployment partition of the USB drive. Default is $false. |
| -CopyUnattend | bool | Copy Unattend.xml | When set to $true, stages the selected architecture-specific unattend XML file as Unattend.xml on the Deployment partition of the USB drive. Cannot be used together with -InjectUnattend. Default is $false. |
| -CreateDeploymentMedia | bool | Create Deployment Media | When set to $true, this will create WinPE deployment media for use when deploying to a physical device. |
| -CustomFFUNameTemplate | string | Custom FFU Name Template | Sets a custom FFU output name with placeholders. Allowed placeholders are: {WindowsRelease}, {WindowsVersion}, {SKU}, {BuildDate}, {yyyy}, {MM}, {dd}, {H}, {hh}, {mm}, {tt}. |
| -DeviceNamePrefixes | string[] | Specify a list of Prefixes | Sets the prefixes used when DeviceNamingMode is Prefixes. Each entry becomes a line in prefixes.txt on the deployment media. |
| -DeviceNamePrefixesPath | string | Prefixes File Path | Path to the source prefixes file used for legacy copy or when -DeviceNamePrefixes is not supplied. Default is $FFUDevelopmentPath\Unattend\prefixes.txt. |
| -DeviceNameSerialComputerNames | string[] | Specify Serial to Device Name Mapping | Sets the CSV content used when DeviceNamingMode is SerialComputerNames. The content must include SerialNumber and ComputerName headers, and the staged file is written as SerialComputerNames.csv on the deployment media. |
| -DeviceNameSerialComputerNamesPath | string | Serial Computer Names CSV Mapping File Path | Path to the source CSV file used when DeviceNamingMode is SerialComputerNames and -DeviceNameSerialComputerNames is not supplied. Default is $FFUDevelopmentPath\Unattend\SerialComputerNames.csv. |
| -DeviceNameTemplate | string | Specify Device Name | Sets the device name used when DeviceNamingMode is Template. Supports a static name or the %serial% token when -CopyUnattend is used. |
| -DeviceNamingMode | string | Device Naming expander | Controls how device naming is handled when unattend content is copied to USB media or injected into the FFU. Accepted values are Legacy, None, Prompt, Template, Prefixes, and SerialComputerNames. The UI shows None, Prompt, Template, Prefixes, and SerialComputerNames. When device naming is left untouched in the UI, the generated config does not write DeviceNamingMode, which preserves the script default of Legacy. Prompt rewrites the staged deployment unattend to the existing manual prompt placeholder and requires -CopyUnattend. Prefixes writes prefixes.txt and requires -CopyUnattend. SerialComputerNames writes SerialComputerNames.csv and requires -CopyUnattend. |
| -Disksize | uint64 | Disk Size (GB) | Size of the virtual hard disk for the virtual machine. Default is a 50GB dynamic disk. |
| -DriversFolder | string | Drivers Folder | Path to the drivers folder. Default is $FFUDevelopmentPath\Drivers. |
| -DriversJsonPath | string | Drivers.json Path | Path to a JSON file that specifies which drivers to download. |
| -EnableVMNetworking | bool | Enable VM Networking (Experimental) | When set to $true, connects the build VM to the selected Hyper-V switch during provisioning. Default is $false because internet-connected Sysprep is experimental. |
| -ExportConfigFile | string | Save Config File | Path to a JSON file to export the parameters used for the script. |
| -FFUCaptureLocation | string | FFU Capture Location | Path to the folder where the captured FFU will be stored. Default is $FFUDevelopmentPath\FFU. |
| -FFUDevelopmentPath | string | FFU Development Path | Path to the FFU development folder. Default is $PSScriptRoot. |
| -FFUPrefix | string | VM Name Prefix | Prefix for the generated FFU file. Default is _FFU. |
| -Headers | hashtable | CLI only (no UI control) | Headers to use when downloading files. Not recommended to modify. |
| -InjectUnattend | bool | Inject Unattend.xml | When set to $true and InstallApps is also $true, stages the selected architecture-specific unattend XML file to $FFUDevelopmentPath\Apps\Unattend\Unattend.xml so sysprep can use it inside the VM. Cannot be used together with -CopyUnattend. Default is $false. |
| -InstallApps | bool | Install Applications | When set to $true, the script will create an Apps.iso file from the $FFUDevelopmentPath\Apps folder. It will also create a VM, mount the Apps.iso, install the apps, sysprep, and capture the VM. When set to $false, the FFU is created from a VHDX file, and no VM is created. |
| -InstallDrivers | bool | Install Drivers to FFU | Install device drivers from the specified $FFUDevelopmentPath\Drivers folder if set to $true. Download the drivers and put them in the Drivers folder. The script will recurse the drivers folder and add the drivers to the FFU. |
| -InstallOffice | bool | Install Office | Install Microsoft Office if set to $true. The script will download the latest ODT and Office files in the $FFUDevelopmentPath\Apps\Office folder and install Office in the FFU via VM. |
| -ISOPath | string | Windows ISO Path | Path to the Windows 10/11 ISO file. |
| -LogicalSectorSizeBytes | uint32 | Logical Sector Size | UInt32 value of 512 or 4096. Useful for 4Kn drives or devices shipping with UFS drives. Default is 512. |
| -Make | string | Make | Make of the device to download drivers. Accepted values are: 'Microsoft', 'Dell', 'HP', 'Lenovo'. |
| -MaxUSBDrives | int | Max USB Drives | Maximum number of USB drives to build in parallel. Default is 5. Set to 0 to process all discovered drives (or all selected drives when USBDriveList or selection is used). Actual throttle will never exceed the number of drives discovered. |
| -MediaType | string | Media Type | String value of either 'business' or 'consumer'. This is used to identify which media type to download. Default is 'consumer'. |
| -Memory | uint64 | Memory (GB) | Amount of memory to allocate for the virtual machine. Recommended to use 8GB if possible, especially for Windows 11. Default is 4GB. |
| -Model | string | Driver Models list | Model of the device to download drivers. This is required if Make is set. |
| -OfficeConfigXMLFile | string | Office Configuration XML File | Path to a custom Office configuration XML file to use for installation. |
| -Optimize | bool | Optimize | When set to $true, will optimize the FFU file. Default is $true. |
| -OptionalFeatures | string | Optional Features | Provide a semicolon-separated list of Windows optional features you want to include in the FFU (e.g., netfx3;TFTP). |
| -OrchestrationPath | string | Application Path (derived Orchestration path) | Path to the orchestration folder containing scripts that run inside the VM. Default is $FFUDevelopmentPath\Apps\Orchestration. |
| -PEDriversFolder | string | PE Drivers Folder | Path to the folder containing drivers to be injected into the WinPE deployment media. Default is $FFUDevelopmentPath\PEDrivers. |
| -Processors | int | Processors | Number of virtual processors for the virtual machine. Recommended to use at least 4. |
| -ProductKey | string | Product Key | Product key for the Windows edition specified in WindowsSKU. This will overwrite whatever SKU is entered for WindowsSKU. Recommended to use if you want to use a MAK or KMS key to activate Enterprise or Education. If using VL media instead of consumer media, you'll want to enter a MAK or KMS key here. |
| -PromptExternalHardDiskMedia | bool | Prompt for External Hard Disk Media | When set to $true, will prompt the user to confirm the use of media identified as External Hard Disk media via WMI class Win32_DiskDrive. Default is $true. |
| -RemoveApps | bool | Remove Apps Folder Content | When set to $true, will remove the application content in the Apps folder after the FFU has been captured. Default is $true. |
| -RemoveDownloadedESD | bool | Remove Downloaded ESD file(s) | When set to $true, downloaded Windows ESD files are automatically deleted after they have been applied. Default is $true. |
| -RemoveFFU | bool | Remove FFU | When set to $true, will remove the FFU file from the $FFUDevelopmentPath\FFU folder after it has been copied to the USB drive. Default is $false. |
| -RemoveUpdates | bool | Remove Downloaded Update Files | When set to $true, will remove the downloaded CU, MSRT, Defender, Edge, OneDrive, and .NET files downloaded. Default is $true. |
| -Threads | int | Threads | Controls the throttle applied to parallel tasks inside the script. Default is 5, matching the UI Threads field, and applies to driver downloads invoked through Invoke-ParallelProcessing. |
| -UnattendArm64FilePath | string | arm64 Unattend File Path | Path to the arm64 unattend XML source file used by Copy Unattend.xml and Inject Unattend.xml. Default is $FFUDevelopmentPath\Unattend\unattend_arm64.xml. |
| -UnattendX64FilePath | string | x64 Unattend File Path | Path to the x64 unattend XML source file used by Copy Unattend.xml and Inject Unattend.xml. Default is $FFUDevelopmentPath\Unattend\unattend_x64.xml. |
| -UpdateADK | bool | Update ADK | When set to $true, the script will check for and install the latest Windows ADK and WinPE add-on if they are not already installed or up-to-date. Default is $true. |
| -UpdateEdge | bool | Update Edge | When set to $true, will download and install the latest Microsoft Edge. Default is $false. |
| -UpdateLatestCU | bool | Update Latest Cumulative Update | When set to $true, will download and install the latest cumulative update. Default is $false. |
| -UpdateLatestDefender | bool | Update Defender | When set to $true, will download and install the latest Windows Defender definitions and Defender platform update. Default is $false. |
| -UpdateLatestMicrocode | bool | Update Latest Microcode (for LTSC/Server 2016/2019) | When set to $true, will download and install the latest microcode updates for applicable Windows releases (e.g., Windows Server 2016/2019, Windows 10 LTSC 2016/2019) into the FFU. Default is $false. |
| -UpdateLatestMSRT | bool | Update Microsoft Software Removal Tool (MSRT) | When set to $true, will download and install the latest Windows Malicious Software Removal Tool. Default is $false. |
| -UpdateLatestNet | bool | Update .NET | When set to $true, will download and install the latest .NET Framework. Default is $false. |
| -UpdateOneDrive | bool | Update OneDrive (Per-Machine) | When set to $true, will download and install the latest OneDrive and install it as a per-machine installation instead of per-user. Default is $false. |
| -UpdatePreviewCU | bool | Update Preview Cumulative Update | When set to $true, will download and install the latest Preview cumulative update. Default is $false. |
| -USBDriveList | hashtable | USB Drives list | A hashtable containing USB drives from win32_diskdrive where:<br>- Key: USB drive model name (partial match supported)<br>- Value: USB drive UniqueId string, or an array of UniqueIds (to support selecting multiple drives with the same model)<br><br>Examples:<br>@{ "SanDisk Ultra" = "1234567890" }<br>@{ "SanDisk Ultra" = @("1234567890", "ABCDEFG"); "Kingston DataTraveler" = "0987654321" } |
| -UseDriversAsPEDrivers | bool | Use Drivers Folder as PE Drivers Source | When set to $true (and -CopyPEDrivers is also $true), bypasses the contents of $FFUDevelopmentPath\PEDrivers and instead builds the WinPE driver set dynamically from the $DriversFolder path, copying only the required WinPE drivers. Has no effect if -CopyPEDrivers is not specified. Default is $false. |
| -UserAgent | string | CLI only (no UI control) | User agent string to use when downloading files. |
| -UserAppListPath | string | Application Path (derived UserAppList.json) | Path to a JSON file containing a list of user-defined applications to install. Default is $FFUDevelopmentPath\Apps\UserAppList.json. |
| -VMLocation | string | VM Location | Default is $FFUDevelopmentPath\VM. This is the location of the VHDX that gets created where Windows will be installed to. |
| -VMSwitchName | string | VM Switch Name + Custom VM Switch Name (when Other selected) | Name of the Hyper-V virtual switch used when -EnableVMNetworking is set to $true. |
| -WindowsArch | string | Windows Architecture | String value of 'x86', 'x64', or 'arm64'. This is used to identify which architecture of Windows to download. Default is 'x64'. |
| -WindowsLang | string | Windows Language | String value in language-region format (e.g., 'en-us'). This is used to identify which language of media to download. Default is 'en-us'. |
| -WindowsRelease | int | Windows Release | Integer value of 10, 11, 2016, 2019, 2021, 2022, 2024, or 2025. This is used to identify which Windows client/LTSC/server release to use. Default is 11. |
| -WindowsSKU | string | Windows SKU | Edition/SKU to install. Accepted values are: 'Home', 'Home N', 'Home Single Language', 'Education', 'Education N', 'Pro', 'Pro N', 'Pro Education', 'Pro Education N', 'Pro for Workstations', 'Pro N for Workstations', 'Enterprise', 'Enterprise N', 'Enterprise 2016 LTSB', 'Enterprise N 2016 LTSB', 'Enterprise LTSC', 'Enterprise N LTSC', 'IoT Enterprise LTSC', 'IoT Enterprise N LTSC', 'Standard', 'Standard (Desktop Experience)', 'Datacenter', 'Datacenter (Desktop Experience)'. |
| -WindowsVersion | string | Windows Version | String value of the Windows version to download. This is used to identify which version of Windows to download. Default is '25h2'. |
{: .parameters-reference-table }

{% include page_nav.html %}