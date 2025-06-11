# FFU UI Core Logic Module
# Contains non-UI specific helper functions, data retrieval, and core processing logic.

#Requires -Modules BitsTransfer 

# Import shared modules
Import-Module "$PSScriptRoot\..\common\FFU.Common.Core.psm1"
Import-Module "$PSScriptRoot\..\common\FFU.Common.Winget.psm1"
Import-Module "$PSScriptRoot\..\common\FFU.Common.Drivers.psm1"


# --------------------------------------------------------------------------
# SECTION: Module Variables (Static Data & State)
# --------------------------------------------------------------------------

# Mutex for log file access is now in FFU.Common.Core.psm1

# Static data moved from UI_Helpers
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

# --------------------------------------------------------------------------
# SECTION: Logging Function (Moved from UI_Helpers)
# --------------------------------------------------------------------------
# WriteLog function has been moved to FFU.Common.Core.psm1
# All WriteLog calls in this module will now use the common WriteLog.

# --------------------------------------------------------------------------
# SECTION: Data Retrieval Functions (Moved from UI_Helpers & BuildFFUVM_UI)
# --------------------------------------------------------------------------

# Function to get VM Switch names and associated IP addresses (Moved from UI_Helpers)
function Get-VMSwitchData {
    [CmdletBinding()]
    param() # No parameters needed

    $switchMap = @{}
    $switchNames = @()

    try {
        # Attempt to get Hyper-V virtual switches
        # SilentlyContinue is used as Hyper-V role might not be installed
        $allSwitches = Get-VMSwitch -ErrorAction SilentlyContinue
        if ($null -ne $allSwitches) {
            foreach ($sw in $allSwitches) {
                # Construct a pattern to find the network adapter associated with the vSwitch
                # The adapter name often includes the vSwitch name in parentheses
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
                        # Log if no valid non-APIPA IP was found for the adapter
                        WriteLog "No valid non-APIPA IPv4 address found for vSwitch '$($sw.Name)' (Adapter: $($netAdapter.Name)). Skipping from list."
                        # Do NOT add $sw.Name to $switchNames
                    }
                }
                else {
                    # Log if no matching network adapter was found for the vSwitch
                    WriteLog "Could not find a network adapter matching pattern '$adapterNamePattern' for vSwitch '$($sw.Name)'. Skipping from list."
                    # Do NOT add $sw.Name to $switchNames
                }
            }
        }
        else {
            # Log if no vSwitches were found at all (Hyper-V might be disabled or not installed)
            WriteLog "No Hyper-V virtual switches found on this system."
        }
    }
    catch {
        # Log any unexpected errors during the process
        WriteLog "Error occurred while getting VM Switch data: $($_.Exception.Message)"
        # Optionally re-throw or handle the error appropriately depending on requirements
        # For UI stability, we might just log and return empty/partial data
    }

    # Return a custom object containing both the list of switch names and the map of names to IP addresses
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
        AllowedFeatures         = $script:allowedFeatures # Return the list
        # SkuList will now be populated dynamically based on Windows Release
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
        return $result # Return empty/disabled state
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
            $result.DefaultVersion = $validVersions[0] # Default to first in list otherwise
        }
        $result.IsEnabled = $true # Combo should be enabled
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

# Function to get the list of Dell models from the catalog using XML streaming (Moved from UI_Helpers)
# Depends on private functions: Start-BitsTransferWithRetry, Invoke-Process
function Get-DellDriversModelList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$WindowsRelease,
        [Parameter(Mandatory = $true)]
        [string]$DriversFolder, # Base drivers folder (e.g., C:\FFUDevelopment\Drivers)
        [Parameter(Mandatory = $true)]
        [string]$Make # Should be 'Dell'
    )

    # Define Dell specific drivers folder and catalog file names
    $dellDriversFolder = Join-Path -Path $DriversFolder -ChildPath "Dell"
    $catalogBaseName = if ($WindowsRelease -le 11) { "CatalogPC" } else { "Catalog" }
    $dellCabFile = Join-Path -Path $dellDriversFolder -ChildPath "$($catalogBaseName).cab"
    $dellCatalogXML = Join-Path -Path $dellDriversFolder -ChildPath "$($catalogBaseName).xml"
    $catalogUrl = if ($WindowsRelease -le 11) { "http://downloads.dell.com/catalog/CatalogPC.cab" } else { "https://downloads.dell.com/catalog/Catalog.cab" }

    $uniqueModelNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $reader = $null # Initialize reader variable

    try {
        # Check if the Dell catalog XML exists and is recent
        $downloadCatalog = $true
        if (Test-Path -Path $dellCatalogXML -PathType Leaf) {
            WriteLog "Dell Catalog XML found: $dellCatalogXML"
            $dellCatalogCreationTime = (Get-Item $dellCatalogXML).CreationTime
            WriteLog "Dell Catalog XML Creation time: $dellCatalogCreationTime"
            # Check if the XML file is less than 7 days old
            if (((Get-Date) - $dellCatalogCreationTime).TotalDays -lt 7) {
                WriteLog "Using existing Dell Catalog XML (less than 7 days old): $dellCatalogXML"
                $downloadCatalog = $false
            }
            else {
                WriteLog "Existing Dell Catalog XML is older than 7 days: $dellCatalogXML"
            }
        }
        else {
            WriteLog "Dell Catalog XML not found: $dellCatalogXML"
        }

        if ($downloadCatalog) {
            WriteLog "Attempting to download and extract Dell Catalog for Get-DellDriversModelList..."
            # Ensure Dell drivers folder exists
            if (-not (Test-Path -Path $dellDriversFolder -PathType Container)) {
                WriteLog "Creating Dell drivers folder: $dellDriversFolder"
                New-Item -Path $dellDriversFolder -ItemType Directory -Force | Out-Null
            }

            # Check URL accessibility
            try {
                $request = [System.Net.WebRequest]::Create($catalogUrl)
                $request.Method = 'HEAD'; $response = $request.GetResponse(); $response.Close()
            }
            catch { throw "Dell Catalog URL '$catalogUrl' not accessible: $($_.Exception.Message)" }

            # Remove existing files before download if they exist
            if (Test-Path -Path $dellCabFile) { Remove-Item -Path $dellCabFile -Force -ErrorAction SilentlyContinue }
            if (Test-Path -Path $dellCatalogXML) { Remove-Item -Path $dellCatalogXML -Force -ErrorAction SilentlyContinue }

            WriteLog "Downloading Dell Catalog cab file: $catalogUrl to $dellCabFile"
            Start-BitsTransferWithRetry -Source $catalogUrl -Destination $dellCabFile
            WriteLog "Dell Catalog cab file downloaded to $dellCabFile"

            WriteLog "Extracting Dell Catalog cab file '$dellCabFile' to '$dellCatalogXML'"
            Invoke-Process -FilePath "Expand.exe" -ArgumentList """$dellCabFile"" ""$dellCatalogXML""" | Out-Null
            WriteLog "Dell Catalog cab file extracted to $dellCatalogXML"

            # Delete the CAB file after extraction
            WriteLog "Deleting Dell Catalog CAB file: $dellCabFile"
            Remove-Item -Path $dellCabFile -Force -ErrorAction SilentlyContinue
        }

        # Ensure the XML file exists before trying to read it
        if (-not (Test-Path -Path $dellCatalogXML -PathType Leaf)) {
            throw "Dell Catalog XML file '$dellCatalogXML' not found after download/check attempt."
        }
        
        # Use XmlReader for streaming from the XML file
        $settings = New-Object System.Xml.XmlReaderSettings
        $settings.IgnoreWhitespace = $true
        $settings.IgnoreComments = $true
        # $settings.DtdProcessing = [System.Xml.DtdProcessing]::Ignore # Optional

        $reader = [System.Xml.XmlReader]::Create($dellCatalogXML, $settings)
        WriteLog "Starting XML stream parsing for Dell models from '$dellCatalogXML'..."

        $isDriverComponent = $false
        $isModelElement = $false
        $modelDepth = -1 # Track depth to handle nested elements if needed

        # Read through the XML stream node by node
        while ($reader.Read()) {
            switch ($reader.NodeType) {
                ([System.Xml.XmlNodeType]::Element) {
                    switch ($reader.Name) {
                        'SoftwareComponent' { $isDriverComponent = $false } # Reset flag
                        'ComponentType' { if ($reader.GetAttribute('value') -eq 'DRVR') { $isDriverComponent = $true } }
                        'Model' { if ($isDriverComponent) { $isModelElement = $true; $modelDepth = $reader.Depth } }
                    }
                }
                ([System.Xml.XmlNodeType]::CDATA) {
                    if ($isModelElement -and $isDriverComponent) {
                        $modelName = $reader.Value.Trim()
                        if (-not [string]::IsNullOrWhiteSpace($modelName)) { $uniqueModelNames.Add($modelName) | Out-Null }
                        $isModelElement = $false # Reset after reading CDATA
                    }
                }
                ([System.Xml.XmlNodeType]::EndElement) {
                    switch ($reader.Name) {
                        'SoftwareComponent' { $isDriverComponent = $false; $isModelElement = $false; $modelDepth = -1 }
                        'Model' { if ($reader.Depth -eq $modelDepth) { $isModelElement = $false; $modelDepth = -1 } }
                    }
                }
            }
        } # End while ($reader.Read())

        WriteLog "Finished XML stream parsing. Found $($uniqueModelNames.Count) unique Dell models."

    }
    catch {
        WriteLog "Error getting Dell models: $($_.Exception.ToString())" # Log full exception
        throw "Failed to retrieve Dell models. Check log for details." # Re-throw for UI handling
    }
    finally {
        # Ensure the reader is closed and disposed
        if ($null -ne $reader) {
            $reader.Dispose()
        }
        # REMOVED: Cleanup of temp folder - XML is kept in DriversFolder
        # Ensure CAB file is deleted even if extraction failed but download succeeded
        if (Test-Path -Path $dellCabFile) {
            WriteLog "Cleaning up downloaded Dell CAB file: $dellCabFile"
            Remove-Item -Path $dellCabFile -Force -ErrorAction SilentlyContinue
        }
    }

    # Convert HashSet to sorted list of PSCustomObjects
    $models = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($modelName in ($uniqueModelNames | Sort-Object)) {
        $models.Add([PSCustomObject]@{
                Make  = $Make
                Model = $modelName
                # Link is not applicable here like for Microsoft
            })
    }

    return $models
}

