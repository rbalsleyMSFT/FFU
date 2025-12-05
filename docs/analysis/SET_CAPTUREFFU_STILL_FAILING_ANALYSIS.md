# Set-CaptureFFU Still Failing After Fix - Troubleshooting Analysis

**Date**: 2025-11-24
**Issue**: Set-CaptureFFU still showing "not recognized" error after implementation
**Previous Fix**: Commit a5064ec implemented Set-CaptureFFU and Remove-FFUUserShare
**Status**: ⚠️ **REQUIRES TROUBLESHOOTING**

---

## Error Still Occurring

```
11/24/2025 7:09:16 AM Set-CaptureFFU function failed with error The term 'Set-CaptureFFU' is not recognized as a name of a cmdlet, function, script file, or executable program.
```

**This error occurred AFTER the fix was committed** (commit a5064ec on 2025-11-23).

---

## Root Cause Analysis

### Possible Reasons

#### 1. **Changes Not Pulled / Old Code Running** ⭐ MOST LIKELY

**Evidence:**
- Fix was committed to branch `feature/improvements-and-fixes`
- User may not have pulled latest changes
- Running old version of BuildFFUVM.ps1 without the fix

**How to verify:**
```powershell
cd C:\claude\FFUBuilder
git log --oneline -5  # Check if a5064ec is present
git status            # Check if on correct branch
```

**Expected:** Commit `a5064ec` should appear in git log

---

#### 2. **PowerShell Module Cache Issue**

**Evidence:**
- PowerShell caches modules in memory per session
- Even with `-Force`, cached exports may persist
- `Import-Module -Force` refreshes module but may not clear cache completely

**How modules are cached:**
```powershell
# Once imported, module functions stay in session
Import-Module FFU.VM -Force  # May use cached exports

# Module cache location
$env:PSModulePath  # Modules loaded from here are cached
```

**How to verify:**
```powershell
# Check what's actually loaded
Get-Module FFU.VM | Select-Object Name, Version, Path

# Check if Set-CaptureFFU is available
Get-Command Set-CaptureFFU -ErrorAction SilentlyContinue
```

---

#### 3. **Module Import Failing Silently**

**Evidence:**
- BuildFFUVM.ps1 line 566: `Import-Module "FFU.VM" -Force -ErrorAction Stop -WarningAction SilentlyContinue`
- `-ErrorAction Stop` should catch failures, but `-WarningAction SilentlyContinue` may hide issues
- If module has syntax errors, import might partially fail

**How to verify:**
```powershell
# Try importing module with verbose output
Import-Module FFU.VM -Force -Verbose

# Check for errors
$Error[0] | Format-List * -Force
```

---

#### 4. **Module Manifest Issues**

**Evidence:**
- Module manifest (.psd1) might not export new functions
- Even if psm1 has Export-ModuleMember, manifest takes precedence

**How to verify:**
```powershell
# Check if manifest exists
Test-Path "C:\claude\FFUBuilder\FFUDevelopment\Modules\FFU.VM\FFU.VM.psd1"

# Check manifest exports
Import-PowerShellDataFile "C:\claude\FFUBuilder\FFUDevelopment\Modules\FFU.VM\FFU.VM.psd1" |
    Select-Object -ExpandProperty FunctionsToExport
```

---

#### 5. **Module Path Resolution**

**Evidence:**
- BuildFFUVM.ps1 imports by name: `Import-Module "FFU.VM"`
- Relies on $env:PSModulePath being set correctly
- If path wrong, old module version might load from elsewhere

**How PSModulePath is set (BuildFFUVM.ps1:553-558):**
```powershell
$ModulePath = "$PSScriptRoot\Modules"
if ($env:PSModulePath -notlike "*$ModulePath*") {
    $env:PSModulePath = "$ModulePath;$env:PSModulePath"
}
```

**How to verify:**
```powershell
$env:PSModulePath -split ';'  # Check all paths
Get-Module FFU.VM -ListAvailable  # Shows all available versions
```

---

#### 6. **Background Job Scope Issue**

