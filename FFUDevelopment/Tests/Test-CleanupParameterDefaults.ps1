#Requires -Version 5.1
<#
.SYNOPSIS
    Tests that cleanup parameter defaults are consistent across all sources.

.DESCRIPTION
    Validates that post-build cleanup parameters have the correct default values:
    - CleanupAppsISO, CleanupCaptureISO, CleanupDeployISO = $true (checked by default)
    - CleanupDrivers, RemoveFFU, RemoveApps, RemoveUpdates = $false (unchecked by default)

    This test was created after discovering that cleanup tasks were executing even when
    their checkboxes were unchecked in the UI, because:
    1. BuildFFUVM.ps1 parameter defaults were incorrectly set to $true
    2. Sample_default.json had incorrect default values

.NOTES
    Version: 1.0.0
    Created to prevent regression of cleanup parameter default issues
#>

param(
    [switch]$Verbose
)

$script:PassCount = 0
$script:FailCount = 0
$script:TestResults = @()

function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Message = ""
    )

    $script:TestResults += [PSCustomObject]@{
        TestName = $TestName
        Passed   = $Passed
        Message  = $Message
    }

    if ($Passed) {
        $script:PassCount++
        Write-Host "  [PASS] $TestName" -ForegroundColor Green
    } else {
        $script:FailCount++
        Write-Host "  [FAIL] $TestName" -ForegroundColor Red
        if ($Message) {
            Write-Host "         $Message" -ForegroundColor Yellow
        }
    }
}

$FFUDevelopmentPath = Split-Path $PSScriptRoot -Parent
$BuildScript = Join-Path $FFUDevelopmentPath "BuildFFUVM.ps1"
$UIModule = Join-Path $FFUDevelopmentPath "FFUUI.Core\FFUUI.Core.psm1"
$SampleConfig = Join-Path $FFUDevelopmentPath "config\Sample_default.json"

Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host "Cleanup Parameter Default Tests" -ForegroundColor Cyan
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host ""
Write-Host "Purpose: Ensure cleanup parameters default to expected UI values" -ForegroundColor Gray
Write-Host ""

# Expected default values based on UI design
$ExpectedDefaults = @{
    # These should be TRUE (checked by default in UI)
    CleanupAppsISO    = $true
    CleanupCaptureISO = $true
    CleanupDeployISO  = $true
    # These should be FALSE (unchecked by default in UI)
    CleanupDrivers    = $false
    RemoveFFU         = $false
    RemoveApps        = $false
    RemoveUpdates     = $false
}

# =============================================================================
# Test 1: Verify BuildFFUVM.ps1 parameter defaults
# =============================================================================
Write-Host "Testing BuildFFUVM.ps1 parameter defaults..." -ForegroundColor Yellow

try {
    $content = Get-Content -Path $BuildScript -Raw -ErrorAction Stop

    # Test CleanupAppsISO default = $true
    $hasCorrectAppsISO = $content -match '\[bool\]\$CleanupAppsISO\s*=\s*\$true'
    Write-TestResult -TestName "CleanupAppsISO defaults to `$true" -Passed $hasCorrectAppsISO

    # Test CleanupCaptureISO default = $true
    $hasCorrectCaptureISO = $content -match '\[bool\]\$CleanupCaptureISO\s*=\s*\$true'
    Write-TestResult -TestName "CleanupCaptureISO defaults to `$true" -Passed $hasCorrectCaptureISO

    # Test CleanupDeployISO default = $true
    $hasCorrectDeployISO = $content -match '\[bool\]\$CleanupDeployISO\s*=\s*\$true'
    Write-TestResult -TestName "CleanupDeployISO defaults to `$true" -Passed $hasCorrectDeployISO

    # Test CleanupDrivers default = $false (NOT $true!)
    $hasCorrectDrivers = $content -match '\[bool\]\$CleanupDrivers\s*=\s*\$false'
    $hasIncorrectDrivers = $content -match '\[bool\]\$CleanupDrivers\s*=\s*\$true'
    Write-TestResult -TestName "CleanupDrivers defaults to `$false" -Passed ($hasCorrectDrivers -and -not $hasIncorrectDrivers) -Message $(if ($hasIncorrectDrivers) { "CRITICAL: CleanupDrivers defaults to `$true - will delete drivers when unchecked!" })

    # Test RemoveFFU - should have no default (which means $false)
    $hasNoDefaultFFU = $content -match '\[bool\]\$RemoveFFU\s*,' -and -not ($content -match '\[bool\]\$RemoveFFU\s*=\s*\$true')
    Write-TestResult -TestName "RemoveFFU has no default or defaults to `$false" -Passed $hasNoDefaultFFU

    # Test RemoveApps default = $false (NOT $true!)
    $hasCorrectApps = $content -match '\[bool\]\$RemoveApps\s*=\s*\$false'
    $hasIncorrectApps = $content -match '\[bool\]\$RemoveApps\s*=\s*\$true'
    Write-TestResult -TestName "RemoveApps defaults to `$false" -Passed ($hasCorrectApps -and -not $hasIncorrectApps) -Message $(if ($hasIncorrectApps) { "CRITICAL: RemoveApps defaults to `$true - will delete apps when unchecked!" })

    # Test RemoveUpdates default = $false (NOT $true!)
    $hasCorrectUpdates = $content -match '\[bool\]\$RemoveUpdates\s*=\s*\$false'
    $hasIncorrectUpdates = $content -match '\[bool\]\$RemoveUpdates\s*=\s*\$true'
    Write-TestResult -TestName "RemoveUpdates defaults to `$false" -Passed ($hasCorrectUpdates -and -not $hasIncorrectUpdates) -Message $(if ($hasIncorrectUpdates) { "CRITICAL: RemoveUpdates defaults to `$true - will delete updates when unchecked!" })

    # Verify explanatory comment exists
    $hasComment = $content -match '# NOTE:.*[Cc]leanup parameters.*default.*\$false'
    Write-TestResult -TestName "Has explanatory comment about cleanup defaults" -Passed $hasComment
}
catch {
    Write-TestResult -TestName "Reading BuildFFUVM.ps1" -Passed $false -Message $_.Exception.Message
}

