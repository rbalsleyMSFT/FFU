#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for FFU.Core cleanup registry system

.DESCRIPTION
    Comprehensive unit tests covering the cleanup registration system in FFU.Core:
    - Register-CleanupAction: Register cleanup actions with GUID tracking
    - Unregister-CleanupAction: Remove cleanup actions by ID
    - Invoke-FailureCleanup: Execute cleanup actions in LIFO order
    - Clear-CleanupRegistry: Remove all registered actions
    - Get-CleanupRegistry: Retrieve registered entries

    Also tests specialized cleanup registration functions:
    - Register-VMCleanup
    - Register-VHDXCleanup
    - Register-DISMMountCleanup
    - Register-ISOCleanup
    - Register-TempFileCleanup
    - Register-NetworkShareCleanup
    - Register-UserAccountCleanup
    - Register-SensitiveMediaCleanup

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\FFU.Core.Cleanup.Tests.ps1 -Output Detailed
    Filter by tag: Invoke-Pester -Path .\Tests\Unit\FFU.Core.Cleanup.Tests.ps1 -Tag 'TEST-05' -Output Detailed

.EXAMPLE
    # Run all cleanup tests
    Invoke-Pester -Path .\Tests\Unit\FFU.Core.Cleanup.Tests.ps1

.EXAMPLE
    # Run with detailed output
    Invoke-Pester -Path .\Tests\Unit\FFU.Core.Cleanup.Tests.ps1 -Output Detailed
#>

BeforeAll {
    # Get paths relative to test file location
    $TestRoot = Split-Path $PSScriptRoot -Parent
    $ProjectRoot = Split-Path $TestRoot -Parent
    $ModulePath = Join-Path $ProjectRoot 'FFUDevelopment\Modules\FFU.Core'

    # Add modules folder to PSModulePath
    $ModulesFolder = Join-Path $ProjectRoot 'FFUDevelopment\Modules'
    if ($env:PSModulePath -notlike "*$ModulesFolder*") {
        $env:PSModulePath = "$ModulesFolder;$env:PSModulePath"
    }

    # Create global WriteLog stub BEFORE module import
    # FFU.Core functions check for WriteLog and call it if available
    # This stub must exist before import to allow Pester mocking to work
    if (-not (Get-Command WriteLog -ErrorAction SilentlyContinue)) {
        function global:WriteLog {
            param([string]$Message)
        }
    }

    # Remove module if loaded (ensures clean state)
    Get-Module -Name 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue

    # Verify module exists
    if (-not (Test-Path "$ModulePath\FFU.Core.psd1")) {
        throw "FFU.Core module not found at: $ModulePath"
    }

    # Import the module
    Import-Module "$ModulePath\FFU.Core.psd1" -Force -ErrorAction Stop

    # Mock WriteLog to suppress logging noise during tests
    Mock WriteLog { }
}

