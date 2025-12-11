#Requires -Version 7.0
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

<#
.SYNOPSIS
    Tests for WIM mount capability validation in FFU.Preflight module.

.DESCRIPTION
    This test file validates the Test-FFUWimMount function that checks for
    WIM mount infrastructure required by DISM operations. This addresses
    DISM error 0x800704DB "The specified service does not exist".

.NOTES
    Created as part of fix for DISM WIM mount failure during WinPE creation.
    Error: "Failed to mount the WIM file" with error 0x800704DB
#>

BeforeAll {
    # Get paths
    $script:FFUDevelopmentPath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ModulesPath = Join-Path $FFUDevelopmentPath 'FFUDevelopment\Modules'

    # Add modules folder to PSModulePath if not present
    if ($env:PSModulePath -notlike "*$ModulesPath*") {
        $env:PSModulePath = "$ModulesPath;$env:PSModulePath"
    }

    # Import the FFU.Preflight module
    Import-Module (Join-Path $ModulesPath 'FFU.Preflight\FFU.Preflight.psd1') -Force -ErrorAction Stop
}

Describe 'Test-FFUWimMount Function Existence' {
    It 'Test-FFUWimMount function should exist' {
        Get-Command -Name 'Test-FFUWimMount' -Module 'FFU.Preflight' | Should -Not -BeNullOrEmpty
    }

    It 'Test-FFUWimMount should be exported from module' {
        $module = Get-Module -Name 'FFU.Preflight'
        $module.ExportedFunctions.Keys | Should -Contain 'Test-FFUWimMount'
    }
}

Describe 'Test-FFUWimMount Return Structure' {
    BeforeAll {
        $script:result = Test-FFUWimMount
    }

    It 'Should return a PSCustomObject' {
        $result | Should -BeOfType [PSCustomObject]
    }

    It 'Should have CheckName property' {
        $result.CheckName | Should -Not -BeNullOrEmpty
        $result.CheckName | Should -Be 'WimMount'
    }

    It 'Should have Status property' {
        $result.Status | Should -Not -BeNullOrEmpty
        $result.Status | Should -BeIn @('Passed', 'Failed', 'Warning', 'Skipped')
    }

    It 'Should have Message property' {
        $result.Message | Should -Not -BeNullOrEmpty
    }

    It 'Should have Details property as hashtable' {
        $result.Details | Should -BeOfType [hashtable]
    }

    It 'Should have DurationMs property' {
        $result.DurationMs | Should -BeOfType [int]
        $result.DurationMs | Should -BeGreaterOrEqual 0
    }
}

Describe 'Test-FFUWimMount Details Structure' {
    BeforeAll {
        $script:result = Test-FFUWimMount
    }

    It 'Details should contain WimMountServiceExists' {
        $result.Details.Keys | Should -Contain 'WimMountServiceExists'
        $result.Details.WimMountServiceExists | Should -BeOfType [bool]
    }

    It 'Details should contain WimMountServiceStatus' {
        $result.Details.Keys | Should -Contain 'WimMountServiceStatus'
    }

    It 'Details should contain WofServiceExists' {
        $result.Details.Keys | Should -Contain 'WofServiceExists'
        $result.Details.WofServiceExists | Should -BeOfType [bool]
    }

    It 'Details should contain WimMountDriverExists' {
        $result.Details.Keys | Should -Contain 'WimMountDriverExists'
        $result.Details.WimMountDriverExists | Should -BeOfType [bool]
    }

    It 'Details should contain WofDriverExists' {
        $result.Details.Keys | Should -Contain 'WofDriverExists'
        $result.Details.WofDriverExists | Should -BeOfType [bool]
    }

    It 'Details should contain FltMgrServiceStatus' {
        $result.Details.Keys | Should -Contain 'FltMgrServiceStatus'
    }

    It 'Details should contain RemediationAttempted' {
        $result.Details.Keys | Should -Contain 'RemediationAttempted'
        $result.Details.RemediationAttempted | Should -BeOfType [bool]
    }

    It 'Details should contain RemediationActions list' {
        $result.Details.Keys | Should -Contain 'RemediationActions'
    }
}

Describe 'Test-FFUWimMount Service Checks' {
    BeforeAll {
        $script:result = Test-FFUWimMount
    }

    It 'Should detect WIMMount service if it exists' {
        # On a healthy Windows system, WIMMount service should exist
        $wimMountService = Get-Service -Name 'WIMMount' -ErrorAction SilentlyContinue
        if ($wimMountService) {
            $result.Details.WimMountServiceExists | Should -BeTrue
        }
        else {
            $result.Details.WimMountServiceExists | Should -BeFalse
        }
    }

    It 'Should detect Filter Manager service status' {
        $fltMgrService = Get-Service -Name 'FltMgr' -ErrorAction SilentlyContinue
        if ($fltMgrService) {
            $result.Details.FltMgrServiceStatus | Should -Be $fltMgrService.Status.ToString()
        }
    }
}

