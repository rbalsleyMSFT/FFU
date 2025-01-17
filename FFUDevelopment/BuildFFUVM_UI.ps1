[CmdletBinding()]
[System.STAThread()]
param()

# --------------------------------------------------------------------------
# SECTION 1: Variables & Constants
# --------------------------------------------------------------------------
$FFUDevelopmentPath = $PSScriptRoot
$infoImagePath      = Join-Path $PSScriptRoot "info.png"
$AppsPath           = Join-Path $FFUDevelopmentPath "Apps"
$OfficePath         = Join-Path $AppsPath "Office"

# Some default values
$defaultISOPath         = ""
$defaultWindowsRelease   = 11   # numeric
$defaultWindowsArch      = "x64"
$defaultWindowsLang      = "en-us"
$defaultWindowsSKU       = "Pro"
$defaultMediaType        = "consumer"
$defaultOptionalFeatures = ""
$defaultProductKey       = ""

# Large list from the ValidateSet in BuildFFUVM.ps1 ($OptionalFeatures parameter)
$allowedFeatures = @(
    "AppServerClient","Client-DeviceLockdown","Client-EmbeddedBootExp","Client-EmbeddedLogon",
    "Client-EmbeddedShellLauncher","Client-KeyboardFilter","Client-ProjFS","Client-UnifiedWriteFilter",
    "Containers","Containers-DisposableClientVM","Containers-HNS","Containers-SDN","DataCenterBridging",
    "DirectoryServices-ADAM-Client","DirectPlay","HostGuardian","HypervisorPlatform","IIS-ApplicationDevelopment",
    "IIS-ApplicationInit","IIS-ASP","IIS-ASPNET","IIS-ASPNET45","IIS-BasicAuthentication","IIS-CertProvider",
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
    "WCF-MSMQ-Activation45","WCF-NonHTTP-Activation","WCF-Pipe-Activation45","WCF-Services45","WCF-TCP-Activation45",
    "WCF-TCP-PortSharing45","Windows-Defender-ApplicationGuard","Windows-Defender-Default-Definitions","Windows-Identity-Foundation",
    "WindowsMediaPlayer","WorkFolders-Client"
)

$skuList = @(
    'Home','Home N','Home Single Language','Education','Education N','Pro',
    'Pro N','Pro Education','Pro Education N','Pro for Workstations',
    'Pro N for Workstations','Enterprise','Enterprise N','Standard',
    'Standard (Desktop Experience)','Datacenter','Datacenter (Desktop Experience)'
)

