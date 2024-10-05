
#Requires -Modules Hyper-V, Storage
#Requires -PSEdition Desktop
#Requires -RunAsAdministrator

<#
.SYNOPSIS
A PowerShell script to create a Windows 10/11 FFU file. 

.DESCRIPTION
This script creates a Windows 10/11 FFU and USB drive to help quickly get a Windows device reimaged. FFU can be customized with drivers, apps, and additional settings. 

.PARAMETER ISOPath
Path to the Windows 10/11 ISO file.

.PARAMETER WindowsSKU
Edition of Windows 10/11 to be installed, e.g., accepted values are: 'Home', 'Home N', 'Home Single Language', 'Education', 'Education N', 'Pro', 'Pro N', 'Pro Education', 'Pro Education N', 'Pro for Workstations', 'Pro N for Workstations', 'Enterprise', 'Enterprise N'

.PARAMETER FFUDevelopmentPath
Path to the FFU development folder (default is C:\FFUDevelopment).

.PARAMETER InstallApps
When set to $true, the script will create an Apps.iso file from the $FFUDevelopmentPath\Apps folder. It will also create a VM, mount the Apps.ISO, install the Apps, sysprep, and capture the VM. When set to $False, the FFU is created from a VHDX file. No VM is created.

.PARAMETER InstallOffice
Install Microsoft Office if set to $true. The script will download the latest ODT and Office files in the $FFUDevelopmentPath\Apps\Office folder and install Office in the FFU via VM

.PARAMETER InstallDrivers
Install device drivers from the specified $FFUDevelopmentPath\Drivers folder if set to $true. Download the drivers and put them in the Drivers folder. The script will recurse the drivers folder and add the drivers to the FFU.

.PARAMETER Memory
Amount of memory to allocate for the virtual machine. Recommended to use 8GB if possible, especially for Windows 11. Use 4GB if necesary.

.PARAMETER Disksize
Size of the virtual hard disk for the virtual machine. Default is a 30GB dynamic disk.

.PARAMETER Processors
Number of virtual processors for the virtual machine. Recommended to use at least 4.

.PARAMETER VMSwitchName
Name of the Hyper-V virtual switch. If $InstallApps is set to $true, this must be set. This is required to capture the FFU from the VM. The default is *external*, but you will likely need to change this. 

.PARAMETER VMLocation
Default is $FFUDevelopmentPath\VM. This is the location of the VHDX that gets created where Windows will be installed to. 

.PARAMETER FFUPrefix
Prefix for the generated FFU file. Default is _FFU

.PARAMETER FFUCaptureLocation
Path to the folder where the captured FFU will be stored. Default is $FFUDevelopmentPath\FFU

.PARAMETER ShareName
Name of the shared folder for FFU capture. The default is FFUCaptureShare. This share will be created with rights for the user account. When finished, the share will be removed.

.PARAMETER Username
Username for accessing the shared folder. The default is ffu_user. The script will auto create the account and password. When finished, it will remove the account.

.PARAMETER VMHostIPAddress
IP address of the Hyper-V host for FFU capture. If $InstallApps is set to $true, this parameter must be configured. You must manually configure this. The script will not auto detect your IP (depending on your network adapters, it may not find the correct IP).

.PARAMETER CreateCaptureMedia
When set to $true, this will create WinPE capture media for use when $InstallApps is set to $true. This capture media will be automatically attached to the VM and the boot order will be changed to automate the capture of the FFU.

.PARAMETER CreateDeploymentMedia
When set to $true, this will create WinPE deployment media for use when deploying to a physical device.

.PARAMETER OptionalFeatures
Provide a semi-colon separated list of Windows optional features you want to include in the FFU (e.g. netfx3;TFTP)

.PARAMETER ProductKey
Product key for the Windows 10/11 edition specified in WindowsSKU. This will overwrite whatever SKU is entered for WindowsSKU. Recommended to use if you want to use a MAK or KMS key to activate Enterprise or Education. If using VL media instead of consumer media, you'll want to enter a MAK or KMS key here.

.PARAMETER BuildUSBDrive
When set to $true, will partition and format a USB drive and copy the captured FFU to the drive. If you'd like to customize the drive to add drivers, provisioning packages, name prefix, etc. You'll need to do that afterward.

.PARAMETER WindowsRelease
Integer value of 10 or 11. This is used to identify which release of Windows to download. Default is 11.

.PARAMETER WindowsVersion
String value of the Windows version to download. This is used to identify which version of Windows to download. Default is 23h2.

.PARAMETER WindowsArch
String value of x86 or x64. This is used to identify which architecture of Windows to download. Default is x64.

.PARAMETER WindowsLang
String value in language-region format (e.g. en-us). This is used to identify which language of media to download. Default is en-us.

.PARAMETER MediaType
String value of either business or consumer. This is used to identify which media type to download. Default is consumer.

.PARAMETER LogicalSectorBytes
unit32 value of 512 or 4096. Not recommended to change from 512. Might be useful for 4kn drives, but needs more testing. Default is 512.

.PARAMETER Optimize
When set to $true, will optimize the FFU file. Default is $true.

.PARAMETER CopyDrivers
When set to $true, will copy the drivers from the $FFUDevelopmentPath\Drivers folder to the Drivers folder on the deploy partition of the USB drive. Default is $false.

.PARAMETER CopyPEDrivers
When set to $true, will copy the drivers from the $FFUDevelopmentPath\PEDrivers folder to the WinPE deployment media. Default is $false.

.PARAMETER RemoveFFU
When set to $true, will remove the FFU file from the $FFUDevelopmentPath\FFU folder after it has been copied to the USB drive. Default is $false.

.PARAMETER UpdateLatestCU
When set to $true, will download and install the latest cumulative update for Windows 10/11. Default is $false.

.PARAMETER UpdatePreviewCU
When set to $true, will download and install the latest Preview cumulative update for Windows 10/11. Default is $false.

.PARAMETER UpdateLatestNet
When set to $true, will download and install the latest .NET Framework for Windows 10/11. Default is $false.

.PARAMETER UpdateLatestDefender
When set to $true, will download and install the latest Windows Defender definitions and Defender platform update. Default is $false.

.PARAMETER UpdateLatestMSRT
When set to $true, will download and install the latest Windows Malicious Software Removal Tool. Default is $false

.PARAMETER UpdateEdge
When set to $true, will download and install the latest Microsoft Edge for Windows 10/11. Default is $false.

.PARAMETER UpdateOneDrive
When set to $true, will download and install the latest OneDrive for Windows 10/11 and install it as a per machine installation instead of per user. Default is $false.

.PARAMETER CopyPPKG
When set to $true, will copy the provisioning package from the $FFUDevelopmentPath\PPKG folder to the Deployment partition of the USB drive. Default is $false.

.PARAMETER CopyUnattend
When set to $true, will copy the $FFUDevelopmentPath\Unattend folder to the Deployment partition of the USB drive. Default is $false.

.PARAMETER CopyAutopilot
When set to $true, will copy the $FFUDevelopmentPath\Autopilot folder to the Deployment partition of the USB drive. Default is $false.

.PARAMETER CompactOS
When set to $true, will compact the OS when building the FFU. Default is $true.

.PARAMETER CleanupCaptureISO
When set to $true, will remove the WinPE capture ISO after the FFU has been captured. Default is $true.

.PARAMETER CleanupDeployISO
When set to $true, will remove the WinPE deployment ISO after the FFU has been captured. Default is $true.

.PARAMETER CleanupAppsISO
When set to $true, will remove the Apps ISO after the FFU has been captured. Default is $true.

.PARAMETER DriversFolder
Path to the drivers folder. Default is $FFUDevelopmentPath\Drivers.

.PARAMETER CleanupDrivers
When set to $true, will remove the drivers folder after the FFU has been captured. Default is $true.

.PARAMETER UserAgent
User agent string to use when downloading files.

.PARAMETER Headers
Headers to use when downloading files.

.PARAMETER AllowExternalHardDiskMedia
When set to $true, will allow the use of media identified as External Hard Disk media via WMI class Win32_DiskDrive. Default is not defined.

.PARAMETER PromptExternalHardDiskMedia
When set to $true, will prompt the user to confirm the use of media identified as External Hard Disk media via WMI class Win32_DiskDrive. Default is $true.

.PARAMETER Make
Make of the device to download drivers. Accepted values are: 'Microsoft', 'Dell', 'HP', 'Lenovo'

.PARAMETER Model
Model of the device to download drivers. This is required if Make is set.

