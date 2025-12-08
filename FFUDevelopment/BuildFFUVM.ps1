
#Requires -Modules Hyper-V, Storage
#Requires -RunAsAdministrator

# Import FFU.Constants module for centralized configuration
# IMPORTANT: using module (not Import-Module) is required here because FFUConstants class
# is referenced in the Param block (lines 311, 314, 317) which is evaluated at PARSE time.
# Import-Module loads at RUNTIME (too late for Param block).
using module .\Modules\FFU.Constants\FFU.Constants.psm1

<#
.SYNOPSIS
A PowerShell script to create a Windows 10/11 FFU file. 

.DESCRIPTION
This script creates a Windows 10/11 FFU and USB drive to help quickly get a Windows device reimaged. FFU can be customized with drivers, apps, and additional settings. 

.PARAMETER AllowExternalHardDiskMedia
When set to $true, will allow the use of media identified as External Hard Disk media via WMI class Win32_DiskDrive. Default is not defined.

.PARAMETER AllowVHDXCaching
When set to $true, will cache the VHDX file to the $FFUDevelopmentPath\VHDXCache folder and create a config json file that will keep track of the Windows build information, the updates installed, and the logical sector byte size information. Default is $false.

.PARAMETER AppListPath
Path to a JSON file containing a list of applications to install using WinGet. Default is $FFUDevelopmentPath\Apps\AppList.json.

.PARAMETER AppsScriptVariables
When passed a hashtable, the script will create an AppsScriptVariables.json file in the OrchestrationPath. This file will be used to pass variables to the Apps script. The hashtable should contain key-value pairs where the key is the variable name and the value is the variable value.

.PARAMETER BuildUSBDrive
When set to $true, will partition and format a USB drive and copy the captured FFU to the drive. 

.PARAMETER CleanupAppsISO
When set to $true, will remove the Apps ISO after the FFU has been captured. Default is $true.

.PARAMETER CleanupCaptureISO
When set to $true, will remove the WinPE capture ISO after the FFU has been captured. Default is $true.

.PARAMETER CleanupDeployISO
When set to $true, will remove the WinPE deployment ISO after the FFU has been captured. Default is $true.

.PARAMETER CleanupDrivers
When set to $true, will remove the drivers folder after the FFU has been captured. Default is $true.

.PARAMETER CompactOS
When set to $true, will compact the OS when building the FFU. Default is $true.

.PARAMETER CompressDownloadedDriversToWim
When set to $true, compresses downloaded drivers into a WIM file. Default is $false.

.PARAMETER ConfigFile
Path to a JSON file containing parameters to use for the script. Default is $null.

.PARAMETER CopyAutopilot
When set to $true, will copy the $FFUDevelopmentPath\Autopilot folder to the Deployment partition of the USB drive. Default is $false.

.PARAMETER CopyDrivers
When set to $true, will copy the drivers from the $FFUDevelopmentPath\Drivers folder to the Drivers folder on the deploy partition of the USB drive. Default is $false.

.PARAMETER CopyPEDrivers
When set to $true, enables adding WinPE drivers. By default copies drivers from $FFUDevelopmentPath\PEDrivers to the WinPE deployment media unless -UseDriversAsPEDrivers is also $true.

.PARAMETER CopyPPKG
When set to $true, will copy the provisioning package from the $FFUDevelopmentPath\PPKG folder to the Deployment partition of the USB drive. Default is $false.

.PARAMETER CopyUnattend
When set to $true, will copy the $FFUDevelopmentPath\Unattend folder to the Deployment partition of the USB drive. Default is $false.

.PARAMETER CreateCaptureMedia
When set to $true, this will create WinPE capture media for use when $InstallApps is set to $true. This capture media will be automatically attached to the VM, and the boot order will be changed to automate the capture of the FFU.

.PARAMETER CreateDeploymentMedia
When set to $true, this will create WinPE deployment media for use when deploying to a physical device.

.PARAMETER CustomFFUNameTemplate
Sets a custom FFU output name with placeholders. Allowed placeholders are: {WindowsRelease}, {WindowsVersion}, {SKU}, {BuildDate}, {yyyy}, {MM}, {dd}, {H}, {hh}, {mm}, {tt}.

.PARAMETER Disksize
Size of the virtual hard disk for the virtual machine. Default is a 50GB dynamic disk.

.PARAMETER DriversFolder
Path to the drivers folder. Default is $FFUDevelopmentPath\Drivers.

.PARAMETER DriversJsonPath
Path to a JSON file that specifies which drivers to download.

.PARAMETER ExportConfigFile
Path to a JSON file to export the parameters used for the script.

.PARAMETER FFUCaptureLocation
Path to the folder where the captured FFU will be stored. Default is $FFUDevelopmentPath\FFU.

.PARAMETER FFUDevelopmentPath
Path to the FFU development folder. Default is C:\FFUDevelopment.

.PARAMETER FFUPrefix
Prefix for the generated FFU file. Default is _FFU.

.PARAMETER Headers
Headers to use when downloading files. Not recommended to modify.

.PARAMETER InjectUnattend
When set to $true and InstallApps is also $true, copies unattend_[arch].xml from $FFUDevelopmentPath\unattend to $FFUDevelopmentPath\Apps\Unattend\Unattend.xml so sysprep can use it inside the VM. Default is $false.

.PARAMETER InstallApps
When set to $true, the script will create an Apps.iso file from the $FFUDevelopmentPath\Apps folder. It will also create a VM, mount the Apps.iso, install the apps, sysprep, and capture the VM. When set to $false, the FFU is created from a VHDX file, and no VM is created.

.PARAMETER InstallDrivers
Install device drivers from the specified $FFUDevelopmentPath\Drivers folder if set to $true. Download the drivers and put them in the Drivers folder. The script will recurse the drivers folder and add the drivers to the FFU.

.PARAMETER InstallOffice
Install Microsoft Office if set to $true. The script will download the latest ODT and Office files in the $FFUDevelopmentPath\Apps\Office folder and install Office in the FFU via VM.

.PARAMETER ISOPath
Path to the Windows 10/11 ISO file.

.PARAMETER LogicalSectorSizeBytes
Unit32 value of 512 or 4096. Useful for 4Kn drives or devices shipping with UFS drives. Default is 512.

.PARAMETER Make
Make of the device to download drivers. Accepted values are: 'Microsoft', 'Dell', 'HP', 'Lenovo'.

.PARAMETER MediaType
String value of either 'business' or 'consumer'. This is used to identify which media type to download. Default is 'consumer'.

.PARAMETER Memory
Amount of memory to allocate for the virtual machine. Recommended to use 8GB if possible, especially for Windows 11. Default is 4GB.

.PARAMETER Model
Model of the device to download drivers. This is required if Make is set.

.PARAMETER OfficeConfigXMLFile
Path to a custom Office configuration XML file to use for installation.

.PARAMETER Optimize
When set to $true, will optimize the FFU file. Default is $true.

.PARAMETER OptionalFeatures
Provide a semicolon-separated list of Windows optional features you want to include in the FFU (e.g., netfx3;TFTP).

.PARAMETER OrchestrationPath
Path to the orchestration folder containing scripts that run inside the VM. Default is $FFUDevelopmentPath\Apps\Orchestration.

.PARAMETER PEDriversFolder
Path to the folder containing drivers to be injected into the WinPE deployment media. Default is $FFUDevelopmentPath\PEDrivers.

.PARAMETER Processors
Number of virtual processors for the virtual machine. Recommended to use at least 4.

.PARAMETER ProductKey
Product key for the Windows edition specified in WindowsSKU. This will overwrite whatever SKU is entered for WindowsSKU. Recommended to use if you want to use a MAK or KMS key to activate Enterprise or Education. If using VL media instead of consumer media, you'll want to enter a MAK or KMS key here.

.PARAMETER PromptExternalHardDiskMedia
When set to $true, will prompt the user to confirm the use of media identified as External Hard Disk media via WMI class Win32_DiskDrive. Default is $true.

.PARAMETER RemoveApps
When set to $true, will remove the application content in the Apps folder after the FFU has been captured. Default is $true.

.PARAMETER RemoveFFU
When set to $true, will remove the FFU file from the $FFUDevelopmentPath\FFU folder after it has been copied to the USB drive. Default is $false.

.PARAMETER RemoveUpdates
When set to $true, will remove the downloaded CU, MSRT, Defender, Edge, OneDrive, and .NET files downloaded. Default is $true.

.PARAMETER ShareName
Name of the shared folder for FFU capture. The default is FFUCaptureShare. This share will be created with rights for the user account. When finished, the share will be removed.

.PARAMETER UpdateADK
When set to $true, the script will check for and install the latest Windows ADK and WinPE add-on if they are not already installed or up-to-date. Default is $true.

.PARAMETER UpdateEdge
When set to $true, will download and install the latest Microsoft Edge. Default is $false.

.PARAMETER UpdateLatestCU
When set to $true, will download and install the latest cumulative update. Default is $false.

.PARAMETER UpdateLatestDefender
When set to $true, will download and install the latest Windows Defender definitions and Defender platform update. Default is $false.

.PARAMETER UpdateLatestMicrocode
When set to $true, will download and install the latest microcode updates for applicable Windows releases (e.g., Windows Server 2016/2019, Windows 10 LTSC 2016/2019) into the FFU. Default is $false.

.PARAMETER UpdateLatestMSRT
When set to $true, will download and install the latest Windows Malicious Software Removal Tool. Default is $false.

.PARAMETER UpdateLatestNet
When set to $true, will download and install the latest .NET Framework. Default is $false.

.PARAMETER UpdateOneDrive
When set to $true, will download and install the latest OneDrive and install it as a per-machine installation instead of per-user. Default is $false.

.PARAMETER UpdatePreviewCU
When set to $true, will download and install the latest Preview cumulative update. Default is $false.

.PARAMETER UseDriversAsPEDrivers
When set to $true (and -CopyPEDrivers is also $true), bypasses the contents of $FFUDevelopmentPath\PEDrivers and instead builds the WinPE driver set dynamically from the $DriversFolder path, copying only the required WinPE drivers. Has no effect if -CopyPEDrivers is not specified. Default is $false.

.PARAMETER UserAppListPath
Path to a JSON file containing a list of user-defined applications to install. Default is $FFUDevelopmentPath\Apps\UserAppList.json.

.PARAMETER USBDriveList
A hashtable containing USB drives from win32_diskdrive where:
- Key: USB drive model name (partial match supported)
- Value: USB drive serial number (trailing partial match supported due to some serial numbers ending with blank spaces)

Example: @{ "SanDisk Ultra" = "1234567890"; "Kingston DataTraveler" = "0987654321" }

.PARAMETER MaxUSBDrives
Maximum number of USB drives to build in parallel. Default is 5. Set to 0 to process all discovered drives (or all selected drives when USBDriveList or selection is used). Actual throttle will never exceed the number of drives discovered.

.PARAMETER UserAgent
User agent string to use when downloading files.

.PARAMETER Username
Username for accessing the shared folder. The default is ffu_user. The script will auto-create the account and password. When finished, it will remove the account.

.PARAMETER VMHostIPAddress
IP address of the Hyper-V host for FFU capture. If $InstallApps is set to $true, this parameter must be configured. You must manually configure this, or use the UI to auto-detect.

.PARAMETER VMLocation
Default is $FFUDevelopmentPath\VM. This is the location of the VHDX that gets created where Windows will be installed to.

.PARAMETER VMSwitchName
Name of the Hyper-V virtual switch. If $InstallApps is set to $true, this must be set. This is required to capture the FFU from the VM. The default is '*external*', but you will likely need to change this.

.PARAMETER WindowsArch
String value of 'x86' or 'x64'. This is used to identify which architecture of Windows to download. Default is 'x64'.

.PARAMETER WindowsLang
String value in language-region format (e.g., 'en-us'). This is used to identify which language of media to download. Default is 'en-us'.

.PARAMETER WindowsRelease
Integer value of 10 or 11. This is used to identify which release of Windows to download. Default is 11.

.PARAMETER WindowsSKU
Edition of Windows 10/11 to be installed. Accepted values are: 'Home', 'Home N', 'Home Single Language', 'Education', 'Education N', 'Pro', 'Pro N', 'Pro Education', 'Pro Education N', 'Pro for Workstations', 'Pro N for Workstations', 'Enterprise', 'Enterprise N'.

.PARAMETER WindowsVersion
String value of the Windows version to download. This is used to identify which version of Windows to download. Default is '25h2'.

.EXAMPLE
Command line for most people who want to download the latest Windows 11 Pro x64 media in English (US) with the latest Windows Cumulative Update, .NET Framework, Defender platform and definition updates, Edge, OneDrive, and Office/M365 Apps. It will also copy drivers to the FFU. This can take about 40 minutes to create the FFU due to the time it takes to download and install the updates.
.\BuildFFUVM.ps1 -WindowsSKU 'Pro' -Installapps $true -InstallOffice $true -InstallDrivers $true -VMSwitchName 'Name of your VM Switch in Hyper-V' -VMHostIPAddress 'Your IP Address' -CreateCaptureMedia $true -CreateDeploymentMedia $true -BuildUSBDrive $true -UpdateLatestCU $true -UpdateLatestNet $true -UpdateLatestDefender $true -UpdateEdge $true -UpdateOneDrive $true -verbose

Command line for most people who want to create an FFU with Office and drivers and have downloaded their own ISO. This assumes you have copied this script and associated files to the C:\FFUDevelopment folder. If you need to use another drive or folder, change the -FFUDevelopment parameter (e.g. -FFUDevelopment 'D:\FFUDevelopment')
.\BuildFFUVM.ps1 -ISOPath 'C:\path_to_iso\Windows.iso' -WindowsSKU 'Pro' -Installapps $true -InstallOffice $true -InstallDrivers $true -VMSwitchName 'Name of your VM Switch in Hyper-V' -VMHostIPAddress 'Your IP Address' -CreateCaptureMedia $true -CreateDeploymentMedia $true -BuildUSBDrive $true -verbose

Command line for those who just want a FFU with no drivers, apps, or Office and have downloaded their own ISO.
.\BuildFFUVM.ps1 -ISOPath 'C:\path_to_iso\Windows.iso' -WindowsSKU 'Pro' -Installapps $false -InstallOffice $false -InstallDrivers $false -CreateCaptureMedia $false -CreateDeploymentMedia $true -BuildUSBDrive $true -verbose

Command line for those who just want a FFU with Apps and drivers, no Office and have downloaded their own ISO.
.\BuildFFUVM.ps1 -ISOPath 'C:\path_to_iso\Windows.iso' -WindowsSKU 'Pro' -Installapps $true -InstallOffice $false -InstallDrivers $true -VMSwitchName 'Name of your VM Switch in Hyper-V' -VMHostIPAddress 'Your IP Address' -CreateCaptureMedia $true -CreateDeploymentMedia $true -BuildUSBDrive $true -verbose

Command line for those who want to download the latest Windows 11 Pro x64 media in English (US) and install the latest version of Office and drivers.
.\BuildFFUVM.ps1 -WindowsSKU 'Pro' -Installapps $true -InstallOffice $true -InstallDrivers $true -VMSwitchName 'Name of your VM Switch in Hyper-V' -VMHostIPAddress 'Your IP Address' -CreateCaptureMedia $true -CreateDeploymentMedia $true -BuildUSBDrive $true -verbose

Command line for those who want to download the latest Windows 11 Pro x64 media in French (CA) and install the latest version of Office and drivers.
.\BuildFFUVM.ps1 -WindowsSKU 'Pro' -Installapps $true -InstallOffice $true -InstallDrivers $true -VMSwitchName 'Name of your VM Switch in Hyper-V' -VMHostIPAddress 'Your IP Address' -CreateCaptureMedia $true -CreateDeploymentMedia $true -BuildUSBDrive $true -WindowsRelease 11 -WindowsArch 'x64' -WindowsLang 'fr-ca' -MediaType 'consumer' -verbose

Command line for those who want to download the latest Windows 11 Pro x64 media in English (US) and install the latest version of Office and drivers.
.\BuildFFUVM.ps1 -WindowsSKU 'Pro' -Installapps $true -InstallOffice $true -InstallDrivers $true -VMSwitchName 'Name of your VM Switch in Hyper-V' -VMHostIPAddress 'Your IP Address' -CreateCaptureMedia $true -CreateDeploymentMedia $true -BuildUSBDrive $true -verbose

.NOTES
    Additional notes about your script.

.LINK
    https://github.com/rbalsleyMSFT/FFU
#>


