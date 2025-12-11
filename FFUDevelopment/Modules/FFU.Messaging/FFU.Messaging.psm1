#Requires -Version 7.0
<#
.SYNOPSIS
    FFU.Messaging - Thread-safe messaging system for FFUBuilder UI/background job communication.

.DESCRIPTION
    Provides a synchronized queue-based messaging system using ConcurrentQueue for real-time
    UI updates while maintaining backward compatibility with file-based logging.

    Key Features:
    - Lock-free thread safety via ConcurrentQueue
    - Structured message types (Progress, Info, Warning, Error, Success, Debug)
    - Dual output: queue for UI + file for persistence
    - Cancellation support via shared state
    - PowerShell 5.1+ and 7+ compatible

.NOTES
    Module: FFU.Messaging
    Version: 1.0.0
    Author: FFUBuilder Team
    Requires: PowerShell 5.1 or later
#>

#region Type Definitions

# Message severity levels
enum FFUMessageLevel {
    Debug = 0
    Info = 1
    Progress = 2
    Success = 3
    Warning = 4
    Error = 5
    Critical = 6
}

# Build state enumeration
enum FFUBuildState {
    NotStarted
    Initializing
    Running
    Completing
    Completed
    Failed
    Cancelled
    Cancelling
}

# Message class for structured communication
class FFUMessage {
    [datetime]$Timestamp
    [FFUMessageLevel]$Level
    [string]$Message
    [string]$Source
    [hashtable]$Data
    [string]$MessageId

    # Default constructor
    FFUMessage() {
        $this.Timestamp = [datetime]::UtcNow
        $this.Level = [FFUMessageLevel]::Info
        $this.Message = ''
        $this.Source = ''
        $this.Data = @{}
        $this.MessageId = [guid]::NewGuid().ToString('N').Substring(0, 8)
    }

    # Simple constructor
    FFUMessage([FFUMessageLevel]$level, [string]$message) {
        $this.Timestamp = [datetime]::UtcNow
        $this.Level = $level
        $this.Message = $message
        $this.Source = ''
        $this.Data = @{}
        $this.MessageId = [guid]::NewGuid().ToString('N').Substring(0, 8)
    }

    # Full constructor
    FFUMessage([FFUMessageLevel]$level, [string]$message, [string]$source, [hashtable]$data) {
        $this.Timestamp = [datetime]::UtcNow
        $this.Level = $level
        $this.Message = $message
        $this.Source = $source
        $this.Data = if ($data) { $data } else { @{} }
        $this.MessageId = [guid]::NewGuid().ToString('N').Substring(0, 8)
    }

    # Format for log file output
    [string] ToLogString() {
        $levelStr = $this.Level.ToString().ToUpper().PadRight(8)
        $timeStr = $this.Timestamp.ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss.fff')
        $sourceStr = if ($this.Source) { "[$($this.Source)] " } else { '' }
        return "$timeStr [$levelStr] $sourceStr$($this.Message)"
    }

    # Format for UI display (without timestamp for cleaner look)
    [string] ToDisplayString() {
        $sourceStr = if ($this.Source) { "[$($this.Source)] " } else { '' }
        return "$sourceStr$($this.Message)"
    }
}

# Progress-specific message with additional metadata
class FFUProgressMessage : FFUMessage {
    [int]$PercentComplete
    [string]$CurrentOperation
    [string]$Status
    [int]$SecondsRemaining

    FFUProgressMessage([string]$activity, [int]$percent) : base([FFUMessageLevel]::Progress, $activity) {
        $this.PercentComplete = [Math]::Max(0, [Math]::Min(100, $percent))
        $this.CurrentOperation = ''
        $this.Status = ''
        $this.SecondsRemaining = -1
        $this.Data['PercentComplete'] = $this.PercentComplete
    }

    FFUProgressMessage([string]$activity, [int]$percent, [string]$currentOp, [string]$status) : base([FFUMessageLevel]::Progress, $activity) {
        $this.PercentComplete = [Math]::Max(0, [Math]::Min(100, $percent))
        $this.CurrentOperation = $currentOp
        $this.Status = $status
        $this.SecondsRemaining = -1
        $this.Data['PercentComplete'] = $this.PercentComplete
        $this.Data['CurrentOperation'] = $this.CurrentOperation
        $this.Data['Status'] = $this.Status
    }
}

