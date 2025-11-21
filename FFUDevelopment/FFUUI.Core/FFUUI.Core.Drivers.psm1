<#
.SYNOPSIS
    Provides functions for managing and downloading hardware drivers in the FFU Builder UI.
.DESCRIPTION
    This module contains all the business logic for the 'Drivers' tab in the FFU Builder UI. It handles fetching driver model lists from various manufacturers (Microsoft, Dell, HP, Lenovo), displaying and filtering them in the UI, and managing the selection state. It also includes functions to import and export driver selections to a JSON file (Drivers.json) and to orchestrate the parallel download of selected driver packages using the common parallel processing module.
#>

function ConvertTo-DriverBaseName {
    param(
        [string]$ModelString
    )

    if ([string]::IsNullOrWhiteSpace($ModelString)) {
        return $ModelString
    }

    if ($ModelString -match '^(.*?)\s*\((.+)\)\s*$') {
        return $matches[1].Trim()
    }

    return $ModelString.Trim()
}

function Get-DriverDisplayName {
    param(
        [string]$BaseName,
        [string]$Identifier
    )

    if ([string]::IsNullOrWhiteSpace($BaseName)) {
        return $Identifier
    }

    if ([string]::IsNullOrWhiteSpace($Identifier)) {
        return $BaseName.Trim()
    }

    return "$($BaseName.Trim()) ($($Identifier.Trim()))"
}

