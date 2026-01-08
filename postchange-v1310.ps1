#!/usr/bin/env pwsh
# Post-change regression test runner for v1.3.10 changes
Set-Location "C:\claude\FFUBuilder"
$result = Invoke-Pester -Path 'Tests' -PassThru -Output None

Write-Host ""
Write-Host "POST-CHANGE REGRESSION RESULTS (v1.3.10):"
Write-Host "  Passed: $($result.PassedCount)"
Write-Host "  Failed: $($result.FailedCount)"
Write-Host "  Skipped: $($result.SkippedCount)"
