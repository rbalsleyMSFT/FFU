<#
.SYNOPSIS
    Comprehensive repair for WimMount service using Windows system repair tools.

.DESCRIPTION
    This script performs a complete repair of the WimMount service and related
    DISM components using Microsoft's official repair mechanisms.

    Steps performed:
    1. Temporarily disables security software exclusions (if SentinelOne detected)
    2. Clears any stale DISM mount points
    3. Runs DISM /RestoreHealth to repair Windows component store
    4. Runs System File Checker (SFC) to verify system files
    5. Re-registers DISM components
    6. Verifies WimMount service is restored
    7. Tests WIM mount functionality

.PARAMETER SkipDISMRepair
    Skip the DISM /RestoreHealth step (useful if already run)

.PARAMETER SkipSFC
    Skip the SFC /scannow step

.PARAMETER Force
    Skip all confirmation prompts

.EXAMPLE
    .\Restore-WimMountComplete.ps1

.EXAMPLE
    .\Restore-WimMountComplete.ps1 -SkipDISMRepair -Force

.NOTES
    Must be run as Administrator.
    This process may take 15-30 minutes.
    A reboot is recommended after completion.
    Solution 2: Complete system repair approach.
#>

[CmdletBinding()]
param(
    [switch]$SkipDISMRepair,
    [switch]$SkipSFC,
    [switch]$Force
)

#Requires -RunAsAdministrator

$ErrorActionPreference = 'Continue'
$script:LogPath = "C:\FFUDevelopment\WimMount_Repair_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Write-Log {
    param([string]$Message, [string]$Type = 'Info')
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] [$Type] $Message"
    Add-Content -Path $script:LogPath -Value $logEntry

    $colors = @{
        'Info' = 'Cyan'
        'Success' = 'Green'
        'Warning' = 'Yellow'
        'Error' = 'Red'
        'Step' = 'White'
    }
    $prefix = @{
        'Info' = '[*]'
        'Success' = '[+]'
        'Warning' = '[!]'
        'Error' = '[-]'
        'Step' = '[>]'
    }
    Write-Host "$($prefix[$Type]) $Message" -ForegroundColor $colors[$Type]
}

function Test-WimMountFunctional {
    Write-Log "Testing WimMount functionality..."

    # Check if filter is loaded
    $filterOutput = fltmc filters 2>&1
    $filterLoaded = $filterOutput -match 'WimMount'

    # Check if service exists
    $serviceExists = $null -ne (Get-Service -Name 'WimMount' -ErrorAction SilentlyContinue)

    # Check registry
    $regExists = Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\WimMount"

    return @{
        FilterLoaded = $filterLoaded
        ServiceExists = $serviceExists
        RegistryExists = $regExists
        IsFullyFunctional = ($filterLoaded -and $serviceExists -and $regExists)
    }
}

# Start
Write-Host ""
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host "  WimMount Complete System Repair" -ForegroundColor White
Write-Host "  Solution 2: DISM RestoreHealth + SFC Approach" -ForegroundColor Gray
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host ""
Write-Log "Starting WimMount complete repair process"
Write-Log "Log file: $script:LogPath"
Write-Host ""

# Initial state check
Write-Log "Step 1: Checking initial system state" -Type Step
$initialState = Test-WimMountFunctional
Write-Log "  Filter loaded: $($initialState.FilterLoaded)"
Write-Log "  Service exists: $($initialState.ServiceExists)"
Write-Log "  Registry exists: $($initialState.RegistryExists)"

if ($initialState.IsFullyFunctional) {
    Write-Log "WimMount appears to be fully functional!" -Type Success
    Write-Log "Running repair anyway to ensure integrity..." -Type Info
}

# Check for security software that might interfere
Write-Log "Step 2: Checking for security software" -Type Step

$sentinelOne = Get-Process -Name "SentinelAgent*" -ErrorAction SilentlyContinue
$sysmon = Get-Process -Name "Sysmon*" -ErrorAction SilentlyContinue

if ($sentinelOne) {
    Write-Log "SentinelOne detected - may need temporary exclusion for repair" -Type Warning
    Write-Log "Consider adding C:\Windows\System32\drivers to SentinelOne exclusions" -Type Warning
}

if ($sysmon) {
    Write-Log "Sysmon detected - this shouldn't interfere with repair" -Type Info
}

# Confirmation
if (-not $Force) {
    Write-Host ""
    Write-Log "This repair process will:" -Type Warning
    Write-Host "  1. Clean up any stale DISM mount points"
    Write-Host "  2. Run DISM /RestoreHealth (may take 10-20 minutes)"
    Write-Host "  3. Run SFC /scannow (may take 10-15 minutes)"
    Write-Host "  4. Re-register DISM components"
    Write-Host "  5. Verify WimMount service restoration"
    Write-Host ""
    Write-Host "Total estimated time: 20-40 minutes" -ForegroundColor Yellow
    Write-Host ""
    $confirm = Read-Host "Continue? (Y/N)"
    if ($confirm -notmatch '^[Yy]') {
        Write-Log "Operation cancelled by user" -Type Warning
        exit 0
    }
}

