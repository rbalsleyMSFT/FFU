<#
.SYNOPSIS
    Core logic module for the FFU Builder UI, providing helper functions, data retrieval, and UI state management.
.DESCRIPTION
    This module serves as the central logic hub for the FFU Builder UI. It contains functions for retrieving system information (like Hyper-V switches and USB drives), providing default application settings, and dynamically managing the visibility and state of various UI controls across different tabs based on user selections. It orchestrates the interactions between different parts of the UI to ensure a consistent and logical user experience.
#>

# --------------------------------------------------------------------------
# SECTION: Module Variables (Static Data & State)
# --------------------------------------------------------------------------

#Microsoft sites will intermittently fail on downloads. These headers and user agent are to help with that.
$script:Headers = @{
    "Accept"                    = "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7"
    "Accept-Encoding"           = "gzip, deflate, br, zstd"
    "Accept-Language"           = "en-US,en;q=0.9"
    "Priority"                  = "u=0, i"
    "Sec-Ch-Ua"                 = "`"Not)A;Brand`";v=`"8`", `"Chromium`";v=`"138`", `"Microsoft Edge`";v=`"138`""
    "Sec-Ch-Ua-Mobile"          = "?0"
    "Sec-Ch-Ua-Platform"        = "`"Windows`""
    "Sec-Fetch-Dest"            = "document"
    "Sec-Fetch-Mode"            = "navigate"
    "Sec-Fetch-Site"            = "none"
    "Sec-Fetch-User"            = "?1"
    "Upgrade-Insecure-Requests" = "1"
}
$script:UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0'

function Get-CoreStaticVariables {
    [CmdletBinding()]
    param()

    return @{
        Headers   = $script:Headers
        UserAgent = $script:UserAgent
    }
}

# Function to get VM Switch names and associated IP addresses
function Get-VMSwitchData {
    [CmdletBinding()]
    param()

    $switchMap = @{}
    $switchNames = @()

    try {
        $allSwitches = Get-VMSwitch -ErrorAction SilentlyContinue
        if ($null -ne $allSwitches) {
            foreach ($sw in $allSwitches) {
                $adapterNamePattern = "*($($sw.Name))*"

                # Attempt to find the network adapter associated with the vSwitch
                # Select-Object -First 1 ensures we only get one adapter if multiple match (unlikely but possible)
                $netAdapter = Get-NetAdapter -Name $adapterNamePattern -ErrorAction SilentlyContinue | Select-Object -First 1

                if ($netAdapter) {
                    # Get IPv4 addresses for the found adapter's interface index
                    $netIPs = Get-NetIPAddress -InterfaceIndex $netAdapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue

                    # Filter out Automatic Private IP Addressing (APIPA) addresses (169.254.x.x)
                    # and select the first valid IP found.
                    $validIP = $netIPs | Where-Object { $_.IPAddress -notlike '169.254.*' -and $_.IPAddress } | Select-Object -First 1

                    if ($validIP) {
                        # Store the valid IP address in the map with the switch name as the key
                        $switchMap[$sw.Name] = $validIP.IPAddress
                        # Log the found IP address for debugging/information using WriteLog
                        WriteLog "Found IP $($validIP.IPAddress) for vSwitch '$($sw.Name)' (Adapter: $($netAdapter.Name)). Adding to list."
                        # Add the switch name to the list ONLY if a valid IP was found
                        $switchNames += $sw.Name
                    }
                    else {
                        WriteLog "No valid non-APIPA IPv4 address found for vSwitch '$($sw.Name)' (Adapter: $($netAdapter.Name)). Skipping from list."
                    }
                }
                else {
                    WriteLog "Could not find a network adapter matching pattern '$adapterNamePattern' for vSwitch '$($sw.Name)'. Skipping from list."
                }
            }
        }
        else {
            WriteLog "No Hyper-V virtual switches found on this system."
        }
    }
    catch {
        WriteLog "Error occurred while getting VM Switch data: $($_.Exception.Message)"
    }
    return [PSCustomObject]@{
        SwitchNames = $switchNames
        SwitchMap   = $switchMap
    }
}

# Function to return general default settings for various UI elements
function Get-GeneralDefaults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FFUDevelopmentPath
    )

    # Derive paths based on the main development path
    $appsPath = Join-Path -Path $FFUDevelopmentPath -ChildPath "Apps"
    $driversPath = Join-Path -Path $FFUDevelopmentPath -ChildPath "Drivers"
    $peDriversPath = Join-Path -Path $FFUDevelopmentPath -ChildPath "PEDrivers"
    $vmLocationPath = Join-Path -Path $FFUDevelopmentPath -ChildPath "VM"
    $ffuCapturePath = Join-Path -Path $FFUDevelopmentPath -ChildPath "FFU"
    $officePath = Join-Path -Path $appsPath -ChildPath "Office"
    $appListJsonPath = Join-Path -Path $appsPath -ChildPath "AppList.json"
    $userAppListPath = Join-Path -Path $appsPath -ChildPath "UserAppList.json"
    $driversJsonPath = Join-Path -Path $driversPath -ChildPath "Drivers.json"

    return [PSCustomObject]@{
        # Build Tab Defaults
        CustomFFUNameTemplate          = "{WindowsRelease}_{WindowsVersion}_{SKU}_{yyyy}-{MM}-{dd}_{HH}{mm}"
        FFUCaptureLocation             = $ffuCapturePath
        Threads                        = 5
        BitsPriority                   = 'Normal'
        MaxUSBDrives                   = 5
        BuildUSBDriveEnable            = $false
        CompactOS                      = $true
        Optimize                       = $true
        AllowVHDXCaching               = $false
        CreateDeploymentMedia          = $true
        Verbose                        = $false
        AllowExternalHardDiskMedia     = $false
        PromptExternalHardDiskMedia    = $true
        SelectSpecificUSBDrives        = $false
        CopyAdditionalFFUFiles         = $false
        CopyAutopilot                  = $false
        CopyUnattend                   = $false
        CopyPPKG                       = $false
        InjectUnattend                 = $false
        CleanupAppsISO                 = $true
        CleanupDeployISO               = $true
        CleanupDrivers                 = $false
        RemoveFFU                      = $false
        RemoveApps                     = $false 
        RemoveUpdates                  = $false 
        RemoveDownloadedESD            = $true
        # Hyper-V Settings Defaults
        DiskSizeGB                     = 50
        MemoryGB                       = 4
        Processors                     = 4
        VMLocation                     = $vmLocationPath
        VMNamePrefix                   = "_FFU"
        LogicalSectorSize              = 512
        # Updates Tab Defaults
        UpdateLatestCU                 = $true
        UpdateLatestNet                = $true
        UpdateLatestDefender           = $true
        UpdateEdge                     = $true
        UpdateOneDrive                 = $true
        UpdateLatestMSRT               = $true
        UpdateLatestMicrocode          = $false
        UpdatePreviewCU                = $false
        # Applications Tab Defaults
        InstallApps                    = $false
        ApplicationPath                = $appsPath
        AppListJsonPath                = $appListJsonPath
        UserAppListPath                = $userAppListPath
        InstallWingetApps              = $false
        BringYourOwnApps               = $false
        # M365 Apps/Office Tab Defaults
        InstallOffice                  = $true
        OfficePath                     = $officePath
        CopyOfficeConfigXML            = $false
        OfficeConfigXMLFilePath        = ""
        # Drivers Tab Defaults
        DriversFolder                  = $driversPath
        PEDriversFolder                = $peDriversPath
        DriversJsonPath                = $driversJsonPath
        DownloadDrivers                = $false
        InstallDrivers                 = $false
        CopyDrivers                    = $false
        CopyPEDrivers                  = $false
        UseDriversAsPEDrivers          = $false
        UpdateADK                      = $true
        CompressDownloadedDriversToWim = $false
    }
}

# Function to get USB Drives (Moved from BuildFFUVM_UI.ps1)
# Uses Get-Disk to retrieve UniqueId which is more reliable than SerialNumber
# UniqueId is trimmed to remove the machine name suffix (characters after colon)
function Get-USBDrives {
    Get-WmiObject Win32_DiskDrive | Where-Object {
        ($_.MediaType -eq 'Removable Media' -or $_.MediaType -eq 'External hard disk media')
    } | ForEach-Object {
        $size = [math]::Round($_.Size / 1GB, 2)
        # Get the disk using the index to retrieve UniqueId
        $disk = Get-Disk -Number $_.Index -ErrorAction SilentlyContinue
        # Trim the machine name suffix (everything after the colon) from UniqueId
        $uniqueId = if ($disk -and $disk.UniqueId) {
            $rawId = $disk.UniqueId
            if ($rawId -match ':') {
                $rawId.Split(':')[0]
            }
            else {
                $rawId
            }
        }
        else {
            "N/A"
        }
        @{
            IsSelected = $false
            Model      = $_.Model.Trim()
            UniqueId   = $uniqueId
            Size       = $size
            DriveIndex = $_.Index
        }
    }
}

# Returns a list of FFU files from the provided folder with selection metadata
function Get-FFUFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    if (-not (Test-Path -Path $Path)) {
        return @()
    }
    Get-ChildItem -Path $Path -Filter '*.ffu' -File -ErrorAction SilentlyContinue | ForEach-Object {
        [PSCustomObject]@{
            IsSelected   = $false
            Name         = $_.Name
            LastModified = $_.LastWriteTime
            FullName     = $_.FullName
        }
    }
}

# Helper: Populate Additional FFU List from the capture folder
function Update-AdditionalFFUList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$State
    )
    try {
        $ffuFolder = $State.Controls.txtFFUCaptureLocation.Text
        $listView = $State.Controls.lstAdditionalFFUs
        if ($null -eq $listView) { return }
        $listView.Items.Clear()
        if ([string]::IsNullOrWhiteSpace($ffuFolder) -or -not (Test-Path -Path $ffuFolder)) {
            WriteLog "Additional FFUs: Capture folder not set or not found: $ffuFolder"
        }
        else {
            $items = Get-ChildItem -Path $ffuFolder -Filter '*.ffu' -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                ForEach-Object {
                    [PSCustomObject]@{
                        IsSelected   = $false
                        Name         = $_.Name
                        LastModified = $_.LastWriteTime
                        FullName     = $_.FullName
                    }
                }
            foreach ($it in $items) { $listView.Items.Add($it) | Out-Null }
            WriteLog "Additional FFUs: Found $($listView.Items.Count) FFU files in $ffuFolder."
        }
        Request-ListViewColumnAutoResize -ListView $listView
        $headerChk = $State.Controls.chkSelectAllAdditionalFFUs
        if ($null -ne $headerChk) {
            Update-SelectAllHeaderCheckBoxState -ListView $listView -HeaderCheckBox $headerChk
        }
    }
    catch {
        WriteLog "Update-AdditionalFFUList error: $($_.Exception.Message)"
    }
}

# Function to manage the visibility of the application UI panels
function Update-ApplicationPanelVisibility {
    param(
        [PSCustomObject]$State,
        [string]$TriggeringControlName # Optional: to know which control initiated the change
    )

    # If BYO Apps, Winget Apps, or Define Apps Script Variables is checked, force Install Apps to be checked
    if ($State.Controls.chkBringYourOwnApps.IsChecked -or $State.Controls.chkInstallWingetApps.IsChecked -or $State.Controls.chkDefineAppsScriptVariables.IsChecked) {
        $State.Controls.chkInstallApps.IsChecked = $true
    }

    $installAppsChecked = $State.Controls.chkInstallApps.IsChecked
    
    # If the main 'Install Apps' is unchecked, everything below it gets hidden and reset.
    if ($TriggeringControlName -eq 'chkInstallApps' -and -not $installAppsChecked) {
        $State.Controls.chkInstallWingetApps.IsChecked = $false
        $State.Controls.chkBringYourOwnApps.IsChecked = $false
        $State.Controls.chkDefineAppsScriptVariables.IsChecked = $false
    }

    $byoAppsChecked = $State.Controls.chkBringYourOwnApps.IsChecked
    $wingetAppsChecked = $State.Controls.chkInstallWingetApps.IsChecked
    $defineVarsChecked = $State.Controls.chkDefineAppsScriptVariables.IsChecked

    # Visibility of primary sub-options
    $subOptionVisibility = if ($installAppsChecked) { 'Visible' } else { 'Collapsed' }
    $State.Controls.applicationPathPanel.Visibility = $subOptionVisibility
    $State.Controls.appListJsonPathPanel.Visibility = $subOptionVisibility
    $State.Controls.userAppListPathPanel.Visibility = $subOptionVisibility
    $State.Controls.chkInstallWingetApps.Visibility = $subOptionVisibility
    $State.Controls.chkBringYourOwnApps.Visibility = $subOptionVisibility
    $State.Controls.chkDefineAppsScriptVariables.Visibility = $subOptionVisibility

    # Visibility of panels dependent on sub-options
    $State.Controls.byoApplicationPanel.Visibility = if ($installAppsChecked -and $byoAppsChecked) { 'Visible' } else { 'Collapsed' }
    $State.Controls.wingetPanel.Visibility = if ($installAppsChecked -and $wingetAppsChecked) { 'Visible' } else { 'Collapsed' }
    $State.Controls.appsScriptVariablesPanel.Visibility = if ($installAppsChecked -and $defineVarsChecked) { 'Visible' } else { 'Collapsed' }

    # Special handling for wingetSearchPanel, which is shown by another button.
    # We only collapse it if its parent becomes invisible.
    if (-not ($installAppsChecked -and $wingetAppsChecked)) {
        $State.Controls.wingetSearchPanel.Visibility = 'Collapsed'
    }
}

# Function to identify whether current Windows release selection is Windows 10 LTSB/LTSC
function Test-IsWindows10LtscReleaseSelection {
    param([PSCustomObject]$State)

    $releaseItem = $State.Controls.cmbWindowsRelease.SelectedItem
    if ($null -eq $releaseItem) {
        return $false
    }

    $releaseDisplay = [string]$releaseItem.Display
    if ([string]::IsNullOrWhiteSpace($releaseDisplay)) {
        return $false
    }

    return (($releaseDisplay -like 'Windows 10*') -and (($releaseDisplay -like '*LTSB*') -or ($releaseDisplay -like '*LTSC*')))
}

# Function to manage the state of the main "Install Apps" checkbox based on selections in Updates/Office
function Update-InstallAppsState {
    param([PSCustomObject]$State)

    $installAppsChk = $State.Controls.chkInstallApps
    $installOfficeChk = $State.Controls.chkInstallOffice

    # Determine if Windows 10 LTSB/LTSC + Update Latest CU is selected
    $isWindows10LtscRelease = Test-IsWindows10LtscReleaseSelection -State $State
    $isLtscCuChecked = $State.Controls.chkUpdateLatestCU.IsChecked -and $isWindows10LtscRelease

    # Determine if any checkbox that forces "Install Apps" is checked
    $anyUpdateChecked = $State.Controls.chkUpdateLatestDefender.IsChecked -or `
        $State.Controls.chkUpdateEdge.IsChecked -or `
        $State.Controls.chkUpdateOneDrive.IsChecked -or `
        $State.Controls.chkUpdateLatestMSRT.IsChecked -or `
        $isLtscCuChecked
    
    $isForced = $anyUpdateChecked -or $installOfficeChk.IsChecked

    if ($isForced) {
        # If InstallApps is not already forced (i.e., it's enabled), save its current state.
        if ($installAppsChk.IsEnabled) {
            $State.Flags.prevInstallAppsState = $installAppsChk.IsChecked
        }
        $installAppsChk.IsChecked = $true
        $installAppsChk.IsEnabled = $false
    }
    else {
        # No longer forced. Restore the previous state if it was saved.
        if ($State.Flags.ContainsKey('prevInstallAppsState')) {
            $installAppsChk.IsChecked = $State.Flags.prevInstallAppsState
            $State.Flags.Remove('prevInstallAppsState') # Use the saved state only once
        }
        else {
            # If no state was saved (e.g., it was never forced), ensure it's unchecked.
            $installAppsChk.IsChecked = $false
        }
        
        # If BYO, Winget, or Apps Script Variables are checked, it overrides the restoration and keeps Install Apps checked.
        if ($State.Controls.chkBringYourOwnApps.IsChecked -or $State.Controls.chkInstallWingetApps.IsChecked -or $State.Controls.chkDefineAppsScriptVariables.IsChecked) {
            $installAppsChk.IsChecked = $true
        }

        $installAppsChk.IsEnabled = $true
    }
}

# Function to manage the enabled state of interdependent driver-related checkboxes
function Update-DriverCheckboxStates {
    param([PSCustomObject]$State)

    $installDriversChk = $State.Controls.chkInstallDrivers
    $copyDriversChk = $State.Controls.chkCopyDrivers
    $compressWimChk = $State.Controls.chkCompressDriversToWIM
    $copyPEDriversChk = $State.Controls.chkCopyPEDrivers
    $useDriversAsPeChk = $State.Controls.chkUseDriversAsPEDrivers

    # Default to enabled, then apply disabling rules
    $installDriversChk.IsEnabled = $true
    $copyDriversChk.IsEnabled = $true
    $compressWimChk.IsEnabled = $true
    $copyPEDriversChk.IsEnabled = $true

    if ($installDriversChk.IsChecked) {
        $copyDriversChk.IsEnabled = $false
        $compressWimChk.IsEnabled = $false
    }
    
    if ($copyDriversChk.IsChecked) {
        $installDriversChk.IsEnabled = $false
    }

    if ($compressWimChk.IsChecked) {
        $installDriversChk.IsEnabled = $false
    }

    # Sub-option visibility logic: only show UseDriversAsPEDrivers when CopyPEDrivers is checked
    if ($copyPEDriversChk.IsChecked) {
        $useDriversAsPeChk.Visibility = 'Visible'
    }
    else {
        # Parent unchecked: hide and clear sub-option
        $useDriversAsPeChk.IsChecked = $false
        $useDriversAsPeChk.Visibility = 'Collapsed'
    }
}

# Function to manage the visibility of Office UI panels
function Update-OfficePanelVisibility {
    param([PSCustomObject]$State)

    if ($State.Controls.chkInstallOffice.IsChecked) {
        $State.Controls.OfficePathStackPanel.Visibility = 'Visible'
        $State.Controls.OfficePathGrid.Visibility = 'Visible'
        $State.Controls.CopyOfficeConfigXMLStackPanel.Visibility = 'Visible'
        # Show/hide XML file path based on checkbox state
        $State.Controls.OfficeConfigurationXMLFileStackPanel.Visibility = if ($State.Controls.chkCopyOfficeConfigXML.IsChecked) { 'Visible' } else { 'Collapsed' }
        $State.Controls.OfficeConfigurationXMLFileGrid.Visibility = if ($State.Controls.chkCopyOfficeConfigXML.IsChecked) { 'Visible' } else { 'Collapsed' }
    }
    else {
        $State.Controls.OfficePathStackPanel.Visibility = 'Collapsed'
        $State.Controls.OfficePathGrid.Visibility = 'Collapsed'
        $State.Controls.CopyOfficeConfigXMLStackPanel.Visibility = 'Collapsed'
        $State.Controls.OfficeConfigurationXMLFileStackPanel.Visibility = 'Collapsed'
        $State.Controls.OfficeConfigurationXMLFileGrid.Visibility = 'Collapsed'
    }
}

# Function to manage the visibility of the driver download UI panels
function Update-DriverDownloadPanelVisibility {
    param([PSCustomObject]$State)

    if ($State.Controls.chkDownloadDrivers.IsChecked) {
        $State.Controls.spMakeSection.Visibility = 'Visible'
        $State.Controls.btnGetModels.Visibility = 'Visible'
        # The other panels are shown/hidden by the Get Models button click handler
    }
    else {
        $State.Controls.spMakeSection.Visibility = 'Collapsed'
        $State.Controls.btnGetModels.Visibility = 'Collapsed'
        $State.Controls.spModelFilterSection.Visibility = 'Collapsed'
        $State.Controls.lstDriverModels.Visibility = 'Collapsed'
        $State.Controls.spDriverActionButtons.Visibility = 'Collapsed'
        $State.Controls.lstDriverModels.ItemsSource = $null
        $State.Data.allDriverModels.Clear()
        $State.Controls.txtModelFilter.Text = ""
    }
}

# --------------------------------------------------------------------------
# SECTION: Home Page Build Status
# --------------------------------------------------------------------------

# Function to normalize release strings so local builds and GitHub tags compare consistently
function ConvertTo-NormalizedReleaseVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$Version
    )

    if ([string]::IsNullOrWhiteSpace($Version)) {
        return $null
    }

    $normalizedVersion = $Version.Trim().ToLowerInvariant()
    $normalizedVersion = $normalizedVersion -replace '^[v]', ''
    return $normalizedVersion
}

# Function to read the current FFU Builder build from the main build script
function Get-FFUBuilderCurrentBuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath
    )

    $buildScriptPath = Join-Path -Path $FFUDevelopmentPath -ChildPath 'BuildFFUVM.ps1'
    if (-not (Test-Path -Path $buildScriptPath)) {
        return 'Unknown'
    }

    try {
        $buildScriptContent = Get-Content -Path $buildScriptPath -Raw -ErrorAction Stop
        $versionMatch = [regex]::Match($buildScriptContent, '(?m)^\$version\s*=\s*''([^'']+)''')
        if ($versionMatch.Success) {
            return $versionMatch.Groups[1].Value
        }
    }
    catch {
        WriteLog "Unable to read the current FFU Builder build version: $($_.Exception.Message)"
    }

    return 'Unknown'
}

# Function to query GitHub for the latest published FFU Builder release
function Get-FFUBuilderLatestRelease {
    [CmdletBinding()]
    param()

    $releaseApiUri = 'https://api.github.com/repos/rbalsleyMSFT/FFU/releases/latest'
    $releaseHeaders = @{
        'User-Agent' = 'FFUBuilderUI'
        'Accept' = 'application/vnd.github+json'
    }

    $releaseResponse = Invoke-RestMethod -Uri $releaseApiUri -Headers $releaseHeaders -TimeoutSec 5 -ErrorAction Stop
    $releaseVersion = if (-not [string]::IsNullOrWhiteSpace([string]$releaseResponse.tag_name)) {
        [string]$releaseResponse.tag_name
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$releaseResponse.name)) {
        [string]$releaseResponse.name
    }
    else {
        $null
    }

    return [PSCustomObject]@{
        Version = $releaseVersion
        HtmlUrl = [string]$releaseResponse.html_url
        Body    = [string]$releaseResponse.body
    }
}

# Function to build a user-friendly release status message for the Home page
function Get-FFUBuilderReleaseStatusMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CurrentBuild,
        [Parameter(Mandatory = $true)]
        [string]$LatestRelease
    )

    # Format the release string for Home page display while keeping compare logic normalized
    $displayLatestRelease = if ([string]::IsNullOrWhiteSpace($LatestRelease)) {
        $LatestRelease
    }
    else {
        $LatestRelease -replace '^[vV]', ''
    }

    $normalizedCurrentBuild = ConvertTo-NormalizedReleaseVersion -Version $CurrentBuild
    $normalizedLatestRelease = ConvertTo-NormalizedReleaseVersion -Version $LatestRelease

    if ([string]::IsNullOrWhiteSpace($normalizedCurrentBuild)) {
        return 'Installed build information is unavailable.'
    }

    if ([string]::IsNullOrWhiteSpace($normalizedLatestRelease)) {
        return 'Unable to compare the installed build with the latest release.'
    }

    if ($normalizedCurrentBuild -eq $normalizedLatestRelease) {
        return 'You are running the latest published build.'
    }

    $currentVersionMatch = [regex]::Match($normalizedCurrentBuild, '^\d+(?:\.\d+){0,3}')
    $latestVersionMatch = [regex]::Match($normalizedLatestRelease, '^\d+(?:\.\d+){0,3}')

    if ($currentVersionMatch.Success -and $latestVersionMatch.Success) {
        try {
            $currentVersion = [version]$currentVersionMatch.Value
            $latestVersion = [version]$latestVersionMatch.Value

            if ($currentVersion -lt $latestVersion) {
                return "A newer release is available: $displayLatestRelease."
            }

            if ($currentVersion -gt $latestVersion) {
                return "This build is newer than the latest published release: $displayLatestRelease."
            }
        }
        catch {
            WriteLog "Unable to compare FFU Builder release versions numerically: $($_.Exception.Message)"
        }
    }

    return "Installed build $CurrentBuild differs from the latest published release $displayLatestRelease."
}

# Function to normalize a markdown heading for release-notes display
function ConvertTo-ReleaseNotesHeadingText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$Line
    )

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return ''
    }

    $cleanLine = $Line.Trim()
    $cleanLine = $cleanLine -replace '^#+\s*', ''
    $cleanLine = [regex]::Replace($cleanLine, '\[([^\]]+)\]\([^)]+\)', '$1')
    $cleanLine = $cleanLine -replace '\*\*', ''
    $cleanLine = $cleanLine -replace '`', ''
    return $cleanLine.Trim()
}

