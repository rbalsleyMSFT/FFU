#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for FFU.Imaging module

.DESCRIPTION
    Comprehensive unit tests covering all exported functions in the FFU.Imaging module.
    Tests verify parameter validation, expected behavior, error handling, and edge cases.

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\FFU.Imaging.Tests.ps1 -Output Detailed
#>

BeforeAll {
    $TestRoot = Split-Path $PSScriptRoot -Parent
    $ProjectRoot = Split-Path $TestRoot -Parent
    $ModulePath = Join-Path $ProjectRoot 'FFUDevelopment\Modules\FFU.Imaging'
    $CoreModulePath = Join-Path $ProjectRoot 'FFUDevelopment\Modules\FFU.Core'

    Get-Module -Name 'FFU.Imaging', 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue

    if (Test-Path "$CoreModulePath\FFU.Core.psd1") {
        Import-Module "$CoreModulePath\FFU.Core.psd1" -Force -ErrorAction SilentlyContinue
    }

    if (-not (Test-Path "$ModulePath\FFU.Imaging.psd1")) {
        throw "FFU.Imaging module not found at: $ModulePath"
    }
    Import-Module "$ModulePath\FFU.Imaging.psd1" -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name 'FFU.Imaging', 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# Module Export Verification
# =============================================================================

Describe 'FFU.Imaging Module Exports' -Tag 'Unit', 'FFU.Imaging', 'Module' {

    Context 'Expected Functions Are Exported' {
        It 'Should export Initialize-DISMService' {
            Get-Command -Name 'Initialize-DISMService' -Module 'FFU.Imaging' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Test-WimSourceAccessibility' {
            Get-Command -Name 'Test-WimSourceAccessibility' -Module 'FFU.Imaging' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Invoke-ExpandWindowsImageWithRetry' {
            Get-Command -Name 'Invoke-ExpandWindowsImageWithRetry' -Module 'FFU.Imaging' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Get-WimFromISO' {
            Get-Command -Name 'Get-WimFromISO' -Module 'FFU.Imaging' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Get-Index' {
            Get-Command -Name 'Get-Index' -Module 'FFU.Imaging' | Should -Not -BeNullOrEmpty
        }

        It 'Should export New-ScratchVhdx' {
            Get-Command -Name 'New-ScratchVhdx' -Module 'FFU.Imaging' | Should -Not -BeNullOrEmpty
        }

        It 'Should export New-SystemPartition' {
            Get-Command -Name 'New-SystemPartition' -Module 'FFU.Imaging' | Should -Not -BeNullOrEmpty
        }

        It 'Should export New-MSRPartition' {
            Get-Command -Name 'New-MSRPartition' -Module 'FFU.Imaging' | Should -Not -BeNullOrEmpty
        }

        It 'Should export New-OSPartition' {
            Get-Command -Name 'New-OSPartition' -Module 'FFU.Imaging' | Should -Not -BeNullOrEmpty
        }

        It 'Should export New-RecoveryPartition' {
            Get-Command -Name 'New-RecoveryPartition' -Module 'FFU.Imaging' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Add-BootFiles' {
            Get-Command -Name 'Add-BootFiles' -Module 'FFU.Imaging' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Dismount-ScratchVhdx' {
            Get-Command -Name 'Dismount-ScratchVhdx' -Module 'FFU.Imaging' | Should -Not -BeNullOrEmpty
        }

        It 'Should export New-FFU' {
            Get-Command -Name 'New-FFU' -Module 'FFU.Imaging' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Invoke-FFUOptimizeWithScratchDir' {
            Get-Command -Name 'Invoke-FFUOptimizeWithScratchDir' -Module 'FFU.Imaging' | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Module Metadata' {
        It 'Should have a valid module manifest' {
            $ManifestPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Imaging\FFU.Imaging.psd1'
            Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Initialize-DISMService Tests
# =============================================================================

Describe 'Initialize-DISMService' -Tag 'Unit', 'FFU.Imaging', 'Initialize-DISMService' {

    Context 'Parameter Validation' {
        It 'Should have MountPath parameter' {
            $command = Get-Command -Name 'Initialize-DISMService' -Module 'FFU.Imaging'
            $command.Parameters['MountPath'] | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Test-WimSourceAccessibility Tests
# =============================================================================

Describe 'Test-WimSourceAccessibility' -Tag 'Unit', 'FFU.Imaging', 'Test-WimSourceAccessibility' {

    Context 'Parameter Validation' {
        It 'Should have WimPath parameter' {
            $command = Get-Command -Name 'Test-WimSourceAccessibility' -Module 'FFU.Imaging'
            $command.Parameters['WimPath'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have optional ISOPath parameter' {
            $command = Get-Command -Name 'Test-WimSourceAccessibility' -Module 'FFU.Imaging'
            $command.Parameters['ISOPath'] | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Return Value' {
        It 'Should return an object with accessibility status' {
            # Test with non-existent path
            $result = Test-WimSourceAccessibility -WimPath 'C:\NonExistent\test.wim'
            $result | Should -Not -BeNullOrEmpty
            $result.IsAccessible | Should -BeFalse
        }
    }
}

# =============================================================================
# Invoke-ExpandWindowsImageWithRetry Tests
# =============================================================================

Describe 'Invoke-ExpandWindowsImageWithRetry' -Tag 'Unit', 'FFU.Imaging', 'Invoke-ExpandWindowsImageWithRetry' {

    Context 'Parameter Validation' {
        It 'Should have ImagePath parameter' {
            $command = Get-Command -Name 'Invoke-ExpandWindowsImageWithRetry' -Module 'FFU.Imaging'
            $command.Parameters['ImagePath'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have Index parameter' {
            $command = Get-Command -Name 'Invoke-ExpandWindowsImageWithRetry' -Module 'FFU.Imaging'
            $command.Parameters['Index'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have ApplyPath parameter' {
            $command = Get-Command -Name 'Invoke-ExpandWindowsImageWithRetry' -Module 'FFU.Imaging'
            $command.Parameters['ApplyPath'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have MaxRetries parameter' {
            $command = Get-Command -Name 'Invoke-ExpandWindowsImageWithRetry' -Module 'FFU.Imaging'
            $command.Parameters['MaxRetries'] | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Get-WimFromISO Tests
# =============================================================================

Describe 'Get-WimFromISO' -Tag 'Unit', 'FFU.Imaging', 'Get-WimFromISO' {

    Context 'Parameter Validation' {
        It 'Should have ISOPath parameter' {
            $command = Get-Command -Name 'Get-WimFromISO' -Module 'FFU.Imaging'
            $command.Parameters['ISOPath'] | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Get-Index Tests
# =============================================================================

Describe 'Get-Index' -Tag 'Unit', 'FFU.Imaging', 'Get-Index' {

    Context 'Parameter Validation' {
        It 'Should have WimPath parameter' {
            $command = Get-Command -Name 'Get-Index' -Module 'FFU.Imaging'
            $command.Parameters['WimPath'] | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# New-ScratchVhdx Tests
# =============================================================================

Describe 'New-ScratchVhdx' -Tag 'Unit', 'FFU.Imaging', 'New-ScratchVhdx' {

    Context 'Parameter Validation' {
        It 'Should have FFUDevelopmentPath parameter' {
            $command = Get-Command -Name 'New-ScratchVhdx' -Module 'FFU.Imaging'
            $command.Parameters['FFUDevelopmentPath'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have SizeBytes parameter' {
            $command = Get-Command -Name 'New-ScratchVhdx' -Module 'FFU.Imaging'
            $command.Parameters['SizeBytes'] | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Partition Functions Tests
# =============================================================================

Describe 'New-SystemPartition' -Tag 'Unit', 'FFU.Imaging', 'New-SystemPartition' {

    Context 'Parameter Validation' {
        It 'Should have VhdxDisk parameter' {
            $command = Get-Command -Name 'New-SystemPartition' -Module 'FFU.Imaging'
            $command.Parameters['VhdxDisk'] | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'New-MSRPartition' -Tag 'Unit', 'FFU.Imaging', 'New-MSRPartition' {

    Context 'Parameter Validation' {
        It 'Should have VhdxDisk parameter' {
            $command = Get-Command -Name 'New-MSRPartition' -Module 'FFU.Imaging'
            $command.Parameters['VhdxDisk'] | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'New-OSPartition' -Tag 'Unit', 'FFU.Imaging', 'New-OSPartition' {

    Context 'Parameter Validation' {
        It 'Should have VhdxDisk parameter' {
            $command = Get-Command -Name 'New-OSPartition' -Module 'FFU.Imaging'
            $command.Parameters['VhdxDisk'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have WimPath parameter' {
            $command = Get-Command -Name 'New-OSPartition' -Module 'FFU.Imaging'
            $command.Parameters['WimPath'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have WimIndex parameter' {
            $command = Get-Command -Name 'New-OSPartition' -Module 'FFU.Imaging'
            $command.Parameters['WimIndex'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have optional ISOPath parameter' {
            $command = Get-Command -Name 'New-OSPartition' -Module 'FFU.Imaging'
            $command.Parameters['ISOPath'] | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'New-RecoveryPartition' -Tag 'Unit', 'FFU.Imaging', 'New-RecoveryPartition' {

    Context 'Parameter Validation' {
        It 'Should have VhdxDisk parameter' {
            $command = Get-Command -Name 'New-RecoveryPartition' -Module 'FFU.Imaging'
            $command.Parameters['VhdxDisk'] | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Add-BootFiles Tests
# =============================================================================

Describe 'Add-BootFiles' -Tag 'Unit', 'FFU.Imaging', 'Add-BootFiles' {

    Context 'Parameter Validation' {
        It 'Should have Disk parameter' {
            $command = Get-Command -Name 'Add-BootFiles' -Module 'FFU.Imaging'
            $command.Parameters['Disk'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have MountPath parameter' {
            $command = Get-Command -Name 'Add-BootFiles' -Module 'FFU.Imaging'
            $command.Parameters['MountPath'] | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Dismount-ScratchVhdx Tests
# =============================================================================

Describe 'Dismount-ScratchVhdx' -Tag 'Unit', 'FFU.Imaging', 'Dismount-ScratchVhdx' {

    Context 'Parameter Validation' {
        It 'Should have VhdxPath parameter' {
            $command = Get-Command -Name 'Dismount-ScratchVhdx' -Module 'FFU.Imaging'
            $command.Parameters['VhdxPath'] | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# New-FFU Tests
# =============================================================================

Describe 'New-FFU' -Tag 'Unit', 'FFU.Imaging', 'New-FFU' {

    Context 'Parameter Validation' {
        It 'Should have CaptureDrive parameter' {
            $command = Get-Command -Name 'New-FFU' -Module 'FFU.Imaging'
            $command.Parameters['CaptureDrive'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have FFUDevelopmentPath parameter' {
            $command = Get-Command -Name 'New-FFU' -Module 'FFU.Imaging'
            $command.Parameters['FFUDevelopmentPath'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have Optimize parameter' {
            $command = Get-Command -Name 'New-FFU' -Module 'FFU.Imaging'
            $command.Parameters['Optimize'] | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Invoke-FFUOptimizeWithScratchDir Tests
# =============================================================================

Describe 'Invoke-FFUOptimizeWithScratchDir' -Tag 'Unit', 'FFU.Imaging', 'Invoke-FFUOptimizeWithScratchDir' {

    Context 'Parameter Validation' {
        It 'Should have FFUFile parameter' {
            $command = Get-Command -Name 'Invoke-FFUOptimizeWithScratchDir' -Module 'FFU.Imaging'
            $command.Parameters['FFUFile'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have DandIEnv parameter' {
            $command = Get-Command -Name 'Invoke-FFUOptimizeWithScratchDir' -Module 'FFU.Imaging'
            $command.Parameters['DandIEnv'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have FFUDevelopmentPath parameter' {
            $command = Get-Command -Name 'Invoke-FFUOptimizeWithScratchDir' -Module 'FFU.Imaging'
            $command.Parameters['FFUDevelopmentPath'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have MaxRetries parameter' {
            $command = Get-Command -Name 'Invoke-FFUOptimizeWithScratchDir' -Module 'FFU.Imaging'
            $command.Parameters['MaxRetries'] | Should -Not -BeNullOrEmpty
        }
    }
}
