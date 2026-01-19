# Phase 7: Feature - Build Cancellation - Research

**Researched:** 2026-01-19
**Domain:** WPF UI + PowerShell Background Job Cancellation, Resource Cleanup
**Confidence:** HIGH

## Summary

Build cancellation in FFUBuilder requires integrating existing infrastructure that is largely already in place. The codebase has a comprehensive FFU.Messaging module with cancellation support (CancellationRequested flag, Request-FFUCancellation, Test-FFUCancellationRequested) and a cleanup registry system in FFU.Core (Register-*Cleanup, Invoke-FailureCleanup). The UI already implements cancel button behavior and process tree termination. The gap is that BuildFFUVM.ps1 does not currently check for cancellation requests during execution.

The implementation strategy is to add periodic cancellation checks (polling) at key checkpoints in BuildFFUVM.ps1, and invoke the cleanup registry when cancellation is detected. The infrastructure exists - it just needs to be wired together.

**Primary recommendation:** Add `Test-FFUCancellationRequested` checks at major phase boundaries in BuildFFUVM.ps1 and call `Invoke-FailureCleanup` when cancellation is detected. No new modules or major infrastructure needed.

## Current State Analysis

### What Already Exists

| Component | Location | Status |
|-----------|----------|--------|
| FFU.Messaging module | `Modules/FFU.Messaging/FFU.Messaging.psm1` | COMPLETE - Full cancellation token pattern |
| Cleanup registry | `Modules/FFU.Core/FFU.Core.psm1` | COMPLETE - LIFO cleanup with resource type filtering |
| UI cancel button | `BuildFFUVM_UI.ps1` lines 210-420 | COMPLETE - Process tree termination |
| Resource registration helpers | FFU.Core | COMPLETE - Register-VMCleanup, Register-VHDXCleanup, etc. |
| MessagingContext param | `BuildFFUVM.ps1` line 536 | COMPLETE - Parameter exists |
| Cancellation check functions | FFU.Messaging | COMPLETE - Test-FFUCancellationRequested, Request-FFUCancellation |

### What Is Missing

| Gap | Impact | Required Work |
|-----|--------|---------------|
| Cancellation polling in BuildFFUVM.ps1 | Build cannot gracefully stop | Add Test-FFUCancellationRequested checks |
| Cleanup invocation on cancel | Resources may be orphaned | Call Invoke-FailureCleanup on cancel detect |
| Resource cleanup registration completeness | Some resources may not be tracked | Audit and add missing Register-*Cleanup calls |
| UI status feedback during cleanup | User doesn't see cleanup progress | Send messages during cleanup phase |

## Standard Stack

The established libraries/tools for this domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| FFU.Messaging | 1.0.0 | ConcurrentQueue-based UI/job communication | Already in codebase, has cancellation support |
| FFU.Core | 1.0.9 | Cleanup registry system | Already in codebase, has LIFO cleanup |
| System.Collections.Concurrent | .NET built-in | Thread-safe collections | ConcurrentQueue for message passing |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| ThreadJob module | PowerShell Gallery | Background job with credential inheritance | Already used for BITS downloads |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Boolean flag polling | CancellationTokenSource | .NET CancellationToken requires binary cmdlets; flag polling is simpler for PowerShell scripts |
| LIFO cleanup registry | Simple try/finally | Registry pattern handles partial failures better |

## Architecture Patterns

### Recommended Cancellation Flow

```
UI Thread                          ThreadJob (BuildFFUVM.ps1)
    |                                       |
    | -- [User clicks Cancel] -->           |
    |                                       |
    | Request-FFUCancellation($ctx)         |
    |    (sets $ctx.CancellationRequested)  |
    |                                       |
    |                              <-- [At checkpoint] -->
    |                              Test-FFUCancellationRequested($ctx)
    |                                       |
    |                              if ($true) {
    |                                  Invoke-FailureCleanup
    |                                  Set-FFUBuildState -State Cancelled
    |                                  return early
    |                              }
    |                                       |
    | -- Stop-Job (force after timeout) --> |
```

### Checkpoint Pattern for BuildFFUVM.ps1

```powershell
# Pattern: Check cancellation at phase boundaries
function Test-BuildCancellation {
    param(
        [hashtable]$MessagingContext,
        [string]$PhaseName
    )

    if ($null -eq $MessagingContext) { return $false }

    if (Test-FFUCancellationRequested -Context $MessagingContext) {
        WriteLog "Cancellation requested at phase: $PhaseName"
        Write-FFUWarning -Context $MessagingContext `
            -Message "Cancellation requested, stopping at: $PhaseName" `
            -Source 'BuildFFUVM'
        return $true
    }
    return $false
}

# Usage at each major phase:
if (Test-BuildCancellation -MessagingContext $MessagingContext -PhaseName "Driver Download") {
    Invoke-FailureCleanup -Reason "User cancelled build"
    return
}
```

### Recommended Checkpoint Locations in BuildFFUVM.ps1

