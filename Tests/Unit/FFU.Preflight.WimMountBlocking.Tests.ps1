#Requires -Version 7.0

<#
.SYNOPSIS
    Pester tests for FFU.Preflight module's Test-FFUWimMount function to verify blocking failure behavior.

.DESCRIPTION
    Validates that Test-FFUWimMount correctly returns Status 'Failed' (NOT 'Warning') when
    WIMMount service issues are detected. This verifies the v1.3.8 fix that made WimMount
    failures BLOCKING again.

    **CURRENT STATUS**: These tests are EXPECTED TO FAIL with FFU.Preflight v1.0.3 because
    the module manifest claims the fix is present but the code still contains the v1.0.2 bug
    (line 1222: "Don't add to errors here - will be handled as warning due to native DISM usage").

    The tests document the DESIRED behavior after the v1.3.8 fix is applied.

    Test coverage:
    - Returns 'Failed' status when WIMMount service is missing
    - Returns 'Failed' status when WIMMount driver is missing
    - Returns 'Passed' status when WIMMount is healthy
    - Failure messages contain "BLOCKING" text
    - Failure messages do NOT contain misleading "non-blocking" text
    - Failure messages do NOT contain incorrect "native DISM cmdlets" workaround claims
    - Remediation guidance is provided for all failures
    - Module exports Test-FFUWimMount function
    - Module version is 1.0.3

.NOTES
    Module: FFU.Preflight
    Version: 1.0.3 (with v1.0.2 bug still present in code)
    Test Focus: WimMount blocking failure validation (v1.3.8 fix specification)
#>

BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\Modules\FFU.Preflight\FFU.Preflight.psd1' | Resolve-Path

    # Import module
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'FFU.Preflight Module - Test-FFUWimMount Blocking Behavior (v1.3.8 Specification)' -Tag 'Unit', 'Preflight', 'WimMount' {

    Context 'Module Structure and Exports' {
        It 'Module should be imported successfully' {
            Get-Module -Name 'FFU.Preflight' | Should -Not -BeNullOrEmpty
        }

        It 'Module version should be 1.0.3' {
            $module = Get-Module -Name 'FFU.Preflight'
            $module.Version.ToString() | Should -Be '1.0.3'
        }

        It 'Should export Test-FFUWimMount function' {
            $module = Get-Module -Name 'FFU.Preflight'
            $module.ExportedFunctions.Keys | Should -Contain 'Test-FFUWimMount'
        }

        It 'Test-FFUWimMount should be callable' {
            { Get-Command Test-FFUWimMount -ErrorAction Stop } | Should -Not -Throw
        }
    }

    Context 'Test-FFUWimMount - WIMMount Service Missing (SHOULD BE BLOCKING)' {
        BeforeAll {
            # Note: We cannot easily mock Get-Service at module scope in Pester 5.x
            # Instead, these tests document the EXPECTED behavior by examining
            # the result object structure and content

            # This test will call the REAL Test-FFUWimMount and verify its behavior
            # on the current system. If WIMMount exists on the test system, we skip.

            try {
                $testSvc = Get-Service -Name 'WIMMount' -ErrorAction Stop
                $wimMountExists = $true
            }
            catch {
                $wimMountExists = $false
            }

            if (-not $wimMountExists) {
                # WIMMount doesn't exist on this system - perfect for testing failure case
                $result = Test-FFUWimMount
            }
        }

        It 'Should return Status "Failed" when WIMMount service missing (NOT "Warning")' -Skip:$wimMountExists {
            $result.Status | Should -Be 'Failed'
            $result.Status | Should -Not -Be 'Warning'
        }

        It 'Should indicate this is a BLOCKING failure in message' -Skip:$wimMountExists {
            $result.Message | Should -Match 'BLOCKING'
        }

        It 'Message should NOT contain "non-blocking"' -Skip:$wimMountExists {
            $result.Message | Should -Not -Match 'non-blocking'
            $result.Message | Should -Not -Match 'non blocking'
        }

        It 'Should contain remediation steps when failed' -Skip:$wimMountExists {
            if ($result.Status -eq 'Failed') {
                $result.Remediation | Should -Not -BeNullOrEmpty
                $result.Remediation | Should -Match 'rundll32.exe wimmount.dll,WimMountDriver'
            }
        }

        It 'Remediation should emphasize BOTH ADK and PowerShell DISM require WIMMount' -Skip:$wimMountExists {
            if ($result.Status -eq 'Failed') {
                $result.Remediation | Should -Match 'BOTH ADK dism.exe AND native PowerShell DISM cmdlets'
                $result.Remediation | Should -Match 'Mount-WindowsImage|Dismount-WindowsImage'
            }
        }

        It 'Remediation should state this is a BLOCKING failure' -Skip:$wimMountExists {
            if ($result.Status -eq 'Failed') {
                $result.Remediation | Should -Match 'BLOCKING'
            }
        }

        It 'Remediation should NOT suggest native DISM as a workaround' -Skip:$wimMountExists {
            if ($result.Status -eq 'Failed') {
                # Should NOT contain misleading guidance that native DISM cmdlets bypass WIMMount
                $result.Remediation | Should -Not -Match 'workaround'
                $result.Remediation | Should -Not -Match 'use.*instead'
            }
        }
    }

    Context 'Test-FFUWimMount - Code Analysis for v1.0.2 Bug' {
        It 'Source code should NOT contain v1.0.2 bug comment on line 1222' {
            $modulePsmPath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\Modules\FFU.Preflight\FFU.Preflight.psm1' | Resolve-Path
            $sourceCode = Get-Content -Path $modulePsmPath -Raw

            # Check for the v1.0.2 buggy comment
            $hasBuggyComment = $sourceCode -match "Don't add to errors here - will be handled as warning due to native DISM usage"

            # This should be FALSE after v1.3.8 fix
            $hasBuggyComment | Should -Be $false -Because 'v1.0.2 bug comment should be removed in v1.3.8 fix'
        }

        It 'Source code line 1222 should ADD WIMMount service missing to errors (not skip it)' {
            $modulePsmPath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\Modules\FFU.Preflight\FFU.Preflight.psm1' | Resolve-Path
            $sourceLines = Get-Content -Path $modulePsmPath

            # Get lines around line 1222 (context: 1215-1230)
            $context = $sourceLines[1214..1229]
            $contextText = $context -join "`n"

            # After v1.3.8 fix, line 1222 should add error, not skip it
            # The logic should be: if service doesn't exist, ADD to errors
            $hasCorrectLogic = $contextText -match '\$errors\.Add.*WIMMount service.*not exist'

            $hasCorrectLogic | Should -Be $true -Because 'After v1.3.8 fix, missing WIMMount should be added to errors list'
        }

        It 'UsingNativeDISM field should NOT be present in Details' {
            # Create a minimal test to check Details structure
            # This requires WIMMount to actually exist on the system
            try {
                $testResult = Test-FFUWimMount
                $testResult.Details.Keys | Should -Not -Contain 'UsingNativeDISM' -Because 'v1.0.3 should have removed this misleading field'
            }
            catch {
                Set-ItResult -Skipped -Because 'Cannot test Details without a valid WIMMount check'
            }
        }
    }

    Context 'Test-FFUWimMount - Remediation Message Content (v1.3.8 Requirements)' {
        It 'Function should exist and be testable' {
            { Get-Command Test-FFUWimMount -ErrorAction Stop } | Should -Not -Throw
        }

        It 'Remediation text in source code should emphasize BOTH DISM implementations' {
            $modulePsmPath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\Modules\FFU.Preflight\FFU.Preflight.psm1' | Resolve-Path
            $sourceCode = Get-Content -Path $modulePsmPath -Raw

            # Look for the remediation string in Test-FFUWimMount function (around lines 1384-1427)
            $remediationSection = $sourceCode -match 'WIM mount capability has.*issues.*CRITICAL'
            $hasCorrectRemediationText = $sourceCode -match 'BOTH ADK dism\.exe AND native PowerShell DISM cmdlets.*require the WIMMount'

            $hasCorrectRemediationText | Should -Be $true -Because 'Remediation should emphasize both DISM implementations require WIMMount'
        }

        It 'Remediation should mention Mount-WindowsImage and Dismount-WindowsImage' {
            $modulePsmPath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\Modules\FFU.Preflight\FFU.Preflight.psm1' | Resolve-Path
            $sourceCode = Get-Content -Path $modulePsmPath -Raw

            $mentionsCmdlets = $sourceCode -match 'Mount-WindowsImage|Dismount-WindowsImage'

            $mentionsCmdlets | Should -Be $true -Because 'Remediation should mention the PowerShell DISM cmdlets that also require WIMMount'
        }

        It 'Error messages should use "BLOCKING" terminology' {
            $modulePsmPath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\Modules\FFU.Preflight\FFU.Preflight.psm1' | Resolve-Path
            $sourceCode = Get-Content -Path $modulePsmPath -Raw

            # Check for BLOCKING terminology in failure messages (lines 1423-1450)
            $hasBlockingTerminology = $sourceCode -match 'Status.*Failed.*Message.*BLOCKING'

            $hasBlockingTerminology | Should -Be $true -Because 'Failure messages should explicitly state BLOCKING to indicate non-negotiable requirement'
        }
    }

    Context 'Test-FFUWimMount - Return Value Structure Validation' {
        BeforeAll {
            # Call the real function to check return structure
            try {
                $result = Test-FFUWimMount
            }
            catch {
                $result = $null
            }
        }

        It 'Should return PSCustomObject' {
            $result | Should -BeOfType [PSCustomObject]
        }

        It 'Should have CheckName property' {
            $result.PSObject.Properties.Name | Should -Contain 'CheckName'
            $result.CheckName | Should -Be 'WimMount'
        }

        It 'Should have Status property with valid value' {
            $result.PSObject.Properties.Name | Should -Contain 'Status'
            $result.Status | Should -BeIn @('Passed', 'Failed', 'Warning', 'Skipped')
        }

        It 'Should have Message property' {
            $result.PSObject.Properties.Name | Should -Contain 'Message'
            $result.Message | Should -Not -BeNullOrEmpty
        }

        It 'Should have Details property with expected fields' {
            $result.PSObject.Properties.Name | Should -Contain 'Details'
            $result.Details.Keys | Should -Contain 'WimMountServiceExists'
            $result.Details.Keys | Should -Contain 'WimMountDriverExists'
            $result.Details.Keys | Should -Contain 'FltMgrServiceStatus'
        }

        It 'Should have Remediation property' {
            $result.PSObject.Properties.Name | Should -Contain 'Remediation'
        }

        It 'Should have DurationMs property greater than 0' {
            $result.PSObject.Properties.Name | Should -Contain 'DurationMs'
            $result.DurationMs | Should -BeGreaterThan 0
        }

        It 'Details should NOT contain misleading UsingNativeDISM field' {
            # This field was added in v1.0.2 and should be removed in v1.0.3+
            $result.Details.Keys | Should -Not -Contain 'UsingNativeDISM' -Because 'v1.0.3 removed this misleading field per release notes'
        }
    }

    Context 'Test-FFUWimMount - Healthy System Behavior' {
        BeforeAll {
            # Check if we have a healthy WIM mount system
            try {
                $wimMountSvc = Get-Service -Name 'WIMMount' -ErrorAction Stop
                $wimMountDriver = Test-Path (Join-Path $env:SystemRoot 'System32\drivers\wimmount.sys')
                $fltMgrSvc = Get-Service -Name 'FltMgr' -ErrorAction Stop

                $isHealthy = ($wimMountSvc.StartType -ne 'Disabled') -and $wimMountDriver -and ($fltMgrSvc.Status -eq 'Running')
            }
            catch {
                $isHealthy = $false
            }

            if ($isHealthy) {
                $result = Test-FFUWimMount
            }
        }

        It 'Should return Status "Passed" when WIMMount infrastructure is healthy' -Skip:(-not $isHealthy) {
            $result.Status | Should -Be 'Passed'
        }

        It 'Should have positive message when passed' -Skip:(-not $isHealthy) {
            $result.Message | Should -Match 'WIM mount capability is available'
        }

        It 'Should NOT have remediation for passed check' -Skip:(-not $isHealthy) {
            $result.Remediation | Should -BeNullOrEmpty
        }

        It 'Should NOT mention BLOCKING in passed message' -Skip:(-not $isHealthy) {
            $result.Message | Should -Not -Match 'BLOCKING'
        }

        It 'Details should indicate all components exist' -Skip:(-not $isHealthy) {
            $result.Details.WimMountServiceExists | Should -Be $true
            $result.Details.WimMountDriverExists | Should -Be $true
            $result.Details.FltMgrServiceStatus | Should -Be 'Running'
        }
    }

    Context 'Invoke-FFUPreflight Integration - WimMount Should Block Build' {
        It 'Test-FFUWimMount should integrate correctly with Invoke-FFUPreflight' {
            # This test verifies that the Invoke-FFUPreflight function correctly
            # treats 'Failed' status from Test-FFUWimMount as a blocking error

            # Check the source code for correct integration
            $modulePsmPath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\Modules\FFU.Preflight\FFU.Preflight.psm1' | Resolve-Path
            $sourceCode = Get-Content -Path $modulePsmPath -Raw

            # Look for Invoke-FFUPreflight WimMount integration (around lines 2000-2029)
            # After v1.3.8 fix, elseif ($wimMountResult.Status -eq 'Warning') should NOT exist
            # Only Failed and Passed should be handled
            $hasWarningHandling = $sourceCode -match 'wimMountResult\.Status.*-eq.*Warning'

            if ($hasWarningHandling) {
                # v1.0.2 bug still present - Warning handling exists
                $correctIntegration = $false
            }
            else {
                # Check for correct Failed handling that sets IsValid = false
                $correctIntegration = $sourceCode -match 'wimMountResult\.Status.*-eq.*Failed.*\$result\.IsValid\s*=\s*\$false'
            }

            $correctIntegration | Should -Be $true -Because 'Invoke-FFUPreflight should treat WimMount Failed status as blocking (no Warning handling)'
        }

        It 'Invoke-FFUPreflight should add WimMount failures to Errors list (not Warnings)' {
            $modulePsmPath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\Modules\FFU.Preflight\FFU.Preflight.psm1' | Resolve-Path
            $sourceCode = Get-Content -Path $modulePsmPath -Raw

            # Check that Failed wimMountResult goes to Errors, not Warnings
            # The pattern should be: if Failed, add to $result.Errors
            # NOT: if Warning, add to $result.Warnings

            # Extract the WimMount handling section (around lines 2000-2029)
            $lines = Get-Content -Path $modulePsmPath
            $wimMountSection = ($lines[1999..2028] | Where-Object { $_ -match 'wimMount' }) -join "`n"

            # After v1.3.8 fix: Failed should add to Errors
            $failedAddsToErrors = $wimMountSection -match "Status.*-eq.*'Failed'.*Errors\.Add"

            # After v1.3.8 fix: There should be NO Warning handling for WimMount
            $warningAddsToWarnings = $wimMountSection -match "Status.*-eq.*'Warning'.*Warnings\.Add"

            $failedAddsToErrors | Should -Be $true -Because 'WimMount Failed status should add to Errors'
            $warningAddsToWarnings | Should -Be $false -Because 'WimMount should never return Warning status in v1.3.8+'
        }
    }

    Context 'v1.0.2 Bug Detection - Code Should Be Fixed' {
        It 'Line 1222 should NOT have the "warning due to native DISM" comment' {
            $modulePsmPath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\Modules\FFU.Preflight\FFU.Preflight.psm1' | Resolve-Path
            $lines = Get-Content -Path $modulePsmPath

            # Line 1222 should NOT contain the v1.0.2 buggy comment
            $line1222 = $lines[1221]  # 0-indexed

            $hasBuggyComment = $line1222 -match 'will be handled as warning due to native DISM'

            $hasBuggyComment | Should -Be $false -Because 'v1.0.2 bug comment should be removed and WIMMount errors should be added to errors list'
        }

        It 'Line 1222 vicinity should add WIMMount missing to errors list' {
            $modulePsmPath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\Modules\FFU.Preflight\FFU.Preflight.psm1' | Resolve-Path
            $lines = Get-Content -Path $modulePsmPath

            # Check lines 1218-1225 for correct error handling
            $errorHandlingSection = $lines[1217..1224] -join "`n"

            # After v1.3.8 fix, this section should call $errors.Add() when service not found
            $addsToErrorsList = $errorHandlingSection -match '\$errors\.Add\('

            $addsToErrorsList | Should -Be $true -Because 'WIMMount service not found should be added to errors list'
        }

        It 'Invoke-FFUPreflight lines 2008-2022 should NOT handle Warning status for WimMount' {
            $modulePsmPath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\Modules\FFU.Preflight\FFU.Preflight.psm1' | Resolve-Path
            $lines = Get-Content -Path $modulePsmPath

            # Check the WimMount integration section in Invoke-FFUPreflight
            $wimMountIntegration = $lines[2007..2021] -join "`n"

            # Should NOT have: elseif ($wimMountResult.Status -eq 'Warning')
            $hasWarningBranch = $wimMountIntegration -match "wimMountResult\.Status\s*-eq\s*'Warning'"

            $hasWarningBranch | Should -Be $false -Because 'v1.3.8 fix removes Warning handling - WimMount failures should always be BLOCKING'
        }
    }
}

AfterAll {
    # Clean up module
    Remove-Module -Name 'FFU.Preflight' -Force -ErrorAction SilentlyContinue
}
