<#
.SYNOPSIS
    Advanced multi-method file download with automatic fallback support

.DESCRIPTION
    This module provides robust file downloading with multiple methods:
    1. BITS (Background Intelligent Transfer Service) - Primary method
    2. Invoke-WebRequest - PowerShell native fallback
    3. System.Net.WebClient - .NET fallback
    4. curl.exe - Native Windows utility fallback

    Automatically falls back through methods if one fails, with special handling
    for BITS authentication error 0x800704DD.
#>

# Import WriteLog from FFU.Common.Core if available
# Uses $function: drive instead of Get-Command for ThreadJob compatibility (v0.0.12)
if ($function:WriteLog) {
    # WriteLog is available from FFU.Common.Core
}
else {
    # Fallback logging function
    # Uses [DateTime]::Now instead of Get-Date for ThreadJob runspace compatibility
    # Uses [Console]::WriteLine instead of Write-Host for ThreadJob runspace compatibility (v0.0.11)
    function WriteLog {
        param([string]$LogText)
        $timestamp = [DateTime]::Now.ToString("yyyy-MM-dd HH:mm:ss")
        Write-Verbose "[$timestamp] $LogText"
        [Console]::WriteLine("[$timestamp] $LogText")
    }
}

enum DownloadMethod {
    BITS
    WebRequest
    WebClient
    Curl
}

function Start-ResilientDownload {
    <#
    .SYNOPSIS
        Downloads a file using multiple fallback methods with retry logic

    .DESCRIPTION
        Attempts to download a file using multiple methods in order:
        1. BITS (if available and credentials present)
        2. Invoke-WebRequest with credentials
        3. System.Net.WebClient
        4. curl.exe (Windows native)

        Automatically falls back if a method fails, with special handling for
        authentication errors. Supports proxy configuration for corporate environments.

    .PARAMETER Source
        The URL to download from

    .PARAMETER Destination
        The local file path to save to

    .PARAMETER Retries
        Number of retry attempts per method (default: 3)

    .PARAMETER Credential
        Optional credentials for authenticated downloads

    .PARAMETER PreferredMethod
        Preferred download method to try first (default: BITS)

    .PARAMETER SkipBITS
        Skip BITS entirely and go straight to fallback methods

    .PARAMETER ProxyConfig
        Optional FFUNetworkConfiguration object for proxy support

    .EXAMPLE
        Start-ResilientDownload -Source "https://example.com/file.zip" -Destination "C:\temp\file.zip"

    .EXAMPLE
        Start-ResilientDownload -Source $url -Destination $dest -SkipBITS -Retries 5
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Destination,

        [int]$Retries = 3,

        [PSCredential]$Credential = $null,

        [DownloadMethod]$PreferredMethod = [DownloadMethod]::BITS,

        [switch]$SkipBITS,

        [object]$ProxyConfig = $null
    )

    $attemptedMethods = @()
    $lastError = $null

    # Determine order of methods to try
    $methodOrder = @()

    if (-not $SkipBITS -and $PreferredMethod -eq [DownloadMethod]::BITS) {
        $methodOrder += [DownloadMethod]::BITS
    }

    $methodOrder += [DownloadMethod]::WebRequest
    $methodOrder += [DownloadMethod]::WebClient
    $methodOrder += [DownloadMethod]::Curl

    WriteLog "Starting resilient download: $Source"
    WriteLog "Destination: $Destination"
    WriteLog "Methods available: $($methodOrder -join ' -> ')"

    foreach ($method in $methodOrder) {
        $attemptedMethods += $method

        try {
            WriteLog "Attempting download using method: $method"

            switch ($method) {
                ([DownloadMethod]::BITS) {
                    $result = Invoke-BITSDownload -Source $Source -Destination $Destination -Retries $Retries -Credential $Credential -ProxyConfig $ProxyConfig
                    if ($result) {
                        WriteLog "SUCCESS: Downloaded using BITS"
                        $true
                        return
                    }
                }

                ([DownloadMethod]::WebRequest) {
                    $result = Invoke-WebRequestDownload -Source $Source -Destination $Destination -Retries $Retries -Credential $Credential -ProxyConfig $ProxyConfig
                    if ($result) {
                        WriteLog "SUCCESS: Downloaded using Invoke-WebRequest"
                        $true
                        return
                    }
                }

                ([DownloadMethod]::WebClient) {
                    $result = Invoke-WebClientDownload -Source $Source -Destination $Destination -Retries $Retries -Credential $Credential -ProxyConfig $ProxyConfig
                    if ($result) {
                        WriteLog "SUCCESS: Downloaded using WebClient"
                        $true
                        return
                    }
                }

                ([DownloadMethod]::Curl) {
                    $result = Invoke-CurlDownload -Source $Source -Destination $Destination -Retries $Retries -ProxyConfig $ProxyConfig
                    if ($result) {
                        WriteLog "SUCCESS: Downloaded using curl"
                        $true
                        return
                    }
                }
            }
        }
        catch {
            $lastError = $_
            WriteLog "Method $method failed: $($_.Exception.Message)"

            # Don't try more methods if it's a 404 or similar client error
            if ($_.Exception.Message -match '404|403|401') {
                WriteLog "HTTP client error detected - file may not exist. Stopping fallback attempts."
                throw
            }

            # Continue to next method
            continue
        }
    }

    # All methods failed
    $errorMessage = "All download methods failed for $Source. Attempted methods: $($attemptedMethods -join ', ')"
    WriteLog $errorMessage

    if ($lastError) {
        throw $lastError
    }
    else {
        throw $errorMessage
    }
}