| Phase | Line (approx) | Why This Location |
|-------|---------------|-------------------|
| After pre-flight validation | ~800 | Before any resource creation |
| Before driver download | ~1200 | Long-running operation |
| After driver download | ~1500 | Before VHDX creation |
| Before VHDX creation | ~1800 | Expensive operation |
| After VHDX creation | ~2100 | Before VM creation |
| Before VM start | ~2200 | Point of no return for VM |
| After VM shutdown | ~2800 | Before FFU capture |
| Before FFU capture | ~3000 | Long-running DISM operation |

### Cleanup Registration Pattern

```powershell
# Resources should be registered immediately after creation
$vhdxPath = New-VHDX -Path $path -Size $size
$cleanupId = Register-VHDXCleanup -VHDXPath $vhdxPath
WriteLog "Registered VHDX cleanup (ID: $cleanupId)"

# ... later, if successful ...
Unregister-CleanupAction -CleanupId $cleanupId
```

### Anti-Patterns to Avoid

- **Immediate termination without cleanup:** Never call `throw` or `return` on cancellation without first calling `Invoke-FailureCleanup`
- **Checking cancellation too frequently:** Don't poll in tight loops; check at phase boundaries only (every 30-60 seconds of work)
- **Checking cancellation too rarely:** Check before any operation that takes >1 minute
- **Ignoring cleanup registry after normal completion:** Call `Clear-CleanupRegistry` at end of successful build

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Thread-safe cancellation flag | `$script:cancelled = $true` | `$Context.CancellationRequested` in synchronized hashtable | Race conditions, visibility |
| Resource cleanup tracking | Manual try/finally nesting | `Register-*Cleanup` + `Invoke-FailureCleanup` | Handles partial failures, ordered cleanup |
| Process tree termination | Simple Stop-Process | UI's existing `Stop-ProcessTree` function | Child processes (DISM, etc.) |
| Message passing | File-based polling | FFU.Messaging ConcurrentQueue | 20x faster, lock-free |

**Key insight:** The FFU.Messaging module already implements the cooperative cancellation pattern recommended by .NET best practices. The cleanup registry in FFU.Core already implements LIFO resource cleanup. Use them.

## Common Pitfalls

### Pitfall 1: Orphaned Resources After Cancellation
**What goes wrong:** VM, VHDX, or mounted images left behind after cancel
**Why it happens:** `Invoke-FailureCleanup` not called before exit
**How to avoid:** Every early return on cancellation MUST call `Invoke-FailureCleanup` first
**Warning signs:** Users report leftover VMs or disk files after cancelling

### Pitfall 2: Cleanup Actions Fail Silently
**What goes wrong:** Cleanup registry has stale/invalid actions
**Why it happens:** Resources were manually deleted or paths changed
**How to avoid:** `Invoke-FailureCleanup` already handles this - logs failures but continues
**Warning signs:** Cleanup log shows failures but build appears successful

### Pitfall 3: Race Condition Between UI Cancel and Job Check
**What goes wrong:** Job doesn't see cancellation flag
**Why it happens:** Job finished checkpoint before flag was set
**How to avoid:** UI uses timeout + force kill after grace period (already implemented)
**Warning signs:** Cancel button appears to do nothing initially

### Pitfall 4: DISM Operations Cannot Be Interrupted
**What goes wrong:** `dism /Capture-FFU` ignores cancellation, must be killed
**Why it happens:** DISM is an external process with no cancellation API
**How to avoid:** Check cancellation BEFORE starting DISM, not during; UI kills process tree
**Warning signs:** FFU capture continues after cancel

### Pitfall 5: Cleanup Registry Not Persisted Across Script Restarts
**What goes wrong:** If BuildFFUVM.ps1 crashes, cleanup registry is lost
**Why it happens:** Registry is in-memory only
**How to avoid:** Accept this limitation; UI's process tree kill handles most cases
**Warning signs:** Resources orphaned after PowerShell crash (rare)

## Code Examples

### Example 1: Test-BuildCancellation Helper (to add to FFU.Core)

```powershell
# Source: New function to add to FFU.Core.psm1
function Test-BuildCancellation {
    <#
    .SYNOPSIS
    Checks if cancellation was requested and handles cleanup if so.

    .DESCRIPTION
    Should be called at major phase boundaries in BuildFFUVM.ps1.
    Returns $true if cancelled (caller should return early).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [hashtable]$MessagingContext,

        [Parameter(Mandatory)]
        [string]$PhaseName,

        [Parameter()]
        [switch]$InvokeCleanup
    )

    # No messaging context = no cancellation support
    if ($null -eq $MessagingContext) { return $false }

    # Check the flag
    if (-not (Test-FFUCancellationRequested -Context $MessagingContext)) {
        return $false
    }

    # Cancellation requested
    WriteLog "Cancellation detected at phase: $PhaseName"
    Write-FFUWarning -Context $MessagingContext `
        -Message "Build cancellation requested at: $PhaseName" `
        -Source 'BuildFFUVM'

    if ($InvokeCleanup) {
        Invoke-FailureCleanup -Reason "User cancelled build at: $PhaseName"
        Set-FFUBuildState -Context $MessagingContext -State Cancelled -SendMessage
    }

    return $true
}
```

### Example 2: Usage in BuildFFUVM.ps1

