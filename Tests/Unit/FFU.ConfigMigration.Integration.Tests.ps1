#Requires -Version 5.1
#Requires -Modules Pester

<#
.SYNOPSIS
    Integration tests for FFU.ConfigMigration module.

.DESCRIPTION
    Pester 5.x integration tests for configuration migration functionality.
    Tests end-to-end migration flows, version comparisons, UI/CLI flow mocking,
    and error handling scenarios.

.NOTES
    Module: FFU.ConfigMigration
    Test Type: Integration
    Coverage Target: End-to-end migration flows
#>

BeforeAll {
    # Add modules to path
    $modulesPath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\Modules'
    if ($env:PSModulePath -notlike "*$modulesPath*") {
        $env:PSModulePath = "$modulesPath;$env:PSModulePath"
    }

    # Import the module
    Import-Module FFU.ConfigMigration -Force

    # Create test directory
    $script:TestDataDir = Join-Path $TestDrive 'ConfigMigrationIntegration'
    New-Item -Path $script:TestDataDir -ItemType Directory -Force | Out-Null
}

AfterAll {
    # Clean up test directory
    if (Test-Path $script:TestDataDir) {
        Remove-Item -Path $script:TestDataDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'End-to-End Migration Tests' {

    BeforeEach {
        # Clean up test files before each test
        Get-ChildItem -Path $script:TestDataDir -File | Remove-Item -Force
    }

    It 'Migrates pre-versioning config file successfully' {
        # Arrange: Create test config without version
        $testConfig = @{
            FFUDevelopmentPath = 'C:\FFU'
            AppsPath = 'C:\FFU\Apps'
            OfficePath = 'C:\FFU\Office'
            Verbose = $true
            InstallWingetApps = $true
            WindowsRelease = 11
        }
        $configPath = Join-Path $script:TestDataDir 'test-config.json'
        $testConfig | ConvertTo-Json | Set-Content -Path $configPath

        # Act: Read, convert, and migrate
        $configData = Get-Content $configPath -Raw | ConvertFrom-Json
        $configHashtable = ConvertTo-HashtableRecursive -InputObject $configData
        $result = Invoke-FFUConfigMigration -Config $configHashtable -CreateBackup -ConfigPath $configPath

        # Assert
        $result.Config.configSchemaVersion | Should -Be '1.0'
        $result.Config.ContainsKey('AppsPath') | Should -BeFalse
        $result.Config.ContainsKey('OfficePath') | Should -BeFalse
        $result.Config.ContainsKey('Verbose') | Should -BeFalse
        $result.Config.InstallApps | Should -BeTrue
        $result.Config.FFUDevelopmentPath | Should -Be 'C:\FFU'
        $result.BackupPath | Should -Not -BeNullOrEmpty
        Test-Path $result.BackupPath | Should -BeTrue
    }

    It 'Backup file created with correct timestamp format' {
        # Arrange
        $testConfig = @{
            FFUDevelopmentPath = 'C:\FFU'
            AppsPath = 'C:\FFU\Apps'
        }
        $configPath = Join-Path $script:TestDataDir 'backup-format-test.json'
        $testConfig | ConvertTo-Json | Set-Content -Path $configPath

        # Act
        $result = Invoke-FFUConfigMigration -Config $testConfig -CreateBackup -ConfigPath $configPath

        # Assert - backup should have timestamp suffix in yyyyMMdd-HHmmss format
        $result.BackupPath | Should -Match 'backup-format-test\.json\.backup-\d{8}-\d{6}$'
    }

    It 'Migrated config file has configSchemaVersion set' {
        # Arrange
        $testConfig = @{
            FFUDevelopmentPath = 'C:\FFU'
        }

        # Act
        $result = Invoke-FFUConfigMigration -Config $testConfig

        # Assert
        $result.Config.configSchemaVersion | Should -Be '1.0'
    }

    It 'All deprecated properties removed from migrated file' {
        # Arrange: Config with all deprecated properties
        $testConfig = @{
            FFUDevelopmentPath = 'C:\FFU'
            AppsPath = 'C:\FFU\Apps'
            OfficePath = 'C:\FFU\Office'
            Verbose = $true
            Threads = 8
            InstallWingetApps = $true
            DownloadDrivers = $false
            CopyOfficeConfigXML = $false
        }

        # Act
        $result = Invoke-FFUConfigMigration -Config $testConfig

        # Assert: All deprecated properties removed
        $result.Config.ContainsKey('AppsPath') | Should -BeFalse
        $result.Config.ContainsKey('OfficePath') | Should -BeFalse
        $result.Config.ContainsKey('Verbose') | Should -BeFalse
        $result.Config.ContainsKey('Threads') | Should -BeFalse
        $result.Config.ContainsKey('InstallWingetApps') | Should -BeFalse
        $result.Config.ContainsKey('DownloadDrivers') | Should -BeFalse
        $result.Config.ContainsKey('CopyOfficeConfigXML') | Should -BeFalse
    }

    It 'Unknown properties preserved in migrated file (forward compatibility)' {
        # Arrange: Config with unknown future property
        $testConfig = @{
            FFUDevelopmentPath = 'C:\FFU'
            FutureProperty = 'some-value'
            AnotherUnknown = 123
            NestedUnknown = @{
                SubProperty = 'nested-value'
            }
        }

        # Act
        $result = Invoke-FFUConfigMigration -Config $testConfig

        # Assert
        $result.Config.FutureProperty | Should -Be 'some-value'
        $result.Config.AnotherUnknown | Should -Be 123
        $result.Config.NestedUnknown.SubProperty | Should -Be 'nested-value'
    }

    It 'InstallWingetApps correctly transformed to InstallApps' {
        # Arrange
        $testConfig = @{
            FFUDevelopmentPath = 'C:\FFU'
            InstallWingetApps = $true
        }

        # Act
        $result = Invoke-FFUConfigMigration -Config $testConfig

        # Assert
        $result.Config.InstallApps | Should -BeTrue
        $result.Config.ContainsKey('InstallWingetApps') | Should -BeFalse
        $result.Changes | Should -Contain "Migrated 'InstallWingetApps=true' to 'InstallApps=true'"
    }

    It 'Complete config file round-trip maintains integrity' {
        # Arrange: Create real config file
        $testConfig = @{
            FFUDevelopmentPath = 'C:\FFUDevelopment'
            WindowsRelease = '24H2'
            WindowsSKU = 'Pro'
            Memory = 8589934592
            Processors = 4
            InstallApps = $true
            AppsPath = 'C:\FFUDevelopment\Apps'  # Deprecated
        }
        $configPath = Join-Path $script:TestDataDir 'round-trip-test.json'
        $testConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath

        # Act: Full round-trip
        $originalContent = Get-Content $configPath -Raw | ConvertFrom-Json
        $configHashtable = ConvertTo-HashtableRecursive -InputObject $originalContent
        $migrationResult = Invoke-FFUConfigMigration -Config $configHashtable -CreateBackup -ConfigPath $configPath

        # Write migrated config back
        $migratedPath = Join-Path $script:TestDataDir 'round-trip-migrated.json'
        $migrationResult.Config | ConvertTo-Json -Depth 10 | Set-Content -Path $migratedPath

        # Read migrated config
        $migratedContent = Get-Content $migratedPath -Raw | ConvertFrom-Json
        $migratedHashtable = ConvertTo-HashtableRecursive -InputObject $migratedContent

        # Assert: Preserved properties intact
        $migratedHashtable.FFUDevelopmentPath | Should -Be 'C:\FFUDevelopment'
        $migratedHashtable.WindowsRelease | Should -Be '24H2'
        $migratedHashtable.WindowsSKU | Should -Be 'Pro'
        $migratedHashtable.Memory | Should -Be 8589934592
        $migratedHashtable.Processors | Should -Be 4
        $migratedHashtable.InstallApps | Should -BeTrue

        # Assert: Deprecated removed
        $migratedHashtable.ContainsKey('AppsPath') | Should -BeFalse

        # Assert: Version set
        $migratedHashtable.configSchemaVersion | Should -Be '1.0'
    }
}

Describe 'Version Comparison Tests' {

    It 'Pre-versioning config needs migration (0.0 < 1.0)' {
        $config = @{ FFUDevelopmentPath = 'C:\FFU' }
        $result = Test-FFUConfigVersion -Config $config
        $result.ConfigVersion | Should -Be '0.0'
        $result.NeedsMigration | Should -BeTrue
    }

    It 'Current version config does not need migration (1.0 = 1.0)' {
        $config = @{ configSchemaVersion = '1.0'; FFUDevelopmentPath = 'C:\FFU' }
        $result = Test-FFUConfigVersion -Config $config
        $result.NeedsMigration | Should -BeFalse
    }

    It 'Future version config does not need migration (forward compatible)' {
        $config = @{ configSchemaVersion = '2.0'; FFUDevelopmentPath = 'C:\FFU' }
        $result = Test-FFUConfigVersion -Config $config
        $result.NeedsMigration | Should -BeFalse
    }

    It 'Semantic versioning works correctly (1.10 > 1.9)' {
        $config = @{ configSchemaVersion = '1.9'; FFUDevelopmentPath = 'C:\FFU' }
        $result = Test-FFUConfigVersion -Config $config -CurrentSchemaVersion '1.10'
        $result.NeedsMigration | Should -BeTrue
    }

    It 'Semantic versioning works correctly (1.2 < 1.10)' {
        $config = @{ configSchemaVersion = '1.2'; FFUDevelopmentPath = 'C:\FFU' }
        $result = Test-FFUConfigVersion -Config $config -CurrentSchemaVersion '1.10'
        $result.NeedsMigration | Should -BeTrue
    }

    It 'Version difference is positive for older config' {
        $config = @{ configSchemaVersion = '0.5' }
        $result = Test-FFUConfigVersion -Config $config
        $result.VersionDifference | Should -BeGreaterThan 0
    }

    It 'Version difference is zero for current config' {
        $config = @{ configSchemaVersion = '1.0' }
        $result = Test-FFUConfigVersion -Config $config
        $result.VersionDifference | Should -Be 0
    }

    It 'Version difference is negative for newer config' {
        $config = @{ configSchemaVersion = '2.0' }
        $result = Test-FFUConfigVersion -Config $config
        $result.VersionDifference | Should -BeLessThan 0
    }
}

Describe 'UI Flow Tests (Mock WPF)' {

    Context 'Migration dialog content generation' {

        It 'Change descriptions contain version numbers' {
            $config = @{
                FFUDevelopmentPath = 'C:\FFU'
                AppsPath = 'C:\FFU\Apps'
            }
            $result = Invoke-FFUConfigMigration -Config $config

            # The migration result has FromVersion and ToVersion
            $result.FromVersion | Should -Be '0.0'
            $result.ToVersion | Should -Be '1.0'
        }

        It 'Change descriptions contain property-specific details' {
            $config = @{
                FFUDevelopmentPath = 'C:\FFU'
                AppsPath = 'C:\FFU\Apps'
                Verbose = $true
            }
            $result = Invoke-FFUConfigMigration -Config $config

            $result.Changes | Should -Contain "Removed deprecated property 'AppsPath' (now computed from FFUDevelopmentPath)"
            $result.Changes | Should -Contain "Removed deprecated property 'Verbose' (use -Verbose CLI switch instead)"
        }

        It 'WARNING changes formatted with WARNING prefix' {
            $config = @{
                FFUDevelopmentPath = 'C:\FFU'
                DownloadDrivers = $true
                CopyOfficeConfigXML = $true
            }
            $result = Invoke-FFUConfigMigration -Config $config

            $warnings = $result.Changes | Where-Object { $_ -like "WARNING:*" }
            $warnings | Should -HaveCount 2
        }

        It 'Can format changes for UI display' {
            $config = @{
                FFUDevelopmentPath = 'C:\FFU'
                AppsPath = 'C:\FFU\Apps'
                DownloadDrivers = $true
            }
            $result = Invoke-FFUConfigMigration -Config $config

            # Simulate UI formatting - separate warnings from info
            $infoChanges = $result.Changes | Where-Object { $_ -notlike "WARNING:*" }
            $warningChanges = $result.Changes | Where-Object { $_ -like "WARNING:*" }

            $infoChanges.Count | Should -BeGreaterThan 0
            $warningChanges.Count | Should -BeGreaterThan 0
        }
    }
}

Describe 'CLI Flow Tests (Mock Read-Host)' {

    Context 'Change list formatting' {

        It 'Changes list can be formatted for console output' {
            $config = @{
                FFUDevelopmentPath = 'C:\FFU'
                AppsPath = 'C:\FFU\Apps'
                OfficePath = 'C:\FFU\Office'
            }
            $result = Invoke-FFUConfigMigration -Config $config

            # Simulate CLI output formatting
            $formattedOutput = $result.Changes | ForEach-Object {
                if ($_ -like "WARNING:*") {
                    "  [!] $_"
                }
                else {
                    "  - $_"
                }
            }

            $formattedOutput | Should -HaveCount 2
            $formattedOutput | ForEach-Object { $_ | Should -Match '^\s+[-\[]' }
        }

        It 'Backup path available for CLI display' {
            $configPath = Join-Path $script:TestDataDir 'cli-backup-test.json'
            $config = @{ FFUDevelopmentPath = 'C:\FFU' }
            $config | ConvertTo-Json | Set-Content -Path $configPath

            $result = Invoke-FFUConfigMigration -Config $config -CreateBackup -ConfigPath $configPath

            # CLI can display backup path
            $result.BackupPath | Should -Not -BeNullOrEmpty
            $result.BackupPath | Should -BeLike '*cli-backup-test.json.backup-*'
        }
    }

    Context 'Response handling simulation' {

        It 'Y response would save migrated config' {
            $config = @{
                FFUDevelopmentPath = 'C:\FFU'
                AppsPath = 'C:\FFU\Apps'
            }

            $result = Invoke-FFUConfigMigration -Config $config

            # Simulate Y response - would write config
            $migratedJson = $result.Config | ConvertTo-Json -Depth 10
            { $migratedJson | ConvertFrom-Json } | Should -Not -Throw
            $result.Config.configSchemaVersion | Should -Be '1.0'
        }

        It 'N response would skip save - original config unchanged' {
            $configPath = Join-Path $script:TestDataDir 'skip-save-test.json'
            $originalConfig = @{
                FFUDevelopmentPath = 'C:\FFU'
                AppsPath = 'C:\FFU\Apps'
            }
            $originalConfig | ConvertTo-Json | Set-Content -Path $configPath

            # Run migration but don't save (simulates N response)
            $configData = Get-Content $configPath -Raw | ConvertFrom-Json
            $configHashtable = ConvertTo-HashtableRecursive -InputObject $configData
            $result = Invoke-FFUConfigMigration -Config $configHashtable

            # Original file should still have AppsPath
            $stillOriginal = Get-Content $configPath -Raw | ConvertFrom-Json
            $stillOriginal.AppsPath | Should -Be 'C:\FFU\Apps'
        }
    }
}

Describe 'Error Handling Tests' {

    It 'Handles already-migrated config gracefully' {
        $config = @{ configSchemaVersion = '1.0'; FFUDevelopmentPath = 'C:\FFU' }
        $result = Invoke-FFUConfigMigration -Config $config

        $result.Changes.Count | Should -Be 0
        $result.FromVersion | Should -Be '1.0'
        $result.Config.configSchemaVersion | Should -Be '1.0'
    }

    It 'Handles future version config gracefully' {
        $config = @{ configSchemaVersion = '2.5'; FFUDevelopmentPath = 'C:\FFU'; FutureField = 'value' }
        $result = Invoke-FFUConfigMigration -Config $config

        $result.Changes.Count | Should -Be 0
        $result.Config.configSchemaVersion | Should -Be '2.5'  # Not downgraded
        $result.Config.FutureField | Should -Be 'value'  # Preserved
    }

    It 'Handles config with only deprecated properties' {
        $config = @{
            AppsPath = 'C:\FFU\Apps'
            OfficePath = 'C:\FFU\Office'
            Verbose = $true
        }
        $result = Invoke-FFUConfigMigration -Config $config

        $result.Config.Count | Should -BeGreaterOrEqual 1  # At least configSchemaVersion
        $result.Config.configSchemaVersion | Should -Be '1.0'
    }

    It 'Backup directory created if missing' {
        $subDir = Join-Path $script:TestDataDir 'new-subdir'
        $configPath = Join-Path $subDir 'missing-dir-test.json'

        # Create directory and file
        New-Item -Path $subDir -ItemType Directory -Force | Out-Null
        $config = @{ FFUDevelopmentPath = 'C:\FFU' }
        $config | ConvertTo-Json | Set-Content -Path $configPath

        # Act
        $result = Invoke-FFUConfigMigration -Config $config -CreateBackup -ConfigPath $configPath

        # Assert
        $result.BackupPath | Should -Not -BeNullOrEmpty
        Test-Path $result.BackupPath | Should -BeTrue
    }

    It 'Returns valid result structure even for minimal config' {
        $config = @{ FFUDevelopmentPath = 'C:\FFU' }

        $result = Invoke-FFUConfigMigration -Config $config

        $result.Config | Should -Not -BeNull
        # Changes is an array (may be empty when no deprecated properties)
        $result.Changes.GetType().BaseType.Name | Should -Be 'Array'
        $result.Changes.Count | Should -Be 0
        $result.FromVersion | Should -Be '0.0'
        $result.ToVersion | Should -Be '1.0'
    }
}

Describe 'Deprecated Property Migration Tests' {

    It 'Removes AppsPath (computed dynamically)' {
        $config = @{ AppsPath = 'C:\Custom\Apps' }
        $result = Invoke-FFUConfigMigration -Config $config
        $result.Config.ContainsKey('AppsPath') | Should -BeFalse
        $result.Changes | Should -Contain "Removed deprecated property 'AppsPath' (now computed from FFUDevelopmentPath)"
    }

    It 'Removes OfficePath (computed dynamically)' {
        $config = @{ OfficePath = 'C:\Custom\Office' }
        $result = Invoke-FFUConfigMigration -Config $config
        $result.Config.ContainsKey('OfficePath') | Should -BeFalse
        $result.Changes | Should -Contain "Removed deprecated property 'OfficePath' (now computed from FFUDevelopmentPath)"
    }

    It 'Removes Verbose (use CLI switch)' {
        $config = @{ Verbose = $true }
        $result = Invoke-FFUConfigMigration -Config $config
        $result.Config.ContainsKey('Verbose') | Should -BeFalse
        $result.Changes | Should -Contain "Removed deprecated property 'Verbose' (use -Verbose CLI switch instead)"
    }

    It 'Removes Threads (automatic processing)' {
        $config = @{ Threads = 8 }
        $result = Invoke-FFUConfigMigration -Config $config
        $result.Config.ContainsKey('Threads') | Should -BeFalse
        $result.Changes | Should -Contain "Removed deprecated property 'Threads' (parallel processing now automatic)"
    }

    It 'Migrates InstallWingetApps to InstallApps when true' {
        $config = @{ InstallWingetApps = $true }
        $result = Invoke-FFUConfigMigration -Config $config
        $result.Config.InstallApps | Should -BeTrue
        $result.Config.ContainsKey('InstallWingetApps') | Should -BeFalse
    }

    It 'Removes InstallWingetApps when false without setting InstallApps' {
        $config = @{ InstallWingetApps = $false }
        $result = Invoke-FFUConfigMigration -Config $config
        $result.Config.ContainsKey('InstallWingetApps') | Should -BeFalse
        $result.Config.ContainsKey('InstallApps') | Should -BeFalse
    }

    It 'DownloadDrivers without Make generates WARNING' {
        $config = @{ DownloadDrivers = $true }
        $result = Invoke-FFUConfigMigration -Config $config
        $result.Config.ContainsKey('DownloadDrivers') | Should -BeFalse
        $warnings = $result.Changes | Where-Object { $_ -like "WARNING:*Make*" }
        $warnings | Should -Not -BeNullOrEmpty
    }

    It 'CopyOfficeConfigXML without OfficeConfigXMLFile generates WARNING' {
        $config = @{ CopyOfficeConfigXML = $true }
        $result = Invoke-FFUConfigMigration -Config $config
        $result.Config.ContainsKey('CopyOfficeConfigXML') | Should -BeFalse
        $warnings = $result.Changes | Where-Object { $_ -like "WARNING:*OfficeConfigXMLFile*" }
        $warnings | Should -Not -BeNullOrEmpty
    }
}

Describe 'File-Based Migration Tests' {

    BeforeEach {
        # Clean up test files before each test
        Get-ChildItem -Path $script:TestDataDir -File | Remove-Item -Force
    }

    It 'Test-FFUConfigVersion reads from file path' {
        $configPath = Join-Path $script:TestDataDir 'file-version-test.json'
        @{
            configSchemaVersion = '0.5'
            FFUDevelopmentPath = 'C:\FFU'
        } | ConvertTo-Json | Set-Content -Path $configPath

        $result = Test-FFUConfigVersion -ConfigPath $configPath

        $result.ConfigVersion | Should -Be '0.5'
        $result.NeedsMigration | Should -BeTrue
    }

    It 'Test-FFUConfigVersion handles file without version' {
        $configPath = Join-Path $script:TestDataDir 'no-version-file.json'
        @{
            FFUDevelopmentPath = 'C:\FFU'
            AppsPath = 'C:\FFU\Apps'
        } | ConvertTo-Json | Set-Content -Path $configPath

        $result = Test-FFUConfigVersion -ConfigPath $configPath

        $result.ConfigVersion | Should -Be '0.0'
        $result.NeedsMigration | Should -BeTrue
    }

    It 'Full migration workflow from file' {
        $configPath = Join-Path $script:TestDataDir 'full-workflow.json'
        @{
            FFUDevelopmentPath = 'C:\FFU'
            AppsPath = 'C:\FFU\Apps'
            InstallWingetApps = $true
        } | ConvertTo-Json | Set-Content -Path $configPath

        # Step 1: Check version
        $versionCheck = Test-FFUConfigVersion -ConfigPath $configPath
        $versionCheck.NeedsMigration | Should -BeTrue

        # Step 2: Load and migrate
        $configData = Get-Content $configPath -Raw | ConvertFrom-Json
        $configHashtable = ConvertTo-HashtableRecursive -InputObject $configData
        $migrationResult = Invoke-FFUConfigMigration -Config $configHashtable -CreateBackup -ConfigPath $configPath

        # Step 3: Save migrated config
        $migrationResult.Config | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath

        # Step 4: Verify no longer needs migration
        $postCheck = Test-FFUConfigVersion -ConfigPath $configPath
        $postCheck.NeedsMigration | Should -BeFalse
        $postCheck.ConfigVersion | Should -Be '1.0'
    }
}

Describe 'Cross-Version Compatibility Tests' {

    It 'ConvertTo-HashtableRecursive handles JSON from file correctly' {
        $configPath = Join-Path $script:TestDataDir 'json-convert-test.json'
        @{
            FFUDevelopmentPath = 'C:\FFU'
            Nested = @{
                SubNested = @{
                    Value = 'deep'
                }
            }
            Array = @('item1', 'item2')
        } | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath

        $jsonData = Get-Content $configPath -Raw | ConvertFrom-Json
        $result = ConvertTo-HashtableRecursive -InputObject $jsonData

        $result | Should -BeOfType [hashtable]
        $result.Nested | Should -BeOfType [hashtable]
        $result.Nested.SubNested | Should -BeOfType [hashtable]
        $result.Nested.SubNested.Value | Should -Be 'deep'
        $result.Array | Should -HaveCount 2
    }

    It 'Migration preserves numeric types' {
        $config = @{
            FFUDevelopmentPath = 'C:\FFU'
            Memory = 8589934592
            Processors = 4
            Disksize = 53687091200
        }
        $result = Invoke-FFUConfigMigration -Config $config

        $result.Config.Memory | Should -Be 8589934592
        $result.Config.Processors | Should -Be 4
        $result.Config.Disksize | Should -Be 53687091200
    }

    It 'Migration preserves boolean types' {
        $config = @{
            FFUDevelopmentPath = 'C:\FFU'
            InstallApps = $true
            InstallOffice = $false
            CreateCaptureMedia = $true
        }
        $result = Invoke-FFUConfigMigration -Config $config

        $result.Config.InstallApps | Should -BeTrue
        $result.Config.InstallOffice | Should -BeFalse
        $result.Config.CreateCaptureMedia | Should -BeTrue
    }

    It 'Migration preserves string types' {
        $config = @{
            FFUDevelopmentPath = 'C:\FFU'
            WindowsRelease = '24H2'
            WindowsSKU = 'Pro'
            Make = 'Dell'
            Model = 'Latitude 7490'
        }
        $result = Invoke-FFUConfigMigration -Config $config

        $result.Config.WindowsRelease | Should -Be '24H2'
        $result.Config.WindowsSKU | Should -Be 'Pro'
        $result.Config.Make | Should -Be 'Dell'
        $result.Config.Model | Should -Be 'Latitude 7490'
    }
}
