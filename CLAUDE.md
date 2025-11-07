# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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

### Component Structure

```
BuildFFUVM_UI.ps1 (WPF UI Host)
├── FFUUI.Core (UI Framework)
├── FFU.Common (Business Logic Module)
└── BuildFFUVM.ps1 (Core Build Orchestrator)
    ├── Hyper-V VM Management
    ├── DISM Image Manipulation
    ├── Driver Download/Injection (Dell, HP, Lenovo, Microsoft)
    ├── Windows Update Integration
    └── USB Media Creator
```

### Key Design Patterns

- **Event-Driven UI:** WPF with DispatcherTimer for non-blocking background job polling
- **Background Job Pattern:** Long-running builds in separate PowerShell runspaces
- **Provider Pattern:** OEM-specific driver download/extraction implementations
- **Configuration as Code:** JSON-based configuration with CLI override support

### Critical Dependencies

- **Windows 10/11** with Hyper-V enabled
- **Windows ADK** with Deployment Tools and WinPE add-on
- **PowerShell 5.1+** or PowerShell 7+
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

### Error Handling Pattern

All operations should use the standardized retry wrapper:

```powershell
# Wrap operations with automatic retry and logging
Invoke-FFUOperation -OperationName "Download Dell Drivers" `
                    -MaxRetries 3 `
                    -CriticalOperation `
                    -Operation {
    Start-BitsTransfer -Source $driverUrl -Destination $driverPath
} -OnFailure {
    # Cleanup logic on final failure
    Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
}
```

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

### Issue #327: Corporate Proxy Failures

**Symptoms:** Driver downloads fail with network errors behind Netskope/zScaler
**Workaround:** Manually configure proxy in UI settings or set environment variables:
```powershell
$env:HTTP_PROXY = "http://proxy.corp.com:8080"
$env:HTTPS_PROXY = "http://proxy.corp.com:8080"
```

### Issue #301: Unattend.xml Extraction from MSU

**Symptoms:** DISM fails to apply unattend.xml from update packages
**Workaround:** Use `Get-UnattendFromMSU` function for robust extraction with validation

### WinPE boot.wim Creation Failures (FIXED)

**Symptoms:** Build fails with "Boot.wim not found at expected path" when creating WinPE capture media
**Root Cause:** Missing Windows ADK or Windows PE add-on installation
**Solution (Implemented):**
- Automatic ADK pre-flight validation now detects missing components before build starts
- Clear error messages with installation instructions
- Run with `-UpdateADK $true` for automatic installation
- Validation checks:
  - ADK installation presence
  - Deployment Tools feature
  - Windows PE add-on
  - Critical files (copype.cmd, oscdimg.exe, boot files)
- Enhanced error handling in `copype` command execution with proper exit code checking

**Previous Behavior:** Silent failure during WinPE media creation
**Current Behavior:** Early detection with actionable error messages

### Issue #298: OS Partition Size Limitations

**Symptoms:** OS partition doesn't expand when injecting large driver sets
**Workaround:** Call `Expand-FFUPartition` before driver injection to resize VHDX dynamically

### Dell Chipset Driver Hang

**Known Issue:** Dell chipset driver installers may hang when run with `-Wait $true`
**Solution:** Always use `-Wait $false` for Dell driver extraction:
```powershell
Start-Process -FilePath $dellDriver -ArgumentList "/s /e=$destination" -Wait:$false
```

### Lenovo PSREF API Authentication

**Known Issue:** Hardcoded JWT token will expire
**Solution:** Implement proper OAuth flow in `LenovoDriverProvider.RefreshAuthToken()`

## Project Structure

```
FFUDevelopment/
├── BuildFFUVM.ps1              # Core orchestrator (298 KB)
├── BuildFFUVM_UI.ps1           # WPF UI launcher (36 KB)
├── BuildFFUVM_UI.xaml          # UI definition (76 KB)
├── Create-PEMedia.ps1          # WinPE media creator
├── USBImagingToolCreator.ps1   # USB tool generator
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
