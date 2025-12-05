<#
.SYNOPSIS
    Test script to verify module exports are synchronized between .psm1 and .psd1 files

.DESCRIPTION
    Validates that all functions exported via Export-ModuleMember in .psm1 files
    are also listed in the corresponding .psd1 manifest FunctionsToExport array.

    This prevents the "function not recognized" error that occurs when:
    - A function is added to Export-ModuleMember in the .psm1
    - But not added to FunctionsToExport in the .psd1 manifest

    PowerShell module manifests take precedence over Export-ModuleMember,
    so missing functions in the manifest will not be exported even if
    they are in Export-ModuleMember.

.NOTES
    Created: 2025-11-26
    Part of: Module Export Synchronization Fix
#>

param(
    [string]$ModulesPath = "$PSScriptRoot\Modules"
)

$ErrorActionPreference = 'Continue'
$testResults = @()
$passCount = 0
$failCount = 0
$warningCount = 0

function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Message = "",
        [switch]$Warning
    )

    if ($Warning) {
        $status = "WARNING"
        $color = "Yellow"
        $symbol = "[!]"
        $script:warningCount++
    } elseif ($Passed) {
        $status = "PASSED"
        $color = "Green"
        $symbol = "[+]"
        $script:passCount++
    } else {
        $status = "FAILED"
        $color = "Red"
        $symbol = "[-]"
        $script:failCount++
    }

    Write-Host "$symbol $TestName - $status" -ForegroundColor $color
    if ($Message) {
        Write-Host "    $Message" -ForegroundColor Gray
    }

    $script:testResults += [PSCustomObject]@{
        Test = $TestName
        Status = $status
        Message = $Message
    }
}

Write-Host "`n===========================================" -ForegroundColor Cyan
Write-Host "Module Export Synchronization Test" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "Validates that .psm1 Export-ModuleMember matches .psd1 FunctionsToExport`n" -ForegroundColor Yellow

# Get all module directories
$modules = Get-ChildItem -Path $ModulesPath -Directory -ErrorAction SilentlyContinue

if (-not $modules) {
    Write-Host "ERROR: No modules found in $ModulesPath" -ForegroundColor Red
    exit 1
}

Write-Host "Found $($modules.Count) module(s) to check`n" -ForegroundColor Gray

foreach ($module in $modules) {
    $moduleName = $module.Name
    $psm1Path = Join-Path $module.FullName "$moduleName.psm1"
    $psd1Path = Join-Path $module.FullName "$moduleName.psd1"

    Write-Host "--- Checking $moduleName ---" -ForegroundColor Cyan

    # Check if both files exist
    if (-not (Test-Path $psm1Path)) {
        Write-TestResult -TestName "$moduleName`: .psm1 exists" -Passed $false -Message "Missing: $psm1Path"
        continue
    }
    if (-not (Test-Path $psd1Path)) {
        Write-TestResult -TestName "$moduleName`: .psd1 exists" -Passed $false -Message "Missing: $psd1Path"
        continue
    }

    Write-TestResult -TestName "$moduleName`: Module files exist" -Passed $true

    # Extract Export-ModuleMember functions from .psm1
    $psm1Content = Get-Content $psm1Path -Raw
    $exportMatch = [regex]::Match($psm1Content, "Export-ModuleMember\s+-Function\s+@\(([\s\S]*?)\)")

    $psm1Functions = @()
    if ($exportMatch.Success) {
        $functionList = $exportMatch.Groups[1].Value
        $psm1Functions = [regex]::Matches($functionList, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value }
    }

    # Extract FunctionsToExport from .psd1
    $psd1Content = Get-Content $psd1Path -Raw
    $psd1Data = $null
    try {
        # Try Import-PowerShellDataFile first (PS 5.0+), fallback to Invoke-Expression for older versions
        if (Get-Command Import-PowerShellDataFile -ErrorAction SilentlyContinue) {
            $psd1Data = Import-PowerShellDataFile -Path $psd1Path -ErrorAction Stop
        } else {
            # Fallback: Parse the file content using regex for FunctionsToExport
            $psd1Data = @{}
            $functionsMatch = [regex]::Match($psd1Content, "FunctionsToExport\s*=\s*@\(([\s\S]*?)\)")
            if ($functionsMatch.Success) {
                $functionList = $functionsMatch.Groups[1].Value
                $psd1Data['FunctionsToExport'] = [regex]::Matches($functionList, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value }
            }
        }
    } catch {
        Write-TestResult -TestName "$moduleName`: Manifest is valid" -Passed $false -Message "Parse error: $_"
        continue
    }

    Write-TestResult -TestName "$moduleName`: Manifest is valid" -Passed $true

    $psd1Functions = @()
    if ($psd1Data.FunctionsToExport) {
        $psd1Functions = $psd1Data.FunctionsToExport
    }

    # Compare the two lists
    $missingInManifest = @()
    $extraInManifest = @()

    foreach ($func in $psm1Functions) {
        if ($func -notin $psd1Functions) {
            $missingInManifest += $func
        }
    }

    foreach ($func in $psd1Functions) {
        if ($func -notin $psm1Functions) {
            $extraInManifest += $func
        }
    }

    # Report results
    if ($missingInManifest.Count -eq 0 -and $extraInManifest.Count -eq 0) {
        Write-TestResult -TestName "$moduleName`: Exports synchronized" -Passed $true -Message "All $($psm1Functions.Count) functions matched"
    } else {
        if ($missingInManifest.Count -gt 0) {
            Write-TestResult -TestName "$moduleName`: Functions missing in manifest" -Passed $false `
                -Message "Add to FunctionsToExport: $($missingInManifest -join ', ')"
        }
        if ($extraInManifest.Count -gt 0) {
            Write-TestResult -TestName "$moduleName`: Extra functions in manifest" -Warning `
                -Message "In manifest but not in psm1: $($extraInManifest -join ', ')"
        }
    }

    # Verify functions are actually exported when module is loaded
    Write-Host "    Verifying actual module exports..." -ForegroundColor Gray

    # Import module in isolated scope
    $modulePath = Join-Path $ModulesPath $moduleName
    $importedFunctions = @()
    try {
        # Add modules path temporarily
        $originalPSModulePath = $env:PSModulePath
        $env:PSModulePath = "$ModulesPath;$env:PSModulePath"

        # Import required modules first (FFU.Constants, FFU.Core)
        $constantsPath = Join-Path $ModulesPath "FFU.Constants\FFU.Constants.psm1"
        $corePath = Join-Path $ModulesPath "FFU.Core\FFU.Core.psm1"
        if (Test-Path $constantsPath) { Import-Module $constantsPath -Force -ErrorAction SilentlyContinue }
        if (Test-Path $corePath) { Import-Module $corePath -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue }

        # Import the target module
        Import-Module $psd1Path -Force -ErrorAction Stop -WarningAction SilentlyContinue
        $importedFunctions = (Get-Module $moduleName).ExportedFunctions.Keys
        Remove-Module $moduleName -Force -ErrorAction SilentlyContinue

        $env:PSModulePath = $originalPSModulePath
    } catch {
        Write-TestResult -TestName "$moduleName`: Module imports successfully" -Passed $false -Message "Import error: $_"
        continue
    }

    # Check if all manifest functions are actually exported
    $notExported = @()
    foreach ($func in $psd1Functions) {
        if ($func -notin $importedFunctions) {
            $notExported += $func
        }
    }

    if ($notExported.Count -eq 0) {
        Write-TestResult -TestName "$moduleName`: All manifest functions exported" -Passed $true `
            -Message "$($importedFunctions.Count) functions available"
    } else {
        Write-TestResult -TestName "$moduleName`: Functions not actually exported" -Passed $false `
            -Message "Listed but not exported: $($notExported -join ', ')"
    }

    Write-Host ""
}

