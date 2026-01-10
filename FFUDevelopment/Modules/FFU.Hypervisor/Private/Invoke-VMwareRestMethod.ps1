<#
.SYNOPSIS
    Wrapper for VMware Workstation REST API calls

.DESCRIPTION
    Provides a consistent interface for making REST API calls to vmrest.
    Handles authentication, error handling, retries, and response parsing.

.PARAMETER Endpoint
    The API endpoint path (e.g., '/vms', '/vms/{id}/power')

.PARAMETER Method
    HTTP method (GET, POST, PUT, DELETE). Default is GET.

.PARAMETER Body
    Request body for POST/PUT operations. Will be converted to JSON.

.PARAMETER Port
    vmrest port. Default 8697.

.PARAMETER Credential
    PSCredential for vmrest authentication.

.PARAMETER RetryCount
    Number of retries on transient failures. Default 3.

.PARAMETER TimeoutSeconds
    Request timeout in seconds. Default 30.

.OUTPUTS
    The deserialized response from the API, or throws on error.

.EXAMPLE
    # Get all VMs
    $vms = Invoke-VMwareRestMethod -Endpoint '/vms'

.EXAMPLE
    # Power on a VM
    Invoke-VMwareRestMethod -Endpoint "/vms/$vmId/power" -Method PUT -Body @{command='on'}

.EXAMPLE
    # Create a VM from clone
    $body = @{
        name = 'NewVM'
        parentId = $sourceVmId
    }
    Invoke-VMwareRestMethod -Endpoint '/vms' -Method POST -Body $body

.NOTES
    Module: FFU.Hypervisor
    Version: 1.0.0

    VMware REST API Reference:
    https://docs.vmware.com/en/VMware-Workstation-Pro/17/com.vmware.ws.using.doc/GUID-9FAAA4DD-1320-450D-B684-2845B311640F.html
#>

function Invoke-VMwareRestMethod {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Endpoint,

        [Parameter(Mandatory = $false)]
        [ValidateSet('GET', 'POST', 'PUT', 'DELETE', 'PATCH')]
        [string]$Method = 'GET',

        [Parameter(Mandatory = $false)]
        [object]$Body,

        [Parameter(Mandatory = $false)]
        [int]$Port = 8697,

        [Parameter(Mandatory = $false)]
        [PSCredential]$Credential,

        [Parameter(Mandatory = $false)]
        [int]$RetryCount = 3,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 30
    )

    # Build the full URL - ensure proper slash handling
    $baseUrl = "http://127.0.0.1:$Port/api"
    $cleanEndpoint = $Endpoint.TrimStart('/').TrimEnd('/')
    $uri = "$baseUrl/$cleanEndpoint"

    # Build request parameters
    $params = @{
        Uri = $uri
        Method = $Method
        ContentType = 'application/vnd.vmware.vmw.rest-v1+json'
        TimeoutSec = $TimeoutSeconds
        ErrorAction = 'Stop'
    }

    # Add credential if provided - use explicit Basic auth header
    # PowerShell's -Credential parameter doesn't work correctly with vmrest
    if ($Credential) {
        $authHeader = Get-BasicAuthHeader -Credential $Credential
        $params['Headers'] = @{ Authorization = $authHeader }
    }

    # Add body for POST/PUT/PATCH
    if ($Body -and $Method -in @('POST', 'PUT', 'PATCH')) {
        if ($Body -is [string]) {
            $params['Body'] = $Body
        }
        else {
            $params['Body'] = $Body | ConvertTo-Json -Depth 10
        }
    }

    # Retry loop
    $lastError = $null
    $attempt = 0

    while ($attempt -lt $RetryCount) {
        $attempt++

        try {
            WriteLog "VMware API: $Method $uri (attempt $attempt/$RetryCount)"

            $response = Invoke-RestMethod @params

            # Log success
            if ($response) {
                WriteLog "VMware API: Success"
            }

            return $response
        }
        catch {
            # Handle both PowerShell 5.1 (WebException) and PowerShell 7 (HttpResponseException)
            $statusCode = $null
            $errorMessage = $_.Exception.Message

            # Try to extract status code from WebException (PS5.1)
            if ($_.Exception -is [System.Net.WebException] -and $_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode

                # Read error response body
                try {
                    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                    $errorBody = $reader.ReadToEnd()
                    $reader.Close()

                    if ($errorBody) {
                        $errorJson = $errorBody | ConvertFrom-Json -ErrorAction SilentlyContinue
                        if ($errorJson.message) {
                            $errorMessage = "$statusCode - $($errorJson.message)"
                        }
                        elseif ($errorJson.error) {
                            $errorMessage = "$statusCode - $($errorJson.error)"
                        }
                        else {
                            $errorMessage = "$statusCode - $errorBody"
                        }
                    }
                }
                catch {
                    # Ignore parse errors
                }
            }
            # Try to extract status code from HttpResponseException message (PS7)
            elseif ($errorMessage -match '(\d{3})') {
                $statusCode = [int]$Matches[1]
            }

            $lastError = $errorMessage
            WriteLog "VMware API: Error on attempt $attempt - $lastError (StatusCode: $statusCode)"

            # Don't retry on client errors (4xx) except 429 (rate limit)
            if ($statusCode -and $statusCode -ge 400 -and $statusCode -lt 500 -and $statusCode -ne 429) {
                WriteLog "VMware API: Client error $statusCode - not retrying"
                throw "VMware API error: $lastError"
            }

            if ($attempt -lt $RetryCount) {
                $delay = [Math]::Pow(2, $attempt)  # Exponential backoff
                WriteLog "Waiting $delay seconds before retry..."
                Start-Sleep -Seconds $delay
            }
        }
    }

    throw "VMware API call failed after $RetryCount attempts: $lastError"
}

