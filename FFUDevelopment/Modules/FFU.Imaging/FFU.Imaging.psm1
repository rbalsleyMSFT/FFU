<#
.SYNOPSIS
    FFU Builder DISM and FFU Imaging Module

.DESCRIPTION
    DISM operations, VHDX management, partition creation, and FFU image
    generation for FFU Builder. Handles WIM extraction, disk partitioning,
    boot file configuration, Windows feature enablement, and FFU capture.

.NOTES
    Module: FFU.Imaging
    Version: 1.0.0
    Dependencies: FFU.Core
    Requires: Administrator privileges for DISM and disk operations
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

# Import constants module
using module ..\FFU.Constants\FFU.Constants.psm1

# Import dependencies
Import-Module "$PSScriptRoot\..\FFU.Core" -Force

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
        WriteLog "Waiting for DISM service to stabilize..."
        Start-Sleep -Seconds ([FFUConstants]::DISM_SERVICE_WAIT)

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

function Test-WimSourceAccessibility {
    <#
    .SYNOPSIS
    Validates that a WIM/ESD source file is accessible and its parent ISO (if any) is still mounted

    .DESCRIPTION
    Performs comprehensive validation to ensure a WIM file is accessible before starting
    long-running operations like Expand-WindowsImage. Checks file existence, readability,
    and validates that the parent ISO mount is still active if the WIM is on an ISO.

    This function helps prevent error 0x8007048F "The device is not connected" which occurs
    when an ISO mount becomes unavailable during Expand-WindowsImage operations.

    .PARAMETER WimPath
    Full path to the WIM or ESD file to validate

    .PARAMETER ISOPath
    Optional path to the source ISO file. If provided, validates the ISO is still mounted.

    .OUTPUTS
    PSCustomObject with properties:
    - IsAccessible: Boolean indicating if WIM is accessible
    - ISOIsMounted: Boolean indicating if ISO is mounted (null if no ISO provided)
    - DriveRoot: The drive root where WIM resides
    - ErrorMessage: Error details if not accessible

    .EXAMPLE
    $validation = Test-WimSourceAccessibility -WimPath "F:\sources\install.wim" -ISOPath "C:\ISOs\Win11.iso"
    if (-not $validation.IsAccessible) {
        throw "WIM source is not accessible: $($validation.ErrorMessage)"
    }

    .NOTES
    Should be called immediately before Expand-WindowsImage to minimize race condition window.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WimPath,

        [Parameter(Mandatory = $false)]
        [string]$ISOPath
    )

    $result = [PSCustomObject]@{
        IsAccessible = $false
        ISOIsMounted = $null
        DriveRoot = $null
        ErrorMessage = $null
        WimSizeBytes = 0
    }

    try {
        # Extract drive letter from WIM path
        $result.DriveRoot = Split-Path -Qualifier $WimPath

        # Check 1: Verify the drive/mount point exists
        if (-not (Test-Path $result.DriveRoot)) {
            $result.ErrorMessage = "Drive $($result.DriveRoot) is not accessible - mount point may have been released"
            return $result
        }

        # Check 2: Verify the WIM file exists
        if (-not (Test-Path $WimPath)) {
            $result.ErrorMessage = "WIM file not found at $WimPath - ISO may have been unmounted"
            return $result
        }

        # Check 3: Verify we can read the WIM file (not just that it exists)
        try {
            $fileInfo = Get-Item $WimPath -ErrorAction Stop
            $result.WimSizeBytes = $fileInfo.Length

            # Try to open the file for reading to verify it's truly accessible
            $stream = [System.IO.File]::Open($WimPath, 'Open', 'Read', 'Read')
            # Read first 1KB to verify file is readable
            $buffer = New-Object byte[] 1024
            $bytesRead = $stream.Read($buffer, 0, $buffer.Length)
            $stream.Close()
            $stream.Dispose()

            if ($bytesRead -eq 0 -and $fileInfo.Length -gt 0) {
                $result.ErrorMessage = "WIM file exists but could not be read - possible access issue"
                return $result
            }
        }
        catch {
            $result.ErrorMessage = "Cannot read WIM file: $($_.Exception.Message)"
            return $result
        }

        # Check 4: If ISO path provided, verify ISO is still mounted
        if ($ISOPath) {
            try {
                $diskImage = Get-DiskImage -ImagePath $ISOPath -ErrorAction Stop
                $result.ISOIsMounted = $diskImage.Attached

                if (-not $diskImage.Attached) {
                    $result.ErrorMessage = "ISO at $ISOPath is no longer mounted"
                    return $result
                }

                # Verify the mounted ISO's drive letter matches the WIM's drive
                $isoVolume = $diskImage | Get-Volume -ErrorAction SilentlyContinue
                if ($isoVolume) {
                    $expectedRoot = "$($isoVolume.DriveLetter):\"
                    $wimRoot = $result.DriveRoot + "\"
                    if ($expectedRoot -ne $wimRoot) {
                        WriteLog "WARNING: ISO mounted at $expectedRoot but WIM is at $wimRoot - drive letter may have changed"
                    }
                }
            }
            catch {
                $result.ErrorMessage = "Cannot verify ISO mount status: $($_.Exception.Message)"
                return $result
            }
        }

        # All checks passed
        $result.IsAccessible = $true
        return $result
    }
    catch {
        $result.ErrorMessage = "Unexpected error during WIM accessibility check: $($_.Exception.Message)"
        return $result
    }
}

