<#
.SYNOPSIS
    Diagnostic script to test VMware VM startup and state detection

.DESCRIPTION
    Tests vmrun start command and verifies VM is running using multiple detection methods:
    1. vmware-vmx.exe process detection (most reliable)
    2. vmx.lck folder detection
    3. vmrun list command (may be broken on some systems)

    Use this script to diagnose why VM state detection may be failing.

.PARAMETER VMXPath
    Full path to the VM's .vmx file to test

.PARAMETER StartVM
    If specified, attempts to start the VM before testing detection

.PARAMETER StopVM
    If specified, stops the VM after testing

.EXAMPLE
    .\Test-VMwareStartup.ps1 -VMXPath "C:\VMs\MyVM\MyVM.vmx"
    # Tests detection on an already-running VM

.EXAMPLE
    .\Test-VMwareStartup.ps1 -VMXPath "C:\VMs\MyVM\MyVM.vmx" -StartVM
    # Starts the VM and tests detection

.EXAMPLE
    .\Test-VMwareStartup.ps1 -VMXPath "C:\VMs\MyVM\MyVM.vmx" -StartVM -StopVM
    # Full cycle: start, test, stop
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$VMXPath,

    [Parameter(Mandatory = $false)]
    [switch]$StartVM,

    [Parameter(Mandatory = $false)]
    [switch]$StopVM
)

$ErrorActionPreference = 'Continue'
$timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$logFile = Join-Path $PSScriptRoot "vmware-startup-$timestamp.log"

function Write-DiagLog {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] [$Level] $Message"
    Write-Host $line -ForegroundColor $(switch ($Level) {
        'ERROR' { 'Red' }
        'WARN'  { 'Yellow' }
        'SUCCESS' { 'Green' }
        'SECTION' { 'Cyan' }
        default { 'White' }
    })
    Add-Content -Path $logFile -Value $line
}

# =============================================================================
# HEADER
# =============================================================================

Write-DiagLog "=== VMware VM Startup Diagnostic ===" 'SECTION'
Write-DiagLog "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-DiagLog "Log File: $logFile"
Write-DiagLog ""

# =============================================================================
# 1. USER CONTEXT INFORMATION
# =============================================================================

Write-DiagLog "=== 1. User Context ===" 'SECTION'
Write-DiagLog "Current User: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-DiagLog "Process: $([System.Diagnostics.Process]::GetCurrentProcess().ProcessName) (PID: $PID)"
Write-DiagLog "Session ID: $([System.Diagnostics.Process]::GetCurrentProcess().SessionId)"
Write-DiagLog "Is Admin: $([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)"
Write-DiagLog "PowerShell Version: $($PSVersionTable.PSVersion)"
Write-DiagLog "Working Directory: $(Get-Location)"
Write-DiagLog ""

# =============================================================================
# 2. VMWARE INSTALLATION
# =============================================================================

Write-DiagLog "=== 2. VMware Installation ===" 'SECTION'

$vmwarePaths = @(
    'C:\Program Files (x86)\VMware\VMware Workstation',
    'C:\Program Files\VMware\VMware Workstation'
)

$vmwareInstallPath = $null
foreach ($path in $vmwarePaths) {
    if (Test-Path $path) {
        $vmwareInstallPath = $path
        break
    }
}

# Try registry
if (-not $vmwareInstallPath) {
    $regPaths = @(
        'HKLM:\SOFTWARE\VMware, Inc.\VMware Workstation',
        'HKLM:\SOFTWARE\WOW6432Node\VMware, Inc.\VMware Workstation'
    )
    foreach ($regPath in $regPaths) {
        if (Test-Path $regPath) {
            $vmwareInstallPath = (Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue).InstallPath
            if ($vmwareInstallPath) { break }
        }
    }
}

if ($vmwareInstallPath) {
    Write-DiagLog "Install Path: $vmwareInstallPath"

    $vmwareExe = Join-Path $vmwareInstallPath 'vmware.exe'
    $vmrunExe = Join-Path $vmwareInstallPath 'vmrun.exe'

    if (Test-Path $vmwareExe) {
        $version = (Get-Item $vmwareExe).VersionInfo
        Write-DiagLog "VMware Version: $($version.ProductVersion)"
    }

    if (Test-Path $vmrunExe) {
        Write-DiagLog "vmrun.exe: Found at $vmrunExe"
    } else {
        Write-DiagLog "vmrun.exe: NOT FOUND!" 'ERROR'
        exit 1
    }
} else {
    Write-DiagLog "VMware Workstation: NOT INSTALLED!" 'ERROR'
    exit 1
}

