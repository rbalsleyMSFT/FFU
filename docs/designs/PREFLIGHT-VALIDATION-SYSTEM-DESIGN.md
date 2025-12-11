# Pre-Flight Validation System Design

**Version:** 1.1.0
**Date:** 2025-12-10
**Author:** FFU Builder Team
**Status:** Design Specification

---

## 1. Executive Summary

This document specifies a comprehensive pre-flight validation system to replace the current fragmented validation approach in FFU Builder. The new system consolidates all environment checks into a single, modular validation framework that runs at script startup, providing clear pass/fail status with actionable remediation guidance.

### Key Design Principles

1. **Fail Fast** - Detect all problems before any build operations begin
2. **No Unnecessary Checks** - Remove redundant validations (e.g., TrustedInstaller running state)
3. **Actionable Output** - Every failure includes specific remediation steps
4. **Feature-Aware** - Only validate requirements for enabled features
5. **Recoverable** - Auto-remediation where safe and appropriate
6. **PowerShell 7+ Required** - Leverage modern PowerShell features and performance

### PowerShell 7 Requirement Rationale

FFU Builder now **requires PowerShell 7.0 or higher**. This decision provides:

| Benefit | Description |
|---------|-------------|
| **Performance** | ForEach-Object -Parallel for concurrent operations (driver downloads, file copies) |
| **Ternary Operator** | Cleaner conditional expressions: `$value = $condition ? 'yes' : 'no'` |
| **Null-Coalescing** | Simplified null handling: `$result = $value ?? 'default'` |
| **Pipeline Chain Operators** | `&&` and `||` for command chaining |
| **Error Handling** | Improved ErrorAction behavior and $ErrorActionPreference consistency |
| **JSON Handling** | Better ConvertTo-Json/ConvertFrom-Json with -AsHashtable |
| **SSH Support** | Native SSH remoting (future remote build scenarios) |
| **Cross-Platform** | Foundation for potential Linux/macOS WinPE creation hosts |
| **Long-Term Support** | PowerShell 5.1 is in maintenance mode; 7.x receives active development |
| **No TelemetryAPI Issues** | Eliminates the "Could not load type TelemetryAPI" errors in local user management |

**Migration Impact:**
- All `#Requires -Version 5.1` statements will be updated to `#Requires -Version 7.0`
- Cross-version compatibility workarounds (e.g., DirectoryServices for local users) can be simplified
- ThreadJob module is built-in (no separate import needed)

---

## 2. Current State Analysis

### 2.1 Existing Pre-Flight Checks (Fragmented)

| Location | Check | Trigger | Issue |
|----------|-------|---------|-------|
| BuildFFUVM.ps1:1276-1336 | Hyper-V feature | Always | Well-implemented with retry |
| BuildFFUVM.ps1:2003-2005 | ADK prerequisites | Only if CreateMedia=true | Not triggered for FFU optimization |
| FFU.Media.psm1:140-168 | TrustedInstaller state | Every copype | **REDUNDANT** - manual service |
| FFU.Updates.psm1:901-952 | TrustedInstaller start | Before KB apply | **PROBLEMATIC** - may fail |
| FFU.Core.psm1:1631+ | Configuration validation | Manual only | **UNDERUTILIZED** |

### 2.2 Redundant Checks to Remove

1. **TrustedInstaller Running State Check** (FFU.Media.psm1:140-168)
   - TrustedInstaller is a demand-start service (Manual trigger)
   - Windows starts it automatically when needed for servicing operations
   - Checking if it's running provides no value; it won't be running when idle
   - Checking if it's disabled is the only useful validation

2. **TrustedInstaller Start Attempt** (FFU.Updates.psm1:924-942)
   - Starting a manual-trigger service externally can fail
   - Windows manages this service automatically
   - Should only verify service is not disabled

### 2.3 Missing Checks Identified

