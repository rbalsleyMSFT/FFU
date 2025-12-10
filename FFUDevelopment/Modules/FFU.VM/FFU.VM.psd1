#
# Module manifest for module 'FFU.VM'
#

@{
    RootModule = 'FFU.VM.psm1'
    ModuleVersion = '1.0.2'
    GUID = 'c8f3a942-7e6d-4c1a-9b85-1f4e8d2c5a76'
    Author = 'FFU Builder Team'
    CompanyName = 'Community'
    Copyright = '(c) 2025 FFU Builder Team. MIT License.'
    Description = 'Hyper-V virtual machine lifecycle management module for FFU Builder. Provides VM creation with TPM/HGS configuration, comprehensive cleanup, and environment validation for FFU build operations.'
    PowerShellVersion = '5.1'
    RequiredModules = @(
        @{ModuleName = 'FFU.Core'; ModuleVersion = '1.0.0'}
    )
    FunctionsToExport = @(
        'Get-LocalUserAccount',
        'New-LocalUserAccount',
        'Remove-LocalUserAccount',
        'Set-LocalUserPassword',
        'Set-LocalUserAccountExpiry',
        'New-FFUVM',
        'Remove-FFUVM',
        'Get-FFUEnvironment',
        'Set-CaptureFFU',
        'Remove-FFUUserShare',
        'Remove-SensitiveCaptureMedia',
        'Update-CaptureFFUScript'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('FFU', 'Hyper-V', 'VM', 'Virtual Machine', 'TPM', 'HGS')
            LicenseUri = 'https://github.com/Schweinehund/FFU/blob/feature/improvements-and-fixes/LICENSE'
            ProjectUri = 'https://github.com/Schweinehund/FFU'
            ReleaseNotes = @'
v1.0.2: Phase 2 Reliability improvements
- Added comprehensive error handling with specific exception types (VirtualizationException, ItemNotFoundException, IOException, COMException, UnauthorizedAccessException)
- Added default values to ShareName parameters to prevent empty string binding errors
- Enhanced cleanup logic with proper error handling in Remove-FFUVM and Get-FFUEnvironment

v1.0.1: Security enhancement - Cryptographically secure password generation
- Set-CaptureFFU now uses New-SecureRandomPassword from FFU.Core
- Password generated directly to SecureString (never plain text in memory)
- Uses RNGCryptoServiceProvider instead of Get-Random for true cryptographic randomness

v1.0.0: Initial release - Hyper-V VM management with TPM/HGS support
'@
        }
    }
}
