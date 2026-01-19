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

# ============================================================================
# Script Integrity Verification (SEC-03)
# Verifies scripts against hash manifest before execution to detect tampering
# ============================================================================

$verifyIntegrity = $true  # Set to $false to disable verification

# Initialize verification variables
$manifest = $null
$manifestPath = $null

if ($verifyIntegrity) {
    # Derive paths - go up from Orchestration to Apps to FFUDevelopment
    $ffuDevelopmentPath = Split-Path -Path (Split-Path -Path $scriptPath -Parent) -Parent
    $manifestPath = Join-Path $ffuDevelopmentPath ".security\orchestration-hashes.json"

    # Check if manifest exists
    if (Test-Path $manifestPath) {
        Write-Host "SECURITY: Verifying script integrity..." -ForegroundColor Cyan

        # Load manifest once for all verifications
        try {
            $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
        }
        catch {
            Write-Host "SECURITY WARNING: Failed to read hash manifest: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        if ($null -ne $manifest) {
            # Self-verify Orchestrator.ps1 first
            $selfPath = $MyInvocation.MyCommand.Definition
            $selfHash = (Get-FileHash -Path $selfPath -Algorithm SHA256).Hash
            $expectedSelfHash = $manifest.scripts.'Orchestrator.ps1'

            if (-not [string]::IsNullOrEmpty($expectedSelfHash) -and $selfHash -ne $expectedSelfHash) {
                Write-Host "SECURITY ERROR: Orchestrator.ps1 integrity check failed!" -ForegroundColor Red
                Write-Host "  Expected: $expectedSelfHash" -ForegroundColor Red
                Write-Host "  Actual:   $selfHash" -ForegroundColor Red
                Write-Host "Script execution halted. This may indicate tampering." -ForegroundColor Red
                exit 1
            }
            Write-Host "SECURITY: Orchestrator.ps1 verified" -ForegroundColor Green
        }
    }
    else {
        Write-Host "SECURITY WARNING: Hash manifest not found at $manifestPath" -ForegroundColor Yellow
        Write-Host "Proceeding without integrity verification" -ForegroundColor Yellow
    }
}

# Define the list of scripts to run, order doesn't matter - if you have a custom script, add it here
$scriptList = @(
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
        # Verify script integrity before execution (SEC-03)
        if ($verifyIntegrity -and $null -ne $manifest) {
            $scriptHash = (Get-FileHash -Path $scriptFile -Algorithm SHA256).Hash
            $expectedHash = $manifest.scripts.$script

            if (-not [string]::IsNullOrEmpty($expectedHash) -and $scriptHash -ne $expectedHash) {
                Write-Host "SECURITY ERROR: $script integrity check failed!" -ForegroundColor Red
                Write-Host "  Expected: $expectedHash" -ForegroundColor Red
                Write-Host "  Actual:   $scriptHash" -ForegroundColor Red
                Write-Host "Skipping execution of $script" -ForegroundColor Red
                continue  # Skip this script but continue with others
            }
            elseif (-not [string]::IsNullOrEmpty($expectedHash)) {
                Write-Host "SECURITY: $script verified" -ForegroundColor Green
            }
        }

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
    # Verify script integrity before execution (SEC-03)
    $skipAppsScript = $false
    if ($verifyIntegrity -and $null -ne $manifest) {
        $appsScriptHash = (Get-FileHash -Path $appsScriptFile -Algorithm SHA256).Hash
        $expectedAppsScriptHash = $manifest.scripts.'Invoke-AppsScript.ps1'

        if (-not [string]::IsNullOrEmpty($expectedAppsScriptHash) -and $appsScriptHash -ne $expectedAppsScriptHash) {
            Write-Host "SECURITY ERROR: Invoke-AppsScript.ps1 integrity check failed!" -ForegroundColor Red
            Write-Host "  Expected: $expectedAppsScriptHash" -ForegroundColor Red
            Write-Host "  Actual:   $appsScriptHash" -ForegroundColor Red
            Write-Host "Skipping execution of Invoke-AppsScript.ps1" -ForegroundColor Red
            $skipAppsScript = $true
        }
        elseif (-not [string]::IsNullOrEmpty($expectedAppsScriptHash)) {
            Write-Host "SECURITY: Invoke-AppsScript.ps1 verified" -ForegroundColor Green
        }
    }

    if (-not $skipAppsScript) {
        Write-Host "`n" # Add a newline for spacing
        Write-Host "---------------------------------------------------" -ForegroundColor Yellow
        Write-Host " Running script: Invoke-AppsScript.ps1             " -ForegroundColor Yellow
        Write-Host "---------------------------------------------------" -ForegroundColor Yellow

        Write-Host "Using AppsScriptVariables from JSON file: $appsScriptVarsJsonPath"
        & $appsScriptFile
    }
}

