# Phase 4: Performance Optimization - Research

**Researched:** 2026-01-19
**Domain:** PowerShell performance optimization, event-driven synchronization, module decomposition
**Confidence:** MEDIUM

## Summary

Phase 4 addresses three performance requirements: VHD flush optimization (PERF-01), event-driven synchronization (PERF-02), and module decomposition evaluation (PERF-03). Research investigated current Start-Sleep usage patterns (56+ instances), VHD flush mechanisms, PowerShell event subscription patterns, and module organization best practices.

Key findings:
1. The current triple-pass VHD flush is overly conservative; Windows provides `Write-VolumeCache` cmdlet for single verified flush
2. Many Start-Sleep instances are "intentional delays" (registry settling, CBS/CSI corruption prevention) that cannot be replaced, but ~20 polling loops can use event-driven patterns
3. Module files are appropriately sized for this project; decomposition would provide marginal benefit at the cost of import performance

**Primary recommendation:** Focus on VHD flush optimization and targeted Start-Sleep replacement for polling loops. Defer extensive module decomposition.

## Standard Stack

The established libraries/tools for this domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Storage module | Built-in | `Write-VolumeCache` cmdlet | Native Windows volume cache flush |
| CimCmdlets | Built-in | `Register-CimIndicationEvent` | Modern replacement for Register-WmiEvent |
| Hyper-V WMI | v2 | `Msvm_ComputerSystem` class | VM state change events |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| fsutil | Built-in | Volume flush fallback | When Write-VolumeCache unavailable |
| FlushFileBuffers API | Win32 | Low-level file flush | .NET FileStream.Flush() wrapper |
| FileStream | .NET | Write-through I/O | Critical file writes |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Triple fsutil flush | Write-VolumeCache | Single call, verified completion, cleaner |
| Register-WmiEvent | Register-CimIndicationEvent | CIM is modern standard, better cross-platform |
| Polling loops | ManualResetEvent | More complex but true event-driven |

**Commands:**
```powershell
# Write-VolumeCache is built into Windows, no installation needed
# Verify availability:
Get-Command Write-VolumeCache -Module Storage
```

## Architecture Patterns

### Recommended VHD Flush Pattern
```
Before VHD Detach:
1. Identify VHD partitions via Get-Disk/Get-Partition
2. Call Write-VolumeCache -DriveLetter $letter for each partition
3. Verify cmdlet completed (no error = flush guaranteed)
4. Proceed with diskpart detach
```

### Pattern 1: Write-VolumeCache (Verified Single-Pass)
**What:** Use native Windows cmdlet for guaranteed volume cache flush
**When to use:** Before VHD dismount, before critical file operations
**Example:**
```powershell
# Source: Microsoft Learn - Write-VolumeCache documentation
# https://learn.microsoft.com/en-us/powershell/module/storage/write-volumecache

function Invoke-VerifiedVolumeFlush {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VhdPath
    )

    $disk = Get-Disk | Where-Object {
        $_.BusType -eq 'File Backed Virtual' -and $_.Location -eq $VhdPath
    }

    if ($disk) {
        $partitions = $disk | Get-Partition | Where-Object { $_.DriveLetter }
        foreach ($partition in $partitions) {
            WriteLog "Flushing volume $($partition.DriveLetter):"
            Write-VolumeCache -DriveLetter $partition.DriveLetter -ErrorAction Stop
            WriteLog "  Flush complete (verified)"
        }
    }
}
```

### Pattern 2: FileStream with WriteThrough
**What:** Bypass OS cache entirely for critical writes
**When to use:** Writing configuration files that must persist before VM operations
**Example:**
```powershell
# Source: Meziantou's blog - Flushing Disk Caches on Windows
# https://www.meziantou.net/flushing-disk-caches-on-windows-a-comprehensive-guide.htm

function Write-FileWithFlush {
    [CmdletBinding()]
    param(
        [string]$Path,
        [string]$Content
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Content)
    $fileStream = [System.IO.FileStream]::new(
        $Path,
        [System.IO.FileMode]::Create,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::None,
        4096,
        [System.IO.FileOptions]::WriteThrough  # Bypass cache
    )
    try {
        $fileStream.Write($bytes, 0, $bytes.Length)
        $fileStream.Flush($true)  # flushToDisk = true
    }
    finally {
        $fileStream.Dispose()
    }
}
```

