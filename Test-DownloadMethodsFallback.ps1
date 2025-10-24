#Requires -RunAsAdministrator

Write-Host ""
Write-Host "=== Download Methods Fallback Test ===" -ForegroundColor Cyan
Write-Host ""

Set-Location "$PSScriptRoot\FFUDevelopment"

Write-Host "[1] Importing FFU.Common module..." -ForegroundColor Yellow
Import-Module ".\FFU.Common" -Force
Write-Host "    PASS: Module imported" -ForegroundColor Green

$testUrl = "https://go.microsoft.com/fwlink/?LinkId=866658"
$testDest = Join-Path $env:TEMP "ffu_test.tmp"

Write-Host ""
Write-Host "[2] Testing download with fallback..." -ForegroundColor Yellow
Write-Host "    URL: $testUrl" -ForegroundColor Gray

if (Test-Path $testDest) { Remove-Item $testDest -Force }

Start-BitsTransferWithRetry -Source $testUrl -Destination $testDest -Retries 2

if (Test-Path $testDest) {
    $sizeMB = [math]::Round((Get-Item $testDest).Length / 1MB, 2)
    Write-Host "    PASS: Downloaded $sizeMB MB" -ForegroundColor Green
    Remove-Item $testDest -Force
    Write-Host ""
    Write-Host "SUCCESS: Fallback system works!" -ForegroundColor Green
    Write-Host ""
}
else {
    Write-Host "    FAIL: File not created" -ForegroundColor Red
    exit 1
}
