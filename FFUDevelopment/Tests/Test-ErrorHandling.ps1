#Requires -Version 5.1
<#
.SYNOPSIS
    Tests error handling functions and patterns implemented in FFU Builder modules.

.DESCRIPTION
    Validates the error handling helper functions in FFU.Core module and verifies
    error handling patterns in critical operations across FFU modules.

.NOTES
    Version: 1.0.5
    Created for error handling implementation validation
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

# Set up module path
$FFUDevelopmentPath = Split-Path $PSScriptRoot -Parent
$ModulesPath = Join-Path $FFUDevelopmentPath "Modules"

if ($env:PSModulePath -notlike "*$ModulesPath*") {
    $env:PSModulePath = "$ModulesPath;$env:PSModulePath"
}

Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host "FFU Builder Error Handling Test Suite" -ForegroundColor Cyan
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host ""

# =============================================================================
# Test 1: FFU.Core Module Export Verification
# =============================================================================
Write-Host "Testing FFU.Core Module Exports..." -ForegroundColor Yellow

try {
    Import-Module (Join-Path $ModulesPath "FFU.Core\FFU.Core.psd1") -Force -ErrorAction Stop

    $exportedFunctions = (Get-Module FFU.Core).ExportedFunctions.Keys

    Write-TestResult -TestName "FFU.Core module loads successfully" -Passed $true

    # Test for new error handling functions
    $expectedFunctions = @(
        'Invoke-WithErrorHandling',
        'Test-ExternalCommandSuccess',
        'Invoke-WithCleanup'
    )

    foreach ($func in $expectedFunctions) {
        $found = $func -in $exportedFunctions
        Write-TestResult -TestName "Function '$func' is exported" -Passed $found -Message $(if (-not $found) { "Function not found in exports" })
    }
}
catch {
    Write-TestResult -TestName "FFU.Core module loads successfully" -Passed $false -Message $_.Exception.Message
}

# =============================================================================
# Test 2: Invoke-WithErrorHandling Function
# =============================================================================
Write-Host ""
Write-Host "Testing Invoke-WithErrorHandling Function..." -ForegroundColor Yellow

# Test successful operation
try {
    $result = Invoke-WithErrorHandling -Operation { return "success" } -OperationName "Test Operation"
    Write-TestResult -TestName "Successful operation returns result" -Passed ($result -eq "success")
}
catch {
    Write-TestResult -TestName "Successful operation returns result" -Passed $false -Message $_.Exception.Message
}

# Test operation with retry on failure
$retryCount = 0
try {
    $result = Invoke-WithErrorHandling -Operation {
        $script:retryCount++
        if ($script:retryCount -lt 2) { throw "Temporary failure" }
        return "recovered"
    } -OperationName "Retry Test" -MaxRetries 3 -RetryDelaySeconds 1 -SuppressErrorLog
    Write-TestResult -TestName "Retry logic works on transient failure" -Passed ($result -eq "recovered" -and $script:retryCount -eq 2)
}
catch {
    Write-TestResult -TestName "Retry logic works on transient failure" -Passed $false -Message $_.Exception.Message
}

# Test cleanup action is called on failure
$cleanupCalled = $false
try {
    Invoke-WithErrorHandling -Operation { throw "Permanent failure" } `
        -OperationName "Cleanup Test" `
        -MaxRetries 1 `
        -CleanupAction { $script:cleanupCalled = $true } `
        -SuppressErrorLog
}
catch {
    # Expected to throw
}
Write-TestResult -TestName "Cleanup action called on failure" -Passed $cleanupCalled

# =============================================================================
# Test 3: Test-ExternalCommandSuccess Function
# =============================================================================
Write-Host ""
Write-Host "Testing Test-ExternalCommandSuccess Function..." -ForegroundColor Yellow

# Test success with exit code 0
$global:LASTEXITCODE = 0
$result = Test-ExternalCommandSuccess -CommandName "TestCmd"
Write-TestResult -TestName "Exit code 0 returns success" -Passed $result

# Test failure with exit code 1 (non-robocopy)
$global:LASTEXITCODE = 1
$result = Test-ExternalCommandSuccess -CommandName "TestCmd"
Write-TestResult -TestName "Exit code 1 returns failure for non-robocopy" -Passed (-not $result)

# Test robocopy success with exit code 1 (files copied)
$global:LASTEXITCODE = 1
$result = Test-ExternalCommandSuccess -CommandName "Robocopy"
Write-TestResult -TestName "Robocopy exit code 1 returns success" -Passed $result

# Test robocopy success with exit code 3 (files copied + extra detected)
$global:LASTEXITCODE = 3
$result = Test-ExternalCommandSuccess -CommandName "robocopy test"
Write-TestResult -TestName "Robocopy exit code 3 returns success" -Passed $result

# Test robocopy failure with exit code 8
$global:LASTEXITCODE = 8
$result = Test-ExternalCommandSuccess -CommandName "Robocopy"
Write-TestResult -TestName "Robocopy exit code 8 returns failure" -Passed (-not $result)

