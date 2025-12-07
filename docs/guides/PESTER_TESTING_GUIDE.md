# FFU Builder Pester Testing Guide

**Version:** 1.0.0
**Date:** December 2025
**Status:** Active Development

## Overview

This guide covers the Pester 5.x unit testing framework for FFU Builder. Pester is PowerShell's official testing framework, providing structured test syntax, assertions, mocking, and code coverage analysis.

## Quick Start

### Prerequisites

```powershell
# Install Pester 5.x (if not already installed)
Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser

# Verify installation
Get-Module -Name Pester -ListAvailable | Select-Object Name, Version
```

### Running Tests

```powershell
# Navigate to project root
cd C:\claude\FFUBuilder

# Run all unit tests
.\Tests\Unit\Invoke-PesterTests.ps1

# Run specific module tests
.\Tests\Unit\Invoke-PesterTests.ps1 -Module 'FFU.Core'

# Run with code coverage
.\Tests\Unit\Invoke-PesterTests.ps1 -EnableCodeCoverage

# Run with CI/CD output
.\Tests\Unit\Invoke-PesterTests.ps1 -EnableTestResults -OutputVerbosity Minimal
```

## Directory Structure

```
Tests/
├── Unit/                           # Pester unit tests
│   ├── Invoke-PesterTests.ps1      # Test runner script
│   ├── _Template.Tests.ps1         # Template for new test files
│   ├── FFU.Core.Tests.ps1          # FFU.Core module tests
│   ├── FFU.ADK.Tests.ps1           # (To be created)
│   ├── FFU.Apps.Tests.ps1          # (To be created)
│   ├── FFU.Drivers.Tests.ps1       # (To be created)
│   ├── FFU.Imaging.Tests.ps1       # (To be created)
│   ├── FFU.Media.Tests.ps1         # (To be created)
│   ├── FFU.Updates.Tests.ps1       # (To be created)
│   └── FFU.VM.Tests.ps1            # (To be created)
├── Coverage/                       # Code coverage reports
│   └── coverage-*.xml              # JaCoCo format coverage
├── Results/                        # Test result reports
│   └── testResults-*.xml           # NUnit XML format
├── Integration/                    # Existing integration tests
├── Fixes/                          # Fix validation tests
└── Modules/                        # Module-level tests
```

## Writing Tests

### Test File Structure

Every test file follows this pattern:

```powershell
#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    # Import the module being tested
    $ModulePath = Join-Path $ProjectRoot 'FFUDevelopment\Modules\FFU.Core'
    Import-Module "$ModulePath\FFU.Core.psd1" -Force
}

AfterAll {
    # Cleanup
    Get-Module -Name 'FFU.Core' | Remove-Module -Force
}

Describe 'FunctionName' -Tag 'Unit', 'FFU.Core' {
    Context 'Parameter Validation' {
        It 'Should have mandatory parameter' { ... }
    }

    Context 'Expected Behavior' {
        It 'Should return expected result' { ... }
    }

    Context 'Error Handling' {
        It 'Should throw on invalid input' { ... }
    }
}
```

### Pester 5.x Syntax

#### Assertions (Should)

```powershell
# Equality
$result | Should -Be 'Expected'
$result | Should -BeExactly 'Expected'     # Case-sensitive
$result | Should -Not -Be 'Unexpected'

# Null/Empty
$result | Should -BeNullOrEmpty
$result | Should -Not -BeNullOrEmpty

# Boolean
$result | Should -BeTrue
$result | Should -BeFalse

# Collections
$result | Should -Contain 'Item'
$result | Should -HaveCount 5
$result.Count | Should -BeGreaterThan 0

# Types
$result | Should -BeOfType [string]

# Exceptions
{ Throw-Error } | Should -Throw
{ Throw-Error } | Should -Throw -ExceptionType ([System.ArgumentException])
{ Throw-Error } | Should -Throw -ExpectedMessage '*text*'

# Patterns
$result | Should -Match 'regex'
$result | Should -BeLike '*wildcard*'

# File System
$path | Should -Exist
```

#### Data-Driven Tests

```powershell
It 'Should map "<SKU>" to "<Expected>"' -ForEach @(
    @{ SKU = 'Enterprise'; Expected = 'Ent' }
    @{ SKU = 'Professional'; Expected = 'Pro' }
    @{ SKU = 'Education'; Expected = 'Edu' }
) {
    Get-ShortenedWindowsSKU -WindowsSKU $SKU | Should -Be $Expected
}
```

#### Mocking

```powershell
Describe 'Function-WithDependencies' {
    BeforeAll {
        # Mock external cmdlets
        Mock Start-BitsTransfer { return @{ JobState = 'Transferred' } }
        Mock Test-Path { return $true }
    }

    It 'Should call dependency with correct parameters' {
        Function-Name -Url 'https://example.com'

        Should -Invoke Start-BitsTransfer -Times 1 -ParameterFilter {
            $Source -eq 'https://example.com'
        }
    }

    It 'Should handle dependency failure' {
        Mock Start-BitsTransfer { throw 'Network error' }

        { Function-Name -Url 'https://example.com' } | Should -Throw '*Network*'
    }
}
```

### Test Categories

