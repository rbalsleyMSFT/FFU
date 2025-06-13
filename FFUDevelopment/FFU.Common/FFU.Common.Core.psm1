# FFU.Common.Core.psm1
# Contains common core functions like logging and process invocation.

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

# Function to invoke external process
# function Invoke-Process {
#     [CmdletBinding(SupportsShouldProcess)]
#     param(
#         [Parameter(Mandatory)]
#         [ValidateNotNullOrEmpty()]
#         [string]$FilePath,
#         [Parameter()]
#         [ValidateNotNullOrEmpty()]
#         [string[]]$ArgumentList,
#         [Parameter()]
#         [ValidateNotNullOrEmpty()]
#         [bool]$Wait = $true
#     )

#     $ErrorActionPreference = 'Stop' # Keep this local to the function

#     try {
#         $stdOutTempFile = "$env:TEMP\$((New-Guid).Guid)"
#         $stdErrTempFile = "$env:TEMP\$((New-Guid).Guid)"

#         $startProcessParams = @{
#             FilePath               = $FilePath
#             ArgumentList           = $ArgumentList
#             RedirectStandardError  = $stdErrTempFile
#             RedirectStandardOutput = $stdOutTempFile
#             Wait                   = $Wait 
#             PassThru               = $true
#             NoNewWindow            = $true
#         }

#         # DEBUG
#         # WriteLog "Running Command: $($startProcessParams.FilePath) $($startProcessParams.ArgumentList -join ' ')"

#         if ($PSCmdlet.ShouldProcess("Process [$($FilePath)]", "Run with args: [$($ArgumentList)]")) {
#             $cmd = Start-Process @startProcessParams
#             $cmdOutput = Get-Content -Path $stdOutTempFile -Raw -ErrorAction SilentlyContinue 
#             $cmdError = Get-Content -Path $stdErrTempFile -Raw -ErrorAction SilentlyContinue  
            
#             if (-not [string]::IsNullOrWhiteSpace($cmdOutput)) {
#                 WriteLog "STDOUT from '$FilePath': $cmdOutput"
#             }
#             if (-not [string]::IsNullOrWhiteSpace($cmdError)) {
#                 WriteLog "STDERR from '$FilePath': $cmdError"
#             }

#             if ($cmd.ExitCode -ne 0 -and $Wait) { 
#                 $errorMessage = "Process '$FilePath' exited with code $($cmd.ExitCode)."
#                 if (-not [string]::IsNullOrWhiteSpace($cmdError)) {
#                     $errorMessage += " Error: $cmdError"
#                 }
#                 elseif (-not [string]::IsNullOrWhiteSpace($cmdOutput)) {
#                     $errorMessage += " Output: $cmdOutput"
#                 }
#                 throw $errorMessage.Trim()
#             }
#         }
#     }
#     catch {
#         WriteLog "Error in Invoke-Process for '$FilePath': $($_.Exception.Message)" 
#         throw 
#     }
#     finally {
#         if (Test-Path $stdOutTempFile) { Remove-Item -Path $stdOutTempFile -Force -ErrorAction Ignore }
#         if (Test-Path $stdErrTempFile) { Remove-Item -Path $stdErrTempFile -Force -ErrorAction Ignore }
#     }
#     return $cmd 
# }

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

            Start-BitsTransfer -Source $Source -Destination $Destination -ErrorAction Stop
            
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

Export-ModuleMember -Function *