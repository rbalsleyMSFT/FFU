Set-Location 'C:\claude\FFUBuilder\FFUDevelopment'
$modulePath = Join-Path $PWD 'Modules'
$env:PSModulePath = "$modulePath;$($env:PSModulePath)"

Write-Host "Testing FFU.Hypervisor module with VMware provider..." -ForegroundColor Cyan

try {
    Import-Module FFU.Hypervisor -Force -ErrorAction Stop
    Write-Host "[PASS] Module imported successfully!" -ForegroundColor Green

    $commands = Get-Command -Module FFU.Hypervisor
    Write-Host "[INFO] Exported commands: $($commands.Count)" -ForegroundColor Cyan

    Write-Host "`nTesting Get-AvailableHypervisors..." -ForegroundColor Cyan
    $hypervisors = Get-AvailableHypervisors
    foreach ($hv in $hypervisors) {
        $status = if ($hv.Available) { "[Available]" } else { "[Not Available]" }
        $color = if ($hv.Available) { 'Green' } else { 'Yellow' }
        Write-Host "  $status $($hv.DisplayName) v$($hv.Version)" -ForegroundColor $color
    }

    Write-Host "`nTesting VMware provider creation..." -ForegroundColor Cyan
    $provider = Get-HypervisorProvider -Type 'VMware'
    Write-Host "[PASS] VMware provider created: $($provider.Name) v$($provider.Version)" -ForegroundColor Green

    Write-Host "`nVMware provider capabilities:" -ForegroundColor Cyan
    Write-Host "  SupportsTPM: $($provider.Capabilities.SupportsTPM)"
    Write-Host "  SupportsSecureBoot: $($provider.Capabilities.SupportsSecureBoot)"
    Write-Host "  SupportedDiskFormats: $($provider.Capabilities.SupportedDiskFormats -join ', ')"

    Write-Host "`n=== All tests passed! ===" -ForegroundColor Green
    exit 0
} catch {
    Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
    exit 1
}
