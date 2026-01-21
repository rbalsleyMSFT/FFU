#Requires -Version 5.1
#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for FFU.ConfigMigration module.

.DESCRIPTION
    Pester 5.x tests for configuration schema versioning and migration functionality.
    Covers version detection, deprecated property transformation, backup creation,
    and forward compatibility.

.NOTES
    Module: FFU.ConfigMigration
    Test Type: Unit
    Coverage Target: 100%
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
    $script:TestBasePath = Join-Path $TestDrive 'ConfigMigrationTests'
    New-Item -Path $script:TestBasePath -ItemType Directory -Force | Out-Null
}

AfterAll {
    # Clean up test directory
    if (Test-Path $script:TestBasePath) {
        Remove-Item -Path $script:TestBasePath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'FFU.ConfigMigration Module' {

    It 'imports without errors' {
        $modulesPath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\Modules'
        { Import-Module "$modulesPath\FFU.ConfigMigration" -Force } | Should -Not -Throw
    }

    It 'exports expected functions' {
        $commands = Get-Command -Module FFU.ConfigMigration
        $commands.Name | Should -Contain 'Get-FFUConfigSchemaVersion'
        $commands.Name | Should -Contain 'Test-FFUConfigVersion'
        $commands.Name | Should -Contain 'Invoke-FFUConfigMigration'
        $commands.Name | Should -Contain 'ConvertTo-HashtableRecursive'
    }

    It 'exports exactly 4 functions' {
        $commands = Get-Command -Module FFU.ConfigMigration
        $commands.Count | Should -Be 4
    }
}

Describe 'Get-FFUConfigSchemaVersion' {

    It 'returns a string type' {
        $result = Get-FFUConfigSchemaVersion
        $result | Should -BeOfType [string]
    }

    It 'returns "1.2" as current version' {
        $result = Get-FFUConfigSchemaVersion
        $result | Should -Be '1.2'
    }

    It 'returns same value on multiple calls (consistent)' {
        $result1 = Get-FFUConfigSchemaVersion
        $result2 = Get-FFUConfigSchemaVersion
        $result1 | Should -Be $result2
    }

    It 'returns version in major.minor format' {
        $result = Get-FFUConfigSchemaVersion
        $result | Should -Match '^\d+\.\d+$'
    }
}

Describe 'Test-FFUConfigVersion' {

    Context 'With hashtable Config parameter' {

        It 'detects pre-versioning config (no configSchemaVersion) as NeedsMigration=$true' {
            $config = @{
                FFUDevelopmentPath = 'C:\FFU'
                InstallApps = $true
            }
            $result = Test-FFUConfigVersion -Config $config
            $result.NeedsMigration | Should -BeTrue
            $result.ConfigVersion | Should -Be '0.0'
        }

        It 'detects current version config as NeedsMigration=$false' {
            $config = @{
                configSchemaVersion = '1.2'
                FFUDevelopmentPath = 'C:\FFU'
            }
            $result = Test-FFUConfigVersion -Config $config
            $result.NeedsMigration | Should -BeFalse
            $result.ConfigVersion | Should -Be '1.2'
        }

        It 'detects older version config as NeedsMigration=$true' {
            $config = @{
                configSchemaVersion = '0.5'
                FFUDevelopmentPath = 'C:\FFU'
            }
            $result = Test-FFUConfigVersion -Config $config
            $result.NeedsMigration | Should -BeTrue
            $result.ConfigVersion | Should -Be '0.5'
        }

        It 'detects newer version config as NeedsMigration=$false (forward compatible)' {
            $config = @{
                configSchemaVersion = '2.0'
                FFUDevelopmentPath = 'C:\FFU'
            }
            $result = Test-FFUConfigVersion -Config $config
            $result.NeedsMigration | Should -BeFalse
            $result.ConfigVersion | Should -Be '2.0'
        }

        It 'returns CurrentSchemaVersion matching Get-FFUConfigSchemaVersion' {
            $config = @{ FFUDevelopmentPath = 'C:\FFU' }
            $result = Test-FFUConfigVersion -Config $config
            $result.CurrentSchemaVersion | Should -Be (Get-FFUConfigSchemaVersion)
        }

        It 'returns correct VersionDifference for older config' {
            $config = @{ configSchemaVersion = '0.5' }
            $result = Test-FFUConfigVersion -Config $config
            $result.VersionDifference | Should -BeGreaterThan 0
        }

        It 'returns correct VersionDifference for current config' {
            $config = @{ configSchemaVersion = '1.2' }
            $result = Test-FFUConfigVersion -Config $config
            $result.VersionDifference | Should -Be 0
        }

        It 'returns correct VersionDifference for newer config' {
            $config = @{ configSchemaVersion = '2.0' }
            $result = Test-FFUConfigVersion -Config $config
            $result.VersionDifference | Should -BeLessThan 0
        }

        It 'handles custom CurrentSchemaVersion parameter' {
            $config = @{ configSchemaVersion = '1.5' }
            $result = Test-FFUConfigVersion -Config $config -CurrentSchemaVersion '2.0'
            $result.NeedsMigration | Should -BeTrue
            $result.CurrentSchemaVersion | Should -Be '2.0'
        }

        It 'handles version comparison correctly (1.0 < 1.10)' {
            $config = @{ configSchemaVersion = '1.0' }
            $result = Test-FFUConfigVersion -Config $config -CurrentSchemaVersion '1.10'
            $result.NeedsMigration | Should -BeTrue
        }
    }

    Context 'With ConfigPath parameter' {

        It 'reads config from JSON file' {
            $configPath = Join-Path $script:TestBasePath 'test-config.json'
            $config = @{
                configSchemaVersion = '0.5'
                FFUDevelopmentPath = 'C:\FFU'
            }
            $config | ConvertTo-Json | Set-Content -Path $configPath

            $result = Test-FFUConfigVersion -ConfigPath $configPath
            $result.ConfigVersion | Should -Be '0.5'
            $result.NeedsMigration | Should -BeTrue
        }

        It 'handles config file without configSchemaVersion' {
            $configPath = Join-Path $script:TestBasePath 'legacy-config.json'
            $config = @{
                FFUDevelopmentPath = 'C:\FFU'
                AppsPath = 'C:\FFU\Apps'
            }
            $config | ConvertTo-Json | Set-Content -Path $configPath

            $result = Test-FFUConfigVersion -ConfigPath $configPath
            $result.ConfigVersion | Should -Be '0.0'
            $result.NeedsMigration | Should -BeTrue
        }
    }
}

Describe 'ConvertTo-HashtableRecursive' {

    It 'returns null for null input' {
        $result = ConvertTo-HashtableRecursive -InputObject $null
        $result | Should -BeNullOrEmpty
    }

    It 'returns primitive values as-is (string)' {
        $result = ConvertTo-HashtableRecursive -InputObject 'test'
        $result | Should -Be 'test'
    }

    It 'returns primitive values as-is (integer)' {
        $result = ConvertTo-HashtableRecursive -InputObject 42
        $result | Should -Be 42
    }

    It 'returns primitive values as-is (boolean)' {
        $result = ConvertTo-HashtableRecursive -InputObject $true
        $result | Should -BeTrue
    }

    It 'converts PSCustomObject to hashtable' {
        $psObject = [PSCustomObject]@{
            Name = 'Test'
            Value = 123
        }
        $result = ConvertTo-HashtableRecursive -InputObject $psObject
        $result | Should -BeOfType [hashtable]
        $result.Name | Should -Be 'Test'
        $result.Value | Should -Be 123
    }

    It 'converts nested PSCustomObject recursively' {
        $psObject = [PSCustomObject]@{
            Parent = 'Root'
            Child = [PSCustomObject]@{
                Name = 'Nested'
                Value = 456
            }
        }
        $result = ConvertTo-HashtableRecursive -InputObject $psObject
        $result | Should -BeOfType [hashtable]
        $result.Child | Should -BeOfType [hashtable]
        $result.Child.Name | Should -Be 'Nested'
    }

    It 'processes arrays element-by-element' {
        $array = @(
            [PSCustomObject]@{ Name = 'First' },
            [PSCustomObject]@{ Name = 'Second' }
        )
        $result = ConvertTo-HashtableRecursive -InputObject $array
        $result | Should -HaveCount 2
        $result[0] | Should -BeOfType [hashtable]
        $result[0].Name | Should -Be 'First'
    }

    It 'handles existing hashtable with nested PSCustomObject' {
        $hashtable = @{
            TopLevel = 'value'
            Nested = [PSCustomObject]@{ Inner = 'data' }
        }
        $result = ConvertTo-HashtableRecursive -InputObject $hashtable
        $result | Should -BeOfType [hashtable]
        $result.Nested | Should -BeOfType [hashtable]
        $result.Nested.Inner | Should -Be 'data'
    }
}

Describe 'Invoke-FFUConfigMigration' {

    Context 'Version handling' {

        It 'returns unchanged config when already at target version' {
            $config = @{
                configSchemaVersion = '1.2'
                FFUDevelopmentPath = 'C:\FFU'
                InstallApps = $true
                IncludePreviewUpdates = $false
                VMwareSettings = @{ NetworkType = 'nat'; NicType = 'e1000e' }
            }
            $result = Invoke-FFUConfigMigration -Config $config
            $result.Config.FFUDevelopmentPath | Should -Be 'C:\FFU'
            $result.Config.InstallApps | Should -BeTrue
            $result.Changes | Should -HaveCount 0
        }

        It 'returns unchanged config when beyond target version' {
            $config = @{
                configSchemaVersion = '2.0'
                FFUDevelopmentPath = 'C:\FFU'
            }
            $result = Invoke-FFUConfigMigration -Config $config
            $result.Changes | Should -HaveCount 0
            $result.Config.configSchemaVersion | Should -Be '2.0'
        }

        It 'sets FromVersion to 0.0 for pre-versioning config' {
            $config = @{ FFUDevelopmentPath = 'C:\FFU' }
            $result = Invoke-FFUConfigMigration -Config $config
            $result.FromVersion | Should -Be '0.0'
        }

        It 'sets ToVersion to target version' {
            $config = @{ FFUDevelopmentPath = 'C:\FFU' }
            $result = Invoke-FFUConfigMigration -Config $config
            $result.ToVersion | Should -Be '1.2'
        }

        It 'sets configSchemaVersion in migrated config' {
            $config = @{ FFUDevelopmentPath = 'C:\FFU' }
            $result = Invoke-FFUConfigMigration -Config $config
            $result.Config.configSchemaVersion | Should -Be '1.2'
        }
    }

    Context 'Deprecated property: AppsPath' {

        It 'removes AppsPath from migrated config' {
            $config = @{
                FFUDevelopmentPath = 'C:\FFU'
                AppsPath = 'C:\FFU\Apps'
            }
            $result = Invoke-FFUConfigMigration -Config $config
            $result.Config.ContainsKey('AppsPath') | Should -BeFalse
        }

        It 'adds change description for AppsPath removal' {
            $config = @{
                FFUDevelopmentPath = 'C:\FFU'
                AppsPath = 'C:\FFU\Apps'
            }
            $result = Invoke-FFUConfigMigration -Config $config
            $result.Changes | Should -Contain "Removed deprecated property 'AppsPath' (now computed from FFUDevelopmentPath)"
        }
    }

    Context 'Deprecated property: OfficePath' {

        It 'removes OfficePath from migrated config' {
            $config = @{
                FFUDevelopmentPath = 'C:\FFU'
                OfficePath = 'C:\FFU\Office'
            }
            $result = Invoke-FFUConfigMigration -Config $config
            $result.Config.ContainsKey('OfficePath') | Should -BeFalse
        }

        It 'adds change description for OfficePath removal' {
            $config = @{
                FFUDevelopmentPath = 'C:\FFU'
                OfficePath = 'C:\FFU\Office'
            }
            $result = Invoke-FFUConfigMigration -Config $config
            $result.Changes | Should -Contain "Removed deprecated property 'OfficePath' (now computed from FFUDevelopmentPath)"
        }
    }

    Context 'Deprecated property: Verbose' {

        It 'removes Verbose from migrated config' {
            $config = @{
                FFUDevelopmentPath = 'C:\FFU'
                Verbose = $true
            }
            $result = Invoke-FFUConfigMigration -Config $config
            $result.Config.ContainsKey('Verbose') | Should -BeFalse
        }

        It 'adds change description for Verbose removal' {
            $config = @{
                FFUDevelopmentPath = 'C:\FFU'
                Verbose = $true
            }
            $result = Invoke-FFUConfigMigration -Config $config
            $result.Changes | Should -Contain "Removed deprecated property 'Verbose' (use -Verbose CLI switch instead)"
        }
    }

    Context 'Deprecated property: Threads' {

        It 'removes Threads from migrated config' {
            $config = @{
                FFUDevelopmentPath = 'C:\FFU'
                Threads = 4
            }
            $result = Invoke-FFUConfigMigration -Config $config
            $result.Config.ContainsKey('Threads') | Should -BeFalse
        }

        It 'adds change description for Threads removal' {
            $config = @{
                FFUDevelopmentPath = 'C:\FFU'
                Threads = 4
            }
            $result = Invoke-FFUConfigMigration -Config $config
            $result.Changes | Should -Contain "Removed deprecated property 'Threads' (parallel processing now automatic)"
        }
    }

    Context 'Deprecated property: InstallWingetApps' {

        It 'migrates InstallWingetApps=true to InstallApps=true' {
            $config = @{
                FFUDevelopmentPath = 'C:\FFU'
                InstallWingetApps = $true
            }
            $result = Invoke-FFUConfigMigration -Config $config
            $result.Config.InstallApps | Should -BeTrue
            $result.Config.ContainsKey('InstallWingetApps') | Should -BeFalse
        }

        It 'does not overwrite existing InstallApps=true' {
            $config = @{
                FFUDevelopmentPath = 'C:\FFU'
                InstallApps = $true
                InstallWingetApps = $true
            }
            $result = Invoke-FFUConfigMigration -Config $config
            $result.Config.InstallApps | Should -BeTrue
            $result.Changes | Should -Contain "Removed 'InstallWingetApps' (InstallApps already set)"
        }

        It 'removes InstallWingetApps=false without setting InstallApps' {
            $config = @{
                FFUDevelopmentPath = 'C:\FFU'
                InstallWingetApps = $false
            }
            $result = Invoke-FFUConfigMigration -Config $config
            $result.Config.ContainsKey('InstallWingetApps') | Should -BeFalse
            # InstallApps should not be set (or remain at whatever it was)
        }
    }

    Context 'Deprecated property: DownloadDrivers' {

        It 'removes DownloadDrivers and adds warning when Make not set' {
            $config = @{
                FFUDevelopmentPath = 'C:\FFU'
                DownloadDrivers = $true
            }
            $result = Invoke-FFUConfigMigration -Config $config
            $result.Config.ContainsKey('DownloadDrivers') | Should -BeFalse
            $result.Changes | Where-Object { $_ -like "WARNING:*Make*" } | Should -Not -BeNullOrEmpty
        }

        It 'removes DownloadDrivers without warning when Make is set' {
            $config = @{
                FFUDevelopmentPath = 'C:\FFU'
                DownloadDrivers = $true
                Make = 'Dell'
                Model = 'Latitude 7490'
            }
            $result = Invoke-FFUConfigMigration -Config $config
            $result.Config.ContainsKey('DownloadDrivers') | Should -BeFalse
            $result.Changes | Where-Object { $_ -like "WARNING:*Make*" } | Should -BeNullOrEmpty
        }

        It 'removes DownloadDrivers=false without warning' {
            $config = @{
                FFUDevelopmentPath = 'C:\FFU'
                DownloadDrivers = $false
            }
            $result = Invoke-FFUConfigMigration -Config $config
            $result.Config.ContainsKey('DownloadDrivers') | Should -BeFalse
            $result.Changes | Should -Contain "Removed deprecated property 'DownloadDrivers' (was false)"
        }
    }

    Context 'Deprecated property: CopyOfficeConfigXML' {

        It 'removes CopyOfficeConfigXML and adds warning when OfficeConfigXMLFile not set' {
            $config = @{
                FFUDevelopmentPath = 'C:\FFU'
                CopyOfficeConfigXML = $true
            }
            $result = Invoke-FFUConfigMigration -Config $config
            $result.Config.ContainsKey('CopyOfficeConfigXML') | Should -BeFalse
            $result.Changes | Where-Object { $_ -like "WARNING:*OfficeConfigXMLFile*" } | Should -Not -BeNullOrEmpty
        }

        It 'removes CopyOfficeConfigXML without warning when OfficeConfigXMLFile is set' {
            $config = @{
                FFUDevelopmentPath = 'C:\FFU'
                CopyOfficeConfigXML = $true
                OfficeConfigXMLFile = 'C:\FFU\Office\config.xml'
            }
            $result = Invoke-FFUConfigMigration -Config $config
            $result.Config.ContainsKey('CopyOfficeConfigXML') | Should -BeFalse
            $result.Changes | Where-Object { $_ -like "WARNING:*OfficeConfigXMLFile*" } | Should -BeNullOrEmpty
        }

        It 'removes CopyOfficeConfigXML=false without warning' {
            $config = @{
                FFUDevelopmentPath = 'C:\FFU'
                CopyOfficeConfigXML = $false
            }
            $result = Invoke-FFUConfigMigration -Config $config
            $result.Config.ContainsKey('CopyOfficeConfigXML') | Should -BeFalse
            $result.Changes | Should -Contain "Removed deprecated property 'CopyOfficeConfigXML' (was false)"
        }
    }

    Context 'Forward compatibility' {

        It 'preserves unknown properties (future config fields)' {
            $config = @{
                FFUDevelopmentPath = 'C:\FFU'
                FutureProperty = 'some value'
                AnotherNewField = 123
            }
            $result = Invoke-FFUConfigMigration -Config $config
            $result.Config.FutureProperty | Should -Be 'some value'
            $result.Config.AnotherNewField | Should -Be 123
        }

        It 'preserves all standard properties' {
            $config = @{
                FFUDevelopmentPath = 'C:\FFU'
                InstallApps = $true
                WindowsRelease = 11
                WindowsSKU = 'Pro'
                Memory = 8589934592
            }
            $result = Invoke-FFUConfigMigration -Config $config
            $result.Config.InstallApps | Should -BeTrue
            $result.Config.WindowsRelease | Should -Be 11
            $result.Config.WindowsSKU | Should -Be 'Pro'
            $result.Config.Memory | Should -Be 8589934592
        }
    }

    Context 'Backup functionality' {

        It 'creates backup file when CreateBackup is specified' {
            $configPath = Join-Path $script:TestBasePath 'backup-test.json'
            $config = @{
                FFUDevelopmentPath = 'C:\FFU'
                Verbose = $true
            }
            $config | ConvertTo-Json | Set-Content -Path $configPath

            $result = Invoke-FFUConfigMigration -Config $config -CreateBackup -ConfigPath $configPath
            $result.BackupPath | Should -Not -BeNullOrEmpty
            Test-Path $result.BackupPath | Should -BeTrue
        }

        It 'backup file has timestamp suffix' {
            $configPath = Join-Path $script:TestBasePath 'backup-timestamp.json'
            $config = @{ FFUDevelopmentPath = 'C:\FFU' }
            $config | ConvertTo-Json | Set-Content -Path $configPath

            $result = Invoke-FFUConfigMigration -Config $config -CreateBackup -ConfigPath $configPath
            $result.BackupPath | Should -Match '\.backup-\d{8}-\d{6}$'
        }

        It 'backup contains original config content' {
            $configPath = Join-Path $script:TestBasePath 'backup-content.json'
            $config = @{
                FFUDevelopmentPath = 'C:\FFU'
                AppsPath = 'C:\FFU\Apps'
                Verbose = $true
            }
            $config | ConvertTo-Json | Set-Content -Path $configPath

            $result = Invoke-FFUConfigMigration -Config $config -CreateBackup -ConfigPath $configPath
            $backupContent = Get-Content $result.BackupPath -Raw | ConvertFrom-Json
            $backupContent.AppsPath | Should -Be 'C:\FFU\Apps'
            $backupContent.Verbose | Should -BeTrue
        }

        It 'returns null BackupPath when CreateBackup not specified' {
            $config = @{ FFUDevelopmentPath = 'C:\FFU' }
            $result = Invoke-FFUConfigMigration -Config $config
            $result.BackupPath | Should -BeNullOrEmpty
        }
    }

    Context 'Changes array' {

        It 'returns empty changes array when no migration needed' {
            $config = @{
                configSchemaVersion = '1.2'
                FFUDevelopmentPath = 'C:\FFU'
                IncludePreviewUpdates = $false
                VMwareSettings = @{ NetworkType = 'nat'; NicType = 'e1000e' }
            }
            $result = Invoke-FFUConfigMigration -Config $config
            $result.Changes | Should -HaveCount 0
        }

        It 'returns change descriptions for each migrated property' {
            $config = @{
                FFUDevelopmentPath = 'C:\FFU'
                AppsPath = 'C:\FFU\Apps'
                OfficePath = 'C:\FFU\Office'
                Verbose = $true
                Threads = 4
            }
            $result = Invoke-FFUConfigMigration -Config $config
            # 4 deprecated properties + IncludePreviewUpdates default + VMwareSettings default = 6
            $result.Changes | Should -HaveCount 6
        }

        It 'WARNING prefix for properties requiring manual action' {
            $config = @{
                FFUDevelopmentPath = 'C:\FFU'
                DownloadDrivers = $true
                CopyOfficeConfigXML = $true
            }
            $result = Invoke-FFUConfigMigration -Config $config
            $warnings = $result.Changes | Where-Object { $_ -like "WARNING:*" }
            $warnings | Should -HaveCount 2
        }
    }

    Context 'Complete migration scenario' {

        It 'migrates complex pre-versioning config correctly' {
            $config = @{
                FFUDevelopmentPath = 'C:\FFUDevelopment'
                AppsPath = 'C:\FFUDevelopment\Apps'
                OfficePath = 'C:\FFUDevelopment\Office'
                Verbose = $true
                Threads = 8
                InstallWingetApps = $true
                DownloadDrivers = $true
                Make = 'Dell'
                Model = 'Latitude 7490'
                WindowsRelease = 11
                WindowsSKU = 'Pro'
                InstallOffice = $true
                CustomProperty = 'preserved'
            }

            $result = Invoke-FFUConfigMigration -Config $config

            # Verify removed properties
            $result.Config.ContainsKey('AppsPath') | Should -BeFalse
            $result.Config.ContainsKey('OfficePath') | Should -BeFalse
            $result.Config.ContainsKey('Verbose') | Should -BeFalse
            $result.Config.ContainsKey('Threads') | Should -BeFalse
            $result.Config.ContainsKey('InstallWingetApps') | Should -BeFalse
            $result.Config.ContainsKey('DownloadDrivers') | Should -BeFalse

            # Verify migrated properties
            $result.Config.InstallApps | Should -BeTrue

            # Verify preserved properties
            $result.Config.FFUDevelopmentPath | Should -Be 'C:\FFUDevelopment'
            $result.Config.Make | Should -Be 'Dell'
            $result.Config.Model | Should -Be 'Latitude 7490'
            $result.Config.WindowsRelease | Should -Be 11
            $result.Config.WindowsSKU | Should -Be 'Pro'
            $result.Config.InstallOffice | Should -BeTrue
            $result.Config.CustomProperty | Should -Be 'preserved'

            # Verify version set
            $result.Config.configSchemaVersion | Should -Be '1.2'
            $result.FromVersion | Should -Be '0.0'
            $result.ToVersion | Should -Be '1.2'

            # Verify new defaults added
            $result.Config.IncludePreviewUpdates | Should -BeFalse
            $result.Config.VMwareSettings | Should -Not -BeNullOrEmpty
            $result.Config.VMwareSettings.NetworkType | Should -Be 'nat'
            $result.Config.VMwareSettings.NicType | Should -Be 'e1000e'

            # Verify change count (5 removed + 1 migrated + 1 IncludePreviewUpdates + 1 VMwareSettings = 8)
            $result.Changes.Count | Should -Be 8
        }
    }
}
