#Requires -Module Pester
#Requires -Version 7.0
<#
.SYNOPSIS
    Pester tests for Test-FFUHyperVSwitchConflict function.

.DESCRIPTION
    Tests the Hyper-V External Virtual Switch conflict detection for VMware builds.
    This check prevents Error 53 (network path not found) during FFU capture by
    detecting when an External Hyper-V switch would interfere with VMware bridged networking.

.NOTES
    Version: 1.0.0
    Date: 2026-01-16
    Author: FFU Builder Team
#>

BeforeAll {
    # Set up paths
    $script:FFUDevelopmentPath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'FFUDevelopment'
    $script:ModulePath = Join-Path $script:FFUDevelopmentPath 'Modules\FFU.Preflight'

    # Import the module
    Import-Module $script:ModulePath -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module 'FFU.Preflight' -Force -ErrorAction SilentlyContinue
}

Describe 'Test-FFUHyperVSwitchConflict' -Tag 'Preflight', 'VMware', 'HyperVSwitch' {

    Context 'Function Export and Availability' {

        It 'Should be exported from FFU.Preflight module' {
            Get-Command -Name 'Test-FFUHyperVSwitchConflict' -Module 'FFU.Preflight' -ErrorAction SilentlyContinue |
                Should -Not -BeNullOrEmpty
        }

        It 'Should have CmdletBinding attribute' {
            $cmd = Get-Command -Name 'Test-FFUHyperVSwitchConflict' -Module 'FFU.Preflight'
            $cmd.CmdletBinding | Should -BeTrue
        }

        It 'Should have OutputType attribute' {
            $cmd = Get-Command -Name 'Test-FFUHyperVSwitchConflict' -Module 'FFU.Preflight'
            $cmd.OutputType | Should -Not -BeNullOrEmpty
        }

        It 'Should have HypervisorType parameter' {
            $cmd = Get-Command -Name 'Test-FFUHyperVSwitchConflict' -Module 'FFU.Preflight'
            $cmd.Parameters.ContainsKey('HypervisorType') | Should -BeTrue
        }

        It 'HypervisorType should have ValidateSet attribute' {
            $cmd = Get-Command -Name 'Test-FFUHyperVSwitchConflict' -Module 'FFU.Preflight'
            $param = $cmd.Parameters['HypervisorType']
            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet | Should -Not -BeNullOrEmpty
            $validateSet.ValidValues | Should -Contain 'HyperV'
            $validateSet.ValidValues | Should -Contain 'VMware'
            $validateSet.ValidValues | Should -Contain 'Auto'
        }
    }

    Context 'When HypervisorType is HyperV' {

        It 'Should return Skipped status' {
            $result = Test-FFUHyperVSwitchConflict -HypervisorType 'HyperV'
            $result.Status | Should -Be 'Skipped'
        }

        It 'Should include HypervisorType in message' {
            $result = Test-FFUHyperVSwitchConflict -HypervisorType 'HyperV'
            $result.Message | Should -Match 'HyperV'
        }

        It 'Should have correct CheckName' {
            $result = Test-FFUHyperVSwitchConflict -HypervisorType 'HyperV'
            $result.CheckName | Should -Be 'HyperVSwitchConflict'
        }
    }

    Context 'When HypervisorType is Auto' {

        It 'Should return Skipped status' {
            $result = Test-FFUHyperVSwitchConflict -HypervisorType 'Auto'
            $result.Status | Should -Be 'Skipped'
        }
    }

    Context 'When HypervisorType is VMware' {

        Context 'When no External switches exist' {

            BeforeAll {
                # Mock Get-VMSwitch to return null (no switches)
                Mock Get-VMSwitch { $null } -ModuleName 'FFU.Preflight'
            }

            It 'Should return Passed status' {
                $result = Test-FFUHyperVSwitchConflict -HypervisorType 'VMware'
                $result.Status | Should -Be 'Passed'
            }

            It 'Should indicate no External switches found' {
                $result = Test-FFUHyperVSwitchConflict -HypervisorType 'VMware'
                $result.Message | Should -Match 'No External Hyper-V virtual switches found'
            }
        }

        Context 'When only Internal/Private switches exist' {

            BeforeAll {
                # Mock Get-VMSwitch to return only Internal switch
                Mock Get-VMSwitch {
                    [PSCustomObject]@{
                        Name = 'Default Switch'
                        SwitchType = 'Internal'
                    }
                } -ModuleName 'FFU.Preflight'
            }

            It 'Should return Passed status' {
                $result = Test-FFUHyperVSwitchConflict -HypervisorType 'VMware'
                $result.Status | Should -Be 'Passed'
            }
        }

        Context 'When External switch exists' {

            BeforeAll {
                # Mock Get-VMSwitch to return External switch
                Mock Get-VMSwitch {
                    [PSCustomObject]@{
                        Name = 'External-WiFi'
                        SwitchType = 'External'
                    }
                } -ModuleName 'FFU.Preflight'
            }

            It 'Should return Failed status' {
                $result = Test-FFUHyperVSwitchConflict -HypervisorType 'VMware'
                $result.Status | Should -Be 'Failed'
            }

            It 'Should include switch name in message' {
                $result = Test-FFUHyperVSwitchConflict -HypervisorType 'VMware'
                $result.Message | Should -Match 'External-WiFi'
            }

            It 'Should provide remediation steps' {
                $result = Test-FFUHyperVSwitchConflict -HypervisorType 'VMware'
                $result.Remediation | Should -Not -BeNullOrEmpty
            }

            It 'Remediation should mention Hyper-V Manager' {
                $result = Test-FFUHyperVSwitchConflict -HypervisorType 'VMware'
                $result.Remediation | Should -Match 'Hyper-V Manager'
            }

            It 'Remediation should include Remove-VMSwitch command' {
                $result = Test-FFUHyperVSwitchConflict -HypervisorType 'VMware'
                $result.Remediation | Should -Match 'Remove-VMSwitch'
            }

            It 'Should include Details with switch information' {
                $result = Test-FFUHyperVSwitchConflict -HypervisorType 'VMware'
                $result.Details | Should -Not -BeNullOrEmpty
                $result.Details.SwitchType | Should -Be 'External'
            }
        }

        Context 'When multiple External switches exist' {

            BeforeAll {
                # Mock Get-VMSwitch to return multiple External switches
                Mock Get-VMSwitch {
                    @(
                        [PSCustomObject]@{
                            Name = 'External-WiFi'
                            SwitchType = 'External'
                        },
                        [PSCustomObject]@{
                            Name = 'External-Ethernet'
                            SwitchType = 'External'
                        }
                    )
                } -ModuleName 'FFU.Preflight'
            }

            It 'Should return Failed status' {
                $result = Test-FFUHyperVSwitchConflict -HypervisorType 'VMware'
                $result.Status | Should -Be 'Failed'
            }

            It 'Should include all switch names in message' {
                $result = Test-FFUHyperVSwitchConflict -HypervisorType 'VMware'
                $result.Message | Should -Match 'External-WiFi'
                $result.Message | Should -Match 'External-Ethernet'
            }

            It 'Should report correct count in Details' {
                $result = Test-FFUHyperVSwitchConflict -HypervisorType 'VMware'
                $result.Details.Count | Should -Be 2
            }
        }

        Context 'When Get-VMSwitch throws an error (Hyper-V not installed)' {

            BeforeAll {
                # Mock Get-VMSwitch to throw error (simulating Hyper-V not installed)
                Mock Get-VMSwitch {
                    throw "The term 'Get-VMSwitch' is not recognized"
                } -ModuleName 'FFU.Preflight'
            }

            It 'Should return Passed status (conflict cannot exist)' {
                $result = Test-FFUHyperVSwitchConflict -HypervisorType 'VMware'
                $result.Status | Should -Be 'Passed'
            }

            It 'Should indicate Hyper-V not accessible in message' {
                $result = Test-FFUHyperVSwitchConflict -HypervisorType 'VMware'
                $result.Message | Should -Match 'not accessible'
            }
        }
    }

    Context 'Default Parameter Values' {

        It 'Should default to HyperV when no HypervisorType specified' {
            $result = Test-FFUHyperVSwitchConflict
            $result.Status | Should -Be 'Skipped'
            $result.Message | Should -Match 'HyperV'
        }
    }

    Context 'Result Object Structure' {

        It 'Should return object with CheckName property' {
            $result = Test-FFUHyperVSwitchConflict -HypervisorType 'HyperV'
            $result.PSObject.Properties.Name | Should -Contain 'CheckName'
        }

        It 'Should return object with Status property' {
            $result = Test-FFUHyperVSwitchConflict -HypervisorType 'HyperV'
            $result.PSObject.Properties.Name | Should -Contain 'Status'
        }

        It 'Should return object with Message property' {
            $result = Test-FFUHyperVSwitchConflict -HypervisorType 'HyperV'
            $result.PSObject.Properties.Name | Should -Contain 'Message'
        }

        It 'Should return object with DurationMs property' {
            $result = Test-FFUHyperVSwitchConflict -HypervisorType 'HyperV'
            $result.PSObject.Properties.Name | Should -Contain 'DurationMs'
        }

        It 'DurationMs should be a valid integer' {
            $result = Test-FFUHyperVSwitchConflict -HypervisorType 'HyperV'
            $result.DurationMs | Should -BeOfType [int]
            $result.DurationMs | Should -BeGreaterOrEqual 0
        }
    }
}
