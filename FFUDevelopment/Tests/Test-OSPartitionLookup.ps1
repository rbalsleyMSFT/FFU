#Requires -Version 5.1
<#
.SYNOPSIS
    Tests the OS partition lookup logic in FFU.Imaging module.

.DESCRIPTION
    Validates that the New-FFU function uses Get-Partition with -DiskNumber parameter
    instead of relying on piping, which is more reliable across different disk object types.

    This test was created after discovering that piping VhdxDisk to Get-Partition failed
    in some cases depending on how the disk object was obtained (Initialize-Disk vs Get-Disk).

.NOTES
    Version: 1.0.0
    Created to prevent regression of OS partition lookup issue
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
$ModulesPath = Join-Path $FFUDevelopmentPath "Modules"
$ImagingModule = Join-Path $ModulesPath "FFU.Imaging\FFU.Imaging.psm1"

Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host "OS Partition Lookup Tests" -ForegroundColor Cyan
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host ""
Write-Host "Purpose: Ensure OS partition lookup uses reliable DiskNumber parameter" -ForegroundColor Gray
Write-Host ""

# =============================================================================
# Test 1: Verify New-FFU uses Get-Partition with -DiskNumber
# =============================================================================
Write-Host "Testing FFU.Imaging OS partition lookup..." -ForegroundColor Yellow

try {
    $content = Get-Content -Path $ImagingModule -Raw -ErrorAction Stop

    # Find the OS partition lookup code in New-FFU function
    # Should use Get-Partition -DiskNumber instead of piping
    $usesDiskNumberParam = $content -match 'Get-Partition\s+-DiskNumber\s+\$'
    Write-TestResult -TestName "Uses Get-Partition with -DiskNumber parameter" -Passed $usesDiskNumberParam -Message $(if (-not $usesDiskNumberParam) { "CRITICAL: Should use 'Get-Partition -DiskNumber' for reliable lookup" })

    # Verify NOT using problematic piping pattern
    $usesBadPiping = $content -match '\$VhdxDisk\s*\|\s*Get-Partition'
    Write-TestResult -TestName "Does NOT use unreliable piping pattern" -Passed (-not $usesBadPiping) -Message $(if ($usesBadPiping) { "WARNING: Piping disk object to Get-Partition is unreliable" })

    # Verify VhdxDisk validation exists
    $validatesVhdxDisk = $content -match 'if\s*\(\s*-not\s+\$VhdxDisk\s*\)'
    Write-TestResult -TestName "Validates VhdxDisk parameter is not null" -Passed $validatesVhdxDisk

    # Verify DiskNumber property validation
    $validatesDiskNumber = $content -match 'if\s*\(\s*\$null\s+-eq\s+\$diskNumber\s*\)'
    Write-TestResult -TestName "Validates DiskNumber property exists" -Passed $validatesDiskNumber

    # Verify partition count validation
    $validatesPartitions = $content -match 'if\s*\(\s*-not\s+\$allPartitions\s*\)'
    Write-TestResult -TestName "Validates partitions were found" -Passed $validatesPartitions

    # Verify GPT type filtering for OS partition
    $gptTypeGuid = '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}'
    $usesGptTypeFilter = $content -match [regex]::Escape($gptTypeGuid)
    Write-TestResult -TestName "Uses correct GPT type GUID for Basic Data Partition" -Passed $usesGptTypeFilter

    # Verify drive letter validation (checks that $osPartitionDriveLetter is not empty)
    $validatesDriveLetter = $content -match 'if\s*\(\s*-not\s+\$osPartitionDriveLetter\s*\)'
    Write-TestResult -TestName "Validates OS partition has assigned drive letter" -Passed $validatesDriveLetter
}
catch {
    Write-TestResult -TestName "Reading FFU.Imaging module" -Passed $false -Message $_.Exception.Message
}

# =============================================================================
# Test 2: Verify Get-WindowsVersionInfo function exists and is exported
# =============================================================================
Write-Host ""
Write-Host "Testing Get-WindowsVersionInfo function..." -ForegroundColor Yellow