# Function to clean plain text segments before rendering markdown-aware inlines
function ConvertTo-ReleaseNotesPlainText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ''
    }

    $cleanText = $Text
    $cleanText = $cleanText -replace '\*\*', ''
    $cleanText = $cleanText -replace '`', ''
    return $cleanText
}

# Function to add markdown-aware inline content to a TextBlock
function Add-ReleaseNotesInlinesToTextBlock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Controls.TextBlock]$TextBlock,
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return
    }

    $matchPattern = '(?<MarkdownLink>\[(?<LinkText>[^\]]+)\]\((?<LinkUrl>https?://[^)\s]+)\))|(?<BareUrl>https?://[^\s)]+)|(?<Bold>\*\*(?<BoldText>.+?)\*\*)'
    $currentIndex = 0

    foreach ($match in [regex]::Matches($Text, $matchPattern)) {
        if ($match.Index -gt $currentIndex) {
            $plainText = ConvertTo-ReleaseNotesPlainText -Text $Text.Substring($currentIndex, $match.Index - $currentIndex)
            if (-not [string]::IsNullOrWhiteSpace($plainText)) {
                $TextBlock.Inlines.Add([System.Windows.Documents.Run]::new($plainText)) | Out-Null
            }
        }

        if ($match.Groups['MarkdownLink'].Success) {
            $hyperlink = [System.Windows.Documents.Hyperlink]::new()
            $hyperlink.NavigateUri = [System.Uri]$match.Groups['LinkUrl'].Value
            $hyperlink.ToolTip = $match.Groups['LinkUrl'].Value
            $hyperlink.Inlines.Add([System.Windows.Documents.Run]::new($match.Groups['LinkText'].Value)) | Out-Null
            $hyperlink.Add_RequestNavigate({
                    param($eventSource, $requestNavigateEventArgs)
                    Start-Process $requestNavigateEventArgs.Uri.AbsoluteUri
                    $requestNavigateEventArgs.Handled = $true
                })
            $TextBlock.Inlines.Add($hyperlink) | Out-Null
        }
        elseif ($match.Groups['BareUrl'].Success) {
            $bareUrl = $match.Groups['BareUrl'].Value.TrimEnd('.', ',', ';', ':')
            $hyperlink = [System.Windows.Documents.Hyperlink]::new()
            $hyperlink.NavigateUri = [System.Uri]$bareUrl
            $hyperlink.ToolTip = $bareUrl
            $hyperlink.Inlines.Add([System.Windows.Documents.Run]::new($bareUrl)) | Out-Null
            $hyperlink.Add_RequestNavigate({
                    param($eventSource, $requestNavigateEventArgs)
                    Start-Process $requestNavigateEventArgs.Uri.AbsoluteUri
                    $requestNavigateEventArgs.Handled = $true
                })
            $TextBlock.Inlines.Add($hyperlink) | Out-Null

            $trailingCharactersLength = $match.Groups['BareUrl'].Value.Length - $bareUrl.Length
            if ($trailingCharactersLength -gt 0) {
                $trailingCharacters = $match.Groups['BareUrl'].Value.Substring($bareUrl.Length, $trailingCharactersLength)
                $TextBlock.Inlines.Add([System.Windows.Documents.Run]::new($trailingCharacters)) | Out-Null
            }
        }
        elseif ($match.Groups['Bold'].Success) {
            $boldRun = [System.Windows.Documents.Run]::new((ConvertTo-ReleaseNotesPlainText -Text $match.Groups['BoldText'].Value))
            $boldRun.FontWeight = 'SemiBold'
            $TextBlock.Inlines.Add($boldRun) | Out-Null
        }

        $currentIndex = $match.Index + $match.Length
    }

    if ($currentIndex -lt $Text.Length) {
        $remainingText = ConvertTo-ReleaseNotesPlainText -Text $Text.Substring($currentIndex)
        if (-not [string]::IsNullOrWhiteSpace($remainingText)) {
            $TextBlock.Inlines.Add([System.Windows.Documents.Run]::new($remainingText)) | Out-Null
        }
    }
}