### Pattern 3: Event-Driven VM State Monitoring (Hyper-V)
**What:** Subscribe to WMI events instead of polling with Start-Sleep
**When to use:** Waiting for VM shutdown, VM startup confirmation
**Example:**
```powershell
# Source: Microsoft Learn - Register-CimIndicationEvent
# https://learn.microsoft.com/en-us/powershell/module/cimcmdlets/register-cimindicationevent

function Wait-VMStateChange {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VMName,
        [Parameter(Mandatory)]
        [ValidateSet('Running', 'Off')]
        [string]$TargetState,
        [int]$TimeoutSeconds = 3600
    )

    $stateMap = @{ 'Running' = 2; 'Off' = 3 }
    $targetStateValue = $stateMap[$TargetState]
    $eventReceived = $false
    $sourceId = "VMStateChange_$([Guid]::NewGuid().ToString('N'))"

    try {
        # WQL query for VM state modification
        $query = @"
SELECT * FROM __InstanceModificationEvent WITHIN 2
WHERE TargetInstance ISA 'Msvm_ComputerSystem'
AND TargetInstance.ElementName = '$VMName'
"@

        # Register for indication with action
        $job = Register-CimIndicationEvent `
            -Query $query `
            -Namespace "root\virtualization\v2" `
            -SourceIdentifier $sourceId `
            -Action {
                $vm = $Event.SourceEventArgs.NewEvent.TargetInstance
                if ($vm.EnabledState -eq $using:targetStateValue) {
                    $global:VMEventReceived = $true
                }
            }

        # Wait with timeout
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        while (-not $global:VMEventReceived -and $stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
            Start-Sleep -Milliseconds 500  # Minimal sleep for event processing
        }

        return $global:VMEventReceived
    }
    finally {
        Unregister-Event -SourceIdentifier $sourceId -ErrorAction SilentlyContinue
        Remove-Variable -Name VMEventReceived -Scope Global -ErrorAction SilentlyContinue
    }
}
```

### Anti-Patterns to Avoid
- **Triple flush for safety:** One verified flush is sufficient; multiple passes waste time
- **Arbitrary sleep durations:** Fixed 60-second or 120-second sleeps should be event-driven or at minimum have validation
- **Polling without events:** When WMI/CIM events exist, prefer subscription over polling
- **Module splitting for its own sake:** Splitting already-modular code reduces import performance

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Volume cache flush | Multiple fsutil calls + sleeps | `Write-VolumeCache` | Single verified operation, handles edge cases |
| VM state monitoring | Polling loops with Start-Sleep | `Register-CimIndicationEvent` | True event-driven, no wasted cycles |
| File flush to disk | Multiple Flush() calls | `FileStream` with `WriteThrough` flag | Guaranteed write-through at OS level |
| Process completion wait | Start-Sleep loops | `Process.WaitForExit()` with timeout | Already used in codebase, consistent |

**Key insight:** Windows provides native mechanisms for verified I/O operations. Custom multi-pass solutions add latency without improving reliability.

## Common Pitfalls

### Pitfall 1: Replacing Intentional Delays
**What goes wrong:** Removing sleep calls that exist for legitimate reasons (registry settling, CBS/CSI corruption prevention)
**Why it happens:** Assumption that all Start-Sleep calls are optimization targets
**How to avoid:** Categorize each sleep before replacing - see "Start-Sleep Categories" below
**Warning signs:** Comments explaining WHY the sleep exists, especially mentioning "corruption" or "stabilize"

### Pitfall 2: WMI Event Leak
**What goes wrong:** Event subscriptions not cleaned up, causing resource exhaustion
**Why it happens:** Error paths skip Unregister-Event, or finally blocks missing
**How to avoid:** Always use try/finally with Unregister-Event in finally block
**Warning signs:** Event subscriber count growing over time, memory increase during long builds

### Pitfall 3: Event Query Performance
**What goes wrong:** WMI event query with WITHIN 1 (1-second polling) causes high CPU
**Why it happens:** Lower WITHIN values = more frequent WMI polling internally
**How to avoid:** Use WITHIN 2-5 for VM state changes (sufficient granularity)
**Warning signs:** WmiPrvSE.exe high CPU during event subscriptions

### Pitfall 4: Module Import Performance Regression
**What goes wrong:** Splitting modules into many small files dramatically increases import time
**Why it happens:** Each dot-sourced file incurs file system overhead
**How to avoid:** Keep functions in single PSM1 unless specific need for separation
**Warning signs:** Module import taking 5+ seconds (should be <1 second)

## Code Examples

Verified patterns from official sources:

### Write-VolumeCache Usage
```powershell
# Source: Microsoft Learn - Write-VolumeCache
# https://learn.microsoft.com/en-us/powershell/module/storage/write-volumecache

# Flush single volume
Write-VolumeCache -DriveLetter C

# Flush multiple volumes
Write-VolumeCache -DriveLetter C, D, E

# Flush by path
Write-VolumeCache -Path "C:\"

# With PassThru to verify completion
$result = Write-VolumeCache -DriveLetter C -PassThru
WriteLog "Flushed volume: $($result.DriveLetter)"
```

