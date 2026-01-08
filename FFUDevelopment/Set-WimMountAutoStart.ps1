<#
.SYNOPSIS
    Configures WimMount to auto-start at system boot.

.DESCRIPTION
    This script changes the WimMount service start type from Manual (3) to System (1)
    so it loads automatically during the boot process. This resolves issues where
    WimMount can be loaded manually but doesn't persist after reboot.

    The script also immediately starts the service if not already running.

.PARAMETER StartType
    The start type to set:
    - System (1): Loads during kernel initialization (earliest, most reliable)
    - Auto (2): Loads during system startup
    - Manual (3): Loads on demand (default Windows behavior)

.PARAMETER Force
    Skip confirmation prompts

.EXAMPLE
    .\Set-WimMountAutoStart.ps1
    Sets WimMount to System start type (recommended)

.EXAMPLE
    .\Set-WimMountAutoStart.ps1 -StartType Auto
    Sets WimMount to Automatic start type

.EXAMPLE
    .\Set-WimMountAutoStart.ps1 -StartType Manual
    Reverts WimMount to Manual start type (original Windows default)

.NOTES
    Must be run as Administrator.
    This is the recommended solution when manual 'sc start wimmount' works but
    the filter doesn't persist after reboot.
#>

[CmdletBinding()]
param(
    [ValidateSet('System', 'Auto', 'Manual')]
    [string]$StartType = 'System',

    [switch]$Force
)

#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

function Write-Status {
    param([string]$Message, [string]$Type = 'Info')
    $colors = @{
        'Info' = 'Cyan'; 'Success' = 'Green'; 'Warning' = 'Yellow'; 'Error' = 'Red'; 'Step' = 'White'
    }
    $prefix = @{
        'Info' = '[*]'; 'Success' = '[+]'; 'Warning' = '[!]'; 'Error' = '[-]'; 'Step' = '[>]'
    }
    Write-Host "$($prefix[$Type]) $Message" -ForegroundColor $colors[$Type]
}

Write-Host ""
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "  WimMount Auto-Start Configuration" -ForegroundColor White
Write-Host "  Solution: Ensure WimMount loads at boot" -ForegroundColor Gray
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host ""

# Map start type names to values
$startTypeValues = @{
    'System' = 1    # SERVICE_SYSTEM_START - Loaded by kernel during boot
    'Auto'   = 2    # SERVICE_AUTO_START - Loaded by Service Control Manager
    'Manual' = 3    # SERVICE_DEMAND_START - Loaded on demand (default)
}

$targetStartValue = $startTypeValues[$StartType]

# Check prerequisites
Write-Status "Checking prerequisites..." -Type Step

$serviceRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\WimMount"
$driverPath = "$env:SystemRoot\System32\drivers\wimmount.sys"

if (-not (Test-Path $driverPath)) {
    Write-Status "Driver file not found: $driverPath" -Type Error
    Write-Status "Run Repair-WimMountService.ps1 first" -Type Error
    exit 1
}

if (-not (Test-Path $serviceRegPath)) {
    Write-Status "Service registry not found" -Type Error
    Write-Status "Run Repair-WimMountService.ps1 first" -Type Error
    exit 1
}

Write-Status "Driver file exists: $driverPath" -Type Success
Write-Status "Service registry exists" -Type Success

# Get current start type
$currentStart = Get-ItemProperty -Path $serviceRegPath -Name "Start" -ErrorAction SilentlyContinue
$currentStartValue = $currentStart.Start

$startTypeNames = @{
    0 = 'Boot'
    1 = 'System'
    2 = 'Auto'
    3 = 'Manual'
    4 = 'Disabled'
}

Write-Host ""
Write-Status "Current start type: $($startTypeNames[$currentStartValue]) ($currentStartValue)"
Write-Status "Target start type:  $StartType ($targetStartValue)"

