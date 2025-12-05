# PowerShell Version Compatibility Error - Root Cause Analysis

**Date**: 2025-11-24
**Issue**: `Could not load type 'Microsoft.PowerShell.Telemetry.Internal.TelemetryAPI' from assembly 'System.Management.Automation, Version=7.5.0.500'`
**Status**: ⚠️ **CRITICAL - BUILD BLOCKER**

---

## Error Analysis

### Error Message
```
ERROR: Failed to set up FFU capture user and share: Could not load type 'Microsoft.PowerShell.Telemetry.Internal.TelemetryAPI' from assembly 'System.Management.Automation, Version=7.5.0.500, Culture=neutral, PublicKeyToken=31bf3856ad364e35'.
```

### Log Context
```
11/24/2025 7:55:49 AM Verifying Set-CaptureFFU function availability...
11/24/2025 7:55:49 AM WARNING: Set-CaptureFFU not found in current session. Attempting module reload...
11/24/2025 7:55:49 AM Importing FFU.VM module from: C:\FFUDevelopment\Modules\FFU.VM\FFU.VM.psm1
11/24/2025 7:55:49 AM Set-CaptureFFU successfully loaded after module reload
11/24/2025 7:55:49 AM Setting up FFU capture user and share
11/24/2025 7:55:49 AM Generating secure password for user ffu_user
11/24/2025 7:55:49 AM Creating local user account: ffu_user
11/24/2025 7:55:49 AM ERROR: Failed to set up FFU capture user and share: Could not load type...
```

**Key Observations:**
1. ✅ Diagnostic verification worked - detected missing function
2. ✅ Module reload succeeded - function loaded successfully
3. ✅ Set-CaptureFFU started executing
4. ✅ Password generation succeeded
5. ❌ **FAILED at `New-LocalUser` cmdlet call (line 515 in FFU.VM.psm1)**

### Assembly Version Evidence

**Critical Clue**: `System.Management.Automation, Version=7.5.0.500`
- This is **PowerShell 7.5**, NOT Windows PowerShell 5.1
- Windows PowerShell 5.1 uses `System.Management.Automation, Version=3.0.0.0`
- User is running BuildFFUVM.ps1 in PowerShell 7.x

---

## Root Cause

### Primary Cause: PowerShell 7.x Compatibility Issue

**The TelemetryAPI Error is a known PowerShell 7 bug with `New-LocalUser` cmdlet:**

1. **PowerShell 7.x has breaking changes** in Windows management cmdlets
2. **`New-LocalUser` cmdlet** specifically has known issues in PowerShell 7.0-7.5
3. **TelemetryAPI type loading failure** occurs when:
   - Running PowerShell 7.x on Windows
   - Using Microsoft.PowerShell.LocalAccounts module
   - Calling New-LocalUser, Set-LocalUser, or related cmdlets
4. **Assembly version mismatch** between PowerShell 7's System.Management.Automation and legacy Windows modules

### Technical Details

**Why `New-LocalUser` fails in PowerShell 7:**
- Microsoft.PowerShell.LocalAccounts module was designed for Windows PowerShell 5.1
- PowerShell 7 uses .NET Core/.NET 5+ runtime
- Windows PowerShell 5.1 uses .NET Framework runtime
- The LocalAccounts module has hardcoded dependencies on .NET Framework types
- TelemetryAPI is an internal PowerShell telemetry mechanism that doesn't exist in PowerShell 7's architecture

**Reference:**
- GitHub Issue: https://github.com/PowerShell/PowerShell/issues/10600
- "New-LocalUser fails in PowerShell 7 with TelemetryAPI error"

### Secondary Causes (Contributing Factors)

**Why user is running in PowerShell 7:**
1. PowerShell 7 installed at `C:\Program Files\PowerShell\7\pwsh.exe`
2. User may have launched BuildFFUVM.ps1 with `pwsh.exe` instead of `powershell.exe`
3. BuildFFUVM_UI.ps1 may be launching jobs in PowerShell 7
4. File association for .ps1 may be set to PowerShell 7

