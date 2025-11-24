# Empty ShortenedWindowsSKU Parameter Error - Root Cause Analysis

**Date**: 2025-11-24
**Issue**: `Cannot bind argument to parameter 'ShortenedWindowsSKU' because it is an empty string`
**Status**: ⚠️ **CRITICAL - BUILD BLOCKER**

---

## Error Analysis

### Error Message
```
11/24/2025 9:44:17 AM Capturing FFU file failed with error Cannot bind argument to parameter 'ShortenedWindowsSKU' because it is an empty string.
```

### Log Context
```
11/24/2025 9:44:06 AM Mounting VHDX as read-only for optimization
11/24/2025 9:44:07 AM Optimizing VHDX in full mode...
11/24/2025 9:44:17 AM Dismounting VHDX
11/24/2025 9:44:17 AM Capturing FFU file failed with error Cannot bind argument to parameter 'ShortenedWindowsSKU' because it is an empty string.
```

**Key Observations:**
1. ✅ VM built successfully
2. ✅ VHDX optimized successfully
3. ✅ VHDX dismounted successfully
4. ❌ **FFU capture fails** due to empty ShortenedWindowsSKU parameter

---

## Root Cause

### Code Flow

**BuildFFUVM.ps1 (lines 2317-2323):**
```powershell
WriteLog "Shortening Windows SKU: $WindowsSKU for FFU file name"
$shortenedWindowsSKU = Get-ShortenedWindowsSKU -WindowsSKU $WindowsSKU
WriteLog "Shortened Windows SKU: $shortenedWindowsSKU"
#Create FFU file
New-FFU -InstallApps $InstallApps -FFUCaptureLocation $FFUCaptureLocation `
        -AllowVHDXCaching $AllowVHDXCaching -CustomFFUNameTemplate $CustomFFUNameTemplate `
        -ShortenedWindowsSKU $shortenedWindowsSKU -VHDXPath $VHDXPath `
        ...
