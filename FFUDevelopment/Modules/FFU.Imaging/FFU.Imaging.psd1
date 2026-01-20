@{
    # Script module or binary module file associated with this manifest.
    RootModule = 'FFU.Imaging.psm1'

    # Version number of this module.
    ModuleVersion = '1.0.12'

    # Supported PSEditions
    CompatiblePSEditions = @('Desktop', 'Core')

    # ID used to uniquely identify this module
    GUID = 'f3d7e4b5-8c9a-4d2e-b1f6-7e8c9a3b5d4f'

    # Author of this module
    Author = 'FFU Builder Contributors'

    # Company or vendor of this module
    CompanyName = 'FFU Builder Project'

    # Copyright statement for this module
    Copyright = '(c) 2024 FFU Builder Contributors. All rights reserved.'

    # Description of the functionality provided by this module
    Description = 'DISM operations, VHDX management, partition creation, and FFU image generation for FFU Builder. Handles WIM extraction, disk partitioning, boot file configuration, Windows feature enablement, and FFU capture.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.0'

    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules = @(
        @{ModuleName = 'FFU.Core'; ModuleVersion = '1.0.0'}
    )

    # Functions to export from this module
    FunctionsToExport = @(
        'Initialize-DISMService',
        'Test-WimSourceAccessibility',
        'Invoke-ExpandWindowsImageWithRetry',
        'Get-WimFromISO',
        'Get-Index',
        'New-ScratchVhdx',
        'New-ScratchVhd',
        'New-SystemPartition',
        'New-MSRPartition',
        'New-OSPartition',
        'New-RecoveryPartition',
        'Add-BootFiles',
        'Enable-WindowsFeaturesByName',
        'Dismount-ScratchVhdx',
        'Dismount-ScratchVhd',
        'Optimize-FFUCaptureDrive',
        'Get-WindowsVersionInfo',
        'New-FFU',
        'Remove-FFU',
        'Start-RequiredServicesForDISM',
        'Invoke-FFUOptimizeWithScratchDir',
        'Expand-FFUPartitionForDrivers',
        'Set-OSPartitionDriveLetter'
    )

    # Cmdlets to export from this module
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module
    AliasesToExport = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess
    PrivateData = @{
        PSData = @{
            # Tags applied to this module for module discovery
            Tags = @('FFU', 'Builder', 'DISM', 'VHDX', 'Imaging', 'WindowsDeployment')

            # A URL to the license for this module.
            LicenseUri = 'https://github.com/rbalsleyMSFT/FFU/blob/main/LICENSE'

            # A URL to the main website for this project.
            ProjectUri = 'https://github.com/rbalsleyMSFT/FFU'

            # ReleaseNotes of this module
            ReleaseNotes = @'
v1.0.12 - VHDX-01: Add Set-OSPartitionDriveLetter for guaranteed drive letter assignment
- New centralized utility function for OS partition drive letter management
- Handles both already-assigned and missing drive letter cases
- Preferred letter support (default: W) with automatic fallback
- Retry logic (3 attempts) for resilience against transient failures
- Addresses drive letter loss during VHDX/VHD dismount/remount cycles

v1.0.11 - PERF-01: Optimize VHD flush from triple-pass to single verified Write-VolumeCache call (~7s -> <1s)
- Added Invoke-VerifiedVolumeFlush function using Windows native Write-VolumeCache cmdlet
- Write-VolumeCache guarantees flush completion before returning (no arbitrary waits needed)
- Fallback to fsutil for older Windows versions without Write-VolumeCache
- Removes 3x flush passes with 500ms pauses and 5s final I/O wait delay
- Dismount-ScratchVhd now completes 6+ seconds faster per VHD operation

v1.0.10 - BUG-03: Added Expand-FFUPartitionForDrivers for automatic VHDX/partition expansion with large driver sets
- New function calculates driver folder size and expands VHDX/partition when driver set exceeds threshold (default 5GB)
- Properly dismounts VHDX before resize and remounts after for partition expansion
- Uses Get-PartitionSupportedSize for safe partition resize to maximum available space
- Includes 1.5x compression factor and configurable safety margin for DISM overhead
- Addresses Issue #298: OS partition size limitations with large driver sets

v1.0.9 - Fix VMware VHD data persistence issue (unattend.xml missing after dismount)
- Added explicit volume flush (fsutil volume flush) before diskpart detach in Dismount-ScratchVhd
- Fixes issue where files copied to VHD (like unattend.xml) were lost due to unflushed buffers
- Without flush, VMware VMs would boot to OOBE instead of audit mode because unattend.xml was missing
- Hyper-V's Dismount-VHD cmdlet flushes automatically, but diskpart detach does not
- Now both Hyper-V (VHDX) and VMware (VHD) paths have proper data persistence

v1.0.8 - Enhanced capture boot logging
- Added clear section markers for CAPTURE BOOT CONFIGURATION and STARTING VM FOR FFU CAPTURE
- Added expected behavior documentation in logs (step-by-step what should happen)
- Logs provider type before capture
- Removed redundant VMX verification (now done in provider's AttachISO method)
- Clearer diagnostic messages if VM boots to Windows instead of WinPE

v1.0.7 - Enhanced VMware capture diagnostics
- Added comprehensive pre-capture logging: provider type, VM name, VMX path
- Added ISO verification: checks existence, logs size and modification time
- Added boot order verification after AttachISO: confirms VMX has correct boot order
- Warns if boot order doesn't start with 'cdrom' (WinPE won't boot)

v1.0.6 - VMware support for FFU capture from VM
- Added HypervisorProvider and VMInfo parameters to New-FFU for hypervisor-agnostic VM operations
- Added VMShutdownTimeoutMinutes parameter with timeout mechanism (default 20 minutes)
- Uses HypervisorProvider.AttachISO(), StartVM(), GetVMState() instead of direct Hyper-V cmdlets
- Maintains backwards compatibility with Hyper-V when provider not specified
- Fixes hang when using VMware - previous code used Hyper-V cmdlets (Get-VM, Start-VM) unconditionally
- Progress logging every minute during VM shutdown wait

v1.0.5 - Fix Windows Explorer format prompt race condition
- Modified New-SystemPartition, New-OSPartition, New-RecoveryPartition to create partitions WITHOUT drive letters
- Partitions are now formatted BEFORE drive letters are assigned, preventing Explorer from detecting raw partitions
- Re-fetch partition objects after drive letter assignment to ensure DriveLetter property is set correctly
- Eliminates "Format Disk" dialog popups that could block automated builds

v1.0.4 - Full diskpart fallback for all disk operations
- Updated partition functions to accept both CimInstance and PSCustomObject (from diskpart fallback)
- New-SystemPartition, New-MSRPartition, New-OSPartition, New-RecoveryPartition now use -DiskNumber parameter
- Removed [ciminstance] type constraint to enable flexible disk object handling
- Full build process works on systems where Get-Disk returns "Invalid property" (WMI corruption)

v1.0.3 - Diskpart fallback for disk enumeration
- Added Get-DiskWithDiskpartFallback function for systems where Get-Disk fails with "Invalid property" (WMI/Storage issues)
- New-ScratchVhd now detects Get-Disk availability and falls back to diskpart for disk enumeration
- Full diskpart-based initialization when Storage cmdlets are unavailable
- Supports Windows 10/11 systems with corrupted WMI Storage namespace

v1.0.2 - VMware VHD support
- Added New-ScratchVhd function for diskpart-based VHD creation (no Hyper-V dependency)
- Added Dismount-ScratchVhd function for diskpart-based VHD dismount
- VHD format is compatible with VMware Workstation (unlike VHDX which VMware cannot read)
- Comprehensive logging for troubleshooting disk operations
- Returns CIM disk instance compatible with existing partition functions

v1.0.1 - Fix missing Get-WindowsVersionInfo function
- Added Get-WindowsVersionInfo function that was lost during modularization
- Function reads Windows version from mounted VHDX registry for FFU filename generation
- Fixed "The term 'Get-WindowsVersionInfo' is not recognized" error during VHDX-direct FFU capture
- Proper parameterization instead of relying on script-scope variables

v1.0.0 - Initial release of modularized FFU.Imaging module
'@
        }
    }
}