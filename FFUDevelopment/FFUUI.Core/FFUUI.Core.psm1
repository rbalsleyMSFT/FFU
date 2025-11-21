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
    $driversJsonPath = Join-Path -Path $driversPath -ChildPath "Drivers.json"

    return [PSCustomObject]@{
        # Build Tab Defaults
        CustomFFUNameTemplate          = "{WindowsRelease}_{WindowsVersion}_{SKU}_{yyyy}-{MM}-{dd}_{HH}{mm}"
        FFUCaptureLocation             = $ffuCapturePath
        ShareName                      = "FFUCaptureShare"
        Username                       = "ffu_user"
        Threads                        = 5
        BitsPriority                   = 'Normal'
        MaxUSBDrives                   = 5
        BuildUSBDriveEnable            = $false
        CompactOS                      = $true
        Optimize                       = $true
        AllowVHDXCaching               = $false
        CreateCaptureMedia             = $true
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
        CleanupCaptureISO              = $true
        CleanupDeployISO               = $true
        CleanupDrivers                 = $false
        RemoveFFU                      = $false
        RemoveApps                     = $false 
        RemoveUpdates                  = $false 
        # Hyper-V Settings Defaults
        VMHostIPAddress                = ""
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
function Get-USBDrives {
    Get-WmiObject Win32_DiskDrive | Where-Object {
        ($_.MediaType -eq 'Removable Media' -or $_.MediaType -eq 'External hard disk media')
    } | ForEach-Object {
        $size = [math]::Round($_.Size / 1GB, 2)
        $serialNumber = if ($_.SerialNumber) { $_.SerialNumber.Trim() } else { "N/A" }
        @{
            IsSelected   = $false
            Model        = $_.Model.Trim()
            SerialNumber = $serialNumber
            Size         = $size
            DriveIndex   = $_.Index
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

# Function to manage the state of the main "Install Apps" checkbox based on selections in Updates/Office
function Update-InstallAppsState {
    param([PSCustomObject]$State)

    $installAppsChk = $State.Controls.chkInstallApps
    $installOfficeChk = $State.Controls.chkInstallOffice

    # Determine if any checkbox that forces "Install Apps" is checked
    $anyUpdateChecked = $State.Controls.chkUpdateLatestDefender.IsChecked -or `
        $State.Controls.chkUpdateEdge.IsChecked -or `
        $State.Controls.chkUpdateOneDrive.IsChecked -or `
        $State.Controls.chkUpdateLatestMSRT.IsChecked
    
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
# SECTION: Module Export
# --------------------------------------------------------------------------

# Export only the functions intended for public use by the UI script
Export-ModuleMember -Function *
