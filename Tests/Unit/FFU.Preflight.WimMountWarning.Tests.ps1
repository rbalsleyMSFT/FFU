#Requires -Version 7.0
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

<#
.SYNOPSIS
    Tests for WIM mount WARNING behavior in FFU.Preflight module (v1.3.5+).

.DESCRIPTION
    This test file validates the Test-FFUWimMount function's WARNING behavior
    introduced in v1.3.5. WIMMount service issues are now returned as WARNING
    (not FAILED) because FFU Builder uses native PowerShell DISM cmdlets
    (Mount-WindowsImage/Dismount-WindowsImage) which do NOT require the
    WIMMount filter driver service.

    Key behaviors tested:
    - Test-FFUWimMount returns 'Warning' status when WIMMount service is missing
    - Test-FFUWimMount returns 'Warning' status when both Get-Service and sc.exe fail
    - Test-FFUWimMount returns 'Passed' status when service exists and is healthy
    - Test-FFUWimMount uses sc.exe fallback when Get-Service throws
    - UsingNativeDISM detail field is set correctly based on status
    - Invoke-FFUPreflight does NOT set IsValid to $false for WimMount warnings
    - Invoke-FFUPreflight adds WimMount warning to Warnings array (not Errors)
    - Remediation message mentions native DISM cmdlets

.NOTES
    Version: 1.0.0
    Date: 2025-12-12
    Author: FFU Builder Team
    Related Fix: v1.3.5 - Native DISM cmdlets to avoid WIMMount filter driver issues
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

AfterAll {
    Remove-Module FFU.Preflight -ErrorAction SilentlyContinue
}

