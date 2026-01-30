
#Requires -Modules Hyper-V, Storage
#Requires -RunAsAdministrator

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

.PARAMETER Threads
Controls the throttle applied to parallel tasks inside the script. Default is 5, matching the UI Threads field, and applies to driver downloads invoked through Invoke-ParallelProcessing.

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
    [ValidateScript({ Test-Path $_ })]
    [string]$FFUDevelopmentPath = $PSScriptRoot,
    [bool]$InstallApps,
    [string]$AppListPath,
    [string]$UserAppListPath,

    [hashtable]$AppsScriptVariables,
    [bool]$InstallOffice,
    [string]$OfficeConfigXMLFile,
    [ValidateSet('Microsoft', 'Dell', 'HP', 'Lenovo')]
    [string]$Make,
    [string]$Model,
    [bool]$InstallDrivers,
    [uint64]$Memory = 4GB,
    [uint64]$Disksize = 50GB,
    [int]$Processors = 4,
    [string]$VMSwitchName,
    [string]$VMLocation,
    [string]$FFUPrefix = '_FFU',
    [string]$FFUCaptureLocation,
    [string]$ShareName = "FFUCaptureShare",
    [string]$Username = "ffu_user",
    [string]$CustomFFUNameTemplate,
    [Parameter(Mandatory = $false)]
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
    [int]$MaxUSBDrives = 5,
    [ValidateRange(1, 64)]
    [int]$Threads = 5,
    [ValidateSet('Foreground', 'High', 'Normal', 'Low')]
    [string]$BitsPriority = 'Normal',
    [Parameter(Mandatory = $false)]
    [ValidateSet(10, 11, 2016, 2019, 2021, 2022, 2024, 2025)]
    [int]$WindowsRelease = 11,
    [Parameter(Mandatory = $false)]
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
    [string]$DriversJsonPath,
    [bool]$CompressDownloadedDriversToWim = $false,
    [bool]$CopyDrivers,
    [bool]$CopyPEDrivers,
    [bool]$UseDriversAsPEDrivers,
    [bool]$RemoveFFU,
    [bool]$CopyAdditionalFFUFiles,
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
    [bool]$RemoveUpdates = $true,
    [bool]$RemoveApps = $true,
    [string]$DriversFolder,
    [string]$PEDriversFolder,
    [bool]$CleanupDrivers = $true,
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
    [string]$ExportConfigFile,
    [bool]$InjectUnattend = $false,
    [string]$orchestrationPath,
    [bool]$UpdateADK = $true,
    [bool]$CleanupCurrentRunDownloads = $false,
    [switch]$Cleanup
)
$ProgressPreference = 'SilentlyContinue'
$version = '2601.1Preview'

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
[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
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
$osInfo = Get-CimInstance -ClassName win32_OperatingSystem
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
if (-not $AppsISO) { $AppsISO = "$FFUDevelopmentPath\Apps.iso" }
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
Set-BitsTransferPriority -Priority $BitsPriority

#FUNCTIONS

function Get-Parameters {
    [CmdletBinding()]
    param (
        [Parameter()]
        $ParamNames
    )
    # Define unwanted parameters
    $excludedParams = 'Debug', 'ErrorAction', 'ErrorVariable', 'InformationAction', 'InformationVariable', 'OutBuffer', 'OutVariable', 'PipelineVariable', 'Verbose', 'WarningAction', 'WarningVariable', 'ProgressAction'

    # Filter out the unwanted parameters
    $filteredParamNames = $paramNames | Where-Object { $excludedParams -notcontains $_ }
    return $filteredParamNames
}

function LogVariableValues {
    $excludedVariables = @(
        'PSBoundParameters', 
        'PSScriptRoot', 
        'PSCommandPath', 
        'MyInvocation', 
        '?', 
        'ConsoleFileName', 
        'ExecutionContext',
        'false',
        'HOME',
        'Host',
        'hyperVFeature',
        'input',
        'MaximumAliasCount',
        'MaximumDriveCount',
        'MaximumErrorCount',
        'MaximumFunctionCount',
        'MaximumVariableCount',
        'null',
        'PID',
        'PSCmdlet',
        'PSCulture',
        'PSUICulture',
        'PSVersionTable',
        'ShellId',
        'true'
    )

    $allVariables = Get-Variable -Scope Script | Where-Object { $_.Name -notin $excludedVariables }
    Writelog "Script version: $version"
    WriteLog 'Logging variables'
    foreach ($variable in $allVariables) {
        $variableName = $variable.Name
        $variableValue = $variable.Value
        if ($null -ne $variableValue) {
            WriteLog "[VAR]$variableName`: $variableValue"
        }
        else {
            WriteLog "[VAR]Variable $variableName not found or not set"
        }
    }
    WriteLog 'End logging variables'
}

function Get-ChildProcesses($parentId) {
    $result = @()
    $children = Get-CimInstance Win32_Process -Filter "ParentProcessId = $parentId"
    foreach ($child in $children) {
        $result += $child
        $result += Get-ChildProcesses $child.ProcessId
    }
    return $result
}

function Test-Url {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Url
    )
    try {
        # Create a web request and check the response
        $request = [System.Net.WebRequest]::Create($Url)
        $request.Method = 'HEAD'
        $response = $request.GetResponse()
        return $true
    }
    catch {
        return $false
    }
}

