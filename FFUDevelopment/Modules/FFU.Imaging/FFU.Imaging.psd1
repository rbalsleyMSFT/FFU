@{
    # Script module or binary module file associated with this manifest.
    RootModule = 'FFU.Imaging.psm1'

    # Version number of this module.
    ModuleVersion = '1.0.1'

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
    PowerShellVersion = '5.1'

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
        'New-SystemPartition',
        'New-MSRPartition',
        'New-OSPartition',
        'New-RecoveryPartition',
        'Add-BootFiles',
        'Enable-WindowsFeaturesByName',
        'Dismount-ScratchVhdx',
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