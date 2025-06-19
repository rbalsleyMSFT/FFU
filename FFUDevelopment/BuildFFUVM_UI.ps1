[CmdletBinding()]
[System.STAThread()]
param()

# Check PowerShell Version
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Error "PowerShell 7 or later is required to run this script."
    exit 1
}

# --------------------------------------------------------------------------
# SECTION: Variables & Constants
# --------------------------------------------------------------------------
# $FFUDevelopmentPath = $PSScriptRoot
$FFUDevelopmentPath = 'C:\FFUDevelopment' # hard coded for testing

# --- NEW: Central State Object ---
$script:uiState = [PSCustomObject]@{
    FFUDevelopmentPath = $FFUDevelopmentPath;
    Window             = $null;
    Controls           = @{
        featureCheckBoxes               = @{}; 
        UpdateInstallAppsBasedOnUpdates = $null 
    };
    Data               = @{
        allDriverModels             = [System.Collections.Generic.List[PSCustomObject]]::new();
        appsScriptVariablesDataList = [System.Collections.Generic.List[PSCustomObject]]::new();
        versionData                 = $null; 
        vmSwitchMap                 = @{}   
    };
    Flags              = @{
        installAppsForcedByUpdates        = $false;
        prevInstallAppsStateBeforeUpdates = $null;
        installAppsCheckedByOffice        = $false;
        lastSortProperty                  = $null;
        lastSortAscending                 = $true
    };
    Defaults           = @{};
    LogFilePath        = "$FFUDevelopmentPath\FFUDevelopment_UI.log"
}

# Remove any existing modules to avoid conflicts
if (Get-Module -Name 'FFU.Common.Core' -ErrorAction SilentlyContinue) {
    Remove-Module -Name 'FFU.Common.Core' -Force
}
if (Get-Module -Name 'FFUUI.Core' -ErrorAction SilentlyContinue) {
    Remove-Module -Name 'FFUUI.Core' -Force
}
# Import the common core module first for logging
Import-Module "$PSScriptRoot\FFU.Common" -Force
# Import the Core UI Logic Module
Import-Module "$PSScriptRoot\FFUUI.Core" -Force

# Set the log path for the common logger (for UI operations)
Set-CommonCoreLogPath -Path $script:uiState.LogFilePath

# Setting long path support - this prevents issues where some applications have deep directory structures
# and driver extraction fails due to long paths.
$script:uiState.Flags.originalLongPathsValue = $null # Store original value
try {
    $script:uiState.Flags.originalLongPathsValue = Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -ErrorAction SilentlyContinue
}
catch {
    # Key or value might not exist, which is fine.
    WriteLog "Could not read initial LongPathsEnabled value (may not exist)."
}

# Enable long paths if not already enabled
if ($script:uiState.Flags.originalLongPathsValue -ne 1) {
    try {
        WriteLog 'LongPathsEnabled is not set to 1. Setting it to 1 for the duration of this script.'
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Value 1 -Force
        WriteLog 'LongPathsEnabled set to 1.'
    }
    catch {
        WriteLog "Error setting LongPathsEnabled registry key: $($_.Exception.Message). Long path issues might persist."
    }
}
else {
    WriteLog "LongPathsEnabled is already set to 1."
}

if (Test-Path -Path $script:uiState.LogFilePath) {
    Remove-item -Path $script:uiState.LogFilePath -Force
}

Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName PresentationCore, PresentationFramework
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

# -----------------------------------------------------------------------------
# SECTION: Winget UI
# -----------------------------------------------------------------------------
# Create data context class for version binding
$script:uiState.Data.versionData = [PSCustomObject]@{
    WingetVersion = "Not checked"
    ModuleVersion = "Not checked"
}

# Add observable property support
$script:uiState.Data.versionData | Add-Member -MemberType ScriptMethod -Name NotifyPropertyChanged -Value {
    param($PropertyName)
    if ($this.PropertyChanged) {
        $this.PropertyChanged.Invoke($this, [System.ComponentModel.PropertyChangedEventArgs]::new($PropertyName))
    }
}

$script:uiState.Data.versionData | Add-Member -MemberType NoteProperty -Name PropertyChanged -Value $null
$script:uiState.Data.versionData | Add-Member -TypeName "System.ComponentModel.INotifyPropertyChanged"



