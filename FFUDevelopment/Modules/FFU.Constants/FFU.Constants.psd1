@{
    # Module metadata
    ModuleVersion = '1.0.0'
    GUID = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author = 'FFUBuilder Contributors'
    CompanyName = 'FFUBuilder'
    Copyright = '(c) 2025 FFUBuilder Contributors. All rights reserved.'
    Description = 'Central constants and configuration values for FFUBuilder. Defines all hardcoded paths, timeouts, retry counts, and magic numbers used throughout the project.'

    # PowerShell version requirements
    PowerShellVersion = '5.1'

    # Root module
    RootModule = 'FFU.Constants.psm1'

    # Exported members (class is exported from psm1)
    FunctionsToExport = @()
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()

    # Private data
    PrivateData = @{
        PSData = @{
            Tags = @('FFU', 'Constants', 'Configuration', 'Windows', 'Deployment')
            LicenseUri = 'https://github.com/rbalsleyMSFT/FFU/blob/UI_2510/LICENSE'
            ProjectUri = 'https://github.com/rbalsleyMSFT/FFU'
            ReleaseNotes = @'
Version 1.0.0 (2025-11-24)
- Initial release
- Centralized all hardcoded paths and values
- Added environment variable override support
- Comprehensive documentation for each constant
'@
        }
    }
}
