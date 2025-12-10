#Requires -Version 5.1

<#
.SYNOPSIS
    FFU Builder Structured Logging Module
.DESCRIPTION
    Provides structured logging with log levels, JSON output, and session correlation.
#>

# Log levels enum
enum FFULogLevel {
    Debug = 0
    Info = 1
    Success = 2
    Warning = 3
    Error = 4
    Critical = 5
}

# Session state for structured logging
$script:FFULogSession = @{
    SessionId = $null
    LogPath = $null
    JsonLogPath = $null
    MinLevel = [FFULogLevel]::Info
    StartTime = $null
}

function Initialize-FFULogging {
    <#
    .SYNOPSIS
        Initializes the structured logging system.
    .PARAMETER LogPath
        Path to the primary log file (human-readable format).
    .PARAMETER MinLevel
        Minimum log level to record. Default is Info.
    .PARAMETER EnableJsonLog
        If true, also creates a .json.log file with structured entries.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogPath,

        [Parameter(Mandatory = $false)]
        [FFULogLevel]$MinLevel = [FFULogLevel]::Info,

        [Parameter(Mandatory = $false)]
        [switch]$EnableJsonLog
    )

    $script:FFULogSession.SessionId = [Guid]::NewGuid().ToString()
    $script:FFULogSession.LogPath = $LogPath
    $script:FFULogSession.MinLevel = $MinLevel
    $script:FFULogSession.StartTime = Get-Date

    if ($EnableJsonLog) {
        $script:FFULogSession.JsonLogPath = [System.IO.Path]::ChangeExtension($LogPath, '.json.log')
    }

    # Ensure log directory exists
    $logDir = Split-Path -Path $LogPath -Parent
    if (-not [string]::IsNullOrEmpty($logDir) -and -not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }

    # Log session start
    Write-FFULog -Level Info -Message "Logging session initialized" -Context @{
        SessionId = $script:FFULogSession.SessionId
        MinLevel = $MinLevel.ToString()
        JsonEnabled = $EnableJsonLog.IsPresent
    }
}

function Write-FFULog {
    <#
    .SYNOPSIS
        Writes a structured log entry.
    .PARAMETER Level
        Log level (Debug, Info, Success, Warning, Error, Critical).
    .PARAMETER Message
        Log message text.
    .PARAMETER Context
        Optional hashtable of additional context data.
    .EXAMPLE
        Write-FFULog -Level Info -Message "Starting VM creation" -Context @{ VMName = "FFU_Build"; Memory = 8GB }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [FFULogLevel]$Level,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [hashtable]$Context = @{}
    )

    # Skip if below minimum level
    if ($Level -lt $script:FFULogSession.MinLevel) {
        return
    }

    # Handle empty messages
    if ([string]::IsNullOrWhiteSpace($Message)) {
        return
    }

    $timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffzzz'
    $displayTimestamp = Get-Date -Format 'M/d/yyyy h:mm:ss tt'

    # Create structured entry
    $entry = [ordered]@{
        Timestamp = $timestamp
        SessionId = $script:FFULogSession.SessionId
        Level = $Level.ToString()
        Message = $Message
        Context = $Context
        ComputerName = $env:COMPUTERNAME
        User = $env:USERNAME
    }

    # Write to JSON log if enabled
    if ($script:FFULogSession.JsonLogPath) {
        try {
            $json = $entry | ConvertTo-Json -Compress -Depth 5
            Add-Content -Path $script:FFULogSession.JsonLogPath -Value $json -ErrorAction SilentlyContinue
        }
        catch {
            # Silently ignore JSON logging errors
        }
    }

    # Format human-readable entry
    $levelTag = "[$($Level.ToString().ToUpper())]".PadRight(10)
    $humanEntry = "$displayTimestamp $levelTag $Message"

    # Add context to human-readable log if present
    if ($Context.Count -gt 0) {
        $contextStr = ($Context.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', '
        $humanEntry += " | $contextStr"
    }

    # Write to primary log file
    if ($script:FFULogSession.LogPath) {
        try {
            Add-Content -Path $script:FFULogSession.LogPath -Value $humanEntry -ErrorAction SilentlyContinue
        }
        catch {
            # Fall back to Write-Host if file write fails
        }
    }

    # Write to console with color
    $color = switch ($Level) {
        ([FFULogLevel]::Debug) { 'Gray' }
        ([FFULogLevel]::Info) { 'White' }
        ([FFULogLevel]::Success) { 'Green' }
        ([FFULogLevel]::Warning) { 'Yellow' }
        ([FFULogLevel]::Error) { 'Red' }
        ([FFULogLevel]::Critical) { 'Magenta' }
    }

    Write-Host $humanEntry -ForegroundColor $color
}

