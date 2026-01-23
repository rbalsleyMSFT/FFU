# Test script to explore vmnet0 bridge configuration options

Write-Host "=== VMnet0 Bridge Configuration Test ===" -ForegroundColor Cyan

# Check current vmnet0 configuration
$vmnet0Path = 'HKLM:\SOFTWARE\WOW6432Node\VMware, Inc.\VMnetLib\VMnetConfig\vmnet0'
Write-Host "`n--- Current vmnet0 Registry ---" -ForegroundColor Yellow
Get-ItemProperty -Path $vmnet0Path -EA SilentlyContinue | Format-List *

# Check if there's a BridgedAdapter or similar key
$possibleKeys = @(
    'BridgedAdapter',
    'Bridge',
    'Adapter',
    'PhysicalAdapter',
    'HostAdapter'
)

foreach ($key in $possibleKeys) {
    $keyPath = Join-Path $vmnet0Path $key
    if (Test-Path $keyPath) {
        Write-Host "Found subkey: $key" -ForegroundColor Green
        Get-ItemProperty -Path $keyPath -EA SilentlyContinue | Format-List *
    }
}

# Look for any vmnet0 related entries elsewhere
Write-Host "`n--- Searching for vmnet0 bridge settings ---" -ForegroundColor Yellow

# Check VMnetLib base
$vmnetLibPath = 'HKLM:\SOFTWARE\WOW6432Node\VMware, Inc.\VMnetLib'
$vmnetLibProps = Get-ItemProperty -Path $vmnetLibPath -EA SilentlyContinue
if ($vmnetLibProps) {
    Write-Host "VMnetLib base properties:" -ForegroundColor Gray
    $vmnetLibProps.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object {
        Write-Host "  $($_.Name): $($_.Value)"
    }
}

# Check if there's a global bridge settings location
$globalPaths = @(
    'HKLM:\SOFTWARE\WOW6432Node\VMware, Inc.\VMnetLib\BridgeSettings',
    'HKLM:\SOFTWARE\WOW6432Node\VMware, Inc.\VMnetLib\Bridges',
    'HKLM:\SOFTWARE\WOW6432Node\VMware, Inc.\VMware Workstation\Network'
)

foreach ($path in $globalPaths) {
    if (Test-Path $path) {
        Write-Host "Found: $path" -ForegroundColor Green
        Get-ItemProperty -Path $path -EA SilentlyContinue | Format-List *
    }
}

# Get the active network adapter that should be used for bridging
Write-Host "`n--- Recommended Bridge Adapter ---" -ForegroundColor Yellow
$gatewayConfigs = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null }
$excludePatterns = @('*PANGP*', '*GlobalProtect*', '*Palo Alto*', '*VPN*')

foreach ($config in $gatewayConfigs) {
    $adapter = Get-NetAdapter -InterfaceAlias $config.InterfaceAlias -ErrorAction SilentlyContinue
    if (-not $adapter) { continue }

    $isExcluded = $false
    foreach ($pattern in $excludePatterns) {
        if ($adapter.InterfaceDescription -like $pattern -or $adapter.Name -like $pattern) {
            $isExcluded = $true
            break
        }
    }

    if (-not $isExcluded) {
        # Test connectivity
        $testResult = Test-NetConnection -ComputerName "8.8.8.8" -WarningAction SilentlyContinue
        if ($testResult.PingSucceeded) {
            Write-Host "Active adapter with internet:" -ForegroundColor Green
            Write-Host "  Name: $($adapter.Name)"
            Write-Host "  Description: $($adapter.InterfaceDescription)"
            Write-Host "  GUID: $($adapter.InterfaceGuid)"
            Write-Host "  MAC: $($adapter.MacAddress)"
            break
        }
    }
}

# Check VMware Workstation preferences for network settings
Write-Host "`n--- VMware Workstation Config Files ---" -ForegroundColor Yellow
$configFiles = @(
    "C:\ProgramData\VMware\VMware Workstation\config.ini",
    "C:\ProgramData\VMware\VMware Workstation\settings.ini",
    "C:\ProgramData\VMware\netmap.conf"
)

foreach ($file in $configFiles) {
    if (Test-Path $file) {
        Write-Host "`n$file :" -ForegroundColor Cyan
        Get-Content $file
    } else {
        Write-Host "$file : Not found" -ForegroundColor DarkYellow
    }
}
