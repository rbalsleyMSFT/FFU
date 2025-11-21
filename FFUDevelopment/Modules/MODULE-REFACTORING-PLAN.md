# FFU Builder Module Refactoring Plan

## Overview

Refactoring BuildFFUVM.ps1 (7,000+ lines, 64 functions) into specialized PowerShell modules for improved maintainability, testability, and team collaboration.

## Module Structure

```
FFUDevelopment/
├── Modules/
│   ├── FFU.Core/
│   │   └── FFU.Core.psm1          (12 functions - Common utilities)
│   ├── FFU.ADK/
│   │   └── FFU.ADK.psm1           (8 functions - Windows ADK management)
│   ├── FFU.Drivers/
│   │   └── FFU.Drivers.psm1       (5 functions - OEM driver handling)
│   ├── FFU.Updates/
│   │   └── FFU.Updates.psm1       (8 functions - Windows Update/MSU)
│   ├── FFU.VM/
│   │   └── FFU.VM.psm1            (3 functions - Hyper-V management)
│   ├── FFU.Media/
│   │   └── FFU.Media.psm1         (4 functions - WinPE media creation)
│   ├── FFU.Imaging/
│   │   └── FFU.Imaging.psm1       (15 functions - DISM/FFU imaging)
│   └── FFU.Apps/
│       └── FFU.Apps.psm1          (4 functions - Application management)
```

## Function Distribution

### FFU.Core Module (12 functions)
**Purpose:** Common utilities, configuration management, logging

- `Get-Parameters` - Parameter parsing and validation
- `LogVariableValues` - Variable logging utility
- `Get-ChildProcesses` - Process management helper
- `Test-Url` - URL validation
- `Get-PrivateProfileString` - INI file reading
- `Get-PrivateProfileSection` - INI section parsing
- `Get-ShortenedWindowsSKU` - SKU name utilities
- `New-FFUFileName` - FFU naming convention
- `Export-ConfigFile` - Configuration export
- `New-RunSession` - Session management
- `Get-CurrentRunManifest` - Manifest retrieval
- `Save-RunManifest` - Manifest persistence

**Dependencies:** None (base module)

---

### FFU.ADK Module (8 functions)
**Purpose:** Windows ADK installation, validation, and management

- `Write-ADKValidationLog` - ADK-specific logging
- `Test-ADKPrerequisites` - Pre-flight ADK validation
- `Get-ADKURL` - ADK download URL resolution
- `Install-ADK` - ADK installation automation
- `Get-InstalledProgramRegKey` - Registry query for installed programs
- `Uninstall-ADK` - ADK removal
- `Confirm-ADKVersionIsLatest` - Version currency check
- `Get-ADK` - Main ADK acquisition function

**Dependencies:** FFU.Core

---

### FFU.Drivers Module (5 functions)
**Purpose:** OEM-specific driver download and injection

- `Get-MicrosoftDrivers` - Microsoft Surface drivers
- `Get-HPDrivers` - HP driver catalog parsing
- `Get-LenovoDrivers` - Lenovo PSREF API integration
- `Get-DellDrivers` - Dell driver catalog handling
- `Copy-Drivers` - Driver injection into image

**Dependencies:** FFU.Core

---

### FFU.Updates Module (8 functions)
**Purpose:** Windows Update, MSU packages, and servicing

- `Get-ProductsCab` - Windows Update catalog parsing
- `Get-WindowsESD` - ESD download from Microsoft
- `Get-KBLink` - KB article URL resolution
- `Get-UpdateFileInfo` - MSU metadata extraction
- `Save-KB` - KB package download
- `Test-MountedImageDiskSpace` - Disk space validation for MSU
- `Add-WindowsPackageWithRetry` - Retry wrapper for DISM package operations
- `Add-WindowsPackageWithUnattend` - MSU with unattend.xml extraction

**Dependencies:** FFU.Core, FFU.Imaging

---

### FFU.VM Module (3 functions)
**Purpose:** Hyper-V virtual machine lifecycle management

- `New-FFUVM` - VM creation and configuration
- `Remove-FFUVM` - VM cleanup
- `Get-FFUEnvironment` - Environment detection and validation

**Dependencies:** FFU.Core

---

### FFU.Media Module (4 functions)
**Purpose:** WinPE media creation and copype operations

- `Invoke-DISMPreFlightCleanup` - DISM mount point cleanup
- `Invoke-CopyPEWithRetry` - copype execution with retry
- `New-PEMedia` - WinPE media orchestration
- `Get-PEArchitecture` - Architecture detection for WinPE

**Dependencies:** FFU.Core, FFU.ADK

---

### FFU.Imaging Module (15 functions)
**Purpose:** DISM operations, VHDX management, FFU creation