try {
    # Import the module
    if ($env:PSModulePath -notlike "*$ModulesPath*") {
        $env:PSModulePath = "$ModulesPath;$env:PSModulePath"
    }

    Import-Module (Join-Path $ModulesPath "FFU.Imaging\FFU.Imaging.psd1") -Force -ErrorAction Stop 2>$null

    $cmd = Get-Command Get-WindowsVersionInfo -ErrorAction Stop

    Write-TestResult -TestName "Get-WindowsVersionInfo command exists" -Passed $true
    Write-TestResult -TestName "Get-WindowsVersionInfo is from FFU.Imaging" -Passed ($cmd.Source -eq 'FFU.Imaging')

    # Verify required parameters
    $params = $cmd.Parameters
    Write-TestResult -TestName "Has OsPartitionDriveLetter parameter (mandatory)" -Passed ($params.ContainsKey('OsPartitionDriveLetter') -and $params['OsPartitionDriveLetter'].Attributes.Mandatory)
    Write-TestResult -TestName "Has InstallationType parameter (mandatory)" -Passed ($params.ContainsKey('InstallationType') -and $params['InstallationType'].Attributes.Mandatory)
    Write-TestResult -TestName "Has ShortenedWindowsSKU parameter (mandatory)" -Passed ($params.ContainsKey('ShortenedWindowsSKU') -and $params['ShortenedWindowsSKU'].Attributes.Mandatory)

    # Verify parameter validation attributes
    $driveLetterValidation = $params['OsPartitionDriveLetter'].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidatePatternAttribute] }
    Write-TestResult -TestName "OsPartitionDriveLetter has ValidatePattern attribute" -Passed ($null -ne $driveLetterValidation)

    $installTypeValidation = $params['InstallationType'].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
    Write-TestResult -TestName "InstallationType has ValidateSet (Client/Server)" -Passed ($null -ne $installTypeValidation)
}
catch {
    Write-TestResult -TestName "Get-WindowsVersionInfo function" -Passed $false -Message $_.Exception.Message
}

# =============================================================================
# Test 3: Verify error messages are descriptive
# =============================================================================
Write-Host ""
Write-Host "Testing error message quality..." -ForegroundColor Yellow

try {
    $content = Get-Content -Path $ImagingModule -Raw -ErrorAction Stop

    # Verify descriptive error for missing VhdxDisk
    $hasVhdxDiskError = $content -match 'throw.*VhdxDisk parameter is required'
    Write-TestResult -TestName "Has descriptive error for missing VhdxDisk" -Passed $hasVhdxDiskError

    # Verify descriptive error for invalid DiskNumber
    $hasDiskNumberError = $content -match 'throw.*missing DiskNumber property'
    Write-TestResult -TestName "Has descriptive error for missing DiskNumber" -Passed $hasDiskNumberError

    # Verify descriptive error for no partitions
    $hasNoPartitionsError = $content -match 'throw.*Could not find any partitions'
    Write-TestResult -TestName "Has descriptive error for no partitions found" -Passed $hasNoPartitionsError

    # Verify descriptive error for missing OS partition
    $hasNoOSPartitionError = $content -match 'throw.*Could not find OS partition'
    Write-TestResult -TestName "Has descriptive error for missing OS partition" -Passed $hasNoOSPartitionError

    # Verify descriptive error for missing drive letter
    $hasNoDriveLetterError = $content -match 'throw.*does not have an assigned drive letter'
    Write-TestResult -TestName "Has descriptive error for missing drive letter" -Passed $hasNoDriveLetterError
}
catch {
    Write-TestResult -TestName "Error message analysis" -Passed $false -Message $_.Exception.Message
}

# =============================================================================
# Test 4: Verify diagnostic logging is present
# =============================================================================
Write-Host ""
Write-Host "Testing diagnostic logging..." -ForegroundColor Yellow

try {
    $content = Get-Content -Path $ImagingModule -Raw -ErrorAction Stop

    # Verify logging of disk number being used
    $logsDiskNumber = $content -match 'WriteLog.*disk number.*\$diskNumber'
    Write-TestResult -TestName "Logs disk number being used" -Passed $logsDiskNumber

    # Verify logging of partition count
    $logsPartitionCount = $content -match 'WriteLog.*partition\(s\)'
    Write-TestResult -TestName "Logs partition count found" -Passed $logsPartitionCount

    # Verify logging on error conditions
    $logsOnError = $content -match 'WriteLog\s+"ERROR:'
    Write-TestResult -TestName "Logs ERROR messages on failure conditions" -Passed $logsOnError
}
catch {
    Write-TestResult -TestName "Diagnostic logging analysis" -Passed $false -Message $_.Exception.Message
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
    Write-Host "All tests passed! OS partition lookup is correctly implemented." -ForegroundColor Green
    exit 0
} else {
    Write-Host "CRITICAL: Some tests failed. OS partition lookup may fail!" -ForegroundColor Red
    exit 1
}
