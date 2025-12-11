#Requires -Version 7.0
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

<#
.SYNOPSIS
    Tests for JSON schema completeness - ensures all BuildFFUVM.ps1 parameters are defined in the schema.

.DESCRIPTION
    This test file validates that the JSON configuration schema (ffubuilder-config.schema.json)
    includes all parameters from BuildFFUVM.ps1 that can be used in configuration files.
    It also validates deprecated property handling and schema structure.

.NOTES
    Created as part of issue fix for config validation errors where properties like
    AdditionalFFUFiles, AppsPath, CopyOfficeConfigXML, etc. were causing errors.
#>

BeforeAll {
    # Get paths
    $script:FFUDevelopmentPath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:SchemaPath = Join-Path $FFUDevelopmentPath 'FFUDevelopment\config\ffubuilder-config.schema.json'
    $script:BuildScriptPath = Join-Path $FFUDevelopmentPath 'FFUDevelopment\BuildFFUVM.ps1'
    $script:ModulesPath = Join-Path $FFUDevelopmentPath 'FFUDevelopment\Modules'

    # Load the schema
    $script:Schema = Get-Content $SchemaPath -Raw | ConvertFrom-Json

    # Get script parameters (excluding common PowerShell parameters)
    $script:CommonParams = @(
        'Debug', 'ErrorAction', 'ErrorVariable', 'InformationAction', 'InformationVariable',
        'OutBuffer', 'OutVariable', 'PipelineVariable', 'Verbose', 'WarningAction', 'WarningVariable',
        'WhatIf', 'Confirm', 'ProgressAction'
    )

    # Parameters that are script-only and NOT meant for config files
    $script:ScriptOnlyParams = @(
        'Cleanup',           # Runtime flag, not persistent config
        'MessagingContext'   # Runtime object for UI communication
    )

    # Get BuildFFUVM.ps1 parameters
    $script:ScriptParams = (Get-Command $BuildScriptPath).Parameters.Keys | Where-Object {
        $_ -notin $CommonParams -and $_ -notin $ScriptOnlyParams
    }
}

