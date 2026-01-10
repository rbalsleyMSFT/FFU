# Implementation Plan: BuildFFUVM.ps1 Hypervisor Integration

**Created:** 2026-01-08
**Status:** Pending Implementation
**Priority:** High - Blocks VMware Workstation Pro usage

---

## Problem Summary

The `BuildFFUVM.ps1` script correctly loads `HypervisorType` from the config file and initializes `$script:HypervisorProvider` (line 886), but the actual VM operations still call Hyper-V-specific functions from `FFU.VM` module instead of using the hypervisor abstraction layer.

**Root Cause:** The hypervisor abstraction layer (`FFU.Hypervisor` module) was implemented, but `BuildFFUVM.ps1` was never updated to use it.

**Symptom:** User selects "VMware" in UI, but build uses Hyper-V anyway.

---

## Files Affected

| File | Changes Required |
|------|------------------|
| `BuildFFUVM.ps1` | VM creation, state polling, cleanup calls |
| `Modules/FFU.VM/FFU.VM.psm1` | Extract user/share cleanup to separate function |
| `Tests/Unit/FFU.Hypervisor.Tests.ps1` | Add integration scenario tests |

---

## Changes Required

### 1. VM Creation (Line 3450-3452)

**Current Code:**
```powershell
$FFUVM = New-FFUVM -VMName $VMName -VMPath $VMPath -Memory $memory `
                   -VHDXPath $VHDXPath -Processors $processors -AppsISO $AppsISO
```

**New Code:**
```powershell
# Create VMConfiguration for hypervisor-agnostic VM creation
$vmConfig = [VMConfiguration]::new()
$vmConfig.Name = $VMName
$vmConfig.Path = $VMPath
$vmConfig.MemoryBytes = $memory
$vmConfig.ProcessorCount = $processors
$vmConfig.VirtualDiskPath = $VHDXPath
$vmConfig.ISOPath = $AppsISO
$vmConfig.DiskFormat = 'VHD'  # Both providers support VHD
$vmConfig.EnableTPM = $true
$vmConfig.EnableSecureBoot = $true
$vmConfig.Generation = 2

# Create VM using the initialized hypervisor provider
$FFUVM = $script:HypervisorProvider.CreateVM($vmConfig)
```

**Impact:** The `$FFUVM` variable changes from a Hyper-V `VirtualMachine` object to a `VMInfo` object.

---

### 2. VM State Polling (Line 3647-3650)

**Current Code:**
```powershell
do {
    $FFUVM = Get-VM -Name $FFUVM.Name
    Start-Sleep -Seconds 5
    WriteLog 'Waiting for VM to shutdown'
} while ($FFUVM.State -ne 'Off')
```

**New Code:**
```powershell
do {
    $vmState = $script:HypervisorProvider.GetVMState($FFUVM)
    Start-Sleep -Seconds 5
    WriteLog 'Waiting for VM to shutdown'
} while ($vmState -ne [VMState]::Off)
```

**Impact:** Uses `VMState` enum instead of Hyper-V string state.

---

### 3. VM Cleanup (Lines 3461, 3534, 3585, 3686, 3691, 3707, 3729)

**Current Code (example):**
```powershell
Remove-FFUVM -VMName $VMName -VMPath $VMPath -InstallApps $InstallApps `
             -VhdxDisk $vhdxDisk -FFUDevelopmentPath $FFUDevelopmentPath `
             -Username $Username -ShareName $ShareName
```

**New Code:**
```powershell
# Remove VM via hypervisor provider
if ($null -ne $FFUVM) {
    $script:HypervisorProvider.RemoveVM($FFUVM, $true)  # $true = remove disks
}

# Handle non-VM cleanup separately (user account, share, etc.)
Remove-FFUUserAndShare -Username $Username -ShareName $ShareName -FFUDevelopmentPath $FFUDevelopmentPath
```

**Impact:** Need to extract user/share cleanup from `Remove-FFUVM` into a separate function.

---

### 4. Skip Hyper-V-Specific Validations for VMware (Lines 551-594, 1757-1764)

**Status:** Already correct - code uses `if ($HypervisorType -eq 'HyperV')` guards.

---

### 5. Environment Cleanup (Lines 1508, 1841)

**Current Code:**
```powershell
Get-FFUEnvironment -FFUDevelopmentPath $FFUDevelopmentPath `
                   -CleanupCurrentRunDownloads $CleanupCurrentRunDownloads ...
```

**New Code:** The `Get-FFUEnvironment` function needs to be made hypervisor-aware. Options:
- A) Update `Get-FFUEnvironment` to accept a provider parameter
- B) Create a wrapper that uses `$script:HypervisorProvider`

