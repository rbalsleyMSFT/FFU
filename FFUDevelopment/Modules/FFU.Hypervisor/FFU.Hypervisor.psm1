<#
.SYNOPSIS
    FFU Builder Hypervisor Abstraction Module

.DESCRIPTION
    Provides a unified abstraction layer for hypervisor operations in FFU Builder.
    Supports multiple hypervisor backends (Hyper-V, VMware Workstation) through
    a provider pattern, allowing the same code to work across different platforms.

.NOTES
    Module: FFU.Hypervisor
    Version: 1.0.0

    Module Structure:
    - Classes/           - Core classes (IHypervisorProvider, VMConfiguration, VMInfo)
    - Providers/         - Provider implementations (HyperVProvider, VMwareProvider)
    - Private/           - Internal helper functions
    - Public/            - Exported public functions
#>

#Requires -Version 7.0

# Get module paths
$script:ModuleRoot = $PSScriptRoot
$script:ClassesPath = Join-Path $ModuleRoot 'Classes'
$script:ProvidersPath = Join-Path $ModuleRoot 'Providers'
$script:PrivatePath = Join-Path $ModuleRoot 'Private'
$script:PublicPath = Join-Path $ModuleRoot 'Public'

#region Load Classes (order matters - dependencies first)

# Load VMConfiguration class first (no dependencies)
. (Join-Path $ClassesPath 'VMConfiguration.ps1')

# Load VMInfo class (depends on VMState enum defined within it)
. (Join-Path $ClassesPath 'VMInfo.ps1')

# Load IHypervisorProvider interface (depends on VMConfiguration, VMInfo)
. (Join-Path $ClassesPath 'IHypervisorProvider.ps1')

#endregion

#region Load Private Functions (load before providers)

# Load private helper functions (if any exist)
# These are loaded first because providers may depend on them
$privateFunctions = Get-ChildItem -Path $PrivatePath -Filter '*.ps1' -ErrorAction SilentlyContinue
foreach ($function in $privateFunctions) {
    try {
        . $function.FullName
    }
    catch {
        Write-Warning "Failed to load private function $($function.Name): $($_.Exception.Message)"
    }
}

#endregion

#region Load Providers (depend on classes and private functions)

# Load Hyper-V provider
. (Join-Path $ProvidersPath 'HyperVProvider.ps1')

# Load VMware provider (Milestone 2)
. (Join-Path $ProvidersPath 'VMwareProvider.ps1')

#endregion

#region Load Public Functions

# Load public functions
$publicFunctions = Get-ChildItem -Path $PublicPath -Filter '*.ps1' -ErrorAction SilentlyContinue
foreach ($function in $publicFunctions) {
    try {
        . $function.FullName
    }
    catch {
        Write-Warning "Failed to load public function $($function.Name): $($_.Exception.Message)"
    }
}

#endregion

#region Wrapper Functions for Provider Interface

<#
.SYNOPSIS
    Creates a new VM using the specified or default hypervisor provider

.PARAMETER Config
    VMConfiguration object with VM parameters

.PARAMETER HypervisorType
    Type of hypervisor to use ('HyperV', 'VMware', or 'Auto')

.EXAMPLE
    $config = [VMConfiguration]::NewFFUBuildVM('_FFU-Build', 'C:\FFU\VM', 8GB, 4)
    $vm = New-HypervisorVM -Config $config
#>
function New-HypervisorVM {
    [CmdletBinding()]
    [OutputType([VMInfo])]
    param(
        [Parameter(Mandatory = $true)]
        [VMConfiguration]$Config,

        [Parameter(Mandatory = $false)]
        [ValidateSet('HyperV', 'VMware', 'Auto')]
        [string]$HypervisorType = 'Auto'
    )

    $provider = Get-HypervisorProvider -Type $HypervisorType -Validate
    return $provider.CreateVM($Config)
}

<#
.SYNOPSIS
    Starts a VM using the appropriate hypervisor provider

