#Requires -Version 5.1
<#
.SYNOPSIS
    Tests the path parameter validation in BuildFFUVM.ps1.

.DESCRIPTION
    Validates that optional file path parameters (AppListPath, UserAppListPath,
    OfficeConfigXMLFile, DriversJsonPath) use parent directory validation instead
    of strict file existence validation.

    This test was created after discovering that strict file validation caused:
    - "The variable cannot be validated because the value X is not a valid value"
    - Failures when config specified paths to files that didn't exist yet
    - The script handles missing files gracefully at runtime, so strict validation was unnecessary

.NOTES
    Version: 1.0.0
    Created to prevent regression of path validation issues
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
Write-Host "Path Parameter Validation Tests" -ForegroundColor Cyan
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host ""
Write-Host "Purpose: Ensure path parameters allow non-existent files with valid parent directories" -ForegroundColor Gray
Write-Host ""

# =============================================================================
# Test 1: Verify parameters use parent directory validation
# =============================================================================
Write-Host "Testing parameter validation patterns..." -ForegroundColor Yellow

try {
    $content = Get-Content -Path $BuildScript -Raw -ErrorAction Stop

    # Parameters that should use parent directory validation (Split-Path -Parent)
    $parentDirValidationParams = @(
        'AppListPath',
        'UserAppListPath',
        'OfficeConfigXMLFile',
        'DriversJsonPath'
    )

    foreach ($param in $parentDirValidationParams) {
        # Look for the pattern: [ValidateScript({ ... (Test-Path (Split-Path $_ -Parent) -PathType Container) })]
        # followed by [string]$ParamName
        $pattern = "ValidateScript\(\{\s*\[string\]::IsNullOrWhiteSpace\(\`$_\)\s*-or\s*\(Test-Path\s+\(Split-Path\s+\`$_\s+-Parent\)\s+-PathType\s+Container\)"

        # Find the param block for this parameter
        $paramPattern = "(?ms)$pattern.*?\[string\]\`$$param"
        $hasParentValidation = $content -match $paramPattern

        Write-TestResult -TestName "$param uses parent directory validation" -Passed $hasParentValidation -Message $(if (-not $hasParentValidation) { "Should use (Split-Path `$_ -Parent) instead of direct file check" })
    }

    # Verify these parameters do NOT use strict file existence check
    foreach ($param in $parentDirValidationParams) {
        # Check for the BAD pattern: ValidateScript with Test-Path $_ -PathType Leaf directly before the param
        $badPattern = "(?ms)ValidateScript\(\{\s*\[string\]::IsNullOrWhiteSpace\(\`$_\)\s*-or\s*\(Test-Path\s+\`$_\s+-PathType\s+Leaf\)\s*\}\)\]\s*\[string\]\`$$param"
        $hasStrictValidation = $content -match $badPattern

        Write-TestResult -TestName "$param does NOT use strict file existence check" -Passed (-not $hasStrictValidation) -Message $(if ($hasStrictValidation) { "CRITICAL: Strict validation will fail for non-existent files" })
    }
}
catch {
    Write-TestResult -TestName "Reading BuildFFUVM.ps1" -Passed $false -Message $_.Exception.Message
}

# =============================================================================
# Test 2: Verify runtime handling of missing files
# =============================================================================
Write-Host ""
Write-Host "Testing runtime handling of missing files..." -ForegroundColor Yellow

try {
    $content = Get-Content -Path $BuildScript -Raw -ErrorAction Stop

    # Verify AppListPath is checked at runtime
    $hasAppListCheck = $content -match 'if\s*\(Test-Path\s+-Path\s+\$AppListPath\)'
    Write-TestResult -TestName "Script checks AppListPath existence at runtime" -Passed $hasAppListCheck

    # Verify UserAppListPath is checked at runtime
    $hasUserAppListCheck = $content -match 'if\s*\(Test-Path\s+-Path\s+\$UserAppListPath\)'
    Write-TestResult -TestName "Script checks UserAppListPath existence at runtime" -Passed $hasUserAppListCheck

    # Verify DriversJsonPath is checked at runtime
    $hasDriversJsonCheck = $content -match 'if.*\$DriversJsonPath.*-and.*Test-Path\s+-Path\s+\$DriversJsonPath'
    Write-TestResult -TestName "Script checks DriversJsonPath existence at runtime" -Passed $hasDriversJsonCheck
}
catch {
    Write-TestResult -TestName "Analyzing runtime checks" -Passed $false -Message $_.Exception.Message
}