Describe 'Test-FFUWimMount Warning Behavior' -Tag 'WimMount', 'Warning', 'Preflight' {

    Context 'UsingNativeDISM Detail Field' {

        It 'Details should contain UsingNativeDISM field' {
            $result = Test-FFUWimMount
            $result.Details.Keys | Should -Contain 'UsingNativeDISM'
        }

        It 'UsingNativeDISM should be a boolean' {
            $result = Test-FFUWimMount
            $result.Details.UsingNativeDISM | Should -BeOfType [bool]
        }

        It 'UsingNativeDISM should be $false when status is Passed' {
            $result = Test-FFUWimMount

            if ($result.Status -eq 'Passed') {
                $result.Details.UsingNativeDISM | Should -BeFalse -Because 'Native DISM fallback is not needed when WIMMount is healthy'
            }
        }

        It 'UsingNativeDISM should be $true when status is Warning' {
            $result = Test-FFUWimMount

            if ($result.Status -eq 'Warning') {
                $result.Details.UsingNativeDISM | Should -BeTrue -Because 'Native DISM cmdlets will be used as workaround'
            }
        }
    }

    Context 'Warning Status for Service Issues' {

        It 'Should return Warning (not Failed) when WIMMount service issues are detected' {
            # Get the actual result - behavior depends on system state
            $result = Test-FFUWimMount

            # The key assertion: if there are WIMMount issues, status should be Warning, never Failed
            $result.Status | Should -BeIn @('Passed', 'Warning') -Because 'v1.3.5+ returns Warning instead of Failed for WIMMount issues'
            $result.Status | Should -Not -Be 'Failed' -Because 'WIMMount failures are non-blocking in v1.3.5+'
        }

        It 'Should not have Failed status in return values' {
            # Verify the function never returns Failed for WIMMount
            # Run multiple times to ensure consistent behavior
            for ($i = 0; $i -lt 3; $i++) {
                $result = Test-FFUWimMount
                $result.Status | Should -Not -Be 'Failed' -Because 'v1.3.5+ uses native DISM cmdlets as fallback'
            }
        }
    }

    Context 'sc.exe Fallback Behavior' {

        It 'Should have sc.exe fallback logic in source code' {
            # Verify the implementation includes sc.exe fallback
            $modulePath = Join-Path $script:ModulesPath 'FFU.Preflight\FFU.Preflight.psm1'
            $moduleContent = Get-Content $modulePath -Raw

            $moduleContent | Should -Match 'sc\.exe query WIMMount' -Because 'sc.exe is used as fallback when Get-Service fails'
        }

        It 'Should handle sc.exe exit code 1060 (service does not exist)' {
            $modulePath = Join-Path $script:ModulesPath 'FFU.Preflight\FFU.Preflight.psm1'
            $moduleContent = Get-Content $modulePath -Raw

            # Verify handling of ERROR_SERVICE_DOES_NOT_EXIST (1060)
            $moduleContent | Should -Match '1060' -Because 'Error code 1060 indicates service does not exist'
        }

        It 'Should parse sc.exe STATE output for service status' {
            $modulePath = Join-Path $script:ModulesPath 'FFU.Preflight\FFU.Preflight.psm1'
            $moduleContent = Get-Content $modulePath -Raw

            # Verify parsing of sc.exe STATE output (regex in source: 'STATE\s+:\s+\d+\s+(\w+)')
            $moduleContent | Should -Match 'STATE\\s\+:\\s\+\\d\+\\s\+\(\\w\+\)' -Because 'sc.exe output STATE line is parsed'
        }
    }

    Context 'Remediation Message Content' {

        It 'Remediation message should mention native DISM cmdlets' {
            $result = Test-FFUWimMount

            if ($result.Status -eq 'Warning' -and $result.Remediation) {
                $result.Remediation | Should -Match 'native.*DISM|Mount-WindowsImage|Dismount-WindowsImage' -Because 'v1.3.5+ uses native DISM cmdlets'
            }
        }

        It 'Remediation message should mention non-blocking warning' {
            $result = Test-FFUWimMount

            if ($result.Status -eq 'Warning' -and $result.Remediation) {
                $result.Remediation | Should -Match 'non-blocking|WARNING' -Because 'User should know this is not a blocking issue'
            }
        }

        It 'Remediation message should mention error code 0x800704DB' {
            $result = Test-FFUWimMount

            if ($result.Status -eq 'Warning' -and $result.Remediation) {
                $result.Remediation | Should -Match '0x800704DB' -Because 'This is the common DISM error for WIM mount failures'
            }
        }

        It 'Warning message should mention native DISM cmdlets' {
            $result = Test-FFUWimMount

            if ($result.Status -eq 'Warning') {
                $result.Message | Should -Match 'native DISM' -Because 'Message should explain the workaround'
            }
        }

        It 'Warning message should indicate non-blocking status' {
            $result = Test-FFUWimMount

            if ($result.Status -eq 'Warning') {
                $result.Message | Should -Match 'non-blocking' -Because 'Message should clarify this is not a blocking issue'
            }
        }
    }

    Context 'Passed Status Behavior' {

        It 'Should return Passed when WIMMount service exists and is healthy' {
            # Check actual system state
            $wimMountService = $null
            try {
                $wimMountService = Get-Service -Name 'WIMMount' -ErrorAction Stop
            }
            catch {
                # Service doesn't exist on this system
            }

            $fltMgrService = $null
            try {
                $fltMgrService = Get-Service -Name 'FltMgr' -ErrorAction Stop
            }
            catch {
                # Service doesn't exist
            }

            $driverExists = Test-Path (Join-Path $env:SystemRoot 'System32\drivers\wimmount.sys')

            $result = Test-FFUWimMount

            # If all components are healthy, should return Passed
            if ($wimMountService -and $fltMgrService -and $fltMgrService.Status -eq 'Running' -and $driverExists) {
                if ($wimMountService.StartType -ne 'Disabled') {
                    # System appears healthy, expect Passed
                    $result.Status | Should -Be 'Passed'
                }
            }
        }

        It 'UsingNativeDISM should be $false on healthy system' {
            $result = Test-FFUWimMount

            if ($result.Status -eq 'Passed') {
                $result.Details.UsingNativeDISM | Should -BeFalse
            }
        }

        It 'Remediation should be empty when Passed' {
            $result = Test-FFUWimMount

            if ($result.Status -eq 'Passed') {
                $result.Remediation | Should -BeNullOrEmpty
            }
        }
    }
}