function Invoke-BITSDownload {
    <#
    .SYNOPSIS
        Download using BITS with authentication error detection
    #>
    [CmdletBinding()]
    param(
        [string]$Source,
        [string]$Destination,
        [int]$Retries,
        [PSCredential]$Credential,
        [object]$ProxyConfig = $null
    )

    # BITS availability is checked via try/catch on actual call for ThreadJob compatibility (v0.0.12)
    # Get-Command can become unavailable in ThreadJob runspaces during heavy operations

    $attempt = 0
    while ($attempt -lt $Retries) {
        try {
            $attempt++

            $bitsParams = @{
                Source      = $Source
                Destination = $Destination
                Priority    = 'Normal'
                ErrorAction = 'Stop'
            }

            if ($Credential) {
                $bitsParams['Credential'] = $Credential
                $bitsParams['Authentication'] = 'Negotiate'
            }

            # Apply proxy configuration if provided
            if ($null -ne $ProxyConfig) {
                try {
                    $proxyUsage = $ProxyConfig.GetBITSProxyUsage()
                    $proxyList = $ProxyConfig.GetBITSProxyList()

                    $bitsParams['ProxyUsage'] = $proxyUsage

                    if ($proxyList -and $proxyList.Count -gt 0) {
                        $bitsParams['ProxyList'] = $proxyList
                        WriteLog "Using proxy for BITS: $($proxyList -join ', ')"
                    }

                    if ($ProxyConfig.ProxyCredential) {
                        $bitsParams['ProxyCredential'] = $ProxyConfig.ProxyCredential
                    }
                }
                catch {
                    WriteLog "Warning: Could not apply proxy configuration to BITS: $($_.Exception.Message)"
                }
            }

            # Suppress progress for cleaner output
            $OriginalProgressPreference = $ProgressPreference
            $ProgressPreference = 'SilentlyContinue'

            Start-BitsTransfer @bitsParams

            $ProgressPreference = $OriginalProgressPreference

            # Verify file was created
            if (Test-Path -Path $Destination) {
                $fileSize = (Get-Item -Path $Destination).Length
                WriteLog "BITS download successful ($fileSize bytes)"
                $true
                        return
            }
            else {
                WriteLog "BITS reported success but file not found"
                $false
                return
            }
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            # BITS cmdlet not available (ThreadJob compatibility - v0.0.12)
            WriteLog "BITS cmdlet not available, skipping"
            $false
            return
        }
        catch {
            $errorCode = $_.Exception.HResult

            # Check for authentication error 0x800704DD
            if ($errorCode -eq 0x800704DD -or $errorCode -eq -2147023651) {
                WriteLog "BITS authentication error 0x800704DD detected - network credentials not available"
                WriteLog "Skipping BITS and falling back to alternate download methods"
                $false
                return  # Don't retry BITS, move to next method
            }

            WriteLog "BITS attempt $attempt/$Retries failed: $($_.Exception.Message)"

            if ($attempt -lt $Retries) {
                $sleepSeconds = 2 * $attempt
                WriteLog "Waiting $sleepSeconds seconds before retry..."
                Start-Sleep -Seconds $sleepSeconds
            }
        }
    }

    $false
    return
}

