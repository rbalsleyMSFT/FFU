<#
.SYNOPSIS
    Provides common functions for driver management, including compression, mapping, and existence checks.

.DESCRIPTION
    The FFU.Common.Drivers module contains a set of shared functions used across the FFU project for handling driver packages.
    This includes compressing driver folders into WIM files for efficient storage and deployment, maintaining a JSON-based mapping
    of downloaded drivers to their respective makes and models, and checking for the pre-existence of driver packages to avoid
    redundant downloads.
#>
function Compress-DriverFolderToWim {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -Path $_ -PathType Container })]
        [string]$SourceFolderPath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationWimPath,

        [Parameter()]
        [string]$WimName, # Optional, defaults to folder name

        [Parameter()]
        [string]$WimDescription, # Optional, defaults to folder name

        [Parameter()]
        [bool]$PreserveSource = $false # When $true, do not delete source folder; create marker for deferred cleanup
    )

    WriteLog "Starting compression of folder '$SourceFolderPath' to '$DestinationWimPath'."

    # Default WIM Name and Description to the source folder name if not provided
    $sourceFolderName = Split-Path -Path $SourceFolderPath -Leaf
    if ([string]::IsNullOrWhiteSpace($WimName)) {
        $WimName = $sourceFolderName
        WriteLog "WIM Name not provided, defaulting to source folder name: '$WimName'."
    }
    if ([string]::IsNullOrWhiteSpace($WimDescription)) {
        $WimDescription = $sourceFolderName
        WriteLog "WIM Description not provided, defaulting to source folder name: '$WimDescription'."
    }

    # Ensure destination directory exists
    $destinationDir = Split-Path -Path $DestinationWimPath -Parent
    if (-not (Test-Path -Path $destinationDir -PathType Container)) {
        WriteLog "Creating destination directory: $destinationDir"
        try {
            New-Item -Path $destinationDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        catch {
            WriteLog "Failed to create destination directory '$destinationDir': $($_.Exception.Message)"
            return $false # Indicate failure
        }
    }

    if ($PSCmdlet.ShouldProcess("Folder '$SourceFolderPath'", "Compress to WIM '$DestinationWimPath'")) {
        try {
            # Construct arguments for dism.exe
            $dismArgs = "/Capture-Image /ImageFile:`"$DestinationWimPath`" /CaptureDir:`"$SourceFolderPath`" /Name:`"$WimName`" /Description:`"$WimDescription`" /Compress:Max /CheckIntegrity /Quiet"
            
            WriteLog "Executing dism.exe via Invoke-Process with arguments:"
            WriteLog "dism.exe $dismArgs"

            # Call Invoke-Process (assumed to be available from FFUUI.Core.psm1 or another imported module)
            # Invoke-Process is expected to throw an exception for non-zero exit codes.
            Invoke-Process -FilePath "dism.exe" -ArgumentList $dismArgs -Wait $true
            
            WriteLog "Successfully compressed '$SourceFolderPath' to '$DestinationWimPath' using dism.exe."
            
            # Remove the source folder after successful compression
            if ($PreserveSource) {
                WriteLog "Preserving source driver folder for deferred WinPE driver harvesting: $SourceFolderPath"
                try {
                    $markerFile = Join-Path -Path $SourceFolderPath -ChildPath '__PreservedForPEDrivers.txt'
                    if (-not (Test-Path -Path $markerFile -PathType Leaf)) {
                        New-Item -Path $markerFile -ItemType File -Force | Out-Null
                        WriteLog "Created preservation marker file: $markerFile"
                    }
                }
                catch {
                    WriteLog "Warning: Failed to create preservation marker in $SourceFolderPath. Error: $($_.Exception.Message)"
                }
            }
            else {
                WriteLog "Removing source driver folder: $SourceFolderPath"
                try {
                    Remove-Item -Path $SourceFolderPath -Recurse -Force -ErrorAction Stop
                    WriteLog "Successfully removed source folder '$SourceFolderPath'."
                }
                catch {
                    WriteLog "Warning: Failed to remove source folder '$SourceFolderPath'. Error: $($_.Exception.Message)"
                    # Do not fail the whole operation, just log a warning.
                }
            }

            return $true # Indicate success
        }
        catch {
            WriteLog "Failed to compress folder '$SourceFolderPath' to WIM '$DestinationWimPath' using dism.exe."
            WriteLog "Error details: $($_.Exception.Message)"
            # Check if the error message contains details about the DISM log (dism.exe output might be in the exception)
            if ($_.Exception.Message -match 'DISM log file can be found at (.*)') {
                $dismLogPath = $matches[1].Trim()
                WriteLog "Check the DISM log for more details: $dismLogPath"
            }
            return $false # Indicate failure
        }
    }
    else {
        WriteLog "Compression operation skipped due to -WhatIf."
        return $false # Indicate skipped operation
    }
}

# --------------------------------------------------------------------------
# SECTION: Driver Mapping Function
# --------------------------------------------------------------------------

function Update-DriverMappingJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$DownloadedDrivers, # Array of PSCustomObjects with Make, Model, DriverPath

        [Parameter(Mandatory = $true)]
        [string]$DriversFolder # Base drivers folder (e.g., C:\FFUDevelopment\Drivers)
    )

    $mappingFilePath = Join-Path -Path $DriversFolder -ChildPath "DriverMapping.json"
    WriteLog "Updating driver mapping file at: $mappingFilePath"

    # Load existing mapping file or create a new list
    $mappingList = [System.Collections.Generic.List[PSCustomObject]]::new()
    if (Test-Path -Path $mappingFilePath -PathType Leaf) {
        try {
            $existingJson = Get-Content -Path $mappingFilePath -Raw | ConvertFrom-Json
            # Ensure it's a collection before adding to the list
            if ($existingJson -is [array]) {
                # Iterate through the array to avoid type conversion issues with AddRange
                foreach ($item in $existingJson) {
                    $mappingList.Add($item)
                }
            }
            else {
                $mappingList.Add($existingJson)
            }
            WriteLog "Loaded $($mappingList.Count) existing entries from $mappingFilePath"
        }
        catch {
            WriteLog "Warning: Could not read or parse existing DriverMapping.json. A new file will be created. Error: $($_.Exception.Message)"
        }
    }

    $updatedCount = 0
    $addedCount = 0

    $hpSystemIdCache = @{}
    $normalizeHpName = {
        param([string]$text)

        if ([string]::IsNullOrWhiteSpace($text)) {
            return $null
        }

        return ([regex]::Replace($text.ToLowerInvariant(), '[^a-z0-9]', ''))
    }
    $getHpSystemId = {
        param([string]$modelName)

        if ([string]::IsNullOrWhiteSpace($modelName)) {
            return $null
        }

        if ($hpSystemIdCache.ContainsKey($modelName)) {
            return $hpSystemIdCache[$modelName]
        }

        $hpFolder = Join-Path -Path $DriversFolder -ChildPath 'HP'
        if (-not (Test-Path -Path $hpFolder -PathType Container)) {
            $hpSystemIdCache[$modelName] = $null
            return $null
        }

        $platformListXml = Join-Path -Path $hpFolder -ChildPath 'PlatformList.xml'
        $platformListCab = Join-Path -Path $hpFolder -ChildPath 'platformList.cab'
        if (-not (Test-Path -Path $platformListXml -PathType Leaf)) {
            try {
                WriteLog "Attempting to refresh HP PlatformList.xml for SystemID lookup."
                Start-BitsTransferWithRetry -Source 'https://hpia.hpcloud.hp.com/ref/platformList.cab' -Destination $platformListCab -ErrorAction Stop
                if (Test-Path -Path $platformListXml) { Remove-Item -Path $platformListXml -Force -ErrorAction SilentlyContinue }
                Invoke-Process -FilePath "expand.exe" -ArgumentList @("`"$platformListCab`"", "`"$platformListXml`"") -ErrorAction Stop | Out-Null
                if (Test-Path -Path $platformListCab) { Remove-Item -Path $platformListCab -Force -ErrorAction SilentlyContinue }
            }
            catch {
                WriteLog "Failed to refresh HP PlatformList.xml: $($_.Exception.Message)"
                $hpSystemIdCache[$modelName] = $null
                return $null
            }
        }

        try {
            [xml]$platformListContent = Get-Content -Path $platformListXml -Raw -Encoding UTF8 -ErrorAction Stop

            $targetName = $modelName.Trim()
            $normalizedTarget = & $normalizeHpName $targetName

            $modelMatch = $platformListContent.ImagePal.Platform | Where-Object {
                [string]::Equals($_.ProductName.'#text'.Trim(), $targetName, [System.StringComparison]::OrdinalIgnoreCase)
            } | Select-Object -First 1

            if (-not $modelMatch -and $normalizedTarget) {
                $modelMatch = $platformListContent.ImagePal.Platform | Where-Object {
                    $candidateName = $_.ProductName.'#text'
                    $normalizedCandidate = & $normalizeHpName $candidateName
                    $normalizedCandidate -eq $normalizedTarget
                } | Select-Object -First 1
            }

            if (-not $modelMatch -and $normalizedTarget) {
                $modelMatch = $platformListContent.ImagePal.Platform | Where-Object {
                    $candidateName = $_.ProductName.'#text'
                    $normalizedCandidate = & $normalizeHpName $candidateName
                    ($normalizedCandidate -like "*$normalizedTarget*") -or ($normalizedTarget -like "*$normalizedCandidate*")
                } | Select-Object -First 1
            }

            if ($modelMatch -and -not [string]::IsNullOrWhiteSpace($modelMatch.SystemID)) {
                $resolvedId = $modelMatch.SystemID.Trim().ToUpperInvariant()
                $hpSystemIdCache[$modelName] = $resolvedId
                return $resolvedId
            }
            else {
                WriteLog "HP SystemId lookup: no match found in PlatformList.xml for model '$modelName'."
            }
        }
        catch {
            WriteLog "Failed to parse HP PlatformList.xml for model '$modelName': $($_.Exception.Message)"
        }

        $hpSystemIdCache[$modelName] = $null
        return $null
    }

    foreach ($driver in $DownloadedDrivers) {
        if (-not $driver.PSObject.Properties['Make'] -or -not $driver.PSObject.Properties['Model'] -or -not $driver.PSObject.Properties['DriverPath'] -or [string]::IsNullOrWhiteSpace($driver.DriverPath)) {
            WriteLog "Skipping driver entry due to missing or empty Make, Model, or DriverPath. Details: $(($driver | ConvertTo-Json -Compress -Depth 3))"
            continue
        }

        $systemIdValue = $null
        $machineTypeValue = $null

        if ($driver.PSObject.Properties['SystemId'] -and -not [string]::IsNullOrWhiteSpace($driver.SystemId)) {
            $systemIdValue = $driver.SystemId.Trim().ToUpperInvariant()
        }
        if ($driver.PSObject.Properties['MachineType'] -and -not [string]::IsNullOrWhiteSpace($driver.MachineType)) {
            $machineTypeValue = $driver.MachineType.Trim()
        }

        switch ($driver.Make) {
            'Dell' {
                if (-not $systemIdValue -and $driver.Model -match '\(([^)]+)\)\s*$') {
                    $systemIdValue = $matches[1].Trim().ToUpperInvariant()
                }
            }
            'HP' {
                if (-not $systemIdValue) {
                    $systemIdValue = & $getHpSystemId $driver.Model
                }
            }
            'Lenovo' {
                if (-not $machineTypeValue -and $driver.Model -match '\(([^)]+)\)\s*$') {
                    $machineTypeValue = $matches[1].Trim()
                }
            }
        }

        $existingEntry = $mappingList | Where-Object { $_.Manufacturer -eq $driver.Make -and $_.Model -eq $driver.Model } | Select-Object -First 1

        if ($null -ne $existingEntry) {
            $entryUpdated = $false
            if ($existingEntry.DriverPath -ne $driver.DriverPath) {
                WriteLog "Updating driver path for '$($driver.Make) - $($driver.Model)' from '$($existingEntry.DriverPath)' to '$($driver.DriverPath)'."
                $existingEntry.DriverPath = $driver.DriverPath
                $entryUpdated = $true
            }

            if ($driver.Make -in @('HP', 'Dell') -and -not [string]::IsNullOrWhiteSpace($systemIdValue)) {
                if ($existingEntry.PSObject.Properties['SystemId']) {
                    if ($existingEntry.SystemId -ne $systemIdValue) {
                        WriteLog "Updating SystemId for '$($driver.Make) - $($driver.Model)' to '$systemIdValue'."
                        $existingEntry.SystemId = $systemIdValue
                        $entryUpdated = $true
                    }
                }
                else {
                    WriteLog "Adding SystemId '$systemIdValue' for '$($driver.Make) - $($driver.Model)'."
                    $existingEntry | Add-Member -NotePropertyName SystemId -NotePropertyValue $systemIdValue
                    $entryUpdated = $true
                }
            }

            if ($driver.Make -eq 'Lenovo' -and -not [string]::IsNullOrWhiteSpace($machineTypeValue)) {
                if ($existingEntry.PSObject.Properties['MachineType']) {
                    if ($existingEntry.MachineType -ne $machineTypeValue) {
                        WriteLog "Updating MachineType for '$($driver.Make) - $($driver.Model)' to '$machineTypeValue'."
                        $existingEntry.MachineType = $machineTypeValue
                        $entryUpdated = $true
                    }
                }
                else {
                    WriteLog "Adding MachineType '$machineTypeValue' for '$($driver.Make) - $($driver.Model)'."
                    $existingEntry | Add-Member -NotePropertyName MachineType -NotePropertyValue $machineTypeValue
                    $entryUpdated = $true
                }
            }

            if ($entryUpdated) {
                $updatedCount++
            }
        }
        else {
            $newEntry = [PSCustomObject]@{
                Manufacturer = $driver.Make
                Model        = $driver.Model
                DriverPath   = $driver.DriverPath
            }

            if ($driver.Make -in @('HP', 'Dell') -and -not [string]::IsNullOrWhiteSpace($systemIdValue)) {
                $newEntry | Add-Member -NotePropertyName SystemId -NotePropertyValue $systemIdValue
            }
            if ($driver.Make -eq 'Lenovo' -and -not [string]::IsNullOrWhiteSpace($machineTypeValue)) {
                $newEntry | Add-Member -NotePropertyName MachineType -NotePropertyValue $machineTypeValue
            }

            $mappingList.Add($newEntry)
            WriteLog "Adding new mapping for '$($driver.Make) - $($driver.Model)' with path '$($driver.DriverPath)'."
            $addedCount++
        }
    }

    if ($updatedCount -gt 0 -or $addedCount -gt 0) {
        try {
            # Sort the list for consistency before saving
            $sortedList = $mappingList | Sort-Object -Property Manufacturer, Model
            $sortedList | ConvertTo-Json -Depth 5 | Set-Content -Path $mappingFilePath -Encoding UTF8
            WriteLog "Successfully saved DriverMapping.json with $addedCount new entries and $updatedCount updated entries."
        }
        catch {
            WriteLog "Error saving updated DriverMapping.json: $($_.Exception.Message)"
            throw "Failed to save driver mapping file."
        }
    }
    else {
        WriteLog "No changes needed for DriverMapping.json."
    }
}

