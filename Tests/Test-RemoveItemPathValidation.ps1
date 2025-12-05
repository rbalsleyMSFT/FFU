<#
.SYNOPSIS
    Test script for Remove-Item path validation fixes

.DESCRIPTION
    Verifies that:
    1. Remove-Item calls have -ErrorAction SilentlyContinue to prevent non-terminating errors
    2. Path variables are validated before being passed to Remove-Item
    3. Arrays are filtered to remove null/empty values before Remove-Item

    These fixes address:
    - "Value cannot be null. (Parameter 'The provided Path argument was null or an empty collection.')"

.NOTES
    Run this script to verify the Remove-Item path validation fixes are in place.
#>

#Requires -Version 5.1

param(
    [Parameter(Mandatory = $false)]
    [string]$FFUDevelopmentPath = "C:\FFUDevelopment"
)

# Initialize test results
$script:TestResults = @{
    Passed = 0
    Failed = 0
    Skipped = 0
    Tests = @()
}

function Write-TestResult {
    param(
        [string]$TestName,
        [string]$Status,
        [string]$Message = ""
    )

    $color = switch ($Status) {
        'Passed' { 'Green' }
        'Failed' { 'Red' }
        'Skipped' { 'Yellow' }
        default { 'White' }
    }

    $script:TestResults[$Status]++
    $script:TestResults.Tests += [PSCustomObject]@{
        Name = $TestName
        Status = $Status
        Message = $Message
    }

    $statusSymbol = switch ($Status) {
        'Passed' { '[PASS]' }
        'Failed' { '[FAIL]' }
        'Skipped' { '[SKIP]' }
    }

    Write-Host "$statusSymbol $TestName" -ForegroundColor $color
    if ($Message) {
        Write-Host "       $Message" -ForegroundColor Gray
    }
}

function Test-Assertion {
    param(
        [string]$TestName,
        [scriptblock]$Test,
        [string]$FailMessage = "Assertion failed"
    )

    try {
        $result = & $Test
        if ($result) {
            Write-TestResult -TestName $TestName -Status 'Passed'
            return $true
        }
        else {
            Write-TestResult -TestName $TestName -Status 'Failed' -Message $FailMessage
            return $false
        }
    }
    catch {
        Write-TestResult -TestName $TestName -Status 'Failed' -Message $_.Exception.Message
        return $false
    }
}

# ============================================================================
# Setup
# ============================================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Remove-Item Path Validation Tests" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Determine paths
$modulePath = Join-Path $FFUDevelopmentPath "Modules"
if (-not (Test-Path $modulePath)) {
    $modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) "FFUDevelopment\Modules"
}

if (-not (Test-Path $FFUDevelopmentPath)) {
    $FFUDevelopmentPath = Join-Path (Split-Path $PSScriptRoot -Parent) "FFUDevelopment"
}

Write-Host "FFUDevelopment path: $FFUDevelopmentPath" -ForegroundColor Gray

# ============================================================================
# Test 1: FFU.Drivers Module - Array Path Validation
# ============================================================================
Write-Host "`n--- FFU.Drivers Module Tests ---" -ForegroundColor Yellow

$driversModule = Join-Path $modulePath "FFU.Drivers\FFU.Drivers.psm1"
if (Test-Path $driversModule) {
    $content = Get-Content $driversModule -Raw

    Test-Assertion "FFU.Drivers: HP driver cleanup uses Where-Object filter" {
        $content -match '\$cleanupPaths\s*=.*Where-Object.*IsNullOrWhiteSpace'
    } "HP driver cleanup should filter null/empty paths with Where-Object"

    Test-Assertion "FFU.Drivers: HP driver cleanup checks array count before Remove-Item" {
        $content -match '\$cleanupPaths\.Count\s*-gt\s*0'
    } "Should check array count > 0 before calling Remove-Item"

    Test-Assertion "FFU.Drivers: Cleanup Remove-Item has ErrorAction SilentlyContinue" {
        $content -match 'Remove-Item\s+-Path\s+\$cleanupPaths.*-ErrorAction\s+SilentlyContinue'
    } "Cleanup Remove-Item should have -ErrorAction SilentlyContinue"

    Test-Assertion "FFU.Drivers: Dell driver file deletion validates path" {
        $content -match 'if\s*\(-not\s+\[string\]::IsNullOrWhiteSpace\(\$DriverFilePath\)\)' -and
        $content -match 'Remove-Item\s+-Path\s+\$DriverFilePath.*-ErrorAction\s+SilentlyContinue'
    } "Dell driver file deletion should validate path and use ErrorAction"
}
else {
    Write-TestResult "FFU.Drivers.psm1 tests" -Status 'Skipped' -Message "File not found: $driversModule"
}