if ($currentStartValue -eq $targetStartValue) {
    Write-Status "WimMount is already set to $StartType start" -Type Success

    # Still check if it's running
    $filterCheck = fltmc filters 2>&1
    if ($filterCheck -match 'WimMount') {
        Write-Status "WimMount filter is currently loaded" -Type Success
        exit 0
    }
    else {
        Write-Status "WimMount is configured correctly but not currently loaded" -Type Warning
        Write-Status "Attempting to start the service..." -Type Info
    }
}
else {
    # Confirmation
    if (-not $Force) {
        Write-Host ""
        Write-Status "This will change WimMount service start type:" -Type Warning
        Write-Host "  From: $($startTypeNames[$currentStartValue]) ($currentStartValue)"
        Write-Host "  To:   $StartType ($targetStartValue)"
        Write-Host ""

        if ($StartType -eq 'System') {
            Write-Host "  Note: 'System' start type means the driver loads during" -ForegroundColor Yellow
            Write-Host "        kernel initialization, before most other drivers." -ForegroundColor Yellow
            Write-Host "        This is the most reliable option for ensuring" -ForegroundColor Yellow
            Write-Host "        WimMount is available for DISM operations." -ForegroundColor Yellow
        }

        Write-Host ""
        $confirm = Read-Host "Continue? (Y/N)"
        if ($confirm -notmatch '^[Yy]') {
            Write-Status "Operation cancelled" -Type Warning
            exit 0
        }
    }

    Write-Host ""
    Write-Status "Updating WimMount start type to $StartType ($targetStartValue)..." -Type Step

    try {
        Set-ItemProperty -Path $serviceRegPath -Name "Start" -Value $targetStartValue -Type DWord
        Write-Status "Registry updated successfully" -Type Success
    }
    catch {
        Write-Status "Failed to update registry: $($_.Exception.Message)" -Type Error
        exit 1
    }
}

# Verify the change
$newStart = Get-ItemProperty -Path $serviceRegPath -Name "Start" -ErrorAction SilentlyContinue
if ($newStart.Start -eq $targetStartValue) {
    Write-Status "Verified: Start type is now $StartType ($targetStartValue)" -Type Success
}
else {
    Write-Status "Warning: Start type verification failed" -Type Warning
}

Write-Host ""

# Start the service now if not running
Write-Status "Checking if WimMount is currently loaded..." -Type Step

$filterCheck = fltmc filters 2>&1
if ($filterCheck -match 'WimMount') {
    Write-Status "WimMount filter is already loaded" -Type Success
}
else {
    Write-Status "WimMount not loaded - starting service now..." -Type Info

    $scResult = sc.exe start wimmount 2>&1
    $scExitCode = $LASTEXITCODE

    if ($scExitCode -eq 0) {
        Write-Status "Service started successfully" -Type Success
    }
    elseif ($scExitCode -eq 1056) {
        Write-Status "Service was already running" -Type Success
    }
    else {
        Write-Status "sc start returned: $scExitCode" -Type Warning
        Write-Status "Output: $($scResult -join ' ')" -Type Warning

        # Try fltmc load as fallback
        Write-Status "Trying fltmc load as fallback..." -Type Info
        $fltmcResult = fltmc load WimMount 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Status "Filter loaded via fltmc" -Type Success
        }
        else {
            Write-Status "Filter load may require a reboot" -Type Warning
        }
    }

    # Final verification
    Start-Sleep -Seconds 2
    $filterCheck = fltmc filters 2>&1
    if ($filterCheck -match 'WimMount') {
        Write-Status "WimMount filter is now loaded!" -Type Success
        fltmc filters | Select-String "WimMount"
    }
}

Write-Host ""
Write-Host "=" * 60 -ForegroundColor Green
Write-Status "Configuration complete!" -Type Success
Write-Host "=" * 60 -ForegroundColor Green
Write-Host ""

Write-Status "Summary:" -Type Info
Write-Host "  - WimMount start type: $StartType ($targetStartValue)"
Write-Host "  - The filter will now load automatically at boot"
Write-Host "  - No reboot is required if the filter is currently loaded"
Write-Host ""

if ($StartType -eq 'System') {
    Write-Status "Recommendation: Test WIM operations now to verify functionality" -Type Info
    Write-Host ""
    Write-Host "  Test command:" -ForegroundColor Yellow
    Write-Host "  Mount-WindowsImage -Path C:\Mount -ImagePath <path-to-wim> -Index 1" -ForegroundColor White
    Write-Host ""
}

Write-Status "If issues persist after reboot, run Get-WimMountDiagnostics.ps1 again" -Type Info
