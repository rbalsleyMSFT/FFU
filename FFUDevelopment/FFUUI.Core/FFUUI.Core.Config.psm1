# FFU UI Core Configuration Module
# Contains functions for loading and saving UI configuration.

function Get-UIConfig {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$State
    )
    # Create hash to store configuration
    $config = [ordered]@{
        AllowExternalHardDiskMedia     = $State.Controls.chkAllowExternalHardDiskMedia.IsChecked
        AllowVHDXCaching               = $State.Controls.chkAllowVHDXCaching.IsChecked
        AppListPath                    = $State.Controls.txtAppListJsonPath.Text
        AppsPath                       = $State.Controls.txtApplicationPath.Text
        AppsScriptVariables            = if ($State.Controls.chkDefineAppsScriptVariables.IsChecked) {
            $vars = @{}
            foreach ($item in $State.Data.appsScriptVariablesDataList) {
                $vars[$item.Key] = $item.Value
            }
            if ($vars.Count -gt 0) { $vars } else { $null }
        }
        else { $null }
        BuildUSBDrive                  = $State.Controls.chkBuildUSBDriveEnable.IsChecked
        CleanupAppsISO                 = $State.Controls.chkCleanupAppsISO.IsChecked
        CleanupCaptureISO              = $State.Controls.chkCleanupCaptureISO.IsChecked
        CleanupDeployISO               = $State.Controls.chkCleanupDeployISO.IsChecked
        CleanupDrivers                 = $State.Controls.chkCleanupDrivers.IsChecked
        CompactOS                      = $State.Controls.chkCompactOS.IsChecked
        CompressDownloadedDriversToWim = $State.Controls.chkCompressDriversToWIM.IsChecked
        CopyAutopilot                  = $State.Controls.chkCopyAutopilot.IsChecked
        CopyDrivers                    = $State.Controls.chkCopyDrivers.IsChecked
        CopyOfficeConfigXML            = $State.Controls.chkCopyOfficeConfigXML.IsChecked
        CopyPEDrivers                  = $State.Controls.chkCopyPEDrivers.IsChecked
        CopyPPKG                       = $State.Controls.chkCopyPPKG.IsChecked
        CopyUnattend                   = $State.Controls.chkCopyUnattend.IsChecked
        CreateCaptureMedia             = $State.Controls.chkCreateCaptureMedia.IsChecked
        CreateDeploymentMedia          = $State.Controls.chkCreateDeploymentMedia.IsChecked
        CustomFFUNameTemplate          = $State.Controls.txtCustomFFUNameTemplate.Text
        Disksize                       = [int64]$State.Controls.txtDiskSize.Text * 1GB
        DownloadDrivers                = $State.Controls.chkDownloadDrivers.IsChecked
        DriversFolder                  = $State.Controls.txtDriversFolder.Text
        DriversJsonPath                = $State.Controls.txtDriversJsonPath.Text
        FFUCaptureLocation             = $State.Controls.txtFFUCaptureLocation.Text
        FFUDevelopmentPath             = $State.Controls.txtFFUDevPath.Text
        FFUPrefix                      = $State.Controls.txtVMNamePrefix.Text
        InstallApps                    = $State.Controls.chkInstallApps.IsChecked
        InstallDrivers                 = $State.Controls.chkInstallDrivers.IsChecked
        InstallOffice                  = $State.Controls.chkInstallOffice.IsChecked
        InstallWingetApps              = $State.Controls.chkInstallWingetApps.IsChecked
        ISOPath                        = $State.Controls.txtISOPath.Text
        LogicalSectorSizeBytes         = [int]$State.Controls.cmbLogicalSectorSize.SelectedItem.Content
        # Make                           = $null
        MediaType                      = $State.Controls.cmbMediaType.SelectedItem
        Memory                         = [int64]$State.Controls.txtMemory.Text * 1GB
        # Model                          = if ($State.Controls.chkDownloadDrivers.IsChecked) {
        #     $selectedModels = $State.Controls.lstDriverModels.Items | Where-Object { $_.IsSelected }
        #     if ($selectedModels.Count -ge 1) {
        #         $selectedModels[0].Model
        #     }
        #     else {
        #         $null
        #     }
        # }
        # else {
        #     $null
        # }
        OfficeConfigXMLFile            = $State.Controls.txtOfficeConfigXMLFilePath.Text
        OfficePath                     = $State.Controls.txtOfficePath.Text
        Optimize                       = $State.Controls.chkOptimize.IsChecked
        OptionalFeatures               = $State.Controls.txtOptionalFeatures.Text
        OrchestrationPath              = "$($State.Controls.txtApplicationPath.Text)\Orchestration"
        PEDriversFolder                = $State.Controls.txtPEDriversFolder.Text
        Processors                     = [int]$State.Controls.txtProcessors.Text
        ProductKey                     = $State.Controls.txtProductKey.Text
        PromptExternalHardDiskMedia    = $State.Controls.chkPromptExternalHardDiskMedia.IsChecked
        RemoveApps                     = $State.Controls.chkRemoveApps.IsChecked
        RemoveFFU                      = $State.Controls.chkRemoveFFU.IsChecked
        RemoveUpdates                  = $State.Controls.chkRemoveUpdates.IsChecked
        ShareName                      = $State.Controls.txtShareName.Text
        UpdateADK                      = $State.Controls.chkUpdateADK.IsChecked
        UpdateEdge                     = $State.Controls.chkUpdateEdge.IsChecked
        UpdateLatestCU                 = $State.Controls.chkUpdateLatestCU.IsChecked
        UpdateLatestDefender           = $State.Controls.chkUpdateLatestDefender.IsChecked
        UpdateLatestMicrocode          = $State.Controls.chkUpdateLatestMicrocode.IsChecked
        UpdateLatestMSRT               = $State.Controls.chkUpdateLatestMSRT.IsChecked
        UpdateLatestNet                = $State.Controls.chkUpdateLatestNet.IsChecked
        UpdateOneDrive                 = $State.Controls.chkUpdateOneDrive.IsChecked
        UpdatePreviewCU                = $State.Controls.chkUpdatePreviewCU.IsChecked
        UserAppListPath                = "$($State.Controls.txtApplicationPath.Text)\UserAppList.json"
        USBDriveList                   = @{}
        Username                       = $State.Controls.txtUsername.Text
        Threads                        = [int]$State.Controls.txtThreads.Text
        Verbose                        = $State.Controls.chkVerbose.IsChecked
        VMHostIPAddress                = $State.Controls.txtVMHostIPAddress.Text
        VMLocation                     = $State.Controls.txtVMLocation.Text
        VMSwitchName                   = if ($State.Controls.cmbVMSwitchName.SelectedItem -eq 'Other') {
            $State.Controls.txtCustomVMSwitchName.Text
        }
        else {
            $State.Controls.cmbVMSwitchName.SelectedItem
        }
        WindowsArch                    = $State.Controls.cmbWindowsArch.SelectedItem
        WindowsLang                    = $State.Controls.cmbWindowsLang.SelectedItem
        WindowsRelease                 = [int]$State.Controls.cmbWindowsRelease.SelectedItem.Value
        WindowsSKU                     = $State.Controls.cmbWindowsSKU.SelectedItem
        WindowsVersion                 = $State.Controls.cmbWindowsVersion.SelectedItem
    }

    $State.Controls.lstUSBDrives.Items | Where-Object { $_.IsSelected } | ForEach-Object {
        $config.USBDriveList[$_.Model] = $_.SerialNumber
    }
    
    return $config
}

