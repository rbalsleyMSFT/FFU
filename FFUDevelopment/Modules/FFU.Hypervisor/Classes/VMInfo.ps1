<#
.SYNOPSIS
    VM Information class for hypervisor-agnostic VM state tracking

.DESCRIPTION
    Represents the current state and properties of a virtual machine
    across different hypervisor platforms (Hyper-V, VMware, etc.)

.NOTES
    Module: FFU.Hypervisor
    Version: 1.0.0
#>

# Enum for VM state (common across hypervisors)
enum VMState {
    Unknown = 0
    Off = 1
    Running = 2
    Paused = 3
    Saved = 4
    Starting = 5
    Stopping = 6
    Saving = 7
    Restoring = 8
    Suspended = 9
}

class VMInfo {
    # Identity
    [string]$Id                      # Hypervisor-specific identifier
    [string]$Name                    # Display name
    [string]$HypervisorType          # 'HyperV' or 'VMware'

    # State
    [VMState]$State = [VMState]::Unknown
    [string]$StateDescription

    # Resources
    [uint64]$MemoryAssigned
    [int]$ProcessorCount
    [string]$IPAddress
    [string[]]$IPAddresses = @()

    # Paths
    [string]$ConfigurationPath       # VMX file for VMware, VM config for Hyper-V
    [string]$VirtualDiskPath

    # Timestamps
    [datetime]$CreatedTime
    [datetime]$LastStateChange

    # Hyper-V specific (populated when HypervisorType = 'HyperV')
    [Guid]$HyperVId
    [int]$Generation

    # VMware specific (populated when HypervisorType = 'VMware')
    [string]$VMwareId                # vmrest API ID
    [string]$VMXPath

    # Hidden tracking
    hidden [object]$NativeObject     # Original Hyper-V VM object or VMware response

    # Default constructor
    VMInfo() {
        $this.CreatedTime = Get-Date
        $this.LastStateChange = Get-Date
    }

    # Constructor from Hyper-V VM object
    VMInfo([object]$HyperVVM) {
        $this.Name = $HyperVVM.Name
        $this.HypervisorType = 'HyperV'
        $this.HyperVId = $HyperVVM.Id
        $this.Id = $HyperVVM.Id.ToString()
        $this.State = [VMInfo]::ConvertHyperVState($HyperVVM.State)
        $this.StateDescription = $HyperVVM.State.ToString()
        $this.MemoryAssigned = $HyperVVM.MemoryAssigned
        $this.ProcessorCount = $HyperVVM.ProcessorCount
        $this.ConfigurationPath = $HyperVVM.Path
        $this.Generation = $HyperVVM.Generation
        $this.CreatedTime = $HyperVVM.CreationTime
        $this.LastStateChange = Get-Date
        $this.NativeObject = $HyperVVM

        # Get IP addresses if VM is running
        if ($HyperVVM.State -eq 'Running') {
            try {
                $networkAdapters = Get-VMNetworkAdapter -VM $HyperVVM -ErrorAction SilentlyContinue
                if ($networkAdapters) {
                    $this.IPAddresses = $networkAdapters.IPAddresses | Where-Object { $_ -notmatch ':' }
                    if ($this.IPAddresses.Count -gt 0) {
                        $this.IPAddress = $this.IPAddresses[0]
                    }
                }
            }
            catch {
                # Ignore errors getting IP
            }
        }
    }

    # Static method to convert Hyper-V state enum to VMState
    static [VMState] ConvertHyperVState([object]$HyperVState) {
        $stateString = $HyperVState.ToString()
        switch ($stateString) {
            'Off' { return [VMState]::Off }
            'Running' { return [VMState]::Running }
            'Paused' { return [VMState]::Paused }
            'Saved' { return [VMState]::Saved }
            'Starting' { return [VMState]::Starting }
            'Stopping' { return [VMState]::Stopping }
            'Saving' { return [VMState]::Saving }
            'Restoring' { return [VMState]::Restoring }
        }
        return [VMState]::Unknown
    }

    # Static method to convert VMware power state
    static [VMState] ConvertVMwareState([string]$VMwarePowerState) {
        $stateString = $VMwarePowerState.ToLower()
        switch ($stateString) {
            'poweredoff' { return [VMState]::Off }
            'poweredon' { return [VMState]::Running }
            'suspended' { return [VMState]::Suspended }
        }
        return [VMState]::Unknown
    }

    # Check if VM is running
    [bool] IsRunning() {
        return $this.State -eq [VMState]::Running
    }

    # Check if VM is stopped
    [bool] IsStopped() {
        return $this.State -eq [VMState]::Off
    }

    # Refresh state from hypervisor
    [void] RefreshState() {
        $this.LastStateChange = Get-Date

        if ($this.HypervisorType -eq 'HyperV' -and $this.HyperVId) {
            try {
                $vm = Get-VM -Id $this.HyperVId -ErrorAction SilentlyContinue
                if ($vm) {
                    $this.State = [VMInfo]::ConvertHyperVState($vm.State)
                    $this.StateDescription = $vm.State.ToString()
                    $this.MemoryAssigned = $vm.MemoryAssigned
                    $this.NativeObject = $vm
                }
            }
            catch {
                $this.State = [VMState]::Unknown
                $this.StateDescription = "Error: $($_.Exception.Message)"
            }
        }
        # VMware refresh will be implemented in VMwareProvider
    }

    # String representation
    [string] ToString() {
        return "VMInfo: $($this.Name) [$($this.HypervisorType)] - $($this.State)"
    }

    # Get display-friendly state
    [string] GetStateDisplay() {
        if ($this.State -eq [VMState]::Running -and $this.IPAddress) {
            return "Running ($($this.IPAddress))"
        }
        return $this.State.ToString()
    }
}
