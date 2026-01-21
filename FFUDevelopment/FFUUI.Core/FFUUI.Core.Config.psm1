<#
.SYNOPSIS
    Contains functions for loading and saving UI configuration.
.DESCRIPTION
    This module provides the core logic for loading and saving the UI configuration. It includes functions to gather settings from the various UI controls, save them to a JSON file, and load settings from a JSON file to populate the UI. This allows users to persist their build configurations and easily switch between different setups.
#>

# Import config migration module for version handling
$migrationModulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Modules\FFU.ConfigMigration'
if (Test-Path $migrationModulePath) {
    Import-Module (Join-Path $migrationModulePath 'FFU.ConfigMigration.psd1') -Force -ErrorAction SilentlyContinue
}
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
        # Convert hypervisor dropdown selection to parameter value
        HypervisorType                 = switch ($State.Controls.cmbHypervisorType.SelectedIndex) {
            0 { 'HyperV' }
            1 { 'VMware' }
            2 { 'Auto' }
            default { 'HyperV' }
        }
        ShowVMConsole                  = $State.Controls.chkShowVMConsole.IsChecked
        ForceVMwareDriverDownload      = $State.Controls.chkForceVMwareDrivers.IsChecked
        # VMware network settings - extract Tag value from selected ComboBoxItem
        VMwareNetworkType              = if ($null -ne $State.Controls.cmbVMwareNetworkType -and $null -ne $State.Controls.cmbVMwareNetworkType.SelectedItem) {
            $selectedItem = $State.Controls.cmbVMwareNetworkType.SelectedItem
            if ($selectedItem -is [System.Windows.Controls.ComboBoxItem]) {
                $selectedItem.Tag
            } else {
                'nat'  # default
            }
        } else { 'nat' }
        VMwareNicType                  = if ($null -ne $State.Controls.cmbVMwareNicType -and $null -ne $State.Controls.cmbVMwareNicType.SelectedItem) {
            $selectedItem = $State.Controls.cmbVMwareNicType.SelectedItem
            if ($selectedItem -is [System.Windows.Controls.ComboBoxItem]) {
                $selectedItem.Tag
            } else {
                'e1000e'  # default
            }
        } else { 'e1000e' }
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
        UseDriversAsPEDrivers          = $State.Controls.chkUseDriversAsPEDrivers.IsChecked
        CopyPPKG                       = $State.Controls.chkCopyPPKG.IsChecked
        CopyUnattend                   = $State.Controls.chkCopyUnattend.IsChecked
        CopyAdditionalFFUFiles         = $State.Controls.chkCopyAdditionalFFUFiles.IsChecked
        CreateCaptureMedia             = $State.Controls.chkCreateCaptureMedia.IsChecked
        CreateDeploymentMedia          = $State.Controls.chkCreateDeploymentMedia.IsChecked
        InjectUnattend                 = $State.Controls.chkInjectUnattend.IsChecked
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
        OptionalFeatures               = (($State.Controls.featureCheckBoxes.GetEnumerator() | Where-Object { $_.Value.IsChecked } | ForEach-Object { $_.Key } | Sort-Object) -join ';')
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
        IncludePreviewUpdates          = $State.Controls.chkIncludePreviewUpdates.IsChecked
        UserAppListPath                = "$($State.Controls.txtApplicationPath.Text)\UserAppList.json"
        USBDriveList                   = @{}
        Username                       = $State.Controls.txtUsername.Text
        Threads                        = [int]$State.Controls.txtThreads.Text
        MaxUSBDrives                   = [int]$State.Controls.txtMaxUSBDrives.Text
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

    # Add VMShutdownTimeoutMinutes from UI control
    if ($null -ne $State.Controls.txtVMShutdownTimeout) {
        $timeoutText = $State.Controls.txtVMShutdownTimeout.Text
        if (-not [string]::IsNullOrWhiteSpace($timeoutText)) {
            $timeout = 0
            if ([int]::TryParse($timeoutText, [ref]$timeout) -and $timeout -ge 5 -and $timeout -le 120) {
                $config.VMShutdownTimeoutMinutes = $timeout
            }
        }
    }

    $State.Controls.lstUSBDrives.Items | Where-Object { $_.IsSelected } | ForEach-Object {
        $config.USBDriveList[$_.Model] = $_.SerialNumber
    }

    # Additional FFU file selections
    $config.AdditionalFFUFiles = @()
    if ($State.Controls.chkCopyAdditionalFFUFiles.IsChecked) {
        $config.AdditionalFFUFiles = @(
            $State.Controls.lstAdditionalFFUs.Items |
                Where-Object { $_.IsSelected } |
                ForEach-Object { $_.FullName }
        )
    }

    $config
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

    # Skip empty/null values for Text properties to preserve UI defaults
    # This allows config files to use empty strings for paths that should use default values
    if ($PropertyName -eq 'Text' -and [string]::IsNullOrWhiteSpace($valueFromConfig)) {
        WriteLog "LoadConfig Info: Skipping '$ControlName.$PropertyName' because config value is empty (preserving UI default)."
        return
    }

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
        $raw = $null
        try {
            $raw = Get-Content -Path $filePath -Raw -ErrorAction Stop
        }
        catch {
            WriteLog "LoadConfig Error: Failed reading file $filePath : $($_.Exception.Message)"
            [System.Windows.MessageBox]::Show("Failed to read the configuration file.`n$($_.Exception.Message)", "Load Error", "OK", "Error")
            return
        }
        if ([string]::IsNullOrWhiteSpace($raw)) {
            WriteLog "LoadConfig Error: File $filePath is empty."
            [System.Windows.MessageBox]::Show("The selected configuration file is empty.", "Load Error", "OK", "Error")
            return
        }
        $configContent = $null
        try {
            $configContent = $raw | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            WriteLog "LoadConfig Error: JSON parse failure for $filePath : $($_.Exception.Message)"
            [System.Windows.MessageBox]::Show("Failed to parse the configuration file (invalid JSON).`n$($_.Exception.Message)", "Load Error", "OK", "Error")
            return
        }
        if ($null -eq $configContent) {
            WriteLog "LoadConfig Error: Parsed config object is null after $filePath."
            [System.Windows.MessageBox]::Show("Parsed configuration object was null.", "Load Error", "OK", "Error")
            return
        }
        WriteLog "LoadConfig: Successfully parsed config file. Top-level keys: $($configContent.PSObject.Properties.Name -join ', ')"
        Update-UIFromConfig -ConfigContent $configContent -State $State
        $State.Data.lastConfigFilePath = $filePath
        Import-ConfigSupplementalAssets -ConfigContent $configContent -State $State -ShowWarnings:$true
    }
    catch {
        WriteLog "LoadConfig FATAL Error: $($_.Exception.ToString())"
        [System.Windows.MessageBox]::Show("Error loading config file:`n$($_.Exception.Message)", "Error", "OK", "Error")
    }
}

