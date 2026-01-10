<#
.SYNOPSIS
    Provides functions for interacting with WinGet and the Microsoft Store to find, download, and configure applications.

.DESCRIPTION
    This module contains a set of functions designed to automate application management using the WinGet package manager and the Microsoft Store. 
    It supports checking for and installing WinGet, downloading applications, handling different application types (Win32 and UWP), and generating silent installation commands for Win32 applications. 
    This module is used by both the build script (BuildFFUVM.ps1) and the UI (BuildFFUVM_UI.ps1) to manage application downloads and configuration.
#>
function Get-Application {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$AppName,
        [Parameter(Mandatory = $true)]
        [string]$AppId,
        [Parameter(Mandatory = $true)]
        [ValidateSet('winget', 'msstore')]
        [string]$Source,
        [Parameter(Mandatory = $true)]
        [string]$AppsPath,
        [Parameter(Mandatory = $true)]
        [string]$ApplicationArch,
        [string]$WindowsArch,
        [Parameter(Mandatory = $true)]
        [string]$OrchestrationPath,
        [switch]$SkipWin32Json
    )

    # Block Company Portal from winget source
    # I refuse to code around the poor packaging of this app
    if ($AppId -eq 'Microsoft.CompanyPortal' -and $Source -eq 'winget') {
        WriteLog "Skipping download of Company Portal from the 'winget' source. This version has packaging inconsistencies. Please use the 'msstore' source instead."
        return 4 # Return specific error code for this case
    }

    # Determine base folder path for checking existence
    $appIsWin32ForCheck = ($Source -eq 'msstore' -and $AppId.StartsWith("XP"))
    $appBaseFolderPathForCheck = ""
    if ($Source -eq 'winget' -or $appIsWin32ForCheck) {
        $appBaseFolderPathForCheck = Join-Path -Path "$AppsPath\Win32" -ChildPath $AppName
    }
    else {
        $appBaseFolderPathForCheck = Join-Path -Path "$AppsPath\MSStore" -ChildPath $AppName
    }

    # Check if the app (any architecture) has already been downloaded by checking for its content folder.
    # This prevents re-downloading if BuildFFUVM.ps1 is run after downloading via the UI.
    if (Test-Path -Path $appBaseFolderPathForCheck -PathType Container) {
        # Check if the folder is not empty.
        if (Get-ChildItem -Path $appBaseFolderPathForCheck -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1) {
            WriteLog "Application '$AppName' appears to be already downloaded as content exists in '$appBaseFolderPathForCheck'. Skipping download."
            
            # Add silent install command(s) only if not skipping JSON generation (build-time scenario)
            $appIsWin32Existing = ($Source -eq 'winget' -or ($Source -eq 'msstore' -and $AppId.StartsWith('XP')))
            if ($appIsWin32Existing -and -not $SkipWin32Json) {
                $win32BasePath = Join-Path -Path "$AppsPath\Win32" -ChildPath $AppName
                if (Test-Path -Path $win32BasePath -PathType Container) {
                    $archFolders = Get-ChildItem -Path $win32BasePath -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -in @('x86', 'x64', 'arm64') }
                    if ($archFolders) {
                        foreach ($archFolder in $archFolders) {
                            WriteLog "Adding silent install command for pre-downloaded $AppName ($($archFolder.Name)) to $OrchestrationPath\WinGetWin32Apps.json"
                            Add-Win32SilentInstallCommand -AppFolder $AppName -AppFolderPath $archFolder.FullName -OrchestrationPath $OrchestrationPath -SubFolder $archFolder.Name | Out-Null
                        }
                    }
                    else {
                        WriteLog "Adding silent install command for pre-downloaded $AppName to $OrchestrationPath\WinGetWin32Apps.json"
                        Add-Win32SilentInstallCommand -AppFolder $AppName -AppFolderPath $win32BasePath -OrchestrationPath $OrchestrationPath | Out-Null
                    }
                }
            }
            elseif ($appIsWin32Existing -and $SkipWin32Json) {
                WriteLog "Skipping WinGetWin32Apps.json regeneration for pre-downloaded $AppName (UI mode)."
            }
            
            return 0 # Success, already present
        }
    }
    
    # Validate app exists in repository
    $wingetSearchResult = Find-WinGetPackage -id $AppId -MatchOption Equals -Source $Source
    if (-not $wingetSearchResult) {
        if ($VerbosePreference -ne 'Continue') {
            Write-Error "$AppName not found in $Source repository."
            Write-Error "Check the AppList.json file and make sure the AppID is correct."
        }
        WriteLog "$AppName not found in $Source repository."
        WriteLog "Check the AppList.json file and make sure the AppID is correct."
        return 1 # Return error code
    }

    # Determine architectures to download (ApplicationArch controls download set; WindowsArch (optional) used later for pruning store installers)
    $architecturesToDownload = if ($ApplicationArch -eq 'x86 x64') { @('x86', 'x64') } else { @($ApplicationArch) }
    $overallResult = 0

    # For msstore, we don't specify architecture, so we only need to loop once.
    if ($Source -eq 'msstore') {
        $architecturesToDownload = @('neutral') # Use a placeholder to loop once
    }

    foreach ($arch in $architecturesToDownload) {
        if ($Source -eq 'msstore') {
            WriteLog "Processing '$AppName' for all architectures."
        }
        else {
            WriteLog "Processing '$AppName' for architecture '$arch'."
        }

        # Determine app type and folder path
        $appIsWin32 = ($Source -eq 'msstore' -and $AppId.StartsWith("XP"))
        $sanitizedAppName = ConvertTo-SafeName -Name $AppName
        if ($sanitizedAppName -ne $AppName) { WriteLog "Sanitized app name: '$AppName' -> '$sanitizedAppName'" }
        if ($Source -eq 'winget' -or $appIsWin32) {
            $appBaseFolderPath = Join-Path -Path "$AppsPath\Win32" -ChildPath $sanitizedAppName
        }
        else {
            $appBaseFolderPath = Join-Path -Path "$AppsPath\MSStore" -ChildPath $sanitizedAppName
        }
        
        # If downloading multiple archs for a Win32 app, create a subfolder
        $appFolderPath = $appBaseFolderPath
        $subFolderForCommand = $null
        if ($architecturesToDownload.Count -gt 1 -and ($Source -eq 'winget' -or $appIsWin32)) {
            $appFolderPath = Join-Path -Path $appBaseFolderPath -ChildPath $arch
            $subFolderForCommand = $arch
        }

        # Create app folder
        New-Item -Path $appFolderPath -ItemType Directory -Force | Out-Null
        
        # Build download parameters and log information
        $downloadParams = @{
            id                = $AppId
            DownloadDirectory = $appFolderPath
            Source            = $Source
        }
        
        if ($Source -ne 'msstore') {
            $downloadParams.Architecture = $arch
            WriteLog "Downloading $AppName for $arch architecture..."
            WriteLog "WinGet command: Export-WinGetPackage -id $AppId -DownloadDirectory `"$appFolderPath`" -Architecture $arch -Source $Source"
        }
        else {
            WriteLog "Downloading $AppName for all architectures..."
            WriteLog 'MSStore app downloads require authentication with an Entra ID account. You may be prompted twice for credentials, once for the app and another for the license file.'
            WriteLog "WinGet command: Export-WinGetPackage -id $AppId -DownloadDirectory `"$appFolderPath`" -Source $Source"
        }
        
        # Download the app
        $wingetDownloadResult = Export-WinGetPackage @downloadParams
        
        # Handle download status
        if ($wingetDownloadResult.status -ne 'Ok') {
            # For winget source, try downloading without architecture if the specified one fails
            if (($Source -eq 'winget') -and ($wingetDownloadResult.status -eq 'NoApplicableInstallers' -or $wingetDownloadResult.status -eq 'NoApplicableInstallerFound')) {
                WriteLog "No installer found for $arch architecture. Attempting to download without specifying architecture..."
                # Remove the architecture parameter and try again
                $downloadParams.Remove('Architecture')
                $wingetDownloadResult = Export-WinGetPackage @downloadParams
            }

            # Re-evaluate status after potential second attempt
            if ($wingetDownloadResult.status -ne 'Ok') {
                # Handle Store-specific publisher restriction error
                if ($Source -eq 'msstore' -and $wingetDownloadResult.ExtendedErrorCode -match '0x8A150084') {
                    $errorMessage = "The Microsoft Store app $AppName does not support downloads by the publisher. Please remove it from the AppList.json. If there's a winget source version of the application, try using that instead. Exiting."
                    WriteLog $errorMessage
                    Remove-Item -Path $appFolderPath -Recurse -Force
                    Write-Error $errorMessage
                    return 3 # Return specific error code for publisher restriction
                }
                # Handle other download failures
                else {
                    $errormsg = "Download failed for $AppName with status: $($wingetDownloadResult.status) $($wingetDownloadResult.ExtendedErrorCode)"
                    WriteLog $errormsg
                    Remove-Item -Path $appFolderPath -Recurse -Force
                    Write-Error $errormsg
                    return 1 # Return generic error code
                }
            }
            else {
                WriteLog "Downloaded $AppName without specifying architecture."
            }
        }
        
        WriteLog "$AppName ($arch) downloaded to $appFolderPath"

        # Handle zip files
        $zipFile = Get-ChildItem -Path $appFolderPath -Filter "*.zip" -File -ErrorAction SilentlyContinue
        if ($zipFile) {
            WriteLog "Found zip file: $($zipFile.FullName). Extracting..."
            Expand-Archive -Path $zipFile.FullName -DestinationPath $appFolderPath -Force
            WriteLog "Extraction complete. Removing zip file."
            Remove-Item -Path $zipFile.FullName -Force
            WriteLog "Zip file removed."
        }
        
        # Handle winget source apps that have appx, appxbundle, msix, or msixbundle extensions but were downloaded to the Win32 folder
        $installerFiles = Get-ChildItem -Path "$appFolderPath\*" -Exclude "*.yaml", "*.xml" -File -ErrorAction SilentlyContinue
        $uwpExtensions = @(".appx", ".appxbundle", ".msix", ".msixbundle")
        $isUwpApp = $false
        if ($installerFiles) {
            foreach ($file in $installerFiles) {
                if ($uwpExtensions -contains $file.Extension) {
                    $isUwpApp = $true
                    break
                }
            }
        }
        
        if ($isUwpApp -and $appFolderPath -match 'Win32') {
            # Handle UWP apps
            $NewAppPath = "$AppsPath\MSStore\$AppName"
            WriteLog "$AppName is a UWP app. Moving to $NewAppPath"
            WriteLog "Creating $NewAppPath"
            New-Item -Path "$AppsPath\MSStore\$AppName" -ItemType Directory -Force | Out-Null
            WriteLog "Moving $AppName to $NewAppPath"
            Move-Item -Path "$appFolderPath\*" -Destination "$AppsPath\MSStore\$AppName" -Force
            WriteLog "Removing $appFolderPath"
            Remove-Item -Path $appFolderPath -Force -Recurse
            WriteLog "$AppName moved to $NewAppPath"
            $result = 0  # Success for UWP app
        }
        # If app is in Win32 folder, add the silent install command to the WinGetWin32Apps.json file
        elseif ($appFolderPath -match 'Win32') {
            if (-not $SkipWin32Json) {
                WriteLog "$AppName is a Win32 app. Adding silent install command to $OrchestrationPath\WinGetWin32Apps.json"
                $result = Add-Win32SilentInstallCommand -AppFolder $AppName -AppFolderPath $appFolderPath -OrchestrationPath $OrchestrationPath -SubFolder $subFolderForCommand
            }
            else {
                WriteLog "$AppName is a Win32 app. Skipping WinGetWin32Apps.json generation (UI mode)."
                $result = 0
            }
        }
        else {
            # For any other case, set result to 0 (success)
            $result = 0
        }
        
        if ($result -ne 0) { $overallResult = $result }

        # Handle MSStore specific post-processing
        if ($Source -eq 'msstore' -and $appFolderPath -match 'MSStore') {
            # Handle ARM64-specific dependencies
            if ($arch -eq 'ARM64') {
                WriteLog 'Windows architecture is ARM64. Removing dependencies that are not ARM64.'
                $dependencies = Get-ChildItem -Path "$appFolderPath\Dependencies" -ErrorAction SilentlyContinue
                if ($dependencies) {
                    foreach ($dependency in $dependencies) {
                        if ($dependency.Name -notmatch 'ARM64') {
                            WriteLog "Removing dependency file $($dependency.FullName)"
                            Remove-Item -Path $dependency.FullName -Recurse -Force
                        }
                    }
                }
            }
            
            # Clean up multiple versions honoring WindowsArch (pruning target; keep only one installer)
            WriteLog "$AppName has completed downloading. Evaluating installer set for pruning."
            $packages = Get-ChildItem -Path "$appFolderPath\*" -Exclude "Dependencies\*", "*.xml", "*.yaml" -File -ErrorAction Stop
            if ($packages.Count -gt 1 -and $WindowsArch) {
                WriteLog "WindowsArch pruning target provided: $WindowsArch"
                # Detect universal bundles (contain x86,x64,arm64 in name)
                $universalCandidates = $packages | Where-Object {
                    $base = $_.BaseName
                    # Split base name into tokens to avoid partial matches (e.g. arm inside arm64)
                    $tokens = ($base -split '[\.\-_]') | ForEach-Object { $_.ToLower() }
                    # Architecture tokens we recognize
                    $archTokens = @('x86', 'x64', 'arm', 'arm64')
                    # Distinct matched architecture tokens
                    $matched = $tokens | Where-Object { $_ -in $archTokens } | Select-Object -Unique
                    if ($matched.Count -ge 2) {
                        WriteLog "Multi-architecture bundle detected: $base (tokens: $($matched -join ', '))"
                        $true
                    }
                    else {
                        $false
                    }
                }
                if ($universalCandidates) {
                    WriteLog "Universal bundle candidate(s) detected: $($universalCandidates.Name -join ', ')"
                    $candidateSet = $universalCandidates
                }
                else {
                    $archToken = switch -Regex ($WindowsArch.ToLower()) {
                        '^x64$' { 'x64' ; break }
                        '^x86$' { 'x86' ; break }
                        '^arm64$' { 'arm64' ; break }
                        default { $WindowsArch.ToLower() }
                    }
                    $archMatches = $packages | Where-Object { $_.BaseName -match "(?i)$archToken" }
                    if ($archMatches) {
                        WriteLog "Architecture-specific candidates matching '$archToken': $($archMatches.Name -join ', ')"
                        $candidateSet = $archMatches
                    }
                    else {
                        WriteLog "No installer filename matched '$archToken'. Falling back to all installers."
                        $candidateSet = $packages
                    }
                }
                # From candidate set, choose latest by signature date
                $latestPackage = $candidateSet | Sort-Object { (Get-AuthenticodeSignature $_.FullName).SignerCertificate.NotBefore } -Descending | Select-Object -First 1
                WriteLog "Retaining installer: $($latestPackage.Name)"
                foreach ($package in $packages) {
                    if ($package.FullName -ne $latestPackage.FullName) {
                        try {
                            WriteLog "Removing $($package.FullName)"
                            Remove-Item -Path $package.FullName -Force
                        }
                        catch {
                            WriteLog "Failed to delete: $($package.FullName) - $_"
                            throw $_
                        }
                    }
                }
            }
            elseif ($packages.Count -gt 1) {
                WriteLog "Multiple installers present but no WindowsArch pruning target supplied. Using original latest-version logic."
                $latestPackage = $packages | Sort-Object { (Get-AuthenticodeSignature $_.FullName).SignerCertificate.NotBefore } -Descending | Select-Object -First 1
                WriteLog "Retaining latest by signature date: $($latestPackage.Name)"
                foreach ($package in $packages) {
                    if ($package.FullName -ne $latestPackage.FullName) {
                        try {
                            WriteLog "Removing $($package.FullName)"
                            Remove-Item -Path $package.FullName -Force
                        }
                        catch {
                            WriteLog "Failed to delete: $($package.FullName) - $_"
                            throw $_
                        }
                    }
                }
            }
            else {
                WriteLog "Single installer present; no pruning required."
            }
        }
    } # End foreach ($arch in $architecturesToDownload)
    
    return $overallResult
}
# Function to handle downloading a winget application in parallel
# This function is called by Invoke-ParallelProcessing for each app
function Start-WingetAppDownloadTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$ApplicationItemData,
        [Parameter(Mandatory = $true)]
        [string]$AppListJsonPath,
        [Parameter(Mandatory = $true)]
        [string]$AppsPath,
        [Parameter(Mandatory = $true)]
        [string]$OrchestrationPath,
        [Parameter(Mandatory = $true)]
        [System.Collections.Concurrent.ConcurrentQueue[hashtable]]$ProgressQueue,
        [string]$WindowsArch,
        [switch]$SkipWin32Json
    )
        
    $appName = $ApplicationItemData.Name
    $appId = $ApplicationItemData.Id
    $source = $ApplicationItemData.Source
    $status = "Checking..."
    $resultCode = -1
    $sanitizedAppName = ConvertTo-SafeName -Name $appName
    
    # Initial status update
    Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $appId -Status $status
    
    WriteLog "Starting download task for $($appName) with ID $($appId) from source $($source)."

    try {
        # Define paths
        $userAppListPath = Join-Path -Path $AppsPath -ChildPath "UserAppList.json"
        $appFound = $false

        # 1. Check UserAppList.json and content
        if (Test-Path -Path $userAppListPath) {
            try {
                $userAppListContent = Get-Content -Path $userAppListPath -Raw | ConvertFrom-Json
                $userAppEntry = $userAppListContent | Where-Object { $_.Name -eq $appName }

                if ($userAppEntry) {
                    $appFolder = Join-Path -Path "$AppsPath\Win32" -ChildPath $sanitizedAppName
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
                            $status = "App in '$userAppListPath' but content missing/small in '$appFolder'. Copy content or remove from UserAppList.json."
                            Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $appId -Status $status
                            WriteLog $status
                            return [PSCustomObject]@{ Id = $appId; Status = $status; ResultCode = 1 }
                        }
                    }
                    else {
                        $appFound = $true
                        $status = "App in '$userAppListPath' but content folder '$appFolder' not found. Copy content or remove from UserAppList.json."
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

        # 2. Check existing downloaded Win32 content (folder-based)
        if (-not $appFound -and $source -eq 'winget') {
            $appFolder = Join-Path -Path "$AppsPath\Win32" -ChildPath $sanitizedAppName
            if (Test-Path -Path $appFolder -PathType Container) {
                $contentFound = $false
                if ($ApplicationItemData.Architecture -eq 'x86 x64') {
                    $x86Folder = Join-Path -Path $appFolder -ChildPath "x86"
                    $x64Folder = Join-Path -Path $appFolder -ChildPath "x64"
                    if ((Test-Path -Path $x86Folder -PathType Container) -and (Test-Path -Path $x64Folder -PathType Container)) {
                        $x86Size = (Get-ChildItem -Path $x86Folder -Recurse | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                        $x64Size = (Get-ChildItem -Path $x64Folder -Recurse | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                        if ($x86Size -gt 1MB -and $x64Size -gt 1MB) {
                            $contentFound = $true
                        }
                    }
                }
                else {
                    $folderSize = (Get-ChildItem -Path $appFolder -Recurse | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                    if ($folderSize -gt 1MB) {
                        $contentFound = $true
                    }
                }
                if ($contentFound) {
                    $appFound = $true
                    $status = "Not Downloaded: Existing content found in $appFolder"
                    Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $appId -Status $status
                    WriteLog "Found existing content for '$appName' in '$appFolder'. Skipping download to prevent duplicate entry."

                    # Regenerate WinGetWin32Apps.json for CLI builds when content already exists
                    # UI mode pre-downloads should not generate this file (SkipWin32Json)
                    if (-not $SkipWin32Json) {
                        $archFolders = Get-ChildItem -Path $appFolder -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -in @('x86', 'x64', 'arm64') }
                        if ($archFolders) {
                            foreach ($archFolder in $archFolders) {
                                WriteLog "Adding silent install command for pre-downloaded $sanitizedAppName ($($archFolder.Name)) to $OrchestrationPath\WinGetWin32Apps.json"
                                Add-Win32SilentInstallCommand -AppFolder $sanitizedAppName -AppFolderPath $archFolder.FullName -OrchestrationPath $OrchestrationPath -SubFolder $archFolder.Name | Out-Null
                            }
                        }
                        else {
                            WriteLog "Adding silent install command for pre-downloaded $sanitizedAppName to $OrchestrationPath\WinGetWin32Apps.json"
                            Add-Win32SilentInstallCommand -AppFolder $sanitizedAppName -AppFolderPath $appFolder -OrchestrationPath $OrchestrationPath | Out-Null
                        }
                    }
                    else {
                        WriteLog "Skipping WinGetWin32Apps.json regeneration for pre-downloaded $sanitizedAppName (UI mode)."
                    }

                    return [PSCustomObject]@{ Id = $appId; Status = $status; ResultCode = 0 }
                }
            }
        }

        # Check MSStore folder
        if (-not $appFound -and (Test-Path -Path "$AppsPath\MSStore" -PathType Container)) {
            $appFolder = Join-Path -Path "$AppsPath\MSStore" -ChildPath $sanitizedAppName
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
            # Add to AppList.json with mutex lock for thread safety
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
                $newApp = @{ name = $sanitizedAppName; id = $appId; source = $source }
                if (-not ($appListContent.apps -is [array])) { $appListContent.apps = @() }
                $appListContent.apps += $newApp
                try {
                    # Use a mutex lock to prevent race conditions when writing to the same file
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
                    $status = "Failed to save AppList.json: $($_.Exception.Message)"
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

            # Ensure necessary folders exist
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
                # Call Get-Application to perform the actual download
                # Pass SkipWin32Json based on caller context (UI mode skips, CLI mode creates)
                $getAppParams = @{
                    AppName          = $appName
                    AppId            = $appId
                    Source           = $source
                    AppsPath         = $AppsPath
                    ApplicationArch  = $ApplicationItemData.Architecture
                    WindowsArch      = $WindowsArch
                    OrchestrationPath = $OrchestrationPath
                    ErrorAction      = 'Stop'
                }
                if ($SkipWin32Json) {
                    $getAppParams['SkipWin32Json'] = $true
                }
                $resultCode = Get-Application @getAppParams

                # Determine status based on result code
                switch ($resultCode) {
                    0 { $status = "Downloaded successfully" }
                    1 { $status = "Error: No app installers were found" }
                    2 { $status = "Silent install switch could not be found. Did not download." }
                    3 { $status = "Error: Publisher does not support download" }
                    4 { $status = "Skipped: Use 'msstore' source instead." }
                    default { $status = "Downloaded with status: $resultCode" }
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
                $status = $_.Exception.Message
                WriteLog "Download error for $($appName): $($_.Exception.Message)"
                $resultCode = 1
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
        }
    }
    catch {
        $status = $_.Exception.Message
        WriteLog "Unexpected error in Start-WingetAppDownloadTask for $($appName): $($_.Exception.Message)"
        $resultCode = 1
        Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $appId -Status $status
    }
    finally {
        # Ensure status is not empty before returning
        if ([string]::IsNullOrEmpty($status)) {
            $status = "Unknown failure"
            WriteLog "Status was empty for $appName ($appId), setting to default error."
            if ($resultCode -ne 0 -and $resultCode -ne 1 -and $resultCode -ne 2) {
                $resultCode = -1
            }
            Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $appId -Status $status
        }
        elseif ($resultCode -ne 0) {
            Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $appId -Status $status
        }
        else {
            Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $appId -Status $status
        }
    }
            
    # Return the final status and result code
    return @{ Id = $appId; Status = $status; ResultCode = $resultCode }
}

function Get-Apps {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$AppList,
        [Parameter(Mandatory = $true)]
        [string]$AppsPath,
        [Parameter(Mandatory = $true)]
        [string]$WindowsArch,
        [Parameter(Mandatory = $true)]
        [string]$OrchestrationPath,
        [Parameter(Mandatory = $false)]
        [string]$LogFilePath,
        [Parameter(Mandatory = $false)]
        [int]$ThrottleLimit = 5
    )
    
    # Load and validate app list
    $apps = Get-Content -Path $AppList -Raw | ConvertFrom-Json
    if (-not $apps -or -not $apps.apps -or $apps.apps.Count -eq 0) {
        WriteLog "No apps were specified in AppList.json file."
        return
    }
    
    # Log app list summary
    $wingetApps = $apps.apps | Where-Object { $_.source -eq "winget" }
    if ($wingetApps) {
        WriteLog 'Winget apps to be installed:'
        $wingetApps | ForEach-Object { WriteLog $_.Name }
    }
    
    $storeApps = $apps.apps | Where-Object { $_.source -eq "msstore" }
    if ($storeApps) {
        WriteLog 'Store apps to be installed:'
        $storeApps | ForEach-Object { WriteLog $_.Name }
    }
    
    # Ensure WinGet is available
    Confirm-WinGetInstallation -WindowsArch $WindowsArch
    
    # Create necessary folders
    $win32Folder = Join-Path -Path $AppsPath -ChildPath "Win32"
    $storeAppsFolder = Join-Path -Path $AppsPath -ChildPath "MSStore"
    
    if (-not (Test-Path -Path $win32Folder -PathType Container)) {
        WriteLog "Creating folder for Winget Win32 apps: $win32Folder"
        New-Item -Path $win32Folder -ItemType Directory -Force | Out-Null
    }
    if (-not (Test-Path -Path $storeAppsFolder -PathType Container)) {
        WriteLog "Creating folder for MSStore apps: $storeAppsFolder"
        New-Item -Path $storeAppsFolder -ItemType Directory -Force | Out-Null
    }
    
    # Transform apps into the format expected by Invoke-ParallelProcessing
    $itemsToProcess = $apps.apps | ForEach-Object {
        $appArch = if ($_.PSObject.Properties['architecture']) { $_.architecture } else { $WindowsArch }
        [PSCustomObject]@{
            Name         = $_.name
            Id           = $_.id
            Source       = $_.source
            Architecture = $appArch
        }
    }
    
    WriteLog "Starting parallel download of $($itemsToProcess.Count) applications with ThrottleLimit: $ThrottleLimit"
    
    # Build task arguments for Invoke-ParallelProcessing
    # CLI builds should create WinGetWin32Apps.json, so SkipWin32Json is false
    $taskArguments = @{
        AppsPath          = $AppsPath
        AppListJsonPath   = $AppList
        OrchestrationPath = $OrchestrationPath
        WindowsArch       = $WindowsArch
        SkipWin32Json     = $false
    }
    
    # Invoke parallel processing in non-UI mode (no WindowObject or ListViewControl)
    Invoke-ParallelProcessing -ItemsToProcess $itemsToProcess `
        -IdentifierProperty 'Id' `
        -StatusProperty 'DownloadStatus' `
        -TaskType 'WingetDownload' `
        -TaskArguments $taskArguments `
        -CompletedStatusText "Completed" `
        -ErrorStatusPrefix "Error: " `
        -MainThreadLogPath $LogFilePath `
        -ThrottleLimit $ThrottleLimit
    
    WriteLog "Parallel download of applications completed."
    
    # Post-processing: Override CommandLine / Arguments from AppList.json if provided
    # Users may supply custom silent install commands or arguments. These optional
    # properties (CommandLine, Arguments) in AppList.json replace the auto-generated
    # values in WinGetWin32Apps.json. Keyed by Name.
    try {
        $overrideMap = @{}
        foreach ($app in $apps.apps) {
            if ($app.source -in @('winget', 'msstore')) {
                $hasCmd    = ($app.PSObject.Properties['CommandLine'] -and -not [string]::IsNullOrWhiteSpace($app.CommandLine))
                $hasArgs   = ($app.PSObject.Properties['Arguments'] -and -not [string]::IsNullOrWhiteSpace($app.Arguments))
                $hasAdd    = ($app.PSObject.Properties['AdditionalExitCodes'] -and -not [string]::IsNullOrWhiteSpace($app.AdditionalExitCodes))
                $hasIgnore = ($app.PSObject.Properties['IgnoreNonZeroExitCodes'])
                if ($hasCmd -or $hasArgs -or $hasAdd -or $hasIgnore) {
                    $overrideMap[$app.name] = @{
                        CommandLine             = if ($hasCmd) { $app.CommandLine } else { $null }
                        Arguments               = if ($hasArgs) { $app.Arguments } else { $null }
                        AdditionalExitCodes     = if ($hasAdd) { $app.AdditionalExitCodes } else { $null }
                        IgnoreNonZeroExitCodes  = if ($hasIgnore) { [bool]$app.IgnoreNonZeroExitCodes } else { $null }
                    }
                }
            }
        }
    
        if ($overrideMap.Count -gt 0) {
            $winGetWin32Path = Join-Path -Path $OrchestrationPath -ChildPath 'WinGetWin32Apps.json'
            if (Test-Path -Path $winGetWin32Path) {
                # Lock WinGetWin32Apps.json during override writes to avoid any unexpected concurrent access
                $mutexName = Get-WinGetWin32AppsJsonMutexName -WinGetWin32AppsJsonPath $winGetWin32Path
                Invoke-WithNamedMutex -MutexName $mutexName -TimeoutSeconds 60 -ScriptBlock {
                    [array]$appsDataUpdated = Get-Content -Path $winGetWin32Path -Raw | ConvertFrom-Json
                    $changed = $false
                    foreach ($entry in $appsDataUpdated) {
                        if ($overrideMap.ContainsKey($entry.Name)) {
                            $ov = $overrideMap[$entry.Name]
                            if ($ov.CommandLine) {
                                WriteLog "Override (AppList.json) CommandLine for $($entry.Name)"
                                $entry.CommandLine = $ov.CommandLine
                                $changed = $true
                            }
                            if ($ov.Arguments) {
                                WriteLog "Override (AppList.json) Arguments for $($entry.Name)"
                                $entry.Arguments = $ov.Arguments
                                $changed = $true
                            }
                            if ($ov.ContainsKey('AdditionalExitCodes') -and $null -ne $ov.AdditionalExitCodes) {
                                WriteLog "Override (AppList.json) AdditionalExitCodes for $($entry.Name)"
                                $entry | Add-Member -NotePropertyName AdditionalExitCodes -NotePropertyValue $ov.AdditionalExitCodes -Force
                                $changed = $true
                            }
                            if ($ov.ContainsKey('IgnoreNonZeroExitCodes') -and $null -ne $ov.IgnoreNonZeroExitCodes) {
                                WriteLog "Override (AppList.json) IgnoreNonZeroExitCodes for $($entry.Name)"
                                $entry | Add-Member -NotePropertyName IgnoreNonZeroExitCodes -NotePropertyValue ([bool]$ov.IgnoreNonZeroExitCodes) -Force
                                $changed = $true
                            }
                        }
                    }
                    if ($changed) {
                        $jsonText = $appsDataUpdated | ConvertTo-Json -Depth 10
                        Set-FileContentAtomic -Path $winGetWin32Path -Content $jsonText
                        WriteLog "Applied AppList.json command overrides to WinGetWin32Apps.json"
                    }
                    else {
                        WriteLog "No matching apps required command overrides."
                    }
                }
            }
            else {
                WriteLog "WinGetWin32Apps.json not found; no overrides applied."
            }
        }
    }
    catch {
        WriteLog "Failed to apply AppList.json command overrides: $($_.Exception.Message)"
    }
}
function Install-WinGet {
    param (
        [string]$Architecture
    )
    $packages = @(
        @{Name = "VCLibs"; Url = "https://aka.ms/Microsoft.VCLibs.$Architecture.14.00.Desktop.appx"; File = "Microsoft.VCLibs.$Architecture.14.00.Desktop.appx" },
        @{Name = "UIXaml"; Url = "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.$Architecture.appx"; File = "Microsoft.UI.Xaml.2.8.$Architecture.appx" },
        @{Name = "WinGet"; Url = "https://aka.ms/getwinget"; File = "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" }
    )
    foreach ($package in $packages) {
        $destination = Join-Path -Path $env:TEMP -ChildPath $package.File
        WriteLog "Downloading $($package.Name) from $($package.Url) to $destination"
        Start-BitsTransferWithRetry -Source $package.Url -Destination $destination
        WriteLog "Installing $($package.Name)..."
        # Don't show progress bar for Add-AppxPackage - there's a weird issue where the progress stays on the screen after the apps are installed
        $ProgressPreference = 'SilentlyContinue'
        Add-AppxPackage -Path $destination -ErrorAction SilentlyContinue
        # Set progress preference back to default
        $ProgressPreference = 'Continue'
        WriteLog "Removing $($package.Name)..."
        Remove-Item -Path $destination -Force -ErrorAction SilentlyContinue
    }
    WriteLog "WinGet installation complete."
}
function Confirm-WinGetInstallation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WindowsArch
    )
    
    WriteLog 'Checking if WinGet is installed...'
    $minVersion = [version]"1.8.1911"
    
    # Check WinGet PowerShell module
    $wingetModule = Get-InstalledModule -Name Microsoft.Winget.Client -ErrorAction SilentlyContinue
    $wingetModuleVersion = [version]$wingetModule.Version
    if ($wingetModuleVersion -lt $minVersion -or -not $wingetModule) {
        WriteLog 'Microsoft.Winget.Client module is not installed or is an older version. Installing the latest version...'
        
        # Handle PSGallery trust settings
        $PSGalleryTrust = (Get-PSRepository -Name 'PSGallery').InstallationPolicy
        if ($PSGalleryTrust -eq 'Untrusted') {
            WriteLog 'Temporarily setting PSGallery as a trusted repository...'
            Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
        }
        
        Install-Module -Name Microsoft.Winget.Client -Force -Repository 'PSGallery'
        
        if ($PSGalleryTrust -eq 'Untrusted') {
            WriteLog 'Setting PSGallery back to untrusted repository...'
            Set-PSRepository -Name 'PSGallery' -InstallationPolicy Untrusted
            WriteLog 'Done'
        }
    }
    else {
        WriteLog "Installed Microsoft.Winget.Client module version: $($wingetModule.Version)"
    }
    
    # Check WinGet CLI
    $wingetVersion = Get-WinGetVersion
    if (-not $wingetVersion) {
        WriteLog "WinGet is not installed. Installing WinGet..."
        Install-WinGet -Architecture $WindowsArch
    }
    elseif ($wingetVersion -match 'v?(\d+\.\d+\.\d+)' -and [version]$matches[1] -lt $minVersion) {
        WriteLog "The installed version of WinGet $($matches[1]) does not support downloading MSStore apps. Installing the latest version of WinGet..."
        Install-WinGet -Architecture $WindowsArch
    }
    else {
        WriteLog "Installed WinGet version: $wingetVersion"
    }
}
# --------------------------------------------------------------------------
# SECTION: WinGetWin32Apps.json File Locking Helpers
# --------------------------------------------------------------------------
function Get-WinGetWin32AppsJsonMutexName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WinGetWin32AppsJsonPath
    )

    # Create a stable, safe mutex name based on the full file path
    # This prevents cross-runspace/cross-process corruption when multiple apps write the same JSON.
    $normalizedPath = $WinGetWin32AppsJsonPath.ToLowerInvariant()
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalizedPath)
        $hashBytes = $sha256.ComputeHash($bytes)
    }
    finally {
        $sha256.Dispose()
    }

    $hash = -join ($hashBytes | ForEach-Object { $_.ToString('x2') })
    return "WinGetWin32AppsJsonLock_$hash"
}

