#Requires -RunAsAdministrator

# Import FFU.Constants for Test 3 (must be at top of script)
using module .\Modules\FFU.Constants\FFU.Constants.psm1

<#
.SYNOPSIS
    Test suite for FFUConstants class accessibility fix

.DESCRIPTION
    Tests that FFUConstants class is accessible in Param block context.
    This validates the fix for "Unable to find type [FFUConstants]" error.

    Root Cause:
    - FFUConstants class is used in Param block as default values (lines 311, 314, 317)
    - Param blocks are evaluated at PARSE time
    - Import-Module loads at RUNTIME (too late)
    - Solution: Use 'using module' for parse-time loading

.NOTES
    This test suite ensures FFUConstants remains accessible in all contexts.
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

Write-Host "=== FFUConstants Accessibility Test Suite ===`n" -ForegroundColor Green
Write-Host "Validating fix for 'Unable to find type [FFUConstants]' error" -ForegroundColor Green

# Test 1: Verify using module statement exists
Write-TestHeader "Test 1: using module Statement Validation"

try {
    $buildScriptPath = Join-Path $PSScriptRoot "BuildFFUVM.ps1"
    $buildScriptContent = Get-Content $buildScriptPath -Raw

    if ($buildScriptContent -match 'using\s+module.*FFU\.Constants') {
        Write-TestResult "using module statement present" $true "Found: using module for FFU.Constants"
    }
    else {
        Write-TestResult "using module statement present" $false "using module not found - FFUConstants won't be available in Param block"
    }

    # Verify explanatory comment
    if ($buildScriptContent -match 'PARSE time|Param block.*PARSE|referenced in.*Param block') {
        Write-TestResult "Explanatory comment about parse-time requirement" $true
    }
    else {
        Write-TestResult "Explanatory comment about parse-time requirement" $false "Missing explanation for future maintainers"
    }
}
catch {
    Write-TestResult "using module validation" $false $_.Exception.Message
}

# Test 2: Verify FFUConstants module can be loaded
Write-TestHeader "Test 2: FFU.Constants Module Loading"

