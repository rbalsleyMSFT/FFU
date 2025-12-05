# Expand-WindowsImage Failure - Error 0x8007048F Fix

**Status:** FIXED
**Date:** November 2025
**Severity:** High
**Test:** `Tests/Test-WimAccessibilityAndRetry.ps1`
**Module:** `FFU.Imaging`

## Symptoms

VHDX creation fails with error 0x8007048F "The device is not connected" during `Expand-WindowsImage`:

- Error occurs after 3-5+ minutes of image expansion
- Log shows: `Creating VHDX Failed with error The device is not connected. (0x8007048F)`
- Build aborts during "Applying base Windows image to VHDX" phase

## Root Cause

During the long `Expand-WindowsImage` operation (3-5+ minutes), the mounted ISO can become unavailable:

1. **Windows auto-unmount** - ISOs that appear "idle" may be unmounted (even during active DISM operations)
2. **Network share timeout** - ISO on network share can timeout due to SMB session expiration
3. **USB drive sleep** - ISO on external USB drive may sleep or disconnect
4. **Antivirus blocking** - May temporarily block access to WIM file during scanning

## Solution Implemented

### New Functions Added (FFU.Imaging module)

| Function | Purpose |
|----------|---------|
| `Test-WimSourceAccessibility` | Validates WIM file and ISO mount status |
| `Invoke-ExpandWindowsImageWithRetry` | Expand-WindowsImage with validation and retry |

### Features

- Pre-flight WIM accessibility validation
- Automatic retry logic (up to 2 attempts)
- ISO re-mount capability on failure (when ISOPath provided)
- Detailed diagnostic output on failure
- Updated `New-OSPartition` with new `ISOPath` parameter

## Usage

### Automatic Usage (BuildFFUVM.ps1)

```powershell
# BuildFFUVM.ps1 now passes ISOPath to New-OSPartition for automatic recovery
$osPartition = New-OSPartition -VhdxDisk $disk -WimPath "F:\sources\install.wim" `
                               -WimIndex 3 -CompactOS $true -ISOPath "C:\ISOs\Win11.iso"
```

### Direct Function Usage

```powershell
# Validate WIM accessibility
$validation = Test-WimSourceAccessibility -WimPath "F:\sources\install.wim" -ISOPath "C:\ISOs\Win11.iso"
if (-not $validation.IsAccessible) {
    throw "WIM not accessible: $($validation.ErrorMessage)"
}

# Expand with retry
Invoke-ExpandWindowsImageWithRetry -ImagePath "F:\sources\install.wim" `
                                   -Index 3 `
                                   -ApplyPath "W:\" `
                                   -ISOPath "C:\ISOs\Win11.iso"
```

## Recommendations

1. **Use local SSD** - Store ISO files on local SSD (not network shares or USB drives)
2. **Antivirus exclusions** - Add exclusions for FFUDevelopment folder and ISO location
3. **Disable USB suspend** - Disable USB selective suspend in Windows power settings
4. **Network share timeouts** - Configure longer SMB session timeouts for network shares

## Testing

```powershell
# Run test suite
.\Tests\Test-WimAccessibilityAndRetry.ps1

# Optional: Test with actual ISO
.\Tests\Test-WimAccessibilityAndRetry.ps1 -TestISOPath "C:\ISOs\Win11.iso"
```

- Validates function exports and parameter requirements
- Tests error code detection (0x8007048F)
- Optional ISO mount validation tests

## Files Modified

- `FFU.Imaging.psm1` - Added validation and retry functions
- `BuildFFUVM.ps1` - Passes ISOPath to New-OSPartition

## Behavior Change

| Before | After |
|--------|-------|
| Expand-WindowsImage fails after 3-5 min | Pre-validation before starting |
| No retry mechanism | Automatic retry with ISO re-mount |
| Build aborts with cryptic error | Detailed diagnostics |
| Manual intervention required | Self-healing capability |