**Why script didn't fail immediately:**
- No `#Requires -PSEdition Desktop` statement in BuildFFUVM.ps1
- No PowerShell version check at script startup
- Most cmdlets (Hyper-V, DISM, file operations) work in both versions
- Error only manifests when calling Windows-specific management cmdlets

---

## Impact Assessment

### Affected Operations
- ❌ **Creating local user accounts** (New-LocalUser)
- ❌ **Creating SMB shares** (New-SmbShare) - may also fail
- ❌ **Managing local groups** (Add-LocalGroupMember) - may also fail
- ❌ **FFU builds with `-InstallApps $true`** - completely broken

### Working Operations
- ✅ Most Hyper-V cmdlets (Get-VM, New-VM, Start-VM, etc.)
- ✅ Most DISM operations
- ✅ File system operations
- ✅ Basic FFU builds without `-InstallApps`

### Severity
**CRITICAL**: FFU builds with application installation cannot complete. User creation is a required step for FFU VM-based capture.

---

## Possible Reasons Why We're Getting This Error

### 1. ⭐ Running in PowerShell 7 Instead of Windows PowerShell 5.1 (MOST LIKELY)

**Evidence:**
- Assembly version 7.5.0.500 in error message
- PowerShell 7 installed on system (`C:\Program Files\PowerShell\7\pwsh.exe`)
- TelemetryAPI error is signature PowerShell 7 compatibility issue

**How it happens:**
- User launches script with `pwsh.exe BuildFFUVM.ps1`
- Or `.ps1` file association changed to PowerShell 7
- Or BuildFFUVM_UI.ps1 uses `pwsh.exe` for background jobs

---

### 2. PowerShell 7 Launched by BuildFFUVM_UI.ps1

**Evidence:**
- BuildFFUVM_UI.ps1 creates background jobs to run BuildFFUVM.ps1
- Job creation may default to PowerShell 7 if it's the default shell

**How to verify:**
```powershell
# Check what PowerShell is used for jobs
$job = Start-Job { $PSVersionTable }
$job | Receive-Job
```

---

### 3. Mixed PowerShell Environment

**Evidence:**
- Both PowerShell 5.1 (built into Windows) and 7.5 installed
- PATH may prioritize PowerShell 7

**How it happens:**
- Windows 10/11 includes PowerShell 5.1 (powershell.exe)
- User installed PowerShell 7 (pwsh.exe)
- System may auto-launch .ps1 files in PowerShell 7

---

### 4. File Association Changed

**Evidence:**
- Right-click .ps1 file → "Open with" may be set to PowerShell 7

**How to check:**
```cmd
assoc .ps1
ftype Microsoft.PowerShellScript.1
```

---

### 5. No PowerShell Version Enforcement

**Evidence:**
- BuildFFUVM.ps1 lacks `#Requires -PSEdition Desktop` directive
- No runtime check for PowerShell version

**Current state:**
- Script will run in ANY PowerShell version
- Fails late (when hitting incompatible cmdlets)

---

## Two Solution Approaches

---

## Solution 1: ⭐ Enforce Windows PowerShell 5.1 Execution (RECOMMENDED)

### Approach
Force BuildFFUVM.ps1 to run ONLY in Windows PowerShell 5.1 (Desktop Edition).

### Implementation Strategy

#### Option A: #Requires Directive (Simplest)
Add to top of BuildFFUVM.ps1:
```powershell
#Requires -PSEdition Desktop
#Requires -Version 5.1
```

**Behavior:**
- Script immediately fails if run in PowerShell 7
- Error message: "This script requires PowerShell Desktop edition"
- User must manually re-run in Windows PowerShell

**Pros:**
✅ Simple - one line of code
✅ Clear error message
✅ PowerShell enforces it automatically

**Cons:**
⚠️ User must manually re-launch script
⚠️ No automatic fix

---

#### Option B: Auto-Relaunch Logic (Best UX)
Detect PowerShell version and auto-relaunch in Windows PowerShell 5.1:

