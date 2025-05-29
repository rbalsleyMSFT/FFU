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
$global:LogFile = "$FFUDevelopmentPath\FFUDevelopment_UI.log"
$AppsPath = "$FFUDevelopmentPath\Apps"
$AppListJsonPath = "$AppsPath\AppList.json"
$UserAppListJsonPath = "$AppsPath\UserAppList.json" # Define path for UserAppList.json
#Microsoft sites will intermittently fail on downloads. These headers are to help with that.
$Headers = @{
    "Accept"                    = "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7"
    "Accept-Encoding"           = "gzip, deflate, br, zstd"
    "Accept-Language"           = "en-US,en;q=0.9"
    "Priority"                  = "u=0, i"
    "Sec-Ch-Ua"                 = "`"Microsoft Edge`";v=`"125`", `"Chromium`";v=`"125`", `"Not.A/Brand`";v=`"24`""
    "Sec-Ch-Ua-Mobile"          = "?0"
    "Sec-Ch-Ua-Platform"        = "`"Windows`""
    "Sec-Fetch-Dest"            = "document"
    "Sec-Fetch-Mode"            = "navigate"
    "Sec-Fetch-Site"            = "none"
    "Sec-Fetch-User"            = "?1"
    "Upgrade-Insecure-Requests" = "1"
}
$UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36 Edg/125.0.0.0'

# Remove any existing modules to avoid conflicts
if (Get-Module -Name 'FFU.Common.Core' -ErrorAction SilentlyContinue) {
    Remove-Module -Name 'FFU.Common.Core' -Force
}
if (Get-Module -Name 'FFUUI.Core' -ErrorAction SilentlyContinue) {
    Remove-Module -Name 'FFUUI.Core' -Force
}
# Import the common core module first for logging
Import-Module "$PSScriptRoot\common\FFU.Common.Core.psm1" 
# Import the Core UI Logic Module
Import-Module "$PSScriptRoot\FFUUI.Core\FFUUI.Core.psm1"

# Set the log path for the common logger (for UI operations)
Set-CommonCoreLogPath -Path $global:LogFile

# Script-scoped list for Apps Script Variables data
$script:appsScriptVariablesDataList = [System.Collections.Generic.List[PSCustomObject]]::new()

# Setting long path support - this prevents issues where some applications have deep directory structures
# and driver extraction fails due to long paths.
$script:originalLongPathsValue = $null # Store original value
try {
    $script:originalLongPathsValue = Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -ErrorAction SilentlyContinue
}
catch {
    # Key or value might not exist, which is fine.
    WriteLog "Could not read initial LongPathsEnabled value (may not exist)."
}

# Enable long paths if not already enabled
if ($script:originalLongPathsValue -ne 1) {
    try {
        WriteLog 'LongPathsEnabled is not set to 1. Setting it to 1 for the duration of this script.'
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Value 1 -Force
        WriteLog 'LongPathsEnabled set to 1.'
    }
    catch {
        WriteLog "Error setting LongPathsEnabled registry key: $($_.Exception.Message). Long path issues might persist."
        # Optionally show a warning to the user if this fails?
        # [System.Windows.MessageBox]::Show("Could not enable long path support. Some operations might fail.", "Warning", "OK", "Warning")
    }
}
else {
    WriteLog "LongPathsEnabled is already set to 1."
}

# ----------------------------------------------------------------------------
# SECTION: LOAD UI
# ----------------------------------------------------------------------------

# Helper function to safely set UI properties from config and log the process
function Set-UIValue {
    param(
        [string]$ControlName,
        [string]$PropertyName,
        [object]$ConfigObject,
        [string]$ConfigKey,
        [scriptblock]$TransformValue = $null, # Optional scriptblock to transform the value from config
        [object]$WindowInstance # Pass the $window object
    )

    $control = $WindowInstance.FindName($ControlName)
    if ($null -eq $control) {
        WriteLog "LoadConfig Error: Control '$ControlName' not found in the window."
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
                } elseif ($item -is [pscustomobject] -and $item.PSObject.Properties['Value']) {
                    $itemValue = $item.Value
                } elseif ($item -is [pscustomobject] -and $item.PSObject.Properties['Display']) { # Assuming 'Display' might be used if 'Value' isn't
                    $itemValue = $item.Display
                } else {
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
            } elseif ($control.IsEditable -and ($finalValue -is [string] -or $finalValue -is [int] -or $finalValue -is [long])) {
                $control.Text = $finalValue.ToString()
                WriteLog "LoadConfig: Set '$ControlName.Text' to '$($finalValue.ToString())' as SelectedItem match failed (editable ComboBox)."
            } else {
                $itemsString = ""
                try {
                    # Safer way to get item strings
                    $itemStrings = @()
                    foreach ($cbItem in $control.Items) {
                        if ($null -ne $cbItem) { $itemStrings += $cbItem.ToString() } else { $itemStrings += "[NULL_ITEM]" }
                    }
                    $itemsString = $itemStrings -join "; "
                } catch { $itemsString = "Error retrieving item strings." }
                WriteLog "LoadConfig Warning: Could not find or set item matching value '$finalValue' for '$ControlName.SelectedItem'. Current items: [$itemsString]"
            }
        } else {
            # For other properties or controls
            $control.$PropertyName = $finalValue
            WriteLog "LoadConfig: Successfully set '$ControlName.$PropertyName' to '$finalValue'."
        }
    }
    catch {
        WriteLog "LoadConfig Error: Failed to set '$ControlName.$PropertyName' to '$finalValue'. Error: $($_.Exception.Message)"
    }
}

# --------------------------------------------------------------------------
# SECTION: Driver Download Functions
# --------------------------------------------------------------------------

# Variable to store the full list of retrieved driver models
$script:allDriverModels = @()

# Helper function to convert raw driver objects to a standardized format
function ConvertTo-StandardizedDriverModel {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$RawDriverObject,
        [Parameter(Mandatory = $true)]
        [string]$Make
    )

    $modelDisplay = $RawDriverObject.Model # Default
    $id = $RawDriverObject.Model           # Default
    $link = $null
    $productName = $null
    $machineType = $null

    if ($RawDriverObject.PSObject.Properties['Link']) {
        $link = $RawDriverObject.Link
    }

    # Lenovo specific handling
    if ($Make -eq 'Lenovo') {
        # RawDriverObject.Model is "ProductName (MachineType)" from Get-LenovoDriversModelList
        # RawDriverObject.ProductName is "ProductName"
        # RawDriverObject.MachineType is "MachineType"
        $modelDisplay = $RawDriverObject.Model # This is already "ProductName (MachineType)"
        $productName = $RawDriverObject.ProductName
        $machineType = $RawDriverObject.MachineType
        $id = $RawDriverObject.MachineType # Use MachineType as a more specific ID for Lenovo backend operations if needed
    }

    return [PSCustomObject]@{
        IsSelected     = $false
        Make           = $Make
        Model          = $modelDisplay # Primary display string, used as identifier in ListView
        Link           = $link
        Id             = $id            # Technical/unique identifier (e.g., MachineType for Lenovo)
        ProductName    = $productName   # Specific for Lenovo
        MachineType    = $machineType   # Specific for Lenovo
        Version        = "" # Placeholder
        Type           = "" # Placeholder
        Size           = "" # Placeholder
        Arch           = "" # Placeholder
        DownloadStatus = "" # Initial download status
    }
}

# Helper function to get models for a selected Make and standardize them
function Get-ModelsForMake {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SelectedMake
    )

    $standardizedModels = [System.Collections.Generic.List[PSCustomObject]]::new()
    $rawModels = @()

    # Get necessary values from UI or script scope
    $localDriversFolder = $window.FindName('txtDriversFolder').Text
    $localWindowsRelease = $null
    if ($null -ne $window.FindName('cmbWindowsRelease').SelectedItem) {
        $localWindowsRelease = $window.FindName('cmbWindowsRelease').SelectedItem.Value
    }
    
    # $Headers and $UserAgent are available from script scope

    if (-not $localWindowsRelease -and ($SelectedMake -eq 'Dell' -or $SelectedMake -eq 'Lenovo')) {
        [System.Windows.MessageBox]::Show("Please select a Windows Release first for $SelectedMake.", "Missing Information", "OK", "Warning")
        throw "Windows Release not selected for $SelectedMake."
    }

    switch ($SelectedMake) {
        'Microsoft' {
            $rawModels = Get-MicrosoftDriversModelList -Headers $Headers -UserAgent $UserAgent
        }
        'Dell' {
            $rawModels = Get-DellDriversModelList -WindowsRelease $localWindowsRelease -DriversFolder $localDriversFolder -Make $SelectedMake
        }
        'HP' {
            $rawModels = Get-HPDriversModelList -DriversFolder $localDriversFolder -Make $SelectedMake
        }
        'Lenovo' {
            $modelSearchTerm = [Microsoft.VisualBasic.Interaction]::InputBox("Enter Lenovo Model Name or Machine Type (e.g., T480 or 20L5):", "Lenovo Model Search", "")
            if ([string]::IsNullOrWhiteSpace($modelSearchTerm)) {
                # User cancelled or entered nothing
                return @() 
            }
            $script:txtStatus.Text = "Searching Lenovo models for '$modelSearchTerm'..."
            $rawModels = Get-LenovoDriversModelList -ModelSearchTerm $modelSearchTerm -Headers $Headers -UserAgent $UserAgent
        }
        default {
            [System.Windows.MessageBox]::Show("Selected Make '$SelectedMake' is not supported for automatic model retrieval.", "Unsupported Make", "OK", "Warning")
            return @()
        }
    }

    if ($null -ne $rawModels) {
        foreach ($rawModel in $rawModels) {
            # Filter out Chromebooks for Lenovo before standardization
            if ($SelectedMake -eq 'Lenovo' -and $rawModel.Model -match 'Chromebook') {
                WriteLog "Get-ModelsForMake: Skipping Chromebook model: $($rawModel.Model)"
                continue
            }
            $standardizedModels.Add((ConvertTo-StandardizedDriverModel -RawDriverObject $rawModel -Make $SelectedMake))
        }
    }
    
    return $standardizedModels.ToArray()
}



# Function to filter the driver model list based on text input
function Filter-DriverModels {
    param(
        [string]$filterText
    )
    # Check if UI elements and the full list are available
    if ($null -eq $script:lstDriverModels -or $null -eq $script:allDriverModels) {
        WriteLog "Filter-DriverModels: ListView or full model list not available."
        return
    }

    WriteLog "Filtering models with text: '$filterText'"

    # Filter the full list based on the Model property (case-insensitive)
    # Use -match for potentially better performance or stick with -like
    # Ensure the result is always an array, even if only one item matches
    $filteredModels = @($script:allDriverModels | Where-Object { $_.Model -like "*$filterText*" })

    # Update the ListView's ItemsSource with the filtered list
    # Setting ItemsSource directly should work for simple scenarios
    $script:lstDriverModels.ItemsSource = $filteredModels

    # Explicitly refresh the ListView's view to reflect the changes in the bound source
    if ($null -ne $script:lstDriverModels.ItemsSource -and $script:lstDriverModels.Items -is [System.ComponentModel.ICollectionView]) {
        $script:lstDriverModels.Items.Refresh()
    }
    elseif ($null -ne $script:lstDriverModels.ItemsSource) {
        # Fallback refresh if not using ICollectionView (less common for direct ItemsSource binding)
        $script:lstDriverModels.Items.Refresh()
    }


    WriteLog "Filtered list contains $($filteredModels.Count) models."
}
    
# Function to save selected driver models to a JSON file
function Save-DriversJson {
    WriteLog "Save-DriversJson function called."
    $selectedDrivers = @($script:lstDriverModels.Items | Where-Object { $_.IsSelected })
    
    if (-not $selectedDrivers) {
        [System.Windows.MessageBox]::Show("No drivers selected to save.", "Save Drivers", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        WriteLog "No drivers selected to save."
        return
    }
    
    $outputJson = @{} # Use a Hashtable for the desired structure
    
    $selectedDrivers | Group-Object -Property Make | ForEach-Object {
        $makeName = $_.Name
        $modelsForThisMake = @() # Initialize an array to hold model objects
    
        foreach ($driverItem in $_.Group) {
            $modelObject = $null
            switch ($makeName) {
                'Microsoft' {
                    $modelObject = @{
                        Name = $driverItem.Model # Model is the display name
                        Link = $driverItem.Link
                    }
                }
                'Dell' {
                    $modelObject = @{
                        Name = $driverItem.Model
                    }
                }
                'HP' {
                    $modelObject = @{
                        Name = $driverItem.Model
                    }
                }
                'Lenovo' {
                    $modelObject = @{
                        Name        = $driverItem.Model       # This is "ProductName (MachineType)"
                        ProductName = $driverItem.ProductName # This is "ProductName"
                        MachineType = $driverItem.MachineType # This is "MachineType"
                    }
                }
                default {
                    WriteLog "Save-DriversJson: Unknown Make '$makeName' encountered for model '$($driverItem.Model)'. Skipping."
                }
            }
            if ($null -ne $modelObject) {
                $modelsForThisMake += $modelObject
            }
        }
    
        if ($modelsForThisMake.Count -gt 0) {
            # Store the array of model objects under a "Models" key
            $outputJson[$makeName] = @{
                "Models" = $modelsForThisMake
            }
        }
    }
    
    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*"
    $sfd.Title = "Save Selected Drivers"
    $sfd.FileName = "Drivers.json"
    $sfd.InitialDirectory = $FFUDevelopmentPath 
    
    if ($sfd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            $outputJson | ConvertTo-Json -Depth 5 | Set-Content -Path $sfd.FileName -Encoding UTF8
            [System.Windows.MessageBox]::Show("Selected drivers saved to $($sfd.FileName)", "Save Successful", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            WriteLog "Selected drivers saved to $($sfd.FileName)"
        }
        catch {
            [System.Windows.MessageBox]::Show("Error saving drivers file: $($_.Exception.Message)", "Save Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
            WriteLog "Error saving drivers file to $($sfd.FileName): $($_.Exception.Message)"
        }
    }
    else {
        WriteLog "Save drivers operation cancelled by user."
    }
}

# Function to import driver models from a JSON file
function Import-DriversJson {
    WriteLog "Import-DriversJson function called."
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*"
    $ofd.Title = "Import Drivers"
    $ofd.InitialDirectory = $FFUDevelopmentPath 

    if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            $importedData = Get-Content -Path $ofd.FileName -Raw | ConvertFrom-Json
            if ($null -eq $importedData -or $importedData -isnot [System.Management.Automation.PSCustomObject]) {
                [System.Windows.MessageBox]::Show("Invalid JSON file format. Expected a JSON object with Makes as keys.", "Import Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
                WriteLog "Import-DriversJson: Invalid JSON format in $($ofd.FileName). Expected an object."
                return
            }

            $newModelsAdded = 0
            $existingModelsUpdated = 0

            if ($null -eq $script:allDriverModels) {
                $script:allDriverModels = @()
            }

            $importedData.PSObject.Properties | ForEach-Object {
                $makeName = $_.Name
                $makeData = $_.Value # This is the object containing "Models" array

                # Check if $makeData is null, not a PSCustomObject, or does not have a 'Models' property
                if ($null -eq $makeData -or $makeData -isnot [System.Management.Automation.PSCustomObject] -or -not ($makeData.PSObject.Properties | Where-Object { $_.Name -eq 'Models' })) {
                    WriteLog "Import-DriversJson: Skipping Make '$makeName' due to invalid structure or missing 'Models' key."
                    return # Corresponds to 'continue' in ForEach-Object script block
                }

                $modelObjectArray = $makeData.Models # This is now an array of objects
                if ($null -eq $modelObjectArray -or $modelObjectArray -isnot [array]) {
                    WriteLog "Import-DriversJson: Skipping Make '$makeName' because 'Models' value is not an array."
                    return
                }

                foreach ($importedModelObject in $modelObjectArray) {
                    if ($null -eq $importedModelObject -or -not $importedModelObject.PSObject.Properties['Name']) {
                        WriteLog "Import-DriversJson: Skipping model for Make '$makeName' due to missing 'Name' property or null object."
                        continue
                    }
                    $importedModelNameFromObject = $importedModelObject.Name
                    if ([string]::IsNullOrWhiteSpace($importedModelNameFromObject)) {
                        WriteLog "Import-DriversJson: Skipping empty model name for Make '$makeName'."
                        continue
                    }

                    $existingModel = $script:allDriverModels | Where-Object { $_.Make -eq $makeName -and $_.Model -eq $importedModelNameFromObject } | Select-Object -First 1

                    if ($null -ne $existingModel) {
                        $existingModel.IsSelected = $true
                        $existingModel.DownloadStatus = "Imported"
                        
                        if ($makeName -eq 'Microsoft' -and $importedModelObject.PSObject.Properties['Link']) {
                            if ($existingModel.Link -ne $importedModelObject.Link) {
                                $existingModel.Link = $importedModelObject.Link
                                WriteLog "Import-DriversJson: Updated Link for existing Microsoft model '$($existingModel.Model)'."
                            }
                        }
                        elseif ($makeName -eq 'Lenovo') {
                            $updateExistingLenovo = $false
                            if ($importedModelObject.PSObject.Properties['ProductName'] -and $existingModel.PSObject.Properties['ProductName'] -and $existingModel.ProductName -ne $importedModelObject.ProductName) {
                                $existingModel.ProductName = $importedModelObject.ProductName
                                $updateExistingLenovo = $true
                            }
                            if ($importedModelObject.PSObject.Properties['MachineType'] -and $existingModel.PSObject.Properties['MachineType'] -and $existingModel.MachineType -ne $importedModelObject.MachineType) {
                                $existingModel.MachineType = $importedModelObject.MachineType
                                $existingModel.Id = $importedModelObject.MachineType # Update Id as well
                                $updateExistingLenovo = $true
                            }
                            if ($updateExistingLenovo) {
                                WriteLog "Import-DriversJson: Updated ProductName/MachineType/Id for existing Lenovo model '$($existingModel.Model)'."
                            }
                        }
                        $existingModelsUpdated++
                        WriteLog "Import-DriversJson: Marked existing model '$($existingModel.Make) - $($existingModel.Model)' as imported."
                    }
                    else {
                        # Model does not exist, create a new one
                        $importedLink = if ($makeName -eq 'Microsoft' -and $importedModelObject.PSObject.Properties['Link']) { $importedModelObject.Link } else { $null }
                        $importedId = $importedModelNameFromObject # Default Id
                        $importedProductName = $null
                        $importedMachineType = $null

                        if ($makeName -eq 'Lenovo') {
                            $importedProductName = if ($importedModelObject.PSObject.Properties['ProductName']) { $importedModelObject.ProductName } else { $null }
                            $importedMachineType = if ($importedModelObject.PSObject.Properties['MachineType']) { $importedModelObject.MachineType } else { $null }
                            
                            if ($null -ne $importedMachineType) {
                                $importedId = $importedMachineType # Override Id for Lenovo
                            }

                            # Fallback parsing if ProductName/MachineType are missing from JSON but Name has the pattern
                            if (($null -eq $importedProductName -or $null -eq $importedMachineType) -and $importedModelNameFromObject -match '(.+?)\s*\((.+?)\)$') {
                                WriteLog "Import-DriversJson: Lenovo model '$importedModelNameFromObject' missing ProductName or MachineType in JSON. Attempting to parse from Name."
                                if ($null -eq $importedProductName) { $importedProductName = $matches[1].Trim() }
                                if ($null -eq $importedMachineType) { 
                                    $importedMachineType = $matches[2].Trim()
                                    $importedId = $importedMachineType # Update Id if MachineType was parsed here
                                }
                            }
                            
                            if ($null -eq $importedProductName -or $null -eq $importedMachineType) {
                                WriteLog "Import-DriversJson: Warning - Lenovo model '$importedModelNameFromObject' is missing ProductName or MachineType after parsing. ID might be based on full name."
                            }
                        }

                        $newDriverModel = [PSCustomObject]@{
                            IsSelected     = $true
                            Make           = $makeName
                            Model          = $importedModelNameFromObject # Full display name
                            Link           = $importedLink
                            Id             = $importedId
                            ProductName    = $importedProductName
                            MachineType    = $importedMachineType
                            Version        = ""
                            Type           = ""
                            Size           = ""
                            Arch           = ""
                            DownloadStatus = "Imported"
                        }
                        $script:allDriverModels += $newDriverModel
                        $newModelsAdded++
                        WriteLog "Import-DriversJson: Added new model '$($newDriverModel.Make) - $($newDriverModel.Model)' from import. ID: $($newDriverModel.Id), Link: $($newDriverModel.Link)"
                    }
                }
            }

            $script:allDriverModels = $script:allDriverModels | Sort-Object @{Expression = { $_.IsSelected }; Descending = $true }, Make, Model
            
            Filter-DriverModels -filterText $script:txtModelFilter.Text

            $message = "Driver import complete.`nNew models added: $newModelsAdded`nExisting models updated: $existingModelsUpdated"
            [System.Windows.MessageBox]::Show($message, "Import Successful", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            WriteLog $message
        }
        catch {
            [System.Windows.MessageBox]::Show("Error importing drivers file: $($_.Exception.Message)", "Import Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
            WriteLog "Error importing drivers file from $($ofd.FileName): $($_.Exception.Message)"
        }
    }
    else {
        WriteLog "Import drivers operation cancelled by user."
    }
}
    
# Some default values
$defaultFFUPrefix = "_FFU" 

# --------------------------------------------------------------------------

# Clean up the Get-UIConfig function to remove duplicates and fix USBDriveList
function Get-UIConfig {
    # Create hash to store configuration
    $config = [ordered]@{
        AllowExternalHardDiskMedia  = $window.FindName('chkAllowExternalHardDiskMedia').IsChecked
        AllowVHDXCaching            = $window.FindName('chkAllowVHDXCaching').IsChecked
        AppListPath                 = $window.FindName('txtAppListJsonPath').Text
        AppsPath                    = $window.FindName('txtApplicationPath').Text
        AppsScriptVariables         = if ($window.FindName('chkDefineAppsScriptVariables').IsChecked) {
                                        $vars = @{}
                                        foreach ($item in $script:appsScriptVariablesDataList) {
                                            $vars[$item.Key] = $item.Value
                                        }
                                        if ($vars.Count -gt 0) { $vars } else { $null }
                                      } else { $null }
        BuildUSBDrive               = $window.FindName('chkBuildUSBDriveEnable').IsChecked
        CleanupAppsISO              = $window.FindName('chkCleanupAppsISO').IsChecked
        CleanupCaptureISO           = $window.FindName('chkCleanupCaptureISO').IsChecked
        CleanupDeployISO            = $window.FindName('chkCleanupDeployISO').IsChecked
        CleanupDrivers              = $window.FindName('chkCleanupDrivers').IsChecked
        CompactOS                   = $window.FindName('chkCompactOS').IsChecked
        CompressDownloadedDriversToWim = $window.FindName('chkCompressDriversToWIM').IsChecked # Renamed from CompressDriversToWIM
        CopyAutopilot               = $window.FindName('chkCopyAutopilot').IsChecked
        CopyDrivers                 = $window.FindName('chkCopyDrivers').IsChecked
        CopyOfficeConfigXML         = $window.FindName('chkCopyOfficeConfigXML').IsChecked # UI Only parameter
        CopyPEDrivers               = $window.FindName('chkCopyPEDrivers').IsChecked
        CopyPPKG                    = $window.FindName('chkCopyPPKG').IsChecked
        CopyUnattend                = $window.FindName('chkCopyUnattend').IsChecked
        CreateCaptureMedia          = $window.FindName('chkCreateCaptureMedia').IsChecked
        CreateDeploymentMedia       = $window.FindName('chkCreateDeploymentMedia').IsChecked
        CustomFFUNameTemplate       = $window.FindName('txtCustomFFUNameTemplate').Text
        Disksize                    = [int64]$window.FindName('txtDiskSize').Text * 1GB # Renamed from DiskSize
        DownloadDrivers             = $window.FindName('chkDownloadDrivers').IsChecked # UI Only parameter
        DriversFolder               = $window.FindName('txtDriversFolder').Text
        DriversJsonPath             = "$($window.FindName('txtDriversFolder').Text)\Drivers.json" # Parameter from Sample_default.json, derived
        FFUCaptureLocation          = $window.FindName('txtFFUCaptureLocation').Text
        FFUDevelopmentPath          = $window.FindName('txtFFUDevPath').Text
        FFUPrefix                   = $window.FindName('txtVMNamePrefix').Text
        InstallApps                 = $window.FindName('chkInstallApps').IsChecked
        InstallDrivers              = $window.FindName('chkInstallDrivers').IsChecked
        InstallOffice               = $window.FindName('chkInstallOffice').IsChecked
        InstallWingetApps           = $window.FindName('chkInstallWingetApps').IsChecked # UI Only parameter
        ISOPath                     = $window.FindName('txtISOPath').Text
        LogicalSectorSizeBytes      = [int]$window.FindName('cmbLogicalSectorSize').SelectedItem.Content
        Make                        = $window.FindName('cmbMake').SelectedItem
        MediaType                   = $window.FindName('cmbMediaType').SelectedItem
        Memory                      = [int64]$window.FindName('txtMemory').Text * 1GB
        Model                       = if ($window.FindName('chkDownloadDrivers').IsChecked) {
                                        $selectedModels = $script:lstDriverModels.Items | Where-Object { $_.IsSelected }
                                        if ($selectedModels.Count -ge 1) { # If one or more models are selected
                                            $selectedModels[0].Model # Use the 'Model' property (display name) of the first selected one
                                        }
                                        else {
                                            $null # No model selected in the list
                                        }
                                    }
                                    else {
                                        $null # Not downloading drivers via UI selection
                                    }
        OfficeConfigXMLFile         = $window.FindName('txtOfficeConfigXMLFilePath').Text # UI Only
        OfficePath                  = $window.FindName('txtOfficePath').Text # UI Only parameter
        Optimize                    = $window.FindName('chkOptimize').IsChecked
        OptionalFeatures            = $window.FindName('txtOptionalFeatures').Text # Parameter from Sample_default.json
        OrchestrationPath           = "$($window.FindName('txtApplicationPath').Text)\Orchestration" # Parameter from Sample_default.json, derived
        PEDriversFolder             = $window.FindName('txtPEDriversFolder').Text
        Processors                  = [int]$window.FindName('txtProcessors').Text
        ProductKey                  = $window.FindName('txtProductKey').Text
        PromptExternalHardDiskMedia = $window.FindName('chkPromptExternalHardDiskMedia').IsChecked
        RemoveApps                  = $window.FindName('chkRemoveApps').IsChecked
        RemoveFFU                   = $window.FindName('chkRemoveFFU').IsChecked
        RemoveUpdates               = $false # Parameter from Sample_default.json, no UI control
        ShareName                   = $window.FindName('txtShareName').Text
        UpdateADK                   = $true # Parameter from Sample_default.json, no UI control
        UpdateEdge                  = $window.FindName('chkUpdateEdge').IsChecked
        UpdateLatestCU              = $window.FindName('chkUpdateLatestCU').IsChecked
        UpdateLatestDefender        = $window.FindName('chkUpdateLatestDefender').IsChecked
        UpdateLatestMicrocode       = $false # Parameter from Sample_default.json, no UI control
        UpdateLatestMSRT            = $window.FindName('chkUpdateLatestMSRT').IsChecked
        UpdateLatestNet             = $window.FindName('chkUpdateLatestNet').IsChecked
        UpdateOneDrive              = $window.FindName('chkUpdateOneDrive').IsChecked
        UpdatePreviewCU             = $window.FindName('chkUpdatePreviewCU').IsChecked
        UserAppListPath             = "$($window.FindName('txtApplicationPath').Text)\UserAppList.json" # Parameter from Sample_default.json, derived
        USBDriveList                = @{}
        Username                    = $window.FindName('txtUsername').Text
        VMHostIPAddress             = $window.FindName('txtVMHostIPAddress').Text
        VMLocation                  = $window.FindName('txtVMLocation').Text
        VMSwitchName                = if ($window.FindName('cmbVMSwitchName').SelectedItem -eq 'Other') {
            $window.FindName('txtCustomVMSwitchName').Text
        }
        else {
            $window.FindName('cmbVMSwitchName').SelectedItem
        }
        WindowsArch                 = $window.FindName('cmbWindowsArch').SelectedItem
        WindowsLang                 = $window.FindName('cmbWindowsLang').SelectedItem
        WindowsRelease              = [int]$window.FindName('cmbWindowsRelease').SelectedItem.Value
        WindowsSKU                  = $window.FindName('cmbWindowsSKU').SelectedItem
        WindowsVersion              = $window.FindName('cmbWindowsVersion').SelectedItem
    }

    # Add selected USB drives to the config
    $window.FindName('lstUSBDrives').Items | Where-Object { $_.IsSelected } | ForEach-Object {
        $config.USBDriveList[$_.Model] = $_.SerialNumber
    }
    
    return $config
}

#Remove old log file if found
if (Test-Path -Path $Logfile) {
    Remove-item -Path $LogFile -Force
}

# Function to refresh the Windows Release ComboBox based on ISO path
function Update-WindowsReleaseCombo {
    param([string]$isoPath)

    if (-not $script:cmbWindowsRelease) { return } # Ensure combo exists

    $oldSelectedItemValue = $null
    if ($null -ne $script:cmbWindowsRelease.SelectedItem) {
        $oldSelectedItemValue = $script:cmbWindowsRelease.SelectedItem.Value
    }

    # Get the appropriate list of releases from the helper module
    $availableReleases = Get-AvailableWindowsReleases -IsoPath $isoPath

    # Update the ComboBox ItemsSource
    $script:cmbWindowsRelease.ItemsSource = $availableReleases
    $script:cmbWindowsRelease.DisplayMemberPath = 'Display'
    $script:cmbWindowsRelease.SelectedValuePath = 'Value'

    # Try to re-select the previously selected item, or default
    $itemToSelect = $availableReleases | Where-Object { $_.Value -eq $oldSelectedItemValue } | Select-Object -First 1
    if ($null -ne $itemToSelect) {
        $script:cmbWindowsRelease.SelectedItem = $itemToSelect
    }
    elseif ($availableReleases.Count -gt 0) {
        # Default to Windows 11 if available, otherwise the first item
        $defaultItem = $availableReleases | Where-Object { $_.Value -eq 11 } | Select-Object -First 1
        if ($null -eq $defaultItem) {
            $defaultItem = $availableReleases[0]
        }
        $script:cmbWindowsRelease.SelectedItem = $defaultItem
    }
    else {
        # No items available (should not happen with current logic)
        $script:cmbWindowsRelease.SelectedIndex = -1
    }
}

# Function to refresh the Windows Version ComboBox based on selected release and ISO path
function Update-WindowsVersionCombo {
    param(
        [int]$selectedRelease,
        [string]$isoPath
    )

    $combo = $script:cmbWindowsVersion # Use script-scoped variable
    if (-not $combo) { return } # Ensure combo exists

    # Get available versions and default from the helper module
    $versionData = Get-AvailableWindowsVersions -SelectedRelease $selectedRelease -IsoPath $isoPath

    # Update the ComboBox ItemsSource and IsEnabled state
    $combo.ItemsSource = $versionData.Versions
    $combo.IsEnabled = $versionData.IsEnabled

    # Set the selected item
    if ($null -ne $versionData.DefaultVersion -and $versionData.Versions -contains $versionData.DefaultVersion) {
        $combo.SelectedItem = $versionData.DefaultVersion
    }
    elseif ($versionData.Versions.Count -gt 0) {
        $combo.SelectedIndex = 0 # Fallback to first item if default isn't valid
    }
    else {
        $combo.SelectedIndex = -1 # No items available
    }
}

# Combined function to refresh both Release and Version combos
$script:RefreshWindowsSettingsCombos = {
    param([string]$isoPath)

    # Update Release combo first
    Update-WindowsReleaseCombo -isoPath $isoPath

    # Get the newly selected release value
    $selectedReleaseValue = 11 # Default to 11 if selection is null
    if ($null -ne $script:cmbWindowsRelease.SelectedItem) {
        $selectedReleaseValue = $script:cmbWindowsRelease.SelectedItem.Value
    }

    # Update Version combo based on the selected release
    Update-WindowsVersionCombo -selectedRelease $selectedReleaseValue -isoPath $isoPath
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
        [Parameter(Mandatory)]
        [System.Windows.FrameworkElement]$parent,
        [Parameter(Mandatory)]
        [array]$allowedFeatures # Pass the list of features explicitly
    )
    $parent.Children.Clear()
    $script:featureCheckBoxes.Clear() # Clear the tracking hashtable

    $sortedFeatures = $allowedFeatures | Sort-Object
    $rows = 10 # Define number of rows for layout
    $columns = [math]::Ceiling($sortedFeatures.Count / $rows)

    $featuresGrid = New-Object System.Windows.Controls.Grid
    $featuresGrid.Margin = "0,5,0,5"
    $featuresGrid.ShowGridLines = $false

    # Define grid rows
    for ($r = 0; $r -lt $rows; $r++) {
        $rowDef = New-Object System.Windows.Controls.RowDefinition
        $rowDef.Height = [System.Windows.GridLength]::Auto
        $featuresGrid.RowDefinitions.Add($rowDef) | Out-Null
    }
    # Define grid columns
    for ($c = 0; $c -lt $columns; $c++) {
        $colDef = New-Object System.Windows.Controls.ColumnDefinition
        $colDef.Width = [System.Windows.GridLength]::Auto
        $featuresGrid.ColumnDefinitions.Add($colDef) | Out-Null
    }

    # Populate grid with checkboxes
    for ($i = 0; $i -lt $sortedFeatures.Count; $i++) {
        $featureName = $sortedFeatures[$i]
        $colIndex = [int]([math]::Floor($i / $rows))
        $rowIndex = $i % $rows

        $chk = New-Object System.Windows.Controls.CheckBox
        $chk.Content = $featureName
        $chk.Margin = "5"
        $chk.Add_Checked({ UpdateOptionalFeaturesString })
        $chk.Add_Unchecked({ UpdateOptionalFeaturesString })

        $script:featureCheckBoxes[$featureName] = $chk # Track the checkbox

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
    }
    else {
        if ($script:installAppsForcedByUpdates) {
            $window.FindName('chkInstallApps').IsChecked = $script:prevInstallAppsStateBeforeUpdates
            $script:installAppsForcedByUpdates = $false
            $script:prevInstallAppsStateBeforeUpdates = $null
        }
        $window.FindName('chkInstallApps').IsEnabled = $true
    }
}
# -----------------------------------------------------------------------------
# SECTION: Winget UI
# -----------------------------------------------------------------------------
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

function Update-WingetVersionFields {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$wingetText,
        [Parameter(Mandatory)]
        [string]$moduleText
    )
    
    # Force UI update on the UI thread
    $window.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Normal, [Action] {
            $script:txtWingetVersion.Text = $wingetText
            $script:txtWingetModuleVersion.Text = $moduleText
            # Force immediate UI refresh
            [System.Windows.Forms.Application]::DoEvents()
        })
}


# Add a function to create a sortable list view for Winget search results
function Add-SortableColumn {
    param(
        [System.Windows.Controls.GridView]$gridView,
        [string]$header,
        [string]$binding,
        [int]$width = 'Auto',
        [bool]$isCheckbox = $false, 
        [System.Windows.HorizontalAlignment]$headerHorizontalAlignment = [System.Windows.HorizontalAlignment]::Stretch
    )

    $column = New-Object System.Windows.Controls.GridViewColumn
    $commonPadding = New-Object System.Windows.Thickness(5, 2, 5, 2)

    $headerControl = New-Object System.Windows.Controls.GridViewColumnHeader
    $headerControl.Tag = $binding # Used for sorting

    if ($isCheckbox) {
        # Cell template for a column of checkboxes
        $cellTemplate = New-Object System.Windows.DataTemplate
        $gridFactory = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.Grid])
        
        $checkBoxFactory = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.CheckBox])
        $checkBoxFactory.SetBinding([System.Windows.Controls.CheckBox]::IsCheckedProperty, (New-Object System.Windows.Data.Binding("IsSelected")))
        $checkBoxFactory.SetValue([System.Windows.FrameworkElement]::HorizontalAlignmentProperty, [System.Windows.HorizontalAlignment]::Center)
        $checkBoxFactory.SetValue([System.Windows.FrameworkElement]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Center)

        $checkBoxFactory.AddHandler([System.Windows.Controls.CheckBox]::ClickEvent, [System.Windows.RoutedEventHandler] {
                param($eventSourceLocal, $eventArgsLocal) 
                # Sync logic would be needed here if this column had a header checkbox
            })
        $gridFactory.AppendChild($checkBoxFactory)
        $cellTemplate.VisualTree = $gridFactory
        $column.CellTemplate = $cellTemplate
        # $column.HorizontalContentAlignment = [System.Windows.HorizontalAlignment]::Center # REMOVED
    }
    else {
        # For regular text columns
        $headerControl.HorizontalContentAlignment = $headerHorizontalAlignment 
        $headerControl.Content = $header 

        $headerTextElementFactory = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.TextBlock])
        $headerTextElementFactory.SetValue([System.Windows.Controls.TextBlock]::TextProperty, $header)
        $headerTextBlockPadding = New-Object System.Windows.Thickness($commonPadding.Left, $commonPadding.Top, $commonPadding.Right, $commonPadding.Bottom)
        $headerTextElementFactory.SetValue([System.Windows.Controls.TextBlock]::PaddingProperty, $headerTextBlockPadding)
        $headerTextElementFactory.SetValue([System.Windows.FrameworkElement]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Center)

        $headerDataTemplate = New-Object System.Windows.DataTemplate
        $headerDataTemplate.VisualTree = $headerTextElementFactory
        $headerControl.ContentTemplate = $headerDataTemplate

        $cellTemplate = New-Object System.Windows.DataTemplate
        $textBlockFactory = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.TextBlock])
        $textBlockFactory.SetBinding([System.Windows.Controls.TextBlock]::TextProperty, (New-Object System.Windows.Data.Binding($binding)))
        # Adjust left padding to 0 for cell text to align with header text
        $cellTextBlockPadding = New-Object System.Windows.Thickness(0, $commonPadding.Top, $commonPadding.Right, $commonPadding.Bottom)
        $textBlockFactory.SetValue([System.Windows.Controls.TextBlock]::PaddingProperty, $cellTextBlockPadding) 
        $textBlockFactory.SetValue([System.Windows.FrameworkElement]::HorizontalAlignmentProperty, [System.Windows.HorizontalAlignment]::Left) 
        $textBlockFactory.SetValue([System.Windows.FrameworkElement]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Center)

        $cellTemplate.VisualTree = $textBlockFactory
        $column.CellTemplate = $cellTemplate
        # $column.HorizontalContentAlignment = $headerHorizontalAlignment # REMOVED
    }

    $column.Header = $headerControl

    if ($width -ne 'Auto') {
        $column.Width = $width
    }

    $gridView.Columns.Add($column)
}

# Initialize tracking variables for sorting
$script:lastSortProperty = $null
$script:lastSortAscending = $true

# Function to sort ListView items
function Invoke-ListViewSort {
    param(
        [System.Windows.Controls.ListView]$listView,
        [string]$property
    )
    
    # Toggle sort direction if clicking the same column
    if ($script:lastSortProperty -eq $property) {
        $script:lastSortAscending = -not $script:lastSortAscending
    }
    else {
        $script:lastSortAscending = $true
    }
    $script:lastSortProperty = $property
    
    # Get items from ItemsSource or Items collection
    $currentItemsSource = $listView.ItemsSource
    $itemsToSort = @()
    if ($null -ne $currentItemsSource) {
        $itemsToSort = @($currentItemsSource)
    }
    else {
        $itemsToSort = @($listView.Items)
    }

    if ($itemsToSort.Count -eq 0) {
        return
    }

    $selectedItems = @($itemsToSort | Where-Object { $_.IsSelected })
    $unselectedItems = @($itemsToSort | Where-Object { -not $_.IsSelected })
    
    # Define the primary sort criterion
    $primarySortDefinition = @{
        Expression = {
            $val = $_.$property
            if ($null -eq $val) { '' } else { $val }
        }
        Ascending  = $script:lastSortAscending
    }

    $sortCriteria = [System.Collections.Generic.List[hashtable]]::new()
    $sortCriteria.Add($primarySortDefinition)

    # Determine secondary sort property based on the ListView
    $secondarySortPropertyName = $null
    if ($listView.Name -eq 'lstDriverModels') {
        $secondarySortPropertyName = "Model"
    }
    elseif ($listView.Name -eq 'lstWingetResults') {
        $secondarySortPropertyName = "Name"
    }
    elseif ($listView.Name -eq 'lstAppsScriptVariables') {
        if ($property -eq "Key") {
            $secondarySortPropertyName = "Value"
        }
        elseif ($property -eq "Value") {
            $secondarySortPropertyName = "Key"
        }
        else { # Default secondary sort for IsSelected or other properties
            $secondarySortPropertyName = "Key"
        }
    }

    if ($null -ne $secondarySortPropertyName -and $property -ne $secondarySortPropertyName) {
        $itemsHaveSecondaryProperty = $false
        if ($unselectedItems.Count -gt 0) {
            if ($null -ne $unselectedItems[0].PSObject.Properties[$secondarySortPropertyName]) {
                $itemsHaveSecondaryProperty = $true
            }
        }
        elseif ($selectedItems.Count -gt 0) {
            if ($null -ne $selectedItems[0].PSObject.Properties[$secondarySortPropertyName]) {
                $itemsHaveSecondaryProperty = $true
            }
        }

        if ($itemsHaveSecondaryProperty) {
            # Create a scriptblock for the secondary sort expression dynamically
            $expressionScriptBlock = [scriptblock]::Create("`$_.$secondarySortPropertyName")
            
            $secondarySortDefinition = @{
                Expression = {
                    $val = Invoke-Command -ScriptBlock $expressionScriptBlock -ArgumentList $_
                    if ($null -eq $val) { '' } else { $val }
                }
                Ascending  = $true # Secondary sort always ascending
            }
            $sortCriteria.Add($secondarySortDefinition)
        }
    }
    
    $sortedUnselected = $unselectedItems | Sort-Object -Property $sortCriteria.ToArray()
    # Ensure $sortedUnselected is not null before attempting to add its range
    if ($null -eq $sortedUnselected) {
        $sortedUnselected = @()
    }
    
    # Combine sorted items: selected items first, then sorted unselected items
    $newSortedList = [System.Collections.Generic.List[object]]::new()
    $newSortedList.AddRange($selectedItems)
    $newSortedList.AddRange($sortedUnselected)
    
    # Set the new sorted list as the ItemsSource
    # Try nulling out ItemsSource first to force a more complete refresh
    $listView.ItemsSource = $null
    $listView.ItemsSource = $newSortedList.ToArray()
}

