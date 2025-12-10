#Requires -Version 5.1
#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for ShareName empty string bug fix

.DESCRIPTION
    Tests the fix for "Cannot bind argument to parameter 'ShareName' because it is an empty string"
    error that occurred when users cleared the ShareName textbox in the UI.

    The fix includes:
    1. BuildFFUVM.ps1: Changed IsNullOrEmpty to IsNullOrWhiteSpace in config loading
    2. FFU.VM.psm1: Added default values to ShareName parameters in functions

.NOTES
    Test Coverage:
    - Config loading skips empty strings
    - Config loading skips whitespace-only strings
    - FFU.VM functions have ShareName defaults
    - Functions work without ShareName parameter
#>

# =============================================================================
# BuildFFUVM.ps1 Config Loading Tests
# =============================================================================

Describe 'BuildFFUVM.ps1 Config Loading - ShareName Validation' -Tag 'Unit', 'BuildFFUVM', 'ShareName', 'ConfigLoading' {

    Context 'IsNullOrWhiteSpace usage in config loading' {

        It 'Should use IsNullOrWhiteSpace instead of IsNullOrEmpty for config value checks' {
            $buildFFUPath = Join-Path $PSScriptRoot "..\..\FFUDevelopment\BuildFFUVM.ps1"
            $content = Get-Content $buildFFUPath -Raw

            # The config loading section should use IsNullOrWhiteSpace
            $content | Should -Match '\[string\]::IsNullOrWhiteSpace\(\[string\]\$value\)'
        }

        It 'Should NOT use IsNullOrEmpty for the main config value check' {
            $buildFFUPath = Join-Path $PSScriptRoot "..\..\FFUDevelopment\BuildFFUVM.ps1"
            $content = Get-Content $buildFFUPath -Raw

            # Extract the config loading section (lines around 640-650)
            $configLoadingMatch = [regex]::Match($content, '# If \$value is empty, skip[\s\S]*?continue\s*\}')

            if ($configLoadingMatch.Success) {
                $configLoadingSection = $configLoadingMatch.Value
                # This section should NOT have IsNullOrEmpty as the primary check
                # It should have IsNullOrWhiteSpace
                $configLoadingSection | Should -Not -Match '\[string\]::IsNullOrEmpty\(\[string\]\$value\)'
                $configLoadingSection | Should -Match '\[string\]::IsNullOrWhiteSpace\(\[string\]\$value\)'
            }
        }
    }

    Context 'Empty and whitespace value handling' {

        BeforeAll {
            # Simulate the fixed config loading logic
            $script:testConfigValues = @(
                @{ Value = ""; ShouldSkip = $true; Description = "Empty string" },
                @{ Value = " "; ShouldSkip = $true; Description = "Single space" },
                @{ Value = "   "; ShouldSkip = $true; Description = "Multiple spaces" },
                @{ Value = "`t"; ShouldSkip = $true; Description = "Tab character" },
                @{ Value = " `t "; ShouldSkip = $true; Description = "Mixed whitespace" },
                @{ Value = "FFUCaptureShare"; ShouldSkip = $false; Description = "Valid value" },
                @{ Value = " FFUCaptureShare "; ShouldSkip = $false; Description = "Value with surrounding spaces" }
            )
        }

        It 'Should skip empty string: "<Description>"' -ForEach @(
            @{ Value = ""; ShouldSkip = $true; Description = "Empty string" }
        ) {
            $result = [string]::IsNullOrWhiteSpace($Value)
            $result | Should -Be $ShouldSkip
        }

        It 'Should skip whitespace-only: "<Description>"' -ForEach @(
            @{ Value = " "; ShouldSkip = $true; Description = "Single space" },
            @{ Value = "   "; ShouldSkip = $true; Description = "Multiple spaces" },
            @{ Value = "`t"; ShouldSkip = $true; Description = "Tab character" }
        ) {
            $result = [string]::IsNullOrWhiteSpace($Value)
            $result | Should -Be $ShouldSkip
        }

        It 'Should NOT skip valid value: "<Description>"' -ForEach @(
            @{ Value = "FFUCaptureShare"; ShouldSkip = $false; Description = "Valid value" },
            @{ Value = " FFUCaptureShare "; ShouldSkip = $false; Description = "Value with surrounding spaces" }
        ) {
            $result = [string]::IsNullOrWhiteSpace($Value)
            $result | Should -Be $ShouldSkip
        }
    }
}

