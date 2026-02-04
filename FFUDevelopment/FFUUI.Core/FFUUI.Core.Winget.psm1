<#
.SYNOPSIS
    Manages all Winget-related functionality for the 'Applications' tab in the FFU Builder UI.
.DESCRIPTION
    This module provides the business logic for interacting with Winget from the FFU Builder UI. It includes functions for searching for packages, importing and exporting application lists, checking for and installing necessary Winget components (CLI and PowerShell module), and managing the parallel download of selected applications. It works in conjunction with FFU.Common.Winget for lower-level operations and FFU.Common.Parallel for managing concurrent downloads.
#>

# Function to search for Winget apps
function Search-WingetApps {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$State
    )

    $searchQuery = $State.Controls.txtWingetSearch.Text
    if ([string]::IsNullOrWhiteSpace($searchQuery)) { return }

    $State.Controls.txtStatus.Text = "Searching Winget for apps matching query '$searchQuery'..."
    $State.Window.Cursor = [System.Windows.Input.Cursors]::Wait
    $State.Controls.btnWingetSearch.IsEnabled = $false

    try {
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

        # Get default architecture from the UI
        $defaultArch = $State.Controls.cmbWindowsArch.SelectedItem

        # Search for new apps, which are streamed directly as PSCustomObjects
        # with the required properties for performance.
        $searchedAppResults = Search-WingetPackagesPublic -Query $searchQuery -DefaultArchitecture $defaultArch
        $finalAppList = [System.Collections.Generic.List[object]]::new()
        $addedAppIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

        # Add previously selected apps first
        foreach ($app in $selectedAppsFromView) {
            $finalAppList.Add($app)
            $addedAppIds.Add($app.Id) | Out-Null
        }

        # Add new search results, avoiding duplicates of already added (selected) apps
        $newAppsAddedCount = 0
        foreach ($result in $searchedAppResults) {
            # HashSet.Add returns $true if the item was added, $false if it already existed.
            if ($addedAppIds.Add($result.Id)) {
                $finalAppList.Add($result)
                $newAppsAddedCount++
            }
        }

        # Update the ListView's ItemsSource using the passed-in State object
        $State.Controls.lstWingetResults.ItemsSource = $finalAppList.ToArray()

        # Update status text
        $statusText = ""
        if ($newAppsAddedCount -gt 0) {
            $statusText = "Found $newAppsAddedCount new applications. "
        }
        else {
            $statusText = "No new applications found. "
        }
        $statusText += "Displaying $($finalAppList.Count) total applications."
        $State.Controls.txtStatus.Text = $statusText
    }
    catch {
        $errorMessage = "Error searching for apps: $($_.Exception.Message)"
        $State.Controls.txtStatus.Text = $errorMessage
        [System.Windows.MessageBox]::Show($errorMessage, "Error", "OK", "Error")
    }
    finally {
        $State.Window.Cursor = $null
        $State.Controls.btnWingetSearch.IsEnabled = $true
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
                        name                   = (ConvertTo-SafeName -Name $_.Name)
                        id                     = $_.Id
                        source                 = $_.Source.ToLower()
                        architecture           = $_.Architecture
                        AdditionalExitCodes    = if ($_.PSObject.Properties['AdditionalExitCodes']) { $_.AdditionalExitCodes } else { "" }
                        IgnoreNonZeroExitCodes = if ($_.PSObject.Properties['IgnoreNonZeroExitCodes']) { [bool]$_.IgnoreNonZeroExitCodes } else { $false }
                    }
                })
        }

        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Filter = "JSON files (*.json)|*.json"
        $sfd.Title = "Save App List"
        # Correctly get the path from the UI control via the State object
        $sfd.InitialDirectory = $State.Controls.txtApplicationPath.Text
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
        # Correctly get the path from the UI control via the State object
        $ofd.InitialDirectory = $State.Controls.txtApplicationPath.Text

        if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $importedAppsData = Get-Content $ofd.FileName -Raw | ConvertFrom-Json

            $newAppListForItemsSource = [System.Collections.Generic.List[object]]::new()

            if ($null -ne $importedAppsData.apps) {
                # Get default architecture from the UI for fallback
                $defaultArch = $State.Controls.cmbWindowsArch.SelectedItem

                foreach ($appInfo in $importedAppsData.apps) {
                    $arch = if ($appInfo.source -eq 'msstore') { 'NA' } else { if ($appInfo.PSObject.Properties['architecture']) { $appInfo.architecture } else { $defaultArch } }
                    $newAppListForItemsSource.Add([PSCustomObject]@{
                            IsSelected               = $true # Imported apps are marked as selected
                            Name                     = $appInfo.name
                            Id                       = $appInfo.id
                            Version                  = ""  # Will be populated when searching or if data exists
                            Source                   = $appInfo.source
                            Architecture             = $arch
                            AdditionalExitCodes      = if ($appInfo.PSObject.Properties['AdditionalExitCodes']) { $appInfo.AdditionalExitCodes } else { "" }
                            IgnoreNonZeroExitCodes   = if ($appInfo.PSObject.Properties['IgnoreNonZeroExitCodes']) { [bool]$appInfo.IgnoreNonZeroExitCodes } else { $false }
                            DownloadStatus           = ""
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

# --------------------------------------------------------------------------
# SECTION: Winget Management Functions (Moved from FFUUI.Core.psm1)
# --------------------------------------------------------------------------
function Search-WingetPackagesPublic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query,
        [Parameter(Mandatory = $true)]
        [string]$DefaultArchitecture
    )

    WriteLog "Searching Winget packages with query: '$Query'"
    try {
        # Using ForEach-Object -Parallel can speed up object creation on multi-core systems
        # by distributing the work across multiple threads.
        $results = Find-WinGetPackage -Query $Query -ErrorAction Stop
        WriteLog "Found $($results.Count) packages matching query '$Query'."
        WriteLog "Creating output objects for Winget search results, please wait..."
        $output = $results | ForEach-Object -Parallel {
            $arch = if ($_.Source -eq 'msstore') { 'NA' } else { $using:DefaultArchitecture }
            [PSCustomObject]@{
                IsSelected               = [bool]$false
                Name                     = [string]$_.Name
                Id                       = [string]$_.Id
                Version                  = [string]$_.Version
                Source                   = [string]$_.Source
                Architecture             = [string]$arch
                AdditionalExitCodes      = [string]::Empty
                IgnoreNonZeroExitCodes   = [bool]$false
                DownloadStatus           = [string]::Empty
            }
        } -ThrottleLimit 20
        WriteLog "Winget search completed. Created $($output.Count) output objects."
        return $output
    }
    catch {
        WriteLog "Error during Winget search: $($_.Exception.Message)"
        # Return an empty array or throw, depending on desired UI policy
        return @()
    }
}

function Test-WingetCLI {
    [CmdletBinding()]
    param()
    
    $minVersion = [version]"1.8.1911"
    
    # Check Winget CLI
    $wingetCmd = Get-Command -Name winget -ErrorAction SilentlyContinue
    if (-not $wingetCmd) {
        return @{
            Version = "Not installed"
            Status  = "Not installed - Install from Microsoft Store"
        }
    }
    
    # Get and check version
    $wingetVersion = & winget.exe --version
    if ($wingetVersion -match 'v?(\d+\.\d+.\d+)') {
        $version = [version]$matches[1]
        if ($version -lt $minVersion) {
            return @{
                Version = $version.ToString()
                Status  = "Update required - Install from Microsoft Store"
            }
        }
        return @{
            Version = $version.ToString()
            Status  = $version.ToString()
        }
    }
    
    return @{
        Version = "Unknown"
        Status  = "Version check failed"
    }
}


function Install-WingetComponents {
    [CmdletBinding()]
    param(
        # Add parameter to accept a script block for UI updates
        [Parameter(Mandatory)]
        [scriptblock]$UiUpdateCallback
    )

    $minVersion = [version]"1.8.1911"
    $module = $null
    
    try {
        # Check and update PowerShell Module
        $module = Get-InstalledModule -Name Microsoft.WinGet.Client -ErrorAction SilentlyContinue
        if (-not $module -or $module.Version -lt $minVersion) {
            WriteLog "Winget module needs install/update. Attempting..."
            # Invoke the callback provided by the UI script to update status
            # Note: We don't have the CLI version readily available here, pass a placeholder or adjust if needed.
            & $UiUpdateCallback "Checking..." "Installing..." 

            # Store and modify PSGallery trust setting temporarily if needed
            $PSGalleryTrust = (Get-PSRepository -Name 'PSGallery').InstallationPolicy
            if ($PSGalleryTrust -eq 'Untrusted') {
                Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
            }

            # Install/Update the module
            Install-Module -Name Microsoft.WinGet.Client -Force -Repository 'PSGallery' -Scope AllUsers
            
            # Restore original PSGallery trust setting
            if ($PSGalleryTrust -eq 'Untrusted') {
                Set-PSRepository -Name 'PSGallery' -InstallationPolicy Untrusted
            }
            
            $module = Get-InstalledModule -Name Microsoft.WinGet.Client -ErrorAction Stop
        }
        
        return $module
    }
    catch {
        Write-Error "Failed to install/update Winget PowerShell module: $_"
        throw
    }
}

# Winget Module Check Function (UI Version)
# Performs checks, triggers install if needed, and reports status back to the UI.
function Confirm-WingetInstallationUI {
    [CmdletBinding()]
    param(
        # Callback for intermediate UI updates (e.g., "Installing...")
        [Parameter(Mandatory)]
        [scriptblock]$UiUpdateCallback 
    )
    
    $minVersion = [version]"1.8.1911"
    $result = [PSCustomObject]@{
        Success         = $false
        Message         = ""
        CliVersion      = "Unknown"
        ModuleVersion   = "Unknown"
        NeedsUpdate     = $false
        UpdateAttempted = $false
    }

    try {
        # Initial Check
        WriteLog "Confirm-WingetInstallationUI: Starting checks..."
        $cliStatus = Test-WingetCLI
        $module = @(Get-InstalledModule -Name Microsoft.WinGet.Client -ErrorAction SilentlyContinue) | Sort-Object -Top 1 -Descending Version -ErrorAction SilentlyContinue

        $result.CliVersion = $cliStatus.Version
        $result.ModuleVersion = if ($null -ne $module) { $module.Version.ToString() } else { "Not installed" }

        # Use callback for initial status display
        & $UiUpdateCallback $result.CliVersion $result.ModuleVersion

        # Determine if install/update is needed
        $needsCliUpdate = $cliStatus.Status -notmatch '^\d+\.\d+\.\d+$' -or ([version]$cliStatus.Version -lt $minVersion)
        $needsModuleUpdate = ($null -eq $module) -or ([version]$module.Version -lt $minVersion)
        $result.NeedsUpdate = $needsCliUpdate -or $needsModuleUpdate

        if ($result.NeedsUpdate) {
            WriteLog "Confirm-WingetInstallationUI: Update needed. CLI Needs Update: $needsCliUpdate, Module Needs Update: $needsModuleUpdate"
            $result.UpdateAttempted = $true
            
            # Use callback to indicate installation attempt
            & $UiUpdateCallback $result.CliVersion "Installing/Updating..."

            # Attempt to install/update Winget CLI and module
            $installedModule = Install-WingetComponents -UiUpdateCallback $UiUpdateCallback
            
            # Re-check status after attempt
            WriteLog "Confirm-WingetInstallationUI: Re-checking status after update attempt..."
            $cliStatus = Test-WingetCLI
            $result.CliVersion = $cliStatus.Version
            $result.ModuleVersion = if ($null -ne $installedModule) { $installedModule.Version } else { "Install Failed" }
            # Use callback for final status display after update attempt
            & $UiUpdateCallback $result.CliVersion $result.ModuleVersion

            # Check if update was successful
            $cliOk = $cliStatus.Status -match '^\d+\.\d+\.\d+$' -and ([version]$cliStatus.Version -ge $minVersion)
            $moduleOk = ($null -ne $installedModule) -and ([version]$installedModule.Version -ge $minVersion)
            $result.Success = $cliOk -and $moduleOk
            $result.Message = if ($result.Success) { "Winget components installed/updated successfully." } else { "Winget component installation/update failed or is incomplete." }
            WriteLog "Confirm-WingetInstallationUI: Update attempt finished. Success: $($result.Success). Message: $($result.Message)"
        }
        else {
            # Already up-to-date
            $result.Success = $true
            $result.Message = "Winget components are up-to-date."
            WriteLog "Confirm-WingetInstallationUI: Components already up-to-date."
        }
    }
    catch {
        $result.Success = $false
        $result.Message = "Error during Winget check/install: $($_.Exception.Message)"
        WriteLog "Confirm-WingetInstallationUI: Error - $($result.Message)"
        # Use callback to show error state
        & $UiUpdateCallback $result.CliVersion "Error"
    }

    return $result
}

# Note: Start-WingetAppDownloadTask has been moved to FFU.Common.Winget.psm1
# to enable code reuse between UI and CLI builds. It is imported via the FFU.Common module.

function Invoke-WingetDownload {
    param(
        [psobject]$State,
        [object]$Button
    )
    try {
        $selectedApps = $State.Controls.lstWingetResults.Items | Where-Object { $_.IsSelected }
        if (-not $selectedApps) {
            [System.Windows.MessageBox]::Show("No applications selected to download.", "Download Winget Apps", "OK", "Information")
            return
        }

        $Button.IsEnabled = $false
        $State.Controls.pbOverallProgress.Visibility = 'Visible'
        $State.Controls.pbOverallProgress.Value = 0
        $State.Controls.txtStatus.Text = "Starting Winget app downloads..."

        # Define necessary task-specific variables locally
        $localAppsPath = $State.Controls.txtApplicationPath.Text
        $localAppListJsonPath = $State.Controls.txtAppListJsonPath.Text
        $localWindowsArch = $State.Controls.cmbWindowsArch.SelectedItem
        $localOrchestrationPath = Join-Path -Path $State.Controls.txtApplicationPath.Text -ChildPath "Orchestration"

        # Create hashtable for task-specific arguments to pass to Invoke-ParallelProcessing
        # UI downloads skip WinGetWin32Apps.json creation - it's generated at build time
        $taskArguments = @{
            AppsPath            = $localAppsPath
            AppListJsonPath     = $localAppListJsonPath
            OrchestrationPath   = $localOrchestrationPath
            WindowsArch         = $localWindowsArch
            SkipWin32Json       = $true
        }

        # Select only necessary properties before passing to Invoke-ParallelProcessing
        $itemsToProcess = $selectedApps | Select-Object Name, Id, Source, Version, Architecture # Include Version and Architecture if needed

        # Before downloading, persist the selected apps to AppList.json including exit-code fields (parity with Save-WingetList)
        try {
            # Determine AppList.json path; default if empty
            if ([string]::IsNullOrWhiteSpace($localAppListJsonPath)) {
                $localAppListJsonPath = Join-Path -Path $localAppsPath -ChildPath "AppList.json"
                $taskArguments.AppListJsonPath = $localAppListJsonPath
                WriteLog "AppListJsonPath was empty. Defaulting to: $localAppListJsonPath"
            }

            # Build apps payload from current selection, preserving AdditionalExitCodes/IgnoreNonZeroExitCodes
            $appListToSave = @{
                apps = @($selectedApps | ForEach-Object {
                        [ordered]@{
                            name                   = (ConvertTo-SafeName -Name $_.Name)
                            id                     = $_.Id
                            source                 = $_.Source.ToLower()
                            architecture           = $_.Architecture
                            AdditionalExitCodes    = if ($_.PSObject.Properties['AdditionalExitCodes']) { $_.AdditionalExitCodes } else { "" }
                            IgnoreNonZeroExitCodes = if ($_.PSObject.Properties['IgnoreNonZeroExitCodes']) { [bool]$_.IgnoreNonZeroExitCodes } else { $false }
                        }
                    })
            }

            # Ensure destination directory exists and write AppList.json
            $destDir = Split-Path -Parent $localAppListJsonPath
            if (-not (Test-Path -LiteralPath $destDir)) {
                [void][System.IO.Directory]::CreateDirectory($destDir)
            }
            $appListToSave | ConvertTo-Json -Depth 10 | Set-Content -Path $localAppListJsonPath -Encoding UTF8
            WriteLog "Persisted AppList.json with selected apps and exit-code fields to: $localAppListJsonPath"
        }
        catch {
            WriteLog "Warning: Failed to persist AppList.json prior to download. Error: $($_.Exception.Message)"
        }

        # Invoke the centralized parallel processing function
        # Pass task type and task-specific arguments
        Invoke-ParallelProcessing -ItemsToProcess $itemsToProcess `
            -ListViewControl $State.Controls.lstWingetResults `
            -IdentifierProperty 'Id' `
            -StatusProperty 'DownloadStatus' `
            -TaskType 'WingetDownload' `
            -TaskArguments $taskArguments `
            -CompletedStatusText "Completed" `
            -ErrorStatusPrefix "Error: " `
            -WindowObject $State.Window `
            -MainThreadLogPath $State.LogFilePath `
            -ThrottleLimit $State.Controls.txtThreads.Text

        # Final status update is handled by Invoke-ParallelProcessing, but we need to re-enable the button
        $State.Controls.pbOverallProgress.Visibility = 'Collapsed'
        $Button.IsEnabled = $true
    }
    catch {
        WriteLog "FATAL Error in Invoke-WingetDownload: $($_.Exception.ToString())"
        [System.Windows.MessageBox]::Show("A critical error occurred while starting the Winget download: $($_.Exception.Message)", "Error", "OK", "Error")
        # Reset UI state on error
        if ($Button) { $Button.IsEnabled = $true }
        if ($State.Controls.pbOverallProgress) { $State.Controls.pbOverallProgress.Visibility = 'Collapsed' }
        if ($State.Controls.txtStatus) { $State.Controls.txtStatus.Text = "Winget download failed to start." }
    }
}

function Update-WingetVersionFields {
    param(
        [psobject]$State,
        [string]$wingetText,
        [string]$moduleText
    )
    $State.Window.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Normal, [Action] {
            $State.Controls.txtWingetVersion.Text = $wingetText
            $State.Controls.txtWingetModuleVersion.Text = $moduleText
            [System.Windows.Forms.Application]::DoEvents()
        })
}

Export-ModuleMember -Function *