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

# Define the path to the scripts
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$appsMediaRoot = Split-Path -Parent $scriptPath
if ([string]::IsNullOrWhiteSpace([string]$env:FFUAppsRoot)) {
    $env:FFUAppsRoot = $appsMediaRoot
}
else {
    $env:FFUAppsRoot = ([string]$env:FFUAppsRoot).Trim().TrimEnd('\')
}
Write-Host "Using Apps media root: $env:FFUAppsRoot"

function Resolve-AppsMediaPath {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $appsRoot = ([string]$env:FFUAppsRoot).Trim().TrimEnd('\')
    if (-not [string]::IsNullOrWhiteSpace($appsRoot)) {
        $tokenPattern = '%FFUAppsRoot%|\$\{?env:FFUAppsRoot\}?|\{FFUAppsRoot\}'
        $regexOptions = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        $Path = [regex]::Replace($Path, $tokenPattern, [System.Text.RegularExpressions.MatchEvaluator] { param($match) $appsRoot }, $regexOptions)
    }

    if ($Path -notmatch '^(?i)d:\\') {
        return $Path
    }

    if ([string]::IsNullOrWhiteSpace($appsRoot)) {
        return $Path
    }

    $candidatePath = Join-Path -Path $appsRoot -ChildPath $Path.Substring(3)
    if (Test-Path -Path $Path) {
        return $Path
    }

    if (Test-Path -Path $candidatePath) {
        return $candidatePath
    }

    return $Path
}

# Resolve the configured BYO app list path for runtime orchestration.
$appInstallConfigPath = Join-Path -Path $scriptPath -ChildPath "AppInstallConfig.json"
$userAppsJsonFile = Join-Path -Path (Split-Path -Parent $scriptPath) -ChildPath "UserAppList.json"

if (Test-Path -Path $appInstallConfigPath) {
    try {
        $appInstallConfig = Get-Content -Path $appInstallConfigPath -Raw | ConvertFrom-Json
        if ($null -ne $appInstallConfig -and $appInstallConfig.PSObject.Properties.Match('UserAppListPath').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($appInstallConfig.UserAppListPath)) {
            $userAppsJsonFile = Resolve-AppsMediaPath -Path $appInstallConfig.UserAppListPath
            Write-Host "Using BYO app list path from AppInstallConfig.json: $userAppsJsonFile"
        }
    }
    catch {
        Write-Host "Failed to parse AppInstallConfig.json. Falling back to default BYO app list path."
    }
}

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
            if (-not (Test-Path -Path $wingetAppsJsonFile) -and -not (Test-Path -Path $userAppsJsonFile)) {
                $shouldRun = $false
            }
        }
        "Install-StoreApps.ps1" {
            $msStorePath = Join-Path -Path $env:FFUAppsRoot -ChildPath "MSStore"
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
        # Run script and wait for it to finish.
        if ($script -eq "Install-Win32Apps.ps1") {
            & $scriptFile -UserAppsJsonFile $userAppsJsonFile
        }
        elseif ($script -eq "Install-StoreApps.ps1") {
            & $scriptFile -BasePath (Join-Path -Path $env:FFUAppsRoot -ChildPath "MSStore")
        }
        else {
            & $scriptFile
        }
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