| Check | Impact | Priority |
|-------|--------|----------|
| Total disk space before build | Build fails mid-process | Critical |
| Network connectivity | Downloads fail | High |
| Antivirus exclusions (optional) | Performance/reliability warning | Medium |
| Configuration file validation | Late failures with cryptic errors | High |

---

## 3. Proposed Architecture

### 3.1 Module Structure

```
FFUDevelopment/
└── Modules/
    └── FFU.Preflight/
        ├── FFU.Preflight.psd1          # Module manifest (PowerShellVersion = '7.0')
        ├── FFU.Preflight.psm1          # Main module with orchestration
        ├── Private/
        │   ├── Test-Administrator.ps1   # Admin privilege check
        │   ├── Test-PowerShellVersion.ps1 # PowerShell 7+ validation
        │   ├── Test-HyperV.ps1          # Hyper-V feature validation
        │   ├── Test-ADK.ps1             # ADK installation validation
        │   ├── Test-DiskSpace.ps1       # Disk space validation
        │   ├── Test-Network.ps1         # Network connectivity
        │   ├── Test-Configuration.ps1   # Config file validation
        │   └── Test-DISMEnvironment.ps1 # DISM state cleanup
        └── Public/
            ├── Invoke-FFUPreflight.ps1  # Main entry point
            └── Get-FFURequirements.ps1  # Calculate requirements for features
```

**Module Manifest Requirements:**
```powershell
# FFU.Preflight.psd1
@{
    ModuleVersion = '1.0.0'
    PowerShellVersion = '7.0'           # Enforce PS7+ at module load
    RequiredModules = @('Hyper-V', 'Storage')
    # ...
}
```

### 3.2 Validation Categories

```
┌─────────────────────────────────────────────────────────────────┐
│                    FFU Pre-Flight Validation                     │
├─────────────────────────────────────────────────────────────────┤
│  TIER 1: CRITICAL (Always Run, Blocking)                        │
│  ├── Administrator Privileges                                    │
│  ├── PowerShell Version (7.0+ REQUIRED)                         │
│  └── Hyper-V Feature (unless -SkipVMCreate)                     │
├─────────────────────────────────────────────────────────────────┤
│  TIER 2: FEATURE-DEPENDENT (Conditional, Blocking)              │
│  ├── ADK Installation (if CreateMedia OR Optimize)              │
│  │   ├── Deployment Tools                                        │
│  │   ├── WinPE Add-on (if CreateMedia)                          │
│  │   └── Critical executables                                   │
│  ├── Disk Space (always, calculate based on features)           │
│  │   ├── Base: VHDX size + 10GB scratch                         │
│  │   ├── +WinPE media: 15GB                                      │
│  │   ├── +Apps ISO: 10GB                                         │
│  │   └── +FFU output: VHDX size                                 │
│  └── Network Connectivity (if downloads required)               │
├─────────────────────────────────────────────────────────────────┤
│  TIER 3: RECOMMENDED (Warnings, Non-Blocking)                   │
│  ├── Antivirus Exclusions (FFUDevelopment folder)               │
│  ├── ADK Version Currency                                        │
│  └── Free Memory (recommend 8GB+ available)                     │
├─────────────────────────────────────────────────────────────────┤
│  TIER 4: CLEANUP (Pre-Remediation, Non-Blocking)                │
│  ├── DISM Stale Mount Points                                     │
│  ├── DISM Temp Directories                                       │
│  └── Orphaned VHD Files                                          │
└─────────────────────────────────────────────────────────────────┘
```

---

## 4. Detailed Specifications

### 4.1 Core Function: Invoke-FFUPreflight