# --------------------------------------------------------------------------
# SECTION: Driver Existence Check Function
# --------------------------------------------------------------------------
function Test-ExistingDriver {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Make,

        [Parameter(Mandatory = $true)]
        [string]$Model,

        [Parameter(Mandatory = $true)]
        [string]$DriversFolder,

        [Parameter(Mandatory = $true)]
        [string]$Identifier,

        [Parameter()]
        [System.Collections.Concurrent.ConcurrentQueue[hashtable]]$ProgressQueue = $null
    )

    $makeDriversPath = Join-Path -Path $DriversFolder -ChildPath $Make
    $modelPath = Join-Path -Path $makeDriversPath -ChildPath $Model
    $driverRelativePath = Join-Path -Path $Make -ChildPath $Model

    # Check for WIM file first
    $wimFilePath = Join-Path -Path $makeDriversPath -ChildPath "$($Model).wim"
    if (Test-Path -Path $wimFilePath -PathType Leaf) {
        $status = "Already downloaded (WIM)"
        WriteLog "Driver WIM for '$Identifier' already exists at '$wimFilePath'."
        if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $Identifier -Status $status }
        $wimRelativePath = Join-Path -Path $Make -ChildPath "$($Model).wim"
        return [PSCustomObject]@{
            Model      = $Identifier # Return original identifier
            Status     = $status
            Success    = $true
            DriverPath = $wimRelativePath
        }
    }

    # Check for existing driver folder
    if (Test-Path -Path $modelPath -PathType Container) {
        $folderSize = (Get-ChildItem -Path $modelPath -Recurse | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        if ($folderSize -gt 1MB) {
            $status = "Already downloaded"
            WriteLog "Drivers for '$Identifier' already exist in '$modelPath'."
            if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $Identifier -Status $status }
            return [PSCustomObject]@{
                Model      = $Identifier # Return original identifier
                Status     = $status
                Success    = $true
                DriverPath = $driverRelativePath
            }
        }
        else {
            WriteLog "Driver folder '$modelPath' for '$Identifier' exists but is empty or very small. Re-downloading."
        }
    }

    # If neither WIM nor a valid folder exists, return null
    return $null
}
function Get-LenovoPSREFToken {

    <# 
        .DESCRIPTION
        Retrieves the Lenovo PSREF token from the Edge browser's local storage.

        .NOTES

        Lenovo's PSREF site creates a cookie/token via javascript when navigating to the PSREF site. This cookie only needs
        to be retrieved once on a single machine, and every machine within the same network will be able to access the PSREF API. 

        Using Invoke-Webrequest with sessionvariable or websession doesn't work because the token is created by javascript.
        Using edge in headless mode with remote debugging enabled allows for the retrieval of the token via the DevTools protocol.

        You couldn't be more unhappy about this solution than I am, but it works.

        Why use PSREF and not catalogv2.xml? Catalogv2.xml doesn't include all models. PSREF provides an API that can be used to retrieve
        the friendly model and machine type information for both business and consumer models. Many EDU devices are deemed consumer. 

        System Update and other tools rely on the user to input machine type and model information, but finding the machine type is difficult for some.
        Our solution makes it easier to simply type the model name and you can match the machine type to the model name.

        If you have a better solution, please submit a PR or open a discussion on Github. Happy to consider alternatives. An easy way to test
        if your alternative works is to see if you can retrieve 100e, 300w, 500w, etc. These don't show up in catalogv2.xml, but they do in PSREF.
    #>

    $token = $null
    $socket = $null
    $edgeProcess = $null
    $tempProfile = $null
    $port = $null

    function Get-FreeLocalTcpPort {
        $listener = $null
        try {
            $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
            $listener.Start()
            $endpoint = [System.Net.IPEndPoint]$listener.LocalEndpoint
            return $endpoint.Port
        }
        finally {
            if ($null -ne $listener) {
                $listener.Stop()
            }
        }
    }

    function Get-EdgeDevToolsPageTarget {
        param(
            [Parameter(Mandatory = $true)][int]$Port,
            [int]$MaxAttempts = 20,
            [int]$DelayMilliseconds = 500,
            [string]$UrlContains
        )

        for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
            try {
                $targets = Invoke-RestMethod -Uri "http://localhost:$Port/json" -ErrorAction Stop
                if ($null -ne $targets) {
                    if ($targets -isnot [System.Array]) { $targets = @($targets) }
                    $pageTargets = $targets | Where-Object { $_.type -eq 'page' }
                    if (-not [string]::IsNullOrWhiteSpace($UrlContains)) {
                        $pageTargets = $pageTargets | Where-Object {
                            -not [string]::IsNullOrWhiteSpace($_.url) -and $_.url -like "*$UrlContains*"
                        }
                    }

                    $target = $pageTargets | Select-Object -First 1
                    if ($null -ne $target) {
                        return $target
                    }

                    WriteLog "DevTools endpoint on port $Port returned targets but no page matched the criteria (attempt $attempt of $MaxAttempts)."
                }
                else {
                    WriteLog "DevTools endpoint on port $Port returned no targets (attempt $attempt of $MaxAttempts)."
                }
            }
            catch {
                WriteLog "DevTools endpoint on port $Port not ready (attempt $attempt of $MaxAttempts). Error: $($_.Exception.Message)"
            }

            Start-Sleep -Milliseconds $DelayMilliseconds
        }

        throw "Edge DevTools endpoint on port $Port did not expose a matching page target after $MaxAttempts attempts."
    }

    try {
        $ffuDevelopmentRoot = Split-Path -Path $PSScriptRoot -Parent
        WriteLog "Derived FFUDevelopmentPath from module path: $ffuDevelopmentRoot"

        if ([string]::IsNullOrWhiteSpace($ffuDevelopmentRoot)) {
            throw "FFUDevelopmentPath could not be resolved. Unable to create Edge profile."
        }

        if (-not (Test-Path -Path $ffuDevelopmentRoot -PathType Container)) {
            throw "Resolved FFUDevelopmentPath '$ffuDevelopmentRoot' does not exist."
        }

        $tempProfile = Join-Path -Path $ffuDevelopmentRoot -ChildPath ("edge-psref-" + [guid]::NewGuid())
        WriteLog "Creating temporary Edge profile at $tempProfile."
        New-Item -ItemType Directory -Path $tempProfile -Force | Out-Null

        $edgeExe = "$Env:ProgramFiles (x86)\Microsoft\Edge\Application\msedge.exe"
        $uri = 'https://psref.lenovo.com'
        $port = Get-FreeLocalTcpPort
        WriteLog "Using Edge DevTools port $port for Lenovo PSREF token retrieval."

        $flags = "--headless=new --disable-gpu --remote-debugging-port=$port $uri --user-data-dir=`"$tempProfile`""
        $edgeProcess = Start-Process -FilePath $edgeExe -ArgumentList $flags -PassThru
        WriteLog "Edge process started with PID: $($edgeProcess.Id)."

        $pageTarget = Get-EdgeDevToolsPageTarget -Port $port -MaxAttempts 40 -DelayMilliseconds 500 -UrlContains 'psref.lenovo.com'
        if (-not [string]::IsNullOrWhiteSpace($pageTarget.url)) {
            WriteLog "Selected DevTools target URL: $($pageTarget.url)"
        }

        $wsUrl = $pageTarget.webSocketDebuggerUrl
        if ([string]::IsNullOrWhiteSpace($wsUrl)) {
            throw "Edge DevTools page target on port $port did not provide a WebSocket URL."
        }

        $socket = [System.Net.WebSockets.ClientWebSocket]::new()
        $socket.ConnectAsync($wsUrl, [Threading.CancellationToken]::None).Wait()

        function Send-DevToolsCommand {
            param([int]$id, [string]$method, [hashtable]$params = @{})
            $cmd = @{ id = $id; method = $method; params = $params } | ConvertTo-Json -Compress
            $data = [Text.Encoding]::UTF8.GetBytes($cmd)
            $socket.SendAsync([ArraySegment[byte]]$data, 'Text', $true, [Threading.CancellationToken]::None).Wait()
        }

        $buffer = New-Object byte[] 8192

        function Invoke-DevToolsValue {
            param(
                [Parameter(Mandatory = $true)][int]$CommandId,
                [Parameter(Mandatory = $true)][string]$Expression,
                [int]$MaxPolls = 25
            )

            Send-DevToolsCommand -id $CommandId -method 'Runtime.evaluate' -params @{
                expression    = $Expression
                returnByValue = $true
                awaitPromise  = $true
            }

            for ($poll = 1; $poll -le $MaxPolls; $poll++) {
                $localStream = $null
                try {
                    $localStream = New-Object System.IO.MemoryStream
                    do {
                        $segment = [ArraySegment[byte]]::new($buffer)
                        $result = $socket.ReceiveAsync($segment, [Threading.CancellationToken]::None).Result
                        $localStream.Write($buffer, 0, $result.Count)
                    } until ($result.EndOfMessage)

                    $jsonBytes = $localStream.ToArray()
                    $jsonText = [Text.Encoding]::UTF8.GetString($jsonBytes)
                    $previewPayload = $jsonText
                    if (-not [string]::IsNullOrEmpty($previewPayload) -and $previewPayload.Length -gt 500) {
                        $previewPayload = $previewPayload.Substring(0, 500) + '...'
                    }
                    WriteLog "DevTools eval payload (cmd $CommandId, poll $poll): $previewPayload"

                    $message = $null
                    try {
                        $message = $jsonText | ConvertFrom-Json
                    }
                    catch {
                        WriteLog "Failed to parse DevTools eval payload for command id $CommandId (poll $poll): $($_.Exception.Message)"
                        continue
                    }

                    if ($message.PSObject.Properties['id'] -and $message.id -eq $CommandId) {
                        if ($message.PSObject.Properties['error']) {
                            $errorMessage = $message.error.message
                            throw "Edge DevTools reported an error for expression '$Expression': $errorMessage"
                        }

                        if ($message.PSObject.Properties['result'] -and $message.result.PSObject.Properties['result']) {
                            $innerResult = $message.result.result
                            return [PSCustomObject]@{
                                Value   = $innerResult.value
                                Type    = $innerResult.type
                                Subtype = $innerResult.subtype
                            }
                        }

                        $serializedMessage = $message | ConvertTo-Json -Compress -Depth 5
                        WriteLog "DevTools response for command id $CommandId lacked result data. Message: $serializedMessage"
                        return $null
                    }

                    if ($message.PSObject.Properties['method']) {
                        WriteLog "Received DevTools event '$($message.method)' while waiting for command id $CommandId."
                    }
                    else {
                        WriteLog "Received DevTools message without id or method while waiting for command id $CommandId."
                    }
                }
                finally {
                    if ($null -ne $localStream) {
                        $localStream.Dispose()
                    }
                }
            }

            throw "No DevTools response received for command id $CommandId after $MaxPolls polls."
        }

        WriteLog "Waiting for PSREF page to initialize local storage context."
        Start-Sleep -Seconds 2

        $commandCounter = 1000
        $rawToken = $null
        $maxTokenAttempts = 12
        for ($attempt = 1; $attempt -le $maxTokenAttempts -and [string]::IsNullOrWhiteSpace($rawToken); $attempt++) {
            $commandCounter++
            $tokenResponse = Invoke-DevToolsValue -CommandId $commandCounter -Expression "window.localStorage?.getItem('asut')" -MaxPolls 25
            if ($null -ne $tokenResponse -and -not [string]::IsNullOrWhiteSpace($tokenResponse.Value)) {
                $rawToken = $tokenResponse.Value
                WriteLog "DevTools response for command id $commandCounter returned token length $($rawToken.Length)."
                break
            }

            WriteLog "Lenovo PSREF token not yet available (attempt $attempt of $maxTokenAttempts)."

            $commandCounter++
            $keysResponse = Invoke-DevToolsValue -CommandId $commandCounter -Expression "JSON.stringify(Object.keys(window.localStorage || {}))" -MaxPolls 10
            if ($null -ne $keysResponse -and -not [string]::IsNullOrWhiteSpace($keysResponse.Value)) {
                WriteLog "Current localStorage keys: $($keysResponse.Value)"
            }

            $commandCounter++
            $cookieResponse = Invoke-DevToolsValue -CommandId $commandCounter -Expression "document.cookie" -MaxPolls 10
            if ($null -ne $cookieResponse -and -not [string]::IsNullOrWhiteSpace($cookieResponse.Value)) {
                WriteLog "document.cookie contents: $($cookieResponse.Value)"
                $cookieEntry = ($cookieResponse.Value -split ';') | ForEach-Object { $_.Trim() } | Where-Object { $_ -like 'asut=*' } | Select-Object -First 1
                if ($cookieEntry) {
                    $rawToken = $cookieEntry.Substring($cookieEntry.IndexOf('=') + 1)
                    WriteLog "Extracted Lenovo PSREF token from cookies with length $($rawToken.Length)."
                    break
                }
            }

            Start-Sleep -Milliseconds 750
        }

        if ([string]::IsNullOrWhiteSpace($rawToken)) {
            throw "Received empty Lenovo PSREF token from Edge DevTools after $maxTokenAttempts attempts."
        }

        $token = "X-PSREF-USER-TOKEN=$rawToken"
        WriteLog "Retrieved Lenovo PSREF token: $token"
    }
    catch {
        WriteLog "Failed to retrieve Lenovo PSREF token. Error: $($_.Exception.Message)"
        throw
    }
    finally {
        if ($null -ne $socket) {
            try {
                $socket.Dispose()
                WriteLog "Edge DevTools WebSocket disposed."
            }
            catch {
                WriteLog "Error disposing Edge DevTools WebSocket: $($_.Exception.Message)"
            }
        }

        $listeningPid = $null
        if ($null -ne $port) {
            try {
                $netstatOutput = netstat -ano -p TCP | Where-Object { $_ -match "127\.0\.0\.1:$port.*LISTENING" }
                if ($netstatOutput) {
                    $listeningPid = ($netstatOutput -split '\s+')[-1]
                    WriteLog "Found Edge process PID $listeningPid listening on port $port."
                }
                else {
                    WriteLog "No process reported as listening on port $port."
                }
            }
            catch {
                WriteLog "Could not run netstat to find listening PID for port $port. Error: $($_.Exception.Message)"
            }
        }

        $pidToKill = $null
        if ($null -ne $listeningPid) {
            $pidToKill = $listeningPid
        }
        elseif ($null -ne $edgeProcess -and -not $edgeProcess.HasExited) {
            $pidToKill = $edgeProcess.Id
            WriteLog "Falling back to initial Edge process PID $pidToKill for termination."
        }

        if ($null -ne $pidToKill) {
            try {
                taskkill /PID $pidToKill /T /F | Out-Null
                WriteLog "Issued termination command for Edge process tree with PID: $pidToKill."
            }
            catch {
                WriteLog "Failed to terminate Edge process tree with PID: $pidToKill. Error: $($_.Exception.Message)"
            }
        }
        else {
            WriteLog "No active Edge process found to terminate."
        }

        if ($null -ne $edgeProcess) {
            try {
                $edgeProcess.WaitForExit(3000) | Out-Null
            }
            catch {
                WriteLog "Error while waiting for Edge process PID $($edgeProcess.Id) to exit: $($_.Exception.Message)"
            }
        }

        Start-Sleep -Milliseconds 250

        if (-not [string]::IsNullOrWhiteSpace($tempProfile) -and (Test-Path -Path $tempProfile -PathType Container)) {
            $maxRemoveAttempts = 5
            $originalProgressPreference = $ProgressPreference
            try {
                $ProgressPreference = 'SilentlyContinue'
                for ($removeAttempt = 1; $removeAttempt -le $maxRemoveAttempts; $removeAttempt++) {
                    try {
                        Remove-Item -Path $tempProfile -Recurse -Force -ErrorAction Stop
                        WriteLog "Removed temporary Edge profile at $tempProfile."
                        break
                    }
                    catch {
                        if ($removeAttempt -eq $maxRemoveAttempts) {
                            WriteLog "Failed to remove temporary Edge profile at $tempProfile after $maxRemoveAttempts attempts. Error: $($_.Exception.Message)"
                        }
                        else {
                            WriteLog "Temporary Edge profile still locked (attempt $removeAttempt of $maxRemoveAttempts). Retrying..."
                            Start-Sleep -Milliseconds 500
                        }
                    }
                }
            }
            finally {
                $ProgressPreference = $originalProgressPreference
            }
        }
    }

    return $token
}


# --------------------------------------------------------------------------
# SECTION: Module Export
# --------------------------------------------------------------------------

Export-ModuleMember -Function Compress-DriverFolderToWim, Update-DriverMappingJson, Test-ExistingDriver, Get-LenovoPSREFToken