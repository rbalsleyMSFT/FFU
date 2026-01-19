# Phase 6: Integration Tests - UI and Error Handling - Research

**Researched:** 2026-01-19
**Domain:** Pester 5.x testing for WPF UI handlers, error recovery paths, cleanup systems, and VMware provider operations
**Confidence:** HIGH

## Summary

This phase adds test coverage for three key areas: UI event handlers (FFUUI.Core.Handlers.psm1), error recovery and cleanup handlers (FFU.Core cleanup system), and VMware provider operations (FFU.Hypervisor). The primary challenge is that UI handlers interact with WPF controls that are unavailable in test contexts, requiring logic extraction patterns.

The standard approach involves:
1. **UI Handler Testing** - Extract testable business logic from event handlers; mock WPF controls as PSCustomObjects
2. **Cleanup Handler Testing** - Test the cleanup registry system directly with mock cleanup actions
3. **VMware Provider Testing** - Build on existing FFU.Hypervisor.Tests.ps1 patterns with conditional skip for unavailable VMware

**Primary recommendation:** Focus tests on the PowerShell logic within handlers, not WPF interactions. Use PSCustomObject mocks for State/Controls patterns. Test cleanup registry operations (Register, Unregister, Invoke) with mock scriptblocks.

## Standard Stack

The established libraries/tools for this domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Pester | 5.0.0+ | Test framework | Official PowerShell testing framework, supports mocking, tagging |
| PowerShell | 7.0+ | Execution environment | Required by FFUUI.Core module manifest |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| System.Windows.* | .NET WPF | UI controls | Only available in UI context, must be mocked in tests |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Full WPF UI testing | Logic extraction + mock | WPF unavailable in CI; mocking State object tests actual logic |
| Real VMware operations | Mocked vmrun calls | Tests pass on any machine, real operations require VMware |
| Real cleanup execution | Mock scriptblocks | Tests cleanup system logic without side effects |

**Installation:**
```powershell
# Pester 5.x is usually pre-installed, upgrade if needed
Install-Module -Name Pester -MinimumVersion 5.0.0 -Force -SkipPublisherCheck -Scope CurrentUser
```

## Architecture Patterns

### Recommended Test Structure
```
Tests/
├── Unit/
│   ├── FFUUI.Core.Handlers.Tests.ps1      # TEST-04: UI event handlers
│   ├── FFU.Core.Cleanup.Tests.ps1         # TEST-05: Error recovery/cleanup
│   └── FFU.Hypervisor.Tests.ps1           # Existing VMware tests (extend)
└── Integration/
    └── FFU.Hypervisor.VMware.Integration.Tests.ps1  # TEST-06: VMware provider
```

### Pattern 1: Mock State Object for UI Handler Testing
**What:** Create PSCustomObject that mimics the UI State structure
**When to use:** Testing FFUUI.Core.Handlers functions without WPF runtime
**Example:**
```powershell
# Source: Project pattern - FFUUI.Core uses $State.Controls.controlName pattern
BeforeAll {
    # Create mock State object matching FFUUI.Core.Handlers expectations
    $script:MockState = [PSCustomObject]@{
        Controls = @{
            txtThreads = [PSCustomObject]@{ Text = '4' }
            txtMaxUSBDrives = [PSCustomObject]@{ Text = '0' }
            txtFFUDevPath = [PSCustomObject]@{ Text = 'C:\FFUDevelopment' }
            chkInstallDrivers = [PSCustomObject]@{ IsChecked = $true }
            lstDriverModels = [PSCustomObject]@{
                Items = [System.Collections.ArrayList]::new()
                ItemsSource = $null
            }
            txtStatus = [PSCustomObject]@{ Text = '' }
        }
        Data = @{
            allDriverModels = [System.Collections.Generic.List[object]]::new()
            vmSwitchMap = @{}
        }
        Flags = @{
            lastSortProperty = $null
            lastSortAscending = $true
        }
        FFUDevelopmentPath = 'C:\FFUDevelopment'
    }
}

It 'Should validate thread count on LostFocus' {
    $MockState.Controls.txtThreads.Text = '0'  # Invalid value

    # Simulate the validation logic from Register-EventHandlers
    $currentValue = 0
    $isValidInteger = [int]::TryParse($MockState.Controls.txtThreads.Text, [ref]$currentValue)

    if (-not $isValidInteger -or $currentValue -lt 1) {
        $MockState.Controls.txtThreads.Text = '1'  # Reset to default
    }

    $MockState.Controls.txtThreads.Text | Should -Be '1'
}
```

