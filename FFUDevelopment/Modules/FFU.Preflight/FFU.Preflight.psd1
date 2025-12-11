#
# Module manifest for module 'FFU.Preflight'
#

@{
    # Script module or binary module file associated with this manifest.
    RootModule = 'FFU.Preflight.psm1'

    # Version number of this module.
    ModuleVersion = '1.0.1'

    # ID used to uniquely identify this module
    GUID = 'a7e8b3f2-c4d5-4e6a-9b8c-1d2e3f4a5b6c'

    # Author of this module
    Author = 'FFU Builder Team'

    # Company or vendor of this module
    CompanyName = 'Community'

    # Copyright statement for this module
    Copyright = '(c) 2025 FFU Builder Team. MIT License.'

    # Description of the functionality provided by this module
    Description = 'Comprehensive pre-flight validation system for FFU Builder. Provides tiered environment checks (Administrator, PowerShell 7+, Hyper-V, ADK, disk space, network, antivirus) with actionable remediation guidance. Fail-fast design detects all issues before build operations begin.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.0'

    # Modules that must be imported into the global environment prior to importing this module
    # Note: FFU.Core is OPTIONAL - only loaded dynamically when ConfigFile validation is used
    # All other validation is self-contained to avoid WriteLog dependency issues
    RequiredModules = @()

    # Assemblies that must be loaded prior to importing this module
    RequiredAssemblies = @()

    # Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
    FunctionsToExport = @(
        # Main entry point
        'Invoke-FFUPreflight',
        # Tier 1: Critical (Always Run, Blocking)
        'Test-FFUAdministrator',
        'Test-FFUPowerShellVersion',
        'Test-FFUHyperV',
        # Tier 2: Feature-Dependent (Conditional, Blocking)
        'Test-FFUADK',
        'Test-FFUDiskSpace',
        'Test-FFUNetwork',
        'Test-FFUConfigurationFile',
        'Test-FFUWimMount',
        # Tier 3: Recommended (Warnings Only)
        'Test-FFUAntivirusExclusions',
        # Tier 4: Cleanup (Pre-Remediation)
        'Invoke-FFUDISMCleanup',
        # Helper functions
        'New-FFUCheckResult',
        'Get-FFURequirements'
    )

    # Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
    AliasesToExport = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
    PrivateData = @{
        PSData = @{
            # Tags applied to this module. These help with module discovery in online galleries.
            Tags = @('FFU', 'Windows', 'Preflight', 'Validation', 'Hyper-V', 'ADK', 'Prerequisites')

            # A URL to the license for this module.
            LicenseUri = 'https://github.com/Schweinehund/FFU/blob/feature/improvements-and-fixes/LICENSE'

            # A URL to the main website for this project.
            ProjectUri = 'https://github.com/Schweinehund/FFU'

            # ReleaseNotes of this module
            ReleaseNotes = @'
# Release Notes - FFU.Preflight v1.0.1

## v1.0.1 (2025-12-11)
### New Feature: WIM Mount Capability Validation
- Added Test-FFUWimMount function for validating WIM mount infrastructure
- Addresses DISM error 0x800704DB "The specified service does not exist"
- Validates WIMMount service, WOF service, FltMgr service, and driver files
- Automatic remediation via service restart and driver re-registration
- Integrated into Invoke-FFUPreflight when ADK/WinPE operations are needed
- Comprehensive Pester test suite (28+ tests)

### Checks Performed:
- WIMMount service existence and status
- WOF (Windows Overlay Filter) service existence
- Filter Manager (FltMgr) service status
- wimmount.sys driver file (System32\drivers)
- wof.sys driver file (System32\drivers)

### Remediation Actions (when -AttemptRemediation used):
1. Restart FltMgr service if stopped
2. Restart WIMMount service if stopped
3. Re-register WIM mount driver via rundll32.exe wimmount.dll,WimMountDriver

---

## v1.0.0 (Initial Release)
- Comprehensive pre-flight validation system for FFU Builder
- Tiered validation architecture with fail-fast design
- Feature-aware validation (only checks requirements for enabled features)
- Actionable remediation guidance for every failure

### Validation Tiers

#### Tier 1: CRITICAL (Always Run, Blocking)
- Test-FFUAdministrator: Verify Administrator privileges
- Test-FFUPowerShellVersion: Require PowerShell 7.0+
- Test-FFUHyperV: Check Hyper-V feature installation

#### Tier 2: FEATURE-DEPENDENT (Conditional, Blocking)
- Test-FFUADK: ADK installation (Deployment Tools, WinPE add-on)
- Test-FFUDiskSpace: Calculate required space based on enabled features
- Test-FFUNetwork: Basic connectivity check (DNS + HTTPS)
- Test-FFUConfigurationFile: Config file validation (calls FFU.Core)
- Test-FFUWimMount: WIM mount infrastructure validation (v1.0.1)

#### Tier 3: RECOMMENDED (Warnings Only)
- Test-FFUAntivirusExclusions: Check Windows Defender exclusions

#### Tier 4: CLEANUP (Pre-Remediation)
- Invoke-FFUDISMCleanup: Clean stale mounts, temp dirs, orphaned VHDs

### Key Design Decisions
- NO TrustedInstaller running state check (it is a demand-start service)
- Feature-aware validation reduces unnecessary checks
- Delegates to existing functions (Test-ADKPrerequisites, Test-FFUConfiguration)
- Returns structured result object with aggregated errors, warnings, remediation steps

### Dependencies
- FFU.Core module for WriteLog, Test-FFUConfiguration
- FFU.ADK module for Test-ADKPrerequisites
- Administrator privileges for Hyper-V and DISM operations
'@
        }
    }
}
