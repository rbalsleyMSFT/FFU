<#
.SYNOPSIS
    Starts the VMware Workstation vmrest.exe REST API service

.DESCRIPTION
    Manages the vmrest.exe service that provides REST API access to VMware Workstation.
    - Detects VMware Workstation installation path
    - Starts vmrest.exe if not already running
    - Validates the REST API is accessible
    - Supports custom port and credential configuration

.PARAMETER Port
    The port number for vmrest to listen on. Default is 8697.

.PARAMETER Credential
    PSCredential object for vmrest authentication.
    If not provided, attempts to use stored credentials.

.PARAMETER VMwarePath
    Override path to VMware Workstation installation.
    If not specified, auto-detects from registry/default paths.

.PARAMETER TimeoutSeconds
    How long to wait for vmrest to become available. Default 30 seconds.

.PARAMETER Force
    Restart vmrest even if it's already running.

.OUTPUTS
    [hashtable] with properties:
    - Success: [bool] whether vmrest is running and accessible
    - Port: [int] the port vmrest is listening on
    - BaseUrl: [string] the full base URL for API calls
    - ProcessId: [int] the vmrest process ID
    - Error: [string] error message if failed

.EXAMPLE
    $result = Start-VMrestService
    if ($result.Success) {
        Write-Host "vmrest accessible at $($result.BaseUrl)"
    }

.EXAMPLE
    $cred = Get-Credential -UserName "admin"
    $result = Start-VMrestService -Credential $cred -Port 8698

.NOTES
    Module: FFU.Hypervisor
    Version: 1.0.0
    VMware Workstation 17.x required
#>

function Start-VMrestService {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $false)]
        [int]$Port = 8697,

        [Parameter(Mandatory = $false)]
        [PSCredential]$Credential,

        [Parameter(Mandatory = $false)]
        [string]$VMwarePath,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 30,

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    $result = @{
        Success = $false
        Port = $Port
        BaseUrl = "http://127.0.0.1:$Port/api"
        ProcessId = $null
        Error = $null
        VMrestPath = $null
    }

    try {
        # Find VMware Workstation installation
        $vmrestPath = $null

        if (-not [string]::IsNullOrWhiteSpace($VMwarePath)) {
            $vmrestPath = Join-Path $VMwarePath 'vmrest.exe'
        }
        else {
            # Try registry first
            $regPaths = @(
                'HKLM:\SOFTWARE\VMware, Inc.\VMware Workstation',
                'HKLM:\SOFTWARE\WOW6432Node\VMware, Inc.\VMware Workstation'
            )

            foreach ($regPath in $regPaths) {
                if (Test-Path $regPath) {
                    $installPath = (Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue).InstallPath
                    if ($installPath -and (Test-Path (Join-Path $installPath 'vmrest.exe'))) {
                        $vmrestPath = Join-Path $installPath 'vmrest.exe'
                        break
                    }
                }
            }

            # Try default paths if registry lookup failed
            if (-not $vmrestPath) {
                $defaultPaths = @(
                    'C:\Program Files (x86)\VMware\VMware Workstation\vmrest.exe',
                    'C:\Program Files\VMware\VMware Workstation\vmrest.exe'
                )

                foreach ($path in $defaultPaths) {
                    if (Test-Path $path) {
                        $vmrestPath = $path
                        break
                    }
                }
            }
        }

        if (-not $vmrestPath -or -not (Test-Path $vmrestPath)) {
            $result.Error = "VMware Workstation vmrest.exe not found. Please ensure VMware Workstation Pro is installed."
            return $result
        }

        $result.VMrestPath = $vmrestPath
        WriteLog "Found vmrest.exe at: $vmrestPath"

        # Check if vmrest is already running
        $existingProcess = Get-Process -Name 'vmrest' -ErrorAction SilentlyContinue

        if ($existingProcess -and -not $Force) {
            WriteLog "vmrest is already running (PID: $($existingProcess.Id))"
            $result.ProcessId = $existingProcess.Id

            # Verify it's accessible
            if (Test-VMrestEndpoint -Port $Port -Credential $Credential) {
                $result.Success = $true
                return $result
            }
            else {
                WriteLog "WARNING: vmrest process found but API not accessible. Restarting..."
                Stop-Process -Id $existingProcess.Id -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
            }
        }
        elseif ($existingProcess -and $Force) {
            WriteLog "Stopping existing vmrest process (PID: $($existingProcess.Id))..."
            Stop-Process -Id $existingProcess.Id -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }

        # Start vmrest
        WriteLog "Starting vmrest on port $Port..."

        # Build credential file if needed
        $credentialConfigured = Test-VMrestCredentialsConfigured -VMrestPath $vmrestPath

        if (-not $credentialConfigured) {
            if (-not $Credential) {
                $result.Error = "vmrest credentials not configured. Please run 'vmrest.exe -C' to configure credentials, or provide -Credential parameter."
                return $result
            }

            # Note: vmrest -C is interactive, so we can't configure it programmatically here
            # The user must have already run 'vmrest.exe -C' to set up credentials
            $result.Error = "vmrest credentials not configured. Please run '$vmrestPath -C' interactively to set up credentials."
            return $result
        }

        # Start vmrest as a background process
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $vmrestPath
        $psi.Arguments = "-p $Port"
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $psi.WindowStyle = 'Hidden'

        $process = [System.Diagnostics.Process]::Start($psi)

        if (-not $process) {
            $result.Error = "Failed to start vmrest process"
            return $result
        }

        $result.ProcessId = $process.Id
        WriteLog "vmrest started (PID: $($process.Id))"

        # Wait for vmrest to become available
        $startTime = Get-Date
        $isAvailable = $false

        while (((Get-Date) - $startTime).TotalSeconds -lt $TimeoutSeconds) {
            Start-Sleep -Seconds 1

            # Check if process is still running
            if ($process.HasExited) {
                $stderr = $process.StandardError.ReadToEnd()
                $result.Error = "vmrest exited unexpectedly. Error: $stderr"
                return $result
            }

            # Try to connect
            if (Test-VMrestEndpoint -Port $Port -Credential $Credential) {
                $isAvailable = $true
                break
            }
        }

        if (-not $isAvailable) {
            $result.Error = "vmrest did not become available within $TimeoutSeconds seconds"
            return $result
        }

        WriteLog "vmrest is ready at $($result.BaseUrl)"
        $result.Success = $true
        return $result
    }
    catch {
        $result.Error = "Failed to start vmrest: $($_.Exception.Message)"
        WriteLog "ERROR: $($result.Error)"
        return $result
    }
}

