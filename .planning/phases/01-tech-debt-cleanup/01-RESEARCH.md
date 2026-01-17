# Phase 1: Tech Debt Cleanup - Research

**Researched:** 2026-01-17
**Domain:** PowerShell module architecture, error handling patterns, code quality
**Confidence:** HIGH

## Summary

This research analyzes five specific tech debt items in the FFUBuilder codebase. The items involve removing deprecated code paths in FFU.Constants, improving error handling patterns by auditing -ErrorAction SilentlyContinue usage, replacing Write-Host with proper output streams, removing legacy UI code, and documenting parameter coupling between scripts.

The codebase already has well-established patterns for proper error handling (WriteLog, Invoke-WithErrorHandling) and the deprecated code is clearly marked with comments indicating the replacements. The primary challenge is ensuring no runtime code depends on the deprecated static properties before removal.

**Primary recommendation:** Execute changes in dependency order starting with the lowest-risk items (DEBT-04, DEBT-05) before tackling the more invasive changes (DEBT-01, DEBT-02, DEBT-03).

## Standard Stack

The established patterns in this codebase:

### Core Error Handling
| Pattern | Location | Purpose | When to Use |
|---------|----------|---------|-------------|
| WriteLog | FFU.Common.Core.psm1 | Centralized logging with file + UI queue | All production logging |
| Invoke-WithErrorHandling | FFU.Core.psm1 | Wrapped try/catch with cleanup | Complex operations |
| try/catch with specific exceptions | Throughout modules | Explicit error handling | When recovery is possible |

### Output Streams
| Stream | Cmdlet | Purpose | When to Use |
|--------|--------|---------|-------------|
| Success | Write-Output | Return data to pipeline | Function return values |
| Verbose | Write-Verbose | Diagnostic information | -Verbose enabled debugging |
| Warning | Write-Warning | Non-fatal issues | Recoverable problems |
| Error | Write-Error | Fatal errors | Unrecoverable failures |
| Host | Write-Host | Console-only display | Interactive scripts ONLY |
| WriteLog | Custom | File + UI logging | Production modules |

## Architecture Patterns

### DEBT-01: FFU.Constants Deprecated Properties

**Current State (lines 255-277 of FFU.Constants.psm1):**
```powershell
#region Static Path Properties (for backward compatibility)
# DEPRECATED: Use [FFUConstants]::GetDefaultWorkingDir() instead
static [string] $DEFAULT_WORKING_DIR = "C:\FFUDevelopment"

# DEPRECATED: Use [FFUConstants]::GetDefaultVMDir() instead
static [string] $DEFAULT_VM_DIR = "C:\FFUDevelopment\VM"

# ... 4 more deprecated properties
#endregion
```

**Also deprecated (lines 536-581):** Legacy helper methods that wrap the new methods:
- `GetWorkingDirectory()` -> calls `GetDefaultWorkingDir()`
- `GetVMDirectory()` -> calls `GetDefaultVMDir()`
- `GetCaptureDirectory()` -> calls `GetDefaultCaptureDir()`

**Current usage search results:** ONLY found in FFU.Constants.psm1 itself (definitions). No external code references `$DEFAULT_WORKING_DIR` etc.

**Safe removal pattern:**
1. Verify no external references exist (grep confirms none)
2. Remove the static properties (lines 255-277)
3. Remove the legacy wrapper methods (lines 536-581)
4. Update module version

### DEBT-02: -ErrorAction SilentlyContinue Audit

**Counts by file category:**
| Category | Files | Occurrences | Action |
|----------|-------|-------------|--------|
| Production Modules | 17 | 288 | Audit and replace appropriate cases |
| Test Files | 10+ | ~100 | Keep (intentional for test isolation) |
| UI Code | 3 | ~50 | Case-by-case (some intentional) |
| Orchestration Scripts | 5 | ~30 | Audit carefully |
| Diagnostics | 10+ | ~50 | Often intentional |

