<#
.SYNOPSIS
    Diagnostic script to investigate vmrun list issues

.DESCRIPTION
    Gathers comprehensive diagnostic information about vmrun.exe behavior,
    VMware Workstation state, and VM detection methods.

.EXAMPLE
    .\Test-VmrunList.ps1
    .\Test-VmrunList.ps1 -VMXPath "C:\VMs\MyVM\MyVM.vmx"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$VMXPath
)

$ErrorActionPreference = 'Continue'
$timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$logFile = Join-Path $PSScriptRoot "vmrun-diagnostics-$timestamp.log"

function Write-DiagLog {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "[$timestamp] [$Level] $Message"
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

Write-DiagLog "=== VMware vmrun.exe Diagnostic Report ===" 'HEADER'
Write-DiagLog "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-DiagLog "Computer: $env:COMPUTERNAME"
Write-DiagLog "User: $env:USERNAME"
Write-DiagLog "PowerShell: $($PSVersionTable.PSVersion)"
Write-DiagLog ""

# 1. VMware Installation Detection
Write-DiagLog "=== 1. VMware Installation ===" 'SECTION'

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
    Write-DiagLog "VMware Install Path: $vmwareInstallPath"

    $vmwareExe = Join-Path $vmwareInstallPath 'vmware.exe'
    $vmrunExe = Join-Path $vmwareInstallPath 'vmrun.exe'

    if (Test-Path $vmwareExe) {
        $version = (Get-Item $vmwareExe).VersionInfo
        Write-DiagLog "VMware Version: $($version.ProductVersion) ($($version.FileVersion))"
    }

    if (Test-Path $vmrunExe) {
        Write-DiagLog "vmrun.exe exists: $vmrunExe"
    } else {
        Write-DiagLog "vmrun.exe NOT FOUND!" 'ERROR'
    }
} else {
    Write-DiagLog "VMware Workstation installation NOT FOUND!" 'ERROR'
    exit 1
}

Write-DiagLog ""

# 2. Running Processes
Write-DiagLog "=== 2. VMware Processes ===" 'SECTION'

$vmwareProcesses = @('vmware', 'vmware-vmx', 'vmware-hostd', 'vmnat', 'vmnetdhcp', 'vmware-authd')
foreach ($procName in $vmwareProcesses) {
    $procs = Get-Process -Name $procName -ErrorAction SilentlyContinue
    if ($procs) {
        foreach ($proc in $procs) {
            Write-DiagLog "  $procName (PID: $($proc.Id), Session: $($proc.SessionId), User: $(try { $proc.StartInfo.UserName } catch { 'N/A' }))"
        }
    } else {
        Write-DiagLog "  ${procName}: Not running"
    }
}

# Check for vmware-vmx specifically - these are the actual VM processes
$vmxProcesses = Get-Process -Name 'vmware-vmx' -ErrorAction SilentlyContinue
if ($vmxProcesses) {
    Write-DiagLog ""
    Write-DiagLog "vmware-vmx processes (VM instances):"
    foreach ($vmx in $vmxProcesses) {
        Write-DiagLog "  PID: $($vmx.Id), CPU: $($vmx.CPU), Memory: $([math]::Round($vmx.WorkingSet64/1MB, 2)) MB"
        try {
            $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($vmx.Id)").CommandLine
            Write-DiagLog "    CommandLine: $cmdLine"
        } catch {
            Write-DiagLog "    CommandLine: Unable to retrieve"
        }
    }
}

Write-DiagLog ""

# 3. vmrun list command tests
Write-DiagLog "=== 3. vmrun list Command Tests ===" 'SECTION'

# Test 1: Basic vmrun list
Write-DiagLog "Test 1: vmrun -T ws list"
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

Write-DiagLog "  Exit Code: $($process.ExitCode)"
Write-DiagLog "  STDOUT:"
foreach ($line in ($stdout -split "`n")) {
    Write-DiagLog "    $($line.Trim())"
}
if ($stderr) {
    Write-DiagLog "  STDERR:"
    foreach ($line in ($stderr -split "`n")) {
        Write-DiagLog "    $($line.Trim())"
    }
}

# Test 2: vmrun list without -T ws
Write-DiagLog ""
Write-DiagLog "Test 2: vmrun list (no -T flag)"
$psi2 = New-Object System.Diagnostics.ProcessStartInfo
$psi2.FileName = $vmrunExe
$psi2.Arguments = "list"
$psi2.UseShellExecute = $false
$psi2.RedirectStandardOutput = $true
$psi2.RedirectStandardError = $true
$psi2.CreateNoWindow = $true

