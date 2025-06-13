# FFU UI Core Logic Module
# Contains non-UI specific helper functions, data retrieval, and core processing logic.

#Requires -Modules BitsTransfer 

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

$script:allowedFeatures = @(
    "AppServerClient", "Client-DeviceLockdown", "Client-EmbeddedBootExp", "Client-EmbeddedLogon",
    "Client-EmbeddedShellLauncher", "Client-KeyboardFilter", "Client-ProjFS", "Client-UnifiedWriteFilter",
    "Containers", "Containers-DisposableClientVM", "Containers-HNS", "Containers-SDN", "DataCenterBridging",
    "DirectoryServices-ADAM-Client", "DirectPlay", "HostGuardian", "HypervisorPlatform", "IIS-ApplicationDevelopment",
    "IIS-ApplicationInit", "IIS-ASP", "IIS-ASPNET45", "IIS-BasicAuthentication", "IIS-CertProvider",
    "IIS-CGI", "IIS-ClientCertificateMappingAuthentication", "IIS-CommonHttpFeatures", "IIS-CustomLogging",
    "IIS-DefaultDocument", "IIS-DirectoryBrowsing", "IIS-DigestAuthentication", "IIS-ESP", "IIS-FTPServer",
    "IIS-FTPExtensibility", "IIS-FTPSvc", "IIS-HealthAndDiagnostics", "IIS-HostableWebCore", "IIS-HttpCompressionDynamic",
    "IIS-HttpCompressionStatic", "IIS-HttpErrors", "IIS-HttpLogging", "IIS-HttpRedirect", "IIS-HttpTracing",
    "IIS-IPSecurity", "IIS-IIS6ManagementCompatibility", "IIS-IISCertificateMappingAuthentication",
    "IIS-ISAPIExtensions", "IIS-ISAPIFilter", "IIS-LoggingLibraries", "IIS-ManagementConsole", "IIS-ManagementService",
    "IIS-ManagementScriptingTools", "IIS-Metabase", "IIS-NetFxExtensibility", "IIS-NetFxExtensibility45",
    "IIS-ODBCLogging", "IIS-Performance", "IIS-RequestFiltering", "IIS-RequestMonitor", "IIS-Security", "IIS-ServerSideIncludes",
    "IIS-StaticContent", "IIS-URLAuthorization", "IIS-WebDAV", "IIS-WebServer", "IIS-WebServerManagementTools",
    "IIS-WebServerRole", "IIS-WebSockets", "LegacyComponents", "MediaPlayback", "Microsoft-Hyper-V", "Microsoft-Hyper-V-All",
    "Microsoft-Hyper-V-Hypervisor", "Microsoft-Hyper-V-Management-Clients", "Microsoft-Hyper-V-Management-PowerShell",
    "Microsoft-Hyper-V-Services", "Microsoft-Windows-Subsystem-Linux", "MSMQ-ADIntegration", "MSMQ-Container", "MSMQ-DCOMProxy",
    "MSMQ-HTTP", "MSMQ-Multicast", "MSMQ-Server", "MSMQ-Triggers", "MultiPoint-Connector", "MultiPoint-Connector-Services",
    "MultiPoint-Tools", "NetFx3", "NetFx4-AdvSrvs", "NetFx4Extended-ASPNET45", "NFS-Administration", "Printing-Foundation-Features",
    "Printing-Foundation-InternetPrinting-Client", "Printing-Foundation-LPDPrintService", "Printing-Foundation-LPRPortMonitor",
    "Printing-PrintToPDFServices-Features", "Printing-XPSServices-Features", "SearchEngine-Client-Package",
    "ServicesForNFS-ClientOnly", "SimpleTCP", "SMB1Protocol", "SMB1Protocol-Client", "SMB1Protocol-Deprecation",
    "SMB1Protocol-Server", "SmbDirect", "TFTP", "TelnetClient", "TIFFIFilter", "VirtualMachinePlatform", "WAS-ConfigurationAPI",
    "WAS-NetFxEnvironment", "WAS-ProcessModel", "WAS-WindowsActivationService", "WCF-HTTP-Activation", "WCF-HTTP-Activation45",
    "WCF-MSMQ-Activation45", "WCF-MSMQ-Activation", "WCF-NonHTTP-Activation", "WCF-Pipe-Activation45", "WCF-Services45",
    "WCF-TCP-Activation45", "WCF-TCP-PortSharing45", "Windows-Defender-ApplicationGuard",
    "Windows-Defender-Default-Definitions", "Windows-Identity-Foundation", "WindowsMediaPlayer", "WorkFolders-Client"
)

