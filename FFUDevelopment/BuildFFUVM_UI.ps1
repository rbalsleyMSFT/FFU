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
$AppsPath = "$FFUDevelopmentPath\Apps"
$AppListJsonPath = "$AppsPath\AppList.json"
$UserAppListJsonPath = "$AppsPath\UserAppList.json" # Define path for UserAppList.json

# --- NEW: Central State Object ---
$script:uiState = [PSCustomObject]@{
    Window      = $null;
    Controls    = @{
        featureCheckBoxes              = @{}; 
        UpdateInstallAppsBasedOnUpdates = $null 
    };
    Data        = @{
        allDriverModels             = [System.Collections.Generic.List[PSCustomObject]]::new();
        appsScriptVariablesDataList = [System.Collections.Generic.List[PSCustomObject]]::new();
        versionData                 = $null; 
        vmSwitchMap                 = @{}   
    };
    Flags       = @{
        installAppsForcedByUpdates      = $false;
        prevInstallAppsStateBeforeUpdates = $null;
        installAppsCheckedByOffice      = $false;
        lastSortProperty                = $null;
        lastSortAscending               = $true
    };
    Defaults    = @{};
    LogFilePath = "$FFUDevelopmentPath\FFUDevelopment_UI.log"
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

#Remove old log file if found
if (Test-Path -Path $script:uiState.LogFilePath) {
    Remove-item -Path $script:uiState.LogFilePath -Force
}

# Function to refresh the Windows Release ComboBox based on ISO path
function Update-WindowsReleaseCombo {
    param(
        [string]$isoPath,
        [Parameter(Mandatory = $true)]
        [psobject]$State
    )

    if (-not $State.Controls.cmbWindowsRelease) { return }

    $oldSelectedItemValue = $null
    if ($null -ne $State.Controls.cmbWindowsRelease.SelectedItem) {
        $oldSelectedItemValue = $State.Controls.cmbWindowsRelease.SelectedItem.Value
    }

    # Get the appropriate list of releases from the helper module
    $availableReleases = Get-AvailableWindowsReleases -IsoPath $isoPath -State $State

    # Update the ComboBox ItemsSource
    $State.Controls.cmbWindowsRelease.ItemsSource = $availableReleases
    $State.Controls.cmbWindowsRelease.DisplayMemberPath = 'Display'
    $State.Controls.cmbWindowsRelease.SelectedValuePath = 'Value'

    # Try to re-select the previously selected item, or default
    $itemToSelect = $availableReleases | Where-Object { $_.Value -eq $oldSelectedItemValue } | Select-Object -First 1
    if ($null -ne $itemToSelect) {
        $State.Controls.cmbWindowsRelease.SelectedItem = $itemToSelect
    }
    elseif ($availableReleases.Count -gt 0) {
        # Default to Windows 11 if available, otherwise the first item
        $defaultItem = $availableReleases | Where-Object { $_.Value -eq 11 } | Select-Object -First 1
        if ($null -eq $defaultItem) {
            $defaultItem = $availableReleases[0]
        }
        $State.Controls.cmbWindowsRelease.SelectedItem = $defaultItem
    }
    else {
        # No items available (should not happen with current logic)
        $State.Controls.cmbWindowsRelease.SelectedIndex = -1
    }
}

# Function to refresh the Windows Version ComboBox based on selected release and ISO path
function Update-WindowsVersionCombo {
    param(
        [int]$selectedRelease,
        [string]$isoPath,
        [Parameter(Mandatory = $true)]
        [psobject]$State
    )

    $combo = $State.Controls.cmbWindowsVersion 
    if (-not $combo) { return } 

    # Get available versions and default from the helper module
    $versionData = Get-AvailableWindowsVersions -SelectedRelease $selectedRelease -IsoPath $isoPath -State $State

    # Update the ComboBox ItemsSource and IsEnabled state
    $combo.ItemsSource = $versionData.Versions
    $combo.IsEnabled = $versionData.IsEnabled

    # Set the selected item
    if ($null -ne $versionData.DefaultVersion -and $versionData.Versions -contains $versionData.DefaultVersion) {
        $combo.SelectedItem = $versionData.DefaultVersion
    }
    elseif ($versionData.Versions.Count -gt 0) {
        $combo.SelectedIndex = 0 
    }
    else {
        $combo.SelectedIndex = -1 # No items available
    }
}

# Function to refresh the Windows SKU ComboBox based on selected release
function Update-WindowsSkuCombo {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$State
    )

    $skuCombo = $State.Controls.cmbWindowsSKU
    if (-not $skuCombo) {
        WriteLog "Update-WindowsSkuCombo: SKU ComboBox not found."
        return
    }

    $releaseCombo = $script:uiState.Controls.cmbWindowsRelease
    if (-not $releaseCombo -or $null -eq $releaseCombo.SelectedItem) {
        WriteLog "Update-WindowsSkuCombo: Windows Release ComboBox not found or no item selected. Cannot update SKUs."
        $skuCombo.ItemsSource = @() # Clear SKUs
        $skuCombo.SelectedIndex = -1
        return
    }

    $selectedReleaseItem = $releaseCombo.SelectedItem
    $selectedReleaseValue = $selectedReleaseItem.Value
    $selectedReleaseDisplayName = $selectedReleaseItem.Display

    $previousSelectedSku = $null
    if ($null -ne $skuCombo.SelectedItem) {
        $previousSelectedSku = $skuCombo.SelectedItem
    }

    WriteLog "Update-WindowsSkuCombo: Updating SKUs for Release Value '$selectedReleaseValue' (Display: '$selectedReleaseDisplayName')."
    # Call Get-AvailableSkusForRelease with both Value and DisplayName
    $availableSkus = Get-AvailableSkusForRelease -SelectedReleaseValue $selectedReleaseValue -SelectedReleaseDisplayName $selectedReleaseDisplayName -State $State

    $skuCombo.ItemsSource = $availableSkus
    WriteLog "Update-WindowsSkuCombo: Set ItemsSource with $($availableSkus.Count) SKUs."

    # Attempt to re-select the previous SKU, or "Pro", or the first available
    if ($null -ne $previousSelectedSku -and $availableSkus -contains $previousSelectedSku) {
        $skuCombo.SelectedItem = $previousSelectedSku
        WriteLog "Update-WindowsSkuCombo: Re-selected previous SKU '$previousSelectedSku'."
    }
    elseif ($availableSkus -contains "Pro") {
        $skuCombo.SelectedItem = "Pro"
        WriteLog "Update-WindowsSkuCombo: Selected default SKU 'Pro'."
    }
    elseif ($availableSkus.Count -gt 0) {
        $skuCombo.SelectedIndex = 0
        WriteLog "Update-WindowsSkuCombo: Selected first available SKU '$($skuCombo.SelectedItem)'."
    }
    else {
        $skuCombo.SelectedIndex = -1 # No SKUs available
        WriteLog "Update-WindowsSkuCombo: No SKUs available for Release '$selectedReleaseValue' (Display: '$selectedReleaseDisplayName')."
    }
}

# Combined function to refresh both Release and Version combos
function Refresh-WindowsSettingsCombos {
    param(
        [string]$isoPath,
        [Parameter(Mandatory = $true)]
        [psobject]$State
    )

    # Update Release combo first
    Update-WindowsReleaseCombo -isoPath $isoPath -State $State

    # Get the newly selected release value
    $selectedReleaseValue = 11 # Default to 11 if selection is null
    if ($null -ne $State.Controls.cmbWindowsRelease.SelectedItem) {
        $selectedReleaseValue = $State.Controls.cmbWindowsRelease.SelectedItem.Value
    }

    # Update Version combo based on the selected release
    Update-WindowsVersionCombo -selectedRelease $selectedReleaseValue -isoPath $isoPath -State $State

    # Update SKU combo based on the selected release (now derives values internally)
    Update-WindowsSkuCombo -State $State
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
function UpdateOptionalFeaturesString {
    param(
        [psobject]$State
    )
    $checkedFeatures = @()
    foreach ($entry in $State.Controls.featureCheckBoxes.GetEnumerator()) {
        if ($entry.Value.IsChecked) { $checkedFeatures += $entry.Key }
    }
    $State.Controls.txtOptionalFeatures.Text = $checkedFeatures -join ";"
}
function BuildFeaturesGrid {
    param (
        [Parameter(Mandatory)]
        [System.Windows.FrameworkElement]$parent,
        [Parameter(Mandatory)]
        [array]$allowedFeatures # Pass the list of features explicitly
    )
    $parent.Children.Clear()
    $script:uiState.Controls.featureCheckBoxes.Clear() # Clear the tracking hashtable

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
        $chk.Add_Checked({ UpdateOptionalFeaturesString -State $script:uiState })
        $chk.Add_Unchecked({ UpdateOptionalFeaturesString -State $script:uiState })

        $script:uiState.Controls.featureCheckBoxes[$featureName] = $chk # Track the checkbox

        [System.Windows.Controls.Grid]::SetRow($chk, $rowIndex)
        [System.Windows.Controls.Grid]::SetColumn($chk, $colIndex)
        $featuresGrid.Children.Add($chk) | Out-Null
    }
    $parent.Children.Add($featuresGrid) | Out-Null
}

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
            $script:uiState.Controls.txtWingetVersion.Text = $wingetText
            $script:uiState.Controls.txtWingetModuleVersion.Text = $moduleText
            # Force immediate UI refresh
            [System.Windows.Forms.Application]::DoEvents()
        })
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
    param(
        [psobject]$State
    )
    $listView = $State.Controls.lstApplications
    $copyButton = $State.Controls.btnCopyBYOApps
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


