<#
.SYNOPSIS
    Regression test for Set-CaptureFFU and Remove-FFUUserShare missing functions fix

.DESCRIPTION
    Tests that FFU.VM module functions (Set-CaptureFFU, Remove-FFUUserShare) work correctly:
    1. Functions exist and are exported
    2. Functions have correct parameter signatures
    3. Functions can be called without errors (signature validation only)

    Prevents regression of the bug: "The term 'Set-CaptureFFU' is not recognized as a name of a cmdlet..."

.NOTES
    Author: FFU Builder Team
    Date: 2025-11-23
    Related: SET_CAPTUREFFU_MISSING_FUNCTION_ANALYSIS.md
#>

#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
$testResults = @()
$totalTests = 0
$passedTests = 0
$failedTests = 0

function Write-TestHeader {
    param([string]$Message)
    Write-Host "`n===============================================" -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "===============================================`n" -ForegroundColor Cyan
}

function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Message = ""
    )

    $script:totalTests++

    if ($Passed) {
        $script:passedTests++
        Write-Host "[PASS] $TestName" -ForegroundColor Green
        if ($Message) {
            Write-Host "       $Message" -ForegroundColor Gray
        }
        $script:testResults += [PSCustomObject]@{
            Test = $TestName
            Status = "PASS"
            Message = $Message
        }
    }
    else {
        $script:failedTests++
        Write-Host "[FAIL] $TestName" -ForegroundColor Red
        if ($Message) {
            Write-Host "       $Message" -ForegroundColor Yellow
        }
        $script:testResults += [PSCustomObject]@{
            Test = $TestName
            Status = "FAIL"
            Message = $Message
        }
    }
}

# Import FFU.VM module
Write-Host "Importing FFU.VM module..." -ForegroundColor Cyan
try {
    $modulePath = Join-Path $PSScriptRoot "Modules\FFU.VM\FFU.VM.psm1"
    Import-Module $modulePath -Force -Global -WarningAction SilentlyContinue -ErrorAction Stop
    Write-Host "Module imported successfully from: $modulePath`n" -ForegroundColor Green
}
catch {
    Write-Host "ERROR: Failed to import FFU.VM module: $_" -ForegroundColor Red
    exit 1
}

Write-TestHeader "Set-CaptureFFU Missing Function Fix - Unit Tests"

# Test 1: Set-CaptureFFU function exists
Write-Host "Test 1: Validate Set-CaptureFFU function exists" -ForegroundColor Yellow
try {
    $func = Get-Command Set-CaptureFFU -ErrorAction Stop

    if ($func) {
        Write-TestResult -TestName "Set-CaptureFFU function exists" -Passed $true

        # Check it has required parameters
        $requiredParams = @('Username', 'ShareName', 'FFUCaptureLocation')
        foreach ($param in $requiredParams) {
            if ($func.Parameters.ContainsKey($param)) {
                Write-TestResult -TestName "Set-CaptureFFU has $param parameter" -Passed $true
            }
            else {
                Write-TestResult -TestName "Set-CaptureFFU has $param parameter" -Passed $false -Message "Parameter not found"
            }
        }

        # Check parameters are mandatory
        foreach ($param in $requiredParams) {
            $paramObj = $func.Parameters[$param]
            $isMandatory = $paramObj.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                          Where-Object { $_.Mandatory -eq $true }

            if ($isMandatory) {
                Write-TestResult -TestName "Set-CaptureFFU $param parameter is mandatory" -Passed $true
            }
            else {
                Write-TestResult -TestName "Set-CaptureFFU $param parameter is mandatory" -Passed $false -Message "Should be mandatory"
            }
        }
    }
    else {
        Write-TestResult -TestName "Set-CaptureFFU function exists" -Passed $false -Message "Function not found"
    }
}
catch {
    Write-TestResult -TestName "Set-CaptureFFU function validation" -Passed $false -Message $_.Exception.Message
}

# Test 2: Remove-FFUUserShare function exists
Write-Host "`nTest 2: Validate Remove-FFUUserShare function exists" -ForegroundColor Yellow
try {
    $func = Get-Command Remove-FFUUserShare -ErrorAction Stop

    if ($func) {
        Write-TestResult -TestName "Remove-FFUUserShare function exists" -Passed $true

        # Check it has required parameters
        $requiredParams = @('Username', 'ShareName')
        foreach ($param in $requiredParams) {
            if ($func.Parameters.ContainsKey($param)) {
                Write-TestResult -TestName "Remove-FFUUserShare has $param parameter" -Passed $true
            }
            else {
                Write-TestResult -TestName "Remove-FFUUserShare has $param parameter" -Passed $false -Message "Parameter not found"
            }
        }

        # Check parameters are mandatory
        foreach ($param in $requiredParams) {
            $paramObj = $func.Parameters[$param]
            $isMandatory = $paramObj.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                          Where-Object { $_.Mandatory -eq $true }

            if ($isMandatory) {
                Write-TestResult -TestName "Remove-FFUUserShare $param parameter is mandatory" -Passed $true
            }
            else {
                Write-TestResult -TestName "Remove-FFUUserShare $param parameter is mandatory" -Passed $false -Message "Should be mandatory"
            }
        }
    }
    else {
        Write-TestResult -TestName "Remove-FFUUserShare function exists" -Passed $false -Message "Function not found"
    }
}
catch {
    Write-TestResult -TestName "Remove-FFUUserShare function validation" -Passed $false -Message $_.Exception.Message
}