.PARAMETER AppsScriptVariables
When passed a hashtable, the script will alter the $FFUDevelopmentPath\Apps\InstallAppsandSysprep.cmd file to set variables with the hashtable keys as variable names and the hashtable values their content.

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
    [ValidateSet('Home', 'Home N', 'Home Single Language', 'Education', 'Education N', 'Pro', 'Pro N', 'Pro Education', 'Pro Education N', 'Pro for Workstations', 'Pro N for Workstations', 'Enterprise', 'Enterprise N', 'Standard', 'Standard (Desktop Experience)', 'Datacenter', 'Datacenter (Desktop Experience)')]
    [string]$WindowsSKU = 'Pro',
    [ValidateScript({ Test-Path $_ })]
    [string]$FFUDevelopmentPath = $PSScriptRoot,

    [bool]$InstallApps,

    [hashtable]$AppsScriptVariables,
    [bool]$InstallOffice,
    [ValidateSet('Microsoft', 'Dell', 'HP', 'Lenovo')]
    [string]$Make,
    [string]$Model,
    # [Parameter(Mandatory = $false)]
    # [ValidateScript({
    #     if ($Make) {
    #         return $true
    #     }
    #     if ($_ -and (!(Test-Path -Path '.\Drivers') -or ((Get-ChildItem -Path '.\Drivers' -Recurse | Measure-Object -Property Length -Sum).Sum -lt 1MB))) {
    #         throw 'InstallDrivers is set to $true, but either the Drivers folder is missing or empty'
    #     }
    #     return $true
    # })]
    [bool]$InstallDrivers,
    [uint64]$Memory = 4GB,
    [uint64]$Disksize = 30GB,
    [int]$Processors = 4,
    [string]$VMSwitchName,
    [string]$VMLocation,
    [string]$FFUPrefix = '_FFU',
    [string]$FFUCaptureLocation,
    [String]$ShareName = "FFUCaptureShare",
    [string]$Username = "ffu_user",
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
    [Parameter(Mandatory = $false)]
    [ValidateSet(10, 11, 2016, 2019, 2022, 2025)]
    [int]$WindowsRelease = 11,
    [Parameter(Mandatory = $false)]
    [string]$WindowsVersion = '23h2',
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
    [Parameter(Mandatory = $false)]
    [ValidateScript({
            if ($Make) {
                return $true
            }
            if ($_ -and (!(Test-Path -Path '.\Drivers') -or ((Get-ChildItem -Path '.\Drivers' -Recurse | Measure-Object -Property Length -Sum).Sum -lt 1MB))) {
                throw 'CopyDrivers is set to $true, but either the Drivers folder is missing or empty'
            }
            return $true
        })]
    [bool]$CopyDrivers,
    [bool]$CopyPEDrivers,
    [bool]$RemoveFFU,
    [bool]$UpdateLatestCU,
    [bool]$UpdatePreviewCU,
    [bool]$UpdateLatestNet,
    [bool]$UpdateLatestDefender,
    [bool]$UpdateLatestMSRT,
    [bool]$UpdateEdge,
    [bool]$UpdateOneDrive,
    [bool]$AllowUpdateCaching,
    [bool]$AllowVHDXCaching,
    [bool]$CopyPPKG,
    [bool]$CopyUnattend,
    [bool]$CopyAutopilot,
    [bool]$CompactOS = $true,
    [bool]$CleanupCaptureISO = $true,
    [bool]$CleanupDeployISO = $true,
    [bool]$CleanupAppsISO = $true,
    [string]$DriversFolder,
    [bool]$CleanupDrivers = $true,
    [string]$UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36 Edg/125.0.0.0',
    #Microsoft sites will intermittently fail on downloads. These headers are to help with that.
    $Headers = @{
        "Accept" = "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7"
        "Accept-Encoding" = "gzip, deflate, br, zstd"
        "Accept-Language" = "en-US,en;q=0.9"
        "Priority" = "u=0, i"
        "Sec-Ch-Ua" = "`"Microsoft Edge`";v=`"125`", `"Chromium`";v=`"125`", `"Not.A/Brand`";v=`"24`""
        "Sec-Ch-Ua-Mobile" = "?0"
        "Sec-Ch-Ua-Platform" = "`"Windows`""
        "Sec-Fetch-Dest" = "document"
        "Sec-Fetch-Mode" = "navigate"
        "Sec-Fetch-Site" = "none"
        "Sec-Fetch-User" = "?1"
        "Upgrade-Insecure-Requests" = "1"
    },
    [bool]$AllowExternalHardDiskMedia,
    [bool]$PromptExternalHardDiskMedia = $true
)
$version = '2410.1'

#Class definition for vhdx cache
class VhdxCacheUpdateItem {
    [string]$Name
    VhdxCacheUpdateItem([string]$Name) {
        $this.Name = $Name
    }
}

class VhdxCacheItem {
    [string]$VhdxFileName = ""
    [string]$WindowsSKU = ""
    [string]$WindowsRelease = ""
    [string]$WindowsVersion = ""
    [string]$OptionalFeatures = ""
    [VhdxCacheUpdateItem[]]$IncludedUpdates = @()
}

#Check if Hyper-V feature is installed (requires only checks the module)
$osInfo = Get-WmiObject -Class Win32_OperatingSystem
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
if (-not $DeployISO) { $DeployISO = "$FFUDevelopmentPath\WinPE_FFU_Deploy_$WindowsArch.iso" }
if (-not $CaptureISO) { $CaptureISO = "$FFUDevelopmentPath\WinPE_FFU_Capture_$WindowsArch.iso" }
if (-not $OfficePath) { $OfficePath = "$AppsPath\Office" }
if (-not $rand) { $rand = Get-Random }
if (-not $VMLocation) { $VMLocation = "$FFUDevelopmentPath\VM" }
if (-not $VMName) { $VMName = "$FFUPrefix-$rand" }
if (-not $VMPath) { $VMPath = "$VMLocation\$VMName" }
if (-not $VHDXPath) { $VHDXPath = "$VMPath\$VMName.vhdx" }
if (-not $FFUCaptureLocation) { $FFUCaptureLocation = "$FFUDevelopmentPath\FFU" }
if (-not $LogFile) { $LogFile = "$FFUDevelopmentPath\FFUDevelopment.log" }
if (-not $KBPath) { $KBPath = "$FFUDevelopmentPath\KB" }
if (-not $KBCachePath) { $KBCachePath = "$FFUDevelopmentPath\KBCache" }
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
if (-not $installationType) { $installationType = if ($WindowsRelease.ToString().Length -eq 2) { 'Client' } else { 'Server' } }
if ($installationType -eq 'Server'){
    #Map $WindowsRelease to $WindowsVersion for Windows Server
    switch ($WindowsRelease) {
        2016 { $WindowsVersion = '1607' }
        2019 { $WindowsVersion = '1809' }
        2022 { $WindowsVersion = '21H2' }
    }
}

#FUNCTIONS
function WriteLog($LogText) { 
    Add-Content -path $LogFile -value "$((Get-Date).ToString()) $LogText" -Force -ErrorAction SilentlyContinue
    Write-Verbose $LogText
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

function Invoke-Process {
    [CmdletBinding(SupportsShouldProcess)]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ArgumentList
    )

    $ErrorActionPreference = 'Stop'

    try {
        $stdOutTempFile = "$env:TEMP\$((New-Guid).Guid)"
        $stdErrTempFile = "$env:TEMP\$((New-Guid).Guid)"

        $startProcessParams = @{
            FilePath               = $FilePath
            ArgumentList           = $ArgumentList
            RedirectStandardError  = $stdErrTempFile
            RedirectStandardOutput = $stdOutTempFile
            Wait                   = $true;
            PassThru               = $true;
            NoNewWindow            = $true;
        }
        if ($PSCmdlet.ShouldProcess("Process [$($FilePath)]", "Run with args: [$($ArgumentList)]")) {
            $cmd = Start-Process @startProcessParams
            $cmdOutput = Get-Content -Path $stdOutTempFile -Raw
            $cmdError = Get-Content -Path $stdErrTempFile -Raw
            if ($cmd.ExitCode -ne 0) {
                if ($cmdError) {
                    throw $cmdError.Trim()
                }
                if ($cmdOutput) {
                    throw $cmdOutput.Trim()
                }
            }
            else {
                if ([string]::IsNullOrEmpty($cmdOutput) -eq $false) {
                    WriteLog $cmdOutput
                }
            }
        }
    }
    catch {
        #$PSCmdlet.ThrowTerminatingError($_)
        WriteLog $_
        Write-Host "Script failed - $Logfile for more info"
        throw $_

    }
    finally {
        Remove-Item -Path $stdOutTempFile, $stdErrTempFile -Force -ErrorAction Ignore
		
    }
	
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

# Function to download a file using BITS with retry and error handling
function Start-BitsTransferWithRetry {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Source,
        [Parameter(Mandatory = $true)]
        [string]$Destination,
        [int]$Retries = 3
    )

    $attempt = 0
    while ($attempt -lt $Retries) {
        try {
            $OriginalVerbosePreference = $VerbosePreference
            $VerbosePreference = 'SilentlyContinue'
            $ProgressPreference = 'SilentlyContinue'
            Start-BitsTransfer -Source $Source -Destination $Destination -ErrorAction Stop
            $ProgressPreference = 'Continue'
            $VerbosePreference = $OriginalVerbosePreference
            return
        }
        catch {
            $attempt++
            WriteLog "Attempt $attempt of $Retries failed to download $Source. Retrying..."
            Start-Sleep -Seconds 5
        }
    }
    WriteLog "Failed to download $Source after $Retries attempts."
    return $false
}

function Get-MicrosoftDrivers {
    param (
        [string]$Make,
        [string]$Model,
        [int]$WindowsRelease
    )

    $url = "https://support.microsoft.com/en-us/surface/download-drivers-and-firmware-for-surface-09bb2e09-2a4b-cb69-0951-078a7739e120"
    
    # Download the webpage content
    WriteLog "Getting Surface driver information from $url"
    $OriginalVerbosePreference = $VerbosePreference
    $VerbosePreference = 'SilentlyContinue'
    $webContent = Invoke-WebRequest -Uri $url -UseBasicParsing -Headers $Headers -UserAgent $UserAgent
    $VerbosePreference = $OriginalVerbosePreference
    WriteLog "Complete"

    # Parse the HTML content
    WriteLog "Parsing web content for models and download links"
    $html = $webContent.Content
    $document = New-Object -ComObject "HTMLFILE"
    $document.IHTMLDocument2_write($html)
    $document.Close()

    $models = @()

    # Select all divs with class 'selectable-content-options__option-content'
    $divs = $document.getElementsByTagName("div") | Where-Object {
        $_.className -eq "selectable-content-options__option-content" -or $_.className -eq "selectable-content-options__option-content ocHidden"
    }

    foreach ($div in $divs) {
        $tables = $div.getElementsByTagName("table")
        foreach ($table in $tables) {
            $rows = $table.getElementsByTagName("tr")
            foreach ($row in $rows) {
                $cells = $row.getElementsByTagName("td")
                if ($cells.length -ge 2) {
                    $modelName = $cells[0].innerText.Trim()
                    $linkElement = $cells[1].getElementsByTagName("a")
                    if ($linkElement.length -gt 0) {
                        $modelLink = $linkElement[0].href
                        $models += [PSCustomObject]@{ Model = $modelName; Link = $modelLink }
                    } else {
                        # Handle cases with instructions instead of links
                        $modelLink = $cells[1].innerText.Trim()
                        $models += [PSCustomObject]@{ Model = $modelName; Link = $modelLink }
                    }
                }
            }
        }
    }
    WriteLog "Parsing complete"

    # Validate the model
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
            } else {
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

    # Follow the link to the download page and parse the script tag
    WriteLog "Getting download page content"
    $OriginalVerbosePreference = $VerbosePreference
    $VerbosePreference = 'SilentlyContinue'
    $downloadPageContent = Invoke-WebRequest -Uri $selectedModel.Link -UseBasicParsing -Headers $Headers -UserAgent $UserAgent
    $VerbosePreference = $OriginalVerbosePreference
    WriteLog "Complete"
    WriteLog "Parsing download page for file"
    $scriptPattern = '<script>window.__DLCDetails__={(.*?)}</script>'
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

        if ($downloadLink) {
            WriteLog "Download Link for Windows ${WindowsRelease}: $downloadLink"
        
            # Create directory structure
            if (-not (Test-Path -Path $DriversFolder)) {
                WriteLog "Creating Drivers folder: $DriversFolder"
                New-Item -Path $DriversFolder -ItemType Directory -Force | Out-Null
                WriteLog "Drivers folder created"
            }
            $surfaceDriversPath = Join-Path -Path $DriversFolder -ChildPath $Make
            $modelPath = Join-Path -Path $surfaceDriversPath -ChildPath $Model
            if (-Not (Test-Path -Path $modelPath)) {
                WriteLog "Creating model folder: $modelPath"
                New-Item -Path $modelPath -ItemType Directory | Out-Null
                WriteLog "Complete"
            }
        
            # Download the file
            $filePath = Join-Path -Path $surfaceDriversPath -ChildPath ($fileName)
            WriteLog "Downloading $Model driver file to $filePath"
            Start-BitsTransferWithRetry -Source $downloadLink -Destination $filePath
            WriteLog "Download complete"
        
            # Determine file extension
            $fileExtension = [System.IO.Path]::GetExtension($filePath).ToLower()
        
            if ($fileExtension -eq ".msi") {
                # Extract the MSI file using an administrative install
                WriteLog "Extracting MSI file to $modelPath"
                $arguments = "/a `"$($filePath)`" /qn TARGETDIR=`"$($modelPath)`""
                Invoke-Process -FilePath "msiexec.exe" -ArgumentList $arguments
                WriteLog "Extraction complete"
            } elseif ($fileExtension -eq ".zip") {
                # Extract the ZIP file
                WriteLog "Extracting ZIP file to $modelPath"
                $ProgressPreference = 'SilentlyContinue'
                Expand-Archive -Path $filePath -DestinationPath $modelPath -Force
                $ProgressPreference = 'Continue'
                WriteLog "Extraction complete"
            } else {
                WriteLog "Unsupported file type: $fileExtension"
            }
            # Remove the downloaded file
            WriteLog "Removing $filePath"
            Remove-Item -Path $filePath -Force
            WriteLog "Complete"
        } else {
            WriteLog "No download link found for Windows $WindowsRelease."
        }
    } else {
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
    Invoke-Process -FilePath expand.exe -ArgumentList "$PlatformListCab $PlatformListXml"
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
    $ModelRelease = $SystemID + "_$Arch" + "_$WindowsRelease" + ".0.$WindowsVersion"
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
    Invoke-Process -FilePath expand.exe -ArgumentList "$DriverCabFile $DriverXmlFile"

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
        Start-BitsTransferWithRetry -Source $DriverUrl -Destination $DriverFilePath
        WriteLog 'Driver downloaded'

        # Make folder for extraction
        $extractFolder = "$downloadFolder\$Name\$Version\" + $DriverFileName.TrimEnd('.exe')
        Writelog "Creating extraction folder: $extractFolder"
        New-Item -Path $extractFolder -ItemType Directory -Force | Out-Null
        WriteLog 'Extraction folder created'
    
        # Extract the driver
        $arguments = "/s /e /f `"$extractFolder`""
        WriteLog "Extracting driver"
        Invoke-Process -FilePath $DriverFilePath -ArgumentList $arguments
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

        return ,$products
    }
    
    # Parse the Lenovo PSREF page for the model
    $machineTypes = Get-LenovoPSREF -ModelName $Model
    if ($machineTypes.ProductName.Count -eq 0) {
        WriteLog "No machine types found for model: $Model"
        WriteLog "Enter a valid model or machine type in the -model parameter"
        exit
    } elseif ($machineTypes.ProductName.Count -eq 1) {
        $machineType = $machineTypes[0].MachineType
        $model = $machineTypes[0].ProductName
    } else {
        if ($VerbosePreference -ne 'Continue'){
            Write-Output "Multiple machine types found for model: $Model"
        }
        WriteLog "Multiple machine types found for model: $Model"
        for ($i = 0; $i -lt $machineTypes.ProductName.Count; $i++) {
            if ($VerbosePreference -ne 'Continue'){
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
        Start-BitsTransferWithRetry -Source $driverUrl -Destination $driverFilePath
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
        Invoke-Process -FilePath $driverFilePath -ArgumentList $modifiedExtractCommand
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
    param (
        [Parameter(Mandatory = $true)]
        [string]$Model,
        [Parameter(Mandatory = $true)]
        [ValidateSet("x64", "x86", "ARM64")]
        [string]$WindowsArch,
        [Parameter(Mandatory = $true)]
        [int]$WindowsRelease
    )

    #CatalogPC.cab is the catalog for Windows client PCs, Catalog.cab is the catalog for Windows Server
    if ($WindowsRelease -le 11) {
        $catalogUrl = "http://downloads.dell.com/catalog/CatalogPC.cab"
        $DellCabFile = "$DriversFolder\CatalogPC.cab"
        $DellCatalogXML = "$DriversFolder\CatalogPC.XML"
    } else {
        $catalogUrl = "https://downloads.dell.com/catalog/Catalog.cab"
        $DellCabFile = "$DriversFolder\Catalog.cab"
        $DellCatalogXML = "$DriversFolder\Catalog.xml"
    }
    
    if (-not (Test-Url -Url $catalogUrl)) {
        WriteLog "Dell Catalog cab URL is not accessible: $catalogUrl Exiting"
        if ($VerbosePreference -ne 'Continue') {
            Write-Host "Dell Catalog cab URL is not accessible: $catalogUrl Exiting"
        }
        exit
    }

    if (-not (Test-Path -Path $DriversFolder)) {
        WriteLog "Creating Drivers folder: $DriversFolder"
        New-Item -Path $DriversFolder -ItemType Directory -Force | Out-Null
        WriteLog "Drivers folder created"
    }

    $DriversFolder = "$DriversFolder\$Make"
    WriteLog "Creating Dell Drivers folder: $DriversFolder"
    New-Item -Path $DriversFolder -ItemType Directory -Force | Out-Null
    WriteLog "Dell Drivers folder created"

    WriteLog "Downloading Dell Catalog cab file: $catalogUrl to $DellCabFile"
    Start-BitsTransferWithRetry -Source $catalogUrl -Destination $DellCabFile
    WriteLog "Dell Catalog cab file downloaded"

    WriteLog "Extracting Dell Catalog cab file to $DellCatalogXML"
    Invoke-Process -FilePath Expand.exe -ArgumentList "$DellCabFile $DellCatalogXML"
    WriteLog "Dell Catalog cab file extracted"

    $xmlContent = [xml](Get-Content -Path $DellCatalogXML)
    $baseLocation = "https://" + $xmlContent.manifest.baseLocation + "/"
    $latestDrivers = @{}

    $softwareComponents = $xmlContent.Manifest.SoftwareComponent | Where-Object { $_.ComponentType.value -eq "DRVR" }
    foreach ($component in $softwareComponents) {
        $models = $component.SupportedSystems.Brand.Model
        foreach ($item in $models) {
            if ($item.Display.'#cdata-section' -match $Model) {
	    	
                if ($WindowsRelease -le 11) {
                    $validOS = $component.SupportedOperatingSystems.OperatingSystem | Where-Object { $_.osArch -eq $WindowsArch }
                } elseif ($WindowsRelease -eq 2016) {
                    $validOS = $component.SupportedOperatingSystems.OperatingSystem | Where-Object { ($_.osArch -eq $WindowsArch) -and ($_.osCode -match "W14") }
                } elseif ($WindowsRelease -eq 2019) {
                    $validOS = $component.SupportedOperatingSystems.OperatingSystem | Where-Object { ($_.osArch -eq $WindowsArch) -and ($_.osCode -match "W19") }
                } elseif ($WindowsRelease -eq 2022) {
                    $validOS = $component.SupportedOperatingSystems.OperatingSystem | Where-Object { ($_.osArch -eq $WindowsArch) -and ($_.osCode -match "W22") }
                } else {
                    $validOS = $component.SupportedOperatingSystems.OperatingSystem | Where-Object { ($_.osArch -eq $WindowsArch) -and ($_.osCode -match "W22") }
                }
		
                if ($validOS) {
                    $driverPath = $component.path
                    $downloadUrl = $baseLocation + $driverPath
                    $driverFileName = [System.IO.Path]::GetFileName($driverPath)
                    $name = $component.Name.Display.'#cdata-section'
                    $name = $name -replace '[\\\/\:\*\?\"\<\>\|]', '_'
                    $name = $name -replace '[\,]', '-'
                    $category = $component.Category.Display.'#cdata-section'
                    $version = [version]$component.vendorVersion
                    $namePrefix = ($name -split '-')[0]

                    # Use hash table to store the latest driver for each category to prevent downloading older driver versions
                    if ($latestDrivers[$category]) {
                        if ($latestDrivers[$category][$namePrefix]) {
                            if ($latestDrivers[$category][$namePrefix].Version -lt $version) {
                                $latestDrivers[$category][$namePrefix] = [PSCustomObject]@{
                                    Name = $name; 
                                    DownloadUrl = $downloadUrl; 
                                    DriverFileName = $driverFileName; 
                                    Version = $version; 
                                    Category = $category 
                                }
                            }
                        }
                        else {
                            $latestDrivers[$category][$namePrefix] = [PSCustomObject]@{
                                Name = $name; 
                                DownloadUrl = $downloadUrl; 
                                DriverFileName = $driverFileName; 
                                Version = $version; 
                                Category = $category 
                            }
                        }
                    }
                    else {
                        $latestDrivers[$category] = @{}
                        $latestDrivers[$category][$namePrefix] = [PSCustomObject]@{
                            Name = $name; 
                            DownloadUrl = $downloadUrl; 
                            DriverFileName = $driverFileName; 
                            Version = $version; 
                            Category = $category 
                        }
                    }
                }
            }
        }
    }

    foreach ($category in $latestDrivers.Keys) {
        foreach ($driver in $latestDrivers[$category].Values) {
            $downloadFolder = "$DriversFolder\$Model\$($driver.Category)"
            $driverFilePath = Join-Path -Path $downloadFolder -ChildPath $driver.DriverFileName
            
            if (Test-Path -Path $driverFilePath) {
                Write-Output "Driver already downloaded: $driverFilePath skipping"
                continue
            }

            WriteLog "Downloading driver: $($driver.Name)"
            if (-not (Test-Path -Path $downloadFolder)) {
                WriteLog "Creating download folder: $downloadFolder"
                New-Item -Path $downloadFolder -ItemType Directory -Force | Out-Null
                WriteLog "Download folder created"
            }

            WriteLog "Downloading driver: $($driver.DownloadUrl) to $driverFilePath"
            try{
                Start-BitsTransferWithRetry -Source $driver.DownloadUrl -Destination $driverFilePath
                WriteLog "Driver downloaded"
            }catch{
                WriteLog "Failed to download driver: $($driver.DownloadUrl) to $driverFilePath"
                continue
            }
            

            $extractFolder = $downloadFolder + "\" + $driver.DriverFileName.TrimEnd($driver.DriverFileName[-4..-1])
            WriteLog "Creating extraction folder: $extractFolder"
            New-Item -Path $extractFolder -ItemType Directory -Force | Out-Null
            WriteLog "Extraction folder created"

            $arguments = "/s /e=`"$extractFolder`""
            WriteLog "Extracting driver: $driverFilePath to $extractFolder"
            Invoke-Process -FilePath $driverFilePath -ArgumentList $arguments
            WriteLog "Driver extracted"

            WriteLog "Deleting driver file: $driverFilePath"
            Remove-Item -Path $driverFilePath -Force
            WriteLog "Driver file deleted"
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
        "Windows ADK" = $basePattern + "Windows ADK"
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

        # Retrieve headers of the FWlink URL
        $OriginalVerbosePreference = $VerbosePreference
        $VerbosePreference = 'SilentlyContinue'
        $FWLinkRequest = Invoke-WebRequest -Uri $ADKFWLink -Method Head -MaximumRedirection 0 -ErrorAction SilentlyContinue
        $VerbosePreference = $OriginalVerbosePreference

        if ($FWLinkRequest.StatusCode -ne 302) {
            WriteLog "Failed to retrieve ADK download URL. Unexpected status code: $($FWLinkRequest.StatusCode)"
            return
        }

        # Get the ADK link redirected to by the FWlink
        $ADKUrl = $FWLinkRequest.Headers.Location
        return $ADKUrl
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
            "Windows ADK" = "adksetup.exe"
            "WinPE add-on" = "adkwinpesetup.exe"
        }[$ADKOption]

        # Select the feature based on the ADK option specified
        $feature = @{
            "Windows ADK" = "OptionId.DeploymentTools"
            "WinPE add-on" = "OptionId.WindowsPreinstallationEnvironment"
        }[$ADKOption]

        $installerLocation = Join-Path $env:TEMP $installer

        WriteLog "Downloading $ADKOption from $ADKUrl to $installerLocation"
        Start-BitsTransferWithRetry -Source $ADKUrl -Destination $installerLocation -ErrorAction Stop
        WriteLog "$ADKOption downloaded to $installerLocation"
        
        WriteLog "Installing $ADKOption with $feature enabled"
        Invoke-Process $installerLocation "/quiet /installpath ""%ProgramFiles(x86)%\Windows Kits\10"" /features $feature"
        
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
        Invoke-Process $adkBundleCachePath "/uninstall /quiet"
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
            Invoke-Process $adkBundleCachePath "/quiet /installpath ""$adkInstallPath"" /features OptionId.DeploymentTools"
            WriteLog "Windows Deployment Tools installed successfully."
        }
        else {
            throw "Failed to retrieve path to adksetup.exe to install the Windows Deployment Tools. Please manually install it."
        }
    }
    return $adkPath
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
        [string]$MediaType
    )
    WriteLog "Downloading Windows $WindowsRelease ESD file"
    WriteLog "Windows Architecture: $WindowsArch"
    WriteLog "Windows Language: $WindowsLang"
    WriteLog "Windows Media Type: $MediaType"

    # Select cab file URL based on Windows Release
    $cabFileUrl = if ($WindowsRelease -eq 10) {
        'https://go.microsoft.com/fwlink/?LinkId=841361'
    }
    elseif ($WindowsRelease -eq 11) {
        'https://go.microsoft.com/fwlink/?LinkId=2156292'
    } else {
        throw "Downloading Windows Server is not supported. Please use the -ISOPath parameter to specify the path to the Windows Server ISO file."
    }

    # Download cab file
    WriteLog "Downloading Cab file"
    $cabFilePath = Join-Path $PSScriptRoot "tempCabFile.cab"
    $OriginalVerbosePreference = $VerbosePreference
    $VerbosePreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $cabFileUrl -OutFile $cabFilePath -Headers $Headers -UserAgent $UserAgent
    $VerbosePreference = $OriginalVerbosePreference
    WriteLog "Download succeeded"

    # Extract XML from cab file
    WriteLog "Extracting Products XML from cab"
    $xmlFilePath = Join-Path $PSScriptRoot "products.xml"
    Invoke-Process Expand "-F:*.xml $cabFilePath $xmlFilePath"
    WriteLog "Products XML extracted"

    # Load XML content
    [xml]$xmlContent = Get-Content -Path $xmlFilePath

    # Define the client type to look for in the FilePath
    $clientType = if ($MediaType -eq 'consumer') { 'CLIENTCONSUMER' } else { 'CLIENTBUSINESS' }

    # Find FilePath values based on WindowsArch, WindowsLang, and MediaType
    foreach ($file in $xmlContent.MCT.Catalogs.Catalog.PublishedMedia.Files.File) {
        if ($file.Architecture -eq $WindowsArch -and $file.LanguageCode -eq $WindowsLang -and $file.FilePath -like "*$clientType*") {
            $esdFilePath = Join-Path $PSScriptRoot (Split-Path $file.FilePath -Leaf)
            #Download if ESD file doesn't already exist
            If (-not (Test-Path $esdFilePath)) {
                #Required to fix slow downloads
                $ProgressPreference = 'SilentlyContinue'
                WriteLog "Downloading $($file.filePath) to $esdFIlePath"
                $OriginalVerbosePreference = $VerbosePreference
                $VerbosePreference = 'SilentlyContinue'
                Invoke-WebRequest -Uri $file.FilePath -OutFile $esdFilePath -Headers $Headers -UserAgent $UserAgent
                $VerbosePreference = $OriginalVerbosePreference
                WriteLog "Download succeeded"
                #Set back to show progress
                $ProgressPreference = 'Continue'
                WriteLog "Cleanup cab and xml file"
                Remove-Item -Path $cabFilePath -Force
                Remove-Item -Path $xmlFilePath -Force
                WriteLog "Cleanup done"
            }
            return $esdFilePath
        }
    }
}



