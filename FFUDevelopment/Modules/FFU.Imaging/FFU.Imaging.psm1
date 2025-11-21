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

function Get-WimFromISO {
    #Mount ISO, get Wim file
    $mountResult = Mount-DiskImage -ImagePath $isoPath -PassThru
    $sourcesFolder = ($mountResult | Get-Volume).DriveLetter + ":\sources\"

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
    param(
        [Parameter(Mandatory = $true)]
        [string]$WindowsImagePath,

        [Parameter(Mandatory = $true)]
        [string]$WindowsSKU
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

    $newVHDX = New-VHD -Path $VhdxPath -SizeBytes $disksize -LogicalSectorSizeBytes $LogicalSectorSizeBytes -Dynamic:($Dynamic.IsPresent)
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
    param(
        [Parameter(Mandatory = $true)]
        [ciminstance]$VhdxDisk,
        [Parameter(Mandatory = $true)]
        [string]$WimPath,
        [uint32]$WimIndex,
        [uint64]$OSPartitionSize = 0
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

    #Server 2019 is missing the Windows Overlay Filter (wof.sys), likely other Server SKUs are missing it as well. Script will error if trying to use the -compact switch on Server OSes
    if ((Get-CimInstance Win32_OperatingSystem).Caption -match "Server") {
        WriteLog (Expand-WindowsImage -ImagePath $WimPath -Index $WimIndex -ApplyPath "$($osPartition.DriveLetter):\")
    }
    elseif ($CompactOS) {
        WriteLog '$CompactOS is set to true, using -Compact switch to apply the WIM file to the OS partition.'
        WriteLog (Expand-WindowsImage -ImagePath $WimPath -Index $WimIndex -ApplyPath "$($osPartition.DriveLetter):\" -Compact)
    }
    else {
        WriteLog (Expand-WindowsImage -ImagePath $WimPath -Index $WimIndex -ApplyPath "$($osPartition.DriveLetter):\")
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
    param (
        [Parameter(Mandatory = $true)]
        [string]$FeatureNames,
        [Parameter(Mandatory = $true)]
        [string]$Source
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

function New-FFU {
    param (
        [Parameter(Mandatory = $false)]
        [string]$VMName
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
            Start-Sleep -Seconds 5
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
        $winverinfo = Get-WindowsVersionInfo
        WriteLog 'Creating FFU File Name'
        if ($CustomFFUNameTemplate) {
            $FFUFileName = New-FFUFileName
        }
        else {
            $FFUFileName = "$($winverinfo.Name)`_$($winverinfo.DisplayVersion)`_$($shortenedWindowsSKU)`_$($winverinfo.BuildDate).ffu"
        }
        WriteLog "FFU file name: $FFUFileName"
        $FFUFile = "$FFUCaptureLocation\$FFUFileName"
        #Capture the FFU
        Set-Progress -Percentage 68 -Message "Capturing FFU from VHDX..."
        WriteLog 'Capturing FFU'
        Invoke-Process cmd "/c ""$DandIEnv"" && dism /Capture-FFU /ImageFile:$FFUFile /CaptureDrive:\\.\PhysicalDrive$($vhdxDisk.DiskNumber) /Name:$($winverinfo.Name)$($winverinfo.DisplayVersion)$($shortenedWindowsSKU) /Compress:Default" | Out-Null
        WriteLog 'FFU Capture complete'
        Dismount-ScratchVhdx -VhdxPath $VHDXPath
    }
    elseif (-not $InstallApps -and $AllowVHDXCaching) {
        # Make $FFUFileName based on values in the config.json file
        WriteLog 'Creating FFU File Name'
        if ($CustomFFUNameTemplate) {
            $FFUFileName = New-FFUFileName
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
        Invoke-Process cmd "/c ""$DandIEnv"" && dism /Capture-FFU /ImageFile:$FFUFile /CaptureDrive:\\.\PhysicalDrive$($vhdxDisk.DiskNumber) /Name:$($cachedVHDXInfo.WindowsRelease)$($cachedVHDXInfo.WindowsVersion)$($shortenedWindowsSKU) /Compress:Default" | Out-Null
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
        WriteLog "Creating $FFUDevelopmentPath\Mount directory"
        New-Item -Path "$FFUDevelopmentPath\Mount" -ItemType Directory -Force | Out-Null
        WriteLog "Created $FFUDevelopmentPath\Mount directory"

        # Ensure required Windows services are running for DISM operations
        Start-RequiredServicesForDISM

        WriteLog "Mounting $FFUFile to $FFUDevelopmentPath\Mount"
        Mount-WindowsImage -ImagePath $FFUFile -Index 1 -Path "$FFUDevelopmentPath\Mount" | Out-null
        WriteLog 'Mounting complete'
        WriteLog 'Adding drivers - This will take a few minutes, please be patient'
        try {
            Add-WindowsDriver -Path "$FFUDevelopmentPath\Mount" -Driver "$DriversFolder" -Recurse -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Out-null
        }
        catch {
            WriteLog 'Some drivers failed to be added to the FFU. This can be expected. Continuing.'
        }
        WriteLog 'Adding drivers complete'
        WriteLog "Dismount $FFUDevelopmentPath\Mount"
        Dismount-WindowsImage -Path "$FFUDevelopmentPath\Mount" -Save | Out-Null
        WriteLog 'Dismount complete'
        WriteLog "Remove $FFUDevelopmentPath\Mount folder"
        Remove-Item -Path "$FFUDevelopmentPath\Mount" -Recurse -Force | Out-null
        WriteLog 'Folder removed'
    }
    #Optimize FFU
    if ($Optimize -eq $true) {
        Set-Progress -Percentage 85 -Message "Optimizing FFU..."
        WriteLog 'Optimizing FFU - This will take a few minutes, please be patient'
        #Need to use ADK version of DISM to address bug in DISM - perhaps Windows 11 24H2 will fix this
        Invoke-Process cmd "/c ""$DandIEnv"" && dism /optimize-ffu /imagefile:$FFUFile" | Out-Null
        #Invoke-Process cmd "/c dism /optimize-ffu /imagefile:$FFUFile" | Out-Null
        WriteLog 'Optimizing FFU complete'
        Set-Progress -Percentage 90 -Message "FFU post-processing complete."
    }


}

function Remove-FFU {
    param (
        [Parameter(Mandatory = $false)]
        [string]$VMName
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
        Remove-Item -Path $VMPath -Force -Recurse
        WriteLog 'Removal complete'
        WriteLog "Removing HGSGuardian for $VMName"
        Remove-HgsGuardian -Name $VMName -WarningAction SilentlyContinue
        WriteLog 'Removal complete'
        WriteLog 'Cleaning up HGS Guardian certs'
        $certs = Get-ChildItem -Path $certPath -Recurse | Where-Object { $_.Subject -like "*$VMName*" }
        foreach ($cert in $Certs) {
            Remove-item -Path $cert.PSPath -force | Out-Null
        }
        WriteLog 'Cert removal complete'
    }
    #If just building the FFU from vhdx, remove the vhdx path
    If (-not $InstallApps -and $vhdxDisk) {
        WriteLog 'Cleaning up VHDX'
        WriteLog "Removing $VMPath"
        Remove-Item -Path $VMPath -Force -Recurse | Out-Null
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
        Remove-Item -Path "$FFUDevelopmentPath\Mount" -Recurse -Force
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
                $maxRetries = 3
                $serviceReady = $false

                while ($retryCount -lt $maxRetries -and -not $serviceReady) {
                    $service = Get-Service -Name $svc.Name
                    if ($service.Status -eq 'Running') {
                        WriteLog "Service '$($svc.DisplayName)' started successfully"
                        $serviceReady = $true
                    }
                    else {
                        $retryCount++
                        WriteLog "Service status: $($service.Status), waiting 2 more seconds (retry $retryCount/$maxRetries)..."
                        Start-Sleep -Seconds 2
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
        WriteLog 'Waiting additional 3 seconds for DISM subsystem initialization...'
        Start-Sleep -Seconds 3
        WriteLog 'DISM subsystem should be ready'
    }

    return $allServicesOk
}

# Export module members
Export-ModuleMember -Function @(
    'Initialize-DISMService',
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
    'New-FFU',
    'Remove-FFU',
    'Start-RequiredServicesForDISM'
)