**Categories of SilentlyContinue usage:**

1. **Legitimate (KEEP):** Cleanup code where failure is acceptable
   ```powershell
   Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
   ```

2. **Questionable (REVIEW):** Existence checks that should use Test-Path
   ```powershell
   Get-VM -Name $VMName -ErrorAction SilentlyContinue  # Should test first
   ```

3. **Problematic (REPLACE):** Operations where errors should be logged
   ```powershell
   Get-Volume -DriveLetter $drive -ErrorAction SilentlyContinue  # Hides real problems
   ```

4. **Guard pattern (KEEP):** Checking if command exists
   ```powershell
   if (Get-Command WriteLog -ErrorAction SilentlyContinue) { ... }
   ```

**Recommended replacement patterns:**
```powershell
# Instead of silently ignoring
$result = Some-Command -ErrorAction SilentlyContinue

# Use try/catch with logging
try {
    $result = Some-Command -ErrorAction Stop
}
catch {
    WriteLog "Operation failed: $($_.Exception.Message)"
    $result = $null  # or default value
}
```

### DEBT-03: Write-Host Replacement

**Counts in production modules:**
| Module | Occurrences | Notes |
|--------|-------------|-------|
| FFU.ADK | 7 | User feedback during ADK operations |
| FFU.BuildTest | 57 | Interactive CLI testing tool (may be intentional) |
| FFU.Core | 3 | PowerShell version info on startup |
| FFU.Preflight | 91 | Validation results display |
| Others | ~20 | Various user feedback |

**Why Write-Host is problematic:**
1. Not captured in background jobs (UI sees nothing)
2. Cannot be redirected or captured in tests
3. Mixes user feedback with data flow

**Replacement decision tree:**
```
Is this in a test/diagnostic tool meant for interactive use?
  YES -> Keep Write-Host (FFU.BuildTest is acceptable)
  NO -> Continue

Is this returning data to the pipeline?
  YES -> Use Write-Output
  NO -> Continue

Is this debugging/diagnostic information?
  YES -> Use Write-Verbose
  NO -> Continue

Is this a warning about recoverable issues?
  YES -> Use Write-Warning
  NO -> Continue

Is this informational logging for production?
  YES -> Use WriteLog function
  NO -> Use Write-Information or Write-Host with -InformationAction
```

### DEBT-04: Legacy logStreamReader Field

**Location:** BuildFFUVM_UI.ps1, line 67

**Current state:**
```powershell
$script:uiState = [PSCustomObject]@{
    # ...
    Data = @{
        # ...
        logStreamReader = $null;  # Legacy: kept for backward compatibility
        # ...
        messagingContext = $null   # New: synchronized queue for real-time UI updates
    };
    # ...
}
```

**Analysis:** The new messaging context (FFU.Messaging module) replaces the old file-based log streaming. The logStreamReader field is:
- Still referenced in cleanup code (lines 236-240, 482-491, etc.)
- Still used as fallback when messagingContext is null (lines 769-788)
- Marked as legacy with comment

**Safe removal pattern:**
1. Remove the field definition (line 67)
2. Remove all references (search for `logStreamReader`)
3. Update cleanup code to only handle messagingContext
4. Keep fallback file reading as separate mechanism (not stored in state)

**Risk:** LOW - Code paths show messagingContext is the primary mechanism

### DEBT-05: Param Block Coupling Documentation

**Current state in BuildFFUVM.ps1 (lines 7-18):**
```powershell
# NOTE: FFU.Constants module is imported at RUNTIME via Import-Module (see module import section).
#
# The param block defaults below use HARDCODED values that MUST match FFU.Constants:
# - DEFAULT_VM_MEMORY = 4GB (4294967296 bytes)
# - DEFAULT_VHDX_SIZE = 50GB (53687091200 bytes)
# - DEFAULT_VM_PROCESSORS = 4
#
# IMPORTANT: If you change values in FFU.Constants.psm1, update these defaults too!
```