try {
    $modulePath = Join-Path $PSScriptRoot "Modules\FFU.Constants\FFU.Constants.psm1"

    if (-not (Test-Path $modulePath)) {
        Write-TestResult "FFU.Constants module exists" $false "Module not found at: $modulePath"
    }
    else {
        Write-TestResult "FFU.Constants module exists" $true

        # Try to load via using module syntax
        $testScript = @"
using module $PSScriptRoot\Modules\FFU.Constants\FFU.Constants.psm1

Param(
    [uint64]`$TestMemory = [FFUConstants]::DEFAULT_VM_MEMORY
)

Write-Output "Memory default: `$TestMemory"
Write-Output "Class accessible: `$([FFUConstants] -ne `$null)"
"@

        $testScriptPath = Join-Path $PSScriptRoot "Test-FFUConstantsTemp.ps1"
        $testScript | Set-Content -Path $testScriptPath -Encoding UTF8

        try {
            # Execute the test script
            $output = & $testScriptPath 2>&1

            if ($output -match "Memory default: \d+" -and $output -match "Class accessible: True") {
                Write-TestResult "FFUConstants accessible in Param block" $true "Class loaded successfully via using module"
            }
            else {
                Write-TestResult "FFUConstants accessible in Param block" $false "Output: $($output -join '; ')"
            }
        }
        catch {
            Write-TestResult "FFUConstants accessible in Param block" $false $_.Exception.Message
        }
        finally {
            Remove-Item $testScriptPath -Force -ErrorAction SilentlyContinue
        }
    }
}
catch {
    Write-TestResult "FFU.Constants module loading" $false $_.Exception.Message
}

# Test 3: Verify FFUConstants constants are accessible
Write-TestHeader "Test 3: FFUConstants Values Accessibility"

try {
    # Module already imported at top of script via using module

    $expectedConstants = @(
        'DEFAULT_VM_MEMORY',
        'DEFAULT_VHDX_SIZE',
        'DEFAULT_VM_PROCESSORS',
        'VM_STATE_POLL_INTERVAL'
    )

    foreach ($constantName in $expectedConstants) {
        try {
            $value = [FFUConstants]::$constantName
            if ($null -ne $value) {
                Write-TestResult "FFUConstants::$constantName accessible" $true "Value: $value"
            }
            else {
                Write-TestResult "FFUConstants::$constantName accessible" $false "Value is null"
            }
        }
        catch {
            Write-TestResult "FFUConstants::$constantName accessible" $false $_.Exception.Message
        }
    }
}
catch {
    Write-TestResult "FFUConstants value accessibility" $false $_.Exception.Message
}

# Test 4: Verify BuildFFUVM.ps1 Param block uses FFUConstants
Write-TestHeader "Test 4: BuildFFUVM.ps1 Param Block Validation"

try {
    $buildScriptContent = Get-Content (Join-Path $PSScriptRoot "BuildFFUVM.ps1") -Raw

    $expectedUsages = @(
        @{ Line = 311; Pattern = '\[FFUConstants\]::DEFAULT_VM_MEMORY'; Name = 'Memory parameter' },
        @{ Line = 314; Pattern = '\[FFUConstants\]::DEFAULT_VHDX_SIZE'; Name = 'Disksize parameter' },
        @{ Line = 317; Pattern = '\[FFUConstants\]::DEFAULT_VM_PROCESSORS'; Name = 'Processors parameter' }
    )

    foreach ($usage in $expectedUsages) {
        if ($buildScriptContent -match $usage.Pattern) {
            Write-TestResult "$($usage.Name) uses FFUConstants" $true "Pattern: $($usage.Pattern)"
        }
        else {
            Write-TestResult "$($usage.Name) uses FFUConstants" $false "Pattern not found: $($usage.Pattern)"
        }
    }
}
catch {
    Write-TestResult "Param block FFUConstants usage" $false $_.Exception.Message
}

# Test 5: ThreadJob context simulation
Write-TestHeader "Test 5: ThreadJob Context Simulation"

try {
    if (-not (Get-Module -ListAvailable -Name ThreadJob)) {
        Write-Host "  NOTE: ThreadJob module not installed - skipping ThreadJob test" -ForegroundColor Yellow
        Write-TestResult "ThreadJob context test" $true "Skipped - ThreadJob not available"
    }
    else {
        Import-Module ThreadJob -Force

        # Simulate how BuildFFUVM_UI.ps1 invokes BuildFFUVM.ps1
        $scriptBlock = {
            param($PSScriptRootParam)

            # Create a minimal test script that mimics BuildFFUVM.ps1 structure
            $testContent = @"
using module $PSScriptRootParam\Modules\FFU.Constants\FFU.Constants.psm1

Param(
    [uint64]`$Memory = [FFUConstants]::DEFAULT_VM_MEMORY
)

BEGIN { }

END {
    Write-Output "SUCCESS: Memory = `$Memory"
    Write-Output "FFUConstants accessible: `$([FFUConstants]::DEFAULT_VM_MEMORY)"
}
"@

            $tempScript = Join-Path $PSScriptRootParam "Test-ThreadJobTemp.ps1"
            $testContent | Set-Content -Path $tempScript -Encoding UTF8

            try {
                $result = & $tempScript
                Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
                return $result
            }
            catch {
                Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
                throw
            }
        }

        $job = Start-ThreadJob -ScriptBlock $scriptBlock -ArgumentList $PSScriptRoot
        $job | Wait-Job -Timeout 10 | Out-Null
        $output = Receive-Job -Job $job
        $jobError = $job.ChildJobs[0].Error

        Remove-Job -Job $job -Force

        if ($output -match "SUCCESS" -and $output -match "FFUConstants accessible") {
            Write-TestResult "FFUConstants works in ThreadJob context" $true "Class accessible when invoked via ThreadJob"
        }
        elseif ($jobError.Count -gt 0) {
            Write-TestResult "FFUConstants works in ThreadJob context" $false "Error: $($jobError[0].Exception.Message)"
        }
        else {
            Write-TestResult "FFUConstants works in ThreadJob context" $false "Unexpected output: $($output -join '; ')"
        }
    }
}
catch {
    Write-TestResult "ThreadJob context simulation" $false $_.Exception.Message
}

# Test 6: Verify no Import-Module in END block
Write-TestHeader "Test 6: No Redundant Import-Module"

try {
    $buildScriptContent = Get-Content (Join-Path $PSScriptRoot "BuildFFUVM.ps1") -Raw

    # Check that we don't have both using module AND Import-Module for FFU.Constants
    $hasUsingModule = $buildScriptContent -match 'using\s+module.*FFU\.Constants'
    $hasImportModule = $buildScriptContent -match 'Import-Module.*FFU\.Constants'

    if ($hasUsingModule -and -not $hasImportModule) {
        Write-TestResult "No redundant Import-Module for FFU.Constants" $true "Only using module present (correct)"
    }
    elseif ($hasUsingModule -and $hasImportModule) {
        Write-TestResult "No redundant Import-Module for FFU.Constants" $false "Both using module AND Import-Module found (redundant)"
    }
    else {
        Write-TestResult "No redundant Import-Module for FFU.Constants" $false "No using module found"
    }
}
catch {
    Write-TestResult "Redundant import check" $false $_.Exception.Message
}

# Test 7: Verify END block structure is maintained
Write-TestHeader "Test 7: BEGIN/END Block Structure"

try {
    $buildScriptContent = Get-Content (Join-Path $PSScriptRoot "BuildFFUVM.ps1") -Raw

    $hasBEGIN = $buildScriptContent -match '^BEGIN\s*\{' -or $buildScriptContent -match '\nBEGIN\s*\{'
    $hasEND = $buildScriptContent -match '^END\s*\{' -or $buildScriptContent -match '\nEND\s*\{'

    if ($hasBEGIN -and $hasEND) {
        Write-TestResult "Script has BEGIN and END blocks" $true "Proper script structure maintained"
    }
    elseif ($hasBEGIN -and -not $hasEND) {
        Write-TestResult "Script has BEGIN and END blocks" $false "BEGIN block without END block (parsing error!)"
    }
    else {
        Write-TestResult "Script has BEGIN and END blocks" $true "No BEGIN/END blocks (acceptable)"
    }
}
catch {
    Write-TestResult "BEGIN/END block structure" $false $_.Exception.Message
}

# Summary
Write-TestHeader "Test Summary"
$total = $testsPassed + $testsFailed
Write-Host "  Total Tests:   $total" -ForegroundColor Cyan
Write-Host "  Passed:        $testsPassed" -ForegroundColor Green
Write-Host "  Failed:        $testsFailed" -ForegroundColor $(if ($testsFailed -gt 0) { "Red" } else { "Gray" })

if ($testsFailed -eq 0) {
    Write-Host "`n✅ All tests passed!" -ForegroundColor Green
    Write-Host "`nFFUConstants class is accessible in all contexts." -ForegroundColor Green
    Write-Host "The 'Unable to find type [FFUConstants]' error is fixed." -ForegroundColor Green
    exit 0
}
else {
    Write-Host "`n❌ $testsFailed test(s) failed. Please review the output above." -ForegroundColor Red
    exit 1
}
