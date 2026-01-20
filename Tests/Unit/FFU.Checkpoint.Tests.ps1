#Requires -Version 5.1
#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for FFU.Checkpoint module.

.DESCRIPTION
    Pester 5.x tests for checkpoint persistence functionality including
    save, load, remove, and validation operations.

.NOTES
    Module: FFU.Checkpoint
    Test Type: Unit
    Coverage Target: 100%
#>

BeforeAll {
    # Import module using 'using module' for enum access
    $modulePath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\Modules\FFU.Checkpoint\FFU.Checkpoint.psm1'

    # First import normally for functions
    Import-Module $modulePath -Force

    # Create test directory
    $script:TestBasePath = Join-Path $TestDrive 'FFUDevelopment'
    New-Item -Path $script:TestBasePath -ItemType Directory -Force | Out-Null
}

AfterAll {
    # Clean up test directory
    if (Test-Path $script:TestBasePath) {
        Remove-Item -Path $script:TestBasePath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'FFU.Checkpoint Module' {

    It 'imports without errors' {
        $modulePath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\Modules\FFU.Checkpoint\FFU.Checkpoint.psm1'
        { Import-Module $modulePath -Force } | Should -Not -Throw
    }

    It 'exports expected functions' {
        $commands = Get-Command -Module FFU.Checkpoint
        $commands.Name | Should -Contain 'Save-FFUBuildCheckpoint'
        $commands.Name | Should -Contain 'Get-FFUBuildCheckpoint'
        $commands.Name | Should -Contain 'Remove-FFUBuildCheckpoint'
        $commands.Name | Should -Contain 'Test-FFUBuildCheckpoint'
        $commands.Name | Should -Contain 'Get-FFUBuildPhasePercent'
    }

    It 'exports exactly 5 functions' {
        $commands = Get-Command -Module FFU.Checkpoint
        $commands.Count | Should -Be 5
    }

    It 'defines FFUBuildPhase enum with 16 phases' {
        # Use InModuleScope to access the enum
        InModuleScope FFU.Checkpoint {
            $phases = [enum]::GetNames([FFUBuildPhase])
            $phases.Count | Should -Be 16
        }
    }

    It 'defines FFUBuildPhase enum with correct phase names' {
        InModuleScope FFU.Checkpoint {
            $phases = [enum]::GetNames([FFUBuildPhase])
            $phases | Should -Contain 'NotStarted'
            $phases | Should -Contain 'PreflightValidation'
            $phases | Should -Contain 'VHDXCreation'
            $phases | Should -Contain 'FFUCapture'
            $phases | Should -Contain 'Completed'
        }
    }
}

Describe 'Save-FFUBuildCheckpoint' {

    BeforeEach {
        # Clean checkpoint before each test
        $checkpointDir = Join-Path $script:TestBasePath '.ffubuilder'
        if (Test-Path $checkpointDir) {
            Remove-Item -Path $checkpointDir -Recurse -Force
        }
    }

    It 'creates checkpoint directory if not exists' {
        InModuleScope FFU.Checkpoint -Parameters @{ TestBasePath = $script:TestBasePath } {
            Save-FFUBuildCheckpoint -CompletedPhase VHDXCreation `
                -Configuration @{ VMName = 'TestBuild' } `
                -Artifacts @{ vhdxCreated = $true } `
                -Paths @{ VHDXPath = 'C:\test.vhdx' } `
                -FFUDevelopmentPath $TestBasePath
        }

        $checkpointDir = Join-Path $script:TestBasePath '.ffubuilder'
        Test-Path $checkpointDir | Should -BeTrue
    }

    It 'creates checkpoint.json file' {
        InModuleScope FFU.Checkpoint -Parameters @{ TestBasePath = $script:TestBasePath } {
            Save-FFUBuildCheckpoint -CompletedPhase VHDXCreation `
                -Configuration @{ VMName = 'TestBuild' } `
                -Artifacts @{ vhdxCreated = $true } `
                -Paths @{ VHDXPath = 'C:\test.vhdx' } `
                -FFUDevelopmentPath $TestBasePath
        }

        $checkpointFile = Join-Path $script:TestBasePath '.ffubuilder\checkpoint.json'
        Test-Path $checkpointFile | Should -BeTrue
    }

    It 'writes valid JSON structure' {
        InModuleScope FFU.Checkpoint -Parameters @{ TestBasePath = $script:TestBasePath } {
            Save-FFUBuildCheckpoint -CompletedPhase VHDXCreation `
                -Configuration @{ VMName = 'TestBuild' } `
                -Artifacts @{ vhdxCreated = $true } `
                -Paths @{ VHDXPath = 'C:\test.vhdx' } `
                -FFUDevelopmentPath $TestBasePath
        }

        $checkpointFile = Join-Path $script:TestBasePath '.ffubuilder\checkpoint.json'
        { Get-Content $checkpointFile -Raw | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'includes all required fields' {
        InModuleScope FFU.Checkpoint -Parameters @{ TestBasePath = $script:TestBasePath } {
            Save-FFUBuildCheckpoint -CompletedPhase VHDXCreation `
                -Configuration @{ VMName = 'TestBuild' } `
                -Artifacts @{ vhdxCreated = $true } `
                -Paths @{ VHDXPath = 'C:\test.vhdx' } `
                -FFUDevelopmentPath $TestBasePath
        }

        $checkpointFile = Join-Path $script:TestBasePath '.ffubuilder\checkpoint.json'
        $checkpoint = Get-Content $checkpointFile -Raw | ConvertFrom-Json

        $checkpoint.version | Should -Not -BeNullOrEmpty
        $checkpoint.buildId | Should -Not -BeNullOrEmpty
        $checkpoint.timestamp | Should -Not -BeNullOrEmpty
        $checkpoint.lastCompletedPhase | Should -Not -BeNullOrEmpty
        $checkpoint.configuration | Should -Not -BeNull
        $checkpoint.artifacts | Should -Not -BeNull
        $checkpoint.paths | Should -Not -BeNull
    }

    It 'uses atomic write (temp file pattern)' {
        # After save, there should be no .tmp file
        InModuleScope FFU.Checkpoint -Parameters @{ TestBasePath = $script:TestBasePath } {
            Save-FFUBuildCheckpoint -CompletedPhase VHDXCreation `
                -Configuration @{ VMName = 'TestBuild' } `
                -Artifacts @{ vhdxCreated = $true } `
                -Paths @{ VHDXPath = 'C:\test.vhdx' } `
                -FFUDevelopmentPath $TestBasePath
        }

        $tempFile = Join-Path $script:TestBasePath '.ffubuilder\checkpoint.json.tmp'
        Test-Path $tempFile | Should -BeFalse
    }

    It 'calculates correct percent complete' {
        InModuleScope FFU.Checkpoint -Parameters @{ TestBasePath = $script:TestBasePath } {
            Save-FFUBuildCheckpoint -CompletedPhase VHDXCreation `
                -Configuration @{ VMName = 'TestBuild' } `
                -Artifacts @{ vhdxCreated = $true } `
                -Paths @{ VHDXPath = 'C:\test.vhdx' } `
                -FFUDevelopmentPath $TestBasePath
        }

        $checkpointFile = Join-Path $script:TestBasePath '.ffubuilder\checkpoint.json'
        $checkpoint = Get-Content $checkpointFile -Raw | ConvertFrom-Json
        $checkpoint.percentComplete | Should -Be 35
    }

    It 'stores UTC ISO 8601 timestamp' {
        InModuleScope FFU.Checkpoint -Parameters @{ TestBasePath = $script:TestBasePath } {
            Save-FFUBuildCheckpoint -CompletedPhase VHDXCreation `
                -Configuration @{ VMName = 'TestBuild' } `
                -Artifacts @{ vhdxCreated = $true } `
                -Paths @{ VHDXPath = 'C:\test.vhdx' } `
                -FFUDevelopmentPath $TestBasePath
        }

        $checkpointFile = Join-Path $script:TestBasePath '.ffubuilder\checkpoint.json'
        $checkpoint = Get-Content $checkpointFile -Raw | ConvertFrom-Json
        # ISO 8601 format ends with Z for UTC or has timezone offset
        $checkpoint.timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}'
    }

    It 'sets version to 1.0' {
        InModuleScope FFU.Checkpoint -Parameters @{ TestBasePath = $script:TestBasePath } {
            Save-FFUBuildCheckpoint -CompletedPhase VHDXCreation `
                -Configuration @{ VMName = 'TestBuild' } `
                -Artifacts @{ vhdxCreated = $true } `
                -Paths @{ VHDXPath = 'C:\test.vhdx' } `
                -FFUDevelopmentPath $TestBasePath
        }

        $checkpointFile = Join-Path $script:TestBasePath '.ffubuilder\checkpoint.json'
        $checkpoint = Get-Content $checkpointFile -Raw | ConvertFrom-Json
        $checkpoint.version | Should -Be '1.0'
    }

    It 'preserves configuration data' {
        $config = @{
            VMName = 'TestBuild'
            WindowsRelease = '24H2'
            WindowsSKU = 'Pro'
        }

        InModuleScope FFU.Checkpoint -Parameters @{ TestBasePath = $script:TestBasePath; Config = $config } {
            Save-FFUBuildCheckpoint -CompletedPhase VHDXCreation `
                -Configuration $Config `
                -Artifacts @{ vhdxCreated = $true } `
                -Paths @{ VHDXPath = 'C:\test.vhdx' } `
                -FFUDevelopmentPath $TestBasePath
        }

        $checkpointFile = Join-Path $script:TestBasePath '.ffubuilder\checkpoint.json'
        $checkpoint = Get-Content $checkpointFile -Raw | ConvertFrom-Json
        $checkpoint.configuration.VMName | Should -Be 'TestBuild'
        $checkpoint.configuration.WindowsRelease | Should -Be '24H2'
    }
}

Describe 'Get-FFUBuildCheckpoint' {

    BeforeEach {
        # Clean checkpoint before each test
        $checkpointDir = Join-Path $script:TestBasePath '.ffubuilder'
        if (Test-Path $checkpointDir) {
            Remove-Item -Path $checkpointDir -Recurse -Force
        }
    }

    It 'returns null when no checkpoint exists' {
        $checkpoint = Get-FFUBuildCheckpoint -FFUDevelopmentPath $script:TestBasePath
        $checkpoint | Should -BeNull
    }

    It 'loads valid checkpoint' {
        # Create a checkpoint first
        InModuleScope FFU.Checkpoint -Parameters @{ TestBasePath = $script:TestBasePath } {
            Save-FFUBuildCheckpoint -CompletedPhase VHDXCreation `
                -Configuration @{ VMName = 'TestBuild' } `
                -Artifacts @{ vhdxCreated = $true } `
                -Paths @{ VHDXPath = 'C:\test.vhdx' } `
                -FFUDevelopmentPath $TestBasePath
        }

        $checkpoint = Get-FFUBuildCheckpoint -FFUDevelopmentPath $script:TestBasePath
        $checkpoint | Should -Not -BeNull
        $checkpoint.lastCompletedPhase | Should -Be 'VHDXCreation'
    }

    It 'returns hashtable (not PSCustomObject)' {
        InModuleScope FFU.Checkpoint -Parameters @{ TestBasePath = $script:TestBasePath } {
            Save-FFUBuildCheckpoint -CompletedPhase VHDXCreation `
                -Configuration @{ VMName = 'TestBuild' } `
                -Artifacts @{ vhdxCreated = $true } `
                -Paths @{ VHDXPath = 'C:\test.vhdx' } `
                -FFUDevelopmentPath $TestBasePath
        }

        $checkpoint = Get-FFUBuildCheckpoint -FFUDevelopmentPath $script:TestBasePath
        $checkpoint | Should -BeOfType [hashtable]
    }

    It 'preserves nested structures' {
        InModuleScope FFU.Checkpoint -Parameters @{ TestBasePath = $script:TestBasePath } {
            Save-FFUBuildCheckpoint -CompletedPhase VHDXCreation `
                -Configuration @{ VMName = 'TestBuild'; Nested = @{ Key = 'Value' } } `
                -Artifacts @{ vhdxCreated = $true } `
                -Paths @{ VHDXPath = 'C:\test.vhdx' } `
                -FFUDevelopmentPath $TestBasePath
        }

        $checkpoint = Get-FFUBuildCheckpoint -FFUDevelopmentPath $script:TestBasePath
        $checkpoint.configuration | Should -BeOfType [hashtable]
        $checkpoint.configuration.Nested | Should -BeOfType [hashtable]
        $checkpoint.configuration.Nested.Key | Should -Be 'Value'
    }

    It 'returns null for invalid version' {
        # Create checkpoint with wrong version
        $checkpointDir = Join-Path $script:TestBasePath '.ffubuilder'
        New-Item -Path $checkpointDir -ItemType Directory -Force | Out-Null

        $badCheckpoint = @{
            version = '2.0'
            buildId = 'Test'
            timestamp = (Get-Date).ToString('o')
            lastCompletedPhase = 'VHDXCreation'
            configuration = @{}
            artifacts = @{}
            paths = @{}
        }
        $badCheckpoint | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $checkpointDir 'checkpoint.json')

        $checkpoint = Get-FFUBuildCheckpoint -FFUDevelopmentPath $script:TestBasePath
        $checkpoint | Should -BeNull
    }

    It 'returns null for invalid JSON' {
        # Create invalid JSON file
        $checkpointDir = Join-Path $script:TestBasePath '.ffubuilder'
        New-Item -Path $checkpointDir -ItemType Directory -Force | Out-Null
        'invalid json {{{' | Set-Content (Join-Path $checkpointDir 'checkpoint.json')

        $checkpoint = Get-FFUBuildCheckpoint -FFUDevelopmentPath $script:TestBasePath
        $checkpoint | Should -BeNull
    }
}

Describe 'Remove-FFUBuildCheckpoint' {

    BeforeEach {
        # Create checkpoint before each test
        $checkpointDir = Join-Path $script:TestBasePath '.ffubuilder'
        if (-not (Test-Path $checkpointDir)) {
            New-Item -Path $checkpointDir -ItemType Directory -Force | Out-Null
        }
    }

    It 'removes existing checkpoint' {
        # Create a checkpoint
        InModuleScope FFU.Checkpoint -Parameters @{ TestBasePath = $script:TestBasePath } {
            Save-FFUBuildCheckpoint -CompletedPhase VHDXCreation `
                -Configuration @{ VMName = 'TestBuild' } `
                -Artifacts @{ vhdxCreated = $true } `
                -Paths @{ VHDXPath = 'C:\test.vhdx' } `
                -FFUDevelopmentPath $TestBasePath
        }

        $checkpointFile = Join-Path $script:TestBasePath '.ffubuilder\checkpoint.json'
        Test-Path $checkpointFile | Should -BeTrue

        Remove-FFUBuildCheckpoint -FFUDevelopmentPath $script:TestBasePath
        Test-Path $checkpointFile | Should -BeFalse
    }

    It 'does not error when no checkpoint exists' {
        # Ensure no checkpoint exists
        $checkpointFile = Join-Path $script:TestBasePath '.ffubuilder\checkpoint.json'
        if (Test-Path $checkpointFile) {
            Remove-Item $checkpointFile -Force
        }

        { Remove-FFUBuildCheckpoint -FFUDevelopmentPath $script:TestBasePath } | Should -Not -Throw
    }

    It 'leaves directory intact (only removes file)' {
        # Create a checkpoint
        InModuleScope FFU.Checkpoint -Parameters @{ TestBasePath = $script:TestBasePath } {
            Save-FFUBuildCheckpoint -CompletedPhase VHDXCreation `
                -Configuration @{ VMName = 'TestBuild' } `
                -Artifacts @{ vhdxCreated = $true } `
                -Paths @{ VHDXPath = 'C:\test.vhdx' } `
                -FFUDevelopmentPath $TestBasePath
        }

        Remove-FFUBuildCheckpoint -FFUDevelopmentPath $script:TestBasePath

        $checkpointDir = Join-Path $script:TestBasePath '.ffubuilder'
        Test-Path $checkpointDir | Should -BeTrue
    }
}

Describe 'Test-FFUBuildCheckpoint' {

    BeforeEach {
        # Clean checkpoint before each test
        $checkpointDir = Join-Path $script:TestBasePath '.ffubuilder'
        if (Test-Path $checkpointDir) {
            Remove-Item -Path $checkpointDir -Recurse -Force
        }
    }

    It 'returns true for valid checkpoint' {
        InModuleScope FFU.Checkpoint -Parameters @{ TestBasePath = $script:TestBasePath } {
            Save-FFUBuildCheckpoint -CompletedPhase VHDXCreation `
                -Configuration @{ VMName = 'TestBuild' } `
                -Artifacts @{ vhdxCreated = $false } `
                -Paths @{ VHDXPath = 'C:\test.vhdx' } `
                -FFUDevelopmentPath $TestBasePath
        }

        $result = Test-FFUBuildCheckpoint -FFUDevelopmentPath $script:TestBasePath
        $result | Should -BeTrue
    }

    It 'returns false for missing version' {
        $checkpointDir = Join-Path $script:TestBasePath '.ffubuilder'
        New-Item -Path $checkpointDir -ItemType Directory -Force | Out-Null

        $badCheckpoint = @{
            # Missing version field
            buildId = 'Test'
            timestamp = (Get-Date).ToString('o')
            lastCompletedPhase = 'VHDXCreation'
            configuration = @{}
            artifacts = @{}
            paths = @{}
        }
        $badCheckpoint | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $checkpointDir 'checkpoint.json')

        # Get-FFUBuildCheckpoint will return null for missing version
        $result = Test-FFUBuildCheckpoint -FFUDevelopmentPath $script:TestBasePath
        $result | Should -BeFalse
    }

    It 'returns false for wrong version' {
        $checkpointDir = Join-Path $script:TestBasePath '.ffubuilder'
        New-Item -Path $checkpointDir -ItemType Directory -Force | Out-Null

        $badCheckpoint = @{
            version = '2.0'
            buildId = 'Test'
            timestamp = (Get-Date).ToString('o')
            lastCompletedPhase = 'VHDXCreation'
            configuration = @{}
            artifacts = @{}
            paths = @{}
        }
        $badCheckpoint | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $checkpointDir 'checkpoint.json')

        $result = Test-FFUBuildCheckpoint -FFUDevelopmentPath $script:TestBasePath
        $result | Should -BeFalse
    }

    It 'returns false for missing required fields' {
        $checkpointDir = Join-Path $script:TestBasePath '.ffubuilder'
        New-Item -Path $checkpointDir -ItemType Directory -Force | Out-Null

        $badCheckpoint = @{
            version = '1.0'
            # Missing buildId, timestamp, lastCompletedPhase, etc.
        }
        $badCheckpoint | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $checkpointDir 'checkpoint.json')

        $result = Test-FFUBuildCheckpoint -FFUDevelopmentPath $script:TestBasePath
        $result | Should -BeFalse
    }

    It 'validates artifact paths when artifacts have true values' {
        # Create checkpoint with artifact marked true but path doesn't exist
        $checkpointDir = Join-Path $script:TestBasePath '.ffubuilder'
        New-Item -Path $checkpointDir -ItemType Directory -Force | Out-Null

        $checkpoint = @{
            version = '1.0'
            buildId = 'Test'
            timestamp = (Get-Date).ToString('o')
            lastCompletedPhase = 'VHDXCreation'
            percentComplete = 35
            configuration = @{ VMName = 'Test' }
            artifacts = @{ vhdxCreated = $true }  # Marked as created
            paths = @{ VHDXPath = 'C:\nonexistent\test.vhdx' }  # Doesn't exist
        }
        $checkpoint | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $checkpointDir 'checkpoint.json')

        $result = Test-FFUBuildCheckpoint -FFUDevelopmentPath $script:TestBasePath
        $result | Should -BeFalse
    }

    It 'returns true when artifact paths exist for true artifacts' {
        # Create a real file for the artifact path
        $testFile = Join-Path $script:TestBasePath 'test.vhdx'
        '' | Set-Content $testFile

        $checkpointDir = Join-Path $script:TestBasePath '.ffubuilder'
        New-Item -Path $checkpointDir -ItemType Directory -Force | Out-Null

        $checkpoint = @{
            version = '1.0'
            buildId = 'Test'
            timestamp = (Get-Date).ToString('o')
            lastCompletedPhase = 'VHDXCreation'
            percentComplete = 35
            configuration = @{ VMName = 'Test' }
            artifacts = @{ vhdxCreated = $true }
            paths = @{ VHDXPath = $testFile }
        }
        $checkpoint | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $checkpointDir 'checkpoint.json')

        $result = Test-FFUBuildCheckpoint -FFUDevelopmentPath $script:TestBasePath
        $result | Should -BeTrue
    }

    It 'accepts pre-loaded checkpoint parameter' {
        $checkpoint = @{
            version = '1.0'
            buildId = 'Test'
            timestamp = (Get-Date).ToString('o')
            lastCompletedPhase = 'VHDXCreation'
            percentComplete = 35
            configuration = @{ VMName = 'Test' }
            artifacts = @{}
            paths = @{}
        }

        $result = Test-FFUBuildCheckpoint -Checkpoint $checkpoint
        $result | Should -BeTrue
    }

    It 'returns false when no path provided and no checkpoint parameter' {
        $result = Test-FFUBuildCheckpoint
        $result | Should -BeFalse
    }
}