# Function to build a formatted UI element for a release-notes section body
function New-ReleaseNotesSectionContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$Content
    )

    $contentPanel = New-Object System.Windows.Controls.StackPanel
    $contentPanel.Margin = '0,2,0,2'

    foreach ($contentLine in ($Content -split "`r?`n")) {
        $trimmedLine = $contentLine.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmedLine)) {
            continue
        }

        $isFirstRenderedLine = ($contentPanel.Children.Count -eq 0)

        $textBlock = New-Object System.Windows.Controls.TextBlock
        $textBlock.TextWrapping = 'Wrap'
        $textBlock.Margin = if ($isFirstRenderedLine) { '0,2,0,0' } else { '0,12,0,0' }

        $lineContent = $trimmedLine
        $listItemMatch = [regex]::Match($trimmedLine, '^(?:[-*]|\d+\.)\s+(.+)$')
        if ($listItemMatch.Success) {
            $textBlock.Margin = if ($isFirstRenderedLine) { '0,2,0,0' } else { '0,10,0,0' }
            $textBlock.Inlines.Add([System.Windows.Documents.Run]::new([string][char]0x2022 + ' ')) | Out-Null
            $lineContent = $listItemMatch.Groups[1].Value
        }

        Add-ReleaseNotesInlinesToTextBlock -TextBlock $textBlock -Text $lineContent
        $contentPanel.Children.Add($textBlock) | Out-Null
    }

    if ($contentPanel.Children.Count -eq 0) {
        $fallbackTextBlock = New-Object System.Windows.Controls.TextBlock
        $fallbackTextBlock.Text = 'No additional details were published for this section.'
        $fallbackTextBlock.TextWrapping = 'Wrap'
        $fallbackTextBlock.Margin = '0,2,0,0'
        $contentPanel.Children.Add($fallbackTextBlock) | Out-Null
    }

    return $contentPanel
}