$imageNames = @(
    "imgFFUNameInfo",
    "imgISOPathInfo",
    "imgWindowsSKUInfo",
    "imgVMSwitchNameInfo",
    "imgVMHostIPAddressInfo",
    "imgInstallOfficeInfo",
    "imgInstallAppsInfo",
    "imgInstallDriversInfo",
    "imgCopyDriversInfo",
    "imgFFUDevPathInfo",
    "imgOfficePathInfo",
    "imgCopyOfficeConfigXMLInfo",
    "imgOfficeConfigXMLFileInfo",
    "imgMakeInfo",
    "imgModelInfo",
    "imgDownloadDriversInfo",
    "imgDriversFolderInfo",
    "imgPEDriversFolderInfo",
    "imgCopyPEDriversInfo"
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
function Set-ImageSource {
    param(
        [System.Windows.Window]$window,
        [string]$imageName,
        [string]$sourcePath
    )
    $imgControl = $window.FindName($imageName)
    if ($imgControl) {
        $uri    = New-Object System.Uri($sourcePath, [System.UriKind]::Absolute)
        $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage($uri)
        $imgControl.Source = $bitmap
    }
}

function Get-UIConfig {
    # Basic tab
    $ffuDevPath       = $window.FindName('txtFFUDevPath').Text
    $ffuName          = $window.FindName('txtFFUName').Text
    $vmSwitchSelected = $window.FindName('cmbVMSwitchName').SelectedItem
    $customVMSwitch   = $window.FindName('txtCustomVMSwitchName').Text
    $vmHostIPAddress  = $window.FindName('txtVMHostIPAddress').Text

    # Windows tab
    $wrItem = $window.FindName('cmbWindowsRelease').SelectedItem
    $windowsRelease = if ($wrItem -and $wrItem.Value) {
        [int]$wrItem.Value
    } else {
        10
    }
    $windowsVersion  = $window.FindName('cmbWindowsVersion').SelectedItem
    $windowsArch     = $window.FindName('cmbWindowsArch').SelectedItem
    $windowsLang     = $window.FindName('cmbWindowsLang').SelectedItem
    $windowsSKU      = $window.FindName('cmbWindowsSKU').SelectedItem
    $mediaType       = $window.FindName('cmbMediaType').SelectedItem
    $optionalFeatures= $window.FindName('txtOptionalFeatures').Text
    $productKey      = $window.FindName('txtProductKey').Text
    $isoPath         = $window.FindName('txtISOPath').Text

    # Apps tab
    $installApps = $window.FindName('chkInstallApps').IsChecked

    # Office tab
    $installOffice       = $window.FindName('chkInstallOffice').IsChecked
    $officePath          = $window.FindName('txtOfficePath').Text
    $copyOfficeConfig    = $window.FindName('chkCopyOfficeConfigXML').IsChecked
    $officeConfigXMLFile = $window.FindName('txtOfficeConfigXMLFilePath').Text

    # Drivers tab
    $installDrivers  = $window.FindName('chkInstallDrivers').IsChecked
    $copyDrivers     = $window.FindName('chkCopyDrivers').IsChecked
    $downloadDrivers = $window.FindName('chkDownloadDrivers').IsChecked
    $make            = $window.FindName('cmbMake').SelectedItem
    $model           = $window.FindName('cmbModel').Text
    $driversFolder   = $window.FindName('txtDriversFolder').Text
    $peDriversFolder = $window.FindName('txtPEDriversFolder').Text
    $copyPEDrivers   = $window.FindName('chkCopyPEDrivers').IsChecked

    # Basic validations
    if (-not $ffuDevPath) {
        throw "FFU Development Path is required."
    }
    if ($installDrivers -and (-not $driversFolder)) {
        throw "Drivers Folder is required when Install Drivers is checked."
    }
    if ($copyDrivers -and (-not $driversFolder)) {
        throw "Drivers Folder is required when Copy Drivers is checked."
    }
    if ($copyPEDrivers -and (-not $peDriversFolder)) {
        throw "PE Drivers Folder is required when Copy PE Drivers is checked."
    }
    if ($downloadDrivers -and (-not $make)) {
        throw "Make is required when Download Drivers is checked."
    }
    if ($downloadDrivers -and (-not $model)) {
        throw "Model is required when Download Drivers is checked."
    }

    # If user picks 'Other' for VM Switch, use custom
    $vmSwitchName = if ($vmSwitchSelected -eq 'Other') { $customVMSwitch } else { $vmSwitchSelected }

    # Build config
    $config = [ordered]@{
        AppsPath            = $AppsPath
        CopyDrivers         = $copyDrivers
        CopyPEDrivers       = $copyPEDrivers
        CopyOfficeConfigXML = $copyOfficeConfig
        DriversFolder       = $driversFolder
        DownloadDrivers     = $downloadDrivers
        FFUDevelopmentPath  = $ffuDevPath
        FFUName             = $ffuName
        InstallApps         = $installApps
        InstallDrivers      = $installDrivers
        InstallOffice       = $installOffice
        ISOPath             = $isoPath
        Make                = if ($downloadDrivers) { $make } else { $null }
        MediaType           = $mediaType
        Model               = if ($downloadDrivers) { $model } else { $null }
        OfficeConfigXMLFile = if ($installOffice -and $copyOfficeConfig) { $officeConfigXMLFile } else { $null }
        OfficePath          = $officePath
        OptionalFeatures    = $optionalFeatures
        PEDriversFolder     = $peDriversFolder
        ProductKey          = $productKey
        VMHostIPAddress     = $vmHostIPAddress
        VMSwitchName        = $vmSwitchName
        WindowsArch         = $windowsArch
        WindowsLang         = $windowsLang
        WindowsRelease      = $windowsRelease
        WindowsSKU          = $windowsSKU
        WindowsVersion      = $windowsVersion
    }
    return $config
}

function UpdateWindowsReleaseList {
    param([string]$isoPath)

    if (-not $script:cmbWindowsRelease) { return }

    $oldItem = $script:cmbWindowsRelease.SelectedItem
    $script:cmbWindowsRelease.Items.Clear()

    $script:cmbWindowsRelease.DisplayMemberPath = 'Display'
    $script:cmbWindowsRelease.SelectedValuePath = 'Value'

    if ([string]::IsNullOrEmpty($isoPath)) {
        # Only MCT
        foreach ($rel in $mctWindowsReleases) {
            $script:cmbWindowsRelease.Items.Add($rel) | Out-Null
        }
    }
    else {
        # Full list
        foreach ($rel in $allWindowsReleases) {
            $script:cmbWindowsRelease.Items.Add($rel) | Out-Null
        }
    }

    if ($oldItem) {
        $reSelect = $script:cmbWindowsRelease.Items | Where-Object { $_.Value -eq $oldItem.Value }
        if ($reSelect) {
            $script:cmbWindowsRelease.SelectedItem = $reSelect
        }
        else {
            $script:cmbWindowsRelease.SelectedIndex = 0
        }
    }
    else {
        $script:cmbWindowsRelease.SelectedIndex = 0
    }
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
        # MCT usage => locked & pick default
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
        # ISO => user can choose
        foreach ($v in $validVersions) {
            [void]$combo.Items.Add($v)
        }

        # If Windows 11 => default to 24H2 if available
        if ($selectedRelease -eq 11 -and $validVersions -contains "24H2") {
            $combo.SelectedItem = "24H2"
        }
        else {
            $combo.SelectedIndex = 0
        }

        $combo.IsEnabled = $true
    }
}