.PARAMETER ShowConsole
    When true, displays the VM console window during startup (VMware only).
    When false (default), runs the VM in headless/nogui mode for automation.
    For Hyper-V, use Hyper-V Manager to view the VM console.
#>
function Start-HypervisorVM {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [VMInfo]$VM,

        [Parameter(Mandatory = $false)]
        [bool]$ShowConsole = $false
    )

    $provider = Get-HypervisorProvider -Type $VM.HypervisorType
    $provider.StartVM($VM, $ShowConsole)
}

<#
.SYNOPSIS
    Stops a VM using the appropriate hypervisor provider
#>
function Stop-HypervisorVM {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [VMInfo]$VM,

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    $provider = Get-HypervisorProvider -Type $VM.HypervisorType
    $provider.StopVM($VM, $Force.IsPresent)
}

<#
.SYNOPSIS
    Removes a VM using the appropriate hypervisor provider
#>
function Remove-HypervisorVM {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [VMInfo]$VM,

        [Parameter(Mandatory = $false)]
        [switch]$RemoveDisks
    )

    $provider = Get-HypervisorProvider -Type $VM.HypervisorType
    $provider.RemoveVM($VM, $RemoveDisks.IsPresent)
}

<#
.SYNOPSIS
    Gets the IP address of a VM
#>
function Get-HypervisorVMIPAddress {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [VMInfo]$VM
    )

    $provider = Get-HypervisorProvider -Type $VM.HypervisorType
    return $provider.GetVMIPAddress($VM)
}

<#
.SYNOPSIS
    Gets the current state of a VM
#>
function Get-HypervisorVMState {
    [CmdletBinding()]
    [OutputType([VMState])]
    param(
        [Parameter(Mandatory = $true)]
        [VMInfo]$VM
    )

    $provider = Get-HypervisorProvider -Type $VM.HypervisorType
    return $provider.GetVMState($VM)
}

<#
.SYNOPSIS
    Creates a new virtual disk
#>
function New-HypervisorVirtualDisk {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [uint64]$SizeBytes,

        [Parameter(Mandatory = $false)]
        [ValidateSet('VHD', 'VHDX', 'VMDK')]
        [string]$Format = 'VHDX',

        [Parameter(Mandatory = $false)]
        [ValidateSet('Dynamic', 'Fixed')]
        [string]$Type = 'Dynamic',

        [Parameter(Mandatory = $false)]
        [ValidateSet('HyperV', 'VMware', 'Auto')]
        [string]$HypervisorType = 'Auto'
    )

    $provider = Get-HypervisorProvider -Type $HypervisorType -Validate
    return $provider.NewVirtualDisk($Path, $SizeBytes, $Format, $Type)
}

<#
.SYNOPSIS
    Mounts a virtual disk to the host
#>
function Mount-HypervisorVirtualDisk {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [ValidateSet('HyperV', 'VMware', 'Auto')]
        [string]$HypervisorType = 'Auto'
    )

    $provider = Get-HypervisorProvider -Type $HypervisorType -Validate
    return $provider.MountVirtualDisk($Path)
}

<#
.SYNOPSIS
    Dismounts a virtual disk from the host
#>
function Dismount-HypervisorVirtualDisk {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [ValidateSet('HyperV', 'VMware', 'Auto')]
        [string]$HypervisorType = 'Auto'
    )

    $provider = Get-HypervisorProvider -Type $HypervisorType -Validate
    $provider.DismountVirtualDisk($Path)
}

<#
.SYNOPSIS
    Attaches an ISO/DVD to a VM
#>
function Add-HypervisorVMDvdDrive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [VMInfo]$VM,

        [Parameter(Mandatory = $true)]
        [string]$ISOPath
    )

    $provider = Get-HypervisorProvider -Type $VM.HypervisorType
    $provider.AttachISO($VM, $ISOPath)
}

<#
.SYNOPSIS
    Removes ISO/DVD from a VM
#>
function Remove-HypervisorVMDvdDrive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [VMInfo]$VM
    )

    $provider = Get-HypervisorProvider -Type $VM.HypervisorType
    $provider.DetachISO($VM)
}

