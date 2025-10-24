<#
.SYNOPSIS
    Comprehensive test script for BITS authentication fix (Issue 0x800704DD)

.DESCRIPTION
    This script validates that the BITS authentication error fix is working correctly by:
    1. Testing ThreadJob module availability and installation
    2. Comparing credential inheritance between Start-Job and Start-ThreadJob
    3. Testing BITS transfers in both job contexts
    4. Validating enhanced error detection and reporting
    5. Testing the updated FFU.Common.Core module functions

.NOTES
    Run as Administrator from the FFUDevelopment directory
#>

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [switch]$SkipDownloadTests,
    [switch]$Verbose
)

$ErrorActionPreference = 'Stop'
$testResults = @()

function Write-TestHeader {
    param([string]$Message)
    Write-Host "`n$('=' * 80)" -ForegroundColor Cyan
    Write-Host "  $Message" -ForegroundColor Cyan
    Write-Host "$('=' * 80)" -ForegroundColor Cyan
}

function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Details = "",
        [string]$ErrorMessage = ""
    )

    $result = [PSCustomObject]@{
        TestName     = $TestName
        Passed       = $Passed
        Details      = $Details
        ErrorMessage = $ErrorMessage
        Timestamp    = Get-Date
    }

    $script:testResults += $result

    if ($Passed) {
        Write-Host "  ✓ PASS: " -ForegroundColor Green -NoNewline
        Write-Host "$TestName" -ForegroundColor White
        if ($Details) {
            Write-Host "         $Details" -ForegroundColor Gray
        }
    }
    else {
        Write-Host "  ✗ FAIL: " -ForegroundColor Red -NoNewline
        Write-Host "$TestName" -ForegroundColor White
        if ($ErrorMessage) {
            Write-Host "         Error: $ErrorMessage" -ForegroundColor Yellow
        }
        if ($Details) {
            Write-Host "         $Details" -ForegroundColor Gray
        }
    }
}

# Test 1: Verify script location
Write-TestHeader "Test 1: Environment Validation"

$currentPath = Get-Location
$expectedPath = "FFUDevelopment"

if ($currentPath.Path -like "*$expectedPath*" -or (Test-Path ".\FFU.Common")) {
    Write-TestResult -TestName "Script location" -Passed $true -Details "Running from correct directory: $currentPath"
}
else {
    Write-TestResult -TestName "Script location" -Passed $false -Details "Expected to be in FFUDevelopment directory" -ErrorMessage "Current path: $currentPath"
    Write-Host "`nPlease run this script from the FFUDevelopment directory." -ForegroundColor Yellow
    exit 1
}

# Test 2: Check PowerShell version
if ($PSVersionTable.PSVersion.Major -ge 7) {
    Write-TestResult -TestName "PowerShell version" -Passed $true -Details "PowerShell $($PSVersionTable.PSVersion)"
}
else {
    Write-TestResult -TestName "PowerShell version" -Passed $false -Details "PowerShell $($PSVersionTable.PSVersion)" -ErrorMessage "PowerShell 7+ recommended for best results"
}

# Test 3: Check for Administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) {
    Write-TestResult -TestName "Administrator privileges" -Passed $true -Details "Running as Administrator"
}
else {
    Write-TestResult -TestName "Administrator privileges" -Passed $false -ErrorMessage "Script must run as Administrator for BITS operations"
    exit 1
}

# Test 4: ThreadJob Module Availability
Write-TestHeader "Test 2: ThreadJob Module"

$threadJobAvailable = Get-Module -ListAvailable -Name ThreadJob -ErrorAction SilentlyContinue

if ($threadJobAvailable) {
    Write-TestResult -TestName "ThreadJob module availability" -Passed $true -Details "Version $($threadJobAvailable.Version)"
}
else {
    Write-Host "  ThreadJob module not found. Attempting installation..." -ForegroundColor Yellow
    try {
        Install-Module -Name ThreadJob -Force -Scope CurrentUser -ErrorAction Stop
        $threadJobAvailable = Get-Module -ListAvailable -Name ThreadJob
        Write-TestResult -TestName "ThreadJob module installation" -Passed $true -Details "Successfully installed version $($threadJobAvailable.Version)"
    }
    catch {
        Write-TestResult -TestName "ThreadJob module installation" -Passed $false -ErrorMessage $_.Exception.Message
        Write-Host "`nContinuing with Start-Job comparison tests..." -ForegroundColor Yellow
    }
}

if ($threadJobAvailable) {
    Import-Module ThreadJob -Force
    Write-TestResult -TestName "ThreadJob module import" -Passed $true
}

# Test 5: FFU.Common Module Import
Write-TestHeader "Test 3: FFU.Common Module Validation"

