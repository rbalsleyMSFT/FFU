<#
.SYNOPSIS
    FFU Builder Windows Update and Servicing Module

.DESCRIPTION
    Windows Update catalog parsing, MSU package download, and DISM servicing
    operations for FFU Builder. Includes disk space validation, automatic retry
    logic, and unattend.xml extraction from MSU packages.

.NOTES
    Module: FFU.Updates
    Version: 1.0.0
    Dependencies: FFU.Core

.IMPROVEMENTS
    - Test-MountedImageDiskSpace: Pre-flight disk space validation (3x package size + 5GB)
    - Initialize-DISMService: Ensures DISM service is ready before package operations
    - Add-WindowsPackageWithRetry: Automatic retry with 30-second delays (up to 2 retries)
    - Add-WindowsPackageWithUnattend: Robust unattend.xml extraction from MSU packages
#>

#Requires -Version 7.0

# Import constants module
using module ..\FFU.Constants\FFU.Constants.psm1

function Get-ProductsCab {
    <#
    .SYNOPSIS
    Downloads Windows 11 products.cab file from Microsoft Update service

    .DESCRIPTION
    Retrieves the products.cab file for a specific Windows 11 build and architecture
    from Microsoft Update servers. Validates download integrity using size and SHA-256
    hash verification. Used for discovering available Windows updates.

    .PARAMETER OutFile
    Full path where products.cab will be saved

    .PARAMETER Architecture
    Target architecture (x64 or arm64)

    .PARAMETER BuildVersion
    Windows build version (e.g., "10.0.22621" for Windows 11 22H2)

    .PARAMETER UserAgent
    User agent string for web requests to Microsoft Update service

    .EXAMPLE
    Get-ProductsCab -OutFile "C:\Temp\products.cab" -Architecture "x64" `
                    -BuildVersion "10.0.22621" -UserAgent $userAgent

    .OUTPUTS
    None - Downloads products.cab to specified OutFile path
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutFile,

        [Parameter(Mandatory = $true)]
        [ValidateSet('x64', 'arm64')]
        [string]$Architecture,

        [Parameter(Mandatory = $true)]
        [string]$BuildVersion,

        [Parameter(Mandatory = $true)]
        [string]$UserAgent
    )

    $productsArchitecture = if ($Architecture -eq 'arm64') { 'arm64' } else { 'amd64' }
    $productsParam = "PN=Windows.Products.Cab.$productsArchitecture&V=$BuildVersion"
    $deviceAttributes = "DUScan=1;OSVersion=10.0.26100.1"

    $bodyObj = [ordered]@{
        Products         = $productsParam
        DeviceAttributes = $deviceAttributes
    }
    $bodyJson = $bodyObj | ConvertTo-Json -Compress

    $searchUri = 'https://fe3.delivery.mp.microsoft.com/UpdateMetadataService/updates/search/v1/bydeviceinfo'

    WriteLog "Requesting products.cab location from Windows Update service..."
    try {
        $searchResponse = Invoke-RestMethod -Uri $searchUri -Method Post -ContentType 'application/json' -Headers @{ Accept = '*/*' } -Body $bodyJson
    }
    catch {
        WriteLog "Failed to retrieve products.cab metadata: $($_.Exception.Message)"
        throw
    }

    if ($searchResponse -is [System.Array]) { $searchResponse = $searchResponse[0] }
    if (-not $searchResponse.FileLocations) { throw "Search response did not include FileLocations." }

    $fileRec = $searchResponse.FileLocations | Where-Object { $_.FileName -eq 'products.cab' } | Select-Object -First 1
    if (-not $fileRec) { throw "products.cab entry not found in FileLocations." }

    $downloadUrl = $fileRec.Url
    $serverDigestB64 = $fileRec.Digest
    $serverSize = [int64]$fileRec.Size
    $updateId = $searchResponse.UpdateIds[0]

    try {
        $metaUri = "https://fe3.delivery.mp.microsoft.com/UpdateMetadataService/updates/v1/$updateId"
        $meta = Invoke-RestMethod -Uri $metaUri -Method Get -Headers @{ Accept = '*/*' }
        if ($meta.LocalizedProperties.Count -gt 0) {
            $title = $meta.LocalizedProperties[0].Title
            WriteLog "Resolved update: $title"
        }
        else {
            WriteLog "Resolved update id: $updateId"
        }
    }
    catch {
        WriteLog "Resolved update id: $updateId"
    }

    $destDir = Split-Path -Path $OutFile -Parent
    if ($destDir -and -not (Test-Path $destDir)) {
        [void](New-Item -ItemType Directory -Path $destDir)
    }

    WriteLog "Downloading products.cab to $OutFile ..."
    $downloadHeaders = @{ Accept = '*/*' }
    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $OutFile -Headers $downloadHeaders -UserAgent $UserAgent -ErrorAction Stop
    }
    catch [System.Net.WebException] {
        WriteLog "ERROR: Network error downloading products.cab: $($_.Exception.Message)"
        throw "Failed to download Windows products catalog: $($_.Exception.Message)"
    }
    catch {
        WriteLog "ERROR: Failed to download products.cab: $($_.Exception.Message)"
        throw
    }

    $actualSize = (Get-Item $OutFile).Length
    if ($actualSize -ne $serverSize) {
        throw "Size check failed. Expected $serverSize bytes. Got $actualSize bytes."
    }

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $fs = [System.IO.File]::OpenRead($OutFile)
    try {
        $hashBytes = $sha256.ComputeHash($fs)
    }
    finally {
        $fs.Dispose()
    }
    $actualDigestB64 = [Convert]::ToBase64String($hashBytes)

    if ($actualDigestB64 -ne $serverDigestB64) {
        throw "Digest check failed. Expected $serverDigestB64. Got $actualDigestB64."
    }

    WriteLog "products.cab downloaded and verified successfully."
    return $OutFile
}

function Get-WindowsESD {
    <#
    .SYNOPSIS
    Downloads Windows ESD (Electronic Software Distribution) file from Microsoft

    .DESCRIPTION
    Downloads the Windows 10 or 11 ESD file from Microsoft's official servers.
    For Windows 11, downloads and parses products.cab. For Windows 10, uses direct download link.

    .PARAMETER WindowsRelease
    Windows release version (10 or 11)

    .PARAMETER WindowsArch
    Windows architecture (x86, x64, or ARM64)

    .PARAMETER WindowsLang
    Windows language code (e.g., en-us)

    .PARAMETER MediaType
    Media type: consumer or business

    .PARAMETER TempPath
    Temporary path for downloading cab/XML files

    .PARAMETER Headers
    HTTP headers hashtable for web requests

    .PARAMETER UserAgent
    User agent string for web requests

    .PARAMETER WindowsVersion
    Windows version (e.g., 22H2, 23H2, 24H2) for Windows 11

    .PARAMETER FFUDevelopmentPath
    Root FFUDevelopment path for download progress tracking

    .EXAMPLE
    Get-WindowsESD -WindowsRelease 11 -WindowsArch 'x64' -WindowsLang 'en-us' `
                   -MediaType 'consumer' -TempPath 'C:\Temp' -Headers @{} `
                   -UserAgent 'Mozilla/5.0' -WindowsVersion '24H2' `
                   -FFUDevelopmentPath 'C:\FFU'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet(10, 11)]
        [int]$WindowsRelease,

        [Parameter(Mandatory = $false)]
        [ValidateSet('x86', 'x64', 'ARM64')]
        [string]$WindowsArch,

        [Parameter(Mandatory = $false)]
        [string]$WindowsLang,

        [Parameter(Mandatory = $false)]
        [ValidateSet('consumer', 'business')]
        [string]$MediaType,

        [Parameter(Mandatory = $true)]
        [string]$TempPath,

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,

        [Parameter(Mandatory = $true)]
        [string]$UserAgent,

        [Parameter(Mandatory = $true)]
        [string]$WindowsVersion,

        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath
    )
    WriteLog "Downloading Windows $WindowsRelease ESD file"
    WriteLog "Windows Architecture: $WindowsArch"
    WriteLog "Windows Language: $WindowsLang"
    WriteLog "Windows Media Type: $MediaType"

    $cabFilePath = Join-Path $TempPath "tempCabFile.cab"
    $OriginalVerbosePreference = $VerbosePreference
    $VerbosePreference = 'SilentlyContinue'
    try {
        if ($WindowsRelease -eq 10) {
            WriteLog "Downloading Cab file"
            Invoke-WebRequest -Uri 'https://go.microsoft.com/fwlink/?LinkId=841361' -OutFile $cabFilePath -Headers $Headers -UserAgent $UserAgent
        }
        elseif ($WindowsRelease -eq 11) {
            WriteLog "Downloading Cab file"
            $buildVersionMap = @{
                '22H2' = '22621.0.0.0'
                '23H2' = '22631.0.0.0'
                '24H2' = '26100.0.0.0'
                '25H2' = '26100.0.0.0'
            }
            $normalizedVersion = $WindowsVersion.ToUpper()
            if ($buildVersionMap.ContainsKey($normalizedVersion)) {
                $buildVersion = $buildVersionMap[$normalizedVersion]
            }
            else {
                WriteLog "No explicit build mapping found for Windows 11 version '$WindowsVersion'. Defaulting products.cab build token to 26100.0.0.0."
                $buildVersion = '26100.0.0.0'
            }

            $cabArchitecture = if ($WindowsArch -eq 'ARM64') { 'arm64' } else { 'x64' }
            Get-ProductsCab -OutFile $cabFilePath -Architecture $cabArchitecture -BuildVersion $buildVersion -UserAgent $UserAgent | Out-Null
        }
        else {
            throw "Downloading Windows $WindowsRelease is not supported. Please use the -ISOPath parameter to specify the path to the Windows $WindowsRelease ISO file."
        }
        WriteLog "Download succeeded"
    }
    finally {
        $VerbosePreference = $OriginalVerbosePreference
    }

    # Extract XML from cab file
    WriteLog "Extracting Products XML from cab"
    $xmlFilePath = Join-Path $TempPath "products.xml"
    try {
        # Use full path to expand.exe to avoid conflicts with Unix 'expand' command in hybrid environments
        $expandExe = Join-Path $env:SystemRoot 'System32\expand.exe'
        Invoke-Process $expandExe "-F:*.xml $cabFilePath $xmlFilePath" -ErrorAction Stop | Out-Null
        WriteLog "Products XML extracted"
    }
    catch {
        WriteLog "ERROR: Failed to extract Products XML from cab: $($_.Exception.Message)"
        throw "Failed to extract Windows products catalog: $($_.Exception.Message)"
    }

    # Load XML content
    try {
        [xml]$xmlContent = Get-Content -Path $xmlFilePath -ErrorAction Stop
    }
    catch {
        WriteLog "ERROR: Failed to parse Products XML: $($_.Exception.Message)"
        throw "Failed to parse Windows products catalog: $($_.Exception.Message)"
    }

    # Define the client type to look for in the FilePath
    $clientType = if ($MediaType -eq 'consumer') { 'CLIENTCONSUMER' } else { 'CLIENTBUSINESS' }

    # Find FilePath values based on WindowsArch, WindowsLang, and MediaType
    foreach ($file in $xmlContent.MCT.Catalogs.Catalog.PublishedMedia.Files.File) {
        if ($file.Architecture -eq $WindowsArch -and $file.LanguageCode -eq $WindowsLang -and $file.FilePath -like "*$clientType*") {
            $esdFilePath = Join-Path $TempPath (Split-Path $file.FilePath -Leaf)
            #Download if ESD file doesn't already exist
            If (-not (Test-Path $esdFilePath)) {
                WriteLog "Downloading $($file.filePath) to $esdFIlePath"
                $OriginalVerbosePreference = $VerbosePreference
                $VerbosePreference = 'SilentlyContinue'
                Set-DownloadInProgress -FFUDevelopmentPath $FFUDevelopmentPath -TargetPath $esdFilePath
                try {
                    # Use resilient download with BITS fallback for large ESD files
                    Start-BitsTransferWithRetry -Source $file.FilePath -Destination $esdFilePath -Retries 3 -ErrorAction Stop | Out-Null
                    WriteLog "Download succeeded using resilient download system"
                }
                catch {
                    WriteLog "ERROR: ESD download failed after retries - $($_.Exception.Message)"
                    Clear-DownloadInProgress -FFUDevelopmentPath $FFUDevelopmentPath -TargetPath $esdFilePath
                    $VerbosePreference = $OriginalVerbosePreference
                    throw "Failed to download ESD file: $($_.Exception.Message)"
                }
                Clear-DownloadInProgress -FFUDevelopmentPath $FFUDevelopmentPath -TargetPath $esdFilePath
                $VerbosePreference = $OriginalVerbosePreference
                WriteLog "Cleanup cab and xml file"
                if (-not [string]::IsNullOrWhiteSpace($cabFilePath)) {
                    Remove-Item -Path $cabFilePath -Force -ErrorAction SilentlyContinue
                }
                if (-not [string]::IsNullOrWhiteSpace($xmlFilePath)) {
                    Remove-Item -Path $xmlFilePath -Force -ErrorAction SilentlyContinue
                }
                WriteLog "Cleanup done"
            }
            return $esdFilePath
        }
    }
}

