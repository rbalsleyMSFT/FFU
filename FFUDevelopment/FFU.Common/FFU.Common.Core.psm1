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
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$LogText
    )

    # Handle null/empty LogText gracefully - this prevents "Cannot bind argument to parameter 'LogText' because it is an empty string"
    if ([string]::IsNullOrWhiteSpace($LogText)) {
        # Don't log empty messages, but don't throw an error either
        return
    }

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

# Helper function to extract error message from exception objects
# This prevents the "Cannot bind argument to parameter 'LogText' because it is an empty string" error
function Get-ErrorMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $ErrorRecord
    )

    if ($null -eq $ErrorRecord) {
        return "[No error details available]"
    }

    # Handle ErrorRecord objects (from catch blocks)
    if ($ErrorRecord -is [System.Management.Automation.ErrorRecord]) {
        $message = $ErrorRecord.Exception.Message
        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = $ErrorRecord.ToString()
        }
        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = "[Error occurred but no message available. Type: $($ErrorRecord.Exception.GetType().FullName)]"
        }
        return $message
    }

    # Handle Exception objects directly
    if ($ErrorRecord -is [System.Exception]) {
        $message = $ErrorRecord.Message
        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = "[Exception occurred but no message available. Type: $($ErrorRecord.GetType().FullName)]"
        }
        return $message
    }

    # Handle string or other objects
    $message = $ErrorRecord.ToString()
    if ([string]::IsNullOrWhiteSpace($message)) {
        return "[Error object could not be converted to string. Type: $($ErrorRecord.GetType().FullName)]"
    }
    return $message
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
        WriteLog (Get-ErrorMessage $_)
        # Write-Host "Script failed - $Logfile for more info"
        throw $_

    }
    finally {
        # Validate paths before Remove-Item to prevent "Path argument was null or an empty collection" error
        $pathsToRemove = @($stdOutTempFile, $stdErrTempFile) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        if ($pathsToRemove.Count -gt 0) {
            Remove-Item -Path $pathsToRemove -Force -ErrorAction Ignore
        }
    }
    return $cmd
}