```powershell
function Invoke-FFUPreflight {
    <#
    .SYNOPSIS
    Comprehensive environment validation for FFU Builder operations.

    .DESCRIPTION
    Performs all necessary pre-flight checks based on enabled features,
    providing clear pass/fail status with actionable remediation guidance.

    .PARAMETER Features
    Hashtable of enabled features to determine which validations to run:
    - CreateVM: Hyper-V required
    - CreateCaptureMedia: ADK + WinPE required
    - CreateDeploymentMedia: ADK + WinPE required
    - OptimizeFFU: ADK required
    - InstallApps: Network + Apps ISO space required
    - UpdateLatestCU: Network + KB space required
    - DownloadDrivers: Network required

    .PARAMETER FFUDevelopmentPath
    Working directory for space calculations

    .PARAMETER VHDXSizeGB
    Target VHDX size for space calculations

    .PARAMETER SkipCleanup
    Skip Tier 4 cleanup operations

    .PARAMETER WarningsAsErrors
    Treat Tier 3 warnings as blocking errors

    .OUTPUTS
    FFUPreflightResult object with validation status
    #>
}
```

### 4.2 Result Object Structure

```powershell
[PSCustomObject]@{
    # Overall Status
    IsValid              = [bool]          # True if all Tier 1-2 checks pass
    HasWarnings          = [bool]          # True if any Tier 3 warnings
    ValidationTimestamp  = [datetime]
    ValidationDurationMs = [int]

    # Tier Results
    Tier1Results = @{
        Administrator    = [FFUCheckResult]
        PowerShellVersion = [FFUCheckResult]
        HyperV           = [FFUCheckResult]
    }

    Tier2Results = @{
        ADKInstallation  = [FFUCheckResult]
        DiskSpace        = [FFUCheckResult]
        Network          = [FFUCheckResult]
        Configuration    = [FFUCheckResult]
    }

    Tier3Results = @{
        AntivirusExclusions = [FFUCheckResult]
        ADKVersion          = [FFUCheckResult]
        AvailableMemory     = [FFUCheckResult]
    }

    Tier4Results = @{
        DISMMountPoints     = [FFUCheckResult]
        DISMTempDirectories = [FFUCheckResult]
        OrphanedVHDs        = [FFUCheckResult]
    }

    # Aggregated Data
    Errors              = [string[]]       # All blocking errors
    Warnings            = [string[]]       # All non-blocking warnings
    RemediationSteps    = [string[]]       # Ordered steps to fix issues
    CleanupPerformed    = [string[]]       # Actions taken in Tier 4

    # Resource Calculations
    RequiredDiskSpaceGB = [int]
    AvailableDiskSpaceGB = [int]
    RequiredFeatures    = [string[]]
}

# Individual Check Result
[PSCustomObject]@{
    CheckName       = [string]
    Status          = [ValidateSet('Passed', 'Failed', 'Warning', 'Skipped')]
    Message         = [string]
    Details         = [hashtable]          # Check-specific data
    Remediation     = [string]             # How to fix if failed
    DurationMs      = [int]
}
```

### 4.3 Validation Specifications

#### 4.3.1 Administrator Privileges (Tier 1)

```powershell
function Test-FFUAdministrator {
    # Check: Current process running with elevated privileges
    # Method: WindowsPrincipal.IsInRole(Administrator)
    # Pass: Running as Administrator
    # Fail: Not elevated
    # Remediation: "Run PowerShell as Administrator (Right-click > Run as administrator)"
}
```

#### 4.3.2 PowerShell Version (Tier 1)

```powershell
function Test-FFUPowerShellVersion {
    <#
    .SYNOPSIS
    Validates PowerShell 7.0+ is being used.

    .DESCRIPTION
    FFU Builder requires PowerShell 7.0 or higher for:
    - ForEach-Object -Parallel (concurrent operations)
    - Improved error handling
    - Built-in ThreadJob support
    - No TelemetryAPI compatibility issues
    - Modern language features (ternary, null-coalescing)
    #>

    $minVersion = [Version]'7.0.0'
    $currentVersion = $PSVersionTable.PSVersion

    # Check: $PSVersionTable.PSVersion >= 7.0
    # Pass: Version 7.0 or higher
    # Fail: Version below 7.0 (including all of PowerShell 5.1)
    # Remediation: "Install PowerShell 7+ from https://aka.ms/powershell"
    #              "winget install Microsoft.PowerShell"

    if ($currentVersion -lt $minVersion) {
        return [FFUCheckResult]@{
            Status = 'Failed'
            Message = "PowerShell $currentVersion detected. FFU Builder requires PowerShell 7.0 or higher."
            Remediation = @"
Install PowerShell 7+ using one of these methods:

1. Winget (recommended):
   winget install Microsoft.PowerShell

2. Direct download:
   https://aka.ms/powershell

3. Microsoft Store:
   Search for "PowerShell" in Microsoft Store

After installation, run FFU Builder from PowerShell 7:
   pwsh.exe -File BuildFFUVM.ps1
"@
        }
    }

    return [FFUCheckResult]@{
        Status = 'Passed'
        Message = "PowerShell $currentVersion detected"
        Details = @{
            Version = $currentVersion.ToString()
            Edition = $PSVersionTable.PSEdition
        }
    }
}
```

