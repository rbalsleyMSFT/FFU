#Requires -Version 5.1
<#
.SYNOPSIS
    Example demonstrating FFU.Messaging integration with WPF UI and ThreadJob.

.DESCRIPTION
    This example shows the complete pattern for:
    1. UI initialization and messaging context creation
    2. Passing context to ThreadJob
    3. Background job message writing
    4. UI timer-based message processing
    5. Progress bar and log window updates
    6. Cancellation handling
    7. Cleanup on completion

.NOTES
    This is a reference implementation. Adapt patterns to BuildFFUVM_UI.ps1.
#>

#region UI-Side Implementation (BuildFFUVM_UI.ps1 pattern)

# ============================================================================
# PART 1: UI Initialization
# ============================================================================

<#
.SYNOPSIS
    Initialize the messaging system when UI loads.

.DESCRIPTION
    Call this during UI initialization (after XAML loads, before build starts).
    Creates the synchronized context and stores it in a script-level variable.
#>
function Initialize-FFUMessaging {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LogFilePath
    )

    # Import the messaging module
    $modulePath = Join-Path $PSScriptRoot '..\FFU.Messaging.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    # Create the messaging context
    $script:MessagingContext = New-FFUMessagingContext -EnableFileLogging -LogFilePath $LogFilePath

    Write-Verbose "Messaging context initialized. Log file: $LogFilePath"

    return $script:MessagingContext
}

# ============================================================================
# PART 2: Starting the Build Job
# ============================================================================

<#
.SYNOPSIS
    Start the build job with messaging context.

.DESCRIPTION
    Demonstrates how to pass the synchronized context to a ThreadJob.
    The context is passed as the first argument and is accessible inside the job.
#>
function Start-FFUBuildWithMessaging {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$MessagingContext,

        [Parameter(Mandatory)]
        [string]$BuildScriptPath,

        [Parameter()]
        [hashtable]$BuildParameters = @{}
    )

    # Validate context
    Test-FFUMessagingContext -Context $MessagingContext | Out-Null

    # Update build state
    Set-FFUBuildState -Context $MessagingContext -State Initializing -SendMessage

    # Prepare the script block for ThreadJob
    $jobScriptBlock = {
        param(
            [hashtable]$SyncContext,
            [string]$ScriptPath,
            [hashtable]$Params
        )

        # Import messaging module inside the job
        # The module path must be absolute since we're in a new runspace
        $modulesPath = Split-Path -Parent (Split-Path -Parent $ScriptPath)
        $messagingModule = Join-Path $modulesPath 'Modules\FFU.Messaging\FFU.Messaging.psd1'

        if (Test-Path $messagingModule) {
            Import-Module $messagingModule -Force
        }
        else {
            # Fallback: define minimal messaging inline if module not found
            throw "FFU.Messaging module not found at: $messagingModule"
        }

        # Set build state to running
        Set-FFUBuildState -Context $SyncContext -State Running -SendMessage

        try {
            # Execute the actual build script
            # Pass the messaging context so the build script can send messages
            & $ScriptPath @Params -MessagingContext $SyncContext

            # Build completed successfully
            Set-FFUBuildState -Context $SyncContext -State Completed -SendMessage
        }
        catch {
            # Build failed
            Write-FFUError -Context $SyncContext -Message "Build failed: $_" -Source 'BuildJob'
            Set-FFUBuildState -Context $SyncContext -State Failed -SendMessage
            throw
        }
    }

    # Start the ThreadJob
    # ThreadJob preserves parent session state including credentials (important for BITS)
    $job = Start-ThreadJob -ScriptBlock $jobScriptBlock `
        -ArgumentList @($MessagingContext, $BuildScriptPath, $BuildParameters) `
        -Name "FFUBuild_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

    return $job
}

# ============================================================================
# PART 3: UI Timer for Message Processing
# ============================================================================

<#
.SYNOPSIS
    Process messages from the queue and update UI controls.

.DESCRIPTION
    This function is called by a DispatcherTimer every 50ms.
    It drains the message queue and updates WPF controls accordingly.