```

**FFU.Core.psm1 - Get-ShortenedWindowsSKU function (lines 163-210):**
```powershell
function Get-ShortenedWindowsSKU {
    param (
        [string]$WindowsSKU
    )
    $shortenedWindowsSKU = switch ($WindowsSKU) {
        'Core' { 'Home' }
        'Home' { 'Home' }
        'Pro' { 'Pro' }
        'Enterprise' { 'Ent' }
        # ... 30+ more cases ...
        'Datacenter (Desktop Experience)' { 'Srv_Dtc_DE' }
    }
    return $shortenedWindowsSKU
}
```

**Problem:** If `$WindowsSKU` doesn't match ANY case in the switch statement:
- `$shortenedWindowsSKU` remains undefined/null
- Function returns empty string
- Empty string is passed to `New-FFU -ShortenedWindowsSKU ""`
- PowerShell parameter validation fails

**FFU.Imaging.psm1 - New-FFU function (line 591):**
```powershell
[Parameter(Mandatory = $true)]
[string]$ShortenedWindowsSKU,
```

The parameter is `Mandatory = $true` but only validates non-null, not non-empty.
Empty string `""` passes validation but causes errors downstream.

---

## Possible Reasons Why SKU Doesn't Match

### 1. ⭐ WindowsSKU Parameter is Empty or Null (MOST LIKELY)

**Evidence:**
- User may have not specified `-WindowsSKU` parameter
- Default value is 'Pro' (line 295), but could be overridden
- Config file might set it to empty string
- UI might pass empty value

**How to verify:**
```powershell
# Check what's being passed to Get-ShortenedWindowsSKU
# Look for log line: "Shortening Windows SKU: <value> for FFU file name"
```

**Expected log:** If this is the cause, log would show:
```
Shortening Windows SKU:  for FFU file name
Shortened Windows SKU:
```

---

### 2. SKU Name Not in Switch Statement

**Evidence:**
- Get-ShortenedWindowsSKU has 30+ cases
- But Windows has many more SKU variants
- New SKUs added in recent Windows versions may not be mapped

**How to verify:**
```powershell
# Check Windows edition on the ISO
Get-WindowsImage -ImagePath "path\to\install.wim" | Select-Object ImageName
```

**Missing SKUs examples:**
- Windows 11 Home for Workstations
- Windows 11 Pro for Gamers
- Custom OEM editions
- Insider/Preview editions

---

### 3. SKU Name Has Unexpected Format

**Evidence:**
- Switch statement is case-sensitive by default
- Extra whitespace could cause mismatch
- Localized edition names

**Examples:**
- `"Pro "` (trailing space) won't match `"Pro"`
- `"pro"` (lowercase) won't match `"Pro"`
- `"Professional Edition"` won't match `"Professional"`

---

### 4. Config File or UI Sets WindowsSKU to Empty

**Evidence:**
- BuildFFUVM.ps1 loads config from JSON (line 461)
- UI may pass empty string from dropdown
- Parameter override may set it to ""

**How config loading works:**
```powershell
if ($ConfigFile -and (Test-Path -Path $ConfigFile)) {
    $configData = Get-Content $ConfigFile -Raw | ConvertFrom-Json
    foreach ($key in $keys) {
        # Overwrites script parameters with config values
    }
}
```

---

### 5. WindowsSKU Detection Failed Earlier

**Evidence:**
- Script tries to detect SKU from WIM image (line 1964)
- Detection might fail and return empty
- No validation after detection

**Code:**
```powershell
if (-not($index) -and ($WindowsSKU)) {
    $index = Get-Index -WindowsImagePath $wimPath -WindowsSKU $WindowsSKU -ISOPath $ISOPath
}
```

---

## Two Solution Approaches

---

## Solution 1: Add Parameter Validation to New-FFU

### Approach
Add `[ValidateNotNullOrEmpty()]` attribute to catch empty strings at parameter binding.

### Implementation

**FFU.Imaging.psm1 (line 590-591):**
```powershell
[Parameter(Mandatory = $true)]
[ValidateNotNullOrEmpty()]
[string]$ShortenedWindowsSKU,
```

### Advantages
✅ Catches error immediately at parameter binding
✅ Clear error message: "Cannot validate argument on parameter 'ShortenedWindowsSKU'. The argument is null or empty"
✅ One-line fix
✅ No logic changes needed

### Disadvantages
⚠️ Doesn't fix root cause (Get-ShortenedWindowsSKU still returns empty)
⚠️ Error happens late in the build process (after optimization)
⚠️ Doesn't help user understand WHICH SKU failed
⚠️ Build still fails, just with better error message

---

## Solution 2: ⭐ Fix Get-ShortenedWindowsSKU to Never Return Empty (RECOMMENDED)

### Approach
- Add parameter validation to ensure WindowsSKU is not empty
- Add default case to switch statement
- Return original WindowsSKU if no match found (fallback)
- Log warning when unknown SKU encountered
- Add validation before calling Get-ShortenedWindowsSKU

### Implementation

**FFU.Core.psm1 - Get-ShortenedWindowsSKU (enhanced):**
```powershell
function Get-ShortenedWindowsSKU {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$WindowsSKU
    )

    # Trim whitespace for robust matching
    $WindowsSKU = $WindowsSKU.Trim()

    $shortenedWindowsSKU = switch ($WindowsSKU) {
        'Core' { 'Home' }
        'Home' { 'Home' }
        'Pro' { 'Pro' }
        # ... existing 30+ cases ...
        'Datacenter (Desktop Experience)' { 'Srv_Dtc_DE' }

        # DEFAULT CASE - Return original SKU if no match
        default {
            WriteLog "WARNING: Unknown Windows SKU '$WindowsSKU', using original name"
            $WindowsSKU
        }
    }

    return $shortenedWindowsSKU
}
```

**BuildFFUVM.ps1 (before calling Get-ShortenedWindowsSKU):**
```powershell
# Validate WindowsSKU before shortening
if ([string]::IsNullOrWhiteSpace($WindowsSKU)) {
    throw "WindowsSKU parameter is empty. Please specify a valid Windows edition (Pro, Enterprise, Education, etc.)"
}