function Invoke-WebRequestDownload {
    <#
    .SYNOPSIS
        Download using Invoke-WebRequest with progress support
    #>
    [CmdletBinding()]
    param(
        [string]$Source,
        [string]$Destination,
        [int]$Retries,
        [PSCredential]$Credential,
        [object]$ProxyConfig = $null
    )

    $attempt = 0
    while ($attempt -lt $Retries) {
        try {
            $attempt++

            $webRequestParams = @{
                Uri             = $Source
                OutFile         = $Destination
                UseBasicParsing = $true
                ErrorAction     = 'Stop'
            }

            # Add credentials if provided
            if ($Credential) {
                $webRequestParams['Credential'] = $Credential
            }
            else {
                # Try to use default credentials
                $webRequestParams['UseDefaultCredentials'] = $true
            }

            # Apply proxy configuration if provided
            if ($null -ne $ProxyConfig -and $ProxyConfig.ProxyServer) {
                $webRequestParams['Proxy'] = $ProxyConfig.ProxyServer
                WriteLog "Using proxy for Invoke-WebRequest: $($ProxyConfig.ProxyServer)"

                if ($ProxyConfig.ProxyCredential) {
                    $webRequestParams['ProxyCredential'] = $ProxyConfig.ProxyCredential
                }
                else {
                    $webRequestParams['ProxyUseDefaultCredentials'] = $true
                }
            }

            # Suppress progress for large files (much faster)
            $OriginalProgressPreference = $ProgressPreference
            $ProgressPreference = 'SilentlyContinue'

            WriteLog "Invoke-WebRequest attempt $attempt/$Retries"
            Invoke-WebRequest @webRequestParams

            $ProgressPreference = $OriginalProgressPreference

            # Verify file was created
            if (Test-Path -Path $Destination) {
                $fileSize = (Get-Item -Path $Destination).Length
                WriteLog "Invoke-WebRequest download successful ($fileSize bytes)"
                $true
                        return
            }
            else {
                WriteLog "Invoke-WebRequest completed but file not found"
                $false
                return
            }
        }
        catch {
            WriteLog "Invoke-WebRequest attempt $attempt/$Retries failed: $($_.Exception.Message)"

            if ($attempt -lt $Retries) {
                $sleepSeconds = 2 * $attempt
                WriteLog "Waiting $sleepSeconds seconds before retry..."
                Start-Sleep -Seconds $sleepSeconds
            }
        }
    }

    $false
                return
}

function Invoke-WebClientDownload {
    <#
    .SYNOPSIS
        Download using System.Net.WebClient (synchronous, reliable)
    #>
    [CmdletBinding()]
    param(
        [string]$Source,
        [string]$Destination,
        [int]$Retries,
        [PSCredential]$Credential,
        [object]$ProxyConfig = $null
    )

    $attempt = 0
    while ($attempt -lt $Retries) {
        try {
            $attempt++

            $webClient = New-Object System.Net.WebClient

            # Configure credentials
            if ($Credential) {
                $webClient.Credentials = $Credential.GetNetworkCredential()
            }
            else {
                $webClient.UseDefaultCredentials = $true
            }

            # Apply proxy configuration if provided
            if ($null -ne $ProxyConfig -and $ProxyConfig.ProxyServer) {
                $proxy = New-Object System.Net.WebProxy($ProxyConfig.ProxyServer)

                if ($ProxyConfig.ProxyCredential) {
                    $proxy.Credentials = $ProxyConfig.ProxyCredential.GetNetworkCredential()
                }
                else {
                    $proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
                }

                if ($ProxyConfig.ProxyBypass -and $ProxyConfig.ProxyBypass.Count -gt 0) {
                    $proxy.BypassList = $ProxyConfig.ProxyBypass
                }

                $webClient.Proxy = $proxy
                WriteLog "Using proxy for WebClient: $($ProxyConfig.ProxyServer)"
            }

            # Set modern TLS protocols
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13

            WriteLog "WebClient attempt $attempt/$Retries"
            $webClient.DownloadFile($Source, $Destination)

            $webClient.Dispose()

            # Verify file was created
            if (Test-Path -Path $Destination) {
                $fileSize = (Get-Item -Path $Destination).Length
                WriteLog "WebClient download successful ($fileSize bytes)"
                $true
                        return
            }
            else {
                WriteLog "WebClient completed but file not found"
                $false
                return
            }
        }
        catch {
            WriteLog "WebClient attempt $attempt/$Retries failed: $($_.Exception.Message)"

            if ($webClient) {
                $webClient.Dispose()
            }

            if ($attempt -lt $Retries) {
                $sleepSeconds = 2 * $attempt
                WriteLog "Waiting $sleepSeconds seconds before retry..."
                Start-Sleep -Seconds $sleepSeconds
            }
        }
    }

    $false
                return
}

