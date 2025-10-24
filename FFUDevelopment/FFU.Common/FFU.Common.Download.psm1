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
if (Get-Command WriteLog -ErrorAction SilentlyContinue) {
    # WriteLog is available from FFU.Common.Core
}
else {
    # Fallback logging function
    function WriteLog {
        param([string]$LogText)
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Verbose "[$timestamp] $LogText"
        Write-Host "[$timestamp] $LogText"
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
        authentication errors.

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

        [switch]$SkipBITS
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
                    $result = Invoke-BITSDownload -Source $Source -Destination $Destination -Retries $Retries -Credential $Credential
                    if ($result) {
                        WriteLog "SUCCESS: Downloaded using BITS"
                        return $true
                    }
                }

                ([DownloadMethod]::WebRequest) {
                    $result = Invoke-WebRequestDownload -Source $Source -Destination $Destination -Retries $Retries -Credential $Credential
                    if ($result) {
                        WriteLog "SUCCESS: Downloaded using Invoke-WebRequest"
                        return $true
                    }
                }

                ([DownloadMethod]::WebClient) {
                    $result = Invoke-WebClientDownload -Source $Source -Destination $Destination -Retries $Retries -Credential $Credential
                    if ($result) {
                        WriteLog "SUCCESS: Downloaded using WebClient"
                        return $true
                    }
                }

                ([DownloadMethod]::Curl) {
                    $result = Invoke-CurlDownload -Source $Source -Destination $Destination -Retries $Retries
                    if ($result) {
                        WriteLog "SUCCESS: Downloaded using curl"
                        return $true
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
        [PSCredential]$Credential
    )

    # Check if BITS is available
    if (-not (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue)) {
        WriteLog "BITS cmdlet not available, skipping"
        return $false
    }

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

            # Suppress progress for cleaner output
            $OriginalProgressPreference = $ProgressPreference
            $ProgressPreference = 'SilentlyContinue'

            Start-BitsTransfer @bitsParams

            $ProgressPreference = $OriginalProgressPreference

            # Verify file was created
            if (Test-Path $Destination) {
                $fileSize = (Get-Item $Destination).Length
                WriteLog "BITS download successful ($fileSize bytes)"
                return $true
            }
            else {
                WriteLog "BITS reported success but file not found"
                return $false
            }
        }
        catch {
            $errorCode = $_.Exception.HResult

            # Check for authentication error 0x800704DD
            if ($errorCode -eq 0x800704DD -or $errorCode -eq -2147023651) {
                WriteLog "BITS authentication error 0x800704DD detected - network credentials not available"
                WriteLog "Skipping BITS and falling back to alternate download methods"
                return $false  # Don't retry BITS, move to next method
            }

            WriteLog "BITS attempt $attempt/$Retries failed: $($_.Exception.Message)"

            if ($attempt -lt $Retries) {
                $sleepSeconds = 2 * $attempt
                WriteLog "Waiting $sleepSeconds seconds before retry..."
                Start-Sleep -Seconds $sleepSeconds
            }
        }
    }

    return $false
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
        [PSCredential]$Credential
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

            # Suppress progress for large files (much faster)
            $OriginalProgressPreference = $ProgressPreference
            $ProgressPreference = 'SilentlyContinue'

            WriteLog "Invoke-WebRequest attempt $attempt/$Retries"
            Invoke-WebRequest @webRequestParams

            $ProgressPreference = $OriginalProgressPreference

            # Verify file was created
            if (Test-Path $Destination) {
                $fileSize = (Get-Item $Destination).Length
                WriteLog "Invoke-WebRequest download successful ($fileSize bytes)"
                return $true
            }
            else {
                WriteLog "Invoke-WebRequest completed but file not found"
                return $false
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

    return $false
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
        [PSCredential]$Credential
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

            # Set modern TLS protocols
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13

            WriteLog "WebClient attempt $attempt/$Retries"
            $webClient.DownloadFile($Source, $Destination)

            $webClient.Dispose()

            # Verify file was created
            if (Test-Path $Destination) {
                $fileSize = (Get-Item $Destination).Length
                WriteLog "WebClient download successful ($fileSize bytes)"
                return $true
            }
            else {
                WriteLog "WebClient completed but file not found"
                return $false
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

    return $false
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
        [int]$Retries
    )

    # Check if curl.exe is available
    $curlPath = (Get-Command curl.exe -ErrorAction SilentlyContinue).Source
    if (-not $curlPath) {
        WriteLog "curl.exe not found in PATH, skipping"
        return $false
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
                '--max-time', '300',       # 5 minute timeout
                '--output', "`"$Destination`"",  # Output file
                "`"$Source`""              # URL (quoted for spaces)
            )

            WriteLog "curl.exe attempt $attempt/$Retries"
            WriteLog "Command: curl.exe $($curlArgs -join ' ')"

            $process = Start-Process -FilePath $curlPath -ArgumentList $curlArgs -Wait -PassThru -NoNewWindow

            if ($process.ExitCode -eq 0) {
                # Verify file was created
                if (Test-Path $Destination) {
                    $fileSize = (Get-Item $Destination).Length
                    WriteLog "curl download successful ($fileSize bytes)"
                    return $true
                }
                else {
                    WriteLog "curl reported success but file not found"
                    return $false
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

    return $false
}

# Export functions
Export-ModuleMember -Function Start-ResilientDownload, Invoke-BITSDownload, Invoke-WebRequestDownload, Invoke-WebClientDownload, Invoke-CurlDownload
