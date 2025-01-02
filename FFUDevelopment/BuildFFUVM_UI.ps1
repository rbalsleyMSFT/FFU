[CmdletBinding()]
[System.STAThread()]
param()

# ------------------------------------------------------------------------------
# SECTION 1: Variables & Constants
# ------------------------------------------------------------------------------
$FFUDevelopmentPath = $PSScriptRoot
$infoImagePath      = Join-Path -Path $PSScriptRoot -ChildPath "info.png"
$AppsPath           = Join-Path -Path $FFUDevelopmentPath -ChildPath "Apps"
$OfficePath         = Join-Path -Path $AppsPath -ChildPath "Office"

# Static SKU list
$skuList = @(
    'Home', 'Home N', 'Home Single Language', 'Education', 'Education N', 'Pro',
    'Pro N', 'Pro Education', 'Pro Education N', 'Pro for Workstations',
    'Pro N for Workstations', 'Enterprise', 'Enterprise N', 'Standard',
    'Standard (Desktop Experience)', 'Datacenter', 'Datacenter (Desktop Experience)'
)

# List of image controls to set
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
    "imgFFUDevPathInfoExtra",
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

# ------------------------------------------------------------------------------
# SECTION 2: Functions
# ------------------------------------------------------------------------------

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# FUNCTION: Set-ImageSource
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
function Set-ImageSource {
    param(
        [System.Windows.Window]$window,
        [string]$imageName,
        [string]$sourcePath
    )
    $image = $window.FindName($imageName)
    if ($image) {
        $uri    = New-Object System.Uri($sourcePath, [System.UriKind]::Absolute)
        $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage($uri)
        $image.Source = $bitmap
    }
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# FUNCTION: Get-UIConfig
#    Gathers UI inputs, validates them, and returns a single $config hashtable.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
function Get-UIConfig {

    # Grab references to UI controls
    $ffuDevPath       = $window.FindName('txtFFUDevPath').Text
    $customFFUName    = $window.FindName('txtFFUName').Text
    $isoPath          = $window.FindName('txtISOPath').Text
    $windowsSKU       = $cmbWindowsSKU.SelectedItem
    $vmSwitchSelected = $window.FindName('cmbVMSwitchName').SelectedItem
    $vmSwitchName     = if ($vmSwitchSelected -eq 'Other') {
                            $window.FindName('txtCustomVMSwitchName').Text
                        } else {
                            $vmSwitchSelected
                        }
    $vmHostIPAddress  = $window.FindName('txtVMHostIPAddress').Text
    $installOffice    = $window.FindName('chkInstallOffice').IsChecked
    $installApps      = $window.FindName('chkInstallApps').IsChecked
    $installDrivers   = $window.FindName('chkInstallDrivers').IsChecked
    $copyDrivers      = $window.FindName('chkCopyDrivers').IsChecked
    $downloadDrivers  = $window.FindName('chkDownloadDrivers').IsChecked
    $make             = $window.FindName('cmbMake').SelectedItem
    $model            = $window.FindName('cmbModel').Text
    $driversFolder    = $window.FindName('txtDriversFolder').Text
    $peDriversFolder  = $window.FindName('txtPEDriversFolder').Text
    $officePath       = $window.FindName('txtOfficePath').Text
    $copyOfficeConfig = $window.FindName('chkCopyOfficeConfigXML').IsChecked
    $officeConfigXMLFile = $window.FindName('txtOfficeConfigXMLFilePath').Text
    $copyPEDrivers    = $window.FindName('chkCopyPEDrivers').IsChecked

    # Validate fields
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
    if (-not $ffuDevPath) {
        throw "FFU Development Path is required."
    }
    if (-not $officePath) {
        throw "Office Path is required."
    }
    if ($installOffice -and $copyOfficeConfig) {
        if (-not (Test-Path -Path $officeConfigXMLFile)) {
            throw "Selected Office Configuration XML file does not exist."
        }
    }

    # Build the $config object (alphabetized)
    $config = [ordered]@{
        AppsPath              = $AppsPath
        CopyDrivers           = $copyDrivers
        CustomFFUNameTemplate = $customFFUName
        DownloadDrivers       = $downloadDrivers
        DriversFolder         = $driversFolder
        FFUDevelopmentPath    = $ffuDevPath
        InstallApps           = $installApps
        InstallDrivers        = $installDrivers
        InstallOffice         = $installOffice
        ISOPath               = $isoPath
        Make                  = if ($downloadDrivers) { $make.ToString() } else { $null }
        Model                 = if ($downloadDrivers) { $model } else { $null }
        OfficeConfigXMLFile   = if ($installOffice -and $copyOfficeConfig) { $officeConfigXMLFile } else { $null }
        OfficePath            = $officePath
        PEDriversFolder       = $peDriversFolder
        VMHostIPAddress       = $vmHostIPAddress
        VMSwitchName          = $vmSwitchName
        WindowsSKU            = $windowsSKU
    }

    return $config
}

# ------------------------------------------------------------------------------
# SECTION 3: Main Script
# ------------------------------------------------------------------------------

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# 3.1) Load XAML and Window
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName PresentationCore,PresentationFramework
Add-Type -AssemblyName System.Windows.Forms

# Build path to XAML
$xamlPath = Join-Path -Path $PSScriptRoot -ChildPath "BuildFFUVM_UI.xaml"
if (-not (Test-Path $xamlPath)) {
    Write-Error "XAML file not found at path: $xamlPath"
    exit
}
$xamlString = Get-Content -Path $xamlPath -Raw
$reader     = New-Object System.IO.StringReader($xamlString)
$xmlReader  = [System.Xml.XmlReader]::Create($reader)
$window     = [Windows.Markup.XamlReader]::Load($xmlReader)

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# 3.2) BASIC TAB: FFU Name, FFU Dev Path, ISO Path, Windows SKU, VM Switch
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# 3.2.1 Default text for FFU Name
$window.FindName('txtFFUName').Text = "{WindowsRelease}_{WindowsVersion}_{SKU}_{yyyy}-{MM}-{dd}_{HH}{mm}"

# 3.2.2 Populate Windows SKU
$cmbWindowsSKU = $window.FindName('cmbWindowsSKU')
$cmbWindowsSKU.Items.Clear()
foreach ($sku in $skuList) {
    $cmbWindowsSKU.Items.Add($sku) | Out-Null
}
if ($cmbWindowsSKU.Items.Count -gt 0) {
    $cmbWindowsSKU.SelectedIndex = 0
}

# 3.2.3 Set images (for all tabs)
foreach ($imgName in $imageNames) {
    Set-ImageSource -window $window -imageName $imgName -sourcePath $infoImagePath
}

# 3.2.4 Browse for FFU Dev Path
$btnBrowseFFUDevPath = $window.FindName('btnBrowseFFUDevPath')
$btnBrowseFFUDevPath.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.Description   = "Select FFU Development Folder"
    $fbd.SelectedPath  = $window.FindName('txtFFUDevPath').Text
    if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $window.FindName('txtFFUDevPath').Text = $fbd.SelectedPath
    }
})
# Default text for txtFFUDevPath
$window.FindName('txtFFUDevPath').Text = $FFUDevelopmentPath

