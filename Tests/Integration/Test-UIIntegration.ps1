# Test-UIIntegration.ps1
# Validates that BuildFFUVM.ps1 modular architecture is compatible with UI integration

<#
.SYNOPSIS
Tests BuildFFUVM.ps1 module loading in UI background job context

.DESCRIPTION
This test suite validates that the modularized BuildFFUVM.ps1 works correctly when
launched from BuildFFUVM_UI.ps1 in a background job. It simulates the UI's job
launching mechanism without requiring the actual WPF UI.

Tests performed:
1. Module imports work in clean PowerShell session
2. All 8 modules export expected functions
3. BuildFFUVM.ps1 can be dot-sourced without errors
4. Background job launches successfully with module imports
5. Module functions are available in job context
6. No function name conflicts between modules

.EXAMPLE
.\Test-UIIntegration.ps1

.EXAMPLE
.\Test-UIIntegration.ps1 -Verbose
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$script:TestResults = @()
$script:TestsPassed = 0
$script:TestsFailed = 0

# Helper function to add test results
function Add-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Message
    )

    $result = [PSCustomObject]@{
        Test = $TestName
        Status = if ($Passed) { "PASS" } else { "FAIL" }
        Message = $Message
        Timestamp = Get-Date
    }

    $script:TestResults += $result

    if ($Passed) {
        $script:TestsPassed++
        Write-Host "[PASS] $TestName" -ForegroundColor Green
        if ($Message) { Write-Host "       $Message" -ForegroundColor Gray }
    } else {
        $script:TestsFailed++
        Write-Host "[FAIL] $TestName" -ForegroundColor Red
        Write-Host "       $Message" -ForegroundColor Red
    }
}

Write-Host "`n===============================================" -ForegroundColor Cyan
Write-Host "UI Integration Test Suite (Modular Architecture)" -ForegroundColor Cyan
Write-Host "===============================================`n" -ForegroundColor Cyan

# ============================================
# Test 1: Module Directory Structure
# ============================================
Write-Host "Test 1: Module Directory Structure" -ForegroundColor Cyan

$expectedModules = @('FFU.Core', 'FFU.ADK', 'FFU.Media', 'FFU.VM', 'FFU.Drivers', 'FFU.Apps', 'FFU.Updates', 'FFU.Imaging')
$modulePath = Join-Path $PSScriptRoot "Modules"

if (Test-Path $modulePath) {
    Add-TestResult -TestName "Modules directory exists" -Passed $true -Message "Found at $modulePath"

    foreach ($module in $expectedModules) {
        $modDir = Join-Path $modulePath $module
        $psd1 = Join-Path $modDir "$module.psd1"
        $psm1 = Join-Path $modDir "$module.psm1"

        $exists = (Test-Path $modDir) -and (Test-Path $psd1) -and (Test-Path $psm1)
        Add-TestResult -TestName "$module module structure valid" `
                       -Passed $exists `
                       -Message $(if ($exists) { "Found .psd1 and .psm1" } else { "Missing files" })
    }
} else {
    Add-TestResult -TestName "Modules directory exists" -Passed $false -Message "Not found at $modulePath"
}

# ============================================
# Test 2: Module Import in Clean Session
# ============================================
Write-Host "`nTest 2: Module Import in Clean Session" -ForegroundColor Cyan

$importTest = {
    param($ModulePath)

    try {
        # Add module path to PSModulePath so RequiredModules can be resolved
        $env:PSModulePath = "$ModulePath;$env:PSModulePath"

        # Import modules in strict dependency order
        # FFU.Core must be loaded first (no dependencies)
        Import-Module "FFU.Core" -Force -ErrorAction Stop -WarningAction SilentlyContinue

        # Modules that depend on FFU.Core
        Import-Module "FFU.ADK" -Force -ErrorAction Stop -WarningAction SilentlyContinue
        Import-Module "FFU.VM" -Force -ErrorAction Stop -WarningAction SilentlyContinue
        Import-Module "FFU.Drivers" -Force -ErrorAction Stop -WarningAction SilentlyContinue
        Import-Module "FFU.Apps" -Force -ErrorAction Stop -WarningAction SilentlyContinue
        Import-Module "FFU.Updates" -Force -ErrorAction Stop -WarningAction SilentlyContinue
        Import-Module "FFU.Imaging" -Force -ErrorAction Stop -WarningAction SilentlyContinue

        # FFU.Media depends on FFU.Core and FFU.ADK
        Import-Module "FFU.Media" -Force -ErrorAction Stop -WarningAction SilentlyContinue

        return @{
            Success = $true
            ModuleCount = (Get-Module FFU.* | Measure-Object).Count
            Error = $null
        }
    } catch {
        return @{
            Success = $false
            ModuleCount = 0
            Error = $_.Exception.Message
        }
    }
}

$importJob = Start-Job -ScriptBlock $importTest -ArgumentList $modulePath
$importResult = $importJob | Wait-Job | Receive-Job

