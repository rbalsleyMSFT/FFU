# Test-CaptureFFUScriptUpdateFix.ps1
# Comprehensive test suite for CaptureFFU.ps1 script update functionality

<#
.SYNOPSIS
Tests the Update-CaptureFFUScript function and BuildFFUVM.ps1 integration

.DESCRIPTION
Validates that:
1. Update-CaptureFFUScript function exists and is exported
2. Function has correct parameters and validation
3. Function correctly replaces placeholder values in CaptureFFU.ps1
4. BuildFFUVM.ps1 generates password and calls Update-CaptureFFUScript
5. Error handling works correctly
6. Backup files are created
7. Verification logic validates updates

.EXAMPLE
.\Test-CaptureFFUScriptUpdateFix.ps1
#>

$ErrorActionPreference = 'Stop'

# Test configuration
$testStartTime = Get-Date
$testsPassed = 0
$testsFailed = 0
$testsSkipped = 0

# Paths
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ffuVMModulePath = Join-Path $scriptRoot "Modules\FFU.VM\FFU.VM.psm1"
$buildFFUVMPath = Join-Path $scriptRoot "BuildFFUVM.ps1"
$captureFFUScriptPath = Join-Path $scriptRoot "WinPECaptureFFUFiles\CaptureFFU.ps1"

Write-Host "====================================================="
Write-Host "  CaptureFFU Script Update Fix - Test Suite"
Write-Host "====================================================="
Write-Host ""
Write-Host "Test file: Test-CaptureFFUScriptUpdateFix.ps1"
Write-Host "Module: $ffuVMModulePath"
Write-Host "BuildFFUVM: $buildFFUVMPath"
Write-Host "CaptureFFU: $captureFFUScriptPath"
Write-Host ""

# Helper function to test conditions
function Test-Condition {
    param(
        [string]$TestName,
        [scriptblock]$Condition,
        [switch]$ShouldFail
    )

    try {
        $result = & $Condition

        if ($ShouldFail) {
            if ($result) {
                Write-Host "[FAIL] $TestName - Expected failure but passed" -ForegroundColor Red
                $script:testsFailed++
                return $false
            } else {
                Write-Host "[PASS] $TestName" -ForegroundColor Green
                $script:testsPassed++
                return $true
            }
        } else {
            if ($result) {
                Write-Host "[PASS] $TestName" -ForegroundColor Green
                $script:testsPassed++
                return $true
            } else {
                Write-Host "[FAIL] $TestName" -ForegroundColor Red
                $script:testsFailed++
                return $false
            }
        }
    }
    catch {
        if ($ShouldFail) {
            Write-Host "[PASS] $TestName (Expected error: $_)" -ForegroundColor Green
            $script:testsPassed++
            return $true
        } else {
            Write-Host "[FAIL] $TestName - Exception: $_" -ForegroundColor Red
            $script:testsFailed++
            return $false
        }
    }
}

# ========== MODULE AND FUNCTION EXISTENCE TESTS ==========
Write-Host "`n========== Module and Function Tests ==========" -ForegroundColor Cyan

Test-Condition "Test 1.1: FFU.VM module file exists" {
    Test-Path $ffuVMModulePath
}

Test-Condition "Test 1.2: BuildFFUVM.ps1 file exists" {
    Test-Path $buildFFUVMPath
}

Test-Condition "Test 1.3: CaptureFFU.ps1 file exists" {
    Test-Path $captureFFUScriptPath
}

# Define WriteLog function for testing (required by FFU.VM module)
if (-not (Get-Command WriteLog -ErrorAction SilentlyContinue)) {
    function global:WriteLog {
        param([string]$Message)
        Write-Verbose $Message -Verbose
    }
}

# Import module for testing
try {
    Import-Module $ffuVMModulePath -Force -Global -ErrorAction Stop
    Write-Host "[INFO] FFU.VM module imported successfully" -ForegroundColor Gray
}
catch {
    Write-Host "[ERROR] Failed to import FFU.VM module: $_" -ForegroundColor Red
    exit 1
}

Test-Condition "Test 1.4: Update-CaptureFFUScript function exists" {
    $null -ne (Get-Command Update-CaptureFFUScript -ErrorAction SilentlyContinue)
}

Test-Condition "Test 1.5: Update-CaptureFFUScript is exported from module" {
    $module = Get-Module FFU.VM
    $module.ExportedCommands.ContainsKey('Update-CaptureFFUScript')
}

