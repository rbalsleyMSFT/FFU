# Custom Issue: BITS Authentication Error (0x800704DD)

## Issue Summary

**Error Code**: `0x800704DD` (ERROR_NOT_LOGGED_ON)
**Full Error Message**:
```
System.Runtime.InteropServices.COMException (0x800704DD):
The operation being requested was not performed because the user has not logged on to the network.
The specified service does not exist. (0x800704DD)
```

**Severity**: HIGH - Blocks all network downloads
**Impact**: All BITS transfers fail, preventing driver downloads, Windows updates, OneDrive, Defender, and application downloads

## Root Cause Analysis

### Primary Cause: PowerShell Background Job Authentication Context

The FFU Builder launches `BuildFFUVM.ps1` via `Start-Job` from the UI:

**BuildFFUVM_UI.ps1, line 298:**
```powershell
$script:uiState.Data.currentBuildJob = Start-Job -ScriptBlock $cleanupScriptBlock -ArgumentList @($cleanupParams, $PSScriptRoot)
```

**The Problem:**
1. `Start-Job` creates a **new PowerShell process** (separate runspace)
2. This new process runs in the current user context but **without network credentials**
3. BITS (Background Intelligent Transfer Service) requires network authentication
4. When BITS tries to download files, it has **no network logon session**
5. Result: `ERROR_NOT_LOGGED_ON` (0x800704DD)

### Secondary Cause: Missing BITS Credential Parameters

**FFU.Common.Core.psm1, lines 140-184:**
```powershell
function Start-BitsTransferWithRetry {
    param (
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [int]$Retries = 3
    )

    # ...

    Start-BitsTransfer -Source $Source -Destination $Destination -Priority Normal -ErrorAction Stop
    # Missing: -Credential, -Authentication, -ProxyUsage, -ProxyCredential
}
```

The `Start-BitsTransfer` cmdlet is called **without** authentication parameters:
- No `-Credential` parameter (uses current process credentials)
- No `-Authentication` parameter (authentication method)
- No `-UseStoredCredential` flag
- No `-ProxyUsage` or proxy credentials

## Affected Operations

This error affects **every network download** in the FFU Builder:

| Operation | File | Lines | Impact |
|-----------|------|-------|--------|
| Surface driver downloads | BuildFFUVM.ps1 | 923 | No Surface drivers |
| HP driver catalog | BuildFFUVM.ps1 | 992, 1125 | No HP drivers |
| HP driver packages | BuildFFUVM.ps1 | 1167 | No HP drivers |
| Lenovo driver catalog | BuildFFUVM.ps1 | 1312 | No Lenovo drivers |
| Lenovo driver packages | BuildFFUVM.ps1 | 1339, 1394 | No Lenovo drivers |
| Dell driver catalog | BuildFFUVM.ps1 | 1473 | No Dell drivers |
| Dell driver packages | BuildFFUVM.ps1 | 1579 | No Dell drivers |
| Windows ADK downloads | BuildFFUVM.ps1 | 1756 | ADK installation fails |
| Windows PE add-ons | BuildFFUVM.ps1 | 2323, 2332, 2340, 2351 | WinPE creation fails |
| Defender definitions | BuildFFUVM.ps1 | 5403 | No Defender updates |
| OneDrive installer | BuildFFUVM.ps1 | 5510 | No OneDrive |
| Windows updates | BuildFFUVM.ps1 | 5812 | No cumulative updates |

**Total**: 20+ download operations affected

## Reproduction Steps

1. Launch `BuildFFUVM_UI.ps1` as Administrator
2. Configure any build with driver downloads enabled
3. Click "Build FFU"
4. UI starts background job via `Start-Job`
5. Background job attempts BITS transfer
6. **Error**: `0x800704DD` appears in log
7. Build fails at first network download

## Why This Happens

### PowerShell Job Context Isolation

```
User Interactive Session (has network credentials)
    └─ BuildFFUVM_UI.ps1 (Administrator)
        └─ Start-Job (creates new process)
            └─ BuildFFUVM.ps1 (NO network credentials)
                └─ Start-BitsTransfer (fails - no network logon)
```

### BITS Authentication Requirements

BITS requires one of:
1. **Interactive user logon** - User logged into Windows with network credentials
2. **Explicit credentials** - Passed via `-Credential` parameter
3. **Stored credentials** - Credential Manager credentials via `-UseStoredCredential`
4. **System context** with network service privileges (not applicable here)