$window.Add_Loaded({
        # Pass the state object to all initialization functions
        $script:uiState.Window = $window
        $window.Tag = $script:uiState
        Initialize-UIControls -State $script:uiState

        Initialize-UIDefaults -State $script:uiState

        Initialize-DynamicUIElements -State $script:uiState

        Initialize-VMSwitchData -State $script:uiState

        Register-EventHandlers -State $script:uiState

        # Drivers tab UI logic
        $makeList = @('Microsoft', 'Dell', 'HP', 'Lenovo') 
        foreach ($m in $makeList) {
            [void]$script:uiState.Controls.cmbMake.Items.Add($m)
        }
        if ($script:uiState.Controls.cmbMake.Items.Count -gt 0) {
            $script:uiState.Controls.cmbMake.SelectedIndex = 0
        }
        $script:uiState.Controls.spMakeSection.Visibility = if ($script:uiState.Controls.chkDownloadDrivers.IsChecked) {
            'Visible' 
        } 
        else { 
            'Collapsed' 
        }
        $script:uiState.Controls.btnGetModels.Visibility = if ($script:uiState.Controls.chkDownloadDrivers.IsChecked) { 'Visible' } else { 'Collapsed' }
        $script:uiState.Controls.spModelFilterSection.Visibility = 'Collapsed'
        $script:uiState.Controls.lstDriverModels.Visibility = 'Collapsed'
        $script:uiState.Controls.spDriverActionButtons.Visibility = 'Collapsed'

        # Office interplay (Keep existing logic)
        $script:uiState.Flags.installAppsCheckedByOffice = $false
        if ($script:uiState.Controls.chkInstallOffice.IsChecked) {
            $script:uiState.Controls.OfficePathStackPanel.Visibility = 'Visible'
            $script:uiState.Controls.OfficePathGrid.Visibility = 'Visible'
            $script:uiState.Controls.CopyOfficeConfigXMLStackPanel.Visibility = 'Visible'
            # Show/hide XML file path based on checkbox state
            $script:uiState.Controls.OfficeConfigurationXMLFileStackPanel.Visibility = if ($script:uiState.Controls.chkCopyOfficeConfigXML.IsChecked) { 'Visible' } else { 'Collapsed' }
            $script:uiState.Controls.OfficeConfigurationXMLFileGrid.Visibility = if ($script:uiState.Controls.chkCopyOfficeConfigXML.IsChecked) { 'Visible' } else { 'Collapsed' }
        }
        else {
            $script:uiState.Controls.OfficePathStackPanel.Visibility = 'Collapsed'
            $script:uiState.Controls.OfficePathGrid.Visibility = 'Collapsed'
            $script:uiState.Controls.CopyOfficeConfigXMLStackPanel.Visibility = 'Collapsed'
            $script:uiState.Controls.OfficeConfigurationXMLFileStackPanel.Visibility = 'Collapsed'
            $script:uiState.Controls.OfficeConfigurationXMLFileGrid.Visibility = 'Collapsed'
        }

        # CU interplay (Keep existing logic)
        # Set initial state based on defaults
        $script:uiState.Controls.chkPreviewCU.IsEnabled = -not $script:uiState.Controls.chkLatestCU.IsChecked
        $script:uiState.Controls.chkLatestCU.IsEnabled = -not $script:uiState.Controls.chkPreviewCU.IsChecked


        # APPLICATIONS tab UI logic (Keep existing logic)
        $script:uiState.Controls.chkInstallWingetApps.Visibility = if ($script:uiState.Controls.chkInstallApps.IsChecked) { 'Visible' } else { 'Collapsed' }
        $script:uiState.Controls.applicationPathPanel.Visibility = if ($script:uiState.Controls.chkInstallApps.IsChecked) { 'Visible' } else { 'Collapsed' }
        $script:uiState.Controls.appListJsonPathPanel.Visibility = if ($script:uiState.Controls.chkInstallApps.IsChecked) { 'Visible' } else { 'Collapsed' }
        $script:uiState.Controls.chkBringYourOwnApps.Visibility = if ($script:uiState.Controls.chkInstallApps.IsChecked) { 'Visible' } else { 'Collapsed' }
        $script:uiState.Controls.byoApplicationPanel.Visibility = if ($script:uiState.Controls.chkBringYourOwnApps.IsChecked) { 'Visible' } else { 'Collapsed' }
        $script:uiState.Controls.wingetPanel.Visibility = if ($script:uiState.Controls.chkInstallWingetApps.IsChecked) { 'Visible' } else { 'Collapsed' }
        $script:uiState.Controls.wingetSearchPanel.Visibility = 'Collapsed' # Keep search hidden initially

        # BYO Apps ListView setup (Keep existing logic, ensure CopyStatus column
        $byoGridView = $script:uiState.Controls.lstApplications.View
        if ($byoGridView -is [System.Windows.Controls.GridView]) {
            $copyStatusColumnExists = $false
            foreach ($col in $byoGridView.Columns) { 
                if ($col.Header -eq "Copy Status") {
                    $copyStatusColumnExists = $true; break 
                } 
            }
            if (-not $copyStatusColumnExists) {
                $actionColumnIndex = -1
                for ($i = 0; $i -lt $byoGridView.Columns.Count; $i++) {
                    if ($byoGridView.Columns[$i].Header -eq "Action") {
                        $actionColumnIndex = $i; break 
                    } 
                }
                $copyStatusColumn = New-Object System.Windows.Controls.GridViewColumn
                $copyStatusColumn.Header = "Copy Status"
                $copyStatusColumn.DisplayMemberBinding = New-Object System.Windows.Data.Binding("CopyStatus") 
                $copyStatusColumn.Width = 150
                if ($actionColumnIndex -ge 0) {
                    $byoGridView.Columns.Insert($actionColumnIndex, $copyStatusColumn) 
                }
                else {
                    $byoGridView.Columns.Add($copyStatusColumn) 
                }
            }
        }
        Update-CopyButtonState -State $script:uiState # Initial check

        # Initial state for chkDefineAppsScriptVariables based on chkInstallApps
        if ($script:uiState.Controls.chkInstallApps.IsChecked) {
            $script:uiState.Controls.chkDefineAppsScriptVariables.Visibility = 'Visible'
        }
        else {
            $script:uiState.Controls.chkDefineAppsScriptVariables.Visibility = 'Collapsed'
        }
        # Initial state for appsScriptVariablesPanel based on chkDefineAppsScriptVariables
        if ($script:uiState.Controls.chkDefineAppsScriptVariables.IsChecked) {
            $script:uiState.Controls.appsScriptVariablesPanel.Visibility = 'Visible'
        }
        else {
            $script:uiState.Controls.appsScriptVariablesPanel.Visibility = 'Collapsed'
        }

    })


