# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Specialized Agents

**Invoke with:** `Task tool with subagent_type="<agent-name>"`

| Agent | Use For |
|-------|---------|
| `powershell-architect` | Architecture review, code quality, PowerShell best practices, refactoring |
| `intune-troubleshooter` | Intune/MDM issues, enrollment failures, policy deployment, compliance |
| `autopilot-deployment-expert` | Autopilot deployment, ESP failures, Azure AD Join, diagnostics |
| `pester-test-developer` | Pester 5.x tests, coverage analysis, mocking, test debugging |
| `verify-app` | Application verification, Pester execution, UI validation, change verification |
| `ffubuilder-pm` | Pre/post implementation checklist (invoke with `general-purpose` subagent) |

**Rule:** Proactively invoke agents when user problems match their expertise.

### Testing Quick Reference
```powershell
.\Tests\Unit\Invoke-PesterTests.ps1                          # All tests
.\Tests\Unit\Invoke-PesterTests.ps1 -Module 'FFU.Core'       # Specific module
.\Tests\Unit\Invoke-PesterTests.ps1 -EnableCodeCoverage      # With coverage
```

### PM Checklist (for all code changes)
See [docs/PM_CHECKLIST.md](docs/PM_CHECKLIST.md) for full checklist. Key items:
1. Version updated in .psd1 manifest
2. Pester tests created/updated
3. Error handling follows patterns (try/catch)
4. CLAUDE.md updated if architecture changed
5. Keep CLAUDE.md under 1000 lines (archive to `docs/VERSION_ARCHIVE.md`)

### Mandatory Verification (BLOCKING)

**Rule:** After ANY PowerShell code changes, invoke `verify-app` before proceeding to code review.

```
Invoke: Task tool with subagent_type="general-purpose"
Prompt: "Act as verify-app agent (read .claude/agents/verify-app.md). Run full regression verification."
```

**Verification is BLOCKING** - implementation cannot continue until:
- All Pester tests pass (failures halt progress)
- No new PSScriptAnalyzer errors
- All modules import successfully
- Code coverage maintained or improved

**HALT CONDITIONS:** If verification fails, return to implementation and fix issues before proceeding.

See `.claude/commands/implement.md` Phase 4.3 for full workflow integration.

## Project Overview

**FFUBuilder** - Improvements and bug fixes for the FFU (Full Flash Update) project, a Windows deployment acceleration tool that creates pre-configured Windows 11 images deployable in under 2 minutes.

**Upstream Repository:** https://github.com/rbalsleyMSFT/FFU/tree/UI_2510
**Primary Language:** PowerShell (98.8%)
**Architecture:** WPF-based UI with PowerShell automation and Hyper-V integration
**License:** MIT

