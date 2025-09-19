<#
.SYNOPSIS
    Initializes the user interface for the BuildFFUVM_UI application.

.DESCRIPTION
    This script module contains functions responsible for initializing the WPF user interface.
    It handles several key tasks:
    - Caching references to all UI controls for efficient access.
    - Populating UI elements like combo boxes with data (e.g., Hyper-V switches).
    - Setting default values for all controls based on configuration or predefined settings.
    - Dynamically creating and configuring complex UI components, such as sortable/selectable GridView columns and feature selection grids.
    
    This module is critical for setting up the initial state of the application window when it first loads.
#>

function Initialize-UIControls {
    param([PSCustomObject]$State)
    WriteLog "Initializing UI control references..."
    $window = $State.Window
    # Find all controls ONCE and store them in the state object
    $State.Controls.cmbWindowsRelease = $window.FindName('cmbWindowsRelease')
    $State.Controls.cmbWindowsVersion = $window.FindName('cmbWindowsVersion')
    $State.Controls.txtISOPath = $window.FindName('txtISOPath')
    $State.Controls.btnBrowseISO = $window.FindName('btnBrowseISO')
    $State.Controls.cmbWindowsArch = $window.FindName('cmbWindowsArch')
    $State.Controls.cmbWindowsLang = $window.FindName('cmbWindowsLang')
    $State.Controls.WindowsLangStackPanel = $window.FindName('WindowsLangStackPanel')
    $State.Controls.cmbWindowsSKU = $window.FindName('cmbWindowsSKU')
    $State.Controls.cmbMediaType = $window.FindName('cmbMediaType')
    $State.Controls.MediaTypeStackPanel = $window.FindName('MediaTypeStackPanel')
    $State.Controls.featuresPanel = $window.FindName('stackFeaturesContainer')
    $State.Controls.chkDownloadDrivers = $window.FindName('chkDownloadDrivers')
    $State.Controls.cmbMake = $window.FindName('cmbMake')
    $State.Controls.spMakeSection = $window.FindName('spMakeSection')
    $State.Controls.btnGetModels = $window.FindName('btnGetModels')
    $State.Controls.spModelFilterSection = $window.FindName('spModelFilterSection')
    $State.Controls.txtModelFilter = $window.FindName('txtModelFilter')
    $State.Controls.lstDriverModels = $window.FindName('lstDriverModels')
    $State.Controls.spDriverActionButtons = $window.FindName('spDriverActionButtons')
    $State.Controls.btnSaveDriversJson = $window.FindName('btnSaveDriversJson')
    $State.Controls.btnImportDriversJson = $window.FindName('btnImportDriversJson')
    $State.Controls.btnDownloadSelectedDrivers = $window.FindName('btnDownloadSelectedDrivers')
    $State.Controls.btnClearDriverList = $window.FindName('btnClearDriverList')
    $State.Controls.chkInstallOffice = $window.FindName('chkInstallOffice')
    $State.Controls.chkInstallApps = $window.FindName('chkInstallApps')
    $State.Controls.OfficePathStackPanel = $window.FindName('OfficePathStackPanel')
    $State.Controls.OfficePathGrid = $window.FindName('OfficePathGrid')
    $State.Controls.CopyOfficeConfigXMLStackPanel = $window.FindName('CopyOfficeConfigXMLStackPanel')
    $State.Controls.OfficeConfigurationXMLFileStackPanel = $window.FindName('OfficeConfigurationXMLFileStackPanel')
    $State.Controls.OfficeConfigurationXMLFileGrid = $window.FindName('OfficeConfigurationXMLFileGrid')
    $State.Controls.chkCopyOfficeConfigXML = $window.FindName('chkCopyOfficeConfigXML')
    $State.Controls.chkLatestCU = $window.FindName('chkUpdateLatestCU')
    $State.Controls.chkPreviewCU = $window.FindName('chkUpdatePreviewCU')
    $State.Controls.btnCheckUSBDrives = $window.FindName('btnCheckUSBDrives')
    $State.Controls.lstUSBDrives = $window.FindName('lstUSBDrives')
    $State.Controls.chkBuildUSBDriveEnable = $window.FindName('chkBuildUSBDriveEnable')
    $State.Controls.usbSection = $window.FindName('usbDriveSection')
    $State.Controls.chkSelectSpecificUSBDrives = $window.FindName('chkSelectSpecificUSBDrives')
    $State.Controls.usbSelectionPanel = $window.FindName('usbDriveSelectionPanel')
    $State.Controls.chkAllowExternalHardDiskMedia = $window.FindName('chkAllowExternalHardDiskMedia')
    $State.Controls.chkPromptExternalHardDiskMedia = $window.FindName('chkPromptExternalHardDiskMedia')
    $State.Controls.chkCopyAdditionalFFUFiles = $window.FindName('chkCopyAdditionalFFUFiles')
    $State.Controls.additionalFFUPanel = $window.FindName('additionalFFUPanel')
    $State.Controls.lstAdditionalFFUs = $window.FindName('lstAdditionalFFUs')
    $State.Controls.btnRefreshAdditionalFFUs = $window.FindName('btnRefreshAdditionalFFUs')
    $State.Controls.chkInstallWingetApps = $window.FindName('chkInstallWingetApps')
    $State.Controls.wingetPanel = $window.FindName('wingetPanel')
    $State.Controls.btnCheckWingetModule = $window.FindName('btnCheckWingetModule')
    $State.Controls.txtWingetVersion = $window.FindName('txtWingetVersion')
    $State.Controls.txtWingetModuleVersion = $window.FindName('txtWingetModuleVersion')
    $State.Controls.applicationPathPanel = $window.FindName('applicationPathPanel')
    $State.Controls.appListJsonPathPanel = $window.FindName('appListJsonPathPanel')
    $State.Controls.btnBrowseApplicationPath = $window.FindName('btnBrowseApplicationPath')
    $State.Controls.btnBrowseAppListJsonPath = $window.FindName('btnBrowseAppListJsonPath')
    $State.Controls.chkBringYourOwnApps = $window.FindName('chkBringYourOwnApps')
    $State.Controls.byoApplicationPanel = $window.FindName('byoApplicationPanel')
    $State.Controls.wingetSearchPanel = $window.FindName('wingetSearchPanel')
    $State.Controls.txtWingetSearch = $window.FindName('txtWingetSearch')
    $State.Controls.btnWingetSearch = $window.FindName('btnWingetSearch')
    $State.Controls.lstWingetResults = $window.FindName('lstWingetResults')
    $State.Controls.btnSaveWingetList = $window.FindName('btnSaveWingetList')
    $State.Controls.btnImportWingetList = $window.FindName('btnImportWingetList')
    $State.Controls.btnClearWingetList = $window.FindName('btnClearWingetList')
    $State.Controls.btnDownloadSelected = $window.FindName('btnDownloadSelected')
    $State.Controls.btnBrowseAppSource = $window.FindName('btnBrowseAppSource')
    $State.Controls.btnBrowseFFUDevPath = $window.FindName('btnBrowseFFUDevPath')
    $State.Controls.btnBrowseFFUCaptureLocation = $window.FindName('btnBrowseFFUCaptureLocation')
    $State.Controls.btnBrowseOfficePath = $window.FindName('btnBrowseOfficePath')
    $State.Controls.btnBrowseDriversFolder = $window.FindName('btnBrowseDriversFolder')
    $State.Controls.btnBrowsePEDriversFolder = $window.FindName('btnBrowsePEDriversFolder')
    $State.Controls.txtAppName = $window.FindName('txtAppName')
    $State.Controls.txtAppCommandLine = $window.FindName('txtAppCommandLine')
    $State.Controls.txtAppArguments = $window.FindName('txtAppArguments')
    $State.Controls.txtAppSource = $window.FindName('txtAppSource')
    $State.Controls.txtAppAdditionalExitCodes = $window.FindName('txtAppAdditionalExitCodes')
    $State.Controls.chkIgnoreExitCodes = $window.FindName('chkIgnoreExitCodes')
    $State.Controls.btnAddApplication = $window.FindName('btnAddApplication')
    $State.Controls.btnSaveBYOApplications = $window.FindName('btnSaveBYOApplications')
    $State.Controls.btnLoadBYOApplications = $window.FindName('btnLoadBYOApplications')
    $State.Controls.btnEditApplication = $window.FindName('btnEditApplication')
    $State.Controls.btnClearBYOApplications = $window.FindName('btnClearBYOApplications')
    $State.Controls.btnRemoveSelectedBYOApps = $window.FindName('btnRemoveSelectedBYOApps')
    $State.Controls.btnCopyBYOApps = $window.FindName('btnCopyBYOApps')
    $State.Controls.lstApplications = $window.FindName('lstApplications')
    $State.Controls.btnMoveTop = $window.FindName('btnMoveTop')
    $State.Controls.btnMoveUp = $window.FindName('btnMoveUp')
    $State.Controls.btnMoveDown = $window.FindName('btnMoveDown')
    $State.Controls.btnMoveBottom = $window.FindName('btnMoveBottom')
    $State.Controls.txtStatus = $window.FindName('txtStatus')
    $State.Controls.pbOverallProgress = $window.FindName('progressBar')
    $State.Controls.txtOverallStatus = $window.FindName('txtStatus')
    $State.Controls.cmbVMSwitchName = $window.FindName('cmbVMSwitchName')
    $State.Controls.txtVMHostIPAddress = $window.FindName('txtVMHostIPAddress')
    $State.Controls.txtCustomVMSwitchName = $window.FindName('txtCustomVMSwitchName')
    $State.Controls.txtFFUDevPath = $window.FindName('txtFFUDevPath')
    $State.Controls.txtCustomFFUNameTemplate = $window.FindName('txtCustomFFUNameTemplate')
    $State.Controls.txtFFUCaptureLocation = $window.FindName('txtFFUCaptureLocation')
    $State.Controls.txtShareName = $window.FindName('txtShareName')
    $State.Controls.txtUsername = $window.FindName('txtUsername')
    $State.Controls.txtThreads = $window.FindName('txtThreads')
    $State.Controls.txtMaxUSBDrives = $window.FindName('txtMaxUSBDrives')
    $State.Controls.chkCompactOS = $window.FindName('chkCompactOS')
    $State.Controls.chkOptimize = $window.FindName('chkOptimize')
    $State.Controls.chkAllowVHDXCaching = $window.FindName('chkAllowVHDXCaching')
    $State.Controls.chkCreateCaptureMedia = $window.FindName('chkCreateCaptureMedia')
    $State.Controls.chkCreateDeploymentMedia = $window.FindName('chkCreateDeploymentMedia')
    $State.Controls.chkInjectUnattend = $window.FindName('chkInjectUnattend')
    $State.Controls.chkVerbose = $window.FindName('chkVerbose')
    $State.Controls.chkCopyAutopilot = $window.FindName('chkCopyAutopilot')
    $State.Controls.chkCopyUnattend = $window.FindName('chkCopyUnattend')
    $State.Controls.chkCopyPPKG = $window.FindName('chkCopyPPKG')
    $State.Controls.chkCleanupAppsISO = $window.FindName('chkCleanupAppsISO')
    $State.Controls.chkCleanupCaptureISO = $window.FindName('chkCleanupCaptureISO')
    $State.Controls.chkCleanupDeployISO = $window.FindName('chkCleanupDeployISO')
    $State.Controls.chkCleanupDrivers = $window.FindName('chkCleanupDrivers')
    $State.Controls.chkRemoveFFU = $window.FindName('chkRemoveFFU')
    $State.Controls.txtDiskSize = $window.FindName('txtDiskSize')
    $State.Controls.txtMemory = $window.FindName('txtMemory')
    $State.Controls.txtProcessors = $window.FindName('txtProcessors')
    $State.Controls.txtVMLocation = $window.FindName('txtVMLocation')
    $State.Controls.txtVMNamePrefix = $window.FindName('txtVMNamePrefix')
    $State.Controls.cmbLogicalSectorSize = $window.FindName('cmbLogicalSectorSize')
    $State.Controls.txtProductKey = $window.FindName('txtProductKey')
    $State.Controls.txtOfficePath = $window.FindName('txtOfficePath')
    $State.Controls.txtOfficeConfigXMLFilePath = $window.FindName('txtOfficeConfigXMLFilePath')
    $State.Controls.btnBrowseOfficeConfigXMLFile = $window.FindName('btnBrowseOfficeConfigXMLFile')
    $State.Controls.txtDriversFolder = $window.FindName('txtDriversFolder')
    $State.Controls.txtPEDriversFolder = $window.FindName('txtPEDriversFolder')
    $State.Controls.chkCopyPEDrivers = $window.FindName('chkCopyPEDrivers')
    $State.Controls.chkUseDriversAsPEDrivers = $window.FindName('chkUseDriversAsPEDrivers')
    $State.Controls.chkUpdateLatestCU = $window.FindName('chkUpdateLatestCU')
    $State.Controls.chkUpdateLatestNet = $window.FindName('chkUpdateLatestNet')
    $State.Controls.chkUpdateLatestDefender = $window.FindName('chkUpdateLatestDefender')
    $State.Controls.chkUpdateEdge = $window.FindName('chkUpdateEdge')
    $State.Controls.chkUpdateOneDrive = $window.FindName('chkUpdateOneDrive')
    $State.Controls.chkUpdateLatestMSRT = $window.FindName('chkUpdateLatestMSRT')
    $State.Controls.chkUpdatePreviewCU = $window.FindName('chkUpdatePreviewCU')
    $State.Controls.txtApplicationPath = $window.FindName('txtApplicationPath')
    $State.Controls.txtAppListJsonPath = $window.FindName('txtAppListJsonPath')
    $State.Controls.chkInstallDrivers = $window.FindName('chkInstallDrivers')
    $State.Controls.chkCopyDrivers = $window.FindName('chkCopyDrivers')
    $State.Controls.chkCompressDriversToWIM = $window.FindName('chkCompressDriversToWIM')
    $State.Controls.chkRemoveApps = $window.FindName('chkRemoveApps')
    $State.Controls.chkRemoveUpdates = $window.FindName('chkRemoveUpdates')
    $State.Controls.chkUpdateLatestMicrocode = $window.FindName('chkUpdateLatestMicrocode')
    $State.Controls.chkDefineAppsScriptVariables = $window.FindName('chkDefineAppsScriptVariables')
    $State.Controls.appsScriptVariablesPanel = $window.FindName('appsScriptVariablesPanel')
    $State.Controls.txtAppsScriptKey = $window.FindName('txtAppsScriptKey')
    $State.Controls.txtAppsScriptValue = $window.FindName('txtAppsScriptValue')
    $State.Controls.btnAddAppsScriptVariable = $window.FindName('btnAddAppsScriptVariable')
    $State.Controls.lstAppsScriptVariables = $window.FindName('lstAppsScriptVariables')
    $State.Controls.btnRemoveSelectedAppsScriptVariables = $window.FindName('btnRemoveSelectedAppsScriptVariables')
    $State.Controls.btnClearAppsScriptVariables = $window.FindName('btnClearAppsScriptVariables')
    $State.Controls.txtDriversJsonPath = $window.FindName('txtDriversJsonPath')
    $State.Controls.btnBrowseDriversJsonPath = $window.FindName('btnBrowseDriversJsonPath')
    $State.Controls.chkUpdateADK = $window.FindName('chkUpdateADK')
    $State.Controls.btnLoadConfig = $window.FindName('btnLoadConfig')
    $State.Controls.btnRestoreDefaults = $window.FindName('btnRestoreDefaults')
    $State.Controls.btnBuildConfig = $window.FindName('btnBuildConfig')

    # Monitor Tab
    $State.Controls.MainTabControl = $window.FindName('MainTabControl')
    $State.Controls.MonitorTab = $window.FindName('MonitorTab')
    $State.Controls.lstLogOutput = $window.FindName('lstLogOutput')

    # Initialize and bind the log data collection
    $State.Data.logData = New-Object System.Collections.ObjectModel.ObservableCollection[string]
    $State.Controls.lstLogOutput.ItemsSource = $State.Data.logData
}

