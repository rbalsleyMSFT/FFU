#Requires -Module Pester
<#
.SYNOPSIS
    Tests for FFU Builder module dependencies and load order.

.DESCRIPTION
    Comprehensive tests validating:
    - RequiredModules declarations are present and correct
    - Required modules exist in the Modules folder
    - No circular dependencies
    - Proper load order (FFU.Constants -> FFU.Core -> other modules)
    - Function availability after imports
    - Manifest validity and consistency

.NOTES
    Module Dependency Hierarchy:
    FFU.Constants (foundation, no dependencies)
    └── FFU.Core (requires FFU.Constants)
        ├── FFU.ADK (requires FFU.Core)
        ├── FFU.Apps (requires FFU.Core)
        ├── FFU.Drivers (requires FFU.Core)
        ├── FFU.Imaging (requires FFU.Core)
        ├── FFU.Updates (requires FFU.Core)
        ├── FFU.VM (requires FFU.Core)
        └── FFU.Media (requires FFU.Core, FFU.ADK)
#>

BeforeAll {
    # Get the module root path
    $script:ModulesPath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\Modules'
    $script:ModulesPath = [System.IO.Path]::GetFullPath($script:ModulesPath)

    # Define the expected dependency hierarchy
    $script:ExpectedDependencies = @{
        'FFU.Constants' = @()
        'FFU.Core'      = @('FFU.Constants')
        'FFU.ADK'       = @('FFU.Core')
        'FFU.Apps'      = @('FFU.Core')
        'FFU.Drivers'   = @('FFU.Core')
        'FFU.Imaging'   = @('FFU.Core')
        'FFU.Media'     = @('FFU.Core', 'FFU.ADK')
        'FFU.Updates'   = @('FFU.Core')
        'FFU.VM'        = @('FFU.Core')
    }

    # All modules in the project
    $script:AllModules = @(
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

    # Helper function to get RequiredModules from a manifest
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

    function Get-ManifestRequiredModules {
        param([string]$ModuleName)

        $manifestPath = Join-Path $script:ModulesPath "$ModuleName\$ModuleName.psd1"
        if (-not (Test-Path $manifestPath)) {
            return $null
        }

        $manifest = Import-ManifestData -Path $manifestPath
        $requiredModules = @()

        if ($manifest.RequiredModules) {
            foreach ($req in $manifest.RequiredModules) {
                if ($req -is [hashtable]) {
                    $requiredModules += $req.ModuleName
                } elseif ($req -is [string]) {
                    $requiredModules += $req
                }
            }
        }

        return $requiredModules
    }
}

Describe 'Module Dependency Declaration Tests' {
    Context 'Module Directory Structure' {
        It 'Modules directory should exist' {
            Test-Path $script:ModulesPath | Should -BeTrue
        }

        It 'Each module should have its own directory' -ForEach @(
            @{ModuleName = 'FFU.Constants'}
            @{ModuleName = 'FFU.Core'}
            @{ModuleName = 'FFU.ADK'}
            @{ModuleName = 'FFU.Apps'}
            @{ModuleName = 'FFU.Drivers'}
            @{ModuleName = 'FFU.Imaging'}
            @{ModuleName = 'FFU.Media'}
            @{ModuleName = 'FFU.Updates'}
            @{ModuleName = 'FFU.VM'}
        ) {
            $modulePath = Join-Path $script:ModulesPath $ModuleName
            Test-Path $modulePath -PathType Container | Should -BeTrue -Because "Module directory for $ModuleName should exist"
        }

        It 'Each module should have a manifest (.psd1) file' -ForEach @(
            @{ModuleName = 'FFU.Constants'}
            @{ModuleName = 'FFU.Core'}
            @{ModuleName = 'FFU.ADK'}
            @{ModuleName = 'FFU.Apps'}
            @{ModuleName = 'FFU.Drivers'}
            @{ModuleName = 'FFU.Imaging'}
            @{ModuleName = 'FFU.Media'}
            @{ModuleName = 'FFU.Updates'}
            @{ModuleName = 'FFU.VM'}
        ) {
            $manifestPath = Join-Path $script:ModulesPath "$ModuleName\$ModuleName.psd1"
            Test-Path $manifestPath | Should -BeTrue -Because "$ModuleName should have a manifest file"
        }

        It 'Each module should have a module file (.psm1)' -ForEach @(
            @{ModuleName = 'FFU.Constants'}
            @{ModuleName = 'FFU.Core'}
            @{ModuleName = 'FFU.ADK'}
            @{ModuleName = 'FFU.Apps'}
            @{ModuleName = 'FFU.Drivers'}
            @{ModuleName = 'FFU.Imaging'}
            @{ModuleName = 'FFU.Media'}
            @{ModuleName = 'FFU.Updates'}
            @{ModuleName = 'FFU.VM'}
        ) {
            $modulePath = Join-Path $script:ModulesPath "$ModuleName\$ModuleName.psm1"
            Test-Path $modulePath | Should -BeTrue -Because "$ModuleName should have a .psm1 file"
        }
    }

    Context 'RequiredModules Declarations' {
        It 'FFU.Constants should have no required modules (foundation module)' {
            $required = Get-ManifestRequiredModules -ModuleName 'FFU.Constants'
            $required.Count | Should -Be 0 -Because 'FFU.Constants is the foundation module with no dependencies'
        }

        It 'FFU.Core should require FFU.Constants' {
            $required = Get-ManifestRequiredModules -ModuleName 'FFU.Core'
            $required | Should -Contain 'FFU.Constants' -Because 'FFU.Core depends on FFU.Constants for configuration values'
        }

        It 'FFU.ADK should require FFU.Core' {
            $required = Get-ManifestRequiredModules -ModuleName 'FFU.ADK'
            $required | Should -Contain 'FFU.Core' -Because 'FFU.ADK uses WriteLog and other core functions'
        }

        It 'FFU.Apps should require FFU.Core' {
            $required = Get-ManifestRequiredModules -ModuleName 'FFU.Apps'
            $required | Should -Contain 'FFU.Core' -Because 'FFU.Apps uses WriteLog and other core functions'
        }

        It 'FFU.Drivers should require FFU.Core' {
            $required = Get-ManifestRequiredModules -ModuleName 'FFU.Drivers'
            $required | Should -Contain 'FFU.Core' -Because 'FFU.Drivers uses WriteLog and other core functions'
        }

        It 'FFU.Imaging should require FFU.Core' {
            $required = Get-ManifestRequiredModules -ModuleName 'FFU.Imaging'
            $required | Should -Contain 'FFU.Core' -Because 'FFU.Imaging uses WriteLog and other core functions'
        }

        It 'FFU.Updates should require FFU.Core' {
            $required = Get-ManifestRequiredModules -ModuleName 'FFU.Updates'
            $required | Should -Contain 'FFU.Core' -Because 'FFU.Updates uses WriteLog and other core functions'
        }

        It 'FFU.VM should require FFU.Core' {
            $required = Get-ManifestRequiredModules -ModuleName 'FFU.VM'
            $required | Should -Contain 'FFU.Core' -Because 'FFU.VM uses WriteLog and other core functions'
        }

        It 'FFU.Media should require both FFU.Core and FFU.ADK' {
            $required = Get-ManifestRequiredModules -ModuleName 'FFU.Media'
            $required | Should -Contain 'FFU.Core' -Because 'FFU.Media uses core functions'
            $required | Should -Contain 'FFU.ADK' -Because 'FFU.Media depends on ADK validation functions'
        }
    }

    Context 'Required Modules Exist' {
        It '<ModuleName> required modules should exist in Modules folder' -ForEach @(
            @{ModuleName = 'FFU.Core'; Expected = @('FFU.Constants')}
            @{ModuleName = 'FFU.ADK'; Expected = @('FFU.Core')}
            @{ModuleName = 'FFU.Apps'; Expected = @('FFU.Core')}
            @{ModuleName = 'FFU.Drivers'; Expected = @('FFU.Core')}
            @{ModuleName = 'FFU.Imaging'; Expected = @('FFU.Core')}
            @{ModuleName = 'FFU.Media'; Expected = @('FFU.Core', 'FFU.ADK')}
            @{ModuleName = 'FFU.Updates'; Expected = @('FFU.Core')}
            @{ModuleName = 'FFU.VM'; Expected = @('FFU.Core')}
        ) {
            foreach ($requiredModule in $Expected) {
                $requiredPath = Join-Path $script:ModulesPath "$requiredModule\$requiredModule.psd1"
                Test-Path $requiredPath | Should -BeTrue -Because "$ModuleName requires $requiredModule which should exist"
            }
        }
    }

    Context 'No Circular Dependencies' {
        It 'Should not have circular dependencies' {
            # Build a dependency graph and check for cycles
            $visited = @{}
            $recursionStack = @{}

            function Test-HasCycle {
                param([string]$Module)

                if ($recursionStack[$Module]) {
                    return $true  # Cycle detected
                }
                if ($visited[$Module]) {
                    return $false  # Already processed, no cycle from here
                }

                $visited[$Module] = $true
                $recursionStack[$Module] = $true

                $deps = $script:ExpectedDependencies[$Module]
                if ($deps) {
                    foreach ($dep in $deps) {
                        if (Test-HasCycle -Module $dep) {
                            return $true
                        }
                    }
                }

                $recursionStack[$Module] = $false
                return $false
            }

            $hasCycle = $false
            foreach ($module in $script:AllModules) {
                $visited = @{}
                $recursionStack = @{}
                if (Test-HasCycle -Module $module) {
                    $hasCycle = $true
                    break
                }
            }

            $hasCycle | Should -BeFalse -Because 'Module dependencies should not have cycles'
        }
    }
}

Describe 'Module Load Order Tests' {
    BeforeAll {
        # Add modules path to PSModulePath for import tests
        if ($env:PSModulePath -notlike "*$script:ModulesPath*") {
            $env:PSModulePath = "$script:ModulesPath;$env:PSModulePath"
        }
    }

    Context 'Foundation Module (FFU.Constants)' {
        It 'FFU.Constants should load without any dependencies' {
            # Test in isolated runspace - suppress warnings with WarningAction
            $result = pwsh -NoProfile -Command @"
                `$env:PSModulePath = '$script:ModulesPath;' + `$env:PSModulePath
                `$WarningPreference = 'SilentlyContinue'
                try {
                    Import-Module FFU.Constants -Force -ErrorAction Stop -WarningAction SilentlyContinue
                    'SUCCESS'
                } catch {
                    `$_.Exception.Message
                }
"@
            $result | Should -Be 'SUCCESS' -Because 'FFU.Constants should load with no dependencies'
        }

        It 'FFUConstants class should be available after importing FFU.Constants' {
            # FFUConstants is a class exported via 'using module' syntax
            # PowerShell classes require the using statement in the same scope where they're used
            $result = pwsh -NoProfile -Command @"
                `$env:PSModulePath = '$script:ModulesPath;' + `$env:PSModulePath
                `$WarningPreference = 'SilentlyContinue'
                # Use ScriptBlock with 'using module' to access the class type
                `$modulePath = Join-Path '$script:ModulesPath' 'FFU.Constants\FFU.Constants.psm1'
                try {
                    # Import the module first
                    Import-Module FFU.Constants -Force -ErrorAction Stop -WarningAction SilentlyContinue
                    # Check if the module exports the class by invoking a method via ScriptBlock
                    `$checkScript = [ScriptBlock]::Create('using module FFU.Constants; [FFUConstants]::GetBasePath()')
                    `$basePath = & `$checkScript
                    if (`$basePath) { 'CLASS_AVAILABLE' } else { 'CLASS_NOT_FOUND' }
                } catch {
                    'CLASS_ERROR'
                }
"@
            $result | Should -Be 'CLASS_AVAILABLE' -Because 'FFUConstants class should be accessible'
        }
    }

    Context 'Core Module (FFU.Core)' {
        It 'FFU.Core should load after FFU.Constants' {
            $result = pwsh -NoProfile -Command @"
                `$env:PSModulePath = '$script:ModulesPath;' + `$env:PSModulePath
                `$WarningPreference = 'SilentlyContinue'
                try {
                    Import-Module FFU.Constants -Force -ErrorAction Stop -WarningAction SilentlyContinue
                    Import-Module FFU.Core -Force -ErrorAction Stop -WarningAction SilentlyContinue
                    'SUCCESS'
                } catch {
                    `$_.Exception.Message
                }
"@
            $result | Should -Be 'SUCCESS' -Because 'FFU.Core should load after FFU.Constants'
        }

        It 'FFU.Core should auto-load FFU.Constants via RequiredModules' {
            $result = pwsh -NoProfile -Command @"
                `$env:PSModulePath = '$script:ModulesPath;' + `$env:PSModulePath
                `$WarningPreference = 'SilentlyContinue'
                try {
                    # Only import FFU.Core - FFU.Constants should load automatically
                    Import-Module FFU.Core -Force -ErrorAction Stop -WarningAction SilentlyContinue
                    if (Get-Module FFU.Constants) {
                        'DEPENDENCY_LOADED'
                    } else {
                        'DEPENDENCY_NOT_LOADED'
                    }
                } catch {
                    `$_.Exception.Message
                }
