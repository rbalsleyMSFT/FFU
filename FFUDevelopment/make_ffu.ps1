#requires -RunAsAdministrator
#requires -Modules Hyper-V
<#
.SYNOPSIS
    Mounts a sysprepped Hyper-V VHDX, verifies the staged drivers survived
    generalize, then captures a bootable FFU with DISM.

.DESCRIPTION
    Run this on the Hyper-V HOST after "sysprep /generalize /oobe /shutdown"
    has completed and the VM is Off. The VM must NOT be booted again.

    Sequence:
      1. Preflight  - VM state, VHDX free/locked, DISM present, output space
      2. Verify     - mounts VHDX read/write, runs DISM /Get-Drivers offline,
                      reads sysprep logs, confirms Panther\unattend.xml staged
      3. PAUSE      - you read the results and press Enter (or Q to abort)
      4. Capture    - remounts READ-ONLY, DISM /Capture-FFU
      5. Cleanup    - always dismounts, even on failure

.NOTES
    A collapsed driver count (~20 instead of hundreds) means
    PersistAllDeviceInstalls did not apply. Do NOT capture - re-sysprep.
#>

#===============================================================================
#  CONFIGURE ME
#===============================================================================

# --- Source -------------------------------------------------------------------
# The sysprepped VHDX. Leave $VMName set to auto-discover the path from the VM,
# or set $VhdxPath directly and leave $VMName empty.
$VMName    = 'Win11-Reference'
$VhdxPath  = 'C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\Win11-Reference.vhdx'    # e.g. 'D:\VMs\FFU-Build\Virtual Hard Disks\FFU-Build.vhdx'

# --- Output -------------------------------------------------------------------
$FfuFolder      = 'F:\'                   # must NOT be inside the VHDX
$ImageName      = 'T14G4'                    # short label, also used in filename
$ImageDescription = 'Win11 25H2 + ThinkPad T14 Gen 4 drivers'
$AppendDateToName = $true                    # T14G4_20260908.ffu

# --- Capture behaviour --------------------------------------------------------
# 'None'    = fastest, largest  (good for build/test loops)
# 'Default' = ~half the size, notably slower (good for the FFU you ship)
$Compress = 'Default'

$OptimizeFfu = $false                        # run DISM /Optimize-FFU afterwards

# --- Verification thresholds --------------------------------------------------
# A clean Win11 install has roughly 15-25 third-party packages. Anything at or
# below this means generalize stripped your staged drivers.
$MinExpectedDrivers = 60

$RequireUnattendStaged = $true               # fail if Panther\unattend.xml missing

# --- Paths inside the image that must be gone before capture ------------------
# Driver cache/scratch left behind by Add-LenovoDriversToImage.ps1.
$MustBeAbsent = @('_DriverCache', '_DriverStage', 'Build')

# --- Behaviour ----------------------------------------------------------------
$PauseForReview = $true                      # $false = fully unattended
$DismPath       = 'dism.exe'                 # or full ADK path if needed

#===============================================================================
#  END CONFIG
#===============================================================================

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
$script:Mounted        = $null

