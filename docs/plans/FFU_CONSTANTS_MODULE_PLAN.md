# FFU.Constants Module Creation Plan (Quick Win #4)

**Created:** 2025-11-24
**Status:** In Progress
**Priority:** High (Quick Win #4)
**Estimated Effort:** 2-3 days

---

## Problem Statement

**Hardcoded Values Found:** 150+ instances across codebase
- 47 hardcoded paths (`C:\FFUDevelopment`)
- 36 magic sleep/wait times
- 75+ retry count values
- 10 timeout values
- VM configuration defaults
- DISM operation parameters

**Impact:**
- Cannot easily relocate builds to different drives
- Path conflicts on systems with different configurations
- No documentation of timing assumptions
- Difficult to tune performance without code changes
- Hard to test with different configurations
- No centralized configuration management

**Root Cause:**
Values are hardcoded directly in scripts and modules instead of being defined in a central constants module with clear documentation.

---

## Current Hardcoded Values Analysis

### 1. Path Defaults

**Found in:**
- BuildFFUVM.ps1 (3 instances)
- Modules/FFU.Media/FFU.Media.psm1 (4 instances)
- Modules/FFU.Apps/FFU.Apps.psm1 (2 instances)
- FFU.Common/FFU.Common.Drivers.psm1 (1 instance)

**Examples:**
```powershell
# BuildFFUVM.ps1:88
# Default is C:\FFUDevelopment

# BuildFFUVM.ps1:239
# -FFUDevelopment 'D:\FFUDevelopment'

# BuildFFUVM.ps1:532
# -DriversFolder 'C:\FFUDevelopment\Drivers'
```

### 2. VM Configuration Defaults

**Found in:** BuildFFUVM.ps1 parameters

**Examples:**
```powershell
[uint64]$Memory = 4GB        # Line 311
[uint64]$Disksize = 50GB     # Line 314
[int]$Processors = 4         # Line 317
```

### 3. Sleep/Wait Times

**Found in:**
- BuildFFUVM.ps1 (1 instance)
- Modules/FFU.Imaging/FFU.Imaging.psm1 (4 instances)
- Modules/FFU.Drivers/FFU.Drivers.psm1 (3 instances)
- Modules/FFU.Media/FFU.Media.psm1 (2 instances)
- Modules/FFU.Updates/FFU.Updates.psm1 (1 instance)
- Modules/FFU.Core/FFU.Core.psm1 (2 instances)

**Examples:**
```powershell
# DISM service stabilization
Start-Sleep -Seconds 10      # FFU.Imaging.psm1:56
Start-Sleep -Seconds 5       # FFU.Imaging.psm1:641

# VM operations
Start-Sleep -Seconds 2       # FFU.Imaging.psm1:917
Start-Sleep -Seconds 3       # FFU.Imaging.psm1:947

# Driver operations
Start-Sleep -Seconds 5       # FFU.Drivers.psm1:1079
Start-Sleep -Seconds 1       # FFU.Drivers.psm1:1088

# Media creation
Start-Sleep -Seconds 3       # FFU.Media.psm1:194
Start-Sleep -Seconds 5       # FFU.Media.psm1:269

# Update operations
Start-Sleep -Seconds 5       # FFU.Updates.psm1:782

# Process polling
Start-Sleep -Milliseconds 350  # FFU.Core.psm1:590
Start-Sleep -Milliseconds 500  # FFU.Core.psm1:649
```

### 4. Retry Configuration

**Found in:**
- Modules/FFU.Imaging/FFU.Imaging.psm1 (1 instance)
- Modules/FFU.Media/FFU.Media.psm1 (1 parameter default)
- Modules/FFU.Updates/FFU.Updates.psm1 (1 parameter default)

**Examples:**
```powershell
# DISM service initialization
$maxRetries = 3              # FFU.Imaging.psm1:905

# copype retry logic
[int]$MaxRetries = 1         # FFU.Media.psm1:247

# Windows Update package retry
[int]$MaxRetries = 2         # FFU.Updates.psm1:883
```

### 5. Size/Space Requirements

**Found in:** Various validation and pre-flight checks

**Examples:**
```powershell
# Disk space requirements (inferred from validation logic)
- Minimum OS partition size: 25GB
- Safety margin for MSU extraction: 5GB
- Multiplier for MSU extraction: 3x package size
- Minimum free disk space for copype: 10GB
```

---

## Proposed Solution

### Design: Central FFU.Constants Module

Create `Modules\FFU.Constants\FFU.Constants.psm1` with a PowerShell class containing all constants:

```powershell
# Modules/FFU.Constants/FFU.Constants.psm1

<#
.SYNOPSIS
Central constants module for FFUBuilder

.DESCRIPTION
Defines all hardcoded values, magic numbers, timeouts, retry counts,
and default paths used throughout the FFUBuilder project.

All values are documented with their purpose and rationale.
#>

class FFUConstants {
    #region Path Defaults

    # Base working directory for all FFU operations
    static [string] $DEFAULT_WORKING_DIR = "C:\FFUDevelopment"

    # VM storage location
    static [string] $DEFAULT_VM_DIR = "C:\FFUDevelopment\VM"

    # FFU capture output location
    static [string] $DEFAULT_CAPTURE_DIR = "C:\FFUDevelopment\FFU"

    # Driver storage location
    static [string] $DEFAULT_DRIVERS_DIR = "C:\FFUDevelopment\Drivers"

    # Application installers location
    static [string] $DEFAULT_APPS_DIR = "C:\FFUDevelopment\Apps"

    # Windows Update cache location
    static [string] $DEFAULT_UPDATES_DIR = "C:\FFUDevelopment\Updates"

    # Windows ADK installation paths
    static [string] $ADK_DEPLOYMENT_TOOLS = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools"
    static [string] $ADK_WINPE_PATH = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment"

    #endregion

    #region VM Configuration Defaults

    # Default VM memory allocation (4GB)
    # Minimum required for Windows 10/11 installation and updates
    static [uint64] $DEFAULT_VM_MEMORY = 4GB

    # Default VM processor count
    # Balances build performance with host system availability
    static [int] $DEFAULT_VM_PROCESSORS = 4

    # Default VHDX disk size (50GB)
    # Sufficient for base Windows + drivers + Office + updates
    static [uint64] $DEFAULT_VHDX_SIZE = 50GB

    # Generation 2 VM (UEFI boot required for modern Windows)
    static [int] $DEFAULT_VM_GENERATION = 2

    #endregion

    #region Validation Limits

    # Minimum memory for Windows installation (2GB)
    static [uint64] $MIN_VM_MEMORY = 2GB

    # Maximum memory allocation (128GB)
    # Prevents misconfiguration from exhausting host resources
    static [uint64] $MAX_VM_MEMORY = 128GB

    # Minimum disk size for Windows (25GB)
    # Based on Windows 11 minimum requirements
    static [uint64] $MIN_VHDX_SIZE = 25GB

    # Maximum disk size (2TB)
    # Reasonable upper limit for deployment images
    static [uint64] $MAX_VHDX_SIZE = 2TB

    # Minimum processor count (1)
    static [int] $MIN_VM_PROCESSORS = 1

    # Maximum processor count (64)
    # Hyper-V Gen2 maximum
    static [int] $MAX_VM_PROCESSORS = 64

    #endregion

    #region Timeouts (in seconds)

    # VM startup timeout (5 minutes)
    # Allows for UEFI initialization and Windows boot
    static [int] $VM_STARTUP_TIMEOUT = 300

    # VM shutdown timeout (10 minutes)
    # Allows for Windows update installation during shutdown
    static [int] $VM_SHUTDOWN_TIMEOUT = 600

    # DISM mount operation timeout (5 minutes)
    # Time to mount large VHDX/WIM files
    static [int] $DISM_MOUNT_TIMEOUT = 300

    # DISM package application timeout (30 minutes)
    # Large cumulative updates can take significant time
    static [int] $DISM_PACKAGE_TIMEOUT = 1800

    # DISM image capture timeout (60 minutes)
    # FFU capture of large images
    static [int] $DISM_CAPTURE_TIMEOUT = 3600

    # Network download timeout (20 minutes)
    # Large driver packages and updates
    static [int] $NETWORK_DOWNLOAD_TIMEOUT = 1200

    #endregion

    #region Wait/Sleep Times (in seconds)

    # DISM service stabilization wait
    # Ensures TrustedInstaller service is ready
    static [int] $DISM_SERVICE_WAIT = 10

    # VM state change polling interval
    # Check VM status during boot/shutdown
    static [int] $VM_STATE_POLL_INTERVAL = 5

    # DISM operation pre-flight cleanup wait
    # Allow system to stabilize after cleanup
    static [int] $DISM_CLEANUP_WAIT = 3

    # Mount point validation wait
    # Ensure mount points are fully registered
    static [int] $MOUNT_VALIDATION_WAIT = 2

    # Driver extraction wait
    # Allow driver installer to complete extraction
    static [int] $DRIVER_EXTRACTION_WAIT = 5

    # Service startup wait
    # Wait for Windows services to initialize
    static [int] $SERVICE_STARTUP_WAIT = 1

    # Update catalog search wait
    # Rate limiting for Microsoft Update Catalog requests
    static [int] $UPDATE_CATALOG_WAIT = 5

    # Process poll interval (milliseconds)
    # Background job status checking
    static [int] $PROCESS_POLL_INTERVAL_MS = 350

    # Service status check interval (milliseconds)
    # Windows service state validation
    static [int] $SERVICE_CHECK_INTERVAL_MS = 500

    #endregion

    #region Retry Configuration

    # Maximum retries for DISM service initialization
    # DISM service can be slow to start
    static [int] $MAX_DISM_SERVICE_RETRIES = 3

    # Maximum retries for copype command
    # WIM mount failures require cleanup and retry
    static [int] $MAX_COPYPE_RETRIES = 1

    # Maximum retries for Windows Update package application
    # Transient BITS/DISM failures
    static [int] $MAX_PACKAGE_RETRIES = 2

    # Maximum retries for network downloads
    # Network instability and throttling
    static [int] $MAX_DOWNLOAD_RETRIES = 3

    # Retry delay (seconds)
    # Wait between retry attempts to allow system recovery
    static [int] $RETRY_DELAY = 30

    #endregion

    #region Disk Space Requirements

    # Minimum free disk space for copype (10GB)
    # WinPE creation requires significant temporary space
    static [uint64] $MIN_FREE_SPACE_COPYPE = 10GB

    # MSU package extraction multiplier (3x)
    # expand.exe requires 3x package size for extraction
    static [int] $MSU_EXTRACTION_MULTIPLIER = 3

    # MSU extraction safety margin (5GB)
    # Additional space for temporary files
    static [uint64] $MSU_SAFETY_MARGIN = 5GB

    #endregion

    #region String Formatting

    # Maximum username length (20 characters)
    # Windows local account username limit
    static [int] $MAX_USERNAME_LENGTH = 20

    # Maximum share name length (80 characters)
    # Windows SMB share name limit
    static [int] $MAX_SHARENAME_LENGTH = 80

    # Product key format pattern
    # Standard Windows product key format
    static [string] $PRODUCT_KEY_PATTERN = '^[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}$'

    # IPv4 address format pattern
    static [string] $IPV4_PATTERN = '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'

    #endregion

    #region Feature Flags

    # Enable verbose DISM logging
    static [bool] $ENABLE_DISM_VERBOSE = $true

    # Enable automatic DISM cleanup
    static [bool] $ENABLE_AUTO_CLEANUP = $true

    # Enable pre-flight validation
    static [bool] $ENABLE_PREFLIGHT_CHECKS = $true

    #endregion
}

# Export the class
Export-ModuleMember -Variable FFUConstants
```

### Module Manifest

Create `Modules\FFU.Constants\FFU.Constants.psd1`:

```powershell
@{
    ModuleVersion = '1.0.0'
    GUID = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author = 'FFUBuilder Contributors'
    CompanyName = 'FFUBuilder'
    Copyright = '(c) 2025 FFUBuilder Contributors. All rights reserved.'
    Description = 'Central constants and configuration values for FFUBuilder'
    PowerShellVersion = '5.1'
    RootModule = 'FFU.Constants.psm1'
    FunctionsToExport = @()
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
```

---

## Implementation Steps

### Step 1: Create FFU.Constants Module

**Action:** Create new module with all constants defined

**Files:**
- `Modules/FFU.Constants/FFU.Constants.psm1` (new)
- `Modules/FFU.Constants/FFU.Constants.psd1` (new)

**Testing:**
```powershell
# Verify module loads
Import-Module .\Modules\FFU.Constants\FFU.Constants.psm1

# Verify constants accessible
[FFUConstants]::DEFAULT_WORKING_DIR
[FFUConstants]::DEFAULT_VM_MEMORY
[FFUConstants]::MAX_DISM_SERVICE_RETRIES
```

---

### Step 2: Update BuildFFUVM.ps1

**Action:** Replace hardcoded values with constant references

**Changes:**

1. **Import FFU.Constants module** (at top of script):
```powershell
# Import constants
$ConstantsModule = Join-Path $PSScriptRoot "Modules\FFU.Constants\FFU.Constants.psm1"
if (Test-Path $ConstantsModule) {
    Import-Module $ConstantsModule -Force
}
else {
    Write-Error "FFU.Constants module not found at: $ConstantsModule"
    exit 1
}
```

2. **Update parameter defaults** (lines 311, 314, 317):
```powershell
# BEFORE
[uint64]$Memory = 4GB,
[uint64]$Disksize = 50GB,
[int]$Processors = 4,

# AFTER
[uint64]$Memory = [FFUConstants]::DEFAULT_VM_MEMORY,
[uint64]$Disksize = [FFUConstants]::DEFAULT_VHDX_SIZE,
[int]$Processors = [FFUConstants]::DEFAULT_VM_PROCESSORS,
```

3. **Update validation ranges** (BEGIN block):
```powershell
# BEFORE
[ValidateRange(2GB, 128GB)]

# AFTER
[ValidateRange([FFUConstants]::MIN_VM_MEMORY, [FFUConstants]::MAX_VM_MEMORY)]
```

4. **Update Start-Sleep** (line 2425):
```powershell
# BEFORE
Start-Sleep -Seconds 10

# AFTER
Start-Sleep -Seconds ([FFUConstants]::DISM_SERVICE_WAIT)
```

5. **Update help documentation** (lines 88, 239, 532):
```powershell
# Update references to C:\FFUDevelopment to use constant
# Example documentation update:
.PARAMETER FFUDevelopment
Path to the FFU development folder. Default is $([FFUConstants]::DEFAULT_WORKING_DIR).
```

---

### Step 3: Update FFU.Imaging Module

**File:** `Modules/FFU.Imaging/FFU.Imaging.psm1`

**Changes:**

1. **Import FFU.Constants** (at top):
```powershell
# Import constants module
$ConstantsModule = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "Modules\FFU.Constants\FFU.Constants.psm1"
Import-Module $ConstantsModule -Force
```

2. **Update sleep times**:
```powershell
# Line 56 - BEFORE
Start-Sleep -Seconds 10

# AFTER
Start-Sleep -Seconds ([FFUConstants]::DISM_SERVICE_WAIT)

# Line 641 - BEFORE
Start-Sleep -Seconds 5

# AFTER
Start-Sleep -Seconds ([FFUConstants]::VM_STATE_POLL_INTERVAL)

# Line 917 - BEFORE
Start-Sleep -Seconds 2

# AFTER
Start-Sleep -Seconds ([FFUConstants]::MOUNT_VALIDATION_WAIT)

# Line 947 - BEFORE
Start-Sleep -Seconds 3

# AFTER
Start-Sleep -Seconds ([FFUConstants]::DISM_CLEANUP_WAIT)
```

3. **Update retry counts**:
```powershell
# Line 905 - BEFORE
$maxRetries = 3

# AFTER
$maxRetries = [FFUConstants]::MAX_DISM_SERVICE_RETRIES
```

---

### Step 4: Update FFU.Drivers Module

**File:** `Modules/FFU.Drivers/FFU.Drivers.psm1`

**Changes:**

1. **Import FFU.Constants** (at top)

2. **Update sleep times**:
```powershell
# Lines 1079, 1097 - BEFORE
Start-Sleep -Seconds 5

# AFTER
Start-Sleep -Seconds ([FFUConstants]::DRIVER_EXTRACTION_WAIT)

# Line 1088 - BEFORE
Start-Sleep -Seconds 1

# AFTER
Start-Sleep -Seconds ([FFUConstants]::SERVICE_STARTUP_WAIT)
```

---

### Step 5: Update FFU.Media Module

**File:** `Modules/FFU.Media/FFU.Media.psm1`

**Changes:**

1. **Import FFU.Constants** (at top)

2. **Update sleep times**:
```powershell
# Line 194 - BEFORE
Start-Sleep -Seconds 3

# AFTER
Start-Sleep -Seconds ([FFUConstants]::DISM_CLEANUP_WAIT)

# Line 269 - BEFORE
Start-Sleep -Seconds 5

# AFTER
Start-Sleep -Seconds ([FFUConstants]::VM_STATE_POLL_INTERVAL)
```

3. **Update retry configuration**:
```powershell
# Line 247 - BEFORE
[int]$MaxRetries = 1

# AFTER
[int]$MaxRetries = [FFUConstants]::MAX_COPYPE_RETRIES
```

---

### Step 6: Update FFU.Updates Module

**File:** `Modules/FFU.Updates/FFU.Updates.psm1`

**Changes:**

1. **Import FFU.Constants** (at top)

2. **Update sleep times**:
```powershell
# Line 782 - BEFORE
Start-Sleep -Seconds 5

# AFTER
Start-Sleep -Seconds ([FFUConstants]::UPDATE_CATALOG_WAIT)
```

3. **Update retry configuration**:
```powershell
# Line 883 - BEFORE
[int]$MaxRetries = 2

# AFTER
[int]$MaxRetries = [FFUConstants]::MAX_PACKAGE_RETRIES
```

---

### Step 7: Update FFU.Core Module

**File:** `Modules/FFU.Core/FFU.Core.psm1`

**Changes:**

1. **Import FFU.Constants** (at top)

2. **Update sleep times**:
```powershell
# Line 590 - BEFORE
Start-Sleep -Milliseconds 350

# AFTER
Start-Sleep -Milliseconds ([FFUConstants]::PROCESS_POLL_INTERVAL_MS)

# Line 649 - BEFORE
Start-Sleep -Milliseconds 500

# AFTER
Start-Sleep -Milliseconds ([FFUConstants]::SERVICE_CHECK_INTERVAL_MS)
```

---

### Step 8: Update Other Modules

**Files:**
- `Modules/FFU.Apps/FFU.Apps.psm1`
- `FFU.Common/FFU.Common.Drivers.psm1`

**Changes:** Replace any remaining hardcoded `C:\FFUDevelopment` references

---

## Testing Strategy

### Unit Tests

Create `Test-FFUConstants.ps1`:

```powershell
Describe "FFU.Constants Module" {
    BeforeAll {
        Import-Module .\Modules\FFU.Constants\FFU.Constants.psm1 -Force
    }

    Context "Module Loading" {
        It "Should load FFU.Constants module successfully" {
            Get-Module FFU.Constants | Should -Not -BeNullOrEmpty
        }

        It "Should define FFUConstants class" {
            [FFUConstants] | Should -Not -BeNullOrEmpty
        }
    }

    Context "Path Constants" {
        It "Should define DEFAULT_WORKING_DIR" {
            [FFUConstants]::DEFAULT_WORKING_DIR | Should -Be "C:\FFUDevelopment"
        }

        It "Should define DEFAULT_VM_DIR" {
            [FFUConstants]::DEFAULT_VM_DIR | Should -Be "C:\FFUDevelopment\VM"
        }

        It "Should define DEFAULT_CAPTURE_DIR" {
            [FFUConstants]::DEFAULT_CAPTURE_DIR | Should -Be "C:\FFUDevelopment\FFU"
        }
    }

    Context "VM Configuration Constants" {
        It "Should define DEFAULT_VM_MEMORY as 4GB" {
            [FFUConstants]::DEFAULT_VM_MEMORY | Should -Be 4GB
        }

        It "Should define DEFAULT_VM_PROCESSORS as 4" {
            [FFUConstants]::DEFAULT_VM_PROCESSORS | Should -Be 4
        }

        It "Should define DEFAULT_VHDX_SIZE as 50GB" {
            [FFUConstants]::DEFAULT_VHDX_SIZE | Should -Be 50GB
        }
    }

    Context "Validation Limits" {
        It "Should have MIN_VM_MEMORY less than MAX_VM_MEMORY" {
            [FFUConstants]::MIN_VM_MEMORY | Should -BeLessThan ([FFUConstants]::MAX_VM_MEMORY)
        }

        It "Should have MIN_VHDX_SIZE less than MAX_VHDX_SIZE" {
            [FFUConstants]::MIN_VHDX_SIZE | Should -BeLessThan ([FFUConstants]::MAX_VHDX_SIZE)
        }

        It "Should have MIN_VM_PROCESSORS less than MAX_VM_PROCESSORS" {
            [FFUConstants]::MIN_VM_PROCESSORS | Should -BeLessThan ([FFUConstants]::MAX_VM_PROCESSORS)
        }
    }

    Context "Timeout Constants" {
        It "Should define VM_STARTUP_TIMEOUT" {
            [FFUConstants]::VM_STARTUP_TIMEOUT | Should -BeGreaterThan 0
        }

        It "Should define DISM_PACKAGE_TIMEOUT" {
            [FFUConstants]::DISM_PACKAGE_TIMEOUT | Should -BeGreaterThan 0
        }
    }

    Context "Retry Configuration" {
        It "Should define MAX_DISM_SERVICE_RETRIES" {
            [FFUConstants]::MAX_DISM_SERVICE_RETRIES | Should -Be 3
        }

        It "Should define MAX_COPYPE_RETRIES" {
            [FFUConstants]::MAX_COPYPE_RETRIES | Should -Be 1
        }

        It "Should define MAX_PACKAGE_RETRIES" {
            [FFUConstants]::MAX_PACKAGE_RETRIES | Should -Be 2
        }
    }

    Context "Wait Times" {
        It "Should define DISM_SERVICE_WAIT" {
            [FFUConstants]::DISM_SERVICE_WAIT | Should -Be 10
        }

        It "Should define VM_STATE_POLL_INTERVAL" {
            [FFUConstants]::VM_STATE_POLL_INTERVAL | Should -Be 5
        }

        It "Should define PROCESS_POLL_INTERVAL_MS" {
            [FFUConstants]::PROCESS_POLL_INTERVAL_MS | Should -Be 350
        }
    }
}
```

### Integration Tests

Verify modules load correctly:

```powershell
# Test all modules import successfully with FFU.Constants
$modules = @(
    ".\Modules\FFU.Constants\FFU.Constants.psm1",
    ".\Modules\FFU.Imaging\FFU.Imaging.psm1",
    ".\Modules\FFU.Drivers\FFU.Drivers.psm1",
    ".\Modules\FFU.Media\FFU.Media.psm1",
    ".\Modules\FFU.Updates\FFU.Updates.psm1",
    ".\Modules\FFU.Core\FFU.Core.psm1"
)

foreach ($module in $modules) {
    Import-Module $module -Force
    Write-Host "✓ Loaded $module successfully"
}

# Test BuildFFUVM.ps1 parameter defaults
. .\BuildFFUVM.ps1 -? | Should -Not -Throw
```

### Regression Tests

Run existing test suites:

```powershell
# Ensure all existing tests still pass
.\Test-ParameterValidation.ps1
.\Test-ShortenedWindowsSKU.ps1
.\Test-DISMCleanupAndCopype.ps1
.\Test-MSUPackageFix.ps1
```

---

## Backward Compatibility

**Breaking Changes:** None
- All hardcoded values replaced with equivalent constants
- Default behavior unchanged
- Module imports added at script/module initialization
- No changes to public APIs or parameters

**Migration Path:** Not applicable (internal refactoring only)

---

## Environment Variable Overrides

**Future Enhancement:** Allow environment variables to override constants

```powershell
# Example implementation in FFU.Constants.psm1
static [string] GetWorkingDir() {
    $envOverride = $env:FFU_WORKING_DIR
    if ($envOverride -and (Test-Path $envOverride)) {
        return $envOverride
    }
    return [FFUConstants]::DEFAULT_WORKING_DIR
}
```

---

## Success Criteria

- [ ] FFU.Constants module created with all hardcoded values
- [ ] All modules import FFU.Constants successfully
- [ ] BuildFFUVM.ps1 uses constants for all default values
- [ ] All sleep/wait times reference constants
- [ ] All retry counts reference constants
- [ ] All validation limits reference constants
- [ ] No hardcoded paths remain in active code
- [ ] All unit tests pass
- [ ] All integration tests pass
- [ ] Module documentation complete with rationale for each constant

---

## Impact Assessment

**Maintainability:** ✅ High Impact
- Centralized configuration management
- Self-documenting constants with rationale
- Easy to tune performance without code changes
- Clear separation of configuration from logic

**Testability:** ✅ Medium Impact
- Can mock constants for testing
- Can test with different configurations easily
- Clear boundaries for test scenarios

**Reliability:** ✅ Medium Impact
- Prevents typos in repeated values
- Ensures consistency across codebase
- Documents assumptions and rationale

**Performance:** ✅ Neutral
- No performance impact
- Slightly faster than string concatenation for paths

---

## Related Issues

- Quick Win #4: Create FFU.Constants Module
- Architecture Issue #5: Hardcoded Paths and Values (High Priority)

---

**Document Status:** Active
**Next Update:** After module creation complete