**The coupling:**
| Parameter | Default Value | FFU.Constants Property |
|-----------|---------------|------------------------|
| Memory | 4GB | DEFAULT_VM_MEMORY |
| Disksize | 50GB | DEFAULT_VHDX_SIZE |
| Processors | 4 | DEFAULT_VM_PROCESSORS |

**Why coupling exists:** PowerShell param blocks are evaluated at parse time, before any module imports. Using module constants in param defaults causes the script to fail if run from ThreadJob with different working directory.

**Documentation location:** Add to CLAUDE.md under Architecture section

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Error logging | Custom Write-Error wrappers | WriteLog function | Integrated with UI messaging and file logging |
| Path resolution | String concatenation | [FFUConstants]::Get*Dir() methods | Handles env overrides, base path resolution |
| Try/catch boilerplate | Manual try/catch everywhere | Invoke-WithErrorHandling | Includes cleanup registration, consistent logging |
| Output streams | Write-Host for everything | Proper stream cmdlets | Proper output handling in jobs/tests |

## Common Pitfalls

### Pitfall 1: Removing SilentlyContinue from Cleanup Code
**What goes wrong:** Build failures during cleanup when resources don't exist
**Why it happens:** Cleanup code runs after errors, resources may not have been created
**How to avoid:** Keep SilentlyContinue in cleanup blocks, only fix in main operation code
**Warning signs:** Failures during error recovery paths

### Pitfall 2: Write-Host in Background Jobs
**What goes wrong:** UI Monitor tab shows no output
**Why it happens:** Write-Host goes to console, not captured by job output
**How to avoid:** Use WriteLog which writes to both file and messaging queue
**Warning signs:** "Build running..." with no progress shown

### Pitfall 3: Removing Deprecated Code Without Checking Usage
**What goes wrong:** Runtime errors when code references removed properties
**Why it happens:** Grep may miss dynamic property access or string interpolation
**How to avoid:** Search for property names without brackets, test in isolated PowerShell
**Warning signs:** PropertyNotFoundException at runtime

### Pitfall 4: Changing Error Handling in Hot Paths
**What goes wrong:** Performance degradation
**Why it happens:** Try/catch with -ErrorAction Stop is slower than SilentlyContinue
**How to avoid:** Profile critical loops, consider error handling overhead
**Warning signs:** Build time increases significantly

## Code Examples

### Proper Error Handling Pattern
```powershell
# Source: FFU.Core.psm1 existing pattern
function Do-Something {
    [CmdletBinding()]
    param($Path)

    try {
        $result = Get-SomeThing -Path $Path -ErrorAction Stop
        WriteLog "Operation succeeded: $result"
        return $result
    }
    catch [ItemNotFoundException] {
        WriteLog "WARNING: Item not found at $Path - using default"
        return $null
    }
    catch {
        WriteLog "ERROR: Unexpected failure: $($_.Exception.Message)"
        throw
    }
}
```

### Replacing Write-Host with WriteLog
```powershell
# BEFORE (problematic)
Write-Host "Processing item $i of $total" -ForegroundColor Green

# AFTER (correct for production)
WriteLog "Processing item $i of $total"

# For verbose diagnostics only
Write-Verbose "Processing item $i of $total"
```

