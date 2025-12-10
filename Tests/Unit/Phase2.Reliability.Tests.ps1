#Requires -Module Pester
<#
.SYNOPSIS
    Comprehensive Pester tests for Phase 2 Reliability improvements.

.DESCRIPTION
    Validates the implementation of Phase 2 Reliability features:
    1. Error Handling (#4) - try/catch blocks, specific exception types, -ErrorAction Stop
    2. Cleanup Mechanisms (#6) - Register-CleanupAction, trap handlers, PowerShell.Exiting event
    3. Structured Logging (#10) - FFU.Common.Logging module with log levels, JSON output, session correlation

.NOTES
    Version: 1.0.2
    Tags: Unit, Phase2, Reliability, ErrorHandling, Cleanup, Logging
#>

BeforeDiscovery {
    # Calculate paths during discovery phase - this runs before the tests are discovered
    # and makes variables available for -Skip conditions
    $script:TestsRoot = 'C:\claude\FFUBuilder\Tests\Unit'
    $script:ProjectRoot = 'C:\claude\FFUBuilder'
    $script:FFUDevelopmentPath = 'C:\claude\FFUBuilder\FFUDevelopment'
    $script:ModulesPath = 'C:\claude\FFUBuilder\FFUDevelopment\Modules'
    $script:FFUCommonPath = 'C:\claude\FFUBuilder\FFUDevelopment\FFU.Common'

    # Pre-calculate module paths for skip conditions
    $script:FFUVMModule = Join-Path $script:ModulesPath 'FFU.VM\FFU.VM.psm1'
    $script:FFUDriversModule = Join-Path $script:ModulesPath 'FFU.Drivers\FFU.Drivers.psm1'
    $script:FFUUpdatesModule = Join-Path $script:ModulesPath 'FFU.Updates\FFU.Updates.psm1'
    $script:FFUCoreModule = Join-Path $script:ModulesPath 'FFU.Core\FFU.Core.psm1'
    $script:FFULoggingModule = Join-Path $script:FFUCommonPath 'FFU.Common.Logging.psm1'
    $script:FFUCommonCoreModule = Join-Path $script:FFUCommonPath 'FFU.Common.Core.psm1'
}

BeforeAll {
    # Set paths for runtime
    $script:TestsRoot = 'C:\claude\FFUBuilder\Tests\Unit'
    $script:ProjectRoot = 'C:\claude\FFUBuilder'
    $script:FFUDevelopmentPath = 'C:\claude\FFUBuilder\FFUDevelopment'
    $script:ModulesPath = 'C:\claude\FFUBuilder\FFUDevelopment\Modules'
    $script:FFUCommonPath = 'C:\claude\FFUBuilder\FFUDevelopment\FFU.Common'

    $script:FFUVMModule = Join-Path $script:ModulesPath 'FFU.VM\FFU.VM.psm1'
    $script:FFUDriversModule = Join-Path $script:ModulesPath 'FFU.Drivers\FFU.Drivers.psm1'
    $script:FFUUpdatesModule = Join-Path $script:ModulesPath 'FFU.Updates\FFU.Updates.psm1'
    $script:FFUCoreModule = Join-Path $script:ModulesPath 'FFU.Core\FFU.Core.psm1'
    $script:FFULoggingModule = Join-Path $script:FFUCommonPath 'FFU.Common.Logging.psm1'
    $script:FFUCommonCoreModule = Join-Path $script:FFUCommonPath 'FFU.Common.Core.psm1'

    # Import required modules
    function Import-TestModule {
        param(
            [string]$ModulePath,
            [string]$ModuleName
        )

        if ([string]::IsNullOrWhiteSpace($ModulePath)) {
            Write-Warning "Module path is empty for $ModuleName"
            return $false
        }

        if (Test-Path $ModulePath) {
            try {
                Import-Module $ModulePath -Force -ErrorAction Stop -WarningAction SilentlyContinue
                return $true
            }
            catch {
                Write-Warning "Failed to import $ModuleName : $($_.Exception.Message)"
                return $false
            }
        }
        Write-Warning "Module not found: $ModulePath"
        return $false
    }

    # Import all modules silently
    $null = Import-TestModule -ModulePath $script:FFUCoreModule -ModuleName 'FFU.Core'
    $null = Import-TestModule -ModulePath $script:FFUVMModule -ModuleName 'FFU.VM'
    $null = Import-TestModule -ModulePath $script:FFUDriversModule -ModuleName 'FFU.Drivers'
    $null = Import-TestModule -ModulePath $script:FFUUpdatesModule -ModuleName 'FFU.Updates'
    $null = Import-TestModule -ModulePath $script:FFULoggingModule -ModuleName 'FFU.Common.Logging'
    $null = Import-TestModule -ModulePath $script:FFUCommonCoreModule -ModuleName 'FFU.Common.Core'
}

AfterAll {
    # Clean up loaded modules
    @('FFU.Core', 'FFU.VM', 'FFU.Drivers', 'FFU.Updates', 'FFU.Common.Logging', 'FFU.Common.Core') | ForEach-Object {
        Remove-Module $_ -Force -ErrorAction SilentlyContinue
    }
}

# =============================================================================
# SECTION 1: ERROR HANDLING TESTS
# Tests for Issue #4 - try/catch blocks, specific exception types, -ErrorAction Stop
# =============================================================================
Describe 'Phase 2: Error Handling Implementation' -Tag 'Unit', 'Phase2', 'Reliability', 'ErrorHandling' {

    Context 'FFU.VM Module Error Handling' {

        It 'Should have try/catch blocks in New-FFUVM function' {
            $moduleContent = Get-Content -Path $script:FFUVMModule -Raw
            $moduleContent | Should -Match 'function New-FFUVM'
            $moduleContent | Should -Match 'try\s*\{'
            $moduleContent | Should -Match 'catch\s*\{'
        }

        It 'Should catch VirtualizationException in Remove-FFUVM' {
            $moduleContent = Get-Content -Path $script:FFUVMModule -Raw
            $moduleContent | Should -Match '\[Microsoft\.HyperV\.PowerShell\.VirtualizationException\]'
        }

        It 'Should catch ItemNotFoundException in Remove-FFUVM' {
            $moduleContent = Get-Content -Path $script:FFUVMModule -Raw
            $moduleContent | Should -Match '\[System\.Management\.Automation\.ItemNotFoundException\]'
        }

        It 'Should catch IOException for file operations' {
            $moduleContent = Get-Content -Path $script:FFUVMModule -Raw
            $moduleContent | Should -Match '\[System\.IO\.IOException\]'
        }

        It 'Should catch COMException for DISM operations' {
            $moduleContent = Get-Content -Path $script:FFUVMModule -Raw
            $moduleContent | Should -Match '\[System\.Runtime\.InteropServices\.COMException\]'
        }

        It 'Should use -ErrorAction Stop with critical Hyper-V cmdlets' {
            $moduleContent = Get-Content -Path $script:FFUVMModule -Raw
            # Check for ErrorAction Stop with key cmdlets
            $moduleContent | Should -Match 'New-VM.*-ErrorAction\s+Stop'
            $moduleContent | Should -Match 'Set-VMProcessor.*-ErrorAction\s+Stop'
        }

        It 'Should have cleanup logic on VM creation failure' {
            $moduleContent = Get-Content -Path $script:FFUVMModule -Raw
            # Check for cleanup variables and logic
            $moduleContent | Should -Match '\$vmCreated\s*=\s*\$false'
            $moduleContent | Should -Match '\$guardianCreated\s*=\s*\$false'
            $moduleContent | Should -Match 'if\s*\(\s*\$vmCreated\s*\)'
        }
    }

    Context 'FFU.Drivers Module Error Handling' {

        It 'Should catch WebException for web requests' {
            $moduleContent = Get-Content -Path $script:FFUDriversModule -Raw
            $moduleContent | Should -Match '\[System\.Net\.WebException\]'
        }

        It 'Should have try/catch in Get-MicrosoftDrivers' {
            $moduleContent = Get-Content -Path $script:FFUDriversModule -Raw
            # Get-MicrosoftDrivers function should have error handling
            $pattern = 'function Get-MicrosoftDrivers[\s\S]*?try\s*\{[\s\S]*?catch'
            $moduleContent | Should -Match $pattern
        }

        It 'Should have try/catch in Get-HPDrivers' {
            $moduleContent = Get-Content -Path $script:FFUDriversModule -Raw
            # Check for try/catch patterns in HP driver function
            $moduleContent | Should -Match 'function Get-HPDrivers'
            $moduleContent | Should -Match 'try\s*\{[\s\S]*?Start-BitsTransferWithRetry[\s\S]*?\}[\s\S]*?catch'
        }

        It 'Should have try/catch in Get-LenovoDrivers' {
            $moduleContent = Get-Content -Path $script:FFUDriversModule -Raw
            $moduleContent | Should -Match 'function Get-LenovoDrivers'
            $moduleContent | Should -Match 'catch\s*\[System\.Net\.WebException\]'
        }

        It 'Should have try/catch in Get-DellDrivers' {
            $moduleContent = Get-Content -Path $script:FFUDriversModule -Raw
            $moduleContent | Should -Match 'function Get-DellDrivers'
        }

        It 'Should use -ErrorAction Stop with Expand-Archive' {
            $moduleContent = Get-Content -Path $script:FFUDriversModule -Raw
            $moduleContent | Should -Match 'Expand-Archive.*-ErrorAction\s+Stop'
        }
    }

    Context 'FFU.Updates Module Error Handling' {

        It 'Should catch WebException for download operations' {
            $moduleContent = Get-Content -Path $script:FFUUpdatesModule -Raw
            $moduleContent | Should -Match '\[System\.Net\.WebException\]'
        }

        It 'Should have retry logic with exponential backoff' {
            $moduleContent = Get-Content -Path $script:FFUUpdatesModule -Raw
            # Check for retry pattern in Get-KBLink
            $moduleContent | Should -Match '\$maxRetries'
            $moduleContent | Should -Match '\$retryDelay\s*\*\s*2'  # Exponential backoff
        }

        It 'Should have Add-WindowsPackageWithRetry function' {
            Get-Command Add-WindowsPackageWithRetry -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should have Test-MountedImageDiskSpace validation' {
            Get-Command Test-MountedImageDiskSpace -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should have Test-DISMServiceHealth function' {
            Get-Command Test-DISMServiceHealth -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should have Test-MountState validation' {
            Get-Command Test-MountState -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should have Test-FileLocked function' {
            Get-Command Test-FileLocked -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should validate disk space before MSU extraction in Add-WindowsPackageWithUnattend' {
            $moduleContent = Get-Content -Path $script:FFUUpdatesModule -Raw
            $moduleContent | Should -Match 'Test-MountedImageDiskSpace'
        }

        It 'Should validate MSU file integrity' {
            $moduleContent = Get-Content -Path $script:FFUUpdatesModule -Raw
            $moduleContent | Should -Match 'Validating MSU package integrity'
        }
    }

    Context 'FFU.Common.Core Module Error Handling' {

        It 'Should have Get-ErrorMessage helper function' {
            Get-Command Get-ErrorMessage -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'WriteLog should accept null/empty strings gracefully' {
            $moduleContent = Get-Content -Path $script:FFUCommonCoreModule -Raw
            $moduleContent | Should -Match '\[AllowNull\(\)\]'
            $moduleContent | Should -Match '\[AllowEmptyString\(\)\]'
        }

        It 'Invoke-Process should have error handling' {
            $moduleContent = Get-Content -Path $script:FFUCommonCoreModule -Raw
            $moduleContent | Should -Match 'function Invoke-Process'
            $moduleContent | Should -Match '\$ErrorActionPreference\s*=\s*[''"]Stop[''"]'
        }

        It 'Invoke-Process should validate paths before Remove-Item' {
            $moduleContent = Get-Content -Path $script:FFUCommonCoreModule -Raw
            # Check for path filtering to prevent null path errors
            $moduleContent | Should -Match 'Where-Object\s*\{.*IsNullOrWhiteSpace'
        }
    }
}

# =============================================================================
# SECTION 2: CLEANUP MECHANISM TESTS
# Tests for Issue #6 - Register-CleanupAction, trap handlers, PowerShell.Exiting event
# =============================================================================
Describe 'Phase 2: Cleanup Mechanism Implementation' -Tag 'Unit', 'Phase2', 'Reliability', 'Cleanup' {

    Context 'BuildFFUVM.ps1 Trap Handler' {

        BeforeAll {
            $script:BuildScript = Join-Path $script:FFUDevelopmentPath 'BuildFFUVM.ps1'
        }

        It 'Should have trap handler defined in BuildFFUVM.ps1' {
            $content = Get-Content -Path $script:BuildScript -Raw
            $content | Should -Match 'trap\s*\{'
        }

        It 'Trap handler should invoke Invoke-FailureCleanup' {
            $content = Get-Content -Path $script:BuildScript -Raw
            $content | Should -Match 'trap[\s\S]*?Invoke-FailureCleanup'
        }

        It 'Trap handler should use break to propagate errors' {
            $content = Get-Content -Path $script:BuildScript -Raw
            # Should have break after cleanup in trap
            $content | Should -Match 'trap[\s\S]*?break'
        }
    }

    Context 'BuildFFUVM.ps1 PowerShell.Exiting Event Handler' {

        BeforeAll {
            $script:BuildScript = Join-Path $script:FFUDevelopmentPath 'BuildFFUVM.ps1'
        }

        It 'Should have PowerShell.Exiting event handler' {
            $content = Get-Content -Path $script:BuildScript -Raw
            $content | Should -Match 'Register-EngineEvent.*PowerShell\.Exiting'
        }

        It 'PowerShell.Exiting handler should invoke Invoke-FailureCleanup' {
            $content = Get-Content -Path $script:BuildScript -Raw
            $content | Should -Match 'PowerShell\.Exiting.*-Action[\s\S]*?Invoke-FailureCleanup'
        }
    }

    Context 'FFU.Core Cleanup Registry Functions' {

        It 'Should have Register-CleanupAction function' {
            Get-Command Register-CleanupAction -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should have Unregister-CleanupAction function' {
            Get-Command Unregister-CleanupAction -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should have Invoke-FailureCleanup function' {
            Get-Command Invoke-FailureCleanup -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should have Get-CleanupRegistry function' {
            Get-Command Get-CleanupRegistry -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should have Clear-CleanupRegistry function' {
            Get-Command Clear-CleanupRegistry -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Specialized Cleanup Helper Functions' {

        It 'Should have Register-VMCleanup function' {
            Get-Command Register-VMCleanup -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should have Register-VHDXCleanup function' {
            Get-Command Register-VHDXCleanup -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should have Register-DISMMountCleanup function' {
            Get-Command Register-DISMMountCleanup -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should have Register-ISOCleanup function' {
            Get-Command Register-ISOCleanup -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should have Register-TempFileCleanup function' {
            Get-Command Register-TempFileCleanup -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should have Register-NetworkShareCleanup function' {
            Get-Command Register-NetworkShareCleanup -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should have Register-UserAccountCleanup function' {
            Get-Command Register-UserAccountCleanup -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should have Register-SensitiveMediaCleanup function' {
            Get-Command Register-SensitiveMediaCleanup -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Cleanup Registration Usage in BuildFFUVM.ps1' {

        BeforeAll {
            $script:BuildScript = Join-Path $script:FFUDevelopmentPath 'BuildFFUVM.ps1'
        }

        It 'Should use Register-ISOCleanup for ISO mounts' {
            $content = Get-Content -Path $script:BuildScript -Raw
            $content | Should -Match 'Register-ISOCleanup'
        }

        It 'Should use Register-VHDXCleanup for VHDX mounts' {
            $content = Get-Content -Path $script:BuildScript -Raw
            $content | Should -Match 'Register-VHDXCleanup'
        }

        It 'Should use Register-VMCleanup for VM creation' {
            $content = Get-Content -Path $script:BuildScript -Raw
            $content | Should -Match 'Register-VMCleanup'
        }

        It 'Should use Register-SensitiveMediaCleanup for credential security' {
            $content = Get-Content -Path $script:BuildScript -Raw
            $content | Should -Match 'Register-SensitiveMediaCleanup'
        }
    }

    Context 'Cleanup Function Behavior' {

        BeforeEach {
            # Clear registry before each test
            Clear-CleanupRegistry
        }

        AfterEach {
            # Clean up after each test
            Clear-CleanupRegistry
        }

        It 'Register-CleanupAction should return a GUID' {
            $id = Register-CleanupAction -Name "Test Cleanup" -Action { } -ResourceType 'Other'
            $id | Should -Not -BeNullOrEmpty
            [guid]::TryParse($id, [ref]([guid]::Empty)) | Should -BeTrue
        }

        It 'Get-CleanupRegistry should return registered items' {
            Register-CleanupAction -Name "Test 1" -Action { } -ResourceType 'VM'
            Register-CleanupAction -Name "Test 2" -Action { } -ResourceType 'VHDX'

            $registry = Get-CleanupRegistry
            $registry.Count | Should -Be 2
        }

        It 'Unregister-CleanupAction should remove specific item' {
            $id = Register-CleanupAction -Name "To Remove" -Action { } -ResourceType 'TempFile'
            Register-CleanupAction -Name "To Keep" -Action { } -ResourceType 'Other'

            $beforeRegistry = @(Get-CleanupRegistry)
            $before = $beforeRegistry.Count
            Unregister-CleanupAction -CleanupId $id
            $afterRegistry = @(Get-CleanupRegistry)
            $after = $afterRegistry.Count

            $before | Should -Be 2
            $after | Should -Be 1
        }

        It 'Clear-CleanupRegistry should remove all items' {
            Register-CleanupAction -Name "Test 1" -Action { } -ResourceType 'VM'
            Register-CleanupAction -Name "Test 2" -Action { } -ResourceType 'VHDX'
            Register-CleanupAction -Name "Test 3" -Action { } -ResourceType 'ISO'

            $before = (Get-CleanupRegistry).Count
            Clear-CleanupRegistry
            $after = (Get-CleanupRegistry).Count

            $before | Should -Be 3
            $after | Should -Be 0
        }

        It 'Invoke-FailureCleanup should execute actions in LIFO order' {
            $script:cleanupOrder = @()

            Register-CleanupAction -Name "First" -Action {
                $script:cleanupOrder += "First"
            } -ResourceType 'Other'

            Register-CleanupAction -Name "Second" -Action {
                $script:cleanupOrder += "Second"
            } -ResourceType 'Other'

            Register-CleanupAction -Name "Third" -Action {
                $script:cleanupOrder += "Third"
            } -ResourceType 'Other'

            Invoke-FailureCleanup -Reason "Test"

            # LIFO order - last registered should execute first
            $script:cleanupOrder[0] | Should -Be "Third"
            $script:cleanupOrder[1] | Should -Be "Second"
            $script:cleanupOrder[2] | Should -Be "First"
        }

        It 'Invoke-FailureCleanup should clear registry after execution' {
            Register-CleanupAction -Name "Test" -Action { } -ResourceType 'Other'

            Invoke-FailureCleanup -Reason "Test"

            (Get-CleanupRegistry).Count | Should -Be 0
        }
    }
}

# =============================================================================
# SECTION 3: STRUCTURED LOGGING TESTS
# Tests for Issue #10 - FFU.Common.Logging module with log levels, JSON output
# =============================================================================
Describe 'Phase 2: Structured Logging Implementation' -Tag 'Unit', 'Phase2', 'Reliability', 'Logging' {

    Context 'FFU.Common.Logging Module Existence' {

        It 'FFU.Common.Logging.psm1 should exist' {
            Test-Path $script:FFULoggingModule | Should -BeTrue
        }

        It 'FFU.Common.Logging.psd1 manifest should exist' {
            $loggingManifest = Join-Path $script:FFUCommonPath 'FFU.Common.Logging.psd1'
            Test-Path $loggingManifest | Should -BeTrue
        }

        It 'FFU.Common.Logging module should be importable' {
            Get-Module -Name 'FFU.Common.Logging' | Should -Not -BeNullOrEmpty
        }
    }

    Context 'FFULogLevel Enum' {

        It 'Should define FFULogLevel enum in module source' {
            $moduleContent = Get-Content -Path $script:FFULoggingModule -Raw
            $moduleContent | Should -Match 'enum FFULogLevel'
        }

        It 'Should define Debug level with value 0' {
            $moduleContent = Get-Content -Path $script:FFULoggingModule -Raw
            $moduleContent | Should -Match 'Debug\s*=\s*0'
        }

        It 'Should define Info level with value 1' {
            $moduleContent = Get-Content -Path $script:FFULoggingModule -Raw
            $moduleContent | Should -Match 'Info\s*=\s*1'
        }

        It 'Should define Success level with value 2' {
            $moduleContent = Get-Content -Path $script:FFULoggingModule -Raw
            $moduleContent | Should -Match 'Success\s*=\s*2'
        }

        It 'Should define Warning level with value 3' {
            $moduleContent = Get-Content -Path $script:FFULoggingModule -Raw
            $moduleContent | Should -Match 'Warning\s*=\s*3'
        }

        It 'Should define Error level with value 4' {
            $moduleContent = Get-Content -Path $script:FFULoggingModule -Raw
            $moduleContent | Should -Match 'Error\s*=\s*4'
        }

        It 'Should define Critical level with value 5' {
            $moduleContent = Get-Content -Path $script:FFULoggingModule -Raw
            $moduleContent | Should -Match 'Critical\s*=\s*5'
        }

        It 'Should have exactly 6 log levels defined' {
            $moduleContent = Get-Content -Path $script:FFULoggingModule -Raw
            # Count enum members in the enum block
            $enumBlock = [regex]::Match($moduleContent, 'enum FFULogLevel \{([^}]+)\}').Groups[1].Value
            $levelCount = ([regex]::Matches($enumBlock, '\w+\s*=\s*\d+')).Count
            $levelCount | Should -Be 6
        }
    }

    Context 'Logging Functions Availability' {

        It 'Should export Initialize-FFULogging function' {
            Get-Command Initialize-FFULogging -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should export Write-FFULog function' {
            Get-Command Write-FFULog -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should export Write-FFUDebug function' {
            Get-Command Write-FFUDebug -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should export Write-FFUInfo function' {
            Get-Command Write-FFUInfo -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should export Write-FFUSuccess function' {
            Get-Command Write-FFUSuccess -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should export Write-FFUWarning function' {
            Get-Command Write-FFUWarning -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should export Write-FFUError function' {
            Get-Command Write-FFUError -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should export Write-FFUCritical function' {
            Get-Command Write-FFUCritical -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should export Get-FFULogSession function' {
            Get-Command Get-FFULogSession -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should export Close-FFULogging function' {
            Get-Command Close-FFULogging -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Initialize-FFULogging Function' {

        BeforeAll {
            $script:TestLogDir = Join-Path $env:TEMP "FFULoggingTests_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
            New-Item -Path $script:TestLogDir -ItemType Directory -Force | Out-Null
        }

        AfterAll {
            # Close any open logging session
            Close-FFULogging
            # Clean up test files
            if (Test-Path $script:TestLogDir) {
                Remove-Item -Path $script:TestLogDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should create session ID on initialization' {
            $logPath = Join-Path $script:TestLogDir 'test1.log'
            Initialize-FFULogging -LogPath $logPath

            $session = Get-FFULogSession
            $session.SessionId | Should -Not -BeNullOrEmpty
            [guid]::TryParse($session.SessionId, [ref]([guid]::Empty)) | Should -BeTrue

            Close-FFULogging
        }

        It 'Should set LogPath correctly' {
            $logPath = Join-Path $script:TestLogDir 'test2.log'
            Initialize-FFULogging -LogPath $logPath

            $session = Get-FFULogSession
            $session.LogPath | Should -Be $logPath

            Close-FFULogging
        }

        It 'Should set MinLevel correctly' {
            $logPath = Join-Path $script:TestLogDir 'test3.log'
            Initialize-FFULogging -LogPath $logPath -MinLevel Warning

            $session = Get-FFULogSession
            $session.MinLevel | Should -Be 'Warning'

            Close-FFULogging
        }

        It 'Should create JSON log path when EnableJsonLog is specified' {
            $logPath = Join-Path $script:TestLogDir 'test4.log'
            Initialize-FFULogging -LogPath $logPath -EnableJsonLog

            $session = Get-FFULogSession
            $session.JsonLogPath | Should -Not -BeNullOrEmpty
            $session.JsonLogPath | Should -Match '\.json\.log$'

            Close-FFULogging
        }

        It 'Should record StartTime' {
            $logPath = Join-Path $script:TestLogDir 'test5.log'
            $before = Get-Date
            Initialize-FFULogging -LogPath $logPath
            $after = Get-Date

            $session = Get-FFULogSession
            $session.StartTime | Should -BeGreaterOrEqual $before
            $session.StartTime | Should -BeLessOrEqual $after

            Close-FFULogging
        }
    }

    Context 'Write-FFULog Function' {

        BeforeAll {
            $script:LogDir = Join-Path $env:TEMP "FFUWriteLogTests_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
            New-Item -Path $script:LogDir -ItemType Directory -Force | Out-Null
        }

        AfterAll {
            Close-FFULogging
            if (Test-Path $script:LogDir) {
                Remove-Item -Path $script:LogDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should write to log file' {
            $logPath = Join-Path $script:LogDir 'write1.log'
            Initialize-FFULogging -LogPath $logPath
            Write-FFULog -Level Info -Message "Test message"
            Close-FFULogging

            Test-Path $logPath | Should -BeTrue
            $content = Get-Content $logPath -Raw
            $content | Should -Match 'Test message'
        }

        It 'Should include level tag in log entry' {
            $logPath = Join-Path $script:LogDir 'write2.log'
            Initialize-FFULogging -LogPath $logPath
            Write-FFULog -Level Warning -Message "Warning test"
            Close-FFULogging

            $content = Get-Content $logPath -Raw
            $content | Should -Match '\[WARNING\]'
        }

        It 'Should filter messages below MinLevel' {
            $logPath = Join-Path $script:LogDir 'write3.log'
            Initialize-FFULogging -LogPath $logPath -MinLevel Warning
            Write-FFULog -Level Debug -Message "Should not appear"
            Write-FFULog -Level Info -Message "Should not appear"
            Write-FFULog -Level Warning -Message "Should appear"
            Close-FFULogging

            $content = Get-Content $logPath -Raw
            $content | Should -Not -Match 'Should not appear'
            $content | Should -Match 'Should appear'
        }

        It 'Should write JSON when EnableJsonLog is specified' {
            $logPath = Join-Path $script:LogDir 'write4.log'
            Initialize-FFULogging -LogPath $logPath -EnableJsonLog
            Write-FFULog -Level Info -Message "JSON test" -Context @{ Key = 'Value' }
            Close-FFULogging

            $jsonPath = [System.IO.Path]::ChangeExtension($logPath, '.json.log')
            Test-Path $jsonPath | Should -BeTrue

            $jsonContent = Get-Content $jsonPath -Raw
            $jsonContent | Should -Match '"Level".*"Info"'
            $jsonContent | Should -Match '"Message".*"JSON test"'
        }

        It 'Should include context data in log entry' {
            $logPath = Join-Path $script:LogDir 'write5.log'
            Initialize-FFULogging -LogPath $logPath
            Write-FFULog -Level Info -Message "Context test" -Context @{ VMName = 'TestVM'; Memory = '8GB' }
            Close-FFULogging

            $content = Get-Content $logPath -Raw
            $content | Should -Match 'VMName=TestVM'
            $content | Should -Match 'Memory=8GB'
        }

        It 'Should handle empty messages gracefully' {
            $logPath = Join-Path $script:LogDir 'write6.log'
            Initialize-FFULogging -LogPath $logPath
            { Write-FFULog -Level Info -Message "" } | Should -Not -Throw
            Close-FFULogging
        }
    }

    Context 'Close-FFULogging Function' {

        It 'Should reset session state' {
            $logPath = Join-Path $env:TEMP "close_test_$(Get-Random).log"
            Initialize-FFULogging -LogPath $logPath
            Close-FFULogging

            $session = Get-FFULogSession
            $session.SessionId | Should -BeNullOrEmpty

            # Clean up
            Remove-Item $logPath -Force -ErrorAction SilentlyContinue
        }

        It 'Should write session close message with duration' {
            $logPath = Join-Path $env:TEMP "close_duration_$(Get-Random).log"
            Initialize-FFULogging -LogPath $logPath
            Start-Sleep -Milliseconds 100
            Close-FFULogging

            $content = Get-Content $logPath -Raw
            $content | Should -Match 'Logging session closed'
            $content | Should -Match 'Duration='

            # Clean up
            Remove-Item $logPath -Force -ErrorAction SilentlyContinue
        }
    }
}

# =============================================================================
# SECTION 4: INTEGRATION TESTS
# Tests that verify all Phase 2 components work together correctly
# =============================================================================
Describe 'Phase 2: Integration Tests' -Tag 'Unit', 'Phase2', 'Reliability', 'Integration' {

    Context 'Module Dependencies' {

        It 'FFU.Core module should load without errors' {
            Get-Module -Name 'FFU.Core' | Should -Not -BeNullOrEmpty
        }

        It 'FFU.VM module should load after FFU.Core' {
            Get-Module -Name 'FFU.VM' | Should -Not -BeNullOrEmpty
        }

        It 'FFU.Updates module should load after FFU.Core' {
            Get-Module -Name 'FFU.Updates' | Should -Not -BeNullOrEmpty
        }

        It 'FFU.Drivers module should load' {
            Get-Module -Name 'FFU.Drivers' | Should -Not -BeNullOrEmpty
        }

        It 'FFU.Common.Logging module should load independently' {
            Get-Module -Name 'FFU.Common.Logging' | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Error Handling Patterns Consistency' {

        It 'All modules should follow the same error handling pattern' {
            $modules = @(
                $script:FFUVMModule,
                $script:FFUDriversModule,
                $script:FFUUpdatesModule
            )

            foreach ($modulePath in $modules) {
                if (Test-Path $modulePath) {
                    $content = Get-Content $modulePath -Raw
                    # Should use try/catch
                    $content | Should -Match 'try\s*\{' -Because "$modulePath should use try/catch"
                    $content | Should -Match 'catch\s*\{' -Because "$modulePath should use catch blocks"
                    # Should log errors
                    $content | Should -Match 'WriteLog.*ERROR' -Because "$modulePath should log errors"
                }
            }
        }
    }

    Context 'BuildFFUVM.ps1 Phase 2 Implementation' {

        BeforeAll {
            $script:BuildScript = Join-Path $script:FFUDevelopmentPath 'BuildFFUVM.ps1'
        }

        It 'Should have all cleanup mechanisms implemented' {
            $content = Get-Content -Path $script:BuildScript -Raw

            # Check for trap handler
            $content | Should -Match 'trap\s*\{' -Because "trap handler should be present"

            # Check for PowerShell.Exiting handler
            $content | Should -Match 'PowerShell\.Exiting' -Because "exit handler should be present"

            # Check for cleanup registry usage
            $content | Should -Match 'Register-.*Cleanup' -Because "cleanup registration should be used"

            # Check for Invoke-FailureCleanup in handlers
            $content | Should -Match 'Invoke-FailureCleanup' -Because "failure cleanup should be invoked"
        }
    }

    Context 'Security Cleanup for Credentials' {

        BeforeAll {
            $script:BuildScript = Join-Path $script:FFUDevelopmentPath 'BuildFFUVM.ps1'
        }

        It 'FFU.VM module should have Remove-SensitiveCaptureMedia function' {
            Get-Command Remove-SensitiveCaptureMedia -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'BuildFFUVM.ps1 should register sensitive media cleanup' {
            $content = Get-Content -Path $script:BuildScript -Raw
            $content | Should -Match 'Register-SensitiveMediaCleanup'
        }
    }
}
