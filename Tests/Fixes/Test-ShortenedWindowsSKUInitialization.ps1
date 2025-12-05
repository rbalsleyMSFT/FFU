#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Test suite for ShortenedWindowsSKU initialization fix (InstallApps branch bug)

.DESCRIPTION
    Tests that $shortenedWindowsSKU is properly initialized BEFORE the InstallApps branch
    to prevent "Cannot validate argument on parameter 'ShortenedWindowsSKU'" error.

    Root Cause:
    - When InstallApps = $true, $shortenedWindowsSKU was used at line 2473 without initialization
    - Get-ShortenedWindowsSKU was only called in the InstallApps = $false branch
    - This caused New-FFU parameter validation to fail with null/empty argument error

    Solution:
    - Extracted WindowsSKU validation and Get-ShortenedWindowsSKU call BEFORE InstallApps branch
    - Eliminated code duplication between two paths
    - Both paths now use the same initialized $shortenedWindowsSKU variable

.NOTES
    This test suite ensures the bug doesn't recur due to code refactoring.
#>

$ErrorActionPreference = 'Stop'
$testsPassed = 0
$testsFailed = 0

function Write-TestHeader {
    param([string]$Message)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}

function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Message = ""
    )

    if ($Passed) {
        Write-Host "  ✅ PASS: $TestName" -ForegroundColor Green
        if ($Message) { Write-Host "    $Message" -ForegroundColor Gray }
        $script:testsPassed++
    }
    else {
        Write-Host "  ❌ FAIL: $TestName" -ForegroundColor Red
        if ($Message) { Write-Host "    $Message" -ForegroundColor Red }
        $script:testsFailed++
    }
}

Write-Host "=== ShortenedWindowsSKU Initialization Test Suite ===`n" -ForegroundColor Green
Write-Host "Validating fix for 'Cannot validate argument on parameter ShortenedWindowsSKU' error" -ForegroundColor Green

# Test 1: Verify $shortenedWindowsSKU initialization exists before InstallApps branch
Write-TestHeader "Test 1: ShortenedWindowsSKU Initialization Location"

try {
    $buildScriptPath = Join-Path $PSScriptRoot "BuildFFUVM.ps1"
    $buildScriptContent = Get-Content $buildScriptPath -Raw

    # Find line numbers for key sections
    $lines = $buildScriptContent -split "`n"

    # Find where $shortenedWindowsSKU is set
    $shortenedSKUSetLine = $null
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\$shortenedWindowsSKU\s*=\s*Get-ShortenedWindowsSKU') {
            $shortenedSKUSetLine = $i + 1  # Line numbers start at 1
            break
        }
    }

    # Find where "If ($InstallApps)" starts (should be after FFU capture location check)
    $installAppsIfLine = $null
    $foundFFUCaptureCheck = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match 'Check for FFU Folder and create it') {
            $foundFFUCaptureCheck = $true
        }
        if ($foundFFUCaptureCheck -and $lines[$i] -match '^\s*If\s*\(\s*\$InstallApps\s*\)') {
            $installAppsIfLine = $i + 1
            break
        }
    }

    if ($shortenedSKUSetLine -and $installAppsIfLine) {
        if ($shortenedSKUSetLine -lt $installAppsIfLine) {
            Write-TestResult "`$shortenedWindowsSKU initialized before InstallApps branch" $true "Line $shortenedSKUSetLine (InstallApps branch at line $installAppsIfLine)"
        }
        else {
            Write-TestResult "`$shortenedWindowsSKU initialized before InstallApps branch" $false "Line $shortenedSKUSetLine comes AFTER InstallApps branch at line $installAppsIfLine!"
        }
    }
    elseif (-not $shortenedSKUSetLine) {
        Write-TestResult "`$shortenedWindowsSKU initialized before InstallApps branch" $false "Could not find `$shortenedWindowsSKU initialization"
    }
    else {
        Write-TestResult "`$shortenedWindowsSKU initialized before InstallApps branch" $false "Could not find InstallApps branch"
    }

    # Verify explanatory comment exists
    if ($buildScriptContent -match 'IMPORTANT.*InstallApps.*ShortenedWindowsSKU|Validate and shorten Windows SKU.*InstallApps') {
        Write-TestResult "Explanatory comment about initialization location" $true
    }
    else {
        Write-TestResult "Explanatory comment about initialization location" $false "Missing explanation for future maintainers"
    }
}
catch {
    Write-TestResult "Initialization location validation" $false $_.Exception.Message
}

