# Test script for network adapter detection
# Goal: Find active adapter with internet connectivity, excluding GlobalProtect VPN

Write-Host "=== Network Adapter Analysis ===" -ForegroundColor Cyan

# Step 1: Get all network adapters that are 'Up'
Write-Host "`n--- Step 1: All Up Adapters ---" -ForegroundColor Yellow
$upAdapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
$upAdapters | Select-Object Name, InterfaceDescription, Status, MacAddress, LinkSpeed | Format-Table -AutoSize

# Step 2: Get adapters with default gateway (connected to network)
Write-Host "`n--- Step 2: Adapters with Default Gateway ---" -ForegroundColor Yellow
$gatewayConfigs = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null }
$gatewayConfigs | ForEach-Object {
    [PSCustomObject]@{
        InterfaceAlias = $_.InterfaceAlias
        InterfaceDescription = $_.InterfaceDescription
        IPv4Address = ($_.IPv4Address | Select-Object -First 1).IPAddress
        Gateway = ($_.IPv4DefaultGateway | Select-Object -First 1).NextHop
    }
} | Format-Table -AutoSize

# Step 3: Identify GlobalProtect/PANGP adapters to exclude
Write-Host "`n--- Step 3: Identifying Adapters to Exclude ---" -ForegroundColor Yellow
$excludePatterns = @(
    '*PANGP*',
    '*GlobalProtect*',
    '*Palo Alto*',
    '*VPN*'
)

$allAdapters = Get-NetAdapter
$excludedAdapters = $allAdapters | Where-Object {
    $desc = $_.InterfaceDescription
    $name = $_.Name
    foreach ($pattern in $excludePatterns) {
        if ($desc -like $pattern -or $name -like $pattern) {
            return $true
        }
    }
    return $false
}

if ($excludedAdapters) {
    Write-Host "Adapters that would be EXCLUDED:" -ForegroundColor Red
    $excludedAdapters | Select-Object Name, InterfaceDescription, Status | Format-Table -AutoSize
} else {
    Write-Host "No VPN/GlobalProtect adapters found to exclude" -ForegroundColor Green
}

# Step 4: Find the best adapter for bridging
Write-Host "`n--- Step 4: Best Adapter for Bridging ---" -ForegroundColor Yellow

# Get adapter with internet connectivity (has default gateway and can reach the internet)
$bestAdapter = $null

foreach ($config in $gatewayConfigs) {
    $adapter = Get-NetAdapter -InterfaceAlias $config.InterfaceAlias -ErrorAction SilentlyContinue

    if (-not $adapter) { continue }

    # Check if it's an excluded adapter
    $isExcluded = $false
    foreach ($pattern in $excludePatterns) {
        if ($adapter.InterfaceDescription -like $pattern -or $adapter.Name -like $pattern) {
            $isExcluded = $true
            Write-Host "  Skipping excluded adapter: $($adapter.InterfaceDescription)" -ForegroundColor DarkYellow
            break
        }
    }

    if ($isExcluded) { continue }

    # Test internet connectivity through this adapter
    Write-Host "  Testing connectivity on: $($adapter.InterfaceDescription)" -ForegroundColor Gray

    # Get the source IP for this adapter
    $sourceIP = ($config.IPv4Address | Select-Object -First 1).IPAddress

    # Test connectivity to a reliable endpoint
    $testResult = Test-NetConnection -ComputerName "8.8.8.8" -WarningAction SilentlyContinue

    if ($testResult.PingSucceeded) {
        Write-Host "  Internet connectivity confirmed via: $($adapter.InterfaceDescription)" -ForegroundColor Green
        $bestAdapter = $adapter
        break
    } else {
        Write-Host "  No internet via: $($adapter.InterfaceDescription)" -ForegroundColor DarkYellow
    }
}

if ($bestAdapter) {
    Write-Host "`n=== RECOMMENDED ADAPTER FOR BRIDGING ===" -ForegroundColor Green
    Write-Host "Name: $($bestAdapter.Name)" -ForegroundColor White
    Write-Host "Description: $($bestAdapter.InterfaceDescription)" -ForegroundColor White
    Write-Host "MAC: $($bestAdapter.MacAddress)" -ForegroundColor White
    Write-Host "Link Speed: $($bestAdapter.LinkSpeed)" -ForegroundColor White
} else {
    Write-Host "`n=== NO SUITABLE ADAPTER FOUND ===" -ForegroundColor Red
    Write-Host "Could not find an adapter with internet connectivity" -ForegroundColor Red
}

# Step 5: Show what VMware would need
Write-Host "`n--- Step 5: VMware Configuration Info ---" -ForegroundColor Yellow
if ($bestAdapter) {
    Write-Host "VMware Virtual Network Editor settings:"
    Write-Host "  VMnet0 -> Bridge to: $($bestAdapter.InterfaceDescription)"
    Write-Host ""
    Write-Host "Adapters to EXCLUDE from auto-bridging:"
    foreach ($pattern in $excludePatterns) {
        $matching = $allAdapters | Where-Object { $_.InterfaceDescription -like $pattern -or $_.Name -like $pattern }
        foreach ($m in $matching) {
            Write-Host "  - $($m.InterfaceDescription)"
        }
    }
}
