<#
.SYNOPSIS
    Orchestration script for FFU VM deployment tasks

.DESCRIPTION
    This script orchestrates the following deployment tasks:
    - Install-Office.ps1
    - Update-Defender.ps1
    - Update-MSRT.ps1
    - Update-OneDrive.ps1
    - Update-Edge.ps1
    - Install-Win32Apps.ps1
    - Invoke-AppsScript.ps1
    - Install-UserApps.ps1
    - Install-StoreApps.ps1
    - Run-DiskCleanup.ps1
    - Run-Sysprep.ps1

    The script will check for the presence of each of these files and if they exist, will run the script
#>

# Header

Write-Host "---------------------------------------------------" -ForegroundColor Yellow
Write-Host "             FFU Builder Orchestrator              " -ForegroundColor Yellow
Write-Host "---------------------------------------------------" -ForegroundColor Yellow

# Define the path to the scripts
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Define the list of scripts to run
$scriptList = @(
    "Install-LTSCUpdate.ps1",
    "Update-Defender.ps1",
    "Install-Office.ps1",
    "Update-MSRT.ps1",
    "Update-OneDrive.ps1",
    "Update-Edge.ps1",
    "Install-Win32Apps.ps1",
    "Install-StoreApps.ps1",
    "Install-UserApps.ps1"    
)
# Check if each script exists and has content to process, then run it
foreach ($script in $scriptList) {
    $scriptFile = Join-Path -Path $scriptPath -ChildPath $script
    if (-not (Test-Path -Path $scriptFile)) {
        continue
    }

    $shouldRun = $true # Default to run if script exists
    switch ($script) {
        "Install-Win32Apps.ps1" {
            $wingetAppsJsonFile = Join-Path -Path $scriptPath -ChildPath "WinGetWin32Apps.json"
            $userAppsJsonFile = Join-Path -Path (Split-Path -Parent $scriptPath) -ChildPath "UserAppList.json"
            if (-not (Test-Path -Path $wingetAppsJsonFile) -and -not (Test-Path -Path $userAppsJsonFile)) {
                $shouldRun = $false
            }
        }
        "Install-StoreApps.ps1" {
            $msStorePath = "D:\MSStore"
            if (-not (Test-Path -Path $msStorePath) -or -not (Get-ChildItem -Path $msStorePath)) {
                $shouldRun = $false
            }
        }
    }

    if ($shouldRun) {
        Write-Host "`n" # Add a newline for spacing
        Write-Host "---------------------------------------------------" -ForegroundColor Yellow
        Write-Host " Running script: $script                           " -ForegroundColor Yellow
        Write-Host "---------------------------------------------------" -ForegroundColor Yellow
        # Run script and wait for it to finish
        & $scriptFile
    }
}

# Invoke-AppsScript.ps1 if it exists and AppsScriptVariables.json is present
$appsScriptFile = Join-Path -Path $scriptPath -ChildPath "Invoke-AppsScript.ps1"
$appsScriptVarsJsonPath = Join-Path -Path $PSScriptRoot -ChildPath "AppsScriptVariables.json"
if ((Test-Path -Path $appsScriptFile) -and (Test-Path -Path $appsScriptVarsJsonPath)) {
    Write-Host "`n" # Add a newline for spacing
    Write-Host "---------------------------------------------------" -ForegroundColor Yellow
    Write-Host " Running script: Invoke-AppsScript.ps1             " -ForegroundColor Yellow
    Write-Host "---------------------------------------------------" -ForegroundColor Yellow

    Write-Host "Using AppsScriptVariables from JSON file: $appsScriptVarsJsonPath"
    & $appsScriptFile
}

# Run-DiskCleanup.ps1 must run before Run-Sysprep.ps1
$diskCleanupScript = Join-Path -Path $scriptPath -ChildPath "Run-DiskCleanup.ps1"
if (Test-Path -Path $diskCleanupScript) {
    Write-Host "`n" # Add a newline for spacing
    Write-Host "---------------------------------------------------" -ForegroundColor Yellow
    Write-Host " Running script: Run-DiskCleanup.ps1               " -ForegroundColor Yellow
    Write-Host "---------------------------------------------------" -ForegroundColor Yellow
    # Run script and wait for it to finish
    & $diskCleanupScript

} else {
    Write-Host "Run-DiskCleanup.ps1 not found!"
}

# Run-Sysprep.ps1 must run last
$sysprepScript = Join-Path -Path $scriptPath -ChildPath "Run-Sysprep.ps1"
if (Test-Path -Path $sysprepScript) {
    Write-Host "`n" # Add a newline for spacing
    Write-Host "---------------------------------------------------" -ForegroundColor Yellow
    Write-Host " Running script: Run-Sysprep.ps1                   " -ForegroundColor Yellow
    Write-Host "---------------------------------------------------" -ForegroundColor Yellow
    # Run script and wait for it to finish
    & $sysprepScript
} else {
    Write-Host "Run-Sysprep.ps1 not found!"
}