$script:RefreshWindowsUI = {
    param([string]$isoPath)

    UpdateWindowsReleaseList -isoPath $isoPath

    $selItem = $script:cmbWindowsRelease.SelectedItem
    if ($selItem -and $selItem.Value -is [int]) {
        $selectedRelease = [int]$selItem.Value
    }
    else {
        $selectedRelease = 10
    }
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
$reader     = New-Object System.IO.StringReader($xamlString)
$xmlReader  = [System.Xml.XmlReader]::Create($reader)
$window     = [Windows.Markup.XamlReader]::Load($xmlReader)

# Assign images
foreach ($imgName in $imageNames) {
    Set-ImageSource -window $window -imageName $imgName -sourcePath $infoImagePath
}

# We'll store dynamic checkboxes for each optional feature
$script:featureCheckBoxes = @{}

function UpdateOptionalFeaturesString {
    # Collect all features that are checked
    $checkedFeatures = @()
    foreach ($entry in $script:featureCheckBoxes.GetEnumerator()) {
        if ($entry.Value.IsChecked) {
            $checkedFeatures += $entry.Key
        }
    }
    $script:txtOptionalFeatures.Text = $checkedFeatures -join ";"
}

# Create the dynamic multi-column grid of feature checkboxes
function BuildFeaturesGrid {
    param (
        [System.Windows.FrameworkElement]$parent
    )
    $parent.Children.Clear()

    $sortedFeatures = $allowedFeatures | Sort-Object

    # Now 10 features per column
    $rows = 10
    $columns = [math]::Ceiling($sortedFeatures.Count / $rows)

    $featuresGrid = New-Object System.Windows.Controls.Grid
    $featuresGrid.Margin = "0,5,0,5"
    $featuresGrid.ShowGridLines = $false

    # Define rows
    for ($r = 0; $r -lt $rows; $r++) {
        $rowDef = New-Object System.Windows.Controls.RowDefinition
        $rowDef.Height = 'Auto'
        $featuresGrid.RowDefinitions.Add($rowDef) | Out-Null
    }
    # Define columns
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
        $chk.Margin = '5,2,15,2'
        $chk.Add_Checked({
            UpdateOptionalFeaturesString
        })
        $chk.Add_Unchecked({
            UpdateOptionalFeaturesString
        })

        $script:featureCheckBoxes[$featureName] = $chk

        [System.Windows.Controls.Grid]::SetRow($chk, $rowIndex)
        [System.Windows.Controls.Grid]::SetColumn($chk, $colIndex)
        $featuresGrid.Children.Add($chk) | Out-Null
    }

    $parent.Children.Add($featuresGrid) | Out-Null
}