$window.Add_Loaded({
        # Pass the state object to all initialization functions
        $script:uiState.Window = $window
        Initialize-UIControls -State $script:uiState
        
        # Set ListViewItem style to stretch content horizontally so cell templates fill the cell
        $itemStyleDriverModels = New-Object System.Windows.Style([System.Windows.Controls.ListViewItem])
        $itemStyleDriverModels.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.ListViewItem]::HorizontalContentAlignmentProperty, [System.Windows.HorizontalAlignment]::Stretch)))
        $script:uiState.Controls.lstDriverModels.ItemContainerStyle = $itemStyleDriverModels

        # Driver Models ListView setup
        $driverModelsGridView = New-Object System.Windows.Controls.GridView
        $script:uiState.Controls.lstDriverModels.View = $driverModelsGridView # Assign GridView to ListView first

        # Add the selectable column using the new function
        Add-SelectableGridViewColumn -ListView $script:uiState.Controls.lstDriverModels -HeaderCheckBoxScriptVariableName "chkSelectAllDriverModels" -ColumnWidth 70

        # Add other sortable columns with left-aligned headers
        Add-SortableColumn -gridView $driverModelsGridView -header "Make" -binding "Make" -width 100 -headerHorizontalAlignment Left
        Add-SortableColumn -gridView $driverModelsGridView -header "Model" -binding "Model" -width 200 -headerHorizontalAlignment Left
        Add-SortableColumn -gridView $driverModelsGridView -header "Download Status" -binding "DownloadStatus" -width 150 -headerHorizontalAlignment Left
        $script:uiState.Controls.lstDriverModels.AddHandler(
            [System.Windows.Controls.GridViewColumnHeader]::ClickEvent,
            [System.Windows.RoutedEventHandler] {
                param($eventSource, $e)
                $header = $e.OriginalSource
                if ($header -is [System.Windows.Controls.GridViewColumnHeader] -and $header.Tag) {
                    Invoke-ListViewSort -listView $script:uiState.Controls.lstDriverModels -property $header.Tag -State $script:uiState 
                }
            }
        )
        # Set ListViewItem style to stretch content horizontally so cell templates fill the cell
        $itemStyleWingetResults = New-Object System.Windows.Style([System.Windows.Controls.ListViewItem])
        $itemStyleWingetResults.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.ListViewItem]::HorizontalContentAlignmentProperty, [System.Windows.HorizontalAlignment]::Stretch)))
        $script:uiState.Controls.lstWingetResults.ItemContainerStyle = $itemStyleWingetResults
        
        # Bind ItemsSource to the data list
        $script:uiState.Controls.lstAppsScriptVariables.ItemsSource = $script:uiState.Data.appsScriptVariablesDataList.ToArray()

        # Set ListViewItem style to stretch content horizontally so cell templates fill the cell
        $itemStyleAppsScriptVars = New-Object System.Windows.Style([System.Windows.Controls.ListViewItem])
        $itemStyleAppsScriptVars.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.ListViewItem]::HorizontalContentAlignmentProperty, [System.Windows.HorizontalAlignment]::Stretch)))
        $script:uiState.Controls.lstAppsScriptVariables.ItemContainerStyle = $itemStyleAppsScriptVars

        # The GridView for lstAppsScriptVariables is defined in XAML. We need to get it and add the column.
        if ($script:uiState.Controls.lstAppsScriptVariables.View -is [System.Windows.Controls.GridView]) {
            Add-SelectableGridViewColumn -ListView $script:uiState.Controls.lstAppsScriptVariables -HeaderCheckBoxScriptVariableName "chkSelectAllAppsScriptVariables" -ColumnWidth 60

            # Make Key and Value columns sortable
            $appsScriptVarsGridView = $script:uiState.Controls.lstAppsScriptVariables.View

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
            $script:uiState.Controls.lstAppsScriptVariables.AddHandler(
                [System.Windows.Controls.GridViewColumnHeader]::ClickEvent,
                [System.Windows.RoutedEventHandler] {
                    param($eventSource, $e)
                    $header = $e.OriginalSource
                    if ($header -is [System.Windows.Controls.GridViewColumnHeader] -and $header.Tag) {
                        Invoke-ListViewSort -listView $script:uiState.Controls.lstAppsScriptVariables -property $header.Tag -State $script:uiState 
                    }
                }
            )
        }
        else {
            WriteLog "Warning: lstAppsScriptVariables.View is not a GridView. Selectable column not added, and sorting cannot be enabled."
        }

        # Get Windows Settings defaults and lists from helper module
        $script:uiState.Defaults.windowsSettingsDefaults = Get-WindowsSettingsDefaults
        # Get General defaults from helper module
        $script:uiState.Defaults.generalDefaults = Get-GeneralDefaults -FFUDevelopmentPath $FFUDevelopmentPath

        # Initialize Windows Settings UI using data from helper module
        Refresh-WindowsSettingsCombos -isoPath $script:uiState.Defaults.windowsSettingsDefaults.DefaultISOPath -State $script:uiState # Use combined refresh function
        $script:uiState.Controls.txtISOPath.Add_TextChanged({ Refresh-WindowsSettingsCombos -isoPath $script:uiState.Controls.txtISOPath.Text -State $script:uiState })
        $script:uiState.Controls.cmbWindowsRelease.Add_SelectionChanged({
                $selectedReleaseValue = 11 # Default if null
                if ($null -ne $script:uiState.Controls.cmbWindowsRelease.SelectedItem) {
                    $selectedReleaseValue = $script:uiState.Controls.cmbWindowsRelease.SelectedItem.Value
                }
                # Only need to update the Version combo when Release changes
                Update-WindowsVersionCombo -selectedRelease $selectedReleaseValue -isoPath $script:uiState.Controls.txtISOPath.Text -State $script:uiState
                # Also update the SKU combo (now derives values internally)
                Update-WindowsSkuCombo -State $script:uiState
            })
        $script:uiState.Controls.btnBrowseISO.Add_Click({
                $ofd = New-Object System.Windows.Forms.OpenFileDialog
                $ofd.Filter = "ISO files (*.iso)|*.iso"
                $ofd.Title = "Select Windows ISO File"
                if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $script:uiState.Controls.txtISOPath.Text = $ofd.FileName }
            })

        # Populate static combos from defaults object
        $script:uiState.Controls.cmbWindowsArch.ItemsSource = $script:uiState.Defaults.windowsSettingsDefaults.AllowedArchitectures
        $script:uiState.Controls.cmbWindowsArch.SelectedItem = $script:uiState.Defaults.windowsSettingsDefaults.DefaultWindowsArch

        $script:uiState.Controls.cmbWindowsLang.ItemsSource = $script:uiState.Defaults.windowsSettingsDefaults.AllowedLanguages
        $script:uiState.Controls.cmbWindowsLang.SelectedItem = $script:uiState.Defaults.windowsSettingsDefaults.DefaultWindowsLang

        # $script:uiState.Controls.cmbWindowsSKU.ItemsSource is now populated by Update-WindowsSkuCombo
        $script:uiState.Controls.cmbWindowsSKU.SelectedItem = $script:uiState.Defaults.windowsSettingsDefaults.DefaultWindowsSKU # Attempt to set default

        $script:uiState.Controls.cmbMediaType.ItemsSource = $script:uiState.Defaults.windowsSettingsDefaults.AllowedMediaTypes
        $script:uiState.Controls.cmbMediaType.SelectedItem = $script:uiState.Defaults.windowsSettingsDefaults.DefaultMediaType

        # Set default text values for Windows Settings
        $script:uiState.Controls.txtOptionalFeatures.Text = $script:uiState.Defaults.windowsSettingsDefaults.DefaultOptionalFeatures
        $window.FindName('txtProductKey').Text = $script:uiState.Defaults.windowsSettingsDefaults.DefaultProductKey

        # Build tab defaults from General Defaults
        $window.FindName('txtFFUDevPath').Text = $FFUDevelopmentPath # Keep this as it's the base path
        $window.FindName('txtCustomFFUNameTemplate').Text = $script:uiState.Defaults.generalDefaults.CustomFFUNameTemplate
        $window.FindName('txtFFUCaptureLocation').Text = $script:uiState.Defaults.generalDefaults.FFUCaptureLocation
        $window.FindName('txtShareName').Text = $script:uiState.Defaults.generalDefaults.ShareName
        $window.FindName('txtUsername').Text = $script:uiState.Defaults.generalDefaults.Username
        $window.FindName('chkBuildUSBDriveEnable').IsChecked = $script:uiState.Defaults.generalDefaults.BuildUSBDriveEnable
        $window.FindName('chkCompactOS').IsChecked = $script:uiState.Defaults.generalDefaults.CompactOS
        $script:uiState.Controls.chkUpdateADK.IsChecked = $script:uiState.Defaults.generalDefaults.UpdateADK # Set default for chkUpdateADK
        $window.FindName('chkOptimize').IsChecked = $script:uiState.Defaults.generalDefaults.Optimize
        $window.FindName('chkAllowVHDXCaching').IsChecked = $script:uiState.Defaults.generalDefaults.AllowVHDXCaching
        $window.FindName('chkCreateCaptureMedia').IsChecked = $script:uiState.Defaults.generalDefaults.CreateCaptureMedia
        $window.FindName('chkCreateDeploymentMedia').IsChecked = $script:uiState.Defaults.generalDefaults.CreateDeploymentMedia
        $window.FindName('chkAllowExternalHardDiskMedia').IsChecked = $script:uiState.Defaults.generalDefaults.AllowExternalHardDiskMedia
        $window.FindName('chkPromptExternalHardDiskMedia').IsChecked = $script:uiState.Defaults.generalDefaults.PromptExternalHardDiskMedia
        $window.FindName('chkSelectSpecificUSBDrives').IsChecked = $script:uiState.Defaults.generalDefaults.SelectSpecificUSBDrives
        $window.FindName('chkCopyAutopilot').IsChecked = $script:uiState.Defaults.generalDefaults.CopyAutopilot
        $window.FindName('chkCopyUnattend').IsChecked = $script:uiState.Defaults.generalDefaults.CopyUnattend
        $window.FindName('chkCopyPPKG').IsChecked = $script:uiState.Defaults.generalDefaults.CopyPPKG
        $window.FindName('chkCleanupAppsISO').IsChecked = $script:uiState.Defaults.generalDefaults.CleanupAppsISO
        $window.FindName('chkCleanupCaptureISO').IsChecked = $script:uiState.Defaults.generalDefaults.CleanupCaptureISO
        $window.FindName('chkCleanupDeployISO').IsChecked = $script:uiState.Defaults.generalDefaults.CleanupDeployISO
        $window.FindName('chkCleanupDrivers').IsChecked = $script:uiState.Defaults.generalDefaults.CleanupDrivers
        $window.FindName('chkRemoveFFU').IsChecked = $script:uiState.Defaults.generalDefaults.RemoveFFU
        $script:uiState.Controls.chkRemoveApps.IsChecked = $script:uiState.Defaults.generalDefaults.RemoveApps
        $script:uiState.Controls.chkRemoveUpdates.IsChecked = $script:uiState.Defaults.generalDefaults.RemoveUpdates

        # Hyper-V Settings defaults from General Defaults
        $window.FindName('txtDiskSize').Text = $script:uiState.Defaults.generalDefaults.DiskSizeGB
        $window.FindName('txtMemory').Text = $script:uiState.Defaults.generalDefaults.MemoryGB
        $window.FindName('txtProcessors').Text = $script:uiState.Defaults.generalDefaults.Processors
        $window.FindName('txtVMLocation').Text = $script:uiState.Defaults.generalDefaults.VMLocation
        $window.FindName('txtVMNamePrefix').Text = $script:uiState.Defaults.generalDefaults.VMNamePrefix
        $window.FindName('cmbLogicalSectorSize').SelectedItem = ($window.FindName('cmbLogicalSectorSize').Items | Where-Object { $_.Content -eq $script:uiState.Defaults.generalDefaults.LogicalSectorSize.ToString() })

        # Hyper-V Settings: Populate VM Switch ComboBox (Keep existing logic)
        $vmSwitchData = Get-VMSwitchData
        $script:uiState.Data.vmSwitchMap = $vmSwitchData.SwitchMap
        $script:uiState.Controls.cmbVMSwitchName.Items.Clear()
        foreach ($switchName in $vmSwitchData.SwitchNames) {
            $script:uiState.Controls.cmbVMSwitchName.Items.Add($switchName) | Out-Null
        }
        $script:uiState.Controls.cmbVMSwitchName.Items.Add('Other') | Out-Null
        if ($script:uiState.Controls.cmbVMSwitchName.Items.Count -gt 1) {
            $script:uiState.Controls.cmbVMSwitchName.SelectedIndex = 0
            $firstSwitch = $script:uiState.Controls.cmbVMSwitchName.SelectedItem
            if ($script:uiState.Data.vmSwitchMap.ContainsKey($firstSwitch)) {
                $script:uiState.Controls.txtVMHostIPAddress.Text = $script:uiState.Data.vmSwitchMap[$firstSwitch]
            }
            else {
                $script:uiState.Controls.txtVMHostIPAddress.Text = $script:uiState.Defaults.generalDefaults.VMHostIPAddress # Use default if IP not found
            }
            $script:uiState.Controls.txtCustomVMSwitchName.Visibility = 'Collapsed'
        }
        else {
            $script:uiState.Controls.cmbVMSwitchName.SelectedItem = 'Other'
            $script:uiState.Controls.txtCustomVMSwitchName.Visibility = 'Visible'
            $script:uiState.Controls.txtVMHostIPAddress.Text = $script:uiState.Defaults.generalDefaults.VMHostIPAddress # Use default
        }
        $script:uiState.Controls.cmbVMSwitchName.Add_SelectionChanged({
                param($eventSource, $selectionChangedEventArgs)
                $selectedItem = $eventSource.SelectedItem
                if ($selectedItem -eq 'Other') {
                    $script:uiState.Controls.txtCustomVMSwitchName.Visibility = 'Visible'
                    $script:uiState.Controls.txtVMHostIPAddress.Text = '' # Clear IP for custom
                }
                else {
                    $script:uiState.Controls.txtCustomVMSwitchName.Visibility = 'Collapsed'
                    if ($script:uiState.Data.vmSwitchMap.ContainsKey($selectedItem)) {
                        $script:uiState.Controls.txtVMHostIPAddress.Text = $script:uiState.Data.vmSwitchMap[$selectedItem]
                    }
                    else {
                        $script:uiState.Controls.txtVMHostIPAddress.Text = '' # Clear IP if not found in map
                    }
                }
            })

        # Updates tab defaults from General Defaults
        $window.FindName('chkUpdateLatestCU').IsChecked = $script:uiState.Defaults.generalDefaults.UpdateLatestCU
        $window.FindName('chkUpdateLatestNet').IsChecked = $script:uiState.Defaults.generalDefaults.UpdateLatestNet
        $window.FindName('chkUpdateLatestDefender').IsChecked = $script:uiState.Defaults.generalDefaults.UpdateLatestDefender
        $window.FindName('chkUpdateEdge').IsChecked = $script:uiState.Defaults.generalDefaults.UpdateEdge
        $window.FindName('chkUpdateOneDrive').IsChecked = $script:uiState.Defaults.generalDefaults.UpdateOneDrive
        $window.FindName('chkUpdateLatestMSRT').IsChecked = $script:uiState.Defaults.generalDefaults.UpdateLatestMSRT
        $script:uiState.Controls.chkUpdateLatestMicrocode.IsChecked = $script:uiState.Defaults.generalDefaults.UpdateLatestMicrocode # Added for UpdateLatestMicrocode
        $window.FindName('chkUpdatePreviewCU').IsChecked = $script:uiState.Defaults.generalDefaults.UpdatePreviewCU

        # Applications tab defaults from General Defaults
        $window.FindName('chkInstallApps').IsChecked = $script:uiState.Defaults.generalDefaults.InstallApps
        $window.FindName('txtApplicationPath').Text = $script:uiState.Defaults.generalDefaults.ApplicationPath
        $window.FindName('txtAppListJsonPath').Text = $script:uiState.Defaults.generalDefaults.AppListJsonPath
        $window.FindName('chkInstallWingetApps').IsChecked = $script:uiState.Defaults.generalDefaults.InstallWingetApps
        $window.FindName('chkBringYourOwnApps').IsChecked = $script:uiState.Defaults.generalDefaults.BringYourOwnApps

        # M365 Apps/Office tab defaults from General Defaults
        $window.FindName('chkInstallOffice').IsChecked = $script:uiState.Defaults.generalDefaults.InstallOffice
        $window.FindName('txtOfficePath').Text = $script:uiState.Defaults.generalDefaults.OfficePath
        $window.FindName('chkCopyOfficeConfigXML').IsChecked = $script:uiState.Defaults.generalDefaults.CopyOfficeConfigXML
        $window.FindName('txtOfficeConfigXMLFilePath').Text = $script:uiState.Defaults.generalDefaults.OfficeConfigXMLFilePath

        # Drivers tab defaults from General Defaults
        $window.FindName('txtDriversFolder').Text = $script:uiState.Defaults.generalDefaults.DriversFolder
        $window.FindName('txtPEDriversFolder').Text = $script:uiState.Defaults.generalDefaults.PEDriversFolder
        $script:uiState.Controls.txtDriversJsonPath.Text = $script:uiState.Defaults.generalDefaults.DriversJsonPath # Set default text
        $window.FindName('chkDownloadDrivers').IsChecked = $script:uiState.Defaults.generalDefaults.DownloadDrivers
        $window.FindName('chkInstallDrivers').IsChecked = $script:uiState.Defaults.generalDefaults.InstallDrivers
        $window.FindName('chkCopyDrivers').IsChecked = $script:uiState.Defaults.generalDefaults.CopyDrivers
        $window.FindName('chkCopyPEDrivers').IsChecked = $script:uiState.Defaults.generalDefaults.CopyPEDrivers

        # Drivers tab UI logic (Keep existing logic)
        $makeList = @('Microsoft', 'Dell', 'HP', 'Lenovo') # Added Lenovo
        foreach ($m in $makeList) { [void]$script:uiState.Controls.cmbMake.Items.Add($m) }
        if ($script:uiState.Controls.cmbMake.Items.Count -gt 0) { $script:uiState.Controls.cmbMake.SelectedIndex = 0 }
        $script:uiState.Controls.chkDownloadDrivers.Add_Checked({
                $script:uiState.Controls.cmbMake.Visibility = 'Visible'
                $script:uiState.Controls.btnGetModels.Visibility = 'Visible'
                $script:uiState.Controls.spMakeSection.Visibility = 'Visible'
                # Make the model filter, list, and action buttons visible immediately
                # This allows users to import a Drivers.json without first clicking "Get Models"
                $script:uiState.Controls.spModelFilterSection.Visibility = 'Visible'
                $script:uiState.Controls.lstDriverModels.Visibility = 'Visible'
                $script:uiState.Controls.spDriverActionButtons.Visibility = 'Visible'
            })
        $script:uiState.Controls.chkDownloadDrivers.Add_Unchecked({
                $script:uiState.Controls.cmbMake.Visibility = 'Collapsed'
                $script:uiState.Controls.btnGetModels.Visibility = 'Collapsed'
                $script:uiState.Controls.spMakeSection.Visibility = 'Collapsed'
                $script:uiState.Controls.spModelFilterSection.Visibility = 'Collapsed'
                $script:uiState.Controls.lstDriverModels.Visibility = 'Collapsed'
                $script:uiState.Controls.spDriverActionButtons.Visibility = 'Collapsed'
                $script:uiState.Controls.lstDriverModels.ItemsSource = $null
                $script:uiState.Data.allDriverModels = @()
                $script:uiState.Controls.txtModelFilter.Text = ""
            })
        $script:uiState.Controls.spMakeSection.Visibility = if ($script:uiState.Controls.chkDownloadDrivers.IsChecked) { 'Visible' } else { 'Collapsed' }
        $script:uiState.Controls.btnGetModels.Visibility = if ($script:uiState.Controls.chkDownloadDrivers.IsChecked) { 'Visible' } else { 'Collapsed' }
        $script:uiState.Controls.spModelFilterSection.Visibility = 'Collapsed'
        $script:uiState.Controls.lstDriverModels.Visibility = 'Collapsed'
        $script:uiState.Controls.spDriverActionButtons.Visibility = 'Collapsed'
        $script:uiState.Controls.btnGetModels.Add_Click({
                $selectedMake = $script:uiState.Controls.cmbMake.SelectedItem
                $script:uiState.Controls.txtStatus.Text = "Getting models for $selectedMake..."
                $window.Cursor = [System.Windows.Input.Cursors]::Wait
                $this.IsEnabled = $false # Disable the button

                try {
                    # Get previously selected models from the master list ($script:uiState.Data.allDriverModels)
                    # This ensures all selected items are captured, regardless of any active filter.
                    $previouslySelectedModels = @($script:uiState.Data.allDriverModels | Where-Object { $_.IsSelected })

                    # Get newly fetched models for the current make (already standardized)
                    $newlyFetchedStandardizedModels = Get-ModelsForMake -SelectedMake $selectedMake -State $script:uiState

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

                    $script:uiState.Data.allDriverModels = $combinedModelsList.ToArray() | Sort-Object @{Expression = { $_.IsSelected }; Descending = $true }, Make, Model # Sort by selection status, then Make, then Model
                    $script:uiState.Controls.lstDriverModels.ItemsSource = $script:uiState.Data.allDriverModels
                    $script:uiState.Controls.txtModelFilter.Text = "" # Clear any existing filter

                    if ($script:uiState.Data.allDriverModels.Count -gt 0) {
                        $script:uiState.Controls.spModelFilterSection.Visibility = 'Visible'
                        $script:uiState.Controls.lstDriverModels.Visibility = 'Visible'
                        $script:uiState.Controls.spDriverActionButtons.Visibility = 'Visible'
                        $statusText = "Displaying $($script:uiState.Data.allDriverModels.Count) models."
                        if ($newlyFetchedStandardizedModels.Count -gt 0 -and $addedNewCount -eq 0 -and $previouslySelectedModels.Count -gt 0) {
                            # This case means new models were fetched, but all were already present in the selected list.
                            $statusText = "Fetched $($newlyFetchedStandardizedModels.Count) models for $selectedMake; all were already in the selected list. Displaying $($script:uiState.Data.allDriverModels.Count) total selected models."
                        }
                        elseif ($addedNewCount -gt 0) {
                            $statusText = "Added $addedNewCount new models for $selectedMake. Displaying $($script:uiState.Data.allDriverModels.Count) total models."
                        }
                        elseif ($newlyFetchedStandardizedModels.Count -eq 0 -and $selectedMake -eq 'Lenovo' ) {
                            # Handled Lenovo specific no new models found message inside Get-ModelsForMake or if user cancelled prompt
                            $statusText = if ($previouslySelectedModels.Count -gt 0) { "No new models found for $selectedMake. Displaying $($previouslySelectedModels.Count) previously selected models." } else { "No models found for $selectedMake." }
                        }
                        elseif ($newlyFetchedStandardizedModels.Count -eq 0) {
                            $statusText = "No new models found for $selectedMake. Displaying $($script:uiState.Data.allDriverModels.Count) previously selected models."
                        }
                        $script:uiState.Controls.txtStatus.Text = $statusText
                    }
                    else {
                        $script:uiState.Controls.spModelFilterSection.Visibility = 'Collapsed'
                        $script:uiState.Controls.lstDriverModels.Visibility = 'Collapsed'
                        $script:uiState.Controls.spDriverActionButtons.Visibility = 'Collapsed'
                        $script:uiState.Controls.txtStatus.Text = "No models to display for $selectedMake."
                    }
                } # End Try
                catch {
                    $script:uiState.Controls.txtStatus.Text = "Error getting models: $($_.Exception.Message)"
                    [System.Windows.MessageBox]::Show("Error getting models: $($_.Exception.Message)", "Error", "OK", "Error")
                    # Minimal UI reset on error, keep previously selected if any
                    if ($null -eq $script:uiState.Data.allDriverModels -or $script:uiState.Data.allDriverModels.Count -eq 0) {
                        $script:uiState.Controls.spModelFilterSection.Visibility = 'Collapsed'
                        $script:uiState.Controls.lstDriverModels.Visibility = 'Collapsed'
                        $script:uiState.Controls.spDriverActionButtons.Visibility = 'Collapsed'
                        $script:uiState.Controls.lstDriverModels.ItemsSource = $null
                        $script:uiState.Controls.txtModelFilter.Text = ""
                    }
                } # End Catch
                finally {
                    $window.Cursor = $null
                    $this.IsEnabled = $true # Re-enable the button
                } # End Finally
            })
        $script:uiState.Controls.txtModelFilter.Add_TextChanged({
                param($sourceObject, $textChangedEventArgs)
                Filter-DriverModels -filterText $script:uiState.Controls.txtModelFilter.Text -State $script:uiState
            })
        $script:uiState.Controls.btnDownloadSelectedDrivers.Add_Click({
                param($buttonSender, $clickEventArgs)

                $selectedDrivers = @($script:uiState.Controls.lstDriverModels.Items | Where-Object { $_.IsSelected })
                if (-not $selectedDrivers) {
                    [System.Windows.MessageBox]::Show("No drivers selected to download.", "Download Drivers", "OK", "Information")
                    return
                }

                $buttonSender.IsEnabled = $false
                $script:uiState.Controls.pbOverallProgress.Visibility = 'Visible'
                $script:uiState.Controls.pbOverallProgress.Value = 0
                $script:uiState.Controls.txtStatus.Text = "Preparing driver downloads..."

                # Define common necessary task-specific variables locally
                # Ensure required selections are made
                if ($null -eq $script:uiState.Controls.cmbWindowsRelease.SelectedItem) {
                    [System.Windows.MessageBox]::Show("Please select a Windows Release.", "Missing Information", "OK", "Warning")
                    $buttonSender.IsEnabled = $true
                    $script:uiState.Controls.pbOverallProgress.Visibility = 'Collapsed'
                    $script:uiState.Controls.txtStatus.Text = "Driver download cancelled."
                    return
                }
                if ($null -eq $script:uiState.Controls.cmbWindowsArch.SelectedItem) {
                    [System.Windows.MessageBox]::Show("Please select a Windows Architecture.", "Missing Information", "OK", "Warning")
                    $buttonSender.IsEnabled = $true
                    $script:uiState.Controls.pbOverallProgress.Visibility = 'Collapsed'
                    $script:uiState.Controls.txtStatus.Text = "Driver download cancelled."
                    return
                }
                if (($selectedDrivers | Where-Object { $_.Make -eq 'HP' }) -and $null -ne $script:uiState.Controls.cmbWindowsVersion -and $null -eq $script:uiState.Controls.cmbWindowsVersion.SelectedItem) {
                    [System.Windows.MessageBox]::Show("HP drivers are selected. Please select a Windows Version.", "Missing Information", "OK", "Warning")
                    $buttonSender.IsEnabled = $true
                    $script:uiState.Controls.pbOverallProgress.Visibility = 'Collapsed'
                    $script:uiState.Controls.txtStatus.Text = "Driver download cancelled."
                    return
                }

                $localDriversFolder = $script:uiState.Controls.txtDriversFolder.Text
                $localWindowsRelease = $script:uiState.Controls.cmbWindowsRelease.SelectedItem.Value
                $localWindowsArch = $script:uiState.Controls.cmbWindowsArch.SelectedItem
                $localWindowsVersion = if ($null -ne $script:uiState.Controls.cmbWindowsVersion -and $null -ne $script:uiState.Controls.cmbWindowsVersion.SelectedItem) { $script:uiState.Controls.cmbWindowsVersion.SelectedItem } else { $null }
                $coreStaticVars = Get-CoreStaticVariables
                $localHeaders = $coreStaticVars.Headers
                $localUserAgent = $coreStaticVars.UserAgent
                $compressDrivers = $script:uiState.Controls.chkCompressDriversToWIM.IsChecked

                # --- Dell Catalog Handling (once, if Dell drivers are selected) ---
                $dellCatalogXmlPath = $null # This will be the path passed to the background task
                if ($selectedDrivers | Where-Object { $_.Make -eq 'Dell' }) {
                    $script:uiState.Controls.txtStatus.Text = "Checking Dell Catalog..."
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
                            $script:uiState.Controls.txtStatus.Text = "Dell Catalog ready."
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
                        $script:uiState.Controls.txtStatus.Text = "Downloading Dell Catalog..."
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
                            $script:uiState.Controls.txtStatus.Text = "Dell Catalog ready."
                        }
                        catch {
                            $errMsg = "Failed to download/extract Dell Catalog for driver download task: $($_.Exception.Message)"
                            WriteLog $errMsg; [System.Windows.MessageBox]::Show($errMsg, "Dell Catalog Error", "OK", "Error")
                            $dellCatalogXmlPath = $null # Ensure it's null if failed, Save-DellDriversTask will handle this
                            $script:uiState.Controls.txtStatus.Text = "Dell Catalog download failed. Dell drivers may not download."
                        }
                    }
                    # If $downloadDellCatalog was false, $dellCatalogXmlPath is already set to the existing valid XML.
                }
                # --- End Dell Catalog Handling ---

                $script:uiState.Controls.txtStatus.Text = "Processing all selected drivers..."
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
                    -ListViewControl $script:uiState.Controls.lstDriverModels `
                    -IdentifierProperty 'Model' `
                    -StatusProperty 'DownloadStatus' `
                    -TaskType 'DownloadDriverByMake' `
                    -TaskArguments $taskArguments `
                    -CompletedStatusText 'Completed' `
                    -ErrorStatusPrefix 'Error: ' `
                    -WindowObject $window `
                    -MainThreadLogPath $script:uiState.LogFilePath

                $overallSuccess = $true
                # Check if any item has an error status after processing
                # We iterate over $script:lstDriverModels.Items because their DownloadStatus property was updated by Invoke-ParallelProcessing
                foreach ($item in ($script:uiState.Controls.lstDriverModels.Items | Where-Object { $_.IsSelected })) {
                    # Check only originally selected items
                    if ($item.DownloadStatus -like 'Error:*') {
                        $overallSuccess = $false
                        WriteLog "Error detected for model $($item.Model) (Make: $($item.Make)): $($item.DownloadStatus)"
                        # No break here, log all errors
                    }
                }

                $script:uiState.Controls.pbOverallProgress.Visibility = 'Collapsed'
                $buttonSender.IsEnabled = $true
                if ($overallSuccess) {
                    $script:uiState.Controls.txtStatus.Text = "All selected driver downloads processed."
                    [System.Windows.MessageBox]::Show("All selected driver downloads processed. Check status column for details.", "Download Process Finished", "OK", "Information")
                }
                else {
                    $script:uiState.Controls.txtStatus.Text = "Driver downloads processed with some errors. Check status column and log."
                    [System.Windows.MessageBox]::Show("Driver downloads processed, but some errors occurred. Please check the status column for each driver and the log file for details.", "Download Process Finished with Errors", "OK", "Warning")
                }
            })
        $script:uiState.Controls.btnClearDriverList.Add_Click({
                $script:uiState.Controls.lstDriverModels.ItemsSource = $null
                $script:uiState.Data.allDriverModels = @()
                $script:uiState.Controls.txtModelFilter.Text = ""
                $script:uiState.Controls.txtStatus.Text = "Driver list cleared."
            })
        $script:uiState.Controls.btnSaveDriversJson.Add_Click({ Save-DriversJson -State $script:uiState })
        $script:uiState.Controls.btnImportDriversJson.Add_Click({ Import-DriversJson -State $script:uiState })

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
        $script:uiState.Controls.chkInstallOffice.Add_Checked({
                if (-not $script:uiState.Controls.chkInstallApps.IsChecked) {
                    $script:uiState.Controls.chkInstallApps.IsChecked = $true
                    $script:uiState.Flags.installAppsCheckedByOffice = $true
                }
                $script:uiState.Controls.chkInstallApps.IsEnabled = $false
                $script:uiState.Controls.OfficePathStackPanel.Visibility = 'Visible'
                $script:uiState.Controls.OfficePathGrid.Visibility = 'Visible'
                $script:uiState.Controls.CopyOfficeConfigXMLStackPanel.Visibility = 'Visible'
                # Show/hide XML file path based on checkbox state
                $script:uiState.Controls.OfficeConfigurationXMLFileStackPanel.Visibility = if ($script:uiState.Controls.chkCopyOfficeConfigXML.IsChecked) { 'Visible' } else { 'Collapsed' }
                $script:uiState.Controls.OfficeConfigurationXMLFileGrid.Visibility = if ($script:uiState.Controls.chkCopyOfficeConfigXML.IsChecked) { 'Visible' } else { 'Collapsed' }
            })
        $script:uiState.Controls.chkInstallOffice.Add_Unchecked({
                if ($script:uiState.Flags.installAppsCheckedByOffice) {
                    $script:uiState.Controls.chkInstallApps.IsChecked = $false
                    $script:uiState.Flags.installAppsCheckedByOffice = $false
                }
                # Only re-enable InstallApps if not forced by Updates
                if (-not $script:uiState.Flags.installAppsForcedByUpdates) {
                    $script:uiState.Controls.chkInstallApps.IsEnabled = $true
                }
                $script:uiState.Controls.OfficePathStackPanel.Visibility = 'Collapsed'
                $script:uiState.Controls.OfficePathGrid.Visibility = 'Collapsed'
                $script:uiState.Controls.CopyOfficeConfigXMLStackPanel.Visibility = 'Collapsed'
                $script:uiState.Controls.OfficeConfigurationXMLFileStackPanel.Visibility = 'Collapsed'
                $script:uiState.Controls.OfficeConfigurationXMLFileGrid.Visibility = 'Collapsed'
            })
        $script:uiState.Controls.chkCopyOfficeConfigXML.Add_Checked({
                $script:uiState.Controls.OfficeConfigurationXMLFileStackPanel.Visibility = 'Visible'
                $script:uiState.Controls.OfficeConfigurationXMLFileGrid.Visibility = 'Visible'
            })
        $script:uiState.Controls.chkCopyOfficeConfigXML.Add_Unchecked({
                $script:uiState.Controls.OfficeConfigurationXMLFileStackPanel.Visibility = 'Collapsed'
                $script:uiState.Controls.OfficeConfigurationXMLFileGrid.Visibility = 'Collapsed'
            })

        # Build dynamic multi-column checkboxes for optional features (Keep existing logic)
        if ($script:uiState.Controls.featuresPanel) { BuildFeaturesGrid -parent $script:uiState.Controls.featuresPanel -allowedFeatures $script:uiState.Defaults.windowsSettingsDefaults.AllowedFeatures }

        # Updates/InstallApps interplay (Keep existing logic)
        $script:uiState.Flags.installAppsForcedByUpdates = $false
        $script:uiState.Flags.prevInstallAppsStateBeforeUpdates = $null
        # Define the scriptblock within the Loaded event and assign it to the state object
        $script:uiState.Controls.UpdateInstallAppsBasedOnUpdates = {
            param($State) # Pass state object to avoid using $script: scope inside
            $anyUpdateChecked = $State.Controls.chkUpdateLatestDefender.IsChecked -or $State.Controls.chkUpdateEdge.IsChecked -or $State.Controls.chkUpdateOneDrive.IsChecked -or $State.Controls.chkUpdateLatestMSRT.IsChecked
            if ($anyUpdateChecked) {
                if (-not $State.Flags.installAppsForcedByUpdates) {
                    $State.Flags.prevInstallAppsStateBeforeUpdates = $State.Controls.chkInstallApps.IsChecked
                    $State.Flags.installAppsForcedByUpdates = $true
                }
                $State.Controls.chkInstallApps.IsChecked = $true
                $State.Controls.chkInstallApps.IsEnabled = $false
            }
            else {
                if ($State.Flags.installAppsForcedByUpdates) {
                    $State.Controls.chkInstallApps.IsChecked = $State.Flags.prevInstallAppsStateBeforeUpdates
                    $State.Flags.installAppsForcedByUpdates = $false
                    $State.Flags.prevInstallAppsStateBeforeUpdates = $null
                }
                # Only re-enable InstallApps if not forced by Office
                if (-not $State.Controls.chkInstallOffice.IsChecked) {
                    $State.Controls.chkInstallApps.IsEnabled = $true
                }
            }
        }
        $script:uiState.Controls.chkUpdateLatestDefender.Add_Checked({ & $script:uiState.Controls.UpdateInstallAppsBasedOnUpdates -State $script:uiState })
        $script:uiState.Controls.chkUpdateLatestDefender.Add_Unchecked({ & $script:uiState.Controls.UpdateInstallAppsBasedOnUpdates -State $script:uiState })
        $script:uiState.Controls.chkUpdateEdge.Add_Checked({ & $script:uiState.Controls.UpdateInstallAppsBasedOnUpdates -State $script:uiState })
        $script:uiState.Controls.chkUpdateEdge.Add_Unchecked({ & $script:uiState.Controls.UpdateInstallAppsBasedOnUpdates -State $script:uiState })
        $script:uiState.Controls.chkUpdateOneDrive.Add_Checked({ & $script:uiState.Controls.UpdateInstallAppsBasedOnUpdates -State $script:uiState })
        $script:uiState.Controls.chkUpdateOneDrive.Add_Unchecked({ & $script:uiState.Controls.UpdateInstallAppsBasedOnUpdates -State $script:uiState })
        $script:uiState.Controls.chkUpdateLatestMSRT.Add_Checked({ & $script:uiState.Controls.UpdateInstallAppsBasedOnUpdates -State $script:uiState })
        $script:uiState.Controls.chkUpdateLatestMSRT.Add_Unchecked({ & $script:uiState.Controls.UpdateInstallAppsBasedOnUpdates -State $script:uiState })
        # Initial check for Updates/InstallApps state
        & $script:uiState.Controls.UpdateInstallAppsBasedOnUpdates -State $script:uiState

        # CU interplay (Keep existing logic)
        $script:uiState.Controls.chkLatestCU.Add_Checked({ $script:uiState.Controls.chkPreviewCU.IsEnabled = $false })
        $script:uiState.Controls.chkLatestCU.Add_Unchecked({ $script:uiState.Controls.chkPreviewCU.IsEnabled = $true })
        $script:uiState.Controls.chkPreviewCU.Add_Checked({ $script:uiState.Controls.chkLatestCU.IsEnabled = $false })
        $script:uiState.Controls.chkPreviewCU.Add_Unchecked({ $script:uiState.Controls.chkLatestCU.IsEnabled = $true })
        # Set initial state based on defaults
        $script:uiState.Controls.chkPreviewCU.IsEnabled = -not $script:uiState.Controls.chkLatestCU.IsChecked
        $script:uiState.Controls.chkLatestCU.IsEnabled = -not $script:uiState.Controls.chkPreviewCU.IsChecked

        # USB Drive Detection/Selection logic (Keep existing logic)
        $script:uiState.Controls.btnCheckUSBDrives.Add_Click({
                $script:uiState.Controls.lstUSBDrives.Items.Clear()
                $usbDrives = Get-USBDrives
                foreach ($drive in $usbDrives) {
                    $script:uiState.Controls.lstUSBDrives.Items.Add([PSCustomObject]$drive)
                }
                if ($script:uiState.Controls.lstUSBDrives.Items.Count -gt 0) {
                    $script:uiState.Controls.lstUSBDrives.SelectedIndex = 0
                }
            })
        $script:uiState.Controls.chkSelectAllUSBDrives.Add_Checked({
                foreach ($item in $script:uiState.Controls.lstUSBDrives.Items) { $item.IsSelected = $true }
                $script:uiState.Controls.lstUSBDrives.Items.Refresh()
            })
        $script:uiState.Controls.chkSelectAllUSBDrives.Add_Unchecked({
                foreach ($item in $script:uiState.Controls.lstUSBDrives.Items) { $item.IsSelected = $false }
                $script:uiState.Controls.lstUSBDrives.Items.Refresh()
            })
        $script:uiState.Controls.lstUSBDrives.Add_KeyDown({
                param($eventSource, $keyEvent)
                if ($keyEvent.Key -eq 'Space') {
                    $selectedItem = $script:uiState.Controls.lstUSBDrives.SelectedItem
                    if ($selectedItem) {
                        $selectedItem.IsSelected = !$selectedItem.IsSelected
                        $script:uiState.Controls.lstUSBDrives.Items.Refresh()
                        $allSelected = -not ($script:uiState.Controls.lstUSBDrives.Items | Where-Object { -not $_.IsSelected })
                        $script:uiState.Controls.chkSelectAllUSBDrives.IsChecked = $allSelected
                    }
                }
            })
        $script:uiState.Controls.lstUSBDrives.Add_SelectionChanged({
                param($eventSource, $selChangeEvent)
                $allSelected = -not ($script:uiState.Controls.lstUSBDrives.Items | Where-Object { -not $_.IsSelected })
                $script:uiState.Controls.chkSelectAllUSBDrives.IsChecked = $allSelected
            })
        $script:uiState.Controls.usbSection.Visibility = if ($script:uiState.Controls.chkBuildUSBDriveEnable.IsChecked) { 'Visible' } else { 'Collapsed' }
        $script:uiState.Controls.usbSelectionPanel.Visibility = if ($script:uiState.Controls.chkSelectSpecificUSBDrives.IsChecked) { 'Visible' } else { 'Collapsed' }
        $script:uiState.Controls.chkBuildUSBDriveEnable.Add_Checked({
                $script:uiState.Controls.usbSection.Visibility = 'Visible'
                $script:uiState.Controls.chkSelectSpecificUSBDrives.IsEnabled = $true
            })
        $script:uiState.Controls.chkBuildUSBDriveEnable.Add_Unchecked({
                $script:uiState.Controls.usbSection.Visibility = 'Collapsed'
                $script:uiState.Controls.chkSelectSpecificUSBDrives.IsEnabled = $false
                $script:uiState.Controls.chkSelectSpecificUSBDrives.IsChecked = $false
                $script:uiState.Controls.lstUSBDrives.Items.Clear()
                $script:uiState.Controls.chkSelectAllUSBDrives.IsChecked = $false
            })
        $script:uiState.Controls.chkSelectSpecificUSBDrives.Add_Checked({ $script:uiState.Controls.usbSelectionPanel.Visibility = 'Visible' })
        $script:uiState.Controls.chkSelectSpecificUSBDrives.Add_Unchecked({
                $script:uiState.Controls.usbSelectionPanel.Visibility = 'Collapsed'
                $script:uiState.Controls.lstUSBDrives.Items.Clear()
                $script:uiState.Controls.chkSelectAllUSBDrives.IsChecked = $false
            })
        $script:uiState.Controls.chkSelectSpecificUSBDrives.IsEnabled = $script:uiState.Controls.chkBuildUSBDriveEnable.IsChecked
        $script:uiState.Controls.chkAllowExternalHardDiskMedia.Add_Checked({ $script:uiState.Controls.chkPromptExternalHardDiskMedia.IsEnabled = $true })
        $script:uiState.Controls.chkAllowExternalHardDiskMedia.Add_Unchecked({
                $script:uiState.Controls.chkPromptExternalHardDiskMedia.IsEnabled = $false
                $script:uiState.Controls.chkPromptExternalHardDiskMedia.IsChecked = $false
            })
        # Set initial state based on defaults
        $script:uiState.Controls.chkPromptExternalHardDiskMedia.IsEnabled = $script:uiState.Controls.chkAllowExternalHardDiskMedia.IsChecked

        # APPLICATIONS tab UI logic (Keep existing logic)
        $script:uiState.Controls.chkInstallWingetApps.Visibility = if ($script:uiState.Controls.chkInstallApps.IsChecked) { 'Visible' } else { 'Collapsed' }
        $script:uiState.Controls.applicationPathPanel.Visibility = if ($script:uiState.Controls.chkInstallApps.IsChecked) { 'Visible' } else { 'Collapsed' }
        $script:uiState.Controls.appListJsonPathPanel.Visibility = if ($script:uiState.Controls.chkInstallApps.IsChecked) { 'Visible' } else { 'Collapsed' }
        $script:uiState.Controls.chkBringYourOwnApps.Visibility = if ($script:uiState.Controls.chkInstallApps.IsChecked) { 'Visible' } else { 'Collapsed' }
        $script:uiState.Controls.byoApplicationPanel.Visibility = if ($script:uiState.Controls.chkBringYourOwnApps.IsChecked) { 'Visible' } else { 'Collapsed' }
        $script:uiState.Controls.wingetPanel.Visibility = if ($script:uiState.Controls.chkInstallWingetApps.IsChecked) { 'Visible' } else { 'Collapsed' }
        $script:uiState.Controls.wingetSearchPanel.Visibility = 'Collapsed' # Keep search hidden initially

        $script:uiState.Controls.chkInstallApps.Add_Checked({
                $script:uiState.Controls.chkInstallWingetApps.Visibility = 'Visible'
                $script:uiState.Controls.applicationPathPanel.Visibility = 'Visible'
                $script:uiState.Controls.appListJsonPathPanel.Visibility = 'Visible'
                $script:uiState.Controls.chkBringYourOwnApps.Visibility = 'Visible'
                # New logic for AppsScriptVariables
                $script:uiState.Controls.chkDefineAppsScriptVariables.Visibility = 'Visible'
            })
        $script:uiState.Controls.chkInstallApps.Add_Unchecked({
                $script:uiState.Controls.chkInstallWingetApps.IsChecked = $false # Uncheck children when parent is unchecked
                $script:uiState.Controls.chkBringYourOwnApps.IsChecked = $false
                $script:uiState.Controls.chkInstallWingetApps.Visibility = 'Collapsed'
                $script:uiState.Controls.applicationPathPanel.Visibility = 'Collapsed'
                $script:uiState.Controls.appListJsonPathPanel.Visibility = 'Collapsed'
                $script:uiState.Controls.chkBringYourOwnApps.Visibility = 'Collapsed'
                $script:uiState.Controls.wingetPanel.Visibility = 'Collapsed'
                $script:uiState.Controls.wingetSearchPanel.Visibility = 'Collapsed'
                $script:uiState.Controls.byoApplicationPanel.Visibility = 'Collapsed'
                # New logic for AppsScriptVariables
                $script:uiState.Controls.chkDefineAppsScriptVariables.IsChecked = $false # Also uncheck it
                $script:uiState.Controls.chkDefineAppsScriptVariables.Visibility = 'Collapsed'
                $script:uiState.Controls.appsScriptVariablesPanel.Visibility = 'Collapsed' # Ensure panel is hidden
            })
        $script:uiState.Controls.btnBrowseApplicationPath.Add_Click({
                $selectedPath = Show-ModernFolderPicker -Title "Select Application Path Folder"
                if ($selectedPath) { $script:uiState.Controls.txtApplicationPath.Text = $selectedPath }
            })
        $script:uiState.Controls.btnBrowseAppListJsonPath.Add_Click({
                $ofd = New-Object System.Windows.Forms.OpenFileDialog
                $ofd.Filter = "JSON files (*.json)|*.json"
                $ofd.Title = "Select AppList.json File"
                $ofd.CheckFileExists = $false
                if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $script:uiState.Controls.txtAppListJsonPath.Text = $ofd.FileName }
            })
        $script:uiState.Controls.chkBringYourOwnApps.Add_Checked({ $script:uiState.Controls.byoApplicationPanel.Visibility = 'Visible' })
        $script:uiState.Controls.chkBringYourOwnApps.Add_Unchecked({
                $script:uiState.Controls.byoApplicationPanel.Visibility = 'Collapsed'
                # Clear fields when hiding
                $script:uiState.Controls.txtAppName.Text = ''
                $script:uiState.Controls.txtAppCommandLine.Text = ''
                $script:uiState.Controls.txtAppArguments.Text = ''
                $script:uiState.Controls.txtAppSource.Text = ''
            })
        $script:uiState.Controls.chkInstallWingetApps.Add_Checked({ $script:uiState.Controls.wingetPanel.Visibility = 'Visible' })
        $script:uiState.Controls.chkInstallWingetApps.Add_Unchecked({
                $script:uiState.Controls.wingetPanel.Visibility = 'Collapsed'
                $script:uiState.Controls.wingetSearchPanel.Visibility = 'Collapsed' # Hide search when unchecked
            })
        $script:uiState.Controls.btnCheckWingetModule.Add_Click({
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
                    if ($statusResult.Success -and $script:uiState.Controls.chkInstallWingetApps.IsChecked) {
                        $script:uiState.Controls.wingetSearchPanel.Visibility = 'Visible'
                    }
                    else {
                        $script:uiState.Controls.wingetSearchPanel.Visibility = 'Collapsed' # Hide if not successful or unchecked
                    }
                }
                catch {
                    # Catch errors from the Confirm-WingetInstallationUI call itself (less likely now)
                    Update-WingetVersionFields -wingetText "Error" -moduleText "Error"
                    [System.Windows.MessageBox]::Show("Unexpected error checking/installing Winget components: $($_.Exception.Message)", "Error", "OK", "Error")
                    $script:uiState.Controls.wingetSearchPanel.Visibility = 'Collapsed' # Ensure search is hidden on error
                }
                finally {
                    $buttonSender.IsEnabled = $true
                    $window.Cursor = $null
                }
            })

        # Winget Search ListView setup
        $wingetGridView = New-Object System.Windows.Controls.GridView
        $script:uiState.Controls.lstWingetResults.View = $wingetGridView # Assign GridView to ListView first

        # Add the selectable column using the new function
        Add-SelectableGridViewColumn -ListView $script:uiState.Controls.lstWingetResults -HeaderCheckBoxScriptVariableName "chkSelectAllWingetResults" -ColumnWidth 60

        # Add other sortable columns with left-aligned headers
        Add-SortableColumn -gridView $wingetGridView -header "Name" -binding "Name" -width 200 -headerHorizontalAlignment Left
        Add-SortableColumn -gridView $wingetGridView -header "Id" -binding "Id" -width 200 -headerHorizontalAlignment Left
        Add-SortableColumn -gridView $wingetGridView -header "Version" -binding "Version" -width 100 -headerHorizontalAlignment Left
        Add-SortableColumn -gridView $wingetGridView -header "Source" -binding "Source" -width 100 -headerHorizontalAlignment Left
        Add-SortableColumn -gridView $wingetGridView -header "Download Status" -binding "DownloadStatus" -width 150 -headerHorizontalAlignment Left
        $script:uiState.Controls.lstWingetResults.AddHandler(
            [System.Windows.Controls.GridViewColumnHeader]::ClickEvent,
            [System.Windows.RoutedEventHandler] {
                param($eventSource, $e)
                $header = $e.OriginalSource
                if ($header -is [System.Windows.Controls.GridViewColumnHeader] -and $header.Tag) {
                    Invoke-ListViewSort -listView $script:uiState.Controls.lstWingetResults -property $header.Tag -State $script:uiState 
                }
            }
        )
        $script:uiState.Controls.btnWingetSearch.Add_Click({ Search-WingetApps -State $script:uiState })
        $script:uiState.Controls.txtWingetSearch.Add_KeyDown({
                param($eventSrc, $keyEvent)
                if ($keyEvent.Key -eq 'Return') { Search-WingetApps -State $script:uiState; $keyEvent.Handled = $true }
            })
        $script:uiState.Controls.btnSaveWingetList.Add_Click({ Save-WingetList -State $script:uiState })
        $script:uiState.Controls.btnImportWingetList.Add_Click({ Import-WingetList -State $script:uiState })
        $script:uiState.Controls.btnClearWingetList.Add_Click({
                $script:uiState.Controls.lstWingetResults.ItemsSource = @() # Set ItemsSource to an empty array
                $script:uiState.Controls.txtWingetSearch.Text = ""
                if ($script:uiState.Controls.txtStatus) { $script:uiState.Controls.txtStatus.Text = "Cleared all applications from the list" }
            })

        $script:uiState.Controls.btnDownloadSelected.Add_Click({
                param($buttonSender, $clickEventArgs)

                $selectedApps = $script:uiState.Controls.lstWingetResults.Items | Where-Object { $_.IsSelected }
                if (-not $selectedApps) {
                    [System.Windows.MessageBox]::Show("No applications selected to download.", "Download Winget Apps", "OK", "Information")
                    return
                }

                $buttonSender.IsEnabled = $false
                $script:uiState.Controls.pbOverallProgress.Visibility = 'Visible'
                $script:uiState.Controls.pbOverallProgress.Value = 0
                $script:uiState.Controls.txtStatus.Text = "Starting Winget app downloads..."

                # Define necessary task-specific variables locally
                $localAppsPath = $script:uiState.Controls.txtApplicationPath.Text
                $localAppListJsonPath = $script:uiState.Controls.txtAppListJsonPath.Text
                $localWindowsArch = $script:uiState.Controls.cmbWindowsArch.SelectedItem
                $localOrchestrationPath = Join-Path -Path $script:uiState.Controls.txtApplicationPath.Text -ChildPath "Orchestration"

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
                    -ListViewControl $script:uiState.Controls.lstWingetResults `
                    -IdentifierProperty 'Id' `
                    -StatusProperty 'DownloadStatus' `
                    -TaskType 'WingetDownload' `
                    -TaskArguments $taskArguments `
                    -CompletedStatusText "Completed" `
                    -ErrorStatusPrefix "Error: " `
                    -WindowObject $window `
                    -MainThreadLogPath $script:uiState.LogFilePath

                # Final status update (handled by Invoke-ParallelProcessing)
                $script:uiState.Controls.pbOverallProgress.Visibility = 'Collapsed'
                $buttonSender.IsEnabled = $true
            })

        # BYO Apps UI logic (Keep existing logic)
        $script:uiState.Controls.btnBrowseAppSource.Add_Click({
                $selectedPath = Show-ModernFolderPicker -Title "Select Application Source Folder"
                if ($selectedPath) { $script:uiState.Controls.txtAppSource.Text = $selectedPath }
            })
        $script:uiState.Controls.btnAddApplication.Add_Click({
                $name = $script:uiState.Controls.txtAppName.Text
                $commandLine = $script:uiState.Controls.txtAppCommandLine.Text
                $arguments = $script:uiState.Controls.txtAppArguments.Text
                $source = $script:uiState.Controls.txtAppSource.Text

                if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($commandLine) -or [string]::IsNullOrWhiteSpace($arguments)) {
                    [System.Windows.MessageBox]::Show("Please fill in all fields (Name, Command Line, and Arguments)", "Missing Information", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
                    return
                }
                $listView = $script:uiState.Controls.lstApplications
                $priority = 1
                if ($listView.Items.Count -gt 0) {
                    $priority = ($listView.Items | Measure-Object -Property Priority -Maximum).Maximum + 1
                }
                $application = [PSCustomObject]@{ Priority = $priority; Name = $name; CommandLine = $commandLine; Arguments = $arguments; Source = $source; CopyStatus = "" }
                $listView.Items.Add($application)
                $script:uiState.Controls.txtAppName.Text = ""
                $script:uiState.Controls.txtAppCommandLine.Text = ""
                $script:uiState.Controls.txtAppArguments.Text = ""
                $script:uiState.Controls.txtAppSource.Text = ""
                Update-CopyButtonState -State $script:uiState
            })
        $script:uiState.Controls.btnSaveBYOApplications.Add_Click({
                $saveDialog = New-Object Microsoft.Win32.SaveFileDialog
                $saveDialog.Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*"
                $saveDialog.DefaultExt = ".json"
                $saveDialog.Title = "Save Application List"
                $initialDir = $script:uiState.Controls.txtApplicationPath.Text
                if ([string]::IsNullOrWhiteSpace($initialDir) -or -not (Test-Path $initialDir)) { $initialDir = $PSScriptRoot }
                $saveDialog.InitialDirectory = $initialDir
                $saveDialog.FileName = "UserAppList.json"
                if ($saveDialog.ShowDialog()) { Save-BYOApplicationList -Path $saveDialog.FileName -State $script:uiState }
            })
        $script:uiState.Controls.btnLoadBYOApplications.Add_Click({
                $openDialog = New-Object Microsoft.Win32.OpenFileDialog
                $openDialog.Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*"
                $openDialog.Title = "Import Application List"
                $initialDir = $script:uiState.Controls.txtApplicationPath.Text
                if ([string]::IsNullOrWhiteSpace($initialDir) -or -not (Test-Path $initialDir)) { $initialDir = $PSScriptRoot }
                $openDialog.InitialDirectory = $initialDir
                if ($openDialog.ShowDialog()) { Import-BYOApplicationList -Path $openDialog.FileName -State $script:uiState; Update-CopyButtonState -State $script:uiState }
            })
        $script:uiState.Controls.btnClearBYOApplications.Add_Click({
                $result = [System.Windows.MessageBox]::Show("Are you sure you want to clear all applications?", "Clear Applications", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
                if ($result -eq [System.Windows.MessageBoxResult]::Yes) { $script:uiState.Controls.lstApplications.Items.Clear(); Update-CopyButtonState -State $script:uiState }
            })
        $script:uiState.Controls.btnCopyBYOApps.Add_Click({
                param($buttonSender, $clickEventArgs)

                $appsToCopy = $script:uiState.Controls.lstApplications.Items | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Source) }
                if (-not $appsToCopy) {
                    [System.Windows.MessageBox]::Show("No applications with a source path specified.", "Copy BYO Apps", "OK", "Information")
                    return
                }

                $buttonSender.IsEnabled = $false
                $script:uiState.Controls.pbOverallProgress.Visibility = 'Visible'
                $script:uiState.Controls.pbOverallProgress.Value = 0
                $script:uiState.Controls.txtStatus.Text = "Starting BYO app copy..."

                # Define necessary task-specific variables locally
                $localAppsPath = $script:uiState.Controls.txtApplicationPath.Text

                # Create hashtable for task-specific arguments
                $taskArguments = @{
                    AppsPath = $localAppsPath
                }

                # Select only necessary properties before passing
                $itemsToProcess = $appsToCopy | Select-Object Priority, Name, CommandLine, Arguments, Source

                # Invoke the centralized parallel processing function
                # Pass task type and task-specific arguments
                Invoke-ParallelProcessing -ItemsToProcess $itemsToProcess `
                    -ListViewControl $script:uiState.Controls.lstApplications `
                    -IdentifierProperty 'Name' `
                    -StatusProperty 'CopyStatus' `
                    -TaskType 'CopyBYO' `
                    -TaskArguments $taskArguments `
                    -CompletedStatusText "Copied" `
                    -ErrorStatusPrefix "Error: " `
                    -WindowObject $window `
                    -MainThreadLogPath $script:uiState.LogFilePath

                # Final status update (handled by Invoke-ParallelProcessing)
                $script:uiState.Controls.pbOverallProgress.Visibility = 'Collapsed'
                $buttonSender.IsEnabled = $true
            })
        $script:uiState.Controls.btnMoveTop.Add_Click({ Move-ListViewItemTop -ListView $script:uiState.Controls.lstApplications })
        $script:uiState.Controls.btnMoveUp.Add_Click({ Move-ListViewItemUp -ListView $script:uiState.Controls.lstApplications })
        $script:uiState.Controls.btnMoveDown.Add_Click({ Move-ListViewItemDown -ListView $script:uiState.Controls.lstApplications })
        $script:uiState.Controls.btnMoveBottom.Add_Click({ Move-ListViewItemBottom -ListView $script:uiState.Controls.lstApplications })

        # BYO Apps ListView setup (Keep existing logic, ensure CopyStatus column is handled)
        $byoGridView = $script:uiState.Controls.lstApplications.View
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
        Update-CopyButtonState -State $script:uiState # Initial check

        # General Browse Button Handlers (Keep existing logic)
        $script:uiState.Controls.btnBrowseFFUDevPath.Add_Click({
                $selectedPath = Show-ModernFolderPicker -Title "Select FFU Development Path"
                if ($selectedPath) { $script:uiState.Controls.txtFFUDevPath.Text = $selectedPath }
            })
        $script:uiState.Controls.btnBrowseFFUCaptureLocation.Add_Click({
                $selectedPath = Show-ModernFolderPicker -Title "Select FFU Capture Location"
                if ($selectedPath) { $script:uiState.Controls.txtFFUCaptureLocation.Text = $selectedPath }
            })
        $script:uiState.Controls.btnBrowseOfficePath.Add_Click({
                $selectedPath = Show-ModernFolderPicker -Title "Select Office Path"
                if ($selectedPath) { $script:uiState.Controls.txtOfficePath.Text = $selectedPath }
            })
        $script:uiState.Controls.btnBrowseDriversFolder.Add_Click({
                $selectedPath = Show-ModernFolderPicker -Title "Select Drivers Folder"
                if ($selectedPath) { $script:uiState.Controls.txtDriversFolder.Text = $selectedPath }
            })
        $script:uiState.Controls.btnBrowsePEDriversFolder.Add_Click({
                $selectedPath = Show-ModernFolderPicker -Title "Select PE Drivers Folder"
                if ($selectedPath) { $script:uiState.Controls.txtPEDriversFolder.Text = $selectedPath }
            })
        $script:uiState.Controls.btnBrowseDriversJsonPath.Add_Click({
                $sfd = New-Object System.Windows.Forms.SaveFileDialog
                $sfd.Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*"
                $sfd.Title = "Select or Create Drivers.json File"
                $sfd.FileName = "Drivers.json"
                $sfd.CheckFileExists = $false # Allow creating a new file or selecting existing

                $currentDriversJsonPath = $script:uiState.Controls.txtDriversJsonPath.Text
                $dialogInitialDirectory = $null # Initialize to null

                if (-not [string]::IsNullOrWhiteSpace($currentDriversJsonPath)) {
                    WriteLog "Attempting to determine InitialDirectory for Drivers.json SaveFileDialog from txtDriversJsonPath: '$currentDriversJsonPath'"
                    try {
                        # Attempt to get the parent directory of the path in the textbox
                        $parentDir = Split-Path -Path $currentDriversJsonPath -Parent -ErrorAction Stop

                        # Check if the parent directory is not null/empty and actually exists as a directory
                        if (-not ([string]::IsNullOrEmpty($parentDir)) -and (Test-Path -Path $parentDir -PathType Container)) {
                            $dialogInitialDirectory = $parentDir
                            WriteLog "Set InitialDirectory for SaveFileDialog to '$parentDir' based on parent of txtDriversJsonPath."
                        }
                        else {
                            # Parent directory is invalid or doesn't exist
                            WriteLog "Parent directory '$parentDir' from txtDriversJsonPath ('$currentDriversJsonPath') is not a valid existing directory. SaveFileDialog will use default InitialDirectory."
                            # $dialogInitialDirectory remains $null, so dialog uses its default
                        }
                    }
                    catch {
                        # Error occurred trying to split the path (e.g., path is malformed)
                        WriteLog "Error splitting path from txtDriversJsonPath ('$currentDriversJsonPath'): $($_.Exception.Message). SaveFileDialog will use default InitialDirectory."
                        # $dialogInitialDirectory remains $null
                    }
                }
                else {
                    # TextBox is empty, dialog will use its default initial directory
                    WriteLog "txtDriversJsonPath is empty. SaveFileDialog will use default InitialDirectory."
                    # $dialogInitialDirectory remains $null
                }

                $sfd.InitialDirectory = $dialogInitialDirectory # Set to $null if no valid directory was found, dialog will use its default

                if ($sfd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                    $script:uiState.Controls.txtDriversJsonPath.Text = $sfd.FileName
                    WriteLog "User selected or created Drivers.json at: $($sfd.FileName)"
                }
                else {
                    WriteLog "User cancelled SaveFileDialog for Drivers.json."
                }
            })

        # Driver Checkbox Conditional Logic
        $script:uiState.Controls.chkInstallDrivers.Add_Checked({
                $script:uiState.Controls.chkCopyDrivers.IsEnabled = $false
                $script:uiState.Controls.chkCompressDriversToWIM.IsEnabled = $false
            })
        $script:uiState.Controls.chkInstallDrivers.Add_Unchecked({
                # Only re-enable if the other checkboxes are not checked
                if (-not $script:uiState.Controls.chkCopyDrivers.IsChecked) { $script:uiState.Controls.chkCopyDrivers.IsEnabled = $true }
                if (-not $script:uiState.Controls.chkCompressDriversToWIM.IsChecked) { $script:uiState.Controls.chkCompressDriversToWIM.IsEnabled = $true }
            })
        $script:uiState.Controls.chkCopyDrivers.Add_Checked({
                $script:uiState.Controls.chkInstallDrivers.IsEnabled = $false
            })
        $script:uiState.Controls.chkCopyDrivers.Add_Unchecked({
                # Only re-enable if InstallDrivers is not checked
                if (-not $script:uiState.Controls.chkInstallDrivers.IsChecked) { $script:uiState.Controls.chkInstallDrivers.IsEnabled = $true }
            })
        $script:uiState.Controls.chkCompressDriversToWIM.Add_Checked({
                $script:uiState.Controls.chkInstallDrivers.IsEnabled = $false
            })
        $script:uiState.Controls.chkCompressDriversToWIM.Add_Unchecked({
                # Only re-enable if InstallDrivers is not checked
                if (-not $script:uiState.Controls.chkInstallDrivers.IsChecked) { $script:uiState.Controls.chkInstallDrivers.IsEnabled = $true }
            })
        # Set initial state based on defaults (assuming defaults are false)
        $script:uiState.Controls.chkInstallDrivers.IsEnabled = $true
        $script:uiState.Controls.chkCopyDrivers.IsEnabled = $true
        $script:uiState.Controls.chkCompressDriversToWIM.IsEnabled = $true

        # AppsScriptVariables Event Handlers
        $script:uiState.Controls.chkDefineAppsScriptVariables.Add_Checked({
                $script:uiState.Controls.appsScriptVariablesPanel.Visibility = 'Visible'
            })
        $script:uiState.Controls.chkDefineAppsScriptVariables.Add_Unchecked({
                $script:uiState.Controls.appsScriptVariablesPanel.Visibility = 'Collapsed'
            })

        $script:uiState.Controls.btnAddAppsScriptVariable.Add_Click({
                $key = $script:uiState.Controls.txtAppsScriptKey.Text.Trim()
                $value = $script:uiState.Controls.txtAppsScriptValue.Text.Trim()

                if ([string]::IsNullOrWhiteSpace($key)) {
                    [System.Windows.MessageBox]::Show("Apps Script Variable Key cannot be empty.", "Input Error", "OK", "Warning")
                    return
                }
                # Check for duplicate keys
                $existingKey = $script:uiState.Controls.lstAppsScriptVariables.Items | Where-Object { $_.Key -eq $key }
                if ($existingKey) {
                    [System.Windows.MessageBox]::Show("An Apps Script Variable with the key '$key' already exists.", "Duplicate Key", "OK", "Warning")
                    return
                }

                $newItem = [PSCustomObject]@{
                    IsSelected = $false # Add IsSelected property
                    Key        = $key
                    Value      = $value
                }
                $script:uiState.Data.appsScriptVariablesDataList.Add($newItem)
                $script:uiState.Controls.lstAppsScriptVariables.ItemsSource = $script:uiState.Data.appsScriptVariablesDataList.ToArray()
                $script:uiState.Controls.txtAppsScriptKey.Clear()
                $script:uiState.Controls.txtAppsScriptValue.Clear()
                # Update the header checkbox state
                if ($null -ne $script:uiState.Controls.chkSelectAllAppsScriptVariables) {
                    Update-SelectAllHeaderCheckBoxState -ListView $script:uiState.Controls.lstAppsScriptVariables -HeaderCheckBox $script:uiState.Controls.chkSelectAllAppsScriptVariables
                }
            })

        $script:uiState.Controls.btnRemoveSelectedAppsScriptVariables.Add_Click({
                $itemsToRemove = @($script:uiState.Data.appsScriptVariablesDataList | Where-Object { $_.IsSelected })
                if ($itemsToRemove.Count -eq 0) {
                    [System.Windows.MessageBox]::Show("Please select one or more Apps Script Variables to remove.", "Selection Error", "OK", "Warning")
                    return
                }

                foreach ($itemToRemove in $itemsToRemove) {
                    $script:uiState.Data.appsScriptVariablesDataList.Remove($itemToRemove)
                }
                $script:uiState.Controls.lstAppsScriptVariables.ItemsSource = $script:uiState.Data.appsScriptVariablesDataList.ToArray()

                # Update the header checkbox state
                if ($null -ne $script:uiState.Controls.chkSelectAllAppsScriptVariables) {
                    # Check if variable exists
                    Update-SelectAllHeaderCheckBoxState -ListView $script:uiState.Controls.lstAppsScriptVariables -HeaderCheckBox $script:uiState.Controls.chkSelectAllAppsScriptVariables
                }
            })

        $script:uiState.Controls.btnClearAppsScriptVariables.Add_Click({
                $script:uiState.Data.appsScriptVariablesDataList.Clear()
                $script:uiState.Controls.lstAppsScriptVariables.ItemsSource = $script:uiState.Data.appsScriptVariablesDataList.ToArray()
                # Update the header checkbox state
                if ($null -ne $script:uiState.Controls.chkSelectAllAppsScriptVariables) {
                    Update-SelectAllHeaderCheckBoxState -ListView $script:uiState.Controls.lstAppsScriptVariables -HeaderCheckBox $script:uiState.Controls.chkSelectAllAppsScriptVariables
                }
            })

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

# Function to search for Winget apps
function Search-WingetApps {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$State
    )
    try {
        $searchQuery = $State.Controls.txtWingetSearch.Text
        if ([string]::IsNullOrWhiteSpace($searchQuery)) { return }

        # Get current items from the ListView
        $currentItemsInListView = @()
        if ($null -ne $State.Controls.lstWingetResults.ItemsSource) {
            $currentItemsInListView = @($State.Controls.lstWingetResults.ItemsSource)
        }
        elseif ($State.Controls.lstWingetResults.HasItems) {
            $currentItemsInListView = @($State.Controls.lstWingetResults.Items)
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
        $script:uiState.Controls.lstWingetResults.ItemsSource = $finalAppList.ToArray()
    }
    catch {
        [System.Windows.MessageBox]::Show("Error searching for apps: $_", "Error", "OK", "Error")
    }
}

# Function to save selected apps to JSON
function Save-WingetList {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$State
    )
    try {
        $selectedApps = $State.Controls.lstWingetResults.Items | Where-Object { $_.IsSelected }
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
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$State
    )
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

            $State.Controls.lstWingetResults.ItemsSource = $newAppListForItemsSource.ToArray()

            [System.Windows.MessageBox]::Show("App list imported successfully.", "Success", "OK", "Information")
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Error importing app list: $_", "Error", "OK", "Error")
    }
}

# Function to remove application and reorder priorities
function Remove-Application {
    param(
        $priority,
        [psobject]$State
    )

    $listView = $State.Controls.lstApplications

    # Remove the item with the specified priority
    $itemToRemove = $listView.Items | Where-Object { $_.Priority -eq $priority } | Select-Object -First 1
    if ($itemToRemove) {
        $listView.Items.Remove($itemToRemove)
        # Reorder priorities for remaining items
        Update-ListViewPriorities -ListView $listView
        # Update the Copy Apps button state
        Update-CopyButtonState -State $State
    }
}

# Function to save BYO applications to JSON
function Save-BYOApplicationList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [psobject]$State
    )

    $listView = $State.Controls.lstApplications
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
        [string]$Path,
        [Parameter(Mandatory)]
        [psobject]$State
    )

    if (-not (Test-Path $Path)) {
        [System.Windows.MessageBox]::Show("Application list file not found at `"$Path`".", "Import Applications", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

    try {
        $applications = Get-Content -Path $Path -Raw | ConvertFrom-Json
        $listView = $State.Controls.lstApplications
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
        Update-CopyButtonState -State $State

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
                $script:uiState.Data.appsScriptVariablesDataList.Clear() # Clear the backing data list

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
                if ($null -ne (Get-Variable -Name 'chkSelectAllAppsScriptVariables' -Scope Script -ErrorAction SilentlyContinue)) {
                    Update-SelectAllHeaderCheckBoxState -ListView $lstAppsScriptVars -HeaderCheckBox $script:chkSelectAllAppsScriptVariables
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

                    # Update the Select All checkbox state
                    $allSelected = $script:uiState.Controls.lstUSBDrives.Items.Count -gt 0 -and -not ($script:uiState.Controls.lstUSBDrives.Items | Where-Object { -not $_.IsSelected })
                    $script:uiState.Controls.chkSelectAllUSBDrives.IsChecked = $allSelected
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