# Run-DiskCleanup.ps1 must run before Run-Sysprep.ps1
$diskCleanupScript = Join-Path -Path $scriptPath -ChildPath "Run-DiskCleanup.ps1"
if (Test-Path -Path $diskCleanupScript) {
    # Verify script integrity before execution (SEC-03)
    $skipDiskCleanup = $false
    if ($verifyIntegrity -and $null -ne $manifest) {
        $diskCleanupHash = (Get-FileHash -Path $diskCleanupScript -Algorithm SHA256).Hash
        $expectedDiskCleanupHash = $manifest.scripts.'Run-DiskCleanup.ps1'

        if (-not [string]::IsNullOrEmpty($expectedDiskCleanupHash) -and $diskCleanupHash -ne $expectedDiskCleanupHash) {
            Write-Host "SECURITY ERROR: Run-DiskCleanup.ps1 integrity check failed!" -ForegroundColor Red
            Write-Host "  Expected: $expectedDiskCleanupHash" -ForegroundColor Red
            Write-Host "  Actual:   $diskCleanupHash" -ForegroundColor Red
            Write-Host "Skipping execution of Run-DiskCleanup.ps1" -ForegroundColor Red
            $skipDiskCleanup = $true
        }
        elseif (-not [string]::IsNullOrEmpty($expectedDiskCleanupHash)) {
            Write-Host "SECURITY: Run-DiskCleanup.ps1 verified" -ForegroundColor Green
        }
    }

    if (-not $skipDiskCleanup) {
        Write-Host "`n" # Add a newline for spacing
        Write-Host "---------------------------------------------------" -ForegroundColor Yellow
        Write-Host " Running script: Run-DiskCleanup.ps1               " -ForegroundColor Yellow
        Write-Host "---------------------------------------------------" -ForegroundColor Yellow
        # Run script and wait for it to finish
        & $diskCleanupScript
    }
} else {
    Write-Host "Run-DiskCleanup.ps1 not found!"
}

# Run-Sysprep.ps1 must run last
$sysprepScript = Join-Path -Path $scriptPath -ChildPath "Run-Sysprep.ps1"
if (Test-Path -Path $sysprepScript) {
    # Verify script integrity before execution (SEC-03)
    $skipSysprep = $false
    if ($verifyIntegrity -and $null -ne $manifest) {
        $sysprepHash = (Get-FileHash -Path $sysprepScript -Algorithm SHA256).Hash
        $expectedSysprepHash = $manifest.scripts.'Run-Sysprep.ps1'

        if (-not [string]::IsNullOrEmpty($expectedSysprepHash) -and $sysprepHash -ne $expectedSysprepHash) {
            Write-Host "SECURITY ERROR: Run-Sysprep.ps1 integrity check failed!" -ForegroundColor Red
            Write-Host "  Expected: $expectedSysprepHash" -ForegroundColor Red
            Write-Host "  Actual:   $sysprepHash" -ForegroundColor Red
            Write-Host "Skipping execution of Run-Sysprep.ps1" -ForegroundColor Red
            $skipSysprep = $true
        }
        elseif (-not [string]::IsNullOrEmpty($expectedSysprepHash)) {
            Write-Host "SECURITY: Run-Sysprep.ps1 verified" -ForegroundColor Green
        }
    }

    if (-not $skipSysprep) {
        Write-Host "`n" # Add a newline for spacing
        Write-Host "---------------------------------------------------" -ForegroundColor Yellow
        Write-Host " Running script: Run-Sysprep.ps1                   " -ForegroundColor Yellow
        Write-Host "---------------------------------------------------" -ForegroundColor Yellow
        # Run script and wait for it to finish
        & $sysprepScript
    }
} else {
    Write-Host "Run-Sysprep.ps1 not found!"
}


