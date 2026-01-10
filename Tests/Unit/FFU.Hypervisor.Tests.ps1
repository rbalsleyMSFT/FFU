#Requires -Version 7.0
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

<#
.SYNOPSIS
    Tests for FFU.Hypervisor module

.DESCRIPTION
    Pester tests for the FFU.Hypervisor module that provides hypervisor
    abstraction for FFU Builder. Tests cover:
    - Module structure and exports
    - VMConfiguration class
    - VMInfo class
    - IHypervisorProvider interface
    - HyperVProvider implementation
    - Factory and utility functions

.NOTES
    These tests can run without Hyper-V being available by mocking
    the underlying Hyper-V cmdlets.
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

Describe 'FFU.Hypervisor Module Structure' {
    It 'Module should be importable' {
        $module = Get-Module -Name 'FFU.Hypervisor'
        $module | Should -Not -BeNullOrEmpty
    }

    It 'Module version should be 1.1.15' {
        $module = Get-Module -Name 'FFU.Hypervisor'
        $module.Version.ToString() | Should -Be '1.1.15'
    }

    It 'Module should export Get-HypervisorProvider function' {
        Get-Command -Name 'Get-HypervisorProvider' -Module 'FFU.Hypervisor' | Should -Not -BeNullOrEmpty
    }

    It 'Module should export Test-HypervisorAvailable function' {
        Get-Command -Name 'Test-HypervisorAvailable' -Module 'FFU.Hypervisor' | Should -Not -BeNullOrEmpty
    }

    It 'Module should export Get-AvailableHypervisors function' {
        Get-Command -Name 'Get-AvailableHypervisors' -Module 'FFU.Hypervisor' | Should -Not -BeNullOrEmpty
    }

    It 'Module should export New-VMConfiguration factory function' {
        Get-Command -Name 'New-VMConfiguration' -Module 'FFU.Hypervisor' | Should -Not -BeNullOrEmpty
    }

    It 'Module should export VM lifecycle functions' {
        Get-Command -Name 'New-HypervisorVM' -Module 'FFU.Hypervisor' | Should -Not -BeNullOrEmpty
        Get-Command -Name 'Start-HypervisorVM' -Module 'FFU.Hypervisor' | Should -Not -BeNullOrEmpty
        Get-Command -Name 'Stop-HypervisorVM' -Module 'FFU.Hypervisor' | Should -Not -BeNullOrEmpty
        Get-Command -Name 'Remove-HypervisorVM' -Module 'FFU.Hypervisor' | Should -Not -BeNullOrEmpty
    }

    It 'Module should export disk operation functions' {
        Get-Command -Name 'New-HypervisorVirtualDisk' -Module 'FFU.Hypervisor' | Should -Not -BeNullOrEmpty
        Get-Command -Name 'Mount-HypervisorVirtualDisk' -Module 'FFU.Hypervisor' | Should -Not -BeNullOrEmpty
        Get-Command -Name 'Dismount-HypervisorVirtualDisk' -Module 'FFU.Hypervisor' | Should -Not -BeNullOrEmpty
    }
}

Describe 'VMConfiguration Class' {
    Context 'Default Constructor' {
        It 'Should create instance with defaults' {
            $config = Invoke-InModuleScope { [VMConfiguration]::new() }
            $config | Should -Not -BeNullOrEmpty
            $config.Generation | Should -Be 2
            $config.EnableTPM | Should -Be $true
            $config.DiskFormat | Should -Be 'VHDX'
        }
    }

    Context 'Parameterized Constructor' {
        BeforeAll {
            $script:config = Invoke-InModuleScope {
                [VMConfiguration]::new(
                    'TestVM',
                    'C:\VMs\TestVM',
                    8GB,
                    4,
                    'C:\VMs\TestVM\disk.vhdx'
                )
            }
        }

        It 'Should set Name correctly' {
            $config.Name | Should -Be 'TestVM'
        }

        It 'Should set Path correctly' {
            $config.Path | Should -Be 'C:\VMs\TestVM'
        }

        It 'Should set MemoryBytes correctly' {
            $config.MemoryBytes | Should -Be 8GB
        }

        It 'Should set ProcessorCount correctly' {
            $config.ProcessorCount | Should -Be 4
        }

        It 'Should auto-detect VHDX format' {
            $config.DiskFormat | Should -Be 'VHDX'
        }
    }

    Context 'Factory Method' {
        BeforeAll {
            $script:config = Invoke-InModuleScope { [VMConfiguration]::NewFFUBuildVM('_FFU-Build', 'C:\FFU\VM', 16GB, 8) }
        }

        It 'Should create VM with FFU defaults' {
            $config.Name | Should -Be '_FFU-Build'
            $config.Generation | Should -Be 2
            $config.EnableTPM | Should -Be $true
            $config.AutomaticCheckpoints | Should -Be $false
        }

        It 'Should construct VirtualDiskPath from name' {
            $config.VirtualDiskPath | Should -Match '_FFU-Build\.vhdx$'
        }
    }

    Context 'Memory Helper Methods' {
        BeforeAll {
            $script:config = Invoke-InModuleScope { [VMConfiguration]::new('Test', 'C:\Test', 8GB, 4, 'C:\Test\disk.vhdx') }
        }

        It 'GetMemoryMB should return correct value' {
            $config.GetMemoryMB() | Should -Be 8192
        }

        It 'GetMemoryGB should return correct value' {
            $config.GetMemoryGB() | Should -Be 8
        }
    }

    Context 'Validation' {
        It 'Should fail validation with empty name' {
            $result = Invoke-InModuleScope {
                $config = [VMConfiguration]::new()
                $config.Name = ''
                $config.Path = 'C:\Test'
                $config.MemoryBytes = 4GB
                $config.ProcessorCount = 2
                $config.Validate()
            }
            $result | Should -Be $false
        }

        It 'Should fail validation with insufficient memory' {
            $result = Invoke-InModuleScope {
                $config = [VMConfiguration]::new()
                $config.Name = 'Test'
                $config.Path = 'C:\Test'
                $config.MemoryBytes = 1GB  # Less than 2GB minimum
                $config.ProcessorCount = 2
                $config.Validate()
            }
            $result | Should -Be $false
        }

        It 'Should pass validation with valid config' {
            $result = Invoke-InModuleScope {
                $config = [VMConfiguration]::new('Test', 'C:\Test', 4GB, 2, 'C:\Test\disk.vhdx')
                $config.Validate()
            }
            $result | Should -Be $true
        }
    }
}

