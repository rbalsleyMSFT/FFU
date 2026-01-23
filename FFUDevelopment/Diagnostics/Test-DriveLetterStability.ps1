#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Diagnostic script to test drive letter stability during VHD/VHDX operations.

.DESCRIPTION
    This script simulates the unattend file copy workflow to diagnose drive letter
    stability issues. It mounts a VHD/VHDX, assigns a drive letter, performs a
    volume flush (fsutil), and checks if the drive letter is lost.

    This helps diagnose the issue where fsutil volume flush causes Windows to
    release the drive letter on file-backed virtual disks.

.PARAMETER VhdxPath
    Path to the VHD or VHDX file to test. The file must exist and contain partitions.

.PARAMETER TestIterations
    Number of times to repeat the flush test to check for intermittent issues.
    Default: 5

.EXAMPLE
    .\Test-DriveLetterStability.ps1 -VhdxPath "D:\FFU\YOURFFU.vhdx" -TestIterations 10

.NOTES
    Created for debugging issue: os-partition-drive-letter-lost
    This script requires Administrator privileges.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ })]
    [string]$VhdxPath,

    [Parameter(Mandatory = $false)]
    [int]$TestIterations = 5
)

$ErrorActionPreference = 'Stop'

function Write-DiagLog {
    param([string]$Message, [string]$Level = 'INFO')
    $timestamp = [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss.fff')
    $color = switch ($Level) {
        'ERROR'   { 'Red' }
        'WARNING' { 'Yellow' }
        'SUCCESS' { 'Green' }
        'DEBUG'   { 'Cyan' }
        default   { 'White' }
    }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function Get-PartitionDriveLetterState {
    param($Disk)

    $result = @()
    $disk | Get-Partition | ForEach-Object {
        $result += [PSCustomObject]@{
            PartitionNumber = $_.PartitionNumber
            GptType         = $_.GptType
            DriveLetter     = $_.DriveLetter
            AccessPaths     = ($_.AccessPaths -join '; ')
            Size            = [math]::Round($_.Size / 1GB, 2)
        }
    }
    return $result
}

# ============================================================================
# MAIN DIAGNOSTIC SCRIPT
# ============================================================================

Write-DiagLog "=== Drive Letter Stability Diagnostic ==="
Write-DiagLog "VHD/VHDX Path: $VhdxPath"
Write-DiagLog "Test Iterations: $TestIterations"
Write-DiagLog ""

# Determine mount method
$isVhd = $VhdxPath -like "*.vhd" -and $VhdxPath -notlike "*.vhdx"
$mountMethod = if ($isVhd) { "diskpart" } else { "Mount-VHD" }
Write-DiagLog "File type: $(if ($isVhd) { 'VHD' } else { 'VHDX' })"
Write-DiagLog "Mount method: $mountMethod"
Write-DiagLog ""

# Check if already mounted
Write-DiagLog "Checking for existing mount..."
$existingMount = $null

if ($isVhd) {
    $existingMount = Get-Disk | Where-Object {
        $_.BusType -eq 'File Backed Virtual' -and $_.Location -eq $VhdxPath
    }
}
else {
    $existingMount = Get-VHD -Path $VhdxPath -ErrorAction SilentlyContinue
    if ($existingMount -and $existingMount.Attached) {
        $existingMount = Get-Disk -Number $existingMount.DiskNumber
    }
    else {
        $existingMount = $null
    }
}

if ($existingMount) {
    Write-DiagLog "Disk is already mounted at Disk $($existingMount.Number)" -Level 'WARNING'
    $disk = $existingMount
}
else {
    Write-DiagLog "Mounting disk..."
    if ($isVhd) {
        $diskpartScript = @"
select vdisk file="$VhdxPath"
attach vdisk
"@
        $scriptPath = Join-Path $env:TEMP "diagdiskpart_$(Get-Random).txt"
        $diskpartScript | Out-File -FilePath $scriptPath -Encoding ASCII
        $process = Start-Process -FilePath 'diskpart.exe' -ArgumentList "/s `"$scriptPath`"" `
                                 -Wait -PassThru -NoNewWindow
        Remove-Item $scriptPath -Force -ErrorAction SilentlyContinue

        if ($process.ExitCode -ne 0) {
            Write-DiagLog "diskpart mount failed with exit code $($process.ExitCode)" -Level 'ERROR'
            exit 1
        }

        Start-Sleep -Seconds 3
        $disk = Get-Disk | Where-Object {
            $_.BusType -eq 'File Backed Virtual'
        } | Select-Object -First 1
    }
    else {
        $disk = Mount-VHD -Path $VhdxPath -Passthru | Get-Disk
    }

    Write-DiagLog "Disk mounted at Disk $($disk.Number)" -Level 'SUCCESS'
}

# Find OS partition
$osPartition = $disk | Get-Partition | Where-Object { $_.GptType -eq '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}' }

if (-not $osPartition) {
    Write-DiagLog "No OS partition found (GPT type {ebd0a0a2-b9e5-4433-87c0-68b6b72699c7})" -Level 'ERROR'
    exit 1
}

Write-DiagLog "Found OS partition: Partition $($osPartition.PartitionNumber)"
Write-DiagLog ""

# Ensure drive letter is assigned
$currentLetter = $osPartition.DriveLetter
if ([string]::IsNullOrWhiteSpace($currentLetter)) {
    Write-DiagLog "OS partition has no drive letter, assigning..."
    $usedLetters = (Get-Volume).DriveLetter
    $availableLetter = [char[]](90..68) | Where-Object { $_ -notin $usedLetters } | Select-Object -First 1
    $osPartition | Set-Partition -NewDriveLetter $availableLetter
    Start-Sleep -Milliseconds 500
    $osPartition = $disk | Get-Partition | Where-Object { $_.GptType -eq '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}' }
    $currentLetter = $osPartition.DriveLetter
    Write-DiagLog "Assigned drive letter: $currentLetter" -Level 'SUCCESS'
}
else {
    Write-DiagLog "Current drive letter: $currentLetter"
}

Write-DiagLog ""
Write-DiagLog "=== Starting Flush Stability Tests ==="
Write-DiagLog ""

$results = @()

for ($i = 1; $i -le $TestIterations; $i++) {
    Write-DiagLog "--- Iteration $i of $TestIterations ---"

    # Capture pre-flush state
    $preFlushState = Get-PartitionDriveLetterState -Disk $disk
    $preFlushLetter = ($preFlushState | Where-Object { $_.GptType -eq '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}' }).DriveLetter
    Write-DiagLog "  Pre-flush drive letter: '$preFlushLetter'" -Level 'DEBUG'

    # Perform fsutil volume flush
    $flushTarget = "$($preFlushLetter):"
    Write-DiagLog "  Executing: fsutil volume flush $flushTarget" -Level 'DEBUG'
    $flushOutput = & fsutil volume flush $flushTarget 2>&1

    # Brief pause
    Start-Sleep -Milliseconds 500

    # Capture post-flush state
    $postFlushState = Get-PartitionDriveLetterState -Disk $disk
    $postFlushLetter = ($postFlushState | Where-Object { $_.GptType -eq '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}' }).DriveLetter
    Write-DiagLog "  Post-flush drive letter: '$postFlushLetter'" -Level 'DEBUG'

    # Analyze result
    $letterLost = [string]::IsNullOrWhiteSpace($postFlushLetter)
    $letterChanged = $postFlushLetter -ne $preFlushLetter

    $status = if ($letterLost) {
        Write-DiagLog "  RESULT: Drive letter LOST!" -Level 'ERROR'
        'LOST'
    }
    elseif ($letterChanged) {
        Write-DiagLog "  RESULT: Drive letter CHANGED from '$preFlushLetter' to '$postFlushLetter'" -Level 'WARNING'
        'CHANGED'
    }
    else {
        Write-DiagLog "  RESULT: Drive letter STABLE" -Level 'SUCCESS'
        'STABLE'
    }

    $results += [PSCustomObject]@{
        Iteration       = $i
        PreFlushLetter  = $preFlushLetter
        PostFlushLetter = $postFlushLetter
        Status          = $status
        FlushOutput     = ($flushOutput -join ' ')
    }

    # If letter was lost, try to recover for next iteration
    if ($letterLost) {
        Write-DiagLog "  Recovering drive letter for next iteration..."
        $usedLetters = (Get-Volume).DriveLetter
        $availableLetter = [char[]](90..68) | Where-Object { $_ -notin $usedLetters } | Select-Object -First 1
        $osPartition = $disk | Get-Partition | Where-Object { $_.GptType -eq '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}' }
        $osPartition | Set-Partition -NewDriveLetter $availableLetter -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
    }

    Write-DiagLog ""
}

# Summary
Write-DiagLog "=== SUMMARY ==="
$lostCount = ($results | Where-Object { $_.Status -eq 'LOST' }).Count
$changedCount = ($results | Where-Object { $_.Status -eq 'CHANGED' }).Count
$stableCount = ($results | Where-Object { $_.Status -eq 'STABLE' }).Count

Write-DiagLog "Total iterations: $TestIterations"
Write-DiagLog "  - Stable:  $stableCount"
Write-DiagLog "  - Changed: $changedCount" -Level $(if ($changedCount -gt 0) { 'WARNING' } else { 'INFO' })
Write-DiagLog "  - Lost:    $lostCount" -Level $(if ($lostCount -gt 0) { 'ERROR' } else { 'INFO' })

if ($lostCount -gt 0) {
    Write-DiagLog ""
    Write-DiagLog "DIAGNOSIS: Drive letter instability detected!" -Level 'ERROR'
    Write-DiagLog "The fsutil volume flush command is causing the drive letter to be released."
    Write-DiagLog "This is the root cause of the 'os-partition-drive-letter-lost' issue."
    Write-DiagLog ""
    Write-DiagLog "Recommendation: Apply the fix in BuildFFUVM.ps1 that re-acquires the drive letter after fsutil flush."
}
else {
    Write-DiagLog ""
    Write-DiagLog "DIAGNOSIS: Drive letter appears stable on this system." -Level 'SUCCESS'
    Write-DiagLog "The issue may be intermittent or specific to certain VHD configurations."
}

# Output detailed results
Write-DiagLog ""
Write-DiagLog "Detailed results:"
$results | Format-Table -AutoSize

# Cleanup prompt
Write-DiagLog ""
$dismount = Read-Host "Dismount the disk? (Y/N)"
if ($dismount -eq 'Y') {
    Write-DiagLog "Dismounting disk..."
    if ($isVhd) {
        $diskpartScript = @"
select vdisk file="$VhdxPath"
detach vdisk
"@
        $scriptPath = Join-Path $env:TEMP "diagdiskpart_detach_$(Get-Random).txt"
        $diskpartScript | Out-File -FilePath $scriptPath -Encoding ASCII
        Start-Process -FilePath 'diskpart.exe' -ArgumentList "/s `"$scriptPath`"" -Wait -NoNewWindow
        Remove-Item $scriptPath -Force -ErrorAction SilentlyContinue
    }
    else {
        Dismount-VHD -Path $VhdxPath
    }
    Write-DiagLog "Disk dismounted." -Level 'SUCCESS'
}

Write-DiagLog ""
Write-DiagLog "=== Diagnostic Complete ==="