function Set-UIValue {
    param(
        [string]$ControlName,
        [string]$PropertyName,
        [object]$ConfigObject,
        [string]$ConfigKey,
        [scriptblock]$TransformValue = $null, # Optional scriptblock to transform the value from config
        [psobject]$State # Pass the $State object
    )

    $control = $State.Controls[$ControlName]
    if ($null -eq $control) {
        WriteLog "LoadConfig Error: Control '$ControlName' not found in the state object."
        return
    }

    # Robust check for property existence.
    $keyExists = $false
    if ($ConfigObject -is [System.Management.Automation.PSCustomObject] -and $null -ne $ConfigObject.PSObject.Properties) {
        # Use the Match() method, which returns a collection of matching properties.
        # If the count is greater than 0, the key exists.
        try {
            if (($ConfigObject.PSObject.Properties.Match($ConfigKey)).Count -gt 0) {
                $keyExists = $true
            }
        }
        catch {
            WriteLog "ERROR: Exception while trying to Match key '$ConfigKey' on ConfigObject.PSObject.Properties. Error: $($_.Exception.Message)"
            # $keyExists remains false
        }
    }

    if (-not $keyExists) {
        WriteLog "LoadConfig Info: Key '$ConfigKey' not found in configuration object. Skipping '$ControlName.$PropertyName'."
        return
    }

    $valueFromConfig = $ConfigObject.$ConfigKey
    WriteLog "LoadConfig: Preparing to set '$ControlName.$PropertyName'. Config key: '$ConfigKey', Raw value: '$valueFromConfig'."

    $finalValue = $valueFromConfig
    if ($null -ne $TransformValue) {
        try {
            $finalValue = Invoke-Command -ScriptBlock $TransformValue -ArgumentList $valueFromConfig
            WriteLog "LoadConfig: Transformed value for '$ControlName.$PropertyName' (from key '$ConfigKey') is: '$finalValue'."
        }
        catch {
            WriteLog "LoadConfig Error: Failed to transform value for '$ControlName.$PropertyName' from key '$ConfigKey'. Error: $($_.Exception.Message)"
            return
        }
    }

    try {
        # Handle ComboBox SelectedItem specifically
        if ($control -is [System.Windows.Controls.ComboBox] -and $PropertyName -eq 'SelectedItem') {
            $itemToSelect = $null
            # Iterate through the Items collection of the ComboBox
            foreach ($item in $control.Items) {
                $itemValue = $null
                if ($item -is [System.Windows.Controls.ComboBoxItem]) {
                    $itemValue = $item.Content
                }
                elseif ($item -is [pscustomobject] -and $item.PSObject.Properties['Value']) {
                    $itemValue = $item.Value
                }
                elseif ($item -is [pscustomobject] -and $item.PSObject.Properties['Display']) {
                    # Assuming 'Display' might be used if 'Value' isn't
                    $itemValue = $item.Display
                }
                else {
                    $itemValue = $item # For simple string items or direct object comparison
                }

                # Compare, ensuring types are compatible or converting $finalValue if necessary
                if (($null -ne $itemValue -and $itemValue.ToString() -eq $finalValue.ToString()) -or ($item -eq $finalValue)) {
                    $itemToSelect = $item
                    break
                }
            }

            if ($null -ne $itemToSelect) {
                $control.SelectedItem = $itemToSelect
                WriteLog "LoadConfig: Successfully set '$ControlName.SelectedItem' by finding matching item for value '$finalValue'."
            }
            elseif ($control.IsEditable -and ($finalValue -is [string] -or $finalValue -is [int] -or $finalValue -is [long])) {
                $control.Text = $finalValue.ToString()
                WriteLog "LoadConfig: Set '$ControlName.Text' to '$($finalValue.ToString())' as SelectedItem match failed (editable ComboBox)."
            }
            else {
                $itemsString = ""
                try {
                    # Safer way to get item strings
                    $itemStrings = @()
                    foreach ($cbItem in $control.Items) {
                        if ($null -ne $cbItem) { $itemStrings += $cbItem.ToString() } else { $itemStrings += "[NULL_ITEM]" }
                    }
                    $itemsString = $itemStrings -join "; "
                }
                catch { $itemsString = "Error retrieving item strings." }
                WriteLog "LoadConfig Warning: Could not find or set item matching value '$finalValue' for '$ControlName.SelectedItem'. Current items: [$itemsString]"
            }
        }
        else {
            # For other properties or controls
            $control.$PropertyName = $finalValue
            WriteLog "LoadConfig: Successfully set '$ControlName.$PropertyName' to '$finalValue'."
        }
    }
    catch {
        WriteLog "LoadConfig Error: Failed to set '$ControlName.$PropertyName' to '$finalValue'. Error: $($_.Exception.Message)"
    }
}

