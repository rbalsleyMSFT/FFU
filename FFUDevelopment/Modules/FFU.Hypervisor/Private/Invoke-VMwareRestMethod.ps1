<#
.SYNOPSIS
    VMware vmrun.exe helper functions

.DESCRIPTION
    Provides PowerShell wrappers for VMware Workstation vmrun.exe command-line tool.
    These functions do not require REST API authentication - they work directly with
    the VMware Workstation installation.

.NOTES
    Module: FFU.Hypervisor
    Version: 1.2.0
    Replaces REST API with direct vmrun.exe control
#>

<#
.SYNOPSIS
    Gets the path to vmrun.exe

.DESCRIPTION
    Locates vmrun.exe in the VMware Workstation installation directory.
    Checks registry first, then falls back to default installation paths.

.OUTPUTS
    String path to vmrun.exe, or $null if not found
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
    Detects if a VMware VM is running by checking for vmware-vmx.exe process

.DESCRIPTION
    Checks for vmware-vmx.exe processes and matches by VMX path in command line.
    This is the most reliable detection method as it:
    - Is independent of vmrun.exe (which can be broken on some systems)
    - Is independent of user session context
    - Works immediately after VM start (no timing issues)

.PARAMETER VMXPath
    Full path to the VM's .vmx file

.OUTPUTS
    Hashtable with:
    - Running: $true if VM process found, $false otherwise
    - ProcessId: PID of the vmware-vmx process (if found)
    - CommandLine: Full command line of the process (if found)

.EXAMPLE
    $result = Test-VMwareVMXProcess -VMXPath "C:\VMs\MyVM\MyVM.vmx"
    if ($result.Running) { Write-Host "VM is running with PID $($result.ProcessId)" }
#>
function Test-VMwareVMXProcess {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMXPath
    )

    $result = @{
        Running = $false
        ProcessId = $null
        CommandLine = $null
    }

    try {
        # Use CIM to get process details including command line
        $vmxProcesses = Get-CimInstance Win32_Process -Filter "Name = 'vmware-vmx.exe'" -ErrorAction SilentlyContinue

        if (-not $vmxProcesses) {
            WriteLog "No vmware-vmx.exe processes found"
            return $result
        }

        # Normalize our target path for comparison
        $normalizedTarget = $VMXPath.ToLower().Replace('/', '\').TrimEnd('\')

        foreach ($proc in $vmxProcesses) {
            if ($proc.CommandLine) {
                # VMware command line contains the VMX path
                $cmdLineLower = $proc.CommandLine.ToLower()

                # Check if our VMX path appears in the command line
                if ($cmdLineLower -like "*$normalizedTarget*") {
                    $result.Running = $true
                    $result.ProcessId = $proc.ProcessId
                    $result.CommandLine = $proc.CommandLine
                    WriteLog "vmware-vmx process found for VM (PID: $($proc.ProcessId))"
                    return $result
                }
            }
        }

        WriteLog "vmware-vmx processes exist ($($vmxProcesses.Count)) but none match our VMX path"
    }
    catch {
        WriteLog "WARNING: Error checking vmware-vmx processes: $($_.Exception.Message)"
    }

    return $result
}

<#
.SYNOPSIS
    Waits for a VMware VM to start by polling for vmware-vmx process

.DESCRIPTION
    Polls for the vmware-vmx.exe process after vmrun start command.
    This verifies the VM actually started, not just that vmrun returned success.

    IMPORTANT: In GUI mode (ShowConsole=true), vmrun blocks until the VM shuts down.
    When vmrun returns with exit code 0 but no process is found, this means the VM
    started, ran to completion, and shut down - NOT that startup failed.

.PARAMETER VMXPath
    Full path to the VM's .vmx file

.PARAMETER TimeoutSeconds
    Maximum time to wait for VM to start (default 10 seconds)
    Note: In GUI mode, vmrun blocks so this timeout only applies to nogui mode.

.PARAMETER GUIMode
    When true, indicates vmrun was called with 'gui' option which blocks until VM shuts down.
    If GUIMode is true and no process is found, returns Status='Completed' (VM ran and finished).

.OUTPUTS
    Hashtable with:
    - Started: $true if VM process found OR if VM completed (GUI mode), $false if timeout
    - Status: 'Running' if VM is currently running, 'Completed' if VM ran and shut down (GUI mode only)
    - ProcessId: PID of the vmware-vmx process (if found)
    - ElapsedSeconds: Time spent waiting

