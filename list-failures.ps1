#!/usr/bin/env pwsh
Set-Location "C:\claude\FFUBuilder"
$r = Invoke-Pester -Path 'Tests' -PassThru -Output None 2>$null

Write-Host ""
Write-Host "FAILING TESTS (Total: $($r.FailedCount)):"
Write-Host "=========================================="
$r.Failed | Select-Object -First 30 | ForEach-Object {
    Write-Host "  - $($_.ExpandedPath)"
}
