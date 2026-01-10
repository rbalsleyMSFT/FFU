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
        $vhdFileName = [System.IO.Path]::GetFileName($Path)

        # First, test if Get-Disk is working
        $getDiskWorks = $true
        try {
            $null = Get-Disk -ErrorAction Stop | Select-Object -First 1
        }
        catch {
            if ($_.Exception.Message -match 'Invalid property') {
                WriteLog "WARNING: Get-Disk unavailable (WMI/Storage issue), using diskpart fallback"
                $getDiskWorks = $false
            }
        }

        $disk = $null
        if ($getDiskWorks) {
            # Find virtual disks (File Backed Virtual bus type)
            $disk = Get-Disk -ErrorAction SilentlyContinue | Where-Object {
                $_.BusType -eq 'File Backed Virtual' -and
                $_.FriendlyName -like "*$vhdFileName*"
            } | Select-Object -First 1

            # If not found by filename, try finding any recently attached virtual disk
            if (-not $disk) {
                $disk = Get-Disk -ErrorAction SilentlyContinue | Where-Object {
                    $_.BusType -eq 'File Backed Virtual' -and
                    $_.OperationalStatus -eq 'Online'
                } | Sort-Object Number -Descending | Select-Object -First 1
            }

            if ($disk) {
                $partition = Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue |
                    Where-Object { $_.DriveLetter } |
                    Select-Object -First 1

                if ($partition -and $partition.DriveLetter) {
                    return "$($partition.DriveLetter):"
                }
            }
        }
        else {
            # Fallback: Use diskpart to get vdisk detail
            if (Test-Path -Path $Path) {
                $detailScript = @"
select vdisk file="$Path"
detail vdisk
"@
                $detailScriptPath = Join-Path $env:TEMP "diskpart_driveLetter_$(Get-Random).txt"
                $detailScript | Out-File -FilePath $detailScriptPath -Encoding ASCII

                $detailOutput = & diskpart /s $detailScriptPath 2>&1 | Out-String
                Remove-Item -Path $detailScriptPath -Force -ErrorAction SilentlyContinue

                # Look for "Associated Disk" line to get disk number
                if ($detailOutput -match "Disk\s*:\s*Disk\s+(\d+)") {
                    $diskNumber = [int]$Matches[1]
                    WriteLog "Found disk $diskNumber for VHD via diskpart"

                    # Use diskpart to list volumes and find matching volume
                    $volScript = @"
select disk $diskNumber
list volume
"@
                    $volScriptPath = Join-Path $env:TEMP "diskpart_vol_$(Get-Random).txt"
                    $volScript | Out-File -FilePath $volScriptPath -Encoding ASCII

                    $volOutput = & diskpart /s $volScriptPath 2>&1 | Out-String
                    Remove-Item -Path $volScriptPath -Force -ErrorAction SilentlyContinue

                    # Parse volume output for drive letter
                    # Format: "  Volume 3     E   FFUDisk    NTFS   Partition    29 GB  Healthy"
                    if ($volOutput -match "Volume\s+\d+\s+([A-Z])\s+") {
                        $driveLetter = $Matches[1]
                        WriteLog "Found drive letter $driveLetter via diskpart"
                        return "$driveLetter`:"
                    }
                }
            }
        }

        return $null
    }
    catch {
        WriteLog "WARNING: Error finding VHD drive letter: $($_.Exception.Message)"
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
        $vhdFileName = [System.IO.Path]::GetFileName($Path)

        # First, test if Get-Disk is working
        $getDiskWorks = $true
        try {
            $null = Get-Disk -ErrorAction Stop | Select-Object -First 1
        }
        catch {
            if ($_.Exception.Message -match 'Invalid property') {
                WriteLog "WARNING: Get-Disk unavailable (WMI/Storage issue), using diskpart fallback"
                $getDiskWorks = $false
            }
        }

        if ($getDiskWorks) {
            # Find the disk by filename or by virtual disk type
            $disk = Get-Disk -ErrorAction SilentlyContinue | Where-Object {
                $_.BusType -eq 'File Backed Virtual' -and
                ($_.FriendlyName -like "*$vhdFileName*" -or $_.OperationalStatus -eq 'Online')
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
        else {
            # Fallback: Use diskpart to assign drive letter
            if (-not (Test-Path -Path $Path)) {
                WriteLog "WARNING: VHD file not found: $Path"
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

            # Use diskpart to assign drive letter
            $assignScript = @"
select vdisk file="$Path"
select partition 1
assign letter=$availableLetter
"@
            $assignScriptPath = Join-Path $env:TEMP "diskpart_assign_$(Get-Random).txt"
            $assignScript | Out-File -FilePath $assignScriptPath -Encoding ASCII

            $assignOutput = & diskpart /s $assignScriptPath 2>&1 | Out-String
            Remove-Item -Path $assignScriptPath -Force -ErrorAction SilentlyContinue

            WriteLog "diskpart assign output: $assignOutput"

            if ($assignOutput -match "successfully assigned") {
                WriteLog "Assigned drive letter $availableLetter via diskpart"
                return "$availableLetter`:"
            }
            else {
                WriteLog "WARNING: diskpart assign may have failed"
                return $null
            }
        }
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
    Creates a new VMDK file using VMware's vmware-vdiskmanager

.DESCRIPTION
    Creates a VMDK virtual disk using vmware-vdiskmanager.exe.
    This is the native VMware disk format and provides optimal performance
    for VMware Workstation VMs.

.PARAMETER Path
    Full path for the new VMDK file

.PARAMETER SizeGB
    Size of the VMDK in gigabytes

.PARAMETER Type
    Disk type: 'Dynamic' (growable/thin) or 'Fixed' (preallocated/thick). Default Dynamic.

.PARAMETER AdapterType
    Virtual adapter type: 'lsilogic', 'buslogic', 'ide'. Default lsilogic.

.PARAMETER VMwarePath
    Optional path to VMware Workstation installation directory.
    If not provided, auto-detects from registry/default paths.

.OUTPUTS
    [string] Path to the created VMDK file

.EXAMPLE
    $vmdkPath = New-VMDKWithVdiskmanager -Path 'C:\VMs\disk.vmdk' -SizeGB 128

.EXAMPLE
    $vmdkPath = New-VMDKWithVdiskmanager -Path 'C:\VMs\disk.vmdk' -SizeGB 256 -Type Fixed

.NOTES
    Module: FFU.Hypervisor
    Version: 1.0.1

    VMware vdiskmanager options:
    -c : create disk
    -s <size> : disk size (e.g., 128GB, 256MB)
    -a <adapter> : adapter type (ide, buslogic, lsilogic)
    -t <type> : disk type (0=single growable, 1=growable split, 2=preallocated, 3=preallocated split)
#>
function New-VMDKWithVdiskmanager {
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
        [ValidateSet('lsilogic', 'buslogic', 'ide')]
        [string]$AdapterType = 'lsilogic',

        [Parameter(Mandatory = $false)]
        [string]$VMwarePath
    )

    # Ensure parent directory exists
    $parentPath = Split-Path -Path $Path -Parent
    if (-not (Test-Path $parentPath)) {
        New-Item -Path $parentPath -ItemType Directory -Force | Out-Null
    }

    # Ensure .vmdk extension
    if (-not $Path.EndsWith('.vmdk', [StringComparison]::OrdinalIgnoreCase)) {
        $Path = "$Path.vmdk"
    }

    # Remove existing file if present
    if (Test-Path $Path) {
        WriteLog "Removing existing VMDK: $Path"
        Remove-Item -Path $Path -Force
        # Also remove any associated files (-flat.vmdk, -s*.vmdk)
        $basePath = [System.IO.Path]::ChangeExtension($Path, $null).TrimEnd('.')
        Get-ChildItem -Path $parentPath -Filter "$([System.IO.Path]::GetFileNameWithoutExtension($Path))*" -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }

    # Find vmware-vdiskmanager
    $vdiskManager = Get-VdiskmanagerPath -VMwarePath $VMwarePath

    if (-not $vdiskManager) {
        throw "vmware-vdiskmanager.exe not found. Please ensure VMware Workstation Pro is installed."
    }

    WriteLog "Found vmware-vdiskmanager: $vdiskManager"

    # Determine disk type number
    # Type 0: Single growable virtual disk (monolithic sparse) - RECOMMENDED for FFU
    # Type 1: Growable virtual disk split into 2GB files (split sparse)
    # Type 2: Preallocated virtual disk (monolithic flat)
    # Type 3: Preallocated virtual disk split into 2GB files (split flat)
    $diskTypeNum = if ($Type -eq 'Fixed') { 2 } else { 0 }

    # Build arguments
    $arguments = @(
        '-c',                           # Create disk
        '-s', "${SizeGB}GB",            # Size
        '-a', $AdapterType,             # Adapter type
        '-t', $diskTypeNum,             # Disk type
        "`"$Path`""                     # Output path
    )

    $argString = $arguments -join ' '
    WriteLog "Creating VMDK: $Path ($SizeGB GB, Type=$Type, Adapter=$AdapterType)"
    WriteLog "Executing: vmware-vdiskmanager $argString"

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $vdiskManager
        $psi.Arguments = $argString
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true

        $process = [System.Diagnostics.Process]::Start($psi)
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()

        if ($stdout) {
            WriteLog "vdiskmanager stdout: $($stdout.Trim())"
        }
        if ($stderr) {
            WriteLog "vdiskmanager stderr: $($stderr.Trim())"
        }
        WriteLog "vdiskmanager exit code: $($process.ExitCode)"

        if ($process.ExitCode -ne 0) {
            throw "vmware-vdiskmanager failed with exit code $($process.ExitCode): $stderr $stdout"
        }

        # Verify file was created
        if (-not (Test-Path $Path)) {
            throw "VMDK file was not created at $Path"
        }

        $fileSize = (Get-Item $Path).Length
        WriteLog "VMDK created successfully: $Path (file size: $([math]::Round($fileSize/1MB, 2)) MB)"
        return $Path
    }
    catch {
        WriteLog "ERROR: Failed to create VMDK: $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    Gets the path to vmware-vdiskmanager.exe

.DESCRIPTION
    Locates vmware-vdiskmanager.exe in the VMware Workstation installation directory.

.PARAMETER VMwarePath
    Optional path to VMware installation. If not provided, auto-detects.

.OUTPUTS
    [string] Full path to vmware-vdiskmanager.exe or $null if not found
#>
function Get-VdiskmanagerPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$VMwarePath
    )

    if ($VMwarePath) {
        $vdiskManager = Join-Path $VMwarePath 'vmware-vdiskmanager.exe'
        if (Test-Path $vdiskManager) {
            return $vdiskManager
        }
    }

    # Try registry first
    $regPaths = @(
        'HKLM:\SOFTWARE\VMware, Inc.\VMware Workstation',
        'HKLM:\SOFTWARE\WOW6432Node\VMware, Inc.\VMware Workstation'
    )

    foreach ($regPath in $regPaths) {
        if (Test-Path $regPath) {
            $installPath = (Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue).InstallPath
            if ($installPath) {
                $vdiskManager = Join-Path $installPath 'vmware-vdiskmanager.exe'
                if (Test-Path $vdiskManager) {
                    return $vdiskManager
                }
            }
        }
    }

    # Try default paths
    $defaultPaths = @(
        'C:\Program Files (x86)\VMware\VMware Workstation\vmware-vdiskmanager.exe',
        'C:\Program Files\VMware\VMware Workstation\vmware-vdiskmanager.exe'
    )

    foreach ($path in $defaultPaths) {
        if (Test-Path $path) {
            return $path
        }
    }

    return $null
}

<#
.SYNOPSIS
    Converts a VHD to VMDK format for VMware (DEPRECATED - Use New-VMDKWithVdiskmanager instead)

.DESCRIPTION
    This function is deprecated. VMware cannot boot from VHD files natively.
    Instead of converting, create VMDK disks directly using New-VMDKWithVdiskmanager.

    If you have an existing VHD that needs conversion, use qemu-img externally:
    qemu-img convert -f vpc -O vmdk input.vhd output.vmdk
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

    WriteLog "WARNING: Convert-VHDToVMDK is deprecated. VMware cannot boot from VHD files."
    WriteLog "Use New-VMDKWithVdiskmanager to create native VMDK disks instead."
    WriteLog "For existing VHD conversion, install qemu-img and run:"
    WriteLog "  qemu-img convert -f vpc -O vmdk `"$VHDPath`" `"$VMDKPath`""

    throw "VHD to VMDK conversion not supported. VMware requires native VMDK disks. Use New-VMDKWithVdiskmanager instead."
}
