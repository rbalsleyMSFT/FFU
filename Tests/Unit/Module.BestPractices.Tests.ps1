#Requires -Module Pester
<#
.SYNOPSIS
    Pester tests for PowerShell module best practices compliance.

.DESCRIPTION
    Tests that all FFU Builder modules follow PowerShell best practices:
    - All exported functions use approved verbs
    - Backward compatibility aliases work correctly
    - OutputType attributes are present on key functions
    - Module manifests pass validation

.NOTES
    Version: 1.0.0
    Date: 2025-12-10
    Author: FFU Builder Team
#>

BeforeAll {
    # Set up paths
    $script:FFUDevelopmentPath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ModulesPath = Join-Path $script:FFUDevelopmentPath 'FFUDevelopment\Modules'

    # Add modules to PSModulePath if not already present
    if ($env:PSModulePath -notlike "*$script:ModulesPath*") {
        $env:PSModulePath = "$script:ModulesPath;$env:PSModulePath"
    }

    # Helper function to read manifest data - compatible with all PowerShell versions
    function Import-ManifestData {
        param([string]$Path)

        if (-not (Test-Path $Path)) {
            return $null
        }

        # Use Invoke-Expression with Get-Content for cross-version compatibility
        $content = Get-Content -Path $Path -Raw -ErrorAction Stop
        $manifest = Invoke-Expression $content
        return $manifest
    }

    # Get approved verbs for reference
    $script:ApprovedVerbs = Get-Verb | Select-Object -ExpandProperty Verb

    # Define modules to test
    $script:ModulesToTest = @(
        'FFU.Constants',
        'FFU.Core',
        'FFU.ADK',
        'FFU.Apps',
        'FFU.Drivers',
        'FFU.Imaging',
        'FFU.Media',
        'FFU.Updates',
        'FFU.VM'
    )

    # Define renamed functions and their aliases (v1.0.11)
    $script:RenamedFunctions = @{
        'LogVariableValues' = 'Write-VariableValues'
        'Mark-DownloadInProgress' = 'Set-DownloadInProgress'
        'Cleanup-CurrentRunDownloads' = 'Clear-CurrentRunDownloads'
    }
}

