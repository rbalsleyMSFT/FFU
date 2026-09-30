#Requires -RunAsAdministrator
#Requires -Version 7

<#
.SYNOPSIS
    FFU Image Build Wrapper Script
.DESCRIPTION
    Wrapper for BuildFFUVM.ps1 to build a Windows FFU image for a specific device.
    Customize the variables in the CONFIGURATION block before running.
.NOTES
    Requires: BuildFFUVM.ps1 present in $FFURoot
    Run As:   Administrator
#>

# ==============================================================================
# CONFIGURATION — Edit these values before running
# ==============================================================================

$FFURoot = "C:\FFUDevelopment"           # Root path of your FFU development folder

# ── Device Info ────────────────────────────────────────────────────────────────
$Make     = "REPLACE_WITH_MANUFACTURER"  # e.g. "Dell", "HP", "Lenovo", "Microsoft"
$Model    = "REPLACE_WITH_FULL_MODEL"    # e.g. "Latitude 5550", "EliteBook 840 G11"
$FileName = "REPLACE_WITH_OUTPUT_NAME"  # Output FFU base name, no extension. e.g. "Latitude5550"

# ── Windows ────────────────────────────────────────────────────────────────────
$WindowsRelease = "11"    # "10" or "11"
$WindowsVersion = "24H2"  # e.g. "23H2", "24H2"

# ── Office ─────────────────────────────────────────────────────────────────────
$InstallOffice      = $false
$OfficeConfigXML    = "$FFURoot\Apps\Office\office_config.xml"

# ── Apps ───────────────────────────────────────────────────────────────────────
$InstallApps        = $false
$AppListPath        = "$FFURoot\Apps\REPLACE_WITH_APPLIST.json"  # Path to your app list JSON

# ── Drivers ────────────────────────────────────────────────────────────────────
$InstallDrivers     = $true

# ── Optimization ───────────────────────────────────────────────────────────────
$Optimize           = $true
$CompactOS          = $true

# ==============================================================================
# DO NOT EDIT BELOW THIS LINE (unless you know what you're doing)
# ==============================================================================

# Validate FFU root exists
if (-not (Test-Path $FFURoot)) {
    Write-Error "FFURoot path '$FFURoot' does not exist. Please check your configuration."
    exit 1
}

# Validate BuildFFUVM.ps1 exists
$BuildScript = "$FFURoot\BuildFFUVM.ps1"
if (-not (Test-Path $BuildScript)) {
    Write-Error "BuildFFUVM.ps1 not found at '$BuildScript'. Cannot continue."
    exit 1
}

# Warn if placeholder values are still present
$Placeholders = @($Make, $Model, $FileName) | Where-Object { $_ -like "REPLACE_WITH_*" }
if ($Placeholders.Count -gt 0) {
    Write-Warning "One or more configuration values have not been replaced:"
    $Placeholders | ForEach-Object { Write-Warning "  >> $_" }
    Write-Warning "Please edit the CONFIGURATION block before running."
    exit 1
}

Set-Location $FFURoot

$Params = @{
    FFUDevelopmentPath      = $FFURoot
    WindowsRelease          = $WindowsRelease
    WindowsVersion          = $WindowsVersion

    InstallOffice           = $InstallOffice
    OfficeConfigXMLFile     = $OfficeConfigXML

    InstallApps             = $InstallApps
    AppListPath             = $AppListPath

    InstallDrivers          = $InstallDrivers
    Make                    = $Make
    Model                   = $Model

    Optimize                = $Optimize
    CompactOS               = $CompactOS

    CustomFFUNameTemplate   = $FileName
    Verbose                 = $true
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor DarkCyan
Write-Host "  FFU Build Starting" -ForegroundColor Cyan
Write-Host "  Make   : $Make" -ForegroundColor Cyan
Write-Host "  Model  : $Model" -ForegroundColor Cyan
Write-Host "  Output : $FileName.ffu" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor DarkCyan
Write-Host ""

& $BuildScript @Params