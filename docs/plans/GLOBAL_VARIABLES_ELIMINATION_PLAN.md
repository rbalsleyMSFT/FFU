# Global Variables Elimination Plan (Quick Win #3)

**Created:** 2025-11-24
**Status:** In Progress
**Priority:** High (Quick Win #3)
**Estimated Effort:** 1-2 days

---

## Problem Statement

**Global Variable Usage Found:** 4 active instances in production code
- `$global:LastKBArticleID` set in `FFU.Updates.psm1` (lines 363, 368)
- `$global:LastKBArticleID` read in `BuildFFUVM.ps1` (lines 1887, 1895, 1911, 1927)

**Impact:**
- Race conditions if multiple updates processed in parallel
- Difficult to track state changes across function calls
- Cannot test functions in isolation
- Non-reusable functions (depend on global state)
- No thread safety

**Root Cause:**
`Get-KBLink` function extracts KB article ID from Microsoft Update Catalog HTML
but only returns download links. The KB article ID is stored as a side effect
in a global variable for later use by calling code.

---

## Current Data Flow

```
BuildFFUVM.ps1 (line 1886):
  └─> Get-UpdateFileInfo()
        └─> Get-KBLink()
              ├─> Searches catalog
              ├─> Extracts KB article ID
              ├─> SETS: $global:LastKBArticleID = "KB1234567"  ❌
              └─> RETURNS: @( "http://link1", "http://link2" )
  └─> READS: $cuKbArticleId = $global:LastKBArticleID  ❌

Problems:
1. Side effect (setting global) separate from return value
2. Caller must know to read global variable after call
3. Value persists between calls (stale data risk)
4. No way to get KB ID for specific update in batch
```

---

## Proposed Solution

### Design: Return Structured Objects

Instead of returning just links, return objects with all metadata:

```powershell
# BEFORE (current)
Get-KBLink returns: @("http://link1", "http://link2")
Side effect: $global:LastKBArticleID = "KB1234567"

# AFTER (proposed)
Get-KBLink returns: [PSCustomObject]@{
    KBArticleID = "KB1234567"
    Links = @("http://link1", "http://link2")
}
```

### New Data Flow

```
BuildFFUVM.ps1:
  └─> Get-UpdateFileInfo()
        └─> Get-KBLink()
              ├─> Searches catalog
              ├─> Extracts KB article ID
              └─> RETURNS: [PSCustomObject]@{
                    KBArticleID = "KB1234567"
                    Links = @("http://link1", "http://link2")
                  }
        └─> RETURNS: @(
              [PSCustomObject]@{ Name = "file1.msu"; Url = "..."; KBArticleID = "KB1234567" }
              [PSCustomObject]@{ Name = "file2.msu"; Url = "..."; KBArticleID = "KB1234567" }
            )
  └─> READS: $cuKbArticleId = $cuUpdateInfos[0].KBArticleID  ✅

Benefits:
1. No side effects - pure function
2. Self-contained return value
3. Can get KB ID for each update in batch
4. Testable in isolation
5. Thread-safe
```

---

## Implementation Steps

### Step 1: Modify Get-KBLink Function

**File:** `Modules/FFU.Updates/FFU.Updates.psm1`
**Lines:** 306-425 (entire function)

**Changes:**
1. Change return type from array of strings to PSCustomObject
2. Return KB article ID along with links
3. Remove `$global:LastKBArticleID` assignment

**Before:**
```powershell
function Get-KBLink {
    # ... search catalog ...

    if ($results.Content -match '>\s*([^\(<]+)\(KB(\d+)\)') {
        $kbArticleID = "KB$($matches[2])"
        $global:LastKBArticleID = $kbArticleID  # ❌ REMOVE THIS
        WriteLog "Found KB article ID: $kbArticleID"
    }
    else {
        $global:LastKBArticleID = $null  # ❌ REMOVE THIS
    }

    # ... process links ...

    return $guids  # Array of URLs
}
```

**After:**
```powershell
function Get-KBLink {
    # ... search catalog ...

    $kbArticleID = $null
    if ($results.Content -match '>\s*([^\(<]+)\(KB(\d+)\)') {
        $kbArticleID = "KB$($matches[2])"
        WriteLog "Found KB article ID: $kbArticleID"
    }
    else {
        WriteLog "No KB article ID found in search results."
    }

    # ... process links ...

    # Return structured object
    return [PSCustomObject]@{
        KBArticleID = $kbArticleID
        Links = $guids
    }
}
```

---

### Step 2: Modify Get-UpdateFileInfo Function

**File:** `Modules/FFU.Updates/FFU.Updates.psm1`
**Lines:** 427-513 (entire function)

**Changes:**
1. Handle new return type from Get-KBLink
2. Add KBArticleID property to returned objects
3. Update documentation

**Before:**
```powershell
function Get-UpdateFileInfo {
    $updateFileInfos = [System.Collections.Generic.List[pscustomobject]]::new()

    foreach ($kb in $Name) {
        $links = Get-KBLink -Name $kb -Headers $Headers -UserAgent $UserAgent -Filter $Filter
        foreach ($link in $links) {
            # ... architecture matching ...

            if ($architectureMatch) {
                $updateFileInfos.Add([pscustomobject]@{
                    Name = $fileName
                    Url  = $link
                })
            }
        }
    }
    return $updateFileInfos
}
```

**After:**
```powershell
function Get-UpdateFileInfo {
    $updateFileInfos = [System.Collections.Generic.List[pscustomobject]]::new()

    foreach ($kb in $Name) {
        $kbResult = Get-KBLink -Name $kb -Headers $Headers -UserAgent $UserAgent -Filter $Filter

        # Extract KB article ID and links from structured result
        $kbArticleID = $kbResult.KBArticleID
        $links = $kbResult.Links

        foreach ($link in $links) {
            # ... architecture matching ...

            if ($architectureMatch) {
                $updateFileInfos.Add([pscustomobject]@{
                    Name = $fileName
                    Url  = $link
                    KBArticleID = $kbArticleID  # Add KB ID to each result
                })
            }
        }
    }
    return $updateFileInfos
}
```

**Update documentation:**
```powershell
.OUTPUTS
System.Collections.Generic.List[PSCustomObject] - Array of objects with Name, Url, and KBArticleID properties
```

---

### Step 3: Update BuildFFUVM.ps1

**File:** `BuildFFUVM.ps1`
**Lines:** 1887, 1895, 1911, 1927

**Changes:**
1. Read KBArticleID from returned objects
2. Remove dependency on global variable

**Before (4 instances):**
```powershell
# Line 1886-1887
(Get-UpdateFileInfo -Name $Name ...) | ForEach-Object { $cuUpdateInfos.Add($_) }
$cuKbArticleId = $global:LastKBArticleID  # ❌ REMOVE

# Line 1894-1895
(Get-UpdateFileInfo -Name $Name ...) | ForEach-Object { $cupUpdateInfos.Add($_) }
$cupKbArticleId = $global:LastKBArticleID  # ❌ REMOVE

# Line 1910-1911
(Get-UpdateFileInfo -Name $name ...) | ForEach-Object { $netUpdateInfos.Add($_) }
$netKbArticleId = $global:LastKBArticleID  # ❌ REMOVE

# Line 1926-1927
(Get-UpdateFileInfo -Name $Name ...) | ForEach-Object { $netUpdateInfos.Add($_) }
$netKbArticleId = $global:LastKBArticleID  # ❌ REMOVE
```

**After:**
```powershell
# Line 1886-1887
(Get-UpdateFileInfo -Name $Name ...) | ForEach-Object { $cuUpdateInfos.Add($_) }
$cuKbArticleId = if ($cuUpdateInfos.Count -gt 0) { $cuUpdateInfos[0].KBArticleID } else { $null }  # ✅

# Line 1894-1895
(Get-UpdateFileInfo -Name $Name ...) | ForEach-Object { $cupUpdateInfos.Add($_) }
$cupKbArticleId = if ($cupUpdateInfos.Count -gt 0) { $cupUpdateInfos[0].KBArticleID } else { $null }  # ✅

# Line 1910-1911
(Get-UpdateFileInfo -Name $name ...) | ForEach-Object { $netUpdateInfos.Add($_) }
$netKbArticleId = if ($netUpdateInfos.Count -gt 0) { $netUpdateInfos[0].KBArticleID } else { $null }  # ✅

# Line 1926-1927
(Get-UpdateFileInfo -Name $Name ...) | ForEach-Object { $netUpdateInfos.Add($_) }
$netKbArticleId = if ($netUpdateInfos.Count -gt 0) { $netUpdateInfos[0].KBArticleID } else { $null }  # ✅
```

**Note:** We get KB ID from first result since all results from same search have same KB ID.

---

## Testing Strategy

### Unit Tests

Create `Test-GlobalVariableElimination.ps1`:

```powershell
# Test 1: Get-KBLink returns structured object
$result = Get-KBLink -Name "KB5034441" -Headers $headers -UserAgent $ua -Filter @()
$result | Should -HaveProperty "KBArticleID"
$result | Should -HaveProperty "Links"
$result.Links | Should -BeOfType [array]

# Test 2: Get-UpdateFileInfo includes KBArticleID
$updates = Get-UpdateFileInfo -Name @("KB5034441") -WindowsArch 'x64' -Headers $headers -UserAgent $ua -Filter @()
$updates[0] | Should -HaveProperty "Name"
$updates[0] | Should -HaveProperty "Url"
$updates[0] | Should -HaveProperty "KBArticleID"

# Test 3: No global variable set
Remove-Variable -Name LastKBArticleID -Scope Global -ErrorAction SilentlyContinue
$result = Get-KBLink -Name "KB5034441" -Headers $headers -UserAgent $ua -Filter @()
Test-Path variable:global:LastKBArticleID | Should -Be $false

# Test 4: BuildFFUVM.ps1 reads KB ID from objects
# (Integration test - verify $cuKbArticleId populated correctly)
```

### Integration Tests

1. Run full build with UpdateLatestCU enabled
2. Verify KB article IDs captured correctly in logs
3. Verify no errors about undefined global variables
4. Verify FFU file naming includes KB ID correctly

### Regression Tests

1. Run existing Test-ParameterValidation.ps1
2. Run existing Test-ShortenedWindowsSKU.ps1
3. Verify all existing functionality preserved

---

## Backward Compatibility

**Breaking Changes:** None
- Function return types change, but callers updated simultaneously
- Internal implementation detail (global variable) removed
- No public API changes

**Migration Path:** None needed (all changes in same commit)

---

## Rollback Plan

If issues discovered:
1. Git revert to previous commit
2. Review specific failure scenarios
3. Fix issues in isolated branch
4. Re-apply with fixes

---

## Success Criteria

- [ ] No `$global:` references in FFU.Updates.psm1
- [ ] No `$global:` references in BuildFFUVM.ps1 (for LastKBArticleID)
- [ ] Get-KBLink returns structured object with KBArticleID and Links
- [ ] Get-UpdateFileInfo returns objects with Name, Url, and KBArticleID
- [ ] BuildFFUVM.ps1 reads KB IDs from returned objects
- [ ] All unit tests pass
- [ ] Full build completes successfully
- [ ] KB article IDs logged correctly

---

## Impact Assessment

**Reliability:** ✅ High Impact
- Eliminates race condition risk
- Makes functions pure (no side effects)
- Enables parallel processing in future

**Testability:** ✅ High Impact
- Functions can be tested in isolation
- No need to check global state
- Deterministic behavior

**Maintainability:** ✅ Medium Impact
- Clearer data flow
- Self-documenting return types
- Easier to understand

**Performance:** ✅ Neutral
- No performance impact (same operations)
- Slightly more memory for return objects (negligible)

---

## Related Issues

- Quick Win #3: Eliminate Global Variables
- Architecture Issue #3: Global Variable Usage (Critical)

---

**Document Status:** Active
**Next Update:** After implementation complete
