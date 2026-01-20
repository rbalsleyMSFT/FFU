# Phase 12: VHDX Drive Letter Stability - Research

**Researched:** 2026-01-20
**Domain:** Windows Storage Management (VHDX/VHD mount, partition drive letters)
**Confidence:** HIGH

## Summary

The VHDX drive letter stability issue occurs when a disk is dismounted and remounted during the FFU build workflow. When `New-OSPartition` creates the OS partition, it assigns drive letter `W:` using `Set-Partition -NewDriveLetter 'W'`. However, this assignment is **not persistent** - when the disk is later dismounted (for VHDX caching) and remounted (for unattend injection), the drive letter assignment is lost.

The core issue is that Windows drive letter assignments to VHDX/VHD partitions are ephemeral unless explicitly stored in the registry (MountedDevices). When `Mount-VHD` or diskpart `attach vdisk` remounts the disk, Windows does not automatically restore the previous drive letter assignment.

**Primary recommendation:** Always explicitly assign drive letters after any mount operation, never assume previous assignments persist. Use `Set-Partition -NewDriveLetter` immediately after mount, not just during initial partition creation.

## Root Cause Analysis

### The Problem Flow

1. **Initial Creation (BuildFFUVM.ps1 line ~3908)**
   ```
   New-OSPartition -> Set-Partition -NewDriveLetter 'W' -> Drive letter assigned
   ```

2. **VHDX Caching (line ~4088-4089)**
   ```
   Invoke-DismountScratchDisk -> Drive letter assignment LOST
   ```

3. **Unattend Injection (line ~4201)**
   ```
   Invoke-MountScratchDisk -> Disk mounted, but NO drive letter assigned
   Get-Partition -> DriveLetter property is NULL or empty
   ```

4. **Current Workaround (line ~4229-4253)**
   The code already detects this condition and assigns a new drive letter:
   ```powershell
   if ([string]::IsNullOrWhiteSpace($osPartitionDriveLetter)) {
       # Find available letter (Z downward) and assign
       $osPartition | Set-Partition -NewDriveLetter $availableLetter
   }
   ```

### Why Drive Letters Are Lost