function Invoke-ExpandWindowsImageWithRetry {
    <#
    .SYNOPSIS
    Expands Windows image with pre-validation, retry logic, and ISO re-mount capability

    .DESCRIPTION
    Wrapper around Expand-WindowsImage that adds robustness for long-running operations.
    Validates WIM source accessibility before starting, and can automatically re-mount
    the source ISO and retry if the operation fails with "device not connected" error.

    Addresses error 0x8007048F "The device is not connected" which occurs when ISO mounts
    become unavailable during the 3-5+ minute Expand-WindowsImage operation.

    .PARAMETER ImagePath
    Path to the WIM or ESD file

    .PARAMETER Index
    Image index to apply

    .PARAMETER ApplyPath
    Destination path (e.g., "W:\")

    .PARAMETER Compact
    Use CompactOS compression (not supported on Server SKUs)

    .PARAMETER ISOPath
    Optional path to source ISO file. Enables re-mount capability on failure.

    .PARAMETER MaxRetries
    Maximum number of retry attempts (default: 2)

    .EXAMPLE
    Invoke-ExpandWindowsImageWithRetry -ImagePath "F:\sources\install.wim" -Index 1 `
                                       -ApplyPath "W:\" -ISOPath "C:\ISOs\Win11.iso"

    .NOTES
    If ISOPath is not provided, retry will fail if the issue is ISO unmount.
    Always provide ISOPath when the WIM source is from an ISO.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ImagePath,

        [Parameter(Mandatory = $true)]
        [int]$Index,

        [Parameter(Mandatory = $true)]
        [string]$ApplyPath,

        [Parameter(Mandatory = $false)]
        [switch]$Compact,

        [Parameter(Mandatory = $false)]
        [string]$ISOPath,

        [Parameter(Mandatory = $false)]
        [int]$MaxRetries = 2
    )

    $attempt = 0
    $lastError = $null
    $success = $false
    $currentImagePath = $ImagePath

    while ($attempt -lt $MaxRetries -and -not $success) {
        $attempt++
        WriteLog "Expand-WindowsImage attempt $attempt of $MaxRetries..."

        # Pre-validation: Check WIM source accessibility
        WriteLog "Validating WIM source accessibility..."
        $validation = Test-WimSourceAccessibility -WimPath $currentImagePath -ISOPath $ISOPath

        if (-not $validation.IsAccessible) {
            WriteLog "WARNING: WIM source validation failed: $($validation.ErrorMessage)"

            if ($ISOPath -and $attempt -lt $MaxRetries) {
                WriteLog "Attempting to re-mount ISO and retry..."

                try {
                    # Dismount if partially mounted
                    try {
                        Dismount-DiskImage -ImagePath $ISOPath -ErrorAction SilentlyContinue
                    }
                    catch { }

                    Start-Sleep -Seconds 3

                    # Re-mount ISO
                    WriteLog "Re-mounting ISO: $ISOPath"
                    $mountResult = Mount-DiskImage -ImagePath $ISOPath -PassThru -ErrorAction Stop
                    $newDriveLetter = ($mountResult | Get-Volume).DriveLetter
                    $newSourcesFolder = "$newDriveLetter`:\sources\"

                    # Register cleanup for re-mounted ISO in case of failure
                    if (Get-Command Register-ISOCleanup -ErrorAction SilentlyContinue) {
                        $null = Register-ISOCleanup -ISOPath $ISOPath
                    }

                    # Find WIM in re-mounted ISO
                    $newWimPath = (Get-ChildItem "$newSourcesFolder\install.*" -ErrorAction Stop |
                                   Where-Object { $_.Name -match "install\.(wim|esd)" }).FullName

                    if ($newWimPath) {
                        WriteLog "ISO re-mounted successfully. New WIM path: $newWimPath"
                        $currentImagePath = $newWimPath
                        Start-Sleep -Seconds 2  # Allow mount to stabilize
                    }
                    else {
                        WriteLog "ERROR: Could not find WIM in re-mounted ISO"
                        $lastError = "ISO re-mount succeeded but WIM not found"
                        continue
                    }
                }
                catch {
                    WriteLog "ERROR: Failed to re-mount ISO: $($_.Exception.Message)"
                    $lastError = "ISO re-mount failed: $($_.Exception.Message)"
                    continue
                }
            }
            else {
                $lastError = $validation.ErrorMessage
                continue
            }
        }
        else {
            WriteLog "WIM source validated. Size: $([math]::Round($validation.WimSizeBytes / 1GB, 2)) GB"
        }

        # Perform the expansion
        try {
            WriteLog "Starting Expand-WindowsImage..."
            WriteLog "  Source: $currentImagePath"
            WriteLog "  Index: $Index"
            WriteLog "  Destination: $ApplyPath"
            WriteLog "  Compact: $Compact"

            $expandParams = @{
                ImagePath = $currentImagePath
                Index = $Index
                ApplyPath = $ApplyPath
                ErrorAction = 'Stop'
            }

            if ($Compact) {
                $expandResult = Expand-WindowsImage @expandParams -Compact
            }
            else {
                $expandResult = Expand-WindowsImage @expandParams
            }

            WriteLog "Expand-WindowsImage completed successfully"
            $success = $true
            return $expandResult
        }
        catch {
            $lastError = $_.Exception.Message
            $hresult = $_.Exception.HResult

            WriteLog "ERROR: Expand-WindowsImage failed: $lastError"
            WriteLog "HResult: $hresult (0x$($hresult.ToString('X8')))"

            # Check if this is a "device not connected" error
            $isDeviceDisconnected = ($hresult -eq -2147023729) -or  # 0x8007048F
                                    ($lastError -match "device.*not connected") -or
                                    ($lastError -match "0x8007048F")

            if ($isDeviceDisconnected) {
                WriteLog "Detected 'device not connected' error - ISO mount may have been released"

                if ($attempt -lt $MaxRetries) {
                    WriteLog "Will attempt to re-mount ISO and retry..."
                    Start-Sleep -Seconds 5
                }
            }
            elseif ($attempt -lt $MaxRetries) {
                WriteLog "Waiting before retry..."
                Start-Sleep -Seconds 10
            }
        }
    }

    # All retries exhausted
    WriteLog "============================================"
    WriteLog "EXPAND-WINDOWSIMAGE FAILED - DIAGNOSTIC INFO"
    WriteLog "============================================"
    WriteLog "Last error: $lastError"
    WriteLog ""
    WriteLog "This error often occurs when the source ISO becomes unmounted during"
    WriteLog "the 3-5+ minute Expand-WindowsImage operation."
    WriteLog ""
    WriteLog "Possible causes:"
    WriteLog "  1. Windows auto-unmounted the ISO (appears 'idle' during DISM operation)"
    WriteLog "  2. ISO is on network share that timed out"
    WriteLog "  3. ISO is on external drive that went to sleep or disconnected"
    WriteLog "  4. Antivirus software blocked access to WIM file"
    WriteLog "  5. Another process unmounted the ISO"
    WriteLog ""
    WriteLog "Recommendations:"
    WriteLog "  1. Use ISO on local SSD drive (not network or USB)"
    WriteLog "  2. Add antivirus exclusions for FFUDevelopment folder and ISO location"
    WriteLog "  3. Disable USB selective suspend in power settings"
    WriteLog "  4. If using network share, ensure SMB timeouts are configured appropriately"
    WriteLog "============================================"

    throw "Expand-WindowsImage failed after $MaxRetries attempts. Last error: $lastError"
}

function Get-WimFromISO {
    <#
    .SYNOPSIS
    Extracts WIM file path from mounted Windows ISO image

    .DESCRIPTION
    Mounts a Windows ISO image and locates the install.wim or install.esd file
    in the sources folder. Returns the full path to the Windows image file.

    .PARAMETER isoPath
    Full path to the Windows ISO file to mount and extract WIM from

    .EXAMPLE
    $wimPath = Get-WimFromISO -isoPath "C:\ISOs\Windows11.iso"

    .OUTPUTS
    System.String - Full path to install.wim or install.esd file
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$isoPath
    )
    #Mount ISO, get Wim file
    $mountResult = Mount-DiskImage -ImagePath $isoPath -PassThru
    $sourcesFolder = ($mountResult | Get-Volume).DriveLetter + ":\sources\"

    # Register cleanup for mounted ISO in case of failure
    if (Get-Command Register-ISOCleanup -ErrorAction SilentlyContinue) {
        $null = Register-ISOCleanup -ISOPath $isoPath
    }

    # Check for install.wim or install.esd
    $wimPath = (Get-ChildItem $sourcesFolder\install.* | Where-Object { $_.Name -match "install\.(wim|esd)" }).FullName

    if ($wimPath) {
        WriteLog "The path to the install file is: $wimPath"
    }
    else {
        WriteLog "No install.wim or install.esd file found in: $sourcesFolder"
    }

    return $wimPath
}

function Get-Index {
    <#
    .SYNOPSIS
    Determines the correct Windows image index for specified SKU

    .DESCRIPTION
    Analyzes a Windows image file (WIM/ESD) to find the image index that matches
    the specified SKU. Uses different index selection logic for ISO vs ESD media.
    Prompts user to select if exact match is not found.

    .PARAMETER WindowsImagePath
    Full path to the Windows image file (install.wim or install.esd)

    .PARAMETER WindowsSKU
    Target Windows SKU (e.g., "Pro", "Enterprise", "Home", "Education")

    .PARAMETER ISOPath
    Optional path to source ISO file. When provided, uses ISO-specific index logic (starts at index 1).
    When not provided, uses ESD/MCT-specific logic (starts at index 4).

    .EXAMPLE
    $index = Get-Index -WindowsImagePath "C:\mount\install.wim" -WindowsSKU "Pro" -ISOPath "C:\ISOs\Win11.iso"

    .OUTPUTS
    System.Int32 - Image index number matching the specified SKU
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WindowsImagePath,

        [Parameter(Mandatory = $true)]
        [string]$WindowsSKU,

        [Parameter(Mandatory = $false)]
        [string]$ISOPath
    )

    # Get the available indexes using Get-WindowsImage
    $imageIndexes = Get-WindowsImage -ImagePath $WindowsImagePath

    # Get the ImageName of ImageIndex 1 if an ISO was specified, else use ImageIndex 4 - this is usually Home or Education SKU on ESD MCT media
    if ($ISOPath) {
        if ($WindowsSKU -notmatch "Standard|Datacenter") {
            $imageIndex = $imageIndexes | Where-Object ImageIndex -eq 1
            $WindowsImage = $imageIndex.ImageName.Substring(0, 10)
        }
        else {
            $imageIndex = $imageIndexes | Where-Object ImageIndex -eq 1
            $WindowsImage = $imageIndex.ImageName.Substring(0, 19)
        }
    }
    else {
        $imageIndex = $imageIndexes | Where-Object ImageIndex -eq 4
        $WindowsImage = $imageIndex.ImageName.Substring(0, 10)
    }

    # Concatenate $WindowsImage and $WindowsSKU (E.g. Windows 11 Pro)
    $ImageNameToFind = "$WindowsImage $WindowsSKU"

    # Find the ImageName in all of the indexes in the image
    $matchingImageIndex = $imageIndexes | Where-Object ImageName -eq $ImageNameToFind

    # Return the index that matches exactly
    if ($matchingImageIndex) {
        return $matchingImageIndex.ImageIndex
    }
    else {
        # Look for the numbers 10, 11, 2016, 2019, 2022+ in the ImageName
        $relevantImageIndexes = $imageIndexes | Where-Object { ($_.ImageName -match "(10|11|2016|2019|202\d)") }

        while ($true) {
            # Present list of ImageNames to the end user if no matching ImageIndex is found
            Write-Host "No matching ImageIndex found for $ImageNameToFind. Please select an ImageName from the list below:"

            $i = 1
            $relevantImageIndexes | ForEach-Object {
                Write-Host "$i. $($_.ImageName)"
                $i++
            }

            # Ask for user input
            $inputValue = Read-Host "Enter the number of the ImageName you want to use"

            # Get selected ImageName based on user input
            $selectedImage = $relevantImageIndexes[$inputValue - 1]

            if ($selectedImage) {
                return $selectedImage.ImageIndex
            }
            else {
                Write-Host "Invalid selection, please try again."
            }
        }
    }
}

