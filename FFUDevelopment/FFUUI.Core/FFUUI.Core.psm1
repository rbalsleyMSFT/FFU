# FFU UI Core Logic Module
# Contains non-UI specific helper functions, data retrieval, and core processing logic.

# --------------------------------------------------------------------------
# SECTION: Module Variables (Static Data & State)
# --------------------------------------------------------------------------

#Microsoft sites will intermittently fail on downloads. These headers and user agent are to help with that.
$script:Headers = @{
    "Accept"                    = "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7"
    "Accept-Encoding"           = "gzip, deflate, br, zstd"
    "Accept-Language"           = "en-US,en;q=0.9"
    "Priority"                  = "u=0, i"
    "Sec-Ch-Ua"                 = "`"Microsoft Edge`";v=`"125`", `"Chromium`";v=`"125`", `"Not.A/Brand`";v=`"24`""
    "Sec-Ch-Ua-Mobile"          = "?0"
    "Sec-Ch-Ua-Platform"        = "`"Windows`""
    "Sec-Fetch-Dest"            = "document"
    "Sec-Fetch-Mode"            = "navigate"
    "Sec-Fetch-Site"            = "none"
    "Sec-Fetch-User"            = "?1"
    "Upgrade-Insecure-Requests" = "1"
}
$script:UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36 Edg/125.0.0.0'

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
        CustomFFUNameTemplate       = "{WindowsRelease}_{WindowsVersion}_{SKU}_{yyyy}-{MM}-{dd}_{HH}{mm}"
        FFUCaptureLocation          = $ffuCapturePath
        ShareName                   = "FFUCaptureShare"
        Username                    = "ffu_user"
        BuildUSBDriveEnable         = $false
        CompactOS                   = $true
        Optimize                    = $true
        AllowVHDXCaching            = $false
        CreateCaptureMedia          = $true
        CreateDeploymentMedia       = $true
        AllowExternalHardDiskMedia  = $false
        PromptExternalHardDiskMedia = $true
        SelectSpecificUSBDrives     = $false
        CopyAutopilot               = $false
        CopyUnattend                = $false
        CopyPPKG                    = $false
        CleanupAppsISO              = $true
        CleanupCaptureISO           = $true
        CleanupDeployISO            = $true
        CleanupDrivers              = $false
        RemoveFFU                   = $false
        RemoveApps                  = $false 
        RemoveUpdates               = $false 
        # Hyper-V Settings Defaults
        VMHostIPAddress             = ""
        DiskSizeGB                  = 30
        MemoryGB                    = 4
        Processors                  = 4
        VMLocation                  = $vmLocationPath
        VMNamePrefix                = "_FFU"
        LogicalSectorSize           = 512
        # Updates Tab Defaults
        UpdateLatestCU              = $true
        UpdateLatestNet             = $true
        UpdateLatestDefender        = $true
        UpdateEdge                  = $true
        UpdateOneDrive              = $true
        UpdateLatestMSRT            = $true
        UpdateLatestMicrocode       = $false
        UpdatePreviewCU             = $false
        # Applications Tab Defaults
        InstallApps                 = $false
        ApplicationPath             = $appsPath
        AppListJsonPath             = $appListJsonPath
        InstallWingetApps           = $false
        BringYourOwnApps            = $false
        # M365 Apps/Office Tab Defaults
        InstallOffice               = $true
        OfficePath                  = $officePath
        CopyOfficeConfigXML         = $false
        OfficeConfigXMLFilePath     = ""
        # Drivers Tab Defaults
        DriversFolder               = $driversPath
        PEDriversFolder             = $peDriversPath
        DriversJsonPath             = $driversJsonPath
        DownloadDrivers             = $false
        InstallDrivers              = $false
        CopyDrivers                 = $false
        CopyPEDrivers               = $false
        UpdateADK                   = $true
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

# --------------------------------------------------------------------------
# SECTION: Module Export
# --------------------------------------------------------------------------

# Export only the functions intended for public use by the UI script
Export-ModuleMember -Function *
