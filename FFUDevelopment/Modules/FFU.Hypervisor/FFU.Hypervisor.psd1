@{
    # Module manifest for FFU.Hypervisor
    # Hypervisor abstraction layer for FFU Builder

    # Script module or binary module file associated with this manifest
    RootModule = 'FFU.Hypervisor.psm1'

    # Version number of this module
    ModuleVersion = '1.3.4'

    # ID used to uniquely identify this module
    GUID = 'a8e2c3f1-5d7b-4e9a-bc12-3f4d5e6a7b8c'

    # Author of this module
    Author = 'FFU Builder Team'

    # Company or vendor of this module
    CompanyName = 'FFU Builder'

    # Copyright statement for this module
    Copyright = '(c) 2025 FFU Builder Team. MIT License.'

    # Description of the functionality provided by this module
    Description = 'Hypervisor abstraction layer supporting Hyper-V and VMware Workstation Pro - vmware-vmx process detection, vmrun list, nvram lock'

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
        'Wait-VMStateChange',
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
v1.3.3 (2026-01-21)
- FIX: ThreadJob runspace compatibility - "Write-Warning is not recognized" error
- Module initialization catch blocks used Write-Warning which fails in ThreadJob runspaces
- Solution: Replaced Write-Warning with [Console]::Error.WriteLine() in FFU.Hypervisor.psm1
- Also fixed Wait-VMStateChange.ps1: Write-Warning → safe logging pattern (WriteLog or Write-Verbose)
- Same class of issue as FFU.Common v0.0.9 (Get-Date), v0.0.10 (Write-Host), v0.0.11 (Write-Warning)

v1.3.2 (2026-01-21)
- FIX: ThreadJob runspace compatibility for fallback WriteLog function
- Root cause: Fallback WriteLog (used when FFU.Core isn't loaded) used Write-Host cmdlet
- Write-Host may not be available in ThreadJob runspaces (same issue as FFU.Common v0.0.10)
- Solution: Replaced Write-Host with [Console]::WriteLine() for console output

v1.3.1 (2026-01-20)
- NEW: VMware network configuration is now user-configurable (RTS-99)
- Added VMwareNetworkType property to VMConfiguration (bridged, nat, hostonly)
- Added VMwareNicType property to VMConfiguration (e1000e, vmxnet3, e1000)
- New-VMConfiguration factory accepts -VMwareNetworkType and -VMwareNicType parameters
- VMwareProvider reads from config instead of hardcoding 'bridged'
- BuildFFUVM.ps1 loads VMwareSettings from config file
- Maintains backward compatibility (defaults to bridged/e1000e)

v1.3.0 (2026-01-19)
- NEW: Event-driven VM state monitoring for Hyper-V (PERF-02)
- Added Wait-VMStateChange function using Register-CimIndicationEvent
- Uses CIM event subscription instead of polling for efficient state monitoring
- Added HyperVProvider.WaitForState method for event-driven waiting
- Added IHypervisorProvider.WaitForState interface method
- VMware keeps polling-based waiting (no CIM event support)

v1.2.9 (2026-01-15)
- FIX: VMware GUI mode capture boot - recognize VM "Completed" vs "Failed to start"
- Root cause: vmrun -T ws start "vmx" gui BLOCKS until VM shuts down
- When vmrun returns with exit code 0 but no VM process, this means VM COMPLETED
- Previously code assumed "no process = startup failed" and retried (wrong)
- CHANGES:
  - Wait-VMwareVMStart: New -GUIMode parameter, returns Status='Completed' when appropriate
  - Set-VMwarePowerStateWithVmrun: Now returns hashtable with Status property
  - VMwareProvider.StartVM: Now returns 'Running' or 'Completed' string
  - IHypervisorProvider.StartVM: Changed from [void] to [string] return type
  - BuildFFUVM.ps1: Handles 'Completed' status - skips shutdown polling, goes to FFU capture
- This fixes the "Apps.iso not replaced with WinPE capture ISO" bug

v1.2.8 (2026-01-15)
- FIX: VMware capture boot now boots from WinPE ISO instead of Windows
- Root cause: VMware NVRAM caches boot order from first boot
- When VM boots Windows (hdd,cdrom), NVRAM records "boot from HDD"
- Even when VMX bios.bootOrder is changed to "cdrom,hdd", NVRAM takes precedence
- FIX: AttachISO() now deletes NVRAM file before configuring capture boot
- This forces VMware to read boot order from VMX file on next boot

v1.2.7 (2026-01-14)
- FIX: Hyper-V VM now connects network adapter to virtual switch specified in config
- Root cause: HyperVProvider.CreateVM() didn't connect network adapter to VMSwitchName
- Added New-VMConfiguration -NetworkSwitchName parameter
- BuildFFUVM.ps1 now passes $VMSwitchName to the factory function
- CreateVM() validates switch exists and connects adapter with logging

v1.2.6 (2026-01-14)
- CRITICAL FIX: Hyper-V AttachISO now correctly sets DVD drive as FIRST boot device
- Root cause: AttachISO only added DVD drive but didn't call Set-VMFirmware -FirstBootDevice
- VM was booting from hard disk (Windows) instead of capture ISO (WinPE)
- Added comprehensive logging: BEFORE/AFTER boot device, step-by-step progress, verification
- VMware AttachISO now includes post-write verification of boot order and ISO path
- Update-VMwareVMX now flushes file to disk and verifies settings persisted

v1.2.5 (2026-01-14)
- CHANGED: Increased VM process wait timeout from 10 to 60 seconds in Wait-VMwareVMStart
- Allows more time for slow VM startups before warning about process not found
- Default timeout is now 60 seconds (previously 10 seconds)

v1.2.4 (2026-01-13)
- NEW: Configurable NIC type for VMware VMs (NicType parameter on New-VMwareVMX)
- Options: e1000e (default), vmxnet3, e1000
- e1000e (Intel 82574L emulation) recommended for best WinPE network compatibility
- vmxnet3 provides higher performance but requires paravirtual drivers in WinPE
- Supports new NicType setting in config schema (VMwareSettings.NicType)

v1.2.3 (2026-01-13)
- REMOVED: All .lck folder detection methods (vmx.lck, vmem.lck, generic .lck)
- Root cause: .lck folders persist after VM shutdown, causing false "running" detections
- Simplified detection to 3 methods:
  1. vmware-vmx process detection (PRIMARY - most reliable)
  2. vmrun list (fallback)
  3. nvram file lock (last resort)
- Process detection remains the definitive method for determining VM state

v1.2.2 (2026-01-12)
- FIX: vmrun list broken on VMware 25.0.0 - now uses vmware-vmx process detection as PRIMARY method
- NEW: Test-VMwareVMXProcess function - detects running VMs via Win32_Process/CIM query
- NEW: Wait-VMwareVMStart function - verifies VM actually started after vmrun returns success
- CHANGED: Get-VMwarePowerStateWithVmrun detection order:
  1. vmware-vmx process detection (PRIMARY - most reliable, context-independent)
  2. vmx.lck folder check
  3. vmem.lck folder check
  4. vmrun list (DEMOTED - broken on some systems)
  5. nvram file lock
  6. Generic .lck folder check
- CHANGED: Set-VMwarePowerStateWithVmrun now verifies VM process appears within 10 seconds
- Root cause: vmrun -T ws list returns 0 VMs on some VMware 25.0.0 installations

v1.2.1 (2026-01-12)
- FIX: VMware 25.0.0 compatibility - VMs may not have nvram files
- vmx.lck folder check is now PRIMARY fallback method (not nvram)
- Added vmem.lck folder detection as additional running indicator
- nvram check is now tertiary (only if nvram file exists)
- Handles missing nvram files gracefully with informational log message
- Better diagnostic logging for all lock folder checks
- Root cause: VMware 25.0.0 doesn't create nvram files for some VM configs

v1.2.0 (2026-01-12)
- BREAKING: Removed vmrest REST API dependency entirely
- NEW: Uses vmrun.exe directly for all VM operations (no authentication required)
- NEW: Optional vmxtoolkit PowerShell module support for enhanced operations
- NEW: vmxtoolkit availability checked in VMwareProvider constructor
- REMOVED: vmrest service startup/management (Start-VMrestService.ps1 deleted)
- REMOVED: Credential management (SetCredential method, Port property)
- REMOVED: REST API functions (Invoke-VMwareRestMethod, Get-VMwareVMList, etc.)
- KEPT: Reliable file lock detection for VM state
- KEPT: ShowVMConsole option (gui/nogui mode)
- Simpler architecture, fewer dependencies, no authentication issues

v1.1.23 (2026-01-12)
- FIX: Improved VM state detection to properly detect shutdown
- nvram file lock test is now PRIMARY detection method (most reliable)
- If nvram file can be opened exclusively, VM is definitely OFF
- Lock folder checks are now secondary and check for ACTIVE .lck files inside
- Stale lock folders (after VM shutdown) no longer cause false "running" detection
- Root cause: .lck folders may persist briefly after shutdown

v1.1.22 (2026-01-12)
- FIX: Get-VMwarePowerStateWithVmrun now uses multiple detection methods
- vmrun list may fail to show running VMs (known VMware bug on some systems)
- Added fallback: Check for .lck folders in VM directory (VMware creates these when VM runs)
- Added fallback: Check if nvram file is locked by VMware process
- Added diagnostic logging: shows raw vmrun list output and path comparisons
- Root cause of "VM failed to start" - vmrun list returned empty despite VM running

v1.1.21 (2026-01-12)
- FIX: Set-VMwareBootISO now changes boot order to "cdrom,hdd" for WinPE capture
- Previous boot order "hdd,cdrom" was correct for initial Windows boot
- But during FFU CAPTURE, VM must boot WinPE from ISO, not Windows from VHD
- Added diagnostic logging: shows current and new boot order when attaching ISO
- Root cause of "VM shutdown timeout" - WinPE never booted, Windows booted instead

v1.1.20 (2026-01-11)
- FIX: Added VHD to VMware SupportedDiskFormats capability list
- Validation was rejecting VHD format even though VMware 10+ supports it
- Error was: "Disk format 'VHD' not supported by VMware. Supported: VMDK"

v1.1.19 (2026-01-11)
- FIX: VMware VM now uses VHD file directly instead of creating empty VMDK
- VMware Workstation 10+ supports VHD files as virtual disks
- Previously: VHD with Windows was created, then empty VMDK was created (boot failure)
- Now: VHD with Windows is passed directly to VMware (VM boots correctly)
- BuildFFUVM.ps1 no longer changes .vhd extension to .vmdk for VMware

v1.1.18 (2026-01-11)
- FIX: VMware VM boot order changed from "cdrom,hdd" to "hdd,cdrom"
- FFU builds apply Windows to VHD before VM boot - HDD must be first
- VM was failing to boot because it looked for CD-ROM first (which has no bootable media)

v1.1.17 (2026-01-11)
- FIX: Added ulm.disableMitigations = TRUE to VMX for Hyper-V host compatibility
- Disables side-channel mitigations popup (KB79832) on systems with Hyper-V enabled
- See: https://knowledge.broadcom.com/external/article?legacyId=79832

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
