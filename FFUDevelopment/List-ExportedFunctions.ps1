# List all exported functions from all modules
$modulePath = Join-Path $PSScriptRoot "Modules"
$env:PSModulePath = "$modulePath;$env:PSModulePath"

# Import modules in dependency order
Import-Module FFU.Core -Force -Global -WarningAction SilentlyContinue
Import-Module FFU.ADK -Force -Global -WarningAction SilentlyContinue
Import-Module FFU.VM -Force -Global -WarningAction SilentlyContinue
Import-Module FFU.Drivers -Force -Global -WarningAction SilentlyContinue
Import-Module FFU.Apps -Force -Global -WarningAction SilentlyContinue
Import-Module FFU.Updates -Force -Global -WarningAction SilentlyContinue
Import-Module FFU.Imaging -Force -Global -WarningAction SilentlyContinue
Import-Module FFU.Media -Force -Global -WarningAction SilentlyContinue

# List functions from each module
@('FFU.Core', 'FFU.ADK', 'FFU.VM', 'FFU.Drivers', 'FFU.Apps', 'FFU.Updates', 'FFU.Imaging', 'FFU.Media') | ForEach-Object {
    Write-Host "`n=== $_ ===" -ForegroundColor Cyan
    Get-Command -Module $_ | Select-Object -ExpandProperty Name | Sort-Object
}
