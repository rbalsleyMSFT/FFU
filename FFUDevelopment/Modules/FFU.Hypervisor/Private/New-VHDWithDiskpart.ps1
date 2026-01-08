<#
.SYNOPSIS
    VHD operations using diskpart (no Hyper-V dependency)

.DESCRIPTION
    Provides VHD create, mount, and dismount operations using diskpart.exe
    instead of Hyper-V cmdlets. This allows VMware provider to work on
    systems without Hyper-V installed.

.NOTES
    Module: FFU.Hypervisor
    Version: 1.0.0

    These functions require Administrator privileges.
#>

<#
.SYNOPSIS
    Creates a new VHD file using diskpart

.PARAMETER Path
    Full path for the new VHD file

.PARAMETER SizeGB
    Size of the VHD in gigabytes

.PARAMETER Type
    VHD type: 'Dynamic' (expandable) or 'Fixed'. Default Dynamic.

.PARAMETER Format
    File system format: 'NTFS' or 'GPT'. Default NTFS.

.PARAMETER Initialize
    If true, initializes and formats the disk. Default false.

.OUTPUTS
    [string] Path to the created VHD file

.EXAMPLE
    $vhdPath = New-VHDWithDiskpart -Path 'C:\VMs\disk.vhd' -SizeGB 128

.EXAMPLE
    $vhdPath = New-VHDWithDiskpart -Path 'C:\VMs\disk.vhd' -SizeGB 128 -Type Fixed -Initialize
#>
function New-VHDWithDiskpart {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [int]$SizeGB,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Dynamic', 'Fixed')]
        [string]$Type = 'Dynamic',

        [Parameter(Mandatory = $false)]
        [switch]$Initialize
    )

    # Ensure parent directory exists
    $parentPath = Split-Path -Path $Path -Parent
    if (-not (Test-Path $parentPath)) {
        New-Item -Path $parentPath -ItemType Directory -Force | Out-Null
    }

    # Ensure .vhd extension
    if (-not $Path.EndsWith('.vhd', [StringComparison]::OrdinalIgnoreCase)) {
        $Path = "$Path.vhd"
    }

    # Remove existing file if present
    if (Test-Path $Path) {
        Remove-Item -Path $Path -Force
    }

    # Calculate size in MB
    $sizeMB = $SizeGB * 1024

    # Build diskpart script
    $vhdType = if ($Type -eq 'Fixed') { 'fixed' } else { 'expandable' }

    $diskpartScript = @"
create vdisk file="$Path" maximum=$sizeMB type=$vhdType
"@

    if ($Initialize) {
        $diskpartScript += @"

select vdisk file="$Path"
attach vdisk
convert gpt
create partition primary
format fs=ntfs quick label="FFUDisk"
assign
detach vdisk
"@
    }

    # Write script to temp file
    $scriptPath = Join-Path $env:TEMP "diskpart_create_$(Get-Random).txt"
    $diskpartScript | Out-File -FilePath $scriptPath -Encoding ASCII

    try {
        WriteLog "Creating VHD: $Path ($SizeGB GB, $Type)"

        # Execute diskpart
        $result = & diskpart /s $scriptPath 2>&1

        if ($LASTEXITCODE -ne 0) {
            throw "diskpart failed with exit code $LASTEXITCODE : $result"
        }

        # Verify file was created
        if (-not (Test-Path $Path)) {
            throw "VHD file was not created at $Path"
        }

        WriteLog "VHD created successfully: $Path"
        return $Path
    }
    catch {
        WriteLog "ERROR: Failed to create VHD: $($_.Exception.Message)"
        throw
    }
    finally {
        Remove-Item -Path $scriptPath -Force -ErrorAction SilentlyContinue
    }
}

<#
.SYNOPSIS
    Mounts a VHD file and returns the drive letter

.PARAMETER Path
    Path to the VHD file to mount

.PARAMETER ReadOnly
    Mount as read-only. Default false.

.OUTPUTS
    [string] Drive letter where VHD is mounted (e.g., "V:")

.EXAMPLE
    $driveLetter = Mount-VHDWithDiskpart -Path 'C:\VMs\disk.vhd'
    # Returns: "V:"
