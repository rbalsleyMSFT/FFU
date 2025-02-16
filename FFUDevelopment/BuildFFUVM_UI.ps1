[CmdletBinding()]
[System.STAThread()]
param()

# --------------------------------------------------------------------------
# SECTION 1: Variables & Constants
# --------------------------------------------------------------------------
$FFUDevelopmentPath = $PSScriptRoot
$AppsPath           = Join-Path $FFUDevelopmentPath "Apps"
$OfficePath         = Join-Path $AppsPath "Office"

# Add the new function for USB drive detection
function Get-USBDrives {
    Get-WmiObject Win32_DiskDrive | Where-Object { 
        ($_.MediaType -eq 'Removable Media' -or $_.MediaType -eq 'External hard disk media') -and
        $_.InterfaceType -eq 'USB'
    } | ForEach-Object {
        $size = [math]::Round($_.Size / 1GB, 2)
        $serialNumber = if ($_.SerialNumber) { $_.SerialNumber.Trim() } else { "N/A" }
        @{
            IsSelected = $false
            Model = $_.Model.Trim()
            SerialNumber = $serialNumber
            Size = $size
            DriveIndex = $_.Index
        }
    }
}

# --------------------------------------------------------------------------
# SECTION: Winget Management Functions
# --------------------------------------------------------------------------
function Test-WingetCLI {
    [CmdletBinding()]
    param()
    
    $minVersion = [version]"1.8.1911"
    
    # Check Winget CLI
    $wingetCmd = Get-Command -Name winget -ErrorAction SilentlyContinue
    if (-not $wingetCmd) {
        return @{
            Version = "Not installed"
            Status = "Not installed - Install from Microsoft Store"
        }
    }
    
    # Get and check version
    $wingetVersion = & winget.exe --version
    if ($wingetVersion -match 'v?(\d+\.\d+.\d+)') {
        $version = [version]$matches[1]
        if ($version -lt $minVersion) {
            return @{
                Version = $version.ToString()
                Status = "Update required - Install from Microsoft Store"
            }
        }
        return @{
            Version = $version.ToString()
            Status = $version.ToString()
        }
    }
    
    return @{
        Version = "Unknown"
        Status = "Version check failed"
    }
}

function Update-WingetVersionFields {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$wingetText,
        [Parameter(Mandatory)]
        [string]$moduleText
    )
    
    # Force UI update on the UI thread
    $window.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Normal, [Action]{
        $script:txtWingetVersion.Text = $wingetText
        $script:txtWingetModuleVersion.Text = $moduleText
        # Force immediate UI refresh
        [System.Windows.Forms.Application]::DoEvents()
    })
}

function Install-WingetComponents {
    [CmdletBinding()]
    param(
        [string]$currentWingetVersion = "Checking..."
    )

    $minVersion = [version]"1.8.1911"
    
    try {
        # Check and update PowerShell Module
        $module = Get-InstalledModule -Name Microsoft.WinGet.Client -ErrorAction SilentlyContinue
        if (-not $module -or $module.Version -lt $minVersion) {
            Update-WingetVersionFields -wingetText $currentWingetVersion -moduleText "Installing..."
            
            # Store and modify PSGallery trust setting temporarily if needed
            $PSGalleryTrust = (Get-PSRepository -Name 'PSGallery').InstallationPolicy
            if ($PSGalleryTrust -eq 'Untrusted') {
                Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
            }

            # Install/Update the module
            Install-Module -Name Microsoft.WinGet.Client -Force -Repository 'PSGallery'
            
            # Restore original PSGallery trust setting
            if ($PSGalleryTrust -eq 'Untrusted') {
                Set-PSRepository -Name 'PSGallery' -InstallationPolicy Untrusted
            }
            
            $module = Get-InstalledModule -Name Microsoft.WinGet.Client -ErrorAction Stop
        }
        
        return $module
    }
    catch {
        Write-Error "Failed to install/update Winget PowerShell module: $_"
        throw
    }
}

# Winget Module Check Function
function Confirm-WinGetInstallation {
    param(
        [System.Windows.Controls.TextBlock]$txtWingetVersion,
        [System.Windows.Controls.TextBlock]$txtWingetModuleVersion
    )
    
    $minVersion = [version]"1.8.1911"
    $result = @{
        Success = $false
        Message = ""
        RequiresRestart = $false
    }
    
    # Check if winget executable exists and is accessible
    if (-not (Get-Command -Name winget -ErrorAction SilentlyContinue)) {
        Update-VersionTextFields -wingetText "Not installed" -moduleText "Not installed"
        $result.Message = "WinGet not found. Installing..."
        $result.RequiresRestart = $true
        return $result
    }

    # Get winget version
    $wingetVersion = & winget.exe --version
    if ($wingetVersion -match 'v?(\d+\.\d+.\d+)') {
        $currentVersion = [version]$matches[1]
        Update-VersionTextFields -wingetText $matches[1] -moduleText $txtWingetModuleVersion.Text
        
        if ($currentVersion -lt $minVersion) {
            Update-VersionTextFields -wingetText "Updating..." -moduleText $txtWingetModuleVersion.Text
            $result.Message = "WinGet version $currentVersion is outdated. Minimum required version is $minVersion"
            $result.RequiresRestart = $true
            return $result
        }
    }

    # Check if Winget PowerShell module is installed and up to date
    $wingetModule = Get-InstalledModule -Name Microsoft.WinGet.Client -ErrorAction SilentlyContinue
    if ($null -eq $wingetModule) {
        Update-VersionTextFields -wingetText $txtWingetVersion.Text -moduleText "Installing..."
        $result.Message = "Microsoft.WinGet.Client module needs to be installed..."
    }
    elseif ($wingetModule.Version -lt $minVersion) {
        Update-VersionTextFields -wingetText $txtWingetVersion.Text -moduleText "Updating..."
        $result.Message = "Microsoft.WinGet.Client module needs to be updated..."
    }
    else {
        Update-VersionTextFields -wingetText $txtWingetVersion.Text -moduleText $wingetModule.Version.ToString()
        $result.Success = $true
        $result.Message = "Winget and its PowerShell module are installed and up to date."
        return $result
    }
    
    # Install/Update module if needed
    try {
        # Check if PSGallery is trusted
        $PSGalleryTrust = (Get-PSRepository -Name 'PSGallery').InstallationPolicy
        if ($PSGalleryTrust -eq 'Untrusted') {
            Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
        }

        # Install/Update the module
        Install-Module -Name Microsoft.WinGet.Client -Force -Repository 'PSGallery'

        # Restore PSGallery trust setting if it was untrusted
        if ($PSGalleryTrust -eq 'Untrusted') {
            Set-PSRepository -Name 'PSGallery' -InstallationPolicy Untrusted
        }
    }
    catch {
        Update-VersionTextFields -wingetText $txtWingetVersion.Text -moduleText "Error"
        throw
    }
    
    $result.RequiresRestart = $true
    return $result
}

# Some default values
$defaultISOPath         = ""
$defaultWindowsRelease   = 11   # numeric
$defaultWindowsArch      = "x64"
$defaultWindowsLang      = "en-us"
$defaultWindowsSKU       = "Pro"
$defaultMediaType        = "Consumer"  # updated value
$defaultOptionalFeatures = ""
$defaultProductKey       = ""
$defaultFFUPrefix        = "_FFU"     # <-- new default for VM Name Prefix