#endregion

#region Synchronized Context

<#
.SYNOPSIS
    Creates a new synchronized messaging context for UI/ThreadJob communication.

.DESCRIPTION
    Initializes a thread-safe hashtable containing a ConcurrentQueue for messages,
    cancellation flag, build state, and other shared data. This context is passed
    to the ThreadJob and used by both the UI and background job.

.PARAMETER EnableFileLogging
    If specified, file logging will be enabled alongside queue messaging.

.PARAMETER LogFilePath
    Path to the log file. Required if EnableFileLogging is specified.

.OUTPUTS
    [hashtable] - Synchronized hashtable containing messaging infrastructure.

.EXAMPLE
    $syncContext = New-FFUMessagingContext -EnableFileLogging -LogFilePath "C:\Logs\build.log"
    Start-ThreadJob -ArgumentList $syncContext -ScriptBlock { ... }
#>
function New-FFUMessagingContext {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [switch]$EnableFileLogging,

        [Parameter()]
        [string]$LogFilePath
    )

    # Validate parameters
    if ($EnableFileLogging -and -not $LogFilePath) {
        throw "LogFilePath is required when EnableFileLogging is specified."
    }

    # Create synchronized hashtable with all required components
    $context = [hashtable]::Synchronized(@{
        # Core messaging queue - ConcurrentQueue for lock-free thread safety
        MessageQueue = [System.Collections.Concurrent.ConcurrentQueue[PSObject]]::new()

        # Cancellation support
        CancellationRequested = $false

        # Build state tracking
        BuildState = [FFUBuildState]::NotStarted

        # Error tracking
        LastError = $null
        ErrorCount = 0

        # Progress tracking
        CurrentProgress = 0
        CurrentOperation = ''
        CurrentPhase = ''

        # File logging configuration
        FileLoggingEnabled = $EnableFileLogging.IsPresent
        LogFilePath = $LogFilePath

        # Timing information
        StartTime = $null
        EndTime = $null

        # Statistics
        MessageCount = 0

        # Version for compatibility checking
        Version = '1.0.0'
    })

    # Initialize log file if enabled
    if ($EnableFileLogging -and $LogFilePath) {
        $logDir = Split-Path -Path $LogFilePath -Parent
        if ($logDir -and -not (Test-Path -Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        # Create or clear the log file
        $null = New-Item -Path $LogFilePath -ItemType File -Force
    }

    return $context
}

<#
.SYNOPSIS
    Validates that a messaging context is properly initialized.

.PARAMETER Context
    The messaging context to validate.

.OUTPUTS
    [bool] - True if context is valid, throws otherwise.
#>
function Test-FFUMessagingContext {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Context
    )

    $requiredKeys = @('MessageQueue', 'CancellationRequested', 'BuildState', 'Version')

    foreach ($key in $requiredKeys) {
        if (-not $Context.ContainsKey($key)) {
            throw "Invalid messaging context: missing required key '$key'"
        }
    }

    if ($null -eq $Context.MessageQueue) {
        throw "Invalid messaging context: MessageQueue is null"
    }

    if ($Context.MessageQueue.GetType().Name -ne 'ConcurrentQueue`1') {
        throw "Invalid messaging context: MessageQueue is not a ConcurrentQueue"
    }

    return $true
}

#endregion

#region Message Writing Functions

<#
.SYNOPSIS
    Writes a message to the synchronized queue and optionally to a log file.

.DESCRIPTION
    Primary function for sending messages from the background job to the UI.
    Messages are enqueued in a thread-safe ConcurrentQueue and optionally
    written to a log file for persistence.

.PARAMETER Context
    The synchronized messaging context created by New-FFUMessagingContext.

.PARAMETER Message
    The message text to send.

.PARAMETER Level
    The severity level of the message. Defaults to Info.

.PARAMETER Source
    Optional source identifier (function name, phase, etc.).

.PARAMETER Data
    Optional hashtable of structured data associated with the message.

.PARAMETER SkipFileLog
    If specified, the message will not be written to the log file.