Describe 'Get-FFUBuildPhasePercent' {

    It 'returns 0 for NotStarted' {
        InModuleScope FFU.Checkpoint {
            $result = Get-FFUBuildPhasePercent -Phase NotStarted
            $result | Should -Be 0
        }
    }

    It 'returns 5 for PreflightValidation' {
        InModuleScope FFU.Checkpoint {
            $result = Get-FFUBuildPhasePercent -Phase PreflightValidation
            $result | Should -Be 5
        }
    }

    It 'returns 35 for VHDXCreation' {
        InModuleScope FFU.Checkpoint {
            $result = Get-FFUBuildPhasePercent -Phase VHDXCreation
            $result | Should -Be 35
        }
    }

    It 'returns 90 for FFUCapture' {
        InModuleScope FFU.Checkpoint {
            $result = Get-FFUBuildPhasePercent -Phase FFUCapture
            $result | Should -Be 90
        }
    }

    It 'returns 100 for Completed' {
        InModuleScope FFU.Checkpoint {
            $result = Get-FFUBuildPhasePercent -Phase Completed
            $result | Should -Be 100
        }
    }

    It 'returns correct percent for each phase' {
        InModuleScope FFU.Checkpoint {
            $expectedPercents = @{
                NotStarted = 0
                PreflightValidation = 5
                DriverDownload = 15
                UpdatesDownload = 25
                AppsPreparation = 30
                VHDXCreation = 35
                WindowsUpdates = 50
                VMSetup = 55
                VMStart = 60
                AppInstallation = 75
                VMShutdown = 80
                FFUCapture = 90
                DeploymentMedia = 95
                USBCreation = 98
                Cleanup = 99
                Completed = 100
            }

            foreach ($phaseName in $expectedPercents.Keys) {
                $phase = [FFUBuildPhase]$phaseName
                $result = Get-FFUBuildPhasePercent -Phase $phase
                $result | Should -Be $expectedPercents[$phaseName] -Because "Phase $phaseName should return $($expectedPercents[$phaseName])%"
            }
        }
    }
}