# Large list from the ValidateSet in BuildFFUVM.ps1 ($OptionalFeatures parameter)
$allowedFeatures = @(
    "AppServerClient","Client-DeviceLockdown","Client-EmbeddedBootExp","Client-EmbeddedLogon",
    "Client-EmbeddedShellLauncher","Client-KeyboardFilter","Client-ProjFS","Client-UnifiedWriteFilter",
    "Containers","Containers-DisposableClientVM","Containers-HNS","Containers-SDN","DataCenterBridging",
    "DirectoryServices-ADAM-Client","DirectPlay","HostGuardian","HypervisorPlatform","IIS-ApplicationDevelopment",
    "IIS-ApplicationInit","IIS-ASP","IIS-ASPNET45","IIS-BasicAuthentication","IIS-CertProvider",
    "IIS-CGI","IIS-ClientCertificateMappingAuthentication","IIS-CommonHttpFeatures","IIS-CustomLogging",
    "IIS-DefaultDocument","IIS-DirectoryBrowsing","IIS-DigestAuthentication","IIS-ESP","IIS-FTPServer",
    "IIS-FTPExtensibility","IIS-FTPSvc","IIS-HealthAndDiagnostics","IIS-HostableWebCore","IIS-HttpCompressionDynamic",
    "IIS-HttpCompressionStatic","IIS-HttpErrors","IIS-HttpLogging","IIS-HttpRedirect","IIS-HttpTracing",
    "IIS-IPSecurity","IIS-IIS6ManagementCompatibility","IIS-IISCertificateMappingAuthentication",
    "IIS-ISAPIExtensions","IIS-ISAPIFilter","IIS-LoggingLibraries","IIS-ManagementConsole","IIS-ManagementService",
    "IIS-ManagementScriptingTools","IIS-Metabase","IIS-NetFxExtensibility","IIS-NetFxExtensibility45",
    "IIS-ODBCLogging","IIS-Performance","IIS-RequestFiltering","IIS-RequestMonitor","IIS-Security","IIS-ServerSideIncludes",
    "IIS-StaticContent","IIS-URLAuthorization","IIS-WebDAV","IIS-WebServer","IIS-WebServerManagementTools",
    "IIS-WebServerRole","IIS-WebSockets","LegacyComponents","MediaPlayback","Microsoft-Hyper-V","Microsoft-Hyper-V-All",
    "Microsoft-Hyper-V-Hypervisor","Microsoft-Hyper-V-Management-Clients","Microsoft-Hyper-V-Management-PowerShell",
    "Microsoft-Hyper-V-Services","Microsoft-Windows-Subsystem-Linux","MSMQ-ADIntegration","MSMQ-Container","MSMQ-DCOMProxy",
    "MSMQ-HTTP","MSMQ-Multicast","MSMQ-Server","MSMQ-Triggers","MultiPoint-Connector","MultiPoint-Connector-Services",
    "MultiPoint-Tools","NetFx3","NetFx4-AdvSrvs","NetFx4Extended-ASPNET45","NFS-Administration","Printing-Foundation-Features",
    "Printing-Foundation-InternetPrinting-Client","Printing-Foundation-LPDPrintService","Printing-Foundation-LPRPortMonitor",
    "Printing-PrintToPDFServices-Features","Printing-XPSServices-Features","SearchEngine-Client-Package",
    "ServicesForNFS-ClientOnly","SimpleTCP","SMB1Protocol","SMB1Protocol-Client","SMB1Protocol-Deprecation",
    "SMB1Protocol-Server","SmbDirect","TFTP","TelnetClient","TIFFIFilter","VirtualMachinePlatform","WAS-ConfigurationAPI",
    "WAS-NetFxEnvironment","WAS-ProcessModel","WAS-WindowsActivationService","WCF-HTTP-Activation","WCF-HTTP-Activation45",
    "WCF-MSMQ-Activation45","WCF-MSMQ-Activation","WCF-NonHTTP-Activation","WCF-Pipe-Activation45","WCF-Services45",
    "WCF-TCP-Activation45","WCF-TCP-PortSharing45","Windows-Defender-ApplicationGuard",
    "Windows-Defender-Default-Definitions","Windows-Identity-Foundation","WindowsMediaPlayer","WorkFolders-Client"
)

$skuList = @(
    'Home','Home N','Home Single Language','Education','Education N','Pro',
    'Pro N','Pro Education','Pro Education N','Pro for Workstations',
    'Pro N for Workstations','Enterprise','Enterprise N','Standard',
    'Standard (Desktop Experience)','Datacenter','Datacenter (Desktop Experience)'
)

# Full list of Windows releases (if ISO path != blank)
$allWindowsReleases = @(
    [PSCustomObject]@{ Display = "Windows 10";          Value = 10    },
    [PSCustomObject]@{ Display = "Windows 11";          Value = 11    },
    [PSCustomObject]@{ Display = "Windows Server 2016"; Value = 2016  },
    [PSCustomObject]@{ Display = "Windows Server 2019"; Value = 2019  },
    [PSCustomObject]@{ Display = "Windows Server 2022"; Value = 2022  },
    [PSCustomObject]@{ Display = "Windows Server 2025"; Value = 2025  }
)

# Subset for MCT (if ISO path is blank)
$mctWindowsReleases = @(
    [PSCustomObject]@{ Display = "Windows 10"; Value = 10 },
    [PSCustomObject]@{ Display = "Windows 11"; Value = 11 }
)

# Windows version sets
$windowsVersionMap = @{
    10    = @("22H2")
    11    = @("22H2","23H2","24H2")
    2016  = @("1607")
    2019  = @("1809")
    2022  = @("21H2")
    2025  = @("24H2")
}

# --------------------------------------------------------------------------