.PARAMETER Window
    The WPF Window object containing the controls to update.

.PARAMETER MessagingContext
    The synchronized messaging context.

.PARAMETER ProgressBar
    The WPF ProgressBar control.

.PARAMETER LogTextBox
    The WPF TextBox or RichTextBox for log output.

.PARAMETER StatusTextBlock
    The WPF TextBlock for status messages.
#>
function Update-UIFromMessages {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$MessagingContext,

        [Parameter(Mandatory)]
        [System.Windows.Controls.ProgressBar]$ProgressBar,

        [Parameter(Mandatory)]
        [System.Windows.Controls.TextBox]$LogTextBox,

        [Parameter(Mandatory)]
        [System.Windows.Controls.TextBlock]$StatusTextBlock
    )

    # Read all available messages (non-blocking)
    $messages = Read-FFUMessages -Context $MessagingContext -MaxMessages 50

    if ($messages.Count -eq 0) {
        return
    }

    # Process each message
    foreach ($msg in $messages) {
        # Update progress bar for progress messages
        if ($msg -is [FFUProgressMessage] -or $msg.Level -eq [FFUMessageLevel]::Progress) {
            $percent = if ($msg.Data.ContainsKey('PercentComplete')) {
                $msg.Data['PercentComplete']
            } elseif ($msg.PercentComplete) {
                $msg.PercentComplete
            } else { 0 }

            $ProgressBar.Value = $percent

            # Update status with current operation
            $operation = if ($msg.Data.ContainsKey('CurrentOperation')) {
                $msg.Data['CurrentOperation']
            } elseif ($msg.CurrentOperation) {
                $msg.CurrentOperation
            } else { $msg.Message }

            $StatusTextBlock.Text = "$($msg.Message) - $operation ($percent%)"
        }

        # Append to log window (for non-progress messages or milestones)
        if ($msg.Level -ne [FFUMessageLevel]::Progress -or
            ($msg.Data.ContainsKey('PercentComplete') -and $msg.Data['PercentComplete'] % 25 -eq 0)) {

            # Format log line with color coding (via TextBox - for RichTextBox use Inlines)
            $timestamp = $msg.Timestamp.ToLocalTime().ToString('HH:mm:ss')
            $levelStr = $msg.Level.ToString().ToUpper().PadRight(8)
            $logLine = "[$timestamp] [$levelStr] $($msg.Message)`r`n"

            # Append to TextBox
            $LogTextBox.AppendText($logLine)

            # Auto-scroll to bottom
            $LogTextBox.ScrollToEnd()
        }

        # Update status for non-progress messages
        if ($msg.Level -ne [FFUMessageLevel]::Progress) {
            $StatusTextBlock.Text = $msg.Message
        }

        # Handle state changes
        if ($msg.Source -eq 'BuildState') {
            switch ($MessagingContext.BuildState) {
                'Completed' {
                    $ProgressBar.Value = 100
                    $StatusTextBlock.Text = "Build completed successfully!"
                }
                'Failed' {
                    $StatusTextBlock.Text = "Build failed. Check log for details."
                }
                'Cancelled' {
                    $StatusTextBlock.Text = "Build cancelled."
                }
            }
        }
    }
}

<#
.SYNOPSIS
    Set up the DispatcherTimer for message polling.

.DESCRIPTION
    Creates and starts a WPF DispatcherTimer that polls the message queue
    at 50ms intervals (20 times per second).

.PARAMETER Window
    The WPF Window object.

.PARAMETER MessagingContext
    The synchronized messaging context.

.PARAMETER ProgressBar
    The WPF ProgressBar control.

.PARAMETER LogTextBox
    The WPF TextBox for log output.

.PARAMETER StatusTextBlock
    The WPF TextBlock for status.

.OUTPUTS
    [System.Windows.Threading.DispatcherTimer] - The timer object (keep reference to stop it later).
