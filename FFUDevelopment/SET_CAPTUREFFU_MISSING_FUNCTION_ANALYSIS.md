# Set-CaptureFFU Missing Function Error - Root Cause Analysis

**Date**: 2025-11-23
**Issue**: `The term 'Set-CaptureFFU' is not recognized as a name of a cmdlet, function, script file, or executable program`
**Location**: BuildFFUVM.ps1 line 2192
**Severity**: HIGH - Breaks VM-based FFU builds with app installation

---

## Error Reproduction

**Error Message:**
```
11/23/2025 8:28:23 AM Set-CaptureFFU function failed with error The term 'Set-CaptureFFU' is not recognized as a name of a cmdlet, function, script file, or executable program.
Check the spelling of the name, or if a path was included, verify that the path is correct and try again.
```

**Log Context:**
```
11/23/2025 8:28:15 AM Creating new FFU VM
11/23/2025 8:28:20 AM Starting vmconnect localhost _FFU-1076521636
11/23/2025 8:28:23 AM FFU VM Created
11/23/2025 8:28:23 AM Set-CaptureFFU function failed with error The term 'Set-CaptureFFU' is not recognized...
```

**Affected Code (BuildFFUVM.ps1:2190-2193):**
```powershell
#Create ffu user and share to capture FFU to
try {
    Set-CaptureFFU
}
catch {
    Write-Host 'Set-CaptureFFU function failed'
    WriteLog "Set-CaptureFFU function failed with error $_"
    ...
}
```

---

## Root Cause Analysis

### Investigation Results

1. **Function is called but never defined**:
   - `Set-CaptureFFU` is called at line 2192
   - No function definition exists in BuildFFUVM.ps1
   - No function definition exists in any module (FFU.VM, FFU.Common, etc.)
   - Git history shows no commits ever defining this function

2. **Companion function also missing**:
   - `Remove-FFUUserShare` is called at line 2286 but also undefined
   - FFU.VM.psm1 line 405 also calls `Remove-FFUUserShare` (undefined)

3. **Context clues reveal intent**:
   - Comment: "Create ffu user and share to capture FFU to"
   - Parameters: `$ShareName = "FFUCaptureShare"`, `$Username = "ffu_user"`
   - Called immediately after VM creation
   - Cleanup function called when `$InstallApps` is true

4. **What these functions should do**:
   Based on parameter names, comments, and usage context:

   **Set-CaptureFFU**:
   - Create Windows user account (`ffu_user`) for FFU capture
   - Create network share (`FFUCaptureShare`) pointing to FFU output directory
   - Grant user permissions to the share
   - Set share permissions for remote capture from VM

   **Remove-FFUUserShare**:
   - Remove network share created during setup
   - Remove user account created during setup
   - Cleanup resources

### Why This Wasn't Caught Earlier

1. **Conditional execution**: Functions only called when `$InstallApps` is true
2. **Silent failure path**: Error is caught and logged but build continues
3. **Testing focused on basic builds**: Testing likely didn't use `-InstallApps $true` parameter
4. **Function stubs**: Comments and try/catch blocks suggest functions were planned but never implemented

---

## Possible Root Causes

