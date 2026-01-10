# Implementation Patterns

This document contains detailed implementation patterns and code examples for FFU Builder development.

> **Quick Reference:** For essential patterns, see [CLAUDE.md](../CLAUDE.md).

---

## Type Safety (Issue #324 Fix)

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

---

## Proxy Support (Issue #327 Fix)

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

---

## Error Handling Pattern (v1.0.5)

FFU Builder provides three standardized error handling functions in FFU.Core module:

### 1. Invoke-WithErrorHandling
Retry wrapper with cleanup actions:

```powershell
$result = Invoke-WithErrorHandling -OperationName "Download Dell Drivers" `
                    -MaxRetries 3 `
                    -RetryDelaySeconds 5 `
                    -CriticalOperation $true `
                    -Operation {
    Start-BitsTransfer -Source $driverUrl -Destination $driverPath
} -CleanupAction {
    Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
}
```

### 2. Test-ExternalCommandSuccess
Validate external command exit codes:

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

### 3. Invoke-WithCleanup
Guaranteed cleanup in finally block:

```powershell
Invoke-WithCleanup -OperationName "Apply drivers" -Operation {
    Mount-WindowsImage -Path $mountPath -ImagePath $wimPath -Index 1
    Add-WindowsDriver -Path $mountPath -Driver $driverPath -Recurse
} -Cleanup {
    Dismount-WindowsImage -Path $mountPath -Save
}
```

### Critical Operations with Error Handling
- Disk partitioning (USB imaging) - try/catch with proper cleanup
- Robocopy operations - exit code validation (0-7 success, 8+ failure)
- Unattend.xml copy - source validation and -ErrorAction Stop
- Optimize-Volume - non-fatal with warning on failure
- New-FFUVM - VM and HGS Guardian cleanup on failure
- DISM mount/dismount - retry with Cleanup-Mountpoints fallback
- Update Catalog requests - 3 retries with exponential backoff

---

## Constants and Magic Numbers

Never use hardcoded values. Reference `FFUConstants` class:

```powershell
# BAD
Start-Sleep -Seconds 15
$registryPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'

# GOOD
Start-Sleep -Milliseconds ([FFUConstants]::LOG_WAIT_TIMEOUT)
$registryPath = [FFUConstants]::REGISTRY_FILESYSTEM
```

---

## Driver Provider Pattern

When adding support for new OEM or modifying driver download logic:

```powershell
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

# Register in DriverProviderFactory class in FFU.Common\Drivers\
```

---

## ADK Pre-Flight Validation

FFUBuilder automatically validates Windows ADK installation before creating WinPE media.

### Automatic Validation
When `-CreateCaptureMedia` or `-CreateDeploymentMedia` is enabled:

```powershell
.\BuildFFUVM.ps1 -CreateCaptureMedia $true -UpdateADK $true
```

### What is validated
- ADK installation (registry and file system)
- Deployment Tools feature
- Windows PE add-on
- Critical executables (oscdimg.exe, copype.cmd, DandISetEnv.bat)
- Architecture-specific boot files (etfsboot.com, Efisys.bin, Efisys_noprompt.bin)
- ADK version currency (warning only)

### Manual validation
```powershell
$validation = Test-ADKPrerequisites -WindowsArch 'x64' -AutoInstall $false -ThrowOnFailure $false

if (-not $validation.IsValid) {
    Write-Host "ADK validation failed:"
    $validation.Errors | ForEach-Object { Write-Host "  - $_" }
}
```

### Common error resolution
1. Check error message for specific missing components
2. Run with `-UpdateADK $true` for automatic installation
3. Or manually install from https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install

---

## Configuration Schema Validation (v1.2.5)

JSON Schema validation for configuration files provides:
- IDE autocomplete
- Typo detection
- Type validation (string, boolean, integer, object)
- Enum validation (WindowsSKU, WindowsArch, Make, MediaType, etc.)
- Range validation (Memory, Disksize, Processors)
- Pattern validation (ShareName, Username, IP addresses)

