---
status: resolved
trigger: "Debug two issues: VMware Capture Boot GUI and FFU File Lock"
created: 2026-01-21T00:00:00Z
updated: 2026-01-21T00:00:00Z
resolved: 2026-01-21T00:00:00Z
---

## Current Focus

hypothesis: Two separate bugs with clear root causes identified
test: Both fixes implemented and verified
expecting: User testing to confirm fixes work
next_action: Run verification tests

## Symptoms

expected:
- Issue 1: VMware capture boot phase should respect ShowVMConsole setting like app installation phase does
- Issue 2: FFU file lock wait should be configurable and have retry logic

actual:
- Issue 1: Capture boot phase always uses nogui mode (line 2076 in FFU.Imaging.psm1 calls StartVM without ShowConsole parameter)
- Issue 2: Hardcoded 120-second wait with no retry logic; error occurred 37 seconds AFTER wait completed

errors:
- Issue 2: "FFU file is locked by another process: C:\FFUDevelopment\FFU\Win11_25H2_Ent_2026-01-21_1118.ffu"

reproduction:
- Issue 1: Build with VMware + InstallApps=true + ShowVMConsole=true - app install shows GUI, capture boot uses nogui
- Issue 2: Build with InstallDrivers=true or Optimize=true - 2min wait may not be enough, no retry

started: Present since VMware integration was added

## Eliminated

(None yet - investigation phase)

## Evidence

### Issue 1: VMware Capture Boot GUI

**Evidence 1: App installation phase correctly uses ShowVMConsole**

From log file (line 602-611):
- App installation correctly respects ShowVMConsole parameter
- Uses "vmrun gui" when ShowVMConsole=$true

Checked: BuildFFUVM.ps1 line 4720
Found: `$startVMStatus = $script:HypervisorProvider.StartVM($FFUVM, $ShowVMConsole)`
Implication: App installation phase correctly passes ShowVMConsole to StartVM

**Evidence 2: Capture boot phase ignores ShowVMConsole**

From log file (line 685-688):
- "Starting VM in headless mode (nogui) - use -ShowVMConsole $true to see console"
- "Executing: vmrun -T ws start ... nogui"

Checked: FFU.Imaging.psm1 line 2076
Found: `$HypervisorProvider.StartVM($VMInfo)` - NO ShowConsole parameter passed!
Implication: Root cause confirmed - StartVM called without $ShowConsole parameter

**Evidence 3: New-FFU function missing ShowVMConsole parameter**

Checked: FFU.Imaging.psm1 lines 1895-2027 (New-FFU function signature)
Found: No ShowVMConsole parameter defined
Implication: New-FFU function needs ShowVMConsole parameter added

**Evidence 4: Caller (BuildFFUVM.ps1) doesn't pass ShowVMConsole to New-FFU**

Checked: BuildFFUVM.ps1 lines 4958-4968 (New-FFU call)
Found: No ShowVMConsole parameter in call to New-FFU
Implication: Caller also needs to pass ShowVMConsole to New-FFU

**Evidence 5: VMwareProvider.StartVM supports ShowConsole parameter**

Checked: VMwareProvider.ps1 lines 265-325
Found: `[string] StartVM([VMInfo]$VM, [bool]$ShowConsole)` - Method signature supports ShowConsole
Implication: Provider already supports the feature, just not being used during capture

---

### Issue 2: FFU File Lock

**Evidence 1: Hardcoded 120-second wait with no configurability**

Checked: FFU.Imaging.psm1 lines 2270-2274
Found:
```powershell
#Without this 120 second sleep, we sometimes see an error when mounting the FFU due to a file handle lock.
If ($InstallDrivers -or $Optimize) {
    WriteLog 'Sleeping 2 minutes to prevent file handle lock'
    Start-Sleep 120
}
```
Implication: Wait time is hardcoded, no retry logic exists

**Evidence 2: No constant defined for this value**

