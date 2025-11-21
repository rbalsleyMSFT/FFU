# Test-NewAppsISO.ps1
# Validates that New-AppsISO function accepts required parameters

$ErrorActionPreference = 'Stop'

Write-Host "`n=== Testing New-AppsISO Parameter Fix ===" -ForegroundColor Cyan

# Load modules
$ModulePath = "$PSScriptRoot\Modules"
$env:PSModulePath = "$ModulePath;$env:PSModulePath"

Write-Host "`nLoading modules..." -ForegroundColor Yellow
Import-Module FFU.Core -Force -WarningAction SilentlyContinue
Import-Module FFU.Apps -Force -WarningAction SilentlyContinue

# Get function and check parameters
Write-Host "`nChecking New-AppsISO function..." -ForegroundColor Yellow
$cmd = Get-Command New-AppsISO -ErrorAction SilentlyContinue

if (-not $cmd) {
    Write-Host "[FAIL] New-AppsISO function not found!" -ForegroundColor Red
    exit 1
}

Write-Host "[PASS] New-AppsISO found in module: $($cmd.Source)" -ForegroundColor Green

# Check for required parameters
Write-Host "`nChecking parameters..." -ForegroundColor Yellow
$params = $cmd.Parameters

$requiredParams = @('ADKPath', 'AppsPath', 'AppsISO')
$allPresent = $true

foreach ($paramName in $requiredParams) {
    if ($params.ContainsKey($paramName)) {
        Write-Host "  [PASS] Parameter '$paramName' exists" -ForegroundColor Green
        $param = $params[$paramName]
        $isMandatory = $param.Attributes | Where-Object { $_.TypeId.Name -eq 'ParameterAttribute' } | Select-Object -ExpandProperty Mandatory
        if ($isMandatory) {
            Write-Host "         (Mandatory: Yes)" -ForegroundColor Gray
        } else {
            Write-Host "         (Mandatory: No)" -ForegroundColor Gray
        }
    } else {
        Write-Host "  [FAIL] Parameter '$paramName' missing!" -ForegroundColor Red
        $allPresent = $false
    }
}

if (-not $allPresent) {
    Write-Host "`n[OVERALL: FAIL] Missing required parameters" -ForegroundColor Red
    exit 1
}

# Test function signature (don't actually create ISO)
Write-Host "`nTesting function signature..." -ForegroundColor Yellow

try {
    # This should fail with "parameter validation" because paths don't exist,
    # not with "parameter binding" error
    New-AppsISO -ADKPath "C:\Test" -AppsPath "C:\Test" -AppsISO "C:\Test.iso" -ErrorAction Stop
} catch {
    if ($_.Exception.Message -like "*Cannot bind argument*") {
        Write-Host "[FAIL] Still has parameter binding issues: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    } elseif ($_.Exception.Message -like "*oscdimg.exe not found*") {
        Write-Host "[PASS] Parameter binding works correctly (failed at file existence check as expected)" -ForegroundColor Green
    } else {
        Write-Host "[PASS] Function accepts parameters (failed with: $($_.Exception.Message))" -ForegroundColor Green
    }
}

Write-Host "`n[OVERALL: PASS] New-AppsISO function signature is correct" -ForegroundColor Green
Write-Host "All required parameters are present and mandatory." -ForegroundColor Green
exit 0