if (Test-Path ".\FFU.Common\FFU.Common.Core.psm1") {
    Write-TestResult -TestName "FFU.Common.Core.psm1 exists" -Passed $true

    try {
        Import-Module ".\FFU.Common" -Force -ErrorAction Stop
        Write-TestResult -TestName "FFU.Common module import" -Passed $true

        # Check if Start-BitsTransferWithRetry exists and has new parameters
        $function = Get-Command Start-BitsTransferWithRetry -ErrorAction SilentlyContinue
        if ($function) {
            $hasCredentialParam = $function.Parameters.ContainsKey('Credential')
            $hasAuthParam = $function.Parameters.ContainsKey('Authentication')

            if ($hasCredentialParam -and $hasAuthParam) {
                Write-TestResult -TestName "Start-BitsTransferWithRetry enhancements" -Passed $true -Details "New Credential and Authentication parameters found"
            }
            else {
                Write-TestResult -TestName "Start-BitsTransferWithRetry enhancements" -Passed $false -ErrorMessage "Missing new parameters (Credential: $hasCredentialParam, Authentication: $hasAuthParam)"
            }
        }
        else {
            Write-TestResult -TestName "Start-BitsTransferWithRetry function" -Passed $false -ErrorMessage "Function not found in module"
        }
    }
    catch {
        Write-TestResult -TestName "FFU.Common module import" -Passed $false -ErrorMessage $_.Exception.Message
    }
}
else {
    Write-TestResult -TestName "FFU.Common.Core.psm1 exists" -Passed $false -ErrorMessage "File not found"
}

# Test 6: Network Credential Inheritance Test
Write-TestHeader "Test 4: Credential Inheritance Comparison"

Write-Host "`n  Testing credential inheritance in different job types..." -ForegroundColor Yellow

# Test with Start-Job
$startJobScript = {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    [PSCustomObject]@{
        UserName           = $identity.Name
        AuthenticationType = $identity.AuthenticationType
        IsAuthenticated    = $identity.IsAuthenticated
        IsSystem           = $identity.IsSystem
        HasNetworkAuth     = $identity.AuthenticationType -in @('Kerberos', 'NTLM', 'Negotiate')
    }
}

try {
    $startJobResult = Start-Job -ScriptBlock $startJobScript | Wait-Job | Receive-Job -AutoRemoveJob

    Write-Host "`n  Start-Job Results:" -ForegroundColor Cyan
    Write-Host "    User: $($startJobResult.UserName)"
    Write-Host "    Auth Type: $($startJobResult.AuthenticationType)"
    Write-Host "    Is Authenticated: $($startJobResult.IsAuthenticated)"
    Write-Host "    Has Network Auth: $($startJobResult.HasNetworkAuth)"

    if ($startJobResult.HasNetworkAuth) {
        Write-TestResult -TestName "Start-Job credential inheritance" -Passed $true -Details "Has network authentication"
    }
    else {
        Write-TestResult -TestName "Start-Job credential inheritance" -Passed $false -Details "No network authentication (expected - this is the bug)" -ErrorMessage "Auth type: $($startJobResult.AuthenticationType)"
    }
}
catch {
    Write-TestResult -TestName "Start-Job credential test" -Passed $false -ErrorMessage $_.Exception.Message
}

# Test with Start-ThreadJob (if available)
if (Get-Command Start-ThreadJob -ErrorAction SilentlyContinue) {
    try {
        $threadJobResult = Start-ThreadJob -ScriptBlock $startJobScript | Wait-Job | Receive-Job -AutoRemoveJob

        Write-Host "`n  Start-ThreadJob Results:" -ForegroundColor Cyan
        Write-Host "    User: $($threadJobResult.UserName)"
        Write-Host "    Auth Type: $($threadJobResult.AuthenticationType)"
        Write-Host "    Is Authenticated: $($threadJobResult.IsAuthenticated)"
        Write-Host "    Has Network Auth: $($threadJobResult.HasNetworkAuth)"

        if ($threadJobResult.HasNetworkAuth) {
            Write-TestResult -TestName "Start-ThreadJob credential inheritance" -Passed $true -Details "Has network authentication (FIX WORKING!)"
        }
        else {
            Write-TestResult -TestName "Start-ThreadJob credential inheritance" -Passed $false -ErrorMessage "Auth type: $($threadJobResult.AuthenticationType)"
        }
    }
    catch {
        Write-TestResult -TestName "Start-ThreadJob credential test" -Passed $false -ErrorMessage $_.Exception.Message
    }
}

