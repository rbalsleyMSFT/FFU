<#
.SYNOPSIS
    Comprehensive test suite for Solution C - Defender Update validation (3 layers)

.DESCRIPTION
    Tests all three layers of the Update-Defender.ps1 validation fix:
    - Layer 1: Build-time file validation before command generation
    - Layer 2: Runtime file existence checks in generated Update-Defender.ps1
    - Layer 3: Stale Apps.iso detection and automatic rebuild

.NOTES
    Created: 2025-11-25
    Purpose: Prevent Update-Defender.ps1 orchestration failures due to missing files
    Related Issue: "The term 'd:\Defender\' is not recognized" and "d:\defender\securityhealthsetup...exe not recognized"
#>

#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
$testsPassed = 0
$testsFailed = 0

function Test-Condition {
    param(
        [string]$TestName,
        [scriptblock]$Condition,
        [string]$FailureMessage = "Test failed"
    )

    try {
        $result = & $Condition
        if ($result) {
            Write-Host "[PASS] $TestName" -ForegroundColor Green
            $script:testsPassed++
            return $true
        } else {
            Write-Host "[FAIL] $TestName - $FailureMessage" -ForegroundColor Red
            $script:testsFailed++
            return $false
        }
    } catch {
        Write-Host "[FAIL] $TestName - Exception: $_" -ForegroundColor Red
        $script:testsFailed++
        return $false
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Solution C Comprehensive Validation Tests" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Read BuildFFUVM.ps1 content
$buildScriptPath = "C:\claude\FFUBuilder\FFUDevelopment\BuildFFUVM.ps1"
if (-not (Test-Path $buildScriptPath)) {
    Write-Host "ERROR: BuildFFUVM.ps1 not found at $buildScriptPath" -ForegroundColor Red
    exit 1
}
$buildScriptContent = Get-Content -Path $buildScriptPath -Raw

Write-Host "`n=== LAYER 1: Build-time File Validation Tests ===" -ForegroundColor Yellow

Test-Condition -TestName "Layer 1.1: Build-time validation comment exists for Defender updates" -Condition {
    $buildScriptContent -match 'Layer 1: Build-time validation - verify downloaded file exists before generating command'
}

Test-Condition -TestName "Layer 1.2: File path join for validation (Join-Path DefenderPath KBFilePath)" -Condition {
    $buildScriptContent -match '\$fullFilePath\s*=\s*Join-Path\s+\$DefenderPath\s+\$KBFilePath'
}

Test-Condition -TestName "Layer 1.3: Test-Path validation with PathType Leaf" -Condition {
    $buildScriptContent -match 'Test-Path\s+-Path\s+\$fullFilePath\s+-PathType\s+Leaf'
}

Test-Condition -TestName "Layer 1.4: Throws error if file not found after download" -Condition {
    $buildScriptContent -match 'Downloaded file not found at expected location.*Save-KB reported success but file is missing'
}

Test-Condition -TestName "Layer 1.5: Logs file size after validation" -Condition {
    $buildScriptContent -match 'Verified file exists:.*Size:.*MB'
}

Test-Condition -TestName "Layer 1.6: Build-time validation for mpam-fe.exe (Defender definitions)" -Condition {
    $buildScriptContent -match '\$mpamFilePath\s*=\s*"\$DefenderPath\\mpam-fe\.exe"' -and
    $buildScriptContent -match 'Test-Path\s+-Path\s+\$mpamFilePath\s+-PathType\s+Leaf'
}

Test-Condition -TestName "Layer 1.7: Error message for missing Defender definitions file" -Condition {
    $buildScriptContent -match 'Defender definitions file not found at expected location.*Download reported success but file is missing'
}

Test-Condition -TestName "Layer 1.8: File size logging for mpam-fe.exe" -Condition {
    $buildScriptContent -match 'Verified Defender definitions file exists:.*mpam-fe\.exe.*Size:.*MB'
}

Write-Host "`n=== LAYER 2: Runtime File Existence Checks Tests ===" -ForegroundColor Yellow

Test-Condition -TestName "Layer 2.1: Generated command includes Test-Path check for Defender updates" -Condition {
    $buildScriptContent -match "if \(Test-Path -Path 'd:\\Defender\\\`\$KBFilePath'\) \{"
}

Test-Condition -TestName "Layer 2.2: Write-Host for successful file detection" -Condition {
    $buildScriptContent -match 'Write-Host "Installing.*\$KBFilePath\.\.\."'
}

Test-Condition -TestName "Layer 2.3: Exit code validation (0 and 3010 are success)" -Condition {
    $buildScriptContent -match 'if \(\`\$LASTEXITCODE -ne 0 -and \`\$LASTEXITCODE -ne 3010\)'
}

Test-Condition -TestName "Layer 2.4: Error message for non-zero exit codes" -Condition {
    $buildScriptContent -match 'Write-Error "Installation of.*failed with exit code: \`\$LASTEXITCODE"'
}

Test-Condition -TestName "Layer 2.5: Success message with exit code logging" -Condition {
    $buildScriptContent -match 'Write-Host ".*installed successfully \(Exit code: \`\$LASTEXITCODE\)"'
}

Test-Condition -TestName "Layer 2.6: Critical error when file not found at d:\Defender\" -Condition {
    $buildScriptContent -match 'Write-Error "CRITICAL: File not found at d:\\Defender\\\$KBFilePath"'
}

Test-Condition -TestName "Layer 2.7: Actionable error message about Apps.iso" -Condition {
    $buildScriptContent -match 'This indicates Apps\.iso does not contain Defender folder' -and
    $buildScriptContent -match 'Possible causes:.*Apps\.iso created before Defender download.*Stale Apps\.iso being reused.*ISO creation failed'
}

Test-Condition -TestName "Layer 2.8: Exit 1 on missing file during orchestration" -Condition {
    $buildScriptContent -match 'exit 1' -and
    ($buildScriptContent -split 'exit 1').Count -ge 2  # Should have at least one exit 1 for Defender files
}

Test-Condition -TestName "Layer 2.9: Runtime check for mpam-fe.exe (Defender definitions)" -Condition {
    $buildScriptContent -match "if \(Test-Path -Path 'd:\\Defender\\mpam-fe\.exe'\) \{"
}

Test-Condition -TestName "Layer 2.10: Installation message for mpam-fe.exe" -Condition {
    $buildScriptContent -match 'Write-Host "Installing Defender Definitions: mpam-fe\.exe\.\.\."'
}

Test-Condition -TestName "Layer 2.11: Exit code validation for mpam-fe.exe" -Condition {
    # Count how many times we check LASTEXITCODE (should be at least 2: one for updates, one for definitions)
    ($buildScriptContent -split 'if \(\`\$LASTEXITCODE -ne 0 -and \`\$LASTEXITCODE -ne 3010\)').Count -ge 3
}

Test-Condition -TestName "Layer 2.12: Critical error for missing mpam-fe.exe" -Condition {
    $buildScriptContent -match 'Write-Error "CRITICAL: File not found at d:\\Defender\\mpam-fe\.exe"'
}

Write-Host "`n=== LAYER 3: Stale Apps.iso Detection Tests ===" -ForegroundColor Yellow

Test-Condition -TestName "Layer 3.1: Layer 3 comment exists before Apps.iso creation" -Condition {
    $buildScriptContent -match 'Layer 3: Force Apps\.iso recreation if downloaded files are newer than existing ISO'
}

Test-Condition -TestName "Layer 3.2: Check if Apps.iso exists before validation" -Condition {
    $buildScriptContent -match 'if \(Test-Path \$AppsISO\) \{'
}

Test-Condition -TestName "Layer 3.3: Get ISO last write time" -Condition {
    $buildScriptContent -match '\$isoLastWrite\s*=\s*\(Get-Item \$AppsISO\)\.LastWriteTime'
}

Test-Condition -TestName "Layer 3.4: Initialize needsRebuild flag" -Condition {
    $buildScriptContent -match '\$needsRebuild\s*=\s*\$false'
}

Test-Condition -TestName "Layer 3.5: Check Defender files if UpdateLatestDefender enabled" -Condition {
    $buildScriptContent -match 'if \(\$UpdateLatestDefender -and \(Test-Path -Path \$DefenderPath\)\)'
}

Test-Condition -TestName "Layer 3.6: Get newest Defender file with Sort-Object" -Condition {
    $buildScriptContent -match '\$newestDefender\s*=\s*\$defenderFiles \| Sort-Object LastWriteTime -Descending \| Select-Object -First 1'
}

Test-Condition -TestName "Layer 3.7: Compare Defender file time with ISO time" -Condition {
    $buildScriptContent -match 'if \(\$newestDefender\.LastWriteTime -gt \$isoLastWrite\)'
}

Test-Condition -TestName "Layer 3.8: Set needsRebuild flag when Defender files are newer" -Condition {
    $buildScriptContent -match '\$needsRebuild\s*=\s*\$true' -and
    $buildScriptContent -match 'Defender file is newer than Apps\.iso'
}

Test-Condition -TestName "Layer 3.9: Check MSRT files if UpdateLatestMSRT enabled" -Condition {
    $buildScriptContent -match 'if \(\$UpdateLatestMSRT -and \(Test-Path -Path \$MSRTPath\)\)'
}

Test-Condition -TestName "Layer 3.10: Get newest MSRT file" -Condition {
    $buildScriptContent -match '\$newestMSRT\s*=\s*\$msrtFiles \| Sort-Object LastWriteTime -Descending \| Select-Object -First 1'
}

Test-Condition -TestName "Layer 3.11: Compare MSRT file time with ISO time" -Condition {
    $buildScriptContent -match 'if \(\$newestMSRT\.LastWriteTime -gt \$isoLastWrite\)'
}

Test-Condition -TestName "Layer 3.12: Check Edge files if UpdateEdge enabled" -Condition {
    $buildScriptContent -match 'if \(\$UpdateEdge -and \(Test-Path -Path \$EdgePath\)\)'
}

Test-Condition -TestName "Layer 3.13: Get newest Edge file" -Condition {
    $buildScriptContent -match '\$newestEdge\s*=\s*\$edgeFiles \| Sort-Object LastWriteTime -Descending \| Select-Object -First 1'
}

Test-Condition -TestName "Layer 3.14: Compare Edge file time with ISO time" -Condition {
    $buildScriptContent -match 'if \(\$newestEdge\.LastWriteTime -gt \$isoLastWrite\)'
}

Test-Condition -TestName "Layer 3.15: Check OneDrive files if UpdateOneDrive enabled" -Condition {
    $buildScriptContent -match 'if \(\$UpdateOneDrive -and \(Test-Path -Path \$OneDrivePath\)\)'
}

Test-Condition -TestName "Layer 3.16: Get newest OneDrive file" -Condition {
    $buildScriptContent -match '\$newestOneDrive\s*=\s*\$oneDriveFiles \| Sort-Object LastWriteTime -Descending \| Select-Object -First 1'
}

Test-Condition -TestName "Layer 3.17: Remove stale Apps.iso when newer files detected" -Condition {
    $buildScriptContent -match 'if \(\$needsRebuild\) \{' -and
    $buildScriptContent -match 'STALE APPS\.ISO DETECTED: Removing outdated Apps\.iso'
}

Test-Condition -TestName "Layer 3.18: Log newest file information" -Condition {
    $buildScriptContent -match 'Newest file:.*\$newestFile.*Modified:.*\$newestFileTime'
}

Test-Condition -TestName "Layer 3.19: Remove-Item for stale ISO" -Condition {
    $buildScriptContent -match 'Remove-Item \$AppsISO -Force'
}

Test-Condition -TestName "Layer 3.20: Success message when ISO removed" -Condition {
    $buildScriptContent -match 'Stale Apps\.iso removed\. New ISO will be created with all latest updates\.'
}

Test-Condition -TestName "Layer 3.21: Info message when ISO is up-to-date" -Condition {
    $buildScriptContent -match 'Apps\.iso is up-to-date\. No rebuild required\.'
}

Write-Host "`n=== INTEGRATION TESTS ===" -ForegroundColor Yellow

Test-Condition -TestName "Integration 1: Layer 1 validation happens BEFORE Layer 2 command generation" -Condition {
    # Layer 1 should appear before the heredoc for Layer 2
    $layer1Index = $buildScriptContent.IndexOf('Layer 1: Build-time validation')
    $layer2Index = $buildScriptContent.IndexOf('Layer 2: Generate command with runtime file existence check')
    $layer1Index -lt $layer2Index -and $layer1Index -gt 0 -and $layer2Index -gt 0
}

Test-Condition -TestName "Integration 2: Layer 3 validation happens BEFORE New-AppsISO call" -Condition {
    $layer3Index = $buildScriptContent.IndexOf('Layer 3: Force Apps.iso recreation')
    $newAppsISOIndex = $buildScriptContent.IndexOf('New-AppsISO -ADKPath')
    $layer3Index -lt $newAppsISOIndex -and $layer3Index -gt 0 -and $newAppsISOIndex -gt 0
}

Test-Condition -TestName "Integration 3: All three layers are present in correct order" -Condition {
    $layer1Index = $buildScriptContent.IndexOf('Layer 1: Build-time validation')
    $layer2Index = $buildScriptContent.IndexOf('Layer 2: Generate command with runtime file existence check')
    $layer3Index = $buildScriptContent.IndexOf('Layer 3: Force Apps.iso recreation')

    # Layer 1 should come first (in Defender download section)
    # Layer 2 should be part of Layer 1 section (command generation)
    # Layer 3 should come later (before Apps.iso creation)
    $layer1Index -gt 0 -and $layer2Index -gt $layer1Index -and $layer3Index -gt $layer2Index
}

Test-Condition -TestName "Integration 4: Build-time validation exists for BOTH Defender updates and definitions" -Condition {
    # Should have two separate build-time validation blocks
    ($buildScriptContent -split 'Layer 1: Build-time validation').Count -eq 3  # Split creates N+1 parts for N occurrences
}

Test-Condition -TestName "Integration 5: Runtime checks exist for BOTH Defender updates and definitions" -Condition {
    # Should have Test-Path for both $KBFilePath and mpam-fe.exe
    $buildScriptContent -match "Test-Path -Path 'd:\\Defender\\\`\$KBFilePath'" -and
    $buildScriptContent -match "Test-Path -Path 'd:\\Defender\\mpam-fe\.exe'"
}

Test-Condition -TestName "Integration 6: Error handling covers all failure scenarios" -Condition {
    # Should handle: file not found after download, file not found during orchestration, non-zero exit codes
    $buildScriptContent -match 'Downloaded file not found' -and
    $buildScriptContent -match 'File not found at d:\\Defender' -and
    $buildScriptContent -match 'failed with exit code'
}

Test-Condition -TestName "Integration 7: Logging is comprehensive (file sizes, timestamps, paths)" -Condition {
    $buildScriptContent -match 'Size:.*MB' -and
    $buildScriptContent -match 'Last modified:' -and
    $buildScriptContent -match 'Modified:'
}

Write-Host "`n=== CODE QUALITY TESTS ===" -ForegroundColor Yellow

Test-Condition -TestName "Quality 1: No hardcoded paths in validation logic" -Condition {
    # Should use variables like $DefenderPath, $MSRTPath, etc., not hardcoded paths
    # Check that validation uses proper variables
    $buildScriptContent -match 'Join-Path.*\$DefenderPath' -and
    $buildScriptContent -match '\$MSRTPath' -and
    $buildScriptContent -match '\$EdgePath'
}

Test-Condition -TestName "Quality 2: All error messages are descriptive and actionable" -Condition {
    # Error messages should explain the problem AND suggest causes
    $buildScriptContent -match 'This indicates' -and
    $buildScriptContent -match 'Possible causes:' -and
    $buildScriptContent -match 'may indicate:'
}

Test-Condition -TestName "Quality 3: Consistent logging style (WriteLog for build, Write-Host/Write-Error for runtime)" -Condition {
    # Build-time logging uses WriteLog, runtime uses Write-Host/Write-Error
    $buildScriptContent -match 'WriteLog "Verified file exists:' -and
    $buildScriptContent -match 'Write-Host "Installing' -and
    $buildScriptContent -match 'Write-Error "CRITICAL:'
}

Test-Condition -TestName "Quality 4: Proper PowerShell escaping in heredoc (backticks for variables)" -Condition {
    # In the generated heredoc, variables that should NOT be evaluated at build time need backticks
    $buildScriptContent -match '\`\$LASTEXITCODE'
}

Test-Condition -TestName "Quality 5: All Test-Path calls include -PathType for clarity" -Condition {
    # Build-time Test-Path should specify -PathType Leaf for files
    $buildScriptContent -match 'Test-Path.*-PathType Leaf'
}

Test-Condition -TestName "Quality 6: Defense-in-depth pattern (multiple validation layers)" -Condition {
    # Should have validation at different stages: download, build, runtime
    $buildScriptContent -match 'Layer 1:' -and
    $buildScriptContent -match 'Layer 2:' -and
    $buildScriptContent -match 'Layer 3:'
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Tests Passed: $testsPassed" -ForegroundColor Green
Write-Host "Tests Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -eq 0) { 'Green' } else { 'Red' })
Write-Host "Total Tests:  $($testsPassed + $testsFailed)" -ForegroundColor Cyan

if ($testsFailed -eq 0) {
    Write-Host "`nAll tests passed! Solution C is fully implemented." -ForegroundColor Green
    exit 0
} else {
    Write-Host "`nSome tests failed. Please review the implementation." -ForegroundColor Red
    exit 1
}
