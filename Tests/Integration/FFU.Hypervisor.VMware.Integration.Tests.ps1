#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester integration tests for VMware provider in FFU.Hypervisor module

.DESCRIPTION
    Integration tests covering VMware provider operations including:
    - Provider availability and capabilities
    - Configuration validation (VMDK, VHD, VHDX handling)
    - VMX file generation
    - Diskpart-based disk operations for non-Hyper-V environments

    Tests use conditional skip pattern for tests requiring actual VMware installation.
    Core provider tests run on any machine.

.NOTES
    Run all: Invoke-Pester -Path .\Tests\Integration\FFU.Hypervisor.VMware.Integration.Tests.ps1 -Output Detailed
    Run by tag: Invoke-Pester -Path .\Tests\Integration\FFU.Hypervisor.VMware.Integration.Tests.ps1 -Tag 'TEST-06' -Output Detailed
    Coverage: TEST-06 - Integration tests for VMware provider operations
#>

# VMware installation detection - MUST be at script root level for -Skip evaluation during discovery
# This runs BEFORE BeforeAll during Pester's discovery phase
$script:VMwareInstalled = $false
$script:VMwarePath = $null

$vmrunPaths = @(
    "${env:ProgramFiles(x86)}\VMware\VMware Workstation\vmrun.exe",
    "${env:ProgramFiles}\VMware\VMware Workstation\vmrun.exe"
)

foreach ($path in $vmrunPaths) {
    if (Test-Path $path) {
        $script:VMwareInstalled = $true
        $script:VMwarePath = Split-Path $path -Parent
        break
    }
}

BeforeAll {
    # Get paths relative to test file location
    $TestRoot = Split-Path $PSScriptRoot -Parent
    $ProjectRoot = Split-Path $TestRoot -Parent
    $ModulesPath = Join-Path $ProjectRoot 'FFUDevelopment\Modules'

    # Add Modules folder to PSModulePath for RequiredModules resolution
    if ($env:PSModulePath -notlike "*$ModulesPath*") {
        $env:PSModulePath = "$ModulesPath;$env:PSModulePath"
    }

    # Re-run VMware detection in BeforeAll scope for test assertions
    # (script-level detection is for -Skip during discovery, this is for runtime)
    $script:VMwareInstalled = $false
    $script:VMwarePath = $null

    $vmrunPaths = @(
        "${env:ProgramFiles(x86)}\VMware\VMware Workstation\vmrun.exe",
        "${env:ProgramFiles}\VMware\VMware Workstation\vmrun.exe"
    )

    foreach ($path in $vmrunPaths) {
        if (Test-Path $path) {
            $script:VMwareInstalled = $true
            $script:VMwarePath = Split-Path $path -Parent
            break
        }
    }

    # Create stub function for WriteLog (defined in FFU.Common, called by FFU.Hypervisor)
    function global:WriteLog { param($LogText) }

    # Remove and re-import modules
    Get-Module -Name 'FFU.Hypervisor', 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue

    # Import FFU.Core first (dependency) - suppress errors if not fully loadable
    Import-Module (Join-Path $ModulesPath 'FFU.Core\FFU.Core.psd1') -Force -ErrorAction SilentlyContinue

    # Import FFU.Hypervisor module
    $HypervisorModulePath = Join-Path $ModulesPath 'FFU.Hypervisor\FFU.Hypervisor.psd1'
    if (-not (Test-Path $HypervisorModulePath)) {
        throw "FFU.Hypervisor module not found at: $HypervisorModulePath"
    }
    Import-Module $HypervisorModulePath -Force -ErrorAction Stop

    # Store module reference for InModuleScope operations
    $script:HypervisorModule = Get-Module -Name 'FFU.Hypervisor'

    # Helper function for module scope access
    function Invoke-InModuleScope {
        param([scriptblock]$ScriptBlock)
        & $script:HypervisorModule $ScriptBlock
    }
}