1. ✅ **Unimplemented functions** - Functions were planned but never coded (ROOT CAUSE)
2. ✅ **Missing during modularization** - Functions should have been moved to FFU.VM but weren't
3. ❌ Module import issue - Functions exist but module not imported (checked: functions don't exist)
4. ❌ Typo in function name - Function spelled differently (checked: no similar functions exist)
5. ❌ Removed intentionally - Functions deleted (checked: never existed in git history)

---

## Two Solution Approaches

### Solution 1: Implement Missing Functions in FFU.VM Module ⭐ **RECOMMENDED**

**Approach:**
- Create `Set-CaptureFFU` function in FFU.VM module
- Create `Remove-FFUUserShare` function in FFU.VM module
- Implement user and share creation/removal logic
- Export functions from module
- Use existing parameters from BuildFFUVM.ps1

**Implementation Details:**

**Set-CaptureFFU Function:**
```powershell
function Set-CaptureFFU {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Username,

        [Parameter(Mandatory = $true)]
        [string]$ShareName,

        [Parameter(Mandatory = $true)]
        [string]$FFUCaptureLocation,

        [Parameter(Mandatory = $false)]
        [SecureString]$Password
    )

    # 1. Generate secure password if not provided
    # 2. Create local user account
    # 3. Create FFU capture directory if doesn't exist
    # 4. Create SMB share pointing to capture directory
    # 5. Grant user full control to share
    # 6. Log success
}
```

**Remove-FFUUserShare Function:**
```powershell
function Remove-FFUUserShare {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Username,

        [Parameter(Mandatory = $true)]
        [string]$ShareName
    )

    # 1. Remove SMB share if it exists
    # 2. Remove local user account if it exists
    # 3. Log success
}
```

**BuildFFUVM.ps1 Call Site Updates:**
```powershell
# Line 2192 - Pass parameters to Set-CaptureFFU
Set-CaptureFFU -Username $Username -ShareName $ShareName `
               -FFUCaptureLocation $FFUCaptureLocation

# Line 2286 - Pass parameters to Remove-FFUUserShare
Remove-FFUUserShare -Username $Username -ShareName $ShareName
```

**Advantages:**
- ✅ **Fixes the immediate error**: Functions will exist and be callable
- ✅ **Proper modularization**: VM-related functions belong in FFU.VM
- ✅ **Reusable**: Functions can be called from other scripts
- ✅ **Testable**: Can unit test share/user creation separately
- ✅ **Complete implementation**: Implements originally intended functionality
- ✅ **No breaking changes**: Existing builds without `-InstallApps` unaffected

**Disadvantages:**
- ⚠️ Requires Windows admin privileges (Create user, create share)
- ⚠️ Security consideration: Creating user accounts and shares

---

### Solution 2: Remove Function Calls (Stub Implementation)

**Approach:**
- Replace `Set-CaptureFFU` call with inline stub
- Replace `Remove-FFUUserShare` call with inline stub
- Log warning that functionality not implemented
- Document as known limitation

**Implementation:**
```powershell
# BuildFFUVM.ps1 line 2192
#Create ffu user and share to capture FFU to
try {
    WriteLog "WARNING: FFU user and share creation not implemented"
    WriteLog "FFU capture will use current user credentials"
    # TODO: Implement Set-CaptureFFU functionality
}
catch {
    WriteLog "Set-CaptureFFU placeholder failed with error $_"
}

# BuildFFUVM.ps1 line 2286
try {
    WriteLog "WARNING: FFU user and share cleanup not implemented"
    # TODO: Implement Remove-FFUUserShare functionality
}
catch {
    WriteLog "Remove-FFUUserShare placeholder failed with error $_"
}
```

**Advantages:**
- ✅ **Quick fix**: Eliminates error immediately
- ✅ **No new code complexity**: Minimal changes
- ✅ **Documents limitation**: Makes missing functionality explicit

**Disadvantages:**
- ❌ **Doesn't implement intended functionality**: User/share not created
- ❌ **May break FFU capture workflow**: Depends on current user having rights
- ❌ **Technical debt**: Leaves TODO items in code
- ❌ **Incomplete solution**: Doesn't address root problem

---

## Recommended Solution: **Solution 1**

**Rationale:**
1. **Implements intended functionality**: Creates user/share as originally designed
2. **Proper architecture**: Functions belong in FFU.VM module
3. **Complete fix**: Resolves root cause, not just symptom
4. **Testable**: Can validate user/share creation independently
5. **Future-proof**: Enables advanced capture scenarios

Solution 2 is a quick workaround but doesn't solve the actual problem and may cause issues with FFU capture workflows.

---

## Implementation Plan

1. ✅ Analyze root cause (COMPLETE)
2. ⏳ Create `Set-CaptureFFU` function in FFU.VM module:
   - Generate secure password for FFU user
   - Create local user account with password
   - Create FFU capture directory if needed
   - Create SMB share pointing to directory
   - Grant user full control permissions
   - Comprehensive error handling
3. ⏳ Create `Remove-FFUUserShare` function in FFU.VM module:
   - Remove SMB share
   - Remove local user account
   - Graceful handling if resources don't exist
4. ⏳ Update BuildFFUVM.ps1 call sites:
   - Pass required parameters to Set-CaptureFFU
   - Pass required parameters to Remove-FFUUserShare
5. ⏳ Export new functions from FFU.VM module
6. ⏳ Create comprehensive regression test suite:
   - Test user account creation
   - Test SMB share creation
   - Test share permissions
   - Test cleanup (removal)
   - Test error scenarios
7. ⏳ Update documentation

---

## Test Scenarios

### Regression Test Cases

1. **User Creation**
   ```powershell
   Set-CaptureFFU -Username "ffu_user" -ShareName "FFUCaptureShare" -FFUCaptureLocation "C:\FFU"
   $user = Get-LocalUser -Name "ffu_user" -ErrorAction SilentlyContinue
   # Expected: User exists
   ```

2. **Share Creation**
   ```powershell
   Set-CaptureFFU -Username "ffu_user" -ShareName "FFUCaptureShare" -FFUCaptureLocation "C:\FFU"
   $share = Get-SmbShare -Name "FFUCaptureShare" -ErrorAction SilentlyContinue
   # Expected: Share exists and points to C:\FFU
   ```

3. **Share Permissions**
   ```powershell
   Set-CaptureFFU -Username "ffu_user" -ShareName "FFUCaptureShare" -FFUCaptureLocation "C:\FFU"
   $access = Get-SmbShareAccess -Name "FFUCaptureShare" | Where-Object { $_.AccountName -like "*ffu_user" }
   # Expected: User has FullControl
   ```

4. **Cleanup - Remove Share**
   ```powershell
   Set-CaptureFFU -Username "ffu_user" -ShareName "FFUCaptureShare" -FFUCaptureLocation "C:\FFU"
   Remove-FFUUserShare -Username "ffu_user" -ShareName "FFUCaptureShare"
   $share = Get-SmbShare -Name "FFUCaptureShare" -ErrorAction SilentlyContinue
   # Expected: Share does not exist
   ```

5. **Cleanup - Remove User**
   ```powershell
   Set-CaptureFFU -Username "ffu_user" -ShareName "FFUCaptureShare" -FFUCaptureLocation "C:\FFU"
   Remove-FFUUserShare -Username "ffu_user" -ShareName "FFUCaptureShare"
   $user = Get-LocalUser -Name "ffu_user" -ErrorAction SilentlyContinue
   # Expected: User does not exist
   ```

6. **Idempotence - Set Twice**
   ```powershell
   Set-CaptureFFU -Username "ffu_user" -ShareName "FFUCaptureShare" -FFUCaptureLocation "C:\FFU"
   Set-CaptureFFU -Username "ffu_user" -ShareName "FFUCaptureShare" -FFUCaptureLocation "C:\FFU"
   # Expected: Second call succeeds (doesn't error if already exists)
   ```

7. **Error Handling - Missing Directory**
   ```powershell
   Set-CaptureFFU -Username "ffu_user" -ShareName "FFUCaptureShare" -FFUCaptureLocation "Z:\NonExistent"
   # Expected: Creates directory or provides clear error
   ```

---

## Success Criteria

✅ Set-CaptureFFU function creates user and share successfully
✅ Remove-FFUUserShare function cleans up user and share
✅ BuildFFUVM.ps1 executes without "function not recognized" error
✅ FFU builds with `-InstallApps $true` complete successfully
✅ Share permissions allow VM to write FFU files
✅ Cleanup removes all created resources
✅ All regression tests pass
✅ No breaking changes to existing functionality

---

## Related Files

- `C:\claude\FFUBuilder\FFUDevelopment\BuildFFUVM.ps1` (lines 2192, 2286)
- `C:\claude\FFUBuilder\FFUDevelopment\Modules\FFU.VM\FFU.VM.psm1`

---

**Analysis Complete**: 2025-11-23
**Next Step**: Implement Set-CaptureFFU and Remove-FFUUserShare in FFU.VM module
