#
# Module manifest for module 'FFU.VM'
#

@{
    RootModule = 'FFU.VM.psm1'
    ModuleVersion = '1.0.8'
    GUID = 'c8f3a942-7e6d-4c1a-9b85-1f4e8d2c5a76'
    Author = 'FFU Builder Team'
    CompanyName = 'Community'
    Copyright = '(c) 2025 FFU Builder Team. MIT License.'
    Description = 'Hyper-V virtual machine lifecycle management module for FFU Builder. Provides VM creation with TPM/HGS configuration, comprehensive cleanup, and environment validation for FFU build operations.'
    PowerShellVersion = '7.0'
    RequiredModules = @(
        @{ModuleName = 'FFU.Core'; ModuleVersion = '1.0.0'},
        @{ModuleName = 'FFU.Hypervisor'; ModuleVersion = '1.1.10'}
    )
    FunctionsToExport = @(
        'Get-LocalUserAccount',
        'New-LocalUserAccount',
        'Remove-LocalUserAccount',
        'Set-LocalUserPassword',
        'Set-LocalUserAccountExpiry',
        'New-FFUVM',
        'Remove-FFUVM',
        'Remove-FFUBuildArtifacts',
        'Remove-FFUVMWithProvider',
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
v1.0.8: ThreadJob function scope fix - Export Remove-FFUVMWithProvider
- Added Remove-FFUVMWithProvider function (previously script-scope in BuildFFUVM.ps1)
- Changed from $script:HypervisorProvider to explicit HypervisorProvider parameter
- Exported from FFU.VM to ensure availability in ThreadJob contexts
- Fixes "Remove-FFUVMWithProvider is not recognized" error during UI builds

v1.0.6: Revert VMware Firewall Functions (Incorrect Root Cause)
- REMOVED: Add-FFUVMwareFirewallRules and Remove-FFUVMwareFirewallRules
- REMOVED: HypervisorType parameter from Set-CaptureFFU
- REMOVED: RemoveVMwareFirewallRules switch from Remove-FFUUserShare
- ROOT CAUSE: VMware Error 53 was due to Hyper-V External switch conflict, not firewall
- SOLUTION: Pre-flight check now detects External Hyper-V switches (Test-FFUHyperVSwitchConflict)
- See FFU.Preflight v1.0.9 for the correct solution

v1.0.5: VMware SMB Firewall Support (REVERTED - see v1.0.6)
- This version incorrectly assumed firewall was blocking VMware SMB
- The actual root cause was Hyper-V External switch interfering with VMware bridging

v1.0.4: Fix [VMState] type not found error
- Fixed Get-FFUEnvironment using [VMState]::Running which caused "Unable to find type" error
- Now uses Test-VMStateRunning factory function from FFU.Hypervisor module
- Added FFU.Hypervisor as required module dependency

v1.0.3: Hypervisor abstraction integration
- Added Remove-FFUBuildArtifacts function for hypervisor-agnostic cleanup of mounted images, mount folders, and mountpoints
- Updated Get-FFUEnvironment with optional HypervisorProvider parameter for multi-hypervisor support
- Get-FFUEnvironment now uses provider when available, falls back to Hyper-V cmdlets

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
