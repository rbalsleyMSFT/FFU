# FFU Common Drivers Module
# Contains shared functions related to driver handling.

#Requires -Modules Dism

# # Import the common core module for logging and process invocation
# Import-Module "$PSScriptRoot\FFU.Common.Core.psm1"

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
# SECTION: Module Export
# --------------------------------------------------------------------------

Export-ModuleMember -Function Compress-DriverFolderToWim