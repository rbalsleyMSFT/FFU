#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for FFU.Core Configuration Schema Validation

.DESCRIPTION
    Tests for Test-FFUConfiguration and Get-FFUConfigurationSchema functions
    that validate FFU Builder configuration files against the JSON schema.

.NOTES
    Version: 1.0.0
    Created for FFU.Core v1.0.10
#>

BeforeAll {
    # Get paths - Tests are in C:\claude\FFUBuilder\Tests\Unit
    # FFUDevelopment is in C:\claude\FFUBuilder\FFUDevelopment
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:FFUDevelopmentPath = Join-Path $script:RepoRoot "FFUDevelopment"
    $script:ModulePath = Join-Path $script:FFUDevelopmentPath "Modules"
    $script:SchemaPath = Join-Path $script:FFUDevelopmentPath "config\ffubuilder-config.schema.json"
    $script:SampleConfigPath = Join-Path $script:FFUDevelopmentPath "config\Sample_default.json"

    # Add modules to path and import
    if ($env:PSModulePath -notlike "*$script:ModulePath*") {
        $env:PSModulePath = "$script:ModulePath;$env:PSModulePath"
    }

    # Import FFU.Core module
    Import-Module (Join-Path $script:ModulePath "FFU.Core\FFU.Core.psd1") -Force -ErrorAction Stop

    # Helper to create temp config file
    function New-TempConfigFile {
        param([hashtable]$Config)
        $tempFile = [System.IO.Path]::GetTempFileName()
        $tempFile = [System.IO.Path]::ChangeExtension($tempFile, ".json")
        $Config | ConvertTo-Json -Depth 10 | Set-Content -Path $tempFile -Encoding UTF8
        return $tempFile
    }
}

Describe "Schema File Validation" {
    It "Schema file exists at expected location" {
        $script:SchemaPath | Should -Exist
    }

    It "Schema file is valid JSON" {
        { Get-Content $script:SchemaPath -Raw | ConvertFrom-Json } | Should -Not -Throw
    }

    It "Schema has required structure" {
        $schema = Get-Content $script:SchemaPath -Raw | ConvertFrom-Json
        $schema.'$schema' | Should -Not -BeNullOrEmpty
        $schema.title | Should -Not -BeNullOrEmpty
        $schema.type | Should -Be "object"
        $schema.properties | Should -Not -BeNullOrEmpty
    }

    It "Schema defines WindowsSKU enum values" {
        $schema = Get-Content $script:SchemaPath -Raw | ConvertFrom-Json
        $schema.properties.WindowsSKU.enum | Should -Contain "Pro"
        $schema.properties.WindowsSKU.enum | Should -Contain "Enterprise"
        $schema.properties.WindowsSKU.enum | Should -Contain "Home"
    }

    It "Schema defines WindowsArch enum values" {
        $schema = Get-Content $script:SchemaPath -Raw | ConvertFrom-Json
        $schema.properties.WindowsArch.enum | Should -Contain "x64"
        $schema.properties.WindowsArch.enum | Should -Contain "x86"
        $schema.properties.WindowsArch.enum | Should -Contain "arm64"
    }

    It "Schema defines Memory range constraints" {
        $schema = Get-Content $script:SchemaPath -Raw | ConvertFrom-Json
        $schema.properties.Memory.minimum | Should -Be 2147483648  # 2GB
        $schema.properties.Memory.maximum | Should -Be 137438953472  # 128GB
    }

    It "Schema defines Disksize range constraints" {
        $schema = Get-Content $script:SchemaPath -Raw | ConvertFrom-Json
        $schema.properties.Disksize.minimum | Should -Be 26843545600  # 25GB
        $schema.properties.Disksize.maximum | Should -Be 2199023255552  # 2TB
    }

    It "Schema defines Processors range constraints" {
        $schema = Get-Content $script:SchemaPath -Raw | ConvertFrom-Json
        $schema.properties.Processors.minimum | Should -Be 1
        $schema.properties.Processors.maximum | Should -Be 64
    }
}