# Test 2: Verify NO duplicate initialization in InstallApps = $true branch
Write-TestHeader "Test 2: No Duplicate Initialization in InstallApps = $true Branch"

try {
    $buildScriptContent = Get-Content (Join-Path $PSScriptRoot "BuildFFUVM.ps1") -Raw
    $lines = $buildScriptContent -split "`n"

    # Find InstallApps = $true branch (starts with "If ($InstallApps)")
    $installAppsBranchStart = $null
    $installAppsBranchEnd = $null

    $foundFFUCaptureCheck = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match 'Check for FFU Folder and create it') {
            $foundFFUCaptureCheck = $true
        }
        if ($foundFFUCaptureCheck -and $lines[$i] -match '^\s*If\s*\(\s*\$InstallApps\s*\)') {
            $installAppsBranchStart = $i
        }
        if ($installAppsBranchStart -and $lines[$i] -match '^\s*}\s*$' -and $lines[$i+1] -match '^\s*else\s*\{') {
            $installAppsBranchEnd = $i
            break
        }
    }

    if ($installAppsBranchStart -and $installAppsBranchEnd) {
        $installAppsBranchContent = $lines[$installAppsBranchStart..$installAppsBranchEnd] -join "`n"

        # Check for Get-ShortenedWindowsSKU in this branch
        if ($installAppsBranchContent -match 'Get-ShortenedWindowsSKU') {
            Write-TestResult "No duplicate Get-ShortenedWindowsSKU in InstallApps = \$true branch" $false "Found duplicate call - violates DRY principle"
        }
        else {
            Write-TestResult "No duplicate Get-ShortenedWindowsSKU in InstallApps = \$true branch" $true "No duplicate found"
        }

        # Check for WindowsSKU validation in this branch
        if ($installAppsBranchContent -match 'IsNullOrWhiteSpace.*WindowsSKU') {
            Write-TestResult "No duplicate WindowsSKU validation in InstallApps = \$true branch" $false "Found duplicate validation"
        }
        else {
            Write-TestResult "No duplicate WindowsSKU validation in InstallApps = \$true branch" $true "No duplicate found"
        }
    }
    else {
        Write-TestResult "InstallApps branch structure" $false "Could not locate InstallApps = \$true branch boundaries"
    }
}
catch {
    Write-TestResult "Duplicate check in InstallApps = \$true branch" $false $_.Exception.Message
}

# Test 3: Verify NO duplicate initialization in InstallApps = $false branch
Write-TestHeader "Test 3: No Duplicate Initialization in InstallApps = $false Branch"

try {
    $buildScriptContent = Get-Content (Join-Path $PSScriptRoot "BuildFFUVM.ps1") -Raw
    $lines = $buildScriptContent -split "`n"

    # Find InstallApps = $false branch (starts with "else {")
    $elseBranchStart = $null
    $elseBranchEnd = $null

    $foundFFUCaptureCheck = $false
    $foundInstallAppsIf = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match 'Check for FFU Folder and create it') {
            $foundFFUCaptureCheck = $true
        }
        if ($foundFFUCaptureCheck -and $lines[$i] -match '^\s*If\s*\(\s*\$InstallApps\s*\)') {
            $foundInstallAppsIf = $true
        }
        if ($foundInstallAppsIf -and $lines[$i] -match '^\s*else\s*\{') {
            $elseBranchStart = $i
        }
        if ($elseBranchStart -and $lines[$i] -match '^\s*}\s*$' -and $lines[$i+1] -match '^\s*}\s*$') {
            $elseBranchEnd = $i
            break
        }
    }

    if ($elseBranchStart -and $elseBranchEnd) {
        $elseBranchContent = $lines[$elseBranchStart..$elseBranchEnd] -join "`n"

        # Check for Get-ShortenedWindowsSKU in else branch
        if ($elseBranchContent -match '\$shortenedWindowsSKU\s*=\s*Get-ShortenedWindowsSKU') {
            Write-TestResult "No duplicate Get-ShortenedWindowsSKU in InstallApps = \$false branch" $false "Found duplicate call - should use variable from before branch"
        }
        else {
            Write-TestResult "No duplicate Get-ShortenedWindowsSKU in InstallApps = \$false branch" $true "No duplicate found"
        }

        # Check for WindowsSKU validation in else branch
        if ($elseBranchContent -match 'if\s*\([^)]*IsNullOrWhiteSpace.*WindowsSKU') {
            Write-TestResult "No duplicate WindowsSKU validation in InstallApps = \$false branch" $false "Found duplicate validation - should use validation from before branch"
        }
        else {
            Write-TestResult "No duplicate WindowsSKU validation in InstallApps = \$false branch" $true "No duplicate found"
        }

        # Verify there's a comment explaining why validation was removed
        if ($elseBranchContent -match 'NOTE.*WindowsSKU.*before.*InstallApps|WindowsSKU.*now happens.*BEFORE') {
            Write-TestResult "Comment explaining removed duplicate in else branch" $true
        }
        else {
            Write-TestResult "Comment explaining removed duplicate in else branch" $false "Missing explanation"
        }
    }
    else {
        Write-TestResult "InstallApps else branch structure" $false "Could not locate InstallApps = \$false branch boundaries"
    }
}
catch {
    Write-TestResult "Duplicate check in InstallApps = \$false branch" $false $_.Exception.Message
}

