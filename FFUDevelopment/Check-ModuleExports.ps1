$ModulesPath = "$PSScriptRoot\Modules"
$modules = Get-ChildItem -Path $ModulesPath -Directory
$hasIssues = $false

foreach ($module in $modules) {
    $moduleName = $module.Name
    $psm1Path = Join-Path $module.FullName "$moduleName.psm1"
    $psd1Path = Join-Path $module.FullName "$moduleName.psd1"

    Write-Host "`n=== $moduleName ===" -ForegroundColor Cyan

    # Extract from .psm1
    $psm1Content = Get-Content $psm1Path -Raw -ErrorAction SilentlyContinue
    $exportMatch = [regex]::Match($psm1Content, "Export-ModuleMember\s+-Function\s+@\(([\s\S]*?)\)")
    $psm1Functions = @()
    if ($exportMatch.Success) {
        $psm1Functions = [regex]::Matches($exportMatch.Groups[1].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value }
    }

    # Extract from .psd1
    $psd1Content = Get-Content $psd1Path -Raw -ErrorAction SilentlyContinue
    $psd1Match = [regex]::Match($psd1Content, "FunctionsToExport\s*=\s*@\(([\s\S]*?)\)")
    $psd1Functions = @()
    if ($psd1Match.Success) {
        $psd1Functions = [regex]::Matches($psd1Match.Groups[1].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value }
    }

    Write-Host "  .psm1 exports: $($psm1Functions.Count) functions"
    Write-Host "  .psd1 exports: $($psd1Functions.Count) functions"

    # Find differences
    $missingInPsd1 = $psm1Functions | Where-Object { $_ -notin $psd1Functions }
    $extraInPsd1 = $psd1Functions | Where-Object { $_ -notin $psm1Functions }

    if ($missingInPsd1.Count -gt 0) {
        Write-Host "  MISSING in .psd1: $($missingInPsd1 -join ', ')" -ForegroundColor Red
        $hasIssues = $true
    }
    if ($extraInPsd1.Count -gt 0) {
        Write-Host "  EXTRA in .psd1 (not in .psm1): $($extraInPsd1 -join ', ')" -ForegroundColor Yellow
    }
    if ($missingInPsd1.Count -eq 0 -and $extraInPsd1.Count -eq 0) {
        Write-Host "  OK - Synchronized" -ForegroundColor Green
    }
}

if ($hasIssues) {
    Write-Host "`nISSUES FOUND - Some modules need manifest updates" -ForegroundColor Red
} else {
    Write-Host "`nAll modules are synchronized!" -ForegroundColor Green
}