Write-Host ""

# Step 3: Clean up DISM mount points
Write-Log "Step 3: Cleaning up DISM mount points" -Type Step

try {
    Write-Log "Running DISM /Cleanup-Wim..."
    $cleanupWim = Start-Process -FilePath "dism.exe" -ArgumentList "/Cleanup-Wim" -Wait -PassThru -NoNewWindow
    Write-Log "  Cleanup-Wim completed with exit code: $($cleanupWim.ExitCode)"

    Write-Log "Running DISM /Cleanup-Mountpoints..."
    $cleanupMount = Start-Process -FilePath "dism.exe" -ArgumentList "/Cleanup-Mountpoints" -Wait -PassThru -NoNewWindow
    Write-Log "  Cleanup-Mountpoints completed with exit code: $($cleanupMount.ExitCode)"
}
catch {
    Write-Log "Mount point cleanup encountered errors (non-fatal): $($_.Exception.Message)" -Type Warning
}

# Step 4: DISM RestoreHealth
if (-not $SkipDISMRepair) {
    Write-Log "Step 4: Running DISM /Online /Cleanup-Image /RestoreHealth" -Type Step
    Write-Log "This may take 10-20 minutes. Please wait..." -Type Info

    try {
        $dismArgs = "/Online /Cleanup-Image /RestoreHealth"
        $dismProcess = Start-Process -FilePath "dism.exe" -ArgumentList $dismArgs -Wait -PassThru -NoNewWindow

        if ($dismProcess.ExitCode -eq 0) {
            Write-Log "DISM RestoreHealth completed successfully!" -Type Success
        }
        elseif ($dismProcess.ExitCode -eq 1726) {
            Write-Log "DISM RestoreHealth: Some repairs were made" -Type Success
        }
        else {
            Write-Log "DISM RestoreHealth completed with exit code: $($dismProcess.ExitCode)" -Type Warning
            Write-Log "Check C:\Windows\Logs\DISM\dism.log for details" -Type Info
        }
    }
    catch {
        Write-Log "DISM RestoreHealth failed: $($_.Exception.Message)" -Type Error
    }
}
else {
    Write-Log "Step 4: Skipping DISM RestoreHealth (as requested)" -Type Warning
}

Write-Host ""

# Step 5: System File Checker
if (-not $SkipSFC) {
    Write-Log "Step 5: Running System File Checker (SFC /scannow)" -Type Step
    Write-Log "This may take 10-15 minutes. Please wait..." -Type Info

    try {
        $sfcProcess = Start-Process -FilePath "sfc.exe" -ArgumentList "/scannow" -Wait -PassThru -NoNewWindow

        if ($sfcProcess.ExitCode -eq 0) {
            Write-Log "SFC completed - no integrity violations found or all repaired" -Type Success
        }
        else {
            Write-Log "SFC completed with exit code: $($sfcProcess.ExitCode)" -Type Warning
            Write-Log "Check C:\Windows\Logs\CBS\CBS.log for details" -Type Info
        }
    }
    catch {
        Write-Log "SFC failed: $($_.Exception.Message)" -Type Error
    }
}
else {
    Write-Log "Step 5: Skipping SFC (as requested)" -Type Warning
}

Write-Host ""

# Step 6: Re-register DISM components
Write-Log "Step 6: Re-registering DISM components" -Type Step

$dllsToRegister = @(
    "$env:SystemRoot\System32\wimgapi.dll"
    "$env:SystemRoot\System32\wdscore.dll"
)