Describe 'Cross-version Compatibility' {

    It 'ConvertTo-HashtableRecursive handles null' {
        InModuleScope FFU.Checkpoint {
            $result = ConvertTo-HashtableRecursive -InputObject $null
            $result | Should -BeNull
        }
    }

    It 'ConvertTo-HashtableRecursive handles primitives' {
        InModuleScope FFU.Checkpoint {
            $result = ConvertTo-HashtableRecursive -InputObject 'test'
            $result | Should -Be 'test'

            $result = ConvertTo-HashtableRecursive -InputObject 42
            $result | Should -Be 42

            $result = ConvertTo-HashtableRecursive -InputObject $true
            $result | Should -BeTrue
        }
    }

    It 'ConvertTo-HashtableRecursive converts PSCustomObject' {
        InModuleScope FFU.Checkpoint {
            $obj = [PSCustomObject]@{ Name = 'Test'; Value = 123 }
            $result = ConvertTo-HashtableRecursive -InputObject $obj
            $result | Should -BeOfType [hashtable]
            $result.Name | Should -Be 'Test'
            $result.Value | Should -Be 123
        }
    }

    It 'ConvertTo-HashtableRecursive handles nested objects' {
        InModuleScope FFU.Checkpoint {
            $obj = [PSCustomObject]@{
                Level1 = [PSCustomObject]@{
                    Level2 = 'DeepValue'
                }
            }
            $result = ConvertTo-HashtableRecursive -InputObject $obj
            $result | Should -BeOfType [hashtable]
            $result.Level1 | Should -BeOfType [hashtable]
            $result.Level1.Level2 | Should -Be 'DeepValue'
        }
    }

    It 'ConvertTo-HashtableRecursive handles arrays' {
        InModuleScope FFU.Checkpoint {
            $obj = @(
                [PSCustomObject]@{ Name = 'Item1' }
                [PSCustomObject]@{ Name = 'Item2' }
            )
            $result = ConvertTo-HashtableRecursive -InputObject $obj
            $result.Count | Should -Be 2
            $result[0].Name | Should -Be 'Item1'
            $result[1].Name | Should -Be 'Item2'
        }
    }
}