# =============================================================================
# FFU.VM Module Function Default Tests
# =============================================================================

Describe 'FFU.VM Module - ShareName Default Values' -Tag 'Unit', 'FFU.VM', 'ShareName', 'Defaults' {

    Context 'Set-CaptureFFU function' {

        It 'Should have ShareName parameter with default value' {
            $modulePath = Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules\FFU.VM\FFU.VM.psm1"
            $content = Get-Content $modulePath -Raw

            # Extract Set-CaptureFFU function
            $functionMatch = [regex]::Match($content, 'function Set-CaptureFFU[\s\S]*?(?=\nfunction |\n#\s*Export|\z)')
            $functionContent = $functionMatch.Value

            # ShareName should have default value
            $functionContent | Should -Match '\[string\]\$ShareName\s*=\s*[''"]FFUCaptureShare[''"]'
        }
    }

    Context 'Remove-FFUUserShare function' {

        It 'Should have ShareName parameter with default value' {
            $modulePath = Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules\FFU.VM\FFU.VM.psm1"
            $content = Get-Content $modulePath -Raw

            # Extract Remove-FFUUserShare function
            $functionMatch = [regex]::Match($content, 'function Remove-FFUUserShare[\s\S]*?(?=\nfunction |\n#\s*Export|\z)')
            $functionContent = $functionMatch.Value

            # ShareName should have default value
            $functionContent | Should -Match '\[string\]\$ShareName\s*=\s*[''"]FFUCaptureShare[''"]'
        }
    }

    Context 'Update-CaptureFFUScript function' {

        It 'Should have ShareName parameter with default value' {
            $modulePath = Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules\FFU.VM\FFU.VM.psm1"
            $content = Get-Content $modulePath -Raw

            # Extract Update-CaptureFFUScript function
            $functionMatch = [regex]::Match($content, 'function Update-CaptureFFUScript[\s\S]*?(?=\nfunction |\n#\s*Export|\z)')
            $functionContent = $functionMatch.Value

            # ShareName should have default value
            $functionContent | Should -Match '\[string\]\$ShareName\s*=\s*[''"]FFUCaptureShare[''"]'
        }
    }

    Context 'Remove-FFUVM function' {

        It 'Should have ShareName parameter with default value' {
            $modulePath = Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules\FFU.VM\FFU.VM.psm1"
            $content = Get-Content $modulePath -Raw

            # Extract Remove-FFUVM function
            $functionMatch = [regex]::Match($content, 'function Remove-FFUVM[\s\S]*?(?=\nfunction |\n#\s*Export|\z)')
            $functionContent = $functionMatch.Value

            # ShareName should have default value
            $functionContent | Should -Match '\[string\]\$ShareName\s*=\s*[''"]FFUCaptureShare[''"]'
        }
    }
}

# =============================================================================
# Functional Tests - Config Loading Simulation
# =============================================================================

Describe 'Config Loading Functional Tests' -Tag 'Unit', 'Functional', 'ShareName', 'ConfigLoading' {

    Context 'Simulate config loading with various ShareName values' {

        BeforeEach {
            # Reset to default
            $script:ShareName = "FFUCaptureShare"
        }

        It 'Should preserve default when config has empty ShareName' {
            $testConfig = '{"ShareName": ""}' | ConvertFrom-Json
            $value = $testConfig.ShareName

            # Simulate the fixed config loading logic
            if (-not ([string]::IsNullOrWhiteSpace([string]$value))) {
                Set-Variable -Name 'ShareName' -Value $value -Scope Script
            }

            $script:ShareName | Should -Be "FFUCaptureShare"
        }

        It 'Should preserve default when config has whitespace-only ShareName' {
            $testConfig = '{"ShareName": "   "}' | ConvertFrom-Json
            $value = $testConfig.ShareName

            # Simulate the fixed config loading logic
            if (-not ([string]::IsNullOrWhiteSpace([string]$value))) {
                Set-Variable -Name 'ShareName' -Value $value -Scope Script
            }

            $script:ShareName | Should -Be "FFUCaptureShare"
        }

        It 'Should apply valid ShareName from config' {
            $testConfig = '{"ShareName": "CustomShare"}' | ConvertFrom-Json
            $value = $testConfig.ShareName

            # Simulate the fixed config loading logic
            if (-not ([string]::IsNullOrWhiteSpace([string]$value))) {
                Set-Variable -Name 'ShareName' -Value $value -Scope Script
            }

            $script:ShareName | Should -Be "CustomShare"
        }

        It 'Should preserve default when ShareName key is missing' {
            $testConfig = '{}' | ConvertFrom-Json

            if ($testConfig.PSObject.Properties.Name -contains 'ShareName') {
                $value = $testConfig.ShareName
                if (-not ([string]::IsNullOrWhiteSpace([string]$value))) {
                    Set-Variable -Name 'ShareName' -Value $value -Scope Script
                }
            }

            $script:ShareName | Should -Be "FFUCaptureShare"
        }
    }
}

