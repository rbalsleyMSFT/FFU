#Requires -Version 5.1
<#
.SYNOPSIS
    Tests the cleanup registration system implemented in FFU.Core module.

.DESCRIPTION
    Validates the cleanup registration functions including Register-CleanupAction,
    Unregister-CleanupAction, Invoke-FailureCleanup, Clear-CleanupRegistry, and
    specialized helpers like Register-VMCleanup, Register-VHDXCleanup, etc.

.NOTES
    Version: 1.0.6
    Created for cleanup registration system validation
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
Write-Host "FFU Builder Cleanup Registration Test Suite" -ForegroundColor Cyan
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host ""

# =============================================================================
# Test 1: FFU.Core Module Export Verification
# =============================================================================
Write-Host "Testing FFU.Core Module Exports..." -ForegroundColor Yellow

try {
    Import-Module (Join-Path $ModulesPath "FFU.Core\FFU.Core.psd1") -Force -ErrorAction Stop

    $exportedFunctions = (Get-Module FFU.Core).ExportedFunctions.Keys

    Write-TestResult -TestName "FFU.Core module loads successfully" -Passed $true

    # Test for cleanup registration functions
    $expectedFunctions = @(
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
        'Register-UserAccountCleanup'
    )

    foreach ($func in $expectedFunctions) {
        $found = $func -in $exportedFunctions
        Write-TestResult -TestName "Function '$func' is exported" -Passed $found -Message $(if (-not $found) { "Function not found in exports" })
    }
}
catch {
    Write-TestResult -TestName "FFU.Core module loads successfully" -Passed $false -Message $_.Exception.Message
}

# =============================================================================
# Test 2: Register-CleanupAction Basic Function
# =============================================================================
Write-Host ""
Write-Host "Testing Register-CleanupAction Function..." -ForegroundColor Yellow

# Clear any existing registry entries
Clear-CleanupRegistry

# Test registering a cleanup action
$testCleanupCalled = $false
try {
    $id = Register-CleanupAction -Name "Test Cleanup" -Action { $script:testCleanupCalled = $true } -ResourceType 'Other'
    $validGuid = [guid]::TryParse($id, [ref]([guid]::Empty))
    Write-TestResult -TestName "Register-CleanupAction returns GUID" -Passed $validGuid -Message "Returned: $id"
}
catch {
    Write-TestResult -TestName "Register-CleanupAction returns GUID" -Passed $false -Message $_.Exception.Message
}

# Test that registry contains the item
$registry = Get-CleanupRegistry
$found = $registry | Where-Object { $_.Name -eq "Test Cleanup" }
Write-TestResult -TestName "Cleanup action appears in registry" -Passed ($null -ne $found)

# =============================================================================
# Test 3: Unregister-CleanupAction Function
# =============================================================================
Write-Host ""
Write-Host "Testing Unregister-CleanupAction Function..." -ForegroundColor Yellow

# Register another action
$id2 = Register-CleanupAction -Name "Test Cleanup 2" -Action { } -ResourceType 'TempFile'

# Unregister it
$result = Unregister-CleanupAction -CleanupId $id2
Write-TestResult -TestName "Unregister-CleanupAction returns true for existing item" -Passed $result

# Verify it's gone
$registry = Get-CleanupRegistry
$notFound = -not ($registry | Where-Object { $_.Id -eq $id2 })
Write-TestResult -TestName "Unregistered item no longer in registry" -Passed $notFound

# Test unregistering non-existent item
$fakeResult = Unregister-CleanupAction -CleanupId "00000000-0000-0000-0000-000000000000"
Write-TestResult -TestName "Unregister-CleanupAction returns false for non-existent item" -Passed (-not $fakeResult)

# =============================================================================
# Test 4: Invoke-FailureCleanup Function
# =============================================================================
Write-Host ""
Write-Host "Testing Invoke-FailureCleanup Function..." -ForegroundColor Yellow

# Clear and set up test
Clear-CleanupRegistry
$script:cleanup1Called = $false
$script:cleanup2Called = $false
$script:cleanupOrder = @()

Register-CleanupAction -Name "First Cleanup" -Action {
    $script:cleanup1Called = $true
    $script:cleanupOrder += "First"
} -ResourceType 'Other'

Register-CleanupAction -Name "Second Cleanup" -Action {
    $script:cleanup2Called = $true
    $script:cleanupOrder += "Second"
} -ResourceType 'Other'

# Invoke cleanup
Invoke-FailureCleanup -Reason "Test failure"

Write-TestResult -TestName "First cleanup action was executed" -Passed $script:cleanup1Called
Write-TestResult -TestName "Second cleanup action was executed" -Passed $script:cleanup2Called
Write-TestResult -TestName "Cleanup executed in LIFO order (Second, First)" -Passed ($script:cleanupOrder[0] -eq "Second" -and $script:cleanupOrder[1] -eq "First")

# Verify registry is cleared after cleanup
$registryAfter = Get-CleanupRegistry
Write-TestResult -TestName "Registry cleared after Invoke-FailureCleanup" -Passed ($registryAfter.Count -eq 0)

# =============================================================================
# Test 5: Clear-CleanupRegistry Function
# =============================================================================
Write-Host ""
Write-Host "Testing Clear-CleanupRegistry Function..." -ForegroundColor Yellow

# Add some items
Register-CleanupAction -Name "Clear Test 1" -Action { } -ResourceType 'VM'
Register-CleanupAction -Name "Clear Test 2" -Action { } -ResourceType 'VHDX'
Register-CleanupAction -Name "Clear Test 3" -Action { } -ResourceType 'ISO'

