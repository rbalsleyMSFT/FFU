<#
.SYNOPSIS
    Creates a new VMConfiguration object for hypervisor-agnostic VM creation

.DESCRIPTION
    Factory function that creates and configures a VMConfiguration object.
    This function exists to work around PowerShell's limitation that module-defined
    classes are not accessible from scripts that import the module.

    Instead of using [VMConfiguration]::new() directly, callers should use:
    $config = New-VMConfiguration -Name "MyVM" -Path "C:\VMs" ...

.PARAMETER Name
    Name of the virtual machine

.PARAMETER Path
    Path where the VM configuration files will be stored

.PARAMETER MemoryBytes
    Amount of RAM in bytes for the VM (e.g., 4GB, 8589934592)

.PARAMETER ProcessorCount
    Number of virtual processors for the VM

.PARAMETER VirtualDiskPath
    Full path to the virtual hard disk file (VHDX, VHD, or VMDK)

.PARAMETER ISOPath
    Optional path to an ISO file to mount as a DVD drive

.PARAMETER Generation
    VM generation (1 or 2). Default is 2.

.PARAMETER EnableTPM
    Enable TPM for the VM. Default is $true.

.PARAMETER EnableSecureBoot
    Enable Secure Boot for the VM. Default is $true.

.PARAMETER DiskFormat
    Format of the virtual disk (VHD, VHDX, or VMDK). Auto-detected from VirtualDiskPath if not specified.

.PARAMETER DynamicMemory
    Enable dynamic memory. Default is $false (static memory).

.PARAMETER AutomaticCheckpoints
    Enable automatic checkpoints. Default is $false.

.EXAMPLE
    $config = New-VMConfiguration -Name "FFU-Build" -Path "C:\VMs\FFU" `
                                  -MemoryBytes 8GB -ProcessorCount 4 `
                                  -VirtualDiskPath "C:\VMs\FFU\FFU-Build.vhdx"

.EXAMPLE
    # For FFU Builder, create a standard build VM configuration
    $config = New-VMConfiguration -Name $VMName -Path $VMPath `
                                  -MemoryBytes $memory -ProcessorCount $processors `
                                  -VirtualDiskPath $VHDXPath -ISOPath $AppsISO

.OUTPUTS
    VMConfiguration

.NOTES
    Module: FFU.Hypervisor
    Version: 1.0.0

    This function is required because PowerShell classes defined in modules cannot
    be directly instantiated from scripts that import the module. The class type
    is not exported to the caller's scope.
#>
function New-VMConfiguration {
    [CmdletBinding()]
    # Note: OutputType omitted because VMConfiguration class is not accessible in caller's scope
    # The function returns a VMConfiguration object, but we cannot declare it with [OutputType]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateRange(2GB, 1TB)]
        [uint64]$MemoryBytes,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 64)]
        [int]$ProcessorCount,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$VirtualDiskPath,

        [Parameter(Mandatory = $false)]
        [string]$ISOPath,

        [Parameter(Mandatory = $false)]
        [ValidateSet(1, 2)]
        [int]$Generation = 2,

        [Parameter(Mandatory = $false)]
        [bool]$EnableTPM = $true,

        [Parameter(Mandatory = $false)]
        [bool]$EnableSecureBoot = $true,

        [Parameter(Mandatory = $false)]
        [ValidateSet('VHD', 'VHDX', 'VMDK')]
        [string]$DiskFormat,

        [Parameter(Mandatory = $false)]
        [bool]$DynamicMemory = $false,

        [Parameter(Mandatory = $false)]
        [bool]$AutomaticCheckpoints = $false
    )

    process {
        # Create new VMConfiguration instance
        $config = [VMConfiguration]::new()

        # Set required properties
        $config.Name = $Name
        $config.Path = $Path
        $config.MemoryBytes = $MemoryBytes
        $config.ProcessorCount = $ProcessorCount
        $config.VirtualDiskPath = $VirtualDiskPath

        # Set optional properties
        if ($PSBoundParameters.ContainsKey('ISOPath') -and -not [string]::IsNullOrEmpty($ISOPath)) {
            $config.ISOPath = $ISOPath
        }

        $config.Generation = $Generation
        $config.EnableTPM = $EnableTPM
        $config.EnableSecureBoot = $EnableSecureBoot
        $config.DynamicMemory = $DynamicMemory
        $config.AutomaticCheckpoints = $AutomaticCheckpoints

        # Set disk format - auto-detect from path if not specified
        if ($PSBoundParameters.ContainsKey('DiskFormat')) {
            $config.DiskFormat = $DiskFormat
        }
        else {
            # Auto-detect from file extension
            if ($VirtualDiskPath -like '*.vhd') {
                $config.DiskFormat = 'VHD'
            }
            elseif ($VirtualDiskPath -like '*.vhdx') {
                $config.DiskFormat = 'VHDX'
            }
            elseif ($VirtualDiskPath -like '*.vmdk') {
                $config.DiskFormat = 'VMDK'
            }
            else {
                # Default to VHDX for unknown extensions
                $config.DiskFormat = 'VHDX'
            }
        }

        return $config
    }
}
