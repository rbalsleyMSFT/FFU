Write-Host "Testing BuildFFUVM.ps1 syntax..." -ForegroundColor Cyan

$scriptPath = Join-Path $PSScriptRoot "BuildFFUVM.ps1"
$errors = $null
$content = Get-Content $scriptPath -Raw

$null = [System.Management.Automation.PSParser]::Tokenize($content, [ref]$errors)

if ($errors) {
    Write-Host "ERRORS FOUND:" -ForegroundColor Red
    $errors | ForEach-Object {
        Write-Host "  Line $($_.Token.StartLine): $($_.Message)" -ForegroundColor Red
    }
    exit 1
}
else {
    Write-Host "BuildFFUVM.ps1 syntax is VALID" -ForegroundColor Green
}
