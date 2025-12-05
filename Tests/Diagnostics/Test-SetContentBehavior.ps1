#Requires -RunAsAdministrator

# Test if Set-Content creates parent directories

$testPath = "C:\Temp\TestFFUSetContent\config\test.json"

Write-Host "Testing Set-Content behavior with non-existent parent directory..." -ForegroundColor Cyan

# Clean up if exists
if (Test-Path "C:\Temp\TestFFUSetContent") {
    Remove-Item "C:\Temp\TestFFUSetContent" -Recurse -Force
}

# Try Set-Content without creating parent directory
try {
    '{}' | Set-Content -Path $testPath -ErrorAction Stop
    Write-Host "SUCCESS: Set-Content created parent directories automatically" -ForegroundColor Green
    Write-Host "File exists: $(Test-Path $testPath)"

    # Clean up
    Remove-Item "C:\Temp\TestFFUSetContent" -Recurse -Force
}
catch {
    Write-Host "FAILED: Set-Content requires parent directory to exist" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)"
}

Write-Host "`nThis means BuildFFUVM_UI.ps1 needs to create the config subdirectory before calling Set-Content."