function Invoke-WithNamedMutex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$MutexName,
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        [int]$TimeoutSeconds = 60
    )

    # Use a named mutex so all parallel runspaces serialize file access
    $mutex = New-Object System.Threading.Mutex($false, $MutexName)
    $lockTaken = $false

    try {
        $lockTaken = $mutex.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds))
        if (-not $lockTaken) {
            throw "Timed out waiting for mutex '$MutexName' after $TimeoutSeconds seconds."
        }

        & $ScriptBlock
    }
    finally {
        if ($lockTaken) {
            try {
                $mutex.ReleaseMutex() | Out-Null
            }
            catch {
                # Best-effort release; ignore release failures
            }
        }
        $mutex.Dispose()
    }
}

function Set-FileContentAtomic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    # Write to a unique temp file in the same directory and then rename into place
    # to reduce the chance of partial writes.
    $parentPath = Split-Path -Path $Path -Parent
    if (-not (Test-Path -Path $parentPath -PathType Container)) {
        New-Item -Path $parentPath -ItemType Directory -Force | Out-Null
    }

    $tempPath = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    Set-Content -Path $tempPath -Value $Content -Encoding UTF8

    try {
        # PowerShell 7+ (.NET) supports overwrite via File.Move overload
        [System.IO.File]::Move($tempPath, $Path, $true)
    }
    catch {
        # Fallback for environments where overwrite overload is unavailable
        Move-Item -Path $tempPath -Destination $Path -Force
    }
}

