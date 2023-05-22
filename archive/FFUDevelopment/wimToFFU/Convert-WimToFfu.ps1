#Requires -Modules Hyper-V, Storage
#Requires -PSEdition Desktop

<#
    .NOTES
        Copyright (c) Microsoft Corporation.
        Licensed under the MIT License.

    .SYNOPSIS
        Creates an FFU with proper disk layout given an input WIM

    .DESCRIPTION
        Creates an FFU with proper disk layout given an input WIM

    .PARAMETER WimPath
        The path to the WIM to be converted into an FFU

    .PARAMETER WimIndex
        The index of the image within the WIM to be used

    .PARAMETER FfuPath
        Output path of the FFU to be created

    .PARAMETER ScratchVhdxPath
        Output path of the scratch VHDX which will be created as an intermediate-step to the process of creating the FFU.

    .PARAMETER SaveScratchVhdx
        Keep the scratch VHDX after capturing the FFU. This VHDX can be used to create a VM for testing.

    .PARAMETER SizeBytes
        Size in bytes of the disk the FFU is to be applied to.
        With an Optimized FFU, the FFU can then be applied to any disk large enough for the data within the FFU.

    .PARAMETER LogicalSectorSizeBytes
        Logical sector size to store data within the FFU.
        This should match the logical sector size of the disks this FFU is applied to.

    .PARAMETER Dynamic
        Whether the scratch VHDX is to be a dynamically sized file or a fixed file size to match the maximum size of the VHDX.

    .PARAMETER PartitionStyle
        GPT or MBR partition style for the final disk layout.

    .PARAMETER SkipSystemPartition
        Skips creating a System partition. Boot files will be placed on the OS partition.

    .PARAMETER SystemPartitionSize
        If creating a System partition, specifies the size in bytes of that partition.

    .PARAMETER SkipMSRPartition
        Skips creating an MSR partition.

    .PARAMETER OSPartitionSize
        Allows the specification of the OS partition size. If left at default, the OS partition will take all available space,
        minus what is needed by the Recovery partition, if any.
        If a Data partition is specified, an OS partition size must be specified.

    .PARAMETER AddDataPartition
        Allows the addition of an extra Data partition, separate from the OS partition.

    .PARAMETER DataPartitionSize
        Allows specifying the size of the Data partition, if the -AddDataPartition flag is used.

    .PARAMETER SkipRecoveryPartition
        Skips the creation of a Recovery partition, used to store the Windows Recovery Environment (WinRE.wim).

    .PARAMETER RecoveryPartitionSize
        Specifies the size of the Recovery partition to be created.
        If left at default, the partition will be the size of the WinRE.wim in the OS partition plus 52 MB plus a buffer of 32 MB
        since free space of WinRE.wim + 52 MB is needed.

    .PARAMETER FFUDriveName
        Name passed to DISM's /Capture-FFU /Name parameter, used to set a name for the FFU, separate from the file name.

    .PARAMETER FFUCompression
        Specifies FFU compression of Default or None.

    .PARAMETER FirmwareType
        Specifies to create boot files for the disk for a firmware of BIOS, UEFI, or both (ALL).

    .PARAMETER OptimizeFfu
        Creates an Optimized FFU which can be applied to a disk of a different size than the original FFU disk size
        as long as the disk it is applied to is large enough to fit the data within the FFU.
        Optimized FFUs are only available on Windows version 1903 and higher.

    .PARAMETER Force
        Forces the overwriting of existing scratch VHDX or FFUs if the script is run multiple times
        or specifying a path with an existing VHDX or FFU of the same name.

    .EXAMPLE
        .\Convert-WimToFfu.ps1 -WimPath .\install.wim

        Creates an FFU named install.ffu in the same directory as the passed install.wim

    .EXAMPLE
        .\Convert-WimToFfu.ps1 -WimPath .\install.wim -WimIndex 1 -FfuPath .\flash.ffu

        Creates an FFU from the Windows image at index 1 within install.wim and names the FFU "flash.ffu"

    .EXAMPLE
        .\Convert-WimToFfu.ps1 -WimPath .\install.wim -WimIndex 1 -FfuPath .\flash.ffu -SizeBytes 64GB

        Creates an FFU that can only be applied on "64GB" disks.
        Keep in mind that 64GB is 68,719,476,736 bytes which may be larger than the target disks.

    .EXAMPLE
        .\Convert-WimToFfu.ps1 -WimPath .\install.wim -WimIndex 1 -FfuPath .\flash.ffu -OptimizeFfu
        Creates an FFU which can be applied to disks of a different size than the original FFU disk size.