# Button: Build FFU
$btnRun = $window.FindName('btnRun')
$btnRun.Add_Click({
        try {
            $progressBar = $script:uiState.Controls.pbOverallProgress
            $txtStatus = $script:uiState.Controls.txtStatus
            $progressBar.Visibility = 'Visible'
            $txtStatus.Text = "Starting FFU build..."
            $config = Get-UIConfig -State $script:uiState
            $configFilePath = Join-Path $config.FFUDevelopmentPath "FFUConfig.json"
            $config | ConvertTo-Json -Depth 10 | Set-Content $configFilePath -Encoding UTF8
            $txtStatus.Text = "Executing BuildFFUVM script with config file..."
            & "$PSScriptRoot\BuildFFUVM.ps1" -ConfigFile $configFilePath
            if ($config.InstallOffice -and $config.OfficeConfigXMLFile) {
                Copy-Item -Path $config.OfficeConfigXMLFile -Destination $config.OfficePath -Force
                $txtStatus.Text = "Office Configuration XML file copied successfully."
            }
            $txtStatus.Text = "FFU build completed successfully."
        }
        catch {
            [System.Windows.MessageBox]::Show("An error occurred: $_", "Error", "OK", "Error")
            $script:uiState.Controls.txtStatus.Text = "FFU build failed."
        }
        finally {
            $script:uiState.Controls.pbOverallProgress.Visibility = 'Collapsed'
        }
    })

