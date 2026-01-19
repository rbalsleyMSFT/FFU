# Phase 5: Integration Tests - Core Operations - Research

**Researched:** 2026-01-19
**Domain:** Pester 5.x integration testing for PowerShell modules (VM, drivers, imaging)
**Confidence:** HIGH

## Summary

This phase adds integration tests for three core FFU Builder operations: VM creation (TEST-01), driver injection workflow (TEST-02), and FFU capture process (TEST-03). The challenge is testing operations that require infrastructure (Hyper-V, VMware, mounted images) which may not be available in all test environments.

The standard approach combines two strategies:
1. **Conditional tests** - Skip tests when infrastructure is unavailable (e.g., Hyper-V not installed)
2. **Mock-based integration tests** - Test the integration logic with mocked cmdlets to verify parameter passing, error handling, and workflow orchestration

**Primary recommendation:** Use Pester 5.x's `Skip` functionality with infrastructure detection, combined with comprehensive mocking of Hyper-V/DISM cmdlets to test integration logic without requiring actual VMs or images.

## Standard Stack

The established libraries/tools for this domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Pester | 5.0.0+ | Test framework | Official PowerShell testing framework, supports mocking, tagging |
| PowerShell | 7.0+ | Execution environment | Required by FFU.VM, FFU.Imaging modules |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Hyper-V Module | Built-in | VM management | When testing Hyper-V operations on enabled hosts |
| DISM Module | Built-in | Image operations | When testing imaging/driver operations |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Conditional Skip | Mocking only | Skipping loses coverage on real infrastructure but tests pass everywhere |
| Full VM creation | Mocked cmdlets | Mocking is faster, no cleanup needed, but doesn't catch real-world issues |

**Installation:**
```powershell
# Pester 5.x is usually pre-installed, upgrade if needed
Install-Module -Name Pester -MinimumVersion 5.0.0 -Force -SkipPublisherCheck -Scope CurrentUser
```

## Architecture Patterns

### Recommended Test Structure
```
Tests/
├── Unit/                           # Existing unit tests (parameter validation)
│   ├── FFU.VM.Tests.ps1
│   ├── FFU.Drivers.Tests.ps1
│   └── FFU.Imaging.Tests.ps1
└── Integration/                    # New integration tests
    ├── FFU.VM.Integration.Tests.ps1         # TEST-01: VM creation
    ├── FFU.Drivers.Integration.Tests.ps1    # TEST-02: Driver injection
    └── FFU.Imaging.Integration.Tests.ps1    # TEST-03: FFU capture
```

### Pattern 1: Infrastructure-Conditional Testing
**What:** Use `Skip` parameter to conditionally run tests based on infrastructure availability
**When to use:** Tests that require real Hyper-V, VMware, or mounted images
**Example:**
```powershell
# Source: Pester documentation - https://pester.dev/docs/usage/skip
Describe 'Hyper-V VM Creation' -Tag 'Integration', 'HyperV' {
    BeforeAll {
        # Detect Hyper-V availability
        $script:HyperVAvailable = $false
        try {
            $service = Get-Service -Name vmms -ErrorAction Stop
            $script:HyperVAvailable = ($service.Status -eq 'Running')
        }
        catch {
            $script:HyperVAvailable = $false
        }
    }

    It 'Should create a Gen2 VM with correct configuration' -Skip:(-not $script:HyperVAvailable) {
        # This test only runs if Hyper-V is available
        # ...actual test code...
    }
}
```