function Get-UIConfig {
    # --- Build Tab Values ---
    $ffuDevPath = $window.FindName('txtFFUDevPath').Text
    $customFFUNameTemplate = $window.FindName('txtCustomFFUNameTemplate').Text
    $ffuCaptureLocation = $window.FindName('txtFFUCaptureLocation').Text
    $shareName = $window.FindName('txtShareName').Text
    $username = $window.FindName('txtUsername').Text

    # General Build Options (Build tab WrapPanel)
    $buildUSB = $window.FindName('chkBuildUSBDriveEnable').IsChecked
    $compactOS = $window.FindName('chkCompactOS').IsChecked
    $optimize = $window.FindName('chkOptimize').IsChecked
    $allowVHDXCaching = $window.FindName('chkAllowVHDXCaching').IsChecked
    $createCapture = $window.FindName('chkCreateCaptureMedia').IsChecked
    $createDeployMedia = $window.FindName('chkCreateDeploymentMedia').IsChecked

    # Build USB Drive Section (new)
    $promptExt = $window.FindName('chkPromptExternalHardDiskMedia').IsChecked
    $allowExt = $window.FindName('chkAllowExternalHardDiskMedia').IsChecked

    # USB Drive Modification group (Build tab right column in new section)
    $copyAutopilot = $window.FindName('chkCopyAutopilot').IsChecked
    $copyUnattend = $window.FindName('chkCopyUnattend').IsChecked
    $copyPPKG = $window.FindName('chkCopyPPKG').IsChecked

    # --- Hyper-V Settings (from Hyper-V tab) ---
    $cmbVMSwitch = $window.FindName('cmbVMSwitchName')
    $vmSwitchName = $cmbVMSwitch.SelectedItem
    if ($vmSwitchName -eq 'Other') { $vmSwitchName = $window.FindName('txtCustomVMSwitchName').Text }
    $vmHostIPAddress = $window.FindName('txtVMHostIPAddress').Text
    [int64]$diskSizeInGB = [int64]$window.FindName('txtDiskSize').Text
    $diskSize = $diskSizeInGB * 1GB
    [int64]$memoryInGB = [int64]$window.FindName('txtMemory').Text
    $memory = $memoryInGB * 1GB
    [int]$processors = [int]$window.FindName('txtProcessors').Text
    $vmLocation = $window.FindName('txtVMLocation').Text
    $logicalSectorObj = $window.FindName('cmbLogicalSectorSize').SelectedItem
    $logicalSectorSize = [int]$logicalSectorObj.Content

    # <-- NEW: retrieve FFUPrefix from the new textbox (VM Name Prefix)
    $ffuPrefix = $window.FindName('txtVMNamePrefix').Text

    # --- Windows Settings tab ---
    $wrItem = $window.FindName('cmbWindowsRelease').SelectedItem
    $windowsRelease = if ($wrItem -and $wrItem.Value) { [int]$wrItem.Value } else { 10 }
    $windowsVersion = $window.FindName('cmbWindowsVersion').SelectedItem
    $windowsArch = $window.FindName('cmbWindowsArch').SelectedItem
    $windowsLang = $window.FindName('cmbWindowsLang').SelectedItem
    $windowsSKU = $window.FindName('cmbWindowsSKU').SelectedItem
    $mediaType = $window.FindName('cmbMediaType').SelectedItem
    $productKey = $window.FindName('txtProductKey').Text
    $isoPath = $window.FindName('txtISOPath').Text

    # --- M365 Apps/Office tab ---
    $installOffice = $window.FindName('chkInstallOffice').IsChecked
    $officePath = $window.FindName('txtOfficePath').Text
    $copyOfficeConfig = $window.FindName('chkCopyOfficeConfigXML').IsChecked
    $officeConfigXMLFile = $window.FindName('txtOfficeConfigXMLFilePath').Text

    # --- Drivers tab ---
    $installDrivers = $window.FindName('chkInstallDrivers').IsChecked
    $copyDrivers = $window.FindName('chkCopyDrivers').IsChecked
    $downloadDrivers = $window.FindName('chkDownloadDrivers').IsChecked
    $make = $window.FindName('cmbMake').SelectedItem
    $model = $window.FindName('cmbModel').Text
    $driversFolder = $window.FindName('txtDriversFolder').Text
    $peDriversFolder = $window.FindName('txtPEDriversFolder').Text
    $copyPEDrivers = $window.FindName('chkCopyPEDrivers').IsChecked

    # --- Updates tab ---
    $updateLatestCU = $window.FindName('chkUpdateLatestCU').IsChecked
    $updateLatestNet = $window.FindName('chkUpdateLatestNet').IsChecked
    $updateLatestDefender = $window.FindName('chkUpdateLatestDefender').IsChecked
    $updateEdge = $window.FindName('chkUpdateEdge').IsChecked
    $updateOneDrive = $window.FindName('chkUpdateOneDrive').IsChecked
    $updateLatestMSRT = $window.FindName('chkUpdateLatestMSRT').IsChecked
    $updatePreviewCU = $window.FindName('chkUpdatePreviewCU').IsChecked

    # --- Applications tab ---
    $installApps = $window.FindName('chkInstallApps').IsChecked
    $installWingetApps = $window.FindName('chkInstallWingetApps').IsChecked

    # Add USB drive selection to config
    $selectedUSBDrives = @{}
    $window.FindName('lstUSBDrives').Items | Where-Object { $_.IsSelected } | ForEach-Object { 
        $selectedUSBDrives[$_.Model] = $_.SerialNumber
    }

    # Build configuration hashtable (unsorted)
    $config = [ordered]@{
        AllowExternalHardDiskMedia = $allowExt
        AllowVHDXCaching = $allowVHDXCaching
        BuildUSBDrive              = $buildUSB
        CompactOS                  = $compactOS
        CopyAutopilot              = $copyAutopilot
        CopyOfficeConfigXML        = $copyOfficeConfig
        CopyPEDrivers              = $copyPEDrivers
        CopyPPKG                   = $copyPPKG
        CopyUnattend               = $copyUnattend
        CreateCaptureMedia         = $createCapture
        CreateDeploymentMedia      = $createDeployMedia
        CleanupAppsISO             = $window.FindName('chkCleanupAppsISO').IsChecked
        CleanupCaptureISO          = $window.FindName('chkCleanupCaptureISO').IsChecked
        CleanupDeployISO           = $window.FindName('chkCleanupDeployISO').IsChecked
        CleanupDrivers             = $window.FindName('chkCleanupDrivers').IsChecked
        Disksize                   = $diskSize
        DownloadDrivers            = $downloadDrivers
        PromptExternalHardDiskMedia = $promptExt
        FFUCaptureLocation         = $ffuCaptureLocation
        FFUDevelopmentPath         = $ffuDevPath
        ISOPath                    = $isoPath      # <-- NEW: Add Windows ISO Path to config
        MediaType                  = $mediaType
        Make                       = $make
        Model                      = $model
        OfficeConfigXMLFile        = $officeConfigXMLFile
        OfficePath                 = $officePath
        OptionalFeatures           = $window.FindName('txtOptionalFeatures').Text
        PEDriversFolder            = $peDriversFolder
        ProductKey                 = $productKey
        Processors                 = $processors
        RemoveFFU                  = $window.FindName('chkRemoveFFU').IsChecked
        UpdateEdge                 = $updateEdge
        UpdateLatestCU             = $updateLatestCU
        UpdateLatestDefender       = $updateLatestDefender
        UpdateLatestMSRT           = $updateLatestMSRT
        UpdateLatestNet            = $updateLatestNet
        UpdateOneDrive             = $updateOneDrive
        UpdatePreviewCU            = $updatePreviewCU
        VMHostIPAddress            = $vmHostIPAddress
        VMLocation                 = $vmLocation
        VMSwitchName               = $vmSwitchName
        LogicalSectorSizeBytes     = $logicalSectorSize
        Memory                     = $memory
        WindowsArch                = $windowsArch
        WindowsLang                = $windowsLang
        WindowsRelease             = $windowsRelease
        WindowsSKU                 = $windowsSKU
        WindowsVersion             = $windowsVersion
        FFUPrefix                  = $ffuPrefix    # <-- new option for VM Name Prefix
        USBDriveList               = $selectedUSBDrives # Add USB drive selection
        InstallApps                = $installApps
        InstallWingetApps          = $installWingetApps
    }

    # Sort the configuration hashtable alphabetically by key
    $sortedConfig = [ordered]@{}
    foreach ($key in ($config.Keys | Sort-Object)) {
        $sortedConfig[$key] = $config[$key]
    }
    return $sortedConfig
}

function UpdateWindowsReleaseList {
    param([string]$isoPath)
    if (-not $script:cmbWindowsRelease) { return }
    $oldItem = $script:cmbWindowsRelease.SelectedItem
    $script:cmbWindowsRelease.Items.Clear()
    $script:cmbWindowsRelease.DisplayMemberPath = 'Display'
    $script:cmbWindowsRelease.SelectedValuePath = 'Value'
    if ([string]::IsNullOrEmpty($isoPath)) {
        foreach ($rel in $mctWindowsReleases) { $script:cmbWindowsRelease.Items.Add($rel) | Out-Null }
    }
    else {
        foreach ($rel in $allWindowsReleases) { $script:cmbWindowsRelease.Items.Add($rel) | Out-Null }
    }
    if ($oldItem) {
        $reSelect = $script:cmbWindowsRelease.Items | Where-Object { $_.Value -eq $oldItem.Value }
        if ($reSelect) { $script:cmbWindowsRelease.SelectedItem = $reSelect }
        else { $script:cmbWindowsRelease.SelectedIndex = 0 }
    }
    else { $script:cmbWindowsRelease.SelectedIndex = 0 }
}

