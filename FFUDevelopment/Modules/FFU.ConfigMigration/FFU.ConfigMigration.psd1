@{
    # Module identification
    RootModule = 'FFU.ConfigMigration.psm1'
    ModuleVersion = '1.1.0'
    GUID = '9a3eab81-2f9c-44dc-a26e-bbb11086668b'

    # Author information
    Author = 'FFU Builder Team'
    CompanyName = 'FFUBuilder'
    Copyright = '(c) 2026 FFUBuilder Team. MIT License.'
    Description = 'Configuration file migration for FFU Builder. Provides schema versioning, version detection, and automatic migration of deprecated properties to their modern equivalents.'

    # PowerShell version requirements
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    # .NET Framework requirements
    DotNetFrameworkVersion = '4.7.2'
    CLRVersion = '4.0'

    # Module dependencies - FFU.Checkpoint provides ConvertTo-HashtableRecursive
    RequiredModules = @(
        @{ModuleName = 'FFU.Checkpoint'; ModuleVersion = '1.0.0'}
    )

    # Assemblies to load
    RequiredAssemblies = @()

    # Help info URI
    HelpInfoURI = 'https://github.com/rbalsleyMSFT/FFU/wiki/Config-Migration'

    # Functions to export
    FunctionsToExport = @(
        'Get-FFUConfigSchemaVersion'
        'Test-FFUConfigVersion'
        'Invoke-FFUConfigMigration'
        'ConvertTo-HashtableRecursive'
    )

    # Cmdlets to export (none - this is a script module)
    CmdletsToExport = @()

    # Variables to export
    VariablesToExport = @()

    # Aliases to export
    AliasesToExport = @()

    # File list (for manifest validation)
    FileList = @(
        'FFU.ConfigMigration.psm1'
        'FFU.ConfigMigration.psd1'
    )

    # Private data - PSData for PowerShell Gallery
    PrivateData = @{
        PSData = @{
            # Tags for gallery discoverability
            Tags = @('FFUBuilder', 'ConfigMigration', 'SchemaVersion', 'PowerShell')

            # License URI
            LicenseUri = 'https://opensource.org/licenses/MIT'

            # Project URI
            ProjectUri = 'https://github.com/rbalsleyMSFT/FFU'

            # Release notes
            ReleaseNotes = @'
Version 1.1.0
- Added v1.2 schema migration for VMwareSettings (NetworkType=nat, NicType=e1000e)
- Configs without VMwareSettings now get default values for VMware Workstation Pro support
- Handles both missing VMwareSettings and partial VMwareSettings (missing properties filled in)

Version 1.0.1
- Added migration support for IncludePreviewUpdates property (v1.1 schema)
- Configs without IncludePreviewUpdates now get default value of false

Version 1.0.0 (Initial Release)
- Get-FFUConfigSchemaVersion returns current schema version (1.0)
- Test-FFUConfigVersion detects if config needs migration
- Invoke-FFUConfigMigration transforms deprecated properties:
  - AppsPath, OfficePath: Removed (computed from FFUDevelopmentPath)
  - Verbose: Removed (use -Verbose CLI switch)
  - Threads: Removed (automatic parallel processing)
  - InstallWingetApps: Migrated to InstallApps
  - DownloadDrivers: Removed with warning (requires Make/Model)
  - CopyOfficeConfigXML: Removed with warning (requires OfficeConfigXMLFile)
- ConvertTo-HashtableRecursive re-exported for PS5.1 compatibility
- Backup creation before migration with timestamp suffix
- UI integration: FFUUI.Core.Config imports module for auto-load migration
- CLI integration: BuildFFUVM.ps1 prompts for migration with Y/N confirmation
'@
        }
    }
}