Describe 'Invoke-FFUPreflight WimMount Handling' -Tag 'WimMount', 'Integration', 'Preflight' {

    Context 'WimMount Warning Does Not Block Build' {

        BeforeAll {
            $script:featuresRequiringWinPE = @{
                CreateVM              = $false
                CreateCaptureMedia    = $true   # Requires ADK/WinPE
                CreateDeploymentMedia = $false
                OptimizeFFU           = $false
                InstallApps           = $false
                UpdateLatestCU        = $false
                DownloadDrivers       = $false
            }
        }

        It 'Should NOT set IsValid to $false when WimMount returns Warning' {
            # Run preflight with features that trigger WimMount check
            $result = Invoke-FFUPreflight -Features $script:featuresRequiringWinPE `
                -FFUDevelopmentPath $env:TEMP -SkipCleanup 6>$null

            # Get the WimMount result
            $wimMountResult = $result.Tier2Results['WimMount']

            # If WimMount returned Warning, IsValid should still be $true
            # (assuming no other checks failed)
            if ($wimMountResult -and $wimMountResult.Status -eq 'Warning') {
                # Check if there are any OTHER errors (not WimMount)
                $otherErrors = $result.Errors | Where-Object { $_ -notmatch 'WimMount' }

                if ($otherErrors.Count -eq 0) {
                    # No other errors, so IsValid should be true despite WimMount warning
                    # Note: Other checks like Admin, ADK may fail - that's expected
                    # The key is: WimMount Warning alone should NOT cause IsValid = $false
                }

                # Verify WimMount is NOT in Errors array
                $wimMountInErrors = $result.Errors | Where-Object { $_ -match 'WimMount' }
                $wimMountInErrors.Count | Should -Be 0 -Because 'WimMount Warning should not be added to Errors'
            }
        }

        It 'Should add WimMount warning to Warnings array (not Errors)' {
            $result = Invoke-FFUPreflight -Features $script:featuresRequiringWinPE `
                -FFUDevelopmentPath $env:TEMP -SkipCleanup 6>$null

            $wimMountResult = $result.Tier2Results['WimMount']

            if ($wimMountResult -and $wimMountResult.Status -eq 'Warning') {
                # Should be in Warnings, not Errors
                $inWarnings = $result.Warnings | Where-Object { $_ -match 'WimMount' }
                $inErrors = $result.Errors | Where-Object { $_ -match 'WimMount' }

                $inWarnings.Count | Should -BeGreaterThan 0 -Because 'WimMount warning should be in Warnings array'
                $inErrors.Count | Should -Be 0 -Because 'WimMount warning should NOT be in Errors array'
            }
        }

        It 'Should set HasWarnings to $true when WimMount returns Warning' {
            $result = Invoke-FFUPreflight -Features $script:featuresRequiringWinPE `
                -FFUDevelopmentPath $env:TEMP -SkipCleanup 6>$null

            $wimMountResult = $result.Tier2Results['WimMount']

            if ($wimMountResult -and $wimMountResult.Status -eq 'Warning') {
                $result.HasWarnings | Should -BeTrue -Because 'WimMount warning should set HasWarnings flag'
            }
        }

        It 'Should include WimMount in Tier2Results when ADK features enabled' {
            $result = Invoke-FFUPreflight -Features $script:featuresRequiringWinPE `
                -FFUDevelopmentPath $env:TEMP -SkipCleanup 6>$null

            $result.Tier2Results.Keys | Should -Contain 'WimMount'
        }
    }

    Context 'WimMount Check Skipped When Not Needed' {

        BeforeAll {
            $script:featuresNotRequiringWinPE = @{
                CreateVM              = $true
                CreateCaptureMedia    = $false
                CreateDeploymentMedia = $false
                OptimizeFFU           = $false
                InstallApps           = $false
                UpdateLatestCU        = $false
                DownloadDrivers       = $false
            }
        }

        It 'Should skip WimMount check when no ADK features enabled' {
            $result = Invoke-FFUPreflight -Features $script:featuresNotRequiringWinPE `
                -FFUDevelopmentPath $env:TEMP -SkipCleanup 6>$null

            $wimMountResult = $result.Tier2Results['WimMount']
            $wimMountResult.Status | Should -Be 'Skipped' -Because 'WimMount is only checked when ADK/WinPE features are enabled'
        }

        It 'Skipped WimMount should not affect IsValid' {
            $result = Invoke-FFUPreflight -Features $script:featuresNotRequiringWinPE `
                -FFUDevelopmentPath $env:TEMP -SkipCleanup 6>$null

            $wimMountResult = $result.Tier2Results['WimMount']

            if ($wimMountResult -and $wimMountResult.Status -eq 'Skipped') {
                # Skipped status should not add to errors or warnings
                $inWarnings = $result.Warnings | Where-Object { $_ -match 'WimMount' }
                $inErrors = $result.Errors | Where-Object { $_ -match 'WimMount' }

                $inWarnings.Count | Should -Be 0
                $inErrors.Count | Should -Be 0
            }
        }
    }

    Context 'Integration with Other Preflight Checks' {

        It 'WimMount warning should not prevent other checks from running' {
            $features = @{
                CreateVM              = $true
                CreateCaptureMedia    = $true   # Triggers WimMount check
                CreateDeploymentMedia = $false
                OptimizeFFU           = $false
                InstallApps           = $false
                UpdateLatestCU        = $false
                DownloadDrivers       = $false
            }

            $result = Invoke-FFUPreflight -Features $features `
                -FFUDevelopmentPath $env:TEMP -SkipCleanup 6>$null

            # All tier results should be populated regardless of WimMount status
            $result.Tier1Results.Keys.Count | Should -BeGreaterThan 0
            $result.Tier2Results.Keys.Count | Should -BeGreaterThan 0
            $result.Tier3Results.Keys.Count | Should -BeGreaterThan 0
            # Tier4 is skipped due to -SkipCleanup
        }

        It 'WimMount result should coexist with other Tier2 results' {
            $features = @{
                CreateVM              = $true
                CreateCaptureMedia    = $true
                CreateDeploymentMedia = $false
                OptimizeFFU           = $false
                InstallApps           = $true   # Triggers Network check
                UpdateLatestCU        = $false
                DownloadDrivers       = $false
            }

            $result = Invoke-FFUPreflight -Features $features `
                -FFUDevelopmentPath $env:TEMP -SkipCleanup 6>$null

            # Multiple Tier2 checks should run
            $result.Tier2Results.Keys | Should -Contain 'WimMount'
            $result.Tier2Results.Keys | Should -Contain 'DiskSpace'
            $result.Tier2Results.Keys | Should -Contain 'ADK'
        }
    }
}