function Invoke-LoadConfiguration {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$State
    )
    try {
        $filePath = Invoke-BrowseAction -Type 'OpenFile' -Filter "JSON files (*.json)|*.json|All files (*.*)|*.*" -Title "Load Configuration File"
        if (-not $filePath) {
            WriteLog "Load configuration cancelled by user."
            return
        }

        WriteLog "Loading configuration from: $filePath"
        $configContent = Get-Content -Path $filePath -Raw | ConvertFrom-Json

        if ($null -eq $configContent) {
            WriteLog "LoadConfig Error: configContent is null after parsing $filePath. File might be empty or malformed."
            [System.Windows.MessageBox]::Show("Failed to parse the configuration file. It might be empty or not valid JSON.", "Load Error", "OK", "Error")
            return
        }
        WriteLog "LoadConfig: Successfully parsed config file. Top-level keys: $($configContent.PSObject.Properties.Name -join ', ')"

        # Apply the configuration to the UI
        Update-UIFromConfig -ConfigContent $configContent -State $State
    }
    catch {
        WriteLog "LoadConfig FATAL Error: $($_.Exception.ToString())"
        [System.Windows.MessageBox]::Show("Error loading config file:`n$($_.Exception.Message)", "Error", "OK", "Error")
    }
}

function Update-UIFromConfig {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$ConfigContent,
        [Parameter(Mandatory = $true)]
        [psobject]$State
    )

    WriteLog "Applying loaded configuration to the UI."

    # Update Build tab values
    Set-UIValue -ControlName 'txtFFUDevPath' -PropertyName 'Text' -ConfigObject $ConfigContent -ConfigKey 'FFUDevelopmentPath' -State $State
    Set-UIValue -ControlName 'txtCustomFFUNameTemplate' -PropertyName 'Text' -ConfigObject $ConfigContent -ConfigKey 'CustomFFUNameTemplate' -State $State
    Set-UIValue -ControlName 'txtFFUCaptureLocation' -PropertyName 'Text' -ConfigObject $ConfigContent -ConfigKey 'FFUCaptureLocation' -State $State
    Set-UIValue -ControlName 'txtShareName' -PropertyName 'Text' -ConfigObject $ConfigContent -ConfigKey 'ShareName' -State $State
    Set-UIValue -ControlName 'txtUsername' -PropertyName 'Text' -ConfigObject $ConfigContent -ConfigKey 'Username' -State $State
    Set-UIValue -ControlName 'txtThreads' -PropertyName 'Text' -ConfigObject $ConfigContent -ConfigKey 'Threads' -State $State
    Set-UIValue -ControlName 'chkBuildUSBDriveEnable' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'BuildUSBDrive' -State $State
    Set-UIValue -ControlName 'chkCompactOS' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'CompactOS' -State $State
    Set-UIValue -ControlName 'chkUpdateADK' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'UpdateADK' -State $State
    Set-UIValue -ControlName 'chkOptimize' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'Optimize' -State $State
    Set-UIValue -ControlName 'chkAllowVHDXCaching' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'AllowVHDXCaching' -State $State
    Set-UIValue -ControlName 'chkAllowExternalHardDiskMedia' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'AllowExternalHardDiskMedia' -State $State
    Set-UIValue -ControlName 'chkPromptExternalHardDiskMedia' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'PromptExternalHardDiskMedia' -State $State
    Set-UIValue -ControlName 'chkCreateCaptureMedia' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'CreateCaptureMedia' -State $State
    Set-UIValue -ControlName 'chkCreateDeploymentMedia' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'CreateDeploymentMedia' -State $State
    Set-UIValue -ControlName 'chkVerbose' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'Verbose' -State $State

    # USB Drive Modification group (Build Tab)
    Set-UIValue -ControlName 'chkCopyAutopilot' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'CopyAutopilot' -State $State
    Set-UIValue -ControlName 'chkCopyUnattend' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'CopyUnattend' -State $State
    Set-UIValue -ControlName 'chkCopyPPKG' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'CopyPPKG' -State $State

    # Post Build Cleanup group (Build Tab)
    Set-UIValue -ControlName 'chkCleanupAppsISO' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'CleanupAppsISO' -State $State
    Set-UIValue -ControlName 'chkCleanupCaptureISO' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'CleanupCaptureISO' -State $State
    Set-UIValue -ControlName 'chkCleanupDeployISO' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'CleanupDeployISO' -State $State
    Set-UIValue -ControlName 'chkCleanupDrivers' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'CleanupDrivers' -State $State
    Set-UIValue -ControlName 'chkRemoveFFU' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'RemoveFFU' -State $State
    Set-UIValue -ControlName 'chkRemoveApps' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'RemoveApps' -State $State
    Set-UIValue -ControlName 'chkRemoveUpdates' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'RemoveUpdates' -State $State

    # Hyper-V Settings
    Set-UIValue -ControlName 'cmbVMSwitchName' -PropertyName 'SelectedItem' -ConfigObject $ConfigContent -ConfigKey 'VMSwitchName' -State $State
    Set-UIValue -ControlName 'txtVMHostIPAddress' -PropertyName 'Text' -ConfigObject $ConfigContent -ConfigKey 'VMHostIPAddress' -State $State
    Set-UIValue -ControlName 'txtDiskSize' -PropertyName 'Text' -ConfigObject $ConfigContent -ConfigKey 'Disksize' -TransformValue { param($val) $val / 1GB } -State $State
    Set-UIValue -ControlName 'txtMemory' -PropertyName 'Text' -ConfigObject $ConfigContent -ConfigKey 'Memory' -TransformValue { param($val) $val / 1GB } -State $State
    Set-UIValue -ControlName 'txtProcessors' -PropertyName 'Text' -ConfigObject $ConfigContent -ConfigKey 'Processors' -State $State
    Set-UIValue -ControlName 'txtVMLocation' -PropertyName 'Text' -ConfigObject $ConfigContent -ConfigKey 'VMLocation' -State $State
    Set-UIValue -ControlName 'txtVMNamePrefix' -PropertyName 'Text' -ConfigObject $ConfigContent -ConfigKey 'FFUPrefix' -State $State
    Set-UIValue -ControlName 'cmbLogicalSectorSize' -PropertyName 'SelectedItem' -ConfigObject $ConfigContent -ConfigKey 'LogicalSectorSizeBytes' -TransformValue { param($val) $val.ToString() } -State $State

    # Windows Settings
    Set-UIValue -ControlName 'txtISOPath' -PropertyName 'Text' -ConfigObject $ConfigContent -ConfigKey 'ISOPath' -State $State
    
    # Special handling for Windows Release and SKU due to value collision (e.g., 2019 for Server and LTSC)
    if (($null -ne $ConfigContent.PSObject.Properties.Item('WindowsRelease')) -and ($null -ne $ConfigContent.PSObject.Properties.Item('WindowsSKU'))) {
        $configReleaseValue = $ConfigContent.WindowsRelease
        $configSkuValue = $ConfigContent.WindowsSKU
        WriteLog "LoadConfig: Handling Windows Release/SKU selection. Release: '$configReleaseValue', SKU: '$configSkuValue'."

        $releaseCombo = $State.Controls.cmbWindowsRelease
        # The items in the combobox are PSCustomObjects with Display and Value properties
        $possibleReleases = $releaseCombo.Items | Where-Object { $_.Value -eq $configReleaseValue }

        $releaseToSelect = $null
        if ($possibleReleases.Count -gt 1) {
            WriteLog "LoadConfig: Ambiguous release value '$configReleaseValue' found. Using SKU to disambiguate."
            if ($configSkuValue -like '*LTS*') {
                $releaseToSelect = $possibleReleases | Where-Object { $_.Display -like '*LTS*' } | Select-Object -First 1
                WriteLog "LoadConfig: SKU contains 'LTS'. Selecting LTSC-related release: '$($releaseToSelect.Display)'."
            }
            else {
                $releaseToSelect = $possibleReleases | Where-Object { $_.Display -notlike '*LTS*' } | Select-Object -First 1
                WriteLog "LoadConfig: SKU does not contain 'LTS'. Selecting non-LTSC (Server) release: '$($releaseToSelect.Display)'."
            }
        }
        else {
            $releaseToSelect = $possibleReleases | Select-Object -First 1
            if ($null -ne $releaseToSelect) {
                WriteLog "LoadConfig: Found unique release match: '$($releaseToSelect.Display)'."
            }
        }

        if ($null -ne $releaseToSelect) {
            $releaseCombo.SelectedItem = $releaseToSelect
        }
        else {
            WriteLog "LoadConfig: Could not determine a specific Windows Release to select for value '$configReleaseValue'. Skipping."
        }
    }
    else {
        # Fallback to individual setting if only one key exists
        WriteLog "LoadConfig: WindowsRelease or WindowsSKU key not found in config. Falling back to simple assignment for WindowsRelease."
        Set-UIValue -ControlName 'cmbWindowsRelease' -PropertyName 'SelectedItem' -ConfigObject $ConfigContent -ConfigKey 'WindowsRelease' -State $State
    }

    Set-UIValue -ControlName 'cmbWindowsVersion' -PropertyName 'SelectedItem' -ConfigObject $ConfigContent -ConfigKey 'WindowsVersion' -State $State
    Set-UIValue -ControlName 'cmbWindowsArch' -PropertyName 'SelectedItem' -ConfigObject $ConfigContent -ConfigKey 'WindowsArch' -State $State
    Set-UIValue -ControlName 'cmbWindowsLang' -PropertyName 'SelectedItem' -ConfigObject $ConfigContent -ConfigKey 'WindowsLang' -State $State
    Set-UIValue -ControlName 'cmbWindowsSKU' -PropertyName 'SelectedItem' -ConfigObject $ConfigContent -ConfigKey 'WindowsSKU' -State $State
    Set-UIValue -ControlName 'cmbMediaType' -PropertyName 'SelectedItem' -ConfigObject $ConfigContent -ConfigKey 'MediaType' -State $State
    Set-UIValue -ControlName 'txtProductKey' -PropertyName 'Text' -ConfigObject $ConfigContent -ConfigKey 'ProductKey' -State $State
    Set-UIValue -ControlName 'txtOptionalFeatures' -PropertyName 'Text' -ConfigObject $ConfigContent -ConfigKey 'OptionalFeatures' -State $State

    # Update Optional Features checkboxes based on the loaded text
    $loadedFeaturesString = $State.Controls.txtOptionalFeatures.Text
    if (-not [string]::IsNullOrWhiteSpace($loadedFeaturesString)) {
        $loadedFeaturesArray = $loadedFeaturesString.Split(';')
        WriteLog "LoadConfig: Updating Optional Features checkboxes. Loaded features: $($loadedFeaturesArray -join ', ')"
        foreach ($featureEntry in $State.Controls.featureCheckBoxes.GetEnumerator()) {
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
        foreach ($featureEntry in $State.Controls.featureCheckBoxes.GetEnumerator()) {
            $featureEntry.Value.IsChecked = $false
        }
    }

    # M365 Apps/Office tab
    Set-UIValue -ControlName 'chkInstallOffice' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'InstallOffice' -State $State
    Set-UIValue -ControlName 'txtOfficePath' -PropertyName 'Text' -ConfigObject $ConfigContent -ConfigKey 'OfficePath' -State $State
    Set-UIValue -ControlName 'chkCopyOfficeConfigXML' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'CopyOfficeConfigXML' -State $State
    Set-UIValue -ControlName 'txtOfficeConfigXMLFilePath' -PropertyName 'Text' -ConfigObject $ConfigContent -ConfigKey 'OfficeConfigXMLFile' -State $State

    # Drivers tab
    Set-UIValue -ControlName 'chkInstallDrivers' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'InstallDrivers' -State $State
    Set-UIValue -ControlName 'chkDownloadDrivers' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'DownloadDrivers' -State $State
    Set-UIValue -ControlName 'chkCopyDrivers' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'CopyDrivers' -State $State
    # Set-UIValue -ControlName 'cmbMake' -PropertyName 'SelectedItem' -ConfigObject $ConfigContent -ConfigKey 'Make' -State $State
    Set-UIValue -ControlName 'txtDriversFolder' -PropertyName 'Text' -ConfigObject $ConfigContent -ConfigKey 'DriversFolder' -State $State
    Set-UIValue -ControlName 'txtPEDriversFolder' -PropertyName 'Text' -ConfigObject $ConfigContent -ConfigKey 'PEDriversFolder' -State $State
    Set-UIValue -ControlName 'txtDriversJsonPath' -PropertyName 'Text' -ConfigObject $ConfigContent -ConfigKey 'DriversJsonPath' -State $State
    Set-UIValue -ControlName 'chkCopyPEDrivers' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'CopyPEDrivers' -State $State
    Set-UIValue -ControlName 'chkCompressDriversToWIM' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'CompressDownloadedDriversToWim' -State $State

    # Updates tab
    Set-UIValue -ControlName 'chkUpdateLatestCU' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'UpdateLatestCU' -State $State
    Set-UIValue -ControlName 'chkUpdateLatestNet' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'UpdateLatestNet' -State $State
    Set-UIValue -ControlName 'chkUpdateLatestDefender' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'UpdateLatestDefender' -State $State
    Set-UIValue -ControlName 'chkUpdateEdge' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'UpdateEdge' -State $State
    Set-UIValue -ControlName 'chkUpdateOneDrive' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'UpdateOneDrive' -State $State
    Set-UIValue -ControlName 'chkUpdateLatestMSRT' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'UpdateLatestMSRT' -State $State
    Set-UIValue -ControlName 'chkUpdateLatestMicrocode' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'UpdateLatestMicrocode' -State $State
    Set-UIValue -ControlName 'chkUpdatePreviewCU' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'UpdatePreviewCU' -State $State

    # Applications tab
    Set-UIValue -ControlName 'chkInstallApps' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'InstallApps' -State $State
    Set-UIValue -ControlName 'chkInstallWingetApps' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'InstallWingetApps' -State $State
    Set-UIValue -ControlName 'chkBringYourOwnApps' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'BringYourOwnApps' -State $State
    Set-UIValue -ControlName 'txtApplicationPath' -PropertyName 'Text' -ConfigObject $ConfigContent -ConfigKey 'AppsPath' -State $State
    Set-UIValue -ControlName 'txtAppListJsonPath' -PropertyName 'Text' -ConfigObject $ConfigContent -ConfigKey 'AppListPath' -State $State

    # Handle AppsScriptVariables
    $appsScriptVarsKeyExists = $false
    if ($ConfigContent -is [System.Management.Automation.PSCustomObject] -and $null -ne $ConfigContent.PSObject.Properties) {
        try {
            if (($ConfigContent.PSObject.Properties.Match('AppsScriptVariables')).Count -gt 0) {
                $appsScriptVarsKeyExists = $true
            }
        }
        catch { WriteLog "ERROR: Exception while trying to Match key 'AppsScriptVariables'. Error: $($_.Exception.Message)" }
    }

    $lstAppsScriptVars = $State.Controls.lstAppsScriptVariables
    $chkDefineAppsScriptVars = $State.Controls.chkDefineAppsScriptVariables
    $appsScriptVarsPanel = $State.Controls.appsScriptVariablesPanel
    $State.Data.appsScriptVariablesDataList.Clear()

    if ($appsScriptVarsKeyExists -and $null -ne $ConfigContent.AppsScriptVariables -and $ConfigContent.AppsScriptVariables -is [System.Management.Automation.PSCustomObject]) {
        WriteLog "LoadConfig: Processing AppsScriptVariables from config."
        $loadedVars = $ConfigContent.AppsScriptVariables
        $hasVars = $false
        foreach ($prop in $loadedVars.PSObject.Properties) {
            $State.Data.appsScriptVariablesDataList.Add([PSCustomObject]@{ IsSelected = $false; Key = $prop.Name; Value = $prop.Value })
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
    elseif ($appsScriptVarsKeyExists -and $null -ne $ConfigContent.AppsScriptVariables -and $ConfigContent.AppsScriptVariables -is [hashtable]) {
        # Handle if it's already a hashtable (e.g., from older config or direct creation)
        WriteLog "LoadConfig: Processing AppsScriptVariables (Hashtable) from config."
        $loadedVars = $ConfigContent.AppsScriptVariables
        $hasVars = $false
        foreach ($keyName in $loadedVars.Keys) {
            $State.Data.appsScriptVariablesDataList.Add([PSCustomObject]@{ IsSelected = $false; Key = $keyName; Value = $loadedVars[$keyName] })
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
    $lstAppsScriptVars.ItemsSource = $State.Data.appsScriptVariablesDataList.ToArray()
    # Update the header checkbox state
    if ($null -ne $State.Controls.chkSelectAllAppsScriptVariables) {
        Update-SelectAllHeaderCheckBoxState -ListView $lstAppsScriptVars -HeaderCheckBox $State.Controls.chkSelectAllAppsScriptVariables
    }

    # Update USB Drive selection if present in config
    $usbDriveListKeyExists = $false
    if ($ConfigContent -is [System.Management.Automation.PSCustomObject] -and $null -ne $ConfigContent.PSObject.Properties) {
        try {
            if (($ConfigContent.PSObject.Properties.Match('USBDriveList')).Count -gt 0) {
                $usbDriveListKeyExists = $true
            }
        }
        catch {
            WriteLog "ERROR: Exception while trying to Match key 'USBDriveList' on ConfigContent.PSObject.Properties. Error: $($_.Exception.Message)"
        }
    }

    if ($usbDriveListKeyExists -and $null -ne $ConfigContent.USBDriveList) {
        WriteLog "LoadConfig: Processing USBDriveList from config."
        # First click the Check USB Drives button to populate the list
        $State.Controls.btnCheckUSBDrives.RaiseEvent(
            [System.Windows.RoutedEventArgs]::new(
                [System.Windows.Controls.Button]::ClickEvent
            )
        )

        # Then select the drives that match the saved configuration
        foreach ($item in $State.Controls.lstUSBDrives.Items) {
            $propertyName = $item.Model
            $propertyExists = $false
            $propertyValue = $null

            # Ensure USBDriveList is a PSCustomObject before trying to access its properties dynamically
            if ($null -ne $ConfigContent.USBDriveList -and $ConfigContent.USBDriveList -is [System.Management.Automation.PSCustomObject]) {
                # Check if the property exists on the USBDriveList object
                if ($ConfigContent.USBDriveList.PSObject.Properties.Match($propertyName).Count -gt 0) {
                    $propertyExists = $true
                    # Access the value dynamically
                    $propertyValue = $ConfigContent.USBDriveList.$($propertyName)
                }
            }

            if ($propertyExists -and ($propertyValue -eq $item.SerialNumber)) {
                WriteLog "LoadConfig: Selecting USB Drive Model '$($item.Model)' with Serial '$($item.SerialNumber)'."
                $item.IsSelected = $true
            }
            else {
                if (-not $propertyExists -and ($null -ne $ConfigContent.USBDriveList)) {
                    WriteLog "LoadConfig: Property '$($propertyName)' not found on USBDriveList for item Model '$($item.Model)'."
                }
                $item.IsSelected = $false # Ensure others are deselected if not in config or value mismatch
            }
        }
        $State.Controls.lstUSBDrives.Items.Refresh()

        # Update the Select All header checkbox state
        $headerChk = $State.Controls.chkSelectAllUSBDrivesHeader
        if ($null -ne $headerChk) {
            Update-SelectAllHeaderCheckBoxState -ListView $State.Controls.lstUSBDrives -HeaderCheckBox $headerChk
        }
        WriteLog "LoadConfig: USBDriveList processing complete."
    }
    else {
        WriteLog "LoadConfig Info: Key 'USBDriveList' not found or is null in configuration file. Skipping USB drive selection."
    }

    # If BuildUSBDrive is enabled and USBDriveList was present and not empty in the config,
    # ensure "Select Specific USB Drives" is checked to show the list.
    $shouldAutoCheckSpecificDrives = $false
    if ($State.Controls.chkBuildUSBDriveEnable.IsChecked -and $usbDriveListKeyExists -and ($null -ne $ConfigContent.USBDriveList)) {
        if ($ConfigContent.USBDriveList -is [System.Management.Automation.PSCustomObject]) {
            if ($ConfigContent.USBDriveList.PSObject.Properties.Count -gt 0) {
                $shouldAutoCheckSpecificDrives = $true
            }
        }
        elseif ($ConfigContent.USBDriveList -is [hashtable]) {
            # Fallback for older configs
            if ($ConfigContent.USBDriveList.Keys.Count -gt 0) {
                $shouldAutoCheckSpecificDrives = $true
            }
        }
    }

    if ($shouldAutoCheckSpecificDrives) {
        WriteLog "LoadConfig: Auto-checking 'Select Specific USB Drives' due to pre-selected USB drives in config."
        $State.Controls.chkSelectSpecificUSBDrives.IsChecked = $true
    }
    else {
        WriteLog "LoadConfig: Condition to auto-check 'Select Specific USB Drives' was NOT met."
    }
    WriteLog "LoadConfig: Configuration loading process finished."
}

function Invoke-SaveConfiguration {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$State
    )
    try {
        $config = Get-UIConfig -State $State
        $defaultConfigPath = Join-Path $config.FFUDevelopmentPath "config"
        if (-not (Test-Path $defaultConfigPath)) {
            New-Item -Path $defaultConfigPath -ItemType Directory -Force | Out-Null
        }
        
        $savePath = Invoke-BrowseAction -Type 'SaveFile' `
            -Title "Save Configuration File" `
            -Filter "JSON files (*.json)|*.json|All files (*.*)|*.*" `
            -InitialDirectory $defaultConfigPath `
            -FileName "FFUConfig.json" `
            -DefaultExt ".json"

        if ($savePath) {
            $config | ConvertTo-Json -Depth 10 | Set-Content -Path $savePath -Encoding UTF8
            [System.Windows.MessageBox]::Show("Configuration file saved to:`n$savePath", "Success", "OK", "Information")
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Error saving config file:`n$($_.Exception.Message)", "Error", "OK", "Error")
    }
}

Export-ModuleMember -Function *