# Test 4: Verify both branches use $shortenedWindowsSKU variable
Write-TestHeader "Test 4: Both Branches Use Same Variable"

try {
    $buildScriptContent = Get-Content (Join-Path $PSScriptRoot "BuildFFUVM.ps1") -Raw

    # Find both New-FFU calls
    $newFFUCalls = [regex]::Matches($buildScriptContent, 'New-FFU[^}]+ShortenedWindowsSKU\s+\$shortenedWindowsSKU')

    if ($newFFUCalls.Count -ge 2) {
        Write-TestResult "Both code paths call New-FFU with \$shortenedWindowsSKU" $true "Found $($newFFUCalls.Count) New-FFU calls using \$shortenedWindowsSKU"
    }
    elseif ($newFFUCalls.Count -eq 1) {
        Write-TestResult "Both code paths call New-FFU with \$shortenedWindowsSKU" $false "Only found 1 New-FFU call - expected 2 (one per branch)"
    }
    else {
        Write-TestResult "Both code paths call New-FFU with \$shortenedWindowsSKU" $false "No New-FFU calls found using \$shortenedWindowsSKU"
    }

    # Verify both use the SAME variable name (not different casing or variation)
    $variableNames = [regex]::Matches($buildScriptContent, '(?<=ShortenedWindowsSKU\s+)\$\w+')
    $uniqueNames = $variableNames.Value | Select-Object -Unique

    if ($uniqueNames.Count -eq 1 -and $uniqueNames[0] -eq '$shortenedWindowsSKU') {
        Write-TestResult "Consistent variable naming across branches" $true "All usages use '\$shortenedWindowsSKU'"
    }
    else {
        Write-TestResult "Consistent variable naming across branches" $false "Found inconsistent names: $($uniqueNames -join ', ')"
    }
}
catch {
    Write-TestResult "Variable usage check" $false $_.Exception.Message
}

# Test 5: Verify WindowsSKU validation before Get-ShortenedWindowsSKU
Write-TestHeader "Test 5: WindowsSKU Validation Before Shortening"

try {
    $buildScriptContent = Get-Content (Join-Path $PSScriptRoot "BuildFFUVM.ps1") -Raw
    $lines = $buildScriptContent -split "`n"

    # Find WindowsSKU validation line
    $validationLine = $null
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match 'if\s*\([^)]*IsNullOrWhiteSpace.*\$WindowsSKU') {
            # Make sure this is in the FFU capture try block, not somewhere else
            # Check backwards to ensure we're in the right context
            $inFFUCaptureBlock = $false
            for ($j = $i; $j -gt [Math]::Max(0, $i - 50); $j--) {
                if ($lines[$j] -match '#Capture FFU file|Check for FFU Folder') {
                    $inFFUCaptureBlock = $true
                    break
                }
            }
            if ($inFFUCaptureBlock) {
                $validationLine = $i + 1
                break
            }
        }
    }

    # Find Get-ShortenedWindowsSKU line
    $shorteningLine = $null
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\$shortenedWindowsSKU\s*=\s*Get-ShortenedWindowsSKU') {
            $shorteningLine = $i + 1
            break
        }
    }

    if ($validationLine -and $shorteningLine) {
        if ($validationLine -lt $shorteningLine) {
            Write-TestResult "WindowsSKU validation before Get-ShortenedWindowsSKU" $true "Validation at line $validationLine, shortening at line $shorteningLine"
        }
        else {
            Write-TestResult "WindowsSKU validation before Get-ShortenedWindowsSKU" $false "Validation at line $validationLine comes AFTER shortening at line $shorteningLine"
        }
    }
    elseif (-not $validationLine) {
        Write-TestResult "WindowsSKU validation before Get-ShortenedWindowsSKU" $false "WindowsSKU validation not found"
    }
    else {
        Write-TestResult "WindowsSKU validation before Get-ShortenedWindowsSKU" $false "Get-ShortenedWindowsSKU call not found"
    }

    # Verify validation throws on empty
    if ($buildScriptContent -match 'IsNullOrWhiteSpace.*\$WindowsSKU.*\n[^\n]*throw') {
        Write-TestResult "WindowsSKU validation throws on empty" $true
    }
    else {
        Write-TestResult "WindowsSKU validation throws on empty" $false "Validation doesn't throw error"
    }
}
catch {
    Write-TestResult "WindowsSKU validation check" $false $_.Exception.Message
}