# Function to download a file using BITS with automatic fallback to other methods
function Start-BitsTransferWithRetry {
    <#
    .SYNOPSIS
        Downloads a file using BITS with automatic fallback to alternate methods

    .DESCRIPTION
        Attempts to download using BITS first. If BITS fails (especially with
        authentication error 0x800704DD), automatically falls back to:
        1. Invoke-WebRequest
        2. System.Net.WebClient
        3. curl.exe

        This ensures downloads work even when BITS credentials are unavailable.

        Supports proxy configuration for corporate environments (addresses Issue #327).

    .PARAMETER Source
        URL to download from

    .PARAMETER Destination
        Local file path to save to

    .PARAMETER Retries
        Number of retry attempts per method (default: 3)

    .PARAMETER Credential
        Optional credentials for authenticated downloads

    .PARAMETER Authentication
        Authentication method for BITS (default: Negotiate)

    .PARAMETER UseResilientDownload
        Use multi-method fallback system (default: $true)
        Set to $false to use BITS-only behavior (legacy)

    .PARAMETER ProxyConfig
        Optional FFUNetworkConfiguration object for proxy support
        If not provided, proxy settings will be auto-detected
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Destination,

        [int]$Retries = 3,

        [PSCredential]$Credential = $null,

        [ValidateSet('Basic', 'Digest', 'NTLM', 'Negotiate', 'Passport')]
        [string]$Authentication = 'Negotiate',

        [bool]$UseResilientDownload = $true,

        [object]$ProxyConfig = $null
    )

    # Auto-detect proxy configuration if not provided
    if ($null -eq $ProxyConfig) {
        try {
            if ([FFUNetworkConfiguration] -as [type]) {
                $ProxyConfig = [FFUNetworkConfiguration]::DetectProxySettings()
            }
        }
        catch {
            WriteLog "Could not auto-detect proxy settings: $($_.Exception.Message)"
        }
    }

    # If resilient download is enabled, use the multi-method fallback system
    if ($UseResilientDownload) {
        try {
            # Check if Start-ResilientDownload is available from FFU.Common.Download module
            if (Get-Command Start-ResilientDownload -ErrorAction SilentlyContinue) {
                WriteLog "Using resilient multi-method download system"

                $downloadParams = @{
                    Source      = $Source
                    Destination = $Destination
                    Retries     = $Retries
                }

                if ($Credential) {
                    $downloadParams['Credential'] = $Credential
                }

                if ($ProxyConfig) {
                    $downloadParams['ProxyConfig'] = $ProxyConfig
                }

                Start-ResilientDownload @downloadParams
                return
            }
            else {
                WriteLog "WARNING: Start-ResilientDownload not available, falling back to BITS-only mode"
            }
        }
        catch {
            # If resilient download fails, log and fall through to legacy BITS behavior
            WriteLog "Resilient download failed: $($_.Exception.Message)"
            WriteLog "Attempting legacy BITS-only download as fallback"
        }
    }

    # Legacy BITS-only behavior (preserved for compatibility)
    $attempt = 0
    $lastError = $null

    while ($attempt -lt $Retries) {
        $OriginalVerbosePreference = $VerbosePreference
        $OriginalProgressPreference = $ProgressPreference
        try {
            $VerbosePreference = 'SilentlyContinue'
            $ProgressPreference = 'SilentlyContinue'

            # Build BITS transfer parameters
            $bitsParams = @{
                Source      = $Source
                Destination = $Destination
                Priority    = 'Normal'
                ErrorAction = 'Stop'
            }

            # Add credential parameters if provided
            if ($null -ne $Credential) {
                $bitsParams['Credential'] = $Credential
                $bitsParams['Authentication'] = $Authentication
                WriteLog "Using explicit credentials for BITS transfer with authentication: $Authentication"
            }

            # Add proxy configuration if available (addresses Issue #327)
            if ($null -ne $ProxyConfig) {
                try {
                    $proxyUsage = $ProxyConfig.GetBITSProxyUsage()
                    $proxyList = $ProxyConfig.GetBITSProxyList()

                    $bitsParams['ProxyUsage'] = $proxyUsage

                    if ($proxyList -and $proxyList.Count -gt 0) {
                        $bitsParams['ProxyList'] = $proxyList
                        WriteLog "Using proxy for BITS transfer: $($proxyList -join ', ')"
                    }

                    if ($ProxyConfig.ProxyCredential) {
                        $bitsParams['ProxyCredential'] = $ProxyConfig.ProxyCredential
                        WriteLog "Using proxy credentials for BITS transfer"
                    }
                }
                catch {
                    WriteLog "Warning: Failed to apply proxy configuration to BITS transfer: $($_.Exception.Message)"
                }
            }

            Start-BitsTransfer @bitsParams

            $ProgressPreference = $OriginalProgressPreference
            $VerbosePreference = $OriginalVerbosePreference
            WriteLog "Successfully transferred $Source to $Destination."
            return
        }
        catch {
            $lastError = $_
            $attempt++

            # Check for specific BITS authentication error
            $errorCode = $lastError.Exception.HResult
            if ($errorCode -eq 0x800704DD -or $errorCode -eq -2147023651) {
                WriteLog "BITS authentication error detected (0x800704DD: ERROR_NOT_LOGGED_ON)."
                WriteLog "This typically means the current process does not have network credentials."
                WriteLog "RECOMMENDATION: Enable -UseResilientDownload for automatic fallback to alternate download methods."
                WriteLog "Or ensure the script runs with Start-ThreadJob instead of Start-Job."
                # Don't retry authentication errors with BITS
                break
            }

            WriteLog "Attempt $attempt of $Retries failed to download $Source. Error: $($lastError.Exception.Message)."

            # Only sleep and retry if we haven't hit max retries
            if ($attempt -lt $Retries) {
                $sleepSeconds = 2 * $attempt  # Exponential backoff: 2s, 4s, 6s, etc.
                WriteLog "Waiting $sleepSeconds seconds before retry..."
                Start-Sleep -Seconds $sleepSeconds
            }
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