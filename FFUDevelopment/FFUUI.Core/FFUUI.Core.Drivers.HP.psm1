<#
.SYNOPSIS
    Provides functions to retrieve HP model lists and download corresponding driver packs.
.DESCRIPTION
    This module contains the logic specific to handling HP drivers for the FFU Builder UI. It includes functions to:
    - Download and parse the HP PlatformList.xml to generate a list of supported HP computer models.
    - For a selected model, find the most appropriate driver pack based on the specified Windows release and version, with intelligent fallback logic.
    - Download the driver pack, extract all individual driver installers, and then extract the driver files from each installer.
    - Optionally, compress the final extracted drivers into a single WIM file for easier deployment.
    These functions are designed to be called by the main UI logic, often in parallel, to efficiently manage driver acquisition.
#>

# Function to get the list of HP models from the PlatformList.xml
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
    }

    # Sort the list alphabetically by Model name before returning
    return $modelList | Sort-Object -Property Model
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
    $sanitizedModelName = $modelName -replace '[\\/:"*?<>|]', '_'
    $hpDriversBaseFolder = Join-Path -Path $DriversFolder -ChildPath $make # Changed variable name for clarity
    $platformListXml = Join-Path -Path $hpDriversBaseFolder -ChildPath "PlatformList.xml"
    $modelSpecificFolder = Join-Path -Path $hpDriversBaseFolder -ChildPath $sanitizedModelName # Sanitize model name for folder path
    $driverRelativePath = Join-Path -Path $make -ChildPath $sanitizedModelName # Relative path for the driver folder
    $finalStatus = "" # Initialize final status
    $successState = $true # Assume success unless an operation fails
    
    if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status "Checking HP drivers for $modelName..." }
    
    try {
        # Check for existing drivers
        $existingDriver = Test-ExistingDriver -Make $make -Model $sanitizedModelName -DriversFolder $DriversFolder -Identifier $identifier -ProgressQueue $ProgressQueue
        if ($null -ne $existingDriver) {
            # The return object from Test-ExistingDriver uses 'Model' as the identifier key.
            # We need to return 'Identifier' for HP's logic.
            $existingDriver | Add-Member -MemberType NoteProperty -Name 'Identifier' -Value $identifier -Force
            $existingDriver.PSObject.Properties.Remove('Model')
            
            # Special handling for existing folders that need compression
            if ($CompressToWim -and $existingDriver.Status -eq 'Already downloaded') {
                $wimFilePath = Join-Path -Path $hpDriversBaseFolder -ChildPath "$($sanitizedModelName).wim"
                $sourceFolderPath = Join-Path -Path $hpDriversBaseFolder -ChildPath $sanitizedModelName
                WriteLog "Attempting compression of existing folder '$sourceFolderPath' to '$wimFilePath'."
                if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status "Compressing existing..." }
                try {
                    Compress-DriverFolderToWim -SourceFolderPath $sourceFolderPath -DestinationWimPath $wimFilePath -WimName $identifier -WimDescription "Drivers for $identifier" -ErrorAction Stop
                    $existingDriver.Status = "Already downloaded & Compressed"
                    $existingDriver.DriverPath = Join-Path -Path $make -ChildPath "$($sanitizedModelName).wim"
                    $existingDriver.Success = $true
                    WriteLog "Successfully compressed existing drivers for $identifier to $wimFilePath."
                }
                catch {
                    WriteLog "Error compressing existing drivers for $($identifier): $($_.Exception.Message)"
                    $existingDriver.Status = "Already downloaded (Compression failed)"
                    $existingDriver.Success = $false
                }
                if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $existingDriver.Status }
            }

            return $existingDriver
        }

        # If folder does not exist, proceed with download and extraction
        WriteLog "HP drivers for '$identifier' not found locally. Starting download process..."
        if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status "Downloading..." }

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
                $driverRelativePath = Join-Path -Path $make -ChildPath "$($identifier).wim" # Update relative path to the WIM
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
        $driverRelativePath = $null # Ensure path is null on error
        if (Test-Path -Path $modelSpecificFolder -PathType Container) {
            WriteLog "Attempting to remove partially created folder $modelSpecificFolder due to error."
            Remove-Item -Path $modelSpecificFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
            
    if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $finalStatus }
    return [PSCustomObject]@{ Identifier = $identifier; Status = $finalStatus; Success = $successState; DriverPath = $driverRelativePath }
}

Export-ModuleMember -Function *