# Module Reference

This document provides detailed reference information for all FFU Builder modules.

> **Quick Reference:** For a high-level overview, see the Module Summary in [CLAUDE.md](../CLAUDE.md).

---

## FFU.Core Module

**Path:** `FFUDevelopment/Modules/FFU.Core/FFU.Core.psm1`
**Purpose:** Core utility module providing common configuration management, logging, session tracking, error handling, cleanup registration, and secure credential management
**Version:** 1.0.11
**Dependencies:** FFU.Constants module (v1.0.9+)

### Functions (39 total)

**Configuration & Utilities:**
- `Get-Parameters` - Retrieve and process parameters
- `Write-VariableValues` - Log variable values for debugging
- `Get-ChildProcesses` - Enumerate child processes
- `Test-Url` - Validate URL accessibility
- `Get-PrivateProfileString` - Read INI file values
- `Get-PrivateProfileSection` - Read INI file sections
- `Get-ShortenedWindowsSKU` - Convert SKU to short form
- `New-FFUFileName` - Generate standardized FFU filenames
- `Export-ConfigFile` - Export configuration to file

**Session Management:**
- `New-RunSession` - Create new build session
- `Get-CurrentRunManifest` - Get current run manifest
- `Save-RunManifest` - Save run manifest
- `Set-DownloadInProgress` - Mark download in progress
- `Clear-DownloadInProgress` - Clear download progress marker
- `Remove-InProgressItems` - Remove incomplete downloads
- `Clear-CurrentRunDownloads` - Clear current run downloads
- `Restore-RunJsonBackups` - Restore JSON backup files

**Error Handling (v1.0.5):**
- `Invoke-WithErrorHandling` - Retry wrapper with cleanup
- `Test-ExternalCommandSuccess` - Validate exit codes
- `Invoke-WithCleanup` - Guaranteed cleanup in finally block

**Cleanup Registration (v1.0.6):**
- `Register-CleanupAction` - Register cleanup action
- `Unregister-CleanupAction` - Remove cleanup action
- `Invoke-FailureCleanup` - Execute all registered cleanups
- `Clear-CleanupRegistry` - Clear cleanup registry
- `Get-CleanupRegistry` - Get registered cleanups

**Specialized Cleanup Helpers:**
- `Register-VMCleanup` - VM cleanup registration
- `Register-VHDXCleanup` - VHDX cleanup registration
- `Register-DISMMountCleanup` - DISM mount cleanup
- `Register-ISOCleanup` - ISO cleanup registration
- `Register-TempFileCleanup` - Temp file cleanup
- `Register-NetworkShareCleanup` - Network share cleanup
- `Register-UserAccountCleanup` - User account cleanup

**Secure Credential Management (v1.0.7):**
- `New-SecureRandomPassword` - Cryptographic password generation
- `ConvertFrom-SecureStringToPlainText` - SecureString conversion
- `Clear-PlainTextPassword` - Memory cleanup for passwords
- `Remove-SecureStringFromMemory` - SecureString disposal

**Configuration Validation (v1.0.10):**
- `Test-FFUConfiguration` - Validate configuration file
- `Get-FFUConfigurationSchema` - Get JSON schema path

### Deprecated Aliases (v1.0.11)
- `LogVariableValues` -> `Write-VariableValues`
- `Mark-DownloadInProgress` -> `Set-DownloadInProgress`
- `Cleanup-CurrentRunDownloads` -> `Clear-CurrentRunDownloads`

### Security Features
- Cryptographically secure password generation using `RNGCryptoServiceProvider`
- SecureString-first design - passwords never exist as complete plain text
- Proper memory cleanup functions

---

## FFU.VM Module

**Path:** `FFUDevelopment/Modules/FFU.VM/FFU.VM.psm1`
**Purpose:** Hyper-V virtual machine lifecycle management
**Dependencies:** FFU.Core
**Requirements:** Administrator privileges, Hyper-V feature enabled

### Functions
- `New-FFUVM` - Creates and configures Generation 2 VMs with TPM, memory, processors, and boot devices
- `Remove-FFUVM` - Cleans up VMs, HGS guardians, certificates, mounted images, and VHDX files
- `Get-FFUEnvironment` - Comprehensive environment cleanup for dirty state recovery

---

## FFU.Hypervisor Module

**Path:** `FFUDevelopment/Modules/FFU.Hypervisor/FFU.Hypervisor.psm1`
**Purpose:** Hypervisor abstraction layer supporting multiple VM platforms
**Version:** 1.1.0
**Documentation:** [VMWARE_WORKSTATION_GUIDE.md](VMWARE_WORKSTATION_GUIDE.md)
**Test Coverage:** 101 Pester tests

### Classes
- `IHypervisorProvider` - Base interface for hypervisor providers
- `HyperVProvider` - Microsoft Hyper-V implementation
- `VMwareProvider` - VMware Workstation Pro implementation
- `VMConfiguration` - VM configuration settings
- `VMInfo` - VM state information
- `VMState` - Enum for VM power states

### Public Functions
- `Get-HypervisorProvider` - Factory function to get provider by type (HyperV, VMware, Auto)
- `Test-HypervisorAvailable` - Check if hypervisor is available
- `Get-AvailableHypervisors` - List all supported hypervisors and their availability
- `New-HypervisorVM`, `Start-HypervisorVM`, `Stop-HypervisorVM`, `Remove-HypervisorVM` - VM lifecycle
- `New-HypervisorVirtualDisk`, `Mount-HypervisorVirtualDisk`, `Dismount-HypervisorVirtualDisk` - Disk operations