.EXAMPLE
    $result = Wait-VMwareVMStart -VMXPath "C:\VMs\MyVM\MyVM.vmx" -TimeoutSeconds 60
    if ($result.Started) { Write-Host "VM started in $($result.ElapsedSeconds) seconds" }

.EXAMPLE
    # GUI mode - vmrun already blocked and returned
    $result = Wait-VMwareVMStart -VMXPath "C:\VMs\MyVM\MyVM.vmx" -GUIMode $true
    if ($result.Status -eq 'Completed') { Write-Host "VM ran and completed during vmrun wait" }
#>
function Wait-VMwareVMStart {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMXPath,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 60,

        [Parameter(Mandatory = $false)]
        [bool]$GUIMode = $false
    )

    $result = @{
        Started = $false
        Status = $null
        ProcessId = $null
        ElapsedSeconds = 0
    }

    # =========================================================================
    # GUI Mode: vmrun blocks until VM shuts down
    # When vmrun returns with exit code 0, the VM already ran and finished
    # =========================================================================
    if ($GUIMode) {
        WriteLog "GUI mode detected - vmrun blocks until VM shuts down"
        WriteLog "Checking if VM is still running or has completed..."

        $processCheck = Test-VMwareVMXProcess -VMXPath $VMXPath
        if ($processCheck.Running) {
            # VM is still running (rare - would only happen if vmrun returned early)
            WriteLog "VM is still running (PID: $($processCheck.ProcessId))"
            $result.Started = $true
            $result.Status = 'Running'
            $result.ProcessId = $processCheck.ProcessId
            return $result
        }
        else {
            # No process found after vmrun gui returned with exit code 0
            # This is the EXPECTED case: VM started, ran, and shut down
            WriteLog "No VM process found after vmrun gui returned - VM COMPLETED (not failed)"
            WriteLog "VM successfully started, ran to completion, and shut down during vmrun wait"
            $result.Started = $true
            $result.Status = 'Completed'
            return $result
        }
    }

    # =========================================================================
    # nogui Mode: vmrun returns immediately, need to poll for VM process
    # =========================================================================
    $startTime = Get-Date
    $pollInterval = 500  # milliseconds

    WriteLog "nogui mode - Waiting up to $TimeoutSeconds seconds for VM process to appear..."

    while (((Get-Date) - $startTime).TotalSeconds -lt $TimeoutSeconds) {
        $processCheck = Test-VMwareVMXProcess -VMXPath $VMXPath
        if ($processCheck.Running) {
            $result.Started = $true
            $result.Status = 'Running'
            $result.ProcessId = $processCheck.ProcessId
            $result.ElapsedSeconds = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 2)
            WriteLog "VM process detected (PID: $($processCheck.ProcessId)) after $($result.ElapsedSeconds) seconds"
            return $result
        }

        Start-Sleep -Milliseconds $pollInterval
    }

    $result.ElapsedSeconds = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 2)
    WriteLog "WARNING: VM process not found after $($result.ElapsedSeconds) seconds"
    return $result
}

<#
.SYNOPSIS
    Gets VM power state using multiple detection methods

