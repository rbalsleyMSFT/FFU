#Requires -Module Pester
<#
.SYNOPSIS
    Pester tests for BuildFFUVM.ps1 MessagingContext parameter integration.

.DESCRIPTION
    Tests that validate the MessagingContext parameter was correctly added to BuildFFUVM.ps1:
    - Parameter exists in param block
    - Parameter is optional (has default value of $null)
    - Parameter accepts hashtable type
    - Script parses correctly from any directory
    - UI can pass MessagingContext without error

.NOTES
    Version: 1.0.0
    Date: 2025-12-10
    Author: FFU Builder Team
    Related Issue: MessagingContext parameter not found error
#>

BeforeAll {
    # Set up paths
    $script:FFUDevelopmentPath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:BuildFFUVMPath = Join-Path $script:FFUDevelopmentPath 'FFUDevelopment\BuildFFUVM.ps1'
    $script:BuildFFUVMUIPath = Join-Path $script:FFUDevelopmentPath 'FFUDevelopment\BuildFFUVM_UI.ps1'
    $script:MessagingModulePath = Join-Path $script:FFUDevelopmentPath 'FFUDevelopment\Modules\FFU.Messaging'

    # Parse BuildFFUVM.ps1 to get AST
    $script:errors = $null
    $script:tokens = $null
    $script:ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:BuildFFUVMPath,
        [ref]$script:tokens,
        [ref]$script:errors
    )

    # Read file content for text-based tests
    $script:BuildFFUVMContent = Get-Content -Path $script:BuildFFUVMPath -Raw
    $script:BuildFFUVMUIContent = Get-Content -Path $script:BuildFFUVMUIPath -Raw
}

Describe 'BuildFFUVM.ps1 MessagingContext Parameter' -Tag 'MessagingContext', 'Parameter' {

    Context 'Parameter Existence' {

        It 'Script should parse without errors' {
            $script:errors.Count | Should -Be 0 -Because "BuildFFUVM.ps1 should have no syntax errors"
        }

        It 'Should have MessagingContext parameter in param block' {
            $params = $script:ast.ParamBlock.Parameters
            $msgParam = $params | Where-Object { $_.Name.VariablePath.UserPath -eq 'MessagingContext' }
            $msgParam | Should -Not -BeNullOrEmpty -Because "MessagingContext parameter must exist"
        }

        It 'MessagingContext parameter should be of type hashtable' {
            $params = $script:ast.ParamBlock.Parameters
            $msgParam = $params | Where-Object { $_.Name.VariablePath.UserPath -eq 'MessagingContext' }
            $typeConstraint = $msgParam.Attributes | Where-Object { $_ -is [System.Management.Automation.Language.TypeConstraintAst] }
            $typeConstraint.TypeName.Name | Should -Be 'hashtable' -Because "MessagingContext must accept hashtable type"
        }

        It 'MessagingContext parameter should have default value of $null' {
            $params = $script:ast.ParamBlock.Parameters
            $msgParam = $params | Where-Object { $_.Name.VariablePath.UserPath -eq 'MessagingContext' }
            $msgParam.DefaultValue | Should -Not -BeNullOrEmpty -Because "Parameter should have a default value"
            $msgParam.DefaultValue.Extent.Text | Should -Be '$null' -Because "Default should be null for CLI compatibility"
        }

        It 'MessagingContext parameter should not be mandatory' {
            $params = $script:ast.ParamBlock.Parameters
            $msgParam = $params | Where-Object { $_.Name.VariablePath.UserPath -eq 'MessagingContext' }
            $paramAttr = $msgParam.Attributes | Where-Object {
                $_ -is [System.Management.Automation.Language.AttributeAst] -and
                $_.TypeName.Name -eq 'Parameter'
            }

            if ($paramAttr) {
                $mandatoryArg = $paramAttr.NamedArguments | Where-Object { $_.ArgumentName -eq 'Mandatory' }
                if ($mandatoryArg) {
                    $mandatoryArg.Argument.Extent.Text | Should -Be '$false' -Because "Parameter should not be mandatory"
                }
                # If no Mandatory argument, it defaults to false, which is correct
            }
            # If no Parameter attribute, it defaults to not mandatory, which is correct
        }
    }

    Context 'Help Documentation' {

        It 'Should have .PARAMETER MessagingContext in help documentation' {
            $script:BuildFFUVMContent | Should -Match '\.PARAMETER MessagingContext' -Because "Help should document the parameter"
        }

        It 'Help should mention FFU.Messaging module' {
            $script:BuildFFUVMContent | Should -Match 'FFU\.Messaging' -Because "Help should reference the messaging module"
        }

        It 'Help should mention UI communication purpose' {
            $script:BuildFFUVMContent | Should -Match 'UI communication|real-time.*UI|UI.*updates' -Because "Help should explain the UI purpose"
        }
    }

    Context 'Code Comments' {

        It 'Should have inline comment explaining MessagingContext purpose' {
            $script:BuildFFUVMContent | Should -Match '#.*MessagingContext.*UI|#.*MessagingContext.*messaging' -Because "Code should document the parameter"
        }
    }
}

Describe 'BuildFFUVM_UI.ps1 MessagingContext Usage' -Tag 'MessagingContext', 'UIIntegration' {

    Context 'Parameter Passing' {

        It 'Should pass MessagingContext to BuildFFUVM.ps1' {
            $script:BuildFFUVMUIContent | Should -Match '-MessagingContext \$SyncContext' -Because "UI must pass MessagingContext to build script"
        }

        It 'Should create messaging context before starting build' {
            $script:BuildFFUVMUIContent | Should -Match 'New-FFUMessagingContext' -Because "UI must create context before build"
        }

        It 'SyncContext should be passed as third argument to scriptBlock' {
            $script:BuildFFUVMUIContent | Should -Match 'param\(\$buildParams,\s*\$ScriptRoot,\s*\$SyncContext\)' -Because "ThreadJob scriptBlock must receive SyncContext"
        }
    }
}