function UpdateWindowsVersionCombo {
    param(
        [int]$selectedRelease,
        [string]$isoPath
    )
    $combo = $window.FindName('cmbWindowsVersion')
    if (-not $combo) { return }
    $combo.Items.Clear()
    if (-not $windowsVersionMap.ContainsKey($selectedRelease)) {
        $combo.IsEnabled = $false
        return
    }
    $validVersions = $windowsVersionMap[$selectedRelease]
    if ([string]::IsNullOrEmpty($isoPath)) {
        switch ($selectedRelease) {
            10   { $default = "22H2" }
            11   { $default = "24H2" }
            2016 { $default = "1607" }
            2019 { $default = "1809" }
            2022 { $default = "21H2" }
            2025 { $default = "24H2" }
            default { $default = $validVersions[0] }
        }
        $combo.Items.Add($default) | Out-Null
        $combo.SelectedIndex = 0
        $combo.IsEnabled = $false
    }
    else {
        foreach ($v in $validVersions) { [void]$combo.Items.Add($v) }
        if ($selectedRelease -eq 11 -and $validVersions -contains "24H2") { $combo.SelectedItem = "24H2" }
        else { $combo.SelectedIndex = 0 }
        $combo.IsEnabled = $true
    }
}

$script:RefreshWindowsUI = {
    param([string]$isoPath)
    UpdateWindowsReleaseList -isoPath $isoPath
    $selItem = $script:cmbWindowsRelease.SelectedItem
    if ($selItem -and $selItem.Value -is [int]) { $selectedRelease = [int]$selItem.Value }
    else { $selectedRelease = 10 }
    UpdateWindowsVersionCombo -selectedRelease $selectedRelease -isoPath $isoPath
}

Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName PresentationCore,PresentationFramework
Add-Type -AssemblyName System.Windows.Forms

# Load XAML
$xamlPath = Join-Path $PSScriptRoot "BuildFFUVM_UI.xaml"
if (-not (Test-Path $xamlPath)) {
    Write-Error "XAML file not found: $xamlPath"
    return
}
$xamlString = Get-Content $xamlPath -Raw
$reader = New-Object System.IO.StringReader($xamlString)
$xmlReader = [System.Xml.XmlReader]::Create($reader)
$window = [Windows.Markup.XamlReader]::Load($xmlReader)

# Dynamic checkboxes for optional features in Windows Settings tab
$script:featureCheckBoxes = @{}
function UpdateOptionalFeaturesString {
    $checkedFeatures = @()
    foreach ($entry in $script:featureCheckBoxes.GetEnumerator()) {
        if ($entry.Value.IsChecked) { $checkedFeatures += $entry.Key }
    }
    $window.FindName('txtOptionalFeatures').Text = $checkedFeatures -join ";"
}
function BuildFeaturesGrid {
    param (
        [System.Windows.FrameworkElement]$parent
    )
    $parent.Children.Clear()
    $sortedFeatures = $allowedFeatures | Sort-Object
    $rows = 10
    $columns = [math]::Ceiling($sortedFeatures.Count / $rows)
    $featuresGrid = New-Object System.Windows.Controls.Grid
    $featuresGrid.Margin = "0,5,0,5"
    $featuresGrid.ShowGridLines = $false
    for ($r = 0; $r -lt $rows; $r++) {
        $rowDef = New-Object System.Windows.Controls.RowDefinition
        $rowDef.Height = 'Auto'
        $featuresGrid.RowDefinitions.Add($rowDef) | Out-Null
    }
    for ($c = 0; $c -lt $columns; $c++) {
        $colDef = New-Object System.Windows.Controls.ColumnDefinition
        $colDef.Width = 'Auto'
        $featuresGrid.ColumnDefinitions.Add($colDef) | Out-Null
    }
    for ($i = 0; $i -lt $sortedFeatures.Count; $i++) {
        $featureName = $sortedFeatures[$i]
        $colIndex = [int]([math]::Floor($i / $rows))
        $rowIndex = $i % $rows
        $chk = New-Object System.Windows.Controls.CheckBox
        $chk.Content = $featureName
        $chk.Margin = "5"
        $chk.Add_Checked({ UpdateOptionalFeaturesString })
        $chk.Add_Unchecked({ UpdateOptionalFeaturesString })
        $script:featureCheckBoxes[$featureName] = $chk
        [System.Windows.Controls.Grid]::SetRow($chk, $rowIndex)
        [System.Windows.Controls.Grid]::SetColumn($chk, $colIndex)
        $featuresGrid.Children.Add($chk) | Out-Null
    }
    $parent.Children.Add($featuresGrid) | Out-Null
}

# Variables for managing forced Install Apps state due to Updates
$script:installAppsForcedByUpdates = $false
$script:prevInstallAppsStateBeforeUpdates = $null

# Define the function in script scope to update Install Apps based on Updates tab
$script:UpdateInstallAppsBasedOnUpdates = {
    $anyUpdateChecked = $window.FindName('chkUpdateLatestDefender').IsChecked -or $window.FindName('chkUpdateEdge').IsChecked -or $window.FindName('chkUpdateOneDrive').IsChecked -or $window.FindName('chkUpdateLatestMSRT').IsChecked
    if ($anyUpdateChecked) {
        if (-not $script:installAppsForcedByUpdates) {
            $script:prevInstallAppsStateBeforeUpdates = $window.FindName('chkInstallApps').IsChecked
            $script:installAppsForcedByUpdates = $true
        }
        $window.FindName('chkInstallApps').IsChecked = $true
        $window.FindName('chkInstallApps').IsEnabled = $false
    } else {
        if ($script:installAppsForcedByUpdates) {
            $window.FindName('chkInstallApps').IsChecked = $script:prevInstallAppsStateBeforeUpdates
            $script:installAppsForcedByUpdates = $false
            $script:prevInstallAppsStateBeforeUpdates = $null
        }
        $window.FindName('chkInstallApps').IsEnabled = $true
    }
}

# Create data context class for version binding
$script:versionData = [PSCustomObject]@{
    WingetVersion = "Not checked"
    ModuleVersion = "Not checked"
}

# Add observable property support
$script:versionData | Add-Member -MemberType ScriptMethod -Name NotifyPropertyChanged -Value {
    param($PropertyName)
    if ($this.PropertyChanged) {
        $this.PropertyChanged.Invoke($this, [System.ComponentModel.PropertyChangedEventArgs]::new($PropertyName))
    }
}

$script:versionData | Add-Member -MemberType NoteProperty -Name PropertyChanged -Value $null
$script:versionData | Add-Member -TypeName "System.ComponentModel.INotifyPropertyChanged"

