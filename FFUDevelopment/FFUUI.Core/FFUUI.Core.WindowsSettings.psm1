# FFU UI Core Windows Settings Logic Module
# Contains UI helper functions, data retrieval, and core processing logic for the Windows Settings tab.

# --------------------------------------------------------------------------
# SECTION: Module Variables (Static Data)
# --------------------------------------------------------------------------

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
    'ar-sa',
    'bg-bg',
    'cs-cz',
    'da-dk',
    'de-de',
    'el-gr',
    'en-gb',
    'en-us',
    'es-es',
    'es-mx',
    'et-ee',
    'fi-fi',
    'fr-ca',
    'fr-fr',
    'he-il',
    'hr-hr',
    'hu-hu',
    'it-it',
    'ja-jp',
    'ko-kr',
    'lt-lt',
    'lv-lv',
    'nb-no',
    'nl-nl',
    'pl-pl',
    'pt-br',
    'pt-pt',
    'ro-ro',
    'ru-ru',
    'sk-sk',
    'sl-si',
    'sr-latn-rs',
    'sv-se',
    'th-th',
    'tr-tr',
    'uk-ua',
    'zh-cn',
    'zh-tw'
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
# SECTION: Functions
# --------------------------------------------------------------------------

# Function to return the default settings and static lists
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
        # Static Data Lists/Maps
        SkuList                 = $script:skuList
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

# Function to get the appropriate list of Windows Releases based on ISO path
function Get-AvailableWindowsReleases {
    [CmdletBinding()]
    param(
        [string]$IsoPath,
        [Parameter(Mandatory = $true)]
        [psobject]$State
    )

    if ([string]::IsNullOrEmpty($IsoPath)) {
        return $State.Defaults.WindowsSettingsDefaults.MctWindowsReleases
    }
    else {
        return $State.Defaults.WindowsSettingsDefaults.AllWindowsReleases
    }
}

# Function to get available Windows Versions for a given release and ISO path
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

    if (-not $State.Defaults.WindowsSettingsDefaults.WindowsVersionMap.ContainsKey($SelectedRelease)) {
        return $result 
    }

    $validVersions = $State.Defaults.WindowsSettingsDefaults.WindowsVersionMap[$SelectedRelease]

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
        return $State.Defaults.WindowsSettingsDefaults.Ltsc2016SKUs
    }
    # Handle LTSC 2019 specifically
    # Ensure "Server" is not in the display name to avoid matching "Windows Server 2019"
    elseif ($SelectedReleaseValue -eq 2019 -and $SelectedReleaseDisplayName -like '*LTSC*' -and $SelectedReleaseDisplayName -notlike '*Server*') {
        WriteLog "Get-AvailableSkusForRelease: Matched LTSC 2019. Returning generic LTSC SKUs (including IoT)."
        # Assuming LTSC 2019 uses the generic LTSC SKUs + IoT LTSC SKUs
        return ($State.Defaults.WindowsSettingsDefaults.LtscGenericSKUs + $State.Defaults.WindowsSettingsDefaults.IotLtscSKUs | Select-Object -Unique)
    }
    # For all other cases, use the main SKU map
    elseif ($State.Defaults.WindowsSettingsDefaults.WindowsReleaseSkuMap.ContainsKey($SelectedReleaseValue)) {
        $availableSkus = $State.Defaults.WindowsSettingsDefaults.WindowsReleaseSkuMap[$SelectedReleaseValue]
        WriteLog "Get-AvailableSkusForRelease: Found $($availableSkus.Count) SKUs for Release '$SelectedReleaseValue' using standard map."
        return $availableSkus
    }
    else {
        WriteLog "Get-AvailableSkusForRelease: Warning - Release Value '$SelectedReleaseValue' not found in SKU map. Returning default client SKUs."
        # Fallback to a default list (e.g., client SKUs) or an empty list
        return $State.Defaults.WindowsSettingsDefaults.ClientSKUs
    }
}

