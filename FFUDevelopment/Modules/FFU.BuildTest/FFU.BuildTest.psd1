@{
    # Module identification
    RootModule        = 'FFU.BuildTest.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'a8b9c0d1-e2f3-4567-8901-234567890abc'
    Author            = 'FFU Builder Team'
    CompanyName       = 'FFU Builder'
    Copyright         = '(c) 2026 FFU Builder. MIT License.'
    Description       = 'Build testing and verification module for FFU Builder. Provides functions to copy FFUDevelopment to test drives, execute builds with different configurations, and verify build outputs.'

    # PowerShell version requirements
    PowerShellVersion = '7.0'

    # Module dependencies
    RequiredModules   = @(
        @{ModuleName = 'FFU.Core'; ModuleVersion = '1.0.0'}
    )

    # Functions to export
    FunctionsToExport = @(
        'Copy-FFUDevelopmentToTestDrive',
        'Invoke-FFUTestBuild',
        'Test-FFUBuildOutput',
        'Get-FFUBuildVerificationReport',
        'Get-FFUTestConfiguration'
    )

    # Cmdlets, variables, and aliases to export
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    # Private data for module manifest
    PrivateData       = @{
        PSData = @{
            Tags         = @('FFU', 'Testing', 'Build', 'Verification', 'Windows', 'Imaging')
            LicenseUri   = 'https://github.com/rbalsleyMSFT/FFU/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/rbalsleyMSFT/FFU'
            ReleaseNotes = @'
## Version 1.0.0 (2026-01-10)
- Initial release
- Copy-FFUDevelopmentToTestDrive: Copy FFUDevelopment to test drive with Robocopy
- Invoke-FFUTestBuild: Execute builds with Minimal, Standard, or UserConfig
- Test-FFUBuildOutput: Verify FFU file creation and validity
- Get-FFUBuildVerificationReport: Generate structured verification reports
- Get-FFUTestConfiguration: Load test configuration files
'@
        }
    }
}
