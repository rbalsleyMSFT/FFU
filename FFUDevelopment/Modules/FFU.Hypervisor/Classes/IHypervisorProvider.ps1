<#
.SYNOPSIS
    Abstract base class for hypervisor providers

.DESCRIPTION
    Defines the interface contract that all hypervisor providers must implement.
    Provides a common abstraction layer for VM operations across different
    hypervisor platforms (Hyper-V, VMware Workstation, etc.)

.NOTES
    Module: FFU.Hypervisor
    Version: 1.0.0

    This is implemented as a PowerShell class with abstract-like methods
    that throw NotImplementedException when called directly.
#>

class IHypervisorProvider {
    # Provider identity
    [string]$Name
    [string]$Version
    [string]$Description

    # Provider capabilities
    [hashtable]$Capabilities = @{
        SupportsTPM = $false
        SupportsSecureBoot = $false
        SupportsGeneration2 = $false
        SupportsDynamicMemory = $false
        SupportsCheckpoints = $false
        SupportsNestedVirtualization = $false
        SupportedDiskFormats = @()
        MaxMemoryGB = 0
        MaxProcessors = 0
    }

    # Default constructor
    IHypervisorProvider() {
        $this.Name = 'Unknown'
        $this.Version = '0.0.0'
        $this.Description = 'Base hypervisor provider'
    }

    #region VM Lifecycle Methods

    <#
    .SYNOPSIS
        Creates a new virtual machine
    .PARAMETER Config
        VMConfiguration object with VM parameters
    .RETURNS
        VMInfo object representing the created VM
    #>
    [VMInfo] CreateVM([VMConfiguration]$Config) {
        throw [System.NotImplementedException]::new("CreateVM must be implemented by derived provider")
    }

    <#
    .SYNOPSIS
        Starts a virtual machine
    .PARAMETER VM
        VMInfo object representing the VM to start
    .PARAMETER ShowConsole
        If true, display the VM console window (VMware only - Hyper-V always shows console)
        Default is false for headless/nogui operation during automated builds
    #>
    [void] StartVM([VMInfo]$VM) {
        # Default overload - runs headless
        $this.StartVM($VM, $false)
    }

    [void] StartVM([VMInfo]$VM, [bool]$ShowConsole) {
        throw [System.NotImplementedException]::new("StartVM must be implemented by derived provider")
    }

    <#
    .SYNOPSIS
        Stops a virtual machine
    .PARAMETER VM
        VMInfo object representing the VM to stop
    .PARAMETER Force
        If true, force stop the VM (equivalent to power off)
    #>
    [void] StopVM([VMInfo]$VM, [bool]$Force) {
        throw [System.NotImplementedException]::new("StopVM must be implemented by derived provider")
    }

    <#
    .SYNOPSIS
        Removes a virtual machine
    .PARAMETER VM
        VMInfo object representing the VM to remove
    .PARAMETER RemoveDisks
        If true, also remove associated virtual disks
    #>
    [void] RemoveVM([VMInfo]$VM, [bool]$RemoveDisks) {
        throw [System.NotImplementedException]::new("RemoveVM must be implemented by derived provider")
    }

    #endregion

    #region VM Information Methods

    <#
    .SYNOPSIS
        Gets the IP address of a virtual machine
    .PARAMETER VM
        VMInfo object representing the VM
    .RETURNS
        Primary IP address of the VM, or null if not available
    #>
    [string] GetVMIPAddress([VMInfo]$VM) {
        throw [System.NotImplementedException]::new("GetVMIPAddress must be implemented by derived provider")
    }

    <#
    .SYNOPSIS
        Gets the current state of a virtual machine
    .PARAMETER VM
        VMInfo object representing the VM
    .RETURNS
        VMState enum value
    #>
    [VMState] GetVMState([VMInfo]$VM) {
        throw [System.NotImplementedException]::new("GetVMState must be implemented by derived provider")
    }

    <#
    .SYNOPSIS
        Gets a VM by name
    .PARAMETER Name
        Name of the VM to find
    .RETURNS
        VMInfo object if found, null otherwise
    #>
    [VMInfo] GetVM([string]$Name) {
        throw [System.NotImplementedException]::new("GetVM must be implemented by derived provider")
    }

    <#
    .SYNOPSIS
        Lists all VMs managed by this provider
    .RETURNS
        Array of VMInfo objects
    #>
    [VMInfo[]] GetAllVMs() {
        throw [System.NotImplementedException]::new("GetAllVMs must be implemented by derived provider")
    }

    #endregion

    #region Disk Operations