function Get-ODTURL {

    # [String]$MSWebPage = Invoke-RestMethod 'https://www.microsoft.com/en-us/download/confirmation.aspx?id=49117'
    [String]$MSWebPage = Invoke-RestMethod 'https://www.microsoft.com/en-us/download/confirmation.aspx?id=49117' -Headers $Headers -UserAgent $UserAgent
  
    $MSWebPage | ForEach-Object {
        if ($_ -match 'url=(https://.*officedeploymenttool.*\.exe)') {
            $matches[1]
        }
    }
}

function Get-Office {
    #Download ODT
    $ODTUrl = Get-ODTURL
    $ODTInstallFile = "$env:TEMP\odtsetup.exe"
    WriteLog "Downloading Office Deployment Toolkit from $ODTUrl to $ODTInstallFile"
    $OriginalVerbosePreference = $VerbosePreference
    $VerbosePreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $ODTUrl -OutFile $ODTInstallFile -Headers $Headers -UserAgent $UserAgent
    $VerbosePreference = $OriginalVerbosePreference

    # Extract ODT
    WriteLog "Extracting ODT to $OfficePath"
    Invoke-Process $ODTInstallFile "/extract:$OfficePath /quiet"

    # Run setup.exe with config.xml and modify xml file to download to $OfficePath
    $ConfigXml = "$OfficePath\DownloadFFU.xml"
    $xmlContent = [xml](Get-Content $ConfigXml)
    $xmlContent.Configuration.Add.SourcePath = $OfficePath
    $xmlContent.Save($ConfigXml)
    WriteLog "Downloading M365 Apps/Office to $OfficePath"
    Invoke-Process $OfficePath\setup.exe "/download $ConfigXml"

    WriteLog "Cleaning up ODT default config files and checking InstallAppsandSysprep.cmd file for proper command line"
    #Clean up default configuration files
    Remove-Item -Path "$OfficePath\configuration*" -Force

    #Read the contents of the InstallAppsandSysprep.cmd file
    $content = Get-Content -Path "$AppsPath\InstallAppsandSysprep.cmd"
        
    #Update the InstallAppsandSysprep.cmd file with the Office install command
    $officeCommand = "d:\Office\setup.exe /configure d:\Office\DeployFFU.xml"

    # Check if Office command is not commented out or missing and fix it if it is
    if ($content[3] -ne $officeCommand) {
        $content[3] = $officeCommand

        # Write the modified content back to the file
        Set-Content -Path "$AppsPath\InstallAppsandSysprep.cmd" -Value $content
    }
}

function Install-WinGet {
    param (
        [string]$Architecture
    )
    $packages = @(
        @{Name = "VCLibs"; Url = "https://aka.ms/Microsoft.VCLibs.$Architecture.14.00.Desktop.appx"; File = "Microsoft.VCLibs.$Architecture.14.00.Desktop.appx"},
        @{Name = "UIXaml"; Url = "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.$Architecture.appx"; File = "Microsoft.UI.Xaml.2.8.$Architecture.appx"},
        @{Name = "WinGet"; Url = "https://aka.ms/getwinget"; File = "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"}
    )
    foreach ($package in $packages) {
        $destination = Join-Path -Path $env:TEMP -ChildPath $package.File
        WriteLog "Downloading $($package.Name) from $($package.Url) to $destination"
        Start-BitsTransferWithRetry -Source $package.Url -Destination $destination
        WriteLog "Installing $($package.Name)..."
        # Don't show progress bar for Add-AppxPackage - there's a weird issue where the progress stays on the screen after the apps are installed
        $ProgressPreference = 'SilentlyContinue'
        Add-AppxPackage -Path $destination -ErrorAction SilentlyContinue
        # Set progress preference back to default
        $ProgressPreference = 'Continue'
        WriteLog "Removing $($package.Name)..."
        Remove-Item -Path $destination -Force -ErrorAction SilentlyContinue
    }
    WriteLog "WinGet installation complete."
}
# function Confirm-WinGetInstallation {
#     WriteLog 'Checking if WinGet is installed...'
#     $wingetPath = "$env:LOCALAPPDATA\Microsoft\WindowsApps\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\winget.exe"
#     $minVersion = [version]"1.8.1911"
#     if (-not (Test-Path -Path $wingetPath -PathType Leaf)) {
#         WriteLog "WinGet is not installed. Downloading WinGet..."
#         Install-WinGet -Architecture $WindowsArch
#     } 
#     if (-not (Get-Command -Name winget -ErrorAction SilentlyContinue)) {
#         WriteLog "WinGet not found. Downloading WinGet..."
#         Install-WinGet -Architecture $WindowsArch
#     }
#     $wingetVersion = & winget.exe --version
#     WriteLog "Installed version of WinGet: $wingetVersion"
#     if ($wingetVersion -match 'v?(\d+\.\d+\.\d+)' -and [version]$matches[1] -lt $minVersion) {
#         WriteLog "The installed version of WinGet $($matches[1]) does not support downloading MSStore apps. Downloading the latest version of WinGet..."
#         Install-WinGet -Architecture $WindowsArch
#     }

#     # Check if Winget PowerShell module version 1.8.1911 or later is installed
#     $wingetModule = Get-InstalledModule -Name Microsoft.Winget.Client -ErrorAction SilentlyContinue
#     if ($wingetModule.Version -lt $minVersion -or -not $wingetModule) {
#         WriteLog 'Microsoft.Winget.Client module is not installed or is an older version. Installing the latest version...'
#         #Check if PSGallery is a trusted repository
#         $PSGalleryTrust = (Get-PSRepository -Name 'PSGallery').InstallationPolicy
#         if($PSGalleryTrust -eq 'Untrusted'){
#             WriteLog 'Temporarily setting PSGallery as a trusted repository...'
#             Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
#         }
#         Install-Module -Name Microsoft.Winget.Client -Force -Repository 'PSGallery'
#         if($PSGalleryTrust -eq 'Untrusted'){
#             WriteLog 'Setting PSGallery back to untrusted repository...'
#             Set-PSRepository -Name 'PSGallery' -InstallationPolicy Untrusted
#             WriteLog 'Done'
#         }
#     }
# }

function Confirm-WinGetInstallation {
    WriteLog 'Checking if WinGet is installed...'
    $minVersion = [version]"1.8.1911"
    # Check if Winget PowerShell module version 1.8.1911 or later is installed
    $wingetModule = Get-InstalledModule -Name Microsoft.Winget.Client -ErrorAction SilentlyContinue
    if ($wingetModule.Version -lt $minVersion -or -not $wingetModule) {
        WriteLog 'Microsoft.Winget.Client module is not installed or is an older version. Installing the latest version...'
        #Check if PSGallery is a trusted repository
        $PSGalleryTrust = (Get-PSRepository -Name 'PSGallery').InstallationPolicy
        if($PSGalleryTrust -eq 'Untrusted'){
            WriteLog 'Temporarily setting PSGallery as a trusted repository...'
            Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
        }
        Install-Module -Name Microsoft.Winget.Client -Force -Repository 'PSGallery'
        if($PSGalleryTrust -eq 'Untrusted'){
            WriteLog 'Setting PSGallery back to untrusted repository...'
            Set-PSRepository -Name 'PSGallery' -InstallationPolicy Untrusted
            WriteLog 'Done'
        }
    }
    $wingetVersion = Get-WinGetVersion
    if (-not $wingetVersion) {
        WriteLog "WinGet is not installed. Installing WinGet..."
        Install-WinGet -Architecture $WindowsArch
    }
    if (($wingetVersion -match 'v?(\d+\.\d+\.\d+)' -and [version]$matches[1] -lt $minVersion)) {
        WriteLog "The installed version of WinGet $($matches[1]) does not support downloading MSStore apps. Installing the latest version of WinGet..."
        Install-WinGet -Architecture $WindowsArch
    }
}

function Add-Win32SilentInstallCommand {
    param (
        [string]$AppFolder,
        [string]$AppFolderPath
    )
    $appName = $AppFolder
    $installerPath = Get-ChildItem -Path "$appFolderPath\*" -Include "*.exe", "*.msi" -File -ErrorAction Stop
    if (-not $installerPath) {
        WriteLog "No win32 app installers were found. Skipping the inclusion of $AppFolder"
        Remove-Item -Path $AppFolderPath -Recurse -Force
        return $false
    }
    $yamlFile = Get-ChildItem -Path "$appFolderPath\*" -Include "*.yaml" -File -ErrorAction Stop
    $yamlContent = Get-Content -Path $yamlFile -Raw
    $silentInstallSwitch = [regex]::Match($yamlContent, 'Silent:\s*(.+)').Groups[1].Value.Replace("'", "").Trim()
    if (-not $silentInstallSwitch) {
        WriteLog "Silent install switch for $appName could not be found. Skipping the inclusion of $appName."
        Remove-Item -Path $appFolderPath -Recurse -Force
        return $false
    }
    $installer = Split-Path -Path $installerPath -Leaf
    if ($installerPath.Extension -eq ".exe") {
        $silentInstallCommand = "`"D:\win32\$appFolder\$installer`" $silentInstallSwitch"
    } 
    elseif ($installerPath.Extension -eq ".msi") {
        $silentInstallCommand = "msiexec /i `"D:\win32\$appFolder\$installer`" $silentInstallSwitch"
    }
    $cmdFile = "$AppsPath\InstallAppsandSysprep.cmd"
    $cmdContent = Get-Content -Path $cmdFile
    $UpdatedcmdContent = $CmdContent -replace '^(REM Winget Win32 Apps)', ("REM Winget Win32 Apps`r`nREM Win32 $($AppName)`r`n$($silentInstallCommand.Trim())")
    WriteLog "Writing silent install command for $appName to InstallAppsandSysprep.cmd"
    Set-Content -Path $cmdFile -Value $UpdatedcmdContent
}

function Set-InstallStoreAppsFlag {
    $cmdPath = "$AppsPath\InstallAppsandSysprep.cmd"
    $cmdContent = Get-Content -Path $cmdPath
    if ($cmdContent -match 'set "INSTALL_STOREAPPS=false"') {
        WriteLog "Setting INSTALL_STOREAPPS flag to true in InstallAppsandSysprep.cmd file."
        $updatedcmdContent = $cmdContent -replace 'set "INSTALL_STOREAPPS=false"', 'set "INSTALL_STOREAPPS=true"'
        Set-Content -Path "$AppsPath\InstallAppsandSysprep.cmd" -Value $updatedcmdContent
    }
}

# function Get-WinGetApp {
#     param (
#         [string]$WinGetAppName,
#         [string]$WinGetAppId
#     )
#     $wingetSearchResult = & winget.exe search --id "$WinGetAppId" --exact --accept-source-agreements --source winget
#     if ($wingetSearchResult -contains "No package found matching input criteria.") {
#         if ($VerbosePreference -ne 'Continue'){
#             Write-Error "$WinGetAppName not found in WinGet repository. Skipping download."
#             Write-Error "Check the AppList.json file and make sure the AppID is correct."
#             Write-Error "If OS language is not English, winget download may fail. We hope to have this addressed in a future release."
#         }
#         WriteLog "$WinGetAppName not found in WinGet repository. Exiting."
#         WriteLog "Check the AppList.json file and make sure the AppID is correct."
#         WriteLog "If OS language is not English, winget download may fail. We hope to have this addressed in a future release."
#         Exit 1
#     }
#     $appFolderPath = Join-Path -Path "$AppsPath\Win32" -ChildPath $WinGetAppName
#     WriteLog "Creating $appFolderPath"
#     New-Item -Path $appFolderPath -ItemType Directory -Force | Out-Null
#     WriteLog "Downloading $WinGetAppName to $appFolderPath"
#     $downloadParams = @(
#         "download", 
#         "--id", "$WinGetAppId",
#         "--exact",
#         "--download-directory", "$appFolderPath",
#         "--accept-package-agreements",
#         "--accept-source-agreements",
#         "--source", "winget",
#         "--scope", "machine",
#         "--architecture", "$WindowsArch"
#     )
#     WriteLog "winget command: winget.exe $downloadParams"
#     $wingetDownloadResult = & winget.exe @downloadParams | Out-String
#     if ($wingetDownloadResult -match "No applicable installer found") {
#         WriteLog "No installer found for $WindowsArch architecture. Attempting to download without specifying architecture..."
#         $downloadParams = $downloadParams | Where-Object { $_ -notmatch "--architecture" -and $_ -notmatch "$WindowsArch" }
#         $wingetDownloadResult = & winget.exe @downloadParams | Out-String
#         if ($wingetDownloadResult -match "Installer downloaded") {
#             WriteLog "Downloaded $WinGetAppName without specifying architecture."
#         }
#     }
#     if ($wingetDownloadResult -notmatch "Installer downloaded") {
#         WriteLog "No installer found for $WinGetAppName. Skipping download."
#         Remove-Item -Path $appFolderPath -Recurse -Force
#     }
#     WriteLog "$WinGetAppName downloaded to $appFolderPath"
#     $installerPath = Get-ChildItem -Path "$appFolderPath\*" -Exclude "*.yaml", "*.xml" -File -ErrorAction Stop
#     $uwpExtensions = @(".appx", ".appxbundle", ".msix", ".msixbundle")
#     if ($uwpExtensions -contains $installerPath.Extension) {
#         $NewAppPath = "$AppsPath\MSStore\$WinGetAppName"
#         Writelog "$WinGetAppName is a UWP app. Moving to $NewAppPath"
#         WriteLog "Creating $NewAppPath"
#         New-Item -Path "$AppsPath\MSStore\$WinGetAppName" -ItemType Directory -Force | Out-Null
#         WriteLog "Moving $WinGetAppName to $NewAppPath"
#         Move-Item -Path "$appFolderPath\*" -Destination "$AppsPath\MSStore\$WinGetAppName" -Force
#         WriteLog "Removing $appFolderPath"
#         Remove-Item -Path $appFolderPath -Force
#         WriteLog "$WinGetAppName moved to $NewAppPath"
#         Set-InstallStoreAppsFlag
#     }
#     else {
#         Add-Win32SilentInstallCommand -AppFolder $WinGetAppName -AppFolderPath $appFolderPath
#     }
# }
function Get-WinGetApp {
    param (
        [string]$WinGetAppName,
        [string]$WinGetAppId
    )
    $Source = 'winget'
    $wingetSearchResult = Find-WinGetPackage -id $WinGetAppId -MatchOption Equals -Source $Source
    if (-not $wingetSearchResult) {
        if ($VerbosePreference -ne 'Continue'){
            Write-Error "$WinGetAppName not found in WinGet repository. Exiting."
            Write-Error "Check the AppList.json file and make sure the AppID is correct."
        }
        WriteLog "$WinGetAppName not found in WinGet repository. Exiting."
        WriteLog "Check the AppList.json file and make sure the AppID is correct."
        Exit 1
    }
    $appFolderPath = Join-Path -Path "$AppsPath\Win32" -ChildPath $WinGetAppName
    WriteLog "Creating $appFolderPath"
    New-Item -Path $appFolderPath -ItemType Directory -Force | Out-Null
    WriteLog "Downloading $WinGetAppName to $appFolderPath"

    WriteLog "WinGet command: Export-WinGetPackage -id $WinGetAppId -DownloadDirectory $appFolderPath -Architecture $WindowsArch -Source $Source"
    $wingetDownloadResult = Export-WinGetPackage -id $WinGetAppId -DownloadDirectory $appFolderPath -Architecture $WindowsArch -Source $Source
    if ($wingetDownloadResult.status -eq 'NoApplicableInstallers') {
        # If no applicable installer is found, try downloading without specifying architecture
        WriteLog "No installer found for $WindowsArch architecture. Attempting to download without specifying architecture..."
        $wingetDownloadResult = Export-WinGetPackage -id $WinGetAppId -DownloadDirectory $appFolderPath -Source $Source
        if ($wingetDownloadResult.status -eq 'Ok') {
            WriteLog "Downloaded $WinGetAppName without specifying architecture."
        }
        else{
            WriteLog "No installer found for $WinGetAppName. Exiting."
            Remove-Item -Path $appFolderPath -Recurse -Force
            Exit 1
        }
    }
    WriteLog "$WinGetAppName downloaded to $appFolderPath"
    $installerPath = Get-ChildItem -Path "$appFolderPath\*" -Exclude "*.yaml", "*.xml" -File -ErrorAction Stop
    $uwpExtensions = @(".appx", ".appxbundle", ".msix", ".msixbundle")
    if ($uwpExtensions -contains $installerPath.Extension) {
        $NewAppPath = "$AppsPath\MSStore\$WinGetAppName"
        Writelog "$WinGetAppName is a UWP app. Moving to $NewAppPath"
        WriteLog "Creating $NewAppPath"
        New-Item -Path "$AppsPath\MSStore\$WinGetAppName" -ItemType Directory -Force | Out-Null
        WriteLog "Moving $WinGetAppName to $NewAppPath"
        Move-Item -Path "$appFolderPath\*" -Destination "$AppsPath\MSStore\$WinGetAppName" -Force
        WriteLog "Removing $appFolderPath"
        Remove-Item -Path $appFolderPath -Force
        WriteLog "$WinGetAppName moved to $NewAppPath"
        Set-InstallStoreAppsFlag
    }
    else {
        Add-Win32SilentInstallCommand -AppFolder $WinGetAppName -AppFolderPath $appFolderPath
    }
}