$window.Add_Loaded({
    $script:cmbWindowsRelease = $window.FindName('cmbWindowsRelease')
    $script:cmbWindowsVersion = $window.FindName('cmbWindowsVersion')
    $script:txtISOPath = $window.FindName('txtISOPath')
    & $script:RefreshWindowsUI($defaultISOPath)
    $script:txtISOPath.Add_TextChanged({ & $script:RefreshWindowsUI($script:txtISOPath.Text) })
    $script:cmbWindowsRelease.Add_SelectionChanged({
        $selItem = $script:cmbWindowsRelease.SelectedItem
        if ($selItem -and $selItem.Value) { UpdateWindowsVersionCombo -selectedRelease $selItem.Value -isoPath $script:txtISOPath.Text }
    })
    $script:btnBrowseISO = $window.FindName('btnBrowseISO')
    $script:btnBrowseISO.Add_Click({
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Filter = "ISO files (*.iso)|*.iso"
        $ofd.Title  = "Select Windows ISO File"
        if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $script:txtISOPath.Text = $ofd.FileName }
    })
    # Home tab (renamed from Basic) displays static welcome text.
    # Build tab defaults
    $window.FindName('txtFFUDevPath').Text = $FFUDevelopmentPath
    $window.FindName('txtCustomFFUNameTemplate').Text = "{WindowsRelease}_{WindowsVersion}_{SKU}_{yyyy}-{MM}-{dd}_{HH}{mm}"
    $window.FindName('txtFFUCaptureLocation').Text = (Join-Path $FFUDevelopmentPath "FFU")
    $window.FindName('txtShareName').Text = "FFUCaptureShare"
    $window.FindName('txtUsername').Text = "ffu_user"
    # Set VM Location default to $FFUDevelopmentPath\VM
    $window.FindName('txtVMLocation').Text = (Join-Path $FFUDevelopmentPath "VM")
    # <-- NEW: Set the default for the new VM Name Prefix textbox on the Hyper-V Settings tab
    $window.FindName('txtVMNamePrefix').Text = $defaultFFUPrefix
    # Hyper-V Settings: Populate defaults (Share Name and Username now on Build, so only populate remaining fields)
    $script:vmSwitchMap = @{}
    $script:allSwitches = Get-VMSwitch -ErrorAction SilentlyContinue
    $script:cmbVMSwitchName = $window.FindName('cmbVMSwitchName')
    foreach ($sw in $script:allSwitches) {
        $script:cmbVMSwitchName.Items.Add($sw.Name) | Out-Null
        $na = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*($($sw.Name))*" }
        if ($na) {
            $netIPs = Get-NetIPAddress -InterfaceIndex $na.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
            $validIPs = $netIPs | Where-Object { $_.IPAddress -notlike '169.254.*' -and $_.IPAddress }
            if ($validIPs) { $script:vmSwitchMap[$sw.Name] = ($validIPs | Select-Object -First 1).IPAddress }
        }
    }
    $script:cmbVMSwitchName.Items.Add('Other') | Out-Null
    if ($script:cmbVMSwitchName.Items.Count -gt 0) {
        if ($script:allSwitches.Count -gt 0) {
            $script:cmbVMSwitchName.SelectedIndex = 0
            $first = $script:cmbVMSwitchName.SelectedItem
            if ($script:vmSwitchMap.ContainsKey($first)) { $window.FindName('txtVMHostIPAddress').Text = $script:vmSwitchMap[$first] }
            else { $window.FindName('txtVMHostIPAddress').Text = '' }
        }
        else {
            $script:cmbVMSwitchName.SelectedItem = 'Other'
            $window.FindName('txtCustomVMSwitchName').Visibility = 'Visible'
        }
    }
    $script:cmbVMSwitchName.Add_SelectionChanged({
        if ($_.AddedItems -contains 'Other') {
            $window.FindName('txtCustomVMSwitchName').Visibility = 'Visible'
            $window.FindName('txtVMHostIPAddress').Text = ''
        }
        else {
            $window.FindName('txtCustomVMSwitchName').Visibility = 'Collapsed'
            $sel = $_.AddedItems[0]
            if ($script:vmSwitchMap.ContainsKey($sel)) { $window.FindName('txtVMHostIPAddress').Text = $script:vmSwitchMap[$sel] }
            else { $window.FindName('txtVMHostIPAddress').Text = '' }
        }
    })
    # Windows Arch, Lang, SKU, etc.
    $script:cmbWindowsArch = $window.FindName('cmbWindowsArch')
    foreach ($a in 'x86','x64','arm64') { [void]$script:cmbWindowsArch.Items.Add($a) }
    $script:cmbWindowsArch.SelectedItem = $defaultWindowsArch
    $script:cmbWindowsLang = $window.FindName('cmbWindowsLang')
    $allowedLangs = @(
        'ar-sa','bg-bg','cs-cz','da-dk','de-de','el-gr','en-gb','en-us','es-es','es-mx','et-ee',
        'fi-fi','fr-ca','fr-fr','he-il','hr-hr','hu-hu','it-it','ja-jp','ko-kr','lt-lt','lv-lv',
        'nb-no','nl-nl','pl-pl','pt-br','pt-pt','ro-ro','ru-ru','sk-sk','sl-si','sr-latn-rs',
        'sv-se','th-th','tr-tr','uk-ua','zh-cn','zh-tw'
    )
    foreach ($lang in $allowedLangs) { [void]$script:cmbWindowsLang.Items.Add($lang) }
    $script:cmbWindowsLang.SelectedItem = $defaultWindowsLang
    $script:cmbWindowsSKU = $window.FindName('cmbWindowsSKU')
    $script:cmbWindowsSKU.Items.Clear()
    foreach ($sku in $skuList) { [void]$script:cmbWindowsSKU.Items.Add($sku) }
    $script:cmbWindowsSKU.SelectedItem = $defaultWindowsSKU
    $script:cmbMediaType = $window.FindName('cmbMediaType')
    foreach ($mt in "Consumer","Business") { [void]$script:cmbMediaType.Items.Add($mt) }  # updated options
    $script:cmbMediaType.SelectedItem = $defaultMediaType
    $script:txtOptionalFeatures = $window.FindName('txtOptionalFeatures')
    $script:txtOptionalFeatures.Text = $defaultOptionalFeatures
    $window.FindName('txtProductKey').Text = $defaultProductKey
    # Drivers tab
    $script:chkDownloadDrivers = $window.FindName('chkDownloadDrivers')
    $script:cmbMake = $window.FindName('cmbMake')
    $script:cmbModel = $window.FindName('cmbModel')
    $script:spMakeModelSection = $window.FindName('spMakeModelSection')
    $makeList = @('Microsoft','Dell','HP','Lenovo')
    foreach ($m in $makeList) { [void]$script:cmbMake.Items.Add($m) }
    if ($script:cmbMake.Items.Count -gt 0) { $script:cmbMake.SelectedIndex = 0 }
    $script:chkDownloadDrivers.Add_Checked({
        $script:cmbMake.Visibility = 'Visible'
        $script:cmbModel.Visibility = 'Visible'
        $script:spMakeModelSection.Visibility = 'Visible'
    })
    $script:chkDownloadDrivers.Add_Unchecked({
        $script:cmbMake.Visibility = 'Collapsed'
        $script:cmbModel.Visibility = 'Collapsed'
        $script:spMakeModelSection.Visibility = 'Collapsed'
    })
    # Office interplay
    $script:chkInstallOffice = $window.FindName('chkInstallOffice')
    $script:chkInstallApps = $window.FindName('chkInstallApps')
    $script:installAppsCheckedByOffice = $false
    $script:OfficePathStackPanel = $window.FindName('OfficePathStackPanel')
    $script:OfficePathGrid = $window.FindName('OfficePathGrid')
    $script:CopyOfficeConfigXMLStackPanel = $window.FindName('CopyOfficeConfigXMLStackPanel')
    $script:OfficeConfigurationXMLFileStackPanel = $window.FindName('OfficeConfigurationXMLFileStackPanel')
    $script:OfficeConfigurationXMLFileGrid = $window.FindName('OfficeConfigurationXMLFileGrid')
    $script:chkCopyOfficeConfigXML = $window.FindName('chkCopyOfficeConfigXML')
    if ($script:chkInstallOffice.IsChecked) {
        $script:OfficePathStackPanel.Visibility = 'Visible'
        $script:OfficePathGrid.Visibility = 'Visible'
        $script:CopyOfficeConfigXMLStackPanel.Visibility = 'Visible'
    }
    else {
        $script:OfficePathStackPanel.Visibility = 'Collapsed'
        $script:OfficePathGrid.Visibility = 'Collapsed'
        $script:CopyOfficeConfigXMLStackPanel.Visibility = 'Collapsed'
        $script:OfficeConfigurationXMLFileStackPanel.Visibility = 'Collapsed'
        $script:OfficeConfigurationXMLFileGrid.Visibility = 'Collapsed'
    }
    $script:chkInstallOffice.Add_Checked({
        if (-not $script:chkInstallApps.IsChecked) {
            $script:chkInstallApps.IsChecked = $true
            $script:installAppsCheckedByOffice = $true
        }
        $script:chkInstallApps.IsEnabled = $false
        $script:OfficePathStackPanel.Visibility = 'Visible'
        $script:OfficePathGrid.Visibility = 'Visible'
        $script:CopyOfficeConfigXMLStackPanel.Visibility = 'Visible'
    })
    $script:chkInstallOffice.Add_Unchecked({
        if ($script:installAppsCheckedByOffice) {
            $script:chkInstallApps.IsChecked = $false
            $script:installAppsCheckedByOffice = $false
        }
        $script:chkInstallApps.IsEnabled = $true
        $script:OfficePathStackPanel.Visibility = 'Collapsed'
        $script:OfficePathGrid.Visibility = 'Collapsed'
        $script:CopyOfficeConfigXMLStackPanel.Visibility = 'Collapsed'
        $script:OfficeConfigurationXMLFileStackPanel.Visibility = 'Collapsed'
        $script:OfficeConfigurationXMLFileGrid.Visibility = 'Collapsed'
    })
    $script:chkCopyOfficeConfigXML.Add_Checked({
        $script:OfficeConfigurationXMLFileStackPanel.Visibility = 'Visible'
        $script:OfficeConfigurationXMLFileGrid.Visibility = 'Visible'
    })
    $script:chkCopyOfficeConfigXML.Add_Unchecked({
        $script:OfficeConfigurationXMLFileStackPanel.Visibility = 'Collapsed'
        $script:OfficeConfigurationXMLFileGrid.Visibility = 'Collapsed'
    })
    # Build dynamic multi-column checkboxes for optional features in Windows Settings tab
    $script:featuresPanel = $window.FindName('stackFeaturesContainer')
    if ($script:featuresPanel) { BuildFeaturesGrid -parent $script:featuresPanel }
    # Variables for managing forced Install Apps state due to Updates
    $script:installAppsForcedByUpdates = $false
    $script:prevInstallAppsStateBeforeUpdates = $null
    # Define the function in script scope to update Install Apps based on Updates tab
    $script:UpdateInstallAppsBasedOnUpdates = {
        $anyUpdateChecked = $window.FindName('chkUpdateLatestDefender').IsChecked -or $window.FindName('chkUpdateEdge').IsChecked -or $window.FindName('chkUpdateOneDrive').IsChecked -or $window.FindName('chkUpdateLatestMSRT').IsChecked
        if ($anyUpdateChecked) {
            if (-not $script:installAppsForcedByUpdates) {
                $script:prevInstallAppsStateBeforeUpdates = $window.FindName('chkInstallApps').IsChecked
                $script:installAppsForcedByUpdates = $true
            }
            $window.FindName('chkInstallApps').IsChecked = $true
            $window.FindName('chkInstallApps').IsEnabled = $false
        } else {
            if ($script:installAppsForcedByUpdates) {
                $window.FindName('chkInstallApps').IsChecked = $script:prevInstallAppsStateBeforeUpdates
                $script:installAppsForcedByUpdates = $false
                $script:prevInstallAppsStateBeforeUpdates = $null
            }
            $window.FindName('chkInstallApps').IsEnabled = $true
        }
    }
    # Add event handlers for Updates tab checkboxes to update Install Apps state
    $window.FindName('chkUpdateLatestDefender').Add_Checked({ & $script:UpdateInstallAppsBasedOnUpdates })
    $window.FindName('chkUpdateLatestDefender').Add_Unchecked({ & $script:UpdateInstallAppsBasedOnUpdates })
    $window.FindName('chkUpdateEdge').Add_Checked({ & $script:UpdateInstallAppsBasedOnUpdates })
    $window.FindName('chkUpdateEdge').Add_Unchecked({ & $script:UpdateInstallAppsBasedOnUpdates })
    $window.FindName('chkUpdateOneDrive').Add_Checked({ & $script:UpdateInstallAppsBasedOnUpdates })
    $window.FindName('chkUpdateOneDrive').Add_Unchecked({ & $script:UpdateInstallAppsBasedOnUpdates })
    $window.FindName('chkUpdateLatestMSRT').Add_Checked({ & $script:UpdateInstallAppsBasedOnUpdates })
    $window.FindName('chkUpdateLatestMSRT').Add_Unchecked({ & $script:UpdateInstallAppsBasedOnUpdates })
    # Add interplay between Latest CU and Preview CU checkboxes
    $script:chkLatestCU = $window.FindName('chkUpdateLatestCU')
    $script:chkPreviewCU = $window.FindName('chkUpdatePreviewCU')
    
    $script:chkLatestCU.Add_Checked({
        $script:chkPreviewCU.IsEnabled = $false
    })
    $script:chkLatestCU.Add_Unchecked({
        $script:chkPreviewCU.IsEnabled = $true
    })
    
    $script:chkPreviewCU.Add_Checked({
        $script:chkLatestCU.IsEnabled = $false
    })
    $script:chkPreviewCU.Add_Unchecked({
        $script:chkLatestCU.IsEnabled = $true
    })

    # Add USB Drive Detection handler
    $script:btnCheckUSBDrives = $window.FindName('btnCheckUSBDrives')
    $script:lstUSBDrives = $window.FindName('lstUSBDrives')
    $script:chkSelectAllUSBDrives = $window.FindName('chkSelectAllUSBDrives')
    
    $script:btnCheckUSBDrives.Add_Click({
        $script:lstUSBDrives.Items.Clear()
        $usbDrives = Get-USBDrives
        foreach ($drive in $usbDrives) {
            $script:lstUSBDrives.Items.Add([PSCustomObject]$drive)
        }
        if ($script:lstUSBDrives.Items.Count -gt 0) {
            $script:lstUSBDrives.SelectedIndex = 0
        }
    })
    
    # Handle Select All checkbox
    $script:chkSelectAllUSBDrives.Add_Checked({
        foreach ($item in $script:lstUSBDrives.Items) {
            $item.IsSelected = $true
        }
        $script:lstUSBDrives.Items.Refresh()
    })

    $script:chkSelectAllUSBDrives.Add_Unchecked({
        foreach ($item in $script:lstUSBDrives.Items) {
            $item.IsSelected = $false
        }
        $script:lstUSBDrives.Items.Refresh()
    })

    # Add keyboard handler
    $script:lstUSBDrives.Add_KeyDown({
        param($sender, $e)
        if ($e.Key -eq 'Space') {
            $selectedItem = $script:lstUSBDrives.SelectedItem
            if ($selectedItem) {
                $selectedItem.IsSelected = !$selectedItem.IsSelected
                $script:lstUSBDrives.Items.Refresh()
                # Update Select All checkbox state
                $allSelected = -not ($script:lstUSBDrives.Items | Where-Object { -not $_.IsSelected })
                $script:chkSelectAllUSBDrives.IsChecked = $allSelected
            }
        }
    })

    # Add selection change handler
    $script:lstUSBDrives.Add_SelectionChanged({
        param($sender, $e)
        # Update Select All checkbox state
        $allSelected = -not ($script:lstUSBDrives.Items | Where-Object { -not $_.IsSelected })
        $script:chkSelectAllUSBDrives.IsChecked = $allSelected
    })

    # Add handler to show/hide USB drive section based on Build USB Drive checkbox
    $script:chkBuildUSBDriveEnable = $window.FindName('chkBuildUSBDriveEnable')
    $script:usbSection = $window.FindName('usbDriveSection')
    $script:chkSelectSpecificUSBDrives = $window.FindName('chkSelectSpecificUSBDrives')
    $script:usbSelectionPanel = $window.FindName('usbDriveSelectionPanel')
    
    # Set initial visibility states
    $script:usbSection.Visibility = if ($script:chkBuildUSBDriveEnable.IsChecked) { 'Visible' } else { 'Collapsed' }
    $script:usbSelectionPanel.Visibility = if ($script:chkSelectSpecificUSBDrives.IsChecked) { 'Visible' } else { 'Collapsed' }
    
    $script:chkBuildUSBDriveEnable.Add_Checked({
        $script:usbSection.Visibility = 'Visible'
        $script:chkSelectSpecificUSBDrives.IsEnabled = $true
    })
    
    $script:chkBuildUSBDriveEnable.Add_Unchecked({
        $script:usbSection.Visibility = 'Collapsed'
        $script:chkSelectSpecificUSBDrives.IsEnabled = $false
        $script:chkSelectSpecificUSBDrives.IsChecked = $false
        $script:lstUSBDrives.Items.Clear()
        $script:chkSelectAllUSBDrives.IsChecked = $false
    })

    # Add handler to show/hide USB drive selection panel based on Select Specific USB Drives checkbox
    $script:chkSelectSpecificUSBDrives.Add_Checked({
        $script:usbSelectionPanel.Visibility = 'Visible'
    })
    
    $script:chkSelectSpecificUSBDrives.Add_Unchecked({
        $script:usbSelectionPanel.Visibility = 'Collapsed'
        $script:lstUSBDrives.Items.Clear()
        $script:chkSelectAllUSBDrives.IsChecked = $false
    })

    # Set initial state of Select Specific USB Drives checkbox
    $script:chkSelectSpecificUSBDrives.IsEnabled = $script:chkBuildUSBDriveEnable.IsChecked

    # Add handler for Allow External Hard Disk Media checkbox
    $script:chkAllowExternalHardDiskMedia = $window.FindName('chkAllowExternalHardDiskMedia')
    $script:chkPromptExternalHardDiskMedia = $window.FindName('chkPromptExternalHardDiskMedia')
    
    $script:chkAllowExternalHardDiskMedia.Add_Checked({
        $script:chkPromptExternalHardDiskMedia.IsEnabled = $true
    })
    
    $script:chkAllowExternalHardDiskMedia.Add_Unchecked({
        $script:chkPromptExternalHardDiskMedia.IsEnabled = $false
        $script:chkPromptExternalHardDiskMedia.IsChecked = $false
    })

    # Add Winget panel visibility handler
    $script:chkInstallApps = $window.FindName('chkInstallApps')
    $script:chkInstallWingetApps = $window.FindName('chkInstallWingetApps')
    $script:wingetPanel = $window.FindName('wingetPanel')
    $script:btnCheckWingetModule = $window.FindName('btnCheckWingetModule')
    $script:txtWingetVersion = $window.FindName('txtWingetVersion')
    $script:txtWingetModuleVersion = $window.FindName('txtWingetModuleVersion')

    # Hide Winget Apps checkbox initially if Install Apps is unchecked
    $script:chkInstallWingetApps.Visibility = if ($script:chkInstallApps.IsChecked) { 'Visible' } else { 'Collapsed' }
    
    # Show/Hide Winget Apps checkbox based on Install Apps state
    $script:chkInstallApps.Add_Checked({ 
        $script:chkInstallWingetApps.Visibility = 'Visible' 
    })
    $script:chkInstallApps.Add_Unchecked({ 
        $script:chkInstallWingetApps.IsChecked = $false
        $script:chkInstallWingetApps.Visibility = 'Collapsed'
        $script:wingetPanel.Visibility = 'Collapsed'
    })

    # Show/Hide Winget panel based on checkbox state
    $script:chkInstallWingetApps.Add_Checked({ $script:wingetPanel.Visibility = 'Visible' })
    $script:chkInstallWingetApps.Add_Unchecked({ $script:wingetPanel.Visibility = 'Collapsed' })

    # Handle Winget component check/installation
    $script:btnCheckWingetModule.Add_Click({
        $this.IsEnabled = $false
        $window.Cursor = [System.Windows.Input.Cursors]::Wait
        
        # Show initial checking status
        Update-WingetVersionFields -wingetText "Checking..." -moduleText "Checking..."
        
        # Run checks in background to prevent UI freezing
        $window.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{
            try {
                # Check Winget CLI first
                $cliStatus = Test-WingetCLI
                
                # Install/Update PowerShell module if needed
                $module = Install-WingetComponents -currentWingetVersion $cliStatus.Status
                
                # Update UI with final status
                Update-WingetVersionFields -wingetText $cliStatus.Status -moduleText $module.Version
            }
            catch {
                Update-WingetVersionFields -wingetText "Error" -moduleText "Error"
                [System.Windows.MessageBox]::Show(
                    "Error checking winget components: $_",
                    "Error",
                    "OK",
                    "Error"
                )
            }
            finally {
                $this.IsEnabled = $true
                $window.Cursor = $null
            }
        })
    })
})

