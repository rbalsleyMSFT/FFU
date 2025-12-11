@{
    # Module identification
    RootModule = 'FFU.Messaging.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'a8d7c3e1-5f2b-4a9c-8e1d-6b3f5c7d9e2a'

    # Author information
    Author = 'FFUBuilder Team'
    CompanyName = 'FFUBuilder'
    Copyright = '(c) 2025 FFUBuilder Team. MIT License.'
    Description = 'Thread-safe messaging system for FFUBuilder UI/background job communication. Provides synchronized queue-based messaging with support for structured messages, progress tracking, and cancellation.'

    # PowerShell version requirements
    PowerShellVersion = '7.0'
    CompatiblePSEditions = @('Desktop', 'Core')

    # .NET Framework requirements
    DotNetFrameworkVersion = '4.7.2'
    CLRVersion = '4.0'

    # Type and format files
    # TypesToProcess = @()
    # FormatsToProcess = @()

    # Module dependencies
    # RequiredModules = @()

    # Assemblies to load
    RequiredAssemblies = @()

    # Script files to run
    # ScriptsToProcess = @()

    # Nested modules
    # NestedModules = @()

    # Functions to export
    FunctionsToExport = @(
        # Context management
        'New-FFUMessagingContext'
        'Test-FFUMessagingContext'
        'Close-FFUMessagingContext'

        # Message writing (background job)
        'Write-FFUMessage'
        'Write-FFUProgress'
        'Write-FFUInfo'
        'Write-FFUSuccess'
        'Write-FFUWarning'
        'Write-FFUError'
        'Write-FFUDebug'

        # Message reading (UI)
        'Read-FFUMessages'
        'Peek-FFUMessage'
        'Get-FFUMessageCount'

        # Build state
        'Set-FFUBuildState'
        'Request-FFUCancellation'
        'Test-FFUCancellationRequested'
    )

    # Cmdlets to export (none - this is a script module)
    CmdletsToExport = @()

    # Variables to export
    VariablesToExport = @()

    # Aliases to export
    AliasesToExport = @()

    # DSC resources to export
    # DscResourcesToExport = @()

    # Module list (for manifest validation)
    # ModuleList = @()

    # File list (for manifest validation)
    FileList = @(
        'FFU.Messaging.psm1'
        'FFU.Messaging.psd1'
    )

    # Private data - PSData for PowerShell Gallery
    PrivateData = @{
        PSData = @{
            # Tags for gallery discoverability
            Tags = @('FFUBuilder', 'Messaging', 'Threading', 'WPF', 'UI', 'PowerShell')

            # License URI
            LicenseUri = 'https://opensource.org/licenses/MIT'

            # Project site
            # ProjectUri = ''

            # Icon URI
            # IconUri = ''

            # Release notes
            ReleaseNotes = @'
Version 1.0.0 (Initial Release)
- ConcurrentQueue-based thread-safe messaging
- Structured message types with FFUMessage class
- Progress tracking with FFUProgressMessage
- Build state management with cancellation support
- Dual output: queue for UI + file for persistence
- PowerShell 5.1 and 7+ compatible
'@

            # Prerelease tag
            # Prerelease = ''

            # External module dependencies
            # ExternalModuleDependencies = @()
        }
    }

    # Help info URI
    # HelpInfoURI = ''

    # Default command prefix (none)
    # DefaultCommandPrefix = ''
}