# Button: Build Config
$btnBuildConfig = $window.FindName('btnBuildConfig')
$btnBuildConfig.Add_Click({
        try {
            $config = Get-UIConfig -State $script:uiState
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
            [System.Windows.MessageBox]::Show("Error saving config file:`n$_", "Error", "OK", "Error")
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
                WriteLog "Loading configuration from: $($ofd.FileName)"
                $configContent = Get-Content -Path $ofd.FileName -Raw | ConvertFrom-Json

                if ($null -eq $configContent) {
                    WriteLog "LoadConfig Error: configContent is null after parsing $($ofd.FileName). File might be empty or malformed."
                    [System.Windows.MessageBox]::Show("Failed to parse the configuration file. It might be empty or not valid JSON.", "Load Error", "OK", "Error")
                    return
                }
                WriteLog "LoadConfig: Successfully parsed config file. Top-level keys: $($configContent.PSObject.Properties.Name -join ', ')"

                # Update Build tab values
                Set-UIValue -ControlName 'txtFFUDevPath' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'FFUDevelopmentPath' -State $script:uiState
                Set-UIValue -ControlName 'txtCustomFFUNameTemplate' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'CustomFFUNameTemplate' -State $script:uiState
                Set-UIValue -ControlName 'txtFFUCaptureLocation' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'FFUCaptureLocation' -State $script:uiState
                Set-UIValue -ControlName 'txtShareName' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'ShareName' -State $script:uiState
                Set-UIValue -ControlName 'txtUsername' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'Username' -State $script:uiState
                Set-UIValue -ControlName 'chkBuildUSBDriveEnable' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'BuildUSBDrive' -State $script:uiState
                Set-UIValue -ControlName 'chkCompactOS' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'CompactOS' -State $script:uiState
                Set-UIValue -ControlName 'chkUpdateADK' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'UpdateADK' -State $script:uiState
                Set-UIValue -ControlName 'chkOptimize' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'Optimize' -State $script:uiState
                Set-UIValue -ControlName 'chkAllowVHDXCaching' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'AllowVHDXCaching' -State $script:uiState
                Set-UIValue -ControlName 'chkAllowExternalHardDiskMedia' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'AllowExternalHardDiskMedia' -State $script:uiState
                Set-UIValue -ControlName 'chkPromptExternalHardDiskMedia' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'PromptExternalHardDiskMedia' -State $script:uiState
                Set-UIValue -ControlName 'chkCreateCaptureMedia' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'CreateCaptureMedia' -State $script:uiState
                Set-UIValue -ControlName 'chkCreateDeploymentMedia' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'CreateDeploymentMedia' -State $script:uiState

                # USB Drive Modification group (Build Tab)
                Set-UIValue -ControlName 'chkCopyAutopilot' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'CopyAutopilot' -State $script:uiState
                Set-UIValue -ControlName 'chkCopyUnattend' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'CopyUnattend' -State $script:uiState
                Set-UIValue -ControlName 'chkCopyPPKG' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'CopyPPKG' -State $script:uiState

                # Post Build Cleanup group (Build Tab)
                Set-UIValue -ControlName 'chkCleanupAppsISO' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'CleanupAppsISO' -State $script:uiState
                Set-UIValue -ControlName 'chkCleanupCaptureISO' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'CleanupCaptureISO' -State $script:uiState
                Set-UIValue -ControlName 'chkCleanupDeployISO' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'CleanupDeployISO' -State $script:uiState
                Set-UIValue -ControlName 'chkCleanupDrivers' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'CleanupDrivers' -State $script:uiState
                Set-UIValue -ControlName 'chkRemoveFFU' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'RemoveFFU' -State $script:uiState
                Set-UIValue -ControlName 'chkRemoveApps' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'RemoveApps' -State $script:uiState
                Set-UIValue -ControlName 'chkRemoveUpdates' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'RemoveUpdates' -State $script:uiState

                # Hyper-V Settings
                Set-UIValue -ControlName 'cmbVMSwitchName' -PropertyName 'SelectedItem' -ConfigObject $configContent -ConfigKey 'VMSwitchName' -State $script:uiState
                Set-UIValue -ControlName 'txtVMHostIPAddress' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'VMHostIPAddress' -State $script:uiState
                Set-UIValue -ControlName 'txtDiskSize' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'Disksize' -TransformValue { param($val) $val / 1GB } -State $script:uiState
                Set-UIValue -ControlName 'txtMemory' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'Memory' -TransformValue { param($val) $val / 1GB } -State $script:uiState
                Set-UIValue -ControlName 'txtProcessors' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'Processors' -State $script:uiState
                Set-UIValue -ControlName 'txtVMLocation' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'VMLocation' -State $script:uiState
                Set-UIValue -ControlName 'txtVMNamePrefix' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'FFUPrefix' -State $script:uiState
                Set-UIValue -ControlName 'cmbLogicalSectorSize' -PropertyName 'SelectedItem' -ConfigObject $configContent -ConfigKey 'LogicalSectorSizeBytes' -TransformValue { param($val) $val.ToString() } -State $script:uiState

                # Windows Settings
                Set-UIValue -ControlName 'txtISOPath' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'ISOPath' -State $script:uiState
                Set-UIValue -ControlName 'cmbWindowsRelease' -PropertyName 'SelectedItem' -ConfigObject $configContent -ConfigKey 'WindowsRelease' -State $script:uiState
                Set-UIValue -ControlName 'cmbWindowsVersion' -PropertyName 'SelectedItem' -ConfigObject $configContent -ConfigKey 'WindowsVersion' -State $script:uiState
                Set-UIValue -ControlName 'cmbWindowsArch' -PropertyName 'SelectedItem' -ConfigObject $configContent -ConfigKey 'WindowsArch' -State $script:uiState
                Set-UIValue -ControlName 'cmbWindowsLang' -PropertyName 'SelectedItem' -ConfigObject $configContent -ConfigKey 'WindowsLang' -State $script:uiState
                Set-UIValue -ControlName 'cmbWindowsSKU' -PropertyName 'SelectedItem' -ConfigObject $configContent -ConfigKey 'WindowsSKU' -State $script:uiState
                Set-UIValue -ControlName 'cmbMediaType' -PropertyName 'SelectedItem' -ConfigObject $configContent -ConfigKey 'MediaType' -State $script:uiState
                Set-UIValue -ControlName 'txtProductKey' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'ProductKey' -State $script:uiState
                Set-UIValue -ControlName 'txtOptionalFeatures' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'OptionalFeatures' -State $script:uiState

                # Update Optional Features checkboxes based on the loaded text
                $loadedFeaturesString = $script:uiState.Controls.txtOptionalFeatures.Text
                if (-not [string]::IsNullOrWhiteSpace($loadedFeaturesString)) {
                    $loadedFeaturesArray = $loadedFeaturesString.Split(';')
                    WriteLog "LoadConfig: Updating Optional Features checkboxes. Loaded features: $($loadedFeaturesArray -join ', ')"
                    foreach ($featureEntry in $script:uiState.Controls.featureCheckBoxes.GetEnumerator()) {
                        $featureName = $featureEntry.Key
                        $featureCheckbox = $featureEntry.Value
                        if ($loadedFeaturesArray -contains $featureName) {
                            $featureCheckbox.IsChecked = $true
                            WriteLog "LoadConfig: Checked checkbox for feature '$featureName'."
                        }
                        else {
                            $featureCheckbox.IsChecked = $false
                        }
                    }
                }
                else {
                    # If no optional features are loaded, uncheck all
                    WriteLog "LoadConfig: No optional features string loaded. Unchecking all feature checkboxes."
                    foreach ($featureEntry in $script:uiState.Controls.featureCheckBoxes.GetEnumerator()) {
                        $featureEntry.Value.IsChecked = $false
                    }
                }

                # M365 Apps/Office tab
                Set-UIValue -ControlName 'chkInstallOffice' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'InstallOffice' -State $script:uiState
                Set-UIValue -ControlName 'txtOfficePath' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'OfficePath' -State $script:uiState
                Set-UIValue -ControlName 'chkCopyOfficeConfigXML' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'CopyOfficeConfigXML' -State $script:uiState
                Set-UIValue -ControlName 'txtOfficeConfigXMLFilePath' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'OfficeConfigXMLFile' -State $script:uiState

                # Drivers tab
                Set-UIValue -ControlName 'chkInstallDrivers' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'InstallDrivers' -State $script:uiState
                Set-UIValue -ControlName 'chkDownloadDrivers' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'DownloadDrivers' -State $script:uiState
                Set-UIValue -ControlName 'chkCopyDrivers' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'CopyDrivers' -State $script:uiState
                Set-UIValue -ControlName 'cmbMake' -PropertyName 'SelectedItem' -ConfigObject $configContent -ConfigKey 'Make' -State $script:uiState
                Set-UIValue -ControlName 'txtDriversFolder' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'DriversFolder' -State $script:uiState
                Set-UIValue -ControlName 'txtPEDriversFolder' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'PEDriversFolder' -State $script:uiState
                Set-UIValue -ControlName 'txtDriversJsonPath' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'DriversJsonPath' -State $script:uiState
                Set-UIValue -ControlName 'chkCopyPEDrivers' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'CopyPEDrivers' -State $script:uiState
                Set-UIValue -ControlName 'chkCompressDriversToWIM' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'CompressDownloadedDriversToWim' -State $script:uiState


                # Updates tab
                Set-UIValue -ControlName 'chkUpdateLatestCU' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'UpdateLatestCU' -State $script:uiState
                Set-UIValue -ControlName 'chkUpdateLatestNet' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'UpdateLatestNet' -State $script:uiState
                Set-UIValue -ControlName 'chkUpdateLatestDefender' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'UpdateLatestDefender' -State $script:uiState
                Set-UIValue -ControlName 'chkUpdateEdge' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'UpdateEdge' -State $script:uiState
                Set-UIValue -ControlName 'chkUpdateOneDrive' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'UpdateOneDrive' -State $script:uiState
                Set-UIValue -ControlName 'chkUpdateLatestMSRT' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'UpdateLatestMSRT' -State $script:uiState
                Set-UIValue -ControlName 'chkUpdateLatestMicrocode' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'UpdateLatestMicrocode' -State $script:uiState
                Set-UIValue -ControlName 'chkUpdatePreviewCU' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'UpdatePreviewCU' -State $script:uiState

                # Applications tab
                Set-UIValue -ControlName 'chkInstallApps' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'InstallApps' -State $script:uiState
                Set-UIValue -ControlName 'chkInstallWingetApps' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'InstallWingetApps' -State $script:uiState
                Set-UIValue -ControlName 'chkBringYourOwnApps' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'BringYourOwnApps' -State $script:uiState
                Set-UIValue -ControlName 'txtApplicationPath' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'AppsPath' -State $script:uiState
                Set-UIValue -ControlName 'txtAppListJsonPath' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'AppListPath' -State $script:uiState

                # Handle AppsScriptVariables
                $appsScriptVarsKeyExists = $false
                if ($configContent -is [System.Management.Automation.PSCustomObject] -and $null -ne $configContent.PSObject.Properties) {
                    try {
                        if (($configContent.PSObject.Properties.Match('AppsScriptVariables')).Count -gt 0) {
                            $appsScriptVarsKeyExists = $true
                        }
                    }
                    catch { WriteLog "ERROR: Exception while trying to Match key 'AppsScriptVariables'. Error: $($_.Exception.Message)" }
                }

                $lstAppsScriptVars = $script:uiState.Controls.lstAppsScriptVariables
                $chkDefineAppsScriptVars = $script:uiState.Controls.chkDefineAppsScriptVariables
                $appsScriptVarsPanel = $script:uiState.Controls.appsScriptVariablesPanel
                $script:uiState.Data.appsScriptVariablesDataList.Clear()

                if ($appsScriptVarsKeyExists -and $null -ne $configContent.AppsScriptVariables -and $configContent.AppsScriptVariables -is [System.Management.Automation.PSCustomObject]) {
                    WriteLog "LoadConfig: Processing AppsScriptVariables from config."
                    $loadedVars = $configContent.AppsScriptVariables
                    $hasVars = $false
                    foreach ($prop in $loadedVars.PSObject.Properties) {
                        $script:uiState.Data.appsScriptVariablesDataList.Add([PSCustomObject]@{ IsSelected = $false; Key = $prop.Name; Value = $prop.Value })
                        $hasVars = $true
                    }
                    if ($hasVars) {
                        $chkDefineAppsScriptVars.IsChecked = $true
                        $appsScriptVarsPanel.Visibility = 'Visible'
                        WriteLog "LoadConfig: Loaded AppsScriptVariables and checked 'Define Apps Script Variables'."
                    }
                    else {
                        $chkDefineAppsScriptVars.IsChecked = $false
                        $appsScriptVarsPanel.Visibility = 'Collapsed'
                        WriteLog "LoadConfig: AppsScriptVariables key was present but empty. Unchecked 'Define Apps Script Variables'."
                    }
                }
                elseif ($appsScriptVarsKeyExists -and $null -ne $configContent.AppsScriptVariables -and $configContent.AppsScriptVariables -is [hashtable]) {
                    # Handle if it's already a hashtable (e.g., from older config or direct creation)
                    WriteLog "LoadConfig: Processing AppsScriptVariables (Hashtable) from config."
                    $loadedVars = $configContent.AppsScriptVariables
                    $hasVars = $false
                    foreach ($keyName in $loadedVars.Keys) {
                        $script:uiState.Data.appsScriptVariablesDataList.Add([PSCustomObject]@{ IsSelected = $false; Key = $keyName; Value = $loadedVars[$keyName] })
                        $hasVars = $true
                    }
                    if ($hasVars) {
                        $chkDefineAppsScriptVars.IsChecked = $true
                        $appsScriptVarsPanel.Visibility = 'Visible'
                        WriteLog "LoadConfig: Loaded AppsScriptVariables (Hashtable) and checked 'Define Apps Script Variables'."
                    }
                    else {
                        $chkDefineAppsScriptVars.IsChecked = $false
                        $appsScriptVarsPanel.Visibility = 'Collapsed'
                        WriteLog "LoadConfig: AppsScriptVariables (Hashtable) key was present but empty. Unchecked 'Define Apps Script Variables'."
                    }
                }
                else {
                    $chkDefineAppsScriptVars.IsChecked = $false
                    $appsScriptVarsPanel.Visibility = 'Collapsed'
                    WriteLog "LoadConfig Info: Key 'AppsScriptVariables' not found, is null, or not a PSCustomObject/Hashtable. Unchecked 'Define Apps Script Variables'."
                }
                # Update the ListView's ItemsSource after populating the data list
                $lstAppsScriptVars.ItemsSource = $script:uiState.Data.appsScriptVariablesDataList.ToArray()
                # Update the header checkbox state
                if ($null -ne $script:uiState.Controls.chkSelectAllAppsScriptVariables) {
                    Update-SelectAllHeaderCheckBoxState -ListView $lstAppsScriptVars -HeaderCheckBox $script:uiState.Controls.chkSelectAllAppsScriptVariables
                }

                # Update USB Drive selection if present in config
                $usbDriveListKeyExists = $false
                if ($configContent -is [System.Management.Automation.PSCustomObject] -and $null -ne $configContent.PSObject.Properties) {
                    try {
                        if (($configContent.PSObject.Properties.Match('USBDriveList')).Count -gt 0) {
                            $usbDriveListKeyExists = $true
                        }
                    }
                    catch {
                        WriteLog "ERROR: Exception while trying to Match key 'USBDriveList' on configContent.PSObject.Properties. Error: $($_.Exception.Message)"
                    }
                }

                if ($usbDriveListKeyExists -and $null -ne $configContent.USBDriveList) {
                    WriteLog "LoadConfig: Processing USBDriveList from config."
                    # First click the Check USB Drives button to populate the list
                    $script:uiState.Controls.btnCheckUSBDrives.RaiseEvent(
                        [System.Windows.RoutedEventArgs]::new(
                            [System.Windows.Controls.Button]::ClickEvent
                        )
                    )

                    # Then select the drives that match the saved configuration
                    foreach ($item in $script:uiState.Controls.lstUSBDrives.Items) {
                        $propertyName = $item.Model
                        $propertyExists = $false
                        $propertyValue = $null

                        # Ensure USBDriveList is a PSCustomObject before trying to access its properties dynamically
                        if ($null -ne $configContent.USBDriveList -and $configContent.USBDriveList -is [System.Management.Automation.PSCustomObject]) {
                            # Check if the property exists on the USBDriveList object
                            if ($configContent.USBDriveList.PSObject.Properties.Match($propertyName).Count -gt 0) {
                                $propertyExists = $true
                                # Access the value dynamically
                                $propertyValue = $configContent.USBDriveList.$($propertyName)
                            }
                        }

                        if ($propertyExists -and ($propertyValue -eq $item.SerialNumber)) {
                            WriteLog "LoadConfig: Selecting USB Drive Model '$($item.Model)' with Serial '$($item.SerialNumber)'."
                            $item.IsSelected = $true
                        }
                        else {
                            if (-not $propertyExists -and ($null -ne $configContent.USBDriveList)) {
                                WriteLog "LoadConfig: Property '$($propertyName)' not found on USBDriveList for item Model '$($item.Model)'."
                            }
                            $item.IsSelected = $false # Ensure others are deselected if not in config or value mismatch
                        }
                    }
                    $script:uiState.Controls.lstUSBDrives.Items.Refresh()

                    # Update the Select All header checkbox state
                    $headerChk = $script:uiState.Controls.chkSelectAllUSBDrivesHeader
                    if ($null -ne $headerChk) {
                        Update-SelectAllHeaderCheckBoxState -ListView $script:uiState.Controls.lstUSBDrives -HeaderCheckBox $headerChk
                    }
                    WriteLog "LoadConfig: USBDriveList processing complete."
                }
                else {
                    WriteLog "LoadConfig Info: Key 'USBDriveList' not found or is null in configuration file. Skipping USB drive selection."
                }

                # If BuildUSBDrive is enabled and USBDriveList was present and not empty in the config,
                # ensure "Select Specific USB Drives" is checked to show the list.
                $shouldAutoCheckSpecificDrives = $false
                if ($window.FindName('chkBuildUSBDriveEnable').IsChecked -and $usbDriveListKeyExists -and ($null -ne $configContent.USBDriveList)) {
                    if ($configContent.USBDriveList -is [System.Management.Automation.PSCustomObject]) {
                        if ($configContent.USBDriveList.PSObject.Properties.Count -gt 0) {
                            $shouldAutoCheckSpecificDrives = $true
                        }
                    }
                    elseif ($configContent.USBDriveList -is [hashtable]) {
                        # Fallback for older configs
                        if ($configContent.USBDriveList.Keys.Count -gt 0) {
                            $shouldAutoCheckSpecificDrives = $true
                        }
                    }
                }

                if ($shouldAutoCheckSpecificDrives) {
                    WriteLog "LoadConfig: Auto-checking 'Select Specific USB Drives' due to pre-selected USB drives in config."
                    $script:uiState.Controls.chkSelectSpecificUSBDrives.IsChecked = $true
                }
                else {
                    WriteLog "LoadConfig: Condition to auto-check 'Select Specific USB Drives' was NOT met."
                }
                WriteLog "LoadConfig: Configuration loading process finished."
            }
        }
        catch {
            WriteLog "LoadConfig FATAL Error: $($_.Exception.ToString())" # Log full exception details
            [System.Windows.MessageBox]::Show("Error loading config file:`n$($_.Exception.Message)", "Error", "OK", "Error")
        }
    })

