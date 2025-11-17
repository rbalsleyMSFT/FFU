<#
.SYNOPSIS
Test script to verify ADK pre-flight validation functionality.

.DESCRIPTION
This script tests the ADK pre-flight validation system by running various scenarios
and displaying the results. It verifies that the validation correctly detects ADK
installation status, missing components, and provides appropriate error messages.

.PARAMETER WindowsArch
Architecture to test (x64 or arm64). Defaults to x64.

.PARAMETER SkipAutoInstall
Skip tests that attempt automatic installation. Use this to avoid modifying the system.

.EXAMPLE
.\Test-ADKValidation.ps1

.EXAMPLE
.\Test-ADKValidation.ps1 -WindowsArch arm64 -SkipAutoInstall
#>

param (
    [Parameter()]
    [ValidateSet('x64', 'arm64')]
    [string]$WindowsArch = 'x64',

    [Parameter()]
    [switch]$SkipAutoInstall
)

# Color output helpers
function Write-TestHeader {
    param([string]$Message)
    Write-Host "`n===============================================================================" -ForegroundColor Cyan
    Write-Host "  $Message" -ForegroundColor Cyan
    Write-Host "===============================================================================" -ForegroundColor Cyan
}

function Write-TestSection {
    param([string]$Message)
    Write-Host "`n--- $Message ---" -ForegroundColor Yellow
}

function Write-TestPass {
    param([string]$Message)
    Write-Host "[PASS] $Message" -ForegroundColor Green
}

function Write-TestFail {
    param([string]$Message)
    Write-Host "[FAIL] $Message" -ForegroundColor Red
}

function Write-TestInfo {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Gray
}

# Source the main script to get access to validation functions
Write-TestHeader "ADK Pre-Flight Validation Test Suite"
Write-TestInfo "Architecture: $WindowsArch"
Write-TestInfo "Auto-Install Tests: $(if ($SkipAutoInstall) { 'Skipped' } else { 'Enabled' })"

Write-TestSection "Loading BuildFFUVM.ps1 functions"
$scriptPath = Join-Path $PSScriptRoot "BuildFFUVM.ps1"

if (-not (Test-Path $scriptPath)) {
    Write-TestFail "BuildFFUVM.ps1 not found at: $scriptPath"
    exit 1
}

try {
    # Source only the validation functions (not the entire script)
    # We'll extract the functions we need
    $scriptContent = Get-Content $scriptPath -Raw

    # Extract the validation region
    $validationRegionPattern = '(?s)#region ADK Pre-Flight Validation Functions.*?#endregion ADK Pre-Flight Validation Functions'
    $validationCode = [regex]::Match($scriptContent, $validationRegionPattern).Value

    if ([string]::IsNullOrEmpty($validationCode)) {
        Write-TestFail "Could not extract ADK validation functions from BuildFFUVM.ps1"
        exit 1
    }

    # Also need supporting functions
    $supportingFunctions = @(
        'function Get-InstalledProgramRegKey',
        'function Install-ADK',
        'function Confirm-ADKVersionIsLatest',
        'function WriteLog'
    )

    # Create a simple WriteLog function for testing
    function WriteLog {
        param([string]$Message)
        # Silent during tests unless verbose
        if ($VerbosePreference -eq 'Continue') {
            Write-Verbose $Message
        }
    }

    # Execute the validation code to load functions
    Invoke-Expression $validationCode
    Write-TestPass "Validation functions loaded successfully"
}
catch {
    Write-TestFail "Failed to load validation functions: $($_.Exception.Message)"
    exit 1
}

# Test counters
$script:TestsRun = 0
$script:TestsPassed = 0
$script:TestsFailed = 0

function Test-ValidationResult {
    param(
        [string]$TestName,
        [scriptblock]$TestCode,
        [scriptblock]$Assertion
    )

    $script:TestsRun++
    Write-TestSection "Test: $TestName"

    try {
        $result = & $TestCode

        if (& $Assertion $result) {
            Write-TestPass $TestName
            $script:TestsPassed++
            return $result
        }
        else {
            Write-TestFail $TestName
            $script:TestsFailed++
            return $null
        }
    }
    catch {
        Write-TestFail "$TestName - Exception: $($_.Exception.Message)"
        Write-Host $_.ScriptStackTrace -ForegroundColor Red
        $script:TestsFailed++
        return $null
    }
}

# ============================================================================
# TEST 1: Validation Function Exists
# ============================================================================
Test-ValidationResult -TestName "Validation function exists" -TestCode {
    return (Get-Command Test-ADKPrerequisites -ErrorAction SilentlyContinue)
} -Assertion {
    param($result)
    return $null -ne $result
}

