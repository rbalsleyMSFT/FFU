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
    $State.Controls.cmbWindowsSKU = $window.FindName('cmbWindowsSKU')
    $State.Controls.cmbMediaType = $window.FindName('cmbMediaType')
    $State.Controls.txtOptionalFeatures = $window.FindName('txtOptionalFeatures')
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
    $State.Controls.chkSelectAllUSBDrives = $window.FindName('chkSelectAllUSBDrives')
    $State.Controls.chkBuildUSBDriveEnable = $window.FindName('chkBuildUSBDriveEnable')
    $State.Controls.usbSection = $window.FindName('usbDriveSection')
    $State.Controls.chkSelectSpecificUSBDrives = $window.FindName('chkSelectSpecificUSBDrives')
    $State.Controls.usbSelectionPanel = $window.FindName('usbDriveSelectionPanel')
    $State.Controls.chkAllowExternalHardDiskMedia = $window.FindName('chkAllowExternalHardDiskMedia')
    $State.Controls.chkPromptExternalHardDiskMedia = $window.FindName('chkPromptExternalHardDiskMedia')
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
    $State.Controls.btnAddApplication = $window.FindName('btnAddApplication')
    $State.Controls.btnSaveBYOApplications = $window.FindName('btnSaveBYOApplications')
    $State.Controls.btnLoadBYOApplications = $window.FindName('btnLoadBYOApplications')
    $State.Controls.btnClearBYOApplications = $window.FindName('btnClearBYOApplications')
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
    $State.Controls.chkCompactOS = $window.FindName('chkCompactOS')
    $State.Controls.chkOptimize = $window.FindName('chkOptimize')
    $State.Controls.chkAllowVHDXCaching = $window.FindName('chkAllowVHDXCaching')
    $State.Controls.chkCreateCaptureMedia = $window.FindName('chkCreateCaptureMedia')
    $State.Controls.chkCreateDeploymentMedia = $window.FindName('chkCreateDeploymentMedia')
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
    $State.Controls.txtDriversFolder = $window.FindName('txtDriversFolder')
    $State.Controls.txtPEDriversFolder = $window.FindName('txtPEDriversFolder')
    $State.Controls.chkCopyPEDrivers = $window.FindName('chkCopyPEDrivers')
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
    $State.Controls.chkBuildUSBDriveEnable.IsChecked = $State.Defaults.generalDefaults.BuildUSBDriveEnable
    $State.Controls.chkCompactOS.IsChecked = $State.Defaults.generalDefaults.CompactOS
    $State.Controls.chkUpdateADK.IsChecked = $State.Defaults.generalDefaults.UpdateADK
    $State.Controls.chkOptimize.IsChecked = $State.Defaults.generalDefaults.Optimize
    $State.Controls.chkAllowVHDXCaching.IsChecked = $State.Defaults.generalDefaults.AllowVHDXCaching
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

    # Hyper-V Settings defaults from General Defaults
    $State.Controls.txtDiskSize.Text = $State.Defaults.generalDefaults.DiskSizeGB
    $State.Controls.txtMemory.Text = $State.Defaults.generalDefaults.MemoryGB
    $State.Controls.txtProcessors.Text = $State.Defaults.generalDefaults.Processors
    $State.Controls.txtVMLocation.Text = $State.Defaults.generalDefaults.VMLocation
    $State.Controls.txtVMNamePrefix.Text = $State.Defaults.generalDefaults.VMNamePrefix
    $State.Controls.cmbLogicalSectorSize.SelectedItem = ($State.Controls.cmbLogicalSectorSize.Items | Where-Object { $_.Content -eq $State.Defaults.generalDefaults.LogicalSectorSize.ToString() })
   
    # Populate Windows Release, Version, and SKU comboboxes
    Get-WindowsSettingsCombos -isoPath $State.Defaults.windowsSettingsDefaults.DefaultISOPath -State $State
    
    # Windows Settings tab defaults
    $State.Controls.cmbWindowsArch.ItemsSource = $State.Defaults.windowsSettingsDefaults.AllowedArchitectures
    $State.Controls.cmbWindowsArch.SelectedItem = $State.Defaults.windowsSettingsDefaults.DefaultWindowsArch
    $State.Controls.cmbWindowsLang.ItemsSource = $State.Defaults.windowsSettingsDefaults.AllowedLanguages
    $State.Controls.cmbWindowsLang.SelectedItem = $State.Defaults.windowsSettingsDefaults.DefaultWindowsLang
    $State.Controls.cmbWindowsSKU.SelectedItem = $State.Defaults.windowsSettingsDefaults.DefaultWindowsSKU
    $State.Controls.cmbMediaType.ItemsSource = $State.Defaults.windowsSettingsDefaults.AllowedMediaTypes
    $State.Controls.cmbMediaType.SelectedItem = $State.Defaults.windowsSettingsDefaults.DefaultMediaType
    $State.Controls.txtOptionalFeatures.Text = $State.Defaults.windowsSettingsDefaults.DefaultOptionalFeatures
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
    Add-SelectableGridViewColumn -ListView $State.Controls.lstDriverModels -HeaderCheckBoxScriptVariableName "chkSelectAllDriverModels" -ColumnWidth 70

    # Add other sortable columns with left-aligned headers
    Add-SortableColumn -gridView $driverModelsGridView -header "Make" -binding "Make" -width 100 -headerHorizontalAlignment Left
    Add-SortableColumn -gridView $driverModelsGridView -header "Model" -binding "Model" -width 200 -headerHorizontalAlignment Left
    Add-SortableColumn -gridView $driverModelsGridView -header "Download Status" -binding "DownloadStatus" -width 150 -headerHorizontalAlignment Left
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
    Add-SelectableGridViewColumn -ListView $State.Controls.lstWingetResults -HeaderCheckBoxScriptVariableName "chkSelectAllWingetResults" -ColumnWidth 60

    # Add other sortable columns with left-aligned headers
    Add-SortableColumn -gridView $wingetGridView -header "Name" -binding "Name" -width 200 -headerHorizontalAlignment Left
    Add-SortableColumn -gridView $wingetGridView -header "Id" -binding "Id" -width 200 -headerHorizontalAlignment Left
    Add-SortableColumn -gridView $wingetGridView -header "Version" -binding "Version" -width 100 -headerHorizontalAlignment Left
    Add-SortableColumn -gridView $wingetGridView -header "Source" -binding "Source" -width 100 -headerHorizontalAlignment Left
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

    # Apps Script Variables ListView setup
    # Bind ItemsSource to the data list
    $State.Controls.lstAppsScriptVariables.ItemsSource = $State.Data.appsScriptVariablesDataList.ToArray()

    # Set ListViewItem style to stretch content horizontally so cell templates fill the cell
    $itemStyleAppsScriptVars = New-Object System.Windows.Style([System.Windows.Controls.ListViewItem])
    $itemStyleAppsScriptVars.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.ListViewItem]::HorizontalContentAlignmentProperty, [System.Windows.HorizontalAlignment]::Stretch)))
    $State.Controls.lstAppsScriptVariables.ItemContainerStyle = $itemStyleAppsScriptVars

    # The GridView for lstAppsScriptVariables is defined in XAML. We need to get it and add the column.
    if ($State.Controls.lstAppsScriptVariables.View -is [System.Windows.Controls.GridView]) {
        Add-SelectableGridViewColumn -ListView $State.Controls.lstAppsScriptVariables -HeaderCheckBoxScriptVariableName "chkSelectAllAppsScriptVariables" -ColumnWidth 60

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
        if ($State.Data.vmSwitchMap.ContainsKey($firstSwitch)) {
            $State.Controls.txtVMHostIPAddress.Text = $State.Data.vmSwitchMap[$firstSwitch]
        }
        else {
            $State.Controls.txtVMHostIPAddress.Text = $State.Defaults.generalDefaults.VMHostIPAddress # Use default if IP not found
        }
        $State.Controls.txtCustomVMSwitchName.Visibility = 'Collapsed'
    }
    else {
        $State.Controls.cmbVMSwitchName.SelectedItem = 'Other'
        $State.Controls.txtCustomVMSwitchName.Visibility = 'Visible'
        $State.Controls.txtVMHostIPAddress.Text = $State.Defaults.generalDefaults.VMHostIPAddress # Use default
    }
}

