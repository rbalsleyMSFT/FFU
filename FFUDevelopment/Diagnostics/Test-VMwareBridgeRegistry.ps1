# Test script to examine VMware Bridge registry configuration
# Goal: Understand how VMware stores bridge adapter bindings

Write-Host "=== VMware Bridge Protocol Registry Analysis ===" -ForegroundColor Cyan

# Get VMnetBridge Linkage
$linkagePath = 'HKLM:\SYSTEM\CurrentControlSet\Services\VMnetBridge\Linkage'
$linkage = Get-ItemProperty -Path $linkagePath -ErrorAction SilentlyContinue

if (-not $linkage) {
    Write-Host "VMnetBridge Linkage not found - VMware may not be installed" -ForegroundColor Red
    exit
}

Write-Host "`n--- Linkage Bind Values ---" -ForegroundColor Yellow
$bindGuids = @()
foreach ($bind in $linkage.Bind) {
    $guid = $bind -replace '\\Device\\', '' -replace '[{}]', ''
    $bindGuids += $guid
    Write-Host "  $bind"
}

Write-Host "`n--- Correlating GUIDs to Network Adapters ---" -ForegroundColor Yellow

# Network adapter class GUID
$adapterClassPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}"

foreach ($guid in $bindGuids) {
    # Find the adapter with this NetCfgInstanceId
    $adapterKeys = Get-ChildItem $adapterClassPath -ErrorAction SilentlyContinue
    $found = $false

    foreach ($key in $adapterKeys) {
        $props = Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue
        if ($props.NetCfgInstanceId -eq "{$guid}") {
            Write-Host "`nGUID: {$guid}" -ForegroundColor White
            Write-Host "  Driver Description: $($props.DriverDesc)" -ForegroundColor Green
            Write-Host "  Device Instance ID: $($props.DeviceInstanceID)"
            $found = $true
            break
        }
    }

    if (-not $found) {
        Write-Host "`nGUID: {$guid}" -ForegroundColor White
        Write-Host "  (Could not find matching adapter)" -ForegroundColor DarkYellow
    }
}

# Check for VMware network configuration files
Write-Host "`n--- VMware Configuration Files ---" -ForegroundColor Yellow

$vmwareDataPath = "C:\ProgramData\VMware"
if (Test-Path $vmwareDataPath) {
    Get-ChildItem $vmwareDataPath -File | ForEach-Object {
        Write-Host "  $($_.Name) - $($_.Length) bytes"
    }
}

# Check for netmap.conf specifically
$netmapPath = Join-Path $vmwareDataPath "netmap.conf"
if (Test-Path $netmapPath) {
    Write-Host "`n--- netmap.conf Contents ---" -ForegroundColor Yellow
    Get-Content $netmapPath
} else {
    Write-Host "`n  netmap.conf does not exist yet" -ForegroundColor DarkYellow
    Write-Host "  (Created when Virtual Network Editor is first opened)" -ForegroundColor DarkYellow
}

# Check VMware preferences
Write-Host "`n--- Looking for VMware Preferences ---" -ForegroundColor Yellow
$prefsLocations = @(
    "$env:APPDATA\VMware\preferences.ini",
    "$env:LOCALAPPDATA\VMware\preferences.ini",
    "C:\ProgramData\VMware\VMware Workstation\config.ini"
)

foreach ($loc in $prefsLocations) {
    if (Test-Path $loc) {
        Write-Host "`nFound: $loc" -ForegroundColor Green
        Get-Content $loc | Select-Object -First 30
    }
}

# Get all network adapters for reference
Write-Host "`n--- All Network Adapters (for reference) ---" -ForegroundColor Yellow
Get-NetAdapter | Select-Object Name, InterfaceDescription, InterfaceGuid, Status | Format-Table -AutoSize