# ========== FUNCTION PARAMETER TESTS ==========
Write-Host "`n========== Function Parameter Tests ==========" -ForegroundColor Cyan

$functionInfo = Get-Command Update-CaptureFFUScript

Test-Condition "Test 2.1: VMHostIPAddress parameter exists and is mandatory" {
    $param = $functionInfo.Parameters['VMHostIPAddress']
    $param -and $param.Attributes.Mandatory -contains $true
}

Test-Condition "Test 2.2: ShareName parameter exists and is mandatory" {
    $param = $functionInfo.Parameters['ShareName']
    $param -and $param.Attributes.Mandatory -contains $true
}

Test-Condition "Test 2.3: Username parameter exists and is mandatory" {
    $param = $functionInfo.Parameters['Username']
    $param -and $param.Attributes.Mandatory -contains $true
}

Test-Condition "Test 2.4: Password parameter exists and is mandatory" {
    $param = $functionInfo.Parameters['Password']
    $param -and $param.Attributes.Mandatory -contains $true
}

Test-Condition "Test 2.5: FFUDevelopmentPath parameter exists and is mandatory" {
    $param = $functionInfo.Parameters['FFUDevelopmentPath']
    $param -and $param.Attributes.Mandatory -contains $true
}

Test-Condition "Test 2.6: CustomFFUNameTemplate parameter exists and is optional" {
    $param = $functionInfo.Parameters['CustomFFUNameTemplate']
    $param -and $param.Attributes.Mandatory -notcontains $true
}

# ========== FUNCTION LOGIC TESTS ==========
Write-Host "`n========== Function Logic Tests ==========" -ForegroundColor Cyan

# Create test environment
$testFFUDevPath = Join-Path $env:TEMP "FFUBuilderTest_$(Get-Date -Format 'yyyyMMddHHmmss')"
$testCaptureFFUPath = Join-Path $testFFUDevPath "WinPECaptureFFUFiles"
$testCaptureFFUScript = Join-Path $testCaptureFFUPath "CaptureFFU.ps1"

try {
    # Create test directory structure
    New-Item -Path $testCaptureFFUPath -ItemType Directory -Force | Out-Null

    # Create test CaptureFFU.ps1 with placeholder values
    $testScriptContent = @"
`$VMHostIPAddress = '192.168.1.158'
`$ShareName = 'FFUCaptureShare'
`$UserName = 'ffu_user'
`$Password = '23202eb4-10c3-47e9-b389-f0c462663a23'
`$CustomFFUNameTemplate = '{WindowsRelease}_{WindowsVersion}_{SKU}_{yyyy}-{MM}-{dd}_{HH}{mm}'

# Rest of script...
Write-Host "This is a test script"
"@
    Set-Content -Path $testCaptureFFUScript -Value $testScriptContent -Force

    Write-Host "[INFO] Created test environment at: $testFFUDevPath" -ForegroundColor Gray

    Test-Condition "Test 3.1: Test script file created successfully" {
        Test-Path $testCaptureFFUScript
    }

    # Test Update-CaptureFFUScript with test values
    $testIP = "10.0.0.100"
    $testShare = "TestShare"
    $testUser = "test_user"
    $testPassword = "SecureTestPass123!"
    $testTemplate = "{WindowsRelease}_{SKU}_TEST"

    Test-Condition "Test 3.2: Function runs without errors" {
        try {
            Update-CaptureFFUScript -VMHostIPAddress $testIP `
                                   -ShareName $testShare `
                                   -Username $testUser `
                                   -Password $testPassword `
                                   -FFUDevelopmentPath $testFFUDevPath `
                                   -CustomFFUNameTemplate $testTemplate `
                                   -ErrorAction Stop
            $true
        }
        catch {
            Write-Host "  Error: $_" -ForegroundColor Yellow
            $false
        }
    }

    # Read updated script
    $updatedContent = Get-Content -Path $testCaptureFFUScript -Raw

    Test-Condition "Test 3.3: VMHostIPAddress replaced correctly" {
        $updatedContent -match [regex]::Escape("`$VMHostIPAddress = '$testIP'")
    }

    Test-Condition "Test 3.4: ShareName replaced correctly" {
        $updatedContent -match [regex]::Escape("`$ShareName = '$testShare'")
    }

    Test-Condition "Test 3.5: Username replaced correctly" {
        $updatedContent -match [regex]::Escape("`$UserName = '$testUser'")
    }

    Test-Condition "Test 3.6: Password replaced correctly" {
        $updatedContent -match [regex]::Escape("`$Password = '$testPassword'")
    }

    Test-Condition "Test 3.7: CustomFFUNameTemplate replaced correctly" {
        $updatedContent -match [regex]::Escape("`$CustomFFUNameTemplate = '$testTemplate'")
    }

    Test-Condition "Test 3.8: Backup file created" {
        $backupFiles = Get-ChildItem -Path $testCaptureFFUPath -Filter "CaptureFFU.ps1.backup-*"
        $backupFiles.Count -gt 0
    }

    Test-Condition "Test 3.9: Original script content preserved in backup" {
        $backupFiles = Get-ChildItem -Path $testCaptureFFUPath -Filter "CaptureFFU.ps1.backup-*" | Sort-Object LastWriteTime -Descending
        if ($backupFiles.Count -gt 0) {
            $backupContent = Get-Content -Path $backupFiles[0].FullName -Raw
            $backupContent -match [regex]::Escape("192.168.1.158")
        } else {
            $false
        }
    }

    Test-Condition "Test 3.10: Old placeholder values removed" {
        $updatedContent -notmatch [regex]::Escape("192.168.1.158") -and
        $updatedContent -notmatch [regex]::Escape("23202eb4-10c3-47e9-b389-f0c462663a23")
    }
}
finally {
    # Cleanup test environment
    if (Test-Path $testFFUDevPath) {
        Remove-Item -Path $testFFUDevPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "[INFO] Test environment cleaned up" -ForegroundColor Gray
    }
}