# Button: Build FFU
$btnRun = $window.FindName('btnRun')
$btnRun.Add_Click({
    try {
        $progressBar = $window.FindName('progressBar')
        $txtStatus = $window.FindName('txtStatus')
        $progressBar.Visibility = 'Visible'
        $txtStatus.Text = "Starting FFU build..."
        $config = Get-UIConfig
        $configFilePath = Join-Path $config.FFUDevelopmentPath "FFUConfig.json"
        $config | ConvertTo-Json -Depth 10 | Set-Content $configFilePath -Encoding UTF8
        $txtStatus.Text = "Executing BuildFFUVM script with config file..."
        & "$PSScriptRoot\BuildFFUVM.ps1" -ConfigFile $configFilePath -Verbose
        if ($config.InstallOffice -and $config.OfficeConfigXMLFile) {
            Copy-Item -Path $config.OfficeConfigXMLFile -Destination $config.OfficePath -Force
            $txtStatus.Text = "Office Configuration XML file copied successfully."
        }
        $txtStatus.Text = "FFU build completed successfully."
    }
    catch {
        [System.Windows.MessageBox]::Show("An error occurred: $_", "Error", "OK", "Error")
        $window.FindName('txtStatus').Text = "FFU build failed."
    }
    finally {
        $window.FindName('progressBar').Visibility = 'Collapsed'
    }
})

