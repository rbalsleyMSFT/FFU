#!/usr/bin/env pwsh
# Baseline regression test runner for v1.3.8 changes

Set-Location "C:\claude\FFUBuilder"
$result = Invoke-Pester -Path 'Tests' -PassThru -Output None

Write-Host ""
Write-Host "BASELINE REGRESSION RESULTS (v1.3.8):"
Write-Host "  Passed: $($result.PassedCount)"
Write-Host "  Failed: $($result.FailedCount)"
Write-Host "  Skipped: $($result.SkippedCount)"
