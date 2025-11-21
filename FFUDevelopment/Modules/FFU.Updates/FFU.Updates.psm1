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

#Requires -Version 5.1

function Get-ProductsCab {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutFile,
        [Parameter(Mandatory = $true)]
        [ValidateSet('x64', 'arm64')]
        [string]$Architecture,
        [Parameter(Mandatory = $true)]
        [string]$BuildVersion
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
    Invoke-WebRequest -Uri $downloadUrl -OutFile $OutFile -Headers $downloadHeaders -UserAgent $UserAgent

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
        [string]$MediaType
    )
    WriteLog "Downloading Windows $WindowsRelease ESD file"
    WriteLog "Windows Architecture: $WindowsArch"
    WriteLog "Windows Language: $WindowsLang"
    WriteLog "Windows Media Type: $MediaType"

    $cabFilePath = Join-Path $PSScriptRoot "tempCabFile.cab"
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
            Get-ProductsCab -OutFile $cabFilePath -Architecture $cabArchitecture -BuildVersion $buildVersion | Out-Null
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
    $xmlFilePath = Join-Path $PSScriptRoot "products.xml"
    Invoke-Process Expand "-F:*.xml $cabFilePath $xmlFilePath" | Out-Null
    WriteLog "Products XML extracted"

    # Load XML content
    [xml]$xmlContent = Get-Content -Path $xmlFilePath

    # Define the client type to look for in the FilePath
    $clientType = if ($MediaType -eq 'consumer') { 'CLIENTCONSUMER' } else { 'CLIENTBUSINESS' }

    # Find FilePath values based on WindowsArch, WindowsLang, and MediaType
    foreach ($file in $xmlContent.MCT.Catalogs.Catalog.PublishedMedia.Files.File) {
        if ($file.Architecture -eq $WindowsArch -and $file.LanguageCode -eq $WindowsLang -and $file.FilePath -like "*$clientType*") {
            $esdFilePath = Join-Path $PSScriptRoot (Split-Path $file.FilePath -Leaf)
            #Download if ESD file doesn't already exist
            If (-not (Test-Path $esdFilePath)) {
                WriteLog "Downloading $($file.filePath) to $esdFIlePath"
                $OriginalVerbosePreference = $VerbosePreference
                $VerbosePreference = 'SilentlyContinue'
                Mark-DownloadInProgress -FFUDevelopmentPath $FFUDevelopmentPath -TargetPath $esdFilePath
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
                Remove-Item -Path $cabFilePath -Force
                Remove-Item -Path $xmlFilePath -Force
                WriteLog "Cleanup done"
            }
            return $esdFilePath
        }
    }
}

function Get-KBLink {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )
    $OriginalVerbosePreference = $VerbosePreference
    $VerbosePreference = 'SilentlyContinue'
    $results = Invoke-WebRequest -Uri "http://www.catalog.update.microsoft.com/Search.aspx?q=$Name" -Headers $Headers -UserAgent $UserAgent
    $VerbosePreference = $OriginalVerbosePreference

    # Extract the first KB article ID from the HTML content and store it globally
    # Edge and Defender do not have KB article IDs
    if ($Name -notmatch 'Defender|Edge') {
        if ($results.Content -match '>\s*([^\(<]+)\(KB(\d+)\)(?:\s*\([^)]+\))*\s*<') {
            $kbArticleID = "KB$($matches[2])"
            $global:LastKBArticleID = $kbArticleID
            WriteLog "Found KB article ID: $kbArticleID"
        }
        else {
            WriteLog "No KB article ID found in search results."
            $global:LastKBArticleID = $null
        }
    }

    $kbids = $results.InputFields |
    Where-Object { $_.type -eq 'Button' -and $_.Value -eq 'Download' } |
    Select-Object -ExpandProperty  ID

    if (-not $kbids) {
        Write-Warning -Message "No results found for $Name"
        return
    }

    $guids = $results.Links |
    Where-Object ID -match '_link' |
    Where-Object { $_.OuterHTML -match ( "(?=.*" + ( $Filter -join ")(?=.*" ) + ")" ) } |
    Select-Object -First 1 |
    ForEach-Object { $_.id.replace('_link', '') } |
    Where-Object { $_ -in $kbids }

    if (-not $guids) {
        Write-Warning -Message "No file found for $Name"
        return
    }

    foreach ($guid in $guids) {
        # Write-Verbose -Message "Downloading information for $guid"
        $post = @{ size = 0; updateID = $guid; uidInfo = $guid } | ConvertTo-Json -Compress
        $body = @{ updateIDs = "[$post]" }
        $OriginalVerbosePreference = $VerbosePreference
        $VerbosePreference = 'SilentlyContinue'
        $links = Invoke-WebRequest -Uri 'https://www.catalog.update.microsoft.com/DownloadDialog.aspx' -Method Post -Body $body -Headers $Headers -UserAgent $UserAgent |
        Select-Object -ExpandProperty Content |
        Select-String -AllMatches -Pattern "http[s]?://[^']*\.microsoft\.com/[^']*|http[s]?://[^']*\.windowsupdate\.com/[^']*" |
        Select-Object -Unique
        $VerbosePreference = $OriginalVerbosePreference

        foreach ($link in $links) {
            $link.matches.value
            #Filter out cab files
            # #if ($link -notmatch '\.cab') {
            #     $link.matches.value
            # }

        }
    }
}

function Get-UpdateFileInfo {
    [CmdletBinding()]
    param(
        [string[]]$Name
    )
    $updateFileInfos = [System.Collections.Generic.List[pscustomobject]]::new()

    foreach ($kb in $Name) {
        $links = Get-KBLink -Name $kb
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
                        })
                }
            }
        }
    }
    return $updateFileInfos
}

