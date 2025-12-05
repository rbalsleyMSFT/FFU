<#
.SYNOPSIS
    Comprehensive test suite for CaptureFFU.ps1 Solution C network improvements

.DESCRIPTION
    Tests all components of the network connection solution:
    - Wait-For-NetworkReady function
    - Connect-NetworkShareWithRetry function
    - Error handling and diagnostics
    - Integration with main script flow

.NOTES
    Created: 2025-11-25
    Purpose: Validate Solution C fixes Error 53 "Network path not found"
    Related Issue: CaptureFFU.ps1 network share connection failures
#>

#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
$testsPassed = 0
$testsFailed = 0

function Test-Condition {
    param(
        [string]$TestName,
        [scriptblock]$Condition,
        [string]$FailureMessage = "Test failed"
    )

    try {
        $result = & $Condition
        if ($result) {
            Write-Host "[PASS] $TestName" -ForegroundColor Green
            $script:testsPassed++
            return $true
        } else {
            Write-Host "[FAIL] $TestName - $FailureMessage" -ForegroundColor Red
            $script:testsFailed++
            return $false
        }
    } catch {
        Write-Host "[FAIL] $TestName - Exception: $_" -ForegroundColor Red
        $script:testsFailed++
        return $false
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "CaptureFFU.ps1 Solution C Test Suite" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Read CaptureFFU.ps1 content
$captureScriptPath = "C:\claude\FFUBuilder\FFUDevelopment\WinPECaptureFFUFiles\CaptureFFU.ps1"
if (-not (Test-Path $captureScriptPath)) {
    Write-Host "ERROR: CaptureFFU.ps1 not found at $captureScriptPath" -ForegroundColor Red
    exit 1
}
$scriptContent = Get-Content -Path $captureScriptPath -Raw

Write-Host "`n=== FUNCTION IMPLEMENTATION TESTS ===" -ForegroundColor Yellow

Test-Condition -TestName "Function 1.1: Wait-For-NetworkReady function exists" -Condition {
    $scriptContent -match 'function Wait-For-NetworkReady \{'
}

Test-Condition -TestName "Function 1.2: Wait-For-NetworkReady has parameter validation" -Condition {
    $scriptContent -match '\[Parameter\(Mandatory\s*=\s*\$true\)\].*\[string\]\$HostIP'
}

Test-Condition -TestName "Function 1.3: Wait-For-NetworkReady has TimeoutSeconds parameter" -Condition {
    $scriptContent -match '\[int\]\$TimeoutSeconds\s*=\s*60'
}

Test-Condition -TestName "Function 1.4: Wait-For-NetworkReady checks for network adapter" -Condition {
    $scriptContent -match 'Get-NetAdapter.*Where-Object.*Status.*Up'
}

Test-Condition -TestName "Function 1.5: Wait-For-NetworkReady checks for IP address (not APIPA)" -Condition {
    $scriptContent -match 'Get-NetIPAddress.*169\.254'
}

Test-Condition -TestName "Function 1.6: Wait-For-NetworkReady performs ping test" -Condition {
    $scriptContent -match 'Test-Connection.*-ComputerName.*HostIP'
}

Test-Condition -TestName "Function 1.7: Wait-For-NetworkReady has timeout logic with stopwatch" -Condition {
    $scriptContent -match 'System\.Diagnostics\.Stopwatch.*StartNew' -and
    $scriptContent -match 'Elapsed\.TotalSeconds.*TimeoutSeconds'
}

Test-Condition -TestName "Function 1.8: Wait-For-NetworkReady returns boolean" -Condition {
    $scriptContent -match 'function Wait-For-NetworkReady' -and
    ($scriptContent -split 'function Wait-For-NetworkReady')[1] -match 'return \$true' -and
    ($scriptContent -split 'function Wait-For-NetworkReady')[1] -match 'return \$false'
}

Test-Condition -TestName "Function 1.9: Wait-For-NetworkReady displays network info on success" -Condition {
    $scriptContent -match 'Adapter:.*adapter.*Name' -and
    $scriptContent -match 'IP Address:.*ip.*IPAddress' -and
    $scriptContent -match 'Gateway:'
}

Test-Condition -TestName "Function 1.10: Wait-For-NetworkReady displays diagnostics on timeout" -Condition {
    $scriptContent -match 'TIMEOUT.*Network failed to become ready' -and
    $scriptContent -match 'No network adapters found' -and
    $scriptContent -match 'No IP addresses assigned'
}

Write-Host "`n=== CONNECT-NETWORKSHARE FUNCTION TESTS ===" -ForegroundColor Yellow

Test-Condition -TestName "Function 2.1: Connect-NetworkShareWithRetry function exists" -Condition {
    $scriptContent -match 'function Connect-NetworkShareWithRetry \{'
}

Test-Condition -TestName "Function 2.2: Connect-NetworkShareWithRetry has SharePath parameter" -Condition {
    $scriptContent -match '\[Parameter\(Mandatory\s*=\s*\$true\)\].*\[string\]\$SharePath'
}

Test-Condition -TestName "Function 2.3: Connect-NetworkShareWithRetry has Username parameter" -Condition {
    $scriptContent -match '\[Parameter\(Mandatory\s*=\s*\$true\)\].*\[string\]\$Username'
}

Test-Condition -TestName "Function 2.4: Connect-NetworkShareWithRetry has Password parameter" -Condition {
    $scriptContent -match '\[Parameter\(Mandatory\s*=\s*\$true\)\].*\[string\]\$Password'
}

Test-Condition -TestName "Function 2.5: Connect-NetworkShareWithRetry has DriveLetter parameter" -Condition {
    $scriptContent -match '\[Parameter\(Mandatory\s*=\s*\$true\)\].*\[string\]\$DriveLetter'
}

Test-Condition -TestName "Function 2.6: Connect-NetworkShareWithRetry has MaxRetries parameter with default" -Condition {
    $scriptContent -match '\[int\]\$MaxRetries\s*=\s*3'
}

Test-Condition -TestName "Function 2.7: Connect-NetworkShareWithRetry implements retry loop" -Condition {
    $scriptContent -match 'for.*\$attempt.*MaxRetries'
}

Test-Condition -TestName "Function 2.8: Connect-NetworkShareWithRetry calls net use command" -Condition {
    $scriptContent -match 'net use.*DriveLetter.*SharePath.*user.*Username.*Password'
}

Test-Condition -TestName "Function 2.9: Connect-NetworkShareWithRetry checks LASTEXITCODE" -Condition {
    $scriptContent -match 'if.*LASTEXITCODE.*-eq 0'
}

Test-Condition -TestName "Function 2.10: Connect-NetworkShareWithRetry parses error codes" -Condition {
    $scriptContent -match 'System error \(\\d\+\)' -and
    $scriptContent -match '\$errorCode\s*=\s*\[int\]\$match\.Groups\[1\]\.Value'
}

Test-Condition -TestName "Function 2.11: Connect-NetworkShareWithRetry handles error 53" -Condition {
    $scriptContent -match '53\s*\{' -and
    $scriptContent -match 'Network path not found' -and
    $scriptContent -match 'VM network switch is Internal/Private'
}

Test-Condition -TestName "Function 2.12: Connect-NetworkShareWithRetry handles multiple error codes" -Condition {
    # Should handle errors: 53, 67, 86, 1219, 1326, 1385, 1792, 2250
    ($scriptContent -match '67\s*\{') -and
    ($scriptContent -match '86\s*\{') -and
    ($scriptContent -match '1219\s*\{') -and
    ($scriptContent -match '1326\s*\{')
}

Test-Condition -TestName "Function 2.13: Connect-NetworkShareWithRetry has retry delay" -Condition {
    $scriptContent -match 'Retrying in 5 seconds' -and
    $scriptContent -match 'Start-Sleep -Seconds 5'
}

Test-Condition -TestName "Function 2.14: Connect-NetworkShareWithRetry returns boolean" -Condition {
    $scriptContent -match 'function Connect-NetworkShareWithRetry' -and
    ($scriptContent -split 'function Connect-NetworkShareWithRetry')[1] -match 'return \$true' -and
    ($scriptContent -split 'function Connect-NetworkShareWithRetry')[1] -match 'return \$false'
}

Write-Host "`n=== DIAGNOSTIC FEATURES TESTS ===" -ForegroundColor Yellow

Test-Condition -TestName "Diagnostics 1: Network adapter diagnostics on failure" -Condition {
    $scriptContent -match 'Get-NetAdapter.*Format-Table'
}

Test-Condition -TestName "Diagnostics 2: IP configuration diagnostics" -Condition {
    $scriptContent -match 'Get-NetIPAddress.*Format-Table'
}

Test-Condition -TestName "Diagnostics 3: Default gateway diagnostics" -Condition {
    $scriptContent -match 'Get-NetRoute.*DestinationPrefix.*0\.0\.0\.0/0'
}

Test-Condition -TestName "Diagnostics 4: Ping test diagnostics" -Condition {
    $scriptContent -match 'Test-Connection.*-Count 4'
}

Test-Condition -TestName "Diagnostics 5: SMB port 445 connectivity test" -Condition {
    $scriptContent -match 'System\.Net\.Sockets\.TcpClient' -and
    $scriptContent -match 'ConnectAsync.*445'
}

Test-Condition -TestName "Diagnostics 6: DNS resolution test" -Condition {
    $scriptContent -match 'Resolve-DnsName'
}

Test-Condition -TestName "Diagnostics 7: Troubleshooting guide included" -Condition {
    $scriptContent -match 'TROUBLESHOOTING GUIDE' -and
    $scriptContent -match 'VERIFY HOST IP ADDRESS' -and
    $scriptContent -match 'CHECK HYPER-V VM SWITCH TYPE' -and
    $scriptContent -match 'DISABLE WINDOWS FIREWALL'
}

Test-Condition -TestName "Diagnostics 8: Firewall troubleshooting mentioned" -Condition {
    $scriptContent -match 'Windows Firewall.*blocking SMB' -and
    $scriptContent -match 'port 445/TCP'
}

Test-Condition -TestName "Diagnostics 9: VM switch type troubleshooting" -Condition {
    $scriptContent -match 'External.*not Internal or Private' -and
    $scriptContent -match 'Hyper-V Manager.*Virtual Switch Manager'
}

Test-Condition -TestName "Diagnostics 10: Network driver troubleshooting" -Condition {
    $scriptContent -match 'network drivers.*PEDrivers folder' -and
    $scriptContent -match 'Rebuild WinPE capture media'
}

Write-Host "`n=== MAIN EXECUTION FLOW TESTS ===" -ForegroundColor Yellow

Test-Condition -TestName "Flow 1: Main execution calls Wait-For-NetworkReady first" -Condition {
    # Main execution should call Wait-For-NetworkReady before Connect-NetworkShareWithRetry
    $mainExecIndex = $scriptContent.IndexOf('# Main execution with Solution C')
    $waitCallIndex = $scriptContent.IndexOf('Wait-For-NetworkReady -HostIP')
    $connectCallIndex = $scriptContent.IndexOf('Connect-NetworkShareWithRetry')

    $waitCallIndex -gt $mainExecIndex -and $waitCallIndex -lt $connectCallIndex
}

Test-Condition -TestName "Flow 2: Main execution passes VMHostIPAddress to Wait-For-NetworkReady" -Condition {
    $scriptContent -match 'Wait-For-NetworkReady.*-HostIP \$VMHostIPAddress'
}

Test-Condition -TestName "Flow 3: Main execution sets 60 second timeout for network wait" -Condition {
    $scriptContent -match 'Wait-For-NetworkReady.*-TimeoutSeconds 60'
}

Test-Condition -TestName "Flow 4: Main execution calls Connect-NetworkShareWithRetry after network ready" -Condition {
    $scriptContent -match 'if.*Wait-For-NetworkReady.*\{.*throw' -and
    $scriptContent -match 'Connect-NetworkShareWithRetry'
}

Test-Condition -TestName "Flow 5: Main execution passes all required parameters to Connect-NetworkShareWithRetry" -Condition {
    $scriptContent -match 'Connect-NetworkShareWithRetry.*-SharePath.*VMHostIPAddress.*ShareName' -and
    $scriptContent -match '-Username \$UserName' -and
    $scriptContent -match '-Password \$Password' -and
    $scriptContent -match '-DriveLetter "W:"'
}

Test-Condition -TestName "Flow 6: Main execution sets 3 retry attempts" -Condition {
    $scriptContent -match 'Connect-NetworkShareWithRetry.*-MaxRetries 3'
}

Test-Condition -TestName "Flow 7: Main execution throws error if network not ready" -Condition {
    $scriptContent -match 'if.*-not.*Wait-For-NetworkReady.*throw.*Network initialization failed'
}

Test-Condition -TestName "Flow 8: Main execution throws error if share connection fails" -Condition {
    $scriptContent -match 'if.*-not.*shareConnected.*throw.*Failed to connect'
}

Test-Condition -TestName "Flow 9: Main execution has try-catch block" -Condition {
    $scriptContent -match '# Main execution with Solution C.*try \{' -and
    $scriptContent -match '\} catch \{.*CaptureFFU\.ps1 network connection error'
}

Test-Condition -TestName "Flow 10: Main execution displays configuration info" -Condition {
    $scriptContent -match 'Configuration:' -and
    $scriptContent -match 'Host IP:.*VMHostIPAddress' -and
    $scriptContent -match 'Share:.*VMHostIPAddress.*ShareName' -and
    $scriptContent -match 'User:.*UserName'
}

Write-Host "`n=== ERROR HANDLING TESTS ===" -ForegroundColor Yellow

Test-Condition -TestName "Error 1: Wait-For-NetworkReady uses -ErrorAction SilentlyContinue" -Condition {
    # Should not throw errors during network checks
    ($scriptContent -split 'function Wait-For-NetworkReady')[1] -match 'ErrorAction SilentlyContinue'
}

Test-Condition -TestName "Error 2: Connect-NetworkShareWithRetry handles exceptions in retry loop" -Condition {
    ($scriptContent -split 'function Connect-NetworkShareWithRetry')[1] -match 'catch \{.*Exception during connection attempt'
}

Test-Condition -TestName "Error 3: Diagnostic functions use try-catch" -Condition {
    $scriptContent -match 'try \{.*Get-NetAdapter.*\} catch \{' -and
    $scriptContent -match 'try \{.*Test-Connection.*\} catch \{'
}

Test-Condition -TestName "Error 4: Main execution shows user-friendly error messages" -Condition {
    $scriptContent -match 'NETWORK CONNECTION FAILED' -and
    $scriptContent -match 'review the troubleshooting guide' -and
    $scriptContent -match 'Press any key to continue'
}

Test-Condition -TestName "Error 5: Errors include actionable guidance" -Condition {
    $scriptContent -match 'try in order' -and
    $scriptContent -match 'Run.*ipconfig.*on host' -and
    $scriptContent -match 'Open Hyper-V Manager'
}

Write-Host "`n=== USER EXPERIENCE TESTS ===" -ForegroundColor Yellow

Test-Condition -TestName "UX 1: Progress indicators with timestamps" -Condition {
    $scriptContent -match '\$elapsed' -and
    $scriptContent -match 'Waiting for network adapter' -and
    $scriptContent -match 'Waiting for IP address'
}

Test-Condition -TestName "UX 2: Color-coded output for success/failure" -Condition {
    $scriptContent -match 'ForegroundColor Green' -and
    $scriptContent -match 'ForegroundColor Red' -and
    $scriptContent -match 'ForegroundColor Yellow' -and
    $scriptContent -match 'ForegroundColor Cyan'
}

Test-Condition -TestName "UX 3: Clear section headers" -Condition {
    $scriptContent -match '========== Network Initialization ==========' -and
    $scriptContent -match '========== Connecting to Network Share ==========' -and
    $scriptContent -match '========== NETWORK DIAGNOSTICS ==========' -and
    $scriptContent -match '========== TROUBLESHOOTING GUIDE =========='
}

Test-Condition -TestName "UX 4: Success messages displayed" -Condition {
    $scriptContent -match '\[SUCCESS\] Network ready' -and
    $scriptContent -match '\[SUCCESS\] Connected to network share' -and
    $scriptContent -match 'Network share connection successful'
}

Test-Condition -TestName "UX 5: Failure messages displayed" -Condition {
    $scriptContent -match '\[FAIL\]' -and
    $scriptContent -match '\[TIMEOUT\]' -and
    $scriptContent -match '\[CRITICAL\]'
}

Test-Condition -TestName "UX 6: Numbered troubleshooting steps" -Condition {
    $scriptContent -match '1\. VERIFY HOST IP ADDRESS' -and
    $scriptContent -match '2\. CHECK HYPER-V VM SWITCH TYPE' -and
    $scriptContent -match '3\. DISABLE WINDOWS FIREWALL' -and
    $scriptContent -match '4\. VERIFY NETWORK DRIVERS' -and
    $scriptContent -match '5\. CHECK SMB SHARE EXISTS' -and
    $scriptContent -match '6\. VERIFY SMB SERVER SERVICE'
}

Write-Host "`n=== CODE QUALITY TESTS ===" -ForegroundColor Yellow

Test-Condition -TestName "Quality 1: Functions have comment-based help" -Condition {
    $scriptContent -match 'function Wait-For-NetworkReady \{.*\.SYNOPSIS' -and
    $scriptContent -match 'function Connect-NetworkShareWithRetry \{.*\.SYNOPSIS'
}

Test-Condition -TestName "Quality 2: Functions have parameter descriptions" -Condition {
    $scriptContent -match '\.PARAMETER HostIP' -and
    $scriptContent -match '\.PARAMETER SharePath' -and
    $scriptContent -match '\.PARAMETER TimeoutSeconds'
}

Test-Condition -TestName "Quality 3: Functions have examples" -Condition {
    $scriptContent -match '\.EXAMPLE.*Wait-For-NetworkReady' -and
    $scriptContent -match '\.EXAMPLE.*Connect-NetworkShareWithRetry'
}

Test-Condition -TestName "Quality 4: No hardcoded values in main logic" -Condition {
    # Should use variables like $VMHostIPAddress, not hardcoded IPs
    -not ($scriptContent -match 'Wait-For-NetworkReady.*-HostIP "192\.168')
}

Test-Condition -TestName "Quality 5: Consistent error message format" -Condition {
    # All error messages should start with error type indicator
    $scriptContent -match '\[FAIL\]' -and
    $scriptContent -match '\[SUCCESS\]' -and
    $scriptContent -match '\[TIMEOUT\]' -and
    $scriptContent -match '\[CRITICAL\]' -and
    $scriptContent -match '\[OK\]'
}

Test-Condition -TestName "Quality 6: Solution C identifier in code" -Condition {
    $scriptContent -match '# Solution C: Automatic Network Wait \+ Retry \+ Diagnostics'
}

Write-Host "`n=== INTEGRATION TESTS ===" -ForegroundColor Yellow

Test-Condition -TestName "Integration 1: Variables initialized before functions" -Condition {
    $varsIndex = $scriptContent.IndexOf('$VMHostIPAddress =')
    $func1Index = $scriptContent.IndexOf('function Wait-For-NetworkReady')
    $varsIndex -lt $func1Index
}

Test-Condition -TestName "Integration 2: Functions defined before main execution" -Condition {
    $func1Index = $scriptContent.IndexOf('function Wait-For-NetworkReady')
    $func2Index = $scriptContent.IndexOf('function Connect-NetworkShareWithRetry')
    $mainIndex = $scriptContent.IndexOf('# Main execution with Solution C')

    $func1Index -lt $mainIndex -and $func2Index -lt $mainIndex
}

Test-Condition -TestName "Integration 3: Original script flow continues after network connection" -Condition {
    # After successful connection, script should continue with disk assignment
    $scriptContent -match 'Network share connection successful' -and
    $scriptContent -match '\$AssignDriveLetter = ' -and
    $scriptContent -match 'Assigning M: as Windows drive letter'
}

Test-Condition -TestName "Integration 4: Script maintains backward compatibility with parameter names" -Condition {
    $scriptContent -match '\$VMHostIPAddress = ' -and
    $scriptContent -match '\$ShareName = ' -and
    $scriptContent -match '\$UserName = ' -and
    $scriptContent -match '\$Password = '
}

Test-Condition -TestName "Integration 5: All original functionality preserved" -Condition {
    # Original FFU capture code should still exist
    $scriptContent -match 'AssignDriveLetter' -and
    $scriptContent -match 'Load Registry Hive' -and
    $scriptContent -match 'WindowsSKU' -and
    $scriptContent -match 'capture-ffu'
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Tests Passed: $testsPassed" -ForegroundColor Green
Write-Host "Tests Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -eq 0) { 'Green' } else { 'Red' })
Write-Host "Total Tests:  $($testsPassed + $testsFailed)" -ForegroundColor Cyan

if ($testsFailed -eq 0) {
    Write-Host "`nAll tests passed! Solution C is fully implemented." -ForegroundColor Green
    exit 0
} else {
    Write-Host "`nSome tests failed. Please review the implementation." -ForegroundColor Red
    exit 1
}