<#
.SYNOPSIS
    Gets all VMs from VMware Workstation
#>
function Get-VMwareVMList {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [int]$Port = 8697,
        [PSCredential]$Credential
    )

    try {
        $response = Invoke-VMwareRestMethod -Endpoint '/vms' -Port $Port -Credential $Credential
        return $response
    }
    catch {
        WriteLog "WARNING: Failed to get VM list: $($_.Exception.Message)"
        return @()
    }
}

<#
.SYNOPSIS
    Gets a specific VM by ID
#>
function Get-VMwareVM {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMId,

        [int]$Port = 8697,
        [PSCredential]$Credential
    )

    try {
        $response = Invoke-VMwareRestMethod -Endpoint "/vms/$VMId" -Port $Port -Credential $Credential
        return $response
    }
    catch {
        WriteLog "WARNING: Failed to get VM $VMId : $($_.Exception.Message)"
        return $null
    }
}

<#
.SYNOPSIS
    Gets the power state of a VM
#>
function Get-VMwarePowerState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMId,

        [int]$Port = 8697,
        [PSCredential]$Credential
    )

    try {
        $response = Invoke-VMwareRestMethod -Endpoint "/vms/$VMId/power" -Port $Port -Credential $Credential
        return $response.power_state
    }
    catch {
        WriteLog "WARNING: Failed to get power state for VM $VMId : $($_.Exception.Message)"
        return 'unknown'
    }
}

<#
.SYNOPSIS
    Gets VM power state using vmrun.exe (no authentication required)

.DESCRIPTION
    Uses "vmrun list" command to check if a VM is running.
    If the VMX path appears in the list of running VMs, it's running; otherwise it's off.
    This method doesn't require REST API authentication.

.PARAMETER VMXPath
    Full path to the VM's .vmx file

.OUTPUTS
    String: 'poweredon', 'poweredoff', or 'unknown'