.EXAMPLE
    Write-FFUMessage -Context $SyncHash -Message "Starting driver download" -Level Info -Source "Get-DellDrivers"

.EXAMPLE
    Write-FFUMessage -Context $SyncHash -Message "Build failed" -Level Error -Data @{ ExitCode = 1; Details = $error }
#>
function Write-FFUMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Context,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message,

        [Parameter()]
        [FFUMessageLevel]$Level = [FFUMessageLevel]::Info,

        [Parameter()]
        [string]$Source = '',

        [Parameter()]
        [hashtable]$Data = @{},

        [Parameter()]
        [switch]$SkipFileLog
    )

    # Handle null/empty messages gracefully
    if ([string]::IsNullOrWhiteSpace($Message)) {
        return
    }

    # Create message object
    $msg = [FFUMessage]::new($Level, $Message, $Source, $Data)

    # Enqueue message (thread-safe)
    $Context.MessageQueue.Enqueue($msg)

    # Update statistics
    $Context.MessageCount++

    # Track errors
    if ($Level -ge [FFUMessageLevel]::Error) {
        $Context.ErrorCount++
        $Context.LastError = $msg
    }

    # Write to log file if enabled
    if (-not $SkipFileLog -and $Context.FileLoggingEnabled -and $Context.LogFilePath) {
        try {
            $logLine = $msg.ToLogString()
            # Use mutex for file write synchronization
            $mutexName = "FFULogMutex_" + ($Context.LogFilePath -replace '[\\/:*?"<>|]', '_')
            $mutex = [System.Threading.Mutex]::new($false, $mutexName)
            try {
                $null = $mutex.WaitOne(1000)
                Add-Content -Path $Context.LogFilePath -Value $logLine -Encoding UTF8
            }
            finally {
                $mutex.ReleaseMutex()
                $mutex.Dispose()
            }
        }
        catch {
            # Silently ignore file logging errors to prevent disrupting main operation
        }
    }
}

<#
.SYNOPSIS
    Writes a progress message with percentage and operation details.

.DESCRIPTION
    Specialized function for sending progress updates that include percentage
    complete and current operation information for progress bar updates.

.PARAMETER Context
    The synchronized messaging context.

.PARAMETER Activity
    The main activity description (shown as progress bar label).

.PARAMETER PercentComplete
    Progress percentage (0-100).

.PARAMETER CurrentOperation
    Current sub-operation being performed.

.PARAMETER Status
    Status text for additional context.

.PARAMETER SecondsRemaining
    Optional estimated seconds remaining (-1 for unknown).

.EXAMPLE
    Write-FFUProgress -Context $SyncHash -Activity "Downloading drivers" -PercentComplete 45 -CurrentOperation "Dell Latitude 7490"
#>
function Write-FFUProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Context,

        [Parameter(Mandatory)]
        [string]$Activity,

        [Parameter(Mandatory)]
        [ValidateRange(0, 100)]
        [int]$PercentComplete,

        [Parameter()]
        [string]$CurrentOperation = '',

        [Parameter()]
        [string]$Status = '',

        [Parameter()]
        [int]$SecondsRemaining = -1
    )

    # Create progress message
    $msg = [FFUProgressMessage]::new($Activity, $PercentComplete, $CurrentOperation, $Status)
    $msg.SecondsRemaining = $SecondsRemaining
    $msg.Data['SecondsRemaining'] = $SecondsRemaining

    # Update context with current progress
    $Context.CurrentProgress = $PercentComplete
    $Context.CurrentOperation = $CurrentOperation
    $Context.CurrentPhase = $Activity

    # Enqueue message
    $Context.MessageQueue.Enqueue($msg)
    $Context.MessageCount++

    # Progress messages typically don't need file logging (too verbose)
    # But we can log significant milestones
    if ($PercentComplete % 25 -eq 0 -or $PercentComplete -eq 100) {
        if ($Context.FileLoggingEnabled -and $Context.LogFilePath) {
            try {
                $logLine = $msg.ToLogString() + " ($PercentComplete%)"
                $mutexName = "FFULogMutex_" + ($Context.LogFilePath -replace '[\\/:*?"<>|]', '_')
                $mutex = [System.Threading.Mutex]::new($false, $mutexName)
                try {
                    $null = $mutex.WaitOne(1000)
                    Add-Content -Path $Context.LogFilePath -Value $logLine -Encoding UTF8
                }
                finally {
                    $mutex.ReleaseMutex()
                    $mutex.Dispose()
                }
            }
            catch {
                # Silently ignore
            }
        }
    }
}

