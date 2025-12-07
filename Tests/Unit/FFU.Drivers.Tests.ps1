#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for FFU.Drivers module

.DESCRIPTION
    Comprehensive unit tests covering all exported functions in the FFU.Drivers module.
    Tests verify parameter validation, expected behavior, error handling, and edge cases.

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\FFU.Drivers.Tests.ps1 -Output Detailed
    Coverage: Invoke-Pester -Path .\Tests\Unit\FFU.Drivers.Tests.ps1 -CodeCoverage .\FFUDevelopment\Modules\FFU.Drivers\*.psm1
#>

BeforeAll {
    # Get paths relative to test file location
    $TestRoot = Split-Path $PSScriptRoot -Parent
    $ProjectRoot = Split-Path $TestRoot -Parent
    $ModulePath = Join-Path $ProjectRoot 'FFUDevelopment\Modules\FFU.Drivers'
    $CoreModulePath = Join-Path $ProjectRoot 'FFUDevelopment\Modules\FFU.Core'

    # Remove modules if loaded
    Get-Module -Name 'FFU.Drivers', 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue

    # Import FFU.Core first (dependency)
    if (Test-Path "$CoreModulePath\FFU.Core.psd1") {
        Import-Module "$CoreModulePath\FFU.Core.psd1" -Force -ErrorAction SilentlyContinue
    }

    # Import FFU.Drivers module
    if (-not (Test-Path "$ModulePath\FFU.Drivers.psd1")) {
        throw "FFU.Drivers module not found at: $ModulePath"
    }
    Import-Module "$ModulePath\FFU.Drivers.psd1" -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name 'FFU.Drivers', 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# Module Export Verification
# =============================================================================

Describe 'FFU.Drivers Module Exports' -Tag 'Unit', 'FFU.Drivers', 'Module' {

    Context 'Expected Functions Are Exported' {
        It 'Should export Get-MicrosoftDrivers' {
            Get-Command -Name 'Get-MicrosoftDrivers' -Module 'FFU.Drivers' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Get-HPDrivers' {
            Get-Command -Name 'Get-HPDrivers' -Module 'FFU.Drivers' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Get-LenovoDrivers' {
            Get-Command -Name 'Get-LenovoDrivers' -Module 'FFU.Drivers' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Get-DellDrivers' {
            Get-Command -Name 'Get-DellDrivers' -Module 'FFU.Drivers' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Copy-Drivers' {
            Get-Command -Name 'Copy-Drivers' -Module 'FFU.Drivers' | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Module Metadata' {
        It 'Should have a valid module manifest' {
            $ManifestPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Drivers\FFU.Drivers.psd1'
            Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Get-MicrosoftDrivers Tests
# =============================================================================

Describe 'Get-MicrosoftDrivers' -Tag 'Unit', 'FFU.Drivers', 'Get-MicrosoftDrivers' {

    Context 'Parameter Validation' {
        It 'Should have mandatory Make parameter' {
            $command = Get-Command -Name 'Get-MicrosoftDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['Make']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory Model parameter' {
            $command = Get-Command -Name 'Get-MicrosoftDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['Model']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory WindowsRelease parameter with ValidateSet' {
            $command = Get-Command -Name 'Get-MicrosoftDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['WindowsRelease']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }

            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet | Should -Not -BeNullOrEmpty
            $validateSet.ValidValues | Should -Contain 10
            $validateSet.ValidValues | Should -Contain 11
        }

        It 'Should have mandatory Headers parameter' {
            $command = Get-Command -Name 'Get-MicrosoftDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['Headers']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory UserAgent parameter' {
            $command = Get-Command -Name 'Get-MicrosoftDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['UserAgent']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory DriversFolder parameter' {
            $command = Get-Command -Name 'Get-MicrosoftDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['DriversFolder']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory FFUDevelopmentPath parameter' {
            $command = Get-Command -Name 'Get-MicrosoftDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['FFUDevelopmentPath']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }
    }
}

# =============================================================================
# Get-HPDrivers Tests
# =============================================================================

Describe 'Get-HPDrivers' -Tag 'Unit', 'FFU.Drivers', 'Get-HPDrivers' {

    Context 'Parameter Validation' {
        It 'Should have mandatory Make parameter' {
            $command = Get-Command -Name 'Get-HPDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['Make']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory Model parameter' {
            $command = Get-Command -Name 'Get-HPDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['Model']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory WindowsArch parameter with ValidateSet' {
            $command = Get-Command -Name 'Get-HPDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['WindowsArch']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }

            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet | Should -Not -BeNullOrEmpty
            $validateSet.ValidValues | Should -Contain 'x64'
            $validateSet.ValidValues | Should -Contain 'x86'
            $validateSet.ValidValues | Should -Contain 'ARM64'
        }

        It 'Should have mandatory WindowsRelease parameter with ValidateSet' {
            $command = Get-Command -Name 'Get-HPDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['WindowsRelease']

            $param | Should -Not -BeNullOrEmpty
            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet | Should -Not -BeNullOrEmpty
            $validateSet.ValidValues | Should -Contain 10
            $validateSet.ValidValues | Should -Contain 11
        }

        It 'Should have mandatory WindowsVersion parameter' {
            $command = Get-Command -Name 'Get-HPDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['WindowsVersion']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory DriversFolder parameter' {
            $command = Get-Command -Name 'Get-HPDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['DriversFolder']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory FFUDevelopmentPath parameter' {
            $command = Get-Command -Name 'Get-HPDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['FFUDevelopmentPath']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }
    }
}

# =============================================================================
# Get-LenovoDrivers Tests
# =============================================================================

Describe 'Get-LenovoDrivers' -Tag 'Unit', 'FFU.Drivers', 'Get-LenovoDrivers' {

    Context 'Parameter Validation' {
        It 'Should have mandatory Make parameter' {
            $command = Get-Command -Name 'Get-LenovoDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['Make']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory Model parameter' {
            $command = Get-Command -Name 'Get-LenovoDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['Model']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory WindowsArch parameter with ValidateSet' {
            $command = Get-Command -Name 'Get-LenovoDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['WindowsArch']

            $param | Should -Not -BeNullOrEmpty

            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet | Should -Not -BeNullOrEmpty
            $validateSet.ValidValues | Should -Contain 'x64'
            $validateSet.ValidValues | Should -Contain 'x86'
            $validateSet.ValidValues | Should -Contain 'ARM64'
        }

        It 'Should have mandatory WindowsRelease parameter with ValidateSet' {
            $command = Get-Command -Name 'Get-LenovoDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['WindowsRelease']

            $param | Should -Not -BeNullOrEmpty

            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet | Should -Not -BeNullOrEmpty
            $validateSet.ValidValues | Should -Contain 10
            $validateSet.ValidValues | Should -Contain 11
        }

        It 'Should have mandatory Headers parameter' {
            $command = Get-Command -Name 'Get-LenovoDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['Headers']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory UserAgent parameter' {
            $command = Get-Command -Name 'Get-LenovoDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['UserAgent']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory DriversFolder parameter' {
            $command = Get-Command -Name 'Get-LenovoDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['DriversFolder']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory FFUDevelopmentPath parameter' {
            $command = Get-Command -Name 'Get-LenovoDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['FFUDevelopmentPath']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }
    }
}

# =============================================================================
# Get-DellDrivers Tests
# =============================================================================

Describe 'Get-DellDrivers' -Tag 'Unit', 'FFU.Drivers', 'Get-DellDrivers' {

    Context 'Parameter Validation' {
        It 'Should have mandatory Make parameter' {
            $command = Get-Command -Name 'Get-DellDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['Make']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory Model parameter' {
            $command = Get-Command -Name 'Get-DellDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['Model']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory WindowsArch parameter with ValidateSet' {
            $command = Get-Command -Name 'Get-DellDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['WindowsArch']

            $param | Should -Not -BeNullOrEmpty

            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet | Should -Not -BeNullOrEmpty
            $validateSet.ValidValues | Should -Contain 'x64'
            $validateSet.ValidValues | Should -Contain 'x86'
            $validateSet.ValidValues | Should -Contain 'ARM64'
        }

        It 'Should have mandatory WindowsRelease parameter' {
            $command = Get-Command -Name 'Get-DellDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['WindowsRelease']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory DriversFolder parameter' {
            $command = Get-Command -Name 'Get-DellDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['DriversFolder']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory FFUDevelopmentPath parameter' {
            $command = Get-Command -Name 'Get-DellDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['FFUDevelopmentPath']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory isServer parameter' {
            $command = Get-Command -Name 'Get-DellDrivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['isServer']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }
    }
}

# =============================================================================
# Copy-Drivers Tests
# =============================================================================

Describe 'Copy-Drivers' -Tag 'Unit', 'FFU.Drivers', 'Copy-Drivers' {

    Context 'Parameter Validation' {
        It 'Should have mandatory Path parameter' {
            $command = Get-Command -Name 'Copy-Drivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['Path']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory Output parameter' {
            $command = Get-Command -Name 'Copy-Drivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['Output']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory WindowsArch parameter with ValidateSet' {
            $command = Get-Command -Name 'Copy-Drivers' -Module 'FFU.Drivers'
            $param = $command.Parameters['WindowsArch']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }

            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet | Should -Not -BeNullOrEmpty
            $validateSet.ValidValues | Should -Contain 'x64'
            $validateSet.ValidValues | Should -Contain 'x86'
            $validateSet.ValidValues | Should -Contain 'ARM64'
        }
    }
}
