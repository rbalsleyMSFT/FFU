#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Simple test for multi-method download fallback
#>

Write-Host "`n=== Download Methods Test ===`n" -ForegroundColor Cyan

# Navigate to FFUDevelopment
Set-Location "$PSScriptRoot\FFUDevelopment"

# Import module
Write-Host "[1] Importing FFU.Common module..." -ForegroundColor Yellow
try {
    Import-Module ".\FFU.Common" -Force
    Write-Host "    ✓ Module imported" -ForegroundColor Green
}
catch {
    Write-Host "    ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Check if Start-ResilientDownload exists
if (Get-Command Start-ResilientDownload -ErrorAction SilentlyContinue) {
    Write-Host "    ✓ Start-ResilientDownload available" -ForegroundColor Green
}
else {
    Write-Host "    ✗ Start-ResilientDownload not found" -ForegroundColor Red
    exit 1
}

# Test download
$testUrl = "https://go.microsoft.com/fwlink/?LinkId=866658"
$testDest = Join-Path $env:TEMP "ffu_download_test.tmp"

Write-Host "`n[2] Testing resilient download..." -ForegroundColor Yellow
Write-Host "    URL: $testUrl" -ForegroundColor Gray
Write-Host "    Dest: $testDest" -ForegroundColor Gray

if (Test-Path $testDest) {
    Remove-Item $testDest -Force
}

try {
    Start-BitsTransferWithRetry -Source $testUrl -Destination $testDest -Retries 2

    if (Test-Path $testDest) {
        $fileSize = (Get-Item $testDest).Length
        $fileSizeMB = [math]::Round($fileSize / 1MB, 2)
        Write-Host "    ✓ Download successful! ($fileSizeMB MB)" -ForegroundColor Green

        # Cleanup
        Remove-Item $testDest -Force
        Write-Host "`n✓ TEST PASSED: Fallback system is working!" -ForegroundColor Green
    }
    else {
        Write-Host "    ✗ File not created" -ForegroundColor Red
        Write-Host "`n✗ TEST FAILED" -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Host "    ✗ Download failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "`n✗ TEST FAILED" -ForegroundColor Red
    exit 1
}

Write-Host ""
