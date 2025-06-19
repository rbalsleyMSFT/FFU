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
        $script:uiState.Controls.btnMoveTop.Add_Click({ 
                Move-ListViewItemTop -ListView $script:uiState.Controls.lstApplications 
            })
        $script:uiState.Controls.btnMoveUp.Add_Click({ 
                Move-ListViewItemUp -ListView $script:uiState.Controls.lstApplications 
            })
        $script:uiState.Controls.btnMoveDown.Add_Click({ 
                Move-ListViewItemDown -ListView $script:uiState.Controls.lstApplications 
            })
        $script:uiState.Controls.btnMoveBottom.Add_Click({ 
                Move-ListViewItemBottom -ListView $script:uiState.Controls.lstApplications 
            })

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
                if (-not $script:uiState.Controls.chkCopyDrivers.IsChecked) { 
                    $script:uiState.Controls.chkCopyDrivers.IsEnabled = $true 
                }
                if (-not $script:uiState.Controls.chkCompressDriversToWIM.IsChecked) { 
                    $script:uiState.Controls.chkCompressDriversToWIM.IsEnabled = $true 
                }
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