Describe 'Test-FFUWimMount Driver File Checks' {
    BeforeAll {
        $script:result = Test-FFUWimMount
        $script:wimMountDriverPath = Join-Path $env:SystemRoot 'System32\drivers\wimmount.sys'
        $script:wofDriverPath = Join-Path $env:SystemRoot 'System32\drivers\wof.sys'
    }

    It 'Should correctly detect wimmount.sys existence' {
        $expectedExists = Test-Path -Path $wimMountDriverPath -PathType Leaf
        $result.Details.WimMountDriverExists | Should -Be $expectedExists
    }

    It 'Should correctly detect wof.sys existence' {
        $expectedExists = Test-Path -Path $wofDriverPath -PathType Leaf
        $result.Details.WofDriverExists | Should -Be $expectedExists
    }
}

Describe 'Test-FFUWimMount with AttemptRemediation' {
    It 'Should accept -AttemptRemediation switch' {
        { Test-FFUWimMount -AttemptRemediation } | Should -Not -Throw
    }

    It 'Should set RemediationAttempted when errors exist and remediation requested' {
        # This test validates the parameter is accepted - actual remediation
        # depends on system state and may or may not occur
        $result = Test-FFUWimMount -AttemptRemediation

        # RemediationAttempted should be true only if there were errors to remediate
        # If system is healthy, RemediationAttempted will be false
        $result.Details.RemediationAttempted | Should -BeOfType [bool]
    }
}

Describe 'Test-FFUWimMount Healthy System Validation' {
    # These tests validate behavior on a healthy Windows system
    # They will pass on most properly configured Windows 10/11 systems

    BeforeAll {
        $script:result = Test-FFUWimMount
        $script:isHealthySystem = (
            (Get-Service -Name 'WIMMount' -ErrorAction SilentlyContinue) -and
            (Get-Service -Name 'FltMgr' -ErrorAction SilentlyContinue) -and
            (Test-Path (Join-Path $env:SystemRoot 'System32\drivers\wimmount.sys'))
        )
    }

    It 'Should pass on healthy Windows system' -Skip:(-not $isHealthySystem) {
        $result.Status | Should -Be 'Passed'
    }

    It 'Should have positive message on healthy system' -Skip:(-not $isHealthySystem) {
        $result.Message | Should -Match 'available'
    }

    It 'Should have empty Remediation on healthy system' -Skip:(-not $isHealthySystem) {
        $result.Remediation | Should -BeNullOrEmpty
    }
}

Describe 'Test-FFUWimMount Error Messaging' {
    It 'Should provide remediation steps when failed' {
        # Get fresh result
        $result = Test-FFUWimMount

        if ($result.Status -eq 'Failed') {
            $result.Remediation | Should -Not -BeNullOrEmpty
            $result.Remediation | Should -Match 'rundll32'
            $result.Remediation | Should -Match 'WimMountDriver'
        }
    }

    It 'Should mention error code 0x800704DB in remediation' {
        $result = Test-FFUWimMount

        if ($result.Status -eq 'Failed') {
            $result.Remediation | Should -Match '0x800704DB'
        }
    }
}

Describe 'Test-FFUWimMount Integration with Invoke-FFUPreflight' {
    It 'Invoke-FFUPreflight should include WimMount check when ADK needed' {
        $features = @{
            CreateCaptureMedia = $true
            CreateVM = $false
        }

        # Run preflight with ADK-requiring features
        $result = Invoke-FFUPreflight -Features $features `
            -FFUDevelopmentPath 'C:\FFUDevelopment' -SkipCleanup 6>$null

        # Should have WimMount in Tier2Results
        $result.Tier2Results.Keys | Should -Contain 'WimMount'
    }

    It 'Invoke-FFUPreflight should skip WimMount check when ADK not needed' {
        $features = @{
            CreateCaptureMedia = $false
            CreateDeploymentMedia = $false
            OptimizeFFU = $false
            CreateVM = $false
        }

        # Run preflight without ADK-requiring features
        $result = Invoke-FFUPreflight -Features $features `
            -FFUDevelopmentPath 'C:\FFUDevelopment' -SkipCleanup 6>$null

        # WimMount should be skipped
        $result.Tier2Results['WimMount'].Status | Should -Be 'Skipped'
    }
}

Describe 'Test-FFUWimMount Performance' {
    It 'Should complete within 5 seconds' {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $null = Test-FFUWimMount
        $stopwatch.Stop()

        $stopwatch.ElapsedMilliseconds | Should -BeLessThan 5000
    }

    It 'Should report accurate duration' {
        $result = Test-FFUWimMount
        $result.DurationMs | Should -BeGreaterThan 0
        $result.DurationMs | Should -BeLessThan 10000
    }
}