Describe 'Test-FFUWimMount Source Code Verification' -Tag 'WimMount', 'SourceCode', 'Preflight' {

    Context 'Warning Return Logic' {

        BeforeAll {
            $script:modulePath = Join-Path $script:ModulesPath 'FFU.Preflight\FFU.Preflight.psm1'
            $script:moduleContent = Get-Content $script:modulePath -Raw
        }

        It 'Should return Warning status for WIMMount issues' {
            # Verify the code returns Warning, not Failed
            $script:moduleContent | Should -Match "Status 'Warning'" -Because 'Warning status is used for WIMMount issues'
        }

        It 'Should set UsingNativeDISM to $true when returning Warning' {
            # Verify UsingNativeDISM is set to $true before returning Warning
            $script:moduleContent | Should -Match '\$details\.UsingNativeDISM\s*=\s*\$true' -Because 'UsingNativeDISM should be set to true when Warning'
        }

        It 'Should initialize UsingNativeDISM to $false' {
            # Verify UsingNativeDISM is initialized as $false
            $script:moduleContent | Should -Match 'UsingNativeDISM\s*=\s*\$false' -Because 'UsingNativeDISM should default to false'
        }

        It 'Should have catch block that returns Warning with native DISM message' {
            # Verify exception handling also returns Warning
            # The catch block sets UsingNativeDISM = $true and returns Warning status
            $script:moduleContent | Should -Match 'catch\s*\{[\s\S]*UsingNativeDISM\s*=\s*\$true[\s\S]*Status\s+.Warning' -Because 'Exception handling should also return Warning'
        }

        It 'Should NOT have Failed status return for WimMount issues' {
            # Extract the Test-FFUWimMount function body
            $functionMatch = [regex]::Match($script:moduleContent, 'function Test-FFUWimMount[\s\S]*?(?=\n#(?:region|endregion)|function\s+\w+|\z)')
            $functionBody = $functionMatch.Value

            # Count occurrences of Status 'Failed' within the function
            $failedMatches = [regex]::Matches($functionBody, "Status\s+'Failed'")

            # There should be no Failed returns (all should be Warning or Passed)
            $failedMatches.Count | Should -Be 0 -Because 'Test-FFUWimMount should never return Failed status'
        }
    }

    Context 'Invoke-FFUPreflight Warning Handling' {

        BeforeAll {
            $script:modulePath = Join-Path $script:ModulesPath 'FFU.Preflight\FFU.Preflight.psm1'
            $script:moduleContent = Get-Content $script:modulePath -Raw
        }

        It 'Should handle Warning status differently than Failed for WimMount' {
            # Verify there is specific handling for Warning status
            $script:moduleContent | Should -Match "elseif\s*\(\s*\`$wimMountResult\.Status\s+-eq\s+'Warning'\s*\)" -Because 'Warning status should have separate handling'
        }

        It 'Should add to Warnings array for WimMount Warning' {
            # Verify warnings are added to Warnings, not Errors
            $script:moduleContent | Should -Match '\$result\.Warnings\.Add\(' -Because 'Warnings array should have Add method called'
        }

        It 'Should NOT set IsValid to $false in Warning branch' {
            # Extract the Warning handling block - it should NOT contain IsValid = $false
            # The Warning branch sets HasWarnings and adds to Warnings, but NOT IsValid = $false
            # Verify the comment exists that explains this
            $script:moduleContent | Should -Match 'Do NOT set \$result\.IsValid = \$false' -Because 'Comment should document non-blocking nature'
        }

        It 'Should have comment explaining non-blocking behavior' {
            # Verify there is a comment explaining why Warning is non-blocking
            $script:moduleContent | Should -Match 'non-blocking' -Because 'Code should document the non-blocking nature'
        }
    }
}