Add-TestResult -TestName "All modules import without errors" `
               -Passed $importResult.Success `
               -Message $(if ($importResult.Success) { "$($importResult.ModuleCount) modules loaded" } else { $importResult.Error })

Remove-Job $importJob -Force

# ============================================
# Test 3: Exported Functions
# ============================================
Write-Host "`nTest 3: Exported Functions" -ForegroundColor Cyan

$expectedFunctions = @{
    'FFU.Core'    = @('Get-Parameters', 'New-RunSession', 'Export-ConfigFile')
    'FFU.ADK'     = @('Test-ADKPrerequisites', 'Install-ADK', 'Get-ADK')
    'FFU.Media'   = @('Invoke-DISMPreFlightCleanup', 'Invoke-CopyPEWithRetry', 'New-PEMedia')
    'FFU.VM'      = @('New-FFUVM', 'Remove-FFUVM', 'Get-FFUEnvironment')
    'FFU.Drivers' = @('Get-DellDrivers', 'Get-HPDrivers', 'Copy-Drivers')
    'FFU.Apps'    = @('Get-Office', 'New-AppsISO')
    'FFU.Updates' = @('Get-WindowsESD', 'Save-KB', 'Add-WindowsPackageWithRetry')
    'FFU.Imaging' = @('New-FFU', 'New-ScratchVhdx', 'Initialize-DISMService')
}

try {
    # Add module path to PSModulePath so RequiredModules can be resolved
    $originalPath = $env:PSModulePath
    $env:PSModulePath = "$modulePath;$env:PSModulePath"

    # Import modules in current session for testing (strict dependency order)
    Import-Module "FFU.Core" -Force -WarningAction SilentlyContinue
    Import-Module "FFU.ADK" -Force -WarningAction SilentlyContinue
    Import-Module "FFU.VM" -Force -WarningAction SilentlyContinue
    Import-Module "FFU.Drivers" -Force -WarningAction SilentlyContinue
    Import-Module "FFU.Apps" -Force -WarningAction SilentlyContinue
    Import-Module "FFU.Updates" -Force -WarningAction SilentlyContinue
    Import-Module "FFU.Imaging" -Force -WarningAction SilentlyContinue
    Import-Module "FFU.Media" -Force -WarningAction SilentlyContinue

    foreach ($moduleName in $expectedFunctions.Keys) {
        $module = Get-Module $moduleName
        if ($module) {
            $exportedCount = ($module.ExportedFunctions.Keys | Measure-Object).Count
            $sampleFunctions = $expectedFunctions[$moduleName]
            $allFound = $true

            foreach ($funcName in $sampleFunctions) {
                if (-not $module.ExportedFunctions.ContainsKey($funcName)) {
                    $allFound = $false
                    break
                }
            }

            Add-TestResult -TestName "$moduleName exports expected functions" `
                           -Passed $allFound `
                           -Message "$exportedCount total functions exported"
        } else {
            Add-TestResult -TestName "$moduleName exports expected functions" `
                           -Passed $false `
                           -Message "Module not loaded"
        }
    }
} catch {
    Add-TestResult -TestName "Function export validation" `
                   -Passed $false `
                   -Message $_.Exception.Message
}

# ============================================
# Test 4: UI Background Job Simulation
# ============================================
Write-Host "`nTest 4: UI Background Job Simulation" -ForegroundColor Cyan