# function Get-StoreApp {
#     param (
#         [string]$StoreAppName,
#         [string]$StoreAppId
#     )
#     $wingetSearchResult = & winget.exe search "$StoreAppId" --accept-source-agreements --source msstore
#     if ($wingetSearchResult -contains "No package found matching input criteria.") {
#         WriteLog "$StoreAppName not found in WinGet repository. Skipping download."
#         return
#     }
#     WriteLog "Checking if $StoreAppName is a win32 app..."
#     $appIsWin32 = $StoreAppId.StartsWith("XP")
#     if ($appIsWin32) {
#         WriteLog "$StoreAppName is a win32 app. Adding to $AppsPath\win32 folder"
#         $appFolderPath = Join-Path -Path "$AppsPath\win32" -ChildPath $StoreAppName
#     }
#     else {
#         WriteLog "$StoreAppName is not a win32 app."
#         $appFolderPath = Join-Path -Path "$AppsPath\MSStore" -ChildPath $StoreAppName
#     }
#     New-Item -Path $appFolderPath -ItemType Directory -Force | Out-Null
#     WriteLog "Downloading $StoreAppName for $WindowsArch architecture..."
#     $downloadParams = @(
#         "download", "$StoreAppId",
#         "--download-directory", "$appFolderPath",
#         "--accept-package-agreements",
#         "--accept-source-agreements",
#         "--source", "msstore",
#         "--scope", "machine",
#         "--architecture", "$WindowsArch"
#     )
#     WriteLog 'MSStore app downloads require authentication with an Entra ID account. You may be prompted twice for credentials, once for the app and another for the license file.'
#     WriteLog "Attempting to download $StoreAppName and dependencies for $WindowsArch architecture..."
#     $wingetDownloadResult = & winget.exe @downloadParams | Out-String
#     # For some apps, specifying the architecture leads to no results found for the app. In those cases, the command will be run without the architecture parameter.
#     if ($wingetDownloadResult -match "No applicable installer found") {
#         WriteLog "No installer found for $WindowsArch architecture. Attempting to download without specifying architecture..."
#         $downloadParams = $downloadParams | Where-Object { $_ -notmatch "--architecture" -and $_ -notmatch "$WindowsArch" }
#         $wingetDownloadResult = & winget.exe @downloadParams | Out-String
#         if ($wingetDownloadResult -match "Microsoft Store package download completed") {
#             WriteLog "Downloaded $StoreAppName without specifying architecture."
#         }
#     }
#     if ($wingetDownloadResult -notmatch "Installer downloaded|Microsoft Store package download completed") {
#         WriteLog "Download not supported for $StoreAppName. Skipping download."
#         Remove-Item -Path $appFolderPath -Recurse -Force
#         return
#     }
#     if ($appIsWin32) {
#         Add-Win32SilentInstallCommand -AppFolder $StoreAppName -AppFolderPath $appFolderPath
#     }
#     Set-InstallStoreAppsFlag
#     # If $WindowsArch -eq 'ARM64', remove all dependency files that are not ARM64
#     if ($WindowsArch -eq 'ARM64') {
#         WriteLog 'Windows architecture is ARM64. Removing dependencies that are not ARM64.'
#         $dependencies = Get-ChildItem -Path "$appFolderPath\Dependencies" -ErrorAction SilentlyContinue
#         if ($dependencies) {
#             foreach ($dependency in $dependencies) {
#                 if ($dependency.Name -notmatch 'ARM64') {
#                     WriteLog "Removing dependency file $($dependency.FullName)"
#                     Remove-Item -Path $dependency.FullName -Recurse -Force
#                 }
#             }
#         }
#     }
#     WriteLog "$StoreAppName has completed downloading. Identifying the latest version of $StoreAppName."
#     $packages = Get-ChildItem -Path "$appFolderPath\*" -Exclude "Dependencies\*", "*.xml", "*.yaml" -File -ErrorAction Stop
#     # WinGet downloads multiple versions of certain store apps. The latest version of the package will be determined based on the date of the file signature.
#     $latestPackage = $packages | Sort-Object { (Get-AuthenticodeSignature $_.FullName).SignerCertificate.NotBefore } -Descending | Select-Object -First 1
#     # Removing all packages that are not the latest version
#     WriteLog "Latest version of $StoreAppName has been identified as $latestPackage. Removing old versions of $StoreAppName that may have downloaded."
#     foreach ($package in $packages) {
#         if ($package.FullName -ne $latestPackage) {
#             try {
#                 WriteLog "Removing $($package.FullName)"
#                 Remove-Item -Path $package.FullName -Force
#             }
#             catch {
#                 WriteLog "Failed to delete: $($package.FullName) - $_"
#                 throw $_
#             }
#         }
#     }
# }
function Get-StoreApp {
    param (
        [string]$StoreAppName,
        [string]$StoreAppId
    )
    $Source = 'msstore'
    $wingetSearchResult = Find-WinGetPackage -id $StoreAppId -MatchOption Equals -Source $Source
    if (-not $wingetSearchResult) {
        if ($VerbosePreference -ne 'Continue'){
            Write-Error "$WinGetAppName not found in WinGet repository. Exiting."
            Write-Error "Check the AppList.json file and make sure the AppID is correct."
        }
        WriteLog "$WinGetAppName not found in WinGet repository. Exiting."
        WriteLog "Check the AppList.json file and make sure the AppID is correct."
        Exit 1
    }
    WriteLog "Checking if $StoreAppName is a win32 app..."
    $appIsWin32 = $StoreAppId.StartsWith("XP")
    if ($appIsWin32) {
        WriteLog "$StoreAppName is a win32 app. Adding to $AppsPath\win32 folder"
        $appFolderPath = Join-Path -Path "$AppsPath\win32" -ChildPath $StoreAppName
    }
    else {
        WriteLog "$StoreAppName is not a win32 app."
        $appFolderPath = Join-Path -Path "$AppsPath\MSStore" -ChildPath $StoreAppName
    }
    New-Item -Path $appFolderPath -ItemType Directory -Force | Out-Null
    WriteLog "Downloading $StoreAppName for $WindowsArch architecture..."
    WriteLog 'MSStore app downloads require authentication with an Entra ID account. You may be prompted twice for credentials, once for the app and another for the license file.'
    WriteLog "Attempting to download $StoreAppName and dependencies for $WindowsArch architecture..."
    WriteLog "WinGet command: Export-WinGetPackage -id $StoreAppId -DownloadDirectory $appFolderPath -Architecture $WindowsArch -Source $Source"
    $wingetDownloadResult = Export-WinGetPackage -id $StoreAppId -DownloadDirectory $appFolderPath -Architecture $WindowsArch -Source $Source
    if ($wingetDownloadResult.status -eq 'NoApplicableInstallerFound') {
        # If no applicable installer is found, try downloading without specifying architecture
        WriteLog "No installer found for $WindowsArch architecture. Attempting to download without specifying architecture..."
        $wingetDownloadResult = Export-WinGetPackage -id $StoreAppId -DownloadDirectory $appFolderPath -Source $Source
        if ($wingetDownloadResult.status -eq 'Ok') {
            WriteLog "Downloaded $WinGetAppName without specifying architecture."
        }
        else{
            WriteLog "No installer found for $WinGetAppName. Exiting"
            Remove-Item -Path $appFolderPath -Recurse -Force
            Exit 1
        }
    }
    if ($appIsWin32) {
        Add-Win32SilentInstallCommand -AppFolder $StoreAppName -AppFolderPath $appFolderPath
    }
    Set-InstallStoreAppsFlag
    # If $WindowsArch -eq 'ARM64', remove all dependency files that are not ARM64
    if ($WindowsArch -eq 'ARM64') {
        WriteLog 'Windows architecture is ARM64. Removing dependencies that are not ARM64.'
        $dependencies = Get-ChildItem -Path "$appFolderPath\Dependencies" -ErrorAction SilentlyContinue
        if ($dependencies) {
            foreach ($dependency in $dependencies) {
                if ($dependency.Name -notmatch 'ARM64') {
                    WriteLog "Removing dependency file $($dependency.FullName)"
                    Remove-Item -Path $dependency.FullName -Recurse -Force
                }
            }
        }
    }
    WriteLog "$StoreAppName has completed downloading. Identifying the latest version of $StoreAppName."
    $packages = Get-ChildItem -Path "$appFolderPath\*" -Exclude "Dependencies\*", "*.xml", "*.yaml" -File -ErrorAction Stop
    # WinGet downloads multiple versions of certain store apps. The latest version of the package will be determined based on the date of the file signature.
    $latestPackage = $packages | Sort-Object { (Get-AuthenticodeSignature $_.FullName).SignerCertificate.NotBefore } -Descending | Select-Object -First 1
    # Removing all packages that are not the latest version
    WriteLog "Latest version of $StoreAppName has been identified as $latestPackage. Removing old versions of $StoreAppName that may have downloaded."
    foreach ($package in $packages) {
        if ($package.FullName -ne $latestPackage) {
            try {
                WriteLog "Removing $($package.FullName)"
                Remove-Item -Path $package.FullName -Force
            }
            catch {
                WriteLog "Failed to delete: $($package.FullName) - $_"
                throw $_
            }
        }
    }
}