#>
function Mount-VHDWithDiskpart {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [switch]$ReadOnly
    )

    if (-not (Test-Path $Path)) {
        throw "VHD file not found: $Path"
    }

    # Build diskpart script
    $readOnlyOption = if ($ReadOnly) { "readonly" } else { "" }

    $diskpartScript = @"
select vdisk file="$Path"
attach vdisk $readOnlyOption
"@

    # Write script to temp file
    $scriptPath = Join-Path $env:TEMP "diskpart_mount_$(Get-Random).txt"
    $diskpartScript | Out-File -FilePath $scriptPath -Encoding ASCII

    try {
        WriteLog "Mounting VHD: $Path"

        # Execute diskpart
        $result = & diskpart /s $scriptPath 2>&1

        if ($LASTEXITCODE -ne 0) {
            throw "diskpart mount failed: $result"
        }

        # Wait briefly for mount to complete
        Start-Sleep -Seconds 2

        # Find the drive letter
        $driveLetter = Get-VHDMountedDriveLetter -Path $Path

        if (-not $driveLetter) {
            # Try to assign a drive letter
            $driveLetter = Set-VHDDriveLetter -Path $Path
        }

        if (-not $driveLetter) {
            throw "VHD mounted but could not determine drive letter"
        }

        WriteLog "VHD mounted at: $driveLetter"
        return $driveLetter
    }
    catch {
        WriteLog "ERROR: Failed to mount VHD: $($_.Exception.Message)"
        throw
    }
    finally {
        Remove-Item -Path $scriptPath -Force -ErrorAction SilentlyContinue
    }
}

<#
.SYNOPSIS
    Dismounts a VHD file

.PARAMETER Path
    Path to the VHD file to dismount
#>
function Dismount-VHDWithDiskpart {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        WriteLog "WARNING: VHD file not found for dismount: $Path"
        return
    }

    $diskpartScript = @"
select vdisk file="$Path"
detach vdisk
"@

    # Write script to temp file
    $scriptPath = Join-Path $env:TEMP "diskpart_dismount_$(Get-Random).txt"
    $diskpartScript | Out-File -FilePath $scriptPath -Encoding ASCII

    try {
        WriteLog "Dismounting VHD: $Path"

        # Execute diskpart
        $result = & diskpart /s $scriptPath 2>&1

        if ($LASTEXITCODE -ne 0) {
            WriteLog "WARNING: diskpart detach returned non-zero: $result"
        }
        else {
            WriteLog "VHD dismounted successfully"
        }
    }
    catch {
        WriteLog "WARNING: Failed to dismount VHD: $($_.Exception.Message)"
    }
    finally {
        Remove-Item -Path $scriptPath -Force -ErrorAction SilentlyContinue
    }
}

<#
.SYNOPSIS
    Gets the drive letter for a mounted VHD
#>
function Get-VHDMountedDriveLetter {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        # Use Get-Disk to find mounted VHDs
        $disk = Get-Disk | Where-Object {
            $_.Location -eq $Path -or
            $_.FriendlyName -like "*$([System.IO.Path]::GetFileName($Path))*"
        } | Select-Object -First 1

        if ($disk) {
            $partition = Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue |
                Where-Object { $_.DriveLetter } |
                Select-Object -First 1

            if ($partition -and $partition.DriveLetter) {
                return "$($partition.DriveLetter):"
            }
        }

        # Fallback: check storage management
        $vdisk = Get-Disk -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $Path }
        if ($vdisk) {
            $part = $vdisk | Get-Partition -ErrorAction SilentlyContinue |
                Where-Object { $_.DriveLetter }
            if ($part) {
                return "$($part.DriveLetter):"
            }
        }

        return $null
    }
    catch {
        return $null
    }
}

<#
.SYNOPSIS
    Assigns a drive letter to a mounted VHD that doesn't have one