# Function to refresh the Windows Release ComboBox based on ISO path
function Update-WindowsReleaseCombo {
    param(
        [string]$isoPath,
        [Parameter(Mandatory = $true)]
        [psobject]$State
    )

    if (-not $State.Controls.cmbWindowsRelease) { return }

    $oldSelectedItemValue = $null
    if ($null -ne $State.Controls.cmbWindowsRelease.SelectedItem) {
        $oldSelectedItemValue = $State.Controls.cmbWindowsRelease.SelectedItem.Value
    }

    # Get the appropriate list of releases from the helper module
    $availableReleases = Get-AvailableWindowsReleases -IsoPath $isoPath -State $State

    # Update the ComboBox ItemsSource
    $State.Controls.cmbWindowsRelease.ItemsSource = $availableReleases
    $State.Controls.cmbWindowsRelease.DisplayMemberPath = 'Display'
    $State.Controls.cmbWindowsRelease.SelectedValuePath = 'Value'

    # Try to re-select the previously selected item, or default
    $itemToSelect = $availableReleases | Where-Object { $_.Value -eq $oldSelectedItemValue } | Select-Object -First 1
    if ($null -ne $itemToSelect) {
        $State.Controls.cmbWindowsRelease.SelectedItem = $itemToSelect
    }
    elseif ($availableReleases.Count -gt 0) {
        # Default to Windows 11 if available, otherwise the first item
        $defaultItem = $availableReleases | Where-Object { $_.Value -eq 11 } | Select-Object -First 1
        if ($null -eq $defaultItem) {
            $defaultItem = $availableReleases[0]
        }
        $State.Controls.cmbWindowsRelease.SelectedItem = $defaultItem
    }
    else {
        # No items available (should not happen with current logic)
        $State.Controls.cmbWindowsRelease.SelectedIndex = -1
    }
}

# Function to refresh the Windows Version ComboBox based on selected release and ISO path
function Update-WindowsVersionCombo {
    param(
        [int]$selectedRelease,
        [string]$isoPath,
        [Parameter(Mandatory = $true)]
        [psobject]$State
    )

    $combo = $State.Controls.cmbWindowsVersion 
    if (-not $combo) { return } 

    # Get available versions and default from the helper module
    $versionData = Get-AvailableWindowsVersions -SelectedRelease $selectedRelease -IsoPath $isoPath -State $State

    # Update the ComboBox ItemsSource and IsEnabled state
    $combo.ItemsSource = $versionData.Versions
    $combo.IsEnabled = $versionData.IsEnabled

    # Set the selected item
    if ($null -ne $versionData.DefaultVersion -and $versionData.Versions -contains $versionData.DefaultVersion) {
        $combo.SelectedItem = $versionData.DefaultVersion
    }
    elseif ($versionData.Versions.Count -gt 0) {
        $combo.SelectedIndex = 0 
    }
    else {
        $combo.SelectedIndex = -1 # No items available
    }
}

# Function to refresh the Windows SKU ComboBox based on selected release
function Update-WindowsSkuCombo {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$State
    )

    $skuCombo = $State.Controls.cmbWindowsSKU
    if (-not $skuCombo) {
        WriteLog "Update-WindowsSkuCombo: SKU ComboBox not found."
        return
    }

    $releaseCombo = $State.Controls.cmbWindowsRelease
    if (-not $releaseCombo -or $null -eq $releaseCombo.SelectedItem) {
        WriteLog "Update-WindowsSkuCombo: Windows Release ComboBox not found or no item selected. Cannot update SKUs."
        $skuCombo.ItemsSource = @() # Clear SKUs
        $skuCombo.SelectedIndex = -1
        return
    }

    $selectedReleaseItem = $releaseCombo.SelectedItem
    $selectedReleaseValue = $selectedReleaseItem.Value
    $selectedReleaseDisplayName = $selectedReleaseItem.Display

    $previousSelectedSku = $null
    if ($null -ne $skuCombo.SelectedItem) {
        $previousSelectedSku = $skuCombo.SelectedItem
    }

    WriteLog "Update-WindowsSkuCombo: Updating SKUs for Release Value '$selectedReleaseValue' (Display: '$selectedReleaseDisplayName')."
    # Call Get-AvailableSkusForRelease with both Value and DisplayName
    $availableSkus = Get-AvailableSkusForRelease -SelectedReleaseValue $selectedReleaseValue -SelectedReleaseDisplayName $selectedReleaseDisplayName -State $State

    $skuCombo.ItemsSource = $availableSkus
    WriteLog "Update-WindowsSkuCombo: Set ItemsSource with $($availableSkus.Count) SKUs."

    # Attempt to re-select the previous SKU, or "Pro", or the first available
    if ($null -ne $previousSelectedSku -and $availableSkus -contains $previousSelectedSku) {
        $skuCombo.SelectedItem = $previousSelectedSku
        WriteLog "Update-WindowsSkuCombo: Re-selected previous SKU '$previousSelectedSku'."
    }
    elseif ($availableSkus -contains "Pro") {
        $skuCombo.SelectedItem = "Pro"
        WriteLog "Update-WindowsSkuCombo: Selected default SKU 'Pro'."
    }
    elseif ($availableSkus.Count -gt 0) {
        $skuCombo.SelectedIndex = 0
        WriteLog "Update-WindowsSkuCombo: Selected first available SKU '$($skuCombo.SelectedItem)'."
    }
    else {
        $skuCombo.SelectedIndex = -1 # No SKUs available
        WriteLog "Update-WindowsSkuCombo: No SKUs available for Release '$selectedReleaseValue' (Display: '$selectedReleaseDisplayName')."
    }
}

