#Requires -Version 5.1
<#
.SYNOPSIS
    Tests that error propagation works correctly through the trap handler.

.DESCRIPTION
    Validates that the global trap handler in BuildFFUVM.ps1 uses 'break' instead of
    'continue' to ensure errors are properly propagated to the calling process/job.

    This test was created after discovering that using 'continue' in the trap caused:
    - Script to continue after catch blocks that re-throw
    - Success marker to be output even after failures
    - UI to incorrectly report success

.NOTES
    Version: 1.0.0
    Created to prevent regression of UI error reporting issue
#>

param(
    [switch]$Verbose
)

$script:PassCount = 0
$script:FailCount = 0
$script:TestResults = @()

function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Message = ""
    )

    $script:TestResults += [PSCustomObject]@{
        TestName = $TestName
        Passed   = $Passed
        Message  = $Message
    }

    if ($Passed) {
        $script:PassCount++
        Write-Host "  [PASS] $TestName" -ForegroundColor Green
    } else {
        $script:FailCount++
        Write-Host "  [FAIL] $TestName" -ForegroundColor Red
        if ($Message) {
            Write-Host "         $Message" -ForegroundColor Yellow
        }
    }
}

$FFUDevelopmentPath = Split-Path $PSScriptRoot -Parent
$BuildScript = Join-Path $FFUDevelopmentPath "BuildFFUVM.ps1"

Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host "Trap Error Propagation Tests" -ForegroundColor Cyan
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host ""
Write-Host "Purpose: Ensure trap handler uses 'break' for proper error propagation" -ForegroundColor Gray
Write-Host ""

# =============================================================================
# Test 1: Verify trap statement uses 'break' not 'continue'
# =============================================================================
Write-Host "Testing BuildFFUVM.ps1 trap handler..." -ForegroundColor Yellow

try {
    $content = Get-Content -Path $BuildScript -Raw -ErrorAction Stop

    # Find the trap block - use a more robust pattern that handles nested braces and comments
    # Look for 'trap {' followed by content up to a line that ends with just '}'
    $trapPattern = '(?ms)trap\s*\{.+?^\}'
    $trapMatch = [regex]::Match($content, $trapPattern)

    Write-TestResult -TestName "Trap statement found in BuildFFUVM.ps1" -Passed $trapMatch.Success

    if ($trapMatch.Success) {
        $trapBlock = $trapMatch.Value

        # Check for 'break' as the control flow statement (should be on its own line, possibly with comments)
        $usesBreak = $trapBlock -match '(?m)^\s*break\s*$'
        # Check for 'continue' which would be wrong
        $usesContinue = $trapBlock -match '(?m)^\s*continue\s*$'

        Write-TestResult -TestName "Trap uses 'break' for error propagation" -Passed $usesBreak -Message $(if (-not $usesBreak) { "CRITICAL: Trap should use 'break' to propagate errors" })
        Write-TestResult -TestName "Trap does NOT use 'continue' (which swallows errors)" -Passed (-not $usesContinue) -Message $(if ($usesContinue) { "CRITICAL: Using 'continue' swallows errors and prevents UI from detecting failures" })

        # Verify the trap block includes cleanup registry check
        $hasCleanupCheck = $trapBlock -match 'Get-CleanupRegistry'
        Write-TestResult -TestName "Trap includes cleanup registry check" -Passed $hasCleanupCheck

        # Verify the trap invokes failure cleanup
        $hasFailureCleanup = $trapBlock -match 'Invoke-FailureCleanup'
        Write-TestResult -TestName "Trap invokes Invoke-FailureCleanup" -Passed $hasFailureCleanup
    }
}
catch {
    Write-TestResult -TestName "Reading BuildFFUVM.ps1" -Passed $false -Message $_.Exception.Message
}

# =============================================================================
# Test 2: Verify catch blocks re-throw errors
# =============================================================================
Write-Host ""
Write-Host "Testing catch block error re-throwing..." -ForegroundColor Yellow

