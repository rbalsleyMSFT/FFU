#
# Module manifest for module 'FFU.Core'
#

@{
    # Script module or binary module file associated with this manifest.
    RootModule = 'FFU.Core.psm1'

    # Version number of this module.
    ModuleVersion = '1.0.11'

    # ID used to uniquely identify this module
    GUID = '9332d136-2710-49af-b356-a0281ebd8999'

    # Author of this module
    Author = 'FFU Builder Team'

    # Company or vendor of this module
    CompanyName = 'Community'

    # Copyright statement for this module
    Copyright = '(c) 2025 FFU Builder Team. MIT License.'

    # Description of the functionality provided by this module
    Description = 'Core utility module for FFU Builder providing common configuration management, logging, session tracking, and helper operations used across all FFU Builder modules.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '5.1'

    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules = @(
        @{ModuleName = 'FFU.Constants'; ModuleVersion = '1.0.0'}
    )

    # Assemblies that must be loaded prior to importing this module
    RequiredAssemblies = @()

    # Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
    FunctionsToExport = @(
        # Configuration and utilities
        'Get-Parameters',
        'Write-VariableValues',         # v1.0.11: Renamed from LogVariableValues (approved verb)
        'Get-ChildProcesses',
        'Test-Url',
        'Get-PrivateProfileString',
        'Get-PrivateProfileSection',
        'Get-ShortenedWindowsSKU',
        'New-FFUFileName',
        'Export-ConfigFile',
        # Session management
        'New-RunSession',
        'Get-CurrentRunManifest',
        'Save-RunManifest',
        'Set-DownloadInProgress',       # v1.0.11: Renamed from Mark-DownloadInProgress (approved verb)
        'Clear-DownloadInProgress',
        'Remove-InProgressItems',
        'Clear-CurrentRunDownloads',    # v1.0.11: Renamed from Cleanup-CurrentRunDownloads (approved verb)
        'Restore-RunJsonBackups',
        # Error handling (v1.0.5)
        'Invoke-WithErrorHandling',
        'Test-ExternalCommandSuccess',
        'Invoke-WithCleanup',
        # Cleanup registration system (v1.0.6)
        'Register-CleanupAction',
        'Unregister-CleanupAction',
        'Invoke-FailureCleanup',
        'Clear-CleanupRegistry',
        'Get-CleanupRegistry',
        # Specialized cleanup helpers
        'Register-VMCleanup',
        'Register-VHDXCleanup',
        'Register-DISMMountCleanup',
        'Register-ISOCleanup',
        'Register-TempFileCleanup',
        'Register-NetworkShareCleanup',
        'Register-UserAccountCleanup',
        'Register-SensitiveMediaCleanup',
        # Secure credential management (v1.0.7)
        'New-SecureRandomPassword',
        'ConvertFrom-SecureStringToPlainText',
        'Clear-PlainTextPassword',
        'Remove-SecureStringFromMemory',
        # Configuration schema validation (v1.0.10)
        'Test-FFUConfiguration',
        'Get-FFUConfigurationSchema'
    )

    # Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
    # v1.0.11: Added backward compatibility aliases for renamed functions (deprecated)
    AliasesToExport = @(
        'LogVariableValues',            # Deprecated: Use Write-VariableValues
        'Mark-DownloadInProgress',      # Deprecated: Use Set-DownloadInProgress
        'Cleanup-CurrentRunDownloads'   # Deprecated: Use Clear-CurrentRunDownloads
    )

    # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
    PrivateData = @{
        PSData = @{
            # Tags applied to this module. These help with module discovery in online galleries.
            Tags = @('FFU', 'Windows', 'Deployment', 'Imaging', 'Utilities')

            # A URL to the license for this module.
            LicenseUri = 'https://github.com/Schweinehund/FFU/blob/feature/improvements-and-fixes/LICENSE'

            # A URL to the main website for this project.
            ProjectUri = 'https://github.com/Schweinehund/FFU'

            # ReleaseNotes of this module
            ReleaseNotes = @'
# Release Notes - FFU.Core v1.0.11

## v1.0.11 - PowerShell Best Practices Compliance
- **BREAKING CHANGE (with backward compatibility)**: Renamed 3 functions to use approved verbs
  - LogVariableValues -> Write-VariableValues (alias preserved)
  - Mark-DownloadInProgress -> Set-DownloadInProgress (alias preserved)
  - Cleanup-CurrentRunDownloads -> Clear-CurrentRunDownloads (alias preserved)
- Added [OutputType([void])] attribute to renamed functions
- Enhanced comment-based help with .NOTES documenting renames
- Backward compatibility aliases exported for existing code
- Old function names continue to work via aliases but are deprecated
- Module imports cleanly without verb warnings when using -DisableNameChecking
- 39 total functions + 3 aliases now exported

## v1.0.10 - Configuration Schema Validation
- Added Test-FFUConfiguration: Validates config files against JSON schema
- Added Get-FFUConfigurationSchema: Returns path to schema file
- JSON Schema validation for all configuration properties
- Type checking (string, boolean, integer, object)
- Enum validation for WindowsSKU, WindowsArch, Make, MediaType, etc.
- Range validation for Memory, Disksize, Processors, etc.
- Pattern validation for ShareName, Username, IP addresses
- Unknown property detection with errors or warnings
- ThrowOnError switch for strict validation mode
- 39 total functions now exported

## v1.0.9 - Module Dependency Declaration
- Added FFU.Constants as RequiredModule dependency
- Ensures proper module load order (FFU.Constants loads before FFU.Core)
- Uses standardized hashtable format for RequiredModules

## v1.0.8 - Sensitive Media Cleanup Enhancement
- Added Register-SensitiveMediaCleanup: Registers cleanup for credential-containing capture media files
- Ensures backup files with credentials are removed on build failures
- Sanitizes CaptureFFU.ps1 password values on failure cleanup
- 37 total functions now exported

## v1.0.7 - Secure Credential Management
- Added New-SecureRandomPassword: Cryptographically secure password generation directly to SecureString
- Uses RNGCryptoServiceProvider instead of Get-Random for true randomness
- Password never exists as complete plain text string during generation
- Added ConvertFrom-SecureStringToPlainText: Safe conversion with BSTR cleanup
- Added Clear-PlainTextPassword: Memory cleanup for plain text password variables
- Added Remove-SecureStringFromMemory: Proper SecureString disposal
- 36 total functions now exported

## v1.0.6 - Cleanup Registration System
- Added cleanup registration system for automatic resource cleanup on failures
- Core functions: Register-CleanupAction, Unregister-CleanupAction, Invoke-FailureCleanup
- Registry management: Clear-CleanupRegistry, Get-CleanupRegistry
- Specialized helpers: Register-VMCleanup, Register-VHDXCleanup, Register-DISMMountCleanup
- Additional helpers: Register-ISOCleanup, Register-TempFileCleanup
- Network/user helpers: Register-NetworkShareCleanup, Register-UserAccountCleanup
- LIFO (Last In First Out) cleanup ordering ensures newest resources cleaned first
- Selective cleanup by ResourceType (VM, VHDX, DISM, ISO, TempFile, Share, User)
- Error-resilient cleanup (continues even if individual cleanup actions fail)
- 32 total functions now exported

## v1.0.5 - Error Handling Implementation
- Added Invoke-WithErrorHandling: Wrapper with retry logic, cleanup actions, and structured error handling
- Added Test-ExternalCommandSuccess: Validates external command exit codes with robocopy special handling
- Added Invoke-WithCleanup: Guaranteed cleanup in finally block for resource management
- Safe logging helpers that work with or without WriteLog function available
- 20 total functions now exported

## v1.0.0 - Initial Release
- Extracted core utility functions from monolithic BuildFFUVM.ps1
- 17 functions providing configuration management, logging, and session tracking
- Foundation module for FFU Builder modular architecture
- No external dependencies (base module)

## Functions Included
- Configuration: Get-Parameters, Write-VariableValues, Export-ConfigFile
- Session Management: New-RunSession, Get-CurrentRunManifest, Save-RunManifest
- Download Tracking: Set-DownloadInProgress, Clear-DownloadInProgress, Remove-InProgressItems
- Utilities: Test-Url, Get-ChildProcesses, Get-PrivateProfileString, Get-ShortenedWindowsSKU, New-FFUFileName
- Cleanup: Clear-CurrentRunDownloads, Restore-RunJsonBackups
- Error Handling: Invoke-WithErrorHandling, Test-ExternalCommandSuccess, Invoke-WithCleanup
- Cleanup Registration: Register-CleanupAction, Unregister-CleanupAction, Invoke-FailureCleanup, etc.

## Deprecated Aliases (for backward compatibility)
- LogVariableValues -> Write-VariableValues
- Mark-DownloadInProgress -> Set-DownloadInProgress
- Cleanup-CurrentRunDownloads -> Clear-CurrentRunDownloads
'@
        }
    }
}
