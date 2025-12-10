#Requires -Version 5.1

<#
.SYNOPSIS
    Test script to demonstrate the expand.exe argument quoting issue
#>

Write-Host "=== Testing expand.exe Argument Construction ===" -ForegroundColor Cyan
Write-Host ""

# Simulate actual paths
$PackagePath = 'C:\FFUDevelopment\KB\windows11.0-kb5043080-x64.msu'
$extractPath = 'C:\FFUDevelopment\KB\Temp\MSU_Extract'

Write-Host "Input paths:"
Write-Host "  PackagePath: $PackagePath"
Write-Host "  extractPath: $extractPath"
Write-Host ""

# Current (PROBLEMATIC) approach - quotes embedded in array
Write-Host "=== PROBLEMATIC APPROACH ===" -ForegroundColor Red
$expandArgsBAD = @(
    '-F:*',
    "`"$PackagePath`"",    # Has embedded quotes
    "`"$extractPath`""     # Has embedded quotes
)

Write-Host "Array elements (with embedded quotes):"
for ($i = 0; $i -lt $expandArgsBAD.Count; $i++) {
    Write-Host "  [$i]: '$($expandArgsBAD[$i])'"
}

Write-Host ""
Write-Host "What the log shows: expand.exe $($expandArgsBAD -join ' ')"
Write-Host "But PowerShell adds its own quotes when paths have spaces!"
Write-Host ""

# When we do: & expand.exe $expandArgsBAD
# PowerShell sees that element 1 contains quotes as part of the string
# and may double-quote it, resulting in: ""path""

# FIXED approach - no embedded quotes
Write-Host "=== FIXED APPROACH ===" -ForegroundColor Green
$expandArgsGOOD = @(
    '-F:*',
    $PackagePath,    # No embedded quotes - PowerShell will quote if needed
    $extractPath     # No embedded quotes
)

Write-Host "Array elements (without embedded quotes):"
for ($i = 0; $i -lt $expandArgsGOOD.Count; $i++) {
    Write-Host "  [$i]: '$($expandArgsGOOD[$i])'"
}

Write-Host ""
Write-Host "PowerShell will automatically quote paths with spaces when calling external commands"
Write-Host ""

# Test with actual expand.exe (dry run)
Write-Host "=== Actual expand.exe Test ===" -ForegroundColor Yellow
$testMsuPath = "C:\Windows\Temp\test file.txt"
$testExtractPath = "C:\Windows\Temp\test extract"

# Create test file with space in name
if (-not (Test-Path $testMsuPath)) {
    New-Item -Path $testMsuPath -ItemType File -Force | Out-Null
}

Write-Host "Testing with path containing spaces: '$testMsuPath'"
Write-Host ""

Write-Host "BAD: Using embedded quotes"
$badArgs = @('-F:*', "`"$testMsuPath`"", "`"$testExtractPath`"")
Write-Host "  Arguments: $($badArgs -join ' ')"
try {
    # This would fail because of double quoting
    $output = & expand.exe $badArgs 2>&1
    Write-Host "  Exit code: $LASTEXITCODE"
    Write-Host "  Output: $($output | Out-String)"
} catch {
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "GOOD: Without embedded quotes"
$goodArgs = @('-F:*', $testMsuPath, $testExtractPath)
Write-Host "  Arguments (what PowerShell sees): $($goodArgs -join ' ')"
# Note: We're not actually running this as the file isn't a real MSU

# Cleanup
Remove-Item $testMsuPath -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "=== Conclusion ===" -ForegroundColor Cyan
Write-Host "The bug is caused by embedding quotes in the argument array."
Write-Host "PowerShell's '& cmd args' syntax automatically handles quoting for external commands."
Write-Host "The fix is to remove the embedded quotes from the array elements."