function Convert-DriverItemToJsonModel {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$DriverItem
    )

    $makeName = $DriverItem.Make
    switch ($makeName) {
        'Microsoft' {
            $modelObject = @{ Name = $DriverItem.Model }
            if ($DriverItem.PSObject.Properties['Link'] -and -not [string]::IsNullOrWhiteSpace($DriverItem.Link)) {
                $modelObject.Link = $DriverItem.Link
            }
            return $modelObject
        }
        'Dell' {
            $systemId = if ($DriverItem.PSObject.Properties['SystemId']) { $DriverItem.SystemId } else { $null }
            $baseName = ConvertTo-DriverBaseName -ModelString $DriverItem.Model
            if ([string]::IsNullOrWhiteSpace($baseName)) {
                $baseName = $DriverItem.Model
            }
            $modelObject = @{ Name = $baseName }
            if (-not [string]::IsNullOrWhiteSpace($systemId)) {
                $modelObject.SystemId = $systemId
            }
            if ($DriverItem.PSObject.Properties['CabUrl'] -and -not [string]::IsNullOrWhiteSpace($DriverItem.CabUrl)) {
                $modelObject.CabUrl = $DriverItem.CabUrl
            }
            return $modelObject
        }
        'HP' {
            $baseName = if ($DriverItem.PSObject.Properties['ProductName'] -and -not [string]::IsNullOrWhiteSpace($DriverItem.ProductName)) { $DriverItem.ProductName } else { ConvertTo-DriverBaseName -ModelString $DriverItem.Model }
            if ([string]::IsNullOrWhiteSpace($baseName)) {
                $baseName = $DriverItem.Model
            }
            $systemId = if ($DriverItem.PSObject.Properties['SystemId']) { $DriverItem.SystemId } else { $null }
            $modelObject = @{ Name = $baseName.Trim() }
            if (-not [string]::IsNullOrWhiteSpace($systemId)) {
                $modelObject.SystemId = $systemId
            }
            return $modelObject
        }
        'Lenovo' {
            $machineType = $DriverItem.MachineType
            $baseName = if ($DriverItem.ProductName) { $DriverItem.ProductName } else { ConvertTo-DriverBaseName -ModelString $DriverItem.Model }
            if ([string]::IsNullOrWhiteSpace($baseName) -or [string]::IsNullOrWhiteSpace($machineType)) {
                WriteLog "Skipping Lenovo driver '$($DriverItem.Model)' because Name or MachineType is missing."
                return $null
            }
            return @{
                Name        = $baseName
                MachineType = $machineType
            }
        }
                default {
                    WriteLog "Convert-DriverItemToJsonModel: Unsupported Make '$makeName'."
                    return $null
                }
            }
        }
        
        function Remove-DriverModelFolder {
            param(
                [Parameter(Mandatory = $true)]
                [string]$DriversFolder,
                [Parameter(Mandatory = $true)]
                [string]$TargetFolder,
                [string]$Description
            )
        
            if ([string]::IsNullOrWhiteSpace($DriversFolder) -or [string]::IsNullOrWhiteSpace($TargetFolder)) {
                return
            }
        
            try {
                if (-not (Test-Path -Path $TargetFolder -PathType Container)) {
                    return
                }
        
                $driversRoot = [System.IO.Path]::GetFullPath((Resolve-Path -Path $DriversFolder -ErrorAction Stop).ProviderPath)
                $targetPath = [System.IO.Path]::GetFullPath((Resolve-Path -Path $TargetFolder -ErrorAction Stop).ProviderPath)
        
                if ($targetPath -eq $driversRoot) {
                    WriteLog "Remove-DriverModelFolder skipped deleting Drivers root: $targetPath"
                    return
                }
        
                if (-not ($targetPath.StartsWith($driversRoot, [System.StringComparison]::OrdinalIgnoreCase))) {
                    WriteLog "Remove-DriverModelFolder skipped path outside Drivers root: $targetPath"
                    return
                }
        
                $contextMessage = if ([string]::IsNullOrWhiteSpace($Description)) { $targetPath } else { "$Description ($targetPath)" }
                WriteLog "Removing driver folder $contextMessage due to failure."
                Remove-Item -Path $targetPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            catch {
                WriteLog "Remove-DriverModelFolder failed for $($TargetFolder): $($_.Exception.Message)"
            }
        }
        
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

    $modelDisplay = $RawDriverObject.Model
    $id = $RawDriverObject.Model
    $link = $null
    $productName = $null
    $machineType = $null
    $systemId = $null

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

    # HP specific handling
    if ($Make -eq 'HP') {
        $productName = if ($RawDriverObject.PSObject.Properties['ProductName'] -and -not [string]::IsNullOrWhiteSpace($RawDriverObject.ProductName)) { $RawDriverObject.ProductName } else { ConvertTo-DriverBaseName -ModelString $RawDriverObject.Model }
        if ([string]::IsNullOrWhiteSpace($productName)) { $productName = $RawDriverObject.Model }
        if ($RawDriverObject.PSObject.Properties['SystemId'] -and -not [string]::IsNullOrWhiteSpace($RawDriverObject.SystemId)) {
            $systemId = $RawDriverObject.SystemId
        }
        $modelDisplay = if ([string]::IsNullOrWhiteSpace($systemId)) { $productName } else { Get-DriverDisplayName -BaseName $productName -Identifier $systemId }
        $id = if ([string]::IsNullOrWhiteSpace($systemId)) { $productName } else { $systemId }
    }

    # Dell-specific passthrough (needed for per-model cab workflow)
    $dellBrand = $null
    $dellModelNumber = $null
    $dellSystemId = $null
    $dellCabUrl = $null
    if ($Make -eq 'Dell') {
        if ($RawDriverObject.PSObject.Properties['Brand']) { $dellBrand = $RawDriverObject.Brand }
        if ($RawDriverObject.PSObject.Properties['ModelNumber']) { $dellModelNumber = $RawDriverObject.ModelNumber }
        if ($RawDriverObject.PSObject.Properties['SystemId']) { $dellSystemId = $RawDriverObject.SystemId }
        if ($RawDriverObject.PSObject.Properties['CabUrl']) { $dellCabUrl = $RawDriverObject.CabUrl }
    }

    $output = [PSCustomObject]@{
        IsSelected     = $false
        Make           = $Make
        Model          = $modelDisplay
        Link           = $link
        Id             = $id
        ProductName    = $productName
        MachineType    = $machineType
        Version        = ""
        Type           = ""
        Size           = ""
        Arch           = ""
        DownloadStatus = ""
    }

    if ($Make -eq 'Dell') {
        # Add Dell-only fields so Save-DellDriversTask can use CabUrl
        $output | Add-Member -NotePropertyName Brand           -NotePropertyValue $dellBrand
        $output | Add-Member -NotePropertyName ModelNumber     -NotePropertyValue $dellModelNumber
        $output | Add-Member -NotePropertyName SystemId        -NotePropertyValue $dellSystemId
        $output | Add-Member -NotePropertyName CabUrl          -NotePropertyValue $dellCabUrl
    }
    elseif ($Make -eq 'HP' -and -not [string]::IsNullOrWhiteSpace($systemId)) {
        $output | Add-Member -NotePropertyName SystemId -NotePropertyValue $systemId
    }

    return $output
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

    # Ensure the ItemsSource is always the master list. This prevents inconsistency.
    if ($State.Controls.lstDriverModels.ItemsSource -ne $State.Data.allDriverModels) {
        $State.Controls.lstDriverModels.ItemsSource = $State.Data.allDriverModels
    }

    # Get the default view of the items source, which supports filtering.
    $collectionView = [System.Windows.Data.CollectionViewSource]::GetDefaultView($State.Controls.lstDriverModels.ItemsSource)
    if ($null -eq $collectionView) {
        WriteLog "Search-DriverModels: Could not get CollectionView. Filtering may not work."
        return
    }

    WriteLog "Applying filter with text: '$filterText'"

    if ([string]::IsNullOrWhiteSpace($filterText)) {
        # If filter is empty, remove any existing filter
        $collectionView.Filter = $null
    }
    else {
        # Apply a filter predicate. This is the correct WPF way to filter.
        $collectionView.Filter = {
            param($item)
            # $item is the PSCustomObject from the list
            return $item.Model -like "*$filterText*"
        }
    }
    
    # The view will automatically refresh. No need to call .Refresh() explicitly for filtering.
    $filteredCount = 0
    if ($null -ne $collectionView) {
        foreach ($item in $collectionView) { $filteredCount++ }
    }
    WriteLog "Filter applied. View now contains $filteredCount models."
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
            $modelObject = Convert-DriverItemToJsonModel -DriverItem $driverItem
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
    $ofd.InitialDirectory = Join-Path -Path $State.FFUDevelopmentPath -ChildPath "Drivers"

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
        
                    $normalizedName = $importedModelNameFromObject
                    $skipModel = $false
                    switch ($makeName) {
                        'Lenovo' {
                            $productName = if ($importedModelObject.PSObject.Properties['ProductName'] -and -not [string]::IsNullOrWhiteSpace($importedModelObject.ProductName)) { $importedModelObject.ProductName } else { ConvertTo-DriverBaseName -ModelString $normalizedName }
                            $machineType = if ($importedModelObject.PSObject.Properties['MachineType'] -and -not [string]::IsNullOrWhiteSpace($importedModelObject.MachineType)) { $importedModelObject.MachineType } else { $null }
                            if ([string]::IsNullOrWhiteSpace($machineType) -and $normalizedName -match '(.+?)\s*\((.+?)\)$') {
                                if ([string]::IsNullOrWhiteSpace($productName)) { $productName = $matches[1].Trim() }
                                $machineType = $matches[2].Trim()
                            }
                            if ([string]::IsNullOrWhiteSpace($productName) -or [string]::IsNullOrWhiteSpace($machineType)) {
                                WriteLog "Import-DriversJson: Skipping Lenovo model '$normalizedName' due to missing ProductName or MachineType."
                                $skipModel = $true
                            }
                            else {
                                $normalizedName = Get-DriverDisplayName -BaseName $productName -Identifier $machineType
                                if ($importedModelObject.PSObject.Properties['ProductName']) {
                                    $importedModelObject.ProductName = $productName
                                }
                                else {
                                    $importedModelObject | Add-Member -NotePropertyName ProductName -NotePropertyValue $productName
                                }
                                if ($importedModelObject.PSObject.Properties['MachineType']) {
                                    $importedModelObject.MachineType = $machineType
                                }
                                else {
                                    $importedModelObject | Add-Member -NotePropertyName MachineType -NotePropertyValue $machineType
                                }
                            }
                        }
                        'Dell' {
                            $baseName = ConvertTo-DriverBaseName -ModelString $normalizedName
                            if ([string]::IsNullOrWhiteSpace($baseName)) { $baseName = $normalizedName }
                            $systemId = if ($importedModelObject.PSObject.Properties['SystemId'] -and -not [string]::IsNullOrWhiteSpace($importedModelObject.SystemId)) { $importedModelObject.SystemId } else { $null }
                            if ([string]::IsNullOrWhiteSpace($systemId) -and $normalizedName -match '(.+?)\s*\((.+?)\)$') {
                                if ([string]::IsNullOrWhiteSpace($baseName)) { $baseName = $matches[1].Trim() }
                                $systemId = $matches[2].Trim()
                            }
                            $normalizedName = if ([string]::IsNullOrWhiteSpace($systemId)) { $baseName.Trim() } else { Get-DriverDisplayName -BaseName $baseName -Identifier $systemId }
                            if ($importedModelObject.PSObject.Properties['SystemId']) {
                                $importedModelObject.SystemId = $systemId
                            }
                            else {
                                $importedModelObject | Add-Member -NotePropertyName SystemId -NotePropertyValue $systemId
                            }
                        }
                        'HP' {
                            $baseName = ConvertTo-DriverBaseName -ModelString $normalizedName
                            if ([string]::IsNullOrWhiteSpace($baseName)) { $baseName = $normalizedName }
                            $systemId = if ($importedModelObject.PSObject.Properties['SystemId'] -and -not [string]::IsNullOrWhiteSpace($importedModelObject.SystemId)) { $importedModelObject.SystemId } else { $null }
                            if ([string]::IsNullOrWhiteSpace($systemId) -and $normalizedName -match '(.+?)\s*\((.+?)\)$') {
                                if ([string]::IsNullOrWhiteSpace($baseName)) { $baseName = $matches[1].Trim() }
                                $systemId = $matches[2].Trim()
                            }
                            $normalizedName = if ([string]::IsNullOrWhiteSpace($systemId)) { $baseName.Trim() } else { Get-DriverDisplayName -BaseName $baseName -Identifier $systemId }
                            if ($importedModelObject.PSObject.Properties['ProductName']) {
                                $importedModelObject.ProductName = $baseName
                            }
                            else {
                                $importedModelObject | Add-Member -NotePropertyName ProductName -NotePropertyValue $baseName
                            }
                            if ($importedModelObject.PSObject.Properties['SystemId']) {
                                $importedModelObject.SystemId = $systemId
                            }
                            else {
                                $importedModelObject | Add-Member -NotePropertyName SystemId -NotePropertyValue $systemId
                            }
                        }
                        default {
                            $normalizedName = $normalizedName.Trim()
                        }
                    }
        
                    if ($skipModel) {
                        continue
                    }
        
                    if ([string]::IsNullOrWhiteSpace($normalizedName)) {
                        WriteLog "Import-DriversJson: Skipping normalized model name for Make '$makeName'."
                        continue
                    }
        
                    $importedModelObject.Name = $normalizedName
                    $importedModelNameFromObject = $normalizedName
        
                    $existingModel = $State.Data.allDriverModels | Where-Object { $_.Make -eq $makeName -and $_.Model -eq $importedModelNameFromObject } | Select-Object -First 1

                    if ($null -ne $existingModel) {
                        $existingModel.IsSelected = $true
                        $existingModel.DownloadStatus = "Imported"
                        $existingModel.Model = $importedModelNameFromObject
                    
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
                                $existingModel.Id = $importedModelObject.MachineType
                                $updateExistingLenovo = $true
                            }
                            if ($updateExistingLenovo) {
                                WriteLog "Import-DriversJson: Updated ProductName/MachineType/Id for existing Lenovo model '$($existingModel.Model)'."
                            }
                        }
                        elseif ($makeName -eq 'Dell') {
                            # Update Dell extended fields if provided
                            if ($importedModelObject.PSObject.Properties['SystemId'] -and $existingModel.PSObject.Properties['SystemId'] -and -not [string]::IsNullOrWhiteSpace($importedModelObject.SystemId)) {
                                if ($existingModel.SystemId -ne $importedModelObject.SystemId) {
                                    $existingModel.SystemId = $importedModelObject.SystemId
                                    WriteLog "Import-DriversJson: Updated SystemId for existing Dell model '$($existingModel.Model)'."
                                }
                            }
                            if ($importedModelObject.PSObject.Properties['CabUrl'] -and $existingModel.PSObject.Properties['CabUrl'] -and -not [string]::IsNullOrWhiteSpace($importedModelObject.CabUrl)) {
                                if ($existingModel.CabUrl -ne $importedModelObject.CabUrl) {
                                    $existingModel.CabUrl = $importedModelObject.CabUrl
                                    WriteLog "Import-DriversJson: Updated CabUrl for existing Dell model '$($existingModel.Model)'."
                                }
                            }
                        }
                        elseif ($makeName -eq 'HP') {
                            $importedProductName = if ($importedModelObject.PSObject.Properties['ProductName'] -and -not [string]::IsNullOrWhiteSpace($importedModelObject.ProductName)) { $importedModelObject.ProductName } else { ConvertTo-DriverBaseName -ModelString $importedModelNameFromObject }
                            if ([string]::IsNullOrWhiteSpace($importedProductName)) { $importedProductName = $importedModelNameFromObject }
                            if ($importedModelObject.PSObject.Properties['SystemId'] -and -not [string]::IsNullOrWhiteSpace($importedModelObject.SystemId)) {
                                $importedId = $importedModelObject.SystemId
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
                            Model          = $importedModelNameFromObject
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
                        if ($makeName -eq 'Dell') {
                            # Attach optional Dell extended fields if present
                            if ($importedModelObject.PSObject.Properties['SystemId'] -and -not [string]::IsNullOrWhiteSpace($importedModelObject.SystemId)) {
                                $newDriverModel | Add-Member -NotePropertyName SystemId -NotePropertyValue $importedModelObject.SystemId
                            }
                            if ($importedModelObject.PSObject.Properties['CabUrl'] -and -not [string]::IsNullOrWhiteSpace($importedModelObject.CabUrl)) {
                                $newDriverModel | Add-Member -NotePropertyName CabUrl -NotePropertyValue $importedModelObject.CabUrl
                            }
                        }
                        elseif ($makeName -eq 'HP') {
                            if ($importedModelObject.PSObject.Properties['SystemId'] -and -not [string]::IsNullOrWhiteSpace($importedModelObject.SystemId)) {
                                $newDriverModel | Add-Member -NotePropertyName SystemId -NotePropertyValue $importedModelObject.SystemId
                            }
                        }
                        $State.Data.allDriverModels.Add($newDriverModel)
                        $newModelsAdded++
                        WriteLog "Import-DriversJson: Added new model '$($newDriverModel.Make) - $($newDriverModel.Model)' from import. ID: $($newDriverModel.Id), Link: $($newDriverModel.Link)"
                    }
                }
            }

            # Sort the full list of models
            $sortedModels = $State.Data.allDriverModels | Sort-Object @{Expression = { $_.IsSelected }; Descending = $true }, Make, Model

            # Create a new list from the sorted results and assign it to the state.
            # This prevents the "ItemsControl inconsistent" error by replacing the source instead of modifying it.
            $newList = [System.Collections.Generic.List[PSCustomObject]]::new()
            if ($null -ne $sortedModels) {
                foreach ($model in @($sortedModels)) {
                    $newList.Add($model)
                }
            }
            $State.Data.allDriverModels = $newList
            
            # Update the UI and apply any existing filter
            $State.Controls.lstDriverModels.ItemsSource = $State.Data.allDriverModels
            Search-DriverModels -filterText $State.Controls.txtModelFilter.Text -State $State

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

