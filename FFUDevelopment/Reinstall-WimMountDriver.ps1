<#
.SYNOPSIS
    Reinstalls the WimMount driver from DriverStore using pnputil.

.DESCRIPTION
    This script attempts to reinstall the WimMount driver when the registry exists
    but the filter won't load. It uses pnputil to:
    1. Find the WimMount driver package in the DriverStore
    2. Delete the existing driver package
    3. Re-add the driver from the original Windows installation
    4. Force installation and loading

    This approach bypasses potential security software caching issues by
    triggering a fresh driver installation through the PnP subsystem.

.PARAMETER Force
    Skip confirmation prompts

.EXAMPLE
    .\Reinstall-WimMountDriver.ps1

.NOTES
    Must be run as Administrator.
    Solution 2: PnP-based driver reinstallation.
#>

[CmdletBinding()]
param(
    [switch]$Force
)

#Requires -RunAsAdministrator

$ErrorActionPreference = 'Continue'
$script:LogPath = "C:\FFUDevelopment\WimMount_Reinstall_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Write-Log {
    param([string]$Message, [string]$Type = 'Info')
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] [$Type] $Message"
    Add-Content -Path $script:LogPath -Value $logEntry -ErrorAction SilentlyContinue

    $colors = @{
        'Info' = 'Cyan'; 'Success' = 'Green'; 'Warning' = 'Yellow'; 'Error' = 'Red'; 'Step' = 'White'
    }
    $prefix = @{
        'Info' = '[*]'; 'Success' = '[+]'; 'Warning' = '[!]'; 'Error' = '[-]'; 'Step' = '[>]'
    }
    Write-Host "$($prefix[$Type]) $Message" -ForegroundColor $colors[$Type]
}

Write-Host ""
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host "  WimMount Driver Reinstall via PnPUtil" -ForegroundColor White
Write-Host "  Solution 2: Fresh driver installation through PnP subsystem" -ForegroundColor Gray
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host ""

Write-Log "Starting WimMount driver reinstall"
Write-Log "Log file: $script:LogPath"

# Check if already working
$filterCheck = fltmc filters 2>&1
if ($filterCheck -match 'WimMount') {
    Write-Log "WimMount filter is already loaded!" -Type Success
    fltmc filters | Select-String "WimMount"
    exit 0
}

Write-Host ""

# Step 1: Check for wimmount.sys in DriverStore
Write-Log "Step 1: Searching for WimMount in DriverStore" -Type Step

$driverStoreInf = $null
$pnpDrivers = pnputil /enum-drivers 2>&1

# Parse pnputil output to find wimmount
$currentDriver = $null
$drivers = @()

foreach ($line in $pnpDrivers) {
    if ($line -match 'Published Name\s*:\s*(.+\.inf)') {
        $currentDriver = @{
            PublishedName = $matches[1].Trim()
        }
    }
    elseif ($line -match 'Original Name\s*:\s*(.+)') {
        if ($currentDriver) {
            $currentDriver.OriginalName = $matches[1].Trim()
        }
    }
    elseif ($line -match 'Provider Name\s*:\s*(.+)') {
        if ($currentDriver) {
            $currentDriver.Provider = $matches[1].Trim()
        }
    }
    elseif ($line -match 'Class Name\s*:\s*(.+)') {
        if ($currentDriver) {
            $currentDriver.ClassName = $matches[1].Trim()
        }
    }
    elseif ($line -match 'Class GUID\s*:\s*(.+)') {
        if ($currentDriver) {
            $currentDriver.ClassGUID = $matches[1].Trim()
        }
    }
    elseif ($line -match 'Driver Version\s*:\s*(.+)') {
        if ($currentDriver) {
            $currentDriver.Version = $matches[1].Trim()
            $drivers += [PSCustomObject]$currentDriver
            $currentDriver = $null
        }
    }
}

# Look for wimmount.inf or similar
$wimDriver = $drivers | Where-Object {
    $_.OriginalName -match 'wim' -or
    $_.PublishedName -match 'wim' -or
    $_.Provider -match 'Microsoft' -and $_.ClassName -match 'System'
}

Write-Log "Found $($drivers.Count) total drivers in DriverStore"

# Also check directly in the DriverStore folder
$driverStorePath = "$env:SystemRoot\System32\DriverStore\FileRepository"
$wimInfFolders = Get-ChildItem -Path $driverStorePath -Directory -Filter "*wim*" -ErrorAction SilentlyContinue

if ($wimInfFolders) {
    Write-Log "Found WIM-related driver folders in DriverStore:" -Type Success
    foreach ($folder in $wimInfFolders) {
        Write-Log "  - $($folder.Name)"
        $infFiles = Get-ChildItem -Path $folder.FullName -Filter "*.inf" -ErrorAction SilentlyContinue
        foreach ($inf in $infFiles) {
            Write-Log "    INF: $($inf.Name)"
            $driverStoreInf = $inf.FullName
        }
    }
}
else {
    Write-Log "No WIM-specific driver folders found in DriverStore" -Type Warning
}