<#
.SYNOPSIS
    Tests if vmrest endpoint is accessible

.DESCRIPTION
    Tests if vmrest is listening on the specified port. This function uses a two-step approach:
    1. TCP connection test to verify vmrest is listening
    2. HTTP request that accepts both success (200) AND authentication failure (401) as "vmrest is running"

    A 401 Unauthorized response means vmrest IS running and responding, just needs credentials.
    Authentication is handled by subsequent API calls, not during startup validation.

.PARAMETER Port
    The port to test (default 8697)

.PARAMETER Credential
    Optional credential for authenticated test. If not provided, function will still
    return $true for 401 responses since that confirms vmrest is running.
#>
function Test-VMrestEndpoint {
    [CmdletBinding()]
    param(
        [int]$Port = 8697,
        [PSCredential]$Credential
    )

    try {
        # Step 1: Quick TCP connection test
        WriteLog "Test-VMrestEndpoint: Testing TCP connection to 127.0.0.1:$Port..."
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $connectTask = $tcpClient.ConnectAsync('127.0.0.1', $Port)
        $connected = $connectTask.Wait(2000) # 2 second timeout
        $tcpClient.Close()
        $tcpClient.Dispose()

        if (-not $connected) {
            WriteLog "Test-VMrestEndpoint: TCP connection FAILED - port not listening"
            return $false
        }
        WriteLog "Test-VMrestEndpoint: TCP connection SUCCESS - port is listening"

        # Step 2: HTTP request - accept both 200 OK and 401 Unauthorized as "vmrest is running"
        $uri = "http://127.0.0.1:$Port/api/vms"
        WriteLog "Test-VMrestEndpoint: Testing HTTP endpoint $uri..."

        $params = @{
            Uri = $uri
            Method = 'GET'
            TimeoutSec = 5
            ErrorAction = 'Stop'
        }

        # Use explicit Basic auth header if credential provided
        if ($Credential) {
            $authHeader = Get-BasicAuthHeader -Credential $Credential
            $params['Headers'] = @{ Authorization = $authHeader }
            WriteLog "Test-VMrestEndpoint: Using provided credentials"
        } else {
            WriteLog "Test-VMrestEndpoint: No credentials provided (will accept 401 as success)"
        }

        $null = Invoke-RestMethod @params
        WriteLog "Test-VMrestEndpoint: HTTP request SUCCESS (200 OK)"
        return $true
    }
    catch {
        # PowerShell 7 throws HttpResponseException, PowerShell 5.1 throws WebException
        # Check for 401 in either case - that means vmrest IS running, just needs auth
        $exceptionType = $_.Exception.GetType().Name
        $exceptionMessage = $_.Exception.Message
        WriteLog "Test-VMrestEndpoint: Exception caught - $exceptionType : $exceptionMessage"

        # Check for 401 Unauthorized in the exception message (works for both PS5 and PS7)
        if ($exceptionMessage -match '401' -or $exceptionMessage -match 'Unauthorized') {
            WriteLog "Test-VMrestEndpoint: 401 Unauthorized detected - vmrest IS running (needs auth)"
            return $true
        }

        # For WebException (PS5.1), check the Response property
        if ($_.Exception -is [System.Net.WebException]) {
            $webException = $_.Exception
            if ($webException.Response) {
                $statusCode = [int]$webException.Response.StatusCode
                WriteLog "Test-VMrestEndpoint: WebException HTTP Status Code = $statusCode"
                if ($statusCode -eq 401) {
                    WriteLog "Test-VMrestEndpoint: 401 via WebException.Response - vmrest IS running"
                    return $true
                }
            }
        }

        # For HttpResponseException (PS7), the status code is in the message
        # Already checked above via message matching

        WriteLog "Test-VMrestEndpoint: Returning FALSE - not a 401 response"
        return $false
    }
}