# Function to parse the full GitHub release notes into UI sections
function Get-FFUBuilderReleaseNotesSections {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$ReleaseNotesBody
    )

    $releaseNoteSections = [System.Collections.Generic.List[object]]::new()

    if ([string]::IsNullOrWhiteSpace($ReleaseNotesBody)) {
        $releaseNoteSections.Add([PSCustomObject]@{
                Title       = 'Release Notes'
                Content     = 'No release notes were published for this release.'
                UseExpander = $false
                IsExpanded  = $true
            })
        return $releaseNoteSections
    }

    $currentTitle = 'Release Overview'
    $currentLines = [System.Collections.Generic.List[string]]::new()

    foreach ($releaseNotesLine in ($ReleaseNotesBody -split "`r?`n")) {
        $trimmedLine = $releaseNotesLine.Trim()

        if ($trimmedLine -match '^#+\s*(.+)$') {
            $sectionContent = ($currentLines -join [Environment]::NewLine).Trim()
            if (-not [string]::IsNullOrWhiteSpace($sectionContent)) {
                $useExpander = (($sectionContent -split "`r?`n").Count -gt 2 -or $sectionContent.Length -gt 220)
                $releaseNoteSections.Add([PSCustomObject]@{
                        Title       = $currentTitle
                        Content     = $sectionContent
                        UseExpander = $useExpander
                        IsExpanded  = ($releaseNoteSections.Count -eq 0)
                    })
            }

            $currentTitle = ConvertTo-ReleaseNotesHeadingText -Line $matches[1]
            $currentLines = [System.Collections.Generic.List[string]]::new()
            continue
        }

        if ([string]::IsNullOrWhiteSpace($trimmedLine)) {
            if ($currentLines.Count -gt 0 -and $currentLines[$currentLines.Count - 1] -ne '') {
                $currentLines.Add('')
            }
            continue
        }

        $currentLines.Add($trimmedLine)
    }

    $finalSectionContent = ($currentLines -join [Environment]::NewLine).Trim()
    if (-not [string]::IsNullOrWhiteSpace($finalSectionContent)) {
        $useExpander = (($finalSectionContent -split "`r?`n").Count -gt 2 -or $finalSectionContent.Length -gt 220)
        $releaseNoteSections.Add([PSCustomObject]@{
                Title       = $currentTitle
                Content     = $finalSectionContent
                UseExpander = $useExpander
                IsExpanded  = ($releaseNoteSections.Count -eq 0)
            })
    }

    if ($releaseNoteSections.Count -eq 0) {
        $releaseNoteSections.Add([PSCustomObject]@{
                Title       = 'Release Notes'
                Content     = 'No release notes were published for this release.'
                UseExpander = $false
                IsExpanded  = $true
            })
    }

    return $releaseNoteSections
}

