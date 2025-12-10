#Requires -Version 5.1
<#
.SYNOPSIS
    Tests the FFU.Common.Logging module functionality.
.DESCRIPTION
    Validates module import, function exports, and logging behavior.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$testsPassed = 0
$testsFailed = 0

function Write-TestResult {
    param([string]$TestName, [bool]$Passed, [string]$Message = '')
    if ($Passed) {
        Write-Host "[PASS] $TestName" -ForegroundColor Green
        $script:testsPassed++
    } else {
        Write-Host "[FAIL] $TestName - $Message" -ForegroundColor Red
        $script:testsFailed++
    }
}

Write-Host "=== FFU.Common.Logging Module Tests ===" -ForegroundColor Cyan
Write-Host ""

# Test 1: Module Import
try {
    Import-Module "$PSScriptRoot\..\FFU.Common\FFU.Common.Logging.psd1" -Force -ErrorAction Stop
    Write-TestResult "Module Import" $true
} catch {
    Write-TestResult "Module Import" $false $_.Exception.Message
    exit 1
}

# Test 2: Verify all functions exported
$expectedFunctions = @(
    'Initialize-FFULogging',
    'Write-FFULog',
    'Write-FFUDebug',
    'Write-FFUInfo',
    'Write-FFUSuccess',
    'Write-FFUWarning',
    'Write-FFUError',
    'Write-FFUCritical',
    'Get-FFULogSession',
    'Close-FFULogging'
)

$exportedFunctions = Get-Command -Module FFU.Common.Logging | Select-Object -ExpandProperty Name
$allExported = $true
foreach ($func in $expectedFunctions) {
    if ($func -notin $exportedFunctions) {
        $allExported = $false
        Write-Host "  Missing: $func" -ForegroundColor Yellow
    }
}
Write-TestResult "All Functions Exported ($($expectedFunctions.Count))" $allExported

# Test 3: Initialize logging
$testLogPath = "$env:TEMP\FFULogging_Test_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
try {
    Initialize-FFULogging -LogPath $testLogPath -MinLevel Debug -EnableJsonLog
    Write-TestResult "Initialize-FFULogging" $true
} catch {
    Write-TestResult "Initialize-FFULogging" $false $_.Exception.Message
}

# Test 4: Get session info
try {
    $session = Get-FFULogSession
    $hasSessionId = -not [string]::IsNullOrEmpty($session.SessionId)
    $hasLogPath = $session.LogPath -eq $testLogPath
    Write-TestResult "Get-FFULogSession (SessionId present)" $hasSessionId
    Write-TestResult "Get-FFULogSession (LogPath correct)" $hasLogPath
} catch {
    Write-TestResult "Get-FFULogSession" $false $_.Exception.Message
}

# Test 5: Write-FFULog with all levels
$logLevels = @('Debug', 'Info', 'Success', 'Warning', 'Error', 'Critical')
foreach ($level in $logLevels) {
    try {
        Write-FFULog -Level $level -Message "Test $level message" -Context @{ TestLevel = $level }
        Write-TestResult "Write-FFULog -Level $level" $true
    } catch {
        Write-TestResult "Write-FFULog -Level $level" $false $_.Exception.Message
    }
}

# Test 6: Convenience functions
$convenienceFunctions = @{
    'Write-FFUDebug' = 'Debug test'
    'Write-FFUInfo' = 'Info test'
    'Write-FFUSuccess' = 'Success test'
    'Write-FFUWarning' = 'Warning test'
    'Write-FFUError' = 'Error test'
    'Write-FFUCritical' = 'Critical test'
}

foreach ($func in $convenienceFunctions.Keys) {
    try {
        & $func -Message $convenienceFunctions[$func] -Context @{ Function = $func }
        Write-TestResult "$func" $true
    } catch {
        Write-TestResult "$func" $false $_.Exception.Message
    }
}