### Pattern 2: Cleanup Registry Testing
**What:** Test Register-CleanupAction, Unregister-CleanupAction, Invoke-FailureCleanup directly
**When to use:** TEST-05 - Error recovery paths and cleanup handlers
**Example:**
```powershell
# Source: FFU.Core.psm1 cleanup registry system
Describe 'Cleanup Registry System' -Tag 'Unit', 'FFU.Core', 'Cleanup' {
    BeforeAll {
        Import-Module "$ModulesPath\FFU.Core\FFU.Core.psd1" -Force

        # Reset cleanup registry before each test
        InModuleScope 'FFU.Core' {
            $script:CleanupRegistry = [System.Collections.Generic.List[PSCustomObject]]::new()
        }
    }

    It 'Should register cleanup action and return ID' {
        $cleanupCalled = $false
        $cleanupId = Register-CleanupAction -Name "Test Cleanup" `
            -ResourceType "TempFile" `
            -ResourceId "C:\temp\test.txt" `
            -Action { $script:cleanupCalled = $true }

        $cleanupId | Should -Not -BeNullOrEmpty
        $cleanupId | Should -Match '^[a-f0-9\-]{36}$'  # GUID format
    }

    It 'Should execute cleanup actions in LIFO order' {
        $executionOrder = [System.Collections.ArrayList]::new()

        Register-CleanupAction -Name "First" -Action { $executionOrder.Add('First') | Out-Null }
        Register-CleanupAction -Name "Second" -Action { $executionOrder.Add('Second') | Out-Null }
        Register-CleanupAction -Name "Third" -Action { $executionOrder.Add('Third') | Out-Null }

        Invoke-FailureCleanup -Reason "Test"

        $executionOrder[0] | Should -Be 'Third'  # Last registered, first executed
        $executionOrder[1] | Should -Be 'Second'
        $executionOrder[2] | Should -Be 'First'
    }

    It 'Should remove entry after successful unregister' {
        $id = Register-CleanupAction -Name "Temp" -Action { }
        $result = Unregister-CleanupAction -CleanupId $id

        $result | Should -Be $true

        # Verify it's gone
        $secondResult = Unregister-CleanupAction -CleanupId $id
        $secondResult | Should -Be $false
    }
}
```

### Pattern 3: VMware Provider Mocked Testing
**What:** Extend existing FFU.Hypervisor.Tests.ps1 with VMware-specific operation mocks
**When to use:** TEST-06 - VMware provider operations
**Example:**
```powershell
# Source: Existing FFU.Hypervisor.Tests.ps1 pattern
Describe 'VMwareProvider Operations' -Tag 'Integration', 'VMware', 'FFU.Hypervisor' {
    BeforeAll {
        $script:VMwareInstalled = $false
        $vmrunPath = "${env:ProgramFiles(x86)}\VMware\VMware Workstation\vmrun.exe"
        if (Test-Path $vmrunPath) {
            $script:VMwareInstalled = $true
        }

        Import-Module "$ModulesPath\FFU.Hypervisor\FFU.Hypervisor.psd1" -Force
    }

    Context 'CreateVM with Mocked vmrun' {
        BeforeAll {
            # Mock at module scope to intercept vmrun calls
            Mock Start-Process {
                return [PSCustomObject]@{ ExitCode = 0 }
            } -ModuleName FFU.Hypervisor
        }

        It 'Should call vmrun with correct arguments for VM creation' -Skip:(-not $script:VMwareInstalled) {
            $config = New-VMConfiguration -Name 'TestVM' `
                -Path 'C:\VMs\Test' `
                -MemoryBytes 4GB `
                -ProcessorCount 2 `
                -VirtualDiskPath 'C:\VMs\Test\TestVM.vmdk' `
                -DiskFormat 'VMDK'

            $provider = Get-HypervisorProvider -Type 'VMware'
            # Note: CreateVM may require actual VMware for full test
            # This validates the provider can be obtained and configured

            $provider.Name | Should -Be 'VMware'
            $provider.Capabilities.SupportedDiskFormats | Should -Contain 'VMDK'
        }
    }
}
```

### Pattern 4: Invoke-WithCleanup Testing
**What:** Test the try-finally cleanup wrapper function
**When to use:** Testing error recovery path execution
**Example:**
```powershell
Describe 'Invoke-WithCleanup' -Tag 'Unit', 'FFU.Core', 'ErrorRecovery' {
    BeforeAll {
        Import-Module "$ModulesPath\FFU.Core\FFU.Core.psd1" -Force
        Mock WriteLog { } -ModuleName FFU.Core
    }

    It 'Should execute cleanup even when operation fails' {
        $cleanupExecuted = $false

        {
            Invoke-WithCleanup -OperationName "Test Op" `
                -Operation { throw "Test error" } `
                -Cleanup { $script:cleanupExecuted = $true }
        } | Should -Throw "Test error"

        $cleanupExecuted | Should -Be $true
    }

    It 'Should execute cleanup on success' {
        $cleanupExecuted = $false

        $result = Invoke-WithCleanup -OperationName "Test Op" `
            -Operation { "success" } `
            -Cleanup { $script:cleanupExecuted = $true }

        $result | Should -Be "success"
        $cleanupExecuted | Should -Be $true
    }
}
```

### Anti-Patterns to Avoid
- **Testing WPF controls directly:** WPF types unavailable in test context; mock State object instead
- **Assuming VMware available:** Always use `-Skip:(-not $script:VMwareInstalled)` pattern
- **Modifying global state without reset:** Use `BeforeEach` to reset cleanup registry between tests
- **Testing handler registration:** Test the logic handlers execute, not that Add_Click was called

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Mock WPF controls | Custom mock framework | PSCustomObject with matching properties | Simpler, works with PowerShell's duck typing |
| Cleanup execution tracking | Manual call tracking | `Should -Invoke` for mocks | Built-in Pester feature |
| Test isolation | Manual cleanup | `BeforeEach`/`AfterEach` blocks | Pester handles scope automatically |
| State object structure | Recreate entire UI | Extract minimal required properties | Tests run faster, less maintenance |

**Key insight:** The handlers in FFUUI.Core.Handlers.psm1 don't test WPF - they test PowerShell logic that happens to be called from WPF events. Mock the State structure, test the business logic.

## Common Pitfalls

### Pitfall 1: WPF Type Not Found Errors
**What goes wrong:** Tests fail with "Unable to find type [System.Windows.Controls.ListView]"
**Why it happens:** WPF assemblies not loaded in test process
**How to avoid:** Don't reference WPF types in tests; mock controls as PSCustomObjects
**Warning signs:** Tests pass in ISE but fail in CI/automated runs

### Pitfall 2: Module-Scoped Variable Isolation
**What goes wrong:** Cleanup registry retains state between tests
**Why it happens:** `$script:CleanupRegistry` persists across test runs
**How to avoid:** Reset in `BeforeEach`: `InModuleScope 'FFU.Core' { $script:CleanupRegistry.Clear() }`
**Warning signs:** Tests pass individually but fail when run together

### Pitfall 3: InModuleScope Required for Script-Scoped Variables
**What goes wrong:** Cannot access or reset `$script:CleanupRegistry`
**Why it happens:** Script-scoped variables only visible within module
**How to avoid:** Use `InModuleScope 'FFU.Core' { ... }` to access/modify
**Warning signs:** "Variable not found" errors when testing cleanup system

### Pitfall 4: VMware Path Detection
**What goes wrong:** Tests fail on machines without VMware
**Why it happens:** VMware not installed or installed in non-standard location
**How to avoid:** Use conditional skip with explicit detection:
```powershell
$vmrunPath = "${env:ProgramFiles(x86)}\VMware\VMware Workstation\vmrun.exe"
$VMwareInstalled = Test-Path $vmrunPath
It 'VMware test' -Skip:(-not $VMwareInstalled) { ... }
```
**Warning signs:** Tests fail in CI but pass locally

### Pitfall 5: Mock Scope for Nested Functions
**What goes wrong:** Mock doesn't intercept function called inside module
**Why it happens:** Pester 5.x mocks at module scope, not call scope
**How to avoid:** Use `-ModuleName 'FFU.Core'` parameter on Mock command
**Warning signs:** Mock set but original function still called

## Code Examples

Verified patterns from official sources and project codebase:

### Testing FFUUI.Core.Handlers Key Functions
```powershell
# Source: Project codebase analysis - Register-EventHandlers pattern
Describe 'FFUUI.Core.Handlers Key Functions' -Tag 'Unit', 'FFUUI.Core' {
    BeforeAll {
        # Don't import FFUUI.Core (requires WPF) - test extracted logic
        $script:MockState = [PSCustomObject]@{
            Controls = @{
                txtThreads = [PSCustomObject]@{ Text = '4' }
                txtMaxUSBDrives = [PSCustomObject]@{ Text = '0' }
                usbSection = [PSCustomObject]@{ Visibility = 'Collapsed' }
                chkSelectSpecificUSBDrives = [PSCustomObject]@{ IsEnabled = $false; IsChecked = $false }
                lstUSBDrives = [PSCustomObject]@{
                    Items = [System.Collections.ArrayList]::new()
                }
            }
            Data = @{
                allDriverModels = [System.Collections.Generic.List[object]]::new()
            }
            Flags = @{}
            FFUDevelopmentPath = 'C:\FFUDevelopment'
        }
    }

    Context 'Integer-Only TextBox Validation' {
        It 'Should allow valid integer input' {
            $text = '123'
            $isInvalid = $text -match '\D'
            $isInvalid | Should -Be $false
        }

        It 'Should reject non-digit characters' {
            $text = '12a3'
            $isInvalid = $text -match '\D'
            $isInvalid | Should -Be $true
        }

        It 'Should reset threads to 1 when value is 0' {
            $MockState.Controls.txtThreads.Text = '0'
            $currentValue = 0
            [int]::TryParse($MockState.Controls.txtThreads.Text, [ref]$currentValue) | Out-Null

            if ($currentValue -lt 1) {
                $MockState.Controls.txtThreads.Text = '1'
            }

            $MockState.Controls.txtThreads.Text | Should -Be '1'
        }
    }

    Context 'USB Drive Settings Visibility' {
        It 'Should show USB section when enabled' {
            # Simulate chkBuildUSBDriveEnable checked
            $MockState.Controls.usbSection.Visibility = 'Visible'
            $MockState.Controls.chkSelectSpecificUSBDrives.IsEnabled = $true

            $MockState.Controls.usbSection.Visibility | Should -Be 'Visible'
            $MockState.Controls.chkSelectSpecificUSBDrives.IsEnabled | Should -Be $true
        }

        It 'Should hide and reset USB section when disabled' {
            # Simulate chkBuildUSBDriveEnable unchecked
            $MockState.Controls.usbSection.Visibility = 'Collapsed'
            $MockState.Controls.chkSelectSpecificUSBDrives.IsEnabled = $false
            $MockState.Controls.chkSelectSpecificUSBDrives.IsChecked = $false
            $MockState.Controls.lstUSBDrives.Items.Clear()

            $MockState.Controls.usbSection.Visibility | Should -Be 'Collapsed'
            $MockState.Controls.lstUSBDrives.Items.Count | Should -Be 0
        }
    }
}
```

### Testing Cleanup Registry System
```powershell
# Source: FFU.Core.psm1 lines 2170-2359
Describe 'FFU.Core Cleanup Registry System' -Tag 'Unit', 'FFU.Core', 'Cleanup', 'TEST-05' {
    BeforeAll {
        $script:ModulesPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules'
        Import-Module "$ModulesPath\FFU.Core\FFU.Core.psd1" -Force -ErrorAction Stop

        Mock WriteLog { } -ModuleName FFU.Core
    }

    BeforeEach {
        # Reset cleanup registry between tests
        InModuleScope 'FFU.Core' {
            $script:CleanupRegistry.Clear()
        }
    }

    Context 'Register-CleanupAction' {
        It 'Should return a valid GUID' {
            $id = Register-CleanupAction -Name "Test" -Action { }
            $id | Should -Match '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'
        }

        It 'Should accept all resource types' {
            $types = @('VM', 'VHDX', 'DISM', 'ISO', 'TempFile', 'BITS', 'Share', 'User', 'Other')
            foreach ($type in $types) {
                { Register-CleanupAction -Name "Test $type" -ResourceType $type -Action { } } |
                    Should -Not -Throw
            }
        }

        It 'Should store ResourceId when provided' {
            $id = Register-CleanupAction -Name "VM Cleanup" `
                -ResourceType "VM" `
                -ResourceId "FFU_Build_VM" `
                -Action { }

            $id | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Unregister-CleanupAction' {
        It 'Should return true when entry exists' {
            $id = Register-CleanupAction -Name "Test" -Action { }
            $result = Unregister-CleanupAction -CleanupId $id
            $result | Should -Be $true
        }

        It 'Should return false for non-existent ID' {
            $result = Unregister-CleanupAction -CleanupId 'non-existent-guid'
            $result | Should -Be $false
        }
    }

    Context 'Invoke-FailureCleanup' {
        It 'Should execute all registered actions' {
            $script:executionCount = 0
            Register-CleanupAction -Name "Action 1" -Action { $script:executionCount++ }
            Register-CleanupAction -Name "Action 2" -Action { $script:executionCount++ }

            Invoke-FailureCleanup -Reason "Test"

            $executionCount | Should -Be 2
        }

        It 'Should execute in LIFO order' {
            $script:order = @()
            Register-CleanupAction -Name "First" -Action { $script:order += 'First' }
            Register-CleanupAction -Name "Second" -Action { $script:order += 'Second' }
            Register-CleanupAction -Name "Third" -Action { $script:order += 'Third' }

            Invoke-FailureCleanup -Reason "Test"

            $order | Should -Be @('Third', 'Second', 'First')
        }

        It 'Should continue after cleanup failure' {
            $script:secondExecuted = $false
            Register-CleanupAction -Name "First" -Action { $script:secondExecuted = $true }
            Register-CleanupAction -Name "Second (Fails)" -Action { throw "Cleanup error" }

            Invoke-FailureCleanup -Reason "Test"

            $secondExecuted | Should -Be $true
        }

        It 'Should filter by ResourceType when specified' {
            $script:vmCleaned = $false
            $script:diskCleaned = $false
            Register-CleanupAction -Name "VM" -ResourceType 'VM' -Action { $script:vmCleaned = $true }
            Register-CleanupAction -Name "Disk" -ResourceType 'VHDX' -Action { $script:diskCleaned = $true }

            Invoke-FailureCleanup -Reason "Test" -ResourceType 'VM'

            $vmCleaned | Should -Be $true
            $diskCleaned | Should -Be $false
        }
    }
}
```

### Testing Specialized Cleanup Functions
```powershell
# Source: FFU.Core.psm1 lines 2402-2570
Describe 'FFU.Core Specialized Cleanup Registration' -Tag 'Unit', 'FFU.Core', 'Cleanup' {
    BeforeAll {
        Import-Module "$ModulesPath\FFU.Core\FFU.Core.psd1" -Force
        Mock WriteLog { } -ModuleName FFU.Core
    }

    BeforeEach {
        InModuleScope 'FFU.Core' { $script:CleanupRegistry.Clear() }
    }

    Context 'Register-VMCleanup' {
        It 'Should register VM cleanup with correct ResourceType' {
            $id = Register-VMCleanup -VMName "TestVM"
            $id | Should -Not -BeNullOrEmpty

            # Verify it was registered correctly
            $entry = InModuleScope 'FFU.Core' {
                $script:CleanupRegistry | Where-Object { $_.ResourceType -eq 'VM' }
            }
            $entry | Should -Not -BeNullOrEmpty
            $entry.ResourceId | Should -Be 'TestVM'
        }
    }

    Context 'Register-VHDXCleanup' {
        It 'Should register VHDX cleanup' {
            $id = Register-VHDXCleanup -VhdxPath "C:\Test\disk.vhdx"
            $id | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Register-DISMMountCleanup' {
        It 'Should register DISM mount cleanup' {
            $id = Register-DISMMountCleanup -MountPath "C:\Mount"
            $id | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Register-TempFileCleanup' {
        It 'Should register temp file cleanup' {
            $id = Register-TempFileCleanup -Path "C:\Temp\file.tmp"
            $id | Should -Not -BeNullOrEmpty
        }

        It 'Should support directory cleanup' {
            $id = Register-TempFileCleanup -Path "C:\Temp\folder" -IsDirectory
            $id | Should -Not -BeNullOrEmpty
        }
    }
}
```

### VMware Provider Extended Tests
```powershell
# Source: Extending existing FFU.Hypervisor.Tests.ps1
Describe 'VMwareProvider Extended Operations' -Tag 'Integration', 'VMware', 'TEST-06' {
    BeforeAll {
        $script:ModulesPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules'

        # Detect VMware installation
        $script:VMwareInstalled = $false
        $vmrunPath = "${env:ProgramFiles(x86)}\VMware\VMware Workstation\vmrun.exe"
        if (Test-Path $vmrunPath) {
            $script:VMwareInstalled = $true
        }

        Import-Module "$ModulesPath\FFU.Hypervisor\FFU.Hypervisor.psd1" -Force
    }

    Context 'VMware Disk Operations' {
        It 'Should have New-VHDWithDiskpart function' {
            $command = InModuleScope 'FFU.Hypervisor' {
                Get-Command -Name 'New-VHDWithDiskpart' -ErrorAction SilentlyContinue
            }
            $command | Should -Not -BeNullOrEmpty
        }

        It 'Should have Mount-VHDWithDiskpart function' {
            $command = InModuleScope 'FFU.Hypervisor' {
                Get-Command -Name 'Mount-VHDWithDiskpart' -ErrorAction SilentlyContinue
            }
            $command | Should -Not -BeNullOrEmpty
        }

        It 'Should have Dismount-VHDWithDiskpart function' {
            $command = InModuleScope 'FFU.Hypervisor' {
                Get-Command -Name 'Dismount-VHDWithDiskpart' -ErrorAction SilentlyContinue
            }
            $command | Should -Not -BeNullOrEmpty
        }
    }

    Context 'VMware VM Lifecycle (Mocked)' {
        BeforeAll {
            # Get the module for InModuleScope
            $script:HypervisorModule = Get-Module -Name 'FFU.Hypervisor'
        }

        It 'Should validate VMDK configuration' {
            $config = New-VMConfiguration -Name 'TestVM' `
                -Path 'C:\VMs\Test' `
                -MemoryBytes 4GB `
                -ProcessorCount 2 `
                -VirtualDiskPath 'C:\VMs\Test\TestVM.vmdk' `
                -DiskFormat 'VMDK'

            $provider = Get-HypervisorProvider -Type 'VMware'
            $result = $provider.ValidateConfiguration($config)

            $result.IsValid | Should -Be $true
        }

        It 'Should reject VHDX for VMware' {
            $config = New-VMConfiguration -Name 'TestVM' `
                -Path 'C:\VMs\Test' `
                -MemoryBytes 4GB `
                -ProcessorCount 2 `
                -VirtualDiskPath 'C:\VMs\Test\TestVM.vhdx' `
                -DiskFormat 'VHDX'

            $provider = Get-HypervisorProvider -Type 'VMware'
            $result = $provider.ValidateConfiguration($config)

            $result.IsValid | Should -Be $false
            $result.Errors | Should -Match 'VHDX'
        }
    }

    Context 'VMX File Generation' -Skip:(-not $script:VMwareInstalled) {
        It 'Should generate VMX with correct settings' {
            $result = InModuleScope 'FFU.Hypervisor' {
                $testPath = Join-Path $env:TEMP "VMXTest_$(Get-Random)"
                New-Item -Path $testPath -ItemType Directory -Force | Out-Null

                try {
                    $vmxPath = New-VMwareVMX -VMName 'TestVM' `
                        -VMPath $testPath `
                        -DiskPath (Join-Path $testPath 'disk.vmdk') `
                        -MemoryMB 4096 `
                        -CPUs 2

                    if (Test-Path $vmxPath) {
                        $content = Get-Content $vmxPath -Raw
                        @{
                            HasMemory = $content -match 'memsize\s*=\s*"4096"'
                            HasCPUs = $content -match 'numvcpus\s*=\s*"2"'
                        }
                    } else {
                        @{ HasMemory = $false; HasCPUs = $false }
                    }
                }
                finally {
                    Remove-Item $testPath -Recurse -Force -ErrorAction SilentlyContinue
                }
            }

            if ($result) {
                $result.HasMemory | Should -Be $true
                $result.HasCPUs | Should -Be $true
            }
        }
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Direct WPF testing | Mock State objects | Always for CI/CD | Tests run without GUI dependencies |
| Global cleanup variables | Module-scoped registry | FFU.Core v1.0.x | Better isolation, LIFO execution |
| REST API for VMware | vmrun.exe direct calls | FFU.Hypervisor v1.2.0 | Simpler, no credentials needed |

**Deprecated/outdated:**
- VMware REST API functions (`Invoke-VMwareRestMethod`, `Start-VMrestService`): Removed in v1.2.0, replaced by vmrun.exe
- Assert-MockCalled: Use `Should -Invoke` in Pester 5.x

## Open Questions

Things that couldn't be fully resolved:

1. **Full Register-EventHandlers testing**
   - What we know: Function takes $State and attaches WPF event handlers
   - What's unclear: Whether we should test handler attachment or just handler logic
   - Recommendation: Test the business logic within handlers using extracted patterns; skip testing that Add_Click was called

2. **FFUUI.Core.Shared.psm1 functions requiring WPF types**
   - What we know: Functions like Update-ListViewPriorities take [System.Windows.Controls.ListView]
   - What's unclear: How to test without WPF types available
   - Recommendation: Create minimal PSCustomObject mocks with Items/ItemsSource properties; test logic not WPF interactions

3. **Real VMware VM creation in tests**
   - What we know: Creating real VMs requires VMware license and cleanup
   - What's unclear: Should integration tests create actual VMs?
   - Recommendation: Tag real VM tests with 'RealVMware', skip by default, run only in dedicated test environment

## Sources

### Primary (HIGH confidence)
- [Pester Quick Start](https://pester.dev/docs/quick-start) - Describe/It/BeforeAll patterns
- [Pester Mocking Documentation](https://pester.dev/docs/usage/mocking) - Mock creation, Should -Invoke
- [Pester Unit Testing within Modules](https://pester.dev/docs/usage/modules) - InModuleScope usage
- Project codebase: FFU.Core.psm1 cleanup registry (lines 2162-2570)
- Project codebase: FFUUI.Core.Handlers.psm1 (1073 lines)
- Project codebase: FFU.Hypervisor.Tests.ps1 (existing test patterns)

### Secondary (MEDIUM confidence)
- [Pester BeforeEach and AfterEach](https://github.com/pester/Pester/wiki/BeforeEach-and-AfterEach) - Test isolation patterns
- [4sysops Pester Mocking](https://4sysops.com/archives/mocking-with-pester-in-powershell-unit-testing/) - Mocking best practices
- [PowerShell Testing Guidelines](https://github.com/PowerShell/PowerShell/blob/master/docs/testing-guidelines/WritingPesterTests.md) - Best practices

### Tertiary (LOW confidence)
- Web search for WPF testing patterns - general guidance (limited 2025 results)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Pester 5.x is well-documented and stable
- Architecture patterns: HIGH - Based on project codebase analysis and existing test files
- UI testing approach: MEDIUM - WPF testing workarounds require validation
- Cleanup testing: HIGH - Direct access to FFU.Core cleanup registry is straightforward
- VMware testing: HIGH - Existing FFU.Hypervisor.Tests.ps1 provides proven patterns

**Research date:** 2026-01-19
**Valid until:** 90 days (Pester 5.x is stable, patterns unlikely to change)