Write-Host ""

# Step 2: Check for wimmount.inf in Windows INF folder
Write-Log "Step 2: Checking Windows INF folder" -Type Step

$windowsInfPath = "$env:SystemRoot\INF"
$wimMountInf = Get-ChildItem -Path $windowsInfPath -Filter "*wim*.inf" -ErrorAction SilentlyContinue

if ($wimMountInf) {
    Write-Log "Found WIM INF files:" -Type Success
    foreach ($inf in $wimMountInf) {
        Write-Log "  - $($inf.FullName)"
        # Check content to verify it's for wimmount
        $content = Get-Content $inf.FullName -Raw -ErrorAction SilentlyContinue
        if ($content -match 'wimmount') {
            Write-Log "    Contains wimmount references - this is our target INF"
            $driverStoreInf = $inf.FullName
        }
    }
}
else {
    Write-Log "No WIM INF files found in $windowsInfPath" -Type Warning
}

Write-Host ""

# Step 3: Try to extract wimmount.inf from Windows image
Write-Log "Step 3: Attempting to restore wimmount.inf from Windows component store" -Type Step

# Try SFC to repair wimmount specifically
Write-Log "Running targeted SFC repair..."
$sfcResult = sfc /VERIFYONLY /FILE=C:\Windows\System32\drivers\wimmount.sys 2>&1
Write-Log "SFC result: $($sfcResult -join ' ')"

Write-Host ""

# Step 4: Try pnputil to add/install the driver
Write-Log "Step 4: Attempting driver installation via pnputil" -Type Step