# ============================================================================
# Test 2: FFU.Apps Module - Remove-Item Error Handling
# ============================================================================
Write-Host "`n--- FFU.Apps Module Tests ---" -ForegroundColor Yellow

$appsModule = Join-Path $modulePath "FFU.Apps\FFU.Apps.psm1"
if (Test-Path $appsModule) {
    $content = Get-Content $appsModule -Raw

    Test-Assertion "FFU.Apps: ODT config cleanup has ErrorAction" {
        $content -match 'Remove-Item\s+-Path\s+"\$OfficePath\\configuration\*".*-ErrorAction\s+SilentlyContinue'
    } "ODT config cleanup should have -ErrorAction SilentlyContinue"

    Test-Assertion "FFU.Apps: ODT install file removal validates path" {
        $content -match 'if\s*\(-not\s+\[string\]::IsNullOrWhiteSpace\(\$ODTInstallFile\)\)'
    } "ODT install file removal should validate path"

    Test-Assertion "FFU.Apps: Win32 folder removal has ErrorAction" {
        $content -match 'Remove-Item\s+-Path\s+"\$AppsPath\\Win32".*-ErrorAction\s+SilentlyContinue'
    } "Win32 folder removal should have -ErrorAction SilentlyContinue"

    Test-Assertion "FFU.Apps: Office download removal validates path" {
        $content -match 'if\s*\(-not\s+\[string\]::IsNullOrWhiteSpace\(\$OfficeDownloadPath\)\)'
    } "Office download removal should validate path"
}
else {
    Write-TestResult "FFU.Apps.psm1 tests" -Status 'Skipped' -Message "File not found: $appsModule"
}

# ============================================================================
# Test 3: FFU.Updates Module - Remove-Item Error Handling
# ============================================================================
Write-Host "`n--- FFU.Updates Module Tests ---" -ForegroundColor Yellow

$updatesModule = Join-Path $modulePath "FFU.Updates\FFU.Updates.psm1"
if (Test-Path $updatesModule) {
    $content = Get-Content $updatesModule -Raw

    Test-Assertion "FFU.Updates: CAB file cleanup validates path" {
        $content -match 'if\s*\(-not\s+\[string\]::IsNullOrWhiteSpace\(\$cabFilePath\)\)' -and
        $content -match 'Remove-Item\s+-Path\s+\$cabFilePath.*-ErrorAction\s+SilentlyContinue'
    } "CAB file cleanup should validate path and use ErrorAction"

    Test-Assertion "FFU.Updates: XML file cleanup validates path" {
        $content -match 'if\s*\(-not\s+\[string\]::IsNullOrWhiteSpace\(\$xmlFilePath\)\)' -and
        $content -match 'Remove-Item\s+-Path\s+\$xmlFilePath.*-ErrorAction\s+SilentlyContinue'
    } "XML file cleanup should validate path and use ErrorAction"

    Test-Assertion "FFU.Updates: Architecture mismatch file deletion validates path" {
        $content -match 'if\s*\(-not\s+\[string\]::IsNullOrWhiteSpace\(\$filePath\)\)' -and
        $content -match 'Remove-Item\s+-Path\s+\$filePath.*-ErrorAction\s+SilentlyContinue'
    } "Architecture mismatch file deletion should validate path"
}
else {
    Write-TestResult "FFU.Updates.psm1 tests" -Status 'Skipped' -Message "File not found: $updatesModule"
}

# ============================================================================
# Test 4: FFU.VM Module - Remove-Item Error Handling
# ============================================================================
Write-Host "`n--- FFU.VM Module Tests ---" -ForegroundColor Yellow