Describe "Get-FFUConfigurationSchema" {
    It "Returns a string path" {
        $result = Get-FFUConfigurationSchema
        $result | Should -BeOfType [string]
    }

    It "Returns path ending with ffubuilder-config.schema.json" {
        $result = Get-FFUConfigurationSchema
        $result | Should -Match "ffubuilder-config\.schema\.json$"
    }
}

Describe "Test-FFUConfiguration - Valid Configurations" {
    It "Validates the Sample_default.json configuration" {
        $result = Test-FFUConfiguration -ConfigPath $script:SampleConfigPath -SchemaPath $script:SchemaPath
        $result.IsValid | Should -Be $true -Because ($result.Errors -join '; ')
        $result.Errors.Count | Should -Be 0
    }

    It "Validates a minimal valid configuration" {
        $tempFile = New-TempConfigFile -Config @{
            WindowsSKU = "Pro"
            WindowsRelease = 11
        }
        try {
            $result = Test-FFUConfiguration -ConfigPath $tempFile -SchemaPath $script:SchemaPath
            $result.IsValid | Should -Be $true
        }
        finally {
            Remove-Item $tempFile -ErrorAction SilentlyContinue
        }
    }

    It "Validates configuration with all boolean properties" {
        $tempFile = New-TempConfigFile -Config @{
            InstallApps = $true
            InstallDrivers = $false
            InstallOffice = $true
            CreateCaptureMedia = $true
            CreateDeploymentMedia = $false
            CompactOS = $true
            Optimize = $true
        }
        try {
            $result = Test-FFUConfiguration -ConfigPath $tempFile -SchemaPath $script:SchemaPath
            $result.IsValid | Should -Be $true
        }
        finally {
            Remove-Item $tempFile -ErrorAction SilentlyContinue
        }
    }

    It "Validates configuration with numeric properties in range" {
        $tempFile = New-TempConfigFile -Config @{
            Memory = 8589934592  # 8GB
            Disksize = 53687091200  # 50GB
            Processors = 4
            MaxUSBDrives = 10
        }
        try {
            $result = Test-FFUConfiguration -ConfigPath $tempFile -SchemaPath $script:SchemaPath
            $result.IsValid | Should -Be $true
        }
        finally {
            Remove-Item $tempFile -ErrorAction SilentlyContinue
        }
    }

    It "Validates configuration using ConfigObject parameter" {
        $config = @{
            WindowsSKU = "Enterprise"
            WindowsRelease = 11
            WindowsArch = "x64"
            MediaType = "business"
        }
        $result = Test-FFUConfiguration -ConfigObject $config -SchemaPath $script:SchemaPath
        $result.IsValid | Should -Be $true
    }

    It "Returns parsed config object" {
        $config = @{
            WindowsSKU = "Pro"
            Memory = 4294967296
        }
        $result = Test-FFUConfiguration -ConfigObject $config -SchemaPath $script:SchemaPath
        $result.Config | Should -Not -BeNullOrEmpty
        $result.Config.WindowsSKU | Should -Be "Pro"
    }
}

Describe "Test-FFUConfiguration - Type Errors" {
    It "Catches type error: string instead of boolean" {
        $tempFile = New-TempConfigFile -Config @{
            InstallApps = "true"  # Should be boolean
        }
        try {
            $result = Test-FFUConfiguration -ConfigPath $tempFile -SchemaPath $script:SchemaPath
            $result.IsValid | Should -Be $false
            ($result.Errors -join ';') | Should -Match "InstallApps.*type"
        }
        finally {
            Remove-Item $tempFile -ErrorAction SilentlyContinue
        }
    }

    It "Catches type error: string instead of integer" {
        $tempFile = New-TempConfigFile -Config @{
            Processors = "four"  # Should be integer
        }
        try {
            $result = Test-FFUConfiguration -ConfigPath $tempFile -SchemaPath $script:SchemaPath
            $result.IsValid | Should -Be $false
            ($result.Errors -join ';') | Should -Match "Processors.*type"
        }
        finally {
            Remove-Item $tempFile -ErrorAction SilentlyContinue
        }
    }

    It "Catches type error: boolean instead of string" {
        $tempFile = New-TempConfigFile -Config @{
            WindowsSKU = $true  # Should be string
        }
        try {
            $result = Test-FFUConfiguration -ConfigPath $tempFile -SchemaPath $script:SchemaPath
            $result.IsValid | Should -Be $false
            ($result.Errors -join ';') | Should -Match "WindowsSKU.*type"
        }
        finally {
            Remove-Item $tempFile -ErrorAction SilentlyContinue
        }
    }
}