$beforeClear = (Get-CleanupRegistry).Count
Write-TestResult -TestName "Registry has items before clear" -Passed ($beforeClear -eq 3)

Clear-CleanupRegistry

$afterClear = (Get-CleanupRegistry).Count
Write-TestResult -TestName "Registry empty after Clear-CleanupRegistry" -Passed ($afterClear -eq 0)

# =============================================================================
# Test 6: Specialized Helper Functions
# =============================================================================
Write-Host ""
Write-Host "Testing Specialized Cleanup Helpers..." -ForegroundColor Yellow

Clear-CleanupRegistry

# Test Register-VMCleanup
$vmId = Register-VMCleanup -VMName "TestVM"
$vmEntry = Get-CleanupRegistry | Where-Object { $_.ResourceType -eq 'VM' -and $_.ResourceId -eq 'TestVM' }
Write-TestResult -TestName "Register-VMCleanup creates VM entry" -Passed ($null -ne $vmEntry)

# Test Register-VHDXCleanup
$vhdxId = Register-VHDXCleanup -VHDXPath "C:\Test\test.vhdx"
$vhdxEntry = Get-CleanupRegistry | Where-Object { $_.ResourceType -eq 'VHDX' }
Write-TestResult -TestName "Register-VHDXCleanup creates VHDX entry" -Passed ($null -ne $vhdxEntry)

# Test Register-DISMMountCleanup
$dismId = Register-DISMMountCleanup -MountPath "C:\Test\Mount"
$dismEntry = Get-CleanupRegistry | Where-Object { $_.ResourceType -eq 'DISM' }
Write-TestResult -TestName "Register-DISMMountCleanup creates DISM entry" -Passed ($null -ne $dismEntry)

# Test Register-ISOCleanup
$isoId = Register-ISOCleanup -ISOPath "C:\Test\test.iso"
$isoEntry = Get-CleanupRegistry | Where-Object { $_.ResourceType -eq 'ISO' }
Write-TestResult -TestName "Register-ISOCleanup creates ISO entry" -Passed ($null -ne $isoEntry)

# Test Register-TempFileCleanup
$tempId = Register-TempFileCleanup -Path "C:\Test\TempFolder"
$tempEntry = Get-CleanupRegistry | Where-Object { $_.ResourceType -eq 'TempFile' }
Write-TestResult -TestName "Register-TempFileCleanup creates TempFile entry" -Passed ($null -ne $tempEntry)

# Test Register-NetworkShareCleanup
$shareId = Register-NetworkShareCleanup -ShareName "TestShare"
$shareEntry = Get-CleanupRegistry | Where-Object { $_.ResourceType -eq 'Share' }
Write-TestResult -TestName "Register-NetworkShareCleanup creates Share entry" -Passed ($null -ne $shareEntry)

# Test Register-UserAccountCleanup
$userId = Register-UserAccountCleanup -Username "TestUser"
$userEntry = Get-CleanupRegistry | Where-Object { $_.ResourceType -eq 'User' }
Write-TestResult -TestName "Register-UserAccountCleanup creates User entry" -Passed ($null -ne $userEntry)

# =============================================================================
# Test 7: ResourceType Filtering in Invoke-FailureCleanup
# =============================================================================
Write-Host ""
Write-Host "Testing ResourceType Filtering..." -ForegroundColor Yellow

Clear-CleanupRegistry
$script:vmCleaned = $false
$script:vhdxCleaned = $false

Register-CleanupAction -Name "VM Cleanup" -Action { $script:vmCleaned = $true } -ResourceType 'VM' -ResourceId 'TestVM'
Register-CleanupAction -Name "VHDX Cleanup" -Action { $script:vhdxCleaned = $true } -ResourceType 'VHDX' -ResourceId 'test.vhdx'

# Only cleanup VM type
Invoke-FailureCleanup -Reason "Test" -ResourceType 'VM'

Write-TestResult -TestName "VM cleanup executed when filtering by VM type" -Passed $script:vmCleaned
Write-TestResult -TestName "VHDX cleanup NOT executed when filtering by VM type" -Passed (-not $script:vhdxCleaned)

# Verify VHDX still in registry
$remaining = @(Get-CleanupRegistry)
$vhdxEntries = @($remaining | Where-Object { $_.ResourceType -eq 'VHDX' })
$vhdxStillPresent = $vhdxEntries.Count -gt 0
Write-TestResult -TestName "VHDX entry remains in registry after filtered cleanup" -Passed $vhdxStillPresent -Message "Remaining count: $($remaining.Count), VHDX count: $($vhdxEntries.Count)"

# Clean up remaining
Clear-CleanupRegistry

# =============================================================================
# Test 8: Cleanup Action Error Handling
# =============================================================================
Write-Host ""
Write-Host "Testing Cleanup Error Handling..." -ForegroundColor Yellow

Clear-CleanupRegistry
$script:secondCleanupRan = $false

# Register a cleanup that throws an error
Register-CleanupAction -Name "Failing Cleanup" -Action { throw "Intentional test error" } -ResourceType 'Other'
Register-CleanupAction -Name "Second Cleanup" -Action { $script:secondCleanupRan = $true } -ResourceType 'Other'

# Invoke cleanup - should continue even if first one fails
Invoke-FailureCleanup -Reason "Test error handling"

Write-TestResult -TestName "Second cleanup runs even if first cleanup fails" -Passed $script:secondCleanupRan

Clear-CleanupRegistry

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
    Write-Host "All tests passed!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "Some tests failed. Please review the results above." -ForegroundColor Red
    exit 1
}