#>

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [Alias("Path")]
    [ValidateScript({ Test-Path $_ })]
    [string]$WimPath,
    [uint32]$WimIndex = 1,
    [string]$FfuPath,
    [string]$ScratchVhdxPath,
    [switch]$SaveScratchVhdx,
    [uint64]$SizeBytes = 31000000000,
    [ValidateSet(512, 4096)]
    [uint32]$LogicalSectorSizeBytes = 512,
    [switch]$Dynamic,
    [Microsoft.PowerShell.Cmdletization.GeneratedTypes.Disk.PartitionStyle]$PartitionStyle = [Microsoft.PowerShell.Cmdletization.GeneratedTypes.Disk.PartitionStyle]::GPT,
    [switch]$SkipSystemPartition,
    [uint64]$SystemPartitionSize = 256MB,
    [switch]$SkipMSRPartition,
    [uint64]$OSPartitionSize = 0,
    [switch]$AddDataPartition,
    [uint64]$DataPartitionSize = 0,
    [switch]$SkipRecoveryPartition,
    [uint64]$RecoveryPartitionSize = 0,
    [string]$FFUDriveName = "WimToFfu",
    [ValidateSet("Default", "None")]
    [string]$FFUCompression = "Default",
    [ValidateSet("UEFI", "BIOS", "ALL")]
    [string]$FirmwareType = "UEFI",
    [switch]$OptimizeFFU,
    [switch]$Force
);

#region FUNCTIONS

function Add-BootFiles
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$OsPartitionDriveLetter,
        [Parameter(Mandatory = $true)]
        [string]$SystemPartitionDriveLetter
    );

    Write-Host "Adding boot files for `"$($OsPartitionDriveLetter):\Windows`" to System partition `"$($SystemPartitionDriveLetter):`"...";

    bcdboot "$($OsPartitionDriveLetter):\Windows" /S "$($SystemPartitionDriveLetter):" /F "$FirmwareType";

    Write-Host "Done.";
}