Describe 'Schema File Validation' {
    It 'Schema file should exist' {
        Test-Path $SchemaPath | Should -BeTrue
    }

    It 'Schema should be valid JSON' {
        { Get-Content $SchemaPath -Raw | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'Schema should have properties object' {
        $Schema.properties | Should -Not -BeNullOrEmpty
    }

    It 'Schema should have additionalProperties set to false' {
        $Schema.additionalProperties | Should -BeFalse
    }
}

Describe 'Schema Completeness - All Script Parameters in Schema' {
    BeforeAll {
        $script:SchemaProperties = $Schema.properties.PSObject.Properties.Name
    }

    It 'Schema should contain <_> parameter' -ForEach @(
        'AdditionalFFUFiles'
        'AllowExternalHardDiskMedia'
        'AllowVHDXCaching'
        'AppListPath'
        'AppsScriptVariables'
        'BuildUSBDrive'
        'CleanupAppsISO'
        'CleanupCaptureISO'
        'CleanupCurrentRunDownloads'
        'CleanupDeployISO'
        'CleanupDrivers'
        'CompactOS'
        'CompressDownloadedDriversToWim'
        'ConfigFile'
        'CopyAdditionalFFUFiles'
        'CopyAutopilot'
        'CopyDrivers'
        'CopyPEDrivers'
        'CopyPPKG'
        'CopyUnattend'
        'CreateCaptureMedia'
        'CreateDeploymentMedia'
        'CustomFFUNameTemplate'
        'Disksize'
        'DriversFolder'
        'DriversJsonPath'
        'ExportConfigFile'
        'FFUCaptureLocation'
        'FFUDevelopmentPath'
        'FFUPrefix'
        'Headers'
        'InjectUnattend'
        'InstallApps'
        'InstallDrivers'
        'InstallOffice'
        'ISOPath'
        'LogicalSectorSizeBytes'
        'Make'
        'MaxUSBDrives'
        'MediaType'
        'Memory'
        'Model'
        'OfficeConfigXMLFile'
        'Optimize'
        'OptionalFeatures'
        'OrchestrationPath'
        'PEDriversFolder'
        'Processors'
        'ProductKey'
        'PromptExternalHardDiskMedia'
        'RemoveApps'
        'RemoveFFU'
        'RemoveUpdates'
        'ShareName'
        'UpdateADK'
        'UpdateEdge'
        'UpdateLatestCU'
        'UpdateLatestDefender'
        'UpdateLatestMicrocode'
        'UpdateLatestMSRT'
        'UpdateLatestNet'
        'UpdateOneDrive'
        'UpdatePreviewCU'
        'USBDriveList'
        'UseDriversAsPEDrivers'
        'UserAgent'
        'UserAppListPath'
        'Username'
        'VMHostIPAddress'
        'VMLocation'
        'VMSwitchName'
        'WindowsArch'
        'WindowsLang'
        'WindowsRelease'
        'WindowsSKU'
        'WindowsVersion'
    ) {
        $SchemaProperties | Should -Contain $_
    }
}

Describe 'Deprecated Properties' {
    BeforeAll {
        $script:DeprecatedProperties = @(
            'AppsPath'
            'CopyOfficeConfigXML'
            'DownloadDrivers'
            'InstallWingetApps'
            'OfficePath'
            'Threads'
            'Verbose'
        )
    }

    It 'Schema should contain deprecated property <_> for backward compatibility' -ForEach @(
        'AppsPath'
        'CopyOfficeConfigXML'
        'DownloadDrivers'
        'InstallWingetApps'
        'OfficePath'
        'Threads'
        'Verbose'
    ) {
        $Schema.properties.$_.deprecated | Should -BeTrue
    }

    It 'Deprecated property <_> should have [DEPRECATED] in description' -ForEach @(
        'AppsPath'
        'CopyOfficeConfigXML'
        'DownloadDrivers'
        'InstallWingetApps'
        'OfficePath'
        'Threads'
        'Verbose'
    ) {
        $Schema.properties.$_.description | Should -Match '\[DEPRECATED\]'
    }
}

Describe 'Config Validation with Deprecated Properties' {
    BeforeAll {
        # Import FFU.Core module
        $modulePath = Join-Path $ModulesPath 'FFU.Core\FFU.Core.psd1'

        # Add modules folder to PSModulePath if not present
        if ($env:PSModulePath -notlike "*$ModulesPath*") {
            $env:PSModulePath = "$ModulesPath;$env:PSModulePath"
        }

        Import-Module $modulePath -Force -ErrorAction Stop
    }

    It 'Should validate config with deprecated properties as warnings, not errors' {
        $testConfig = @{
            WindowsRelease = 11
            WindowsSKU = 'Pro'
            AppsPath = 'C:\SomePath'  # Deprecated
            Threads = 4               # Deprecated
        }

        $result = Test-FFUConfiguration -ConfigObject $testConfig

        # Should be valid (deprecated doesn't cause failure)
        $result.IsValid | Should -BeTrue

        # Should have warnings for deprecated properties
        $result.Warnings | Should -Not -BeNullOrEmpty
        ($result.Warnings -join "`n") | Should -Match 'AppsPath.*deprecated'
    }

    It 'Should still reject truly unknown properties' {
        $testConfig = @{
            WindowsRelease = 11
            WindowsSKU = 'Pro'
            CompletelyFakeProperty = 'value'  # Not in schema at all
        }

        $result = Test-FFUConfiguration -ConfigObject $testConfig

        # Should fail validation
        $result.IsValid | Should -BeFalse
        ($result.Errors -join "`n") | Should -Match 'CompletelyFakeProperty.*not allowed'
    }
}

Describe 'Schema Property Completeness Against Script' {
    It 'All config-eligible script parameters should be in schema' {
        $missingFromSchema = @()

        foreach ($param in $ScriptParams) {
            $inSchema = $Schema.properties.PSObject.Properties.Name -contains $param
            if (-not $inSchema) {
                $missingFromSchema += $param
            }
        }

        if ($missingFromSchema.Count -gt 0) {
            Write-Warning "Parameters missing from schema: $($missingFromSchema -join ', ')"
        }

        $missingFromSchema.Count | Should -Be 0 -Because "All script parameters should be defined in the schema. Missing: $($missingFromSchema -join ', ')"
    }
}

Describe 'AdditionalFFUFiles Property' {
    It 'AdditionalFFUFiles should allow array of strings' {
        $prop = $Schema.properties.AdditionalFFUFiles
        $prop | Should -Not -BeNullOrEmpty

        # Should be oneOf with array type
        $prop.oneOf | Should -Not -BeNullOrEmpty
        $arrayType = $prop.oneOf | Where-Object { $_.type -eq 'array' }
        $arrayType | Should -Not -BeNullOrEmpty
        $arrayType.items.type | Should -Be 'string'
    }

    It 'AdditionalFFUFiles should allow null' {
        $prop = $Schema.properties.AdditionalFFUFiles
        $nullType = $prop.oneOf | Where-Object { $_.type -eq 'null' }
        $nullType | Should -Not -BeNullOrEmpty
    }
}
