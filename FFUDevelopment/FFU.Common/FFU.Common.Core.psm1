#Requires -Version 7.0

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
# Script-scoped variable for FFU.Messaging context (for real-time UI updates)
# When set, WriteLog will also write messages to the messaging queue
$script:CommonCoreMessagingContext = $null
# Mutex for log file access
$script:commonCoreLogMutexName = "Global\FFUCommonCoreLogMutex" # Unique name
$script:commonCoreLogMutex = New-Object System.Threading.Mutex($false, $script:commonCoreLogMutexName)

# Function to set the log file path for this module
function Set-CommonCoreLogPath {
    <#
    .SYNOPSIS
        Sets the log file path for the FFU.Common.Core logging system.
    .DESCRIPTION
        Configures the log file path used by WriteLog function. Optionally deletes
        any existing log file to start a fresh logging session.
    .PARAMETER Path
        The full path to the log file.
    .PARAMETER Initialize
        When specified, deletes any existing log file at the path before setting it.
        This ensures a clean log file for the new session.
    .EXAMPLE
        Set-CommonCoreLogPath -Path "C:\FFUDevelopment\FFUDevelopment.log"
        Sets the log path without clearing existing content.
    .EXAMPLE
        Set-CommonCoreLogPath -Path "C:\FFUDevelopment\FFUDevelopment.log" -Initialize
        Clears any existing log file and starts a fresh logging session.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [switch]$Initialize
    )

    # Validate the path is not empty
    if ([string]::IsNullOrWhiteSpace($Path)) {
        Write-Warning "Set-CommonCoreLogPath called with an empty or null path."
        return
    }

    # If -Initialize is specified, delete any existing log file first
    if ($Initialize) {
        if (Test-Path -Path $Path -PathType Leaf) {
            try {
                Remove-Item -Path $Path -Force -ErrorAction Stop
                Write-Verbose "Removed existing log file: $Path"
            }
            catch {
                Write-Warning "Failed to remove existing log file '$Path': $($_.Exception.Message)"
            }
        }
    }

    # Set the script-scoped log file path
    $script:CommonCoreLogFilePath = $Path

    # Ensure the log directory exists
    $logDir = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($logDir) -and -not (Test-Path -Path $logDir -PathType Container)) {
        try {
            New-Item -Path $logDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Write-Verbose "Created log directory: $logDir"
        }
        catch {
            Write-Warning "Failed to create log directory '$logDir': $($_.Exception.Message)"
        }
    }

    # Log the initialization message
    if ($Initialize) {
        WriteLog "=== Fresh log session started at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="
        WriteLog "CommonCoreLogPath set to: $script:CommonCoreLogFilePath"
    }
    else {
        WriteLog "CommonCoreLogPath set to: $script:CommonCoreLogFilePath"
    }
}