function Get-Apps {
    param (
        [string]$AppList
    )
    $apps = Get-Content -Path $AppList -Raw | ConvertFrom-Json
    if (-not $apps) {
        WriteLog "No apps were specified in AppList.json file."
        return
    }
    $wingetApps = $apps.apps | Where-Object { $_.source -eq "winget" }
    # List each Winget app in the AppList.json file
    if ($wingetApps) {
        WriteLog 'Winget apps to be installed:'
        foreach ($wingetapp in $wingetApps){
            WriteLog "$($wingetapp.Name)"
        }
    }
    $StoreApps = $apps.apps | Where-Object { $_.source -eq "msstore" }
    # List each Store app in the AppList.json file
    if ($StoreApps) {
        WriteLog 'Store apps to be installed:'
        foreach ($StoreApp in $StoreApps){
            WriteLog "$($StoreApp.Name)"
        }
    }
    Confirm-WinGetInstallation
    $win32Folder = Join-Path -Path $AppsPath -ChildPath "Win32"
    $storeAppsFolder = Join-Path -Path $AppsPath -ChildPath "MSStore"
    if ($wingetApps) {
        if (-not (Test-Path -Path $win32Folder -PathType Container)) {
            WriteLog "Creating folder for Winget Win32 apps: $win32Folder"
            New-Item -Path $win32Folder -ItemType Directory -Force | Out-Null
            WriteLog "Folder created successfully."
        }
        foreach ($wingetApp in $wingetApps) {
            try {
                Get-WinGetApp -WinGetAppName $wingetApp.Name -WinGetAppId $wingetApp.Id
            }
            catch {
                WriteLog "Error occurred while processing $wingetApp : $_"
                throw $_
            }
        }
    }
    if ($storeApps) {
        if (-not (Test-Path -Path $storeAppsFolder -PathType Container)) {
            New-Item -Path $storeAppsFolder -ItemType Directory -Force | Out-Null
        }
        foreach ($storeApp in $storeApps) {
            try {
                Get-StoreApp -StoreAppName $storeApp.Name -StoreAppId $storeApp.Id
            }
            catch {
                WriteLog "Error occurred while processing $storeApp : $_"
                throw $_
            }
        }
    }
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
    $kbids = $results.InputFields |
    Where-Object { $_.type -eq 'Button' -and $_.Value -eq 'Download' } |
    Select-Object -ExpandProperty  ID

    Write-Verbose -Message "$kbids"

    if (-not $kbids) {
        Write-Warning -Message "No results found for $Name"
        return
    }

    $guids = $results.Links |
    Where-Object ID -match '_link' |
    Where-Object { $_.OuterHTML -match ( "(?=.*" + ( $Filter -join ")(?=.*" ) + ")" ) } |
    ForEach-Object { $_.id.replace('_link', '') } |
    Where-Object { $_ -in $kbids }

    if (-not $guids) {
        Write-Warning -Message "No file found for $Name"
        return
    }

    foreach ($guid in $guids) {
        Write-Verbose -Message "Downloading information for $guid"
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
function Get-LatestWindowsKB {
    param (
        [Parameter(Mandatory)]
        [ValidateSet(10, 11, 2016, 2019, 2022, 2025)]
        [int]$WindowsRelease,
        [Parameter(Mandatory)]
        [string]$WindowsVersion
    )
        
    # Define the URL of the update history page based on the Windows release
    if ($WindowsRelease -eq 11) {
        $updateHistoryUrl = 'https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information'
    }
    elseif ($WindowsRelease -eq 10) {
        $updateHistoryUrl = 'https://learn.microsoft.com/en-us/windows/release-health/release-information'
    } else {
        $updateHistoryUrl = 'https://learn.microsoft.com/en-us/windows/release-health/windows-server-release-info'
    }
        
    # Use Invoke-WebRequest to fetch the content of the page
    $OriginalVerbosePreference = $VerbosePreference
    $VerbosePreference = 'SilentlyContinue'
    $response = Invoke-WebRequest -Uri $updateHistoryUrl -Headers $Headers -UserAgent $UserAgent
    $VerbosePreference = $OriginalVerbosePreference
        
    # Use a regular expression to find the KB article number
    if ($WindowsRelease -le 11) {
        $kbArticleRegex = "(?:Version $WindowsRelease \(OS build d+\)(?!(KB)).)*?KB\d+"
    } else {
        $kbArticleRegex = "(?:Windows Server $WindowsRelease \(OS build d+\)(?!(KB)).)*?KB\d+"
    }
    $kbArticle = [regex]::Match($response.Content, $kbArticleRegex).Value
        
    return $kbArticle
}

function Find-CachedKB {
    param(
        [string]$Link,
        [string]$Path 
    )

    WriteLog "Searching for cached download of $Link"
    $fileHash = ($Link | Select-String -Pattern "(?<=^[^_]*_).*(?=\..*$)").Matches[0].Value
    $file = [System.IO.FileInfo]::new((Join-Path -Path $KBCachePath -ChildPath ($Link -split '/')[-1]))

    if ($file.Exists) {
        if ((Get-FileHash -Path $file.FullName -Algorithm SHA1).Hash -eq $fileHash) {
            WriteLog "Found cached download of $Link as $($file.FullName)"
            Robocopy.exe $($KBCachePath) $($Path) $file.Name /E /R:5 /W:5 /J /Copy:DAT | ForEach-Object { }
            return $file.Name
        }
    }

    return ""
}

function Invoke-KBDownload {
    param (
        [string]$Link,
        [string]$WindowsArch,
        [string]$Path
    )

    if ($AllowUpdateCaching) 
        $fileName = Find-CachedKB -Link $Link -Path $Path
        if (![string]::IsNullOrEmpty($fileName)) {
            Writelog "Found $Link for $WindowsArch in $KBCachePath"
            Writelog "Returning $fileName"
            return $fileName
        }
    }
    Writelog "Downloading $Link for $WindowsArch to $Path"
    Start-BitsTransferWithRetry -Source $link -Destination $Path
    $fileName = ($link -split '/')[-1]
    if ($AllowUpdateCaching) {
        WriteLog "Caching $fileName for later use"
        Robocopy.exe $($Path) $($KBCachePath) $fileName /E /R:5 /W:5 /J /Copy:DAT | ForEach-Object { }
    }
    Writelog "Returning $fileName"
    return $fileName
}

function Save-KB {
    [CmdletBinding()]
    param(
        [string[]]$Name,
        [string]$Path
    )

    if ($WindowsArch -eq 'x64') {
        [array]$WindowsArch = @("x64", "amd64")
    }
    foreach ($kb in $name) {
        $links = Get-KBLink -Name $kb
        foreach ($link in $links) {
            if (!($link -match 'x64' -or $link -match 'amd64' -or $link -match 'x86' -or $link -match 'arm64')) {
                WriteLog "No architecture found in $link, assume this is for all architectures"
                #FIX: 3/22/2024 - the SecurityHealthSetup fix was updated and now includes two files (one is x64 and the other is arm64)
                #Unfortunately there is no easy way to determine the architecture from the file name
                #There is a support doc that include links to download, but it's out of date (n-1)
                #https://support.microsoft.com/en-us/topic/windows-security-update-a6ac7d2e-b1bf-44c0-a028-41720a242da3
                #These files don't change that often, so will check the link above to see when it updates and may use that
                #For now this is hard-coded for these specific file names
                if ($link -match 'security') {
                    #Make sure we're getting the correct architecture for the Security Health Setup update
                    WriteLog "Link: $link matches security"
                    if ($WindowsArch -eq 'x64') {
                        if ($link -match 'securityhealthsetup_e1') {
                            $fileName = Invoke-KBDownload -Link $link -WindowsArch $WindowsArch -Path $Path
                            break
                        }
                    }
                    if ($WindowsArch -eq 'arm64') {
                        if ($link -match 'securityhealthsetup_25') {
                            $fileName = Invoke-KBDownload -Link $link -WindowsArch $WindowsArch -Path $Path
                            break
                        }
                    }
                }
            }

            if ($link -match 'x64' -or $link -match 'amd64') {
                if($WindowsArch -is [array]) {
                    if ($link -match $WindowsArch[0] -or $link -match $WindowsArch[1]) {
                        $fileName = Invoke-KBDownload -Link $link -WindowsArch $WindowsArch -Path $Path
                        break
                    }
                }
                
            }
            if ($link -match 'arm64') {
                if ($WindowsArch -eq 'arm64') {
        	    $fileName = Invoke-KBDownload -Link $link -WindowsArch $WindowsArch -Path $Path
                    break
                }
            }                
        }
    }
    return $fileName
}

function New-AppsISO {
    #Create Apps ISO file
    $OSCDIMG = "$adkpath`Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
    #Start-Process -FilePath $OSCDIMG -ArgumentList "-n -m -d $Appspath $AppsISO" -wait
    Invoke-Process $OSCDIMG "-n -m -d $Appspath $AppsISO"
    
    #Remove the Office Download and ODT
    if ($InstallOffice) {
        $ODTPath = "$AppsPath\Office"
        $OfficeDownloadPath = "$ODTPath\Office"
        WriteLog 'Cleaning up Office and ODT download'
        Remove-Item -Path $OfficeDownloadPath -Recurse -Force
        Remove-Item -Path "$ODTPath\setup.exe"
    }    
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


function Get-WimIndex {
    param (
        [Parameter(Mandatory = $true)]
        [string]$WindowsSKU
    )
    WriteLog "Getting WIM Index for Windows SKU: $WindowsSKU"

    If ($ISOPath) {
        $wimindex = switch ($WindowsSKU) {
            'Home' { 1 }
            'Standard' { 1 }
            'Home_N' { 2 }
            'Standard (Desktop Experience)' { 1 }
            'Home_SL' { 3 }
            'Datacenter' { 3 }
            'EDU' { 4 }
            'Datacenter (Desktop Experience)' { 4 }
            'EDU_N' { 5 }
            'Pro' { 6 }
            'Pro_N' { 7 }
            'Pro_EDU' { 8 }
            'Pro_Edu_N' { 9 }
            'Pro_WKS' { 10 }
            'Pro_WKS_N' { 11 }
            Default { 6 }
        }
    }
 
    Writelog "WIM Index: $wimindex"
    return $WimIndex
}

function Get-Index {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WindowsImagePath,

        [Parameter(Mandatory = $true)]
        [string]$WindowsSKU
    )

    
    # Get the available indexes using Get-WindowsImage
    $imageIndexes = Get-WindowsImage -ImagePath $WindowsImagePath
    
    # Get the ImageName of ImageIndex 1 if an ISO was specified, else use ImageIndex 4 - this is usually Home or Education SKU on ESD MCT media
    if($ISOPath){
        if ($WindowsSKU -notmatch "Standard|Datacenter") {
            $imageIndex = $imageIndexes | Where-Object ImageIndex -eq 1
            $WindowsImage = $imageIndex.ImageName.Substring(0, 10)
        } else {
            $imageIndex = $imageIndexes | Where-Object ImageIndex -eq 1
            $WindowsImage = $imageIndex.ImageName.Substring(0, 19)
        }
    }
    else{
        $imageIndex = $imageIndexes | Where-Object ImageIndex -eq 4
        $WindowsImage = $imageIndex.ImageName.Substring(0, 10)
    }
    
    # Concatenate $WindowsImage and $WindowsSKU (E.g. Windows 11 Pro)
    $ImageNameToFind = "$WindowsImage $WindowsSKU"
    
    # Find the ImageName in all of the indexes in the image
    $matchingImageIndex = $imageIndexes | Where-Object ImageName -eq $ImageNameToFind
    
    # Return the index that matches exactly
    if ($matchingImageIndex) {
        return $matchingImageIndex.ImageIndex
    }
    else {
        # Look for the numbers 10, 11, 2016, 2019, 2022+ in the ImageName
        $relevantImageIndexes = $imageIndexes | Where-Object { ($_.ImageName -match "(10|11|2016|2019|202\d)") }
            
        while ($true) {
            # Present list of ImageNames to the end user if no matching ImageIndex is found
            Write-Host "No matching ImageIndex found for $ImageNameToFind. Please select an ImageName from the list below:"
    
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
                return $selectedImage.ImageIndex
            }
            else {
                Write-Host "Invalid selection, please try again."
            }
        }
    }
}

#Create VHDX
function New-ScratchVhdx {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VhdxPath,
        [uint64]$SizeBytes = 30GB,
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
    Invoke-Process bcdboot "$($OsPartitionDriveLetter):\Windows /S $($SystemPartitionDriveLetter): /F $FirmwareType"
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
    $SharePath = "net use W: " + $SharePath
    
    # Update CaptureFFU.ps1 script
    if (Test-Path -Path $CaptureFFUScriptPath) {
        $ScriptContent = Get-Content -Path $CaptureFFUScriptPath
        $UpdatedContent = $ScriptContent -replace '(net use).*', ("$SharePath")
        WriteLog 'Updating share command in CaptureFFU.ps1 script with new share information'
        Set-Content -Path $CaptureFFUScriptPath -Value $UpdatedContent
        WriteLog 'Update complete'
    }
    else {
        throw "CaptureFFU.ps1 script not found at $CaptureFFUScriptPath"
    }
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
    if($WindowsArch -eq 'x64') {
        & cmd /c """$DandIEnv"" && copype amd64 $WinPEFFUPath" | Out-Null
    }
    elseif($WindowsArch -eq 'arm64') {
        & cmd /c """$DandIEnv"" && copype arm64 $WinPEFFUPath" | Out-Null
    }
    #Invoke-Process cmd "/c ""$DandIEnv"" && copype amd64 $WinPEFFUPath"
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

    if($WindowsArch -eq 'x64'){
        $PackagePathBase = "$adkPath`Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs\"
    }
    elseif($WindowsArch -eq 'arm64'){
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
            WriteLog "Adding drivers to WinPE media"
            try {
                Add-WindowsDriver -Path "$WinPEFFUPath\Mount" -Driver "$FFUDevelopmentPath\PEDrivers" -Recurse -ErrorAction SilentlyContinue | Out-null
            }
            catch {
                WriteLog 'Some drivers failed to be added to the FFU. This can be expected. Continuing.'
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
    if($WindowsArch -eq 'x64'){
        if($Capture){
            $OSCDIMGArgs = "-m -o -u2 -udfver102 -bootdata:2`#p0,e,b`"$OSCDIMGPath\etfsboot.com`"`#pEF,e,b`"$OSCDIMGPath\Efisys_noprompt.bin`" `"$WinPEFFUPath\media`" `"$WinPEISOFile`""
        }
        if($Deploy){
            $OSCDIMGArgs = "-m -o -u2 -udfver102 -bootdata:2`#p0,e,b`"$OSCDIMGPath\etfsboot.com`"`#pEF,e,b`"$OSCDIMGPath\Efisys.bin`" `"$WinPEFFUPath\media`" `"$WinPEISOFile`""
        }
    }
    elseif($WindowsArch -eq 'arm64'){
        if($Capture){
            $OSCDIMGArgs = "-m -o -u2 -udfver102 -bootdata:1`#pEF,e,b`"$OSCDIMGPath\Efisys_noprompt.bin`" `"$WinPEFFUPath\media`" `"$WinPEISOFile`""
        }
        if($Deploy){
            $OSCDIMGArgs = "-m -o -u2 -udfver102 -bootdata:1`#pEF,e,b`"$OSCDIMGPath\Efisys.bin`" `"$WinPEFFUPath\media`" `"$WinPEISOFile`""
        }
        
    }
    Invoke-Process $OSCDIMG $OSCDIMGArgs
    WriteLog "ISO created successfully"
    WriteLog "Cleaning up $WinPEFFUPath"
    Remove-Item -Path "$WinPEFFUPath" -Recurse -Force
    WriteLog 'Cleanup complete'
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
    } catch {
        throw $_
    }
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
            WriteLog "No .ffu files found in $FFUFolderPath"
            throw $_
        }
    }
    elseif (-not $InstallApps) {
        #Get Windows Version Information from the VHDX
        $winverinfo = Get-WindowsVersionInfo
        $FFUFileName = "$($winverinfo.Name)`_$($winverinfo.DisplayVersion)`_$($winverinfo.SKU)`_$($winverinfo.BuildDate).ffu"
        WriteLog "FFU file name: $FFUFileName"
        $FFUFile = "$FFUCaptureLocation\$FFUFileName"
        #Capture the FFU
        Invoke-Process cmd "/c ""$DandIEnv"" && dism /Capture-FFU /ImageFile:$FFUFile /CaptureDrive:\\.\PhysicalDrive$($vhdxDisk.DiskNumber) /Name:$($winverinfo.Name)$($winverinfo.DisplayVersion)$($winverinfo.SKU) /Compress:Default"
        # Invoke-Process cmd "/c dism /Capture-FFU /ImageFile:$FFUFile /CaptureDrive:\\.\PhysicalDrive$($vhdxDisk.DiskNumber) /Name:$($winverinfo.Name)$($winverinfo.DisplayVersion)$($winverinfo.SKU) /Compress:Default"
        WriteLog 'FFU Capture complete'
        Dismount-ScratchVhdx -VhdxPath $VHDXPath
    }

    #Without this 120 second sleep, we sometimes see an error when mounting the FFU due to a file handle lock. Needed for both driver and optimize steps.
    WriteLog 'Sleeping 2 minutes to prevent file handle lock'
    Start-Sleep 120

    #Add drivers
    If ($InstallDrivers) {
        WriteLog 'Adding drivers'
        WriteLog "Creating $FFUDevelopmentPath\Mount directory"
        New-Item -Path "$FFUDevelopmentPath\Mount" -ItemType Directory -Force | Out-Null
        WriteLog "Created $FFUDevelopmentPath\Mount directory"
        WriteLog "Mounting $FFUFile to $FFUDevelopmentPath\Mount"
        Mount-WindowsImage -ImagePath $FFUFile -Index 1 -Path "$FFUDevelopmentPath\Mount" | Out-null
        WriteLog 'Mounting complete'
        WriteLog 'Adding drivers - This will take a few minutes, please be patient'
        try {
            Add-WindowsDriver -Path "$FFUDevelopmentPath\Mount" -Driver "$DriversFolder" -Recurse -ErrorAction SilentlyContinue | Out-null
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
        WriteLog 'Optimizing FFU - This will take a few minutes, please be patient'
        #Need to use ADK version of DISM to address bug in DISM - perhaps Windows 11 24H2 will fix this
        Invoke-Process cmd "/c ""$DandIEnv"" && dism /optimize-ffu /imagefile:$FFUFile"
        #Invoke-Process cmd "/c dism /optimize-ffu /imagefile:$FFUFile"
        WriteLog 'Optimizing FFU complete'
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
    Invoke-Process cmd "/c mountvol /r"
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
    WriteLog "Loading Software registry hive"
    Invoke-Process reg "load HKLM\FFU $Software"

    #Find Windows version values
    $SKU = Get-ItemPropertyValue -Path 'HKLM:\FFU\Microsoft\Windows NT\CurrentVersion\' -Name 'EditionID'
    WriteLog "Windows SKU: $SKU"
    [int]$CurrentBuild = Get-ItemPropertyValue -Path 'HKLM:\FFU\Microsoft\Windows NT\CurrentVersion\' -Name 'CurrentBuild'
    WriteLog "Windows Build: $CurrentBuild"
    #DisplayVersion does not exist for 1607 builds (RS1 and Server 2016) and Server 2019
    if($CurrentBuild -notin (14393, 17763)) {
    $DisplayVersion = Get-ItemPropertyValue -Path 'HKLM:\FFU\Microsoft\Windows NT\CurrentVersion\' -Name 'DisplayVersion'
    WriteLog "Windows Version: $DisplayVersion"
    }
    
    $BuildDate = Get-Date -uformat %b%Y

    $SKU = switch ($SKU) {
        Core { 'Home' }
        Professional { 'Pro' }
        ProfessionalEducation { 'Pro_Edu' }
        Enterprise { 'Ent' }
        Education { 'Edu' }
        ProfessionalWorkstation { 'Pro_Wks' }
	    ServerStandard { 'Srv_Std' }
        ServerDatacenter { 'Srv_Dtc' }
    }
    WriteLog "Windows SKU Modified to: $SKU"

    if ($SKU -notmatch "Srv") {
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
    Invoke-Process reg "unload HKLM\FFU"
    #This prevents Critical Process Died errors you can have during deployment of the FFU. Capturing from very fast disks (NVME) can cause the capture to happen faster than Windows is ready for.
    WriteLog 'Sleep 60 seconds to allow registry to completely unload'
    Start-sleep 60

    return @{

        DisplayVersion = $DisplayVersion
        BuildDate      = $buildDate
        Name           = $Name
        SKU            = $SKU
    }
}
Function Get-USBDrive {
    # Log the start of the USB drive check
    WriteLog 'Checking for USB drives'
    
    # Check if external hard disk media is allowed
    If ($AllowExternalHardDiskMedia) {
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
                    Write-Host "$ExternalCount are external drives"
                }
            }
            WriteLog "Found $USBDrivesCount total USB drives"
            If ($ExternalCount -gt 0) {
                WriteLog "$ExternalCount are external drives"
            }
        }
    }
    else {
        # Get only removable media drives
        [array]$USBDrives = (Get-WmiObject -Class Win32_DiskDrive -Filter "MediaType='Removable Media'")
        $USBDrivesCount = $USBDrives.Count
        WriteLog "Found $USBDrivesCount Removable USB drives"
    }
    
    # Check if any USB drives were found
    if ($null -eq $USBDrives) {
        WriteLog "No removable USB drive found. Exiting"
        Write-Error "No removable USB drive found. Exiting"
        exit 1
    }
    
    # Return the found USB drives and their count
    return $USBDrives, $USBDrivesCount
}
Function New-DeploymentUSB {
    param(
        [switch]$CopyFFU
    )
    WriteLog "CopyFFU is set to $CopyFFU"
    $BuildUSBPath = $PSScriptRoot
    WriteLog "BuildUSBPath is $BuildUSBPath"

    $SelectedFFUFile = $null

    # Check if the CopyFFU switch is present
    if ($CopyFFU.IsPresent) {
        # Get all FFU files in the specified directory
        $FFUFiles = Get-ChildItem -Path "$BuildUSBPath\FFU" -Filter "*.ffu"
        $FFUCount = $FFUFiles.count

        # If there is exactly one FFU file, select it
        if ($FFUCount -eq 1) {
            $SelectedFFUFile = $FFUFiles.FullName
        }
        # If there are multiple FFU files, prompt the user to select one
        elseif ($FFUCount -gt 1) {
            WriteLog "Found $FFUCount FFU files"
            if($VerbosePreference -ne 'Continue'){
                Write-Host "Found $FFUCount FFU files"
            }
            $output = @()
            # Create a table of FFU files with their index, name, and last modified date
            for ($i = 0; $i -lt $FFUCount; $i++) {
                $index = $i + 1
                $name = $FFUFiles[$i].Name
                $modified = $FFUFiles[$i].LastWriteTime
                $Properties = [ordered]@{
                    'FFU Number'    = $index
                    'FFU Name'      = $name
                    'Last Modified' = $modified
                }
                $output += New-Object PSObject -Property $Properties
            }
            $output | Format-Table -AutoSize -Property 'FFU Number', 'FFU Name', 'Last Modified'
            
            # Loop until a valid FFU file is selected
            do {
                $inputChoice = Read-Host "Enter the number corresponding to the FFU file you want to copy or 'A' to copy all FFU files"
                # Check if the input is a valid number or 'A'
                if ($inputChoice -match '^\d+$' -or $inputChoice -eq 'A') {
                    if ($inputChoice -eq 'A') {
                        # Select all FFU files
                        $SelectedFFUFile = $FFUFiles.FullName
                        if ($VerbosePreference -ne 'Continue') {
                            Write-Host 'Will copy all FFU files'
                        }
                        WriteLog 'Will copy all FFU Files'
                    }
                    else {
                        # Convert input to integer and validate the selection
                        $inputChoice = [int]$inputChoice
                        if ($inputChoice -ge 1 -and $inputChoice -le $FFUCount) {
                            $selectedIndex = $inputChoice - 1
                            $SelectedFFUFile = $FFUFiles[$selectedIndex].FullName
                            if ($VerbosePreference -ne 'Continue') {
                                Write-Host "$SelectedFFUFile was selected"
                            }
                            WriteLog "$SelectedFFUFile was selected"
                        }
                        else {
                            # Handle invalid selection
                            if ($VerbosePreference -ne 'Continue') {
                                Write-Host "Invalid selection. Please try again."
                            }
                            WriteLog "Invalid selection. Please try again."
                        }
                    }
                }
                else {
                    # Handle invalid input
                    if ($VerbosePreference -ne 'Continue') {
                        Write-Host "Invalid selection. Please try again."
                    }
                    WriteLog "Invalid selection. Please try again."
                }
            } while ($null -eq $SelectedFFUFile)
            
        }
        else {
            # Handle case where no FFU files are found
            WriteLog "No FFU files found in the current directory."
            Write-Error "No FFU files found in the current directory."
            Return
        }
    }    
    $counter = 0

    foreach ($USBDrive in $USBDrives) {
        $Counter++
        WriteLog "Formatting USB drive $Counter out of $USBDrivesCount"
        $DiskNumber = $USBDrive.DeviceID.Replace("\\.\PHYSICALDRIVE", "")
        WriteLog "Physical Disk number is $DiskNumber for USB drive $Counter out of $USBDrivesCount"

        $ScriptBlock = {
            param($DiskNumber)
            $Disk = Get-Disk -Number $DiskNumber
            # Clear-Disk -Number $DiskNumber -RemoveData -RemoveOEM -Confirm:$false
            # Clear-disk has an unusual behavior where it sets external hard disk media as RAW, however removable media is set as MBR.
            if ($Disk.PartitionStyle -ne "RAW") {
                $Disk | Clear-Disk -RemoveData -RemoveOEM -Confirm:$false
                $Disk = Get-Disk -Number $DiskNumber
            }
            
            if($Disk.PartitionStyle -eq "RAW") {
                $Disk | Initialize-Disk -PartitionStyle MBR -Confirm:$false
            }
            elseif($Disk.PartitionStyle -ne "RAW"){
                $Disk | Get-Partition | Remove-Partition -Confirm:$false
                $Disk | Set-Disk -PartitionStyle MBR
            }
            # Get-Disk $DiskNumber | Get-Partition | Remove-Partition            
            $BootPartition = $Disk | New-Partition -Size 2GB -IsActive -AssignDriveLetter
            $DeployPartition = $Disk | New-Partition -UseMaximumSize -AssignDriveLetter
            Format-Volume -Partition $BootPartition -FileSystem FAT32 -NewFileSystemLabel "TempBoot" -Confirm:$false
            Format-Volume -Partition $DeployPartition -FileSystem NTFS -NewFileSystemLabel "TempDeploy" -Confirm:$false
        }

        WriteLog 'Partitioning USB Drive'
        Invoke-Command -ScriptBlock $ScriptBlock -ArgumentList $DiskNumber | Out-null
        WriteLog 'Done'

        # $BootPartitionDriveLetter = (Get-WmiObject -Class win32_volume -Filter "Label='TempBoot' AND DriveType=2 AND DriveLetter IS NOT NULL").Name
        $BootPartitionDriveLetter = (Get-WmiObject -Class win32_volume -Filter "Label='TempBoot' AND DriveLetter IS NOT NULL").Name
        $ISOMountPoint = (Mount-DiskImage -ImagePath $DeployISO -PassThru | Get-Volume).DriveLetter + ":\"
        WriteLog "Copying WinPE files to $BootPartitionDriveLetter"
        robocopy "$ISOMountPoint" "$BootPartitionDriveLetter" /E /COPYALL /R:5 /W:5 /J
        Dismount-DiskImage -ImagePath $DeployISO | Out-Null

        if ($CopyFFU.IsPresent) {
            if ($null -ne $SelectedFFUFile) {
                # $DeployPartitionDriveLetter = (Get-WmiObject -Class win32_volume -Filter "Label='TempDeploy' AND DriveType=2 AND DriveLetter IS NOT NULL").Name
                $DeployPartitionDriveLetter = (Get-WmiObject -Class win32_volume -Filter "Label='TempDeploy' AND DriveLetter IS NOT NULL").Name
                if ($SelectedFFUFile -is [array]) {
                    WriteLog "Copying multiple FFU files to $DeployPartitionDriveLetter. This could take a few minutes."
                    foreach ($FFUFile in $SelectedFFUFile) {
                        robocopy $(Split-Path $FFUFile -Parent) $DeployPartitionDriveLetter $(Split-Path $FFUFile -Leaf) /COPYALL /R:5 /W:5 /J
                    }
                }
                else {
                    WriteLog ("Copying " + $SelectedFFUFile + " to $DeployPartitionDriveLetter. This could take a few minutes.")
                    robocopy $(Split-Path $SelectedFFUFile -Parent) $DeployPartitionDriveLetter $(Split-Path $SelectedFFUFile -Leaf) /COPYALL /R:5 /W:5 /J
                }
                #Copy drivers using robocopy due to potential size
                if ($CopyDrivers) {
                    WriteLog "Copying drivers to $DeployPartitionDriveLetter\Drivers"
                    if ($Make){
                        robocopy "$DriversFolder\$Make" "$DeployPartitionDriveLetter\Drivers" /E /R:5 /W:5 /J
                    }else{
                        robocopy "$DriversFolder" "$DeployPartitionDriveLetter\Drivers" /E /R:5 /W:5 /J
                    }
                    
                }
                #Copy Unattend file to the USB drive. 
                if ($CopyUnattend) {
                    # WriteLog "Copying Unattend folder to $DeployPartitionDriveLetter"
                    # Copy-Item -Path "$FFUDevelopmentPath\Unattend" -Destination $DeployPartitionDriveLetter -Recurse -Force
                    $DeployUnattendPath = "$DeployPartitionDriveLetter\unattend"
                    WriteLog "Copying unattend file to $DeployUnattendPath"
                    New-Item -Path $DeployUnattendPath -ItemType Directory | Out-Null
                    if ($WindowsArch -eq 'x64') {
                        Copy-Item -Path "$FFUDevelopmentPath\unattend\unattend_x64.xml" -Destination "$DeployUnattendPath\Unattend.xml" -Force | Out-Null
                    }
                    if ($WindowsArch -eq 'arm64') {
                        Copy-Item -Path "$FFUDevelopmentPath\unattend\unattend_arm64.xml" -Destination "$DeployUnattendPath\Unattend.xml" -Force | Out-Null
                    }
                    #Check for prefixes.txt file and copy it to the USB drive
                    if (Test-Path "$FFUDevelopmentPath\unattend\prefixes.txt") {
                        WriteLog "Copying prefixes.txt file to $DeployUnattendPath"
                        Copy-Item -Path "$FFUDevelopmentPath\unattend\prefixes.txt" -Destination "$DeployUnattendPath\prefixes.txt" -Force | Out-Null
                    }
                    WriteLog 'Copy completed'
                }  
                #Copy PPKG folder in the FFU folder to the USB drive. Can use copy-item as it's a small folder
                if ($CopyPPKG) {
                    WriteLog "Copying PPKG folder to $DeployPartitionDriveLetter"
                    Copy-Item -Path "$FFUDevelopmentPath\PPKG" -Destination $DeployPartitionDriveLetter -Recurse -Force
                }
                #Copy Autopilot folder in the FFU folder to the USB drive. Can use copy-item as it's a small folder
                if ($CopyAutopilot) {
                    WriteLog "Copying Autopilot folder to $DeployPartitionDriveLetter"
                    Copy-Item -Path "$FFUDevelopmentPath\Autopilot" -Destination $DeployPartitionDriveLetter -Recurse -Force
                }
            }
            else {
                WriteLog "No FFU file selected. Skipping copy."
            }
        }

        Set-Volume -FileSystemLabel "TempBoot" -NewFileSystemLabel "Boot"
        Set-Volume -FileSystemLabel "TempDeploy" -NewFileSystemLabel "Deploy"

        if ($USBDrivesCount -gt 1) {
            & mountvol $BootPartitionDriveLetter /D
            & mountvol $DeployPartitionDriveLetter /D 
        }

        WriteLog "Drive $counter completed"
    }

    WriteLog "USB Drives completed"
}


