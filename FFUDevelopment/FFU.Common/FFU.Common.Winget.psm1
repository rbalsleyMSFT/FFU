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
        [string]$Source
    )
    
    # Validate app exists in repository
    $wingetSearchResult = Find-WinGetPackage -id $AppId -MatchOption Equals -Source $Source
    if (-not $wingetSearchResult) {
        if ($VerbosePreference -ne 'Continue') {
            Write-Error "$AppName not found in $Source repository."
            Write-Error "Check the AppList.json file and make sure the AppID is correct."
        }
        WriteLog "$AppName not found in $Source repository."
        WriteLog "Check the AppList.json file and make sure the AppID is correct."
        Exit 1
    }
    
    # Determine app type and folder path
    $appIsWin32 = ($Source -eq 'msstore' -and $AppId.StartsWith("XP"))
    if ($Source -eq 'winget' -or $appIsWin32) {
        $appFolderPath = Join-Path -Path "$AppsPath\Win32" -ChildPath $AppName
    }
    else {
        $appFolderPath = Join-Path -Path "$AppsPath\MSStore" -ChildPath $AppName
    }
    
    # Create app folder
    New-Item -Path $appFolderPath -ItemType Directory -Force | Out-Null
    
    # Log download information
    WriteLog "Downloading $AppName for $WindowsArch architecture..."
    if ($Source -eq 'msstore') {
        WriteLog 'MSStore app downloads require authentication with an Entra ID account. You may be prompted twice for credentials, once for the app and another for the license file.'
    }
    WriteLog "WinGet command: Export-WinGetPackage -id $AppId -DownloadDirectory $appFolderPath -Architecture $WindowsArch -Source $Source"
    
    # Download the app
    $wingetDownloadResult = Export-WinGetPackage -id $AppId -DownloadDirectory $appFolderPath -Architecture $WindowsArch -Source $Source
    
    # Handle download status
    if ($wingetDownloadResult.status -ne 'Ok') {
        # Try downloading without architecture if no applicable installer found
        if ($wingetDownloadResult.status -eq 'NoApplicableInstallers' -or $wingetDownloadResult.status -eq 'NoApplicableInstallerFound') {
            WriteLog "No installer found for $WindowsArch architecture. Attempting to download without specifying architecture..."
            $wingetDownloadResult = Export-WinGetPackage -id $AppId -DownloadDirectory $appFolderPath -Source $Source
            if ($wingetDownloadResult.status -eq 'Ok') {
                WriteLog "Downloaded $AppName without specifying architecture."
            }
            else {
                WriteLog "ERROR: No installer found for $AppName. Exiting"
                Remove-Item -Path $appFolderPath -Recurse -Force
                Exit 1
            }
        }
        # Handle Store-specific errors
        elseif ($Source -eq 'msstore') {
            # If download not supported by publisher
            if ($wingetDownloadResult.ExtendedErrorCode -match '0x8A150084') {
                WriteLog "ERROR: The Microsoft Store app $AppName does not support downloads by the publisher. Please remove it from the AppList.json. If there's a winget source version of the application, try using that instead. Exiting."
                Remove-Item -Path $appFolderPath -Recurse -Force
                Write-Error "ERROR: The Microsoft Store app $AppName does not support downloads by the publisher. Please remove it from the AppList.json. If there's a winget source version of the application, try using that instead. Exiting."
                Exit 1
            }
        }
        else {
            $errormsg = "ERROR: Download failed for $AppName with status: $($wingetDownloadResult.status) $($wingetDownloadResult.ExtendedErrorCode)"
            WriteLog $errormsg
            Remove-Item -Path $appFolderPath -Recurse -Force
            Write-Error $errormsg
            Exit 1
        }
    }
    
    WriteLog "$AppName downloaded to $appFolderPath"
    
    # Handle winget source apps that have appx, appxbundle, msix, or msixbundle extensions but were downloaded to the Win32 folder
    $installerPath = Get-ChildItem -Path "$appFolderPath\*" -Exclude "*.yaml", "*.xml" -File -ErrorAction Stop
    $uwpExtensions = @(".appx", ".appxbundle", ".msix", ".msixbundle")
    
    if ($uwpExtensions -contains $installerPath.Extension -and $appFolderPath -match 'Win32') {
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
        # Set-InstallStoreAppsFlag
        $result = 0  # Success for UWP app
    }
    # If app is in Win32 folder, add the silent install command to the WinGetWin32Apps.json file
    elseif ($appFolderPath -match 'Win32') {
        WriteLog "$AppName is a Win32 app. Adding silent install command to $orchestrationpath\WinGetWin32Apps.json"
        $result = Add-Win32SilentInstallCommand -AppFolder $AppName -AppFolderPath $appFolderPath
    }
    else {
        # For any other case, set result to 0 (success)
        $result = 0
    }
    
    # Handle MSStore specific post-processing
    if ($Source -eq 'msstore' -and $appFolderPath -match 'MSStore') {
        # Set-InstallStoreAppsFlag
        
        # Handle ARM64-specific dependencies
        if ($WindowsArch -eq 'ARM64') {
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
        
        # Clean up multiple versions (keep only the latest)
        WriteLog "$AppName has completed downloading. Identifying the latest version of $AppName."
        $packages = Get-ChildItem -Path "$appFolderPath\*" -Exclude "Dependencies\*", "*.xml", "*.yaml" -File -ErrorAction Stop
        
        # Find latest version based on signature date
        $latestPackage = $packages | Sort-Object { (Get-AuthenticodeSignature $_.FullName).SignerCertificate.NotBefore } -Descending | Select-Object -First 1
        
        # Remove older versions
        WriteLog "Latest version of $AppName has been identified as $latestPackage. Removing old versions of $AppName that may have downloaded."
        foreach ($package in $packages) {
            if ($package.FullName -ne $latestPackage) {
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
    
    return $result
}
function Get-Apps {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$AppList
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
    Confirm-WinGetInstallation
    
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
                Get-Application -AppName $wingetApp.Name -AppId $wingetApp.Id -Source 'winget'
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
                Get-Application -AppName $storeApp.Name -AppId $storeApp.Id -Source 'msstore'
            }
            catch {
                WriteLog "Error occurred while processing $($storeApp.Name): $_"
                throw $_
            }
        }
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
    param()
    
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
        [string]$AppFolderPath
    )
    $appName = $AppFolder
    $installerPath = Get-ChildItem -Path "$appFolderPath\*" -Include "*.exe", "*.msi" -File -ErrorAction Stop
    if (-not $installerPath) {
        WriteLog "No win32 app installers were found. Skipping the inclusion of $AppFolder"
        Remove-Item -Path $AppFolderPath -Recurse -Force
        return 1
    }
    $yamlFile = Get-ChildItem -Path "$appFolderPath\*" -Include "*.yaml" -File -ErrorAction Stop
    $yamlContent = Get-Content -Path $yamlFile -Raw
    $silentInstallSwitch = [regex]::Match($yamlContent, 'Silent:\s*(.+)').Groups[1].Value.Replace("'", "").Trim()
    if (-not $silentInstallSwitch) {
        WriteLog "Silent install switch for $appName could not be found. Skipping the inclusion of $appName."
        Remove-Item -Path $appFolderPath -Recurse -Force
        return 2
    }
    $installer = Split-Path -Path $installerPath -Leaf
    if ($installerPath.Extension -eq ".exe") {
        $silentInstallCommand = "D:\win32\$appFolder\$installer"
    } 
    elseif ($installerPath.Extension -eq ".msi") {
        $silentInstallCommand = "msiexec"
        $silentInstallSwitch = "/i `"D:\win32\$appFolder\$installer`" $silentInstallSwitch"
    }
    
    # Path to the JSON file
    $wingetWin32AppsJson = "$orchestrationPath\WinGetWin32Apps.json"
    
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
        Name        = $appName
        CommandLine = $silentInstallCommand
        Arguments   = $silentInstallSwitch
    }
    
    $appsData += $newApp
    $appsData | ConvertTo-Json -Depth 10 | Set-Content -Path $wingetWin32AppsJson
    
    WriteLog "Added $appName to WinGetWin32Apps.json with priority $highestPriority"
    
    # Return 0 for success
    return 0
}

# --------------------------------------------------------------------------
# SECTION: Module Export
# --------------------------------------------------------------------------

# Export functions needed by both BuildFFUVM and the UI Core module
Export-ModuleMember -Function Get-Application, Get-Apps, Confirm-WinGetInstallation, Add-Win32SilentInstallCommand, Install-Winget