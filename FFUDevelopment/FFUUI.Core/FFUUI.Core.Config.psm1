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
        Make                           = $State.Controls.cmbMake.SelectedItem
        MediaType                      = $State.Controls.cmbMediaType.SelectedItem
        Memory                         = [int64]$State.Controls.txtMemory.Text * 1GB
        Model                          = if ($State.Controls.chkDownloadDrivers.IsChecked) {
            $selectedModels = $State.Controls.lstDriverModels.Items | Where-Object { $_.IsSelected }
            if ($selectedModels.Count -ge 1) {
                $selectedModels[0].Model
            }
            else {
                $null
            }
        }
        else {
            $null
        }
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

Export-ModuleMember -Function Get-UIConfig, Set-UIValue