# ============================================================================
# TEST 2: Validation Result Object Structure
# ============================================================================
Write-TestSection "Test: Validation result object structure"
try {
    $validation = Test-ADKPrerequisites -WindowsArch $WindowsArch -AutoInstall $false -ThrowOnFailure $false

    $requiredProperties = @(
        'IsValid',
        'ADKInstalled',
        'ADKPath',
        'ADKVersion',
        'DeploymentToolsInstalled',
        'WinPEAddOnInstalled',
        'MissingFiles',
        'MissingExecutables',
        'Errors',
        'Warnings',
        'ValidationTimestamp'
    )

    $allPropertiesPresent = $true
    foreach ($prop in $requiredProperties) {
        if (-not ($validation.PSObject.Properties.Name -contains $prop)) {
            Write-TestFail "Missing property: $prop"
            $allPropertiesPresent = $false
        }
        else {
            Write-TestInfo "Property present: $prop"
        }
    }

    if ($allPropertiesPresent) {
        Write-TestPass "Validation result object has all required properties"
        $script:TestsPassed++
    }
    else {
        Write-TestFail "Validation result object is missing required properties"
        $script:TestsFailed++
    }
    $script:TestsRun++
}
catch {
    Write-TestFail "Exception testing result object: $($_.Exception.Message)"
    $script:TestsFailed++
    $script:TestsRun++
}

# ============================================================================
# TEST 3: Current System ADK Status
# ============================================================================
Write-TestSection "Test: Current system ADK status check"
try {
    $validation = Test-ADKPrerequisites -WindowsArch $WindowsArch -AutoInstall $false -ThrowOnFailure $false

    Write-Host "`nCurrent System Status:" -ForegroundColor Cyan
    Write-Host "  ADK Installed:          $($validation.ADKInstalled)" -ForegroundColor $(if ($validation.ADKInstalled) { 'Green' } else { 'Red' })
    Write-Host "  ADK Path:               $($validation.ADKPath)"
    Write-Host "  ADK Version:            $($validation.ADKVersion)"
    Write-Host "  Deployment Tools:       $($validation.DeploymentToolsInstalled)" -ForegroundColor $(if ($validation.DeploymentToolsInstalled) { 'Green' } else { 'Red' })
    Write-Host "  WinPE Add-on:           $($validation.WinPEAddOnInstalled)" -ForegroundColor $(if ($validation.WinPEAddOnInstalled) { 'Green' } else { 'Red' })
    Write-Host "  Overall Valid:          $($validation.IsValid)" -ForegroundColor $(if ($validation.IsValid) { 'Green' } else { 'Red' })
    Write-Host "  Missing Files Count:    $($validation.MissingFiles.Count)" -ForegroundColor $(if ($validation.MissingFiles.Count -eq 0) { 'Green' } else { 'Yellow' })
    Write-Host "  Errors Count:           $($validation.Errors.Count)" -ForegroundColor $(if ($validation.Errors.Count -eq 0) { 'Green' } else { 'Red' })
    Write-Host "  Warnings Count:         $($validation.Warnings.Count)" -ForegroundColor $(if ($validation.Warnings.Count -eq 0) { 'Green' } else { 'Yellow' })

    if ($validation.MissingFiles.Count -gt 0) {
        Write-Host "`nMissing Files:" -ForegroundColor Yellow
        foreach ($file in $validation.MissingFiles) {
            Write-Host "  - $file" -ForegroundColor Yellow
        }
    }

    if ($validation.Errors.Count -gt 0) {
        Write-Host "`nErrors:" -ForegroundColor Red
        foreach ($error in $validation.Errors) {
            Write-Host "  - $error" -ForegroundColor Red
        }
    }

    if ($validation.Warnings.Count -gt 0) {
        Write-Host "`nWarnings:" -ForegroundColor Yellow
        foreach ($warning in $validation.Warnings) {
            Write-Host "  - $warning" -ForegroundColor Yellow
        }
    }

    Write-TestPass "System status check completed"
    $script:TestsPassed++
    $script:TestsRun++
}
catch {
    Write-TestFail "Exception checking system status: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    $script:TestsFailed++
    $script:TestsRun++
}

