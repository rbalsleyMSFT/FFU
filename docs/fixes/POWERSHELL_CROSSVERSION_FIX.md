# PowerShell Cross-Version Compatibility Fix

**Status:** FIXED
**Date:** November 2025
**Severity:** Critical
**Test:** `Test-PowerShell7Compatibility.ps1` (19 test cases)

## Symptoms

Build fails with error when running in PowerShell 7:
```
Could not load type 'Microsoft.PowerShell.Telemetry.Internal.TelemetryAPI'
```

The error occurs during local user management operations.

## Root Cause

PowerShell Core (7.x) `New-LocalUser`, `Get-LocalUser`, `Remove-LocalUser` cmdlets have TelemetryAPI compatibility issues. These cmdlets rely on internal APIs that differ between Windows PowerShell 5.1 and PowerShell Core 7.x.

## Solution Implemented

Cross-version compatible .NET APIs replace problematic cmdlets.

### Implementation Details

- Uses `System.DirectoryServices.AccountManagement` for local user management
- Works natively in both PowerShell 5.1 (Desktop) and PowerShell 7+ (Core)
- No version detection or relaunching required

### Helper Functions (FFU.VM Module)

| Function | Replaces | Purpose |
|----------|----------|---------|
| `Get-LocalUserAccount` | `Get-LocalUser` | Query local user using DirectoryServices API |
| `New-LocalUserAccount` | `New-LocalUser` | Create local user with secure password handling |
| `Remove-LocalUserAccount` | `Remove-LocalUser` | Remove local user using DirectoryServices API |

### Code Location

- Helper functions in `FFU.VM.psm1` (lines 20-201)
- Used by: `Set-CaptureFFU`, `Remove-FFUUserShare`, `Remove-FFUVM`

### Security Features

- SecureString password conversion with proper memory cleanup
- IDisposable pattern for PrincipalContext resources
- No plain-text password handling in memory

## Usage

The helper functions are used automatically by existing code:

```powershell
# Check if user exists
$userExists = Get-LocalUserAccount -Username "ffu_user"

# Create new local user
New-LocalUserAccount -Username "ffu_user" -Password $securePassword -Description "FFU Build User"

# Remove local user
Remove-LocalUserAccount -Username "ffu_user"
```

## Testing

```powershell
# Run the test suite (works in both PS5.1 and PS7+)
.\Tests\Test-PowerShell7Compatibility.ps1
```

- 19 test cases covering all scenarios
- 100% pass rate in both PowerShell 5.1 and 7+
- Validates helper function implementation and usage
- Confirms no cmdlet dependencies remain

## Files Modified

- `FFU.VM.psm1` - Added cross-version helper functions

## Behavior Change

| Before | After |
|--------|-------|
| Build fails with TelemetryAPI error in PS7 | Works natively in both PS5.1 and PS7+ |
| Required version detection/switching | No version detection needed |
| PS7 users had to run in PS5.1 | Seamless operation in preferred version |