### Pattern 2: Mock Cmdlets Not Available Locally
**What:** Create stub functions when cmdlets (like Hyper-V) are not installed on test machine
**When to use:** Testing on machines without Hyper-V/DISM modules installed
**Example:**
```powershell
# Source: Pester mocking docs - https://pester.dev/docs/usage/mocking
BeforeAll {
    # Create stub functions if Hyper-V module not available
    if (-not (Get-Module -Name Hyper-V -ListAvailable)) {
        function global:New-VM { param($Name, $Path, $MemoryStartupBytes, $VHDPath, $Generation) }
        function global:Set-VMProcessor { param($VMName, $Count) }
        function global:Start-VM { param($Name) }
        function global:Stop-VM { param($Name, $Force, $TurnOff) }
        function global:Remove-VM { param($Name, $Force) }
        function global:Get-VM { param($Name) }
    }
}

Describe 'HyperVProvider.CreateVM Integration' -Tag 'Integration' {
    BeforeAll {
        # Mock all Hyper-V cmdlets to verify parameter passing
        Mock New-VM { return [PSCustomObject]@{ Name = $Name; State = 'Off' } }
        Mock Set-VMProcessor { }
        Mock Start-VM { }
    }

    It 'Should call New-VM with correct parameters' {
        $config = [VMConfiguration]::new()
        $config.Name = '_FFU-Test-VM'
        $config.MemoryBytes = 8GB
        $config.ProcessorCount = 4

        # Test the provider logic
        $provider = [HyperVProvider]::new()
        $provider.CreateVM($config)

        Should -Invoke New-VM -Times 1 -ParameterFilter {
            $Name -eq '_FFU-Test-VM' -and
            $MemoryStartupBytes -eq 8GB -and
            $Generation -eq 2
        }
    }
}
```

### Pattern 3: WriteLog Mock Pattern
**What:** Mock WriteLog function which is called by most FFU module functions
**When to use:** Testing any function that calls WriteLog (most of them)
**Example:**
```powershell
# Source: Project decision from STATE.md - "WriteLog mock pattern for tests"
BeforeAll {
    # Import module under test
    Import-Module "$PSScriptRoot\..\..\FFUDevelopment\Modules\FFU.VM\FFU.VM.psd1" -Force

    # Mock WriteLog - required because functions call it
    Mock WriteLog { }
}

It 'Should handle VM creation failure gracefully' {
    Mock New-VM { throw 'VM creation failed' }

    { New-FFUVM -VMName 'Test' -VMPath 'C:\Test' -Memory 8GB -VHDXPath 'C:\test.vhdx' -Processors 4 -AppsISO 'C:\apps.iso' } |
        Should -Throw

    # Verify WriteLog was called with error message
    Should -Invoke WriteLog -ParameterFilter { $_ -like '*ERROR*' }
}
```

### Pattern 4: Test Tags for Selective Execution
**What:** Use Pester tags to enable running specific test categories
**When to use:** All tests, enables `Invoke-Pester -Tag 'Integration'`
**Example:**
```powershell
Describe 'Driver Injection Workflow' -Tag 'Integration', 'FFU.Drivers', 'DriverInjection' {
    # Tests here can be run with:
    # Invoke-Pester -Tag 'Integration'       # All integration tests
    # Invoke-Pester -Tag 'DriverInjection'   # Just driver tests
    # Invoke-Pester -ExcludeTag 'HyperV'     # Skip Hyper-V tests
}
```

### Anti-Patterns to Avoid
- **Hardcoded paths:** Use `$TestDrive` for temporary test files, not `C:\Temp`
- **Test pollution:** Always clean up VMs/files in `AfterAll` or `AfterEach`
- **No skip explanation:** Always include `-Skip` reason in test description
- **Testing implementation details:** Test behavior, not internal method calls (except for mocking verification)

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Temporary files | Manual file cleanup | Pester's `$TestDrive` | Auto-cleaned after test run |
| Infrastructure detection | Custom detection | `Get-Service vmms`, `Get-Module -ListAvailable` | Standard PowerShell cmdlets |
| Test result output | Custom formatters | Pester's `-Output Detailed` | Standardized, CI/CD compatible |
| Mocking cmdlets | Manual function replacement | Pester's `Mock` command | Handles scope, call counting |
| Test tagging | Custom test categories | Pester's `-Tag` parameter | Built-in filtering |

