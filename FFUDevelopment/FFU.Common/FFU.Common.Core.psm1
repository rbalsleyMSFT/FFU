<#
.SYNOPSIS
    Provides core, shared functions for logging, process execution, and resilient file transfers used across the FFU project.
.DESCRIPTION
    This module is a central component of the FFU project, offering a set of robust, reusable functions. 
    It includes a centralized logging mechanism (WriteLog), a wrapper for running external processes with error handling (Invoke-Process), 
    a retry-aware BITS transfer function for reliable downloads (Start-BitsTransferWithRetry), and a progress reporting helper. 
    This module is designed to be imported by other scripts and modules within the project to ensure consistent behavior for common tasks.
#>
# Script-scoped variable for the log file path
$script:CommonCoreLogFilePath = $null
# Mutex for log file access
$script:commonCoreLogMutexName = "Global\FFUCommonCoreLogMutex" # Unique name
$script:commonCoreLogMutex = New-Object System.Threading.Mutex($false, $script:commonCoreLogMutexName)

# Function to set the log file path for this module
function Set-CommonCoreLogPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    $script:CommonCoreLogFilePath = $Path
    if (-not [string]::IsNullOrWhiteSpace($script:CommonCoreLogFilePath)) {
        # This initial WriteLog confirms the path is set and the logger is working.
        WriteLog "CommonCoreLogPath set to: $script:CommonCoreLogFilePath"
    }
    else {
        # This Write-Warning will appear on console if path is bad, but won't go to log file yet.
        Write-Warning "Set-CommonCoreLogPath called with an empty or null path."
    }
}

# Centralized WriteLog function
function WriteLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogText
    )

    # Check if the log file path has been set
    if ([string]::IsNullOrWhiteSpace($script:CommonCoreLogFilePath)) {
        Write-Warning "CommonCoreLogFilePath not set. Message: $LogText"
        return
    }

    $logEntry = "$((Get-Date).ToString()) $LogText"
    $streamWriter = $null

    try {
        $script:commonCoreLogMutex.WaitOne() | Out-Null
        # Ensure directory exists before writing
        $logDir = Split-Path -Path $script:CommonCoreLogFilePath -Parent
        if (-not (Test-Path -Path $logDir -PathType Container)) {
            New-Item -Path $logDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
        }
        $streamWriter = New-Object System.IO.StreamWriter($script:CommonCoreLogFilePath, $true, [System.Text.Encoding]::UTF8)
        $streamWriter.WriteLine($logEntry)

        Write-Verbose $LogText
    }
    catch {
        # Use Write-Host for console visibility as Write-Warning might also try to log
        Write-Host "WARNING: Error writing to log file '$($script:CommonCoreLogFilePath)': $($_.Exception.Message)" -ForegroundColor Yellow
    }
    finally {
        if ($null -ne $streamWriter) {
            $streamWriter.Dispose()
        }
        $script:commonCoreLogMutex.ReleaseMutex()
    }
}

function Invoke-Process {
    [CmdletBinding(SupportsShouldProcess)]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]]$ArgumentList,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [bool]$Wait = $true
    )

    $ErrorActionPreference = 'Stop'

    try {
        $stdOutTempFile = "$env:TEMP\$((New-Guid).Guid)"
        $stdErrTempFile = "$env:TEMP\$((New-Guid).Guid)"

        $startProcessParams = @{
            FilePath               = $FilePath
            ArgumentList           = $ArgumentList
            RedirectStandardError  = $stdErrTempFile
            RedirectStandardOutput = $stdOutTempFile
            Wait                   = $($Wait);
            PassThru               = $true;
            NoNewWindow            = $true;
        }
        if ($PSCmdlet.ShouldProcess("Process [$($FilePath)]", "Run with args: [$($ArgumentList)]")) {
            $cmd = Start-Process @startProcessParams
            $cmdOutput = Get-Content -Path $stdOutTempFile -Raw
            $cmdError = Get-Content -Path $stdErrTempFile -Raw
            if ($cmd.ExitCode -ne 0 -and $wait -eq $true) {
                if ($cmdError) {
                    throw $cmdError.Trim()
                }
                if ($cmdOutput) {
                    throw $cmdOutput.Trim()
                }
            }
            else {
                if ([string]::IsNullOrEmpty($cmdOutput) -eq $false) {
                    WriteLog $cmdOutput
                }
            }
        }
    }
    catch {
        #$PSCmdlet.ThrowTerminatingError($_)
        WriteLog $_
        # Write-Host "Script failed - $Logfile for more info"
        throw $_

    }
    finally {
        Remove-Item -Path $stdOutTempFile, $stdErrTempFile -Force -ErrorAction Ignore
    }
    return $cmd
}

# Function to download a file using BITS with retry and error handling
function Start-BitsTransferWithRetry {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Source,
        [Parameter(Mandatory = $true)]
        [string]$Destination,
        [int]$Retries = 3
    )

    $attempt = 0
    $lastError = $null

    while ($attempt -lt $Retries) {
        $OriginalVerbosePreference = $VerbosePreference
        $OriginalProgressPreference = $ProgressPreference
        try {
            $VerbosePreference = 'SilentlyContinue' 
            $ProgressPreference = 'SilentlyContinue' 

            Start-BitsTransfer -Source $Source -Destination $Destination -Priority Normal -ErrorAction Stop
            
            $ProgressPreference = $OriginalProgressPreference
            $VerbosePreference = $OriginalVerbosePreference
            WriteLog "Successfully transferred $Source to $Destination." 
            return 
        }
        catch {
            $lastError = $_
            $attempt++
            WriteLog "Attempt $attempt of $Retries failed to download $Source. Error: $($lastError.Exception.Message)." 
            Start-Sleep -Seconds (1 * $attempt) 
        }
        finally {
            if (Get-Variable -Name 'OriginalProgressPreference' -ErrorAction SilentlyContinue) {
                $ProgressPreference = $OriginalProgressPreference
            }
            if (Get-Variable -Name 'OriginalVerbosePreference' -ErrorAction SilentlyContinue) {
                $VerbosePreference = $OriginalVerbosePreference
            }
        }
    }

    WriteLog "Failed to download $Source after $Retries attempts. Last Error: $($lastError.Exception.Message)" 
    throw $lastError 
}
    
function Set-Progress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$Percentage,
        [Parameter(Mandatory)]
        [string]$Message
    )
    WriteLog "[PROGRESS] $Percentage | $Message"
}
    
function ConvertTo-SafeName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )
    # Replace invalid Windows filename characters (<>:"/\|?* and control chars) with a dash
    $sanitized = $Name -replace '[<>:\"/\\|?*\x00-\x1F]', '-'
    # Collapse multiple consecutive dashes
    $sanitized = $sanitized -replace '-{2,}', '-'
    # Trim leading/trailing spaces, periods, and dashes
    $sanitized = $sanitized.Trim(' ','.','-')
    if ([string]::IsNullOrWhiteSpace($sanitized)) {
        $sanitized = 'Unnamed'
    }
    return $sanitized
}

Export-ModuleMember -Function *