    <#
    .SYNOPSIS
        Creates a new virtual disk
    .PARAMETER Path
        Full path for the new virtual disk file
    .PARAMETER SizeBytes
        Size of the virtual disk in bytes
    .PARAMETER Format
        Disk format (VHD, VHDX, VMDK)
    .PARAMETER Type
        Disk type (Dynamic or Fixed)
    .RETURNS
        Full path to the created virtual disk
    #>
    [string] NewVirtualDisk([string]$Path, [uint64]$SizeBytes, [string]$Format, [string]$Type) {
        throw [System.NotImplementedException]::new("NewVirtualDisk must be implemented by derived provider")
    }

    <#
    .SYNOPSIS
        Mounts a virtual disk to the host
    .PARAMETER Path
        Path to the virtual disk file
    .RETURNS
        Drive letter or mount point where the disk is mounted
    #>
    [string] MountVirtualDisk([string]$Path) {
        throw [System.NotImplementedException]::new("MountVirtualDisk must be implemented by derived provider")
    }

    <#
    .SYNOPSIS
        Dismounts a virtual disk from the host
    .PARAMETER Path
        Path to the virtual disk file
    #>
    [void] DismountVirtualDisk([string]$Path) {
        throw [System.NotImplementedException]::new("DismountVirtualDisk must be implemented by derived provider")
    }

    #endregion

    #region Media Operations

    <#
    .SYNOPSIS
        Attaches an ISO file to a VM
    .PARAMETER VM
        VMInfo object representing the VM
    .PARAMETER ISOPath
        Path to the ISO file to attach
    #>
    [void] AttachISO([VMInfo]$VM, [string]$ISOPath) {
        throw [System.NotImplementedException]::new("AttachISO must be implemented by derived provider")
    }

    <#
    .SYNOPSIS
        Detaches ISO from a VM
    .PARAMETER VM
        VMInfo object representing the VM
    #>
    [void] DetachISO([VMInfo]$VM) {
        throw [System.NotImplementedException]::new("DetachISO must be implemented by derived provider")
    }

    #endregion

    #region Availability Methods

    <#
    .SYNOPSIS
        Tests if this hypervisor is available on the current system
    .RETURNS
        True if the hypervisor is installed and functional
    #>
    [bool] TestAvailable() {
        throw [System.NotImplementedException]::new("TestAvailable must be implemented by derived provider")
    }

    <#
    .SYNOPSIS
        Gets the capabilities of this hypervisor provider
    .RETURNS
        Hashtable of capability flags and values
    #>
    [hashtable] GetCapabilities() {
        return $this.Capabilities
    }

    <#
    .SYNOPSIS
        Gets detailed availability information
    .RETURNS
        Hashtable with availability details and any issues found
    #>
    [hashtable] GetAvailabilityDetails() {
        return @{
            IsAvailable = $this.TestAvailable()
            ProviderName = $this.Name
            ProviderVersion = $this.Version
            Issues = @()
        }
    }

    #endregion

    #region Utility Methods

    <#
    .SYNOPSIS
        Validates a VMConfiguration for this provider
    .PARAMETER Config
        VMConfiguration to validate
    .RETURNS
        Hashtable with IsValid flag and any error messages
    #>
    [hashtable] ValidateConfiguration([VMConfiguration]$Config) {
        $result = @{
            IsValid = $true
            Errors = @()
            Warnings = @()
        }

        # Basic validation
        if (-not $Config.Validate()) {
            $result.IsValid = $false
            $result.Errors += "VMConfiguration basic validation failed"
        }

        # Check disk format support
        if ($Config.DiskFormat -notin $this.Capabilities.SupportedDiskFormats) {
            $result.IsValid = $false
            $result.Errors += "Disk format '$($Config.DiskFormat)' not supported by $($this.Name). Supported: $($this.Capabilities.SupportedDiskFormats -join ', ')"
        }

        # Check memory limits
        $memoryGB = $Config.GetMemoryGB()
        if ($this.Capabilities.MaxMemoryGB -gt 0 -and $memoryGB -gt $this.Capabilities.MaxMemoryGB) {
            $result.Warnings += "Memory $($memoryGB)GB exceeds recommended maximum $($this.Capabilities.MaxMemoryGB)GB"
        }

        # Check processor limits
        if ($this.Capabilities.MaxProcessors -gt 0 -and $Config.ProcessorCount -gt $this.Capabilities.MaxProcessors) {
            $result.Warnings += "Processor count $($Config.ProcessorCount) exceeds recommended maximum $($this.Capabilities.MaxProcessors)"
        }

        # Check TPM support
        if ($Config.EnableTPM -and -not $this.Capabilities.SupportsTPM) {
            $result.Warnings += "TPM requested but not supported by $($this.Name) - will be skipped"
        }

        # Check Generation 2 support
        if ($Config.Generation -eq 2 -and -not $this.Capabilities.SupportsGeneration2) {
            $result.IsValid = $false
            $result.Errors += "Generation 2 VMs not supported by $($this.Name)"
        }

        return $result
    }

    #endregion

    # String representation
    [string] ToString() {
        return "$($this.Name) v$($this.Version)"
    }
}