# Test 3: Module exports both functions
Write-Host "`nTest 3: Validate functions are exported from FFU.VM module" -ForegroundColor Yellow
try {
    $exportedFunctions = Get-Command -Module FFU.VM

    $expectedFunctions = @('Set-CaptureFFU', 'Remove-FFUUserShare')

    foreach ($funcName in $expectedFunctions) {
        $isExported = $exportedFunctions.Name -contains $funcName

        if ($isExported) {
            Write-TestResult -TestName "$funcName is exported from FFU.VM module" -Passed $true
        }
        else {
            Write-TestResult -TestName "$funcName is exported from FFU.VM module" -Passed $false -Message "Not found in exports"
        }
    }
}
catch {
    Write-TestResult -TestName "Module export validation" -Passed $false -Message $_.Exception.Message
}

# Test 4: Remove-FFUVM has Username and ShareName parameters
Write-Host "`nTest 4: Validate Remove-FFUVM has new parameters" -ForegroundColor Yellow
try {
    $func = Get-Command Remove-FFUVM -ErrorAction Stop

    if ($func) {
        Write-TestResult -TestName "Remove-FFUVM function exists" -Passed $true

        # Check for new parameters
        $newParams = @('Username', 'ShareName')
        foreach ($param in $newParams) {
            if ($func.Parameters.ContainsKey($param)) {
                Write-TestResult -TestName "Remove-FFUVM has $param parameter" -Passed $true
            }
            else {
                Write-TestResult -TestName "Remove-FFUVM has $param parameter" -Passed $false -Message "Parameter not found"
            }
        }

        # Check they have default values (not mandatory)
        foreach ($param in $newParams) {
            if ($func.Parameters.ContainsKey($param)) {
                $paramObj = $func.Parameters[$param]
                $isMandatory = $paramObj.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                              Where-Object { $_.Mandatory -eq $true }

                if (-not $isMandatory) {
                    Write-TestResult -TestName "Remove-FFUVM $param parameter is optional (has default)" -Passed $true
                }
                else {
                    Write-TestResult -TestName "Remove-FFUVM $param parameter is optional (has default)" -Passed $false -Message "Should be optional with default value"
                }
            }
        }
    }
    else {
        Write-TestResult -TestName "Remove-FFUVM function exists" -Passed $false -Message "Function not found"
    }
}
catch {
    Write-TestResult -TestName "Remove-FFUVM parameter validation" -Passed $false -Message $_.Exception.Message
}

# Summary
Write-TestHeader "Test Summary"

Write-Host "Total Tests: $totalTests" -ForegroundColor White
Write-Host "Passed: $passedTests" -ForegroundColor Green
Write-Host "Failed: $failedTests" -ForegroundColor $(if ($failedTests -gt 0) { 'Red' } else { 'Green' })
$passRate = if ($totalTests -gt 0) { [math]::Round(($passedTests / $totalTests) * 100, 1) } else { 0 }
Write-Host "Pass Rate: $passRate%`n" -ForegroundColor $(if ($passRate -eq 100) { 'Green' } elseif ($passRate -ge 80) { 'Yellow' } else { 'Red' })

if ($failedTests -gt 0) {
    Write-Host "`nFailed Tests:" -ForegroundColor Red
    $testResults | Where-Object { $_.Status -eq "FAIL" } | Format-Table -AutoSize
    Write-Host "`n[OVERALL: FAIL] Some Set-CaptureFFU fix tests failed" -ForegroundColor Red
    Write-Host "The missing function fix may not be complete. Review failures above." -ForegroundColor Yellow
    exit 1
}
else {
    Write-Host "`n[OVERALL: PASS] All Set-CaptureFFU fix tests passed!" -ForegroundColor Green
    Write-Host "The missing Set-CaptureFFU and Remove-FFUUserShare functions have been implemented successfully.`n" -ForegroundColor Cyan
    Write-Host "Key validations:" -ForegroundColor White
    Write-Host "  [OK] Set-CaptureFFU function exists and has correct signature" -ForegroundColor Green
    Write-Host "  [OK] Remove-FFUUserShare function exists and has correct signature" -ForegroundColor Green
    Write-Host "  [OK] Both functions are exported from FFU.VM module" -ForegroundColor Green
    Write-Host "  [OK] Remove-FFUVM updated with Username and ShareName parameters" -ForegroundColor Green
    exit 0
}
