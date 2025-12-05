# Test-SyntaxCheck.ps1
# Verifies syntax of all modified files

$files = @(
    "$PSScriptRoot\..\BuildFFUVM.ps1",
    "$PSScriptRoot\..\Modules\FFU.Core\FFU.Core.psm1",
    "$PSScriptRoot\..\Modules\FFU.Core\FFU.Core.psd1",
    "$PSScriptRoot\..\Modules\FFU.VM\FFU.VM.psm1",
    "$PSScriptRoot\..\Modules\FFU.VM\FFU.VM.psd1",
    "$PSScriptRoot\..\Modules\FFU.Imaging\FFU.Imaging.psm1",
    "$PSScriptRoot\..\Modules\FFU.Updates\FFU.Updates.psm1"
)

$allPassed = $true

foreach ($file in $files) {
    $resolvedPath = Resolve-Path $file -ErrorAction SilentlyContinue
    if (-not $resolvedPath) {
        Write-Host "SKIP: File not found - $file" -ForegroundColor Yellow
        continue
    }

    $errors = $null
    $tokens = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($resolvedPath.Path, [ref]$tokens, [ref]$errors)

    $fileName = Split-Path $resolvedPath.Path -Leaf
    if ($errors.Count -eq 0) {
        Write-Host "PASS: $fileName - Syntax OK" -ForegroundColor Green
    } else {
        Write-Host "FAIL: $fileName - Syntax errors:" -ForegroundColor Red
        $allPassed = $false
        foreach ($err in $errors) {
            Write-Host "  Line $($err.Extent.StartLineNumber): $($err.Message)" -ForegroundColor Red
        }
    }
}

if ($allPassed) {
    Write-Host "`nAll syntax checks passed!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`nSome syntax checks failed!" -ForegroundColor Red
    exit 1
}
