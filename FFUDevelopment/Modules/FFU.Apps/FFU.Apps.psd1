@{
    # Module manifest for FFU.Apps

    # Script module or binary module file associated with this manifest
    RootModule = 'FFU.Apps.psm1'

    # Version number of this module
    ModuleVersion = '1.0.0'

    # Supported PSEditions
    CompatiblePSEditions = @('Desktop', 'Core')

    # ID used to uniquely identify this module
    GUID = '7f3c8e52-4d91-4b56-9c38-2a5e4f8d3b91'

    # Author of this module
    Author = 'FFU Builder Team'

    # Company or vendor of this module
    CompanyName = 'FFU Builder Project'

    # Copyright statement for this module
    Copyright = '(c) 2024 FFU Builder Project. All rights reserved.'

    # Description of the functionality provided by this module
    Description = 'Application installation and management module for FFU Builder. Handles Office Deployment Tool, application ISO creation, and provisioned app removal (bloatware cleanup).'

    # Minimum version of the Windows PowerShell engine required by this module
    PowerShellVersion = '5.1'

    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules = @(
        @{ModuleName = 'FFU.Core'; ModuleVersion = '1.0.0'}
    )

    # Functions to export from this module
    FunctionsToExport = @(
        'Get-ODTURL',
        'Get-Office',
        'New-AppsISO',
        'Remove-Apps',
        'Remove-DisabledArtifacts'
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
            # Tags applied to this module
            Tags = @('FFU', 'Applications', 'Office', 'AppManagement', 'WindowsDeployment')

            # A URL to the license for this module
            LicenseUri = 'https://github.com/rbalsleyMSFT/FFU/blob/main/LICENSE'

            # A URL to the main website for this project
            ProjectUri = 'https://github.com/rbalsleyMSFT/FFU'

            # ReleaseNotes of this module
            ReleaseNotes = @'
## Version 1.0.0
- Initial module extraction from BuildFFUVM.ps1
- Office Deployment Tool (ODT) URL retrieval and download
- Office 365/Microsoft 365 Apps installation support
- Application ISO creation for deployment
- Provisioned app removal (bloatware cleanup)
- Support for custom Office configuration XML
'@
        }
    }

    # HelpInfo URI of this module
    # HelpInfoURI = ''
}