# Test robocopy failure with exit code 16
$global:LASTEXITCODE = 16
$result = Test-ExternalCommandSuccess -CommandName "Robocopy"
Write-TestResult -TestName "Robocopy exit code 16 returns failure" -Passed (-not $result)

# Test custom success codes
$global:LASTEXITCODE = 5
$result = Test-ExternalCommandSuccess -CommandName "TestCmd" -SuccessCodes @(0, 5, 10)
Write-TestResult -TestName "Custom success codes work" -Passed $result

# =============================================================================
# Test 4: Invoke-WithCleanup Function
# =============================================================================
Write-Host ""
Write-Host "Testing Invoke-WithCleanup Function..." -ForegroundColor Yellow

# Test cleanup runs after success
$cleanupRan = $false
try {
    $result = Invoke-WithCleanup -Operation { return "done" } -Cleanup { $script:cleanupRan = $true }
    Write-TestResult -TestName "Cleanup runs after successful operation" -Passed ($cleanupRan -and $result -eq "done")
}
catch {
    Write-TestResult -TestName "Cleanup runs after successful operation" -Passed $false -Message $_.Exception.Message
}

# Test cleanup runs after failure
$cleanupRan = $false
try {
    Invoke-WithCleanup -Operation { throw "test error" } -Cleanup { $script:cleanupRan = $true }
}
catch {
    # Expected
}
Write-TestResult -TestName "Cleanup runs after failed operation" -Passed $cleanupRan

# =============================================================================
# Test 5: Module Error Handling Patterns
# =============================================================================
Write-Host ""
Write-Host "Testing Error Handling Patterns in Modules..." -ForegroundColor Yellow

# Check BuildFFUVM.ps1 for error handling patterns
$buildScript = Get-Content (Join-Path $FFUDevelopmentPath "BuildFFUVM.ps1") -Raw

$patterns = @(
    @{ Name = "Disk partitioning has try/catch"; Pattern = "# Partitioning with error handling\s+try\s*\{" },
    @{ Name = "Robocopy exit code validation present"; Pattern = "Test-RobocopySuccess|Test-ExternalCommandSuccess.*Robocopy" },
    @{ Name = "Unattend copy has error handling"; Pattern = "Copying unattend file to boot to audit mode'\s+try\s*\{" },
    @{ Name = "Optimize-Volume has error handling"; Pattern = "Optimize-Volume.*-ErrorAction Stop" }
)

foreach ($pattern in $patterns) {
    $found = $buildScript -match $pattern.Pattern
    Write-TestResult -TestName $pattern.Name -Passed $found
}

# Check FFU.VM for error handling
$vmModule = Get-Content (Join-Path $ModulesPath "FFU.VM\FFU.VM.psm1") -Raw

# VM module patterns need simpler tests due to multi-line code
$vmHasCleanupFlag = $vmModule -match '\$vmCreated\s*=\s*\$false'
$vmHasStopOnFailure = $vmModule -match 'if\s*\(\$vmCreated\)'
$vmHasRemoveVM = $vmModule -match 'Remove-VM\s+-Name\s+\$VMName\s+-Force'
Write-TestResult -TestName "New-FFUVM has VM cleanup on failure" -Passed ($vmHasCleanupFlag -and $vmHasStopOnFailure -and $vmHasRemoveVM)

$vmHasGuardianFlag = $vmModule -match '\$guardianCreated\s*=\s*\$false'
$vmHasGuardianCleanup = $vmModule -match 'if\s*\(\$guardianCreated\)'
$vmHasRemoveGuardian = $vmModule -match 'Remove-HgsGuardian\s+-Name'
Write-TestResult -TestName "New-FFUVM has guardian cleanup on failure" -Passed ($vmHasGuardianFlag -and $vmHasGuardianCleanup -and $vmHasRemoveGuardian)

# Check FFU.Imaging for error handling
$imagingModule = Get-Content (Join-Path $ModulesPath "FFU.Imaging\FFU.Imaging.psm1") -Raw

$imagingPatterns = @(
    @{ Name = "Driver injection has mount retry"; Pattern = "imageMounted.*Mount-WindowsImage.*retry|Cleanup-Mountpoints" },
    @{ Name = "Dismount has fallback handling"; Pattern = "Dismount-WindowsImage.*-Discard|-Save.*catch" }
)

foreach ($pattern in $imagingPatterns) {
    $found = $imagingModule -match $pattern.Pattern
    Write-TestResult -TestName $pattern.Name -Passed $found
}

# Check FFU.Updates for retry logic
$updatesModule = Get-Content (Join-Path $ModulesPath "FFU.Updates\FFU.Updates.psm1") -Raw

$updatesPatterns = @(
    @{ Name = "Get-KBLink has retry logic"; Pattern = "\`$maxRetries\s*=\s*3" },
    @{ Name = "Exponential backoff implemented"; Pattern = "\`$retryDelay\s*=\s*\`$retryDelay\s*\*\s*2" }
)

foreach ($pattern in $updatesPatterns) {
    $found = $updatesModule -match $pattern.Pattern
    Write-TestResult -TestName $pattern.Name -Passed $found
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
    Write-Host "All tests passed!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "Some tests failed. Please review the results above." -ForegroundColor Red
    exit 1
}
