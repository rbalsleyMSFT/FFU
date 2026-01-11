@{
    # Module manifest for FFU.Hypervisor
    # Hypervisor abstraction layer for FFU Builder

    # Script module or binary module file associated with this manifest
    RootModule = 'FFU.Hypervisor.psm1'

    # Version number of this module
    ModuleVersion = '1.1.17'

    # ID used to uniquely identify this module
    GUID = 'a8e2c3f1-5d7b-4e9a-bc12-3f4d5e6a7b8c'

    # Author of this module
    Author = 'FFU Builder Team'

    # Company or vendor of this module
    CompanyName = 'FFU Builder'

    # Copyright statement for this module
    Copyright = '(c) 2025 FFU Builder Team. MIT License.'

    # Description of the functionality provided by this module
    Description = 'Hypervisor abstraction layer supporting Hyper-V and VMware Workstation Pro for FFU Builder VM operations'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.0'

    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules = @(
        @{ModuleName = 'FFU.Core'; ModuleVersion = '1.0.0'}
    )

    # Functions to export from this module
    FunctionsToExport = @(
        # Public functions
        'Get-HypervisorProvider',
        'Test-HypervisorAvailable',
        'Get-AvailableHypervisors',
        'New-VMConfiguration',
        'Get-VMStateValue',
        'Test-VMStateOff',
        'Test-VMStateRunning',
        # Provider interface functions
        'New-HypervisorVM',
        'Start-HypervisorVM',
        'Stop-HypervisorVM',
        'Remove-HypervisorVM',
        'Get-HypervisorVMIPAddress',
        'Get-HypervisorVMState',
        'New-HypervisorVirtualDisk',
        'Mount-HypervisorVirtualDisk',
        'Dismount-HypervisorVirtualDisk',
        'Add-HypervisorVMDvdDrive',
        'Remove-HypervisorVMDvdDrive'
    )

    # Cmdlets to export from this module
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module
    AliasesToExport = @()

    # Private data to pass to the module specified in RootModule
    PrivateData = @{
        PSData = @{
            # Tags applied to this module for module discovery
            Tags = @('Hyper-V', 'VMware', 'Hypervisor', 'FFU', 'WindowsDeployment')

            # A URL to the license for this module
            LicenseUri = 'https://github.com/FFUBuilder/FFU/blob/main/LICENSE'

            # A URL to the main website for this project
            ProjectUri = 'https://github.com/FFUBuilder/FFU'

            # ReleaseNotes of this module
            ReleaseNotes = @'
v1.1.16 (2026-01-10)
- FIX: Get-VHDMountedDriveLetter and Set-VHDDriveLetter now have diskpart fallback
- Systems with broken WMI/Storage namespace (Get-Disk "Invalid property" error) now work
- Fallback uses diskpart "detail vdisk" and "list volume" commands to find disk info
- Enables VHD operations on Windows 10/11 systems with corrupted Storage namespace

v1.1.15 (2026-01-09)
- FIX: vmrun command syntax for stop - option (hard/soft) must come AFTER VMX path
- Corrected: "vmrun stop 'path.vmx' hard" instead of "vmrun stop hard 'path.vmx'"
- FIX: [VMState] type not found error in cross-scope calls from BuildFFUVM.ps1
- Changed Test-VMStateOff/Test-VMStateRunning to use [object] parameter type
- PowerShell module types aren't exported to caller's scope, causing type resolution failures

v1.1.14 (2026-01-09)
- FIX: Disable vTPM for VMware VMs - vTPM requires VM encryption which breaks vmrun automation
- VMware's "managedvm.autoAddVTPM = software" causes "Virtual TPM Initialization failed" error
- TPM-dependent features (BitLocker, Windows Hello) work on target hardware after FFU deployment
- Added comprehensive logging for TPM configuration decisions in VMwareProvider.CreateVM
- Updated VMwareProvider.Capabilities to reflect TPM limitation with explanatory note
- FUTURE: VM encryption + vTPM support documented in code comments (requires vmrun -vp password)

v1.1.13 (2026-01-09)
- FIX: vmrun gui fallback when nogui fails with "operation was canceled"
- vTPM/encrypted VMs cannot use nogui mode - automatically retries with gui
- Improved error messaging showing both nogui and gui attempt results

v1.1.12 (2026-01-09)
- FIX: VMware VMs now use VMDK disk format (VHD is not bootable in VMware)
- NEW: New-VMDKWithVdiskmanager creates native VMDK disks using vmware-vdiskmanager.exe
- FIX: Disabled 3D acceleration (mks.enable3d=FALSE) to fix "operation was canceled" error with vmrun nogui
- Enhanced pre-flight diagnostics: logs disk size, 3D accel settings, fullscreen warnings
- BuildFFUVM.ps1 now passes VMDK path to VMwareProvider instead of VHD

v1.1.11 (2026-01-09)
- vmrun fallback for GetVMState when REST API returns 401
- New Get-VMwarePowerStateWithVmrun function uses "vmrun list" to check running state
- RemoveVM simplified: skip unregister if 401, just stop VM and delete files
- All VM operations now work without REST API credentials via vmrun.exe fallback

v1.1.10 (2026-01-09)
- Fix: [VMState] type not found error in BuildFFUVM.ps1
- Added factory functions for cross-scope enum access: Get-VMStateValue, Test-VMStateOff, Test-VMStateRunning
- PowerShell module enums aren't exported to caller's scope, so factory functions provide access

v1.1.9 (2026-01-09)
- MAJOR: Skip VM registration - use direct VMX path for all operations
- vmrun register command is unreliable/unsupported in VMware Workstation
- CreateVM now creates VMX and returns VMInfo without registration
- StartVM uses "vmrun start vmx_path nogui" directly (headless mode)
- All vmrun operations use VMX path instead of VM ID
- Simpler, more reliable VMware integration

v1.1.8 (2026-01-09)
- Enhanced vmrun diagnostic logging for troubleshooting
- Register-VMwareVMWithVmrun now logs: vmrun path, VMX existence, VMware UI status
- Added vmrun list command test when registration fails
- Detailed error messages with exit code interpretation
- Logs stdout and stderr for all vmrun commands

v1.1.7 (2026-01-09)
- Added vmrun.exe fallback for VM operations when REST API authentication fails (401)
- New functions: Get-VmrunPath, Register-VMwareVMWithVmrun, Set-VMwarePowerStateWithVmrun
- Register-VMwareVM now falls back to "vmrun -T ws register" if REST API fails
- Set-VMwarePowerState now falls back to "vmrun -T ws start/stop" if REST API fails
- VMwareProvider passes VMXPath to power state functions for vmrun fallback
- Added ResolveVMXPath helper method to VMwareProvider
- VMware operations now work without REST API credentials using vmrun.exe

v1.1.6 (2026-01-09)
- Fix: VMware REST API URL construction bug causing 405 Method Not Allowed errors
- URLs were malformed as "/apivms/..." instead of "/api/vms/..." (missing slash)
- Invoke-VMwareRestMethod now logs full URL for debugging
- Consolidated error handling for both PowerShell 5.1 (WebException) and PS7 (HttpResponseException)

v1.1.5 (2026-01-08)
- Fix: vmrest startup timeout due to 401 Unauthorized treated as "not ready"
- Test-VMrestEndpoint now correctly treats 401 as "vmrest is running" (just needs auth)
- Added TCP connection pre-check before HTTP test for faster failure detection
- Get-HypervisorProvider now accepts -Credential and -Port parameters for VMware
- VMwareProvider.SetCredential() method for setting API credentials
- EnsureVMrestRunning now passes credentials to Start-VMrestService
- BuildFFUVM.ps1 now supports -VMwareUsername, -VMwarePassword, -VMwarePort parameters

v1.1.4 (2026-01-08)
- Added New-VMConfiguration factory function for cross-scope class instantiation
- Fixes "Unable to find type [VMConfiguration]" error when running in background jobs
- PowerShell module classes aren't exported to caller's scope, so factory function is required

v1.1.3 (2026-01-08)
- Fix: Test-HypervisorAvailable now properly uses VMwareProvider for VMware checks
- Removed hardcoded stub code that returned "VMware provider is not yet implemented"
- Build script now correctly detects VMware availability via provider pattern
- 101 Pester tests passing

v1.1.2 (2026-01-08)
- Fix: vmrest authentication failure with PowerShell's -Credential parameter
- PowerShell's Invoke-RestMethod -Credential doesn't work correctly with vmrest
- Replaced with explicit Basic auth headers via new Get-BasicAuthHeader function
- Proper SecureString handling with memory cleanup for security
- 101 Pester tests passing

v1.1.1 (2026-01-08)
- Fix: PowerShell 7+ HTTP authentication error with vmrest REST API
- Fix: VMware 17.x uses 'vmrest.cfg' (no leading dot), not '.vmrestCfg'
- Now checks both filename variants for backward compatibility

v1.1.0 (2026-01-07)
- Milestone 2: Full VMware Workstation Pro provider implementation
- VMware REST API integration via vmrest.exe (Start-VMrestService, Invoke-VMwareRestMethod)
- VM lifecycle management (CreateVM, StartVM, StopVM, RemoveVM) via VMX file generation
- Disk operations via diskpart (no Hyper-V dependency) - New-VHDWithDiskpart
- Network configuration with NAT/bridged adapter support
- IP address retrieval via VMware guest info
- 61 Pester tests passing

v1.0.0 (2025-12-17)
- Initial release
- IHypervisorProvider interface definition
- HyperVProvider implementation (refactored from FFU.VM)
- VMConfiguration and VMInfo supporting classes
- Factory function Get-HypervisorProvider
- Availability detection functions
'@
        }
    }

    # HelpInfo URI of this module
    # HelpInfoURI = ''
}