Write-DiagLog ""

# =============================================================================
# 3. VMX FILE VALIDATION
# =============================================================================

Write-DiagLog "=== 3. VMX File Validation ===" 'SECTION'
Write-DiagLog "VMX Path: $VMXPath"
Write-DiagLog "VMX Exists: $(Test-Path $VMXPath)"

if (-not (Test-Path $VMXPath)) {
    Write-DiagLog "VMX file does not exist!" 'ERROR'
    exit 1
}

$vmFolder = Split-Path $VMXPath -Parent
$vmName = [System.IO.Path]::GetFileNameWithoutExtension($VMXPath)
Write-DiagLog "VM Folder: $vmFolder"
Write-DiagLog "VM Name: $vmName"
Write-DiagLog ""

# =============================================================================
# 4. PRE-START STATE
# =============================================================================

Write-DiagLog "=== 4. Pre-Start State ===" 'SECTION'

# Check vmware-vmx processes
function Test-VMwareVMXProcess {
    param([string]$VMXPath)

    $result = @{
        Running = $false
        ProcessId = $null
        CommandLine = $null
        AllProcesses = @()
    }

    try {
        $vmxProcesses = Get-CimInstance Win32_Process -Filter "Name = 'vmware-vmx.exe'" -ErrorAction SilentlyContinue

        foreach ($proc in $vmxProcesses) {
            $result.AllProcesses += @{
                ProcessId = $proc.ProcessId
                CommandLine = $proc.CommandLine
            }

            # Check if this process is for our VM
            if ($proc.CommandLine -and $proc.CommandLine -like "*$VMXPath*") {
                $result.Running = $true
                $result.ProcessId = $proc.ProcessId
                $result.CommandLine = $proc.CommandLine
            }
        }
    }
    catch {
        Write-DiagLog "Error checking vmware-vmx processes: $($_.Exception.Message)" 'WARN'
    }

    return $result
}

$preStartProcess = Test-VMwareVMXProcess -VMXPath $VMXPath
Write-DiagLog "vmware-vmx processes (total): $($preStartProcess.AllProcesses.Count)"
foreach ($proc in $preStartProcess.AllProcesses) {
    Write-DiagLog "  PID $($proc.ProcessId): $($proc.CommandLine)"
}

if ($preStartProcess.Running) {
    Write-DiagLog "VM Process: RUNNING (PID: $($preStartProcess.ProcessId))" 'SUCCESS'
} else {
    Write-DiagLog "VM Process: Not running"
}

# Check lock files
$vmxLockPath = Join-Path $vmFolder "$vmName.vmx.lck"
$vmemLockPattern = Join-Path $vmFolder "*.vmem.lck"
$nvramPath = Join-Path $vmFolder "$vmName.nvram"

Write-DiagLog "vmx.lck folder: $(if (Test-Path $vmxLockPath) { 'EXISTS' } else { 'Does not exist' })"
if (Test-Path $vmxLockPath) {
    $lockContents = Get-ChildItem -Path $vmxLockPath -ErrorAction SilentlyContinue
    Write-DiagLog "  Contents: $($lockContents.Count) items"
    foreach ($item in $lockContents) {
        Write-DiagLog "    $($item.Name)"
    }
}

$vmemLocks = Get-ChildItem -Path $vmFolder -Filter "*.vmem.lck" -Directory -ErrorAction SilentlyContinue
Write-DiagLog "vmem.lck folders: $($vmemLocks.Count)"
foreach ($lock in $vmemLocks) {
    Write-DiagLog "  $($lock.Name)"
}

Write-DiagLog "nvram file: $(if (Test-Path $nvramPath) { 'EXISTS' } else { 'Does not exist (normal for VMware 25+)' })"

# Check vmrun list
Write-DiagLog ""
Write-DiagLog "Checking vmrun list..."
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $vmrunExe
$psi.Arguments = "-T ws list"
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true

$process = [System.Diagnostics.Process]::Start($psi)
$stdout = $process.StandardOutput.ReadToEnd()
$stderr = $process.StandardError.ReadToEnd()
$process.WaitForExit()

Write-DiagLog "vmrun list exit code: $($process.ExitCode)"
$lines = $stdout -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
foreach ($line in $lines) {
    Write-DiagLog "  $line"
}
if ($stderr) {
    Write-DiagLog "vmrun stderr: $stderr" 'WARN'
}