<#
.SYNOPSIS
    Checks if vmrest credentials have been configured
#>
function Test-VMrestCredentialsConfigured {
    [CmdletBinding()]
    param(
        [string]$VMrestPath
    )

    # vmrest stores credentials in user profile
    # VMware 17.x uses 'vmrest.cfg' (no leading dot)
    # Older versions may use '.vmrestCfg' (with leading dot)
    $configPaths = @(
        (Join-Path $env:USERPROFILE 'vmrest.cfg'),      # VMware 17.x
        (Join-Path $env:USERPROFILE '.vmrestCfg')       # Legacy/older versions
    )

    foreach ($configPath in $configPaths) {
        if (Test-Path $configPath) {
            $content = Get-Content $configPath -Raw -ErrorAction SilentlyContinue
            # Check if credentials section exists
            if ($content -match 'username' -and $content -match 'password') {
                return $true
            }
        }
    }

    return $false
}

<#
.SYNOPSIS
    Stops the vmrest service if running
#>
function Stop-VMrestService {
    [CmdletBinding()]
    param()

    try {
        $processes = Get-Process -Name 'vmrest' -ErrorAction SilentlyContinue
        foreach ($proc in $processes) {
            WriteLog "Stopping vmrest (PID: $($proc.Id))..."
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        }
        return $true
    }
    catch {
        WriteLog "WARNING: Failed to stop vmrest: $($_.Exception.Message)"
        return $false
    }
}

<#
.SYNOPSIS
    Gets the status of vmrest service
#>
function Get-VMrestServiceStatus {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [int]$Port = 8697
    )

    $result = @{
        IsRunning = $false
        ProcessId = $null
        Port = $Port
        IsAccessible = $false
    }

    $process = Get-Process -Name 'vmrest' -ErrorAction SilentlyContinue
    if ($process) {
        $result.IsRunning = $true
        $result.ProcessId = $process.Id

        # Test if accessible
        $result.IsAccessible = Test-VMrestEndpoint -Port $Port
    }

    return $result
}

<#
.SYNOPSIS
    Generates a Basic authentication header from a PSCredential

.DESCRIPTION
    Creates a properly formatted Basic authentication header string for use
    with vmrest REST API calls. PowerShell's -Credential parameter doesn't
    work correctly with vmrest, so explicit Basic auth headers are required.

.PARAMETER Credential
    PSCredential object containing username and password.

.OUTPUTS
    [string] The formatted Basic auth header value (e.g., "Basic dXNlcjpwYXNz")

.EXAMPLE
    $cred = Get-Credential
    $header = Get-BasicAuthHeader -Credential $cred
    Invoke-RestMethod -Uri "http://localhost:8697/api/vms" -Headers @{ Authorization = $header }

.NOTES
    This function properly handles SecureString conversion and cleanup.
#>
function Get-BasicAuthHeader {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCredential]$Credential
    )

    $username = $Credential.UserName
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Credential.Password)
    try {
        $password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        $pair = "${username}:${password}"
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
        $base64 = [System.Convert]::ToBase64String($bytes)
        return "Basic $base64"
    }
    finally {
        # Cleanup sensitive data from memory
        if ($BSTR -ne [IntPtr]::Zero) {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        }
        $password = $null
    }
}
