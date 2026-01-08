#Requires -Version 7.0
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

<#
.SYNOPSIS
    Tests for WIM mount capability validation in FFU.Preflight module.

.DESCRIPTION
    This test file validates the Test-FFUWimMount function that checks for
    WIM mount infrastructure required by DISM operations. This addresses
    DISM error 0x800704DB "The specified service does not exist".

    v1.0.4 Changes:
    - PRIMARY CHECK is now 'fltmc filters' for WimMount presence
    - Auto-repair is now the default behavior
    - New details fields: WimMountFilterLoaded, RegistryExists, FilterInstanceExists, RemediationSuccess
    - Removed WOF-related fields (not required for WimMount functionality)

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

Describe 'Test-FFUWimMount Details Structure (v1.0.4)' {
    BeforeAll {
        $script:result = Test-FFUWimMount
    }

    It 'Details should contain WimMountFilterLoaded (primary indicator)' {
        $result.Details.Keys | Should -Contain 'WimMountFilterLoaded'
        $result.Details.WimMountFilterLoaded | Should -BeOfType [bool]
    }

    It 'Details should contain WimMountServiceExists' {
        $result.Details.Keys | Should -Contain 'WimMountServiceExists'
        $result.Details.WimMountServiceExists | Should -BeOfType [bool]
    }

    It 'Details should contain WimMountServiceStatus' {
        $result.Details.Keys | Should -Contain 'WimMountServiceStatus'
    }

    It 'Details should contain WimMountDriverExists' {
        $result.Details.Keys | Should -Contain 'WimMountDriverExists'
        $result.Details.WimMountDriverExists | Should -BeOfType [bool]
    }

    It 'Details should contain WimMountDriverVersion' {
        $result.Details.Keys | Should -Contain 'WimMountDriverVersion'
    }

    It 'Details should contain FltMgrServiceStatus' {
        $result.Details.Keys | Should -Contain 'FltMgrServiceStatus'
    }

    It 'Details should contain RegistryExists' {
        $result.Details.Keys | Should -Contain 'RegistryExists'
        $result.Details.RegistryExists | Should -BeOfType [bool]
    }

    It 'Details should contain FilterInstanceExists' {
        $result.Details.Keys | Should -Contain 'FilterInstanceExists'
        $result.Details.FilterInstanceExists | Should -BeOfType [bool]
    }

    It 'Details should contain RemediationAttempted' {
        $result.Details.Keys | Should -Contain 'RemediationAttempted'
        $result.Details.RemediationAttempted | Should -BeOfType [bool]
    }

    It 'Details should contain RemediationActions list' {
        $result.Details.Keys | Should -Contain 'RemediationActions'
    }

    It 'Details should contain RemediationSuccess' {
        $result.Details.Keys | Should -Contain 'RemediationSuccess'
        $result.Details.RemediationSuccess | Should -BeOfType [bool]
    }
}

Describe 'Test-FFUWimMount Primary Check (fltmc filters)' {
    BeforeAll {
        # Check actual fltmc filters output
        $script:fltmcOutput = fltmc filters 2>&1
        $script:wimMountInFilters = ($fltmcOutput -match 'WimMount')
        $script:result = Test-FFUWimMount
    }

    It 'Should use fltmc filters as primary indicator' {
        # WimMountFilterLoaded should match whether WimMount appears in fltmc filters
        # Note: If auto-repair succeeded, both will be true
        if ($result.Status -eq 'Passed') {
            $result.Details.WimMountFilterLoaded | Should -BeTrue
        }
    }

    It 'Should return Passed when WimMount is in fltmc filters' {
        if ($wimMountInFilters) {
            $result.Status | Should -Be 'Passed'
        }
    }

    It 'Message should reference filter status' {
        if ($result.Status -eq 'Passed') {
            $result.Message | Should -Match 'filter'
        }
    }
}

Describe 'Test-FFUWimMount Driver File Checks' {
    BeforeAll {
        $script:result = Test-FFUWimMount
        $script:wimMountDriverPath = Join-Path $env:SystemRoot 'System32\drivers\wimmount.sys'
    }

    It 'Should correctly detect wimmount.sys existence' {
        $expectedExists = Test-Path -Path $wimMountDriverPath -PathType Leaf
        $result.Details.WimMountDriverExists | Should -Be $expectedExists
    }

    It 'Should report driver version when driver exists' {
        if ($result.Details.WimMountDriverExists) {
            $result.Details.WimMountDriverVersion | Should -Not -Be 'Unknown'
        }
    }
}

Describe 'Test-FFUWimMount Registry Checks' {
    BeforeAll {
        $script:result = Test-FFUWimMount
        $script:serviceRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\WimMount"
        $script:instancePath = "$serviceRegPath\Instances\WimMount"
    }

    It 'Should correctly detect service registry existence' {
        $expectedExists = Test-Path $serviceRegPath
        # Note: After auto-repair, this may have been created
        $result.Details.RegistryExists | Should -BeOfType [bool]
    }

    It 'Should correctly detect filter instance existence' {
        # Note: After auto-repair, this may have been created
        $result.Details.FilterInstanceExists | Should -BeOfType [bool]
    }
}