# Function to add a selectable GridViewColumn with a "Select All" header CheckBox
function Add-SelectableGridViewColumn {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.ListView]$ListView,
        [Parameter(Mandatory)]
        [string]$HeaderCheckBoxScriptVariableName,
        [Parameter(Mandatory)]
        [double]$ColumnWidth,
        [string]$IsSelectedPropertyName = "IsSelected"
    )

    # Ensure the ListView has a GridView
    if ($null -eq $ListView.View -or -not ($ListView.View -is [System.Windows.Controls.GridView])) {
        WriteLog "Add-SelectableGridViewColumn: ListView '$($ListView.Name)' does not have a GridView or View is null. Cannot add column."
        # Optionally, create a new GridView if one doesn't exist, though XAML usually defines it.
        # $ListView.View = New-Object System.Windows.Controls.GridView
        return
    }
    $gridView = $ListView.View

    # Create the "Select All" CheckBox for the header
    $headerCheckBox = New-Object System.Windows.Controls.CheckBox
    $headerCheckBox.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
    # Store an object containing the IsSelectedPropertyName and the ListView's Name in the Tag
    $headerTagObject = [PSCustomObject]@{
        PropertyName = $IsSelectedPropertyName
        ListViewName = $ListView.Name
    }
    $headerCheckBox.Tag = $headerTagObject
    # Removed debug WriteLog for storing tag data

    $headerCheckBox.Add_Checked({
            param($senderCheckBoxLocal, $eventArgsCheckedLocal)

            $tagData = $senderCheckBoxLocal.Tag
            if ($null -eq $tagData -or -not $tagData.PSObject.Properties['PropertyName'] -or -not $tagData.PSObject.Properties['ListViewName']) {
                WriteLog "Add-SelectableGridViewColumn: CRITICAL - Tag data on header checkbox is missing, null, or malformed. Aborting HeaderChecked event."
                return
            }

            $localPropertyName = $tagData.PropertyName
            $localListViewName = $tagData.ListViewName
            # Removed debug WriteLog for HeaderChecked event fired

            if ([string]::IsNullOrEmpty($localPropertyName)) {
                WriteLog "Add-SelectableGridViewColumn: CRITICAL - PropertyName from Tag is null or empty in HeaderChecked event for ListView '$localListViewName'. Aborting."
                return
            }
            if ([string]::IsNullOrEmpty($localListViewName)) {
                WriteLog "Add-SelectableGridViewColumn: CRITICAL - ListViewName from Tag is null or empty in HeaderChecked event. Aborting."
                return
            }

            $actualListView = $window.FindName($localListViewName)
            if ($null -eq $actualListView) {
                WriteLog "Add-SelectableGridViewColumn: CRITICAL - ListView control '$localListViewName' not found in window during HeaderChecked event. Aborting."
                return
            }
            # Removed debug WriteLog for successfully finding ListView in HeaderChecked

            $collectionToUpdate = $null
            if ($null -ne $actualListView.ItemsSource) {
                $collectionToUpdate = $actualListView.ItemsSource
            }
            elseif ($actualListView.HasItems) {
                $collectionToUpdate = $actualListView.Items
            }

            if ($null -ne $collectionToUpdate) {
                foreach ($item in $collectionToUpdate) {
                    try {
                        $item.($localPropertyName) = $true
                    }
                    catch {
                        WriteLog "Error setting '$localPropertyName' to true for item in $($actualListView.Name): $($_.Exception.Message)"
                    }
                }
                $actualListView.Items.Refresh()
                WriteLog "Header checkbox for $($actualListView.Name) checked. All items' '$localPropertyName' set to true."
            }
        })
    $headerCheckBox.Add_Unchecked({
            param($senderCheckBoxLocal, $eventArgsUncheckedLocal)

            $tagData = $senderCheckBoxLocal.Tag
            if ($null -eq $tagData -or -not $tagData.PSObject.Properties['PropertyName'] -or -not $tagData.PSObject.Properties['ListViewName']) {
                WriteLog "Add-SelectableGridViewColumn: CRITICAL - Tag data on header checkbox is missing, null, or malformed. Aborting HeaderUnchecked event."
                return
            }

            $localPropertyName = $tagData.PropertyName
            $localListViewName = $tagData.ListViewName
            # Removed debug WriteLog for HeaderUnchecked event fired

            if ([string]::IsNullOrEmpty($localPropertyName)) {
                WriteLog "Add-SelectableGridViewColumn: CRITICAL - PropertyName from Tag is null or empty in HeaderUnchecked event for ListView '$localListViewName'. Aborting."
                return
            }
            if ([string]::IsNullOrEmpty($localListViewName)) {
                WriteLog "Add-SelectableGridViewColumn: CRITICAL - ListViewName from Tag is null or empty in HeaderUnchecked event. Aborting."
                return
            }
            
            $actualListView = $window.FindName($localListViewName)
            if ($null -eq $actualListView) {
                WriteLog "Add-SelectableGridViewColumn: CRITICAL - ListView control '$localListViewName' not found in window during HeaderUnchecked event. Aborting."
                return
            }
            # Removed debug WriteLog for successfully finding ListView in HeaderUnchecked

            # Only proceed if the uncheck was initiated by the user (IsChecked is explicitly false)
            if ($senderCheckBoxLocal.IsChecked -eq $false) {
                $collectionToUpdate = $null
                if ($null -ne $actualListView.ItemsSource) {
                    $collectionToUpdate = $actualListView.ItemsSource
                }
                elseif ($actualListView.HasItems) {
                    $collectionToUpdate = $actualListView.Items
                }

                if ($null -ne $collectionToUpdate) {
                    foreach ($item in $collectionToUpdate) {
                        try {
                            $item.($localPropertyName) = $false
                        }
                        catch {
                            WriteLog "Error setting '$localPropertyName' to false for item in $($actualListView.Name): $($_.Exception.Message)"
                        }
                    }
                    $actualListView.Items.Refresh()
                    WriteLog "Header checkbox for $($actualListView.Name) unchecked by user. All items' '$localPropertyName' set to false."
                }
            }
        })

    # Store the header checkbox in a script-scoped variable
    Set-Variable -Name $HeaderCheckBoxScriptVariableName -Value $headerCheckBox -Scope Script -Force
    WriteLog "Add-SelectableGridViewColumn: Stored header checkbox in script variable '$HeaderCheckBoxScriptVariableName'."

    # Create the GridViewColumn
    $selectableColumn = New-Object System.Windows.Controls.GridViewColumn
    $selectableColumn.Header = $headerCheckBox
    $selectableColumn.Width = $ColumnWidth

    # Create the CellTemplate for item CheckBoxes
    $cellTemplate = New-Object System.Windows.DataTemplate
    
    # Use a Border to ensure CheckBox centers and stretches
    $borderFactory = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.Border])
    $borderFactory.SetValue([System.Windows.FrameworkElement]::HorizontalAlignmentProperty, [System.Windows.HorizontalAlignment]::Stretch)
    $borderFactory.SetValue([System.Windows.FrameworkElement]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Stretch)
    
    $checkBoxFactory = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.CheckBox])
    $checkBoxFactory.SetBinding([System.Windows.Controls.CheckBox]::IsCheckedProperty, (New-Object System.Windows.Data.Binding($IsSelectedPropertyName)))
    $checkBoxFactory.SetValue([System.Windows.FrameworkElement]::HorizontalAlignmentProperty, [System.Windows.HorizontalAlignment]::Center)
    $checkBoxFactory.SetValue([System.Windows.FrameworkElement]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Center)
    
    # Create an object to store both the header checkbox name and the ListView name
    $tagObject = [PSCustomObject]@{
        HeaderCheckboxName = $HeaderCheckBoxScriptVariableName
        ListViewName       = $ListView.Name # Store the name of the ListView
    }
    # Store this object in the Tag of each item checkbox
    $checkBoxFactory.SetValue([System.Windows.FrameworkElement]::TagProperty, $tagObject)

    # Add handler to update the header checkbox state when an item checkbox is clicked
    $checkBoxFactory.AddHandler([System.Windows.Controls.CheckBox]::ClickEvent, [System.Windows.RoutedEventHandler] {
            param($eventSourceLocal, $eventArgsLocal)
            
            $itemCheckBox = $eventSourceLocal -as [System.Windows.Controls.CheckBox]
            if ($null -eq $itemCheckBox) {
                WriteLog "Add-SelectableGridViewColumn: CRITICAL - Event source in item checkbox click handler is not a CheckBox."
                return
            }

            $tagData = $itemCheckBox.Tag
            if ($null -eq $tagData -or -not $tagData.PSObject.Properties['HeaderCheckboxName'] -or -not $tagData.PSObject.Properties['ListViewName']) {
                WriteLog "Add-SelectableGridViewColumn: Error - Tag data on itemCheckBox is missing or malformed."
                return
            }
            
            $headerCheckboxNameFromTag = $tagData.HeaderCheckboxName
            $listViewNameFromTag = $tagData.ListViewName

            WriteLog "Add-SelectableGridViewColumn: Item Click. ListView: '$listViewNameFromTag', HeaderChkName: '$headerCheckboxNameFromTag'"

            if ([string]::IsNullOrEmpty($headerCheckboxNameFromTag)) {
                WriteLog "Add-SelectableGridViewColumn: Error - Header checkbox name from Tag is null or empty for ListView '$listViewNameFromTag'."
                return 
            }
            if ([string]::IsNullOrEmpty($listViewNameFromTag)) {
                WriteLog "Add-SelectableGridViewColumn: Error - ListView name from Tag is null or empty."
                return
            }

            # Retrieve the actual ListView control using its name stored in the Tag
            $targetListView = $window.FindName($listViewNameFromTag)
            if ($null -eq $targetListView) {
                WriteLog "Add-SelectableGridViewColumn: Error - Could not find ListView control named '$listViewNameFromTag'."
                return
            }

            $headerChk = Get-Variable -Name $headerCheckboxNameFromTag -Scope Script -ValueOnly -ErrorAction SilentlyContinue
            if ($null -ne $headerChk) {
                Update-SelectAllHeaderCheckBoxState -ListView $targetListView -HeaderCheckBox $headerChk
            } else {
                WriteLog "Add-SelectableGridViewColumn: Error - Could not retrieve script variable for header checkbox named '$headerCheckboxNameFromTag' for ListView '$listViewNameFromTag'."
            }
        })
    
    $borderFactory.AppendChild($checkBoxFactory)
    $cellTemplate.VisualTree = $borderFactory
    $selectableColumn.CellTemplate = $cellTemplate

    # Insert the new column at the beginning of the GridView
    $gridView.Columns.Insert(0, $selectableColumn)
    WriteLog "Add-SelectableGridViewColumn: Successfully added selectable column to '$($ListView.Name)'."
}