function Get-RecoveryPartition
{
    param(
        [Parameter(Mandatory = $true)]
        [ciminstance]$VhdxDisk,
        [Parameter(Mandatory = $true)]
        [ciminstance]$OsPartition,
        [uint64]$RecoveryPartitionSize = 0,
        [ciminstance]$DataPartition
    );

    Write-Host "Creating empty Recovery partition (to be filled on first boot automatically)...";
    
    $calculatedRecoverySize = 0;
    $recoveryPartition = $null;

    if($RecoveryPartitionSize -gt 0)
    {
        $calculatedRecoverySize = $RecoveryPartitionSize;
    }
    else
    {
        $winReWim = Get-ChildItem "$($OsPartition.DriveLetter):\Windows\System32\Recovery\Winre.wim";

        if(($winReWim -ne $null) -and ($winReWim.Count -eq 1))
        {
            # Wim size + 52MB is minimum WinRE partition size.
            # NTFS and other partitioning size differences account for about 17MB of space that's unavailable.
            # Adding 32MB as a buffer to ensure there's enough space.
            $calculatedRecoverySize = $winReWim.Length + 52MB + 32MB;

            Write-Host "Calculated space needed for recovery in bytes: $calculatedRecoverySize";

            if($DataPartition -ne $null)
            {
                $DataPartition | Resize-Partition -Size ($DataPartition.Size - $calculatedRecoverySize);
                Write-Host "Data partition shrunk by $calculatedRecoverySize bytes for Recovery partition.";
            }
            else
            {
                $OsPartition | Resize-Partition -Size ($OsPartition.Size - $calculatedRecoverySize);
                Write-Host "OS partition shrunk by $calculatedRecoverySize bytes for Recovery partition.";
            }

            $recoveryPartition = $VhdxDisk | New-Partition -AssignDriveLetter -UseMaximumSize -GptType "{de94bba4-06d1-4d40-a16a-bfd50179d6ac}" `
                | Format-Volume -FileSystem NTFS -Confirm:$false -Force -NewFileSystemLabel "WinRE";

            Write-Host "Done. Recovery partition at drive $($recoveryPartition.DriveLetter):";
        }
        else
        {
            Write-Host "No WinRE.WIM found in the OS partition under \Windows\System32\Recovery.";
            Write-Host "Skipping creating the Recovery partition.";
            Write-Host "If a Recovery partition is desired, please re-run the script setting the -RecoveryPartitionSize flag as appropriate."
        }
    }

    return $recoveryPartition;
}

function Get-DataPartition
{
    param(
        [Parameter(Mandatory = $true)]
        [ciminstance]$VhdxDisk,
        [uint64]$DataPartitionSize = 0
    );

    Write-Host "Creating Data partition...";
    
    $dataPartition = $null;

    if(($OSPartitionSize -ne $null) -and ($OSPartitionSize -gt 0))
    {
        if(($DataPartitionSize -ne $null) -and ($DataPartitionSize -gt 0))
        {
            $dataPartition = $vhdxDisk | New-Partition -AssignDriveLetter -Size $DataPartitionSize;
        }
        else
        {
            $dataPartition = $vhdxDisk | New-Partition -AssignDriveLetter -UseMaximumSize;
        }
    }
    else
    {
        Write-Host "To add a data partition, OS partition size must be set. Skipping adding data partition...";
    }

    Write-Host "Done. Data partition at drive $($dataPartition.DriveLetter):";

    return $dataPartition;
}

function Get-OSPartition
{
    param(
        [Parameter(Mandatory = $true)]
        [ciminstance]$VhdxDisk,
        [Parameter(Mandatory = $true)]
        [string]$WimPath,
        [uint32]$WimIndex = 1,
        [uint64]$OSPartitionSize = 0
    );

    Write-Host "Creating OS partition...";

    if($OSPartitionSize -gt 0)
    {
        $osPartition = $vhdxDisk | New-Partition -AssignDriveLetter -Size $OSPartitionSize;
    }
    else
    {
        $osPartition = $vhdxDisk | New-Partition -AssignDriveLetter -UseMaximumSize;
    }

    $formattedOsPartition = $osPartition | Format-Volume -FileSystem NTFS -Confirm:$false -Force -NewFileSystemLabel "Windows";
    Write-Host "Done. OS partition at drive $($osPartition.DriveLetter):";

    Write-Host "Writing WIM at $WimPath to OS partition at drive $($osPartition.DriveLetter):...";
    
    #Server 2019 is missing the Windows Overlay Filter (wof.sys), likely other Server SKUs are missing it as well. Script will error if trying to use the -compact switch on Server OSes
    if((Get-CimInstance Win32_OperatingSystem).Caption -match "Server"){
        Write-Host (Expand-WindowsImage -ImagePath $WimPath -Index $WimIndex -ApplyPath "$($osPartition.DriveLetter):\");
    }
    else {
        Write-Host (Expand-WindowsImage -ImagePath $WimPath -Index $WimIndex -ApplyPath "$($osPartition.DriveLetter):\" -Compact);
    }
    
    Write-Host "Done.";
    
    return $osPartition;
}

function Get-MSRPartition
{
    param(
        [Parameter(Mandatory = $true)]
        [ciminstance]$VhdxDisk
    );

    Write-Host "Creating MSR partition...";

    $toReturn = $VhdxDisk | New-Partition -AssignDriveLetter -Size 16MB -GptType "{e3c9e316-0b5c-4db8-817d-f92df00215ae}" -IsHidden;

    Write-Host "Done.";

    return $toReturn;
}

function Get-SystemPartition
{
    param(
        [Parameter(Mandatory = $true)]
        [ciminstance]$VhdxDisk,
        [uint64]$SystemPartitionSize = 100MB
    );

    Write-Host "Creating System partition...";

    $sysPartition = $VhdxDisk | New-Partition -AssignDriveLetter -Size $SystemPartitionSize -GptType "{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}" -IsHidden;
    $formattedSysPartition = $sysPartition | Format-Volume -FileSystem FAT32 -Force -NewFileSystemLabel "System";

    Write-Host "Done. System partition at drive $($sysPartition.DriveLetter):";
    return $sysPartition.DriveLetter;
}

function Dismount-ScratchVhdx
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$VhdxPath
    );

    if(Test-Path $VhdxPath)
    {
        Write-Host "Dismounting scratch VHDX...";
        Dismount-VHD -Path $VhdxPath;
        Write-Host "Done.";
    }
}

function Get-ScratchVhdx
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$VhdxPath,
        [uint64]$SizeBytes = 64000000000,
        [ValidateSet(512, 4096)]
        [uint32]$LogicalSectorSizeBytes = 512,
        [switch]$Dynamic,
        [Microsoft.PowerShell.Cmdletization.GeneratedTypes.Disk.PartitionStyle]$PartitionStyle = [Microsoft.PowerShell.Cmdletization.GeneratedTypes.Disk.PartitionStyle]::GPT,
        [switch]$AddRecoveryPartition,
        [uint64]$RecoveryPartitionSize = 0
    );

    Write-Host "Creating new Scratch VHDX...";

    $newVHDX = New-VHD -Path $VhdxPath -SizeBytes $SizeBytes -LogicalSectorSizeBytes $LogicalSectorSizeBytes -Dynamic:($Dynamic.IsPresent);
    $toReturn = $newVHDX | Mount-VHD -Passthru | Initialize-Disk -PassThru -PartitionStyle $PartitionStyle;

    Write-Host "Done.";
    return $toReturn;
}

function Get-OutputFilePath
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$WimPath,
        [string]$OutputFilePath,
        [Parameter(Mandatory = $true)]
        [string]$ParamName,
        [Parameter(Mandatory = $true)]
        [string]$Extension,
        [Parameter(Mandatory = $true)]
        [bool]$Force
    );

    if([string]::IsNullOrEmpty($OutputFilePath))
    {
        $OutputFilePath = [System.IO.Path]::ChangeExtension($WimPath, $Extension);
    }

    if((Test-Path $OutputFilePath) -and (-not $Force))
    {
        throw New-Object System.ArgumentException("Unable to overwrite existing file $OutputFilePath without -Force flag.", $ParamName);
    }

    return $OutputFilePath;
}

function Write-If
{
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,
        [Parameter(Mandatory = $true)]
        [string]$MessageIfTrue,
        [Parameter(Mandatory = $true)]
        [string]$MessageIfFalse
    );

    if($Condition)
    {
        Write-Host $MessageIfTrue;
    }
    else
    {
        Write-Host $MessageIfFalse;
    }
}

#endregion

#region MAIN SCRIPT BODY

#region PRINT INPUT PARAMETERS
Write-Host "Using WIM path: $WimPath.";

$FfuPath = Get-OutputFilePath -WimPath $WimPath -OutputFilePath $FfuPath -ParamName "FfuPath" -Extension "ffu" -Force $Force.IsPresent;
Write-Host "Using FFU path: $FfuPath.";

$ScratchVhdxPath = Get-OutputFilePath -WimPath $WimPath -OutputFilePath $ScratchVhdxPath -ParamName "ScratchVhdxPath" -Extension "vhdx" -Force $Force.IsPresent;
Write-Host "Using VHDX path: $ScratchVhdxPath.";

Write-Host "Using WIM Index: $WimIndex.";

Write-If -Condition $SaveScratchVhdx.IsPresent `
    -MessageIfTrue "Will save intermediate scratch VHDX." `
    -MessageIfFalse "Will delete intermediate scratch VHDX.";

Write-Host "Using Disk Size (bytes) of $SizeBytes.";
Write-Host "Using Logical Sector Size (bytes) of $LogicalSectorSizeBytes.";

Write-If -Condition $Dynamic.IsPresent `
    -MessageIfTrue "Intermediate scratch VHDX on disk will be Dynamically sized." `
    -MessageIfFalse "Intermediate scratch VHDX on disk will be Fixed sized.";

Write-Host "Partition style will be $PartitionStyle.";

Write-If -Condition $SkipSystemPartition.IsPresent `
    -MessageIfTrue "Will not add System partition." `
    -MessageIfFalse "Will add System partition of size (bytes) $SystemPartitionSize.";

Write-If -Condition $SkipMSRPartition.IsPresent `
    -MessageIfTrue "Will not add MSR partition." `
    -MessageIfFalse "Will add 16 MB MSR partition.";

Write-If -Condition ($OSPartitionSize -eq 0) `
    -MessageIfTrue "Will create maximum-sized OS partition." `
    -MessageIfFalse "Will create OS partition of size (bytes) $OSPartitionSize.";

Write-If -Condition $AddDataPartition.IsPresent `
    -MessageIfTrue "Will add extra Data partition of size (bytes) $DataPartitionSize." `
    -MessageIfFalse "Will not add extra Data partition.";

Write-If -Condition $SkipRecoveryPartition.IsPresent `
    -MessageIfTrue "Will not add Recovery partition." `
    -MessageIfFalse "Will add Recovery partition.";

Write-If -Condition $OptimizeFFU.IsPresent `
    -MessageIfTrue "Will run DISM's /Optimize-FFU command." `
    -MessageIfFalse "Will skip DISM's /Optimize-FFU command.";

if(-not ($SkipSystemPartition.IsPresent))
{
    if($RecoveryPartitionSize -eq 0)
    {
        Write-Host "Will use default, calculated Recovery partition size (WinRE.WIM size + 52 MB + plus a buffer of 32 MB due to NTFS).";
    }
    else
    {
        Write-Host "Will add Recovery partition of size (bytes) $RecoveryPartitionSize.";
    }
}

Write-Host "Using FFU Drive name of $FFUDriveName.";
Write-Host "Using FFU compression of $FFUCompression.";
Write-Host "Using Firmware Type (for boot files) of $FirmwareType.";

Write-If -Condition $Force.IsPresent `
    -MessageIfTrue "Force flag is present. Overwriting files when necessary." `
    -MessageIfFalse "Force flag is not present. Will not overwrite existing files.";

#endregion PRINT INPUT PARAMETERS

try
{
    $vhdxDisk = Get-ScratchVhdx -VhdxPath $ScratchVhdxPath -SizeBytes $SizeBytes -LogicalSectorSizeBytes $LogicalSectorSizeBytes -Dynamic:($Dynamic.IsPresent) -PartitionStyle $PartitionStyle;

    if(-not ($SkipSystemPartition.IsPresent))
    {
        $systemPartitionDriveLetter = Get-SystemPartition -VhdxDisk $vhdxDisk -SystemPartitionSize $SystemPartitionSize;
    }

    if(-not ($SkipMSRPartition.IsPresent))
    {
        $msrPartition = Get-MSRPartition -VhdxDisk $vhdxDisk;
    }

    $osPartition = Get-OSPartition -VhdxDisk $vhdxDisk -OSPartitionSize $OSPartitionSize -WimPath $WimPath -WimIndex $WimIndex;

    if($AddDataPartition.IsPresent)
    {
        $dataPartition = Get-DataPartition -VhdxDisk $vhdxDisk -DataPartitionSize $DataPartitionSize;
    }

    if(-not($SkipRecoveryPartition.IsPresent))
    {
        $recoveryPartition = Get-RecoveryPartition -VhdxDisk $vhdxDisk -OsPartition $osPartition -RecoveryPartitionSize $RecoveryPartitionSize -DataPartition $dataPartition;
    }

    Write-Host "All necessary partitions created.";

    if($SkipSystemPartition.IsPresent)
    {
        Add-BootFiles -OsPartitionDriveLetter $osPartition.DriveLetter -SystemPartitionDriveLetter $osPartition.DriveLetter;
    }
    else
    {
        Add-BootFiles -OsPartitionDriveLetter $osPartition.DriveLetter -SystemPartitionDriveLetter $systemPartitionDriveLetter;
    }

    Write-Host "Capturing scratch VHDX into FFU...";
    dism /Capture-FFU /ImageFile:"$FfuPath" /CaptureDrive:"\\.\PhysicalDrive$($vhdxDisk.DiskNumber)" /Name:"$FFUDriveName" /Compress:"$FFUCompression"
    Write-Host "Done.";
}
finally
{
    Dismount-ScratchVhdx -VhdxPath $ScratchVhdxPath;
}

if($SaveScratchVhdx.IsPresent)
{
    Write-Host "Scratch VHDX has been kept at $ScratchVhdxPath";
}
else
{
    Remove-Item -Path $ScratchVhdxPath -Force -Confirm:$false;
    Write-Host "Scratch VHDX has been deleted.";
}

if($OptimizeFFU.IsPresent)
{
    Write-Host "Running DISM /Optimize-FFU /ImageFile:$FfuPath...";
    dism /Optimize-FFU /ImageFile:"$FfuPath"
    Write-Host "Done.";
}
else
{
    Write-Host "Skipping running DISM /Optimize-FFU.";
}

Write-Host "Convert-WimToFfu.ps1 script complete.";

#endregion

