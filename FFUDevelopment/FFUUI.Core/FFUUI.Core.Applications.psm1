# FFU UI Core Applications Module
# Contains UI-layer logic for the "Bring Your Own Apps" and related features.

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

    if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($commandLine) -or [string]::IsNullOrWhiteSpace($arguments)) {
        [System.Windows.MessageBox]::Show("Please fill in all fields (Name, Command Line, and Arguments)", "Missing Information", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }
    $listView = $State.Controls.lstApplications
    $priority = 1
    if ($listView.Items.Count -gt 0) {
        $priority = ($listView.Items | Measure-Object -Property Priority -Maximum).Maximum + 1
    }
    $application = [PSCustomObject]@{ Priority = $priority; Name = $name; CommandLine = $commandLine; Arguments = $arguments; Source = $source; CopyStatus = "" }
    $listView.Items.Add($application)
    $State.Controls.txtAppName.Text = ""
    $State.Controls.txtAppCommandLine.Text = ""
    $State.Controls.txtAppArguments.Text = ""
    $State.Controls.txtAppSource.Text = ""
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
        
# Function to invoke the parallel copy process for BYO apps
function Invoke-CopyBYOApps {
    param(
        [psobject]$State,
        [System.Windows.Controls.Button]$Button
    )
        
    $appsToCopy = $State.Controls.lstApplications.Items | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Source) }
    if (-not $appsToCopy) {
        [System.Windows.MessageBox]::Show("No applications with a source path specified.", "Copy BYO Apps", "OK", "Information")
        return
    }
        
    $Button.IsEnabled = $false
    $State.Controls.pbOverallProgress.Visibility = 'Visible'
    $State.Controls.pbOverallProgress.Value = 0
    $State.Controls.txtStatus.Text = "Starting BYO app copy..."
        
    # Define necessary task-specific variables locally
    $localAppsPath = $State.Controls.txtApplicationPath.Text
        
    # Create hashtable for task-specific arguments
    $taskArguments = @{
        AppsPath = $localAppsPath
    }
        
    # Select only necessary properties before passing
    $itemsToProcess = $appsToCopy | Select-Object Priority, Name, CommandLine, Arguments, Source
        
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
        -MainThreadLogPath $State.LogFilePath
        
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
        $status = "Error: Source path not found"
        Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $appName -Status $status
        WriteLog "Copy error for $($appName): Source path '$sourcePath' not found."
        return [PSCustomObject]@{ Name = $appName; Status = $status; Success = $success }
    }

    $win32BasePath = Join-Path -Path $AppsPath -ChildPath "Win32"
    $destinationPath = Join-Path -Path $win32BasePath -ChildPath $appName

    try {
        # Check destination
        if (Test-Path -Path $destinationPath -PathType Container) {
            $folderSize = (Get-ChildItem -Path $destinationPath -Recurse | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
            if ($folderSize -gt 1MB) {
                $status = "Already copied"
                Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $appName -Status $status
                WriteLog "Skipping copy for $($appName): Destination '$destinationPath' exists and has content."
                $success = $true
                return [PSCustomObject]@{ Name = $appName; Status = $status; Success = $success }
            }
            else {
                WriteLog "Destination '$destinationPath' exists but is empty/small. Proceeding with copy."
            }
        }

        # Ensure base directory exists
        if (-not (Test-Path -Path $win32BasePath -PathType Container)) {
            New-Item -Path $win32BasePath -ItemType Directory -Force | Out-Null
            WriteLog "Created directory: $win32BasePath"
        }

        # Perform the copy
        $status = "Copying..."
        Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $appName -Status $status
        WriteLog "Copying '$sourcePath' to '$destinationPath'..."
        Copy-Item -Path $sourcePath -Destination $destinationPath -Recurse -Force -ErrorAction Stop
        $status = "Copied successfully"
        $success = $true
        WriteLog "Successfully copied '$appName' to '$destinationPath'."

        # ------------------------------------------------------------------
        # Update (or create) UserAppList.json with the copied application
        # ------------------------------------------------------------------
        try {
            WriteLog "Updating UserAppList.json for '$appName'..."
            $userAppListPath = Join-Path -Path $AppsPath -ChildPath 'UserAppList.json'

            # Build the new entry
            $newEntry = [pscustomobject]@{
                Priority    = $priority
                Name        = $appName
                CommandLine = $commandLine
                Arguments   = $arguments
                Source      = $sourcePath
            }

            # Load existing list if present, ensuring it's always an array
            if (Test-Path -Path $userAppListPath) {
                try {
                    # Attempt to load and ensure it's an array
                    $appList = @(Get-Content -Path $userAppListPath -Raw | ConvertFrom-Json -ErrorAction Stop)
                }
                catch {
                    WriteLog "Warning: Could not parse '$userAppListPath' or it's not a valid JSON array. Initializing as empty array. Error: $($_.Exception.Message)"
                    $appList = @() # Initialize as empty array on error
                }
            }
            else {
                $appList = @() # Initialize as empty array if file doesn't exist
            }

            # Ensure $appList is an array even if ConvertFrom-Json returned $null or a single object somehow
            if ($null -eq $appList -or $appList -isnot [array]) {
                # If it was a single object, wrap it in an array. Otherwise, start fresh.
                $appList = if ($null -ne $appList) { @($appList) } else { @() }
            }

            # Skip adding if an entry with the same Name already exists
            if (-not ($appList | Where-Object { $_.Name -eq $newEntry.Name })) {
                # Now $appList is guaranteed to be an array, so += is safe
                $appList += $newEntry
                # Sort by Priority before saving
                $sortedAppList = $appList | Sort-Object Priority
                $sortedAppList | ConvertTo-Json -Depth 10 | Set-Content -Path $userAppListPath -Encoding UTF8
                WriteLog "Added '$($newEntry.Name)' to '$userAppListPath'."
            }
            else {
                WriteLog "'$appName' already exists in '$userAppListPath'."
            }
        }
        catch {
            WriteLog "Failed to update UserAppList.json for '$appName': $($_.Exception.Message)"
        }

    }
    catch {
        $errorMessage = $_.Exception.Message
        $status = "Error: $($errorMessage)"
        WriteLog "Copy error for $($appName): $($errorMessage)"
        $success = $false
        # Enqueue error status
        Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $appName -Status $status
    }
        
    # Enqueue final success status if applicable
    if ($success) {
        Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $appName -Status $status
    }
        
    # Return the final status
    return [PSCustomObject]@{ Name = $appName; Status = $status; Success = $success }
}

Export-ModuleMember -Function *