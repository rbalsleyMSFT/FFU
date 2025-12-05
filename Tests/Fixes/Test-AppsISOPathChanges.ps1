<#
.SYNOPSIS
    Test script to verify Apps.iso path updates

.DESCRIPTION
    Validates that all references to Apps.iso have been updated
    to use the new path in the Apps subfolder.
#>

$ErrorActionPreference = 'Continue'
$testsPassed = 0
$testsFailed = 0

Write-Host "`n=====================================" -ForegroundColor Cyan
Write-Host "Apps.iso Path Update Verification" -ForegroundColor Cyan
Write-Host "=====================================`n" -ForegroundColor Cyan

# Test 1: Verify BuildFFUVM.ps1 has updated path
Write-Host "Test 1: BuildFFUVM.ps1 default path..." -NoNewline
$content = Get-Content "$PSScriptRoot\BuildFFUVM.ps1" -Raw
if ($content -match '\$AppsISO = "\$FFUDevelopmentPath\\Apps\\Apps\.iso"') {
    Write-Host " PASSED" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host " FAILED" -ForegroundColor Red
    $testsFailed++
}

# Test 2: Verify FFUUI.Core.Config.psm1 has updated path
Write-Host "Test 2: FFUUI.Core.Config.psm1..." -NoNewline
$content = Get-Content "$PSScriptRoot\FFUUI.Core\FFUUI.Core.Config.psm1" -Raw
if ($content -match "Join-Path \`$rootPath 'Apps\\Apps\.iso'") {
    Write-Host " PASSED" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host " FAILED" -ForegroundColor Red
    $testsFailed++
}

# Test 3: Verify Diagnose-UpdateDownloadIssue.ps1 has updated path
Write-Host "Test 3: Diagnose-UpdateDownloadIssue.ps1..." -NoNewline
$content = Get-Content "$PSScriptRoot\Diagnose-UpdateDownloadIssue.ps1" -Raw
if ($content -match 'Join-Path \$FFUDevelopmentPath "Apps\\Apps\.iso"') {
    Write-Host " PASSED" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host " FAILED" -ForegroundColor Red
    $testsFailed++
}

# Test 4: Verify FFU.Apps.psm1 documentation example
Write-Host "Test 4: FFU.Apps.psm1 documentation..." -NoNewline
$content = Get-Content "$PSScriptRoot\Modules\FFU.Apps\FFU.Apps.psm1" -Raw
if ($content -match 'AppsISO "C:\\FFUDevelopment\\Apps\\Apps\.iso"') {
    Write-Host " PASSED" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host " FAILED" -ForegroundColor Red
    $testsFailed++
}

# Test 5: Verify FFU.VM.psm1 documentation example (New-FFUVM)
Write-Host "Test 5: FFU.VM.psm1 New-FFUVM example..." -NoNewline
$content = Get-Content "$PSScriptRoot\Modules\FFU.VM\FFU.VM.psm1" -Raw
if ($content -match 'AppsISO "C:\\FFU\\Apps\\Apps\.iso"') {
    Write-Host " PASSED" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host " FAILED" -ForegroundColor Red
    $testsFailed++
}

# Test 6: Verify no old paths remain (Apps.iso in root)
Write-Host "Test 6: No old paths remain..." -NoNewline
$oldPathPattern = '\\Apps\.iso[^\\]'  # Apps.iso NOT followed by backslash (i.e., not in Apps folder)
$buildFFU = Get-Content "$PSScriptRoot\BuildFFUVM.ps1" -Raw
$ffuuiConfig = Get-Content "$PSScriptRoot\FFUUI.Core\FFUUI.Core.Config.psm1" -Raw
$diagnose = Get-Content "$PSScriptRoot\Diagnose-UpdateDownloadIssue.ps1" -Raw

# Check if old pattern exists (excluding the Apps\Apps.iso pattern)
$hasOldPath = $false
if ($buildFFU -match 'FFUDevelopmentPath\\Apps\.iso[^\\]') { $hasOldPath = $true }
if ($ffuuiConfig -match "rootPath 'Apps\.iso'") { $hasOldPath = $true }
if ($diagnose -match 'FFUDevelopmentPath "Apps\.iso"') { $hasOldPath = $true }

if (-not $hasOldPath) {
    Write-Host " PASSED" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host " FAILED" -ForegroundColor Red
    $testsFailed++
}

# Test 7: Syntax validation of modified files
Write-Host "Test 7: PowerShell syntax validation..." -NoNewline
$syntaxErrors = @()
$filesToCheck = @(
    "$PSScriptRoot\BuildFFUVM.ps1",
    "$PSScriptRoot\FFUUI.Core\FFUUI.Core.Config.psm1",
    "$PSScriptRoot\Diagnose-UpdateDownloadIssue.ps1",
    "$PSScriptRoot\Modules\FFU.Apps\FFU.Apps.psm1",
    "$PSScriptRoot\Modules\FFU.VM\FFU.VM.psm1"
)

foreach ($file in $filesToCheck) {
    $errors = $null
    $content = Get-Content $file -Raw
    [void][System.Management.Automation.PSParser]::Tokenize($content, [ref]$errors)
    if ($errors) {
        $syntaxErrors += "$($file | Split-Path -Leaf): $($errors.Count) errors"
    }
}

if ($syntaxErrors.Count -eq 0) {
    Write-Host " PASSED" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host " FAILED" -ForegroundColor Red
    $syntaxErrors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    $testsFailed++
}

# Summary
Write-Host "`n=====================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Passed: $testsPassed" -ForegroundColor Green
Write-Host "Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -gt 0) { "Red" } else { "Green" })
Write-Host "Total:  $($testsPassed + $testsFailed)" -ForegroundColor White

if ($testsFailed -eq 0) {
    Write-Host "`nAll Apps.iso path updates verified successfully!" -ForegroundColor Green
} else {
    Write-Host "`nSome tests failed. Please review the changes." -ForegroundColor Red
}

return [PSCustomObject]@{
    Passed = $testsPassed
    Failed = $testsFailed
    Total = $testsPassed + $testsFailed
}
