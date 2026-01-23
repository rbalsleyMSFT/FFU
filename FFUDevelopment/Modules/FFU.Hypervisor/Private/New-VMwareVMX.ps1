<#
.SYNOPSIS
    Creates a VMware VMX configuration file

.DESCRIPTION
    Generates a VMX file for VMware Workstation with the specified configuration.
    Supports Windows 10/11 guests with UEFI, Secure Boot, and vTPM.

.PARAMETER VMName
    Name of the virtual machine

.PARAMETER VMPath
    Path to the VM folder where VMX and other files will be stored

.PARAMETER MemoryMB
    Memory allocation in megabytes. Default 8192 (8GB).

.PARAMETER Processors
    Number of virtual CPUs. Default 4.

.PARAMETER DiskPath
    Path to the virtual disk file (VHD/VMDK)

.PARAMETER ISOPath
    Path to the boot ISO file (optional)

.PARAMETER NetworkType
    Network connection type: bridged, nat, hostonly, custom. Default bridged.

.PARAMETER EnableTPM
    Enable virtual TPM for Windows 11 compatibility. Default true.

.PARAMETER EnableSecureBoot
    Enable UEFI Secure Boot. Default true.

.PARAMETER GuestOS
    VMware guest OS identifier. Default windows11-64.

.PARAMETER NicType
    Virtual network adapter type. Options:
    - e1000e: Intel 82574L emulation (default, best WinPE compatibility)
    - vmxnet3: VMware paravirtual (higher performance, requires drivers)
    - e1000: Older Intel PRO/1000 MT emulation

.OUTPUTS
    [string] Path to the created VMX file

.EXAMPLE
    $vmxPath = New-VMwareVMX -VMName '_FFU-Build' -VMPath 'C:\VMs\FFU' -DiskPath 'C:\VMs\FFU\disk.vhd'

.NOTES
    Module: FFU.Hypervisor
    Version: 1.0.0

    VMX file format reference:
    https://docs.vmware.com/en/VMware-Workstation-Pro/17/com.vmware.ws.using.doc/GUID-FAAB4CF8-A92A-4F01-82B2-6F1E5F7DD916.html
#>