try {
    $content = Get-Content -Path $BuildScript -Raw -ErrorAction Stop

    # Find the FFU capture catch block (the one that handles "Capturing FFU file failed")
    # Use a more robust pattern that handles multi-line blocks
    $ffuCatchPattern = '(?ms)Catch\s*\{.*?Capturing FFU file failed.*?throw\s+\$_.*?^\}'
    $ffuCatchMatch = [regex]::Match($content, $ffuCatchPattern)

    Write-TestResult -TestName "FFU capture catch block found" -Passed $ffuCatchMatch.Success

    if ($ffuCatchMatch.Success) {
        $catchBlock = $ffuCatchMatch.Value

        # Verify it re-throws the error
        $rethrowsError = $catchBlock -match 'throw\s+\$_'
        Write-TestResult -TestName "FFU capture catch block re-throws error" -Passed $rethrowsError -Message $(if (-not $rethrowsError) { "Catch block should re-throw with 'throw `$_'" })
    }

    # Check other critical catch blocks for re-throwing
    # Use line-by-line search to find catch blocks by their log message
    $lines = $content -split "`n"

    # VM creation catch
    $vmCatchFound = $false
    $vmCatchRethrows = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match 'VM creation failed') {
            $vmCatchFound = $true
            # Look ahead for throw $_
            for ($j = $i; $j -lt [Math]::Min($i + 10, $lines.Count); $j++) {
                if ($lines[$j] -match 'throw\s+\$_') {
                    $vmCatchRethrows = $true
                    break
                }
            }
            break
        }
    }
    Write-TestResult -TestName "VM creation catch re-throws error" -Passed $vmCatchRethrows -Message $(if ($vmCatchFound -and -not $vmCatchRethrows) { "Catch block should re-throw with 'throw `$_'" })

    # FFU User/Share cleanup catch
    $shareCleanupFound = $false
    $shareCleanupRethrows = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match 'FFU User and/or share failed') {
            $shareCleanupFound = $true
            for ($j = $i; $j -lt [Math]::Min($i + 10, $lines.Count); $j++) {
                if ($lines[$j] -match 'throw\s+\$_') {
                    $shareCleanupRethrows = $true
                    break
                }
            }
            break
        }
    }
    Write-TestResult -TestName "FFU User/Share cleanup catch re-throws error" -Passed $shareCleanupRethrows

    # VHDX creation catch
    $vhdxCatchFound = $false
    $vhdxCatchRethrows = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match 'Creating VHDX Failed') {
            $vhdxCatchFound = $true
            for ($j = $i; $j -lt [Math]::Min($i + 30, $lines.Count); $j++) {
                if ($lines[$j] -match 'throw\s+\$_') {
                    $vhdxCatchRethrows = $true
                    break
                }
            }
            break
        }
    }
    Write-TestResult -TestName "VHDX creation catch re-throws error" -Passed $vhdxCatchRethrows -Message $(if ($vhdxCatchFound -and -not $vhdxCatchRethrows) { "Catch block should re-throw with 'throw `$_'" })
}
catch {
    Write-TestResult -TestName "Analyzing catch blocks" -Passed $false -Message $_.Exception.Message
}

# =============================================================================
# Test 3: Verify success marker is only output at script completion
# =============================================================================
Write-Host ""
Write-Host "Testing success marker placement..." -ForegroundColor Yellow

try {
    $content = Get-Content -Path $BuildScript -Raw -ErrorAction Stop

    # Find the success marker
    $successPattern = 'FFUBuildSuccess\s*=\s*\$true'
    $successMatches = [regex]::Matches($content, $successPattern)

    Write-TestResult -TestName "Success marker found in script" -Passed ($successMatches.Count -gt 0)
    Write-TestResult -TestName "Only one success marker exists" -Passed ($successMatches.Count -eq 1) -Message $(if ($successMatches.Count -gt 1) { "Multiple success markers found - could cause false positives" })

    # Verify success marker is near the end of the script (in the END block)
    if ($successMatches.Count -eq 1) {
        $successIndex = $successMatches[0].Index
        $scriptLength = $content.Length
        $percentFromEnd = (($scriptLength - $successIndex) / $scriptLength) * 100

        # Success marker should be in the last 5% of the script
        $isNearEnd = $percentFromEnd -lt 5
        Write-TestResult -TestName "Success marker is at script completion (END block)" -Passed $isNearEnd -Message $(if (-not $isNearEnd) { "Success marker should only be output after all operations complete" })
    }
}
catch {
    Write-TestResult -TestName "Analyzing success marker" -Passed $false -Message $_.Exception.Message
}

# =============================================================================
# Test 4: Simulate trap behavior with break vs continue
# =============================================================================
Write-Host ""
Write-Host "Testing trap behavior simulation..." -ForegroundColor Yellow

try {
    # Test that 'break' in trap propagates errors
    $breakResult = $null
    $breakErrorCaught = $false

    try {
        $breakResult = & {
            trap {
                # Simulate cleanup
                break
            }
            throw "Test error"
            return "Should not reach here"
        }
    }
    catch {
        $breakErrorCaught = $true
    }

    Write-TestResult -TestName "Trap with 'break' propagates error" -Passed $breakErrorCaught
    Write-TestResult -TestName "Trap with 'break' prevents return value" -Passed ($null -eq $breakResult)

    # Test that 'continue' in trap swallows errors (BAD behavior)
    $continueResult = $null
    $continueErrorCaught = $false

    try {
        $continueResult = & {
            trap {
                # Simulate cleanup
                continue
            }
            throw "Test error"
            return "After error"
        }
    }
    catch {
        $continueErrorCaught = $true
    }

    # Note: With 'continue', error is NOT caught externally and script continues
    Write-TestResult -TestName "Trap with 'continue' swallows error (demonstrates BAD behavior)" -Passed (-not $continueErrorCaught) -Message "This test verifies WHY we need 'break'"
}
catch {
    Write-TestResult -TestName "Trap behavior simulation" -Passed $false -Message $_.Exception.Message
}

# =============================================================================
# Test Summary
# =============================================================================
Write-Host ""
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host "Total Tests: $($script:PassCount + $script:FailCount)" -ForegroundColor White
Write-Host "Passed: $script:PassCount" -ForegroundColor Green
Write-Host "Failed: $script:FailCount" -ForegroundColor $(if ($script:FailCount -gt 0) { "Red" } else { "Green" })
Write-Host ""

if ($script:FailCount -eq 0) {
    Write-Host "All tests passed! Error propagation is correctly configured." -ForegroundColor Green
    exit 0
} else {
    Write-Host "CRITICAL: Some tests failed. UI may not detect build failures!" -ForegroundColor Red
    Write-Host "Fix the trap handler to use 'break' instead of 'continue'." -ForegroundColor Red
    exit 1
}