WriteLog "Shortening Windows SKU: $WindowsSKU for FFU file name"
$shortenedWindowsSKU = Get-ShortenedWindowsSKU -WindowsSKU $WindowsSKU
WriteLog "Shortened Windows SKU: $shortenedWindowsSKU"
```

### Advantages
✅ **Fixes root cause** - Function never returns empty string
✅ **Graceful fallback** - Uses original SKU name if unknown
✅ **Early detection** - Validates before calling function
✅ **Clear logging** - Warns when unknown SKU encountered
✅ **Robust** - Handles edge cases (whitespace, new SKUs, etc.)
✅ **User-friendly** - Build continues with original SKU name
✅ **Future-proof** - Works with new Windows editions automatically

### Disadvantages
⚠️ Slightly more code (but more maintainable)
⚠️ Unknown SKU names might be long (but better than failing)

---

## Recommended Solution: **Solution 2 (Fix Get-ShortenedWindowsSKU)**

### Rationale

1. **Fixes root cause**, not just symptoms
2. **Graceful degradation** - Build continues instead of failing
3. **Better user experience** - Clear warning about unknown SKU
4. **Future-proof** - Handles new Windows editions without code changes
5. **Robust** - Handles all edge cases (empty, whitespace, unknown SKUs)
6. **Fail fast** - Validates early before optimization (saves time)

### Why Not Solution 1?

- Only adds validation, doesn't fix the empty string issue
- Build still fails at the same point
- Doesn't help with unknown SKUs
- User still needs to manually investigate

---

## Implementation Plan

### Step 1: Enhance Get-ShortenedWindowsSKU Function
- Add parameter validation (`[ValidateNotNullOrEmpty()]`)
- Add `.Trim()` to remove whitespace
- Add `default` case to switch statement
- Add warning log for unknown SKUs
- Return original SKU name as fallback

### Step 2: Add Pre-Flight Validation in BuildFFUVM.ps1
- Check WindowsSKU before calling Get-ShortenedWindowsSKU
- Throw clear error if empty
- Log the SKU value being processed

### Step 3: Add Validation to New-FFU Parameter (Defense in Depth)
- Add `[ValidateNotNullOrEmpty()]` to ShortenedWindowsSKU parameter
- Provides second layer of protection

### Step 4: Create Regression Tests
- Test Get-ShortenedWindowsSKU with all known SKUs
- Test with empty string (should throw)
- Test with unknown SKU (should return original)
- Test with whitespace (should trim and match)
- Test full Build process with unknown SKU

---

## Success Criteria

✅ Get-ShortenedWindowsSKU never returns empty string
✅ Clear error message if WindowsSKU is empty
✅ Warning logged for unknown SKUs
✅ Build succeeds with unknown SKU (uses original name)
✅ All known SKUs still map correctly
✅ Whitespace handled correctly
✅ All tests pass

---

## Testing Plan

### Unit Tests for Get-ShortenedWindowsSKU

```powershell
# Test known SKUs
Get-ShortenedWindowsSKU -WindowsSKU "Pro" | Should -Be "Pro"
Get-ShortenedWindowsSKU -WindowsSKU "Enterprise" | Should -Be "Ent"

# Test with whitespace
Get-ShortenedWindowsSKU -WindowsSKU "  Pro  " | Should -Be "Pro"

# Test unknown SKU (should return original)
Get-ShortenedWindowsSKU -WindowsSKU "CustomEdition" | Should -Be "CustomEdition"

# Test empty (should throw)
{ Get-ShortenedWindowsSKU -WindowsSKU "" } | Should -Throw

# Test null (should throw)
{ Get-ShortenedWindowsSKU -WindowsSKU $null } | Should -Throw
```

### Integration Test

```powershell
# Test full build with unknown SKU
.\BuildFFUVM.ps1 -WindowsSKU "TestEdition" -WindowsRelease 11
# Should complete successfully with warning
```

---

**Analysis Complete**: 2025-11-24
**Next Step**: Implement Solution 2 (Fix Get-ShortenedWindowsSKU with default case)
