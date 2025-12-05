# Testing Guide - BITS Authentication Fix

## How to Test the Fix with a Real FFU Build

This guide walks you through testing the BITS authentication fix (error 0x800704DD) in a real FFU build scenario.

---

## Prerequisites

### 1. System Requirements
- ✅ Windows 10/11 (with Hyper-V capability)
- ✅ Administrator privileges
- ✅ At least 50GB free disk space
- ✅ Internet connection (for downloads)

### 2. Hyper-V Requirement
FFU Builder requires Hyper-V. Check if enabled:

```powershell
Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All
```

**If not enabled**, run:
```powershell
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All -NoRestart
```
Then reboot your system.

### 3. Verify ThreadJob Module
```powershell
Get-Module -ListAvailable -Name ThreadJob
```

**If not installed**, it will be auto-installed when you launch the UI.

---

## Quick Test (Minimal Build - ~15 minutes)

This test focuses on verifying BITS downloads work without requiring a full FFU build.

### Step 1: Launch the UI

```powershell
# Navigate to FFUDevelopment directory
cd C:\claude\FFUBuilder\FFUDevelopment

# Launch the UI as Administrator
.\BuildFFUVM_UI.ps1
```

**Expected Output**:
- Window opens with WPF interface
- Check the UI log file at: `C:\claude\FFUBuilder\FFUDevelopment\FFUDevelopment_UI.log`

**Look for**:
```
ThreadJob module loaded successfully.
```

✅ **CHECKPOINT**: If you see this message, ThreadJob is working!

---

### Step 2: Configure Minimal Test Build

In the FFU Builder UI:

#### **Hyper-V Settings Tab**
1. **VM Name**: `FFU_Test_VM`
2. **Windows Release**: Select latest (e.g., `23H2`)
3. **VM Memory**: `4` GB (minimum for quick test)
4. **VM Processors**: `2`
5. **VM Switch**: Select an existing virtual switch

#### **Windows Settings Tab**
1. **Windows SKU**: Select `Windows 11 Pro` (or any edition)
2. **Windows Architecture**: `x64`
3. ✅ **Enable**: "Download Windows ISO" (this tests BITS transfers!)

#### **Updates Tab**
- ⬜ **Disable all updates** for this quick test

#### **Drivers Tab** (CRITICAL FOR TESTING)
Pick ONE OEM to test BITS downloads:

**Option A - Microsoft Surface** (fastest, smallest downloads):
1. ✅ **Enable**: "Apply Drivers"
2. **OEM**: Select `Microsoft`
3. **Model**: Select any Surface model (e.g., `Surface Laptop 5`)

**Option B - HP** (medium size):
1. ✅ **Enable**: "Apply Drivers"
2. **OEM**: Select `HP`
3. **Model**: Select any HP model (e.g., `HP EliteBook 840 G8`)

**Option C - Dell** (thorough test):
1. ✅ **Enable**: "Apply Drivers"
2. **OEM**: Select `Dell`
3. **Model**: Select any Dell model (e.g., `Latitude 7490`)

#### **Applications Tab**
- ⬜ **Disable all applications** for quick test

#### **Office Tab**
- ⬜ **Disable Office** for quick test

---

### Step 3: Start the Build

1. Click **"Build FFU"** button at the bottom
2. The button text changes to **"Cancel"** (build is running)

**Immediately check the log file**:
```powershell
# Open log in real-time (PowerShell)
Get-Content C:\claude\FFUBuilder\FFUDevelopment\FFUDevelopment.log -Wait -Tail 50

# Or open in Notepad++ / VS Code
code C:\claude\FFUBuilder\FFUDevelopment\FFUDevelopment.log
```

---

### Step 4: Monitor for Success Indicators

**Within 1-2 minutes**, you should see these log entries:

#### ✅ **ThreadJob Confirmation**
```
Build job started using ThreadJob (with network credential inheritance).
```

**If you see this instead**:
```
WARNING: Build job started using Start-Job (network credentials may not be available for BITS transfers).
```
⚠️ ThreadJob is not available. The fix won't work. Install ThreadJob manually (see troubleshooting).

---

#### ✅ **Windows ISO Download (BITS Transfer #1)**
```
Downloading Windows ISO from https://...
Successfully transferred https://... to C:\claude\FFUBuilder\FFUDevelopment\...
```

**If you see 0x800704DD here**:
```
BITS authentication error detected (0x800704DD: ERROR_NOT_LOGGED_ON).
```
❌ The fix is NOT working. Check troubleshooting section.

---

#### ✅ **Driver Catalog Download (BITS Transfer #2)**