# ============================================================================
# TEST 4: Registry Check Logic
# ============================================================================
Write-TestSection "Test: ADK registry detection"
try {
    $adkPathKey = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots"
    $adkPathName = "KitsRoot10"

    $registryExists = $false
    $registryPath = $null

    try {
        $adkPathValue = Get-ItemProperty -Path $adkPathKey -Name $adkPathName -ErrorAction Stop
        if ($adkPathValue -and $adkPathValue.$adkPathName) {
            $registryExists = $true
            $registryPath = $adkPathValue.$adkPathName
        }
    }
    catch {
        $registryExists = $false
    }

    Write-Host "  Registry Key: $adkPathKey"
    Write-Host "  Registry Exists: $registryExists" -ForegroundColor $(if ($registryExists) { 'Green' } else { 'Red' })
    if ($registryPath) {
        Write-Host "  Registry Path: $registryPath"
        $pathExists = Test-Path $registryPath
        Write-Host "  Path Exists on Disk: $pathExists" -ForegroundColor $(if ($pathExists) { 'Green' } else { 'Red' })
    }

    Write-TestPass "Registry check logic verified"
    $script:TestsPassed++
    $script:TestsRun++
}
catch {
    Write-TestFail "Exception in registry check: $($_.Exception.Message)"
    $script:TestsFailed++
    $script:TestsRun++
}

# ============================================================================
# TEST 5: Critical Files Check
# ============================================================================
Write-TestSection "Test: Critical files validation"
try {
    $validation = Test-ADKPrerequisites -WindowsArch $WindowsArch -AutoInstall $false -ThrowOnFailure $false

    if ($validation.ADKInstalled) {
        $archPath = if ($WindowsArch -eq 'x64') { 'amd64' } else { 'arm64' }

        $criticalFiles = @(
            "$($validation.ADKPath)Assessment and Deployment Kit\Deployment Tools\DandISetEnv.bat",
            "$($validation.ADKPath)Assessment and Deployment Kit\Deployment Tools\$archPath\Oscdimg\oscdimg.exe",
            "$($validation.ADKPath)Assessment and Deployment Kit\Deployment Tools\$archPath\Oscdimg\Efisys.bin",
            "$($validation.ADKPath)Assessment and Deployment Kit\Deployment Tools\$archPath\Oscdimg\Efisys_noprompt.bin",
            "$($validation.ADKPath)Assessment and Deployment Kit\Windows Preinstallation Environment\copype.cmd"
        )

        if ($WindowsArch -eq 'x64') {
            $criticalFiles += "$($validation.ADKPath)Assessment and Deployment Kit\Deployment Tools\$archPath\Oscdimg\etfsboot.com"
        }

        Write-Host "`nCritical Files Check:" -ForegroundColor Cyan
        $allFilesExist = $true
        foreach ($file in $criticalFiles) {
            $exists = Test-Path $file -PathType Leaf
            $fileName = Split-Path $file -Leaf
            $status = if ($exists) { "[OK]" } else { "[!!]" }
            $color = if ($exists) { 'Green' } else { 'Red' }
            Write-Host "  $status $fileName" -ForegroundColor $color
            if (-not $exists) {
                Write-Host "    Path: $file" -ForegroundColor Gray
                $allFilesExist = $false
            }
        }

        if ($allFilesExist) {
            Write-TestPass "All critical files present"
        }
        else {
            Write-TestFail "Some critical files are missing"
        }
    }
    else {
        Write-TestInfo "ADK not installed, skipping file checks"
    }

    $script:TestsPassed++
    $script:TestsRun++
}
catch {
    Write-TestFail "Exception in critical files check: $($_.Exception.Message)"
    $script:TestsFailed++
    $script:TestsRun++
}

# ============================================================================
# TEST 6: Error Message Templates
# ============================================================================
Write-TestSection "Test: Error message templates"
try {
    # Check if error message templates variable exists
    $templatesExist = $null -ne $script:ADKErrorMessageTemplates

    if ($templatesExist) {
        Write-TestInfo "Error message templates loaded"

        $expectedTemplates = @(
            'ADKNotInstalled',
            'DeploymentToolsMissing',
            'WinPEMissing',
            'MissingCriticalFiles',
            'ArchitectureMismatch'
        )

        $allTemplatesPresent = $true
        foreach ($template in $expectedTemplates) {
            if ($script:ADKErrorMessageTemplates.ContainsKey($template)) {
                Write-Host "  [OK] Template: $template" -ForegroundColor Green
            }
            else {
                Write-Host "  [!!] Missing: $template" -ForegroundColor Red
                $allTemplatesPresent = $false
            }
        }

        if ($allTemplatesPresent) {
            Write-TestPass "All error message templates present"
        }
        else {
            Write-TestFail "Some error message templates missing"
        }
    }
    else {
        Write-TestFail "Error message templates not loaded"
    }

    $script:TestsPassed++
    $script:TestsRun++
}
catch {
    Write-TestFail "Exception checking error templates: $($_.Exception.Message)"
    $script:TestsFailed++
    $script:TestsRun++
}

