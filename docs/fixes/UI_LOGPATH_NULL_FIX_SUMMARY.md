# UI Log Path Null Fix Summary

## Problem Description

**Error Message:**
```
The build process failed. No log file was created (expected at ).
This usually indicates an early failure before logging started.
Error: Value cannot be null. (Parameter 'The provided Path argument was null or an empty collection.')
```

**Context:**
- FFUDevelopment.log showed successful build completion (57 minutes)
- Error appeared when UI tried to verify build success after job completed
- Path was empty after "expected at )" in error message

## Root Cause Analysis

The bug was in `BuildFFUVM_UI.ps1` at line 686 inside the Timer's Tick event handler:

```powershell
# BUGGY CODE (line 686):
$mainLogPath = Join-Path $config.FFUDevelopmentPath "FFUDevelopment.log"
```

**Why it failed:**
1. `$config` is a **local variable** defined in the button click handler (line 439)
2. The Timer's Tick handler is a scriptblock that runs **asynchronously** when the timer fires
3. When the build job completes (after 57+ minutes), the button click handler's scope has long since ended
4. `$config` is **no longer accessible** from within the timer's scriptblock
5. `$config.FFUDevelopmentPath` evaluates to `$null`
6. `Join-Path $null "FFUDevelopment.log"` produces an empty/invalid path

**Key insight:** The timer handler correctly uses `$script:uiState.XXX` for all other state access (29 occurrences), but this one line used a local variable.

## Solution Implemented

Changed line 686-687 to use the script-scoped state variable:

```powershell
# FIXED CODE:
# NOTE: Use script-scoped uiState.FFUDevelopmentPath (not $config which is out of scope in this timer handler)
$mainLogPath = Join-Path $script:uiState.FFUDevelopmentPath "FFUDevelopment.log"
```

**Why this works:**
- `$script:uiState.FFUDevelopmentPath` is defined at script initialization (line 38)
- Script-scoped variables are accessible from any scriptblock within the script
- This is the same pattern used for all other state access in the timer handler

## Files Modified

| File | Change |
|------|--------|
| `BuildFFUVM_UI.ps1` | Line 686-687: Changed `$config.FFUDevelopmentPath` to `$script:uiState.FFUDevelopmentPath` |

## Test Coverage

**Test Script:** `Test-UILogPathFix.ps1`

8 tests covering:
- Correct path variable usage in timer handler
- No out-of-scope `$config` references in timer
- Explanatory comment presence
- Script-level variable definition
- Scriptblock scope behavior simulation
- Path construction validity
- Consistent script-scope usage pattern
- No `$config` references in timer handler

**Results:** 100% pass rate (8/8 tests)

## New Behavior

### Before Fix
```
Timer fires after 57-minute build:
  $config → null (out of scope)
  $mainLogPath = Join-Path $null "FFUDevelopment.log" → ""
  Error: "No log file was created (expected at )"
```

### After Fix
```
Timer fires after 57-minute build:
  $script:uiState.FFUDevelopmentPath → "C:\FFUDevelopment" (always accessible)
  $mainLogPath = "C:\FFUDevelopment\FFUDevelopment.log"
  Test-Path finds log file
  Success: "FFU build completed successfully."
```

## Scope Rule for Timer Handlers

**Important:** When using WPF DispatcherTimer in PowerShell:

| Variable Type | Accessible from Timer Handler? |
|--------------|-------------------------------|
| `$script:uiState.XXX` | Yes - script scope persists |
| `$local:variable` | No - function scope ends |
| `$buttonHandler.variable` | No - outer function scope ends |
| `$sender`, `$e` | Yes - timer event parameters |

**Best Practice:** Always use `$script:` scoped variables for state that needs to persist across asynchronous operations.

## Date
November 26, 2025