# Add handler for Remove button clicks
$window.Add_SourceInitialized({
        $listView = $window.FindName('lstApplications')
        $listView.AddHandler(
            [System.Windows.Controls.Button]::ClickEvent,
            [System.Windows.RoutedEventHandler] {
                param($buttonSender, $clickEventArgs)
                if ($clickEventArgs.OriginalSource -is [System.Windows.Controls.Button] -and $clickEventArgs.OriginalSource.Content -eq "Remove") {
                    Remove-Application -priority $clickEventArgs.OriginalSource.Tag -State $script:uiState
                }
            }
        )
    })

# Register cleanup to reclaim memory and revert LongPathsEnabled setting when the UI window closes
$window.Add_Closed({
        # Revert LongPathsEnabled registry setting if it was changed by this script
        if ($script:uiState.Flags.originalLongPathsValue -ne 1) {
            # Only revert if we changed it from something other than 1
            try {
                $currentValue = Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -ErrorAction SilentlyContinue
                if ($currentValue -eq 1) {
                    # Double-check it's still 1 before reverting
                    $revertValue = if ($null -eq $script:uiState.Flags.originalLongPathsValue) { 0 } else { $script:uiState.Flags.originalLongPathsValue } # Revert to original or 0 if it didn't exist
                    WriteLog "Reverting LongPathsEnabled registry key back to original value ($revertValue)."
                    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Value $revertValue -Force
                    WriteLog "LongPathsEnabled reverted."
                }
            }
            catch {
                WriteLog "Error reverting LongPathsEnabled registry key: $($_.Exception.Message)."
            }
        }

        # Garbage collection
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
    })

[void]$window.ShowDialog()