"@
            $result | Should -Be 'DEPENDENCY_LOADED' -Because 'FFU.Constants should be auto-loaded as a required module'
        }
    }

    Context 'Dependent Modules' {
        It '<ModuleName> should load after its dependencies' -ForEach @(
            @{ModuleName = 'FFU.ADK'}
            @{ModuleName = 'FFU.Apps'}
            @{ModuleName = 'FFU.Drivers'}
            @{ModuleName = 'FFU.Imaging'}
            @{ModuleName = 'FFU.Updates'}
            @{ModuleName = 'FFU.VM'}
        ) {
            $result = pwsh -NoProfile -Command @"
                `$env:PSModulePath = '$script:ModulesPath;' + `$env:PSModulePath
                `$WarningPreference = 'SilentlyContinue'
                try {
                    Import-Module $ModuleName -Force -ErrorAction Stop -WarningAction SilentlyContinue
                    'SUCCESS'
                } catch {
                    `$_.Exception.Message
                }
"@
            $result | Should -Be 'SUCCESS' -Because "$ModuleName should load with its dependencies"
        }

        It 'FFU.Media should load after FFU.Core and FFU.ADK' {
            $result = pwsh -NoProfile -Command @"
                `$env:PSModulePath = '$script:ModulesPath;' + `$env:PSModulePath
                `$WarningPreference = 'SilentlyContinue'
                try {
                    Import-Module FFU.Media -Force -ErrorAction Stop -WarningAction SilentlyContinue
                    `$loaded = (Get-Module FFU.Core) -and (Get-Module FFU.ADK)
                    if (`$loaded) { 'SUCCESS' } else { 'DEPS_NOT_LOADED' }
                } catch {
                    `$_.Exception.Message
                }
"@
            $result | Should -Be 'SUCCESS' -Because 'FFU.Media should auto-load both FFU.Core and FFU.ADK'
        }
    }

    Context 'All Modules Load Successfully' {
        It 'All 9 modules should load in the correct order' {
            $result = pwsh -NoProfile -Command @"
                `$env:PSModulePath = '$script:ModulesPath;' + `$env:PSModulePath
                `$WarningPreference = 'SilentlyContinue'
                `$modules = @('FFU.Constants', 'FFU.Core', 'FFU.ADK', 'FFU.Apps',
                             'FFU.Drivers', 'FFU.Imaging', 'FFU.Media', 'FFU.Updates', 'FFU.VM')
                try {
                    foreach (`$mod in `$modules) {
                        Import-Module `$mod -Force -ErrorAction Stop -WarningAction SilentlyContinue
                    }
                    (Get-Module -Name 'FFU.*').Count
                } catch {
                    "ERROR: `$(`$_.Exception.Message)"
                }
"@
            [int]$result | Should -Be 9 -Because 'All 9 FFU modules should load successfully'
        }
    }
}

Describe 'Function Availability Tests' {
    BeforeAll {
        if ($env:PSModulePath -notlike "*$script:ModulesPath*") {
            $env:PSModulePath = "$script:ModulesPath;$env:PSModulePath"
        }
    }

    Context 'FFU.Constants Class Availability' {
        It 'FFUConstants class should have GetBasePath method' {
            # FFUConstants is a class that requires 'using module' to access the type
            $result = pwsh -NoProfile -Command @"
                `$env:PSModulePath = '$script:ModulesPath;' + `$env:PSModulePath
                `$WarningPreference = 'SilentlyContinue'
                Import-Module FFU.Constants -Force -WarningAction SilentlyContinue
                try {
                    # Use ScriptBlock with 'using module' to access the class type
                    `$checkScript = [ScriptBlock]::Create('using module FFU.Constants; [FFUConstants].GetMethod(''GetBasePath'') -ne `$null')
                    & `$checkScript
                } catch {
                    'False'
                }
"@
            $result | Should -Be 'True'
        }
    }

    Context 'FFU.Core Function Exports' {
        It 'Get-ShortenedWindowsSKU should be available after importing FFU.Core' {
            $result = pwsh -NoProfile -Command @"
                `$env:PSModulePath = '$script:ModulesPath;' + `$env:PSModulePath
                `$WarningPreference = 'SilentlyContinue'
                Import-Module FFU.Core -Force -WarningAction SilentlyContinue
                (Get-Command Get-ShortenedWindowsSKU -ErrorAction SilentlyContinue) -ne `$null
"@
            $result | Should -Be 'True'
        }

        It 'Register-CleanupAction should be available after importing FFU.Core' {
            $result = pwsh -NoProfile -Command @"
                `$env:PSModulePath = '$script:ModulesPath;' + `$env:PSModulePath
                `$WarningPreference = 'SilentlyContinue'
                Import-Module FFU.Core -Force -WarningAction SilentlyContinue
                (Get-Command Register-CleanupAction -ErrorAction SilentlyContinue) -ne `$null
"@
            $result | Should -Be 'True'
        }
    }

    Context 'Dependent Module Function Exports' {
        It '<ModuleName> should export its declared functions' -ForEach @(
            @{ModuleName = 'FFU.ADK'; Function = 'Test-ADKPrerequisites'}
            @{ModuleName = 'FFU.Apps'; Function = 'Get-Office'}
            @{ModuleName = 'FFU.Drivers'; Function = 'Get-DellDrivers'}
            @{ModuleName = 'FFU.Imaging'; Function = 'New-FFU'}
            @{ModuleName = 'FFU.Media'; Function = 'New-PEMedia'}
            @{ModuleName = 'FFU.Updates'; Function = 'Save-KB'}
            @{ModuleName = 'FFU.VM'; Function = 'New-FFUVM'}
        ) {
            $result = pwsh -NoProfile -Command @"
                `$env:PSModulePath = '$script:ModulesPath;' + `$env:PSModulePath
                `$WarningPreference = 'SilentlyContinue'
                Import-Module $ModuleName -Force -WarningAction SilentlyContinue
                (Get-Command $Function -ErrorAction SilentlyContinue) -ne `$null
"@
            $result | Should -Be 'True' -Because "$ModuleName should export $Function"
        }
    }
}

Describe 'Manifest Validation Tests' {
    Context 'Manifest Syntax Validation' {
        It '<ModuleName> manifest should be valid PowerShell data file' -ForEach @(
            @{ModuleName = 'FFU.Constants'}
            @{ModuleName = 'FFU.Core'}
            @{ModuleName = 'FFU.ADK'}
            @{ModuleName = 'FFU.Apps'}
            @{ModuleName = 'FFU.Drivers'}
            @{ModuleName = 'FFU.Imaging'}
            @{ModuleName = 'FFU.Media'}
            @{ModuleName = 'FFU.Updates'}
            @{ModuleName = 'FFU.VM'}
        ) {
            $manifestPath = Join-Path $script:ModulesPath "$ModuleName\$ModuleName.psd1"
            { Import-ManifestData -Path $manifestPath -ErrorAction Stop } | Should -Not -Throw
        }

        It '<ModuleName> manifest should pass Test-ModuleManifest' -ForEach @(
            @{ModuleName = 'FFU.Constants'}
            @{ModuleName = 'FFU.Core'}
            @{ModuleName = 'FFU.ADK'}
            @{ModuleName = 'FFU.Apps'}
            @{ModuleName = 'FFU.Drivers'}
            @{ModuleName = 'FFU.Imaging'}
            @{ModuleName = 'FFU.Media'}
            @{ModuleName = 'FFU.Updates'}
            @{ModuleName = 'FFU.VM'}
        ) {
            $manifestPath = Join-Path $script:ModulesPath "$ModuleName\$ModuleName.psd1"
            # Note: Test-ModuleManifest may warn about RequiredModules not being available
            # We only check that it doesn't throw an error
            { Test-ModuleManifest -Path $manifestPath -ErrorAction Stop } | Should -Not -Throw
        }
    }

    Context 'RequiredModules Format Consistency' {
        It '<ModuleName> RequiredModules should use hashtable format' -ForEach @(
            @{ModuleName = 'FFU.Core'}
            @{ModuleName = 'FFU.ADK'}
            @{ModuleName = 'FFU.Apps'}
            @{ModuleName = 'FFU.Drivers'}
            @{ModuleName = 'FFU.Imaging'}
            @{ModuleName = 'FFU.Media'}
            @{ModuleName = 'FFU.Updates'}
            @{ModuleName = 'FFU.VM'}
        ) {
            $manifestPath = Join-Path $script:ModulesPath "$ModuleName\$ModuleName.psd1"
            $manifest = Import-ManifestData -Path $manifestPath

            if ($manifest.RequiredModules -and $manifest.RequiredModules.Count -gt 0) {
                foreach ($req in $manifest.RequiredModules) {
                    $req | Should -BeOfType [hashtable] -Because "$ModuleName should use hashtable format for RequiredModules"
                    $req.ModuleName | Should -Not -BeNullOrEmpty -Because "RequiredModules hashtable should have ModuleName key"
                    $req.ModuleVersion | Should -Not -BeNullOrEmpty -Because "RequiredModules hashtable should have ModuleVersion key"
                }
            }
        }

        It 'FFU.Constants should have empty or no RequiredModules' {
            $manifestPath = Join-Path $script:ModulesPath "FFU.Constants\FFU.Constants.psd1"
            $manifest = Import-ManifestData -Path $manifestPath

            ($manifest.RequiredModules -eq $null -or $manifest.RequiredModules.Count -eq 0) |
                Should -BeTrue -Because 'FFU.Constants is the foundation module and should have no dependencies'
        }
    }

    Context 'Exported Functions Match Implementation' {
        It '<ModuleName> should export all declared functions' -ForEach @(
            @{ModuleName = 'FFU.Constants'}
            @{ModuleName = 'FFU.Core'}
            @{ModuleName = 'FFU.ADK'}
            @{ModuleName = 'FFU.Apps'}
            @{ModuleName = 'FFU.Drivers'}
            @{ModuleName = 'FFU.Imaging'}
            @{ModuleName = 'FFU.Media'}
            @{ModuleName = 'FFU.Updates'}
            @{ModuleName = 'FFU.VM'}
        ) {
            $manifestPath = Join-Path $script:ModulesPath "$ModuleName\$ModuleName.psd1"
            $manifest = Import-ManifestData -Path $manifestPath

            # Get declared exports from manifest
            $declaredExports = $manifest.FunctionsToExport

            if ($declaredExports -and $declaredExports.Count -gt 0) {
                # Import module and check actual exports
                $result = pwsh -NoProfile -Command @"
                    `$env:PSModulePath = '$script:ModulesPath;' + `$env:PSModulePath
                    Import-Module $ModuleName -Force -ErrorAction SilentlyContinue
                    (Get-Module $ModuleName).ExportedFunctions.Keys -join ','
"@
                $actualExports = $result -split ','

                foreach ($func in $declaredExports) {
                    $actualExports | Should -Contain $func -Because "$ModuleName declares export of $func"
                }
            }
        }
    }
}

Describe 'Module Version Tests' {
    Context 'Version Numbers' {
        It '<ModuleName> should have a valid version number' -ForEach @(
            @{ModuleName = 'FFU.Constants'}
            @{ModuleName = 'FFU.Core'}
            @{ModuleName = 'FFU.ADK'}
            @{ModuleName = 'FFU.Apps'}
            @{ModuleName = 'FFU.Drivers'}
            @{ModuleName = 'FFU.Imaging'}
            @{ModuleName = 'FFU.Media'}
            @{ModuleName = 'FFU.Updates'}
            @{ModuleName = 'FFU.VM'}
        ) {
            $manifestPath = Join-Path $script:ModulesPath "$ModuleName\$ModuleName.psd1"
            $manifest = Import-ManifestData -Path $manifestPath

            $manifest.ModuleVersion | Should -Not -BeNullOrEmpty
            { [version]$manifest.ModuleVersion } | Should -Not -Throw -Because 'ModuleVersion should be a valid version string'
        }

        It 'FFU.Core should be version 1.0.9 or higher (includes FFU.Constants dependency)' {
            $manifestPath = Join-Path $script:ModulesPath "FFU.Core\FFU.Core.psd1"
            $manifest = Import-ManifestData -Path $manifestPath

            [version]$manifest.ModuleVersion | Should -BeGreaterOrEqual ([version]'1.0.9')
        }

        It 'FFU.Drivers should be version 1.0.2 or higher (includes FFU.Core dependency)' {
            $manifestPath = Join-Path $script:ModulesPath "FFU.Drivers\FFU.Drivers.psd1"
            $manifest = Import-ManifestData -Path $manifestPath

            [version]$manifest.ModuleVersion | Should -BeGreaterOrEqual ([version]'1.0.2')
        }
    }
}

Describe 'Dependency Chain Validation' {
    Context 'Transitive Dependencies' {
        It 'FFU.Media should transitively depend on FFU.Constants via FFU.Core' {
            # FFU.Media -> FFU.Core -> FFU.Constants
            $result = pwsh -NoProfile -Command @"
                `$env:PSModulePath = '$script:ModulesPath;' + `$env:PSModulePath
                `$WarningPreference = 'SilentlyContinue'
                Import-Module FFU.Media -Force -WarningAction SilentlyContinue
                (Get-Module FFU.Constants) -ne `$null
"@
            $result | Should -Be 'True' -Because 'FFU.Media should load FFU.Constants transitively'
        }

        It 'Importing any leaf module should load the entire dependency chain' {
            $result = pwsh -NoProfile -Command @"
                `$env:PSModulePath = '$script:ModulesPath;' + `$env:PSModulePath
                `$WarningPreference = 'SilentlyContinue'
                Import-Module FFU.Media -Force -WarningAction SilentlyContinue
                `$loaded = @((Get-Module FFU.Constants), (Get-Module FFU.Core), (Get-Module FFU.ADK), (Get-Module FFU.Media))
                (`$loaded | Where-Object { `$_ -ne `$null }).Count
"@
            [int]$result | Should -Be 4 -Because 'FFU.Media should load all 4 modules in its dependency chain'
        }
    }
}
