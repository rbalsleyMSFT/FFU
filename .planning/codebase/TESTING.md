# Testing Patterns

**Analysis Date:** 2026-01-16

## Test Framework

**Runner:**
- Pester 5.0.0+ (PowerShell testing framework)
- Config: `Tests/Unit/Invoke-PesterTests.ps1` (custom runner)

**Assertion Library:**
- Pester built-in assertions (Should -Be, Should -Not -BeNullOrEmpty, etc.)

**Run Commands:**
```powershell
# Run all unit tests
.\Tests\Unit\Invoke-PesterTests.ps1

# Run specific module tests
.\Tests\Unit\Invoke-PesterTests.ps1 -Module 'FFU.Core'

# Run with coverage
.\Tests\Unit\Invoke-PesterTests.ps1 -EnableCodeCoverage

# Run with CI/CD output
.\Tests\Unit\Invoke-PesterTests.ps1 -EnableTestResults -OutputVerbosity Minimal

# Run tests with specific tags
.\Tests\Unit\Invoke-PesterTests.ps1 -Tag 'ErrorHandling'

# Direct Pester invocation
Invoke-Pester -Path .\Tests\Unit\FFU.Core.Tests.ps1 -Output Detailed
```

## Test File Organization

**Location:**
- Unit tests: `Tests/Unit/<ModuleName>.Tests.ps1`
- Integration tests: `Tests/Integration/`
- Fix verification tests: `Tests/Fixes/`
- Diagnostic tests: `Tests/Diagnostics/`
- Module-specific tests: `Tests/Modules/`
- Coverage output: `Tests/Coverage/`
- CI/CD results: `Tests/Results/`

**Naming:**
- Module tests: `FFU.<ModuleName>.Tests.ps1` (e.g., `FFU.Core.Tests.ps1`)
- Feature tests: `<Feature>.Tests.ps1` (e.g., `Phase2.Reliability.Tests.ps1`)
- Fix verification: `Test-<FixName>.ps1`
- Template: `_Template.Tests.ps1`

**Structure:**
```
Tests/
├── Unit/                              # Module unit tests
│   ├── _Template.Tests.ps1           # Test file template
│   ├── Invoke-PesterTests.ps1        # Custom test runner
│   ├── FFU.Core.Tests.ps1
│   ├── FFU.Drivers.Tests.ps1
│   ├── FFU.Hypervisor.Tests.ps1
│   ├── FFU.Imaging.Tests.ps1
│   ├── FFU.Media.Tests.ps1
│   ├── FFU.Preflight.Tests.ps1
│   └── Module.Dependencies.Tests.ps1
├── Integration/                       # Cross-module tests
│   ├── Test-UIIntegration.ps1
│   ├── Test-DownloadMethods.ps1
│   └── Test-ConfigFileValidation.ps1
├── Fixes/                             # Bug fix verification
│   ├── Test-BITSAuthenticationFix.ps1
│   └── Test-CaptureFFUNetworkConnection.ps1
├── Coverage/                          # Generated coverage reports
└── Results/                           # CI/CD test results
```

## Test Structure

**Suite Organization:**
```powershell
#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for FFU.Core module

.DESCRIPTION
    Comprehensive unit tests covering all exported functions.

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\FFU.Core.Tests.ps1 -Output Detailed
#>

BeforeAll {
    # Get paths relative to test file location
    $TestRoot = Split-Path $PSScriptRoot -Parent
    $ProjectRoot = Split-Path $TestRoot -Parent
    $ModulePath = Join-Path $ProjectRoot 'FFUDevelopment\Modules\FFU.Core'

    # Remove module if loaded (ensures clean state)
    Get-Module -Name 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue

    # Import the module
    Import-Module "$ModulePath\FFU.Core.psd1" -Force -ErrorAction Stop
}

AfterAll {
    # Cleanup
    Get-Module -Name 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue
}

Describe 'FunctionName' -Tag 'Unit', 'FFU.Core', 'FunctionName' {
    Context 'Parameter Validation' {
        It 'Should have mandatory parameter' { }
    }

    Context 'Expected Behavior' {
        It 'Should return expected result' { }
    }

    Context 'Error Handling' {
        It 'Should throw on invalid input' { }
    }
}
```

**Patterns:**

1. **BeforeAll/AfterAll for module setup:**
```powershell
BeforeAll {
    $ModulesPath = Join-Path $ProjectRoot 'FFUDevelopment\Modules'

    # Add to PSModulePath for RequiredModules resolution
    if ($env:PSModulePath -notlike "*$ModulesPath*") {
        $env:PSModulePath = "$ModulesPath;$env:PSModulePath"
    }

    # Import dependencies first
    Import-Module "$CoreModulePath\FFU.Core.psd1" -Force -ErrorAction SilentlyContinue
    Import-Module "$ModulePath\FFU.Drivers.psd1" -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name 'FFU.Drivers', 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue
}
```