# Function to get the list of Microsoft Surface models
function Get-MicrosoftDriversModelList {
    [CmdletBinding()]
    param(
        [hashtable]$Headers, # Pass necessary headers
        [string]$UserAgent # Pass UserAgent
    )

    $url = "https://support.microsoft.com/en-us/surface/download-drivers-and-firmware-for-surface-09bb2e09-2a4b-cb69-0951-078a7739e120"
    $models = @()

    try {
        WriteLog "Getting Surface driver information from $url"
        $OriginalVerbosePreference = $VerbosePreference
        $VerbosePreference = 'SilentlyContinue'
        # Use passed-in UserAgent and Headers
        $webContent = Invoke-WebRequest -Uri $url -UseBasicParsing -Headers $Headers -UserAgent $UserAgent
        $VerbosePreference = $OriginalVerbosePreference
        WriteLog "Complete"

        WriteLog "Parsing web content for models and download links"
        $html = $webContent.Content
        $divPattern = '<div[^>]*class="selectable-content-options__option-content(?: ocHidden)?"[^>]*>(.*?)</div>'
        $divMatches = [regex]::Matches($html, $divPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

        foreach ($divMatch in $divMatches) {
            $divContent = $divMatch.Groups[1].Value
            $tablePattern = '<table[^>]*>(.*?)</table>'
            $tableMatches = [regex]::Matches($divContent, $tablePattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

            foreach ($tableMatch in $tableMatches) {
                $tableContent = $tableMatch.Groups[1].Value
                $rowPattern = '<tr[^>]*>(.*?)</tr>'
                $rowMatches = [regex]::Matches($tableContent, $rowPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

                foreach ($rowMatch in $rowMatches) {
                    $rowContent = $rowMatch.Groups[1].Value
                    $cellPattern = '<td[^>]*>\s*(?:<p[^>]*>)?(.*?)(?:</p>)?\s*</td>'
                    $cellMatches = [regex]::Matches($rowContent, $cellPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

                    if ($cellMatches.Count -ge 2) {
                        $modelName = ($cellMatches[0].Groups[1].Value).Trim()
                        $secondTdContent = $cellMatches[1].Groups[1].Value.Trim()
                        # $linkPattern = '<a[^>]+href="([^"]+)"[^>]*>'
                        # Change linkPattern to match https://www.microsoft.com/download/details.aspx?id=
                        $linkPattern = '<a[^>]+href="(https://www\.microsoft\.com/download/details\.aspx\?id=\d+)"[^>]*>'
                        $linkMatch = [regex]::Match($secondTdContent, $linkPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

                        if ($linkMatch.Success) {
                            $modelLink = $linkMatch.Groups[1].Value
                        }
                        else {
                            continue
                        }

                        $models += [PSCustomObject]@{
                            Make  = 'Microsoft'
                            Model = $modelName
                            Link  = $modelLink
                        }
                    }
                }
            }
        }
        WriteLog "Parsing complete. Found $($models.Count) models."
        return $models
    }
    catch {
        WriteLog "Error getting Microsoft models: $($_.Exception.Message)"
        throw "Failed to retrieve Microsoft Surface models."
    }
}

# Function to get the list of Lenovo models using the PSREF API
function Get-LenovoDriversModelList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModelSearchTerm, # User input for model/machine type
        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,
        [Parameter(Mandatory = $true)]
        [string]$UserAgent
    )

    WriteLog "Querying Lenovo PSREF API for model/machine type: $ModelSearchTerm"
    $url = "https://psref.lenovo.com/api/search/DefinitionFilterAndSearch/Suggest?kw=$([uri]::EscapeDataString($ModelSearchTerm))"
    $models = [System.Collections.Generic.List[PSCustomObject]]::new()

    try {
        $OriginalVerbosePreference = $VerbosePreference
        $VerbosePreference = 'SilentlyContinue'
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -Headers $Headers -UserAgent $UserAgent -ErrorAction Stop
        $VerbosePreference = $OriginalVerbosePreference
        WriteLog "PSREF API query complete."

        $jsonResponse = $response.Content | ConvertFrom-Json

        if ($null -ne $jsonResponse.data -and $jsonResponse.data.Count -gt 0) {
            foreach ($item in $jsonResponse.data) {
                $productName = $item.ProductName
                $machineTypes = $item.MachineType -split " / " # Split if multiple machine types are listed

                foreach ($machineTypeRaw in $machineTypes) {
                    $machineType = $machineTypeRaw.Trim()
                    # Only add if machine type is not empty
                    if (-not [string]::IsNullOrWhiteSpace($machineType)) {
                        # Create the combined display string
                        $displayModel = "$productName ($machineType)"
                        # Add each combination as a separate entry
                        $models.Add([PSCustomObject]@{
                                Make        = 'Lenovo'
                                Model       = $displayModel # Combined string for display
                                ProductName = $productName # Original product name stored separately if needed
                                MachineType = $machineType # Machine type needed for catalog URL
                            })
                    }
                    else {
                        WriteLog "Skipping entry for product '$productName' due to missing machine type."
                    }
                }
            }
            WriteLog "Found $($models.Count) potential model/machine type combinations for '$ModelSearchTerm'."
        }
        else {
            WriteLog "No models found matching '$ModelSearchTerm' in Lenovo PSREF."
        }
    }
    catch {
        WriteLog "Error querying Lenovo PSREF API: $($_.Exception.Message)"
        # Return empty list on error
    }

    # Return the list (sorting might be done in the UI layer if needed)
    return $models
}

# Function to download and extract drivers for a specific Lenovo model (Background Task)
function Save-LenovoDriversTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$DriverItemData, # Contains Model (ProductName) and MachineType
        [Parameter(Mandatory = $true)]
        [string]$DriversFolder,
        [Parameter(Mandatory = $true)]
        [int]$WindowsRelease,
        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,
        [Parameter(Mandatory = $true)]
        [string]$UserAgent,
        [Parameter()] # Made optional
        [System.Collections.Concurrent.ConcurrentQueue[hashtable]]$ProgressQueue = $null, # Default to null
        [Parameter()]
        [bool]$CompressToWim = $false # New parameter for compression
    )
            
    # The Model property from the UI already contains the combined "ProductName (MachineType)" string
    $identifier = $DriverItemData.Model       
    # We still need the machine type for the catalog URL
    $machineType = $DriverItemData.MachineType 
    $make = "Lenovo"
    # $identifier = "$($modelName) ($($machineType))" # No longer needed, use Model directly
    $status = "Starting..."
    $success = $false
    
    # Define paths
    $makeDriversPath = Join-Path -Path $DriversFolder -ChildPath $Make
    # Use the identifier (which contains the model name and machine type) and sanitize it for the path
    $modelPath = Join-Path -Path $makeDriversPath -ChildPath ($identifier -replace '[\\/:"*?<>|]', '_') 
    $tempDownloadPath = Join-Path -Path $makeDriversPath -ChildPath "_TEMP_$($machineType)_$($PID)" # Temp folder for catalog/package XMLs
    
    if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status "Checking..." }
    
    try {
        # 1. Check if drivers already exist for this model (final destination)
        if (Test-Path -Path $modelPath -PathType Container) {
            $folderSize = (Get-ChildItem -Path $modelPath -Recurse | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
            if ($folderSize -gt 1MB) {
                $status = "Already downloaded"
                WriteLog "Drivers for '$identifier' already exist in '$modelPath'."
                if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $status }
                return [PSCustomObject]@{ Identifier = $identifier; Status = $status; Success = $true }
            }
            else {
                WriteLog "Driver folder '$modelPath' for '$identifier' exists but is empty/small. Re-downloading."
            }
        }

        # Ensure base directories exist
        if (-not (Test-Path -Path $makeDriversPath)) { New-Item -Path $makeDriversPath -ItemType Directory -Force | Out-Null }
        if (-not (Test-Path -Path $modelPath)) { New-Item -Path $modelPath -ItemType Directory -Force | Out-Null }
        if (-not (Test-Path -Path $tempDownloadPath)) { New-Item -Path $tempDownloadPath -ItemType Directory -Force | Out-Null }

        # 2. Construct and Download Catalog URL
        $modelRelease = $machineType + "_Win" + $WindowsRelease
        $catalogUrl = "https://download.lenovo.com/catalog/$modelRelease.xml"
        $lenovoCatalogXML = Join-Path -Path $tempDownloadPath -ChildPath "$modelRelease.xml"

        $status = "Downloading Catalog..."
        if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $status }
        WriteLog "Downloading Lenovo Driver catalog for '$identifier' from $catalogUrl"

        # Check URL accessibility first
        try {
            $request = [System.Net.WebRequest]::Create($catalogUrl); $request.Method = 'HEAD'; $response = $request.GetResponse(); $response.Close()
        }
        catch { throw "Lenovo Driver catalog URL is not accessible: $catalogUrl. Error: $($_.Exception.Message)" }

        Start-BitsTransferWithRetry -Source $catalogUrl -Destination $lenovoCatalogXML
        WriteLog "Catalog download Complete: $lenovoCatalogXML"

        # 3. Parse Catalog and Process Packages
        $status = "Parsing Catalog..."
        if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $status }
        [xml]$xmlContent = Get-Content -Path $lenovoCatalogXML -Encoding UTF8

        $packages = @($xmlContent.packages.package) # Ensure it's an array
        $totalPackages = $packages.Count
        $processedPackages = 0
        WriteLog "Found $totalPackages packages in catalog for '$identifier'."

        foreach ($package in $packages) {
            $processedPackages++
            $category = $package.category
            $packageUrl = $package.location # URL to the package's *XML* file

            # Skip BIOS/Firmware based on category
            if ($category -like 'BIOS*' -or $category -like 'Firmware*') {
                WriteLog "($processedPackages/$totalPackages) Skipping BIOS/Firmware package: $category"
                continue
            }

            # Sanitize category for path
            $categoryClean = $category -replace '[\\/:"*?<>|]', '_'
            if ($categoryClean -eq 'Motherboard Devices Backplanes core chipset onboard video PCIe switches') {
                $categoryClean = 'Motherboard Devices' # Shorten long category name
            }

            $packageName = [System.IO.Path]::GetFileName($packageUrl)
            $packageXMLPath = Join-Path -Path $tempDownloadPath -ChildPath $packageName
            $baseURL = $packageUrl -replace [regex]::Escape($packageName), "" # Base URL for the driver file

            $status = "($processedPackages/$totalPackages) Getting package info..."
            if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $status }

            # Download the package XML
            WriteLog "($processedPackages/$totalPackages) Downloading package XML: $packageUrl"
            try {
                Start-BitsTransferWithRetry -Source $packageUrl -Destination $packageXMLPath
            }
            catch {
                WriteLog "($processedPackages/$totalPackages) Failed to download package XML '$packageUrl'. Skipping. Error: $($_.Exception.Message)"
                continue # Skip this package
            }

            # Load and parse the package XML
            [xml]$packageXmlContent = Get-Content -Path $packageXMLPath -Encoding UTF8
            $packageType = $packageXmlContent.Package.PackageType.type
            $packageTitleRaw = $packageXmlContent.Package.title.InnerText

            # Filter out non-driver packages (Type 2 = Driver)
            if ($packageType -ne 2) {
                WriteLog "($processedPackages/$totalPackages) Skipping package '$packageTitleRaw' (Type: $packageType) - Not a driver."
                Remove-Item -Path $packageXMLPath -Force -ErrorAction SilentlyContinue # Clean up package XML
                continue
            }

            # Sanitize title for folder name
            $packageTitle = $packageTitleRaw -replace '[\\/:"*?<>|]', '_' -replace ' - .*', ''

            # Extract driver file name and extract command
            $driverFileName = $null
            $extractCommand = $null
            try {
                $driverFileName = $packageXmlContent.Package.Files.Installer.File.Name
                $extractCommand = $packageXmlContent.Package.ExtractCommand
            }
            catch {
                WriteLog "($processedPackages/$totalPackages) Error parsing package XML '$packageXMLPath' for file name/command. Skipping. Error: $($_.Exception.Message)"
                Remove-Item -Path $packageXMLPath -Force -ErrorAction SilentlyContinue
                continue
            }


            # Skip if essential info is missing
            if ([string]::IsNullOrWhiteSpace($driverFileName) -or [string]::IsNullOrWhiteSpace($extractCommand)) {
                WriteLog "($processedPackages/$totalPackages) Skipping package '$packageTitleRaw' - Missing driver file name or extract command in XML."
                Remove-Item -Path $packageXMLPath -Force -ErrorAction SilentlyContinue
                continue
            }

            # Construct paths
            $driverUrl = $baseURL + $driverFileName
            $categoryPath = Join-Path -Path $modelPath -ChildPath $categoryClean
            $downloadFolder = Join-Path -Path $categoryPath -ChildPath $packageTitle # Final destination subfolder
            $driverFilePath = Join-Path -Path $downloadFolder -ChildPath $driverFileName
            $extractFolder = Join-Path -Path $downloadFolder -ChildPath ($driverFileName -replace '\.exe$', '') # Extract to subfolder named after exe
            # Check if already extracted
            if (Test-Path -Path $extractFolder -PathType Container) {
                $extractSize = (Get-ChildItem -Path $extractFolder -Recurse | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                if ($extractSize -gt 1KB) {
                    WriteLog "($processedPackages/$totalPackages) Driver '$packageTitleRaw' already extracted to '$extractFolder'. Skipping."
                    Remove-Item -Path $packageXMLPath -Force -ErrorAction SilentlyContinue # Clean up package XML
                    continue
                }
            }

            # Ensure download folder exists
            if (-not (Test-Path -Path $downloadFolder)) {
                New-Item -Path $downloadFolder -ItemType Directory -Force | Out-Null
            }

            # Download the driver .exe
            $status = "($processedPackages/$totalPackages) Downloading $packageTitle..."
            if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $status }
            WriteLog "($processedPackages/$totalPackages) Downloading driver: $driverUrl to $driverFilePath"
            try {
                Start-BitsTransferWithRetry -Source $driverUrl -Destination $driverFilePath
                WriteLog "($processedPackages/$totalPackages) Driver downloaded: $driverFileName"
            }
            catch {
                WriteLog "($processedPackages/$totalPackages) Failed to download driver '$driverUrl'. Skipping. Error: $($_.Exception.Message)"
                Remove-Item -Path $packageXMLPath -Force -ErrorAction SilentlyContinue # Clean up package XML
                continue # Skip this driver
            }

            # --- Extraction Logic ---
            $status = "($processedPackages/$totalPackages) Extracting $packageTitle..."
            if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $status }
    
            # Always use a temporary extraction path to avoid long path issues
            $originalExtractFolder = $extractFolder # Store the originally intended final path
            $extractionSucceeded = $false
            $tempExtractBase = $null # Initialize
    
            # Create randomized number for use with temp folder name
            $randomNumber = Get-Random -Minimum 1000 -Maximum 9999
            $tempExtractBase = Join-Path $env:TEMP "LenovoDriverExtract_$randomNumber"
            $extractFolder = Join-Path $tempExtractBase ($driverFileName -replace '\.exe$', '') # Actual temp extraction folder
            WriteLog "($processedPackages/$totalPackages) Using temporary extraction path: $extractFolder"
    
            # Ensure the base temp directory exists
            if (-not (Test-Path -Path $tempExtractBase)) {
                New-Item -Path $tempExtractBase -ItemType Directory -Force | Out-Null
            }
            # Ensure the target temporary extraction folder exists
            if (-not (Test-Path -Path $extractFolder)) {
                New-Item -Path $extractFolder -ItemType Directory -Force | Out-Null
            }
    
            # Modify the extract command to point to the temporary folder
            $modifiedExtractCommand = $extractCommand -replace '%PACKAGEPATH%', "`"$extractFolder`""
            WriteLog "($processedPackages/$totalPackages) Extracting driver: $driverFilePath using command: $modifiedExtractCommand"
                
            try {
                Invoke-Process -FilePath $driverFilePath -ArgumentList $modifiedExtractCommand -Wait $true | Out-Null
                WriteLog "($processedPackages/$totalPackages) Driver extracted to temporary path: $extractFolder"
                $extractionSucceeded = $true
            }
            catch {
                WriteLog "($processedPackages/$totalPackages) Failed to extract driver '$driverFilePath' to temporary path. Skipping. Error: $($_.Exception.Message)"
                # Don't delete the downloaded exe yet if extraction fails
                Remove-Item -Path $packageXMLPath -Force -ErrorAction SilentlyContinue # Clean up package XML
                # Clean up temp folder if extraction failed
                if ($tempExtractBase -and (Test-Path -Path $tempExtractBase)) {
                    Remove-Item -Path $tempExtractBase -Recurse -Force -ErrorAction SilentlyContinue
                }
                continue # Skip further processing for this driver
            }
    
            # --- Post-Extraction Handling (Move from Temp to Final Destination) ---
            if ($extractionSucceeded) {
                WriteLog "($processedPackages/$totalPackages) Performing post-extraction move from temp to final destination..."
                try {
                    # Ensure the *original* final destination folder exists and is empty
                    if (Test-Path -Path $originalExtractFolder) {
                        WriteLog "($processedPackages/$totalPackages) Clearing existing final destination folder: $originalExtractFolder"
                        Get-ChildItem -Path $originalExtractFolder -Recurse | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                    }
                    else {
                        WriteLog "($processedPackages/$totalPackages) Creating final destination folder: $originalExtractFolder"
                        New-Item -Path $originalExtractFolder -ItemType Directory -Force | Out-Null
                    }
    
                    # Get all items (files and folders) directly inside the temp extraction folder
                    $extractedItems = Get-ChildItem -Path $extractFolder -ErrorAction Stop
    
                    foreach ($item in $extractedItems) {
                        $itemName = $item.Name
                        $finalDestinationPath = $null
    
                        # Check if it's a directory containing 'Liteon'
                        if ($item.PSIsContainer -and $itemName -like '*Liteon*') {
                            # Rename Liteon folders with a random number suffix
                            $randomNumber = Get-Random -Minimum 1000 -Maximum 9999
                            $finalFolderName = "Liteon_$randomNumber"
                            $finalDestinationPath = Join-Path -Path $originalExtractFolder -ChildPath $finalFolderName
                            WriteLog "($processedPackages/$totalPackages) Moving Liteon folder '$itemName' to '$finalDestinationPath'"
                        }
                        else {
                            # For other files/folders, move them directly
                            $finalDestinationPath = Join-Path -Path $originalExtractFolder -ChildPath $itemName
                            WriteLog "($processedPackages/$totalPackages) Moving item '$itemName' to '$finalDestinationPath'"
                        }
    
                        # Perform the move
                        try {
                            Move-Item -Path $item.FullName -Destination $finalDestinationPath -Force -ErrorAction Stop
                        }
                        catch {
                            WriteLog "($processedPackages/$totalPackages) Failed to move item '$($item.FullName)' to '$finalDestinationPath'. Error: $($_.Exception.Message)"
                            # Decide if this should stop the whole process or just skip this item
                            # For now, we'll log and continue, but mark overall success as false
                            $extractionSucceeded = $false
                        }
                    } # End foreach ($item in $extractedItems)
    
                    if ($extractionSucceeded) {
                        WriteLog "($processedPackages/$totalPackages) All driver contents moved successfully from temp to final destination."
                    }
                    else {
                        WriteLog "($processedPackages/$totalPackages) Some driver contents failed to move. Check logs."
                    }
    
                }
                catch {
                    WriteLog "($processedPackages/$totalPackages) Error during post-extraction move: $($_.Exception.Message). Files might remain in temp."
                    $extractionSucceeded = $false # Mark as failed for cleanup logic below
                }
                finally {
                    # Clean up the base temporary directory regardless of move success/failure
                    if ($tempExtractBase -and (Test-Path -Path $tempExtractBase)) {
                        WriteLog "($processedPackages/$totalPackages) Cleaning up temporary extraction base: $tempExtractBase"
                        Remove-Item -Path $tempExtractBase -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }
            }
    
            # --- Final Cleanup ---
            # Delete the downloaded .exe only if extraction AND move were successful
            if ($extractionSucceeded) {
                WriteLog "($processedPackages/$totalPackages) Deleting driver installation file: $driverFilePath"
                Remove-Item -Path $driverFilePath -Force -ErrorAction SilentlyContinue
            }
            else {
                WriteLog "($processedPackages/$totalPackages) Keeping driver installation file due to extraction/move failure: $driverFilePath"
            }
            # Always delete the package XML
            WriteLog "($processedPackages/$totalPackages) Deleting package XML file: $packageXMLPath"
            Remove-Item -Path $packageXMLPath -Force -ErrorAction SilentlyContinue
    
        } # End foreach package
        
        # --- Compress to WIM if requested (after all drivers processed) ---
        if ($CompressToWim) {
            $status = "Compressing..."
            if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $status }
            $wimFileName = "$($identifier).wim" # Use sanitized identifier for filename
            $destinationWimPath = Join-Path -Path $makeDriversPath -ChildPath $wimFileName
            WriteLog "Compressing '$modelPath' to '$destinationWimPath'..."
            try {
                $compressResult = Compress-DriverFolderToWim -SourceFolderPath $modelPath -DestinationWimPath $destinationWimPath -WimName $identifier -WimDescription $identifier -ErrorAction Stop
                if ($compressResult) {
                    WriteLog "Compression successful for '$identifier'."
                    $status = "Completed & Compressed"
                }
                else {
                    WriteLog "Compression failed for '$identifier'. Check verbose/error output from Compress-DriverFolderToWim."
                    $status = "Completed (Compression Failed)"
                }
            }
            catch {
                WriteLog "Error during compression for '$identifier': $($_.Exception.Message)"
                $status = "Completed (Compression Error)"
            }
        }
        else {
            $status = "Completed" # Final status if not compressing
        }
        # --- End Compression ---
        
        $success = $true # Mark success as download/extract was okay
        
    }
    catch {
        $status = "Error: $($_.Exception.Message.Split('.')[0])" # Shorten error message
        WriteLog "Error saving Lenovo drivers for '$identifier': $($_.Exception.ToString())" # Log full exception string
        $success = $false
        # Enqueue the error status before returning
        if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $status }
        # Ensure return object is created even on error
        return [PSCustomObject]@{ Identifier = $identifier; Status = $status; Success = $success }
    }
    finally {
        # Clean up the main catalog XML and temp folder
        WriteLog "Cleaning up temporary download folder: $tempDownloadPath"
        Remove-Item -Path $tempDownloadPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Enqueue the final status (success or error) before returning
    if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $status }

    # Return the final status
    return [PSCustomObject]@{ Identifier = $identifier; Status = $status; Success = $success }
}

# Function to get the list of HP models from the PlatformList.xml
# Depends on private functions: Start-BitsTransferWithRetry, Invoke-Process
function Get-HPDriversModelList {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$DriversFolder,
        [Parameter(Mandatory = $true)]
        [string]$Make # Expected to be 'HP'
    )

    WriteLog "Getting HP driver model list..."
    $hpDriversFolder = Join-Path -Path $DriversFolder -ChildPath $Make
    $platformListUrl = 'https://hpia.hpcloud.hp.com/ref/platformList.cab'
    $platformListCab = Join-Path -Path $hpDriversFolder -ChildPath "platformList.cab"
    $platformListXml = Join-Path -Path $hpDriversFolder -ChildPath "PlatformList.xml"
    $modelList = [System.Collections.Generic.List[PSCustomObject]]::new()

    try {
        # Ensure HP drivers folder exists
        if (-not (Test-Path -Path $hpDriversFolder)) {
            WriteLog "Creating HP Drivers folder: $hpDriversFolder"
            New-Item -Path $hpDriversFolder -ItemType Directory -Force | Out-Null
        }

        # Download PlatformList.cab if it doesn't exist or is outdated (e.g., older than 7 days)
        if (-not (Test-Path -Path $platformListCab) -or ((Get-Date) - (Get-Item $platformListCab).LastWriteTime).TotalDays -gt 7) {
            WriteLog "Downloading $platformListUrl to $platformListCab"
            # Use the private helper function for download with retry
            Start-BitsTransferWithRetry -Source $platformListUrl -Destination $platformListCab -ErrorAction Stop
            WriteLog "PlatformList.cab download complete."
            # Force extraction if downloaded
            if (Test-Path -Path $platformListXml) {
                Remove-Item -Path $platformListXml -Force
            }
        }
        else {
            WriteLog "Using existing PlatformList.cab found at $platformListCab"
        }

        # Extract PlatformList.xml if it doesn't exist
        if (-not (Test-Path -Path $platformListXml)) {
            WriteLog "Expanding $platformListCab to $platformListXml"
            # Use the private helper function for process invocation
            Invoke-Process -FilePath "expand.exe" -ArgumentList @("`"$platformListCab`"", "`"$platformListXml`"") -ErrorAction Stop | Out-Null
            WriteLog "PlatformList.xml extraction complete."
        }
        else {
            WriteLog "Using existing PlatformList.xml found at $platformListXml"
        }

        # Parse the PlatformList.xml using XmlReader for efficiency
        WriteLog "Parsing PlatformList.xml to extract HP models..."
        $settings = New-Object System.Xml.XmlReaderSettings
        $settings.Async = $false # Ensure synchronous reading

        $reader = [System.Xml.XmlReader]::Create($platformListXml, $settings)
        $uniqueModels = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

        while ($reader.Read()) {
            if ($reader.NodeType -eq [System.Xml.XmlNodeType]::Element -and $reader.Name -eq 'Platform') {
                # Read the inner content of the Platform node
                $platformReader = $reader.ReadSubtree()
                while ($platformReader.Read()) {
                    if ($platformReader.NodeType -eq [System.Xml.XmlNodeType]::Element -and $platformReader.Name -eq 'ProductName') {
                        $modelName = $platformReader.ReadElementContentAsString()
                        if (-not [string]::IsNullOrWhiteSpace($modelName) -and $uniqueModels.Add($modelName)) {
                            # Add to list only if it's a new unique model
                            $modelList.Add([PSCustomObject]@{
                                    Make  = $Make
                                    Model = $modelName
                                    # Add other properties like SystemID if needed later, but keep it simple for now
                                })
                        }
                    }
                }
                $platformReader.Close()
            }
        }
        $reader.Close()

        WriteLog "Successfully parsed $($modelList.Count) unique HP models from PlatformList.xml."

    }
    catch {
        WriteLog "Error getting HP driver model list: $($_.Exception.Message)"
        # Optionally re-throw or return an empty list/error object
        # For now, just return the potentially partially populated list or empty list
    }

    # Sort the list alphabetically by Model name before returning
    return $modelList | Sort-Object -Property Model
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
# SECTION: Modern Folder Picker (Moved from BuildFFUVM_UI.ps1)
# --------------------------------------------------------------------------