```powershell
# Source: Pattern for BuildFFUVM.ps1 phase boundaries
# Add after imports, before each major phase

# Example checkpoint before driver download
WriteLog "Phase: Downloading OEM Drivers"
if (Test-BuildCancellation -MessagingContext $MessagingContext -PhaseName "Driver Download" -InvokeCleanup) {
    return
}

# ... driver download code ...

# Example checkpoint before VHDX creation
WriteLog "Phase: Creating VHDX"
if (Test-BuildCancellation -MessagingContext $MessagingContext -PhaseName "VHDX Creation" -InvokeCleanup) {
    return
}
```

### Example 3: Proper Resource Registration

```powershell
# Source: Pattern already in BuildFFUVM.ps1 lines 3704, 3820, 4316
# Register immediately after creation
$VHDXPath = Join-Path $VMPath "$VMName.vhdx"
New-VHD -Path $VHDXPath -SizeBytes $Disksize
$vhdxCleanupId = Register-VHDXCleanup -VHDXPath $VHDXPath
WriteLog "Registered VHDX cleanup handler (ID: $vhdxCleanupId)"

# ... work with VHDX ...

# On successful completion, unregister
Unregister-CleanupAction -CleanupId $vhdxCleanupId
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| File-based cancellation flag | ConcurrentQueue + synchronized hashtable | FFU.Messaging 1.0.0 | Lock-free, faster |
| Manual cleanup in catch blocks | Cleanup registry pattern | FFU.Core 1.0.6 | Handles partial failures |
| Stop-Job only | Stop-Job + process tree kill | Current UI | Kills DISM, Office setup |

**Deprecated/outdated:**
- Polling log file for cancellation markers (slow, unreliable)
- `Stop-Job -PassThru | Remove-Job -Force` without cleanup (leaves resources)

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Cancel during DISM capture leaves partial FFU | MEDIUM | LOW | DISM is killed; partial files can be deleted |
| Cancel during VM operation leaves VM running | LOW | MEDIUM | Register-VMCleanup handles this |
| MessagingContext is null (CLI usage) | MEDIUM | NONE | Guard clauses handle gracefully |
| Cleanup action throws exception | LOW | LOW | Invoke-FailureCleanup continues on error |

## Open Questions

Things that couldn't be fully resolved:

1. **Should cleanup progress be shown in UI?**
   - What we know: UI currently shows "Cleaning environment..." static text
   - What's unclear: Would users benefit from detailed cleanup progress?
   - Recommendation: Keep simple for Phase 7; enhance in future if needed

2. **Should we add a "force cancel" option?**
   - What we know: Current flow waits for graceful stop, then force kills
   - What's unclear: Do users need a way to skip graceful shutdown?
   - Recommendation: Current behavior is sufficient; add if user feedback requests it

## Implementation Recommendations

### Phase 7 Scope (Minimal Viable)

1. **Add Test-BuildCancellation helper to FFU.Core** - Single function for consistent checking
2. **Add ~8 cancellation checkpoints to BuildFFUVM.ps1** - At phase boundaries
3. **Verify all resources have Register-*Cleanup calls** - Audit existing code
4. **Add unit tests for cancellation flow** - Pester tests with mocked context

### Out of Scope for Phase 7

- Cleanup progress reporting to UI (cosmetic)
- Persistent cleanup registry across crashes (complex, edge case)
- Cancellation during individual downloads (would require FFU.Common changes)
- Force cancel without cleanup option (not requested)

## Sources

### Primary (HIGH confidence)
- FFU.Messaging module code (`FFUDevelopment/Modules/FFU.Messaging/FFU.Messaging.psm1`)
- FFU.Core cleanup registry code (`FFUDevelopment/Modules/FFU.Core/FFU.Core.psm1`)
- BuildFFUVM_UI.ps1 cancel handler implementation (lines 210-420)
- UIIntegration-Example.ps1 (FFU.Messaging examples)

### Secondary (MEDIUM confidence)
- [Microsoft Learn: Stop-Job](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/stop-job?view=powershell-7.5)
- [Microsoft Learn: Canceling threads cooperatively](https://learn.microsoft.com/en-us/dotnet/standard/threading/canceling-threads-cooperatively)
- [Microsoft Learn: Cancellation in Managed Threads](https://learn.microsoft.com/en-us/dotnet/standard/threading/cancellation-in-managed-threads)

### Tertiary (LOW confidence)
- [PowerShell Forums: Clean up before exiting script](https://forums.powershell.org/t/clean-up-before-exiting-script/20605)
- [Cleaning Up PowerShell Jobs](https://jdhitsolutions.com/blog/powershell/8564/cleaning-up-powershell-jobs/)

## Metadata

**Confidence breakdown:**
- Current state analysis: HIGH - Verified by reading actual codebase
- Architecture patterns: HIGH - Based on existing FFU.Messaging design
- Pitfalls: MEDIUM - Derived from code analysis + general patterns
- Implementation recommendations: HIGH - Clear scope from existing infrastructure

**Research date:** 2026-01-19
**Valid until:** 60 days (stable domain, no external dependencies)