function Initialize-VMSwitchData {
    param([PSCustomObject]$State)

    WriteLog "Initializing VM Switch data..."
    
    # Hyper-V Settings: Populate VM Switch ComboBox
    $vmSwitchData = Get-VMSwitchData
    $State.Data.vmSwitchMap = $vmSwitchData.SwitchMap
    $State.Controls.cmbVMSwitchName.Items.Clear()
    foreach ($switchName in $vmSwitchData.SwitchNames) {
        $State.Controls.cmbVMSwitchName.Items.Add($switchName) | Out-Null
    }
    $State.Controls.cmbVMSwitchName.Items.Add('Other') | Out-Null
    if ($State.Controls.cmbVMSwitchName.Items.Count -gt 1) {
        $State.Controls.cmbVMSwitchName.SelectedIndex = 0
        $firstSwitch = $State.Controls.cmbVMSwitchName.SelectedItem
        if ($null -ne $firstSwitch -and $State.Data.vmSwitchMap.ContainsKey($firstSwitch)) {
            $State.Controls.txtVMHostIPAddress.Text = $State.Data.vmSwitchMap[$firstSwitch]
        }
        else {
            $State.Controls.txtVMHostIPAddress.Text = $State.Defaults.generalDefaults.VMHostIPAddress # Use default if IP not found or key null
        }
        $State.Controls.txtCustomVMSwitchName.Visibility = 'Collapsed'
    }
    else {
        $State.Controls.cmbVMSwitchName.SelectedItem = 'Other'
        $State.Controls.txtCustomVMSwitchName.Visibility = 'Visible'
        $State.Controls.txtVMHostIPAddress.Text = $State.Defaults.generalDefaults.VMHostIPAddress # Use default
    }
}