According to [Microsoft documentation](https://learn.microsoft.com/en-us/answers/questions/784412/mount-vhd-no-drive-letter-getting-assigned-when-vh), this behavior is expected:

- **Windows Server 2022+** behavior: `Mount-VHD` does not automatically assign drive letters
- **Hyper-V module differences**: Different Windows versions have different auto-assign behavior
- **diskpart attach**: Never auto-assigns drive letters (unlike `Mount-VHD` which may)
- **Persistence model**: Drive letters are only persistent when stored in `HKLM:\SYSTEM\MountedDevices`

### Scenarios Where Issue Occurs

| Scenario | Provider | Mount Method | Auto-Assign? | Issue? |
|----------|----------|--------------|--------------|--------|
| Fresh VHDX creation | Hyper-V | Mount-VHD | Sometimes | LOW |
| Cached VHDX remount | Hyper-V | Mount-VHD | NO | HIGH |
| Fresh VHD creation | VMware | diskpart attach | NO | HIGH |
| Cached VHD remount | VMware | diskpart attach | NO | HIGH |
| Existing disk reuse | Either | Mount-VHD/diskpart | NO | HIGH |

## Current Implementation Analysis

### Key Files

| File | Function | Role |
|------|----------|------|
| `BuildFFUVM.ps1` | `Invoke-MountScratchDisk` | Mounts VHD/VHDX, returns disk object |
| `BuildFFUVM.ps1` | `Invoke-DismountScratchDisk` | Dismounts disk |
| `FFU.Imaging.psm1` | `New-OSPartition` | Creates partition with initial `W:` drive letter |
| `FFU.Hypervisor/HyperVProvider.ps1` | `MountVirtualDisk` | Provider mount with drive letter handling |
| `FFU.Hypervisor/VMwareProvider.ps1` | `MountVirtualDisk` | Provider mount via diskpart |
| `FFU.Hypervisor/New-VHDWithDiskpart.ps1` | `Mount-VHDWithDiskpart`, `Get-VHDMountedDriveLetter`, `Set-VHDDriveLetter` | Diskpart-based mounting with drive letter utilities |

### Existing Drive Letter Handling Code

**1. FFU.Imaging - Initial Creation (HIGH confidence)**
```powershell
# FFU.Imaging.psm1 line 1431
$osPartition | Set-Partition -NewDriveLetter 'W'
$osPartition = Get-Partition -DriveLetter 'W'  # Re-fetch to get updated object
```

**2. BuildFFUVM.ps1 - Unattend Injection (HIGH confidence)**
```powershell
# Lines 4226-4253 - already handles missing drive letter
$osPartitionDriveLetter = $osPartition.DriveLetter
if ([string]::IsNullOrWhiteSpace($osPartitionDriveLetter)) {
    $usedLetters = (Get-Volume).DriveLetter
    $availableLetter = [char[]](90..68) | Where-Object { $_ -notin $usedLetters } | Select-Object -First 1
    $osPartition | Set-Partition -NewDriveLetter $availableLetter
    # Re-fetch and verify
    $osPartition = $disk | Get-Partition | Where-Object { $_.GptType -eq '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}' }
    $osPartitionDriveLetter = $osPartition.DriveLetter
}
```

**3. Hyper-V Provider (MEDIUM confidence)**
```powershell
# HyperVProvider.ps1 lines 411-436
[string] MountVirtualDisk([string]$Path) {
    $disk = Mount-VHD -Path $Path -Passthru -ErrorAction Stop
    $partitions = $disk | Get-Disk | Get-Partition | Where-Object { $_.Type -ne 'Reserved' }

    foreach ($partition in $partitions) {
        if ($partition.DriveLetter) {
            return "$($partition.DriveLetter):\"  # Return if already assigned
        }
    }

    # No drive letter - try to assign one
    $partition = $partitions | Select-Object -First 1
    $availableLetter = (68..90 | ForEach-Object { [char]$_ } |
        Where-Object { -not (Test-Path "$($_):") } | Select-Object -First 1)
    Set-Partition -DiskNumber $partition.DiskNumber -PartitionNumber $partition.PartitionNumber `
        -NewDriveLetter $availableLetter -ErrorAction Stop
    return "$($availableLetter):\"
}
```

**4. VMware Provider (MEDIUM confidence)**
```powershell
# VMwareProvider.ps1 lines 760-764
[string] MountVirtualDisk([string]$Path) {
    $driveLetter = Mount-VHDWithDiskpart -Path $Path  # Handles drive letter internally
    return $driveLetter
}
```

**5. New-VHDWithDiskpart.ps1 - Get/Set Drive Letter (HIGH confidence)**
```powershell
# Lines 267-361 - Get-VHDMountedDriveLetter
# Lines 368-475 - Set-VHDDriveLetter
# These functions provide robust drive letter detection and assignment
```

## Identified Issues

### Issue 1: Inconsistent Mount Returns

**What:** Different mount functions return different types
- `Invoke-MountScratchDisk` returns disk object (no drive letter)
- `HyperVProvider.MountVirtualDisk` returns drive letter string
- `VMwareProvider.MountVirtualDisk` returns drive letter string

**Impact:** Code must handle both cases, leading to inconsistent patterns

### Issue 2: Verification Step Uses Wrong Path Variable

**What:** At line 4343, the code checks if `$unattendDest` is empty and tries to refresh
**Actual Issue:** The `$osPartitionDriveLetter` variable was already populated, but the refresh logic at line 4346-4354 is defensive coding for an edge case

### Issue 3: Drive Letter Contention

**What:** Using hardcoded `'W'` for initial creation but dynamic letters for remount
**Impact:** May cause confusion in logs, potential conflicts if W: is in use

### Issue 4: No Retention of Original Drive Letter

**What:** After remount, the code assigns any available letter (Z downward)
**Impact:** Different drive letters between creation and remount phases could cause issues if code hardcodes paths

## Standard Approach

### Pattern: Always-Assign-After-Mount

**Principle:** Never assume drive letter persistence. Always assign after any mount operation.

```powershell
function Mount-DiskWithDriveLetter {
    param(
        [string]$DiskPath,
        [char]$PreferredLetter = $null
    )

    # Mount the disk
    $disk = Mount-DiskWithoutLetter -DiskPath $DiskPath

    # Find OS partition
    $osPartition = $disk | Get-Partition |
        Where-Object { $_.GptType -eq '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}' }

    # Check if drive letter exists
    if ([string]::IsNullOrWhiteSpace($osPartition.DriveLetter)) {
        # Assign preferred or find available
        $letter = if ($PreferredLetter -and -not (Test-Path "$($PreferredLetter):")) {
            $PreferredLetter
        } else {
            $usedLetters = (Get-Volume).DriveLetter
            [char[]](90..68) | Where-Object { $_ -notin $usedLetters } | Select-Object -First 1
        }

        $osPartition | Set-Partition -NewDriveLetter $letter
        Start-Sleep -Milliseconds 500  # Allow Windows to complete assignment

        # Re-fetch to confirm
        $osPartition = Get-Partition -DriveLetter $letter
    }

    return @{
        Disk = $disk
        Partition = $osPartition
        DriveLetter = $osPartition.DriveLetter
    }
}
```

### Pattern: Centralized Drive Letter Utility

Create a single function that handles all drive letter operations:

```powershell
function Ensure-OSPartitionDriveLetter {
    param(
        [Parameter(Mandatory)]
        $Disk,
        [char]$PreferredLetter = $null
    )

    $osPartition = $Disk | Get-Partition |
        Where-Object { $_.GptType -eq '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}' }

    if (-not $osPartition) {
        throw "No OS partition found on disk $($Disk.Number)"
    }

    $currentLetter = $osPartition.DriveLetter

    if ([string]::IsNullOrWhiteSpace($currentLetter)) {
        # Assign drive letter
        $letter = Get-AvailableDriveLetter -Preferred $PreferredLetter
        $osPartition | Set-Partition -NewDriveLetter $letter
        Start-Sleep -Milliseconds 500
        $currentLetter = $letter
    }

    return $currentLetter
}
```

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Drive letter detection | Custom WMI queries | `Get-Partition`, `Get-Volume` | Built-in, handles edge cases |
| Available letter finding | Manual iteration | `(Get-Volume).DriveLetter` exclusion | Accounts for all mounted volumes |
| Drive letter assignment | `diskpart assign` for VHDX | `Set-Partition -NewDriveLetter` | PowerShell native, better error handling |
| Partition refresh | Cache partition object | `Get-Partition -DriveLetter $letter` | Always get fresh state after changes |

## Common Pitfalls

### Pitfall 1: Stale Partition Objects

**What goes wrong:** Using cached `$osPartition` object after `Set-Partition`
**Why it happens:** PowerShell partition objects don't auto-refresh
**How to avoid:** Always re-fetch after any modification:
```powershell
$osPartition | Set-Partition -NewDriveLetter $letter
$osPartition = Get-Partition -DriveLetter $letter  # REQUIRED
```
**Warning signs:** `$osPartition.DriveLetter` is null even after Set-Partition

### Pitfall 2: Race Conditions with Windows Shell

**What goes wrong:** Drive letter operation fails or Explorer prompts format dialog
**Why it happens:** Windows Shell detects new partition before format completes
**How to avoid:**
- Create partitions without drive letter first
- Format the partition
- Then assign drive letter
**Warning signs:** Random "Format disk" dialogs during build

### Pitfall 3: Assuming Mount-VHD Auto-Assigns

**What goes wrong:** Code assumes `Mount-VHD` returns partition with drive letter
**Why it happens:** Works in some Windows versions, not others
**How to avoid:** Always check and assign explicitly
**Warning signs:** Works on dev machine, fails on server

### Pitfall 4: Using -Passthru Incorrectly

**What goes wrong:** `Mount-VHD -Passthru` returns VHD object, not disk
**Why it happens:** Need `| Get-Disk` to get disk object for partitions
**How to avoid:** Chain properly:
```powershell
$disk = Mount-VHD -Path $path -Passthru | Get-Disk
# NOT: $disk = Mount-VHD -Path $path -Passthru
```
**Warning signs:** `Get-Partition` fails on VHD object

### Pitfall 5: Hardcoded Drive Letters

**What goes wrong:** Using `W:` everywhere, fails when W: is in use
**Why it happens:** Assuming W: is always available
**How to avoid:** Use dynamic letter selection with preferred letter fallback
**Warning signs:** Fails when another VHDX is mounted

## Recommended Approach

### Option A: Enhance Existing Code (Recommended)

The current code at lines 4226-4253 already handles missing drive letters. The issue is that:
1. This handling is **only in the unattend injection section**
2. Other code paths may have the same issue
3. No centralized utility function exists

**Recommendation:**
1. Extract drive letter handling to a utility function in FFU.Imaging or FFU.Core
2. Call this function after every mount operation
3. Add verification to ensure drive letter is stable before proceeding

### Option B: Modify Mount Functions

Modify `Invoke-MountScratchDisk` to always return both disk object AND drive letter:

```powershell
function Invoke-MountScratchDisk {
    param([string]$DiskPath)

    # Existing mount logic...

    # NEW: Always ensure drive letter
    $driveLetter = Ensure-OSPartitionDriveLetter -Disk $disk

    return @{
        Disk = $disk
        DriveLetter = $driveLetter
    }
}
```

### Option C: Store Drive Letter Preference

Store the preferred drive letter in a tracking variable and always try to reassign it:

```powershell
$script:PreferredOSDriveLetter = 'W'