This fork focuses on addressing critical bugs (#327, #324, #319, #318, #301, #298, #268) and implementing architectural improvements for maintainability, reliability, and extensibility.

## Architecture

### Param Block Coupling

**Why this coupling exists:** PowerShell param blocks are evaluated at parse time, before any module imports execute. Using `[FFUConstants]::CONSTANT` in param defaults causes failure when scripts run in ThreadJob contexts with different working directories, because the module cannot be loaded during parse.

**Coupled parameters in BuildFFUVM.ps1:**

| Parameter | Default Value | FFU.Constants Property |
|-----------|---------------|------------------------|
| Memory | 4GB (4294967296) | DEFAULT_VM_MEMORY |
| Disksize | 50GB (53687091200) | DEFAULT_VHDX_SIZE |
| Processors | 4 | DEFAULT_VM_PROCESSORS |

**Maintenance Note:** If you change values in `FFU.Constants.psm1`, you MUST also update the corresponding param defaults in `BuildFFUVM.ps1` (lines 7-18).

Reference: BuildFFUVM.ps1 contains inline comments at lines 7-18 explaining this coupling.

## Workflow Requirements

### Mandatory Steps for Every Code Change

**BEFORE making changes:**
1. Consult ffubuilder-pm agent to get pre-implementation checklist
2. Identify which modules will be affected
3. Note current version numbers of affected modules

**DURING implementation:**
4. Use powershell-architect agent for code implementation
5. Follow error handling patterns (try/catch with specific exceptions)
6. Register cleanup actions for new resources

**AFTER implementation:**
7. Update version numbers in affected .psd1 manifests
8. Add release notes to manifests
9. Create/update Pester tests (use pester-test-developer agent if needed)
10. Run tests to verify changes work
11. Consult ffubuilder-pm agent for post-implementation verification
12. Update CLAUDE.md if architecture/patterns changed
13. Update `CHANGELOG_FORK.md` with new fixes/enhancements

## GSD Command Integration

When using `/gsd:*` commands in this project, the following FFUBuilder-specific requirements MUST be followed. **These rules apply universally** whether using `/implement` or `/gsd:*` commands.

### During `/gsd:execute-plan` or `/gsd:execute-phase`

1. **Code Standards**: All PowerShell code must follow [PowerShell Style Standards](#powershell-style-standards)
2. **Error Handling**: Use try/catch patterns from [IMPLEMENTATION_PATTERNS.md](docs/IMPLEMENTATION_PATTERNS.md)
3. **Cleanup Registration**: Register cleanup actions for new resources (see PM Checklist)

### After Code Changes (BLOCKING)

Before marking any GSD plan/phase as complete:

1. **Run verify-app**: Invoke `verify-app` agent for automated verification
   ```
   Invoke: Task tool with subagent_type="general-purpose"
   Prompt: "Act as verify-app agent (read .claude/agents/verify-app.md). Run full regression verification."
   ```
2. **Update Versions**: Bump affected .psd1 manifests + version.json (see [Version Increment Checklist](#version-increment-checklist))
3. **Run Tests**: Ensure all Pester tests pass
4. **PSScriptAnalyzer**: No new errors

**HALT CONDITIONS**: If any of the above fail, the GSD plan/phase CANNOT be marked complete. Return to implementation and fix issues.

### `/gsd:verify-work` Enhancement

When `/gsd:verify-work` is invoked in this project:

1. **First**: Run automated verification (verify-app workflow)
2. **Then**: Proceed to conversational UAT if automated checks pass
3. **Report**: Include both automated test results AND UAT findings

### Version Management

Any GSD phase that modifies code requires:

- Module `.psd1` version bump (see [Module Version Locations](docs/PM_CHECKLIST.md#module-version-locations))
- `version.json` update (main version PATCH bump minimum)
- Release notes in `.psd1`
- `CHANGELOG_FORK.md` entry

## Versioning Policy

**Current Version:** 1.3.0
**Single Source of Truth:** `FFUDevelopment/version.json`

This project follows [Semantic Versioning](https://semver.org/) with centralized version management.

### Version File Location
All version information is stored in `version.json` in the FFUDevelopment folder:
- Main FFU Builder version
- Build date
- All module versions with descriptions
- Versioning policy documentation

### Version Bump Rules

| Change Type | Version | When to Bump | Examples |
|-------------|---------|--------------|----------|
| **MAJOR** | X.0.0 | Breaking changes to configs/scripts OR major milestones | Removing parameters, changing config format, UI overhaul |
| **MINOR** | 0.X.0 | New user-facing features OR significant improvements | New OEM driver support, new UI tabs, major performance gains |
| **PATCH** | 0.0.X | Bug fixes OR any subcomponent version change | Error handling fixes, module updates, logging improvements |

**Key Rule:** Any subcomponent (module) version change automatically requires a PATCH bump to the main FFU Builder version.

### Version Increment Checklist
1. Update the affected module's `.psd1` manifest version
2. Update `version.json`:
   - Bump main version (PATCH for module changes, MINOR for features, MAJOR for breaking)
   - Update `buildDate` to current date
   - Update the module version in the `modules` section
3. Add release notes to the affected module's `.psd1` manifest
4. The UI automatically reads from `version.json` on startup

### Helper Functions
```powershell
# Get current version info
Get-FFUBuilderVersion -FFUDevelopmentPath "C:\FFUDevelopment"

# Get specific module version
Get-FFUBuilderVersion -FFUDevelopmentPath "C:\FFUDevelopment" -ModuleName "FFU.Common"

# Update version (increments main version and optionally updates module)
Update-FFUBuilderVersion -FFUDevelopmentPath "C:\FFUDevelopment" -BumpType Patch -ModuleName "FFU.Common" -ModuleVersion "0.0.5"
```

### UI Display
- Window title shows: "FFU Builder UI v1.2.0"
- About tab shows: Main version, build date, and all module versions with tooltips

## Version History

| Version | Date | Type | Description |
|---------|------|------|-------------|
| 1.6.0 | 2026-01-07 | MINOR | VMware Workstation Pro integration - UI hypervisor selection, config schema, auto-detection |
| 1.5.0 | 2026-01-07 | MINOR | Full VMware provider - REST API, VM lifecycle, diskpart-based disk ops |
| 1.4.0 | 2026-01-06 | MINOR | FFU.Hypervisor module - Provider pattern, IHypervisorProvider interface |
| 1.3.12 | 2025-12-17 | PATCH | WimMount auto-repair - `fltmc filters` check, registry repair, service restart |
| 1.3.11 | 2025-12-15 | PATCH | WIMMount JIT validation in New-WinPEMediaNative |
| 1.3.10 | 2025-12-15 | PATCH | FFU.Common.Logging signature compatibility fix |
| 1.3.9 | 2025-12-15 | PATCH | Invoke-WimMountWithErrorHandling with 0x800704db detection |
| 1.3.8 | 2025-12-15 | PATCH | WimMount pre-flight now BLOCKING with remediation guidance |
| 1.3.7 | 2025-12-13 | MINOR | Native WinPE creation - New-WinPEMediaNative replaces copype.cmd |

> **Note:** Older versions archived in [docs/VERSION_ARCHIVE.md](docs/VERSION_ARCHIVE.md). See `version.json` for complete history.

### Component Structure

```
BuildFFUVM_UI.ps1 (WPF UI Host)
├── FFUUI.Core (UI Framework)
├── FFU.Common (Business Logic Module - shared between UI and build script)
│   ├── FFU.Common.Core.psm1 (WriteLog, error handling, path utilities)
│   ├── FFU.Common.Download.psm1 (Resilient downloads: BITS → WebRequest → WebClient → curl)
│   ├── FFU.Common.ParallelDownload.psm1 (Concurrent downloads with PS7 Parallel / PS5.1 RunspacePool)
│   ├── FFU.Common.Parallel.psm1 (Runspace-based parallel execution for UI)
│   ├── FFU.Common.Winget.psm1 (WinGet package management)
│   ├── FFU.Common.Drivers.psm1 (Driver download utilities)
│   ├── FFU.Common.Cleanup.psm1 (Build artifact cleanup)
│   └── FFU.Common.Classes.psm1 (Shared class definitions)
└── BuildFFUVM.ps1 (Core Build Orchestrator - 2,404 lines after modularization)
    └── Modules/ (Extracted functions now in 11 specialized modules)
        ├── FFU.Core (Core functionality - 36 functions for configuration, session tracking, error handling, cleanup, credential management)
        ├── FFU.Apps (Application management - 5 functions for Office, Apps ISO, cleanup)
        ├── FFU.Drivers (OEM driver management - 5 functions for Dell, HP, Lenovo, Microsoft)
        ├── FFU.VM (Hyper-V VM operations - 3 functions for VM lifecycle)
        ├── FFU.Hypervisor (Hypervisor abstraction - Provider pattern supporting Hyper-V and VMware Workstation Pro)
        ├── FFU.Media (WinPE media creation - 4 functions for PE media and architecture)
        ├── FFU.ADK (Windows ADK management - 8 functions for validation and installation)
        ├── FFU.Updates (Windows Update handling - 8 functions for KB downloads and MSU processing)
        ├── FFU.Imaging (DISM and FFU operations - 15 functions for partitioning, imaging, FFU creation)
        ├── FFU.Preflight (Pre-flight validation - 12 functions for tiered environment checks with remediation)
        └── FFU.Messaging (Thread-safe UI/job communication - 14 functions for queue-based messaging, progress, cancellation)
```

### Modularization Status (Completed)
- **Original file:** BuildFFUVM.ps1 with 7,790 lines
- **After extraction:** BuildFFUVM.ps1 reduced to 2,404 lines (69% reduction)
- **Functions extracted:** 64 total functions moved to 8 modules + 14 new messaging functions
- **Lines removed:** 5,387 lines (functions from lines 674-6059)
- **Module imports added:** After param block at lines 552-569
- **PSModulePath handling:** Modules folder added to path for RequiredModules resolution
- **UI compatibility:** Fully compatible with BuildFFUVM_UI.ps1 background job execution
- **Test coverage:** 100% pass rate (23/23 tests) in Test-UIIntegration.ps1

### UI Integration and Background Jobs

The modular architecture is fully compatible with BuildFFUVM_UI.ps1:

**How it works:**
1. BuildFFUVM_UI.ps1 launches BuildFFUVM.ps1 in a PowerShell background job (ThreadJob or Start-Job)
2. BuildFFUVM.ps1 automatically adds `Modules/` folder to `$env:PSModulePath` on startup
3. This allows PowerShell RequiredModules declarations in manifests to resolve correctly
4. All 8 modules import cleanly in the background job context
5. Functions are available throughout the build process

**Key implementation details:**
```powershell
# BuildFFUVM.ps1 lines 552-569
$ModulePath = "$PSScriptRoot\Modules"

# Add modules folder to PSModulePath for RequiredModules resolution
if ($env:PSModulePath -notlike "*$ModulePath*") {
    $env:PSModulePath = "$ModulePath;$env:PSModulePath"
}

# Import modules in dependency order
Import-Module "FFU.Core" -Force -ErrorAction Stop
Import-Module "FFU.ADK" -Force -ErrorAction Stop
# ... (remaining 6 modules)
```

**Module dependencies:**
- FFU.Core: No dependencies (foundation module)
- FFU.ADK: Requires FFU.Core
- FFU.Media: Requires FFU.Core and FFU.ADK
- FFU.Imaging: Requires FFU.Core
- FFU.Updates: Requires FFU.Core
- FFU.VM, FFU.Drivers, FFU.Apps: Require FFU.Core
- FFU.Messaging: No dependencies (standalone for UI/job communication)

**Testing:**
Run `Test-UIIntegration.ps1` to verify UI compatibility:
- Module directory structure validation
- Import tests in clean PowerShell sessions
- Background job simulation (mimics UI launch mechanism)
- Function export verification (64 unique functions across 8 modules)
- Module dependency chain validation
- Function name conflict detection

### Module Dependency Hierarchy (v1.2.4)

All modules declare their dependencies using standardized hashtable format in `RequiredModules`:

```
FFU.Constants (v1.1.0) - Foundation module, no dependencies
└── FFU.Core (v1.0.9) - Requires FFU.Constants
    ├── FFU.ADK (v1.0.0) - Requires FFU.Core
    ├── FFU.Apps (v1.0.0) - Requires FFU.Core
    ├── FFU.Drivers (v1.0.2) - Requires FFU.Core
    ├── FFU.Imaging (v1.0.1) - Requires FFU.Core
    ├── FFU.Updates (v1.0.1) - Requires FFU.Core
    ├── FFU.VM (v1.0.2) - Requires FFU.Core
    └── FFU.Media (v1.0.0) - Requires FFU.Core, FFU.ADK
```

**RequiredModules Format Standard:**
```powershell
# All modules use this standardized hashtable format
RequiredModules = @(
    @{ModuleName = 'FFU.Core'; ModuleVersion = '1.0.0'}
)
```

**Automatic Dependency Loading:**
- PowerShell automatically loads required modules when importing a dependent module
- Example: `Import-Module FFU.Media` automatically loads FFU.Core, FFU.ADK, and FFU.Constants
- The dependency chain is: FFU.Media -> FFU.ADK -> FFU.Core -> FFU.Constants

**Testing Module Dependencies:**
```powershell
# Run comprehensive dependency tests (117 tests)
Invoke-Pester -Path 'Tests/Unit/Module.Dependencies.Tests.ps1' -Output Detailed
```

### Module Summary

| Module | Purpose | Key Functions |
|--------|---------|---------------|
| FFU.Core | Configuration, logging, error handling, credentials | 39 functions - see [MODULE_REFERENCE.md](docs/MODULE_REFERENCE.md) |
| FFU.VM | Hyper-V VM lifecycle | `New-FFUVM`, `Remove-FFUVM`, `Get-FFUEnvironment` |
| FFU.Hypervisor | Multi-platform hypervisor abstraction | Provider pattern for Hyper-V/VMware |
| FFU.Apps | Application management | Office, Apps ISO, cleanup |
| FFU.Updates | Windows Update handling | KB downloads, MSU processing |
| FFU.Messaging | Thread-safe UI communication | ConcurrentQueue-based messaging |
| FFU.ADK | Windows ADK management | Validation, installation |
| FFU.Media | WinPE media creation | Native WinPE method |
| FFU.Imaging | DISM/FFU operations | Partitioning, imaging |
| FFU.Drivers | OEM driver management | Dell, HP, Lenovo, Microsoft |
| FFU.Preflight | Pre-flight validation | Environment checks, WIMMount |

> **Detailed Reference:** See [docs/MODULE_REFERENCE.md](docs/MODULE_REFERENCE.md) for complete function lists and parameters.

### Key Design Patterns

- **Event-Driven UI:** WPF with DispatcherTimer for non-blocking background job polling (50ms interval)
- **Thread-Safe Messaging:** ConcurrentQueue-based UI/job communication via FFU.Messaging module
- **Background Job Pattern:** Long-running builds in separate PowerShell runspaces (ThreadJob for credential inheritance)
- **Provider Pattern:** OEM-specific driver download/extraction implementations
- **Configuration as Code:** JSON-based configuration with CLI override support

### Critical Dependencies

- **Windows 10/11** with Hyper-V enabled
- **Windows ADK** with Deployment Tools and WinPE add-on
- **PowerShell 5.1+** (Windows PowerShell 5.1 or PowerShell 7+)
  - **Cross-version compatibility:** Works natively in both PowerShell 5.1 and PowerShell 7+
  - **No version switching required:** Uses .NET DirectoryServices APIs for local user management
  - **Avoids TelemetryAPI errors:** Cross-version compatible implementations of New-LocalUser, Get-LocalUser, Remove-LocalUser
  - **UI works in both versions:** BuildFFUVM_UI.ps1 supports PowerShell 5.1+ (recommended: PowerShell 7+ for best performance)
- **DISM, expand.exe, BITS** for image manipulation and downloads

### ThreadJob Compatibility

The UI runs builds via `Start-ThreadJob` for credential inheritance and responsive UI. ThreadJob runspaces have **limited cmdlet availability** - `Microsoft.PowerShell.Core` and `Microsoft.PowerShell.Utility` cmdlets can become temporarily unavailable during heavy operations.

**Avoid in code that runs during builds:**
| Cmdlet | .NET/PowerShell Alternative |
|--------|------------------|
| `Get-Date` | `[DateTime]::Now` |
| `Write-Host` | `[Console]::WriteLine()` |
| `Write-Warning` | `[Console]::Error.WriteLine()` or safe logging pattern |
| `Get-Command FuncName` | `$function:FuncName` (for functions) |
| `Get-Command CmdletName` | try/catch around actual cmdlet call |
| `Get-Command exe.exe` | `Find-ExecutableInPath 'exe.exe'` (FFU.Common.Core) |

**Safe Logging Pattern (for warning messages):**
```powershell
# Uses $function: drive instead of Get-Command for ThreadJob compatibility (v0.0.12)
$warningMsg = "Your warning message here"
if ($function:WriteLog) {
    WriteLog "WARNING: $warningMsg"
}
else {
    Write-Verbose "WARNING: $warningMsg"
}
```

**Why ThreadJob?** Credential inheritance for network shares. `Start-Job` would require explicit credential passing (security concern).

**Fix History:**
- v0.0.9: Get-Date → [DateTime]::Now
- v0.0.10: Write-Host → [Console]::WriteLine
- v0.0.11: Write-Warning → [Console]::Error.WriteLine
- v0.0.12: Get-Command → $function: / try-catch / Find-ExecutableInPath

## Development Commands

### Running the UI Application

```powershell
# Launch the WPF UI (primary interface)
cd C:\FFUDevelopment
.\BuildFFUVM_UI.ps1
```

### Running Core Build Script Directly

```powershell
# Execute build without UI (for automation/testing)
.\BuildFFUVM.ps1 -ConfigFile "config.json" -Verbose

# Example with parameters
.\BuildFFUVM.ps1 -VMName "FFU_Build_VM" `
                 -WindowsRelease "23H2" `
                 -OEM "Dell" `
                 -Model "Latitude 7490" `
                 -ApplyDrivers $true
```

### Testing

```powershell
# Run Pester unit tests
Invoke-Pester -Path ".\Tests\Unit" -Output Detailed

# Run integration tests
Invoke-Pester -Path ".\Tests\Integration" -Output Detailed

# Run all tests with coverage
Invoke-Pester -Path ".\Tests" -CodeCoverage ".\FFU.Common\*.ps1" -Output Detailed
```

### Code Quality

```powershell
# Run PSScriptAnalyzer for code quality checks
Invoke-ScriptAnalyzer -Path ".\FFU.Common" -Recurse -Severity Warning,Error

# Run on specific file
Invoke-ScriptAnalyzer -Path ".\BuildFFUVM.ps1" -Settings PSGallery
```

## PowerShell Style Standards

All PowerShell code in this project follows the [PoshCode Practice and Style Guide](https://github.com/PoshCode/PowerShellPracticeAndStyle).

**Key Requirements:**
- One True Brace Style (OTBS) - opening brace at end of line
- Full cmdlet names (no aliases)
- Explicit parameter names (`-Path $x` not `$x`)
- 4-space indentation, 115 char max lines
- `[CmdletBinding()]` and `[OutputType()]` on all functions

**Validation:**
```powershell
Invoke-ScriptAnalyzer -Path .\FFUDevelopment -Recurse -ReportSummary
```

### Creating USB Deployment Media

```powershell
# After FFU build completes
.\USBImagingToolCreator.ps1 -FFUPath "C:\FFUDevelopment\FFU\MyImage.ffu"
```

## Implementation Patterns

> **Detailed Patterns:** See [docs/IMPLEMENTATION_PATTERNS.md](docs/IMPLEMENTATION_PATTERNS.md) for complete examples.

### Essential Patterns (Quick Reference)

**Error Handling:** Use `Invoke-WithErrorHandling`, `Test-ExternalCommandSuccess`, `Invoke-WithCleanup` from FFU.Core
**Constants:** Never hardcode values - use `[FFUConstants]::CONSTANT_NAME`
**Type Safety:** Never pass booleans as paths - use `[FFUPaths]::ExpandPath()`
**Proxy Support:** Use `[FFUNetworkConfiguration]::DetectProxySettings()` for all network ops
**Config Validation:** Use `Test-FFUConfiguration -ConfigPath "config.json"`
**Pre-flight:** Always call `$validator.ValidateAll()` before builds

## Known Issues and Workarounds

### Open Issues

#### Issue #327: Corporate Proxy Failures
**Symptoms:** Driver downloads fail with network errors behind Netskope/zScaler
**Workaround:** Manually configure proxy in UI settings or set environment variables:
```powershell
$env:HTTP_PROXY = "http://proxy.corp.com:8080"
$env:HTTPS_PROXY = "http://proxy.corp.com:8080"
```

#### Issue #301: Unattend.xml Extraction from MSU
**Symptoms:** DISM fails to apply unattend.xml from update packages
**Workaround:** Use `Get-UnattendFromMSU` function for robust extraction with validation

#### Issue #298: OS Partition Size Limitations
**Symptoms:** OS partition doesn't expand when injecting large driver sets
**Workaround:** Call `Expand-FFUPartition` before driver injection to resize VHDX dynamically

#### Dell Chipset Driver Hang
**Known Issue:** Dell chipset driver installers may hang when run with `-Wait $true`
**Solution:** Always use `-Wait $false` for Dell driver extraction:
```powershell
Start-Process -FilePath $dellDriver -ArgumentList "/s /e=$destination" -Wait:$false
```

#### Lenovo PSREF API Authentication
**Known Issue:** Hardcoded JWT token will expire
**Solution:** Implement proper OAuth flow in `LenovoDriverProvider.RefreshAuthToken()`

### Fixed Issues

For detailed fix documentation, see:
- **[docs/FIXED_ISSUES_ARCHIVE.md](docs/FIXED_ISSUES_ARCHIVE.md)** - Comprehensive fix documentation with root cause analysis
- **[docs/fixes/](docs/fixes/)** - Individual fix summary files

| Issue | Version | Quick Reference |
|-------|---------|-----------------|
| WIMMount JIT Validation Missing | v1.3.11 | Added Test-FFUWimMount call before Mount-WindowsImage in New-WinPEMediaNative |
| WimMount Warning (False Positives) | v1.3.6 | **SUPERSEDED** - native cmdlets DO require WIMMount service |
| DISM WIM Mount Error 0x800704DB | v1.3.5 | **CORRECTED v1.3.8** - Both ADK and native cmdlets require WIMMount |
| [FFUConstants] Type Not Found | v1.2.9 | Hardcoded VM poll interval value |
| FFU.Constants Not Found in ThreadJob | v1.2.8 | Removed `using module`, added Set-Location in UI |
| Module Loading Failure | v1.2.7 | Early PSModulePath setup, defensive error handlers |
| Hardcoded Installation Paths | v1.2.3 | Dynamic path resolution via GetBasePath() |
| DISM Initialization 0x80004005 | v1.2.2 | Early logging, DISM cleanup, retry logic |
| Monitor Tab Stale Logs | v1.2.1 | StreamReader cleanup, pre-delete log file |
| Module Best Practices | v1.0.11 | Renamed unapproved verbs with aliases |

## Project Structure

```
FFUDevelopment/
├── BuildFFUVM.ps1              # Core orchestrator
├── BuildFFUVM_UI.ps1           # WPF UI launcher
├── Modules/                    # 11 PowerShell modules (see Module Summary above)
├── FFU.Common/                 # Business logic (Classes/, Functions/)
├── FFUUI.Core/                 # UI framework
├── Drivers/Providers/          # OEM driver implementations (Dell, HP, Lenovo, Microsoft)
├── Tests/                      # Pester test suites (Unit/, Integration/, UI/)
└── Logs/                       # Runtime logs
```

## Quick References

| Topic | Location |
|-------|----------|
| Debugging tips | [docs/IMPLEMENTATION_PATTERNS.md](docs/IMPLEMENTATION_PATTERNS.md#debugging-tips) |
| Customization guide | [docs/IMPLEMENTATION_PATTERNS.md](docs/IMPLEMENTATION_PATTERNS.md#common-customizations) |
| Performance optimization | [docs/IMPLEMENTATION_PATTERNS.md](docs/IMPLEMENTATION_PATTERNS.md#performance-optimization) |
| Security considerations | [docs/IMPLEMENTATION_PATTERNS.md](docs/IMPLEMENTATION_PATTERNS.md#security-considerations) |
| Module details | [docs/MODULE_REFERENCE.md](docs/MODULE_REFERENCE.md) |
| Fixed issues archive | [docs/FIXED_ISSUES_ARCHIVE.md](docs/FIXED_ISSUES_ARCHIVE.md) |
| Version archive | [docs/VERSION_ARCHIVE.md](docs/VERSION_ARCHIVE.md) |
