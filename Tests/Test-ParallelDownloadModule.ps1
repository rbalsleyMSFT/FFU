#Requires -Version 5.1

<#
.SYNOPSIS
    Test script for FFU.Common.ParallelDownload module
#>

$ErrorActionPreference = 'Stop'

try {
    Write-Host "Testing FFU.Common.ParallelDownload module..."

    # Import the module
    $modulePath = Join-Path $PSScriptRoot "..\FFUDevelopment\FFU.Common\FFU.Common.psd1"
    Import-Module $modulePath -Force
    Write-Host "[PASS] Module imported successfully"

    # Test New-DownloadItem function
    $item = New-DownloadItem -Id 'TestKB123' `
                             -Source 'https://example.com/test.msu' `
                             -Destination 'C:\temp\test.msu' `
                             -DisplayName 'Test Update' `
                             -Category 'WindowsUpdate'

    if ($item.Id -eq 'TestKB123' -and
        $item.Source -eq 'https://example.com/test.msu' -and
        $item.Destination -eq 'C:\temp\test.msu' -and
        $item.DisplayName -eq 'Test Update' -and
        $item.Category -eq 'WindowsUpdate') {
        Write-Host "[PASS] New-DownloadItem creates object with correct properties"
    }
    else {
        Write-Host "[FAIL] New-DownloadItem properties don't match expected values"
        Write-Host "  Id: $($item.Id)"
        Write-Host "  Source: $($item.Source)"
        Write-Host "  Destination: $($item.Destination)"
        exit 1
    }

    # Test New-ParallelDownloadConfig function
    $config = New-ParallelDownloadConfig -MaxConcurrentDownloads 3 -RetryCount 5

    if ($config.MaxConcurrentDownloads -eq 3 -and $config.RetryCount -eq 5) {
        Write-Host "[PASS] New-ParallelDownloadConfig creates config with correct values"
    }
    else {
        Write-Host "[FAIL] New-ParallelDownloadConfig values don't match"
        exit 1
    }

    # Test Get-ParallelDownloadSummary function
    $mockResults = @(
        [PSCustomObject]@{ Id = 'Test1'; Success = $true; BytesDownloaded = 1000; DurationSeconds = 1.5; ErrorMessage = $null }
        [PSCustomObject]@{ Id = 'Test2'; Success = $true; BytesDownloaded = 2000; DurationSeconds = 2.0; ErrorMessage = $null }
        [PSCustomObject]@{ Id = 'Test3'; Success = $false; BytesDownloaded = 0; DurationSeconds = 0.5; ErrorMessage = 'Test error' }
    )

    $summary = Get-ParallelDownloadSummary -Results $mockResults

    if ($summary.TotalCount -eq 3 -and
        $summary.SuccessCount -eq 2 -and
        $summary.FailedCount -eq 1 -and
        $summary.TotalBytesDownloaded -eq 3000) {
        Write-Host "[PASS] Get-ParallelDownloadSummary calculates correct statistics"
    }
    else {
        Write-Host "[FAIL] Get-ParallelDownloadSummary statistics incorrect"
        Write-Host "  TotalCount: $($summary.TotalCount)"
        Write-Host "  SuccessCount: $($summary.SuccessCount)"
        Write-Host "  FailedCount: $($summary.FailedCount)"
        exit 1
    }

    # Test Start-ParallelDownloads function exists
    $cmd = Get-Command Start-ParallelDownloads -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Host "[PASS] Start-ParallelDownloads function is available"
    }
    else {
        Write-Host "[FAIL] Start-ParallelDownloads function not found"
        exit 1
    }

    Write-Host ""
    Write-Host "All tests passed!"
    exit 0
}
catch {
    Write-Host "[ERROR] $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    exit 1
}