# After any mount:
$driveLetter = Ensure-OSPartitionDriveLetter -Disk $disk -Preferred $script:PreferredOSDriveLetter
```

## Provider-Specific Considerations

### Hyper-V Provider

- Uses `Mount-VHD` which **sometimes** auto-assigns drive letters
- Current `MountVirtualDisk` method already handles missing letters
- **Risk:** LOW - existing implementation is robust

### VMware Provider

- Uses `diskpart attach` which **never** auto-assigns drive letters
- `Mount-VHDWithDiskpart` calls `Set-VHDDriveLetter` if needed
- **Risk:** MEDIUM - relies on `Get-VHDMountedDriveLetter` which has fallback logic

### Verification Requirements

Both providers should:
1. Return the assigned drive letter from mount operations
2. Verify drive letter is accessible before returning
3. Log drive letter assignment for debugging

## Code Examples

### Example 1: Robust Drive Letter Assignment

```powershell
# Source: BuildFFUVM.ps1 pattern adapted
function Set-OSPartitionDriveLetter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Disk,

        [char]$PreferredLetter = $null,

        [int]$RetryCount = 3
    )

    $osPartition = $Disk | Get-Partition |
        Where-Object { $_.GptType -eq '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}' }

    if (-not $osPartition) {
        throw "No OS partition found on disk $($Disk.Number)"
    }

    # Check existing drive letter
    if (-not [string]::IsNullOrWhiteSpace($osPartition.DriveLetter)) {
        WriteLog "OS partition already has drive letter: $($osPartition.DriveLetter)"
        return $osPartition.DriveLetter
    }

    WriteLog "OS partition has no drive letter, assigning..."

    # Get available letters (Z downward to avoid conflicts)
    $usedLetters = (Get-Volume).DriveLetter
    $availableLetters = [char[]](90..68) | Where-Object { $_ -notin $usedLetters }

    # Prefer specified letter if available
    $targetLetter = if ($PreferredLetter -and $PreferredLetter -in $availableLetters) {
        $PreferredLetter
    } else {
        $availableLetters | Select-Object -First 1
    }

    if (-not $targetLetter) {
        throw "No available drive letters"
    }

    # Assign with retry
    for ($i = 1; $i -le $RetryCount; $i++) {
        try {
            WriteLog "  Attempt $i`: Assigning drive letter $targetLetter"
            $osPartition | Set-Partition -NewDriveLetter $targetLetter -ErrorAction Stop
            Start-Sleep -Milliseconds 500

            # Verify assignment
            $osPartition = Get-Partition -DriveLetter $targetLetter -ErrorAction Stop
            WriteLog "  Successfully assigned drive letter $targetLetter"
            return $targetLetter
        }
        catch {
            WriteLog "  WARNING: Attempt $i failed: $($_.Exception.Message)"
            if ($i -eq $RetryCount) { throw }
            Start-Sleep -Seconds 1
        }
    }
}
```

### Example 2: Mount with Guaranteed Drive Letter

```powershell
# Source: Pattern for enhanced Invoke-MountScratchDisk
function Mount-DiskWithDriveLetter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DiskPath,

        [char]$PreferredLetter = $null
    )

    WriteLog "Mounting disk: $DiskPath"

    # Mount using appropriate method
    if ($DiskPath -like "*.vhd" -and $DiskPath -notlike "*.vhdx") {
        # VHD via diskpart
        $disk = Mount-VHDViaDiskpart -DiskPath $DiskPath
    }
    else {
        # VHDX via Hyper-V
        $disk = Mount-VHD -Path $DiskPath -Passthru | Get-Disk
    }

    # Ensure drive letter
    $driveLetter = Set-OSPartitionDriveLetter -Disk $disk -PreferredLetter $PreferredLetter

    return @{
        Disk = $disk
        DriveLetter = $driveLetter
        Path = "$($driveLetter):\"
    }
}
```

## Open Questions

1. **Should we persist drive letter in MountedDevices registry?**
   - What we know: Windows can remember drive letters if stored in registry
   - What's unclear: May cause conflicts with other mounted disks
   - Recommendation: Avoid registry persistence, use dynamic assignment

2. **Should the drive letter be consistent across remounts?**
   - What we know: Current code uses any available letter
   - What's unclear: Are there downstream dependencies on specific letters?
   - Recommendation: Use preferred letter pattern (try W: first, fall back)

3. **VMware VMDK support?**
   - What we know: VMware uses VHD via diskpart currently
   - What's unclear: Will future VMDK support need different handling?
   - Recommendation: Abstract drive letter handling in provider interface

## Sources

### Primary (HIGH confidence)
- Codebase analysis: `BuildFFUVM.ps1` lines 4190-4420, `FFU.Imaging.psm1` lines 1300-1450
- Codebase analysis: `FFU.Hypervisor/Providers/*.ps1`, `New-VHDWithDiskpart.ps1`

### Secondary (MEDIUM confidence)
- [Mount-VHD Microsoft Learn](https://learn.microsoft.com/en-us/powershell/module/hyper-v/mount-vhd?view=windowsserver2025-ps)
- [Mount-VHD no drive letter Q&A](https://learn.microsoft.com/en-us/answers/questions/784412/mount-vhd-no-drive-letter-getting-assigned-when-vh)

### Tertiary (LOW confidence)
- Web search: Windows VHDX drive letter persistence patterns

## Metadata

**Confidence breakdown:**
- Root cause analysis: HIGH - verified in codebase
- Standard approach: HIGH - well-documented Windows behavior
- Provider-specific: MEDIUM - VMware path less tested
- Pitfalls: HIGH - documented in codebase comments

**Research date:** 2026-01-20
**Valid until:** 60 days (stable Windows APIs)
