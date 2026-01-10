<#
.SYNOPSIS
    Core classes and constants for FFU Builder

.DESCRIPTION
    This module provides foundational classes used throughout the FFU Builder system:
    - FFUConstants: Configuration constants and magic numbers
    - FFUPaths: Path validation and type safety (addresses Issue #324)
    - FFUNetworkConfiguration: Proxy and network settings (addresses Issue #327)
    - Invoke-FFUOperation: Error handling framework (addresses Issue #319)
#>

# ============================================================================
# FFUConstants Class - Configuration Constants
# ============================================================================
class FFUConstants {
    # Registry paths
    static [string] $REGISTRY_FILESYSTEM = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
    static [string] $REGISTRY_LONGPATHS = 'LongPathsEnabled'
    static [string] $REGISTRY_PROXY = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'

    # Timeouts (milliseconds)
    static [int] $LOG_POLL_INTERVAL = 1000
    static [int] $LOG_WAIT_TIMEOUT = 15000
    static [int] $PROCESS_CLEANUP_TIMEOUT = 5000
    static [int] $NETWORK_TIMEOUT = 5000

    # Retry configuration
    static [int] $DEFAULT_MAX_RETRIES = 3
    static [int] $DOWNLOAD_MAX_RETRIES = 5
    static [int] $NETWORK_MAX_RETRIES = 3

    # Disk space requirements (GB)
    static [int] $MIN_FREE_SPACE_GB = 50
    static [int] $RECOMMENDED_FREE_SPACE_GB = 100

    # Default VM configuration
    static [int] $DEFAULT_VM_MEMORY_GB = 8
    static [int] $DEFAULT_VM_PROCESSORS = 4
    static [long] $DEFAULT_VM_DISK_SIZE = 50GB

    # WinGet version requirements
    static [version] $MIN_WINGET_VERSION = [version]"1.8.1911"

    # Download buffer sizes
    static [int] $DOWNLOAD_BUFFER_SIZE = 8192

    # Log levels
    static [hashtable] $LOG_COLORS = @{
        'Debug'   = 'Gray'
        'Info'    = 'White'
        'Warning' = 'Yellow'
        'Error'   = 'Red'
        'Success' = 'Green'
    }
}

# ============================================================================
# FFUPaths Class - Path Validation and Type Safety (Issue #324)
# ============================================================================
class FFUPaths {
    [string]$FFUDevelopmentPath
    [string]$DriversFolder
    [string]$AppsPath
    [string]$VMPath
    [string]$ISOPath
    [string]$OutputFFUPath

    # Validates that a path is not a boolean value or empty string
    static [bool] ValidatePathNotBoolean([string]$Path, [string]$ParameterName) {
        if ([string]::IsNullOrWhiteSpace($Path)) {
            return $true # null/empty is valid for optional paths
        }

        # Check for boolean string values
        if ($Path -eq 'False' -or $Path -eq 'True' -or $Path -eq '$false' -or $Path -eq '$true' -or $Path -eq '0' -or $Path -eq '1') {
            throw "Invalid path value for parameter '$ParameterName': '$Path' appears to be a boolean value. Paths must be valid file system paths, not boolean values."
        }

        return $true
    }

    # Expands and validates a path
    static [string] ExpandPath([string]$Path, [string]$ParameterName) {
        if ([string]::IsNullOrWhiteSpace($Path)) {
            return $null
        }

        # Validate not boolean
        [FFUPaths]::ValidatePathNotBoolean($Path, $ParameterName)

        # Expand environment variables and relative paths
        try {
            $expandedPath = [System.Environment]::ExpandEnvironmentVariables($Path)

            # Convert to absolute path if it's not already
            if (-not [System.IO.Path]::IsPathRooted($expandedPath)) {
                $expandedPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $expandedPath))
            }

            return $expandedPath
        }
        catch {
            throw "Invalid path for parameter '$ParameterName': '$Path'. Error: $($_.Exception.Message)"
        }
    }

    # Validates that a path exists
    static [bool] ValidatePathExists([string]$Path, [string]$ParameterName, [bool]$MustExist = $true) {
        if ([string]::IsNullOrWhiteSpace($Path)) {
            if ($MustExist) {
                throw "Path parameter '$ParameterName' cannot be null or empty."
            }
            return $true
        }

        $expandedPath = [FFUPaths]::ExpandPath($Path, $ParameterName)

        if ($MustExist -and -not (Test-Path -LiteralPath $expandedPath)) {
            throw "Path for parameter '$ParameterName' does not exist: '$expandedPath'"
        }

        return $true
    }

    # Validates that a path exists and is a directory
    static [bool] ValidateDirectoryPath([string]$Path, [string]$ParameterName, [bool]$MustExist = $true) {
        if ([string]::IsNullOrWhiteSpace($Path)) {
            if ($MustExist) {
                throw "Directory path parameter '$ParameterName' cannot be null or empty."
            }
            return $true
        }

        $expandedPath = [FFUPaths]::ExpandPath($Path, $ParameterName)

        if ($MustExist) {
            if (-not (Test-Path -LiteralPath $expandedPath -PathType Container)) {
                throw "Directory path for parameter '$ParameterName' does not exist or is not a directory: '$expandedPath'"
            }
        }

        return $true
    }

    # Creates a directory if it doesn't exist
    static [string] EnsureDirectory([string]$Path, [string]$ParameterName) {
        $expandedPath = [FFUPaths]::ExpandPath($Path, $ParameterName)

        if (-not (Test-Path -LiteralPath $expandedPath)) {
            try {
                [void][System.IO.Directory]::CreateDirectory($expandedPath)
                WriteLog "Created directory: $expandedPath"
            }
            catch {
                throw "Failed to create directory for parameter '$ParameterName' at '$expandedPath': $($_.Exception.Message)"
            }
        }

        return $expandedPath
    }
}

# ============================================================================
# FFUNetworkConfiguration Class - Proxy Support (Issue #327)
# ============================================================================
class FFUNetworkConfiguration {
    [string]$ProxyServer
    [PSCredential]$ProxyCredential
    [string[]]$ProxyBypass
    [bool]$UseSystemProxy

    FFUNetworkConfiguration() {
        $this.ProxyBypass = @()
        $this.UseSystemProxy = $false
    }

    # Detects proxy settings from Windows configuration
    static [FFUNetworkConfiguration] DetectProxySettings() {
        $config = [FFUNetworkConfiguration]::new()

        try {
            # Check for environment variables first (common in corporate environments)
            $httpProxy = [System.Environment]::GetEnvironmentVariable('HTTP_PROXY')
            $httpsProxy = [System.Environment]::GetEnvironmentVariable('HTTPS_PROXY')
            $noProxy = [System.Environment]::GetEnvironmentVariable('NO_PROXY')

            if ($httpsProxy) {
                $config.ProxyServer = $httpsProxy
                WriteLog "Detected HTTPS proxy from environment: $httpsProxy"
            }
            elseif ($httpProxy) {
                $config.ProxyServer = $httpProxy
                WriteLog "Detected HTTP proxy from environment: $httpProxy"
            }

            if ($noProxy) {
                $config.ProxyBypass = $noProxy -split '[,;]' | ForEach-Object { $_.Trim() }
                WriteLog "Detected proxy bypass list: $($config.ProxyBypass -join ', ')"
            }

            # Check Windows Internet Settings if no environment variable
            if (-not $config.ProxyServer) {
                $regPath = [FFUConstants]::REGISTRY_PROXY
                if (Test-Path $regPath) {
                    $regProxy = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue

                    if ($regProxy.ProxyEnable -eq 1 -and $regProxy.ProxyServer) {
                        $config.ProxyServer = $regProxy.ProxyServer
                        $config.UseSystemProxy = $true
                        WriteLog "Detected system proxy from registry: $($config.ProxyServer)"
                    }

                    if ($regProxy.ProxyOverride) {
                        $config.ProxyBypass = $regProxy.ProxyOverride -split ';' | ForEach-Object { $_.Trim() }
                        WriteLog "Detected proxy bypass from registry: $($config.ProxyBypass -join ', ')"
                    }
                }
            }

            if (-not $config.ProxyServer) {
                WriteLog "No proxy configuration detected. Using direct connection."
            }
        }
        catch {
            WriteLog "Warning: Failed to detect proxy settings: $($_.Exception.Message)"
        }

        return $config
    }

    # Applies proxy configuration to a WebRequest
    [void] ApplyToWebRequest([System.Net.WebRequest]$Request) {
        if ($this.ProxyServer) {
            try {
                $proxy = New-Object System.Net.WebProxy($this.ProxyServer)

                if ($this.ProxyCredential) {
                    $proxy.Credentials = $this.ProxyCredential.GetNetworkCredential()
                }
                else {
                    $proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
                }

                if ($this.ProxyBypass -and $this.ProxyBypass.Count -gt 0) {
                    $proxy.BypassList = $this.ProxyBypass
                }

                $Request.Proxy = $proxy
                WriteLog "Applied proxy configuration to WebRequest: $($this.ProxyServer)"
            }
            catch {
                WriteLog "Warning: Failed to apply proxy configuration: $($_.Exception.Message)"
            }
        }
    }

    # Gets BITS proxy usage setting
    [string] GetBITSProxyUsage() {
        if ($this.ProxyServer) {
            return 'Override'
        }
        elseif ($this.UseSystemProxy) {
            return 'SystemDefault'
        }
        else {
            return 'AutoDetect'
        }
    }

    # Gets BITS proxy list
    [string[]] GetBITSProxyList() {
        if ($this.ProxyServer) {
            return @($this.ProxyServer)
        }
        return $null
    }

    # Tests connectivity to a URL
    [bool] TestConnectivity([string]$Url, [int]$TimeoutMs = 5000) {
        try {
            $request = [System.Net.WebRequest]::Create($Url)
            $request.Method = 'HEAD'
            $request.Timeout = $TimeoutMs

            # Apply proxy configuration
            $this.ApplyToWebRequest($request)

            $response = $request.GetResponse()
            $response.Close()

            WriteLog "Connectivity test to $Url succeeded"
            return $true
        }
        catch {
            WriteLog "Connectivity test to $Url failed: $($_.Exception.Message)"
            return $false
        }
    }
}

# ============================================================================
# Error Handling Framework (Issue #319)
# ============================================================================

<#
.SYNOPSIS
    Executes an operation with standardized error handling and retry logic

.DESCRIPTION
    Provides consistent error handling, retry logic with exponential backoff,
    and comprehensive logging for all FFU operations. Addresses Issue #319
    by preventing null reference exceptions through proper error handling.

.PARAMETER Operation
    The script block to execute

.PARAMETER OperationName
    Descriptive name for the operation (used in logging)

.PARAMETER MaxRetries
    Maximum number of retry attempts (default: 3)

.PARAMETER OnFailure
    Optional script block to execute when operation fails

.PARAMETER CriticalOperation
    If true, throws exception on failure. If false, logs warning and returns null

.PARAMETER RetryDelaySeconds
    Base delay in seconds before first retry (doubles for each subsequent retry)

.EXAMPLE
    Invoke-FFUOperation -Operation { Test-Path $somePath } -OperationName "Check path exists" -CriticalOperation

.EXAMPLE
    $result = Invoke-FFUOperation -Operation {
        Get-Item $path -ErrorAction Stop
    } -OperationName "Get file info" -MaxRetries 3 -OnFailure {
        WriteLog "Failed to get file info, cleaning up..."
    }
#>
function Invoke-FFUOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ScriptBlock]$Operation,

        [Parameter(Mandatory = $true)]
        [string]$OperationName,

        [int]$MaxRetries = [FFUConstants]::DEFAULT_MAX_RETRIES,

        [ScriptBlock]$OnFailure,

        [switch]$CriticalOperation,

        [int]$RetryDelaySeconds = 1
    )

    $retryCount = 0
    $lastError = $null

    while ($retryCount -le $MaxRetries) {
        try {
            $attemptNumber = $retryCount + 1
            WriteLog "Starting operation: $OperationName (Attempt $attemptNumber of $($MaxRetries + 1))"

            # Execute the operation
            $result = & $Operation

            WriteLog "Operation completed successfully: $OperationName"
            $result
            return
        }
        catch {
            $lastError = $_
            $errorMessage = $_.Exception.Message

            # Check for null reference exceptions specifically
            if ($_.Exception -is [System.NullReferenceException]) {
                $errorMessage = "Null reference error in ${OperationName}: ${errorMessage}. This likely indicates an object was not properly initialized."
            }

            WriteLog "WARNING: Operation failed: $OperationName - $errorMessage"

            if ($retryCount -eq $MaxRetries) {
                # All retries exhausted
                if ($CriticalOperation) {
                    WriteLog "ERROR: Critical operation failed after $($MaxRetries + 1) attempts: $OperationName"

                    if ($OnFailure) {
                        WriteLog "Executing failure callback for: $OperationName"
                        try {
                            & $OnFailure
                        }
                        catch {
                            WriteLog "ERROR: Failure callback itself failed: $($_.Exception.Message)"
                        }
                    }

                    throw $lastError
                }
                else {
                    WriteLog "WARNING: Non-critical operation failed, returning null: $OperationName"

                    if ($OnFailure) {
                        WriteLog "Executing failure callback for: $OperationName"
                        try {
                            & $OnFailure
                        }
                        catch {
                            WriteLog "ERROR: Failure callback itself failed: $($_.Exception.Message)"
                        }
                    }

                    $null
                    return
                }
            }

            # Calculate exponential backoff delay
            $delaySeconds = $RetryDelaySeconds * [Math]::Pow(2, $retryCount)
            WriteLog "WARNING: Retrying in $delaySeconds seconds..."
            Start-Sleep -Seconds $delaySeconds

            $retryCount++
        }
    }
}