# Function to update the IsChecked state of a "Select All" header CheckBox
function Update-SelectAllHeaderCheckBoxState {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.ListView]$ListView,
        [Parameter(Mandatory)]
        [System.Windows.Controls.CheckBox]$HeaderCheckBox
    )

    $collectionToInspect = $null
    if ($null -ne $ListView.ItemsSource) {
        $collectionToInspect = @($ListView.ItemsSource)
    }
    elseif ($ListView.HasItems) { # Check if Items collection has items and ItemsSource is null
        $collectionToInspect = @($ListView.Items)
    }

    # If no items to inspect (either ItemsSource was null and Items was empty, or ItemsSource was empty)
    if ($null -eq $collectionToInspect -or $collectionToInspect.Count -eq 0) {
        $HeaderCheckBox.IsChecked = $false
        return
    }

    $selectedCount = ($collectionToInspect | Where-Object { $_.IsSelected }).Count
    $totalItemCount = $collectionToInspect.Count # Get the total count from the collection being inspected

    if ($totalItemCount -eq 0) { # Handle empty list case specifically
        $HeaderCheckBox.IsChecked = $false
    }
    elseif ($selectedCount -eq $totalItemCount) {
        $HeaderCheckBox.IsChecked = $true
    }
    elseif ($selectedCount -eq 0) {
        $HeaderCheckBox.IsChecked = $false
    }
    else {
        # Indeterminate state
        $HeaderCheckBox.IsChecked = $null
    }
}

# Function to update priorities sequentially in a ListView
function Update-ListViewPriorities {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.ListView]$ListView
    )
    
    $currentPriority = 1
    foreach ($item in $ListView.Items) {
        if ($null -ne $item -and $item.PSObject.Properties['Priority']) {
            $item.Priority = $currentPriority
            $currentPriority++
        }
    }
    $ListView.Items.Refresh()
}

# Function to move selected item to the top
function Move-ListViewItemTop {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.ListView]$ListView
    )
    
    $selectedItem = $ListView.SelectedItem
    if ($null -eq $selectedItem) { return }
    
    $currentIndex = $ListView.Items.IndexOf($selectedItem)
    if ($currentIndex -gt 0) {
        $ListView.Items.RemoveAt($currentIndex)
        $ListView.Items.Insert(0, $selectedItem)
        $ListView.SelectedItem = $selectedItem
        Update-ListViewPriorities -ListView $ListView
    }
}

# Function to move selected item up one position
function Move-ListViewItemUp {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.ListView]$ListView
    )
    
    $selectedItem = $ListView.SelectedItem
    if ($null -eq $selectedItem) { return }
    
    $currentIndex = $ListView.Items.IndexOf($selectedItem)
    if ($currentIndex -gt 0) {
        $ListView.Items.RemoveAt($currentIndex)
        $ListView.Items.Insert($currentIndex - 1, $selectedItem)
        $ListView.SelectedItem = $selectedItem
        Update-ListViewPriorities -ListView $ListView
    }
}

# Function to move selected item down one position
function Move-ListViewItemDown {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.ListView]$ListView
    )
    
    $selectedItem = $ListView.SelectedItem
    if ($null -eq $selectedItem) { return }
    
    $currentIndex = $ListView.Items.IndexOf($selectedItem)
    if ($currentIndex -lt ($ListView.Items.Count - 1)) {
        $ListView.Items.RemoveAt($currentIndex)
        $ListView.Items.Insert($currentIndex + 1, $selectedItem)
        $ListView.SelectedItem = $selectedItem
        Update-ListViewPriorities -ListView $ListView
    }
}

# Function to move selected item to the bottom
function Move-ListViewItemBottom {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.ListView]$ListView
    )
    
    $selectedItem = $ListView.SelectedItem
    if ($null -eq $selectedItem) { return }
    
    $currentIndex = $ListView.Items.IndexOf($selectedItem)
    if ($currentIndex -lt ($ListView.Items.Count - 1)) {
        $ListView.Items.RemoveAt($currentIndex)
        $ListView.Items.Add($selectedItem)
        $ListView.SelectedItem = $selectedItem
        Update-ListViewPriorities -ListView $ListView
    }
}