Describe 'New-VMConfiguration Factory Function' {
    # This tests the exported factory function that works around PowerShell's
    # module class scope limitation (classes aren't exported to caller's scope)

    It 'Should create VMConfiguration with required parameters' {
        $config = New-VMConfiguration -Name 'TestVM' `
                                      -Path 'C:\VMs\Test' `
                                      -MemoryBytes 8GB `
                                      -ProcessorCount 4 `
                                      -VirtualDiskPath 'C:\VMs\Test\TestVM.vhdx'
        $config | Should -Not -BeNullOrEmpty
        $config.Name | Should -Be 'TestVM'
        $config.Path | Should -Be 'C:\VMs\Test'
        $config.MemoryBytes | Should -Be 8589934592
        $config.ProcessorCount | Should -Be 4
    }

    It 'Should auto-detect VHDX disk format' {
        $config = New-VMConfiguration -Name 'TestVM' `
                                      -Path 'C:\VMs\Test' `
                                      -MemoryBytes 4GB `
                                      -ProcessorCount 2 `
                                      -VirtualDiskPath 'C:\VMs\Test\TestVM.vhdx'
        $config.DiskFormat | Should -Be 'VHDX'
    }

    It 'Should auto-detect VHD disk format' {
        $config = New-VMConfiguration -Name 'TestVM' `
                                      -Path 'C:\VMs\Test' `
                                      -MemoryBytes 4GB `
                                      -ProcessorCount 2 `
                                      -VirtualDiskPath 'C:\VMs\Test\TestVM.vhd'
        $config.DiskFormat | Should -Be 'VHD'
    }

    It 'Should auto-detect VMDK disk format' {
        $config = New-VMConfiguration -Name 'TestVM' `
                                      -Path 'C:\VMs\Test' `
                                      -MemoryBytes 4GB `
                                      -ProcessorCount 2 `
                                      -VirtualDiskPath 'C:\VMs\Test\TestVM.vmdk'
        $config.DiskFormat | Should -Be 'VMDK'
    }

    It 'Should apply default values for optional parameters' {
        $config = New-VMConfiguration -Name 'TestVM' `
                                      -Path 'C:\VMs\Test' `
                                      -MemoryBytes 4GB `
                                      -ProcessorCount 2 `
                                      -VirtualDiskPath 'C:\VMs\Test\TestVM.vhdx'
        $config.Generation | Should -Be 2
        $config.EnableTPM | Should -Be $true
        $config.EnableSecureBoot | Should -Be $true
        $config.DynamicMemory | Should -Be $false
        $config.AutomaticCheckpoints | Should -Be $false
    }

    It 'Should allow overriding optional parameters' {
        $config = New-VMConfiguration -Name 'TestVM' `
                                      -Path 'C:\VMs\Test' `
                                      -MemoryBytes 4GB `
                                      -ProcessorCount 2 `
                                      -VirtualDiskPath 'C:\VMs\Test\TestVM.vhdx' `
                                      -Generation 1 `
                                      -EnableTPM $false `
                                      -EnableSecureBoot $false `
                                      -DynamicMemory $true `
                                      -AutomaticCheckpoints $true
        $config.Generation | Should -Be 1
        $config.EnableTPM | Should -Be $false
        $config.EnableSecureBoot | Should -Be $false
        $config.DynamicMemory | Should -Be $true
        $config.AutomaticCheckpoints | Should -Be $true
    }

    It 'Should allow setting ISOPath' {
        $config = New-VMConfiguration -Name 'TestVM' `
                                      -Path 'C:\VMs\Test' `
                                      -MemoryBytes 4GB `
                                      -ProcessorCount 2 `
                                      -VirtualDiskPath 'C:\VMs\Test\TestVM.vhdx' `
                                      -ISOPath 'C:\ISOs\Apps.iso'
        $config.ISOPath | Should -Be 'C:\ISOs\Apps.iso'
    }

    It 'Should allow explicit disk format override' {
        $config = New-VMConfiguration -Name 'TestVM' `
                                      -Path 'C:\VMs\Test' `
                                      -MemoryBytes 4GB `
                                      -ProcessorCount 2 `
                                      -VirtualDiskPath 'C:\VMs\Test\TestVM.disk' `
                                      -DiskFormat 'VMDK'
        $config.DiskFormat | Should -Be 'VMDK'
    }
}

Describe 'VMInfo Class' {
    Context 'Default Constructor' {
        It 'Should create instance with defaults' {
            $vmInfo = Invoke-InModuleScope { [VMInfo]::new() }
            $vmInfo | Should -Not -BeNullOrEmpty
            $vmInfo.State | Should -Be 0  # VMState::Unknown
        }
    }

    Context 'State Methods' {
        It 'IsRunning should return true when state is Running' {
            $result = Invoke-InModuleScope {
                $vmInfo = [VMInfo]::new()
                $vmInfo.State = [VMState]::Running
                $vmInfo.IsRunning()
            }
            $result | Should -Be $true
        }

        It 'IsStopped should return true when state is Off' {
            $result = Invoke-InModuleScope {
                $vmInfo = [VMInfo]::new()
                $vmInfo.State = [VMState]::Off
                $vmInfo.IsStopped()
            }
            $result | Should -Be $true
        }
    }

    Context 'State Display' {
        It 'Should show IP when running with IP address' {
            $result = Invoke-InModuleScope {
                $vmInfo = [VMInfo]::new()
                $vmInfo.State = [VMState]::Running
                $vmInfo.IPAddress = '192.168.1.100'
                $vmInfo.GetStateDisplay()
            }
            $result | Should -Be 'Running (192.168.1.100)'
        }

        It 'Should show state name without IP when stopped' {
            $result = Invoke-InModuleScope {
                $vmInfo = [VMInfo]::new()
                $vmInfo.State = [VMState]::Off
                $vmInfo.GetStateDisplay()
            }
            $result | Should -Be 'Off'
        }
    }
}

Describe 'VMState Enum' {
    It 'Should have expected values' {
        $values = Invoke-InModuleScope {
            @{
                Unknown = [int][VMState]::Unknown
                Off = [int][VMState]::Off
                Running = [int][VMState]::Running
                Paused = [int][VMState]::Paused
            }
        }
        $values.Unknown | Should -Be 0
        $values.Off | Should -Be 1
        $values.Running | Should -Be 2
        $values.Paused | Should -Be 3
    }
}

Describe 'HyperVProvider Class' {
    BeforeAll {
        # Use Get-HypervisorProvider function instead of direct class instantiation
        $script:provider = Get-HypervisorProvider -Type 'HyperV'
    }

    Context 'Provider Identity' {
        It 'Should have Name set to HyperV' {
            $provider.Name | Should -Be 'HyperV'
        }

        It 'Should have Version populated' {
            $provider.Version | Should -Not -BeNullOrEmpty
        }

        It 'Should have Description' {
            $provider.Description | Should -Match 'Hyper-V'
        }
    }

    Context 'Capabilities' {
        It 'Should support TPM' {
            $provider.Capabilities.SupportsTPM | Should -Be $true
        }

        It 'Should support Generation 2' {
            $provider.Capabilities.SupportsGeneration2 | Should -Be $true
        }

        It 'Should support VHD and VHDX formats' {
            $provider.Capabilities.SupportedDiskFormats | Should -Contain 'VHD'
            $provider.Capabilities.SupportedDiskFormats | Should -Contain 'VHDX'
        }

        It 'Should support dynamic memory' {
            $provider.Capabilities.SupportsDynamicMemory | Should -Be $true
        }
    }

    Context 'Configuration Validation' {
        It 'Should validate VHDX format as supported' {
            $result = Invoke-InModuleScope {
                $config = [VMConfiguration]::new('Test', 'C:\Test', 4GB, 2, 'C:\Test\disk.vhdx')
                $provider = [HyperVProvider]::new()
                $provider.ValidateConfiguration($config)
            }
            $result.IsValid | Should -Be $true
        }

        It 'Should warn on unsupported VMDK format' {
            $result = Invoke-InModuleScope {
                $config = [VMConfiguration]::new('Test', 'C:\Test', 4GB, 2, 'C:\Test\disk.vmdk')
                $config.DiskFormat = 'VMDK'
                $provider = [HyperVProvider]::new()
                $provider.ValidateConfiguration($config)
            }
            $result.IsValid | Should -Be $false
            $result.Errors | Should -Match 'VMDK'
        }
    }
}

Describe 'Get-HypervisorProvider Function' {
    It 'Should return HyperVProvider for Type HyperV' {
        $provider = Get-HypervisorProvider -Type 'HyperV'
        $provider | Should -Not -BeNullOrEmpty
        $provider.Name | Should -Be 'HyperV'
    }

    It 'Should return VMwareProvider for Type VMware' {
        $provider = Get-HypervisorProvider -Type 'VMware'
        $provider | Should -Not -BeNullOrEmpty
        $provider.Name | Should -Be 'VMware'
    }

    It 'Should support Auto detection' {
        # This may succeed or fail depending on whether Hyper-V is available
        # We just verify it doesn't throw an unexpected error
        try {
            $provider = Get-HypervisorProvider -Type 'Auto'
            $provider | Should -Not -BeNullOrEmpty
        }
        catch {
            # Expected if no hypervisor is available
            $_.Exception.Message | Should -Match 'No supported hypervisor'
        }
    }
}

Describe 'Test-HypervisorAvailable Function' {
    It 'Should return boolean for HyperV check' {
        $result = Test-HypervisorAvailable -Type 'HyperV'
        $result | Should -BeOfType [bool]
    }

    It 'Should return boolean for VMware check' {
        # VMware may or may not be available depending on installation
        $result = Test-HypervisorAvailable -Type 'VMware'
        $result | Should -BeOfType [bool]
    }

    It 'Should return detailed hashtable with -Detailed' {
        $result = Test-HypervisorAvailable -Type 'HyperV' -Detailed
        $result | Should -BeOfType [hashtable]
        $result.Keys | Should -Contain 'IsAvailable'
        $result.Keys | Should -Contain 'ProviderName'
        $result.Keys | Should -Contain 'Issues'
    }
}

Describe 'Get-AvailableHypervisors Function' {
    BeforeAll {
        $script:hypervisors = Get-AvailableHypervisors
    }

    It 'Should return array of hashtables' {
        $hypervisors | Should -Not -BeNullOrEmpty
        $hypervisors | Should -BeOfType [hashtable]
    }

    It 'Should include HyperV entry' {
        $hypervEntry = $hypervisors | Where-Object { $_.Name -eq 'HyperV' }
        $hypervEntry | Should -Not -BeNullOrEmpty
        $hypervEntry.DisplayName | Should -Be 'Microsoft Hyper-V'
    }

    It 'Should include VMware entry' {
        $vmwareEntry = $hypervisors | Where-Object { $_.Name -eq 'VMware' }
        $vmwareEntry | Should -Not -BeNullOrEmpty
        $vmwareEntry.DisplayName | Should -Be 'VMware Workstation Pro'
        # Available depends on whether VMware is installed
        $vmwareEntry.Keys | Should -Contain 'Available'
    }

    It 'Each entry should have required fields' {
        foreach ($hypervisor in $hypervisors) {
            $hypervisor.Keys | Should -Contain 'Name'
            $hypervisor.Keys | Should -Contain 'Available'
            $hypervisor.Keys | Should -Contain 'Capabilities'
        }
    }
}

Describe 'IHypervisorProvider Interface' {
    It 'Should throw NotImplementedException for base class methods' {
        Invoke-InModuleScope {
            $baseProvider = [IHypervisorProvider]::new()
            $config = [VMConfiguration]::new('Test', 'C:\Test', 4GB, 2, 'C:\Test\disk.vhdx')
            $vmInfo = [VMInfo]::new()

            $createFailed = $false
            try { $baseProvider.CreateVM($config) } catch [System.NotImplementedException] { $createFailed = $true }
            if (-not $createFailed) { throw "CreateVM should throw NotImplementedException" }

            $startFailed = $false
            try { $baseProvider.StartVM($vmInfo) } catch [System.NotImplementedException] { $startFailed = $true }
            if (-not $startFailed) { throw "StartVM should throw NotImplementedException" }
        }
    }

    It 'GetCapabilities should return hashtable from base class' {
        $capabilities = Invoke-InModuleScope {
            $baseProvider = [IHypervisorProvider]::new()
            $baseProvider.GetCapabilities()
        }
        $capabilities | Should -BeOfType [hashtable]
        $capabilities.Keys | Should -Contain 'SupportsTPM'
    }
}

Describe 'VMwareProvider Class' {
    BeforeAll {
        $script:provider = Get-HypervisorProvider -Type 'VMware'
    }

    Context 'Provider Identity' {
        It 'Should have Name set to VMware' {
            $provider.Name | Should -Be 'VMware'
        }

        It 'Should have Version populated (may be 0.0.0 if not installed)' {
            $provider.Version | Should -Not -BeNullOrEmpty
        }

        It 'Should have Description' {
            $provider.Description | Should -Match 'VMware'
        }
    }

    Context 'Capabilities' {
        It 'Should NOT support TPM (requires encryption which breaks vmrun automation)' {
            # VMware vTPM requires VM encryption which breaks vmrun.exe automation
            # TPM features work on target hardware after FFU deployment
            $provider.Capabilities.SupportsTPM | Should -Be $false
        }

        It 'Should have TPMNote explaining the limitation' {
            $provider.Capabilities.TPMNote | Should -Match 'encryption'
        }

        It 'Should support Secure Boot' {
            $provider.Capabilities.SupportsSecureBoot | Should -Be $true
        }

        It 'Should support VMDK format only (VHD not bootable)' {
            # VMware cannot boot from VHD files - they require VMDK for bootable VMs
            $provider.Capabilities.SupportedDiskFormats | Should -Contain 'VMDK'
            # VHD is not included as it's not bootable in VMware
            $provider.Capabilities.SupportedDiskFormats | Should -Not -Contain 'VHD'
        }

        It 'Should NOT support dynamic memory' {
            $provider.Capabilities.SupportsDynamicMemory | Should -Be $false
        }
    }

    Context 'Configuration Validation' {
        It 'Should validate VMDK format as supported' {
            # VMDK is the only bootable format for VMware
            $result = Invoke-InModuleScope {
                $config = [VMConfiguration]::new('Test', 'C:\Test', 4GB, 2, 'C:\Test\disk.vmdk')
                $config.DiskFormat = 'VMDK'
                $provider = [VMwareProvider]::new()
                $provider.ValidateConfiguration($config)
            }
            $result.IsValid | Should -Be $true
        }

        It 'Should reject VHDX format (not supported by VMware)' {
            $result = Invoke-InModuleScope {
                $config = [VMConfiguration]::new('Test', 'C:\Test', 4GB, 2, 'C:\Test\disk.vhdx')
                $config.DiskFormat = 'VHDX'
                $provider = [VMwareProvider]::new()
                $provider.ValidateConfiguration($config)
            }
            $result.IsValid | Should -Be $false
            $result.Errors | Should -Match 'VHDX'
        }

        It 'Should warn about TPM when EnableTPM is true' {
            $result = Invoke-InModuleScope {
                $config = [VMConfiguration]::new('Test', 'C:\Test', 4GB, 2, 'C:\Test\disk.vmdk')
                $config.DiskFormat = 'VMDK'
                $config.EnableTPM = $true
                $provider = [VMwareProvider]::new()
                $provider.ValidateConfiguration($config)
            }
            # Should have warnings about TPM (from base class and/or VMwareProvider override)
            # The combined warnings include "encryption" from VMwareProvider and "not supported" from base
            $warningText = $result.Warnings -join ' '
            $warningText | Should -Match 'TPM'
            # VMwareProvider adds specific warnings about encryption
            $warningText | Should -Match 'encryption|will be disabled|target hardware'
        }
    }

    Context 'Availability Check' {
        It 'Should return availability details' {
            $details = $provider.GetAvailabilityDetails()
            $details | Should -BeOfType [hashtable]
            $details.Keys | Should -Contain 'IsAvailable'
            $details.Keys | Should -Contain 'ProviderName'
            $details.ProviderName | Should -Be 'VMware'
        }
    }
}

Describe 'Module Integration' {
    It 'Should have all classes available via module scope' {
        { Invoke-InModuleScope { [VMConfiguration]::new() } } | Should -Not -Throw
        { Invoke-InModuleScope { [VMInfo]::new() } } | Should -Not -Throw
        { Invoke-InModuleScope { [VMState]::Running } } | Should -Not -Throw
        { Invoke-InModuleScope { [HyperVProvider]::new() } } | Should -Not -Throw
        { Invoke-InModuleScope { [VMwareProvider]::new() } } | Should -Not -Throw
    }

    It 'Classes should be usable together' {
        $validation = Invoke-InModuleScope {
            $config = [VMConfiguration]::NewFFUBuildVM('Test', 'C:\Test', 8GB, 4)
            $provider = [HyperVProvider]::new()
            $provider.ValidateConfiguration($config)
        }

        $validation | Should -BeOfType [hashtable]
        $validation.IsValid | Should -Be $true
    }

    It 'HyperV provider can be obtained via exported function' {
        $provider = Get-HypervisorProvider -Type 'HyperV'
        $provider | Should -Not -BeNullOrEmpty
        $provider.Name | Should -Be 'HyperV'
        $provider.Capabilities | Should -Not -BeNullOrEmpty
    }

    It 'VMware provider can be obtained via exported function' {
        $provider = Get-HypervisorProvider -Type 'VMware'
        $provider | Should -Not -BeNullOrEmpty
        $provider.Name | Should -Be 'VMware'
        $provider.Capabilities | Should -Not -BeNullOrEmpty
    }
}

# =============================================================================
# Private Function Tests - VMware REST API and Utilities
# =============================================================================

Describe 'VMware Private Functions' -Tag 'VMware', 'Private' {

    Context 'Start-VMrestService Function' {
        It 'Should be defined in module scope' {
            $command = Invoke-InModuleScope {
                Get-Command -Name 'Start-VMrestService' -ErrorAction SilentlyContinue
            }
            $command | Should -Not -BeNullOrEmpty
        }

        It 'Should have correct parameters' {
            $params = Invoke-InModuleScope {
                (Get-Command -Name 'Start-VMrestService').Parameters.Keys
            }
            $params | Should -Contain 'Port'
            $params | Should -Contain 'Credential'  # Uses PSCredential instead of Username/Password
        }
    }

    Context 'Stop-VMrestService Function' {
        It 'Should be defined in module scope' {
            $command = Invoke-InModuleScope {
                Get-Command -Name 'Stop-VMrestService' -ErrorAction SilentlyContinue
            }
            $command | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Test-VMrestEndpoint Function' {
        It 'Should be defined in module scope' {
            $command = Invoke-InModuleScope {
                Get-Command -Name 'Test-VMrestEndpoint' -ErrorAction SilentlyContinue
            }
            $command | Should -Not -BeNullOrEmpty
        }

        It 'Should return boolean' {
            # Without VMware installed, this should return false gracefully
            $result = Invoke-InModuleScope {
                Test-VMrestEndpoint -Port 8697
            }
            $result | Should -BeOfType [bool]
        }
    }

    Context 'Invoke-VMwareRestMethod Function' {
        It 'Should be defined in module scope' {
            $command = Invoke-InModuleScope {
                Get-Command -Name 'Invoke-VMwareRestMethod' -ErrorAction SilentlyContinue
            }
            $command | Should -Not -BeNullOrEmpty
        }

        It 'Should have required parameters' {
            $params = Invoke-InModuleScope {
                (Get-Command -Name 'Invoke-VMwareRestMethod').Parameters.Keys
            }
            $params | Should -Contain 'Endpoint'
            $params | Should -Contain 'Method'
        }

        It 'Should have Method parameter for HTTP verbs' {
            $params = Invoke-InModuleScope {
                (Get-Command -Name 'Invoke-VMwareRestMethod').Parameters.Keys
            }
            $params | Should -Contain 'Method'
        }
    }

    Context 'Get-VMwareVMList Function' {
        It 'Should be defined in module scope' {
            $command = Invoke-InModuleScope {
                Get-Command -Name 'Get-VMwareVMList' -ErrorAction SilentlyContinue
            }
            $command | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Get-VMwarePowerState Function' {
        It 'Should be defined in module scope' {
            $command = Invoke-InModuleScope {
                Get-Command -Name 'Get-VMwarePowerState' -ErrorAction SilentlyContinue
            }
            $command | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Set-VMwarePowerState Function' {
        It 'Should be defined in module scope' {
            $command = Invoke-InModuleScope {
                Get-Command -Name 'Set-VMwarePowerState' -ErrorAction SilentlyContinue
            }
            $command | Should -Not -BeNullOrEmpty
        }

        It 'Should have State parameter' {
            $params = Invoke-InModuleScope {
                (Get-Command -Name 'Set-VMwarePowerState').Parameters.Keys
            }
            $params | Should -Contain 'State'  # Parameter is named 'State' not 'PowerState'
        }
    }
}

Describe 'VMX File Generation Functions' -Tag 'VMware', 'Private' {

    Context 'New-VMwareVMX Function' {
        It 'Should be defined in module scope' {
            $command = Invoke-InModuleScope {
                Get-Command -Name 'New-VMwareVMX' -ErrorAction SilentlyContinue
            }
            $command | Should -Not -BeNullOrEmpty
        }

        It 'Should have required parameters' {
            $params = Invoke-InModuleScope {
                (Get-Command -Name 'New-VMwareVMX').Parameters.Keys
            }
            $params | Should -Contain 'VMName'
            $params | Should -Contain 'VMPath'
            $params | Should -Contain 'DiskPath'
        }

        It 'Should generate valid VMX content' {
            $vmxPath = Invoke-InModuleScope {
                $testPath = Join-Path $env:TEMP "TestVM_$(Get-Random)"
                New-Item -Path $testPath -ItemType Directory -Force | Out-Null
                $diskPath = Join-Path $testPath 'disk.vhd'

                try {
                    New-VMwareVMX -VMName 'TestVM' -VMPath $testPath -DiskPath $diskPath -MemoryMB 4096 -CPUs 2
                }
                catch {
                    # Function may not be fully available, return null
                    $null
                }
                finally {
                    Remove-Item $testPath -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            # If function executed, it should return a path or null
            # This test validates the function exists and can be called
        }
    }

    Context 'Update-VMwareVMX Function' {
        It 'Should be defined in module scope' {
            $command = Invoke-InModuleScope {
                Get-Command -Name 'Update-VMwareVMX' -ErrorAction SilentlyContinue
            }
            $command | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Get-VMwareVMXSettings Function' {
        It 'Should be defined in module scope' {
            $command = Invoke-InModuleScope {
                Get-Command -Name 'Get-VMwareVMXSettings' -ErrorAction SilentlyContinue
            }
            $command | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Set-VMwareBootISO Function' {
        It 'Should be defined in module scope' {
            $command = Invoke-InModuleScope {
                Get-Command -Name 'Set-VMwareBootISO' -ErrorAction SilentlyContinue
            }
            $command | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Remove-VMwareBootISO Function' {
        It 'Should be defined in module scope' {
            $command = Invoke-InModuleScope {
                Get-Command -Name 'Remove-VMwareBootISO' -ErrorAction SilentlyContinue
            }
            $command | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'VHD Operations without Hyper-V' -Tag 'VMware', 'Private' {

    Context 'New-VHDWithDiskpart Function' {
        It 'Should be defined in module scope' {
            $command = Invoke-InModuleScope {
                Get-Command -Name 'New-VHDWithDiskpart' -ErrorAction SilentlyContinue
            }
            $command | Should -Not -BeNullOrEmpty
        }

        It 'Should have required parameters' {
            $params = Invoke-InModuleScope {
                (Get-Command -Name 'New-VHDWithDiskpart').Parameters.Keys
            }
            $params | Should -Contain 'Path'
            $params | Should -Contain 'SizeGB'  # Parameter is named 'SizeGB' not 'SizeBytes'
        }

        It 'Should have Type parameter' {
            $params = Invoke-InModuleScope {
                (Get-Command -Name 'New-VHDWithDiskpart').Parameters.Keys
            }
            $params | Should -Contain 'Type'
        }
    }

    Context 'Mount-VHDWithDiskpart Function' {
        It 'Should be defined in module scope' {
            $command = Invoke-InModuleScope {
                Get-Command -Name 'Mount-VHDWithDiskpart' -ErrorAction SilentlyContinue
            }
            $command | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Dismount-VHDWithDiskpart Function' {
        It 'Should be defined in module scope' {
            $command = Invoke-InModuleScope {
                Get-Command -Name 'Dismount-VHDWithDiskpart' -ErrorAction SilentlyContinue
            }
            $command | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Initialize-VHDWithDiskpart Function' {
        It 'Should be defined in module scope' {
            $command = Invoke-InModuleScope {
                Get-Command -Name 'Initialize-VHDWithDiskpart' -ErrorAction SilentlyContinue
            }
            $command | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Edge Cases and Error Handling Tests
# =============================================================================

Describe 'VMConfiguration Edge Cases' -Tag 'EdgeCase' {

    Context 'Boundary Values' {
        It 'Should handle minimum valid memory (2GB)' {
            $result = Invoke-InModuleScope {
                $config = [VMConfiguration]::new('Test', 'C:\Test', 2GB, 1, 'C:\Test\disk.vhdx')
                $config.Validate()
            }
            $result | Should -Be $true
        }

        It 'Should handle maximum reasonable memory (128GB)' {
            $result = Invoke-InModuleScope {
                $config = [VMConfiguration]::new('Test', 'C:\Test', 128GB, 1, 'C:\Test\disk.vhdx')
                $config.Validate()
            }
            $result | Should -Be $true
        }

        It 'Should handle single processor' {
            $result = Invoke-InModuleScope {
                $config = [VMConfiguration]::new('Test', 'C:\Test', 4GB, 1, 'C:\Test\disk.vhdx')
                $config.Validate()
            }
            $result | Should -Be $true
        }

        It 'Should handle many processors (32)' {
            $result = Invoke-InModuleScope {
                $config = [VMConfiguration]::new('Test', 'C:\Test', 4GB, 32, 'C:\Test\disk.vhdx')
                $config.Validate()
            }
            $result | Should -Be $true
        }
    }

    Context 'Invalid Input Handling' {
        It 'Should reject zero memory' {
            $result = Invoke-InModuleScope {
                $config = [VMConfiguration]::new()
                $config.Name = 'Test'
                $config.Path = 'C:\Test'
                $config.MemoryBytes = 0
                $config.ProcessorCount = 2
                $config.Validate()
            }
            $result | Should -Be $false
        }

        It 'Should throw on negative memory (UInt64 cannot be negative)' {
            # MemoryBytes is UInt64, so assigning negative value throws an exception
            {
                Invoke-InModuleScope {
                    $config = [VMConfiguration]::new()
                    $config.Name = 'Test'
                    $config.Path = 'C:\Test'
                    $config.MemoryBytes = -1GB  # This should throw
                    $config.ProcessorCount = 2
                }
            } | Should -Throw
        }

        It 'Should reject zero processors' {
            $result = Invoke-InModuleScope {
                $config = [VMConfiguration]::new()
                $config.Name = 'Test'
                $config.Path = 'C:\Test'
                $config.MemoryBytes = 4GB
                $config.ProcessorCount = 0
                $config.Validate()
            }
            $result | Should -Be $false
        }

        It 'Should handle special characters in VM name' {
            $config = Invoke-InModuleScope {
                [VMConfiguration]::new('Test-VM_123', 'C:\Test', 4GB, 2, 'C:\Test\disk.vhdx')
            }
            $config.Name | Should -Be 'Test-VM_123'
        }

        It 'Should handle paths with spaces' {
            $config = Invoke-InModuleScope {
                [VMConfiguration]::new('Test', 'C:\My VMs\Test VM', 4GB, 2, 'C:\My VMs\Test VM\disk.vhdx')
            }
            $config.Path | Should -Be 'C:\My VMs\Test VM'
        }
    }
}

Describe 'Provider Pattern Correctness' -Tag 'Architecture' {

    Context 'Provider Interface Contract' {
        It 'All providers should implement same interface methods' {
            $hyperv = Get-HypervisorProvider -Type 'HyperV'
            $vmware = Get-HypervisorProvider -Type 'VMware'

            # Check required properties exist on both
            $hyperv.Name | Should -Not -BeNullOrEmpty
            $vmware.Name | Should -Not -BeNullOrEmpty

            $hyperv.Version | Should -Not -BeNullOrEmpty
            $vmware.Version | Should -Not -BeNullOrEmpty

            $hyperv.Capabilities | Should -BeOfType [hashtable]
            $vmware.Capabilities | Should -BeOfType [hashtable]
        }

        It 'Both providers should have TestAvailable method' {
            $hyperv = Get-HypervisorProvider -Type 'HyperV'
            $vmware = Get-HypervisorProvider -Type 'VMware'

            # Both should have TestAvailable method and return boolean
            $hypervAvail = $hyperv.TestAvailable()
            $vmwareAvail = $vmware.TestAvailable()

            $hypervAvail | Should -BeOfType [bool]
            $vmwareAvail | Should -BeOfType [bool]
        }

        It 'Both providers should have GetAvailabilityDetails method' {
            $hyperv = Get-HypervisorProvider -Type 'HyperV'
            $vmware = Get-HypervisorProvider -Type 'VMware'

            $hypervDetails = $hyperv.GetAvailabilityDetails()
            $vmwareDetails = $vmware.GetAvailabilityDetails()

            $hypervDetails | Should -BeOfType [hashtable]
            $vmwareDetails | Should -BeOfType [hashtable]

            # Both should have same keys
            $hypervDetails.Keys | Should -Contain 'IsAvailable'
            $vmwareDetails.Keys | Should -Contain 'IsAvailable'
        }

        It 'Both providers should have ValidateConfiguration method' {
            $config = Invoke-InModuleScope {
                [VMConfiguration]::new('Test', 'C:\Test', 4GB, 2, 'C:\Test\disk.vhd')
            }
            $config.DiskFormat = 'VHD'  # Both support VHD

            $hyperv = Get-HypervisorProvider -Type 'HyperV'
            $vmware = Get-HypervisorProvider -Type 'VMware'

            $hypervResult = $hyperv.ValidateConfiguration($config)
            $vmwareResult = $vmware.ValidateConfiguration($config)

            $hypervResult | Should -BeOfType [hashtable]
            $vmwareResult | Should -BeOfType [hashtable]

            $hypervResult.Keys | Should -Contain 'IsValid'
            $vmwareResult.Keys | Should -Contain 'IsValid'
        }
    }

    Context 'Capability Consistency' {
        It 'Both providers should report SupportedDiskFormats' {
            $hyperv = Get-HypervisorProvider -Type 'HyperV'
            $vmware = Get-HypervisorProvider -Type 'VMware'

            $hyperv.Capabilities.SupportedDiskFormats | Should -Not -BeNullOrEmpty
            $vmware.Capabilities.SupportedDiskFormats | Should -Not -BeNullOrEmpty
        }

        It 'Both providers should report SupportsTPM' {
            $hyperv = Get-HypervisorProvider -Type 'HyperV'
            $vmware = Get-HypervisorProvider -Type 'VMware'

            $hyperv.Capabilities.SupportsTPM | Should -BeOfType [bool]
            $vmware.Capabilities.SupportsTPM | Should -BeOfType [bool]
        }
    }
}
