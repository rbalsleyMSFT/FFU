<#
.SYNOPSIS
    Test script to reproduce the RemoveUpdates configuration bug

.DESCRIPTION
    This script simulates the config loading logic in BuildFFUVM.ps1 to verify
    whether boolean $false values in JSON configs are properly loaded or if they're
    being skipped by the empty value check.
#>

Write-Host "=== Testing RemoveUpdates Configuration Loading ===" -ForegroundColor Cyan
Write-Host ""

# Create a test config JSON with RemoveUpdates = false (simulating unchecked checkbox)
$testConfigPath = Join-Path $env:TEMP "test_ffu_config.json"
$testConfig = @{
    RemoveUpdates = $false
    UpdateLatestDefender = $true
    WindowsRelease = 11
}

Write-Host "Step 1: Creating test config JSON with RemoveUpdates = false" -ForegroundColor Yellow
$testConfig | ConvertTo-Json | Set-Content -Path $testConfigPath
Write-Host "Config saved to: $testConfigPath"
Write-Host "Config contents:" -ForegroundColor Gray
Get-Content $testConfigPath | Write-Host -ForegroundColor Gray
Write-Host ""

# Simulate BuildFFUVM.ps1's parameter default
Write-Host "Step 2: Setting parameter default (like BuildFFUVM.ps1 line 417)" -ForegroundColor Yellow
[bool]$RemoveUpdates = $true  # Default value in script
Write-Host "Initial value: RemoveUpdates = $RemoveUpdates" -ForegroundColor Gray
Write-Host ""

# Simulate the config loading logic from BuildFFUVM.ps1 lines 586-620
Write-Host "Step 3: Loading config file (simulating BuildFFUVM.ps1 lines 586-620)" -ForegroundColor Yellow
$configData = Get-Content $testConfigPath -Raw | ConvertFrom-Json
$keys = $configData.psobject.Properties.Name

Write-Host "Config keys found: $($keys -join ', ')" -ForegroundColor Gray
Write-Host ""

foreach ($key in $keys) {
    $value = $configdata.$key

    Write-Host "Processing key: '$key'" -ForegroundColor Gray
    Write-Host "  Value: $value (Type: $($value.GetType().Name))" -ForegroundColor Gray

    # This is the problematic check from lines 594-602
    $shouldSkip = (
        ($null -eq $value) -or
        ([string]::IsNullOrEmpty([string]$value)) -or
        ($value -is [System.Collections.Hashtable] -and $value.Count -eq 0) -or
        ($value -is [System.UInt32] -and $value -eq 0) -or
        ($value -is [System.UInt64] -and $value -eq 0) -or
        ($value -is [System.Int32] -and $value -eq 0)
    )

    Write-Host "  Should skip? $shouldSkip" -ForegroundColor Gray

    if ($shouldSkip) {
        Write-Host "  Action: SKIPPED (continue)" -ForegroundColor Red
        continue
    }

    # Simulate Set-Variable (line 617)
    Write-Host "  Action: Setting variable to $value" -ForegroundColor Green
    Set-Variable -Name $key -Value $value -Scope 0
    Write-Host ""
}

# Check final value
Write-Host "Step 4: Checking final value after config load" -ForegroundColor Yellow
Write-Host "RemoveUpdates = $RemoveUpdates" -ForegroundColor $(if ($RemoveUpdates) { "Red" } else { "Green" })
Write-Host ""

# Expected vs Actual
Write-Host "=== RESULTS ===" -ForegroundColor Cyan
Write-Host "Expected: RemoveUpdates = FALSE (from unchecked checkbox)" -ForegroundColor White
Write-Host "Actual:   RemoveUpdates = $RemoveUpdates" -ForegroundColor White
Write-Host ""

if ($RemoveUpdates -eq $false) {
    Write-Host "TEST PASSED: Config loading works correctly!" -ForegroundColor Green
    Write-Host "Boolean false is NOT being caught by the empty value check." -ForegroundColor Green
} else {
    Write-Host "TEST FAILED: Boolean false is being treated as empty!" -ForegroundColor Red
    Write-Host "This is the BUG causing re-downloads." -ForegroundColor Red
}
Write-Host ""

# Additional test: Check what happens with downloaded files
Write-Host "=== Testing Download Logic ===" -ForegroundColor Cyan
Write-Host ""

$testAppsPath = Join-Path $env:TEMP "TestFFUApps"
$testDefenderPath = Join-Path $testAppsPath "Defender"

# Create test files
Write-Host "Creating test Defender files..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path $testDefenderPath -Force | Out-Null
"test" | Out-File -FilePath "$testDefenderPath\test.exe" -Force
Write-Host "Created: $testDefenderPath\test.exe" -ForegroundColor Gray
Write-Host ""

# Simulate download check logic from BuildFFUVM.ps1 lines 1592-1599
Write-Host "Simulating Defender download check (lines 1592-1599)..." -ForegroundColor Yellow
$DefenderDownloaded = $false
if (Test-Path -Path $testDefenderPath) {
    $DefenderSize = (Get-ChildItem -Path $testDefenderPath -Recurse | Measure-Object -Property Length -Sum).Sum
    Write-Host "  Defender folder exists, size: $DefenderSize bytes" -ForegroundColor Gray
    if ($DefenderSize -gt 1MB) {
        Write-Host "  Size > 1MB: Would skip download" -ForegroundColor Green
        $DefenderDownloaded = $true
    } else {
        Write-Host "  Size <= 1MB: Would proceed with download" -ForegroundColor Red
    }
} else {
    Write-Host "  Defender folder does not exist: Would download" -ForegroundColor Red
}
Write-Host ""

# Cleanup
Remove-Item -Path $testConfigPath -Force
Remove-Item -Path $testAppsPath -Recurse -Force

Write-Host "=== Test Complete ===" -ForegroundColor Cyan
