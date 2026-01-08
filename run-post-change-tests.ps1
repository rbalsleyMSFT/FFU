#Requires -Version 7.0
Set-Location 'C:\claude\FFUBuilder'
$r = Invoke-Pester -Path 'Tests' -PassThru -Output None
Write-Host "Post-Change: Passed=$($r.PassedCount) Failed=$($r.FailedCount) Skipped=$($r.SkippedCount)"