[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [ValidateScript({ Test-Path $_ })]
    [string]$ISOPath,
    [ValidateSet(
        'Home',
        'Home N',
        'Home Single Language',
        'Education',
        'Education N',
        'Pro',
        'Pro N',
        'Pro Education',
        'Pro Education N',
        'Pro for Workstations',
        'Pro N for Workstations',
        'Enterprise',
        'Enterprise N',
        'Enterprise 2016 LTSB',
        'Enterprise N 2016 LTSB',
        'Enterprise LTSC',
        'Enterprise N LTSC',
        'IoT Enterprise LTSC',
        'IoT Enterprise N LTSC',
        'Standard',
        'Standard (Desktop Experience)',
        'Datacenter',
        'Datacenter (Desktop Experience)'
    )]
    [string]$WindowsSKU = 'Pro',
    [ValidateNotNullOrEmpty()]
    [string]$FFUDevelopmentPath = $PSScriptRoot,
    [bool]$InstallApps,
    # NOTE: AppListPath/UserAppListPath validation uses parent directory check instead of file existence
    # because these files may be specified in config before they exist (e.g., populated by winget operations)
    # The script gracefully handles missing files at runtime (see lines 1885-1886)
    [Parameter(Mandatory = $false)]
    [ValidateScript({ [string]::IsNullOrWhiteSpace($_) -or (Test-Path (Split-Path $_ -Parent) -PathType Container) })]
    [string]$AppListPath,
    [Parameter(Mandatory = $false)]
    [ValidateScript({ [string]::IsNullOrWhiteSpace($_) -or (Test-Path (Split-Path $_ -Parent) -PathType Container) })]
    [string]$UserAppListPath,

    [hashtable]$AppsScriptVariables,
    [bool]$InstallOffice,
    # NOTE: OfficeConfigXMLFile uses parent directory check for same reason as above
    [Parameter(Mandatory = $false)]
    [ValidateScript({ [string]::IsNullOrWhiteSpace($_) -or (Test-Path (Split-Path $_ -Parent) -PathType Container) })]
    [string]$OfficeConfigXMLFile,
    [ValidateSet('Microsoft', 'Dell', 'HP', 'Lenovo')]
    [string]$Make,
    [string]$Model,
    [bool]$InstallDrivers,
    [Parameter(Mandatory = $false)]
    [ValidateRange(2GB, 128GB)]
    [uint64]$Memory = [FFUConstants]::DEFAULT_VM_MEMORY,
    [Parameter(Mandatory = $false)]
    [ValidateRange(25GB, 2TB)]
    [uint64]$Disksize = [FFUConstants]::DEFAULT_VHDX_SIZE,
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 64)]
    [int]$Processors = [FFUConstants]::DEFAULT_VM_PROCESSORS,
    [string]$VMSwitchName,
    [Parameter(Mandatory = $false)]
    [ValidateScript({ [string]::IsNullOrWhiteSpace($_) -or (Test-Path (Split-Path $_ -Parent) -PathType Container) })]
    [string]$VMLocation,
    [ValidateNotNullOrEmpty()]
    [string]$FFUPrefix = '_FFU',
    [Parameter(Mandatory = $false)]
    [ValidateScript({ [string]::IsNullOrWhiteSpace($_) -or (Test-Path (Split-Path $_ -Parent) -PathType Container) -or (Test-Path $_ -PathType Container) })]
    [string]$FFUCaptureLocation,
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^[a-zA-Z0-9_\-$]+$')]
    [string]$ShareName = "FFUCaptureShare",
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^[a-zA-Z0-9_\-]+$')]
    [string]$Username = "ffu_user",
    [string]$CustomFFUNameTemplate,
    [Parameter(Mandatory = $false)]
    [ValidatePattern('^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$')]
    [string]$VMHostIPAddress,
    [bool]$CreateCaptureMedia = $true,
    [bool]$CreateDeploymentMedia,
    [ValidateScript({
            $allowedFeatures = @("Windows-Defender-Default-Definitions", "Printing-PrintToPDFServices-Features", "Printing-XPSServices-Features", "TelnetClient", "TFTP",
                "TIFFIFilter", "LegacyComponents", "DirectPlay", "MSRDC-Infrastructure", "Windows-Identity-Foundation", "MicrosoftWindowsPowerShellV2Root", "MicrosoftWindowsPowerShellV2",
                "SimpleTCP", "NetFx4-AdvSrvs", "NetFx4Extended-ASPNET45", "WCF-Services45", "WCF-HTTP-Activation45", "WCF-TCP-Activation45", "WCF-Pipe-Activation45", "WCF-MSMQ-Activation45",
                "WCF-TCP-PortSharing45", "IIS-WebServerRole", "IIS-WebServer", "IIS-CommonHttpFeatures", "IIS-HttpErrors", "IIS-HttpRedirect", "IIS-ApplicationDevelopment", "IIS-Security",
                "IIS-RequestFiltering", "IIS-NetFxExtensibility", "IIS-NetFxExtensibility45", "IIS-HealthAndDiagnostics", "IIS-HttpLogging", "IIS-LoggingLibraries", "IIS-RequestMonitor",
                "IIS-HttpTracing", "IIS-URLAuthorization", "IIS-IPSecurity", "IIS-Performance", "IIS-HttpCompressionDynamic", "IIS-WebServerManagementTools", "IIS-ManagementScriptingTools",
                "IIS-IIS6ManagementCompatibility", "IIS-Metabase", "WAS-WindowsActivationService", "WAS-ProcessModel", "WAS-NetFxEnvironment", "WAS-ConfigurationAPI", "IIS-HostableWebCore",
                "WCF-HTTP-Activation", "WCF-NonHTTP-Activation", "IIS-StaticContent", "IIS-DefaultDocument", "IIS-DirectoryBrowsing", "IIS-WebDAV", "IIS-WebSockets", "IIS-ApplicationInit",
                "IIS-ISAPIFilter", "IIS-ISAPIExtensions", "IIS-ASPNET", "IIS-ASPNET45", "IIS-ASP", "IIS-CGI", "IIS-ServerSideIncludes", "IIS-CustomLogging", "IIS-BasicAuthentication",
                "IIS-HttpCompressionStatic", "IIS-ManagementConsole", "IIS-ManagementService", "IIS-WMICompatibility", "IIS-LegacyScripts", "IIS-LegacySnapIn", "IIS-FTPServer", "IIS-FTPSvc",
                "IIS-FTPExtensibility", "MSMQ-Container", "MSMQ-DCOMProxy", "MSMQ-Server", "MSMQ-ADIntegration", "MSMQ-HTTP", "MSMQ-Multicast", "MSMQ-Triggers", "IIS-CertProvider",
                "IIS-WindowsAuthentication", "IIS-DigestAuthentication", "IIS-ClientCertificateMappingAuthentication", "IIS-IISCertificateMappingAuthentication", "IIS-ODBCLogging",
                "NetFx3", "SMB1Protocol-Deprecation", "MediaPlayback", "WindowsMediaPlayer", "Client-DeviceLockdown", "Client-EmbeddedShellLauncher", "Client-EmbeddedBootExp",
                "Client-EmbeddedLogon", "Client-KeyboardFilter", "Client-UnifiedWriteFilter", "HostGuardian", "MultiPoint-Connector", "MultiPoint-Connector-Services", "MultiPoint-Tools"
                , "AppServerClient", "SearchEngine-Client-Package", "WorkFolders-Client", "Printing-Foundation-Features", "Printing-Foundation-InternetPrinting-Client",
                "Printing-Foundation-LPDPrintService", "Printing-Foundation-LPRPortMonitor", "HypervisorPlatform", "VirtualMachinePlatform", "Microsoft-Windows-Subsystem-Linux",
                "Client-ProjFS", "Containers-DisposableClientVM", 'Containers-DisposableClientVM', 'Microsoft-Hyper-V-All', 'Microsoft-Hyper-V', 'Microsoft-Hyper-V-Tools-All',
                'Microsoft-Hyper-V-Management-PowerShell', 'Microsoft-Hyper-V-Hypervisor', 'Microsoft-Hyper-V-Services', 'Microsoft-Hyper-V-Management-Clients', 'DataCenterBridging',
                'DirectoryServices-ADAM-Client', 'Windows-Defender-ApplicationGuard', 'ServicesForNFS-ClientOnly', 'ClientForNFS-Infrastructure', 'NFS-Administration', 'Containers', 'Containers-HNS',
                'Containers-SDN', 'SMB1Protocol', 'SMB1Protocol-Client', 'SMB1Protocol-Server', 'SmbDirect')
            $inputFeatures = $_ -split ';'
            foreach ($feature in $inputFeatures) {
                if (-not ($allowedFeatures -contains $feature)) {
                    throw "Invalid optional feature '$feature'. Allowed values: $($allowedFeatures -join ', ')"
                }
            }
            return $true
        })]
    [string]$OptionalFeatures,
    [string]$ProductKey,
    [bool]$BuildUSBDrive,
    [hashtable]$USBDriveList,
    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 100)]
    [int]$MaxUSBDrives = 5,
    [Parameter(Mandatory = $false)]
    [ValidateSet(10, 11, 2016, 2019, 2021, 2022, 2024, 2025)]
    [int]$WindowsRelease = 11,
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^(\d{4}|[12][0-9][hH][12]|LTSC|ltsc)$')]
    [string]$WindowsVersion = '25h2',
    [Parameter(Mandatory = $false)]
    [ValidateSet('x86', 'x64', 'arm64')]
    [string]$WindowsArch = 'x64',
    [ValidateScript({
            $allowedLang = @('ar-sa', 'bg-bg', 'cs-cz', 'da-dk', 'de-de', 'el-gr', 'en-gb', 'en-us', 'es-es', 'es-mx', 'et-ee', 'fi-fi', 'fr-ca', 'fr-fr', 'he-il', 'hr-hr', 'hu-hu',
                'it-it', 'ja-jp', 'ko-kr', 'lt-lt', 'lv-lv', 'nb-no', 'nl-nl', 'pl-pl', 'pt-br', 'pt-pt', 'ro-ro', 'ru-ru', 'sk-sk', 'sl-si', 'sr-latn-rs', 'sv-se', 'th-th', 'tr-tr', 'uk-ua',
                'zh-cn', 'zh-tw')
            if ($allowedLang -contains $_) { $true } else { throw "Invalid WindowsLang value. Allowed values: $($allowedLang -join ', ')" }
            return $true
        })]
    [Parameter(Mandatory = $false)]
    [string]$WindowsLang = 'en-us',
    [Parameter(Mandatory = $false)]
    [ValidateSet('consumer', 'business')]
    [string]$MediaType = 'consumer',
    [ValidateSet(512, 4096)]
    [uint32]$LogicalSectorSizeBytes = 512,
    [bool]$Optimize = $true,
    # NOTE: DriversJsonPath uses parent directory check instead of file existence
    # because the file may be specified in config before it exists
    # The script gracefully handles missing files at runtime (see lines 1375, 1401)
    [Parameter(Mandatory = $false)]
    [ValidateScript({ [string]::IsNullOrWhiteSpace($_) -or (Test-Path (Split-Path $_ -Parent) -PathType Container) })]
    [string]$DriversJsonPath,
    [bool]$CompressDownloadedDriversToWim = $false,
    [bool]$CopyDrivers,
    [bool]$CopyPEDrivers,
    [bool]$UseDriversAsPEDrivers,
    [bool]$RemoveFFU,
    [bool]$CopyAdditionalFFUFiles,
    [Parameter(Mandatory = $false)]
    [ValidateScript({
        if ($null -eq $_ -or $_.Count -eq 0) { return $true }
        foreach ($file in $_) {
            if (-not (Test-Path $file -PathType Leaf)) {
                throw "AdditionalFFUFiles: File not found: $file"
            }
        }
        return $true
    })]
    [string[]]$AdditionalFFUFiles,
    [bool]$UpdateLatestCU,
    [bool]$UpdatePreviewCU,
    [bool]$UpdateLatestMicrocode,
    [bool]$UpdateLatestNet,
    [bool]$UpdateLatestDefender,
    [bool]$UpdateLatestMSRT,
    [bool]$UpdateEdge,
    [bool]$UpdateOneDrive,
    [bool]$AllowVHDXCaching,
    [bool]$CopyPPKG,
    [bool]$CopyUnattend,
    [bool]$CopyAutopilot,
    [bool]$CompactOS = $true,
    [bool]$CleanupCaptureISO = $true,
    [bool]$CleanupDeployISO = $true,
    [bool]$CleanupAppsISO = $true,
    # NOTE: Cleanup parameters below default to $false to match UI defaults
    # Only the ISO cleanup options are checked by default in the UI
    [bool]$RemoveUpdates = $false,
    [bool]$RemoveApps = $false,
    [Parameter(Mandatory = $false)]
    [ValidateScript({ [string]::IsNullOrWhiteSpace($_) -or (Test-Path $_ -PathType Container) })]
    [string]$DriversFolder,
    [Parameter(Mandatory = $false)]
    [ValidateScript({ [string]::IsNullOrWhiteSpace($_) -or (Test-Path $_ -PathType Container) })]
    [string]$PEDriversFolder,
    [bool]$CleanupDrivers = $false,
    [string]$UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36 Edg/125.0.0.0',
    #Microsoft sites will intermittently fail on downloads. These headers are to help with that.
    $Headers = @{
        "Accept"                    = "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7"
        "Accept-Encoding"           = "gzip, deflate, br, zstd"
        "Accept-Language"           = "en-US,en;q=0.9"
        "Priority"                  = "u=0, i"
        "Sec-Ch-Ua"                 = "`"Microsoft Edge`";v=`"125`", `"Chromium`";v=`"125`", `"Not.A/Brand`";v=`"24`""
        "Sec-Ch-Ua-Mobile"          = "?0"
        "Sec-Ch-Ua-Platform"        = "`"Windows`""
        "Sec-Fetch-Dest"            = "document"
        "Sec-Fetch-Mode"            = "navigate"
        "Sec-Fetch-Site"            = "none"
        "Sec-Fetch-User"            = "?1"
        "Upgrade-Insecure-Requests" = "1"
    },
    [bool]$AllowExternalHardDiskMedia,
    [bool]$PromptExternalHardDiskMedia = $true,
    [Parameter(Mandatory = $false)]
    [ValidateScript({ $_ -eq $null -or (Test-Path $_) })]
    [string]$ConfigFile,
    [Parameter(Mandatory = $false)]
    [ValidateScript({ [string]::IsNullOrWhiteSpace($_) -or (Test-Path (Split-Path $_ -Parent) -PathType Container) })]
    [string]$ExportConfigFile,
    [bool]$InjectUnattend = $false,
    [Parameter(Mandatory = $false)]
    [ValidateScript({ [string]::IsNullOrWhiteSpace($_) -or (Test-Path $_ -PathType Container) })]
    [string]$orchestrationPath,
    [bool]$UpdateADK = $true,
    [bool]$CleanupCurrentRunDownloads = $false,
    [switch]$Cleanup
)

BEGIN {
    # ===================================================================
    # PARAMETER VALIDATION - Cross-parameter dependencies
    # ===================================================================
    # This block validates combinations of parameters that have dependencies
    # on each other. Individual parameter validation is handled by attributes.

    # Validate InstallApps dependencies
    if ($InstallApps) {
        if ([string]::IsNullOrWhiteSpace($VMSwitchName)) {
            throw @"
VMSwitchName is required when InstallApps is enabled.

Please specify a VM switch name using -VMSwitchName parameter.
To see available switches, run: Get-VMSwitch | Select-Object Name

Example: -VMSwitchName 'Default Switch'
"@
        }

        if ([string]::IsNullOrWhiteSpace($VMHostIPAddress)) {
            throw @"
VMHostIPAddress is required when InstallApps is enabled.

Please specify your host IP address using -VMHostIPAddress parameter.
This is the IP address of the Hyper-V host that will be used for FFU capture.

To find your IP address, run: Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -notlike '127.*'}

Example: -VMHostIPAddress '192.168.1.100'
"@
        }

        # Validate VM switch exists
        try {
            $switch = Get-VMSwitch -Name $VMSwitchName -ErrorAction Stop
            Write-Verbose "VM switch '$VMSwitchName' found and will be used for the build VM"
        }
        catch {
            $availableSwitches = @(Get-VMSwitch | Select-Object -ExpandProperty Name)
            if ($availableSwitches.Count -gt 0) {
                throw @"
VM switch '$VMSwitchName' not found.

Available VM switches on this host:
$($availableSwitches | ForEach-Object { "  - $_" } | Out-String)

Please specify a valid VM switch using -VMSwitchName parameter.
"@
            }
            else {
                throw @"
VM switch '$VMSwitchName' not found and no VM switches exist on this host.

Please create a VM switch first:
1. Open Hyper-V Manager
2. Click 'Virtual Switch Manager' in the Actions pane
3. Create an External, Internal, or Private switch
4. Then specify it using -VMSwitchName parameter

Or create via PowerShell: New-VMSwitch -Name 'Default Switch' -SwitchType External -NetAdapterName (Get-NetAdapter | Select-Object -First 1).Name
"@
            }
        }
    }

    # Validate Make/Model dependency
    if ($Make -and [string]::IsNullOrWhiteSpace($Model)) {
        throw @"
Model parameter is required when Make is specified.

You specified -Make '$Make' but did not provide a -Model.
Please specify the device model for driver download.

Example: -Make 'Dell' -Model 'Latitude 7490'
"@
    }

    # Validate InstallDrivers dependencies
    if ($InstallDrivers -and -not $DriversFolder -and -not $Make) {
        throw @"
Either DriversFolder or Make must be specified when InstallDrivers is enabled.

InstallDrivers is set to `$true but no driver source is specified.

Options:
1. Specify a local drivers folder: -DriversFolder 'C:\FFUDevelopment\Drivers'
2. Specify Make/Model to auto-download: -Make 'Dell' -Model 'Latitude 7490'

Example: .\BuildFFUVM.ps1 -InstallDrivers `$true -Make 'Dell' -Model 'Latitude 7490'
"@
    }

    Write-Verbose "Parameter validation complete - all required parameters present and valid"
}

END {
    # ===================================================================
    # MAIN SCRIPT BODY
    # ===================================================================

    # NOTE: WindowsRelease/WindowsSKU compatibility validation is performed AFTER config file loading
    # to ensure config file values are used instead of parameter defaults. See validation after line 633.

    # Log PowerShell version information (compatible with PowerShell 5.1 and 7+)
Write-Host "PowerShell Version: $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition) Edition)" -ForegroundColor Green
if ($PSVersionTable.CLRVersion) {
    Write-Host "CLR Version: $($PSVersionTable.CLRVersion)" -ForegroundColor Green
}
Write-Host ""

$ProgressPreference = 'SilentlyContinue'
$version = '2509.1Preview'

# Remove any existing modules to avoid conflicts
if (Get-Module -Name 'FFU.Common.Core' -ErrorAction SilentlyContinue) {
    Remove-Module -Name 'FFU.Common.Core' -Force
}
if (Get-Module -Name 'FFU.Common.Winget' -ErrorAction SilentlyContinue) {
    Remove-Module -Name 'FFU.Common.Winget' -Force
}
if (Get-Module -Name 'FFU.Common.Drivers' -ErrorAction SilentlyContinue) {
    Remove-Module -Name 'FFU.Common.Drivers' -Force
}
# Import the required modules
Import-Module "$PSScriptRoot\FFU.Common" -Force

# Set the module's verbose preference to match the script's - allows logging verbose output to console.
$moduleInfo = Get-Module -Name 'FFU.Common'
if ($moduleInfo) {
    & $moduleInfo { $script:VerbosePreference = $args[0] } $VerbosePreference | Out-Null
}

# If a config file is specified and it exists, load it
if ($ConfigFile -and (Test-Path -Path $ConfigFile)) {
    $configData = Get-Content $ConfigFile -Raw | ConvertFrom-Json
    $keys = $configData.psobject.Properties.Name
    
    # Iterate through the keys in the config data
    foreach ($key in $keys) {
        $value = $configdata.$key
        
        # If $value is empty, skip
        if ($null -eq $value -or 
            ([string]::IsNullOrEmpty([string]$value)) -or 
            ($value -is [System.Collections.Hashtable] -and $value.Count -eq 0) -or 
            ($value -is [System.UInt32] -and $value -eq 0) -or 
            ($value -is [System.UInt64] -and $value -eq 0) -or 
            ($value -is [System.Int32] -and $value -eq 0)) {
            continue
        }

        # If this is the Headers parameter, convert PSCustomObject to hashtable
        if ((($key -eq 'Headers') -or ($key -eq 'AppsScriptVariables') -or ($key -eq 'USBDriveList')) -and ($value -is [System.Management.Automation.PSCustomObject])) {
            $hashtableValue = [hashtable]::new()
            foreach ($prop in $value.psobject.Properties) {
                $hashtableValue[$prop.Name] = $prop.Value
            }
            $value = $hashtableValue
        }

        # Check if this key matches a parameter in the script
        # and if the user did NOT explicitly supply it on the command line
        if ($MyInvocation.MyCommand.Parameters.ContainsKey($key) -and -not $PSBoundParameters.ContainsKey($key)) {
            # Set the parameter's value to what's in the config file
            Set-Variable -Name $key -Value $value -Scope 0
        }
    }
}

# Initialize $Filter for Microsoft Update Catalog searches
# IMPORTANT: Filter is required for architecture-specific catalog queries to ensure
# correct downloads. Without Filter, Get-KBLink returns the first matching result
# which may not match the target architecture, causing Save-KB to return null.
$Filter = @($WindowsArch)
WriteLog "Initialized Update Catalog filter with architecture: $WindowsArch"

# Create FFUDevelopmentPath directory if it doesn't exist
# This allows the script to work even if the directory was deleted or specified path doesn't exist yet
if (-not (Test-Path -LiteralPath $FFUDevelopmentPath -PathType Container)) {
    Write-Host "FFU Development Path does not exist: $FFUDevelopmentPath"
    Write-Host "Creating directory..."
    try {
        New-Item -ItemType Directory -Path $FFUDevelopmentPath -Force | Out-Null
        Write-Host "Successfully created FFU Development Path: $FFUDevelopmentPath" -ForegroundColor Green
    }
    catch {
        Write-Error "FATAL: Failed to create FFU Development Path: $FFUDevelopmentPath"
        Write-Error "Error: $($_.Exception.Message)"
        Write-Error "Please verify you have write permissions to the parent directory."
        throw
    }
}

# Validate that the selected Windows SKU is compatible with the chosen Windows release and ensure an ISO is provided for unsupported releases
$clientSKUs = @(
    'Home',
    'Home N',
    'Home Single Language',
    'Education',
    'Education N',
    'Pro',
    'Pro N',
    'Pro Education',
    'Pro Education N',
    'Pro for Workstations',
    'Pro N for Workstations',
    'Enterprise',
    'Enterprise N'
)
$LTSCSKUs = @(
    'Enterprise 2016 LTSB',
    'Enterprise N 2016 LTSB',
    'Enterprise LTSC',
    'Enterprise N LTSC',
    'IoT Enterprise LTSC',
    'IoT Enterprise N LTSC'
)
$ServerSKUs = @(
    'Standard',
    'Standard (Desktop Experience)',
    'Datacenter',
    'Datacenter (Desktop Experience)'
)
$releaseToSKUMapping = @{
    10   = $clientSKUs
    11   = $clientSKUs
    2016 = $LTSCSKUs + $ServerSKUs
    2019 = $LTSCSKUs + $ServerSKUs
    2021 = $LTSCSKUs
    2022 = $ServerSKUs
    2024 = $LTSCSKUs
    2025 = $ServerSKUs
}
if ($releaseToSKUMapping.ContainsKey($WindowsRelease) -and $WindowsSKU -notin $releaseToSKUMapping[$WindowsRelease]) {
    throw "Selected SKU is $WindowsSKU. Windows $WindowsRelease requires one of these SKUs: $($releaseToSKUMapping[$WindowsRelease] -join ', ')"
}
if ($WindowsRelease -notin 10, 11 -and -not $ISOPath) {
    throw "Windows $WindowsRelease cannot automatically be downloaded. Please specify your own ISO using the -ISOPath parameter."
}

#Class definition for vhdx cache
class VhdxCacheUpdateItem {
    [string]$Name
    VhdxCacheUpdateItem([string]$Name) {
        $this.Name = $Name
    }
}

# Import FFU Builder modules
$ModulePath = "$PSScriptRoot\Modules"

# Add modules folder to PSModulePath so RequiredModules in manifests can be resolved
# This is critical when running in background jobs (e.g., from BuildFFUVM_UI.ps1)
if ($env:PSModulePath -notlike "*$ModulePath*") {
    $env:PSModulePath = "$ModulePath;$env:PSModulePath"
}

# Import modules in dependency order with -Global for cross-scope availability
Import-Module "FFU.Core" -Force -Global -ErrorAction Stop -WarningAction SilentlyContinue
Import-Module "FFU.ADK" -Force -Global -ErrorAction Stop -WarningAction SilentlyContinue
Import-Module "FFU.Drivers" -Force -Global -ErrorAction Stop -WarningAction SilentlyContinue
Import-Module "FFU.Updates" -Force -Global -ErrorAction Stop -WarningAction SilentlyContinue
Import-Module "FFU.VM" -Force -Global -ErrorAction Stop -WarningAction SilentlyContinue
Import-Module "FFU.Imaging" -Force -Global -ErrorAction Stop -WarningAction SilentlyContinue
Import-Module "FFU.Media" -Force -Global -ErrorAction Stop -WarningAction SilentlyContinue
Import-Module "FFU.Apps" -Force -Global -ErrorAction Stop -WarningAction SilentlyContinue

# =============================================================================
# Global Failure Cleanup Handler
# Ensures cleanup of registered resources on terminating errors
# =============================================================================
trap {
    # Only invoke cleanup if the registry has items (avoid unnecessary work)
    $registry = Get-CleanupRegistry
    if ($registry -and $registry.Count -gt 0) {
        WriteLog "TRAP: Unhandled terminating error detected. Invoking failure cleanup for $($registry.Count) registered resource(s)..."
        Invoke-FailureCleanup -Reason "Terminating error: $($_.Exception.Message)"
    }
    # CRITICAL: Use 'break' to propagate the error up the call stack
    # Using 'continue' would swallow the error and resume execution, causing:
    # - Script to continue after catch blocks that re-throw
    # - Success marker to be output even after failures
    # - UI to incorrectly report success
    break
}

# =============================================================================
# USB Drive Functions
# These functions were intentionally kept in BuildFFUVM.ps1 (not modularized)
# because New-DeploymentUSB uses ForEach-Object -Parallel with many $using:
# script-scope variables, which doesn't work well with module encapsulation.
# =============================================================================

Function Get-USBDrive {
    <#
    .SYNOPSIS
        Discovers and validates USB drives for deployment media creation.
    .DESCRIPTION
        Checks for removable and external hard disk media drives based on configuration.
        Supports user prompts for external hard disk selection to prevent data loss.
        Can filter drives by model and serial number using USBDriveList parameter.
    .OUTPUTS
        Returns array of USB drives and count: $USBDrives, $USBDrivesCount
    #>
    # Log the start of the USB drive check
    WriteLog 'Checking for USB drives'

    # Check if external hard disk media is allowed and user has not specified USB drives
    If ($AllowExternalHardDiskMedia -and (-not($USBDriveList))) {
        # Get all removable and external hard disk media drives
        [array]$USBDrives = (Get-WmiObject -Class Win32_DiskDrive -Filter "MediaType='Removable Media' OR MediaType='External hard disk media'")
        [array]$ExternalHardDiskDrives = $USBDrives | Where-Object { $_.MediaType -eq 'External hard disk media' }
        $ExternalCount = $ExternalHardDiskDrives.Count
        $USBDrivesCount = $USBDrives.Count

        # Check if user should be prompted for external hard disk media
        if ($PromptExternalHardDiskMedia) {
            if ($ExternalHardDiskDrives) {
                # Log and warn about found external hard disk media drives
                if ($VerbosePreference -ne 'Continue') {
                    Write-Warning 'Found external hard disk media drives'
                    Write-Warning 'Will prompt for user input to select the drive to use to prevent accidental data loss'
                    Write-Warning 'If you do not want to be prompted for this in the future, set -PromptExternalHardDiskMedia to $false'
                }
                WriteLog 'Found external hard disk media drives'
                WriteLog 'Will prompt for user input to select the drive to use to prevent accidental data loss'
                WriteLog 'If you do not want to be prompted for this in the future, set -PromptExternalHardDiskMedia to $false'

                # Prepare output for user selection
                $Output = @()
                for ($i = 0; $i -lt $ExternalHardDiskDrives.Count; $i++) {
                    $ExternalDiskNumber = $ExternalHardDiskDrives[$i].Index
                    $ExternalDisk = Get-Disk -Number $ExternalDiskNumber
                    $Index = $i + 1
                    $Name = $ExternalDisk.FriendlyName
                    $SerialNumber = $ExternalHardDiskDrives[$i].serialnumber
                    $PartitionStyle = $ExternalDisk.PartitionStyle
                    $Status = $ExternalDisk.OperationalStatus
                    $Properties = [ordered]@{
                        'Drive Number'    = $Index
                        'Drive Name'      = $Name
                        'Serial Number'   = $SerialNumber
                        'Partition Style' = $PartitionStyle
                        'Status'          = $Status
                    }
                    $Output += New-Object PSObject -Property $Properties
                }

                # Format and display the output
                $FormattedOutput = $Output | Format-Table -AutoSize -Property 'Drive Number', 'Drive Name', 'Serial Number', 'Partition Style', 'Status' | Out-String
                if ($VerbosePreference -ne 'Continue') {
                    $FormattedOutput | Out-Host
                }
                WriteLog $FormattedOutput

                # Prompt user to select a drive
                do {
                    $inputChoice = Read-Host "Enter the number corresponding to the external hard disk media drive you want to use"
                    if ($inputChoice -match '^\d+$') {
                        $inputChoice = [int]$inputChoice
                        if ($inputChoice -ge 1 -and $inputChoice -le $ExternalCount) {
                            $SelectedIndex = $inputChoice - 1
                            $ExternalDiskNumber = $ExternalHardDiskDrives[$SelectedIndex].Index
                            $ExternalDisk = Get-Disk -Number $ExternalDiskNumber
                            $USBDrives = $ExternalHardDiskDrives[$SelectedIndex]
                            $USBDrivesCount = $USBDrives.Count
                            if ($VerbosePreference -ne 'Continue') {
                                Write-Host "Drive $inputChoice was selected"
                            }
                            WriteLog "Drive $inputChoice was selected"
                        }
                        else {
                            # Handle invalid selection
                            if ($VerbosePreference -ne 'Continue') {
                                Write-Host "Invalid selection. Please try again."
                            }
                            WriteLog "Invalid selection. Please try again."
                        }

                        # Check if the selected drive is offline
                        if ($ExternalDisk.OperationalStatus -eq 'Offline') {
                            if ($VerbosePreference -ne 'Continue') {
                                Write-Error "Selected Drive is in an Offline State. Please check the drive status in Disk Manager and try again."
                            }
                            WriteLog "Selected Drive is in an Offline State. Please check the drive status in Disk Manager and try again."
                            exit 1
                        }
                    }
                    else {
                        # Handle invalid input
                        if ($VerbosePreference -ne 'Continue') {
                            Write-Host "Invalid selection. Please try again."
                        }
                        WriteLog "Invalid selection. Please try again."
                    }
                } while ($null -eq $selectedIndex)
            }
        }
        else {
            # Log the count of found USB drives
            if ($VerbosePreference -ne 'Continue') {
                Write-Host "Found $USBDrivesCount total USB drives"
                If ($ExternalCount -gt 0) {
                    Write-Host "$ExternalCount external drives"
                }
            }
            WriteLog "Found $USBDrivesCount total USB drives"
            If ($ExternalCount -gt 0) {
                WriteLog "$ExternalCount external drives"
            }
        }
    }
    elseif ($USBDriveList) {
        # Log the count of specified USB drives
        $USBDriveListCount = $USBDriveList.Count
        WriteLog "Looking for $USBDriveListCount USB drives from USB Drive List"
        # Get only the specified USB drives based on both model and serial number
        $USBDrives = @()
        foreach ($model in $USBDriveList.Keys) {
            $serialNumber = $USBDriveList[$model]
            Writelog "Looking for USB drive model $model with serial number $serialNumber"
            $USBDrive = Get-CimInstance -ClassName Win32_DiskDrive -Filter "Model LIKE '%$model%' AND SerialNumber LIKE '$serialNumber%' AND (MediaType='Removable Media' OR MediaType='External hard disk media')"
            if ($USBDrive) {
                WriteLog "Found USB drive model $($USBDrive.model) with serial number $($USBDrive.serialNumber)"
                $USBDrives += $USBDrive
            }
            else {
                WriteLog "USB drive model $model with serial number $serialNumber not found"
            }
        }
        $USBDrivesCount = $USBDrives.Count
        WriteLog "Found $USBDrivesCount of $USBDriveListCount USB drives from USB Drive List"
    }
    else {
        # Get only removable media drives
        [array]$USBDrives = (Get-WmiObject -Class Win32_DiskDrive -Filter "MediaType='Removable Media'")
        $USBDrivesCount = $USBDrives.Count
        WriteLog "Found $USBDrivesCount Removable USB drives"
    }

    # Check if any USB drives were found
    if ($null -eq $USBDrives) {
        WriteLog "No USB drive found. Exiting"
        Write-Error "No USB drive found. Exiting"
        exit 1
    }

    # Return the found USB drives and their count
    return $USBDrives, $USBDrivesCount
}

Function New-DeploymentUSB {
    <#
    .SYNOPSIS
        Creates bootable USB deployment drives with FFU files and supporting content.
    .DESCRIPTION
        Partitions and formats USB drives, copies WinPE boot files from deployment ISO,
        and optionally copies FFU files, drivers, PPKGs, unattend files, and Autopilot configs.
        Supports parallel processing of multiple USB drives.
    .PARAMETER CopyFFU
        Switch to enable copying FFU files to the USB drive.
    .PARAMETER FFUFilesToCopy
        Array of FFU file paths to copy. If not provided and CopyFFU is set,
        prompts user to select from available FFU files.
    #>
    param(
        [switch]$CopyFFU,
        [string[]]$FFUFilesToCopy
    )
    WriteLog "CopyFFU is set to $CopyFFU"
    $BuildUSBPath = $PSScriptRoot
    WriteLog "BuildUSBPath is $BuildUSBPath"

    $SelectedFFUFile = $null

    # 1. Get FFU File(s) - This happens once before parallel processing
    if ($CopyFFU.IsPresent) {
        if ($null -ne $FFUFilesToCopy -and $FFUFilesToCopy.Count -gt 0) {
            $SelectedFFUFile = $FFUFilesToCopy
            WriteLog "Using preselected FFU file list. Count: $($FFUFilesToCopy.Count)"
            WriteLog "FFU files to copy:"
            foreach ($f in $FFUFilesToCopy) {
                WriteLog ("- {0}" -f (Split-Path $f -Leaf))
            }
        }
        else {
            $FFUFiles = Get-ChildItem -Path "$BuildUSBPath\FFU" -Filter "*.ffu"
            $FFUCount = $FFUFiles.count

            switch ($FFUCount) {
                0 {
                    Write-Error "No FFU files found in $BuildUSBPath\FFU. Cannot copy FFU to USB drive."
                    return
                }
                1 {
                    $SelectedFFUFile = $FFUFiles.FullName
                    WriteLog "One FFU file found, will use: $SelectedFFUFile"
                }
                default {
                    WriteLog "Found $FFUCount FFU files"
                    if ($VerbosePreference -ne 'Continue') {
                        Write-Host "Found $FFUCount FFU files"
                    }
                    $output = @()
                    for ($i = 0; $i -lt $FFUCount; $i++) {
                        $output += [PSCustomObject]@{
                            'FFU Number'    = $i + 1
                            'FFU Name'      = $FFUFiles[$i].Name
                            'Last Modified' = $FFUFiles[$i].LastWriteTime
                        }
                    }
                    $output | Format-Table -AutoSize | Out-String | Write-Host

                    do {
                        $inputChoice = Read-Host "Enter the number for the FFU to copy, or 'A' for all"
                        if ($inputChoice -eq 'A') {
                            $SelectedFFUFile = $FFUFiles.FullName
                            WriteLog 'Will copy all FFU Files'
                        }
                        elseif ($inputChoice -match '^\d+$' -and [int]$inputChoice -ge 1 -and [int]$inputChoice -le $FFUCount) {
                            $SelectedFFUFile = $FFUFiles[[int]$inputChoice - 1].FullName
                            WriteLog "$SelectedFFUFile was selected"
                        }
                        else {
                            Write-Host "Invalid selection. Please try again."
                        }
                    } while ($null -eq $SelectedFFUFile)
                }
            }
        }
    }

    # Mount ISO once before the loop
    WriteLog "Mounting deployment ISO: $DeployISO"
    $ISOMountPoint = (Mount-DiskImage -ImagePath $DeployISO -PassThru | Get-Volume).DriveLetter + ":\"
    WriteLog "ISO mounted at $ISOMountPoint"

    # Register cleanup for ISO mount in case of failure
    $isoCleanupId = Register-ISOCleanup -ISOPath $DeployISO
    WriteLog "Registered ISO cleanup handler (ID: $isoCleanupId)"

    # 2. Partition and format USB drives in parallel
    WriteLog "Starting parallel creation for $USBDrivesCount USB drive(s)."

    $resolvedUSBThrottle = if ($MaxUSBDrives -gt 0) { [math]::Min($MaxUSBDrives, $USBDrivesCount) } else { $USBDrivesCount }
    WriteLog "Using USB drive throttle limit: $resolvedUSBThrottle (MaxUSBDrives param: $MaxUSBDrives; Drives to process: $USBDrivesCount)"

    $USBDrives | ForEach-Object -Parallel {
        $USBDrive = $_

        # Import common module for logging in this thread
        Import-Module "$($using:PSScriptRoot)\FFU.Common" -Force
        Set-CommonCoreLogPath -Path $using:LogFile

        $DiskNumber = $USBDrive.DeviceID.Replace("\\.\PHYSICALDRIVE", "")
        WriteLog "Thread $([System.Threading.Thread]::CurrentThread.ManagedThreadId) processing DiskNumber $DiskNumber ($($USBDrive.Model))"

        # Partitioning with error handling
        try {
            $Disk = Get-Disk -Number $DiskNumber -ErrorAction Stop
            if ($Disk.PartitionStyle -ne "RAW") {
                $Disk | Clear-Disk -RemoveData -RemoveOEM -Confirm:$false -ErrorAction Stop
                $Disk = Get-Disk -Number $DiskNumber -ErrorAction Stop
            }
            if ($Disk.PartitionStyle -eq "RAW") {
                $Disk | Initialize-Disk -PartitionStyle MBR -Confirm:$false -ErrorAction Stop
            }
            else {
                $Disk | Get-Partition | Remove-Partition -Confirm:$false -ErrorAction Stop
                $Disk | Set-Disk -PartitionStyle MBR -ErrorAction Stop
            }

            $BootPartition = $Disk | New-Partition -Size 2GB -IsActive -AssignDriveLetter -ErrorAction Stop
            $DeployPartition = $Disk | New-Partition -UseMaximumSize -AssignDriveLetter -ErrorAction Stop
            Format-Volume -Partition $BootPartition -FileSystem FAT32 -NewFileSystemLabel "TempBoot" -Confirm:$false -ErrorAction Stop
            Format-Volume -Partition $DeployPartition -FileSystem NTFS -NewFileSystemLabel "TempDeploy" -Confirm:$false -ErrorAction Stop
        }
        catch {
            WriteLog "ERROR: Disk partitioning failed for disk $DiskNumber - $($_.Exception.Message)"
            throw "Failed to partition disk $DiskNumber : $($_.Exception.Message)"
        }

        $BootPartitionDriveLetter = "$($BootPartition.DriveLetter):\"
        $DeployPartitionDriveLetter = "$($DeployPartition.DriveLetter):\"
        WriteLog "Disk $DiskNumber partitioned. Boot: $BootPartitionDriveLetter, Deploy: $DeployPartitionDriveLetter"

        # Helper function for robocopy exit code validation (exit codes 0-7 are success)
        function Test-RobocopySuccess {
            param([string]$Operation)
            $exitCode = $LASTEXITCODE
            if ($exitCode -ge 8) {
                WriteLog "ERROR: Robocopy failed for '$Operation' with exit code $exitCode"
                throw "Robocopy failed for '$Operation' with exit code $exitCode"
            }
            elseif ($exitCode -gt 0) {
                WriteLog "Robocopy '$Operation' completed with exit code $exitCode (files copied/extra detected)"
            }
        }

        # Copy WinPE files
        WriteLog "Copying WinPE files from $($using:ISOMountPoint) to $BootPartitionDriveLetter"
        robocopy $using:ISOMountPoint $BootPartitionDriveLetter /E /COPYALL /R:5 /W:5 /J /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
        Test-RobocopySuccess -Operation "WinPE files to Boot partition"

        # Copy other files
        if ($using:CopyFFU.IsPresent -and $null -ne $using:SelectedFFUFile) {
            if ($using:SelectedFFUFile -is [array]) {
                WriteLog "Copying multiple FFU files to $DeployPartitionDriveLetter"
                foreach ($FFUFile in $using:SelectedFFUFile) {
                    robocopy (Split-Path $FFUFile -Parent) $DeployPartitionDriveLetter (Split-Path $FFUFile -Leaf) /J /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
                    Test-RobocopySuccess -Operation "FFU file $FFUFile"
                }
            }
            else {
                WriteLog "Copying $($using:SelectedFFUFile) to $DeployPartitionDriveLetter"
                robocopy (Split-Path $using:SelectedFFUFile -Parent) $DeployPartitionDriveLetter (Split-Path $using:SelectedFFUFile -Leaf) /J /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
                Test-RobocopySuccess -Operation "FFU file $($using:SelectedFFUFile)"
            }
        }

        if ($using:CopyDrivers) {
            $DriversPathOnUSB = Join-Path $DeployPartitionDriveLetter "Drivers"
            WriteLog "Copying drivers to $DriversPathOnUSB"
            robocopy $using:DriversFolder $DriversPathOnUSB /E /COPYALL /R:5 /W:5 /J /XF .gitkeep /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
            Test-RobocopySuccess -Operation "Drivers to USB"
        }

        if ($using:CopyPPKG) {
            $PPKGPathOnUSB = Join-Path $DeployPartitionDriveLetter "PPKG"
            WriteLog "Copying PPKGs to $PPKGPathOnUSB"
            robocopy $using:PPKGFolder $PPKGPathOnUSB /E /COPYALL /R:5 /W:5 /J /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
            Test-RobocopySuccess -Operation "PPKG files to USB"
        }

        if ($using:CopyUnattend) {
            $UnattendPathOnUSB = Join-Path $DeployPartitionDriveLetter "Unattend"
            WriteLog "Copying unattend file to $UnattendPathOnUSB"
            New-Item -Path $UnattendPathOnUSB -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
            try {
                if ($using:WindowsArch -eq 'x64') {
                    $unattendSource = Join-Path $using:UnattendFolder 'unattend_x64.xml'
                    if (-not (Test-Path $unattendSource)) {
                        throw "Unattend file not found: $unattendSource"
                    }
                    Copy-Item -Path $unattendSource -Destination (Join-Path $UnattendPathOnUSB 'Unattend.xml') -Force -ErrorAction Stop | Out-Null
                }
                elseif ($using:WindowsArch -eq 'arm64') {
                    $unattendSource = Join-Path $using:UnattendFolder 'unattend_arm64.xml'
                    if (-not (Test-Path $unattendSource)) {
                        throw "Unattend file not found: $unattendSource"
                    }
                    Copy-Item -Path $unattendSource -Destination (Join-Path $UnattendPathOnUSB 'Unattend.xml') -Force -ErrorAction Stop | Out-Null
                }
                if (Test-Path (Join-Path $using:UnattendFolder 'prefixes.txt')) {
                    WriteLog "Copying prefixes.txt file to $UnattendPathOnUSB"
                    Copy-Item -Path (Join-Path $using:UnattendFolder 'prefixes.txt') -Destination (Join-Path $UnattendPathOnUSB 'prefixes.txt') -Force -ErrorAction Stop | Out-Null
                }
                WriteLog 'Copy completed'
            }
            catch {
                WriteLog "ERROR: Failed to copy unattend files - $($_.Exception.Message)"
                throw
            }
        }

        if ($using:CopyAutopilot) {
            $AutopilotPathOnUSB = Join-Path $DeployPartitionDriveLetter "Autopilot"
            WriteLog "Copying Autopilot files to $AutopilotPathOnUSB"
            robocopy $using:AutopilotFolder $AutopilotPathOnUSB /E /COPYALL /R:5 /W:5 /J /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
            Test-RobocopySuccess -Operation "Autopilot files to USB"
        }

        # Rename volumes
        WriteLog "Renaming volumes for disk $DiskNumber"
        Set-Volume -DriveLetter $BootPartition.DriveLetter -NewFileSystemLabel "Boot"
        Set-Volume -DriveLetter $DeployPartition.DriveLetter -NewFileSystemLabel "Deploy"
        WriteLog "Finished processing disk $DiskNumber"

    } -ThrottleLimit $resolvedUSBThrottle

    # Dismount ISO after all parallel jobs are complete
    WriteLog "Dismounting deployment ISO."
    Dismount-DiskImage -ImagePath $DeployISO | Out-Null

    WriteLog "USB Drives completed"
}

# =============================================================================
# End USB Drive Functions
# =============================================================================

class VhdxCacheItem {
    [string]$VhdxFileName = ""
    [uint32]$LogicalSectorSizeBytes = ""
    [string]$WindowsSKU = ""
    [string]$WindowsRelease = ""
    [string]$WindowsVersion = ""
    [string]$OptionalFeatures = ""
    [VhdxCacheUpdateItem[]]$IncludedUpdates = @()
}

#Support for ini reading
$definition = @'
[DllImport("kernel32.dll")]
public static extern uint GetPrivateProfileString(
    string lpAppName,
    string lpKeyName,
    string lpDefault,
    System.Text.StringBuilder lpReturnedString,
    uint nSize,
    string lpFileName);

[DllImport("kernel32.dll", CharSet = CharSet.Auto)]
public static extern uint GetPrivateProfileSection(
    string lpAppName,
    byte[] lpReturnedString,
    uint nSize,
    string lpFileName);
'@
Add-Type -MemberDefinition $definition -Namespace Win32 -Name Kernel32 -PassThru

#Check if Hyper-V feature is installed (requires only checks the module)
$osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
$isServer = $osInfo.Caption -match 'server'

if ($isServer) {
    $hyperVFeature = Get-WindowsFeature -Name Hyper-V
    if ($hyperVFeature.InstallState -ne "Installed") {
        Write-Host "Hyper-V feature is not installed. Please install it before running this script."
        exit
    }
}
else {
    $hyperVFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All
    if ($hyperVFeature.State -ne "Enabled") {
        Write-Host "Hyper-V feature is not enabled. Please enable it before running this script."
        exit
    }
}

# Set default values for variables that depend on other parameters
if (-not $AppsISO) { $AppsISO = "$FFUDevelopmentPath\Apps\Apps.iso" }
if (-not $AppsPath) { $AppsPath = "$FFUDevelopmentPath\Apps" }
if (-not $AppListPath) { $AppListPath = "$AppsPath\AppList.json" }
if (-not $UserAppListPath) { $UserAppListPath = "$AppsPath\UserAppList.json" }
if (-not $OrchestrationPath) { $OrchestrationPath = "$AppsPath\Orchestration" }
if (-not $wingetWin32jsonFile) { $wingetWin32jsonFile = "$OrchestrationPath\WinGetWin32Apps.json" }
if (-not $InstallOfficePath) { $InstallOfficePath = "$OrchestrationPath\Install-Office.ps1" }
if (-not $InstallDefenderPath) { $InstallDefenderPath = "$OrchestrationPath\Update-Defender.ps1" }
if (-not $InstallMSRTPath) { $InstallMSRTPath = "$OrchestrationPath\Update-MSRT.ps1" }
if (-not $InstallODPath) { $InstallODPath = "$OrchestrationPath\Update-OneDrive.ps1" }
if (-not $InstallEdgePath) { $InstallEdgePath = "$OrchestrationPath\Update-Edge.ps1" }
if (-not $AppsScriptVarsJsonPath) { $AppsScriptVarsJsonPath = "$OrchestrationPath\AppsScriptVariables.json" }
if (-not $DeployISO) { $DeployISO = "$FFUDevelopmentPath\WinPE_FFU_Deploy_$WindowsArch.iso" }
if (-not $CaptureISO) { $CaptureISO = "$FFUDevelopmentPath\WinPE_FFU_Capture_$WindowsArch.iso" }
if (-not $OfficePath) { $OfficePath = "$AppsPath\Office" }
if (-not $OfficeDownloadXML) { $OfficeDownloadXML = "$OfficePath\DownloadFFU.xml" }
if (-not $OfficeInstallXML) { $OfficeInstallXML = "DeployFFU.xml" }
if (-not $rand) { $rand = Get-Random }
if (-not $VMLocation) { $VMLocation = "$FFUDevelopmentPath\VM" }
if (-not $VMName) { $VMName = "$FFUPrefix-$rand" }
if (-not $VMPath) { $VMPath = "$VMLocation\$VMName" }
if (-not $VHDXPath) { $VHDXPath = "$VMPath\$VMName.vhdx" }
if (-not $FFUCaptureLocation) { $FFUCaptureLocation = "$FFUDevelopmentPath\FFU" }
if (-not $LogFile) { $LogFile = "$FFUDevelopmentPath\FFUDevelopment.log" }
if (-not $KBPath) { $KBPath = "$FFUDevelopmentPath\KB" }
if (-not $MicrocodePath) { $MicrocodePath = "$KBPath\Microcode" }
if (-not $DefenderPath) { $DefenderPath = "$AppsPath\Defender" }
if (-not $MSRTPath) { $MSRTPath = "$AppsPath\MSRT" }
if (-not $OneDrivePath) { $OneDrivePath = "$AppsPath\OneDrive" }
if (-not $EdgePath) { $EdgePath = "$AppsPath\Edge" }
if (-not $DriversFolder) { $DriversFolder = "$FFUDevelopmentPath\Drivers" }
if (-not $PPKGFolder) { $PPKGFolder = "$FFUDevelopmentPath\PPKG" }
if (-not $UnattendFolder) { $UnattendFolder = "$FFUDevelopmentPath\Unattend" }
if (-not $AutopilotFolder) { $AutopilotFolder = "$FFUDevelopmentPath\Autopilot" }
if (-not $PEDriversFolder) { $PEDriversFolder = "$FFUDevelopmentPath\PEDrivers" }
if (-not $VHDXCacheFolder) { $VHDXCacheFolder = "$FFUDevelopmentPath\VHDXCache" }
if (-not $installationType) { $installationType = if ($WindowsSKU -like "Standard*" -or $WindowsSKU -like "Datacenter*") { 'Server' } else { 'Client' } }
if ($installationType -eq 'Server') {
    #Map $WindowsRelease to $WindowsVersion for Windows Server
    switch ($WindowsRelease) {
        2016 { $WindowsVersion = '1607' }
        2019 { $WindowsVersion = '1809' }
        2022 { $WindowsVersion = '21H2' }
        2025 { $WindowsVersion = '24H2' }
    }
}
if (-not $AppListPath) { $AppListPath = "$AppsPath\AppList.json" }

if ($WindowsSKU -like "*LTS*") {
    switch ($WindowsRelease) {
        2016 { $WindowsVersion = '1607' }
        2019 { $WindowsVersion = '1809' }
        2021 { $WindowsVersion = '21H2' }
        2024 { $WindowsVersion = '24H2' }
    }
    $isLTSC = $true
}

# Set the log path for the common logger
Set-CommonCoreLogPath -Path $LogFile



if (-not $Cleanup) {
    #Remove old log file if found
    if (Test-Path -Path $Logfile) {
        Remove-item -Path $LogFile -Force
    }

    $startTime = Get-Date
    Write-Host "FFU build process started at" $startTime
    Write-Host "This process can take 20 minutes or more. Please do not close this window or any additional windows that pop up"
    Write-Host "To track progress, please open the log file $Logfile or use the -Verbose parameter next time"
}


if ($Cleanup) {
    WriteLog 'User cancelled, starting cleanup process'
    WriteLog 'Cleanup requested via -Cleanup. Running Get-FFUEnvironment...'
    Get-FFUEnvironment -FFUDevelopmentPath $FFUDevelopmentPath `
                       -CleanupCurrentRunDownloads $CleanupCurrentRunDownloads `
                       -VMLocation $VMLocation -UserName $UserName `
                       -RemoveApps $RemoveApps -AppsPath $AppsPath `
                       -RemoveUpdates $RemoveUpdates -KBPath $KBPath `
                       -AppsISO $AppsISO
    return
}

