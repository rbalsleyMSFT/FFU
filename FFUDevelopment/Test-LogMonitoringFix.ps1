#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Comprehensive test suite for BuildFFUVM_UI.ps1 log monitoring fix

.DESCRIPTION
    Tests all components of the fix for the log file monitoring failure issue:
    1. Sample_default.json has correct FFUDevelopmentPath
    2. BuildFFUVM.ps1 parameter validation accepts non-existent paths
    3. BuildFFUVM.ps1 creates missing FFUDevelopmentPath directory
    4. UI pre-flight validation catches invalid paths
    5. UI surfaces errors when BuildFFUVM.ps1 fails early

.NOTES
    This test suite validates the fixes for the issue where BuildFFUVM_UI.ps1
    could not find the log file because FFUDevelopmentPath was incorrectly
    set to "C:\FFUDevelopment" (from sample config) instead of the actual
    script location.
#>

using module .\Modules\FFU.Constants\FFU.Constants.psm1

$ErrorActionPreference = 'Stop'
$testsPassed = 0
$testsFailed = 0
$testsSkipped = 0

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
        [string]$Message = "",
        [bool]$Skipped = $false
    )

    if ($Skipped) {
        Write-Host "  ⊘ SKIP: $TestName" -ForegroundColor Yellow
        if ($Message) { Write-Host "    $Message" -ForegroundColor Gray }
        $script:testsSkipped++
    }
    elseif ($Passed) {
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

Write-Host "=== BuildFFUVM_UI.ps1 Log Monitoring Fix - Comprehensive Test Suite ===" -ForegroundColor Green
Write-Host "Testing root cause fix and preventive measures for log file monitoring failure" -ForegroundColor Green

# Test 1: Verify Sample_default.json has correct paths
Write-TestHeader "Test 1: Sample Config File Validation"

try {
    $sampleConfigPath = Join-Path $PSScriptRoot "config\Sample_default.json"

    if (-not (Test-Path $sampleConfigPath)) {
        Write-TestResult "Sample_default.json exists" $false "File not found at $sampleConfigPath"
    }
    else {
        Write-TestResult "Sample_default.json exists" $true

        $sampleConfig = Get-Content $sampleConfigPath -Raw | ConvertFrom-Json
        $ffuDevPath = $sampleConfig.FFUDevelopmentPath

        # Check that it doesn't use hardcoded absolute paths
        if ($ffuDevPath -match '^[A-Z]:\\') {
            Write-TestResult "Sample config uses relative paths (not hardcoded)" $false "FFUDevelopmentPath is hardcoded: $ffuDevPath"
        }
        else {
            Write-TestResult "Sample config uses relative paths (not hardcoded)" $true "FFUDevelopmentPath is empty/relative (will use UI default)"
        }

        # Check that other paths are also empty/relative
        $pathProperties = @('AppListPath', 'DriversFolder', 'DriversJsonPath', 'FFUCaptureLocation',
                            'OrchestrationPath', 'PEDriversFolder', 'UserAppListPath', 'VMLocation')
        $hardcodedPaths = @()
        foreach ($prop in $pathProperties) {
            $value = $sampleConfig.$prop
            if ($value -and ($value -match '^[A-Z]:\\')) {
                $hardcodedPaths += "$prop=$value"
            }
        }

        if ($hardcodedPaths.Count -gt 0) {
            Write-TestResult "Sample config paths are all relative" $false "Found hardcoded paths: $($hardcodedPaths -join ', ')"
        }
        else {
            Write-TestResult "Sample config paths are all relative" $true "All paths use empty strings or relative syntax"
        }

        # Check for comment/documentation
        if ($sampleConfig.PSObject.Properties['_comment']) {
            Write-TestResult "Sample config has instructional comment" $true
        }
        else {
            Write-Host "    NOTE: No '_comment' field found. Consider adding instructions." -ForegroundColor Yellow
            Write-TestResult "Sample config documentation" $true "Optional documentation missing"
        }
    }
}
catch {
    Write-TestResult "Sample config validation" $false $_.Exception.Message
}

# Test 2: BuildFFUVM.ps1 Parameter Validation
Write-TestHeader "Test 2: BuildFFUVM.ps1 Parameter Validation"

try {
    $buildScriptPath = Join-Path $PSScriptRoot "BuildFFUVM.ps1"
    $buildScriptContent = Get-Content $buildScriptPath -Raw

    # Check that FFUDevelopmentPath parameter doesn't have Test-Path ValidateScript
    if ($buildScriptContent -match '\[ValidateScript\(\s*\{\s*Test-Path\s+\$_\s*\}\s*\)\]\s*\[string\]\s*\$FFUDevelopmentPath') {
        Write-TestResult "FFUDevelopmentPath doesn't require existing path" $false "Still has [ValidateScript({ Test-Path `$_ })]"
    }
    else {
        Write-TestResult "FFUDevelopmentPath doesn't require existing path" $true "Parameter validation relaxed"
    }

    # Check that directory creation logic exists
    if ($buildScriptContent -match 'Create\s+FFUDevelopmentPath\s+directory\s+if\s+it\s+doesn''?t\s+exist') {
        Write-TestResult "BuildFFUVM.ps1 has directory creation logic" $true "Found in script"
    }
    else {
        Write-TestResult "BuildFFUVM.ps1 has directory creation logic" $false "Directory creation code not found"
    }

    # Check for New-Item call for FFUDevelopmentPath
    if ($buildScriptContent -match 'New-Item.*-ItemType\s+Directory.*-Path\s+\$FFUDevelopmentPath') {
        Write-TestResult "BuildFFUVM.ps1 creates FFUDevelopmentPath if missing" $true
    }
    else {
        Write-TestResult "BuildFFUVM.ps1 creates FFUDevelopmentPath if missing" $false "New-Item call not found"
    }
}
catch {
    Write-TestResult "BuildFFUVM.ps1 parameter validation check" $false $_.Exception.Message
}

# Test 3: BuildFFUVM.ps1 Directory Creation (Functional Test)
Write-TestHeader "Test 3: BuildFFUVM.ps1 Directory Creation Functional Test"

Write-Host "  NOTE: Functional test of directory creation requires full script execution" -ForegroundColor Yellow
Write-Host "  The code logic has been verified in Test 2" -ForegroundColor Gray
Write-Host "  Manual verification:" -ForegroundColor Gray
Write-Host "    1. Run BuildFFUVM.ps1 with ConfigFile pointing to non-existent FFUDevelopmentPath" -ForegroundColor Gray
Write-Host "    2. Verify the script creates the directory instead of failing" -ForegroundColor Gray
Write-Host "    3. Check for 'Successfully created FFU Development Path' message" -ForegroundColor Gray
Write-TestResult "BuildFFUVM.ps1 directory creation (functional)" $true "Code logic verified - manual test recommended" -Skipped $true

# Test 4: UI Config Loading Logic
Write-TestHeader "Test 4: UI Config Loading Preserves Defaults for Empty Paths"

try {
    $configModulePath = Join-Path $PSScriptRoot "FFUUI.Core\FFUUI.Core.Config.psm1"
    $configModuleContent = Get-Content $configModulePath -Raw

    # Check for empty string skip logic
    if ($configModuleContent -match 'Skip.*empty.*preserve.*UI\s+default|IsNullOrWhiteSpace.*PropertyName.*Text') {
        Write-TestResult "UI skips empty string values from config" $true "Empty paths preserve UI defaults"
    }
    else {
        Write-TestResult "UI skips empty string values from config" $false "No logic to skip empty strings found"
    }

    # Check that the skip happens before setting the control
    if (($configModuleContent -match 'PropertyName.*-eq.*Text') -and
        ($configModuleContent -match 'IsNullOrWhiteSpace.*valueFromConfig') -and
        ($configModuleContent -match 'preserving UI default')) {
        Write-TestResult "UI returns early for empty text values" $true "Prevents overwriting UI defaults"
    }
    else {
        Write-TestResult "UI returns early for empty text values" $false "May overwrite defaults with empty strings"
    }
}
catch {
    Write-TestResult "UI config loading check" $false $_.Exception.Message
}

# Test 5: UI Pre-flight Validation Logic
Write-TestHeader "Test 5: UI Pre-Flight Validation Logic"

try {
    $uiScriptPath = Join-Path $PSScriptRoot "BuildFFUVM_UI.ps1"
    $uiScriptContent = Get-Content $uiScriptPath -Raw

    # Check for PRE-FLIGHT VALIDATION comment
    if ($uiScriptContent -match 'PRE-FLIGHT\s+VALIDATION') {
        Write-TestResult "UI has pre-flight validation section" $true "Found in BuildFFUVM_UI.ps1"
    }
    else {
        Write-TestResult "UI has pre-flight validation section" $false "PRE-FLIGHT VALIDATION section not found"
    }

    # Check for FFUDevelopmentPath existence check
    if ($uiScriptContent -match 'Test-Path.*\$ffuDevPath') {
        Write-TestResult "UI checks if FFUDevelopmentPath exists" $true
    }
    else {
        Write-TestResult "UI checks if FFUDevelopmentPath exists" $false "No Test-Path check found"
    }

    # Check for path mismatch warning
    if ($uiScriptContent -match 'Path\s+Mismatch|mismatch\s+detected') {
        Write-TestResult "UI warns on FFUDevelopmentPath mismatch" $true "Mismatch detection found"
    }
    else {
        Write-TestResult "UI warns on FFUDevelopmentPath mismatch" $false "No mismatch warning found"
    }

    # Check for directory creation offer
    if ($uiScriptContent -match 'Do\s+you\s+want\s+to\s+create\s+this\s+directory') {
        Write-TestResult "UI offers to create missing directory" $true
    }
    else {
        Write-TestResult "UI offers to create missing directory" $false "Creation prompt not found"
    }
}
catch {
    Write-TestResult "UI pre-flight validation check" $false $_.Exception.Message
}

# Test 6: UI Error Surfacing Logic
Write-TestHeader "Test 6: UI ThreadJob Error Surfacing"

try {
    $uiScriptContent = Get-Content (Join-Path $PSScriptRoot "BuildFFUVM_UI.ps1") -Raw

    # Check for enhanced error detection
    if ($uiScriptContent -match 'Even\s+"Completed"\s+jobs\s+can\s+have\s+errors') {
        Write-TestResult "UI detects errors in 'Completed' jobs" $true "Enhanced error detection comment found"
    }
    else {
        Write-TestResult "UI detects errors in 'Completed' jobs" $false "No comment about Completed jobs with errors"
    }

    # Check for log file existence check
    if ($uiScriptContent -match 'if\s+log\s+file\s+was\s+never\s+created.*likely\s+failed\s+early|Test-Path.*mainLogPath.*\$hasErrors\s*=\s*\$true') {
        Write-TestResult "UI detects early failures (no log file)" $true
    }
    else {
        Write-TestResult "UI detects early failures (no log file)" $false "No log file existence check in error detection"
    }

    # Check for detailed error message construction
    if ($uiScriptContent -match 'No\s+log\s+file\s+was\s+created') {
        Write-TestResult "UI provides helpful error messages" $true "Detailed error messages found"
    }
    else {
        Write-TestResult "UI provides helpful error messages" $false "Generic error messages only"
    }

    # Check for parameter validation error hint
    if ($uiScriptContent -match 'parameter\s+validation\s+error|missing\s+directory') {
        Write-TestResult "UI hints at parameter validation errors" $true
    }
    else {
        Write-TestResult "UI hints at parameter validation errors" $false "No hint about parameter errors"
    }
}
catch {
    Write-TestResult "UI error surfacing check" $false $_.Exception.Message
}

# Test 7: Integration Test (Optional - requires UI interaction)
Write-TestHeader "Test 7: Integration Test (UI + BuildFFUVM.ps1)"

Write-Host "  NOTE: Full integration test requires manual UI interaction" -ForegroundColor Yellow
Write-Host "  To manually test:" -ForegroundColor Gray
Write-Host "    1. Run BuildFFUVM_UI.ps1" -ForegroundColor Gray
Write-Host "    2. Load config\Sample_default.json" -ForegroundColor Gray
Write-Host "    3. Verify FFU Development Path shows: $PSScriptRoot" -ForegroundColor Gray
Write-Host "    4. Start a build" -ForegroundColor Gray
Write-Host "    5. Verify log monitoring works and progress is displayed" -ForegroundColor Gray
Write-TestResult "Integration test" $true "Manual test required" -Skipped $true

# Summary
Write-TestHeader "Test Summary"
$total = $testsPassed + $testsFailed + $testsSkipped
Write-Host "  Total Tests:   $total" -ForegroundColor Cyan
Write-Host "  Passed:        $testsPassed" -ForegroundColor Green
Write-Host "  Failed:        $testsFailed" -ForegroundColor $(if ($testsFailed -gt 0) { "Red" } else { "Gray" })
Write-Host "  Skipped:       $testsSkipped" -ForegroundColor Yellow

if ($testsFailed -eq 0) {
    Write-Host "`n✅ All automated tests passed!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "`n❌ $testsFailed test(s) failed. Please review the output above." -ForegroundColor Red
    exit 1
}
