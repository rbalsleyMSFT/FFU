# Simple parse check for BuildFFUVM.ps1

$scriptPath = Join-Path $PSScriptRoot "BuildFFUVM.ps1"
$scriptContent = Get-Content $scriptPath -Raw

Write-Host "Checking BuildFFUVM.ps1 for parse errors..." -ForegroundColor Cyan

# Method 1: PSParser (PowerShell 5.1 compatible)
$parseErrors = @()
$null = [System.Management.Automation.PSParser]::Tokenize($scriptContent, [ref]$parseErrors)

if ($parseErrors.Count -gt 0) {
    Write-Host "`nPSParser found errors:" -ForegroundColor Red
    $parseErrors | ForEach-Object {
        Write-Host "  Line $($_.Token.StartLine): $($_.Message)" -ForegroundColor Red
    }
}
else {
    Write-Host "PSParser: No errors ✅" -ForegroundColor Green
}

# Method 2: Try to create ScriptBlock
Write-Host "`nTrying to create ScriptBlock..." -ForegroundColor Cyan
try {
    $null = [ScriptBlock]::Create($scriptContent)
    Write-Host "ScriptBlock creation: Success ✅" -ForegroundColor Green
}
catch {
    Write-Host "ScriptBlock creation: Failed ❌" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}

# Method 3: Test if script can be dot-sourced (requires valid parameters)
Write-Host "`nTrying to analyze with AST parser..." -ForegroundColor Cyan
try {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        Write-Host "AST Parser found errors:" -ForegroundColor Red
        $parseErrors | ForEach-Object {
            Write-Host "  $($_.Message)" -ForegroundColor Red
        }
    }
    else {
        Write-Host "AST Parser: No errors ✅" -ForegroundColor Green
    }
}
catch {
    Write-Host "AST Parser: Failed ❌" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}
