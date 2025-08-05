<#
.SYNOPSIS
    Manages the UI business logic for the "Applications" tab, including "Bring Your Own (BYO) Applications" and "Apps Script Variables".
.DESCRIPTION
    This module contains all the functions that power the "Applications" tab in the BuildFFUVM_UI. It handles user interactions for managing custom application lists (BYO Apps), such as adding, removing, reordering, and saving/loading the list from a JSON file (UserAppList.json). It also includes the logic for copying the application source files to the designated staging directory in parallel. Additionally, it manages the UI for creating and removing key-value pairs for the AppsScriptVariables.json file, which allows for custom parameterization of user-provided scripts.
#>

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

# Function to add a new BYO application from the UI
function Add-BYOApplication {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$State
    )

    $name = $State.Controls.txtAppName.Text
    $commandLine = $State.Controls.txtAppCommandLine.Text
    $arguments = $State.Controls.txtAppArguments.Text
    $source = $State.Controls.txtAppSource.Text
    $additionalExitCodes = $State.Controls.txtAppAdditionalExitCodes.Text
    $ignoreNonZeroExitCodes = $State.Controls.chkIgnoreExitCodes.IsChecked

    if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($commandLine)) {
        [System.Windows.MessageBox]::Show("Please fill in all fields (Name and Command Line)", "Missing Information", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }
    $listView = $State.Controls.lstApplications
    # Check for duplicate names
    $existingApp = $listView.Items | Where-Object { $_.Name -eq $name }
    if ($existingApp) {
        [System.Windows.MessageBox]::Show("An application with the name '$name' already exists.", "Duplicate Name", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }
    $priority = 1
    if ($listView.Items.Count -gt 0) {
        $priority = ($listView.Items | Measure-Object -Property Priority -Maximum).Maximum + 1
    }
    $application = [PSCustomObject]@{ 
        Priority = $priority
        Name = $name
        CommandLine = $commandLine
        Arguments = $arguments
        Source = $source
        AdditionalExitCodes = $additionalExitCodes
        IgnoreNonZeroExitCodes = $ignoreNonZeroExitCodes
        IgnoreExitCodes = if ($ignoreNonZeroExitCodes) { "Yes" } else { "No" }
        CopyStatus = "" 
    }
    $listView.Items.Add($application)
    $State.Controls.txtAppName.Text = ""
    $State.Controls.txtAppCommandLine.Text = ""
    $State.Controls.txtAppArguments.Text = ""
    $State.Controls.txtAppSource.Text = ""
    $State.Controls.txtAppAdditionalExitCodes.Text = ""
    $State.Controls.chkIgnoreExitCodes.IsChecked = $false
    Update-CopyButtonState -State $State
}
    
# Function to add a new Apps Script Variable from the UI
function Add-AppsScriptVariable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$State
    )
    
    $key = $State.Controls.txtAppsScriptKey.Text.Trim()
    $value = $State.Controls.txtAppsScriptValue.Text.Trim()
    
    if ([string]::IsNullOrWhiteSpace($key)) {
        [System.Windows.MessageBox]::Show("Apps Script Variable Key cannot be empty.", "Input Error", "OK", "Warning")
        return
    }
    # Check for duplicate keys
    $existingKey = $State.Controls.lstAppsScriptVariables.Items | Where-Object { $_.Key -eq $key }
    if ($existingKey) {
        [System.Windows.MessageBox]::Show("An Apps Script Variable with the key '$key' already exists.", "Duplicate Key", "OK", "Warning")
        return
    }
    
    $newItem = [PSCustomObject]@{
        IsSelected = $false # Add IsSelected property
        Key        = $key
        Value      = $value
    }
    $State.Data.appsScriptVariablesDataList.Add($newItem)
    $State.Controls.lstAppsScriptVariables.ItemsSource = $State.Data.appsScriptVariablesDataList.ToArray()
    $State.Controls.txtAppsScriptKey.Clear()
    $State.Controls.txtAppsScriptValue.Clear()
    # Update the header checkbox state
    if ($null -ne $State.Controls.chkSelectAllAppsScriptVariables) {
        Update-SelectAllHeaderCheckBoxState -ListView $State.Controls.lstAppsScriptVariables -HeaderCheckBox $State.Controls.chkSelectAllAppsScriptVariables
    }
}