### Schema Location
`FFUDevelopment/config/ffubuilder-config.schema.json`

### Using in Config Files
```json
{
    "$schema": "./ffubuilder-config.schema.json",
    "WindowsSKU": "Pro",
    "WindowsRelease": 11
}
```

### Programmatic Validation
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
```

### Validation Result Object
```powershell
@{
    IsValid = $true/$false
    Errors = @(...)
    Warnings = @(...)
    Config = @{...}
}
```

### Validated Properties
- **Enums:** WindowsSKU (22 values), WindowsArch (x86/x64/arm64), Make (Dell/HP/Lenovo/Microsoft), MediaType, LogicalSectorSizeBytes, WindowsRelease, WindowsLang (38 locales)
- **Ranges:** Memory (2GB-128GB), Disksize (25GB-2TB), Processors (1-64), MaxUSBDrives (0-100)
- **Patterns:** ShareName, Username, FFUPrefix (alphanumeric), VMHostIPAddress (IPv4)
- **Types:** 60+ properties with type validation

---

## Pre-flight Validation

Always validate configuration before starting builds:

```powershell
$config = [FFUConfiguration]::LoadAndValidate("config.json")
$validator = [FFUPreflightValidator]::new($config)

if (-not $validator.ValidateAll()) {
    Write-Error "Pre-flight validation failed. Check errors above."
    exit 1
}
```

---

## Logging Best Practices

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

---

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

---

## Performance Optimization

- **Parallel Windows Update Downloads:** KB updates download concurrently using `FFU.Common.ParallelDownload` module
  - Configurable concurrency (default: 5 concurrent downloads)
  - PowerShell 7+ uses `ForEach-Object -Parallel` with thread-safe collections
  - PowerShell 5.1 uses `RunspacePool` for compatibility
  - Automatic retry with exponential backoff (3 retries by default)
  - Multi-method fallback: BITS -> WebRequest -> WebClient -> curl.exe
  - Progress callback support for UI integration
- **Driver Downloads:** BITS background jobs with proxy support
- **Incremental Builds:** Reuse existing VM if configuration unchanged (`-ReuseVM`)
- **Local Driver Cache:** Downloaded drivers cached in `Drivers/` to avoid re-downloads
- **VM Checkpoints:** Create checkpoints before risky operations for quick rollback

---

## Security Considerations

- Scripts require **Administrator privileges** for Hyper-V and DISM operations
- Driver downloads verify **HTTPS certificates** (no self-signed certs)
- **No credentials stored** in configuration files (use Windows Credential Manager)
- Audit logs written to `Logs/` directory for compliance tracking
- **Secure Credential Generation (v1.0.7):**
  - Passwords generated using `RNGCryptoServiceProvider`
  - Passwords created directly as `SecureString` - never exist as plain text
  - Plain text only created when absolutely necessary
  - Memory cleanup functions ensure proper disposal
  - Temporary `ffu_user` account has automatic 4-hour expiry

---

## Debugging Tips

### Enable Verbose Logging
```powershell
$VerbosePreference = 'Continue'
.\BuildFFUVM.ps1 -Verbose
```

### Monitor Background Job Progress
```powershell
Get-Job | Where-Object { $_.Name -like "*FFU*" }
Receive-Job -Name "FFUBuild" -Keep
```

### Inspect VM During Build
```powershell
vmconnect.exe localhost "FFU_Build_VM"
Get-VM -Name "FFU_Build_VM" | Select-Object Name, State, Uptime
```

### Analyze DISM Errors
```powershell
Get-Content "C:\Windows\Logs\DISM\dism.log" -Tail 100
```

### Test Driver Download in Isolation
```powershell
$provider = [DriverProviderFactory]::CreateProvider('Dell', $proxyConfig)
$catalogUrl = $provider.GetDriverCatalogUrl()
Invoke-WebRequest -Uri $catalogUrl -UseBasicParsing
```