# Combined function to refresh both Release and Version combos
function Refresh-WindowsSettingsCombos {
    param(
        [string]$isoPath,
        [Parameter(Mandatory = $true)]
        [psobject]$State
    )

    # Update Release combo first
    Update-WindowsReleaseCombo -isoPath $isoPath -State $State

    # Get the newly selected release value
    $selectedReleaseValue = 11 # Default to 11 if selection is null
    if ($null -ne $State.Controls.cmbWindowsRelease.SelectedItem) {
        $selectedReleaseValue = $State.Controls.cmbWindowsRelease.SelectedItem.Value
    }

    # Update Version combo based on the selected release
    Update-WindowsVersionCombo -selectedRelease $selectedReleaseValue -isoPath $isoPath -State $State

    # Update SKU combo based on the selected release (now derives values internally)
    Update-WindowsSkuCombo -State $State
}

# Dynamic checkboxes for optional features in Windows Settings tab
function UpdateOptionalFeaturesString {
    param(
        [psobject]$State
    )
    $checkedFeatures = @()
    foreach ($entry in $State.Controls.featureCheckBoxes.GetEnumerator()) {
        if ($entry.Value.IsChecked) { $checkedFeatures += $entry.Key }
    }
    $State.Controls.txtOptionalFeatures.Text = $checkedFeatures -join ";"
}
function BuildFeaturesGrid {
    param (
        [Parameter(Mandatory)]
        [System.Windows.FrameworkElement]$parent,
        [Parameter(Mandatory)]
        [array]$allowedFeatures, # Pass the list of features explicitly
        [Parameter(Mandatory = $true)]
        [psobject]$State
    )
    $parent.Children.Clear()
    $State.Controls.featureCheckBoxes.Clear() # Clear the tracking hashtable

    $sortedFeatures = $allowedFeatures | Sort-Object
    $rows = 10 # Define number of rows for layout
    $columns = [math]::Ceiling($sortedFeatures.Count / $rows)

    $featuresGrid = New-Object System.Windows.Controls.Grid
    $featuresGrid.Margin = "0,5,0,5"
    $featuresGrid.ShowGridLines = $false

    # Define grid rows
    for ($r = 0; $r -lt $rows; $r++) {
        $rowDef = New-Object System.Windows.Controls.RowDefinition
        $rowDef.Height = [System.Windows.GridLength]::Auto
        $featuresGrid.RowDefinitions.Add($rowDef) | Out-Null
    }
    # Define grid columns
    for ($c = 0; $c -lt $columns; $c++) {
        $colDef = New-Object System.Windows.Controls.ColumnDefinition
        $colDef.Width = [System.Windows.GridLength]::Auto
        $featuresGrid.ColumnDefinitions.Add($colDef) | Out-Null
    }

    # Populate grid with checkboxes
    for ($i = 0; $i -lt $sortedFeatures.Count; $i++) {
        $featureName = $sortedFeatures[$i]
        $colIndex = [int]([math]::Floor($i / $rows))
        $rowIndex = $i % $rows

        $chk = New-Object System.Windows.Controls.CheckBox
        $chk.Content = $featureName
        $chk.Margin = "5"
        $chk.Add_Checked({
            param($sender, $e)
            $window = [System.Windows.Window]::GetWindow($sender)
            if ($null -ne $window) {
                UpdateOptionalFeaturesString -State $window.Tag
            }
        })
        $chk.Add_Unchecked({
            param($sender, $e)
            $window = [System.Windows.Window]::GetWindow($sender)
            if ($null -ne $window) {
                UpdateOptionalFeaturesString -State $window.Tag
            }
        })

        $State.Controls.featureCheckBoxes[$featureName] = $chk # Track the checkbox

        [System.Windows.Controls.Grid]::SetRow($chk, $rowIndex)
        [System.Windows.Controls.Grid]::SetColumn($chk, $colIndex)
        $featuresGrid.Children.Add($chk) | Out-Null
    }
    $parent.Children.Add($featuresGrid) | Out-Null
}

# --------------------------------------------------------------------------
# SECTION: Module Export
# --------------------------------------------------------------------------

Export-ModuleMember -Function Get-WindowsSettingsDefaults, Get-AvailableWindowsReleases, Get-AvailableWindowsVersions, Get-AvailableSkusForRelease, Update-WindowsReleaseCombo, Update-WindowsVersionCombo, Update-WindowsSkuCombo, Refresh-WindowsSettingsCombos, UpdateOptionalFeaturesString, BuildFeaturesGrid