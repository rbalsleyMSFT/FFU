# Get VMware VMnet configuration from registry

Write-Host "=== VMware VMnet Configuration ===" -ForegroundColor Cyan

$basePath = 'HKLM:\SOFTWARE\WOW6432Node\VMware, Inc.\VMnetLib\VMnetConfig'

# Get all vmnet entries
$vmnets = Get-ChildItem -Path $basePath -ErrorAction SilentlyContinue

foreach ($vmnet in $vmnets) {
    $vmnetName = $vmnet.PSChildName
    Write-Host "`n=== $vmnetName ===" -ForegroundColor Yellow

    # Get main properties
    $props = Get-ItemProperty -Path $vmnet.PSPath -ErrorAction SilentlyContinue
    foreach ($prop in $props.PSObject.Properties) {
        if ($prop.Name -notlike 'PS*') {
            Write-Host "  $($prop.Name): $($prop.Value)"
        }
    }

    # Get subkeys
    $subkeys = Get-ChildItem -Path $vmnet.PSPath -ErrorAction SilentlyContinue
    foreach ($subkey in $subkeys) {
        Write-Host "  --- $($subkey.PSChildName) ---" -ForegroundColor Gray
        $subProps = Get-ItemProperty -Path $subkey.PSPath -ErrorAction SilentlyContinue
        foreach ($prop in $subProps.PSObject.Properties) {
            if ($prop.Name -notlike 'PS*') {
                Write-Host "    $($prop.Name): $($prop.Value)"
            }
        }
    }
}