# Function to handle the 'Get Models' button click logic
function Invoke-GetModels {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$State,
        [Parameter(Mandatory = $true)]
        [object]$Button
    )

    $selectedMake = $State.Controls.cmbMake.SelectedItem
    $State.Controls.txtStatus.Text = "Getting models for $selectedMake..."
    $State.Window.Cursor = [System.Windows.Input.Cursors]::Wait
    $Button.IsEnabled = $false
    try {
        # Get ALL previously selected models to preserve them, regardless of make.
        $allPreviouslySelectedModels = @($State.Data.allDriverModels | Where-Object { $_.IsSelected })

        # Get newly fetched models for the current make
        $newlyFetchedStandardizedModels = Get-ModelsForMake -SelectedMake $selectedMake -State $State

        $combinedModelsList = [System.Collections.Generic.List[PSCustomObject]]::new()
        $modelIdentifiersInCombinedList = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

        # Add all previously selected models first to preserve their 'IsSelected' state.
        foreach ($item in $allPreviouslySelectedModels) {
            $combinedModelsList.Add($item)
            $modelIdentifiersInCombinedList.Add("$($item.Make)::$($item.Model)") | Out-Null
        }

        # Add newly fetched models, but only if they are not already in the list.
        # This prevents overwriting a selected model with an unselected one.
        $addedNewCount = 0
        foreach ($item in $newlyFetchedStandardizedModels) {
            if ($modelIdentifiersInCombinedList.Add("$($item.Make)::$($item.Model)")) {
                $combinedModelsList.Add($item)
                $addedNewCount++
            }
        }

        # Sort the combined list
        $sortedModels = $combinedModelsList | Sort-Object @{Expression = { $_.IsSelected }; Descending = $true }, Make, Model

        # Create a new list object from the sorted results. This is safer than modifying the existing list
        # that the UI is bound to, which can cause inconsistency errors.
        $newList = [System.Collections.Generic.List[PSCustomObject]]::new()
        if ($null -ne $sortedModels) {
            # Sort-Object can return a single object or an array. Ensure it's always treated as a collection.
            foreach ($model in @($sortedModels)) {
                $newList.Add($model)
            }
        }
        $State.Data.allDriverModels = $newList
        
        # Update the UI ItemsSource to point to the new list and clear the filter
        $State.Controls.lstDriverModels.ItemsSource = $State.Data.allDriverModels
        $State.Controls.txtModelFilter.Text = ""

        if ($State.Data.allDriverModels.Count -gt 0) {
            $State.Controls.spModelFilterSection.Visibility = 'Visible'
            $State.Controls.lstDriverModels.Visibility = 'Visible'
            $State.Controls.spDriverActionButtons.Visibility = 'Visible'
            $statusText = "Displaying $($State.Data.allDriverModels.Count) models."
            if ($newlyFetchedStandardizedModels.Count -gt 0 -and $addedNewCount -eq 0 -and $allPreviouslySelectedModels.Count -gt 0) {
                $statusText = "Fetched $($newlyFetchedStandardizedModels.Count) models for $selectedMake; all were already in the selected list. Displaying $($State.Data.allDriverModels.Count) total selected models."
            }
            elseif ($addedNewCount -gt 0) {
                $statusText = "Added $addedNewCount new models for $selectedMake. Displaying $($State.Data.allDriverModels.Count) total models."
            }
            elseif ($newlyFetchedStandardizedModels.Count -eq 0 -and $selectedMake -eq 'Lenovo' ) {
                $statusText = if ($allPreviouslySelectedModels.Count -gt 0) { "No new models found for $selectedMake. Displaying $($allPreviouslySelectedModels.Count) previously selected models." } else { "No models found for $selectedMake." }
            }
            elseif ($newlyFetchedStandardizedModels.Count -eq 0) {
                $statusText = "No new models found for $selectedMake. Displaying $($State.Data.allDriverModels.Count) previously selected models."
            }
            $State.Controls.txtStatus.Text = $statusText
        }
        else {
            $State.Controls.spModelFilterSection.Visibility = 'Collapsed'
            $State.Controls.lstDriverModels.Visibility = 'Collapsed'
            $State.Controls.spDriverActionButtons.Visibility = 'Collapsed'
            $State.Controls.txtStatus.Text = "No models to display for $selectedMake."
        }
    }
    catch {
        $State.Controls.txtStatus.Text = "Error getting models: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show("Error getting models: $($_.Exception.Message)", "Error", "OK", "Error")
        if ($null -eq $State.Data.allDriverModels -or $State.Data.allDriverModels.Count -eq 0) {
            $State.Controls.spModelFilterSection.Visibility = 'Collapsed'
            $State.Controls.lstDriverModels.Visibility = 'Collapsed'
            $State.Controls.spDriverActionButtons.Visibility = 'Collapsed'
            $State.Controls.lstDriverModels.ItemsSource = $null
            $State.Controls.txtModelFilter.Text = ""
        }
    }
    finally {
        $State.Window.Cursor = $null
        $Button.IsEnabled = $true
    }
}

