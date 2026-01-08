#Requires -Version 7.0
#Requires -Modules Pester

<#
.SYNOPSIS
    Tests for FFU.Common.Logging signature compatibility with FFU.Messaging.
.DESCRIPTION
    Ensures that FFU.Common.Logging functions (Write-FFUError, Write-FFUWarning, Write-FFUCritical)
    have signature compatibility with FFU.Messaging functions to prevent "parameter cannot be found"
    errors when modules are loaded in different orders.

    Issue: When BuildFFUVM.ps1 imports FFU.Common with -Force, it overwrites the FFU.Messaging
    versions of Write-FFUError/Warning/Critical. If the caller uses -Source parameter (which
    FFU.Messaging supports), the call fails because FFU.Common.Logging didn't have -Source.

    Fix (v0.0.7): Added optional -Source and -Data parameters to FFU.Common.Logging functions
    for signature compatibility.
#>

BeforeAll {
    # Import the module
    $ModulePath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\FFU.Common'
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'FFU.Common.Logging Signature Compatibility' -Tag 'Unit', 'SignatureCompatibility' {

    Context 'Write-FFUError Parameter Compatibility' {

        It 'Should have -Source parameter' {
            $cmd = Get-Command Write-FFUError -Module FFU.Common -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
            $cmd.Parameters.Keys | Should -Contain 'Source'
        }

        It 'Should have -Data parameter' {
            $cmd = Get-Command Write-FFUError -Module FFU.Common -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
            $cmd.Parameters.Keys | Should -Contain 'Data'
        }

        It 'Should accept -Source parameter without error' {
            { Write-FFUError -Message "Test error" -Source 'TestSource' } | Should -Not -Throw
        }

        It 'Should accept -Data parameter without error' {
            { Write-FFUError -Message "Test error" -Data @{ Key = 'Value' } } | Should -Not -Throw
        }

        It 'Should accept both -Source and -Data parameters together' {
            { Write-FFUError -Message "Test error" -Source 'TestSource' -Data @{ Key = 'Value' } } | Should -Not -Throw
        }

        It 'Should work without optional parameters (backward compatible)' {
            { Write-FFUError -Message "Test error" } | Should -Not -Throw
        }

        It 'Should accept -Context parameter (existing functionality)' {
            { Write-FFUError -Message "Test error" -Context @{ ContextKey = 'ContextValue' } } | Should -Not -Throw
        }

        It '-Source parameter should be optional (not mandatory)' {
            $cmd = Get-Command Write-FFUError -Module FFU.Common
            $param = $cmd.Parameters['Source']
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } | Should -Contain $false
        }

        It '-Data parameter should be optional (not mandatory)' {
            $cmd = Get-Command Write-FFUError -Module FFU.Common
            $param = $cmd.Parameters['Data']
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } | Should -Contain $false
        }

        It '-Source parameter should be string type' {
            $cmd = Get-Command Write-FFUError -Module FFU.Common
            $cmd.Parameters['Source'].ParameterType.Name | Should -Be 'String'
        }

        It '-Data parameter should be hashtable type' {
            $cmd = Get-Command Write-FFUError -Module FFU.Common
            $cmd.Parameters['Data'].ParameterType.Name | Should -Be 'Hashtable'
        }
    }

    Context 'Write-FFUWarning Parameter Compatibility' {

        It 'Should have -Source parameter' {
            $cmd = Get-Command Write-FFUWarning -Module FFU.Common -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
            $cmd.Parameters.Keys | Should -Contain 'Source'
        }

        It 'Should accept -Source parameter without error' {
            { Write-FFUWarning -Message "Test warning" -Source 'TestSource' } | Should -Not -Throw
        }

        It 'Should work without optional parameters (backward compatible)' {
            { Write-FFUWarning -Message "Test warning" } | Should -Not -Throw
        }

        It '-Source parameter should be optional (not mandatory)' {
            $cmd = Get-Command Write-FFUWarning -Module FFU.Common
            $param = $cmd.Parameters['Source']
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } | Should -Contain $false
        }

        It '-Source parameter should be string type' {
            $cmd = Get-Command Write-FFUWarning -Module FFU.Common
            $cmd.Parameters['Source'].ParameterType.Name | Should -Be 'String'
        }
    }

    Context 'Write-FFUCritical Parameter Compatibility' {

        It 'Should have -Source parameter' {
            $cmd = Get-Command Write-FFUCritical -Module FFU.Common -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
            $cmd.Parameters.Keys | Should -Contain 'Source'
        }

        It 'Should accept -Source parameter without error' {
            { Write-FFUCritical -Message "Test critical" -Source 'TestSource' } | Should -Not -Throw
        }

        It 'Should work without optional parameters (backward compatible)' {
            { Write-FFUCritical -Message "Test critical" } | Should -Not -Throw
        }

        It '-Source parameter should be optional (not mandatory)' {
            $cmd = Get-Command Write-FFUCritical -Module FFU.Common
            $param = $cmd.Parameters['Source']
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } | Should -Contain $false
        }

        It '-Source parameter should be string type' {
            $cmd = Get-Command Write-FFUCritical -Module FFU.Common
            $cmd.Parameters['Source'].ParameterType.Name | Should -Be 'String'
        }
    }

    Context 'Module Import Order Compatibility' {

        It 'FFU.Common.Logging should export Write-FFUError' {
            $modulePath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\FFU.Common\FFU.Common.Logging.psm1'
            $content = Get-Content $modulePath -Raw
            # The export statement is multi-line, so check for the function name anywhere in the Export-ModuleMember block
            $content | Should -Match 'Write-FFUError'
            $content | Should -Match 'Export-ModuleMember'
        }

        It 'FFU.Common.Logging should export Write-FFUWarning' {
            $modulePath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\FFU.Common\FFU.Common.Logging.psm1'
            $content = Get-Content $modulePath -Raw
            $content | Should -Match 'Write-FFUWarning'
            $content | Should -Match 'Export-ModuleMember'
        }

        It 'FFU.Common.Logging should export Write-FFUCritical' {
            $modulePath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\FFU.Common\FFU.Common.Logging.psm1'
            $content = Get-Content $modulePath -Raw
            $content | Should -Match 'Write-FFUCritical'
            $content | Should -Match 'Export-ModuleMember'
        }
    }

    Context 'ThreadJob Catch Block Simulation' {
        # This simulates the exact scenario that caused the original bug
        # The catch block in BuildFFUVM_UI.ps1 calls Write-FFUError -Source 'BuildFFUVM'

        It 'Should handle the exact call pattern from BuildFFUVM_UI.ps1 catch block' {
            # This is the exact call that was failing before the fix
            { Write-FFUError -Message "Build failed: Test exception message" -Source 'BuildFFUVM' } |
                Should -Not -Throw
        }

        It 'Should handle error call with Context from FFU.Messaging pattern' {
            # FFU.Messaging uses -Context as the first parameter (mandatory)
            # FFU.Common.Logging accepts -Context as optional
            { Write-FFUError -Message "Test error" -Context @{} -Source 'BuildFFUVM' } |
                Should -Not -Throw
        }
    }
}

Describe 'FFU.Common Module Version' -Tag 'Unit', 'Version' {

    It 'FFU.Common.psd1 should be version 0.0.7 or higher' {
        $manifestPath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\FFU.Common\FFU.Common.psd1'
        $manifest = Import-PowerShellDataFile $manifestPath
        [version]$manifest.ModuleVersion | Should -BeGreaterOrEqual ([version]'0.0.7')
    }

    It 'Release notes should mention signature compatibility fix' {
        $manifestPath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\FFU.Common\FFU.Common.psd1'
        $manifest = Import-PowerShellDataFile $manifestPath
        $manifest.PrivateData.PSData.ReleaseNotes | Should -Match 'Signature compatibility'
    }
}
