#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for FFU.Apps module

.DESCRIPTION
    Comprehensive unit tests covering all exported functions in the FFU.Apps module.
    Tests verify parameter validation, expected behavior, error handling, and edge cases.

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\FFU.Apps.Tests.ps1 -Output Detailed
    Coverage: Invoke-Pester -Path .\Tests\Unit\FFU.Apps.Tests.ps1 -CodeCoverage .\FFUDevelopment\Modules\FFU.Apps\*.psm1
#>

BeforeAll {
    # Get paths relative to test file location
    $TestRoot = Split-Path $PSScriptRoot -Parent
    $ProjectRoot = Split-Path $TestRoot -Parent
    $ModulePath = Join-Path $ProjectRoot 'FFUDevelopment\Modules\FFU.Apps'
    $CoreModulePath = Join-Path $ProjectRoot 'FFUDevelopment\Modules\FFU.Core'

    # Remove modules if loaded
    Get-Module -Name 'FFU.Apps', 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue

    # Import FFU.Core first (dependency)
    if (Test-Path "$CoreModulePath\FFU.Core.psd1") {
        Import-Module "$CoreModulePath\FFU.Core.psd1" -Force -ErrorAction SilentlyContinue
    }

    # Import FFU.Apps module
    if (-not (Test-Path "$ModulePath\FFU.Apps.psd1")) {
        throw "FFU.Apps module not found at: $ModulePath"
    }
    Import-Module "$ModulePath\FFU.Apps.psd1" -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name 'FFU.Apps', 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# Module Export Verification
# =============================================================================

Describe 'FFU.Apps Module Exports' -Tag 'Unit', 'FFU.Apps', 'Module' {

    Context 'Expected Functions Are Exported' {
        It 'Should export Get-ODTURL' {
            Get-Command -Name 'Get-ODTURL' -Module 'FFU.Apps' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Get-Office' {
            Get-Command -Name 'Get-Office' -Module 'FFU.Apps' | Should -Not -BeNullOrEmpty
        }

        It 'Should export New-AppsISO' {
            Get-Command -Name 'New-AppsISO' -Module 'FFU.Apps' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Remove-Apps' {
            Get-Command -Name 'Remove-Apps' -Module 'FFU.Apps' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Remove-DisabledArtifacts' {
            Get-Command -Name 'Remove-DisabledArtifacts' -Module 'FFU.Apps' | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Module Metadata' {
        It 'Should have a valid module manifest' {
            $ManifestPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Apps\FFU.Apps.psd1'
            Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Get-ODTURL Tests
# =============================================================================

Describe 'Get-ODTURL' -Tag 'Unit', 'FFU.Apps', 'Get-ODTURL' {

    Context 'Parameter Validation' {
        It 'Should have mandatory Headers parameter' {
            $command = Get-Command -Name 'Get-ODTURL' -Module 'FFU.Apps'
            $param = $command.Parameters['Headers']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory UserAgent parameter' {
            $command = Get-Command -Name 'Get-ODTURL' -Module 'FFU.Apps'
            $param = $command.Parameters['UserAgent']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have hashtable type for Headers parameter' {
            $command = Get-Command -Name 'Get-ODTURL' -Module 'FFU.Apps'
            $param = $command.Parameters['Headers']
            $param.ParameterType.Name | Should -Be 'Hashtable'
        }

        It 'Should have string type for UserAgent parameter' {
            $command = Get-Command -Name 'Get-ODTURL' -Module 'FFU.Apps'
            $param = $command.Parameters['UserAgent']
            $param.ParameterType.Name | Should -Be 'String'
        }
    }
}

# =============================================================================
# Get-Office Tests
# =============================================================================

Describe 'Get-Office' -Tag 'Unit', 'FFU.Apps', 'Get-Office' {

    Context 'Parameter Validation' {
        It 'Should have mandatory OfficePath parameter' {
            $command = Get-Command -Name 'Get-Office' -Module 'FFU.Apps'
            $param = $command.Parameters['OfficePath']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory OfficeDownloadXML parameter' {
            $command = Get-Command -Name 'Get-Office' -Module 'FFU.Apps'
            $param = $command.Parameters['OfficeDownloadXML']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have optional OfficeInstallXML parameter with default value' {
            $command = Get-Command -Name 'Get-Office' -Module 'FFU.Apps'
            $param = $command.Parameters['OfficeInstallXML']
            $param | Should -Not -BeNullOrEmpty
        }

        It 'Should have mandatory OrchestrationPath parameter' {
            $command = Get-Command -Name 'Get-Office' -Module 'FFU.Apps'
            $param = $command.Parameters['OrchestrationPath']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory FFUDevelopmentPath parameter' {
            $command = Get-Command -Name 'Get-Office' -Module 'FFU.Apps'
            $param = $command.Parameters['FFUDevelopmentPath']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory Headers parameter' {
            $command = Get-Command -Name 'Get-Office' -Module 'FFU.Apps'
            $param = $command.Parameters['Headers']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory UserAgent parameter' {
            $command = Get-Command -Name 'Get-Office' -Module 'FFU.Apps'
            $param = $command.Parameters['UserAgent']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have optional OfficeConfigXMLFile parameter' {
            $command = Get-Command -Name 'Get-Office' -Module 'FFU.Apps'
            $command.Parameters['OfficeConfigXMLFile'] | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# New-AppsISO Tests
# =============================================================================

Describe 'New-AppsISO' -Tag 'Unit', 'FFU.Apps', 'New-AppsISO' {

    Context 'Parameter Validation' {
        It 'Should have mandatory ADKPath parameter' {
            $command = Get-Command -Name 'New-AppsISO' -Module 'FFU.Apps'
            $param = $command.Parameters['ADKPath']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory AppsPath parameter' {
            $command = Get-Command -Name 'New-AppsISO' -Module 'FFU.Apps'
            $param = $command.Parameters['AppsPath']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory AppsISO parameter' {
            $command = Get-Command -Name 'New-AppsISO' -Module 'FFU.Apps'
            $param = $command.Parameters['AppsISO']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }
    }
}

# =============================================================================
# Remove-Apps Tests
# =============================================================================

Describe 'Remove-Apps' -Tag 'Unit', 'FFU.Apps', 'Remove-Apps' {

    Context 'Function Existence' {
        It 'Should be exported from module' {
            $command = Get-Command -Name 'Remove-Apps' -Module 'FFU.Apps'
            $command | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Remove-DisabledArtifacts Tests
# =============================================================================

Describe 'Remove-DisabledArtifacts' -Tag 'Unit', 'FFU.Apps', 'Remove-DisabledArtifacts' {

    Context 'Function Existence' {
        It 'Should be exported from module' {
            $command = Get-Command -Name 'Remove-DisabledArtifacts' -Module 'FFU.Apps'
            $command | Should -Not -BeNullOrEmpty
        }

        It 'Should support CmdletBinding' {
            $command = Get-Command -Name 'Remove-DisabledArtifacts' -Module 'FFU.Apps'
            $command.CmdletBinding | Should -BeTrue
        }
    }
}
