#Requires -Version 7.0
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

<#
.SYNOPSIS
    Tests for VMware network configuration feature

.DESCRIPTION
    Pester tests verifying that VMware network type (bridged, nat, hostonly)
    and NIC type (e1000e, vmxnet3, e1000) are properly configurable through:
    - VMConfiguration class properties
    - New-VMConfiguration factory function parameters
    - VMwareProvider using config values instead of hardcoding

.NOTES
    Related Epic: RTS-99 - Make VMware Network Configuration User-Configurable
#>

BeforeAll {
    # Get paths
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

    # Helper function to run code in module scope (for class access)
    $script:HypervisorModule = Get-Module -Name 'FFU.Hypervisor'
    function Invoke-InModuleScope {
        param([scriptblock]$ScriptBlock)
        & $script:HypervisorModule $ScriptBlock
    }
}

Describe 'VMware Network Configuration' {

    Context 'VMConfiguration Class Properties' {
        It 'Should have VMwareNetworkType property with default value bridged' {
            $config = Invoke-InModuleScope { [VMConfiguration]::new() }
            $config.VMwareNetworkType | Should -Be 'bridged'
        }

        It 'Should have VMwareNicType property with default value e1000e' {
            $config = Invoke-InModuleScope { [VMConfiguration]::new() }
            $config.VMwareNicType | Should -Be 'e1000e'
        }

        It 'Should allow setting VMwareNetworkType to nat' {
            $config = Invoke-InModuleScope {
                $c = [VMConfiguration]::new()
                $c.VMwareNetworkType = 'nat'
                $c
            }
            $config.VMwareNetworkType | Should -Be 'nat'
        }

        It 'Should allow setting VMwareNetworkType to hostonly' {
            $config = Invoke-InModuleScope {
                $c = [VMConfiguration]::new()
                $c.VMwareNetworkType = 'hostonly'
                $c
            }
            $config.VMwareNetworkType | Should -Be 'hostonly'
        }

        It 'Should allow setting VMwareNicType to vmxnet3' {
            $config = Invoke-InModuleScope {
                $c = [VMConfiguration]::new()
                $c.VMwareNicType = 'vmxnet3'
                $c
            }
            $config.VMwareNicType | Should -Be 'vmxnet3'
        }

        It 'Should allow setting VMwareNicType to e1000' {
            $config = Invoke-InModuleScope {
                $c = [VMConfiguration]::new()
                $c.VMwareNicType = 'e1000'
                $c
            }
            $config.VMwareNicType | Should -Be 'e1000'
        }
    }

    Context 'New-VMConfiguration Factory Function' {
        BeforeAll {
            $script:TestParams = @{
                Name = 'TestVM'
                Path = 'C:\TestVMs\TestVM'
                MemoryBytes = 4GB
                ProcessorCount = 2
                VirtualDiskPath = 'C:\TestVMs\TestVM\disk.vhd'
            }
        }

        It 'Should accept VMwareNetworkType parameter' {
            $cmd = Get-Command New-VMConfiguration
            $cmd.Parameters.ContainsKey('VMwareNetworkType') | Should -BeTrue
        }

        It 'Should accept VMwareNicType parameter' {
            $cmd = Get-Command New-VMConfiguration
            $cmd.Parameters.ContainsKey('VMwareNicType') | Should -BeTrue
        }

        It 'Should validate VMwareNetworkType parameter values' {
            $cmd = Get-Command New-VMConfiguration
            $validateSet = $cmd.Parameters['VMwareNetworkType'].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet.ValidValues | Should -Contain 'bridged'
            $validateSet.ValidValues | Should -Contain 'nat'
            $validateSet.ValidValues | Should -Contain 'hostonly'
        }

        It 'Should validate VMwareNicType parameter values' {
            $cmd = Get-Command New-VMConfiguration
            $validateSet = $cmd.Parameters['VMwareNicType'].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet.ValidValues | Should -Contain 'e1000e'
            $validateSet.ValidValues | Should -Contain 'vmxnet3'
            $validateSet.ValidValues | Should -Contain 'e1000'
        }

        It 'Should create config with default VMwareNetworkType when not specified' {
            $config = New-VMConfiguration @TestParams
            $config.VMwareNetworkType | Should -Be 'bridged'
        }

        It 'Should create config with default VMwareNicType when not specified' {
            $config = New-VMConfiguration @TestParams
            $config.VMwareNicType | Should -Be 'e1000e'
        }

        It 'Should pass VMwareNetworkType to config when specified' {
            $config = New-VMConfiguration @TestParams -VMwareNetworkType 'nat'
            $config.VMwareNetworkType | Should -Be 'nat'
        }

        It 'Should pass VMwareNicType to config when specified' {
            $config = New-VMConfiguration @TestParams -VMwareNicType 'vmxnet3'
            $config.VMwareNicType | Should -Be 'vmxnet3'
        }

        It 'Should pass both VMware network settings when specified together' {
            $config = New-VMConfiguration @TestParams -VMwareNetworkType 'hostonly' -VMwareNicType 'e1000'
            $config.VMwareNetworkType | Should -Be 'hostonly'
            $config.VMwareNicType | Should -Be 'e1000'
        }
    }

    Context 'VMwareProvider Configuration Usage' {
        BeforeAll {
            # Check if VMware provider source file exists
            $script:VMwareProviderPath = Join-Path $ModulesPath 'FFU.Hypervisor\Providers\VMwareProvider.ps1'
        }

        It 'VMwareProvider should read NetworkType from config' {
            # Verify the provider code references Config.VMwareNetworkType
            $providerContent = Get-Content $VMwareProviderPath -Raw
            $providerContent | Should -Match '\$Config\.VMwareNetworkType'
        }

        It 'VMwareProvider should read NicType from config' {
            # Verify the provider code references Config.VMwareNicType
            $providerContent = Get-Content $VMwareProviderPath -Raw
            $providerContent | Should -Match '\$Config\.VMwareNicType'
        }

        It 'VMwareProvider should use null-coalescing for NetworkType default' {
            # Verify fallback to default if config value is null
            $providerContent = Get-Content $VMwareProviderPath -Raw
            $providerContent | Should -Match "VMwareNetworkType.*\?\?.*'bridged'"
        }

        It 'VMwareProvider should use null-coalescing for NicType default' {
            # Verify fallback to default if config value is null
            $providerContent = Get-Content $VMwareProviderPath -Raw
            $providerContent | Should -Match "VMwareNicType.*\?\?.*'e1000e'"
        }

        It 'VMwareProvider should NOT have hardcoded bridged network type' {
            # Verify the old hardcoded line is removed
            $providerContent = Get-Content $VMwareProviderPath -Raw
            # Should NOT match the old hardcoded pattern (hardcoded 'bridged' without config lookup)
            $providerContent | Should -Not -Match "-NetworkType\s+'bridged'\s+-NicType"
        }
    }

    Context 'Backward Compatibility' {
        It 'Existing code without VMware settings should work with defaults' {
            $config = New-VMConfiguration -Name 'LegacyVM' -Path 'C:\VMs\Legacy' `
                -MemoryBytes 4GB -ProcessorCount 2 -VirtualDiskPath 'C:\VMs\Legacy\disk.vhd'

            # Should have sensible defaults for VMware
            $config.VMwareNetworkType | Should -Be 'bridged'
            $config.VMwareNicType | Should -Be 'e1000e'
        }

        It 'Config validation should pass with VMware network settings' {
            $config = New-VMConfiguration -Name 'TestVM' -Path 'C:\VMs\Test' `
                -MemoryBytes 4GB -ProcessorCount 2 -VirtualDiskPath 'C:\VMs\Test\disk.vhd' `
                -VMwareNetworkType 'nat' -VMwareNicType 'vmxnet3'

            $config.Validate() | Should -BeTrue
        }
    }
}