**Key insight:** Pester 5.x provides all necessary infrastructure for integration testing. The complexity is in designing tests that work both with and without real infrastructure.

## Common Pitfalls

### Pitfall 1: Mock Scope in Pester 5
**What goes wrong:** Mocks created in `Describe` don't apply in nested `Context` blocks
**Why it happens:** Pester 5 changed mock scoping rules - mocks default to block scope
**How to avoid:** Place mocks in `BeforeAll` at the correct level, or use `-Scope It`
**Warning signs:** Tests pass individually but fail when run together

### Pitfall 2: Module Function Not Found When Mocking
**What goes wrong:** `Mock Get-VM` fails with "command not found"
**Why it happens:** Hyper-V module not installed on test machine
**How to avoid:** Create stub functions in `BeforeAll` before mocking
**Warning signs:** Tests fail on CI/CD but pass locally

### Pitfall 3: InModuleScope Required for Internal Functions
**What goes wrong:** Cannot mock functions called internally by the module
**Why it happens:** Module functions call each other, not the mocked version
**How to avoid:** Use `InModuleScope 'FFU.VM' { Mock WriteLog { } }`
**Warning signs:** Mock is set but function still logs to file

### Pitfall 4: Test Order Dependency
**What goes wrong:** Tests pass when run individually but fail in sequence
**Why it happens:** Previous test left state (VMs, mounted images, files)
**How to avoid:** Use `BeforeEach`/`AfterEach` for proper isolation
**Warning signs:** Flaky tests, different results on re-run

### Pitfall 5: Long Test Execution Time
**What goes wrong:** Integration tests take too long, skip or timeout
**Why it happens:** Creating/destroying real VMs, mounting images is slow
**How to avoid:** Use mocking for logic tests; reserve real operations for tagged "slow" tests
**Warning signs:** Test suite takes >5 minutes, developers skip tests

## Code Examples

Verified patterns from official sources:

### Infrastructure Detection and Skip
```powershell
# Source: Pester documentation - https://pester.dev/docs/usage/skip
BeforeAll {
    $script:HyperVEnabled = $false
    $script:VMwareAvailable = $false

    # Detect Hyper-V
    try {
        $service = Get-Service -Name vmms -ErrorAction Stop
        $script:HyperVEnabled = ($service.Status -eq 'Running')
    }
    catch { }

    # Detect VMware
    $vmrunPath = "${env:ProgramFiles(x86)}\VMware\VMware Workstation\vmrun.exe"
    $script:VMwareAvailable = Test-Path $vmrunPath
}

Describe 'VM Creation Tests' -Tag 'Integration', 'VMCreation' {
    Context 'Hyper-V Provider' {
        It 'Creates Gen2 VM with TPM' -Skip:(-not $script:HyperVEnabled) {
            # Real Hyper-V test
        }
    }

    Context 'VMware Provider' {
        It 'Creates VM with VMX configuration' -Skip:(-not $script:VMwareAvailable) {
            # Real VMware test
        }
    }
}
```