function Save-KB {
    [CmdletBinding()]
    param(
        [string[]]$Name,
        [string]$Path
    )
    foreach ($kb in $name) {
        $links = Get-KBLink -Name $kb
        foreach ($link in $links) {
            # if (!($link -match 'x64' -or $link -match 'amd64' -or $link -match 'x86' -or $link -match 'arm64')) {
            #     WriteLog "No architecture found in $link, skipping"
            #     continue
            # }

            if ($link -match 'x64' -or $link -match 'amd64') {
                if ($WindowsArch -eq 'x64') {
                    Writelog "Downloading $link for $WindowsArch to $Path"
                    Start-BitsTransferWithRetry -Source $link -Destination $Path | Out-Null
                    $fileName = ($link -split '/')[-1]
                    Writelog "Returning $fileName"
                    return $fileName
                }

            }
            elseif ($link -match 'arm64') {
                if ($WindowsArch -eq 'arm64') {
                    Writelog "Downloading $Link for $WindowsArch to $Path"
                    Start-BitsTransferWithRetry -Source $link -Destination $Path | Out-Null
                    $fileName = ($link -split '/')[-1]
                    Writelog "Returning $fileName"
                    return $fileName
                }
            }
            elseif ($link -match 'x86') {
                if ($WindowsArch -eq 'x86') {
                    Writelog "Downloading $link for $WindowsArch to $Path"
                    Start-BitsTransferWithRetry -Source $link -Destination $Path | Out-Null
                    $fileName = ($link -split '/')[-1]
                    Writelog "Returning $fileName"
                    return $fileName
                }

            }
            else {
                WriteLog "No architecture found in $link"

                #If no architecture is found, download the file and run it through Get-PEArchitecture to determine the architecture
                Writelog "Downloading $link to $Path and analyzing file for architecture"
                Start-BitsTransferWithRetry -Source $link -Destination $Path | Out-Null

                #Take the file and run it through Get-PEArchitecture to determine the architecture
                $fileName = ($link -split '/')[-1]
                $filePath = Join-Path -Path $Path -ChildPath $fileName
                $arch = Get-PEArchitecture -FilePath $filePath
                Writelog "$fileName is $arch"
                #If the architecture matches $WindowsArch, keep the file, otherwise delete it
                if ($arch -eq $WindowsArch) {
                    Writelog "Architecture for $fileName matches $WindowsArch, keeping file"
                    return $fileName
                }
                else {
                    Writelog "Deleting $fileName, architecture does not match"
                    Remove-Item -Path $filePath -Force
                }
            }

        }
    }
    return $fileName
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

function Initialize-DISMService {
    <#
    .SYNOPSIS
    Ensures DISM service is fully initialized before applying packages

    .DESCRIPTION
    Performs a lightweight DISM operation to ensure the service is ready for package application.
    This prevents race conditions and service initialization failures.

    .PARAMETER MountPath
    The path to the mounted Windows image

    .EXAMPLE
    Initialize-DISMService -MountPath "W:\"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$MountPath
    )

    WriteLog "Initializing DISM service for mounted image..."

    try {
        # Perform a lightweight DISM operation to ensure service is ready
        # Use Get-WindowsEdition which works with mounted image paths
        $dismInfo = Get-WindowsEdition -Path $MountPath -ErrorAction Stop
        WriteLog "DISM service initialized. Image edition: $($dismInfo.Edition)"
        return $true
    }
    catch {
        WriteLog "WARNING: DISM service initialization check failed: $($_.Exception.Message)"
        WriteLog "Waiting 10 seconds for DISM service to stabilize..."
        Start-Sleep -Seconds 10

        try {
            $dismInfo = Get-WindowsEdition -Path $MountPath -ErrorAction Stop
            WriteLog "DISM service initialized after retry. Image edition: $($dismInfo.Edition)"
            return $true
        }
        catch {
            WriteLog "ERROR: DISM service failed to initialize after retry"
            return $false
        }
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
        [int]$MaxRetries = 2,

        [Parameter()]
        [int]$RetryDelaySeconds = 30
    )

    $packageName = Split-Path $PackagePath -Leaf
    $attempt = 0
    $success = $false

    while (-not $success -and $attempt -lt $MaxRetries) {
        $attempt++

        try {
            if ($attempt -gt 1) {
                WriteLog "Retry attempt $attempt of $MaxRetries for package: $packageName"
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

        $extractPath = Join-Path $env:TEMP "MSU_Extract_$(Get-Date -Format 'yyyyMMddHHmmss')"
        $unattendExtracted = $false

        try {
            # Create extraction directory
            New-Item -Path $extractPath -ItemType Directory -Force | Out-Null
            WriteLog "Extracting MSU package to check for unattend.xml: $extractPath"

            # Extract MSU package using expand.exe with enhanced error handling
            $expandArgs = @(
                '-F:*',
                "`"$PackagePath`"",
                "`"$extractPath`""
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

            # Now apply the package with DISM
            WriteLog "Applying package with Add-WindowsPackage"
            Add-WindowsPackage -Path $Path -PackagePath $PackagePath | Out-Null
            WriteLog "Package $packageName applied successfully"

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

# Export module members
Export-ModuleMember -Function @(
    'Get-ProductsCab',
    'Get-WindowsESD',
    'Get-KBLink',
    'Get-UpdateFileInfo',
    'Save-KB',
    'Test-MountedImageDiskSpace',
    'Initialize-DISMService',
    'Add-WindowsPackageWithRetry',
    'Add-WindowsPackageWithUnattend'
)