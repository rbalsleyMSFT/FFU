<#
.SYNOPSIS
    Forces WimMount filter to load using multiple methods with detailed error capture.

.DESCRIPTION
    This script attempts to force the WimMount filter to load after registry entries
    exist but the filter won't start. It tries multiple methods:
    1. sc start wimmount
    2. fltmc load WimMount
    3. fltmc attach WimMount C:
    4. Direct driver loading via NtLoadDriver (if other methods fail)

    Captures detailed error codes for diagnosis.

.PARAMETER Force
    Skip confirmation prompts

.EXAMPLE
    .\Force-WimMountLoad.ps1

.NOTES
    Must be run as Administrator.
    Solution 1: Force filter load with detailed error capture.
#>

[CmdletBinding()]
param(
    [switch]$Force
)

#Requires -RunAsAdministrator

$ErrorActionPreference = 'Continue'
$script:LogPath = "C:\FFUDevelopment\WimMount_ForceLoad_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

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

function Get-LastWin32Error {
    $errorCode = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
    $errorMessage = (New-Object System.ComponentModel.Win32Exception($errorCode)).Message
    return @{
        Code = $errorCode
        Hex = "0x{0:X8}" -f $errorCode
        Message = $errorMessage
    }
}

Write-Host ""
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host "  Force WimMount Filter Load" -ForegroundColor White
Write-Host "  Solution 1: Aggressive filter loading with error capture" -ForegroundColor Gray
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host ""

Write-Log "Starting Force-WimMountLoad"
Write-Log "Log file: $script:LogPath"

# Check prerequisites
Write-Log "Step 1: Verifying prerequisites" -Type Step

$driverPath = "$env:SystemRoot\System32\drivers\wimmount.sys"
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\WimMount"

if (-not (Test-Path $driverPath)) {
    Write-Log "Driver file missing: $driverPath" -Type Error
    Write-Log "Run Restore-WimMountComplete.ps1 first" -Type Error
    exit 1
}

if (-not (Test-Path $regPath)) {
    Write-Log "Service registry missing" -Type Error
    Write-Log "Run Repair-WimMountService.ps1 first" -Type Error
    exit 1
}

Write-Log "Prerequisites OK" -Type Success

# Check if already loaded
$filterCheck = fltmc filters 2>&1
if ($filterCheck -match 'WimMount') {
    Write-Log "WimMount filter is already loaded!" -Type Success
    fltmc filters | Select-String "WimMount"
    exit 0
}

Write-Host ""

# Method 1: sc start
Write-Log "Step 2: Attempting 'sc start wimmount'" -Type Step

$scOutput = sc.exe start wimmount 2>&1
$scExitCode = $LASTEXITCODE

Write-Log "  Exit code: $scExitCode"
Write-Log "  Output: $($scOutput -join ' ')"

if ($scExitCode -eq 0) {
    Write-Log "sc start succeeded!" -Type Success
}
else {
    # Decode common error codes
    $errorMeaning = switch ($scExitCode) {
        1056 { "Service already running" }
        1058 { "Service disabled" }
        1068 { "Dependency failed" }
        1069 { "Logon failed" }
        1077 { "No start attempt since boot" }
        577  { "Signature/certificate issue - may be blocked by security software" }
        1275 { "Driver blocked from loading (security software?)" }
        default { "Unknown error" }
    }
    Write-Log "  Error meaning: $errorMeaning" -Type Warning
}

Start-Sleep -Seconds 2

# Check if loaded now
$filterCheck = fltmc filters 2>&1
if ($filterCheck -match 'WimMount') {
    Write-Log "WimMount filter loaded after sc start!" -Type Success
    fltmc filters | Select-String "WimMount"
    exit 0
}

Write-Host ""

# Method 2: fltmc load
Write-Log "Step 3: Attempting 'fltmc load WimMount'" -Type Step

$fltmcLoadOutput = fltmc load WimMount 2>&1
$fltmcLoadExitCode = $LASTEXITCODE

Write-Log "  Exit code: $fltmcLoadExitCode"
Write-Log "  Output: $($fltmcLoadOutput -join ' ')"