$script:skuList = @(
    'Home',
    'Home N',
    'Home Single Language',
    'Education',
    'Education N',
    'Pro',
    'Pro N',
    'Pro Education',
    'Pro Education N',
    'Pro for Workstations',
    'Pro N for Workstations',
    'Enterprise',
    'Enterprise N',
    'Enterprise 2016 LTSB',
    'Enterprise N 2016 LTSB',
    'Enterprise LTSC',
    'Enterprise N LTSC',
    'IoT Enterprise LTSC',
    'IoT Enterprise N LTSC',
    'Standard',
    'Standard (Desktop Experience)',
    'Datacenter',
    'Datacenter (Desktop Experience)'
)

$script:allowedLangs = @(
    'ar-sa', 'bg-bg', 'cs-cz', 'da-dk', 'de-de', 'el-gr', 'en-gb', 'en-us', 'es-es', 'es-mx', 'et-ee',
    'fi-fi', 'fr-ca', 'fr-fr', 'he-il', 'hr-hr', 'hu-hu', 'it-it', 'ja-jp', 'ko-kr', 'lt-lt', 'lv-lv',
    'nb-no', 'nl-nl', 'pl-pl', 'pt-br', 'pt-pt', 'ro-ro', 'ru-ru', 'sk-sk', 'sl-si', 'sr-latn-rs',
    'sv-se', 'th-th', 'tr-tr', 'uk-ua', 'zh-cn', 'zh-tw'
)

$script:allWindowsReleases = @(
    [PSCustomObject]@{ Display = "Windows 10"; Value = 10 },
    [PSCustomObject]@{ Display = "Windows 11"; Value = 11 },
    [PSCustomObject]@{ Display = "Windows Server 2016"; Value = 2016 },
    [PSCustomObject]@{ Display = "Windows Server 2019"; Value = 2019 },
    [PSCustomObject]@{ Display = "Windows Server 2022"; Value = 2022 },
    [PSCustomObject]@{ Display = "Windows Server 2025"; Value = 2025 },
    [PSCustomObject]@{ Display = "Windows 10 LTSB 2016"; Value = 2016 }, # Changed Value from 1607
    [PSCustomObject]@{ Display = "Windows 10 LTSC 2019"; Value = 2019 }, # Changed Value from 1809
    [PSCustomObject]@{ Display = "Windows 10 LTSC 2021"; Value = 2021 },
    [PSCustomObject]@{ Display = "Windows 10 LTSC 2024"; Value = 2024 }
)

$script:mctWindowsReleases = @(
    [PSCustomObject]@{ Display = "Windows 10"; Value = 10 },
    [PSCustomObject]@{ Display = "Windows 11"; Value = 11 }
)

$script:windowsVersionMap = @{
    10   = @("22H2")
    11   = @("22H2", "23H2", "24H2")
    2016 = @("1607") # Windows 10 LTSB 2016 & Server 2016
    2019 = @("1809") # Windows 10 LTSC 2019 & Server 2019
    # Note: Server 2016 and LTSB 2016 now share the key 2016, mapping to version "1607"
    # Note: Server 2019 and LTSC 2019 now share the key 2019, mapping to version "1809"
    2021 = @("21H2") # LTSC 2021
    2022 = @("21H2") # Server 2022
    2024 = @("24H2") # LTSC 2024
    2025 = @("24H2") # Server 2025
}

# SKU Groups
$script:clientSKUs = @(
    'Home',
    'Home N',
    'Home Single Language',
    'Education',
    'Education N',
    'Pro',
    'Pro N',
    'Pro Education',
    'Pro Education N',
    'Pro for Workstations',
    'Pro N for Workstations',
    'Enterprise',
    'Enterprise N'
)

$script:serverSKUs = @(
    'Standard',
    'Standard (Desktop Experience)',
    'Datacenter',
    'Datacenter (Desktop Experience)'
)

$script:ltsc2016SKUs = @(
    'Enterprise 2016 LTSB',
    'Enterprise N 2016 LTSB'
)

$script:ltscGenericSKUs = @( # For LTSC 2019, 2021, 2024
    'Enterprise LTSC',
    'Enterprise N LTSC'
)

$script:iotLtscSKUs = @(
    'IoT Enterprise LTSC',
    'IoT Enterprise N LTSC'
    # Note: IoT SKUs are often specialized and might have different edition IDs.
    # This list is a general representation. Actual ISOs might be needed for specific IoT LTSC editions.
)

