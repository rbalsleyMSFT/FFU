cd "C:\claude\FFUBuilder"
$r = Invoke-Pester -Path 'Tests' -PassThru -Output None
Write-Host "POST-CHANGE REGRESSION RESULTS:"
Write-Host "  Passed: $($r.PassedCount)"
Write-Host "  Failed: $($r.FailedCount)"
Write-Host "  Skipped: $($r.SkippedCount)"