#>
function Start-MessagePollingTimer {
    [CmdletBinding()]
    [OutputType([System.Windows.Threading.DispatcherTimer])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$MessagingContext,

        [Parameter(Mandatory)]
        [System.Windows.Controls.ProgressBar]$ProgressBar,

        [Parameter(Mandatory)]
        [System.Windows.Controls.TextBox]$LogTextBox,

        [Parameter(Mandatory)]
        [System.Windows.Controls.TextBlock]$StatusTextBlock
    )

    # Create timer with 50ms interval
    $timer = [System.Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [TimeSpan]::FromMilliseconds(50)

    # Store references for the event handler (using script scope)
    $script:UIContext = @{
        MessagingContext = $MessagingContext
        ProgressBar = $ProgressBar
        LogTextBox = $LogTextBox
        StatusTextBlock = $StatusTextBlock
    }

    # Timer tick event handler
    $timer.Add_Tick({
        Update-UIFromMessages `
            -MessagingContext $script:UIContext.MessagingContext `
            -ProgressBar $script:UIContext.ProgressBar `
            -LogTextBox $script:UIContext.LogTextBox `
            -StatusTextBlock $script:UIContext.StatusTextBlock
    })

    # Start the timer
    $timer.Start()

    return $timer
}

# ============================================================================
# PART 4: Cancellation Handling
# ============================================================================

<#
.SYNOPSIS
    Handle cancel button click in UI.

.DESCRIPTION
    Sets the cancellation flag and updates UI state.
    The background job should check for cancellation periodically.
#>
function Stop-FFUBuildFromUI {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$MessagingContext,

        [Parameter()]
        [System.Management.Automation.Job]$BuildJob
    )

    # Request cancellation via messaging context
    Request-FFUCancellation -Context $MessagingContext

    # Optionally, give the job a few seconds to stop gracefully
    # If it doesn't stop, force-stop it
    if ($BuildJob) {
        $timeout = [DateTime]::Now.AddSeconds(10)
        while ($BuildJob.State -eq 'Running' -and [DateTime]::Now -lt $timeout) {
            Start-Sleep -Milliseconds 200
        }

        if ($BuildJob.State -eq 'Running') {
            Write-Warning "Build job did not stop gracefully, forcing stop..."
            Stop-Job -Job $BuildJob -PassThru | Remove-Job -Force
        }
    }
}

# ============================================================================
# PART 5: Cleanup
# ============================================================================

<#
.SYNOPSIS
    Clean up messaging resources when UI closes or build completes.
#>
function Close-FFUMessagingFromUI {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$MessagingContext,

        [Parameter()]
        [System.Windows.Threading.DispatcherTimer]$Timer
    )

    # Stop the polling timer
    if ($Timer) {
        $Timer.Stop()
    }

    # Close the messaging context
    Close-FFUMessagingContext -Context $MessagingContext
}

#endregion

#region Background Job Implementation (BuildFFUVM.ps1 pattern)

# ============================================================================
# PART 6: Background Job Message Writing
# ============================================================================

<#
.SYNOPSIS
    Example of how BuildFFUVM.ps1 would use the messaging system.

.DESCRIPTION
    Shows the pattern for checking cancellation and sending messages
    throughout the build process.
