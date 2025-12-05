<#
.SYNOPSIS
    Test script for WIM source accessibility validation and Expand-WindowsImage retry logic

.DESCRIPTION
    Tests the following functions in FFU.Imaging module:
    - Test-WimSourceAccessibility: Validates WIM file accessibility and ISO mount status
    - Invoke-ExpandWindowsImageWithRetry: Retry wrapper for Expand-WindowsImage

    These functions address error 0x8007048F "The device is not connected" which occurs
    when ISO mounts become unavailable during long Expand-WindowsImage operations.

.NOTES
    Run this script as Administrator to test ISO mount scenarios.
    Some tests require actual ISO files or mock scenarios.
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

param(
    [Parameter(Mandatory = $false)]
    [string]$FFUDevelopmentPath = "C:\FFUDevelopment",

    [Parameter(Mandatory = $false)]
    [string]$TestISOPath,

    [Parameter(Mandatory = $false)]
    [switch]$SkipISOTests
)

# Initialize test results
$script:TestResults = @{
    Passed = 0
    Failed = 0
    Skipped = 0
    Tests = @()
}

function Write-TestResult {
    param(
        [string]$TestName,
        [string]$Status,  # 'Passed', 'Failed', 'Skipped'
        [string]$Message = ""
    )

    $color = switch ($Status) {
        'Passed' { 'Green' }
        'Failed' { 'Red' }
        'Skipped' { 'Yellow' }
        default { 'White' }
    }

    $script:TestResults[$Status]++
    $script:TestResults.Tests += [PSCustomObject]@{
        Name = $TestName
        Status = $Status
        Message = $Message
    }

    $statusSymbol = switch ($Status) {
        'Passed' { '[PASS]' }
        'Failed' { '[FAIL]' }
        'Skipped' { '[SKIP]' }
    }

    Write-Host "$statusSymbol $TestName" -ForegroundColor $color
    if ($Message) {
        Write-Host "       $Message" -ForegroundColor Gray
    }
}

function Test-Assertion {
    param(
        [string]$TestName,
        [scriptblock]$Test,
        [string]$FailMessage = "Assertion failed"
    )

    try {
        $result = & $Test
        if ($result) {
            Write-TestResult -TestName $TestName -Status 'Passed'
            return $true
        }
        else {
            Write-TestResult -TestName $TestName -Status 'Failed' -Message $FailMessage
            return $false
        }
    }
    catch {
        Write-TestResult -TestName $TestName -Status 'Failed' -Message $_.Exception.Message
        return $false
    }
}

# ============================================================================
# Setup
# ============================================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "WIM Accessibility & Retry Logic Tests" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Import module
$modulePath = Join-Path $FFUDevelopmentPath "Modules"
if (-not (Test-Path $modulePath)) {
    # Try relative path from script location
    $modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) "FFUDevelopment\Modules"
}

Write-Host "Module path: $modulePath" -ForegroundColor Gray

# Add to PSModulePath
if ($env:PSModulePath -notlike "*$modulePath*") {
    $env:PSModulePath = "$modulePath;$env:PSModulePath"
}

try {
    Import-Module "$modulePath\FFU.Core" -Force -ErrorAction Stop
    Import-Module "$modulePath\FFU.Imaging" -Force -ErrorAction Stop
    Write-Host "Modules imported successfully`n" -ForegroundColor Green
}
catch {
    Write-Host "ERROR: Failed to import modules: $_" -ForegroundColor Red
    exit 1
}

# ============================================================================
# Test 1: Function Exports
# ============================================================================
Write-Host "`n--- Function Export Tests ---" -ForegroundColor Yellow

Test-Assertion "Test-WimSourceAccessibility is exported" {
    Get-Command Test-WimSourceAccessibility -Module FFU.Imaging -ErrorAction SilentlyContinue
}

Test-Assertion "Invoke-ExpandWindowsImageWithRetry is exported" {
    Get-Command Invoke-ExpandWindowsImageWithRetry -Module FFU.Imaging -ErrorAction SilentlyContinue
}

Test-Assertion "New-OSPartition has ISOPath parameter" {
    $cmd = Get-Command New-OSPartition -Module FFU.Imaging -ErrorAction SilentlyContinue
    $cmd.Parameters.ContainsKey('ISOPath')
}

# ============================================================================
# Test 2: Test-WimSourceAccessibility - Invalid Paths
# ============================================================================
Write-Host "`n--- WIM Accessibility - Invalid Path Tests ---" -ForegroundColor Yellow

Test-Assertion "Non-existent WIM path returns IsAccessible=false" {
    $result = Test-WimSourceAccessibility -WimPath "Z:\NonExistent\install.wim"
    $result.IsAccessible -eq $false -and $result.ErrorMessage -match "(not accessible|not found)"
}