# =============================================================================
# Specific test for the KB path resolution functions
# =============================================================================
Write-Host "--- Critical Function Verification ---" -ForegroundColor Cyan
Write-Host "Testing functions that caused the original error:" -ForegroundColor Yellow

$criticalFunctions = @('Test-KBPathsValid', 'Resolve-KBFilePath')
$updatesModule = Join-Path $ModulesPath "FFU.Updates\FFU.Updates.psd1"

if (Test-Path $updatesModule) {
    try {
        $env:PSModulePath = "$ModulesPath;$env:PSModulePath"
        Import-Module (Join-Path $ModulesPath "FFU.Constants\FFU.Constants.psm1") -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $ModulesPath "FFU.Core\FFU.Core.psm1") -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
        Import-Module $updatesModule -Force -ErrorAction Stop -WarningAction SilentlyContinue

        foreach ($func in $criticalFunctions) {
            $cmd = Get-Command $func -ErrorAction SilentlyContinue
            if ($cmd) {
                Write-TestResult -TestName "$func is available" -Passed $true `
                    -Message "Function found in module: $($cmd.Module.Name)"
            } else {
                Write-TestResult -TestName "$func is available" -Passed $false `
                    -Message "Function NOT found - this would cause build failures"
            }
        }

        Remove-Module FFU.Updates -Force -ErrorAction SilentlyContinue
    } catch {
        Write-TestResult -TestName "Critical functions verification" -Passed $false -Message "Error: $_"
    }
}

# =============================================================================
# Summary
# =============================================================================
Write-Host "`n===========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "Total Tests: $($passCount + $failCount + $warningCount)" -ForegroundColor White
Write-Host "Passed: $passCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "Green" })
Write-Host "Warnings: $warningCount" -ForegroundColor $(if ($warningCount -gt 0) { "Yellow" } else { "Green" })

if ($failCount -eq 0) {
    Write-Host "`nAll module exports are properly synchronized!" -ForegroundColor Green
    Write-Host "`nThis test should be run whenever:" -ForegroundColor White
    Write-Host "  - Adding new functions to a module" -ForegroundColor Cyan
    Write-Host "  - Modifying Export-ModuleMember in .psm1 files" -ForegroundColor Cyan
    Write-Host "  - Updating FunctionsToExport in .psd1 manifests" -ForegroundColor Cyan
} else {
    Write-Host "`nSome modules have export synchronization issues!" -ForegroundColor Red
    Write-Host "Fix the issues above to prevent 'function not recognized' errors." -ForegroundColor Yellow
}

# Return results for automation
return [PSCustomObject]@{
    TotalTests = $passCount + $failCount + $warningCount
    Passed = $passCount
    Failed = $failCount
    Warnings = $warningCount
    Results = $testResults
}