#>
function Invoke-ExampleBuildWithMessaging {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$MessagingContext
    )

    # Example build phases
    $phases = @(
        @{ Name = 'Initializing'; Weight = 5 }
        @{ Name = 'Downloading Drivers'; Weight = 20 }
        @{ Name = 'Creating VHDX'; Weight = 15 }
        @{ Name = 'Applying Windows Image'; Weight = 25 }
        @{ Name = 'Installing Updates'; Weight = 20 }
        @{ Name = 'Capturing FFU'; Weight = 15 }
    )

    $totalWeight = ($phases | Measure-Object -Property Weight -Sum).Sum
    $completedWeight = 0

    foreach ($phase in $phases) {
        # CHECK FOR CANCELLATION at the start of each phase
        if (Test-FFUCancellationRequested -Context $MessagingContext) {
            Write-FFUWarning -Context $MessagingContext `
                -Message "Cancellation requested, stopping at phase: $($phase.Name)" `
                -Source 'Build'
            return
        }

        # Send progress update
        $percentComplete = [int](($completedWeight / $totalWeight) * 100)
        Write-FFUProgress -Context $MessagingContext `
            -Activity $phase.Name `
            -PercentComplete $percentComplete `
            -CurrentOperation "Starting $($phase.Name)..." `
            -Status 'In Progress'

        # Send info message
        Write-FFUInfo -Context $MessagingContext `
            -Message "Starting phase: $($phase.Name)" `
            -Source 'Build'

        # Simulate work with sub-progress
        $subSteps = 5
        for ($i = 1; $i -le $subSteps; $i++) {
            # Check cancellation during long operations
            if (Test-FFUCancellationRequested -Context $MessagingContext) {
                Write-FFUWarning -Context $MessagingContext `
                    -Message "Cancellation requested during $($phase.Name)" `
                    -Source 'Build'
                return
            }

            # Sub-step progress
            $subProgress = ($completedWeight + ($phase.Weight * ($i / $subSteps))) / $totalWeight * 100
            Write-FFUProgress -Context $MessagingContext `
                -Activity $phase.Name `
                -PercentComplete ([int]$subProgress) `
                -CurrentOperation "Step $i of $subSteps" `
                -Status 'Processing'

            # Simulate work
            Start-Sleep -Milliseconds 500
        }

        # Phase complete
        $completedWeight += $phase.Weight
        Write-FFUSuccess -Context $MessagingContext `
            -Message "Completed phase: $($phase.Name)" `
            -Source 'Build'
    }

    # Final progress
    Write-FFUProgress -Context $MessagingContext `
        -Activity 'Build Complete' `
        -PercentComplete 100 `
        -CurrentOperation 'Done' `
        -Status 'Complete'
}

#endregion

#region Integration with Existing WriteLog

<#
.SYNOPSIS
    Wrapper to maintain backward compatibility with existing WriteLog function.

.DESCRIPTION
    This function bridges the existing WriteLog pattern with the new messaging system.
    It writes to both the queue (for UI) and the file (for persistence).

    Use this in BuildFFUVM.ps1 to gradually migrate to the new system.

.PARAMETER LogText
    The log message text.

.PARAMETER LogLevel
    The log level (Info, Warning, Error, Success, etc.).

.PARAMETER MessagingContext
    Optional. If provided, also sends to the messaging queue.
    If not provided, falls back to file-only logging (backward compatible).
#>
function Write-FFULogBridge {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$LogText,

        [Parameter()]
        [string]$LogLevel = 'Info',

        [Parameter()]
        [hashtable]$MessagingContext = $null,

        [Parameter()]
        [string]$Source = ''
    )

    # Handle null/empty gracefully
    if ([string]::IsNullOrWhiteSpace($LogText)) {
        return
    }

    # Map string level to enum
    $level = switch ($LogLevel) {
        'Debug' { [FFUMessageLevel]::Debug }
        'Info' { [FFUMessageLevel]::Info }
        'Progress' { [FFUMessageLevel]::Progress }
        'Success' { [FFUMessageLevel]::Success }
        'Warning' { [FFUMessageLevel]::Warning }
        'Error' { [FFUMessageLevel]::Error }
        'Critical' { [FFUMessageLevel]::Critical }
        default { [FFUMessageLevel]::Info }
    }

    # If messaging context is available, use it
    if ($MessagingContext) {
        Write-FFUMessage -Context $MessagingContext -Message $LogText -Level $level -Source $Source
    }

    # Also call the original WriteLog if it exists (for backward compatibility)
    if (Get-Command -Name 'WriteLog' -ErrorAction SilentlyContinue) {
        WriteLog $LogText
    }
}

#endregion

#region Full Integration Example

<#
.SYNOPSIS
    Complete example showing full UI integration workflow.

.DESCRIPTION
    This demonstrates the complete lifecycle:
    1. UI loads and initializes messaging
    2. User clicks Build button
    3. Timer polls messages and updates UI
    4. User can click Cancel
    5. Build completes/fails/cancels
    6. UI cleans up resources