# Function to render formatted release notes into the Home page
function Set-HomeReleaseNotesContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$State,
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$ReleaseNotesBody
    )

    $releaseNotesPanel = $State.Controls.spHomeReleaseNotesSections
    if ($null -eq $releaseNotesPanel) {
        return
    }

    $releaseNotesPanel.Children.Clear()
    $releaseNoteSections = @(Get-FFUBuilderReleaseNotesSections -ReleaseNotesBody $ReleaseNotesBody)

    foreach ($releaseNoteSection in $releaseNoteSections) {
        $sectionContent = New-ReleaseNotesSectionContent -Content $releaseNoteSection.Content

        if ($releaseNoteSection.UseExpander) {
            $headerTextBlock = New-Object System.Windows.Controls.TextBlock
            $headerTextBlock.Text = $releaseNoteSection.Title
            $headerTextBlock.TextWrapping = 'Wrap'
            $headerTextBlock.FontWeight = 'SemiBold'

            $releaseNotesExpander = New-Object System.Windows.Controls.Expander
            $releaseNotesExpander.Header = $headerTextBlock
            $releaseNotesExpander.IsExpanded = [bool]$releaseNoteSection.IsExpanded
            $releaseNotesExpander.Margin = '0,0,0,8'
            $releaseNotesExpander.Content = $sectionContent

            $releaseNotesPanel.Children.Add($releaseNotesExpander) | Out-Null
        }
        else {
            $releaseNotesSectionPanel = New-Object System.Windows.Controls.StackPanel
            $releaseNotesSectionPanel.Margin = '0,0,0,8'

            if (-not [string]::IsNullOrWhiteSpace($releaseNoteSection.Title)) {
                $titleTextBlock = New-Object System.Windows.Controls.TextBlock
                $titleTextBlock.Text = $releaseNoteSection.Title
                $titleTextBlock.FontWeight = 'SemiBold'
                $titleTextBlock.TextWrapping = 'Wrap'
                $releaseNotesSectionPanel.Children.Add($titleTextBlock) | Out-Null
            }

            $releaseNotesSectionPanel.Children.Add($sectionContent) | Out-Null
            $releaseNotesPanel.Children.Add($releaseNotesSectionPanel) | Out-Null
        }
    }
}

