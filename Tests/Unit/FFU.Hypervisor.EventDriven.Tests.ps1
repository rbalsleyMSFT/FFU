#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for FFU.Hypervisor event-driven VM state monitoring (PERF-02)

.DESCRIPTION
    Tests Wait-VMStateChange function behavior including:
    - CIM event registration
    - State detection
    - Timeout handling
    - Cleanup on exit
#>

BeforeAll {
    $script:FFUDevelopmentPath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ModulesPath = Join-Path $FFUDevelopmentPath 'FFUDevelopment\Modules'

    # Add modules folder to PSModulePath if not present
    if ($env:PSModulePath -notlike "*$ModulesPath*") {
        $env:PSModulePath = "$ModulesPath;$env:PSModulePath"
    }

    # Import FFU.Core first (dependency)
    Import-Module (Join-Path $ModulesPath 'FFU.Core\FFU.Core.psd1') -Force -ErrorAction SilentlyContinue

    # Import the FFU.Hypervisor module
    Import-Module (Join-Path $ModulesPath 'FFU.Hypervisor\FFU.Hypervisor.psd1') -Force -ErrorAction Stop
}

Describe "Wait-VMStateChange" {

    Context "When VM is already in target state" {

        BeforeEach {
            Mock Get-VM {
                return [PSCustomObject]@{
                    Name = 'TestVM'
                    State = 'Off'
                }
            } -ModuleName FFU.Hypervisor

            Mock Register-CimIndicationEvent { } -ModuleName FFU.Hypervisor
        }

        It "Should return true immediately without waiting" {
            $result = Wait-VMStateChange -VMName 'TestVM' -TargetState 'Off' -TimeoutSeconds 5

            $result | Should -Be $true
        }

        It "Should return true when VM starts at target state" {
            # This verifies the early-exit code path when VM is already in desired state
            $result = Wait-VMStateChange -VMName 'TestVM' -TargetState 'Off' -TimeoutSeconds 5

            $result | Should -BeTrue
            # Function should return quickly without needing to register events
            Should -Not -Invoke Register-CimIndicationEvent -ModuleName FFU.Hypervisor
        }
    }

    Context "When VM does not exist" {

        BeforeEach {
            Mock Get-VM { return $null } -ModuleName FFU.Hypervisor
        }

        It "Should return false with warning" {
            $result = Wait-VMStateChange -VMName 'NonExistentVM' -TargetState 'Off' -TimeoutSeconds 5 -WarningAction SilentlyContinue

            $result | Should -Be $false
        }
    }

    Context "CIM Event Registration" {

        BeforeEach {
            # VM starts Running, needs to wait for Off
            Mock Get-VM {
                return [PSCustomObject]@{
                    Name = 'TestVM'
                    State = 'Running'
                }
            } -ModuleName FFU.Hypervisor

            Mock Register-CimIndicationEvent {
                return [PSCustomObject]@{ Name = 'MockJob' }
            } -ModuleName FFU.Hypervisor

            Mock Unregister-Event { } -ModuleName FFU.Hypervisor
            Mock Remove-Job { } -ModuleName FFU.Hypervisor
        }

        It "Should register CIM event with correct namespace" {
            # Short timeout to avoid long test
            $result = Wait-VMStateChange -VMName 'TestVM' -TargetState 'Off' -TimeoutSeconds 1

            Should -Invoke Register-CimIndicationEvent -ModuleName FFU.Hypervisor -ParameterFilter {
                $Namespace -eq 'root\virtualization\v2'
            }
        }

        It "Should include VM name in WQL query" {
            $result = Wait-VMStateChange -VMName 'TestVM' -TargetState 'Off' -TimeoutSeconds 1

            Should -Invoke Register-CimIndicationEvent -ModuleName FFU.Hypervisor -ParameterFilter {
                $Query -match 'TestVM'
            }
        }

        It "Should use Msvm_ComputerSystem class in WQL query" {
            $result = Wait-VMStateChange -VMName 'TestVM' -TargetState 'Off' -TimeoutSeconds 1

            Should -Invoke Register-CimIndicationEvent -ModuleName FFU.Hypervisor -ParameterFilter {
                $Query -match 'Msvm_ComputerSystem'
            }
        }
    }

    Context "Cleanup" {

        BeforeEach {
            Mock Get-VM {
                return [PSCustomObject]@{ Name = 'TestVM'; State = 'Running' }
            } -ModuleName FFU.Hypervisor

            Mock Register-CimIndicationEvent {
                return [PSCustomObject]@{ Name = 'MockJob' }
            } -ModuleName FFU.Hypervisor

            Mock Unregister-Event { } -ModuleName FFU.Hypervisor
            Mock Remove-Job { } -ModuleName FFU.Hypervisor
        }

        It "Should unregister event subscription on timeout" {
            $result = Wait-VMStateChange -VMName 'TestVM' -TargetState 'Off' -TimeoutSeconds 1

            Should -Invoke Unregister-Event -ModuleName FFU.Hypervisor -Times 1
        }

        It "Should clean up job on timeout" {
            $result = Wait-VMStateChange -VMName 'TestVM' -TargetState 'Off' -TimeoutSeconds 1

            Should -Invoke Remove-Job -ModuleName FFU.Hypervisor -Times 1
        }
    }

    Context "State Mapping" {

        BeforeEach {
            Mock Register-CimIndicationEvent { } -ModuleName FFU.Hypervisor
            Mock Unregister-Event { } -ModuleName FFU.Hypervisor
            Mock Remove-Job { } -ModuleName FFU.Hypervisor
        }

        It "Should accept 'Running' as valid target state" {
            Mock Get-VM { [PSCustomObject]@{ Name = 'TestVM'; State = 'Running' } } -ModuleName FFU.Hypervisor

            { Wait-VMStateChange -VMName 'TestVM' -TargetState 'Running' -TimeoutSeconds 1 } | Should -Not -Throw
        }

        It "Should accept 'Off' as valid target state" {
            Mock Get-VM { [PSCustomObject]@{ Name = 'TestVM'; State = 'Off' } } -ModuleName FFU.Hypervisor

            { Wait-VMStateChange -VMName 'TestVM' -TargetState 'Off' -TimeoutSeconds 1 } | Should -Not -Throw
        }

        It "Should accept 'Paused' as valid target state" {
            Mock Get-VM { [PSCustomObject]@{ Name = 'TestVM'; State = 'Paused' } } -ModuleName FFU.Hypervisor

            { Wait-VMStateChange -VMName 'TestVM' -TargetState 'Paused' -TimeoutSeconds 1 } | Should -Not -Throw
        }

        It "Should accept 'Saved' as valid target state" {
            Mock Get-VM { [PSCustomObject]@{ Name = 'TestVM'; State = 'Saved' } } -ModuleName FFU.Hypervisor

            { Wait-VMStateChange -VMName 'TestVM' -TargetState 'Saved' -TimeoutSeconds 1 } | Should -Not -Throw
        }

        It "Should reject invalid target states" {
            { Wait-VMStateChange -VMName 'TestVM' -TargetState 'InvalidState' -TimeoutSeconds 1 } | Should -Throw
        }
    }

    Context "Timeout Behavior" {

        BeforeEach {
            # VM stays in Running state (never reaches Off)
            Mock Get-VM {
                return [PSCustomObject]@{ Name = 'TestVM'; State = 'Running' }
            } -ModuleName FFU.Hypervisor

            Mock Register-CimIndicationEvent {
                return [PSCustomObject]@{ Name = 'MockJob' }
            } -ModuleName FFU.Hypervisor

            Mock Unregister-Event { } -ModuleName FFU.Hypervisor
            Mock Remove-Job { } -ModuleName FFU.Hypervisor
        }

        It "Should return false when timeout is exceeded" {
            $result = Wait-VMStateChange -VMName 'TestVM' -TargetState 'Off' -TimeoutSeconds 1

            $result | Should -Be $false
        }

        It "Should write warning on timeout" {
            $warnings = Wait-VMStateChange -VMName 'TestVM' -TargetState 'Off' -TimeoutSeconds 1 3>&1

            $warnings | Where-Object { $_ -match 'Timeout' } | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "HyperVProvider.WaitForState Integration" {

    It "Should have WaitForState method in HyperVProvider" {
        $providerContent = Get-Content (Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules\FFU.Hypervisor\Providers\HyperVProvider.ps1") -Raw

        $providerContent | Should -Match "WaitForState"
    }

    It "Should have WaitForState method in IHypervisorProvider interface" {
        $interfaceContent = Get-Content (Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules\FFU.Hypervisor\Classes\IHypervisorProvider.ps1") -Raw

        $interfaceContent | Should -Match "WaitForState"
    }

    It "Should export Wait-VMStateChange function" {
        Get-Command Wait-VMStateChange -Module FFU.Hypervisor -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It "Should have module version 1.3.0 or higher" {
        $module = Get-Module -Name FFU.Hypervisor
        $module.Version | Should -BeGreaterOrEqual ([Version]'1.3.0')
    }
}

Describe "Wait-VMStateChange Function Structure" {

    It "Should have CmdletBinding attribute" {
        $functionContent = Get-Content (Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules\FFU.Hypervisor\Public\Wait-VMStateChange.ps1") -Raw
        $functionContent | Should -Match '\[CmdletBinding\(\)\]'
    }

    It "Should have OutputType attribute" {
        $functionContent = Get-Content (Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules\FFU.Hypervisor\Public\Wait-VMStateChange.ps1") -Raw
        $functionContent | Should -Match '\[OutputType\(\[bool\]\)\]'
    }

    It "Should use Register-CimIndicationEvent for event subscription" {
        $functionContent = Get-Content (Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules\FFU.Hypervisor\Public\Wait-VMStateChange.ps1") -Raw
        $functionContent | Should -Match 'Register-CimIndicationEvent'
    }

    It "Should have cleanup in finally block" {
        $functionContent = Get-Content (Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules\FFU.Hypervisor\Public\Wait-VMStateChange.ps1") -Raw
        $functionContent | Should -Match 'finally\s*\{'
        $functionContent | Should -Match 'Unregister-Event'
    }
}