function Invoke-CurlDownload {
    <#
    .SYNOPSIS
        Download using curl.exe (native Windows utility since Windows 10 1803)
    #>
    [CmdletBinding()]
    param(
        [string]$Source,
        [string]$Destination,
        [int]$Retries,
        [object]$ProxyConfig = $null
    )

    # Check if curl.exe is available using ThreadJob-safe path search (v0.0.12)
    # Get-Command can become unavailable in ThreadJob runspaces during heavy operations
    $curlPath = $null
    if (Get-Command -Name 'Find-ExecutableInPath' -ErrorAction SilentlyContinue) {
        $curlPath = Find-ExecutableInPath -Name 'curl.exe'
    }
    else {
        # Fallback: search PATH manually (same logic as Find-ExecutableInPath)
        foreach ($dir in $env:PATH -split ';') {
            if ([string]::IsNullOrWhiteSpace($dir)) { continue }
            $testPath = Join-Path $dir 'curl.exe'
            if ([System.IO.File]::Exists($testPath)) {
                $curlPath = $testPath
                break
            }
        }
    }
    if (-not $curlPath) {
        WriteLog "curl.exe not found in PATH, skipping"
        $false
        return
    }

    $attempt = 0
    while ($attempt -lt $Retries) {
        try {
            $attempt++

            # Build curl arguments
            $curlArgs = @(
                '--location',              # Follow redirects
                '--silent',                # Silent mode
                '--show-error',            # Show errors
                '--fail',                  # Fail on HTTP errors
                '--retry', '2',            # Retry on transient errors
                '--retry-delay', '2',      # Delay between retries
                '--max-time', '300'        # 5 minute timeout
            )

            # Apply proxy configuration if provided
            if ($null -ne $ProxyConfig -and $ProxyConfig.ProxyServer) {
                $curlArgs += '--proxy'
                $curlArgs += "`"$($ProxyConfig.ProxyServer)`""
                WriteLog "Using proxy for curl: $($ProxyConfig.ProxyServer)"

                if ($ProxyConfig.ProxyCredential) {
                    $proxyUser = $ProxyConfig.ProxyCredential.UserName
                    $proxyPass = $ProxyConfig.ProxyCredential.GetNetworkCredential().Password
                    $curlArgs += '--proxy-user'
                    $curlArgs += "`"${proxyUser}:${proxyPass}`""
                }
            }

            $curlArgs += '--output'
            $curlArgs += "`"$Destination`""
            $curlArgs += "`"$Source`""

            WriteLog "curl.exe attempt $attempt/$Retries"
            # Don't log the full command if it contains credentials
            if ($ProxyConfig -and $ProxyConfig.ProxyCredential) {
                WriteLog "Command: curl.exe [args with credentials redacted]"
            }
            else {
                WriteLog "Command: curl.exe $($curlArgs -join ' ')"
            }

            $process = Start-Process -FilePath $curlPath -ArgumentList $curlArgs -Wait -PassThru -NoNewWindow

            if ($process.ExitCode -eq 0) {
                # Verify file was created
                if (Test-Path -Path $Destination) {
                    $fileSize = (Get-Item -Path $Destination).Length
                    WriteLog "curl download successful ($fileSize bytes)"
                    $true
                        return
                }
                else {
                    WriteLog "curl reported success but file not found"
                    $false
                return
                }
            }
            else {
                WriteLog "curl exited with code $($process.ExitCode)"

                if ($attempt -lt $Retries) {
                    $sleepSeconds = 2 * $attempt
                    WriteLog "Waiting $sleepSeconds seconds before retry..."
                    Start-Sleep -Seconds $sleepSeconds
                }
            }
        }
        catch {
            WriteLog "curl attempt $attempt/$Retries failed: $($_.Exception.Message)"

            if ($attempt -lt $Retries) {
                $sleepSeconds = 2 * $attempt
                WriteLog "Waiting $sleepSeconds seconds before retry..."
                Start-Sleep -Seconds $sleepSeconds
            }
        }
    }

    $false
                return
}

# Export functions
Export-ModuleMember -Function Start-ResilientDownload, Invoke-BITSDownload, Invoke-WebRequestDownload, Invoke-WebClientDownload, Invoke-CurlDownload
