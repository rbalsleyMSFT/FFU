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

    foreach ($driver in $DownloadedDrivers) {
        # Skip if any required property is missing or null
        if (-not $driver.PSObject.Properties['Make'] -or -not $driver.PSObject.Properties['Model'] -or -not $driver.PSObject.Properties['DriverPath'] -or [string]::IsNullOrWhiteSpace($driver.DriverPath)) {
            WriteLog "Skipping driver entry due to missing or empty Make, Model, or DriverPath. Details: $(($driver | ConvertTo-Json -Compress -Depth 3))"
            continue
        }

        # Find existing entry
        $existingEntry = $mappingList | Where-Object { $_.Manufacturer -eq $driver.Make -and $_.Model -eq $driver.Model } | Select-Object -First 1

        if ($null -ne $existingEntry) {
            # Update existing entry if the path is different
            if ($existingEntry.DriverPath -ne $driver.DriverPath) {
                WriteLog "Updating driver path for '$($driver.Make) - $($driver.Model)' from '$($existingEntry.DriverPath)' to '$($driver.DriverPath)'."
                $existingEntry.DriverPath = $driver.DriverPath
                $updatedCount++
            }
        }
        else {
            # Add new entry
            $newEntry = [PSCustomObject]@{
                Manufacturer = $driver.Make
                Model        = $driver.Model
                DriverPath   = $driver.DriverPath
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

    # Path to Edge
    $edgeExe = "$Env:ProgramFiles (x86)\Microsoft\Edge\Application\msedge.exe"

    # Any free port works. 9222 is common.
    $port = 9222
    $uri = 'https://psref.lenovo.com'

    # Headless run with remote debugging.
    $flags = "--headless=new --disable-gpu --remote-debugging-port=$port $uri"
    $edge = Start-Process -FilePath $edgeExe -ArgumentList $flags -PassThru
    Writelog "Edge process started with PID: $($edge.Id)."

    # Wait a short moment so the target appears.
    Start-Sleep -Seconds 3

    # Find the first page target.
    $targets = Invoke-RestMethod "http://localhost:$port/json"
    $wsUrl = ($targets | Where-Object type -eq 'page')[0].webSocketDebuggerUrl

    # Connect to that WebSocket.
    $socket = [System.Net.WebSockets.ClientWebSocket]::new()
    $socket.ConnectAsync($wsUrl, [Threading.CancellationToken]::None).Wait()

    # Helper to send a DevTools command.
    function Send-DevToolsCommand {
        param([int]$id, [string]$method, [hashtable]$params = @{})
        $cmd = @{ id = $id; method = $method; params = $params } |
        ConvertTo-Json -Compress
        $data = [Text.Encoding]::UTF8.GetBytes($cmd)
        $socket.SendAsync([ArraySegment[byte]]$data, 'Text', $true,
            [Threading.CancellationToken]::None).Wait()
    }

    # Ask the page to return localStorage['asut'].
    Send-DevToolsCommand -id 1 -method 'Runtime.evaluate' -params @{
        expression = "localStorage.getItem('asut')"
    }

    # Receive frames until the whole message arrives.
    $ms = New-Object System.IO.MemoryStream
    $buf = New-Object byte[] 8192
    do {
        $seg = [ArraySegment[byte]]::new($buf)
        $res = $socket.ReceiveAsync($seg,
            [Threading.CancellationToken]::None).Result
        $ms.Write($buf, 0, $res.Count)
    } until ($res.EndOfMessage)

    $ms.Position = 0
    $json = ([System.IO.StreamReader]::new($ms, [Text.Encoding]::UTF8)).ReadToEnd() |
    ConvertFrom-Json

    $token = $json.result.result.value
    # Concatenate the token value with X-PSREF-USER-TOKEN=
    $token = "X-PSREF-USER-TOKEN=$token"
    WriteLog "Retrieved Lenovo PSREF token: $token"

    # Clean up.
    $socket.Dispose()

    if ($null -ne $socket) {
        $socket.Dispose()
    }

    # Find the PID listening on the debugging port for reliable termination.
    $listeningPid = $null
    try {
        # Find the process listening on the specific port. The regex now looks for the local address and port, followed by anything, then LISTENING.
        # Dots are escaped for literal matching.
        $netstatOutput = netstat -ano -p TCP | Where-Object { $_ -match "127\.0\.0\.1:$port.*LISTENING" }
        if ($netstatOutput) {
            # The last number in the line is the PID
            $listeningPid = ($netstatOutput -split '\s+')[-1]
            WriteLog "Found Edge process PID $listeningPid listening on port $port. This is the process we will terminate."
        }
        else {
            WriteLog "Could not find any process listening on port $port."
        }
    }
    catch {
        WriteLog "Could not run netstat to find listening PID. Error: $($_.Exception.Message)"
    }

    # Determine the correct PID to kill. Prioritize the one found via netstat.
    $pidToKill = $null
    if ($listeningPid) {
        $pidToKill = $listeningPid
    }
    elseif ($null -ne $edgeProcess -and -not $edgeProcess.HasExited) {
        $pidToKill = $edgeProcess.Id
        WriteLog "Could not find listening process via netstat. Falling back to initial Edge process PID $($pidToKill) for termination."
    }

    if ($pidToKill) {
        WriteLog "Attempting to terminate Edge process tree with PID: $pidToKill"
        try {
            taskkill /PID $pidToKill /T /F | Out-Null
            WriteLog "Successfully issued termination command for Edge process tree with PID: $pidToKill."
        }
        catch {
            WriteLog "Failed to terminate Edge process tree with PID: $pidToKill. It may have already closed. Error: $($_.Exception.Message)"
        }
    }
    else {
        WriteLog "No active Edge process found to terminate."
    }

    return $token
}


# --------------------------------------------------------------------------
# SECTION: Module Export
# --------------------------------------------------------------------------

Export-ModuleMember -Function Compress-DriverFolderToWim, Update-DriverMappingJson, Test-ExistingDriver, Get-LenovoPSREFToken