function Get-FFUEnvironment {
    WriteLog 'Dirty.txt file detected. Last run did not complete succesfully. Will clean environment'
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
    Invoke-Process cmd "/c mountvol /r"
    WriteLog 'Removal complete'

    # Check for content in the VM folder and delete any folders that start with _FFU-
    $folders = Get-ChildItem -Path $VMLocation -Directory
    foreach ($folder in $folders) {
        if ($folder.Name -like '_FFU-*') {
            WriteLog "Removing folder $($folder.FullName)"
            Remove-Item -Path $folder.FullName -Recurse -Force
        }
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
        Invoke-Process reg "unload HKLM\FFU"
    }

    #Remove FFU User and Share
    $UserExists = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
    if ($UserExists) {
        WriteLog "Removing FFU User and Share"
        Remove-FFUUserShare
        WriteLog 'Removal complete'
    }
    Clear-InstallAppsandSysprep
    #Clean up $KBPath
    If (Test-Path -Path $KBPath) {
         if ($AllowUpdateCaching) {
            WriteLog "Copying $KBPath content to $KBCachePath for cache retrieval"
            Robocopy.exe $($KBPath) $($KBCachePath) /E /Z /Copy:DAT
            WriteLog "Copy complete"
        }
        WriteLog "Removing $KBPath"
        Remove-Item -Path $KBPath -Recurse -Force -ErrorAction SilentlyContinue
        WriteLog 'Removal complete'
    }
    #Clean up $DefenderPath
    If (Test-Path -Path $DefenderPath) {
        WriteLog "Removing $DefenderPath"
        Remove-Item -Path $DefenderPath -Recurse -Force -ErrorAction SilentlyContinue
        WriteLog 'Removal complete'
    }
    #Clean up $MSRTPath
    if (Test-Path -Path $MSRTPath) {
        WriteLog "Removing $MSRTPath"
        Remove-Item -Path $MSRTPath -Recurse -Force -ErrorAction SilentlyContinue
        WriteLog 'Removal complete'
    }
    #Clean up $OneDrivePath
    If (Test-Path -Path $OneDrivePath) {
        WriteLog "Removing $OneDrivePath"
        Remove-Item -Path $OneDrivePath -Recurse -Force -ErrorAction SilentlyContinue
        WriteLog 'Removal complete'
    }
    #Clean up $EdgePath
    If (Test-Path -Path $EdgePath) {
        WriteLog "Removing $EdgePath"
        Remove-Item -Path $EdgePath -Recurse -Force -ErrorAction SilentlyContinue
        WriteLog 'Removal complete'
    }
    if (Test-Path -Path "$AppsPath\Win32" -PathType Container) {
        WriteLog "Cleaning up Win32 folder"
        Remove-Item -Path "$AppsPath\Win32" -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -Path "$AppsPath\MSStore" -PathType Container) {
        WriteLog "Cleaning up MSStore folder"
        Remove-Item -Path "$AppsPath\MSStore" -Recurse -Force -ErrorAction SilentlyContinue
    }   
    Writelog 'Removing dirty.txt file'
    Remove-Item -Path "$FFUDevelopmentPath\dirty.txt" -Force
    WriteLog "Cleanup complete"
}
function Remove-FFU {
    #Remove all FFU files in the FFUCaptureLocation
    WriteLog "Removing all FFU files in $FFUCaptureLocation"
    Remove-Item -Path $FFUCaptureLocation\*.ffu -Force
    WriteLog "Removal complete"
}
function Clear-InstallAppsandSysprep {
    $cmdContent = Get-Content -Path "$AppsPath\InstallAppsandSysprep.cmd"
    WriteLog "Updating $AppsPath\InstallAppsandSysprep.cmd to remove win32 app install commands"
    $cmdContent -notmatch "REM Win32*" | Set-Content -Path "$AppsPath\InstallAppsandSysprep.cmd"
    $cmdContent = Get-Content -Path "$AppsPath\InstallAppsandSysprep.cmd"
    $cmdContent -notmatch "D:\\win32*" | Set-Content -Path "$AppsPath\InstallAppsandSysprep.cmd"
    $cmdContent = Get-Content -Path "$AppsPath\InstallAppsandSysprep.cmd"
    WriteLog "Setting MSStore installation condition to false"
    $cmdContent -replace 'set "INSTALL_STOREAPPS=true"', 'set "INSTALL_STOREAPPS=false"' | Set-Content -Path "$AppsPath\InstallAppsandSysprep.cmd"
    if ($UpdateLatestDefender) {
        WriteLog "Updating $AppsPath\InstallAppsandSysprep.cmd to remove Defender Platform Update"
        $CmdContent = Get-Content -Path "$AppsPath\InstallAppsandSysprep.cmd"
        $CmdContent -notmatch 'd:\\Defender*' | Set-Content -Path "$AppsPath\InstallAppsandSysprep.cmd"
        #Clean up $DefenderPath
        If (Test-Path -Path $DefenderPath) {
            WriteLog "Removing $DefenderPath"
            Remove-Item -Path $DefenderPath -Recurse -Force -ErrorAction SilentlyContinue
            WriteLog 'Removal complete'
        }
    }
    if ($UpdateLatestMSRT) {
        WriteLog "Updating $AppsPath\InstallAppsandSysprep.cmd to remove Windows Malicious Software Removal Tool"
        $CmdContent = Get-Content -Path "$AppsPath\InstallAppsandSysprep.cmd"
        $CmdContent -notmatch 'd:\\MSRT*' | Set-Content -Path "$AppsPath\InstallAppsandSysprep.cmd"
        #Clean up $MSRTPath
        If (Test-Path -Path $MSRTPath) {
            WriteLog "Removing $MSRTPath"
            Remove-Item -Path $MSRTPath -Recurse -Force -ErrorAction SilentlyContinue
            WriteLog 'Removal complete'
        }
    }
    if ($UpdateOneDrive) {
        WriteLog "Updating $AppsPath\InstallAppsandSysprep.cmd to remove OneDrive install"
        $CmdContent = Get-Content -Path "$AppsPath\InstallAppsandSysprep.cmd"
        $CmdContent -notmatch 'd:\\OneDrive*' | Set-Content -Path "$AppsPath\InstallAppsandSysprep.cmd"
        #Clean up $OneDrivePath
        If (Test-Path -Path $OneDrivePath) {
            WriteLog "Removing $OneDrivePath"
            Remove-Item -Path $OneDrivePath -Recurse -Force -ErrorAction SilentlyContinue
            WriteLog 'Removal complete'
        }
    }
    if ($UpdateEdge) {
        WriteLog "Updating $AppsPath\InstallAppsandSysprep.cmd to remove Edge install"
        $CmdContent = Get-Content -Path "$AppsPath\InstallAppsandSysprep.cmd"
        $CmdContent -notmatch 'd:\\Edge*' | Set-Content -Path "$AppsPath\InstallAppsandSysprep.cmd"
        #Clean up $EdgePath
        If (Test-Path -Path $EdgePath) {
            WriteLog "Removing $EdgePath"
            Remove-Item -Path $EdgePath -Recurse -Force -ErrorAction SilentlyContinue
            WriteLog 'Removal complete'
        }
    }
}

###END FUNCTIONS

#Remove old log file if found
if (Test-Path -Path $Logfile) {
    Remove-item -Path $LogFile -Force
}
$startTime = Get-Date
Write-Host "FFU build process started at" $startTime
Write-Host "This process can take 20 minutes or more. Please do not close this window or any additional windows that pop up"
Write-Host "To track progress, please open the log file $Logfile or use the -Verbose parameter next time"

WriteLog 'Begin Logging'

###PARAMETER VALIDATION