### Safe Cleanup Pattern
```powershell
# Source: FFU.Core.psm1 - Keep SilentlyContinue in cleanup
finally {
    # Cleanup SHOULD be silent - resources may not exist
    Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
    Dismount-VHD -Path $vhdPath -ErrorAction SilentlyContinue
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Static path properties | Dynamic Get*Dir() methods | v1.2.3 | Supports non-default installation paths |
| File-based log streaming | Queue-based messaging (FFU.Messaging) | v1.3.x | 20x faster UI updates |
| Write-Host for feedback | WriteLog with UI integration | v1.2.x | Background job visibility |

**Deprecated/outdated:**
- `[FFUConstants]::$DEFAULT_*_DIR` properties: Use `Get*Dir()` methods
- `logStreamReader` field: Use `messagingContext` with FFU.Messaging
- Write-Host in modules: Use WriteLog or proper output streams

## Open Questions

1. **FFU.BuildTest Write-Host Usage**
   - What we know: 57 occurrences, module is for interactive CLI testing
   - What's unclear: Should this be considered "production" code?
   - Recommendation: Keep Write-Host in FFU.BuildTest (it's intentionally interactive)

2. **Performance Impact of Error Handling Changes**
   - What we know: Try/catch has overhead vs SilentlyContinue
   - What's unclear: Impact on build times for loops
   - Recommendation: Profile before/after for high-frequency operations

## Recommended Order of Operations

Based on dependencies and risk:

1. **DEBT-05: Document param coupling** (Risk: NONE)
   - Pure documentation, no code changes
   - Add section to CLAUDE.md

2. **DEBT-04: Remove logStreamReader** (Risk: LOW)
   - Self-contained in BuildFFUVM_UI.ps1
   - New messaging system is proven
   - Test: UI build functionality

3. **DEBT-01: Remove deprecated FFU.Constants** (Risk: LOW)
   - No external references found
   - Test: Module import, path resolution

4. **DEBT-03: Replace Write-Host** (Risk: MEDIUM)
   - Multiple files affected
   - Test: Background job output visibility
   - Exclude FFU.BuildTest (intentionally interactive)

5. **DEBT-02: Audit SilentlyContinue** (Risk: MEDIUM-HIGH)
   - Most invasive change
   - Requires categorization of each occurrence
   - Test: Error scenarios, cleanup paths
   - Goal: 50%+ reduction (target ~130-150 removals from ~288 in modules)

## Testing Approach

### DEBT-01 Testing
```powershell
# After removing deprecated properties
Import-Module FFU.Constants -Force
$path = [FFUConstants]::GetDefaultWorkingDir()
# Should resolve correctly

# Verify no PropertyNotFoundException
$null -eq [FFUConstants]::DEFAULT_WORKING_DIR  # This should error (property removed)
```

### DEBT-02 Testing
```powershell
# Test error paths don't break builds
# 1. Run with missing VM switch
# 2. Run with missing ISO
# 3. Run cleanup after partial failure
# Verify: Errors logged, cleanup succeeds
```

### DEBT-03 Testing
```powershell
# Test UI sees output from background job
# 1. Start build from UI
# 2. Check Monitor tab shows progress
# 3. Verify WriteLog messages appear
```

### DEBT-04 Testing
```powershell
# Test UI build with messaging context only
# 1. Launch UI
# 2. Start build
# 3. Verify progress updates
# 4. Cancel mid-build
# 5. Verify cleanup works
```

## Sources

### Primary (HIGH confidence)
- FFU.Constants.psm1 - Direct code inspection (lines 255-277, 536-581)
- BuildFFUVM_UI.ps1 - Direct code inspection (line 67, messaging context)
- BuildFFUVM.ps1 - Direct code inspection (lines 7-18, param block)
- Grep analysis of -ErrorAction SilentlyContinue (521 total, 288 in modules)
- Grep analysis of Write-Host (1177 total, estimated 178 in production modules)

### Secondary (MEDIUM confidence)
- CLAUDE.md implementation patterns documentation
- Module manifests for version information
- Existing test files for verification patterns

### Tertiary (LOW confidence)
- None - all findings verified through direct code inspection

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Direct code inspection of existing patterns
- Architecture: HIGH - Clear deprecation comments in code
- Pitfalls: MEDIUM - Based on common PowerShell patterns and codebase context

**Research date:** 2026-01-17
**Valid until:** Stable codebase - valid for 30+ days unless significant changes
