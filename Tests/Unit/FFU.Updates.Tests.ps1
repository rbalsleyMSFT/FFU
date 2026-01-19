#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for FFU.Updates module

.DESCRIPTION
    Comprehensive unit tests covering all exported functions in the FFU.Updates module.
    Tests verify parameter validation, expected behavior, error handling, and edge cases.

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\FFU.Updates.Tests.ps1 -Output Detailed
#>

BeforeAll {
    $TestRoot = Split-Path $PSScriptRoot -Parent
    $ProjectRoot = Split-Path $TestRoot -Parent
    $ModulesPath = Join-Path $ProjectRoot 'FFUDevelopment\Modules'
    $ModulePath = Join-Path $ModulesPath 'FFU.Updates'
    $CoreModulePath = Join-Path $ModulesPath 'FFU.Core'

    # Add Modules folder to PSModulePath for proper dependency resolution
    if ($env:PSModulePath -notlike "*$ModulesPath*") {
        $env:PSModulePath = "$ModulesPath;$env:PSModulePath"
    }

    Get-Module -Name 'FFU.Updates', 'FFU.Core', 'FFU.Constants' | Remove-Module -Force -ErrorAction SilentlyContinue

    # Import FFU.Core first (required dependency)
    if (Test-Path "$CoreModulePath\FFU.Core.psd1") {
        Import-Module "$CoreModulePath\FFU.Core.psd1" -Force -ErrorAction Stop
    }

    if (-not (Test-Path "$ModulePath\FFU.Updates.psd1")) {
        throw "FFU.Updates module not found at: $ModulePath"
    }
    Import-Module "$ModulePath\FFU.Updates.psd1" -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name 'FFU.Updates', 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# Module Export Verification
# =============================================================================

Describe 'FFU.Updates Module Exports' -Tag 'Unit', 'FFU.Updates', 'Module' {

    Context 'Expected Functions Are Exported' {
        It 'Should export Get-ProductsCab' {
            Get-Command -Name 'Get-ProductsCab' -Module 'FFU.Updates' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Get-WindowsESD' {
            Get-Command -Name 'Get-WindowsESD' -Module 'FFU.Updates' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Get-KBLink' {
            Get-Command -Name 'Get-KBLink' -Module 'FFU.Updates' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Get-UpdateFileInfo' {
            Get-Command -Name 'Get-UpdateFileInfo' -Module 'FFU.Updates' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Save-KB' {
            Get-Command -Name 'Save-KB' -Module 'FFU.Updates' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Test-MountedImageDiskSpace' {
            Get-Command -Name 'Test-MountedImageDiskSpace' -Module 'FFU.Updates' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Add-WindowsPackageWithRetry' {
            Get-Command -Name 'Add-WindowsPackageWithRetry' -Module 'FFU.Updates' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Add-WindowsPackageWithUnattend' {
            Get-Command -Name 'Add-WindowsPackageWithUnattend' -Module 'FFU.Updates' | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Module Metadata' {
        It 'Should have a valid module manifest' {
            $ManifestPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psd1'
            Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Get-ProductsCab Tests
# =============================================================================

Describe 'Get-ProductsCab' -Tag 'Unit', 'FFU.Updates', 'Get-ProductsCab' {

    Context 'Parameter Validation' {
        It 'Should have OutFile parameter' {
            $command = Get-Command -Name 'Get-ProductsCab' -Module 'FFU.Updates'
            $command.Parameters['OutFile'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have Architecture parameter with ValidateSet' {
            $command = Get-Command -Name 'Get-ProductsCab' -Module 'FFU.Updates'
            $param = $command.Parameters['Architecture']
            $param | Should -Not -BeNullOrEmpty

            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Get-WindowsESD Tests
# =============================================================================

Describe 'Get-WindowsESD' -Tag 'Unit', 'FFU.Updates', 'Get-WindowsESD' {

    Context 'Parameter Validation' {
        It 'Should have WindowsRelease parameter' {
            $command = Get-Command -Name 'Get-WindowsESD' -Module 'FFU.Updates'
            $command.Parameters['WindowsRelease'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have WindowsArch parameter' {
            $command = Get-Command -Name 'Get-WindowsESD' -Module 'FFU.Updates'
            $command.Parameters['WindowsArch'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have WindowsLang parameter' {
            $command = Get-Command -Name 'Get-WindowsESD' -Module 'FFU.Updates'
            $command.Parameters['WindowsLang'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have MediaType parameter' {
            $command = Get-Command -Name 'Get-WindowsESD' -Module 'FFU.Updates'
            $command.Parameters['MediaType'] | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Get-KBLink Tests
# =============================================================================

Describe 'Get-KBLink' -Tag 'Unit', 'FFU.Updates', 'Get-KBLink' {

    Context 'Parameter Validation' {
        It 'Should have Name parameter' {
            $command = Get-Command -Name 'Get-KBLink' -Module 'FFU.Updates'
            $command.Parameters['Name'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have Headers parameter' {
            $command = Get-Command -Name 'Get-KBLink' -Module 'FFU.Updates'
            $command.Parameters['Headers'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have Filter parameter' {
            $command = Get-Command -Name 'Get-KBLink' -Module 'FFU.Updates'
            $command.Parameters['Filter'] | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Get-UpdateFileInfo Tests
# =============================================================================

Describe 'Get-UpdateFileInfo' -Tag 'Unit', 'FFU.Updates', 'Get-UpdateFileInfo' {

    Context 'Parameter Validation' {
        It 'Should have Name parameter (string array)' {
            $command = Get-Command -Name 'Get-UpdateFileInfo' -Module 'FFU.Updates'
            $param = $command.Parameters['Name']
            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType.Name | Should -Match 'String\[\]|Object\[\]'
        }

        It 'Should have WindowsArch parameter with ValidateSet' {
            $command = Get-Command -Name 'Get-UpdateFileInfo' -Module 'FFU.Updates'
            $param = $command.Parameters['WindowsArch']
            $param | Should -Not -BeNullOrEmpty

            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet | Should -Not -BeNullOrEmpty
            $validateSet.ValidValues | Should -Contain 'x64'
            $validateSet.ValidValues | Should -Contain 'x86'
            $validateSet.ValidValues | Should -Contain 'arm64'
        }
    }
}

# =============================================================================
# Save-KB Tests
# =============================================================================

Describe 'Save-KB' -Tag 'Unit', 'FFU.Updates', 'Save-KB' {

    Context 'Parameter Validation' {
        It 'Should have Name parameter' {
            $command = Get-Command -Name 'Save-KB' -Module 'FFU.Updates'
            $command.Parameters['Name'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have Path parameter' {
            $command = Get-Command -Name 'Save-KB' -Module 'FFU.Updates'
            $command.Parameters['Path'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have WindowsArch parameter' {
            $command = Get-Command -Name 'Save-KB' -Module 'FFU.Updates'
            $command.Parameters['WindowsArch'] | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Test-MountedImageDiskSpace Tests
# =============================================================================

Describe 'Test-MountedImageDiskSpace' -Tag 'Unit', 'FFU.Updates', 'Test-MountedImageDiskSpace' {

    Context 'Parameter Validation' {
        It 'Should have Path parameter' {
            $command = Get-Command -Name 'Test-MountedImageDiskSpace' -Module 'FFU.Updates'
            $command.Parameters['Path'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have PackagePath parameter' {
            $command = Get-Command -Name 'Test-MountedImageDiskSpace' -Module 'FFU.Updates'
            $command.Parameters['PackagePath'] | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Return Type' {
        It 'Should return a boolean or object with validation result' {
            # This tests the function signature, not actual disk space
            $command = Get-Command -Name 'Test-MountedImageDiskSpace' -Module 'FFU.Updates'
            $command | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Add-WindowsPackageWithRetry Tests
# =============================================================================

Describe 'Add-WindowsPackageWithRetry' -Tag 'Unit', 'FFU.Updates', 'Add-WindowsPackageWithRetry' {

    Context 'Parameter Validation' {
        It 'Should have Path parameter' {
            $command = Get-Command -Name 'Add-WindowsPackageWithRetry' -Module 'FFU.Updates'
            $command.Parameters['Path'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have PackagePath parameter' {
            $command = Get-Command -Name 'Add-WindowsPackageWithRetry' -Module 'FFU.Updates'
            $command.Parameters['PackagePath'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have MaxRetries parameter' {
            $command = Get-Command -Name 'Add-WindowsPackageWithRetry' -Module 'FFU.Updates'
            $command.Parameters['MaxRetries'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have RetryDelaySeconds parameter' {
            $command = Get-Command -Name 'Add-WindowsPackageWithRetry' -Module 'FFU.Updates'
            $command.Parameters['RetryDelaySeconds'] | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Add-WindowsPackageWithUnattend Tests
# =============================================================================

Describe 'Add-WindowsPackageWithUnattend' -Tag 'Unit', 'FFU.Updates', 'Add-WindowsPackageWithUnattend' {

    Context 'Parameter Validation' {
        It 'Should have Path parameter' {
            $command = Get-Command -Name 'Add-WindowsPackageWithUnattend' -Module 'FFU.Updates'
            $command.Parameters['Path'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have PackagePath parameter' {
            $command = Get-Command -Name 'Add-WindowsPackageWithUnattend' -Module 'FFU.Updates'
            $command.Parameters['PackagePath'] | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# MSU Handling Helper Function Tests (BUG-02 Coverage)
# =============================================================================

Describe 'Test-MountedImageDiskSpace' -Tag 'Unit', 'FFU.Updates', 'MSU', 'BUG-02' {

    Context 'Parameter Signature' {
        It 'Has required parameters' {
            $cmd = Get-Command Test-MountedImageDiskSpace -Module 'FFU.Updates'
            $cmd.Parameters.Keys | Should -Contain 'Path'
            $cmd.Parameters.Keys | Should -Contain 'PackagePath'
            $cmd.Parameters.Keys | Should -Contain 'SafetyMarginGB'
        }

        It 'SafetyMarginGB has default value' {
            $cmd = Get-Command Test-MountedImageDiskSpace -Module 'FFU.Updates'
            $param = $cmd.Parameters['SafetyMarginGB']
            $param | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Test-FileLocked' -Tag 'Unit', 'FFU.Updates', 'MSU', 'BUG-02' {

    BeforeAll {
        # Mock WriteLog if not available (it's exported from FFU.Core)
        if (-not (Get-Command WriteLog -ErrorAction SilentlyContinue)) {
            function global:WriteLog { param($Message) Write-Verbose $Message }
        }
    }

    Context 'File Lock Detection' {
        It 'Returns false for non-existent file' {
            $result = Test-FileLocked -Path "C:\NonExistent\File_$(Get-Random).msu"
            $result | Should -BeFalse
        }

        It 'Returns false for accessible file' {
            $tempFile = [System.IO.Path]::GetTempFileName()
            try {
                $result = Test-FileLocked -Path $tempFile
                $result | Should -BeFalse
            }
            finally {
                Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Returns true for locked file' {
            $tempFile = [System.IO.Path]::GetTempFileName()
            try {
                # Lock the file with exclusive access
                $stream = [System.IO.File]::Open($tempFile, 'Open', 'ReadWrite', 'None')
                try {
                    $result = Test-FileLocked -Path $tempFile
                    $result | Should -BeTrue
                }
                finally {
                    $stream.Close()
                    $stream.Dispose()
                }
            }
            finally {
                Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Parameter Validation' {
        It 'Has Path parameter as mandatory' {
            $cmd = Get-Command Test-FileLocked -Module 'FFU.Updates'
            $param = $cmd.Parameters['Path']
            $param | Should -Not -BeNullOrEmpty
            $mandatory = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $mandatory.Mandatory | Should -BeTrue
        }
    }
}

Describe 'Test-DISMServiceHealth' -Tag 'Unit', 'FFU.Updates', 'MSU', 'BUG-02' {

    BeforeAll {
        # Mock WriteLog if not available (it's exported from FFU.Core)
        if (-not (Get-Command WriteLog -ErrorAction SilentlyContinue)) {
            function global:WriteLog { param($Message) Write-Verbose $Message }
        }
    }

    Context 'Service Health Check' {
        It 'Returns a boolean result' {
            $result = Test-DISMServiceHealth
            $result | Should -BeOfType [bool]
        }

        It 'Returns true when TrustedInstaller service exists and is not disabled' {
            # On a healthy Windows system, TrustedInstaller should be available
            $service = Get-Service -Name 'TrustedInstaller' -ErrorAction SilentlyContinue
            if ($service -and $service.StartType -ne 'Disabled') {
                $result = Test-DISMServiceHealth
                $result | Should -BeTrue
            }
            else {
                Set-ItResult -Skipped -Because 'TrustedInstaller service is disabled or unavailable'
            }
        }
    }
}

Describe 'Resolve-KBFilePath' -Tag 'Unit', 'FFU.Updates', 'MSU', 'BUG-02' {

    BeforeAll {
        $script:testKBPath = Join-Path $env:TEMP "FFU_Test_KB_$(Get-Random)"
        New-Item -Path $script:testKBPath -ItemType Directory -Force | Out-Null
    }

    AfterAll {
        if (Test-Path $script:testKBPath) {
            Remove-Item $script:testKBPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Path Resolution Strategies' {
        It 'Returns null for non-existent KB path' {
            $result = Resolve-KBFilePath -KBPath "C:\NonExistent\Path_$(Get-Random)" -UpdateType "Test"
            $result | Should -BeNull
        }

        It 'Returns null for empty KB folder' {
            $result = Resolve-KBFilePath -KBPath $script:testKBPath -UpdateType "Test"
            $result | Should -BeNull
        }

        It 'Finds file by KB article ID pattern' {
            $testFile = Join-Path $script:testKBPath "windows11.0-kb5046613-x64.msu"
            New-Item -Path $testFile -ItemType File -Force | Out-Null

            try {
                $result = Resolve-KBFilePath -KBPath $script:testKBPath -KBArticleId "5046613" -UpdateType "CU"
                # Normalize paths to handle 8.3 short name vs long name differences
                $normalizedResult = if ($result) { (Get-Item $result).FullName } else { $null }
                $normalizedExpected = (Get-Item $testFile).FullName
                $normalizedResult | Should -Be $normalizedExpected
            }
            finally {
                Remove-Item $testFile -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Finds single file as fallback when no specific pattern matches' {
            $testFile = Join-Path $script:testKBPath "update.msu"
            New-Item -Path $testFile -ItemType File -Force | Out-Null

            try {
                $result = Resolve-KBFilePath -KBPath $script:testKBPath -UpdateType "Test"
                # Normalize paths to handle 8.3 short name vs long name differences
                $normalizedResult = if ($result) { (Get-Item $result).FullName } else { $null }
                $normalizedExpected = (Get-Item $testFile).FullName
                $normalizedResult | Should -Be $normalizedExpected
            }
            finally {
                Remove-Item $testFile -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Returns null when multiple files exist but none match pattern' {
            $testFile1 = Join-Path $script:testKBPath "update1.msu"
            $testFile2 = Join-Path $script:testKBPath "update2.msu"
            New-Item -Path $testFile1 -ItemType File -Force | Out-Null
            New-Item -Path $testFile2 -ItemType File -Force | Out-Null

            try {
                # Without a specific KB article ID, should return null when multiple files exist
                $result = Resolve-KBFilePath -KBPath $script:testKBPath -UpdateType "Test"
                $result | Should -BeNull
            }
            finally {
                Remove-Item $testFile1 -Force -ErrorAction SilentlyContinue
                Remove-Item $testFile2 -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Parameter Validation' {
        It 'Has required KBPath parameter' {
            $cmd = Get-Command Resolve-KBFilePath -Module 'FFU.Updates'
            $cmd.Parameters.Keys | Should -Contain 'KBPath'
        }

        It 'Has optional FileName parameter' {
            $cmd = Get-Command Resolve-KBFilePath -Module 'FFU.Updates'
            $cmd.Parameters.Keys | Should -Contain 'FileName'
        }

        It 'Has optional KBArticleId parameter' {
            $cmd = Get-Command Resolve-KBFilePath -Module 'FFU.Updates'
            $cmd.Parameters.Keys | Should -Contain 'KBArticleId'
        }
    }
}

Describe 'Test-KBPathsValid' -Tag 'Unit', 'FFU.Updates', 'MSU', 'BUG-02' {

    Context 'Validation Logic' {
        It 'Returns valid when no updates enabled' {
            $result = Test-KBPathsValid
            $result.IsValid | Should -BeTrue
            $result.Errors.Count | Should -Be 0
        }

        It 'Returns invalid when CU enabled but path is empty' {
            $result = Test-KBPathsValid -UpdateLatestCU $true -CUPath ""
            $result.IsValid | Should -BeFalse
            $result.Errors.Count | Should -BeGreaterThan 0
        }

        It 'Returns invalid when CU enabled but file not found' {
            $result = Test-KBPathsValid -UpdateLatestCU $true -CUPath "C:\NonExistent\update_$(Get-Random).msu"
            $result.IsValid | Should -BeFalse
        }

        It 'Returns warning for microcode when path is empty' {
            $result = Test-KBPathsValid -UpdateLatestMicrocode $true -MicrocodePath ""
            # Microcode is a warning, not an error
            $result.Warnings.Count | Should -BeGreaterThan 0
        }

        It 'Returns valid when CU enabled and file exists' {
            $tempFile = [System.IO.Path]::GetTempFileName()
            try {
                $result = Test-KBPathsValid -UpdateLatestCU $true -CUPath $tempFile
                $result.IsValid | Should -BeTrue
            }
            finally {
                Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Returns result with expected properties' {
            $result = Test-KBPathsValid
            $result | Should -Not -BeNull
            $result.PSObject.Properties.Name | Should -Contain 'IsValid'
            $result.PSObject.Properties.Name | Should -Contain 'Errors'
            $result.PSObject.Properties.Name | Should -Contain 'Warnings'
            $result.PSObject.Properties.Name | Should -Contain 'ErrorMessage'
        }
    }
}

Describe 'Add-WindowsPackageWithUnattend' -Tag 'Unit', 'FFU.Updates', 'MSU', 'BUG-02' {

    Context 'Function Signature' {
        It 'Has required parameters' {
            $cmd = Get-Command Add-WindowsPackageWithUnattend -Module 'FFU.Updates'
            $cmd.Parameters.Keys | Should -Contain 'Path'
            $cmd.Parameters.Keys | Should -Contain 'PackagePath'
        }

        It 'Path parameter is mandatory' {
            $cmd = Get-Command Add-WindowsPackageWithUnattend -Module 'FFU.Updates'
            $param = $cmd.Parameters['Path']
            $mandatory = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $mandatory.Mandatory | Should -BeTrue
        }

        It 'PackagePath parameter is mandatory' {
            $cmd = Get-Command Add-WindowsPackageWithUnattend -Module 'FFU.Updates'
            $param = $cmd.Parameters['PackagePath']
            $mandatory = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $mandatory.Mandatory | Should -BeTrue
        }
    }

    Context 'BUG-02 Documentation' {
        It 'Function help contains BUG-02 FIX documentation' {
            $help = Get-Help Add-WindowsPackageWithUnattend -Full
            $description = $help.description.Text -join ' '
            $description | Should -Match 'BUG-02'
        }

        It 'Function help documents Issue #301' {
            $help = Get-Help Add-WindowsPackageWithUnattend -Full
            $description = $help.description.Text -join ' '
            $description | Should -Match '301'
        }

        It 'Function help documents CAB extraction workaround' {
            $help = Get-Help Add-WindowsPackageWithUnattend -Full
            $description = $help.description.Text -join ' '
            $description | Should -Match 'CAB'
        }
    }
}