- `Initialize-DISMService` - DISM service readiness check
- `Get-WimFromISO` - WIM extraction from ISO
- `Get-Index` - WIM index selection
- `New-ScratchVhdx` - VHDX creation
- `New-SystemPartition` - EFI system partition
- `New-MSRPartition` - Microsoft Reserved partition
- `New-OSPartition` - OS partition creation
- `New-RecoveryPartition` - Recovery partition
- `Add-BootFiles` - Boot file configuration
- `Enable-WindowsFeaturesByName` - Feature enablement
- `Dismount-ScratchVhdx` - Safe VHDX dismount
- `Optimize-FFUCaptureDrive` - Pre-capture optimization
- `New-FFU` - FFU image creation
- `Remove-FFU` - FFU cleanup
- `Start-RequiredServicesForDISM` - Service dependency check

**Dependencies:** FFU.Core

---

### FFU.Apps Module (4 functions)
**Purpose:** Application installation and management

- `Get-ODTURL` - Office Deployment Tool URL
- `Get-Office` - Office 365 acquisition
- `New-AppsISO` - Application ISO creation
- `Remove-Apps` - Provisioned app removal

**Dependencies:** FFU.Core

---

## Download Management Functions

**Note:** These functions are currently in BuildFFUVM.ps1 but may belong in FFU.Core:

- `Mark-DownloadInProgress`
- `Clear-DownloadInProgress`
- `Remove-InProgressItems`
- `Cleanup-CurrentRunDownloads`
- `Restore-RunJsonBackups`

**Decision:** Move to FFU.Core as download state management utilities

---

## Implementation Strategy

### Phase 1: Core Module (Foundation)
1. Create FFU.Core module with common utilities
2. Extract logging, configuration, and helper functions
3. Test FFU.Core independently

### Phase 2: Domain Modules (Parallel)
1. Create FFU.ADK module (ADK validation work)
2. Create FFU.Media module (WinPE/copype work)
3. Create FFU.Imaging module (DISM operations)
4. Create FFU.Updates module (MSU handling)
5. Create FFU.Drivers module (OEM drivers)
6. Create FFU.VM module (Hyper-V)
7. Create FFU.Apps module (Application management)

### Phase 3: Integration
1. Update BuildFFUVM.ps1 to import modules
2. Remove extracted functions from main script
3. Maintain backward compatibility

### Phase 4: Testing
1. Run existing test suites (Test-ADKValidation.ps1, Test-DISMCleanupAndCopype.ps1)
2. Create new module-specific tests
3. Integration testing with UI (BuildFFUVM_UI.ps1)

---

## Module Manifest Template

Each module will have a manifest (.psd1) with:

```powershell
@{
    ModuleVersion = '1.0.0'
    GUID = '<unique-guid>'
    Author = 'FFU Builder Team'
    CompanyName = 'Community'
    Copyright = '(c) 2025 FFU Builder. MIT License.'
    Description = '<module-specific description>'
    PowerShellVersion = '5.1'
    RequiredModules = @('FFU.Core')
    FunctionsToExport = @('<exported-functions>')
    AliasesToExport = @()
    VariablesToExport = @()
}
```

---

## Benefits

1. **Maintainability:** Smaller, focused modules easier to understand and modify
2. **Testing:** Unit test individual modules independently
3. **Performance:** Selective module loading reduces memory footprint
4. **Collaboration:** Multiple developers can work on different modules
5. **Reusability:** Modules can be used in other scripts/projects
6. **Documentation:** Each module has focused documentation
7. **Error Isolation:** Issues contained to specific modules
8. **Versioning:** Independent module versioning for compatibility

---

## Backward Compatibility

To maintain compatibility during transition:

```powershell
# BuildFFUVM.ps1 will support both monolithic and modular modes
param(
    [switch]$UseLegacyMonolith  # Fallback to old behavior
)

if (-not $UseLegacyMonolith) {
    # Import modular architecture
    Import-Module "$PSScriptRoot\Modules\FFU.Core"
    Import-Module "$PSScriptRoot\Modules\FFU.ADK"
    # ... other modules
} else {
    # Use inline functions (existing code)
    Write-Warning "Using legacy monolithic architecture"
}
```

---

## Success Criteria

- ✅ All 64 functions successfully extracted into appropriate modules
- ✅ BuildFFUVM.ps1 reduced from 7,000+ lines to ~1,500 lines (orchestration only)
- ✅ All existing tests pass (Test-ADKValidation.ps1, Test-DISMCleanupAndCopype.ps1)
- ✅ UI (BuildFFUVM_UI.ps1) functions correctly with modular architecture
- ✅ Performance unchanged or improved (module caching)
- ✅ Documentation updated (CLAUDE.md, module README files)

---

## Timeline Estimate

- **Phase 1 (FFU.Core):** 2-3 hours
- **Phase 2 (Domain Modules):** 5-7 hours
- **Phase 3 (Integration):** 2-3 hours
- **Phase 4 (Testing):** 2-3 hours

**Total:** 11-16 hours of development work

---

## Next Steps

1. Create module directory structure
2. Generate module manifests
3. Extract FFU.Core functions first (foundation)
4. Extract domain-specific modules
5. Update main script
6. Test thoroughly
7. Update documentation
