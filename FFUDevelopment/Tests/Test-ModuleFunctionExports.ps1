#Requires -Version 5.1
<#
.SYNOPSIS
    Validates that all expected functions are exported from FFU Builder modules.

.DESCRIPTION
    This test suite verifies that all critical functions are properly exported
    from each FFU Builder module. This prevents regression issues where functions
    are accidentally lost during refactoring or modularization.

    Created in response to missing Get-WindowsVersionInfo function issue.

.NOTES
    Version: 1.0.0
    Purpose: Prevent function export regressions
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

# Set up module path
$FFUDevelopmentPath = Split-Path $PSScriptRoot -Parent
$ModulesPath = Join-Path $FFUDevelopmentPath "Modules"

if ($env:PSModulePath -notlike "*$ModulesPath*") {
    $env:PSModulePath = "$ModulesPath;$env:PSModulePath"
}

Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host "FFU Builder Module Function Export Verification" -ForegroundColor Cyan
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host ""
Write-Host "Purpose: Prevent regression where functions are lost during modularization" -ForegroundColor Gray
Write-Host ""

# =============================================================================
# Define expected exports for each module
# =============================================================================

$ExpectedExports = @{
    'FFU.Core' = @(
        'Get-Parameters',
        'Write-VariableValues',          # v1.0.11: Renamed from LogVariableValues
        'Get-ChildProcesses',
        'Test-Url',
        'Get-PrivateProfileString',
        'Get-PrivateProfileSection',
        'Get-ShortenedWindowsSKU',
        'New-FFUFileName',
        'Export-ConfigFile',
        'New-RunSession',
        'Get-CurrentRunManifest',
        'Save-RunManifest',
        'Set-DownloadInProgress',        # v1.0.11: Renamed from Mark-DownloadInProgress
        'Clear-DownloadInProgress',
        'Remove-InProgressItems',
        'Clear-CurrentRunDownloads',     # v1.0.11: Renamed from Cleanup-CurrentRunDownloads
        'Restore-RunJsonBackups',
        'Invoke-WithErrorHandling',
        'Test-ExternalCommandSuccess',
        'Invoke-WithCleanup',
        'Register-CleanupAction',
        'Unregister-CleanupAction',
        'Invoke-FailureCleanup',
        'Clear-CleanupRegistry',
        'Get-CleanupRegistry',
        'Register-VMCleanup',
        'Register-VHDXCleanup',
        'Register-DISMMountCleanup',
        'Register-ISOCleanup',
        'Register-TempFileCleanup',
        'Register-NetworkShareCleanup',
        'Register-UserAccountCleanup',
        'New-SecureRandomPassword',
        'ConvertFrom-SecureStringToPlainText',
        'Clear-PlainTextPassword',
        'Remove-SecureStringFromMemory'
    )
    'FFU.Imaging' = @(
        'Initialize-DISMService',
        'Test-WimSourceAccessibility',
        'Invoke-ExpandWindowsImageWithRetry',
        'Get-WimFromISO',
        'Get-Index',
        'New-ScratchVhdx',
        'New-SystemPartition',
        'New-MSRPartition',
        'New-OSPartition',
        'New-RecoveryPartition',
        'Add-BootFiles',
        'Enable-WindowsFeaturesByName',
        'Dismount-ScratchVhdx',
        'Optimize-FFUCaptureDrive',
        'Get-WindowsVersionInfo',  # Critical: Added to fix missing function issue
        'New-FFU',
        'Remove-FFU',
        'Start-RequiredServicesForDISM',
        'Invoke-FFUOptimizeWithScratchDir'
    )
    'FFU.VM' = @(
        'Get-LocalUserAccount',
        'New-LocalUserAccount',
        'Remove-LocalUserAccount',
        'Set-LocalUserPassword',
        'Set-LocalUserAccountExpiry',
        'New-FFUVM',
        'Remove-FFUVM',
        'Get-FFUEnvironment',
        'Set-CaptureFFU',
        'Remove-FFUUserShare',
        'Remove-SensitiveCaptureMedia',
        'Update-CaptureFFUScript'
    )
    'FFU.Updates' = @(
        'Get-ProductsCab',
        'Get-WindowsESD',
        'Get-KBLink',
        'Get-UpdateFileInfo',
        'Save-KB',
        'Test-MountedImageDiskSpace',
        'Add-WindowsPackageWithRetry',
        'Add-WindowsPackageWithUnattend'
    )
    'FFU.ADK' = @(
        'Write-ADKValidationLog',
        'Test-ADKPrerequisites',
        'Get-ADKURL',
        'Install-ADK',
        'Get-InstalledProgramRegKey',
        'Uninstall-ADK',
        'Confirm-ADKVersionIsLatest',
        'Get-ADK'
    )
    'FFU.Drivers' = @(
        'Get-MicrosoftDrivers',
        'Get-HPDrivers',
        'Get-LenovoDrivers',
        'Get-DellDrivers',
        'Copy-Drivers'
    )
    'FFU.Apps' = @(
        'Get-ODTURL',
        'Get-Office',
        'New-AppsISO',
        'Remove-Apps',
        'Remove-DisabledArtifacts'
    )
    'FFU.Media' = @(
        'Invoke-DISMPreFlightCleanup',
        'Invoke-CopyPEWithRetry',
        'New-PEMedia',
        'Get-PEArchitecture'
    )
}