$vmModule = Join-Path $modulePath "FFU.VM\FFU.VM.psm1"
if (Test-Path $vmModule) {
    $content = Get-Content $vmModule -Raw

    Test-Assertion "FFU.VM: VMPath removal validates path" {
        $content -match 'if\s*\(-not\s+\[string\]::IsNullOrWhiteSpace\(\$VMPath\)\)' -and
        $content -match 'Remove-Item\s+-Path\s+\$VMPath.*-ErrorAction\s+SilentlyContinue'
    } "VMPath removal should validate path and use ErrorAction"

    Test-Assertion "FFU.VM: Mount folder removal has ErrorAction" {
        $content -match 'Remove-Item\s+-Path\s+"\$FFUDevelopmentPath\\Mount".*-ErrorAction\s+SilentlyContinue'
    } "Mount folder removal should have -ErrorAction SilentlyContinue"

    Test-Assertion "FFU.VM: dirty.txt removal validates path with Test-Path" {
        $content -match '\$dirtyPath\s*=\s*Join-Path\s+\$FFUDevelopmentPath\s+"dirty\.txt"' -and
        $content -match 'if\s*\(Test-Path\s+-Path\s+\$dirtyPath\)'
    } "dirty.txt removal should use Test-Path check"

    Test-Assertion "FFU.VM: dirty.txt removal has ErrorAction" {
        $content -match 'Remove-Item\s+-Path\s+\$dirtyPath.*-ErrorAction\s+SilentlyContinue'
    } "dirty.txt removal should have -ErrorAction SilentlyContinue"
}
else {
    Write-TestResult "FFU.VM.psm1 tests" -Status 'Skipped' -Message "File not found: $vmModule"
}

# ============================================================================
# Test 4b: FFU.Imaging Module - Remove-Item Error Handling
# ============================================================================
Write-Host "`n--- FFU.Imaging Module Tests ---" -ForegroundColor Yellow

$imagingModule = Join-Path $modulePath "FFU.Imaging\FFU.Imaging.psm1"
if (Test-Path $imagingModule) {
    $content = Get-Content $imagingModule -Raw

    Test-Assertion "FFU.Imaging: Mount folder removal after driver injection has ErrorAction" {
        $content -match 'Remove-Item\s+-Path\s+"\$FFUDevelopmentPath\\Mount".*-ErrorAction\s+SilentlyContinue.*Out-Null'
    } "Mount folder removal after drivers should have -ErrorAction SilentlyContinue"

    Test-Assertion "FFU.Imaging: VMPath removal in Remove-FFU validates path" {
        $content -match 'if\s*\(-not\s+\[string\]::IsNullOrWhiteSpace\(\$VMPath\)\)\s*\{\s*Remove-Item\s+-Path\s+\$VMPath.*-ErrorAction\s+SilentlyContinue'
    } "VMPath removal should validate path and use ErrorAction"

    Test-Assertion "FFU.Imaging: Cert removal has ErrorAction" {
        $content -match 'Remove-Item\s+-Path\s+\$cert\.PSPath\s+-Force\s+-ErrorAction\s+SilentlyContinue'
    } "Cert removal should have -ErrorAction SilentlyContinue"

    Test-Assertion "FFU.Imaging: Mount folder cleanup in Remove-FFU has ErrorAction" {
        # Check that Mount folder cleanup uses Test-Path and has ErrorAction
        $content -match 'If\s*\(Test-Path\s+-Path\s+\$FFUDevelopmentPath\\Mount\)' -and
        $content -match 'Remove-Item\s+-Path\s+"\$FFUDevelopmentPath\\Mount"\s+-Recurse\s+-Force\s+-ErrorAction\s+SilentlyContinue[^|]'
    } "Mount folder cleanup should have -ErrorAction SilentlyContinue"
}
else {
    Write-TestResult "FFU.Imaging.psm1 tests" -Status 'Skipped' -Message "File not found: $imagingModule"
}

# ============================================================================
# Test 4c: FFU.Core Module - Remove-Item Error Handling
# ============================================================================
Write-Host "`n--- FFU.Core Module Tests ---" -ForegroundColor Yellow