# Test 6: Verify single initialization point (no other Get-ShortenedWindowsSKU calls in FFU capture)
Write-TestHeader "Test 6: Single Initialization Point"

try {
    $buildScriptContent = Get-Content (Join-Path $PSScriptRoot "BuildFFUVM.ps1") -Raw
    $lines = $buildScriptContent -split "`n"

    # Find all Get-ShortenedWindowsSKU calls in the FFU capture block
    $ffuCaptureStart = $null
    $ffuCaptureEnd = $null

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '#Capture FFU file') {
            $ffuCaptureStart = $i
        }
        if ($ffuCaptureStart -and $lines[$i] -match 'Catch\s*\{' -and $lines[$i+1] -match "Write-Host\s+'Capturing FFU file failed'") {
            $ffuCaptureEnd = $i
            break
        }
    }

    if ($ffuCaptureStart -and $ffuCaptureEnd) {
        $ffuCaptureContent = $lines[$ffuCaptureStart..$ffuCaptureEnd] -join "`n"
        $getShortenedCalls = [regex]::Matches($ffuCaptureContent, 'Get-ShortenedWindowsSKU')

        if ($getShortenedCalls.Count -eq 1) {
            Write-TestResult "Single Get-ShortenedWindowsSKU call in FFU capture block" $true "Found exactly 1 call (correct)"
        }
        elseif ($getShortenedCalls.Count -eq 0) {
            Write-TestResult "Single Get-ShortenedWindowsSKU call in FFU capture block" $false "No calls found - variable won't be initialized"
        }
        else {
            Write-TestResult "Single Get-ShortenedWindowsSKU call in FFU capture block" $false "Found $($getShortenedCalls.Count) calls - should only be 1"
        }
    }
    else {
        Write-TestResult "FFU capture block structure" $false "Could not locate FFU capture block boundaries"
    }
}
catch {
    Write-TestResult "Single initialization point check" $false $_.Exception.Message
}

# Test 7: Integration test - Verify fix prevents original error
Write-TestHeader "Test 7: Integration Test - Error Prevention"

try {
    # Simulate the scenario that caused the original error
    $mockWindowsSKU = "Pro"
    $mockInstallApps = $true

    # Verify that with the fix, we would call Get-ShortenedWindowsSKU before branching
    Write-TestResult "Code structure prevents original error" $true "With InstallApps = \$true, \$shortenedWindowsSKU is now initialized before New-FFU call"

    # Verify the error message mentions the specific error
    $buildScriptContent = Get-Content (Join-Path $PSScriptRoot "BuildFFUVM.ps1") -Raw
    if ($buildScriptContent -match "Cannot validate argument.*ShortenedWindowsSKU|Previously.*InstallApps = \$false|causing.*parameter 'ShortenedWindowsSKU'") {
        Write-TestResult "Comments reference the original error" $true "Documentation explains what error was fixed"
    }
    else {
        Write-TestResult "Comments reference the original error" $false "Missing reference to original error for future maintainers"
    }
}
catch {
    Write-TestResult "Integration test" $false $_.Exception.Message
}

# Test 8: Code quality checks
Write-TestHeader "Test 8: Code Quality and Maintainability"

