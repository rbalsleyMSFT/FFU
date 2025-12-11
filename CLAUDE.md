# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Specialized Agent Usage Policy

**IMPORTANT:** This project has specialized agents that MUST be used for specific tasks:

### powershell-architect Agent
**When to use:**
- Architecture evaluation and code quality analysis
- Identifying design patterns and anti-patterns
- PowerShell best practices and module design
- Performance optimization recommendations
- Refactoring and modularization guidance
- Security vulnerability assessment
- When user explicitly requests architecture review or evaluation

**How to invoke:**
```
Use Task tool with subagent_type="powershell-architect"
```

### intune-troubleshooter Agent
**When to use:**
- Microsoft Intune device management issues
- MDM enrollment failures or errors
- Policy deployment and compliance problems
- Application installation issues via Intune
- Device configuration profile troubleshooting
- Conditional access and authentication issues
- Intune log analysis and diagnostics
- When user mentions Intune, MDM, or mobile device management errors

**How to invoke:**
```
Use Task tool with subagent_type="intune-troubleshooter"
```

### autopilot-deployment-expert Agent
**When to use:**
- Windows Autopilot deployment issues
- Enrollment Status Page (ESP) failures
- Autopilot device registration problems
- Azure AD Join or Hybrid Azure AD Join issues
- White Glove (pre-provisioning) scenarios
- AutopilotDiagnostics.zip log analysis
- Network/proxy issues during Autopilot
- When user mentions Autopilot, ESP, or device provisioning errors

**How to invoke:**
```
Use Task tool with subagent_type="autopilot-deployment-expert"
```

### pester-test-developer Agent
**When to use:**
- Creating Pester 5.x unit tests for FFU Builder modules
- Running test suites with code coverage analysis
- Debugging failing tests
- Adding mocking to tests for external dependencies
- Improving test coverage for modules
- Setting up CI/CD test integration
- When user asks to create, run, or maintain Pester tests

**How to invoke:**
```
Use Task tool with subagent_type="pester-test-developer"
```

**Test Structure:**
```
Tests/Unit/                    # Pester unit tests
├── Invoke-PesterTests.ps1     # Test runner
├── FFU.Core.Tests.ps1         # Module tests
└── _Template.Tests.ps1        # Template for new tests
```

**Running Tests:**
```powershell
# All tests
.\Tests\Unit\Invoke-PesterTests.ps1

# Specific module
.\Tests\Unit\Invoke-PesterTests.ps1 -Module 'FFU.Core'

# With coverage
.\Tests\Unit\Invoke-PesterTests.ps1 -EnableCodeCoverage
```

### ffubuilder-pm Agent (Project Manager)
**When to use - MANDATORY for all code changes:**
- **Before starting any code modification** - Get checklist of required steps
- **After completing code changes** - Verify all steps were followed
- Ensuring version numbers are updated in module manifests
- Verifying Pester tests are created for new/modified functionality
- Checking that appropriate subagents were used for implementation
- Validating CLAUDE.md is updated if architecture changes
- Reviewing that error handling patterns are followed
- Confirming cleanup mechanisms are registered for new resources
- Ensuring release notes are added to module manifests

**How to invoke:**
```
Use Task tool with subagent_type="general-purpose" with prompt requesting FFUBuilder PM checklist
```

**Checklist the PM agent enforces:**
1. ✅ Version number updated in .psd1 manifest
2. ✅ Release notes added to manifest
3. ✅ Pester tests created/updated for changes
4. ✅ Error handling follows project patterns (try/catch with specific exceptions)
5. ✅ Cleanup registration added for new resources (Register-*Cleanup)
6. ✅ Appropriate subagent used (powershell-architect for code, pester-test-developer for tests)
7. ✅ CLAUDE.md updated if architecture/patterns changed
8. ✅ All tests pass after changes

**CRITICAL:** This agent should be consulted at the START and END of every code modification task.

**General Rule:** When user describes a problem that falls within an agent's expertise area, invoke that agent proactively rather than attempting to solve it directly. These agents have specialized knowledge and diagnostic capabilities beyond general assistance.

## Project Overview

**FFUBuilder** - Improvements and bug fixes for the FFU (Full Flash Update) project, a Windows deployment acceleration tool that creates pre-configured Windows 11 images deployable in under 2 minutes.

**Upstream Repository:** https://github.com/rbalsleyMSFT/FFU/tree/UI_2510
**Primary Language:** PowerShell (98.8%)
**Architecture:** WPF-based UI with PowerShell automation and Hyper-V integration
**License:** MIT

