# Fixed Issues Archive

This file contains detailed documentation for issues that have been fixed in FFU Builder. For current issues and workarounds, see the main [CLAUDE.md](../CLAUDE.md).

> **Note:** This archive is maintained automatically. When a new fix is added to CLAUDE.md, the PM agent will move detailed fix documentation here after 5 releases.

---

## Table of Contents

- [DISM WIM Mount Error 0x800704DB (v1.3.5)](#dism-wim-mount-error-0x800704db-fixed-v135)
- [[FFUConstants] Type Not Found (v1.2.9)](#ffuconstants-type-not-found-during-ffu-capture-fixed-v129)
- [FFU.Constants Not Found in ThreadJob (v1.2.8)](#ffuconstants-not-found-in-threadjob-fixed-v128)
- [Module Loading Failure in Background Jobs (v1.2.7)](#module-loading-failure-in-background-jobs-fixed-v127)
- [Hardcoded Installation Paths (v1.2.3)](#hardcoded-installation-paths-fixed-v123)
- [DISM Initialization Error 0x80004005 (v1.2.2)](#dism-initialization-error-0x80004005-fixed-v122)
- [Monitor Tab Shows Stale Log Entries (v1.2.1)](#monitor-tab-shows-stale-log-entries-fixed-v121)
- [Module Best Practices Compliance (v1.0.11)](#module-best-practices-compliance-fixed-v1011)

---

## DISM WIM Mount Error 0x800704DB (FIXED v1.3.5)

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
- `dism.exe /Mount-Image` -> `Mount-WindowsImage` cmdlet
- `dism.exe /Unmount-Image` -> `Dismount-WindowsImage` cmdlet

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

---

## [FFUConstants] Type Not Found During FFU Capture (FIXED v1.2.9)

**Symptoms:** Build fails during FFU capture phase with error:
```
Unable to find type [FFUConstants]
```

**Root Cause:** In v1.2.8, we removed the `using module` statement from BuildFFUVM.ps1 to fix the ThreadJob path issue. However, line 3542 still had runtime code using `[FFUConstants]::VM_STATE_POLL_INTERVAL`. PowerShell classes defined in modules require `using module` to make the type available - `Import-Module` only makes functions available, not class types.

**Solution (Implemented in v1.2.9):**
- Replaced `[FFUConstants]::VM_STATE_POLL_INTERVAL` with hardcoded value `5` on line 3542
- Added comment `# VM poll interval - must match [FFUConstants]::VM_STATE_POLL_INTERVAL`
- This follows the same pattern used in v1.2.8 for Memory, Disksize, and Processors defaults

**Files Changed:**
- `BuildFFUVM.ps1` line 3542
- `Tests/Unit/BuildFFUVM.UsingModulePath.Tests.ps1`
- `Tests/Unit/BuildFFUVM.FFUConstantsType.Tests.ps1`: New test file with 22 tests

---

## FFU.Constants Not Found in ThreadJob (FIXED v1.2.8)

**Symptoms:** Build fails immediately when launched from BuildFFUVM_UI.ps1 with error:
```
The required module 'FFU.Constants' was not loaded because no valid module file was found in any module directory
```

**Root Cause:**
BuildFFUVM.ps1 line 9 used `using module .\Modules\FFU.Constants\FFU.Constants.psm1` to import constants for the param block default values. The `using` statement resolves relative paths from the **current working directory**, not the script location (`$PSScriptRoot`). When launched in a ThreadJob by BuildFFUVM_UI.ps1, the working directory is typically `C:\Users\<user>\OneDrive\Documents`, not the script's directory.

**Solution (Implemented in v1.2.8):**
Belt-and-suspenders approach with two layers of defense:

1. **BuildFFUVM_UI.ps1 fix** (lines 602-614):
   - Added `Set-Location $ScriptRoot` at the beginning of the ThreadJob scriptBlock

2. **BuildFFUVM.ps1 fix** (lines 5-17, param block):
   - **Removed** the `using module` statement entirely
   - **Hardcoded** param block default values:
     - `$Memory = 4GB` (was `[FFUConstants]::DEFAULT_VM_MEMORY`)
     - `$Disksize = 50GB` (was `[FFUConstants]::DEFAULT_VHDX_SIZE`)
     - `$Processors = 4` (was `[FFUConstants]::DEFAULT_VM_PROCESSORS`)

**Test Coverage:**
- `Tests/Unit/BuildFFUVM.UsingModulePath.Tests.ps1`: 27 test cases

---

## Module Loading Failure in Background Jobs (FIXED v1.2.7)

**Symptoms:** Build fails immediately when launched from BuildFFUVM_UI.ps1 with error:
```
The 'Get-CleanupRegistry' command was found in the module 'FFU.Core', but the module could not be loaded
```

**Root Cause:** Early error handler executed before module dependencies were properly configured. FFU.Core requires FFU.Constants, and PSModulePath wasn't set up yet when the trap handler fired.

**Solution (Implemented in v1.2.7):**
Defense-in-depth approach with three layers of protection:

1. **Early PSModulePath Configuration** (BuildFFUVM.ps1 lines 626-637)
2. **Defensive Trap Handler** (lines 777-793) - checks if function exists before calling
3. **Defensive Exit Handler** (lines 799-809) - same pattern

**Code Example:**
```powershell
# Defensive trap handler
trap {
    if (Get-Command Get-CleanupRegistry -ErrorAction SilentlyContinue) {
        Get-CleanupRegistry | Invoke-FailureCleanup
    } else {
        WriteLog "Trap handler invoked but cleanup registry not available"
    }
    throw $_
}
```

**Test Coverage:**
- `Tests/Unit/BuildFFUVM.ModuleLoading.Tests.ps1`: 25 test cases

---

## Hardcoded Installation Paths (FIXED v1.2.3)

**Symptoms:** FFUBuilder could only be installed in `C:\FFUDevelopment`. Installing in a different location caused path resolution failures.

**Root Cause:** FFU.Constants module had ~40 instances of `C:\FFUDevelopment` hardcoded.

**Solution (Implemented in v1.2.3):**
Added dynamic path resolution in FFU.Constants v1.1.0:

1. **GetBasePath() method** - Resolves installation path from module location
2. **Get*Dir() methods** - Dynamic path construction
3. **SetBasePath()/ResetBasePath()** - For testing and manual overrides
4. **Environment variable overrides** - `FFU_BASE_PATH`, etc.

**Migration Guide:**
```powershell
# Old (hardcoded, deprecated)
$path = [FFUConstants]::DEFAULT_WORKING_DIR  # Always C:\FFUDevelopment

# New (dynamic, recommended)
$path = [FFUConstants]::GetDefaultWorkingDir()  # Resolves to actual installation
```

**Test Coverage:**
- `Tests/Unit/FFU.Constants.DynamicPaths.Tests.ps1` - 27 test cases

---

## DISM Initialization Error 0x80004005 (FIXED v1.2.2)

**Symptoms:** Build fails immediately with error: "DismInitialize failed. Error code = 0x80004005" and UI reports "No log file was created"

**Root Cause:** Hyper-V feature check internally calls DISM API (`DismInitialize`) BEFORE logging was initialized.

**Solution (Implemented in v1.2.2):**
1. Move logging initialization earlier
2. Add DISM cleanup before check (`dism.exe /Cleanup-Mountpoints`)
3. Add retry logic (3 retries with 5-second delays)
4. Provide actionable error messages

**Common Causes:**
- Another DISM operation in progress
- Stale DISM mount points
- Antivirus blocking DISM
- Insufficient permissions

**Test Coverage:**
- `Tests/Unit/BuildFFUVM.DismInitialization.Tests.ps1`: 40 test cases

---

## Monitor Tab Shows Stale Log Entries (FIXED v1.2.1)

**Symptoms:** When clicking Build button, the Monitor tab briefly shows log entries from the previous build run.

**Root Cause:** Race condition where the UI's StreamReader opens the old log file before the background job deletes it.

**Solution (Implemented in v1.2.1):**
- Close existing StreamReader before starting new build
- Delete old log file from UI BEFORE starting background job
- Clear log data collection
- Add 100ms delay after deletion

**Test Coverage:**
- `Tests/Unit/FFUUI.LogRaceCondition.Tests.ps1`: 23 test cases

---

## Module Best Practices Compliance (FIXED v1.0.11)

**Symptoms:** PSScriptAnalyzer warnings about unapproved verbs when importing FFU.Core module

**Root Cause:** Three functions used non-standard PowerShell verbs.

**Solution (Implemented in v1.0.11):**
Renamed functions to use approved verbs with backward-compatible aliases:

| Old Name (Deprecated Alias) | New Name (Approved Verb) |
|----------------------------|-------------------------|
| `LogVariableValues` | `Write-VariableValues` |
| `Mark-DownloadInProgress` | `Set-DownloadInProgress` |
| `Cleanup-CurrentRunDownloads` | `Clear-CurrentRunDownloads` |

**Test Coverage:**
- `Tests/Unit/Module.BestPractices.Tests.ps1`

---

## Additional Fix Documentation

For more fix documentation, see individual files in `docs/fixes/`:
- [CHECKPOINT_UPDATE_0x80070228_FIX.md](fixes/CHECKPOINT_UPDATE_0x80070228_FIX.md)
- [WINPE_BOOTWIM_CREATION_FIX.md](fixes/WINPE_BOOTWIM_CREATION_FIX.md)
- [MSU_PACKAGE_FIX_SUMMARY.md](fixes/MSU_PACKAGE_FIX_SUMMARY.md)
- [COPYPE_WIM_MOUNT_FIX.md](fixes/COPYPE_WIM_MOUNT_FIX.md)
- [POWERSHELL_CROSSVERSION_FIX.md](fixes/POWERSHELL_CROSSVERSION_FIX.md)
- [FFU_OPTIMIZATION_ERROR_1167_FIX.md](fixes/FFU_OPTIMIZATION_ERROR_1167_FIX.md)
- [EXPAND_WINDOWSIMAGE_FIX.md](fixes/EXPAND_WINDOWSIMAGE_FIX.md)
- [CMD_PATH_QUOTING_FIX.md](fixes/CMD_PATH_QUOTING_FIX.md)
- [WRITELOG_PATH_VALIDATION_FIX.md](fixes/WRITELOG_PATH_VALIDATION_FIX.md)

---

## Module Extraction History

### FFU.Common.ParallelDownload Module (v1.1.0)
**Created:** December 8, 2025
**Location:** `FFUDevelopment\FFU.Common\FFU.Common.ParallelDownload.psm1`
**Purpose:** Concurrent download orchestration with cross-version PowerShell support

**Exported Functions:**
- `Start-ParallelDownloads` - Main orchestrator
- `New-DownloadItem` - Factory function for download items
- `New-ParallelDownloadConfig` - Configuration factory
- `New-KBDownloadItems` - Windows Update download items
- `New-GenericDownloadItem` - Single download item
- `Get-ParallelDownloadSummary` - Statistics generator

**Key Features:**
- PowerShell 7+ uses `ForEach-Object -Parallel` with thread-safe `ConcurrentBag`
- PowerShell 5.1 uses `RunspacePool` with synchronized `ArrayList`
- Multi-method fallback (BITS -> WebRequest -> WebClient -> curl)

### FFU.Drivers Module (v1.0.0)
**Extracted:** November 20, 2025
**Location:** `FFUDevelopment\Modules\FFU.Drivers\`
**Purpose:** Centralized OEM driver management

**Extracted Functions:**
- `Get-MicrosoftDrivers` - Surface drivers
- `Get-HPDrivers` - HP drivers via HPIA catalog
- `Get-LenovoDrivers` - Lenovo drivers via PSREF API
- `Get-DellDrivers` - Dell drivers from Dell catalog
- `Copy-Drivers` - WinPE boot media drivers