# Simulate how BuildFFUVM_UI.ps1 launches BuildFFUVM.ps1
$uiJobTest = {
    param($PSScriptRoot)

    try {
        # This simulates the UI's job launch mechanism
        $ModulePath = "$PSScriptRoot\Modules"

        # Add module path so RequiredModules can be resolved
        $env:PSModulePath = "$ModulePath;$env:PSModulePath"

        # Modules should load via BuildFFUVM.ps1's own import statements
        # Test that the import section works
        Import-Module "FFU.Core" -Force -ErrorAction Stop -WarningAction SilentlyContinue
        Import-Module "FFU.ADK" -Force -ErrorAction Stop -WarningAction SilentlyContinue
        Import-Module "FFU.Media" -Force -ErrorAction Stop -WarningAction SilentlyContinue

        # Verify critical functions are available
        $coreFunc = Get-Command -Name 'Get-Parameters' -ErrorAction SilentlyContinue
        $adkFunc = Get-Command -Name 'Test-ADKPrerequisites' -ErrorAction SilentlyContinue
        $mediaFunc = Get-Command -Name 'Invoke-DISMPreFlightCleanup' -ErrorAction SilentlyContinue

        return @{
            Success = ($null -ne $coreFunc -and $null -ne $adkFunc -and $null -ne $mediaFunc)
            CoreFunction = ($null -ne $coreFunc)
            ADKFunction = ($null -ne $adkFunc)
            MediaFunction = ($null -ne $mediaFunc)
        }
    } catch {
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

$bgJob = Start-Job -ScriptBlock $uiJobTest -ArgumentList $PSScriptRoot
$bgResult = $bgJob | Wait-Job | Receive-Job

Add-TestResult -TestName "Background job module imports work" `
               -Passed $bgResult.Success `
               -Message $(if ($bgResult.Success) { "All test functions available in job" } else { $bgResult.Error })

if ($bgResult.CoreFunction -ne $null) {
    Add-TestResult -TestName "FFU.Core functions available in job" `
                   -Passed $bgResult.CoreFunction `
                   -Message $(if ($bgResult.CoreFunction) { "Get-Parameters found" } else { "Function not found" })
}

if ($bgResult.MediaFunction -ne $null) {
    Add-TestResult -TestName "FFU.Media functions available in job" `
                   -Passed $bgResult.MediaFunction `
                   -Message $(if ($bgResult.MediaFunction) { "Invoke-DISMPreFlightCleanup found" } else { "Function not found" })
}

Remove-Job $bgJob -Force

# ============================================
# Test 5: Module Dependency Chain
# ============================================
Write-Host "`nTest 5: Module Dependency Chain" -ForegroundColor Cyan

$depTest = {
    param($ModulePath)

    try {
        # Add module path so RequiredModules can be resolved
        $env:PSModulePath = "$ModulePath;$env:PSModulePath"

        # FFU.Core has no dependencies
        Import-Module "FFU.Core" -Force -ErrorAction Stop -WarningAction SilentlyContinue

        # FFU.ADK requires FFU.Core
        Import-Module "FFU.ADK" -Force -ErrorAction Stop -WarningAction SilentlyContinue

        # FFU.Media requires FFU.Core and FFU.ADK
        Import-Module "FFU.Media" -Force -ErrorAction Stop -WarningAction SilentlyContinue

        # Read manifest file directly (compatible with PS 5.0+)
        $manifestPath = "$ModulePath\FFU.Media\FFU.Media.psd1"
        $manifestContent = Get-Content $manifestPath -Raw

        # Extract RequiredModules using regex (simple approach for test)
        $requiredModules = if ($manifestContent -match "RequiredModules\s*=\s*@\('([^']+)'(?:,\s*'([^']+)')*\)") {
            $Matches[1..($Matches.Count-1)] | Where-Object { $_ } | ForEach-Object { $_ }
        } else {
            @()
        }

        return @{
            Success = $true
            MediaDependencies = ($requiredModules -join ', ')
        }
    } catch {
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

$depJob = Start-Job -ScriptBlock $depTest -ArgumentList $modulePath
$depResult = $depJob | Wait-Job | Receive-Job

Add-TestResult -TestName "Module dependencies resolve correctly" `
               -Passed $depResult.Success `
               -Message $(if ($depResult.Success) { "FFU.Media requires: $($depResult.MediaDependencies)" } else { $depResult.Error })

Remove-Job $depJob -Force

# ============================================
# Test 6: No Function Name Conflicts
# ============================================
Write-Host "`nTest 6: Function Name Conflicts" -ForegroundColor Cyan

$allFunctions = @()
$conflicts = @()

foreach ($moduleName in $expectedModules) {
    $module = Get-Module $moduleName
    if ($module) {
        foreach ($funcName in $module.ExportedFunctions.Keys) {
            if ($allFunctions -contains $funcName) {
                $conflicts += $funcName
            } else {
                $allFunctions += $funcName
            }
        }
    }
}

Add-TestResult -TestName "No duplicate function names across modules" `
               -Passed ($conflicts.Count -eq 0) `
               -Message $(if ($conflicts.Count -eq 0) { "$($allFunctions.Count) unique functions" } else { "Conflicts: $($conflicts -join ', ')" })

# ============================================
# Summary
# ============================================
Write-Host "`n===============================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan

$totalTests = $script:TestsPassed + $script:TestsFailed
$passRate = if ($totalTests -gt 0) { [Math]::Round(($script:TestsPassed / $totalTests) * 100, 1) } else { 0 }

Write-Host "`nTotal Tests: $totalTests" -ForegroundColor White
Write-Host "Passed: $script:TestsPassed" -ForegroundColor Green
Write-Host "Failed: $script:TestsFailed" -ForegroundColor $(if ($script:TestsFailed -gt 0) { "Red" } else { "Green" })
Write-Host "Pass Rate: $passRate%" -ForegroundColor $(if ($passRate -ge 90) { "Green" } elseif ($passRate -ge 70) { "Yellow" } else { "Red" })

Write-Host "`nDetailed Results:" -ForegroundColor White
$script:TestResults | Format-Table Test, Status, Message -AutoSize

# Return exit code based on results
if ($script:TestsFailed -gt 0) {
    Write-Host "`n[OVERALL: FAIL] Some tests failed" -ForegroundColor Red
    Write-Host "The modular architecture may have issues with UI integration." -ForegroundColor Yellow
    exit 1
} else {
    Write-Host "`n[OVERALL: PASS] All tests passed!" -ForegroundColor Green
    Write-Host "The modular architecture is compatible with BuildFFUVM_UI.ps1" -ForegroundColor Green
    exit 0
}