# Map Windows Release Values to their corresponding SKU lists
$script:windowsReleaseSkuMap = @{
    10   = $script:clientSKUs # Windows 10 Client
    11   = $script:clientSKUs # Windows 11 Client
    2016 = $script:serverSKUs # Windows Server 2016 (LTSB 2016 handled by Get-AvailableSkusForRelease)
    2019 = $script:serverSKUs # Windows Server 2019 (LTSC 2019 handled by Get-AvailableSkusForRelease)
    2022 = $script:serverSKUs # Windows Server 2022
    2025 = $script:serverSKUs # Windows Server 2025
    2021 = $script:ltscGenericSKUs + $script:iotLtscSKUs # Windows 10 LTSC 2021
    2024 = $script:ltscGenericSKUs + $script:iotLtscSKUs # Windows 10 LTSC 2024
    # Note: LTSC 2016 and LTSC 2019 SKUs are now conditionally returned by Get-AvailableSkusForRelease
}
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

# Function to return the default settings and static lists (Moved from UI_Helpers)
function Get-WindowsSettingsDefaults {
    [CmdletBinding()]
    param()

    return [PSCustomObject]@{
        DefaultISOPath          = ""
        DefaultWindowsArch      = "x64"
        DefaultWindowsLang      = "en-us"
        DefaultWindowsSKU       = "Pro"
        DefaultMediaType        = "Consumer"
        DefaultOptionalFeatures = ""
        DefaultProductKey       = ""
        AllowedFeatures         = $script:allowedFeatures
        AllowedLanguages        = $script:allowedLangs
        AllowedArchitectures    = @('x86', 'x64', 'arm64')
        AllowedMediaTypes       = @('Consumer', 'Business')
    }
}

# Function to get the appropriate list of Windows Releases based on ISO path (Moved from UI_Helpers)
function Get-AvailableWindowsReleases {
    [CmdletBinding()]
    param(
        [string]$IsoPath,
        [Parameter(Mandatory = $true)]
        [psobject]$State
    )

    if ([string]::IsNullOrEmpty($IsoPath)) {
        return $State.Defaults.GeneralDefaults.MctWindowsReleases
    }
    else {
        return $State.Defaults.GeneralDefaults.AllWindowsReleases
    }
}

# Function to get available Windows Versions for a given release and ISO path (Moved from UI_Helpers)
function Get-AvailableWindowsVersions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$SelectedRelease,

        [string]$IsoPath,
        [Parameter(Mandatory = $true)]
        [psobject]$State
    )

    $result = [PSCustomObject]@{
        Versions       = @()
        DefaultVersion = $null
        IsEnabled      = $false
    }

    if (-not $State.Defaults.GeneralDefaults.WindowsVersionMap.ContainsKey($SelectedRelease)) {
        return $result 
    }

    $validVersions = $State.Defaults.GeneralDefaults.WindowsVersionMap[$SelectedRelease]

    if ([string]::IsNullOrEmpty($IsoPath)) {
        # Logic for when no ISO is specified (MCT scenario)
        switch ($SelectedRelease) {
            10 { $result.DefaultVersion = "22H2" }
            11 { $result.DefaultVersion = "24H2" }
            # Server versions typically require an ISO, but handle just in case
            2016 { $result.DefaultVersion = "1607" }
            2019 { $result.DefaultVersion = "1809" }
            2022 { $result.DefaultVersion = "21H2" }
            2025 { $result.DefaultVersion = "24H2" }
            default { $result.DefaultVersion = $validVersions[0] }
        }
        $result.Versions = @($result.DefaultVersion) # Only the default is available/relevant
        $result.IsEnabled = $false # Combo should be disabled
    }
    else {
        # Logic for when an ISO is specified
        $result.Versions = $validVersions
        # Set default selection logic (e.g., latest for Win11)
        if ($SelectedRelease -eq 11 -and $validVersions -contains "24H2") {
            $result.DefaultVersion = "24H2"
        }
        elseif ($validVersions.Count -gt 0) {
            $result.DefaultVersion = $validVersions[0]
        }
        $result.IsEnabled = $true 
    }

    return $result
}

