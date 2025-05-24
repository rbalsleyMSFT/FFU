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

# Define the list of scripts to run, order doesn't matter - if you have a custom script, add it here
$scriptList = @(
    "Install-Office.ps1",
    "Update-Defender.ps1",
    "Update-MSRT.ps1",
    "Update-OneDrive.ps1",
    "Update-Edge.ps1",
    "Install-Win32Apps.ps1",
    "Install-StoreApps.ps1",
    "Invoke-AppsScript.ps1",
    "Install-UserApps.ps1"    
)
# Check if each script exists and run it if it does 
foreach ($script in $scriptList) {
    $scriptFile = Join-Path -Path $scriptPath -ChildPath $script
    if (Test-Path -Path $scriptFile) {
        Write-Host "`n" # Add a newline for spacing
        Write-Host "---------------------------------------------------" -ForegroundColor Yellow
        Write-Host " Running script: $script" -ForegroundColor Yellow
        Write-Host "---------------------------------------------------" -ForegroundColor Yellow
        # Run script and wait for it to finish
        # pause
        & $scriptFile
    }
}

# Run-DiskCleanup.ps1 must run before Run-Sysprep.ps1
$diskCleanupScript = Join-Path -Path $scriptPath -ChildPath "Run-DiskCleanup.ps1"
if (Test-Path -Path $diskCleanupScript) {
    Write-Host "`n" # Add a newline for spacing
    Write-Host "---------------------------------------------------" -ForegroundColor Yellow
    Write-Host " Running script: Run-DiskCleanup.ps1" -ForegroundColor Yellow
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
    Write-Host " Running script: Run-Sysprep.ps1" -ForegroundColor Yellow
    Write-Host "---------------------------------------------------" -ForegroundColor Yellow
    # Run script and wait for it to finish
    & $sysprepScript
} else {
    Write-Host "Run-Sysprep.ps1 not found!"
}