# Function to remove selected Apps Script Variables from the list
function Remove-SelectedAppsScriptVariable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$State
    )

    $itemsToRemove = @($State.Data.appsScriptVariablesDataList | Where-Object { $_.IsSelected })
    if ($itemsToRemove.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Please select one or more Apps Script Variables to remove.", "Selection Error", "OK", "Warning")
        return
    }

    foreach ($itemToRemove in $itemsToRemove) {
        $State.Data.appsScriptVariablesDataList.Remove($itemToRemove)
    }
    $State.Controls.lstAppsScriptVariables.ItemsSource = $State.Data.appsScriptVariablesDataList.ToArray()

    # Update the header checkbox state
    if ($null -ne $State.Controls.chkSelectAllAppsScriptVariables) {
        Update-SelectAllHeaderCheckBoxState -ListView $State.Controls.lstAppsScriptVariables -HeaderCheckBox $State.Controls.chkSelectAllAppsScriptVariables
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
        # Exclude UI-only properties (CopyStatus, IgnoreExitCodes) and ensure Priority is an integer
        $propertiesToSave = 'Priority', 'Name', 'CommandLine', 'Arguments', 'Source', 'AdditionalExitCodes', 'IgnoreNonZeroExitCodes'
        $applications = $listView.Items | Sort-Object Priority | Select-Object @{N = 'Priority'; E = { [int]$_.Priority } }, Name, CommandLine, Arguments, Source, AdditionalExitCodes, IgnoreNonZeroExitCodes
        
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
            $ignoreNonZero = if ($app.PSObject.Properties['IgnoreNonZeroExitCodes']) { $app.IgnoreNonZeroExitCodes } else { $false }
            $appObject = [PSCustomObject]@{
                Priority               = $app.Priority
                Name                   = $app.Name
                CommandLine            = $app.CommandLine
                Arguments              = if ($app.PSObject.Properties['Arguments']) { $app.Arguments } else { "" }
                Source                 = $app.Source
                AdditionalExitCodes    = if ($app.PSObject.Properties['AdditionalExitCodes']) { $app.AdditionalExitCodes } else { "" }
                IgnoreNonZeroExitCodes = $ignoreNonZero
                IgnoreExitCodes        = if ($ignoreNonZero) { "Yes" } else { "No" }
                CopyStatus             = ""
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
        
# Function to invoke the parallel copy process for BYO apps
function Invoke-CopyBYOApps {
    param(
        [psobject]$State,
        [System.Windows.Controls.Button]$Button
    )
        
    $localAppsPath = $State.Controls.txtApplicationPath.Text
    $userAppListPath = Join-Path -Path $localAppsPath -ChildPath 'UserAppList.json'
    $listView = $State.Controls.lstApplications

    try {
        # Ensure items are sorted by current priority before saving
        # Exclude CopyStatus when saving and ensure Priority is an integer
        $applications = $listView.Items | Sort-Object Priority | Select-Object @{N = 'Priority'; E = { [int]$_.Priority } }, Name, CommandLine, Arguments, Source
        $applications | ConvertTo-Json -Depth 5 | Set-Content -Path $userAppListPath -Force -Encoding UTF8
        WriteLog "Successfully updated UserAppList.json with all applications from the UI."
    }
    catch {
        $errorMessage = "Failed to update UserAppList.json: $_"
        WriteLog $errorMessage
        [System.Windows.MessageBox]::Show($errorMessage, "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        return
    }

    $allAppsWithSource = $State.Controls.lstApplications.Items | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Source) }
    if (-not $allAppsWithSource) {
        [System.Windows.MessageBox]::Show("No applications with a source path were found to copy.", "Copy BYO Apps", "OK", "Information")
        return
    }
        
    $win32BasePath = Join-Path -Path $localAppsPath -ChildPath "Win32"
    
    $appsToProcess = [System.Collections.Generic.List[object]]::new()
    $appsThatExist = [System.Collections.Generic.List[string]]::new()
    $appsToConfirm = [System.Collections.Generic.List[object]]::new()

    foreach ($app in $allAppsWithSource) {
        $destinationPath = Join-Path -Path $win32BasePath -ChildPath $app.Name
        if (Test-Path -Path $destinationPath -PathType Container) {
            $appsThatExist.Add($app.Name)
            $appsToConfirm.Add($app)
        }
        else {
            $appsToProcess.Add($app)
        }
    }

    if ($appsThatExist.Count -gt 0) {
        $message = "The following application folders already exist in the destination and will be overwritten:`n`n$($appsThatExist -join "`n")`n`nDo you want to proceed with copying and overwriting them?"
        $result = [System.Windows.MessageBox]::Show($message, "Confirm Overwrite", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
        
        if ($result -eq 'Yes') {
            $appsToProcess.AddRange($appsToConfirm)
        }
    }

    if ($appsToProcess.Count -eq 0) {
        # This message can be suppressed if you prefer no notification when the user clicks "No"
        # [System.Windows.MessageBox]::Show("No applications selected for copying.", "Copy BYO Apps", "OK", "Information")
        return
    }
        
    $Button.IsEnabled = $false
    $State.Controls.pbOverallProgress.Visibility = 'Visible'
    $State.Controls.pbOverallProgress.Value = 0
    $State.Controls.txtStatus.Text = "Starting BYO app copy..."
        
    # Create hashtable for task-specific arguments
    $taskArguments = @{
        AppsPath = $localAppsPath
    }
        
    # Select only necessary properties before passing
    $itemsToProcess = $appsToProcess | Select-Object Priority, Name, CommandLine, Arguments, Source
        
    # Invoke the centralized parallel processing function
    # Pass task type and task-specific arguments
    Invoke-ParallelProcessing -ItemsToProcess $itemsToProcess `
        -ListViewControl $State.Controls.lstApplications `
        -IdentifierProperty 'Name' `
        -StatusProperty 'CopyStatus' `
        -TaskType 'CopyBYO' `
        -TaskArguments $taskArguments `
        -CompletedStatusText "Copied" `
        -ErrorStatusPrefix "Error: " `
        -WindowObject $State.Window `
        -MainThreadLogPath $State.LogFilePath `
        -ThrottleLimit $State.Controls.txtThreads.Text
        
    # Final status update (handled by Invoke-ParallelProcessing)
    $State.Controls.pbOverallProgress.Visibility = 'Collapsed'
    $Button.IsEnabled = $true
}
        
# Function to copy a single BYO application (Modified for ForEach-Object -Parallel)
function Start-CopyBYOApplicationTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$ApplicationItemData, # Pass data, not the UI object
        [Parameter(Mandatory)]
        [string]$AppsPath, # Pass necessary path
        [Parameter(Mandatory = $true)]
        [System.Collections.Concurrent.ConcurrentQueue[hashtable]]$ProgressQueue # Add queue parameter
        # REMOVED: UI-related parameters
    )
    
    $priority = $ApplicationItemData.Priority
    $appName = $ApplicationItemData.Name
    $commandLine = $ApplicationItemData.CommandLine
    $arguments = $ApplicationItemData.Arguments
    $sourcePath = $ApplicationItemData.Source   
    $status = "Starting..." # Initial local status
    $success = $false
    
    # Initial status update
    Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $appName -Status $status
    
    if ([string]::IsNullOrWhiteSpace($AppsPath)) {
        $status = "Error: Apps Path not set"
        Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $appName -Status $status
        WriteLog "Copy error for $($appName): Apps Path not set."
        return [PSCustomObject]@{ Name = $appName; Status = $status; Success = $success }
    }

    if ([string]::IsNullOrWhiteSpace($sourcePath)) {
        $status = "No source specified"
        Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $appName -Status $status
        # This isn't an error, just nothing to do. Consider it success.
        $success = $true
        return [PSCustomObject]@{ Name = $appName; Status = $status; Success = $success }
    }

    if (-not (Test-Path -Path $sourcePath -PathType Container)) {
        $status = "Source path not found"
        Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $appName -Status $status
        WriteLog "Copy error for $($appName): Source path '$sourcePath' not found."
        return [PSCustomObject]@{ Name = $appName; Status = $status; Success = $success }
    }

    $win32BasePath = Join-Path -Path $AppsPath -ChildPath "Win32"
    $destinationPath = Join-Path -Path $win32BasePath -ChildPath $appName

    try {
        # Ensure base directory exists
        if (-not (Test-Path -Path $win32BasePath -PathType Container)) {
            New-Item -Path $win32BasePath -ItemType Directory -Force | Out-Null
            WriteLog "Created directory: $win32BasePath"
        }

        # If destination exists, remove it to ensure a clean copy and prevent nesting.
        if (Test-Path -Path $destinationPath -PathType Container) {
            WriteLog "Removing existing destination folder: $destinationPath"
            Remove-Item -Path $destinationPath -Recurse -Force -ErrorAction Stop
        }

        # Perform the copy
        $status = "Copying..."
        Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $appName -Status $status
        WriteLog "Copying '$sourcePath' to '$destinationPath'..."
        Copy-Item -Path $sourcePath -Destination $destinationPath -Recurse -Force -ErrorAction Stop
        $status = "Copied successfully"
        $success = $true
        WriteLog "Successfully copied '$appName' to '$destinationPath'."

    }
    catch {
        $errorMessage = $_.Exception.Message
        $status = "Error: $($errorMessage)"
        WriteLog "Copy error for $($appName): $($errorMessage)"
        $success = $false
        # Enqueue error status
        Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $appName -Status $status
    }
                
    # Return the final status
    return [PSCustomObject]@{ Name = $appName; Status = $status; Success = $success }
}

Export-ModuleMember -Function *