<#
.SYNOPSIS
    VM Configuration class for hypervisor-agnostic VM creation

.DESCRIPTION
    Defines the configuration parameters required to create a virtual machine
    across different hypervisor platforms (Hyper-V, VMware, etc.)

.NOTES
    Module: FFU.Hypervisor
    Version: 1.0.0
#>

class VMConfiguration {
    # Required properties
    [string]$Name
    [string]$Path
    [uint64]$MemoryBytes
    [int]$ProcessorCount
    [string]$VirtualDiskPath

    # Optional properties with defaults
    [int]$Generation = 2
    [bool]$EnableTPM = $true
    [bool]$EnableSecureBoot = $true
    [string]$GuestOS = 'windows11-64'
    [string]$NetworkType = 'External'
    [string]$NetworkSwitchName = $null
    [string]$ISOPath = $null
    [bool]$StartConnected = $true
    [bool]$AutomaticCheckpoints = $false
    [bool]$DynamicMemory = $false

    # Disk configuration
    [string]$DiskFormat = 'VHDX'  # VHDX or VHD
    [uint64]$DiskSizeBytes = 0    # 0 means use existing disk
    [string]$DiskType = 'Dynamic' # Dynamic or Fixed

    # Hidden tracking properties
    hidden [datetime]$CreatedAt
    hidden [string]$HypervisorType

    # Default constructor
    VMConfiguration() {
        $this.CreatedAt = Get-Date
    }

    # Constructor with required parameters
    VMConfiguration([string]$Name, [string]$Path, [uint64]$MemoryBytes, [int]$ProcessorCount, [string]$VirtualDiskPath) {
        $this.Name = $Name
        $this.Path = $Path
        $this.MemoryBytes = $MemoryBytes
        $this.ProcessorCount = $ProcessorCount
        $this.VirtualDiskPath = $VirtualDiskPath
        $this.CreatedAt = Get-Date

        # Auto-detect disk format from extension
        if ($VirtualDiskPath -like '*.vhd') {
            $this.DiskFormat = 'VHD'
        }
        elseif ($VirtualDiskPath -like '*.vhdx') {
            $this.DiskFormat = 'VHDX'
        }
        elseif ($VirtualDiskPath -like '*.vmdk') {
            $this.DiskFormat = 'VMDK'
        }
    }

    # Factory method for FFU Builder defaults
    static [VMConfiguration] NewFFUBuildVM([string]$Name, [string]$BasePath, [uint64]$MemoryBytes, [int]$ProcessorCount) {
        $config = [VMConfiguration]::new()
        $config.Name = $Name
        $config.Path = Join-Path $BasePath $Name
        $config.MemoryBytes = $MemoryBytes
        $config.ProcessorCount = $ProcessorCount
        $config.VirtualDiskPath = Join-Path $config.Path "$Name.vhdx"
        $config.DiskFormat = 'VHDX'
        $config.Generation = 2
        $config.EnableTPM = $true
        $config.EnableSecureBoot = $true
        $config.AutomaticCheckpoints = $false
        $config.DynamicMemory = $false
        return $config
    }

    # Validate configuration
    [bool] Validate() {
        $errors = @()

        if ([string]::IsNullOrWhiteSpace($this.Name)) {
            $errors += "VM Name is required"
        }

        if ([string]::IsNullOrWhiteSpace($this.Path)) {
            $errors += "VM Path is required"
        }

        if ($this.MemoryBytes -lt 2GB) {
            $errors += "Memory must be at least 2GB"
        }

        if ($this.ProcessorCount -lt 1) {
            $errors += "Processor count must be at least 1"
        }

        if ($this.Generation -notin @(1, 2)) {
            $errors += "Generation must be 1 or 2"
        }

        if ($this.DiskFormat -notin @('VHD', 'VHDX', 'VMDK')) {
            $errors += "DiskFormat must be VHD, VHDX, or VMDK"
        }

        if ($errors.Count -gt 0) {
            foreach ($error in $errors) {
                Write-Warning "VMConfiguration validation error: $error"
            }
            return $false
        }

        return $true
    }

    # Convert memory to MB for display
    [int] GetMemoryMB() {
        return [math]::Round($this.MemoryBytes / 1MB, 0)
    }

    # Convert memory to GB for display
    [double] GetMemoryGB() {
        return [math]::Round($this.MemoryBytes / 1GB, 2)
    }

    # String representation
    [string] ToString() {
        return "VMConfiguration: $($this.Name) [$($this.GetMemoryGB())GB RAM, $($this.ProcessorCount) CPUs, Gen$($this.Generation)]"
    }
}