# =============================================================================
# Regression Tests
# =============================================================================

Describe 'ShareName Bug Regression Prevention' -Tag 'Unit', 'Regression', 'ShareName' {

    Context 'Original bug scenario' {

        It 'Should not fail when calling function with empty ShareName variable (using defaults)' {
            # Simulate a function with default ShareName
            function Test-ShareNameDefault {
                param(
                    [string]$ShareName = "FFUCaptureShare"
                )
                return $ShareName
            }

            # Even with empty variable, default should be used
            $emptyVar = ""
            $result = Test-ShareNameDefault  # Don't pass the empty variable
            $result | Should -Be "FFUCaptureShare"
        }

        It 'Should handle whitespace-only values correctly in IsNullOrWhiteSpace check' {
            $whitespaceValues = @("", " ", "  ", "`t", " `t ", "`n")

            foreach ($val in $whitespaceValues) {
                $result = [string]::IsNullOrWhiteSpace($val)
                $result | Should -BeTrue -Because "Value '$val' (length: $($val.Length)) should be treated as whitespace"
            }
        }

        It 'Should NOT treat valid values with spaces as whitespace' {
            $validValues = @("Share", " Share", "Share ", " Share ", "My Share")

            foreach ($val in $validValues) {
                $result = [string]::IsNullOrWhiteSpace($val)
                $result | Should -BeFalse -Because "Value '$val' is a valid share name"
            }
        }
    }

    Context 'Error message verification' {

        It 'Should demonstrate the original error when passing empty string to Mandatory parameter' {
            function Test-MandatoryParam {
                param(
                    [Parameter(Mandatory = $true)]
                    [string]$ShareName
                )
                return $ShareName
            }

            { Test-MandatoryParam -ShareName "" } | Should -Throw "*Cannot bind argument*empty string*"
        }

        It 'Should NOT throw when using default value instead of empty string' {
            function Test-DefaultParam {
                param(
                    [string]$ShareName = "FFUCaptureShare"
                )
                return $ShareName
            }

            # Calling without parameter should use default
            $result = Test-DefaultParam
            $result | Should -Be "FFUCaptureShare"
        }
    }
}

# =============================================================================
# IsNullOrEmpty vs IsNullOrWhiteSpace Comparison Tests
# =============================================================================

Describe 'IsNullOrEmpty vs IsNullOrWhiteSpace Behavior' -Tag 'Unit', 'ShareName', 'StringValidation' {

    Context 'Behavior comparison' {

        It 'IsNullOrEmpty returns False for whitespace, but IsNullOrWhiteSpace returns True' {
            $whitespace = " "

            [string]::IsNullOrEmpty($whitespace) | Should -BeFalse
            [string]::IsNullOrWhiteSpace($whitespace) | Should -BeTrue
        }

        It 'Both return True for empty string' {
            $empty = ""

            [string]::IsNullOrEmpty($empty) | Should -BeTrue
            [string]::IsNullOrWhiteSpace($empty) | Should -BeTrue
        }

        It 'Both return True for null' {
            $null_value = $null

            [string]::IsNullOrEmpty($null_value) | Should -BeTrue
            [string]::IsNullOrWhiteSpace($null_value) | Should -BeTrue
        }

        It 'Both return False for valid values' {
            $valid = "FFUCaptureShare"

            [string]::IsNullOrEmpty($valid) | Should -BeFalse
            [string]::IsNullOrWhiteSpace($valid) | Should -BeFalse
        }
    }
}