Checked: FFU.Constants.psm1 (entire file)
Found: No FFU file lock wait constant exists
Implication: Should add FFU_FILE_LOCK_WAIT_SECONDS constant

**Evidence 3: Error occurs 37 seconds AFTER wait ends**

From log file:
- Line 1297-1298: "Most recent .ffu file: ... Sleeping 2 minutes to prevent file handle lock"
- Line 1312: Error occurred (timestamp shows ~37 seconds after 2min wait)
Implication: The wait completed, then something else grabbed the lock during Step 4 verification

**Evidence 4: File lock check exists in Invoke-FFUOptimizeWithScratchDir**

Checked: FFU.Imaging.psm1 lines 2671-2688
Found:
```powershell
# Step 4: Verify FFU file exists and is not locked
try {
    $fileStream = [System.IO.File]::Open($FFUFile, 'Open', 'Read', 'Read')
    $fileStream.Close()
    $fileStream.Dispose()
    WriteLog "FFU file is accessible and not exclusively locked"
}
catch {
    throw "FFU file is locked by another process: $FFUFile - $($_.Exception.Message)"
}
```
Implication: Check exists but has no retry logic

**Evidence 5: Test-FileLocked function exists in FFU.Updates**

Checked: FFU.Updates.psm1 lines 859-900
Found: `function Test-FileLocked` with proper lock detection
Implication: Reusable function exists; should use it with retry loop

**Evidence 6: Retry pattern already exists for similar operations**

Checked: FFU.Imaging.psm1 lines 2707-2775 (Invoke-FFUOptimizeWithScratchDir)
Found: `$MaxRetries = 3` with retry loop for DISM operations
Implication: Retry pattern already established in same function

---

## Resolution

### Root Cause Analysis

**Issue 1: VMware Capture Boot GUI**

**ROOT CAUSE:** The `New-FFU` function in `FFU.Imaging.psm1` does not accept a `ShowVMConsole` parameter, and at line 2076 it calls `$HypervisorProvider.StartVM($VMInfo)` without passing any ShowConsole value, which defaults to `$false` (nogui mode).

The app installation phase works correctly because it calls `StartVM($FFUVM, $ShowVMConsole)` directly in `BuildFFUVM.ps1`, but the capture boot phase goes through `New-FFU` which loses the ShowVMConsole context.

**Issue 2: FFU File Lock**

**ROOT CAUSE:** Two problems:
1. The 120-second wait time is hardcoded with no configuration option
2. No retry logic exists for the file lock check - it fails immediately if the file is locked at check time

The error occurred 37 seconds after the wait completed, suggesting:
- Either Windows Defender/antivirus scanned the FFU after the wait
- Or a background indexer grabbed the file handle
- The simple wait approach is insufficient for race conditions

---

## Proposed Fixes

### Issue 1: VMware Capture Boot GUI

**Files to modify:**

1. **FFU.Imaging.psm1** - Add ShowVMConsole parameter to New-FFU function
   - Location: Lines 1965-2027 (param block)
   - Add: `[Parameter(Mandatory = $false)][bool]$ShowVMConsole = $false`
   - Location: Line 2076
   - Change: `$HypervisorProvider.StartVM($VMInfo)` to `$HypervisorProvider.StartVM($VMInfo, $ShowVMConsole)`

2. **BuildFFUVM.ps1** - Pass ShowVMConsole to New-FFU calls
   - Location: Lines 4958-4968 (New-FFU call with InstallApps)
   - Add: `-ShowVMConsole $ShowVMConsole` parameter

3. **Config Schema** - Already has ShowVMConsole (no change needed)
   - Location: ffubuilder-config.schema.json lines 446-450
   - Default is `false` - consider changing to `true` per user request

4. **UI XAML** - Already has chkShowVMConsole checkbox (no change needed)
   - Location: BuildFFUVM_UI.xaml line 129
   - IsChecked="False" - consider changing to "True" per user request