**For Microsoft Surface**:
```
Downloading https://aka.ms/surface/DriverPackageCatalog...
Successfully transferred ...
```

**For HP**:
```
Downloading HP Driver cab from https://ftp.ext.hp.com/...
Successfully transferred ...
```

**For Dell**:
```
Downloading Dell Catalog cab file: https://downloads.dell.com/...
Successfully transferred ...
```

---

#### ✅ **Driver Package Download (BITS Transfer #3+)**
```
Downloading driver: https://[vendor-url]/[driver-package]...
Successfully transferred ...
Driver downloaded
```

**You should see multiple of these** (one per driver package).

---

### Step 5: Verify Success

**✅ ALL TESTS PASSED IF**:
1. "Build job started using ThreadJob" appears in log
2. Windows ISO downloads successfully (no 0x800704DD)
3. Driver catalog downloads successfully
4. At least 1 driver package downloads successfully
5. No errors mentioning "ERROR_NOT_LOGGED_ON" or "0x800704DD"

**At this point, you can cancel the build**:
- Click **"Cancel"** button in UI
- Select **"No"** when asked about removing downloads (keep them for verification)

---

## Full Build Test (~45-60 minutes)

If the quick test passes, you can run a complete build to verify everything works end-to-end.

### Recommended Full Test Configuration

#### **Hyper-V Settings**
- VM Name: `FFU_Full_Test`
- VM Memory: `8 GB` (recommended)
- VM Processors: `4`

#### **Windows Settings**
- SKU: `Windows 11 Pro`
- Architecture: `x64`
- ✅ Download Windows ISO

#### **Updates**
- ✅ Install Latest Cumulative Update
- ✅ Install .NET Cumulative Update
- ⬜ Disable Defender updates (optional, speeds up build)

#### **Drivers**
- ✅ Apply Drivers
- Select your actual hardware model (or any model for testing)

#### **Applications**
- ⬜ Disable (or enable 1-2 WinGet apps for testing)

#### **Office**
- ⬜ Disable (adds significant time)

### Expected Timeline
- ISO Download: 5-10 minutes (5-6 GB)
- Driver Downloads: 5-15 minutes (varies by OEM)
- VM Creation: 2-3 minutes
- Windows Installation in VM: 10-15 minutes
- Update Installation: 10-20 minutes
- FFU Capture: 5-10 minutes

**Total**: 45-60 minutes for full build

---

## What to Look For

### ✅ Success Indicators

**In FFUDevelopment.log**:
```
ThreadJob module loaded successfully.
Build job started using ThreadJob
Successfully transferred [URL] to [Path]
Driver downloaded
Update downloaded
FFU capture completed successfully
Build completed successfully
```

**In UI**:
- Progress bar advances smoothly
- Status text updates regularly
- No red error messages
- Build completes without cancellation

**On Disk**:
```powershell
# Check for successful FFU file
Get-ChildItem C:\claude\FFUBuilder\FFUDevelopment\FFU -Filter *.ffu

# Should show:
# Name                   Length
# ----                   ------
# FFU_Test_VM_[date].ffu [size in GB]
```

---

### ❌ Failure Indicators

**Error 0x800704DD (BITS Authentication Error)**:
```
Error: System.Runtime.InteropServices.COMException (0x800704DD):
The operation being requested was not performed because the user has not logged on to the network.
```

**Other BITS Errors**:
```
Failed to download [URL] after 3 attempts
Start-BitsTransfer failed with error [...]
```

**ThreadJob Not Used**:
```
WARNING: Build job started using Start-Job
```

---

## Troubleshooting

### Issue 1: ThreadJob Module Not Found

**Symptom**:
```
WARNING: Build job started using Start-Job (network credentials may not be available for BITS transfers).
```

**Solution**:
```powershell
# Manual installation
Install-Module -Name ThreadJob -Force -Scope CurrentUser

# Restart the UI
```

---

### Issue 2: Still Getting 0x800704DD

**Possible Causes**:

#### A. ThreadJob Not Actually Being Used
Check the log for "Build job started using ThreadJob". If it says "Start-Job", ThreadJob isn't working.

**Fix**: Ensure ThreadJob is imported:
```powershell
Import-Module ThreadJob -Force
Get-Command Start-ThreadJob  # Should return the command
```

#### B. Corporate Firewall/Proxy Blocking BITS
BITS may be blocked by corporate policies or proxy.

**Fix**: This requires Issue #327 (proxy support) to be implemented. For now, you can:
1. Disable VPN temporarily
2. Test from home network
3. Configure Windows proxy settings to allow BITS

