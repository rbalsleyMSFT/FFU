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
- Update CLAUDE.md before every git commit
- Increment version number based on change type (see Versioning Policy)
- Update `CHANGELOG_FORK.md` with new fixes/enhancements

## Versioning Policy

**Current Version:** 1.0.5
**Version Location:** `BuildFFUVM_UI.ps1` line 35 (`$script:FFUBuilderVersion`)

This project follows [Semantic Versioning](https://semver.org/):

| Change Type | Version | When to Use | Examples |
|-------------|---------|-------------|----------|
| **MAJOR** | X.0.0 | Breaking changes, incompatible API/parameter changes | Removing parameters, changing config format, dropping PS 5.1 support |
| **MINOR** | 0.X.0 | New features, backward compatible additions | New OEM driver support, new UI tabs, new export formats |
| **BUILD** | 0.0.X | Bug fixes, patches, backward compatible fixes | Error handling fixes, DISM workarounds, logging improvements |

**Version Increment Checklist:**
1. Determine change type (major/minor/build)
2. Update `$script:FFUBuilderVersion` in `BuildFFUVM_UI.ps1`
3. Document the change in CLAUDE.md under "Version History"
4. Commit with version in message (e.g., "v1.0.1: Fix checkpoint update error")

## Version History

| Version | Date | Type | Description |
|---------|------|------|-------------|
| 1.0.5 | 2025-12-04 | BUILD | Secure credential management - cryptographic password generation, SecureString handling |
| 1.0.4 | 2025-12-03 | BUILD | Add comprehensive parameter validation to BuildFFUVM.ps1 (15 parameters) |
| 1.0.3 | 2025-12-03 | BUILD | Fix FFU.VM module export - Add missing functions to Export-ModuleMember |
| 1.0.2 | 2025-12-03 | BUILD | Enhanced fix for 0x80070228 - Direct CAB application bypasses UUP download requirement |
| 1.0.1 | 2025-12-03 | BUILD | Fix DISM error 0x80070228 for Windows 11 24H2/25H2 checkpoint cumulative updates |
| 1.0.0 | 2025-12-03 | MAJOR | Initial modularized release with 8 modules, UI version display, credential security |

### Component Structure

```
BuildFFUVM_UI.ps1 (WPF UI Host)
├── FFUUI.Core (UI Framework)
├── FFU.Common (Business Logic Module - provides WriteLog function)
└── BuildFFUVM.ps1 (Core Build Orchestrator - 2,404 lines after modularization)
    └── Modules/ (Extracted functions now in 8 specialized modules)
        ├── FFU.Core (Core functionality - 36 functions for configuration, session tracking, error handling, cleanup, credential management)
        ├── FFU.Apps (Application management - 5 functions for Office, Apps ISO, cleanup)
        ├── FFU.Drivers (OEM driver management - 5 functions for Dell, HP, Lenovo, Microsoft)
        ├── FFU.VM (Hyper-V VM operations - 3 functions for VM lifecycle)
        ├── FFU.Media (WinPE media creation - 4 functions for PE media and architecture)
        ├── FFU.ADK (Windows ADK management - 8 functions for validation and installation)
        ├── FFU.Updates (Windows Update handling - 8 functions for KB downloads and MSU processing)
        └── FFU.Imaging (DISM and FFU operations - 15 functions for partitioning, imaging, FFU creation)
```

### Modularization Status (Completed)
- **Original file:** BuildFFUVM.ps1 with 7,790 lines
- **After extraction:** BuildFFUVM.ps1 reduced to 2,404 lines (69% reduction)
- **Functions extracted:** 64 total functions moved to 8 modules
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

**Testing:**
Run `Test-UIIntegration.ps1` to verify UI compatibility:
- Module directory structure validation
- Import tests in clean PowerShell sessions
- Background job simulation (mimics UI launch mechanism)
- Function export verification (64 unique functions across 8 modules)
- Module dependency chain validation
- Function name conflict detection

### Module Architecture

**FFU.Core Module** (FFUDevelopment/Modules/FFU.Core/FFU.Core.psm1)
- **Purpose:** Core utility module providing common configuration management, logging, session tracking, error handling, cleanup registration, and secure credential management
- **Version:** 1.0.7
- **Functions (36 total):**
  - **Configuration & Utilities:** `Get-Parameters`, `LogVariableValues`, `Get-ChildProcesses`, `Test-Url`, `Get-PrivateProfileString`, `Get-PrivateProfileSection`, `Get-ShortenedWindowsSKU`, `New-FFUFileName`, `Export-ConfigFile`
  - **Session Management:** `New-RunSession`, `Get-CurrentRunManifest`, `Save-RunManifest`, `Mark-DownloadInProgress`, `Clear-DownloadInProgress`, `Remove-InProgressItems`, `Cleanup-CurrentRunDownloads`, `Restore-RunJsonBackups`
  - **Error Handling (v1.0.5):** `Invoke-WithErrorHandling`, `Test-ExternalCommandSuccess`, `Invoke-WithCleanup`
  - **Cleanup Registration (v1.0.6):** `Register-CleanupAction`, `Unregister-CleanupAction`, `Invoke-FailureCleanup`, `Clear-CleanupRegistry`, `Get-CleanupRegistry`
  - **Specialized Cleanup Helpers:** `Register-VMCleanup`, `Register-VHDXCleanup`, `Register-DISMMountCleanup`, `Register-ISOCleanup`, `Register-TempFileCleanup`, `Register-NetworkShareCleanup`, `Register-UserAccountCleanup`
  - **Secure Credential Management (v1.0.7):** `New-SecureRandomPassword`, `ConvertFrom-SecureStringToPlainText`, `Clear-PlainTextPassword`, `Remove-SecureStringFromMemory`
- **Dependencies:** None (base module)
- **Security Features:** Cryptographically secure password generation using RNGCryptoServiceProvider, SecureString-first design, proper memory cleanup

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

### Key Design Patterns

- **Event-Driven UI:** WPF with DispatcherTimer for non-blocking background job polling
- **Background Job Pattern:** Long-running builds in separate PowerShell runspaces
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
| DISM Error 0x80070228 (Checkpoint Updates) | FIXED v1.0.2 | [CHECKPOINT_UPDATE_0x80070228_FIX.md](docs/fixes/CHECKPOINT_UPDATE_0x80070228_FIX.md) |
| WinPE boot.wim Creation Failures | FIXED | [WINPE_BOOTWIM_CREATION_FIX.md](docs/fixes/WINPE_BOOTWIM_CREATION_FIX.md) |
| MSU Package Expansion Failures | FIXED | [MSU_PACKAGE_FIX_SUMMARY.md](docs/fixes/MSU_PACKAGE_FIX_SUMMARY.md) |
| copype WIM Mount Failures | FIXED | [COPYPE_WIM_MOUNT_FIX.md](docs/fixes/COPYPE_WIM_MOUNT_FIX.md) |
| PowerShell Cross-Version Compatibility | FIXED | [POWERSHELL_CROSSVERSION_FIX.md](docs/fixes/POWERSHELL_CROSSVERSION_FIX.md) |
| FFU Optimization Error 1167 | FIXED | [FFU_OPTIMIZATION_ERROR_1167_FIX.md](docs/fixes/FFU_OPTIMIZATION_ERROR_1167_FIX.md) |
| Expand-WindowsImage Error 0x8007048F | FIXED | [EXPAND_WINDOWSIMAGE_FIX.md](docs/fixes/EXPAND_WINDOWSIMAGE_FIX.md) |
| cmd.exe Path Quoting Error | FIXED | [CMD_PATH_QUOTING_FIX.md](docs/fixes/CMD_PATH_QUOTING_FIX.md) |
| WriteLog Empty String Errors | FIXED | [WRITELOG_PATH_VALIDATION_FIX.md](docs/fixes/WRITELOG_PATH_VALIDATION_FIX.md) |

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

- **Parallel Downloads:** Driver downloads use BITS background jobs (max 5 concurrent)
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
