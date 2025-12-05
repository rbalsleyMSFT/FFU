# Quick Test Steps - BITS Authentication Fix

## 🚀 Fast Track Test (15 minutes)

### Step 1: Launch UI (as Administrator)
```powershell
cd C:\claude\FFUBuilder\FFUDevelopment
.\BuildFFUVM_UI.ps1
```

### Step 2: Check UI Log Immediately
```powershell
# In another PowerShell window
Get-Content .\FFUDevelopment_UI.log -Wait -Tail 10
```

✅ **Look for**: `ThreadJob module loaded successfully.`

---

### Step 3: Configure Minimal Build

**In the UI**:
- **Hyper-V Tab**: VM Name = `FFU_Test`, Memory = `4 GB`, Processors = `2`
- **Windows Tab**: SKU = `Windows 11 Pro`, Architecture = `x64`, ✅ Download ISO
- **Updates Tab**: ⬜ Disable all
- **Drivers Tab**: ✅ Enable, OEM = `Microsoft`, Model = any Surface model
- **Applications Tab**: ⬜ Disable all
- **Office Tab**: ⬜ Disable

---

### Step 4: Start Build & Monitor

Click **"Build FFU"**

**Open build log**:
```powershell
Get-Content .\FFUDevelopment.log -Wait -Tail 20
```

---

### Step 5: Watch for These Messages

#### ✅ Must See (within 2 minutes):
```
Build job started using ThreadJob (with network credential inheritance).
```

```
Successfully transferred https://... to ...
```

#### ❌ Must NOT See:
```
0x800704DD
ERROR_NOT_LOGGED_ON
```

---

### Step 6: Result

**If you see ✅ messages**:
- **SUCCESS!** Fix is working
- You can cancel the build now (keep downloads)

**If you see ❌ messages**:
- **PROBLEM** - Check troubleshooting in TESTING_GUIDE.md

---

## 📝 Quick Troubleshooting

### Problem: "WARNING: Build job started using Start-Job"
**Fix**:
```powershell
Install-Module -Name ThreadJob -Force -Scope CurrentUser
# Restart UI
```

### Problem: Still getting 0x800704DD
**Check**:
1. Is ThreadJob actually installed? `Get-Module -ListAvailable ThreadJob`
2. Are you running as Administrator?
3. Corporate proxy blocking? Try from home network

---

## ✅ Success Checklist

- [ ] ThreadJob loaded in UI log
- [ ] "Build job started using ThreadJob" in build log
- [ ] Windows ISO downloads successfully
- [ ] Driver catalog downloads successfully
- [ ] NO 0x800704DD errors

**All checked = Fix working!** 🎉

---

## 📞 Need Help?

See **TESTING_GUIDE.md** for detailed instructions and troubleshooting.
