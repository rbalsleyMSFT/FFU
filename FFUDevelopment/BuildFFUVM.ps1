
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

.PARAMETER UpdateLatestNet
When set to $true, will download and install the latest .NET Framework for Windows 10/11. Default is $false.

.PARAMETER UpdateLatestDefender
When set to $true, will download and install the latest Windows Defender definitions and Defender platform update. Default is $false.

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
    [ValidateScript({
            $allowedSKUs = @('Home', 'Home N', 'Home Single Language', 'Education', 'Education N', 'Pro', 'Pro N', 'Pro Education', 'Pro Education N', 'Pro for Workstations', 'Pro N for Workstations', 'Enterprise', 'Enterprise N')
            if ($allowedSKUs -contains $_) { $true } else { throw "Invalid WindowsSKU value. Allowed values: $($allowedSKUs -join ', ')" }
            return $true
        })]
    [string]$WindowsSKU = 'Pro',
    [ValidateScript({ Test-Path $_ })]
    [string]$FFUDevelopmentPath = $PSScriptRoot,
    [bool]$InstallApps,
    [bool]$InstallOffice,
    [Parameter(Mandatory = $false)]
    [ValidateScript({
            if ($_ -and (!(Test-Path -Path '.\Drivers') -or ((Get-ChildItem -Path '.\Drivers' -Recurse | Measure-Object -Property Length -Sum).Sum -lt 1MB))) {
                throw 'InstallDrivers is set to $true, but either the Drivers folder is missing or empty'
            }
            return $true
        })]
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
    [ValidateSet(10, 11)]
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
            if ($_ -and (!(Test-Path -Path '.\Drivers') -or ((Get-ChildItem -Path '.\Drivers' -Recurse | Measure-Object -Property Length -Sum).Sum -lt 1MB))) {
                throw 'CopyDrivers is set to $true, but either the Drivers folder is missing or empty'
            }
            return $true
        })]
    [bool]$CopyDrivers,
    [bool]$CopyPEDrivers,
    [bool]$RemoveFFU,
    [bool]$UpdateLatestCU,
    [bool]$UpdateLatestNet,
    [bool]$UpdateLatestDefender,
    [bool]$UpdateEdge,
    [bool]$UpdateOneDrive,
    [bool]$CopyPPKG,
    [bool]$CopyUnattend,
    [bool]$CopyAutopilot,
    [bool]$CompactOS = $true,
    [bool]$CleanupCaptureISO = $true,
    [bool]$CleanupDeployISO = $true,
    [bool]$CleanupAppsISO = $true
)
$version = '2404.2'

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
if (-not $DeployISO) { $DeployISO = "$FFUDevelopmentPath\WinPE_FFU_Deploy.iso" }
if (-not $CaptureISO) { $CaptureISO = "$FFUDevelopmentPath\WinPE_FFU_Capture.iso" }
if (-not $OfficePath) { $OfficePath = "$AppsPath\Office" }
if (-not $rand) { $rand = Get-Random }
if (-not $VMLocation) { $VMLocation = "$FFUDevelopmentPath\VM" }
if (-not $VMName) { $VMName = "$FFUPrefix-$rand" }
if (-not $VMPath) { $VMPath = "$VMLocation\$VMName" }
if (-not $VHDXPath) { $VHDXPath = "$VMPath\$VMName.vhdx" }
if (-not $FFUCaptureLocation) { $FFUCaptureLocation = "$FFUDevelopmentPath\FFU" }
if (-not $LogFile) { $LogFile = "$FFUDevelopmentPath\FFUDevelopment.log" }
if (-not $KBPath) { $KBPath = "$FFUDevelopmentPath\KB" }
if (-not $DefenderPath) { $DefenderPath = "$AppsPath\Defender" }
if (-not $OneDrivePath) { $OneDrivePath = "$AppsPath\OneDrive" }
if (-not $EdgePath) { $EdgePath = "$AppsPath\Edge" }

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
        $ADKWebPage = Invoke-RestMethod "https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install"
        
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
        $FWLinkRequest = Invoke-WebRequest -Uri $ADKFWLink -Method Head -MaximumRedirection 0 -ErrorAction SilentlyContinue

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
        Start-BitsTransfer -Source $ADKUrl -Destination $installerLocation -ErrorAction Stop
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
        $adkWebPage = Invoke-RestMethod "https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install"
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
        [ValidateSet('x86', 'x64')]
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
    else {
        'https://go.microsoft.com/fwlink/?LinkId=2156292'
    }

    # Download cab file
    WriteLog "Downloading Cab file"
    $cabFilePath = Join-Path $PSScriptRoot "tempCabFile.cab"
    Invoke-WebRequest -Uri $cabFileUrl -OutFile $cabFilePath
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
                Invoke-WebRequest -Uri $file.FilePath -OutFile $esdFilePath
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

    [String]$MSWebPage = Invoke-RestMethod 'https://www.microsoft.com/en-us/download/confirmation.aspx?id=49117'
  
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
    Invoke-WebRequest -Uri $ODTUrl -OutFile $ODTInstallFile

    # Extract ODT
    WriteLog "Extracting ODT to $OfficePath"
    # Start-Process -FilePath $ODTInstallFile -ArgumentList "/extract:$OfficePath /quiet" -Wait
    Invoke-Process $ODTInstallFile "/extract:$OfficePath /quiet"

    # Run setup.exe with config.xml and modify xml file to download to $OfficePath
    $ConfigXml = "$OfficePath\DownloadFFU.xml"
    $xmlContent = [xml](Get-Content $ConfigXml)
    $xmlContent.Configuration.Add.SourcePath = $OfficePath
    $xmlContent.Save($ConfigXml)
    WriteLog "Downloading M365 Apps/Office to $OfficePath"
    # Start-Process -FilePath "$OfficePath\setup.exe" -ArgumentList "/download $ConfigXml" -Wait
    Invoke-Process $OfficePath\setup.exe "/download $ConfigXml"

    WriteLog "Cleaning up ODT default config files and checking InstallAppsandSysprep.cmd file for proper command line"
    #Clean up default configuration files
    Remove-Item -Path "$OfficePath\configuration*" -Force

    #Read the contents of the InstallAppsandSysprep.cmd file
    $content = Get-Content -Path "$AppsPath\InstallAppsandSysprep.cmd"
        
    #Update the InstallAppsandSysprep.cmd file with the Office install command
    $officeCommand = "d:\Office\setup.exe /configure d:\Office\DeployFFU.xml"

    # Check if Office command is not commented out or missing and fix it if it is
    if ($content[2] -ne $officeCommand) {
        $content[2] = $officeCommand

        # Write the modified content back to the file
        Set-Content -Path "$AppsPath\InstallAppsandSysprep.cmd" -Value $content
    }
}
function Get-KBLink {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )
    $results = Invoke-WebRequest -Uri "http://www.catalog.update.microsoft.com/Search.aspx?q=$Name"
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
        $links = Invoke-WebRequest -Uri 'https://www.catalog.update.microsoft.com/DownloadDialog.aspx' -Method Post -Body $body |
        Select-Object -ExpandProperty Content |
        Select-String -AllMatches -Pattern "http[s]?://[^']*\.microsoft\.com/[^']*|http[s]?://[^']*\.windowsupdate\.com/[^']*" |
        Select-Object -Unique

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
        [ValidateSet(10, 11)]
        [int]$WindowsRelease
    )
        
    # Define the URL of the update history page based on the Windows release
    if ($WindowsRelease -eq 11) {
        $updateHistoryUrl = 'https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information'
    }
    else {
        $updateHistoryUrl = 'https://learn.microsoft.com/en-us/windows/release-health/release-information'
    }
        
    # Use Invoke-WebRequest to fetch the content of the page
    $response = Invoke-WebRequest -Uri $updateHistoryUrl
        
    # Use a regular expression to find the KB article number
    $kbArticleRegex = 'KB\d+'
    $kbArticle = [regex]::Match($response.Content, $kbArticleRegex).Value
        
    return $kbArticle
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
            #Check if $WindowsArch is an array
            if ($WindowsArch -is [array]) { 
                #Some file names include either x64 or amd64
                if ($link -match $WindowsArch[0] -or $link -match $WindowsArch[1]) {
                    Start-BitsTransfer -Source $link -Destination $Path
                    $fileName = ($link -split '/')[-1]
                    break
                }
                # elseif (!($link -match 'x64' -or $link -match 'amd64' -or $link -match 'x86' -or $link -match 'arm64')) {
                #     Write-Host "No architecture found in $link, assume it's for all architectures"
                #     Start-BitsTransfer -Source $link -Destination $Path
                #     $fileName = ($link -split '/')[-1]
                #     break
                # }
                elseif (!($link -match 'x64' -or $link -match 'amd64' -or $link -match 'x86' -or $link -match 'arm64')) {
                    WriteLog "No architecture found in $link, assume this is for all architectures"
                    #FIX: 3/22/2024 - the SecurityHealthSetup fix was updated and now includes two files (one is x64 and the other is arm64)
                    #Unfortunately there is no easy way to determine the architecture from the file name
                    #There is a support doc that include links to download, but it's out of date (n-1)
                    #https://support.microsoft.com/en-us/topic/windows-security-update-a6ac7d2e-b1bf-44c0-a028-41720a242da3
                    #These files don't change that often, so will check the link above to see when it updates and may use that
                    #For now this is hard-coded for these specific file names
                    if ($link -match 'security'){
                        #Make sure we're getting the correct architecture for the Security Health Setup update
                        if ($WindowsArch -eq 'x64'){
                            if ($link -match 'securityhealthsetup_e1'){
                                Start-BitsTransfer -Source $link -Destination $Path
                                $fileName = ($link -split '/')[-1]
                                break
                            }
                        }
                        elseif ($WindowsArch -eq 'arm64'){
                            if ($link -match 'securityhealthsetup_25'){
                                Start-BitsTransfer -Source $link -Destination $Path
                                $fileName = ($link -split '/')[-1]
                                break
                            }
                        }
                        continue
                    }
                    Start-BitsTransfer -Source $link -Destination $Path
                    $fileName = ($link -split '/')[-1]
                }
            }
            else {
                if ($link -match $WindowsArch) {
                    Start-BitsTransfer -Source $link -Destination $Path
                    $fileName = ($link -split '/')[-1]
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
            'Home_N' { 2 }
            'Home_SL' { 3 }
            'EDU' { 4 }
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
        $imageIndex = $imageIndexes | Where-Object ImageIndex -eq 1
        $WindowsImage = $imageIndex.ImageName.Substring(0, 10)
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
        # Look for either the number 10 or 11 in the ImageName
        $relevantImageIndexes = $imageIndexes | Where-Object { ($_.ImageName -like "*10*") -or ($_.ImageName -like "*11*") }
            
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
    if ($CompactOS) {
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
        $winReWim = Get-ChildItem "$($OsPartition.DriveLetter):\Windows\System32\Recovery\Winre.wim"

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
    & cmd /c """$DandIEnv"" && copype amd64 $WinPEFFUPath" | Out-Null
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

    $PackagePathBase = "$adkPath`Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs\"

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
        Remove-Item -Path "$WinPEFFUPath\media\boot\bootfix.bin" -Force | Out-null
        $WinPEISOName = 'WinPE_FFU_Capture.iso'
        $Capture = $false
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
        $WinPEISOName = 'WinPE_FFU_Deploy.iso'
        $Deploy = $false
    }
    WriteLog 'Dismounting WinPE media' 
    Dismount-WindowsImage -Path "$WinPEFFUPath\mount" -Save | Out-Null
    WriteLog 'Dismount complete'
    #Make ISO
    $OSCDIMGPath = "$adkPath`Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg"
    $OSCDIMG = "$OSCDIMGPath\oscdimg.exe"
    WriteLog "Creating WinPE ISO at $FFUDevelopmentPath\$WinPEISOName"
    # & "$OSCDIMG" -m -o -u2 -udfver102 -bootdata:2`#p0,e,b$OSCDIMGPath\etfsboot.com`#pEF,e,b$OSCDIMGPath\Efisys_noprompt.bin $WinPEFFUPath\media $FFUDevelopmentPath\$WinPEISOName | Out-null
    Invoke-Process $OSCDIMG "-m -o -u2 -udfver102 -bootdata:2`#p0,e,b`"$OSCDIMGPath\etfsboot.com`"`#pEF,e,b`"$OSCDIMGPath\Efisys_noprompt.bin`" `"$WinPEFFUPath\media`" `"$FFUDevelopmentPath\$WinPEISOName`""
    WriteLog "ISO created successfully"
    WriteLog "Cleaning up $WinPEFFUPath"
    Remove-Item -Path "$WinPEFFUPath" -Recurse -Force
    WriteLog 'Cleanup complete'
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
            Add-WindowsDriver -Path "$FFUDevelopmentPath\Mount" -Driver "$FFUDevelopmentPath\Drivers" -Recurse -ErrorAction SilentlyContinue | Out-null
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
    $DisplayVersion = Get-ItemPropertyValue -Path 'HKLM:\FFU\Microsoft\Windows NT\CurrentVersion\' -Name 'DisplayVersion'
    WriteLog "Windows Version: $DisplayVersion"
    $BuildDate = Get-Date -uformat %b%Y

    $SKU = switch ($SKU) {
        Core { 'Home' }
        Professional { 'Pro' }
        ProfessionalEducation { 'Pro_Edu' }
        Enterprise { 'Ent' }
        Education { 'Edu' }
        ProfessionalWorkstation { 'Pro_Wks' }
    }
    WriteLog "Windows SKU Modified to: $SKU"

    if ($CurrentBuild -ge 22000) {
        $Name = 'Win11'
    }
    else {
        $Name = 'Win10'
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
    $USBDrives = (Get-WmiObject -Class Win32_DiskDrive -Filter "MediaType='Removable Media'")
    If ($USBDrives -and ($null -eq $USBDrives.count)) {
        $USBDrivesCount = 1
    }
    else {
        $USBDrivesCount = $USBDrives.Count
    }
    WriteLog "Found $USBDrivesCount USB drives"

    if ($null -eq $USBDrives) {
        WriteLog "No removable USB drive found. Exiting"
        Write-Error "No removable USB drive found. Exiting"
        exit 1
    }
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

    if ($CopyFFU.IsPresent) {
        $FFUFiles = Get-ChildItem -Path "$BuildUSBPath\FFU" -Filter "*.ffu"

        if ($FFUFiles.Count -eq 1) {
            $SelectedFFUFile = $FFUFiles.FullName
        }
        elseif ($FFUFiles.Count -gt 1) {
            WriteLog 'Found multiple FFU files'
            for ($i = 0; $i -lt $FFUFiles.Count; $i++) {
                WriteLog ("{0}: {1}" -f ($i + 1), $FFUFiles[$i].Name)
            }
            $inputChoice = Read-Host "Enter the number corresponding to the FFU file you want to copy or 'A' to copy all FFU files"
            
            if ($inputChoice -eq 'A') {
                $SelectedFFUFile = $FFUFiles.FullName
            }
            elseif ($inputChoice -ge 1 -and $inputChoice -le $FFUFiles.Count) {
                $selectedIndex = $inputChoice - 1
                $SelectedFFUFile = $FFUFiles[$selectedIndex].FullName
            }
            WriteLog "$SelectedFFUFile was selected"
        }
        else {
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
            Clear-Disk -Number $DiskNumber -RemoveData -RemoveOEM -Confirm:$false
            Get-Disk $DiskNumber | Get-Partition | Remove-Partition
            $Disk = Get-Disk -Number $DiskNumber
            $Disk | Set-Disk -PartitionStyle MBR
            $BootPartition = $Disk | New-Partition -Size 2GB -IsActive -AssignDriveLetter
            $DeployPartition = $Disk | New-Partition -UseMaximumSize -AssignDriveLetter
            Format-Volume -Partition $BootPartition -FileSystem FAT32 -NewFileSystemLabel "TempBoot" -Confirm:$false
            Format-Volume -Partition $DeployPartition -FileSystem NTFS -NewFileSystemLabel "TempDeploy" -Confirm:$false
        }

        WriteLog 'Partitioning USB Drive'
        Invoke-Command -ScriptBlock $ScriptBlock -ArgumentList $DiskNumber | Out-null
        WriteLog 'Done'

        $BootPartitionDriveLetter = (Get-WmiObject -Class win32_volume -Filter "Label='TempBoot' AND DriveType=2 AND DriveLetter IS NOT NULL").Name
        $ISOMountPoint = (Mount-DiskImage -ImagePath $DeployISO -PassThru | Get-Volume).DriveLetter + ":\"
        WriteLog "Copying WinPE files to $BootPartitionDriveLetter"
        robocopy "$ISOMountPoint" "$BootPartitionDriveLetter" /E /COPYALL /R:5 /W:5 /J
        Dismount-DiskImage -ImagePath $DeployISO | Out-Null

        if ($CopyFFU.IsPresent) {
            if ($null -ne $SelectedFFUFile) {
                $DeployPartitionDriveLetter = (Get-WmiObject -Class win32_volume -Filter "Label='TempDeploy' AND DriveType=2 AND DriveLetter IS NOT NULL").Name
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
                    robocopy "$FFUDevelopmentPath\Drivers" "$DeployPartitionDriveLetter\Drivers" /E /R:5 /W:5 /J
                }
                #Copy Unattend folder in the FFU folder to the USB drive. Can use copy-item as it's a small folder
                if ($CopyUnattend) {
                    WriteLog "Copying Unattend folder to $DeployPartitionDriveLetter"
                    Copy-Item -Path "$FFUDevelopmentPath\Unattend" -Destination $DeployPartitionDriveLetter -Recurse -Force
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
            Dismount-WindowsImage -Path $mountPath -discard | Out-null
            WriteLog "Successfully dismounted image at $mountPath"
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
    #Clean up $KBPath
    If (Test-Path -Path $KBPath) {
        WriteLog "Removing $KBPath"
        Remove-Item -Path $KBPath -Recurse -Force
        WriteLog 'Removal complete'
    }
    #Clean up $DefenderPath
    If (Test-Path -Path $DefenderPath) {
        WriteLog "Removing $DefenderPath"
        Remove-Item -Path $DefenderPath -Recurse -Force
        WriteLog 'Removal complete'
    }
    #Clean up $OneDrivePath
    If (Test-Path -Path $OneDrivePath) {
        WriteLog "Removing $OneDrivePath"
        Remove-Item -Path $OneDrivePath -Recurse -Force
        WriteLog 'Removal complete'
    }
    #Clean up $EdgePath
    If (Test-Path -Path $EdgePath) {
        WriteLog "Removing $EdgePath"
        Remove-Item -Path $EdgePath -Recurse -Force
        WriteLog 'Removal complete'
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
    if ($UpdateLatestDefender) {
        WriteLog "Updating $AppsPath\InstallAppsandSysprep.cmd to remove Defender Platform Update"
        $CmdContent = Get-Content -Path "$AppsPath\InstallAppsandSysprep.cmd"
        $CmdContent -notmatch 'd:\\Defender*' | Set-Content -Path "$AppsPath\InstallAppsandSysprep.cmd"
        #Remove $DefenderPath
        WriteLog "Removing $DefenderPath"
        Remove-Item -Path $DefenderPath -Recurse -Force
        WriteLog "Removal complete"

    }
    if ($UpdateOneDrive) {
        WriteLog "Updating $AppsPath\InstallAppsandSysprep.cmd to remove OneDrive install"
        $CmdContent = Get-Content -Path "$AppsPath\InstallAppsandSysprep.cmd"
        $CmdContent -notmatch 'd:\\OneDrive*' | Set-Content -Path "$AppsPath\InstallAppsandSysprep.cmd"
        #Remove $OneDrivePath
        WriteLog "Removing $OneDrivePath"
        Remove-Item -Path $OneDrivePath -Recurse -Force
        WriteLog "Removal complete"  
    }
    if ($UpdateEdge) {
        WriteLog "Updating $AppsPath\InstallAppsandSysprep.cmd to remove Edge install"
        $CmdContent = Get-Content -Path "$AppsPath\InstallAppsandSysprep.cmd"
        $CmdContent -notmatch 'd:\\Edge*' | Set-Content -Path "$AppsPath\InstallAppsandSysprep.cmd"
        #Remove $EdgePath
        WriteLog "Removing $EdgePath"
        Remove-Item -Path $EdgePath -Recurse -Force
        WriteLog "Removal complete"
    }
}

###END FUNCTIONS

#Remove old log file if found
if (Test-Path -Path $Logfile) {
    Remove-item -Path $LogFile -Force
}
Write-Host "FFU build process has begun. This process can take 20 minutes or more. Please do not close this window or any additional windows that pop up"
Write-Host "To track progress, please open the log file $Logfile or use the -Verbose parameter next time"

WriteLog 'Begin Logging'

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
if (($InstallApps -eq $false) -and (($UpdateLatestDefender -eq $true) -or ($UpdateOneDrive -eq $true) -or ($UpdateEdge -eq $true))) {
    WriteLog 'You have selected to update Defender, OneDrive, or Edge, however you are setting InstallApps to false. These updates require the InstallApps variable to be set to true. Please set InstallApps to true and try again.'
    throw "InstallApps variable must be set to `$true to update Defender, OneDrive, or Edge"
}

#Get script variable values
LogVariableValues    

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

#Check if environment is dirty
If (Test-Path -Path "$FFUDevelopmentPath\dirty.txt") {
    Get-FFUEnvironment
}
WriteLog 'Creating dirty.txt file'
New-Item -Path .\ -Name "dirty.txt" -ItemType "file" | Out-Null

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

            #Get Windows Security platform update
            $Name = "Windows Security platform definition updates"
            WriteLog "Searching for $Name from Microsoft Update Catalog and saving to $DefenderPath"
            $KBFilePath = Save-KB -Name $Name -Path $DefenderPath
            WriteLog "Latest Security Platform Update saved to $DefenderPath\$KBFilePath"
            #Modify InstallAppsandSysprep.cmd to add in $KBFilePath on the line after REM Install Windows Security Platform Update
            WriteLog "Updating $AppsPath\InstallAppsandSysprep.cmd to include Windows Security Platform Update"
            $CmdContent = Get-Content -Path "$AppsPath\InstallAppsandSysprep.cmd"
            $UpdatedcmdContent = $CmdContent -replace '^(REM Install Windows Security Platform Update)', ("REM Install Windows Security Platform Update`r`nd:\Defender\$KBFilePath")
            Set-Content -Path "$AppsPath\InstallAppsandSysprep.cmd" -Value $UpdatedcmdContent
            WriteLog "Update complete"

            #Download latest Defender Definitions
            WriteLog "Downloading latest Defender Definitions"
            # Defender def updates can be found https://www.microsoft.com/en-us/wdsi/defenderupdates
            if ($WindowsArch -eq 'x64') {
                $DefenderDefURL = 'https://go.microsoft.com/fwlink/?LinkID=121721&arch=x64'
            }
            if ($WindowsArch -eq 'ARM64') {
                $DefenderDefURL = 'https://go.microsoft.com/fwlink/?LinkID=121721&arch=arm'
            }
            try {
                Start-BitsTransfer -Source $DefenderDefURL -Destination "$DefenderPath\mpam-fe.exe"
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
        #Download and Install OneDrive Per Machine
        if ($UpdateOneDrive) {
            #Check if $OneDrivePath exists, if not, create it
            If (-not (Test-Path -Path $OneDrivePath)) {
                WriteLog "Creating $OneDrivePath"
                New-Item -Path $OneDrivePath -ItemType Directory -Force | Out-Null
            }
            WriteLog "Downloading latest OneDrive client"
            $OneDriveURL = 'https://go.microsoft.com/fwlink/?linkid=844652'
            try {
                Start-BitsTransfer -Source $OneDriveURL -Destination "$OneDrivePath\OneDriveSetup.exe"
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
            $UpdatedcmdContent = $CmdContent -replace '^(REM Install OneDrive Per Machine)', ("REM Install OneDrive Per Machine`r`nd:\OneDrive\OneDriveSetup.exe /allusers")
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
            WriteLog "Extracting $EdgeCABFilePath"
            Invoke-Process Expand "$EdgeCABFilePath -F:*.msi $EdgeFullFilePath"
            WriteLog "Extraction complete"

            #Modify InstallAppsandSysprep.cmd to add in $KBFilePath on the line after REM Install Edge Stable
            WriteLog "Updating $AppsPath\InstallAppsandSysprep.cmd to include Edge Stable $WindowsArch release"
            $CmdContent = Get-Content -Path "$AppsPath\InstallAppsandSysprep.cmd"
            $UpdatedcmdContent = $CmdContent -replace '^(REM Install Edge Stable)', ("REM Install Edge Stable`r`nd:\Edge\$EdgeMSIFileName /quiet /norestart")
            Set-Content -Path "$AppsPath\InstallAppsandSysprep.cmd" -Value $UpdatedcmdContent
            WriteLog "Update complete"
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

    #Update latest Cumulative Update
    #Changed to use MU Catalog instead of using Get-LatestWindowsKB
    #The Windows release info page is updated later than the MU Catalog
    if ($UpdateLatestCU) {
        Writelog "`$UpdateLatestCU is set to true, checking for latest CU"
        $Name = """Cumulative update for Windows $WindowsRelease Version $WindowsVersion for $WindowsArch"""
        #Check if $KBPath exists, if not, create it
        If (-not (Test-Path -Path $KBPath)) {
            WriteLog "Creating $KBPath"
            New-Item -Path $KBPath -ItemType Directory -Force | Out-Null
        }
        WriteLog "Searching for $name from Microsoft Update Catalog and saving to $KBPath"
        $KBFilePath = Save-KB -Name $Name -Path $KBPath
        WriteLog "Latest CU saved to $KBPath\$KBFilePath"
    }


    #Update Latest .NET Framework
    if ($UpdateLatestNet) {
        Writelog "`$UpdateLatestNet is set to true, checking for latest .NET Framework"
        $Name = "Cumulative update for .net framework windows $WindowsRelease $WindowsVersion $WindowsArch -preview"
        #Check if $KBPath exists, if not, create it
        If (-not (Test-Path -Path $KBPath)) {
            WriteLog "Creating $KBPath"
            New-Item -Path $KBPath -ItemType Directory -Force | Out-Null
        }
        WriteLog "Searching for $name from Microsoft Update Catalog and saving to $KBPath"
        $KBFilePath = Save-KB -Name $Name -Path $KBPath
        WriteLog "Latest .NET saved to $KBPath\$KBFilePath"
    }
    #Update Latest Security Platform Update
    if ($UpdateSecurityPlatform) {
        WriteLog "`$UpdateSecurityPlatform is set to true, checking for latest Security Platform Update"
        $Name = "Windows Security platform definition updates"
        #Check if $KBPath exists, if not, create it
        If (-not (Test-Path -Path $KBPath)) {
            WriteLog "Creating $KBPath"
            New-Item -Path $KBPath -ItemType Directory -Force | Out-Null
        }
        WriteLog "Searching for $Name from Microsoft Update Catalog and saving to $KBPath"
        $KBFilePath = Save-KB -Name $Name -Path $KBPath
        WriteLog "Latest Security Platform Update saved to $KBPath\$KBFilePath"
    }
    
    
    #Add Windows packages
    if ($UpdateLatestCU -or $UpdateLatestNet) {
        try {
            WriteLog "Adding KBs to $WindowsPartition"
            Add-WindowsPackage -Path $WindowsPartition -PackagePath $KBPath | Out-Null
            WriteLog "KBs added to $WindowsPartition"
            WriteLog "Removing $KBPath"
            Remove-Item -Path $KBPath -Recurse -Force | Out-Null
        }
        catch {
            Write-Host "Adding KB to VHDX failed with error $_"
            WriteLog "Adding KB to VHDX failed with error $_"
            throw $_
        }  
    }


    #Enable Windows Optional Features (e.g. .Net3, etc)
    If ($OptionalFeatures) {
        $Source = Join-Path (Split-Path $wimpath) "sxs"
        Enable-WindowsFeaturesByName -FeatureNames $OptionalFeatures -Source $Source
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
        New-Item -Path "$($osPartitionDriveLetter):\Windows\Panther\unattend" -ItemType Directory | Out-Null
        Copy-Item -Path "$FFUDevelopmentPath\BuildFFUUnattend\unattend.xml" -Destination "$($osPartitionDriveLetter):\Windows\Panther\Unattend\Unattend.xml" -Force | Out-Null
        WriteLog 'Copy completed'
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
#Clean up ffu_user and Share
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
}
#Clean up dirty.txt file
Remove-Item -Path .\dirty.txt -Force | out-null
Write-Host "Script complete"
WriteLog "Script complete"