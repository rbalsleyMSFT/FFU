#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Test script for multi-method download fallback system

.DESCRIPTION
    Tests all download methods (BITS, Invoke-WebRequest, WebClient, curl) to ensure
    the fallback system works correctly.
#>

param(
    [switch]$Quick,  # Quick test with small file
    [switch]$SkipCleanup  # Don't delete test files
)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Download Methods Test Suite" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Setup
$ErrorActionPreference = 'Stop'
Set-Location "$PSScriptRoot\FFUDevelopment"

# Import modules
Write-Host "[Setup] Importing FFU.Common module..." -ForegroundColor Yellow
try {
    Import-Module ".\FFU.Common" -Force
    Write-Host "  ✓ Module imported successfully" -ForegroundColor Green
}
catch {
    Write-Host "  ✗ Failed to import module: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Test URLs
if ($Quick) {
    # Small test file (~1MB)
    $testUrl = "https://go.microsoft.com/fwlink/?LinkId=866658"
    $testFileName = "test_small.msi"
}
else {
    # Medium test file (~10MB)
    $testUrl = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
    $testFileName = "test_vcredist.exe"
}

$testDest = Join-Path $env:TEMP $testFileName

Write-Host "`n[Test URL] $testUrl" -ForegroundColor Cyan
Write-Host "[Test Destination] $testDest`n" -ForegroundColor Cyan

# Test results
$results = @()

# Test 1: Resilient Download (Default - tries all methods)
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Test 1: Resilient Download (Default)" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

try {
    if (Test-Path $testDest) {
        Remove-Item $testDest -Force
    }

    Write-Host "Testing Start-BitsTransferWithRetry with default settings..." -ForegroundColor Yellow

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Start-BitsTransferWithRetry -Source $testUrl -Destination $testDest -Retries 2 -Verbose
    $sw.Stop()

    if (Test-Path $testDest) {
        $fileSize = (Get-Item $testDest).Length
        $fileSizeMB = [math]::Round($fileSize / 1MB, 2)
        Write-Host "  ✓ Download successful!" -ForegroundColor Green
        Write-Host "    File size: $fileSizeMB MB" -ForegroundColor Gray
        Write-Host "    Duration: $($sw.Elapsed.TotalSeconds) seconds" -ForegroundColor Gray

        $results += [PSCustomObject]@{
            Test     = "Resilient Download (Default)"
            Status   = "PASS"
            Size     = $fileSizeMB
            Duration = $sw.Elapsed.TotalSeconds
        }

        if (-not $SkipCleanup) {
            Remove-Item $testDest -Force
        }
    }
    else {
        Write-Host "  ✗ Download reported success but file not found" -ForegroundColor Red
        $results += [PSCustomObject]@{
            Test     = "Resilient Download (Default)"
            Status   = "FAIL"
            Size     = 0
            Duration = 0
        }
    }
}
catch {
    Write-Host "  ✗ Download failed: $($_.Exception.Message)" -ForegroundColor Red
    $results += [PSCustomObject]@{
        Test     = "Resilient Download (Default)"
        Status   = "FAIL"
        Size     = 0
        Duration = 0
    }
}

# Test 2: Direct Start-ResilientDownload
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Test 2: Direct Start-ResilientDownload" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

try {
    $testDest2 = $testDest -replace '\.', '_direct.'

    if (Test-Path $testDest2) {
        Remove-Item $testDest2 -Force
    }

    Write-Host "Testing Start-ResilientDownload directly..." -ForegroundColor Yellow

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Start-ResilientDownload -Source $testUrl -Destination $testDest2 -Retries 2 -Verbose
    $sw.Stop()

    if (Test-Path $testDest2) {
        $fileSize = (Get-Item $testDest2).Length
        $fileSizeMB = [math]::Round($fileSize / 1MB, 2)
        Write-Host "  ✓ Download successful!" -ForegroundColor Green
        Write-Host "    File size: $fileSizeMB MB" -ForegroundColor Gray
        Write-Host "    Duration: $($sw.Elapsed.TotalSeconds) seconds" -ForegroundColor Gray

        $results += [PSCustomObject]@{
            Test     = "Start-ResilientDownload"
            Status   = "PASS"
            Size     = $fileSizeMB
            Duration = $sw.Elapsed.TotalSeconds
        }

        if (-not $SkipCleanup) {
            Remove-Item $testDest2 -Force
        }
    }
    else {
        Write-Host "  ✗ Download reported success but file not found" -ForegroundColor Red
        $results += [PSCustomObject]@{
            Test     = "Start-ResilientDownload"
            Status   = "FAIL"
            Size     = 0
            Duration = 0
        }
    }
}
catch {
    Write-Host "  ✗ Download failed: $($_.Exception.Message)" -ForegroundColor Red
    $results += [PSCustomObject]@{
        Test     = "Start-ResilientDownload"
        Status   = "FAIL"
        Size     = 0
        Duration = 0
    }
}

# Test 3: BITS-Only Mode (Legacy)
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Test 3: BITS-Only Mode (Legacy)" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

try {
    $testDest3 = $testDest -replace '\.', '_bits.'

    if (Test-Path $testDest3) {
        Remove-Item $testDest3 -Force
    }

    Write-Host "Testing BITS-only mode (UseResilientDownload = false)..." -ForegroundColor Yellow

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Start-BitsTransferWithRetry -Source $testUrl -Destination $testDest3 -UseResilientDownload $false -Retries 2 -Verbose
    $sw.Stop()

    if (Test-Path $testDest3) {
        $fileSize = (Get-Item $testDest3).Length
        $fileSizeMB = [math]::Round($fileSize / 1MB, 2)
        Write-Host "  ✓ BITS download successful!" -ForegroundColor Green
        Write-Host "    File size: $fileSizeMB MB" -ForegroundColor Gray
        Write-Host "    Duration: $($sw.Elapsed.TotalSeconds) seconds" -ForegroundColor Gray

        $results += [PSCustomObject]@{
            Test     = "BITS-Only (Legacy)"
            Status   = "PASS"
            Size     = $fileSizeMB
            Duration = $sw.Elapsed.TotalSeconds
        }

        if (-not $SkipCleanup) {
            Remove-Item $testDest3 -Force
        }
    }
    else {
        Write-Host "  ✗ Download reported success but file not found" -ForegroundColor Red
        $results += [PSCustomObject]@{
            Test     = "BITS-Only (Legacy)"
            Status   = "FAIL"
            Size     = 0
            Duration = 0
        }
    }
}
catch {
    $errorMsg = $_.Exception.Message

    if ($errorMsg -like "*0x800704DD*") {
        Write-Host "  ⚠ BITS failed with 0x800704DD (expected in some contexts)" -ForegroundColor Yellow
        Write-Host "    This is why we need the resilient download system!" -ForegroundColor Yellow
        $results += [PSCustomObject]@{
            Test     = "BITS-Only (Legacy)"
            Status   = "EXPECTED FAIL (0x800704DD)"
            Size     = 0
            Duration = 0
        }
    }
    else {
        Write-Host "  ✗ Download failed: $errorMsg" -ForegroundColor Red
        $results += [PSCustomObject]@{
            Test     = "BITS-Only (Legacy)"
            Status   = "FAIL"
            Size     = 0
            Duration = 0
        }
    }
}

# Test 4: Skip BITS Entirely
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Test 4: Skip BITS (Force Fallback)" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

try {
    $testDest4 = $testDest -replace '\.', '_skipbits.'

    if (Test-Path $testDest4) {
        Remove-Item $testDest4 -Force
    }

    Write-Host "Testing with -SkipBITS (goes straight to Invoke-WebRequest)..." -ForegroundColor Yellow

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Start-ResilientDownload -Source $testUrl -Destination $testDest4 -SkipBITS -Retries 2 -Verbose
    $sw.Stop()

    if (Test-Path $testDest4) {
        $fileSize = (Get-Item $testDest4).Length
        $fileSizeMB = [math]::Round($fileSize / 1MB, 2)
        Write-Host "  ✓ Download successful (without BITS)!" -ForegroundColor Green
        Write-Host "    File size: $fileSizeMB MB" -ForegroundColor Gray
        Write-Host "    Duration: $($sw.Elapsed.TotalSeconds) seconds" -ForegroundColor Gray

        $results += [PSCustomObject]@{
            Test     = "Skip BITS (Fallback Only)"
            Status   = "PASS"
            Size     = $fileSizeMB
            Duration = $sw.Elapsed.TotalSeconds
        }

        if (-not $SkipCleanup) {
            Remove-Item $testDest4 -Force
        }
    }
    else {
        Write-Host "  ✗ Download reported success but file not found" -ForegroundColor Red
        $results += [PSCustomObject]@{
            Test     = "Skip BITS (Fallback Only)"
            Status   = "FAIL"
            Size     = 0
            Duration = 0
        }
    }
}
catch {
    Write-Host "  ✗ Download failed: $($_.Exception.Message)" -ForegroundColor Red
    $results += [PSCustomObject]@{
        Test     = "Skip BITS (Fallback Only)"
        Status   = "FAIL"
        Size     = 0
        Duration = 0
    }
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Test Summary" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$results | Format-Table -AutoSize

$passCount = ($results | Where-Object { $_.Status -eq "PASS" }).Count
$totalTests = $results.Count

Write-Host "`nResults: $passCount / $totalTests tests passed" -ForegroundColor $(if ($passCount -eq $totalTests) { 'Green' } else { 'Yellow' })

if ($passCount -ge 2) {
    Write-Host "`n✓ SUCCESS: The resilient download system is working!" -ForegroundColor Green
    Write-Host "  Downloads will automatically fall back if BITS fails." -ForegroundColor Green
}
else {
    Write-Host "`n⚠ WARNING: Some download methods failed." -ForegroundColor Yellow
    Write-Host "  Check your network connectivity and firewall settings." -ForegroundColor Yellow
}

Write-Host ""