# 1) Define a C# class that uses the correct GUIDs for IFileDialog, IFileOpenDialog, and FileOpenDialog,
#    while omitting conflicting "GetResults/GetSelectedItems" from IFileDialog.
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class ModernFolderBrowser
{
    // Flags for IFileDialog
    [Flags]
    private enum FileDialogOptions : uint
    {
        OverwritePrompt      = 0x00000002,
        StrictFileTypes      = 0x00000004,
        NoChangeDir          = 0x00000008,
        PickFolders          = 0x00000020,
        ForceFileSystem      = 0x00000040,
        AllNonStorageItems   = 0x00000080,
        NoValidate           = 0x00000100,
        AllowMultiSelect     = 0x00000200,
        PathMustExist        = 0x00000800,
        FileMustExist        = 0x00001000,
        CreatePrompt         = 0x00002000,
        ShareAware           = 0x00004000,
        NoReadOnlyReturn     = 0x00008000,
        NoTestFileCreate     = 0x00010000,
        DontAddToRecent      = 0x02000000,
        ForceShowHidden      = 0x10000000
    }

    // IFileDialog (GUID from Windows SDK)
    //  - Omitting GetResults / GetSelectedItems to avoid overshadow.
    [ComImport]
    [Guid("42F85136-DB7E-439C-85F1-E4075D135FC8")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IFileDialog
    {
        [PreserveSig]
        int Show(IntPtr parent);

        void SetFileTypes(uint cFileTypes, IntPtr rgFilterSpec);
        void SetFileTypeIndex(uint iFileType);
        void GetFileTypeIndex(out uint piFileType);
        void Advise(IntPtr pfde, out uint pdwCookie);
        void Unadvise(uint dwCookie);
        void SetOptions(FileDialogOptions fos);
        void GetOptions(out FileDialogOptions pfos);
        void SetDefaultFolder(IShellItem psi);
        void SetFolder(IShellItem psi);
        void GetFolder(out IShellItem ppsi);
        void GetCurrentSelection(out IShellItem ppsi);
        void SetFileName([MarshalAs(UnmanagedType.LPWStr)] string pszName);
        void GetFileName(out IntPtr pszName);
        void SetTitle([MarshalAs(UnmanagedType.LPWStr)] string pszTitle);
        void SetOkButtonLabel([MarshalAs(UnmanagedType.LPWStr)] string pszText);
        void SetFileNameLabel([MarshalAs(UnmanagedType.LPWStr)] string pszLabel);
        void GetResult(out IShellItem ppsi);
        void AddPlace(IShellItem psi, int fdap);
        void SetDefaultExtension([MarshalAs(UnmanagedType.LPWStr)] string pszDefaultExtension);
        void Close(int hr);
        void SetClientGuid(ref Guid guid);
        void ClearClientData();
        void SetFilter(IntPtr pFilter);

        // NOTE: We intentionally do NOT define GetResults and GetSelectedItems here,
        // because they cause overshadow warnings in IFileOpenDialog.
    }

    // IFileOpenDialog extends IFileDialog by adding 2 new methods with the same name,
    // which otherwise cause overshadow warnings. We'll define them only here.
    [ComImport]
    [Guid("D57C7288-D4AD-4768-BE02-9D969532D960")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IFileOpenDialog : IFileDialog
    {
        // These two come after the parent's vtable:
        void GetResults(out IntPtr ppenum);
        void GetSelectedItems(out IntPtr ppsai);
    }

    // The coclass for creating an IFileOpenDialog
    [ComImport]
    [Guid("DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7")]
    private class FileOpenDialog
    {
    }

    // IShellItem
    [ComImport]
    [Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellItem
    {
        void BindToHandler(IntPtr pbc, ref Guid bhid, ref Guid riid, out IntPtr ppv);
        void GetParent(out IShellItem ppsi);
        void GetDisplayName(uint sigdnName, out IntPtr ppszName);
        void GetAttributes(uint sfgaoMask, out uint psfgaoAttribs);
        void Compare(IShellItem psi, uint hint, out int piOrder);
    }

    private const uint SIGDN_FILESYSPATH = 0x80058000;

    public static string ShowDialog(string title, IntPtr parentHandle)
    {
        // Create COM dialog instance
        IFileOpenDialog dialog = (IFileOpenDialog)(new FileOpenDialog());

        // Get current options
        FileDialogOptions opts;
        dialog.GetOptions(out opts);

        // Add flags for picking folders
        opts |= FileDialogOptions.PickFolders | FileDialogOptions.PathMustExist | FileDialogOptions.ForceFileSystem;
        dialog.SetOptions(opts);

        // Set title
        if (!string.IsNullOrEmpty(title))
        {
            dialog.SetTitle(title);
        }

        // Show the dialog
        int hr = dialog.Show(parentHandle);
        // 0 = S_OK. 1 or 0x800704C7 often means user canceled. Return null if so.
        if (hr != 0)
        {
            if ((uint)hr == 0x800704C7 || hr == 1)
            {
                return null; // Canceled
            }
            else
            {
                Marshal.ThrowExceptionForHR(hr);
            }
        }

        // Retrieve the selection (IShellItem)
        IShellItem shellItem;
        dialog.GetResult(out shellItem);
        if (shellItem == null) return null;

        // Convert to file system path
        IntPtr pszPath = IntPtr.Zero;
        shellItem.GetDisplayName(SIGDN_FILESYSPATH, out pszPath);
        if (pszPath == IntPtr.Zero) return null;

        string folderPath = Marshal.PtrToStringAuto(pszPath);
        Marshal.FreeCoTaskMem(pszPath);

        return folderPath;
    }
}
"@ -Language CSharp

# 2) Define a PowerShell function that invokes our C# wrapper
function Show-ModernFolderPicker {
    param(
        [string]$Title = "Select a folder"
    )
    # For a simple test, pass IntPtr.Zero as the parent window handle
    return [ModernFolderBrowser]::ShowDialog($Title, [IntPtr]::Zero)
}

# --------------------------------------------------------------------------
# SECTION: Winget Management Functions
# --------------------------------------------------------------------------
function Search-WingetPackagesPublic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query
    )
    
    WriteLog "Searching Winget packages with query: '$Query'"
    try {
        # Call the shared Find-WinGetPackage function
        $results = Find-WinGetPackage -Query $Query -ErrorAction Stop
        WriteLog "Found $($results.Count) packages matching query '$Query'."
        return $results
    }
    catch {
        WriteLog "Error during Winget search: $($_.Exception.Message)"
        # Return an empty array or throw, depending on desired UI behavior
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

            # Call Install-WingetComponents (which also uses the callback internally)
            # Note: Install-WingetComponents currently only installs the module.
            # CLI installation/update might need separate handling or integration here if desired.
            # For now, we focus on the module install triggered by this check.
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
            # Set environment variable for Get-Application checks (if needed by sub-functions)
            # Set environment variables needed by Get-Application if called within this scope
            # Note: ForEach-Object -Parallel handles variable scoping differently than Runspaces.
            # Ensure Get-Application correctly accesses these if needed, potentially via $using: scope
            # or by passing them as parameters if Get-Application            # 2. Check previous Winget download and WinGetWin32Apps.json for duplicate entries
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
                $resultCode = -1 # Ensure resultCode reflects an error if status was empty
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
# Helper function to enqueue progress updates to the UI thread
function Invoke-ProgressUpdate {
    param(
        [Parameter(Mandatory)]
        [System.Collections.Concurrent.ConcurrentQueue[hashtable]]$ProgressQueue,
        [Parameter(Mandatory)]
        [string]$Identifier,
        [Parameter(Mandatory)]
        [string]$Status
    )
    $ProgressQueue.Enqueue(@{ Identifier = $Identifier; Status = $Status })
}

# Function to download and extract drivers for a specific Microsoft model (Modified for ForEach-Object -Parallel)
function Save-MicrosoftDriversTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$DriverItemData, # Pass data, not the UI object
        [Parameter(Mandatory = $true)]
        [string]$DriversFolder,
        [Parameter(Mandatory = $true)]
        [int]$WindowsRelease,
        [Parameter(Mandatory = $true)]
        [hashtable]$Headers, # Pass necessary headers
        [Parameter(Mandatory = $true)]
        [string]$UserAgent, # Pass UserAgent
        [Parameter()] # Made optional
        [System.Collections.Concurrent.ConcurrentQueue[hashtable]]$ProgressQueue = $null, # Default to null
        [Parameter()]
        [bool]$CompressToWim = $false # New parameter for compression
        # REMOVED: UI-related parameters
    )
        
    $modelName = $DriverItemData.Model
    $modelLink = $DriverItemData.Link
    $make = $DriverItemData.Make
    $status = "Getting download link..." # Initial local status
    $success = $false
    
    # Initial status update
    if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status "Checking..." }
    
    try {
        # Check if drivers already exist for this model
        $makeDriversPath = Join-Path -Path $DriversFolder -ChildPath $Make
        $modelPath = Join-Path -Path $makeDriversPath -ChildPath $modelName
        if (Test-Path -Path $modelPath -PathType Container) {
            $folderSize = (Get-ChildItem -Path $modelPath -Recurse | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
            if ($folderSize -gt 1MB) {
                $status = "Already downloaded"
                WriteLog "Drivers for '$modelName' already exist in '$modelPath'."
                # Enqueue this status before returning
                if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }
                # Return success immediately
                return [PSCustomObject]@{ Model = $modelName; Status = $status; Success = $true }
            }
            else {
                # Status is not set to error here, just log and continue
                WriteLog "Driver folder '$modelPath' for '$modelName' exists but is empty or very small. Re-downloading."
                # Allow the process to continue to re-download
            }
        }

        ### GET THE DOWNLOAD LINK
        $status = "Getting download link..."
        if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }
        WriteLog "Getting download page content for $modelName from $modelLink"
        $OriginalVerbosePreference = $VerbosePreference
        $VerbosePreference = 'SilentlyContinue'
        # Use passed-in UserAgent and Headers
        $downloadPageContent = Invoke-WebRequest -Uri $modelLink -UseBasicParsing -Headers $Headers -UserAgent $UserAgent
        $VerbosePreference = $OriginalVerbosePreference
        WriteLog "Complete"

        $status = "Parsing download page..."
        if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }
        WriteLog "Parsing download page for file"
        $scriptPattern = '<script>window.__DLCDetails__={(.*?)}<\/script>'
        $scriptMatch = [regex]::Match($downloadPageContent.Content, $scriptPattern)

        if ($scriptMatch.Success) {
            $scriptContent = $scriptMatch.Groups[1].Value
            # $downloadFilePattern = '"name":"(.*?)",.*?"url":"(.*?)"'
            $downloadFilePattern = '"name":"([^"]+\.(?:msi|zip))",[^}]*?"url":"(.*?)"'
            $downloadFileMatches = [regex]::Matches($scriptContent, $downloadFilePattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)


            $win10Link = $null
            $win10FileName = $null
            $win11Link = $null
            $win11FileName = $null

            # Iterate through all matches to find potential Win10 and Win11 links
            foreach ($downloadFile in $downloadFileMatches) {
                $currentFileName = $downloadFile.Groups[1].Value
                $fileUrl = $downloadFile.Groups[2].Value

                if ($currentFileName -match "Win10") {
                    $win10Link = $fileUrl
                    $win10FileName = $currentFileName
                    WriteLog "Found Win10 link: $win10FileName"
                }
                elseif ($currentFileName -match "Win11") {
                    $win11Link = $fileUrl
                    $win11FileName = $currentFileName
                    WriteLog "Found Win11 link: $win11FileName"
                }
            }

            # Decision logic to select the appropriate download link
            $downloadLink = $null
            $fileName = $null
            $downloadedVersion = $null # Track which version we are actually downloading

            if ($WindowsRelease -eq 10 -and $win10Link) {
                $downloadLink = $win10Link
                $fileName = $win10FileName
                $downloadedVersion = 10
                WriteLog "Exact match found for Win10."
            }
            elseif ($WindowsRelease -eq 11 -and $win11Link) {
                $downloadLink = $win11Link
                $fileName = $win11FileName
                $downloadedVersion = 11
                WriteLog "Exact match found for Win11."
            }
            elseif (-not $win10Link -and $win11Link) {
                # Only Win11 available, regardless of $WindowsRelease
                $downloadLink = $win11Link
                $fileName = $win11FileName
                $downloadedVersion = 11
                WriteLog "Exact match for Win$($WindowsRelease) not found. Falling back to available Win11 driver."
            }
            elseif ($win10Link -and -not $win11Link) {
                # Only Win10 available, regardless of $WindowsRelease
                $downloadLink = $win10Link
                $fileName = $win10FileName
                $downloadedVersion = 10
                WriteLog "Exact match for Win$($WindowsRelease) not found. Falling back to available Win10 driver."
            }
            # If both Win10 and Win11 links exist, but neither matches $WindowsRelease, $downloadLink remains $null.

            ### DOWNLOAD AND EXTRACT
            if ($downloadLink) {
                WriteLog "Selected Download Link for $modelName (Actual: Windows $downloadedVersion): $downloadLink"
                $status = "Downloading (Win$downloadedVersion)..." # Update status message
                if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }

                # Create directories
                if (-not (Test-Path -Path $DriversFolder)) {
                    WriteLog "Creating Drivers folder: $DriversFolder"
                    New-Item -Path $DriversFolder -ItemType Directory -Force | Out-Null
                }
                $makeDriversPath = Join-Path -Path $DriversFolder -ChildPath $Make
                $modelPath = Join-Path -Path $makeDriversPath -ChildPath $modelName
                if (-Not (Test-Path -Path $modelPath)) {
                    WriteLog "Creating model folder: $modelPath"
                    New-Item -Path $modelPath -ItemType Directory -Force | Out-Null
                }
                else {
                    WriteLog "Model folder already exists: $modelPath"
                }

                ### DOWNLOAD
                $filePath = Join-Path -Path $makeDriversPath -ChildPath ($fileName)
                WriteLog "Downloading $modelName driver file to $filePath"
                # Use Start-BitsTransferWithRetry
                Start-BitsTransferWithRetry -Source $downloadLink -Destination $filePath
                WriteLog "Download complete"

                $fileExtension = [System.IO.Path]::GetExtension($filePath).ToLower()

                ### EXTRACT
                if ($fileExtension -eq ".msi") {
                    $status = "Extracting MSI..." # Set initial status
                    if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }

                    # Loop indefinitely to wait for mutex and handle MSIExec exit codes by catching errors
                    while ($true) {
                        $mutexClear = $false

                        # 1. Check Mutex
                        try {
                            $Mutex = [System.Threading.Mutex]::OpenExisting("Global\_MSIExecute")
                            $Mutex.Dispose()
                            $status = "Waiting for MSIExec..."
                            if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }
                            WriteLog "Another MSIExec installer is running (Mutex Held). Waiting 5 seconds before rechecking for $modelName..."
                            Start-Sleep -Seconds 5
                            continue # Go back to start of while loop to re-check mutex
                        }
                        catch [System.Threading.WaitHandleCannotBeOpenedException] {
                            # Mutex is clear, proceed to extraction attempt
                            WriteLog "Mutex clear. Proceeding with MSI extraction attempt for $modelName."
                            $status = "Extracting MSI..."
                            if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }
                            $mutexClear = $true
                        }
                        catch {
                            # Handle other potential errors when checking the mutex
                            WriteLog "Warning: Error checking MSIExec mutex for $($modelName): $_. Proceeding with caution."
                            $status = "Extracting MSI (Mutex Error)..."
                            if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }
                            $mutexClear = $true # Proceed despite mutex error
                        }

                        # 2. Attempt Extraction (only if mutex was clear or error occurred during check)
                        if ($mutexClear) {
                            WriteLog "Extracting MSI file to $modelPath"
                            $arguments = "/a `"$($filePath)`" /qn TARGETDIR=`"$($modelPath)`""
                            try {
                                # Use Invoke-Process. It will throw an error for any non-zero exit code.
                                Invoke-Process -FilePath "msiexec.exe" -ArgumentList $arguments -Wait $true -ErrorAction Stop | Out-Null
                                
                                # If Invoke-Process succeeded (didn't throw), extraction is complete.
                                WriteLog "Extraction complete for $modelName (Exit Code 0)."
                                break # Success, exit the while loop
                            }
                            catch {
                                # Catch errors thrown by Invoke-Process
                                $errorMessage = $_.Exception.Message
                                if ($errorMessage -match 'Process exited with code 1618') {
                                    # Specific handling for MSIExec busy error (1618)
                                    WriteLog "MSIExec collision detected (Exit Code 1618) for $modelName. Retrying after wait..."
                                    $status = "Waiting (MSI Collision)..."
                                    if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }
                                    Start-Sleep -Seconds 5 # Wait before retrying
                                    continue # Go back to start of while loop to re-check mutex/retry
                                }
                                else {
                                    # Handle other errors from Invoke-Process (e.g., file not found, permissions, other exit codes)
                                    WriteLog "Error during MSI extraction process for $($modelName): $errorMessage"
                                    throw # Re-throw the original exception to be caught by the outer try/catch
                                }
                            }
                        } # End if ($mutexClear)
                    } # End while ($true) - Loop runs until break or throw
                }
                elseif ($fileExtension -eq ".zip") {
                    $status = "Extracting ZIP..." # Set status before extraction
                    if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }
                    WriteLog "Extracting ZIP file to $modelPath"
                    $ProgressPreference = 'SilentlyContinue'
                    Expand-Archive -Path $filePath -DestinationPath $modelPath -Force
                    $ProgressPreference = 'Continue'
                    WriteLog "Extraction complete"
                }
                else {
                    WriteLog "Unsupported file type: $fileExtension"
                    throw "Unsupported file type: $fileExtension"
                }
                # Remove downloaded file
                $status = "Cleaning up..."
                if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }
                WriteLog "Removing $filePath"
                Remove-Item -Path $filePath -Force
                WriteLog "Cleanup complete." # Changed log message slightly
        
                # --- Compress to WIM if requested ---
                if ($CompressToWim) {
                    $status = "Compressing..."
                    if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }
                    $wimFileName = "$($modelName).wim"
                    # Corrected WIM path: WIM file should be next to the model folder, not inside it.
                    $destinationWimPath = Join-Path -Path $makeDriversPath -ChildPath $wimFileName 
                    WriteLog "Compressing '$modelPath' to '$destinationWimPath'..."
                    try {
                        # Use the function from the imported common module
                        $compressResult = Compress-DriverFolderToWim -SourceFolderPath $modelPath -DestinationWimPath $destinationWimPath -WimName $modelName -WimDescription $modelName -ErrorAction Stop
                        if ($compressResult) {
                            WriteLog "Compression successful for '$modelName'."
                            $status = "Completed & Compressed"
                        }
                        else {
                            WriteLog "Compression failed for '$modelName'. Check verbose/error output from Compress-DriverFolderToWim."
                            $status = "Completed (Compression Failed)"
                            # Don't mark overall success as false, download/extract succeeded
                        }
                    }
                    catch {
                        WriteLog "Error during compression for '$modelName': $($_.Exception.Message)"
                        $status = "Completed (Compression Error)"
                        # Don't mark overall success as false
                    }
                }
                else {
                    $status = "Completed" # Final status if not compressing
                }
                # --- End Compression ---
        
                $success = $true # Mark success as download/extract was okay
            } # End if/elseif for .msi/.zip
            else {
                WriteLog "No suitable download link found for Windows $WindowsRelease (or fallback) for model $modelName."
                $status = "Error: No Win$($WindowsRelease)/Fallback link"
                $success = $false
            }
        }
        else {
            WriteLog "Failed to parse the download page for the driver file for model $modelName."
            $status = "Error: Parse failed"
            $success = $false
        }
    }
    catch {
        $status = "Error: $($_.Exception.Message.Split('.')[0])" # Shorten error message
        WriteLog "Error saving Microsoft drivers for $($modelName): $($_.Exception.Message)"
        $success = $false
        # Enqueue the error status before returning
        if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }
        # Ensure return object is created even on error
        return [PSCustomObject]@{ Model = $modelName; Status = $status; Success = $success }
    }
    
    # Enqueue the final status (success or error) before returning
    if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }
    
    # Return the final status (this is still used by Receive-Job for final confirmation)
    return [PSCustomObject]@{ Model = $modelName; Status = $status; Success = $success }
}
# Function to download and extract drivers for a specific Dell model (Modified for ForEach-Object -Parallel)
function Save-DellDriversTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$DriverItemData, # Contains Model property
        [Parameter(Mandatory = $true)]
        [string]$DriversFolder,         # Base drivers folder (e.g., C:\FFUDevelopment\Drivers)
        [Parameter(Mandatory = $true)]
        [string]$WindowsArch,
        [Parameter(Mandatory = $true)]
        [int]$WindowsRelease,
        [Parameter(Mandatory = $true)]
        [string]$DellCatalogXmlPath,    # Path to the *existing* central XML catalog file
        [Parameter()] # Made optional
        [System.Collections.Concurrent.ConcurrentQueue[hashtable]]$ProgressQueue = $null, # Default to null
        [Parameter()]
        [bool]$CompressToWim = $false # New parameter for compression
        # REMOVED: UI-related parameters, Catalog download/extract params
    )
        
    $modelName = $DriverItemData.Model
    $make = "Dell" # Hardcoded for this task
    $status = "Starting..." # Initial local status
    $success = $false
    
    # Initial status update
    if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status "Checking..." }
    
    $makeDriversPath = Join-Path -Path $DriversFolder -ChildPath $Make
    $modelPath = Join-Path -Path $makeDriversPath -ChildPath $modelName

    try {
        # 1. Check if drivers already exist for this model (final destination)
        if (Test-Path -Path $modelPath -PathType Container) {
            $folderSize = (Get-ChildItem -Path $modelPath -Recurse | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
            if ($folderSize -gt 1MB) {
                $status = "Already downloaded"
                WriteLog "Drivers for '$modelName' already exist in '$modelPath'."
                if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }
                return [PSCustomObject]@{ Model = $modelName; Status = $status; Success = $true }
            }
            else {
                WriteLog "Driver folder '$modelPath' for '$modelName' exists but is empty/small. Re-downloading."
            }
        }

        # 2. REMOVED: Download and Extract Catalog - This is now done centrally in the UI script

        # 3. Parse the *EXISTING* XML and Find Drivers for *this specific model*
        $status = "Finding drivers..."
        if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }

        # Check if the provided XML path exists
        if (-not (Test-Path -Path $DellCatalogXmlPath -PathType Leaf)) {
            throw "Dell Catalog XML file not found at specified path: $DellCatalogXmlPath"
        }

        WriteLog "Parsing existing Dell Catalog XML for model '$modelName' from: $DellCatalogXmlPath"
        [xml]$xmlContent = Get-Content -Path $DellCatalogXmlPath
        # Check if manifest and baseLocation exist before accessing
        if ($null -eq $xmlContent.manifest -or $null -eq $xmlContent.manifest.baseLocation) {
            throw "Invalid Dell Catalog XML format: Missing 'manifest' or 'baseLocation' element in '$DellCatalogXmlPath'."
        }
        $baseLocation = "https://" + $xmlContent.manifest.baseLocation + "/"
        $latestDrivers = @{} # Hashtable to store latest drivers for this model

        # Ensure SoftwareComponent is iterable
        $softwareComponents = @($xmlContent.Manifest.SoftwareComponent | Where-Object { $_.ComponentType.value -eq "DRVR" })
        $modelSpecificDriversFound = $false

        WriteLog "Searching $($softwareComponents.Count) DRVR components in '$DellCatalogXmlPath' for model '$modelName'..."

        foreach ($component in $softwareComponents) {
            # Check if SupportedSystems and Brand exist
            if ($null -eq $component.SupportedSystems -or $null -eq $component.SupportedSystems.Brand) { continue }
            # Ensure Model is iterable
            $componentModels = @($component.SupportedSystems.Brand.Model)
            if ($null -eq $componentModels) { continue }

            $modelMatch = $false
            foreach ($item in $componentModels) {
                # Check if Display and its CDATA section exist before accessing
                if ($null -ne $item.Display -and $null -ne $item.Display.'#cdata-section' -and $item.Display.'#cdata-section'.Trim() -eq $modelName) {
                    $modelMatch = $true
                    break
                }
            }

            if ($modelMatch) {
                # Model matches, now check OS compatibility
                $validOS = $null
                if ($null -ne $component.SupportedOperatingSystems) {
                    # Ensure OperatingSystem is always an array/collection
                    $osList = @($component.SupportedOperatingSystems.OperatingSystem)

                    if ($null -ne $osList) {
                        if ($WindowsRelease -le 11) {
                            # Client OS check
                            $validOS = $osList | Where-Object { $_.osArch -eq $WindowsArch } | Select-Object -First 1
                        }
                        else {
                            # Server OS check
                            $osCodePattern = switch ($WindowsRelease) {
                                2016 { "W14" } # Note: Dell uses W14 for Server 2016
                                2019 { "W19" }
                                2022 { "W22" }
                                2025 { "W25" }
                                default { "W22" } # Fallback, adjust as needed
                            }
                            $validOS = $osList | Where-Object { ($_.osArch -eq $WindowsArch) -and ($_.osCode -match $osCodePattern) } | Select-Object -First 1
                        }
                    }
                }

                if ($validOS) {
                    $modelSpecificDriversFound = $true # Mark that we found at least one relevant driver component
                    $driverPath = $component.path
                    $downloadUrl = $baseLocation + $driverPath
                    $driverFileName = [System.IO.Path]::GetFileName($driverPath)
                    # Check if Name, Display, and CDATA exist
                    $name = "UnknownDriver" # Default name
                    if ($null -ne $component.Name -and $null -ne $component.Name.Display -and $null -ne $component.Name.Display.'#cdata-section') {
                        $name = $component.Name.Display.'#cdata-section'
                        $name = $name -replace '[\\\/\:\*\?\"\<\>\| ]', '_' -replace '[\,]', '-'
                    }
                    # Check if Category, Display, and CDATA exist
                    $category = "Uncategorized" # Default category
                    if ($null -ne $component.Category -and $null -ne $component.Category.Display -and $null -ne $component.Category.Display.'#cdata-section') {
                        $category = $component.Category.Display.'#cdata-section'
                        $category = $category -replace '[\\\/\:\*\?\"\<\>\| ]', '_'
                    }
                    $version = [version]"0.0" # Default version
                    if ($null -ne $component.vendorVersion) {
                        try { $version = [version]$component.vendorVersion } catch { WriteLog "Warning: Could not parse version '$($component.vendorVersion)' for driver '$name'. Using 0.0." }
                    }
                    $namePrefix = ($name -split '-')[0] # Group by prefix within category

                    # Store the latest version for each category/prefix combination
                    if (-not $latestDrivers.ContainsKey($category)) { $latestDrivers[$category] = @{} }
                    if (-not $latestDrivers[$category].ContainsKey($namePrefix) -or $latestDrivers[$category][$namePrefix].Version -lt $version) {
                        $latestDrivers[$category][$namePrefix] = [PSCustomObject]@{
                            Name           = $name
                            DownloadUrl    = $downloadUrl
                            DriverFileName = $driverFileName
                            Version        = $version
                            Category       = $category
                        }
                    }
                }
            } # End if ($modelMatch)
        } # End foreach ($component in $softwareComponents)

        if (-not $modelSpecificDriversFound) {
            $status = "No drivers found for OS"
            WriteLog "No drivers found for model '$modelName' matching Windows Release '$WindowsRelease' and Arch '$WindowsArch' in '$DellCatalogXmlPath'."
            if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }
            # Consider this success as the process completed, just no drivers to download
            return [PSCustomObject]@{ Model = $modelName; Status = $status; Success = $true }
        }

        # 4. Download and Extract Found Drivers (Logic remains largely the same)
        $totalDriversToProcess = ($latestDrivers.Values | ForEach-Object { $_.Values.Count } | Measure-Object -Sum).Sum
        $driversProcessed = 0
        WriteLog "Found $totalDriversToProcess latest driver packages to download for $modelName."

        # Ensure base directories exist before loop
        if (-not (Test-Path -Path $makeDriversPath)) { New-Item -Path $makeDriversPath -ItemType Directory -Force | Out-Null }
        if (-not (Test-Path -Path $modelPath)) { New-Item -Path $modelPath -ItemType Directory -Force | Out-Null }

        foreach ($category in $latestDrivers.Keys) {
            foreach ($driver in $latestDrivers[$category].Values) {
                $driversProcessed++
                $status = "Downloading $($driversProcessed)/$($totalDriversToProcess): $($driver.Name)"
                if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }

                $downloadFolder = Join-Path -Path $modelPath -ChildPath $driver.Category
                $driverFilePath = Join-Path -Path $downloadFolder -ChildPath $driver.DriverFileName
                $extractFolder = Join-Path -Path $downloadFolder -ChildPath $driver.DriverFileName.TrimEnd($driver.DriverFileName[-4..-1])

                # Check if already extracted (more robust check)
                if (Test-Path -Path $extractFolder -PathType Container) {
                    $extractSize = (Get-ChildItem -Path $extractFolder -Recurse -Exclude *.log | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                    if ($extractSize -gt 1KB) {
                        WriteLog "Driver already extracted: $($driver.Name) in $extractFolder. Skipping."
                        continue # Skip to next driver
                    }
                }
                # Check if download file exists but extraction folder doesn't or is empty
                if (Test-Path -Path $driverFilePath -PathType Leaf) {
                    WriteLog "Download file $($driver.DriverFileName) exists, but extraction folder '$extractFolder' is missing or empty. Will attempt extraction."
                    # Proceed to extraction logic below
                }
                else {
                    # Download the driver
                    WriteLog "Downloading driver: $($driver.Name) ($($driver.DriverFileName))"
                    if (-not (Test-Path -Path $downloadFolder)) {
                        WriteLog "Creating download folder: $downloadFolder"
                        New-Item -Path $downloadFolder -ItemType Directory -Force | Out-Null
                    }
                    WriteLog "Downloading from: $($driver.DownloadUrl) to $driverFilePath"
                    try {
                        Start-BitsTransferWithRetry -Source $driver.DownloadUrl -Destination $driverFilePath
                        WriteLog "Driver downloaded: $($driver.DriverFileName)"
                    }
                    catch {
                        WriteLog "Failed to download driver: $($driver.DownloadUrl). Error: $($_.Exception.Message). Skipping."
                        # Update status for this specific driver failure? Maybe too granular.
                        continue # Skip to next driver
                    }
                }


                # Extract the driver
                $status = "Extracting $($driversProcessed)/$($totalDriversToProcess): $($driver.Name)"
                if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }
                
                # Ensure extraction folder exists before attempting extraction
                if (-not (Test-Path -Path $extractFolder)) {
                    WriteLog "Creating extraction folder: $extractFolder"
                    New-Item -Path $extractFolder -ItemType Directory -Force | Out-Null
                }

                # Dell uses /e to extact the entire DUP while /drivers to extract only the drivers
                # In many cases /drivers will extract drivers for mutliple OS versions
                # Which can cause many duplicate files and bloat your driver folder
                # /e seems to be better and only extracts what is necessary and has less issues
                # We will default to using /e, but will fall back to /drivers if content cannot be found

                $arguments = "/s /e=`"$extractFolder`" /l=`"$extractFolder\log.log`""
                $altArguments = "/s /drivers=`"$extractFolder`" /l=`"$extractFolder\log.log`""
                $extractionSuccess = $false
                try {
                    # Handle special cases (Chipset/Network) - Check if OS is Server
                    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem # Get OS info within the task scope
                    $isServer = $osInfo.Caption -match 'server'
                    
                    # Chipset drivers may require killing child processes in some cases
                    if ($driver.Category -eq "Chipset") {
                        WriteLog "Extracting Chipset driver: $driverFilePath $arguments"
                        $process = Invoke-Process -FilePath $driverFilePath -ArgumentList $arguments -Wait $false
                        Start-Sleep -Seconds 5 # Allow time for extraction
                        WriteLog "Extraction exited with exit code: $($process.ExitCode)"
                        # Attempt to gracefully close child process if needed (logic from original script)
                        $childProcesses = Get-CimInstance Win32_Process -Filter "ParentProcessId = $($process.Id)"
                        if ($childProcesses) {
                            $latestProcess = $childProcesses | Sort-Object CreationDate -Descending | Select-Object -First 1
                            WriteLog "Stopping child process for Chipset driver: $($latestProcess.Name) (PID: $($latestProcess.ProcessId))"
                            Stop-Process -Id $latestProcess.ProcessId -Force -ErrorAction SilentlyContinue
                            Start-Sleep -Seconds 1
                        }
                    }
                    # Network drivers on client OS may require killing child processes
                    elseif ($driver.Category -eq "Network" -and -not $isServer) {
                        WriteLog "Extracting Network driver: $driverFilePath $arguments"
                        $process = Invoke-Process -FilePath $driverFilePath -ArgumentList $arguments -Wait $false
                        Start-Sleep -Seconds 5
                        WriteLog "Extraction exited with exit code: $($process.ExitCode)"
                        if (-not $process.HasExited) {
                            $childProcesses = Get-CimInstance Win32_Process -Filter "ParentProcessId = $($process.Id)"
                            if ($childProcesses) {
                                $latestProcess = $childProcesses | Sort-Object CreationDate -Descending | Select-Object -First 1
                                WriteLog "Stopping child process for Network driver: $($latestProcess.Name) (PID: $($latestProcess.ProcessId))"
                                Stop-Process -Id $latestProcess.ProcessId -Force -ErrorAction SilentlyContinue
                                Start-Sleep -Seconds 1
                            }
                        }
                    }
                    else {
                        WriteLog "Extracting driver: $driverFilePath $arguments"
                        $process = Invoke-Process -FilePath $driverFilePath -ArgumentList $arguments
                        WriteLog "Extraction exited with exit code: $($process.ExitCode)"
                    }

                    # Verify extraction (check if folder has content)
                    if (Test-Path -Path $extractFolder -PathType Container) {
                        $extractSize = (Get-ChildItem -Path $extractFolder -Recurse -Exclude *.log | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                        if ($extractSize -gt 1KB) {
                            $extractionSuccess = $true
                            WriteLog "Extraction successful (Method 1) for $driverFilePath $arguments"
                        }
                    }

                    # If primary extraction failed or folder is empty, try alternative
                    if (-not $extractionSuccess) {
                        # $arguments = "/s /e=`"$extractFolder`""
                        # $altArguments = "/s /drivers=`"$extractFolder`""
                        WriteLog "Extraction with $arguments failed or resulted in empty folder for $driverFilePath. Retrying with $altArguments"
                        # Clean up potentially empty folder before retrying
                        Remove-Item -Path $extractFolder -Recurse -Force -ErrorAction SilentlyContinue
                        New-Item -Path $extractFolder -ItemType Directory -Force | Out-Null # Recreate empty folder
                        $process = Invoke-Process -FilePath $driverFilePath -ArgumentList $altArguments
                        WriteLog "Extraction exited with exit code: $($process.ExitCode)"

                        # Verify extraction again
                        if (Test-Path -Path $extractFolder -PathType Container) {
                            $extractSize = (Get-ChildItem -Path $extractFolder -Recurse -Exclude *.log | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                            if ($extractSize -gt 1KB) {
                                $extractionSuccess = $true
                                WriteLog "Extraction successful (Method 2) for $driverFilePath $altArguments"
                            }
                        }
                    }
                }
                catch {
                    WriteLog "Error during extraction process for $($driver.DriverFileName): $($_.Exception.Message). Trying alternative method."
                    # Try alternative method on any error during the first attempt block
                    try {
                        if (Test-Path -Path $extractFolder) {
                            # Clean up before retry if needed
                            Remove-Item -Path $extractFolder -Recurse -Force -ErrorAction SilentlyContinue
                        }
                        New-Item -Path $extractFolder -ItemType Directory -Force | Out-Null
                        # $arguments = "/s /e=`"$extractFolder`""
                        # $altArguments = "/s /drivers=`"$extractFolder`""
                        WriteLog "Extracting driver (Method 2): $driverFilePath $altArguments"
                        $process = Invoke-Process -FilePath $driverFilePath -ArgumentList $altArguments
                        WriteLog "Extraction exited with exit code: $($process.ExitCode)"

                        # Verify extraction again
                        if (Test-Path -Path $extractFolder -PathType Container) {
                            $extractSize = (Get-ChildItem -Path $extractFolder -Recurse -Exclude *.log | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                            if ($extractSize -gt 1KB) {
                                $extractionSuccess = $true
                                WriteLog "Extraction successful (Method 2) for $driverFilePath."
                            }
                        }
                    }
                    catch {
                        WriteLog "Alternative extraction method also failed for $($driver.DriverFileName): $($_.Exception.Message)."
                        # Extraction failed completely
                    }
                }

                # Cleanup downloaded file only if extraction was successful
                if ($extractionSuccess) {
                    WriteLog "Deleting driver file: $driverFilePath"
                    Remove-Item -Path $driverFilePath -Force -ErrorAction SilentlyContinue
                    WriteLog "Driver file deleted: $driverFilePath"
                }
                else {
                    WriteLog "Extraction failed for $($driver.DriverFileName). Downloaded file kept at $driverFilePath for inspection."
                    # Update status to indicate partial failure?
                }

            } # End foreach ($driver in $latestDrivers)
        } # End foreach ($category in $latestDrivers)
            
        # --- Compress to WIM if requested (after all drivers processed) ---
        if ($CompressToWim) {
            $status = "Compressing..."
            if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }
            $wimFileName = "$($modelName).wim"
            $destinationWimPath = Join-Path -Path $makeDriversPath -ChildPath $wimFileName
            WriteLog "Compressing '$modelPath' to '$destinationWimPath'..."
            try {
                $compressResult = Compress-DriverFolderToWim -SourceFolderPath $modelPath -DestinationWimPath $destinationWimPath -WimName $modelName -WimDescription $modelName -ErrorAction Stop
                if ($compressResult) {
                    WriteLog "Compression successful for '$modelName'."
                    $status = "Completed & Compressed"
                }
                else {
                    WriteLog "Compression failed for '$modelName'. Check verbose/error output from Compress-DriverFolderToWim."
                    $status = "Completed (Compression Failed)"
                }
            }
            catch {
                WriteLog "Error during compression for '$modelName': $($_.Exception.Message)"
                $status = "Completed (Compression Error)"
            }
        }
        else {
            $status = "Completed" # Final status if not compressing
        }
        # --- End Compression ---
            
        $success = $true # Mark success as download/extract was okay
            
    }
    catch {
        $status = "Error: $($_.Exception.Message.Split('.')[0])" # Shorten error message
        WriteLog "Error saving Dell drivers for $($modelName): $($_.Exception.ToString())" # Log full exception string
        $success = $false
        # Enqueue the error status before returning
        if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }
        # Ensure return object is created even on error
        return [PSCustomObject]@{ Model = $modelName; Status = $status; Success = $success }
    }
    # REMOVED: Finally block that cleaned up temp catalog files

    # Enqueue the final status (success or error) before returning
    if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }

    # Return the final status
    return [PSCustomObject]@{ Model = $modelName; Status = $status; Success = $success }
}
# Function to download and extract drivers for a specific HP model (Designed for ForEach-Object -Parallel)
function Save-HPDriversTask {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$DriverItemData, # Contains Make, Model
        [Parameter(Mandatory = $true)]
        [string]$DriversFolder,
        [Parameter(Mandatory = $true)]
        [ValidateSet("x64", "x86", "ARM64")]
        [string]$WindowsArch,
        [Parameter(Mandatory = $true)]
        [ValidateSet(10, 11)]
        [int]$WindowsRelease,
        [Parameter(Mandatory = $true)]
        [string]$WindowsVersion, # e.g., 22H2, 23H2, etc.
        [Parameter()] # Made optional
        [System.Collections.Concurrent.ConcurrentQueue[hashtable]]$ProgressQueue = $null, # Default to null
        [Parameter()]
        [bool]$CompressToWim = $false # New parameter for compression
    )
            
    $modelName = $DriverItemData.Model
    $make = $DriverItemData.Make # Should be 'HP'
    $identifier = $modelName # Unique identifier for progress updates
    $hpDriversBaseFolder = Join-Path -Path $DriversFolder -ChildPath $make # Changed variable name for clarity
    $platformListXml = Join-Path -Path $hpDriversBaseFolder -ChildPath "PlatformList.xml"
    $modelSpecificFolder = Join-Path -Path $hpDriversBaseFolder -ChildPath ($modelName -replace '[\\/:"*?<>|]', '_') # Sanitize model name for folder path
    $finalStatus = "" # Initialize final status
    $successState = $true # Assume success unless an operation fails
    
    if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status "Checking HP drivers for $modelName..." }
    
    # Ensure the base HP folder exists
    if (-not (Test-Path -Path $hpDriversBaseFolder -PathType Container)) {
        try {
            New-Item -Path $hpDriversBaseFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
            WriteLog "Created base HP driver folder: $hpDriversBaseFolder"
        }
        catch {
            $errMsg = "Failed to create base HP driver folder '$hpDriversBaseFolder': $($_.Exception.Message)"
            WriteLog $errMsg
            if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status "Error: Create HP dir failed" }
            return [PSCustomObject]@{ Identifier = $identifier; Status = "Error: Create HP dir failed"; Success = $false }
        }
    }

    # Check if drivers already exist for this model
    if (Test-Path -Path $modelSpecificFolder -PathType Container) {
        WriteLog "HP drivers for '$identifier' already exist in '$modelSpecificFolder'."
        if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status "Found existing HP drivers for $identifier. Verifying..." }
        
        if ($CompressToWim) {
            $wimFilePath = Join-Path -Path $hpDriversBaseFolder -ChildPath "$($identifier).wim" # WIM in base HP folder, next to model folder

            if (Test-Path -Path $wimFilePath -PathType Leaf) {
                $finalStatus = "Already downloaded (WIM exists)"
                WriteLog "WIM file $wimFilePath already exists for $identifier."
            }
            else {
                WriteLog "WIM file $wimFilePath not found for $identifier. Attempting compression of existing folder '$modelSpecificFolder'."
                if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status "Compressing existing HP drivers for $identifier..." }
                try {
                    Compress-DriverFolderToWim -SourceFolderPath $modelSpecificFolder -DestinationWimPath $wimFilePath -WimName $identifier -WimDescription "Drivers for $identifier" -ErrorAction Stop
                    $finalStatus = "Already downloaded & Compressed"
                    WriteLog "Successfully compressed existing drivers for $identifier to $wimFilePath."
                }
                catch {
                    $errMsgForLog = "Error compressing existing drivers for $($identifier): $($_.Exception.Message)"
                    WriteLog $errMsgForLog
                    $finalStatus = "Already downloaded (Compression failed: $($_.Exception.Message.Split([Environment]::NewLine)[0]))"
                    # $successState = false # Keep true if folder exists, compression is secondary
                }
            }
        }
        else {
            # Not compressing
            $finalStatus = "Already downloaded"
        }
        if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $finalStatus }
        return [PSCustomObject]@{
            Identifier = $identifier
            Status     = $finalStatus
            Success    = $successState 
        }
    }

    # If folder does not exist, proceed with download and extraction
    WriteLog "HP drivers for '$identifier' not found locally. Starting download process..."
    if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status "Downloading HP drivers for $identifier..." }

    try {
        # Ensure PlatformList.xml exists (it should have been downloaded by Get-HPDriversModelList)
        if (-not (Test-Path -Path $platformListXml)) {
            # Attempt to download/extract it again if missing
            WriteLog "PlatformList.xml not found for HP task, attempting download/extract..."
            $platformListUrl = 'https://hpia.hpcloud.hp.com/ref/platformList.cab'
            $platformListCab = Join-Path -Path $hpDriversBaseFolder -ChildPath "platformList.cab"
            # Base folder already checked/created
            Start-BitsTransferWithRetry -Source $platformListUrl -Destination $platformListCab -ErrorAction Stop
            if (Test-Path -Path $platformListXml) { Remove-Item -Path $platformListXml -Force }
            Invoke-Process -FilePath "expand.exe" -ArgumentList @("`"$platformListCab`"", "`"$platformListXml`"") -ErrorAction Stop | Out-Null
            WriteLog "PlatformList.xml download/extract complete for HP task."
            if (-not (Test-Path -Path $platformListXml)) {
                throw "Failed to obtain PlatformList.xml for HP driver task."
            }
        }

        # Parse PlatformList.xml to find SystemID and OSReleaseID for the specific model
        WriteLog "Parsing $platformListXml for model '$modelName' details..."
        [xml]$platformListContent = Get-Content -Path $platformListXml -Raw -Encoding UTF8 -ErrorAction Stop
        $platformNode = $platformListContent.ImagePal.Platform | Where-Object { $_.ProductName.'#text' -match "^$([regex]::Escape($modelName))$" } | Select-Object -First 1

        if ($null -eq $platformNode) {
            throw "Model '$modelName' not found in PlatformList.xml."
        }

        $systemID = $platformNode.SystemID
        # --- OS Node Selection with Fallback Logic ---
        $selectedOSNode = $null
        $selectedOSVersion = $null
        $selectedOSRelease = $WindowsRelease # Start with the requested release

        # Complete list of Windows 11 feature-update versions (newest to oldest)
        $win11Versions = @(
            "24H2", "23H2", "22H2", "21H2"
        )

        # Complete list of Windows 10 feature-update versions (newest to oldest)
        $win10Versions = @(
            "22H2", "21H2", "21H1", "20H2", "2004", "1909", "1903", "1809", "1803", "1709", "1703", "1607", "1511", "1507"
        )

        # Helper function to find a matching OS node for a given release and version list
        function Find-MatchingOSNode {
            param(
                [int]$ReleaseToSearch,
                [array]$VersionsToSearch
            )
            $osNodesForRelease = $platformNode.OS | Where-Object {
                ($ReleaseToSearch -eq 11 -and $_.IsWindows11 -contains 'true') -or
                ($ReleaseToSearch -eq 10 -and ($null -eq $_.IsWindows11 -or $_.IsWindows11 -notcontains 'true'))
            }

            if ($null -eq $osNodesForRelease) { return $null } 

            foreach ($version in $VersionsToSearch) {
                foreach ($osNode in $osNodesForRelease) {
                    $releaseIDs = $osNode.OSReleaseIdFileName -replace 'H', 'h' -split ' '
                    if ($releaseIDs -contains $version.ToLower()) {
                        return @{ Node = $osNode; Version = $version }
                    }
                }
            }
            return $null 
        }

        # 1. Attempt Exact Match (Requested Release and Version)
        WriteLog "Attempting to find exact match for Win$($WindowsRelease) ($($WindowsVersion))..."
        $exactMatchResult = Find-MatchingOSNode -ReleaseToSearch $WindowsRelease -VersionsToSearch @($WindowsVersion)
        if ($null -ne $exactMatchResult) {
            $selectedOSNode = $exactMatchResult.Node
            $selectedOSVersion = $exactMatchResult.Version
            WriteLog "Exact match found: Win$($selectedOSRelease) ($($selectedOSVersion))."
        }
        else {
            WriteLog "Exact match not found for Win$($WindowsRelease) ($($WindowsVersion))."
            # 2. Fallback: Same Release, Other Versions (Newest First)
            WriteLog "Attempting fallback within Win$($WindowsRelease)..."
            $versionsForCurrentRelease = if ($WindowsRelease -eq 11) { $win11Versions } else { $win10Versions }
            $fallbackVersions = $versionsForCurrentRelease | Where-Object { $_ -ne $WindowsVersion }
            $fallbackResult = Find-MatchingOSNode -ReleaseToSearch $WindowsRelease -VersionsToSearch $fallbackVersions
            if ($null -ne $fallbackResult) {
                $selectedOSNode = $fallbackResult.Node
                $selectedOSVersion = $fallbackResult.Version
                WriteLog "Fallback successful within Win$($selectedOSRelease). Using version: $($selectedOSVersion)."
            }
            else {
                WriteLog "Fallback within Win$($WindowsRelease) unsuccessful."
                # 3. Fallback: Other Release, Versions (Newest First)
                $otherRelease = if ($WindowsRelease -eq 11) { 10 } else { 11 }
                WriteLog "Attempting fallback to Win$($otherRelease)..."
                $versionsForOtherRelease = if ($otherRelease -eq 11) { $win11Versions } else { $win10Versions }
                $otherFallbackResult = Find-MatchingOSNode -ReleaseToSearch $otherRelease -VersionsToSearch $versionsForOtherRelease
                if ($null -ne $otherFallbackResult) {
                    $selectedOSNode = $otherFallbackResult.Node
                    $selectedOSVersion = $otherFallbackResult.Version
                    $selectedOSRelease = $otherRelease 
                    WriteLog "Fallback successful to Win$($selectedOSRelease). Using version: $($selectedOSVersion)."
                }
                else {
                    WriteLog "Fallback to Win$($otherRelease) also failed."
                }
            }
        }

        if ($null -eq $selectedOSNode) {
            $allAvailableVersions = @()
            if ($platformNode.OS) {
                foreach ($osNode in $platformNode.OS) {
                    $osRel = if ($osNode.IsWindows11 -contains 'true') { 11 } else { 10 }
                    $relIDs = $osNode.OSReleaseIdFileName -replace 'H', 'h' -split ' '
                    foreach ($id in $relIDs) { $allAvailableVersions += "Win$($osRel) $($id)" }
                }
            }
            $availableVersionsString = ($allAvailableVersions | Select-Object -Unique) -join ', '
            if ([string]::IsNullOrWhiteSpace($availableVersionsString)) { $availableVersionsString = "None" }
            throw "Could not find any suitable OS driver pack for model '$modelName' matching requested or fallback versions (Win$($WindowsRelease) $WindowsVersion). Available: $availableVersionsString"
        }

        $osReleaseIdFileName = $selectedOSNode.OSReleaseIdFileName -replace 'H', 'h' 
        WriteLog "Using SystemID: $systemID and OS Info: Win$($selectedOSRelease) ($($selectedOSVersion)) for '$modelName'"
        $archSuffix = $WindowsArch -replace "^x", "" 
        $modelRelease = "$($systemID)_$($archSuffix)_$($selectedOSRelease).0.$($selectedOSVersion.ToLower())"
        $driverCabUrl = "https://hpia.hpcloud.hp.com/ref/$systemID/$modelRelease.cab"
        $driverCabFile = Join-Path -Path $hpDriversBaseFolder -ChildPath "$modelRelease.cab" # Store in base HP folder
        $driverXmlFile = Join-Path -Path $hpDriversBaseFolder -ChildPath "$modelRelease.xml" # Store in base HP folder

        if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status "Downloading driver index..." }
        WriteLog "Downloading HP Driver cab from $driverCabUrl to $driverCabFile"
        Start-BitsTransferWithRetry -Source $driverCabUrl -Destination $driverCabFile -ErrorAction Stop
        WriteLog "Expanding HP Driver cab $driverCabFile to $driverXmlFile"
        if (Test-Path -Path $driverXmlFile) { Remove-Item -Path $driverXmlFile -Force }
        Invoke-Process -FilePath "expand.exe" -ArgumentList @("`"$driverCabFile`"", "`"$driverXmlFile`"") -ErrorAction Stop | Out-Null

        WriteLog "Parsing driver XML $driverXmlFile"
        [xml]$driverXmlContent = Get-Content -Path $driverXmlFile -Raw -Encoding UTF8 -ErrorAction Stop
        $updates = $driverXmlContent.ImagePal.Solutions.UpdateInfo | Where-Object { $_.Category -match '^Driver' }
        $totalDrivers = ($updates | Measure-Object).Count
        $downloadedCount = 0
        WriteLog "Found $totalDrivers driver updates for $modelName."
        if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status "Found $totalDrivers drivers. Downloading..." }

        if (-not (Test-Path -Path $modelSpecificFolder)) {
            New-Item -Path $modelSpecificFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }

        foreach ($update in $updates) {
            $driverName = $update.Name -replace '[\\/:"*?<>|]', '_' 
            $category = $update.Category -replace '[\\/:"*?<>|]', '_' 
            $version = $update.Version -replace '[\\/:"*?<>|]', '_' 
            $driverUrl = "https://$($update.URL)" 
            $driverFileName = Split-Path -Path $driverUrl -Leaf
            $downloadFolder = Join-Path -Path $modelSpecificFolder -ChildPath $category
            $driverFilePath = Join-Path -Path $downloadFolder -ChildPath $driverFileName
            $extractFolder = Join-Path -Path $downloadFolder -ChildPath ($driverName + "_" + $version + "_" + ($driverFileName -replace '\.exe$', ''))

            $downloadedCount++
            $progressMsg = "($downloadedCount/$totalDrivers) Downloading $driverName..."
            if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $progressMsg }
            WriteLog "$progressMsg URL: $driverUrl"

            if (Test-Path -Path $extractFolder) {
                WriteLog "Driver already extracted to $extractFolder, skipping download."
                continue
            }
            if (-not (Test-Path -Path $downloadFolder)) {
                New-Item -Path $downloadFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }
            WriteLog "Downloading driver to: $driverFilePath"
            Start-BitsTransferWithRetry -Source $driverUrl -Destination $driverFilePath -ErrorAction Stop
            WriteLog "Driver downloaded: $driverFilePath"
            WriteLog "Creating extraction folder: $extractFolder"
            New-Item -Path $extractFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
            $arguments = "/s /e /f `"$extractFolder`"" 
            WriteLog "Extracting driver $driverFilePath with args: $arguments"
            #DEBUG
            # wrap $driverFilePath in quotes to handle spaces
            # $driverFilePath = "`"$driverFilePath`""
            WriteLog "Running HP Driver Extraction Command: $driverFilePath $arguments"
            Invoke-Process -FilePath $driverFilePath -ArgumentList $arguments -ErrorAction Stop | Out-Null
            # Start-Process -FilePath $driverFilePath -ArgumentList $arguments -Wait -NoNewWindow -ErrorAction Stop | Out-Null
            WriteLog "Driver extracted to: $extractFolder"
            Remove-Item -Path $driverFilePath -Force -ErrorAction SilentlyContinue
            WriteLog "Deleted driver installer: $driverFilePath"
        }

        Remove-Item -Path $driverCabFile, $driverXmlFile -Force -ErrorAction SilentlyContinue
        WriteLog "Cleaned up driver cab and xml files for $modelName"
        
        $finalStatus = "Completed" 
        if ($CompressToWim) {
            if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status "Compressing..." }
            $wimFilePath = Join-Path -Path $hpDriversBaseFolder -ChildPath "$($identifier).wim"
            WriteLog "Compressing '$modelSpecificFolder' to '$wimFilePath'..."
            try {
                Compress-DriverFolderToWim -SourceFolderPath $modelSpecificFolder -DestinationWimPath $wimFilePath -WimName $identifier -WimDescription "Drivers for $identifier" -ErrorAction Stop
                WriteLog "Compression successful for '$identifier'."
                $finalStatus = "Completed & Compressed"
            }
            catch {
                WriteLog "Error during compression for '$identifier': $($_.Exception.Message)"
                $finalStatus = "Completed (Compression Failed)"
            }
        }
        $successState = $true
    }
    catch {
        $errorMessage = "Error saving HP drivers for $($modelName): $($_.Exception.Message)"
        WriteLog $errorMessage
        $finalStatus = "Error: $($_.Exception.Message.Split([Environment]::NewLine)[0])"
        $successState = $false
        if (Test-Path -Path $modelSpecificFolder -PathType Container) {
            WriteLog "Attempting to remove partially created folder $modelSpecificFolder due to error."
            Remove-Item -Path $modelSpecificFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
            
    if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $finalStatus }
    return [PSCustomObject]@{ Identifier = $identifier; Status = $finalStatus; Success = $successState }
}
# Function to update status of a specific item in a ListView
function Update-ListViewItemStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$WindowObject, # Changed type to [object]
        [Parameter(Mandatory)]
        [object]$ListView,     # Changed type to [object]
        [Parameter(Mandatory)]
        [string]$IdentifierProperty, 
        [Parameter(Mandatory)]
        [string]$IdentifierValue,
        [Parameter(Mandatory)]
        [string]$StatusProperty,     
        [Parameter(Mandatory)]
        [string]$StatusValue
    )
    
    # Ensure we are in UI mode and objects are of correct WPF types
    if ($WindowObject -is [System.Windows.Window] -and $ListView -is [System.Windows.Controls.ListView]) {
        # Directly update UI elements as this function is now called on the UI thread
        try {
            $itemToUpdate = $ListView.Items | Where-Object { $_.$IdentifierProperty -eq $IdentifierValue } | Select-Object -First 1
            if ($null -ne $itemToUpdate) {
                $itemToUpdate.$StatusProperty = $StatusValue
                $ListView.Items.Refresh() # Refresh the view to show the change
            }
            else {
                # Log if item not found (for debugging)
                WriteLog "Update-ListViewItemStatus: Item with $IdentifierProperty '$IdentifierValue' not found in ListView."
            }
        }
        catch {
            WriteLog "Update-ListViewItemStatus: Error updating ListView: $($_.Exception.Message)"
        }
    } # End of if ($WindowObject -is [System.Windows.Window]...)
    else {
        # Log if called in non-UI mode or with incorrect types (should not happen if Invoke-ParallelProcessing $isUiMode is correct)
        WriteLog "Update-ListViewItemStatus: Skipped UI update for $IdentifierValue due to non-UI mode or incorrect object types."
    }
}

