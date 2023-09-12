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
Edition of Windows 10/11 to be installed, e.g., 'Home', 'Home_N', 'Home_SL', 'EDU', 'EDU_N', 'Pro', 'Pro_N', 'Pro_EDU', 'Pro_Edu_N', 'Pro_WKS', 'Pro_WKS_N'

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

.PARAMETER WindowsArch
String value of x86 or x64. This is used to identify which architecture of Windows to download. Default is x64.

.PARAMETER WindowsLang
String value in language-region format (e.g. en-us). This is used to identify which language of media to download. Default is en-us.

.PARAMETER MediaType
String value of either business or consumer. This is used to identify which media type to download. Default is consumer.

.PARAMETER LogicalSectorBytes
unit32 value of 512 or 4096. Not recommended to change from 512. Might be useful for 4kn drives, but needs more testing. Default is 512.

.EXAMPLE
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

Command line with all parameters for reference
.\BuildFFUVM.ps1 -ISOPath "C:\path_to_iso\Windows.iso" -WindowsSKU "Pro" -FFUDevelopmentPath "C:\FFUDevelopment" -InstallApps $true -InstallOffice $true -InstallDrivers $true -Memory 8GB -Disksize 30GB -Processors 4 -VMSwitchName "Your VM Switch Name" -VMLocation "C:\VMs" -FFUPrefix "_FFU" -FFUCaptureLocation "C:\FFUDevelopment\FFU" -ShareName "FFUCaptureShare" -Username "ffu_user" -VMHostIPAddress "Your IP Address" -CreateCaptureMedia $true -CreateDeploymentMedia $false -OptionalFeatures "NetFx3;TFTP" -ProductKey "XXXXX-XXXXX-XXXXX-XXXXX-XXXXX -BuildUSBDrive $true -WindowsRelease 11 -WindowsArch 'x64' -WindowsLang 'en-us' -MediaType 'consumer' -verbose"

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
    [string]$FFUDevelopmentPath = 'C:\FFUDevelopment',
    [bool]$InstallApps,
    [bool]$InstallOffice,
    [Parameter(Mandatory = $false)]
    [ValidateScript({
            if ($_ -and (!(Test-Path -Path '.\Drivers') -or ((Get-ChildItem -Path '.\Drivers' -Recurse | Measure-Object -Property Length -Sum).Sum -lt 1MB))) {
                throw "InstallDrivers is set to `$true, but either the Drivers folder is missing or empty"
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
    [ValidateSet('x86', 'x64')]
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
    [uint32]$LogicalSectorSizeBytes = 512
)
$version = '2309.2'

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
if (-not $OfficePath) { $OfficePath = "$AppsPath\Office" }
if (-not $rand) { $rand = Get-Random }
if (-not $VMLocation) { $VMLocation = "$FFUDevelopmentPath\VM" }
if (-not $VMName) { $VMName = "$FFUPrefix-$rand" }
if (-not $VMPath) { $VMPath = "$VMLocation\$VMName" }
if (-not $VHDXPath) { $VHDXPath = "$VMPath\$VMName.vhdx" }
if (-not $FFUCaptureLocation) { $FFUCaptureLocation = "$FFUDevelopmentPath\FFU" }
if (-not $LogFile) { $LogFile = "$FFUDevelopmentPath\FFUDevelopment.log" }

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
Function Get-ADK {
    Writelog 'Get ADK Path'
    # Define the registry key and value name to query
    $adkRegKey = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots"
    $adkRegValueName = "KitsRoot10"

    # Check if the registry key exists
    if (Test-Path $adkRegKey) {
        # Get the registry value for the Windows ADK installation path
        $adkPath = (Get-ItemProperty -Path $adkRegKey -Name $adkRegValueName).$adkRegValueName

        if ($adkPath) {
            WriteLog "ADK located at $adkPath"
            return $adkPath
        }
    }
    else {
        throw "Windows ADK is not installed or the installation path could not be found."
    }
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
    
    # Get the ImageName of ImageIndex 4 - this is usually Home or Education SKU on ESD MCT media
    $imageIndex4 = $imageIndexes | Where-Object ImageIndex -eq 4
    $WindowsImage = $imageIndex4.ImageName.Substring(0, 10)
    
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
    else {
        WriteLog (Expand-WindowsImage -ImagePath $WimPath -Index $WimIndex -ApplyPath "$($osPartition.DriveLetter):\" -Compact)
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
            # Wim size + 52MB is minimum WinRE partition size.
            # NTFS and other partitioning size differences account for about 17MB of space that's unavailable.
            # Adding 32MB as a buffer to ensure there's enough space.
            $calculatedRecoverySize = $winReWim.Length + 52MB + 32MB

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
        # If you need to add drivers (storage/keyboard most likely), remove the '#' from the below line and change the /Driver:Path to a folder of drivers
        # & dism /image:$WinPEFFUPath\mount /Add-Driver /Driver:<Path to Drivers folder e.g c:\drivers> /Recurse
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
        #Mount the Capture ISO to the VM
        $CaptureISOPath = "$FFUDevelopmentPath\WinPE_FFU_Capture.iso"

        WriteLog "Setting $CaptureISOPath as first boot device"
        $VMDVDDrive = Get-VMDvdDrive -VMName $VMName
        Set-VMFirmware -VMName $VMName -FirstBootDevice $VMDVDDrive
        Set-VMDvdDrive -VMName $VMName -Path $CaptureISOPath
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
        #Invoke-Process cmd "/c ""$DandIEnv"" && dism /Capture-FFU /ImageFile:$FFUFile /CaptureDrive:\\.\PhysicalDrive$($vhdxDisk.DiskNumber) /Name:$($winverinfo.Name)$($winverinfo.DisplayVersion)$($winverinfo.SKU) /Compress:Default"
        Invoke-Process cmd "/c dism /Capture-FFU /ImageFile:$FFUFile /CaptureDrive:\\.\PhysicalDrive$($vhdxDisk.DiskNumber) /Name:$($winverinfo.Name)$($winverinfo.DisplayVersion)$($winverinfo.SKU) /Compress:Default"
        WriteLog 'FFU Capture complete'
        #WriteLog 'Sleeping 60 seconds before dismount of VHDX'
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
        Add-WindowsDriver -Path "$FFUDevelopmentPath\Mount" -Driver "$FFUDevelopmentPath\Drivers" -Recurse | Out-null
        WriteLog 'Adding drivers complete'
        WriteLog "Dismount $FFUDevelopmentPath\Mount"
        Dismount-WindowsImage -Path "$FFUDevelopmentPath\Mount" -Save | Out-Null
        WriteLog 'Dismount complete'
        WriteLog "Remove $FFUDevelopmentPath\Mount folder"
        Remove-Item -Path "$FFUDevelopmentPath\Mount" -Recurse -Force | Out-null
        WriteLog 'Folder removed'
    }
    #Optimize FFU
    WriteLog 'Optimizing FFU - This will take a few minutes, please be patient'
    #Invoke-Process cmd "/c ""$DandIEnv"" && dism /optimize-ffu /imagefile:$FFUFile"
    Invoke-Process cmd "/c dism /optimize-ffu /imagefile:$FFUFile"
    WriteLog 'Optimizing FFU complete'

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
# Function New-DeploymentUSB {
#     param(
#         [switch]$CopyFFU
#     )
#     WriteLog "CopyFFU is set to $CopyFFU"
#     # Set your FFUDevelopmentPath here
#     $BuildUSBPath = $FFUDevelopmentPath

#     # Get the first removable USB drive
#     $USBDrive = (Get-WmiObject -Class Win32_DiskDrive -Filter "MediaType='Removable Media'")

#     if ($null -eq $USBDrive) {
#         Writelog "No USB drive found"
#         exit 1
#     }

#     # Format the USB drive
#     $DiskNumber = $USBDrive.DeviceID.Replace("\\.\PHYSICALDRIVE", "")
#     $ScriptBlock = {
#         param($DiskNumber)
#         Clear-Disk -Number $DiskNumber -RemoveData -Confirm:$false
#         Clear-Disk -Number $DiskNumber -RemoveData -RemoveOEM -Confirm:$false
#         #Check for other partitions since, apparently, Clear-Disk doesn't remove all of them
#         Get-Disk $disknumber | Get-Partition | Remove-Partition -Confirm:$false
#         $Disk = Get-Disk -Number $DiskNumber
#         $Disk | Set-Disk -PartitionStyle MBR
#         $BootPartition = $Disk | New-Partition -Size 2GB -IsActive -AssignDriveLetter
#         $DeployPartition = $Disk | New-Partition -UseMaximumSize -AssignDriveLetter
#         Format-Volume -Partition $BootPartition -FileSystem FAT32 -NewFileSystemLabel "Boot" -Confirm:$false
#         Format-Volume -Partition $DeployPartition -FileSystem NTFS -NewFileSystemLabel "Deploy" -Confirm:$false
#     }
#     WriteLog 'Partitioning USB Drive'
#     Invoke-Command -ScriptBlock $ScriptBlock -ArgumentList $DiskNumber | Out-null
#     WriteLog 'Done'

#     # Mount the ISO and copy the contents to the boot partition
#     $BootPartitionDriveLetter = (get-volume -FileSystemLabel Boot).DriveLetter + ":\"  
#     $ISOMountPoint = (Mount-DiskImage -ImagePath "$BuildUSBPath\WinPE_FFU_Deploy.iso" -PassThru | Get-Volume).DriveLetter + ":\"
#     WriteLog "Copying WinPE files to $BootPartitionDriveLetter"
#     Copy-Item -Path "$ISOMountPoint\*" -Destination $BootPartitionDriveLetter -Recurse -Force | Out-Null
#     Dismount-DiskImage -ImagePath "$BuildUSBPath\WinPE_FFU_Deploy.iso" | Out-Null

#     # Copy FFU files if switch is provided
#     if ($CopyFFU.IsPresent) {
#         WriteLog 'Copying FFU files'
#         $DeployPartitionDriveLetter = (get-volume -FileSystemLabel Deploy).DriveLetter + ":\"  
#         $FFUFiles = Get-ChildItem -Path "$BuildUSBPath\FFU" -Filter "*.ffu"

#         if ($FFUFiles.Count -eq 1) {
#             WriteLog "Copying $($FFUFiles.FullName) to $DeployPartitionDriveLetter this could take a few minutes"
#             Copy-Item -Path $FFUFiles.FullName -Destination $DeployPartitionDriveLetter -Force | Out-Null
#             Writelog 'Copy complete'
#         }
#         elseif ($FFUFiles.Count -gt 1) {
#             WriteLog "Multiple FFU files found:"
#             Write-Host "Multiple FFU files found:"
#             for ($i = 0; $i -lt $FFUFiles.Count; $i++) {
#                 WriteLog ("{0}: {1}" -f ($i + 1), $FFUFiles[$i].Name)
#                 Write-Host ("{0}: {1}" -f ($i + 1), $FFUFiles[$i].Name)
#             }
#             WriteLog "A: Copy all FFU files"
#             Write-Host "A: Copy all FFU files"
#             $inputChoice = Read-Host "Enter the number corresponding to the FFU file you want to copy or 'A' to copy all FFU files"

#             if ($inputChoice -eq 'A') {
#                 WriteLog "Copying All FFU files to $DeployPartitionDriveLetter this could take a few minutes"
#                 Write-Host "Copying All FFU files to $DeployPartitionDriveLetter this could take a few minutes"
#                 Copy-Item -Path $FFUFiles.FullName -Destination $DeployPartitionDriveLetter -Force | Out-Null
#                 Writelog 'Copy complete'
#                 Write-Host 'Copy complete'
#             }
#             elseif ($inputChoice -ge 1 -and $inputChoice -le $FFUFiles.Count) {
#                 $selectedIndex = $inputChoice - 1
#                 WriteLog "Copying $($FFUFiles[$selectedIndex].FullName) to $DeployPartitionDriveLetter this could take a few minutes"
#                 Write-Host "Copying $($FFUFiles[$selectedIndex].FullName) to $DeployPartitionDriveLetter this could take a few minutes"
#                 Copy-Item -Path $FFUFiles[$selectedIndex].FullName -Destination $DeployPartitionDriveLetter -Force | Out-Null
#                 Writelog 'Copy complete'
#                 Write-Host 'Copy complete'
#             }
#             else {
#                 WriteLog "Invalid choice. No FFU file copied"
#                 Write-Host 'Invalid choice. No FFU file copied'
#             }
#         }
#         else {
#             WriteLog "No FFU files found in the current directory."
#         }
#     }

#     WriteLog "USB drive prepared successfully."
# }

Function New-DeploymentUSB {
    param(
        [switch]$CopyFFU
    )
    WriteLog "CopyFFU is set to $CopyFFU"
    # Set your FFUDevelopmentPath here
    $BuildUSBPath = $PSScriptRoot
    WriteLog "BuildUSBPath is $BuildUSBPath"
    $counter = 0

    # Get removable drives
    $USBDrives = (Get-WmiObject -Class Win32_DiskDrive -Filter "MediaType='Removable Media'")
    If ($USBDrives -and ($null -eq $USBDrives.count)) {
        $USBDrivesCount = 1
    }
    else {
        $USBDrivesCount = $USBDrives.Count
    }
    WriteLog "Found $USBDrivesCount USB drives"

    if ($null -eq $USBDrives) {
        WriteLog "No removable USB drive found."
        exit 1
    }

    foreach ($USBDrive in $USBDrives) {
        $Counter++
        WriteLog "Fromatting USB drive $Counter out of $USBDrivesCount"
        # Format the USB drive
        $DiskNumber = $USBDrive.DeviceID.Replace("\\.\PHYSICALDRIVE", "")
        WriteLog "Physical Disk number is $DiskNumber for USB drive $Counter out of $USBDrivesCount"
        #Delete these two lines
        # Clear-Disk -Number $DiskNumber -RemoveData -RemoveOEM -Confirm:$false 
        # Get-Disk -number $disknumber | select *
        $ScriptBlock = {
            param($DiskNumber)
            Clear-Disk -Number $DiskNumber -RemoveData -RemoveOEM -Confirm:$false
            #Check for other partitions since, apparently, Clear-Disk doesn't remove all of them
            Get-Disk $disknumber | Get-Partition | Remove-Partition
            $Disk = Get-Disk -Number $disknumber
            $Disk | Set-Disk -PartitionStyle MBR
            #Initialize-Disk -Number $DiskNumber -PartitionStyle MBR
            $BootPartition = $Disk | New-Partition -Size 2GB -IsActive -AssignDriveLetter
            $DeployPartition = $Disk | New-Partition -UseMaximumSize -AssignDriveLetter
            Format-Volume -Partition $BootPartition -FileSystem FAT32 -NewFileSystemLabel "TempBoot" -Confirm:$false
            Format-Volume -Partition $DeployPartition -FileSystem NTFS -NewFileSystemLabel "TempDeploy" -Confirm:$false
        }
        WriteLog 'Partitioning USB Drive'
        Invoke-Command -ScriptBlock $ScriptBlock -ArgumentList $DiskNumber | Out-null
        WriteLog 'Done'
    
        # Mount the ISO and copy the contents to the boot partition
        $BootPartitionDriveLetter = (Get-WmiObject -Class win32_volume -Filter "Label='TempBoot' AND DriveType=2 AND DriveLetter IS NOT NULL").Name
        $ISOMountPoint = (Mount-DiskImage -ImagePath "$BuildUSBPath\WinPE_FFU_Deploy.iso" -PassThru | Get-Volume).DriveLetter + ":\"
        WriteLog "Copying WinPE files to $BootPartitionDriveLetter"
        # Copy-Item -Path "$ISOMountPoint\*" -Destination $BootPartitionDriveLetter -Recurse -Force | Out-Null
        robocopy "$ISOMountPoint" "$BootPartitionDriveLetter" /E /COPYALL /R:5 /W:5 /J
        Dismount-DiskImage -ImagePath "$BuildUSBPath\WinPE_FFU_Deploy.iso" | Out-Null
    
        # Copy FFU files if switch is provided
        if ($CopyFFU.IsPresent) {
            WriteLog 'Copying FFU files'
            #$DeployPartitionDriveLetter = (get-volume -FileSystemLabel Deploy).DriveLetter + ":\"  
            $DeployPartitionDriveLetter = (Get-WmiObject -Class win32_volume -Filter "Label='TempDeploy' AND DriveType=2 AND DriveLetter IS NOT NULL").Name
            $FFUFiles = Get-ChildItem -Path "$BuildUSBPath\FFU" -Filter "*.ffu"
    
            if ($FFUFiles.Count -eq 1) {
                WriteLog ("Copying " + $FFUFiles.FullName + " to $DeployPartitionDriveLetter this could take a few minutes")
                # Copy-Item -Path $FFUFiles.FullName -Destination $DeployPartitionDriveLetter -Force
                robocopy $(Split-Path $FFUFiles.FullName -Parent) $DeployPartitionDriveLetter $(Split-Path $FFUFiles.FullName -Leaf) /COPYALL /R:5 /W:5 /J
    
            }
            elseif ($FFUFiles.Count -gt 1) {
                WriteLog "Multiple FFU files found:"
                for ($i = 0; $i -lt $FFUFiles.Count; $i++) {
                    WriteLog ("{0}: {1}" -f ($i + 1), $FFUFiles[$i].Name)
                }
                WriteLog "A: Copy all FFU files"
                $inputChoice = Read-Host "Enter the number corresponding to the FFU file you want to copy or 'A' to copy all FFU files"
    
                if ($inputChoice -eq 'A') {
                    WriteLog "Copying All FFU files to $DeployPartitionDriveLetter this could take a few minutes"
                    # Copy-Item -Path $FFUFiles.FullName -Destination $DeployPartitionDriveLetter -Force
                    robocopy $(Split-Path $FFUFiles.FullName -Parent) $DeployPartitionDriveLetter $(Split-Path $FFUFiles.FullName -Leaf) /COPYALL /R:5 /W:5 /J
                }
                elseif ($inputChoice -ge 1 -and $inputChoice -le $FFUFiles.Count) {
                    $selectedIndex = $inputChoice - 1
                    WriteLog ("Copying " + $FFUFiles[$selectedIndex].FullName + " to $DeployPartitionDriveLetter this could take a few minutes")
                    # Copy-Item -Path $FFUFiles[$selectedIndex].FullName -Destination $DeployPartitionDriveLetter -Force
                    robocopy $(Split-Path $FFUFiles[$selectedIndex].FullName -Parent) $DeployPartitionDriveLetter $(Split-Path $FFUFiles[$selectedIndex].FullName -Leaf) /COPYALL /R:5 /W:5 /J
                }
                else {
                    WriteLog "Invalid choice. No FFU file copied."
                }
            }
            else {
                WriteLog "No FFU files found in the current directory."
            }
        }
        Set-Volume -FileSystemLabel "TempBoot" -NewFileSystemLabel "Boot"
        Set-Volume -FileSystemLabel "TempDeploy" -NewFileSystemLabel "Deploy"
        #Remove drive letter (so we don't run out of drive letters)
        If ($USBDrivesCount -gt 1) {
            & mountvol $BootPartitionDriveLetter /D
            & mountvol $DeployPartitionDriveLetter /D 
        }
        WriteLog "Drive $counter completed"
    }
    
    WriteLog "USB Drives completed"
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

#Get script variable values
LogVariableValues    

#Get Windows ADK
try {
    $adkPath = Get-ADK
    #Need to use the Deployment and Imaging tools environment to use dism from the Insider ADK to optimize the FFU. This is only needed until Windows 23H2
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
        
        if (-not $InstallOffice) {
            #Modify InstallAppsandSysprep.cmd to REM out the office install command
            $cmdContent = Get-Content -Path "$AppsPath\InstallAppsandSysprep.cmd"
            $UpdatedcmdContent = $cmdContent -replace '^(d:\\Office\\setup.exe /configure d:\\office\\DeployFFU.xml)', ("REM d:\Office\setup.exe /configure d:\office\DeployFFU.xml")
            Set-Content -Path "$AppsPath\InstallAppsandSysprep.cmd" -Value $UpdatedcmdContent
        }
        
        if ($InstallOffice) {
            WriteLog 'Downloading M365 Apps/Office'
            Get-Office
            WriteLog 'Downloading M365 Apps/Office completed successfully'
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

    $vhdxDisk = New-ScratchVhdx -VhdxPath $VHDXPath -SizeBytes $disksize -Dynamic -LogicalSectorSizeBytes $LogicalSectorSizeBytes

    $systemPartitionDriveLetter = New-SystemPartition -VhdxDisk $vhdxDisk
    
    New-MSRPartition -VhdxDisk $vhdxDisk
    
    $osPartition = New-OSPartition -VhdxDisk $vhdxDisk -OSPartitionSize $OSPartitionSize -WimPath $WimPath -WimIndex $index
    $osPartitionDriveLetter = $osPartition[1].DriveLetter
    $WindowsPartition = $osPartitionDriveLetter + ":\"

    #$recoveryPartition = New-RecoveryPartition -VhdxDisk $vhdxDisk -OsPartition $osPartition[1] -RecoveryPartitionSize $RecoveryPartitionSize -DataPartition $dataPartition

    WriteLog "All necessary partitions created."

    Add-BootFiles -OsPartitionDriveLetter $osPartitionDriveLetter -SystemPartitionDriveLetter $systemPartitionDriveLetter[1]

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
        If (Test-Path -Path "$FFUDevelopmentPath\WinPE_FFU_Deploy.iso") {
            New-DeploymentUSB -CopyFFU
        }
        else {
            WriteLog "$BuildUSBDrive set to true, however unable to find WinPE_FFU_Deploy.iso. USB drive not built."
        }
        
    }
    catch {
        Write-Host 'Building USB deployment drive failed'
        Writelog "Building USB deployment drive failed with error $_"
        throw $_
    }
}
Write-Host "Script complete"
WriteLog "Script complete"