#region Convenience Functions

<#
.SYNOPSIS
    Writes an informational message.
#>
function Write-FFUInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Context,

        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [string]$Source = ''
    )

    Write-FFUMessage -Context $Context -Message $Message -Level Info -Source $Source
}

<#
.SYNOPSIS
    Writes a success message.
#>
function Write-FFUSuccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Context,

        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [string]$Source = ''
    )

    Write-FFUMessage -Context $Context -Message $Message -Level Success -Source $Source
}

<#
.SYNOPSIS
    Writes a warning message.
#>
function Write-FFUWarning {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Context,

        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [string]$Source = ''
    )

    Write-FFUMessage -Context $Context -Message $Message -Level Warning -Source $Source
}

<#
.SYNOPSIS
    Writes an error message.
#>
function Write-FFUError {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Context,

        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [string]$Source = '',

        [Parameter()]
        [hashtable]$Data = @{}
    )

    Write-FFUMessage -Context $Context -Message $Message -Level Error -Source $Source -Data $Data
}

<#
.SYNOPSIS
    Writes a debug message.
#>
function Write-FFUDebug {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Context,

        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [string]$Source = ''
    )

    Write-FFUMessage -Context $Context -Message $Message -Level Debug -Source $Source
}

#endregion

#endregion

#region Message Reading Functions (UI Side)

<#
.SYNOPSIS
    Reads and removes all available messages from the queue.

.DESCRIPTION
    Drains the ConcurrentQueue, returning all messages that have been enqueued
    since the last read. This is called by the UI timer to process messages.

    The function is non-blocking - if no messages are available, it returns
    an empty array immediately.

.PARAMETER Context
    The synchronized messaging context.

.PARAMETER MaxMessages
    Maximum number of messages to dequeue in a single call. Defaults to 100.
    This prevents the UI from becoming unresponsive if many messages queue up.

.OUTPUTS
    [FFUMessage[]] - Array of messages, or empty array if none available.

.EXAMPLE
    $messages = Read-FFUMessages -Context $SyncHash
    foreach ($msg in $messages) {
        Update-UIControl -Message $msg
    }
#>
function Read-FFUMessages {
    [CmdletBinding()]
    [OutputType([PSObject[]])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Context,

        [Parameter()]
        [int]$MaxMessages = 100
    )

    $messages = [System.Collections.Generic.List[PSObject]]::new()
    $msg = $null
    $count = 0

    # Drain queue up to MaxMessages
    while ($count -lt $MaxMessages -and $Context.MessageQueue.TryDequeue([ref]$msg)) {
        $messages.Add($msg)
        $count++
    }

    return $messages.ToArray()
}

<#
.SYNOPSIS
    Peeks at the next message without removing it from the queue.

.PARAMETER Context
    The synchronized messaging context.

.OUTPUTS
    [FFUMessage] - The next message, or $null if queue is empty.
#>
function Peek-FFUMessage {
    [CmdletBinding()]
    [OutputType([PSObject])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Context
    )

    $msg = $null
    if ($Context.MessageQueue.TryPeek([ref]$msg)) {
        return $msg
    }
    return $null
}

<#
.SYNOPSIS
    Gets the current number of messages waiting in the queue.

.PARAMETER Context
    The synchronized messaging context.

.OUTPUTS
    [int] - Number of messages in queue.
#>
function Get-FFUMessageCount {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Context
    )

    return $Context.MessageQueue.Count
}

#endregion

#region Build State Management

<#
.SYNOPSIS
    Sets the build state in the messaging context.

.PARAMETER Context
    The synchronized messaging context.

.PARAMETER State
    The new build state.

.PARAMETER SendMessage
    If specified, sends a message about the state change.
