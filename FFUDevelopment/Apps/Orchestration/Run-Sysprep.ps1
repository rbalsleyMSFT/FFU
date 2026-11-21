#The below lines will remove the unattend.xml that gets the machine into audit mode. If not removed, the OS will get stuck booting to audit mode each time.
#Also kills the sysprep process in order to automate sysprep generalize
function Stop-SysprepProcess {
    $sysprepProcesses = @(Get-Process -Name 'sysprep' -ErrorAction SilentlyContinue)
    if (0 -eq $sysprepProcesses.Count) {
        return
    }

    Write-Host 'Stopping existing Sysprep process before continuing...'
    $sysprepProcesses | Stop-Process -Force -ErrorAction SilentlyContinue

    $deadline = (Get-Date).AddSeconds(30)
    do {
        Start-Sleep -Seconds 1
        $sysprepProcesses = @(Get-Process -Name 'sysprep' -ErrorAction SilentlyContinue)
    } while ($sysprepProcesses.Count -gt 0 -and (Get-Date) -lt $deadline)

    if ($sysprepProcesses.Count -gt 0) {
        throw 'Unable to stop the existing Sysprep process before continuing.'
    }
}

function Stop-CompetingSysprepProcess {
    param(
        [Parameter(Mandatory)]
        [int]$SysprepProcessId
    )

    $competingSysprepProcesses = @(Get-Process -Name 'sysprep' -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $SysprepProcessId })
    foreach ($competingSysprepProcess in $competingSysprepProcesses) {
        Write-Host "Stopping competing Sysprep process $($competingSysprepProcess.Id)."
        Stop-Process -Id $competingSysprepProcess.Id -Force -ErrorAction SilentlyContinue
    }
}

function Join-ProcessArgumentList {
    param(
        [Parameter(Mandatory)]
        [string[]]$ArgumentList
    )

    $escapedArguments = foreach ($argument in $ArgumentList) {
        if ($argument -match '[\s"]') {
            '"{0}"' -f ($argument -replace '"', '\"')
        }
        else {
            $argument
        }
    }

    return ($escapedArguments -join ' ')
}

function Invoke-SysprepProcess {
    param(
        [Parameter(Mandatory)]
        [string[]]$ArgumentList
    )

    $sysprepPath = 'C:\windows\system32\sysprep\sysprep.exe'
    $sysprepArgumentString = Join-ProcessArgumentList -ArgumentList $ArgumentList
    Write-Host "Starting Sysprep with arguments: $sysprepArgumentString"
    $sysprepProcess = Start-Process -FilePath $sysprepPath -ArgumentList $sysprepArgumentString -PassThru -ErrorAction Stop

    do {
        Stop-CompetingSysprepProcess -SysprepProcessId $sysprepProcess.Id
        Start-Sleep -Seconds 1
        $sysprepProcess.Refresh()
    } while (-not $sysprepProcess.HasExited)

    return $sysprepProcess.ExitCode
}

$orchestrationBootstrapPath = 'C:\Windows\Setup\Scripts\Start-FFUOrchestration.ps1'
if (Test-Path -LiteralPath $orchestrationBootstrapPath -PathType Leaf) {
    Write-Host "Removing build-only orchestration bootstrap: $orchestrationBootstrapPath"
    try {
        Remove-Item -LiteralPath $orchestrationBootstrapPath -Force -ErrorAction Stop
    }
    catch {
        Write-Warning "Unable to remove build-only orchestration bootstrap '$orchestrationBootstrapPath': $($_.Exception.Message)"
    }
}

Write-Host "Removing existing unattend.xml files and stopping sysprep process if running..."
Remove-Item -Path "C:\windows\panther\unattend\unattend.xml" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\windows\panther\unattend.xml" -Force -ErrorAction SilentlyContinue
Stop-SysprepProcess

$sysprepRetryTaskName = 'FFU-Sysprep-Retry'
$sysprepRetryRunOncePath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
$sysprepRetryRunOnceName = '!FFU-Sysprep-Retry'
$sysprepRetryStatePath = 'C:\Windows\Setup\Scripts\Logs\SysprepRetry.state'
$sysprepRetryScriptPath = 'C:\Windows\Setup\Scripts\Run-FFUSysprepRetry.ps1'
$maxSysprepRebootRetries = 1