#### C. Running Under Wrong User Context
BITS requires proper user authentication.

**Fix**: Ensure you're running PowerShell as Administrator with your actual Windows login (not a service account).

---

### Issue 3: Build Fails Later (Not BITS Related)

If BITS downloads work but build fails at VM creation, driver injection, or capture, that's a different issue (not related to this fix).

**Check**:
- Hyper-V is enabled and functional
- Virtual switch is configured correctly
- Sufficient disk space
- Windows ADK is installed

---

### Issue 4: Slow Downloads

**If downloads are working but very slow**:

BITS is working, but network speed is slow. This is normal if:
- Downloading large files (Windows ISO ~6GB)
- On slow internet connection
- During peak hours

**Not a bug**, just patience required.

---

## Advanced: Manual BITS Test

Test BITS directly without full build:

```powershell
# Import modules
cd C:\claude\FFUBuilder\FFUDevelopment
Import-Module .\FFU.Common -Force
Import-Module ThreadJob -Force

# Test BITS transfer in ThreadJob
$testJob = Start-ThreadJob -ScriptBlock {
    param($modulePath)
    Import-Module $modulePath -Force

    $testUrl = "https://go.microsoft.com/fwlink/?LinkId=866658"  # Small test file
    $testDest = "$env:TEMP\ffu_bits_manual_test.tmp"

    try {
        Start-BitsTransferWithRetry -Source $testUrl -Destination $testDest -Retries 2

        if (Test-Path $testDest) {
            Remove-Item $testDest -Force
            return "SUCCESS: BITS transfer worked in ThreadJob!"
        }
        else {
            return "FAIL: File not created"
        }
    }
    catch {
        return "FAIL: $($_.Exception.Message)"
    }
} -ArgumentList (Resolve-Path .\FFU.Common\FFU.Common.psd1).Path

# Wait and get result
$result = $testJob | Wait-Job | Receive-Job -AutoRemoveJob
Write-Host $result -ForegroundColor $(if ($result -like "SUCCESS*") { 'Green' } else { 'Red' })
```

**Expected Output**: `SUCCESS: BITS transfer worked in ThreadJob!`

---

## Verification Checklist

After testing, confirm:

- [ ] UI launched successfully
- [ ] "ThreadJob module loaded successfully" in UI log
- [ ] "Build job started using ThreadJob" in build log
- [ ] Windows ISO downloaded without errors
- [ ] Driver catalog downloaded without errors
- [ ] At least 1 driver package downloaded without errors
- [ ] **NO occurrences of "0x800704DD" in logs**
- [ ] **NO occurrences of "ERROR_NOT_LOGGED_ON" in logs**

**If all checked**: ✅ **Fix is working perfectly!**

---

## Quick Reference: Log File Locations

```
UI Log:    C:\claude\FFUBuilder\FFUDevelopment\FFUDevelopment_UI.log
Build Log: C:\claude\FFUBuilder\FFUDevelopment\FFUDevelopment.log
```

**Tail logs in PowerShell**:
```powershell
Get-Content C:\claude\FFUBuilder\FFUDevelopment\FFUDevelopment.log -Wait -Tail 20
```

**Search for errors**:
```powershell
Select-String -Path C:\claude\FFUBuilder\FFUDevelopment\FFUDevelopment.log -Pattern "0x800704DD"
Select-String -Path C:\claude\FFUBuilder\FFUDevelopment\FFUDevelopment.log -Pattern "ERROR_NOT_LOGGED_ON"
Select-String -Path C:\claude\FFUBuilder\FFUDevelopment\FFUDevelopment.log -Pattern "FAIL"
```

---

## Success Criteria

✅ **The fix is working if**:
1. ThreadJob is used for background jobs
2. All BITS transfers complete successfully
3. Zero occurrences of error 0x800704DD
4. Build progresses past driver download phase

---

## Reporting Results

After testing, please report back:

**If it worked**:
- ✅ "Fix confirmed working! All downloads succeeded."
- Share any interesting observations

**If it didn't work**:
- ❌ "Still getting 0x800704DD at [stage]"
- Attach relevant log excerpts
- Describe your environment (network, corporate proxy, etc.)

---

## Next Steps After Successful Test

1. **Report success** so we can proceed with confidence
2. **Continue using** the fixed version for your FFU builds
3. **Optionally**: Create PR to upstream repo to help others
4. **Next**: Fix other issues (#324, #319, #327, etc.)

---

**Good luck with testing! The fix should eliminate all 0x800704DD errors.** 🎉