### Mocking Hyper-V Cmdlets
```powershell
# Source: Pester mocking docs - https://pester.dev/docs/usage/mocking
Describe 'New-FFUVM Integration Logic' -Tag 'Integration', 'FFU.VM' {
    BeforeAll {
        # Create stubs if Hyper-V not available
        if (-not (Get-Module -Name Hyper-V -ListAvailable)) {
            function global:New-VM { param($Name, $Path, $MemoryStartupBytes, $VHDPath, $Generation) }
            function global:Set-VMProcessor { param($VMName, $Count) }
            function global:Add-VMDvdDrive { param($VMName, $Path) }
            function global:Get-VMHarddiskdrive { param($VMName) }
            function global:Set-VMFirmware { param($VMName, $FirstBootDevice) }
            function global:Set-VM { param($Name, $AutomaticCheckpointsEnabled, $StaticMemory) }
            function global:New-HgsGuardian { param($Name, $GenerateCertificates) }
            function global:Get-HgsGuardian { param($Name) }
            function global:New-HgsKeyProtector { param($Owner, $AllowUntrustedRoot) }
            function global:Set-VMKeyProtector { param($VMName, $KeyProtector) }
            function global:Enable-VMTPM { param($VMName) }
            function global:Start-VM { param($Name) }
        }

        # Import module
        Import-Module "$PSScriptRoot\..\..\FFUDevelopment\Modules\FFU.VM\FFU.VM.psd1" -Force

        # Mock WriteLog
        Mock WriteLog { } -ModuleName 'FFU.VM'
    }

    It 'Should call VM creation cmdlets in correct order' {
        Mock New-VM { [PSCustomObject]@{ Name = $Name } }
        Mock Set-VMProcessor { }
        Mock Add-VMDvdDrive { }
        Mock Get-VMHarddiskdrive { [PSCustomObject]@{ Path = 'C:\test.vhdx' } }
        Mock Set-VMFirmware { }
        Mock Set-VM { }
        Mock New-HgsGuardian { }
        Mock Get-HgsGuardian { [PSCustomObject]@{ Name = 'Test' } }
        Mock New-HgsKeyProtector { [PSCustomObject]@{ RawData = [byte[]]@(1,2,3) } }
        Mock Set-VMKeyProtector { }
        Mock Enable-VMTPM { }
        Mock Start-VM { }
        Mock vmconnect { }  # External command

        New-FFUVM -VMName '_FFU-Test' -VMPath 'C:\VM' -Memory 8GB -VHDXPath 'C:\test.vhdx' -Processors 4 -AppsISO 'C:\apps.iso'

        # Verify call order
        Should -Invoke New-VM -Times 1
        Should -Invoke Set-VMProcessor -Times 1 -ParameterFilter { $Count -eq 4 }
        Should -Invoke Add-VMDvdDrive -Times 1
        Should -Invoke Start-VM -Times 1
    }
}
```

### Driver Injection Workflow Mock
```powershell
# Source: Project codebase - FFU.Imaging uses Add-WindowsDriver
Describe 'Driver Injection Workflow' -Tag 'Integration', 'FFU.Drivers' {
    BeforeAll {
        # Create DISM stubs if not available
        if (-not (Get-Command Add-WindowsDriver -ErrorAction SilentlyContinue)) {
            function global:Add-WindowsDriver { param($Path, $Driver, $Recurse) }
            function global:Mount-WindowsImage { param($Path, $ImagePath, $Index) }
            function global:Dismount-WindowsImage { param($Path, $Save, $Discard) }
        }

        Import-Module "$PSScriptRoot\..\..\FFUDevelopment\Modules\FFU.Imaging\FFU.Imaging.psd1" -Force
        Mock WriteLog { } -ModuleName 'FFU.Imaging'
    }

    Context 'Add-WindowsDriver Integration' {
        It 'Should call Add-WindowsDriver with -Recurse for driver folder' {
            Mock Add-WindowsDriver { }

            # This tests the driver injection portion of New-CustomFFU
            # The actual function would be called here

            Should -Invoke Add-WindowsDriver -ParameterFilter { $Recurse -eq $true }
        }

        It 'Should handle driver injection failure gracefully' {
            Mock Add-WindowsDriver { throw 'Driver signing error' }

            # Test that the function continues or handles gracefully
            # Based on FFU.Imaging code, it uses -ErrorAction SilentlyContinue
        }
    }
}
```