#endregion

#region Factory Functions for Cross-Scope Type Access

<#
.SYNOPSIS
    Returns a VMState enum value by name

.DESCRIPTION
    Factory function to get VMState enum values from outside the module.
    PowerShell module classes and enums aren't automatically exported to the caller's scope,
    so this function provides access to VMState values.

.PARAMETER State
    The state name: Unknown, Off, Running, Paused, Saved, Starting, Stopping, Saving, Restoring, Suspended

.EXAMPLE
    $offState = Get-VMStateValue -State 'Off'
    if ($vmState -eq $offState) { Write-Host "VM is off" }
#>
function Get-VMStateValue {
    [CmdletBinding()]
    [OutputType([VMState])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Unknown', 'Off', 'Running', 'Paused', 'Saved', 'Starting', 'Stopping', 'Saving', 'Restoring', 'Suspended')]
        [string]$State
    )

    return [VMState]::$State
}

<#
.SYNOPSIS
    Tests if a VM state equals Off

.DESCRIPTION
    Helper function to check if a VMState value equals Off without requiring
    direct access to the [VMState] enum type. Accepts any object type to avoid
    cross-scope type resolution issues in PowerShell background jobs.

.PARAMETER State
    The VMState value to test (from GetVMState or Get-HypervisorVMState)

.EXAMPLE
    $state = $provider.GetVMState($VM)
    if (Test-VMStateOff -State $state) { Write-Host "VM is off" }
#>
function Test-VMStateOff {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        # Use [object] instead of [VMState] to avoid type resolution errors in cross-scope calls
        # PowerShell module types aren't exported to the caller's scope
        [object]$State
    )

    # Compare by value (handles both enum and string comparisons)
    return $State -eq [VMState]::Off -or $State.ToString() -eq 'Off'
}

<#
.SYNOPSIS
    Tests if a VM state equals Running

.DESCRIPTION
    Helper function to check if a VMState value equals Running without requiring
    direct access to the [VMState] enum type. Accepts any object type to avoid
    cross-scope type resolution issues in PowerShell background jobs.

.PARAMETER State
    The VMState value to test (from GetVMState or Get-HypervisorVMState)

.EXAMPLE
    $state = $provider.GetVMState($VM)
    if (Test-VMStateRunning -State $state) { Write-Host "VM is running" }
#>
function Test-VMStateRunning {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        # Use [object] instead of [VMState] to avoid type resolution errors in cross-scope calls
        # PowerShell module types aren't exported to the caller's scope
        [object]$State
    )

    # Compare by value (handles both enum and string comparisons)
    return $State -eq [VMState]::Running -or $State.ToString() -eq 'Running'
}

#endregion

#region Module Initialization

# Verify WriteLog function is available from FFU.Core
if (-not (Get-Command 'WriteLog' -ErrorAction SilentlyContinue)) {
    # Create a simple WriteLog fallback if FFU.Core isn't loaded
    function script:WriteLog {
        param([string]$Message)
        Write-Host "[FFU.Hypervisor] $Message"
    }
}

#endregion

# Export public functions
Export-ModuleMember -Function @(
    # Factory and utility functions
    'Get-HypervisorProvider',
    'Test-HypervisorAvailable',
    'Get-AvailableHypervisors',
    'New-VMConfiguration',
    'Get-VMStateValue',
    'Test-VMStateOff',
    'Test-VMStateRunning',
    # VM lifecycle wrapper functions
    'New-HypervisorVM',
    'Start-HypervisorVM',
    'Stop-HypervisorVM',
    'Remove-HypervisorVM',
    'Get-HypervisorVMIPAddress',
    'Get-HypervisorVMState',
    # Disk operations
    'New-HypervisorVirtualDisk',
    'Mount-HypervisorVirtualDisk',
    'Dismount-HypervisorVirtualDisk',
    # Media operations
    'Add-HypervisorVMDvdDrive',
    'Remove-HypervisorVMDvdDrive'
)