# 3.2.5 Browse for ISO
$btnBrowseISO = $window.FindName('btnBrowseISO')
$btnBrowseISO.Add_Click({
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = "ISO files (*.iso)|*.iso"
    $ofd.Title  = "Select Windows ISO File"
    if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $window.FindName('txtISOPath').Text = $ofd.FileName
    }
})

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# 3.3) APPLICATIONS TAB: Install Apps
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# (Primarily handled in Window Loaded logic if needed.)

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# 3.4) M365 APPS/OFFICE TAB: Install Office, Office Path, Copy Office Config
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# 3.4.1 Browse for Office Path
$btnBrowseOfficePath = $window.FindName('btnBrowseOfficePath')
$btnBrowseOfficePath.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.Description = "Select Office Installation Folder"
    if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $window.FindName('txtOfficePath').Text = $fbd.SelectedPath
    }
})
# Default text for txtOfficePath
$window.FindName('txtOfficePath').Text = $OfficePath

# 3.4.2 Browse for Office Config XML File
$btnBrowseOfficeConfigXMLFile = $window.FindName('btnBrowseOfficeConfigXMLFile')
$btnBrowseOfficeConfigXMLFile.Add_Click({
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = "XML files (*.xml)|*.xml"
    $ofd.Title  = "Select Office Configuration XML File"
    if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $window.FindName('txtOfficeConfigXMLFilePath').Text = $ofd.FileName
    }
})

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# 3.5) DRIVERS TAB: Install Drivers, Copy Drivers, Download Drivers, etc.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# 3.5.1 Browse for Drivers Folder
$btnBrowseDriversFolder = $window.FindName('btnBrowseDriversFolder')
$btnBrowseDriversFolder.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.Description = "Select Drivers Folder"
    if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $window.FindName('txtDriversFolder').Text = $fbd.SelectedPath
    }
})