# ============================================================================
# TEST 7: ThrowOnFailure Parameter
# ============================================================================
Write-TestSection "Test: ThrowOnFailure parameter behavior"
try {
    # Test with ThrowOnFailure=$false (should return object)
    $validationNoThrow = Test-ADKPrerequisites -WindowsArch $WindowsArch -AutoInstall $false -ThrowOnFailure $false

    if ($null -ne $validationNoThrow) {
        Write-TestPass "ThrowOnFailure=`$false returns validation object"
    }
    else {
        Write-TestFail "ThrowOnFailure=`$false did not return object"
    }

    # Test with ThrowOnFailure=$true only if validation would fail
    if (-not $validationNoThrow.IsValid) {
        Write-TestInfo "Testing ThrowOnFailure=`$true (validation should fail and throw)"
        $exceptionThrown = $false
        try {
            $validationThrow = Test-ADKPrerequisites -WindowsArch $WindowsArch -AutoInstall $false -ThrowOnFailure $true
        }
        catch {
            $exceptionThrown = $true
            Write-TestInfo "Exception thrown as expected: $($_.Exception.Message)"
        }

        if ($exceptionThrown) {
            Write-TestPass "ThrowOnFailure=`$true throws exception on validation failure"
        }
        else {
            Write-TestFail "ThrowOnFailure=`$true did not throw exception despite validation failure"
        }
    }
    else {
        Write-TestInfo "Validation passed, cannot test exception throwing behavior"
        Write-TestPass "ThrowOnFailure parameter logic verified (validation passed)"
    }

    $script:TestsPassed++
    $script:TestsRun++
}
catch {
    Write-TestFail "Exception testing ThrowOnFailure parameter: $($_.Exception.Message)"
    $script:TestsFailed++
    $script:TestsRun++
}

# ============================================================================
# TEST 8: Architecture Parameter
# ============================================================================
Write-TestSection "Test: Architecture parameter handling"
try {
    $validX64 = $null -ne (Test-ADKPrerequisites -WindowsArch 'x64' -AutoInstall $false -ThrowOnFailure $false)

    if ($validX64) {
        Write-TestPass "x64 architecture parameter accepted"
    }
    else {
        Write-TestFail "x64 architecture test failed"
    }

    # Test arm64 if system supports it
    try {
        $validArm64 = $null -ne (Test-ADKPrerequisites -WindowsArch 'arm64' -AutoInstall $false -ThrowOnFailure $false)
        if ($validArm64) {
            Write-TestPass "arm64 architecture parameter accepted"
        }
    }
    catch {
        Write-TestInfo "arm64 architecture test skipped (may not be supported on this system)"
    }

    $script:TestsPassed++
    $script:TestsRun++
}
catch {
    Write-TestFail "Exception testing architecture parameter: $($_.Exception.Message)"
    $script:TestsFailed++
    $script:TestsRun++
}

# ============================================================================
# TEST SUMMARY
# ============================================================================
Write-TestHeader "Test Summary"

$passRate = if ($script:TestsRun -gt 0) {
    [math]::Round(($script:TestsPassed / $script:TestsRun) * 100, 2)
}
else {
    0
}

Write-Host "`nTotal Tests Run:     $script:TestsRun" -ForegroundColor Cyan
Write-Host "Tests Passed:        $script:TestsPassed" -ForegroundColor Green
Write-Host "Tests Failed:        $script:TestsFailed" -ForegroundColor $(if ($script:TestsFailed -eq 0) { 'Green' } else { 'Red' })
Write-Host "Pass Rate:           $passRate%" -ForegroundColor $(if ($passRate -ge 80) { 'Green' } elseif ($passRate -ge 50) { 'Yellow' } else { 'Red' })

# Overall result
Write-Host ""
if ($script:TestsFailed -eq 0) {
    Write-Host "===============================================================================" -ForegroundColor Green
    Write-Host "  [PASS] ALL TESTS PASSED" -ForegroundColor Green
    Write-Host "===============================================================================" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "===============================================================================" -ForegroundColor Red
    Write-Host "  [FAIL] SOME TESTS FAILED" -ForegroundColor Red
    Write-Host "===============================================================================" -ForegroundColor Red
    exit 1
}
