<#
.SYNOPSIS
    Test script to verify fix for missing Get-USBDrive and New-DeploymentUSB functions

.DESCRIPTION
    This test verifies that the USB drive functions that were accidentally omitted
    during modularization have been restored to BuildFFUVM.ps1.

    The bug was:
    - During modularization, Get-USBDrive and New-DeploymentUSB were not extracted
    - When BuildUSBDrive=$true, the script failed with "New-DeploymentUSB is not recognized"

    The fix:
    - Added both functions back to BuildFFUVM.ps1 (intentionally not modularized)
    - They remain in script scope because New-DeploymentUSB uses ForEach-Object -Parallel
      with many $using: variables that require script scope access

.NOTES
    Created: 2025-11-27
    Fix: Restore Get-USBDrive and New-DeploymentUSB functions to BuildFFUVM.ps1
#>

param()

$ErrorActionPreference = 'Continue'
$testResults = @()
$passCount = 0
$failCount = 0

function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Message = ""
    )

    if ($Passed) {
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

Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host "USB Drive Functions Fix Test" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Tests that Get-USBDrive and New-DeploymentUSB are restored`n" -ForegroundColor Yellow

$buildScript = Get-Content "$PSScriptRoot\BuildFFUVM.ps1" -Raw

# =============================================================================
# Test 1: Verify Get-USBDrive function exists
# =============================================================================
Write-Host "--- Verifying Get-USBDrive Function ---`n" -ForegroundColor Cyan

$hasGetUSBDrive = $buildScript -match 'Function Get-USBDrive'
Write-TestResult -TestName "Get-USBDrive function exists in BuildFFUVM.ps1" -Passed $hasGetUSBDrive `
    -Message $(if ($hasGetUSBDrive) { "Function definition found" } else { "Function missing!" })

# Verify function has proper documentation
$hasGetUSBDriveDoc = $buildScript -match 'Get-USBDrive[\s\S]*?\.SYNOPSIS[\s\S]*?Discovers and validates USB drives'
Write-TestResult -TestName "Get-USBDrive has documentation" -Passed $hasGetUSBDriveDoc `
    -Message $(if ($hasGetUSBDriveDoc) { "Comment-based help found" } else { "Missing documentation" })

# Verify function returns USB drives
$hasReturnStatement = $buildScript -match 'return \$USBDrives, \$USBDrivesCount'
Write-TestResult -TestName "Get-USBDrive returns drives and count" -Passed $hasReturnStatement `
    -Message $(if ($hasReturnStatement) { "Return statement found" } else { "Missing return statement" })

# =============================================================================
# Test 2: Verify New-DeploymentUSB function exists
# =============================================================================
Write-Host "`n--- Verifying New-DeploymentUSB Function ---`n" -ForegroundColor Cyan

$hasNewDeploymentUSB = $buildScript -match 'Function New-DeploymentUSB'
Write-TestResult -TestName "New-DeploymentUSB function exists in BuildFFUVM.ps1" -Passed $hasNewDeploymentUSB `
    -Message $(if ($hasNewDeploymentUSB) { "Function definition found" } else { "Function missing!" })

# Verify function has proper parameters
$hasCopyFFUParam = $buildScript -match 'New-DeploymentUSB[\s\S]*?\[switch\]\$CopyFFU'
Write-TestResult -TestName "New-DeploymentUSB has CopyFFU parameter" -Passed $hasCopyFFUParam `
    -Message $(if ($hasCopyFFUParam) { "CopyFFU switch parameter found" } else { "Missing CopyFFU parameter" })

$hasFFUFilesToCopyParam = $buildScript -match 'New-DeploymentUSB[\s\S]*?\[string\[\]\]\$FFUFilesToCopy'
Write-TestResult -TestName "New-DeploymentUSB has FFUFilesToCopy parameter" -Passed $hasFFUFilesToCopyParam `
    -Message $(if ($hasFFUFilesToCopyParam) { "FFUFilesToCopy string array parameter found" } else { "Missing FFUFilesToCopy parameter" })

# Verify function has parallel processing
$hasParallelProcessing = $buildScript -match 'New-DeploymentUSB[\s\S]*?ForEach-Object -Parallel'
Write-TestResult -TestName "New-DeploymentUSB uses parallel processing" -Passed $hasParallelProcessing `
    -Message $(if ($hasParallelProcessing) { "ForEach-Object -Parallel found" } else { "Missing parallel processing" })

# =============================================================================
# Test 3: Verify functions are called correctly
# =============================================================================
Write-Host "`n--- Verifying Function Calls ---`n" -ForegroundColor Cyan

$hasGetUSBDriveCall = $buildScript -match '\$USBDrives, \$USBDrivesCount = Get-USBDrive'
Write-TestResult -TestName "Get-USBDrive is called with correct assignment" -Passed $hasGetUSBDriveCall `
    -Message $(if ($hasGetUSBDriveCall) { "Call pattern found" } else { "Call pattern missing" })

$hasNewDeploymentUSBCall = $buildScript -match 'New-DeploymentUSB -CopyFFU -FFUFilesToCopy \$ffuFilesToCopy'
Write-TestResult -TestName "New-DeploymentUSB is called with correct parameters" -Passed $hasNewDeploymentUSBCall `
    -Message $(if ($hasNewDeploymentUSBCall) { "Call pattern found" } else { "Call pattern missing" })

# =============================================================================
# Test 4: Verify functions are NOT in modules (intentionally)
# =============================================================================
Write-Host "`n--- Verifying Functions Are Not Modularized ---`n" -ForegroundColor Cyan

$modulesPath = "$PSScriptRoot\Modules"
$moduleFiles = Get-ChildItem -Path $modulesPath -Filter "*.psm1" -Recurse -ErrorAction SilentlyContinue

$inModule = $false
foreach ($moduleFile in $moduleFiles) {
    $moduleContent = Get-Content $moduleFile.FullName -Raw
    if ($moduleContent -match 'function Get-USBDrive|function New-DeploymentUSB') {
        $inModule = $true
        break
    }
}

Write-TestResult -TestName "USB functions are NOT in any module (intentional)" -Passed (-not $inModule) `
    -Message $(if (-not $inModule) { "Functions correctly kept in BuildFFUVM.ps1" } else { "Functions found in module - may cause issues" })

# =============================================================================
# Test 5: Verify explanation comment exists
# =============================================================================
Write-Host "`n--- Verifying Documentation ---`n" -ForegroundColor Cyan

$hasExplanationComment = $buildScript -match '# USB Drive Functions[\s\S]*?intentionally kept in BuildFFUVM\.ps1'
Write-TestResult -TestName "Explanation comment documents why functions are not modularized" -Passed $hasExplanationComment `
    -Message $(if ($hasExplanationComment) { "Comment explains ForEach-Object -Parallel scoping" } else { "Missing explanation" })

# =============================================================================
# Test 6: Verify $using: variables in parallel block
# =============================================================================
Write-Host "`n--- Verifying Parallel Block Variables ---`n" -ForegroundColor Cyan

$usingVariables = @(
    '\$using:PSScriptRoot',
    '\$using:LogFile',
    '\$using:ISOMountPoint',
    '\$using:CopyFFU',
    '\$using:SelectedFFUFile',
    '\$using:CopyDrivers',
    '\$using:DriversFolder',
    '\$using:CopyPPKG',
    '\$using:PPKGFolder',
    '\$using:CopyUnattend',
    '\$using:UnattendFolder',
    '\$using:WindowsArch',
    '\$using:CopyAutopilot',
    '\$using:AutopilotFolder'
)

$usingVarCount = 0
foreach ($var in $usingVariables) {
    if ($buildScript -match $var) {
        $usingVarCount++
    }
}

Write-TestResult -TestName 'Parallel block uses $using: for script-scope variables' -Passed ($usingVarCount -ge 10) `
    -Message "Found $usingVarCount of $($usingVariables.Count) expected `$using: variables"

# =============================================================================
# Test 7: Verify script syntax is valid
# =============================================================================
Write-Host "`n--- Verifying Script Syntax ---`n" -ForegroundColor Cyan

try {
    [scriptblock]::Create($buildScript) | Out-Null
    Write-TestResult -TestName "BuildFFUVM.ps1 has valid PowerShell syntax" -Passed $true `
        -Message "Script parses successfully"
} catch {
    Write-TestResult -TestName "BuildFFUVM.ps1 has valid PowerShell syntax" -Passed $false `
        -Message "Parse error: $($_.Exception.Message)"
}

# =============================================================================
# Summary
# =============================================================================
Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Total Tests: $($passCount + $failCount)" -ForegroundColor White
Write-Host "Passed: $passCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "Green" })

if ($failCount -eq 0) {
    Write-Host "`nAll tests passed! The fix correctly restores:" -ForegroundColor Green
    Write-Host "  - Get-USBDrive function for USB drive discovery" -ForegroundColor Cyan
    Write-Host "  - New-DeploymentUSB function for bootable USB creation" -ForegroundColor Cyan
    Write-Host '  - Parallel processing support with $using: variables' -ForegroundColor Cyan
    Write-Host "  - Documentation explaining why not modularized" -ForegroundColor Cyan
} else {
    Write-Host "`nSome tests failed! Review the issues above." -ForegroundColor Red
}

Write-Host "`n=== Bug Pattern ===" -ForegroundColor Yellow
Write-Host "Before fix:" -ForegroundColor Red
Write-Host "  1. BuildUSBDrive = \$true" -ForegroundColor Gray
Write-Host "  2. Script calls Get-USBDrive (line 1083)" -ForegroundColor Gray
Write-Host "  3. ERROR: 'Get-USBDrive' is not recognized" -ForegroundColor Red
Write-Host "  4. Script calls New-DeploymentUSB (line 2917)" -ForegroundColor Gray
Write-Host "  5. ERROR: 'New-DeploymentUSB' is not recognized" -ForegroundColor Red

Write-Host "`nAfter fix:" -ForegroundColor Green
Write-Host "  1. BuildUSBDrive = \$true" -ForegroundColor Gray
Write-Host "  2. Get-USBDrive discovers removable drives" -ForegroundColor Green
Write-Host "  3. New-DeploymentUSB partitions USB drives in parallel" -ForegroundColor Green
Write-Host "  4. FFU files copied to bootable USB" -ForegroundColor Green
Write-Host "  5. USB deployment drives created successfully!" -ForegroundColor Green

Write-Host "`n=== Why Not Modularized ===" -ForegroundColor Yellow
Write-Host 'New-DeploymentUSB uses ForEach-Object -Parallel with 14+ $using: variables.' -ForegroundColor Gray
Write-Host "These variables come from BuildFFUVM.ps1's script scope." -ForegroundColor Gray
Write-Host "Modularizing would require passing all 14+ parameters explicitly," -ForegroundColor Gray
Write-Host "which is impractical and error-prone for this use case." -ForegroundColor Gray

# Return results for automation
return [PSCustomObject]@{
    TotalTests = $passCount + $failCount
    Passed = $passCount
    Failed = $failCount
    Results = $testResults
}