Describe "Test-FFUConfiguration - Enum Violations" {
    It "Catches invalid WindowsSKU value" {
        $tempFile = New-TempConfigFile -Config @{
            WindowsSKU = "InvalidSKU"
        }
        try {
            $result = Test-FFUConfiguration -ConfigPath $tempFile -SchemaPath $script:SchemaPath
            $result.IsValid | Should -Be $false
            ($result.Errors -join ';') | Should -Match "WindowsSKU.*invalid value"
        }
        finally {
            Remove-Item $tempFile -ErrorAction SilentlyContinue
        }
    }

    It "Catches invalid WindowsArch value" {
        $tempFile = New-TempConfigFile -Config @{
            WindowsArch = "ia64"  # Not a valid architecture
        }
        try {
            $result = Test-FFUConfiguration -ConfigPath $tempFile -SchemaPath $script:SchemaPath
            $result.IsValid | Should -Be $false
            ($result.Errors -join ';') | Should -Match "WindowsArch.*invalid value"
        }
        finally {
            Remove-Item $tempFile -ErrorAction SilentlyContinue
        }
    }

    It "Catches invalid MediaType value" {
        $tempFile = New-TempConfigFile -Config @{
            MediaType = "retail"  # Should be 'consumer' or 'business'
        }
        try {
            $result = Test-FFUConfiguration -ConfigPath $tempFile -SchemaPath $script:SchemaPath
            $result.IsValid | Should -Be $false
            ($result.Errors -join ';') | Should -Match "MediaType.*invalid value"
        }
        finally {
            Remove-Item $tempFile -ErrorAction SilentlyContinue
        }
    }

    It "Catches invalid Make value" {
        $tempFile = New-TempConfigFile -Config @{
            Make = "Samsung"  # Not a supported OEM
        }
        try {
            $result = Test-FFUConfiguration -ConfigPath $tempFile -SchemaPath $script:SchemaPath
            $result.IsValid | Should -Be $false
            ($result.Errors -join ';') | Should -Match "Make.*invalid value"
        }
        finally {
            Remove-Item $tempFile -ErrorAction SilentlyContinue
        }
    }

    It "Catches invalid LogicalSectorSizeBytes value" {
        $tempFile = New-TempConfigFile -Config @{
            LogicalSectorSizeBytes = 1024  # Only 512 or 4096 allowed
        }
        try {
            $result = Test-FFUConfiguration -ConfigPath $tempFile -SchemaPath $script:SchemaPath
            $result.IsValid | Should -Be $false
            ($result.Errors -join ';') | Should -Match "LogicalSectorSizeBytes.*invalid value"
        }
        finally {
            Remove-Item $tempFile -ErrorAction SilentlyContinue
        }
    }

    It "Catches invalid WindowsRelease value" {
        $tempFile = New-TempConfigFile -Config @{
            WindowsRelease = 12  # Only 10, 11, or server versions allowed
        }
        try {
            $result = Test-FFUConfiguration -ConfigPath $tempFile -SchemaPath $script:SchemaPath
            $result.IsValid | Should -Be $false
            ($result.Errors -join ';') | Should -Match "WindowsRelease.*invalid value"
        }
        finally {
            Remove-Item $tempFile -ErrorAction SilentlyContinue
        }
    }
}