#>
function Set-FFUBuildState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Context,

        [Parameter(Mandatory)]
        [FFUBuildState]$State,

        [Parameter()]
        [switch]$SendMessage
    )

    $previousState = $Context.BuildState
    $Context.BuildState = $State

    # Update timing
    switch ($State) {
        'Running' {
            $Context.StartTime = [datetime]::UtcNow
        }
        { $_ -in 'Completed', 'Failed', 'Cancelled' } {
            $Context.EndTime = [datetime]::UtcNow
        }
    }

    if ($SendMessage) {
        $stateMessages = @{
            [FFUBuildState]::Initializing = "Initializing build environment..."
            [FFUBuildState]::Running = "Build started"
            [FFUBuildState]::Completing = "Finalizing build..."
            [FFUBuildState]::Completed = "Build completed successfully"
            [FFUBuildState]::Failed = "Build failed"
            [FFUBuildState]::Cancelled = "Build cancelled by user"
            [FFUBuildState]::Cancelling = "Cancellation requested, stopping build..."
        }

        $level = switch ($State) {
            'Completed' { [FFUMessageLevel]::Success }
            'Failed' { [FFUMessageLevel]::Error }
            'Cancelled' { [FFUMessageLevel]::Warning }
            'Cancelling' { [FFUMessageLevel]::Warning }
            default { [FFUMessageLevel]::Info }
        }

        Write-FFUMessage -Context $Context -Message $stateMessages[$State] -Level $level -Source 'BuildState'
    }
}

<#
.SYNOPSIS
    Requests cancellation of the build.

.DESCRIPTION
    Sets the cancellation flag in the context. The background job should
    check this flag periodically and gracefully stop if set.

.PARAMETER Context
    The synchronized messaging context.

.EXAMPLE
    # In UI cancel button handler
    Request-FFUCancellation -Context $SyncHash
#>
function Request-FFUCancellation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Context
    )

    $Context.CancellationRequested = $true
    Set-FFUBuildState -Context $Context -State Cancelling -SendMessage
}

<#
.SYNOPSIS
    Checks if cancellation has been requested.

.DESCRIPTION
    Should be called periodically by the background job to check if the
    user has requested cancellation.

.PARAMETER Context
    The synchronized messaging context.

.OUTPUTS
    [bool] - True if cancellation requested.
#>
function Test-FFUCancellationRequested {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Context
    )

    return $Context.CancellationRequested -eq $true
}

#endregion

#region Cleanup

<#
.SYNOPSIS
    Cleans up the messaging context resources.

.DESCRIPTION
    Should be called when the build completes or is cancelled to ensure
    proper cleanup of resources.

.PARAMETER Context
    The synchronized messaging context.
#>
function Close-FFUMessagingContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Context
    )

    # Drain any remaining messages
    $msg = $null
    while ($Context.MessageQueue.TryDequeue([ref]$msg)) {
        # Discard or log remaining messages
    }

    # Final log entry
    if ($Context.FileLoggingEnabled -and $Context.LogFilePath) {
        try {
            $duration = if ($Context.StartTime -and $Context.EndTime) {
                ($Context.EndTime - $Context.StartTime).ToString('hh\:mm\:ss')
            } else { 'Unknown' }

            $finalMsg = "=== Messaging context closed. Total messages: $($Context.MessageCount), Errors: $($Context.ErrorCount), Duration: $duration ==="
            Add-Content -Path $Context.LogFilePath -Value $finalMsg -Encoding UTF8
        }
        catch {
            # Ignore cleanup errors
        }
    }
}

#endregion

#region Export Module Members

# Export all public functions
Export-ModuleMember -Function @(
    # Context management
    'New-FFUMessagingContext'
    'Test-FFUMessagingContext'
    'Close-FFUMessagingContext'

    # Message writing (background job)
    'Write-FFUMessage'
    'Write-FFUProgress'
    'Write-FFUInfo'
    'Write-FFUSuccess'
    'Write-FFUWarning'
    'Write-FFUError'
    'Write-FFUDebug'

    # Message reading (UI)
    'Read-FFUMessages'
    'Peek-FFUMessage'
    'Get-FFUMessageCount'

    # Build state
    'Set-FFUBuildState'
    'Request-FFUCancellation'
    'Test-FFUCancellationRequested'
)

#endregion