if ($driverStoreInf -and (Test-Path $driverStoreInf)) {
    Write-Log "Using INF file: $driverStoreInf"

    # Try to install the driver
    Write-Log "Running: pnputil /add-driver `"$driverStoreInf`" /install"
    $pnpAddResult = pnputil /add-driver "$driverStoreInf" /install 2>&1
    $pnpExitCode = $LASTEXITCODE

    Write-Log "Exit code: $pnpExitCode"
    Write-Log "Output: $($pnpAddResult -join ' ')"

    if ($pnpExitCode -eq 0) {
        Write-Log "Driver installation succeeded!" -Type Success
    }
    else {
        Write-Log "Driver installation returned code: $pnpExitCode" -Type Warning
    }
}
else {
    Write-Log "No INF file found to install - trying alternative methods" -Type Warning
}

Write-Host ""

# Step 5: Try to manually create and install an INF
Write-Log "Step 5: Creating custom WimMount INF for installation" -Type Step

$customInfPath = "$env:TEMP\wimmount_repair.inf"
$customInfContent = @"
; WimMount Driver INF for repair installation
[Version]
Signature   = "`$CHICAGO`$"
Class       = System
ClassGuid   = {4D36E97D-E325-11CE-BFC1-08002BE10318}
Provider    = %MSFT%
DriverVer   = 06/21/2006,10.0.22621.1
CatalogFile = wimmount.cat

[DestinationDirs]
DefaultDestDir = 12

[DefaultInstall.NTamd64]
CopyFiles = WimMount.CopyFiles

[DefaultInstall.NTamd64.Services]
AddService = WimMount,0x00000002,WimMount.Service

[WimMount.CopyFiles]
wimmount.sys,,,0x00004000

[WimMount.Service]
DisplayName    = %WimMount.SvcDesc%
ServiceType    = 2
StartType      = 3
ErrorControl   = 1
ServiceBinary  = %12%\wimmount.sys
LoadOrderGroup = FSFilter Infrastructure

[SourceDisksNames]
1 = %DiskName%,,,

[SourceDisksFiles]
wimmount.sys = 1

[Strings]
MSFT = "Microsoft Corporation"
WimMount.SvcDesc = "WIMMount"
DiskName = "WimMount Driver Disk"
"@

try {
    $customInfContent | Out-File -FilePath $customInfPath -Encoding ASCII -Force
    Write-Log "Created custom INF at: $customInfPath" -Type Success

    # Try to install using the custom INF
    Write-Log "Attempting installation with custom INF..."
    $installResult = pnputil /add-driver "$customInfPath" /install 2>&1
    Write-Log "Result: $($installResult -join ' ')"
}
catch {
    Write-Log "Failed to create/use custom INF: $($_.Exception.Message)" -Type Warning
}

Write-Host ""

# Step 6: Try rundll32 method (used by Windows internally)
Write-Log "Step 6: Attempting rundll32 installation method" -Type Step

$driverSysPath = "$env:SystemRoot\System32\drivers\wimmount.sys"
if (Test-Path $driverSysPath) {
    Write-Log "Driver file exists, attempting rundll32 installation..."

    try {
        # This method is sometimes used by Windows for driver installation
        $rundllCmd = "rundll32.exe setupapi.dll,InstallHinfSection DefaultInstall 128 $customInfPath"
        Write-Log "Running: $rundllCmd"

        $process = Start-Process -FilePath "rundll32.exe" `
            -ArgumentList "setupapi.dll,InstallHinfSection DefaultInstall 128 $customInfPath" `
            -Wait -PassThru -NoNewWindow -ErrorAction SilentlyContinue

        Write-Log "rundll32 completed with exit code: $($process.ExitCode)"
    }
    catch {
        Write-Log "rundll32 method failed: $($_.Exception.Message)" -Type Warning
    }
}

Write-Host ""

# Step 7: Try to load the filter after installation attempts
Write-Log "Step 7: Attempting to load WimMount filter" -Type Step

# First try sc start
$scResult = sc.exe start wimmount 2>&1
$scExitCode = $LASTEXITCODE
Write-Log "sc start wimmount: Exit=$scExitCode, Output=$($scResult -join ' ')"

Start-Sleep -Seconds 2

# Then try fltmc load
$fltmcResult = fltmc load WimMount 2>&1
$fltmcExitCode = $LASTEXITCODE
Write-Log "fltmc load WimMount: Exit=$fltmcExitCode, Output=$($fltmcResult -join ' ')"

Start-Sleep -Seconds 2

# Final check
$filterCheck = fltmc filters 2>&1
if ($filterCheck -match 'WimMount') {
    Write-Host ""
    Write-Host "=" * 70 -ForegroundColor Green
    Write-Log "SUCCESS: WimMount filter is now loaded!" -Type Success
    Write-Host "=" * 70 -ForegroundColor Green
    Write-Host ""
    fltmc filters | Select-String "WimMount"
    exit 0
}

Write-Host ""

# Step 8: If still not working, try DISM component repair
Write-Log "Step 8: Running targeted DISM component repair" -Type Step

Write-Log "Running: DISM /Online /Cleanup-Image /CheckHealth"
$dismCheck = dism /Online /Cleanup-Image /CheckHealth 2>&1
Write-Log "CheckHealth result: $($dismCheck -join ' ')"

Write-Log "Running: DISM /Online /Cleanup-Image /ScanHealth"
$dismScan = dism /Online /Cleanup-Image /ScanHealth 2>&1
Write-Log "ScanHealth result: $($dismScan[-5..-1] -join ' ')"

# Try to repair just the specific component
Write-Log "Attempting targeted component restoration..."
$componentName = "Microsoft-Windows-WIM-FS-Filter"
$dismRestore = dism /Online /Cleanup-Image /RestoreHealth /LimitAccess 2>&1
Write-Log "RestoreHealth result: $($dismRestore[-10..-1] -join ' ')"

Write-Host ""

# Final verification
Write-Log "Final verification..." -Type Step
Start-Sleep -Seconds 3

# Try loading one more time after DISM
$scFinal = sc.exe start wimmount 2>&1
$fltmcFinal = fltmc load WimMount 2>&1

$finalCheck = fltmc filters 2>&1
if ($finalCheck -match 'WimMount') {
    Write-Host ""
    Write-Host "=" * 70 -ForegroundColor Green
    Write-Log "SUCCESS: WimMount filter loaded after DISM repair!" -Type Success
    Write-Host "=" * 70 -ForegroundColor Green
    exit 0
}

Write-Host ""
Write-Host "=" * 70 -ForegroundColor Red
Write-Log "REINSTALLATION METHODS EXHAUSTED" -Type Error
Write-Host "=" * 70 -ForegroundColor Red
Write-Host ""

Write-Log "All PnP-based reinstallation methods have been tried." -Type Warning
Write-Log "The driver file exists but Windows cannot load it." -Type Warning
Write-Host ""

Write-Log "Likely causes:" -Type Info
Write-Host "  1. SentinelOne EDR is actively blocking the driver load"
Write-Host "  2. Driver signature verification is failing"
Write-Host "  3. Group Policy restricts minifilter driver loading"
Write-Host ""

Write-Log "Recommended next steps:" -Type Info
Write-Host "  1. Contact security team to whitelist wimmount.sys"
Write-Host "  2. Check Windows Event Viewer > System for driver load errors"
Write-Host "  3. Try booting into Safe Mode and running this script"
Write-Host "  4. Consider Windows in-place upgrade (repair install)"
Write-Host ""

Write-Log "Log saved to: $script:LogPath" -Type Info

# Clean up temp INF
if (Test-Path $customInfPath) {
    Remove-Item $customInfPath -Force -ErrorAction SilentlyContinue
}