function New-VMwareVMX {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMName,

        [Parameter(Mandatory = $true)]
        [string]$VMPath,

        [Parameter(Mandatory = $false)]
        [int]$MemoryMB = 8192,

        [Parameter(Mandatory = $false)]
        [int]$Processors = 4,

        [Parameter(Mandatory = $false)]
        [string]$DiskPath,

        [Parameter(Mandatory = $false)]
        [string]$ISOPath,

        [Parameter(Mandatory = $false)]
        [ValidateSet('bridged', 'nat', 'hostonly', 'custom')]
        [string]$NetworkType = 'bridged',

        [Parameter(Mandatory = $false)]
        [bool]$EnableTPM = $true,

        [Parameter(Mandatory = $false)]
        [bool]$EnableSecureBoot = $true,

        [Parameter(Mandatory = $false)]
        [string]$GuestOS = 'windows11-64',

        [Parameter(Mandatory = $false)]
        [ValidateSet('e1000e', 'vmxnet3', 'e1000')]
        [string]$NicType = 'e1000e'
    )

    # Ensure VM folder exists
    if (-not (Test-Path $VMPath)) {
        New-Item -Path $VMPath -ItemType Directory -Force | Out-Null
    }

    # Generate VMX path
    $vmxPath = Join-Path $VMPath "$VMName.vmx"

    # Determine disk controller and path
    $diskController = 'scsi0'
    $diskDevice = 'scsi0:0'

    # Use relative path for disk if it's in the VM folder
    $relativeDiskPath = $DiskPath
    if ($DiskPath -and $DiskPath.StartsWith($VMPath)) {
        $relativeDiskPath = $DiskPath.Substring($VMPath.Length).TrimStart('\', '/')
    }

    # Build VMX content
    $vmxLines = @(
        '.encoding = "UTF-8"',
        'config.version = "8"',
        'virtualHW.version = "21"',  # VMware Workstation 17.x
        "displayName = `"$VMName`"",
        "guestOS = `"$GuestOS`"",
        "memsize = `"$MemoryMB`"",
        "numvcpus = `"$Processors`"",
        'cpuid.coresPerSocket = "2"',
        '',
        '# UEFI/EFI firmware',
        'firmware = "efi"',
        "uefi.secureBoot.enabled = `"$($EnableSecureBoot.ToString().ToUpper())`""
    )

    # Virtual TPM configuration
    # NOTE: VMware Workstation vTPM requires VM encryption to work properly.
    # The "managedvm.autoAddVTPM = software" experimental feature does NOT work
    # with vmrun.exe automation - it causes "operation was canceled" and
    # "Virtual TPM Initialization failed" errors.
    #
    # For FFU builds, TPM is not required during image capture. The final FFU
    # can be deployed to physical hardware with real TPM, and all TPM-dependent
    # features (BitLocker, Windows Hello) will work on the target device.
    #
    # FUTURE: To enable encrypted VM + vTPM support, implement:
    # 1. Encrypt VM using VMware encryption API
    # 2. Add vtpm.present = "TRUE" (not managedvm.autoAddVTPM)
    # 3. Use "vmrun -vp <password>" to start encrypted VMs
    # See: https://communities.vmware.com/t5/VMware-Workstation-Pro/Windows-11-and-vmrun/td-p/2897971
    if ($EnableTPM) {
        WriteLog "WARNING: vTPM requested but VMware vTPM requires VM encryption which breaks vmrun automation"
        WriteLog "Disabling vTPM for VMware VM - TPM features will work on target hardware after FFU deployment"
        $vmxLines += @(
            '',
            '# Virtual TPM - DISABLED for VMware automation compatibility',
            '# VMware vTPM requires VM encryption which breaks vmrun.exe',
            '# TPM features will work on target hardware after FFU deployment',
            'vtpm.present = "FALSE"'
        )
    }
    else {
        $vmxLines += @(
            '',
            '# Virtual TPM disabled per configuration',
            'vtpm.present = "FALSE"'
        )
    }

    # SCSI controller for disk
    $vmxLines += @(
        '',
        '# Storage controller',
        'scsi0.present = "TRUE"',
        'scsi0.virtualDev = "lsisas1068"'
    )

    # Virtual disk
    if ($DiskPath) {
        $vmxLines += @(
            '',
            '# Virtual disk',
            'scsi0:0.present = "TRUE"',
            "scsi0:0.fileName = `"$relativeDiskPath`"",
            'scsi0:0.mode = "persistent"'
        )

        # Detect disk type from extension
        if ($DiskPath -like '*.vmdk') {
            $vmxLines += 'scsi0:0.deviceType = "disk"'
        }
        else {
            # For VHD files, VMware needs special handling
            $vmxLines += @(
                'scsi0:0.deviceType = "disk"',
                '# Note: VHD files may require conversion to VMDK for optimal performance'
            )
        }
    }

    # CD-ROM / ISO
    $vmxLines += @(
        '',
        '# SATA controller for CD-ROM',
        'sata0.present = "TRUE"',
        'sata0:0.present = "TRUE"'
    )

    if ($ISOPath -and (Test-Path $ISOPath)) {
        $vmxLines += @(
            'sata0:0.deviceType = "cdrom-image"',
            "sata0:0.fileName = `"$ISOPath`"",
            'sata0:0.startConnected = "TRUE"'
        )
    }
    else {
        $vmxLines += @(
            'sata0:0.deviceType = "cdrom-raw"',
            'sata0:0.autodetect = "TRUE"',
            'sata0:0.startConnected = "FALSE"'
        )
    }

    # Network adapter
    # NicType determines the virtual NIC hardware:
    # - e1000e: Intel 82574L emulation (default, best WinPE compatibility)
    # - vmxnet3: VMware paravirtual (higher performance, requires vmxnet3 drivers)
    # - e1000: Older Intel PRO/1000 MT emulation
    $vmxLines += @(
        '',
        '# Network adapter',
        'ethernet0.present = "TRUE"',
        "ethernet0.connectionType = `"$NetworkType`"",
        "ethernet0.virtualDev = `"$NicType`"",
        'ethernet0.startConnected = "TRUE"',
        'ethernet0.addressType = "generated"',
        'ethernet0.wakeOnPcktRcv = "FALSE"'
    )

    # Boot options
    # FFU builds apply Windows to the VHD before VM boot - VM boots from hard drive, not ISO
    # HDD must be first in boot order for the VM to find the Windows installation
    $vmxLines += @(
        '',
        '# Boot options',
        '# IMPORTANT: HDD first - Windows is pre-installed on VHD before VM boot',
        'bios.bootOrder = "hdd,cdrom"',
        'bios.bootDelay = "0"'
    )

    # Power management and misc
    $vmxLines += @(
        '',
        '# Power management',
        'powerType.powerOff = "soft"',
        'powerType.powerOn = "soft"',
        'powerType.suspend = "soft"',
        'powerType.reset = "soft"',
        '',
        '# VM behavior',
        'tools.syncTime = "TRUE"',
        'tools.upgrade.policy = "manual"',
        'cleanShutdown = "TRUE"',
        'softPowerOff = "TRUE"',
        '',
        '# Display',
        '# IMPORTANT: Disable 3D acceleration for headless/nogui VM operation',
        '# vmrun start with "nogui" fails with "The operation was canceled" if 3D is enabled',
        'mks.enable3d = "FALSE"',
        'svga.vramSize = "8388608"',
        'svga.autodetect = "TRUE"',
        'svga.present = "TRUE"',
        '',
        '# USB controller',
        'usb.present = "TRUE"',
        'usb.generic.autoconnect = "FALSE"',
        'ehci.present = "TRUE"',
        'usb_xhci.present = "TRUE"',
        '',
        '# VMware Tools',
        'isolation.tools.hgfs.disable = "FALSE"',
        'isolation.tools.copy.disable = "FALSE"',
        'isolation.tools.paste.disable = "FALSE"',
        '',
        '# Hyper-V host compatibility',
        '# Disable side-channel mitigations popup on Hyper-V enabled hosts',
        '# See: https://knowledge.broadcom.com/external/article?legacyId=79832',
        'ulm.disableMitigations = "TRUE"',
        '',
        '# Miscellaneous',
        'pciBridge0.present = "TRUE"',
        'pciBridge4.present = "TRUE"',
        'pciBridge4.virtualDev = "pcieRootPort"',
        'pciBridge4.functions = "8"',
        'pciBridge5.present = "TRUE"',
        'pciBridge5.virtualDev = "pcieRootPort"',
        'pciBridge5.functions = "8"',
        'pciBridge6.present = "TRUE"',
        'pciBridge6.virtualDev = "pcieRootPort"',
        'pciBridge6.functions = "8"',
        'pciBridge7.present = "TRUE"',
        'pciBridge7.virtualDev = "pcieRootPort"',
        'pciBridge7.functions = "8"',
        'vmci0.present = "TRUE"',
        'hpet0.present = "TRUE"'
    )

    # Write VMX file
    $vmxContent = $vmxLines -join "`n"
    $vmxContent | Out-File -FilePath $vmxPath -Encoding UTF8 -Force

    WriteLog "Created VMX file: $vmxPath"
    return $vmxPath
}

<#
.SYNOPSIS
    Updates an existing VMX file with new settings
#>
function Update-VMwareVMX {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMXPath,

        [Parameter(Mandatory = $true)]
        [hashtable]$Settings
    )

    if (-not (Test-Path $VMXPath)) {
        throw "VMX file not found: $VMXPath"
    }

    # Read existing content
    $lines = Get-Content $VMXPath

    # Parse into hashtable
    $config = @{}
    foreach ($line in $lines) {
        if ($line -match '^([^=]+)\s*=\s*"?([^"]*)"?\s*$') {
            $key = $Matches[1].Trim()
            $value = $Matches[2].Trim()
            $config[$key] = $value
        }
    }

    # Apply new settings
    foreach ($key in $Settings.Keys) {
        $config[$key] = $Settings[$key]
    }

    # Write back
    $newLines = @()
    foreach ($key in $config.Keys | Sort-Object) {
        $value = $config[$key]
        $newLines += "$key = `"$value`""
    }

    # Write to file
    $newLines -join "`n" | Out-File -FilePath $VMXPath -Encoding UTF8 -Force

    # Force flush to disk to ensure changes are persisted before VM starts
    $fileStream = $null
    try {
        $fileStream = [System.IO.File]::Open($VMXPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $fileStream.Flush()
    }
    finally {
        if ($fileStream) {
            $fileStream.Close()
            $fileStream.Dispose()
        }
    }

    # Verify write succeeded by re-reading the file
    $verifyContent = Get-Content $VMXPath -Raw
    $settingsVerified = $true
    foreach ($key in $Settings.Keys) {
        $expectedValue = $Settings[$key]
        $escapedKey = [regex]::Escape($key)
        if ($verifyContent -notmatch "$escapedKey\s*=\s*`"$([regex]::Escape($expectedValue))`"") {
            WriteLog "WARNING: Setting '$key' may not have been written correctly"
            $settingsVerified = $false
        }
    }

    if ($settingsVerified) {
        WriteLog "Updated VMX file: $VMXPath (verified)"
    }
    else {
        WriteLog "Updated VMX file: $VMXPath (some settings may not have persisted)"
    }
}

<#
.SYNOPSIS
    Gets settings from a VMX file
#>
function Get-VMwareVMXSettings {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMXPath
    )

    if (-not (Test-Path $VMXPath)) {
        throw "VMX file not found: $VMXPath"
    }

    $config = @{}
    $lines = Get-Content $VMXPath

    foreach ($line in $lines) {
        # Skip comments and empty lines
        if ($line -match '^\s*#' -or [string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        if ($line -match '^([^=]+)\s*=\s*"?([^"]*)"?\s*$') {
            $key = $Matches[1].Trim()
            $value = $Matches[2].Trim()
            $config[$key] = $value
        }
    }

    return $config
}

<#
.SYNOPSIS
    Sets the boot ISO for a VMware VM and configures boot order to CD-ROM first

.DESCRIPTION
    Attaches an ISO file to the VM's SATA CD-ROM device and changes the BIOS boot order
    to boot from CD-ROM before hard disk. This is essential for WinPE capture scenarios
    where the VM must boot from the capture ISO rather than the pre-installed Windows.

.PARAMETER VMXPath
    Full path to the VMX configuration file

.PARAMETER ISOPath
    Full path to the ISO file to attach

.NOTES
    CRITICAL: Changes bios.bootOrder from "hdd,cdrom" to "cdrom,hdd" to ensure the VM
    boots from the ISO. Without this, the VM would boot Windows from the VHD and the
    WinPE capture script would never execute.
#>
function Set-VMwareBootISO {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMXPath,

        [Parameter(Mandatory = $true)]
        [string]$ISOPath
    )

    # Log current boot order before change for diagnostics
    if (Test-Path $VMXPath) {
        $currentVMX = Get-Content $VMXPath -Raw
        if ($currentVMX -match 'bios\.bootOrder\s*=\s*"([^"]*)"') {
            WriteLog "Current boot order: $($Matches[1])"
        }
        else {
            WriteLog "No explicit boot order found in VMX (using VMware default)"
        }
    }

    $settings = @{
        # Attach ISO to SATA CD-ROM device
        'sata0:0.deviceType'    = 'cdrom-image'
        'sata0:0.fileName'      = $ISOPath
        'sata0:0.startConnected' = 'TRUE'
        # CRITICAL: Set boot order to CD-ROM first for WinPE capture
        # This overrides the default "hdd,cdrom" set during VM creation
        'bios.bootOrder'        = 'cdrom,hdd'
    }

    Update-VMwareVMX -VMXPath $VMXPath -Settings $settings
    WriteLog "Set boot ISO to: $ISOPath"
    WriteLog "Changed boot order to: cdrom,hdd (CD-ROM first for WinPE capture)"
}

<#
.SYNOPSIS
    Removes the boot ISO from a VMware VM
#>
function Remove-VMwareBootISO {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMXPath
    )

    $settings = @{
        'sata0:0.deviceType' = 'cdrom-raw'
        'sata0:0.autodetect' = 'TRUE'
        'sata0:0.startConnected' = 'FALSE'
        'sata0:0.fileName' = ''
    }

    Update-VMwareVMX -VMXPath $VMXPath -Settings $settings
    WriteLog "Removed boot ISO"
}