# Test 7: Close logging
try {
    Close-FFULogging
    $session = Get-FFULogSession
    $sessionClosed = $null -eq $session.SessionId
    Write-TestResult "Close-FFULogging" $sessionClosed
} catch {
    Write-TestResult "Close-FFULogging" $false $_.Exception.Message
}

# Test 8: Verify log file created
$logFileExists = Test-Path $testLogPath
Write-TestResult "Log file created" $logFileExists

# Test 9: Verify JSON log file created
$jsonLogPath = [System.IO.Path]::ChangeExtension($testLogPath, '.json.log')
$jsonLogExists = Test-Path $jsonLogPath
Write-TestResult "JSON log file created" $jsonLogExists

# Test 10: Verify log content
if ($logFileExists) {
    $logContent = Get-Content $testLogPath -Raw
    $hasInitMessage = $logContent -match 'Logging session initialized'
    $hasCloseMessage = $logContent -match 'Logging session closed'
    Write-TestResult "Log contains init message" $hasInitMessage
    Write-TestResult "Log contains close message" $hasCloseMessage
}

# Test 11: Verify JSON content is valid
if ($jsonLogExists) {
    try {
        $jsonLines = Get-Content $jsonLogPath
        $validJson = $true
        foreach ($line in $jsonLines) {
            $null = $line | ConvertFrom-Json -ErrorAction Stop
        }
        Write-TestResult "JSON log entries are valid JSON" $validJson
    } catch {
        Write-TestResult "JSON log entries are valid JSON" $false $_.Exception.Message
    }
}

# Test 12: Empty message handling
try {
    Import-Module "$PSScriptRoot\..\FFU.Common\FFU.Common.Logging.psd1" -Force
    Initialize-FFULogging -LogPath "$env:TEMP\empty_test.log" -MinLevel Debug
    Write-FFULog -Level Info -Message ""  # Should not throw
    Write-FFULog -Level Info -Message "   "  # Should not throw (whitespace only)
    Close-FFULogging
    Remove-Item "$env:TEMP\empty_test.log" -Force -ErrorAction SilentlyContinue
    Write-TestResult "Empty message handling (no throw)" $true
} catch {
    Write-TestResult "Empty message handling (no throw)" $false $_.Exception.Message
}

# Test 13: MinLevel filtering
try {
    Import-Module "$PSScriptRoot\..\FFU.Common\FFU.Common.Logging.psd1" -Force
    $filterLogPath = "$env:TEMP\filter_test.log"
    Initialize-FFULogging -LogPath $filterLogPath -MinLevel Warning
    Write-FFUDebug -Message "Debug should not appear"
    Write-FFUInfo -Message "Info should not appear"
    Write-FFUWarning -Message "Warning should appear"
    Write-FFUError -Message "Error should appear"
    Close-FFULogging

    $filterContent = Get-Content $filterLogPath -Raw
    $debugFiltered = $filterContent -notmatch 'Debug should not appear'
    $infoFiltered = $filterContent -notmatch 'Info should not appear'
    $warningPresent = $filterContent -match 'Warning should appear'
    $errorPresent = $filterContent -match 'Error should appear'

    $filterWorking = $debugFiltered -and $infoFiltered -and $warningPresent -and $errorPresent
    Write-TestResult "MinLevel filtering works correctly" $filterWorking

    Remove-Item $filterLogPath -Force -ErrorAction SilentlyContinue
} catch {
    Write-TestResult "MinLevel filtering works correctly" $false $_.Exception.Message
}

# Cleanup
Remove-Item $testLogPath -Force -ErrorAction SilentlyContinue
Remove-Item $jsonLogPath -Force -ErrorAction SilentlyContinue

# Summary
Write-Host ""
Write-Host "=== Test Summary ===" -ForegroundColor Cyan
Write-Host "Passed: $testsPassed" -ForegroundColor Green
Write-Host "Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -gt 0) { 'Red' } else { 'Green' })
Write-Host ""

if ($testsFailed -eq 0) {
    Write-Host "All tests passed!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "Some tests failed." -ForegroundColor Red
    exit 1
}