---

## Additional Considerations

### A. VHDX vs VHD Disk Format
- Hyper-V uses VHDX (line 2954: `$VHDXPath = Join-Path $VMPath ($VMName + '.vhdx')`)
- VMware uses VHD (diskpart-based)
- Need to conditionally set disk path extension based on hypervisor type:

```powershell
$diskExtension = if ($HypervisorType -eq 'HyperV') { '.vhdx' } else { '.vhd' }
$VHDXPath = Join-Path $VMPath ($VMName + $diskExtension)
```

### B. VM Switch vs Network Type
- Hyper-V requires `$VMSwitchName`
- VMware uses bridged/NAT networking (no switch parameter)
- Already handled in validations, but `New-FFUVM` parameters need updating

### C. IP Address Retrieval
The `Set-CaptureFFU` function (around line 3490) may use `Get-VM` or similar to get the VM IP. This needs to use:
```powershell
$vmIP = $script:HypervisorProvider.GetVMIPAddress($FFUVM)
```

### D. HyperVProvider CreateVM Implementation
Need to verify `HyperVProvider.CreateVM()` handles:
- VM switch attachment
- VHDX attachment
- ISO attachment
- TPM configuration
- Secure Boot configuration

If not, these need to be added to match `New-FFUVM` functionality.

---

## Estimated Impact

| Area | Files Changed | Risk Level |
|------|---------------|------------|
| VM Creation | BuildFFUVM.ps1 | Medium |
| VM State Polling | BuildFFUVM.ps1 | Low |
| VM Cleanup | BuildFFUVM.ps1, FFU.VM.psm1 | Medium |
| Environment Cleanup | FFU.VM.psm1 | Medium |
| Disk Path Handling | BuildFFUVM.ps1 | Low |

---

## Implementation Order

1. **Phase 1:** Update disk path handling (VHDX vs VHD based on hypervisor)
2. **Phase 2:** Replace `New-FFUVM` with `$script:HypervisorProvider.CreateVM()`
3. **Phase 3:** Replace `Get-VM` state polling with `$script:HypervisorProvider.GetVMState()`
4. **Phase 4:** Extract user/share cleanup from `Remove-FFUVM`
5. **Phase 5:** Replace `Remove-FFUVM` calls with provider-based cleanup
6. **Phase 6:** Update `Get-FFUEnvironment` to be hypervisor-aware
7. **Phase 7:** Run full test suite

---

## Testing Plan

1. **Unit Tests:** Update/add tests in `FFU.Hypervisor.Tests.ps1` for integration scenarios
2. **Integration Test - VMware:** Run full build with VMware selected
3. **Integration Test - Hyper-V:** Run full build with Hyper-V to ensure no regression
4. **Cleanup Test:** Verify VM cleanup works for both hypervisors

---

## Version Updates Required

After implementation:
- `FFU.Hypervisor` module version bump (if changes needed)
- `FFU.VM` module version bump (for cleanup extraction)
- Main FFU Builder version bump in `version.json`

---

## Reference: Key Line Numbers in BuildFFUVM.ps1

| Line | Current Code | Purpose |
|------|--------------|---------|
| 520 | `[string]$HypervisorType = 'HyperV'` | Parameter definition |
| 695-729 | Config file loading | Loads HypervisorType from JSON |
| 825-888 | Hypervisor initialization | Creates `$script:HypervisorProvider` |
| 2954 | `$VHDXPath = Join-Path...` | Disk path creation |
| 3450 | `New-FFUVM` | VM creation |
| 3647 | `Get-VM -Name` | VM state polling |
| 3461, 3534, 3585, 3686, 3691, 3707, 3729 | `Remove-FFUVM` | Cleanup calls |

---

## Reference: VMInfo Object Properties

The `VMInfo` object returned by `CreateVM()` has these properties:
- `Name` - VM name
- `Id` - Unique identifier
- `HypervisorType` - 'HyperV' or 'VMware'
- `State` - VMState enum (Off, Running, Paused, etc.)
- `IPAddress` - VM IP address
- `VirtualDiskPath` - Path to virtual disk
- `ConfigurationPath` - Path to VM config (VMX for VMware)
- `VMwareId` - VMware-specific ID (for vmrest API)
- `VMXPath` - Path to VMX file (VMware only)

---

## Reference: VMState Enum Values

```powershell
enum VMState {
    Unknown = 0
    Off = 1
    Running = 2
    Paused = 3
    Saved = 4
    Starting = 5
    Stopping = 6
    Saving = 7
    Restoring = 8
    Suspended = 9
}
```