Describe "Test-FFUConfiguration - Range Violations" {
    It "Catches Memory below minimum" {
        $tempFile = New-TempConfigFile -Config @{
            Memory = 1073741824  # 1GB - below 2GB minimum
        }
        try {
            $result = Test-FFUConfiguration -ConfigPath $tempFile -SchemaPath $script:SchemaPath
            $result.IsValid | Should -Be $false
            ($result.Errors -join ';') | Should -Match "Memory.*less than minimum"
        }
        finally {
            Remove-Item $tempFile -ErrorAction SilentlyContinue
        }
    }

    It "Catches Memory above maximum" {
        $tempFile = New-TempConfigFile -Config @{
            Memory = 274877906944  # 256GB - above 128GB maximum
        }
        try {
            $result = Test-FFUConfiguration -ConfigPath $tempFile -SchemaPath $script:SchemaPath
            $result.IsValid | Should -Be $false
            ($result.Errors -join ';') | Should -Match "Memory.*greater than maximum"
        }
        finally {
            Remove-Item $tempFile -ErrorAction SilentlyContinue
        }
    }

    It "Catches Processors below minimum" {
        $tempFile = New-TempConfigFile -Config @{
            Processors = 0  # Minimum is 1
        }
        try {
            $result = Test-FFUConfiguration -ConfigPath $tempFile -SchemaPath $script:SchemaPath
            $result.IsValid | Should -Be $false
            ($result.Errors -join ';') | Should -Match "Processors.*less than minimum"
        }
        finally {
            Remove-Item $tempFile -ErrorAction SilentlyContinue
        }
    }

    It "Catches Processors above maximum" {
        $tempFile = New-TempConfigFile -Config @{
            Processors = 128  # Maximum is 64
        }
        try {
            $result = Test-FFUConfiguration -ConfigPath $tempFile -SchemaPath $script:SchemaPath
            $result.IsValid | Should -Be $false
            ($result.Errors -join ';') | Should -Match "Processors.*greater than maximum"
        }
        finally {
            Remove-Item $tempFile -ErrorAction SilentlyContinue
        }
    }

    It "Catches Disksize below minimum" {
        $tempFile = New-TempConfigFile -Config @{
            Disksize = 10737418240  # 10GB - below 25GB minimum
        }
        try {
            $result = Test-FFUConfiguration -ConfigPath $tempFile -SchemaPath $script:SchemaPath
            $result.IsValid | Should -Be $false
            ($result.Errors -join ';') | Should -Match "Disksize.*less than minimum"
        }
        finally {
            Remove-Item $tempFile -ErrorAction SilentlyContinue
        }
    }
}

Describe "Test-FFUConfiguration - Missing Optional Properties" {
    It "Handles missing optional properties gracefully" {
        $tempFile = New-TempConfigFile -Config @{
            WindowsSKU = "Pro"
            # All other properties omitted (they're optional)
        }
        try {
            $result = Test-FFUConfiguration -ConfigPath $tempFile -SchemaPath $script:SchemaPath
            $result.IsValid | Should -Be $true
        }
        finally {
            Remove-Item $tempFile -ErrorAction SilentlyContinue
        }
    }

    It "Handles null values for nullable properties" {
        $tempFile = New-TempConfigFile -Config @{
            AppsScriptVariables = $null
            USBDriveList = $null
        }
        try {
            $result = Test-FFUConfiguration -ConfigPath $tempFile -SchemaPath $script:SchemaPath
            $result.IsValid | Should -Be $true
        }
        finally {
            Remove-Item $tempFile -ErrorAction SilentlyContinue
        }
    }
}

Describe "Test-FFUConfiguration - Multiple Errors" {
    It "Reports multiple validation errors" {
        $tempFile = New-TempConfigFile -Config @{
            WindowsSKU = "InvalidSKU"
            WindowsArch = "ia64"
            Memory = 1073741824  # Below minimum
            Processors = 128  # Above maximum
        }
        try {
            $result = Test-FFUConfiguration -ConfigPath $tempFile -SchemaPath $script:SchemaPath
            $result.IsValid | Should -Be $false
            $result.Errors.Count | Should -BeGreaterOrEqual 4
        }
        finally {
            Remove-Item $tempFile -ErrorAction SilentlyContinue
        }
    }
}

