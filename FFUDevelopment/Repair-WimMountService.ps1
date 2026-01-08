<#
.SYNOPSIS
    Repairs the WimMount service by re-registering it from the existing driver file.

.DESCRIPTION
    This script repairs the WimMount minifilter service when the driver file exists
    but the service registration is missing (causing error 0x800704DB).

    It performs the following:
    1. Verifies the wimmount.sys driver file exists
    2. Creates the required registry entries for the WimMount service
    3. Creates the filter instance registration
    4. Loads the WimMount filter into the Filter Manager
    5. Verifies the repair was successful

.PARAMETER Force
    Skip confirmation prompts

.EXAMPLE
    .\Repair-WimMountService.ps1

.EXAMPLE
    .\Repair-WimMountService.ps1 -Force

.NOTES
    Must be run as Administrator.
    Solution 1: Quick fix for missing WimMount service registration.
#>

[CmdletBinding()]
param(
    [switch]$Force
)

#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

function Write-Status {
    param([string]$Message, [string]$Type = 'Info')
    $colors = @{
        'Info' = 'Cyan'
        'Success' = 'Green'
        'Warning' = 'Yellow'
        'Error' = 'Red'
    }
    $prefix = @{
        'Info' = '[*]'
        'Success' = '[+]'
        'Warning' = '[!]'
        'Error' = '[-]'
    }
    Write-Host "$($prefix[$Type]) $Message" -ForegroundColor $colors[$Type]
}

Write-Host ""
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "  WimMount Service Repair Script" -ForegroundColor White
Write-Host "  Solution 1: Manual Service Re-Registration" -ForegroundColor Gray
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host ""

# Step 1: Verify driver file exists
Write-Status "Checking for wimmount.sys driver file..."
$driverPath = "$env:SystemRoot\System32\drivers\wimmount.sys"

if (-not (Test-Path $driverPath)) {
    Write-Status "Driver file not found at: $driverPath" -Type Error
    Write-Status "This solution requires the driver file to exist." -Type Error
    Write-Status "Use Solution 2 (DISM RestoreHealth) instead." -Type Warning
    exit 1
}

$driverFile = Get-Item $driverPath
Write-Status "Driver file found: $driverPath" -Type Success
Write-Status "  Version: $($driverFile.VersionInfo.FileVersion)"
Write-Status "  Size: $($driverFile.Length) bytes"

# Step 2: Check current state
Write-Status "Checking current WimMount service state..."
$serviceExists = $null -ne (Get-Service -Name 'WimMount' -ErrorAction SilentlyContinue)
$regExists = Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\WimMount"
$filterLoaded = (fltmc filters 2>&1) -match 'WimMount'

Write-Status "  Service registered: $serviceExists"
Write-Status "  Registry exists: $regExists"
Write-Status "  Filter loaded: $filterLoaded"

if ($serviceExists -and $regExists -and $filterLoaded) {
    Write-Status "WimMount appears to be properly configured!" -Type Success
    Write-Status "If you're still seeing errors, try Solution 2 (DISM RestoreHealth)." -Type Warning
    exit 0
}

# Step 3: Confirmation
if (-not $Force) {
    Write-Host ""
    Write-Status "This script will:" -Type Warning
    Write-Host "  1. Create WimMount service registry entries"
    Write-Host "  2. Create filter instance configuration"
    Write-Host "  3. Load the WimMount filter"
    Write-Host ""
    $confirm = Read-Host "Continue? (Y/N)"
    if ($confirm -notmatch '^[Yy]') {
        Write-Status "Operation cancelled." -Type Warning
        exit 0
    }
}

# Step 4: Create the WimMount service registry entries
Write-Status "Creating WimMount service registry entries..."

$serviceRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\WimMount"
$instancesPath = "$serviceRegPath\Instances"
$defaultInstancePath = "$instancesPath\WimMount"