Write-DiagLog ""

# =============================================================================
# 5. START VM (if requested)
# =============================================================================

if ($StartVM) {
    Write-DiagLog "=== 5. Starting VM ===" 'SECTION'

    # Use nogui mode
    $startArgs = "-T ws start `"$VMXPath`" nogui"
    Write-DiagLog "Command: vmrun $startArgs"

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $vmrunExe
    $psi.Arguments = $startArgs
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $startTime = Get-Date
    $process = [System.Diagnostics.Process]::Start($psi)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    $elapsed = (Get-Date) - $startTime

    Write-DiagLog "Exit Code: $($process.ExitCode)"
    Write-DiagLog "Elapsed: $($elapsed.TotalSeconds) seconds"
    if ($stdout) { Write-DiagLog "stdout: $stdout" }
    if ($stderr) { Write-DiagLog "stderr: $stderr" }

    if ($process.ExitCode -eq 0) {
        Write-DiagLog "vmrun start returned success" 'SUCCESS'
    } else {
        Write-DiagLog "vmrun start FAILED!" 'ERROR'

        # Try with gui mode as fallback
        Write-DiagLog ""
        Write-DiagLog "Retrying with gui mode..."
        $startArgs = "-T ws start `"$VMXPath`" gui"
        Write-DiagLog "Command: vmrun $startArgs"

        $psi2 = New-Object System.Diagnostics.ProcessStartInfo
        $psi2.FileName = $vmrunExe
        $psi2.Arguments = $startArgs
        $psi2.UseShellExecute = $false
        $psi2.RedirectStandardOutput = $true
        $psi2.RedirectStandardError = $true
        $psi2.CreateNoWindow = $true

        $process2 = [System.Diagnostics.Process]::Start($psi2)
        $stdout2 = $process2.StandardOutput.ReadToEnd()
        $stderr2 = $process2.StandardError.ReadToEnd()
        $process2.WaitForExit()

        Write-DiagLog "Exit Code (gui): $($process2.ExitCode)"
        if ($stdout2) { Write-DiagLog "stdout: $stdout2" }
        if ($stderr2) { Write-DiagLog "stderr: $stderr2" }
    }

    Write-DiagLog ""
}

# =============================================================================
# 6. POST-START VERIFICATION
# =============================================================================

Write-DiagLog "=== 6. Post-Start Verification ===" 'SECTION'
Write-DiagLog "Waiting 3 seconds for VM to initialize..."
Start-Sleep -Seconds 3

# Method 1: Process detection (PRIMARY)
Write-DiagLog ""
Write-DiagLog "Method 1: vmware-vmx Process Detection"
$postProcess = Test-VMwareVMXProcess -VMXPath $VMXPath
Write-DiagLog "  vmware-vmx processes (total): $($postProcess.AllProcesses.Count)"
foreach ($proc in $postProcess.AllProcesses) {
    $isOurs = if ($proc.ProcessId -eq $postProcess.ProcessId) { " <-- OUR VM" } else { "" }
    Write-DiagLog "    PID $($proc.ProcessId)$isOurs"
}

if ($postProcess.Running) {
    Write-DiagLog "  RESULT: VM is RUNNING (PID: $($postProcess.ProcessId))" 'SUCCESS'
} else {
    Write-DiagLog "  RESULT: VM process NOT FOUND" 'WARN'
}

# Method 2: Lock file detection
Write-DiagLog ""
Write-DiagLog "Method 2: Lock File Detection"
$vmxLockExists = Test-Path $vmxLockPath
Write-DiagLog "  vmx.lck folder: $(if ($vmxLockExists) { 'EXISTS' } else { 'Does not exist' })"

if ($vmxLockExists) {
    $lockContents = Get-ChildItem -Path $vmxLockPath -ErrorAction SilentlyContinue
    $activeLocks = $lockContents | Where-Object { $_.Extension -eq '.lck' }
    Write-DiagLog "  Active lock files: $($activeLocks.Count)"
    foreach ($lock in $activeLocks) {
        Write-DiagLog "    $($lock.Name)"
    }
    if ($activeLocks.Count -gt 0) {
        Write-DiagLog "  RESULT: VM is RUNNING (lock files present)" 'SUCCESS'
    } else {
        Write-DiagLog "  RESULT: Lock folder exists but no active locks (stale?)" 'WARN'
    }
} else {
    Write-DiagLog "  RESULT: No lock folder" 'WARN'
}