This fork focuses on addressing critical bugs (#327, #324, #319, #318, #301, #298, #268) and implementing architectural improvements for maintainability, reliability, and extensibility.

## Architecture

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
| 1.3.5 | 2025-12-11 | PATCH | Native DISM fix - Replace ADK dism.exe with PowerShell cmdlets (Mount-WindowsImage/Dismount-WindowsImage) in ApplyFFU.ps1 to avoid WIMMount filter driver errors |
| 1.3.4 | 2025-12-11 | PATCH | Defense-in-depth fix for log monitoring - Restore messaging context after FFU.Common -Force import |
| 1.3.3 | 2025-12-11 | PATCH | UI Monitor tab fix - Integrate WriteLog with messaging queue for real-time UI updates |
| 1.3.2 | 2025-12-11 | PATCH | DISM WIM mount error 0x800704DB pre-flight validation with Test-FFUWimMount remediation |
| 1.3.1 | 2025-12-11 | PATCH | Config schema validation fix - Added AdditionalFFUFiles property and 7 deprecated properties (AppsPath, CopyOfficeConfigXML, DownloadDrivers, InstallWingetApps, OfficePath, Threads, Verbose) with backward compatibility warnings |
| 1.3.0 | 2025-12-11 | MINOR | Pre-flight validation system with FFU.Preflight module - Tiered validation (Critical/Feature/Warning/Cleanup), PowerShell 7.0+ requirement, corrected TrustedInstaller handling |
| 1.2.12 | 2025-12-10 | PATCH | Fix FFUMessageLevel type not found - Replace enum type references with string comparisons |
| 1.2.11 | 2025-12-10 | PATCH | Fix MessagingContext parameter not found - Add -MessagingContext parameter to BuildFFUVM.ps1 |
| 1.2.10 | 2025-12-10 | MINOR | Issue #14: Real-time UI updates with FFU.Messaging module (ConcurrentQueue, 50ms timer, 20x faster) |
| 1.2.9 | 2025-12-10 | PATCH | [FFUConstants] type not found during FFU capture - Eliminated runtime FFUConstants type references |
| 1.2.8 | 2025-12-10 | PATCH | FFU.Constants module loading fix - Removed 'using module' statement, added UI Set-Location fix |
| 1.2.7 | 2025-12-10 | PATCH | Module loading failure fix - Early PSModulePath setup and defensive error handlers |
| 1.2.0 | 2025-12-09 | MINOR | Centralized versioning with version.json, module version display in About dialog |
| 1.1.0 | 2025-12-08 | MINOR | Parallel Windows Update downloads - concurrent KB downloads with PS7/PS5.1 support and multi-method fallback |
| 1.0.5 | 2025-12-04 | PATCH | Secure credential management - cryptographic password generation, SecureString handling |
| 1.0.4 | 2025-12-03 | PATCH | Add comprehensive parameter validation to BuildFFUVM.ps1 (15 parameters) |
| 1.0.3 | 2025-12-03 | PATCH | Fix FFU.VM module export - Add missing functions to Export-ModuleMember |
| 1.0.2 | 2025-12-03 | PATCH | Enhanced fix for 0x80070228 - Direct CAB application bypasses UUP download requirement |
| 1.0.1 | 2025-12-03 | PATCH | Fix DISM error 0x80070228 for Windows 11 24H2/25H2 checkpoint cumulative updates |
| 1.0.0 | 2025-12-03 | MAJOR | Initial modularized release with 8 modules, UI version display, credential security |

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
    └── Modules/ (Extracted functions now in 10 specialized modules)
        ├── FFU.Core (Core functionality - 36 functions for configuration, session tracking, error handling, cleanup, credential management)
        ├── FFU.Apps (Application management - 5 functions for Office, Apps ISO, cleanup)
        ├── FFU.Drivers (OEM driver management - 5 functions for Dell, HP, Lenovo, Microsoft)
        ├── FFU.VM (Hyper-V VM operations - 3 functions for VM lifecycle)
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

### Module Architecture

**FFU.Core Module** (FFUDevelopment/Modules/FFU.Core/FFU.Core.psm1)
- **Purpose:** Core utility module providing common configuration management, logging, session tracking, error handling, cleanup registration, and secure credential management
- **Version:** 1.0.11
- **Functions (39 total):**
  - **Configuration & Utilities:** `Get-Parameters`, `Write-VariableValues`, `Get-ChildProcesses`, `Test-Url`, `Get-PrivateProfileString`, `Get-PrivateProfileSection`, `Get-ShortenedWindowsSKU`, `New-FFUFileName`, `Export-ConfigFile`
  - **Session Management:** `New-RunSession`, `Get-CurrentRunManifest`, `Save-RunManifest`, `Set-DownloadInProgress`, `Clear-DownloadInProgress`, `Remove-InProgressItems`, `Clear-CurrentRunDownloads`, `Restore-RunJsonBackups`
  - **Error Handling (v1.0.5):** `Invoke-WithErrorHandling`, `Test-ExternalCommandSuccess`, `Invoke-WithCleanup`
  - **Cleanup Registration (v1.0.6):** `Register-CleanupAction`, `Unregister-CleanupAction`, `Invoke-FailureCleanup`, `Clear-CleanupRegistry`, `Get-CleanupRegistry`
  - **Specialized Cleanup Helpers:** `Register-VMCleanup`, `Register-VHDXCleanup`, `Register-DISMMountCleanup`, `Register-ISOCleanup`, `Register-TempFileCleanup`, `Register-NetworkShareCleanup`, `Register-UserAccountCleanup`
  - **Secure Credential Management (v1.0.7):** `New-SecureRandomPassword`, `ConvertFrom-SecureStringToPlainText`, `Clear-PlainTextPassword`, `Remove-SecureStringFromMemory`
  - **Configuration Validation (v1.0.10):** `Test-FFUConfiguration`, `Get-FFUConfigurationSchema`
- **Deprecated Aliases (v1.0.11):** `LogVariableValues` -> `Write-VariableValues`, `Mark-DownloadInProgress` -> `Set-DownloadInProgress`, `Cleanup-CurrentRunDownloads` -> `Clear-CurrentRunDownloads`
- **Dependencies:** FFU.Constants module (v1.0.9+) for centralized configuration values
- **Security Features:** Cryptographically secure password generation using RNGCryptoServiceProvider, SecureString-first design, proper memory cleanup
- **PowerShell Best Practices (v1.0.11):** All exported functions use approved verbs; deprecated aliases preserve backward compatibility

**FFU.VM Module** (FFUDevelopment/Modules/FFU.VM/FFU.VM.psm1)
- **Purpose:** Hyper-V virtual machine lifecycle management
- **Functions:**
  - `New-FFUVM`: Creates and configures Generation 2 VMs with TPM, memory, processors, and boot devices
  - `Remove-FFUVM`: Cleans up VMs, HGS guardians, certificates, mounted images, and VHDX files
  - `Get-FFUEnvironment`: Comprehensive environment cleanup for dirty state recovery
- **Dependencies:** FFU.Core module for logging and common variables
- **Requirements:** Administrator privileges, Hyper-V feature enabled

**FFU.Apps Module** (FFUDevelopment/Modules/FFU.Apps/FFU.Apps.psm1)
- **Purpose:** Application installation and management for FFU Builder
- **Functions:**
  - `Get-ODTURL`: Retrieves the latest Office Deployment Tool download URL from Microsoft
  - `Get-Office`: Downloads and configures Office/Microsoft 365 Apps for deployment
  - `New-AppsISO`: Creates ISO file from applications folder for VM deployment
  - `Remove-Apps`: Cleans up application downloads, Office installers, and temporary files
  - `Remove-DisabledArtifacts`: Removes downloaded artifacts for disabled features (Office, Defender, MSRT, OneDrive, Edge)
- **Dependencies:** FFU.Core module for logging, process execution, and download tracking
- **Requirements:** Internet access for Office downloads, ADK for ISO creation

**FFU.Updates Module** (FFUDevelopment/Modules/FFU.Updates/FFU.Updates.psm1)
- **Purpose:** Windows Update catalog parsing, MSU package download, and DISM servicing
- **Functions:**
  - `Get-ProductsCab`: Downloads products.cab from Windows Update service for ESD file discovery
  - `Get-WindowsESD`: Downloads Windows ESD files from Microsoft servers
  - `Get-KBLink`: Searches Microsoft Update Catalog and retrieves download links
  - `Get-UpdateFileInfo`: Gathers update file information for architecture-specific packages
  - `Save-KB`: Downloads KB updates from Microsoft Update Catalog with architecture detection
  - `Test-MountedImageDiskSpace`: Validates disk space for MSU extraction (3x package size + 5GB safety)
  - `Add-WindowsPackageWithRetry`: Applies packages with automatic retry logic (2 retries, 30s delays)
  - `Add-WindowsPackageWithUnattend`: Handles MSU packages with unattend.xml extraction
- **Dependencies:** FFU.Core module for logging, BITS transfers, and download tracking
- **Improvements:** Enhanced MSU handling with disk space validation, retry logic, and unattend.xml extraction

**FFU.Messaging Module** (FFUDevelopment/Modules/FFU.Messaging/FFU.Messaging.psm1)
- **Purpose:** Thread-safe messaging system for UI/background job communication (Issue #14)
- **Functions:**
  - Context management: `New-FFUMessagingContext`, `Test-FFUMessagingContext`, `Close-FFUMessagingContext`
  - Message writing: `Write-FFUMessage`, `Write-FFUProgress`, `Write-FFUInfo`, `Write-FFUSuccess`, `Write-FFUWarning`, `Write-FFUError`, `Write-FFUDebug`
  - Message reading: `Read-FFUMessages`, `Peek-FFUMessage`, `Get-FFUMessageCount`
  - Build state: `Set-FFUBuildState`, `Request-FFUCancellation`, `Test-FFUCancellationRequested`
- **Technology:** ConcurrentQueue<T> for lock-free messaging, synchronized hashtable for state
- **Performance:** ~12,000+ messages/second throughput, 50ms UI polling interval (20x faster than file-based)
- **Design:** Dual output (queue for UI + file for persistence), backward compatible with file-based fallback

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

### Creating USB Deployment Media

```powershell
# After FFU build completes
.\USBImagingToolCreator.ps1 -FFUPath "C:\FFUDevelopment\FFU\MyImage.ffu"
```

## Important Implementation Notes

### Type Safety (Issue #324 Fix)

When working with path parameters, **never** pass boolean values or strings like "False". Always use strongly-typed path validation:

```powershell
# BAD - Will cause runtime errors
$path = $false
Expand-Archive -Path $path

# GOOD - Use FFUPaths class validation
$paths = [FFUPaths]::new()
$expandedPath = $paths.ExpandPath($userInput)
if ($expandedPath) {
    Expand-Archive -Path $expandedPath
}
```

### Proxy Support (Issue #327 Fix)

All network operations must respect proxy configuration:

```powershell
# Detect and apply proxy settings
$proxyConfig = [FFUNetworkConfiguration]::DetectProxySettings()

# Use with BITS transfers
Start-BitsTransferWithRetry -Source $url -Destination $dest -ProxyConfig $proxyConfig

# Use with web requests
$request = [System.Net.WebRequest]::Create($url)
$proxyConfig.ApplyToWebRequest($request)
```

### Error Handling Pattern (v1.0.5)

FFU Builder provides three standardized error handling functions in FFU.Core module:

**1. Invoke-WithErrorHandling** - Retry wrapper with cleanup actions:
```powershell
# Wrap operations with automatic retry and logging
$result = Invoke-WithErrorHandling -OperationName "Download Dell Drivers" `
                    -MaxRetries 3 `
                    -RetryDelaySeconds 5 `
                    -CriticalOperation $true `
                    -Operation {
    Start-BitsTransfer -Source $driverUrl -Destination $driverPath
} -CleanupAction {
    # Cleanup logic on final failure
    Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
}
```

**2. Test-ExternalCommandSuccess** - Validate external command exit codes:
```powershell
# Standard command validation
& oscdimg.exe $args
if (-not (Test-ExternalCommandSuccess -CommandName "oscdimg")) {
    throw "Failed to create ISO"
}

# Robocopy special handling (exit codes 0-7 are success)
Robocopy.exe $source $dest /E /R:3
if (-not (Test-ExternalCommandSuccess -CommandName "Robocopy copy files")) {
    throw "Robocopy failed"
}
```

**3. Invoke-WithCleanup** - Guaranteed cleanup in finally block:
```powershell
# Ensure cleanup runs regardless of success or failure
Invoke-WithCleanup -OperationName "Apply drivers" -Operation {
    Mount-WindowsImage -Path $mountPath -ImagePath $wimPath -Index 1
    Add-WindowsDriver -Path $mountPath -Driver $driverPath -Recurse
} -Cleanup {
    Dismount-WindowsImage -Path $mountPath -Save
}
```

**Critical Operations with Error Handling (v1.0.5):**
- Disk partitioning (USB imaging) - try/catch with proper cleanup
- Robocopy operations - exit code validation (0-7 success, 8+ failure)
- Unattend.xml copy - source validation and -ErrorAction Stop
- Optimize-Volume - non-fatal with warning on failure
- New-FFUVM - VM and HGS Guardian cleanup on failure
- DISM mount/dismount - retry with Cleanup-Mountpoints fallback
- Update Catalog requests - 3 retries with exponential backoff

### Constants and Magic Numbers

Never use hardcoded values. Reference `FFUConstants` class:

```powershell
# BAD
Start-Sleep -Seconds 15
$registryPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'

# GOOD
Start-Sleep -Milliseconds ([FFUConstants]::LOG_WAIT_TIMEOUT)
$registryPath = [FFUConstants]::REGISTRY_FILESYSTEM
```

### Driver Provider Pattern

When adding support for new OEM or modifying driver download logic:

```powershell
# Implement DriverProvider abstract class
class NewOEMDriverProvider : DriverProvider {
    [string] GetDriverCatalogUrl() {
        return "https://oem-vendor.com/catalog.xml"
    }

    [PSCustomObject[]] ParseDriverCatalog([string]$Content) {
        # OEM-specific XML/JSON parsing
    }

    [void] ExtractDriverPackage([string]$Package, [string]$Destination) {
        # OEM-specific extraction (exe, cab, zip, etc.)
    }
}

# Register in factory
# See DriverProviderFactory class in FFU.Common\Drivers\
```

### ADK Pre-Flight Validation (New Feature)

FFUBuilder automatically validates Windows ADK installation before creating WinPE media to prevent silent failures.

**Automatic Validation:**
When `-CreateCaptureMedia` or `-CreateDeploymentMedia` is enabled, the system performs comprehensive pre-flight checks:

```powershell
# Automatically triggered when creating WinPE media
.\BuildFFUVM.ps1 -CreateCaptureMedia $true -UpdateADK $true
```

**What is validated:**
- ADK installation (registry and file system)
- Deployment Tools feature
- Windows PE add-on
- Critical executables (oscdimg.exe, copype.cmd, DandISetEnv.bat)
- Architecture-specific boot files (etfsboot.com, Efisys.bin, Efisys_noprompt.bin)
- ADK version currency (warning only)

**Error handling:**
- Clear error messages with specific missing components
- Direct links to Microsoft download pages
- Automatic installation when `-UpdateADK $true` is set
- Detailed logging with severity levels (Info, Success, Warning, Error, Critical)

**Manual validation:**
```powershell
# Explicitly validate ADK prerequisites
$validation = Test-ADKPrerequisites -WindowsArch 'x64' -AutoInstall $false -ThrowOnFailure $false

if (-not $validation.IsValid) {
    Write-Host "ADK validation failed:"
    $validation.Errors | ForEach-Object { Write-Host "  - $_" }
}
```

**Common error resolution:**
If ADK validation fails:
1. Check error message for specific missing components
2. Run with `-UpdateADK $true` for automatic installation
3. Or manually install from https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install
   - Install "Windows ADK" with "Deployment Tools" feature
   - Install "Windows PE add-on"

### Configuration Schema Validation (New Feature - v1.2.5)

FFUBuilder now includes JSON Schema validation for configuration files, providing:
- IDE autocomplete when editing config files
- Detection of typos in property names
- Type validation (string, boolean, integer, object)
- Enum validation for WindowsSKU, WindowsArch, Make, MediaType, etc.
- Range validation for Memory, Disksize, Processors
- Pattern validation for ShareName, Username, IP addresses
- Unknown property detection

**Schema Location:**
- `FFUDevelopment/config/ffubuilder-config.schema.json`

**Using the Schema in Config Files:**
Add the `$schema` reference at the top of your config file for IDE support:
```json
{
    "$schema": "./ffubuilder-config.schema.json",
    "WindowsSKU": "Pro",
    "WindowsRelease": 11,
    ...
}
```

**Programmatic Validation:**
```powershell
# Validate a config file
$result = Test-FFUConfiguration -ConfigPath "C:\FFU\config\my-config.json"
if ($result.IsValid) {
    Write-Host "Configuration is valid"
} else {
    $result.Errors | ForEach-Object { Write-Error $_ }
}

# Validate with ThrowOnError for strict mode
Test-FFUConfiguration -ConfigPath "config.json" -ThrowOnError

# Validate a hashtable directly
$config = @{
    WindowsSKU = "Enterprise"
    Memory = 8GB
    Processors = 4
}
$result = Test-FFUConfiguration -ConfigObject $config

# Get schema path
$schemaPath = Get-FFUConfigurationSchema
```

**Validation Result Object:**
```powershell
@{
    IsValid = $true/$false           # Overall validation status
    Errors = @(...)                   # Array of error messages
    Warnings = @(...)                 # Array of warning messages
    Config = @{...}                   # Parsed configuration object
}
```

**Validated Properties Include:**
- **Enums:** WindowsSKU (22 values), WindowsArch (x86/x64/arm64), Make (Dell/HP/Lenovo/Microsoft), MediaType (consumer/business), LogicalSectorSizeBytes (512/4096), WindowsRelease (10/11/server versions), WindowsLang (38 locales)
- **Ranges:** Memory (2GB-128GB), Disksize (25GB-2TB), Processors (1-64), MaxUSBDrives (0-100)
- **Patterns:** ShareName, Username, FFUPrefix (alphanumeric), VMHostIPAddress (IPv4)
- **Types:** 60+ properties with boolean, integer, string, object type validation

### Pre-flight Validation

Always validate configuration before starting builds:

```powershell
$config = [FFUConfiguration]::LoadAndValidate("config.json")
$validator = [FFUPreflightValidator]::new($config)

if (-not $validator.ValidateAll()) {
    Write-Error "Pre-flight validation failed. Check errors above."
    exit 1
}

# Proceed with build
```

### Logging Best Practices

Use structured logging with context:

```powershell
# Basic logging
Write-FFULog -Level Info -Message "Starting driver download"

# Logging with context
Write-FFULog -Level Warning -Message "Download retry required" -Context @{
    URL = $driverUrl
    Attempt = $retryCount
    Error = $_.Exception.Message
}

# Success logging
Write-FFULog -Level Success -Message "FFU build completed" -Context @{
    FFUPath = $outputPath
    SizeGB = $ffuSizeGB
    Duration = $buildDuration
}
```

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

For detailed documentation on fixed issues, see the individual fix summaries in `docs/fixes/`:

| Issue | Status | Documentation |
|-------|--------|---------------|
| [FFUConstants] Type Not Found | FIXED v1.2.9 | See below |
| FFU.Constants Not Found in ThreadJob | FIXED v1.2.8 | See below |
| Module Loading Failure in Background Jobs | FIXED v1.2.7 | See below |
| DISM Initialization Error 0x80004005 | FIXED v1.2.2 | See below |
| Monitor Tab Shows Stale Log Entries | FIXED v1.2.1 | See below |
| DISM Error 0x80070228 (Checkpoint Updates) | FIXED v1.0.2 | [CHECKPOINT_UPDATE_0x80070228_FIX.md](docs/fixes/CHECKPOINT_UPDATE_0x80070228_FIX.md) |
| WinPE boot.wim Creation Failures | FIXED | [WINPE_BOOTWIM_CREATION_FIX.md](docs/fixes/WINPE_BOOTWIM_CREATION_FIX.md) |
| MSU Package Expansion Failures | FIXED | [MSU_PACKAGE_FIX_SUMMARY.md](docs/fixes/MSU_PACKAGE_FIX_SUMMARY.md) |
| copype WIM Mount Failures | FIXED | [COPYPE_WIM_MOUNT_FIX.md](docs/fixes/COPYPE_WIM_MOUNT_FIX.md) |
| PowerShell Cross-Version Compatibility | FIXED | [POWERSHELL_CROSSVERSION_FIX.md](docs/fixes/POWERSHELL_CROSSVERSION_FIX.md) |
| FFU Optimization Error 1167 | FIXED | [FFU_OPTIMIZATION_ERROR_1167_FIX.md](docs/fixes/FFU_OPTIMIZATION_ERROR_1167_FIX.md) |
| Expand-WindowsImage Error 0x8007048F | FIXED | [EXPAND_WINDOWSIMAGE_FIX.md](docs/fixes/EXPAND_WINDOWSIMAGE_FIX.md) |
| cmd.exe Path Quoting Error | FIXED | [CMD_PATH_QUOTING_FIX.md](docs/fixes/CMD_PATH_QUOTING_FIX.md) |
| WriteLog Empty String Errors | FIXED | [WRITELOG_PATH_VALIDATION_FIX.md](docs/fixes/WRITELOG_PATH_VALIDATION_FIX.md) |
| DISM WIM Mount Error 0x800704DB | FIXED v1.3.5 | See below |
| Module Unapproved Verbs | FIXED v1.0.11 | See below |

### DISM WIM Mount Error 0x800704DB (FIXED v1.3.5)

**Symptoms:** DISM WIM mount operations fail with "The specified service does not exist":
```
DISM.log shows:
- Error [1784] OpenFilterPort: Failed to open filter port. hr = 0x800704db
- Error [1820] FltCommVerifyFilterPresent: Failed to verify filter. hr = 0x800704db
- Error [1968] WIMMountImageHandle: Failed to mount the image. hr = 0x800704db
```

**Root Cause:** ADK DISM.exe relies on WIMMount filter driver which can become corrupted by newer ADK versions (10.1.26100.1+). The WIMMount filter must be registered with Filter Manager at altitude 180700, but ADK updates can corrupt this registration.

**Solution History:**

**v1.3.2 - Remediation Approach:** Added pre-flight validation (`Test-FFUWimMount`) to detect and attempt to fix WIMMount service/driver issues before build. This worked in many cases but not when the filter driver was fundamentally corrupted.

**v1.3.5 - Native DISM Approach (Recommended):** Replaced ADK dism.exe calls with native PowerShell DISM cmdlets in ApplyFFU.ps1:
- `dism.exe /Mount-Image` → `Mount-WindowsImage` cmdlet
- `dism.exe /Unmount-Image` → `Dismount-WindowsImage` cmdlet

The PowerShell cmdlets use the OS DISM infrastructure which is more reliable than ADK DISM because:
1. No dependency on WIMMount filter driver for mount operations
2. Uses native Windows APIs
3. Better integrated with PowerShell error handling
4. Works consistently across Windows versions

**Files Changed (v1.3.5):**
- `WinPEDeployFFUFiles/ApplyFFU.ps1` - Lines 895-930, replaced dism.exe with PowerShell cmdlets
- `Tests/FFU.NativeDISM.Tests.ps1` - 31 comprehensive tests

**Test Results:** 31 new tests, all passing
**Regression Tests:** Baseline 1321 passed, Post-change 1352 passed (+31 from new tests)

**Previous Behavior:** dism.exe fails with "service does not exist" when WIMMount filter is corrupted
**Current Behavior:** Mount-WindowsImage cmdlet uses native OS infrastructure, avoiding filter driver issues

### [FFUConstants] Type Not Found During FFU Capture (FIXED v1.2.9)

**Symptoms:** Build fails during FFU capture phase with error:
```
Unable to find type [FFUConstants]
```

**Root Cause:** In v1.2.8, we removed the `using module` statement from BuildFFUVM.ps1 to fix the ThreadJob path issue. However, line 3542 still had runtime code using `[FFUConstants]::VM_STATE_POLL_INTERVAL`. PowerShell classes defined in modules require `using module` to make the type available - `Import-Module` only makes functions available, not class types. The modules (FFU.Core, FFU.Imaging, etc.) work because they have their own `using module` statements that resolve from their $PSScriptRoot.

**Solution (Implemented in v1.2.9):**
- Replaced `[FFUConstants]::VM_STATE_POLL_INTERVAL` with hardcoded value `5` on line 3542
- Added comment `# VM poll interval - must match [FFUConstants]::VM_STATE_POLL_INTERVAL`
- This follows the same pattern used in v1.2.8 for Memory, Disksize, and Processors defaults

**Files Changed:**
- `BuildFFUVM.ps1` line 3542: `Start-Sleep -Seconds 5  # VM poll interval - must match [FFUConstants]::VM_STATE_POLL_INTERVAL`
- `Tests/Unit/BuildFFUVM.UsingModulePath.Tests.ps1`: Updated to verify no runtime [FFUConstants]:: references
- `Tests/Unit/BuildFFUVM.FFUConstantsType.Tests.ps1`: New test file with 22 tests

**Test Results:**
- New FFUConstantsType tests: 22/22 passing
- Regression tests: 1070 passed (24 new tests added), 32 failed (pre-existing), 23 skipped

**Previous Behavior:** Build fails with "Unable to find type [FFUConstants]" during FFU capture
**Current Behavior:** Build completes successfully, VM polling uses hardcoded value with comment referencing FFUConstants source

### FFU.Constants Not Found in ThreadJob (FIXED v1.2.8)

**Symptoms:** Build fails immediately when launched from BuildFFUVM_UI.ps1 with error:
```
The required module 'FFU.Constants' was not loaded because no valid module file was found in any module directory
```

**Root Cause:**
BuildFFUVM.ps1 line 9 used `using module .\Modules\FFU.Constants\FFU.Constants.psm1` to import constants for the param block default values. The `using` statement resolves relative paths from the **current working directory**, not the script location (`$PSScriptRoot`). When launched in a ThreadJob by BuildFFUVM_UI.ps1, the working directory is typically `C:\Users\<user>\OneDrive\Documents`, not the script's directory. This caused the relative path to fail resolution.

**Solution (Implemented in v1.2.8):**
Belt-and-suspenders approach with two layers of defense:

1. **BuildFFUVM_UI.ps1 fix** (lines 602-614):
   - Added `Set-Location $ScriptRoot` at the beginning of the ThreadJob scriptBlock
   - This ensures the working directory is the script's location before BuildFFUVM.ps1 executes
   - Renamed parameter from `$PSScriptRoot` to `$ScriptRoot` to avoid confusion with automatic variable

2. **BuildFFUVM.ps1 fix** (lines 5-17, param block):
   - **Removed** the `using module .\Modules\FFU.Constants\...` statement entirely
   - Added documentation comment explaining why `using` statements don't work in ThreadJob contexts
   - **Hardcoded** param block default values that previously referenced FFUConstants:
     - `$Memory = 4GB` (was `[FFUConstants]::DEFAULT_VM_MEMORY`)
     - `$Disksize = 50GB` (was `[FFUConstants]::DEFAULT_VHDX_SIZE`)
     - `$Processors = 4` (was `[FFUConstants]::DEFAULT_VM_PROCESSORS`)
   - Each hardcoded value has a comment `# Must match [FFUConstants]::...` for maintainability
   - Runtime FFUConstants references (e.g., `VM_STATE_POLL_INTERVAL`) remain unchanged as they work fine after module import

**Why Both Fixes:**
- UI fix ensures correct working directory for any relative paths
- Script fix eliminates the problematic `using module` pattern entirely
- Hardcoded defaults are more reliable than dynamic resolution in param blocks
- Together they provide defense-in-depth against path resolution issues

**Files Modified:**
- `BuildFFUVM.ps1`: Removed `using module`, hardcoded param defaults, added documentation
- `BuildFFUVM_UI.ps1`: Added `Set-Location $ScriptRoot` in ThreadJob scriptBlock
- `Tests/Unit/BuildFFUVM.ParameterValidation.Tests.ps1`: Updated test expectations
- `Tests/Unit/BuildFFUVM.DismInitialization.Tests.ps1`: Updated line number expectations

**Test Coverage:**
- `Tests/Unit/BuildFFUVM.UsingModulePath.Tests.ps1`: 27 test cases covering:
  - Absence of `using module` statements in BuildFFUVM.ps1
  - Hardcoded param block default values match FFUConstants
  - Runtime FFUConstants references still work after module import
  - UI scriptBlock has Set-Location command
  - Integration test validates end-to-end module loading in ThreadJob context

**Previous Behavior:** Build fails with "module not found" error when launched from UI
**Current Behavior:** Build starts successfully from UI, param defaults are reliable, no dependency on working directory

### Module Loading Failure in Background Jobs (FIXED v1.2.7)

**Symptoms:** Build fails immediately when launched from BuildFFUVM_UI.ps1 with error:
```
The 'Get-CleanupRegistry' command was found in the module 'FFU.Core', but the module could not be loaded
```

**Root Cause:** Early error handler executed before module dependencies were properly configured:
1. FFU.Core module requires FFU.Constants as a dependency (via RequiredModules)
2. The PSModulePath modification that enables FFU.Constants resolution happened late in the script (around line 754)
3. The trap handler at line 771 called Get-CleanupRegistry from FFU.Core
4. If ANY error occurred before PSModulePath was set up (e.g., parameter validation, Hyper-V check), the trap handler fired and triggered module auto-loading
5. PowerShell attempted to load FFU.Core, which then tried to load FFU.Constants
6. Because PSModulePath wasn't configured yet, FFU.Constants couldn't be found, causing the entire module chain to fail

**Solution (Implemented in v1.2.7):**
Defense-in-depth approach with three layers of protection:

1. **Early PSModulePath Configuration** (BuildFFUVM.ps1 lines 626-637):
   - Moved PSModulePath setup to immediately after FFU.Common import
   - Ensures module dependencies are resolvable before any error can occur
   - Happens before parameter validation, Hyper-V checks, and all other operations

2. **Defensive Trap Handler** (BuildFFUVM.ps1 lines 777-793):
   - Checks if Get-CleanupRegistry is available before calling it
   - Uses `Get-Command -ErrorAction SilentlyContinue` to test availability
   - Falls back to basic error logging if function isn't loaded
   - Prevents secondary failures in error handling code

3. **Defensive Exit Handler** (BuildFFUVM.ps1 lines 799-809):
   - Same defensive pattern for PowerShell.Exiting event handler
   - Ensures cleanup can run even if modules fail to load
   - Provides graceful degradation instead of cascading failures

**Code Example:**
```powershell
# OLD (vulnerable to early failures):
trap {
    Get-CleanupRegistry | Invoke-FailureCleanup  # Fails if modules not loaded
    throw $_
}

# NEW (defensive):
trap {
    if (Get-Command Get-CleanupRegistry -ErrorAction SilentlyContinue) {
        Get-CleanupRegistry | Invoke-FailureCleanup
    } else {
        WriteLog "Trap handler invoked but cleanup registry not available"
    }
    throw $_
}
```

**Files Modified:**
- `BuildFFUVM.ps1`: Early PSModulePath setup (lines 626-637), defensive handlers (lines 777-793, 799-809)

**Test Coverage:**
- `Tests/Unit/BuildFFUVM.ModuleLoading.Tests.ps1`: 25 test cases covering:
  - PSModulePath configuration happens immediately after FFU.Common import
  - PSModulePath setup precedes all error-prone operations
  - Trap handler has defensive Get-Command check
  - Exit handler has defensive Get-Command check
  - Early cleanup of DISM mount points before Hyper-V check
  - Module dependency resolution sequence
  - Error handler resilience to module load failures

**Previous Behavior:** Build fails with cryptic module loading error when any early error occurs
**Current Behavior:** Module dependencies always available, error handlers are resilient to module load failures, provides graceful degradation

### Module Best Practices Compliance (FIXED v1.0.11)

**Symptoms:** PSScriptAnalyzer warnings about unapproved verbs when importing FFU.Core module
**Root Cause:** Three functions used non-standard PowerShell verbs:
- `LogVariableValues` (unapproved verb: Log)
- `Mark-DownloadInProgress` (unapproved verb: Mark)
- `Cleanup-CurrentRunDownloads` (unapproved verb: Cleanup)

**Solution (Implemented in v1.0.11):**
- Renamed functions to use approved verbs (Write-, Set-, Clear-)
- Added backward compatibility aliases for existing code
- Added `[OutputType([void])]` attributes to renamed functions
- Enhanced comment-based help with migration notes

**Function Mapping:**
| Old Name (Deprecated Alias) | New Name (Approved Verb) |
|----------------------------|-------------------------|
| `LogVariableValues` | `Write-VariableValues` |
| `Mark-DownloadInProgress` | `Set-DownloadInProgress` |
| `Cleanup-CurrentRunDownloads` | `Clear-CurrentRunDownloads` |

**Backward Compatibility:**
All old function names continue to work as aliases. Existing scripts do not need modification, but new code should use the approved verb names.

**Testing:**
Run `Invoke-Pester -Path 'Tests\Unit\Module.BestPractices.Tests.ps1'` to verify:
- All exported functions use approved verbs
- Deprecated aliases exist and resolve correctly
- OutputType attributes are present
- Module manifests pass validation
| Hardcoded C:\FFUDevelopment Paths | FIXED v1.2.3 | See below |

### Hardcoded Installation Paths (FIXED v1.2.3)

**Symptoms:** FFUBuilder could only be installed in `C:\FFUDevelopment`. Installing in a different location (e.g., `D:\FFU` or `C:\MyProjects\FFU`) caused path resolution failures.

**Root Cause:** The FFU.Constants module had approximately 40 instances of `C:\FFUDevelopment` hardcoded as static string properties:
```powershell
# OLD (hardcoded)
static [string] $DEFAULT_WORKING_DIR = "C:\FFUDevelopment"
static [string] $DEFAULT_VM_DIR = "C:\FFUDevelopment\VM"
```

**Solution (Implemented in v1.2.3):**
Added dynamic path resolution in FFU.Constants v1.1.0:

1. **New GetBasePath() method** - Resolves installation path from module location:
   ```powershell
   # Path resolution: Modules/FFU.Constants/FFU.Constants.psm1 -> Modules -> FFUDevelopment
   $basePath = [FFUConstants]::GetBasePath()  # Returns actual installation path
   ```

2. **New Get*Dir() methods** - Dynamic path construction:
   ```powershell
   [FFUConstants]::GetDefaultWorkingDir()  # Returns <base>
   [FFUConstants]::GetDefaultVMDir()       # Returns <base>\VM
   [FFUConstants]::GetDefaultCaptureDir()  # Returns <base>\FFU
   [FFUConstants]::GetDefaultDriversDir()  # Returns <base>\Drivers
   [FFUConstants]::GetDefaultAppsDir()     # Returns <base>\Apps
   [FFUConstants]::GetDefaultUpdatesDir()  # Returns <base>\Updates
   ```

3. **SetBasePath() and ResetBasePath()** - For testing and manual overrides:
   ```powershell
   [FFUConstants]::SetBasePath("D:\CustomPath")  # Override
   [FFUConstants]::ResetBasePath()               # Re-resolve from module location
   ```

4. **Environment variable overrides** - For deployment flexibility:
   - `FFU_BASE_PATH` - Override base installation path
   - `FFU_WORKING_DIR`, `FFU_VM_DIR`, `FFU_CAPTURE_DIR`, etc. - Override individual paths

5. **Office DownloadFFU.xml** - Changed hardcoded path to placeholder:
   ```xml
   <!-- Old: SourcePath="C:\FFUDevelopment\Apps\Office" -->
   <!-- New: Uses placeholder, dynamically set at runtime by Get-Office -->
   <Add SourcePath="{{OFFICE_PATH}}" ...>
   ```

**Backward Compatibility:**
- Static properties (e.g., `DEFAULT_WORKING_DIR`) are kept but marked as DEPRECATED
- Legacy methods (`GetWorkingDirectory()`, etc.) now call the new dynamic methods
- Existing code using static properties continues to work (returns hardcoded values)
- New code should use `Get*Dir()` methods for proper path resolution

**Files Modified:**
- `Modules/FFU.Constants/FFU.Constants.psm1` - Dynamic path resolution
- `Modules/FFU.Constants/FFU.Constants.psd1` - Version 1.1.0
- `Apps/Office/DownloadFFU.xml` - Placeholder instead of hardcoded path
- `version.json` - Version 1.2.3

**Test Coverage:**
- `Tests/Unit/FFU.Constants.DynamicPaths.Tests.ps1` - 27 test cases covering:
  - GetBasePath() resolution and caching
  - SetBasePath() override functionality
  - ResetBasePath() cache clearing
  - All Get*Dir() method correctness
  - Backward compatibility with legacy methods
  - Path construction quality (separators, subdirectory names)
  - Module integrity verification

**Migration Guide:**
```powershell
# Old (hardcoded, deprecated)
$path = [FFUConstants]::DEFAULT_WORKING_DIR  # Always C:\FFUDevelopment

# New (dynamic, recommended)
$path = [FFUConstants]::GetDefaultWorkingDir()  # Resolves to actual installation
```

**Previous Behavior:** Project only worked when installed at `C:\FFUDevelopment`
**Current Behavior:** Project works when installed in any location

### DISM Initialization Error 0x80004005 (FIXED v1.2.2)

**Symptoms:** Build fails immediately with error: "DismInitialize failed. Error code = 0x80004005" and UI reports "No log file was created (expected at C:\FFUDevelopment\FFUDevelopment.log)"

**Root Cause:** The Hyper-V feature check (`Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All`) internally calls DISM API (`DismInitialize`). This check happened BEFORE logging was initialized, so when DISM failed with stale mount points or concurrent access issues, no diagnostic information was captured.

**Solution (Implemented in v1.2.2):**
1. **Move logging initialization earlier** - `Set-CommonCoreLogPath` now runs BEFORE the Hyper-V check (moved from line ~1315 to line ~1240)
2. **Add DISM cleanup before check** - Runs `dism.exe /Cleanup-Mountpoints` to clear stale DISM state that causes 0x80004005
3. **Add retry logic** - Retries `Get-WindowsOptionalFeature` up to 3 times with 5-second delays for transient failures
4. **Provide actionable error messages** - If all retries fail, logs specific troubleshooting guidance

**Common Causes of 0x80004005:**
- Another DISM operation in progress (Windows Update, another build)
- Stale DISM mount points from previous failed operations
- Antivirus blocking DISM operations
- Insufficient permissions (not running as Administrator)

**Files Modified:**
- `BuildFFUVM.ps1`: Lines 1234-1308 (early logging and DISM retry logic)

**Test Coverage:**
- `Tests/Unit/BuildFFUVM.DismInitialization.Tests.ps1`: 40 test cases covering:
  - Logging initialization order verification
  - DISM cleanup presence before Hyper-V check
  - Retry logic structure (3 retries, 5-second delays)
  - Error message quality and actionable guidance
  - Code flow integrity and regression prevention

**Previous Behavior:** Build fails silently with no log file created
**Current Behavior:** DISM errors are logged, automatic cleanup and retry attempted, actionable guidance provided

### Monitor Tab Shows Stale Log Entries (FIXED v1.2.1)

**Symptoms:** When clicking Build button, the Monitor tab briefly shows log entries from the previous build run before the current build starts.

**Root Cause:** Race condition where the UI's StreamReader opens the old log file before the background job has a chance to delete and recreate it:
1. Previous run's `FFUDevelopment.log` exists with old content
2. User clicks Build -> UI starts background job
3. UI checks: "Does log file exist?" -> YES (old file still exists)
4. UI opens StreamReader at position 0 (beginning of old file)
5. Background job finally starts, deletes old log, creates new log
6. UI's StreamReader reads old content before deletion completes

**Solution (Implemented in v1.2.1):**
- Close any existing StreamReader before starting new build (releases file handle)
- Delete old log file from the UI BEFORE starting the background job
- Clear log data collection to reset Monitor tab display
- Add 100ms delay after deletion to ensure file system operation completes
- Graceful error handling - build continues even if deletion fails (background job will handle it)

**Files Modified:**
- `BuildFFUVM_UI.ps1`: Lines 461-471 (StreamReader cleanup), Lines 610-624 (log file deletion)

**Test Coverage:**
- `Tests/Unit/FFUUI.LogRaceCondition.Tests.ps1`: 23 test cases
- Tests code structure, fix location, error handling, and functional simulation

**Previous Behavior:** Stale log entries visible for 1-2 seconds at build start
**Current Behavior:** Monitor tab shows only current build log entries

### Additional Fix Documentation

See `docs/fixes/` for complete list of fix summaries including:
- KB Path Resolution fixes
- Filter Parameter fixes
- Log Monitoring fixes
- CaptureFFU Network fixes
- Defender Update fixes
- And more...

## Project Structure

```
FFUDevelopment/
├── BuildFFUVM.ps1              # Core orchestrator (298 KB)
├── BuildFFUVM_UI.ps1           # WPF UI launcher (36 KB)
├── BuildFFUVM_UI.xaml          # UI definition (76 KB)
├── Create-PEMedia.ps1          # WinPE media creator
├── USBImagingToolCreator.ps1   # USB tool generator
├── Modules/                    # PowerShell modules
│   └── FFU.VM/                # Hyper-V VM management module
│       └── FFU.VM.psm1        # VM lifecycle functions
├── FFU.Common/                 # Business logic module
│   ├── Classes/                # Type definitions
│   │   ├── FFUConfiguration.ps1
│   │   ├── FFUConstants.ps1
│   │   ├── FFULogger.ps1
│   │   ├── FFUNetworkConfiguration.ps1
│   │   ├── FFUPaths.ps1
│   │   └── FFUPreflightValidator.ps1
│   └── Functions/              # Reusable functions
│       ├── Invoke-FFUOperation.ps1
│       └── Write-FFULog.ps1
├── FFUUI.Core/                 # UI framework
│   └── FFUBuildJobManager.ps1
├── Drivers/
│   └── Providers/              # OEM driver implementations
│       ├── DriverProvider.ps1
│       ├── DellDriverProvider.ps1
│       ├── HPDriverProvider.ps1
│       ├── LenovoDriverProvider.ps1
│       └── MicrosoftDriverProvider.ps1
├── Apps/                       # Application installers
├── Autopilot/                  # Windows Autopilot configs
├── PPKG/                       # Provisioning packages
├── VM/                         # Hyper-V VM configurations
├── Tests/                      # Pester test suites
│   ├── Unit/
│   ├── Integration/
│   └── UI/
└── Logs/                       # Runtime logs and telemetry
```

## Debugging Tips

### Enable Verbose Logging

```powershell
$VerbosePreference = 'Continue'
.\BuildFFUVM.ps1 -Verbose
```

### Monitor Background Job Progress

```powershell
# Get running jobs
Get-Job | Where-Object { $_.Name -like "*FFU*" }

# Receive job output in real-time
Receive-Job -Name "FFUBuild" -Keep
```

### Inspect VM During Build

```powershell
# Connect to running build VM
vmconnect.exe localhost "FFU_Build_VM"

# Check VM state
Get-VM -Name "FFU_Build_VM" | Select-Object Name, State, Uptime
```

### Analyze DISM Errors

DISM logs are located in the mounted image:
```powershell
# After DISM failure, check logs
Get-Content "C:\Windows\Logs\DISM\dism.log" -Tail 100
```

### Test Driver Download in Isolation

```powershell
# Test single OEM driver provider
$provider = [DriverProviderFactory]::CreateProvider('Dell', $proxyConfig)
$catalogUrl = $provider.GetDriverCatalogUrl()
Invoke-WebRequest -Uri $catalogUrl -UseBasicParsing
```

## Common Customizations

### Add New OEM Driver Support

1. Create new provider class inheriting from `DriverProvider`
2. Implement `GetDriverCatalogUrl()`, `ParseDriverCatalog()`, `ExtractDriverPackage()`
3. Register in `DriverProviderFactory.CreateProvider()` switch statement
4. Add integration tests in `Tests/Integration/Drivers/`

### Modify VM Configuration Defaults

Edit `FFUConstants` class:
```powershell
static [int] $DEFAULT_VM_MEMORY_GB = 16      # Increase for faster builds
static [int] $DEFAULT_VM_PROCESSORS = 8      # Use more cores if available
```

### Add Custom WinPE Drivers

Place drivers in `PEDrivers/` folder - they'll be automatically injected into boot media

### Integrate Custom Applications

Add WinGet package IDs to configuration JSON or use `Apps/` folder for MSI/EXE installers

## Performance Optimization

- **Parallel Windows Update Downloads:** KB updates download concurrently using `FFU.Common.ParallelDownload` module
  - Configurable concurrency (default: 5 concurrent downloads)
  - PowerShell 7+ uses `ForEach-Object -Parallel` with thread-safe collections
  - PowerShell 5.1 uses `RunspacePool` for compatibility
  - Automatic retry with exponential backoff (3 retries by default)
  - Multi-method fallback per download: BITS → WebRequest → WebClient → curl.exe
  - Progress callback support for UI integration
  - Download summary with success/failure statistics
- **Driver Downloads:** BITS background jobs with proxy support
- **Incremental Builds:** Reuse existing VM if configuration unchanged (`-ReuseVM`)
- **Local Driver Cache:** Downloaded drivers cached in `Drivers/` to avoid re-downloads
- **VM Checkpoints:** Create checkpoints before risky operations for quick rollback

## Security Considerations

- Scripts require **Administrator privileges** for Hyper-V and DISM operations
- Driver downloads verify **HTTPS certificates** (no self-signed certs)
- **No credentials stored** in configuration files (use Windows Credential Manager)
- Audit logs written to `Logs/` directory for compliance tracking
- **Secure Credential Generation (v1.0.7):**
  - Passwords generated using `RNGCryptoServiceProvider` for cryptographic randomness
  - Passwords created directly as `SecureString` - never exist as complete plain text during generation
  - Plain text only created when absolutely necessary (e.g., writing to WinPE scripts)
  - Memory cleanup functions ensure credentials are disposed properly
  - Temporary `ffu_user` account has automatic 4-hour expiry as a security failsafe

## Module Extraction History

### FFU.Common.ParallelDownload Module (v1.1.0)
**Created:** December 8, 2025
**Location:** `FFUDevelopment\FFU.Common\FFU.Common.ParallelDownload.psm1`
**Purpose:** Concurrent download orchestration with cross-version PowerShell support

**Exported Functions:**
- **Start-ParallelDownloads**: Main orchestrator - downloads items concurrently with configurable concurrency
- **New-DownloadItem**: Factory function to create download item objects
- **New-ParallelDownloadConfig**: Factory function to create download configuration
- **New-KBDownloadItems**: Creates download items from Windows Update objects
- **New-GenericDownloadItem**: Creates a single download item from URL
- **Get-ParallelDownloadSummary**: Generates summary statistics from download results

**Key Features:**
- PowerShell 7+ uses `ForEach-Object -Parallel` with thread-safe `ConcurrentBag`
- PowerShell 5.1 uses `RunspacePool` with synchronized `ArrayList`
- Each download uses `Start-ResilientDownload` for multi-method fallback (BITS → WebRequest → WebClient → curl)
- Configurable retry with exponential backoff
- Progress callback support for UI integration

**Usage:**
```powershell
# Create download items
$items = @(
    New-DownloadItem -Id 'KB5001234' -Source 'https://...' -Destination 'C:\Updates\KB5001234.msu'
    New-DownloadItem -Id 'KB5005678' -Source 'https://...' -Destination 'C:\Updates\KB5005678.msu'
)

# Configure and execute
$config = New-ParallelDownloadConfig -MaxConcurrentDownloads 5 -RetryCount 3
$results = Start-ParallelDownloads -Downloads $items -Config $config

# Get summary
$summary = Get-ParallelDownloadSummary -Results $results
Write-Host "Downloaded $($summary.SuccessCount)/$($summary.TotalCount) files"
```

### FFU.Drivers Module (v1.0.0)
**Extracted:** November 20, 2025
**Location:** `FFUDevelopment\Modules\FFU.Drivers\`
**Purpose:** Centralized OEM driver management functionality

Extracted the following functions from BuildFFUVM.ps1 to improve modularity:
- **Get-MicrosoftDrivers** (line 751): Downloads and extracts Microsoft Surface drivers
- **Get-HPDrivers** (line 963): Downloads and extracts HP drivers using HPIA catalog
- **Get-LenovoDrivers** (line 1191): Downloads and extracts Lenovo drivers using PSREF API
- **Get-DellDrivers** (line 1433): Downloads and extracts Dell drivers from Dell catalog
- **Copy-Drivers** (line 3738): Copies and filters drivers for WinPE boot media

**Dependencies:** Requires FFU.Core module for shared functions (WriteLog, Invoke-Process, etc.)

**Usage:**
```powershell
Import-Module "$FFUDevelopmentPath\Modules\FFU.Drivers\FFU.Drivers.psd1"
Get-DellDrivers -Model "Latitude 7490" -WindowsArch "x64" -WindowsRelease 11
```
