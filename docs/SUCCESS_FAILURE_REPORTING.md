# FFU Builder Success/Failure Reporting Architecture

This document explains how `BuildFFUVM.ps1` and `BuildFFUVM_UI.ps1` communicate success and failure states to the user.

## Overview

The FFU Builder uses a **PowerShell Background Job** pattern for long-running builds. The UI launches the build script as a background job and monitors its state through:

1. **Job State Monitoring** - PowerShell job states (`Completed`, `Failed`, `Stopped`)
2. **Error Stream Capture** - Non-terminating errors via `Receive-Job -ErrorVariable`
3. **Log File Parsing** - Real-time progress updates via `[PROGRESS]` markers
4. **Log File Existence Check** - Early failure detection

## Communication Flow

```
BuildFFUVM_UI.ps1                           BuildFFUVM.ps1
       |                                           |
       |--- Start-ThreadJob ------------------->   |
       |                                           |
       |    [DispatcherTimer polls every 500ms]    |
       |                                           |
       |<--- Writes to FFUDevelopment.log ------   |
       |     [PROGRESS] 25 | Applying updates...   |
       |                                           |
       |<--- WriteLog messages -----------------   |
       |                                           |
       |    [On error: throw or Write-Error]       |
       |                                           |
       |<--- Job.State changes to terminal -----   |
       |     ('Completed', 'Failed', 'Stopped')    |
       |                                           |
       |--- Receive-Job -ErrorVariable ----------> |
       |                                           |
       v                                           v
   Determine Success/Failure
```

## BuildFFUVM.ps1 - How It Reports Status

### 1. Progress Reporting

Progress is reported through the `Set-Progress` function (defined in `FFU.Common.Core.psm1`):

```powershell
function Set-Progress {
    param(
        [int]$Percentage,
        [string]$Message
    )
    WriteLog "[PROGRESS] $Percentage | $Message"
}
```

**Progress milestones in BuildFFUVM.ps1:**

| Percentage | Stage |
|------------|-------|
| 1% | FFU build process started |
| 2% | Validating parameters |
| 3% | Processing drivers |
| 5% | Validating ADK installation |
| 6% | Downloading and preparing applications |
| 10% | Creating Apps ISO |
| 11% | Checking for required Windows Updates |
| 12% | Downloading Windows Updates |
| 15% | Creating VHDX and applying base Windows image |
| 16% | Applying base Windows image to VHDX |
| 25% | Applying Windows Updates to VHDX |
| 40% | Finalizing VHDX |
| 41% | Starting VM for app installation |
| 45% | Creating WinPE capture media |
| 50% | Installing applications in VM |
| 65% | Optimizing VHDX before capture |
| 68% | Capturing FFU from VM/VHDX |
| 75% | Injecting drivers into FFU |
| 81% | Starting FFU capture from VHDX |
| 85% | Optimizing FFU |
| 90% | FFU post-processing complete |
| 91% | Creating deployment media |
| 95% | Building USB drive |
| 99% | Finalizing and cleaning up |
| 100% | Build process complete |

### 2. Success Reporting

**BuildFFUVM.ps1 signals success implicitly** by:
- Reaching the end of the script without throwing an unhandled exception
- Writing `Set-Progress -Percentage 100 -Message "Build process complete."`
- Writing `WriteLog 'Script complete'`

The script does NOT explicitly return a success value. Success is determined by:
- Job State = `Completed`
- Error stream is empty (`$jobErrors.Count -eq 0`)
- Log file exists

### 3. Failure Reporting

**BuildFFUVM.ps1 signals failure** by:

1. **Throwing terminating errors** - Sets job state to `Failed`
   ```powershell
   throw "InstallApps must also be set to `$true"
   throw "Driver folder path contains spaces"
   throw $_  # Re-throw caught exceptions
   ```

2. **Calling exit** - Sets job state to `Completed` but the script exits early
   ```powershell
   exit 1  # Used in some error paths
   exit    # Used in some early termination paths
   ```

3. **Non-terminating errors** - Job state remains `Completed` but errors are captured
   ```powershell
   Write-Error "Installation failed"
   # Or Remove-Item without -ErrorAction produces non-terminating errors
   ```

## BuildFFUVM_UI.ps1 - How It Detects Status

### Job Launch

The UI uses `Start-ThreadJob` (preferred) or `Start-Job` (fallback):

```powershell
if (Get-Command Start-ThreadJob -ErrorAction SilentlyContinue) {
    $script:uiState.Data.currentBuildJob = Start-ThreadJob -ScriptBlock $scriptBlock -ArgumentList @($buildParams, $PSScriptRoot)
} else {
    $script:uiState.Data.currentBuildJob = Start-Job -ScriptBlock $scriptBlock -ArgumentList @($buildParams, $PSScriptRoot)
}
```

### Real-Time Monitoring (DispatcherTimer)

A timer polls every 500ms to:

1. **Read new log lines** from `FFUDevelopment.log`
2. **Parse progress markers** using regex: `\[PROGRESS\] (\d{1,3}) \| (.*)`
3. **Update UI elements**:
   - Progress bar (`pbOverallProgress.Value`)
   - Status text (`txtStatus.Text`)
   - Log viewer (`lstLogOutput`)

```powershell
if ($line -match '\[PROGRESS\] (\d{1,3}) \| (.*)') {
    $percentage = [double]$matches[1]
    $message = $matches[2]
    $script:uiState.Controls.pbOverallProgress.Value = $percentage
    $script:uiState.Controls.txtStatus.Text = $message
}
```

### Final Status Determination

When job reaches terminal state (`Completed`, `Failed`, or `Stopped`):

```powershell
# Capture job output and errors
$jobOutput = Receive-Job -Job $currentJob -Keep -ErrorVariable jobErrors -ErrorAction SilentlyContinue

# Determine if there were errors
$hasErrors = ($jobErrors.Count -gt 0) -or
             ($currentJob.State -eq 'Failed') -or
             ($currentJob.State -eq 'Stopped')

# Additional check: if log file was never created, the job likely failed early
$mainLogPath = Join-Path $script:uiState.FFUDevelopmentPath "FFUDevelopment.log"
if (-not (Test-Path -LiteralPath $mainLogPath)) {
    $hasErrors = $true
}
```

### Error Message Extraction

The UI tries multiple sources to get error details:

```powershell
# 1. Error variable from Receive-Job
if ($null -ne $jobErrors -and $jobErrors.Count -gt 0) {
    $reason = ($jobErrors | Select-Object -Last 1).ToString()
}

# 2. Job state reason
if ([string]::IsNullOrWhiteSpace($reason) -and $currentJob.JobStateInfo.Reason) {
    $reason = $currentJob.JobStateInfo.Reason.Message
}

# 3. Scan job output for error keywords
if ([string]::IsNullOrWhiteSpace($reason) -and $jobOutput) {
    $errorLines = $jobOutput | Where-Object { $_ -match '(error|exception|failed|fatal)' } | Select-Object -Last 5
    if ($errorLines) {
        $reason = ($errorLines -join "`n")
    }
}

# 4. Default message based on log file existence
if ([string]::IsNullOrWhiteSpace($reason)) {
    if (-not (Test-Path -LiteralPath $mainLogPath)) {
        $reason = "Build failed before creating log file..."
    } else {
        $reason = "An unknown error occurred..."
    }
}
```

### User Notification

**On Success:**
```powershell
WriteLog "BuildFFUVM.ps1 job completed successfully."
$script:uiState.Controls.txtStatus.Text = "FFU build completed successfully."
$script:uiState.Controls.pbOverallProgress.Value = 100
```

**On Failure:**
```powershell
WriteLog "BuildFFUVM.ps1 job failed. State: $($currentJob.State). Reason: $reason"
$script:uiState.Controls.txtStatus.Text = "FFU build failed. Check FFUDevelopment.log for details."