function Register-EventHandlers {
    param([PSCustomObject]$State)
    WriteLog "Registering UI event handlers..."

    # Hyper-V tab event handlers
    $State.Controls.cmbVMSwitchName.Add_SelectionChanged({
            param($eventSource, $selectionChangedEventArgs)
            # The state object is available via the parent window's Tag property
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag

            $selectedItem = $eventSource.SelectedItem
            if ($selectedItem -eq 'Other') {
                $localState.Controls.txtCustomVMSwitchName.Visibility = 'Visible'
                $localState.Controls.txtVMHostIPAddress.Text = '' # Clear IP for custom
            }
            else {
                $localState.Controls.txtCustomVMSwitchName.Visibility = 'Collapsed'
                if ($localState.Data.vmSwitchMap.ContainsKey($selectedItem)) {
                    $localState.Controls.txtVMHostIPAddress.Text = $localState.Data.vmSwitchMap[$selectedItem]
                }
                else {
                    $localState.Controls.txtVMHostIPAddress.Text = '' # Clear IP if not found in map
                }
            }
        })

    # Windows Settings tab Event Handlers
    $State.Controls.txtISOPath.Add_TextChanged({
            param($eventSource, $textChangedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            Get-WindowsSettingsCombos -isoPath $localState.Controls.txtISOPath.Text -State $localState
        })

    $State.Controls.cmbWindowsRelease.Add_SelectionChanged({
            param($eventSource, $selectionChangedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $selectedReleaseValue = 11 # Default if null
            if ($null -ne $localState.Controls.cmbWindowsRelease.SelectedItem) {
                $selectedReleaseValue = $localState.Controls.cmbWindowsRelease.SelectedItem.Value
            }
            # Only need to update the Version combo when Release changes
            Update-WindowsVersionCombo -selectedRelease $selectedReleaseValue -isoPath $localState.Controls.txtISOPath.Text -State $localState
            # Also update the SKU combo (now derives values internally)
            Update-WindowsSkuCombo -State $localState
        })

    $State.Controls.btnBrowseISO.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $ofd = New-Object System.Windows.Forms.OpenFileDialog
            $ofd.Filter = "ISO files (*.iso)|*.iso"
            $ofd.Title = "Select Windows ISO File"
            if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $localState.Controls.txtISOPath.Text = $ofd.FileName }
        })

    # Drivers Tab Event Handlers
    $State.Controls.chkDownloadDrivers.Add_Checked({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $localState.Controls.cmbMake.Visibility = 'Visible'
            $localState.Controls.btnGetModels.Visibility = 'Visible'
            $localState.Controls.spMakeSection.Visibility = 'Visible'
            $localState.Controls.spModelFilterSection.Visibility = 'Visible'
            $localState.Controls.lstDriverModels.Visibility = 'Visible'
            $localState.Controls.spDriverActionButtons.Visibility = 'Visible'
        })
    $State.Controls.chkDownloadDrivers.Add_Unchecked({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $localState.Controls.cmbMake.Visibility = 'Collapsed'
            $localState.Controls.btnGetModels.Visibility = 'Collapsed'
            $localState.Controls.spMakeSection.Visibility = 'Collapsed'
            $localState.Controls.spModelFilterSection.Visibility = 'Collapsed'
            $localState.Controls.lstDriverModels.Visibility = 'Collapsed'
            $localState.Controls.spDriverActionButtons.Visibility = 'Collapsed'
            $localState.Controls.lstDriverModels.ItemsSource = $null
            $localState.Data.allDriverModels.Clear()
            $localState.Controls.txtModelFilter.Text = ""
        })

    $State.Controls.btnGetModels.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag

            $selectedMake = $localState.Controls.cmbMake.SelectedItem
            $localState.Controls.txtStatus.Text = "Getting models for $selectedMake..."
            $window.Cursor = [System.Windows.Input.Cursors]::Wait
            $eventSource.IsEnabled = $false
            try {
                # Get previously selected models from the master list ($localState.Data.allDriverModels)
                $previouslySelectedModels = @($localState.Data.allDriverModels | Where-Object { $_.IsSelected })

                # Get newly fetched models for the current make
                $newlyFetchedStandardizedModels = Get-ModelsForMake -SelectedMake $selectedMake -State $localState

                $combinedModelsList = [System.Collections.Generic.List[PSCustomObject]]::new()
                $modelIdentifiersInCombinedList = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

                # Add previously selected models first
                foreach ($item in $previouslySelectedModels) {
                    $combinedModelsList.Add($item)
                    $modelIdentifiersInCombinedList.Add("$($item.Make)::$($item.Model)") | Out-Null
                }

                # Add newly fetched models if they are not already in the list
                $addedNewCount = 0
                foreach ($item in $newlyFetchedStandardizedModels) {
                    if (-not $modelIdentifiersInCombinedList.Contains("$($item.Make)::$($item.Model)")) {
                        $combinedModelsList.Add($item)
                        $modelIdentifiersInCombinedList.Add("$($item.Make)::$($item.Model)") | Out-Null
                        $addedNewCount++
                    }
                }

                # Sort the combined list and update the master list while preserving its List<> type
                $sortedModels = $combinedModelsList | Sort-Object @{Expression = { $_.IsSelected }; Descending = $true }, Make, Model
                $localState.Data.allDriverModels.Clear()
                $sortedModels.ForEach({ $localState.Data.allDriverModels.Add($_) })

                # Update the UI
                $localState.Controls.lstDriverModels.ItemsSource = $localState.Data.allDriverModels
                $localState.Controls.txtModelFilter.Text = ""

                if ($localState.Data.allDriverModels.Count -gt 0) {
                    $localState.Controls.spModelFilterSection.Visibility = 'Visible'
                    $localState.Controls.lstDriverModels.Visibility = 'Visible'
                    $localState.Controls.spDriverActionButtons.Visibility = 'Visible'
                    $statusText = "Displaying $($localState.Data.allDriverModels.Count) models."
                    if ($newlyFetchedStandardizedModels.Count -gt 0 -and $addedNewCount -eq 0 -and $previouslySelectedModels.Count -gt 0) {
                        $statusText = "Fetched $($newlyFetchedStandardizedModels.Count) models for $selectedMake; all were already in the selected list. Displaying $($localState.Data.allDriverModels.Count) total selected models."
                    }
                    elseif ($addedNewCount -gt 0) {
                        $statusText = "Added $addedNewCount new models for $selectedMake. Displaying $($localState.Data.allDriverModels.Count) total models."
                    }
                    elseif ($newlyFetchedStandardizedModels.Count -eq 0 -and $selectedMake -eq 'Lenovo' ) {
                        $statusText = if ($previouslySelectedModels.Count -gt 0) { "No new models found for $selectedMake. Displaying $($previouslySelectedModels.Count) previously selected models." } else { "No models found for $selectedMake." }
                    }
                    elseif ($newlyFetchedStandardizedModels.Count -eq 0) {
                        $statusText = "No new models found for $selectedMake. Displaying $($localState.Data.allDriverModels.Count) previously selected models."
                    }
                    $localState.Controls.txtStatus.Text = $statusText
                }
                else {
                    $localState.Controls.spModelFilterSection.Visibility = 'Collapsed'
                    $localState.Controls.lstDriverModels.Visibility = 'Collapsed'
                    $localState.Controls.spDriverActionButtons.Visibility = 'Collapsed'
                    $localState.Controls.txtStatus.Text = "No models to display for $selectedMake."
                }
            }
            catch {
                $localState.Controls.txtStatus.Text = "Error getting models: $($_.Exception.Message)"
                [System.Windows.MessageBox]::Show("Error getting models: $($_.Exception.Message)", "Error", "OK", "Error")
                if ($null -eq $localState.Data.allDriverModels -or $localState.Data.allDriverModels.Count -eq 0) {
                    $localState.Controls.spModelFilterSection.Visibility = 'Collapsed'
                    $localState.Controls.lstDriverModels.Visibility = 'Collapsed'
                    $localState.Controls.spDriverActionButtons.Visibility = 'Collapsed'
                    $localState.Controls.lstDriverModels.ItemsSource = $null
                    $localState.Controls.txtModelFilter.Text = ""
                }
            }
            finally {
                $window.Cursor = $null
                $eventSource.IsEnabled = $true
            }
        })
    $State.Controls.txtModelFilter.Add_TextChanged({
            param($sourceObject, $textChangedEventArgs)
            $window = [System.Windows.Window]::GetWindow($sourceObject)
            $localState = $window.Tag
            Search-DriverModels -filterText $localState.Controls.txtModelFilter.Text -State $localState
        })
}

Export-ModuleMember -Function *