2. **BeforeEach/AfterEach for test isolation:**
```powershell
Context 'Cleanup Registry' {
    BeforeEach {
        Clear-CleanupRegistry -ErrorAction SilentlyContinue
    }

    AfterEach {
        Clear-CleanupRegistry -ErrorAction SilentlyContinue
    }
}
```

3. **Tags for filtering:**
```powershell
Describe 'Get-ShortenedWindowsSKU' -Tag 'Unit', 'FFU.Core', 'Get-ShortenedWindowsSKU' {
```

## Mocking

**Framework:** Pester built-in Mock

**Patterns:**
```powershell
# Basic mock in BeforeAll
BeforeAll {
    Mock Start-Process { } -ModuleName '[MODULE_NAME]'
    Mock Test-Path { return $true } -ModuleName '[MODULE_NAME]'
    Mock Get-Content { return '{"key": "value"}' } -ModuleName '[MODULE_NAME]'
}

# Context-specific mock
Context 'With Mocked Dependencies' {
    It 'Should call external command with correct parameters' {
        FunctionName -Path 'C:\Test\Path'

        Should -Invoke Start-Process -Times 1 -Exactly -ModuleName '[MODULE_NAME]' -ParameterFilter {
            $FilePath -eq 'expected.exe'
        }
    }
}

# Mock to simulate failure
It 'Should handle dependency failure' {
    Mock Start-Process { throw 'Process failed' } -ModuleName '[MODULE_NAME]'
    { FunctionName -Path 'C:\Test\Path' } | Should -Throw '*Process failed*'
}

# Mock Hyper-V cmdlets
Mock Get-VMSwitch {
    @(
        [PSCustomObject]@{ Name = 'External'; SwitchType = 'External' }
    )
} -ModuleName 'FFU.Preflight'
```

**What to Mock:**
- External cmdlets (Hyper-V, DISM, network)
- File system operations when testing logic
- Web requests and downloads
- WriteLog function (when testing non-logging behavior)

**What NOT to Mock:**
- The function under test
- Pure logic/calculation functions
- Module loading (test actual imports)

## Fixtures and Factories

**Test Data:**
```powershell
# ForEach pattern for data-driven tests
It 'Should map "<SKU>" to "<Expected>"' -ForEach @(
    @{ SKU = 'Core'; Expected = 'Home' }
    @{ SKU = 'Home'; Expected = 'Home' }
    @{ SKU = 'Professional'; Expected = 'Pro' }
    @{ SKU = 'Enterprise'; Expected = 'Ent' }
) {
    Get-ShortenedWindowsSKU -WindowsSKU $SKU | Should -Be $Expected
}

# Creating test objects
$script:config = New-VMConfiguration -Name 'TestVM' `
                                     -Path 'C:\VMs\Test' `
                                     -MemoryBytes 8GB `
                                     -ProcessorCount 4 `
                                     -VirtualDiskPath 'C:\VMs\Test\TestVM.vhdx'
```

**Location:**
- Inline in test files (no separate fixtures directory)
- Use `-ForEach` for parameterized tests
- Use `$script:` scope for shared test data in BeforeAll

**Helper Functions:**
```powershell
# In BeforeAll block
$script:HypervisorModule = Get-Module -Name 'FFU.Hypervisor'
function Invoke-InModuleScope {
    param([scriptblock]$ScriptBlock)
    & $script:HypervisorModule $ScriptBlock
}

# Usage - access internal classes
$config = Invoke-InModuleScope { [VMConfiguration]::new() }
```

## Coverage

**Requirements:** No formal coverage threshold enforced, but coverage reports generated

**View Coverage:**
```powershell
# Generate coverage report
.\Tests\Unit\Invoke-PesterTests.ps1 -EnableCodeCoverage

# Coverage output location
Tests/Coverage/coverage-{timestamp}.xml  # JaCoCo format

# Manual Pester coverage
Invoke-Pester -Path .\Tests\Unit\FFU.Core.Tests.ps1 `
              -CodeCoverage .\FFUDevelopment\Modules\FFU.Core\*.psm1
