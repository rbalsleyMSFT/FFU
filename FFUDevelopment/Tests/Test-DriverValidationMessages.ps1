#Requires -Version 5.1
<#
.SYNOPSIS
    Tests the driver validation error messages in BuildFFUVM.ps1.

.DESCRIPTION
    Validates that driver validation provides clear, actionable error messages when:
    - InstallDrivers/CopyDrivers is enabled but no driver source is configured
    - Drivers folder is missing or empty
    - No Make/Model or DriversJsonPath specified

    The error messages should guide users on how to fix the configuration.

.NOTES
    Version: 1.0.0
    Created to ensure driver validation provides helpful guidance
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

Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host "Driver Validation Error Message Tests" -ForegroundColor Cyan
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host ""
Write-Host "Purpose: Ensure driver validation provides clear, actionable error guidance" -ForegroundColor Gray
Write-Host ""

# =============================================================================
# Test 1: Verify error messages contain actionable guidance
# =============================================================================
Write-Host "Testing error message content..." -ForegroundColor Yellow

try {
    $content = Get-Content -Path $BuildScript -Raw -ErrorAction Stop

    # Test for missing folder error message
    $hasMissingFolderError = $content -match 'DRIVER CONFIGURATION ERROR.*Drivers folder is missing'
    Write-TestResult -TestName "Has descriptive error for missing Drivers folder" -Passed $hasMissingFolderError

    # Test for empty folder error message
    $hasEmptyFolderError = $content -match 'DRIVER CONFIGURATION ERROR.*Drivers folder is empty'
    Write-TestResult -TestName "Has descriptive error for empty Drivers folder" -Passed $hasEmptyFolderError

    # Test that error messages include all 4 fix options
    $fixOptions = @(
        'SELECT A DEVICE MODEL',
        'PROVIDE A DRIVERS JSON FILE',
        'ADD DRIVERS MANUALLY',
        'DISABLE DRIVER INSTALLATION'
    )

    foreach ($option in $fixOptions) {
        $hasOption = $content -match [regex]::Escape($option)
        Write-TestResult -TestName "Error message includes fix option: $option" -Passed $hasOption
    }

    # Test that error messages mention specific UI steps
    $hasUIGuidance = $content -match 'Go to the Drivers tab'
    Write-TestResult -TestName "Error message includes UI navigation guidance" -Passed $hasUIGuidance

    $hasMakeGuidance = $content -match 'Select a Make.*Dell.*HP.*Lenovo.*Microsoft'
    Write-TestResult -TestName "Error message lists supported driver Makes" -Passed $hasMakeGuidance

    $hasModelGuidance = $content -match 'Select a Model from the list'
    Write-TestResult -TestName "Error message mentions Model selection" -Passed $hasModelGuidance

    # Test that error shows the actual folder path
    $showsFolderPath = $content -match 'Folder (expected at|location):\s*\$DriversFolder'
    Write-TestResult -TestName "Error message shows the actual folder path" -Passed $showsFolderPath
}
catch {
    Write-TestResult -TestName "Reading BuildFFUVM.ps1" -Passed $false -Message $_.Exception.Message
}

# =============================================================================
# Test 2: Verify validation logic structure
# =============================================================================
Write-Host ""
Write-Host "Testing validation logic structure..." -ForegroundColor Yellow

try {
    $content = Get-Content -Path $BuildScript -Raw -ErrorAction Stop

    # Verify Make and Model check comes first
    $hasMakeModelCheck = $content -match 'if\s*\(\s*\$Make\s+-and\s+\$Model\s*\)'
    Write-TestResult -TestName "Validates Make and Model as primary driver source" -Passed $hasMakeModelCheck

    # Verify DriversJsonPath check is second
    $hasJsonPathCheck = $content -match 'elseif\s*\(\s*\$DriversJsonPath\s+-and\s*\(Test-Path'
    Write-TestResult -TestName "Validates DriversJsonPath as secondary driver source" -Passed $hasJsonPathCheck

    # Verify folder existence check
    $hasFolderExistCheck = $content -match 'Test-Path\s+-Path\s+\$DriversFolder'
    Write-TestResult -TestName "Checks if Drivers folder exists" -Passed $hasFolderExistCheck

    # Verify folder content check (>= 1MB)
    $hasFolderContentCheck = $content -match 'Measure-Object.*-Sum.*-ge\s+1MB'
    Write-TestResult -TestName "Checks if Drivers folder has content (>=1MB)" -Passed $hasFolderContentCheck

    # Verify success message when drivers found
    $hasSuccessMessage = $content -match 'Drivers folder found with content\. Will use existing drivers'
    Write-TestResult -TestName "Logs success when existing drivers found" -Passed $hasSuccessMessage
}
catch {
    Write-TestResult -TestName "Analyzing validation logic" -Passed $false -Message $_.Exception.Message
}

# =============================================================================
# Test 3: Verify PEDrivers validation consistency
# =============================================================================
Write-Host ""
Write-Host "Testing PEDrivers validation consistency..." -ForegroundColor Yellow

try {
    $content = Get-Content -Path $BuildScript -Raw -ErrorAction Stop

    # Verify UseDriversAsPEDrivers provides alternative path
    $hasUseDriversCheck = $content -match 'if\s*\(\s*\$UseDriversAsPEDrivers\s*\)'
    Write-TestResult -TestName "PEDrivers validation checks UseDriversAsPEDrivers option" -Passed $hasUseDriversCheck

    # Verify PEDrivers folder validation exists
    $hasPEDriversCheck = $content -match 'CopyPEDrivers is set to.*but the.*PEDriversFolder.*folder'
    Write-TestResult -TestName "PEDrivers validation has descriptive error" -Passed $hasPEDriversCheck
}
catch {
    Write-TestResult -TestName "Analyzing PEDrivers validation" -Passed $false -Message $_.Exception.Message
}

# =============================================================================
# Test 4: Verify no cryptic error messages remain
# =============================================================================
Write-Host ""
Write-Host "Testing for cryptic error messages..." -ForegroundColor Yellow

try {
    $content = Get-Content -Path $BuildScript -Raw -ErrorAction Stop

    # The old cryptic messages should NOT exist anymore
    $hasOldCrypticMessage1 = $content -match 'throw\s+"-InstallDrivers or -CopyDrivers is set to.*folder is missing"' -and
                             -not ($content -match 'DRIVER CONFIGURATION ERROR')

    # Check for the old one-liner error (should be replaced with detailed message)
    $hasOldSimpleError = $content -match 'throw.*Drivers folder is empty, and no drivers are specified.*[^"]$'

    Write-TestResult -TestName "Old cryptic 'folder is missing' message replaced" -Passed (-not $hasOldCrypticMessage1)
    Write-TestResult -TestName "Old cryptic 'folder is empty' message replaced" -Passed (-not $hasOldSimpleError)

    # Verify here-strings are used for multi-line error messages
    $usesHereStrings = $content -match '@"\s*\nDRIVER CONFIGURATION ERROR'
    Write-TestResult -TestName "Uses here-strings for readable multi-line errors" -Passed $usesHereStrings
}
catch {
    Write-TestResult -TestName "Checking for cryptic messages" -Passed $false -Message $_.Exception.Message
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
    Write-Host "All tests passed! Driver validation provides clear guidance." -ForegroundColor Green
    exit 0
} else {
    Write-Host "Some tests failed. Review driver validation error messages." -ForegroundColor Red
    exit 1
}
