#
# Module manifest for module 'FFU.ADK'
#

@{
    # Script module or binary module file associated with this manifest.
    RootModule = 'FFU.ADK.psm1'

    # Version number of this module.
    ModuleVersion = '1.0.1'

    # ID used to uniquely identify this module
    GUID = 'f24f0701-bcfc-489f-8111-1fbd89c61bdc'

    # Author of this module
    Author = 'FFU Builder Team'

    # Company or vendor of this module
    CompanyName = 'Community'

    # Copyright statement for this module
    Copyright = '(c) 2025 FFU Builder Team. MIT License.'

    # Description of the functionality provided by this module
    Description = 'Windows Assessment and Deployment Kit (ADK) management module for FFU Builder. Provides installation validation, automatic ADK/WinPE add-on installation, version checking, and lifecycle management for Windows ADK components.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.0'

    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules = @(
        @{ModuleName = 'FFU.Core'; ModuleVersion = '1.0.0'}
    )

    # Assemblies that must be loaded prior to importing this module
    RequiredAssemblies = @()

    # Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
    FunctionsToExport = @(
        'Write-ADKValidationLog',
        'Test-ADKPrerequisites',
        'Get-ADKURL',
        'Install-ADK',
        'Get-InstalledProgramRegKey',
        'Uninstall-ADK',
        'Confirm-ADKVersionIsLatest',
        'Get-ADK'
    )

    # Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
    AliasesToExport = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
    PrivateData = @{
        PSData = @{
            # Tags applied to this module. These help with module discovery in online galleries.
            Tags = @('FFU', 'Windows', 'ADK', 'Deployment', 'WinPE', 'Validation')

            # A URL to the license for this module.
            LicenseUri = 'https://github.com/Schweinehund/FFU/blob/feature/improvements-and-fixes/LICENSE'

            # A URL to the main website for this project.
            ProjectUri = 'https://github.com/Schweinehund/FFU'

            # ReleaseNotes of this module
            ReleaseNotes = @'
# Release Notes - FFU.ADK v1.0.1

## v1.0.1 - Background Job Compatibility
- Replaced Write-Host with proper output streams for background job compatibility
- Write-ADKValidationLog now uses Write-Verbose for diagnostic console output
- ADK error templates now logged via WriteLog for UI Monitor tab visibility
- Color-coded console output removed (not captured in background jobs)
- Validation messages visible in UI when running builds from UI

## v1.0.0 - Initial Release
- Extracted ADK management functions from monolithic BuildFFUVM.ps1
- 8 functions for complete ADK lifecycle management
- Pre-flight validation prevents silent WinPE media creation failures
- Automatic installation and repair capabilities
- Requires FFU.Core module and Administrator privileges

## Functions Included
- Validation: Write-ADKValidationLog, Test-ADKPrerequisites
- Installation: Get-ADKURL, Install-ADK, Get-ADK
- Management: Get-InstalledProgramRegKey, Uninstall-ADK, Confirm-ADKVersionIsLatest

## Key Features
- Comprehensive pre-flight ADK validation (addresses silent boot.wim failures)
- Automatic detection and installation of missing ADK components
- Version currency checking against latest Microsoft releases
- Support for both Windows ADK and WinPE add-on
- Detailed error messages with actionable resolution steps
'@
        }
    }
}
