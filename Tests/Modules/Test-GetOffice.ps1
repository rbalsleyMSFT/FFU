# Test-GetOffice.ps1
# Comprehensive validation for Get-Office function parameter fix

<#
.SYNOPSIS
Tests Get-Office function to ensure all required parameters are properly defined

.DESCRIPTION
Validates that the Get-Office function has been fixed to accept all required
parameters explicitly instead of relying on script-scope variables. This prevents
"Cannot bind argument to parameter 'Path' because it is null" errors during
Office download and extraction.

.EXAMPLE
.\Test-GetOffice.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$script:TestResults = @()
$script:TestsPassed = 0
$script:TestsFailed = 0

# Helper function to add test results
function Add-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Message
    )

    $result = [PSCustomObject]@{
        Test = $TestName
        Status = if ($Passed) { "PASS" } else { "FAIL" }
        Message = $Message
        Timestamp = Get-Date
    }

    $script:TestResults += $result

    if ($Passed) {
        $script:TestsPassed++
        Write-Host "[PASS] $TestName" -ForegroundColor Green
        if ($Message) { Write-Host "       $Message" -ForegroundColor Gray }
    } else {
        $script:TestsFailed++
        Write-Host "[FAIL] $TestName" -ForegroundColor Red
        Write-Host "       $Message" -ForegroundColor Red
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Get-Office Parameter Validation Tests" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Load modules
$ModulePath = "$PSScriptRoot\Modules"
$env:PSModulePath = "$ModulePath;$env:PSModulePath"

Write-Host "Loading FFU modules..." -ForegroundColor Yellow
try {
    Import-Module FFU.Core -Force -WarningAction SilentlyContinue -ErrorAction Stop
    Import-Module FFU.Apps -Force -WarningAction SilentlyContinue -ErrorAction Stop
    Write-Host "Modules loaded successfully`n" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to load modules: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ============================================
# Test 1: Function Existence
# ============================================
Write-Host "Test 1: Function Existence" -ForegroundColor Cyan

$cmd = Get-Command Get-Office -ErrorAction SilentlyContinue

if ($cmd) {
    Add-TestResult -TestName "Get-Office function exists" `
                   -Passed $true `
                   -Message "Found in module: $($cmd.Source)"
} else {
    Add-TestResult -TestName "Get-Office function exists" `
                   -Passed $false `
                   -Message "Function not found"
    exit 1
}

# ============================================
# Test 2: Required Parameters
# ============================================
Write-Host "`nTest 2: Required Parameters" -ForegroundColor Cyan

$params = $cmd.Parameters
$requiredParams = @{
    'OfficePath' = 'Path to Office download folder'
    'OfficeDownloadXML' = 'Download configuration XML path'
    'OrchestrationPath' = 'Path to orchestration scripts folder'
    'FFUDevelopmentPath' = 'Root FFUDevelopment path'
    'Headers' = 'HTTP headers hashtable'
    'UserAgent' = 'User agent string'
}

foreach ($paramName in $requiredParams.Keys) {
    if ($params.ContainsKey($paramName)) {
        $param = $params[$paramName]
        $attrs = $param.Attributes | Where-Object { $_.TypeId.Name -eq 'ParameterAttribute' }
        $isMandatory = $attrs | Select-Object -ExpandProperty Mandatory -First 1

        Add-TestResult -TestName "Parameter '$paramName' exists and is mandatory" `
                       -Passed $isMandatory `
                       -Message $(if ($isMandatory) { $requiredParams[$paramName] } else { "Parameter exists but is not mandatory!" })
    } else {
        Add-TestResult -TestName "Parameter '$paramName' exists and is mandatory" `
                       -Passed $false `
                       -Message "Parameter missing from function signature"
    }
}

# ============================================
# Test 3: Optional Parameters
# ============================================
Write-Host "`nTest 3: Optional Parameters" -ForegroundColor Cyan

$optionalParams = @{
    'OfficeInstallXML' = 'Install configuration XML filename'
    'OfficeConfigXMLFile' = 'Custom Office config XML path'
}

foreach ($paramName in $optionalParams.Keys) {
    if ($params.ContainsKey($paramName)) {
        $param = $params[$paramName]
        $attrs = $param.Attributes | Where-Object { $_.TypeId.Name -eq 'ParameterAttribute' }
        $isMandatory = $attrs | Select-Object -ExpandProperty Mandatory -First 1

        Add-TestResult -TestName "Optional parameter '$paramName' exists" `
                       -Passed (-not $isMandatory) `
                       -Message $(if (-not $isMandatory) { $optionalParams[$paramName] } else { "Should be optional but is mandatory!" })
    } else {
        Add-TestResult -TestName "Optional parameter '$paramName' exists" `
                       -Passed $false `
                       -Message "Parameter missing from function signature"
    }
}

# ============================================
# Test 4: Parameter Binding Test
# ============================================
Write-Host "`nTest 4: Parameter Binding Validation" -ForegroundColor Cyan

try {
    # Test with mock parameters (function should fail at execution, not parameter binding)
    $testParams = @{
        OfficePath = "C:\Test\Office"
        OfficeDownloadXML = "C:\Test\Download.xml"
        OfficeInstallXML = "Install.xml"
        OrchestrationPath = "C:\Test\Orchestration"
        FFUDevelopmentPath = "C:\Test"
        Headers = @{ "Accept" = "text/html" }
        UserAgent = "TestAgent/1.0"
        OfficeConfigXMLFile = ""
    }

    # This should fail at execution (file not found), not at parameter binding
    Get-Office @testParams -ErrorAction Stop 2>$null
} catch {
    $errorMessage = $_.Exception.Message

    if ($errorMessage -like "*Cannot bind argument*") {
        Add-TestResult -TestName "Parameter binding works (no null parameter errors)" `
                       -Passed $false `
                       -Message "Still has parameter binding issues: $errorMessage"
    } elseif ($errorMessage -like "*error occurred while retrieving the ODT URL*" -or
              $errorMessage -like "*OutFile*" -or
              $errorMessage -like "*Cannot find path*") {
        Add-TestResult -TestName "Parameter binding works (no null parameter errors)" `
                       -Passed $true `
                       -Message "Parameters bind correctly (failed at execution as expected)"
    } else {
        Add-TestResult -TestName "Parameter binding works (no null parameter errors)" `
                       -Passed $true `
                       -Message "Parameters accepted (error: $($errorMessage.Substring(0, [Math]::Min(50, $errorMessage.Length)))...)"
    }
}

# ============================================
# Test 5: Help Documentation
# ============================================
Write-Host "`nTest 5: Help Documentation" -ForegroundColor Cyan

$help = Get-Help Get-Office -ErrorAction SilentlyContinue

if ($help -and $help.Synopsis) {
    Add-TestResult -TestName "Function has help documentation" `
                   -Passed $true `
                   -Message "Synopsis: $($help.Synopsis)"
} else {
    Add-TestResult -TestName "Function has help documentation" `
                   -Passed $false `
                   -Message "No help documentation found"
}

$exampleCount = ($help.examples.example | Measure-Object).Count
Add-TestResult -TestName "Function has usage examples" `
               -Passed ($exampleCount -gt 0) `
               -Message "$exampleCount example(s) provided"

# ============================================
# Summary
# ============================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$totalTests = $script:TestsPassed + $script:TestsFailed
$passRate = if ($totalTests -gt 0) { [Math]::Round(($script:TestsPassed / $totalTests) * 100, 1) } else { 0 }

Write-Host "`nTotal Tests: $totalTests" -ForegroundColor White
Write-Host "Passed: $script:TestsPassed" -ForegroundColor Green
Write-Host "Failed: $script:TestsFailed" -ForegroundColor $(if ($script:TestsFailed -gt 0) { "Red" } else { "Green" })
Write-Host "Pass Rate: $passRate%" -ForegroundColor $(if ($passRate -ge 90) { "Green" } elseif ($passRate -ge 70) { "Yellow" } else { "Red" })

Write-Host "`nDetailed Results:" -ForegroundColor White
$script:TestResults | Format-Table Test, Status, Message -AutoSize -Wrap

# Return exit code
if ($script:TestsFailed -gt 0) {
    Write-Host "`n[OVERALL: FAIL] Some tests failed" -ForegroundColor Red
    Write-Host "The Get-Office function may have parameter issues." -ForegroundColor Yellow
    exit 1
} else {
    Write-Host "`n[OVERALL: PASS] All tests passed!" -ForegroundColor Green
    Write-Host "Get-Office function is properly parameterized and ready to use." -ForegroundColor Green
    exit 0
}