# =============================================================================
# Test each module
# =============================================================================

foreach ($moduleName in $ExpectedExports.Keys | Sort-Object) {
    Write-Host ""
    Write-Host "Testing $moduleName Module Exports..." -ForegroundColor Yellow

    $modulePath = Join-Path $ModulesPath "$moduleName\$moduleName.psd1"

    if (-not (Test-Path $modulePath)) {
        Write-TestResult -TestName "$moduleName module manifest exists" -Passed $false -Message "Module not found at: $modulePath"
        continue
    }

    try {
        Import-Module $modulePath -Force -ErrorAction Stop 2>$null
        Write-TestResult -TestName "$moduleName module loads successfully" -Passed $true
    }
    catch {
        Write-TestResult -TestName "$moduleName module loads successfully" -Passed $false -Message $_.Exception.Message
        continue
    }

    $exportedFunctions = (Get-Module $moduleName).ExportedFunctions.Keys
    $expectedFunctions = $ExpectedExports[$moduleName]

    foreach ($func in $expectedFunctions) {
        $found = $func -in $exportedFunctions
        $testName = "Function '$func' is exported from $moduleName"
        Write-TestResult -TestName $testName -Passed $found -Message $(if (-not $found) { "CRITICAL: Function missing from module exports!" })
    }

    # Check for any unexpected exports (informational only)
    $unexpectedExports = $exportedFunctions | Where-Object { $_ -notin $expectedFunctions }
    if ($unexpectedExports -and $Verbose) {
        Write-Host "  [INFO] Additional exports in ${moduleName}: $($unexpectedExports -join ', ')" -ForegroundColor Cyan
    }
}

# =============================================================================
# Test specific critical function - Get-WindowsVersionInfo
# This is the function that was previously missing
# =============================================================================
Write-Host ""
Write-Host "Testing Critical Function: Get-WindowsVersionInfo..." -ForegroundColor Yellow

try {
    $cmd = Get-Command Get-WindowsVersionInfo -ErrorAction Stop
    Write-TestResult -TestName "Get-WindowsVersionInfo command exists" -Passed $true
    Write-TestResult -TestName "Get-WindowsVersionInfo is from FFU.Imaging" -Passed ($cmd.Source -eq 'FFU.Imaging')

    # Verify parameters
    $params = $cmd.Parameters.Keys
    Write-TestResult -TestName "Get-WindowsVersionInfo has OsPartitionDriveLetter parameter" -Passed ('OsPartitionDriveLetter' -in $params)
    Write-TestResult -TestName "Get-WindowsVersionInfo has InstallationType parameter" -Passed ('InstallationType' -in $params)
    Write-TestResult -TestName "Get-WindowsVersionInfo has ShortenedWindowsSKU parameter" -Passed ('ShortenedWindowsSKU' -in $params)
}
catch {
    Write-TestResult -TestName "Get-WindowsVersionInfo command exists" -Passed $false -Message "CRITICAL: Function not found! This will cause FFU capture to fail."
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
    Write-Host "All tests passed! All expected functions are exported." -ForegroundColor Green
    exit 0
} else {
    Write-Host "CRITICAL: Some functions are missing from module exports!" -ForegroundColor Red
    Write-Host "This can cause runtime errors like 'The term X is not recognized'" -ForegroundColor Red
    exit 1
}
