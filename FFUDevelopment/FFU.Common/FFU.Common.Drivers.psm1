# FFU Common Drivers Module
# Contains shared functions related to driver handling.

# --------------------------------------------------------------------------
# SECTION: Driver Compression Function
# --------------------------------------------------------------------------

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
        [string]$WimDescription # Optional, defaults to folder name
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
            WriteLog "Removing source driver folder: $SourceFolderPath"
            try {
                Remove-Item -Path $SourceFolderPath -Recurse -Force -ErrorAction Stop
                WriteLog "Successfully removed source folder '$SourceFolderPath'."
            }
            catch {
                WriteLog "Warning: Failed to remove source folder '$SourceFolderPath'. Error: $($_.Exception.Message)"
                # Do not fail the whole operation, just log a warning.
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
                $mappingList.AddRange($existingJson)
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
# SECTION: Module Export
# --------------------------------------------------------------------------

Export-ModuleMember -Function Compress-DriverFolderToWim, Update-DriverMappingJson