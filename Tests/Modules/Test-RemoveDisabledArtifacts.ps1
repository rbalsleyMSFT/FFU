# Quick test for Remove-DisabledArtifacts function

$ModulePath = "$PSScriptRoot\Modules"
$env:PSModulePath = "$ModulePath;$env:PSModulePath"

Write-Host "Loading modules..." -ForegroundColor Cyan
Import-Module FFU.Core -Force -WarningAction SilentlyContinue
Import-Module FFU.Apps -Force -WarningAction SilentlyContinue

Write-Host "`nChecking if Remove-DisabledArtifacts exists..." -ForegroundColor Cyan
$cmd = Get-Command Remove-DisabledArtifacts -ErrorAction SilentlyContinue

if ($cmd) {
    Write-Host "[PASS] Remove-DisabledArtifacts found in module: $($cmd.Source)" -ForegroundColor Green
    Write-Host "`nFunction details:" -ForegroundColor White
    Get-Help Remove-DisabledArtifacts -Detailed
    exit 0
} else {
    Write-Host "[FAIL] Remove-DisabledArtifacts not found!" -ForegroundColor Red
    Write-Host "`nAvailable FFU.Apps functions:" -ForegroundColor Yellow
    Get-Command -Module FFU.Apps
    exit 1
}