# ========== SECURESTRING PASSWORD TESTS ==========
Write-Host "`n========== SecureString Password Tests ==========" -ForegroundColor Cyan

# Create new test environment
$testFFUDevPath2 = Join-Path $env:TEMP "FFUBuilderTest2_$(Get-Date -Format 'yyyyMMddHHmmss')"
$testCaptureFFUPath2 = Join-Path $testFFUDevPath2 "WinPECaptureFFUFiles"
$testCaptureFFUScript2 = Join-Path $testCaptureFFUPath2 "CaptureFFU.ps1"

try {
    New-Item -Path $testCaptureFFUPath2 -ItemType Directory -Force | Out-Null
    Set-Content -Path $testCaptureFFUScript2 -Value $testScriptContent -Force

    $secureTestPassword = ConvertTo-SecureString -String "SecureTestPass456!" -AsPlainText -Force

    Test-Condition "Test 4.1: Function accepts SecureString password" {
        try {
            Update-CaptureFFUScript -VMHostIPAddress "10.0.0.200" `
                                   -ShareName "TestShare2" `
                                   -Username "test_user2" `
                                   -Password $secureTestPassword `
                                   -FFUDevelopmentPath $testFFUDevPath2 `
                                   -ErrorAction Stop
            $true
        }
        catch {
            Write-Host "  Error: $_" -ForegroundColor Yellow
            $false
        }
    }

    $updatedContent2 = Get-Content -Path $testCaptureFFUScript2 -Raw

    Test-Condition "Test 4.2: SecureString password converted and replaced correctly" {
        $updatedContent2 -match [regex]::Escape("`$Password = 'SecureTestPass456!'")
    }
}
finally {
    if (Test-Path $testFFUDevPath2) {
        Remove-Item -Path $testFFUDevPath2 -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ========== ERROR HANDLING TESTS ==========
Write-Host "`n========== Error Handling Tests ==========" -ForegroundColor Cyan

Test-Condition "Test 5.1: Function throws error when CaptureFFU.ps1 not found" -ShouldFail {
    Update-CaptureFFUScript -VMHostIPAddress "10.0.0.1" `
                           -ShareName "Test" `
                           -Username "test" `
                           -Password "pass" `
                           -FFUDevelopmentPath "C:\NonExistentPath"
    $false  # Should not reach here
}

# ========== BUILDFFUVM.PS1 INTEGRATION TESTS ==========
Write-Host "`n========== BuildFFUVM.ps1 Integration Tests ==========" -ForegroundColor Cyan

$buildFFUVMContent = Get-Content -Path $buildFFUVMPath -Raw

Test-Condition "Test 6.1: BuildFFUVM.ps1 generates password for capture user" {
    $buildFFUVMContent -match '\$capturePassword\s*=\s*-join.*Get-Random'
}

Test-Condition "Test 6.2: BuildFFUVM.ps1 converts password to SecureString" {
    $buildFFUVMContent -match '\$capturePasswordSecure\s*=\s*ConvertTo-SecureString.*\$capturePassword'
}

Test-Condition "Test 6.3: BuildFFUVM.ps1 passes password to Set-CaptureFFU" {
    $buildFFUVMContent -match 'Set-CaptureFFU.*-Password\s+\$capturePasswordSecure'
}

Test-Condition "Test 6.4: BuildFFUVM.ps1 calls Update-CaptureFFUScript" {
    $buildFFUVMContent -match 'Update-CaptureFFUScript'
}

Test-Condition "Test 6.5: Update-CaptureFFUScript called before New-PEMedia" {
    # Extract the section between Set-CaptureFFU and New-PEMedia
    $pattern = '(?s)Set-CaptureFFU.*?Update-CaptureFFUScript.*?New-PEMedia'
    $buildFFUVMContent -match $pattern
}

Test-Condition "Test 6.6: Update-CaptureFFUScript passes VMHostIPAddress parameter" {
    $buildFFUVMContent -match 'VMHostIPAddress\s*=\s*\$VMHostIPAddress'
}

Test-Condition "Test 6.7: Update-CaptureFFUScript passes ShareName parameter" {
    $buildFFUVMContent -match 'ShareName\s*=\s*\$ShareName'
}

Test-Condition "Test 6.8: Update-CaptureFFUScript passes Username parameter" {
    $buildFFUVMContent -match 'Username\s*=\s*\$Username'
}

Test-Condition "Test 6.9: Update-CaptureFFUScript passes plain text password" {
    $buildFFUVMContent -match 'Password\s*=\s*\$capturePassword'
}

Test-Condition "Test 6.10: Update-CaptureFFUScript passes FFUDevelopmentPath parameter" {
    $buildFFUVMContent -match 'FFUDevelopmentPath\s*=\s*\$FFUDevelopmentPath'
}

Test-Condition "Test 6.11: Update-CaptureFFUScript conditionally passes CustomFFUNameTemplate" {
    $buildFFUVMContent -match 'if.*CustomFFUNameTemplate.*CustomFFUNameTemplate\s*='
}

Test-Condition "Test 6.12: Update-CaptureFFUScript wrapped in CreateCaptureMedia conditional" {
    # Check that Update-CaptureFFUScript is inside the CreateCaptureMedia if block
    $pattern = '(?s)If\s*\(\$CreateCaptureMedia\).*?Update-CaptureFFUScript.*?New-PEMedia'
    $buildFFUVMContent -match $pattern
}

Test-Condition "Test 6.13: Update-CaptureFFUScript has error handling" {
    # Check for try-catch around Update-CaptureFFUScript
    $pattern = '(?s)try\s*\{.*?Update-CaptureFFUScript.*?\}\s*catch'
    $buildFFUVMContent -match $pattern
}

# ========== ACTUAL CAPTUREFFU.PS1 PLACEHOLDER TESTS ==========
Write-Host "`n========== Actual CaptureFFU.ps1 Placeholder Tests ==========" -ForegroundColor Cyan

$actualCaptureFFUContent = Get-Content -Path $captureFFUScriptPath -Raw

Test-Condition "Test 7.1: Actual CaptureFFU.ps1 has VMHostIPAddress placeholder" {
    $actualCaptureFFUContent -match '\$VMHostIPAddress\s*='
}

Test-Condition "Test 7.2: Actual CaptureFFU.ps1 has ShareName placeholder" {
    $actualCaptureFFUContent -match '\$ShareName\s*='
}

Test-Condition "Test 7.3: Actual CaptureFFU.ps1 has UserName placeholder" {
    $actualCaptureFFUContent -match '\$UserName\s*='
}

Test-Condition "Test 7.4: Actual CaptureFFU.ps1 has Password placeholder" {
    $actualCaptureFFUContent -match '\$Password\s*='
}

Test-Condition "Test 7.5: Actual CaptureFFU.ps1 uses VMHostIPAddress variable" {
    # Check that the variable is used in the script (not just defined)
    $lines = $actualCaptureFFUContent -split "`n"
    $definitionLine = ($lines | Select-String -Pattern '\$VMHostIPAddress\s*=' | Select-Object -First 1).LineNumber
    $usageLine = ($lines | Select-String -Pattern '\$VMHostIPAddress' | Where-Object LineNumber -ne $definitionLine | Select-Object -First 1)
    $null -ne $usageLine
}

# ========== CODE QUALITY TESTS ==========
Write-Host "`n========== Code Quality Tests ==========" -ForegroundColor Cyan

Test-Condition "Test 8.1: Update-CaptureFFUScript has comment-based help" {
    $help = Get-Help Update-CaptureFFUScript -ErrorAction SilentlyContinue
    $null -ne $help.Synopsis -and $help.Synopsis.Length -gt 10
}

Test-Condition "Test 8.2: Update-CaptureFFUScript logs operations" {
    $moduleContent = Get-Content -Path $ffuVMModulePath -Raw
    $functionStart = $moduleContent.IndexOf('function Update-CaptureFFUScript')
    $functionEnd = $moduleContent.IndexOf('Export-ModuleMember', $functionStart)
    $functionBody = $moduleContent.Substring($functionStart, $functionEnd - $functionStart)

    # Check for WriteLog calls
    ($functionBody -split 'WriteLog').Count -gt 5  # Should have multiple WriteLog statements
}

Test-Condition "Test 8.3: Update-CaptureFFUScript has error handling" {
    $moduleContent = Get-Content -Path $ffuVMModulePath -Raw
    $functionStart = $moduleContent.IndexOf('function Update-CaptureFFUScript')
    $functionEnd = $moduleContent.IndexOf('Export-ModuleMember', $functionStart)
    $functionBody = $moduleContent.Substring($functionStart, $functionEnd - $functionStart)

    $functionBody -match 'try\s*\{' -and $functionBody -match 'catch\s*\{'
}

Test-Condition "Test 8.4: Update-CaptureFFUScript validates input parameters" {
    $moduleContent = Get-Content -Path $ffuVMModulePath -Raw
    $functionStart = $moduleContent.IndexOf('function Update-CaptureFFUScript')
    $functionEnd = $moduleContent.IndexOf('Export-ModuleMember', $functionStart)
    $functionBody = $moduleContent.Substring($functionStart, $functionEnd - $functionStart)

    # Check for file path validation
    $functionBody -match 'Test-Path.*captureFFUScriptPath'
}

Test-Condition "Test 8.5: Password is redacted in logs" {
    $moduleContent = Get-Content -Path $ffuVMModulePath -Raw
    $functionStart = $moduleContent.IndexOf('function Update-CaptureFFUScript')
    $functionEnd = $moduleContent.IndexOf('Export-ModuleMember', $functionStart)
    $functionBody = $moduleContent.Substring($functionStart, $functionEnd - $functionStart)

    # Check that password is logged as REDACTED
    $functionBody -match 'Password:.*REDACTED'
}

# ========== TEST SUMMARY ==========
Write-Host "`n====================================================="
Write-Host "         TEST SUITE SUMMARY"
Write-Host "====================================================="
Write-Host "Total tests: $($testsPassed + $testsFailed + $testsSkipped)" -ForegroundColor White
Write-Host "Passed: $testsPassed" -ForegroundColor Green
Write-Host "Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -gt 0) { 'Red' } else { 'Green' })
Write-Host "Skipped: $testsSkipped" -ForegroundColor Yellow
$successRate = if (($testsPassed + $testsFailed) -gt 0) {
    [math]::Round(($testsPassed / ($testsPassed + $testsFailed)) * 100, 2)
} else { 0 }
Write-Host "Success rate: $successRate%" -ForegroundColor $(if ($successRate -ge 95) { 'Green' } elseif ($successRate -ge 80) { 'Yellow' } else { 'Red' })

$duration = (Get-Date) - $testStartTime
Write-Host "Duration: $($duration.TotalSeconds) seconds" -ForegroundColor Gray
Write-Host ""

if ($testsFailed -eq 0) {
    Write-Host "[SUCCESS] All tests passed! CaptureFFU script update fix is working correctly." -ForegroundColor Green
    exit 0
} else {
    Write-Host "[FAILURE] Some tests failed. Please review the issues above." -ForegroundColor Red
    exit 1
}