function Disable-AuditModeSysprepStartup {
    $startupRegistryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
    )

    foreach ($startupRegistryPath in $startupRegistryPaths) {
        $startupRegistryKey = Get-Item -Path $startupRegistryPath -ErrorAction SilentlyContinue
        if ($null -eq $startupRegistryKey) {
            continue
        }

        foreach ($valueName in $startupRegistryKey.GetValueNames()) {
            if ($valueName -eq $sysprepRetryRunOnceName) {
                continue
            }

            $valueData = [string]$startupRegistryKey.GetValue($valueName)
            if ($valueData -notmatch '(?i)sysprep\.exe') {
                continue
            }

            Write-Host "Removing Audit mode Sysprep startup value '$valueName' from '$startupRegistryPath'."
            Remove-ItemProperty -Path $startupRegistryPath -Name $valueName -ErrorAction SilentlyContinue
        }
    }
}

Disable-AuditModeSysprepStartup

function Resolve-FFUAppsMediaRoot {
    $appsRoot = ([string]$env:FFUAppsRoot).Trim().TrimEnd('\')
    if (-not [string]::IsNullOrWhiteSpace($appsRoot) -and (Test-Path -Path $appsRoot)) {
        return $appsRoot
    }

    foreach ($driveInfo in Get-PSDrive -PSProvider FileSystem) {
        if ([string]::IsNullOrWhiteSpace([string]$driveInfo.Root)) {
            continue
        }

        $candidateOrchestrator = Join-Path -Path $driveInfo.Root -ChildPath 'Orchestration\Orchestrator.ps1'
        $candidateSysprep = Join-Path -Path $driveInfo.Root -ChildPath 'Orchestration\Run-Sysprep.ps1'
        if ((Test-Path -Path $candidateOrchestrator -PathType Leaf) -and (Test-Path -Path $candidateSysprep -PathType Leaf)) {
            return $driveInfo.Root.TrimEnd('\')
        }
    }

    return 'D:'
}

function Get-SysprepRetryCount {
    if (-not (Test-Path -LiteralPath $sysprepRetryStatePath -ErrorAction Stop)) {
        return 0
    }

    $retryCount = 0
    $savedRetryCount = Get-Content -LiteralPath $sysprepRetryStatePath -Raw -ErrorAction Stop
    if (-not [int]::TryParse($savedRetryCount, [ref]$retryCount) -or $retryCount -lt 0) {
        throw "Invalid Sysprep retry count in '$sysprepRetryStatePath'."
    }
    return $retryCount
}

function Set-SysprepRetryCount {
    param(
        [Parameter(Mandatory)]
        [int]$RetryCount
    )

    $retryStateFolder = Split-Path -Path $sysprepRetryStatePath -Parent
    New-Item -Path $retryStateFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    Set-Content -LiteralPath $sysprepRetryStatePath -Value ([string]$RetryCount) -Encoding ASCII -Force -ErrorAction Stop
}

function Clear-SysprepRetryResume {
    Unregister-ScheduledTask -TaskName $sysprepRetryTaskName -Confirm:$false -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $sysprepRetryRunOncePath -Name $sysprepRetryRunOnceName -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $sysprepRetryRunOncePath -Name $sysprepRetryTaskName -ErrorAction SilentlyContinue
    Remove-Item -Path $sysprepRetryScriptPath -Force -ErrorAction SilentlyContinue
}

function Clear-SysprepRetryState {
    Clear-SysprepRetryResume
    Remove-Item -Path $sysprepRetryStatePath -Force -ErrorAction SilentlyContinue
}

function Test-PendingReboot {
    return ((Get-PendingRebootReasons).Count -gt 0)
}

function Get-RegistryChildSummary {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $childNames = @(Get-ChildItem -Path $Path -ErrorAction SilentlyContinue | Select-Object -First 8 -ExpandProperty PSChildName)
    if (0 -eq $childNames.Count) {
        return ''
    }

    return ' Child keys: {0}' -f ($childNames -join ', ')
}

function Get-PendingRebootReasons {
    $pendingRebootReasons = @()

    $cbsRebootPendingPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    if (Test-Path -Path $cbsRebootPendingPath) {
        $pendingRebootReasons += "CBS RebootPending marker found at $cbsRebootPendingPath.$(Get-RegistryChildSummary -Path $cbsRebootPendingPath)"
    }

    $cbsPackagesPendingPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending'
    if (Test-Path -Path $cbsPackagesPendingPath) {
        $pendingRebootReasons += "CBS PackagesPending marker found at $cbsPackagesPendingPath.$(Get-RegistryChildSummary -Path $cbsPackagesPendingPath)"
    }

    $windowsUpdateRebootRequiredPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    if (Test-Path -Path $windowsUpdateRebootRequiredPath) {
        $pendingRebootReasons += "Windows Update RebootRequired marker found at $windowsUpdateRebootRequiredPath.$(Get-RegistryChildSummary -Path $windowsUpdateRebootRequiredPath)"
    }

    $pendingXmlPath = 'C:\Windows\WinSxS\pending.xml'
    if (Test-Path -Path $pendingXmlPath) {
        $pendingXml = Get-Item -Path $pendingXmlPath -ErrorAction SilentlyContinue
        if ($null -ne $pendingXml) {
            $pendingRebootReasons += "WinSxS pending.xml exists at $pendingXmlPath. LastWriteTime: $($pendingXml.LastWriteTime); Size: $($pendingXml.Length) bytes."
        }
        else {
            $pendingRebootReasons += "WinSxS pending.xml exists at $pendingXmlPath."
        }
    }

    $sessionManagerPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
    foreach ($pendingRenameValueName in @('PendingFileRenameOperations', 'PendingFileRenameOperations2')) {
        $pendingFileRename = (Get-ItemProperty -Path $sessionManagerPath -Name $pendingRenameValueName -ErrorAction SilentlyContinue).$pendingRenameValueName
        if ($null -eq $pendingFileRename) {
            continue
        }

        $pendingFileRenameEntries = @($pendingFileRename | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        $pendingRebootReasons += "Session Manager $pendingRenameValueName contains $($pendingFileRenameEntries.Count) pending file rename/delete entries:"
        $pendingFileRenameIndex = 1
        foreach ($pendingFileRenameEntry in $pendingFileRenameEntries) {
            $pendingRebootReasons += 'Session Manager {0} entry {1}: {2}' -f $pendingRenameValueName, $pendingFileRenameIndex, $pendingFileRenameEntry
            $pendingFileRenameIndex++
        }
    }

    $updatesPath = 'HKLM:\SOFTWARE\Microsoft\Updates'
    $updateExeVolatile = (Get-ItemProperty -Path $updatesPath -Name 'UpdateExeVolatile' -ErrorAction SilentlyContinue).UpdateExeVolatile
    if ($null -ne $updateExeVolatile -and 0 -ne $updateExeVolatile) {
        $pendingRebootReasons += "Microsoft Updates UpdateExeVolatile is $updateExeVolatile at $updatesPath."
    }

    return @($pendingRebootReasons)
}

function Write-PendingRebootReasons {
    param(
        [string[]]$PendingRebootReasons
    )

    if ($null -eq $PendingRebootReasons -or 0 -eq $PendingRebootReasons.Count) {
        Write-Host 'Pending reboot detected, but no specific pending reboot marker details were collected.'
        return
    }

    Write-Host 'Pending reboot reason(s) detected:'
    foreach ($pendingRebootReason in $PendingRebootReasons) {
        Write-Host " - $pendingRebootReason"
    }
}

function Test-SysprepPendingRebootFailure {
    $sysprepLogPaths = @(
        'C:\Windows\System32\Sysprep\Panther\setuperr.log',
        'C:\Windows\System32\Sysprep\Panther\setupact.log'
    )

    foreach ($sysprepLogPath in $sysprepLogPaths) {
        if (-not (Test-Path -Path $sysprepLogPath)) {
            continue
        }

        $sysprepLogText = Get-Content -Path $sysprepLogPath -Tail 200 -ErrorAction SilentlyContinue | Out-String
        if ($sysprepLogText -match '0x8007139f|pending\s+reboot|reboot\s+required|required\s+reboot|Windows Updates?.*reboot|pre-validate sysprep cleanup internal providers') {
            return $true
        }
    }

    return (Test-PendingReboot)
}

function New-SysprepRetryLauncher {
    $retryScriptFolder = Split-Path -Path $sysprepRetryScriptPath -Parent
    New-Item -Path $retryScriptFolder -ItemType Directory -Force | Out-Null

    $retryScript = @'
$ErrorActionPreference = 'Stop'

function Disable-AuditModeSysprepStartup {
    $startupRegistryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
    )

    foreach ($startupRegistryPath in $startupRegistryPaths) {
        $startupRegistryKey = Get-Item -Path $startupRegistryPath -ErrorAction SilentlyContinue
        if ($null -eq $startupRegistryKey) {
            continue
        }

        foreach ($valueName in $startupRegistryKey.GetValueNames()) {
            $valueData = [string]$startupRegistryKey.GetValue($valueName)
            if ($valueData -notmatch '(?i)sysprep\.exe') {
                continue
            }

            Write-Host "Removing Audit mode Sysprep startup value '$valueName' from '$startupRegistryPath'."
            Remove-ItemProperty -Path $startupRegistryPath -Name $valueName -ErrorAction SilentlyContinue
        }
    }
}

& (Join-Path $PSScriptRoot 'Invoke-FFUBuildVmStage.ps1') -Stage 'Sysprep retry' -LogPath 'C:\Windows\Temp\FFUSysprepRetry.log' -Action {
    Write-Host 'Starting FFU sysprep retry.'
    Disable-AuditModeSysprepStartup

    Write-Host 'Waiting for the Audit mode desktop shell to load before retrying.'
    $explorerProcesses = @()
    $shellDeadline = (Get-Date).AddMinutes(2)
    do {
        $explorerProcesses = @(Get-Process -Name 'explorer' -ErrorAction SilentlyContinue)
        if ($explorerProcesses.Count -gt 0) {
            Write-Host 'Detected Explorer shell. Continuing retry.'
            break
        }

        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $shellDeadline)

    if (0 -eq $explorerProcesses.Count) {
        Write-Host 'Explorer shell was not detected before timeout. Continuing retry.'
    }

    Write-Host 'Waiting briefly for the Audit mode Sysprep UI to launch, then closing it before retrying.'
    $sysprepUiSeen = $false
    $minimumSysprepUiWaitDeadline = (Get-Date).AddSeconds(15)
    $sysprepUiQuietDeadline = (Get-Date).AddSeconds(15)
    $sysprepUiDeadline = (Get-Date).AddMinutes(2)
    do {
        $sysprepProcesses = @(Get-Process -Name 'sysprep' -ErrorAction SilentlyContinue)
        if ($sysprepProcesses.Count -gt 0) {
            $sysprepUiSeen = $true
            foreach ($sysprepProcess in $sysprepProcesses) {
                Write-Host "Stopping Audit mode Sysprep process $($sysprepProcess.Id) before retrying."
                Stop-Process -Id $sysprepProcess.Id -Force -ErrorAction SilentlyContinue
            }

            $sysprepUiQuietDeadline = (Get-Date).AddSeconds(10)
        }
        elseif ((Get-Date) -ge $minimumSysprepUiWaitDeadline -and (Get-Date) -ge $sysprepUiQuietDeadline) {
            break
        }

        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $sysprepUiDeadline)

    if ($sysprepUiSeen) {
        Write-Host 'Audit mode Sysprep UI is closed.'
    }
    else {
        Write-Host 'Audit mode Sysprep UI was not detected before retrying.'
    }

    $deadline = (Get-Date).AddMinutes(10)
    $sysprepScript = $null

    do {
        $fileSystemDrives = @(Get-PSDrive -PSProvider FileSystem | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Root) })
        foreach ($driveInfo in $fileSystemDrives) {
            $candidatePath = Join-Path -Path $driveInfo.Root -ChildPath 'Orchestration\Run-Sysprep.ps1'
            Write-Host "Checking for sysprep script at $candidatePath"
            if (Test-Path -Path $candidatePath -PathType Leaf) {
                $sysprepScript = $candidatePath
                break
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($sysprepScript)) {
            break
        }

        Write-Host 'Apps ISO sysprep script was not found yet. Waiting before retry.'
        Start-Sleep -Seconds 5
    } while ((Get-Date) -lt $deadline)

    if ([string]::IsNullOrWhiteSpace($sysprepScript)) {
        throw 'Unable to locate Apps ISO Run-Sysprep.ps1 after waiting for Apps media.'
    }

    $env:FFUAppsRoot = Split-Path -Parent (Split-Path -Parent $sysprepScript)
    Write-Host "Using Apps media root: $env:FFUAppsRoot"
    Write-Host "Launching sysprep script: $sysprepScript"
    & $sysprepScript
}
'@

    Set-Content -Path $sysprepRetryScriptPath -Value $retryScript -Encoding ASCII -Force
}

function Register-SysprepRetryResume {
    Disable-AuditModeSysprepStartup
    New-SysprepRetryLauncher

    $cmdPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\cmd.exe'
    $powerShellPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $runOnceCommand = "`"$cmdPath`" /c start `"FFU Sysprep Retry`" `"$powerShellPath`" -NoProfile -ExecutionPolicy Bypass -File `"$sysprepRetryScriptPath`""
    New-Item -Path $sysprepRetryRunOncePath -Force | Out-Null
    New-ItemProperty -Path $sysprepRetryRunOncePath -Name $sysprepRetryRunOnceName -Value $runOnceCommand -PropertyType String -Force | Out-Null
}

function Restart-SysprepRetry {
    param(
        [Parameter(Mandatory)]
        [string]$Reason,

        [Parameter(Mandatory)]
        [int]$RetryCount,

        [string[]]$PendingRebootReasons
    )

    if ($RetryCount -ge $maxSysprepRebootRetries) {
        return $false
    }

    Write-Host $Reason
    Write-PendingRebootReasons -PendingRebootReasons $PendingRebootReasons

    # Let TrustedInstaller reach its idle stop before requesting the retry reboot.
    $trustedInstallerTimeout = [TimeSpan]::FromMinutes(5)
    $statusUpdateInterval = [TimeSpan]::FromSeconds(5)
    $trustedInstaller = Get-Service -Name 'TrustedInstaller' -ErrorAction Stop
    $waitTimer = [System.Diagnostics.Stopwatch]::StartNew()
    while ($trustedInstaller.Status -ne 'Stopped') {
        $elapsed = $waitTimer.Elapsed
        $remaining = $trustedInstallerTimeout - $elapsed
        if ($remaining -le [TimeSpan]::Zero) {
            throw "TrustedInstaller did not stop on its own within $($trustedInstallerTimeout.TotalSeconds) seconds. No Sysprep retry reboot was requested."
        }

        Write-Host ('TrustedInstaller status: {0} ({1:F1}s elapsed). Restarting as soon as it stops on its own.' -f $trustedInstaller.Status, $elapsed.TotalSeconds)
        $waitInterval = if ($remaining -lt $statusUpdateInterval) { $remaining } else { $statusUpdateInterval }
        try {
            $trustedInstaller.WaitForStatus('Stopped', $waitInterval)
        }
        catch [System.ServiceProcess.TimeoutException] {
            continue
        }
    }
    Write-Host ('TrustedInstaller is stopped after {0:F1} seconds.' -f $waitTimer.Elapsed.TotalSeconds)

    Set-SysprepRetryCount -RetryCount ($RetryCount + 1)
    Register-SysprepRetryResume
    Write-Host 'Restarting now. Sysprep will resume during the next Audit mode logon.'
    Restart-Computer -ErrorAction Stop
    return $true
}

# Detect and remediate per-user, non-provisioned Appx packages that would block Sysprep.
Write-Host "Checking for per-user Appx packages not provisioned for all users (potential Sysprep blockers)..."

# Build hash set of provisioned package families (DisplayName_PublisherId).
$provFamilies = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
Get-AppxProvisionedPackage -Online | ForEach-Object {
    $family = '{0}_{1}' -f $_.DisplayName, $_.PublisherId
    [void]$provFamilies.Add($family)
}

# Collect current user Appx packages excluding frameworks, resource packs, and non-removable packages.
$userApps = Get-AppxPackage -User $env:USERNAME | Where-Object {
    $_.Status -eq 'Ok' -and
    -not $_.IsFramework -and
    -not $_.IsResourcePackage -and
    -not $_.NonRemovable
}

# Identify packages not provisioned (per-user only).
$notProvisioned = foreach ($pkg in $userApps) {
    if (-not $provFamilies.Contains($pkg.PackageFamilyName)) {
        [PSCustomObject]@{
            Name              = $pkg.Name
            PackageFamilyName = $pkg.PackageFamilyName
            Version           = $pkg.Version
            SignatureKind     = $pkg.SignatureKind
            PackageFullName   = $pkg.PackageFullName
        }
    }
}

if ($notProvisioned) {
    Write-Host "Found $($notProvisioned.Count) per-user Appx package(s) not provisioned for all users:"
    $notProvisioned | Sort-Object PackageFamilyName | Format-Table -AutoSize -Property Name,PackageFamilyName,Version
    Write-Host "Attempting removal of per-user, non-provisioned Appx packages..."
    foreach ($pkg in $notProvisioned) {
        try {
            Write-Host "Removing $($pkg.PackageFullName)..."
            Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
        }
        catch {
            Write-Warning "Failed to remove $($pkg.PackageFullName): $($_.Exception.Message)"
        }
    }

    # Re-check after attempted removals.
    $remaining = @()
    $currentUserApps = Get-AppxPackage -User $env:USERNAME | Where-Object {
        $_.Status -eq 'Ok' -and
        -not $_.IsFramework -and
        -not $_.IsResourcePackage -and
        -not $_.NonRemovable
    }
    foreach ($pkg in $currentUserApps) {
        if (-not $provFamilies.Contains($pkg.PackageFamilyName)) {
            $remaining += $pkg
        }
    }

    if ($remaining.Count -gt 0) {
        Write-Error "Unable to remove all per-user, non-provisioned Appx packages. Sysprep cannot continue."
        $remaining | Sort-Object PackageFamilyName | Format-Table -AutoSize -Property Name,PackageFamilyName,Version
        throw "Sysprep aborted due to unresolved per-user Appx packages. Resolve manually and re-run."
    }
    else {
        Write-Host "All per-user, non-provisioned Appx packages were successfully removed."
    }
}
else {
    Write-Host "No per-user, non-provisioned Appx packages detected."
}

# If an Unattend.xml has been provided on the mounted Apps ISO,
# pass it to sysprep; otherwise, run without /unattend.
$appsMediaRoot = Resolve-FFUAppsMediaRoot
$env:FFUAppsRoot = $appsMediaRoot
$unattendOnAppsIso = Join-Path -Path $appsMediaRoot -ChildPath "Unattend\Unattend.xml"

$sysprepArguments = @('/quiet', '/generalize', '/oobe')
if (Test-Path -Path $unattendOnAppsIso) {
    Write-Host "Using $unattendOnAppsIso from Apps ISO..."
    $sysprepArguments += "/unattend:$unattendOnAppsIso"
}

$retryCount = $null
$pendingRebootReasons = @()
$sysprepExitCode = $null
try {
    $retryCount = Get-SysprepRetryCount
    $pendingRebootReasons = @(Get-PendingRebootReasons)
    if ($pendingRebootReasons.Count -gt 0) {
        if (Restart-SysprepRetry -RetryCount $retryCount -Reason 'Pending reboot detected immediately before Sysprep.' -PendingRebootReasons $pendingRebootReasons) {
            return
        }

        throw "Pending reboot is still detected after $retryCount Sysprep retry reboot(s). Sysprep cannot continue."
    }

    Clear-SysprepRetryResume

    Disable-AuditModeSysprepStartup
    Stop-SysprepProcess
    $sysprepExitCode = Invoke-SysprepProcess -ArgumentList $sysprepArguments

    if (0 -eq $sysprepExitCode) {
        Clear-SysprepRetryState
        return
    }

    if (Test-SysprepPendingRebootFailure) {
        $pendingRebootReasons = @(Get-PendingRebootReasons)
        if (Restart-SysprepRetry -RetryCount $retryCount -Reason 'Sysprep reported a pending-reboot condition.' -PendingRebootReasons $pendingRebootReasons) {
            return
        }
    }

    throw "Sysprep failed with exit code $sysprepExitCode. Review C:\Windows\System32\Sysprep\Panther\setuperr.log and setupact.log."
}
catch {
    $_.Exception.Data['FFUSysprepFailure'] = $true
    $_.Exception.Data['FFUSysprepRetryCount'] = $retryCount
    $_.Exception.Data['FFUPendingRebootReasons'] = $pendingRebootReasons
    $_.Exception.Data['FFUSysprepExitCode'] = $sysprepExitCode
    Clear-SysprepRetryState
    throw
}