#### 4.3.3 Hyper-V Feature (Tier 1)

```powershell
function Test-FFUHyperV {
    # Check: Hyper-V feature installed and enabled
    # Method:
    #   - Server: Get-WindowsFeature -Name Hyper-V
    #   - Client: Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All
    # Pass: Feature installed and enabled
    # Fail: Feature not installed or disabled
    # Retry: 3 attempts with 5-second delays (DISM can have transient failures)
    # Pre-cleanup: DISM /Cleanup-Mountpoints before check
    # Remediation (Client): "Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -NoRestart"
    # Remediation (Server): "Install-WindowsFeature -Name Hyper-V -IncludeManagementTools"
}
```

#### 4.3.4 ADK Installation (Tier 2)

```powershell
function Test-FFUADK {
    param(
        [bool]$RequireWinPE,      # True if CreateMedia enabled
        [string]$WindowsArch      # x64 or arm64
    )

    # Checks (in order):
    # 1. Registry: HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots\KitsRoot10
    # 2. Directory exists at KitsRoot10 path
    # 3. Deployment Tools feature installed (registry check)
    # 4. WinPE Add-on installed (if RequireWinPE, registry check)
    # 5. Critical executables exist:
    #    - copype.cmd
    #    - oscdimg.exe
    #    - DandISetEnv.bat
    # 6. Architecture-specific boot files (if RequireWinPE):
    #    - etfsboot.com
    #    - Efisys.bin
    #    - Efisys_noprompt.bin

    # Pass: All required checks pass
    # Fail: Any required check fails
    # Warning: ADK version is outdated
    # Remediation: Links to Microsoft ADK download pages
}
```

#### 4.3.5 Disk Space (Tier 2)

```powershell
function Test-FFUDiskSpace {
    param(
        [string]$FFUDevelopmentPath,
        [hashtable]$Features,
        [int]$VHDXSizeGB
    )

    # Calculate required space based on enabled features:
    $requiredGB = 0

    # Base requirements
    $requiredGB += $VHDXSizeGB          # VHDX file
    $requiredGB += 10                    # Scratch space

    # Feature-dependent
    if ($Features.CreateCaptureMedia -or $Features.CreateDeploymentMedia) {
        $requiredGB += 15                # WinPE media
    }
    if ($Features.InstallApps) {
        $requiredGB += 10                # Apps ISO
    }
    if ($Features.CaptureFFU) {
        $requiredGB += $VHDXSizeGB       # FFU output (similar to VHDX)
    }
    if ($Features.UpdateLatestCU) {
        $requiredGB += 5                 # KB downloads
    }
    if ($Features.DownloadDrivers) {
        $requiredGB += 5                 # Driver packages
    }

    # Check available space
    $drive = Get-PSDrive -Name ($FFUDevelopmentPath.Substring(0,1))
    $availableGB = [Math]::Round($drive.Free / 1GB, 2)

    # Pass: Available >= Required + 10% safety margin
    # Fail: Available < Required
    # Details: Breakdown of space requirements by feature
    # Remediation: "Free up {X}GB on drive {D}: or move FFUDevelopment folder"
}
```