Describe 'CLI Compatibility' -Tag 'MessagingContext', 'CLI' {

    Context 'Default Behavior Without MessagingContext' {

        It 'Script can be called without MessagingContext parameter' {
            # This test verifies the parameter has a default value and isn't mandatory
            $params = $script:ast.ParamBlock.Parameters
            $msgParam = $params | Where-Object { $_.Name.VariablePath.UserPath -eq 'MessagingContext' }

            # Should have default value
            $msgParam.DefaultValue | Should -Not -BeNullOrEmpty

            # Should not be mandatory
            $paramAttr = $msgParam.Attributes | Where-Object {
                $_ -is [System.Management.Automation.Language.AttributeAst] -and
                $_.TypeName.Name -eq 'Parameter'
            }
            $isMandatory = $false
            if ($paramAttr) {
                $mandatoryArg = $paramAttr.NamedArguments | Where-Object { $_.ArgumentName -eq 'Mandatory' }
                if ($mandatoryArg -and $mandatoryArg.Argument.Extent.Text -eq '$true') {
                    $isMandatory = $true
                }
            }
            $isMandatory | Should -BeFalse -Because "CLI users should not need to provide MessagingContext"
        }

        It 'MessagingContext default is $null (not empty hashtable)' {
            $params = $script:ast.ParamBlock.Parameters
            $msgParam = $params | Where-Object { $_.Name.VariablePath.UserPath -eq 'MessagingContext' }
            $msgParam.DefaultValue.Extent.Text | Should -Be '$null' -Because "Default should be null, not empty hashtable"
        }
    }
}

Describe 'FFU.Messaging Module Availability' -Tag 'MessagingContext', 'Module' {

    Context 'Module Structure' {

        It 'FFU.Messaging module folder exists' {
            Test-Path $script:MessagingModulePath | Should -BeTrue
        }

        It 'FFU.Messaging.psm1 exists' {
            Test-Path (Join-Path $script:MessagingModulePath 'FFU.Messaging.psm1') | Should -BeTrue
        }

        It 'FFU.Messaging.psd1 exists' {
            Test-Path (Join-Path $script:MessagingModulePath 'FFU.Messaging.psd1') | Should -BeTrue
        }
    }

    Context 'Module Functions Required for Integration' {

        BeforeAll {
            Import-Module $script:MessagingModulePath -Force -DisableNameChecking -ErrorAction Stop
        }

        AfterAll {
            Remove-Module 'FFU.Messaging' -Force -ErrorAction SilentlyContinue
        }

        It 'New-FFUMessagingContext is exported' {
            Get-Command -Name 'New-FFUMessagingContext' -Module 'FFU.Messaging' | Should -Not -BeNullOrEmpty
        }

        It 'Set-FFUBuildState is exported' {
            Get-Command -Name 'Set-FFUBuildState' -Module 'FFU.Messaging' | Should -Not -BeNullOrEmpty
        }

        It 'Write-FFUError is exported' {
            Get-Command -Name 'Write-FFUError' -Module 'FFU.Messaging' | Should -Not -BeNullOrEmpty
        }

        It 'Close-FFUMessagingContext is exported' {
            Get-Command -Name 'Close-FFUMessagingContext' -Module 'FFU.Messaging' | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Integration Simulation' -Tag 'MessagingContext', 'Integration' {

    Context 'UI Can Create and Pass Context' {

        It 'Can create messaging context like UI does' {
            # Import module directly in test for proper scoping
            Import-Module $script:MessagingModulePath -Force -DisableNameChecking -ErrorAction Stop
            try {
                $context = New-FFUMessagingContext
                $context | Should -Not -BeNullOrEmpty
                $context | Should -BeOfType [hashtable]
                # Check that MessageQueue key exists and is not null
                $context.ContainsKey('MessageQueue') | Should -BeTrue -Because "Context should have MessageQueue key"
                # Note: Can't use -BeNullOrEmpty because ConcurrentQueue.ToString() returns empty string
                # Instead, explicitly check for null
                ($null -eq $context['MessageQueue']) | Should -BeFalse -Because "MessageQueue should be initialized"
                $context['MessageQueue'].GetType().Name | Should -Be 'ConcurrentQueue`1' -Because "MessageQueue should be a ConcurrentQueue"
            }
            finally {
                Remove-Module 'FFU.Messaging' -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Context can be passed to hashtable parameter' {
            Import-Module $script:MessagingModulePath -Force -DisableNameChecking -ErrorAction Stop
            try {
                $context = New-FFUMessagingContext

                # Simulate what happens when passing to BuildFFUVM.ps1
                $testFunction = {
                    param([hashtable]$MessagingContext = $null)
                    return $MessagingContext -ne $null
                }

                $result = & $testFunction -MessagingContext $context
                $result | Should -BeTrue -Because "Context should be passable to hashtable parameter"
            }
            finally {
                Remove-Module 'FFU.Messaging' -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Null context is accepted (CLI mode)' {
            $testFunction = {
                param([hashtable]$MessagingContext = $null)
                return $MessagingContext -eq $null
            }

            $result = & $testFunction
            $result | Should -BeTrue -Because "Null should be valid for CLI usage"
        }
    }
}