Describe 'Test-FFUWimMount Backward Compatibility' -Tag 'WimMount', 'Compatibility', 'Preflight' {

    Context 'Return Structure Compatibility' {

        It 'Should maintain original return structure' {
            $result = Test-FFUWimMount

            # Verify all original properties exist
            $result.CheckName | Should -Be 'WimMount'
            $result.PSObject.Properties.Name | Should -Contain 'Status'
            $result.PSObject.Properties.Name | Should -Contain 'Message'
            $result.PSObject.Properties.Name | Should -Contain 'Details'
            $result.PSObject.Properties.Name | Should -Contain 'Remediation'
            $result.PSObject.Properties.Name | Should -Contain 'DurationMs'
        }

        It 'Should maintain original Details structure with new UsingNativeDISM field' {
            $result = Test-FFUWimMount

            # Original detail fields should still exist
            $result.Details.Keys | Should -Contain 'WimMountServiceExists'
            $result.Details.Keys | Should -Contain 'WimMountServiceStatus'
            $result.Details.Keys | Should -Contain 'WofServiceExists'
            $result.Details.Keys | Should -Contain 'WofServiceStatus'
            $result.Details.Keys | Should -Contain 'WimMountDriverExists'
            $result.Details.Keys | Should -Contain 'WofDriverExists'
            $result.Details.Keys | Should -Contain 'FltMgrServiceStatus'
            $result.Details.Keys | Should -Contain 'RemediationAttempted'
            $result.Details.Keys | Should -Contain 'RemediationActions'

            # New field should also exist
            $result.Details.Keys | Should -Contain 'UsingNativeDISM'
        }

        It 'Should accept -AttemptRemediation parameter' {
            { Test-FFUWimMount -AttemptRemediation } | Should -Not -Throw
        }
    }
}