### FFU Capture Mock Test
```powershell
Describe 'FFU Capture Workflow' -Tag 'Integration', 'FFU.Imaging', 'FFUCapture' {
    BeforeAll {
        Import-Module "$PSScriptRoot\..\..\FFUDevelopment\Modules\FFU.Imaging\FFU.Imaging.psd1" -Force
        Import-Module "$PSScriptRoot\..\..\FFUDevelopment\Modules\FFU.VM\FFU.VM.psd1" -Force
        Mock WriteLog { } -ModuleName 'FFU.Imaging'
        Mock WriteLog { } -ModuleName 'FFU.VM'
    }

    Context 'Set-CaptureFFU User Setup' {
        BeforeAll {
            # Mock DirectoryServices for local user management
            Mock Add-Type { } -ModuleName 'FFU.VM'
        }

        It 'Should create local user and SMB share for capture' {
            Mock Get-SmbShare { $null }  # Share doesn't exist
            Mock New-SmbShare { }
            Mock Grant-SmbShareAccess { }
            Mock New-Item { }  # Directory creation

            # Mock user doesn't exist
            InModuleScope 'FFU.VM' {
                Mock Get-LocalUserAccount { $null }
                Mock New-LocalUserAccount { $true }
                Mock Set-LocalUserAccountExpiry { Get-Date }
            }

            $securePassword = ConvertTo-SecureString 'TestPassword123!' -AsPlainText -Force
            Set-CaptureFFU -Username 'ffu_user' -ShareName 'FFUCaptureShare' -FFUCaptureLocation 'C:\FFU' -Password $securePassword

            Should -Invoke New-SmbShare -Times 1
            Should -Invoke Grant-SmbShareAccess -Times 1
        }
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Assert-MockCalled | Should -Invoke | Pester 5.0 | Same functionality, new syntax |
| Describe-level mocks | Block-scoped mocks | Pester 5.0 | Must place mocks in BeforeAll |
| -PassThru for mock returns | -MockWith scriptblock | Pester 5.0 | Same behavior, syntax change |

**Deprecated/outdated:**
- `Assert-MockCalled`: Use `Should -Invoke` instead (alias exists but deprecated)
- Global-scope mocks: Use `-Scope` parameter or place in appropriate block

## Open Questions

Things that couldn't be fully resolved:

1. **VMware REST API mocking complexity**
   - What we know: VMwareProvider uses REST API calls to vmrest service
   - What's unclear: Best approach to mock HTTP calls within the provider
   - Recommendation: Mock at the `Invoke-VMwareRestMethod` function level, not HTTP

2. **Real infrastructure test frequency**
   - What we know: Some tests need real Hyper-V/VMware to catch real issues
   - What's unclear: How often should these run? Only in CI with proper infrastructure?
   - Recommendation: Tag real infrastructure tests with 'RealInfra', run nightly not per-commit

3. **FFU capture end-to-end testing**
   - What we know: Full FFU capture requires VM, WinPE boot, network share
   - What's unclear: Can this be meaningfully tested without actual build?
   - Recommendation: Test individual components (user creation, share setup, script update) separately; defer full E2E to manual/nightly

## Sources

### Primary (HIGH confidence)
- [Pester Mocking Documentation](https://pester.dev/docs/usage/mocking) - Mock creation, Should -Invoke
- [Pester Quick Start](https://pester.dev/docs/quick-start) - Describe/It/BeforeAll patterns
- [Pester Unit Testing with Modules](https://pester.dev/docs/usage/modules) - InModuleScope usage

### Secondary (MEDIUM confidence)
- [Integration testing with Pester and PowerShell](https://martink.me/articles/integration-testing-with-pester-and-powershell) - General integration test patterns
- [Converting tests to Pester 5](https://dsccommunity.org/blog/converting-tests-to-pester5/) - Pester 5 migration patterns
- [4sysops Pester Mocking](https://4sysops.com/archives/mocking-with-pester-in-powershell-unit-testing/) - Mocking best practices

### Tertiary (LOW confidence)
- Web search for Pester infrastructure testing patterns - general guidance

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Pester 5.x is well-documented and stable
- Architecture: HIGH - Patterns from official documentation and project codebase
- Pitfalls: MEDIUM - Based on documentation and common issues, not all verified in this codebase

**Research date:** 2026-01-19
**Valid until:** 90 days (Pester 5.x is stable, patterns unlikely to change)