try {
    # Create main service key
    if (-not (Test-Path $serviceRegPath)) {
        New-Item -Path $serviceRegPath -Force | Out-Null
    }

    # Set service properties
    Set-ItemProperty -Path $serviceRegPath -Name "Type" -Value 2 -Type DWord              # FILE_SYSTEM_DRIVER
    Set-ItemProperty -Path $serviceRegPath -Name "Start" -Value 3 -Type DWord             # DEMAND_START (Manual)
    Set-ItemProperty -Path $serviceRegPath -Name "ErrorControl" -Value 1 -Type DWord      # NORMAL
    Set-ItemProperty -Path $serviceRegPath -Name "ImagePath" -Value "system32\drivers\wimmount.sys" -Type ExpandString
    Set-ItemProperty -Path $serviceRegPath -Name "DisplayName" -Value "WIMMount" -Type String
    Set-ItemProperty -Path $serviceRegPath -Name "Description" -Value "@%SystemRoot%\system32\drivers\wimmount.sys,-102" -Type ExpandString
    Set-ItemProperty -Path $serviceRegPath -Name "Group" -Value "FSFilter Infrastructure" -Type String
    Set-ItemProperty -Path $serviceRegPath -Name "Tag" -Value 1 -Type DWord
    Set-ItemProperty -Path $serviceRegPath -Name "SupportedFeatures" -Value 3 -Type DWord
    Set-ItemProperty -Path $serviceRegPath -Name "DebugFlags" -Value 0 -Type DWord

    Write-Status "Service registry entries created" -Type Success

    # Create Instances key
    if (-not (Test-Path $instancesPath)) {
        New-Item -Path $instancesPath -Force | Out-Null
    }
    Set-ItemProperty -Path $instancesPath -Name "DefaultInstance" -Value "WimMount" -Type String

    # Create default instance
    if (-not (Test-Path $defaultInstancePath)) {
        New-Item -Path $defaultInstancePath -Force | Out-Null
    }
    Set-ItemProperty -Path $defaultInstancePath -Name "Altitude" -Value "180700" -Type String
    Set-ItemProperty -Path $defaultInstancePath -Name "Flags" -Value 0 -Type DWord

    Write-Status "Filter instance configuration created" -Type Success
}
catch {
    Write-Status "Failed to create registry entries: $($_.Exception.Message)" -Type Error
    exit 1
}

# Step 5: Load the filter
Write-Status "Loading WimMount filter..."

try {
    # First try to start the service
    $startResult = sc.exe start wimmount 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Status "WimMount service started successfully" -Type Success
    }
    else {
        # Try loading via fltmc
        $loadResult = fltmc load WimMount 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Status "WimMount filter loaded via fltmc" -Type Success
        }
        else {
            Write-Status "Could not load filter automatically. A reboot may be required." -Type Warning
        }
    }
}
catch {
    Write-Status "Filter load attempt completed with warnings" -Type Warning
}

# Step 6: Verify the repair
Write-Status "Verifying repair..."

Start-Sleep -Seconds 2

$filterCheck = fltmc filters 2>&1
$wimMountLoaded = $filterCheck -match 'WimMount'

if ($wimMountLoaded) {
    Write-Host ""
    Write-Status "=" * 50 -Type Success
    Write-Status "WimMount filter is now loaded!" -Type Success
    Write-Status "=" * 50 -Type Success
    Write-Host ""

    # Show the filter entry
    $filterCheck | Select-String -Pattern "WimMount" | ForEach-Object {
        Write-Host "  $_" -ForegroundColor Green
    }

    Write-Host ""
    Write-Status "You can now retry your WIM mount operation." -Type Info
}
else {
    Write-Host ""
    Write-Status "Registry entries created, but filter not yet loaded." -Type Warning
    Write-Status "A system REBOOT is required to complete the repair." -Type Warning
    Write-Host ""

    if (-not $Force) {
        $reboot = Read-Host "Reboot now? (Y/N)"
        if ($reboot -match '^[Yy]') {
            Write-Status "Rebooting in 10 seconds..." -Type Warning
            shutdown /r /t 10 /c "WimMount service repair - reboot required"
        }
    }
}

Write-Host ""
Write-Status "If issues persist after reboot, run Solution 2 (DISM RestoreHealth)" -Type Info