.DESCRIPTION
    Uses multiple detection methods to determine VM state (in priority order):
    1. vmware-vmx process detection (PRIMARY - most reliable, context-independent)
    2. vmrun list (fallback - may be broken on some VMware 25.0.0 systems)
    3. nvram file lock (last resort - if nvram exists)

    Process detection is the most reliable as it doesn't depend on vmrun working.

    Note: .lck folder detection was removed in v1.2.3 because these folders
    persist after VM shutdown, causing false "running" detections.

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

    WriteLog "Checking VM power state for: $VMXPath"

    try {
        $vmFolder = [System.IO.Path]::GetDirectoryName($VMXPath)
        $vmName = [System.IO.Path]::GetFileNameWithoutExtension($VMXPath)

        # =======================================================================
        # Method 1: vmware-vmx Process Detection (PRIMARY - most reliable)
        # This method is independent of vmrun.exe which can be broken on some systems
        # =======================================================================
        WriteLog "Method 1: Checking vmware-vmx process..."
        $processCheck = Test-VMwareVMXProcess -VMXPath $VMXPath
        if ($processCheck.Running) {
            WriteLog "VM is RUNNING (vmware-vmx process detected, PID: $($processCheck.ProcessId))"
            return 'poweredon'
        }
        WriteLog "  No vmware-vmx process found for this VM"

        # =======================================================================
        # Method 2: vmrun list (fallback - may be broken on some VMware 25.0.0 systems)
        # =======================================================================
        $vmrunPath = Get-VmrunPath
        if ($vmrunPath) {
            WriteLog "Method 2: Checking vmrun list (may be unreliable on some systems)..."

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

            if ($process.ExitCode -eq 0) {
                $lines = $stdout -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
                WriteLog "  vmrun list output: $($lines[0])"  # Just log the count line

                $normalizedTarget = $VMXPath.ToLower().Replace('/', '\')
                foreach ($line in $lines) {
                    if ($line -match '^Total running VMs:') { continue }
                    $normalizedLine = $line.ToLower().Replace('/', '\')
                    if ($normalizedLine -eq $normalizedTarget) {
                        WriteLog "VM is RUNNING (found in vmrun list)"
                        return 'poweredon'
                    }
                }
                WriteLog "  VM not found in vmrun list"
            }
            else {
                WriteLog "  vmrun list failed (exit code $($process.ExitCode)) - skipping this method"
            }
        }
        else {
            WriteLog "Method 2: Skipped (vmrun.exe not found)"
        }

        # =======================================================================
        # Method 3: nvram file lock (if nvram exists - may not exist in VMware 25+)
        # =======================================================================
        $nvramPath = Join-Path $vmFolder "$vmName.nvram"
        if (Test-Path $nvramPath) {
            WriteLog "Method 3: Checking nvram file lock: $nvramPath"
            try {
                # Try to open the file exclusively - if we can, VM is definitely OFF
                $fs = [System.IO.File]::Open($nvramPath, 'Open', 'Read', 'None')
                $fs.Close()
                WriteLog "nvram file is NOT locked - VM is OFF (file accessible)"
                return 'poweredoff'
            }
            catch {
                if ($_.Exception.InnerException -is [System.IO.IOException] -or
                    $_.Exception.Message -match 'being used by another process') {
                    WriteLog "VM is RUNNING based on locked nvram file"
                    return 'poweredon'
                }
                # Other error - continue to next check
                WriteLog "nvram file check inconclusive: $($_.Exception.Message)"
            }
        }
        else {
            WriteLog "Method 3: Skipped (nvram file does not exist - normal for VMware 25.0.0+)"
        }

        # All methods exhausted - VM is OFF
        WriteLog "VM is OFF (all 3 detection methods indicate VM is not running)"
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

.PARAMETER VMXPath
    Full path to the VM's .vmx file

.PARAMETER State
    Power state to set: on, off, shutdown, suspend, pause, unpause, reset

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
                WriteLog "vmrun $vmrunCommand returned success (gui mode) - verifying VM started..."

                # Verify VM actually started using process detection
                # Note: GUI mode was used here, so vmrun may have blocked until VM shut down
                if ($State -eq 'on') {
                    $verifyResult = Wait-VMwareVMStart -VMXPath $VMXPath -TimeoutSeconds 10 -GUIMode $true
                    if (-not $verifyResult.Started) {
                        throw "vmrun start returned success but VM process not found after 10 seconds"
                    }

                    if ($verifyResult.Status -eq 'Completed') {
                        WriteLog "VM COMPLETED - VM started, ran, and shut down during vmrun gui wait"
                        return @{
                            power_state = $State
                            Status = 'Completed'
                            Message = 'VM ran to completion during vmrun gui blocking wait (fallback mode)'
                        }
                    }
                    else {
                        WriteLog "VM startup VERIFIED (PID: $($verifyResult.ProcessId))"
                    }
                }

                return @{ power_state = $State; Status = 'Running' }
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

    WriteLog "vmrun $vmrunCommand returned success - verifying VM started..."

    # Verify VM actually started using process detection
    if ($State -eq 'on') {
        # Pass GUI mode flag - in GUI mode, vmrun blocks until VM shuts down
        # so no process found means VM completed (not failed)
        $verifyResult = Wait-VMwareVMStart -VMXPath $VMXPath -TimeoutSeconds 10 -GUIMode $ShowConsole
        if (-not $verifyResult.Started) {
            throw "vmrun start returned success but VM process not found after 10 seconds"
        }

        if ($verifyResult.Status -eq 'Completed') {
            WriteLog "VM COMPLETED - VM started, ran, and shut down during vmrun gui wait"
            return @{
                power_state = $State
                Status = 'Completed'
                Message = 'VM ran to completion during vmrun gui blocking wait'
            }
        }
        else {
            WriteLog "VM startup VERIFIED - VM is running (PID: $($verifyResult.ProcessId))"
            return @{
                power_state = $State
                Status = 'Running'
                ProcessId = $verifyResult.ProcessId
            }
        }
    }

    return @{ power_state = $State; Status = 'Running' }
}
