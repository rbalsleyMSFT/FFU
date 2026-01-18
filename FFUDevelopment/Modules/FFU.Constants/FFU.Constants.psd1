@{
    # Module metadata
    ModuleVersion = '1.1.1'
    GUID = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author = 'FFUBuilder Contributors'
    CompanyName = 'FFUBuilder'
    Copyright = '(c) 2025 FFUBuilder Contributors. All rights reserved.'
    Description = 'Central constants and configuration values for FFUBuilder. Defines all hardcoded paths, timeouts, retry counts, and magic numbers used throughout the project.'

    # PowerShell version requirements
    PowerShellVersion = '7.0'

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
Version 1.1.1 (2026-01-17)
- Removed deprecated static path properties ($DEFAULT_WORKING_DIR, etc.)
- Removed legacy wrapper methods (GetWorkingDirectory, GetVMDirectory, GetCaptureDirectory)
- Use GetDefault*Dir() methods for all path resolution

Version 1.1.0 (2025-12-10)
- BREAKING: Added dynamic path resolution (no longer assumes C:\FFUDevelopment)
- New GetBasePath() method resolves installation location from module path
- New SetBasePath() and ResetBasePath() methods for testing and overrides
- New Get*Dir() methods for all path types (Working, VM, Capture, Drivers, Apps, Updates)
- Environment variable overrides: FFU_BASE_PATH, FFU_WORKING_DIR, FFU_VM_DIR, etc.

Version 1.0.0 (2025-11-24)
- Initial release
- Centralized all hardcoded paths and values
- Added environment variable override support
- Comprehensive documentation for each constant
'@
        }
    }
}