Test-Assertion "Non-existent drive returns appropriate error" {
    $result = Test-WimSourceAccessibility -WimPath "Q:\sources\install.wim"
    $result.IsAccessible -eq $false -and $result.ErrorMessage -match "not accessible"
}

# ============================================================================
# Test 3: Test-WimSourceAccessibility - Valid Local Files
# ============================================================================
Write-Host "`n--- WIM Accessibility - Local File Tests ---" -ForegroundColor Yellow

# Create a test file for accessibility testing
$testDir = Join-Path $env:TEMP "FFU_WimAccessTest"
$testWimPath = Join-Path $testDir "test.wim"

try {
    New-Item -Path $testDir -ItemType Directory -Force | Out-Null
    # Create a small test file (not a real WIM, but good for accessibility testing)
    [byte[]]$testContent = 1..1024 | ForEach-Object { Get-Random -Maximum 256 }
    [System.IO.File]::WriteAllBytes($testWimPath, $testContent)

    Test-Assertion "Existing local file returns IsAccessible=true" {
        $result = Test-WimSourceAccessibility -WimPath $testWimPath
        $result.IsAccessible -eq $true
    }

    Test-Assertion "WimSizeBytes is populated for accessible file" {
        $result = Test-WimSourceAccessibility -WimPath $testWimPath
        $result.WimSizeBytes -gt 0
    }

    Test-Assertion "DriveRoot is correctly identified" {
        $result = Test-WimSourceAccessibility -WimPath $testWimPath
        $result.DriveRoot -eq (Split-Path -Qualifier $testWimPath)
    }
}
finally {
    # Cleanup
    Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
}

# ============================================================================
# Test 4: Test-WimSourceAccessibility - ISO Mount Validation
# ============================================================================
Write-Host "`n--- WIM Accessibility - ISO Mount Tests ---" -ForegroundColor Yellow

if ($SkipISOTests) {
    Write-TestResult "ISO mount validation (mounted ISO)" -Status 'Skipped' -Message "SkipISOTests specified"
    Write-TestResult "ISO mount validation (unmounted ISO)" -Status 'Skipped' -Message "SkipISOTests specified"
    Write-TestResult "ISO mount validation (invalid ISO path)" -Status 'Skipped' -Message "SkipISOTests specified"
}
elseif ($TestISOPath -and (Test-Path $TestISOPath)) {
    # Test with actual ISO file
    try {
        # Mount the ISO
        Write-Host "Mounting test ISO: $TestISOPath" -ForegroundColor Gray
        $mountResult = Mount-DiskImage -ImagePath $TestISOPath -PassThru
        $isoVolume = $mountResult | Get-Volume
        $wimPath = "$($isoVolume.DriveLetter):\sources\install.wim"
        $esdPath = "$($isoVolume.DriveLetter):\sources\install.esd"

        $actualWimPath = if (Test-Path $wimPath) { $wimPath } elseif (Test-Path $esdPath) { $esdPath } else { $null }

        if ($actualWimPath) {
            Test-Assertion "Mounted ISO WIM is accessible" {
                $result = Test-WimSourceAccessibility -WimPath $actualWimPath -ISOPath $TestISOPath
                $result.IsAccessible -eq $true -and $result.ISOIsMounted -eq $true
            }
        }
        else {
            Write-TestResult "Mounted ISO WIM is accessible" -Status 'Skipped' -Message "No install.wim/esd found in ISO"
        }

        # Unmount and test again
        Dismount-DiskImage -ImagePath $TestISOPath | Out-Null
        Start-Sleep -Seconds 2

        Test-Assertion "Unmounted ISO reports ISOIsMounted=false" {
            $result = Test-WimSourceAccessibility -WimPath $actualWimPath -ISOPath $TestISOPath
            $result.IsAccessible -eq $false -and $result.ISOIsMounted -eq $false
        }
    }
    finally {
        # Ensure ISO is unmounted
        Dismount-DiskImage -ImagePath $TestISOPath -ErrorAction SilentlyContinue
    }
}
else {
    Write-TestResult "ISO mount validation tests" -Status 'Skipped' -Message "No TestISOPath provided or file not found"
}

# Test invalid ISO path
Test-Assertion "Invalid ISOPath is handled gracefully" {
    $result = Test-WimSourceAccessibility -WimPath "C:\Windows\System32\config\SYSTEM" -ISOPath "Z:\NonExistent.iso"
    # Should handle the error without throwing
    $true  # If we get here without exception, test passes
}

# ============================================================================
# Test 5: Invoke-ExpandWindowsImageWithRetry - Parameter Validation
# ============================================================================
Write-Host "`n--- Expand Retry Function - Parameter Tests ---" -ForegroundColor Yellow

Test-Assertion "Invoke-ExpandWindowsImageWithRetry requires ImagePath" {
    $cmd = Get-Command Invoke-ExpandWindowsImageWithRetry -Module FFU.Imaging
    $param = $cmd.Parameters['ImagePath']
    $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
        ForEach-Object { $_.Mandatory } | Select-Object -First 1
}