$process2 = [System.Diagnostics.Process]::Start($psi2)
$stdout2 = $process2.StandardOutput.ReadToEnd()
$stderr2 = $process2.StandardError.ReadToEnd()
$process2.WaitForExit()

Write-DiagLog "  Exit Code: $($process2.ExitCode)"
Write-DiagLog "  STDOUT:"
foreach ($line in ($stdout2 -split "`n")) {
    Write-DiagLog "    $($line.Trim())"
}
if ($stderr2) {
    Write-DiagLog "  STDERR:"
    foreach ($line in ($stderr2 -split "`n")) {
        Write-DiagLog "    $($line.Trim())"
    }
}

Write-DiagLog ""

# 4. Check for running VMs via lock files
Write-DiagLog "=== 4. VM Lock File Detection ===" 'SECTION'

if ($VMXPath) {
    $vmFolder = Split-Path $VMXPath -Parent
    $vmName = [System.IO.Path]::GetFileNameWithoutExtension($VMXPath)

    Write-DiagLog "Checking VM: $VMXPath"
    Write-DiagLog "  VMX Exists: $(Test-Path $VMXPath)"

    # Check lock files
    $lockPath = Join-Path $vmFolder "$vmName.vmx.lck"
    $nvramPath = Join-Path $vmFolder "$vmName.nvram"

    Write-DiagLog "  Lock folder ($vmName.vmx.lck): $(Test-Path $lockPath)"
    if (Test-Path $lockPath) {
        $lockContents = Get-ChildItem -Path $lockPath -ErrorAction SilentlyContinue
        Write-DiagLog "    Contents: $($lockContents.Count) items"
        foreach ($item in $lockContents) {
            Write-DiagLog "      $($item.Name)"
        }
    }

    Write-DiagLog "  NVRAM file: $(Test-Path $nvramPath)"
    if (Test-Path $nvramPath) {
        try {
            $fs = [System.IO.File]::Open($nvramPath, 'Open', 'Read', 'None')
            $fs.Close()
            Write-DiagLog "    NVRAM file is NOT locked (VM is OFF)"
        } catch {
            Write-DiagLog "    NVRAM file IS LOCKED (VM may be running)"
        }
    }

    # Check all lock folders
    $allLocks = Get-ChildItem -Path $vmFolder -Filter "*.lck" -Directory -ErrorAction SilentlyContinue
    if ($allLocks) {
        Write-DiagLog "  All lock folders in VM directory:"
        foreach ($lock in $allLocks) {
            Write-DiagLog "    $($lock.Name)"
        }
    }
}

Write-DiagLog ""

# 5. VMware inventory file
Write-DiagLog "=== 5. VMware Inventory Files ===" 'SECTION'

$inventoryPaths = @(
    "$env:APPDATA\VMware\inventory.vmls",
    "$env:USERPROFILE\.vmware\inventory.vmls",
    "$env:PROGRAMDATA\VMware\VMware Workstation\inventory.vmls"
)

foreach ($invPath in $inventoryPaths) {
    if (Test-Path $invPath) {
        Write-DiagLog "Found inventory: $invPath"
        $content = Get-Content $invPath -Raw -ErrorAction SilentlyContinue
        if ($content) {
            $vmEntries = [regex]::Matches($content, 'vmlist\d+\.config\s*=\s*"([^"]+)"')
            Write-DiagLog "  Registered VMs: $($vmEntries.Count)"
            foreach ($entry in $vmEntries) {
                Write-DiagLog "    $($entry.Groups[1].Value)"
            }
        }
    }
}

Write-DiagLog ""

# 6. VMware Services
Write-DiagLog "=== 6. VMware Services ===" 'SECTION'

$vmwareServices = Get-Service -Name "VMware*" -ErrorAction SilentlyContinue
if ($vmwareServices) {
    foreach ($svc in $vmwareServices) {
        Write-DiagLog "  $($svc.Name): $($svc.Status)"
    }
} else {
    Write-DiagLog "  No VMware services found"
}

Write-DiagLog ""

# 7. Environment and context
Write-DiagLog "=== 7. Execution Context ===" 'SECTION'
Write-DiagLog "  Current User: $env:USERNAME"
Write-DiagLog "  User Domain: $env:USERDOMAIN"
Write-DiagLog "  Session ID: $([System.Diagnostics.Process]::GetCurrentProcess().SessionId)"
Write-DiagLog "  Is Admin: $([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)"
Write-DiagLog "  Working Directory: $(Get-Location)"

Write-DiagLog ""
Write-DiagLog "=== Diagnostic Report Complete ===" 'HEADER'
Write-DiagLog "Log saved to: $logFile"

Write-Host ""
Write-Host "Diagnostics complete. Log file: $logFile" -ForegroundColor Cyan
