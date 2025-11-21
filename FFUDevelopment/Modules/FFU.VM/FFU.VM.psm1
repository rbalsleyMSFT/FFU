<#
.SYNOPSIS
    FFU Builder Hyper-V Virtual Machine Management Module

.DESCRIPTION
    Hyper-V virtual machine lifecycle management for FFU Builder.
    Provides VM creation, configuration, and cleanup operations for FFU build VMs.
    Handles VM networking, VHDX attachment, and environment validation.

.NOTES
    Module: FFU.VM
    Version: 1.0.0
    Dependencies: FFU.Core (for WriteLog function and common variables)
    Requires: Administrator privileges and Hyper-V feature enabled
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

function New-FFUVM {
    <#
    .SYNOPSIS
    Creates a new Generation 2 Hyper-V virtual machine for FFU build process

    .DESCRIPTION
    Creates and configures a new Hyper-V VM with TPM, mounts the Apps ISO,
    configures boot settings, and starts the VM with vmconnect.

    .PARAMETER VMName
    Name of the virtual machine to create

    .PARAMETER VMPath
    Path where the VM configuration files will be stored

    .PARAMETER Memory
    Memory allocation for the VM in bytes (e.g., 8GB = 8589934592)

    .PARAMETER VHDXPath
    Path to the VHDX file to attach to the VM

    .PARAMETER Processors
    Number of virtual processors to assign to the VM

    .PARAMETER AppsISO
    Path to the Apps ISO file to mount to the VM

    .EXAMPLE
    New-FFUVM -VMName "_FFU-Build-Win11" -VMPath "C:\FFU\VM" -Memory 8GB `
              -VHDXPath "C:\FFU\VM\disk.vhdx" -Processors 4 -AppsISO "C:\FFU\Apps.iso"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMName,

        [Parameter(Mandatory = $true)]
        [string]$VMPath,

        [Parameter(Mandatory = $true)]
        [uint64]$Memory,

        [Parameter(Mandatory = $true)]
        [string]$VHDXPath,

        [Parameter(Mandatory = $true)]
        [int]$Processors,

        [Parameter(Mandatory = $true)]
        [string]$AppsISO
    )

    #Create new Gen2 VM
    $VM = New-VM -Name $VMName -Path $VMPath -MemoryStartupBytes $Memory -VHDPath $VHDXPath -Generation 2
    Set-VMProcessor -VMName $VMName -Count $Processors

    #Mount AppsISO
    Add-VMDvdDrive -VMName $VMName -Path $AppsISO

    #Set Hard Drive as boot device
    $VMHardDiskDrive = Get-VMHarddiskdrive -VMName $VMName
    Set-VMFirmware -VMName $VMName -FirstBootDevice $VMHardDiskDrive
    Set-VM -Name $VMName -AutomaticCheckpointsEnabled $false -StaticMemory

    #Configure TPM
    New-HgsGuardian -Name $VMName -GenerateCertificates
    $owner = get-hgsguardian -Name $VMName
    $kp = New-HgsKeyProtector -Owner $owner -AllowUntrustedRoot
    Set-VMKeyProtector -VMName $VMName -KeyProtector $kp.RawData
    Enable-VMTPM -VMName $VMName

    #Connect to VM
    WriteLog "Starting vmconnect localhost $VMName"
    & vmconnect localhost "$VMName"

    #Start VM
    Start-VM -Name $VMName

    return $VM
}

function Remove-FFUVM {
    <#
    .SYNOPSIS
    Removes FFU build VM and associated resources

    .DESCRIPTION
    Removes the Hyper-V VM, HGS Guardian, certificates, VHDX files, and cleans up
    orphaned mounted images. Can be called with or without VMName for different
    cleanup scenarios.

    .PARAMETER VMName
    Optional name of the VM to remove. If not specified, only VHDX cleanup is performed.

    .PARAMETER VMPath
    Path to the VM configuration directory to remove

    .PARAMETER InstallApps
    Boolean indicating if apps were installed (affects cleanup behavior)

    .PARAMETER VhdxDisk
    VHDX disk object for cleanup validation

    .PARAMETER FFUDevelopmentPath
    Root FFUDevelopment path for mount folder cleanup

    .EXAMPLE
    Remove-FFUVM -VMName "_FFU-Build-Win11" -VMPath "C:\FFU\VM\_FFU-Build-Win11" `
                 -InstallApps $true -VhdxDisk $disk -FFUDevelopmentPath "C:\FFU"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$VMName,

        [Parameter(Mandatory = $true)]
        [string]$VMPath,

        [Parameter(Mandatory = $true)]
        [bool]$InstallApps,

        [Parameter(Mandatory = $false)]
        $VhdxDisk,

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
    If (-not $InstallApps -and $VhdxDisk) {
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
    If (Test-Path -Path "$FFUDevelopmentPath\Mount") {
        WriteLog "Remove $FFUDevelopmentPath\Mount folder"
        Remove-Item -Path "$FFUDevelopmentPath\Mount" -Recurse -Force
        WriteLog 'Folder removed'
    }
    #Remove unused mountpoints
    WriteLog 'Remove unused mountpoints'
    Invoke-Process cmd "/c mountvol /r" | Out-Null
    WriteLog 'Removal complete'
}

function Get-FFUEnvironment {
    <#
    .SYNOPSIS
    Cleans up FFU build environment after failed or incomplete builds

    .DESCRIPTION
    Performs comprehensive environment cleanup including VMs, VHDXs, mounted images,
    stale downloads, user accounts, and temporary files. Called when dirty.txt is detected
    or when explicit cleanup is requested.

    .PARAMETER FFUDevelopmentPath
    Root FFUDevelopment path

    .PARAMETER CleanupCurrentRunDownloads
    Boolean indicating whether to clean up current run downloads

    .PARAMETER VMLocation
    Path to VM storage location (defaults to FFUDevelopmentPath\VM if not provided)

    .PARAMETER UserName
    FFU user account name to remove

    .PARAMETER RemoveApps
    Boolean indicating whether to remove Apps folder

    .PARAMETER AppsPath
    Path to Apps folder

    .PARAMETER RemoveUpdates
    Boolean indicating whether to remove Updates folder

    .PARAMETER KBPath
    Path to KB updates folder

    .PARAMETER AppsISO
    Path to Apps ISO file

    .EXAMPLE
    Get-FFUEnvironment -FFUDevelopmentPath "C:\FFU" -CleanupCurrentRunDownloads $true `
                       -VMLocation "C:\FFU\VM" -UserName "ffu_user" -RemoveApps $false `
                       -AppsPath "C:\FFU\Apps" -RemoveUpdates $false -KBPath "C:\FFU\KB" `
                       -AppsISO "C:\FFU\Apps.iso"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath,

        [Parameter(Mandatory = $true)]
        [bool]$CleanupCurrentRunDownloads,

        [Parameter(Mandatory = $false)]
        [string]$VMLocation,

        [Parameter(Mandatory = $true)]
        [string]$UserName,

        [Parameter(Mandatory = $true)]
        [bool]$RemoveApps,

        [Parameter(Mandatory = $true)]
        [string]$AppsPath,

        [Parameter(Mandatory = $true)]
        [bool]$RemoveUpdates,

        [Parameter(Mandatory = $true)]
        [string]$KBPath,

        [Parameter(Mandatory = $true)]
        [string]$AppsISO
    )

    WriteLog 'Dirty.txt file detected. Last run did not complete succesfully. Will clean environment'
    try {
        Remove-InProgressItems -FFUDevelopmentPath $FFUDevelopmentPath `
                              -DriversFolder "$FFUDevelopmentPath\Drivers" `
                              -OfficePath "$FFUDevelopmentPath\Office"
    }
    catch {
        WriteLog "Remove-InProgressItems failed: $($_.Exception.Message)"
    }
    if ($CleanupCurrentRunDownloads) {
        try {
            Cleanup-CurrentRunDownloads -FFUDevelopmentPath $FFUDevelopmentPath `
                                       -AppsPath $AppsPath -DefenderPath "$FFUDevelopmentPath\Defender" `
                                       -MSRTPath "$FFUDevelopmentPath\MSRT" -OneDrivePath "$FFUDevelopmentPath\OneDrive" `
                                       -EdgePath "$FFUDevelopmentPath\Edge" -KBPath $KBPath `
                                       -DriversFolder "$FFUDevelopmentPath\Drivers" `
                                       -orchestrationPath "$FFUDevelopmentPath\Orchestration" `
                                       -OfficePath "$FFUDevelopmentPath\Office"
        }
        catch {
            WriteLog "Cleanup-CurrentRunDownloads failed: $($_.Exception.Message)"
        }
        try {
            Restore-RunJsonBackups -FFUDevelopmentPath $FFUDevelopmentPath `
                                  -DriversFolder "$FFUDevelopmentPath\Drivers" `
                                  -orchestrationPath "$FFUDevelopmentPath\Orchestration"
        }
        catch {
            WriteLog "Restore-RunJsonBackups failed: $($_.Exception.Message)"
        }
    }
    # Check for running VMs that start with '_FFU-' and are in the 'Off' state
    $vms = Get-VM

    # Loop through each VM
    foreach ($vm in $vms) {
        if ($vm.Name.StartsWith("_FFU-")) {
            if ($vm.State -eq 'Running') {
                Stop-VM -Name $vm.Name -TurnOff -Force
            }
            # If conditions are met, delete the VM
            # Note: For old VMs we may not have VMPath, so we derive it
            $vmPath = Join-Path $FFUDevelopmentPath "VM\$($vm.Name)"
            Remove-FFUVM -VMName $vm.Name -VMPath $vmPath -InstallApps $true `
                         -VhdxDisk $null -FFUDevelopmentPath $FFUDevelopmentPath
        }
    }
    # Check for MSFT Virtual disks where location contains FFUDevelopment in the path
    $disks = Get-Disk -FriendlyName *virtual*
    foreach ($disk in $disks) {
        $diskNumber = $disk.Number
        $vhdLocation = $disk.Location
        if ($vhdLocation -like "*FFUDevelopment*") {
            WriteLog "Dismounting Virtual Disk $diskNumber with Location $vhdLocation"
            Dismount-ScratchVhdx -VhdxPath $vhdLocation
            $parentFolder = Split-Path -Parent $vhdLocation
            WriteLog "Removing folder $parentFolder"
            Remove-Item -Path $parentFolder -Recurse -Force
        }
    }

    # Check for mounted DiskImages
    $volumes = Get-Volume | Where-Object { $_.DriveType -eq 'CD-ROM' }
    foreach ($volume in $volumes) {
        $letter = $volume.DriveLetter
        WriteLog "Dismounting DiskImage for volume $letter"
        Get-Volume $letter | Get-DiskImage | Dismount-DiskImage | Out-Null
        WriteLog "Dismounting complete"
    }

    # Remove unused mountpoints
    WriteLog 'Remove unused mountpoints'
    Invoke-Process cmd "/c mountvol /r" | Out-Null
    WriteLog 'Removal complete'

    # Check for content in the VM folder and delete any folders that start with _FFU-
    if ([string]::IsNullOrWhiteSpace($VMLocation)) {
        $VMLocation = Join-Path $FFUDevelopmentPath 'VM'
        WriteLog "VMLocation not set; defaulting to $VMLocation"
    }
    if (Test-Path -Path $VMLocation) {
        $folders = Get-ChildItem -Path $VMLocation -Directory
        foreach ($folder in $folders) {
            if ($folder.Name -like '_FFU-*') {
                WriteLog "Removing folder $($folder.FullName)"
                Remove-Item -Path $folder.FullName -Recurse -Force
            }
        }
    }
    else {
        WriteLog "VMLocation path $VMLocation not found; skipping VM folder cleanup"
    }

    # Remove orphaned mounted images
    $mountedImages = Get-WindowsImage -Mounted
    if ($mountedImages) {
        foreach ($image in $mountedImages) {
            $mountPath = $image.Path
            WriteLog "Dismounting image at $mountPath"
            try {
                Dismount-WindowsImage -Path $mountPath -discard | Out-null
                WriteLog "Successfully dismounted image at $mountPath"
            }
            catch {
                WriteLog "Failed to dismount image at $mountPath with error: $_"
            }
        }
    }

    # Remove Mount folder if it exists
    if (Test-Path -Path "$FFUDevelopmentPath\Mount") {
        WriteLog "Remove $FFUDevelopmentPath\Mount folder"
        Remove-Item -Path "$FFUDevelopmentPath\Mount" -Recurse -Force
        WriteLog 'Folder removed'
    }

    #Clear any corrupt Windows mount points
    WriteLog 'Clearing any corrupt Windows mount points'
    Clear-WindowsCorruptMountPoint | Out-null
    WriteLog 'Complete'

    #Clean up registry
    if (Test-Path -Path 'HKLM:\FFU') {
        Writelog 'Found HKLM:\FFU, removing it'
        Invoke-Process reg "unload HKLM\FFU" | Out-Null
    }

    #Remove FFU User and Share
    $UserExists = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
    if ($UserExists) {
        WriteLog "Removing FFU User and Share"
        Remove-FFUUserShare
        WriteLog 'Removal complete'
    }
    if ($RemoveApps) {
        WriteLog "Removing Apps in $AppsPath"
        Remove-Apps
    }
    #Remove updates
    if ($RemoveUpdates) {
        WriteLog "Removing updates"
        Remove-Updates
    }
    #Clean up $KBPath
    If (Test-Path -Path $KBPath) {
        WriteLog "Removing $KBPath"
        Remove-Item -Path $KBPath -Recurse -Force -ErrorAction SilentlyContinue
        WriteLog 'Removal complete'
    }
    # Remove existing Apps.iso
    if (Test-Path -Path $AppsISO) {
        WriteLog "Removing $AppsISO"
        Remove-Item -Path $AppsISO -Force -ErrorAction SilentlyContinue
        WriteLog 'Removal complete'
    }
    # Remove per-run session folder if present (Cancel/-Cleanup scenario)
    $sessionDir = Join-Path $FFUDevelopmentPath '.session'
    if (Test-Path -Path $sessionDir) {
        WriteLog 'Removing .session folder'
        Remove-Item -Path $sessionDir -Recurse -Force -ErrorAction SilentlyContinue
        WriteLog 'Removal complete'
    }
    WriteLog 'Removing dirty.txt file'
    Remove-Item -Path "$FFUDevelopmentPath\dirty.txt" -Force
    WriteLog "Cleanup complete"
}

# Export module members
Export-ModuleMember -Function @(
    'New-FFUVM',
    'Remove-FFUVM',
    'Get-FFUEnvironment'
)