function New-ScratchVhdx {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VhdxPath,
        [uint64]$SizeBytes = 50GB,
        [uint32]$LogicalSectorSizeBytes,
        [switch]$Dynamic,
        [Microsoft.PowerShell.Cmdletization.GeneratedTypes.Disk.PartitionStyle]$PartitionStyle = [Microsoft.PowerShell.Cmdletization.GeneratedTypes.Disk.PartitionStyle]::GPT
    )

    WriteLog "Creating new Scratch VHDX..."

    $newVHDX = New-VHD -Path $VhdxPath -SizeBytes $SizeBytes -LogicalSectorSizeBytes $LogicalSectorSizeBytes -Dynamic:($Dynamic.IsPresent)
    $toReturn = $newVHDX | Mount-VHD -Passthru | Initialize-Disk -PassThru -PartitionStyle GPT

    #Remove auto-created partition so we can create the correct partition layout
    remove-partition $toreturn.DiskNumber -PartitionNumber 1 -Confirm:$False

    Writelog "Done."
    return $toReturn
}

function New-SystemPartition {
    param(
        [Parameter(Mandatory = $true)]
        [ciminstance]$VhdxDisk,
        [uint64]$SystemPartitionSize = 260MB
    )

    WriteLog "Creating System partition..."

    $sysPartition = $VhdxDisk | New-Partition -DriveLetter 'S' -Size $SystemPartitionSize -GptType "{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}" -IsHidden
    $sysPartition | Format-Volume -FileSystem FAT32 -Force -NewFileSystemLabel "System"

    WriteLog 'Done.'
    return $sysPartition.DriveLetter
}

function New-MSRPartition {
    param(
        [Parameter(Mandatory = $true)]
        [ciminstance]$VhdxDisk
    )

    WriteLog "Creating MSR partition..."

    # $toReturn = $VhdxDisk | New-Partition -AssignDriveLetter -Size 16MB -GptType "{e3c9e316-0b5c-4db8-817d-f92df00215ae}" -IsHidden | Out-Null
    $toReturn = $VhdxDisk | New-Partition -Size 16MB -GptType "{e3c9e316-0b5c-4db8-817d-f92df00215ae}" -IsHidden | Out-Null

    WriteLog "Done."

    return $toReturn
}

function New-OSPartition {
    <#
    .SYNOPSIS
    Creates and formats the OS partition on VHDX and applies Windows image

    .DESCRIPTION
    Creates a GPT OS partition on the mounted VHDX disk, formats it as NTFS,
    and applies the Windows image from WIM/ESD file. Supports CompactOS for
    reduced disk space usage on client SKUs.

    Uses Invoke-ExpandWindowsImageWithRetry for robust image application with
    automatic retry and ISO re-mount capability to prevent error 0x8007048F
    "The device is not connected" during long operations.

    .PARAMETER VhdxDisk
    CIM instance of the mounted VHDX disk

    .PARAMETER WimPath
    Full path to the Windows image file (install.wim or install.esd)

    .PARAMETER WimIndex
    Image index to apply from the WIM file

    .PARAMETER OSPartitionSize
    Size of OS partition in bytes (0 = use maximum available space)

    .PARAMETER CompactOS
    If $true, applies Windows image with compression using -Compact switch
    (reduces disk usage but not supported on Server SKUs)

    .PARAMETER ISOPath
    Optional path to source ISO file. When provided, enables automatic ISO
    re-mount if the WIM source becomes unavailable during expansion.

    .EXAMPLE
    $osPartition = New-OSPartition -VhdxDisk $disk -WimPath "C:\install.wim" `
                                   -WimIndex 1 -OSPartitionSize 0 -CompactOS $true

    .EXAMPLE
    $osPartition = New-OSPartition -VhdxDisk $disk -WimPath "F:\sources\install.wim" `
                                   -WimIndex 3 -CompactOS $true -ISOPath "C:\ISOs\Win11.iso"

    .OUTPUTS
    CimInstance - The created OS partition object
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ciminstance]$VhdxDisk,

        [Parameter(Mandatory = $true)]
        [string]$WimPath,

        [Parameter(Mandatory = $false)]
        [uint32]$WimIndex,

        [Parameter(Mandatory = $false)]
        [uint64]$OSPartitionSize = 0,

        [Parameter(Mandatory = $false)]
        [bool]$CompactOS = $false,

        [Parameter(Mandatory = $false)]
        [string]$ISOPath
    )

    WriteLog "Creating OS partition..."

    if ($OSPartitionSize -gt 0) {
        $osPartition = $vhdxDisk | New-Partition -DriveLetter 'W' -Size $OSPartitionSize -GptType "{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}"
    }
    else {
        $osPartition = $vhdxDisk | New-Partition -DriveLetter 'W' -UseMaximumSize -GptType "{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}"
    }

    $osPartition | Format-Volume -FileSystem NTFS -Confirm:$false -Force -NewFileSystemLabel "Windows"
    WriteLog 'Done'
    Writelog "OS partition at drive $($osPartition.DriveLetter):"

    WriteLog "Writing Windows at $WimPath to OS partition at drive $($osPartition.DriveLetter):..."

    # Build parameters for Invoke-ExpandWindowsImageWithRetry
    $expandParams = @{
        ImagePath = $WimPath
        Index = $WimIndex
        ApplyPath = "$($osPartition.DriveLetter):\"
    }

    # Add ISOPath if provided (enables re-mount on failure)
    if ($ISOPath) {
        $expandParams['ISOPath'] = $ISOPath
    }

    # Server 2019 is missing the Windows Overlay Filter (wof.sys), likely other Server SKUs are missing it as well.
    # Script will error if trying to use the -compact switch on Server OSes
    if ((Get-CimInstance Win32_OperatingSystem).Caption -match "Server") {
        WriteLog "Server OS detected - using standard expansion (no CompactOS)"
        $expandResult = Invoke-ExpandWindowsImageWithRetry @expandParams
        WriteLog $expandResult
    }
    elseif ($CompactOS) {
        WriteLog '$CompactOS is set to true, using -Compact switch to apply the WIM file to the OS partition.'
        $expandParams['Compact'] = $true
        $expandResult = Invoke-ExpandWindowsImageWithRetry @expandParams
        WriteLog $expandResult
    }
    else {
        $expandResult = Invoke-ExpandWindowsImageWithRetry @expandParams
        WriteLog $expandResult
    }

    WriteLog 'Done'
    return $osPartition
}

