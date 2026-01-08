@{
    # Module manifest for FFU.Hypervisor
    # Hypervisor abstraction layer for FFU Builder

    # Script module or binary module file associated with this manifest
    RootModule = 'FFU.Hypervisor.psm1'

    # Version number of this module
    ModuleVersion = '1.1.0'

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