PowerShell background jobs created with `Start-Job`:
- ✅ Have local user context
- ✅ Can access local files
- ❌ Do NOT have network authentication token
- ❌ Cannot access network shares
- ❌ BITS transfers fail with 0x800704DD

## Solution Design

### Option 1: Use ThreadJob Instead of Start-Job (RECOMMENDED)

**Advantages:**
- Uses threads in current process (not separate process)
- Inherits all credentials from parent session
- No changes to BITS code required
- Fastest to implement

**Implementation:**
```powershell
# Install ThreadJob module if not present
if (-not (Get-Module -ListAvailable -Name ThreadJob)) {
    Install-Module -Name ThreadJob -Force -Scope CurrentUser
}

# Replace Start-Job with Start-ThreadJob
$script:uiState.Data.currentBuildJob = Start-ThreadJob -ScriptBlock $cleanupScriptBlock -ArgumentList @($cleanupParams, $PSScriptRoot)
```

**Change Required:**
- BuildFFUVM_UI.ps1, line 298 (and other Start-Job calls)

**Risk:** Low - ThreadJob is well-tested Microsoft module

---

### Option 2: Pass Explicit Credentials to BITS

**Advantages:**
- More control over authentication
- Works with proxy authentication
- Can use different credentials if needed

**Implementation:**
```powershell
function Start-BitsTransferWithRetry {
    param (
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [int]$Retries = 3,
        [PSCredential]$Credential = $null,
        [switch]$UseDefaultCredentials
    )

    $bitsParams = @{
        Source      = $Source
        Destination = $Destination
        Priority    = 'Normal'
        ErrorAction = 'Stop'
    }

    if ($Credential) {
        $bitsParams['Credential'] = $Credential
        $bitsParams['Authentication'] = 'Negotiate'  # or 'NTLM', 'Basic', etc.
    }
    elseif ($UseDefaultCredentials) {
        # Try to use the credentials of the current user
        # This works if the parent session has network credentials
        try {
            $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
            if ($currentUser.AuthenticationType -eq 'Kerberos' -or $currentUser.AuthenticationType -eq 'NTLM') {
                $bitsParams['Authentication'] = $currentUser.AuthenticationType
            }
        }
        catch {
            WriteLog "Could not determine current authentication type: $($_.Exception.Message)"
        }
    }

    while ($attempt -lt $Retries) {
        try {
            Start-BitsTransfer @bitsParams
            WriteLog "Successfully transferred $Source to $Destination."
            return
        }
        catch {
            $lastError = $_
            $attempt++
            WriteLog "Attempt $attempt of $Retries failed to download $Source. Error: $($lastError.Exception.Message)."

            # If authentication error, don't retry
            if ($lastError.Exception.HResult -eq 0x800704DD) {
                WriteLog "BITS authentication error detected. Check network credentials and authentication context."
                break
            }

            Start-Sleep -Seconds (1 * $attempt)
        }
    }

    WriteLog "Failed to download $Source after $Retries attempts. Last Error: $($lastError.Exception.Message)"
    throw $lastError
}
```

**Change Required:**
- FFU.Common.Core.psm1, lines 140-184

**Risk:** Medium - Requires credential management

---

### Option 3: Run Background Script Directly (Not in Job)

**Advantages:**
- No job isolation issues
- Full credential inheritance

**Disadvantages:**
- UI freezes during build
- No easy cancellation
- Poor user experience

**NOT RECOMMENDED** for this project.

---

### Option 4: Use Invoke-WebRequest with -UseDefaultCredentials

**Advantages:**
- Simpler than BITS for small files
- Built-in credential support

**Disadvantages:**
- No resume capability (BITS advantage lost)
- No bandwidth throttling
- Larger memory footprint for big files