function Select-VMSwitchFromConfig {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$State,
        [Parameter(Mandatory = $true)]
        [psobject]$ConfigContent
    )

    # Select VM switch based on configuration; fall back to 'Other' with custom name.
    $combo = $State.Controls.cmbVMSwitchName
    if ($null -eq $combo) {
        WriteLog "LoadConfig Error: 'cmbVMSwitchName' control not found."
        return
    }

    $configSwitch = $ConfigContent.VMSwitchName
    if ($null -eq $configSwitch -or [string]::IsNullOrWhiteSpace($configSwitch)) {
        WriteLog "LoadConfig Info: VMSwitchName in config was empty or null. Leaving selection unchanged."
        return
    }

    $itemFound = $false
    foreach ($item in $combo.Items) {
        if ($null -ne $item -and $item.ToString().Equals($configSwitch, [System.StringComparison]::OrdinalIgnoreCase)) {
            $itemFound = $true
            break
        }
    }

    if ($itemFound) {
        $combo.SelectedItem = ($combo.Items | Where-Object { $_.ToString().Equals($configSwitch, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
        $State.Controls.txtCustomVMSwitchName.Visibility = 'Collapsed'
        WriteLog "LoadConfig: Selected existing VM switch '$configSwitch'."
    }
    else {
        # Ensure 'Other' exists
        $otherExists = $false
        foreach ($item in $combo.Items) {
            if ($null -ne $item -and $item.ToString() -eq 'Other') { $otherExists = $true; break }
        }
        if (-not $otherExists) { $combo.Items.Add('Other') | Out-Null }

        # Select 'Other' and populate custom name
        $combo.SelectedItem = 'Other'
        $State.Controls.txtCustomVMSwitchName.Visibility = 'Visible'
        $State.Controls.txtCustomVMSwitchName.Text = $configSwitch
        $State.Data.customVMSwitchName = $configSwitch
        $State.Data.customVMHostIP = $ConfigContent.VMHostIPAddress
        WriteLog "LoadConfig: VMSwitchName '$configSwitch' not found. Selected 'Other' and populated custom VM Switch Name textbox."
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
    Set-UIValue -ControlName 'txtMaxUSBDrives' -PropertyName 'Text' -ConfigObject $ConfigContent -ConfigKey 'MaxUSBDrives' -State $State
    Set-UIValue -ControlName 'chkBuildUSBDriveEnable' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'BuildUSBDrive' -State $State
    Set-UIValue -ControlName 'chkCompactOS' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'CompactOS' -State $State
    Set-UIValue -ControlName 'chkUpdateADK' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'UpdateADK' -State $State
    Set-UIValue -ControlName 'chkOptimize' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'Optimize' -State $State
    Set-UIValue -ControlName 'chkAllowVHDXCaching' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'AllowVHDXCaching' -State $State
    Set-UIValue -ControlName 'chkAllowExternalHardDiskMedia' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'AllowExternalHardDiskMedia' -State $State
    Set-UIValue -ControlName 'chkPromptExternalHardDiskMedia' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'PromptExternalHardDiskMedia' -State $State
    Set-UIValue -ControlName 'chkCopyAdditionalFFUFiles' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'CopyAdditionalFFUFiles' -State $State
    Set-UIValue -ControlName 'chkCreateCaptureMedia' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'CreateCaptureMedia' -State $State
    Set-UIValue -ControlName 'chkCreateDeploymentMedia' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'CreateDeploymentMedia' -State $State
    Set-UIValue -ControlName 'chkInjectUnattend' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'InjectUnattend' -State $State
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

    # VM/Hypervisor Settings
    # Load HypervisorType selection
    if ($ConfigContent.PSObject.Properties.Match('HypervisorType').Count -gt 0) {
        $hypervisorType = $ConfigContent.HypervisorType
        $hypervisorIndex = switch ($hypervisorType) {
            'HyperV' { 0 }
            'VMware' { 1 }
            'Auto' { 2 }
            default { 0 }
        }
        if ($null -ne $State.Controls.cmbHypervisorType) {
            $State.Controls.cmbHypervisorType.SelectedIndex = $hypervisorIndex
            WriteLog "LoadConfig: Set HypervisorType to '$hypervisorType' (index $hypervisorIndex)."
        }
    }
    Set-UIValue -ControlName 'chkShowVMConsole' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'ShowVMConsole' -State $State
    Set-UIValue -ControlName 'chkForceVMwareDrivers' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'ForceVMwareDriverDownload' -State $State

    # Load VMware Network Type selection (nat/bridged/hostonly)
    if ($ConfigContent.PSObject.Properties.Match('VMwareNetworkType').Count -gt 0) {
        $vmwareNetworkType = $ConfigContent.VMwareNetworkType
        if ($null -ne $State.Controls.cmbVMwareNetworkType -and -not [string]::IsNullOrWhiteSpace($vmwareNetworkType)) {
            # Find the ComboBoxItem with matching Tag value
            $itemToSelect = $null
            foreach ($item in $State.Controls.cmbVMwareNetworkType.Items) {
                if ($item -is [System.Windows.Controls.ComboBoxItem] -and $item.Tag -eq $vmwareNetworkType) {
                    $itemToSelect = $item
                    break
                }
            }
            if ($null -ne $itemToSelect) {
                $State.Controls.cmbVMwareNetworkType.SelectedItem = $itemToSelect
                WriteLog "LoadConfig: Set VMwareNetworkType to '$vmwareNetworkType'."
            }
        }
    }

    # Load VMware NIC Type selection (e1000e/vmxnet3/e1000)
    if ($ConfigContent.PSObject.Properties.Match('VMwareNicType').Count -gt 0) {
        $vmwareNicType = $ConfigContent.VMwareNicType
        if ($null -ne $State.Controls.cmbVMwareNicType -and -not [string]::IsNullOrWhiteSpace($vmwareNicType)) {
            # Find the ComboBoxItem with matching Tag value
            $itemToSelect = $null
            foreach ($item in $State.Controls.cmbVMwareNicType.Items) {
                if ($item -is [System.Windows.Controls.ComboBoxItem] -and $item.Tag -eq $vmwareNicType) {
                    $itemToSelect = $item
                    break
                }
            }
            if ($null -ne $itemToSelect) {
                $State.Controls.cmbVMwareNicType.SelectedItem = $itemToSelect
                WriteLog "LoadConfig: Set VMwareNicType to '$vmwareNicType'."
            }
        }
    }

    Select-VMSwitchFromConfig -State $State -ConfigContent $ConfigContent
    Set-UIValue -ControlName 'txtVMHostIPAddress' -PropertyName 'Text' -ConfigObject $ConfigContent -ConfigKey 'VMHostIPAddress' -State $State
    Set-UIValue -ControlName 'txtDiskSize' -PropertyName 'Text' -ConfigObject $ConfigContent -ConfigKey 'Disksize' -TransformValue { param($val) $val / 1GB } -State $State
    Set-UIValue -ControlName 'txtMemory' -PropertyName 'Text' -ConfigObject $ConfigContent -ConfigKey 'Memory' -TransformValue { param($val) $val / 1GB } -State $State
    Set-UIValue -ControlName 'txtProcessors' -PropertyName 'Text' -ConfigObject $ConfigContent -ConfigKey 'Processors' -State $State
    Set-UIValue -ControlName 'txtVMLocation' -PropertyName 'Text' -ConfigObject $ConfigContent -ConfigKey 'VMLocation' -State $State
    Set-UIValue -ControlName 'txtVMNamePrefix' -PropertyName 'Text' -ConfigObject $ConfigContent -ConfigKey 'FFUPrefix' -State $State
    Set-UIValue -ControlName 'cmbLogicalSectorSize' -PropertyName 'SelectedItem' -ConfigObject $ConfigContent -ConfigKey 'LogicalSectorSizeBytes' -TransformValue { param($val) $val.ToString() } -State $State

    # Load VMShutdownTimeoutMinutes if present
    if ($ConfigContent.VMShutdownTimeoutMinutes -and $null -ne $State.Controls.txtVMShutdownTimeout) {
        $State.Controls.txtVMShutdownTimeout.Text = $ConfigContent.VMShutdownTimeoutMinutes.ToString()
        WriteLog "LoadConfig: Set VMShutdownTimeoutMinutes to $($ConfigContent.VMShutdownTimeoutMinutes)."
    }

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
   
    # Update Optional Features checkboxes
    $loadedFeaturesString = $ConfigContent.OptionalFeatures
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
    Set-UIValue -ControlName 'chkUseDriversAsPEDrivers' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'UseDriversAsPEDrivers' -State $State
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
    Set-UIValue -ControlName 'chkIncludePreviewUpdates' -PropertyName 'IsChecked' -ConfigObject $ConfigContent -ConfigKey 'IncludePreviewUpdates' -State $State

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
        # Populate additional FFU list and apply selections
        try {
            if ($State.Controls.chkCopyAdditionalFFUFiles.IsChecked) {
                $State.Controls.additionalFFUPanel.Visibility = 'Visible'
                if ($State.Controls.btnRefreshAdditionalFFUs) {
                    $State.Controls.btnRefreshAdditionalFFUs.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
                }
                $selectedFiles = @()
                $addFFUKeyExists = $false
                if ($ConfigContent -is [System.Management.Automation.PSCustomObject] -and $null -ne $ConfigContent.PSObject.Properties) {
                    if (($ConfigContent.PSObject.Properties.Match('AdditionalFFUFiles')).Count -gt 0) {
                        $addFFUKeyExists = $true
                    }
                }
                if ($addFFUKeyExists -and $null -ne $ConfigContent.AdditionalFFUFiles) {
                    $selectedFiles = @($ConfigContent.AdditionalFFUFiles)
                }
                if ($selectedFiles.Count -gt 0) {
                    foreach ($item in $State.Controls.lstAdditionalFFUs.Items) {
                        if ($selectedFiles -contains $item.FullName) {
                            $item.IsSelected = $true
                        }
                    }
                    $State.Controls.lstAdditionalFFUs.Items.Refresh()
                    $headerChk = $State.Controls.chkSelectAllAdditionalFFUs
                    if ($null -ne $headerChk) {
                        Update-SelectAllHeaderCheckBoxState -ListView $State.Controls.lstAdditionalFFUs -HeaderCheckBox $headerChk
                    }
                }
            }
            else {
                $State.Controls.additionalFFUPanel.Visibility = 'Collapsed'
            }
        }
        catch {
            WriteLog "LoadConfig: Error applying Additional FFU selections: $($_.Exception.Message)"
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
            # Sort top-level keys alphabetically for consistent output
            $sortedConfig = [ordered]@{}
            foreach ($k in ($config.Keys | Sort-Object)) { $sortedConfig[$k] = $config[$k] }
            $sortedConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $savePath -Encoding UTF8
            [System.Windows.MessageBox]::Show("Configuration file saved to:`n$savePath", "Success", "OK", "Information")
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Error saving config file:`n$($_.Exception.Message)", "Error", "OK", "Error")
    }
}

function Invoke-RestoreDefaults {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$State
    )
    try {
        $rootPath = $State.FFUDevelopmentPath

        # Normalize potential array values to single strings
        function Normalize-PathScalar {
            param([object]$value)
            if ($null -eq $value) { $null; return }
            if ($value -is [System.Array]) {
                foreach ($v in $value) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$v)) {
                        [string]$v
                        return
                    }
                }
                $null
                return
            }
            [string]$value
        }

        $appsPath = Join-Path $rootPath 'Apps'
        $driversRaw = Normalize-PathScalar -value $State.Controls.txtDriversFolder.Text
        if ([string]::IsNullOrWhiteSpace($driversRaw)) {
            $driversPath = Join-Path $rootPath 'Drivers'
        }
        else {
            $driversPath = $driversRaw
        }
        $ffuCaptureRaw = Normalize-PathScalar -value $State.Controls.txtFFUCaptureLocation.Text
        $ffuCapturePath = if ([string]::IsNullOrWhiteSpace($ffuCaptureRaw)) { Join-Path $rootPath 'FFU' } else { $ffuCaptureRaw }

        $captureISOPath = Join-Path $rootPath 'WinPECaptureFFUFiles\WinPE-Capture.iso'
        $deployISOPath = Join-Path $rootPath 'WinPEDeployFFUFiles\WinPE-Deploy.iso'
        $appsISOPath = Join-Path $rootPath 'Apps\Apps.iso'
        
        $msg = "Restore Defaults will:`n`n- Delete generated config and app/driver list JSON files`n- Remove ISO files (Capture, Deploy, Apps) if present`n- Remove Apps/Update/downloaded artifacts`n- Remove driver folder contents (not the folder)`n- Remove FFU files in the capture folder`n`nSample/template files and VM/VHDX cache are NOT removed.`n`nProceed?"
        $result = [System.Windows.MessageBox]::Show($msg, "Confirm Restore Defaults", "YesNo", "Warning")
        if ($result -ne [System.Windows.MessageBoxResult]::Yes) {
            WriteLog "RestoreDefaults: User cancelled."
            return
        }

        WriteLog "RestoreDefaults: Starting environment reset."
        WriteLog "RestoreDefaults: Paths -> Apps=$appsPath Drivers=$driversPath FFUCapture=$ffuCapturePath"

        # Remove JSON artifact files if present
        $artifactFiles = @(
            (Join-Path $rootPath 'config\FFUConfig.json'),
            (Join-Path $appsPath 'AppList.json'),
            (Join-Path $driversPath 'Drivers.json'),
            (Join-Path $appsPath 'UserAppList.json')
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

        foreach ($file in $artifactFiles) {
            if ((-not [string]::IsNullOrWhiteSpace($file)) -and (Test-Path -LiteralPath $file)) {
                try {
                    WriteLog "RestoreDefaults: Removing $file"
                    Remove-Item -LiteralPath $file -Force -ErrorAction Stop
                }
                catch {
                    WriteLog "RestoreDefaults: Failed removing $file : $($_.Exception.Message)"
                }
            }
        }

        # Force all cleanup flags true
        Invoke-FFUPostBuildCleanup `
            -RootPath $rootPath `
            -AppsPath $appsPath `
            -DriversPath $driversPath `
            -FFUCapturePath $ffuCapturePath `
            -CaptureISOPath $captureISOPath `
            -DeployISOPath $deployISOPath `
            -AppsISOPath $appsISOPath `
            -RemoveCaptureISO:$true `
            -RemoveDeployISO:$true `
            -RemoveAppsISO:$true `
            -RemoveDrivers:$true `
            -RemoveFFU:$true `
            -RemoveApps:$true `
            -RemoveUpdates:$true

        # Clear UI lists / state
        if ($null -ne $State.Data.allDriverModels) { $State.Data.allDriverModels.Clear() }
        if ($null -ne $State.Controls.lstDriverModels) { $State.Controls.lstDriverModels.Items.Refresh() }
        if ($null -ne $State.Controls.lstApplications) {
            try {
                if ($State.Controls.lstApplications.ItemsSource) { $State.Controls.lstApplications.ItemsSource = $null }
                $State.Controls.lstApplications.Items.Clear()
            } catch {}
        }
        if ($null -ne $State.Controls.lstWingetResults) {
            try { 
                if ($State.Controls.lstWingetResults.ItemsSource) { $State.Controls.lstWingetResults.ItemsSource = $null }
                $State.Controls.lstWingetResults.Items.Clear() 
            } catch {}
        }
        if ($null -ne $State.Controls.lstAppsScriptVariables) {
            try {
                if ($State.Controls.lstAppsScriptVariables.ItemsSource) { $State.Controls.lstAppsScriptVariables.ItemsSource = $null }
                $State.Controls.lstAppsScriptVariables.Items.Clear()
            } catch {}
        }

        $State.Data.lastConfigFilePath = $null

        Initialize-UIDefaults -State $State

        WriteLog "RestoreDefaults: Completed."
        [System.Windows.MessageBox]::Show("Environment restored to defaults.", "Restore Defaults", "OK", "Information")
    }
    catch {
        WriteLog "RestoreDefaults: Failed with $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show("Restore Defaults failed:`n$($_.Exception.Message)", "Error", "OK", "Error")
    }
}

function Show-ConfigMigrationDialog {
    <#
    .SYNOPSIS
    Shows a dialog with migration changes and asks user to confirm.

    .DESCRIPTION
    Displays a WPF MessageBox showing the list of changes that will be applied
    during config migration. User can accept or decline the migration.

    .PARAMETER MigrationResult
    The result hashtable from Invoke-FFUConfigMigration containing:
    - FromVersion: The original config version
    - ToVersion: The target schema version
    - Changes: Array of change descriptions

    .OUTPUTS
    System.Boolean - $true if user accepted, $false if declined

    .EXAMPLE
    $proceed = Show-ConfigMigrationDialog -MigrationResult $migrationResult
    if ($proceed) { # Save migrated config }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$MigrationResult
    )

    if ($MigrationResult.Changes.Count -eq 0) {
        return $true  # No changes needed
    }

    # Format changes with icons
    $changesList = $MigrationResult.Changes | ForEach-Object {
        if ($_ -like "WARNING:*") {
            "[!] $_"
        } else {
            "[+] $_"
        }
    }
    $changesText = $changesList -join "`n"

    $message = @"
Your configuration file was created with an older version of FFU Builder.

From version: $($MigrationResult.FromVersion)
To version: $($MigrationResult.ToVersion)

The following changes will be applied:
$changesText

A backup of your original configuration has been created.

Do you want to apply these changes?
"@

    $result = [System.Windows.MessageBox]::Show(
        $message,
        "Configuration Migration Required",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )

    return ($result -eq [System.Windows.MessageBoxResult]::Yes)
}

function Invoke-AutoLoadPreviousEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$State
    )
    try {
        $ffuDevRoot = $State.FFUDevelopmentPath
        if ([string]::IsNullOrWhiteSpace($ffuDevRoot)) {
            WriteLog "AutoLoad: FFUDevelopmentPath not set; skipping."
            return
        }
        $configPath = Join-Path $ffuDevRoot "config\FFUConfig.json"
        if (-not (Test-Path -LiteralPath $configPath)) {
            WriteLog "AutoLoad: No existing FFUConfig.json found at $configPath."
            return
        }
        WriteLog "AutoLoad: Found config file at $configPath. Parsing..."
        $raw = Get-Content -Path $configPath -Raw -ErrorAction SilentlyContinue
        if ([string]::IsNullOrWhiteSpace($raw)) {
            WriteLog "AutoLoad: Config file empty; aborting."
            return
        }
        $configContent = $null
        try {
            $configContent = $raw | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            WriteLog "AutoLoad: JSON parse failed: $($_.Exception.Message)"
            return
        }
        if ($null -eq $configContent) {
            WriteLog "AutoLoad: Parsed object null; aborting."
            return
        }

        # Check if migration is needed
        if (Get-Command -Name 'Test-FFUConfigVersion' -ErrorAction SilentlyContinue) {
            # Convert to hashtable for migration
            $configHashtable = ConvertTo-HashtableRecursive -InputObject $configContent

            $versionCheck = Test-FFUConfigVersion -Config $configHashtable

            if ($versionCheck.NeedsMigration) {
                WriteLog "AutoLoad: Config needs migration from v$($versionCheck.ConfigVersion) to v$($versionCheck.CurrentSchemaVersion)"

                # Perform migration with backup
                $migrationResult = Invoke-FFUConfigMigration -Config $configHashtable -CreateBackup -ConfigPath $configPath

                if ($migrationResult.Changes.Count -gt 0) {
                    # Show dialog and get user confirmation
                    $proceed = Show-ConfigMigrationDialog -MigrationResult $migrationResult

                    if ($proceed) {
                        WriteLog "AutoLoad: User accepted migration. Saving migrated config."

                        # Save migrated config
                        $migrationResult.Config | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath -Encoding UTF8
                        WriteLog "AutoLoad: Migrated config saved to $configPath"

                        # Use migrated config
                        $configContent = [PSCustomObject]$migrationResult.Config
                    } else {
                        WriteLog "AutoLoad: User declined migration. Loading original config (deprecated properties ignored)."
                    }
                }
            }
        }

        WriteLog "AutoLoad: Applying core configuration."
        Update-UIFromConfig -ConfigContent $configContent -State $State
        $State.Data.lastConfigFilePath = $configPath
        Import-ConfigSupplementalAssets -ConfigContent $configContent -State $State -ShowWarnings:$false
        WriteLog "AutoLoad: Completed supplemental import with warnings disabled."
    }
    catch {
        WriteLog "AutoLoad: Unexpected failure: $($_.Exception.ToString())"
    }
}

function Import-ConfigSupplementalAssets {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$ConfigContent,
        [Parameter(Mandatory = $true)]
        [psobject]$State,
        [Parameter()]
        [bool]$ShowWarnings = $false
    )
    WriteLog "SupplementalImport: Starting import of helper assets."
    $loadedWinget = $false
    $loadedBYO = $false
    $loadedDrivers = $false
    $missing = New-Object System.Collections.Generic.List[string]

    # Winget AppList
    $appListPath = $null
    if ($ConfigContent.PSObject.Properties.Match('AppListPath').Count -gt 0) {
        $appListPath = $ConfigContent.AppListPath
    }
    if (-not [string]::IsNullOrWhiteSpace($appListPath)) {
        if (Test-Path -LiteralPath $appListPath) {
            WriteLog "SupplementalImport: Loading Winget AppList from $appListPath"
            try {
                $importedAppsData = Get-Content -Path $appListPath -Raw | ConvertFrom-Json -ErrorAction Stop
                if ($null -ne $importedAppsData -and $null -ne $importedAppsData.apps) {
                    $defaultArch = $State.Controls.cmbWindowsArch.SelectedItem
                    $appsBuffer = [System.Collections.Generic.List[object]]::new()
                    foreach ($appInfo in $importedAppsData.apps) {
                        $arch = if ($appInfo.source -eq 'msstore') { 'NA' } else {
                            if ($appInfo.PSObject.Properties['architecture']) { $appInfo.architecture } else { $defaultArch }
                        }
                        $appsBuffer.Add([PSCustomObject]@{
                                IsSelected               = $true
                                Name                     = $appInfo.name
                                Id                       = $appInfo.id
                                Version                  = ""
                                Source                   = $appInfo.source
                                Architecture             = $arch
                                AdditionalExitCodes      = if ($appInfo.PSObject.Properties['AdditionalExitCodes']) { $appInfo.AdditionalExitCodes } else { "" }
                                IgnoreNonZeroExitCodes   = if ($appInfo.PSObject.Properties['IgnoreNonZeroExitCodes']) { [bool]$appInfo.IgnoreNonZeroExitCodes } else { $false }
                                DownloadStatus           = ""
                            })
                    }
                    $State.Controls.lstWingetResults.ItemsSource = $appsBuffer.ToArray()
                    $loadedWinget = $true
                    if ($null -ne $State.Controls.wingetSearchPanel) {
                        $State.Controls.wingetSearchPanel.Visibility = 'Visible'
                    }
                    if ($null -ne $State.Controls.chkSelectAllWingetResults -and (Get-Command -Name Update-SelectAllHeaderCheckBoxState -ErrorAction SilentlyContinue)) {
                        Update-SelectAllHeaderCheckBoxState -ListView $State.Controls.lstWingetResults -HeaderCheckBox $State.Controls.chkSelectAllWingetResults
                    }
                    WriteLog "SupplementalImport: Winget list loaded with $($appsBuffer.Count) entries."
                }
                else {
                    WriteLog "SupplementalImport: Winget AppList missing 'apps' array."
                }
            }
            catch {
                WriteLog "SupplementalImport: Failed loading Winget AppList ($appListPath): $($_.Exception.Message)"
            }
        }
        else {
            WriteLog "SupplementalImport: Winget AppList file missing: $appListPath"
            $missing.Add("Winget AppList (AppListPath): $appListPath")
        }
    }
    else {
        WriteLog "SupplementalImport: AppListPath not defined in config."
    }

    # UserAppList (BYO)
    $userAppListPath = $null
    if ($ConfigContent.PSObject.Properties.Match('UserAppListPath').Count -gt 0) {
        $userAppListPath = $ConfigContent.UserAppListPath
    }
    if (-not [string]::IsNullOrWhiteSpace($userAppListPath)) {
        if (Test-Path -LiteralPath $userAppListPath) {
            WriteLog "SupplementalImport: Loading UserAppList from $userAppListPath"
            try {
                $applications = Get-Content -Path $userAppListPath -Raw | ConvertFrom-Json -ErrorAction Stop
                if ($applications) {
                    $listView = $State.Controls.lstApplications
                    $listView.Items.Clear()
                    $sortedApps = $applications | Sort-Object Priority
                    foreach ($app in $sortedApps) {
                        $ignoreNonZero = if ($app.PSObject.Properties['IgnoreNonZeroExitCodes']) { $app.IgnoreNonZeroExitCodes } else { $false }
                        $listView.Items.Add([PSCustomObject]@{
                                IsSelected             = $false
                                Priority               = $app.Priority
                                Name                   = $app.Name
                                CommandLine            = $app.CommandLine
                                Arguments              = if ($app.PSObject.Properties['Arguments']) { $app.Arguments } else { "" }
                                Source                 = $app.Source
                                AdditionalExitCodes    = if ($app.PSObject.Properties['AdditionalExitCodes']) { $app.AdditionalExitCodes } else { "" }
                                IgnoreNonZeroExitCodes = $ignoreNonZero
                                IgnoreExitCodes        = if ($ignoreNonZero) { "Yes" } else { "No" }
                                CopyStatus             = ""
                            })
                    }
                    if (Get-Command -Name Update-ListViewPriorities -ErrorAction SilentlyContinue) {
                        Update-ListViewPriorities -ListView $listView
                    }
                    if (Get-Command -Name Update-CopyButtonState -ErrorAction SilentlyContinue) {
                        Update-CopyButtonState -State $State
                    }
                    if (Get-Command -Name Update-BYOAppsActionButtonsState -ErrorAction SilentlyContinue) {
                        Update-BYOAppsActionButtonsState -State $State
                    }
                    $loadedBYO = $true
                    WriteLog "SupplementalImport: UserAppList loaded with $($listView.Items.Count) entries."
                }
                else {
                    WriteLog "SupplementalImport: UserAppList JSON empty."
                }
            }
            catch {
                WriteLog "SupplementalImport: Failed loading UserAppList ($userAppListPath): $($_.Exception.Message)"
            }
        }
        else {
            WriteLog "SupplementalImport: UserAppList file missing: $userAppListPath"
            $missing.Add("UserAppList (UserAppListPath): $userAppListPath")
        }
    }
    else {
        WriteLog "SupplementalImport: UserAppListPath not defined in config."
    }

    # Drivers JSON
    $driversJsonPath = $null
    if ($ConfigContent.PSObject.Properties.Match('DriversJsonPath').Count -gt 0) {
        $driversJsonPath = $ConfigContent.DriversJsonPath
    }
    if (-not [string]::IsNullOrWhiteSpace($driversJsonPath)) {
        if (Test-Path -LiteralPath $driversJsonPath) {
            WriteLog "SupplementalImport: Loading Drivers JSON from $driversJsonPath"
            try {
                $rawDrivers = Get-Content -Path $driversJsonPath -Raw | ConvertFrom-Json -ErrorAction Stop
                if ($rawDrivers -and $rawDrivers.PSObject.Properties.Count -gt 0) {
                    $State.Data.allDriverModels.Clear()
                    foreach ($makeProp in $rawDrivers.PSObject.Properties) {
                        $makeName = $makeProp.Name
                        $makeObject = $makeProp.Value
                        if ($null -eq $makeObject -or -not ($makeObject.PSObject.Properties['Models'])) { continue }
                        $models = $makeObject.Models
                        if ($models -and ($models -is [System.Collections.IEnumerable])) {
                            foreach ($modelEntry in $models) {
                                if ($null -eq $modelEntry -or -not ($modelEntry.PSObject.Properties['Name'])) { continue }
                                $modelName = $modelEntry.Name
                                if ([string]::IsNullOrWhiteSpace($modelName)) { continue }
                                $driverObj = [PSCustomObject]@{
                                    IsSelected     = $true
                                    Make           = $makeName
                                    Model          = $modelName
                                    DownloadStatus = if ($modelEntry.PSObject.Properties['DownloadStatus']) { $modelEntry.DownloadStatus } else { "" }
                                    Link           = if ($modelEntry.PSObject.Properties['Link']) { $modelEntry.Link } else { $null }
                                    ProductName    = if ($modelEntry.PSObject.Properties['ProductName']) { $modelEntry.ProductName } else { $null }
                                    MachineType    = if ($modelEntry.PSObject.Properties['MachineType']) { $modelEntry.MachineType } else { $null }
                                    Id             = if ($modelEntry.PSObject.Properties['Id']) { $modelEntry.Id } else { $null }
                                }
                                $State.Data.allDriverModels.Add($driverObj)
                            }
                        }
                    }
                    $State.Controls.lstDriverModels.ItemsSource = $State.Data.allDriverModels
                    if (Get-Command -Name Update-SelectAllHeaderCheckBoxState -ErrorAction SilentlyContinue) {
                        $headerChk = $State.Controls.chkSelectAllDriverModels
                        if ($null -ne $headerChk) {
                            Update-SelectAllHeaderCheckBoxState -ListView $State.Controls.lstDriverModels -HeaderCheckBox $headerChk
                        }
                    }
                    if ($State.Data.allDriverModels.Count -gt 0) {
                        if ($null -ne $State.Controls.spModelFilterSection) { $State.Controls.spModelFilterSection.Visibility = 'Visible' }
                        if ($null -ne $State.Controls.lstDriverModels) { $State.Controls.lstDriverModels.Visibility = 'Visible' }
                        if ($null -ne $State.Controls.spDriverActionButtons) { $State.Controls.spDriverActionButtons.Visibility = 'Visible' }
                        try {
                            if ($State.Controls.cmbMake.SelectedIndex -lt 0 -and $State.Data.allDriverModels.Count -gt 0) {
                                $firstMake = ($State.Data.allDriverModels | Select-Object -First 1).Make
                                if (-not [string]::IsNullOrWhiteSpace($firstMake)) {
                                    $makeItem = $State.Controls.cmbMake.Items | Where-Object { $_ -eq $firstMake } | Select-Object -First 1
                                    if ($makeItem) { $State.Controls.cmbMake.SelectedItem = $makeItem }
                                }
                            }
                        }
                        catch {
                            WriteLog "SupplementalImport: Non-fatal error selecting first Make: $($_.Exception.Message)"
                        }
                    }
                    $loadedDrivers = $true
                    WriteLog "SupplementalImport: Loaded $($State.Data.allDriverModels.Count) driver models."
                }
                else {
                    WriteLog "SupplementalImport: Drivers JSON empty or structure unexpected."
                }
            }
            catch {
                WriteLog "SupplementalImport: Failed loading Drivers JSON ($driversJsonPath): $($_.Exception.Message)"
            }
        }
        else {
            WriteLog "SupplementalImport: Drivers JSON file missing: $driversJsonPath"
            $missing.Add("Drivers (DriversJsonPath): $driversJsonPath")
        }
    }
    else {
        WriteLog "SupplementalImport: DriversJsonPath not defined in config."
    }

    if ($loadedWinget -or $loadedBYO) {
        $State.Controls.chkInstallApps.IsChecked = $true
    }
    if ($loadedWinget) {
        $State.Controls.chkInstallWingetApps.IsChecked = $true
    }
    if ($loadedBYO) {
        $State.Controls.chkBringYourOwnApps.IsChecked = $true
    }
    if ($loadedDrivers) {
        $State.Controls.chkDownloadDrivers.IsChecked = $true
    }

    if (Get-Command -Name Update-ApplicationPanelVisibility -ErrorAction SilentlyContinue) {
        Update-ApplicationPanelVisibility -State $State -TriggeringControlName 'SupplementalImport'
    }
    if (Get-Command -Name Update-DriverDownloadPanelVisibility -ErrorAction SilentlyContinue) {
        Update-DriverDownloadPanelVisibility -State $State
    }
    if (Get-Command -Name Update-DriverCheckboxStates -ErrorAction SilentlyContinue) {
        Update-DriverCheckboxStates -State $State
    }
    if (Get-Command -Name Update-OfficePanelVisibility -ErrorAction SilentlyContinue) {
        Update-OfficePanelVisibility -State $State
    }
    if (Get-Command -Name Update-CopyButtonState -ErrorAction SilentlyContinue) {
        Update-CopyButtonState -State $State
    }

    # Updated message to clarify successful load and that missing helper files are optional if not yet created.
    if ($ShowWarnings -and $missing.Count -gt 0) {
        $msg = "Configuration file loaded successfully.`n`n" +
            "Optional helper file(s) referenced in the configuration were not found:`n" +
            ($missing | ForEach-Object { "- $_" } | Out-String) +
            "`nThese files are optional. They won't exist until you create Winget (AppList.json), User (UserAppList.json), or Driver (Drivers.json) manifests. You can create them later or ignore this message."
        [System.Windows.MessageBox]::Show($msg.TrimEnd(), "Configuration Loaded - Optional Files Missing", "OK", "Information") | Out-Null
    }

    WriteLog ("SupplementalImport: Complete. Winget={0} BYO={1} Drivers={2} Missing={3}" -f $loadedWinget, $loadedBYO, $loadedDrivers, $missing.Count)
}

Export-ModuleMember -Function *