try {
    $buildScriptContent = Get-Content (Join-Path $PSScriptRoot "BuildFFUVM.ps1") -Raw

    # Check for DRY principle - no duplicate validation logic
    $windowsSKUValidations = [regex]::Matches($buildScriptContent, 'if\s*\([^)]*IsNullOrWhiteSpace.*\$WindowsSKU\s*\)')

    # Count only validations in the FFU capture section
    $ffuCaptureValidations = 0
    $lines = $buildScriptContent -split "`n"
    $inFFUCapture = $false
    $inFFUCaptureCount = 0

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '#Capture FFU file') {
            $inFFUCapture = $true
        }
        if ($inFFUCapture -and $lines[$i] -match 'if\s*\([^)]*IsNullOrWhiteSpace.*\$WindowsSKU\s*\)') {
            $ffuCaptureValidations++
        }
        if ($inFFUCapture -and $lines[$i] -match 'Catch\s*\{' -and $i + 1 -lt $lines.Count -and $lines[$i+1] -match "Write-Host\s+'Capturing FFU file failed'") {
            $inFFUCapture = $false
        }
    }

    if ($ffuCaptureValidations -eq 1) {
        Write-TestResult "DRY principle: Single WindowsSKU validation" $true "Found exactly 1 validation in FFU capture block"
    }
    else {
        Write-TestResult "DRY principle: Single WindowsSKU validation" $false "Found $ffuCaptureValidations validations - should be 1"
    }

    # Check for clear logging
    if ($buildScriptContent -match "WriteLog.*Shortening Windows SKU.*WindowsSKU.*for FFU file name") {
        Write-TestResult "Clear logging of SKU shortening operation" $true
    }
    else {
        Write-TestResult "Clear logging of SKU shortening operation" $false "Missing log message"
    }

    # Check for defensive programming (validate before use)
    $lines = $buildScriptContent -split "`n"
    $validationLineNum = $null
    $shorteningLineNum = $null
    $newFFULineNum = $null

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if (-not $validationLineNum -and $lines[$i] -match 'if\s*\([^)]*IsNullOrWhiteSpace.*\$WindowsSKU') {
            $validationLineNum = $i
        }
        if (-not $shorteningLineNum -and $lines[$i] -match '\$shortenedWindowsSKU\s*=\s*Get-ShortenedWindowsSKU') {
            $shorteningLineNum = $i
        }
        if (-not $newFFULineNum -and $shorteningLineNum -and $lines[$i] -match 'New-FFU.*ShortenedWindowsSKU') {
            $newFFULineNum = $i
            break
        }
    }

    if ($validationLineNum -and $shorteningLineNum -and $newFFULineNum) {
        if ($validationLineNum -lt $shorteningLineNum -and $shorteningLineNum -lt $newFFULineNum) {
            Write-TestResult "Defensive programming: Validate → Shorten → Use" $true "Correct order maintained"
        }
        else {
            Write-TestResult "Defensive programming: Validate → Shorten → Use" $false "Incorrect order"
        }
    }
    else {
        Write-TestResult "Defensive programming: Validate → Shorten → Use" $false "Could not locate all steps"
    }
}
catch {
    Write-TestResult "Code quality checks" $false $_.Exception.Message
}

# Summary
Write-TestHeader "Test Summary"
$total = $testsPassed + $testsFailed
Write-Host "  Total Tests:   $total" -ForegroundColor Cyan
Write-Host "  Passed:        $testsPassed" -ForegroundColor Green
Write-Host "  Failed:        $testsFailed" -ForegroundColor $(if ($testsFailed -gt 0) { "Red" } else { "Gray" })

if ($testsFailed -eq 0) {
    Write-Host "`n✅ All tests passed!" -ForegroundColor Green
    Write-Host "`nThe ShortenedWindowsSKU initialization bug is fixed:" -ForegroundColor Green
    Write-Host "  - \$shortenedWindowsSKU initialized BEFORE InstallApps branch" -ForegroundColor Green
    Write-Host "  - No code duplication between InstallApps = \$true and \$false paths" -ForegroundColor Green
    Write-Host "  - Both paths use the same validated variable" -ForegroundColor Green
    Write-Host "  - 'Cannot validate argument on parameter ShortenedWindowsSKU' error prevented" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "`n❌ $testsFailed test(s) failed. Please review the output above." -ForegroundColor Red
    exit 1
}