Describe "Test-FFUConfiguration - ThrowOnError" {
    It "Throws exception when ThrowOnError is set and validation fails" {
        $tempFile = New-TempConfigFile -Config @{
            WindowsSKU = "InvalidSKU"
        }
        try {
            { Test-FFUConfiguration -ConfigPath $tempFile -SchemaPath $script:SchemaPath -ThrowOnError } | Should -Throw "*validation failed*"
        }
        finally {
            Remove-Item $tempFile -ErrorAction SilentlyContinue
        }
    }

    It "Does not throw when ThrowOnError is set and validation succeeds" {
        $tempFile = New-TempConfigFile -Config @{
            WindowsSKU = "Pro"
        }
        try {
            { Test-FFUConfiguration -ConfigPath $tempFile -SchemaPath $script:SchemaPath -ThrowOnError } | Should -Not -Throw
        }
        finally {
            Remove-Item $tempFile -ErrorAction SilentlyContinue
        }
    }
}

Describe "Test-FFUConfiguration - Unknown Properties" {
    It "Reports error for unknown properties (additionalProperties = false)" {
        $tempFile = New-TempConfigFile -Config @{
            WindowsSKU = "Pro"
            UnknownProperty = "test value"
        }
        try {
            $result = Test-FFUConfiguration -ConfigPath $tempFile -SchemaPath $script:SchemaPath
            $result.IsValid | Should -Be $false
            ($result.Errors -join ';') | Should -Match "Unknown property.*UnknownProperty"
        }
        finally {
            Remove-Item $tempFile -ErrorAction SilentlyContinue
        }
    }

    It "Allows metadata properties (`$schema, _comment)" {
        $tempFile = New-TempConfigFile -Config @{
            '$schema' = "./ffubuilder-config.schema.json"
            '_comment' = "Test configuration"
            WindowsSKU = "Pro"
        }
        try {
            $result = Test-FFUConfiguration -ConfigPath $tempFile -SchemaPath $script:SchemaPath
            $result.IsValid | Should -Be $true
        }
        finally {
            Remove-Item $tempFile -ErrorAction SilentlyContinue
        }
    }
}

Describe "Test-FFUConfiguration - Invalid JSON" {
    It "Reports error for invalid JSON syntax" {
        $tempFile = [System.IO.Path]::GetTempFileName()
        $tempFile = [System.IO.Path]::ChangeExtension($tempFile, ".json")
        Set-Content -Path $tempFile -Value '{ "WindowsSKU": "Pro", }'  # Trailing comma is invalid
        try {
            $result = Test-FFUConfiguration -ConfigPath $tempFile -SchemaPath $script:SchemaPath
            $result.IsValid | Should -Be $false
            ($result.Errors -join ';') | Should -Match "(parse|JSON)"
        }
        finally {
            Remove-Item $tempFile -ErrorAction SilentlyContinue
        }
    }
}

Describe "Test-FFUConfiguration - Both Parameter Sets" {
    It "ConfigPath parameter set works" {
        $tempFile = New-TempConfigFile -Config @{ WindowsSKU = "Pro" }
        try {
            $result = Test-FFUConfiguration -ConfigPath $tempFile -SchemaPath $script:SchemaPath
            $result | Should -Not -BeNullOrEmpty
        }
        finally {
            Remove-Item $tempFile -ErrorAction SilentlyContinue
        }
    }

    It "ConfigObject parameter set works" {
        $result = Test-FFUConfiguration -ConfigObject @{ WindowsSKU = "Pro" } -SchemaPath $script:SchemaPath
        $result | Should -Not -BeNullOrEmpty
    }
}

AfterAll {
    # Clean up
    Remove-Module FFU.Core -ErrorAction SilentlyContinue
}