function New-RecoveryPartition {
    param(
        [Parameter(Mandatory = $true)]
        [ciminstance]$VhdxDisk,
        [Parameter(Mandatory = $true)]
        $OsPartition,
        [uint64]$RecoveryPartitionSize = 0,
        [ciminstance]$DataPartition
    )

    WriteLog "Creating empty Recovery partition (to be filled on first boot automatically)..."

    $calculatedRecoverySize = 0
    $recoveryPartition = $null

    if ($RecoveryPartitionSize -gt 0) {
        $calculatedRecoverySize = $RecoveryPartitionSize
    }
    else {
        $winReWim = Get-ChildItem "$($OsPartition.DriveLetter):\Windows\System32\Recovery\Winre.wim" -Attributes Hidden -ErrorAction SilentlyContinue

        if (($null -ne $winReWim) -and ($winReWim.Count -eq 1)) {
            # Wim size + 100MB is minimum WinRE partition size.
            # NTFS and other partitioning size differences account for about 17MB of space that's unavailable.
            # Adding 32MB as a buffer to ensure there's enough space to account for NTFS file system overhead.
            # Adding 250MB as per recommendations from
            # https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/configure-uefigpt-based-hard-drive-partitions?view=windows-11#recovery-tools-partition
            $calculatedRecoverySize = $winReWim.Length + 250MB + 32MB

            WriteLog "Calculated space needed for recovery in bytes: $calculatedRecoverySize"

            if ($null -ne $DataPartition) {
                $DataPartition | Resize-Partition -Size ($DataPartition.Size - $calculatedRecoverySize)
                WriteLog "Data partition shrunk by $calculatedRecoverySize bytes for Recovery partition."
            }
            else {
                $newOsPartitionSize = [math]::Floor(($OsPartition.Size - $calculatedRecoverySize) / 4096) * 4096
                $OsPartition | Resize-Partition -Size $newOsPartitionSize
                WriteLog "OS partition shrunk by $calculatedRecoverySize bytes for Recovery partition."
            }

            $recoveryPartition = $VhdxDisk | New-Partition -DriveLetter 'R' -UseMaximumSize -GptType "{de94bba4-06d1-4d40-a16a-bfd50179d6ac}" `
            | Format-Volume -FileSystem NTFS -Confirm:$false -Force -NewFileSystemLabel 'Recovery'

            WriteLog "Done. Recovery partition at drive $($recoveryPartition.DriveLetter):"
        }
        else {
            WriteLog "No WinRE.WIM found in the OS partition under \Windows\System32\Recovery."
            WriteLog "Skipping creating the Recovery partition."
            WriteLog "If a Recovery partition is desired, please re-run the script setting the -RecoveryPartitionSize flag as appropriate."
        }
    }

    return $recoveryPartition
}

function Add-BootFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OsPartitionDriveLetter,
        [Parameter(Mandatory = $true)]
        [string]$SystemPartitionDriveLetter,
        [string]$FirmwareType = 'UEFI'
    )

    WriteLog "Adding boot files for `"$($OsPartitionDriveLetter):\Windows`" to System partition `"$($SystemPartitionDriveLetter):`"..."
    Invoke-Process bcdboot "$($OsPartitionDriveLetter):\Windows /S $($SystemPartitionDriveLetter): /F $FirmwareType" | Out-Null
    WriteLog "Done."
}

function Enable-WindowsFeaturesByName {
    <#
    .SYNOPSIS
    Enables Windows optional features by name in mounted Windows image

    .DESCRIPTION
    Enables one or more Windows optional features in a mounted Windows partition.
    Supports semicolon-separated feature names and uses a specified source path
    for feature files.

    .PARAMETER FeatureNames
    Semicolon-separated list of Windows feature names to enable (e.g., "NetFx3;TelnetClient")

    .PARAMETER Source
    Path to feature source files (typically WIM SxS folder)

    .PARAMETER WindowsPartition
    Mounted Windows partition path where features will be enabled

    .EXAMPLE
    Enable-WindowsFeaturesByName -FeatureNames "NetFx3;TelnetClient" `
                                -Source "C:\Mount\Sources\SxS" -WindowsPartition "C:\Mount"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$FeatureNames,

        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$WindowsPartition
    )

    $FeaturesArray = $FeatureNames.Split(';')

    # Looping through each feature and enabling it
    foreach ($FeatureName in $FeaturesArray) {
        WriteLog "Enabling Windows Optional feature: $FeatureName"
        Enable-WindowsOptionalFeature -Path $WindowsPartition -FeatureName $FeatureName -All -Source $Source | Out-Null
        WriteLog "Done"
    }
}

function Dismount-ScratchVhdx {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VhdxPath
    )

    if (Test-Path $VhdxPath) {
        WriteLog "Dismounting scratch VHDX..."
        Dismount-VHD -Path $VhdxPath
        WriteLog "Done."
    }
}

function Optimize-FFUCaptureDrive {
    param (
        [string]$VhdxPath
    )
    try {
        WriteLog 'Mounting VHDX for volume optimization'
        $mountedDisk = Mount-VHD -Path $VhdxPath -Passthru | Get-Disk
        $osPartition = $mountedDisk | Get-Partition | Where-Object { $_.GptType -eq "{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}" }
        WriteLog 'Defragmenting Windows partition...'
        Optimize-Volume -DriveLetter $osPartition.DriveLetter -Defrag -NormalPriority
        WriteLog 'Performing slab consolidation on Windows partition...'
        Optimize-Volume -DriveLetter $osPartition.DriveLetter -SlabConsolidate -NormalPriority
        WriteLog 'Dismounting VHDX'
        Dismount-ScratchVhdx -VhdxPath $VhdxPath
        WriteLog 'Mounting VHDX as read-only for optimization'
        Mount-VHD -Path $VhdxPath -NoDriveLetter -ReadOnly
        WriteLog 'Optimizing VHDX in full mode...'
        Optimize-VHD -Path $VhdxPath -Mode Full
        WriteLog 'Dismounting VHDX'
        Dismount-ScratchVhdx -VhdxPath $VhdxPath
    }
    catch {
        throw $_
    }
}

function Get-WindowsVersionInfo {
    <#
    .SYNOPSIS
    Retrieves Windows version information from a mounted VHDX partition.

    .DESCRIPTION
    Loads the Windows registry hive from a mounted VHDX partition to extract
    version information including build number, display version, and OS name.
    This information is used to generate appropriate FFU filenames.

    IMPORTANT: Includes 60-second delays before and after registry access to
    prevent CBS/CSI corruption which can cause Windows Update issues after
    deployment. This is especially important when capturing from fast NVMe disks.

    .PARAMETER OsPartitionDriveLetter
    The drive letter (without colon) of the mounted Windows partition.

    .PARAMETER InstallationType
    The Windows installation type ('Client' or 'Server').

    .PARAMETER ShortenedWindowsSKU
    The shortened Windows SKU name (e.g., 'Pro', 'Ent', 'Srv2022').

    .EXAMPLE
    $versionInfo = Get-WindowsVersionInfo -OsPartitionDriveLetter "E" `
                                          -InstallationType "Client" `
                                          -ShortenedWindowsSKU "Pro"

    .OUTPUTS
    Hashtable with keys: DisplayVersion, BuildDate, Name

    .NOTES
    This function was extracted during modularization to fix missing function error.
    The delays are critical for system stability during VHDX-direct FFU capture.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[A-Za-z]$')]
        [string]$OsPartitionDriveLetter,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Client', 'Server')]
        [string]$InstallationType,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ShortenedWindowsSKU
    )

    # This sleep prevents CBS/CSI corruption which causes issues with Windows Update after deployment.
    # Capturing from very fast disks (NVME) can cause the capture to happen faster than Windows is ready for.
    # This primarily affects VHDX-only captures, not VM captures.
    WriteLog 'Sleep 60 seconds before opening registry to grab Windows version info'
    Start-Sleep 60

    WriteLog "Getting Windows Version info"

    # Load Registry Hive
    $Software = "$OsPartitionDriveLetter`:\Windows\System32\config\software"
    WriteLog "Loading Software registry hive: $Software"
    Invoke-Process reg "load HKLM\FFU `"$Software`"" | Out-Null

    try {
        # Find Windows version values
        [int]$CurrentBuild = Get-ItemPropertyValue -Path 'HKLM:\FFU\Microsoft\Windows NT\CurrentVersion\' -Name 'CurrentBuild'
        WriteLog "Windows Build: $CurrentBuild"

        # DisplayVersion does not exist for 1607 builds (RS1 and Server 2016) and Server 2019
        $DisplayVersion = $null
        if ($CurrentBuild -notin (14393, 17763)) {
            $DisplayVersion = Get-ItemPropertyValue -Path 'HKLM:\FFU\Microsoft\Windows NT\CurrentVersion\' -Name 'DisplayVersion'
            WriteLog "Windows Version: $DisplayVersion"
        }

        # For Windows 10 LTSC 2019, set DisplayVersion to 2019
        if ($CurrentBuild -eq 17763 -and $InstallationType -eq "Client") {
            $DisplayVersion = '2019'
        }

        $BuildDate = Get-Date -UFormat %b%Y

        # Determine the OS name based on SKU and build
        if ($ShortenedWindowsSKU -notmatch "Srv") {
            if ($CurrentBuild -ge 22000) {
                $Name = 'Win11'
            }
            else {
                $Name = 'Win10'
            }
        }
        else {
            $Name = switch ($CurrentBuild) {
                26100 { '2025' }
                20348 { '2022' }
                17763 { '2019' }
                14393 { '2016' }
                Default { $DisplayVersion }
            }
        }
    }
    finally {
        WriteLog "Unloading registry"
        Invoke-Process reg "unload HKLM\FFU" | Out-Null
    }

    # This prevents Critical Process Died errors during deployment of the FFU.
    # Capturing from very fast disks (NVME) can cause the capture to happen faster than Windows is ready for.
    WriteLog 'Sleep 60 seconds to allow registry to completely unload'
    Start-Sleep 60

    return @{
        DisplayVersion = $DisplayVersion
        BuildDate      = $BuildDate
        Name           = $Name
    }
}

function New-FFU {
    <#
    .SYNOPSIS
    Creates FFU (Full Flash Update) image from VM or VHDX

    .DESCRIPTION
    Captures FFU image from a running VM (if InstallApps=true) or directly from VHDX.
    Optionally injects drivers and optimizes the FFU for deployment.

    .PARAMETER VMName
    Optional VM name (required if InstallApps is true)

    .PARAMETER InstallApps
    Boolean indicating if apps were installed in VM

    .PARAMETER CaptureISO
    Path to WinPE capture ISO

    .PARAMETER VMSwitchName
    Name of Hyper-V virtual switch for VM network

    .PARAMETER FFUCaptureLocation
    Directory where FFU file will be saved

    .PARAMETER AllowVHDXCaching
    Boolean indicating if VHDX caching is enabled

    .PARAMETER CustomFFUNameTemplate
    Custom template for FFU filename

    .PARAMETER ShortenedWindowsSKU
    Shortened Windows SKU name for FFU filename

    .PARAMETER VHDXPath
    Path to VHDX file

    .PARAMETER DandIEnv
    Path to Deployment and Imaging Environment batch file

    .PARAMETER VhdxDisk
    VHDX disk object

    .PARAMETER CachedVHDXInfo
    Cached VHDX information object

    .PARAMETER InstallationType
    Installation type (Client or Server)

    .PARAMETER InstallDrivers
    Boolean indicating if drivers should be injected

    .PARAMETER Optimize
    Boolean indicating if FFU should be optimized

    .PARAMETER FFUDevelopmentPath
    Root FFUDevelopment path

    .PARAMETER DriversFolder
    Path to drivers folder

    .EXAMPLE
    New-FFU -VMName "_FFU-Build" -InstallApps $true -CaptureISO "C:\FFU\Capture.iso" `
            -VMSwitchName "Default Switch" -FFUCaptureLocation "C:\FFU" `
            -AllowVHDXCaching $false -CustomFFUNameTemplate "" `
            -ShortenedWindowsSKU "Pro" -VHDXPath "C:\FFU\disk.vhdx" `
            -DandIEnv "C:\ADK\DandISetEnv.bat" -VhdxDisk $disk `
            -CachedVHDXInfo $null -InstallationType "Client" `
            -InstallDrivers $true -Optimize $true `
            -FFUDevelopmentPath "C:\FFU" -DriversFolder "C:\FFU\Drivers"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$VMName,

        [Parameter(Mandatory = $true)]
        [bool]$InstallApps,

        [Parameter(Mandatory = $false)]
        [string]$CaptureISO,

        [Parameter(Mandatory = $false)]
        [string]$VMSwitchName,

        [Parameter(Mandatory = $true)]
        [string]$FFUCaptureLocation,

        [Parameter(Mandatory = $true)]
        [bool]$AllowVHDXCaching,

        [Parameter(Mandatory = $false)]
        [string]$CustomFFUNameTemplate,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ShortenedWindowsSKU,

        [Parameter(Mandatory = $false)]
        [string]$VHDXPath,

        [Parameter(Mandatory = $true)]
        [string]$DandIEnv,

        [Parameter(Mandatory = $false)]
        $VhdxDisk,

        [Parameter(Mandatory = $false)]
        $CachedVHDXInfo,

        [Parameter(Mandatory = $false)]
        [string]$InstallationType,

        [Parameter(Mandatory = $true)]
        [bool]$InstallDrivers,

        [Parameter(Mandatory = $true)]
        [bool]$Optimize,

        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath,

        [Parameter(Mandatory = $false)]
        [string]$DriversFolder
    )
    #If $InstallApps = $true, configure the VM
    If ($InstallApps) {
        WriteLog 'Creating FFU from VM'
        WriteLog "Setting $CaptureISO as first boot device"
        $VMDVDDrive = Get-VMDvdDrive -VMName $VMName
        Set-VMFirmware -VMName $VMName -FirstBootDevice $VMDVDDrive
        Set-VMDvdDrive -VMName $VMName -Path $CaptureISO
        $VMSwitch = Get-VMSwitch -name $VMSwitchName
        WriteLog "Setting $($VMSwitch.Name) as VMSwitch"
        get-vm $VMName | Get-VMNetworkAdapter | Connect-VMNetworkAdapter -SwitchName $VMSwitch.Name
        WriteLog "Configuring VM complete"

        #Start VM
        Set-Progress -Percentage 68 -Message "Capturing FFU from VM..."
        WriteLog "Starting VM"
        Start-VM -Name $VMName

        # Wait for the VM to turn off
        do {
            $FFUVM = Get-VM -Name $VMName
            Start-Sleep -Seconds ([FFUConstants]::VM_STATE_POLL_INTERVAL)
        } while ($FFUVM.State -ne 'Off')
        WriteLog "VM Shutdown"
        # Check for .ffu files in the FFUDevelopment folder
        WriteLog "Checking for FFU Files"
        $FFUFiles = Get-ChildItem -Path $FFUCaptureLocation -Filter "*.ffu" -File

        # If there's more than one .ffu file, get the most recent and store its path in $FFUFile
        if ($FFUFiles.Count -gt 0) {
            WriteLog 'Getting the most recent FFU file'
            $FFUFile = ($FFUFiles | Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1).FullName
            WriteLog "Most recent .ffu file: $FFUFile"
        }
        else {
            WriteLog "No .ffu files found in $FFUCaptureLocation"
            throw $_
        }
    }
    elseif (-not $InstallApps -and (-not $AllowVHDXCaching)) {
        #Get Windows Version Information from the VHDX
        # Validate VhdxDisk parameter before using it
        if (-not $VhdxDisk) {
            WriteLog "ERROR: VhdxDisk parameter is null or empty"
            throw "VhdxDisk parameter is required for direct VHDX-to-FFU capture but was not provided"
        }

        # Validate disk number is available
        $diskNumber = $VhdxDisk.DiskNumber
        if ($null -eq $diskNumber) {
            WriteLog "ERROR: VhdxDisk object does not have a valid DiskNumber property"
            WriteLog "VhdxDisk type: $($VhdxDisk.GetType().FullName)"
            throw "VhdxDisk object is invalid - missing DiskNumber property"
        }
        WriteLog "Using disk number $diskNumber to get partition information"

        # Get the OS partition drive letter from the mounted VHDX disk
        # Use Get-Partition with -DiskNumber for reliable lookup (more consistent than piping)
        # GPT type {ebd0a0a2-b9e5-4433-87c0-68b6b72699c7} is the Basic Data Partition type (where Windows is installed)
        $allPartitions = Get-Partition -DiskNumber $diskNumber -ErrorAction SilentlyContinue
        if (-not $allPartitions) {
            WriteLog "ERROR: No partitions found on disk $diskNumber"
            WriteLog "This may indicate the VHDX is not properly mounted or partitioned"
            throw "Could not find any partitions on mounted VHDX disk (DiskNumber: $diskNumber)"
        }

        WriteLog "Found $($allPartitions.Count) partition(s) on disk $diskNumber"
        $osPartition = $allPartitions | Where-Object { $_.GptType -eq "{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}" }

        if (-not $osPartition) {
            # Log available partitions for debugging
            WriteLog "ERROR: Could not find OS partition (GPT type: Basic Data Partition)"
            WriteLog "Available partitions:"
            foreach ($p in $allPartitions) {
                WriteLog "  Partition $($p.PartitionNumber): Type=$($p.Type), GptType=$($p.GptType), DriveLetter=$($p.DriveLetter)"
            }
            throw "Could not find OS partition on mounted VHDX disk. Expected GPT type {ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}"
        }

        $osPartitionDriveLetter = $osPartition.DriveLetter
        if (-not $osPartitionDriveLetter) {
            WriteLog "ERROR: OS partition found but has no drive letter assigned"
            WriteLog "Partition details: Number=$($osPartition.PartitionNumber), Size=$($osPartition.Size), GptType=$($osPartition.GptType)"
            throw "OS partition does not have an assigned drive letter"
        }
        WriteLog "OS partition found at drive letter: $osPartitionDriveLetter"

        $winverinfo = Get-WindowsVersionInfo -OsPartitionDriveLetter $osPartitionDriveLetter `
                                              -InstallationType $InstallationType `
                                              -ShortenedWindowsSKU $ShortenedWindowsSKU
        WriteLog 'Creating FFU File Name'
        if ($CustomFFUNameTemplate) {
            # Extract WindowsRelease from winverinfo.Name (e.g., "Win11" -> 11)
            $releaseNumber = if ($winverinfo.Name -match '\d+') { [int]$matches[0] } else { 11 }
            $FFUFileName = New-FFUFileName -installationType $InstallationType -winverinfo $winverinfo `
                                          -WindowsRelease $releaseNumber -CustomFFUNameTemplate $CustomFFUNameTemplate `
                                          -WindowsVersion $winverinfo.DisplayVersion -shortenedWindowsSKU $ShortenedWindowsSKU
        }
        else {
            $FFUFileName = "$($winverinfo.Name)`_$($winverinfo.DisplayVersion)`_$($shortenedWindowsSKU)`_$($winverinfo.BuildDate).ffu"
        }
        WriteLog "FFU file name: $FFUFileName"
        $FFUFile = "$FFUCaptureLocation\$FFUFileName"
        #Capture the FFU
        Set-Progress -Percentage 68 -Message "Capturing FFU from VHDX..."
        WriteLog 'Capturing FFU'
        # Use 'call' before batch file path to properly handle spaces in paths like "C:\Program Files (x86)\..."
        Invoke-Process cmd "/c call `"$DandIEnv`" && dism /Capture-FFU /ImageFile:`"$FFUFile`" /CaptureDrive:\\.\PhysicalDrive$($vhdxDisk.DiskNumber) /Name:$($winverinfo.Name)$($winverinfo.DisplayVersion)$($shortenedWindowsSKU) /Compress:Default" | Out-Null
        WriteLog 'FFU Capture complete'
        Dismount-ScratchVhdx -VhdxPath $VHDXPath
    }
    elseif (-not $InstallApps -and $AllowVHDXCaching) {
        # Make $FFUFileName based on values in the config.json file
        WriteLog 'Creating FFU File Name'
        if ($CustomFFUNameTemplate) {
            $FFUFileName = New-FFUFileName -installationType $InstallationType -winverinfo $null `
                                          -WindowsRelease $cachedVHDXInfo.WindowsRelease `
                                          -CustomFFUNameTemplate $CustomFFUNameTemplate `
                                          -WindowsVersion $cachedVHDXInfo.WindowsVersion `
                                          -shortenedWindowsSKU $ShortenedWindowsSKU
        }
        else {
            $BuildDate = Get-Date -UFormat %b%Y
            # Get Windows Information to make the FFU file name from the cachedVHDXInfo file
            if ($installationType -eq 'Client') {
                $FFUFileName = "Win$($cachedVHDXInfo.WindowsRelease)`_$($cachedVHDXInfo.WindowsVersion)`_$($shortenedWindowsSKU)`_$BuildDate.ffu"
            }
            else {
                $FFUFileName = "Server$($cachedVHDXInfo.WindowsRelease)`_$($cachedVHDXInfo.WindowsVersion)`_$($shortenedWindowsSKU)`_$BuildDate.ffu"
            }
        }
        WriteLog "FFU file name: $FFUFileName"
        $FFUFile = "$FFUCaptureLocation\$FFUFileName"
        #Capture the FFU
        WriteLog 'Capturing FFU'
        # Use 'call' before batch file path to properly handle spaces in paths like "C:\Program Files (x86)\..."
        Invoke-Process cmd "/c call `"$DandIEnv`" && dism /Capture-FFU /ImageFile:`"$FFUFile`" /CaptureDrive:\\.\PhysicalDrive$($vhdxDisk.DiskNumber) /Name:$($cachedVHDXInfo.WindowsRelease)$($cachedVHDXInfo.WindowsVersion)$($shortenedWindowsSKU) /Compress:Default" | Out-Null
        WriteLog 'FFU Capture complete'
        Dismount-ScratchVhdx -VhdxPath $VHDXPath
    }

    #Without this 120 second sleep, we sometimes see an error when mounting the FFU due to a file handle lock. Needed for both driver and optimize steps.

    If ($InstallDrivers -or $Optimize) {
        WriteLog 'Sleeping 2 minutes to prevent file handle lock'
        Start-Sleep 120
    }

    #Add drivers
    If ($InstallDrivers) {
        Set-Progress -Percentage 75 -Message "Injecting drivers into FFU..."
        WriteLog 'Adding drivers'
        $mountPath = "$FFUDevelopmentPath\Mount"
        $imageMounted = $false

        try {
            WriteLog "Creating $mountPath directory"
            New-Item -Path $mountPath -ItemType Directory -Force | Out-Null
            WriteLog "Created $mountPath directory"

            # Ensure required Windows services are running for DISM operations
            Start-RequiredServicesForDISM

            # Mount the image with retry logic
            WriteLog "Mounting $FFUFile to $mountPath"
            try {
                Mount-WindowsImage -ImagePath $FFUFile -Index 1 -Path $mountPath -ErrorAction Stop | Out-Null
                $imageMounted = $true
                WriteLog 'Mounting complete'

                # Register cleanup for DISM mount in case of failure
                if (Get-Command Register-DISMMountCleanup -ErrorAction SilentlyContinue) {
                    $null = Register-DISMMountCleanup -MountPath $mountPath
                }
            }
            catch {
                WriteLog "ERROR: Failed to mount image: $($_.Exception.Message)"
                # Attempt cleanup of stale mount points before retry
                WriteLog "Attempting DISM cleanup and retry..."
                & dism.exe /Cleanup-Mountpoints 2>&1 | Out-Null
                Start-Sleep -Seconds 3
                try {
                    Mount-WindowsImage -ImagePath $FFUFile -Index 1 -Path $mountPath -ErrorAction Stop | Out-Null
                    $imageMounted = $true
                    WriteLog 'Mounting succeeded on retry'

                    # Register cleanup for DISM mount in case of failure
                    if (Get-Command Register-DISMMountCleanup -ErrorAction SilentlyContinue) {
                        $null = Register-DISMMountCleanup -MountPath $mountPath
                    }
                }
                catch {
                    throw "Failed to mount image after retry: $($_.Exception.Message)"
                }
            }

            WriteLog 'Adding drivers - This will take a few minutes, please be patient'
            try {
                Add-WindowsDriver -Path $mountPath -Driver "$DriversFolder" -Recurse -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Out-Null
            }
            catch {
                WriteLog 'Some drivers failed to be added to the FFU. This can be expected. Continuing.'
            }
            WriteLog 'Adding drivers complete'
        }
        finally {
            # Always attempt dismount if image was mounted
            if ($imageMounted) {
                WriteLog "Dismount $mountPath"
                try {
                    Dismount-WindowsImage -Path $mountPath -Save -ErrorAction Stop | Out-Null
                    WriteLog 'Dismount complete'
                }
                catch {
                    WriteLog "WARNING: Dismount failed: $($_.Exception.Message)"
                    WriteLog "Attempting forced dismount with discard..."
                    try {
                        Dismount-WindowsImage -Path $mountPath -Discard -ErrorAction Stop | Out-Null
                        WriteLog 'Dismount with discard complete'
                    }
                    catch {
                        WriteLog "WARNING: Forced dismount also failed. Running DISM cleanup..."
                        & dism.exe /Cleanup-Mountpoints 2>&1 | Out-Null
                    }
                }
            }

            # Cleanup mount folder
            WriteLog "Remove $mountPath folder"
            try {
                Remove-Item -Path $mountPath -Recurse -Force -ErrorAction Stop | Out-Null
                WriteLog 'Folder removed'
            }
            catch {
                WriteLog "WARNING: Could not remove mount folder: $($_.Exception.Message)"
            }
        }
    }
    #Optimize FFU
    if ($Optimize -eq $true) {
        Set-Progress -Percentage 85 -Message "Optimizing FFU..."
        WriteLog 'Optimizing FFU - This will take a few minutes, please be patient'
        # Use dedicated scratch directory to prevent file lock errors (Error 1167 / 0x8007048f)
        # This addresses antivirus and Windows Search indexer interference with temp VHD files
        Invoke-FFUOptimizeWithScratchDir -FFUFile $FFUFile -DandIEnv $DandIEnv -FFUDevelopmentPath $FFUDevelopmentPath
        WriteLog 'Optimizing FFU complete'
        Set-Progress -Percentage 90 -Message "FFU post-processing complete."
    }


}

function Remove-FFU {
    <#
    .SYNOPSIS
    Removes FFU build VM, VHDX, and associated resources

    .DESCRIPTION
    Cleans up Hyper-V VM, HGS Guardian, certificates, VHDX files, and mounted
    Windows images after FFU capture completes or fails. Implements different
    cleanup logic depending on whether VM-based or VHDX-only build was used.

    .PARAMETER VMName
    Optional name of the VM to remove

    .PARAMETER InstallApps
    Boolean indicating if apps were installed (affects cleanup logic)

    .PARAMETER vhdxDisk
    VHDX disk object for cleanup validation

    .PARAMETER VMPath
    Path to VM configuration directory to remove

    .PARAMETER FFUDevelopmentPath
    Root FFUDevelopment path for mount folder cleanup

    .EXAMPLE
    Remove-FFU -VMName "_FFU-Build-Win11" -InstallApps $true -vhdxDisk $disk `
              -VMPath "C:\FFU\VM\_FFU-Build-Win11" -FFUDevelopmentPath "C:\FFU"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$VMName,

        [Parameter(Mandatory = $true)]
        [bool]$InstallApps,

        [Parameter(Mandatory = $false)]
        $vhdxDisk,

        [Parameter(Mandatory = $true)]
        [string]$VMPath,

        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath
    )
    #Get the VM object and remove the VM, the HGSGuardian, and the certs
    If ($VMName) {
        $FFUVM = get-vm $VMName | Where-Object { $_.state -ne 'running' }
    }
    If ($null -ne $FFUVM) {
        WriteLog 'Cleaning up VM'
        $certPath = 'Cert:\LocalMachine\Shielded VM Local Certificates\'
        $VMName = $FFUVM.Name
        WriteLog "Removing VM: $VMName"
        Remove-VM -Name $VMName -Force
        WriteLog 'Removal complete'
        WriteLog "Removing $VMPath"
        if (-not [string]::IsNullOrWhiteSpace($VMPath)) {
            Remove-Item -Path $VMPath -Force -Recurse -ErrorAction SilentlyContinue
        }
        WriteLog 'Removal complete'
        WriteLog "Removing HGSGuardian for $VMName"
        Remove-HgsGuardian -Name $VMName -WarningAction SilentlyContinue
        WriteLog 'Removal complete'
        WriteLog 'Cleaning up HGS Guardian certs'
        $certs = Get-ChildItem -Path $certPath -Recurse | Where-Object { $_.Subject -like "*$VMName*" }
        foreach ($cert in $Certs) {
            Remove-Item -Path $cert.PSPath -Force -ErrorAction SilentlyContinue | Out-Null
        }
        WriteLog 'Cert removal complete'
    }
    #If just building the FFU from vhdx, remove the vhdx path
    If (-not $InstallApps -and $vhdxDisk) {
        WriteLog 'Cleaning up VHDX'
        WriteLog "Removing $VMPath"
        if (-not [string]::IsNullOrWhiteSpace($VMPath)) {
            Remove-Item -Path $VMPath -Force -Recurse -ErrorAction SilentlyContinue | Out-Null
        }
        WriteLog 'Removal complete'
    }

    #Remove orphaned mounted images
    $mountedImages = Get-WindowsImage -Mounted
    if ($mountedImages) {
        foreach ($image in $mountedImages) {
            $mountPath = $image.Path
            WriteLog "Dismounting image at $mountPath"
            Dismount-WindowsImage -Path $mountPath -discard
            WriteLog "Successfully dismounted image at $mountPath"
        }
    }
    #Remove Mount folder if it exists
    If (Test-Path -Path $FFUDevelopmentPath\Mount) {
        WriteLog "Remove $FFUDevelopmentPath\Mount folder"
        Remove-Item -Path "$FFUDevelopmentPath\Mount" -Recurse -Force -ErrorAction SilentlyContinue
        WriteLog 'Folder removed'
    }
    #Remove unused mountpoints
    WriteLog 'Remove unused mountpoints'
    Invoke-Process cmd "/c mountvol /r" | Out-Null
    WriteLog 'Removal complete'
}

function Start-RequiredServicesForDISM {
    <#
    .SYNOPSIS
    Ensures required Windows services are running for DISM operations

    .DESCRIPTION
    DISM operations require certain Windows services to be running, primarily
    the Windows Modules Installer (TrustedInstaller) service. This function
    checks if required services are running and starts them if needed, with
    robust waiting and validation to ensure services are fully initialized.

    Addresses "The specified service does not exist" error during Mount-WindowsImage
    and other DISM cmdlets.

    .EXAMPLE
    Start-RequiredServicesForDISM
    #>
    [CmdletBinding()]
    param()

    WriteLog 'Checking required Windows services for DISM operations'
    $requiredServices = @(
        @{Name = 'TrustedInstaller'; DisplayName = 'Windows Modules Installer'; InitDelay = 5},
        @{Name = 'wuauserv'; DisplayName = 'Windows Update'; InitDelay = 3}
    )

    $allServicesOk = $true

    foreach ($svc in $requiredServices) {
        try {
            $service = Get-Service -Name $svc.Name -ErrorAction Stop
            WriteLog "Service '$($svc.DisplayName)' current status: $($service.Status)"

            if ($service.Status -ne 'Running') {
                WriteLog "Starting service '$($svc.DisplayName)'..."
                Start-Service -Name $svc.Name -ErrorAction Stop

                # Wait for service to fully initialize with retry logic
                $initDelay = $svc.InitDelay
                WriteLog "Waiting $initDelay seconds for service to fully initialize..."
                Start-Sleep -Seconds $initDelay

                # Verify service is actually running and ready
                $retryCount = 0
                $maxRetries = [FFUConstants]::MAX_DISM_SERVICE_RETRIES
                $serviceReady = $false

                while ($retryCount -lt $maxRetries -and -not $serviceReady) {
                    $service = Get-Service -Name $svc.Name
                    if ($service.Status -eq 'Running') {
                        WriteLog "Service '$($svc.DisplayName)' started successfully"
                        $serviceReady = $true
                    }
                    else {
                        $retryCount++
                        WriteLog "Service status: $($service.Status), waiting for mount validation (retry $retryCount/$maxRetries)..."
                        Start-Sleep -Seconds ([FFUConstants]::MOUNT_VALIDATION_WAIT)
                    }
                }

                if (-not $serviceReady) {
                    WriteLog "WARNING: Service '$($svc.DisplayName)' did not fully start after $maxRetries retries. Status: $($service.Status)"
                    $allServicesOk = $false
                }
            }
            else {
                WriteLog "Service '$($svc.DisplayName)' is already running"
            }
        }
        catch {
            WriteLog "WARNING: Could not check/start service '$($svc.DisplayName)' - $($_.Exception.Message)"
            WriteLog "DISM operations may fail if this service is required"
            $allServicesOk = $false
        }
    }

    if ($allServicesOk) {
        WriteLog 'All required services for DISM are running and ready'
    }
    else {
        WriteLog 'WARNING: Some required services could not be started. DISM operations may fail.'
    }

    # Additional wait after all services started to ensure DISM subsystem is ready
    if ($allServicesOk) {
        WriteLog 'Waiting for DISM subsystem initialization...'
        Start-Sleep -Seconds ([FFUConstants]::DISM_CLEANUP_WAIT)
        WriteLog 'DISM subsystem should be ready'
    }

    return $allServicesOk
}

function Invoke-FFUOptimizeWithScratchDir {
    <#
    .SYNOPSIS
    Optimizes FFU image using a dedicated scratch directory to prevent file lock errors

    .DESCRIPTION
    Performs FFU optimization using DISM /optimize-ffu with a dedicated scratch directory
    instead of the default %TEMP% folder. This prevents file lock errors (0x80070020)
    caused by antivirus, Windows Search indexer, or other processes accessing temporary
    VHD files created during optimization.

    Addresses DISM error 1167 "The device is not connected" (0x8007048f) which occurs
    when the temporary VHD mount fails due to sharing violations.

    .PARAMETER FFUFile
    Full path to the FFU file to optimize

    .PARAMETER DandIEnv
    Path to the ADK Deployment and Imaging Tools environment batch file (DandISetEnv.bat)

    .PARAMETER FFUDevelopmentPath
    Root FFUDevelopment path where the scratch directory will be created

    .PARAMETER MaxRetries
    Maximum number of retry attempts if optimization fails (default: 2)

    .EXAMPLE
    Invoke-FFUOptimizeWithScratchDir -FFUFile "C:\FFU\Win11_24H2_Pro.ffu" `
                                     -DandIEnv "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\DandISetEnv.bat" `
                                     -FFUDevelopmentPath "C:\FFUDevelopment"

    .NOTES
    This function:
    - Creates a dedicated scratch directory outside of %TEMP%
    - Cleans stale DISM mount points before optimization
    - Dismounts orphaned VHDs that may be locking resources
    - Verifies FFU file is accessible before optimization
    - Provides detailed diagnostics on failure
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ })]
        [string]$FFUFile,

        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ })]
        [string]$DandIEnv,

        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ })]
        [string]$FFUDevelopmentPath,

        [Parameter(Mandatory = $false)]
        [int]$MaxRetries = 2
    )

    # Create dedicated scratch directory (not in user temp)
    $scratchDir = Join-Path $FFUDevelopmentPath "DISMScratch"
    $userTempPath = [System.IO.Path]::GetTempPath()

    WriteLog "Starting FFU optimization with dedicated scratch directory"
    WriteLog "FFU file: $FFUFile"
    WriteLog "Scratch directory: $scratchDir"

    # Step 1: Clean up stale DISM mount points system-wide
    WriteLog "Step 1/6: Cleaning stale DISM mount points..."
    try {
        $dismCleanupOutput = & dism.exe /Cleanup-Mountpoints 2>&1
        WriteLog "DISM cleanup completed"
    }
    catch {
        WriteLog "WARNING: DISM cleanup encountered an issue: $($_.Exception.Message)"
    }

    # Step 2: Dismount any orphaned VHDs in user temp folder (from previous failed operations)
    WriteLog "Step 2/6: Checking for orphaned temporary VHDs in $userTempPath..."
    $staleVhds = Get-ChildItem -Path $userTempPath -Filter "_ffumount*.vhd" -ErrorAction SilentlyContinue
    if ($staleVhds) {
        WriteLog "Found $($staleVhds.Count) orphaned VHD(s) to clean up"
        foreach ($vhd in $staleVhds) {
            try {
                WriteLog "  Dismounting: $($vhd.Name)"
                Dismount-VHD -Path $vhd.FullName -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 1
                Remove-Item $vhd.FullName -Force -ErrorAction SilentlyContinue
                WriteLog "  Removed: $($vhd.Name)"
            }
            catch {
                WriteLog "  WARNING: Could not clean up $($vhd.Name): $($_.Exception.Message)"
            }
        }
    }
    else {
        WriteLog "No orphaned VHDs found in temp folder"
    }

    # Step 3: Clean and recreate scratch directory
    WriteLog "Step 3/6: Preparing scratch directory..."
    if (Test-Path $scratchDir) {
        WriteLog "Cleaning existing scratch directory..."
        # Dismount any VHDs that might be in the scratch directory
        $scratchVhds = Get-ChildItem -Path $scratchDir -Filter "*.vhd*" -ErrorAction SilentlyContinue
        foreach ($vhd in $scratchVhds) {
            try {
                Dismount-VHD -Path $vhd.FullName -ErrorAction SilentlyContinue
            }
            catch { }
        }
        Start-Sleep -Seconds 2
        Remove-Item $scratchDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -Path $scratchDir -ItemType Directory -Force | Out-Null
    WriteLog "Scratch directory created: $scratchDir"

    # Step 4: Verify FFU file exists and is not locked
    WriteLog "Step 4/6: Verifying FFU file accessibility..."
    if (-not (Test-Path $FFUFile)) {
        throw "FFU file not found: $FFUFile"
    }

    $ffuFileInfo = Get-Item $FFUFile
    WriteLog "FFU file size: $([math]::Round($ffuFileInfo.Length / 1GB, 2)) GB"

    try {
        $fileStream = [System.IO.File]::Open($FFUFile, 'Open', 'Read', 'Read')
        $fileStream.Close()
        $fileStream.Dispose()
        WriteLog "FFU file is accessible and not exclusively locked"
    }
    catch {
        throw "FFU file is locked by another process: $FFUFile - $($_.Exception.Message)"
    }

    # Step 5: Verify sufficient disk space for scratch operations
    WriteLog "Step 5/6: Checking disk space for scratch operations..."
    $scratchDrive = Split-Path -Qualifier $scratchDir
    $scratchVolume = Get-Volume -DriveLetter $scratchDrive.TrimEnd(':') -ErrorAction SilentlyContinue
    if ($scratchVolume) {
        $freeSpaceGB = [math]::Round($scratchVolume.SizeRemaining / 1GB, 2)
        WriteLog "Available space on $scratchDrive : $freeSpaceGB GB"
        # FFU optimization typically needs space for a temporary VHD (can be several GB)
        if ($freeSpaceGB -lt 10) {
            WriteLog "WARNING: Low disk space. FFU optimization may fail. Recommend at least 10GB free."
        }
    }

    # Step 6: Wait for file system to settle
    WriteLog "Step 6/6: Waiting for file system to settle..."
    Start-Sleep -Seconds 3

    # Run optimization with retry logic
    $attempt = 0
    $success = $false
    $lastError = $null

    while ($attempt -lt $MaxRetries -and -not $success) {
        $attempt++
        WriteLog "FFU optimization attempt $attempt of $MaxRetries..."

        try {
            # Build DISM command with scratch directory
            # Note: Using /ScratchDir to redirect temporary files away from %TEMP%
            # IMPORTANT: Use 'call' before batch file path to properly handle spaces in paths like
            # "C:\Program Files (x86)\Windows Kits\10\..." - without 'call', cmd.exe /c fails with
            # "'C:\Program' is not recognized as an internal or external command"
            $dismArgs = "/c call `"$DandIEnv`" && dism /optimize-ffu /imagefile:`"$FFUFile`" /ScratchDir:`"$scratchDir`""

            WriteLog "Executing: cmd $dismArgs"
            $result = Invoke-Process cmd $dismArgs

            if ($LASTEXITCODE -eq 0) {
                WriteLog "FFU optimization completed successfully"
                $success = $true
            }
            else {
                $lastError = "DISM optimize-ffu returned exit code $LASTEXITCODE"
                WriteLog "ERROR: $lastError"

                if ($attempt -lt $MaxRetries) {
                    WriteLog "Performing cleanup before retry..."

                    # Clean up scratch directory for retry
                    Get-ChildItem -Path $scratchDir -ErrorAction SilentlyContinue | ForEach-Object {
                        try {
                            if ($_.Extension -match '\.vhd') {
                                Dismount-VHD -Path $_.FullName -ErrorAction SilentlyContinue
                            }
                            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
                        }
                        catch { }
                    }

                    # Also clean user temp in case DISM fell back to it
                    Get-ChildItem -Path $userTempPath -Filter "_ffumount*.vhd" -ErrorAction SilentlyContinue | ForEach-Object {
                        try {
                            Dismount-VHD -Path $_.FullName -ErrorAction SilentlyContinue
                            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
                        }
                        catch { }
                    }

                    # Run DISM cleanup again
                    & dism.exe /Cleanup-Mountpoints 2>&1 | Out-Null

                    WriteLog "Waiting 10 seconds before retry..."
                    Start-Sleep -Seconds 10
                }
            }
        }
        catch {
            $lastError = $_.Exception.Message
            WriteLog "ERROR: FFU optimization threw exception: $lastError"

            if ($attempt -lt $MaxRetries) {
                WriteLog "Waiting 10 seconds before retry..."
                Start-Sleep -Seconds 10
            }
        }
    }

    # Cleanup scratch directory
    WriteLog "Cleaning up scratch directory..."
    try {
        # Dismount any remaining VHDs
        Get-ChildItem -Path $scratchDir -Filter "*.vhd*" -ErrorAction SilentlyContinue | ForEach-Object {
            Dismount-VHD -Path $_.FullName -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 2
        Remove-Item $scratchDir -Recurse -Force -ErrorAction SilentlyContinue
        WriteLog "Scratch directory cleaned up"
    }
    catch {
        WriteLog "WARNING: Could not fully clean scratch directory: $($_.Exception.Message)"
    }

    if (-not $success) {
        # Log diagnostic information on failure
        WriteLog "============================================"
        WriteLog "FFU OPTIMIZATION FAILED - DIAGNOSTIC INFO"
        WriteLog "============================================"
        WriteLog "Last error: $lastError"
        WriteLog ""
        WriteLog "Possible causes:"
        WriteLog "  1. Antivirus scanning temporary VHD files"
        WriteLog "     Fix: Add exclusions for $FFUDevelopmentPath and .vhd/.ffu extensions"
        WriteLog ""
        WriteLog "  2. Windows Search indexing temporary files"
        WriteLog "     Fix: Exclude $FFUDevelopmentPath from Windows Search"
        WriteLog ""
        WriteLog "  3. Another process has the FFU file locked"
        WriteLog "     Fix: Close any applications that may have the FFU open"
        WriteLog ""
        WriteLog "  4. Insufficient disk space for temporary VHD"
        WriteLog "     Fix: Ensure at least 10GB free on $scratchDrive"
        WriteLog ""
        WriteLog "  5. DISM service conflict"
        WriteLog "     Fix: Restart and try again, or run dism /Cleanup-Mountpoints manually"
        WriteLog ""
        WriteLog "Recommended quick fix commands (run as Administrator):"
        WriteLog "  Add-MpPreference -ExclusionPath '$FFUDevelopmentPath'"
        WriteLog "  Add-MpPreference -ExclusionExtension '.vhd'"
        WriteLog "  Add-MpPreference -ExclusionExtension '.ffu'"
        WriteLog "  dism.exe /Cleanup-Mountpoints"
        WriteLog "============================================"

        throw "FFU optimization failed after $MaxRetries attempts. Last error: $lastError"
    }

    return $true
}

# Export module members
Export-ModuleMember -Function @(
    'Initialize-DISMService',
    'Test-WimSourceAccessibility',
    'Invoke-ExpandWindowsImageWithRetry',
    'Get-WimFromISO',
    'Get-Index',
    'New-ScratchVhdx',
    'New-SystemPartition',
    'New-MSRPartition',
    'New-OSPartition',
    'New-RecoveryPartition',
    'Add-BootFiles',
    'Enable-WindowsFeaturesByName',
    'Dismount-ScratchVhdx',
    'Optimize-FFUCaptureDrive',
    'Get-WindowsVersionInfo',
    'New-FFU',
    'Remove-FFU',
    'Start-RequiredServicesForDISM',
    'Invoke-FFUOptimizeWithScratchDir'
)