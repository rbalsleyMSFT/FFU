<#
.SYNOPSIS
    Simple syntax check for BuildFFUVM.ps1
#>

$scriptPath = "$PSScriptRoot\BuildFFUVM.ps1"
$tokens = $null
$errors = $null

Write-Host "Checking syntax of: $scriptPath"

try {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)

    if ($errors.Count -gt 0) {
        Write-Host "Syntax Errors Found:" -ForegroundColor Red
        foreach ($e in $errors) {
            Write-Host "  Line $($e.Extent.StartLineNumber): $($e.Message)" -ForegroundColor Red
        }
        exit 1
    } else {
        Write-Host "Syntax OK - No errors found" -ForegroundColor Green
        exit 0
    }
} catch {
    Write-Host "Parse failed: $_" -ForegroundColor Red
    exit 1
}