# 3.5.2 Browse for PE Drivers Folder
$btnBrowsePEDrivers = $window.FindName('btnBrowsePEDrivers')
$btnBrowsePEDrivers.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.Description = "Select PE Drivers Folder"
    if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $window.FindName('txtPEDriversFolder').Text = $fbd.SelectedPath
    }
})

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# 3.6) BUILD FFU & BUILD CONFIG FILE BUTTON EVENTS
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# 3.6.1 "Build FFU" button event
$runScriptHandler = {
    try {
        $progressBar = $window.FindName('progressBar')
        $txtStatus   = $window.FindName('txtStatus')
        $progressBar.Visibility = 'Visible'
        $txtStatus.Text = "Starting FFU build..."

        # Gather + validate config once
        $config = Get-UIConfig

        # Save config as JSON
        $configFilePath = Join-Path $config.FFUDevelopmentPath "FFUConfig.json"
        $config | ConvertTo-Json -Depth 10 | Set-Content -Path $configFilePath -Encoding UTF8

        # Update status and run BuildFFUVM.ps1
        $txtStatus.Text = "Executing BuildFFUVM script with config file..."
        & "$PSScriptRoot\BuildFFUVM.ps1" -ConfigFile $configFilePath -Verbose

        # Copy Office XML if needed
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
}
$btnRun = $window.FindName('btnRun')
$btnRun.Add_Click($runScriptHandler)

# 3.6.2 "Build Config File" button event
$btnBuildConfig = $window.FindName('btnBuildConfig')
$btnBuildConfig.Add_Click({
    try {
        # Gather + validate config once
        $config = Get-UIConfig

        # Where to save
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
            $config | ConvertTo-Json -Depth 10 | Set-Content -Path $savePath -Encoding UTF8

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

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# 3.7) WINDOW LOADED LOGIC
#    Reorganized below based on tab order:
#    1) Basic, 2) Applications, 3) M365 Apps/Office, 4) Drivers
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

$script:installAppsCheckedByOffice = $false

$window.Add_Loaded({
    # ---------------------------------------------------------
    # (1) BASIC TAB
    #     VM Switch combos & IP
    # ---------------------------------------------------------
    $script:vmSwitchMap     = @{}
    $script:cmbVMSwitchName = $window.FindName('cmbVMSwitchName')
    $allSwitches = Get-VMSwitch -ErrorAction SilentlyContinue

    foreach ($sw in $allSwitches) {
        $script:cmbVMSwitchName.Items.Add($sw.Name) | Out-Null
        $netAdapter = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*($($sw.Name))*" }
        if ($netAdapter) {
            $netIPs = Get-NetIPAddress -InterfaceIndex $netAdapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
            $validIPs = $netIPs | Where-Object { $_.IPAddress -notlike '169.254.*' -and $_.IPAddress }
            if ($validIPs) {
                $script:vmSwitchMap[$sw.Name] = ($validIPs | Select-Object -First 1).IPAddress
            }
        }
    }
    $script:cmbVMSwitchName.Items.Add('Other') | Out-Null

    if ($script:cmbVMSwitchName.Items.Count -gt 0) {
        if ($allSwitches.Count -gt 0) {
            $script:cmbVMSwitchName.SelectedIndex = 0
            $pre = $script:cmbVMSwitchName.SelectedItem.ToString()
            if ($script:vmSwitchMap.ContainsKey($pre)) {
                $window.FindName('txtVMHostIPAddress').Text = $script:vmSwitchMap[$pre]
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
        param($sender, $eventArgs)
        if ($sender.SelectedItem -eq 'Other') {
            $window.FindName('txtCustomVMSwitchName').Visibility = 'Visible'
            $window.FindName('txtVMHostIPAddress').Text = ''
        }
        else {
            $window.FindName('txtCustomVMSwitchName').Visibility = 'Collapsed'
            if ($script:vmSwitchMap.ContainsKey($sender.SelectedItem)) {
                $ip = $script:vmSwitchMap[$sender.SelectedItem]
                $window.FindName('txtVMHostIPAddress').Text = $ip
            }
            else {
                $window.FindName('txtVMHostIPAddress').Text = ''
            }
        }
    })

    # ---------------------------------------------------------
    # (2) APPLICATIONS TAB
    #     "Install Apps" interplay (with "Install Office")
    # ---------------------------------------------------------
    # We handle additional interplay in the next section, but if you have more
    # "Applications" logic, put it here.
    $script:chkInstallApps = $window.FindName('chkInstallApps')
    # (No extra event code needed here—it's in the next section for synergy with Office.)

    # ---------------------------------------------------------
    # (3) M365 APPS/OFFICE TAB
    #     "Install Office" + "Install Apps" interplay,
    #     plus the Office config UI references/visibility
    # ---------------------------------------------------------
    $script:chkInstallOffice = $window.FindName('chkInstallOffice')

    # When Office is checked, ensure Apps is also checked
    $script:chkInstallOffice.Add_Checked({
        if (-not $script:chkInstallApps.IsChecked) {
            $script:chkInstallApps.IsChecked = $true
            $script:installAppsCheckedByOffice = $true
        }
        $script:chkInstallApps.IsEnabled = $false
    })
    $script:chkInstallOffice.Add_Unchecked({
        if ($script:installAppsCheckedByOffice) {
            $script:chkInstallApps.IsChecked = $false
            $script:installAppsCheckedByOffice = $false
        }
        $script:chkInstallApps.IsEnabled = $true
    })

    $script:chkInstallApps.Add_Checked({
        if (-not $script:installAppsCheckedByOffice) {
            # user checked it manually
        }
    })
    $script:chkInstallApps.Add_Unchecked({
        if (-not $script:installAppsCheckedByOffice) {
            # user unchecked it manually
        }
    })

    # Office Path & Copy Office Config references
    $script:stackOfficePath   = $window.FindName('OfficePathStackPanel')
    $script:gridOfficePath    = $window.FindName('OfficePathGrid')
    $script:CopyOfficeConfigXMLStackPanel = $window.FindName('CopyOfficeConfigXMLStackPanel')
    $script:OfficeConfigurationXMLFileStackPanel = $window.FindName('OfficeConfigurationXMLFileStackPanel')
    $script:OfficeConfigurationXMLFileGrid       = $window.FindName('OfficeConfigurationXMLFileGrid')
    $script:chkCopyOfficeConfigXML = $window.FindName('chkCopyOfficeConfigXML')

    # Initial visibility for Office controls
    if ($script:chkInstallOffice.IsChecked) {
        $script:stackOfficePath.Visibility = 'Visible'
        $script:gridOfficePath.Visibility  = 'Visible'
        $script:CopyOfficeConfigXMLStackPanel.Visibility = 'Visible'
        if ($script:chkCopyOfficeConfigXML.IsChecked) {
            $script:OfficeConfigurationXMLFileStackPanel.Visibility = 'Visible'
            $script:OfficeConfigurationXMLFileGrid.Visibility       = 'Visible'
        }
        else {
            $script:OfficeConfigurationXMLFileStackPanel.Visibility = 'Collapsed'
            $script:OfficeConfigurationXMLFileGrid.Visibility       = 'Collapsed'
        }
    }
    else {
        $script:stackOfficePath.Visibility = 'Collapsed'
        $script:gridOfficePath.Visibility  = 'Collapsed'
        $script:CopyOfficeConfigXMLStackPanel.Visibility = 'Collapsed'
        $script:OfficeConfigurationXMLFileStackPanel.Visibility = 'Collapsed'
        $script:OfficeConfigurationXMLFileGrid.Visibility       = 'Collapsed'
    }

    $script:chkInstallOffice.Add_Checked({
        $script:stackOfficePath.Visibility = 'Visible'
        $script:gridOfficePath.Visibility  = 'Visible'
        $script:CopyOfficeConfigXMLStackPanel.Visibility = 'Visible'
    })
    $script:chkInstallOffice.Add_Unchecked({
        $script:stackOfficePath.Visibility = 'Collapsed'
        $script:gridOfficePath.Visibility  = 'Collapsed'
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

    # ---------------------------------------------------------
    # (4) DRIVERS TAB
    #     Download Drivers logic, Install/Copy Drivers, etc.
    # ---------------------------------------------------------
    $script:chkDownloadDrivers   = $window.FindName('chkDownloadDrivers')
    $script:cmbMake              = $window.FindName('cmbMake')
    $script:cmbModel             = $window.FindName('cmbModel')
    $script:txtMakeLabel         = $window.FindName('txtMakeLabel')
    $script:txtModelLabel        = $window.FindName('txtModelLabel')
    $script:spMakeModelSection   = $window.FindName('spMakeModelSection')

    # "Download Drivers" logic
    if ($script:chkDownloadDrivers.IsChecked) {
        $script:cmbMake.Visibility      = 'Visible'
        $script:cmbModel.Visibility     = 'Visible'
        $script:txtMakeLabel.Visibility = 'Visible'
        $script:txtModelLabel.Visibility= 'Visible'
        $script:spMakeModelSection.Visibility = 'Visible'
    }
    else {
        $script:cmbMake.Visibility      = 'Collapsed'
        $script:cmbModel.Visibility     = 'Collapsed'
        $script:txtMakeLabel.Visibility = 'Collapsed'
        $script:txtModelLabel.Visibility= 'Collapsed'
        $script:spMakeModelSection.Visibility = 'Collapsed'
    }
    $script:chkDownloadDrivers.Add_Checked({
        $script:cmbMake.Visibility      = 'Visible'
        $script:cmbModel.Visibility     = 'Visible'
        $script:txtMakeLabel.Visibility = 'Visible'
        $script:txtModelLabel.Visibility= 'Visible'
        $script:spMakeModelSection.Visibility = 'Visible'
    })
    $script:chkDownloadDrivers.Add_Unchecked({
        $script:cmbMake.Visibility      = 'Collapsed'
        $script:cmbModel.Visibility     = 'Collapsed'
        $script:txtMakeLabel.Visibility = 'Collapsed'
        $script:txtModelLabel.Visibility= 'Collapsed'
        $script:spMakeModelSection.Visibility = 'Collapsed'
    })

    # Populate Make ComboBox
    $makeList = @('Microsoft','Dell','HP','Lenovo')
    foreach ($m in $makeList) {
        $script:cmbMake.Items.Add($m) | Out-Null
    }
    if ($script:cmbMake.Items.Count -gt 0) {
        $script:cmbMake.SelectedIndex = 0
    }

    # "Install Drivers" & "Copy Drivers" interplay
    $script:chkInstallDrivers = $window.FindName('chkInstallDrivers')
    $script:chkCopyDrivers    = $window.FindName('chkCopyDrivers')
    $script:chkCopyPEDrivers  = $window.FindName('chkCopyPEDrivers')

    $script:chkInstallDrivers.Add_Checked({
        $script:chkCopyDrivers.IsEnabled = $false
    })
    $script:chkInstallDrivers.Add_Unchecked({
        $script:chkCopyDrivers.IsEnabled = $true
    })
    $script:chkCopyDrivers.Add_Checked({
        $script:chkInstallDrivers.IsEnabled = $false
    })
    $script:chkCopyDrivers.Add_Unchecked({
        $script:chkInstallDrivers.IsEnabled = $true
    })

    # Default text for Drivers folders
    $window.FindName('txtDriversFolder').Text    = Join-Path $FFUDevelopmentPath "Drivers"
    $window.FindName('txtPEDriversFolder').Text = Join-Path $FFUDevelopmentPath "PEDrivers"
})

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# 3.8) SHOW THE WPF WINDOW
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[void]$window.ShowDialog()
