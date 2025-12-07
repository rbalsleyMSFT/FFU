#Requires -Version 5.1

<#
.SYNOPSIS
    Runs Pester unit tests for FFU Builder modules

.DESCRIPTION
    Executes Pester 5.x unit tests with configurable options for output verbosity,
    code coverage, and CI/CD integration. Supports running all tests or specific
    module tests.

.PARAMETER Module
    Specific module to test (e.g., 'FFU.Core', 'FFU.VM'). If not specified, runs all tests.

.PARAMETER OutputVerbosity
    Level of output detail: Minimal, Normal, Detailed, Diagnostic
    Default: Detailed

.PARAMETER EnableCodeCoverage
    Enable code coverage analysis. Generates coverage report in Tests\Coverage\

.PARAMETER EnableTestResults
    Enable test result XML output for CI/CD integration. Outputs to Tests\Results\

.PARAMETER Tag
    Run only tests with specific tags (e.g., 'Unit', 'ErrorHandling')

.PARAMETER ExcludeTag
    Exclude tests with specific tags

.EXAMPLE
    .\Invoke-PesterTests.ps1
    Runs all unit tests with detailed output

.EXAMPLE
    .\Invoke-PesterTests.ps1 -Module 'FFU.Core'
    Runs only FFU.Core module tests

.EXAMPLE
    .\Invoke-PesterTests.ps1 -EnableCodeCoverage
    Runs all tests with code coverage analysis

.EXAMPLE
    .\Invoke-PesterTests.ps1 -EnableTestResults -OutputVerbosity Minimal
    Runs tests with CI/CD output format

.EXAMPLE
    .\Invoke-PesterTests.ps1 -Tag 'ErrorHandling'
    Runs only tests tagged with 'ErrorHandling'

.NOTES
    Requires Pester 5.0.0 or later
    Install with: Install-Module -Name Pester -Force -SkipPublisherCheck
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('FFU.Core', 'FFU.ADK', 'FFU.Apps', 'FFU.Drivers', 'FFU.Imaging', 'FFU.Media', 'FFU.Updates', 'FFU.VM')]
    [string]$Module,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Minimal', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$OutputVerbosity = 'Detailed',

    [Parameter(Mandatory = $false)]
    [switch]$EnableCodeCoverage,

    [Parameter(Mandatory = $false)]
    [switch]$EnableTestResults,

    [Parameter(Mandatory = $false)]
    [string[]]$Tag,

    [Parameter(Mandatory = $false)]
    [string[]]$ExcludeTag
)

# Ensure Pester is available
$pesterModule = Get-Module -Name Pester -ListAvailable | Where-Object { $_.Version -ge '5.0.0' }
if (-not $pesterModule) {
    Write-Host "Pester 5.0.0+ not found. Installing..." -ForegroundColor Yellow
    Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser
}

Import-Module Pester -MinimumVersion 5.0.0 -Force

# Define paths
$TestRoot = $PSScriptRoot
$ProjectRoot = Split-Path (Split-Path $TestRoot -Parent) -Parent
$ModulesPath = Join-Path $ProjectRoot 'FFUDevelopment\Modules'
$CoveragePath = Join-Path (Split-Path $TestRoot -Parent) 'Coverage'
$ResultsPath = Join-Path (Split-Path $TestRoot -Parent) 'Results'

# Ensure output directories exist
if ($EnableCodeCoverage) {
    New-Item -Path $CoveragePath -ItemType Directory -Force | Out-Null
}
if ($EnableTestResults) {
    New-Item -Path $ResultsPath -ItemType Directory -Force | Out-Null
}

# Build Pester configuration
$config = New-PesterConfiguration

# Test path
if ($Module) {
    $config.Run.Path = Join-Path $TestRoot "$Module.Tests.ps1"
    if (-not (Test-Path $config.Run.Path.Value)) {
        Write-Error "Test file not found: $($config.Run.Path.Value)"
        exit 1
    }
}
else {
    $config.Run.Path = $TestRoot
}

# Output configuration
$config.Output.Verbosity = $OutputVerbosity

# Tag filtering
if ($Tag) {
    $config.Filter.Tag = $Tag
}
if ($ExcludeTag) {
    $config.Filter.ExcludeTag = $ExcludeTag
}

# Code coverage configuration
if ($EnableCodeCoverage) {
    $config.CodeCoverage.Enabled = $true

    if ($Module) {
        $config.CodeCoverage.Path = Join-Path $ModulesPath "$Module\*.psm1"
    }
    else {
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
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $config.CodeCoverage.OutputPath = Join-Path $CoveragePath "coverage-$timestamp.xml"
    $config.CodeCoverage.OutputFormat = 'JaCoCo'

    Write-Host "Code coverage enabled. Output: $($config.CodeCoverage.OutputPath.Value)" -ForegroundColor Cyan
}

# Test results configuration (for CI/CD)
if ($EnableTestResults) {
    $config.TestResult.Enabled = $true
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $config.TestResult.OutputPath = Join-Path $ResultsPath "testResults-$timestamp.xml"
    $config.TestResult.OutputFormat = 'NUnitXml'

    Write-Host "Test results enabled. Output: $($config.TestResult.OutputPath.Value)" -ForegroundColor Cyan
}

# Display configuration summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "FFU Builder Pester Unit Tests" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Test Path: $($config.Run.Path.Value)" -ForegroundColor Gray
Write-Host "Verbosity: $OutputVerbosity" -ForegroundColor Gray
if ($Tag) { Write-Host "Tags: $($Tag -join ', ')" -ForegroundColor Gray }
if ($ExcludeTag) { Write-Host "Excluded Tags: $($ExcludeTag -join ', ')" -ForegroundColor Gray }
Write-Host "Code Coverage: $($EnableCodeCoverage.IsPresent)" -ForegroundColor Gray
Write-Host "Test Results: $($EnableTestResults.IsPresent)" -ForegroundColor Gray
Write-Host "========================================`n" -ForegroundColor Cyan

# Run tests
$result = Invoke-Pester -Configuration $config

# Display summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Passed:  $($result.PassedCount)" -ForegroundColor Green
Write-Host "Failed:  $($result.FailedCount)" -ForegroundColor $(if ($result.FailedCount -gt 0) { 'Red' } else { 'Green' })
Write-Host "Skipped: $($result.SkippedCount)" -ForegroundColor Yellow
Write-Host "Total:   $($result.TotalCount)" -ForegroundColor White

if ($EnableCodeCoverage -and $result.CodeCoverage) {
    $coverage = [math]::Round(($result.CodeCoverage.CommandsExecutedCount / $result.CodeCoverage.CommandsAnalyzedCount) * 100, 2)
    Write-Host "`nCode Coverage: $coverage%" -ForegroundColor $(if ($coverage -ge 80) { 'Green' } elseif ($coverage -ge 60) { 'Yellow' } else { 'Red' })
}

Write-Host "========================================`n" -ForegroundColor Cyan

# Return appropriate exit code
if ($result.FailedCount -gt 0) {
    exit 1
}
exit 0