#### 4.3.6 Network Connectivity (Tier 2)

```powershell
function Test-FFUNetwork {
    param(
        [hashtable]$Features
    )

    # Only check if network-dependent features enabled
    $needsNetwork = $Features.DownloadDrivers -or
                    $Features.UpdateLatestCU -or
                    $Features.InstallDefender -or
                    $Features.GetOneDrive

    if (-not $needsNetwork) {
        return [Skipped]
    }

    # Check 1: Basic connectivity (DNS resolution)
    $dnsTest = Resolve-DnsName -Name "www.microsoft.com" -ErrorAction SilentlyContinue

    # Check 2: HTTPS connectivity (required endpoints)
    $endpoints = @(
        "https://catalog.update.microsoft.com"    # Windows Update Catalog
        "https://go.microsoft.com"                # Microsoft redirects
    )

    # Pass: DNS resolves AND at least one endpoint reachable
    # Warning: DNS works but endpoints slow (>5s response)
    # Fail: No connectivity
    # Remediation: "Check network connection and proxy settings"
}
```

#### 4.3.7 Configuration Validation (Tier 2)

```powershell
function Test-FFUConfiguration {
    param(
        [string]$ConfigFilePath
    )

    if (-not $ConfigFilePath) {
        return [Skipped]  # No config file specified
    }

    # Validate:
    # 1. File exists and is readable
    # 2. Valid JSON syntax
    # 3. Schema validation (known properties, correct types)
    # 4. Logical validation (paths exist, values in range)

    # Pass: Valid configuration
    # Fail: Invalid JSON or schema violations
    # Warning: Unknown properties (may be ignored)
    # Details: List of validation errors with line numbers
    # Remediation: "Fix configuration errors: {specific issues}"
}
```

#### 4.3.8 Antivirus Exclusions (Tier 3 - Warning Only)

```powershell
function Test-FFUAntivirusExclusions {
    param(
        [string]$FFUDevelopmentPath
    )

    # Check Windows Defender exclusions (if Defender is active)
    try {
        $mpStatus = Get-MpComputerStatus -ErrorAction SilentlyContinue
        if ($mpStatus -and $mpStatus.RealTimeProtectionEnabled) {
            $exclusions = Get-MpPreference | Select-Object -ExpandProperty ExclusionPath

            $hasPathExclusion = $exclusions -contains $FFUDevelopmentPath

            # Also recommend process exclusions
            $processExclusions = Get-MpPreference | Select-Object -ExpandProperty ExclusionProcess
            $hasDismExclusion = $processExclusions -contains 'dism.exe'
        }
    } catch {
        # Non-Defender AV or no access - skip
        return [Skipped]
    }

    # Pass: Exclusions configured
    # Warning: Exclusions not configured
    # Remediation:
    #   "Add-MpPreference -ExclusionPath '$FFUDevelopmentPath'"
    #   "Add-MpPreference -ExclusionProcess 'dism.exe'"
}
```

#### 4.3.9 DISM Environment Cleanup (Tier 4)

```powershell
function Invoke-FFUDISMCleanup {
    # Actions (non-blocking, best-effort):

    # 1. Clean stale mount points
    & dism.exe /Cleanup-Mountpoints 2>&1 | Out-Null

    # 2. Dismount any remaining mounted images
    $mountedImages = Get-WindowsImage -Mounted -ErrorAction SilentlyContinue
    foreach ($mount in $mountedImages) {
        Dismount-WindowsImage -Path $mount.Path -Discard -ErrorAction SilentlyContinue
    }

    # 3. Clean DISM temp directories
    $tempPaths = @(
        "$env:TEMP\DISM*",
        "$env:SystemRoot\Temp\DISM*",
        "$env:LOCALAPPDATA\Temp\DISM*"
    )
    foreach ($path in $tempPaths) {
        Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 4. Clean orphaned _ffumount*.vhd files
    Get-ChildItem "$env:TEMP\_ffumount*.vhd" -ErrorAction SilentlyContinue |
        ForEach-Object {
            try {
                Dismount-DiskImage -ImagePath $_.FullName -ErrorAction SilentlyContinue
                Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
            } catch { }
        }

    # Return: List of cleanup actions performed
}
```

