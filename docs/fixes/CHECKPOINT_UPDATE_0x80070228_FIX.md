# DISM Error 0x80070228 - Checkpoint Cumulative Update Fix

**Status:** FIXED (v1.0.2)
**Date:** December 2025
**Severity:** Critical
**Test:** `Tests/Test-CheckpointUpdateFix.ps1` (12 test cases)
**Module:** `FFU.Updates`

## Symptoms

DISM fails when applying Windows 11 24H2/25H2 cumulative updates with error:
```
DISM Package Manager: Failed getting the download request. - CDISMPackageManager::ProcessWithUpdateAgent(hr:0x80070228)
Failed to install UUP package. - CMsuPackage::DoInstall(hr:0x80070228)
Failed to apply the MSU unattend file to the image.
```

Affects packages like KB5043080 and other checkpoint cumulative updates.

## Root Cause

**UUP (Unified Update Platform) packages** like KB5043080 checkpoint updates trigger Windows Update Agent to download additional content. When DISM applies MSU files:

1. DISM extracts MSU to mounted image's temp folder
2. UpdateAgent tries to download content from Windows Update
3. Offline mounted images have no network access
4. Download fails with 0x80070228 "Failed getting the download request"

## Solution Implemented (v1.0.2)

**Direct CAB Application** - Extract CAB files from MSU and apply directly. CAB files don't trigger the UpdateAgent mechanism.

### Why This Works

| Component | Mechanism | Network Required |
|-----------|-----------|------------------|
| MSU via DISM | UpdateAgent | Yes (for UUP) |
| CAB directly | Package Manager | No |

MSU files are containers:
```
MSU Package
├── Main_Update.cab  ← Apply this directly (no network needed)
├── WSUSSCAN.cab     ← Skip (metadata only)
└── other metadata
```

### Implementation

1. MSU is already expanded (for unattend.xml extraction)
2. Find CAB files (excluding WSUSSCAN.cab metadata)
3. Apply each CAB directly with `Add-WindowsPackage`
4. Fall back to isolated MSU if no CAB files found

### Code Flow

```powershell
# Find CAB files in extracted MSU
$cabFiles = Get-ChildItem -Path $extractPath -Filter "*.cab" |
    Where-Object { $_.Name -notmatch 'WSUSSCAN' }

# Apply CAB directly (bypasses UUP)
foreach ($cabFile in $cabFiles) {
    Add-WindowsPackage -Path $Path -PackagePath $cabFile.FullName
}
```

## Testing

```powershell
# Run test suite
.\Tests\Test-CheckpointUpdateFix.ps1 -FFUDevelopmentPath "C:\FFUDevelopment"
```

- 12 test cases validating implementation
- Tests UUP documentation, CAB extraction, WSUSSCAN exclusion
- Validates fallback mechanism and error handling

## Version History

| Version | Approach | Result |
|---------|----------|--------|
| 1.0.1 | Isolated MSU directory | Partial - didn't fix UUP download |
| 1.0.2 | Direct CAB application | Success - bypasses UUP entirely |

## Files Modified

- `FFU.Updates.psm1` - Enhanced `Add-WindowsPackageWithUnattend` function

## Reference

- Microsoft Q&A: https://learn.microsoft.com/en-us/answers/questions/3855149/

## Behavior Change

| Before | After |
|--------|-------|
| KB5043080 fails with 0x80070228 | Updates apply successfully |
| UUP packages require network | Offline application works |
| Silent failures | Clear logging of CAB application |
