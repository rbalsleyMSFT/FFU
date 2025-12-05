# cmd.exe Path Quoting Error Fix

**Status:** FIXED
**Date:** November 2025
**Severity:** High
**Test:** `Tests/Test-CmdPathQuoting.ps1` (15 test cases)

## Symptoms

Commands fail with error:
```
'C:\Program' is not recognized as an internal or external command
```

Occurs when:
- Calling ADK tools (copype, DandISetEnv.bat) from `cmd /c`
- Running FFU capture, optimization, or WinPE media creation
- ADK is installed in default path: `C:\Program Files (x86)\Windows Kits\10\...`

## Root Cause

When using `cmd /c` to execute batch files with paths containing spaces followed by `&&` for command chaining, the quotes are not handled correctly.

cmd.exe parses:
```cmd
"C:\Program Files\script.bat" && other_command
```

Incorrectly, treating only `C:\Program` as the command.

## Solution Implemented

Use the `call` command before the batch file path. `call` tells cmd.exe to execute the batch file properly before processing chained commands.

### Correct Pattern

```powershell
# WRONG (fails with paths containing spaces):
cmd /c "$DandIEnv" && dism /optimize-ffu ...

# CORRECT (using 'call' command):
cmd /c call "$DandIEnv" && dism /optimize-ffu ...
```

### Example Fix

```powershell
# Before (broken):
$copypeOutput = & cmd /c """$DandIEnvPath"" && copype amd64 ""$DestinationPath"" 2>&1"

# After (fixed):
$copypeOutput = & cmd /c "call `"$DandIEnvPath`" && copype amd64 `"$DestinationPath`"" 2>&1
```

## Why 'call' Works

The `call` command in cmd.exe:
1. Executes a batch file as a subroutine
2. Properly handles the quoted path
3. Returns control to process `&&` chained commands
4. Without `call`, cmd.exe attempts to parse the entire quoted path as multiple arguments

## Files Fixed

| File | Locations | Commands |
|------|-----------|----------|
| `FFU.Imaging.psm1` | 3 | DISM capture and FFU optimization |
| `FFU.Media.psm1` | 2 | copype amd64/arm64 |
| `Create-PEMedia.ps1` | 2 | copype amd64/arm64 |

## Testing

```powershell
# Run test suite
.\Tests\Test-CmdPathQuoting.ps1
```

- 15 test cases validating correct quoting patterns
- Functional tests with actual paths containing spaces
- Verifies 'call' command is used in all relevant locations

## Behavior Change

| Before | After |
|--------|-------|
| ADK commands fail on standard installations | All ADK commands work correctly |
| Path with spaces causes failure | Handles any installation path |
| Silent failures with cryptic errors | Reliable execution |