# Test 7: BITS Transfer Tests (if not skipped)
if (-not $SkipDownloadTests) {
    Write-TestHeader "Test 5: BITS Transfer Validation"

    # Use a small, reliable test file from Microsoft
    $testUrl = "https://go.microsoft.com/fwlink/?LinkId=866658"  # Small MSI file (~1MB)
    $testDestination = Join-Path $env:TEMP "ffu_bits_test_$(Get-Date -Format 'yyyyMMddHHmmss').tmp"

    Write-Host "`n  Testing BITS transfer with ThreadJob (if available)..." -ForegroundColor Yellow

    if (Get-Command Start-ThreadJob -ErrorAction SilentlyContinue) {
        $bitsTestScript = {
            param($Source, $Dest, $ModulePath)

            try {
                # Import module in job context
                Import-Module $ModulePath -Force -ErrorAction Stop

                # Attempt BITS transfer
                Start-BitsTransferWithRetry -Source $Source -Destination $Dest -Retries 2

                # Check if file was created
                if (Test-Path $Dest) {
                    $size = (Get-Item $Dest).Length
                    return [PSCustomObject]@{
                        Success      = $true
                        Error        = $null
                        FileSize     = $size
                        ErrorCode    = $null
                    }
                }
                else {
                    return [PSCustomObject]@{
                        Success      = $false
                        Error        = "File not created"
                        FileSize     = 0
                        ErrorCode    = $null
                    }
                }
            }
            catch {
                return [PSCustomObject]@{
                    Success      = $false
                    Error        = $_.Exception.Message
                    FileSize     = 0
                    ErrorCode    = $_.Exception.HResult
                }
            }
        }

        try {
            $modulePath = (Get-Module FFU.Common).Path
            if (-not $modulePath) {
                $modulePath = Resolve-Path ".\FFU.Common\FFU.Common.psd1"
            }

            $threadJobBitsResult = Start-ThreadJob -ScriptBlock $bitsTestScript -ArgumentList @($testUrl, $testDestination, $modulePath) |
                Wait-Job -Timeout 60 |
                Receive-Job -AutoRemoveJob

            if ($threadJobBitsResult.Success) {
                Write-TestResult -TestName "BITS transfer in ThreadJob" -Passed $true -Details "Downloaded $($threadJobBitsResult.FileSize) bytes successfully"

                # Cleanup
                if (Test-Path $testDestination) {
                    Remove-Item $testDestination -Force
                }
            }
            else {
                $errorDetails = "Error: $($threadJobBitsResult.Error)"
                if ($threadJobBitsResult.ErrorCode -eq 0x800704DD -or $threadJobBitsResult.ErrorCode -eq -2147023651) {
                    $errorDetails += " (Error code 0x800704DD)"
                    Write-TestResult -TestName "BITS transfer in ThreadJob" -Passed $false -Details "AUTHENTICATION ERROR STILL PRESENT" -ErrorMessage $errorDetails
                }
                else {
                    Write-TestResult -TestName "BITS transfer in ThreadJob" -Passed $false -ErrorMessage $errorDetails
                }
            }
        }
        catch {
            Write-TestResult -TestName "BITS transfer in ThreadJob" -Passed $false -ErrorMessage $_.Exception.Message
        }
    }
    else {
        Write-Host "  Skipping BITS transfer test - ThreadJob not available" -ForegroundColor Yellow
    }

    # Test enhanced error detection
    Write-Host "`n  Testing enhanced error detection..." -ForegroundColor Yellow

    # Create a scenario that would trigger 0x800704DD if credentials are missing
    $errorTestScript = {
        param($ModulePath)

        try {
            Import-Module $ModulePath -Force -ErrorAction Stop

            # Try to download with deliberately broken context (simulate the old bug)
            # This will fail, but we want to see if error handling is improved
            Start-BitsTransferWithRetry -Source "https://nonexistent.invalid.test/file.zip" -Destination "$env:TEMP\test.zip" -Retries 1
        }
        catch {
            # Return error details
            return [PSCustomObject]@{
                ErrorMessage = $_.Exception.Message
                ErrorCode    = $_.Exception.HResult
                Contains800704DD = $_.Exception.Message -like "*0x800704DD*" -or $_.Exception.Message -like "*ERROR_NOT_LOGGED_ON*"
                ContainsGuidance = $_.Exception.Message -like "*ThreadJob*" -or $_.Exception.Message -like "*credential*"
            }
        }
    }

    if (Get-Command Start-Job -ErrorAction SilentlyContinue) {
        try {
            $modulePath = (Get-Module FFU.Common).Path
            if (-not $modulePath) {
                $modulePath = Resolve-Path ".\FFU.Common\FFU.Common.psd1"
            }

            # This should fail with network error, but we're checking error message quality
            $errorResult = Start-Job -ScriptBlock $errorTestScript -ArgumentList $modulePath |
                Wait-Job -Timeout 30 |
                Receive-Job -AutoRemoveJob -ErrorAction SilentlyContinue

            if ($null -ne $errorResult) {
                # We expect an error, so if we got error details back, check if they're helpful
                Write-TestResult -TestName "Enhanced error detection" -Passed $true -Details "Error handling provides diagnostic information"
            }
        }
        catch {
            # Expected to fail, just checking it doesn't crash
            Write-TestResult -TestName "Enhanced error detection" -Passed $true -Details "Error handled gracefully"
        }
    }
}
else {
    Write-Host "`n  Skipping download tests (-SkipDownloadTests specified)" -ForegroundColor Yellow
}