function Get-KBLink {
    <#
    .SYNOPSIS
    Retrieves download links for Windows updates from the Microsoft Update Catalog

    .DESCRIPTION
    Searches the Microsoft Update Catalog for a specific update by name and returns
    the download URLs. Supports filtering by architecture and other criteria.
    Extracts KB article IDs when available (not applicable to Defender/Edge updates).

    .PARAMETER Name
    The name or search term for the update (e.g., "2024-01 Cumulative Update for Windows 11")

    .PARAMETER Headers
    HTTP headers to use for catalog requests (includes session cookies and metadata)

    .PARAMETER UserAgent
    User agent string to identify the client making catalog requests

    .PARAMETER Filter
    Optional array of filter criteria to match against update descriptions (e.g., @('x64', 'Windows 11')).
    If not provided or empty, returns the first matching update without filtering.

    .EXAMPLE
    $headers = @{ 'User-Agent' = 'Mozilla/5.0' }
    Get-KBLink -Name "2024-01 Cumulative Update" -Headers $headers -UserAgent $userAgent -Filter @('x64')

    .OUTPUTS
    PSCustomObject - Object with KBArticleID (string or null) and Links (array of download URLs)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,

        [Parameter(Mandatory = $true)]
        [string]$UserAgent,

        [Parameter(Mandatory = $false)]
        [string[]]$Filter = @()
    )
    $OriginalVerbosePreference = $VerbosePreference
    $VerbosePreference = 'SilentlyContinue'

    # Search catalog with retry logic for network resilience
    $maxRetries = 3
    $retryDelay = 10
    $results = $null

    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        try {
            $results = Invoke-WebRequest -Uri "http://www.catalog.update.microsoft.com/Search.aspx?q=$Name" -Headers $Headers -UserAgent $UserAgent -ErrorAction Stop
            break
        }
        catch {
            $VerbosePreference = $OriginalVerbosePreference
            if ($attempt -eq $maxRetries) {
                WriteLog "ERROR: Failed to search Update Catalog after $maxRetries attempts: $($_.Exception.Message)"
                return [PSCustomObject]@{
                    KBArticleID = $null
                    Links = @()
                }
            }
            WriteLog "WARNING: Update Catalog search failed (attempt $attempt of $maxRetries): $($_.Exception.Message)"
            WriteLog "Retrying in $retryDelay seconds..."
            Start-Sleep -Seconds $retryDelay
            $retryDelay = $retryDelay * 2  # Exponential backoff
            $VerbosePreference = 'SilentlyContinue'
        }
    }

    $VerbosePreference = $OriginalVerbosePreference

    # Extract the first KB article ID from the HTML content
    # Edge and Defender do not have KB article IDs
    $kbArticleID = $null
    if ($Name -notmatch 'Defender|Edge') {
        if ($results.Content -match '>\s*([^\(<]+)\(KB(\d+)\)(?:\s*\([^)]+\))*\s*<') {
            $kbArticleID = "KB$($matches[2])"
            WriteLog "Found KB article ID: $kbArticleID"
        }
        else {
            WriteLog "No KB article ID found in search results."
        }
    }

    $kbids = $results.InputFields |
    Where-Object { $_.type -eq 'Button' -and $_.Value -eq 'Download' } |
    Select-Object -ExpandProperty  ID

    if (-not $kbids) {
        Write-Warning -Message "No results found for $Name"
        # Return empty result with KB article ID if available
        return [PSCustomObject]@{
            KBArticleID = $kbArticleID
            Links = @()
        }
    }

    # Apply Filter if provided, otherwise return all results
    if ($Filter -and $Filter.Count -gt 0) {
        $guids = $results.Links |
        Where-Object ID -match '_link' |
        Where-Object { $_.OuterHTML -match ( "(?=.*" + ( $Filter -join ")(?=.*" ) + ")" ) } |
        Select-Object -First 1 |
        ForEach-Object { $_.id.replace('_link', '') } |
        Where-Object { $_ -in $kbids }
    }
    else {
        # No filter - return first matching result
        $guids = $results.Links |
        Where-Object ID -match '_link' |
        Select-Object -First 1 |
        ForEach-Object { $_.id.replace('_link', '') } |
        Where-Object { $_ -in $kbids }
    }

    if (-not $guids) {
        Write-Warning -Message "No file found for $Name"
        # Return empty result with KB article ID if available
        return [PSCustomObject]@{
            KBArticleID = $kbArticleID
            Links = @()
        }
    }

    # Collect all download links
    $downloadLinks = @()
    foreach ($guid in $guids) {
        # Write-Verbose -Message "Downloading information for $guid"
        $post = @{ size = 0; updateID = $guid; uidInfo = $guid } | ConvertTo-Json -Compress
        $body = @{ updateIDs = "[$post]" }
        $OriginalVerbosePreference = $VerbosePreference
        $VerbosePreference = 'SilentlyContinue'

        # Get download links with error handling
        $links = $null
        try {
            $links = Invoke-WebRequest -Uri 'https://www.catalog.update.microsoft.com/DownloadDialog.aspx' -Method Post -Body $body -Headers $Headers -UserAgent $UserAgent -ErrorAction Stop |
            Select-Object -ExpandProperty Content |
            Select-String -AllMatches -Pattern "http[s]?://[^']*\.microsoft\.com/[^']*|http[s]?://[^']*\.windowsupdate\.com/[^']*" |
            Select-Object -Unique
        }
        catch {
            $VerbosePreference = $OriginalVerbosePreference
            WriteLog "WARNING: Failed to get download links for $guid : $($_.Exception.Message)"
            continue
        }

        $VerbosePreference = $OriginalVerbosePreference

        foreach ($link in $links) {
            $downloadLinks += $link.matches.value
            #Filter out cab files
            # #if ($link -notmatch '\.cab') {
            #     $downloadLinks += $link.matches.value
            # }

        }
    }

    # Return structured object with KB article ID and links
    return [PSCustomObject]@{
        KBArticleID = $kbArticleID
        Links = $downloadLinks
    }
}