function Add-Win32SilentInstallCommand {
    param (
        [string]$AppFolder,
        [string]$AppFolderPath,
        [Parameter(Mandatory = $true)]
        [string]$OrchestrationPath,
        [string]$SubFolder
    )
    $appName = $AppFolder

    # Discover installer candidates (top-level files as before)
    $installerCandidates = Get-ChildItem -Path "$appFolderPath\*" -Include "*.exe", "*.msi" -File -ErrorAction SilentlyContinue
    if (-not $installerCandidates) {
        WriteLog "No win32 app installers were found. Skipping the inclusion of $AppFolder"
        Remove-Item -Path $AppFolderPath -Recurse -Force
        return 1
    }

    # Read the exported WinGet YAML
    $yamlFile = Get-ChildItem -Path "$appFolderPath\*" -Include "*.yaml" -File -ErrorAction Stop
    $yamlText = Get-Content -Path $yamlFile -Raw

    # Attempt to resolve the correct installer from YAML NestedInstallerFiles within the matching Architecture block
    $desiredArch = if (-not [string]::IsNullOrEmpty($SubFolder)) { $SubFolder } else { $null }
    $relativeFromYaml = $null
    $blockSilent = $null

    $regexOptions = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    $pattern = '-\s+Architecture:\s*(?<arch>\S+)[\s\S]*?NestedInstallerFiles:\s*-\s*RelativeFilePath:\s*(?<path>.+?)\r?\n'
    $yamlMatches = [regex]::Matches($yamlText, $pattern, $regexOptions)

    $selectedMatch = $null
    if ($yamlMatches.Count -gt 0) {
        if ($desiredArch) {
            foreach ($m in $yamlMatches) {
                if ($m.Groups['arch'].Value -ieq $desiredArch) {
                    $selectedMatch = $m
                    break
                }
            }
        }
        if (-not $selectedMatch) {
            $selectedMatch = $yamlMatches[0]
        }

        $pathValue = $selectedMatch.Groups['path'].Value.Trim()
        $pathValue = $pathValue.Trim("'").Trim('"')
        $relativeFromYaml = $pathValue

        # Extract a Silent switch from within the same installer block if present
        $startIndex = $selectedMatch.Index
        $nextIndex = -1
        for ($i = 0; $i -lt $yamlMatches.Count; $i++) {
            if ($yamlMatches[$i].Index -gt $startIndex) {
                $nextIndex = $yamlMatches[$i].Index
                break
            }
        }
        if ($nextIndex -gt -1) {
            $blockText = $yamlText.Substring($startIndex, $nextIndex - $startIndex)
        }
        else {
            $blockText = $yamlText.Substring($startIndex)
        }
        $blockSilentMatch = [regex]::Match($blockText, 'InstallerSwitches:[\s\S]*?Silent:\s*(.+?)\r?\n', $regexOptions)
        if ($blockSilentMatch.Success) {
            $blockSilent = $blockSilentMatch.Groups[1].Value.Trim().Trim("'").Trim('"')
        }
    }

    # Resolve Silent switch (prefer block-level, fallback to first Silent in file)
    $silentInstallSwitch = $blockSilent
    if ([string]::IsNullOrEmpty($silentInstallSwitch)) {
        $globalSilentMatch = [regex]::Match($yamlText, 'Silent:\s*(.+)', $regexOptions)
        $silentInstallSwitch = $globalSilentMatch.Groups[1].Value.Trim().Trim("'").Trim('"')
    }
    if (-not $silentInstallSwitch) {
        WriteLog "Silent install switch for $appName could not be found. Skipping the inclusion of $appName."
        Remove-Item -Path $appFolderPath -Recurse -Force
        return 2
    }

    # Choose final installer path and extension
    $resolvedRelativePath = $null
    $installerExt = $null

    if ($installerCandidates.Count -eq 1 -and -not $relativeFromYaml) {
        # Single installer – keep current behavior
        $resolvedRelativePath = $installerCandidates[0].Name
        $installerExt = $installerCandidates[0].Extension
        WriteLog "Single installer detected ($resolvedRelativePath). Using current behavior."
    }
    else {
        if ($relativeFromYaml) {
            $normalizedPath = ($relativeFromYaml -replace '/', '\')
            $resolvedRelativePath = $normalizedPath
            $installerExt = [System.IO.Path]::GetExtension($normalizedPath)
            if ([string]::IsNullOrEmpty($installerExt)) {
                $leafName = [System.IO.Path]::GetFileName($normalizedPath)
                $matchedCandidate = $installerCandidates | Where-Object { $_.Name -ieq $leafName } | Select-Object -First 1
                if ($matchedCandidate) {
                    $installerExt = $matchedCandidate.Extension
                }
            }
            WriteLog "Multiple installers found. Selected by YAML NestedInstallerFiles: $resolvedRelativePath"
        }
        if (-not $resolvedRelativePath) {
            # Fallbacks when YAML lacks NestedInstallerFiles or couldn't be matched
            $msis = $installerCandidates | Where-Object { $_.Extension -ieq ".msi" }
            if ($msis.Count -eq 1) {
                $resolvedRelativePath = $msis[0].Name
                $installerExt = ".msi"
                WriteLog "Multiple installers found. YAML not used. Falling back to single MSI: $resolvedRelativePath"
            }
            else {
                $exes = $installerCandidates | Where-Object { $_.Extension -ieq ".exe" }
                if ($exes.Count -eq 1) {
                    $resolvedRelativePath = $exes[0].Name
                    $installerExt = ".exe"
                    WriteLog "Multiple installers found. YAML not used. Falling back to single EXE: $resolvedRelativePath"
                }
                else {
                    $first = $installerCandidates | Select-Object -First 1
                    $resolvedRelativePath = $first.Name
                    $installerExt = $first.Extension
                    WriteLog "Multiple installers found and ambiguous. Selecting the first candidate: $resolvedRelativePath"
                }
            }
        }
    }

    $basePath = "D:\win32\$AppFolder"
    if (-not [string]::IsNullOrEmpty($SubFolder)) {
        $basePath = "$basePath\$SubFolder"
    }

    # Build final command/arguments
    if ($installerExt -ieq ".exe") {
        $silentInstallCommand = "$basePath\$resolvedRelativePath"
    }
    elseif ($installerExt -ieq ".msi") {
        $silentInstallCommand = "msiexec"
        $silentInstallSwitch = "/i `"$basePath\$resolvedRelativePath`" $silentInstallSwitch"
    }
    else {
        # Default path usage if extension could not be inferred
        $silentInstallCommand = "$basePath\$resolvedRelativePath"
    }

    # Path to the JSON file
    $wingetWin32AppsJson = "$OrchestrationPath\WinGetWin32Apps.json"

    # Serialize access to WinGetWin32Apps.json to prevent corruption when multiple apps are processed in parallel
    $mutexName = Get-WinGetWin32AppsJsonMutexName -WinGetWin32AppsJsonPath $wingetWin32AppsJson
    Invoke-WithNamedMutex -MutexName $mutexName -TimeoutSeconds 60 -ScriptBlock {
        # Initialize or load existing JSON data
        $appsData = @()
        if (Test-Path -Path $wingetWin32AppsJson) {
            try {
                [array]$appsData = Get-Content -Path $wingetWin32AppsJson -Raw | ConvertFrom-Json
                if ($null -eq $appsData) {
                    $appsData = @()
                }
            }
            catch {
                # Backup the corrupted file so the build can continue
                $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
                $backupPath = "$wingetWin32AppsJson.corrupt.$timestamp"
                try {
                    Copy-Item -Path $wingetWin32AppsJson -Destination $backupPath -Force
                    WriteLog "WinGetWin32Apps.json could not be parsed. Backed up corrupt file to '$backupPath' and rebuilding."
                }
                catch {
                    WriteLog "WinGetWin32Apps.json could not be parsed and backup failed: $($_.Exception.Message). Rebuilding anyway."
                }

                $appsData = @()
            }
        }

        # Calculate next priority (always set, even if the file exists but is empty)
        $highestPriority = if ($appsData.Count -gt 0) { $appsData.Count + 1 } else { 1 }

        # Create new app entry
        $newApp = [PSCustomObject]@{
            Priority    = $highestPriority
            Name        = if (-not [string]::IsNullOrEmpty($SubFolder)) { "$appName ($SubFolder)" } else { $appName }
            CommandLine = $silentInstallCommand
            Arguments   = $silentInstallSwitch
        }

        # Write the updated JSON file using a temp+rename to reduce partial-write risk
        $appsData += $newApp
        $jsonText = $appsData | ConvertTo-Json -Depth 10
        Set-FileContentAtomic -Path $wingetWin32AppsJson -Content $jsonText
    }

    WriteLog "Added $($newApp.Name) to WinGetWin32Apps.json with priority $highestPriority"

    # Return 0 for success
    return 0
}

# --------------------------------------------------------------------------
# SECTION: Module Export
# --------------------------------------------------------------------------

# Export functions needed by both BuildFFUVM and the UI Core module
Export-ModuleMember -Function Get-Application, Get-Apps, Start-WingetAppDownloadTask, Confirm-WinGetInstallation, Add-Win32SilentInstallCommand, Install-Winget