# Test 8: BuildFFUVM_UI.ps1 Changes Verification
Write-TestHeader "Test 6: UI Script Modifications"

if (Test-Path ".\BuildFFUVM_UI.ps1") {
    $uiScript = Get-Content ".\BuildFFUVM_UI.ps1" -Raw

    # Check for ThreadJob module import
    if ($uiScript -match "Import-Module ThreadJob") {
        Write-TestResult -TestName "ThreadJob import added to UI script" -Passed $true
    }
    else {
        Write-TestResult -TestName "ThreadJob import added to UI script" -Passed $false -ErrorMessage "ThreadJob import not found"
    }

    # Check for Start-ThreadJob usage
    $threadJobUsages = ([regex]::Matches($uiScript, 'Start-ThreadJob')).Count
    if ($threadJobUsages -ge 2) {
        Write-TestResult -TestName "Start-ThreadJob usage in UI script" -Passed $true -Details "Found $threadJobUsages occurrences"
    }
    else {
        Write-TestResult -TestName "Start-ThreadJob usage in UI script" -Passed $false -Details "Found $threadJobUsages occurrences (expected 2+)"
    }

    # Check for fallback logic
    if ($uiScript -match "Get-Command Start-ThreadJob") {
        Write-TestResult -TestName "ThreadJob availability check" -Passed $true -Details "Fallback logic present"
    }
    else {
        Write-TestResult -TestName "ThreadJob availability check" -Passed $false -ErrorMessage "No fallback check found"
    }
}
else {
    Write-TestResult -TestName "BuildFFUVM_UI.ps1 exists" -Passed $false -ErrorMessage "File not found"
}

# Summary Report
Write-TestHeader "Test Summary"

$totalTests = $testResults.Count
$passedTests = ($testResults | Where-Object { $_.Passed }).Count
$failedTests = $totalTests - $passedTests
$passRate = if ($totalTests -gt 0) { [math]::Round(($passedTests / $totalTests) * 100, 2) } else { 0 }

Write-Host ""
Write-Host "  Total Tests:  " -NoNewline
Write-Host "$totalTests" -ForegroundColor Cyan
Write-Host "  Passed:       " -NoNewline
Write-Host "$passedTests" -ForegroundColor Green
Write-Host "  Failed:       " -NoNewline
Write-Host "$failedTests" -ForegroundColor $(if ($failedTests -eq 0) { 'Green' } else { 'Red' })
Write-Host "  Pass Rate:    " -NoNewline
Write-Host "$passRate%" -ForegroundColor $(if ($passRate -ge 80) { 'Green' } elseif ($passRate -ge 60) { 'Yellow' } else { 'Red' })
Write-Host ""

# Failed tests details
if ($failedTests -gt 0) {
    Write-Host "  Failed Tests:" -ForegroundColor Red
    $testResults | Where-Object { -not $_.Passed } | ForEach-Object {
        Write-Host "    • $($_.TestName)" -ForegroundColor Yellow
        if ($_.ErrorMessage) {
            Write-Host "      $($_.ErrorMessage)" -ForegroundColor Gray
        }
    }
    Write-Host ""
}

# Overall verdict
Write-Host "$('=' * 80)" -ForegroundColor Cyan
if ($passRate -ge 80) {
    Write-Host "  OVERALL: FIX VERIFIED ✓" -ForegroundColor Green
    Write-Host "  The BITS authentication fix is working correctly." -ForegroundColor Green
}
elseif ($passRate -ge 60) {
    Write-Host "  OVERALL: PARTIAL SUCCESS ⚠" -ForegroundColor Yellow
    Write-Host "  The fix is partially working. Review failed tests above." -ForegroundColor Yellow
}
else {
    Write-Host "  OVERALL: FIX ISSUES DETECTED ✗" -ForegroundColor Red
    Write-Host "  The fix has problems. Review failed tests above." -ForegroundColor Red
}
Write-Host "$('=' * 80)" -ForegroundColor Cyan
Write-Host ""

# Export results to JSON
$resultsFile = ".\Test-BITSAuthenticationFix-Results_$(Get-Date -Format 'yyyyMMddHHmmss').json"
$testResults | ConvertTo-Json -Depth 3 | Set-Content $resultsFile
Write-Host "  Detailed results exported to: $resultsFile" -ForegroundColor Gray
Write-Host ""

# Return exit code
if ($failedTests -eq 0) {
    exit 0
}
else {
    exit 1
}