# Function to get available SKUs for a given Windows Release value and display name
function Get-AvailableSkusForRelease {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$SelectedReleaseValue,

        [Parameter(Mandatory)]
        [string]$SelectedReleaseDisplayName,
        [Parameter(Mandatory = $true)]
        [psobject]$State
    )

    WriteLog "Get-AvailableSkusForRelease: Getting SKUs for Release Value '$SelectedReleaseValue', Display Name '$SelectedReleaseDisplayName'."

    # Handle LTSC 2016 specifically
    if ($SelectedReleaseValue -eq 2016 -and $SelectedReleaseDisplayName -like '*LTSB*') {
        WriteLog "Get-AvailableSkusForRelease: Matched LTSB 2016. Returning LTSC 2016 SKUs."
        return $State.Defaults.GeneralDefaults.Ltsc2016SKUs
    }
    # Handle LTSC 2019 specifically
    # Ensure "Server" is not in the display name to avoid matching "Windows Server 2019"
    elseif ($SelectedReleaseValue -eq 2019 -and $SelectedReleaseDisplayName -like '*LTSC*' -and $SelectedReleaseDisplayName -notlike '*Server*') {
        WriteLog "Get-AvailableSkusForRelease: Matched LTSC 2019. Returning generic LTSC SKUs (including IoT)."
        # Assuming LTSC 2019 uses the generic LTSC SKUs + IoT LTSC SKUs
        return ($State.Defaults.GeneralDefaults.LtscGenericSKUs + $State.Defaults.GeneralDefaults.IotLtscSKUs | Select-Object -Unique)
    }
    # For all other cases, use the main SKU map
    elseif ($State.Defaults.GeneralDefaults.WindowsReleaseSkuMap.ContainsKey($SelectedReleaseValue)) {
        $availableSkus = $State.Defaults.GeneralDefaults.WindowsReleaseSkuMap[$SelectedReleaseValue]
        WriteLog "Get-AvailableSkusForRelease: Found $($availableSkus.Count) SKUs for Release '$SelectedReleaseValue' using standard map."
        return $availableSkus
    }
    else {
        WriteLog "Get-AvailableSkusForRelease: Warning - Release Value '$SelectedReleaseValue' not found in SKU map. Returning default client SKUs."
        # Fallback to a default list (e.g., client SKUs) or an empty list
        return $State.Defaults.GeneralDefaults.ClientSKUs
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
        UpdateADK                      = $true
        # Static Data Lists/Maps
        AllowedFeatures         = $script:allowedFeatures
        SkuList                 = $script:skuList
        AllowedLanguages        = $script:allowedLangs
        AllWindowsReleases      = $script:allWindowsReleases
        MctWindowsReleases      = $script:mctWindowsReleases
        WindowsVersionMap       = $script:windowsVersionMap
        ClientSKUs              = $script:clientSKUs
        ServerSKUs              = $script:serverSKUs
        Ltsc2016SKUs            = $script:ltsc2016SKUs
        LtscGenericSKUs         = $script:ltscGenericSKUs
        IotLtscSKUs             = $script:iotLtscSKUs
        WindowsReleaseSkuMap    = $script:windowsReleaseSkuMap
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

# --------------------------------------------------------------------------
# SECTION: UI Configuration
# --------------------------------------------------------------------------
function Get-UIConfig {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$State
    )
    # Create hash to store configuration
    $config = [ordered]@{
        AllowExternalHardDiskMedia     = $State.Controls.chkAllowExternalHardDiskMedia.IsChecked
        AllowVHDXCaching               = $State.Controls.chkAllowVHDXCaching.IsChecked
        AppListPath                    = $State.Controls.txtAppListJsonPath.Text
        AppsPath                       = $State.Controls.txtApplicationPath.Text
        AppsScriptVariables            = if ($State.Controls.chkDefineAppsScriptVariables.IsChecked) {
            $vars = @{}
            foreach ($item in $State.Data.appsScriptVariablesDataList) {
                $vars[$item.Key] = $item.Value
            }
            if ($vars.Count -gt 0) { $vars } else { $null }
        }
        else { $null }
        BuildUSBDrive                  = $State.Controls.chkBuildUSBDriveEnable.IsChecked
        CleanupAppsISO                 = $State.Controls.chkCleanupAppsISO.IsChecked
        CleanupCaptureISO              = $State.Controls.chkCleanupCaptureISO.IsChecked
        CleanupDeployISO               = $State.Controls.chkCleanupDeployISO.IsChecked
        CleanupDrivers                 = $State.Controls.chkCleanupDrivers.IsChecked
        CompactOS                      = $State.Controls.chkCompactOS.IsChecked
        CompressDownloadedDriversToWim = $State.Controls.chkCompressDriversToWIM.IsChecked
        CopyAutopilot                  = $State.Controls.chkCopyAutopilot.IsChecked
        CopyDrivers                    = $State.Controls.chkCopyDrivers.IsChecked
        CopyOfficeConfigXML            = $State.Controls.chkCopyOfficeConfigXML.IsChecked
        CopyPEDrivers                  = $State.Controls.chkCopyPEDrivers.IsChecked
        CopyPPKG                       = $State.Controls.chkCopyPPKG.IsChecked
        CopyUnattend                   = $State.Controls.chkCopyUnattend.IsChecked
        CreateCaptureMedia             = $State.Controls.chkCreateCaptureMedia.IsChecked
        CreateDeploymentMedia          = $State.Controls.chkCreateDeploymentMedia.IsChecked
        CustomFFUNameTemplate          = $State.Controls.txtCustomFFUNameTemplate.Text
        Disksize                       = [int64]$State.Controls.txtDiskSize.Text * 1GB
        DownloadDrivers                = $State.Controls.chkDownloadDrivers.IsChecked
        DriversFolder                  = $State.Controls.txtDriversFolder.Text
        DriversJsonPath                = $State.Controls.txtDriversJsonPath.Text
        FFUCaptureLocation             = $State.Controls.txtFFUCaptureLocation.Text
        FFUDevelopmentPath             = $State.Controls.txtFFUDevPath.Text
        FFUPrefix                      = $State.Controls.txtVMNamePrefix.Text
        InstallApps                    = $State.Controls.chkInstallApps.IsChecked
        InstallDrivers                 = $State.Controls.chkInstallDrivers.IsChecked
        InstallOffice                  = $State.Controls.chkInstallOffice.IsChecked
        InstallWingetApps              = $State.Controls.chkInstallWingetApps.IsChecked
        ISOPath                        = $State.Controls.txtISOPath.Text
        LogicalSectorSizeBytes         = [int]$State.Controls.cmbLogicalSectorSize.SelectedItem.Content
        Make                           = $State.Controls.cmbMake.SelectedItem
        MediaType                      = $State.Controls.cmbMediaType.SelectedItem
        Memory                         = [int64]$State.Controls.txtMemory.Text * 1GB
        Model                          = if ($State.Controls.chkDownloadDrivers.IsChecked) {
            $selectedModels = $State.Controls.lstDriverModels.Items | Where-Object { $_.IsSelected }
            if ($selectedModels.Count -ge 1) {
                $selectedModels[0].Model
            }
            else {
                $null
            }
        }
        else {
            $null
        }
        OfficeConfigXMLFile            = $State.Controls.txtOfficeConfigXMLFilePath.Text
        OfficePath                     = $State.Controls.txtOfficePath.Text
        Optimize                       = $State.Controls.chkOptimize.IsChecked
        OptionalFeatures               = $State.Controls.txtOptionalFeatures.Text
        OrchestrationPath              = "$($State.Controls.txtApplicationPath.Text)\Orchestration"
        PEDriversFolder                = $State.Controls.txtPEDriversFolder.Text
        Processors                     = [int]$State.Controls.txtProcessors.Text
        ProductKey                     = $State.Controls.txtProductKey.Text
        PromptExternalHardDiskMedia    = $State.Controls.chkPromptExternalHardDiskMedia.IsChecked
        RemoveApps                     = $State.Controls.chkRemoveApps.IsChecked
        RemoveFFU                      = $State.Controls.chkRemoveFFU.IsChecked
        RemoveUpdates                  = $State.Controls.chkRemoveUpdates.IsChecked
        ShareName                      = $State.Controls.txtShareName.Text
        UpdateADK                      = $State.Controls.chkUpdateADK.IsChecked
        UpdateEdge                     = $State.Controls.chkUpdateEdge.IsChecked
        UpdateLatestCU                 = $State.Controls.chkUpdateLatestCU.IsChecked
        UpdateLatestDefender           = $State.Controls.chkUpdateLatestDefender.IsChecked
        UpdateLatestMicrocode          = $State.Controls.chkUpdateLatestMicrocode.IsChecked
        UpdateLatestMSRT               = $State.Controls.chkUpdateLatestMSRT.IsChecked
        UpdateLatestNet                = $State.Controls.chkUpdateLatestNet.IsChecked
        UpdateOneDrive                 = $State.Controls.chkUpdateOneDrive.IsChecked
        UpdatePreviewCU                = $State.Controls.chkUpdatePreviewCU.IsChecked
        UserAppListPath                = "$($State.Controls.txtApplicationPath.Text)\UserAppList.json"
        USBDriveList                   = @{}
        Username                       = $State.Controls.txtUsername.Text
        VMHostIPAddress                = $State.Controls.txtVMHostIPAddress.Text
        VMLocation                     = $State.Controls.txtVMLocation.Text
        VMSwitchName                   = if ($State.Controls.cmbVMSwitchName.SelectedItem -eq 'Other') {
            $State.Controls.txtCustomVMSwitchName.Text
        }
        else {
            $State.Controls.cmbVMSwitchName.SelectedItem
        }
        WindowsArch                    = $State.Controls.cmbWindowsArch.SelectedItem
        WindowsLang                    = $State.Controls.cmbWindowsLang.SelectedItem
        WindowsRelease                 = [int]$State.Controls.cmbWindowsRelease.SelectedItem.Value
        WindowsSKU                     = $State.Controls.cmbWindowsSKU.SelectedItem
        WindowsVersion                 = $State.Controls.cmbWindowsVersion.SelectedItem
    }

    $State.Controls.lstUSBDrives.Items | Where-Object { $_.IsSelected } | ForEach-Object {
        $config.USBDriveList[$_.Model] = $_.SerialNumber
    }
    
    return $config
}