# Function to set the messaging context for real-time UI updates
function Set-CommonCoreMessagingContext {
    <#
    .SYNOPSIS
        Sets the FFU.Messaging context for real-time UI updates via WriteLog.
    .DESCRIPTION
        When a messaging context is set, WriteLog will write messages to both:
        1. The log file (FFUDevelopment.log)
        2. The messaging queue for real-time UI display

        This enables the Monitor tab in BuildFFUVM_UI.ps1 to display log entries
        in real-time (50ms polling) instead of waiting for file system updates.
    .PARAMETER Context
        The synchronized hashtable from New-FFUMessagingContext (FFU.Messaging module).
        Must contain a MessageQueue property (ConcurrentQueue).
        Pass $null to disable messaging integration.
    .EXAMPLE
        # In ThreadJob scriptblock after importing FFU.Messaging:
        Set-CommonCoreMessagingContext -Context $SyncContext

        # All subsequent WriteLog calls will also write to the queue
        WriteLog "This appears in both file and UI"
    .EXAMPLE
        # Disable messaging integration:
        Set-CommonCoreMessagingContext -Context $null
    .NOTES
        This function is typically called by BuildFFUVM_UI.ps1's ThreadJob scriptblock
        after importing FFU.Common.Core, to enable real-time log updates in the Monitor tab.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [hashtable]$Context
    )

    $script:CommonCoreMessagingContext = $Context

    if ($null -ne $Context) {
        Write-Verbose "CommonCoreMessagingContext set - WriteLog will write to messaging queue"
    }
    else {
        Write-Verbose "CommonCoreMessagingContext cleared - WriteLog will only write to file"
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

    # Track whether we wrote to at least one destination
    $wroteToFile = $false
    $wroteToQueue = $false

    # Write to log file if path is set
    if (-not [string]::IsNullOrWhiteSpace($script:CommonCoreLogFilePath)) {
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
            $wroteToFile = $true

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

    # Also write to messaging queue if context is set (for real-time UI updates)
    # This enables the Monitor tab to display log entries via the fast queue polling (50ms)
    # instead of waiting for the slower file polling fallback
    # NOTE: This runs EVEN if log file path isn't set - queue is primary for UI updates
    if ($null -ne $script:CommonCoreMessagingContext -and $null -ne $script:CommonCoreMessagingContext.MessageQueue) {
        try {
            # Create FFUMessage-compatible object for the queue
            # Using [PSCustomObject] to match FFU.Messaging's FFUMessage class structure
            $msgObject = [PSCustomObject]@{
                Timestamp = [DateTime]::Now
                Level     = 'Info'  # Default to Info level for WriteLog messages
                Message   = $LogText
                Source    = 'WriteLog'
                Data      = @{}
            }

            # Add ToLogString method for compatibility with UI timer's message processing
            $msgObject | Add-Member -MemberType ScriptMethod -Name 'ToLogString' -Value {
                return "$($this.Timestamp.ToString('yyyy-MM-dd HH:mm:ss.fff')) [$($this.Level.ToString().PadRight(8))] $($this.Message)"
            }

            # Enqueue the message (thread-safe via ConcurrentQueue)
            $script:CommonCoreMessagingContext.MessageQueue.Enqueue($msgObject)
            $wroteToQueue = $true
        }
        catch {
            # Don't fail the log operation if messaging fails
            # This is a best-effort enhancement for real-time UI updates
        }
    }

    # Warn only if we couldn't write anywhere (neither file nor queue)
    if (-not $wroteToFile -and -not $wroteToQueue) {
        Write-Warning "CommonCoreLogFilePath not set and no messaging queue. Message: $LogText"
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
        "[No error details available]"
        return
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
        $message
        return
    }

    # Handle Exception objects directly
    if ($ErrorRecord -is [System.Exception]) {
        $message = $ErrorRecord.Message
        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = "[Exception occurred but no message available. Type: $($ErrorRecord.GetType().FullName)]"
        }
        $message
        return
    }

    # Handle string or other objects
    $message = $ErrorRecord.ToString()
    if ([string]::IsNullOrWhiteSpace($message)) {
        "[Error object could not be converted to string. Type: $($ErrorRecord.GetType().FullName)]"
        return
    }
    $message
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
                $errorMessage = "Process '$FilePath' exited with code $($cmd.ExitCode)."
                if ($cmdError) {
                    $errorMessage += " Error: $($cmdError.Trim())"
                }
                elseif ($cmdOutput) {
                    $errorMessage += " Output: $($cmdOutput.Trim())"
                }
                else {
                    $errorMessage += " No error output captured."
                }
                throw $errorMessage
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
    $cmd
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
    $sanitized
}

function Get-FFUBuilderVersion {
    <#
    .SYNOPSIS
        Retrieves FFU Builder version information from version.json.
    .DESCRIPTION
        Reads the central version.json file and returns version information
        for FFU Builder and all its modules. This is the single source of truth
        for all versioning in the project.
    .PARAMETER FFUDevelopmentPath
        Path to the FFUDevelopment folder. If not specified, attempts to find
        version.json relative to this module's location.
    .PARAMETER ModuleName
        Optional. If specified, returns only the version for that specific module.
    .EXAMPLE
        Get-FFUBuilderVersion
        Returns the full version object with main version and all module versions.
    .EXAMPLE
        Get-FFUBuilderVersion -ModuleName "FFU.Common"
        Returns just the version string for FFU.Common module.
    .OUTPUTS
        PSCustomObject with version information, or string if -ModuleName specified.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$FFUDevelopmentPath,

        [Parameter(Mandatory = $false)]
        [string]$ModuleName
    )

    # Determine version.json path
    if ([string]::IsNullOrWhiteSpace($FFUDevelopmentPath)) {
        # Try to find version.json relative to this module
        $modulePath = $PSScriptRoot
        if ($modulePath) {
            $FFUDevelopmentPath = Split-Path -Parent $modulePath
        }
    }

    $versionFile = Join-Path $FFUDevelopmentPath "version.json"

    if (-not (Test-Path -Path $versionFile -PathType Leaf)) {
        Write-Warning "version.json not found at: $versionFile"
        $null
        return
    }

    try {
        $versionData = Get-Content -Path $versionFile -Raw | ConvertFrom-Json

        # If a specific module was requested, return just that version
        if (-not [string]::IsNullOrWhiteSpace($ModuleName)) {
            if ($versionData.modules.PSObject.Properties.Name -contains $ModuleName) {
                $versionData.modules.$ModuleName.version
                return
            }
            else {
                Write-Warning "Module '$ModuleName' not found in version.json"
                $null
                return
            }
        }

        # Return the full version object
        [PSCustomObject]@{
            Version     = $versionData.version
            BuildDate   = $versionData.buildDate
            Modules     = $versionData.modules
            Policy      = $versionData.versioningPolicy
            VersionFile = $versionFile
        }
    }
    catch {
        Write-Warning "Failed to parse version.json: $($_.Exception.Message)"
        $null
    }
}