# Function to return a Home page status light brush for environment checks
function Get-HomeStatusBrush {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Green', 'Yellow', 'Red')]
        [string]$Level
    )

    switch ($Level) {
        'Green' { return [System.Windows.Media.Brushes]::LimeGreen }
        'Yellow' { return [System.Windows.Media.Brushes]::Gold }
        'Red' { return [System.Windows.Media.Brushes]::IndianRed }
    }
}

# Function to evaluate free disk space on the drive hosting the FFU development path
function Get-FFUBuilderDiskSpaceStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath
    )

    try {
        $resolvedPath = if (Test-Path -Path $FFUDevelopmentPath) {
            (Resolve-Path -Path $FFUDevelopmentPath -ErrorAction Stop).Path
        }
        else {
            $FFUDevelopmentPath
        }

        $driveRoot = [System.IO.Path]::GetPathRoot($resolvedPath)
        if ([string]::IsNullOrWhiteSpace($driveRoot)) {
            throw "Unable to determine a drive root for path $FFUDevelopmentPath"
        }

        $driveInfo = [System.IO.DriveInfo]::new($driveRoot)
        $freeSpaceGb = [math]::Round($driveInfo.AvailableFreeSpace / 1GB, 2)

        if ($freeSpaceGb -lt 50) {
            return [PSCustomObject]@{
                Level = 'Red'
                Message = "$freeSpaceGb GB free on $driveRoot. FFU Builder is likely to run out of disk space and should have at least 100 GB free."
            }
        }

        if ($freeSpaceGb -lt 100) {
            return [PSCustomObject]@{
                Level = 'Yellow'
                Message = "$freeSpaceGb GB free on $driveRoot. FFU Builder recommends at least 100 GB free space."
            }
        }

        return [PSCustomObject]@{
            Level = 'Green'
            Message = "$freeSpaceGb GB free on $driveRoot. Free space is within the recommended range."
        }
    }
    catch {
        WriteLog "Unable to determine free disk space for FFUDevelopmentPath: $($_.Exception.Message)"
        return [PSCustomObject]@{
            Level = 'Red'
            Message = 'Unable to determine free disk space for the FFUDevelopmentPath drive.'
        }
    }
}