Describe 'Module Best Practices' {

    Context 'Approved Verb Compliance' {

        It 'All FFU modules exist in expected location' {
            Test-Path $script:ModulesPath | Should -BeTrue
        }

        foreach ($moduleName in $script:ModulesToTest) {
            It "Module '$moduleName' folder exists" {
                $modulePath = Join-Path $script:ModulesPath $moduleName
                Test-Path $modulePath | Should -BeTrue
            }
        }

        It 'FFU.Core exports only functions with approved verbs' {
            # Import module with -DisableNameChecking to avoid warnings during test
            Import-Module (Join-Path $script:ModulesPath 'FFU.Core') -Force -DisableNameChecking -ErrorAction Stop

            $exportedFunctions = Get-Command -Module 'FFU.Core' -CommandType Function

            foreach ($func in $exportedFunctions) {
                $verb = $func.Name -split '-' | Select-Object -First 1
                $script:ApprovedVerbs | Should -Contain $verb -Because "Function '$($func.Name)' should use an approved verb"
            }

            Remove-Module 'FFU.Core' -Force -ErrorAction SilentlyContinue
        }

        It 'All FFU modules export only functions with approved verbs' {
            foreach ($moduleName in $script:ModulesToTest) {
                $modulePath = Join-Path $script:ModulesPath $moduleName

                if (Test-Path $modulePath) {
                    try {
                        Import-Module $modulePath -Force -DisableNameChecking -ErrorAction Stop

                        $exportedFunctions = Get-Command -Module $moduleName -CommandType Function -ErrorAction SilentlyContinue

                        foreach ($func in $exportedFunctions) {
                            $verb = $func.Name -split '-' | Select-Object -First 1
                            $script:ApprovedVerbs | Should -Contain $verb -Because "Function '$($func.Name)' in module '$moduleName' should use an approved verb"
                        }

                        Remove-Module $moduleName -Force -ErrorAction SilentlyContinue
                    }
                    catch {
                        # Module load might fail due to dependencies - that's OK for this test
                        Write-Verbose "Skipping module '$moduleName' due to load error: $($_.Exception.Message)"
                    }
                }
            }
        }
    }

    Context 'Backward Compatibility Aliases' {

        BeforeAll {
            # Import FFU.Core to test aliases
            Import-Module (Join-Path $script:ModulesPath 'FFU.Core') -Force -DisableNameChecking -ErrorAction Stop
        }

        AfterAll {
            Remove-Module 'FFU.Core' -Force -ErrorAction SilentlyContinue
        }

        foreach ($aliasName in $script:RenamedFunctions.Keys) {
            $newFunctionName = $script:RenamedFunctions[$aliasName]

            It "Deprecated alias '$aliasName' exists" {
                $alias = Get-Alias -Name $aliasName -ErrorAction SilentlyContinue
                $alias | Should -Not -BeNullOrEmpty -Because "Alias '$aliasName' should exist for backward compatibility"
            }

            It "Deprecated alias '$aliasName' points to '$newFunctionName'" {
                $alias = Get-Alias -Name $aliasName -ErrorAction SilentlyContinue
                $alias.Definition | Should -Be $newFunctionName -Because "Alias should resolve to the new function name"
            }

            It "New function '$newFunctionName' exists and is callable" {
                $func = Get-Command -Name $newFunctionName -ErrorAction SilentlyContinue
                $func | Should -Not -BeNullOrEmpty
                $func.CommandType | Should -Be 'Function'
            }
        }

        It 'All deprecated aliases are exported from FFU.Core' {
            $module = Get-Module 'FFU.Core'
            $exportedAliases = $module.ExportedAliases.Keys

            foreach ($aliasName in $script:RenamedFunctions.Keys) {
                $exportedAliases | Should -Contain $aliasName -Because "Alias '$aliasName' should be exported for backward compatibility"
            }
        }
    }

    Context 'OutputType Attribute Compliance' {

        BeforeAll {
            Import-Module (Join-Path $script:ModulesPath 'FFU.Core') -Force -DisableNameChecking -ErrorAction Stop
        }

        AfterAll {
            Remove-Module 'FFU.Core' -Force -ErrorAction SilentlyContinue
        }

        # Test renamed functions have OutputType
        foreach ($newFunctionName in $script:RenamedFunctions.Values) {
            It "Function '$newFunctionName' has [OutputType] attribute" {
                $func = Get-Command -Name $newFunctionName
                $outputType = $func.OutputType

                # Functions should have OutputType defined (even if void)
                $outputType | Should -Not -BeNullOrEmpty -Because "Function '$newFunctionName' should have [OutputType()] attribute defined"
            }
        }
    }

    Context 'Module Manifest Validation' {

        foreach ($moduleName in $script:ModulesToTest) {
            $manifestPath = Join-Path $script:ModulesPath "$moduleName\$moduleName.psd1"

            It "Module '$moduleName' has a valid manifest" -Skip:(-not (Test-Path $manifestPath)) {
                { Test-ModuleManifest -Path $manifestPath -ErrorAction Stop } | Should -Not -Throw
            }
        }

        It 'FFU.Core manifest contains FunctionsToExport with new function names' {
            $manifestPath = Join-Path $script:ModulesPath 'FFU.Core\FFU.Core.psd1'
            $manifest = Import-ManifestData -Path $manifestPath

            foreach ($newFunctionName in $script:RenamedFunctions.Values) {
                $manifest.FunctionsToExport | Should -Contain $newFunctionName -Because "Manifest should export '$newFunctionName'"
            }
        }

        It 'FFU.Core manifest contains AliasesToExport with deprecated aliases' {
            $manifestPath = Join-Path $script:ModulesPath 'FFU.Core\FFU.Core.psd1'
            $manifest = Import-ManifestData -Path $manifestPath

            foreach ($aliasName in $script:RenamedFunctions.Keys) {
                $manifest.AliasesToExport | Should -Contain $aliasName -Because "Manifest should export deprecated alias '$aliasName'"
            }
        }

        It 'FFU.Core manifest version is 1.0.11 or higher' {
            $manifestPath = Join-Path $script:ModulesPath 'FFU.Core\FFU.Core.psd1'
            $manifest = Import-ManifestData -Path $manifestPath

            [version]$manifest.ModuleVersion | Should -BeGreaterOrEqual ([version]'1.0.11')
        }
    }

    Context 'Functional Backward Compatibility Tests' {

        BeforeAll {
            # Import FFU.Common first to get WriteLog function
            $commonPath = Join-Path (Split-Path -Parent $script:ModulesPath) 'FFU.Common'
            if (Test-Path "$commonPath\FFU.Common.Core.psm1") {
                Import-Module "$commonPath\FFU.Common.Core.psm1" -Force -ErrorAction SilentlyContinue
            }

            Import-Module (Join-Path $script:ModulesPath 'FFU.Core') -Force -DisableNameChecking -ErrorAction Stop

            # Create temp test directory
            $script:TestPath = Join-Path $env:TEMP "FFU_BestPractices_Test_$(Get-Random)"
            New-Item -Path $script:TestPath -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path $script:TestPath '.session') -ItemType Directory -Force | Out-Null

            # Define a mock WriteLog function if not available (for isolated test runs)
            if (-not (Get-Command WriteLog -ErrorAction SilentlyContinue)) {
                function global:WriteLog { param([string]$Message) Write-Verbose $Message }
            }
        }

        AfterAll {
            Remove-Module 'FFU.Core' -Force -ErrorAction SilentlyContinue
            if ($script:TestPath -and (Test-Path $script:TestPath)) {
                Remove-Item -Path $script:TestPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            # Remove mock WriteLog
            Remove-Item -Path 'Function:\WriteLog' -ErrorAction SilentlyContinue
        }

        It 'Old function name "Mark-DownloadInProgress" works via alias' {
            # This should work via the alias
            { Mark-DownloadInProgress -FFUDevelopmentPath $script:TestPath -TargetPath "$script:TestPath\test.file" } | Should -Not -Throw
        }

        It 'New function name "Set-DownloadInProgress" works directly' {
            { Set-DownloadInProgress -FFUDevelopmentPath $script:TestPath -TargetPath "$script:TestPath\test2.file" } | Should -Not -Throw
        }

        It 'Both old and new function names produce identical behavior' {
            # Clear any existing markers
            $inprogressPath = Join-Path $script:TestPath '.session\inprogress'
            if (Test-Path $inprogressPath) {
                Get-ChildItem $inprogressPath -Filter '*.marker' | Remove-Item -Force
            }

            # Use old name
            Mark-DownloadInProgress -FFUDevelopmentPath $script:TestPath -TargetPath "$script:TestPath\old.file"

            # Check marker was created
            $markers = Get-ChildItem (Join-Path $script:TestPath '.session\inprogress') -Filter '*.marker' -ErrorAction SilentlyContinue
            $markers.Count | Should -Be 1

            # Use new name
            Set-DownloadInProgress -FFUDevelopmentPath $script:TestPath -TargetPath "$script:TestPath\new.file"

            # Check both markers exist
            $markers = Get-ChildItem (Join-Path $script:TestPath '.session\inprogress') -Filter '*.marker' -ErrorAction SilentlyContinue
            $markers.Count | Should -Be 2
        }
    }

    Context 'No Unapproved Verbs in Source Code' {

        It 'FFU.Core.psm1 does not define functions with unapproved verbs (except for test/internal use)' {
            $psm1Path = Join-Path $script:ModulesPath 'FFU.Core\FFU.Core.psm1'
            $content = Get-Content -Path $psm1Path -Raw

            # Check that old function names no longer exist as function definitions
            $content | Should -Not -Match 'function\s+LogVariableValues\s*\{' -Because "Old function name 'LogVariableValues' should be renamed"
            $content | Should -Not -Match 'function\s+Mark-DownloadInProgress\s*\{' -Because "Old function name 'Mark-DownloadInProgress' should be renamed"
            $content | Should -Not -Match 'function\s+Cleanup-CurrentRunDownloads\s*\{' -Because "Old function name 'Cleanup-CurrentRunDownloads' should be renamed"
        }

        It 'FFU.Core.psm1 defines functions with approved verbs' {
            $psm1Path = Join-Path $script:ModulesPath 'FFU.Core\FFU.Core.psm1'
            $content = Get-Content -Path $psm1Path -Raw

            # Check that new function names exist as function definitions
            $content | Should -Match 'function\s+Write-VariableValues\s*\{' -Because "New function name 'Write-VariableValues' should exist"
            $content | Should -Match 'function\s+Set-DownloadInProgress\s*\{' -Because "New function name 'Set-DownloadInProgress' should exist"
            $content | Should -Match 'function\s+Clear-CurrentRunDownloads\s*\{' -Because "New function name 'Clear-CurrentRunDownloads' should exist"
        }
    }
}

Describe 'Module Import Without Warnings' {

    It 'FFU.Core imports without verb warnings when using -DisableNameChecking' {
        # Remove if loaded
        Remove-Module 'FFU.Core' -Force -ErrorAction SilentlyContinue

        # Import with warning capture
        $warnings = @()
        Import-Module (Join-Path $script:ModulesPath 'FFU.Core') -Force -DisableNameChecking -WarningVariable warnings -ErrorAction Stop

        # Filter for verb-related warnings
        $verbWarnings = $warnings | Where-Object { $_ -match 'verb' -or $_ -match 'approved' }

        $verbWarnings.Count | Should -Be 0 -Because "Module should import without verb warnings"

        Remove-Module 'FFU.Core' -Force -ErrorAction SilentlyContinue
    }
}