WriteLog 'Begin Logging'
New-RunSession -FFUDevelopmentPath $FFUDevelopmentPath -DriversFolder $DriversFolder -OrchestrationPath $orchestrationPath -OfficePath $OfficePath
Set-Progress -Percentage 1 -Message "FFU build process started..."

####### Generate Config File #######

if ($ExportConfigFile) {
    WriteLog 'Exporting Config File'
    # Get the parameter names from the script and exclude ExportConfigFile
    $paramNames = $MyInvocation.MyCommand.Parameters.Keys | Where-Object { $_ -ne 'ExportConfigFile' }
    try {
        Export-ConfigFile -paramNames $paramNames -ExportConfigFile $ExportConfigFile
        WriteLog "Config file exported to $ExportConfigFile"
    }
    catch {
        WriteLog 'Failed to export config file'
        throw $_
    }
}

####### End Generate Config File #######


#Setting long path support - this prevents issues where some applications have deep directory structures
#and oscdimg fails to create the Apps ISO
try {
    $LongPathsEnabled = Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -ErrorAction Stop
}
catch {
    $LongPathsEnabled = $null
}
if ($LongPathsEnabled -ne 1) {
    WriteLog 'LongPathsEnabled is not set to 1. Setting it to 1'
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Value 1
    WriteLog 'LongPathsEnabled set to 1'
}


Set-Progress -Percentage 2 -Message "Validating parameters..."
###PARAMETER VALIDATION