function Update-FFUBuilderVersion {
    <#
    .SYNOPSIS
        Updates the FFU Builder version in version.json.
    .DESCRIPTION
        Increments the version number according to SemVer rules and updates
        the build date. Use this after making changes to any module.
    .PARAMETER FFUDevelopmentPath
        Path to the FFUDevelopment folder.
    .PARAMETER BumpType
        Type of version bump: Major, Minor, or Patch.
    .PARAMETER ModuleName
        Optional. If specified, also updates that module's version in version.json.
    .PARAMETER ModuleVersion
        Required if ModuleName is specified. The new version for the module.
    .EXAMPLE
        Update-FFUBuilderVersion -FFUDevelopmentPath "C:\FFUDevelopment" -BumpType Patch
        Increments the patch version (e.g., 1.2.0 -> 1.2.1).
    .EXAMPLE
        Update-FFUBuilderVersion -FFUDevelopmentPath "C:\FFUDevelopment" -BumpType Patch -ModuleName "FFU.Common" -ModuleVersion "0.0.5"
        Increments main patch version and updates FFU.Common module version.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Major', 'Minor', 'Patch')]
        [string]$BumpType,

        [Parameter(Mandatory = $false)]
        [string]$ModuleName,

        [Parameter(Mandatory = $false)]
        [string]$ModuleVersion
    )

    $versionFile = Join-Path $FFUDevelopmentPath "version.json"

    if (-not (Test-Path -Path $versionFile -PathType Leaf)) {
        throw "version.json not found at: $versionFile"
    }

    try {
        $versionData = Get-Content -Path $versionFile -Raw | ConvertFrom-Json

        # Parse current version
        $versionParts = $versionData.version -split '\.'
        $major = [int]$versionParts[0]
        $minor = [int]$versionParts[1]
        $patch = [int]$versionParts[2]

        # Apply bump
        switch ($BumpType) {
            'Major' {
                $major++
                $minor = 0
                $patch = 0
            }
            'Minor' {
                $minor++
                $patch = 0
            }
            'Patch' {
                $patch++
            }
        }

        $newVersion = "$major.$minor.$patch"
        $newBuildDate = (Get-Date).ToString('yyyy-MM-dd')

        if ($PSCmdlet.ShouldProcess("version.json", "Update version from $($versionData.version) to $newVersion")) {
            $versionData.version = $newVersion
            $versionData.buildDate = $newBuildDate

            # Update module version if specified
            if (-not [string]::IsNullOrWhiteSpace($ModuleName) -and -not [string]::IsNullOrWhiteSpace($ModuleVersion)) {
                if ($versionData.modules.PSObject.Properties.Name -contains $ModuleName) {
                    $versionData.modules.$ModuleName.version = $ModuleVersion
                    WriteLog "Updated $ModuleName version to $ModuleVersion in version.json"
                }
                else {
                    Write-Warning "Module '$ModuleName' not found in version.json"
                }
            }

            # Write back to file with proper formatting
            $versionData | ConvertTo-Json -Depth 10 | Set-Content -Path $versionFile -Encoding UTF8
            WriteLog "Updated FFU Builder version to $newVersion (build $newBuildDate)"

            return [PSCustomObject]@{
                OldVersion = $versionData.version
                NewVersion = $newVersion
                BuildDate  = $newBuildDate
                BumpType   = $BumpType
            }
        }
    }
    catch {
        throw "Failed to update version.json: $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function *