# Function to update overall progress bar and status text label
function Update-OverallProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$WindowObject, # Changed type to [object]
        [Parameter(Mandatory)]
        [int]$CompletedCount,
        [Parameter(Mandatory)]
        [int]$TotalCount,
        [Parameter(Mandatory)]
        [string]$StatusText,
        [Parameter(Mandatory)] 
        [string]$ProgressBarName,
        [Parameter(Mandatory)]
        [string]$StatusLabelName
    )

    # Ensure we are in UI mode and WindowObject is of correct WPF type
    if ($WindowObject -is [System.Windows.Window]) {
        # Directly update UI elements as this function is now called on the UI thread
        try {
            # Find controls by name using the $WindowObject
            $pb = $WindowObject.FindName($ProgressBarName)
            $lbl = $WindowObject.FindName($StatusLabelName)

            if ($null -eq $pb) {
                WriteLog "Update-OverallProgress: ProgressBar '$ProgressBarName' not found."
                return
            }
            if ($null -eq $lbl) {
                WriteLog "Update-OverallProgress: StatusLabel '$StatusLabelName' not found."
                return
            }

            # Update the progress bar
            if ($TotalCount -gt 0) {
                $percentComplete = ($CompletedCount / $TotalCount) * 100
                $pb.Value = $percentComplete
            }
            else {
                $pb.Value = 0 
            }
            
            # Update the status label
            $lbl.Text = $StatusText
            
        }
        catch {
            WriteLog "Update-OverallProgress: Error updating progress: $($_.Exception.Message)"
        }
    } # End of if ($WindowObject -is [System.Windows.Window])
    else {
        # Log if called in non-UI mode or with incorrect types
        WriteLog "Update-OverallProgress: Skipped UI update ($StatusText) due to non-UI mode or incorrect WindowObject type."
    }
}