function Get-UpdateFileInfo {
    <#
    .SYNOPSIS
    Retrieves download information for Windows updates from Microsoft Update Catalog

    .DESCRIPTION
    Searches Microsoft Update Catalog for specified updates and returns download URLs
    filtered by target architecture. Used to discover update file names and URLs
    before downloading. Automatically filters out duplicate entries.

    .PARAMETER Name
    Array of update names or KB numbers to search for

    .PARAMETER WindowsArch
    Target Windows architecture (x86, x64, or arm64) for update filtering

    .PARAMETER Headers
    HTTP headers hashtable for catalog requests (includes session cookies and metadata)

    .PARAMETER UserAgent
    User agent string to identify the client making catalog requests

    .PARAMETER Filter
    Optional array of filter criteria to match against update descriptions.
    If not provided or empty, downloads the first matching update without filtering.

    .EXAMPLE
    $updates = Get-UpdateFileInfo -Name @('KB5034441') -WindowsArch 'x64' `
                                   -Headers $headers -UserAgent $userAgent -Filter @('Windows 11', 'x64')

    .OUTPUTS
    System.Collections.Generic.List[PSCustomObject] - Array of objects with Name, Url, and KBArticleID properties
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateSet('x86', 'x64', 'arm64')]
        [string]$WindowsArch,

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,

        [Parameter(Mandatory = $true)]
        [string]$UserAgent,

        [Parameter(Mandatory = $false)]
        [string[]]$Filter = @()
    )
    $updateFileInfos = [System.Collections.Generic.List[pscustomobject]]::new()

    foreach ($kb in $Name) {
        # Get-KBLink now returns a structured object with KBArticleID and Links
        $kbResult = Get-KBLink -Name $kb -Headers $Headers -UserAgent $UserAgent -Filter $Filter

        # Extract KB article ID and links from the result object
        $kbArticleID = $kbResult.KBArticleID
        $links = $kbResult.Links

        foreach ($link in $links) {
            $fileName = ($link -split '/')[-1]

            $architectureMatch = $false
            if ($link -match 'x64' -or $link -match 'amd64') {
                if ($WindowsArch -eq 'x64') { $architectureMatch = $true }
            }
            elseif ($link -match 'arm64') {
                if ($WindowsArch -eq 'arm64') { $architectureMatch = $true }
            }
            elseif ($link -match 'x86') {
                if ($WindowsArch -eq 'x86') { $architectureMatch = $true }
            }
            else {
                # If no architecture is specified in the URL, we assume the search query was specific enough.
                # The alternative is to download the file to check, which defeats the purpose of this function.
                $architectureMatch = $true
            }

            if ($architectureMatch) {
                # Check for duplicates before adding
                if (-not ($updateFileInfos.Name -contains $fileName)) {
                    $updateFileInfos.Add([pscustomobject]@{
                            Name = $fileName
                            Url  = $link
                            KBArticleID = $kbArticleID
                        })
                }
            }
        }
    }
    return $updateFileInfos
}

function Save-KB {
    <#
    .SYNOPSIS
    Downloads Windows update files (KB, MSU, CAB) from Microsoft Update Catalog

    .DESCRIPTION
    Downloads Windows updates for the specified architecture from Microsoft Update Catalog.
    Automatically filters by architecture and validates downloaded files match the target platform.
    Supports fallback analysis for updates without explicit architecture in filenames.

    .PARAMETER Name
    Array of update names or KB numbers to download

    .PARAMETER Path
    Destination folder path for downloaded update files

    .PARAMETER WindowsArch
    Target Windows architecture (x64, x86, or arm64) for update filtering

    .PARAMETER Headers
    HTTP headers to use for catalog requests (includes session cookies and metadata)

    .PARAMETER UserAgent
    User agent string to identify the client making catalog requests

    .PARAMETER Filter
    Optional array of filter criteria to match against update descriptions.
    If not provided or empty, downloads the first matching update without filtering.

    .EXAMPLE
    # With filter
    Save-KB -Name @('KB5034441') -Path 'C:\Updates' -WindowsArch 'x64' `
            -Headers $headers -UserAgent $userAgent -Filter @('Windows 11', 'x64')

    # Without filter (returns first match)
    Save-KB -Name @('KB5034441') -Path 'C:\Updates' -WindowsArch 'x64' `
            -Headers $headers -UserAgent $userAgent

    .OUTPUTS
    System.String - Filename of the downloaded update file
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateSet('x64', 'x86', 'arm64')]
        [string]$WindowsArch,

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,

        [Parameter(Mandatory = $true)]
        [string]$UserAgent,

        [Parameter(Mandatory = $false)]
        [string[]]$Filter = @()
    )
    foreach ($kb in $name) {
        # Architecture-agnostic updates: Defender, Edge, and Security Platform updates
        # don't have architecture indicators (x64/x86/ARM64) in their Microsoft Update Catalog titles.
        # Skip the filter for these updates and rely on post-download architecture detection.
        $isArchAgnosticUpdate = $kb -match 'Defender|Edge|Security Platform'

        if ($isArchAgnosticUpdate -and $Filter -and $Filter.Count -gt 0) {
            WriteLog "Update '$kb' is architecture-agnostic in catalog listing. Skipping architecture filter."
            $kbResult = Get-KBLink -Name $kb -Headers $Headers -UserAgent $UserAgent -Filter @()
        } else {
            $kbResult = Get-KBLink -Name $kb -Headers $Headers -UserAgent $UserAgent -Filter $Filter
        }
        $links = $kbResult.Links

        # Check if Get-KBLink returned any links
        if (-not $links -or $links.Count -eq 0) {
            WriteLog "WARNING: No download links found for '$kb' with Filter: $($Filter -join ', '). This may indicate the update is not available for the specified architecture or search criteria."
            continue  # Skip to next KB in the array
        }

        WriteLog "Found $($links.Count) download link(s) for '$kb'"

        foreach ($link in $links) {
            # if (!($link -match 'x64' -or $link -match 'amd64' -or $link -match 'x86' -or $link -match 'arm64')) {
            #     WriteLog "No architecture found in $link, skipping"
            #     continue
            # }

            if ($link -match 'x64' -or $link -match 'amd64') {
                if ($WindowsArch -eq 'x64') {
                    WriteLog "Downloading $link for $WindowsArch to $Path"
                    try {
                        Start-BitsTransferWithRetry -Source $link -Destination $Path -ErrorAction Stop | Out-Null
                        $fileName = ($link -split '/')[-1]
                        WriteLog "Download complete: $fileName"
                        return $fileName
                    }
                    catch [System.Net.WebException] {
                        WriteLog "ERROR: Network error downloading update from $link : $($_.Exception.Message)"
                        continue
                    }
                    catch {
                        WriteLog "ERROR: Failed to download update from $link : $($_.Exception.Message)"
                        continue
                    }
                }
            }
            elseif ($link -match 'arm64') {
                if ($WindowsArch -eq 'arm64') {
                    WriteLog "Downloading $link for $WindowsArch to $Path"
                    try {
                        Start-BitsTransferWithRetry -Source $link -Destination $Path -ErrorAction Stop | Out-Null
                        $fileName = ($link -split '/')[-1]
                        WriteLog "Download complete: $fileName"
                        return $fileName
                    }
                    catch [System.Net.WebException] {
                        WriteLog "ERROR: Network error downloading update from $link : $($_.Exception.Message)"
                        continue
                    }
                    catch {
                        WriteLog "ERROR: Failed to download update from $link : $($_.Exception.Message)"
                        continue
                    }
                }
            }
            elseif ($link -match 'x86') {
                if ($WindowsArch -eq 'x86') {
                    WriteLog "Downloading $link for $WindowsArch to $Path"
                    try {
                        Start-BitsTransferWithRetry -Source $link -Destination $Path -ErrorAction Stop | Out-Null
                        $fileName = ($link -split '/')[-1]
                        WriteLog "Download complete: $fileName"
                        return $fileName
                    }
                    catch [System.Net.WebException] {
                        WriteLog "ERROR: Network error downloading update from $link : $($_.Exception.Message)"
                        continue
                    }
                    catch {
                        WriteLog "ERROR: Failed to download update from $link : $($_.Exception.Message)"
                        continue
                    }
                }
            }
            else {
                WriteLog "No architecture found in $link"

                #If no architecture is found, download the file and run it through Get-PEArchitecture to determine the architecture
                WriteLog "Downloading $link to $Path and analyzing file for architecture"
                try {
                    Start-BitsTransferWithRetry -Source $link -Destination $Path -ErrorAction Stop | Out-Null
                }
                catch [System.Net.WebException] {
                    WriteLog "ERROR: Network error downloading update from $link : $($_.Exception.Message)"
                    continue
                }
                catch {
                    WriteLog "ERROR: Failed to download update from $link : $($_.Exception.Message)"
                    continue
                }

                #Take the file and run it through Get-PEArchitecture to determine the architecture
                $fileName = ($link -split '/')[-1]
                $filePath = Join-Path -Path $Path -ChildPath $fileName
                try {
                    $arch = Get-PEArchitecture -FilePath $filePath -ErrorAction Stop
                    WriteLog "$fileName is $arch"
                }
                catch {
                    WriteLog "WARNING: Failed to determine architecture of $fileName : $($_.Exception.Message)"
                    $arch = $null
                }

                #If the architecture matches $WindowsArch, keep the file, otherwise delete it
                if ($arch -eq $WindowsArch) {
                    WriteLog "Architecture for $fileName matches $WindowsArch, keeping file"
                    return $fileName
                }
                else {
                    WriteLog "Deleting $fileName, architecture does not match"
                    if (-not [string]::IsNullOrWhiteSpace($filePath)) {
                        try {
                            Remove-Item -Path $filePath -Force -ErrorAction Stop
                        }
                        catch {
                            WriteLog "WARNING: Failed to delete $fileName : $($_.Exception.Message)"
                        }
                    }
                }
            }

        }
    }

    # If we reached here, no matching architecture file was found
    WriteLog "ERROR: No file matching architecture '$WindowsArch' was found for update(s): $($Name -join ', ')"
    WriteLog "ERROR: All download links were checked but none matched the target architecture."
    WriteLog "ERROR: Filter used: $($Filter -join ', ')"
    return $null
}

function Test-MountedImageDiskSpace {
    <#
    .SYNOPSIS
    Validates sufficient disk space on mounted image for MSU extraction

    .DESCRIPTION
    Checks if the mounted image has sufficient free disk space to extract and apply MSU packages.
    MSU extraction requires approximately 3x the package size plus a safety margin.

    .PARAMETER Path
    The path to the mounted Windows image

    .PARAMETER PackagePath
    The path to the MSU package file

    .PARAMETER SafetyMarginGB
    Additional safety margin in GB (default: 5GB)

    .EXAMPLE
    Test-MountedImageDiskSpace -Path "W:\" -PackagePath "C:\KB\kb5066835.msu"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$PackagePath,

        [Parameter()]
        [int]$SafetyMarginGB = 5
    )

    $packageSizeGB = [Math]::Round((Get-Item $PackagePath).Length / 1GB, 2)
    $requiredSpaceGB = ($packageSizeGB * 3) + $SafetyMarginGB  # 3x for extraction + safety margin

    $drive = (Get-Item $Path).PSDrive
    $freeSpaceGB = [Math]::Round($drive.Free / 1GB, 2)

    if ($freeSpaceGB -lt $requiredSpaceGB) {
        WriteLog "WARNING: Insufficient disk space on mounted image. Free: ${freeSpaceGB}GB, Required: ${requiredSpaceGB}GB"
        WriteLog "Package size: ${packageSizeGB}GB"
        return $false
    }

    WriteLog "Disk space check passed. Free: ${freeSpaceGB}GB, Required: ${requiredSpaceGB}GB"
    return $true
}

function Test-FileLocked {
    <#
    .SYNOPSIS
    Tests if a file is locked by another process

    .DESCRIPTION
    Attempts to open the file with exclusive ReadWrite access to determine if it's locked.
    Returns true if the file is locked, false if it's accessible.

    .PARAMETER Path
    The path to the file to test

    .EXAMPLE
    if (Test-FileLocked -Path "C:\KB\update.msu") {
        Write-Host "File is locked by another process"
    }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        WriteLog "WARNING: File does not exist for lock test: $Path"
        return $false
    }

    try {
        $file = [System.IO.File]::Open($Path, 'Open', 'ReadWrite', 'None')
        $file.Close()
        return $false
    }
    catch [System.IO.IOException] {
        # File is locked
        return $true
    }
    catch {
        # Other errors (permissions, etc.) - treat as locked
        WriteLog "WARNING: File lock test failed: $($_.Exception.Message)"
        return $true
    }
}

function Test-DISMServiceHealth {
    <#
    .SYNOPSIS
    Validates DISM service (TrustedInstaller) availability

    .DESCRIPTION
    Checks if the TrustedInstaller service is available and not disabled.
    NOTE: TrustedInstaller is a demand-start service - Windows automatically starts it
    when DISM operations are invoked and stops it when complete. We should NOT try to
    start it manually; we only verify it's not disabled.

    Returns true if the service is available (exists and not disabled), false otherwise.

    .EXAMPLE
    if (-not (Test-DISMServiceHealth)) {
        Write-Error "DISM service is not available"
    }
    #>
    [CmdletBinding()]
    param()

    try {
        $service = Get-Service -Name 'TrustedInstaller' -ErrorAction Stop

        # Check if service is disabled - this is a real problem
        if ($service.StartType -eq 'Disabled') {
            WriteLog "ERROR: TrustedInstaller service is disabled. DISM operations will fail."
            WriteLog "RESOLUTION: Enable the Windows Modules Installer service:"
            WriteLog "  Run: Set-Service -Name TrustedInstaller -StartupType Manual"
            return $false
        }

        # TrustedInstaller is demand-start (Manual) - Windows starts it when needed
        # Log current status for debugging purposes but don't try to change it
        WriteLog "TrustedInstaller service: StartType=$($service.StartType), Status=$($service.Status)"

        # Service exists and is not disabled - it's healthy
        return $true
    }
    catch {
        WriteLog "ERROR: Failed to query TrustedInstaller service: $($_.Exception.Message)"
        WriteLog "RESOLUTION: The Windows Modules Installer service may be corrupted. Consider running:"
        WriteLog "  sfc /scannow"
        return $false
    }
}

function Test-MountState {
    <#
    .SYNOPSIS
    Validates that a mounted Windows image is still accessible

    .DESCRIPTION
    Checks if the specified path exists and can be queried with DISM commands.
    Returns true if the mount is healthy, false if the mount is lost or corrupted.

    .PARAMETER Path
    The path to the mounted Windows image

    .EXAMPLE
    if (-not (Test-MountState -Path "W:\")) {
        Write-Error "Mounted image is no longer accessible"
    }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    # First check if path exists
    if (-not (Test-Path $Path)) {
        WriteLog "ERROR: Mounted image path not found: $Path"
        return $false
    }

    # Try to query the image with DISM
    try {
        $null = Get-WindowsEdition -Path $Path -ErrorAction Stop
        return $true
    }
    catch {
        WriteLog "ERROR: Mounted image is not accessible via DISM: $($_.Exception.Message)"
        return $false
    }
}

function Add-WindowsPackageWithRetry {
    <#
    .SYNOPSIS
    Applies Windows packages with automatic retry logic

    .DESCRIPTION
    Wraps Add-WindowsPackageWithUnattend with retry logic to handle transient failures.
    Useful for MSU packages that occasionally fail due to timing or resource contention issues.

    .PARAMETER Path
    The path to the mounted Windows image

    .PARAMETER PackagePath
    The path to the MSU or CAB package file

    .PARAMETER MaxRetries
    Maximum number of retry attempts (default: 2)

    .PARAMETER RetryDelaySeconds
    Delay in seconds between retry attempts (default: 30)

    .EXAMPLE
    Add-WindowsPackageWithRetry -Path "W:\" -PackagePath "C:\KB\kb5066835.msu" -MaxRetries 3
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$PackagePath,

        [Parameter()]
        [int]$MaxRetries = [FFUConstants]::MAX_PACKAGE_RETRIES,

        [Parameter()]
        [int]$RetryDelaySeconds = [FFUConstants]::RETRY_DELAY
    )

    $packageName = Split-Path $PackagePath -Leaf
    $attempt = 0
    $success = $false

    while (-not $success -and $attempt -lt $MaxRetries) {
        $attempt++

        try {
            if ($attempt -gt 1) {
                WriteLog "Retry attempt $attempt of $MaxRetries for package: $packageName"

                # Validate mount state before retry
                WriteLog "Validating mounted image state..."
                if (-not (Test-MountState -Path $Path)) {
                    WriteLog "CRITICAL: Mounted image at $Path is no longer accessible"
                    WriteLog "The VHDX may have been dismounted due to a previous DISM service crash"
                    WriteLog "RESOLUTION: Reboot your computer and restart the FFU build process"
                    throw "Mounted image lost between retry attempts. Cannot continue."
                }
                WriteLog "Mount state validation passed. Image is accessible."

                # Validate DISM service health before retry
                WriteLog "Validating DISM service health..."
                if (-not (Test-DISMServiceHealth)) {
                    WriteLog "CRITICAL: DISM service (TrustedInstaller) is not healthy"
                    WriteLog "The service may have crashed during the previous package application attempt"
                    WriteLog "RESOLUTION: Reboot your computer and restart the FFU build process"
                    throw "DISM service is not available for retry. Cannot continue."
                }
                WriteLog "DISM service health check passed. TrustedInstaller is available."

                WriteLog "Waiting $RetryDelaySeconds seconds before retry..."
                Start-Sleep -Seconds $RetryDelaySeconds

                WriteLog "Refreshing DISM mount state before retry..."
                # Clear any potentially stuck DISM operations
                $null = Get-WindowsEdition -Path $Path -ErrorAction SilentlyContinue
            }

            Add-WindowsPackageWithUnattend -Path $Path -PackagePath $PackagePath
            $success = $true
            WriteLog "Package $packageName applied successfully on attempt $attempt"
        }
        catch {
            WriteLog "ERROR: Attempt $attempt failed for package $packageName - $($_.Exception.Message)"

            if ($attempt -ge $MaxRetries) {
                WriteLog "CRITICAL: All $MaxRetries attempts failed for package $packageName"
                WriteLog "RESOLUTION: Reboot your computer and restart the FFU build process"
                WriteLog "A reboot will clear file locks, reset services, and resolve most transient issues"
                throw $_
            }
        }
    }
}

function Add-WindowsPackageWithUnattend {
    <#
    .SYNOPSIS
    Applies Windows update packages (MSU/CAB) with robust unattend.xml handling

    .DESCRIPTION
    Some MSU packages contain unattend.xml files that DISM fails to extract and apply automatically.
    This function extracts unattend.xml from MSU packages and applies it separately before
    applying the update package, working around DISM's "An error occurred applying the
    Unattend.xml file from the .msu package" error.

    Addresses Issue #301: Unattend.xml Extraction from MSU

    .PARAMETER Path
    The path to the mounted Windows image

    .PARAMETER PackagePath
    The path to the MSU or CAB package file

    .EXAMPLE
    Add-WindowsPackageWithUnattend -Path "W:\" -PackagePath "C:\KB\kb5066835.msu"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$PackagePath
    )

    $packageName = Split-Path $PackagePath -Leaf
    WriteLog "Applying package: $packageName"

    # For CAB files, apply directly (no unattend.xml issues)
    if ($PackagePath -match '\.cab$') {
        WriteLog "CAB file detected, applying directly with DISM"
        Add-WindowsPackage -Path $Path -PackagePath $PackagePath | Out-Null
        WriteLog "Package $packageName applied successfully"
        return
    }

    # For MSU files, check for unattend.xml and handle it separately
    if ($PackagePath -match '\.msu$') {
        # Validate MSU file integrity before attempting extraction
        WriteLog "Validating MSU package integrity: $packageName"
        $msuFileInfo = Get-Item $PackagePath -ErrorAction Stop

        if ($msuFileInfo.Length -eq 0) {
            WriteLog "ERROR: MSU package is empty (0 bytes): $packageName"
            throw "Corrupted or incomplete MSU package: $packageName"
        }

        # Check for minimum reasonable MSU size (typically >1MB)
        if ($msuFileInfo.Length -lt 1MB) {
            WriteLog "WARNING: MSU package is suspiciously small ($([Math]::Round($msuFileInfo.Length / 1MB, 2)) MB): $packageName"
        }

        WriteLog "MSU package validation passed. Size: $([Math]::Round($msuFileInfo.Length / 1MB, 2)) MB"

        # Check disk space before extraction
        if (-not (Test-MountedImageDiskSpace -Path $Path -PackagePath $PackagePath)) {
            WriteLog "ERROR: Insufficient disk space to extract MSU package"
            throw "Insufficient disk space on mounted image for MSU extraction"
        }

        # Use controlled temp directory instead of $env:TEMP for better reliability and shorter paths
        $kbFolder = Split-Path $PackagePath -Parent
        $extractBasePath = Join-Path $kbFolder "Temp"
        if (-not (Test-Path $extractBasePath)) {
            New-Item -Path $extractBasePath -ItemType Directory -Force | Out-Null
            WriteLog "Created controlled temp directory: $extractBasePath"
        }

        $extractPath = Join-Path $extractBasePath "MSU_Extract_$(Get-Date -Format 'yyyyMMddHHmmss')"
        $unattendExtracted = $false

        try {
            # Detect file locking before extraction (antivirus/Windows Defender interference)
            WriteLog "Checking for file locks on MSU package..."
            $lockRetries = 0
            $maxLockRetries = 5
            $lockRetryDelay = 10

            while ((Test-FileLocked -Path $PackagePath) -and $lockRetries -lt $maxLockRetries) {
                $lockRetries++
                WriteLog "WARNING: MSU file is locked by another process (attempt $lockRetries/$maxLockRetries)"
                WriteLog "This is typically caused by antivirus real-time scanning or Windows Defender"
                WriteLog "Waiting $lockRetryDelay seconds for file to become available..."
                Start-Sleep -Seconds $lockRetryDelay
            }

            if (Test-FileLocked -Path $PackagePath) {
                WriteLog "ERROR: MSU file remains locked after $($lockRetries * $lockRetryDelay) seconds"
                WriteLog "RESOLUTION: Try the following steps:"
                WriteLog "  1. Add the following paths to your antivirus exclusions:"
                WriteLog "     - $kbFolder"
                WriteLog "     - $extractBasePath"
                WriteLog "     - C:\FFUDevelopment\"
                WriteLog "  2. Reboot your computer and try again"
                WriteLog "     (This will clear any locked file handles and reset services)"
                throw "MSU file is locked by another process (likely antivirus): $PackagePath"
            }

            WriteLog "File lock check passed. MSU file is accessible."

            # Create extraction directory
            New-Item -Path $extractPath -ItemType Directory -Force | Out-Null
            WriteLog "Extracting MSU package to check for unattend.xml: $extractPath"

            # Extract MSU package using expand.exe with enhanced error handling
            # Note: Do not embed quotes in argument array - PowerShell handles quoting automatically
            $expandArgs = @(
                '-F:*',
                $PackagePath,
                $extractPath
            )

            WriteLog "Running expand.exe with arguments: expand.exe $($expandArgs -join ' ')"

            # Capture stderr and stdout
            $expandOutput = & expand.exe $expandArgs 2>&1
            $expandExitCode = $LASTEXITCODE

            WriteLog "expand.exe exit code: $expandExitCode"

            if ($expandExitCode -ne 0) {
                WriteLog "WARNING: expand.exe returned exit code $expandExitCode"
                WriteLog "expand.exe output: $($expandOutput | Out-String)"

                # Check specific exit codes
                switch ($expandExitCode) {
                    -1 { WriteLog "ERROR: expand.exe reported file system or permission error" }
                    1  { WriteLog "ERROR: expand.exe reported invalid syntax or file not found" }
                    2  { WriteLog "ERROR: expand.exe reported out of memory" }
                    default { WriteLog "ERROR: expand.exe reported unknown error: $expandExitCode" }
                }

                # Verify extraction path is accessible
                if (-not (Test-Path $extractPath)) {
                    WriteLog "ERROR: Extraction path does not exist or is inaccessible: $extractPath"
                }

                # Before falling back, verify the MSU file is readable
                try {
                    $testRead = [System.IO.File]::OpenRead($PackagePath)
                    $testRead.Close()
                    WriteLog "MSU file is readable, attempting direct DISM application"
                }
                catch {
                    WriteLog "ERROR: MSU file is not readable: $($_.Exception.Message)"
                    throw "MSU file is corrupted or inaccessible: $PackagePath"
                }

                WriteLog "Attempting direct package application with Add-WindowsPackage"

                try {
                    Add-WindowsPackage -Path $Path -PackagePath $PackagePath -ErrorAction Stop | Out-Null
                    WriteLog "Package $packageName applied successfully (direct method)"
                    return
                }
                catch {
                    WriteLog "ERROR: Direct DISM application also failed: $($_.Exception.Message)"

                    # Check if this is the known DISM temp folder error
                    if ($_.Exception.Message -match "temporary folder") {
                        WriteLog "CRITICAL: DISM failed to create temporary folder in mounted image"
                        WriteLog "This typically indicates insufficient disk space or permission issues"
                        WriteLog "Mounted image path: $Path"

                        # Attempt to get detailed volume information
                        try {
                            $driveLetter = $Path[0]
                            $volume = Get-Volume | Where-Object { $_.DriveLetter -eq $driveLetter }
                            if ($volume) {
                                WriteLog "Volume information - Size: $([Math]::Round($volume.Size / 1GB, 2))GB, Free: $([Math]::Round($volume.SizeRemaining / 1GB, 2))GB"
                            }
                        }
                        catch {
                            WriteLog "Could not retrieve volume information"
                        }
                    }

                    throw $_
                }
            }

            WriteLog "MSU extraction completed successfully"

            # Look for unattend.xml in extracted files
            $unattendFiles = Get-ChildItem -Path $extractPath -Filter "*.xml" -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match "unattend" -or $_.Name -match "Unattend" }

            if ($unattendFiles) {
                WriteLog "Found unattend.xml file(s) in MSU package: $($unattendFiles.Count) file(s)"

                foreach ($unattendFile in $unattendFiles) {
                    WriteLog "Processing unattend file: $($unattendFile.Name)"

                    # Copy unattend.xml to Windows\Panther directory for DISM to apply
                    $pantherPath = Join-Path $Path "Windows\Panther"
                    if (-not (Test-Path $pantherPath)) {
                        New-Item -Path $pantherPath -ItemType Directory -Force | Out-Null
                        WriteLog "Created Panther directory: $pantherPath"
                    }

                    $destUnattend = Join-Path $pantherPath "unattend.xml"

                    # Backup existing unattend.xml if present
                    if (Test-Path $destUnattend) {
                        $backupUnattend = Join-Path $pantherPath "unattend_backup_$(Get-Date -Format 'yyyyMMddHHmmss').xml"
                        Copy-Item -Path $destUnattend -Destination $backupUnattend -Force
                        WriteLog "Backed up existing unattend.xml to: $backupUnattend"
                    }

                    # Copy extracted unattend.xml
                    Copy-Item -Path $unattendFile.FullName -Destination $destUnattend -Force
                    WriteLog "Copied unattend.xml to Panther directory for DISM processing"
                    $unattendExtracted = $true
                }
            }
            else {
                WriteLog "No unattend.xml files found in MSU package (this is normal for most updates)"
            }

            # Windows 11 24H2/25H2 Checkpoint Cumulative Update Fix (error 0x80070228)
            # UUP (Unified Update Platform) packages like KB5043080 trigger Windows Update Agent
            # to download additional content, which fails on offline images with "Failed getting
            # the download request" (0x80070228).
            #
            # Solution: Apply the CAB file directly instead of the MSU. CAB files don't trigger
            # the UpdateAgent mechanism, completely bypassing the UUP download requirement.
            # See: https://learn.microsoft.com/en-us/answers/questions/3855149/

            # Find the main CAB file in the extracted MSU contents
            # Exclude WSUSSCAN.cab (metadata only) and look for the actual update CAB
            $cabFiles = Get-ChildItem -Path $extractPath -Filter "*.cab" -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch 'WSUSSCAN' -and $_.Name -notmatch 'wsusscan' }

            if ($cabFiles -and $cabFiles.Count -gt 0) {
                WriteLog "Found $($cabFiles.Count) CAB file(s) in MSU package - applying directly to bypass UUP"

                # Apply each CAB file (typically there's only one main CAB)
                foreach ($cabFile in $cabFiles) {
                    WriteLog "Applying CAB: $($cabFile.Name) (Size: $([Math]::Round($cabFile.Length / 1MB, 2)) MB)"

                    try {
                        Add-WindowsPackage -Path $Path -PackagePath $cabFile.FullName -ErrorAction Stop | Out-Null
                        WriteLog "CAB $($cabFile.Name) applied successfully"
                    }
                    catch {
                        # Check if error is "package already installed" (not an error for us)
                        if ($_.Exception.Message -match 'is already installed' -or
                            $_.Exception.Message -match '0x800f081e' -or
                            $_.Exception.Message -match 'CBS_E_ALREADY_INSTALLED') {
                            WriteLog "CAB $($cabFile.Name) is already installed (skipping)"
                        }
                        else {
                            WriteLog "ERROR applying CAB $($cabFile.Name): $($_.Exception.Message)"
                            throw $_
                        }
                    }
                }

                WriteLog "Package $packageName applied successfully via direct CAB method"
            }
            else {
                # Fallback: No CAB files found, try MSU directly with isolated directory
                WriteLog "WARNING: No CAB files found in extracted MSU, falling back to isolated MSU method"

                $isolatedApplyPath = Join-Path $extractBasePath "MSU_Apply_$(Get-Date -Format 'yyyyMMddHHmmss')"

                try {
                    # Create isolated directory and copy MSU there
                    New-Item -Path $isolatedApplyPath -ItemType Directory -Force | Out-Null
                    $isolatedPackagePath = Join-Path $isolatedApplyPath $packageName
                    Copy-Item -Path $PackagePath -Destination $isolatedPackagePath -Force
                    WriteLog "Isolated MSU to prevent checkpoint update conflict: $isolatedApplyPath"

                    # Apply the package from isolated directory
                    WriteLog "Applying package with Add-WindowsPackage (isolated mode)"
                    Add-WindowsPackage -Path $Path -PackagePath $isolatedPackagePath | Out-Null
                    WriteLog "Package $packageName applied successfully"
                }
                finally {
                    # Clean up isolated directory
                    if (Test-Path $isolatedApplyPath) {
                        Remove-Item -Path $isolatedApplyPath -Recurse -Force -ErrorAction SilentlyContinue
                        WriteLog "Cleaned up isolated MSU directory"
                    }
                }
            }

        }
        catch {
            WriteLog "ERROR: Failed to apply package $packageName - $($_.Exception.Message)"

            # If unattend.xml was extracted, clean it up to avoid affecting next package
            if ($unattendExtracted) {
                $pantherUnattend = Join-Path (Join-Path $Path "Windows\Panther") "unattend.xml"
                if (Test-Path $pantherUnattend) {
                    Remove-Item -Path $pantherUnattend -Force -ErrorAction SilentlyContinue
                    WriteLog "Cleaned up unattend.xml from Panther directory"
                }
            }

            throw $_
        }
        finally {
            # Clean up extraction directory
            if (Test-Path $extractPath) {
                Remove-Item -Path $extractPath -Recurse -Force -ErrorAction SilentlyContinue
                WriteLog "Cleaned up MSU extraction directory"
            }

            # Clean up unattend.xml from Panther after successful application
            if ($unattendExtracted) {
                $pantherUnattend = Join-Path (Join-Path $Path "Windows\Panther") "unattend.xml"
                if (Test-Path $pantherUnattend) {
                    Remove-Item -Path $pantherUnattend -Force -ErrorAction SilentlyContinue
                    WriteLog "Removed unattend.xml from Panther directory after package application"
                }
            }
        }
    }
    else {
        WriteLog "ERROR: Unknown package format: $packageName (expected .msu or .cab)"
        throw "Unsupported package format: $packageName"
    }
}

function Resolve-KBFilePath {
    <#
    .SYNOPSIS
    Resolves a KB file path using multiple fallback patterns

    .DESCRIPTION
    Attempts to locate a Windows Update package file in the KB folder using
    multiple search strategies:
    1. Direct filename match (if provided)
    2. KB article ID pattern match (*KBxxxxxx*)
    3. Update name pattern match

    Returns the full path if found, or $null if not found.
    This prevents the "empty PackagePath" error when files don't match expected patterns.

    .PARAMETER KBPath
    Base path to the KB downloads folder

    .PARAMETER FileName
    Optional specific filename to search for (from update info)

    .PARAMETER KBArticleId
    Optional KB article ID (e.g., "5046613") for pattern matching

    .PARAMETER UpdateType
    Type of update for logging (e.g., "CU", "NET", "SSU")

    .EXAMPLE
    Resolve-KBFilePath -KBPath "C:\FFU\KB" -KBArticleId "5046613" -UpdateType "CU"

    .EXAMPLE
    Resolve-KBFilePath -KBPath "C:\FFU\KB" -FileName "windows11.0-kb5046613-x64.msu" -UpdateType "CU"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$KBPath,

        [Parameter(Mandatory = $false)]
        [string]$FileName,

        [Parameter(Mandatory = $false)]
        [string]$KBArticleId,

        [Parameter(Mandatory = $false)]
        [string]$UpdateType = "Update"
    )

    # Helper function for safe logging (WriteLog may not be available in standalone tests)
    $logMessage = {
        param([string]$msg)
        if (Get-Command WriteLog -ErrorAction SilentlyContinue) {
            WriteLog $msg
        } else {
            Write-Verbose $msg
        }
    }

    # Ensure KB path exists
    if (-not (Test-Path -Path $KBPath)) {
        & $logMessage "WARNING: KB path does not exist: $KBPath"
        return $null
    }

    $resolvedPath = $null

    # Strategy 1: Try direct filename match first (most reliable)
    if ($FileName -and $FileName.Length -gt 0) {
        $directMatch = Get-ChildItem -Path $KBPath -Filter $FileName -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($directMatch) {
            $resolvedPath = $directMatch.FullName
            & $logMessage "Resolved $UpdateType path via direct filename match: $resolvedPath"
            return $resolvedPath
        }
    }

    # Strategy 2: Try KB article ID pattern match
    if ($KBArticleId -and $KBArticleId.Length -gt 0) {
        # Try with KB prefix
        $kbPattern = "*KB$KBArticleId*"
        $kbMatch = Get-ChildItem -Path $KBPath -Filter $kbPattern -Recurse -File -ErrorAction SilentlyContinue |
                   Where-Object { $_.Extension -in '.msu', '.cab' } |
                   Select-Object -First 1
        if ($kbMatch) {
            $resolvedPath = $kbMatch.FullName
            & $logMessage "Resolved $UpdateType path via KB article ID pattern ($kbPattern): $resolvedPath"
            return $resolvedPath
        }

        # Try without KB prefix (just the number)
        $numPattern = "*$KBArticleId*"
        $numMatch = Get-ChildItem -Path $KBPath -Filter $numPattern -Recurse -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Extension -in '.msu', '.cab' } |
                    Select-Object -First 1
        if ($numMatch) {
            $resolvedPath = $numMatch.FullName
            & $logMessage "Resolved $UpdateType path via numeric pattern ($numPattern): $resolvedPath"
            return $resolvedPath
        }
    }

    # Strategy 3: Try to find any MSU/CAB file if we have no other info
    # This is a last resort for single-file scenarios
    if (-not $resolvedPath) {
        $allUpdates = Get-ChildItem -Path $KBPath -Recurse -File -ErrorAction SilentlyContinue |
                      Where-Object { $_.Extension -in '.msu', '.cab' }

        if ($allUpdates -and $allUpdates.Count -eq 1) {
            $resolvedPath = $allUpdates[0].FullName
            & $logMessage "WARNING: Resolved $UpdateType path via single-file fallback: $resolvedPath"
            return $resolvedPath
        } elseif ($allUpdates -and $allUpdates.Count -gt 1) {
            & $logMessage "WARNING: Multiple update files found in $KBPath but could not match specific $UpdateType"
            & $logMessage "  Available files: $($allUpdates.Name -join ', ')"
        }
    }

    & $logMessage "ERROR: Could not resolve $UpdateType file path in $KBPath"
    if ($FileName) { & $logMessage "  Searched for filename: $FileName" }
    if ($KBArticleId) { & $logMessage "  Searched for KB article: $KBArticleId" }

    return $null
}

function Test-KBPathsValid {
    <#
    .SYNOPSIS
    Validates that all required KB update paths are valid before application

    .DESCRIPTION
    Pre-flight validation that checks all enabled update flags have corresponding
    valid file paths. Returns a hashtable with validation results and any errors.

    This prevents the "Cannot bind argument to parameter 'PackagePath' because it
    is an empty string" error by catching missing paths early with clear messages.

    .PARAMETER UpdateLatestCU
    Flag indicating if CU update is requested

    .PARAMETER CUPath
    Path to the Cumulative Update file

    .PARAMETER UpdatePreviewCU
    Flag indicating if Preview CU update is requested

    .PARAMETER CUPPath
    Path to the Preview Cumulative Update file

    .PARAMETER UpdateLatestNet
    Flag indicating if .NET update is requested

    .PARAMETER NETPath
    Path to the .NET Framework update file or folder

    .PARAMETER UpdateLatestMicrocode
    Flag indicating if Microcode update is requested

    .PARAMETER MicrocodePath
    Path to the Microcode update folder

    .PARAMETER SSURequired
    Flag indicating if SSU is required (for older Windows versions)

    .PARAMETER SSUFilePath
    Path to the Servicing Stack Update file

    .EXAMPLE
    $validation = Test-KBPathsValid -UpdateLatestCU $true -CUPath "C:\KB\update.msu" -UpdateLatestNet $false
    if (-not $validation.IsValid) { throw $validation.ErrorMessage }
    #>
    [CmdletBinding()]
    param(
        [bool]$UpdateLatestCU = $false,
        [string]$CUPath,

        [bool]$UpdatePreviewCU = $false,
        [string]$CUPPath,

        [bool]$UpdateLatestNet = $false,
        [string]$NETPath,

        [bool]$UpdateLatestMicrocode = $false,
        [string]$MicrocodePath,

        [bool]$SSURequired = $false,
        [string]$SSUFilePath
    )

    # Helper function for safe logging (WriteLog may not be available in standalone tests)
    $logMessage = {
        param([string]$msg)
        if (Get-Command WriteLog -ErrorAction SilentlyContinue) {
            WriteLog $msg
        } else {
            Write-Verbose $msg
        }
    }

    $errors = [System.Collections.Generic.List[string]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()

    # Validate CU path
    if ($UpdateLatestCU) {
        if ([string]::IsNullOrWhiteSpace($CUPath)) {
            $errors.Add("Cumulative Update (CU) is enabled but path is empty. The CU file may not have been downloaded or could not be located in the KB folder.")
        }
        elseif (-not (Test-Path -Path $CUPath -PathType Leaf)) {
            $errors.Add("Cumulative Update file not found at: $CUPath")
        }
        else {
            & $logMessage "Validated CU path: $CUPath"
        }
    }

    # Validate Preview CU path
    if ($UpdatePreviewCU) {
        if ([string]::IsNullOrWhiteSpace($CUPPath)) {
            $errors.Add("Preview Cumulative Update is enabled but path is empty. The Preview CU file may not have been downloaded or could not be located.")
        }
        elseif (-not (Test-Path -Path $CUPPath -PathType Leaf)) {
            $errors.Add("Preview Cumulative Update file not found at: $CUPPath")
        }
        else {
            & $logMessage "Validated Preview CU path: $CUPPath"
        }
    }

    # Validate .NET path (can be file or folder for LTSC)
    if ($UpdateLatestNet) {
        if ([string]::IsNullOrWhiteSpace($NETPath)) {
            $errors.Add(".NET Framework update is enabled but path is empty. The .NET update may not have been downloaded or could not be located.")
        }
        elseif (-not (Test-Path -Path $NETPath)) {
            $errors.Add(".NET Framework update not found at: $NETPath")
        }
        else {
            & $logMessage "Validated .NET path: $NETPath"
        }
    }

    # Validate Microcode path (folder)
    if ($UpdateLatestMicrocode) {
        if ([string]::IsNullOrWhiteSpace($MicrocodePath)) {
            $warnings.Add("Microcode update is enabled but path is empty. Microcode updates may be skipped.")
        }
        elseif (-not (Test-Path -Path $MicrocodePath)) {
            $warnings.Add("Microcode update folder not found at: $MicrocodePath")
        }
        else {
            & $logMessage "Validated Microcode path: $MicrocodePath"
        }
    }

    # Validate SSU path (if required for older Windows versions)
    if ($SSURequired) {
        if ([string]::IsNullOrWhiteSpace($SSUFilePath)) {
            $errors.Add("Servicing Stack Update (SSU) is required for this Windows version but path is empty.")
        }
        elseif (-not (Test-Path -Path $SSUFilePath -PathType Leaf)) {
            $errors.Add("Servicing Stack Update file not found at: $SSUFilePath")
        }
        else {
            & $logMessage "Validated SSU path: $SSUFilePath"
        }
    }

    # Build result
    $isValid = $errors.Count -eq 0
    $errorMessage = if ($errors.Count -gt 0) {
        "KB path validation failed with $($errors.Count) error(s):`n" + ($errors | ForEach-Object { "  - $_" }) -join "`n"
    } else { $null }

    # Log warnings
    foreach ($warning in $warnings) {
        & $logMessage "WARNING: $warning"
    }

    # Log errors
    foreach ($err in $errors) {
        & $logMessage "ERROR: $err"
    }

    return [PSCustomObject]@{
        IsValid = $isValid
        Errors = $errors
        Warnings = $warnings
        ErrorMessage = $errorMessage
    }
}

# Export module members
Export-ModuleMember -Function @(
    'Get-ProductsCab',
    'Get-WindowsESD',
    'Get-KBLink',
    'Get-UpdateFileInfo',
    'Save-KB',
    'Test-MountedImageDiskSpace',
    'Test-FileLocked',
    'Test-DISMServiceHealth',
    'Test-MountState',
    'Add-WindowsPackageWithRetry',
    'Add-WindowsPackageWithUnattend',
    'Resolve-KBFilePath',
    'Test-KBPathsValid'
)