function Initialize-UIDefaults {
    param([PSCustomObject]$State)
    WriteLog "Initializing UI defaults..."

    # Get default values from helper functions
    $State.Defaults.windowsSettingsDefaults = Get-WindowsSettingsDefaults
    $State.Defaults.generalDefaults = Get-GeneralDefaults -FFUDevelopmentPath $State.FFUDevelopmentPath

    # Build tab defaults from General Defaults
    $State.Controls.txtFFUDevPath.Text = $State.FFUDevelopmentPath 
    $State.Controls.txtCustomFFUNameTemplate.Text = $State.Defaults.generalDefaults.CustomFFUNameTemplate
    $State.Controls.txtFFUCaptureLocation.Text = $State.Defaults.generalDefaults.FFUCaptureLocation
    $State.Controls.txtShareName.Text = $State.Defaults.generalDefaults.ShareName
    $State.Controls.txtUsername.Text = $State.Defaults.generalDefaults.Username
    $State.Controls.txtThreads.Text = $State.Defaults.generalDefaults.Threads
    $State.Controls.txtMaxUSBDrives.Text = $State.Defaults.generalDefaults.MaxUSBDrives
    $State.Controls.chkBuildUSBDriveEnable.IsChecked = $State.Defaults.generalDefaults.BuildUSBDriveEnable
    $State.Controls.chkCompactOS.IsChecked = $State.Defaults.generalDefaults.CompactOS
    $State.Controls.chkUpdateADK.IsChecked = $State.Defaults.generalDefaults.UpdateADK
    $State.Controls.chkOptimize.IsChecked = $State.Defaults.generalDefaults.Optimize
    $State.Controls.chkAllowVHDXCaching.IsChecked = $State.Defaults.generalDefaults.AllowVHDXCaching
    $State.Controls.chkInjectUnattend.IsChecked = $State.Defaults.generalDefaults.InjectUnattend
    $State.Controls.chkCreateCaptureMedia.IsChecked = $State.Defaults.generalDefaults.CreateCaptureMedia
    $State.Controls.chkCreateDeploymentMedia.IsChecked = $State.Defaults.generalDefaults.CreateDeploymentMedia
    $State.Controls.chkAllowExternalHardDiskMedia.IsChecked = $State.Defaults.generalDefaults.AllowExternalHardDiskMedia
    $State.Controls.chkPromptExternalHardDiskMedia.IsChecked = $State.Defaults.generalDefaults.PromptExternalHardDiskMedia
    $State.Controls.chkSelectSpecificUSBDrives.IsChecked = $State.Defaults.generalDefaults.SelectSpecificUSBDrives
    $State.Controls.chkCopyAutopilot.IsChecked = $State.Defaults.generalDefaults.CopyAutopilot
    $State.Controls.chkCopyUnattend.IsChecked = $State.Defaults.generalDefaults.CopyUnattend
    $State.Controls.chkCopyPPKG.IsChecked = $State.Defaults.generalDefaults.CopyPPKG
    $State.Controls.chkCleanupAppsISO.IsChecked = $State.Defaults.generalDefaults.CleanupAppsISO
    $State.Controls.chkCleanupCaptureISO.IsChecked = $State.Defaults.generalDefaults.CleanupCaptureISO
    $State.Controls.chkCleanupDeployISO.IsChecked = $State.Defaults.generalDefaults.CleanupDeployISO
    $State.Controls.chkCleanupDrivers.IsChecked = $State.Defaults.generalDefaults.CleanupDrivers
    $State.Controls.chkRemoveFFU.IsChecked = $State.Defaults.generalDefaults.RemoveFFU
    $State.Controls.chkRemoveApps.IsChecked = $State.Defaults.generalDefaults.RemoveApps
    $State.Controls.chkRemoveUpdates.IsChecked = $State.Defaults.generalDefaults.RemoveUpdates
    $State.Controls.chkVerbose.IsChecked = $State.Defaults.generalDefaults.Verbose
    $State.Controls.usbSection.Visibility = if ($State.Controls.chkBuildUSBDriveEnable.IsChecked) { 'Visible' } else { 'Collapsed' }
    $State.Controls.usbSelectionPanel.Visibility = if ($State.Controls.chkSelectSpecificUSBDrives.IsChecked) { 'Visible' } else { 'Collapsed' }
    $State.Controls.chkSelectSpecificUSBDrives.IsEnabled = $State.Controls.chkBuildUSBDriveEnable.IsChecked
    $State.Controls.chkPromptExternalHardDiskMedia.IsEnabled = $State.Controls.chkAllowExternalHardDiskMedia.IsChecked
    $State.Controls.chkCopyAdditionalFFUFiles.IsChecked = $State.Defaults.generalDefaults.CopyAdditionalFFUFiles
    $State.Controls.additionalFFUPanel.Visibility = if ($State.Controls.chkCopyAdditionalFFUFiles.IsChecked) { 'Visible' } else { 'Collapsed' }

    # Hyper-V Settings defaults from General Defaults
    Initialize-VMSwitchData -State $State
    $State.Controls.txtDiskSize.Text = $State.Defaults.generalDefaults.DiskSizeGB
    $State.Controls.txtMemory.Text = $State.Defaults.generalDefaults.MemoryGB
    $State.Controls.txtProcessors.Text = $State.Defaults.generalDefaults.Processors
    $State.Controls.txtVMLocation.Text = $State.Defaults.generalDefaults.VMLocation
    $State.Controls.txtVMNamePrefix.Text = $State.Defaults.generalDefaults.VMNamePrefix
    $State.Controls.cmbLogicalSectorSize.SelectedItem = ($State.Controls.cmbLogicalSectorSize.Items | Where-Object { $_.Content -eq $State.Defaults.generalDefaults.LogicalSectorSize.ToString() })
   
    # Populate Windows Release, Version, and SKU comboboxes
    Get-WindowsSettingsCombos -isoPath $State.Defaults.windowsSettingsDefaults.DefaultISOPath -State $State
    
    # Windows Settings tab defaults
    $State.Controls.cmbWindowsLang.ItemsSource = $State.Defaults.windowsSettingsDefaults.AllowedLanguages
    $State.Controls.cmbWindowsLang.SelectedItem = $State.Defaults.windowsSettingsDefaults.DefaultWindowsLang
    $State.Controls.cmbMediaType.ItemsSource = $State.Defaults.windowsSettingsDefaults.AllowedMediaTypes
    $State.Controls.cmbMediaType.SelectedItem = $State.Defaults.windowsSettingsDefaults.DefaultMediaType
    $State.Controls.txtProductKey.Text = $State.Defaults.windowsSettingsDefaults.DefaultProductKey

    # Updates tab defaults from General Defaults
    $State.Controls.chkUpdateLatestCU.IsChecked = $State.Defaults.generalDefaults.UpdateLatestCU
    $State.Controls.chkUpdateLatestNet.IsChecked = $State.Defaults.generalDefaults.UpdateLatestNet
    $State.Controls.chkUpdateLatestDefender.IsChecked = $State.Defaults.generalDefaults.UpdateLatestDefender
    $State.Controls.chkUpdateEdge.IsChecked = $State.Defaults.generalDefaults.UpdateEdge
    $State.Controls.chkUpdateOneDrive.IsChecked = $State.Defaults.generalDefaults.UpdateOneDrive
    $State.Controls.chkUpdateLatestMSRT.IsChecked = $State.Defaults.generalDefaults.UpdateLatestMSRT
    $State.Controls.chkUpdateLatestMicrocode.IsChecked = $State.Defaults.generalDefaults.UpdateLatestMicrocode
    $State.Controls.chkUpdatePreviewCU.IsChecked = $State.Defaults.generalDefaults.UpdatePreviewCU
    # Set initial state for CU checkbox interplay
    $State.Controls.chkPreviewCU.IsEnabled = -not $State.Controls.chkLatestCU.IsChecked
    $State.Controls.chkLatestCU.IsEnabled = -not $State.Controls.chkPreviewCU.IsChecked

    # Applications tab defaults from General Defaults
    $State.Controls.chkInstallApps.IsChecked = $State.Defaults.generalDefaults.InstallApps
    $State.Controls.txtApplicationPath.Text = $State.Defaults.generalDefaults.ApplicationPath
    $State.Controls.txtAppListJsonPath.Text = $State.Defaults.generalDefaults.AppListJsonPath
    $State.Controls.chkInstallWingetApps.IsChecked = $State.Defaults.generalDefaults.InstallWingetApps
    $State.Controls.chkBringYourOwnApps.IsChecked = $State.Defaults.generalDefaults.BringYourOwnApps

    # M365 Apps/Office tab defaults from General Defaults
    $State.Controls.chkInstallOffice.IsChecked = $State.Defaults.generalDefaults.InstallOffice
    $State.Controls.txtOfficePath.Text = $State.Defaults.generalDefaults.OfficePath
    $State.Controls.chkCopyOfficeConfigXML.IsChecked = $State.Defaults.generalDefaults.CopyOfficeConfigXML
    $State.Controls.txtOfficeConfigXMLFilePath.Text = $State.Defaults.generalDefaults.OfficeConfigXMLFilePath

    # Drivers tab defaults from General Defaults
    $State.Controls.txtDriversFolder.Text = $State.Defaults.generalDefaults.DriversFolder
    $State.Controls.txtPEDriversFolder.Text = $State.Defaults.generalDefaults.PEDriversFolder
    $State.Controls.txtDriversJsonPath.Text = $State.Defaults.generalDefaults.DriversJsonPath
    $State.Controls.chkDownloadDrivers.IsChecked = $State.Defaults.generalDefaults.DownloadDrivers
    $State.Controls.chkInstallDrivers.IsChecked = $State.Defaults.generalDefaults.InstallDrivers
    $State.Controls.chkCopyDrivers.IsChecked = $State.Defaults.generalDefaults.CopyDrivers
    $State.Controls.chkCopyPEDrivers.IsChecked = $State.Defaults.generalDefaults.CopyPEDrivers
    $State.Controls.chkUseDriversAsPEDrivers.IsChecked = $State.Defaults.generalDefaults.UseDriversAsPEDrivers
    $State.Controls.chkCompressDriversToWIM.IsChecked = $State.Defaults.generalDefaults.CompressDownloadedDriversToWim

    # Drivers tab UI logic
    $makeList = @('Microsoft', 'Dell', 'HP', 'Lenovo')
    foreach ($m in $makeList) {
        [void]$State.Controls.cmbMake.Items.Add($m)
    }
    if ($State.Controls.cmbMake.Items.Count -gt 0) {
        $State.Controls.cmbMake.SelectedIndex = 0
    }
    Update-DriverDownloadPanelVisibility -State $State

    # Set initial state for driver checkbox interplay
    Update-DriverCheckboxStates -State $State

    # Set initial state for InstallApps checkbox based on updates
    Update-InstallAppsState -State $State

    # Set initial state for Office panel visibility
    Update-OfficePanelVisibility -State $State
    
    # Set initial state for Application panel visibility
    Update-ApplicationPanelVisibility -State $State
    
    # Set initial state for BYO Apps copy button
    Update-CopyButtonState -State $State
}

