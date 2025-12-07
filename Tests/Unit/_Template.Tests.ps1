#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for [MODULE_NAME] module

.DESCRIPTION
    Comprehensive unit tests covering all exported functions in the [MODULE_NAME] module.
    Tests verify parameter validation, expected behavior, error handling, and edge cases.

    INSTRUCTIONS:
    1. Copy this file and rename to [ModuleName].Tests.ps1 (e.g., FFU.VM.Tests.ps1)
    2. Replace [MODULE_NAME] with actual module name
    3. Update BeforeAll to import correct module
    4. Add Describe blocks for each exported function
    5. Follow the patterns shown in FFU.Core.Tests.ps1

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\[ModuleName].Tests.ps1 -Output Detailed
    Coverage: Invoke-Pester -Path .\Tests\Unit\[ModuleName].Tests.ps1 -CodeCoverage .\FFUDevelopment\Modules\[ModuleName]\*.psm1
#>

BeforeAll {
    # Get paths relative to test file location
    $TestRoot = Split-Path $PSScriptRoot -Parent
    $ProjectRoot = Split-Path $TestRoot -Parent
    $ModulePath = Join-Path $ProjectRoot 'FFUDevelopment\Modules\[MODULE_NAME]'

    # Remove module if loaded (ensures clean state)
    Get-Module -Name '[MODULE_NAME]' | Remove-Module -Force -ErrorAction SilentlyContinue

    # Verify module exists
    if (-not (Test-Path "$ModulePath\[MODULE_NAME].psd1")) {
        throw "[MODULE_NAME] module not found at: $ModulePath"
    }

    # Import the module
    Import-Module "$ModulePath\[MODULE_NAME].psd1" -Force -ErrorAction Stop
}

AfterAll {
    # Cleanup
    Get-Module -Name '[MODULE_NAME]' | Remove-Module -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# [FunctionName] Tests
# =============================================================================

Describe '[FunctionName]' -Tag 'Unit', '[MODULE_NAME]', '[FunctionName]' {

    Context 'Parameter Validation' {
        It 'Should have mandatory [ParameterName] parameter' {
            $command = Get-Command -Name '[FunctionName]' -Module '[MODULE_NAME]'
            $param = $command.Parameters['[ParameterName]']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should reject null value for [ParameterName]' {
            { [FunctionName] -[ParameterName] $null } | Should -Throw
        }

        It 'Should reject empty string for [ParameterName]' {
            { [FunctionName] -[ParameterName] '' } | Should -Throw
        }
    }

    Context 'Expected Behavior' {
        It 'Should return expected result for valid input' {
            # Arrange
            $input = 'ValidValue'
            $expected = 'ExpectedResult'

            # Act
            $result = [FunctionName] -[ParameterName] $input

            # Assert
            $result | Should -Be $expected
        }

        It 'Should handle multiple inputs correctly' -ForEach @(
            @{ Input = 'Value1'; Expected = 'Result1' }
            @{ Input = 'Value2'; Expected = 'Result2' }
            @{ Input = 'Value3'; Expected = 'Result3' }
        ) {
            $result = [FunctionName] -[ParameterName] $Input
            $result | Should -Be $Expected
        }
    }

    Context 'Error Handling' {
        It 'Should throw on invalid input' {
            { [FunctionName] -[ParameterName] 'InvalidValue' } | Should -Throw
        }

        It 'Should throw specific exception type' {
            { [FunctionName] -[ParameterName] 'InvalidValue' } |
                Should -Throw -ExceptionType ([System.ArgumentException])
        }

        It 'Should include helpful error message' {
            { [FunctionName] -[ParameterName] 'InvalidValue' } |
                Should -Throw -ExpectedMessage '*specific text*'
        }
    }

    Context 'Edge Cases' {
        It 'Should handle empty array' {
            $result = [FunctionName] -[ParameterName] @()
            $result | Should -BeNullOrEmpty
        }

        It 'Should handle special characters' {
            $result = [FunctionName] -[ParameterName] 'Value with spaces & symbols!'
            $result | Should -Not -BeNullOrEmpty
        }

        It 'Should handle very long strings' {
            $longString = 'x' * 10000
            { [FunctionName] -[ParameterName] $longString } | Should -Not -Throw
        }
    }

    Context 'Output Type' {
        It 'Should return correct type' {
            $result = [FunctionName] -[ParameterName] 'ValidValue'
            $result | Should -BeOfType [ExpectedType]
        }
    }
}

# =============================================================================
# [FunctionName2] Tests (with Mocking Example)
# =============================================================================

Describe '[FunctionName2]' -Tag 'Unit', '[MODULE_NAME]', '[FunctionName2]' {

    BeforeAll {
        # Mock external dependencies
        Mock Start-Process { } -ModuleName '[MODULE_NAME]'
        Mock Test-Path { return $true } -ModuleName '[MODULE_NAME]'
        Mock Get-Content { return '{"key": "value"}' } -ModuleName '[MODULE_NAME]'
    }

    Context 'With Mocked Dependencies' {
        It 'Should call external command with correct parameters' {
            [FunctionName2] -Path 'C:\Test\Path'

            Should -Invoke Start-Process -Times 1 -Exactly -ModuleName '[MODULE_NAME]' -ParameterFilter {
                $FilePath -eq 'expected.exe'
            }
        }

        It 'Should handle dependency failure' {
            Mock Start-Process { throw 'Process failed' } -ModuleName '[MODULE_NAME]'

            { [FunctionName2] -Path 'C:\Test\Path' } | Should -Throw '*Process failed*'
        }
    }
}

# =============================================================================
# Module Export Verification
# =============================================================================

Describe '[MODULE_NAME] Module Exports' -Tag 'Unit', '[MODULE_NAME]', 'Module' {

    Context 'Expected Functions Are Exported' {
        It 'Should export [FunctionName]' {
            Get-Command -Name '[FunctionName]' -Module '[MODULE_NAME]' | Should -Not -BeNullOrEmpty
        }

        It 'Should export [FunctionName2]' {
            Get-Command -Name '[FunctionName2]' -Module '[MODULE_NAME]' | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Module Metadata' {
        It 'Should have a valid module manifest' {
            $TestRoot = Split-Path $PSScriptRoot -Parent
            $ProjectRoot = Split-Path $TestRoot -Parent
            $ManifestPath = Join-Path $ProjectRoot 'FFUDevelopment\Modules\[MODULE_NAME]\[MODULE_NAME].psd1'

            Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop | Should -Not -BeNullOrEmpty
        }
    }
}
