@{
    # Script module or binary module file associated with this manifest.
    RootModule = 'FFU.Imaging.psm1'

    # Version number of this module.
    ModuleVersion = '1.0.5'

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
        'Invoke-FFUOptimizeWithScratchDir'
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