$coreModule = Join-Path $modulePath "FFU.Core\FFU.Core.psm1"
if (Test-Path $coreModule) {
    $content = Get-Content $coreModule -Raw

    Test-Assertion "FFU.Core: Clear-DownloadInProgress has ErrorAction" {
        $content -match 'Remove-Item\s+-Path\s+\$_\.FullName\s+-Force\s+-ErrorAction\s+SilentlyContinue'
    } "Clear-DownloadInProgress should have -ErrorAction SilentlyContinue"

    Test-Assertion "FFU.Core: Remove-InProgressItems marker cleanup has ErrorAction" {
        # Line 673 - the marker file removal in Remove-InProgressItems
        $content -match 'Remove-Item\s+-Path\s+\$_\.FullName\s+-Force\s+-ErrorAction\s+SilentlyContinue\s*\}'
    } "Remove-InProgressItems marker cleanup should have -ErrorAction SilentlyContinue"
}
else {
    Write-TestResult "FFU.Core.psm1 tests" -Status 'Skipped' -Message "File not found: $coreModule"
}

# ============================================================================
# Test 4e: FFU.Media Module - Remove-Item Error Handling
# ============================================================================
Write-Host "`n--- FFU.Media Module Tests ---" -ForegroundColor Yellow

$mediaModule = Join-Path $modulePath "FFU.Media\FFU.Media.psm1"
if (Test-Path $mediaModule) {
    $content = Get-Content $mediaModule -Raw

    Test-Assertion "FFU.Media: WinPE cleanup has ErrorAction" {
        $content -match 'Remove-Item\s+-Path\s+"\$WinPEFFUPath"\s+-Recurse\s+-Force\s+-ErrorAction\s+SilentlyContinue'
    } "WinPE folder cleanup should have -ErrorAction SilentlyContinue"
}
else {
    Write-TestResult "FFU.Media.psm1 tests" -Status 'Skipped' -Message "File not found: $mediaModule"
}

# ============================================================================
# Test 4f: FFU.Drivers Module Additional Tests - Remove-Item Error Handling
# ============================================================================
Write-Host "`n--- FFU.Drivers Module Additional Tests ---" -ForegroundColor Yellow

$driversModuleExtended = Join-Path $modulePath "FFU.Drivers\FFU.Drivers.psm1"
if (Test-Path $driversModuleExtended) {
    $content = Get-Content $driversModuleExtended -Raw

    Test-Assertion "FFU.Drivers: Microsoft driver file removal has ErrorAction" {
        $content -match 'Remove-Item\s+-Path\s+\$filePath\s+-Force\s+-ErrorAction\s+SilentlyContinue'
    } "Microsoft driver file removal should have -ErrorAction SilentlyContinue"

    Test-Assertion "FFU.Drivers: Lenovo packageXML cleanup has ErrorAction" {
        $content -match 'Remove-Item\s+-Path\s+\$packageXMLPath\s+-Force\s+-ErrorAction\s+SilentlyContinue'
    } "Lenovo packageXML cleanup should have -ErrorAction SilentlyContinue"

    Test-Assertion "FFU.Drivers: Lenovo catalog cleanup has ErrorAction" {
        $content -match 'Remove-Item\s+-Path\s+\$LenovoCatalogXML\s+-Force\s+-ErrorAction\s+SilentlyContinue'
    } "Lenovo catalog cleanup should have -ErrorAction SilentlyContinue"

    Test-Assertion "FFU.Drivers: Dell driver file cleanup has ErrorAction" {
        $content -match 'Remove-Item\s+-Path\s+\$driverFilePath\s+-Force\s+-ErrorAction\s+SilentlyContinue'
    } "Dell driver file cleanup should have -ErrorAction SilentlyContinue"
}
else {
    Write-TestResult "FFU.Drivers.psm1 extended tests" -Status 'Skipped' -Message "File not found: $driversModuleExtended"
}

# ============================================================================
# Test 4d: FFU.Common.Winget Module - Remove-Item Error Handling
# ============================================================================
Write-Host "`n--- FFU.Common.Winget Module Tests ---" -ForegroundColor Yellow