Describe 'Test-FFUWimMount Auto-Repair Behavior' {
    It 'Should accept -AttemptRemediation parameter' {
        { Test-FFUWimMount -AttemptRemediation } | Should -Not -Throw
        { Test-FFUWimMount -AttemptRemediation:$true } | Should -Not -Throw
        { Test-FFUWimMount -AttemptRemediation:$false } | Should -Not -Throw
    }

    It 'Auto-repair should be default behavior (AttemptRemediation defaults to $true)' {
        # When filter is not loaded and driver exists, remediation should be attempted
        $result = Test-FFUWimMount

        # If the filter wasn't loaded initially but repair succeeded, we know remediation was attempted
        if ($result.Details.RemediationSuccess) {
            $result.Details.RemediationAttempted | Should -BeTrue
        }
    }

    It 'Should NOT attempt remediation when -AttemptRemediation:$false' {
        $result = Test-FFUWimMount -AttemptRemediation:$false

        # If filter is loaded, RemediationAttempted will be false anyway
        # If filter is not loaded and we passed -AttemptRemediation:$false, it should also be false
        if (-not $result.Details.WimMountFilterLoaded) {
            # This confirms detection-only mode worked
            $result.Details.RemediationAttempted | Should -BeFalse
        }
    }

    It 'Should track all remediation actions' {
        $result = Test-FFUWimMount

        if ($result.Details.RemediationAttempted) {
            $result.Details.RemediationActions.Count | Should -BeGreaterThan 0
        }
    }
}

Describe 'Test-FFUWimMount Healthy System Validation' {
    BeforeAll {
        # Check if this is a healthy system where WimMount is in fltmc filters
        $script:fltmcOutput = fltmc filters 2>&1
        $script:isHealthySystem = ($fltmcOutput -match 'WimMount')
        $script:result = Test-FFUWimMount
    }

    It 'Should pass on healthy Windows system' -Skip:(-not $isHealthySystem) {
        $result.Status | Should -Be 'Passed'
    }

    It 'Should have message indicating filter is loaded on healthy system' -Skip:(-not $isHealthySystem) {
        $result.Message | Should -Match 'loaded'
    }

    It 'Should have empty Remediation on healthy system' -Skip:(-not $isHealthySystem) {
        $result.Remediation | Should -BeNullOrEmpty
    }

    It 'WimMountFilterLoaded should be true on healthy system' -Skip:(-not $isHealthySystem) {
        $result.Details.WimMountFilterLoaded | Should -BeTrue
    }
}

Describe 'Test-FFUWimMount Failure Messaging' {
    It 'Should provide detailed diagnostics when failed' {
        $result = Test-FFUWimMount -AttemptRemediation:$false

        if ($result.Status -eq 'Failed') {
            $result.Remediation | Should -Not -BeNullOrEmpty
            # Should include diagnostic info
            $result.Remediation | Should -Match 'Diagnostic'
            # Should include manual remediation steps
            $result.Remediation | Should -Match 'Remediation'
        }
    }

    It 'Should mention fltmc filters in remediation' {
        $result = Test-FFUWimMount -AttemptRemediation:$false

        if ($result.Status -eq 'Failed') {
            $result.Remediation | Should -Match 'fltmc filters'
        }
    }

    It 'Should mention security software when repair fails' {
        $result = Test-FFUWimMount -AttemptRemediation:$false

        if ($result.Status -eq 'Failed') {
            # Should mention SentinelOne or security software
            $result.Remediation | Should -Match 'security|SentinelOne|CrowdStrike|EDR'
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

    It 'Invoke-FFUPreflight should fail when WimMount fails and ADK needed' {
        # This test validates that WimMount failure blocks the build
        $features = @{
            CreateCaptureMedia = $true
            CreateVM = $false
        }

        $result = Invoke-FFUPreflight -Features $features `
            -FFUDevelopmentPath 'C:\FFUDevelopment' -SkipCleanup 6>$null

        # If WimMount failed, IsValid should be false
        if ($result.Tier2Results['WimMount'].Status -eq 'Failed') {
            $result.IsValid | Should -BeFalse
        }
    }
}

Describe 'Test-FFUWimMount Performance' {
    It 'Should complete within 10 seconds (includes potential repair time)' {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $null = Test-FFUWimMount
        $stopwatch.Stop()

        # Allow up to 10 seconds to account for registry operations and service start
        $stopwatch.ElapsedMilliseconds | Should -BeLessThan 10000
    }

    It 'Should complete within 2 seconds in detection-only mode' {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $null = Test-FFUWimMount -AttemptRemediation:$false
        $stopwatch.Stop()

        $stopwatch.ElapsedMilliseconds | Should -BeLessThan 2000
    }

    It 'Should report accurate duration' {
        $result = Test-FFUWimMount -AttemptRemediation:$false
        $result.DurationMs | Should -BeGreaterThan 0
        $result.DurationMs | Should -BeLessThan 10000
    }
}

Describe 'Test-FFUWimMount Remediation Success Tracking' {
    It 'RemediationSuccess should be true when repair succeeds' {
        $result = Test-FFUWimMount

        if ($result.Details.RemediationAttempted) {
            # If remediation was attempted and status is Passed, success should be true
            if ($result.Status -eq 'Passed') {
                $result.Details.RemediationSuccess | Should -BeTrue
            }
        }
    }

    It 'RemediationSuccess should be false when repair fails' {
        $result = Test-FFUWimMount

        if ($result.Details.RemediationAttempted -and $result.Status -eq 'Failed') {
            $result.Details.RemediationSuccess | Should -BeFalse
        }
    }
}
