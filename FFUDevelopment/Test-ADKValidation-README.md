# ADK Pre-Flight Validation Test Suite

## Overview

This test script (`Test-ADKValidation.ps1`) verifies the ADK pre-flight validation system is working correctly.

## Test Results

**Test Run:** 87.5% Pass Rate (7/8 tests passed)

### Tests Performed

1. ✅ **Validation function exists** - Confirms `Test-ADKPrerequisites` is loaded
2. ✅ **Validation result object structure** - Verifies all required properties present
3. ❌ **Current system ADK status check** - Failed due to missing ADK components (expected in test environment)
4. ✅ **ADK registry detection** - Registry checks working correctly
5. ✅ **Critical files validation** - File validation logic working
6. ✅ **Error message templates** - All 5 templates present and formatted
7. ✅ **ThrowOnFailure parameter** - Exception throwing behavior correct
8. ✅ **Architecture parameter** - Both x64 and arm64 supported

### What the Test Detected (On Test System)

The validation correctly identified:
- ✅ ADK is installed (registry found)
- ❌ Deployment Tools feature missing
- ❌ WinPE add-on not installed
- ❌ 6 critical files missing (DandISetEnv.bat, oscdimg.exe, boot files, copype.cmd)

**This is exactly the scenario the validation was designed to catch!**

## Running the Test

### Basic Usage
```powershell
.\Test-ADKValidation.ps1
```

### Test Options
```powershell
# Test with arm64 architecture
.\Test-ADKValidation.ps1 -WindowsArch arm64

# Skip auto-install tests (prevents system modifications)
.\Test-ADKValidation.ps1 -SkipAutoInstall

# Both options
.\Test-ADKValidation.ps1 -WindowsArch x64 -SkipAutoInstall
```

## What Gets Tested

### 1. Function Loading
- Verifies validation functions are loaded from BuildFFUVM.ps1
- Tests function availability

### 2. Object Structure
- Validates result object has all required properties:
  - `IsValid`, `ADKInstalled`, `ADKPath`, `ADKVersion`
  - `DeploymentToolsInstalled`, `WinPEAddOnInstalled`
  - `MissingFiles`, `MissingExecutables`, `Errors`, `Warnings`
  - `ValidationTimestamp`

### 3. System Status
- Runs full validation on current system
- Displays detailed status of all components
- Shows missing files and errors

### 4. Registry Detection
- Tests ADK registry key detection
- Verifies path validation

### 5. Critical Files
- Checks for all required ADK files:
  - DandISetEnv.bat
  - oscdimg.exe
  - Boot files (etfsboot.com, Efisys.bin, Efisys_noprompt.bin)
  - copype.cmd

### 6. Error Templates
- Verifies all 5 error message templates exist:
  - ADKNotInstalled
  - DeploymentToolsMissing
  - WinPEMissing
  - MissingCriticalFiles
  - ArchitectureMismatch

### 7. Parameter Behavior
- Tests `ThrowOnFailure` parameter
- Verifies exception throwing on validation failure
- Confirms object return when `ThrowOnFailure=$false`

### 8. Architecture Support
- Tests x64 architecture
- Tests arm64 architecture
- Verifies architecture-specific file checks

## Expected Output

### When ADK is Properly Installed
```
===============================================================================
  Test Summary
===============================================================================

Total Tests Run:     8
Tests Passed:        8
Tests Failed:        0
Pass Rate:           100%

===============================================================================
  [PASS] ALL TESTS PASSED
===============================================================================
```

### When ADK Components Are Missing
```
===============================================================================
  Test Summary
===============================================================================

Total Tests Run:     8
Tests Passed:        7
Tests Failed:        1
Pass Rate:           87.5%

===============================================================================
  [FAIL] SOME TESTS FAILED
===============================================================================
```

The failure is expected when ADK is not fully installed - it demonstrates the validation is working correctly by detecting missing components.

## Interpreting Results

### Validation Working Correctly If You See:
- ✅ Clear error messages about missing components
- ✅ Specific file paths that are missing
- ✅ Installation instructions displayed
- ✅ Colored output (Green=OK, Red=Error, Yellow=Warning)

### Validation May Have Issues If:
- ❌ No error messages for obviously missing components
- ❌ Generic errors without specific paths
- ❌ Test script crashes or hangs
- ❌ Functions not loading

## Example Test Output

### Successful Detection of Missing Components:
```
11/07/2025 11:57:26 [INFO] ADK Pre-Flight: Starting ADK pre-flight validation for architecture: x64
11/07/2025 11:57:26 [  OK] ADK Pre-Flight: ADK installation found
    Path : C:\Program Files (x86)\Windows Kits\10\
11/07/2025 11:57:26 [FAIL] ADK Pre-Flight: Missing: Deployment and Imaging environment setup
    Path : C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\DandISetEnv.bat
11/07/2025 11:57:26 [FAIL] ADK Pre-Flight: Missing: WinPE media creation script (copype.cmd)
    Path : C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\copype.cmd
11/07/2025 11:57:26 [CRIT] ADK Pre-Flight: === ADK pre-flight validation FAILED ===
```

### Error Message Display:
```
════════════════════════════════════════════════════════════════════════════════
  CRITICAL ERROR: Deployment Tools Feature Missing
════════════════════════════════════════════════════════════════════════════════

Windows ADK is installed but the Deployment Tools feature is missing.

Resolution Options:
  1. Manual Installation:
     Run: <path> /quiet /features OptionId.DeploymentTools

  2. Automatic Installation:
     Re-run FFU build script with -UpdateADK $true
```

## Troubleshooting

### Test Script Fails to Load Functions
**Issue:** "Failed to load validation functions"
**Solution:** Ensure BuildFFUVM.ps1 is in the same directory

### All Tests Fail
**Issue:** PowerShell execution policy or permissions
**Solution:** Run as Administrator: `powershell.exe -ExecutionPolicy Bypass -File .\Test-ADKValidation.ps1`

### Unicode Character Errors
**Issue:** Console encoding issues
**Solution:** Test script uses ASCII characters only - should work on all systems

## Notes

- Tests are read-only unless `-AutoInstall` is enabled
- Test runs in ~2-3 seconds
- Safe to run repeatedly
- Does not modify the system (unless AutoInstall enabled)
- Exit code 0 = all tests passed
- Exit code 1 = some tests failed

## Integration with FFU Build

The validation tested by this script is automatically triggered when:
- Running `BuildFFUVM.ps1` with `-CreateCaptureMedia $true`
- Running `BuildFFUVM.ps1` with `-CreateDeploymentMedia $true`

No manual invocation needed - the pre-flight validation runs automatically before WinPE media creation begins.