#Validate drivers folder
if ($InstallDrivers -or $CopyDrivers) {
    WriteLog 'Doing driver validation'
    if ($DriversFolder -match '\s') {
        WriteLog "Driver folder path $DriversFolder contains spaces. Please remove spaces from the path and try again."
        throw "Driver folder path $DriversFolder contains spaces. Please remove spaces from the path and try again."
    }
    if ($Make -and $Model) {
        WriteLog "Make and Model are set to $Make and $Model, will attempt to download drivers"
    }
    elseif ($DriversJsonPath -and (Test-Path -Path $DriversJsonPath)) {
        WriteLog "Drivers JSON path is set to $DriversJsonPath, will attempt to download drivers"
    }
    else {
        # No automatic download source configured - check for existing drivers in folder
        $folderExists = Test-Path -Path $DriversFolder
        $folderHasContent = $false
        if ($folderExists) {
            $folderHasContent = (Get-ChildItem -Path $DriversFolder -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum -ge 1MB
        }

        if (-not $folderExists) {
            $errorMsg = @"
DRIVER CONFIGURATION ERROR: InstallDrivers or CopyDrivers is enabled, but the Drivers folder is missing.

Folder expected at: $DriversFolder

To fix this issue, do ONE of the following:

1. SELECT A DEVICE MODEL in the UI:
   - Go to the Drivers tab
   - Check 'Download Drivers'
   - Select a Make (Dell, HP, Lenovo, Microsoft)
   - Select a Model from the list
   This will automatically download drivers during the build.

2. PROVIDE A DRIVERS JSON FILE:
   - Create a DriversJsonPath configuration with device models
   - The JSON file should list Make/Model combinations to download

3. ADD DRIVERS MANUALLY:
   - Create the folder: $DriversFolder
   - Copy your driver files (INF, CAT, SYS) into subfolders

4. DISABLE DRIVER INSTALLATION:
   - Uncheck 'Install Drivers' and 'Copy Drivers' in the UI
   - This will build the FFU without custom drivers
"@
            WriteLog $errorMsg
            throw $errorMsg
        }

        if (-not $folderHasContent) {
            $errorMsg = @"
DRIVER CONFIGURATION ERROR: InstallDrivers or CopyDrivers is enabled, but the Drivers folder is empty and no drivers are specified for download.

Folder location: $DriversFolder

To fix this issue, do ONE of the following:

1. SELECT A DEVICE MODEL in the UI:
   - Go to the Drivers tab
   - Check 'Download Drivers'
   - Select a Make (Dell, HP, Lenovo, Microsoft)
   - Select a Model from the list
   This will automatically download drivers during the build.

2. PROVIDE A DRIVERS JSON FILE:
   - Set DriversJsonPath to a JSON file with device models
   - The JSON file should list Make/Model combinations to download

3. ADD DRIVERS MANUALLY:
   - Copy your driver files (INF, CAT, SYS) into: $DriversFolder
   - Drivers should be in subfolders organized by device type

4. DISABLE DRIVER INSTALLATION:
   - Uncheck 'Install Drivers' and 'Copy Drivers' in the UI
   - This will build the FFU without custom drivers
"@
            WriteLog $errorMsg
            throw $errorMsg
        }
        WriteLog "Drivers folder found with content. Will use existing drivers."
    }
}
#Validate PEDrivers folder
if ($CopyPEDrivers) {
    WriteLog 'Doing PEDriver validation'
    # Check if $PEdriversFolder has spaces in the path, if it does, throw an error
    if ($PEDriversFolder -match '\s') {
        WriteLog "Driver folder path $PEDriversFolder contains spaces. Please remove spaces from the path and try again."
        throw "Driver folder path $PEDriversFolder contains spaces. Please remove spaces from the path and try again."
    }
    if ($UseDriversAsPEDrivers) {
        # When using Drivers as PE drivers, skip strict PEDrivers folder existence/content checks.
        $driverSourceAvailable = $false
        if ($DriversJsonPath -and (Test-Path -Path $DriversJsonPath)) {
            $driverSourceAvailable = $true
            WriteLog "Drivers JSON path is set to $DriversJsonPath; drivers will be downloaded for WinPE."
        }
        elseif ($Make -and $Model) {
            $driverSourceAvailable = $true
            WriteLog "Make/Model ($Make / $Model) specified; drivers will be downloaded for WinPE."
        }
        elseif ((Test-Path -Path $DriversFolder) -and ((Get-ChildItem -Path $DriversFolder -Recurse | Measure-Object -Property Length -Sum).Sum -ge 1MB)) {
            $driverSourceAvailable = $true
            WriteLog "Drivers folder contains existing content; will reuse for WinPE."
        }
        if (-not $driverSourceAvailable) {
            WriteLog "-UseDriversAsPEDrivers is set, but no driver sources are available (Drivers folder missing/empty and no download instructions)."
            throw "-UseDriversAsPEDrivers is set, but no driver sources are available (Drivers folder missing/empty and no download instructions)."
        }
        WriteLog "UseDriversAsPEDrivers is set. Skipping PEDrivers folder existence/content checks; drivers will be sourced from Drivers folder (or downloaded)."
        WriteLog 'PEDriver validation complete'
    }
    else {
        if (!(Test-Path -Path $PEDriversFolder)) {
            WriteLog "-CopyPEDrivers is set to `$true, but the $PEDriversFolder folder is missing"
            throw "-CopyPEDrivers is set to `$true, but the $PEDriversFolder folder is missing"
        }
        if ((Get-ChildItem -Path $PEDriversFolder -Recurse | Measure-Object -Property Length -Sum).Sum -lt 1MB) {
            WriteLog "-CopyPEDrivers is set to `$true, but the $PEDriversFolder folder is empty"
            throw "-CopyPEDrivers is set to `$true, but the $PEDriversFolder folder is empty"
        }
        WriteLog 'PEDriver validation complete'
    }
}

#Validate PPKG folder
if ($CopyPPKG) {
    WriteLog 'Doing PPKG validation'
    if (!(Test-Path -Path $PPKGFolder)) {
        WriteLog "-CopyPPKG is set to `$true, but the $PPKGFolder folder is missing"
        throw "-CopyPPKG is set to `$true, but the $PPKGFolder folder is missing"
    }
    #Check for at least one .PPKG file
    if (!(Get-ChildItem -Path $PPKGFolder -Filter *.ppkg)) {
        WriteLog "-CopyPPKG is set to `$true, but the $PPKGFolder folder is missing a .PPKG file"
        throw "-CopyPPKG is set to `$true, but the $PPKGFolder folder is missing a .PPKG file"
    }
    WriteLog 'PPKG validation complete'
}

#Validate Autopilot folder
if ($CopyAutopilot) {
    WriteLog 'Doing Autopilot validation'
    if (!(Test-Path -Path $AutopilotFolder)) {
        WriteLog "-CopyAutopilot is set to `$true, but the $AutopilotFolder folder is missing"
        throw "-CopyAutopilot is set to `$true, but the $AutopilotFolder folder is missing"
    }
    #Check for .JSON file
    if (!(Get-ChildItem -Path $AutopilotFolder -Filter *.json)) {
        WriteLog "-CopyAutopilot is set to `$true, but the $AutopilotFolder folder is missing a .JSON file"
        throw "-CopyAutopilot is set to `$true, but the $AutopilotFolder folder is missing a .JSON file"
    }
    WriteLog 'Autopilot validation complete'
}

#Validate Unattend folder
if ($CopyUnattend) {
    WriteLog 'Doing Unattend validation'
    if (!(Test-Path -Path $UnattendFolder)) {
        WriteLog "-CopyUnattend is set to `$true, but the $UnattendFolder folder is missing"
        throw "-CopyUnattend is set to `$true, but the $UnattendFolder folder is missing"
    }
    #Check for .XML file
    if (!(Get-ChildItem -Path $UnattendFolder -Filter unattend_*.xml)) {
        WriteLog "-CopyUnattend is set to `$true, but the $UnattendFolder folder is missing a .XML file"
        throw "-CopyUnattend is set to `$true, but the $UnattendFolder folder is missing a .XML file"
    }
    WriteLog 'Unattend validation complete'
}

# If InstallApps is true, we need capture media.
if ($InstallApps) {
    if (-not $CreateCaptureMedia) {
        WriteLog "InstallApps is true, but CreateCaptureMedia is false. Forcing to true to allow for VM capture to FFU."
        $CreateCaptureMedia = $true
    }
}

#Override $InstallApps value if using ESD to build FFU. This is due to a strange issue where building the FFU
#from vhdx doesn't work (you get an older style OOBE screen and get stuck in an OOBE reboot loop when hitting next).
#This behavior doesn't happen with WIM files.
# If (-not ($ISOPath) -and (-not ($InstallApps))) {
#     $InstallApps = $true
#     WriteLog "Script will download Windows media. Setting `$InstallApps to `$true to build VM to capture FFU. Must do this when using MCT ESD."
# }

if (($InstallOffice -eq $true) -and ($InstallApps -eq $false)) {
    throw "If variable InstallOffice is set to `$true, InstallApps must also be set to `$true."
}
if (($InstallApps -and ($VMSwitchName -eq ''))) {
    throw "If variable InstallApps is set to `$true, VMSwitchName must also be set to capture the FFU. Please set -VMSwitchName and try again."
}

if (($InstallApps -and ($VMHostIPAddress -eq ''))) {
    throw "If variable InstallApps is set to `$true, VMHostIPAddress must also be set to capture the FFU. Please set -VMHostIPAddress and try again."
}

if (($VMHostIPAddress) -and ($VMSwitchName)) {
    WriteLog "Validating -VMSwitchName $VMSwitchName and -VMHostIPAddress $VMHostIPAddress"
    #Check $VMSwitchName by using Get-VMSwitch
    $VMSwitch = Get-VMSwitch -Name $VMSwitchName -ErrorAction SilentlyContinue
    if (-not $VMSwitch) {
        throw "-VMSwitchName $VMSwitchName not found. Please check the -VMSwitchName parameter and try again."
    }
    #Find the IP address of $VMSwitch and check if it matches $VMHostIPAddress
    $interfaceAlias = "vEthernet ($VMSwitchName)"
    $VMSwitchIPAddress = (Get-NetIPAddress -InterfaceAlias $interfaceAlias -AddressFamily 'IPv4' -ErrorAction SilentlyContinue).IPAddress
    if (-not $VMSwitchIPAddress) {
        throw "IP address for -VMSwitchName $VMSwitchName not found. Please check the -VMSwitchName parameter and try again."
    }
    if ($VMSwitchIPAddress -ne $VMHostIPAddress) {
        try {
            # Bypass the check for systems that could have a Hyper-V NAT switch
            $null = Get-NetNat -ErrorAction Stop
            $NetNat = @(Get-NetNat -ErrorAction Stop)
        }
        catch {
            throw "IP address for -VMSwitchName $VMSwitchName is $VMSwitchIPAddress, which does not match the -VMHostIPAddress $VMHostIPAddress. Please check the -VMHostIPAddress parameter and try again."
        }
        if ($NetNat.Count -gt 0) {
            WriteLog "IP address for -VMSwitchName $VMSwitchName is $VMSwitchIPAddress, which does not match the -VMHostIPAddress $VMHostIPAddress!"
            WriteLog "NAT setup detected, remember to configure NATing if the FFU image can't be captured to the network share on the host."
        }
        else {
            throw "IP address for -VMSwitchName $VMSwitchName is $VMSwitchIPAddress, which does not match the -VMHostIPAddress $VMHostIPAddress. Please check the -VMHostIPAddress parameter and try again."
        }
    }
    WriteLog '-VMSwitchName and -VMHostIPAddress validation complete'
}

if (-not ($ISOPath) -and ($OptionalFeatures -like '*netfx3*')) {
    throw "netfx3 specified as an optional feature, however Windows ISO isn't defined. Unable to get netfx3 source files from downloaded ESD media. Please specify a Windows ISO in the ISOPath parameter."
}
if (($LogicalSectorSizeBytes -eq 4096) -and ($installdrivers -eq $true)) {
    $installdrivers = $false
    $CopyDrivers = $true
    WriteLog 'LogicalSectorSizeBytes is set to 4096, which is not supported for driver injection. Setting $installdrivers to $false'
    WriteLog 'As a workaround, setting -copydrivers $true to copy drivers to the deploy partition drivers folder'
    WriteLog 'We are investigating this issue and will update the script if/when we have a fix'
}
if ($BuildUSBDrive -eq $true) {
    $USBDrives, $USBDrivesCount = Get-USBDrive
}
if (($InstallApps -eq $false) -and (($UpdateLatestDefender -eq $true) -or ($UpdateOneDrive -eq $true) -or ($UpdateEdge -eq $true) -or ($UpdateLatestMSRT -eq $true))) {
    WriteLog 'You have selected to update Defender, Malicious Software Removal Tool, OneDrive, or Edge, however you are setting InstallApps to false. These updates require the InstallApps variable to be set to true. Please set InstallApps to true and try again.'
    throw "InstallApps variable must be set to `$true to update Defender, OneDrive, or Edge"
}
if (($WindowsArch -eq 'ARM64') -and ($InstallOffice -eq $true)) {
    $InstallOffice = $false
    WriteLog 'M365 Apps/Office currently fails to install on ARM64 VMs without an internet connection. Setting InstallOffice to false'
}

if (($WindowsArch -eq 'ARM64') -and ($UpdateOneDrive -eq $true)) {
    $UpdateOneDrive = $false
    WriteLog 'OneDrive currently fails to install on ARM64 VMs (even with the OneDrive ARM setup files). Setting UpdateOneDrive to false'
}

if (($WindowsArch -eq 'ARM64') -and ($UpdateLatestMSRT -eq $true)) {
    $UpdateLatestMSRT = $false
    WriteLog 'Windows Malicious Software Removal Tool is not available for the ARM64 architecture.'
}
#If downloading ESD from MCT, hardcode WindowsVersion to 22H2 for Windows 10 and 25H2 for Windows 11
#MCT media only provides 22H2 and 25H2 media
#This prevents issues with VHDX Caching unecessarily and with searching for CUs
if ($ISOPath -eq '') {
    if ($WindowsRelease -eq '10') {
        $WindowsVersion = '22H2'
    }
    if ($WindowsRelease -eq '11') {
        $WindowsVersion = '25H2'
    }
}

###END PARAMETER VALIDATION

#Get script variable values
LogVariableValues -version $version

#Check if environment is dirty
If (Test-Path -Path "$FFUDevelopmentPath\dirty.txt") {
    Get-FFUEnvironment -FFUDevelopmentPath $FFUDevelopmentPath `
                       -CleanupCurrentRunDownloads $CleanupCurrentRunDownloads `
                       -VMLocation $VMLocation -UserName $UserName `
                       -RemoveApps $RemoveApps -AppsPath $AppsPath `
                       -RemoveUpdates $RemoveUpdates -KBPath $KBPath `
                       -AppsISO $AppsISO
}
WriteLog 'Creating dirty.txt file'
New-Item -Path .\ -Name "dirty.txt" -ItemType "file" | Out-Null

# Early CLI prompt for additional FFUs (only if enabled and not provided)
if ($BuildUSBDrive -and $CopyAdditionalFFUFiles -and ((-not $AdditionalFFUFiles) -or ($AdditionalFFUFiles.Count -eq 0))) {
    try {
        $ffuFolder = Join-Path $FFUDevelopmentPath 'FFU'
        if (Test-Path -Path $ffuFolder) {
            $cand = Get-ChildItem -Path $ffuFolder -Filter '*.ffu' -File | Sort-Object LastWriteTime -Descending
            if ($cand.Count -gt 0) {
                Write-Host ""
                Write-Host "Additional FFU files available in $($ffuFolder):"
                $i = 1
                foreach ($c in $cand) {
                    Write-Host ("{0,3}. {1}  [{2}]" -f $i, $c.Name, $c.LastWriteTime)
                    $i++
                }
                Write-Host ""
                $resp = Read-Host "Select additional FFUs to copy (e.g. 1,3,5) or 'A' for all, or press Enter to skip"
                if ($resp -match '^[Aa]$') {
                    $AdditionalFFUFiles = @($cand.FullName)
                }
                elseif ($resp -match '^\s*\d+(\s*,\s*\d+)*\s*$') {
                    $indices = $resp.Split(',') | ForEach-Object { [int]($_.Trim()) }
                    $sel = @()
                    foreach ($idx in $indices) {
                        if ($idx -ge 1 -and $idx -le $cand.Count) {
                            $sel += $cand[$idx - 1].FullName
                        }
                    }
                    $AdditionalFFUFiles = @($sel | Select-Object -Unique)
                }
                else {
                    # Skip if blank or invalid
                    if (-not [string]::IsNullOrWhiteSpace($resp)) {
                        WriteLog "Invalid additional FFU selection input. Skipping."
                    }
                }
            }
        }
    }
    catch {
        WriteLog "Early additional FFU selection prompt failed: $($_.Exception.Message)"
    }
}

#Get drivers first since user could be prompted for additional info
Set-Progress -Percentage 3 -Message "Processing drivers..."
if ($driversJsonPath -and (Test-Path $driversJsonPath) -and ($InstallDrivers -or $CopyDrivers)) {
    WriteLog "Processing drivers from JSON file: $driversJsonPath"
    Import-Module "$PSScriptRoot\FFUUI.Core\FFUUI.Core.psm1"
    # FFU.Common.Drivers.psm1 is imported by FFUUI.Core.psm1

    $driversToProcess = @()
    $jsonData = Get-Content -Path $driversJsonPath -Raw | ConvertFrom-Json

    foreach ($makeEntry in $jsonData.PSObject.Properties) {
        $makeName = $makeEntry.Name
        if ($makeEntry.Value.PSObject.Properties['Models']) {
            foreach ($modelEntry in $makeEntry.Value.Models) {
                # Construct the PSCustomObject exactly as the Save-*DriversTask functions expect $DriverItemData
                $driverItem = [PSCustomObject]@{
                    Make        = $makeName
                    Model       = $modelEntry.Name # This is the display name, e.g., "Surface Book 3" or "Lenovo 500w (83LH)"
                    Link        = if ($modelEntry.PSObject.Properties['Link']) { $modelEntry.Link } else { $null }
                    ProductName = if ($modelEntry.PSObject.Properties['ProductName']) { $modelEntry.ProductName } else { $null } # Specifically for Lenovo
                    MachineType = if ($modelEntry.PSObject.Properties['MachineType']) { $modelEntry.MachineType } else { $null } # Specifically for Lenovo
                    # Ensure all properties potentially accessed by any Save-*DriversTask via $DriverItemData are present
                }
                $driversToProcess += $driverItem
            }
        }
    }

    if ($driversToProcess.Count -eq 0) {
        WriteLog "No drivers found to process in $driversJsonPath."
    }
    else {
        WriteLog "Found $($driversToProcess.Count) driver entries to process from $driversJsonPath."

        $preserveSourceOnCompress = ($UseDriversAsPEDrivers -and $CompressDownloadedDriversToWim)
        $taskArguments = @{
            DriversFolder            = $DriversFolder
            WindowsRelease           = $WindowsRelease
            WindowsArch              = $WindowsArch
            WindowsVersion           = $WindowsVersion 
            Headers                  = $Headers
            UserAgent                = $UserAgent
            CompressToWim            = $CompressDownloadedDriversToWim
            PreserveSourceOnCompress = $preserveSourceOnCompress
        }
        
        WriteLog "Starting parallel driver processing using Invoke-ParallelProcessing..."
        $parallelResults = Invoke-ParallelProcessing -ItemsToProcess $driversToProcess `
            -TaskType 'DownloadDriverByMake' `
            -TaskArguments $taskArguments `
            -IdentifierProperty 'Model' `
            -WindowObject $null `
            -ListViewControl $null `
            -MainThreadLogPath $LogFile

        # After processing, update the driver mapping file
        $successfullyDownloaded = [System.Collections.Generic.List[PSCustomObject]]::new()
        if ($null -ne $parallelResults) {
            # Create a lookup table from the original items to get the 'Make'
            $makeLookup = @{}
            $driversToProcess | ForEach-Object { $makeLookup[$_.Model] = $_.Make }

            # Filter for objects that could be results, avoiding stray log strings
            foreach ($result in ($parallelResults | Where-Object { $_ -is [hashtable] })) {
                if ($null -eq $result) { continue }

                # The result from Invoke-ParallelProcessing is a hashtable.
                # Access properties using their keys.
                $modelName = $result['Identifier']
                $resultCode = $result['ResultCode']
                $driverPath = $result['DriverPath']

                if ([string]::IsNullOrWhiteSpace($modelName)) {
                    WriteLog "Could not determine model name from result object: $($result | ConvertTo-Json -Compress -Depth 3)"
                    continue
                }

                if ($resultCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($driverPath)) {
                    # The task was successful and returned a driver path.
                    $makeJson = $makeLookup[$modelName]
                    if ($makeJson) {
                        $successfullyDownloaded.Add([PSCustomObject]@{
                                Make       = $makeJson
                                Model      = $modelName
                                DriverPath = $driverPath
                            })
                    }
                    else {
                        WriteLog "Warning: Could not find 'Make' for successful download of model '$modelName'. Skipping from DriverMapping.json."
                    }
                }
                else {
                    $logMessage = "Driver download failed or did not return a path for model '$modelName'. Status: $($result['Status'])"
                    WriteLog $logMessage
                    Write-Warning $logMessage
                }
            }
        }
        else {
            WriteLog "Invoke-ParallelProcessing returned null or no results."
        }

        # Update the driver mapping JSON if there are any successful downloads
        if ($successfullyDownloaded.Count -gt 0) {
            try {
                WriteLog "Updating DriverMapping.json with $($successfullyDownloaded.Count) successfully downloaded drivers."
                Update-DriverMappingJson -DownloadedDrivers $successfullyDownloaded -DriversFolder $DriversFolder
            }
            catch {
                WriteLog "Warning: Failed to update DriverMapping.json: $($_.Exception.Message)"
                # This is not a fatal error for the build process itself, so just show a warning.
                Write-Warning "The driver download process completed, but failed to update the DriverMapping.json file. Please check the log for details."
            }
        }
        WriteLog "Finished processing drivers from $driversJsonPath."
        
        # After processing, update the driver mapping file
        $successfullyDownloaded = [System.Collections.Generic.List[PSCustomObject]]::new()
        if ($null -ne $parallelResults) {
            # Create a lookup table from the original items to get the 'Make'
            $makeLookup = @{}
            $driversToProcess | ForEach-Object { $makeLookup[$_.Model] = $_.Make }
        
            foreach ($result in $parallelResults) {
                if ($null -ne $result) {
                    # Collect successful results for driver mapping
                    if ($result.PSObject.Properties['Success'] -and $result.Success -and $result.PSObject.Properties['DriverPath'] -and -not [string]::IsNullOrWhiteSpace($result.DriverPath)) {
                        $modelName = if ($result.PSObject.Properties.Name -contains 'Identifier') { $result.Identifier } else { $result.Model }
                                
                        # Find the 'Make' from the original list
                        $makeJson = $makeLookup[$modelName]

                        if ($makeJson) {
                            $successfullyDownloaded.Add([PSCustomObject]@{
                                    Make       = $makeJson
                                    Model      = $modelName
                                    DriverPath = $result.DriverPath
                                })
                        }
                        else {
                            WriteLog "Warning: Could not find 'Make' for successful download of model '$modelName'. Skipping from DriverMapping.json."
                        }
                    }
                }
            }
        }
        
        # Update the driver mapping JSON if there are any successful downloads
        if ($successfullyDownloaded.Count -gt 0) {
            try {
                WriteLog "Updating DriverMapping.json with $($successfullyDownloaded.Count) successfully downloaded drivers."
                Update-DriverMappingJson -DownloadedDrivers $successfullyDownloaded -DriversFolder $DriversFolder
            }
            catch {
                WriteLog "Warning: Failed to update DriverMapping.json: $($_.Exception.Message)"
                # This is not a fatal error for the build process itself, so just show a warning.
                Write-Warning "The driver download process completed, but failed to update the DriverMapping.json file. Please check the log for details."
            }
        }
    }
}
# Existing single-model driver download logic
elseif (($Make -and $Model) -and ($InstallDrivers -or $CopyDrivers)) {
    try {
        if ($Make -eq 'HP') {
            WriteLog 'Getting HP drivers'
            Get-HPDrivers -Make $Make -Model $Model -WindowsArch $WindowsArch -WindowsRelease $WindowsRelease `
                          -WindowsVersion $WindowsVersion -DriversFolder $DriversFolder `
                          -FFUDevelopmentPath $FFUDevelopmentPath
            WriteLog 'Getting HP drivers completed successfully'
        }
        if ($make -eq 'Microsoft') {
            WriteLog 'Getting Microsoft drivers'
            Get-MicrosoftDrivers -Make $Make -Model $Model -WindowsRelease $WindowsRelease `
                                -Headers $Headers -UserAgent $UserAgent -DriversFolder $DriversFolder `
                                -FFUDevelopmentPath $FFUDevelopmentPath
            WriteLog 'Getting Microsoft drivers completed successfully'
        }
        if ($make -eq 'Lenovo') {
            WriteLog 'Getting Lenovo drivers'
            Get-LenovoDrivers -Make $Make -Model $Model -WindowsArch $WindowsArch -WindowsRelease $WindowsRelease `
                              -Headers $Headers -UserAgent $UserAgent -DriversFolder $DriversFolder `
                              -FFUDevelopmentPath $FFUDevelopmentPath
            WriteLog 'Getting Lenovo drivers completed successfully'
        }
        if ($make -eq 'Dell') {
            WriteLog 'Getting Dell drivers'
            #Dell mixes Win10 and 11 drivers, hence no WindowsRelease parameter
            Get-DellDrivers -Make $Make -Model $Model -WindowsArch $WindowsArch -WindowsRelease $WindowsRelease `
                            -DriversFolder $DriversFolder -FFUDevelopmentPath $FFUDevelopmentPath `
                            -isServer $isServer
            WriteLog 'Getting Dell drivers completed successfully'
        }
    }
    catch {
        Writelog "Getting drivers failed with error $_"
        throw $_
    }
}
            
#Get Windows ADK
Set-Progress -Percentage 5 -Message "Validating ADK installation..."
try {
    # If creating WinPE media, perform comprehensive pre-flight validation
    if ($CreateCaptureMedia -or $CreateDeploymentMedia) {
        WriteLog "Performing ADK pre-flight validation (WinPE media creation requested)..."

        $adkValidation = Test-ADKPrerequisites -WindowsArch $WindowsArch `
                                               -AutoInstall $UpdateADK `
                                               -ThrowOnFailure $true

        if ($adkValidation.IsValid) {
            $adkPath = $adkValidation.ADKPath
            WriteLog "ADK pre-flight validation passed. ADK version: $($adkValidation.ADKVersion)"

            if ($adkValidation.Warnings.Count -gt 0) {
                WriteLog "Note: $($adkValidation.Warnings.Count) warning(s) detected (non-blocking)"
            }
        }
        else {
            # This should never execute if ThrowOnFailure=$true, but included for defensive programming
            throw "ADK pre-flight validation failed. See errors above."
        }
    }
    else {
        # No WinPE media creation, use standard ADK validation
        $adkPath = Get-ADK -UpdateADK $UpdateADK
    }

    #Need to use the Deployment and Imaging tools environment to use dism from the Sept 2023 ADK to optimize FFU
    $DandIEnv = Join-Path $adkPath "Assessment and Deployment Kit\Deployment Tools\DandISetEnv.bat"

}
catch {
    WriteLog 'ADK validation or installation failed'
    throw $_
}
            
#Create apps ISO for Office and/or 3rd party apps
if ($InstallApps) {
    Set-Progress -Percentage 6 -Message "Downloading and preparing applications..."
    if (Test-Path -Path $AppsISO) {
        WriteLog "Apps ISO exists at: $AppsISO"
        WriteLog "Will use existing ISO"
    }
    else {
        try {
            #Check for and download WinGet applications
            if (Test-Path -Path $AppListPath) {
                $appList = Get-Content -Path $AppListPath -Raw | ConvertFrom-Json
                
                WriteLog 'Checking for previously downloaded Winget applications'
            
                # Initialize variables
                $missingApps = @()
                $existingMSStoreApps = @()
                $hasExistingApps = $false
            
                # Check for WinGetWin32Apps.json
                $wingetAppsJson = $null
                if (Test-Path -Path $wingetWin32jsonFile) {
                    WriteLog "$wingetWin32jsonFile found"
                    $wingetAppsJson = Get-Content -Path $wingetWin32jsonFile -Raw | ConvertFrom-Json
                    $hasExistingApps = $true
                }
            
                # Check MSStore folder for existing apps
                if (Test-Path -Path "$AppsPath\MSStore") {
                    WriteLog "$AppsPath\MSStore folder found"
                    
                    # Get root folder names in MSStore directory
                    $MSStoreFolder = Get-ChildItem -Path "$AppsPath\MSStore" -Directory
                    
                    # Check content size of each folder
                    foreach ($folder in $MSStoreFolder) {
                        $folderSize = (Get-ChildItem -Path $folder.FullName -Recurse | Measure-Object -Property Length -Sum).Sum
                        if ($folderSize -gt 1MB) {
                            $existingMSStoreApps += $folder.Name
                            $hasExistingApps = $true
                        }
                    }
                }
            
                # If there are no existing apps, use the original AppList.json directly
                if (-not $hasExistingApps) {
                    WriteLog "No existing applications found. Using original AppList.json for all apps."
                    Get-Apps -AppList $AppListPath -AppsPath $AppsPath -WindowsArch $WindowsArch -OrchestrationPath $OrchestrationPath
                }
                else {
                    # Compare apps in AppList.json with existing installations
                    foreach ($app in $appList.apps) {
                        $appFound = $false
                        
                        # Check Win32 apps regardless of source
                        if ($wingetAppsJson) {
                            # Check for exact match or architecture-specific entries
                            $wingetApp = $wingetAppsJson | Where-Object { 
                                $_.Name -eq $app.name -or 
                                $_.Name -eq "$($app.name) (x86)" -or 
                                $_.Name -eq "$($app.name) (x64)" -or
                                $_.Name -eq "$($app.name) (arm64)"
                            }
                            
                            if ($wingetApp) {
                                # Verify content exists in Win32 folder
                                $appFolder = Join-Path -Path "$AppsPath\Win32" -ChildPath $app.name
                                if (Test-Path -Path $appFolder) {
                                    # Check for actual files in the folder or its subdirectories
                                    $allFiles = Get-ChildItem -Path $appFolder -Recurse -File -ErrorAction SilentlyContinue
                                    
                                    if ($allFiles) {
                                        # Verify actual content size
                                        $folderSize = ($allFiles | Measure-Object -Property Length -Sum).Sum
                                        if ($folderSize -gt 1MB) {
                                            $appFound = $true
                                            WriteLog "Found existing Win32 app: $($app.name) (Size: $([math]::Round($folderSize/1MB, 2)) MB)"
                                        }
                                        else {
                                            WriteLog "Win32 app folder exists but content is too small: $($app.name) (Size: $([math]::Round($folderSize/1MB, 2)) MB)"
                                        }
                                    }
                                    else {
                                        WriteLog "Win32 app folder exists but contains no files: $($app.name)"
                                    }
                                }
                                else {
                                    WriteLog "Win32 app folder does not exist: $($app.name)"
                                }
                            }
                        }
            
                        # If not found in Win32, check MSStore folder regardless of source
                        if (-not $appFound) {
                            if ($existingMSStoreApps -contains $app.name) {
                                $appFound = $true
                                WriteLog "Found existing MSStore app: $($app.name)"
                            }
                        }
            
                        # If app not found in either location, add to missing apps list
                        if (-not $appFound) {
                            $missingApps += $app
                            WriteLog "App not found, will download: $($app.name)"
                        }
                    }
            
                    # If missing apps found, create modified AppList.json
                    if ($missingApps.Count -gt 0) {
                        $modifiedAppList = @{
                            apps = $missingApps
                        }
                        
                        $modifiedAppListPath = Join-Path -Path $AppsPath -ChildPath "ModifiedAppList.json"
                        $modifiedAppList | ConvertTo-Json | Set-Content -Path $modifiedAppListPath
                        WriteLog "Created ModifiedAppList.json with $($missingApps.Count) apps to download"
            
                        # Download missing apps
                        WriteLog "Downloading missing applications"
                        Get-Apps -AppList $modifiedAppListPath -AppsPath $AppsPath -WindowsArch $WindowsArch -OrchestrationPath $OrchestrationPath
                        
                        # Cleanup modified app list
                        if (-not [string]::IsNullOrWhiteSpace($modifiedAppListPath)) {
                            Remove-Item -Path $modifiedAppListPath -Force -ErrorAction SilentlyContinue
                        }
                    }
                    else {
                        WriteLog "All applications already downloaded, skipping downloads"
                    }
                }
            }
            # Check is UserAppList.json exists and output to the user which apps will be installed
            # It's expected that the user will have already copied the applications and created the UserAppList.json file
            if (Test-Path -Path $UserAppListPath) {
                $userAppList = Get-Content -Path $UserAppListPath -Raw | ConvertFrom-Json
                WriteLog "UserAppList.json found, the following apps will be installed:"
                foreach ($app in $userAppList) {
                    WriteLog "$($app.name)"
                }
            }

            # Remove residual update artifacts for any updates disabled via flags
            Remove-DisabledArtifacts

            #Install Office
            if ($InstallOffice) {
                #Check if Office has already been downloaded, if so, skip download
                WriteLog 'Checking for M365 Apps/Office download'
                $officeDataFolder = "$AppsPath\Office\Office\Data"
                if (Test-Path -Path $officeDataFolder) {
                    # Check the size of the $officeDataFolder folder
                    $OfficeSize = (Get-ChildItem -Path $officeDataFolder -Recurse | Measure-Object -Property Length -Sum).Sum
                    if ($OfficeSize -gt 1MB) {
                        WriteLog "Found Office download in $officeDataFolder, skipping download"
                    }
                    else {
                        WriteLog 'Downloading M365 Apps/Office'
                        Get-Office -OfficePath $OfficePath -OfficeDownloadXML $OfficeDownloadXML `
                                   -OfficeInstallXML $OfficeInstallXML -OrchestrationPath $OrchestrationPath `
                                   -FFUDevelopmentPath $FFUDevelopmentPath -Headers $Headers `
                                   -UserAgent $UserAgent -OfficeConfigXMLFile $OfficeConfigXMLFile
                        WriteLog 'Downloading M365 Apps/Office completed successfully'
                    }

                }
                else {
                    WriteLog 'Downloading M365 Apps/Office'
                    Get-Office -OfficePath $OfficePath -OfficeDownloadXML $OfficeDownloadXML `
                               -OfficeInstallXML $OfficeInstallXML -OrchestrationPath $OrchestrationPath `
                               -FFUDevelopmentPath $FFUDevelopmentPath -Headers $Headers `
                               -UserAgent $UserAgent -OfficeConfigXMLFile $OfficeConfigXMLFile
                    WriteLog 'Downloading M365 Apps/Office completed successfully'
                }
                
            }

            #Update Latest Defender Platform and Definitions - these can't be serviced into the VHDX, will be saved to AppsPath
            if ($UpdateLatestDefender) {
                # Check if Defender has already been downloaded, if so, skip download
                WriteLog "`$UpdateLatestDefender is set to true, checking for latest Defender Platform and Security updates"
                if (Test-Path -Path $DefenderPath) {
                    # Check if folder has files (handles empty folder edge case)
                    $defenderFiles = Get-ChildItem -Path $DefenderPath -Recurse -File -ErrorAction SilentlyContinue
                    if ($defenderFiles -and $defenderFiles.Count -gt 0) {
                        $DefenderSize = ($defenderFiles | Measure-Object -Property Length -Sum).Sum
                        if ($DefenderSize -gt 1MB) {
                            WriteLog "Found Defender download in $DefenderPath ($($defenderFiles.Count) files, $([math]::Round($DefenderSize/1MB, 2)) MB), skipping download"
                            $DefenderDownloaded = $true
                        } else {
                            WriteLog "Defender folder exists but files are too small ($([math]::Round($DefenderSize/1MB, 2)) MB < 1 MB), will re-download"
                        }
                    } else {
                        WriteLog "Defender folder exists but is EMPTY (0 files), will download"
                    }
                }
                if (-not $DefenderDownloaded) {
                    WriteLog "Creating $DefenderPath"
                    New-Item -Path $DefenderPath -ItemType Directory -Force | Out-Null

                    # Define array of updates to download
                    $defenderUpdates = @(
                        @{
                            Name        = "Update for Microsoft Defender Antivirus antimalware platform"
                            Description = "Defender Platform"
                        },
                        @{
                            Name        = "Windows Security Platform"
                            Description = "Windows Security Platform"
                        }
                    )

                    # Download each update
                    foreach ($update in $defenderUpdates) {
                        WriteLog "Searching for $($update.Name) from Microsoft Update Catalog and saving to $DefenderPath"
                        $KBFilePath = Save-KB -Name $update.Name -Path $DefenderPath -WindowsArch $WindowsArch -Headers $Headers -UserAgent $UserAgent -Filter $Filter

                        # Validate that Save-KB returned a valid filename
                        if ([string]::IsNullOrWhiteSpace($KBFilePath)) {
                            $errorMsg = "ERROR: Failed to download $($update.Name) for architecture $WindowsArch. No matching file found in Microsoft Update Catalog. This may indicate: (1) The update name is incorrect, (2) No updates available for $WindowsArch architecture, or (3) Microsoft Update Catalog is temporarily unavailable."
                            WriteLog $errorMsg
                            throw $errorMsg
                        }

                        WriteLog "Latest $($update.Description) saved to $DefenderPath\$KBFilePath"

                        # Layer 1: Build-time validation - verify downloaded file exists before generating command
                        $fullFilePath = Join-Path $DefenderPath $KBFilePath
                        if (-not (Test-Path -Path $fullFilePath -PathType Leaf)) {
                            $errorMsg = "ERROR: Downloaded file not found at expected location: $fullFilePath. Save-KB reported success but file is missing."
                            WriteLog $errorMsg
                            throw $errorMsg
                        }
                        $fileSize = (Get-Item -Path $fullFilePath).Length
                        WriteLog "Verified file exists: $fullFilePath (Size: $([math]::Round($fileSize / 1MB, 2)) MB)"

                        # Layer 2: Generate command with runtime file existence check
                        $installDefenderCommand += @"
if (Test-Path -Path 'd:\Defender\$KBFilePath') {
    Write-Host "Installing $($update.Description): $KBFilePath..."
    & d:\Defender\$KBFilePath
    if (`$LASTEXITCODE -ne 0 -and `$LASTEXITCODE -ne 3010) {
        Write-Error "Installation of $KBFilePath failed with exit code: `$LASTEXITCODE"
    } else {
        Write-Host "$KBFilePath installed successfully (Exit code: `$LASTEXITCODE)"
    }
} else {
    Write-Error "CRITICAL: File not found at d:\Defender\$KBFilePath"
    Write-Error "This indicates Apps.iso does not contain Defender folder or files were not included during ISO creation."
    Write-Error "Possible causes: (1) Apps.iso created before Defender download, (2) Stale Apps.iso being reused, (3) ISO creation failed"
    exit 1
}

"@
                    }
                
                    # Download latest Defender Definitions
                    WriteLog "Downloading latest Defender Definitions"
                    # Defender def updates can be found https://www.microsoft.com/en-us/wdsi/defenderupdates
                    if ($WindowsArch -eq 'x64') {
                        $DefenderDefURL = 'https://go.microsoft.com/fwlink/?LinkID=121721&arch=x64'
                    }
                    if ($WindowsArch -eq 'ARM64') {
                        $DefenderDefURL = 'https://go.microsoft.com/fwlink/?LinkID=121721&arch=arm64'
                    }
                    try {
                        WriteLog "Defender definitions URL is $DefenderDefURL"
                        Start-BitsTransferWithRetry -Source $DefenderDefURL -Destination "$DefenderPath\mpam-fe.exe"
                        WriteLog "Defender Definitions downloaded to $DefenderPath\mpam-fe.exe"

                        # Layer 1: Build-time validation - verify downloaded file exists before generating command
                        $mpamFilePath = "$DefenderPath\mpam-fe.exe"
                        if (-not (Test-Path -Path $mpamFilePath -PathType Leaf)) {
                            $errorMsg = "ERROR: Defender definitions file not found at expected location: $mpamFilePath. Download reported success but file is missing."
                            WriteLog $errorMsg
                            throw $errorMsg
                        }
                        $fileSize = (Get-Item -Path $mpamFilePath).Length
                        WriteLog "Verified Defender definitions file exists: $mpamFilePath (Size: $([math]::Round($fileSize / 1MB, 2)) MB)"

                        # Layer 2: Generate command with runtime file existence check
                        $installDefenderCommand += @"
if (Test-Path -Path 'd:\Defender\mpam-fe.exe') {
    Write-Host "Installing Defender Definitions: mpam-fe.exe..."
    & d:\Defender\mpam-fe.exe
    if (`$LASTEXITCODE -ne 0 -and `$LASTEXITCODE -ne 3010) {
        Write-Error "Installation of mpam-fe.exe failed with exit code: `$LASTEXITCODE"
    } else {
        Write-Host "mpam-fe.exe installed successfully (Exit code: `$LASTEXITCODE)"
    }
} else {
    Write-Error "CRITICAL: File not found at d:\Defender\mpam-fe.exe"
    Write-Error "This indicates Apps.iso does not contain Defender definitions file."
    Write-Error "Possible causes: (1) Apps.iso created before Defender download, (2) Stale Apps.iso being reused, (3) ISO creation failed"
    exit 1
}
"@
                    }
                    catch {
                        Write-Host "Downloading Defender Definitions Failed"
                        WriteLog "Downloading Defender Definitions Failed with error $_"
                        throw $_
                    }

                    # Create Update-Defender.ps1
                    WriteLog "Creating $installDefenderPath"
                    Set-Content -Path $installDefenderPath -Value $installDefenderCommand -Force
                    if (Test-Path -Path $installDefenderPath) {
                        WriteLog "$installDefenderPath created successfully"
                    }
                    else {
                        WriteLog "$installDefenderPath failed to create"
                        throw "$installDefenderPath failed to create"
                    }
                }
            }
            # Download latest MSRT
            if ($UpdateLatestMSRT) {
                WriteLog "`$UpdateLatestMSRT is set to true, checking for latest Windows Malicious Software Removal Tool"
                # Check if MSRT has already been downloaded, if so, skip download
                if (Test-Path -Path $MSRTPath) {
                    # Check if folder has files (handles empty folder edge case)
                    $msrtFiles = Get-ChildItem -Path $MSRTPath -Recurse -File -ErrorAction SilentlyContinue
                    if ($msrtFiles -and $msrtFiles.Count -gt 0) {
                        $MSRTSize = ($msrtFiles | Measure-Object -Property Length -Sum).Sum
                        if ($MSRTSize -gt 1MB) {
                            WriteLog "Found MSRT download in $MSRTPath ($($msrtFiles.Count) files, $([math]::Round($MSRTSize/1MB, 2)) MB), skipping download"
                            $MSRTDownloaded = $true
                        } else {
                            WriteLog "MSRT folder exists but files are too small ($([math]::Round($MSRTSize/1MB, 2)) MB < 1 MB), will re-download"
                        }
                    } else {
                        WriteLog "MSRT folder exists but is EMPTY (0 files), will download"
                    }
                }
                if (-Not $MSRTDownloaded) {
                    # Create the search string for MSRT based on Windows architecture and release
                    if ($WindowsArch -eq 'x64') {
                        if ($installationType -eq 'client' -and (-not $isLTSC)) {
                            $Name = """Windows Malicious Software Removal Tool x64""" + " " + """Windows $WindowsRelease""" 
                        }
                        # Handle LTSB/LTSC
                        elseif ($installationType -eq 'client' -and $isLTSC -eq $true) {
                            $Name = """Windows Malicious Software Removal Tool x64""" + " " + """LTSB"""    
                        }
                        #Windows Server 2025 isn't listed as a product in the Microsoft Update Catalog, so we'll use the 2019 version
                        elseif ($installationType -eq 'server' -and $WindowsRelease -eq '24H2') {
                            $Name = """Windows Malicious Software Removal Tool x64""" + " " + """Windows Server 2019"""
                        }
                        else {
                            $Name = """Windows Malicious Software Removal Tool x64""" + " " + """Windows Server $WindowsRelease""" 
                        }
                    }
                    if ($WindowsArch -eq 'x86') {
                        $Name = """Windows Malicious Software Removal Tool""" + " " + """Windows $WindowsRelease""" 
                    }
                    #Check if $MSRTPath exists, if not, create it
                    if (-not (Test-Path -Path $MSRTPath)) {
                        WriteLog "Creating $MSRTPath"
                        New-Item -Path $MSRTPath -ItemType Directory -Force | Out-Null
                    }
                    WriteLog "Searching for $Name from Microsoft Update Catalog and saving to $MSRTPath"
                    WriteLog "Getting Windows Malicious Software Removal Tool URL"
                    $MSRTFileName = Save-KB -Name $Name -Path $MSRTPath -WindowsArch $WindowsArch -Headers $Headers -UserAgent $UserAgent -Filter $Filter

                    # Validate that Save-KB returned a valid filename
                    if ([string]::IsNullOrWhiteSpace($MSRTFileName)) {
                        $errorMsg = "ERROR: Failed to download Windows Malicious Software Removal Tool for architecture $WindowsArch. Search query was: $Name. This may indicate: (1) No updates available for $WindowsArch architecture, or (2) Microsoft Update Catalog is temporarily unavailable."
                        WriteLog $errorMsg
                        throw $errorMsg
                    }

                    WriteLog "Latest Windows Malicious Software Removal Tool saved to $MSRTPath\$MSRTFileName"
                
                    # Create Update-MSRT.ps1
                    $installMSRTPath = Join-Path -Path $orchestrationPath -ChildPath "Update-MSRT.ps1"
                    WriteLog "Creating $installMSRTPath"
                    $installMSRTCommand = "& d:\MSRT\$MSRTFileName /quiet"
                    Set-Content -Path $installMSRTPath -Value $installMSRTCommand -Force
                    # Validate that the file created successfully
                    if (Test-Path -Path $installMSRTPath) {
                        WriteLog "$installMSRTPath created successfully"
                    }
                    else {
                        WriteLog "$installMSRTPath failed to create"
                        throw "$installMSRTPath failed to create"
                    }
                }   
            }

            #Download and Install OneDrive Per Machine
            if ($UpdateOneDrive) {
                WriteLog "`$UpdateOneDrive is set to true, checking for latest OneDrive client"
                # Check if OneDrive has already been downloaded, if so, skip download
                if (Test-Path -Path $OneDrivePath) {
                    # Check if folder has files (handles empty folder edge case)
                    $oneDriveFiles = Get-ChildItem -Path $OneDrivePath -Recurse -File -ErrorAction SilentlyContinue
                    if ($oneDriveFiles -and $oneDriveFiles.Count -gt 0) {
                        $OneDriveSize = ($oneDriveFiles | Measure-Object -Property Length -Sum).Sum
                        if ($OneDriveSize -gt 1MB) {
                            WriteLog "Found OneDrive download in $OneDrivePath ($($oneDriveFiles.Count) files, $([math]::Round($OneDriveSize/1MB, 2)) MB), skipping download"
                            $OneDriveDownloaded = $true
                        } else {
                            WriteLog "OneDrive folder exists but files are too small ($([math]::Round($OneDriveSize/1MB, 2)) MB < 1 MB), will re-download"
                        }
                    } else {
                        WriteLog "OneDrive folder exists but is EMPTY (0 files), will download"
                    }
                }
                if (-not $OneDriveDownloaded) {
                    #Check if $OneDrivePath exists, if not, create it
                    If (-not (Test-Path -Path $OneDrivePath)) {
                        WriteLog "Creating $OneDrivePath"
                        New-Item -Path $OneDrivePath -ItemType Directory -Force | Out-Null
                    }
                    WriteLog "Downloading latest OneDrive client"
                    if ($WindowsArch -eq 'x64') {
                        $OneDriveURL = 'https://go.microsoft.com/fwlink/?linkid=844652'
                    }
                    elseif ($WindowsArch -eq 'ARM64') {
                        $OneDriveURL = 'https://go.microsoft.com/fwlink/?linkid=2271260'
                    }
                    try {
                        Start-BitsTransferWithRetry -Source $OneDriveURL -Destination "$OneDrivePath\OneDriveSetup.exe"
                        WriteLog "OneDrive client downloaded to $OneDrivePath\OneDriveSetup.exe"
                    }
                    catch {
                        Write-Host "Downloading OneDrive client Failed"
                        WriteLog "Downloading OneDrive client Failed with error $_"
                        throw $_
                    }

                    # Create Update-OneDrive.ps1
                    $installODPath = Join-Path -Path $orchestrationPath -ChildPath "Update-OneDrive.ps1"
                    WriteLog "Creating $installODPath"
                    $installODCommand = "& d:\OneDrive\OneDriveSetup.exe /allusers /silent"
                    Set-Content -Path $installODPath -Value $installODCommand -Force
                    # Validate that the file created successfully
                    if (Test-Path -Path $installODPath) {
                        WriteLog "$installODPath created successfully"
                    }
                    else {
                        WriteLog "$installODPath failed to create"
                        throw "$installODPath failed to create"
                    }
                }
               
            }

            #Download and Install Edge Stable
            if ($UpdateEdge) {
                WriteLog "`$UpdateEdge is set to true, checking for latest Edge Stable $WindowsArch release"
                # Check if Edge has already been downloaded, if so, skip download
                if (Test-Path -Path $EdgePath) {
                    # Check if folder has files (handles empty folder edge case)
                    $edgeFiles = Get-ChildItem -Path $EdgePath -Recurse -File -ErrorAction SilentlyContinue
                    if ($edgeFiles -and $edgeFiles.Count -gt 0) {
                        $EdgeSize = ($edgeFiles | Measure-Object -Property Length -Sum).Sum
                        if ($EdgeSize -gt 1MB) {
                            WriteLog "Found Edge download in $EdgePath ($($edgeFiles.Count) files, $([math]::Round($EdgeSize/1MB, 2)) MB), skipping download"
                            $EdgeDownloaded = $true
                        } else {
                            WriteLog "Edge folder exists but files are too small ($([math]::Round($EdgeSize/1MB, 2)) MB < 1 MB), will re-download"
                        }
                    } else {
                        WriteLog "Edge folder exists but is EMPTY (0 files), will download"
                    }
                }
                if (-not $EdgeDownloaded) {
                    # Create the search string for Edge based on Windows architecture
                    $Name = "microsoft edge stable -extended $WindowsArch"
                    #Check if $EdgePath exists, if not, create it
                    If (-not (Test-Path -Path $EdgePath)) {
                        WriteLog "Creating $EdgePath"
                        New-Item -Path $EdgePath -ItemType Directory -Force | Out-Null
                    }
                    WriteLog "Searching for $Name from Microsoft Update Catalog and saving to $EdgePath"
                    $KBFilePath = Save-KB -Name $Name -Path $EdgePath -WindowsArch $WindowsArch -Headers $Headers -UserAgent $UserAgent -Filter $Filter

                    # Validate that Save-KB returned a valid filename
                    if ([string]::IsNullOrWhiteSpace($KBFilePath)) {
                        $errorMsg = "ERROR: Failed to download Microsoft Edge Stable for architecture $WindowsArch. Search query was: $Name. This may indicate: (1) No Edge updates available for $WindowsArch architecture, or (2) Microsoft Update Catalog is temporarily unavailable."
                        WriteLog $errorMsg
                        throw $errorMsg
                    }

                    $EdgeCABFilePath = "$EdgePath\$KBFilePath"
                    WriteLog "Latest Edge Stable $WindowsArch release saved to $EdgeCABFilePath"
                
                    #Extract Edge cab file to same folder as $EdgeFilePath
                    $EdgeMSIFileName = "MicrosoftEdgeEnterprise$WindowsArch.msi"
                    $EdgeFullFilePath = "$EdgePath\$EdgeMSIFileName"
                    WriteLog "Expanding $EdgeCABFilePath"
                    Invoke-Process Expand "$EdgeCABFilePath -F:*.msi $EdgeFullFilePath" | Out-Null
                    WriteLog "Expansion complete"

                    #Remove Edge CAB file
                    WriteLog "Removing $EdgeCABFilePath"
                    if (-not [string]::IsNullOrWhiteSpace($EdgeCABFilePath)) {
                        Remove-Item -Path $EdgeCABFilePath -Force -ErrorAction SilentlyContinue
                    }
                    WriteLog "Removal complete"

                    # Create Update-Edge.ps1
                    $installEdgePath = Join-Path -Path $orchestrationPath -ChildPath "Update-Edge.ps1"
                    WriteLog "Creating $installEdgePath"
                    $installEdgeCommand = "& d:\Edge\$EdgeMSIFileName /quiet /norestart"
                    Set-Content -Path $installEdgePath -Value $installEdgeCommand -Force
                    # Validate that the file created successfully
                    if (Test-Path -Path $installEdgePath) {
                        WriteLog "$installEdgePath created successfully"
                    }
                    else {
                        WriteLog "$installEdgePath failed to create"
                        throw "$installEdgePath failed to create"
                    }
                }
                
            }

            # Process AppsScriptVariables - Create json file
            if ($AppsScriptVariables) {
                $AppsScriptVariables | ConvertTo-Json | Out-File -FilePath $appsScriptVarsJsonPath -Encoding UTF8
                WriteLog "AppsScriptVariables exported to $appsScriptVarsJsonPath for use during orchestration"
            }
        
            #Create Apps ISO
            # Inject Unattend.xml into Apps if requested and applicable
            if ($InstallApps -and $InjectUnattend) {
                # Determine source unattend.xml based on architecture
                $archSuffix = if ($WindowsArch -ieq 'arm64') { 'arm64' } else { 'x64' }
                $unattendSource = Join-Path $UnattendFolder "unattend_$archSuffix.xml"

                # Ensure target folder exists under Apps
                $targetFolder = Join-Path $AppsPath 'Unattend'
                if (-not (Test-Path -Path $targetFolder -PathType Container)) {
                    New-Item -Path $targetFolder -ItemType Directory -Force | Out-Null
                }

                # Copy if source exists; otherwise log and skip
                if (Test-Path -Path $unattendSource -PathType Leaf) {
                    $destination = Join-Path $targetFolder 'Unattend.xml'
                    Copy-Item -Path $unattendSource -Destination $destination -Force | Out-Null
                    WriteLog "Injected unattend file into Apps: $unattendSource -> $destination"
                }
                else {
                    WriteLog "InjectUnattend is true but source file missing: $unattendSource. Skipping unattend injection."
                }
            }

            # Layer 3: Force Apps.iso recreation if downloaded files are newer than existing ISO
            if (Test-Path $AppsISO) {
                $isoLastWrite = (Get-Item $AppsISO).LastWriteTime
                WriteLog "Existing Apps.iso found (Last modified: $isoLastWrite). Checking if update files are newer..."

                $needsRebuild = $false
                $newestFile = $null
                $newestFileTime = $null

                # Check Defender files if UpdateLatestDefender was enabled
                if ($UpdateLatestDefender -and (Test-Path -Path $DefenderPath)) {
                    $defenderFiles = Get-ChildItem -Path $DefenderPath -Recurse -File -ErrorAction SilentlyContinue
                    if ($defenderFiles) {
                        $newestDefender = $defenderFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                        if ($newestDefender.LastWriteTime -gt $isoLastWrite) {
                            $needsRebuild = $true
                            $newestFile = $newestDefender.FullName
                            $newestFileTime = $newestDefender.LastWriteTime
                            WriteLog "Defender file is newer than Apps.iso: $($newestDefender.Name) (Modified: $($newestDefender.LastWriteTime))"
                        }
                    }
                }

                # Check MSRT files if UpdateLatestMSRT was enabled
                if ($UpdateLatestMSRT -and (Test-Path -Path $MSRTPath)) {
                    $msrtFiles = Get-ChildItem -Path $MSRTPath -Recurse -File -ErrorAction SilentlyContinue
                    if ($msrtFiles) {
                        $newestMSRT = $msrtFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                        if ($newestMSRT.LastWriteTime -gt $isoLastWrite) {
                            $needsRebuild = $true
                            if (-not $newestFileTime -or $newestMSRT.LastWriteTime -gt $newestFileTime) {
                                $newestFile = $newestMSRT.FullName
                                $newestFileTime = $newestMSRT.LastWriteTime
                            }
                            WriteLog "MSRT file is newer than Apps.iso: $($newestMSRT.Name) (Modified: $($newestMSRT.LastWriteTime))"
                        }
                    }
                }

                # Check Edge files if UpdateEdge was enabled
                if ($UpdateEdge -and (Test-Path -Path $EdgePath)) {
                    $edgeFiles = Get-ChildItem -Path $EdgePath -Recurse -File -ErrorAction SilentlyContinue
                    if ($edgeFiles) {
                        $newestEdge = $edgeFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                        if ($newestEdge.LastWriteTime -gt $isoLastWrite) {
                            $needsRebuild = $true
                            if (-not $newestFileTime -or $newestEdge.LastWriteTime -gt $newestFileTime) {
                                $newestFile = $newestEdge.FullName
                                $newestFileTime = $newestEdge.LastWriteTime
                            }
                            WriteLog "Edge file is newer than Apps.iso: $($newestEdge.Name) (Modified: $($newestEdge.LastWriteTime))"
                        }
                    }
                }

                # Check OneDrive files if UpdateOneDrive was enabled
                if ($UpdateOneDrive -and (Test-Path -Path $OneDrivePath)) {
                    $oneDriveFiles = Get-ChildItem -Path $OneDrivePath -Recurse -File -ErrorAction SilentlyContinue
                    if ($oneDriveFiles) {
                        $newestOneDrive = $oneDriveFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                        if ($newestOneDrive.LastWriteTime -gt $isoLastWrite) {
                            $needsRebuild = $true
                            if (-not $newestFileTime -or $newestOneDrive.LastWriteTime -gt $newestFileTime) {
                                $newestFile = $newestOneDrive.FullName
                                $newestFileTime = $newestOneDrive.LastWriteTime
                            }
                            WriteLog "OneDrive file is newer than Apps.iso: $($newestOneDrive.Name) (Modified: $($newestOneDrive.LastWriteTime))"
                        }
                    }
                }

                if ($needsRebuild) {
                    WriteLog "STALE APPS.ISO DETECTED: Removing outdated Apps.iso to force rebuild with latest files"
                    WriteLog "Newest file: $newestFile (Modified: $newestFileTime)"
                    WriteLog "Apps.iso age: $isoLastWrite"
                    if (-not [string]::IsNullOrWhiteSpace($AppsISO)) {
                        Remove-Item -Path $AppsISO -Force -ErrorAction SilentlyContinue
                    }
                    WriteLog "Stale Apps.iso removed. New ISO will be created with all latest updates."
                } else {
                    WriteLog "Apps.iso is up-to-date. No rebuild required."
                }
            }

            Set-Progress -Percentage 10 -Message "Creating Apps ISO..."
            WriteLog "Creating $AppsISO file"
            New-AppsISO -ADKPath $adkPath -AppsPath $AppsPath -AppsISO $AppsISO
            WriteLog "$AppsISO created successfully"
        }
        catch {
            Write-Host "Creating Apps ISO Failed"
            WriteLog "Creating Apps ISO Failed with error $_"
            throw $_
        }
    }
}