---

## 5. Checks NOT Included (Intentionally Removed)

### 5.1 TrustedInstaller Service Running State

**Reason for Removal:**
- TrustedInstaller is a **demand-start (Manual)** service
- Windows automatically starts it when servicing operations begin
- The service is NOT running when idle - this is expected behavior
- Checking if it's running when idle will always show "Stopped"
- Attempting to start it externally may fail or be redundant

**What IS Checked:**
- Service exists (sanity check)
- Service is NOT disabled (only valid concern)

### 5.2 Specific Service Running States

**Removed Checks:**
- BITS service running state (starts on demand)
- Windows Update service running state (starts on demand)
- CBS service running state (starts on demand)

**Reasoning:**
- All these services are demand-start
- Windows manages them automatically
- Only checking for "Disabled" state is meaningful

### 5.3 Redundant Registry Checks

**Removed:**
- Duplicate ADK path validation (consolidated into single check)
- Multiple registry key existence checks for same component

---

## 6. Integration Points

### 6.1 BuildFFUVM.ps1 Integration

```powershell
# Early in script, after parameter processing
$preflightFeatures = @{
    CreateVM              = -not $SkipVMCreate
    CreateCaptureMedia    = $CreateCaptureMedia
    CreateDeploymentMedia = $CreateDeploymentMedia
    OptimizeFFU           = $Optimize
    InstallApps           = $InstallApps
    UpdateLatestCU        = $UpdateLatestCU
    DownloadDrivers       = $true  # Always might need drivers
}

$preflightResult = Invoke-FFUPreflight `
    -Features $preflightFeatures `
    -FFUDevelopmentPath $FFUDevelopmentPath `
    -VHDXSizeGB ([Math]::Round($Disksize / 1GB)) `
    -ConfigFile $ConfigFile

if (-not $preflightResult.IsValid) {
    Write-Host "`n=== PRE-FLIGHT VALIDATION FAILED ===" -ForegroundColor Red
    foreach ($error in $preflightResult.Errors) {
        Write-Host "  ERROR: $error" -ForegroundColor Red
    }
    Write-Host "`nRemediation Steps:" -ForegroundColor Yellow
    foreach ($step in $preflightResult.RemediationSteps) {
        Write-Host "  - $step" -ForegroundColor Yellow
    }
    throw "Pre-flight validation failed. Please resolve the above issues and try again."
}

if ($preflightResult.HasWarnings) {
    Write-Host "`n=== PRE-FLIGHT WARNINGS ===" -ForegroundColor Yellow
    foreach ($warning in $preflightResult.Warnings) {
        Write-Host "  WARNING: $warning" -ForegroundColor Yellow
    }
}
```

### 6.2 BuildFFUVM_UI.ps1 Integration

```powershell
# In the Start-Build handler, before launching ThreadJob
$preflightResult = Invoke-FFUPreflight -Features $enabledFeatures ...