function Initialize-DynamicUIElements {
    param([PSCustomObject]$State)
    WriteLog "Initializing dynamic UI elements (Grids, Columns)..."

    # Driver Models ListView setup
    # Set ListViewItem style to stretch content horizontally so cell templates fill the cell
    $itemStyleDriverModels = New-Object System.Windows.Style([System.Windows.Controls.ListViewItem])
    $itemStyleDriverModels.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.ListViewItem]::HorizontalContentAlignmentProperty, [System.Windows.HorizontalAlignment]::Stretch)))
    $State.Controls.lstDriverModels.ItemContainerStyle = $itemStyleDriverModels

    $driverModelsGridView = New-Object System.Windows.Controls.GridView
    $State.Controls.lstDriverModels.View = $driverModelsGridView # Assign GridView to ListView first

    # Add the selectable column using the new function
    Add-SelectableGridViewColumn -ListView $State.Controls.lstDriverModels -State $State -HeaderCheckBoxKeyName "chkSelectAllDriverModels" -ColumnWidth 70

    # Add other sortable columns with left-aligned headers
    Add-SortableColumn -gridView $driverModelsGridView -header "Make" -binding "Make" -width 100 -headerHorizontalAlignment Left
    Add-SortableColumn -gridView $driverModelsGridView -header "Model" -binding "Model" -width 200 -headerHorizontalAlignment Left
    Add-SortableColumn -gridView $driverModelsGridView -header "Status" -binding "DownloadStatus" -width 150 -headerHorizontalAlignment Left
    $State.Controls.lstDriverModels.AddHandler(
        [System.Windows.Controls.GridViewColumnHeader]::ClickEvent,
        [System.Windows.RoutedEventHandler] {
            param($eventSource, $e) # $eventSource is the ListView control
            $header = $e.OriginalSource
            if ($header -is [System.Windows.Controls.GridViewColumnHeader] -and $header.Tag) {
                # Retrieve the main UI state object from the window's Tag property
                $listViewControl = $eventSource
                $window = [System.Windows.Window]::GetWindow($listViewControl)
                $uiStateFromWindowTag = $window.Tag
                
                Invoke-ListViewSort -listView $eventSource -property $header.Tag -State $uiStateFromWindowTag
            }
        }
    )

    # Winget Search ListView setup
    $wingetGridView = New-Object System.Windows.Controls.GridView
    $State.Controls.lstWingetResults.View = $wingetGridView # Assign GridView to ListView first

    # Set ListViewItem style to stretch content horizontally so cell templates fill the cell
    $itemStyleWingetResults = New-Object System.Windows.Style([System.Windows.Controls.ListViewItem])
    $itemStyleWingetResults.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.ListViewItem]::HorizontalContentAlignmentProperty, [System.Windows.HorizontalAlignment]::Stretch)))
    $State.Controls.lstWingetResults.ItemContainerStyle = $itemStyleWingetResults

    # Add the selectable column using the new function
    Add-SelectableGridViewColumn -ListView $State.Controls.lstWingetResults -State $State -HeaderCheckBoxKeyName "chkSelectAllWingetResults" -ColumnWidth 60

    # Add other sortable columns with left-aligned headers
    Add-SortableColumn -gridView $wingetGridView -header "Name" -binding "Name" -width 200 -headerHorizontalAlignment Left
    Add-SortableColumn -gridView $wingetGridView -header "Id" -binding "Id" -width 200 -headerHorizontalAlignment Left
    Add-SortableColumn -gridView $wingetGridView -header "Version" -binding "Version" -width 100 -headerHorizontalAlignment Left
    Add-SortableColumn -gridView $wingetGridView -header "Source" -binding "Source" -width 100 -headerHorizontalAlignment Left

    # --- START: Add Architecture Column ---
    $archColumn = New-Object System.Windows.Controls.GridViewColumn
    $archHeader = New-Object System.Windows.Controls.GridViewColumnHeader
    $archHeader.Tag = "Architecture" # For sorting
    $archHeader.HorizontalContentAlignment = [System.Windows.HorizontalAlignment]::Left
    
    # Create header content with correct padding to match other columns
    $commonPaddingForHeader = New-Object System.Windows.Thickness(5, 2, 5, 2)
    $headerTextElementFactory = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.TextBlock])
    $headerTextElementFactory.SetValue([System.Windows.Controls.TextBlock]::TextProperty, "Architecture")
    $headerTextBlockPadding = New-Object System.Windows.Thickness($commonPaddingForHeader.Left, $commonPaddingForHeader.Top, $commonPaddingForHeader.Right, $commonPaddingForHeader.Bottom)
    $headerTextElementFactory.SetValue([System.Windows.Controls.TextBlock]::PaddingProperty, $headerTextBlockPadding)
    $headerTextElementFactory.SetValue([System.Windows.FrameworkElement]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Center)
    
    $headerDataTemplate = New-Object System.Windows.DataTemplate
    $headerDataTemplate.VisualTree = $headerTextElementFactory
    $archHeader.ContentTemplate = $headerDataTemplate
    
    $archColumn.Header = $archHeader
    $archColumn.Width = 120

    # Create the CellTemplate with a ComboBox
    $archCellTemplate = New-Object System.Windows.DataTemplate
    $comboBoxFactory = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.ComboBox])
    
    # The ItemsSource for the ComboBox
    $availableArchitectures = @('x86', 'x64', 'arm64', 'x86 x64', 'NA')
    $comboBoxFactory.SetValue([System.Windows.Controls.ItemsControl]::ItemsSourceProperty, $availableArchitectures)

    # Bind the text property to the 'Architecture' property of the data item.
    # This ensures the initial value is displayed correctly.
    $binding = New-Object System.Windows.Data.Binding("Architecture")
    $binding.Mode = [System.Windows.Data.BindingMode]::TwoWay
    $comboBoxFactory.SetBinding([System.Windows.Controls.ComboBox]::TextProperty, $binding)

    # Create a style to disable the ComboBox for 'msstore' source
    $comboBoxStyle = New-Object System.Windows.Style
    $comboBoxStyle.TargetType = [System.Windows.Controls.ComboBox]
    
    $dataTrigger = New-Object System.Windows.DataTrigger
    $dataTrigger.Binding = New-Object System.Windows.Data.Binding("Source")
    $dataTrigger.Value = "msstore"
    $dataTrigger.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.ComboBox]::IsEnabledProperty, $false)))
    
    $comboBoxStyle.Triggers.Add($dataTrigger)
    $comboBoxFactory.SetValue([System.Windows.FrameworkElement]::StyleProperty, $comboBoxStyle)

    $archCellTemplate.VisualTree = $comboBoxFactory
    $archColumn.CellTemplate = $archCellTemplate
    $wingetGridView.Columns.Add($archColumn)
    # --- END: Add Architecture Column ---

    # --- START: Add Additional Exit Codes Column ---
    $exitCodesColumn = New-Object System.Windows.Controls.GridViewColumn
    $exitCodesHeader = New-Object System.Windows.Controls.GridViewColumnHeader
    $exitCodesHeader.Tag = "AdditionalExitCodes"
    $exitCodesHeader.HorizontalContentAlignment = [System.Windows.HorizontalAlignment]::Left

    $exitHeaderTextFactory = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.TextBlock])
    $exitHeaderTextFactory.SetValue([System.Windows.Controls.TextBlock]::TextProperty, "Additional Exit Codes")
    $exitHeaderTextFactory.SetValue([System.Windows.Controls.TextBlock]::PaddingProperty, (New-Object System.Windows.Thickness(5, 2, 5, 2)))
    $exitHeaderTextFactory.SetValue([System.Windows.FrameworkElement]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Center)

    $exitHeaderTemplate = New-Object System.Windows.DataTemplate
    $exitHeaderTemplate.VisualTree = $exitHeaderTextFactory
    $exitCodesHeader.ContentTemplate = $exitHeaderTemplate

    $exitCodesColumn.Header = $exitCodesHeader
    $exitCodesColumn.Width = 140

    $exitCodesCellTemplate = New-Object System.Windows.DataTemplate
    $exitCodesTextBoxFactory = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.TextBox])
    $exitBinding = New-Object System.Windows.Data.Binding("AdditionalExitCodes")
    $exitBinding.Mode = [System.Windows.Data.BindingMode]::TwoWay
    $exitCodesTextBoxFactory.SetBinding([System.Windows.Controls.TextBox]::TextProperty, $exitBinding)
    $exitCodesCellTemplate.VisualTree = $exitCodesTextBoxFactory
    $exitCodesColumn.CellTemplate = $exitCodesCellTemplate
    $wingetGridView.Columns.Add($exitCodesColumn)
    # --- END: Add Additional Exit Codes Column ---

    # --- START: Add Ignore Non-Zero Exit Codes Column ---
    $ignoreColumn = New-Object System.Windows.Controls.GridViewColumn
    $ignoreHeader = New-Object System.Windows.Controls.GridViewColumnHeader
    $ignoreHeader.Tag = "IgnoreNonZeroExitCodes"
    $ignoreHeader.HorizontalContentAlignment = [System.Windows.HorizontalAlignment]::Left

    $ignoreHeaderTextFactory = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.TextBlock])
    $ignoreHeaderTextFactory.SetValue([System.Windows.Controls.TextBlock]::TextProperty, "Ignore Exit Codes")
    $ignoreHeaderTextFactory.SetValue([System.Windows.Controls.TextBlock]::PaddingProperty, (New-Object System.Windows.Thickness(5, 2, 5, 2)))
    $ignoreHeaderTextFactory.SetValue([System.Windows.FrameworkElement]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Center)

    $ignoreHeaderTemplate = New-Object System.Windows.DataTemplate
    $ignoreHeaderTemplate.VisualTree = $ignoreHeaderTextFactory
    $ignoreHeader.ContentTemplate = $ignoreHeaderTemplate

    $ignoreColumn.Header = $ignoreHeader
    $ignoreColumn.Width = 140

    $ignoreCellTemplate = New-Object System.Windows.DataTemplate

    # Center the checkbox in the cell
    $ignoreCellGridFactory = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.Grid])
    $ignoreCellGridFactory.SetValue([System.Windows.FrameworkElement]::HorizontalAlignmentProperty, [System.Windows.HorizontalAlignment]::Stretch)
    $ignoreCellGridFactory.SetValue([System.Windows.FrameworkElement]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Stretch)

    $ignoreCheckFactory = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.CheckBox])
    $ignoreCheckFactory.SetValue([System.Windows.FrameworkElement]::HorizontalAlignmentProperty, [System.Windows.HorizontalAlignment]::Center)
    $ignoreCheckFactory.SetValue([System.Windows.FrameworkElement]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Center)

    $ignoreBinding = New-Object System.Windows.Data.Binding("IgnoreNonZeroExitCodes")
    $ignoreBinding.Mode = [System.Windows.Data.BindingMode]::TwoWay
    $ignoreCheckFactory.SetBinding([System.Windows.Controls.Primitives.ToggleButton]::IsCheckedProperty, $ignoreBinding)

    # Build the visual tree: Grid -> CheckBox
    $ignoreCellGridFactory.AppendChild($ignoreCheckFactory)
    $ignoreCellTemplate.VisualTree = $ignoreCellGridFactory

    $ignoreColumn.CellTemplate = $ignoreCellTemplate
    $wingetGridView.Columns.Add($ignoreColumn)
    # --- END: Add Ignore Non-Zero Exit Codes Column ---

    Add-SortableColumn -gridView $wingetGridView -header "Download Status" -binding "DownloadStatus" -width 150 -headerHorizontalAlignment Left
    $State.Controls.lstWingetResults.AddHandler(
        [System.Windows.Controls.GridViewColumnHeader]::ClickEvent,
        [System.Windows.RoutedEventHandler] {
            param($eventSource, $e) # $eventSource is the ListView control
            $header = $e.OriginalSource
            if ($header -is [System.Windows.Controls.GridViewColumnHeader] -and $header.Tag) {
                # Retrieve the main UI state object from the window's Tag property
                $listViewControl = $eventSource
                $window = [System.Windows.Window]::GetWindow($listViewControl)
                $uiStateFromWindowTag = $window.Tag
                
                Invoke-ListViewSort -listView $eventSource -property $header.Tag -State $uiStateFromWindowTag
            }
        }
    )

    # BYO Applications ListView setup
    $byoAppsGridView = New-Object System.Windows.Controls.GridView
    $State.Controls.lstApplications.View = $byoAppsGridView

    # Set ListViewItem style to stretch content horizontally
    $itemStyleBYOApps = New-Object System.Windows.Style([System.Windows.Controls.ListViewItem])
    $itemStyleBYOApps.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.ListViewItem]::HorizontalContentAlignmentProperty, [System.Windows.HorizontalAlignment]::Stretch)))
    $State.Controls.lstApplications.ItemContainerStyle = $itemStyleBYOApps

    # Add the selectable column
    Add-SelectableGridViewColumn -ListView $State.Controls.lstApplications -State $State -HeaderCheckBoxKeyName "chkSelectAllBYOApps" -ColumnWidth 60

    # Add other sortable columns
    Add-SortableColumn -gridView $byoAppsGridView -header "Priority" -binding "Priority" -width 60 -headerHorizontalAlignment Left
    Add-SortableColumn -gridView $byoAppsGridView -header "Name" -binding "Name" -width 150 -headerHorizontalAlignment Left
    Add-SortableColumn -gridView $byoAppsGridView -header "Command Line" -binding "CommandLine" -width 200 -headerHorizontalAlignment Left
    Add-SortableColumn -gridView $byoAppsGridView -header "Arguments" -binding "Arguments" -width 200 -headerHorizontalAlignment Left
    Add-SortableColumn -gridView $byoAppsGridView -header "Source" -binding "Source" -width 150 -headerHorizontalAlignment Left
    Add-SortableColumn -gridView $byoAppsGridView -header "Exit Codes" -binding "AdditionalExitCodes" -width 100 -headerHorizontalAlignment Left
    Add-SortableColumn -gridView $byoAppsGridView -header "Ignore Exit Codes" -binding "IgnoreExitCodes" -width 120 -headerHorizontalAlignment Left
    Add-SortableColumn -gridView $byoAppsGridView -header "Copy Status" -binding "CopyStatus" -width 150 -headerHorizontalAlignment Left

    # Apps Script Variables ListView setup
    # Bind ItemsSource to the data list
    $State.Controls.lstAppsScriptVariables.ItemsSource = $State.Data.appsScriptVariablesDataList.ToArray()

    # Set ListViewItem style to stretch content horizontally so cell templates fill the cell
    $itemStyleAppsScriptVars = New-Object System.Windows.Style([System.Windows.Controls.ListViewItem])
    $itemStyleAppsScriptVars.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.ListViewItem]::HorizontalContentAlignmentProperty, [System.Windows.HorizontalAlignment]::Stretch)))
    $State.Controls.lstAppsScriptVariables.ItemContainerStyle = $itemStyleAppsScriptVars

    # The GridView for lstAppsScriptVariables is defined in XAML. We need to get it and add the column.
    if ($State.Controls.lstAppsScriptVariables.View -is [System.Windows.Controls.GridView]) {
        Add-SelectableGridViewColumn -ListView $State.Controls.lstAppsScriptVariables -State $State -HeaderCheckBoxKeyName "chkSelectAllAppsScriptVariables" -ColumnWidth 60

        # Make Key and Value columns sortable
        $appsScriptVarsGridView = $State.Controls.lstAppsScriptVariables.View

        # Key Column (should be at index 1 after selectable column is inserted at 0)
        if ($appsScriptVarsGridView.Columns.Count -gt 1) {
            $keyColumn = $appsScriptVarsGridView.Columns[1]
            $keyHeader = New-Object System.Windows.Controls.GridViewColumnHeader
            $keyHeader.Content = "Key"
            $keyHeader.Tag = "Key" # Property to sort by
            $keyHeader.HorizontalContentAlignment = [System.Windows.HorizontalAlignment]::Left
            $keyColumn.Header = $keyHeader
        }

        # Value Column (should be at index 2)
        if ($appsScriptVarsGridView.Columns.Count -gt 2) {
            $valueColumn = $appsScriptVarsGridView.Columns[2]
            $valueHeader = New-Object System.Windows.Controls.GridViewColumnHeader
            $valueHeader.Content = "Value"
            $valueHeader.Tag = "Value" # Property to sort by
            $valueHeader.HorizontalContentAlignment = [System.Windows.HorizontalAlignment]::Left
            $valueColumn.Header = $valueHeader
        }

        # Add Click event handler for sorting
        $State.Controls.lstAppsScriptVariables.AddHandler(
            [System.Windows.Controls.GridViewColumnHeader]::ClickEvent,
            [System.Windows.RoutedEventHandler] {
                param($eventSource, $e) # $eventSource is the ListView control
                $header = $e.OriginalSource
                if ($header -is [System.Windows.Controls.GridViewColumnHeader] -and $header.Tag) {
                    # Retrieve the main UI state object from the window's Tag property
                    $listViewControl = $eventSource
                    $window = [System.Windows.Window]::GetWindow($listViewControl)
                    $uiStateFromWindowTag = $window.Tag
                
                    Invoke-ListViewSort -listView $eventSource -property $header.Tag -State $uiStateFromWindowTag
                }
            }
        )
    }
    else {
        WriteLog "Warning: lstAppsScriptVariables.View is not a GridView. Selectable column not added, and sorting cannot be enabled."
    }

    # Build dynamic multi-column checkboxes for optional features
    if ($State.Controls.featuresPanel -and $State.Defaults.windowsSettingsDefaults) {
        BuildFeaturesGrid -parent $State.Controls.featuresPanel -allowedFeatures $State.Defaults.windowsSettingsDefaults.AllowedFeatures -State $State
    }
    else {
        WriteLog "Initialize-DynamicUIElements: Could not build features grid. Panel or defaults missing."
    }
    
    # USB Drives ListView setup
    # Set ListViewItem style to stretch content horizontally so cell templates fill the cell
    $itemStyleUSBDrives = New-Object System.Windows.Style([System.Windows.Controls.ListViewItem])
    $itemStyleUSBDrives.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.ListViewItem]::HorizontalContentAlignmentProperty, [System.Windows.HorizontalAlignment]::Stretch)))
    $State.Controls.lstUSBDrives.ItemContainerStyle = $itemStyleUSBDrives
    
    if ($State.Controls.lstUSBDrives.View -is [System.Windows.Controls.GridView]) {
        # Add the selectable column using the shared function
        Add-SelectableGridViewColumn -ListView $State.Controls.lstUSBDrives -State $State -HeaderCheckBoxKeyName "chkSelectAllUSBDrivesHeader" -ColumnWidth 70
    
        # Make other columns sortable
        $usbDrivesGridView = $State.Controls.lstUSBDrives.View
            
        # Model Column (index 0 in XAML, now 1)
        if ($usbDrivesGridView.Columns.Count -gt 1) {
            $modelColumn = $usbDrivesGridView.Columns[1]
            $modelHeader = New-Object System.Windows.Controls.GridViewColumnHeader
            $modelHeader.Content = "Model"
            $modelHeader.Tag = "Model" # Property to sort by
            $modelHeader.HorizontalContentAlignment = [System.Windows.HorizontalAlignment]::Left
            $modelColumn.Header = $modelHeader
        }
    
        # Serial Number Column (index 1 in XAML, now 2)
        if ($usbDrivesGridView.Columns.Count -gt 2) {
            $serialColumn = $usbDrivesGridView.Columns[2]
            $serialHeader = New-Object System.Windows.Controls.GridViewColumnHeader
            $serialHeader.Content = "Serial Number"
            $serialHeader.Tag = "SerialNumber" # Property to sort by
            $serialHeader.HorizontalContentAlignment = [System.Windows.HorizontalAlignment]::Left
            $serialColumn.Header = $serialHeader
        }
    
        # Size Column (index 2 in XAML, now 3)
        if ($usbDrivesGridView.Columns.Count -gt 3) {
            $sizeColumn = $usbDrivesGridView.Columns[3]
            $sizeHeader = New-Object System.Windows.Controls.GridViewColumnHeader
            $sizeHeader.Content = "Size (GB)"
            $sizeHeader.Tag = "Size" # Property to sort by
            $sizeHeader.HorizontalContentAlignment = [System.Windows.HorizontalAlignment]::Left
            $sizeColumn.Header = $sizeHeader
        }
    
        # Add Click event handler for sorting
        $State.Controls.lstUSBDrives.AddHandler(
            [System.Windows.Controls.GridViewColumnHeader]::ClickEvent,
            [System.Windows.RoutedEventHandler] {
                param($eventSource, $e) # $eventSource is the ListView control
                $header = $e.OriginalSource
                if ($header -is [System.Windows.Controls.GridViewColumnHeader] -and $header.Tag) {
                    # Retrieve the main UI state object from the window's Tag property
                    $listViewControl = $eventSource
                    $window = [System.Windows.Window]::GetWindow($listViewControl)
                    $uiStateFromWindowTag = $window.Tag
                        
                    Invoke-ListViewSort -listView $eventSource -property $header.Tag -State $uiStateFromWindowTag
                }
            }
        )
    }
    else {
        WriteLog "Warning: lstUSBDrives.View is not a GridView. Selectable column not added, and sorting cannot be enabled."
    }
    
    # Additional FFUs ListView setup
    $itemStyleAdditionalFFUs = New-Object System.Windows.Style([System.Windows.Controls.ListViewItem])
    $itemStyleAdditionalFFUs.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.ListViewItem]::HorizontalContentAlignmentProperty, [System.Windows.HorizontalAlignment]::Stretch)))
    $State.Controls.lstAdditionalFFUs.ItemContainerStyle = $itemStyleAdditionalFFUs
    
    if ($State.Controls.lstAdditionalFFUs.View -is [System.Windows.Controls.GridView]) {
        Add-SelectableGridViewColumn -ListView $State.Controls.lstAdditionalFFUs -State $State -HeaderCheckBoxKeyName "chkSelectAllAdditionalFFUs" -ColumnWidth 70
    
        $additionalFFUsGridView = $State.Controls.lstAdditionalFFUs.View
    
        if ($additionalFFUsGridView.Columns.Count -gt 1) {
            $nameColumn = $additionalFFUsGridView.Columns[1]
            $nameHeader = New-Object System.Windows.Controls.GridViewColumnHeader
            $nameHeader.Content = "FFU Name"
            $nameHeader.Tag = "Name"
            $nameHeader.HorizontalContentAlignment = [System.Windows.HorizontalAlignment]::Left
            $nameColumn.Header = $nameHeader
        }
        if ($additionalFFUsGridView.Columns.Count -gt 2) {
            $lastModColumn = $additionalFFUsGridView.Columns[2]
            $lastModHeader = New-Object System.Windows.Controls.GridViewColumnHeader
            $lastModHeader.Content = "Last Modified"
            $lastModHeader.Tag = "LastModified"
            $lastModHeader.HorizontalContentAlignment = [System.Windows.HorizontalAlignment]::Left
            $lastModColumn.Header = $lastModHeader
        }
    
        $State.Controls.lstAdditionalFFUs.AddHandler(
            [System.Windows.Controls.GridViewColumnHeader]::ClickEvent,
            [System.Windows.RoutedEventHandler] {
                param($eventSource, $e)
                $header = $e.OriginalSource
                if ($header -is [System.Windows.Controls.GridViewColumnHeader] -and $header.Tag) {
                    $listViewControl = $eventSource
                    $window = [System.Windows.Window]::GetWindow($listViewControl)
                    $uiStateFromWindowTag = $window.Tag
                    Invoke-ListViewSort -listView $eventSource -property $header.Tag -State $uiStateFromWindowTag
                }
            }
        )
    }
    else {
        WriteLog "Warning: lstAdditionalFFUs.View is not a GridView. Selectable column not added, and sorting cannot be enabled."
    }
}


Export-ModuleMember -Function *