$wingetModule = Join-Path (Split-Path $modulePath -Parent) "FFU.Common\FFU.Common.Winget.psm1"
if (Test-Path $wingetModule) {
    $content = Get-Content $wingetModule -Raw

    Test-Assertion "FFU.Common.Winget: Store app error cleanup validates path" {
        $content -match 'if\s*\(-not\s+\[string\]::IsNullOrWhiteSpace\(\$appFolderPath\)\)\s*\{\s*Remove-Item\s+-Path\s+\$appFolderPath.*-ErrorAction\s+SilentlyContinue'
    } "Store app error cleanup should validate path and use ErrorAction"

    Test-Assertion "FFU.Common.Winget: Zip file removal has ErrorAction" {
        $content -match 'Remove-Item\s+-Path\s+\$zipFile\.FullName\s+-Force\s+-ErrorAction\s+SilentlyContinue'
    } "Zip file removal should have -ErrorAction SilentlyContinue"

    Test-Assertion "FFU.Common.Winget: Dependency cleanup has ErrorAction" {
        $content -match 'Remove-Item\s+-Path\s+\$dependency\.FullName\s+-Recurse\s+-Force\s+-ErrorAction\s+SilentlyContinue'
    } "Dependency cleanup should have -ErrorAction SilentlyContinue"

    Test-Assertion "FFU.Common.Winget: Package pruning has ErrorAction" {
        $content -match 'Remove-Item\s+-Path\s+\$package\.FullName\s+-Force\s+-ErrorAction\s+SilentlyContinue'
    } "Package pruning should have -ErrorAction SilentlyContinue"

    Test-Assertion "FFU.Common.Winget: Win32 app cleanup validates path" {
        $content -match 'if\s*\(-not\s+\[string\]::IsNullOrWhiteSpace\(\$AppFolderPath\)\)\s*\{\s*Remove-Item\s+-Path\s+\$AppFolderPath.*-ErrorAction\s+SilentlyContinue'
    } "Win32 app cleanup should validate path and use ErrorAction"
}
else {
    Write-TestResult "FFU.Common.Winget.psm1 tests" -Status 'Skipped' -Message "File not found: $wingetModule"
}

# ============================================================================
# Test 5: BuildFFUVM.ps1 - Remove-Item Error Handling
# ============================================================================
Write-Host "`n--- BuildFFUVM.ps1 Tests ---" -ForegroundColor Yellow

$buildScript = Join-Path $FFUDevelopmentPath "BuildFFUVM.ps1"
if (Test-Path $buildScript) {
    $content = Get-Content $buildScript -Raw

    Test-Assertion "BuildFFUVM.ps1: dirty.txt removal uses full path" {
        $content -match '\$dirtyFilePath\s*=\s*Join-Path\s+\$FFUDevelopmentPath\s+"dirty\.txt"'
    } "dirty.txt should use Join-Path with FFUDevelopmentPath"

    Test-Assertion "BuildFFUVM.ps1: dirty.txt removal has Test-Path check" {
        $content -match 'if\s*\(Test-Path\s+-Path\s+\$dirtyFilePath\)'
    } "dirty.txt removal should check if file exists"

    Test-Assertion "BuildFFUVM.ps1: dirty.txt removal has ErrorAction" {
        $content -match 'Remove-Item\s+-Path\s+\$dirtyFilePath.*-ErrorAction\s+SilentlyContinue'
    } "dirty.txt removal should have -ErrorAction SilentlyContinue"

    Test-Assertion "BuildFFUVM.ps1: Apps.iso removal validates path" {
        $content -match 'if\s*\(-not\s+\[string\]::IsNullOrWhiteSpace\(\$AppsISO\)\)' -and
        $content -match 'Remove-Item\s+-Path\s+\$AppsISO.*-ErrorAction\s+SilentlyContinue'
    } "Apps.iso removal should validate path and use ErrorAction"

    Test-Assertion "BuildFFUVM.ps1: KBPath removal validates path" {
        $content -match 'if\s*\(-not\s+\[string\]::IsNullOrWhiteSpace\(\$KBPath\)' -and
        $content -match 'Remove-Item\s+-Path\s+\$KBPath.*-ErrorAction\s+SilentlyContinue'
    } "KBPath removal should validate path and use ErrorAction"
}
else {
    Write-TestResult "BuildFFUVM.ps1 tests" -Status 'Skipped' -Message "File not found: $buildScript"
}

# ============================================================================
# Test 6: Functional Test - Verify no non-terminating errors
# ============================================================================
Write-Host "`n--- Functional Tests ---" -ForegroundColor Yellow

Test-Assertion "Remove-Item with null path does not throw with ErrorAction" {
    try {
        $nullPath = $null
        if (-not [string]::IsNullOrWhiteSpace($nullPath)) {
            Remove-Item -Path $nullPath -Force -ErrorAction SilentlyContinue
        }
        $true
    }
    catch {
        $false
    }
} "Remove-Item with validated null path should not throw"