**Default change recommendation:**
- Change `ShowVMConsole` default from `false` to `true`
- Users want to see what's happening by default
- Automation users can explicitly set to `false`

---

### Issue 2: FFU File Lock

**Files to modify:**

1. **FFU.Constants.psm1** - Add new constants
   - Add: `static [int] $FFU_FILE_LOCK_WAIT_SECONDS = 120`
   - Add: `static [int] $FFU_FILE_LOCK_RETRY_COUNT = 3`
   - Add: `static [int] $FFU_FILE_LOCK_RETRY_DELAY_SECONDS = 10`

2. **FFU.Imaging.psm1** - Implement retry logic
   - Location: Lines 2270-2275 (initial wait)
   - Replace hardcoded `Start-Sleep 120` with constant
   - Location: Lines 2671-2688 (file lock check in Invoke-FFUOptimizeWithScratchDir)
   - Add retry loop with configurable attempts

3. **BuildFFUVM.ps1** - Add parameter for configurable wait time
   - Add: `[int]$FFUFileLockWaitSeconds = 120` to param block
   - Pass to New-FFU function

4. **ffubuilder-config.schema.json** - Add new config options
   ```json
   "FFUFileLockWaitSeconds": {
       "type": "integer",
       "minimum": 30,
       "maximum": 600,
       "default": 120,
       "description": "Time in seconds to wait after FFU capture before accessing the file. Helps prevent file lock errors from antivirus or indexing services."
   },
   "FFUFileLockRetryCount": {
       "type": "integer",
       "minimum": 1,
       "maximum": 10,
       "default": 3,
       "description": "Number of retry attempts when FFU file is locked by another process."
   },
   "FFUFileLockRetryDelaySeconds": {
       "type": "integer",
       "minimum": 5,
       "maximum": 60,
       "default": 10,
       "description": "Delay in seconds between FFU file lock retry attempts."
   }
   ```

5. **BuildFFUVM_UI.xaml** - Add UI controls to VM Settings tab
   - Add new row after existing controls
   - Add numeric input for FFU File Lock Wait (seconds)
   - Add numeric input for retry count (optional - could be advanced setting)

6. **FFUUI.Core.Config.psm1** - Add config save/load for new settings

7. **FFUUI.Core.Initialize.psm1** - Register new controls

**Implementation pattern for retry logic:**

```powershell
# Step 4: Verify FFU file exists and is not locked (with retry)
WriteLog "Step 4/6: Verifying FFU file accessibility..."
$lockRetries = 0
$maxLockRetries = $FFUFileLockRetryCount
$fileLocked = $true

while ($fileLocked -and $lockRetries -lt $maxLockRetries) {
    $lockRetries++
    try {
        $fileStream = [System.IO.File]::Open($FFUFile, 'Open', 'Read', 'Read')
        $fileStream.Close()
        $fileStream.Dispose()
        $fileLocked = $false
        WriteLog "FFU file is accessible and not exclusively locked"
    }
    catch {
        if ($lockRetries -lt $maxLockRetries) {
            WriteLog "WARNING: FFU file is locked (attempt $lockRetries/$maxLockRetries). Waiting $FFUFileLockRetryDelaySeconds seconds..."
            Start-Sleep -Seconds $FFUFileLockRetryDelaySeconds
        }
        else {
            throw "FFU file is locked by another process after $maxLockRetries attempts: $FFUFile - $($_.Exception.Message)"
        }
    }
}
```

**Remediation guidance to add to error message:**

