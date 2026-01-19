@{
    # Script module or binary module file associated with this manifest.
    RootModule = 'FFU.Drivers.psm1'

    # Version number of this module.
    ModuleVersion = '1.0.6'

    # Supported PSEditions
    # CompatiblePSEditions = @()

    # ID used to uniquely identify this module
    GUID = '8e7f3c9b-4a2d-4f8e-b9c1-2a5d3e7b8c4f'

    # Author of this module
    Author = 'FFU Builder Team'

    # Company or vendor of this module
    CompanyName = 'FFU Builder Project'

    # Copyright statement for this module
    Copyright = '(c) FFU Builder Project. All rights reserved.'

    # Description of the functionality provided by this module
    Description = 'OEM-specific driver download, parsing, and injection module for FFU Builder. Supports Microsoft Surface, HP, Lenovo, and Dell driver catalogs with automatic download, extraction, and DISM injection capabilities.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.0'

    # Name of the PowerShell host required by this module
    # PowerShellHostName = ''

    # Minimum version of the PowerShell host required by this module
    # PowerShellHostVersion = ''

    # Minimum version of Microsoft .NET Framework required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
    # DotNetFrameworkVersion = ''

    # Minimum version of the common language runtime (CLR) required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
    # ClrVersion = ''

    # Processor architecture (None, X86, Amd64) required by this module
    # ProcessorArchitecture = ''

    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules = @(
        @{ModuleName = 'FFU.Core'; ModuleVersion = '1.0.0'}
    )

    # Assemblies that must be loaded prior to importing this module
    # RequiredAssemblies = @()

    # Script files (.ps1) that are run in the caller's environment prior to importing this module.
    # ScriptsToProcess = @()

    # Type files (.ps1xml) to be loaded when importing this module
    # TypesToProcess = @()

    # Format files (.ps1xml) to be loaded when importing this module
    # FormatsToProcess = @()

    # Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
    # NestedModules = @()

    # Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
    FunctionsToExport = @(
        'Get-MicrosoftDrivers',
        'Get-HPDrivers',
        'Get-LenovoDrivers',
        'Get-DellDrivers',
        'Copy-Drivers',
        'Get-IntelEthernetDrivers'
    )

    # Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
    AliasesToExport = @()

    # DSC resources to export from this module
    # DscResourcesToExport = @()

    # List of all modules packaged with this module
    # ModuleList = @()

    # List of all files packaged with this module
    # FileList = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
    PrivateData = @{
        PSData = @{
            # Tags applied to this module. These help with module discovery in online galleries.
            Tags = @('FFU', 'Driver', 'OEM', 'Microsoft', 'HP', 'Lenovo', 'Dell', 'Surface', 'Download', 'DISM')

            # A URL to the license for this module.
            LicenseUri = 'https://github.com/rbalsleyMSFT/FFU/blob/main/LICENSE'

            # A URL to the main website for this project.
            ProjectUri = 'https://github.com/rbalsleyMSFT/FFU'

            # A URL to an icon representing this module.
            # IconUri = ''

            # ReleaseNotes of this module
            ReleaseNotes = @'
v1.0.6: BUG-04 Fix Dell Chipset Driver Extraction Hang
- Fixed Dell Intel chipset driver extraction hanging indefinitely
- Replaced Invoke-Process + Start-Sleep with Start-Process + WaitForExit()
- Added 30-second timeout via DRIVER_EXTRACTION_TIMEOUT_SECONDS constant
- Use Get-CimInstance for reliable child process discovery
- Kill child processes before parent for clean process tree termination
- Applied same timeout pattern to Network driver extraction on client OS
- Added detailed logging for timeout events and exit codes

v1.0.5: Enhanced Download Diagnostics and BITS Fallback
- Added BITS transfer fallback when WebRequest fails (network restrictions)
- Enhanced file size validation with 50MB minimum (detects proxy/firewall blocks)
- Added HTML content detection to identify proxy interception (blocked downloads)
- Added extraction verification to ensure archive produces files
- Enhanced copy verification with detailed logging of source/destination
- Comprehensive diagnostic logging throughout download process

v1.0.4: Fix Intel CDN 403 Forbidden Error
- Updated Intel driver URL to v30.6 release (871940/Release_30.6.zip)
- Added browser-like headers to bypass Intel CDN 403 Forbidden error
- Removed BITS transfer in favor of Invoke-WebRequest with custom headers
- Added search path for Release_* folder structure in v30.6 archive

v1.0.3: VMware WinPE Network Support
- Added Get-IntelEthernetDrivers function for auto-downloading Intel e1000e drivers
- Intel e1000e is the default NIC type for VMware Workstation Pro VMs
- Added Network Adapters ClassGUID to Copy-Drivers filter for WinPE network support
- Updated exclusion list to filter Bluetooth/WiFi drivers from WinPE

v1.0.2: Module Dependency Declaration
- Added FFU.Core as RequiredModule dependency
- Ensures WriteLog and other shared functions are available
- Uses standardized hashtable format for RequiredModules

v1.0.1: Phase 2 Reliability improvements
- Added comprehensive error handling with WebException catches for all web requests
- Added try/catch blocks in Get-MicrosoftDrivers, Get-HPDrivers, Get-LenovoDrivers, Get-DellDrivers
- Implemented graceful degradation (continue on individual driver failures instead of aborting)
- Added download-in-progress marker cleanup on failures
- Enhanced error logging with context

v1.0.0: Initial release of FFU.Drivers module extracted from BuildFFUVM.ps1 for improved modularity.
'@

            # Prerelease string of this module
            # Prerelease = ''

            # Flag to indicate whether the module requires explicit user acceptance for install/update/save
            # RequireLicenseAcceptance = $false

            # External dependent modules of this module
            # ExternalModuleDependencies = @()
        }
    }

    # HelpInfo URI of this module
    # HelpInfoURI = ''

    # Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
    # DefaultCommandPrefix = ''
}