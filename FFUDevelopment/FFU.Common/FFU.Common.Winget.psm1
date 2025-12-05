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
                    if (-not [string]::IsNullOrWhiteSpace($appFolderPath)) {
                        Remove-Item -Path $appFolderPath -Recurse -Force -ErrorAction SilentlyContinue
                    }
                    Write-Error $errorMessage
                    return 3 # Return specific error code for publisher restriction
                }
                # Handle other download failures
                else {
                    $errormsg = "Download failed for $AppName with status: $($wingetDownloadResult.status) $($wingetDownloadResult.ExtendedErrorCode)"
                    WriteLog $errormsg
                    if (-not [string]::IsNullOrWhiteSpace($appFolderPath)) {
                        Remove-Item -Path $appFolderPath -Recurse -Force -ErrorAction SilentlyContinue
                    }
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
            Remove-Item -Path $zipFile.FullName -Force -ErrorAction SilentlyContinue
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
            if (-not [string]::IsNullOrWhiteSpace($appFolderPath)) {
                Remove-Item -Path $appFolderPath -Force -Recurse -ErrorAction SilentlyContinue
            }
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
                            Remove-Item -Path $dependency.FullName -Recurse -Force -ErrorAction SilentlyContinue
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
                            Remove-Item -Path $package.FullName -Force -ErrorAction SilentlyContinue
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
                            Remove-Item -Path $package.FullName -Force -ErrorAction SilentlyContinue
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
        [string]$OrchestrationPath
    )
    
    # Load and validate app list
    $apps = Get-Content -Path $AppList -Raw | ConvertFrom-Json
    if (-not $apps) {
        WriteLog "No apps were specified in AppList.json file."
        return
    }
    
    # Process WinGet apps
    $wingetApps = $apps.apps | Where-Object { $_.source -eq "winget" }
    if ($wingetApps) {
        WriteLog 'Winget apps to be installed:'
        $wingetApps | ForEach-Object { WriteLog $_.Name }
    }
    
    # Process Store apps
    $StoreApps = $apps.apps | Where-Object { $_.source -eq "msstore" }
    if ($StoreApps) {
        WriteLog 'Store apps to be installed:'
        $StoreApps | ForEach-Object { WriteLog $_.Name }
    }
    
    # Ensure WinGet is available
    Confirm-WinGetInstallation -WindowsArch $WindowsArch
    
    # Create necessary folders
    $win32Folder = Join-Path -Path $AppsPath -ChildPath "Win32"
    $storeAppsFolder = Join-Path -Path $AppsPath -ChildPath "MSStore"

    # Process WinGet apps
    if ($wingetApps) {
        if (-not (Test-Path -Path $win32Folder -PathType Container)) {
            WriteLog "Creating folder for Winget Win32 apps: $win32Folder"
            New-Item -Path $win32Folder -ItemType Directory -Force | Out-Null
            WriteLog "Folder created successfully."
        }
        
        foreach ($wingetApp in $wingetApps) {
            try {
                $appArch = if ($wingetApp.PSObject.Properties['architecture']) { $wingetApp.architecture } else { $WindowsArch }
                Get-Application -AppName $wingetApp.Name -AppId $wingetApp.Id -Source 'winget' -AppsPath $AppsPath -ApplicationArch $appArch -OrchestrationPath $OrchestrationPath
            }
            catch {
                WriteLog "Error occurred while processing $($wingetApp.Name): $_"
                throw $_
            }
        }
    }
    
    # Process Store apps
    if ($StoreApps) {
        if (-not (Test-Path -Path $storeAppsFolder -PathType Container)) {
            New-Item -Path $storeAppsFolder -ItemType Directory -Force | Out-Null
        }
            
        foreach ($storeApp in $StoreApps) {
            try {
                $appArch = if ($storeApp.PSObject.Properties['architecture']) { $storeApp.architecture } else { $WindowsArch }
                Get-Application -AppName $storeApp.Name -AppId $storeApp.Id -Source 'msstore' -AppsPath $AppsPath -ApplicationArch $appArch -WindowsArch $WindowsArch -OrchestrationPath $OrchestrationPath
            }
            catch {
                WriteLog "Error occurred while processing $($storeApp.Name): $_"
                throw $_
            }
        }
    }
    
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
                    $appsDataUpdated | ConvertTo-Json -Depth 10 | Set-Content -Path $winGetWin32Path
                    WriteLog "Applied AppList.json command overrides to WinGetWin32Apps.json"
                }
                else {
                    WriteLog "No matching apps required command overrides."
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
        if (-not [string]::IsNullOrWhiteSpace($AppFolderPath)) {
            Remove-Item -Path $AppFolderPath -Recurse -Force -ErrorAction SilentlyContinue
        }
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
        if (-not [string]::IsNullOrWhiteSpace($appFolderPath)) {
            Remove-Item -Path $appFolderPath -Recurse -Force -ErrorAction SilentlyContinue
        }
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

    # Initialize or load existing JSON data
    if (Test-Path -Path $wingetWin32AppsJson) {
        [array]$appsData = Get-Content -Path $wingetWin32AppsJson -Raw | ConvertFrom-Json

        # Get highest priority value
        if ($appsData.Count -gt 0) {
            $highestPriority = $appsData.Count + 1
        }
    }
    else {
        $appsData = @()
        $highestPriority = 1
    }

    # Create new app entry
    $newApp = [PSCustomObject]@{
        Priority    = $highestPriority
        Name        = if (-not [string]::IsNullOrEmpty($SubFolder)) { "$appName ($SubFolder)" } else { $appName }
        CommandLine = $silentInstallCommand
        Arguments   = $silentInstallSwitch
    }

    $appsData += $newApp
    $appsData | ConvertTo-Json -Depth 10 | Set-Content -Path $wingetWin32AppsJson

    WriteLog "Added $($newApp.Name) to WinGetWin32Apps.json with priority $highestPriority"

    # Return 0 for success
    return 0
}

# --------------------------------------------------------------------------
# SECTION: Module Export
# --------------------------------------------------------------------------

# Export functions needed by both BuildFFUVM and the UI Core module
Export-ModuleMember -Function Get-Application, Get-Apps, Confirm-WinGetInstallation, Add-Win32SilentInstallCommand, Install-Winget