# Function to update the enabled state of the Copy Apps button
function Update-CopyButtonState {
    $listView = $window.FindName('lstApplications')
    $copyButton = $window.FindName('btnCopyBYOApps')
    if ($listView -and $copyButton) {
        $hasSource = $false
        foreach ($item in $listView.Items) {
            if ($null -ne $item -and $item.PSObject.Properties['Source'] -and -not [string]::IsNullOrWhiteSpace($item.Source)) {
                $hasSource = $true
                break
            }
        }
        $copyButton.IsEnabled = $hasSource
    }
}

# --------------------------------------------------------------------------
# SECTION: Parallel Processing
# --------------------------------------------------------------------------

# --------------------------------------------------------------------------

$window.Add_Loaded({
        # Assign UI elements to script variables
        $script:cmbWindowsRelease = $window.FindName('cmbWindowsRelease')
        $script:cmbWindowsVersion = $window.FindName('cmbWindowsVersion')
        $script:txtISOPath = $window.FindName('txtISOPath')
        $script:btnBrowseISO = $window.FindName('btnBrowseISO')
        $script:cmbWindowsArch = $window.FindName('cmbWindowsArch')
        $script:cmbWindowsLang = $window.FindName('cmbWindowsLang')
        $script:cmbWindowsSKU = $window.FindName('cmbWindowsSKU')
        $script:cmbMediaType = $window.FindName('cmbMediaType')
        $script:txtOptionalFeatures = $window.FindName('txtOptionalFeatures')
        $script:featuresPanel = $window.FindName('stackFeaturesContainer')
        $script:chkDownloadDrivers = $window.FindName('chkDownloadDrivers')
        $script:cmbMake = $window.FindName('cmbMake')
        # $script:cmbModel = $window.FindName('cmbModel') # cmbModel TextBox removed from XAML
        $script:spMakeSection = $window.FindName('spMakeSection') # Updated StackPanel name
        $script:btnGetModels = $window.FindName('btnGetModels')
        $script:spModelFilterSection = $window.FindName('spModelFilterSection') # New StackPanel for filter
        $script:txtModelFilter = $window.FindName('txtModelFilter') # New TextBox for filter
        $script:lstDriverModels = $window.FindName('lstDriverModels')
        # Set ListViewItem style to stretch content horizontally so cell templates fill the cell
        $itemStyleDriverModels = New-Object System.Windows.Style([System.Windows.Controls.ListViewItem])
        $itemStyleDriverModels.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.ListViewItem]::HorizontalContentAlignmentProperty, [System.Windows.HorizontalAlignment]::Stretch)))
        $script:lstDriverModels.ItemContainerStyle = $itemStyleDriverModels

        # Driver Models ListView setup
        $driverModelsGridView = New-Object System.Windows.Controls.GridView
        $script:lstDriverModels.View = $driverModelsGridView # Assign GridView to ListView first

        # Add the selectable column using the new function
        Add-SelectableGridViewColumn -ListView $script:lstDriverModels -HeaderCheckBoxScriptVariableName "chkSelectAllDriverModels" -ColumnWidth 70

        # Add other sortable columns with left-aligned headers
        Add-SortableColumn -gridView $driverModelsGridView -header "Make" -binding "Make" -width 100 -headerHorizontalAlignment Left
        Add-SortableColumn -gridView $driverModelsGridView -header "Model" -binding "Model" -width 200 -headerHorizontalAlignment Left
        Add-SortableColumn -gridView $driverModelsGridView -header "Download Status" -binding "DownloadStatus" -width 150 -headerHorizontalAlignment Left
        $script:lstDriverModels.AddHandler(
            [System.Windows.Controls.GridViewColumnHeader]::ClickEvent,
            [System.Windows.RoutedEventHandler] {
                param($eventSource, $e)
                $header = $e.OriginalSource
                if ($header -is [System.Windows.Controls.GridViewColumnHeader] -and $header.Tag) {
                    Invoke-ListViewSort -listView $script:lstDriverModels -property $header.Tag
                }
            }
        )
        $script:spDriverActionButtons = $window.FindName('spDriverActionButtons')
        $script:btnSaveDriversJson = $window.FindName('btnSaveDriversJson')
        $script:btnImportDriversJson = $window.FindName('btnImportDriversJson')
        $script:btnDownloadSelectedDrivers = $window.FindName('btnDownloadSelectedDrivers')
        $script:btnClearDriverList = $window.FindName('btnClearDriverList')
        # New button
        $script:chkInstallOffice = $window.FindName('chkInstallOffice')
        $script:chkInstallApps = $window.FindName('chkInstallApps')
        $script:OfficePathStackPanel = $window.FindName('OfficePathStackPanel')
        $script:OfficePathGrid = $window.FindName('OfficePathGrid')
        $script:CopyOfficeConfigXMLStackPanel = $window.FindName('CopyOfficeConfigXMLStackPanel')
        $script:OfficeConfigurationXMLFileStackPanel = $window.FindName('OfficeConfigurationXMLFileStackPanel')
        $script:OfficeConfigurationXMLFileGrid = $window.FindName('OfficeConfigurationXMLFileGrid')
        $script:chkCopyOfficeConfigXML = $window.FindName('chkCopyOfficeConfigXML')
        $script:chkLatestCU = $window.FindName('chkUpdateLatestCU')
        $script:chkPreviewCU = $window.FindName('chkUpdatePreviewCU')
        $script:btnCheckUSBDrives = $window.FindName('btnCheckUSBDrives')
        $script:lstUSBDrives = $window.FindName('lstUSBDrives')
        $script:chkSelectAllUSBDrives = $window.FindName('chkSelectAllUSBDrives')
        $script:chkBuildUSBDriveEnable = $window.FindName('chkBuildUSBDriveEnable')
        $script:usbSection = $window.FindName('usbDriveSection')
        $script:chkSelectSpecificUSBDrives = $window.FindName('chkSelectSpecificUSBDrives')
        $script:usbSelectionPanel = $window.FindName('usbDriveSelectionPanel')
        $script:chkAllowExternalHardDiskMedia = $window.FindName('chkAllowExternalHardDiskMedia')
        $script:chkPromptExternalHardDiskMedia = $window.FindName('chkPromptExternalHardDiskMedia')
        $script:chkInstallWingetApps = $window.FindName('chkInstallWingetApps')
        $script:wingetPanel = $window.FindName('wingetPanel')
        $script:btnCheckWingetModule = $window.FindName('btnCheckWingetModule')
        $script:txtWingetVersion = $window.FindName('txtWingetVersion')
        $script:txtWingetModuleVersion = $window.FindName('txtWingetModuleVersion')
        $script:applicationPathPanel = $window.FindName('applicationPathPanel')
        $script:appListJsonPathPanel = $window.FindName('appListJsonPathPanel')
        $script:btnBrowseApplicationPath = $window.FindName('btnBrowseApplicationPath')
        $script:btnBrowseAppListJsonPath = $window.FindName('btnBrowseAppListJsonPath')
        $script:chkBringYourOwnApps = $window.FindName('chkBringYourOwnApps')
        $script:byoApplicationPanel = $window.FindName('byoApplicationPanel')
        $script:wingetSearchPanel = $window.FindName('wingetSearchPanel')
        $script:txtWingetSearch = $window.FindName('txtWingetSearch')
        $script:btnWingetSearch = $window.FindName('btnWingetSearch')
        $script:lstWingetResults = $window.FindName('lstWingetResults')
        # Set ListViewItem style to stretch content horizontally so cell templates fill the cell
        $itemStyleWingetResults = New-Object System.Windows.Style([System.Windows.Controls.ListViewItem])
        $itemStyleWingetResults.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.ListViewItem]::HorizontalContentAlignmentProperty, [System.Windows.HorizontalAlignment]::Stretch)))
        $script:lstWingetResults.ItemContainerStyle = $itemStyleWingetResults
        $script:btnSaveWingetList = $window.FindName('btnSaveWingetList')
        $script:btnImportWingetList = $window.FindName('btnImportWingetList')
        $script:btnClearWingetList = $window.FindName('btnClearWingetList')
        $script:btnDownloadSelected = $window.FindName('btnDownloadSelected')
        $script:btnBrowseAppSource = $window.FindName('btnBrowseAppSource')
        $script:btnBrowseFFUDevPath = $window.FindName('btnBrowseFFUDevPath')
        $script:btnBrowseFFUCaptureLocation = $window.FindName('btnBrowseFFUCaptureLocation')
        $script:btnBrowseOfficePath = $window.FindName('btnBrowseOfficePath')
        $script:btnBrowseDriversFolder = $window.FindName('btnBrowseDriversFolder')
        $script:btnBrowsePEDriversFolder = $window.FindName('btnBrowsePEDriversFolder')
        $script:btnAddApplication = $window.FindName('btnAddApplication')
        $script:btnSaveBYOApplications = $window.FindName('btnSaveBYOApplications')
        $script:btnLoadBYOApplications = $window.FindName('btnLoadBYOApplications')
        $script:btnClearBYOApplications = $window.FindName('btnClearBYOApplications')
        $script:btnCopyBYOApps = $window.FindName('btnCopyBYOApps')
        $script:lstApplications = $window.FindName('lstApplications')
        $script:btnMoveTop = $window.FindName('btnMoveTop')
        $script:btnMoveUp = $window.FindName('btnMoveUp')
        $script:btnMoveDown = $window.FindName('btnMoveDown')
        $script:btnMoveBottom = $window.FindName('btnMoveBottom')
        $script:txtStatus = $window.FindName('txtStatus') # Assign txtStatus control
        # Assign Progress Bar and Overall Status Text controls to script variables
        $script:pbOverallProgress = $window.FindName('progressBar') # Use the correct x:Name from XAML
        $script:txtOverallStatus = $window.FindName('txtStatus')     # Use the correct x:Name from XAML (assuming it's txtStatus)
        $script:cmbVMSwitchName = $window.FindName('cmbVMSwitchName')
        $script:txtVMHostIPAddress = $window.FindName('txtVMHostIPAddress')
        $script:txtCustomVMSwitchName = $window.FindName('txtCustomVMSwitchName')
        # Assign Driver Checkboxes
        $script:chkInstallDrivers = $window.FindName('chkInstallDrivers')
        $script:chkCopyDrivers = $window.FindName('chkCopyDrivers')
        $script:chkCompressDriversToWIM = $window.FindName('chkCompressDriversToWIM')
        $script:chkRemoveApps = $window.FindName('chkRemoveApps')

        # AppsScriptVariables Controls
        $script:chkDefineAppsScriptVariables = $window.FindName('chkDefineAppsScriptVariables')
        $script:appsScriptVariablesPanel = $window.FindName('appsScriptVariablesPanel')
        $script:txtAppsScriptKey = $window.FindName('txtAppsScriptKey')
        $script:txtAppsScriptValue = $window.FindName('txtAppsScriptValue')
        $script:btnAddAppsScriptVariable = $window.FindName('btnAddAppsScriptVariable')
        $script:lstAppsScriptVariables = $window.FindName('lstAppsScriptVariables')
        # Bind ItemsSource to the data list
        $script:lstAppsScriptVariables.ItemsSource = $script:appsScriptVariablesDataList.ToArray()
        
        # Set ListViewItem style to stretch content horizontally so cell templates fill the cell
        $itemStyleAppsScriptVars = New-Object System.Windows.Style([System.Windows.Controls.ListViewItem])
        $itemStyleAppsScriptVars.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.ListViewItem]::HorizontalContentAlignmentProperty, [System.Windows.HorizontalAlignment]::Stretch)))
        $script:lstAppsScriptVariables.ItemContainerStyle = $itemStyleAppsScriptVars

        # The GridView for lstAppsScriptVariables is defined in XAML. We need to get it and add the column.
        if ($script:lstAppsScriptVariables.View -is [System.Windows.Controls.GridView]) {
            Add-SelectableGridViewColumn -ListView $script:lstAppsScriptVariables -HeaderCheckBoxScriptVariableName "chkSelectAllAppsScriptVariables" -ColumnWidth 60
            
            # Make Key and Value columns sortable
            $appsScriptVarsGridView = $script:lstAppsScriptVariables.View
            
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
            $script:lstAppsScriptVariables.AddHandler(
                [System.Windows.Controls.GridViewColumnHeader]::ClickEvent,
                [System.Windows.RoutedEventHandler] {
                    param($eventSource, $e)
                    $header = $e.OriginalSource
                    if ($header -is [System.Windows.Controls.GridViewColumnHeader] -and $header.Tag) {
                        Invoke-ListViewSort -listView $script:lstAppsScriptVariables -property $header.Tag
                    }
                }
            )
        }
        else {
            WriteLog "Warning: lstAppsScriptVariables.View is not a GridView. Selectable column not added, and sorting cannot be enabled."
        }

        $script:btnRemoveSelectedAppsScriptVariables = $window.FindName('btnRemoveSelectedAppsScriptVariables') # Updated variable name
        $script:btnClearAppsScriptVariables = $window.FindName('btnClearAppsScriptVariables')

        # Get Windows Settings defaults and lists from helper module
        $script:windowsSettingsDefaults = Get-WindowsSettingsDefaults
        # Get General defaults from helper module
        $script:generalDefaults = Get-GeneralDefaults -FFUDevelopmentPath $FFUDevelopmentPath

        # Initialize Windows Settings UI using data from helper module
        & $script:RefreshWindowsSettingsCombos($script:windowsSettingsDefaults.DefaultISOPath) # Use combined refresh function
        $script:txtISOPath.Add_TextChanged({ & $script:RefreshWindowsSettingsCombos($script:txtISOPath.Text) })
        $script:cmbWindowsRelease.Add_SelectionChanged({
                $selectedReleaseValue = 11 # Default if null
                if ($null -ne $script:cmbWindowsRelease.SelectedItem) {
                    $selectedReleaseValue = $script:cmbWindowsRelease.SelectedItem.Value
                }
                # Only need to update the Version combo when Release changes
                Update-WindowsVersionCombo -selectedRelease $selectedReleaseValue -isoPath $script:txtISOPath.Text
            })
        $script:btnBrowseISO.Add_Click({
                $ofd = New-Object System.Windows.Forms.OpenFileDialog
                $ofd.Filter = "ISO files (*.iso)|*.iso"
                $ofd.Title = "Select Windows ISO File"
                if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $script:txtISOPath.Text = $ofd.FileName }
            })

        # Populate static combos from defaults object
        $script:cmbWindowsArch.ItemsSource = $script:windowsSettingsDefaults.AllowedArchitectures
        $script:cmbWindowsArch.SelectedItem = $script:windowsSettingsDefaults.DefaultWindowsArch

        $script:cmbWindowsLang.ItemsSource = $script:windowsSettingsDefaults.AllowedLanguages
        $script:cmbWindowsLang.SelectedItem = $script:windowsSettingsDefaults.DefaultWindowsLang

        $script:cmbWindowsSKU.ItemsSource = $script:windowsSettingsDefaults.SkuList
        $script:cmbWindowsSKU.SelectedItem = $script:windowsSettingsDefaults.DefaultWindowsSKU

        $script:cmbMediaType.ItemsSource = $script:windowsSettingsDefaults.AllowedMediaTypes
        $script:cmbMediaType.SelectedItem = $script:windowsSettingsDefaults.DefaultMediaType

        # Set default text values for Windows Settings
        $script:txtOptionalFeatures.Text = $script:windowsSettingsDefaults.DefaultOptionalFeatures
        $window.FindName('txtProductKey').Text = $script:windowsSettingsDefaults.DefaultProductKey

        # Build tab defaults from General Defaults
        $window.FindName('txtFFUDevPath').Text = $FFUDevelopmentPath # Keep this as it's the base path
        $window.FindName('txtCustomFFUNameTemplate').Text = $script:generalDefaults.CustomFFUNameTemplate
        $window.FindName('txtFFUCaptureLocation').Text = $script:generalDefaults.FFUCaptureLocation
        $window.FindName('txtShareName').Text = $script:generalDefaults.ShareName
        $window.FindName('txtUsername').Text = $script:generalDefaults.Username
        $window.FindName('chkBuildUSBDriveEnable').IsChecked = $script:generalDefaults.BuildUSBDriveEnable
        $window.FindName('chkCompactOS').IsChecked = $script:generalDefaults.CompactOS
        $window.FindName('chkOptimize').IsChecked = $script:generalDefaults.Optimize
        $window.FindName('chkAllowVHDXCaching').IsChecked = $script:generalDefaults.AllowVHDXCaching
        $window.FindName('chkCreateCaptureMedia').IsChecked = $script:generalDefaults.CreateCaptureMedia
        $window.FindName('chkCreateDeploymentMedia').IsChecked = $script:generalDefaults.CreateDeploymentMedia
        $window.FindName('chkAllowExternalHardDiskMedia').IsChecked = $script:generalDefaults.AllowExternalHardDiskMedia
        $window.FindName('chkPromptExternalHardDiskMedia').IsChecked = $script:generalDefaults.PromptExternalHardDiskMedia
        $window.FindName('chkSelectSpecificUSBDrives').IsChecked = $script:generalDefaults.SelectSpecificUSBDrives
        $window.FindName('chkCopyAutopilot').IsChecked = $script:generalDefaults.CopyAutopilot
        $window.FindName('chkCopyUnattend').IsChecked = $script:generalDefaults.CopyUnattend
        $window.FindName('chkCopyPPKG').IsChecked = $script:generalDefaults.CopyPPKG
        $window.FindName('chkCleanupAppsISO').IsChecked = $script:generalDefaults.CleanupAppsISO
        $window.FindName('chkCleanupCaptureISO').IsChecked = $script:generalDefaults.CleanupCaptureISO
        $window.FindName('chkCleanupDeployISO').IsChecked = $script:generalDefaults.CleanupDeployISO
        $window.FindName('chkCleanupDrivers').IsChecked = $script:generalDefaults.CleanupDrivers
        $window.FindName('chkRemoveFFU').IsChecked = $script:generalDefaults.RemoveFFU
        $script:chkRemoveApps.IsChecked = $script:generalDefaults.RemoveApps # New

        # Hyper-V Settings defaults from General Defaults
        $window.FindName('txtDiskSize').Text = $script:generalDefaults.DiskSizeGB
        $window.FindName('txtMemory').Text = $script:generalDefaults.MemoryGB
        $window.FindName('txtProcessors').Text = $script:generalDefaults.Processors
        $window.FindName('txtVMLocation').Text = $script:generalDefaults.VMLocation
        $window.FindName('txtVMNamePrefix').Text = $script:generalDefaults.VMNamePrefix
        $window.FindName('cmbLogicalSectorSize').SelectedItem = ($window.FindName('cmbLogicalSectorSize').Items | Where-Object { $_.Content -eq $script:generalDefaults.LogicalSectorSize.ToString() })

        # Hyper-V Settings: Populate VM Switch ComboBox (Keep existing logic)
        $vmSwitchData = Get-VMSwitchData
        $script:vmSwitchMap = $vmSwitchData.SwitchMap
        $script:cmbVMSwitchName.Items.Clear()
        foreach ($switchName in $vmSwitchData.SwitchNames) {
            $script:cmbVMSwitchName.Items.Add($switchName) | Out-Null
        }
        $script:cmbVMSwitchName.Items.Add('Other') | Out-Null
        if ($script:cmbVMSwitchName.Items.Count -gt 1) {
            $script:cmbVMSwitchName.SelectedIndex = 0
            $firstSwitch = $script:cmbVMSwitchName.SelectedItem
            if ($script:vmSwitchMap.ContainsKey($firstSwitch)) {
                $script:txtVMHostIPAddress.Text = $script:vmSwitchMap[$firstSwitch]
            }
            else {
                $script:txtVMHostIPAddress.Text = $script:generalDefaults.VMHostIPAddress # Use default if IP not found
            }
            $script:txtCustomVMSwitchName.Visibility = 'Collapsed'
        }
        else {
            $script:cmbVMSwitchName.SelectedItem = 'Other'
            $script:txtCustomVMSwitchName.Visibility = 'Visible'
            $script:txtVMHostIPAddress.Text = $script:generalDefaults.VMHostIPAddress # Use default
        }
        $script:cmbVMSwitchName.Add_SelectionChanged({
                param($eventSource, $selectionChangedEventArgs)
                $selectedItem = $eventSource.SelectedItem
                if ($selectedItem -eq 'Other') {
                    $script:txtCustomVMSwitchName.Visibility = 'Visible'
                    $script:txtVMHostIPAddress.Text = '' # Clear IP for custom
                }
                else {
                    $script:txtCustomVMSwitchName.Visibility = 'Collapsed'
                    if ($script:vmSwitchMap.ContainsKey($selectedItem)) {
                        $script:txtVMHostIPAddress.Text = $script:vmSwitchMap[$selectedItem]
                    }
                    else {
                        $script:txtVMHostIPAddress.Text = '' # Clear IP if not found in map
                    }
                }
            })

        # Updates tab defaults from General Defaults
        $window.FindName('chkUpdateLatestCU').IsChecked = $script:generalDefaults.UpdateLatestCU
        $window.FindName('chkUpdateLatestNet').IsChecked = $script:generalDefaults.UpdateLatestNet
        $window.FindName('chkUpdateLatestDefender').IsChecked = $script:generalDefaults.UpdateLatestDefender
        $window.FindName('chkUpdateEdge').IsChecked = $script:generalDefaults.UpdateEdge
        $window.FindName('chkUpdateOneDrive').IsChecked = $script:generalDefaults.UpdateOneDrive
        $window.FindName('chkUpdateLatestMSRT').IsChecked = $script:generalDefaults.UpdateLatestMSRT
        $window.FindName('chkUpdatePreviewCU').IsChecked = $script:generalDefaults.UpdatePreviewCU

        # Applications tab defaults from General Defaults
        $window.FindName('chkInstallApps').IsChecked = $script:generalDefaults.InstallApps
        $window.FindName('txtApplicationPath').Text = $script:generalDefaults.ApplicationPath
        $window.FindName('txtAppListJsonPath').Text = $script:generalDefaults.AppListJsonPath
        $window.FindName('chkInstallWingetApps').IsChecked = $script:generalDefaults.InstallWingetApps
        $window.FindName('chkBringYourOwnApps').IsChecked = $script:generalDefaults.BringYourOwnApps

        # M365 Apps/Office tab defaults from General Defaults
        $window.FindName('chkInstallOffice').IsChecked = $script:generalDefaults.InstallOffice
        $window.FindName('txtOfficePath').Text = $script:generalDefaults.OfficePath
        $window.FindName('chkCopyOfficeConfigXML').IsChecked = $script:generalDefaults.CopyOfficeConfigXML
        $window.FindName('txtOfficeConfigXMLFilePath').Text = $script:generalDefaults.OfficeConfigXMLFilePath

        # Drivers tab defaults from General Defaults
        $window.FindName('txtDriversFolder').Text = $script:generalDefaults.DriversFolder
        $window.FindName('txtPEDriversFolder').Text = $script:generalDefaults.PEDriversFolder
        $window.FindName('chkDownloadDrivers').IsChecked = $script:generalDefaults.DownloadDrivers
        $window.FindName('chkInstallDrivers').IsChecked = $script:generalDefaults.InstallDrivers
        $window.FindName('chkCopyDrivers').IsChecked = $script:generalDefaults.CopyDrivers
        $window.FindName('chkCopyPEDrivers').IsChecked = $script:generalDefaults.CopyPEDrivers

        # Drivers tab UI logic (Keep existing logic)
        $makeList = @('Microsoft', 'Dell', 'HP', 'Lenovo') # Added Lenovo
        foreach ($m in $makeList) { [void]$script:cmbMake.Items.Add($m) }
        if ($script:cmbMake.Items.Count -gt 0) { $script:cmbMake.SelectedIndex = 0 }
        $script:chkDownloadDrivers.Add_Checked({
                $script:cmbMake.Visibility = 'Visible'
                $script:btnGetModels.Visibility = 'Visible'
                $script:spMakeSection.Visibility = 'Visible'
                # Make the model filter, list, and action buttons visible immediately
                # This allows users to import a Drivers.json without first clicking "Get Models"
                $script:spModelFilterSection.Visibility = 'Visible'
                $script:lstDriverModels.Visibility = 'Visible'
                $script:spDriverActionButtons.Visibility = 'Visible'
            })
        $script:chkDownloadDrivers.Add_Unchecked({
                $script:cmbMake.Visibility = 'Collapsed'
                $script:btnGetModels.Visibility = 'Collapsed'
                $script:spMakeSection.Visibility = 'Collapsed'
                $script:spModelFilterSection.Visibility = 'Collapsed'
                $script:lstDriverModels.Visibility = 'Collapsed'
                $script:spDriverActionButtons.Visibility = 'Collapsed'
                $script:lstDriverModels.ItemsSource = $null
                $script:allDriverModels = @()
                $script:txtModelFilter.Text = ""
            })
        $script:spMakeSection.Visibility = if ($script:chkDownloadDrivers.IsChecked) { 'Visible' } else { 'Collapsed' }
        $script:btnGetModels.Visibility = if ($script:chkDownloadDrivers.IsChecked) { 'Visible' } else { 'Collapsed' }
        $script:spModelFilterSection.Visibility = 'Collapsed'
        $script:lstDriverModels.Visibility = 'Collapsed'
        $script:spDriverActionButtons.Visibility = 'Collapsed'
        $script:btnGetModels.Add_Click({
                $selectedMake = $script:cmbMake.SelectedItem
                $script:txtStatus.Text = "Getting models for $selectedMake..."
                $window.Cursor = [System.Windows.Input.Cursors]::Wait
                $this.IsEnabled = $false # Disable the button

                try {
                    # Get previously selected models from the master list ($script:allDriverModels)
                    # This ensures all selected items are captured, regardless of any active filter.
                    $previouslySelectedModels = @($script:allDriverModels | Where-Object { $_.IsSelected })
                    
                    # Get newly fetched models for the current make (already standardized)
                    $newlyFetchedStandardizedModels = Get-ModelsForMake -SelectedMake $selectedMake
                    
                    $combinedModelsList = [System.Collections.Generic.List[PSCustomObject]]::new()
                    $modelIdentifiersInCombinedList = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

                    # Add previously selected models first to preserve their selection state and order (if any)
                    foreach ($item in $previouslySelectedModels) {
                        $combinedModelsList.Add($item)
                        # Use a composite key of Make and Model for uniqueness tracking
                        $modelIdentifiersInCombinedList.Add("$($item.Make)::$($item.Model)") | Out-Null
                    }

                    # Add newly fetched models if they are not already in the combined list (based on Make::Model identifier)
                    $addedNewCount = 0
                    foreach ($item in $newlyFetchedStandardizedModels) {
                        if (-not $modelIdentifiersInCombinedList.Contains("$($item.Make)::$($item.Model)")) {
                            $combinedModelsList.Add($item)
                            # Add to HashSet to prevent duplicates if the new list itself has them (though Get-ModelsForMake should try to avoid this)
                            $modelIdentifiersInCombinedList.Add("$($item.Make)::$($item.Model)") | Out-Null
                            $addedNewCount++
                        }
                    }
                    
                    $script:allDriverModels = $combinedModelsList.ToArray() | Sort-Object @{Expression = { $_.IsSelected }; Descending = $true }, Make, Model # Sort by selection status, then Make, then Model
                    $script:lstDriverModels.ItemsSource = $script:allDriverModels
                    $script:txtModelFilter.Text = "" # Clear any existing filter

                    if ($script:allDriverModels.Count -gt 0) {
                        $script:spModelFilterSection.Visibility = 'Visible'
                        $script:lstDriverModels.Visibility = 'Visible'
                        $script:spDriverActionButtons.Visibility = 'Visible'
                        $statusText = "Displaying $($script:allDriverModels.Count) models."
                        if ($newlyFetchedStandardizedModels.Count -gt 0 -and $addedNewCount -eq 0 -and $previouslySelectedModels.Count -gt 0) {
                            # This case means new models were fetched, but all were already present in the selected list.
                            $statusText = "Fetched $($newlyFetchedStandardizedModels.Count) models for $selectedMake; all were already in the selected list. Displaying $($script:allDriverModels.Count) total selected models."
                        }
                        elseif ($addedNewCount -gt 0) {
                            $statusText = "Added $addedNewCount new models for $selectedMake. Displaying $($script:allDriverModels.Count) total models."
                        }
                        elseif ($newlyFetchedStandardizedModels.Count -eq 0 -and $selectedMake -eq 'Lenovo' ) {
                            # Handled Lenovo specific no new models found message inside Get-ModelsForMake or if user cancelled prompt
                            $statusText = if ($previouslySelectedModels.Count -gt 0) { "No new models found for $selectedMake. Displaying $($previouslySelectedModels.Count) previously selected models." } else { "No models found for $selectedMake." }
                        }
                        elseif ($newlyFetchedStandardizedModels.Count -eq 0) {
                            $statusText = "No new models found for $selectedMake. Displaying $($script:allDriverModels.Count) previously selected models."
                        }
                        $script:txtStatus.Text = $statusText
                    }
                    else {
                        $script:spModelFilterSection.Visibility = 'Collapsed'
                        $script:lstDriverModels.Visibility = 'Collapsed'
                        $script:spDriverActionButtons.Visibility = 'Collapsed'
                        $script:txtStatus.Text = "No models to display for $selectedMake."
                    }
                } # End Try
                catch {
                    $script:txtStatus.Text = "Error getting models: $($_.Exception.Message)"
                    [System.Windows.MessageBox]::Show("Error getting models: $($_.Exception.Message)", "Error", "OK", "Error")
                    # Minimal UI reset on error, keep previously selected if any
                    if ($null -eq $script:allDriverModels -or $script:allDriverModels.Count -eq 0) {
                        $script:spModelFilterSection.Visibility = 'Collapsed'
                        $script:lstDriverModels.Visibility = 'Collapsed'
                        $script:spDriverActionButtons.Visibility = 'Collapsed'
                        $script:lstDriverModels.ItemsSource = $null
                        $script:txtModelFilter.Text = ""
                    }
                } # End Catch
                finally {
                    $window.Cursor = $null
                    $this.IsEnabled = $true # Re-enable the button
                } # End Finally
            })
        $script:txtModelFilter.Add_TextChanged({
                param($sourceObject, $textChangedEventArgs)
                Filter-DriverModels -filterText $script:txtModelFilter.Text
            })
        $script:btnDownloadSelectedDrivers.Add_Click({
                param($buttonSender, $clickEventArgs)

                $selectedDrivers = @($script:lstDriverModels.Items | Where-Object { $_.IsSelected })
                if (-not $selectedDrivers) {
                    [System.Windows.MessageBox]::Show("No drivers selected to download.", "Download Drivers", "OK", "Information")
                    return
                }

                $buttonSender.IsEnabled = $false
                $script:progressBar = $window.FindName('progressBar') # Ensure progress bar is assigned
                $script:progressBar.Visibility = 'Visible'
                $script:progressBar.Value = 0
                $script:txtStatus.Text = "Preparing driver downloads..."

                # Define common necessary task-specific variables locally
                $localDriversFolder = $window.FindName('txtDriversFolder').Text
                $localWindowsRelease = $window.FindName('cmbWindowsRelease').SelectedItem.Value
                $localWindowsArch = $window.FindName('cmbWindowsArch').SelectedItem
                $localHeaders = $Headers # Use script-level variable
                $localUserAgent = $UserAgent # Use script-level variable
                $compressDrivers = $script:chkCompressDriversToWIM.IsChecked

                # Define common necessary task-specific variables locally
                # Ensure required selections are made
                if ($null -eq $window.FindName('cmbWindowsRelease').SelectedItem) {
                    [System.Windows.MessageBox]::Show("Please select a Windows Release.", "Missing Information", "OK", "Warning")
                    $buttonSender.IsEnabled = $true
                    $script:progressBar.Visibility = 'Collapsed'
                    $script:txtStatus.Text = "Driver download cancelled."
                    return
                }
                if ($null -eq $window.FindName('cmbWindowsArch').SelectedItem) {
                    [System.Windows.MessageBox]::Show("Please select a Windows Architecture.", "Missing Information", "OK", "Warning")
                    $buttonSender.IsEnabled = $true
                    $script:progressBar.Visibility = 'Collapsed'
                    $script:txtStatus.Text = "Driver download cancelled."
                    return
                }
                if (($selectedDrivers | Where-Object { $_.Make -eq 'HP' }) -and $null -eq $window.FindName('cmbWindowsVersion').SelectedItem) {
                    [System.Windows.MessageBox]::Show("HP drivers are selected. Please select a Windows Version.", "Missing Information", "OK", "Warning")
                    $buttonSender.IsEnabled = $true
                    $script:progressBar.Visibility = 'Collapsed'
                    $script:txtStatus.Text = "Driver download cancelled."
                    return
                }
            
                $localDriversFolder = $window.FindName('txtDriversFolder').Text
                $localWindowsRelease = $window.FindName('cmbWindowsRelease').SelectedItem.Value
                $localWindowsArch = $window.FindName('cmbWindowsArch').SelectedItem
                $localWindowsVersion = if ($null -ne $window.FindName('cmbWindowsVersion').SelectedItem) { $window.FindName('cmbWindowsVersion').SelectedItem } else { $null }
                $localHeaders = $Headers # Use script-level variable
                $localUserAgent = $UserAgent # Use script-level variable
                $compressDrivers = $script:chkCompressDriversToWIM.IsChecked
            
                # --- Dell Catalog Handling (once, if Dell drivers are selected) ---
                $dellCatalogXmlPath = $null # This will be the path passed to the background task
                if ($selectedDrivers | Where-Object { $_.Make -eq 'Dell' }) {
                    $script:txtStatus.Text = "Checking Dell Catalog..."
                    WriteLog "Dell drivers selected. Preparing Dell catalog..."
                    
                    $dellDriversFolderUi = Join-Path -Path $localDriversFolder -ChildPath "Dell"
                    $catalogBaseName = if ($localWindowsRelease -le 11) { "CatalogPC" } else { "Catalog" }
                    $dellCabFileUi = Join-Path -Path $dellDriversFolderUi -ChildPath "$($catalogBaseName).cab"
                    # This $dellCatalogXmlPath is the one we ensure exists and is up-to-date for the Save-DellDriversTask
                    $dellCatalogXmlPath = Join-Path -Path $dellDriversFolderUi -ChildPath "$($catalogBaseName).xml" 
                    $catalogUrl = if ($localWindowsRelease -le 11) { "http://downloads.dell.com/catalog/CatalogPC.cab" } else { "https://downloads.dell.com/catalog/Catalog.cab" }
                    
                    $downloadDellCatalog = $true
                    if (Test-Path -Path $dellCatalogXmlPath -PathType Leaf) {
                        if (((Get-Date) - (Get-Item $dellCatalogXmlPath).LastWriteTime).TotalDays -lt 7) {
                            WriteLog "Using existing Dell Catalog XML (less than 7 days old) for download task: $dellCatalogXmlPath"
                            $downloadDellCatalog = $false
                            $script:txtStatus.Text = "Dell Catalog ready."
                        }
                        else {
                            WriteLog "Existing Dell Catalog XML '$dellCatalogXmlPath' is older than 7 days."
                        }
                    }
                    else {
                        WriteLog "Dell Catalog XML '$dellCatalogXmlPath' not found."
                    }

                    if ($downloadDellCatalog) {
                        WriteLog "Dell Catalog XML '$dellCatalogXmlPath' needs to be downloaded/updated for driver download task."
                        $script:txtStatus.Text = "Downloading Dell Catalog..."
                        try {
                            # Ensure Dell drivers folder exists
                            if (-not (Test-Path -Path $dellDriversFolderUi -PathType Container)) {
                                WriteLog "Creating Dell drivers folder: $dellDriversFolderUi"
                                New-Item -Path $dellDriversFolderUi -ItemType Directory -Force | Out-Null
                            }

                            if (Test-Path $dellCabFileUi) { Remove-Item $dellCabFileUi -Force -ErrorAction SilentlyContinue }
                            if (Test-Path $dellCatalogXmlPath) { Remove-Item $dellCatalogXmlPath -Force -ErrorAction SilentlyContinue }
                            
                            # Using Start-BitsTransferWithRetry and Invoke-Process (available from FFUUI.Core.psm1)
                            Start-BitsTransferWithRetry -Source $catalogUrl -Destination $dellCabFileUi
                            WriteLog "Dell Catalog CAB downloaded to $dellCabFileUi"
                            Invoke-Process -FilePath "Expand.exe" -ArgumentList """$dellCabFileUi"" ""$dellCatalogXmlPath""" | Out-Null
                            WriteLog "Dell Catalog XML extracted to $dellCatalogXmlPath"
                            Remove-Item -Path $dellCabFileUi -Force -ErrorAction SilentlyContinue
                            WriteLog "Dell Catalog CAB file $dellCabFileUi deleted."
                            $script:txtStatus.Text = "Dell Catalog ready."
                        }
                        catch {
                            $errMsg = "Failed to download/extract Dell Catalog for driver download task: $($_.Exception.Message)"
                            WriteLog $errMsg; [System.Windows.MessageBox]::Show($errMsg, "Dell Catalog Error", "OK", "Error")
                            $dellCatalogXmlPath = $null # Ensure it's null if failed, Save-DellDriversTask will handle this
                            $script:txtStatus.Text = "Dell Catalog download failed. Dell drivers may not download."
                        }
                    }
                    # If $downloadDellCatalog was false, $dellCatalogXmlPath is already set to the existing valid XML.
                }
                # --- End Dell Catalog Handling ---
            
                $script:txtStatus.Text = "Processing all selected drivers..."
                WriteLog "Processing all selected drivers: $($selectedDrivers.Model -join ', ')"
            
                $taskArguments = @{
                    DriversFolder      = $localDriversFolder
                    WindowsRelease     = $localWindowsRelease
                    WindowsArch        = $localWindowsArch
                    WindowsVersion     = $localWindowsVersion # Will be null if not applicable (e.g., not HP)
                    Headers            = $localHeaders
                    UserAgent          = $localUserAgent
                    CompressToWim      = $compressDrivers
                    DellCatalogXmlPath = $dellCatalogXmlPath  # Will be null if not Dell or if Dell catalog prep failed
                }
                
                Invoke-ParallelProcessing -ItemsToProcess $selectedDrivers `
                    -ListViewControl $script:lstDriverModels `
                    -IdentifierProperty 'Model' `
                    -StatusProperty 'DownloadStatus' `
                    -TaskType 'DownloadDriverByMake' `
                    -TaskArguments $taskArguments `
                    -CompletedStatusText 'Completed' `
                    -ErrorStatusPrefix 'Error: ' `
                    -WindowObject $window `
                    -MainThreadLogPath $global:LogFile 
                
                $overallSuccess = $true
                # Check if any item has an error status after processing
                # We iterate over $script:lstDriverModels.Items because their DownloadStatus property was updated by Invoke-ParallelProcessing
                foreach ($item in ($script:lstDriverModels.Items | Where-Object { $_.IsSelected })) {
                    # Check only originally selected items
                    if ($item.DownloadStatus -like 'Error:*') {
                        $overallSuccess = $false
                        WriteLog "Error detected for model $($item.Model) (Make: $($item.Make)): $($item.DownloadStatus)"
                        # No break here, log all errors
                    }
                }
            
                $script:progressBar.Visibility = 'Collapsed'
                $buttonSender.IsEnabled = $true
                if ($overallSuccess) {
                    $script:txtStatus.Text = "All selected driver downloads processed."
                    [System.Windows.MessageBox]::Show("All selected driver downloads processed. Check status column for details.", "Download Process Finished", "OK", "Information")
                }
                else {
                    $script:txtStatus.Text = "Driver downloads processed with some errors. Check status column and log."
                    [System.Windows.MessageBox]::Show("Driver downloads processed, but some errors occurred. Please check the status column for each driver and the log file for details.", "Download Process Finished with Errors", "OK", "Warning")
                }
            })
        $script:btnClearDriverList.Add_Click({
                $script:lstDriverModels.ItemsSource = $null
                $script:allDriverModels = @()
                $script:txtModelFilter.Text = ""
                $script:txtStatus.Text = "Driver list cleared."
            })
        $script:btnSaveDriversJson.Add_Click({ Save-DriversJson })
        $script:btnImportDriversJson.Add_Click({ Import-DriversJson })
        
        # Office interplay (Keep existing logic)
        $script:installAppsCheckedByOffice = $false
        if ($script:chkInstallOffice.IsChecked) {
            $script:OfficePathStackPanel.Visibility = 'Visible'
            $script:OfficePathGrid.Visibility = 'Visible'
            $script:CopyOfficeConfigXMLStackPanel.Visibility = 'Visible'
            # Show/hide XML file path based on checkbox state
            $script:OfficeConfigurationXMLFileStackPanel.Visibility = if ($script:chkCopyOfficeConfigXML.IsChecked) { 'Visible' } else { 'Collapsed' }
            $script:OfficeConfigurationXMLFileGrid.Visibility = if ($script:chkCopyOfficeConfigXML.IsChecked) { 'Visible' } else { 'Collapsed' }
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
                # Show/hide XML file path based on checkbox state
                $script:OfficeConfigurationXMLFileStackPanel.Visibility = if ($script:chkCopyOfficeConfigXML.IsChecked) { 'Visible' } else { 'Collapsed' }
                $script:OfficeConfigurationXMLFileGrid.Visibility = if ($script:chkCopyOfficeConfigXML.IsChecked) { 'Visible' } else { 'Collapsed' }
            })
        $script:chkInstallOffice.Add_Unchecked({
                if ($script:installAppsCheckedByOffice) {
                    $script:chkInstallApps.IsChecked = $false
                    $script:installAppsCheckedByOffice = $false
                }
                # Only re-enable InstallApps if not forced by Updates
                if (-not $script:installAppsForcedByUpdates) {
                    $script:chkInstallApps.IsEnabled = $true
                }
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

        # Build dynamic multi-column checkboxes for optional features (Keep existing logic)
        if ($script:featuresPanel) { BuildFeaturesGrid -parent $script:featuresPanel -allowedFeatures $script:windowsSettingsDefaults.AllowedFeatures }

        # Updates/InstallApps interplay (Keep existing logic)
        $script:installAppsForcedByUpdates = $false
        $script:prevInstallAppsStateBeforeUpdates = $null
        $script:UpdateInstallAppsBasedOnUpdates = {
            $anyUpdateChecked = $window.FindName('chkUpdateLatestDefender').IsChecked -or $window.FindName('chkUpdateEdge').IsChecked -or $window.FindName('chkUpdateOneDrive').IsChecked -or $window.FindName('chkUpdateLatestMSRT').IsChecked
            if ($anyUpdateChecked) {
                if (-not $script:installAppsForcedByUpdates) {
                    $script:prevInstallAppsStateBeforeUpdates = $window.FindName('chkInstallApps').IsChecked
                    $script:installAppsForcedByUpdates = $true
                }
                $window.FindName('chkInstallApps').IsChecked = $true
                $window.FindName('chkInstallApps').IsEnabled = $false
            }
            else {
                if ($script:installAppsForcedByUpdates) {
                    $window.FindName('chkInstallApps').IsChecked = $script:prevInstallAppsStateBeforeUpdates
                    $script:installAppsForcedByUpdates = $false
                    $script:prevInstallAppsStateBeforeUpdates = $null
                }
                # Only re-enable InstallApps if not forced by Office
                if (-not $script:chkInstallOffice.IsChecked) {
                    $window.FindName('chkInstallApps').IsEnabled = $true
                }
            }
        }
        $window.FindName('chkUpdateLatestDefender').Add_Checked({ & $script:UpdateInstallAppsBasedOnUpdates })
        $window.FindName('chkUpdateLatestDefender').Add_Unchecked({ & $script:UpdateInstallAppsBasedOnUpdates })
        $window.FindName('chkUpdateEdge').Add_Checked({ & $script:UpdateInstallAppsBasedOnUpdates })
        $window.FindName('chkUpdateEdge').Add_Unchecked({ & $script:UpdateInstallAppsBasedOnUpdates })
        $window.FindName('chkUpdateOneDrive').Add_Checked({ & $script:UpdateInstallAppsBasedOnUpdates })
        $window.FindName('chkUpdateOneDrive').Add_Unchecked({ & $script:UpdateInstallAppsBasedOnUpdates })
        $window.FindName('chkUpdateLatestMSRT').Add_Checked({ & $script:UpdateInstallAppsBasedOnUpdates })
        $window.FindName('chkUpdateLatestMSRT').Add_Unchecked({ & $script:UpdateInstallAppsBasedOnUpdates })
        # Initial check for Updates/InstallApps state
        & $script:UpdateInstallAppsBasedOnUpdates

        # CU interplay (Keep existing logic)
        $script:chkLatestCU.Add_Checked({ $script:chkPreviewCU.IsEnabled = $false })
        $script:chkLatestCU.Add_Unchecked({ $script:chkPreviewCU.IsEnabled = $true })
        $script:chkPreviewCU.Add_Checked({ $script:chkLatestCU.IsEnabled = $false })
        $script:chkPreviewCU.Add_Unchecked({ $script:chkLatestCU.IsEnabled = $true })
        # Set initial state based on defaults
        $script:chkPreviewCU.IsEnabled = -not $script:chkLatestCU.IsChecked
        $script:chkLatestCU.IsEnabled = -not $script:chkPreviewCU.IsChecked

        # USB Drive Detection/Selection logic (Keep existing logic)
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
        $script:chkSelectAllUSBDrives.Add_Checked({
                foreach ($item in $script:lstUSBDrives.Items) { $item.IsSelected = $true }
                $script:lstUSBDrives.Items.Refresh()
            })
        $script:chkSelectAllUSBDrives.Add_Unchecked({
                foreach ($item in $script:lstUSBDrives.Items) { $item.IsSelected = $false }
                $script:lstUSBDrives.Items.Refresh()
            })
        $script:lstUSBDrives.Add_KeyDown({
                param($eventSource, $keyEvent)
                if ($keyEvent.Key -eq 'Space') {
                    $selectedItem = $script:lstUSBDrives.SelectedItem
                    if ($selectedItem) {
                        $selectedItem.IsSelected = !$selectedItem.IsSelected
                        $script:lstUSBDrives.Items.Refresh()
                        $allSelected = -not ($script:lstUSBDrives.Items | Where-Object { -not $_.IsSelected })
                        $script:chkSelectAllUSBDrives.IsChecked = $allSelected
                    }
                }
            })
        $script:lstUSBDrives.Add_SelectionChanged({
                param($eventSource, $selChangeEvent)
                $allSelected = -not ($script:lstUSBDrives.Items | Where-Object { -not $_.IsSelected })
                $script:chkSelectAllUSBDrives.IsChecked = $allSelected
            })
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
        $script:chkSelectSpecificUSBDrives.Add_Checked({ $script:usbSelectionPanel.Visibility = 'Visible' })
        $script:chkSelectSpecificUSBDrives.Add_Unchecked({
                $script:usbSelectionPanel.Visibility = 'Collapsed'
                $script:lstUSBDrives.Items.Clear()
                $script:chkSelectAllUSBDrives.IsChecked = $false
            })
        $script:chkSelectSpecificUSBDrives.IsEnabled = $script:chkBuildUSBDriveEnable.IsChecked
        $script:chkAllowExternalHardDiskMedia.Add_Checked({ $script:chkPromptExternalHardDiskMedia.IsEnabled = $true })
        $script:chkAllowExternalHardDiskMedia.Add_Unchecked({
                $script:chkPromptExternalHardDiskMedia.IsEnabled = $false
                $script:chkPromptExternalHardDiskMedia.IsChecked = $false
            })
        # Set initial state based on defaults
        $script:chkPromptExternalHardDiskMedia.IsEnabled = $script:chkAllowExternalHardDiskMedia.IsChecked

        # APPLICATIONS tab UI logic (Keep existing logic)
        $script:chkInstallWingetApps.Visibility = if ($script:chkInstallApps.IsChecked) { 'Visible' } else { 'Collapsed' }
        $script:applicationPathPanel.Visibility = if ($script:chkInstallApps.IsChecked) { 'Visible' } else { 'Collapsed' }
        $script:appListJsonPathPanel.Visibility = if ($script:chkInstallApps.IsChecked) { 'Visible' } else { 'Collapsed' }
        $script:chkBringYourOwnApps.Visibility = if ($script:chkInstallApps.IsChecked) { 'Visible' } else { 'Collapsed' }
        $script:byoApplicationPanel.Visibility = if ($script:chkBringYourOwnApps.IsChecked) { 'Visible' } else { 'Collapsed' }
        $script:wingetPanel.Visibility = if ($script:chkInstallWingetApps.IsChecked) { 'Visible' } else { 'Collapsed' }
        $script:wingetSearchPanel.Visibility = 'Collapsed' # Keep search hidden initially
    
        $script:chkInstallApps.Add_Checked({
                $script:chkInstallWingetApps.Visibility = 'Visible'
                $script:applicationPathPanel.Visibility = 'Visible'
                $script:appListJsonPathPanel.Visibility = 'Visible'
                $script:chkBringYourOwnApps.Visibility = 'Visible'
                # New logic for AppsScriptVariables
                $script:chkDefineAppsScriptVariables.Visibility = 'Visible'
            })
$script:chkInstallApps.Add_Unchecked({
                $script:chkInstallWingetApps.IsChecked = $false # Uncheck children when parent is unchecked
                $script:chkBringYourOwnApps.IsChecked = $false
                $script:chkInstallWingetApps.Visibility = 'Collapsed'
                $script:applicationPathPanel.Visibility = 'Collapsed'
                $script:appListJsonPathPanel.Visibility = 'Collapsed'
                $script:chkBringYourOwnApps.Visibility = 'Collapsed'
                $script:wingetPanel.Visibility = 'Collapsed'
                $script:wingetSearchPanel.Visibility = 'Collapsed'
                $script:byoApplicationPanel.Visibility = 'Collapsed'
                # New logic for AppsScriptVariables
                $script:chkDefineAppsScriptVariables.IsChecked = $false # Also uncheck it
                $script:chkDefineAppsScriptVariables.Visibility = 'Collapsed'
                $script:appsScriptVariablesPanel.Visibility = 'Collapsed' # Ensure panel is hidden
            })
        $script:btnBrowseApplicationPath.Add_Click({
                $selectedPath = Show-ModernFolderPicker -Title "Select Application Path Folder"
                if ($selectedPath) { $window.FindName('txtApplicationPath').Text = $selectedPath }
            })
        $script:btnBrowseAppListJsonPath.Add_Click({
                $ofd = New-Object System.Windows.Forms.OpenFileDialog
                $ofd.Filter = "JSON files (*.json)|*.json"
                $ofd.Title = "Select AppList.json File"
                $ofd.CheckFileExists = $false
                if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $window.FindName('txtAppListJsonPath').Text = $ofd.FileName }
            })
        $script:chkBringYourOwnApps.Add_Checked({ $script:byoApplicationPanel.Visibility = 'Visible' })
        $script:chkBringYourOwnApps.Add_Unchecked({
                $script:byoApplicationPanel.Visibility = 'Collapsed'
                # Clear fields when hiding
                $window.FindName('txtAppName').Text = ''
                $window.FindName('txtAppCommandLine').Text = ''
                $window.FindName('txtAppArguments').Text = ''
                $window.FindName('txtAppSource').Text = ''
            })
        $script:chkInstallWingetApps.Add_Checked({ $script:wingetPanel.Visibility = 'Visible' })
        $script:chkInstallWingetApps.Add_Unchecked({
                $script:wingetPanel.Visibility = 'Collapsed'
                $script:wingetSearchPanel.Visibility = 'Collapsed' # Hide search when unchecked
            })
        $script:btnCheckWingetModule.Add_Click({
                param($buttonSender, $clickEventArgs)
                $buttonSender.IsEnabled = $false
                $window.Cursor = [System.Windows.Input.Cursors]::Wait
                # Initial UI update before calling the core function
                Update-WingetVersionFields -wingetText "Checking..." -moduleText "Checking..."
    
                $statusResult = $null
                try {
                    # Call the Core function to perform checks and potential install/update
                    # Pass the UI update function as a callback
                    $statusResult = Confirm-WingetInstallationUI -UiUpdateCallback { 
                        param($wingetText, $moduleText) 
                        Update-WingetVersionFields -wingetText $wingetText -moduleText $moduleText 
                    }
    
                    # Display appropriate message based on the result
                    if ($statusResult.Success -and $statusResult.UpdateAttempted) {
                        # Update attempted and successful
                        [System.Windows.MessageBox]::Show("Winget components installed/updated successfully.", "Winget Installation Complete", "OK", "Information")
                    }
                    elseif (-not $statusResult.Success) {
                        # Error occurred
                        $errorMessage = if (-not [string]::IsNullOrWhiteSpace($statusResult.Message)) { $statusResult.Message } else { "An unknown error occurred during Winget check/install." }
                        [System.Windows.MessageBox]::Show($errorMessage, "Winget Error", "OK", "Error")
                    }
                    # If Winget components were already up-to-date ($statusResult.Success -eq $true -and $statusResult.UpdateAttempted -eq $false), no message box is shown.
    
                    # Show search panel only if the final status is successful and checkbox is still checked
                    if ($statusResult.Success -and $script:chkInstallWingetApps.IsChecked) {
                        $script:wingetSearchPanel.Visibility = 'Visible'
                    }
                    else {
                        $script:wingetSearchPanel.Visibility = 'Collapsed' # Hide if not successful or unchecked
                    }
                }
                catch {
                    # Catch errors from the Confirm-WingetInstallationUI call itself (less likely now)
                    Update-WingetVersionFields -wingetText "Error" -moduleText "Error"
                    [System.Windows.MessageBox]::Show("Unexpected error checking/installing Winget components: $($_.Exception.Message)", "Error", "OK", "Error")
                    $script:wingetSearchPanel.Visibility = 'Collapsed' # Ensure search is hidden on error
                }
                finally {
                    $buttonSender.IsEnabled = $true
                    $window.Cursor = $null
                }
            })

        # Winget Search ListView setup
        $wingetGridView = New-Object System.Windows.Controls.GridView 
        $script:lstWingetResults.View = $wingetGridView # Assign GridView to ListView first

        # Add the selectable column using the new function
        Add-SelectableGridViewColumn -ListView $script:lstWingetResults -HeaderCheckBoxScriptVariableName "chkSelectAllWingetResults" -ColumnWidth 60

        # Add other sortable columns with left-aligned headers
        Add-SortableColumn -gridView $wingetGridView -header "Name" -binding "Name" -width 200 -headerHorizontalAlignment Left
        Add-SortableColumn -gridView $wingetGridView -header "Id" -binding "Id" -width 200 -headerHorizontalAlignment Left
        Add-SortableColumn -gridView $wingetGridView -header "Version" -binding "Version" -width 100 -headerHorizontalAlignment Left
        Add-SortableColumn -gridView $wingetGridView -header "Source" -binding "Source" -width 100 -headerHorizontalAlignment Left
        Add-SortableColumn -gridView $wingetGridView -header "Download Status" -binding "DownloadStatus" -width 150 -headerHorizontalAlignment Left
        $script:lstWingetResults.AddHandler(
            [System.Windows.Controls.GridViewColumnHeader]::ClickEvent,
            [System.Windows.RoutedEventHandler] {
                param($eventSource, $e)
                $header = $e.OriginalSource
                if ($header -is [System.Windows.Controls.GridViewColumnHeader] -and $header.Tag) {
                    Invoke-ListViewSort -listView $script:lstWingetResults -property $header.Tag
                }
            }
        )
        $script:btnWingetSearch.Add_Click({ Search-WingetApps })
        $script:txtWingetSearch.Add_KeyDown({
                param($eventSrc, $keyEvent)
                if ($keyEvent.Key -eq 'Return') { Search-WingetApps; $keyEvent.Handled = $true }
            })
        $script:btnSaveWingetList.Add_Click({ Save-WingetList })
        $script:btnImportWingetList.Add_Click({ Import-WingetList })
        $script:btnClearWingetList.Add_Click({
                $script:lstWingetResults.ItemsSource = @() # Set ItemsSource to an empty array
                $script:txtWingetSearch.Text = ""
                if ($script:txtStatus) { $script:txtStatus.Text = "Cleared all applications from the list" }
            })
        # --------------------------------------------------------------------------
        # SECTION: Background Task Management (Using ForEach-Object -Parallel)
        # --------------------------------------------------------------------------
        # Modules (UI_Helpers, BackgroundTasks) and Scripts (WingetFunctions) are imported/dot-sourced
        # directly into the main script scope. ForEach-Object -Parallel automatically handles
        # module/variable availability in the parallel threads.
        # UI updates are handled by calling helper functions directly on the main UI thread
        # after the parallel processing completes.
        # --------------------------------------------------------------------------

        $script:btnDownloadSelected.Add_Click({
                param($buttonSender, $clickEventArgs)

                $selectedApps = $script:lstWingetResults.Items | Where-Object { $_.IsSelected }
                if (-not $selectedApps) {
                    [System.Windows.MessageBox]::Show("No applications selected to download.", "Download Winget Apps", "OK", "Information")
                    return
                }

                $buttonSender.IsEnabled = $false
                $script:progressBar = $window.FindName('progressBar') # Ensure progress bar is assigned
                $script:progressBar.Visibility = 'Visible'
                $script:progressBar.Value = 0
                $script:txtStatus.Text = "Starting Winget app downloads..."

                # Define necessary task-specific variables locally
                $localAppsPath = $window.FindName('txtApplicationPath').Text
                $localAppListJsonPath = $window.FindName('txtAppListJsonPath').Text
                $localWindowsArch = $window.FindName('cmbWindowsArch').SelectedItem
                $localOrchestrationPath = Join-Path -Path $window.FindName('txtApplicationPath').Text -ChildPath "Orchestration"

                # Create hashtable for task-specific arguments to pass to Invoke-ParallelProcessing
                $taskArguments = @{
                    AppsPath          = $localAppsPath
                    AppListJsonPath   = $localAppListJsonPath
                    WindowsArch       = $localWindowsArch
                    OrchestrationPath = $localOrchestrationPath
                }

                # Select only necessary properties before passing to Invoke-ParallelProcessing
                $itemsToProcess = $selectedApps | Select-Object Name, Id, Source, Version # Include Version if needed

                # Invoke the centralized parallel processing function
                # Pass task type and task-specific arguments
                Invoke-ParallelProcessing -ItemsToProcess $itemsToProcess `
                    -ListViewControl $script:lstWingetResults `
                    -IdentifierProperty 'Id' `
                    -StatusProperty 'DownloadStatus' `
                    -TaskType 'WingetDownload' `
                    -TaskArguments $taskArguments `
                    -CompletedStatusText "Completed" `
                    -ErrorStatusPrefix "Error: " `
                    -WindowObject $window `
                    -MainThreadLogPath $global:LogFile

                # Final status update (handled by Invoke-ParallelProcessing)
                $script:progressBar.Visibility = 'Collapsed'
                $buttonSender.IsEnabled = $true
            })

        # BYO Apps UI logic (Keep existing logic)
        $script:btnBrowseAppSource.Add_Click({
                $selectedPath = Show-ModernFolderPicker -Title "Select Application Source Folder"
                if ($selectedPath) { $window.FindName('txtAppSource').Text = $selectedPath }
            })
        $script:btnAddApplication.Add_Click({
                $name = $window.FindName('txtAppName').Text
                $commandLine = $window.FindName('txtAppCommandLine').Text
                $arguments = $window.FindName('txtAppArguments').Text
                $source = $window.FindName('txtAppSource').Text

                if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($commandLine) -or [string]::IsNullOrWhiteSpace($arguments)) {
                    [System.Windows.MessageBox]::Show("Please fill in all fields (Name, Command Line, and Arguments)", "Missing Information", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
                    return
                }
                $listView = $window.FindName('lstApplications')
                $priority = 1
                if ($listView.Items.Count -gt 0) {
                    $priority = ($listView.Items | Measure-Object -Property Priority -Maximum).Maximum + 1
                }
                $application = [PSCustomObject]@{ Priority = $priority; Name = $name; CommandLine = $commandLine; Arguments = $arguments; Source = $source; CopyStatus = "" }
                $listView.Items.Add($application)
                $window.FindName('txtAppName').Text = ""
                $window.FindName('txtAppCommandLine').Text = ""
                $window.FindName('txtAppArguments').Text = ""
                $window.FindName('txtAppSource').Text = ""
                Update-CopyButtonState
            })
        $script:btnSaveBYOApplications.Add_Click({
                $saveDialog = New-Object Microsoft.Win32.SaveFileDialog
                $saveDialog.Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*"
                $saveDialog.DefaultExt = ".json"
                $saveDialog.Title = "Save Application List"
                $initialDir = $window.FindName('txtApplicationPath').Text
                if ([string]::IsNullOrWhiteSpace($initialDir) -or -not (Test-Path $initialDir)) { $initialDir = $PSScriptRoot }
                $saveDialog.InitialDirectory = $initialDir
                $saveDialog.FileName = "UserAppList.json"
                if ($saveDialog.ShowDialog()) { Save-BYOApplicationList -Path $saveDialog.FileName }
            })
        $script:btnLoadBYOApplications.Add_Click({
                $openDialog = New-Object Microsoft.Win32.OpenFileDialog
                $openDialog.Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*"
                $openDialog.Title = "Import Application List"
                $initialDir = $window.FindName('txtApplicationPath').Text
                if ([string]::IsNullOrWhiteSpace($initialDir) -or -not (Test-Path $initialDir)) { $initialDir = $PSScriptRoot }
                $openDialog.InitialDirectory = $initialDir
                if ($openDialog.ShowDialog()) { Import-BYOApplicationList -Path $openDialog.FileName; Update-CopyButtonState }
            })
        $script:btnClearBYOApplications.Add_Click({
                $result = [System.Windows.MessageBox]::Show("Are you sure you want to clear all applications?", "Clear Applications", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
                if ($result -eq [System.Windows.MessageBoxResult]::Yes) { $window.FindName('lstApplications').Items.Clear(); Update-CopyButtonState }
            })
        $script:btnCopyBYOApps.Add_Click({
                param($buttonSender, $clickEventArgs)

                $appsToCopy = $script:lstApplications.Items | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Source) }
                if (-not $appsToCopy) {
                    [System.Windows.MessageBox]::Show("No applications with a source path specified.", "Copy BYO Apps", "OK", "Information")
                    return
                }

                $buttonSender.IsEnabled = $false
                $script:progressBar = $window.FindName('progressBar') # Ensure progress bar is assigned
                $script:progressBar.Visibility = 'Visible'
                $script:progressBar.Value = 0
                $script:txtStatus.Text = "Starting BYO app copy..."

                # Define necessary task-specific variables locally
                $localAppsPath = $window.FindName('txtApplicationPath').Text

                # Create hashtable for task-specific arguments
                $taskArguments = @{
                    AppsPath = $localAppsPath
                }

                # Select only necessary properties before passing
                $itemsToProcess = $appsToCopy | Select-Object Priority, Name, CommandLine, Arguments, Source

                # Invoke the centralized parallel processing function
                # Pass task type and task-specific arguments
                Invoke-ParallelProcessing -ItemsToProcess $itemsToProcess `
                    -ListViewControl $script:lstApplications `
                    -IdentifierProperty 'Name' `
                    -StatusProperty 'CopyStatus' `
                    -TaskType 'CopyBYO' `
                    -TaskArguments $taskArguments `
                    -CompletedStatusText "Copied" `
                    -ErrorStatusPrefix "Error: " `
                    -WindowObject $window `
                    -MainThreadLogPath $global:LogFile

                # Final status update (handled by Invoke-ParallelProcessing)
                $script:progressBar.Visibility = 'Collapsed'
                $buttonSender.IsEnabled = $true
            })
        $script:btnMoveTop.Add_Click({ Move-ListViewItemTop -ListView $script:lstApplications })
        $script:btnMoveUp.Add_Click({ Move-ListViewItemUp -ListView $script:lstApplications })
        $script:btnMoveDown.Add_Click({ Move-ListViewItemDown -ListView $script:lstApplications })
        $script:btnMoveBottom.Add_Click({ Move-ListViewItemBottom -ListView $script:lstApplications })

        # BYO Apps ListView setup (Keep existing logic, ensure CopyStatus column is handled)
        $byoGridView = $script:lstApplications.View
        if ($byoGridView -is [System.Windows.Controls.GridView]) {
            $copyStatusColumnExists = $false
            foreach ($col in $byoGridView.Columns) { if ($col.Header -eq "Copy Status") { $copyStatusColumnExists = $true; break } }
            if (-not $copyStatusColumnExists) {
                $actionColumnIndex = -1
                for ($i = 0; $i -lt $byoGridView.Columns.Count; $i++) { if ($byoGridView.Columns[$i].Header -eq "Action") { $actionColumnIndex = $i; break } }
                $copyStatusColumn = New-Object System.Windows.Controls.GridViewColumn
                $copyStatusColumn.Header = "Copy Status"; $copyStatusColumn.DisplayMemberBinding = New-Object System.Windows.Data.Binding("CopyStatus"); $copyStatusColumn.Width = 150
                if ($actionColumnIndex -ge 0) { $byoGridView.Columns.Insert($actionColumnIndex, $copyStatusColumn) } else { $byoGridView.Columns.Add($copyStatusColumn) }
            }
        }
        Update-CopyButtonState # Initial check

        # General Browse Button Handlers (Keep existing logic)
        $script:btnBrowseFFUDevPath.Add_Click({
                $selectedPath = Show-ModernFolderPicker -Title "Select FFU Development Path"
                if ($selectedPath) { $window.FindName('txtFFUDevPath').Text = $selectedPath }
            })
        $script:btnBrowseFFUCaptureLocation.Add_Click({
                $selectedPath = Show-ModernFolderPicker -Title "Select FFU Capture Location"
                if ($selectedPath) { $window.FindName('txtFFUCaptureLocation').Text = $selectedPath }
            })
        $script:btnBrowseOfficePath.Add_Click({
                $selectedPath = Show-ModernFolderPicker -Title "Select Office Path"
                if ($selectedPath) { $window.FindName('txtOfficePath').Text = $selectedPath }
            })
        $script:btnBrowseDriversFolder.Add_Click({
                $selectedPath = Show-ModernFolderPicker -Title "Select Drivers Folder"
                if ($selectedPath) { $window.FindName('txtDriversFolder').Text = $selectedPath }
            })
        $script:btnBrowsePEDriversFolder.Add_Click({
                $selectedPath = Show-ModernFolderPicker -Title "Select PE Drivers Folder"
                if ($selectedPath) { $window.FindName('txtPEDriversFolder').Text = $selectedPath }
            })

        # Driver Checkbox Conditional Logic
        $script:chkInstallDrivers.Add_Checked({
                $script:chkCopyDrivers.IsEnabled = $false
                $script:chkCompressDriversToWIM.IsEnabled = $false
            })
        $script:chkInstallDrivers.Add_Unchecked({
                # Only re-enable if the other checkboxes are not checked
                if (-not $script:chkCopyDrivers.IsChecked) { $script:chkCopyDrivers.IsEnabled = $true }
                if (-not $script:chkCompressDriversToWIM.IsChecked) { $script:chkCompressDriversToWIM.IsEnabled = $true }
            })
        $script:chkCopyDrivers.Add_Checked({
                $script:chkInstallDrivers.IsEnabled = $false
            })
        $script:chkCopyDrivers.Add_Unchecked({
                # Only re-enable if InstallDrivers is not checked
                if (-not $script:chkInstallDrivers.IsChecked) { $script:chkInstallDrivers.IsEnabled = $true }
            })
        $script:chkCompressDriversToWIM.Add_Checked({
                $script:chkInstallDrivers.IsEnabled = $false
            })
        $script:chkCompressDriversToWIM.Add_Unchecked({
                # Only re-enable if InstallDrivers is not checked
                if (-not $script:chkInstallDrivers.IsChecked) { $script:chkInstallDrivers.IsEnabled = $true }
            })
        # Set initial state based on defaults (assuming defaults are false)
        $script:chkInstallDrivers.IsEnabled = $true
        $script:chkCopyDrivers.IsEnabled = $true
        $script:chkCompressDriversToWIM.IsEnabled = $true

        # AppsScriptVariables Event Handlers
        $script:chkDefineAppsScriptVariables.Add_Checked({
            $script:appsScriptVariablesPanel.Visibility = 'Visible'
        })
        $script:chkDefineAppsScriptVariables.Add_Unchecked({
            $script:appsScriptVariablesPanel.Visibility = 'Collapsed'
        })

        $script:btnAddAppsScriptVariable.Add_Click({
            $key = $script:txtAppsScriptKey.Text.Trim()
            $value = $script:txtAppsScriptValue.Text.Trim()

            if ([string]::IsNullOrWhiteSpace($key)) {
                [System.Windows.MessageBox]::Show("Apps Script Variable Key cannot be empty.", "Input Error", "OK", "Warning")
                return
            }
            # Check for duplicate keys
            $existingKey = $script:lstAppsScriptVariables.Items | Where-Object { $_.Key -eq $key }
            if ($existingKey) {
                [System.Windows.MessageBox]::Show("An Apps Script Variable with the key '$key' already exists.", "Duplicate Key", "OK", "Warning")
                return
            }

            $newItem = [PSCustomObject]@{
                IsSelected = $false # Add IsSelected property
                Key        = $key
                Value      = $value
            }
            $script:appsScriptVariablesDataList.Add($newItem)
            $script:lstAppsScriptVariables.ItemsSource = $script:appsScriptVariablesDataList.ToArray()
            $script:txtAppsScriptKey.Clear()
            $script:txtAppsScriptValue.Clear()
            # Update the header checkbox state
            if ($null -ne $script:chkSelectAllAppsScriptVariables) {
                 Update-SelectAllHeaderCheckBoxState -ListView $script:lstAppsScriptVariables -HeaderCheckBox $script:chkSelectAllAppsScriptVariables
            }
        })

        $script:btnRemoveSelectedAppsScriptVariables.Add_Click({
            $itemsToRemove = @($script:appsScriptVariablesDataList | Where-Object { $_.IsSelected })
            if ($itemsToRemove.Count -eq 0) {
                [System.Windows.MessageBox]::Show("Please select one or more Apps Script Variables to remove.", "Selection Error", "OK", "Warning")
                return
            }

            foreach ($itemToRemove in $itemsToRemove) {
                $script:appsScriptVariablesDataList.Remove($itemToRemove)
            }
            $script:lstAppsScriptVariables.ItemsSource = $script:appsScriptVariablesDataList.ToArray()

            # Update the header checkbox state
            if ($null -ne $script:chkSelectAllAppsScriptVariables) { # Check if variable exists
                 Update-SelectAllHeaderCheckBoxState -ListView $script:lstAppsScriptVariables -HeaderCheckBox $script:chkSelectAllAppsScriptVariables
            }
        })

        $script:btnClearAppsScriptVariables.Add_Click({
            $script:appsScriptVariablesDataList.Clear()
            $script:lstAppsScriptVariables.ItemsSource = $script:appsScriptVariablesDataList.ToArray()
            # Update the header checkbox state
            if ($null -ne $script:chkSelectAllAppsScriptVariables) {
                 Update-SelectAllHeaderCheckBoxState -ListView $script:lstAppsScriptVariables -HeaderCheckBox $script:chkSelectAllAppsScriptVariables
            }
        })

        # Initial state for chkDefineAppsScriptVariables based on chkInstallApps
        if ($script:chkInstallApps.IsChecked) {
            $script:chkDefineAppsScriptVariables.Visibility = 'Visible'
        }
        else {
            $script:chkDefineAppsScriptVariables.Visibility = 'Collapsed'
        }
        # Initial state for appsScriptVariablesPanel based on chkDefineAppsScriptVariables
        if ($script:chkDefineAppsScriptVariables.IsChecked) {
            $script:appsScriptVariablesPanel.Visibility = 'Visible'
        }
        else {
            $script:appsScriptVariablesPanel.Visibility = 'Collapsed'
        }

    })

# Function to search for Winget apps
function Search-WingetApps {
    try {
        $searchQuery = $script:txtWingetSearch.Text
        if ([string]::IsNullOrWhiteSpace($searchQuery)) { return }

        # Get current items from the ListView
        $currentItemsInListView = @()
        if ($null -ne $script:lstWingetResults.ItemsSource) {
            $currentItemsInListView = @($script:lstWingetResults.ItemsSource)
        } 
        elseif ($script:lstWingetResults.HasItems) {
            $currentItemsInListView = @($script:lstWingetResults.Items)
        }
        
        # Store selected apps from the current view
        $selectedAppsFromView = @($currentItemsInListView | Where-Object { $_.IsSelected })
        
        # Search for new apps
        $searchedAppResults = Search-WingetPackagesPublic -Query $searchQuery | ForEach-Object {
            [PSCustomObject]@{
                IsSelected     = $false # New items are not selected by default
                Name           = $_.Name
                Id             = $_.Id
                Version        = $_.Version
                Source         = $_.Source
                DownloadStatus = "" 
            }
        }
        
        $finalAppList = [System.Collections.Generic.List[object]]::new()
        $addedAppIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

        # Add previously selected apps first
        foreach ($app in $selectedAppsFromView) {
            $finalAppList.Add($app)
            $addedAppIds.Add($app.Id) | Out-Null
        }
        
        # Add new search results, avoiding duplicates of already added (selected) apps
        foreach ($result in $searchedAppResults) {
            if (-not $addedAppIds.Contains($result.Id)) {
                $finalAppList.Add($result)
                $addedAppIds.Add($result.Id) | Out-Null # Track added IDs to prevent duplicates from search results themselves
            }
        }
        
        # Update the ListView's ItemsSource
        $script:lstWingetResults.ItemsSource = $finalAppList.ToArray()
    }
    catch {
        [System.Windows.MessageBox]::Show("Error searching for apps: $_", "Error", "OK", "Error")
    }
}

# Function to save selected apps to JSON
function Save-WingetList {
    try {
        $selectedApps = $script:lstWingetResults.Items | Where-Object { $_.IsSelected }
        if (-not $selectedApps) {
            [System.Windows.MessageBox]::Show("No apps selected to save.", "Warning", "OK", "Warning")
            return
        }
        
        $appList = @{
            apps = @($selectedApps | ForEach-Object {
                    [ordered]@{
                        name   = $_.Name
                        id     = $_.Id
                        source = $_.Source.ToLower()
                    }
                })
        }
        
        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Filter = "JSON files (*.json)|*.json"
        $sfd.Title = "Save App List"
        $sfd.InitialDirectory = $AppsPath
        $sfd.FileName = "AppList.json"
        
        if ($sfd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $appList | ConvertTo-Json -Depth 10 | Set-Content $sfd.FileName -Encoding UTF8
            [System.Windows.MessageBox]::Show("App list saved successfully.", "Success", "OK", "Information")
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Error saving app list: $_", "Error", "OK", "Error")
    }
}

# Function to import app list from JSON
function Import-WingetList {
    try {
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Filter = "JSON files (*.json)|*.json"
        $ofd.Title = "Import App List"
        $ofd.InitialDirectory = $AppsPath
        
        if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $importedAppsData = Get-Content $ofd.FileName -Raw | ConvertFrom-Json
            
            $newAppListForItemsSource = [System.Collections.Generic.List[object]]::new()
            
            if ($null -ne $importedAppsData.apps) {
                foreach ($appInfo in $importedAppsData.apps) {
                    $newAppListForItemsSource.Add([PSCustomObject]@{
                            IsSelected     = $true # Imported apps are marked as selected
                            Name           = $appInfo.name
                            Id             = $appInfo.id
                            Version        = ""  # Will be populated when searching or if data exists
                            Source         = $appInfo.source
                            DownloadStatus = "" 
                        })
                }
            }
            
            $script:lstWingetResults.ItemsSource = $newAppListForItemsSource.ToArray()
            
            [System.Windows.MessageBox]::Show("App list imported successfully.", "Success", "OK", "Information")
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Error importing app list: $_", "Error", "OK", "Error")
    }
}

# Function to remove application and reorder priorities
function Remove-Application {
    param($priority)
    
    $listView = $window.FindName('lstApplications')
    
    # Remove the item with the specified priority
    $itemToRemove = $listView.Items | Where-Object { $_.Priority -eq $priority } | Select-Object -First 1
    if ($itemToRemove) {
        $listView.Items.Remove($itemToRemove)
        # Reorder priorities for remaining items
        Update-ListViewPriorities -ListView $listView
        # Update the Copy Apps button state
        Update-CopyButtonState
    }
}

# Function to save BYO applications to JSON
function Save-BYOApplicationList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $listView = $window.FindName('lstApplications')
    if (-not $listView -or $listView.Items.Count -eq 0) {
        [System.Windows.MessageBox]::Show("No applications to save.", "Save Applications", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        return
    }

    try {
        # Ensure items are sorted by current priority before saving
        # Exclude CopyStatus when saving
        $applications = $listView.Items | Sort-Object Priority | Select-Object Priority, Name, CommandLine, Arguments, Source 
        $applications | ConvertTo-Json -Depth 5 | Set-Content -Path $Path -Force -Encoding UTF8
        [System.Windows.MessageBox]::Show("Applications saved successfully to `"$Path`".", "Save Applications", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    }
    catch {
        [System.Windows.MessageBox]::Show("Failed to save applications: $_", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    }
}

# Function to load BYO applications from JSON
function Import-BYOApplicationList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        [System.Windows.MessageBox]::Show("Application list file not found at `"$Path`".", "Import Applications", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

    try {
        $applications = Get-Content -Path $Path -Raw | ConvertFrom-Json
        $listView = $window.FindName('lstApplications')
        $listView.Items.Clear()

        # Add items and sort by priority from the file
        $sortedApps = $applications | Sort-Object Priority
        foreach ($app in $sortedApps) {
            # Ensure all properties exist, add CopyStatus
            $appObject = [PSCustomObject]@{
                Priority    = $app.Priority # Keep original priority for now
                Name        = $app.Name
                CommandLine = $app.CommandLine
                Arguments   = if ($app.PSObject.Properties['Arguments']) { $app.Arguments } else { "" } # Handle missing Arguments
                Source      = $app.Source
                CopyStatus  = "" # Initialize CopyStatus
            }
            $listView.Items.Add($appObject)
        }

        # Reorder priorities sequentially after loading
        Update-ListViewPriorities -ListView $listView
        # Update the Copy Apps button state
        Update-CopyButtonState

        [System.Windows.MessageBox]::Show("Applications imported successfully from `"$Path`".", "Import Applications", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    }
    catch {
        [System.Windows.MessageBox]::Show("Failed to import applications: $_", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    }
}

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
                Set-UIValue -ControlName 'txtFFUDevPath' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'FFUDevelopmentPath' -WindowInstance $window
                Set-UIValue -ControlName 'txtCustomFFUNameTemplate' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'CustomFFUNameTemplate' -WindowInstance $window
                Set-UIValue -ControlName 'txtFFUCaptureLocation' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'FFUCaptureLocation' -WindowInstance $window
                Set-UIValue -ControlName 'txtShareName' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'ShareName' -WindowInstance $window
                Set-UIValue -ControlName 'txtUsername' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'Username' -WindowInstance $window
                Set-UIValue -ControlName 'chkBuildUSBDriveEnable' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'BuildUSBDrive' -WindowInstance $window
                Set-UIValue -ControlName 'chkCompactOS' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'CompactOS' -WindowInstance $window
                Set-UIValue -ControlName 'chkOptimize' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'Optimize' -WindowInstance $window
                Set-UIValue -ControlName 'chkAllowVHDXCaching' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'AllowVHDXCaching' -WindowInstance $window
                Set-UIValue -ControlName 'chkAllowExternalHardDiskMedia' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'AllowExternalHardDiskMedia' -WindowInstance $window
                Set-UIValue -ControlName 'chkPromptExternalHardDiskMedia' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'PromptExternalHardDiskMedia' -WindowInstance $window
                Set-UIValue -ControlName 'chkCreateCaptureMedia' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'CreateCaptureMedia' -WindowInstance $window
                Set-UIValue -ControlName 'chkCreateDeploymentMedia' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'CreateDeploymentMedia' -WindowInstance $window

                # USB Drive Modification group (Build Tab)
                Set-UIValue -ControlName 'chkCopyAutopilot' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'CopyAutopilot' -WindowInstance $window
                Set-UIValue -ControlName 'chkCopyUnattend' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'CopyUnattend' -WindowInstance $window
                Set-UIValue -ControlName 'chkCopyPPKG' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'CopyPPKG' -WindowInstance $window
                
                # Post Build Cleanup group (Build Tab)
                Set-UIValue -ControlName 'chkCleanupAppsISO' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'CleanupAppsISO' -WindowInstance $window
                Set-UIValue -ControlName 'chkCleanupCaptureISO' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'CleanupCaptureISO' -WindowInstance $window
                Set-UIValue -ControlName 'chkCleanupDeployISO' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'CleanupDeployISO' -WindowInstance $window
                Set-UIValue -ControlName 'chkCleanupDrivers' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'CleanupDrivers' -WindowInstance $window
                Set-UIValue -ControlName 'chkRemoveFFU' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'RemoveFFU' -WindowInstance $window
                Set-UIValue -ControlName 'chkRemoveApps' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'RemoveApps' -WindowInstance $window # New
                
                # Hyper-V Settings
                Set-UIValue -ControlName 'cmbVMSwitchName' -PropertyName 'SelectedItem' -ConfigObject $configContent -ConfigKey 'VMSwitchName' -WindowInstance $window
                Set-UIValue -ControlName 'txtVMHostIPAddress' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'VMHostIPAddress' -WindowInstance $window
                Set-UIValue -ControlName 'txtDiskSize' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'Disksize' -TransformValue { param($val) $val / 1GB } -WindowInstance $window
                Set-UIValue -ControlName 'txtMemory' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'Memory' -TransformValue { param($val) $val / 1GB } -WindowInstance $window
                Set-UIValue -ControlName 'txtProcessors' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'Processors' -WindowInstance $window
                Set-UIValue -ControlName 'txtVMLocation' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'VMLocation' -WindowInstance $window
                Set-UIValue -ControlName 'txtVMNamePrefix' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'FFUPrefix' -WindowInstance $window
                Set-UIValue -ControlName 'cmbLogicalSectorSize' -PropertyName 'SelectedItem' -ConfigObject $configContent -ConfigKey 'LogicalSectorSizeBytes' -TransformValue { param($val) $val.ToString() } -WindowInstance $window
                
                # Windows Settings
                Set-UIValue -ControlName 'txtISOPath' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'ISOPath' -WindowInstance $window
                Set-UIValue -ControlName 'cmbWindowsRelease' -PropertyName 'SelectedItem' -ConfigObject $configContent -ConfigKey 'WindowsRelease' -WindowInstance $window # Helper will try to match by Value
                Set-UIValue -ControlName 'cmbWindowsVersion' -PropertyName 'SelectedItem' -ConfigObject $configContent -ConfigKey 'WindowsVersion' -WindowInstance $window
                Set-UIValue -ControlName 'cmbWindowsArch' -PropertyName 'SelectedItem' -ConfigObject $configContent -ConfigKey 'WindowsArch' -WindowInstance $window
                Set-UIValue -ControlName 'cmbWindowsLang' -PropertyName 'SelectedItem' -ConfigObject $configContent -ConfigKey 'WindowsLang' -WindowInstance $window
                Set-UIValue -ControlName 'cmbWindowsSKU' -PropertyName 'SelectedItem' -ConfigObject $configContent -ConfigKey 'WindowsSKU' -WindowInstance $window
                Set-UIValue -ControlName 'cmbMediaType' -PropertyName 'SelectedItem' -ConfigObject $configContent -ConfigKey 'MediaType' -WindowInstance $window
                Set-UIValue -ControlName 'txtProductKey' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'ProductKey' -WindowInstance $window
                Set-UIValue -ControlName 'txtOptionalFeatures' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'OptionalFeatures' -WindowInstance $window # This will update the text box; checkboxes need separate logic if desired for load.

                # Update Optional Features checkboxes based on the loaded text
                $loadedFeaturesString = $window.FindName('txtOptionalFeatures').Text
                if (-not [string]::IsNullOrWhiteSpace($loadedFeaturesString)) {
                    $loadedFeaturesArray = $loadedFeaturesString.Split(';')
                    WriteLog "LoadConfig: Updating Optional Features checkboxes. Loaded features: $($loadedFeaturesArray -join ', ')"
                    foreach ($featureEntry in $script:featureCheckBoxes.GetEnumerator()) {
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
                    foreach ($featureEntry in $script:featureCheckBoxes.GetEnumerator()) {
                        $featureEntry.Value.IsChecked = $false
                    }
                }

                # M365 Apps/Office tab
                Set-UIValue -ControlName 'chkInstallOffice' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'InstallOffice' -WindowInstance $window
                Set-UIValue -ControlName 'txtOfficePath' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'OfficePath' -WindowInstance $window # Assuming OfficePath is in config
                Set-UIValue -ControlName 'chkCopyOfficeConfigXML' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'CopyOfficeConfigXML' -WindowInstance $window # Assuming CopyOfficeConfigXML is in config
                Set-UIValue -ControlName 'txtOfficeConfigXMLFilePath' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'OfficeConfigXMLFile' -WindowInstance $window # Assuming OfficeConfigXMLFile is in config
                
                # Drivers tab
                Set-UIValue -ControlName 'chkInstallDrivers' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'InstallDrivers' -WindowInstance $window
                Set-UIValue -ControlName 'chkDownloadDrivers' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'DownloadDrivers' -WindowInstance $window # Assuming DownloadDrivers is in config
                Set-UIValue -ControlName 'chkCopyDrivers' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'CopyDrivers' -WindowInstance $window
                Set-UIValue -ControlName 'cmbMake' -PropertyName 'SelectedItem' -ConfigObject $configContent -ConfigKey 'Make' -WindowInstance $window
                # The 'Model' from the config is not directly set to a single UI control.
                # If 'Make' is set, the user would typically click 'Get Models' and select from lstDriverModels.
                # For now, we skip trying to set a non-existent 'cmbModel'.
                # WriteLog "LoadConfig Info: 'Model' key ('$($configContent.Model)') from config is not directly mapped to a single UI input. Set 'Make' and use 'Get Models'."
                Set-UIValue -ControlName 'txtDriversFolder' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'DriversFolder' -WindowInstance $window
                Set-UIValue -ControlName 'txtPEDriversFolder' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'PEDriversFolder' -WindowInstance $window
                Set-UIValue -ControlName 'chkCopyPEDrivers' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'CopyPEDrivers' -WindowInstance $window
                Set-UIValue -ControlName 'chkCompressDriversToWIM' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'CompressDownloadedDriversToWim' -WindowInstance $window


                # Updates tab
                Set-UIValue -ControlName 'chkUpdateLatestCU' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'UpdateLatestCU' -WindowInstance $window
                Set-UIValue -ControlName 'chkUpdateLatestNet' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'UpdateLatestNet' -WindowInstance $window
                Set-UIValue -ControlName 'chkUpdateLatestDefender' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'UpdateLatestDefender' -WindowInstance $window
                Set-UIValue -ControlName 'chkUpdateEdge' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'UpdateEdge' -WindowInstance $window
                Set-UIValue -ControlName 'chkUpdateOneDrive' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'UpdateOneDrive' -WindowInstance $window
                Set-UIValue -ControlName 'chkUpdateLatestMSRT' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'UpdateLatestMSRT' -WindowInstance $window
                Set-UIValue -ControlName 'chkUpdatePreviewCU' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'UpdatePreviewCU' -WindowInstance $window
                
                # Applications tab
                Set-UIValue -ControlName 'chkInstallApps' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'InstallApps' -WindowInstance $window
                Set-UIValue -ControlName 'chkInstallWingetApps' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'InstallWingetApps' -WindowInstance $window # Assuming InstallWingetApps is in config
                Set-UIValue -ControlName 'chkBringYourOwnApps' -PropertyName 'IsChecked' -ConfigObject $configContent -ConfigKey 'BringYourOwnApps' -WindowInstance $window # Assuming BringYourOwnApps is in config
                Set-UIValue -ControlName 'txtApplicationPath' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'AppsPath' -WindowInstance $window
                Set-UIValue -ControlName 'txtAppListJsonPath' -PropertyName 'Text' -ConfigObject $configContent -ConfigKey 'AppListPath' -WindowInstance $window

                # Handle AppsScriptVariables
                $appsScriptVarsKeyExists = $false
                if ($configContent -is [System.Management.Automation.PSCustomObject] -and $null -ne $configContent.PSObject.Properties) {
                    try {
                        if (($configContent.PSObject.Properties.Match('AppsScriptVariables')).Count -gt 0) {
                            $appsScriptVarsKeyExists = $true
                        }
                    } catch { WriteLog "ERROR: Exception while trying to Match key 'AppsScriptVariables'. Error: $($_.Exception.Message)" }
                }

                $lstAppsScriptVars = $window.FindName('lstAppsScriptVariables')
                $chkDefineAppsScriptVars = $window.FindName('chkDefineAppsScriptVariables')
                $appsScriptVarsPanel = $window.FindName('appsScriptVariablesPanel')
                $script:appsScriptVariablesDataList.Clear() # Clear the backing data list

                if ($appsScriptVarsKeyExists -and $null -ne $configContent.AppsScriptVariables -and $configContent.AppsScriptVariables -is [System.Management.Automation.PSCustomObject]) {
                    WriteLog "LoadConfig: Processing AppsScriptVariables from config."
                    $loadedVars = $configContent.AppsScriptVariables
                    $hasVars = $false
                    foreach ($prop in $loadedVars.PSObject.Properties) {
                        $script:appsScriptVariablesDataList.Add([PSCustomObject]@{ IsSelected = $false; Key = $prop.Name; Value = $prop.Value })
                        $hasVars = $true
                    }
                    if ($hasVars) {
                        $chkDefineAppsScriptVars.IsChecked = $true
                        $appsScriptVarsPanel.Visibility = 'Visible'
                        WriteLog "LoadConfig: Loaded AppsScriptVariables and checked 'Define Apps Script Variables'."
                    } else {
                        $chkDefineAppsScriptVars.IsChecked = $false
                        $appsScriptVarsPanel.Visibility = 'Collapsed'
                        WriteLog "LoadConfig: AppsScriptVariables key was present but empty. Unchecked 'Define Apps Script Variables'."
                    }
                } elseif ($appsScriptVarsKeyExists -and $null -ne $configContent.AppsScriptVariables -and $configContent.AppsScriptVariables -is [hashtable]) {
                    # Handle if it's already a hashtable (e.g., from older config or direct creation)
                    WriteLog "LoadConfig: Processing AppsScriptVariables (Hashtable) from config."
                    $loadedVars = $configContent.AppsScriptVariables
                    $hasVars = $false
                    foreach ($keyName in $loadedVars.Keys) {
                        $script:appsScriptVariablesDataList.Add([PSCustomObject]@{ IsSelected = $false; Key = $keyName; Value = $loadedVars[$keyName] })
                        $hasVars = $true
                    }
                    if ($hasVars) {
                        $chkDefineAppsScriptVars.IsChecked = $true
                        $appsScriptVarsPanel.Visibility = 'Visible'
                        WriteLog "LoadConfig: Loaded AppsScriptVariables (Hashtable) and checked 'Define Apps Script Variables'."
                    } else {
                        $chkDefineAppsScriptVars.IsChecked = $false
                        $appsScriptVarsPanel.Visibility = 'Collapsed'
                        WriteLog "LoadConfig: AppsScriptVariables (Hashtable) key was present but empty. Unchecked 'Define Apps Script Variables'."
                    }
                } else {
                    $chkDefineAppsScriptVars.IsChecked = $false
                    $appsScriptVarsPanel.Visibility = 'Collapsed'
                    WriteLog "LoadConfig Info: Key 'AppsScriptVariables' not found, is null, or not a PSCustomObject/Hashtable. Unchecked 'Define Apps Script Variables'."
                }
                # Update the ListView's ItemsSource after populating the data list
                $lstAppsScriptVars.ItemsSource = $script:appsScriptVariablesDataList.ToArray()
                # Update the header checkbox state
                if ($null -ne $script:chkSelectAllAppsScriptVariables) {
                     Update-SelectAllHeaderCheckBoxState -ListView $lstAppsScriptVars -HeaderCheckBox $script:chkSelectAllAppsScriptVariables
                }

                # Update USB Drive selection if present in config
                $usbDriveListKeyExists = $false
                if ($configContent -is [System.Management.Automation.PSCustomObject] -and $null -ne $configContent.PSObject.Properties) {
                    try {
                        if (($configContent.PSObject.Properties.Match('USBDriveList')).Count -gt 0) {
                            $usbDriveListKeyExists = $true
                        }
                    } catch {
                        WriteLog "ERROR: Exception while trying to Match key 'USBDriveList' on configContent.PSObject.Properties. Error: $($_.Exception.Message)"
                    }
                }

                if ($usbDriveListKeyExists -and $null -ne $configContent.USBDriveList) {
                    WriteLog "LoadConfig: Processing USBDriveList from config."
                    # First click the Check USB Drives button to populate the list
                    $script:btnCheckUSBDrives.RaiseEvent(
                        [System.Windows.RoutedEventArgs]::new(
                            [System.Windows.Controls.Button]::ClickEvent
                        )
                    )
                
                    # Then select the drives that match the saved configuration
                    foreach ($item in $script:lstUSBDrives.Items) {
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
                        } else {
                            if (-not $propertyExists -and ($null -ne $configContent.USBDriveList)) {
                                WriteLog "LoadConfig: Property '$($propertyName)' not found on USBDriveList for item Model '$($item.Model)'."
                            }
                            $item.IsSelected = $false # Ensure others are deselected if not in config or value mismatch
                        }
                    }
                    $script:lstUSBDrives.Items.Refresh()

                    # Update the Select All checkbox state
                    $allSelected = $script:lstUSBDrives.Items.Count -gt 0 -and -not ($script:lstUSBDrives.Items | Where-Object { -not $_.IsSelected })
                    $script:chkSelectAllUSBDrives.IsChecked = $allSelected
                    WriteLog "LoadConfig: USBDriveList processing complete."
                } else {
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
                    elseif ($configContent.USBDriveList -is [hashtable]) { # Fallback for older configs
                        if ($configContent.USBDriveList.Keys.Count -gt 0) {
                            $shouldAutoCheckSpecificDrives = $true
                        }
                    }
                }

                if ($shouldAutoCheckSpecificDrives) {
                    WriteLog "LoadConfig: Auto-checking 'Select Specific USB Drives' due to pre-selected USB drives in config."
                    $window.FindName('chkSelectSpecificUSBDrives').IsChecked = $true
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
                    Remove-Application -priority $clickEventArgs.OriginalSource.Tag
                }
            }
        )
    })

# Register cleanup to reclaim memory and revert LongPathsEnabled setting when the UI window closes
$window.Add_Closed({
        # Revert LongPathsEnabled registry setting if it was changed by this script
        if ($script:originalLongPathsValue -ne 1) {
            # Only revert if we changed it from something other than 1
            try {
                $currentValue = Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -ErrorAction SilentlyContinue
                if ($currentValue -eq 1) {
                    # Double-check it's still 1 before reverting
                    $revertValue = if ($null -eq $script:originalLongPathsValue) { 0 } else { $script:originalLongPathsValue } # Revert to original or 0 if it didn't exist
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