# =============================================================================
# Test 2: Verify FFUUI.Core.psm1 defaults
# =============================================================================
Write-Host ""
Write-Host "Testing FFUUI.Core.psm1 defaults..." -ForegroundColor Yellow

try {
    $uiContent = Get-Content -Path $UIModule -Raw -ErrorAction Stop

    # ISO cleanup should be true
    $uiAppsISO = $uiContent -match 'CleanupAppsISO\s*=\s*\$true'
    Write-TestResult -TestName "UI: CleanupAppsISO = `$true" -Passed $uiAppsISO

    $uiCaptureISO = $uiContent -match 'CleanupCaptureISO\s*=\s*\$true'
    Write-TestResult -TestName "UI: CleanupCaptureISO = `$true" -Passed $uiCaptureISO

    $uiDeployISO = $uiContent -match 'CleanupDeployISO\s*=\s*\$true'
    Write-TestResult -TestName "UI: CleanupDeployISO = `$true" -Passed $uiDeployISO

    # Other cleanup should be false
    $uiDrivers = $uiContent -match 'CleanupDrivers\s*=\s*\$false'
    Write-TestResult -TestName "UI: CleanupDrivers = `$false" -Passed $uiDrivers

    $uiFFU = $uiContent -match 'RemoveFFU\s*=\s*\$false'
    Write-TestResult -TestName "UI: RemoveFFU = `$false" -Passed $uiFFU

    $uiApps = $uiContent -match 'RemoveApps\s*=\s*\$false'
    Write-TestResult -TestName "UI: RemoveApps = `$false" -Passed $uiApps

    $uiUpdates = $uiContent -match 'RemoveUpdates\s*=\s*\$false'
    Write-TestResult -TestName "UI: RemoveUpdates = `$false" -Passed $uiUpdates
}
catch {
    Write-TestResult -TestName "Reading FFUUI.Core.psm1" -Passed $false -Message $_.Exception.Message
}

# =============================================================================
# Test 3: Verify Sample_default.json defaults
# =============================================================================
Write-Host ""
Write-Host "Testing Sample_default.json defaults..." -ForegroundColor Yellow

try {
    $configContent = Get-Content -Path $SampleConfig -Raw -ErrorAction Stop
    $config = $configContent | ConvertFrom-Json

    # ISO cleanup should be true
    Write-TestResult -TestName "Config: CleanupAppsISO = true" -Passed ($config.CleanupAppsISO -eq $true)
    Write-TestResult -TestName "Config: CleanupCaptureISO = true" -Passed ($config.CleanupCaptureISO -eq $true)
    Write-TestResult -TestName "Config: CleanupDeployISO = true" -Passed ($config.CleanupDeployISO -eq $true)

    # Other cleanup should be false
    Write-TestResult -TestName "Config: CleanupDrivers = false" -Passed ($config.CleanupDrivers -eq $false) -Message $(if ($config.CleanupDrivers -eq $true) { "CRITICAL: Sample config has CleanupDrivers=true!" })
    Write-TestResult -TestName "Config: RemoveFFU = false" -Passed ($config.RemoveFFU -eq $false) -Message $(if ($config.RemoveFFU -eq $true) { "CRITICAL: Sample config has RemoveFFU=true!" })
    Write-TestResult -TestName "Config: RemoveApps = false" -Passed ($config.RemoveApps -eq $false)
    Write-TestResult -TestName "Config: RemoveUpdates = false" -Passed ($config.RemoveUpdates -eq $false)
}
catch {
    Write-TestResult -TestName "Reading Sample_default.json" -Passed $false -Message $_.Exception.Message
}