**Implementation:**
```powershell
function Start-WebRequestWithRetry {
    param (
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [int]$Retries = 3
    )

    while ($attempt -lt $Retries) {
        try {
            Invoke-WebRequest -Uri $Source -OutFile $Destination `
                -UseDefaultCredentials -UseBasicParsing -ErrorAction Stop
            return
        }
        catch {
            $attempt++
            Start-Sleep -Seconds (1 * $attempt)
        }
    }
}
```

**Risk:** Medium - Different behavior than BITS

---

## Recommended Solution: Hybrid Approach

**Phase 1: Immediate Fix (Use ThreadJob)**
- Replace `Start-Job` with `Start-ThreadJob` in BuildFFUVM_UI.ps1
- Solves authentication issue immediately
- No changes to BITS code required
- Low risk, high reward

**Phase 2: Enhanced BITS (Add Credential Support)**
- Update `Start-BitsTransferWithRetry` to accept credentials
- Add `-UseDefaultCredentials` switch
- Detect and report authentication errors clearly
- Aligns with Issue #327 (proxy support)

**Phase 3: Comprehensive Network Configuration**
- Implement `FFUNetworkConfiguration` class (from DESIGN.md)
- Unified credential and proxy handling
- Pre-flight network authentication validation

## Implementation Priority

1. **CRITICAL (Immediate)**: Switch to ThreadJob in BuildFFUVM_UI.ps1
2. **HIGH (This Week)**: Add credential parameters to Start-BitsTransferWithRetry
3. **MEDIUM (Next Week)**: Implement FFUNetworkConfiguration with proxy support
4. **LOW (Future)**: Add network diagnostics and pre-flight authentication testing

## Testing Plan

### Test 1: ThreadJob Credential Inheritance
```powershell
# Verify ThreadJob inherits network credentials
Start-ThreadJob -ScriptBlock {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    Write-Output "Auth Type: $($identity.AuthenticationType)"
    Write-Output "Is Authenticated: $($identity.IsAuthenticated)"

    # Test BITS transfer
    Start-BitsTransfer -Source "https://download.microsoft.com/download/test.txt" `
        -Destination "$env:TEMP\test.txt" -ErrorAction Stop
} | Receive-Job -Wait -AutoRemoveJob
```

### Test 2: BITS with Explicit Credentials
```powershell
$cred = Get-Credential
Start-BitsTransferWithRetry -Source "https://example.com/file.zip" `
    -Destination "C:\temp\file.zip" `
    -Credential $cred
```

### Test 3: Network Authentication Validation
```powershell
# Check if current session has network authentication
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
Write-Host "User: $($currentUser.Name)"
Write-Host "Auth Type: $($currentUser.AuthenticationType)"
Write-Host "Is System: $($currentUser.IsSystem)"
Write-Host "Is Authenticated: $($currentUser.IsAuthenticated)"
```

## Related Issues

- **Issue #327**: Proxy support for corporate networks
  - Same root cause: Missing network configuration in BITS
  - Solution: Unified network configuration class

- **DESIGN.md Section 3.1.3**: FFUNetworkConfiguration
  - Comprehensive proxy and credential handling
  - Detection from Windows settings
  - Manual override capability

## Success Criteria

✅ All BITS transfers complete without 0x800704DD error
✅ Driver downloads work in background job context
✅ No user interaction required for authentication
✅ Clear error messages if authentication fails
✅ Backward compatible with existing configurations
✅ Works with corporate proxies (after Issue #327 fix)

## Additional Notes

### Why Not Use -UseStoredCredential?

The `-UseStoredCredential` parameter requires credentials to be pre-stored in Windows Credential Manager for the target URL. This is:
- Not user-friendly (requires manual setup)
- Not portable across machines
- Requires credential management UI
- Doesn't solve the root cause (job isolation)

### Why ThreadJob Is Better Than Start-Job

| Feature | Start-Job | ThreadJob |
|---------|-----------|-----------|
| Execution | Separate process | Thread in current process |
| Credential inheritance | ❌ No | ✅ Yes |
| Startup time | Slow (~1-2s) | Fast (<100ms) |
| Memory overhead | High (~50MB) | Low (~5MB) |
| Variable sharing | Difficult (serialization) | Easy (shared runspace) |
| Network context | Isolated | Inherited |

### Microsoft Documentation References

- **Start-ThreadJob**: https://docs.microsoft.com/en-us/powershell/module/threadjob/start-threadjob
- **BITS Cmdlets**: https://docs.microsoft.com/en-us/powershell/module/bitstransfer/
- **Error 0x800704DD**: https://docs.microsoft.com/en-us/windows/win32/debug/system-error-codes--1300-1699-
- **PowerShell Jobs**: https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_jobs

---

**Created**: 2025-10-24
**Author**: FFU Builder Development Team
**Status**: Analysis Complete, Ready for Implementation