<#
.SYNOPSIS
    Safely invokes a method on an object with null checking

.DESCRIPTION
    Prevents null reference exceptions by checking if object is null before
    invoking a method. Addresses Issue #319.

.PARAMETER Object
    The object to invoke the method on

.PARAMETER MethodName
    Name of the method to invoke

.PARAMETER Arguments
    Arguments to pass to the method

.PARAMETER DefaultValue
    Value to return if object is null

.EXAMPLE
    $result = Invoke-SafeMethod -Object $myObject -MethodName "GetValue" -Arguments @("key") -DefaultValue $null
#>
function Invoke-SafeMethod {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Object,

        [Parameter(Mandatory = $true)]
        [string]$MethodName,

        [Parameter(Mandatory = $false)]
        [object[]]$Arguments = @(),

        [Parameter(Mandatory = $false)]
        [object]$DefaultValue = $null
    )

    if ($null -eq $Object) {
        WriteLog "WARNING: Cannot invoke method '$MethodName' on null object. Returning default value."
        $DefaultValue
        return
    }

    try {
        if ($Arguments -and $Arguments.Count -gt 0) {
            $Object.$MethodName.Invoke($Arguments)
        }
        else {
            $Object.$MethodName.Invoke()
        }
    }
    catch [System.NullReferenceException] {
        WriteLog "ERROR: Null reference exception when invoking '$MethodName'. Object type: $($Object.GetType().FullName)"
        $DefaultValue
    }
    catch {
        WriteLog "ERROR: Error invoking method '$MethodName': $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    Safely gets a property value with null checking

.DESCRIPTION
    Prevents null reference exceptions by checking if object is null before
    accessing a property. Addresses Issue #319.

.PARAMETER Object
    The object to get the property from

.PARAMETER PropertyName
    Name of the property to get

.PARAMETER DefaultValue
    Value to return if object is null or property doesn't exist

.EXAMPLE
    $value = Get-SafeProperty -Object $myObject -PropertyName "Name" -DefaultValue "Unknown"
#>
function Get-SafeProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Object,

        [Parameter(Mandatory = $true)]
        [string]$PropertyName,

        [Parameter(Mandatory = $false)]
        [object]$DefaultValue = $null
    )

    if ($null -eq $Object) {
        WriteLog "WARNING: Cannot get property '$PropertyName' from null object. Returning default value."
        $DefaultValue
        return
    }

    try {
        if ($Object.PSObject.Properties[$PropertyName]) {
            $Object.$PropertyName
        }
        else {
            WriteLog "WARNING: Property '$PropertyName' does not exist on object of type $($Object.GetType().FullName). Returning default value."
            $DefaultValue
        }
    }
    catch [System.NullReferenceException] {
        WriteLog "ERROR: Null reference exception when accessing property '$PropertyName'. Object type: $($Object.GetType().FullName)"
        $DefaultValue
    }
    catch {
        WriteLog "ERROR: Error accessing property '$PropertyName': $($_.Exception.Message)"
        $DefaultValue
    }
}

# Export module members
Export-ModuleMember -Function @(
    'Invoke-FFUOperation',
    'Invoke-SafeMethod',
    'Get-SafeProperty'
)