function Write-Step { param([string]$m) Write-Host "`n=== $m ===" -ForegroundColor Cyan }
function Write-Ok   { param([string]$m) Write-Host "  [ OK ] $m" -ForegroundColor Green }
function Write-Warn { param([string]$m) Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function Write-Bad  { param([string]$m) Write-Host "  [FAIL] $m" -ForegroundColor Red }
function Write-Info { param([string]$m) Write-Host "  $m" -ForegroundColor Gray }

function Dismount-Safe {
    param([string]$Path)
    if (-not $Path) { return }
    try {
        if (Get-DiskImage -ImagePath $Path -ErrorAction Stop | Where-Object Attached) {
            Dismount-VHD -Path $Path -ErrorAction Stop
            Write-Info "Dismounted $Path"
        }
    } catch { Write-Warn "Dismount issue: $($_.Exception.Message)" }
}

function Get-OsVolumeLetter {
    <# Returns the drive letter of the Windows partition on a mounted disk. #>
    param([Parameter(Mandatory)][int]$DiskNumber)

    $parts = Get-Partition -DiskNumber $DiskNumber |
             Where-Object { $_.Size -gt 5GB -and $_.Type -ne 'Reserved' }
    foreach ($p in $parts) {
        $letter = $p.DriveLetter
        if (-not $letter) {
            # Unlettered basic partition - give it one temporarily.
            try {
                $free = [char[]](68..90) | Where-Object { -not (Test-Path "$($_):\") } | Select-Object -First 1
                if ($free) { Set-Partition -DiskNumber $DiskNumber -PartitionNumber $p.PartitionNumber -NewDriveLetter $free
                             $letter = $free }
            } catch { continue }
        }
        if ($letter -and (Test-Path "$($letter):\Windows\System32\config\SYSTEM")) { return "$letter" }
    }
    return $null
}

try {

#--- 1. PREFLIGHT --------------------------------------------------------------
Write-Step 'PREFLIGHT'

if ($VMName) {
    $vm = Get-VM -Name $VMName -ErrorAction Stop
    Write-Info "VM '$VMName' state: $($vm.State)"
    if ($vm.State -ne 'Off') {
        throw "VM is '$($vm.State)'. It must be Off (shut down by sysprep). Do NOT boot it again - booting consumes the answer file and generates a machine SID."
    }
    Write-Ok 'VM is Off'

    if (-not $VhdxPath) {
        $drives = @(Get-VMHardDiskDrive -VMName $VMName)
        if ($drives.Count -eq 0) { throw "VM '$VMName' has no attached hard disks." }
        $VhdxPath = $drives[0].Path
        Write-Info "Auto-detected VHDX: $VhdxPath"
        if ($drives.Count -gt 1) {
            Write-Warn "VM has $($drives.Count) disks; using the first. Set `$VhdxPath explicitly if that's wrong:"
            $drives | ForEach-Object { Write-Info "    $($_.ControllerType)$($_.ControllerNumber):$($_.ControllerLocation)  $($_.Path)" }
        }
    }
}

if (-not $VhdxPath) { throw 'Set either $VMName or $VhdxPath.' }
if (-not (Test-Path -LiteralPath $VhdxPath)) { throw "VHDX not found: $VhdxPath" }

$vhdInfo = Get-VHD -Path $VhdxPath
Write-Info ('VHDX: {0}  type={1}  virtual={2} GB  file={3} GB' -f (Split-Path $VhdxPath -Leaf),
            $vhdInfo.VhdType,
            [Math]::Round($vhdInfo.Size/1GB,1),
            [Math]::Round($vhdInfo.FileSize/1GB,1))

# FFU records the source disk size; it will not apply to a SMALLER target disk.
Write-Warn ('This FFU will only apply to disks >= {0} GB. Confirm that is <= your smallest target SSD.' -f [Math]::Round($vhdInfo.Size/1GB,0))

if ($vhdInfo.Attached) {
    Write-Warn 'VHDX is already attached - dismounting first.'
    Dismount-Safe -Path $VhdxPath
}

if (-not (Get-Command $DismPath -ErrorAction SilentlyContinue)) { throw "DISM not found at '$DismPath'." }
Write-Ok 'DISM available'

$null = New-Item -Path $FfuFolder -ItemType Directory -Force
if ((Split-Path $FfuFolder -Qualifier) -eq (Split-Path $VhdxPath -Qualifier)) {
    Write-Warn 'Output folder is on the same volume as the VHDX. Fine, but watch free space.'
}
$freeGB = [Math]::Round((Get-PSDrive (Split-Path $FfuFolder -Qualifier).TrimEnd(':')).Free/1GB,1)
Write-Info "Free space at output: $freeGB GB"
if ($freeGB -lt [Math]::Round($vhdInfo.FileSize/1GB,0)) {
    Write-Warn 'Free space is less than the VHDX file size. Capture may fail.'
}

$stamp    = if ($AppendDateToName) { '_' + (Get-Date -Format 'yyyyMMdd') } else { '' }
$ffuFile  = Join-Path $FfuFolder ("{0}{1}.ffu" -f $ImageName, $stamp)
if (Test-Path -LiteralPath $ffuFile) {
    Write-Warn "Output exists and will be overwritten: $ffuFile"
    Remove-Item -LiteralPath $ffuFile -Force
}
Write-Info "Target FFU: $ffuFile"

#--- 2. VERIFY (read/write mount - DISM /Image: requires it) --------------------
Write-Step 'VERIFY IMAGE CONTENTS'
Write-Info 'Mounting read/write (offline DISM servicing needs write access)...'

$disk = Mount-VHD -Path $VhdxPath -Passthru | Get-Disk
$script:Mounted = $VhdxPath
Write-Ok "Mounted as PhysicalDrive$($disk.Number)  (partition style: $($disk.PartitionStyle))"

if ($disk.PartitionStyle -ne 'GPT') { Write-Warn "Partition style is $($disk.PartitionStyle); UEFI images should be GPT." }

$osLetter = Get-OsVolumeLetter -DiskNumber $disk.Number
if (-not $osLetter) { throw 'Could not locate the Windows partition on the mounted VHDX.' }
$osRoot = "$($osLetter):\"
Write-Ok "Windows volume: $osRoot"

$verifyFailed = @()

# -- 2a. driver count ----------------------------------------------------------
Write-Host "`n-- Third-party driver packages (offline) --" -ForegroundColor White
$driverRaw   = & $DismPath "/Image:$osRoot" /Get-Drivers /Format:Table 2>&1
$driverLines = @($driverRaw | Select-String -SimpleMatch 'oem' )
$driverCount = @($driverRaw | Select-String -Pattern 'Published Name\s*:\s*oem\d+\.inf').Count
if ($driverCount -eq 0) { $driverCount = $driverLines.Count }

Write-Info "Published third-party packages: $driverCount"

# class breakdown, handy sanity signal
$classes = @($driverRaw | Select-String -Pattern 'Class Name\s*:\s*(\S+)' -AllMatches |
             ForEach-Object { $_.Matches.Groups[1].Value }) | Group-Object | Sort-Object Count -Descending
if ($classes) {
    Write-Info 'By class:'
    $classes | Select-Object -First 15 | ForEach-Object { Write-Info ('    {0,-22} {1}' -f $_.Name, $_.Count) }
}

foreach ($critical in 'Net','SCSIAdapter','HDC','System','Display','Media','Bluetooth') {
    $n = @($classes | Where-Object Name -eq $critical).Count
    if ($n -eq 0) { Write-Warn "No '$critical' class drivers found." }
}

if ($driverCount -lt $MinExpectedDrivers) {
    Write-Bad "Only $driverCount packages (expected >= $MinExpectedDrivers). PersistAllDeviceInstalls likely did NOT apply - generalize stripped the staged drivers."
    $verifyFailed += "driver count $driverCount < $MinExpectedDrivers"
} else {
    Write-Ok "$driverCount driver packages survived generalize"
}

# -- 2b. sysprep result --------------------------------------------------------
Write-Host "`n-- Sysprep logs --" -ForegroundColor White
$errLog = Join-Path $osRoot 'Windows\System32\Sysprep\Panther\setuperr.log'
$actLog = Join-Path $osRoot 'Windows\System32\Sysprep\Panther\setupact.log'

if (Test-Path -LiteralPath $errLog) {
    $errText = @(Get-Content -LiteralPath $errLog -ErrorAction SilentlyContinue | Where-Object { $_.Trim() })
    if ($errText.Count -gt 0) {
        Write-Warn "setuperr.log has $($errText.Count) line(s); last 10:"
        $errText | Select-Object -Last 10 | ForEach-Object { Write-Info "    $_" }
    } else { Write-Ok 'setuperr.log is empty' }
} else { Write-Info 'No setuperr.log (usually good).' }

if (Test-Path -LiteralPath $actLog) {
    $tail = @(Get-Content -LiteralPath $actLog -Tail 40 -ErrorAction SilentlyContinue)
    if ($tail | Select-String -SimpleMatch 'Sysprep_Generalize' -Quiet) { Write-Ok 'Generalize entries present in setupact.log' }
    if ($tail | Select-String -Pattern 'Sysprep failed|fatal|0x8' -Quiet) {
        Write-Bad 'setupact.log tail contains failure indicators:'
        $tail | Select-String -Pattern 'Sysprep failed|fatal|0x8' | Select-Object -First 5 |
            ForEach-Object { Write-Info "    $($_.Line.Trim())" }
        $verifyFailed += 'sysprep log shows failure'
    }
} else { Write-Warn 'setupact.log not found - was sysprep actually run?' }

# generalize sets this; its absence means the image was booted after sysprep
$imageStateFile = Join-Path $osRoot 'Windows\Setup\State\State.ini'
if (Test-Path -LiteralPath $imageStateFile) {
    Write-Info ('Image state: ' + ((Get-Content -LiteralPath $imageStateFile) -join ' '))
}

# -- 2c. answer file staged ----------------------------------------------------
Write-Host "`n-- Answer file --" -ForegroundColor White
$pantherUnattend = Join-Path $osRoot 'Windows\Panther\unattend.xml'
if (Test-Path -LiteralPath $pantherUnattend) {
    Write-Ok 'Windows\Panther\unattend.xml is staged for first boot'
    try {
        $x = New-Object System.Xml.XmlDocument
        $x.Load($pantherUnattend)
        $passes = @($x.unattend.settings | ForEach-Object { $_.pass })
        Write-Info "  passes: $($passes -join ', ')"
        if ($passes -notcontains 'oobeSystem') { Write-Warn '  no oobeSystem pass - the deployed machine will show full OOBE.' }
        if ($x.OuterXml -match '<Value>[^<]*</Value>' -and $x.OuterXml -match 'PlainText>true') {
            Write-Warn '  contains a plaintext password value.'
        }
    } catch { Write-Warn "  could not parse: $($_.Exception.Message)" }
} else {
    if ($RequireUnattendStaged) {
        Write-Bad 'Windows\Panther\unattend.xml missing - sysprep was run without /unattend, so your OOBE settings will not apply.'
        $verifyFailed += 'unattend.xml not staged'
    } else { Write-Warn 'unattend.xml not staged.' }
}

# -- 2d. leftover scratch ------------------------------------------------------
Write-Host "`n-- Leftover build folders --" -ForegroundColor White
$found = $false
foreach ($f in $MustBeAbsent) {
    $p = Join-Path $osRoot $f
    if (Test-Path -LiteralPath $p) {
        $sz = [Math]::Round((Get-ChildItem $p -Recurse -File -ErrorAction SilentlyContinue |
               Measure-Object Length -Sum).Sum / 1GB, 2)
        Write-Warn "$f still present (~$sz GB) - this bloats every FFU. Delete before capture."
        $found = $true
    }
}
if (-not $found) { Write-Ok 'No leftover driver cache/scratch folders' }

# -- 2e. summary ---------------------------------------------------------------
Write-Host ''
Write-Host ('='*70) -ForegroundColor White
if ($verifyFailed.Count -gt 0) {
    Write-Bad ('VERIFICATION PROBLEMS: ' + ($verifyFailed -join '; '))
    Write-Host '  Capturing now would produce a broken image. Recommend aborting,' -ForegroundColor Red
    Write-Host '  fixing the unattend, and re-syspreping from a clean pre-sysprep VHDX.' -ForegroundColor Red
} else {
    Write-Ok 'All checks passed - safe to capture'
}
Write-Host ('='*70) -ForegroundColor White

#--- 3. PAUSE ------------------------------------------------------------------
if ($PauseForReview) {
    Write-Host ''
    Write-Host 'Review the output above.' -ForegroundColor Cyan
    Write-Host ("Windows volume is mounted at $osRoot if you want to browse it in another window.") -ForegroundColor Gray
    Write-Host 'Press ENTER to capture the FFU, or type Q then ENTER to abort: ' -ForegroundColor Yellow -NoNewline
    $answer = Read-Host
    if ($answer -match '^[Qq]') { throw 'Aborted by user at review prompt.' }
} elseif ($verifyFailed.Count -gt 0) {
    throw 'Verification failed and $PauseForReview is off - refusing to capture.'
}

#--- 4. CAPTURE (remount read-only) --------------------------------------------
Write-Step 'CAPTURE FFU'
Write-Info 'Dismounting, then remounting READ-ONLY so the host cannot dirty the image...'
Dismount-Safe -Path $VhdxPath
$script:Mounted = $null

Start-Sleep -Seconds 2
$disk = Mount-VHD -Path $VhdxPath -ReadOnly -Passthru | Get-Disk
$script:Mounted = $VhdxPath
$physicalDrive  = "\\.\PhysicalDrive$($disk.Number)"
Write-Ok "Mounted read-only as $physicalDrive"

Write-Info "Capturing to $ffuFile  (compress: $Compress)"
Write-Info 'This typically takes 10-40 minutes. DISM progress follows.'
$sw = [Diagnostics.Stopwatch]::StartNew()

& $DismPath /Capture-FFU `
    "/ImageFile:$ffuFile" `
    "/CaptureDrive:$physicalDrive" `
    "/Name:$ImageName" `
    "/Description:$ImageDescription" `
    "/Compress:$Compress"

$dismExit = $LASTEXITCODE
$sw.Stop()

if ($dismExit -ne 0 -or -not (Test-Path -LiteralPath $ffuFile)) {
    throw "DISM /Capture-FFU failed with exit code $dismExit. See C:\Windows\Logs\DISM\dism.log"
}

$ffuGB = [Math]::Round((Get-Item -LiteralPath $ffuFile).Length/1GB, 2)
Write-Ok ('Captured {0} GB in {1:hh\:mm\:ss}' -f $ffuGB, $sw.Elapsed)

#--- 5. OPTIONAL OPTIMIZE ------------------------------------------------------
if ($OptimizeFfu) {
    Write-Step 'OPTIMIZE FFU'
    Write-Warn 'Optimize rewrites the FFU. Verify the result applies cleanly before trusting it.'
    & $DismPath /Optimize-FFU "/ImageFile:$ffuFile"
    if ($LASTEXITCODE -ne 0) { Write-Warn "Optimize returned $LASTEXITCODE - original FFU is still usable." }
    else { Write-Ok ('Optimized to {0} GB' -f [Math]::Round((Get-Item -LiteralPath $ffuFile).Length/1GB,2)) }
}

#--- 6. REPORT -----------------------------------------------------------------
Write-Step 'IMAGE INFO'
& $DismPath /Get-ImageInfo "/ImageFile:$ffuFile"

$sidecar = [IO.Path]::ChangeExtension($ffuFile, 'json')
[pscustomobject]@{
    CapturedUtc        = (Get-Date).ToUniversalTime().ToString('s') + 'Z'
    FfuFile            = $ffuFile
    FfuSizeGB          = $ffuGB
    ImageName          = $ImageName
    Description        = $ImageDescription
    Compression        = $Compress
    Optimized          = [bool]$OptimizeFfu
    SourceVhdx         = $VhdxPath
    SourceVMName       = $VMName
    SourceDiskSizeGB   = [Math]::Round($vhdInfo.Size/1GB,1)
    MinimumTargetDiskGB= [Math]::Round($vhdInfo.Size/1GB,0)
    DriverPackages     = $driverCount
    UnattendStaged     = (Test-Path -LiteralPath $pantherUnattend)
    CaptureMinutes     = [Math]::Round($sw.Elapsed.TotalMinutes,1)
} | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $sidecar -Encoding UTF8

Write-Host ''
Write-Ok "FFU:      $ffuFile"
Write-Ok "Manifest: $sidecar"
Write-Host ''
Write-Host 'Apply with (from WinPE on the target):' -ForegroundColor Cyan
Write-Host ("  DISM /Apply-FFU /ImageFile:{0} /ApplyDrive:\\.\PhysicalDrive0" -f (Split-Path $ffuFile -Leaf)) -ForegroundColor Gray
Write-Host ''
Write-Warn 'If targets have Intel VMD/RST enabled, inject the storage driver into your WinPE boot.wim or WinPE will not see the SSD.'

}
catch {
    Write-Host ''
    Write-Bad $_.Exception.Message
    if ($_.ScriptStackTrace) { Write-Info ($_.ScriptStackTrace -split "`n" | Select-Object -First 3) }
    exit 1
}
finally {
    Write-Host ''
    Dismount-Safe -Path $script:Mounted
}