### Private Functions (VMware)
- `Start-VMrestService`, `Stop-VMrestService`, `Test-VMrestEndpoint` - vmrest.exe management
- `Invoke-VMwareRestMethod` - REST API wrapper
- `New-VMwareVMX`, `Update-VMwareVMX`, `Get-VMwareVMXSettings` - VMX file management
- `New-VHDWithDiskpart`, `Mount-VHDWithDiskpart`, `Dismount-VHDWithDiskpart` - VHD ops without Hyper-V

---

## FFU.Apps Module

**Path:** `FFUDevelopment/Modules/FFU.Apps/FFU.Apps.psm1`
**Purpose:** Application installation and management for FFU Builder
**Dependencies:** FFU.Core
**Requirements:** Internet access for Office downloads, ADK for ISO creation

### Functions
- `Get-ODTURL` - Retrieves the latest Office Deployment Tool download URL from Microsoft
- `Get-Office` - Downloads and configures Office/Microsoft 365 Apps for deployment
- `New-AppsISO` - Creates ISO file from applications folder for VM deployment
- `Remove-Apps` - Cleans up application downloads, Office installers, and temporary files
- `Remove-DisabledArtifacts` - Removes downloaded artifacts for disabled features

---

## FFU.Updates Module

**Path:** `FFUDevelopment/Modules/FFU.Updates/FFU.Updates.psm1`
**Purpose:** Windows Update catalog parsing, MSU package download, and DISM servicing
**Dependencies:** FFU.Core

### Functions
- `Get-ProductsCab` - Downloads products.cab from Windows Update service for ESD file discovery
- `Get-WindowsESD` - Downloads Windows ESD files from Microsoft servers
- `Get-KBLink` - Searches Microsoft Update Catalog and retrieves download links
- `Get-UpdateFileInfo` - Gathers update file information for architecture-specific packages
- `Save-KB` - Downloads KB updates from Microsoft Update Catalog with architecture detection
- `Test-MountedImageDiskSpace` - Validates disk space for MSU extraction (3x package size + 5GB safety)
- `Add-WindowsPackageWithRetry` - Applies packages with automatic retry logic (2 retries, 30s delays)
- `Add-WindowsPackageWithUnattend` - Handles MSU packages with unattend.xml extraction

---

## FFU.Messaging Module

**Path:** `FFUDevelopment/Modules/FFU.Messaging/FFU.Messaging.psm1`
**Purpose:** Thread-safe messaging system for UI/background job communication
**Technology:** ConcurrentQueue<T> for lock-free messaging, synchronized hashtable for state
**Performance:** ~12,000+ messages/second throughput, 50ms UI polling interval

### Functions

**Context Management:**
- `New-FFUMessagingContext` - Create new messaging context
- `Test-FFUMessagingContext` - Test if context exists
- `Close-FFUMessagingContext` - Close and cleanup context

**Message Writing:**
- `Write-FFUMessage` - Write generic message
- `Write-FFUProgress` - Write progress message
- `Write-FFUInfo` - Write info message
- `Write-FFUSuccess` - Write success message
- `Write-FFUWarning` - Write warning message
- `Write-FFUError` - Write error message
- `Write-FFUDebug` - Write debug message

**Message Reading:**
- `Read-FFUMessages` - Read messages from queue
- `Peek-FFUMessage` - Peek at next message
- `Get-FFUMessageCount` - Get message count

**Build State:**
- `Set-FFUBuildState` - Set build state
- `Request-FFUCancellation` - Request build cancellation
- `Test-FFUCancellationRequested` - Check if cancellation requested

---

## FFU.ADK Module

**Path:** `FFUDevelopment/Modules/FFU.ADK/FFU.ADK.psm1`
**Purpose:** Windows ADK management and validation
**Dependencies:** FFU.Core

### Functions (8 total)
- ADK installation validation
- Deployment Tools feature detection
- Windows PE add-on verification
- Critical executable validation
- Architecture-specific boot file checks
- ADK version currency warnings
- Auto-installation support

---

## FFU.Media Module

**Path:** `FFUDevelopment/Modules/FFU.Media/FFU.Media.psm1`
**Purpose:** WinPE media creation
**Dependencies:** FFU.Core, FFU.ADK

### Functions (4 total)
- WinPE media creation
- Architecture detection
- Native WinPE creation (v1.3.7)

---

## FFU.Imaging Module

**Path:** `FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psm1`
**Purpose:** DISM and FFU operations
**Dependencies:** FFU.Core

### Functions (15 total)
- Disk partitioning
- Image mounting/dismounting
- FFU creation and application
- WIM operations

---

## FFU.Drivers Module

**Path:** `FFUDevelopment/Modules/FFU.Drivers/FFU.Drivers.psm1`
**Purpose:** OEM driver management
**Dependencies:** FFU.Core

### Functions (5 total)
- Dell driver download
- HP driver download
- Lenovo driver download
- Microsoft Surface driver download

---

## FFU.Preflight Module

**Path:** `FFUDevelopment/Modules/FFU.Preflight/FFU.Preflight.psm1`
**Purpose:** Pre-flight validation
**Dependencies:** FFU.Core

### Functions (12 total)
- Tiered environment checks
- Remediation suggestions
- WIMMount validation

---

## Module Dependency Hierarchy

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

### RequiredModules Format Standard
```powershell
# All modules use this standardized hashtable format
RequiredModules = @(
    @{ModuleName = 'FFU.Core'; ModuleVersion = '1.0.0'}
)
```

### Automatic Dependency Loading
PowerShell automatically loads required modules when importing a dependent module:
- Example: `Import-Module FFU.Media` automatically loads FFU.Core, FFU.ADK, and FFU.Constants
- Dependency chain: FFU.Media -> FFU.ADK -> FFU.Core -> FFU.Constants
