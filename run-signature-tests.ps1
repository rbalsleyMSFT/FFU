#!/usr/bin/env pwsh
Set-Location "C:\claude\FFUBuilder"
$result = Invoke-Pester -Path 'Tests\Unit\FFU.Common.Logging.SignatureCompatibility.Tests.ps1' -PassThru -Output None
Write-Host ""
Write-Host "SIGNATURE COMPATIBILITY TEST RESULTS:"
Write-Host "  Passed: $($result.PassedCount)"
Write-Host "  Failed: $($result.FailedCount)"
Write-Host "  Skipped: $($result.SkippedCount)"