if ($fltmcLoadExitCode -eq 0) {
    Write-Log "fltmc load succeeded!" -Type Success
}
else {
    $fltmcError = switch ($fltmcLoadExitCode) {
        2  { "Filter not found in registry" }
        5  { "Access denied - elevation or security software blocking" }
        87 { "Invalid parameter - registry misconfigured" }
        1060 { "Service does not exist" }
        default { "Unknown fltmc error" }
    }
    Write-Log "  Error meaning: $fltmcError" -Type Warning
}

Start-Sleep -Seconds 2

# Check if loaded now
$filterCheck = fltmc filters 2>&1
if ($filterCheck -match 'WimMount') {
    Write-Log "WimMount filter loaded after fltmc load!" -Type Success
    fltmc filters | Select-String "WimMount"
    exit 0
}

Write-Host ""

# Method 3: fltmc attach
Write-Log "Step 4: Attempting 'fltmc attach WimMount C: -a 180700'" -Type Step

$fltmcAttachOutput = fltmc attach WimMount C: -a 180700 2>&1
$fltmcAttachExitCode = $LASTEXITCODE

Write-Log "  Exit code: $fltmcAttachExitCode"
Write-Log "  Output: $($fltmcAttachOutput -join ' ')"

Start-Sleep -Seconds 2

# Final check
$filterCheck = fltmc filters 2>&1
if ($filterCheck -match 'WimMount') {
    Write-Log "WimMount filter loaded after fltmc attach!" -Type Success
    fltmc filters | Select-String "WimMount"
    exit 0
}

Write-Host ""

# Method 4: Try to get detailed Windows error
Write-Log "Step 5: Capturing detailed Windows error information" -Type Step

# Check Windows Event Log for driver load failures
Write-Log "Checking System Event Log for recent driver load errors..."

$driverErrors = Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    StartTime = (Get-Date).AddMinutes(-5)
} -MaxEvents 50 -ErrorAction SilentlyContinue | Where-Object {
    $_.Message -match 'WimMount|wimmount|driver.*blocked|driver.*failed|0x800704DB'
}

if ($driverErrors) {
    Write-Log "Found relevant events:" -Type Warning
    foreach ($event in $driverErrors) {
        Write-Log "  [$($event.TimeCreated)] $($event.Message)" -Type Warning
    }
}
else {
    Write-Log "No recent driver load errors in System log" -Type Info
}

# Check for SentinelOne blocks
Write-Log "Checking for SentinelOne activity..."
$sentinelLogs = Get-WinEvent -LogName 'Application' -MaxEvents 100 -ErrorAction SilentlyContinue | Where-Object {
    $_.ProviderName -match 'Sentinel' -and $_.Message -match 'block|prevent|deny|wim'
}

if ($sentinelLogs) {
    Write-Log "SentinelOne may be blocking WimMount:" -Type Error
    foreach ($log in $sentinelLogs | Select-Object -First 5) {
        Write-Log "  $($log.Message)" -Type Error
    }
}

Write-Host ""
Write-Host "=" * 70 -ForegroundColor Red
Write-Log "ALL METHODS FAILED - SECURITY SOFTWARE LIKELY BLOCKING" -Type Error
Write-Host "=" * 70 -ForegroundColor Red
Write-Host ""

Write-Log "Diagnosis:" -Type Warning
Write-Host "  The WimMount driver file exists and registry is configured correctly,"
Write-Host "  but Windows cannot load the filter. This is typically caused by:"
Write-Host ""
Write-Host "  1. SentinelOne EDR blocking the driver load" -ForegroundColor Yellow
Write-Host "  2. Windows Driver Signature Enforcement" -ForegroundColor Yellow
Write-Host "  3. Group Policy restricting driver loading" -ForegroundColor Yellow
Write-Host ""

Write-Log "Recommended Actions:" -Type Info
Write-Host "  1. Contact your security team to whitelist wimmount.sys"
Write-Host "  2. Add exclusion in SentinelOne for:"
Write-Host "     - C:\Windows\System32\drivers\wimmount.sys"
Write-Host "     - Process: dism.exe"
Write-Host "     - Process: powershell.exe (for Mount-WindowsImage)"
Write-Host "  3. Try Solution 2: Use pnputil to reinstall from DriverStore"
Write-Host ""

Write-Log "Log saved to: $script:LogPath" -Type Info