**Evidence:**
- BuildFFUVM_UI.ps1 runs BuildFFUVM.ps1 in background job
- Background jobs have isolated scope
- Module imports in main script may not propagate to job

**How to verify:**
```powershell
# Check if running in background job
$PSSenderInfo  # Non-null if in background job
```

---

## Two Solution Approaches

### Solution 1: Force Complete Module Reload with Diagnostic Verification ⭐ **RECOMMENDED**

**Approach:**
- Add diagnostic verification before Set-CaptureFFU call
- Force module unload and reload
- Validate function availability before calling
- Provide clear error if module import fails

**Implementation:**

Add diagnostic check in BuildFFUVM.ps1 before Set-CaptureFFU call (before line 2192):

```powershell
#Create ffu user and share to capture FFU to
try {
    # DIAGNOSTIC: Verify Set-CaptureFFU is available
    WriteLog "Verifying Set-CaptureFFU function availability..."

    $funcAvailable = Get-Command Set-CaptureFFU -ErrorAction SilentlyContinue

    if (-not $funcAvailable) {
        WriteLog "WARNING: Set-CaptureFFU not found in current session. Attempting module reload..."

        # Force complete module reload
        Remove-Module FFU.VM -Force -ErrorAction SilentlyContinue

        $modulePath = Join-Path $PSScriptRoot "Modules\FFU.VM\FFU.VM.psm1"
        WriteLog "Importing FFU.VM module from: $modulePath"

        Import-Module $modulePath -Force -Global -ErrorAction Stop

        # Verify again
        $funcAvailable = Get-Command Set-CaptureFFU -ErrorAction SilentlyContinue

        if (-not $funcAvailable) {
            WriteLog "ERROR: Set-CaptureFFU still not available after reload"
            WriteLog "Module path: $modulePath"
            WriteLog "Module imports:"
            Get-Module FFU.VM | Format-List | Out-String | ForEach-Object { WriteLog $_ }
            WriteLog "Available commands from FFU.VM:"
            Get-Command -Module FFU.VM | Select-Object -ExpandProperty Name | ForEach-Object { WriteLog "  - $_" }

            throw "Set-CaptureFFU function not available. Module import failed."
        }

        WriteLog "Set-CaptureFFU successfully loaded after module reload"
    }
    else {
        WriteLog "Set-CaptureFFU verified available"
    }

    # Call function with parameters
    Set-CaptureFFU -Username $Username -ShareName $ShareName -FFUCaptureLocation $FFUCaptureLocation
}
catch {
    Write-Host 'Set-CaptureFFU function failed'
    WriteLog "Set-CaptureFFU function failed with error $_"
    Remove-FFUVM -VMName $VMName -VMPath $VMPath -InstallApps $InstallApps `
                 -VhdxDisk $vhdxDisk -FFUDevelopmentPath $FFUDevelopmentPath `
                 -Username $Username -ShareName $ShareName
    throw $_
}
```

**Advantages:**
- ✅ **Diagnostic visibility**: Logs exactly what's happening
- ✅ **Self-healing**: Automatically reloads module if function missing
- ✅ **Clear errors**: Identifies exact failure point
- ✅ **Forces fresh load**: Remove-Module + Import ensures no cache
- ✅ **Global scope**: `-Global` ensures availability across scopes
- ✅ **Comprehensive logging**: Lists all available commands for debugging

---

### Solution 2: Import Module by Full Path Instead of Name

**Approach:**
- Change all module imports to use full file paths
- Bypasses $env:PSModulePath resolution
- Guarantees correct version loads

**Implementation:**

Replace BuildFFUVM.ps1 lines 562-568:

```powershell
# Import modules in dependency order using full paths for reliability
$ModulePath = "$PSScriptRoot\Modules"

Import-Module "$ModulePath\FFU.Core\FFU.Core.psm1" -Force -Global -ErrorAction Stop -WarningAction SilentlyContinue
Import-Module "$ModulePath\FFU.ADK\FFU.ADK.psm1" -Force -Global -ErrorAction Stop -WarningAction SilentlyContinue
Import-Module "$ModulePath\FFU.Drivers\FFU.Drivers.psm1" -Force -Global -ErrorAction Stop -WarningAction SilentlyContinue
Import-Module "$ModulePath\FFU.Updates\FFU.Updates.psm1" -Force -Global -ErrorAction Stop -WarningAction SilentlyContinue
Import-Module "$ModulePath\FFU.VM\FFU.VM.psm1" -Force -Global -ErrorAction Stop -WarningAction SilentlyContinue
Import-Module "$ModulePath\FFU.Imaging\FFU.Imaging.psm1" -Force -Global -ErrorAction Stop -WarningAction SilentlyContinue
Import-Module "$ModulePath\FFU.Media\FFU.Media.psm1" -Force -Global -ErrorAction Stop -WarningAction SilentlyContinue
Import-Module "$ModulePath\FFU.Apps\FFU.Apps.psm1" -Force -Global -ErrorAction Stop -WarningAction SilentlyContinue
```

**Advantages:**
- ✅ **Explicit paths**: No ambiguity about which module loads
- ✅ **Bypasses path issues**: Doesn't rely on $env:PSModulePath
- ✅ **Global scope**: Forces global availability

**Disadvantages:**
- ⚠️ Doesn't address module cache if old session still running
- ⚠️ Doesn't provide diagnostics if still fails

---

## Recommended Solution: **Solution 1**

**Rationale:**
1. **Diagnostic first**: Need to understand WHY function isn't available
2. **Self-healing**: Automatically recovers from cache issues
3. **Clear errors**: Tells user exactly what's wrong
4. **Addresses all scenarios**: Works whether it's cache, path, or import issue

Solution 2 is good as a secondary measure but doesn't help diagnose the root cause.

---

## Immediate Troubleshooting Steps for User

**Before applying fix, run these commands:**

```powershell
# 1. Verify latest code is present
cd C:\claude\FFUBuilder
git log --oneline -1  # Should show commit a5064ec or later

# 2. Check if functions exist in module file
Select-String -Path "C:\claude\FFUBuilder\FFUDevelopment\Modules\FFU.VM\FFU.VM.psm1" -Pattern "^function Set-CaptureFFU"

# 3. Try importing module manually
Remove-Module FFU.VM -Force -ErrorAction SilentlyContinue
Import-Module "C:\claude\FFUBuilder\FFUDevelopment\Modules\FFU.VM\FFU.VM.psm1" -Force -Global -Verbose

# 4. Verify function available
Get-Command Set-CaptureFFU

# 5. Check module exports
Get-Command -Module FFU.VM

# 6. If above works, try calling function
Set-CaptureFFU -Username "test_user" -ShareName "TestShare" -FFUCaptureLocation "C:\Temp" -WhatIf
```

**Expected results:**
- Step 1: Commit a5064ec should be present
- Step 2: Should find "function Set-CaptureFFU" at line 441
- Step 3: Should import without errors
- Step 4: Should show Set-CaptureFFU command info
- Step 5: Should list Set-CaptureFFU and Remove-FFUUserShare
- Step 6: Should show what the function would do (WhatIf doesn't exist, will try to run)

---

## Implementation Plan

1. ⏳ Add diagnostic verification before Set-CaptureFFU call
2. ⏳ Add module reload logic with Remove-Module + Import-Module
3. ⏳ Add comprehensive logging of module state
4. ⏳ Add `-Global` flag to all module imports (Solution 2 hybrid)
5. ⏳ Test with fresh PowerShell session
6. ⏳ Test with background job (UI scenario)
7. ⏳ Create test that validates module caching behavior

---

## Success Criteria

✅ Set-CaptureFFU function recognized and executes successfully
✅ Diagnostic logs show function availability verification
✅ Module reload logic triggers if function missing
✅ Clear error messages if module import fails
✅ Works in fresh PowerShell session
✅ Works when run from BuildFFUVM_UI.ps1 (background job)
✅ All tests pass

---

**Analysis Complete**: 2025-11-24
**Next Step**: Implement Solution 1 with diagnostic verification