```powershell
# Auto-relaunch in Windows PowerShell 5.1 if running in PowerShell 7
if ($PSVersionTable.PSEdition -eq 'Core') {
    Write-Host "Detected PowerShell $($PSVersionTable.PSVersion) (Core Edition)"
    Write-Host "FFUBuilder requires Windows PowerShell 5.1 for compatibility with Windows management cmdlets"
    Write-Host "Relaunching in Windows PowerShell 5.1..."

    $psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

    if (-not (Test-Path $psExe)) {
        Write-Error "Windows PowerShell 5.1 not found at: $psExe"
        Write-Error "Please install Windows PowerShell 5.1 (included with Windows 10/11)"
        exit 1
    }

    # Build argument list
    $scriptPath = $MyInvocation.MyCommand.Path
    $arguments = @(
        '-NoProfile'
        '-ExecutionPolicy', 'Bypass'
        '-File', "`"$scriptPath`""
    )

    # Pass all current script parameters
    foreach ($key in $PSBoundParameters.Keys) {
        $value = $PSBoundParameters[$key]
        if ($value -is [bool]) {
            $arguments += "-$key `$$value"
        }
        elseif ($value -is [string]) {
            $arguments += "-$key `"$value`""
        }
        else {
            $arguments += "-$key $value"
        }
    }

    # Relaunch in Windows PowerShell 5.1
    & $psExe @arguments
    exit $LASTEXITCODE
}

# Verify we're now in Windows PowerShell 5.1
if ($PSVersionTable.PSEdition -ne 'Desktop') {
    Write-Error "FATAL: Script must run in Windows PowerShell 5.1 (Desktop Edition)"
    Write-Error "Current edition: $($PSVersionTable.PSEdition)"
    exit 1
}
```

**Behavior:**
- Detects PowerShell 7
- Automatically relaunches script in Windows PowerShell 5.1
- Preserves all parameters
- Seamless user experience

**Pros:**
✅ Automatic - no user intervention
✅ Preserves all script parameters
✅ Clear messaging
✅ Best user experience

**Cons:**
⚠️ Slightly more complex code
⚠️ Creates new process (minor overhead)

---

#### Option C: Fix BuildFFUVM_UI.ps1 Job Launcher
Ensure UI always launches jobs in Windows PowerShell 5.1:

```powershell
# In BuildFFUVM_UI.ps1, when creating background job:
$psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

$job = Start-Job -ScriptBlock {
    param($scriptPath, $params)
    & $scriptPath @params
} -ArgumentList $buildScriptPath, $buildParams -PSVersion 5.1
```

**Pros:**
✅ Fixes UI-launched builds
✅ No changes to BuildFFUVM.ps1 needed

**Cons:**
⚠️ Doesn't fix direct script execution
⚠️ User can still run BuildFFUVM.ps1 manually in PowerShell 7

---

### Advantages of Solution 1
✅ **Most compatible** - Windows management cmdlets designed for 5.1
✅ **No code rewrites** - Keep using New-LocalUser, New-SmbShare, etc.
✅ **Well-tested** - FFU project designed for Windows PowerShell 5.1
✅ **Fixes all compatibility issues** - Hyper-V, DISM, SMB all work perfectly
✅ **Future-proof** - Windows PowerShell 5.1 built into Windows 10/11 (not going away)
✅ **Clear error messages** - Users understand the requirement

### Disadvantages of Solution 1
⚠️ Requires Windows PowerShell 5.1 (but it's included in Windows 10/11)
⚠️ PowerShell 7 users must switch editions

---

## Solution 2: Replace Cmdlets with .NET APIs (Cross-Version Compatibility)

### Approach
Replace PowerShell cmdlets with direct .NET/WMI calls that work in both PowerShell 5.1 and 7.x.

### Implementation

#### Replace New-LocalUser with DirectoryServices API

```powershell
function New-LocalUserAccount {
    param(
        [string]$Username,
        [SecureString]$Password,
        [string]$FullName,
        [string]$Description
    )

    try {
        # Convert SecureString to plain text (required for PrincipalContext)
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
        $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

        # Create user via DirectoryServices
        Add-Type -AssemblyName System.DirectoryServices.AccountManagement

        $context = [System.DirectoryServices.AccountManagement.PrincipalContext]::new(
            [System.DirectoryServices.AccountManagement.ContextType]::Machine
        )

        $user = [System.DirectoryServices.AccountManagement.UserPrincipal]::new($context)
        $user.Name = $Username
        $user.SetPassword($plainPassword)
        $user.DisplayName = $FullName
        $user.Description = $Description
        $user.UserCannotChangePassword = $false
        $user.PasswordNeverExpires = $true
        $user.Save()

        $context.Dispose()

        # Clear password from memory
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)

        WriteLog "User account $Username created successfully via .NET API"
    }
    catch {
        WriteLog "ERROR: Failed to create user account via .NET API: $_"
        throw
    }
}
```

#### Replace Get-LocalUser with DirectoryServices API

```powershell
function Get-LocalUserAccount {
    param([string]$Username)

    try {
        Add-Type -AssemblyName System.DirectoryServices.AccountManagement

        $context = [System.DirectoryServices.AccountManagement.PrincipalContext]::new(
            [System.DirectoryServices.AccountManagement.ContextType]::Machine
        )

        $user = [System.DirectoryServices.AccountManagement.UserPrincipal]::FindByIdentity(
            $context,
            [System.DirectoryServices.AccountManagement.IdentityType]::SamAccountName,
            $Username
        )

        $context.Dispose()
        return $user
    }
    catch {
        return $null
    }
}
```

#### Replace New-SmbShare and Grant-SmbShareAccess with WMI

```powershell
function New-SmbShareWMI {
    param(
        [string]$Name,
        [string]$Path,
        [string]$Description
    )

    try {
        $shares = Get-CimInstance -ClassName Win32_Share -Filter "Name='$Name'"
        if ($shares) {
            WriteLog "Share $Name already exists"
            return
        }

        $shareClass = [wmiclass]"Win32_Share"
        $result = $shareClass.Create($Path, $Name, 0, $null, $Description)

        if ($result.ReturnValue -eq 0) {
            WriteLog "SMB share $Name created successfully via WMI"
        }
        else {
            throw "WMI Create returned error code: $($result.ReturnValue)"
        }
    }
    catch {
        WriteLog "ERROR: Failed to create SMB share via WMI: $_"
        throw
    }
}

function Grant-SmbShareAccessWMI {
    param(
        [string]$ShareName,
        [string]$AccountName,
        [string]$AccessRight = 'Full'
    )

    try {
        # Use icacls.exe to grant NTFS permissions
        $sharePath = (Get-SmbShare -Name $ShareName -ErrorAction Stop).Path

        $accessMask = switch ($AccessRight) {
            'Full'   { '(OI)(CI)F' }
            'Change' { '(OI)(CI)C' }
            'Read'   { '(OI)(CI)R' }
        }

        $result = icacls.exe $sharePath /grant "${AccountName}:${accessMask}"

        if ($LASTEXITCODE -eq 0) {
            WriteLog "Granted $AccessRight access to $AccountName on share $ShareName"
        }
        else {
            throw "icacls returned exit code: $LASTEXITCODE"
        }
    }
    catch {
        WriteLog "ERROR: Failed to grant share permissions: $_"
        throw
    }
}
```

### Update Set-CaptureFFU to use .NET APIs

```powershell
# Replace lines 508-516 in FFU.VM.psm1
$existingUser = Get-LocalUserAccount -Username $Username

if ($existingUser) {
    WriteLog "User $Username already exists, skipping user creation"
    $existingUser.Dispose()
}
else {
    WriteLog "Creating local user account: $Username"
    New-LocalUserAccount -Username $Username -Password $Password `
                        -FullName "FFU Capture User" `
                        -Description "User account for FFU capture operations"
    WriteLog "User account $Username created successfully"
}
```

### Advantages of Solution 2
✅ Works in both PowerShell 5.1 and 7.x
✅ No PowerShell version requirement
✅ More control over operations
✅ No dependency on cmdlets that may be deprecated

### Disadvantages of Solution 2
⚠️ Much more complex code
⚠️ Requires extensive testing
⚠️ Less readable than cmdlets
⚠️ Password handling more complex (SecureString → plain text conversion)
⚠️ WMI/CIM methods more error-prone
⚠️ Need to handle error codes manually
⚠️ May introduce security risks (plain text passwords in memory)

---

## Recommended Solution: **Solution 1 - Option B (Auto-Relaunch)**

### Rationale

1. **Simpler and safer** - Keep using well-tested PowerShell cmdlets
2. **Better UX** - Auto-relaunch is seamless for users
3. **Less risky** - No complex .NET code that could introduce bugs
4. **Maintainable** - Cmdlet-based code is easier to read and maintain
5. **FFU project designed for Windows PowerShell 5.1** - Stay with intended platform
6. **Windows 10/11 include PowerShell 5.1** - No additional installation required
7. **Fixes ALL compatibility issues** - Not just New-LocalUser, but any future cmdlet issues

### Why Not Solution 2?

- Much more complex implementation
- Higher risk of introducing bugs
- Password security concerns (SecureString → plain text)
- Less maintainable code
- Doesn't solve root cause (wrong PowerShell version)

---

## Implementation Plan

### Step 1: Add Auto-Relaunch Logic to BuildFFUVM.ps1
- Add PowerShell edition detection at script start
- Implement auto-relaunch in Windows PowerShell 5.1
- Preserve all script parameters during relaunch
- Add clear logging messages

### Step 2: Fix BuildFFUVM_UI.ps1 Job Launcher
- Ensure background jobs use Windows PowerShell 5.1
- Use explicit path to powershell.exe
- Add PowerShell version logging

### Step 3: Add PowerShell Version Logging
- Log PowerShell version at script start
- Log edition (Desktop vs Core)
- Helps troubleshooting

### Step 4: Create Tests
- Test auto-relaunch from PowerShell 7
- Test parameter preservation during relaunch
- Test error handling if Windows PowerShell not found
- Test UI-launched jobs use correct PowerShell version

### Step 5: Update Documentation
- Document PowerShell 5.1 requirement in README
- Update CLAUDE.md with PowerShell requirements
- Add troubleshooting section for PowerShell version issues

---

## Success Criteria

✅ BuildFFUVM.ps1 runs in Windows PowerShell 5.1
✅ Auto-relaunch works from PowerShell 7
✅ All parameters preserved during relaunch
✅ New-LocalUser succeeds without TelemetryAPI error
✅ FFU builds with -InstallApps complete successfully
✅ UI-launched jobs use Windows PowerShell 5.1
✅ Clear error if Windows PowerShell 5.1 not available
✅ All tests pass

---

## Testing Scenarios

### Scenario 1: Direct Execution in PowerShell 7
```powershell
pwsh.exe -File BuildFFUVM.ps1 -InstallApps $true
```
**Expected:** Auto-relaunches in Windows PowerShell 5.1, build succeeds

### Scenario 2: Direct Execution in PowerShell 5.1
```powershell
powershell.exe -File BuildFFUVM.ps1 -InstallApps $true
```
**Expected:** Runs directly, no relaunch, build succeeds

### Scenario 3: UI-Launched Build
```powershell
.\BuildFFUVM_UI.ps1
# Click "Start Build" with -InstallApps enabled
```
**Expected:** Background job runs in PowerShell 5.1, build succeeds

### Scenario 4: Parameter Preservation
```powershell
pwsh.exe -File BuildFFUVM.ps1 -InstallApps $true -WindowsRelease "11" -OEM "Dell" -Model "Latitude 7490"
```
**Expected:** All parameters passed to relaunched Windows PowerShell 5.1

---

**Analysis Complete**: 2025-11-24
**Next Step**: Implement Solution 1 - Option B (Auto-Relaunch Logic)
