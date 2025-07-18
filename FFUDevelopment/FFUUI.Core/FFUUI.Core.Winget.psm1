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

        # Search for new apps, which are streamed directly as PSCustomObjects
        # with the required properties for performance.
        $searchedAppResults = Search-WingetPackagesPublic -Query $searchQuery
        WriteLog "Found $($searchedAppResults.Count) apps matching query '$searchQuery'."

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

        # Update the ListView's ItemsSource using the passed-in State object
        $State.Controls.lstWingetResults.ItemsSource = $finalAppList.ToArray()
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

# --------------------------------------------------------------------------
# SECTION: Winget Management Functions (Moved from FFUUI.Core.psm1)
# --------------------------------------------------------------------------
function Search-WingetPackagesPublic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query
    )

    WriteLog "Searching Winget packages with query: '$Query'"
    try {
        # Stream results directly from Find-WinGetPackage and convert them to simple PSCustomObjects
        # on the fly using Select-Object with calculated properties. This is significantly faster
        # for large datasets as it avoids holding complex objects in memory and bypasses the
        # expensive formatting system for the raw results.
        Find-WinGetPackage -Query $Query -ErrorAction Stop |
        Select-Object -Property @{Name = 'IsSelected'; Expression = { $false } },
        Name,
        Id,
        Version,
        Source,
        @{Name = 'DownloadStatus'; Expression = { '' } }
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
            Install-Module -Name Microsoft.WinGet.Client -Force -Repository 'PSGallery'
            
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
        $module = Get-InstalledModule -Name Microsoft.WinGet.Client -ErrorAction SilentlyContinue

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
# Function to handle downloading a winget application (Modified for ForEach-Object -Parallel)
function Start-WingetAppDownloadTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$ApplicationItemData, # Pass data, not the UI object
        [Parameter(Mandatory = $true)]
        [string]$AppListJsonPath,
        [Parameter(Mandatory = $true)]
        [string]$AppsPath, # Pass necessary paths
        [Parameter(Mandatory = $true)]
        [string]$WindowsArch,
        [Parameter(Mandatory = $true)]
        [string]$OrchestrationPath,
        [Parameter(Mandatory = $true)]
        [System.Collections.Concurrent.ConcurrentQueue[hashtable]]$ProgressQueue # Add queue parameter
    )
        
    $appName = $ApplicationItemData.Name
    $appId = $ApplicationItemData.Id
    $source = $ApplicationItemData.Source
    $status = "Checking..." # Initial local status
    $resultCode = -1 # Default to error/unknown
    
    # Initial status update
    Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $appId -Status $status
    
    WriteLog "Starting download task for $($appName) with ID $($appId) from source $($source)."
    # WriteLog "Apps Path: $($AppsPath)"
    # WriteLog "AppList JSON Path: $($AppListJsonPath)"
    # WriteLog "Windows Architecture: $($WindowsArch)"
    # WriteLog "Orchestration Path: $($OrchestrationPath)"

    try {
        # Define paths
        $userAppListPath = Join-Path -Path $AppsPath -ChildPath "UserAppList.json"
        $appFound = $false # Flag to track if the app is found locally
        # WriteLog "UserAppList Path: $($userAppListPath)"
        # WriteLog "Checking for existing app in UserAppList.json and content folder."

        # 1. Check UserAppList.json and content
        if (Test-Path -Path $userAppListPath) {
            # WriteLog "UserAppList.json found at $($userAppListPath). Checking for app entry."
            try {
                $userAppListContent = Get-Content -Path $userAppListPath -Raw | ConvertFrom-Json
                $userAppEntry = $userAppListContent | Where-Object { $_.Name -eq $appName }

                if ($userAppEntry) {
                    $appFolder = Join-Path -Path "$AppsPath\Win32" -ChildPath $appName
                    if (Test-Path -Path $appFolder -PathType Container) {
                        $folderSize = (Get-ChildItem -Path $appFolder -Recurse | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                        if ($folderSize -gt 1MB) {
                            $appFound = $true
                            $status = "Not Downloaded: App in $userAppListPath and found in $appFolder"
                            Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $appId -Status $status
                            WriteLog "Found '$appName' in $userAppListPath and content exists in '$appFolder'."
                            return [PSCustomObject]@{ Id = $appId; Status = $status; ResultCode = 0 }
                        }
                        else {
                            $appFound = $true
                            $status = "Error: App in '$userAppListPath' but content missing/small in '$appFolder'. Copy content or remove from UserAppList.json."
                            Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $appId -Status $status
                            WriteLog $status
                            return [PSCustomObject]@{ Id = $appId; Status = $status; ResultCode = 1 }
                        }
                    }
                    else {
                        $appFound = $true
                        $status = "Error: App in '$userAppListPath' but content folder '$appFolder' not found. Copy content or remove from UserAppList.json."
                        Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $appId -Status $status
                        WriteLog $status
                        return [PSCustomObject]@{ Id = $appId; Status = $status; ResultCode = 1 }
                    }
                }
            }
            catch {
                WriteLog "Warning: Could not read or parse '$userAppListPath'. Error: $($_.Exception.Message)"
            }
        }

        # 2. Check previous Winget download
        if (-not $appFound) {
            if (-not $appFound) {
                $wingetWin32jsonFile = Join-Path -Path $OrchestrationPath -ChildPath "WinGetWin32Apps.json"
                if (Test-Path -Path $wingetWin32jsonFile) {
                    try {
                        $wingetAppsJson = Get-Content -Path $wingetWin32jsonFile -Raw | ConvertFrom-Json
                        # Check if app already exists in WinGetWin32Apps.json
                        $existingWin32Entry = $wingetAppsJson | Where-Object { $_.Name -eq $appName }
                        if ($existingWin32Entry) {
                            $appFolder = Join-Path -Path "$AppsPath\Win32" -ChildPath $appName
                            if (Test-Path -Path $appFolder -PathType Container) {
                                $folderSize = (Get-ChildItem -Path $appFolder -Recurse | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                                if ($folderSize -gt 1MB) {
                                    $appFound = $true
                                    $status = "Not Downloaded: App already in $wingetWin32jsonFile and found in $appFolder"
                                    Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $appId -Status $status
                                    WriteLog "Found '$appName' in WinGetWin32Apps.json and content exists in '$appFolder'. Skipping download to prevent duplicate entry."
                                    return [PSCustomObject]@{ Id = $appId; Status = $status; ResultCode = 0 }
                                }
                            }
                            else {
                                # App entry exists in WinGetWin32Apps.json but folder is missing
                                $appFound = $true
                                $status = "Error: App in '$wingetWin32jsonFile' but content folder '$appFolder' not found. Remove entry from WinGetWin32Apps.json or restore content."
                                Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $appId -Status $status
                                WriteLog $status
                                return [PSCustomObject]@{ Id = $appId; Status = $status; ResultCode = 1 }
                            }
                        }
                    }
                    catch {
                        WriteLog "Warning: Could not read or parse '$wingetWin32jsonFile'. Error: $($_.Exception.Message)"
                    }
                }
            }
            # For now, assuming Get-Application uses $global variables set in the main script or $using: scope.
            # $global:AppsPath = $AppsPath # Potentially redundant if set globally before parallel call
            # $global:WindowsArch = $WindowsArch # Potentially redundant
            # $global:orchestrationPath = $OrchestrationPath # Potentially redundant

            $wingetWin32jsonFile = Join-Path -Path $OrchestrationPath -ChildPath "WinGetWin32Apps.json"
            if (Test-Path -Path $wingetWin32jsonFile) {
                try {
                    $wingetAppsJson = Get-Content -Path $wingetWin32jsonFile -Raw | ConvertFrom-Json
                    $wingetApp = $wingetAppsJson | Where-Object { $_.Name -eq $appName }
                    if ($wingetApp) {
                        $appFolder = Join-Path -Path "$AppsPath\Win32" -ChildPath $appName
                        if (Test-Path -Path $appFolder -PathType Container) {
                            $folderSize = (Get-ChildItem -Path $appFolder -Recurse | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                            if ($folderSize -gt 1MB) {
                                $appFound = $true
                                $status = "Not Downloaded: App in $wingetWin32jsonFile and found in $appFolder"
                                Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $appId -Status $status
                                WriteLog "Found '$appName' via WinGetWin32Apps.json and content exists in '$appFolder'."
                                return [PSCustomObject]@{ Id = $appId; Status = $status; ResultCode = 0 }
                            }
                        }
                    }
                }
                catch {
                    WriteLog "Warning: Could not read or parse '$wingetWin32jsonFile'. Error: $($_.Exception.Message)"
                }
            }
        }

        # Check MSStore folder
        if (-not $appFound -and (Test-Path -Path "$AppsPath\MSStore" -PathType Container)) {
            $appFolder = Join-Path -Path "$AppsPath\MSStore" -ChildPath $appName
            if (Test-Path -Path $appFolder -PathType Container) {
                $folderSize = (Get-ChildItem -Path $appFolder -Recurse | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                if ($folderSize -gt 1MB) {
                    $appFound = $true
                    $status = "Already downloaded (MSStore)"
                    Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $appId -Status $status
                    WriteLog "Found '$appName' content in '$appFolder'."
                    return [PSCustomObject]@{ Id = $appId; Status = $status; ResultCode = 0 }
                }
            }
        }

        # 3. If not found locally, add to AppList.json and download
        if (-not $appFound) {
            # Add to AppList.json
            $appListContent = $null
            $appListDir = Split-Path -Path $AppListJsonPath -Parent
            if (-not (Test-Path -Path $appListDir -PathType Container)) {
                New-Item -Path $appListDir -ItemType Directory -Force | Out-Null
            }
            if (Test-Path -Path $AppListJsonPath) {
                try {
                    $appListContent = Get-Content -Path $AppListJsonPath -Raw | ConvertFrom-Json
                    if (-not $appListContent.PSObject.Properties['apps']) {
                        $appListContent = @{ apps = @() }
                    }
                }
                catch {
                    WriteLog "Warning: Could not read or parse '$AppListJsonPath'. Creating new structure. Error: $($_.Exception.Message)"
                    $appListContent = @{ apps = @() }
                }
            }
            else {
                $appListContent = @{ apps = @() }
            }

            $appExistsInAppList = $false
            if ($appListContent.apps) {
                foreach ($app in $appListContent.apps) {
                    if ($app.id -eq $appId) {
                        $appExistsInAppList = $true
                        break
                    }
                }
            }

            if (-not $appExistsInAppList) {
                $newApp = @{ name = $appName; id = $appId; source = $source }
                if (-not ($appListContent.apps -is [array])) { $appListContent.apps = @() }
                $appListContent.apps += $newApp
                try {
                    # Use a lock to prevent race conditions when writing to the same file
                    $lockName = "AppListJsonLock"
                    $lock = New-Object System.Threading.Mutex($false, $lockName)
                    try {
                        $lock.WaitOne() | Out-Null
                        # Re-read content inside lock to ensure latest version
                        if (Test-Path -Path $AppListJsonPath) {
                            $currentAppListContent = Get-Content -Path $AppListJsonPath -Raw | ConvertFrom-Json
                            if (-not ($currentAppListContent.apps | Where-Object { $_.id -eq $appId })) {
                                $currentAppListContent.apps += $newApp
                                $currentAppListContent | ConvertTo-Json -Depth 10 | Set-Content -Path $AppListJsonPath -Encoding UTF8
                                WriteLog "Added '$appName' to '$AppListJsonPath'."
                            }
                            else {
                                WriteLog "'$appName' already exists in '$AppListJsonPath' (checked inside lock)."
                            }
                        }
                        else {
                            # File doesn't exist, write the initial content
                            $appListContent | ConvertTo-Json -Depth 10 | Set-Content -Path $AppListJsonPath -Encoding UTF8
                            WriteLog "Created '$AppListJsonPath' and added '$appName'."
                        }
                    }
                    finally {
                        $lock.ReleaseMutex()
                        $lock.Dispose()
                    }
                }
                catch {
                    WriteLog "Error saving '$AppListJsonPath'. Error: $($_.Exception.Message)"
                    $status = "Error saving AppList.json"
                    Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $appId -Status $status
                    return [PSCustomObject]@{ Id = $appId; Status = $status; ResultCode = 1 }
                }
            }
            else {
                WriteLog "'$appName' already exists in '$AppListJsonPath'."
            }

            # Proceed with download
            $status = "Downloading..."
            Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $appId -Status $status

            # Ensure variables needed by Get-Application are accessible
            # (Assuming they are available via $using: scope or global scope from main script)
            # $global:AppsPath = $AppsPath # Potentially redundant
            # $global:WindowsArch = $WindowsArch # Potentially redundant
            # $global:orchestrationPath = $OrchestrationPath # Potentially redundant"
            WriteLog "Orchestration Path: $($OrchestrationPath)"
            if (-not (Test-Path -Path $OrchestrationPath -PathType Container)) {
                New-Item -Path $OrchestrationPath -ItemType Directory -Force | Out-Null
            }
            $win32Folder = Join-Path -Path $AppsPath -ChildPath "Win32"
            if ($source -eq "winget" -and -not (Test-Path -Path $win32Folder -PathType Container)) {
                New-Item -Path $win32Folder -ItemType Directory -Force | Out-Null
            }
            $storeAppsFolder = Join-Path -Path $AppsPath -ChildPath "MSStore"
            if ($source -eq "msstore" -and -not (Test-Path -Path $storeAppsFolder -PathType Container)) {
                New-Item -Path $storeAppsFolder -ItemType Directory -Force | Out-Null
            }

            try {
                # Call Get-Application (ensure it's available via dot-sourcing and uses $global:LogFile)
                $resultCode = Get-Application -AppName $appName -AppId $appId -Source $source -ErrorAction Stop

                # Determine status based on result code
                switch ($resultCode) {
                    0 { $status = "Downloaded successfully" }
                    1 { $status = "Error: No win32 app installers were found" }
                    2 { $status = "Silent install switch could not be found. Did not download." }
                    default { $status = "Downloaded with status: $resultCode" } # Should not happen with current Get-Application
                }

                # Remove app from AppList.json if silent install switch could not be found (resultCode 2)
                if ($resultCode -eq 2) {
                    try {
                        if (Test-Path -Path $AppListJsonPath) {
                            $appListContent = Get-Content -Path $AppListJsonPath -Raw | ConvertFrom-Json
                            if ($appListContent.apps) {
                                $filteredApps = @($appListContent.apps | Where-Object { $_.id -ne $appId })
                                $appListContent.apps = $filteredApps
                                $appListContent | ConvertTo-Json -Depth 10 | Set-Content -Path $AppListJsonPath -Encoding UTF8
                                WriteLog "Removed '$appName' ($appId) from '$AppListJsonPath' due to missing silent install switch."
                            }
                        }
                    }
                    catch {
                        WriteLog "Failed to remove '$appName' from '$AppListJsonPath': $($_.Exception.Message)"
                    }
                }
            }
            catch {
                $status = "Error: $($_.Exception.Message)"
                WriteLog "Download error for $($appName): $($_.Exception.Message)"
                $resultCode = 1 # Indicate error
                # Enqueue error status
                Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $appId -Status $status
                
                # Remove app from AppList.json if publisher does not support download
                if ($_.Exception.Message -match "does not support downloads by the publisher") {
                    try {
                        if (Test-Path -Path $AppListJsonPath) {
                            $appListContent = Get-Content -Path $AppListJsonPath -Raw | ConvertFrom-Json
                            if ($appListContent.apps) {
                                $filteredApps = @($appListContent.apps | Where-Object { $_.id -ne $appId })
                                $appListContent.apps = $filteredApps
                                $appListContent | ConvertTo-Json -Depth 10 | Set-Content -Path $AppListJsonPath -Encoding UTF8
                                WriteLog "Removed '$appName' ($appId) from '$AppListJsonPath' due to publisher download restriction."
                            }
                        }
                    }
                    catch {
                        WriteLog "Failed to remove '$appName' from '$AppListJsonPath': $($_.Exception.Message)"
                    }
                }
            
            }
        } # End if (-not $appFound)
            
    }
    catch {
        $status = "Error: $($_.Exception.Message)"
        WriteLog "Unexpected error in Start-WingetAppDownloadTask for $($appName): $($_.Exception.Message)"
        $resultCode = 1 # Indicate error
        # Enqueue error status
        Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $appId -Status $status
    }
    finally {
        # Ensure status is not empty before returning
        if ([string]::IsNullOrEmpty($status)) {
            $status = "Error: Unknown failure" # Provide a default error status
            WriteLog "Status was empty for $appName ($appId), setting to default error."
            if ($resultCode -ne 0 -and $resultCode -ne 1 -and $resultCode -ne 2) {
                $resultCode = -1 # Ensure resultCode reflects an error if it was empty
            }
            # Enqueue the final (error) status if it was previously empty
            Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $appId -Status $status
        }
        elseif ($resultCode -ne 0) {
            # Enqueue the final status if it's an error (already set in try/catch)
            Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $appId -Status $status
        }
        else {
            # Enqueue the final success status
            Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $appId -Status $status
        }
    }
            
    # Prepare the return object as a Hashtable
    $returnObject = @{ Id = $appId; Status = $status; ResultCode = $resultCode }
            
    # Return the final status and result code as a Hashtable
    return $returnObject
}

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