# Function to evaluate the local Hyper-V installation state
function Get-FFUBuilderHyperVStatus {
    [CmdletBinding()]
    param()

    try {
        $hyperVFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -ErrorAction Stop
        switch ([string]$hyperVFeature.State) {
            'Enabled' {
                return [PSCustomObject]@{
                    Level = 'Green'
                    Message = 'Hyper-V is installed and ready.'
                }
            }
            'EnablePending' {
                return [PSCustomObject]@{
                    Level = 'Yellow'
                    Message = 'Hyper-V is installed, but a reboot is required before it is ready.'
                }
            }
            default {
                return [PSCustomObject]@{
                    Level = 'Red'
                    Message = "Hyper-V is not installed. Current feature state: $($hyperVFeature.State)."
                }
            }
        }
    }
    catch {
        WriteLog "Unable to determine Hyper-V installation state: $($_.Exception.Message)"
        return [PSCustomObject]@{
            Level = 'Red'
            Message = 'Unable to determine the Hyper-V installation state.'
        }
    }
}

# Function to update the Home page release status fields
function Update-HomeReleaseStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$State,
        [Parameter(Mandatory = $true)]
        [string]$CurrentBuild,
        [Parameter(Mandatory = $true)]
        [string]$LatestRelease,
        [Parameter(Mandatory = $true)]
        [string]$StatusMessage,
        [Parameter(Mandatory = $true)]
        [string]$ReleaseNotesBody
    )

    if ($null -ne $State.Controls.txtHomeCurrentBuildValue) {
        $State.Controls.txtHomeCurrentBuildValue.Text = $CurrentBuild
    }

    if ($null -ne $State.Controls.txtHomeLatestReleaseValue) {
        $State.Controls.txtHomeLatestReleaseValue.Text = $LatestRelease
    }

    if ($null -ne $State.Controls.txtHomeReleaseStatusValue) {
        $State.Controls.txtHomeReleaseStatusValue.Text = $StatusMessage
    }

    # Render the full release notes into structured sections on the Home page
    Set-HomeReleaseNotesContent -State $State -ReleaseNotesBody $ReleaseNotesBody
}

# Function to update the Home page environment check fields
function Update-HomeEnvironmentStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$State,
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$DiskSpaceStatus,
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$HyperVStatus
    )

    if ($null -ne $State.Controls.ellipseHomeDiskSpaceStatus) {
        $State.Controls.ellipseHomeDiskSpaceStatus.Fill = Get-HomeStatusBrush -Level $DiskSpaceStatus.Level
    }

    if ($null -ne $State.Controls.txtHomeDiskSpaceStatusValue) {
        $State.Controls.txtHomeDiskSpaceStatusValue.Text = $DiskSpaceStatus.Message
    }

    if ($null -ne $State.Controls.ellipseHomeHyperVStatus) {
        $State.Controls.ellipseHomeHyperVStatus.Fill = Get-HomeStatusBrush -Level $HyperVStatus.Level
    }

    if ($null -ne $State.Controls.txtHomeHyperVStatusValue) {
        $State.Controls.txtHomeHyperVStatusValue.Text = $HyperVStatus.Message
    }
}

# Function to retrieve latest public GitHub discussions for Home page display
function Get-FFUBuilderLatestDiscussions {
    [CmdletBinding()]
    param()

    $discussionUri = 'https://github.com/rbalsleyMSFT/FFU/discussions'
    $discussionHeaders = @{
        'User-Agent' = 'FFUBuilderUI'
        'Accept' = 'text/html,application/xhtml+xml'
    }

    $discussionResponse = Invoke-WebRequest -Uri $discussionUri -Headers $discussionHeaders -TimeoutSec 5 -ErrorAction Stop
    $discussionContent = [string]$discussionResponse.Content
    $latestDiscussions = New-Object System.Collections.Generic.List[PSCustomObject]
    $seenDiscussionUrls = @{}

    # Parse the raw HTML instead of Invoke-WebRequest Links because GitHub's page structure
    # does not reliably surface the discussion topic anchors through the Links collection.
    $discussionMatches = [regex]::Matches(
        $discussionContent,
        '<a[^>]+href="(?<Href>/rbalsleyMSFT/FFU/discussions/(?<Id>\d+))"[^>]*>(?<InnerHtml>.*?)</a>',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Singleline
    )

    foreach ($discussionMatch in $discussionMatches) {
        $discussionHref = [string]$discussionMatch.Groups['Href'].Value
        $discussionUrl = "https://github.com$discussionHref"

        if ($seenDiscussionUrls.ContainsKey($discussionUrl)) {
            continue
        }

        $discussionInnerHtml = [string]$discussionMatch.Groups['InnerHtml'].Value
        $discussionTitle = [regex]::Replace($discussionInnerHtml, '<[^>]+>', ' ')
        $discussionTitle = [System.Net.WebUtility]::HtmlDecode($discussionTitle)
        $discussionTitle = [regex]::Replace($discussionTitle, '\s+', ' ').Trim()

        if ([string]::IsNullOrWhiteSpace($discussionTitle)) {
            continue
        }

        # Skip links that resolve to comment counts or other numeric-only link text.
        if ($discussionTitle -match '^\d+$') {
            continue
        }

        $seenDiscussionUrls[$discussionUrl] = $true
        $latestDiscussions.Add([PSCustomObject]@{
                Title = $discussionTitle
                Url   = $discussionUrl
            })

        if ($latestDiscussions.Count -ge 5) {
            break
        }
    }

    return $latestDiscussions
}