#Validate drivers folder
if ($InstallDrivers -or $CopyDrivers) {
    WriteLog 'Doing driver validation'
    if ($Make -and $Model){
        WriteLog "Make and Model are set to $Make and $Model, will attempt to download drivers"
    } else {
        if (!(Test-Path -Path $DriversFolder)) {
            WriteLog "-InstallDrivers or -CopyDrivers is set to `$true, but the $DriversFolder folder is missing"
            throw "-InstallDrivers or -CopyDrivers is set to `$true, but the $DriversFolder folder is missing"
        }
        if ((Get-ChildItem -Path $DriversFolder -Recurse | Measure-Object -Property Length -Sum).Sum -lt 1MB) {
            WriteLog "-InstallDrivers or -CopyDrivers is set to `$true, but the $DriversFolder folder is empty"
            throw "-InstallDrivers or -CopyDrivers is set to `$true, but the $DriversFolder folder is empty"
        }
        WriteLog 'Driver validation complete'
    }   
}
#Validate PEDrivers folder
if ($CopyPEDrivers) {
    WriteLog 'Doing PEDriver validation'
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

#Override $InstallApps value if using ESD to build FFU. This is due to a strange issue where building the FFU
#from vhdx doesn't work (you get an older style OOBE screen and get stuck in an OOBE reboot loop when hitting next).
#This behavior doesn't happen with WIM files.
If (-not ($ISOPath) -and (-not ($InstallApps))) {
    $InstallApps = $true
    WriteLog "Script will download Windows media. Setting `$InstallApps to `$true to build VM to capture FFU. Must do this when using MCT ESD."
}

if (($InstallOffice -eq $true) -and ($InstallApps -eq $false)) {
    throw "If variable InstallOffice is set to `$true, InstallApps must also be set to `$true."
}
if (($InstallApps -and ($VMSwitchName -eq ''))) {
    throw "If variable InstallApps is set to `$true, VMSwitchName must also be set to capture the FFU. Please set -VMSwitchName and try again."
}

if (($InstallApps -and ($VMHostIPAddress -eq ''))) {
    throw "If variable InstallApps is set to `$true, VMHostIPAddress must also be set to capture the FFU. Please set -VMHostIPAddress and try again."
}

if (($VMHostIPAddress) -and ($VMSwitchName)){
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

###END PARAMETER VALIDATION

#Get script variable values
LogVariableValues

#Check if environment is dirty
If (Test-Path -Path "$FFUDevelopmentPath\dirty.txt") {
    Get-FFUEnvironment
}
WriteLog 'Creating dirty.txt file'
New-Item -Path .\ -Name "dirty.txt" -ItemType "file" | Out-Null

#Get drivers first since user could be prompted for additional info
if (($make -and $model) -and ($installdrivers -or $copydrivers)) {
    try {
        if ($Make -eq 'HP'){
            WriteLog 'Getting HP drivers'
            Get-HPDrivers -Make $Make -Model $Model -WindowsArch $WindowsArch -WindowsRelease $WindowsRelease -WindowsVersion $WindowsVersion
            WriteLog 'Getting HP drivers completed successfully'
        }
        if ($make -eq 'Microsoft'){
            WriteLog 'Getting Microsoft drivers'
            Get-MicrosoftDrivers -Make $Make -Model $Model -WindowsArch $WindowsArch -WindowsRelease $WindowsRelease
            WriteLog 'Getting Microsoft drivers completed successfully'
        }
        if ($make -eq 'Lenovo'){
            WriteLog 'Getting Lenovo drivers'
            Get-LenovoDrivers -Model $Model -WindowsArch $WindowsArch -WindowsRelease $WindowsRelease
            WriteLog 'Getting Lenovo drivers completed successfully'
        }
        if ($make -eq 'Dell'){
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
try {
    $adkPath = Get-ADK
    #Need to use the Deployment and Imaging tools environment to use dism from the Sept 2023 ADK to optimize FFU 
    $DandIEnv = "$adkPath`Assessment and Deployment Kit\Deployment Tools\DandISetEnv.bat"
}
catch {
    WriteLog 'ADK not found'
    throw $_
}

#Create apps ISO for Office and/or 3rd party apps
if ($InstallApps) {
    try {
        #Make sure InstallAppsandSysprep.cmd file exists
        WriteLog "InstallApps variable set to true, verifying $AppsPath\InstallAppsandSysprep.cmd exists"
        if (-not (Test-Path -Path "$AppsPath\InstallAppsandSysprep.cmd")) {
            Write-Host "$AppsPath\InstallAppsandSysprep.cmd is missing, exiting script"
            WriteLog "$AppsPath\InstallAppsandSysprep.cmd is missing, exiting script"
            exit
        }
        WriteLog "$AppsPath\InstallAppsandSysprep.cmd found"
        If (Test-Path -Path "$AppsPath\AppList.json"){
            WriteLog "$AppsPath\AppList.json found, checking for winget apps to install"
            Get-Apps -AppList "$AppsPath\AppList.json"
        }
        
        if (-not $InstallOffice) {
            #Modify InstallAppsandSysprep.cmd to REM out the office install command
            $CmdContent = Get-Content -Path "$AppsPath\InstallAppsandSysprep.cmd"
            $UpdatedcmdContent = $CmdContent -replace '^(d:\\Office\\setup.exe /configure d:\\office\\DeployFFU.xml)', ("REM d:\Office\setup.exe /configure d:\office\DeployFFU.xml")
            Set-Content -Path "$AppsPath\InstallAppsandSysprep.cmd" -Value $UpdatedcmdContent
        }
        
        if ($InstallOffice) {
            WriteLog 'Downloading M365 Apps/Office'
            Get-Office
            WriteLog 'Downloading M365 Apps/Office completed successfully'
        }

        #Update Latest Defender Platform and Definitions - these can't be serviced into the VHDX, will be saved to AppsPath
        if ($UpdateLatestDefender) {
            WriteLog "`$UpdateLatestDefender is set to true, checking for latest Defender Platform and Definitions"
            $Name = "Update for Microsoft Defender Antivirus antimalware platform"
            #Check if $DefenderPath exists, if not, create it
            If (-not (Test-Path -Path $DefenderPath)) {
                WriteLog "Creating $DefenderPath"
                New-Item -Path $DefenderPath -ItemType Directory -Force | Out-Null
            }
            WriteLog "Searching for $Name from Microsoft Update Catalog and saving to $DefenderPath"
            $KBFilePath = Save-KB -Name $Name -Path $DefenderPath
            WriteLog "Latest Defender Platform and Definitions saved to $DefenderPath\$KBFilePath"
            
            #Modify InstallAppsandSysprep.cmd to add in $KBFilePath on the line after REM Install Defender Update Platform
            WriteLog "Updating $AppsPath\InstallAppsandSysprep.cmd to include Defender Platform Update"
            $CmdContent = Get-Content -Path "$AppsPath\InstallAppsandSysprep.cmd"
            $UpdatedcmdContent = $CmdContent -replace '^(REM Install Defender Platform Update)', ("REM Install Defender Platform Update`r`nd:\Defender\$KBFilePath")
            Set-Content -Path "$AppsPath\InstallAppsandSysprep.cmd" -Value $UpdatedcmdContent
            WriteLog "Update complete"

            ###### 9/4/2024 - Windows Security Platform update is no longer available from Update Catalog. Will change to using
            ###### https://support.microsoft.com/en-us/topic/windows-security-update-a6ac7d2e-b1bf-44c0-a028-41720a242da3

            # #Get Windows Security platform update
            # $Name = "Windows Security platform definition updates"
            # WriteLog "Searching for $Name from Microsoft Update Catalog and saving to $DefenderPath"
            # $KBFilePath = Save-KB -Name $Name -Path $DefenderPath
            # WriteLog "Latest Security Platform Update saved to $DefenderPath\$KBFilePath"
            # #Modify InstallAppsandSysprep.cmd to add in $KBFilePath on the line after REM Install Windows Security Platform Update
            # WriteLog "Updating $AppsPath\InstallAppsandSysprep.cmd to include Windows Security Platform Update"
            # $CmdContent = Get-Content -Path "$AppsPath\InstallAppsandSysprep.cmd"
            # $UpdatedcmdContent = $CmdContent -replace '^(REM Install Windows Security Platform Update)', ("REM Install Windows Security Platform Update`r`nd:\Defender\$KBFilePath")
            # Set-Content -Path "$AppsPath\InstallAppsandSysprep.cmd" -Value $UpdatedcmdContent
            # WriteLog "Update complete"

            #Download latest Defender Definitions
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
            }
            catch {
                Write-Host "Downloading Defender Definitions Failed"
                WriteLog "Downloading Defender Definitions Failed with error $_"
                throw $_
            }

            #Modify InstallAppsandSysprep.cmd to add in $DefenderPath on the line after REM Install Defender Definitions
            WriteLog "Updating $AppsPath\InstallAppsandSysprep.cmd to include Defender Definitions"
            $CmdContent = Get-Content -Path "$AppsPath\InstallAppsandSysprep.cmd"
            $UpdatedcmdContent = $CmdContent -replace '^(REM Install Defender Definitions)', ("REM Install Defender Definitions`r`nd:\Defender\mpam-fe.exe")
            Set-Content -Path "$AppsPath\InstallAppsandSysprep.cmd" -Value $UpdatedcmdContent
            WriteLog "Update complete"
        }
        if ($UpdateLatestMSRT) {
            WriteLog "`$UpdateLatestMSRT is set to true."
            $Name = "Windows Malicious Software Removal Tool"
            #Check if $MSRTPath exists, if not, create it
            if (-not (Test-Path -Path $MSRTPath)) {
                WriteLog "Creating $MSRTPath"
                New-Item -Path $MSRTPath -ItemType Directory -Force | Out-Null
            }
            WriteLog "Getting Windows Malicious Software Removal Tool URL"
            $MSRTFileName = Save-KB -Name $Name -Path $MSRTPath
            WriteLog "Latest Windows Malicious Software Removal Tool saved to $MSRTPath\$MSRTFileName"
            WriteLog "Updating $AppsPath\InstallAppsandSysprep.cmd to include Windows Malicious Software Removal Tool"
            $CmdContent = Get-Content -Path "$AppsPath\InstallAppsandSysprep.cmd"
            $UpdatedcmdContent = $CmdContent -replace '^(REM Install Windows Malicious Software Removal Tool)', ("REM Install Windows Malicious Software Removal Tool`r`nd:\MSRT\$MSRTFileName /quiet")
            Set-Content -Path "$AppsPath\InstallAppsandSysprep.cmd" -Value $UpdatedcmdContent
            WriteLog "Update complete"
        }
        #Download and Install OneDrive Per Machine
        if ($UpdateOneDrive) {
            WriteLog "`$UpdateOneDrive is set to true, checking for latest OneDrive client"
            #Check if $OneDrivePath exists, if not, create it
            If (-not (Test-Path -Path $OneDrivePath)) {
                WriteLog "Creating $OneDrivePath"
                New-Item -Path $OneDrivePath -ItemType Directory -Force | Out-Null
            }
            WriteLog "Downloading latest OneDrive client"
            if($WindowsArch -eq 'x64')
            {
                $OneDriveURL = 'https://go.microsoft.com/fwlink/?linkid=844652'
            }
            elseif($WindowsArch -eq 'ARM64')
            {
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

            #Modify InstallAppsandSysprep.cmd to add in $OneDrivePath on the line after REM Install Defender Definitions
            WriteLog "Updating $AppsPath\InstallAppsandSysprep.cmd to include OneDrive client"
            $CmdContent = Get-Content -Path "$AppsPath\InstallAppsandSysprep.cmd"
            $UpdatedcmdContent = $CmdContent -replace '^(REM Install OneDrive Per Machine)', ("REM Install OneDrive Per Machine`r`nd:\OneDrive\OneDriveSetup.exe /allusers /silent")
            Set-Content -Path "$AppsPath\InstallAppsandSysprep.cmd" -Value $UpdatedcmdContent
            WriteLog "Update complete"
        }

        #Download and Install Edge Stable
        if ($UpdateEdge) {
            WriteLog "`$UpdateEdge is set to true, checking for latest Edge Stable $WindowsArch release"
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
            Invoke-Process Expand "$EdgeCABFilePath -F:*.msi $EdgeFullFilePath"
            WriteLog "Expansion complete"

            #Remove Edge CAB file
            WriteLog "Removing $EdgeCABFilePath"
            Remove-Item -Path $EdgeCABFilePath -Force
            WriteLog "Removal complete"

            #Modify InstallAppsandSysprep.cmd to add in $KBFilePath on the line after REM Install Edge Stable
            WriteLog "Updating $AppsPath\InstallAppsandSysprep.cmd to include Edge Stable $WindowsArch release"
            $CmdContent = Get-Content -Path "$AppsPath\InstallAppsandSysprep.cmd"
            $UpdatedcmdContent = $CmdContent -replace '^(REM Install Edge Stable)', ("REM Install Edge Stable`r`nd:\Edge\$EdgeMSIFileName /quiet /norestart")
            Set-Content -Path "$AppsPath\InstallAppsandSysprep.cmd" -Value $UpdatedcmdContent
            WriteLog "Update complete"
        }

        #Modify InstallAppsandSysprep.cmd to remove old script variables
        $CmdContent = Get-Content -Path "$AppsPath\InstallAppsandSysprep.cmd"
        $StartIndex = $CmdContent.IndexOf("REM START Batch variables placeholder")
        $EndIndex = $CmdContent.IndexOf("REM END Batch variables placeholder")
        if (($StartIndex + 1) -lt $EndIndex) {
            for ($i = ($StartIndex + 1); $i -lt $EndIndex; $i++) {
                $CmdContent[$i] = $null
            }
        }
        Set-Content -Path "$AppsPath\InstallAppsandSysprep.cmd" -Value $CmdContent

        if ($AppsScriptVariables) {
            #Modify InstallAppsandSysprep.cmd to add the script variables
            $CmdContent = [System.Collections.ArrayList](Get-Content -Path "$AppsPath\InstallAppsandSysprep.cmd")
            $ScriptIndex = $CmdContent.IndexOf("REM START Batch variables placeholder") + 1
            foreach ($VariableKey in $AppsScriptVariables.Keys) {
                $CmdContent.Insert($ScriptIndex, ("set {0}={1}" -f $VariableKey, $AppsScriptVariables[$VariableKey]))
                $ScriptIndex++
            }
            Set-Content -Path "$AppsPath\InstallAppsandSysprep.cmd" -Value $CmdContent
        }
	
        #Create Apps ISO
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

#Create VHDX
try {

    #Update latest Cumulative Update if both $UpdateLatestCU is $true and $UpdatePreviewCU is $false
    #Changed to use MU Catalog instead of using Get-LatestWindowsKB
    #The Windows release info page is updated later than the MU Catalog
    if ($UpdateLatestCU -and -not $UpdatePreviewCU) {
        Writelog "`$UpdateLatestCU is set to true, checking for latest CU"
        if ($installationType -eq 'Client') {
            $Name = """Cumulative update for Windows $WindowsRelease Version $WindowsVersion for $WindowsArch"""
        }
        if ($WindowsRelease -eq 2022) {
            $Name = """Cumulative Update for Microsoft server operating system, version 22h2 for $WindowsArch"""
        } 
        if ($WindowsRelease -in 2016, 2019) {
            $Name = """Cumulative update for Windows Server $WindowsRelease for $WindowsArch"""
        }
        #Check if $KBPath exists, if not, create it
        If (-not (Test-Path -Path $KBPath)) {
            WriteLog "Creating $KBPath"
            New-Item -Path $KBPath -ItemType Directory -Force | Out-Null
        }
        #Get latest Servicing Stack Update for Windows Server 2016
        if ($WindowsRelease -eq 2016) {
            $SSUName = """Servicing stack update for Windows Server $WindowsRelease for $WindowsArch"""
            WriteLog "Searching for $SSUName from Microsoft Update Catalog and saving to $KBPath"
            $SSUFile = Save-KB -Name $SSUName -Path $KBPath
            $SSUFilePath = "$KBPath\$SSUFile"
            WriteLog "Latest SSU saved to $SSUFilePath"
        }
        WriteLog "Searching for $name from Microsoft Update Catalog and saving to $KBPath"
        $KBFilePath = Save-KB -Name $Name -Path $KBPath
        WriteLog "Latest CU saved to $KBPath\$KBFilePath"
    }

    #Update Latest Preview Cumlative Update for Client OS only
    #will take Precendence over $UpdateLastestCU if both were set to $true
    if ($UpdatePreviewCU -and $installationType -eq 'Client') {
        Writelog "`$UpdatePreviewCU is set to true, checking for latest Preview CU"
        $Name = """Cumulative update Preview for Windows $WindowsRelease Version $WindowsVersion for $WindowsArch"""
        #Check if $KBPath exists, if not, create it
        If (-not (Test-Path -Path $KBPath)) {
            WriteLog "Creating $KBPath"
            New-Item -Path $KBPath -ItemType Directory -Force | Out-Null
        }
        WriteLog "Searching for $name from Microsoft Update Catalog and saving to $KBPath"
        $KBFilePath = Save-KB -Name $Name -Path $KBPath
        WriteLog "Latest Preview CU saved to $KBPath\$KBFilePath"
    }

    #Update Latest .NET Framework
    if ($UpdateLatestNet) {
        Writelog "`$UpdateLatestNet is set to true, checking for latest .NET Framework"
        if ($installationType -eq 'Client') {
        $Name = "Cumulative update for .net framework windows $WindowsRelease $WindowsVersion $WindowsArch -preview"
        }
        if ($WindowsRelease -eq 2022) {
            $Name = """Cumulative Update for .NET Framework 3.5, 4.8 and 4.8.1"" " + """operating system version 21H2 for x64"""
        }
        if ($WindowsRelease -eq 2019) {
            $Name = """Cumulative Update for .NET Framework 3.5, 4.7.2 and 4.8 for Windows Server 2019 for x64"""
        }
        if ($WindowsRelease -eq 2016) {
            $Name = """Cumulative Update for .NET Framework 4.8 for Windows Server 2016 for x64"""
        }
        #Check if $KBPath exists, if not, create it
        If (-not (Test-Path -Path $KBPath)) {
            WriteLog "Creating $KBPath"
            New-Item -Path $KBPath -ItemType Directory -Force | Out-Null
        }
        WriteLog "Searching for $name from Microsoft Update Catalog and saving to $KBPath"
        $KBFilePath = Save-KB -Name $Name -Path $KBPath
        WriteLog "Latest .NET saved to $KBPath\$KBFilePath"
    }
    # #Update Latest Security Platform Update
    # if ($UpdateSecurityPlatform) {
    #     WriteLog "`$UpdateSecurityPlatform is set to true, checking for latest Security Platform Update"
    #     $Name = "Windows Security platform definition updates"
    #     #Check if $KBPath exists, if not, create it
    #     If (-not (Test-Path -Path $KBPath)) {
    #         WriteLog "Creating $KBPath"
    #         New-Item -Path $KBPath -ItemType Directory -Force | Out-Null
    #     }
    #     WriteLog "Searching for $Name from Microsoft Update Catalog and saving to $KBPath"
    #     $KBFilePath = Save-KB -Name $Name -Path $KBPath
    #     WriteLog "Latest Security Platform Update saved to $KBPath\$KBFilePath"
    # }

    #Search for cached VHDX and skip VHDX creation if there's a cached version
    if ($AllowVHDXCaching) {
        if (Test-Path -Path $VHDXCacheFolder) {
            $vhdxJsons = @(Get-ChildItem -File -Path $VHDXCacheFolder -Filter "*_config.json" | Sort-Object -Property CreationTime -Descending)
            $downloadedKBs = @(Get-ChildItem -File -Path $KBPath)
            #$jsonDeserializer = [System.Web.Script.Serialization.JavaScriptSerializer]::new()

            foreach ($vhdxJson in $vhdxJsons) {
                try {
                    #$vhdxCacheItem = $jsonDeserializer.Deserialize((Get-Content -Path $vhdxJson.FullName -Raw), [VhdxCacheItem])
                    $vhdxCacheItem = Get-Content -Path $vhdxJson.FullName -Raw | ConvertFrom-Json

                    if ((($vhdxCacheItem.WindowsSKU -ne $WindowsSKU) -or
                        ([string]::IsNullOrEmpty($vhdxCacheItem.WindowsSKU) -xor [string]::IsNullOrEmpty($WindowsSKU)))) {
                        WriteLog "WindowsSKU not equal"
                        continue
                    }

                    if ((($vhdxCacheItem.WindowsRelease -ne $WindowsRelease) -or
                        ([string]::IsNullOrEmpty($vhdxCacheItem.WindowsRelease) -xor [string]::IsNullOrEmpty($WindowsRelease)))) {
                        WriteLog "WindowsRelease not equal"
                        continue
                    }

                    if ((($vhdxCacheItem.WindowsVersion -ne $WindowsVersion) -or
                        ([string]::IsNullOrEmpty($vhdxCacheItem.WindowsVersion) -xor [string]::IsNullOrEmpty($WindowsVersion)))) {
                        WriteLog "WindowsVersion not equal"
                        continue
                    }

                    if ((($vhdxCacheItem.OptionalFeatures -ne $OptionalFeatures) -or
                        ([string]::IsNullOrEmpty($vhdxCacheItem.OptionalFeatures) -xor [string]::IsNullOrEmpty($OptionalFeatures)))) {
                        WriteLog "OptionalFeatures not equal"
                        continue
                    }

                    if ((Compare-Object -ReferenceObject $downloadedKBs -DifferenceObject $vhdxCacheItem.IncludedUpdates -Property Name).Length -gt 0) {
                        (Compare-Object -ReferenceObject $downloadedKBs -DifferenceObject $vhdxCacheItem.IncludedUpdates -Property Name)
                        $downloadedKBs.Name
                        $vhdxCacheItem.IncludedUpdates.Name
                        WriteLog "Updates not equal"
                        continue
                    }

                    WriteLog "Found cached VHDX file with same parameters and patches"
                    $cachedVHDXFileFound = $true
                    $cachedVHDXInfo = $vhdxCacheItem
                    break
                } catch {
                    WriteLog "Reading $vhdxJson Failed with error $_"
                }
            }
        }
    }
    
    if (-Not $cachedVHDXFileFound) {
    if ($ISOPath) {
        $wimPath = Get-WimFromISO
    }
    else {
        $wimPath = Get-WindowsESD -WindowsRelease $WindowsRelease -WindowsArch $WindowsArch -WindowsLang $WindowsLang -MediaType $mediaType
    }
    #If index not specified by user, try and find based on WindowsSKU
    if (-not($index) -and ($WindowsSKU)) {
        $index = Get-Index -WindowsImagePath $wimPath -WindowsSKU $WindowsSKU
    }

    $vhdxDisk = New-ScratchVhdx -VhdxPath $VHDXPath -SizeBytes $disksize -LogicalSectorSizeBytes $LogicalSectorSizeBytes

    $systemPartitionDriveLetter = New-SystemPartition -VhdxDisk $vhdxDisk
    
    New-MSRPartition -VhdxDisk $vhdxDisk
    
    $osPartition = New-OSPartition -VhdxDisk $vhdxDisk -OSPartitionSize $OSPartitionSize -WimPath $WimPath -WimIndex $index
    $osPartitionDriveLetter = $osPartition[1].DriveLetter
    $WindowsPartition = $osPartitionDriveLetter + ":\"

    #$recoveryPartition = New-RecoveryPartition -VhdxDisk $vhdxDisk -OsPartition $osPartition[1] -RecoveryPartitionSize $RecoveryPartitionSize -DataPartition $dataPartition
    $recoveryPartition = New-RecoveryPartition -VhdxDisk $vhdxDisk -OsPartition $osPartition[1] -RecoveryPartitionSize $RecoveryPartitionSize -DataPartition $dataPartition

    WriteLog "All necessary partitions created."

    Add-BootFiles -OsPartitionDriveLetter $osPartitionDriveLetter -SystemPartitionDriveLetter $systemPartitionDriveLetter[1]

    if ($UpdateLatestCU -or $UpdateLatestNet -or $UpdatePreviewCU ) {
        #Check if $KBCachePath exists, if not, create it
        if ($AllowUpdateCaching) {
            if (-not (Test-Path -Path $KBCachePath)) {
                WriteLog "Creating $KBCachePath"
                New-Item -Path $KBCachePath -ItemType Directory -Force | Out-Null
            }
        }
    }

    
    
    #Add Windows packages
    if ($UpdateLatestCU -or $UpdateLatestNet -or $UpdatePreviewCU ) {
        try {
            WriteLog "Adding KBs to $WindowsPartition"
            WriteLog 'This can take 10+ minutes depending on how old the media is and the size of the KB. Please be patient'
            # If WindowsRelease is 2016, we need to add the SSU first
            if ($WindowsRelease -eq 2016) {
                WriteLog "WindowsRelease is 2016, adding SSU first"
                WriteLog "Adding SSU to $WindowsPartition"
                # Add-WindowsPackage -Path $WindowsPartition -PackagePath $SSUFilePath -PreventPending | Out-Null
                # Commenting out -preventpending as it causes an issue with the SSU being applied
                # Seems to be because of the registry being mounted per dism.log
                Add-WindowsPackage -Path $WindowsPartition -PackagePath $SSUFilePath | Out-Null
                WriteLog "SSU added to $WindowsPartition"
                WriteLog "Removing $SSUFilePath"
                Remove-Item -Path $SSUFilePath -Force | Out-Null
                WriteLog 'SSU removed'
                WriteLog "Adding CU to $WindowsPartition"
            }
            # Add-WindowsPackage -Path $WindowsPartition -PackagePath $KBPath -PreventPending | Out-Null
            Add-WindowsPackage -Path $WindowsPartition -PackagePath $KBPath | Out-Null
            WriteLog "KBs added to $WindowsPartition"
            if ($AllowUpdateCaching) {
                WriteLog "Copying downloaded KBs from $KBPath to $KBCachePath"
                Robocopy.exe $($KBPath) $($KBCachePath) /E /COPY:DAT /R:5 /W:5 /J
                WriteLog "Copy complete"
            }
            if ($AllowVHDXCaching) {
                $cachedVHDXInfo = [VhdxCacheItem]::new()
                $includedUpdates = Get-ChildItem -Path $KBPath -File
                
                foreach ($includedUpdate in $includedUpdates) {
                    $cachedVHDXInfo.IncludedUpdates += ([VhdxCacheUpdateItem]::new($includedUpdate.Name))
                }
            }
            WriteLog "Removing $KBPath"
            Remove-Item -Path $KBPath -Recurse -Force | Out-Null
            WriteLog "Clean Up the WinSxS Folder"
            WriteLog 'This can take 10+ minutes depending on how old the media is and the size of the KB. Please be patient'
            Dism /Image:$WindowsPartition /Cleanup-Image /StartComponentCleanup /ResetBase | Out-Null
            WriteLog "Clean Up the WinSxS Folder completed"
        }
        catch {
            Write-Host "Adding KB to VHDX failed with error $_"
            WriteLog "Adding KB to VHDX failed with error $_"
            if ($_.Exception.HResult -eq -2146498525){
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
        $Source = Join-Path (Split-Path $wimpath) "sxs"
        Enable-WindowsFeaturesByName -FeatureNames $OptionalFeatures -Source $Source
    }    
    
    } else {
        #Use cached vhdx file
        WriteLog "Using cached VHDX file to speed up build proces"
        WriteLog "VHDX file is: $($cachedVHDXInfo.VhdxFileName)"

        Robocopy.exe $($VHDXCacheFolder) $($VMPath) $($cachedVHDXInfo.VhdxFileName) /E /COPY:DAT /R:5 /W:5 /J
        $VHDXPath = Join-Path $($VMPath) $($cachedVHDXInfo.VhdxFileName)

        $vhdxDisk = Get-VHD -Path $VHDXPath | Mount-VHD -Passthru | Get-Disk
        $osPartition = $vhdxDisk | Get-Partition | Where-Object { $_.GptType -eq "{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}" }
        $osPartitionDriveLetter = $osPartition.DriveLetter
        $WindowsPartition = $osPartitionDriveLetter + ":\"

    }

    #Set Product key
    If ($ProductKey) {
        WriteLog "Setting Windows Product Key"
        Set-WindowsProductKey -Path $WindowsPartition -ProductKey $ProductKey
    }
    If ($ISOPath) {
        WriteLog 'Dismounting Windows ISO'
        Dismount-DiskImage -ImagePath $ISOPath | Out-null
        WriteLog 'Done'
    }
    else {
        #Remove ESD file
        Remove-Item -Path $wimPath -Force
    }
    

    If ($InstallApps) {
        #Copy Unattend file so VM Boots into Audit Mode
        WriteLog 'Copying unattend file to boot to audit mode'
        New-Item -Path "$($osPartitionDriveLetter):\Windows\Panther\unattend" -ItemType Directory -Force | Out-Null
        if($WindowsArch -eq 'x64'){
            Copy-Item -Path "$FFUDevelopmentPath\BuildFFUUnattend\unattend_x64.xml" -Destination "$($osPartitionDriveLetter):\Windows\Panther\Unattend\Unattend.xml" -Force | Out-Null
        }
        else {
            Copy-Item -Path "$FFUDevelopmentPath\BuildFFUUnattend\unattend_arm64.xml" -Destination "$($osPartitionDriveLetter):\Windows\Panther\Unattend\Unattend.xml" -Force | Out-Null
        }
        WriteLog 'Copy completed'
    }

    if ($AllowVHDXCaching -and !$cachedVHDXFileFound) {
        WriteLog 'New cachabe VHDX created'

        WriteLog 'Defragmenting Windows partition...'
        Optimize-Volume -DriveLetter $osPartition.DriveLetter -Defrag -NormalPriority -Verbose 
        WriteLog 'Performing slab consolidation on Windows partition...'
        Optimize-Volume -DriveLetter $osPartition.DriveLetter -SlabConsolidate -NormalPriority -Verbose
        WriteLog 'Dismounting VHDX'
        Dismount-ScratchVhdx -VhdxPath $VHDXPath

        WriteLog 'Copying to cache dir'

        #Assuming there are now name collisons
        Robocopy.exe $($VMPath) $($VHDXCacheFolder) $("$VMName.vhdx") /E /COPY:DAT /R:5 /W:5 /J

        #Only create new instance if not created during patching
        if ($null -eq $cachedVHDXInfo) {
            $cachedVHDXInfo = [VhdxCacheItem]::new()
        }
        $cachedVHDXInfo.VhdxFileName = $("$VMName.vhdx")
        $cachedVHDXInfo.WindowsSKU = $WindowsSKU
        $cachedVHDXInfo.WindowsRelease = $WindowsRelease
        $cachedVHDXInfo.WindowsVersion = $WindowsVersion
        $cachedVHDXInfo.OptionalFeatures = $OptionalFeatures
        
        $cachedVHDXInfo | ConvertTo-Json | Out-File -FilePath ("{0}\{1}_config.json" -f $($VHDXCacheFolder), $VMName)
    } else {
        Dismount-ScratchVhdx -VhdxPath $VHDXPath
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

#If installing apps (Office or 3rd party), we need to build a VM and capture that FFU, if not, just cut the FFU from the VHDX file
if ($InstallApps) {
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
        do {
            $FFUVM = Get-VM -Name $FFUVM.Name
            Start-Sleep -Seconds 10
            WriteLog 'Waiting for VM to shutdown'
        } while ($FFUVM.State -ne 'Off')
        WriteLog 'VM Shutdown'
        Optimize-FFUCaptureDrive -VhdxPath $VHDXPath
        #Capture FFU file
        New-FFU $FFUVM.Name
    }
    else {
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
    #Clean up InstallAppsandSysprep.cmd
    try {
        WriteLog "Cleaning up $AppsPath\InstallAppsandSysprep.cmd"
        Clear-InstallAppsandSysprep
    }
    catch {
        Write-Host 'Cleaning up InstallAppsandSysprep.cmd failed'
        Writelog "Cleaning up InstallAppsandSysprep.cmd failed with error $_"
        throw $_
    }
    try {
        if (Test-Path -Path "$AppsPath\Win32" -PathType Container) {
            WriteLog "Cleaning up Win32 folder"
            Remove-Item -Path "$AppsPath\Win32" -Recurse -Force
        }
        if (Test-Path -Path "$AppsPath\MSStore" -PathType Container) {
            WriteLog "Cleaning up MSStore folder"
            Remove-Item -Path "$AppsPath\MSStore" -Recurse -Force
        }
    }
    catch {
        WriteLog "$_"
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

# #Clean up InstallAppsandSysprep.cmd
# try {
#     WriteLog "Cleaning up $AppsPath\InstallAppsandSysprep.cmd"
#     Clear-InstallAppsandSysprep
# }
# catch {
#     Write-Host 'Cleaning up InstallAppsandSysprep.cmd failed'
#     Writelog "Cleaning up InstallAppsandSysprep.cmd failed with error $_"
#     throw $_
# }
# try {
#     if (Test-Path -Path "$AppsPath\Win32" -PathType Container) {
#         WriteLog "Cleaning up Win32 folder"
#         Remove-Item -Path "$AppsPath\Win32" -Recurse -Force
#     }
#     if (Test-Path -Path "$AppsPath\MSStore" -PathType Container) {
#         WriteLog "Cleaning up MSStore folder"
#         Remove-Item -Path "$AppsPath\MSStore" -Recurse -Force
#     }
# }
# catch {
#     WriteLog "$_"
#     throw $_
# }
#Create Deployment Media
If ($CreateDeploymentMedia) {
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
    try {
        If (Test-Path -Path $DeployISO) {
            New-DeploymentUSB -CopyFFU
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
        Remove-FFU
    }
    catch {
        Write-Host 'Removing FFU files failed'
        Writelog "Removing FFU files failed with error $_"
        throw $_
    }
   
}
If ($CleanupCaptureISO) {
    try {
        If (Test-Path -Path $CaptureISO) {
            WriteLog "Removing $CaptureISO"
            Remove-Item -Path $CaptureISO -Force
            WriteLog "Removal complete"
        }     
    }
    catch {
        Writelog "Removing $CaptureISO failed with error $_"
        throw $_
    }
}
If ($CleanupDeployISO) {
    try {
        If (Test-Path -Path $DeployISO) {
            WriteLog "Removing $DeployISO"
            Remove-Item -Path $DeployISO -Force
            WriteLog "Removal complete"
        }     
    }
    catch {
        Writelog "Removing $DeployISO failed with error $_"
        throw $_
    }
}
If ($CleanupAppsISO) {
    try {
        If (Test-Path -Path $AppsISO) {
            WriteLog "Removing $AppsISO"
            Remove-Item -Path $AppsISO -Force
            WriteLog "Removal complete"
        }     
    }
    catch {
        Writelog "Removing $AppsISO failed with error $_"
        throw $_
    }
If ($CleanupDrivers){
    try {
        If (Test-Path -Path $Driversfolder\$Make) {
            WriteLog "Removing $Driversfolder\$Make"
            Remove-Item -Path $Driversfolder\$Make -Force -Recurse
            WriteLog "Removal complete"
        }     
    }
    catch {
        Writelog "Removing $Driversfolder\$Make failed with error $_"
        throw $_
    }

}
}
#Clean up dirty.txt file
Remove-Item -Path .\dirty.txt -Force | out-null
if ($VerbosePreference -ne 'Continue'){
    Write-Host 'Script complete'
}
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

if ($VerbosePreference -ne 'Continue'){
    Write-Host $runTimeFormatted
}
WriteLog 'Script complete'
WriteLog $runTimeFormatted