function Get-MicrosoftDrivers {
    param (
        [string]$Make,
        [string]$Model,
        [int]$WindowsRelease
    )

    $url = "https://support.microsoft.com/en-us/surface/download-drivers-and-firmware-for-surface-09bb2e09-2a4b-cb69-0951-078a7739e120"

    ### DOWNLOAD DRIVER PAGE CONTENT
    WriteLog "Getting Surface driver information from $url"
    $OriginalVerbosePreference = $VerbosePreference
    $VerbosePreference = 'SilentlyContinue'
    $webContent = Invoke-WebRequest -Uri $url -UseBasicParsing -Headers $Headers -UserAgent $UserAgent
    $VerbosePreference = $OriginalVerbosePreference
    WriteLog "Complete"

    ### PARSE THE DRIVER PAGE CONTENT FOR MODELS AND DOWNLOAD LINKS
    WriteLog "Parsing web content for models and download links"
    $html = $webContent.Content

    # Regex to match divs with selectable-content-options__option-content classes
    $divPattern = '<div[^>]*class="selectable-content-options__option-content(?: ocHidden)?"[^>]*>(.*?)</div>'
    $divMatches = [regex]::Matches($html, $divPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

    $models = @()

    foreach ($divMatch in $divMatches) {
        $divContent = $divMatch.Groups[1].Value

        # Find all tables within the div
        $tablePattern = '<table[^>]*>(.*?)</table>'
        $tableMatches = [regex]::Matches($divContent, $tablePattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

        foreach ($tableMatch in $tableMatches) {
            $tableContent = $tableMatch.Groups[1].Value

            # Find all rows in the table
            $rowPattern = '<tr[^>]*>(.*?)</tr>'
            $rowMatches = [regex]::Matches($tableContent, $rowPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

            foreach ($rowMatch in $rowMatches) {
                $rowContent = $rowMatch.Groups[1].Value

                # Extract cells from the row
                $cellPattern = '<td[^>]*>\s*(?:<p[^>]*>)?(.*?)(?:</p>)?\s*</td>'
                $cellMatches = [regex]::Matches($rowContent, $cellPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

                if ($cellMatches.Count -ge 2) {
                    # Model name in the first TD
                    $modelName = ($cellMatches[0].Groups[1].Value).Trim()

                    # # Remove <p> and </p> tags if present
                    # $modelName = $modelName -replace '<p[^>]*>', '' -replace '</p>', ''
                    # $modelName = $modelName.Trim()


                    # The second TD might contain a link or just text
                    $secondTdContent = $cellMatches[1].Groups[1].Value.Trim()

                    # Look for a link in the second TD
                    $linkPattern = '<a[^>]+href="([^"]+)"[^>]*>'
                    $linkMatch = [regex]::Match($secondTdContent, $linkPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

                    if ($linkMatch.Success) {
                        $modelLink = $linkMatch.Groups[1].Value
                    }
                    else {
                        # No link, just text instructions
                        $modelLink = $secondTdContent
                    }

                    $models += [PSCustomObject]@{ Model = $modelName; Link = $modelLink }
                }
            }
        }
    }

    WriteLog "Parsing complete"

    ### FIND THE MODEL IN THE LIST OF MODELS
    $selectedModel = $models | Where-Object { $_.Model -eq $Model }

    if ($null -eq $selectedModel) {
        if ($VerbosePreference -ne 'Continue') {
            Write-Host "The model '$Model' was not found in the list of available models."
            Write-Host "Please run the script with the -Verbose switch to see the list of available models."
        }
        WriteLog "The model '$Model' was not found in the list of available models."
        WriteLog "Please select a model from the list below by number:"

        for ($i = 0; $i -lt $models.Count; $i++) {
            if ($VerbosePreference -ne 'Continue') {
                Write-Host "$($i + 1). $($models[$i].Model)"
            }
            WriteLog "$($i + 1). $($models[$i].Model)"
        }

        do {
            $selection = Read-Host "Enter the number of the model you want to select"
            WriteLog "User selected model number: $selection"

            if ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $models.Count) {
                $selectedModel = $models[$selection - 1]
            }
            else {
                if ($VerbosePreference -ne 'Continue') {
                    Write-Host "Invalid selection. Please try again."
                }
                WriteLog "Invalid selection. Please try again."
            }
        } while ($null -eq $selectedModel)
    }

    $Model = $selectedModel.Model
    WriteLog "Model: $Model"
    WriteLog "Download Page: $($selectedModel.Link)"

    ### GET THE DOWNLOAD LINK FOR THE SELECTED MODEL
    WriteLog "Getting download page content"
    $OriginalVerbosePreference = $VerbosePreference
    $VerbosePreference = 'SilentlyContinue'
    $downloadPageContent = Invoke-WebRequest -Uri $selectedModel.Link -UseBasicParsing -Headers $Headers -UserAgent $UserAgent
    $VerbosePreference = $OriginalVerbosePreference
    WriteLog "Complete"
    WriteLog "Parsing download page for file"
    $scriptPattern = '<script>window.__DLCDetails__={(.*?)}<\/script>'
    $scriptMatch = [regex]::Match($downloadPageContent.Content, $scriptPattern)

    if ($scriptMatch.Success) {
        $scriptContent = $scriptMatch.Groups[1].Value

        # Extract the download file information from the script tag
        $downloadFilePattern = '"name":"(.*?)",.*?"url":"(.*?)"'
        $downloadFileMatches = [regex]::Matches($scriptContent, $downloadFilePattern)

        $downloadLink = $null
        foreach ($downloadFile in $downloadFileMatches) {
            $fileName = $downloadFile.Groups[1].Value
            $fileUrl = $downloadFile.Groups[2].Value

            if ($fileName -match "Win$WindowsRelease") {
                $downloadLink = $fileUrl
                break
            }
        }


        ### CREATE FOLDER STRUCTURE AND DOWNLOAD AND EXTRACT THE FILE
        if ($downloadLink) {
            WriteLog "Download Link for Windows ${WindowsRelease}: $downloadLink"

            # Create directory structure
            if (-not (Test-Path -Path $DriversFolder)) {
                WriteLog "Creating Drivers folder: $DriversFolder"
                New-Item -Path $DriversFolder -ItemType Directory -Force | Out-Null
                WriteLog "Drivers folder created"
            }
            $sanitizedModel = ConvertTo-SafeName -Name $Model
            if ($sanitizedModel -ne $Model) { WriteLog "Sanitized model name: '$Model' -> '$sanitizedModel'" }
            $surfaceDriversPath = Join-Path -Path $DriversFolder -ChildPath $Make
            $modelPath = Join-Path -Path $surfaceDriversPath -ChildPath $sanitizedModel
            if (-Not (Test-Path -Path $modelPath)) {
                WriteLog "Creating model folder: $modelPath"
                New-Item -Path $modelPath -ItemType Directory | Out-Null
                WriteLog "Complete"
            }

            ### DOWNLOAD THE FILE
            $filePath = Join-Path -Path $surfaceDriversPath -ChildPath ($fileName)
            WriteLog "Downloading $Model driver file to $filePath"
            Mark-DownloadInProgress -FFUDevelopmentPath $FFUDevelopmentPath -TargetPath $filePath
            Start-BitsTransferWithRetry -Source $downloadLink -Destination $filePath
            Clear-DownloadInProgress -FFUDevelopmentPath $FFUDevelopmentPath -TargetPath $filePath
            WriteLog "Download complete"

            # Determine file extension
            $fileExtension = [System.IO.Path]::GetExtension($filePath).ToLower()

            ### EXTRACT THE FILE
            if ($fileExtension -eq ".msi") {
                # Extract the MSI file using an administrative install
                WriteLog "Extracting MSI file to $modelPath"
                $arguments = "/a `"$($filePath)`" /qn TARGETDIR=`"$($modelPath)`""
                Invoke-Process -FilePath "msiexec.exe" -ArgumentList $arguments | Out-Null
                WriteLog "Extraction complete"
            }
            elseif ($fileExtension -eq ".zip") {
                # Extract the ZIP file
                WriteLog "Extracting ZIP file to $modelPath"
                # $ProgressPreference = 'SilentlyContinue'
                Expand-Archive -Path $filePath -DestinationPath $modelPath -Force
                # $ProgressPreference = 'Continue'
                WriteLog "Extraction complete"
            }
            else {
                WriteLog "Unsupported file type: $fileExtension"
            }
            # Remove the downloaded file
            WriteLog "Removing $filePath"
            Remove-Item -Path $filePath -Force
            WriteLog "Complete"
        }
        else {
            WriteLog "No download link found for Windows $WindowsRelease."
        }
    }
    else {
        WriteLog "Failed to parse the download page for the MSI file."
    }
}

function Get-HPDrivers {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$Make,
        [Parameter()]
        [string]$Model,
        [Parameter()]
        [ValidateSet("x64", "x86", "ARM64")]
        [string]$WindowsArch,
        [Parameter()]
        [ValidateSet(10, 11)]
        [int]$WindowsRelease,
        [Parameter()]
        [string]$WindowsVersion
    )

    # Download and extract the PlatformList.cab
    $PlatformListUrl = 'https://hpia.hpcloud.hp.com/ref/platformList.cab'
    $DriversFolder = "$DriversFolder\$Make"
    $PlatformListCab = "$DriversFolder\platformList.cab"
    $PlatformListXml = "$DriversFolder\PlatformList.xml"

    if (-not (Test-Path -Path $DriversFolder)) {
        WriteLog "Creating Drivers folder: $DriversFolder"
        New-Item -Path $DriversFolder -ItemType Directory -Force | Out-Null
        WriteLog "Drivers folder created"
    }
    WriteLog "Downloading $PlatformListUrl to $PlatformListCab"
    Start-BitsTransferWithRetry -Source $PlatformListUrl -Destination $PlatformListCab
    WriteLog "Download complete"
    WriteLog "Expanding $PlatformListCab to $PlatformListXml"
    Invoke-Process -FilePath expand.exe -ArgumentList "$PlatformListCab $PlatformListXml" | Out-Null
    WriteLog "Expansion complete"

    # Parse the PlatformList.xml to find the SystemID based on the ProductName
    [xml]$PlatformListContent = Get-Content -Path $PlatformListXml
    $ProductNodes = $PlatformListContent.ImagePal.Platform | Where-Object { $_.ProductName.'#text' -match $Model }

    # Create a list of unique ProductName entries
    $ProductNames = @()
    foreach ($node in $ProductNodes) {
        foreach ($productName in $node.ProductName) {
            if ($productName.'#text' -match $Model) {
                $ProductNames += [PSCustomObject]@{
                    ProductName = $productName.'#text'
                    SystemID    = $node.SystemID
                    OSReleaseID = $node.OS.OSReleaseIdFileName -replace 'H', 'h'
                    IsWindows11 = $node.OS.IsWindows11 -contains 'true'
                }
            }
        }
    }

    if ($ProductNames.Count -gt 1) {
        Write-Output "More than one model found matching '$Model':"
        WriteLog "More than one model found matching '$Model':"
        $ProductNames | ForEach-Object -Begin { $i = 1 } -Process {
            if ($VerbosePreference -ne 'Continue') {
                Write-Output "$i. $($_.ProductName)"
            }
            WriteLog "$i. $($_.ProductName)"
            $i++
        }
        $selection = Read-Host "Please select the number corresponding to the correct model"
        WriteLog "User selected model number: $selection"
        if ($selection -match '^\d+$' -and [int]$selection -le $ProductNames.Count) {
            $SelectedProduct = $ProductNames[[int]$selection - 1]
            $ProductName = $SelectedProduct.ProductName
            WriteLog "Selected model: $ProductName"
            $SystemID = $SelectedProduct.SystemID
            WriteLog "SystemID: $SystemID"
            $ValidOSReleaseIDs = $SelectedProduct.OSReleaseID
            WriteLog "Valid OSReleaseIDs: $ValidOSReleaseIDs"
            $IsWindows11 = $SelectedProduct.IsWindows11
            WriteLog "IsWindows11 supported: $IsWindows11"
        }
        else {
            WriteLog "Invalid selection. Exiting."
            if ($VerbosePreference -ne 'Continue') {
                Write-Host "Invalid selection. Exiting."
            }
            exit
        }
    }
    elseif ($ProductNames.Count -eq 1) {
        $SelectedProduct = $ProductNames[0]
        $ProductName = $SelectedProduct.ProductName
        WriteLog "Selected model: $ProductName"
        $SystemID = $SelectedProduct.SystemID
        WriteLog "SystemID: $SystemID"
        $ValidOSReleaseIDs = $SelectedProduct.OSReleaseID
        WriteLog "OSReleaseID: $ValidOSReleaseIDs"
        $IsWindows11 = $SelectedProduct.IsWindows11
        WriteLog "IsWindows11: $IsWindows11"
    }
    else {
        WriteLog "No models found matching '$Model'. Exiting."
        if ($VerbosePreference -ne 'Continue') {
            Write-Host "No models found matching '$Model'. Exiting."
        }
        exit
    }

    if (-not $SystemID) {
        WriteLog "SystemID not found for model: $Model Exiting."
        if ($VerbosePreference -ne 'Continue') {
            Write-Host "SystemID not found for model: $Model Exiting."
        }
        exit
    }

    # Validate if WindowsRelease is 11 and there is no IsWindows11 element set to true
    if ($WindowsRelease -eq 11 -and -not $IsWindows11) {
        WriteLog "WindowsRelease is set to 11, but no drivers are available for this Windows release. Please set the -WindowsRelease parameter to 10, or provide your own drivers to the FFUDevelopment\Drivers folder."
        Write-Output "WindowsRelease is set to 11, but no drivers are available for this Windows release. Please set the -WindowsRelease parameter to 10, or provide your own drivers to the FFUDevelopment\Drivers folder."
        exit
    }

    # Validate WindowsVersion against OSReleaseID
    $OSReleaseIDs = $ValidOSReleaseIDs -split ' '
    $MatchingReleaseID = $OSReleaseIDs | Where-Object { $_ -eq "$WindowsVersion" }

    if (-not $MatchingReleaseID) {
        Write-Output "The specified WindowsVersion value '$WindowsVersion' is not valid for the selected model. Please select a valid OSReleaseID:"
        $OSReleaseIDs | ForEach-Object -Begin { $i = 1 } -Process {
            Write-Output "$i. $_"
            $i++
        }
        $selection = Read-Host "Please select the number corresponding to the correct OSReleaseID"
        WriteLog "User selected OSReleaseID number: $selection"
        if ($selection -match '^\d+$' -and [int]$selection -le $OSReleaseIDs.Count) {
            $WindowsVersion = $OSReleaseIDs[[int]$selection - 1]
            WriteLog "Selected OSReleaseID: $WindowsVersion"
        }
        else {
            WriteLog "Invalid selection. Exiting."
            exit
        }
    }

    # Modify WindowsArch for URL
    $Arch = $WindowsArch -replace "^x", ""

    # Construct the URL to download the driver XML cab for the model
    # The HPcloud reference site is case sensitve so we must convert the Windowsversion to lower 'h' first
    $WindowsVersionHP = $WindowsVersion -replace 'H', 'h'
    $ModelRelease = $SystemID + "_$Arch" + "_$WindowsRelease" + ".0.$WindowsVersionHP"
    $DriverCabUrl = "https://hpia.hpcloud.hp.com/ref/$SystemID/$ModelRelease.cab"
    $DriverCabFile = "$DriversFolder\$ModelRelease.cab"
    $DriverXmlFile = "$DriversFolder\$ModelRelease.xml"

    if (-not (Test-Url -Url $DriverCabUrl)) {
        WriteLog "HP Driver cab URL is not accessible: $DriverCabUrl Exiting"
        if ($VerbosePreference -ne 'Continue') {
            Write-Host "HP Driver cab URL is not accessible: $DriverCabUrl Exiting"
        }
        exit
    }

    # Download and extract the driver XML cab
    Writelog "Downloading HP Driver cab from $DriverCabUrl to $DriverCabFile"
    Start-BitsTransferWithRetry -Source $DriverCabUrl -Destination $DriverCabFile
    WriteLog "Expanding HP Driver cab to $DriverXmlFile"
    Invoke-Process -FilePath expand.exe -ArgumentList "$DriverCabFile $DriverXmlFile" | Out-Null

    # Parse the extracted XML file to download individual drivers
    [xml]$DriverXmlContent = Get-Content -Path $DriverXmlFile
    $baseUrl = "https://ftp.hp.com/pub/softpaq/sp"

    WriteLog "Downloading drivers for $ProductName"
    foreach ($update in $DriverXmlContent.ImagePal.Solutions.UpdateInfo) {
        if ($update.Category -notmatch '^Driver') {
            continue
        }
    
        $Name = $update.Name
        # Fix the name for drivers that contain illegal characters for folder name purposes
        $Name = $Name -replace '[\\\/\:\*\?\"\<\>\|]', '_'
        WriteLog "Downloading driver: $Name"
        $Category = $update.Category
        $Category = $Category -replace '[\\\/\:\*\?\"\<\>\|]', '_'
        $Version = $update.Version
        $Version = $Version -replace '[\\\/\:\*\?\"\<\>\|]', '_'
        $DriverUrl = "https://$($update.URL)"
        WriteLog "Driver URL: $DriverUrl"
        $DriverFileName = [System.IO.Path]::GetFileName($DriverUrl)
        $downloadFolder = "$DriversFolder\$ProductName\$Category"
        $DriverFilePath = Join-Path -Path $downloadFolder -ChildPath $DriverFileName

        if (Test-Path -Path $DriverFilePath) {
            WriteLog "Driver already downloaded: $DriverFilePath, skipping"
            continue
        }

        if (-not (Test-Path -Path $downloadFolder)) {
            WriteLog "Creating download folder: $downloadFolder"
            New-Item -Path $downloadFolder -ItemType Directory -Force | Out-Null
            WriteLog "Download folder created"
        }

        # Download the driver with retry
        WriteLog "Downloading driver to: $DriverFilePath"
        Mark-DownloadInProgress -FFUDevelopmentPath $FFUDevelopmentPath -TargetPath $DriverFilePath
        Start-BitsTransferWithRetry -Source $DriverUrl -Destination $DriverFilePath
        Clear-DownloadInProgress -FFUDevelopmentPath $FFUDevelopmentPath -TargetPath $DriverFilePath
        WriteLog 'Driver downloaded'

        # Make folder for extraction
        $extractFolder = "$downloadFolder\$Name\$Version\" + $DriverFileName.TrimEnd('.exe')
        Writelog "Creating extraction folder: $extractFolder"
        New-Item -Path $extractFolder -ItemType Directory -Force | Out-Null
        WriteLog 'Extraction folder created'
    
        # Extract the driver
        $arguments = "/s /e /f `"$extractFolder`""
        WriteLog "Extracting driver"
        Invoke-Process -FilePath $DriverFilePath -ArgumentList $arguments | Out-Null
        WriteLog "Driver extracted to: $extractFolder"

        # Delete the .exe driver file after extraction
        Remove-Item -Path $DriverFilePath -Force
        WriteLog "Driver installation file deleted: $DriverFilePath"
    }
    # Clean up the downloaded cab and xml files
    Remove-Item -Path $DriverCabFile, $DriverXmlFile, $PlatformListCab, $PlatformListXml -Force
    WriteLog "Driver cab and xml files deleted"
}
function Get-LenovoDrivers {
    param (
        [Parameter()]
        [string]$Model,
        [Parameter()]
        [ValidateSet("x64", "x86", "ARM64")]
        [string]$WindowsArch,
        [Parameter()]
        [ValidateSet(10, 11)]
        [int]$WindowsRelease
    )

    function Get-LenovoPSREF {
        param (
            [string]$ModelName
        )

        # Lenovo is special - they prevent access to the PSREF API without a cookie as of July 2025. 
        # This cookie must be retrieved via Javascript
        # It appears that the cookie is hard-coded. We'll see how long this lasts.
        # If anyone knows how to reliably get the the model and machine type information from Lenovo, let me know.
        # https://download.lenovo.com/cdrt/td/catalogv2.xml only provides a subset of the information available from PSREF (e.g. it's missing 300w, 500w, and other consumer models).

        # $lenovoCookie = "X-PSREF-USER-TOKEN=eyJ0eXAiOiJKV1QifQ.bjVTdWk0YklZeUc2WnFzL0lXU0pTeU1JcFo0aExzRXl1UGxHN3lnS1BtckI0ZVU5WEJyVGkvaFE0NmVNU2U1ZjNrK3ZqTEVIZ29nTk1TNS9DQmIwQ0pTN1Q1VytlY1RpNzZTUldXbm4wZ1g2RGJuQWg4MXRkTmxKT2YrOW9LRjBzQUZzV05HM3NpcU92WFVTM0o0blM1SDQyUlVXNThIV1VBS2R0c1B2NjJyQjIrUGxNZ2x6RTRhUjY5UDZWclBX.ZDBmM2EyMWRjZTg2N2JmYWMxZDIxY2NiYjQzMWFhNjg1YjEzZTAxNmU2M2RmN2M5ZjIyZWJhMzZkOWI1OWJhZg"
    
        # Wrote a separate function to grab the token. Check the function notes for more details. Keep the above comment for now to see if the cookie ever changes.
        $lenovoCookie = Get-LenovoPSREFToken

        # Add the cookie to the headers
        $Headers["Cookie"] = $lenovoCookie

        $url = "https://psref.lenovo.com/api/search/DefinitionFilterAndSearch/Suggest?kw=$ModelName"
        WriteLog "Querying Lenovo PSREF API for model: $ModelName"
        $OriginalVerbosePreference = $VerbosePreference
        $VerbosePreference = 'SilentlyContinue'
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -Headers $Headers -UserAgent $UserAgent
        $VerbosePreference = $OriginalVerbosePreference
        WriteLog "Complete"

        $jsonResponse = $response.Content | ConvertFrom-Json

        $products = @()
        foreach ($item in $jsonResponse.data) {
            if (-not [string]::IsNullOrEmpty($item.MachineType) -and -not [string]::IsNullOrEmpty($item.ProductName)) {
                $productName = $item.ProductName
                $machineTypes = $item.MachineType -split " / "

                foreach ($machineType in $machineTypes) {
                    if ($machineType -eq $ModelName) {
                        WriteLog "Model name entered is a matching machine type"
                        $products = @()
                        $products += [pscustomobject]@{
                            ProductName = $productName
                            MachineType = $machineType
                        }
                        WriteLog "Product Name: $productName Machine Type: $machineType"
                        return $products
                    }
                    $products += [pscustomobject]@{
                        ProductName = $productName
                        MachineType = $machineType
                    }
                }
            }
        }

        return , $products
    }
    
    # Parse the Lenovo PSREF page for the model
    $machineTypes = Get-LenovoPSREF -ModelName $Model
    if ($machineTypes.ProductName.Count -eq 0) {
        WriteLog "No machine types found for model: $Model"
        WriteLog "Enter a valid model or machine type in the -model parameter"
        exit
    }
    elseif ($machineTypes.ProductName.Count -eq 1) {
        $machineType = $machineTypes[0].MachineType
        $model = $machineTypes[0].ProductName
    }
    else {
        if ($VerbosePreference -ne 'Continue') {
            Write-Output "Multiple machine types found for model: $Model"
        }
        WriteLog "Multiple machine types found for model: $Model"
        for ($i = 0; $i -lt $machineTypes.ProductName.Count; $i++) {
            if ($VerbosePreference -ne 'Continue') {
                Write-Output "$($i + 1). $($machineTypes[$i].ProductName) ($($machineTypes[$i].MachineType))"
            }
            WriteLog "$($i + 1). $($machineTypes[$i].ProductName) ($($machineTypes[$i].MachineType))"
        }
        $selection = Read-Host "Enter the number of the model you want to select"
        $machineType = $machineTypes[$selection - 1].MachineType
        WriteLog "Selected machine type: $machineType"
        $model = $machineTypes[$selection - 1].ProductName
        WriteLog "Selected model: $model"
    }
    

    # Construct the catalog URL based on Windows release and machine type
    $ModelRelease = $machineType + "_Win" + $WindowsRelease
    $CatalogUrl = "https://download.lenovo.com/catalog/$ModelRelease.xml"
    WriteLog "Lenovo Driver catalog URL: $CatalogUrl"

    if (-not (Test-Url -Url $catalogUrl)) {
        Write-Error "Lenovo Driver catalog URL is not accessible: $catalogUrl"
        WriteLog "Lenovo Driver catalog URL is not accessible: $catalogUrl"
        exit
    }

    # Create the folder structure for the Lenovo drivers
    $driversFolder = "$DriversFolder\$Make"
    if (-not (Test-Path -Path $DriversFolder)) {
        WriteLog "Creating Drivers folder: $DriversFolder"
        New-Item -Path $DriversFolder -ItemType Directory -Force | Out-Null
        WriteLog "Drivers folder created"
    }

    # Download and parse the Lenovo catalog XML
    $LenovoCatalogXML = "$DriversFolder\$ModelRelease.xml"
    WriteLog "Downloading $catalogUrl to $LenovoCatalogXML"
    Start-BitsTransferWithRetry -Source $catalogUrl -Destination $LenovoCatalogXML
    WriteLog "Download Complete"
    $xmlContent = [xml](Get-Content -Path $LenovoCatalogXML)

    WriteLog "Parsing Lenovo catalog XML"
    # Process each package in the catalog
    foreach ($package in $xmlContent.packages.package) {
        $packageUrl = $package.location
        $category = $package.category

        #If category starts with BIOS, skip the package
        if ($category -like 'BIOS*') {
            continue
        }

        #If category name is 'Motherboard Devices Backplanes core chipset onboard video PCIe switches', truncate to 'Motherboard Devices' to shorten path
        if ($category -eq 'Motherboard Devices Backplanes core chipset onboard video PCIe switches') {
            $category = 'Motherboard Devices'
        }

        $packageName = [System.IO.Path]::GetFileName($packageUrl)
        #Remove the filename from the $packageURL
        $baseURL = $packageUrl -replace $packageName, "" 

        # Download the package XML
        $packageXMLPath = "$DriversFolder\$packageName"
        WriteLog "Downloading $category package XML $packageUrl to $packageXMLPath"
        If ((Start-BitsTransferWithRetry -Source $packageUrl -Destination $packageXMLPath) -eq $false) {
            Write-Output "Failed to download $category package XML: $packageXMLPath"
            WriteLog "Failed to download $category package XML: $packageXMLPath"
            continue
        }

        # Load the package XML content
        $packageXmlContent = [xml](Get-Content -Path $packageXMLPath)
        $packageType = $packageXmlContent.Package.PackageType.type
        $packageTitle = $packageXmlContent.Package.title.InnerText

        # Fix the name for drivers that contain illegal characters for folder name purposes
        $packageTitle = $packageTitle -replace '[\\\/\:\*\?\"\<\>\|]', '_'

        # If ' - ' is in the package title, truncate the title to the first part of the string.
        $packageTitle = $packageTitle -replace ' - .*', ''

        #Check if packagetype = 2. If packagetype is not 2, skip the package. $packageType is a System.Xml.XmlElement.
        #This filters out Firmware, BIOS, and other non-INF drivers
        if ($packageType -ne 2) {
            Remove-Item -Path $packageXMLPath -Force
            continue
        }

        # Extract the driver file name and the extract command
        $driverFileName = $packageXmlContent.Package.Files.Installer.File.Name
        $extractCommand = $packageXmlContent.Package.ExtractCommand

        #if extract command is empty/missing, skip the package
        if (!($extractCommand)) {
            Remove-Item -Path $packageXMLPath -Force
            continue
        }

        # Create the download URL and folder structure
        $driverUrl = $baseUrl + $driverFileName
        $downloadFolder = "$DriversFolder\$Model\$Category\$packageTitle"
        $driverFilePath = Join-Path -Path $downloadFolder -ChildPath $driverFileName

        # Check if file has already been downloaded
        if (Test-Path -Path $driverFilePath) {
            Write-Output "Driver already downloaded: $driverFilePath skipping"
            WriteLog "Driver already downloaded: $driverFilePath skipping"
            continue
        }

        if (-not (Test-Path -Path $downloadFolder)) {
            WriteLog "Creating download folder: $downloadFolder"
            New-Item -Path $downloadFolder -ItemType Directory -Force | Out-Null
            WriteLog "Download folder created"
        }

        # Download the driver with retry
        WriteLog "Downloading driver: $driverUrl to $driverFilePath"
        Mark-DownloadInProgress -FFUDevelopmentPath $FFUDevelopmentPath -TargetPath $driverFilePath
        Start-BitsTransferWithRetry -Source $driverUrl -Destination $driverFilePath
        Clear-DownloadInProgress -FFUDevelopmentPath $FFUDevelopmentPath -TargetPath $driverFilePath
        WriteLog "Driver downloaded"

        # Make folder for extraction
        $extractFolder = $downloadFolder + "\" + $driverFileName.TrimEnd($driverFileName[-4..-1])
        WriteLog "Creating extract folder: $extractFolder"
        New-Item -Path $extractFolder -ItemType Directory -Force | Out-Null
        WriteLog "Extract folder created"

        # Modify the extract command
        $modifiedExtractCommand = $extractCommand -replace '%PACKAGEPATH%', "`"$extractFolder`""

        # Extract the driver
        # Start-Process -FilePath $driverFilePath -ArgumentList $modifiedExtractCommand -Wait -NoNewWindow
        WriteLog "Extracting driver: $driverFilePath to $extractFolder"
        Invoke-Process -FilePath $driverFilePath -ArgumentList $modifiedExtractCommand | Out-Null
        WriteLog "Driver extracted"

        # Delete the .exe driver file after extraction
        WriteLog "Deleting driver installation file: $driverFilePath"
        Remove-Item -Path $driverFilePath -Force
        WriteLog "Driver installation file deleted: $driverFilePath"

        # Delete the package XML file after extraction
        WriteLog "Deleting package XML file: $packageXMLPath"
        Remove-Item -Path $packageXMLPath -Force
        WriteLog "Package XML file deleted"
    }

    #Delete the catalog XML file after processing
    WriteLog "Deleting catalog XML file: $LenovoCatalogXML"
    Remove-Item -Path $LenovoCatalogXML -Force
    WriteLog "Catalog XML file deleted"
}

function Get-DellDrivers {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Model,
        [Parameter(Mandatory = $true)]
        [ValidateSet('x64', 'x86', 'ARM64')]
        [string]$WindowsArch,
        [Parameter(Mandatory = $true)]
        [int]$WindowsRelease
    )

    if (-not (Test-Path -Path $DriversFolder)) {
        New-Item -Path $DriversFolder -ItemType Directory -Force | Out-Null
    }
    $DriversFolder = Join-Path $DriversFolder $Make
    if (-not (Test-Path $DriversFolder)) {
        New-Item -Path $DriversFolder -ItemType Directory -Force | Out-Null
    }

    # Client pathway (<=11): use CatalogIndexPC + per-model cab.
    if ($WindowsRelease -le 11) {
        $indexXml = Get-DellCatalogIndex -DriversFolder (Split-Path $DriversFolder -Parent)
        $allModels = Get-DellClientModels -CatalogIndexXmlPath $indexXml
        $target = $allModels | Where-Object { $_.ModelDisplay -eq $Model }
        if (-not $target) { throw "Requested Dell model '$Model' not found in index." }

        $cabUrl = $target.CabUrl
        if ([string]::IsNullOrWhiteSpace($cabUrl)) {
            WriteLog "CabUrl missing for '$($target.Model)'; resolving via CatalogIndexPC."
            $resolved = Resolve-DellCabUrlFromModel -DriversFolder $DriversFolder -ModelDisplay $target.Model
            if ($null -eq $resolved -or [string]::IsNullOrWhiteSpace($resolved.CabUrl)) {
                throw "Unable to resolve CabUrl for $($target.Model) from CatalogIndexPC."
            }
            $cabUrl = $resolved.CabUrl
            $target.CabUrl = $cabUrl
        }
        $modelCabName = [IO.Path]::GetFileName($cabUrl)
        $modelCabPath = Join-Path $DriversFolder $modelCabName
        $modelXmlPath = Join-Path $DriversFolder ($modelCabName -replace '\.cab$', '.xml')

        if (Test-Path $modelCabPath) { Remove-Item $modelCabPath -Force -ErrorAction SilentlyContinue }
        if (Test-Path $modelXmlPath) { Remove-Item $modelXmlPath -Force -ErrorAction SilentlyContinue }

        Start-BitsTransferWithRetry -Source $cabUrl -Destination $modelCabPath
        Invoke-Process -FilePath Expand.exe -ArgumentList """$modelCabPath"" ""$modelXmlPath""" | Out-Null
        Remove-Item $modelCabPath -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path $modelXmlPath)) { throw "Failed to extract model cab XML: $modelXmlPath" }

        $pkgs = Get-DellLatestDriverPackages -ModelXmlPath $modelXmlPath -WindowsArch $WindowsArch -WindowsRelease $WindowsRelease
        if (-not $pkgs) {
            WriteLog "No drivers found for '$Model'."
            return
        }

        foreach ($pkg in $pkgs) {
            $categorySafe = ($pkg.Category -replace '[\\\/\:\*\?\"\<\>\| ]', '_')
            $downloadFolder = Join-Path $DriversFolder (Join-Path $Model $categorySafe)
            if (-not (Test-Path $downloadFolder)) { New-Item -Path $downloadFolder -ItemType Directory -Force | Out-Null }
            $driverFilePath = Join-Path $downloadFolder $pkg.DriverFileName
            $extractFolder = Join-Path $downloadFolder ($pkg.DriverFileName.TrimEnd($pkg.DriverFileName[-4..-1]))

            if (Test-Path $extractFolder) {
                $sz = (Get-ChildItem -Path $extractFolder -Recurse -Exclude *.log | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                if ($sz -gt 1KB) { continue }
            }
            if (-not (Test-Path $driverFilePath)) {
                try { Start-BitsTransferWithRetry -Source $pkg.DownloadUrl -Destination $driverFilePath }
                catch { WriteLog "Download failed: $($pkg.DownloadUrl) $($_.Exception.Message)"; continue }
            }

            if (-not (Test-Path $extractFolder)) { New-Item -Path $extractFolder -ItemType Directory -Force | Out-Null }

            $arg1 = "/s /e=`"$extractFolder`" /l=`"$extractFolder\log.log`""
            $arg2 = "/s /drivers=`"$extractFolder`" /l=`"$extractFolder\log.log`""
            $ok = $false
            try {
                Invoke-Process -FilePath $driverFilePath -ArgumentList $arg1 | Out-Null
                $sz = (Get-ChildItem -Path $extractFolder -Recurse -Exclude *.log | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                if ($sz -gt 1KB) { $ok = $true }
                if (-not $ok) {
                    Remove-Item $extractFolder -Recurse -Force -ErrorAction SilentlyContinue
                    New-Item -Path $extractFolder -ItemType Directory -Force | Out-Null
                    Invoke-Process -FilePath $driverFilePath -ArgumentList $arg2 | Out-Null
                    $sz = (Get-ChildItem -Path $extractFolder -Recurse -Exclude *.log | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                    if ($sz -gt 1KB) { $ok = $true }
                }
            }
            catch {
                WriteLog "Extraction error: $($_.Exception.Message)"
            }
            if ($ok) { Remove-Item $driverFilePath -Force -ErrorAction SilentlyContinue }
        }
        return
    }

    # Server pathway (unchanged legacy)
    $catalogUrl = "https://downloads.dell.com/catalog/Catalog.cab"
    $DellCabFile = Join-Path $DriversFolder 'Catalog.cab'
    $DellCatalogXML = Join-Path $DriversFolder 'Catalog.xml'

    Start-BitsTransferWithRetry -Source $catalogUrl -Destination $DellCabFile
    Invoke-Process -FilePath Expand.exe -ArgumentList "$DellCabFile $DellCatalogXML" | Out-Null

    $xmlContent = [xml](Get-Content -Path $DellCatalogXML)
    $baseLocation = "https://" + $xmlContent.manifest.baseLocation + "/"
    $latestDrivers = @{}
    $softwareComponents = $xmlContent.Manifest.SoftwareComponent | Where-Object { $_.ComponentType.value -eq 'DRVR' }

    foreach ($component in $softwareComponents) {
        $models = $component.SupportedSystems.Brand.Model
        foreach ($item in $models) {
            if ($item.Display.'#cdata-section' -match $Model) {
                $validOS = $component.SupportedOperatingSystems.OperatingSystem | Where-Object { $_.osArch -eq $WindowsArch }
                if (-not $validOS) { continue }
                $driverPath = $component.path
                $downloadUrl = $baseLocation + $driverPath
                $driverFileName = [System.IO.Path]::GetFileName($driverPath)
                $name = $component.Name.Display.'#cdata-section' -replace '[\\\/\:\*\?\"\<\>\| ]', '_' -replace '[\,]', '-'
                $category = $component.Category.Display.'#cdata-section' -replace '[\\\/\:\*\?\"\<\>\| ]', '_'
                $version = [version]$component.vendorVersion
                $namePrefix = ($name -split '-')[0]
                if (-not $latestDrivers[$category]) { $latestDrivers[$category] = @{} }
                if (-not $latestDrivers[$category][$namePrefix] -or $latestDrivers[$category][$namePrefix].Version -lt $version) {
                    $latestDrivers[$category][$namePrefix] = [pscustomobject]@{
                        Name = $name; DownloadUrl = $downloadUrl; DriverFileName = $driverFileName; Version = $version; Category = $category
                    }
                }
            }
        }
    }

    foreach ($category in $latestDrivers.Keys) {
        foreach ($driver in $latestDrivers[$category].Values) {
            $downloadFolder = Join-Path $DriversFolder (Join-Path $Model $driver.Category)
            if (-not (Test-Path $downloadFolder)) { New-Item -Path $downloadFolder -ItemType Directory -Force | Out-Null }
            $driverFilePath = Join-Path $downloadFolder $driver.DriverFileName
            if (Test-Path $driverFilePath) { continue }
            Start-BitsTransferWithRetry -Source $driver.DownloadUrl -Destination $driverFilePath
            $extractFolder = Join-Path $downloadFolder ($driver.DriverFileName.TrimEnd($driver.DriverFileName[-4..-1]))
            $arguments = "/s /drivers=`"$extractFolder`""
            try { Invoke-Process -FilePath $driverFilePath -ArgumentList $arguments | Out-Null } catch {}
            Remove-Item $driverFilePath -Force -ErrorAction SilentlyContinue
        }
    }
}
function Get-ADKURL {
    param (
        [ValidateSet("Windows ADK", "WinPE add-on")]
        [string]$ADKOption
    )

    # Define base pattern for URL scraping
    $basePattern = '<li><a href="(https://[^"]+)" data-linktype="external">Download the '

    # Define specific URL patterns based on ADK options
    $ADKUrlPattern = @{
        "Windows ADK"  = $basePattern + "Windows ADK"
        "WinPE add-on" = $basePattern + "Windows PE add-on for the Windows ADK"
    }[$ADKOption]

    try {
        # Retrieve content of Microsoft documentation page
        $OriginalVerbosePreference = $VerbosePreference
        $VerbosePreference = 'SilentlyContinue'
        $ADKWebPage = Invoke-RestMethod "https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install" -Headers $Headers -UserAgent $UserAgent
        $VerbosePreference = $OriginalVerbosePreference
        
        # Extract download URL based on specified pattern
        $ADKMatch = [regex]::Match($ADKWebPage, $ADKUrlPattern)

        if (-not $ADKMatch.Success) {
            WriteLog "Failed to retrieve ADK download URL. Pattern match failed."
            return
        }

        # Extract FWlink from the matched pattern
        $ADKFWLink = $ADKMatch.Groups[1].Value

        if ($null -eq $ADKFWLink) {
            WriteLog "FWLink for $ADKOption not found."
            return
        }

        # Let Invoke-WebRequest handle the redirect and get the final URL.
        try {
            $OriginalVerbosePreference = $VerbosePreference
            $VerbosePreference = 'SilentlyContinue'
            # Allow one redirection to get the final URL from the fwlink
            $response = Invoke-WebRequest -Uri $ADKFWLink -Method Head -MaximumRedirection 1 -Headers $Headers -UserAgent $UserAgent
            $VerbosePreference = $OriginalVerbosePreference
            
            # The final URL after redirection is in the ResponseUri property of the BaseResponse's RequestMessage.
            $ADKUrl = $response.BaseResponse.RequestMessage.RequestUri.AbsoluteUri
            
            if ($null -eq $ADKUrl) {
                WriteLog "Could not determine final ADK download URL after redirection."
                return $null
            }
            
            WriteLog "Resolved ADK download URL to: $ADKUrl"
            return $ADKUrl
        }
        catch {
            WriteLog "An error occurred while resolving the ADK FWLink: $($_.Exception.Message)"
            throw
        }
    }
    catch {
        WriteLog $_
        Write-Error "Error occurred while retrieving ADK download URL"
        throw $_
    }
}
function Install-ADK {
    param (
        [ValidateSet("Windows ADK", "WinPE add-on")]
        [string]$ADKOption
    )

    try {
        $ADKUrl = Get-ADKURL -ADKOption $ADKOption
        
        if ($null -eq $ADKUrl) {
            throw "Failed to retrieve URL for $ADKOption. Please manually install it."
        }

        # Select the installer based on the ADK option specified
        $installer = @{
            "Windows ADK"  = "adksetup.exe"
            "WinPE add-on" = "adkwinpesetup.exe"
        }[$ADKOption]

        # Select the feature based on the ADK option specified
        $feature = @{
            "Windows ADK"  = "OptionId.DeploymentTools"
            "WinPE add-on" = "OptionId.WindowsPreinstallationEnvironment"
        }[$ADKOption]

        $installerLocation = Join-Path $env:TEMP $installer

        WriteLog "Downloading $ADKOption from $ADKUrl to $installerLocation"
        Start-BitsTransferWithRetry -Source $ADKUrl -Destination $installerLocation -ErrorAction Stop
        WriteLog "$ADKOption downloaded to $installerLocation"
        
        WriteLog "Installing $ADKOption with $feature enabled"
        Invoke-Process $installerLocation "/quiet /installpath ""%ProgramFiles(x86)%\Windows Kits\10"" /features $feature" | Out-Null
        
        WriteLog "$ADKOption installation completed."
        WriteLog "Removing $installer from $installerLocation"
        # Clean up downloaded installation file
        Remove-Item -Path $installerLocation -Force -ErrorAction SilentlyContinue
    }
    catch {
        WriteLog $_
        Write-Error "Error occurred while installing $ADKOption. Please manually install it."
        throw $_
    }
}
function Get-InstalledProgramRegKey {
    param (
        [string]$DisplayName
    )

    $uninstallRegPath = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    $uninstallRegKeys = Get-ChildItem -Path $uninstallRegPath -Recurse
    
    foreach ($regKey in $uninstallRegKeys) {
        try {
            $regValue = $regKey.GetValue("DisplayName")
            if ($regValue -eq $DisplayName) {
                return $regKey
            }
        }
        catch {
            WriteLog $_
            throw "Error retrieving installed program info for $DisplayName : $_"
        }
    }
}

function Uninstall-ADK {
    param (
        [ValidateSet("Windows ADK", "WinPE add-on")]
        [string]$ADKOption
    )

    # Match name as it appears in the registry
    $displayName = switch ($ADKOption) {
        "Windows ADK" { "Windows Assessment and Deployment Kit" }
        "WinPE add-on" { "Windows Assessment and Deployment Kit Windows Preinstallation Environment Add-ons" }
    }

    try {
        $adkRegKey = Get-InstalledProgramRegKey -DisplayName $displayName

        if (-not $adkRegKey) {
            WriteLog "$ADKOption is not installed."
            return
        }

        $adkBundleCachePath = $adkRegKey.GetValue("BundleCachePath")
        WriteLog "Uninstalling $ADKOption..."
        Invoke-Process $adkBundleCachePath "/uninstall /quiet" | Out-Null
        WriteLog "$ADKOption uninstalled successfully."
    }
    catch {
        WriteLog $_
        Write-Error "Error occurred while uninstalling $ADKOption. Please manually uninstall it."
        throw $_
    }
}

function Confirm-ADKVersionIsLatest {
    param (
        [ValidateSet("Windows ADK", "WinPE add-on")]
        [string]$ADKOption
    )

    $displayName = switch ($ADKOption) {
        "Windows ADK" { "Windows Assessment and Deployment Kit" }
        "WinPE add-on" { "Windows Assessment and Deployment Kit Windows Preinstallation Environment Add-ons" }
    }

    try {
        $adkRegKey = Get-InstalledProgramRegKey -DisplayName $displayName

        if (-not $adkRegKey) {
            return $false
        }

        $installedADKVersion = $adkRegKey.GetValue("DisplayVersion")

        # Retrieve content of Microsoft documentation page
        $adkWebPage = Invoke-RestMethod "https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install" -Headers $Headers -UserAgent $UserAgent
        # Specify regex pattern for ADK version
        $adkVersionPattern = 'ADK\s+(\d+(\.\d+)+)'
        # Check for regex pattern match
        $adkVersionMatch = [regex]::Match($adkWebPage, $adkVersionPattern)

        if (-not $adkVersionMatch.Success) {
            WriteLog "Failed to retrieve latest ADK version from web page."
            return $false
        }

        # Extract ADK version from the matched pattern
        $latestADKVersion = $adkVersionMatch.Groups[1].Value

        if ($installedADKVersion -eq $latestADKVersion) {
            WriteLog "Installed $ADKOption version $installedADKVersion is the latest."
            return $true
        }
        else {
            WriteLog "Installed $ADKOption version $installedADKVersion is not the latest ($latestADKVersion)"
            return $false
        }
    }
    catch {
        WriteLog "An error occurred while confirming the ADK version: $_"
        return $false
    }
}

function Get-ADK {
    # Check if latest ADK and WinPE add-on are installed
    if ($UpdateADK) {
        WriteLog "Checking if latest ADK and WinPE add-on are installed"
        $latestADKInstalled = Confirm-ADKVersionIsLatest -ADKOption "Windows ADK"
        $latestWinPEInstalled = Confirm-ADKVersionIsLatest -ADKOption "WinPE add-on"

        # Uninstall older versions and install latest versions if necessary
        if (-not $latestADKInstalled) {
            Uninstall-ADK -ADKOption "Windows ADK"
            Install-ADK -ADKOption "Windows ADK"
        }

        if (-not $latestWinPEInstalled) {
            Uninstall-ADK -ADKOption "WinPE add-on"
            Install-ADK -ADKOption "WinPE add-on"
        }
    }

    # Define registry path
    $adkPathKey = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots"
    $adkPathName = "KitsRoot10"

    # Check if ADK installation path exists in registry
    $adkPathNameExists = (Get-ItemProperty -Path $adkPathKey -Name $adkPathName -ErrorAction SilentlyContinue)

    if ($adkPathNameExists) {
        # Get the ADK installation path
        WriteLog 'Get ADK Path'
        $adkPath = (Get-ItemProperty -Path $adkPathKey -Name $adkPathName).$adkPathName
        WriteLog "ADK located at $adkPath"
    }
    else {
        throw "Windows ADK installation path could not be found."
    }

    # If ADK was already installed, then check if the Windows Deployment Tools feature is also installed
    $deploymentToolsRegKey = Get-InstalledProgramRegKey -DisplayName "Windows Deployment Tools"

    if (-not $deploymentToolsRegKey) {
        WriteLog "ADK is installed, but the Windows Deployment Tools feature is not installed."
        $adkRegKey = Get-InstalledProgramRegKey -DisplayName "Windows Assessment and Deployment Kit"
        $adkBundleCachePath = $adkRegKey.GetValue("BundleCachePath")
        if ($adkBundleCachePath) {
            WriteLog "Installing Windows Deployment Tools..."
            $adkInstallPath = $adkPath.TrimEnd('\')
            Invoke-Process $adkBundleCachePath "/quiet /installpath ""$adkInstallPath"" /features OptionId.DeploymentTools" | Out-Null
            WriteLog "Windows Deployment Tools installed successfully."
        }
        else {
            throw "Failed to retrieve path to adksetup.exe to install the Windows Deployment Tools. Please manually install it."
        }
    }
    return $adkPath
}
function Get-ProductsCab {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutFile,
        [Parameter(Mandatory = $true)]
        [ValidateSet('x64', 'arm64')]
        [string]$Architecture,
        [Parameter(Mandatory = $true)]
        [string]$BuildVersion
    )

    $productsArchitecture = if ($Architecture -eq 'arm64') { 'arm64' } else { 'amd64' }
    $productsParam = "PN=Windows.Products.Cab.$productsArchitecture&V=$BuildVersion"
    $deviceAttributes = "DUScan=1;OSVersion=10.0.26100.1"

    $bodyObj = [ordered]@{
        Products         = $productsParam
        DeviceAttributes = $deviceAttributes
    }
    $bodyJson = $bodyObj | ConvertTo-Json -Compress

    $searchUri = 'https://fe3.delivery.mp.microsoft.com/UpdateMetadataService/updates/search/v1/bydeviceinfo'

    WriteLog "Requesting products.cab location from Windows Update service..."
    try {
        $searchResponse = Invoke-RestMethod -Uri $searchUri -Method Post -ContentType 'application/json' -Headers @{ Accept = '*/*' } -Body $bodyJson
    }
    catch {
        WriteLog "Failed to retrieve products.cab metadata: $($_.Exception.Message)"
        throw
    }

    if ($searchResponse -is [System.Array]) { $searchResponse = $searchResponse[0] }
    if (-not $searchResponse.FileLocations) { throw "Search response did not include FileLocations." }

    $fileRec = $searchResponse.FileLocations | Where-Object { $_.FileName -eq 'products.cab' } | Select-Object -First 1
    if (-not $fileRec) { throw "products.cab entry not found in FileLocations." }

    $downloadUrl = $fileRec.Url
    $serverDigestB64 = $fileRec.Digest
    $serverSize = [int64]$fileRec.Size
    $updateId = $searchResponse.UpdateIds[0]

    try {
        $metaUri = "https://fe3.delivery.mp.microsoft.com/UpdateMetadataService/updates/v1/$updateId"
        $meta = Invoke-RestMethod -Uri $metaUri -Method Get -Headers @{ Accept = '*/*' }
        if ($meta.LocalizedProperties.Count -gt 0) {
            $title = $meta.LocalizedProperties[0].Title
            WriteLog "Resolved update: $title"
        }
        else {
            WriteLog "Resolved update id: $updateId"
        }
    }
    catch {
        WriteLog "Resolved update id: $updateId"
    }

    $destDir = Split-Path -Path $OutFile -Parent
    if ($destDir -and -not (Test-Path $destDir)) {
        [void](New-Item -ItemType Directory -Path $destDir)
    }

    WriteLog "Downloading products.cab to $OutFile ..."
    $downloadHeaders = @{ Accept = '*/*' }
    Invoke-WebRequest -Uri $downloadUrl -OutFile $OutFile -Headers $downloadHeaders -UserAgent $UserAgent

    $actualSize = (Get-Item $OutFile).Length
    if ($actualSize -ne $serverSize) {
        throw "Size check failed. Expected $serverSize bytes. Got $actualSize bytes."
    }

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $fs = [System.IO.File]::OpenRead($OutFile)
    try {
        $hashBytes = $sha256.ComputeHash($fs)
    }
    finally {
        $fs.Dispose()
    }
    $actualDigestB64 = [Convert]::ToBase64String($hashBytes)

    if ($actualDigestB64 -ne $serverDigestB64) {
        throw "Digest check failed. Expected $serverDigestB64. Got $actualDigestB64."
    }

    WriteLog "products.cab downloaded and verified successfully."
    return $OutFile
}

function Get-WindowsESDMetadata {
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet(10, 11)]
        [int]$WindowsRelease,

        [Parameter(Mandatory = $false)]
        [ValidateSet('x86', 'x64', 'ARM64')]
        [string]$WindowsArch,

        [Parameter(Mandatory = $false)]
        [string]$WindowsLang,

        [Parameter(Mandatory = $false)]
        [ValidateSet('consumer', 'business')]
        [string]$MediaType
    )
    WriteLog "Resolving Windows $WindowsRelease ESD metadata"
    $cabFilePath = Join-Path $PSScriptRoot "tempCabFile.cab"
    $xmlFilePath = Join-Path $PSScriptRoot "products.xml"
    $esdMetadata = $null
    $OriginalVerbosePreference = $VerbosePreference
    $VerbosePreference = 'SilentlyContinue'
    try {
        if ($WindowsRelease -eq 10) {
            WriteLog "Downloading Cab file"
            Invoke-WebRequest -Uri 'https://go.microsoft.com/fwlink/?LinkId=841361' -OutFile $cabFilePath -Headers $Headers -UserAgent $UserAgent
        }
        elseif ($WindowsRelease -eq 11) {
            WriteLog "Downloading Cab file"
            $buildVersionMap = @{
                '22H2' = '22621.0.0.0'
                '23H2' = '22631.0.0.0'
                '24H2' = '26100.0.0.0'
                '25H2' = '26100.0.0.0'
            }
            $normalizedVersion = $WindowsVersion.ToUpper()
            if ($buildVersionMap.ContainsKey($normalizedVersion)) {
                $buildVersion = $buildVersionMap[$normalizedVersion]
            }
            else {
                WriteLog "No explicit build mapping found for Windows 11 version '$WindowsVersion'. Defaulting products.cab build token to 26100.0.0.0."
                $buildVersion = '26100.0.0.0'
            }

            $cabArchitecture = if ($WindowsArch -eq 'ARM64') { 'arm64' } else { 'x64' }
            Get-ProductsCab -OutFile $cabFilePath -Architecture $cabArchitecture -BuildVersion $buildVersion | Out-Null
        }
        else {
            throw "Downloading Windows $WindowsRelease is not supported. Please use the -ISOPath parameter to specify the path to the Windows $WindowsRelease ISO file."
        }
        WriteLog "products.cab download succeeded"
    }
    finally {
        $VerbosePreference = $OriginalVerbosePreference
    }

    WriteLog "Extracting Products XML from cab"
    Invoke-Process Expand "-F:*.xml $cabFilePath $xmlFilePath" | Out-Null
    WriteLog "Products XML extracted"

    [xml]$xmlContent = Get-Content -Path $xmlFilePath
    $clientType = if ($MediaType -eq 'consumer') { 'CLIENTCONSUMER' } else { 'CLIENTBUSINESS' }

    foreach ($file in $xmlContent.MCT.Catalogs.Catalog.PublishedMedia.Files.File) {
        if ($file.Architecture -eq $WindowsArch -and $file.LanguageCode -eq $WindowsLang -and $file.FilePath -like "*$clientType*") {
            $fileName = Split-Path $file.FilePath -Leaf
            $esdFilePath = Join-Path $PSScriptRoot $fileName
            $esdVersion = $null
            if ($file.FileName -match '^([0-9]+\.[0-9]+)') {
                $esdVersion = $matches[1]
            }

            $esdMetadata = [pscustomobject]@{
                FileUrl   = $file.FilePath
                FileName  = $fileName
                LocalPath = $esdFilePath
                Version   = $esdVersion
            }
            break
        }
    }

    if ($esdMetadata) {
        WriteLog "Resolved ESD metadata: $($esdMetadata.FileName) (Version: $($esdMetadata.Version))"
    }
    else {
        WriteLog "No matching ESD entry found in products.xml."
    }

    WriteLog "Cleaning up temporary cab and xml files"
    Remove-Item -Path $cabFilePath -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $xmlFilePath -Force -ErrorAction SilentlyContinue

    return $esdMetadata
}

function Get-WindowsESD {
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet(10, 11)]
        [int]$WindowsRelease,

        [Parameter(Mandatory = $false)]
        [ValidateSet('x86', 'x64', 'ARM64')]
        [string]$WindowsArch,

        [Parameter(Mandatory = $false)]
        [string]$WindowsLang,

        [Parameter(Mandatory = $false)]
        [ValidateSet('consumer', 'business')]
        [string]$MediaType,

        [Parameter(Mandatory = $false)]
        [pscustomobject]$Metadata
    )
    WriteLog "Downloading Windows $WindowsRelease ESD file"
    WriteLog "Windows Architecture: $WindowsArch"
    WriteLog "Windows Language: $WindowsLang"
    WriteLog "Windows Media Type: $MediaType"

    $esdMetadata = $Metadata
    if (-not $esdMetadata) {
        $esdMetadata = Get-WindowsESDMetadata -WindowsRelease $WindowsRelease -WindowsArch $WindowsArch -WindowsLang $WindowsLang -MediaType $MediaType
    }
    if (-not $esdMetadata) {
        throw "Unable to resolve Windows ESD metadata."
    }

    $esdFilePath = $esdMetadata.LocalPath
    if (-not (Test-Path $esdFilePath)) {
        WriteLog "Downloading $($esdMetadata.FileUrl) to $esdFilePath"
        $OriginalVerbosePreference = $VerbosePreference
        $VerbosePreference = 'SilentlyContinue'
        Mark-DownloadInProgress -FFUDevelopmentPath $FFUDevelopmentPath -TargetPath $esdFilePath
        Start-BitsTransferWithRetry -Source $esdMetadata.FileUrl -Destination $esdFilePath
        Clear-DownloadInProgress -FFUDevelopmentPath $FFUDevelopmentPath -TargetPath $esdFilePath
        $VerbosePreference = $OriginalVerbosePreference
        WriteLog "ESD download succeeded"
    }
    else {
        WriteLog "Found existing ESD at $esdFilePath, skipping download"
    }

    return $esdFilePath
}

function Get-ODTURL {
    try {
        [String]$ODTPage = Invoke-WebRequest 'https://www.microsoft.com/en-us/download/details.aspx?id=49117' -Headers $Headers -UserAgent $UserAgent -ErrorAction Stop

        # Extract JSON data from the webpage
        if ($ODTPage -match '<script>window\.__DLCDetails__=(.*?)<\/script>') {
            # Parse JSON content
            $jsonContent = $matches[1] | ConvertFrom-Json
            $ODTURL = $jsonContent.dlcDetailsView.downloadFile[0].url

            if ($ODTURL) {
                return $ODTURL
            }
            else {
                WriteLog 'Cannot find the ODT download URL in the JSON content'
                throw 'Cannot find the ODT download URL in the JSON content'
            }
        }
        else {
            WriteLog 'Failed to extract JSON content from the ODT webpage'
            throw 'Failed to extract JSON content from the ODT webpage'
        }
    }
    catch {
        WriteLog $_.Exception.Message
        throw 'An error occurred while retrieving the ODT URL.'
    }
}

function Get-Office {
    # If a custom Office Config XML is provided via config file, use its filename for the installation.
    # The UI script is responsible for copying the file itself to the OfficePath.
    if ((Get-Variable -Name 'OfficeConfigXMLFile' -ErrorAction SilentlyContinue) -and -not([string]::IsNullOrEmpty($OfficeConfigXMLFile))) {
        $script:OfficeInstallXML = Split-Path -Path $OfficeConfigXMLFile -Leaf
        WriteLog "A custom Office configuration file was specified. Using '$($script:OfficeInstallXML)' for installation."
    }
    #Download ODT
    $ODTUrl = Get-ODTURL
    $ODTInstallFile = "$OfficePath\odtsetup.exe"
    WriteLog "Downloading Office Deployment Toolkit from $ODTUrl to $ODTInstallFile"
    $OriginalVerbosePreference = $VerbosePreference
    $VerbosePreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $ODTUrl -OutFile $ODTInstallFile -Headers $Headers -UserAgent $UserAgent
    $VerbosePreference = $OriginalVerbosePreference

    # Extract ODT
    WriteLog "Extracting ODT to $OfficePath"
    Invoke-Process $ODTInstallFile "/extract:$OfficePath /quiet" | Out-Null

    # Run setup.exe with config.xml and modify xml file to download to $OfficePath
    $xmlContent = [xml](Get-Content $OfficeDownloadXML)
    $xmlContent.Configuration.Add.SourcePath = $OfficePath
    $xmlContent.Save($OfficeDownloadXML)
    Mark-DownloadInProgress -FFUDevelopmentPath $FFUDevelopmentPath -TargetPath $OfficePath
    WriteLog "Downloading M365 Apps/Office to $OfficePath"
    Invoke-Process $OfficePath\setup.exe "/download $OfficeDownloadXML" | Out-Null
    Clear-DownloadInProgress -FFUDevelopmentPath $FFUDevelopmentPath -TargetPath $OfficePath

    WriteLog "Cleaning up ODT default config files"
    #Clean up default configuration files
    Remove-Item -Path "$OfficePath\configuration*" -Force

    #Create Install-Office.ps1 in $orchestrationpath
    WriteLog "Creating $orchestrationpath\Install-Office.ps1"   
    $installOfficePath = Join-Path -Path $orchestrationpath -ChildPath "Install-Office.ps1"
    # Create the Install-Office.ps1 file
    $installOfficeCommand = "& d:\Office\setup.exe /configure d:\office\$OfficeInstallXML"
    Set-Content -Path $installOfficePath -Value $installOfficeCommand -Force
    WriteLog "Install-Office.ps1 created successfully at $installOfficePath"

    #Remove the ODT setup file
    WriteLog "Removing ODT setup file"
    Remove-Item -Path $ODTInstallFile -Force
    WriteLog "ODT setup file removed"
}

function Get-KBLink {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )
    $OriginalVerbosePreference = $VerbosePreference
    $VerbosePreference = 'SilentlyContinue'
    $results = Invoke-WebRequest -Uri "http://www.catalog.update.microsoft.com/Search.aspx?q=$Name" -Headers $Headers -UserAgent $UserAgent
    $VerbosePreference = $OriginalVerbosePreference

    # Extract the first KB article ID and Windows version (if present) from the HTML content and store globally
    # Edge and Defender do not have KB article IDs
    if ($Name -notmatch 'Defender|Edge') {
        $global:LastKBArticleID = $null
        $global:LastKBWindowsVersion = $null
        if ($results.Content -match '\(KB(\d+)\)[^(<]*\(([0-9]+\.[0-9]+)\)\s*<') {
            $kbArticleID = "KB$($matches[1])"
            $global:LastKBArticleID = $kbArticleID
            $global:LastKBWindowsVersion = $matches[2]
            WriteLog "Found KB article ID: $kbArticleID with Windows version $($matches[2])"
        }
        elseif ($results.Content -match '>\s*([^\(<]+)\(KB(\d+)\)(?:\s*\([^)]+\))*\s*<') {
            $kbArticleID = "KB$($matches[2])"
            $global:LastKBArticleID = $kbArticleID
            WriteLog "Found KB article ID: $kbArticleID (no Windows version found)"
        }
        else {
            WriteLog "No KB article ID found in search results."
        }
    }

    $kbids = $results.InputFields |
    Where-Object { $_.type -eq 'Button' -and $_.Value -eq 'Download' } |
    Select-Object -ExpandProperty  ID

    if (-not $kbids) {
        Write-Warning -Message "No results found for $Name"
        return
    }

    $guids = $results.Links |
    Where-Object ID -match '_link' |
    Where-Object { $_.OuterHTML -match ( "(?=.*" + ( $Filter -join ")(?=.*" ) + ")" ) } |
    Select-Object -First 1 |
    ForEach-Object { $_.id.replace('_link', '') } |
    Where-Object { $_ -in $kbids }

    if (-not $guids) {
        Write-Warning -Message "No file found for $Name"
        return
    }

    foreach ($guid in $guids) {
        # Write-Verbose -Message "Downloading information for $guid"
        $post = @{ size = 0; updateID = $guid; uidInfo = $guid } | ConvertTo-Json -Compress
        $body = @{ updateIDs = "[$post]" }
        $OriginalVerbosePreference = $VerbosePreference
        $VerbosePreference = 'SilentlyContinue'
        $links = Invoke-WebRequest -Uri 'https://www.catalog.update.microsoft.com/DownloadDialog.aspx' -Method Post -Body $body -Headers $Headers -UserAgent $UserAgent |
        Select-Object -ExpandProperty Content |
        Select-String -AllMatches -Pattern "http[s]?://[^']*\.microsoft\.com/[^']*|http[s]?://[^']*\.windowsupdate\.com/[^']*" |
        Select-Object -Unique
        $VerbosePreference = $OriginalVerbosePreference

        foreach ($link in $links) {
            $link.matches.value
            #Filter out cab files
            # #if ($link -notmatch '\.cab') {
            #     $link.matches.value
            # }
                    
        }
    }  
}


function Get-UpdateFileInfo {
    [CmdletBinding()]
    param(
        [string[]]$Name
    )
    $updateFileInfos = [System.Collections.Generic.List[pscustomobject]]::new()

    foreach ($kb in $Name) {
        $links = Get-KBLink -Name $kb
        foreach ($link in $links) {
            $fileName = ($link -split '/')[-1]

            $architectureMatch = $false
            if ($link -match 'x64' -or $link -match 'amd64') {
                if ($WindowsArch -eq 'x64') { $architectureMatch = $true }
            }
            elseif ($link -match 'arm64') {
                if ($WindowsArch -eq 'arm64') { $architectureMatch = $true }
            }
            elseif ($link -match 'x86') {
                if ($WindowsArch -eq 'x86') { $architectureMatch = $true }
            }
            else {
                # If no architecture is specified in the URL, we assume the search query was specific enough.
                # The alternative is to download the file to check, which defeats the purpose of this function.
                $architectureMatch = $true
            }

            if ($architectureMatch) {
                # Check for duplicates before adding
                if (-not ($updateFileInfos.Name -contains $fileName)) {
                    $updateFileInfos.Add([pscustomobject]@{
                            Name = $fileName
                            Url  = $link
                        })
                }
            }
        }
    }
    return $updateFileInfos
}

function Save-KB {
    [CmdletBinding()]
    param(
        [string[]]$Name,
        [string]$Path
    )
    foreach ($kb in $name) {
        $links = Get-KBLink -Name $kb
        foreach ($link in $links) {
            # if (!($link -match 'x64' -or $link -match 'amd64' -or $link -match 'x86' -or $link -match 'arm64')) {
            #     WriteLog "No architecture found in $link, skipping"
            #     continue
            # }

            if ($link -match 'x64' -or $link -match 'amd64') {
                if ($WindowsArch -eq 'x64') {
                    Writelog "Downloading $link for $WindowsArch to $Path"
                    Start-BitsTransferWithRetry -Source $link -Destination $Path
                    $fileName = ($link -split '/')[-1]
                    Writelog "Returning $fileName"
                }
                
            }
            elseif ($link -match 'arm64') {
                if ($WindowsArch -eq 'arm64') {
                    Writelog "Downloading $Link for $WindowsArch to $Path"
                    Start-BitsTransferWithRetry -Source $link -Destination $Path
                    $fileName = ($link -split '/')[-1]
                    Writelog "Returning $fileName"
                }
            }
            elseif ($link -match 'x86') {
                if ($WindowsArch -eq 'x86') {
                    Writelog "Downloading $link for $WindowsArch to $Path"
                    Start-BitsTransferWithRetry -Source $link -Destination $Path
                    $fileName = ($link -split '/')[-1]
                    Writelog "Returning $fileName"
                }

            }
            else {
                WriteLog "No architecture found in $link"
                
                #If no architecture is found, download the file and run it through Get-PEArchitecture to determine the architecture
                Writelog "Downloading $link to $Path and analyzing file for architecture"
                Start-BitsTransferWithRetry -Source $link -Destination $Path

                #Take the file and run it through Get-PEArchitecture to determine the architecture
                $fileName = ($link -split '/')[-1]
                $filePath = Join-Path -Path $Path -ChildPath $fileName
                $arch = Get-PEArchitecture -FilePath $filePath
                Writelog "$fileName is $arch"
                #If the architecture matches $WindowsArch, keep the file, otherwise delete it
                if ($arch -eq $WindowsArch) {
                    Writelog "Architecture for $fileName matches $WindowsArch, keeping file"
                    return $fileName
                }
                else {
                    Writelog "Deleting $fileName, architecture does not match"
                    Remove-Item -Path $filePath -Force
                }
            }
             
        }
    }
    return $fileName
}

function New-AppsISO {
    #Create Apps ISO file
    $OSCDIMG = "$adkpath`Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
    #Adding Long Path support for AppsPath to prevent issues with oscdimg
    $AppsPath = '\\?\' + $AppsPath
    Invoke-Process $OSCDIMG "-n -m -d $Appspath $AppsISO" | Out-Null  
}
function Get-WimFromISO {
    #Mount ISO, get Wim file
    $mountResult = Mount-DiskImage -ImagePath $isoPath -PassThru
    $sourcesFolder = ($mountResult | Get-Volume).DriveLetter + ":\sources\"

    # Check for install.wim or install.esd
    $wimPath = (Get-ChildItem $sourcesFolder\install.* | Where-Object { $_.Name -match "install\.(wim|esd)" }).FullName

    if ($wimPath) {
        WriteLog "The path to the install file is: $wimPath"
    }
    else {
        WriteLog "No install.wim or install.esd file found in: $sourcesFolder"
    }

    return $wimPath
}

function Get-Index {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WindowsImagePath,

        [Parameter(Mandatory = $true)]
        [string]$WindowsSKU
    )

    # Get the available indexes in the WIM/ESD
    $imageIndexes = Get-WindowsImage -ImagePath $WindowsImagePath

    # Normalize SKU and determine if Desktop Experience is explicitly requested (Server only)
    $normalizedWindowsSKU = $WindowsSKU.Trim()
    $isDesktopExperienceRequested = $normalizedWindowsSKU -match '\(Desktop Experience\)'
    $normalizedWindowsSKU = $normalizedWindowsSKU -replace '\s*\(Desktop Experience\)\s*', ''

    # Map user-selected SKU to language-independent EditionId values
    # Notes:
    # - Client: EditionId values are stable across languages (e.g. Professional, Core, Education)
    # - Server: Desktop Experience vs Core is differentiated by InstallationType (EditionId is the same)
    $editionIdCandidates = switch ($normalizedWindowsSKU) {
        'Home' { @('Core') }
        'Core' { @('Core') }

        'Home N' { @('CoreN') }
        'CoreN' { @('CoreN') }

        'Home Single Language' { @('CoreSingleLanguage') }
        'CoreSingleLanguage' { @('CoreSingleLanguage') }

        'Education' { @('Education') }
        'Education N' { @('EducationN') }
        'EducationN' { @('EducationN') }

        'Pro' { @('Professional') }
        'Professional' { @('Professional') }

        'Pro N' { @('ProfessionalN') }
        'ProfessionalN' { @('ProfessionalN') }

        'Pro Education' { @('ProfessionalEducation') }
        'ProfessionalEducation' { @('ProfessionalEducation') }

        'Pro Education N' { @('ProfessionalEducationN') }
        'ProfessionalEducationN' { @('ProfessionalEducationN') }

        'Pro for Workstations' { @('ProfessionalWorkstation') }
        'ProfessionalWorkstation' { @('ProfessionalWorkstation') }

        'Pro N for Workstations' { @('ProfessionalWorkstationN') }
        'ProfessionalWorkstationN' { @('ProfessionalWorkstationN') }

        'Enterprise' { @('Enterprise') }
        'Enterprise N' { @('EnterpriseN') }
        'EnterpriseN' { @('EnterpriseN') }

        'Enterprise LTSC' { @('EnterpriseS') }
        'Enterprise 2016 LTSB' { @('EnterpriseS') }
        'EnterpriseS' { @('EnterpriseS') }

        'Enterprise N LTSC' { @('EnterpriseSN') }
        'Enterprise N 2016 LTSB' { @('EnterpriseSN') }
        'EnterpriseSN' { @('EnterpriseSN') }

        'IoT Enterprise LTSC' { @('IoTEnterpriseS') }
        'IoTEnterpriseS' { @('IoTEnterpriseS') }

        'IoT Enterprise N LTSC' { @('IoTEnterpriseSN') }
        'IoTEnterpriseSN' { @('IoTEnterpriseSN') }

        'Standard' { @('ServerStandard') }
        'ServerStandard' { @('ServerStandard') }

        'Datacenter' { @('ServerDatacenter') }
        'ServerDatacenter' { @('ServerDatacenter') }

        default { @() }
    }

    # Determine preferred InstallationType for Server images
    $preferredInstallationType = $null
    if ($normalizedWindowsSKU -in @('Standard', 'Datacenter', 'ServerStandard', 'ServerDatacenter')) {
        if ($isDesktopExperienceRequested) {
            $preferredInstallationType = 'Server'
        }
        else {
            $preferredInstallationType = 'Server Core'
        }
    }

    # If we can map SKU -> EditionId, attempt a non-interactive match
    if ($editionIdCandidates.Count -gt 0) {
        # Build per-index metadata (EditionId, InstallationType) to match deterministically
        $imageMetadata = @(foreach ($imageIndex in $imageIndexes) {
            try {
                $details = Get-WindowsImage -ImagePath $WindowsImagePath -Index $imageIndex.ImageIndex
                [pscustomobject]@{
                    ImageIndex       = $details.ImageIndex
                    ImageName        = $details.ImageName
                    ImageSize        = $details.ImageSize
                    EditionId        = $details.EditionId
                    InstallationType = $details.InstallationType
                }
            }
            catch {
                $null
            }
        }) | Where-Object { $null -ne $_ }

        # Match by EditionId first
        $imageMatches = $imageMetadata | Where-Object { $_.EditionId -in $editionIdCandidates }

        # If this is a Server SKU, prefer the requested InstallationType (Server vs Server Core)
        if ($null -ne $preferredInstallationType -and $imageMatches.Count -gt 0) {
            $preferredImageMatches = $imageMatches | Where-Object { $_.InstallationType -eq $preferredInstallationType }
            if ($preferredImageMatches.Count -gt 0) {
                $imageMatches = $preferredImageMatches
            }
        }

        # If multiple matches remain, pick the largest image (Desktop Experience tends to be larger)
        if ($imageMatches.Count -gt 0) {
            $bestMatch = $imageMatches | Sort-Object -Property ImageSize -Descending | Select-Object -First 1
            WriteLog "Selected Windows image index $($bestMatch.ImageIndex) (SKU='$WindowsSKU', EditionId='$($bestMatch.EditionId)', InstallationType='$($bestMatch.InstallationType)'): $($bestMatch.ImageName)"
            return $bestMatch.ImageIndex
        }
    }

    # Final fallback: prompt the user to select an ImageName
    # Look for the numbers 10, 11, 2016, 2019, 2022+ in the ImageName
    $relevantImageIndexes = $imageIndexes | Where-Object { ($_.ImageName -match "(10|11|2016|2019|202\d)") }

    WriteLog "No matching image index found for SKU '$WindowsSKU' in '$WindowsImagePath'. Prompting user to select an ImageName."

    while ($true) {
        # Present list of ImageNames to the end user if no matching ImageIndex is found
        Write-Host "No matching ImageIndex found for Windows SKU '$WindowsSKU'. Please select an ImageName from the list below:"

        $i = 1
        $relevantImageIndexes | ForEach-Object {
            Write-Host "$i. $($_.ImageName)"
            $i++
        }

        # Ask for user input
        $inputValue = Read-Host "Enter the number of the ImageName you want to use"

        # Get selected ImageName based on user input
        $selectedImage = $relevantImageIndexes[$inputValue - 1]

        if ($selectedImage) {
            WriteLog "User selected Windows image index $($selectedImage.ImageIndex) (SKU='$WindowsSKU'): $($selectedImage.ImageName)"
            return $selectedImage.ImageIndex
        }
        else {
            Write-Host "Invalid selection, please try again."
        }
    }
}

#Create VHDX
function New-ScratchVhdx {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VhdxPath,
        [uint64]$SizeBytes = 50GB,
        [uint32]$LogicalSectorSizeBytes,
        [switch]$Dynamic,
        [Microsoft.PowerShell.Cmdletization.GeneratedTypes.Disk.PartitionStyle]$PartitionStyle = [Microsoft.PowerShell.Cmdletization.GeneratedTypes.Disk.PartitionStyle]::GPT
    )

    WriteLog "Creating new Scratch VHDX..."

    $newVHDX = New-VHD -Path $VhdxPath -SizeBytes $disksize -LogicalSectorSizeBytes $LogicalSectorSizeBytes -Dynamic:($Dynamic.IsPresent) 
    $toReturn = $newVHDX | Mount-VHD -Passthru | Initialize-Disk -PassThru -PartitionStyle GPT

    #Remove auto-created partition so we can create the correct partition layout
    remove-partition $toreturn.DiskNumber -PartitionNumber 1 -Confirm:$False 

    Writelog "Done."
    return $toReturn
}
#Add System Partition
function New-SystemPartition {
    param(
        [Parameter(Mandatory = $true)]
        [ciminstance]$VhdxDisk,
        [uint64]$SystemPartitionSize = 260MB
    )

    WriteLog "Creating System partition..."

    $sysPartition = $VhdxDisk | New-Partition -DriveLetter 'S' -Size $SystemPartitionSize -GptType "{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}" -IsHidden 
    $sysPartition | Format-Volume -FileSystem FAT32 -Force -NewFileSystemLabel "System" 

    WriteLog 'Done.'
    return $sysPartition.DriveLetter
}
#Add MSRPartition
function New-MSRPartition {
    param(
        [Parameter(Mandatory = $true)]
        [ciminstance]$VhdxDisk
    )

    WriteLog "Creating MSR partition..."

    # $toReturn = $VhdxDisk | New-Partition -AssignDriveLetter -Size 16MB -GptType "{e3c9e316-0b5c-4db8-817d-f92df00215ae}" -IsHidden | Out-Null
    $toReturn = $VhdxDisk | New-Partition -Size 16MB -GptType "{e3c9e316-0b5c-4db8-817d-f92df00215ae}" -IsHidden | Out-Null

    WriteLog "Done."

    return $toReturn
}
#Add OS Partition
function New-OSPartition {
    param(
        [Parameter(Mandatory = $true)]
        [ciminstance]$VhdxDisk,
        [Parameter(Mandatory = $true)]
        [string]$WimPath,
        [uint32]$WimIndex,
        [uint64]$OSPartitionSize = 0
    )

    WriteLog "Creating OS partition..."

    if ($OSPartitionSize -gt 0) {
        $osPartition = $vhdxDisk | New-Partition -DriveLetter 'W' -Size $OSPartitionSize -GptType "{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}" 
    }
    else {
        $osPartition = $vhdxDisk | New-Partition -DriveLetter 'W' -UseMaximumSize -GptType "{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}" 
    }

    $osPartition | Format-Volume -FileSystem NTFS -Confirm:$false -Force -NewFileSystemLabel "Windows" 
    WriteLog 'Done'
    Writelog "OS partition at drive $($osPartition.DriveLetter):"

    WriteLog "Writing Windows at $WimPath to OS partition at drive $($osPartition.DriveLetter):..."
    
    #Server 2019 is missing the Windows Overlay Filter (wof.sys), likely other Server SKUs are missing it as well. Script will error if trying to use the -compact switch on Server OSes
    if ((Get-CimInstance Win32_OperatingSystem).Caption -match "Server") {
        WriteLog (Expand-WindowsImage -ImagePath $WimPath -Index $WimIndex -ApplyPath "$($osPartition.DriveLetter):\")
    }
    elseif ($CompactOS) {
        WriteLog '$CompactOS is set to true, using -Compact switch to apply the WIM file to the OS partition.'
        WriteLog (Expand-WindowsImage -ImagePath $WimPath -Index $WimIndex -ApplyPath "$($osPartition.DriveLetter):\" -Compact)
    }
    else {
        WriteLog (Expand-WindowsImage -ImagePath $WimPath -Index $WimIndex -ApplyPath "$($osPartition.DriveLetter):\")
    }
    
    WriteLog 'Done'    
    return $osPartition
}
#Add Recovery partition
function New-RecoveryPartition {
    param(
        [Parameter(Mandatory = $true)]
        [ciminstance]$VhdxDisk,
        [Parameter(Mandatory = $true)]
        $OsPartition,
        [uint64]$RecoveryPartitionSize = 0,
        [ciminstance]$DataPartition
    )

    WriteLog "Creating empty Recovery partition (to be filled on first boot automatically)..."
    
    $calculatedRecoverySize = 0
    $recoveryPartition = $null

    if ($RecoveryPartitionSize -gt 0) {
        $calculatedRecoverySize = $RecoveryPartitionSize
    }
    else {
        $winReWim = Get-ChildItem "$($OsPartition.DriveLetter):\Windows\System32\Recovery\Winre.wim" -Attributes Hidden -ErrorAction SilentlyContinue

        if (($null -ne $winReWim) -and ($winReWim.Count -eq 1)) {
            # Wim size + 100MB is minimum WinRE partition size.
            # NTFS and other partitioning size differences account for about 17MB of space that's unavailable.
            # Adding 32MB as a buffer to ensure there's enough space to account for NTFS file system overhead.
            # Adding 250MB as per recommendations from 
            # https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/configure-uefigpt-based-hard-drive-partitions?view=windows-11#recovery-tools-partition
            $calculatedRecoverySize = $winReWim.Length + 250MB + 32MB

            WriteLog "Calculated space needed for recovery in bytes: $calculatedRecoverySize"

            if ($null -ne $DataPartition) {
                $DataPartition | Resize-Partition -Size ($DataPartition.Size - $calculatedRecoverySize)
                WriteLog "Data partition shrunk by $calculatedRecoverySize bytes for Recovery partition."
            }
            else {
                $newOsPartitionSize = [math]::Floor(($OsPartition.Size - $calculatedRecoverySize) / 4096) * 4096
                $OsPartition | Resize-Partition -Size $newOsPartitionSize
                WriteLog "OS partition shrunk by $calculatedRecoverySize bytes for Recovery partition."
            }

            $recoveryPartition = $VhdxDisk | New-Partition -DriveLetter 'R' -UseMaximumSize -GptType "{de94bba4-06d1-4d40-a16a-bfd50179d6ac}" `
            | Format-Volume -FileSystem NTFS -Confirm:$false -Force -NewFileSystemLabel 'Recovery' 

            WriteLog "Done. Recovery partition at drive $($recoveryPartition.DriveLetter):"
        }
        else {
            WriteLog "No WinRE.WIM found in the OS partition under \Windows\System32\Recovery."
            WriteLog "Skipping creating the Recovery partition."
            WriteLog "If a Recovery partition is desired, please re-run the script setting the -RecoveryPartitionSize flag as appropriate."
        }
    }

    return $recoveryPartition
}
#Add boot files
function Add-BootFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OsPartitionDriveLetter,
        [Parameter(Mandatory = $true)]
        [string]$SystemPartitionDriveLetter,
        [string]$FirmwareType = 'UEFI'
    )

    WriteLog "Adding boot files for `"$($OsPartitionDriveLetter):\Windows`" to System partition `"$($SystemPartitionDriveLetter):`"..."
    Invoke-Process bcdboot "$($OsPartitionDriveLetter):\Windows /S $($SystemPartitionDriveLetter): /F $FirmwareType" | Out-Null
    WriteLog "Done."
}

function Enable-WindowsFeaturesByName {
    param (
        [Parameter(Mandatory = $true)]
        [string]$FeatureNames,
        [Parameter(Mandatory = $true)]
        [string]$Source
    )

    $FeaturesArray = $FeatureNames.Split(';')

    # Looping through each feature and enabling it
    foreach ($FeatureName in $FeaturesArray) {
        WriteLog "Enabling Windows Optional feature: $FeatureName"
        Enable-WindowsOptionalFeature -Path $WindowsPartition -FeatureName $FeatureName -All -Source $Source | Out-Null
        WriteLog "Done"
    }
}

#Dismount VHDX
function Dismount-ScratchVhdx {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VhdxPath
    )

    if (Test-Path $VhdxPath) {
        WriteLog "Dismounting scratch VHDX..."
        Dismount-VHD -Path $VhdxPath
        WriteLog "Done."
    }
}

function New-FFUVM {
    #Create new Gen2 VM
    $VM = New-VM -Name $VMName -Path $VMPath -MemoryStartupBytes $memory -VHDPath $VHDXPath -Generation 2
    Set-VMProcessor -VMName $VMName -Count $processors

    #Mount AppsISO
    Add-VMDvdDrive -VMName $VMName -Path $AppsISO
   
    #Set Hard Drive as boot device
    $VMHardDiskDrive = Get-VMHarddiskdrive -VMName $VMName 
    Set-VMFirmware -VMName $VMName -FirstBootDevice $VMHardDiskDrive
    Set-VM -Name $VMName -AutomaticCheckpointsEnabled $false -StaticMemory

    #Configure TPM
    New-HgsGuardian -Name $VMName -GenerateCertificates
    $owner = get-hgsguardian -Name $VMName
    $kp = New-HgsKeyProtector -Owner $owner -AllowUntrustedRoot
    Set-VMKeyProtector -VMName $VMName -KeyProtector $kp.RawData
    Enable-VMTPM -VMName $VMName

    #Connect to VM
    WriteLog "Starting vmconnect localhost $VMName"
    & vmconnect localhost "$VMName"

    #Start VM
    Start-VM -Name $VMName

    return $VM
}

Function Set-CaptureFFU {
    $CaptureFFUScriptPath = "$FFUDevelopmentPath\WinPECaptureFFUFiles\CaptureFFU.ps1"

    # Workaround for PowerShell 7 issue on Windows 11 23H2 and earlier
    # https://github.com/PowerShell/PowerShell/issues/21645
    $osBuild = (Get-CimInstance -ClassName Win32_OperatingSystem).BuildNumber
    if ($osBuild -le 22631) {
        WriteLog "Applying workaround for PowerShell 7 LocalAccounts module issue on Windows 11 build $osBuild"
        Import-Module Microsoft.PowerShell.LocalAccounts -UseWindowsPowerShell
    }

    If (-not (Test-Path -Path $FFUCaptureLocation)) {
        WriteLog "Creating FFU capture location at $FFUCaptureLocation"
        New-Item -Path $FFUCaptureLocation -ItemType Directory -Force
        WriteLog "Successfully created FFU capture location at $FFUCaptureLocation"
    }

    # Create a standard user
    $UserExists = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
    if (-not $UserExists) {
        WriteLog "Creating FFU_User account as standard user"
        New-LocalUser -Name $UserName -AccountNeverExpires -NoPassword | Out-null
        WriteLog "Successfully created FFU_User account"
    }

    # Create a random password for the standard user
    $Password = New-Guid | Select-Object -ExpandProperty Guid
    $SecurePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
    Set-LocalUser -Name $UserName -Password $SecurePassword -PasswordNeverExpires:$true

    # Create a share of the $FFUCaptureLocation variable
    $ShareExists = Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue
    if (-not $ShareExists) {
        WriteLog "Creating $ShareName and giving access to $UserName"
        New-SmbShare -Name $ShareName -Path $FFUCaptureLocation -FullAccess $UserName | Out-Null
        WriteLog "Share created"
    }

    # Return the share path in the format of \\<IPAddress>\<ShareName> /user:<UserName> <password>
    $SharePath = "\\$VMHostIPAddress\$ShareName /user:$UserName $Password"
    $SharePath = "net use W: " + $SharePath + ' 2>&1'
    
    # Update CaptureFFU.ps1 script
    if (Test-Path -Path $CaptureFFUScriptPath) {
        $ScriptContent = Get-Content -Path $CaptureFFUScriptPath
        #Update variables in CaptureFFU.ps1 script ($VMHostIPAddress, $ShareName, $UserName, $Password)
        WriteLog 'Updating CaptureFFU.ps1 script with new share information'
        $ScriptContent = $ScriptContent -replace '(\$VMHostIPAddress = ).*', "`$1'$VMHostIPAddress'"
        $ScriptContent = $ScriptContent -replace '(\$ShareName = ).*', "`$1'$ShareName'"
        $ScriptContent = $ScriptContent -replace '(\$UserName = ).*', "`$1'$UserName'"
        $ScriptContent = $ScriptContent -replace '(\$Password = ).*', "`$1'$Password'"
        if (![string]::IsNullOrEmpty($CustomFFUNameTemplate)) {
            $ScriptContent = $ScriptContent -replace '(\$CustomFFUNameTemplate = ).*', "`$1'$CustomFFUNameTemplate'"
            WriteLog 'Updating CaptureFFU.ps1 script with new ffu name template information'
        }
        Set-Content -Path $CaptureFFUScriptPath -Value $ScriptContent
        WriteLog 'Update complete'
    }
    else {
        throw "CaptureFFU.ps1 script not found at $CaptureFFUScriptPath"
    }
}

function Get-PrivateProfileString {
    param (
        [Parameter()]
        [string]$FileName,
        [Parameter()]
        [string]$SectionName,
        [Parameter()]
        [string]$KeyName
    )

    # Read key from an INF/INI file. Use a larger buffer and allow it to grow if needed.
    $bufferSize = 4096
    $maxBufferSize = 65536
    $sbuilder = $null
    $charsCopied = 0

    while ($true) {
        $sbuilder = [System.Text.StringBuilder]::new($bufferSize)
        $charsCopied = [Win32.Kernel32]::GetPrivateProfileString($SectionName, $KeyName, "", $sbuilder, [uint32]$sbuilder.Capacity, $FileName)

        if ([int]$charsCopied -lt ($sbuilder.Capacity - 1)) {
            break
        }

        if ($bufferSize -ge $maxBufferSize) {
            break
        }

        $bufferSize = [Math]::Min(($bufferSize * 2), $maxBufferSize)
    }

    return $sbuilder.ToString()
}

function Get-PrivateProfileSection {
    param (
        [Parameter()]
        [string]$FileName,
        [Parameter()]
        [string]$SectionName
    )
    # Read the requested section from an INF/INI file
    # Some INF sections can be large; grow the buffer to avoid truncated results
    $hashTable = @{}
    $bufferSize = 16384
    $buffer = $null
    $charsCopied = 0

    while ($true) {
        $buffer = [byte[]]::new($bufferSize)
        $charsCopied = [Win32.Kernel32]::GetPrivateProfileSection($SectionName, $buffer, $buffer.Length, $FileName)

        # No section found or no content
        if ($charsCopied -eq 0) {
            return $hashTable
        }

        # If the returned data is close to the buffer size, assume truncation and retry bigger
        if (($charsCopied -ge ($bufferSize - 2)) -and ($bufferSize -lt 1048576)) {
            $bufferSize = $bufferSize * 2
            continue
        }

        break
    }

    # Convert only the returned portion of the buffer (Unicode = 2 bytes per char)
    $sectionText = [System.Text.Encoding]::Unicode.GetString($buffer, 0, ($charsCopied * 2))
    $keyValues = $sectionText.TrimEnd("`0").Split("`0")

    foreach ($keyValue in $keyValues) {
        if (![string]::IsNullOrEmpty($keyValue)) {
            $parts = $keyValue -split "=", 2
            if ($parts.Count -eq 2) {
                $hashTable[$parts[0]] = $parts[1]
            }
        }
    }

    return $hashTable
}
    
function Get-AvailableDriveLetter {
    # Get an unused drive letter for temporary SUBST mappings
    $usedLetters = (Get-PSDrive -PSProvider FileSystem).Name | ForEach-Object { $_.ToUpperInvariant() }
    for ($ascii = [int][char]'Z'; $ascii -ge [int][char]'A'; $ascii--) {
        $candidate = [char]$ascii
        if ($usedLetters -notcontains $candidate) {
            return $candidate
        }
    }
    return $null
}
    
function New-DriverSubstMapping {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath
    )
    
    # Map a long driver source folder to a short drive root using SUBST
    $resolvedPath = (Resolve-Path -Path $SourcePath -ErrorAction Stop).Path
    $driveLetter = Get-AvailableDriveLetter
    if ($null -eq $driveLetter) {
        throw 'No drive letters are available for SUBST mapping.'
    }
    $driveName = "$driveLetter`:"
    $mappedPath = "$driveLetter`:\"
    WriteLog "Mapping driver folder '$resolvedPath' to $driveName with SUBST."
    $escapedPath = $resolvedPath -replace '"', '""'
    $arguments = "/c subst $driveName `"$escapedPath`""
    Invoke-Process -FilePath cmd.exe -ArgumentList $arguments
    return [PSCustomObject]@{
        DriveLetter = $driveLetter
        DriveName   = $driveName
        DrivePath   = $mappedPath
    }
}
    
function Remove-DriverSubstMapping {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DriveLetter
    )
    
    # Remove the temporary SUBST mapping
    $driveName = "$DriveLetter`:"
    WriteLog "Removing SUBST drive $driveName"
    try {
        $arguments = "/c subst $driveName /d"
        Invoke-Process -FilePath cmd.exe -ArgumentList $arguments
    }
    catch {
        WriteLog "Failed to remove SUBST drive $($driveName): $_"
    }
}

function Invoke-DismDriverInjectionWithSubstLoop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ImagePath,

        [Parameter(Mandatory = $true)]
        [string]$DriverRoot
    )

    # Resolve input paths
    $resolvedImagePath = (Resolve-Path -Path $ImagePath -ErrorAction Stop).Path
    $resolvedDriverRoot = (Resolve-Path -Path $DriverRoot -ErrorAction Stop).Path

    # Discover INF files under the driver root
    WriteLog "Scanning for INF files under: $resolvedDriverRoot"
    $infFiles = Get-ChildItem -Path $resolvedDriverRoot -Filter '*.inf' -File -Recurse -ErrorAction SilentlyContinue
    if ($null -eq $infFiles -or $infFiles.Count -eq 0) {
        WriteLog "No INF files found under: $resolvedDriverRoot"
        return
    }

    # Determine the deepest stable folders we can map with SUBST (SUBST has its own max path constraints)
    # Strategy:
    # - Start at the INF parent folder
    # - If too long for SUBST, walk up until the path is short enough
    # - Deduplicate and avoid redundant child folders when a parent already covers them via DISM /Recurse
    $substTargetMaxLength = 240
    $candidateDirs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($infFile in $infFiles) {
        $candidateDir = Split-Path -Path $infFile.FullName -Parent

        while ($candidateDir.Length -gt $substTargetMaxLength) {
            $parentDir = Split-Path -Path $candidateDir -Parent
            if ([string]::IsNullOrWhiteSpace($parentDir) -or $parentDir -eq $candidateDir) {
                break
            }
            $candidateDir = $parentDir
        }

        if ($candidateDir.Length -gt $substTargetMaxLength) {
            WriteLog "Warning: Skipping INF folder due to SUBST length limit (len=$($candidateDir.Length)): $candidateDir"
            continue
        }

        [void]$candidateDirs.Add($candidateDir)
    }

    $sortedCandidates = $candidateDirs | Sort-Object Length, @{ Expression = { $_ }; Ascending = $true }
    $selectedDirs = [System.Collections.Generic.List[string]]::new()

    foreach ($candidateDir in $sortedCandidates) {
        $isCovered = $false
        foreach ($selectedDir in $selectedDirs) {
            if ($candidateDir.Equals($selectedDir, [System.StringComparison]::OrdinalIgnoreCase)) {
                $isCovered = $true
                break
            }

            $prefix = $selectedDir.TrimEnd('\') + '\'
            if ($candidateDir.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                $isCovered = $true
                break
            }
        }

        if (-not $isCovered) {
            [void]$selectedDirs.Add($candidateDir)
        }
    }

    $infDirs = $selectedDirs | Sort-Object
    WriteLog "Driver injection will process $($infDirs.Count) SUBST-safe folders (candidateFolders=$($candidateDirs.Count), INF total=$($infFiles.Count), substMaxLen=$substTargetMaxLength)."

    # Use a single SUBST drive letter and reuse it in a loop (map -> dism -> unmap)
    $driveLetter = Get-AvailableDriveLetter
    if ($null -eq $driveLetter) {
        throw 'No drive letters are available for SUBST mapping.'
    }

    $driveName = "$driveLetter`:"
    $drivePath = "$driveLetter`:\"
    WriteLog "Using SUBST drive $driveName for driver injection loop."

    $currentIndex = 0
    foreach ($infDir in $infDirs) {
        $currentIndex++
        $escapedPath = $infDir -replace '"', '""'

        try {
            WriteLog "[$currentIndex/$($infDirs.Count)] Mapping '$infDir' to $driveName with SUBST."
            $mapArgs = "/c subst $driveName `"$escapedPath`""
            Invoke-Process -FilePath cmd.exe -ArgumentList $mapArgs | Out-Null

            # Inject drivers (do not use \\?\ with DISM)
            $dismArgs = @(
                "/Image:`"$resolvedImagePath`""
                '/Add-Driver'
                "/Driver:$drivePath"
                '/Recurse'
            )

            WriteLog "dism.exe $($dismArgs -join ' ')"
            Invoke-Process -FilePath dism.exe -ArgumentList $dismArgs | Out-Null
        }
        catch {
            WriteLog "Warning: Driver injection failed for '$infDir': $($_.Exception.Message)"
        }
        finally {
            try {
                WriteLog "Removing SUBST drive $driveName"
                $unmapArgs = "/c subst $driveName /d"
                Invoke-Process -FilePath cmd.exe -ArgumentList $unmapArgs | Out-Null
            }
            catch {
                WriteLog "Warning: Failed removing SUBST drive $($driveName): $($_.Exception.Message)"
            }
        }
    }

    WriteLog "Driver injection loop complete for $resolvedDriverRoot"
}
    
function Copy-Drivers {
    param (
        [Parameter()]
        [string]$Path,
        [Parameter()]
        [string]$Output
    )
    # Find more information about device classes here:
    # https://learn.microsoft.com/en-us/windows-hardware/drivers/install/system-defined-device-setup-classes-available-to-vendors
    # For now, included are system devices, scsi and raid controllers, keyboards, mice and HID devices for touch support
    # 4D36E97D-E325-11CE-BFC1-08002BE10318 = System devices
    # 4D36E97B-E325-11CE-BFC1-08002BE10318 = SCSI, RAID, and NVMe Controllers
    # 4d36e96b-e325-11ce-bfc1-08002be10318 = Keyboards
    # 4d36e96f-e325-11ce-bfc1-08002be10318 = Mice and other pointing devices
    # 745a17a0-74d3-11d0-b6fe-00a0c90f57da = Human Interface Devices
    $filterGUIDs = @("{4D36E97D-E325-11CE-BFC1-08002BE10318}", "{4D36E97B-E325-11CE-BFC1-08002BE10318}", "{4d36e96b-e325-11ce-bfc1-08002be10318}", "{4d36e96f-e325-11ce-bfc1-08002be10318}", "{745a17a0-74d3-11d0-b6fe-00a0c90f57da}")
    $exclusionList = "wdmaudio.inf|Sound|Machine Learning|Camera|Firmware"

    # Log start and validate paths
    WriteLog "Copying PE drivers from '$Path' to '$Output' (WindowsArch: $WindowsArch)"
    if (-not (Test-Path -Path $Path)) {
        WriteLog "ERROR: Drivers source path not found: $Path"
        return
    }
    [void](New-Item -Path $Output -ItemType Directory -Force)
    
    $driverSourcePath = $Path
    $pathLength = $Path.Length
    
    # Determine common arch-specific SourceDisksFiles section names
    # Many INFs use 'amd64' rather than 'x64' for 64-bit paths (e.g. SourceDisksFiles.amd64)
    $sourceDisksFileSections = @("SourceDisksFiles")
    if ($WindowsArch -eq 'x64') {
        $sourceDisksFileSections += "SourceDisksFiles.amd64"
    }
    elseif ($WindowsArch -eq 'arm64') {
        $sourceDisksFileSections += "SourceDisksFiles.arm64"
    }
    
    $infFiles = Get-ChildItem -Path $Path -Recurse -Filter "*.inf"
    WriteLog "Found $($infFiles.Count) INF files under: $driverSourcePath"
    
    $matchedInfCount = 0
    $skippedInfCount = 0
    $copiedFileCount = 0
    $errorCount = 0
    
    for ($i = 0; $i -lt $infFiles.Count; $i++) {
        $infFullName = $infFiles[$i].FullName
        # Add long path prefix to handle long paths
        $longInfFullName = "\\?\$infFullName"
        $infPath = Split-Path -Path $infFullName
        $childPath = $infPath.Substring($pathLength).TrimStart('\')
        $targetPath = Join-Path -Path $Output -ChildPath $childPath
    
        # Log the INF files found
        WriteLog "Examining PE driver INF ($($i + 1)/$($infFiles.Count)): $infFullName"
    
        # Filter to known device classes
        # Some INFs include trailing comments after the value (e.g. "{GUID} ; TODO: ..."), so normalize to the GUID token only.
        $classGuidRaw = Get-PrivateProfileString -FileName $longInfFullName -SectionName "version" -KeyName "ClassGUID"
        $classGuid = $classGuidRaw
        if (-not [string]::IsNullOrWhiteSpace($classGuid)) {
            # Remove any trailing ';' comment and trim whitespace
            $classGuid = ($classGuid -split ';', 2)[0].Trim()

            # Extract the GUID token if the value contains other text
            if ($classGuid -match '\{[0-9A-Fa-f\-]{36}\}') {
                $classGuid = $matches[0]
            }
        }

        # WriteLog "ClassGUID: $classGuid"
        if ($classGuid -notin $filterGUIDs) {
            # WriteLog "Skipping PE driver INF due to GUID: $infFullName"
            $skippedInfCount++
            continue
        }
    
        # Avoid drivers that reference keywords from the exclusion list to keep the total size small
        if (((Get-Content -Path $infFullName) -match $exclusionList).Length -ne 0) {
            WriteLog "Skipping PE driver INF due to exclusion match: $infFullName"
            $skippedInfCount++
            continue
        }
    
        $matchedInfCount++
    
        # Log the INF being processed
        $providerName = (Get-PrivateProfileString -FileName $longInfFullName -SectionName "Version" -KeyName "Provider").Trim("%")
        if ([string]::IsNullOrWhiteSpace($providerName)) {
            $providerName = "Unknown Provider"
        }
    
        WriteLog "Processing PE driver INF: $infFullName"
        WriteLog "Provider: $providerName | ClassGUID: $classGuid"
        WriteLog "Target folder: $targetPath"
    
        [void](New-Item -Path $targetPath -ItemType Directory -Force)
    
        # Copy the INF itself
        try {
            Copy-Item -LiteralPath "$infFullName" -Destination "$targetPath" -Force -ErrorAction Stop
            $copiedFileCount++
            WriteLog "Copied: $infFullName -> $targetPath"
        }
        catch {
            $errorCount++
            WriteLog "ERROR: Failed to copy INF '$infFullName' to '$targetPath': $($_.Exception.Message)"
        }
    
        # Copy the catalog file (if specified)
        $CatalogFileName = Get-PrivateProfileString -FileName $longInfFullName -SectionName "version" -KeyName "Catalogfile"
        if (-not [string]::IsNullOrWhiteSpace($CatalogFileName)) {
            $catalogSource = Join-Path -Path $infPath -ChildPath $CatalogFileName
            if (Test-Path -Path $catalogSource) {
                try {
                    Copy-Item -LiteralPath "$catalogSource" -Destination "$targetPath" -Force -ErrorAction Stop
                    $copiedFileCount++
                    WriteLog "Copied: $catalogSource -> $targetPath"
                }
                catch {
                    $errorCount++
                    WriteLog "ERROR: Failed to copy catalog '$catalogSource' to '$targetPath': $($_.Exception.Message)"
                }
            }
            else {
                $errorCount++
                WriteLog "ERROR: Catalog file not found: $catalogSource (INF: $infFullName)"
            }
        }
        else {
            WriteLog "WARNING: No CatalogFile entry found in INF: $infFullName"
        }
    
        # Copy all files referenced by SourceDisksFiles sections
        foreach ($sectionName in $sourceDisksFileSections) {
            $sourceDiskFiles = Get-PrivateProfileSection -FileName $longInfFullName -SectionName $sectionName
            if ($sourceDiskFiles.Count -eq 0) {
                continue
            }
    
            WriteLog "Copying files from INF section [$sectionName] ($($sourceDiskFiles.Count) entries)"
    
            foreach ($sourceDiskFile in $sourceDiskFiles.Keys) {
                # Determine if the file lives in a subfolder relative to the INF path
                $rawValue = $sourceDiskFiles[$sourceDiskFile]
                $subdir = ""
    
                if (($null -ne $rawValue) -and ($rawValue.Contains(","))) {
                    $splitParts = $rawValue -split ","
                    if ($splitParts.Count -ge 2) {
                        $subdir = $splitParts[1]
                    }
                }
    
                if ([string]::IsNullOrWhiteSpace($subdir)) {
                    $subdir = ""
                }
    
                # Build source and destination paths
                if ([string]::IsNullOrEmpty($subdir)) {
                    $sourceFilePath = Join-Path -Path $infPath -ChildPath $sourceDiskFile
                    $destinationFolder = $targetPath
                }
                else {
                    $sourceFolder = Join-Path -Path $infPath -ChildPath $subdir
                    $sourceFilePath = Join-Path -Path $sourceFolder -ChildPath $sourceDiskFile
                    $destinationFolder = Join-Path -Path $targetPath -ChildPath $subdir
                    [void](New-Item -Path $destinationFolder -ItemType Directory -Force)
                }
    
                # Copy with logging and error handling
                if (Test-Path -Path $sourceFilePath) {
                    try {
                        Copy-Item -LiteralPath "$sourceFilePath" -Destination "$destinationFolder" -Force -ErrorAction Stop
                        $copiedFileCount++
                        WriteLog "Copied: $sourceFilePath -> $destinationFolder"
                    }
                    catch {
                        $errorCount++
                        WriteLog "ERROR: Failed to copy '$sourceFilePath' to '$destinationFolder' (INF: $infFullName): $($_.Exception.Message)"
                    }
                }
                else {
                    $errorCount++
                    WriteLog "ERROR: Source file not found for [$sectionName] entry '$sourceDiskFile': $sourceFilePath (INF: $infFullName)"
                }
            }
        }
    }
    
    # Final summary
    WriteLog "PE driver copy summary: INF total=$($infFiles.Count) matched=$matchedInfCount skipped=$skippedInfCount filesCopied=$copiedFileCount errors=$errorCount"
}

function New-PEMedia {
    param (
        [Parameter()]
        [bool]$Capture,
        [Parameter()]
        [bool]$Deploy
    )
    #Need to use the Demployment and Imaging tools environment to create winPE media
    $DandIEnv = "$adkPath`Assessment and Deployment Kit\Deployment Tools\DandISetEnv.bat"
    $WinPEFFUPath = "$FFUDevelopmentPath\WinPE"

    If (Test-path -Path "$WinPEFFUPath") {
        WriteLog "Removing old WinPE path at $WinPEFFUPath"
        Remove-Item -Path "$WinPEFFUPath" -Recurse -Force | out-null
    }

    WriteLog "Copying WinPE files to $WinPEFFUPath"
    # Use & cmd over invoke-process as Invoke-process has issues with the winpe media folder copying all contents
    if ($WindowsArch -eq 'x64') {
        & cmd /c """$DandIEnv"" && copype amd64 $WinPEFFUPath" | Out-Null
        # Invoke-Process cmd "/c ""$DandIEnv"" && copype amd64 $WinPEFFUPath" | Out-Null
    }
    elseif ($WindowsArch -eq 'arm64') {
        & cmd /c """$DandIEnv"" && copype arm64 $WinPEFFUPath" | Out-Null
        # Invoke-Process cmd "/c ""$DandIEnv"" && copype arm64 $WinPEFFUPath" | Out-Null
    }
    WriteLog 'Files copied successfully'

    WriteLog 'Mounting WinPE media to add WinPE optional components'
    Mount-WindowsImage -ImagePath "$WinPEFFUPath\media\sources\boot.wim" -Index 1 -Path "$WinPEFFUPath\mount" | Out-Null
    WriteLog 'Mounting complete'

    $Packages = @(
        "WinPE-WMI.cab",
        "en-us\WinPE-WMI_en-us.cab",
        "WinPE-NetFX.cab",
        "en-us\WinPE-NetFX_en-us.cab",
        "WinPE-Scripting.cab",
        "en-us\WinPE-Scripting_en-us.cab",
        "WinPE-PowerShell.cab",
        "en-us\WinPE-PowerShell_en-us.cab",
        "WinPE-StorageWMI.cab",
        "en-us\WinPE-StorageWMI_en-us.cab",
        "WinPE-DismCmdlets.cab",
        "en-us\WinPE-DismCmdlets_en-us.cab"
    )

    if ($WindowsArch -eq 'x64') {
        $PackagePathBase = "$adkPath`Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs\"
    }
    elseif ($WindowsArch -eq 'arm64') {
        $PackagePathBase = "$adkPath`Assessment and Deployment Kit\Windows Preinstallation Environment\arm64\WinPE_OCs\"
    }
    

    foreach ($Package in $Packages) {
        $PackagePath = Join-Path $PackagePathBase $Package
        WriteLog "Adding Package $Package"
        Add-WindowsPackage -Path "$WinPEFFUPath\mount" -PackagePath $PackagePath | Out-Null
        WriteLog "Adding package complete"
    }
    If ($Capture) {
        WriteLog "Copying $FFUDevelopmentPath\WinPECaptureFFUFiles\* to WinPE capture media"
        Copy-Item -Path "$FFUDevelopmentPath\WinPECaptureFFUFiles\*" -Destination "$WinPEFFUPath\mount" -Recurse -Force | out-null
        WriteLog "Copy complete"
        #Remove Bootfix.bin - for BIOS systems, shouldn't be needed, but doesn't hurt to remove for our purposes
        #Remove-Item -Path "$WinPEFFUPath\media\boot\bootfix.bin" -Force | Out-null
        # $WinPEISOName = 'WinPE_FFU_Capture.iso'
        $WinPEISOFile = $CaptureISO
        # $Capture = $false
    }
    If ($Deploy) {
        WriteLog "Copying $FFUDevelopmentPath\WinPEDeployFFUFiles\* to WinPE deploy media"
        Copy-Item -Path "$FFUDevelopmentPath\WinPEDeployFFUFiles\*" -Destination "$WinPEFFUPath\mount" -Recurse -Force | Out-Null
        WriteLog 'Copy complete'
        #If $CopyPEDrivers = $true, add drivers to WinPE media using dism
        if ($CopyPEDrivers) {
            if ($UseDriversAsPEDrivers) {
                WriteLog "UseDriversAsPEDrivers is set. Building WinPE driver set from Drivers folder (bypassing PEDrivers folder contents)."
                if (Test-Path -Path $PEDriversFolder) {
                    try {
                        Remove-Item -Path (Join-Path $PEDriversFolder '*') -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
                    }
                    catch {
                        WriteLog "Warning: Failed clearing existing PEDriversFolder contents: $($_.Exception.Message)"
                    }
                }
                else {
                    try {
                        New-Item -Path $PEDriversFolder -ItemType Directory -Force | Out-Null
                    }
                    catch {
                        WriteLog "Error: Failed to create PEDriversFolder at $PEDriversFolder - continuing may fail when adding drivers."
                    }
                }
                WriteLog "Copying required WinPE drivers from Drivers folder"
                Copy-Drivers -Path $DriversFolder -Output $PEDriversFolder
            }
            else {
                WriteLog "Copying PE drivers from PEDrivers folder"
            }
            
            WriteLog "Adding drivers to WinPE media"
            try {
                $WinPEMount = "$WinPEFFUPath\Mount"

                # Inject drivers using deep SUBST mapping (reuse one drive letter and loop each INF folder)
                Invoke-DismDriverInjectionWithSubstLoop -ImagePath $WinPEMount -DriverRoot $PEDriversFolder
            }
            catch {
                WriteLog 'Some drivers failed to be added. This can be expected. Continuing.'
            }
            WriteLog "Adding drivers complete"
        }
        # $WinPEISOName = 'WinPE_FFU_Deploy.iso'
        $WinPEISOFile = $DeployISO

        # $Deploy = $false
    }
    WriteLog 'Dismounting WinPE media' 
    Dismount-WindowsImage -Path "$WinPEFFUPath\mount" -Save | Out-Null
    WriteLog 'Dismount complete'
    #Make ISO
    if ($WindowsArch -eq 'x64') {
        $OSCDIMGPath = "$adkPath`Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg"
    }
    elseif ($WindowsArch -eq 'arm64') {
        $OSCDIMGPath = "$adkPath`Assessment and Deployment Kit\Deployment Tools\arm64\Oscdimg"
    }
    $OSCDIMG = "$OSCDIMGPath\oscdimg.exe"
    WriteLog "Creating WinPE ISO at $WinPEISOFile"
    # & "$OSCDIMG" -m -o -u2 -udfver102 -bootdata:2`#p0,e,b$OSCDIMGPath\etfsboot.com`#pEF,e,b$OSCDIMGPath\Efisys_noprompt.bin $WinPEFFUPath\media $FFUDevelopmentPath\$WinPEISOName | Out-null
    if ($WindowsArch -eq 'x64') {
        if ($Capture) {
            $OSCDIMGArgs = "-m -o -u2 -udfver102 -bootdata:2`#p0,e,b`"$OSCDIMGPath\etfsboot.com`"`#pEF,e,b`"$OSCDIMGPath\Efisys_noprompt.bin`" `"$WinPEFFUPath\media`" `"$WinPEISOFile`""
        }
        if ($Deploy) {
            $OSCDIMGArgs = "-m -o -u2 -udfver102 -bootdata:2`#p0,e,b`"$OSCDIMGPath\etfsboot.com`"`#pEF,e,b`"$OSCDIMGPath\Efisys.bin`" `"$WinPEFFUPath\media`" `"$WinPEISOFile`""
        }
    }
    elseif ($WindowsArch -eq 'arm64') {
        if ($Capture) {
            $OSCDIMGArgs = "-m -o -u2 -udfver102 -bootdata:1`#pEF,e,b`"$OSCDIMGPath\Efisys_noprompt.bin`" `"$WinPEFFUPath\media`" `"$WinPEISOFile`""
        }
        if ($Deploy) {
            $OSCDIMGArgs = "-m -o -u2 -udfver102 -bootdata:1`#pEF,e,b`"$OSCDIMGPath\Efisys.bin`" `"$WinPEFFUPath\media`" `"$WinPEISOFile`""
        }
        
    }
    Invoke-Process $OSCDIMG $OSCDIMGArgs | Out-Null
    WriteLog "ISO created successfully"
    WriteLog "Cleaning up $WinPEFFUPath"
    Remove-Item -Path "$WinPEFFUPath" -Recurse -Force
    WriteLog 'Cleanup complete'
    # Deferred cleanup of preserved driver model folders (only after WinPE Deploy media is created)
    if ($UseDriversAsPEDrivers -and $CompressDownloadedDriversToWim -and $Deploy -and $CopyPEDrivers) {
        WriteLog "Beginning deferred cleanup of preserved driver model folders (UseDriversAsPEDrivers + compression scenario)."
        $removedCount = 0
        $skippedCount = 0
        if (Test-Path -Path $DriversFolder) {
            Get-ChildItem -Path $DriversFolder -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $makeDir = $_.FullName
                Get-ChildItem -Path $makeDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                    $modelDir = $_.FullName
                    $markerFile = Join-Path -Path $modelDir -ChildPath '__PreservedForPEDrivers.txt'
                    $leaf = Split-Path -Path $modelDir -Leaf
                    $wimPath = Join-Path -Path $makeDir -ChildPath ($leaf + '.wim')
                    if ((Test-Path -Path $markerFile -PathType Leaf) -and (Test-Path -Path $wimPath -PathType Leaf)) {
                        try {
                            WriteLog "Removing preserved driver folder: $modelDir (WIM located at $wimPath)"
                            Remove-Item -Path $modelDir -Recurse -Force -ErrorAction Stop
                            $removedCount++
                        }
                        catch {
                            WriteLog "Warning: Failed to remove preserved folder $modelDir : $($_.Exception.Message)"
                            $skippedCount++
                        }
                    }
                    else {
                        $skippedCount++
                    }
                }
            }
            WriteLog "Deferred driver cleanup complete. Removed: $removedCount; Skipped: $skippedCount"
        }
        else {
            WriteLog "Drivers folder $DriversFolder not found during deferred cleanup."
        }
    }
}

function Optimize-FFUCaptureDrive {
    param (
        [string]$VhdxPath
    )
    try {
        WriteLog 'Mounting VHDX for volume optimization'
        $mountedDisk = Mount-VHD -Path $VhdxPath -Passthru | Get-Disk
        $osPartition = $mountedDisk | Get-Partition | Where-Object { $_.GptType -eq "{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}" }
        WriteLog 'Defragmenting Windows partition...'
        Optimize-Volume -DriveLetter $osPartition.DriveLetter -Defrag -NormalPriority
        WriteLog 'Performing slab consolidation on Windows partition...'
        Optimize-Volume -DriveLetter $osPartition.DriveLetter -SlabConsolidate -NormalPriority
        WriteLog 'Dismounting VHDX'
        Dismount-ScratchVhdx -VhdxPath $VhdxPath
        WriteLog 'Mounting VHDX as read-only for optimization'
        Mount-VHD -Path $VhdxPath -NoDriveLetter -ReadOnly
        WriteLog 'Optimizing VHDX in full mode...'
        Optimize-VHD -Path $VhdxPath -Mode Full
        WriteLog 'Dismounting VHDX'
        Dismount-ScratchVhdx -VhdxPath $VhdxPath
    }
    catch {
        throw $_
    }
}

function Get-ShortenedWindowsSKU {
    param (
        [string]$WindowsSKU
    )
    $shortenedWindowsSKU = switch ($WindowsSKU) {
        'Core' { 'Home' }
        'Home' { 'Home' }
        'CoreN' { 'Home_N' }
        'Home N' { 'Home_N' }
        'CoreSingleLanguage' { 'Home_SL' }
        'Home Single Language' { 'Home_SL' }
        'Education' { 'Edu' }
        'EducationN' { 'Edu_N' }
        'Education N' { 'Edu_N' }
        'Professional' { 'Pro' }
        'Pro' { 'Pro' }
        'ProfessionalN' { 'Pro_N' }
        'Pro N' { 'Pro_N' }
        'ProfessionalEducation' { 'Pro_Edu' }
        'Pro Education' { 'Pro_Edu' }
        'ProfessionalEducationN' { 'Pro_Edu_N' }
        'Pro Education N' { 'Pro_Edu_N' }
        'ProfessionalWorkstation' { 'Pro_WKS' }
        'Pro for Workstations' { 'Pro_WKS' }
        'ProfessionalWorkstationN' { 'Pro_WKS_N' }
        'Pro N for Workstations' { 'Pro_WKS_N' }
        'Enterprise' { 'Ent' }
        'EnterpriseN' { 'Ent_N' }
        'Enterprise N' { 'Ent_N' }
        'Enterprise N LTSC' { 'Ent_N_LTSC' }
        'EnterpriseS' { 'Ent_LTSC' }
        'EnterpriseSN' { 'Ent_N_LTSC' }
        'Enterprise LTSC' { 'Ent_LTSC' }
        'Enterprise 2016 LTSB' { 'Ent_LTSC' }
        'Enterprise N 2016 LTSB' { 'Ent_N_LTSC' }
        'IoT Enterprise LTSC' { 'IoT_Ent_LTSC' }
        'IoTEnterpriseS' { 'IoT_Ent_LTSC' }
        'IoT Enterprise N LTSC' { 'IoT_Ent_N_LTSC' }
        'ServerStandard' { 'Srv_Std' }
        'Standard' { 'Srv_Std' }
        'ServerDatacenter' { 'Srv_Dtc' }
        'Datacenter' { 'Srv_Dtc' }
        'Standard (Desktop Experience)' { 'Srv_Std_DE' }
        'Datacenter (Desktop Experience)' { 'Srv_Dtc_DE' }  
    }
    return $shortenedWindowsSKU

}
function New-FFUFileName {

    # $Winverinfo.name will be either Win10 or Win11 for client OSes
    # Since WindowsRelease now includes dates, it breaks default name template in the config file
    # This should keep in line with the naming that's done via VM Captures
    if ($installationType -eq 'Client' -and $winverinfo) {
        $WindowsRelease = $winverinfo.name
    }
        
    $BuildDate = Get-Date -uformat %b%Y
    # Replace '{WindowsRelease}' with the Windows release (e.g., 10, 11, 2016, 2019, 2022, 2025)
    $CustomFFUNameTemplate = $CustomFFUNameTemplate -replace '{WindowsRelease}', $WindowsRelease
    # Replace '{WindowsVersion}' with the Windows version (e.g., 1607, 1809, 21h2, 22h2, 23h2, 24h2, etc)
    $CustomFFUNameTemplate = $CustomFFUNameTemplate -replace '{WindowsVersion}', $WindowsVersion
    # Replace '{SKU}' with the SKU of the Windows image (e.g., Pro, Enterprise, etc.)
    $CustomFFUNameTemplate = $CustomFFUNameTemplate -replace '{SKU}', $shortenedWindowsSKU
    # Replace '{BuildDate}' with the current month and year (e.g., Jan2023)
    $CustomFFUNameTemplate = $CustomFFUNameTemplate -replace '{BuildDate}', $BuildDate
    # Replace '{yyyy}' with the current year in 4-digit format (e.g., 2023)
    $CustomFFUNameTemplate = $CustomFFUNameTemplate -replace '{yyyy}', (Get-Date -UFormat '%Y')
    # Replace '{MM}' with the current month in 2-digit format (e.g., 01 for January)
    $CustomFFUNameTemplate = $CustomFFUNameTemplate -creplace '{MM}', (Get-Date -UFormat '%m')
    # Replace '{dd}' with the current day of the month in 2-digit format (e.g., 05)
    $CustomFFUNameTemplate = $CustomFFUNameTemplate -replace '{dd}', (Get-Date -UFormat '%d')
    # Replace '{HH}' with the current hour in 24-hour format (e.g., 14 for 2 PM)
    $CustomFFUNameTemplate = $CustomFFUNameTemplate -creplace '{HH}', (Get-Date -UFormat '%H')
    # Replace '{hh}' with the current hour in 12-hour format (e.g., 02 for 2 PM)
    $CustomFFUNameTemplate = $CustomFFUNameTemplate -creplace '{hh}', (Get-Date -UFormat '%I')
    # Replace '{mm}' with the current minute in 2-digit format (e.g., 09)
    $CustomFFUNameTemplate = $CustomFFUNameTemplate -creplace '{mm}', (Get-Date -UFormat '%M')
    # Replace '{tt}' with the current AM/PM designator (e.g., AM or PM)
    $CustomFFUNameTemplate = $CustomFFUNameTemplate -replace '{tt}', (Get-Date -UFormat '%p')
    if ($CustomFFUNameTemplate -notlike '*.ffu') {
        $CustomFFUNameTemplate += '.ffu'
    }
    return $CustomFFUNameTemplate
}

function New-FFU {
    param (
        [Parameter(Mandatory = $false)]
        [string]$VMName
    )
    #If $InstallApps = $true, configure the VM
    If ($InstallApps) {
        WriteLog 'Creating FFU from VM'
        WriteLog "Setting $CaptureISO as first boot device"
        $VMDVDDrive = Get-VMDvdDrive -VMName $VMName
        Set-VMFirmware -VMName $VMName -FirstBootDevice $VMDVDDrive
        Set-VMDvdDrive -VMName $VMName -Path $CaptureISO
        $VMSwitch = Get-VMSwitch -name $VMSwitchName
        WriteLog "Setting $($VMSwitch.Name) as VMSwitch"
        get-vm $VMName | Get-VMNetworkAdapter | Connect-VMNetworkAdapter -SwitchName $VMSwitch.Name
        WriteLog "Configuring VM complete"

        #Start VM
        Set-Progress -Percentage 68 -Message "Capturing FFU from VM..."
        WriteLog "Starting VM"
        Start-VM -Name $VMName

        # Wait for the VM to turn off
        do {
            $FFUVM = Get-VM -Name $VMName
            Start-Sleep -Seconds 5
        } while ($FFUVM.State -ne 'Off')
        WriteLog "VM Shutdown"
        # Check for .ffu files in the FFUDevelopment folder
        WriteLog "Checking for FFU Files"
        $FFUFiles = Get-ChildItem -Path $FFUCaptureLocation -Filter "*.ffu" -File

        # If there's more than one .ffu file, get the most recent and store its path in $FFUFile
        if ($FFUFiles.Count -gt 0) {
            WriteLog 'Getting the most recent FFU file'
            $FFUFile = ($FFUFiles | Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1).FullName
            WriteLog "Most recent .ffu file: $FFUFile"
        }
        else {
            WriteLog "No .ffu files found in $FFUCaptureLocation"
            throw $_
        }
    }
    elseif (-not $InstallApps -and (-not $AllowVHDXCaching)) {
        #Get Windows Version Information from the VHDX
        $winverinfo = Get-WindowsVersionInfo
        WriteLog 'Creating FFU File Name'
        if ($CustomFFUNameTemplate) {
            $FFUFileName = New-FFUFileName
        }
        else {
            $FFUFileName = "$($winverinfo.Name)`_$($winverinfo.DisplayVersion)`_$($shortenedWindowsSKU)`_$($winverinfo.BuildDate).ffu"
        }
        WriteLog "FFU file name: $FFUFileName"
        $FFUFile = "$FFUCaptureLocation\$FFUFileName"
        #Capture the FFU
        Set-Progress -Percentage 68 -Message "Capturing FFU from VHDX..."
        WriteLog 'Capturing FFU'
        Invoke-Process cmd "/c ""$DandIEnv"" && dism /Capture-FFU /ImageFile:$FFUFile /CaptureDrive:\\.\PhysicalDrive$($vhdxDisk.DiskNumber) /Name:$($winverinfo.Name)$($winverinfo.DisplayVersion)$($shortenedWindowsSKU) /Compress:Default" | Out-Null
        WriteLog 'FFU Capture complete'
        Dismount-ScratchVhdx -VhdxPath $VHDXPath
    }
    elseif (-not $InstallApps -and $AllowVHDXCaching) {
        # Make $FFUFileName based on values in the config.json file
        WriteLog 'Creating FFU File Name'
        if ($CustomFFUNameTemplate) {
            $FFUFileName = New-FFUFileName
        }
        else {
            $BuildDate = Get-Date -UFormat %b%Y
            # Get Windows Information to make the FFU file name from the cachedVHDXInfo file
            if ($installationType -eq 'Client') {
                $FFUFileName = "Win$($cachedVHDXInfo.WindowsRelease)`_$($cachedVHDXInfo.WindowsVersion)`_$($shortenedWindowsSKU)`_$BuildDate.ffu"
            }
            else {
                $FFUFileName = "Server$($cachedVHDXInfo.WindowsRelease)`_$($cachedVHDXInfo.WindowsVersion)`_$($shortenedWindowsSKU)`_$BuildDate.ffu"
            } 
        }
        WriteLog "FFU file name: $FFUFileName"
        $FFUFile = "$FFUCaptureLocation\$FFUFileName"
        #Capture the FFU
        WriteLog 'Capturing FFU'
        Invoke-Process cmd "/c ""$DandIEnv"" && dism /Capture-FFU /ImageFile:$FFUFile /CaptureDrive:\\.\PhysicalDrive$($vhdxDisk.DiskNumber) /Name:$($cachedVHDXInfo.WindowsRelease)$($cachedVHDXInfo.WindowsVersion)$($shortenedWindowsSKU) /Compress:Default" | Out-Null     
        WriteLog 'FFU Capture complete'
        Dismount-ScratchVhdx -VhdxPath $VHDXPath
    }

    #Without this 120 second sleep, we sometimes see an error when mounting the FFU due to a file handle lock. Needed for both driver and optimize steps.
    
    If ($InstallDrivers -or $Optimize) {
        WriteLog 'Sleeping 2 minutes to prevent file handle lock'
        Start-Sleep 120
    }

    #Add drivers
    If ($InstallDrivers) {
        Set-Progress -Percentage 75 -Message "Injecting drivers into FFU..."
        WriteLog 'Adding drivers'
        WriteLog "Creating $FFUDevelopmentPath\Mount directory"
        New-Item -Path "$FFUDevelopmentPath\Mount" -ItemType Directory -Force | Out-Null
        WriteLog "Created $FFUDevelopmentPath\Mount directory"
        WriteLog "Mounting $FFUFile to $FFUDevelopmentPath\Mount"
        Mount-WindowsImage -ImagePath $FFUFile -Index 1 -Path "$FFUDevelopmentPath\Mount" | Out-null
        WriteLog 'Mounting complete'
        WriteLog 'Adding drivers - This will take a few minutes, please be patient'
        try {
            # Inject drivers using deep SUBST mapping (reuse one drive letter and loop each INF folder)
            Invoke-DismDriverInjectionWithSubstLoop -ImagePath "$FFUDevelopmentPath\Mount" -DriverRoot "$DriversFolder"
        }
        catch {
            WriteLog 'Some drivers failed to be added to the FFU. This can be expected. Continuing.'
        }
        WriteLog 'Adding drivers complete'
        WriteLog "Dismount $FFUDevelopmentPath\Mount"
        Dismount-WindowsImage -Path "$FFUDevelopmentPath\Mount" -Save | Out-Null
        WriteLog 'Dismount complete'
        WriteLog "Remove $FFUDevelopmentPath\Mount folder"
        Remove-Item -Path "$FFUDevelopmentPath\Mount" -Recurse -Force | Out-null
        WriteLog 'Folder removed'
    }
    #Optimize FFU
    if ($Optimize -eq $true) {
        Set-Progress -Percentage 85 -Message "Optimizing FFU..."
        WriteLog 'Optimizing FFU - This will take a few minutes, please be patient'
        #Need to use ADK version of DISM to address bug in DISM - perhaps Windows 11 24H2 will fix this
        Invoke-Process cmd "/c ""$DandIEnv"" && dism /optimize-ffu /imagefile:$FFUFile" | Out-Null
        #Invoke-Process cmd "/c dism /optimize-ffu /imagefile:$FFUFile" | Out-Null
        WriteLog 'Optimizing FFU complete'
        Set-Progress -Percentage 90 -Message "FFU post-processing complete."
    }
    

}
function Remove-FFUVM {
    param (
        [Parameter(Mandatory = $false)]
        [string]$VMName
    )
    #Get the VM object and remove the VM, the HGSGuardian, and the certs
    If ($VMName) {
        $FFUVM = get-vm $VMName | Where-Object { $_.state -ne 'running' }
    }   
    If ($null -ne $FFUVM) {
        WriteLog 'Cleaning up VM'
        $certPath = 'Cert:\LocalMachine\Shielded VM Local Certificates\'
        $VMName = $FFUVM.Name
        WriteLog "Removing VM: $VMName"
        Remove-VM -Name $VMName -Force
        WriteLog 'Removal complete'
        WriteLog "Removing $VMPath"
        Remove-Item -Path $VMPath -Force -Recurse
        WriteLog 'Removal complete'
        WriteLog "Removing HGSGuardian for $VMName" 
        Remove-HgsGuardian -Name $VMName -WarningAction SilentlyContinue
        WriteLog 'Removal complete'
        WriteLog 'Cleaning up HGS Guardian certs'
        $certs = Get-ChildItem -Path $certPath -Recurse | Where-Object { $_.Subject -like "*$VMName*" }
        foreach ($cert in $Certs) {
            Remove-item -Path $cert.PSPath -force | Out-Null
        }
        WriteLog 'Cert removal complete'
    }
    #If just building the FFU from vhdx, remove the vhdx path
    If (-not $InstallApps -and $vhdxDisk) {
        WriteLog 'Cleaning up VHDX'
        WriteLog "Removing $VMPath"
        Remove-Item -Path $VMPath -Force -Recurse | Out-Null
        WriteLog 'Removal complete'
    }

    #Remove orphaned mounted images
    $mountedImages = Get-WindowsImage -Mounted
    if ($mountedImages) {
        foreach ($image in $mountedImages) {
            $mountPath = $image.Path
            WriteLog "Dismounting image at $mountPath"
            Dismount-WindowsImage -Path $mountPath -discard
            WriteLog "Successfully dismounted image at $mountPath"
        }
    } 
    #Remove Mount folder if it exists
    If (Test-Path -Path $FFUDevelopmentPath\Mount) {
        WriteLog "Remove $FFUDevelopmentPath\Mount folder"
        Remove-Item -Path "$FFUDevelopmentPath\Mount" -Recurse -Force
        WriteLog 'Folder removed'
    }
    #Remove unused mountpoints
    WriteLog 'Remove unused mountpoints'
    Invoke-Process cmd "/c mountvol /r" | Out-Null
    WriteLog 'Removal complete'
}
Function Remove-FFUUserShare {
    WriteLog "Removing $ShareName"
    Remove-SmbShare -Name $ShareName -Force | Out-null
    WriteLog 'Removal complete'
    WriteLog "Removing $Username"
    Remove-LocalUser -Name $Username | Out-Null
    WriteLog 'Removal complete'
}

Function Get-WindowsVersionInfo {
    #This sleep prevents CBS/CSI corruption which causes issues with Windows update after deployment. Capturing from very fast disks (NVME) can cause the capture to happen faster than Windows is ready for. This seems to affect VHDX-only captures, not VM captures. 
    WriteLog 'Sleep 60 seconds before opening registry to grab Windows version info '
    Start-sleep 60
    WriteLog "Getting Windows Version info"
    #Load Registry Hive
    $Software = "$osPartitionDriveLetter`:\Windows\System32\config\software"
    WriteLog "Loading Software registry hive: $Software"
    Invoke-Process reg "load HKLM\FFU $Software" | Out-Null

    #Find Windows version values
    # $WindowsSKU = Get-ItemPropertyValue -Path 'HKLM:\FFU\Microsoft\Windows NT\CurrentVersion\' -Name 'EditionID'
    # WriteLog "Windows SKU: $WindowsSKU"
    [int]$CurrentBuild = Get-ItemPropertyValue -Path 'HKLM:\FFU\Microsoft\Windows NT\CurrentVersion\' -Name 'CurrentBuild'
    WriteLog "Windows Build: $CurrentBuild"
    #DisplayVersion does not exist for 1607 builds (RS1 and Server 2016) and Server 2019
    if ($CurrentBuild -notin (14393, 17763)) {
        $DisplayVersion = Get-ItemPropertyValue -Path 'HKLM:\FFU\Microsoft\Windows NT\CurrentVersion\' -Name 'DisplayVersion'
        WriteLog "Windows Version: $DisplayVersion"
    }
    # For Windows 10 LTSC 2019, set DisplayVersion to 2019
    if ($CurrentBuild -eq 17763 -and $InstallationType -eq "Client") {
        $DisplayVersion = '2019'
    }
    
    $BuildDate = Get-Date -uformat %b%Y

    if ($shortenedWindowsSKU -notmatch "Srv") {
        if ($CurrentBuild -ge 22000) {
            $Name = 'Win11'
        }
        else {
            $Name = 'Win10'
        }
    } 
    else {
        $Name = switch ($CurrentBuild) {
            26100 { '2025' }
            20348 { '2022' }
            17763 { '2019' }
            14393 { '2016' }
            Default { $DisplayVersion }
        }
    }
    
    WriteLog "Unloading registry"
    Invoke-Process reg "unload HKLM\FFU" | Out-Null
    #This prevents Critical Process Died errors you can have during deployment of the FFU. Capturing from very fast disks (NVME) can cause the capture to happen faster than Windows is ready for.
    WriteLog 'Sleep 60 seconds to allow registry to completely unload'
    Start-sleep 60

    return @{

        DisplayVersion = $DisplayVersion
        BuildDate      = $buildDate
        Name           = $Name
        # SKU            = $WindowsSKU
    }
}
Function Get-USBDrive {
    # Log the start of the USB drive check
    WriteLog 'Checking for USB drives'
    
    # Check if external hard disk media is allowed and user has not specified USB drives
    If ($AllowExternalHardDiskMedia -and (-not($USBDriveList))) {
        # Get all removable and external hard disk media drives
        [array]$USBDrives = (Get-CimInstance -ClassName Win32_DiskDrive -Filter "MediaType='Removable Media' OR MediaType='External hard disk media'")
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
        # Get only the specified USB drives based on model and UniqueId
        $USBDrives = @()
        foreach ($model in $USBDriveList.Keys) {
            $configUniqueId = $USBDriveList[$model]
            WriteLog "Looking for USB drive model $model with UniqueId $configUniqueId"
            # First get candidate drives by model and media type
            $candidateDrives = Get-CimInstance -ClassName Win32_DiskDrive -Filter "Model LIKE '%$model%' AND (MediaType='Removable Media' OR MediaType='External hard disk media')"
            $foundDrive = $null
            foreach ($candidate in $candidateDrives) {
                # Get the disk to retrieve UniqueId
                $disk = Get-Disk -Number $candidate.Index -ErrorAction SilentlyContinue
                if ($disk -and $disk.UniqueId) {
                    # Trim the machine name suffix (everything after the colon) from UniqueId
                    $diskUniqueId = if ($disk.UniqueId -match ':') {
                        $disk.UniqueId.Split(':')[0]
                    }
                    else {
                        $disk.UniqueId
                    }
                    # Match on the trimmed UniqueId
                    if ($diskUniqueId -eq $configUniqueId) {
                        $foundDrive = $candidate
                        break
                    }
                }
            }
            if ($foundDrive) {
                WriteLog "Found USB drive model $($foundDrive.Model) with UniqueId $configUniqueId"
                $USBDrives += $foundDrive
            }
            else {
                WriteLog "USB drive model $model with UniqueId $configUniqueId not found"
            }
        }
        $USBDrivesCount = $USBDrives.Count
        WriteLog "Found $USBDrivesCount of $USBDriveListCount USB drives from USB Drive List"
    }
    else {
        # Get only removable media drives
        [array]$USBDrives = (Get-CimInstance -ClassName Win32_DiskDrive -Filter "MediaType='Removable Media'")
        $USBDrivesCount = $USBDrives.Count
        WriteLog "Found $USBDrivesCount Removable USB drives"
    }
    
    # Check if any USB drives were found
    if ($USBDrives.Count -eq 0) {
        WriteLog "No USB drive found. Exiting"
        Write-Error "No USB drive found. Exiting"
        exit 1
    }
    
    # Return the found USB drives and their count
    return $USBDrives, $USBDrivesCount
}
Function New-DeploymentUSB {
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

        # Partitioning
        $Disk = Get-Disk -Number $DiskNumber
        if ($Disk.PartitionStyle -ne "RAW") {
            $Disk | Clear-Disk -RemoveData -RemoveOEM -Confirm:$false
            $Disk = Get-Disk -Number $DiskNumber
        }
        if ($Disk.PartitionStyle -eq "RAW") {
            $Disk | Initialize-Disk -PartitionStyle MBR -Confirm:$false
        }
        else {
            $Disk | Get-Partition | Remove-Partition -Confirm:$false
            $Disk | Set-Disk -PartitionStyle MBR
        }
        
        $BootPartition = $Disk | New-Partition -Size 2GB -IsActive -AssignDriveLetter
        $DeployPartition = $Disk | New-Partition -UseMaximumSize -AssignDriveLetter
        Format-Volume -Partition $BootPartition -FileSystem FAT32 -NewFileSystemLabel "TempBoot" -Confirm:$false 
        Format-Volume -Partition $DeployPartition -FileSystem NTFS -NewFileSystemLabel "TempDeploy" -Confirm:$false
        
        $BootPartitionDriveLetter = "$($BootPartition.DriveLetter):\"
        $DeployPartitionDriveLetter = "$($DeployPartition.DriveLetter):\"
        WriteLog "Disk $DiskNumber partitioned. Boot: $BootPartitionDriveLetter, Deploy: $DeployPartitionDriveLetter"

        # Copy WinPE files
        WriteLog "Copying WinPE files from $($using:ISOMountPoint) to $BootPartitionDriveLetter"
        robocopy $using:ISOMountPoint $BootPartitionDriveLetter /E /COPYALL /R:5 /W:5 /J /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null

        # Copy other files
        if ($using:CopyFFU.IsPresent -and $null -ne $using:SelectedFFUFile) {
            if ($using:SelectedFFUFile -is [array]) {
                WriteLog "Copying multiple FFU files to $DeployPartitionDriveLetter"
                foreach ($FFUFile in $using:SelectedFFUFile) {
                    robocopy (Split-Path $FFUFile -Parent) $DeployPartitionDriveLetter (Split-Path $FFUFile -Leaf) /J /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
                }
            }
            else {
                WriteLog "Copying $($using:SelectedFFUFile) to $DeployPartitionDriveLetter"
                robocopy (Split-Path $using:SelectedFFUFile -Parent) $DeployPartitionDriveLetter (Split-Path $using:SelectedFFUFile -Leaf) /J /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
            }
        }

        if ($using:CopyDrivers) {
            $DriversPathOnUSB = Join-Path $DeployPartitionDriveLetter "Drivers"
            WriteLog "Copying drivers to $DriversPathOnUSB"
            robocopy $using:DriversFolder $DriversPathOnUSB /E /COPYALL /R:5 /W:5 /J /XF .gitkeep /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
        }

        if ($using:CopyPPKG) {
            $PPKGPathOnUSB = Join-Path $DeployPartitionDriveLetter "PPKG"
            WriteLog "Copying PPKGs to $PPKGPathOnUSB"
            robocopy $using:PPKGFolder $PPKGPathOnUSB /E /COPYALL /R:5 /W:5 /J /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
        }

        if ($using:CopyUnattend) {
            $UnattendPathOnUSB = Join-Path $DeployPartitionDriveLetter "Unattend"
            WriteLog "Copying unattend file to $UnattendPathOnUSB"
            New-Item -Path $UnattendPathOnUSB -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
            if ($using:WindowsArch -eq 'x64') {
                Copy-Item -Path (Join-Path $using:UnattendFolder 'unattend_x64.xml') -Destination (Join-Path $UnattendPathOnUSB 'Unattend.xml') -Force | Out-Null
            }
            elseif ($using:WindowsArch -eq 'arm64') {
                Copy-Item -Path (Join-Path $using:UnattendFolder 'unattend_arm64.xml') -Destination (Join-Path $UnattendPathOnUSB 'Unattend.xml') -Force | Out-Null
            }
            if (Test-Path (Join-Path $using:UnattendFolder 'prefixes.txt')) {
                WriteLog "Copying prefixes.txt file to $UnattendPathOnUSB"
                Copy-Item -Path (Join-Path $using:UnattendFolder 'prefixes.txt') -Destination (Join-Path $UnattendPathOnUSB 'prefixes.txt') -Force | Out-Null
            }
            WriteLog 'Copy completed'
        }

        if ($using:CopyAutopilot) {
            $AutopilotPathOnUSB = Join-Path $DeployPartitionDriveLetter "Autopilot"
            WriteLog "Copying Autopilot files to $AutopilotPathOnUSB"
            robocopy $using:AutopilotFolder $AutopilotPathOnUSB /E /COPYALL /R:5 /W:5 /J /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
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


function Get-FFUEnvironment {
    WriteLog 'Dirty.txt file detected. Last run did not complete succesfully. Will clean environment'
    try {
        Remove-InProgressItems -FFUDevelopmentPath $FFUDevelopmentPath
    }
    catch {
        WriteLog "Remove-InProgressItems failed: $($_.Exception.Message)"
    }
    if ($CleanupCurrentRunDownloads) {
        try {
            Cleanup-CurrentRunDownloads -FFUDevelopmentPath $FFUDevelopmentPath
        }
        catch {
            WriteLog "Cleanup-CurrentRunDownloads failed: $($_.Exception.Message)"
        }
        try {
            Restore-RunJsonBackups -FFUDevelopmentPath $FFUDevelopmentPath
        }
        catch {
            WriteLog "Restore-RunJsonBackups failed: $($_.Exception.Message)"
        }
    }
    # Check for running VMs that start with '_FFU-' and are in the 'Off' state
    $vms = Get-VM

    # Loop through each VM
    foreach ($vm in $vms) {
        if ($vm.Name.StartsWith("_FFU-")) {
            if ($vm.State -eq 'Running') {
                Stop-VM -Name $vm.Name -TurnOff -Force
            }
            # If conditions are met, delete the VM
            Remove-FFUVM -VMName $vm.Name
        }
    }
    # Check for MSFT Virtual disks where location contains FFUDevelopment in the path
    $disks = Get-Disk -FriendlyName *virtual*
    foreach ($disk in $disks) {
        $diskNumber = $disk.Number
        $vhdLocation = $disk.Location
        if ($vhdLocation -like "*FFUDevelopment*") {
            WriteLog "Dismounting Virtual Disk $diskNumber with Location $vhdLocation"
            Dismount-ScratchVhdx -VhdxPath $vhdLocation
            $parentFolder = Split-Path -Parent $vhdLocation
            WriteLog "Removing folder $parentFolder"
            Remove-Item -Path $parentFolder -Recurse -Force
        }
    }

    # Check for mounted DiskImages
    $volumes = Get-Volume | Where-Object { $_.DriveType -eq 'CD-ROM' }
    foreach ($volume in $volumes) {
        $letter = $volume.DriveLetter
        WriteLog "Dismounting DiskImage for volume $letter"
        Get-Volume $letter | Get-DiskImage | Dismount-DiskImage | Out-Null
        WriteLog "Dismounting complete"
    }

    # Remove unused mountpoints
    WriteLog 'Remove unused mountpoints'
    Invoke-Process cmd "/c mountvol /r" | Out-Null
    WriteLog 'Removal complete'

    # Check for content in the VM folder and delete any folders that start with _FFU-
    if ([string]::IsNullOrWhiteSpace($VMLocation)) {
        $VMLocation = Join-Path $FFUDevelopmentPath 'VM'
        WriteLog "VMLocation not set; defaulting to $VMLocation"
    }
    if (Test-Path -Path $VMLocation) {
        $folders = Get-ChildItem -Path $VMLocation -Directory
        foreach ($folder in $folders) {
            if ($folder.Name -like '_FFU-*') {
                WriteLog "Removing folder $($folder.FullName)"
                Remove-Item -Path $folder.FullName -Recurse -Force
            }
        }
    }
    else {
        WriteLog "VMLocation path $VMLocation not found; skipping VM folder cleanup"
    }

    # Remove orphaned mounted images
    $mountedImages = Get-WindowsImage -Mounted
    if ($mountedImages) {
        foreach ($image in $mountedImages) {
            $mountPath = $image.Path
            WriteLog "Dismounting image at $mountPath"
            try {
                Dismount-WindowsImage -Path $mountPath -discard | Out-null
                WriteLog "Successfully dismounted image at $mountPath"
            }
            catch {
                WriteLog "Failed to dismount image at $mountPath with error: $_"
            }
        }
    }

    # Remove Mount folder if it exists
    if (Test-Path -Path "$FFUDevelopmentPath\Mount") {
        WriteLog "Remove $FFUDevelopmentPath\Mount folder"
        Remove-Item -Path "$FFUDevelopmentPath\Mount" -Recurse -Force
        WriteLog 'Folder removed'
    }

    #Clear any corrupt Windows mount points
    WriteLog 'Clearing any corrupt Windows mount points'
    Clear-WindowsCorruptMountPoint | Out-null
    WriteLog 'Complete'

    #Clean up registry
    if (Test-Path -Path 'HKLM:\FFU') {
        Writelog 'Found HKLM:\FFU, removing it' 
        Invoke-Process reg "unload HKLM\FFU" | Out-Null
    }

    #Remove FFU User and Share
    $UserExists = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
    if ($UserExists) {
        WriteLog "Removing FFU User and Share"
        Remove-FFUUserShare
        WriteLog 'Removal complete'
    }

    #Run shared cleanup to avoid duplicated logic
    Invoke-FFUPostBuildCleanup -RootPath $FFUDevelopmentPath -AppsPath $AppsPath -DriversPath $DriversFolder -FFUCapturePath $FFUCaptureLocation -CaptureISOPath $CaptureISO -DeployISOPath $DeployISO -AppsISOPath $AppsISO -RemoveCaptureISO:$CleanupCaptureISO -RemoveDeployISO:$CleanupDeployISO -RemoveAppsISO:$CleanupAppsISO -RemoveDrivers:$CleanupDrivers -RemoveFFU:$RemoveFFU -RemoveApps:$RemoveApps -RemoveUpdates:$RemoveUpdates -KBPath:$KBPath

    # Remove existing Apps.iso
    if (Test-Path -Path $AppsISO) {
        WriteLog "Removing $AppsISO"
        Remove-Item -Path $AppsISO -Force -ErrorAction SilentlyContinue
        WriteLog 'Removal complete'
    }
    # Remove per-run session folder if present (Cancel/-Cleanup scenario)
    $sessionDir = Join-Path $FFUDevelopmentPath '.session'
    if (Test-Path -Path $sessionDir) {
        WriteLog 'Removing .session folder'
        Remove-Item -Path $sessionDir -Recurse -Force -ErrorAction SilentlyContinue
        WriteLog 'Removal complete'
    }
    WriteLog 'Removing dirty.txt file'
    Remove-Item -Path "$FFUDevelopmentPath\dirty.txt" -Force
    WriteLog "Cleanup complete"
}
Function Remove-DisabledArtifacts {
    # Remove Office artifacts if Install Office is disabled
    if (-not $InstallOffice) {
        $removed = $false
        if (Test-Path -Path $installOfficePath) {
            WriteLog "Install Office disabled - removing $installOfficePath"
            Remove-Item -Path $installOfficePath -Force -ErrorAction SilentlyContinue
            $removed = $true
        }
        if (Test-Path -Path $OfficePath) {
            WriteLog 'Removing Office and ODT download'
            $OfficeDownloadPath = "$OfficePath\Office"
            Remove-Item -Path $OfficeDownloadPath -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path "$OfficePath\setup.exe" -Recurse -Force -ErrorAction SilentlyContinue
            $removed = $true
        }
        if ($removed) { WriteLog 'Removal complete' }
    }


    # Remove Defender artifacts if Defender update is disabled
    if (-not $UpdateLatestDefender) {
        $removed = $false
        if (Test-Path -Path $installDefenderPath) {
            WriteLog "Update Defender disabled - removing $installDefenderPath"
            Remove-Item -Path $installDefenderPath -Force -ErrorAction SilentlyContinue
            $removed = $true
        }
        if (Test-Path -Path $DefenderPath) {
            WriteLog "Update Defender disabled - removing $DefenderPath"
            Remove-Item -Path $DefenderPath -Recurse -Force -ErrorAction SilentlyContinue
            $removed = $true
        }
        if ($removed) { WriteLog 'Removal complete' }
    }

    # Remove MSRT artifacts if MSRT update is disabled
    if (-not $UpdateLatestMSRT) {
        $removed = $false
        if (Test-Path -Path $installMSRTPath) {
            WriteLog "Update MSRT disabled - removing $installMSRTPath"
            Remove-Item -Path $installMSRTPath -Force -ErrorAction SilentlyContinue
            $removed = $true
        }
        if (Test-Path -Path $MSRTPath) {
            WriteLog "Update MSRT disabled - removing $MSRTPath"
            Remove-Item -Path $MSRTPath -Recurse -Force -ErrorAction SilentlyContinue
            $removed = $true
        }
        if ($removed) { WriteLog 'Removal complete' }
    }

    # Remove OneDrive artifacts if OneDrive update is disabled
    if (-not $UpdateOneDrive) {
        $removed = $false
        if (Test-Path -Path $installODPath) {
            WriteLog "Update OneDrive disabled - removing $installODPath"
            Remove-Item -Path $installODPath -Force -ErrorAction SilentlyContinue
            $removed = $true
        }
        if (Test-Path -Path $OneDrivePath) {
            WriteLog "Update OneDrive disabled - removing $OneDrivePath"
            Remove-Item -Path $OneDrivePath -Recurse -Force -ErrorAction SilentlyContinue
            $removed = $true
        }
        if ($removed) { WriteLog 'Removal complete' }
    }

    # Remove Edge artifacts if Edge update is disabled
    if (-not $UpdateEdge) {
        $removed = $false
        if (Test-Path -Path $installEdgePath) {
            WriteLog "Update Edge disabled - removing $installEdgePath"
            Remove-Item -Path $installEdgePath -Force -ErrorAction SilentlyContinue
            $removed = $true
        }
        if (Test-Path -Path $EdgePath) {
            WriteLog "Update Edge disabled - removing $EdgePath"
            Remove-Item -Path $EdgePath -Recurse -Force -ErrorAction SilentlyContinue
            $removed = $true
        }
        if ($removed) { WriteLog 'Removal complete' }
    }
}

function Export-ConfigFile {
    [CmdletBinding()]
    param (
        [Parameter()]
        $paramNames
    )
    $filteredParamNames = Get-Parameters -ParamNames $paramNames
    
    # Retrieve their values
    $paramsToExport = @{}
    foreach ($paramName in $filteredParamNames) {
        $paramsToExport[$paramName] = Get-Variable -Name $paramName -ValueOnly
    }
    
    # Sort the keys alphabetically
    $orderedParams = [ordered]@{}
    foreach ($key in ($paramsToExport.Keys | Sort-Object)) {
        $orderedParams[$key] = $paramsToExport[$key]
    }
    
    # Convert to JSON and save
    $orderedParams | ConvertTo-Json -Depth 10 | Set-Content -Path $ExportConfigFile -Encoding UTF8
}
function Get-PEArchitecture {
    param(
        [string]$FilePath
    )
    
    # Read the entire file as bytes.1
    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    
    # Check for the 'MZ' signature.
    if ($bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) {
        throw "The file is not a valid PE file."
    }
    
    # The PE header offset is stored at offset 0x3C.
    $peHeaderOffset = [System.BitConverter]::ToInt32($bytes, 0x3C)
    
    # Verify the PE signature "PE\0\0".
    if ($bytes[$peHeaderOffset] -ne 0x50 -or $bytes[$peHeaderOffset + 1] -ne 0x45) {
        throw "Invalid PE header."
    }
    
    # The Machine field is located immediately after the PE signature.
    $machine = [System.BitConverter]::ToUInt16($bytes, $peHeaderOffset + 4)
    
    switch ($machine) {
        0x014c { return "x86" }
        0x8664 { return "x64" }
        0xAA64 { return "ARM64" }
        default { return ("Unknown architecture: 0x{0:X}" -f $machine) }
    }
}

function New-RunSession {
    param(
        [string]$FFUDevelopmentPath,
        [string]$DriversFolder,
        [string]$OrchestrationPath
    )
    try {
        $sessionDir = Join-Path $FFUDevelopmentPath '.session'
        $backupDir = Join-Path $sessionDir 'backups'
        $inprogDir = Join-Path $sessionDir 'inprogress'
        if (-not (Test-Path $sessionDir)) { New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null }
        if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
        if (-not (Test-Path $inprogDir)) { New-Item -ItemType Directory -Path $inprogDir -Force | Out-Null }

        $manifest = [ordered]@{
            RunStartUtc      = (Get-Date).ToUniversalTime().ToString('o')
            JsonBackups      = @()
            OfficeXmlBackups = @()
        }

        if ($DriversFolder) {
            $driverMapPath = Join-Path $DriversFolder 'DriverMapping.json'
            if (Test-Path $driverMapPath) {
                $backup = Join-Path $backupDir 'DriverMapping.json'
                Copy-Item -Path $driverMapPath -Destination $backup -Force
                $manifest.JsonBackups += @{ Path = $driverMapPath; Backup = $backup }
                WriteLog "Backed up DriverMapping.json to $backup"
            }
        }
        if ($OrchestrationPath) {
            $wgPath = Join-Path $OrchestrationPath 'WinGetWin32Apps.json'
            if (Test-Path $wgPath) {
                $backup2 = Join-Path $backupDir 'WinGetWin32Apps.json'
                Copy-Item -Path $wgPath -Destination $backup2 -Force
                $manifest.JsonBackups += @{ Path = $wgPath; Backup = $backup2 }
                WriteLog "Backed up WinGetWin32Apps.json to $backup2"
            }
        }
        # Backup Office XMLs (DeployFFU.xml, DownloadFFU.xml) if present so we can restore them after cleanup
        if ($OfficePath) {
            foreach ($n in @('DeployFFU.xml', 'DownloadFFU.xml')) {
                $src = Join-Path $OfficePath $n
                if (Test-Path $src) {
                    $dst = Join-Path $backupDir $n
                    try {
                        Copy-Item -Path $src -Destination $dst -Force
                        $manifest.OfficeXmlBackups += @{ Path = $src; Backup = $dst }
                        WriteLog "Backed up $n to $dst"
                    }
                    catch { WriteLog "Failed backing up $($n): $($_.Exception.Message)" }
                }
            }
        }

        $manifestPath = Join-Path $sessionDir 'currentRun.json'
        $manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestPath -Encoding UTF8
        WriteLog "Run session initialized at $sessionDir"
    }
    catch {
        WriteLog "New-RunSession failed: $($_.Exception.Message)"
    }
}
function Get-CurrentRunManifest {
    param([string]$FFUDevelopmentPath)
    $manifestPath = Join-Path $FFUDevelopmentPath '.session\currentRun.json'
    if (Test-Path $manifestPath) { return (Get-Content $manifestPath -Raw | ConvertFrom-Json) }
    return $null
}
function Save-RunManifest {
    param([string]$FFUDevelopmentPath, [object]$Manifest)
    if ($null -eq $Manifest) { return }
    $manifestPath = Join-Path $FFUDevelopmentPath '.session\currentRun.json'
    $Manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestPath -Encoding UTF8
}
function Mark-DownloadInProgress {
    param([string]$FFUDevelopmentPath, [string]$TargetPath)
    if ([string]::IsNullOrWhiteSpace($FFUDevelopmentPath) -or [string]::IsNullOrWhiteSpace($TargetPath)) { return }
    $sessionInprog = Join-Path (Join-Path $FFUDevelopmentPath '.session') 'inprogress'
    if (-not (Test-Path $sessionInprog)) { New-Item -ItemType Directory -Path $sessionInprog -Force | Out-Null }
    $marker = Join-Path $sessionInprog ("{0}.marker" -f ([guid]::NewGuid()))
    $payload = @{ TargetPath = $TargetPath; CreatedUtc = (Get-Date).ToUniversalTime().ToString('o') }
    $payload | ConvertTo-Json -Depth 3 | Set-Content -Path $marker -Encoding UTF8
    WriteLog "Marked in-progress: $TargetPath"
}
function Clear-DownloadInProgress {
    param([string]$FFUDevelopmentPath, [string]$TargetPath)
    $sessionInprog = Join-Path (Join-Path $FFUDevelopmentPath '.session') 'inprogress'
    if (-not (Test-Path $sessionInprog)) { return }
    Get-ChildItem -Path $sessionInprog -Filter *.marker -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $data = Get-Content $_.FullName -Raw | ConvertFrom-Json
            if ($data.TargetPath -eq $TargetPath) { Remove-Item -Path $_.FullName -Force }
        }
        catch {}
    }
    WriteLog "Cleared in-progress: $TargetPath"
}
function Remove-InProgressItems {
    param([string]$FFUDevelopmentPath)
    $sessionInprog = Join-Path (Join-Path $FFUDevelopmentPath '.session') 'inprogress'
    if (-not (Test-Path $sessionInprog)) { return }

    function Remove-PathWithRetry {
        param(
            [string]$path,
            [bool]$isDirectory
        )
        for ($i = 0; $i -lt 3; $i++) {
            try {
                if ($isDirectory) {
                    Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
                }
                else {
                    # clear readonly if set
                    try { (Get-Item -LiteralPath $path -ErrorAction SilentlyContinue).Attributes = 'Normal' } catch {}
                    Remove-Item -Path $path -Force -ErrorAction Stop
                }
                return $true
            }
            catch {
                Start-Sleep -Milliseconds 350
            }
        }
        return -not (Test-Path -LiteralPath $path)
    }

    Get-ChildItem -Path $sessionInprog -Filter *.marker -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $data = Get-Content $_.FullName -Raw | ConvertFrom-Json
            $target = $data.TargetPath
            try {
                if ($DriversFolder -and $target) {
                    $fullTarget = [System.IO.Path]::GetFullPath($target).TrimEnd('\')
                    $driversRoot = [System.IO.Path]::GetFullPath($DriversFolder).TrimEnd('\')
                    if ($fullTarget.StartsWith($driversRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $remainder = $fullTarget.Substring($driversRoot.Length).TrimStart('\')
                        $parts = $remainder -split '\\'
                        if ($parts.Length -ge 1) {
                            $knownMakes = @('Dell', 'HP', 'Lenovo', 'Microsoft')
                            if ($parts.Length -ge 2 -and $knownMakes -contains $parts[0]) {
                                # Drivers\<Make>\<Model>\...
                                $modelFolder = Join-Path (Join-Path $driversRoot $parts[0]) $parts[1]
                            }
                            else {
                                # Drivers\<Model>\... (when DriversFolder already includes Make)
                                $modelFolder = Join-Path $driversRoot $parts[0]
                            }
                            if ($modelFolder) {
                                WriteLog "Promoting in-progress driver target to model folder: $modelFolder (from $target)"
                                $target = $modelFolder
                            }
                        }
                    }
                }
            }
            catch {}

            if (Test-Path $target) {
                # Special-case Office: preserve DeployFFU.xml and DownloadFFU.xml; remove everything else with retries.
                $targetFull = [System.IO.Path]::GetFullPath($target).TrimEnd('\')
                $officeFull = $null
                if ($OfficePath) { $officeFull = [System.IO.Path]::GetFullPath($OfficePath).TrimEnd('\') }

                if ($officeFull -and ($targetFull -ieq $officeFull) -and (Test-Path $OfficePath -PathType Container)) {
                    $preserve = @('DeployFFU.xml', 'DownloadFFU.xml')
                    WriteLog "Cleaning in-progress Office folder: preserving $($preserve -join ', ') and removing other content."
                    Get-ChildItem -Path $OfficePath -Force | ForEach-Object {
                        if ($preserve -notcontains $_.Name) {
                            $itemPath = $_.FullName
                            $isDir = $_.PSIsContainer
                            WriteLog "Removing Office item: $itemPath"
                            $removed = $false
                            try { $removed = Remove-PathWithRetry -path $itemPath -isDirectory:$isDir } catch {}
                            if (-not $removed) {
                                # If setup.exe (or ODT stub) is locked, try to stop the exact owning process by path and retry.
                                try {
                                    $basename = [System.IO.Path]::GetFileName($itemPath)
                                    if (-not $isDir -and $basename -in @('setup.exe', 'odtsetup.exe')) {
                                        Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $itemPath } | Stop-Process -Force -ErrorAction SilentlyContinue
                                        Start-Sleep -Milliseconds 500
                                        $removed = Remove-PathWithRetry -path $itemPath -isDirectory:$false
                                    }
                                }
                                catch {
                                    WriteLog "Process stop attempt for $itemPath failed: $($_.Exception.Message)"
                                }
                            }
                            if (-not $removed) {
                                WriteLog "Failed removing Office item $itemPath after retries."
                            }
                        }
                    }
                }
                else {
                    WriteLog "Removing in-progress target: $target"
                    $isDir = Test-Path $target -PathType Container
                    [void](Remove-PathWithRetry -path $target -isDirectory:$isDir)
                }
            }

            Remove-Item -Path $_.FullName -Force
        }
        catch {
            WriteLog "Failed Remove-InProgressItems marker '$($_.FullName)': $($_.Exception.Message)"
        }
    }
    # Also clean up any driver content created this run (model folders and temp folders),
    # even when broader current-run cleanup is not requested.
    try {
        if ($DriversFolder -and (Test-Path $DriversFolder)) {
            $manifest = Get-CurrentRunManifest -FFUDevelopmentPath $FFUDevelopmentPath
            if ($manifest -and $manifest.RunStartUtc) {
                $runStart = [datetime]::Parse($manifest.RunStartUtc)

                # Remove OEM temp folders like _TEMP_* (safe to always remove)
                Get-ChildItem -Path $DriversFolder -Directory -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like '_TEMP_*' } |
                ForEach-Object {
                    WriteLog "Removing driver temp folder: $($_.FullName)"
                    Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                }

                # Remove model folders created/modified this run; never remove top-level make roots
                Get-ChildItem -Path $DriversFolder -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                    $makeRoot = $_.FullName
                    # Model-level folders are immediate children under a make root (e.g. Drivers\Lenovo\<Model>)
                    Get-ChildItem -Path $makeRoot -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.CreationTimeUtc -ge $runStart -or $_.LastWriteTimeUtc -ge $runStart } |
                    ForEach-Object {
                        WriteLog "Removing driver model folder from current run: $($_.FullName)"
                        Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }

                # Remove make root folders created this run (if empty)
                Get-ChildItem -Path $DriversFolder -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.CreationTimeUtc -ge $runStart -and $_.LastWriteTimeUtc -ge $runStart } |
                ForEach-Object {
                    $any = Get-ChildItem -Path $_.FullName -Force -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($null -eq $any) {
                        WriteLog "Removing empty make root folder created this run: $($_.FullName)"
                        Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                    }
                    else {
                        WriteLog "Skipping non-empty make root folder: $($_.FullName)"
                    }
                }
            }
        }
    }
    catch {
        WriteLog "Driver in-progress cleanup step failed: $($_.Exception.Message)"
    }
}
function Cleanup-CurrentRunDownloads {
    param([string]$FFUDevelopmentPath)
    $manifest = Get-CurrentRunManifest -FFUDevelopmentPath $FFUDevelopmentPath
    if ($null -eq $manifest) { WriteLog "No current run manifest; skipping current-run cleanup."; return }
    $runStart = [datetime]::Parse($manifest.RunStartUtc)

    # 1) Generic current-run scrub across known roots (includes Orchestration now)
    $roots = @()
    if ($AppsPath) { $roots += (Join-Path $AppsPath 'Win32'); $roots += (Join-Path $AppsPath 'MSStore') }
    if ($DefenderPath) { $roots += $DefenderPath }
    if ($MSRTPath) { $roots += $MSRTPath }
    if ($OneDrivePath) { $roots += $OneDrivePath }
    if ($EdgePath) { $roots += $EdgePath }
    if ($KBPath) { $roots += $KBPath }
    if ($DriversFolder) { $roots += $DriversFolder }
    if ($orchestrationPath) { $roots += $orchestrationPath }

    foreach ($root in $roots | Where-Object { $_ -and (Test-Path $_) }) {
        $isDriversRoot = $false
        try {
            if ($DriversFolder) {
                $isDriversRoot = ([System.IO.Path]::GetFullPath($root).TrimEnd('\') -ieq [System.IO.Path]::GetFullPath($DriversFolder).TrimEnd('\'))
            }
        }
        catch {}

        if ($isDriversRoot) {
            WriteLog "Scanning Drivers folder (creation-time filter) in $root"

            # Remove driver folders created this run (skip non-empty make roots)
            Get-ChildItem -Path $root -Directory -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.CreationTimeUtc -ge $runStart } |
            Sort-Object FullName -Descending | ForEach-Object {
                try {
                    $parent = Split-Path -Path $_.FullName -Parent
                    $parentIsDriversRoot = ([System.IO.Path]::GetFullPath($parent).TrimEnd('\') -ieq [System.IO.Path]::GetFullPath($root).TrimEnd('\'))
                    if ($parentIsDriversRoot) {
                        # Only remove top-level make folders if created this run AND empty (avoid deleting existing Lenovo/HP/Dell/Microsoft trees)
                        $any = Get-ChildItem -Path $_.FullName -Force -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($null -eq $any) {
                            WriteLog "Removing empty make folder created this run: $($_.FullName)"
                            Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                        }
                    }
                    else {
                        WriteLog "Removing current-run driver folder: $($_.FullName)"
                        Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }
                catch { WriteLog "Failed removing driver folder $($_.FullName): $($_.Exception.Message)" }
            }

            # Remove driver files created this run
            Get-ChildItem -Path $root -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.CreationTimeUtc -ge $runStart } |
            ForEach-Object {
                try {
                    WriteLog "Removing current-run driver file: $($_.FullName)"
                    Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
                }
                catch { WriteLog "Failed removing driver file $($_.FullName): $($_.Exception.Message)" }
            }

            # Prune empty driver folders (skip existing make roots)
            Get-ChildItem -Path $root -Directory -Recurse -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending | ForEach-Object {
                try {
                    $any = Get-ChildItem -Path $_.FullName -Force -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($null -eq $any) {
                        $parent = Split-Path -Path $_.FullName -Parent
                        $parentIsDriversRoot = ([System.IO.Path]::GetFullPath($parent).TrimEnd('\') -ieq [System.IO.Path]::GetFullPath($root).TrimEnd('\'))
                        if ($parentIsDriversRoot) {
                            # Only remove empty make roots if they were created this run
                            if ($_.CreationTimeUtc -ge $runStart) {
                                WriteLog "Removing empty make folder created this run: $($_.FullName)"
                                Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                            }
                        }
                        else {
                            WriteLog "Removing empty driver subfolder: $($_.FullName)"
                            Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                        }
                    }
                }
                catch { WriteLog "Failed pruning empty driver folder $($_.FullName): $($_.Exception.Message)" }
            }
        }
        else {
            WriteLog "Scanning for current-run items in $root"
            # Remove folders created/modified this run (legacy behavior for non-Drivers roots)
            Get-ChildItem -Path $root -Directory -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTimeUtc -ge $runStart } |
            Sort-Object FullName -Descending | ForEach-Object {
                try {
                    WriteLog "Removing current-run folder: $($_.FullName)"
                    Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                }
                catch { WriteLog "Failed removing folder $($_.FullName): $($_.Exception.Message)" }
            }
            # Remove files created/modified this run (preserve Office XMLs)
            Get-ChildItem -Path $root -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTimeUtc -ge $runStart -and $_.Name -notin @('DeployFFU.xml', 'DownloadFFU.xml') } |
            ForEach-Object {
                try {
                    WriteLog "Removing current-run file: $($_.FullName)"
                    Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
                }
                catch { WriteLog "Failed removing file $($_.FullName): $($_.Exception.Message)" }
            }
        }
    }

    # 2) Office folder policy: keep XML configs, remove everything else
    if ($OfficePath -and (Test-Path $OfficePath)) {
        $preserve = @('DeployFFU.xml', 'DownloadFFU.xml')
        WriteLog "Cleaning Office folder: preserving $($preserve -join ', ') and removing other content."
        Get-ChildItem -Path $OfficePath -Force | ForEach-Object {
            if ($preserve -notcontains $_.Name) {
                try {
                    WriteLog "Removing Office item: $($_.FullName)"
                    if ($_.PSIsContainer) {
                        Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                    }
                    else {
                        Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
                    }
                }
                catch { WriteLog "Failed removing Office item $($_.FullName): $($_.Exception.Message)" }
            }
        }
    }

    # 3) Remove generated update artifacts under Orchestration (Update-*.ps1) created this run
    if ($orchestrationPath -and (Test-Path $orchestrationPath)) {
        try {
            Get-ChildItem -Path $orchestrationPath -Filter 'Update-*.ps1' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTimeUtc -ge $runStart } | ForEach-Object {
                WriteLog "Removing current-run artifact: $($_.FullName)"
                Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
            }
        }
        catch { WriteLog "Failed removing Update-*.ps1 artifacts: $($_.Exception.Message)" }
        # Also remove Install-Office.ps1 if created this run
        $installOffice = Join-Path $orchestrationPath 'Install-Office.ps1'
        if (Test-Path $installOffice) {
            $fi = Get-Item $installOffice
            if ($fi.LastWriteTimeUtc -ge $runStart) {
                WriteLog "Removing current-run artifact: $installOffice"
                Remove-Item -Path $installOffice -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # 4) If Defender/OneDrive/Edge/MSRT folders exist, remove them entirely (they're session downloads)
    foreach ($p in @($DefenderPath, $OneDrivePath, $EdgePath, $MSRTPath)) {
        if ($p -and (Test-Path $p)) {
            try {
                WriteLog "Removing current-run folder (entire): $p"
                Remove-Item -Path $p -Recurse -Force -ErrorAction SilentlyContinue
            }
            catch { WriteLog "Failed removing folder $($p): $($_.Exception.Message)" }
        }
    }

    # 5) Remove any ESDs downloaded this run
    Get-ChildItem -Path $PSScriptRoot -Filter *.esd -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTimeUtc -ge $runStart } | ForEach-Object {
        try {
            WriteLog "Removing current-run ESD: $($_.FullName)"
            Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
        }
        catch { WriteLog "Failed removing ESD $($_.FullName): $($_.Exception.Message)" }
    }

    # 6) Remove empty top-level subfolders under Apps (cosmetic)
    if ($AppsPath -and (Test-Path $AppsPath)) {
        Get-ChildItem -Path $AppsPath -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $any = Get-ChildItem -Path $_.FullName -Force -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($null -eq $any) {
                    WriteLog "Removing empty folder: $($_.FullName)"
                    Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            catch { WriteLog "Failed removing empty folder $($_.FullName): $($_.Exception.Message)" }
        }
    }
}
function Restore-RunJsonBackups {
    param([string]$FFUDevelopmentPath)
    $manifest = Get-CurrentRunManifest -FFUDevelopmentPath $FFUDevelopmentPath
    if ($null -eq $manifest) { return }
    $runStart = [datetime]::Parse($manifest.RunStartUtc)

    foreach ($entry in $manifest.JsonBackups) {
        $path = $entry.Path
        $backup = $entry.Backup
        try {
            if (Test-Path $backup) {
                WriteLog "Restoring JSON from backup: $path"
                Copy-Item -Path $backup -Destination $path -Force
            }
        }
        catch { WriteLog "Failed restoring backup for $($path): $($_.Exception.Message)" }
    }

    $candidateJsons = @()
    if ($DriversFolder) { $candidateJsons += (Join-Path $DriversFolder 'DriverMapping.json') }
    if ($orchestrationPath) { $candidateJsons += (Join-Path $orchestrationPath 'WinGetWin32Apps.json') }

    foreach ($jp in $candidateJsons) {
        if (Test-Path $jp) {
            $hasBackup = $manifest.JsonBackups | Where-Object { $_.Path -eq $jp }
            if ($null -eq $hasBackup) {
                $fi = Get-Item $jp
                if ($fi.LastWriteTimeUtc -ge $runStart) {
                    WriteLog "Removing current-run JSON: $jp"
                    Remove-Item -Path $jp -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
}

# Restore Office XML backups if present; ensure Office folder exists and only XMLs remain
if ($manifest.OfficeXmlBackups -and $OfficePath) {
    if (-not (Test-Path $OfficePath)) {
        try { New-Item -ItemType Directory -Path $OfficePath -Force | Out-Null } catch {}
    }
    foreach ($ox in $manifest.OfficeXmlBackups) {
        try {
            WriteLog "Restoring Office XML from backup: $($ox.Path)"
            Copy-Item -Path $ox.Backup -Destination $ox.Path -Force
        }
        catch { WriteLog "Failed restoring Office XML $($ox.Path): $($_.Exception.Message)" }
    }
    # Ensure only DeployFFU.xml and DownloadFFU.xml remain
    $preserve = @('DeployFFU.xml', 'DownloadFFU.xml')
    Get-ChildItem -Path $OfficePath -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if ($preserve -notcontains $_.Name) {
            try {
                if ($_.PSIsContainer) { Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
                else { Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue }
            }
            catch { WriteLog "Failed removing extra Office item $($_.FullName): $($_.Exception.Message)" }
        }
    }
}

###END FUNCTIONS


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
    Get-FFUEnvironment
    return
}

WriteLog 'Begin Logging'
New-RunSession -FFUDevelopmentPath $FFUDevelopmentPath -DriversFolder $DriversFolder -OrchestrationPath $orchestrationPath
Set-Progress -Percentage 1 -Message "FFU build process started..."

####### Generate Config File #######

if ($ExportConfigFile) {
    WriteLog 'Exporting Config File'
    # Get the parameter names from the script and exclude ExportConfigFile
    $paramNames = $MyInvocation.MyCommand.Parameters.Keys | Where-Object { $_ -ne 'ExportConfigFile' }
    try {
        Export-ConfigFile($paramNames)
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
        if (!(Test-Path -Path $DriversFolder)) {
            WriteLog "-InstallDrivers or -CopyDrivers is set to `$true, but the $DriversFolder folder is missing"
            throw "-InstallDrivers or -CopyDrivers is set to `$true, but the $DriversFolder folder is missing"
        }
        if ((Get-ChildItem -Path $DriversFolder -Recurse | Measure-Object -Property Length -Sum).Sum -lt 1MB) {
            WriteLog "-InstallDrivers or -CopyDrivers is set to `$true, but the $DriversFolder folder is empty, and no drivers are specified for download."
            throw "-InstallDrivers or -CopyDrivers is set to `$true, but the $DriversFolder folder is empty, and no drivers are specified for download."
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
LogVariableValues

#Check if environment is dirty
If (Test-Path -Path "$FFUDevelopmentPath\dirty.txt") {
    Get-FFUEnvironment
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
                if ($null -eq $modelEntry -or -not $modelEntry.PSObject.Properties['Name']) {
                    WriteLog "Skipping model entry for Make '$makeName' due to missing Name."
                    continue
                }

                $modelName = $modelEntry.Name
                if ([string]::IsNullOrWhiteSpace($modelName)) {
                    WriteLog "Skipping model entry for Make '$makeName' because Name is empty."
                    continue
                }
                $modelName = $modelName.Trim()

                $driverItem = $null
                switch ($makeName) {
                    'Microsoft' {
                        $driverItem = [PSCustomObject]@{
                            Make  = $makeName
                            Model = $modelName
                            Link  = if ($modelEntry.PSObject.Properties['Link']) { $modelEntry.Link } else { $null }
                        }
                    }
                    'HP' {
                        $systemId = if ($modelEntry.PSObject.Properties['SystemId'] -and -not [string]::IsNullOrWhiteSpace($modelEntry.SystemId)) { $modelEntry.SystemId.Trim() } else { $null }
                        $baseName = if ($modelEntry.PSObject.Properties['ProductName'] -and -not [string]::IsNullOrWhiteSpace($modelEntry.ProductName)) { $modelEntry.ProductName } else { $modelName }
                        if ($modelName -match '(.+?)\s*\((.+?)\)$') {
                            if ([string]::IsNullOrWhiteSpace($baseName)) { $baseName = $matches[1].Trim() }
                            if ([string]::IsNullOrWhiteSpace($systemId)) { $systemId = $matches[2].Trim() }
                        }
                        if ($baseName -match '(.+?)\s*\((.+?)\)$') {
                            $baseName = $matches[1].Trim()
                            if ([string]::IsNullOrWhiteSpace($systemId)) { $systemId = $matches[2].Trim() }
                        }
                        if ([string]::IsNullOrWhiteSpace($baseName)) { $baseName = $modelName }
                        $displayModel = if ([string]::IsNullOrWhiteSpace($systemId)) { $baseName.Trim() } else { "$($baseName.Trim()) ($($systemId.Trim()))" }
                        $driverItem = [PSCustomObject]@{
                            Make  = $makeName
                            Model = $displayModel
                        }
                        if (-not [string]::IsNullOrWhiteSpace($baseName)) {
                            $driverItem | Add-Member -NotePropertyName ProductName -NotePropertyValue $baseName.Trim()
                        }
                        if (-not [string]::IsNullOrWhiteSpace($systemId)) {
                            $driverItem | Add-Member -NotePropertyName SystemId -NotePropertyValue $systemId
                        }
                    }
                    'Lenovo' {
                        $machineType = if ($modelEntry.PSObject.Properties['MachineType']) { $modelEntry.MachineType } else { $null }
                        $productName = $modelName
                        if ([string]::IsNullOrWhiteSpace($machineType) -and $modelName -match '(.+?)\s*\((.+?)\)$') {
                            $productName = $matches[1].Trim()
                            $machineType = $matches[2].Trim()
                        }
                        if ([string]::IsNullOrWhiteSpace($machineType)) {
                            WriteLog "Skipping Lenovo model '$modelName' because MachineType is missing."
                            continue
                        }
                        $displayModel = "$productName ($machineType)"
                        $driverItem = [PSCustomObject]@{
                            Make        = $makeName
                            Model       = $displayModel
                            ProductName = $productName
                            MachineType = $machineType
                        }
                    }
                    'Dell' {
                        $systemId = if ($modelEntry.PSObject.Properties['SystemId']) { $modelEntry.SystemId } else { $null }
                        $baseName = $modelName
                        if ([string]::IsNullOrWhiteSpace($systemId) -and $modelName -match '(.+?)\s*\((.+?)\)$') {
                            $baseName = $matches[1].Trim()
                            $systemId = $matches[2].Trim()
                        }
                        $displayModel = if ([string]::IsNullOrWhiteSpace($systemId)) { $baseName } else { "$baseName ($systemId)" }
                        $driverItem = [PSCustomObject]@{
                            Make     = $makeName
                            Model    = $displayModel
                            SystemId = $systemId
                            CabUrl   = if ($modelEntry.PSObject.Properties['CabUrl']) { $modelEntry.CabUrl } else { $null }
                        }
                    }
                    default {
                        WriteLog "Skipping unsupported Make '$makeName' in Drivers.json."
                    }
                }

                if ($null -ne $driverItem) {
                    $driversToProcess += $driverItem
                }
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
        # Use the configured Threads value to control driver download concurrency
        $parallelResults = Invoke-ParallelProcessing -ItemsToProcess $driversToProcess `
            -TaskType 'DownloadDriverByMake' `
            -TaskArguments $taskArguments `
            -IdentifierProperty 'Model' `
            -WindowObject $null `
            -ListViewControl $null `
            -MainThreadLogPath $LogFile `
            -ThrottleLimit $Threads

        # After processing, update the driver mapping file and detect failures
        $successfullyDownloaded = [System.Collections.Generic.List[PSCustomObject]]::new()
        $failedDownloads = [System.Collections.Generic.List[PSCustomObject]]::new()

        if ($null -ne $parallelResults) {
            # Create a lookup table from the original items to retain full metadata for mapping.
            $driverLookup = @{}
            foreach ($driver in $driversToProcess) {
                if (-not [string]::IsNullOrWhiteSpace($driver.Model)) {
                    $driverLookup[$driver.Model] = $driver
                }
            }

            foreach ($result in $parallelResults) {
                if ($null -eq $result) { continue }

                $lookupModelName = $null
                $resultStatus = $null
                $resultDriverPath = $null
                $resultSuccess = $false

                if ($result -is [hashtable]) {
                    $lookupModelName = $result['Identifier']
                    $resultStatus = $result['Status']
                    if ($result.ContainsKey('DriverPath')) { $resultDriverPath = $result['DriverPath'] }
                    if ($result.ContainsKey('Success')) {
                        $resultSuccess = [bool]$result['Success']
                    }
                    elseif ($result.ContainsKey('ResultCode')) {
                        $resultSuccess = ($result['ResultCode'] -eq 0)
                    }
                }
                elseif ($result -is [pscustomobject]) {
                    if ($result.PSObject.Properties.Name -contains 'Identifier' -and -not [string]::IsNullOrWhiteSpace($result.Identifier)) {
                        $lookupModelName = $result.Identifier
                    }
                    elseif ($result.PSObject.Properties.Name -contains 'Model' -and -not [string]::IsNullOrWhiteSpace($result.Model)) {
                        $lookupModelName = $result.Model
                    }

                    if ($result.PSObject.Properties.Name -contains 'Status') { $resultStatus = $result.Status }
                    if ($result.PSObject.Properties.Name -contains 'DriverPath') { $resultDriverPath = $result.DriverPath }
                    if ($result.PSObject.Properties.Name -contains 'Success') {
                        $resultSuccess = [bool]$result.Success
                    }
                    elseif ($result.PSObject.Properties.Name -contains 'ResultCode') {
                        $resultSuccess = ($result.ResultCode -eq 0)
                    }
                }

                if ($resultSuccess -and -not [string]::IsNullOrWhiteSpace($resultDriverPath)) {
                    $modelKey = if (-not [string]::IsNullOrWhiteSpace($lookupModelName)) { $lookupModelName } else { 'Unknown model' }
                    $driverMetadata = $null
                    if (-not [string]::IsNullOrWhiteSpace($lookupModelName) -and $driverLookup.ContainsKey($lookupModelName)) {
                        $driverMetadata = $driverLookup[$lookupModelName]
                    }

                    if ($driverMetadata) {
                        $driverRecord = [PSCustomObject]@{
                            Make       = $driverMetadata.Make
                            Model      = $modelKey
                            DriverPath = $resultDriverPath
                        }
                        if ($driverMetadata.PSObject.Properties['SystemId'] -and -not [string]::IsNullOrWhiteSpace($driverMetadata.SystemId)) {
                            $driverRecord | Add-Member -NotePropertyName SystemId -NotePropertyValue $driverMetadata.SystemId
                        }
                        if ($driverMetadata.PSObject.Properties['MachineType'] -and -not [string]::IsNullOrWhiteSpace($driverMetadata.MachineType)) {
                            $driverRecord | Add-Member -NotePropertyName MachineType -NotePropertyValue $driverMetadata.MachineType
                        }
                        if ($driverMetadata.PSObject.Properties['ProductName'] -and -not [string]::IsNullOrWhiteSpace($driverMetadata.ProductName)) {
                            $driverRecord | Add-Member -NotePropertyName ProductName -NotePropertyValue $driverMetadata.ProductName
                        }
                        $successfullyDownloaded.Add($driverRecord)
                    }
                    else {
                        WriteLog "Warning: Could not find driver metadata for successful download of model '$modelKey'. Skipping from DriverMapping.json."
                    }
                }
                else {
                    $failureModel = if (-not [string]::IsNullOrWhiteSpace($lookupModelName)) { $lookupModelName } else { 'Unknown model' }
                    $failureStatus = if (-not [string]::IsNullOrWhiteSpace($resultStatus)) { $resultStatus } else { 'Driver download failed without a status message. Check the log for details.' }
                    $failedDownloads.Add([PSCustomObject]@{
                            Model  = $failureModel
                            Status = $failureStatus
                        })
                    WriteLog "Driver download failed for '$failureModel'. Status: $failureStatus"
                }
            }
        }
        else {
            WriteLog "Invoke-ParallelProcessing returned null or no results."
        }

        if ($failedDownloads.Count -gt 0) {
            $firstFailure = $failedDownloads[0]
            $errorMessage = "Driver download failed for model '$($firstFailure.Model)': $($firstFailure.Status)"
            WriteLog $errorMessage
            throw $errorMessage
        }

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
    }
}
# Existing single-model driver download logic
elseif (($Make -and $Model) -and ($InstallDrivers -or $CopyDrivers)) {
    try {
        if ($Make -eq 'HP') {
            WriteLog 'Getting HP drivers'
            Get-HPDrivers -Make $Make -Model $Model -WindowsArch $WindowsArch -WindowsRelease $WindowsRelease -WindowsVersion $WindowsVersion
            WriteLog 'Getting HP drivers completed successfully'
        }
        if ($make -eq 'Microsoft') {
            WriteLog 'Getting Microsoft drivers'
            Get-MicrosoftDrivers -Make $Make -Model $Model -WindowsArch $WindowsArch -WindowsRelease $WindowsRelease
            WriteLog 'Getting Microsoft drivers completed successfully'
        }
        if ($make -eq 'Lenovo') {
            WriteLog 'Getting Lenovo drivers'
            Get-LenovoDrivers -Model $Model -WindowsArch $WindowsArch -WindowsRelease $WindowsRelease
            WriteLog 'Getting Lenovo drivers completed successfully'
        }
        if ($make -eq 'Dell') {
            WriteLog 'Getting Dell drivers'
            #Dell mixes Win10 and 11 drivers, hence no WindowsRelease parameter
            Get-DellDrivers -Model $Model -WindowsArch $WindowsArch -WindowsRelease $WindowsRelease
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
    $adkPath = Get-ADK
    #Need to use the Deployment and Imaging tools environment to use dism from the Sept 2023 ADK to optimize FFU 
    $DandIEnv = Join-Path $adkPath "Assessment and Deployment Kit\Deployment Tools\DandISetEnv.bat"

}
catch {
    WriteLog 'ADK not found'
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
                    Get-Apps -AppList $AppListPath -AppsPath $AppsPath -WindowsArch $WindowsArch -OrchestrationPath $OrchestrationPath -LogFilePath $LogFile -ThrottleLimit $Threads
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
                        Get-Apps -AppList $modifiedAppListPath -AppsPath $AppsPath -WindowsArch $WindowsArch -OrchestrationPath $OrchestrationPath -LogFilePath $LogFile -ThrottleLimit $Threads
                        
                        # Cleanup modified app list
                        Remove-Item -Path $modifiedAppListPath -Force
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
                        Get-Office
                        WriteLog 'Downloading M365 Apps/Office completed successfully'
                    }

                }
                else {
                    WriteLog 'Downloading M365 Apps/Office'
                    Get-Office
                    WriteLog 'Downloading M365 Apps/Office completed successfully'
                }
                
            }

            #Update Latest Defender Platform and Definitions - these can't be serviced into the VHDX, will be saved to AppsPath
            if ($UpdateLatestDefender) {
                # Check if Defender has already been downloaded, if so, skip download
                WriteLog "`$UpdateLatestDefender is set to true, checking for latest Defender Platform and Security updates"
                if (Test-Path -Path $DefenderPath) {
                    # Check the size of the $DefenderPath folder
                    $DefenderSize = (Get-ChildItem -Path $DefenderPath -Recurse | Measure-Object -Property Length -Sum).Sum
                    if ($DefenderSize -gt 1MB) {
                        WriteLog "Found Defender download in $DefenderPath, skipping download"
                        $DefenderDownloaded = $true
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

                    # Add 30 second delay to allow for Windows Security Platform to install
                    # I suspect this is related to AppxSVC not being immediately ready when booting to audit mode
                    # Long-term solution would be the check for AppxSVC being started, but for now the 30 second sleep seems to work consistently
                    $installDefenderCommand = "Start-Sleep -Seconds 30`r`n"

                    # Download each update
                    foreach ($update in $defenderUpdates) {
                        WriteLog "Searching for $($update.Name) from Microsoft Update Catalog and saving to $DefenderPath"
                        $KBFilePath = Save-KB -Name $update.Name -Path $DefenderPath
                        WriteLog "Latest $($update.Description) saved to $DefenderPath\$KBFilePath"
                        # Add the KB file path to the installDefenderCommand
                        $installDefenderCommand += "& d:\Defender\$KBFilePath`r`n"
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
                        $installDefenderCommand += "& d:\Defender\mpam-fe.exe"
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
                    # Check the size of the $MSRTPath folder
                    $MSRTSize = (Get-ChildItem -Path $MSRTPath -Recurse | Measure-Object -Property Length -Sum).Sum
                    if ($MSRTSize -gt 1MB) {
                        WriteLog "Found MSRT download in $MSRTPath, skipping download"
                        $MSRTDownloaded = $true
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
                    $MSRTFileName = Save-KB -Name $Name -Path $MSRTPath
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
                    # Check the size of the $OneDrivePath folder
                    $OneDriveSize = (Get-ChildItem -Path $OneDrivePath -Recurse | Measure-Object -Property Length -Sum).Sum
                    if ($OneDriveSize -gt 1MB) {
                        WriteLog "Found OneDrive download in $OneDrivePath, skipping download"
                        $OneDriveDownloaded = $true
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
                    # Check the size of the $EdgePath folder
                    $EdgeSize = (Get-ChildItem -Path $EdgePath -Recurse | Measure-Object -Property Length -Sum).Sum
                    if ($EdgeSize -gt 1MB) {
                        WriteLog "Found Edge download in $EdgePath, skipping download"
                        $EdgeDownloaded = $true
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
                    $KBFilePath = Save-KB -Name $Name -Path $EdgePath
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
                    Remove-Item -Path $EdgeCABFilePath -Force
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
            Set-Progress -Percentage 10 -Message "Creating Apps ISO..."
            WriteLog "Creating $AppsISO file"
            New-AppsISO
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
    $cachedIncludedUpdateNames = [System.Collections.Generic.List[string]]::new()

    $esdMetadata = $null
    $esdVersion = $null
    $cuKbWindowsVersion = $null
    $cupKbWindowsVersion = $null

    if ($WindowsRelease -eq 11 -and -not $ISOPath) {
        try {
            $esdMetadata = Get-WindowsESDMetadata -WindowsRelease $WindowsRelease -WindowsArch $WindowsArch -WindowsLang $WindowsLang -MediaType $mediaType
            if ($esdMetadata -and $esdMetadata.Version) {
                $esdVersion = $esdMetadata.Version
                WriteLog "ESD version identified as $esdVersion"
            }
            elseif ($esdMetadata) {
                WriteLog "ESD metadata resolved but no version could be parsed from filename."
            }
        }
        catch {
            WriteLog "Failed to resolve Windows ESD metadata: $($_.Exception.Message)"
        }
    }

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
                (Get-UpdateFileInfo -Name $SSUName) | ForEach-Object { $ssuUpdateInfos.Add($_) }
            }
            WriteLog "Searching for $Name from Microsoft Update Catalog"
            (Get-UpdateFileInfo -Name $Name) | ForEach-Object { $cuUpdateInfos.Add($_) }
            $cuKbArticleId = $global:LastKBArticleID
            $cuKbWindowsVersion = $global:LastKBWindowsVersion
        }

        if ($UpdatePreviewCU -and $installationType -eq 'Client' -and $WindowsSKU -notlike "*LTSC") {
            Writelog "`$UpdatePreviewCU is set to true, checking for latest Preview CU"
            $Name = """Cumulative update Preview for Windows $WindowsRelease Version $WindowsVersion for $WindowsArch"""
            WriteLog "Searching for $Name from Microsoft Update Catalog"
            (Get-UpdateFileInfo -Name $Name) | ForEach-Object { $cupUpdateInfos.Add($_) }
            $cupKbArticleId = $global:LastKBArticleID
            $cupKbWindowsVersion = $global:LastKBWindowsVersion
        }

        if ($UpdateLatestNet) {
            Writelog "`$UpdateLatestNet is set to true, checking for latest .NET Framework"
            if ($WindowsRelease -in 2016, 2019, 2021 -and $isLTSC) {
                if ($ssuUpdateInfos.Count -eq 0) {
                    $SSUName = """Servicing Stack Update for Windows 10 Version $WindowsVersion for $WindowsArch"""
                    WriteLog "Searching for $SSUName from Microsoft Update Catalog"
                    (Get-UpdateFileInfo -Name $SSUName) | ForEach-Object { $ssuUpdateInfos.Add($_) }
                }
                if ($WindowsRelease -in 2016) { $name = """Cumulative Update for .NET Framework 4.8 for Windows 10 version $WindowsVersion for $WindowsArch""" }
                if ($WindowsRelease -eq 2019) { $name = """Cumulative Update for .NET Framework 3.5, 4.7.2 and 4.8 for Windows 10 Version $WindowsVersion for $WindowsArch""" }
                if ($WindowsRelease -eq 2021) { $name = """Cumulative Update for .NET Framework 3.5, 4.8 and 4.8.1 for Windows 10 Version $WindowsVersion for $WindowsArch""" }
                WriteLog "Searching for $name from Microsoft Update Catalog"
                (Get-UpdateFileInfo -Name $name) | ForEach-Object { $netUpdateInfos.Add($_) }
                $netKbArticleId = $global:LastKBArticleID

                if ($WindowsRelease -eq 2021) { $NETFeatureName = """Microsoft .NET Framework 4.8.1 for Windows 10 Version 21H2 for x64""" }
                if ($WindowsRelease -in 2016, 2019) { $NETFeatureName = """Microsoft .NET Framework 4.8 for Windows 10 Version $WindowsVersion and Windows Server $WindowsRelease for x64""" }
                WriteLog "Checking for latest .NET Framework feature pack: $NETFeatureName"
                (Get-UpdateFileInfo -Name $NETFeatureName) | ForEach-Object { $netFeatureUpdateInfos.Add($_) }
            }
            else {
                if ($WindowsRelease -eq 2024 -and $isLTSC) { $Name = "Cumulative update for .NET framework windows 11 $WindowsVersion $WindowsArch -preview" }
                if ($WindowsRelease -in 10, 11) { $Name = "Cumulative update for .NET framework windows $WindowsRelease $WindowsVersion $WindowsArch -preview" }
                if ($WindowsRelease -eq 2025 -and $installationType -eq "Server") { $Name = """Cumulative Update for .NET Framework"" ""3.5 and 4.8.1"" for Windows 11 24H2 x64 -preview" }
                if ($WindowsRelease -eq 2022 -and $installationType -eq "Server") { $Name = """Cumulative Update for .NET Framework 3.5, 4.8 and 4.8.1"" ""operating system version 21H2 for x64""" }
                if ($WindowsRelease -eq 2019 -and $installationType -eq "Server") { $Name = """Cumulative Update for .NET Framework 3.5, 4.7.2 and 4.8 for Windows Server 2019 for x64""" }
                if ($WindowsRelease -eq 2016 -and $installationType -eq "Server") { $Name = """Cumulative Update for .NET Framework 4.8 for Windows Server 2016 for x64""" }
                WriteLog "Searching for $Name from Microsoft Update Catalog"
                (Get-UpdateFileInfo -Name $Name) | ForEach-Object { $netUpdateInfos.Add($_) }
                $netKbArticleId = $global:LastKBArticleID
            }
        }

        if ($UpdateLatestMicrocode -and $WindowsRelease -in 2016, 2019) {
            WriteLog "`$UpdateLatestMicrocode is set to true, checking for latest Microcode"
            if ($WindowsRelease -eq 2016) { $name = "KB4589210 $windowsArch" }
            if ($WindowsRelease -eq 2019) { $name = "KB4589208 $windowsArch" }
            WriteLog "Searching for $name from Microsoft Update Catalog"
            (Get-UpdateFileInfo -Name $name) | ForEach-Object { $microcodeUpdateInfos.Add($_) }
        }
        
        $esdVerObj = $null
        $cuVerObj = $null
        $cupVerObj = $null
        if ($esdVersion) { try { $esdVerObj = [version]$esdVersion } catch { } }
        if ($cuKbWindowsVersion) { try { $cuVerObj = [version]$cuKbWindowsVersion } catch { } }
        if ($cupKbWindowsVersion) { try { $cupVerObj = [version]$cupKbWindowsVersion } catch { } }
        
        if ($esdVerObj -and $cuVerObj) {
            if ($esdVerObj -eq $cuVerObj -or $esdVerObj -gt $cuVerObj) {
                $skipReason = if ($esdVerObj -eq $cuVerObj) { 'matches' } else { 'is newer than' }
                WriteLog "Windows 11 ESD version $esdVersion $skipReason CU version $cuKbWindowsVersion. Skipping CU download and installation."
                if ($AllowVHDXCaching -and $cuUpdateInfos -and $cuUpdateInfos.Count -gt 0) {
                    foreach ($cuUpdateInfo in $cuUpdateInfos) {
                        if (-not [string]::IsNullOrWhiteSpace($cuUpdateInfo.Name) -and -not $cachedIncludedUpdateNames.Contains($cuUpdateInfo.Name)) {
                            $cachedIncludedUpdateNames.Add($cuUpdateInfo.Name)
                        }
                    }
                }
                $cuUpdateInfos.Clear()
                $UpdateLatestCU = $false
                $CUPath = $null
            }
        }
        if ($esdVerObj -and $cupVerObj) {
            if ($esdVerObj -eq $cupVerObj -or $esdVerObj -gt $cupVerObj) {
                $skipReason = if ($esdVerObj -eq $cupVerObj) { 'matches' } else { 'is newer than' }
                WriteLog "Windows 11 ESD version $esdVersion $skipReason Preview CU version $cupKbWindowsVersion. Skipping Preview CU download and installation."
                if ($AllowVHDXCaching -and $cupUpdateInfos -and $cupUpdateInfos.Count -gt 0) {
                    foreach ($cupUpdateInfo in $cupUpdateInfos) {
                        if (-not [string]::IsNullOrWhiteSpace($cupUpdateInfo.Name) -and -not $cachedIncludedUpdateNames.Contains($cupUpdateInfo.Name)) {
                            $cachedIncludedUpdateNames.Add($cupUpdateInfo.Name)
                        }
                    }
                }
                $cupUpdateInfos.Clear()
                $UpdatePreviewCU = $false
                $CUPPath = $null
            }
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
            
            # Build comparison list from update names and cached names
            $requiredUpdateFileNames = @()
            if ($requiredUpdates.Count -gt 0) {
                $requiredUpdateFileNames += $requiredUpdates | ForEach-Object {
                    if (-not [string]::IsNullOrWhiteSpace($_.Name)) {
                        $_.Name
                    }
                    elseif (-not [string]::IsNullOrWhiteSpace($_.Url)) {
                        ($_.Url -split '/')[-1]
                    }
                }
            }
            if ($cachedIncludedUpdateNames.Count -gt 0) {
                $requiredUpdateFileNames += $cachedIncludedUpdateNames
            }
            if ($requiredUpdateFileNames.Count -gt 0) {
                $requiredUpdateFileNames = @($requiredUpdateFileNames | Where-Object { $_ } | Sort-Object -Unique)
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

    # If no cached VHDX is found, download the required updates now
    if (-Not $cachedVHDXFileFound -and $requiredUpdates.Count -gt 0) {
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

            # Skip download if expected file is already present
            $expectedFilePath = Join-Path -Path $destinationPath -ChildPath $update.Name

            if (Test-Path -LiteralPath $expectedFilePath) {
                WriteLog "Update already exists at $expectedFilePath, skipping download"
                continue
            }

            WriteLog "Downloading $($update.Name) to $destinationPath"
            Start-BitsTransferWithRetry -Source $update.Url -Destination $destinationPath
        }
    

        # Set file path variables for the patching process
        if ($ssuUpdateInfos.Count -gt 0) {
            $SSUFile = $ssuUpdateInfos[0].Name
            $SSUFilePath = "$KBPath\$SSUFile"
            WriteLog "Latest SSU identified as $SSUFilePath"
        }
        if ($cuUpdateInfos.Count -gt 0) {
            if (-not $CUPath) {
                $CUPath = (Get-ChildItem -Path $KBPath -Filter "*$cuKbArticleId*" -Recurse | Select-Object -First 1).FullName
            }
            WriteLog "Latest CU identified as $CUPath"
        }
        if ($cupUpdateInfos.Count -gt 0) {
            if (-not $CUPPath) {
                $CUPPath = (Get-ChildItem -Path $KBPath -Filter "*$cupKbArticleId*" -Recurse | Select-Object -First 1).FullName
            }
            WriteLog "Latest Preview CU identified as $CUPPath"
        }
        if ($netUpdateInfos.Count -gt 0 -or $netFeatureUpdateInfos.Count -gt 0) {
            if ($isLTSC -and $WindowsRelease -in 2016, 2019, 2021) {
                $NETPath = Join-Path -Path $KBPath -ChildPath "NET"
                WriteLog ".NET updates for LTSC are in $NETPath"
            }
            else {
                # Use the actual downloaded file name from the update info
                $NETFileName = $netUpdateInfos[0].Name
                $NETPath = (Get-ChildItem -Path $KBPath -Filter $NETFileName -Recurse).FullName
                if (-not $NETPath) {
                    # If exact match fails, try to find by KB article ID
                    $NETPath = (Get-ChildItem -Path $KBPath -Filter "*$netKbArticleId*" -Recurse | Select-Object -First 1).FullName
                    if ($NETPath) {
                        $NETFileName = Split-Path $NETPath -Leaf
                    }
                }
                WriteLog "Latest .NET Framework identified as $NETPath"
            }
        }
        if ($microcodeUpdateInfos.Count -gt 0) {
            $MicrocodePath = "$KBPath\Microcode"
            WriteLog "Microcode updates are in $MicrocodePath"
        }
    }
    
    if (-Not $cachedVHDXFileFound) {
        Set-Progress -Percentage 15 -Message "Creating VHDX and applying base Windows image..."
        if ($ISOPath) {
            $wimPath = Get-WimFromISO
        }
        else {
            $wimPath = Get-WindowsESD -WindowsRelease $WindowsRelease -WindowsArch $WindowsArch -WindowsLang $WindowsLang -MediaType $mediaType -Metadata $esdMetadata
        }
        #If index not specified by user, try and find based on WindowsSKU
        if (-not($index) -and ($WindowsSKU)) {
            $index = Get-Index -WindowsImagePath $wimPath -WindowsSKU $WindowsSKU
        }

        $vhdxDisk = New-ScratchVhdx -VhdxPath $VHDXPath -SizeBytes $disksize -LogicalSectorSizeBytes $LogicalSectorSizeBytes

        $systemPartitionDriveLetter = New-SystemPartition -VhdxDisk $vhdxDisk
    
        New-MSRPartition -VhdxDisk $vhdxDisk
    
        Set-Progress -Percentage 16 -Message "Applying base Windows image to VHDX..."
        $osPartition = New-OSPartition -VhdxDisk $vhdxDisk -OSPartitionSize $OSPartitionSize -WimPath $WimPath -WimIndex $index
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
                # If WindowsRelease is 2016, we need to add the SSU first
                if ($WindowsRelease -eq 2016 -and $installationType -eq "Server") {
                    WriteLog 'WindowsRelease is 2016, adding SSU first'
                    WriteLog "Adding SSU to $WindowsPartition"
                    # Add-WindowsPackage -Path $WindowsPartition -PackagePath $SSUFilePath -PreventPending | Out-Null
                    # Commenting out -preventpending as it causes an issue with the SSU being applied
                    # Seems to be because of the registry being mounted per dism.log
                    Add-WindowsPackage -Path $WindowsPartition -PackagePath $SSUFilePath | Out-Null
                    WriteLog "SSU added to $WindowsPartition"
                    # WriteLog "Removing $SSUFilePath"
                    # Remove-Item -Path $SSUFilePath -Force | Out-Null
                    # WriteLog 'SSU removed'
                }
                if ($WindowsRelease -in 2016, 2019, 2021 -and $isLTSC) {
                    WriteLog "WindowsRelease is $WindowsRelease and is $WindowsSKU, adding SSU first"
                    WriteLog "Adding SSU to $WindowsPartition"
                    Add-WindowsPackage -Path $WindowsPartition -PackagePath $SSUFilePath | Out-Null
                    WriteLog "SSU added to $WindowsPartition"
                    # WriteLog "Removing $SSUFilePath"
                    # Remove-Item -Path $SSUFilePath -Force | Out-Null
                    # WriteLog 'SSU removed'
                }
                # Break out CU and NET updates to be added separately to abide by Checkpoint Update recommendations
                if ($UpdateLatestCU) {
                    WriteLog "Adding $CUPath to $WindowsPartition"
                    Add-WindowsPackage -Path $WindowsPartition -PackagePath $CUPath | Out-Null
                    WriteLog "$CUPath added to $WindowsPartition"
                }
                if ($UpdatePreviewCU) {
                    WriteLog "Adding $CUPPath to $WindowsPartition"
                    Add-WindowsPackage -Path $WindowsPartition -PackagePath $CUPPath | Out-Null
                    WriteLog "$CUPPath added to $WindowsPartition"
                }
                if ($UpdateLatestNet) {
                    WriteLog "Adding $NETPath to $WindowsPartition"
                    Add-WindowsPackage -Path $WindowsPartition -PackagePath $NETPath | Out-Null
                    WriteLog "$NETPath added to $WindowsPartition"
                }
                if ($UpdateLatestMicrocode -and $WindowsRelease -in 2016, 2019) {
                    WriteLog "Adding $MicrocodePath to $WindowsPartition"
                    Add-WindowsPackage -Path $WindowsPartition -PackagePath $MicrocodePath | Out-Null
                    WriteLog "$MicrocodePath added to $WindowsPartition"
                }
                WriteLog "KBs added to $WindowsPartition"
                if ($AllowVHDXCaching) {
                    $cachedVHDXInfo = [VhdxCacheItem]::new()
                    # Record only updates from this build (current required updates and any cached names carried forward)
                    $includedUpdateNames = [System.Collections.Generic.List[string]]::new()
                    foreach ($includedUpdate in $requiredUpdates) {
                        if (-not [string]::IsNullOrWhiteSpace($includedUpdate.Name)) {
                            $includedUpdateNames.Add($includedUpdate.Name)
                        }
                    }
                    foreach ($cachedName in $cachedIncludedUpdateNames) {
                        if (-not [string]::IsNullOrWhiteSpace($cachedName)) {
                            $includedUpdateNames.Add($cachedName)
                        }
                    }
                    foreach ($includedName in ($includedUpdateNames | Sort-Object -Unique)) {
                        if (-not ($cachedVHDXInfo.IncludedUpdates | Where-Object { $_.Name -eq $includedName })) {
                            $cachedVHDXInfo.IncludedUpdates += ([VhdxCacheUpdateItem]::new($includedName))
                        }
                    }
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
            Enable-WindowsFeaturesByName -FeatureNames $OptionalFeatures -Source $Source
        }
        If ($ISOPath) {
            WriteLog 'Dismounting Windows ISO'
            Dismount-DiskImage -ImagePath $ISOPath | Out-null
            WriteLog 'Done'
        }
        #If $wimPath is an esd file, remove it
        If ($wimPath -match '.esd') {
            WriteLog "Deleting $wimPath file"
            Remove-Item -Path $wimPath -Force
            WriteLog "$wimPath deleted"
        }
    
    }
    else {
        #Use cached vhdx file
        WriteLog 'Using cached VHDX file to speed up build process'
        WriteLog "VHDX file is: $($cachedVHDXInfo.VhdxFileName)"

        Robocopy.exe $($VHDXCacheFolder) $($VMPath) $($cachedVHDXInfo.VhdxFileName) /E /COPY:DAT /R:5 /W:5 /J
        $VHDXPath = Join-Path $($VMPath) $($cachedVHDXInfo.VhdxFileName)

        $vhdxDisk = Get-VHD -Path $VHDXPath | Mount-VHD -Passthru | Get-Disk
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

        WriteLog 'Defragmenting Windows partition...'
        Optimize-Volume -DriveLetter $osPartition.DriveLetter -Defrag -NormalPriority 
        WriteLog 'Performing slab consolidation on Windows partition...'
        Optimize-Volume -DriveLetter $osPartition.DriveLetter -SlabConsolidate -NormalPriority 
        WriteLog 'Dismounting VHDX'
        Dismount-ScratchVhdx -VhdxPath $VHDXPath

        WriteLog 'Copying to cache dir'

        #Assuming there are now name collisons
        Robocopy.exe $($VMPath) $($VHDXCacheFolder) $("$VMName.vhdx") /E /COPY:DAT /R:5 /W:5 /J

        #Only create new instance if not created during patching
        if ($null -eq $cachedVHDXInfo) {
            $cachedVHDXInfo = [VhdxCacheItem]::new()
        }
        if ($AllowVHDXCaching -and $cachedIncludedUpdateNames.Count -gt 0) {
            foreach ($cachedName in $cachedIncludedUpdateNames) {
                if (-not ($cachedVHDXInfo.IncludedUpdates | Where-Object { $_.Name -eq $cachedName })) {
                    $cachedVHDXInfo.IncludedUpdates += ([VhdxCacheUpdateItem]::new($cachedName))
                }
            }
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
    Remove-Item -Path $VMPath -Force -Recurse | Out-Null
    WriteLog 'Removal complete'
    If ($ISOPath) {
        WriteLog 'Dismounting Windows ISO'
        Dismount-DiskImage -ImagePath $ISOPath | Out-null
        WriteLog 'Done'
    }
    else {
        #Remove ESD file
        WriteLog "Deleting ESD file"
        Remove-Item -Path $wimPath -Force
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
    }
    $osPartition = $disk | Get-Partition | Where-Object { $_.GptType -eq '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}' }
    $osPartitionDriveLetter = $osPartition.DriveLetter
    WriteLog 'Copying unattend file to boot to audit mode'
    New-Item -Path "$($osPartitionDriveLetter):\Windows\Panther\Unattend" -ItemType Directory -Force | Out-Null
    if ($WindowsArch -eq 'x64') {
        Copy-Item -Path "$FFUDevelopmentPath\BuildFFUUnattend\unattend_x64.xml" -Destination "$($osPartitionDriveLetter):\Windows\Panther\Unattend\Unattend.xml" -Force | Out-Null
    }
    else {
        Copy-Item -Path "$FFUDevelopmentPath\BuildFFUUnattend\unattend_arm64.xml" -Destination "$($osPartitionDriveLetter):\Windows\Panther\Unattend\Unattend.xml" -Force | Out-Null
    }
    WriteLog 'Copy completed'
    # Always dismount so downstream VM creation logic has a clean starting point
    Dismount-ScratchVhdx -VhdxPath $VHDXPath
}

#If installing apps (Office or 3rd party), we need to build a VM and capture that FFU, if not, just cut the FFU from the VHDX file
if ($InstallApps) {
    Set-Progress -Percentage 41 -Message "Starting VM for app installation..."
    #Create VM and attach VHDX
    try {
        WriteLog 'Creating new FFU VM'
        $FFUVM = New-FFUVM
        WriteLog 'FFU VM Created'
    }
    catch {
        Write-Host 'VM creation failed'
        Writelog "VM creation failed with error $_"
        Remove-FFUVM -VMName $VMName
        throw $_
        
    }
    #Create ffu user and share to capture FFU to
    try {
        Set-CaptureFFU
    }
    catch {
        Write-Host 'Set-CaptureFFU function failed'
        WriteLog "Set-CaptureFFU function failed with error $_"
        Remove-FFUVM -VMName $VMName
        throw $_
        
    }
    If ($CreateCaptureMedia) {
        #Create Capture Media
        try {
            Set-Progress -Percentage 45 -Message "Creating WinPE capture media..."
            #This should happen while the FFUVM is building
            New-PEMedia -Capture $true
        }
        catch {
            Write-Host 'Creating capture media failed'
            WriteLog "Creating capture media failed with error $_"
            Remove-FFUVM -VMName $VMName
            throw $_
        
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
    #Check if VM is done provisioning
    If ($InstallApps) {
        Set-Progress -Percentage 50 -Message "Installing applications in VM; please wait for VM to shut down..."
        do {
            $FFUVM = Get-VM -Name $FFUVM.Name
            Start-Sleep -Seconds 10
            WriteLog 'Waiting for VM to shutdown'
        } while ($FFUVM.State -ne 'Off')
        WriteLog 'VM Shutdown'
        Set-Progress -Percentage 65 -Message "Optimizing VHDX before capture..."
        Optimize-FFUCaptureDrive -VhdxPath $VHDXPath
        #Capture FFU file
        New-FFU $FFUVM.Name
    }
    else {
        #Shorten Windows SKU for use in FFU file name to remove spaces and long names
        WriteLog "Shortening Windows SKU: $WindowsSKU for FFU file name"
        $shortenedWindowsSKU = Get-ShortenedWindowsSKU -WindowsSKU $WindowsSKU
        WriteLog "Shortened Windows SKU: $shortenedWindowsSKU"
        #Create FFU file
        New-FFU
    }    
}
Catch {
    Write-Host 'Capturing FFU file failed'
    Writelog "Capturing FFU file failed with error $_"
    If ($InstallApps) {
        Remove-FFUVM -VMName $VMName
    }
    else {
        Remove-FFUVM
    }
    
    throw $_
    
}
#Clean up ffu_user and Share and clean up apps
If ($InstallApps) {
    try {
        Remove-FFUUserShare
    }
    catch {
        Write-Host 'Cleaning up FFU User and/or share failed'
        WriteLog "Cleaning up FFU User and/or share failed with error $_"
        Remove-FFUVM -VMName $VMName
        throw $_
    }
}
#Clean up VM or VHDX
try {
    Remove-FFUVM
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
        New-PEMedia -Deploy $true
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

Set-Progress -Percentage 99 -Message "Finalizing and cleaning up..."
# Delegated post-build cleanup to common module
Invoke-FFUPostBuildCleanup -RootPath $FFUDevelopmentPath -AppsPath $AppsPath -DriversPath $DriversFolder -FFUCapturePath $FFUCaptureLocation -CaptureISOPath $CaptureISO -DeployISOPath $DeployISO -AppsISOPath $AppsISO -RemoveCaptureISO:$CleanupCaptureISO -RemoveDeployISO:$CleanupDeployISO -RemoveAppsISO:$CleanupAppsISO -RemoveDrivers:$CleanupDrivers -RemoveFFU:$RemoveFFU -RemoveApps:$RemoveApps -RemoveUpdates:$RemoveUpdates -KBPath:$KBPath


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
Remove-Item -Path .\dirty.txt -Force | out-null
# Remove per-run session folder if present
$sessionDir = Join-Path $FFUDevelopmentPath '.session'
if (Test-Path -Path $sessionDir) { 
    Remove-Item -Path $sessionDir -Recurse -Force -ErrorAction SilentlyContinue 
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