# --------------------------------------------------------------------------
# SECTION: UI Initialization Functions
# --------------------------------------------------------------------------

function Initialize-UIControls {
    param([PSCustomObject]$State)
    WriteLog "Initializing UI control references..."
    $window = $State.Window
    # Find all controls ONCE and store them in the state object
    $State.Controls.cmbWindowsRelease = $window.FindName('cmbWindowsRelease')
    $State.Controls.cmbWindowsVersion = $window.FindName('cmbWindowsVersion')
    $State.Controls.txtISOPath = $window.FindName('txtISOPath')
    $State.Controls.btnBrowseISO = $window.FindName('btnBrowseISO')
    $State.Controls.cmbWindowsArch = $window.FindName('cmbWindowsArch')
    $State.Controls.cmbWindowsLang = $window.FindName('cmbWindowsLang')
    $State.Controls.cmbWindowsSKU = $window.FindName('cmbWindowsSKU')
    $State.Controls.cmbMediaType = $window.FindName('cmbMediaType')
    $State.Controls.txtOptionalFeatures = $window.FindName('txtOptionalFeatures')
    $State.Controls.featuresPanel = $window.FindName('stackFeaturesContainer')
    $State.Controls.chkDownloadDrivers = $window.FindName('chkDownloadDrivers')
    $State.Controls.cmbMake = $window.FindName('cmbMake')
    $State.Controls.spMakeSection = $window.FindName('spMakeSection')
    $State.Controls.btnGetModels = $window.FindName('btnGetModels')
    $State.Controls.spModelFilterSection = $window.FindName('spModelFilterSection')
    $State.Controls.txtModelFilter = $window.FindName('txtModelFilter')
    $State.Controls.lstDriverModels = $window.FindName('lstDriverModels')
    $State.Controls.spDriverActionButtons = $window.FindName('spDriverActionButtons')
    $State.Controls.btnSaveDriversJson = $window.FindName('btnSaveDriversJson')
    $State.Controls.btnImportDriversJson = $window.FindName('btnImportDriversJson')
    $State.Controls.btnDownloadSelectedDrivers = $window.FindName('btnDownloadSelectedDrivers')
    $State.Controls.btnClearDriverList = $window.FindName('btnClearDriverList')
    $State.Controls.chkInstallOffice = $window.FindName('chkInstallOffice')
    $State.Controls.chkInstallApps = $window.FindName('chkInstallApps')
    $State.Controls.OfficePathStackPanel = $window.FindName('OfficePathStackPanel')
    $State.Controls.OfficePathGrid = $window.FindName('OfficePathGrid')
    $State.Controls.CopyOfficeConfigXMLStackPanel = $window.FindName('CopyOfficeConfigXMLStackPanel')
    $State.Controls.OfficeConfigurationXMLFileStackPanel = $window.FindName('OfficeConfigurationXMLFileStackPanel')
    $State.Controls.OfficeConfigurationXMLFileGrid = $window.FindName('OfficeConfigurationXMLFileGrid')
    $State.Controls.chkCopyOfficeConfigXML = $window.FindName('chkCopyOfficeConfigXML')
    $State.Controls.chkLatestCU = $window.FindName('chkUpdateLatestCU')
    $State.Controls.chkPreviewCU = $window.FindName('chkUpdatePreviewCU')
    $State.Controls.btnCheckUSBDrives = $window.FindName('btnCheckUSBDrives')
    $State.Controls.lstUSBDrives = $window.FindName('lstUSBDrives')
    $State.Controls.chkSelectAllUSBDrives = $window.FindName('chkSelectAllUSBDrives')
    $State.Controls.chkBuildUSBDriveEnable = $window.FindName('chkBuildUSBDriveEnable')
    $State.Controls.usbSection = $window.FindName('usbDriveSection')
    $State.Controls.chkSelectSpecificUSBDrives = $window.FindName('chkSelectSpecificUSBDrives')
    $State.Controls.usbSelectionPanel = $window.FindName('usbDriveSelectionPanel')
    $State.Controls.chkAllowExternalHardDiskMedia = $window.FindName('chkAllowExternalHardDiskMedia')
    $State.Controls.chkPromptExternalHardDiskMedia = $window.FindName('chkPromptExternalHardDiskMedia')
    $State.Controls.chkInstallWingetApps = $window.FindName('chkInstallWingetApps')
    $State.Controls.wingetPanel = $window.FindName('wingetPanel')
    $State.Controls.btnCheckWingetModule = $window.FindName('btnCheckWingetModule')
    $State.Controls.txtWingetVersion = $window.FindName('txtWingetVersion')
    $State.Controls.txtWingetModuleVersion = $window.FindName('txtWingetModuleVersion')
    $State.Controls.applicationPathPanel = $window.FindName('applicationPathPanel')
    $State.Controls.appListJsonPathPanel = $window.FindName('appListJsonPathPanel')
    $State.Controls.btnBrowseApplicationPath = $window.FindName('btnBrowseApplicationPath')
    $State.Controls.btnBrowseAppListJsonPath = $window.FindName('btnBrowseAppListJsonPath')
    $State.Controls.chkBringYourOwnApps = $window.FindName('chkBringYourOwnApps')
    $State.Controls.byoApplicationPanel = $window.FindName('byoApplicationPanel')
    $State.Controls.wingetSearchPanel = $window.FindName('wingetSearchPanel')
    $State.Controls.txtWingetSearch = $window.FindName('txtWingetSearch')
    $State.Controls.btnWingetSearch = $window.FindName('btnWingetSearch')
    $State.Controls.lstWingetResults = $window.FindName('lstWingetResults')
    $State.Controls.btnSaveWingetList = $window.FindName('btnSaveWingetList')
    $State.Controls.btnImportWingetList = $window.FindName('btnImportWingetList')
    $State.Controls.btnClearWingetList = $window.FindName('btnClearWingetList')
    $State.Controls.btnDownloadSelected = $window.FindName('btnDownloadSelected')
    $State.Controls.btnBrowseAppSource = $window.FindName('btnBrowseAppSource')
    $State.Controls.btnBrowseFFUDevPath = $window.FindName('btnBrowseFFUDevPath')
    $State.Controls.btnBrowseFFUCaptureLocation = $window.FindName('btnBrowseFFUCaptureLocation')
    $State.Controls.btnBrowseOfficePath = $window.FindName('btnBrowseOfficePath')
    $State.Controls.btnBrowseDriversFolder = $window.FindName('btnBrowseDriversFolder')
    $State.Controls.btnBrowsePEDriversFolder = $window.FindName('btnBrowsePEDriversFolder')
    $State.Controls.txtAppName = $window.FindName('txtAppName')
    $State.Controls.txtAppCommandLine = $window.FindName('txtAppCommandLine')
    $State.Controls.txtAppArguments = $window.FindName('txtAppArguments')
    $State.Controls.txtAppSource = $window.FindName('txtAppSource')
    $State.Controls.btnAddApplication = $window.FindName('btnAddApplication')
    $State.Controls.btnSaveBYOApplications = $window.FindName('btnSaveBYOApplications')
    $State.Controls.btnLoadBYOApplications = $window.FindName('btnLoadBYOApplications')
    $State.Controls.btnClearBYOApplications = $window.FindName('btnClearBYOApplications')
    $State.Controls.btnCopyBYOApps = $window.FindName('btnCopyBYOApps')
    $State.Controls.lstApplications = $window.FindName('lstApplications')
    $State.Controls.btnMoveTop = $window.FindName('btnMoveTop')
    $State.Controls.btnMoveUp = $window.FindName('btnMoveUp')
    $State.Controls.btnMoveDown = $window.FindName('btnMoveDown')
    $State.Controls.btnMoveBottom = $window.FindName('btnMoveBottom')
    $State.Controls.txtStatus = $window.FindName('txtStatus')
    $State.Controls.pbOverallProgress = $window.FindName('progressBar')
    $State.Controls.txtOverallStatus = $window.FindName('txtStatus')
    $State.Controls.cmbVMSwitchName = $window.FindName('cmbVMSwitchName')
    $State.Controls.txtVMHostIPAddress = $window.FindName('txtVMHostIPAddress')
    $State.Controls.txtCustomVMSwitchName = $window.FindName('txtCustomVMSwitchName')
    $State.Controls.txtFFUDevPath = $window.FindName('txtFFUDevPath')
    $State.Controls.txtCustomFFUNameTemplate = $window.FindName('txtCustomFFUNameTemplate')
    $State.Controls.txtFFUCaptureLocation = $window.FindName('txtFFUCaptureLocation')
    $State.Controls.txtShareName = $window.FindName('txtShareName')
    $State.Controls.txtUsername = $window.FindName('txtUsername')
    $State.Controls.chkCompactOS = $window.FindName('chkCompactOS')
    $State.Controls.chkOptimize = $window.FindName('chkOptimize')
    $State.Controls.chkAllowVHDXCaching = $window.FindName('chkAllowVHDXCaching')
    $State.Controls.chkCreateCaptureMedia = $window.FindName('chkCreateCaptureMedia')
    $State.Controls.chkCreateDeploymentMedia = $window.FindName('chkCreateDeploymentMedia')
    $State.Controls.chkCopyAutopilot = $window.FindName('chkCopyAutopilot')
    $State.Controls.chkCopyUnattend = $window.FindName('chkCopyUnattend')
    $State.Controls.chkCopyPPKG = $window.FindName('chkCopyPPKG')
    $State.Controls.chkCleanupAppsISO = $window.FindName('chkCleanupAppsISO')
    $State.Controls.chkCleanupCaptureISO = $window.FindName('chkCleanupCaptureISO')
    $State.Controls.chkCleanupDeployISO = $window.FindName('chkCleanupDeployISO')
    $State.Controls.chkCleanupDrivers = $window.FindName('chkCleanupDrivers')
    $State.Controls.chkRemoveFFU = $window.FindName('chkRemoveFFU')
    $State.Controls.txtDiskSize = $window.FindName('txtDiskSize')
    $State.Controls.txtMemory = $window.FindName('txtMemory')
    $State.Controls.txtProcessors = $window.FindName('txtProcessors')
    $State.Controls.txtVMLocation = $window.FindName('txtVMLocation')
    $State.Controls.txtVMNamePrefix = $window.FindName('txtVMNamePrefix')
    $State.Controls.cmbLogicalSectorSize = $window.FindName('cmbLogicalSectorSize')
    $State.Controls.txtProductKey = $window.FindName('txtProductKey')
    $State.Controls.txtOfficePath = $window.FindName('txtOfficePath')
    $State.Controls.txtOfficeConfigXMLFilePath = $window.FindName('txtOfficeConfigXMLFilePath')
    $State.Controls.txtDriversFolder = $window.FindName('txtDriversFolder')
    $State.Controls.txtPEDriversFolder = $window.FindName('txtPEDriversFolder')
    $State.Controls.chkCopyPEDrivers = $window.FindName('chkCopyPEDrivers')
    $State.Controls.chkUpdateLatestCU = $window.FindName('chkUpdateLatestCU')
    $State.Controls.chkUpdateLatestNet = $window.FindName('chkUpdateLatestNet')
    $State.Controls.chkUpdateLatestDefender = $window.FindName('chkUpdateLatestDefender')
    $State.Controls.chkUpdateEdge = $window.FindName('chkUpdateEdge')
    $State.Controls.chkUpdateOneDrive = $window.FindName('chkUpdateOneDrive')
    $State.Controls.chkUpdateLatestMSRT = $window.FindName('chkUpdateLatestMSRT')
    $State.Controls.chkUpdatePreviewCU = $window.FindName('chkUpdatePreviewCU')
    $State.Controls.txtApplicationPath = $window.FindName('txtApplicationPath')
    $State.Controls.txtAppListJsonPath = $window.FindName('txtAppListJsonPath')
    $State.Controls.chkInstallDrivers = $window.FindName('chkInstallDrivers')
    $State.Controls.chkCopyDrivers = $window.FindName('chkCopyDrivers')
    $State.Controls.chkCompressDriversToWIM = $window.FindName('chkCompressDriversToWIM')
    $State.Controls.chkRemoveApps = $window.FindName('chkRemoveApps')
    $State.Controls.chkRemoveUpdates = $window.FindName('chkRemoveUpdates')
    $State.Controls.chkUpdateLatestMicrocode = $window.FindName('chkUpdateLatestMicrocode')
    $State.Controls.chkDefineAppsScriptVariables = $window.FindName('chkDefineAppsScriptVariables')
    $State.Controls.appsScriptVariablesPanel = $window.FindName('appsScriptVariablesPanel')
    $State.Controls.txtAppsScriptKey = $window.FindName('txtAppsScriptKey')
    $State.Controls.txtAppsScriptValue = $window.FindName('txtAppsScriptValue')
    $State.Controls.btnAddAppsScriptVariable = $window.FindName('btnAddAppsScriptVariable')
    $State.Controls.lstAppsScriptVariables = $window.FindName('lstAppsScriptVariables')
    $State.Controls.btnRemoveSelectedAppsScriptVariables = $window.FindName('btnRemoveSelectedAppsScriptVariables')
    $State.Controls.btnClearAppsScriptVariables = $window.FindName('btnClearAppsScriptVariables')
    $State.Controls.txtDriversJsonPath = $window.FindName('txtDriversJsonPath')
    $State.Controls.btnBrowseDriversJsonPath = $window.FindName('btnBrowseDriversJsonPath')
    $State.Controls.chkUpdateADK = $window.FindName('chkUpdateADK')
}

# --------------------------------------------------------------------------
# SECTION: Module Export
# --------------------------------------------------------------------------

# Export only the functions intended for public use by the UI script
Export-ModuleMember -Function *