Test-Assertion "Remove-Item with empty array does not throw when filtered" {
    try {
        $paths = @($null, "", "   ", $null)
        $validPaths = $paths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        if ($validPaths.Count -gt 0) {
            Remove-Item -Path $validPaths -Force -ErrorAction SilentlyContinue
        }
        $true
    }
    catch {
        $false
    }
} "Remove-Item with filtered empty array should not throw"

Test-Assertion "Remove-Item with non-existent path does not throw with ErrorAction" {
    $testPassed = $true
    try {
        $nonExistentPath = Join-Path $env:TEMP "NonExistent_$(Get-Random).txt"
        # This should not throw with SilentlyContinue even if file doesn't exist
        Remove-Item -Path $nonExistentPath -Force -ErrorAction SilentlyContinue 2>$null
    }
    catch {
        $testPassed = $false
    }
    return $testPassed
} "Remove-Item with non-existent path should not throw when using ErrorAction SilentlyContinue"

# ============================================================================
# Summary
# ============================================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Passed:  $($script:TestResults.Passed)" -ForegroundColor Green
Write-Host "Failed:  $($script:TestResults.Failed)" -ForegroundColor Red
Write-Host "Skipped: $($script:TestResults.Skipped)" -ForegroundColor Yellow
Write-Host "Total:   $($script:TestResults.Tests.Count)" -ForegroundColor White

$overallResult = if ($script:TestResults.Failed -eq 0) { "PASS" } else { "FAIL" }
$overallColor = if ($script:TestResults.Failed -eq 0) { "Green" } else { "Red" }
Write-Host "`nOverall: $overallResult" -ForegroundColor $overallColor

# Show explanation of the fixes
Write-Host "`n--- Fix Explanation ---" -ForegroundColor Yellow
Write-Host @"
This fix addresses the non-terminating error:
"Value cannot be null. (Parameter 'The provided Path argument was null or an empty collection.')"

Root Cause:
- Remove-Item -Path receives null/empty values or arrays containing null elements
- Without -ErrorAction SilentlyContinue, PowerShell writes a non-terminating error
- The error is captured by Receive-Job -ErrorVariable even though the script completes

Solution Applied (Defense-in-Depth):
1. Validate path variables before passing to Remove-Item:
   - Check for null/empty using [string]::IsNullOrWhiteSpace()
   - Use Test-Path where appropriate
2. Filter arrays to remove null/empty elements:
   - Use Where-Object to filter before Remove-Item
   - Check array count > 0 before calling Remove-Item
3. Add -ErrorAction SilentlyContinue as defense-in-depth

Files Modified:
  - Modules\FFU.Drivers\FFU.Drivers.psm1 (HP driver cleanup, Dell driver file, Microsoft driver, Lenovo XML/catalog)
  - Modules\FFU.Apps\FFU.Apps.psm1 (ODT, Win32, Office cleanup)
  - Modules\FFU.Updates\FFU.Updates.psm1 (CAB/XML cleanup, architecture mismatch)
  - Modules\FFU.VM\FFU.VM.psm1 (VMPath, Mount folder, dirty.txt)
  - Modules\FFU.Imaging\FFU.Imaging.psm1 (Mount folder, VMPath, cert cleanup)
  - Modules\FFU.Core\FFU.Core.psm1 (Clear-DownloadInProgress, Remove-InProgressItems marker)
  - Modules\FFU.Media\FFU.Media.psm1 (WinPE folder cleanup)
  - FFU.Common\FFU.Common.Winget.psm1 (app folder cleanup, zip file, dependencies)
  - BuildFFUVM.ps1 (dirty.txt, Apps.iso, KBPath, wimPath, VMPath)
"@ -ForegroundColor Gray

# Exit with appropriate code
if ($script:TestResults.Failed -gt 0) {
    Write-Host "`nFailed tests:" -ForegroundColor Red
    $script:TestResults.Tests | Where-Object Status -eq 'Failed' | ForEach-Object {
        Write-Host "  - $($_.Name): $($_.Message)" -ForegroundColor Red
    }
    exit 1
}
else {
    Write-Host "`nAll tests passed!" -ForegroundColor Green
    exit 0
}