# Function to handle the 'Download Selected Drivers' button click logic
function Invoke-DownloadSelectedDrivers {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$State,
        [Parameter(Mandatory = $true)]
        [object]$Button
    )

    $selectedDrivers = @($State.Data.allDriverModels | Where-Object { $_.IsSelected })
    if (-not $selectedDrivers) {
        [System.Windows.MessageBox]::Show("No drivers selected to download.", "Download Drivers", "OK", "Information")
        return
    }

    $Button.IsEnabled = $false
    $State.Controls.pbOverallProgress.Visibility = 'Visible'
    $State.Controls.pbOverallProgress.Value = 0
    $State.Controls.txtStatus.Text = "Preparing driver downloads..."

    # Define common necessary task-specific variables locally
    # Ensure required selections are made
    if ($null -eq $State.Controls.cmbWindowsRelease.SelectedItem) {
        [System.Windows.MessageBox]::Show("Please select a Windows Release.", "Missing Information", "OK", "Warning")
        $Button.IsEnabled = $true
        $State.Controls.pbOverallProgress.Visibility = 'Collapsed'
        $State.Controls.txtStatus.Text = "Driver download cancelled."
        return
    }
    if ($null -eq $State.Controls.cmbWindowsArch.SelectedItem) {
        [System.Windows.MessageBox]::Show("Please select a Windows Architecture.", "Missing Information", "OK", "Warning")
        $Button.IsEnabled = $true
        $State.Controls.pbOverallProgress.Visibility = 'Collapsed'
        $State.Controls.txtStatus.Text = "Driver download cancelled."
        return
    }
    if (($selectedDrivers | Where-Object { $_.Make -eq 'HP' }) -and $null -ne $State.Controls.cmbWindowsVersion -and $null -eq $State.Controls.cmbWindowsVersion.SelectedItem) {
        [System.Windows.MessageBox]::Show("HP drivers are selected. Please select a Windows Version.", "Missing Information", "OK", "Warning")
        $Button.IsEnabled = $true
        $State.Controls.pbOverallProgress.Visibility = 'Collapsed'
        $State.Controls.txtStatus.Text = "Driver download cancelled."
        return
    }

    $localDriversFolder = $State.Controls.txtDriversFolder.Text
    $localWindowsRelease = $State.Controls.cmbWindowsRelease.SelectedItem.Value
    $localWindowsArch = $State.Controls.cmbWindowsArch.SelectedItem
    $localWindowsVersion = if ($null -ne $State.Controls.cmbWindowsVersion -and $null -ne $State.Controls.cmbWindowsVersion.SelectedItem) { $State.Controls.cmbWindowsVersion.SelectedItem } else { $null }
    $coreStaticVars = Get-CoreStaticVariables
    $localHeaders = $coreStaticVars.Headers
    $localUserAgent = $coreStaticVars.UserAgent
    $compressDrivers = $State.Controls.chkCompressDriversToWIM.IsChecked
    # Determine if we must preserve source folders (used later for PE driver harvesting)
    $preserveSource = ($State.Controls.chkUseDriversAsPEDrivers.IsChecked -and $State.Controls.chkCompressDriversToWIM.IsChecked)

    $State.Controls.txtStatus.Text = "Processing all selected drivers..."
    WriteLog "Processing all selected drivers: $($selectedDrivers.Model -join ', ')"

    # Pre-process Dell Catalog if needed, so it's not done in parallel
    if ($selectedDrivers | Where-Object { $_.Make -eq 'Dell' }) {
        WriteLog "Dell drivers selected. Ensuring Dell Catalog is up-to-date..."
        try {
            $dellDriversFolder = Join-Path -Path $localDriversFolder -ChildPath "Dell"
            $catalogBaseName = if ($localWindowsRelease -le 11) { "CatalogIndexPC" } else { "Catalog" }
            $dellCabFile = Join-Path -Path $dellDriversFolder -ChildPath "$($catalogBaseName).cab"
            $dellCatalogXML = Join-Path -Path $dellDriversFolder -ChildPath "$($catalogBaseName).xml"
            $catalogUrl = if ($localWindowsRelease -le 11) { "https://downloads.dell.com/catalog/CatalogIndexPC.cab" } else { "https://downloads.dell.com/catalog/Catalog.cab" }

            $downloadCatalog = $true
            if (Test-Path -Path $dellCatalogXML -PathType Leaf) {
                if (((Get-Date) - (Get-Item $dellCatalogXML).CreationTime).TotalDays -lt 7) {
                    WriteLog "Using existing Dell Catalog XML (less than 7 days old): $dellCatalogXML"
                    $downloadCatalog = $false
                }
                else { WriteLog "Existing Dell Catalog XML is older than 7 days: $dellCatalogXML" }
            }
            else { WriteLog "Dell Catalog XML not found: $dellCatalogXML" }

            if ($downloadCatalog) {
                WriteLog "Downloading and extracting Dell Catalog for driver download process..."
                if (-not (Test-Path -Path $dellDriversFolder -PathType Container)) {
                    New-Item -Path $dellDriversFolder -ItemType Directory -Force | Out-Null
                }
                
                if (Test-Path -Path $dellCabFile) { Remove-Item -Path $dellCabFile -Force -ErrorAction SilentlyContinue }
                if (Test-Path -Path $dellCatalogXML) { Remove-Item -Path $dellCatalogXML -Force -ErrorAction SilentlyContinue }

                Start-BitsTransferWithRetry -Source $catalogUrl -Destination $dellCabFile
                Invoke-Process -FilePath "Expand.exe" -ArgumentList """$dellCabFile"" ""$dellCatalogXML""" | Out-Null
                Remove-Item -Path $dellCabFile -Force -ErrorAction SilentlyContinue
                WriteLog "Dell Catalog prepared successfully."
            }
        }
        catch {
            $errorMessage = "Failed to prepare Dell Catalog: $($_.Exception.Message)"
            WriteLog $errorMessage
            [System.Windows.MessageBox]::Show($errorMessage, "Dell Catalog Error", "OK", "Error")
            $Button.IsEnabled = $true
            $State.Controls.pbOverallProgress.Visibility = 'Collapsed'
            $State.Controls.txtStatus.Text = "Driver download cancelled due to Dell Catalog error."
            return
        }
    }
    $preserveSource = ($State.Controls.chkUseDriversAsPEDrivers.IsChecked -and $State.Controls.chkCompressDriversToWIM.IsChecked)
    $taskArguments = @{
        DriversFolder            = $localDriversFolder
        WindowsRelease           = $localWindowsRelease
        WindowsArch              = $localWindowsArch
        WindowsVersion           = $localWindowsVersion
        Headers                  = $localHeaders
        UserAgent                = $localUserAgent
        CompressToWim            = $compressDrivers
        PreserveSourceOnCompress = $preserveSource
    }

    $parallelResults = Invoke-ParallelProcessing -ItemsToProcess $selectedDrivers `
        -ListViewControl $State.Controls.lstDriverModels `
        -IdentifierProperty 'Model' `
        -StatusProperty 'DownloadStatus' `
        -TaskType 'DownloadDriverByMake' `
        -TaskArguments $taskArguments `
        -CompletedStatusText 'Completed' `
        -ErrorStatusPrefix 'Error: ' `
        -WindowObject $State.Window `
        -MainThreadLogPath $State.LogFilePath `
        -ThrottleLimit $State.Controls.txtThreads.Text

    $overallSuccess = $true
    $successfullyDownloaded = [System.Collections.Generic.List[PSCustomObject]]::new()
    $failedDownloads = [System.Collections.Generic.List[PSCustomObject]]::new()

    # Check the results from the parallel processing tasks
    if ($null -ne $parallelResults) {
        # Create a lookup from the original selected drivers to retain full metadata for mapping.
        $driverLookup = @{}
        foreach ($driver in $selectedDrivers) {
            if (-not [string]::IsNullOrWhiteSpace($driver.Model)) {
                $driverLookup[$driver.Model] = $driver
            }
        }
    
        # Filter for objects that could be results, avoiding stray log strings
        foreach ($result in ($parallelResults | Where-Object { $_ -is [hashtable] })) {
            if ($null -eq $result) { continue }

            # The result from Invoke-ParallelProcessing is a hashtable.
            # Access properties using their keys.
            $modelName = $result['Identifier']
            $resultCode = $result['ResultCode']
            $driverPath = $result['DriverPath']

            if ([string]::IsNullOrWhiteSpace($modelName)) {
                WriteLog "Could not determine model name from result object: $($result | ConvertTo-Json -Compress -Depth 3)"
                $overallSuccess = $false
                $failedDownloads.Add([PSCustomObject]@{
                        Model  = 'Unknown model'
                        Status = 'Driver task returned without a model identifier.'
                    })
                continue
            }

            if ($resultCode -ne 0) {
                $overallSuccess = $false
                $failureStatus = $result['Status']
                if ([string]::IsNullOrWhiteSpace($failureStatus)) { $failureStatus = 'Driver download failed. Check the log for details.' }
                $failedDownloads.Add([PSCustomObject]@{
                        Model  = $modelName
                        Status = $failureStatus
                    })
                WriteLog "Error detected for model $modelName."
            }
            elseif (-not [string]::IsNullOrWhiteSpace($driverPath)) {
                # The task was successful and returned a driver path.
                $driverMetadata = $null
                if (-not [string]::IsNullOrWhiteSpace($modelName) -and $driverLookup.ContainsKey($modelName)) {
                    $driverMetadata = $driverLookup[$modelName]
                }

                if ($driverMetadata) {
                    $driverRecord = [PSCustomObject]@{
                        Make       = $driverMetadata.Make
                        Model      = $modelName
                        DriverPath = $driverPath
                    }
                    if ($driverMetadata.PSObject.Properties['SystemId'] -and -not [string]::IsNullOrWhiteSpace($driverMetadata.SystemId)) {
                        $driverRecord | Add-Member -NotePropertyName SystemId -NotePropertyValue $driverMetadata.SystemId
                    }
                    if ($driverMetadata.PSObject.Properties['MachineType'] -and -not [string]::IsNullOrWhiteSpace($driverMetadata.MachineType)) {
                        $driverRecord | Add-Member -NotePropertyName MachineType -NotePropertyValue $driverMetadata.MachineType
                    }
                    if ($driverMetadata.PSObject.Properties['ProductName'] -and -not [string]::IsNullOrWhiteSpace($driverMetadata.ProductName)) {
                        $driverRecord | Add-Member -NotePropertyName ProductName -NotePropertyValue $driverMetadata.ProductName
                    }
                    $successfullyDownloaded.Add($driverRecord)
                }
                else {
                    WriteLog "Warning: Could not find driver metadata for successful download of model '$modelName'. Skipping from DriverMapping.json."
                }
            }
            else {
                $overallSuccess = $false
                $fallbackStatus = $result['Status']
                if ([string]::IsNullOrWhiteSpace($fallbackStatus)) { $fallbackStatus = 'Driver download did not return a driver path.' }
                $failedDownloads.Add([PSCustomObject]@{
                        Model  = $modelName
                        Status = $fallbackStatus
                    })
                WriteLog "Driver download did not provide a path for model $modelName."
            }
        }
    }

    # Update the driver mapping JSON if there are any successful downloads
    if ($successfullyDownloaded.Count -gt 0) {
        try {
            WriteLog "Updating DriverMapping.json with $($successfullyDownloaded.Count) successfully downloaded drivers."
            Update-DriverMappingJson -DownloadedDrivers $successfullyDownloaded -DriversFolder $localDriversFolder
        }
        catch {
            WriteLog "Failed to update DriverMapping.json: $($_.Exception.Message)"
            # This is not a fatal error for the download process itself, so just show a warning.
            [System.Windows.MessageBox]::Show("The driver download process completed, but failed to update the DriverMapping.json file. Please check the log for details.", "Driver Mapping Error", "OK", "Warning")
        }
    }

    # Automatically save the selected drivers to the specified Drivers.json path
    $driversJsonPath = $State.Controls.txtDriversJsonPath.Text
    if (-not [string]::IsNullOrWhiteSpace($driversJsonPath) -and $selectedDrivers.Count -gt 0) {
        WriteLog "Attempting to automatically save selected drivers list to $driversJsonPath"
        try {
            $outputJson = @{} # Use a Hashtable for the desired structure

            $selectedDrivers | Group-Object -Property Make | ForEach-Object {
                $makeName = $_.Name
                $modelsForThisMake = @() # Initialize an array to hold model objects

                            foreach ($driverItem in $_.Group) {
                        $modelObject = Convert-DriverItemToJsonModel -DriverItem $driverItem
                        if ($null -ne $modelObject) {
                            $modelsForThisMake += $modelObject
                        }
                    }
            
                    if ($modelsForThisMake.Count -gt 0) {
                        $outputJson[$makeName] = @{ Models = $modelsForThisMake }
                    }
                }

            # Ensure directory exists
            $parentDir = Split-Path -Path $driversJsonPath -Parent
            if (-not (Test-Path -Path $parentDir -PathType Container)) {
                WriteLog "Creating directory for Drivers.json: $parentDir"
                New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
            }

            $outputJson | ConvertTo-Json -Depth 5 | Set-Content -Path $driversJsonPath -Encoding UTF8
            WriteLog "Successfully auto-saved selected drivers to $driversJsonPath"
        }
        catch {
            WriteLog "Failed to automatically save selected drivers to $driversJsonPath. Error: $($_.Exception.Message)"
            # This is a best-effort operation, so we only log the error and don't bother the user with a popup.
        }
    }

    $State.Controls.pbOverallProgress.Visibility = 'Collapsed'
    $Button.IsEnabled = $true
    if ($overallSuccess) {
        $State.Controls.txtStatus.Text = "All selected driver downloads processed."
        [System.Windows.MessageBox]::Show("All selected driver downloads processed. Check status column for details.", "Download Process Finished", "OK", "Information")
    }
    else {
        $State.Controls.txtStatus.Text = "Driver download failed. Resolve the errors and try again."
        $messageLines = [System.Collections.Generic.List[string]]::new()
        if ($failedDownloads.Count -gt 0) {
            $messageLines.Add("Driver download failed for:")
            foreach ($item in ($failedDownloads | Select-Object -First 5)) {
                $messageLines.Add("- $($item.Model): $($item.Status)")
            }
            if ($failedDownloads.Count -gt 5) {
                $messageLines.Add("...see the log for additional failures.")
            }
        }
        else {
            $messageLines.Add("One or more driver downloads failed. Check the log for details.")
        }
        [System.Windows.MessageBox]::Show(($messageLines -join [System.Environment]::NewLine), "Driver Download Failed", "OK", "Error")
    }
}

Export-ModuleMember -Function *