# =============================================================================
# Test 3: Functional validation tests
# =============================================================================
Write-Host ""
Write-Host "Testing functional validation..." -ForegroundColor Yellow

try {
    # Create a test directory
    $testDir = Join-Path $env:TEMP "FFUPathValidationTest_$(Get-Random)"
    New-Item -Path $testDir -ItemType Directory -Force | Out-Null

    # Test 1: Empty path should be valid
    $emptyPathValid = $true
    try {
        $scriptBlock = [ScriptBlock]::Create(@"
            `$testPath = ''
            [string]::IsNullOrWhiteSpace(`$testPath) -or (Test-Path (Split-Path `$testPath -Parent) -PathType Container)
"@)
        $emptyPathValid = & $scriptBlock
    }
    catch {
        $emptyPathValid = $false
    }
    Write-TestResult -TestName "Empty path passes validation" -Passed $emptyPathValid

    # Test 2: Whitespace path should be valid
    $whitespacePathValid = $true
    try {
        $testPath = '   '
        $whitespacePathValid = [string]::IsNullOrWhiteSpace($testPath) -or (Test-Path (Split-Path $testPath -Parent) -PathType Container)
    }
    catch {
        $whitespacePathValid = $false
    }
    Write-TestResult -TestName "Whitespace path passes validation" -Passed $whitespacePathValid

    # Test 3: Path with existing parent but non-existent file should be valid
    $nonExistentFileValid = $false
    try {
        $testPath = Join-Path $testDir "NonExistentFile.json"
        $nonExistentFileValid = [string]::IsNullOrWhiteSpace($testPath) -or (Test-Path (Split-Path $testPath -Parent) -PathType Container)
    }
    catch {
        $nonExistentFileValid = $false
    }
    Write-TestResult -TestName "Non-existent file with valid parent passes validation" -Passed $nonExistentFileValid

    # Test 4: Path with non-existent parent should fail
    $badParentInvalid = $true
    try {
        $testPath = "C:\NonExistentFolder12345\SomeFile.json"
        $badParentInvalid = -not ([string]::IsNullOrWhiteSpace($testPath) -or (Test-Path (Split-Path $testPath -Parent) -PathType Container))
    }
    catch {
        $badParentInvalid = $true
    }
    Write-TestResult -TestName "Non-existent parent directory fails validation" -Passed $badParentInvalid

    # Test 5: Path with existing file should be valid
    $existingFileValid = $false
    try {
        $existingFile = Join-Path $testDir "ExistingFile.json"
        Set-Content -Path $existingFile -Value "{}" -Force
        $existingFileValid = [string]::IsNullOrWhiteSpace($existingFile) -or (Test-Path (Split-Path $existingFile -Parent) -PathType Container)
    }
    catch {
        $existingFileValid = $false
    }
    Write-TestResult -TestName "Existing file passes validation" -Passed $existingFileValid

    # Cleanup
    Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
}
catch {
    Write-TestResult -TestName "Functional validation tests" -Passed $false -Message $_.Exception.Message
}

# =============================================================================
# Test 4: Verify explanatory comments exist
# =============================================================================
Write-Host ""
Write-Host "Testing documentation..." -ForegroundColor Yellow

try {
    $content = Get-Content -Path $BuildScript -Raw -ErrorAction Stop

    # Check for explanatory comments about the validation approach
    $hasAppListComment = $content -match '# NOTE:.*AppListPath.*parent directory'
    Write-TestResult -TestName "AppListPath has explanatory comment" -Passed $hasAppListComment

    $hasDriversJsonComment = $content -match '# NOTE:.*DriversJsonPath.*parent directory'
    Write-TestResult -TestName "DriversJsonPath has explanatory comment" -Passed $hasDriversJsonComment
}
catch {
    Write-TestResult -TestName "Documentation analysis" -Passed $false -Message $_.Exception.Message
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
    Write-Host "All tests passed! Path parameter validation is correctly configured." -ForegroundColor Green
    exit 0
} else {
    Write-Host "CRITICAL: Some tests failed. Path validation may cause build failures!" -ForegroundColor Red
    exit 1
}