# Button: Build Config
$btnBuildConfig = $window.FindName('btnBuildConfig')
$btnBuildConfig.Add_Click({
    try {
        $config = Get-UIConfig
        $defaultConfigPath = Join-Path $config.FFUDevelopmentPath "config"
        if (-not (Test-Path $defaultConfigPath)) {
            New-Item -Path $defaultConfigPath -ItemType Directory -Force | Out-Null
        }
        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*"
        $sfd.Title = "Save Configuration File"
        $sfd.InitialDirectory = $defaultConfigPath
        $sfd.FileName = "FFUConfig.json"
        if ($sfd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $savePath = $sfd.FileName
            $config | ConvertTo-Json -Depth 10 | Set-Content $savePath -Encoding UTF8
            [System.Windows.MessageBox]::Show("Configuration file saved to:`n$savePath", "Success", "OK", "Information")
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Error saving config file:`n$_","Error","OK","Error")
    }
})

# Button: Load Config File
$btnLoadConfig = $window.FindName('btnLoadConfig')
$btnLoadConfig.Add_Click({
    try {
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*"
        $ofd.Title = "Load Configuration File"
        if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $configContent = Get-Content -Path $ofd.FileName -Raw | ConvertFrom-Json
            # Update Build tab values
            $window.FindName('txtFFUDevPath').Text = $configContent.FFUDevelopmentPath
            $window.FindName('txtCustomFFUNameTemplate').Text = $configContent.CustomFFUNameTemplate
            $window.FindName('txtFFUCaptureLocation').Text = $configContent.FFUCaptureLocation
            $window.FindName('txtShareName').Text = $configContent.ShareName
            $window.FindName('txtUsername').Text = $configContent.Username
            $window.FindName('chkBuildUSBDriveEnable').IsChecked = $configContent.BuildUSBDrive
            $window.FindName('chkCompactOS').IsChecked = $configContent.CompactOS
            $window.FindName('chkOptimize').IsChecked = $configContent.Optimize
            $window.FindName('chkAllowVHDXCaching').IsChecked = $configContent.AllowVHDXCaching
            $window.FindName('chkAllowExternalHardDiskMedia').IsChecked = $configContent.AllowExternalHardDiskMedia
            $window.FindName('chkPromptExternalHardDiskMedia').IsChecked = $configContent.PromptExternalHardDiskMedia
            $window.FindName('chkCreateCaptureMedia').IsChecked = $configContent.CreateCaptureMedia
            $window.FindName('chkCreateDeploymentMedia').IsChecked = $configContent.CreateDeploymentMedia

            # USB Drive Modification group
            $window.FindName('chkCopyAutopilot').IsChecked = $configContent.CopyAutopilot
            $window.FindName('chkCopyUnattend').IsChecked = $configContent.CopyUnattend
            $window.FindName('chkCopyPPKG').IsChecked = $configContent.CopyPPKG

            # Post Build Cleanup group
            $window.FindName('chkCleanupAppsISO').IsChecked = $configContent.CleanupAppsISO
            $window.FindName('chkCleanupCaptureISO').IsChecked = $configContent.CleanupCaptureISO
            $window.FindName('chkCleanupDeployISO').IsChecked = $configContent.CleanupDeployISO
            $window.FindName('chkCleanupDrivers').IsChecked = $configContent.CleanupDrivers
            $window.FindName('chkRemoveFFU').IsChecked = $configContent.RemoveFFU
            # USB Drive Modification group (now in Build USB Drive section)
            $window.FindName('chkCopyAutopilot').IsChecked = $configContent.CopyAutopilot
            $window.FindName('chkCopyUnattend').IsChecked = $configContent.CopyUnattend
            $window.FindName('chkCopyPPKG').IsChecked = $configContent.CopyPPKG
            # Hyper-V Settings
            $window.FindName('cmbVMSwitchName').SelectedItem = $configContent.VMSwitchName
            $window.FindName('txtVMHostIPAddress').Text = $configContent.VMHostIPAddress
            $window.FindName('txtDiskSize').Text = $configContent.Disksize / 1GB
            $window.FindName('txtMemory').Text = $configContent.Memory / 1GB
            $window.FindName('txtProcessors').Text = $configContent.Processors
            $window.FindName('txtVMLocation').Text = $configContent.VMLocation
            # <-- NEW: Update the VM Name Prefix textbox value during config load
            $window.FindName('txtVMNamePrefix').Text = $configContent.FFUPrefix
            $window.FindName('cmbLogicalSectorSize').SelectedItem = $configContent.LogicalSectorSizeBytes
            # Windows Settings
            $window.FindName('txtISOPath').Text = $configContent.ISOPath
            $window.FindName('cmbWindowsRelease').SelectedItem = ($script:allWindowsReleases | Where-Object { $_.Value -eq $configContent.WindowsRelease })
            $window.FindName('cmbWindowsVersion').SelectedItem = $configContent.WindowsVersion
            $window.FindName('cmbWindowsArch').SelectedItem = $configContent.WindowsArch
            $window.FindName('cmbWindowsLang').SelectedItem = $configContent.WindowsLang
            $window.FindName('cmbWindowsSKU').SelectedItem = $configContent.WindowsSKU
            $window.FindName('cmbMediaType').SelectedItem = $configContent.MediaType
            $window.FindName('txtProductKey').Text = $configContent.ProductKey
            # M365 Apps/Office tab
            $window.FindName('chkInstallOffice').IsChecked = $configContent.InstallOffice
            $window.FindName('txtOfficePath').Text = $configContent.OfficePath
            $window.FindName('chkCopyOfficeConfigXML').IsChecked = $configContent.CopyOfficeConfigXML
            $window.FindName('txtOfficeConfigXMLFilePath').Text = $configContent.OfficeConfigXMLFile
            # Drivers tab
            $window.FindName('chkInstallDrivers').IsChecked = $configContent.InstallDrivers
            $window.FindName('chkDownloadDrivers').IsChecked = $configContent.DownloadDrivers
            $window.FindName('chkCopyDrivers').IsChecked = $configContent.CopyDrivers
            $window.FindName('cmbMake').SelectedItem = $configContent.Make
            $window.FindName('cmbModel').Text = $configContent.Model
            $window.FindName('txtDriversFolder').Text = $configContent.DriversFolder
            $window.FindName('txtPEDriversFolder').Text = $configContent.PEDriversFolder
            $window.FindName('chkCopyPEDrivers').IsChecked = $configContent.CopyPEDrivers
            # Updates tab
            $window.FindName('chkUpdateLatestCU').IsChecked = $configContent.UpdateLatestCU
            $window.FindName('chkUpdateLatestNet').IsChecked = $configContent.UpdateLatestNet
            $window.FindName('chkUpdateLatestDefender').IsChecked = $configContent.UpdateLatestDefender
            $window.FindName('chkUpdateEdge').IsChecked = $configContent.UpdateEdge
            $window.FindName('chkUpdateOneDrive').IsChecked = $configContent.UpdateOneDrive
            $window.FindName('chkUpdateLatestMSRT').IsChecked = $configContent.UpdateLatestMSRT
            $window.FindName('chkUpdatePreviewCU').IsChecked = $configContent.UpdatePreviewCU
            # Applications tab
            $window.FindName('chkInstallApps').IsChecked = $configContent.InstallApps
            $window.FindName('chkInstallWingetApps').IsChecked = $configContent.InstallWingetApps

            # Update USB Drive selection if present in config
            if ($configContent.USBDriveList) {
                # First click the Check USB Drives button to populate the list
                $script:btnCheckUSBDrives.RaiseEvent(
                    [System.Windows.RoutedEventArgs]::new(
                        [System.Windows.Controls.Button]::ClickEvent
                    )
                )
                
                # Then select the drives that match the saved configuration
                foreach ($item in $script:lstUSBDrives.Items) {
                    if ($configContent.USBDriveList.ContainsKey($item.Model) -and 
                        $configContent.USBDriveList[$item.Model] -eq $item.SerialNumber) {
                        $item.IsSelected = $true
                    }
                }
                $script:lstUSBDrives.Items.Refresh()

                # Update the Select All checkbox state
                $allSelected = -not ($script:lstUSBDrives.Items | Where-Object { -not $_.IsSelected })
                $script:chkSelectAllUSBDrives.IsChecked = $allSelected
            }
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Error loading config file:`n$_","Error","OK","Error")
    }
})

[void]$window.ShowDialog()