#Create VHDX
try {
    Set-Progress -Percentage 11 -Message "Checking for required Windows Updates..."
    $requiredUpdates = [System.Collections.Generic.List[pscustomobject]]::new()
    $ssuUpdateInfos = [System.Collections.Generic.List[pscustomobject]]::new()
    $cuUpdateInfos = [System.Collections.Generic.List[pscustomobject]]::new()
    $cupUpdateInfos = [System.Collections.Generic.List[pscustomobject]]::new()
    $netUpdateInfos = [System.Collections.Generic.List[pscustomobject]]::new()
    $netFeatureUpdateInfos = [System.Collections.Generic.List[pscustomobject]]::new()
    $microcodeUpdateInfos = [System.Collections.Generic.List[pscustomobject]]::new()

    if ($UpdateLatestCU -or $UpdatePreviewCU -or $UpdateLatestNet -or $UpdateLatestMicrocode) {
        # Determine required updates without downloading them yet
        $cuKbArticleId = $null
        $cupKbArticleId = $null
        $netKbArticleId = $null

        if ($UpdateLatestCU -and -not $UpdatePreviewCU) {
            Writelog "`$UpdateLatestCU is set to true, checking for latest CU"
            if ($WindowsRelease -in 10, 11) { $Name = """Cumulative update for Windows $WindowsRelease Version $WindowsVersion for $WindowsArch""" }
            if ($WindowsRelease -eq 2025) { $Name = """Cumulative Update for Microsoft server operating system, version 24h2 for $WindowsArch""" }
            if ($WindowsRelease -eq 2022) { $Name = """Cumulative Update for Microsoft server operating system, version 21h2 for $WindowsArch""" }
            if ($WindowsRelease -in 2016, 2019 -and $installationType -eq "Server") { $Name = """Cumulative update for Windows Server $WindowsRelease for $WindowsArch""" }
            if ($WindowsRelease -in 2016, 2019, 2021 -and $isLTSC) {
                $today = Get-Date; $firstDayOfMonth = Get-Date -Year $today.Year -Month $today.Month -Day 1; $secondTuesday = $firstDayOfMonth.AddDays(((2 - [int]$firstDayOfMonth.DayOfWeek + 7) % 7) + 7); $updateDate = if ($today -gt $secondTuesday) { $today } else { $today.AddMonths(-1) }
                $Name = """$($updateDate.ToString('yyyy-MM')) Cumulative update for Windows 10 Version $WindowsVersion for $WindowsArch"""
            }
            if ($WindowsRelease -eq 2024 -and $isLTSC) { $Name = """Cumulative update for Windows 11 Version $WindowsVersion for $WindowsArch""" }
            
            if (($WindowsRelease -eq 2016 -and $installationType -eq "Server") -or ($WindowsRelease -in 2016, 2019, 2021 -and $isLTSC)) {
                $SSUName = if ($isLTSC) { """Servicing Stack Update for Windows 10 Version $WindowsVersion for $WindowsArch""" } else { """Servicing stack update for Windows Server $WindowsRelease for $WindowsArch""" }
                WriteLog "Searching for $SSUName from Microsoft Update Catalog"
                (Get-UpdateFileInfo -Name $SSUName -WindowsArch $WindowsArch -Headers $Headers -UserAgent $UserAgent -Filter $Filter) | ForEach-Object { $ssuUpdateInfos.Add($_) }
            }
            WriteLog "Searching for $Name from Microsoft Update Catalog"
            (Get-UpdateFileInfo -Name $Name -WindowsArch $WindowsArch -Headers $Headers -UserAgent $UserAgent -Filter $Filter) | ForEach-Object { $cuUpdateInfos.Add($_) }
            $cuKbArticleId = if ($cuUpdateInfos.Count -gt 0) { $cuUpdateInfos[0].KBArticleID } else { $null }
        }

        if ($UpdatePreviewCU -and $installationType -eq 'Client' -and $WindowsSKU -notlike "*LTSC") {
            Writelog "`$UpdatePreviewCU is set to true, checking for latest Preview CU"
            $Name = """Cumulative update Preview for Windows $WindowsRelease Version $WindowsVersion for $WindowsArch"""
            WriteLog "Searching for $Name from Microsoft Update Catalog"
            (Get-UpdateFileInfo -Name $Name -WindowsArch $WindowsArch -Headers $Headers -UserAgent $UserAgent -Filter $Filter) | ForEach-Object { $cupUpdateInfos.Add($_) }
            $cupKbArticleId = if ($cupUpdateInfos.Count -gt 0) { $cupUpdateInfos[0].KBArticleID } else { $null }
        }

        if ($UpdateLatestNet) {
            Writelog "`$UpdateLatestNet is set to true, checking for latest .NET Framework"
            if ($WindowsRelease -in 2016, 2019, 2021 -and $isLTSC) {
                if ($ssuUpdateInfos.Count -eq 0) {
                    $SSUName = """Servicing Stack Update for Windows 10 Version $WindowsVersion for $WindowsArch"""
                    WriteLog "Searching for $SSUName from Microsoft Update Catalog"
                    (Get-UpdateFileInfo -Name $SSUName -WindowsArch $WindowsArch -Headers $Headers -UserAgent $UserAgent -Filter $Filter) | ForEach-Object { $ssuUpdateInfos.Add($_) }
                }
                if ($WindowsRelease -in 2016) { $name = """Cumulative Update for .NET Framework 4.8 for Windows 10 version $WindowsVersion for $WindowsArch""" }
                if ($WindowsRelease -eq 2019) { $name = """Cumulative Update for .NET Framework 3.5, 4.7.2 and 4.8 for Windows 10 Version $WindowsVersion for $WindowsArch""" }
                if ($WindowsRelease -eq 2021) { $name = """Cumulative Update for .NET Framework 3.5, 4.8 and 4.8.1 for Windows 10 Version $WindowsVersion for $WindowsArch""" }
                WriteLog "Searching for $name from Microsoft Update Catalog"
                (Get-UpdateFileInfo -Name $name -WindowsArch $WindowsArch -Headers $Headers -UserAgent $UserAgent -Filter $Filter) | ForEach-Object { $netUpdateInfos.Add($_) }
                $netKbArticleId = if ($netUpdateInfos.Count -gt 0) { $netUpdateInfos[0].KBArticleID } else { $null }

                if ($WindowsRelease -eq 2021) { $NETFeatureName = """Microsoft .NET Framework 4.8.1 for Windows 10 Version 21H2 for x64""" }
                if ($WindowsRelease -in 2016, 2019) { $NETFeatureName = """Microsoft .NET Framework 4.8 for Windows 10 Version $WindowsVersion and Windows Server $WindowsRelease for x64""" }
                WriteLog "Checking for latest .NET Framework feature pack: $NETFeatureName"
                (Get-UpdateFileInfo -Name $NETFeatureName -WindowsArch $WindowsArch -Headers $Headers -UserAgent $UserAgent -Filter $Filter) | ForEach-Object { $netFeatureUpdateInfos.Add($_) }
            }
            else {
                if ($WindowsRelease -eq 2024 -and $isLTSC) { $Name = "Cumulative update for .NET framework windows 11 $WindowsVersion $WindowsArch -preview" }
                if ($WindowsRelease -in 10, 11) { $Name = "Cumulative update for .NET framework windows $WindowsRelease $WindowsVersion $WindowsArch -preview" }
                if ($WindowsRelease -eq 2025 -and $installationType -eq "Server") { $Name = """Cumulative Update for .NET Framework"" ""3.5 and 4.8.1"" for Windows 11 24H2 x64 -preview" }
                if ($WindowsRelease -eq 2022 -and $installationType -eq "Server") { $Name = """Cumulative Update for .NET Framework 3.5, 4.8 and 4.8.1"" ""operating system version 21H2 for x64""" }
                if ($WindowsRelease -eq 2019 -and $installationType -eq "Server") { $Name = """Cumulative Update for .NET Framework 3.5, 4.7.2 and 4.8 for Windows Server 2019 for x64""" }
                if ($WindowsRelease -eq 2016 -and $installationType -eq "Server") { $Name = """Cumulative Update for .NET Framework 4.8 for Windows Server 2016 for x64""" }
                WriteLog "Searching for $Name from Microsoft Update Catalog"
                (Get-UpdateFileInfo -Name $Name -WindowsArch $WindowsArch -Headers $Headers -UserAgent $UserAgent -Filter $Filter) | ForEach-Object { $netUpdateInfos.Add($_) }
                $netKbArticleId = if ($netUpdateInfos.Count -gt 0) { $netUpdateInfos[0].KBArticleID } else { $null }
            }
        }

        if ($UpdateLatestMicrocode -and $WindowsRelease -in 2016, 2019) {
            WriteLog "`$UpdateLatestMicrocode is set to true, checking for latest Microcode"
            if ($WindowsRelease -eq 2016) { $name = "KB4589210 $windowsArch" }
            if ($WindowsRelease -eq 2019) { $name = "KB4589208 $windowsArch" }
            WriteLog "Searching for $name from Microsoft Update Catalog"
            (Get-UpdateFileInfo -Name $name -WindowsArch $WindowsArch -Headers $Headers -UserAgent $UserAgent -Filter $Filter) | ForEach-Object { $microcodeUpdateInfos.Add($_) }
        }
        
        $requiredUpdates.AddRange($ssuUpdateInfos)
        $requiredUpdates.AddRange($cuUpdateInfos)
        $requiredUpdates.AddRange($cupUpdateInfos)
        $requiredUpdates.AddRange($netUpdateInfos)
        $requiredUpdates.AddRange($netFeatureUpdateInfos)
        $requiredUpdates.AddRange($microcodeUpdateInfos)
    }

    #Search for cached VHDX and skip VHDX creation if there's a cached version
    if ($AllowVHDXCaching) {
        WriteLog 'AllowVHDXCaching is true, checking for cached VHDX file'
        if (Test-Path -Path $VHDXCacheFolder) {
            WriteLog "Found $VHDXCacheFolder"
            $vhdxJsons = @(Get-ChildItem -File -Path $VHDXCacheFolder -Filter '*_config.json' | Sort-Object -Property CreationTime -Descending)
            WriteLog "Found $($vhdxJsons.Count) cached VHDX config files"
            
            # Extract file names from URLs for comparison
            $requiredUpdateFileNames = @()
            if ($requiredUpdates.Count -gt 0) {
                $requiredUpdateFileNames = @(($requiredUpdates.Url | ForEach-Object { ($_ -split '/')[-1] }) | Sort-Object)
            }

            foreach ($vhdxJson in $vhdxJsons) {
                try {
                    WriteLog "Processing $($vhdxJson.FullName)"
                    $vhdxCacheItem = Get-Content -Path $vhdxJson.FullName -Raw | ConvertFrom-Json

                    if ($vhdxCacheItem.WindowsSKU -ne $WindowsSKU) { WriteLog 'WindowsSKU mismatch, continuing'; continue }
                    if ($vhdxCacheItem.LogicalSectorSizeBytes -ne $LogicalSectorSizeBytes) { WriteLog 'LogicalSectorSizeBytes mismatch, continuing'; continue }
                    if ($vhdxCacheItem.WindowsRelease -ne $WindowsRelease) { WriteLog 'WindowsRelease mismatch, continuing'; continue }
                    if ($vhdxCacheItem.WindowsVersion -ne $WindowsVersion) { WriteLog 'WindowsVersion mismatch, continuing'; continue }
                    if ($vhdxCacheItem.OptionalFeatures -ne $OptionalFeatures) { WriteLog 'OptionalFeatures mismatch, continuing'; continue }

                    $cachedUpdateNames = @()
                    if ($vhdxCacheItem.IncludedUpdates -and $vhdxCacheItem.IncludedUpdates.Count -gt 0) {
                        $cachedUpdateNames = @($vhdxCacheItem.IncludedUpdates.Name | Sort-Object)
                    }
                    
                    # Manually compare the two sorted arrays of update names
                    $updatesMatch = $false
                    if ($requiredUpdateFileNames.Count -eq $cachedUpdateNames.Count) {
                        $updatesMatch = $true # Assume true and prove false
                        for ($i = 0; $i -lt $requiredUpdateFileNames.Count; $i++) {
                            if ($requiredUpdateFileNames[$i] -ne $cachedUpdateNames[$i]) {
                                $updatesMatch = $false
                                break
                            }
                        }
                    }

                    if (-not $updatesMatch) {
                        WriteLog 'IncludedUpdates mismatch, continuing'
                        continue
                    }

                    WriteLog "Found cached VHDX file $vhdxCacheFolder\$($vhdxCacheItem.VhdxFileName) with matching parameters and included updates"
                    $cachedVHDXFileFound = $true
                    $cachedVHDXInfo = $vhdxCacheItem
                    break
                }
                catch {
                    WriteLog "Reading $vhdxJson Failed with error $_"
                }
            }
        }
    }

    # Check if KB updates already exist and can be reused (when RemoveUpdates=false)
    $kbCacheValid = $false
    if ((Test-Path -Path $KBPath) -and -not $RemoveUpdates -and $requiredUpdates.Count -gt 0) {
        $existingKBFiles = Get-ChildItem -Path $KBPath -Recurse -File -ErrorAction SilentlyContinue
        if ($existingKBFiles -and $existingKBFiles.Count -gt 0) {
            $kbSize = ($existingKBFiles | Measure-Object -Property Length -Sum).Sum
            if ($kbSize -gt 10MB) {
                WriteLog "Found existing KB downloads in $KBPath ($($existingKBFiles.Count) files, $([math]::Round($kbSize/1MB, 2)) MB)"

                # Check if required updates match existing files
                $existingFileNames = $existingKBFiles.Name
                $missingUpdates = [System.Collections.Generic.List[pscustomobject]]::new()
                foreach ($update in $requiredUpdates) {
                    $updateFileName = ($update.Url -split '/')[-1]
                    if ($updateFileName -notin $existingFileNames) {
                        $missingUpdates.Add($update)
                    }
                }

                if ($missingUpdates.Count -eq 0) {
                    WriteLog "All $($requiredUpdates.Count) required updates found in KB cache, skipping download"
                    $kbCacheValid = $true
                } elseif ($missingUpdates.Count -lt $requiredUpdates.Count) {
                    WriteLog "$($missingUpdates.Count) of $($requiredUpdates.Count) updates missing from cache, downloading missing updates only"
                    $requiredUpdates = $missingUpdates
                } else {
                    WriteLog "No matching updates found in cache, will download all $($requiredUpdates.Count) updates"
                }
            } else {
                WriteLog "KB folder exists but files are too small ($([math]::Round($kbSize/1MB, 2)) MB < 10 MB), will re-download"
            }
        } else {
            WriteLog "KB folder exists but is EMPTY (0 files), will download"
        }
    }

    # If no cached VHDX is found, download the required updates now
    if (-Not $cachedVHDXFileFound -and $requiredUpdates.Count -gt 0 -and -not $kbCacheValid) {
        Set-Progress -Percentage 12 -Message "Downloading Windows Updates..."
        WriteLog "No suitable VHDX cache found. Downloading $($requiredUpdates.Count) update(s)."

        If (-not (Test-Path -Path $KBPath)) {
            WriteLog "Creating $KBPath"; New-Item -Path $KBPath -ItemType Directory -Force | Out-Null
        }

        foreach ($update in $requiredUpdates) {
            $destinationPath = $KBPath
            if (($netUpdateInfos -and ($netUpdateInfos.Name -contains $update.Name)) -or `
                ($netFeatureUpdateInfos -and ($netFeatureUpdateInfos.Name -contains $update.Name))) {
                if ($isLTSC -and $WindowsRelease -in 2016, 2019, 2021) {
                    $destinationPath = Join-Path -Path $KBPath -ChildPath "NET"
                }
            }
            if ($microcodeUpdateInfos -and ($microcodeUpdateInfos.Name -contains $update.Name)) {
                $destinationPath = Join-Path -Path $KBPath -ChildPath "Microcode"
            }

            if (-not (Test-Path -Path $destinationPath)) {
                New-Item -Path $destinationPath -ItemType Directory -Force | Out-Null
            }
            WriteLog "Downloading $($update.Name) to $destinationPath"
            Start-BitsTransferWithRetry -Source $update.Url -Destination $destinationPath
        }
    }

    # Set file path variables for the patching process using robust resolution
    # IMPORTANT: This section runs regardless of whether downloads occurred or were skipped (KB cache valid)
    # This prevents "Cannot bind argument to parameter 'PackagePath' because it is an empty string" errors
    if ($ssuUpdateInfos.Count -gt 0) {
        $SSUFile = $ssuUpdateInfos[0].Name
        if (-not $SSUFilePath) {
            $SSUFilePath = Resolve-KBFilePath -KBPath $KBPath -FileName $SSUFile -KBArticleId $ssuUpdateInfos[0].KBArticleID -UpdateType "SSU"
            if (-not $SSUFilePath) {
                # Fallback to direct path construction
                $SSUFilePath = "$KBPath\$SSUFile"
            }
        }
        WriteLog "Latest SSU identified as $SSUFilePath"
    }
    if ($cuUpdateInfos.Count -gt 0) {
        if (-not $CUPath) {
            $cuFileName = if ($cuUpdateInfos[0].Name) { $cuUpdateInfos[0].Name } else { $null }
            $CUPath = Resolve-KBFilePath -KBPath $KBPath -FileName $cuFileName -KBArticleId $cuKbArticleId -UpdateType "CU"
        }
        if ($CUPath) {
            WriteLog "Latest CU identified as $CUPath"
        } else {
            WriteLog "WARNING: Could not resolve CU path - CU application will be skipped"
            $UpdateLatestCU = $false
        }
    } elseif ($UpdateLatestCU) {
        # User requested CU update but catalog search returned no results
        WriteLog "WARNING: No Cumulative Update found in Microsoft Update Catalog for this Windows version - CU update will be skipped"
        $UpdateLatestCU = $false
    }
    if ($cupUpdateInfos.Count -gt 0) {
        if (-not $CUPPath) {
            $cupFileName = if ($cupUpdateInfos[0].Name) { $cupUpdateInfos[0].Name } else { $null }
            $CUPPath = Resolve-KBFilePath -KBPath $KBPath -FileName $cupFileName -KBArticleId $cupKbArticleId -UpdateType "Preview CU"
        }
        if ($CUPPath) {
            WriteLog "Latest Preview CU identified as $CUPPath"
        } else {
            WriteLog "WARNING: Could not resolve Preview CU path - Preview CU application will be skipped"
            $UpdatePreviewCU = $false
        }
    } elseif ($UpdatePreviewCU) {
        # User requested Preview CU update but catalog search returned no results
        WriteLog "WARNING: No Preview Cumulative Update found in Microsoft Update Catalog for this Windows version - Preview CU update will be skipped"
        $UpdatePreviewCU = $false
    }
    if ($netUpdateInfos.Count -gt 0 -or $netFeatureUpdateInfos.Count -gt 0) {
        if ($isLTSC -and $WindowsRelease -in 2016, 2019, 2021) {
            $NETPath = Join-Path -Path $KBPath -ChildPath "NET"
            WriteLog ".NET updates for LTSC are in $NETPath"
        }
        else {
            if (-not $NETPath) {
                $NETFileName = if ($netUpdateInfos.Count -gt 0 -and $netUpdateInfos[0].Name) { $netUpdateInfos[0].Name } else { $null }
                $NETPath = Resolve-KBFilePath -KBPath $KBPath -FileName $NETFileName -KBArticleId $netKbArticleId -UpdateType ".NET"
            }
            if ($NETPath) {
                WriteLog "Latest .NET Framework identified as $NETPath"
            } else {
                WriteLog "WARNING: Could not resolve .NET path - .NET update application will be skipped"
                $UpdateLatestNet = $false
            }
        }
    } elseif ($UpdateLatestNet) {
        # User requested .NET update but catalog search returned no results
        WriteLog "WARNING: No .NET Framework update found in Microsoft Update Catalog for this Windows version - .NET update will be skipped"
        $UpdateLatestNet = $false
    }
    if ($microcodeUpdateInfos.Count -gt 0) {
        $MicrocodePath = "$KBPath\Microcode"
        WriteLog "Microcode updates are in $MicrocodePath"
    } elseif ($UpdateLatestMicrocode) {
        # User requested Microcode update but catalog search returned no results
        WriteLog "WARNING: No Microcode update found in Microsoft Update Catalog for this Windows version - Microcode update will be skipped"
        $UpdateLatestMicrocode = $false
    }
    
    if (-Not $cachedVHDXFileFound) {
        Set-Progress -Percentage 15 -Message "Creating VHDX and applying base Windows image..."
        if ($ISOPath) {
            $wimPath = Get-WimFromISO -isoPath $ISOPath
        }
        else {
            $wimPath = Get-WindowsESD -WindowsRelease $WindowsRelease -WindowsArch $WindowsArch `
                                      -WindowsLang $WindowsLang -MediaType $mediaType `
                                      -TempPath $PSScriptRoot -Headers $Headers -UserAgent $UserAgent `
                                      -WindowsVersion $WindowsVersion -FFUDevelopmentPath $FFUDevelopmentPath
        }
        #If index not specified by user, try and find based on WindowsSKU
        if (-not($index) -and ($WindowsSKU)) {
            $index = Get-Index -WindowsImagePath $wimPath -WindowsSKU $WindowsSKU -ISOPath $ISOPath
        }

        $vhdxDisk = New-ScratchVhdx -VhdxPath $VHDXPath -SizeBytes $disksize -LogicalSectorSizeBytes $LogicalSectorSizeBytes

        $systemPartitionDriveLetter = New-SystemPartition -VhdxDisk $vhdxDisk
    
        New-MSRPartition -VhdxDisk $vhdxDisk
    
        Set-Progress -Percentage 16 -Message "Applying base Windows image to VHDX..."
        # Pass ISOPath to enable automatic ISO re-mount if WIM source becomes unavailable during expansion
        $osPartition = New-OSPartition -VhdxDisk $vhdxDisk -OSPartitionSize $OSPartitionSize -WimPath $WimPath -WimIndex $index -CompactOS $CompactOS -ISOPath $ISOPath
        $osPartitionDriveLetter = $osPartition[1].DriveLetter
        $WindowsPartition = $osPartitionDriveLetter + ':\'

        #$recoveryPartition = New-RecoveryPartition -VhdxDisk $vhdxDisk -OsPartition $osPartition[1] -RecoveryPartitionSize $RecoveryPartitionSize -DataPartition $dataPartition
        $recoveryPartition = New-RecoveryPartition -VhdxDisk $vhdxDisk -OsPartition $osPartition[1] -RecoveryPartitionSize $RecoveryPartitionSize -DataPartition $dataPartition

        WriteLog 'All necessary partitions created.'

        Add-BootFiles -OsPartitionDriveLetter $osPartitionDriveLetter -SystemPartitionDriveLetter $systemPartitionDriveLetter[1]
    
        #Add Windows packages
        if ($UpdateLatestCU -or $UpdateLatestNet -or $UpdatePreviewCU ) {
            try {
                Set-Progress -Percentage 25 -Message "Applying Windows Updates to VHDX..."
                WriteLog "Adding KBs to $WindowsPartition"
                WriteLog 'This can take 10+ minutes depending on how old the media is and the size of the KB. Please be patient'

                # Pre-flight validation: Ensure all enabled update paths are valid before attempting application
                # This prevents "Cannot bind argument to parameter 'PackagePath' because it is an empty string" errors
                $ssuRequired = ($WindowsRelease -eq 2016 -and $installationType -eq "Server") -or ($WindowsRelease -in 2016, 2019, 2021 -and $isLTSC)
                $pathValidation = Test-KBPathsValid -UpdateLatestCU $UpdateLatestCU -CUPath $CUPath `
                                                    -UpdatePreviewCU $UpdatePreviewCU -CUPPath $CUPPath `
                                                    -UpdateLatestNet $UpdateLatestNet -NETPath $NETPath `
                                                    -UpdateLatestMicrocode $UpdateLatestMicrocode -MicrocodePath $MicrocodePath `
                                                    -SSURequired $ssuRequired -SSUFilePath $SSUFilePath

                if (-not $pathValidation.IsValid) {
                    WriteLog "KB path validation failed:"
                    foreach ($err in $pathValidation.Errors) {
                        WriteLog "  ERROR: $err"
                    }
                    WriteLog "Tip: Ensure Windows Update downloads completed successfully and files exist in $KBPath"
                    WriteLog "Tip: Check that KB article IDs match the downloaded file names"
                    throw "KB path validation failed: $($pathValidation.ErrorMessage)"
                }

                # Initialize DISM service before applying packages
                if (-not (Initialize-DISMService -MountPath $WindowsPartition)) {
                    throw "Failed to initialize DISM service for package application"
                }

                # If WindowsRelease is 2016, we need to add the SSU first
                if ($WindowsRelease -eq 2016 -and $installationType -eq "Server") {
                    WriteLog 'WindowsRelease is 2016, adding SSU first'
                    Add-WindowsPackageWithRetry -Path $WindowsPartition -PackagePath $SSUFilePath
                }
                if ($WindowsRelease -in 2016, 2019, 2021 -and $isLTSC) {
                    WriteLog "WindowsRelease is $WindowsRelease and is $WindowsSKU, adding SSU first"
                    Add-WindowsPackageWithRetry -Path $WindowsPartition -PackagePath $SSUFilePath
                }
                # Break out CU and NET updates to be added separately to abide by Checkpoint Update recommendations
                if ($UpdateLatestCU) {
                    WriteLog "Adding $CUPath to $WindowsPartition"
                    Add-WindowsPackageWithRetry -Path $WindowsPartition -PackagePath $CUPath
                }
                if ($UpdatePreviewCU) {
                    WriteLog "Adding $CUPPath to $WindowsPartition"
                    Add-WindowsPackageWithRetry -Path $WindowsPartition -PackagePath $CUPPath
                }
                if ($UpdateLatestNet) {
                    WriteLog "Adding $NETPath to $WindowsPartition"
                    Add-WindowsPackageWithRetry -Path $WindowsPartition -PackagePath $NETPath
                }
                if ($UpdateLatestMicrocode -and $WindowsRelease -in 2016, 2019) {
                    WriteLog "Adding $MicrocodePath to $WindowsPartition"
                    Add-WindowsPackageWithRetry -Path $WindowsPartition -PackagePath $MicrocodePath
                }
                WriteLog "KBs added to $WindowsPartition"
                if ($AllowVHDXCaching) {
                    $cachedVHDXInfo = [VhdxCacheItem]::new()
                    $includedUpdates = Get-ChildItem -Path $KBPath -File -Recurse
                
                    foreach ($includedUpdate in $includedUpdates) {
                        $cachedVHDXInfo.IncludedUpdates += ([VhdxCacheUpdateItem]::new($includedUpdate.Name))
                    }
                }
                # Only remove KB folder if RemoveUpdates is true; otherwise keep for future builds
                if ($RemoveUpdates) {
                    WriteLog "Removing $KBPath (RemoveUpdates=true)"
                    if (-not [string]::IsNullOrWhiteSpace($KBPath) -and (Test-Path -Path $KBPath)) {
                        Remove-Item -Path $KBPath -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
                    }
                } else {
                    $kbFiles = Get-ChildItem -Path $KBPath -Recurse -File -ErrorAction SilentlyContinue
                    $kbSize = if ($kbFiles) { ($kbFiles | Measure-Object -Property Length -Sum).Sum } else { 0 }
                    WriteLog "Keeping $KBPath for future builds ($($kbFiles.Count) files, $([math]::Round($kbSize/1MB, 2)) MB) - RemoveUpdates=false"
                }
                WriteLog 'Clean Up the WinSxS Folder'
                WriteLog 'This can take 10+ minutes depending on how old the media is and the size of the KB. Please be patient'
                Dism /Image:$WindowsPartition /Cleanup-Image /StartComponentCleanup /ResetBase | Out-Null
                WriteLog 'Clean Up the WinSxS Folder completed'
            }
            catch {
                Write-Host "Adding KB to VHDX failed with error $_"
                WriteLog "Adding KB to VHDX failed with error $_"
                if ($_.Exception.HResult -eq -2146498525) {
                    Write-Host 'Missing latest Servicing Stack Update'
                    Write-Host 'Media likely older than 2023-09 for Windows Server 2022 (KB5030216), or 2021-08 for Windows Server 2019 (KB5005112)'
                    Write-Host 'Recommended to use the latest media'
                    WriteLog 'Missing latest Servicing Stack Update'
                    WriteLog 'Media likely older than 2023-09 for Windows Server 2022 (KB5030216), or 2021-08 for Windows Server 2019 (KB5005112)'
                    WriteLog 'Recommended to use the latest media'
                }
                throw $_
            }  
        }

        #Enable Windows Optional Features (e.g. .Net3, etc)
        If ($OptionalFeatures) {
            $Source = Join-Path (Split-Path $wimpath) 'sxs'
            Enable-WindowsFeaturesByName -FeatureNames $OptionalFeatures -Source $Source `
                                        -WindowsPartition $WindowsPartition
        }
        If ($ISOPath) {
            WriteLog 'Dismounting Windows ISO'
            Dismount-DiskImage -ImagePath $ISOPath | Out-null
            WriteLog 'Done'
        }
        #If $wimPath is an esd file, remove it
        If ($wimPath -match '.esd') {
            WriteLog "Deleting $wimPath file"
            if (-not [string]::IsNullOrWhiteSpace($wimPath)) {
                Remove-Item -Path $wimPath -Force -ErrorAction SilentlyContinue
            }
            WriteLog "$wimPath deleted"
        }
    
    }
    else {
        #Use cached vhdx file
        WriteLog 'Using cached VHDX file to speed up build process'
        WriteLog "VHDX file is: $($cachedVHDXInfo.VhdxFileName)"

        Robocopy.exe $($VHDXCacheFolder) $($VMPath) $($cachedVHDXInfo.VhdxFileName) /E /COPY:DAT /R:5 /W:5 /J
        if (-not (Test-ExternalCommandSuccess -CommandName 'Robocopy (copy cached VHDX)')) {
            throw "Failed to copy cached VHDX file from $VHDXCacheFolder to $VMPath"
        }
        $VHDXPath = Join-Path $($VMPath) $($cachedVHDXInfo.VhdxFileName)

        $vhdxDisk = Get-VHD -Path $VHDXPath | Mount-VHD -Passthru | Get-Disk

        # Register cleanup for mounted VHDX in case of failure
        $vhdxCleanupId = Register-VHDXCleanup -VHDXPath $VHDXPath
        WriteLog "Registered VHDX cleanup handler (ID: $vhdxCleanupId)"

        $osPartition = $vhdxDisk | Get-Partition | Where-Object { $_.GptType -eq '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}' }
        $osPartitionDriveLetter = $osPartition.DriveLetter
        $WindowsPartition = $osPartitionDriveLetter + ':\'

    }

    #Set Product key
    If ($ProductKey) {
        WriteLog "Setting Windows Product Key"
        Set-WindowsProductKey -Path $WindowsPartition -ProductKey $ProductKey
    }

    Set-Progress -Percentage 40 -Message "Finalizing VHDX..."
    if ($AllowVHDXCaching -and !$cachedVHDXFileFound) {
        WriteLog 'Caching VHDX file'

        # Optimize volume for better caching - non-critical, continue on failure
        try {
            WriteLog 'Defragmenting Windows partition...'
            Optimize-Volume -DriveLetter $osPartition.DriveLetter -Defrag -NormalPriority -ErrorAction Stop
        }
        catch {
            WriteLog "WARNING: Defragmentation failed - $($_.Exception.Message). Continuing with caching."
        }

        try {
            WriteLog 'Performing slab consolidation on Windows partition...'
            Optimize-Volume -DriveLetter $osPartition.DriveLetter -SlabConsolidate -NormalPriority -ErrorAction Stop
        }
        catch {
            WriteLog "WARNING: Slab consolidation failed - $($_.Exception.Message). Continuing with caching."
        }

        WriteLog 'Dismounting VHDX'
        Dismount-ScratchVhdx -VhdxPath $VHDXPath

        WriteLog 'Copying to cache dir'

        #Assuming there are now name collisons
        Robocopy.exe $($VMPath) $($VHDXCacheFolder) $("$VMName.vhdx") /E /COPY:DAT /R:5 /W:5 /J
        if (-not (Test-ExternalCommandSuccess -CommandName 'Robocopy (copy VHDX to cache)')) {
            WriteLog "WARNING: Failed to copy VHDX to cache directory. Caching may be incomplete."
            # Non-fatal - continue with build even if caching fails
        }

        #Only create new instance if not created during patching
        if ($null -eq $cachedVHDXInfo) {
            $cachedVHDXInfo = [VhdxCacheItem]::new()
        }
        $cachedVHDXInfo.VhdxFileName = $("$VMName.vhdx")
        $cachedVHDXInfo.LogicalSectorSizeBytes = $LogicalSectorSizeBytes
        $cachedVHDXInfo.WindowsSKU = $WindowsSKU
        $cachedVHDXInfo.WindowsRelease = $WindowsRelease
        $cachedVHDXInfo.WindowsVersion = $WindowsVersion
        $cachedVHDXInfo.OptionalFeatures = $OptionalFeatures
        
        $cachedVHDXInfo | ConvertTo-Json | Out-File -FilePath ("{0}\{1}_config.json" -f $($VHDXCacheFolder), $VMName)
        WriteLog "Cached VHDX file $("$VMName.vhdx")"

        #Remount the VHDX file if $installapps is false so the VHDX can be captured to an FFU
        If (-not $InstallApps) {
            Mount-Vhd -Path $VHDXPath
        }
    } 
}
catch {
    Write-Host 'Creating VHDX Failed'
    WriteLog "Creating VHDX Failed with error $_"
    WriteLog "Dismounting $VHDXPath"
    Dismount-ScratchVhdx -VhdxPath $VHDXPath
    WriteLog "Removing $VMPath"
    if (-not [string]::IsNullOrWhiteSpace($VMPath)) {
        Remove-Item -Path $VMPath -Force -Recurse -ErrorAction SilentlyContinue | Out-Null
    }
    WriteLog 'Removal complete'
    If ($ISOPath) {
        WriteLog 'Dismounting Windows ISO'
        Dismount-DiskImage -ImagePath $ISOPath | Out-null
        WriteLog 'Done'
    }
    else {
        #Remove ESD file
        WriteLog "Deleting ESD file"
        if (-not [string]::IsNullOrWhiteSpace($wimPath)) {
            Remove-Item -Path $wimPath -Force -ErrorAction SilentlyContinue
        }
        WriteLog "ESD File deleted"
    }
    throw $_
    
}

#Inject unattend after caching so cached VHDX never contains audit-mode unattend
if ($InstallApps) {
    # Determine mount state and only mount if needed to avoid redundant mount/dismount cycles
    $vhdMeta = Get-VHD -Path $VHDXPath
    if ($vhdMeta.Attached) {
        WriteLog 'VHDX already mounted; reusing existing mount for unattend injection'
        $disk = Get-Disk -Number $vhdMeta.DiskNumber
    }
    else {
        WriteLog 'Mounting VHDX to inject unattend for audit-mode boot'
        $disk = Mount-VHD -Path $VHDXPath -Passthru | Get-Disk

        # Register cleanup for mounted VHDX in case of failure (only if we did a fresh mount)
        $vhdxUnattendCleanupId = Register-VHDXCleanup -VHDXPath $VHDXPath
        WriteLog "Registered VHDX cleanup handler for unattend injection (ID: $vhdxUnattendCleanupId)"
    }
    $osPartition = $disk | Get-Partition | Where-Object { $_.GptType -eq '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}' }
    $osPartitionDriveLetter = $osPartition.DriveLetter
    WriteLog 'Copying unattend file to boot to audit mode'
    try {
        New-Item -Path "$($osPartitionDriveLetter):\Windows\Panther\Unattend" -ItemType Directory -Force -ErrorAction Stop | Out-Null

        # Determine source unattend file based on architecture
        $unattendSource = if ($WindowsArch -eq 'x64') {
            "$FFUDevelopmentPath\BuildFFUUnattend\unattend_x64.xml"
        } else {
            "$FFUDevelopmentPath\BuildFFUUnattend\unattend_arm64.xml"
        }
        $unattendDest = "$($osPartitionDriveLetter):\Windows\Panther\Unattend\Unattend.xml"

        # Validate source exists before copying
        if (-not (Test-Path $unattendSource -PathType Leaf)) {
            throw "Unattend source file not found: $unattendSource"
        }

        Copy-Item -Path $unattendSource -Destination $unattendDest -Force -ErrorAction Stop | Out-Null

        # Verify copy succeeded
        if (-not (Test-Path $unattendDest -PathType Leaf)) {
            throw "Unattend file copy verification failed - destination file not found: $unattendDest"
        }

        WriteLog 'Copy completed'
    }
    catch {
        WriteLog "ERROR: Failed to copy unattend file for audit mode boot - $($_.Exception.Message)"
        # Ensure dismount happens even on error
        Dismount-ScratchVhdx -VhdxPath $VHDXPath
        throw "Critical failure: Cannot proceed without unattend file for audit mode boot. Error: $($_.Exception.Message)"
    }
    # Always dismount so downstream VM creation logic has a clean starting point
    Dismount-ScratchVhdx -VhdxPath $VHDXPath
}

#If installing apps (Office or 3rd party), we need to build a VM and capture that FFU, if not, just cut the FFU from the VHDX file
if ($InstallApps) {
    Set-Progress -Percentage 41 -Message "Starting VM for app installation..."
    #Create VM and attach VHDX
    try {
        WriteLog 'Creating new FFU VM'
        $FFUVM = New-FFUVM -VMName $VMName -VMPath $VMPath -Memory $memory `
                           -VHDXPath $VHDXPath -Processors $processors -AppsISO $AppsISO
        WriteLog 'FFU VM Created'

        # Register cleanup for VM in case of failure during subsequent operations
        $vmCleanupId = Register-VMCleanup -VMName $VMName
        WriteLog "Registered VM cleanup handler (ID: $vmCleanupId)"
    }
    catch {
        Write-Host 'VM creation failed'
        Writelog "VM creation failed with error $_"
        Remove-FFUVM -VMName $VMName -VMPath $VMPath -InstallApps $InstallApps `
                     -VhdxDisk $vhdxDisk -FFUDevelopmentPath $FFUDevelopmentPath `
                     -Username $Username -ShareName $ShareName
        throw $_

    }
    #Create ffu user and share to capture FFU to
    try {
        # DIAGNOSTIC: Verify Set-CaptureFFU is available before calling
        WriteLog "Verifying Set-CaptureFFU function availability..."

        $funcAvailable = Get-Command Set-CaptureFFU -ErrorAction SilentlyContinue

        if (-not $funcAvailable) {
            WriteLog "WARNING: Set-CaptureFFU not found in current session. Attempting module reload..."

            # Force complete module unload and reload
            Remove-Module FFU.VM -Force -ErrorAction SilentlyContinue

            $modulePath = Join-Path $PSScriptRoot "Modules\FFU.VM\FFU.VM.psm1"
            WriteLog "Importing FFU.VM module from: $modulePath"

            if (-not (Test-Path $modulePath)) {
                WriteLog "ERROR: Module file not found at: $modulePath"
                throw "FFU.VM module file not found. Expected at: $modulePath"
            }

            Import-Module $modulePath -Force -Global -ErrorAction Stop

            # Verify function is now available
            $funcAvailable = Get-Command Set-CaptureFFU -ErrorAction SilentlyContinue

            if (-not $funcAvailable) {
                WriteLog "ERROR: Set-CaptureFFU still not available after module reload"
                WriteLog "Module path: $modulePath"
                WriteLog "Available FFU.VM module info:"
                $moduleInfo = Get-Module FFU.VM
                if ($moduleInfo) {
                    WriteLog "  Module Name: $($moduleInfo.Name)"
                    WriteLog "  Module Path: $($moduleInfo.Path)"
                    WriteLog "  Exported Commands:"
                    Get-Command -Module FFU.VM | Select-Object -ExpandProperty Name | ForEach-Object {
                        WriteLog "    - $_"
                    }
                }
                else {
                    WriteLog "  ERROR: FFU.VM module not loaded"
                }

                throw "Set-CaptureFFU function not available after reload. Module import may have failed."
            }

            WriteLog "Set-CaptureFFU successfully loaded after module reload"
        }
        else {
            WriteLog "Set-CaptureFFU verified available in current session"
        }

        # Generate secure random password for FFU capture user
        # SECURITY: Password is generated directly to SecureString - never exists as plain text during generation
        # This password will be used by both Set-CaptureFFU and Update-CaptureFFUScript
        WriteLog "Generating cryptographically secure password for FFU capture user"
        $capturePasswordSecure = New-SecureRandomPassword -Length 32 -IncludeSpecialChars $false
        WriteLog "Password generated (length: 32 characters, using cryptographic RNG)"

        # Call function with parameters (including generated password)
        Set-CaptureFFU -Username $Username -ShareName $ShareName -FFUCaptureLocation $FFUCaptureLocation -Password $capturePasswordSecure
    }
    catch {
        Write-Host 'Set-CaptureFFU function failed'
        WriteLog "Set-CaptureFFU function failed with error $_"
        # SECURITY: Dispose credentials on failure
        Remove-SecureStringFromMemory -SecureStringVariable ([ref]$capturePasswordSecure)
        Remove-FFUVM -VMName $VMName -VMPath $VMPath -InstallApps $InstallApps `
                     -VhdxDisk $vhdxDisk -FFUDevelopmentPath $FFUDevelopmentPath `
                     -Username $Username -ShareName $ShareName
        throw $_

    }
    If ($CreateCaptureMedia) {
        #Create Capture Media
        try {
            Set-Progress -Percentage 45 -Message "Creating WinPE capture media..."

            # Update CaptureFFU.ps1 script with runtime configuration before creating WinPE media
            # SECURITY: Pass SecureString - Update-CaptureFFUScript handles conversion internally
            WriteLog "Updating CaptureFFU.ps1 script with capture configuration"
            try {
                $updateParams = @{
                    VMHostIPAddress       = $VMHostIPAddress
                    ShareName             = $ShareName
                    Username              = $Username
                    Password              = $capturePasswordSecure  # SecureString - converted internally
                    FFUDevelopmentPath    = $FFUDevelopmentPath
                }

                # Add CustomFFUNameTemplate if provided
                if (![string]::IsNullOrEmpty($CustomFFUNameTemplate)) {
                    $updateParams.CustomFFUNameTemplate = $CustomFFUNameTemplate
                }

                Update-CaptureFFUScript @updateParams
                WriteLog "CaptureFFU.ps1 script updated successfully"
            }
            catch {
                WriteLog "ERROR: Failed to update CaptureFFU.ps1 script: $_"
                throw "Failed to update CaptureFFU.ps1 script. Capture media creation aborted. Error: $_"
            }

            #This should happen while the FFUVM is building
            New-PEMedia -Capture $true -Deploy $false -adkPath $adkPath -FFUDevelopmentPath $FFUDevelopmentPath `
                        -WindowsArch $WindowsArch -CaptureISO $CaptureISO -DeployISO $null `
                        -CopyPEDrivers $CopyPEDrivers -UseDriversAsPEDrivers $UseDriversAsPEDrivers `
                        -PEDriversFolder $PEDriversFolder -DriversFolder $DriversFolder `
                        -CompressDownloadedDriversToWim $CompressDownloadedDriversToWim
        }
        catch {
            Write-Host 'Creating capture media failed'
            WriteLog "Creating capture media failed with error $_"
            Remove-FFUVM -VMName $VMName -VMPath $VMPath -InstallApps $InstallApps `
                         -VhdxDisk $vhdxDisk -FFUDevelopmentPath $FFUDevelopmentPath `
                         -Username $Username -ShareName $ShareName
            throw $_

        }
        finally {
            # SECURITY: Dispose of credentials after capture media is created
            # This minimizes the time sensitive data is in memory
            if ($capturePasswordSecure) {
                $capturePasswordSecure.Dispose()
                $capturePasswordSecure = $null
                WriteLog "SECURITY: SecureString credential disposed"
            }
            if ($capturePassword) {
                # Clear plain text password from memory
                $capturePassword = $null
                [System.GC]::Collect()
                WriteLog "SECURITY: Plain text credential cleared from memory"
            }
        }
    }
    else {
        # SECURITY: Dispose credentials even when not creating capture media
        if ($capturePasswordSecure) {
            $capturePasswordSecure.Dispose()
            $capturePasswordSecure = $null
            WriteLog "SECURITY: SecureString credential disposed (no capture media)"
        }
        if ($capturePassword) {
            $capturePassword = $null
            WriteLog "SECURITY: Plain text credential cleared (no capture media)"
        }
    }
}
#Capture FFU file
try {
    #Check for FFU Folder and create it if it's missing
    If (-not (Test-Path -Path $FFUCaptureLocation)) {
        WriteLog "Creating FFU capture location at $FFUCaptureLocation"
        New-Item -Path $FFUCaptureLocation -ItemType Directory -Force
        WriteLog "Successfully created FFU capture location at $FFUCaptureLocation"
    }

    # Validate and shorten Windows SKU for FFU file naming
    # IMPORTANT: This must happen BEFORE the InstallApps branch because both code paths
    # require ShortenedWindowsSKU parameter for New-FFU function. Previously this was
    # only done in the InstallApps = $false path, causing "Cannot validate argument on
    # parameter 'ShortenedWindowsSKU'" error when InstallApps = $true.
    if ([string]::IsNullOrWhiteSpace($WindowsSKU)) {
        WriteLog "ERROR: WindowsSKU parameter is empty or null"
        throw "WindowsSKU parameter is required for FFU file naming. Please specify a valid Windows edition (Pro, Enterprise, Education, etc.)"
    }

    WriteLog "Shortening Windows SKU: '$WindowsSKU' for FFU file name"
    $shortenedWindowsSKU = Get-ShortenedWindowsSKU -WindowsSKU $WindowsSKU
    WriteLog "Shortened Windows SKU: '$shortenedWindowsSKU'"

    #Check if VM is done provisioning
    If ($InstallApps) {
        Set-Progress -Percentage 50 -Message "Installing applications in VM; please wait for VM to shut down..."
        do {
            $FFUVM = Get-VM -Name $FFUVM.Name
            Start-Sleep -Seconds ([FFUConstants]::VM_STATE_POLL_INTERVAL)
            WriteLog 'Waiting for VM to shutdown'
        } while ($FFUVM.State -ne 'Off')
        WriteLog 'VM Shutdown'
        Set-Progress -Percentage 65 -Message "Optimizing VHDX before capture..."
        Optimize-FFUCaptureDrive -VhdxPath $VHDXPath
        #Capture FFU file
        New-FFU -VMName $FFUVM.Name -InstallApps $InstallApps -CaptureISO $CaptureISO `
                -VMSwitchName $VMSwitchName -FFUCaptureLocation $FFUCaptureLocation `
                -AllowVHDXCaching $AllowVHDXCaching -CustomFFUNameTemplate $CustomFFUNameTemplate `
                -ShortenedWindowsSKU $shortenedWindowsSKU -VHDXPath $VHDXPath `
                -DandIEnv $DandIEnv -VhdxDisk $vhdxDisk -CachedVHDXInfo $cachedVHDXInfo `
                -InstallationType $installationType -InstallDrivers $InstallDrivers `
                -Optimize $Optimize -FFUDevelopmentPath $FFUDevelopmentPath `
                -DriversFolder $DriversFolder
    }
    else {
        Set-Progress -Percentage 81 -Message "Starting FFU capture from VHDX..."

        # NOTE: WindowsSKU validation and shortening now happens BEFORE the InstallApps branch
        # (lines 2464-2471) to eliminate code duplication and ensure both paths have valid
        # $shortenedWindowsSKU variable. This prevents "Cannot validate argument on parameter
        # 'ShortenedWindowsSKU'" errors.

        #Create FFU file
        New-FFU -InstallApps $InstallApps -FFUCaptureLocation $FFUCaptureLocation `
                -AllowVHDXCaching $AllowVHDXCaching -CustomFFUNameTemplate $CustomFFUNameTemplate `
                -ShortenedWindowsSKU $shortenedWindowsSKU -VHDXPath $VHDXPath `
                -DandIEnv $DandIEnv -VhdxDisk $vhdxDisk -CachedVHDXInfo $cachedVHDXInfo `
                -InstallationType $installationType -InstallDrivers $InstallDrivers `
                -Optimize $Optimize -FFUDevelopmentPath $FFUDevelopmentPath `
                -DriversFolder $DriversFolder
    }    
}
Catch {
    Write-Host 'Capturing FFU file failed'
    Writelog "Capturing FFU file failed with error $_"
    If ($InstallApps) {
        Remove-FFUVM -VMName $VMName -VMPath $VMPath -InstallApps $InstallApps `
                     -VhdxDisk $vhdxDisk -FFUDevelopmentPath $FFUDevelopmentPath `
                     -Username $Username -ShareName $ShareName
    }
    else {
        Remove-FFUVM -VMPath $VMPath -InstallApps $InstallApps `
                     -VhdxDisk $vhdxDisk -FFUDevelopmentPath $FFUDevelopmentPath `
                     -Username $Username -ShareName $ShareName
    }

    throw $_

}
#Clean up ffu_user and Share and clean up apps
If ($InstallApps) {
    try {
        Remove-FFUUserShare -Username $Username -ShareName $ShareName
    }
    catch {
        Write-Host 'Cleaning up FFU User and/or share failed'
        WriteLog "Cleaning up FFU User and/or share failed with error $_"
        Remove-FFUVM -VMName $VMName -VMPath $VMPath -InstallApps $InstallApps `
                     -VhdxDisk $vhdxDisk -FFUDevelopmentPath $FFUDevelopmentPath `
                     -Username $Username -ShareName $ShareName
        throw $_
    }
    #Clean up Apps
    if ($RemoveApps) {
        try {
            WriteLog "Cleaning up $AppsPath"
            Remove-Apps
        }
        catch {
            Write-Host 'Cleaning up Apps failed'
            Writelog "Cleaning up Apps failed with error $_"
            throw $_
        }
    }
    # Note: Update file cleanup is handled by Invoke-FFUPostBuildCleanup (line 2830)
    # which properly respects the RemoveUpdates parameter
}
#Clean up VM or VHDX
try {
    Remove-FFUVM -VMName $VMName -VMPath $VMPath -InstallApps $InstallApps `
                 -VhdxDisk $vhdxDisk -FFUDevelopmentPath $FFUDevelopmentPath `
                 -Username $Username -ShareName $ShareName
    WriteLog 'FFU build complete!'
}
catch {
    Write-Host 'VM or vhdx cleanup failed'
    Writelog "VM or vhdx cleanup failed with error $_"
    throw $_
}


#Create Deployment Media
If ($CreateDeploymentMedia) {
    Set-Progress -Percentage 91 -Message "Creating deployment media..."
    try {
        New-PEMedia -Capture $false -Deploy $true -adkPath $adkPath -FFUDevelopmentPath $FFUDevelopmentPath `
                    -WindowsArch $WindowsArch -CaptureISO $null -DeployISO $DeployISO `
                    -CopyPEDrivers $CopyPEDrivers -UseDriversAsPEDrivers $UseDriversAsPEDrivers `
                    -PEDriversFolder $PEDriversFolder -DriversFolder $DriversFolder `
                    -CompressDownloadedDriversToWim $CompressDownloadedDriversToWim
    }
    catch {
        Write-Host 'Creating deployment media failed'
        WriteLog "Creating deployment media failed with error $_"
        throw $_
    
    }
}
If ($BuildUSBDrive) {
    Set-Progress -Percentage 95 -Message "Building USB drive..."
    try {
        If (Test-Path -Path $DeployISO) {
            $ffuFilesToCopy = @()

            # Always include the FFU that was just built (fallback to most recent .ffu in capture folder)
            $currentFFU = $null
            if ($null -ne $FFUFile -and -not [string]::IsNullOrWhiteSpace($FFUFile) -and (Test-Path -LiteralPath $FFUFile)) {
                $currentFFU = $FFUFile
            }
            else {
                try {
                    $ffuDir = if (-not [string]::IsNullOrWhiteSpace($FFUCaptureLocation)) { $FFUCaptureLocation } else { Join-Path $FFUDevelopmentPath 'FFU' }
                    if (Test-Path -LiteralPath $ffuDir) {
                        $latest = Get-ChildItem -Path $ffuDir -Filter '*.ffu' -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                        if ($null -ne $latest) { $currentFFU = $latest.FullName }
                    }
                }
                catch {
                    WriteLog "Failed to resolve latest FFU file to copy: $($_.Exception.Message)"
                }
            }
            if ($null -ne $currentFFU) {
                $ffuFilesToCopy += $currentFFU
            }

            if ($CopyAdditionalFFUFiles -and ($null -ne $AdditionalFFUFiles) -and ($AdditionalFFUFiles.Count -gt 0)) {
                $ffuFilesToCopy += $AdditionalFFUFiles
            }

            $ffuFilesToCopy = $ffuFilesToCopy | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
            New-DeploymentUSB -CopyFFU -FFUFilesToCopy $ffuFilesToCopy
        }
        else {
            WriteLog "$BuildUSBDrive set to true, however unable to find $DeployISO. USB drive not built."
        }
        
    }
    catch {
        Write-Host 'Building USB deployment drive failed'
        Writelog "Building USB deployment drive failed with error $_"
        throw $_
    }
}
If ($RemoveFFU) {
    try {
        Remove-FFU -VMName $VMName -InstallApps $InstallApps -vhdxDisk $vhdxDisk `
                   -VMPath $VMPath -FFUDevelopmentPath $FFUDevelopmentPath
    }
    catch {
        Write-Host 'Removing FFU files failed'
        Writelog "Removing FFU files failed with error $_"
        throw $_
    }
       
}
Set-Progress -Percentage 99 -Message "Finalizing and cleaning up..."
# Delegated post-build cleanup to common module
Invoke-FFUPostBuildCleanup -RootPath $FFUDevelopmentPath -AppsPath $AppsPath -DriversPath $Driversfolder -FFUCapturePath $FFUCaptureLocation -CaptureISOPath $CaptureISO -DeployISOPath $DeployISO -AppsISOPath $AppsISO -RemoveCaptureISO:$CleanupCaptureISO -RemoveDeployISO:$CleanupDeployISO -RemoveAppsISO:$CleanupAppsISO -RemoveDrivers:$CleanupDrivers -RemoveFFU:$RemoveFFU -RemoveApps:$RemoveApps -RemoveUpdates:$RemoveUpdates

# Remove KBPath for cached vhdx files only if RemoveUpdates is true
if ($AllowVHDXCaching -and $RemoveUpdates) {
    try {
        If (Test-Path -Path $KBPath) {
            WriteLog "Removing $KBPath (RemoveUpdates=true, AllowVHDXCaching=true)"
            Remove-Item -Path $KBPath -Recurse -Force -ErrorAction SilentlyContinue
            WriteLog 'Removal complete'
        }
    }
    catch {
        Writelog "Removing $KBPath failed with error $_"
        throw $_
    }
} elseif ($AllowVHDXCaching -and (Test-Path -Path $KBPath)) {
    $kbFiles = Get-ChildItem -Path $KBPath -Recurse -File -ErrorAction SilentlyContinue
    if ($kbFiles -and $kbFiles.Count -gt 0) {
        $kbSize = ($kbFiles | Measure-Object -Property Length -Sum).Sum
        WriteLog "Keeping $KBPath ($($kbFiles.Count) files, $([math]::Round($kbSize/1MB, 2)) MB) for future builds - RemoveUpdates=false"
    }
}

# Remove WinGetWin32Apps.json so it is always rebuilt next run
if (Test-Path -Path $wingetWin32jsonFile -PathType Leaf) {
    WriteLog "Removing $wingetWin32jsonFile"
    Remove-Item -Path $wingetWin32jsonFile -Force -ErrorAction SilentlyContinue
    WriteLog "Removal complete"
}
#Set $LongPathsEnabled registry value back to original value. $LongPathsEnabled could be $null if the registry value was not found
if ($null -eq $LongPathsEnabled) {
    Remove-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -ErrorAction SilentlyContinue
}
else {
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Value $LongPathsEnabled
}

#Clean up dirty.txt file
$dirtyFilePath = Join-Path $FFUDevelopmentPath "dirty.txt"
if (Test-Path -Path $dirtyFilePath) {
    Remove-Item -Path $dirtyFilePath -Force -ErrorAction SilentlyContinue | Out-Null
}
# Remove per-run session folder if present
$sessionDir = Join-Path $FFUDevelopmentPath '.session'
if (Test-Path -Path $sessionDir) {
    Remove-Item -Path $sessionDir -Recurse -Force -ErrorAction SilentlyContinue
}

# SECURITY: Sanitize sensitive credentials from capture media files
# This removes/overwrites the plain text password in CaptureFFU.ps1 and backup files
try {
    Remove-SensitiveCaptureMedia -FFUDevelopmentPath $FFUDevelopmentPath -SanitizeScript $true -RemoveBackups $true
}
catch {
    WriteLog "WARNING: Sensitive capture media cleanup failed (non-critical): $($_.Exception.Message)"
    # Continue - this is a security enhancement, not a requirement
}

if ($VerbosePreference -ne 'Continue') {
    Write-Host 'Script complete'
}
Set-Progress -Percentage 100 -Message "Build process complete."
# Record the end time
$endTime = Get-Date
Write-Host "FFU build process completed at" $endTime

# Calculate the total run time
$runTime = $endTime - $startTime

# Format the runtime with hours, minutes, and seconds
if ($runTime.TotalHours -ge 1) {
    $runTimeFormatted = 'Duration: {0:hh} hr {0:mm} min {0:ss} sec' -f $runTime
}
else {
    $runTimeFormatted = 'Duration: {0:mm} min {0:ss} sec' -f $runTime
}

if ($VerbosePreference -ne 'Continue') {
    Write-Host $runTimeFormatted
}
WriteLog 'Script complete'
WriteLog $runTimeFormatted

# Clear cleanup registry since build completed successfully
Clear-CleanupRegistry

# Output explicit success marker for UI to detect
# This allows the UI to distinguish successful completion from builds that
# completed but had non-terminating errors in the error stream
[PSCustomObject]@{
    FFUBuildSuccess = $true
    Message = "FFU build completed successfully"
    Duration = $runTimeFormatted
    Timestamp = Get-Date
}

} # END block