# Window Loaded
$window.Add_Loaded({
    $script:cmbWindowsRelease = $window.FindName('cmbWindowsRelease')
    $script:cmbWindowsVersion = $window.FindName('cmbWindowsVersion')
    $script:txtISOPath        = $window.FindName('txtISOPath')

    & $script:RefreshWindowsUI($defaultISOPath)

    # ISO path changed
    $script:txtISOPath.Add_TextChanged({
        & $script:RefreshWindowsUI($script:txtISOPath.Text)
    })

    # Windows release changed
    $script:cmbWindowsRelease.Add_SelectionChanged({
        $selItem = $script:cmbWindowsRelease.SelectedItem
        if ($selItem -and $selItem.Value) {
            UpdateWindowsVersionCombo -selectedRelease $selItem.Value -isoPath $script:txtISOPath.Text
        }
    })

    # Browse ISO
    $script:btnBrowseISO = $window.FindName('btnBrowseISO')
    $script:btnBrowseISO.Add_Click({
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Filter = "ISO files (*.iso)|*.iso"
        $ofd.Title  = "Select Windows ISO File"
        if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:txtISOPath.Text = $ofd.FileName
        }
    })

    # Basic defaults
    $window.FindName('txtFFUDevPath').Text = $FFUDevelopmentPath
    $window.FindName('txtFFUName').Text    = "{WindowsRelease}_{WindowsVersion}_{SKU}_{yyyy}-{MM}-{dd}_{HH}{mm}"

    # VM Switch detection
    $script:vmSwitchMap     = @{}
    $script:allSwitches     = Get-VMSwitch -ErrorAction SilentlyContinue
    $script:cmbVMSwitchName = $window.FindName('cmbVMSwitchName')

    foreach ($sw in $script:allSwitches) {
        $script:cmbVMSwitchName.Items.Add($sw.Name) | Out-Null
        $na = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*($($sw.Name))*" }
        if ($na) {
            $netIPs = Get-NetIPAddress -InterfaceIndex $na.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
            $validIPs = $netIPs | Where-Object { $_.IPAddress -notlike '169.254.*' -and $_.IPAddress }
            if ($validIPs) {
                $script:vmSwitchMap[$sw.Name] = ($validIPs | Select-Object -First 1).IPAddress
            }
        }
    }
    $script:cmbVMSwitchName.Items.Add('Other') | Out-Null

    if ($script:cmbVMSwitchName.Items.Count -gt 0) {
        if ($script:allSwitches.Count -gt 0) {
            $script:cmbVMSwitchName.SelectedIndex = 0
            $first = $script:cmbVMSwitchName.SelectedItem
            if ($script:vmSwitchMap.ContainsKey($first)) {
                $window.FindName('txtVMHostIPAddress').Text = $script:vmSwitchMap[$first]
            }
            else {
                $window.FindName('txtVMHostIPAddress').Text = ''
            }
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
            if ($script:vmSwitchMap.ContainsKey($sel)) {
                $window.FindName('txtVMHostIPAddress').Text = $script:vmSwitchMap[$sel]
            }
            else {
                $window.FindName('txtVMHostIPAddress').Text = ''
            }
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
    foreach ($lang in $allowedLangs) {
        [void]$script:cmbWindowsLang.Items.Add($lang)
    }
    $script:cmbWindowsLang.SelectedItem = $defaultWindowsLang

    $script:cmbWindowsSKU = $window.FindName('cmbWindowsSKU')
    $script:cmbWindowsSKU.Items.Clear()
    foreach ($sku in $skuList) {
        [void]$script:cmbWindowsSKU.Items.Add($sku)
    }
    $script:cmbWindowsSKU.SelectedItem = $defaultWindowsSKU

    $script:cmbMediaType = $window.FindName('cmbMediaType')
    foreach ($mt in 'consumer','business') {
        [void]$script:cmbMediaType.Items.Add($mt)
    }
    $script:cmbMediaType.SelectedItem = $defaultMediaType

    $script:txtOptionalFeatures = $window.FindName('txtOptionalFeatures')
    $script:txtOptionalFeatures.Text = $defaultOptionalFeatures
    $window.FindName('txtProductKey').Text = $defaultProductKey

    # Drivers tab
    $script:chkDownloadDrivers   = $window.FindName('chkDownloadDrivers')
    $script:cmbMake              = $window.FindName('cmbMake')
    $script:cmbModel             = $window.FindName('cmbModel')
    $script:spMakeModelSection   = $window.FindName('spMakeModelSection')

    $makeList = @('Microsoft','Dell','HP','Lenovo')
    foreach ($m in $makeList) { [void]$script:cmbMake.Items.Add($m) }
    if ($script:cmbMake.Items.Count -gt 0) { $script:cmbMake.SelectedIndex = 0 }

    $script:chkDownloadDrivers.Add_Checked({
        $script:cmbMake.Visibility      = 'Visible'
        $script:cmbModel.Visibility     = 'Visible'
        $script:spMakeModelSection.Visibility = 'Visible'
    })
    $script:chkDownloadDrivers.Add_Unchecked({
        $script:cmbMake.Visibility      = 'Collapsed'
        $script:cmbModel.Visibility     = 'Collapsed'
        $script:spMakeModelSection.Visibility = 'Collapsed'
    })

    # Office interplay
    $script:chkInstallOffice = $window.FindName('chkInstallOffice')
    $script:chkInstallApps   = $window.FindName('chkInstallApps')
    $script:installAppsCheckedByOffice = $false

    $script:OfficePathStackPanel           = $window.FindName('OfficePathStackPanel')
    $script:OfficePathGrid                 = $window.FindName('OfficePathGrid')
    $script:CopyOfficeConfigXMLStackPanel  = $window.FindName('CopyOfficeConfigXMLStackPanel')
    $script:OfficeConfigurationXMLFileStackPanel = $window.FindName('OfficeConfigurationXMLFileStackPanel')
    $script:OfficeConfigurationXMLFileGrid       = $window.FindName('OfficeConfigurationXMLFileGrid')
    $script:chkCopyOfficeConfigXML         = $window.FindName('chkCopyOfficeConfigXML')

    if ($script:chkInstallOffice.IsChecked) {
        $script:OfficePathStackPanel.Visibility = 'Visible'
        $script:OfficePathGrid.Visibility       = 'Visible'
        $script:CopyOfficeConfigXMLStackPanel.Visibility = 'Visible'
    }
    else {
        $script:OfficePathStackPanel.Visibility = 'Collapsed'
        $script:OfficePathGrid.Visibility       = 'Collapsed'
        $script:CopyOfficeConfigXMLStackPanel.Visibility = 'Collapsed'
        $script:OfficeConfigurationXMLFileStackPanel.Visibility = 'Collapsed'
        $script:OfficeConfigurationXMLFileGrid.Visibility       = 'Collapsed'
    }

    $script:chkInstallOffice.Add_Checked({
        if (-not $script:chkInstallApps.IsChecked) {
            $script:chkInstallApps.IsChecked = $true
            $script:installAppsCheckedByOffice = $true
        }
        $script:chkInstallApps.IsEnabled = $false
        $script:OfficePathStackPanel.Visibility = 'Visible'
        $script:OfficePathGrid.Visibility       = 'Visible'
        $script:CopyOfficeConfigXMLStackPanel.Visibility = 'Visible'
    })
    $script:chkInstallOffice.Add_Unchecked({
        if ($script:installAppsCheckedByOffice) {
            $script:chkInstallApps.IsChecked = $false
            $script:installAppsCheckedByOffice = $false
        }
        $script:chkInstallApps.IsEnabled = $true
        $script:OfficePathStackPanel.Visibility = 'Collapsed'
        $script:OfficePathGrid.Visibility       = 'Collapsed'
        $script:CopyOfficeConfigXMLStackPanel.Visibility = 'Collapsed'
        $script:OfficeConfigurationXMLFileStackPanel.Visibility = 'Collapsed'
        $script:OfficeConfigurationXMLFileGrid.Visibility       = 'Collapsed'
    })

    $script:chkCopyOfficeConfigXML.Add_Checked({
        $script:OfficeConfigurationXMLFileStackPanel.Visibility = 'Visible'
        $script:OfficeConfigurationXMLFileGrid.Visibility       = 'Visible'
    })
    $script:chkCopyOfficeConfigXML.Add_Unchecked({
        $script:OfficeConfigurationXMLFileStackPanel.Visibility = 'Collapsed'
        $script:OfficeConfigurationXMLFileGrid.Visibility       = 'Collapsed'
    })

    # Build the dynamic multi-column checkboxes inside the Expander content
    $script:featuresPanel = $window.FindName('stackFeaturesContainer')
    if ($script:featuresPanel) {
        BuildFeaturesGrid -parent $script:featuresPanel
    }
})

# Button: Build FFU
$btnRun = $window.FindName('btnRun')
$btnRun.Add_Click({
    try {
        $progressBar = $window.FindName('progressBar')
        $txtStatus   = $window.FindName('txtStatus')
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
        $sfd.Filter          = "JSON files (*.json)|*.json|All files (*.*)|*.*"
        $sfd.Title           = "Save Configuration File"
        $sfd.InitialDirectory= $defaultConfigPath
        $sfd.FileName        = "FFUConfig.json"

        if ($sfd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $savePath = $sfd.FileName
            $config | ConvertTo-Json -Depth 10 | Set-Content $savePath -Encoding UTF8

            [System.Windows.MessageBox]::Show(
                "Configuration file saved to:`n$savePath",
                "Success",
                "OK",
                "Information"
            )
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Error saving config file:`n$_","Error","OK","Error")
    }
})

[void]$window.ShowDialog()