```powershell
WriteLog "============================================"
WriteLog "FFU FILE LOCK ERROR - POSSIBLE CAUSES"
WriteLog "============================================"
WriteLog "1. Windows Defender real-time scanning"
WriteLog "   Fix: Add exclusion for $FFUDevelopmentPath"
WriteLog "   Command: Add-MpPreference -ExclusionPath '$FFUDevelopmentPath'"
WriteLog ""
WriteLog "2. Windows Search indexer"
WriteLog "   Fix: Exclude FFU folder from indexing"
WriteLog ""
WriteLog "3. Another application has file open"
WriteLog "   Fix: Close any apps that may have the FFU open"
WriteLog ""
WriteLog "4. Antivirus software (non-Defender)"
WriteLog "   Fix: Add FFU folder and .ffu extension to exclusions"
WriteLog "============================================"
```

---

## UI Changes Summary

### VM Settings Tab Updates

**For Issue 1 (ShowVMConsole default):**
- Change `IsChecked="False"` to `IsChecked="True"` on line 129
- This makes GUI mode the default for VMware builds

**For Issue 2 (FFU File Lock settings):**
- Add new row to VM Settings grid (after existing VMware settings)
- Label: "FFU File Lock Wait (sec)"
- Control: NumericUpDown or TextBox with validation (30-600 range)
- Default: 120
- Tooltip: "Time to wait after FFU capture before accessing the file. Increase if experiencing file lock errors."

Optional advanced settings (could be in Advanced tab or hidden):
- FFU File Lock Retry Count (1-10, default 3)
- FFU File Lock Retry Delay (5-60 seconds, default 10)

### Grid Row Allocation

Current VM Settings tab has 16 RowDefinitions (rows 0-15). Need to add rows for:
- Row 16: FFU File Lock Wait (or reuse empty row if available)

---

## Files Changed Summary

| File | Issue | Change Type |
|------|-------|-------------|
| FFU.Imaging.psm1 | 1 | Add ShowVMConsole param to New-FFU, pass to StartVM |
| FFU.Imaging.psm1 | 2 | Use constants, add retry logic for file lock |
| BuildFFUVM.ps1 | 1 | Pass ShowVMConsole to New-FFU |
| BuildFFUVM.ps1 | 2 | Add FFUFileLockWaitSeconds param |
| FFU.Constants.psm1 | 2 | Add FFU_FILE_LOCK_* constants |
| ffubuilder-config.schema.json | 1 | Change ShowVMConsole default to true |
| ffubuilder-config.schema.json | 2 | Add FFUFileLockWaitSeconds, retry settings |
| BuildFFUVM_UI.xaml | 1 | Change chkShowVMConsole IsChecked to True |
| BuildFFUVM_UI.xaml | 2 | Add FFU file lock wait control |
| FFUUI.Core.Config.psm1 | 2 | Add config save/load for new settings |
| FFUUI.Core.Initialize.psm1 | 2 | Register new controls |
| FFU.Imaging.psd1 | 1,2 | Version bump and release notes |
| FFU.Constants.psd1 | 2 | Version bump |

---

## Version Updates Required

After implementation:
- FFU.Imaging: Bump version (new parameter + retry logic)
- FFU.Constants: Bump version (new constants)
- FFUUI.Core: Bump version (new config options)
- Main version.json: Bump PATCH (subcomponent changes)

---

## Test Plan

### Issue 1 Tests
1. VMware build with ShowVMConsole=true (default after fix)
   - Verify app installation shows GUI
   - Verify capture boot shows GUI
2. VMware build with ShowVMConsole=false
   - Verify both phases run headless
3. Hyper-V build (should not be affected)

### Issue 2 Tests
1. Normal build with default settings
   - Verify 120-second wait occurs
   - Verify retry logic doesn't interfere with successful builds
2. Simulate file lock (use handle.exe or similar)
   - Verify retry occurs
   - Verify proper error message after max retries
3. Configure longer wait time via UI
   - Verify config saves/loads correctly
   - Verify longer wait is applied

---

## Next Steps

1. Await approval for proposed fixes
2. Implement Issue 1 fixes (simpler, fewer files)
3. Implement Issue 2 fixes (more files, config changes)
4. Update version numbers
5. Run test plan
6. Update CHANGELOG_FORK.md
