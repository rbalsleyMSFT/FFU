# Helper function to get models for a selected Make and standardize them
function Get-ModelsForMake {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SelectedMake,
        [Parameter(Mandatory = $true)]
        [psobject]$State
    )

    $standardizedModels = [System.Collections.Generic.List[PSCustomObject]]::new()
    $rawModels = @()

    # Get necessary values from UI or script scope
    $localDriversFolder = $State.Controls.txtDriversFolder.Text
    $localWindowsRelease = $null
    if ($null -ne $State.Controls.cmbWindowsRelease.SelectedItem) {
        $localWindowsRelease = $State.Controls.cmbWindowsRelease.SelectedItem.Value
    }

    # Get headers and user agent from Get-CoreStaticVariables
    $staticVars = Get-CoreStaticVariables
    $Headers = $staticVars.Headers
    $UserAgent = $staticVars.UserAgent

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
            $State.Controls.txtStatus.Text = "Searching Lenovo models for '$modelSearchTerm'..."
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
            $standardizedModels.Add((ConvertTo-StandardizedDriverModel -RawDriverObject $rawModel -Make $SelectedMake -State $State))
        }
    }

    return $standardizedModels.ToArray()
}

# Helper function to convert raw driver objects to a standardized format
function ConvertTo-StandardizedDriverModel {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$RawDriverObject,
        [Parameter(Mandatory = $true)]
        [string]$Make,
        [Parameter(Mandatory = $true)]
        [psobject]$State
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
        $modelDisplay = $RawDriverObject.Model 
        $productName = $RawDriverObject.ProductName
        $machineType = $RawDriverObject.MachineType
        $id = $RawDriverObject.MachineType 
    }

    return [PSCustomObject]@{
        IsSelected     = $false
        Make           = $Make
        Model          = $modelDisplay 
        Link           = $link
        Id             = $id            
        ProductName    = $productName   
        MachineType    = $machineType   
        Version        = "" # Placeholder
        Type           = "" # Placeholder
        Size           = "" # Placeholder
        Arch           = "" # Placeholder
        DownloadStatus = "" # Initial download status
    }
}

# Function to filter the driver model list based on text input
function Search-DriverModels {
    param(
        [string]$filterText,
        [Parameter(Mandatory = $true)]
        [psobject]$State
    )
    # Check if UI elements and the full list are available
    if ($null -eq $State.Controls.lstDriverModels -or $null -eq $State.Data.allDriverModels) {
        WriteLog "Search-DriverModels: ListView or full model list not available."
        return
    }

    WriteLog "Filtering models with text: '$filterText'"

    # Filter the full list based on the Model property (case-insensitive)
    # Ensure the result is always an array, even if only one item matches
    $filteredModels = @($State.Data.allDriverModels | Where-Object { $_.Model -like "*$filterText*" })

    # Update the ListView's ItemsSource with the filtered list
    # Setting ItemsSource directly should work for simple scenarios
    $State.Controls.lstDriverModels.ItemsSource = $filteredModels

    # Explicitly refresh the ListView's view to reflect the changes in the bound source
    if ($null -ne $State.Controls.lstDriverModels.ItemsSource -and $State.Controls.lstDriverModels.Items -is [System.ComponentModel.ICollectionView]) {
        $State.Controls.lstDriverModels.Items.Refresh()
    }
    elseif ($null -ne $State.Controls.lstDriverModels.ItemsSource) {
        # Fallback refresh if not using ICollectionView (less common for direct ItemsSource binding)
        $State.Controls.lstDriverModels.Items.Refresh()
    }


    WriteLog "Filtered list contains $($filteredModels.Count) models."
}

# Function to save selected driver models to a JSON file
function Save-DriversJson {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$State
    )
    WriteLog "Save-DriversJson function called."
    $selectedDrivers = @($State.Controls.lstDriverModels.Items | Where-Object { $_.IsSelected })

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
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$State
    )
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

            if ($null -eq $State.Data.allDriverModels) {
                $State.Data.allDriverModels = @()
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

                    $existingModel = $State.Data.allDriverModels | Where-Object { $_.Make -eq $makeName -and $_.Model -eq $importedModelNameFromObject } | Select-Object -First 1

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
                        $State.Data.allDriverModels += $newDriverModel
                        $newModelsAdded++
                        WriteLog "Import-DriversJson: Added new model '$($newDriverModel.Make) - $($newDriverModel.Model)' from import. ID: $($newDriverModel.Id), Link: $($newDriverModel.Link)"
                    }
                }
            }

            $State.Data.allDriverModels = $State.Data.allDriverModels | Sort-Object @{Expression = { $_.IsSelected }; Descending = $true }, Make, Model

            Search-DriverModels -filterText $State.Controls.txtModelFilter.Text -State $script:uiState

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

Export-ModuleMember -Function *