#>
function Set-VHDDriveLetter {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        # Find the disk
        $disk = Get-Disk | Where-Object {
            $_.Location -eq $Path -or
            $_.BusType -eq 'File Backed Virtual'
        } | Select-Object -First 1

        if (-not $disk) {
            WriteLog "WARNING: Could not find disk for VHD: $Path"
            return $null
        }

        # Find a partition without a drive letter
        $partition = Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue |
            Where-Object { $_.Type -notin @('Reserved', 'Unknown') } |
            Select-Object -First 1

        if (-not $partition) {
            WriteLog "WARNING: No suitable partition found on disk"
            return $null
        }

        # Find available drive letter
        $usedLetters = (Get-PSDrive -PSProvider FileSystem).Name
        $availableLetter = 68..90 | ForEach-Object { [char]$_ } |
            Where-Object { $_ -notin $usedLetters } |
            Select-Object -First 1

        if (-not $availableLetter) {
            WriteLog "WARNING: No available drive letters"
            return $null
        }

        # Assign drive letter
        Set-Partition -DiskNumber $disk.Number -PartitionNumber $partition.PartitionNumber `
            -NewDriveLetter $availableLetter -ErrorAction Stop

        return "$availableLetter`:"
    }
    catch {
        WriteLog "WARNING: Failed to assign drive letter: $($_.Exception.Message)"
        return $null
    }
}

<#
.SYNOPSIS
    Initializes a VHD with GPT partition table and NTFS format
#>
function Initialize-VHDWithDiskpart {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [string]$Label = 'FFUDisk',

        [Parameter(Mandatory = $false)]
        [char]$DriveLetter
    )

    if (-not (Test-Path $Path)) {
        throw "VHD file not found: $Path"
    }

    # Build diskpart script
    $assignLetter = if ($DriveLetter) { "assign letter=$DriveLetter" } else { "assign" }

    $diskpartScript = @"
select vdisk file="$Path"
attach vdisk
convert gpt
create partition primary
format fs=ntfs quick label="$Label"
$assignLetter
"@

    # Write script to temp file
    $scriptPath = Join-Path $env:TEMP "diskpart_init_$(Get-Random).txt"
    $diskpartScript | Out-File -FilePath $scriptPath -Encoding ASCII

    try {
        WriteLog "Initializing VHD: $Path"

        # Execute diskpart
        $result = & diskpart /s $scriptPath 2>&1

        if ($LASTEXITCODE -ne 0) {
            throw "diskpart initialization failed: $result"
        }

        WriteLog "VHD initialized successfully"

        # Return the drive letter
        return Get-VHDMountedDriveLetter -Path $Path
    }
    catch {
        WriteLog "ERROR: Failed to initialize VHD: $($_.Exception.Message)"
        throw
    }
    finally {
        Remove-Item -Path $scriptPath -Force -ErrorAction SilentlyContinue
    }
}

<#
.SYNOPSIS
    Converts a VHD to VMDK format for VMware
#>
function Convert-VHDToVMDK {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VHDPath,

        [Parameter(Mandatory = $false)]
        [string]$VMDKPath,

        [Parameter(Mandatory = $false)]
        [string]$VMwarePath
    )

    if (-not (Test-Path $VHDPath)) {
        throw "VHD file not found: $VHDPath"
    }

    # Determine output path
    if (-not $VMDKPath) {
        $VMDKPath = [System.IO.Path]::ChangeExtension($VHDPath, '.vmdk')
    }

    # Find vmware-vdiskmanager
    $vdiskManager = $null

    if ($VMwarePath) {
        $vdiskManager = Join-Path $VMwarePath 'vmware-vdiskmanager.exe'
    }
    else {
        $searchPaths = @(
            'C:\Program Files (x86)\VMware\VMware Workstation\vmware-vdiskmanager.exe',
            'C:\Program Files\VMware\VMware Workstation\vmware-vdiskmanager.exe'
        )

        foreach ($path in $searchPaths) {
            if (Test-Path $path) {
                $vdiskManager = $path
                break
            }
        }
    }

    if (-not $vdiskManager -or -not (Test-Path $vdiskManager)) {
        throw "vmware-vdiskmanager.exe not found. Please ensure VMware Workstation Pro is installed."
    }

    try {
        WriteLog "Converting VHD to VMDK: $VHDPath -> $VMDKPath"

        # Use vdiskmanager to create VMDK from raw disk
        # Note: This is a simplified approach - full conversion would require qemu-img or similar
        # For FFU Builder, we can use VHD directly with VMware

        # VMware can actually use VHD files directly if they're referenced correctly in VMX
        # But for best performance, we should convert
        # This is a placeholder for the conversion logic

        WriteLog "Note: Using VHD directly with VMware. For optimal performance, consider converting to VMDK."
        return $VHDPath
    }
    catch {
        WriteLog "ERROR: Failed to convert VHD to VMDK: $($_.Exception.Message)"
        throw
    }
}