# Convenience functions for each log level
function Write-FFUDebug {
    <#
    .SYNOPSIS
        Writes a debug-level log entry.
    .PARAMETER Message
        Log message text.
    .PARAMETER Context
        Optional hashtable of additional context data.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [hashtable]$Context = @{}
    )
    Write-FFULog -Level Debug -Message $Message -Context $Context
}

function Write-FFUInfo {
    <#
    .SYNOPSIS
        Writes an info-level log entry.
    .PARAMETER Message
        Log message text.
    .PARAMETER Context
        Optional hashtable of additional context data.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [hashtable]$Context = @{}
    )
    Write-FFULog -Level Info -Message $Message -Context $Context
}

function Write-FFUSuccess {
    <#
    .SYNOPSIS
        Writes a success-level log entry.
    .PARAMETER Message
        Log message text.
    .PARAMETER Context
        Optional hashtable of additional context data.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [hashtable]$Context = @{}
    )
    Write-FFULog -Level Success -Message $Message -Context $Context
}

function Write-FFUWarning {
    <#
    .SYNOPSIS
        Writes a warning-level log entry.
    .PARAMETER Message
        Log message text.
    .PARAMETER Context
        Optional hashtable of additional context data.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [hashtable]$Context = @{}
    )
    Write-FFULog -Level Warning -Message $Message -Context $Context
}

function Write-FFUError {
    <#
    .SYNOPSIS
        Writes an error-level log entry.
    .PARAMETER Message
        Log message text.
    .PARAMETER Context
        Optional hashtable of additional context data.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [hashtable]$Context = @{}
    )
    Write-FFULog -Level Error -Message $Message -Context $Context
}

function Write-FFUCritical {
    <#
    .SYNOPSIS
        Writes a critical-level log entry.
    .PARAMETER Message
        Log message text.
    .PARAMETER Context
        Optional hashtable of additional context data.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [hashtable]$Context = @{}
    )
    Write-FFULog -Level Critical -Message $Message -Context $Context
}

function Get-FFULogSession {
    <#
    .SYNOPSIS
        Returns current logging session information.
    .DESCRIPTION
        Returns a copy of the current logging session state including
        SessionId, LogPath, JsonLogPath, MinLevel, and StartTime.
    .EXAMPLE
        $session = Get-FFULogSession
        Write-Host "Session ID: $($session.SessionId)"
    #>
    [CmdletBinding()]
    param()
    return $script:FFULogSession.Clone()
}

function Close-FFULogging {
    <#
    .SYNOPSIS
        Closes the logging session and writes summary.
    .DESCRIPTION
        Writes a final log entry with session duration and resets
        the logging session state.
    .EXAMPLE
        Close-FFULogging
    #>
    [CmdletBinding()]
    param()

    if ($script:FFULogSession.SessionId) {
        $duration = (Get-Date) - $script:FFULogSession.StartTime
        Write-FFULog -Level Info -Message "Logging session closed" -Context @{
            Duration = $duration.ToString()
            TotalSeconds = [math]::Round($duration.TotalSeconds, 2)
        }

        # Reset session
        $script:FFULogSession.SessionId = $null
        $script:FFULogSession.LogPath = $null
        $script:FFULogSession.JsonLogPath = $null
        $script:FFULogSession.StartTime = $null
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Initialize-FFULogging',
    'Write-FFULog',
    'Write-FFUDebug',
    'Write-FFUInfo',
    'Write-FFUSuccess',
    'Write-FFUWarning',
    'Write-FFUError',
    'Write-FFUCritical',
    'Get-FFULogSession',
    'Close-FFULogging'
)