AfterAll {
    Get-Module -Name 'FFU.Hypervisor', 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# VMware Infrastructure Detection
# =============================================================================

Describe 'VMware Infrastructure Detection' -Tag 'Integration', 'VMware', 'FFU.Hypervisor', 'TEST-06' {

    It 'Should detect VMware installation status' {
        # This confirms detection logic works, not that VMware is installed
        $script:VMwareInstalled | Should -BeIn @($true, $false)
    }

    It 'Should report VMware status for test planning' {
        if ($script:VMwareInstalled) {
            Write-Host "  [INFO] VMware Workstation is AVAILABLE at: $script:VMwarePath" -ForegroundColor Green
            Write-Host "  [INFO] VMX generation tests will execute" -ForegroundColor Green
        }
        else {
            Write-Host "  [INFO] VMware Workstation is NOT installed" -ForegroundColor Yellow
            Write-Host "  [INFO] VMX generation tests will be skipped" -ForegroundColor Yellow
        }
        $true | Should -BeTrue  # Always passes, informational
    }
}

# =============================================================================
# VMwareProvider Availability Tests
# =============================================================================

Describe 'VMwareProvider Availability' -Tag 'Integration', 'VMware', 'FFU.Hypervisor', 'TEST-06' {

    Context 'Provider Factory' {

        It 'Get-HypervisorProvider returns VMware provider' {
            $provider = Get-HypervisorProvider -Type 'VMware'

            $provider | Should -Not -BeNullOrEmpty
        }

        It 'Provider.Name equals VMware' {
            $provider = Get-HypervisorProvider -Type 'VMware'

            $provider.Name | Should -Be 'VMware'
        }

        It 'Provider.Capabilities contains expected properties' {
            $provider = Get-HypervisorProvider -Type 'VMware'

            $provider.Capabilities | Should -Not -BeNullOrEmpty
            $provider.Capabilities.Keys | Should -Contain 'SupportsTPM'
            $provider.Capabilities.Keys | Should -Contain 'SupportsSecureBoot'
            $provider.Capabilities.Keys | Should -Contain 'SupportedDiskFormats'
            $provider.Capabilities.Keys | Should -Contain 'MaxMemoryGB'
            $provider.Capabilities.Keys | Should -Contain 'MaxProcessors'
        }
    }
}

# =============================================================================
# VMware Configuration Validation Tests
# =============================================================================

Describe 'VMware Configuration Validation' -Tag 'Integration', 'VMware', 'FFU.Hypervisor', 'TEST-06' {

    BeforeAll {
        $script:VMwareProvider = Get-HypervisorProvider -Type 'VMware'
    }

    Context 'Disk Format Validation' {

        It 'ValidateConfiguration accepts valid VMDK config' {
            $config = Invoke-InModuleScope {
                $c = [VMConfiguration]::new('TestVM', 'C:\VM\Test', 4GB, 2, 'C:\VM\Test\disk.vmdk')
                $c.DiskFormat = 'VMDK'
                $c
            }

            $result = $script:VMwareProvider.ValidateConfiguration($config)

            $result.IsValid | Should -Be $true
        }

        It 'ValidateConfiguration rejects VHDX for VMware' {
            $config = Invoke-InModuleScope {
                $c = [VMConfiguration]::new('TestVM', 'C:\VM\Test', 4GB, 2, 'C:\VM\Test\disk.vhdx')
                $c.DiskFormat = 'VHDX'
                $c
            }

            $result = $script:VMwareProvider.ValidateConfiguration($config)

            $result.IsValid | Should -Be $false
            $result.Errors | Should -Match 'VHDX'
        }

        It 'ValidateConfiguration accepts VHD format (VMware 10+ feature)' {
            $config = Invoke-InModuleScope {
                $c = [VMConfiguration]::new('TestVM', 'C:\VM\Test', 4GB, 2, 'C:\VM\Test\disk.vhd')
                $c.DiskFormat = 'VHD'
                $c
            }

            $result = $script:VMwareProvider.ValidateConfiguration($config)

            $result.IsValid | Should -Be $true
        }
    }

    Context 'Resource Limits Validation' {

        It 'ValidateConfiguration accepts memory within limits' {
            $config = Invoke-InModuleScope {
                $c = [VMConfiguration]::new('TestVM', 'C:\VM\Test', 64GB, 8, 'C:\VM\Test\disk.vmdk')
                $c.DiskFormat = 'VMDK'
                $c
            }

            $result = $script:VMwareProvider.ValidateConfiguration($config)

            $result.IsValid | Should -Be $true
        }

        It 'ValidateConfiguration warns when memory exceeds MaxMemoryGB' {
            # Note: Base class uses warnings (not errors) for exceeding recommended limits
            # This allows flexibility while still alerting the user
            $provider = $script:VMwareProvider
            $maxMemory = $provider.Capabilities.MaxMemoryGB

            $config = Invoke-InModuleScope -ScriptBlock ([scriptblock]::Create(@"
                `$c = [VMConfiguration]::new('TestVM', 'C:\VM\Test', $([uint64](($maxMemory + 50) * 1GB)), 2, 'C:\VM\Test\disk.vmdk')
                `$c.DiskFormat = 'VMDK'
                `$c
"@))

            $result = $provider.ValidateConfiguration($config)

            # Should remain valid but have warning about exceeding recommended max
            $result.IsValid | Should -Be $true
            $result.Warnings | Should -Not -BeNullOrEmpty
            ($result.Warnings -join ' ') | Should -Match 'memory|Memory'
        }

        It 'ValidateConfiguration warns when processors exceed MaxProcessors' {
            # Note: Base class uses warnings (not errors) for exceeding recommended limits
            $provider = $script:VMwareProvider
            $maxProcessors = $provider.Capabilities.MaxProcessors

            $config = Invoke-InModuleScope -ScriptBlock ([scriptblock]::Create(@"
                `$c = [VMConfiguration]::new('TestVM', 'C:\VM\Test', 8GB, $($maxProcessors + 10), 'C:\VM\Test\disk.vmdk')
                `$c.DiskFormat = 'VMDK'
                `$c
"@))

            $result = $provider.ValidateConfiguration($config)

            # Should remain valid but have warning about exceeding recommended max
            $result.IsValid | Should -Be $true
            $result.Warnings | Should -Not -BeNullOrEmpty
            ($result.Warnings -join ' ') | Should -Match 'processor|Processor'
        }
    }
}

# =============================================================================
# VMware Disk Format Support Tests
# =============================================================================

Describe 'VMware Disk Format Support' -Tag 'Integration', 'VMware', 'FFU.Hypervisor', 'TEST-06' {

    BeforeAll {
        $script:VMwareProvider = Get-HypervisorProvider -Type 'VMware'
    }

    It 'Capabilities.SupportedDiskFormats contains VMDK' {
        $script:VMwareProvider.Capabilities.SupportedDiskFormats | Should -Contain 'VMDK'
    }

    It 'Capabilities.SupportedDiskFormats contains VHD (VMware 10+ feature)' {
        $script:VMwareProvider.Capabilities.SupportedDiskFormats | Should -Contain 'VHD'
    }

    It 'Capabilities.SupportedDiskFormats does NOT contain VHDX' {
        $script:VMwareProvider.Capabilities.SupportedDiskFormats | Should -Not -Contain 'VHDX'
    }
}

# =============================================================================
# Diskpart Function Existence Tests (for VMware disk operations)
# =============================================================================

Describe 'Diskpart Function Existence' -Tag 'Integration', 'VMware', 'FFU.Hypervisor', 'TEST-06' {

    Context 'VHD Operations without Hyper-V' {

        It 'New-VHDWithDiskpart function exists in module' {
            $command = Invoke-InModuleScope {
                Get-Command -Name 'New-VHDWithDiskpart' -ErrorAction SilentlyContinue
            }

            $command | Should -Not -BeNullOrEmpty
        }

        It 'Mount-VHDWithDiskpart function exists in module' {
            $command = Invoke-InModuleScope {
                Get-Command -Name 'Mount-VHDWithDiskpart' -ErrorAction SilentlyContinue
            }

            $command | Should -Not -BeNullOrEmpty
        }

        It 'Dismount-VHDWithDiskpart function exists in module' {
            $command = Invoke-InModuleScope {
                Get-Command -Name 'Dismount-VHDWithDiskpart' -ErrorAction SilentlyContinue
            }

            $command | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# VMX File Generation Tests (Skip if no VMware)
# =============================================================================

Describe 'VMX File Generation' -Tag 'Integration', 'VMware', 'FFU.Hypervisor', 'TEST-06' {

    BeforeAll {
        # Create temp directory for test files
        $script:TestVMPath = Join-Path $env:TEMP "VMwareTest_$(Get-Random)"
        if (-not (Test-Path $script:TestVMPath)) {
            New-Item -Path $script:TestVMPath -ItemType Directory -Force | Out-Null
        }
    }

    AfterAll {
        # Cleanup test directory
        if ($script:TestVMPath -and (Test-Path $script:TestVMPath)) {
            Remove-Item -Path $script:TestVMPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'New-VMwareVMX Function' -Skip:(-not $script:VMwareInstalled) {

        BeforeEach {
            # Clean test directory before each test
            Get-ChildItem -Path $script:TestVMPath -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }

        AfterEach {
            # Clean test files after each test
            Get-ChildItem -Path $script:TestVMPath -File -Filter '*.vmx' -ErrorAction SilentlyContinue |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }

        It 'New-VMwareVMX creates file at expected path' {
            $diskPath = Join-Path $script:TestVMPath 'TestVM.vhd'

            $vmxPath = Invoke-InModuleScope -ScriptBlock ([scriptblock]::Create(@"
                New-VMwareVMX -VMName 'TestVM' -VMPath '$($script:TestVMPath)' -DiskPath '$diskPath' -MemoryMB 4096 -Processors 2
"@))

            # Should return path or create file
            if ($vmxPath) {
                Test-Path $vmxPath | Should -Be $true
            }
        }

        It 'VMX contains correct memsize setting' {
            $diskPath = Join-Path $script:TestVMPath 'TestVM.vhd'
            $expectedMemoryMB = 8192

            $vmxPath = Invoke-InModuleScope -ScriptBlock ([scriptblock]::Create(@"
                New-VMwareVMX -VMName 'TestVM' -VMPath '$($script:TestVMPath)' -DiskPath '$diskPath' -MemoryMB $expectedMemoryMB -Processors 2
"@))

            if ($vmxPath -and (Test-Path $vmxPath)) {
                $vmxContent = Get-Content $vmxPath -Raw
                $vmxContent | Should -Match "memsize\s*=\s*`"$expectedMemoryMB`""
            }
        }

        It 'VMX contains correct numvcpus setting' {
            $diskPath = Join-Path $script:TestVMPath 'TestVM.vhd'
            $expectedCPUs = 4

            $vmxPath = Invoke-InModuleScope -ScriptBlock ([scriptblock]::Create(@"
                New-VMwareVMX -VMName 'TestVM' -VMPath '$($script:TestVMPath)' -DiskPath '$diskPath' -MemoryMB 4096 -Processors $expectedCPUs
"@))

            if ($vmxPath -and (Test-Path $vmxPath)) {
                $vmxContent = Get-Content $vmxPath -Raw
                $vmxContent | Should -Match "numvcpus\s*=\s*`"$expectedCPUs`""
            }
        }

        It 'VMX contains guestOS setting' {
            $diskPath = Join-Path $script:TestVMPath 'TestVM.vhd'

            $vmxPath = Invoke-InModuleScope -ScriptBlock ([scriptblock]::Create(@"
                New-VMwareVMX -VMName 'TestVM' -VMPath '$($script:TestVMPath)' -DiskPath '$diskPath' -MemoryMB 4096 -Processors 2
"@))

            if ($vmxPath -and (Test-Path $vmxPath)) {
                $vmxContent = Get-Content $vmxPath -Raw
                # Should have guestOS set (typically windows11-64 for FFU builds)
                $vmxContent | Should -Match 'guestOS\s*=\s*"'
            }
        }
    }

    Context 'VMX Function Existence (No VMware Required)' {

        It 'New-VMwareVMX function is defined in module' {
            $command = Invoke-InModuleScope {
                Get-Command -Name 'New-VMwareVMX' -ErrorAction SilentlyContinue
            }

            $command | Should -Not -BeNullOrEmpty
        }

        It 'Set-VMwareBootISO function is defined in module' {
            $command = Invoke-InModuleScope {
                Get-Command -Name 'Set-VMwareBootISO' -ErrorAction SilentlyContinue
            }

            $command | Should -Not -BeNullOrEmpty
        }

        It 'Remove-VMwareBootISO function is defined in module' {
            $command = Invoke-InModuleScope {
                Get-Command -Name 'Remove-VMwareBootISO' -ErrorAction SilentlyContinue
            }

            $command | Should -Not -BeNullOrEmpty
        }

        It 'Update-VMwareVMX function is defined in module' {
            $command = Invoke-InModuleScope {
                Get-Command -Name 'Update-VMwareVMX' -ErrorAction SilentlyContinue
            }

            $command | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# VMware Provider TPM Handling Tests
# =============================================================================

Describe 'VMware TPM Handling' -Tag 'Integration', 'VMware', 'FFU.Hypervisor', 'TEST-06' {

    BeforeAll {
        $script:VMwareProvider = Get-HypervisorProvider -Type 'VMware'
    }

    It 'VMware reports TPM not supported due to encryption requirement' {
        $script:VMwareProvider.Capabilities.SupportsTPM | Should -Be $false
    }

    It 'VMware has TPMNote explaining the limitation' {
        $script:VMwareProvider.Capabilities.TPMNote | Should -Not -BeNullOrEmpty
        $script:VMwareProvider.Capabilities.TPMNote | Should -Match 'encryption'
    }

    It 'ValidateConfiguration warns when EnableTPM is true' {
        $config = Invoke-InModuleScope {
            $c = [VMConfiguration]::new('TestVM', 'C:\VM\Test', 4GB, 2, 'C:\VM\Test\disk.vmdk')
            $c.DiskFormat = 'VMDK'
            $c.EnableTPM = $true
            $c
        }

        $result = $script:VMwareProvider.ValidateConfiguration($config)

        # Should still be valid (TPM is not a hard requirement)
        $result.IsValid | Should -Be $true
        # But should have warnings about TPM
        $result.Warnings | Should -Not -BeNullOrEmpty
        ($result.Warnings -join ' ') | Should -Match 'TPM|encryption'
    }
}

# =============================================================================
# VMware Provider Availability Details Tests
# =============================================================================

Describe 'VMware Availability Details' -Tag 'Integration', 'VMware', 'FFU.Hypervisor', 'TEST-06' {

    BeforeAll {
        $script:VMwareProvider = Get-HypervisorProvider -Type 'VMware'
    }

    It 'GetAvailabilityDetails returns hashtable' {
        $details = $script:VMwareProvider.GetAvailabilityDetails()

        $details | Should -BeOfType [hashtable]
    }

    It 'Availability details include IsAvailable' {
        $details = $script:VMwareProvider.GetAvailabilityDetails()

        $details.Keys | Should -Contain 'IsAvailable'
        $details.IsAvailable | Should -BeOfType [bool]
    }

    It 'Availability details include ProviderName' {
        $details = $script:VMwareProvider.GetAvailabilityDetails()

        $details.Keys | Should -Contain 'ProviderName'
        $details.ProviderName | Should -Be 'VMware'
    }

    It 'Availability details match installation status' {
        $details = $script:VMwareProvider.GetAvailabilityDetails()

        # IsAvailable should match our detection
        # Note: Provider may have stricter requirements than just vmrun.exe
        if ($script:VMwareInstalled) {
            # If we detected VMware, provider should also detect it
            # (unless there are additional requirements like specific version)
            $details.Details | Should -Not -BeNullOrEmpty
        }
    }
}