# =============================================================================
# Test 4: Consistency check across all sources
# =============================================================================
Write-Host ""
Write-Host "Testing cross-source consistency..." -ForegroundColor Yellow

try {
    $scriptContent = Get-Content -Path $BuildScript -Raw -ErrorAction Stop
    $uiContent = Get-Content -Path $UIModule -Raw -ErrorAction Stop
    $config = Get-Content -Path $SampleConfig -Raw | ConvertFrom-Json

    foreach ($param in $ExpectedDefaults.Keys) {
        $expected = $ExpectedDefaults[$param]

        # Check script default
        if ($expected) {
            $scriptMatch = $scriptContent -match "\[bool\]\`$$param\s*=\s*\`$true"
        } else {
            $scriptMatch = $scriptContent -match "\[bool\]\`$$param\s*=\s*\`$false" -or
                          ($scriptContent -match "\[bool\]\`$$param\s*," -and -not ($scriptContent -match "\[bool\]\`$$param\s*=\s*\`$true"))
        }

        # Check UI default
        $uiMatch = $uiContent -match "$param\s*=\s*\`$$($expected.ToString().ToLower())"

        # Check config default
        $configValue = $config.$param
        $configMatch = $configValue -eq $expected

        $allMatch = $scriptMatch -and $uiMatch -and $configMatch

        Write-TestResult -TestName "Consistency: $param = `$$expected across all sources" -Passed $allMatch -Message $(if (-not $allMatch) {
            $issues = @()
            if (-not $scriptMatch) { $issues += "Script default wrong" }
            if (-not $uiMatch) { $issues += "UI default wrong" }
            if (-not $configMatch) { $issues += "Config value wrong (=$configValue)" }
            $issues -join ", "
        })
    }
}
catch {
    Write-TestResult -TestName "Cross-source consistency check" -Passed $false -Message $_.Exception.Message
}

# =============================================================================
# Test 5: Functional test - parse script to get parameter defaults
# =============================================================================
Write-Host ""
Write-Host "Testing functional parameter parsing..." -ForegroundColor Yellow

try {
    # Parse the script file to extract actual parameter defaults
    $scriptContent = Get-Content -Path $BuildScript -Raw

    # Extract the param block
    $paramBlockMatch = [regex]::Match($scriptContent, '(?ms)param\s*\((.*?)^\)')

    if ($paramBlockMatch.Success) {
        $paramBlock = $paramBlockMatch.Groups[1].Value

        # Parse each cleanup parameter
        foreach ($param in $ExpectedDefaults.Keys) {
            $expected = $ExpectedDefaults[$param]

            # Look for the parameter definition - use single quotes for regex pattern
            $paramPattern = '\[bool\]\$' + $param + '\s*(?:=\s*\$(\w+))?'
            $paramMatch = [regex]::Match($paramBlock, $paramPattern)

            if ($paramMatch.Success) {
                $defaultValue = $paramMatch.Groups[1].Value
                $actualDefault = if ([string]::IsNullOrEmpty($defaultValue)) { $false } else { $defaultValue -eq 'true' }

                $isCorrect = $actualDefault -eq $expected
                Write-TestResult -TestName "Parsed: $param actual default = `$$actualDefault (expected `$$expected)" -Passed $isCorrect
            } else {
                Write-TestResult -TestName "Parsed: $param not found in param block" -Passed $false
            }
        }
    } else {
        Write-TestResult -TestName "Could not parse param block" -Passed $false
    }
}
catch {
    Write-TestResult -TestName "Functional parameter parsing" -Passed $false -Message $_.Exception.Message
}

# =============================================================================
# Test Summary
# =============================================================================
Write-Host ""
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host "Total Tests: $($script:PassCount + $script:FailCount)" -ForegroundColor White
Write-Host "Passed: $script:PassCount" -ForegroundColor Green
Write-Host "Failed: $script:FailCount" -ForegroundColor $(if ($script:FailCount -gt 0) { "Red" } else { "Green" })
Write-Host ""

if ($script:FailCount -eq 0) {
    Write-Host "All tests passed! Cleanup parameter defaults are correctly configured." -ForegroundColor Green
    Write-Host ""
    Write-Host "Expected behavior:" -ForegroundColor Gray
    Write-Host "  - CleanupAppsISO, CleanupCaptureISO, CleanupDeployISO = CHECKED by default" -ForegroundColor Gray
    Write-Host "  - CleanupDrivers, RemoveFFU, RemoveApps, RemoveUpdates = UNCHECKED by default" -ForegroundColor Gray
    exit 0
} else {
    Write-Host "CRITICAL: Some tests failed!" -ForegroundColor Red
    Write-Host "Cleanup tasks may execute even when their checkboxes are unchecked!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Fix the parameter defaults in BuildFFUVM.ps1 and/or Sample_default.json" -ForegroundColor Yellow
    exit 1
}