1. **Parameter Validation** - Verify parameter attributes
2. **Expected Behavior** - Verify function logic
3. **Error Handling** - Verify error conditions
4. **Edge Cases** - Verify boundary conditions
5. **Module Exports** - Verify function exports

## Creating New Test Files

1. Copy `Tests\Unit\_Template.Tests.ps1`
2. Rename to `[ModuleName].Tests.ps1`
3. Replace `[MODULE_NAME]` placeholders
4. Add Describe blocks for each exported function
5. Run tests to verify

### Example: Adding FFU.VM Tests

```powershell
# 1. Copy template
Copy-Item .\Tests\Unit\_Template.Tests.ps1 .\Tests\Unit\FFU.VM.Tests.ps1

# 2. Edit file and replace placeholders
# 3. Run to verify
.\Tests\Unit\Invoke-PesterTests.ps1 -Module 'FFU.VM'
```

## Code Coverage

### Running with Coverage

```powershell
# All modules
.\Tests\Unit\Invoke-PesterTests.ps1 -EnableCodeCoverage

# Specific module
.\Tests\Unit\Invoke-PesterTests.ps1 -Module 'FFU.Core' -EnableCodeCoverage
```

### Coverage Goals

| Module | Target | Priority |
|--------|--------|----------|
| FFU.Core | 90% | Critical |
| FFU.VM | 85% | High |
| FFU.Updates | 85% | High |
| FFU.Imaging | 80% | High |
| FFU.ADK | 80% | Medium |
| FFU.Drivers | 75% | Medium |
| FFU.Apps | 75% | Medium |
| FFU.Media | 75% | Medium |

### Viewing Coverage Reports

Coverage reports are generated in JaCoCo XML format at `Tests\Coverage\coverage-*.xml`. These can be:
- Viewed in VS Code with coverage extensions
- Uploaded to SonarQube, Codecov, or Coveralls
- Parsed with PowerShell for summary reports

## CI/CD Integration

### Azure DevOps Pipeline

```yaml
- task: PowerShell@2
  displayName: 'Run Pester Tests'
  inputs:
    targetType: 'inline'
    script: |
      Install-Module -Name Pester -Force -SkipPublisherCheck
      .\Tests\Unit\Invoke-PesterTests.ps1 -EnableTestResults -OutputVerbosity Minimal
    pwsh: true

- task: PublishTestResults@2
  displayName: 'Publish Test Results'
  inputs:
    testResultsFormat: 'NUnit'
    testResultsFiles: 'Tests/Results/*.xml'
```

### GitHub Actions

```yaml
- name: Run Pester Tests
  shell: pwsh
  run: |
    Install-Module -Name Pester -Force -SkipPublisherCheck
    .\Tests\Unit\Invoke-PesterTests.ps1 -EnableTestResults -EnableCodeCoverage

- name: Upload Test Results
  uses: actions/upload-artifact@v3
  with:
    name: test-results
    path: Tests/Results/*.xml
```

## Using the Pester Test Developer Agent

The `pester-test-developer` agent is specialized for creating and maintaining Pester tests.

### When to Use

- Creating tests for new functions
- Running test suites with coverage
- Debugging test failures
- Adding mocking to tests
- Improving test coverage

### Example Invocation

```
User: Create Pester tests for the New-FFUVM function
Assistant: [Uses pester-test-developer agent to analyze function and create comprehensive tests]
```

## Best Practices

### Do

- Test ONE behavior per `It` block
- Use descriptive test names
- Group related tests in `Context` blocks
- Mock external dependencies
- Clean up after tests
- Use appropriate tags for filtering

### Don't

- Depend on external resources (network, files)
- Depend on test execution order
- Share state between tests
- Skip cleanup on failure
- Use production credentials

### Naming Conventions

```powershell
# Test file: [ModuleName].Tests.ps1
FFU.Core.Tests.ps1

# Describe block: Function name
Describe 'Get-ShortenedWindowsSKU' { }

# Context: Scenario category
Context 'Parameter Validation' { }
Context 'Expected Behavior' { }
Context 'Error Handling' { }

# It block: "Should [expected behavior]"
It 'Should return Pro for Professional input' { }
It 'Should throw on null input' { }
```

## Troubleshooting

### Module Not Found

```powershell
# Error: Module 'FFU.Core' not found
# Solution: Check module path in BeforeAll block
$ModulePath = Join-Path $ProjectRoot 'FFUDevelopment\Modules\FFU.Core'
```

### Pester Version Issues

```powershell
# Error: Requires Pester 5.0.0
# Solution: Install/update Pester
Install-Module -Name Pester -Force -SkipPublisherCheck
```

### Mock Not Working

```powershell
# Issue: Mock not intercepting calls
# Solution: Specify -ModuleName parameter
Mock Start-BitsTransfer { } -ModuleName 'FFU.Updates'
```

### Test State Bleeding

```powershell
# Issue: Tests affecting each other
# Solution: Use BeforeEach/AfterEach for isolation
BeforeEach {
    Clear-CleanupRegistry
}
AfterEach {
    Clear-CleanupRegistry
}
```

## References

- [Pester Documentation](https://pester.dev/docs/quick-start)
- [Pester GitHub](https://github.com/pester/Pester)
- [PowerShell Testing Best Practices](https://docs.microsoft.com/en-us/powershell/scripting/developer/cmdlet/testing-cmdlets)