#>
function Get-VMwarePowerStateWithVmrun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMXPath
    )

    $vmrunPath = Get-VmrunPath
    if (-not $vmrunPath) {
        WriteLog "WARNING: vmrun.exe not found - cannot determine VM state"
        return 'unknown'
    }

    WriteLog "Using vmrun list to check power state for: $VMXPath"

    try {
        # vmrun -T ws list returns all running VMs, one path per line
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $vmrunPath
        $psi.Arguments = "-T ws list"
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true

        $process = [System.Diagnostics.Process]::Start($psi)
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()

        if ($process.ExitCode -ne 0) {
            WriteLog "WARNING: vmrun list failed with exit code $($process.ExitCode): $stderr"
            return 'unknown'
        }

        # Parse output - first line is "Total running VMs: N", rest are VMX paths
        $lines = $stdout -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }

        # Normalize path for comparison (case-insensitive, consistent slashes)
        $normalizedTarget = $VMXPath.ToLower().Replace('/', '\')

        foreach ($line in $lines) {
            if ($line -match '^Total running VMs:') {
                continue
            }
            # Each line is a full path to a running VM's VMX file
            $normalizedLine = $line.ToLower().Replace('/', '\')
            if ($normalizedLine -eq $normalizedTarget) {
                WriteLog "VM is RUNNING (found in vmrun list)"
                return 'poweredon'
            }
        }

        WriteLog "VM is OFF (not found in vmrun list)"
        return 'poweredoff'
    }
    catch {
        WriteLog "WARNING: Error checking VM state with vmrun: $($_.Exception.Message)"
        return 'unknown'
    }
}

<#
.SYNOPSIS
    Sets the power state of a VM using vmrun.exe

.DESCRIPTION
    Uses vmrun.exe command-line tool to control VM power state.
    This method doesn't require REST API authentication.
.PARAMETER ShowConsole
    When true and State is 'on', starts the VM with a visible console window (gui mode).
    When false (default), starts the VM in headless mode (nogui) for automation.