# Reusable function to invoke parallel processing with UI updates
function Invoke-ParallelProcessing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$ItemsToProcess,
        [Parameter(Mandatory = $false)] 
        [object]$ListViewControl = $null, # Changed type to [object]
        [Parameter(Mandatory = $false)] 
        [string]$IdentifierProperty = 'Identifier', 
        [Parameter(Mandatory = $false)] 
        [string]$StatusProperty = 'Status',         
        [Parameter(Mandatory)]
        [ValidateSet('WingetDownload', 'CopyBYO', 'DownloadDriverByMake')]
        [string]$TaskType,
        [Parameter()]
        [hashtable]$TaskArguments = @{},
        [Parameter(Mandatory = $false)] 
        [string]$CompletedStatusText = "Completed",
        [Parameter(Mandatory = $false)] 
        [string]$ErrorStatusPrefix = "Error: ",
        [Parameter(Mandatory = $false)] 
        [object]$WindowObject = $null, # Changed type to [object]
        [Parameter(Mandatory = $false)]
        [string]$MainThreadLogPath = $null # New parameter for the log path
    )
    # Check if running in UI mode by verifying the types of the passed objects
    $isUiMode = ($null -ne $WindowObject -and $WindowObject -is [System.Windows.Window] -and $null -ne $ListViewControl -and $ListViewControl -is [System.Windows.Controls.ListView])

    if ($isUiMode) {
        WriteLog "Invoke-ParallelProcessing started for $($ItemsToProcess.Count) items in ListView '$($ListViewControl.Name)'."
    }
    else {
        WriteLog "Invoke-ParallelProcessing started for $($ItemsToProcess.Count) items (non-UI mode)."
    }
    $resultsCollection = [System.Collections.Generic.List[object]]::new()
    $jobs = @()
    $results = @() # Store results from jobs
    $totalItems = $ItemsToProcess.Count
    $processedCount = 0

    # Create a thread-safe queue for intermediate progress updates
    $progressQueue = New-Object System.Collections.Concurrent.ConcurrentQueue[hashtable]

    # Define common paths locally within this function's scope
    $coreModulePath = $MyInvocation.MyCommand.Module.Path 
    $coreModuleDirectory = Split-Path -Path $coreModulePath -Parent
    $ffuDevelopmentRoot = Split-Path -Path $coreModuleDirectory -Parent 
    
    # Paths to other modules needed by the parallel threads
    $commonCoreModulePathForJob = Join-Path -Path $ffuDevelopmentRoot -ChildPath "common\FFU.Common.Core.psm1"
    $commonWingetModulePathForJob = Join-Path -Path $ffuDevelopmentRoot -ChildPath "common\FFU.Common.Winget.psm1"
    $commonDriversModulePathForJob = Join-Path -Path $ffuDevelopmentRoot -ChildPath "common\FFU.Common.Drivers.psm1"
    
    # Use the explicitly passed MainThreadLogPath for the parallel jobs.
    # If not provided (e.g., older calls or direct module use without this param), it might be null.
    # The parallel job's Set-CommonCoreLogPath will handle null/empty paths by warning.
    $currentLogFilePathForJob = $MainThreadLogPath

    $jobScopeVariables = $TaskArguments.Clone() 
    $jobScopeVariables['_thisCoreModulePath'] = $coreModulePath # Path to FFUUI.Core.psm1 itself
    $jobScopeVariables['_commonCoreModulePath'] = $commonCoreModulePathForJob
    $jobScopeVariables['_commonWingetModulePath'] = $commonWingetModulePathForJob
    $jobScopeVariables['_commonDriversModulePath'] = $commonDriversModulePathForJob
    $jobScopeVariables['_currentLogFilePathForJob'] = $currentLogFilePathForJob # Pass the determined log path
    $jobScopeVariables['_progressQueue'] = $progressQueue

    # The $TaskScriptBlock parameter is already a local variable in this scope

    # Initial UI update needs to happen *before* starting the jobs
    # Update all items to a static "Processing..." status
    if ($isUiMode) {
        # Use the new $isUiMode flag
        foreach ($item in $ItemsToProcess) {
            $identifierValue = $item.$IdentifierProperty
            $initialStaticStatus = "Queued..." 
            try {
                # Update the UI on the main thread to show the item is being queued for processing
                $WindowObject.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Background, [Action] { 
                        Update-ListViewItemStatus -WindowObject $WindowObject -ListView $ListViewControl -IdentifierProperty $IdentifierProperty -IdentifierValue $identifierValue -StatusProperty $StatusProperty -StatusValue $initialStaticStatus 
                    })
            }
            catch {
                WriteLog "Error setting initial status for item '$identifierValue': $($_.Exception.Message)"
            }
        }
    }

    # Queue items and start jobs using the pipeline and $using:
    try {
        # $jobScopeVariables and $TaskType are local here
        # Inside the -Parallel scriptblock, we access them with $using:
        $jobs = $ItemsToProcess | ForEach-Object -Parallel {
            # Access the current item via pipeline variable $_
            $currentItem = $_
            # Access the combined arguments hashtable from the calling scope using $using:
            $localJobArgs = $using:jobScopeVariables
            # Access the task type string from the calling scope using $using:
            $localTaskType = $using:TaskType
            # Access the progress queue using $using:
            $localProgressQueue = $localJobArgs['_progressQueue']

            # Initialize result hashtable
            $taskResult = $null
            $resultIdentifier = $null
            $resultStatus = "Error: Task type '$localTaskType' not recognized"
            $resultCode = 1 # Default to error

            try {
                # Import the common core module first
                Import-Module $localJobArgs['_commonCoreModulePath']
                # Set the log path for this parallel thread
                Set-CommonCoreLogPath -Path $localJobArgs['_currentLogFilePathForJob']

                # Set other global variables if tasks rely on them (prefer passing as parameters)
                $global:AppsPath = $localJobArgs['AppsPath']
                $global:WindowsArch = $localJobArgs['WindowsArch']
                if ($localJobArgs.ContainsKey('OrchestrationPath')) {
                    $global:OrchestrationPath = $localJobArgs['OrchestrationPath']
                }

                # Import other necessary modules. Their WriteLog calls will use the path set above.
                Import-Module $localJobArgs['_thisCoreModulePath'] # FFUUI.Core.psm1
                Import-Module $localJobArgs['_commonWingetModulePath']
                Import-Module $localJobArgs['_commonDriversModulePath']

                # Execute the appropriate background task based on $localTaskType
                switch ($localTaskType) {
                    'WingetDownload' {
                        # Pass the progress queue to the task function
                        $taskResult = Start-WingetAppDownloadTask -ApplicationItemData $currentItem `
                            -AppListJsonPath $localJobArgs['AppListJsonPath'] `
                            -AppsPath $localJobArgs['AppsPath'] `
                            -WindowsArch $localJobArgs['WindowsArch'] `
                            -OrchestrationPath $localJobArgs['OrchestrationPath'] `
                            -ProgressQueue $localProgressQueue
                        if ($null -ne $taskResult) {
                            $resultIdentifier = $taskResult.Id
                            $resultStatus = $taskResult.Status
                            $resultCode = $taskResult.ResultCode
                        }
                        else {
                            $resultIdentifier = $currentItem.Id # Fallback
                            $resultStatus = "Error: WingetDownload task returned null"
                            $resultCode = 1
                            WriteLog $resultStatus
                        }
                    }
                    'CopyBYO' {
                        # Pass the progress queue to the task function
                        $taskResult = Start-CopyBYOApplicationTask -ApplicationItemData $currentItem `
                            -AppsPath $localJobArgs['AppsPath'] `
                            -ProgressQueue $localProgressQueue 
                        if ($null -ne $taskResult) {
                            $resultIdentifier = $taskResult.Name
                            $resultStatus = $taskResult.Status
                            $resultCode = if ($taskResult.Success) { 0 } else { 1 }
                        }
                        else {
                            $resultIdentifier = $currentItem.Name # Fallback
                            $resultStatus = "Error: CopyBYO task returned null"
                            $resultCode = 1
                            WriteLog $resultStatus
                        }
                    }
                    'DownloadDriverByMake' {
                        $make = $currentItem.Make
                        # Ensure $resultIdentifier is set before the switch, using the main IdentifierProperty
                        # This is crucial if a Make is unsupported or a task fails to return a result.
                        $resultIdentifier = $currentItem.$($using:IdentifierProperty)

                        switch ($make) {
                            'Microsoft' {
                                $taskResult = Save-MicrosoftDriversTask -DriverItemData $currentItem `
                                    -DriversFolder $localJobArgs['DriversFolder'] `
                                    -WindowsRelease $localJobArgs['WindowsRelease'] `
                                    -Headers $localJobArgs['Headers'] `
                                    -UserAgent $localJobArgs['UserAgent'] `
                                    -ProgressQueue $localProgressQueue `
                                    -CompressToWim $localJobArgs['CompressToWim']
                            }
                            'Dell' {
                                # DellCatalogXmlPath might be null if catalog prep failed; Save-DellDriversTask should handle this.
                                $taskResult = Save-DellDriversTask -DriverItemData $currentItem `
                                    -DriversFolder $localJobArgs['DriversFolder'] `
                                    -WindowsArch $localJobArgs['WindowsArch'] `
                                    -WindowsRelease $localJobArgs['WindowsRelease'] `
                                    -DellCatalogXmlPath $localJobArgs['DellCatalogXmlPath'] `
                                    -ProgressQueue $localProgressQueue `
                                    -CompressToWim $localJobArgs['CompressToWim']
                            }
                            'HP' {
                                $taskResult = Save-HPDriversTask -DriverItemData $currentItem `
                                    -DriversFolder $localJobArgs['DriversFolder'] `
                                    -WindowsArch $localJobArgs['WindowsArch'] `
                                    -WindowsRelease $localJobArgs['WindowsRelease'] `
                                    -WindowsVersion $localJobArgs['WindowsVersion'] `
                                    -ProgressQueue $localProgressQueue `
                                    -CompressToWim $localJobArgs['CompressToWim']
                            }
                            'Lenovo' {
                                $taskResult = Save-LenovoDriversTask -DriverItemData $currentItem `
                                    -DriversFolder $localJobArgs['DriversFolder'] `
                                    -WindowsRelease $localJobArgs['WindowsRelease'] `
                                    -Headers $localJobArgs['Headers'] `
                                    -UserAgent $localJobArgs['UserAgent'] `
                                    -ProgressQueue $localProgressQueue `
                                    -CompressToWim $localJobArgs['CompressToWim']
                            }
                            default {
                                $unsupportedMakeMessage = "Error: Unsupported Make '$make' for driver download."
                                WriteLog $unsupportedMakeMessage
                                $resultStatus = $unsupportedMakeMessage
                                $resultCode = 1
                                # $resultIdentifier is already set from $currentItem.$($using:IdentifierProperty)
                                $localProgressQueue.Enqueue(@{ Identifier = $resultIdentifier; Status = $resultStatus })
                                # $taskResult remains null, handled below
                            }
                        }

                        # Consolidate result handling for 'DownloadDriverByMake'
                        if ($null -ne $taskResult) {
                            # $resultIdentifier is already $currentItem.$($using:IdentifierProperty)
                            # We use the task's returned Model/Identifier for logging/status if needed,
                            # but the primary identifier for UI updates should be consistent.
                            $taskSpecificIdentifier = $null
                            if ($taskResult.PSObject.Properties.Name -contains 'Model') { $taskSpecificIdentifier = $taskResult.Model }
                            elseif ($taskResult.PSObject.Properties.Name -contains 'Identifier') { $taskSpecificIdentifier = $taskResult.Identifier }

                            $resultStatus = $taskResult.Status
                            if ($taskResult.PSObject.Properties.Name -contains 'Success') {
                                # Dell, Microsoft, Lenovo
                                $resultCode = if ($taskResult.Success) { 0 } else { 1 }
                            }
                            elseif ($taskResult.Status -like 'Completed*') {
                                # HP success
                                $resultCode = 0
                            }
                            elseif ($taskResult.Status -like 'Error*') {
                                # HP error
                                $resultCode = 1
                            }
                            else {
                                # Default for HP if status is unexpected, or if 'Success' property is missing but status isn't 'Completed*' or 'Error*'
                                WriteLog "Unexpected status or missing 'Success' property from task for '$taskSpecificIdentifier': $($taskResult.Status)"
                                $resultCode = 1 # Assume error
                            }
                        }
                        elseif ($make -in ('Microsoft', 'Dell', 'HP', 'Lenovo')) {
                            # This means a specific Make case was hit, but $taskResult was unexpectedly null
                            $nullTaskResultMessage = "Error: Task for Make '$make' returned null."
                            WriteLog $nullTaskResultMessage
                            $resultStatus = $nullTaskResultMessage
                            $resultCode = 1
                            # $resultIdentifier is already set
                        }
                        # If it was an unsupported Make, $resultStatus and $resultCode are already set from the 'default' case.
                    }
                    Default {
                        # This handles unknown $localTaskType values
                        $resultStatus = "Error: Task type '$localTaskType' not recognized"
                        $resultCode = 1
                        if ($currentItem -is [pscustomobject] -and $currentItem.PSObject.Properties.Name -match $using:IdentifierProperty) {
                            $resultIdentifier = $currentItem.$($using:IdentifierProperty)
                        }
                        else {
                            $resultIdentifier = "UnknownItem"
                        }
                        WriteLog "Error in parallel job: Unknown TaskType '$localTaskType' provided for item '$resultIdentifier'."
                    }
                }
            }
            catch {
                # Catch errors within the parallel task execution
                $resultStatus = "Error: $($_.Exception.Message)"
                $resultCode = 1
                # Try to get an identifier
                if ($currentItem -is [pscustomobject] -and $currentItem.PSObject.Properties.Name -match $using:IdentifierProperty) {
                    $resultIdentifier = $currentItem.$($using:IdentifierProperty)
                }
                else {
                    $resultIdentifier = "UnknownItemOnError"
                }
                WriteLog "Exception during parallel task '$localTaskType' for item '$resultIdentifier': $($_.Exception.ToString())"
                # Enqueue the error status from the catch block
                $localProgressQueue.Enqueue(@{ Identifier = $resultIdentifier; Status = $resultStatus })
            }

            # Return a consistent hashtable structure (final result)
            return @{
                Identifier = $resultIdentifier
                Status     = $resultStatus # Return the final status
                ResultCode = $resultCode
            }

        } -ThrottleLimit 5 -AsJob
    }
    catch {
        # Catch errors during the *creation* of the parallel jobs (e.g., module loading in main thread failed)
        WriteLog "Error initiating ForEach-Object -Parallel: $($_.Exception.Message)"
        # Update all items to show a general startup error
        $errorStatus = "$ErrorStatusPrefix Failed to start processing"
        foreach ($item in $ItemsToProcess) {
            $identifier = $item.$IdentifierProperty
            $WindowObject.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Background, [Action] { # Use $WindowObject
                    Update-ListViewItemStatus -WindowObject $WindowObject -ListView $ListViewControl -IdentifierProperty $IdentifierProperty -IdentifierValue $identifier -StatusProperty $StatusProperty -StatusValue $errorStatus # Pass $WindowObject
                })
        }
        # Exit the function as processing cannot proceed
        return
    }

    # Check if any jobs failed to start immediately (e.g., module loading issues within the job)
    $failedJobs = $jobs | Where-Object { $_.State -eq 'Failed' -and $_.JobStateInfo.Reason }
    foreach ($failedJob in $failedJobs) {
        WriteLog "Job $($failedJob.Id) failed to start or failed early: $($failedJob.JobStateInfo.Reason)"
        # We don't easily know which item failed here without more complex mapping
        # Update overall status maybe?
        $processedCount++
    }
    # Filter out jobs that failed immediately
    $jobs = $jobs | Where-Object { $_.State -ne 'Failed' }

    # Process job results and intermediate status updates without blocking the UI thread
    while ($jobs.Count -gt 0 -or -not $progressQueue.IsEmpty) {
        # Continue while jobs are running OR queue has messages

        # 1. Process intermediate status updates from the queue
        $statusUpdate = $null 
        while ($progressQueue.TryDequeue([ref]$statusUpdate)) {
            if ($null -ne $statusUpdate) {
                $intermediateIdentifier = $statusUpdate.Identifier
                $intermediateStatus = $statusUpdate.Status
                if ($isUiMode) {
                    # Use the new $isUiMode flag
                    # Update the UI with the intermediate status
                    try {
                        $WindowObject.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Background, [Action] { 
                                Update-ListViewItemStatus -WindowObject $WindowObject -ListView $ListViewControl -IdentifierProperty $IdentifierProperty -IdentifierValue $intermediateIdentifier -StatusProperty $StatusProperty -StatusValue $intermediateStatus 
                            })
                    }
                    catch {
                        WriteLog "Error setting intermediate status for item '$intermediateIdentifier': $($_.Exception.Message)"
                    }
                }
                else {
                    # Log intermediate status if not in UI mode
                    WriteLog "Intermediate Status for '$intermediateIdentifier': $intermediateStatus"
                }
            }
        }

        # 2. Check for completed jobs
        $completedJobs = $jobs | Where-Object { $_.State -in 'Completed', 'Failed', 'Stopped' }

        if ($completedJobs) {
            foreach ($completedJob in $completedJobs) {
                $finalIdentifier = "UnknownJob" # Placeholder if we can't get result
                $finalStatus = "$ErrorStatusPrefix Job $($completedJob.Id) ended unexpectedly"
                $finalResultCode = 1 # Assume error

                if ($completedJob.State -eq 'Failed') {
                    WriteLog "Job $($completedJob.Id) failed: $($completedJob.Error)"
                    # Try to get identifier from job name if possible (less reliable)
                    # $finalIdentifier = ... logic to parse job name or map ID ...
                    $finalStatus = "$ErrorStatusPrefix Job Failed"
                    $processedCount++ # Count failed job as processed
                }
                elseif ($completedJob.HasMoreData) {
                    # Receive final results specifically from the completed job
                    $jobResults = $completedJob | Receive-Job
                    foreach ($result in $jobResults) {
                        # Should only be one result per job in this setup
                        if ($null -ne $result -and $result -is [hashtable] -and $result.ContainsKey('Identifier')) {
                            $finalIdentifier = $result.Identifier
                            $status = $result.Status # This is the FINAL status returned by the task
                            $finalResultCode = $result.ResultCode
    
                            # Determine final status text based on the result code
                            if ($finalResultCode -eq 0) {
                                # Assuming 0 means success
                                # Use the specific status returned by the successful job
                                # This handles cases like "Already downloaded" correctly
                                $finalStatus = $status
                            }
                            else {
                                $finalStatus = "$($ErrorStatusPrefix)$($status)" # Use status from result for error message
                            }
                            $processedCount++
                        }
                        else {
                            WriteLog "Warning: Received unexpected final job result format: $($result | Out-String)"
                            $finalStatus = "$ErrorStatusPrefix Invalid Result Format"
                            $processedCount++ # Count as processed to avoid loop issues
                        }
                        # Add the received result (even if format was unexpected, for logging)
                        if ($null -ne $result) { $resultsCollection.Add($result) }
                        break # Only process first result from this job
                    }
                }
                else {
                    # Job completed but had no data
                    if ($completedJob.State -ne 'Failed') {
                        WriteLog "Job $($completedJob.Id) completed with state '$($completedJob.State)' but had no data."
                        # $finalIdentifier = ... logic to parse job name or map ID ...
                        $finalStatus = "$ErrorStatusPrefix No Result Data"
                        $processedCount++
                    }
                    # If it was 'Failed', it was handled above
                }

                # Update the specific item in the ListView with its FINAL status
                if ($isUiMode) {
                    # Use the new $isUiMode flag
                    try {
                        $WindowObject.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Background, [Action] { 
                                Update-ListViewItemStatus -WindowObject $WindowObject -ListView $ListViewControl -IdentifierProperty $IdentifierProperty -IdentifierValue $finalIdentifier -StatusProperty $StatusProperty -StatusValue $finalStatus 
                            })
                    }
                    catch {
                        WriteLog "Error setting FINAL status for item '$finalIdentifier': $($_.Exception.Message)"
                    }

                    # Update overall progress after processing a job's results
                    $WindowObject.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Background, [Action] { 
                            Update-OverallProgress -WindowObject $WindowObject -CompletedCount $processedCount -TotalCount $totalItems -StatusText "Processed $processedCount of $totalItems..." -ProgressBarName "progressBar" -StatusLabelName "txtStatus" 
                        })
                }
                else {
                    # Log final status if not in UI mode
                    WriteLog "Final Status for '$finalIdentifier': $finalStatus (ResultCode: $finalResultCode)"
                }

                # Remove the completed/failed job from the list and clean it up
                $jobs = $jobs | Where-Object { $_.Id -ne $completedJob.Id }
                Remove-Job -Job $completedJob -Force -ErrorAction SilentlyContinue
            } # End foreach completedJob
        } # End if ($completedJobs)

        # 3. Allow UI events to process and sleep briefly
        if ($isUiMode) {
            # Use the new $isUiMode flag
            # Only sleep if jobs are still running AND the queue is empty (to avoid delaying UI updates)
            if ($jobs.Count -gt 0 -and $progressQueue.IsEmpty) {
                $WindowObject.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Background, [action] { }) | Out-Null 
                Start-Sleep -Milliseconds 100
            }
            elseif (-not $progressQueue.IsEmpty) {
                # If queue has messages, process them immediately without sleeping
                $WindowObject.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Background, [action] { }) | Out-Null 
            }
        }
        else {
            # Non-UI mode, just sleep if jobs are running
            if ($jobs.Count -gt 0) {
                Start-Sleep -Milliseconds 100
            }
        }
        # If jobs are done AND queue is empty, the loop condition will terminate

    } # End while ($jobs.Count -gt 0 -or -not $progressQueue.IsEmpty)

    # Final cleanup of any remaining jobs (shouldn't be necessary with this loop logic, but good practice)
    if ($jobs.Count -gt 0) {
        WriteLog "Cleaning up $($jobs.Count) remaining jobs after loop exit."
        Remove-Job -Job $jobs -Force -ErrorAction SilentlyContinue
    }

    if ($isUiMode) {
        # Use the new $isUiMode flag
        WriteLog "Invoke-ParallelProcessing finished for ListView '$($ListViewControl.Name)'."
        # Final overall progress update
        $WindowObject.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Background, [Action] { 
                Update-OverallProgress -WindowObject $WindowObject -CompletedCount $processedCount -TotalCount $totalItems -StatusText "Processing complete. Processed $processedCount of $totalItems." -ProgressBarName "progressBar" -StatusLabelName "txtStatus" 
            })
    }
    else {
        WriteLog "Invoke-ParallelProcessing finished (non-UI mode). Processed $processedCount of $totalItems."
    }
        
    # Return all collected final results from jobs
    return $resultsCollection
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
Export-ModuleMember -Function Get-UIConfig,
Get-VMSwitchData,
Get-WindowsSettingsDefaults,
Get-AvailableWindowsReleases,
Get-AvailableWindowsVersions,
Get-GeneralDefaults,
Get-DellDriversModelList,
Get-HPDriversModelList,
Get-MicrosoftDriversModelList,
Get-LenovoDriversModelList,
Get-USBDrives,
Show-ModernFolderPicker,
Test-WingetCLI,
Install-WingetComponents,
Confirm-WingetInstallationUI,
Search-WingetPackagesPublic,
Start-WingetAppDownloadTask,
Start-CopyBYOApplicationTask,
Save-MicrosoftDriversTask,
Save-DellDriversTask,
Save-HPDriversTask,
Save-LenovoDriversTask,
Invoke-ProgressUpdate,
Invoke-ParallelProcessing,
Update-ListViewItemStatus,
Update-OverallProgress,
Compress-DriverFolderToWim,
Get-AvailableSkusForRelease,
Initialize-UIControls