```

**Coverage Targets:**
```powershell
# Modules covered by default runner
$config.CodeCoverage.Path = @(
    (Join-Path $ModulesPath 'FFU.Core\*.psm1'),
    (Join-Path $ModulesPath 'FFU.ADK\*.psm1'),
    (Join-Path $ModulesPath 'FFU.Apps\*.psm1'),
    (Join-Path $ModulesPath 'FFU.Drivers\*.psm1'),
    (Join-Path $ModulesPath 'FFU.Imaging\*.psm1'),
    (Join-Path $ModulesPath 'FFU.Media\*.psm1'),
    (Join-Path $ModulesPath 'FFU.Updates\*.psm1'),
    (Join-Path $ModulesPath 'FFU.VM\*.psm1')
)
```

## Test Types

**Unit Tests (`Tests/Unit/`):**
- Test individual functions in isolation
- Mock external dependencies
- Focus on parameter validation, return values, error handling
- Use `-Tag 'Unit'` for filtering

**Integration Tests (`Tests/Integration/`):**
- Test cross-module interactions
- Test UI integration (`Test-UIIntegration.ps1`)
- Test configuration file validation
- May require real resources (filesystem, network)

**Fix Verification Tests (`Tests/Fixes/`):**
- Verify specific bug fixes
- Often regression tests
- Named after the fix: `Test-BITSAuthenticationFix.ps1`

**Module Tests (`Tests/Modules/`):**
- Test module loading and exports
- Validate manifest correctness
- Test function availability

## Common Patterns

**Parameter Validation Testing:**
```powershell
Context 'Parameter Validation' {
    It 'Should have mandatory WindowsSKU parameter' {
        $command = Get-Command -Name 'Get-ShortenedWindowsSKU' -Module 'FFU.Core'
        $param = $command.Parameters['WindowsSKU']

        $param | Should -Not -BeNullOrEmpty
        $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
            ForEach-Object { $_.Mandatory | Should -BeTrue }
    }

    It 'Should have ValidateNotNullOrEmpty attribute' {
        $command = Get-Command -Name 'Get-ShortenedWindowsSKU' -Module 'FFU.Core'
        $param = $command.Parameters['WindowsSKU']

        $hasValidation = $param.Attributes | Where-Object {
            $_ -is [System.Management.Automation.ValidateNotNullOrEmptyAttribute]
        }
        $hasValidation | Should -Not -BeNullOrEmpty
    }

    It 'Should reject empty string' {
        { Get-ShortenedWindowsSKU -WindowsSKU '' } | Should -Throw
    }

    It 'Should reject null value' {
        { Get-ShortenedWindowsSKU -WindowsSKU $null } | Should -Throw
    }
}
```

**Error Testing:**
```powershell
Context 'Error Handling' {
    It 'Should throw on invalid input' {
        { FunctionName -ParameterName 'InvalidValue' } | Should -Throw
    }

    It 'Should throw specific exception type' {
        { FunctionName -ParameterName 'InvalidValue' } |
            Should -Throw -ExceptionType ([System.ArgumentException])
    }

    It 'Should include helpful error message' {
        { FunctionName -ParameterName 'InvalidValue' } |
            Should -Throw -ExpectedMessage '*specific text*'
    }
}
```

**Output Type Testing:**
```powershell
Context 'Output Type' {
    It 'Should return a string' {
        $result = Get-ShortenedWindowsSKU -WindowsSKU 'Pro'
        $result | Should -BeOfType [string]
    }

    It 'Should return exactly one value' {
        $result = @(Get-ShortenedWindowsSKU -WindowsSKU 'Pro')
        $result.Count | Should -Be 1
    }

    It 'Should return valid result object' {
        $result = New-FFUCheckResult -CheckName 'Test' -Status 'Passed' -Message 'OK'
        $result | Should -Not -BeNullOrEmpty
        $result.CheckName | Should -Be 'Test'
        $result.Status | Should -Be 'Passed'
    }
}
```

**Module Export Verification:**
```powershell
Describe 'FFU.Core Module Exports' -Tag 'Unit', 'FFU.Core', 'Module' {

    Context 'Expected Functions Are Exported' {
        It 'Should export Get-ShortenedWindowsSKU' {
            Get-Command -Name 'Get-ShortenedWindowsSKU' -Module 'FFU.Core' | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Module Metadata' {
        It 'Should have a valid module manifest' {
            $ManifestPath = Join-Path $ProjectRoot 'FFUDevelopment\Modules\FFU.Core\FFU.Core.psd1'
            Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop | Should -Not -BeNullOrEmpty
        }
    }
}
```

**Conditional/Skip Tests:**
```powershell
# Skip test based on condition
It 'Should pass when running as Administrator' -Skip:(-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $result = Test-FFUAdministrator
    $result.Status | Should -Be 'Passed'
}
```

## CI/CD Integration

**Test Results Output:**
```powershell
# Enable NUnit XML output for CI
.\Tests\Unit\Invoke-PesterTests.ps1 -EnableTestResults

# Output location
Tests/Results/testResults-{timestamp}.xml  # NUnit format
```

**Exit Codes:**
```powershell
# From Invoke-PesterTests.ps1
if ($result.FailedCount -gt 0) {
    exit 1
}
exit 0
```

**Summary Display:**
```powershell
Write-Host "Passed:  $($result.PassedCount)" -ForegroundColor Green
Write-Host "Failed:  $($result.FailedCount)" -ForegroundColor $(if ($result.FailedCount -gt 0) { 'Red' } else { 'Green' })
Write-Host "Skipped: $($result.SkippedCount)" -ForegroundColor Yellow
Write-Host "Total:   $($result.TotalCount)" -ForegroundColor White
```

---

*Testing analysis: 2026-01-16*
