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
#>
function Test-VMrestEndpoint {
    [CmdletBinding()]
    param(
        [int]$Port = 8697,
        [PSCredential]$Credential
    )

    try {
        $uri = "http://127.0.0.1:$Port/api/vms"

        $params = @{
            Uri = $uri
            Method = 'GET'
            TimeoutSec = 5
            ErrorAction = 'Stop'
        }

        if ($Credential) {
            $params['Credential'] = $Credential
        }

        $null = Invoke-RestMethod @params
        return $true
    }
    catch {
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

    # vmrest stores credentials in ~/.vmrestCfg on Windows
    $configPath = Join-Path $env:USERPROFILE '.vmrestCfg'

    if (Test-Path $configPath) {
        $content = Get-Content $configPath -Raw -ErrorAction SilentlyContinue
        # Check if credentials section exists
        return ($content -match 'username' -and $content -match 'password')
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