AfterAll {
    # Cleanup
    Get-Module -Name 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# Register-CleanupAction Tests
# =============================================================================

Describe 'Register-CleanupAction' -Tag 'Unit', 'FFU.Core', 'Cleanup', 'TEST-05' {

    BeforeEach {
        # Reset cleanup registry before each test
        InModuleScope 'FFU.Core' {
            $script:CleanupRegistry.Clear()
        }
    }

    Context 'GUID Format Validation' {
        It 'Should return valid GUID format' {
            $id = Register-CleanupAction -Name "Test Action" -Action { }

            # GUID format: 8-4-4-4-12 hexadecimal characters
            $id | Should -Match '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'
        }

        It 'Should return unique GUID for each registration' {
            $id1 = Register-CleanupAction -Name "Action 1" -Action { }
            $id2 = Register-CleanupAction -Name "Action 2" -Action { }
            $id3 = Register-CleanupAction -Name "Action 3" -Action { }

            $id1 | Should -Not -Be $id2
            $id2 | Should -Not -Be $id3
            $id1 | Should -Not -Be $id3
        }
    }

    Context 'ResourceType Validation' {
        It 'Should accept ResourceType "<ResourceType>"' -ForEach @(
            @{ ResourceType = 'VM' }
            @{ ResourceType = 'VHDX' }
            @{ ResourceType = 'DISM' }
            @{ ResourceType = 'ISO' }
            @{ ResourceType = 'TempFile' }
            @{ ResourceType = 'BITS' }
            @{ ResourceType = 'Share' }
            @{ ResourceType = 'User' }
            @{ ResourceType = 'Other' }
        ) {
            $id = Register-CleanupAction -Name "Test $ResourceType" -ResourceType $ResourceType -Action { }
            $id | Should -Not -BeNullOrEmpty
        }

        It 'Should use "Other" as default ResourceType' {
            $id = Register-CleanupAction -Name "Default Type" -Action { }

            $entry = InModuleScope 'FFU.Core' {
                $script:CleanupRegistry | Where-Object { $_.Name -eq "Default Type" }
            }

            $entry.ResourceType | Should -Be 'Other'
        }
    }

    Context 'ResourceId Storage' {
        It 'Should store ResourceId when provided' {
            $id = Register-CleanupAction -Name "VM Cleanup" -ResourceType "VM" -ResourceId "FFU_Build_VM" -Action { }

            # Access entry by Name since we know it's unique in this test
            $entry = InModuleScope 'FFU.Core' {
                $script:CleanupRegistry | Where-Object { $_.Name -eq "VM Cleanup" }
            }

            $entry.ResourceId | Should -Be 'FFU_Build_VM'
        }

        It 'Should store empty ResourceId when not provided' {
            $id = Register-CleanupAction -Name "No Resource ID" -Action { }

            $entry = InModuleScope 'FFU.Core' {
                $script:CleanupRegistry | Where-Object { $_.Name -eq "No Resource ID" }
            }

            $entry.ResourceId | Should -Be ''
        }
    }

    Context 'Registry Count' {
        It 'Should increment registry count after registration' {
            $beforeCount = InModuleScope 'FFU.Core' { $script:CleanupRegistry.Count }

            Register-CleanupAction -Name "Action 1" -Action { }

            $afterCount = InModuleScope 'FFU.Core' { $script:CleanupRegistry.Count }

            $afterCount | Should -Be ($beforeCount + 1)
        }

        It 'Should increment for multiple registrations' {
            Register-CleanupAction -Name "Action 1" -Action { }
            Register-CleanupAction -Name "Action 2" -Action { }
            Register-CleanupAction -Name "Action 3" -Action { }

            $count = InModuleScope 'FFU.Core' { $script:CleanupRegistry.Count }

            $count | Should -Be 3
        }
    }

    Context 'Action ScriptBlock Storage' {
        It 'Should store Action scriptblock correctly' {
            $testAction = { Write-Output "Test Cleanup" }
            $id = Register-CleanupAction -Name "Script Test" -Action $testAction

            $entry = InModuleScope 'FFU.Core' {
                $script:CleanupRegistry | Where-Object { $_.Name -eq "Script Test" }
            }

            $entry.Action | Should -BeOfType [scriptblock]
        }
    }
}

# =============================================================================
# Unregister-CleanupAction Tests
# =============================================================================

Describe 'Unregister-CleanupAction' -Tag 'Unit', 'FFU.Core', 'Cleanup', 'TEST-05' {

    BeforeEach {
        # Reset cleanup registry before each test
        InModuleScope 'FFU.Core' {
            $script:CleanupRegistry.Clear()
        }
    }

    Context 'Successful Unregistration' {
        It 'Should return $true when entry exists and is removed' {
            $id = Register-CleanupAction -Name "To Remove" -Action { }

            $result = Unregister-CleanupAction -CleanupId $id

            $result | Should -BeTrue
        }

        It 'Should actually remove the entry from registry' {
            $id = Register-CleanupAction -Name "To Remove" -Action { }

            Unregister-CleanupAction -CleanupId $id | Out-Null

            $entry = InModuleScope 'FFU.Core' {
                $script:CleanupRegistry | Where-Object { $_.Id -eq $args[0] }
            } -ArgumentList $id

            $entry | Should -BeNullOrEmpty
        }
    }

    Context 'Failed Unregistration' {
        It 'Should return $false for non-existent ID' {
            $result = Unregister-CleanupAction -CleanupId 'non-existent-guid-12345'

            $result | Should -BeFalse
        }

        It 'Should return $false when called twice with same ID' {
            $id = Register-CleanupAction -Name "Remove Once" -Action { }

            $firstResult = Unregister-CleanupAction -CleanupId $id
            $secondResult = Unregister-CleanupAction -CleanupId $id

            $firstResult | Should -BeTrue
            $secondResult | Should -BeFalse
        }
    }

    Context 'Registry Count After Removal' {
        It 'Should decrement registry count after removal' {
            Register-CleanupAction -Name "Action 1" -Action { }
            $id2 = Register-CleanupAction -Name "Action 2" -Action { }
            Register-CleanupAction -Name "Action 3" -Action { }

            $beforeCount = InModuleScope 'FFU.Core' { $script:CleanupRegistry.Count }

            Unregister-CleanupAction -CleanupId $id2 | Out-Null

            $afterCount = InModuleScope 'FFU.Core' { $script:CleanupRegistry.Count }

            $afterCount | Should -Be ($beforeCount - 1)
        }
    }
}

# =============================================================================
# Invoke-FailureCleanup Tests
# =============================================================================

Describe 'Invoke-FailureCleanup' -Tag 'Unit', 'FFU.Core', 'Cleanup', 'TEST-05' {

    BeforeEach {
        # Reset cleanup registry before each test
        InModuleScope 'FFU.Core' {
            $script:CleanupRegistry.Clear()
        }
    }

    Context 'Action Execution' {
        It 'Should execute all registered actions' {
            $script:executionCount = 0
            Register-CleanupAction -Name "Action 1" -Action { $script:executionCount++ }
            Register-CleanupAction -Name "Action 2" -Action { $script:executionCount++ }
            Register-CleanupAction -Name "Action 3" -Action { $script:executionCount++ }

            Invoke-FailureCleanup -Reason "Test execution"

            $script:executionCount | Should -Be 3
        }

        It 'Should not throw when no actions registered' {
            { Invoke-FailureCleanup -Reason "Empty registry" } | Should -Not -Throw
        }
    }

    Context 'LIFO Execution Order' {
        It 'Should execute in LIFO order (last registered first)' {
            $script:executionOrder = [System.Collections.ArrayList]::new()

            Register-CleanupAction -Name "First" -Action { $script:executionOrder.Add('First') | Out-Null }
            Register-CleanupAction -Name "Second" -Action { $script:executionOrder.Add('Second') | Out-Null }
            Register-CleanupAction -Name "Third" -Action { $script:executionOrder.Add('Third') | Out-Null }

            Invoke-FailureCleanup -Reason "Test order"

            $script:executionOrder[0] | Should -Be 'Third'
            $script:executionOrder[1] | Should -Be 'Second'
            $script:executionOrder[2] | Should -Be 'First'
        }
    }

    Context 'Error Resilience' {
        It 'Should continue after cleanup action throws exception' {
            $script:actionsExecuted = [System.Collections.ArrayList]::new()

            Register-CleanupAction -Name "First (succeeds)" -Action { $script:actionsExecuted.Add('First') | Out-Null }
            Register-CleanupAction -Name "Second (fails)" -Action { throw "Cleanup error" }
            Register-CleanupAction -Name "Third (succeeds)" -Action { $script:actionsExecuted.Add('Third') | Out-Null }

            Invoke-FailureCleanup -Reason "Test error handling"

            # Third executed first (LIFO), then Second fails, then First should still execute
            $script:actionsExecuted | Should -Contain 'First'
            $script:actionsExecuted | Should -Contain 'Third'
        }

        It 'Should not throw when cleanup action fails' {
            Register-CleanupAction -Name "Failing action" -Action { throw "Cleanup failed" }

            { Invoke-FailureCleanup -Reason "Test no throw" } | Should -Not -Throw
        }
    }

    Context 'ResourceType Filtering' {
        It 'Should filter by ResourceType when specified' {
            $script:vmCleaned = $false
            $script:diskCleaned = $false
            $script:isoCleaned = $false

            Register-CleanupAction -Name "VM" -ResourceType 'VM' -Action { $script:vmCleaned = $true }
            Register-CleanupAction -Name "Disk" -ResourceType 'VHDX' -Action { $script:diskCleaned = $true }
            Register-CleanupAction -Name "ISO" -ResourceType 'ISO' -Action { $script:isoCleaned = $true }

            Invoke-FailureCleanup -Reason "Filter test" -ResourceType 'VM'

            $script:vmCleaned | Should -BeTrue
            $script:diskCleaned | Should -BeFalse
            $script:isoCleaned | Should -BeFalse
        }

        It 'Should execute all types when ResourceType is "All"' {
            $script:allExecuted = [System.Collections.ArrayList]::new()

            Register-CleanupAction -Name "VM" -ResourceType 'VM' -Action { $script:allExecuted.Add('VM') | Out-Null }
            Register-CleanupAction -Name "VHDX" -ResourceType 'VHDX' -Action { $script:allExecuted.Add('VHDX') | Out-Null }
            Register-CleanupAction -Name "DISM" -ResourceType 'DISM' -Action { $script:allExecuted.Add('DISM') | Out-Null }

            Invoke-FailureCleanup -Reason "All types" -ResourceType 'All'

            $script:allExecuted.Count | Should -Be 3
        }

        It 'Should default to "All" ResourceTypes when not specified' {
            $script:executionCount = 0

            Register-CleanupAction -Name "VM" -ResourceType 'VM' -Action { $script:executionCount++ }
            Register-CleanupAction -Name "VHDX" -ResourceType 'VHDX' -Action { $script:executionCount++ }

            Invoke-FailureCleanup -Reason "Default all"

            $script:executionCount | Should -Be 2
        }
    }

    Context 'Registry State After Cleanup' {
        It 'Should remove successful cleanups from registry' {
            Register-CleanupAction -Name "Succeeds" -Action { }

            $beforeCount = InModuleScope 'FFU.Core' { $script:CleanupRegistry.Count }

            Invoke-FailureCleanup -Reason "Test removal"

            $afterCount = InModuleScope 'FFU.Core' { $script:CleanupRegistry.Count }

            $beforeCount | Should -Be 1
            $afterCount | Should -Be 0
        }

        It 'Should keep failed cleanups in registry' {
            Register-CleanupAction -Name "Fails" -Action { throw "Error" }

            Invoke-FailureCleanup -Reason "Test retention"

            $count = InModuleScope 'FFU.Core' { $script:CleanupRegistry.Count }

            $count | Should -Be 1
        }
    }
}

# =============================================================================
# Clear-CleanupRegistry Tests
# =============================================================================

Describe 'Clear-CleanupRegistry' -Tag 'Unit', 'FFU.Core', 'Cleanup', 'TEST-05' {

    BeforeEach {
        # Reset cleanup registry before each test
        InModuleScope 'FFU.Core' {
            $script:CleanupRegistry.Clear()
        }
    }

    Context 'Clearing Registry' {
        It 'Should remove all entries' {
            Register-CleanupAction -Name "Action 1" -Action { }
            Register-CleanupAction -Name "Action 2" -Action { }
            Register-CleanupAction -Name "Action 3" -Action { }

            Clear-CleanupRegistry

            $count = InModuleScope 'FFU.Core' { $script:CleanupRegistry.Count }

            $count | Should -Be 0
        }

        It 'Should have registry count of 0 after clear' {
            Register-CleanupAction -Name "Action 1" -Action { }

            Clear-CleanupRegistry

            $registry = Get-CleanupRegistry
            @($registry).Count | Should -Be 0
        }

        It 'Should not throw when registry is already empty' {
            { Clear-CleanupRegistry } | Should -Not -Throw
        }
    }
}

# =============================================================================
# Get-CleanupRegistry Tests
# =============================================================================

Describe 'Get-CleanupRegistry' -Tag 'Unit', 'FFU.Core', 'Cleanup', 'TEST-05' {

    BeforeEach {
        # Reset cleanup registry before each test
        InModuleScope 'FFU.Core' {
            $script:CleanupRegistry.Clear()
        }
    }

    Context 'Empty Registry' {
        It 'Should return empty array when no entries' {
            $registry = Get-CleanupRegistry

            @($registry).Count | Should -Be 0
        }
    }

    Context 'Populated Registry' {
        It 'Should return array of registered entries' {
            Register-CleanupAction -Name "Action 1" -Action { }
            Register-CleanupAction -Name "Action 2" -Action { }

            $registry = Get-CleanupRegistry

            @($registry).Count | Should -Be 2
        }

        It 'Should return entries with expected properties' {
            $id = Register-CleanupAction -Name "Test Entry" -ResourceType "VM" -ResourceId "TestVM" -Action { }

            $registry = Get-CleanupRegistry
            $entry = $registry | Where-Object { $_.Id -eq $id }

            $entry.Id | Should -Not -BeNullOrEmpty
            $entry.Name | Should -Be "Test Entry"
            $entry.ResourceType | Should -Be "VM"
            $entry.ResourceId | Should -Be "TestVM"
            $entry.Action | Should -Not -BeNullOrEmpty
            $entry.RegisteredAt | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Specialized Cleanup Registration Functions Tests
# =============================================================================

Describe 'Register-VMCleanup' -Tag 'Unit', 'FFU.Core', 'Cleanup', 'TEST-05' {

    BeforeEach {
        InModuleScope 'FFU.Core' {
            $script:CleanupRegistry.Clear()
        }
    }

    It 'Should register with ResourceType "VM"' {
        $id = Register-VMCleanup -VMName "TestVM"

        $entry = InModuleScope 'FFU.Core' {
            $script:CleanupRegistry | Where-Object { $_.ResourceType -eq 'VM' }
        }

        $entry | Should -Not -BeNullOrEmpty
        $entry.ResourceType | Should -Be 'VM'
    }

    It 'Should store VMName as ResourceId' {
        $id = Register-VMCleanup -VMName "FFU_Build_VM"

        $entry = InModuleScope 'FFU.Core' {
            $script:CleanupRegistry | Where-Object { $_.ResourceType -eq 'VM' }
        }

        $entry.ResourceId | Should -Be 'FFU_Build_VM'
    }

    It 'Should return valid GUID' {
        $id = Register-VMCleanup -VMName "TestVM"

        $id | Should -Match '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'
    }
}

Describe 'Register-VHDXCleanup' -Tag 'Unit', 'FFU.Core', 'Cleanup', 'TEST-05' {

    BeforeEach {
        InModuleScope 'FFU.Core' {
            $script:CleanupRegistry.Clear()
        }
    }

    It 'Should register with ResourceType "VHDX"' {
        $id = Register-VHDXCleanup -VHDXPath "C:\VMs\Test\disk.vhdx"

        $entry = InModuleScope 'FFU.Core' {
            $script:CleanupRegistry | Where-Object { $_.ResourceType -eq 'VHDX' }
        }

        $entry | Should -Not -BeNullOrEmpty
        $entry.ResourceType | Should -Be 'VHDX'
    }

    It 'Should store VHDXPath as ResourceId' {
        $id = Register-VHDXCleanup -VHDXPath "C:\VMs\FFU_Build\disk.vhdx"

        $entry = InModuleScope 'FFU.Core' {
            $script:CleanupRegistry | Where-Object { $_.ResourceType -eq 'VHDX' }
        }

        $entry.ResourceId | Should -Be 'C:\VMs\FFU_Build\disk.vhdx'
    }
}

Describe 'Register-DISMMountCleanup' -Tag 'Unit', 'FFU.Core', 'Cleanup', 'TEST-05' {

    BeforeEach {
        InModuleScope 'FFU.Core' {
            $script:CleanupRegistry.Clear()
        }
    }

    It 'Should register with ResourceType "DISM"' {
        $id = Register-DISMMountCleanup -MountPath "C:\Mount\WinPE"

        $entry = InModuleScope 'FFU.Core' {
            $script:CleanupRegistry | Where-Object { $_.ResourceType -eq 'DISM' }
        }

        $entry | Should -Not -BeNullOrEmpty
        $entry.ResourceType | Should -Be 'DISM'
    }

    It 'Should store MountPath as ResourceId' {
        $id = Register-DISMMountCleanup -MountPath "C:\Mount\WinImage"

        $entry = InModuleScope 'FFU.Core' {
            $script:CleanupRegistry | Where-Object { $_.ResourceType -eq 'DISM' }
        }

        $entry.ResourceId | Should -Be 'C:\Mount\WinImage'
    }
}

Describe 'Register-ISOCleanup' -Tag 'Unit', 'FFU.Core', 'Cleanup', 'TEST-05' {

    BeforeEach {
        InModuleScope 'FFU.Core' {
            $script:CleanupRegistry.Clear()
        }
    }

    It 'Should register with ResourceType "ISO"' {
        $id = Register-ISOCleanup -ISOPath "C:\ISOs\Windows11.iso"

        $entry = InModuleScope 'FFU.Core' {
            $script:CleanupRegistry | Where-Object { $_.ResourceType -eq 'ISO' }
        }

        $entry | Should -Not -BeNullOrEmpty
        $entry.ResourceType | Should -Be 'ISO'
    }

    It 'Should store ISOPath as ResourceId' {
        $id = Register-ISOCleanup -ISOPath "D:\Images\Win11_23H2.iso"

        $entry = InModuleScope 'FFU.Core' {
            $script:CleanupRegistry | Where-Object { $_.ResourceType -eq 'ISO' }
        }

        $entry.ResourceId | Should -Be 'D:\Images\Win11_23H2.iso'
    }
}

Describe 'Register-TempFileCleanup' -Tag 'Unit', 'FFU.Core', 'Cleanup', 'TEST-05' {

    BeforeEach {
        InModuleScope 'FFU.Core' {
            $script:CleanupRegistry.Clear()
        }
    }

    It 'Should register with ResourceType "TempFile"' {
        $id = Register-TempFileCleanup -Path "C:\Temp\build.tmp"

        $entry = InModuleScope 'FFU.Core' {
            $script:CleanupRegistry | Where-Object { $_.ResourceType -eq 'TempFile' }
        }

        $entry | Should -Not -BeNullOrEmpty
        $entry.ResourceType | Should -Be 'TempFile'
    }

    It 'Should store Path as ResourceId' {
        $id = Register-TempFileCleanup -Path "C:\Temp\scratch\file.dat"

        $entry = InModuleScope 'FFU.Core' {
            $script:CleanupRegistry | Where-Object { $_.ResourceType -eq 'TempFile' }
        }

        $entry.ResourceId | Should -Be 'C:\Temp\scratch\file.dat'
    }

    It 'Should handle -Recurse switch for directory cleanup' {
        $id = Register-TempFileCleanup -Path "C:\Temp\BuildFolder" -Recurse

        $entry = InModuleScope 'FFU.Core' {
            $script:CleanupRegistry | Where-Object { $_.ResourceType -eq 'TempFile' }
        }

        # Name should indicate directory
        $entry.Name | Should -Match 'directory'
    }
}

Describe 'Register-NetworkShareCleanup' -Tag 'Unit', 'FFU.Core', 'Cleanup', 'TEST-05' {

    BeforeEach {
        InModuleScope 'FFU.Core' {
            $script:CleanupRegistry.Clear()
        }
    }

    It 'Should register with ResourceType "Share"' {
        $id = Register-NetworkShareCleanup -ShareName "FFUShare"

        $entry = InModuleScope 'FFU.Core' {
            $script:CleanupRegistry | Where-Object { $_.ResourceType -eq 'Share' }
        }

        $entry | Should -Not -BeNullOrEmpty
        $entry.ResourceType | Should -Be 'Share'
    }

    It 'Should store ShareName as ResourceId' {
        $id = Register-NetworkShareCleanup -ShareName "BuildShare$"

        $entry = InModuleScope 'FFU.Core' {
            $script:CleanupRegistry | Where-Object { $_.ResourceType -eq 'Share' }
        }

        $entry.ResourceId | Should -Be 'BuildShare$'
    }
}

Describe 'Register-UserAccountCleanup' -Tag 'Unit', 'FFU.Core', 'Cleanup', 'TEST-05' {

    BeforeEach {
        InModuleScope 'FFU.Core' {
            $script:CleanupRegistry.Clear()
        }
    }

    It 'Should register with ResourceType "User"' {
        $id = Register-UserAccountCleanup -Username "FFUBuildUser"

        $entry = InModuleScope 'FFU.Core' {
            $script:CleanupRegistry | Where-Object { $_.ResourceType -eq 'User' }
        }

        $entry | Should -Not -BeNullOrEmpty
        $entry.ResourceType | Should -Be 'User'
    }

    It 'Should store Username as ResourceId' {
        $id = Register-UserAccountCleanup -Username "vmbuildaccount"

        $entry = InModuleScope 'FFU.Core' {
            $script:CleanupRegistry | Where-Object { $_.ResourceType -eq 'User' }
        }

        $entry.ResourceId | Should -Be 'vmbuildaccount'
    }
}

Describe 'Register-SensitiveMediaCleanup' -Tag 'Unit', 'FFU.Core', 'Cleanup', 'TEST-05' {

    BeforeEach {
        InModuleScope 'FFU.Core' {
            $script:CleanupRegistry.Clear()
        }
    }

    It 'Should register with ResourceType "TempFile"' {
        $id = Register-SensitiveMediaCleanup -FFUDevelopmentPath "C:\FFUDevelopment"

        $entry = InModuleScope 'FFU.Core' {
            $script:CleanupRegistry | Where-Object { $_.ResourceType -eq 'TempFile' }
        }

        $entry | Should -Not -BeNullOrEmpty
        $entry.ResourceType | Should -Be 'TempFile'
    }

    It 'Should store "CaptureFFU-Backups" as ResourceId' {
        $id = Register-SensitiveMediaCleanup -FFUDevelopmentPath "C:\FFUDevelopment"

        $entry = InModuleScope 'FFU.Core' {
            $script:CleanupRegistry | Where-Object { $_.ResourceId -eq 'CaptureFFU-Backups' }
        }

        $entry | Should -Not -BeNullOrEmpty
        $entry.ResourceId | Should -Be 'CaptureFFU-Backups'
    }
}