#>
function Show-CompleteIntegrationExample {
    Write-Host "=== FFU.Messaging Integration Example ===" -ForegroundColor Cyan
    Write-Host ""

    # Step 1: Initialize (normally done when UI loads)
    Write-Host "1. Initializing messaging context..." -ForegroundColor Yellow
    $logPath = Join-Path $env:TEMP "FFUBuild_Example_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    $context = New-FFUMessagingContext -EnableFileLogging -LogFilePath $logPath
    Write-Host "   Log file: $logPath" -ForegroundColor Gray
    Write-Host ""

    # Step 2: Start background job (normally triggered by Build button)
    Write-Host "2. Starting build job..." -ForegroundColor Yellow
    Set-FFUBuildState -Context $context -State Running -SendMessage

    $job = Start-ThreadJob -ScriptBlock {
        param($ctx)

        # Simulate importing module (in real scenario, import FFU.Messaging)
        # For this example, we'll use the context directly

        # Simulate build phases
        $phases = @('Initializing', 'Downloading', 'Building', 'Capturing')
        $phaseIndex = 0

        foreach ($phase in $phases) {
            # Check cancellation
            if ($ctx.CancellationRequested) {
                $msg = [PSCustomObject]@{
                    Timestamp = [datetime]::UtcNow
                    Level = 'Warning'
                    Message = "Build cancelled at phase: $phase"
                    Source = 'Build'
                    Data = @{}
                }
                $ctx.MessageQueue.Enqueue($msg)
                return
            }

            # Send progress
            $percent = [int](($phaseIndex / $phases.Count) * 100)
            $progressMsg = [PSCustomObject]@{
                Timestamp = [datetime]::UtcNow
                Level = 'Progress'
                Message = $phase
                Source = 'Build'
                Data = @{ PercentComplete = $percent; CurrentOperation = $phase }
            }
            $ctx.MessageQueue.Enqueue($progressMsg)

            # Simulate work
            Start-Sleep -Seconds 1

            $phaseIndex++
        }

        # Complete
        $completeMsg = [PSCustomObject]@{
            Timestamp = [datetime]::UtcNow
            Level = 'Success'
            Message = "Build completed successfully"
            Source = 'Build'
            Data = @{ PercentComplete = 100 }
        }
        $ctx.MessageQueue.Enqueue($completeMsg)
        $ctx.BuildState = 'Completed'

    } -ArgumentList $context

    Write-Host "   Job started: $($job.Name)" -ForegroundColor Gray
    Write-Host ""

    # Step 3: Poll for messages (normally done by DispatcherTimer)
    Write-Host "3. Polling messages (simulating UI timer)..." -ForegroundColor Yellow

    while ($job.State -eq 'Running' -or $context.MessageQueue.Count -gt 0) {
        # Read messages
        $msg = $null
        while ($context.MessageQueue.TryDequeue([ref]$msg)) {
            $timestamp = $msg.Timestamp.ToLocalTime().ToString('HH:mm:ss')
            $levelColor = switch ($msg.Level) {
                'Error' { 'Red' }
                'Warning' { 'Yellow' }
                'Success' { 'Green' }
                'Progress' { 'Cyan' }
                default { 'White' }
            }

            if ($msg.Data.ContainsKey('PercentComplete')) {
                Write-Host "   [$timestamp] $($msg.Level.ToString().PadRight(8)) $($msg.Message) - $($msg.Data['PercentComplete'])%" -ForegroundColor $levelColor
            }
            else {
                Write-Host "   [$timestamp] $($msg.Level.ToString().PadRight(8)) $($msg.Message)" -ForegroundColor $levelColor
            }
        }

        Start-Sleep -Milliseconds 100
    }

    Write-Host ""

    # Step 4: Cleanup
    Write-Host "4. Cleaning up..." -ForegroundColor Yellow
    $job | Wait-Job | Remove-Job
    Close-FFUMessagingContext -Context $context
    Write-Host "   Done. Log saved to: $logPath" -ForegroundColor Gray
    Write-Host ""

    Write-Host "=== Example Complete ===" -ForegroundColor Cyan
}

# Run the example if executed directly
if ($MyInvocation.InvocationName -ne '.') {
    Show-CompleteIntegrationExample
}

#endregion