# Function to update the Home page discussions card
function Update-HomeDiscussions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$State,
        [Parameter(Mandatory = $true)]
        [string]$StatusMessage,
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [System.Collections.IEnumerable]$Discussions
    )

    if ($null -ne $State.Controls.txtHomeDiscussionsStatusValue) {
        $State.Controls.txtHomeDiscussionsStatusValue.Text = $StatusMessage
    }

    $discussionItems = @($Discussions)
    for ($index = 1; $index -le 5; $index++) {
        $container = $State.Controls["tbDiscussion$index"]
        $link = $State.Controls["linkDiscussion$index"]
        $run = $State.Controls["runDiscussion$index"]

        if ($null -eq $container -or $null -eq $link -or $null -eq $run) {
            continue
        }

        if ($index -le $discussionItems.Count -and $null -ne $discussionItems[$index - 1]) {
            $discussionItem = $discussionItems[$index - 1]
            $run.Text = $discussionItem.Title
            $link.NavigateUri = [System.Uri]$discussionItem.Url
            $container.Visibility = 'Visible'
        }
        else {
            $run.Text = ''
            $link.NavigateUri = [System.Uri]'https://github.com/rbalsleyMSFT/FFU/discussions'
            $container.Visibility = 'Collapsed'
        }
    }

    if ($null -ne $State.Controls.tbDiscussionsLink) {
        $State.Controls.tbDiscussionsLink.Visibility = 'Visible'
    }
}

# Function to populate the Home page build status after the window has rendered
function Start-HomeStatusRefresh {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$State
    )

    # Populate local status checks immediately so Home is useful even before network requests complete
    $currentBuild = Get-FFUBuilderCurrentBuild -FFUDevelopmentPath $State.FFUDevelopmentPath
    $diskSpaceStatus = Get-FFUBuilderDiskSpaceStatus -FFUDevelopmentPath $State.FFUDevelopmentPath
    $hyperVStatus = Get-FFUBuilderHyperVStatus

    Update-HomeReleaseStatus -State $State -CurrentBuild $currentBuild -LatestRelease 'Checking GitHub...' -StatusMessage 'Checking whether this build is current...' -ReleaseNotesBody 'Checking latest release notes...'
    Update-HomeEnvironmentStatus -State $State -DiskSpaceStatus $diskSpaceStatus -HyperVStatus $hyperVStatus
    Update-HomeDiscussions -State $State -StatusMessage 'Checking latest discussions...' -Discussions @()

    if ($null -eq $State.Window) {
        return
    }

    # Capture the state values before dispatching to avoid losing them in the deferred callback
    $refreshState = $State
    $refreshCurrentBuild = $currentBuild
    $refreshAction = {
        $latestReleaseDisplay = 'Unable to check'
        $statusMessage = 'Unable to check the latest release right now. Check GitHub Releases when you are back online.'
        $releaseNotesBody = 'Unable to load the latest release notes right now.'
        $discussionsStatusMessage = 'Unable to load the latest GitHub discussions right now.'
        $latestDiscussions = @()

        try {
            $latestRelease = Get-FFUBuilderLatestRelease
            if ($null -ne $latestRelease -and -not [string]::IsNullOrWhiteSpace($latestRelease.Version)) {
                # Strip the GitHub tag prefix so Home shows the same style as the installed build
                $latestReleaseDisplay = $latestRelease.Version -replace '^[vV]', ''
                $statusMessage = Get-FFUBuilderReleaseStatusMessage -CurrentBuild $refreshCurrentBuild -LatestRelease $latestRelease.Version
                $releaseNotesBody = if ([string]::IsNullOrWhiteSpace($latestRelease.Body)) {
                    'No release notes were published for this release.'
                }
                else {
                    $latestRelease.Body
                }
            }
        }
        catch {
            WriteLog "Unable to retrieve the latest FFU Builder release: $($_.Exception.Message)"
        }

        try {
            $latestDiscussions = @(Get-FFUBuilderLatestDiscussions)
            if ($latestDiscussions.Count -gt 0) {
                $discussionsStatusMessage = 'Latest public GitHub discussions.'
            }
            else {
                $discussionsStatusMessage = 'No recent public discussion topics were found.'
            }
        }
        catch {
            WriteLog "Unable to retrieve the latest FFU Builder discussions: $($_.Exception.Message)"
        }

        Update-HomeReleaseStatus -State $refreshState -CurrentBuild $refreshCurrentBuild -LatestRelease $latestReleaseDisplay -StatusMessage $statusMessage -ReleaseNotesBody $releaseNotesBody
        Update-HomeDiscussions -State $refreshState -StatusMessage $discussionsStatusMessage -Discussions $latestDiscussions
    }.GetNewClosure()

    # Queue the network checks after the UI renders so startup remains responsive
    $null = $State.Window.Dispatcher.BeginInvoke(
        [System.Action]$refreshAction,
        [System.Windows.Threading.DispatcherPriority]::Background
    )
}

# --------------------------------------------------------------------------
# SECTION: Module Export
# --------------------------------------------------------------------------

# Export only the functions intended for public use by the UI script
Export-ModuleMember -Function *