# Show MessageBox with error details
$errorMsg = "The build process failed.`n`n"
$errorMsg += "Please check the log file for details:`n$mainLogPath`n`n"
$errorMsg += "Error: $reason"
[System.Windows.MessageBox]::Show($errorMsg, "Build Error", "OK", "Error")
```

## Important Edge Cases

### 1. Non-Terminating Errors (Job State: Completed, but hasErrors = true)

This occurs when:
- `Remove-Item` receives null/empty path without `-ErrorAction SilentlyContinue`
- `Write-Error` is called but execution continues
- Any cmdlet writes to the error stream

**Example from recent fix:**
```
Job State: Completed
Reason: Value cannot be null. (Parameter 'The provided Path argument was null or an empty collection.')
```

The script completed ("Script complete" was logged at 100%) but the error stream contained an error, so UI reported failure.

### 2. Early Parameter Validation Failures

If the script fails before creating the log file:
- Job State: `Failed` or `Completed` (if using `exit`)
- Log file doesn't exist
- UI shows: "Build failed before creating log file"

### 3. Unhandled Exceptions

If an unhandled exception occurs:
- Job State: `Failed`
- `$currentJob.JobStateInfo.Reason` contains the exception message
- Exception is also captured in `$jobErrors`

## Summary Table

| Scenario | Job State | Error Stream | Log File | UI Result |
|----------|-----------|--------------|----------|-----------|
| Successful build | Completed | Empty | Exists, ends at 100% | "completed successfully" |
| throw exception | Failed | Contains error | May exist | MessageBox with error |
| exit 1 | Completed | Empty | May exist | May appear successful |
| Write-Error | Completed | Contains error | Exists | MessageBox with error |
| Remove-Item null path | Completed | Contains error | Exists at 100% | MessageBox with error |
| Parameter validation fail | Failed | Contains error | May not exist | "failed before creating log" |

## Explicit Success Marker (Implemented Fix)

To address false failure reports caused by non-terminating errors, BuildFFUVM.ps1 now outputs an explicit success marker at completion:

```powershell
# At the end of BuildFFUVM.ps1
[PSCustomObject]@{
    FFUBuildSuccess = $true
    Message = "FFU build completed successfully"
    Duration = $runTimeFormatted
    Timestamp = Get-Date
}
```

**BuildFFUVM_UI.ps1 Detection Logic:**
```powershell
# Check for explicit success marker FIRST
$successMarker = $jobOutput | Where-Object {
    $_ -is [PSCustomObject] -and $_.PSObject.Properties['FFUBuildSuccess'] -and $_.FFUBuildSuccess -eq $true
} | Select-Object -Last 1

if ($successMarker) {
    # Explicit success - ignore non-terminating errors
    $hasErrors = $false
} else {
    # Fall back to error stream check
    $hasErrors = ($jobErrors.Count -gt 0) -or ($currentJob.State -eq 'Failed')
}
```

**Why This Works:**
- Provides **positive confirmation** of success rather than relying on absence of errors
- Non-terminating errors from cleanup operations no longer cause false failures
- The success marker is only output if the script reaches the end successfully

## Recommendations for Developers

1. **Always use `-ErrorAction SilentlyContinue`** for cleanup operations (Remove-Item, etc.)
2. **Validate paths before passing to cmdlets** to prevent non-terminating errors
3. **Use `throw` for intentional failures** - this sets job state to `Failed`
4. **Avoid `exit`** - it doesn't clearly indicate failure to the UI
5. **Use `Set-Progress`** at key milestones for user feedback
6. **Log errors with `WriteLog`** before throwing for better diagnostics
7. **Do not remove the success marker** - it's critical for proper success/failure detection