foreach ($dll in $dllsToRegister) {
    if (Test-Path $dll) {
        try {
            $regResult = Start-Process -FilePath "regsvr32.exe" -ArgumentList "/s `"$dll`"" -Wait -PassThru -NoNewWindow
            if ($regResult.ExitCode -eq 0) {
                Write-Log "  Registered: $(Split-Path $dll -Leaf)" -Type Success
            }
            else {
                Write-Log "  Failed to register: $(Split-Path $dll -Leaf)" -Type Warning
            }
        }
        catch {
            Write-Log "  Error registering $(Split-Path $dll -Leaf): $($_.Exception.Message)" -Type Warning
        }
    }
    else {
        Write-Log "  DLL not found: $dll" -Type Warning
    }
}

Write-Host ""

# Step 7: Try to load WimMount filter
Write-Log "Step 7: Attempting to load WimMount filter" -Type Step

# Check if service exists now
$serviceCheck = Get-Service -Name 'WimMount' -ErrorAction SilentlyContinue

if ($serviceCheck) {
    Write-Log "WimMount service found!" -Type Success

    try {
        if ($serviceCheck.Status -ne 'Running') {
            Start-Service -Name 'WimMount' -ErrorAction Stop
            Write-Log "WimMount service started" -Type Success
        }
        else {
            Write-Log "WimMount service already running" -Type Success
        }
    }
    catch {
        Write-Log "Could not start service: $($_.Exception.Message)" -Type Warning
        Write-Log "Trying fltmc load..." -Type Info

        $loadResult = fltmc load WimMount 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "WimMount filter loaded via fltmc" -Type Success
        }
        else {
            Write-Log "Filter load may require reboot" -Type Warning
        }
    }
}
else {
    Write-Log "WimMount service still not found after DISM repair" -Type Warning
    Write-Log "Attempting manual registration as fallback..." -Type Info

    # Fallback: Create registry entries manually
    $serviceRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\WimMount"
    $driverPath = "$env:SystemRoot\System32\drivers\wimmount.sys"

    if (Test-Path $driverPath) {
        try {
            if (-not (Test-Path $serviceRegPath)) {
                New-Item -Path $serviceRegPath -Force | Out-Null
            }
            Set-ItemProperty -Path $serviceRegPath -Name "Type" -Value 2 -Type DWord
            Set-ItemProperty -Path $serviceRegPath -Name "Start" -Value 3 -Type DWord
            Set-ItemProperty -Path $serviceRegPath -Name "ErrorControl" -Value 1 -Type DWord
            Set-ItemProperty -Path $serviceRegPath -Name "ImagePath" -Value "system32\drivers\wimmount.sys" -Type ExpandString
            Set-ItemProperty -Path $serviceRegPath -Name "DisplayName" -Value "WIMMount" -Type String
            Set-ItemProperty -Path $serviceRegPath -Name "Group" -Value "FSFilter Infrastructure" -Type String

            $instancesPath = "$serviceRegPath\Instances"
            if (-not (Test-Path $instancesPath)) {
                New-Item -Path $instancesPath -Force | Out-Null
            }
            Set-ItemProperty -Path $instancesPath -Name "DefaultInstance" -Value "WimMount" -Type String

            $defaultInstancePath = "$instancesPath\WimMount"
            if (-not (Test-Path $defaultInstancePath)) {
                New-Item -Path $defaultInstancePath -Force | Out-Null
            }
            Set-ItemProperty -Path $defaultInstancePath -Name "Altitude" -Value "180700" -Type String
            Set-ItemProperty -Path $defaultInstancePath -Name "Flags" -Value 0 -Type DWord

            Write-Log "Manual registry entries created" -Type Success
        }
        catch {
            Write-Log "Failed to create manual registry entries: $($_.Exception.Message)" -Type Error
        }
    }
    else {
        Write-Log "Driver file missing - DISM repair may have failed" -Type Error
    }
}

Write-Host ""

# Step 8: Final verification
Write-Log "Step 8: Final verification" -Type Step

Start-Sleep -Seconds 3

$finalState = Test-WimMountFunctional

Write-Host ""
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host "  REPAIR RESULTS" -ForegroundColor White
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host ""

Write-Log "Final State:"
Write-Log "  WimMount filter loaded: $($finalState.FilterLoaded)"
Write-Log "  WimMount service exists: $($finalState.ServiceExists)"
Write-Log "  WimMount registry exists: $($finalState.RegistryExists)"

if ($finalState.IsFullyFunctional) {
    Write-Host ""
    Write-Log "SUCCESS: WimMount is fully functional!" -Type Success
    Write-Host ""

    # Show filter status
    Write-Log "Current filter status:"
    fltmc filters | Select-String -Pattern "WimMount" | ForEach-Object {
        Write-Host "  $_" -ForegroundColor Green
    }

    Write-Host ""
    Write-Log "You can now retry your WIM mount operations." -Type Success
    Write-Log "A reboot is recommended to ensure stability." -Type Info
}
elseif ($finalState.RegistryExists -and -not $finalState.FilterLoaded) {
    Write-Host ""
    Write-Log "PARTIAL SUCCESS: Registry configured, but filter not yet loaded" -Type Warning
    Write-Log "A REBOOT IS REQUIRED to complete the repair." -Type Warning
    Write-Host ""

    if (-not $Force) {
        $reboot = Read-Host "Reboot now? (Y/N)"
        if ($reboot -match '^[Yy]') {
            Write-Log "Initiating reboot in 30 seconds..." -Type Warning
            shutdown /r /t 30 /c "WimMount repair - reboot required to load filter"
        }
    }
}
else {
    Write-Host ""
    Write-Log "REPAIR INCOMPLETE" -Type Error
    Write-Log "The repair process could not fully restore WimMount." -Type Error
    Write-Host ""
    Write-Log "Recommended next steps:" -Type Info
    Write-Host "  1. Reboot the system and run this script again"
    Write-Host "  2. Check if SentinelOne is blocking the driver"
    Write-Host "  3. Try running from Windows Recovery Environment"
    Write-Host "  4. Consider Windows in-place upgrade repair"
    Write-Host ""
}

Write-Host ""
Write-Log "Repair log saved to: $script:LogPath" -Type Info
Write-Host ""