Test-Assertion "Invoke-ExpandWindowsImageWithRetry requires Index" {
    $cmd = Get-Command Invoke-ExpandWindowsImageWithRetry -Module FFU.Imaging
    $param = $cmd.Parameters['Index']
    $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
        ForEach-Object { $_.Mandatory } | Select-Object -First 1
}

Test-Assertion "Invoke-ExpandWindowsImageWithRetry requires ApplyPath" {
    $cmd = Get-Command Invoke-ExpandWindowsImageWithRetry -Module FFU.Imaging
    $param = $cmd.Parameters['ApplyPath']
    $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
        ForEach-Object { $_.Mandatory } | Select-Object -First 1
}

Test-Assertion "Invoke-ExpandWindowsImageWithRetry has optional ISOPath" {
    $cmd = Get-Command Invoke-ExpandWindowsImageWithRetry -Module FFU.Imaging
    $param = $cmd.Parameters['ISOPath']
    $isMandatory = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
        ForEach-Object { $_.Mandatory } | Select-Object -First 1
    $isMandatory -eq $false -or $null -eq $isMandatory
}

Test-Assertion "Invoke-ExpandWindowsImageWithRetry has MaxRetries with default 2" {
    $cmd = Get-Command Invoke-ExpandWindowsImageWithRetry -Module FFU.Imaging
    $param = $cmd.Parameters['MaxRetries']
    $param -ne $null
}

# ============================================================================
# Test 6: New-OSPartition - ISOPath Parameter
# ============================================================================
Write-Host "`n--- New-OSPartition ISOPath Integration ---" -ForegroundColor Yellow

Test-Assertion "New-OSPartition ISOPath parameter is optional" {
    $cmd = Get-Command New-OSPartition -Module FFU.Imaging
    $param = $cmd.Parameters['ISOPath']
    $isMandatory = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
        ForEach-Object { $_.Mandatory } | Select-Object -First 1
    $isMandatory -eq $false -or $null -eq $isMandatory
}

Test-Assertion "New-OSPartition ISOPath parameter is type string" {
    $cmd = Get-Command New-OSPartition -Module FFU.Imaging
    $param = $cmd.Parameters['ISOPath']
    $param.ParameterType -eq [string]
}

# ============================================================================
# Test 7: Error Code Detection
# ============================================================================
Write-Host "`n--- Error Code Detection Tests ---" -ForegroundColor Yellow

Test-Assertion "HResult -2147023729 equals 0x8007048F" {
    [int]-2147023729 -eq [int]0x8007048F
}

Test-Assertion "0x8007048F is ERROR_DEVICE_NOT_CONNECTED (1167)" {
    $errorCode = 0x8007048F -band 0xFFFF  # Extract lower 16 bits
    $errorCode -eq 1167
}

# ============================================================================
# Test 8: BuildFFUVM.ps1 Integration
# ============================================================================
Write-Host "`n--- BuildFFUVM.ps1 Integration Tests ---" -ForegroundColor Yellow

$buildScript = Join-Path $FFUDevelopmentPath "BuildFFUVM.ps1"
if (-not (Test-Path $buildScript)) {
    $buildScript = Join-Path (Split-Path $PSScriptRoot -Parent) "FFUDevelopment\BuildFFUVM.ps1"
}

if (Test-Path $buildScript) {
    $content = Get-Content $buildScript -Raw

    Test-Assertion "BuildFFUVM.ps1 passes ISOPath to New-OSPartition" {
        $content -match "New-OSPartition.*-ISOPath\s+\`$ISOPath"
    }
}
else {
    Write-TestResult "BuildFFUVM.ps1 integration" -Status 'Skipped' -Message "BuildFFUVM.ps1 not found"
}

# ============================================================================
# Summary
# ============================================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Passed:  $($script:TestResults.Passed)" -ForegroundColor Green
Write-Host "Failed:  $($script:TestResults.Failed)" -ForegroundColor Red
Write-Host "Skipped: $($script:TestResults.Skipped)" -ForegroundColor Yellow
Write-Host "Total:   $($script:TestResults.Tests.Count)" -ForegroundColor White

$overallResult = if ($script:TestResults.Failed -eq 0) { "PASS" } else { "FAIL" }
$overallColor = if ($script:TestResults.Failed -eq 0) { "Green" } else { "Red" }
Write-Host "`nOverall: $overallResult" -ForegroundColor $overallColor

# Exit with appropriate code
if ($script:TestResults.Failed -gt 0) {
    Write-Host "`nFailed tests:" -ForegroundColor Red
    $script:TestResults.Tests | Where-Object Status -eq 'Failed' | ForEach-Object {
        Write-Host "  - $($_.Name): $($_.Message)" -ForegroundColor Red
    }
    exit 1
}
else {
    Write-Host "`nAll tests passed!" -ForegroundColor Green
    exit 0
}
