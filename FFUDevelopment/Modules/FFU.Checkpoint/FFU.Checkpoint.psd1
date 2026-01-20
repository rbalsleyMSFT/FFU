@{
    # Module identification
    RootModule = 'FFU.Checkpoint.psm1'
    ModuleVersion = '1.1.0'
    GUID = 'b4e8f2a1-6c3d-4b7e-9f1a-5d2c8e4f6a3b'

    # Author information
    Author = 'FFUBuilder Team'
    CompanyName = 'FFUBuilder'
    Copyright = '(c) 2026 FFUBuilder Team. MIT License.'
    Description = 'Build checkpoint and resume functionality for FFU Builder. Provides atomic checkpoint persistence at phase boundaries, enabling resume capability after script restart.'

    # PowerShell version requirements
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    # .NET Framework requirements
    DotNetFrameworkVersion = '4.7.2'
    CLRVersion = '4.0'

    # Module dependencies - NONE (must work early in build before other modules load)
    RequiredModules = @()

    # Assemblies to load
    RequiredAssemblies = @()

    # Functions to export
    FunctionsToExport = @(
        'Save-FFUBuildCheckpoint'
        'Get-FFUBuildCheckpoint'
        'Remove-FFUBuildCheckpoint'
        'Test-FFUBuildCheckpoint'
        'Get-FFUBuildPhasePercent'
        'Test-CheckpointArtifacts'
        'Test-PhaseAlreadyComplete'
    )

    # Cmdlets to export (none - this is a script module)
    CmdletsToExport = @()

    # Variables to export
    VariablesToExport = @()

    # Aliases to export
    AliasesToExport = @()

    # File list (for manifest validation)
    FileList = @(
        'FFU.Checkpoint.psm1'
        'FFU.Checkpoint.psd1'
    )

    # Private data - PSData for PowerShell Gallery
    PrivateData = @{
        PSData = @{
            # Tags for gallery discoverability
            Tags = @('FFUBuilder', 'Checkpoint', 'Resume', 'BuildState', 'PowerShell')

            # License URI
            LicenseUri = 'https://opensource.org/licenses/MIT'

            # Release notes
            ReleaseNotes = @'
Version 1.1.0 (Resume Support)
- NEW: Test-CheckpointArtifacts validates artifact existence on disk
- NEW: Test-PhaseAlreadyComplete determines if phase should be skipped
- Phase ordering map with alias support (e.g., VMSetup/VMCreation)
- Hyper-V VM existence validation for vmCreated artifacts

Version 1.0.0 (Initial Release)
- FFUBuildPhase enum defining 16 build phases
- Save-FFUBuildCheckpoint with atomic write pattern
- Get-FFUBuildCheckpoint with PS5.1/PS7+ compatibility
- Remove-FFUBuildCheckpoint for cleanup
- Test-FFUBuildCheckpoint for validation
- Get-FFUBuildPhasePercent for progress calculation
- No external module dependencies
'@
        }
    }
}
