@{
    # Module identification
    RootModule = 'FFU.ConfigMigration.psm1'
    ModuleVersion = '1.0.0'
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

            # Release notes
            ReleaseNotes = @'
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
'@
        }
    }
}