if (-not $preflightResult.IsValid) {
    # Show validation failures in UI
    $errorMessage = "Pre-flight validation failed:`n`n" +
                    ($preflightResult.Errors -join "`n") +
                    "`n`nRemediation:`n" +
                    ($preflightResult.RemediationSteps -join "`n")

    [System.Windows.MessageBox]::Show(
        $errorMessage,
        "Validation Failed",
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error
    )
    return
}
```

---

## 7. Migration Path

### Phase 0: PowerShell 7 Requirement Enforcement
Update all scripts and modules to require PowerShell 7.0+:

**Files to Update (#Requires -Version 7.0):**
```
FFUDevelopment/
├── BuildFFUVM.ps1                           # Add: #Requires -Version 7.0
├── BuildFFUVM_UI.ps1                        # Add: #Requires -Version 7.0
├── Create-PEMedia.ps1                       # Add: #Requires -Version 7.0
├── USBImagingToolCreator.ps1                # Add: #Requires -Version 7.0
├── Modules/
│   ├── FFU.Core/FFU.Core.psm1               # Update: 5.1 → 7.0
│   ├── FFU.ADK/FFU.ADK.psm1                 # Update: 5.1 → 7.0
│   ├── FFU.Apps/FFU.Apps.psm1               # Update: 5.1 → 7.0
│   ├── FFU.Drivers/FFU.Drivers.psm1         # Update: 5.1 → 7.0
│   ├── FFU.Imaging/FFU.Imaging.psm1         # Update: 5.1 → 7.0
│   ├── FFU.Media/FFU.Media.psm1             # Update: 5.1 → 7.0
│   ├── FFU.Messaging/FFU.Messaging.psm1     # Update: 5.1 → 7.0
│   ├── FFU.Updates/FFU.Updates.psm1         # Update: 5.1 → 7.0
│   ├── FFU.VM/FFU.VM.psm1                   # Update: 5.1 → 7.0
│   └── FFU.Preflight/FFU.Preflight.psm1     # New: 7.0
├── FFU.Common/
│   ├── FFU.Common.Core.psm1                 # Update: 5.1 → 7.0
│   ├── FFU.Common.Logging.psm1              # Update: 5.1 → 7.0
│   └── FFU.Common.ParallelDownload.psm1     # Update: 5.1 → 7.0
└── FFUUI.Core/*.psm1                        # Update: 5.1 → 7.0
```

**Module Manifests to Update (PowerShellVersion = '7.0'):**
```
FFUDevelopment/
├── Modules/
│   ├── FFU.Core/FFU.Core.psd1
│   ├── FFU.ADK/FFU.ADK.psd1
│   ├── FFU.Apps/FFU.Apps.psd1
│   ├── FFU.Drivers/FFU.Drivers.psd1
│   ├── FFU.Imaging/FFU.Imaging.psd1
│   ├── FFU.Media/FFU.Media.psd1
│   ├── FFU.Messaging/FFU.Messaging.psd1
│   ├── FFU.Updates/FFU.Updates.psd1
│   └── FFU.VM/FFU.VM.psd1
├── FFU.Common/FFU.Common.psd1
└── FFUUI.Core/FFUUI.Core.psd1
```

**Simplifications Enabled by PowerShell 7:**
1. Remove DirectoryServices workarounds for local user management (TelemetryAPI fix no longer needed)
2. Use built-in ThreadJob (no Import-Module ThreadJob needed)
3. Use ForEach-Object -Parallel for concurrent driver downloads
4. Use ternary operator for cleaner conditionals
5. Use null-coalescing for default values

### Phase 1: Create FFU.Preflight Module
- Implement all Tier 1-4 checks
- Unit tests for each check
- Integration tests for orchestration
- PowerShell 7 features in implementation

### Phase 2: Integrate into BuildFFUVM.ps1
- Add call to Invoke-FFUPreflight after parameter processing
- Remove redundant inline checks (Hyper-V check moves to module)
- Update error handling to use preflight results

### Phase 3: Remove Redundant Checks
- Remove TrustedInstaller running state check from FFU.Media.psm1
- Remove TrustedInstaller start attempt from FFU.Updates.psm1
- Consolidate ADK validation into single preflight call

### Phase 4: UI Integration
- Add preflight validation before build start
- Display validation results in UI
- Add "Re-validate" button for user to manually recheck

---

## 8. Testing Strategy

### 8.1 Unit Tests

```powershell
Describe 'FFU.Preflight' {
    Context 'Test-FFUAdministrator' {
        It 'Should detect non-admin execution' { }
        It 'Should pass for admin execution' { }
    }

    Context 'Test-FFUHyperV' {
        It 'Should detect missing Hyper-V' { }
        It 'Should detect disabled Hyper-V' { }
        It 'Should pass for enabled Hyper-V' { }
        It 'Should retry on DISM transient failures' { }
    }

    Context 'Test-FFUDiskSpace' {
        It 'Should calculate correct space for base build' { }
        It 'Should add space for WinPE media when enabled' { }
        It 'Should fail when insufficient space' { }
        It 'Should include safety margin' { }
    }

    # ... etc for each check
}
```

### 8.2 Integration Tests

```powershell
Describe 'Invoke-FFUPreflight Integration' {
    It 'Should run all Tier 1 checks always' { }
    It 'Should skip ADK check when no media creation' { }
    It 'Should perform cleanup in Tier 4' { }
    It 'Should aggregate errors correctly' { }
    It 'Should provide remediation for each failure' { }
}
```

---

## 9. Success Criteria

1. **Single Entry Point:** All environment validation through `Invoke-FFUPreflight`
2. **Feature-Aware:** Only validates requirements for enabled features
3. **No Unnecessary Checks:** TrustedInstaller running state NOT checked
4. **Clear Output:** Every failure has specific remediation steps
5. **Fast Execution:** Complete validation in <10 seconds
6. **Backward Compatible:** Existing scripts continue to work
7. **Test Coverage:** >90% code coverage on preflight module

---

## 10. Appendix: Current vs Proposed Check Mapping

| Current Check | Location | Proposed Location | Change |
|---------------|----------|-------------------|--------|
| Admin privileges | #Requires directive | FFU.Preflight (explicit) | Enhanced with message |
| PowerShell version | #Requires -Version 5.1 | FFU.Preflight (7.0+ required) | **UPGRADED to 7.0** |
| Hyper-V feature | BuildFFUVM.ps1:1276-1336 | FFU.Preflight | Moved, unchanged logic |
| ADK prerequisites | FFU.ADK.psm1 | FFU.Preflight (calls existing) | Consolidated |
| TrustedInstaller running | FFU.Media.psm1:140-168 | **REMOVED** | Unnecessary |
| TrustedInstaller start | FFU.Updates.psm1:924 | **REMOVED** | Unnecessary |
| TrustedInstaller disabled | FFU.Media.psm1:151 | FFU.Preflight | Kept, moved |
| Disk space (per-operation) | Multiple locations | FFU.Preflight (aggregate) | Consolidated |
| DISM cleanup | FFU.Media.psm1:64-91 | FFU.Preflight Tier 4 | Moved |
| Config validation | FFU.Core.psm1 | FFU.Preflight (calls existing) | Auto-triggered |
| Network connectivity | (none) | FFU.Preflight | **NEW** |
| AV exclusions | (none) | FFU.Preflight | **NEW** |

### PowerShell Version Requirement Changes

| Component | Current | Proposed | Notes |
|-----------|---------|----------|-------|
| BuildFFUVM.ps1 | (none explicit) | 7.0 | Main orchestrator |
| BuildFFUVM_UI.ps1 | (none explicit) | 7.0 | WPF UI host |
| FFU.Core.psm1 | 5.1 | 7.0 | Core module |
| FFU.ADK.psm1 | 5.1 | 7.0 | ADK validation |
| FFU.Apps.psm1 | 5.1 | 7.0 | App management |
| FFU.Drivers.psm1 | 5.1 | 7.0 | Driver downloads |
| FFU.Imaging.psm1 | 5.1 | 7.0 | DISM operations |
| FFU.Media.psm1 | 5.1 | 7.0 | WinPE creation |
| FFU.Messaging.psm1 | 5.1 | 7.0 | Thread-safe messaging |
| FFU.Updates.psm1 | 5.1 | 7.0 | Windows Update |
| FFU.VM.psm1 | 5.1 | 7.0 | Hyper-V management |
| FFU.Common.*.psm1 | 5.1 | 7.0 | Shared utilities |
| FFUUI.Core.*.psm1 | (none) | 7.0 | UI framework |
| FFU.Preflight.psm1 | N/A | 7.0 | **NEW** module |

---

*End of Design Specification*