# Method 3: vmem.lck detection
Write-DiagLog ""
Write-DiagLog "Method 3: vmem.lck Detection"
$vmemLocks = Get-ChildItem -Path $vmFolder -Filter "*.vmem.lck" -Directory -ErrorAction SilentlyContinue
Write-DiagLog "  vmem.lck folders: $($vmemLocks.Count)"
if ($vmemLocks.Count -gt 0) {
    foreach ($lock in $vmemLocks) {
        Write-DiagLog "    $($lock.Name)"
    }
    Write-DiagLog "  RESULT: VM is RUNNING (memory locks present)" 'SUCCESS'
} else {
    Write-DiagLog "  RESULT: No vmem.lck folders"
}

# Method 4: vmrun list (may be broken)
Write-DiagLog ""
Write-DiagLog "Method 4: vmrun list"
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $vmrunExe
$psi.Arguments = "-T ws list"
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true

$process = [System.Diagnostics.Process]::Start($psi)
$stdout = $process.StandardOutput.ReadToEnd()
$stderr = $process.StandardError.ReadToEnd()
$process.WaitForExit()

$lines = $stdout -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
Write-DiagLog "  Exit Code: $($process.ExitCode)"
foreach ($line in $lines) {
    Write-DiagLog "    $line"
}

# Check if our VM is in the list
$normalizedTarget = $VMXPath.ToLower().Replace('/', '\')
$foundInList = $false
foreach ($line in $lines) {
    if ($line -match '^Total running VMs:') { continue }
    $normalizedLine = $line.ToLower().Replace('/', '\')
    if ($normalizedLine -eq $normalizedTarget) {
        $foundInList = $true
        break
    }
}

if ($foundInList) {
    Write-DiagLog "  RESULT: VM found in vmrun list" 'SUCCESS'
} else {
    Write-DiagLog "  RESULT: VM NOT found in vmrun list (vmrun may be broken on this system)" 'WARN'
}

Write-DiagLog ""

# =============================================================================
# 7. STOP VM (if requested)
# =============================================================================

if ($StopVM) {
    Write-DiagLog "=== 7. Stopping VM ===" 'SECTION'

    $stopArgs = "-T ws stop `"$VMXPath`" hard"
    Write-DiagLog "Command: vmrun $stopArgs"

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $vmrunExe
    $psi.Arguments = $stopArgs
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $process = [System.Diagnostics.Process]::Start($psi)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    Write-DiagLog "Exit Code: $($process.ExitCode)"
    if ($stdout) { Write-DiagLog "stdout: $stdout" }
    if ($stderr) { Write-DiagLog "stderr: $stderr" }

    Write-DiagLog ""
}

# =============================================================================
# 8. SUMMARY
# =============================================================================

Write-DiagLog "=== 8. Summary ===" 'SECTION'

$detectionResults = @{
    ProcessDetection = $postProcess.Running
    LockFileDetection = ($vmxLockExists -and $activeLocks.Count -gt 0)
    VmemLockDetection = ($vmemLocks.Count -gt 0)
    VmrunListDetection = $foundInList
}

$workingMethods = @()
$brokenMethods = @()

if ($detectionResults.ProcessDetection) { $workingMethods += "Process Detection" }
else { $brokenMethods += "Process Detection" }

if ($detectionResults.LockFileDetection) { $workingMethods += "Lock File Detection" }
else { $brokenMethods += "Lock File Detection" }

if ($detectionResults.VmemLockDetection) { $workingMethods += "vmem.lck Detection" }
else { $brokenMethods += "vmem.lck Detection" }

if ($detectionResults.VmrunListDetection) { $workingMethods += "vmrun list" }
else { $brokenMethods += "vmrun list" }

Write-DiagLog "Working Detection Methods: $($workingMethods -join ', ')"
Write-DiagLog "Non-Working Detection Methods: $($brokenMethods -join ', ')"

Write-DiagLog ""
if ($workingMethods.Count -gt 0) {
    Write-DiagLog "RECOMMENDATION: Use '$($workingMethods[0])' as primary detection method" 'SUCCESS'
} else {
    Write-DiagLog "WARNING: No detection methods working - VM may not be running" 'ERROR'
}

Write-DiagLog ""
Write-DiagLog "=== Diagnostic Complete ===" 'SECTION'
Write-DiagLog "Log saved to: $logFile"

Write-Host ""
Write-Host "Diagnostics complete. Log file: $logFile" -ForegroundColor Cyan