### CIM Event Subscription
```powershell
# Source: Microsoft Learn - Register-CimIndicationEvent
# https://learn.microsoft.com/en-us/powershell/module/cimcmdlets/register-cimindicationevent

# Subscribe to process start events (example pattern)
$action = {
    $name = $Event.SourceEventArgs.NewEvent.ProcessName
    Write-Host "Process started: $name"
}

Register-CimIndicationEvent `
    -ClassName 'Win32_ProcessStartTrace' `
    -SourceIdentifier 'ProcessStarted' `
    -Action $action

# Cleanup
Unregister-Event -SourceIdentifier 'ProcessStarted'
```

### fsutil Fallback (for older Windows)
```powershell
# Fallback when Write-VolumeCache unavailable
function Invoke-FsutilFlush {
    param([char]$DriveLetter)

    $result = & fsutil volume flush "$DriveLetter`:" 2>&1
    if ($LASTEXITCODE -eq 0) {
        WriteLog "Volume $DriveLetter`: flushed via fsutil"
        return $true
    }
    WriteLog "WARNING: fsutil flush returned: $result"
    return $false
}
```

## Start-Sleep Categories

Analysis of 56+ Start-Sleep instances in the codebase:

### Category A: Replaceable Polling Loops (Target ~20 instances)
**Can be replaced with event-driven synchronization:**

| Location | Current Sleep | Replacement |
|----------|---------------|-------------|
| BuildFFUVM.ps1:4293 | VM startup poll (2s) | Register-CimIndicationEvent for VM state |
| BuildFFUVM.ps1:4409 | VM shutdown poll (5s) | Register-CimIndicationEvent for VM state |
| FFU.Imaging.psm1:1882 | Mount poll (poll interval) | WaitHandle or event |
| FFU.Imaging.psm1:1926 | Mount poll (poll interval) | WaitHandle or event |
| FFU.BuildTest.psm1:249/385 | Build test poll | Event subscription |
| FFU.Common.Parallel.psm1:483/493 | Runspace poll | WaitHandle |
| FFU.Common.ParallelDownload.psm1:281/509 | Download poll | WaitHandle |

### Category B: Intentional Delays - Do Not Replace (Keep ~20 instances)
**These exist for legitimate technical reasons:**

| Location | Sleep Duration | Reason (from comments) |
|----------|----------------|------------------------|
| FFU.Imaging.psm1:1626 | 60 seconds | "prevents CBS/CSI corruption" before registry |
| FFU.Imaging.psm1:1681 | 60 seconds | "allow registry to completely unload" |
| FFU.Imaging.psm1:2069 | 120 seconds | "prevent file handle lock" |
| FFU.Imaging.psm1:1171 | 500ms | "Between flush passes" (will be obsolete after single-pass) |
| FFU.Imaging.psm1:1187 | 5 seconds | "Waiting for disk I/O to complete" |
| FFU.Media.psm1:197 | DISM_CLEANUP_WAIT | DISM stabilization |
| Various | 2-3 seconds | Post-dismount, post-mount stabilization |

### Category C: Retry Delays - Keep with Exponential Backoff (~10 instances)
**Standard retry patterns, can improve with backoff:**

| Location | Current | Improvement |
|----------|---------|-------------|
| FFU.Common.Download.psm1:284/369/457/552/562 | Fixed delay | Exponential backoff |
| FFU.Updates.psm1:408/1061/1196 | Fixed retry delay | Exponential backoff |
| FFU.Core.psm1:1250 | Fixed retry delay | Already appropriate |
| FFU.Preflight.psm1:498 | Fixed retry delay | Already appropriate |

### Category D: Service/Process Waits - Consider Process.WaitForExit (~6 instances)
**Could use process completion events:**

| Location | Current | Improvement |
|----------|---------|-------------|
| FFU.Drivers.psm1:1324/1351 | SERVICE_STARTUP_WAIT | Check service status |
| Various WimMount scripts | Fixed 2-3 second waits | Service ready check |

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Register-WmiEvent | Register-CimIndicationEvent | PowerShell 3.0+ | CIM is modern standard |
| Multiple fsutil flush | Write-VolumeCache | Windows 10/Server 2016 | Single verified operation |
| Multi-file dot-source modules | Single PSM1 or build-merged | 2020s best practice | 10-15x faster import |
| Fixed-interval polling | Event subscriptions | Always available | Lower CPU, faster response |

**Deprecated/outdated:**
- **Register-WmiEvent:** Still works but CIM cmdlets preferred; not available in PowerShell Core
- **Triple-pass flush:** Unnecessary with verified flush cmdlets

## Module Decomposition Analysis

### Current Module Sizes
| Module | Lines | Functions | Assessment |
|--------|-------|-----------|------------|
| BuildFFUVM.ps1 | 4,683 | Script orchestrator | Appropriate size for main script |
| FFU.Core.psm1 | 2,963 | 39 | Large but cohesive; decomposition marginal benefit |
| FFU.Preflight.psm1 | 2,883 | 12 | Validation functions; logically grouped |
| FFU.Imaging.psm1 | 2,805 | 15 | DISM/FFU operations; cohesive domain |

### Decomposition Recommendation: **Defer**
**Rationale:**
1. **Import performance:** Multi-file modules load 12-15x slower than single PSM1
2. **Current sizes reasonable:** 2,500-3,000 lines is manageable for cohesive modules
3. **Already modularized:** Project has 11+ specialized modules
4. **Marginal benefit:** Further splitting would fragment related functions

**If decomposition is desired later:**
- Use build-time merging: develop in multiple files, merge for production
- Group by domain: keep related functions together
- Avoid over-splitting: 10-20 functions per module is reasonable

## Open Questions

Things that couldn't be fully resolved:

1. **VMware event model**
   - What we know: VMware Workstation uses vmrun CLI, no WMI events
   - What's unclear: Whether vmrest API has event subscription capability
   - Recommendation: Keep polling for VMware; focus event-driven on Hyper-V only

2. **CBS/CSI timing requirements**
   - What we know: 60-second sleep "prevents corruption" per code comments
   - What's unclear: Exact minimum safe duration; whether event-based verification possible
   - Recommendation: Keep conservative delays; document as technical debt for future investigation

3. **Write-VolumeCache on older Windows**
   - What we know: Available Windows 10+/Server 2016+
   - What's unclear: Behavior on Windows Server 2012 R2 if still supported
   - Recommendation: Implement with fsutil fallback for compatibility

## Sources

### Primary (HIGH confidence)
- [Microsoft Learn - Write-VolumeCache](https://learn.microsoft.com/en-us/powershell/module/storage/write-volumecache?view=windowsserver2025-ps) - Full cmdlet documentation
- [Microsoft Learn - Register-CimIndicationEvent](https://learn.microsoft.com/en-us/powershell/module/cimcmdlets/register-cimindicationevent?view=powershell-7.5) - Event subscription patterns
- [Microsoft Learn - Msvm_ComputerSystem](https://learn.microsoft.com/en-us/windows/win32/hyperv_v2/msvm-computersystem) - Hyper-V WMI class documentation

### Secondary (MEDIUM confidence)
- [Meziantou's Blog - Flushing Disk Caches](https://www.meziantou.net/flushing-disk-caches-on-windows-a-comprehensive-guide.htm) - Comprehensive flush methods
- [Evotec - Single PSM1 vs Multi-file](https://evotec.xyz/powershell-single-psm1-file-versus-multi-file-modules/) - Module performance benchmarks
- [PowerShell Playbook - Module Best Practices](https://www.psplaybook.com/2025/02/06/powershell-modules-best-practices/) - Structure recommendations

### Tertiary (LOW confidence)
- [FoxDeploy - WMI Events](https://www.foxdeploy.com/blog/registering-for-wmi-events-in-powershell.html) - Example patterns
- WebSearch results on event-driven PowerShell patterns

## Metadata

**Confidence breakdown:**
- VHD flush optimization: HIGH - Official cmdlet documentation, clear replacement path
- Event-driven sync: MEDIUM - Pattern clear for Hyper-V, VMware unclear
- Module decomposition: HIGH - Clear benchmarks and best practices available
- Start-Sleep categorization: MEDIUM - Based on code analysis and comments

**Research date:** 2026-01-19
**Valid until:** 60 days (stable domain, infrequent Windows API changes)

## Implementation Priority

Based on research, recommended task ordering:

1. **PERF-01 (VHD flush):** High impact, low risk, clear implementation path
2. **PERF-02 (event-driven):** Medium impact, target Hyper-V VM polling loops only (~8 instances)
3. **PERF-03 (decomposition):** Low priority, recommend documenting current state and deferring

**Estimated time savings from PERF-01:**
- Current: 3 flush passes x 500ms pause + 5s I/O wait = ~7 seconds per VHD dismount
- After: 1 verified flush = <1 second
- **50%+ reduction target: Achievable**

**Estimated PERF-02 scope:**
- ~20 instances can be converted to event-driven
- Focus on VM state polling (BuildFFUVM.ps1 lines 4280-4420)
- Secondary: runspace/parallel download completion