#>
function Set-VMwarePowerStateWithVmrun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMXPath,

        [Parameter(Mandatory = $true)]
        [ValidateSet('on', 'off', 'shutdown', 'suspend', 'pause', 'unpause', 'reset')]
        [string]$State,

        [Parameter(Mandatory = $false)]
        [bool]$ShowConsole = $false
    )

    $vmrunPath = Get-VmrunPath
    if (-not $vmrunPath) {
        throw "vmrun.exe not found. Please ensure VMware Workstation is properly installed."
    }

    # Map REST API state names to vmrun commands
    # vmrun syntax: vmrun -T ws <command> "vmx_path" [options]
    # For 'start': vmrun -T ws start "vmx_path" [gui|nogui]
    # For 'stop':  vmrun -T ws stop "vmx_path" [hard|soft]
    $vmrunCommand = switch ($State) {
        'on'       { 'start' }
        'off'      { 'stop' }
        'shutdown' { 'stop' }
        'suspend'  { 'suspend' }
        'pause'    { 'pause' }
        'unpause'  { 'unpause' }
        'reset'    { 'reset' }
        default    { throw "Unknown power state: $State" }
    }

    WriteLog "Using vmrun.exe to set power state '$State' (vmrun command: $vmrunCommand)"

    # Determine options that come AFTER the VMX path
    # nogui = headless (preferred for automation unless ShowConsole is requested)
    # gui = with window (when ShowConsole is true, or as fallback if nogui fails)
    # hard/soft = for stop command
    $tryNoGui = ($State -eq 'on' -and -not $ShowConsole)
    $postOptions = switch ($State) {
        'on'       {
            if ($ShowConsole) {
                WriteLog "VM console will be visible (gui mode requested)"
                ' gui'    # Start with visible console
            } else {
                ' nogui'  # Start headless for automation
            }
        }
        'off'      { ' hard' }   # Force power off
        'shutdown' { ' soft' }   # Graceful shutdown
        default    { '' }        # No extra options
    }
    # vmrun syntax: vmrun -T ws <command> "vmx_path" [options]
    $arguments = "-T ws $vmrunCommand `"$VMXPath`"$postOptions"
    WriteLog "Executing: vmrun $arguments"

    # Pre-flight checks
    WriteLog "Pre-flight checks for vmrun $($vmrunCommand):"
    WriteLog "  VMX Path: $VMXPath"
    WriteLog "  VMX Exists: $(Test-Path $VMXPath)"
    if (Test-Path $VMXPath) {
        $vmxContent = Get-Content $VMXPath -Raw -ErrorAction SilentlyContinue
        $vmxLines = ($vmxContent -split "`n").Count
        WriteLog "  VMX File Size: $((Get-Item $VMXPath).Length) bytes, $vmxLines lines"

        # Check for key VMX settings
        if ($vmxContent -match 'scsi0:0\.fileName\s*=\s*"([^"]+)"') {
            $diskPath = $matches[1]
            WriteLog "  Disk Path in VMX: $diskPath"
            # If it's a relative path, resolve it
            if (-not [System.IO.Path]::IsPathRooted($diskPath)) {
                $vmxDir = Split-Path $VMXPath -Parent
                $diskPath = Join-Path $vmxDir $diskPath
            }
            $diskExists = Test-Path $diskPath
            WriteLog "  Disk Exists: $diskExists"
            if ($diskExists) {
                $diskInfo = Get-Item $diskPath
                WriteLog "  Disk Size: $([math]::Round($diskInfo.Length/1MB, 2)) MB"
            }
        }
        if ($vmxContent -match 'sata0:0\.fileName\s*=\s*"([^"]+)"') {
            $isoPath = $matches[1]
            WriteLog "  ISO Path in VMX (SATA): $isoPath"
            WriteLog "  ISO Exists: $(Test-Path $isoPath)"
        }
        if ($vmxContent -match 'ide1:0\.fileName\s*=\s*"([^"]+)"') {
            $isoPath = $matches[1]
            WriteLog "  ISO Path in VMX (IDE): $isoPath"
            WriteLog "  ISO Exists: $(Test-Path $isoPath)"
        }

        # Check 3D acceleration (known to cause "operation was canceled" with nogui)
        if ($vmxContent -match 'mks\.enable3d\s*=\s*"([^"]+)"') {
            $enable3d = $matches[1]
            WriteLog "  3D Acceleration (mks.enable3d): $enable3d"
            if ($enable3d -eq 'TRUE' -and $State -eq 'on') {
                WriteLog "  WARNING: 3D acceleration may cause 'operation was canceled' error with nogui mode"
            }
        } else {
            WriteLog "  3D Acceleration: Not configured (will use VMware default)"
        }

        # Check for fullscreen settings that can cause issues
        if ($vmxContent -match 'gui\.lastPoweredViewMode\s*=\s*"fullscreen"') {
            WriteLog "  WARNING: gui.lastPoweredViewMode=fullscreen may cause issues with nogui mode"
        }
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $vmrunPath
    $psi.Arguments = $arguments
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $process = [System.Diagnostics.Process]::Start($psi)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    # Always log output for diagnostics
    if ($stdout) {
        WriteLog "vmrun stdout: $($stdout.Trim())"
    }
    if ($stderr) {
        WriteLog "vmrun stderr: $($stderr.Trim())"
    }
    WriteLog "vmrun exit code: $($process.ExitCode)"

    if ($process.ExitCode -ne 0) {
        $errorOutput = if ($stdout) { $stdout.Trim() } else { $stderr.Trim() }

        # Check if this is the "operation was canceled" error with nogui mode
        # This often happens with vTPM/encrypted VMs - retry with gui mode
        if ($tryNoGui -and ($errorOutput -match 'operation was canceled' -or $process.ExitCode -eq -1)) {
            WriteLog "WARNING: vmrun nogui failed with 'operation was canceled' - this may be due to vTPM/encryption"
            WriteLog "Retrying vmrun start WITH gui (VM window will appear)..."

            # Retry with 'gui' option instead of 'nogui' - option comes AFTER vmx path
            $guiArguments = "-T ws $vmrunCommand `"$VMXPath`" gui"
            WriteLog "Executing: vmrun $guiArguments"

            $psi2 = New-Object System.Diagnostics.ProcessStartInfo
            $psi2.FileName = $vmrunPath
            $psi2.Arguments = $guiArguments
            $psi2.UseShellExecute = $false
            $psi2.RedirectStandardOutput = $true
            $psi2.RedirectStandardError = $true
            $psi2.CreateNoWindow = $true

            $process2 = [System.Diagnostics.Process]::Start($psi2)
            $stdout2 = $process2.StandardOutput.ReadToEnd()
            $stderr2 = $process2.StandardError.ReadToEnd()
            $process2.WaitForExit()

            if ($stdout2) { WriteLog "vmrun (gui) stdout: $($stdout2.Trim())" }
            if ($stderr2) { WriteLog "vmrun (gui) stderr: $($stderr2.Trim())" }
            WriteLog "vmrun (gui) exit code: $($process2.ExitCode)"

            if ($process2.ExitCode -eq 0) {
                WriteLog "vmrun $vmrunCommand completed successfully (with gui mode)"
                return @{ power_state = $State }
            }

            # Both attempts failed
            $errorDetails = @()
            $errorDetails += "Exit code (nogui): $($process.ExitCode)"
            $errorDetails += "Exit code (gui): $($process2.ExitCode)"
            if ($stdout2) { $errorDetails += "stdout (gui): $($stdout2.Trim())" }
            if ($stderr2) { $errorDetails += "stderr (gui): $($stderr2.Trim())" }
            $errorMsg = $errorDetails -join '; '
            throw "vmrun $vmrunCommand failed (both nogui and gui modes): $errorMsg"
        }

        # Standard error (not the nogui-specific issue)
        $errorDetails = @()
        $errorDetails += "Exit code: $($process.ExitCode)"
        if ($stderr) { $errorDetails += "stderr: $($stderr.Trim())" }
        if ($stdout) { $errorDetails += "stdout: $($stdout.Trim())" }
        $errorMsg = $errorDetails -join '; '
        throw "vmrun $vmrunCommand failed: $errorMsg"
    }

    WriteLog "vmrun $vmrunCommand completed successfully"
    return @{ power_state = $State }
}

<#
.SYNOPSIS
    Sets the power state of a VM

.DESCRIPTION
    Tries REST API first, falls back to vmrun.exe if authentication fails (401).
    vmrun.exe doesn't require API credentials and works for local operations.

.PARAMETER ShowConsole
    When true and State is 'on', starts the VM with a visible console window (gui mode).
    When false (default), starts the VM in headless mode (nogui) for automation.
#>
function Set-VMwarePowerState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMId,

        [Parameter(Mandatory = $true)]
        [ValidateSet('on', 'off', 'shutdown', 'suspend', 'pause', 'unpause', 'reset')]
        [string]$State,

        [Parameter(Mandatory = $false)]
        [string]$VMXPath,

        [int]$Port = 8697,
        [PSCredential]$Credential,

        [Parameter(Mandatory = $false)]
        [bool]$ShowConsole = $false
    )

    # Try REST API first if credentials are provided
    if ($Credential) {
        try {
            $body = $State  # VMware REST API expects just the command string
            $response = Invoke-VMwareRestMethod -Endpoint "/vms/$VMId/power" -Method PUT -Body $body -Port $Port -Credential $Credential
            WriteLog "Set power state '$State' via REST API for VM $VMId"
            # Note: REST API doesn't support gui/nogui mode - it always shows the console
            if ($State -eq 'on' -and -not $ShowConsole) {
                WriteLog "Note: REST API doesn't support nogui mode - VM console will be visible"
            }
            return $response
        }
        catch {
            if ($_.Exception.Message -match '401|Unauthorized') {
                WriteLog "WARNING: REST API authentication failed. Falling back to vmrun.exe..."
            }
            else {
                WriteLog "ERROR: REST API power control failed: $($_.Exception.Message)"
                WriteLog "Attempting vmrun.exe fallback..."
            }
        }
    }
    else {
        WriteLog "No REST API credentials provided. Using vmrun.exe for power control."
    }

    # Fall back to vmrun.exe - requires VMXPath
    if ([string]::IsNullOrEmpty($VMXPath)) {
        throw "Cannot use vmrun.exe fallback without VMXPath. Please provide VMXPath parameter or configure REST API credentials."
    }

    try {
        return Set-VMwarePowerStateWithVmrun -VMXPath $VMXPath -State $State -ShowConsole $ShowConsole
    }
    catch {
        WriteLog "ERROR: Failed to set power state with vmrun.exe: $($_.Exception.Message)"
        throw "Failed to set power state. Both REST API and vmrun.exe methods failed. Last error: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Gets the IP address of a VM
#>
function Get-VMwareVMIPAddress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMId,

        [int]$Port = 8697,
        [PSCredential]$Credential,

        [int]$TimeoutSeconds = 120,
        [int]$PollIntervalSeconds = 5
    )

    $startTime = Get-Date

    while (((Get-Date) - $startTime).TotalSeconds -lt $TimeoutSeconds) {
        try {
            $response = Invoke-VMwareRestMethod -Endpoint "/vms/$VMId/ip" -Port $Port -Credential $Credential
            if ($response.ip) {
                return $response.ip
            }
        }
        catch {
            # IP might not be available yet
        }

        Start-Sleep -Seconds $PollIntervalSeconds
    }

    WriteLog "WARNING: Could not get IP address for VM $VMId within $TimeoutSeconds seconds"
    return $null
}

<#
.SYNOPSIS
    Gets the path to vmrun.exe

.DESCRIPTION
    Locates vmrun.exe in the VMware Workstation installation directory.
    vmrun is a command-line utility that doesn't require REST API authentication.
#>
function Get-VmrunPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # Try registry first
    $regPaths = @(
        'HKLM:\SOFTWARE\VMware, Inc.\VMware Workstation',
        'HKLM:\SOFTWARE\WOW6432Node\VMware, Inc.\VMware Workstation'
    )

    foreach ($regPath in $regPaths) {
        if (Test-Path $regPath) {
            $installPath = (Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue).InstallPath
            if ($installPath) {
                $vmrunPath = Join-Path $installPath 'vmrun.exe'
                if (Test-Path $vmrunPath) {
                    return $vmrunPath
                }
            }
        }
    }

    # Try default paths
    $defaultPaths = @(
        'C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe',
        'C:\Program Files\VMware\VMware Workstation\vmrun.exe'
    )

    foreach ($path in $defaultPaths) {
        if (Test-Path $path) {
            return $path
        }
    }

    return $null
}

<#
.SYNOPSIS
    Registers a VM with VMware Workstation using vmrun.exe

.DESCRIPTION
    Uses vmrun.exe command-line tool to register a VM.
    This method doesn't require REST API authentication.
#>
function Register-VMwareVMWithVmrun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMXPath
    )

    $vmrunPath = Get-VmrunPath
    if (-not $vmrunPath) {
        throw "vmrun.exe not found. Please ensure VMware Workstation is properly installed."
    }

    WriteLog "vmrun.exe path: $vmrunPath"

    # Verify VMX file exists
    if (-not (Test-Path $VMXPath)) {
        throw "VMX file not found: $VMXPath"
    }
    WriteLog "VMX file exists: $VMXPath"

    # Check if VMware Workstation UI is running (may be required for some operations)
    $vmwareProcess = Get-Process -Name 'vmware' -ErrorAction SilentlyContinue
    if ($vmwareProcess) {
        WriteLog "VMware Workstation UI is running (PID: $($vmwareProcess.Id))"
    }
    else {
        WriteLog "WARNING: VMware Workstation UI is not running. Some vmrun operations may require it."
    }

    # Try registering with vmrun
    # Note: vmrun register may fail if:
    # 1. The VM is already registered
    # 2. VMware Workstation UI needs to be running
    # 3. The VMX file is invalid or from an incompatible version

    $arguments = "-T ws register `"$VMXPath`""
    WriteLog "Executing: vmrun $arguments"

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $vmrunPath
    $psi.Arguments = $arguments
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $process = [System.Diagnostics.Process]::Start($psi)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    $exitCode = $process.ExitCode

    # Log all output for debugging
    WriteLog "vmrun exit code: $exitCode"
    if ($stdout) {
        WriteLog "vmrun stdout: $stdout"
    }
    if ($stderr) {
        WriteLog "vmrun stderr: $stderr"
    }

    if ($exitCode -ne 0) {
        # Provide detailed error message
        $errorDetails = @()
        $errorDetails += "Exit code: $exitCode"
        if ($stderr) {
            $errorDetails += "Stderr: $stderr"
        }
        if ($stdout) {
            $errorDetails += "Stdout: $stdout"
        }

        # Common exit code meanings for vmrun
        $exitCodeMeaning = switch ($exitCode) {
            -1 { "General error - VMware services may not be running or VMX file invalid" }
            1 { "Command failed - check VMX file path and VMware installation" }
            2 { "VM is already running or operation not allowed in current state" }
            default { "Unknown error" }
        }
        $errorDetails += "Possible cause: $exitCodeMeaning"

        # Check if vmrun works at all by listing VMs
        WriteLog "Testing vmrun by listing running VMs..."
        $listArgs = "-T ws list"
        $psi2 = New-Object System.Diagnostics.ProcessStartInfo
        $psi2.FileName = $vmrunPath
        $psi2.Arguments = $listArgs
        $psi2.UseShellExecute = $false
        $psi2.RedirectStandardOutput = $true
        $psi2.RedirectStandardError = $true
        $psi2.CreateNoWindow = $true

        $proc2 = [System.Diagnostics.Process]::Start($psi2)
        $listOut = $proc2.StandardOutput.ReadToEnd()
        $listErr = $proc2.StandardError.ReadToEnd()
        $proc2.WaitForExit()

        WriteLog "vmrun list exit code: $($proc2.ExitCode)"
        if ($listOut) {
            WriteLog "vmrun list output: $listOut"
        }
        if ($listErr) {
            WriteLog "vmrun list stderr: $listErr"
        }

        throw "vmrun register failed: $($errorDetails -join '; ')"
    }

    WriteLog "vmrun register completed successfully"

    # Return a result object similar to REST API
    $vmName = [System.IO.Path]::GetFileNameWithoutExtension($VMXPath)
    return @{
        id = $vmName  # vmrun doesn't return an ID, use VM name
        path = $VMXPath
        name = $vmName
    }
}

<#
.SYNOPSIS
    Registers a VM with VMware Workstation

.DESCRIPTION
    Tries REST API first, falls back to vmrun.exe if authentication fails (401).
    vmrun.exe doesn't require API credentials and works for local operations.
#>
function Register-VMwareVM {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMXPath,

        [string]$VMName,

        [int]$Port = 8697,
        [PSCredential]$Credential
    )

    $resolvedName = if ($VMName) { $VMName } else { [System.IO.Path]::GetFileNameWithoutExtension($VMXPath) }

    # Try REST API first if credentials are provided
    if ($Credential) {
        try {
            $body = @{
                name = $resolvedName
                path = $VMXPath
            }

            $response = Invoke-VMwareRestMethod -Endpoint '/vms/registration' -Method POST -Body $body -Port $Port -Credential $Credential
            WriteLog "Registered VM via REST API: $resolvedName"
            return $response
        }
        catch {
            # Check if it's an auth error - fall back to vmrun
            if ($_.Exception.Message -match '401|Unauthorized') {
                WriteLog "WARNING: REST API authentication failed. Falling back to vmrun.exe..."
            }
            else {
                WriteLog "ERROR: REST API registration failed: $($_.Exception.Message)"
                WriteLog "Attempting vmrun.exe fallback..."
            }
        }
    }
    else {
        WriteLog "No REST API credentials provided. Using vmrun.exe for VM registration."
    }

    # Fall back to vmrun.exe
    try {
        return Register-VMwareVMWithVmrun -VMXPath $VMXPath
    }
    catch {
        WriteLog "ERROR: Failed to register VM with vmrun.exe: $($_.Exception.Message)"
        throw "Failed to register VM. Both REST API and vmrun.exe methods failed. Last error: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Unregisters (removes) a VM from VMware Workstation
#>
function Unregister-VMwareVM {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMId,

        [int]$Port = 8697,
        [PSCredential]$Credential
    )

    try {
        $response = Invoke-VMwareRestMethod -Endpoint "/vms/$VMId" -Method DELETE -Port $Port -Credential $Credential
        WriteLog "Unregistered VM: $VMId"
        return $response
    }
    catch {
        WriteLog "ERROR: Failed to unregister VM $VMId : $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    Updates VM settings (CPU, memory, etc.)
#>
function Set-VMwareVMSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMId,

        [int]$Processors,
        [int]$MemoryMB,

        [int]$Port = 8697,
        [PSCredential]$Credential
    )

    try {
        $body = @{}

        if ($Processors -gt 0) {
            $body['processors'] = $Processors
        }

        if ($MemoryMB -gt 0) {
            $body['memory'] = $MemoryMB
        }

        if ($body.Count -eq 0) {
            WriteLog "No settings to update"
            return
        }

        $response = Invoke-VMwareRestMethod -Endpoint "/vms/$VMId" -Method PUT -Body $body -Port $Port -Credential $Credential
        WriteLog "Updated VM settings: $VMId"
        return $response
    }
    catch {
        WriteLog "ERROR: Failed to update VM settings: $($_.Exception.Message)"
        throw
    }
}
