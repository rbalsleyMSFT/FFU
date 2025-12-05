#Requires -Version 5.1
<#
.SYNOPSIS
    Tests the secure credential management functions in FFU.Core module.

.DESCRIPTION
    Validates the secure credential management functions including New-SecureRandomPassword,
    ConvertFrom-SecureStringToPlainText, Clear-PlainTextPassword, and Remove-SecureStringFromMemory.

.NOTES
    Version: 1.0.7
    Created for secure credential management validation
#>

param(
    [switch]$Verbose
)

$script:PassCount = 0
$script:FailCount = 0
$script:TestResults = @()

function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Message = ""
    )

    $script:TestResults += [PSCustomObject]@{
        TestName = $TestName
        Passed   = $Passed
        Message  = $Message
    }

    if ($Passed) {
        $script:PassCount++
        Write-Host "  [PASS] $TestName" -ForegroundColor Green
    } else {
        $script:FailCount++
        Write-Host "  [FAIL] $TestName" -ForegroundColor Red
        if ($Message) {
            Write-Host "         $Message" -ForegroundColor Yellow
        }
    }
}

# Set up module path
$FFUDevelopmentPath = Split-Path $PSScriptRoot -Parent
$ModulesPath = Join-Path $FFUDevelopmentPath "Modules"

if ($env:PSModulePath -notlike "*$ModulesPath*") {
    $env:PSModulePath = "$ModulesPath;$env:PSModulePath"
}

Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host "FFU Builder Secure Credential Management Test Suite" -ForegroundColor Cyan
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host ""

# =============================================================================
# Test 1: FFU.Core Module Export Verification
# =============================================================================
Write-Host "Testing FFU.Core Module Exports..." -ForegroundColor Yellow

try {
    Import-Module (Join-Path $ModulesPath "FFU.Core\FFU.Core.psd1") -Force -ErrorAction Stop

    $exportedFunctions = (Get-Module FFU.Core).ExportedFunctions.Keys

    Write-TestResult -TestName "FFU.Core module loads successfully" -Passed $true

    # Test for credential management functions
    $expectedFunctions = @(
        'New-SecureRandomPassword',
        'ConvertFrom-SecureStringToPlainText',
        'Clear-PlainTextPassword',
        'Remove-SecureStringFromMemory'
    )

    foreach ($func in $expectedFunctions) {
        $found = $func -in $exportedFunctions
        Write-TestResult -TestName "Function '$func' is exported" -Passed $found -Message $(if (-not $found) { "Function not found in exports" })
    }
}
catch {
    Write-TestResult -TestName "FFU.Core module loads successfully" -Passed $false -Message $_.Exception.Message
}

# =============================================================================
# Test 2: New-SecureRandomPassword Basic Functionality
# =============================================================================
Write-Host ""
Write-Host "Testing New-SecureRandomPassword Function..." -ForegroundColor Yellow

try {
    # Test default parameters (32 characters with special chars)
    $securePassword = New-SecureRandomPassword

    Write-TestResult -TestName "New-SecureRandomPassword returns SecureString" -Passed ($securePassword -is [SecureString])
    Write-TestResult -TestName "Generated password is read-only" -Passed $securePassword.IsReadOnly()

    # Convert to plain text to verify length (then dispose)
    $plainText = ConvertFrom-SecureStringToPlainText -SecureString $securePassword
    Write-TestResult -TestName "Default length is 32 characters" -Passed ($plainText.Length -eq 32)
    $plainText = $null

    $securePassword.Dispose()
}
catch {
    Write-TestResult -TestName "New-SecureRandomPassword returns SecureString" -Passed $false -Message $_.Exception.Message
}

# =============================================================================
# Test 3: New-SecureRandomPassword Custom Length
# =============================================================================
Write-Host ""
Write-Host "Testing Custom Password Lengths..." -ForegroundColor Yellow

try {
    # Test minimum length (16)
    $shortPassword = New-SecureRandomPassword -Length 16
    $shortPlain = ConvertFrom-SecureStringToPlainText -SecureString $shortPassword
    Write-TestResult -TestName "Minimum length (16) works" -Passed ($shortPlain.Length -eq 16)
    $shortPlain = $null
    $shortPassword.Dispose()

    # Test maximum length (128)
    $longPassword = New-SecureRandomPassword -Length 128
    $longPlain = ConvertFrom-SecureStringToPlainText -SecureString $longPassword
    Write-TestResult -TestName "Maximum length (128) works" -Passed ($longPlain.Length -eq 128)
    $longPlain = $null
    $longPassword.Dispose()

    # Test custom length (20)
    $customPassword = New-SecureRandomPassword -Length 20
    $customPlain = ConvertFrom-SecureStringToPlainText -SecureString $customPassword
    Write-TestResult -TestName "Custom length (20) works" -Passed ($customPlain.Length -eq 20)
    $customPlain = $null
    $customPassword.Dispose()
}
catch {
    Write-TestResult -TestName "Custom length tests" -Passed $false -Message $_.Exception.Message
}

# =============================================================================
# Test 4: New-SecureRandomPassword Character Sets
# =============================================================================
Write-Host ""
Write-Host "Testing Password Character Sets..." -ForegroundColor Yellow

try {
    # Test with special characters (default)
    $withSpecial = New-SecureRandomPassword -Length 64 -IncludeSpecialChars $true
    $withSpecialPlain = ConvertFrom-SecureStringToPlainText -SecureString $withSpecial
    $hasSpecial = $withSpecialPlain -match '[!@#$%^&*\-_]'
    Write-TestResult -TestName "Password with special chars contains special chars" -Passed $hasSpecial
    $withSpecialPlain = $null
    $withSpecial.Dispose()

    # Test without special characters
    $noSpecial = New-SecureRandomPassword -Length 64 -IncludeSpecialChars $false
    $noSpecialPlain = ConvertFrom-SecureStringToPlainText -SecureString $noSpecial
    $hasNoSpecial = $noSpecialPlain -notmatch '[!@#$%^&*\-_]'
    Write-TestResult -TestName "Password without special chars has no special chars" -Passed $hasNoSpecial

    # Verify alphanumeric only
    $isAlphanumeric = $noSpecialPlain -match '^[a-zA-Z0-9]+$'
    Write-TestResult -TestName "Password without special chars is alphanumeric only" -Passed $isAlphanumeric
    $noSpecialPlain = $null
    $noSpecial.Dispose()
}
catch {
    Write-TestResult -TestName "Character set tests" -Passed $false -Message $_.Exception.Message
}

# =============================================================================
# Test 5: Password Uniqueness (Randomness Verification)
# =============================================================================
Write-Host ""
Write-Host "Testing Password Randomness..." -ForegroundColor Yellow

try {
    # Generate multiple passwords and verify they're unique
    $passwords = @()
    for ($i = 0; $i -lt 10; $i++) {
        $pw = New-SecureRandomPassword -Length 32
        $plain = ConvertFrom-SecureStringToPlainText -SecureString $pw
        $passwords += $plain
        $plain = $null
        $pw.Dispose()
    }

    $uniquePasswords = $passwords | Select-Object -Unique
    Write-TestResult -TestName "10 generated passwords are all unique" -Passed ($uniquePasswords.Count -eq 10)

    # Clear passwords array
    $passwords = $null
}
catch {
    Write-TestResult -TestName "Randomness verification" -Passed $false -Message $_.Exception.Message
}

# =============================================================================
# Test 6: ConvertFrom-SecureStringToPlainText Function
# =============================================================================
Write-Host ""
Write-Host "Testing ConvertFrom-SecureStringToPlainText Function..." -ForegroundColor Yellow

try {
    # Create a known SecureString by building it character by character
    # This avoids ConvertTo-SecureString which has environment issues
    $knownChars = "TestPassword123!".ToCharArray()
    $knownSecure = New-Object System.Security.SecureString
    foreach ($char in $knownChars) {
        $knownSecure.AppendChar($char)
    }
    $knownSecure.MakeReadOnly()

    # Convert back and verify
    $converted = ConvertFrom-SecureStringToPlainText -SecureString $knownSecure
    Write-TestResult -TestName "Conversion preserves original value" -Passed ($converted -eq "TestPassword123!")

    # Clean up
    $converted = $null
    $knownSecure.Dispose()
}
catch {
    Write-TestResult -TestName "SecureString conversion" -Passed $false -Message $_.Exception.Message
}

# =============================================================================
# Test 7: Clear-PlainTextPassword Function
# =============================================================================
Write-Host ""
Write-Host "Testing Clear-PlainTextPassword Function..." -ForegroundColor Yellow

try {
    $testPassword = "SensitivePassword123!"

    # Verify variable has value before clearing
    $hasValueBefore = -not [string]::IsNullOrEmpty($testPassword)

    # Clear the password
    Clear-PlainTextPassword -PasswordVariable ([ref]$testPassword)

    # Verify variable is null after clearing
    $isNullAfter = $null -eq $testPassword

    Write-TestResult -TestName "Variable has value before Clear-PlainTextPassword" -Passed $hasValueBefore
    Write-TestResult -TestName "Variable is null after Clear-PlainTextPassword" -Passed $isNullAfter
}
catch {
    Write-TestResult -TestName "Clear-PlainTextPassword" -Passed $false -Message $_.Exception.Message
}

# =============================================================================
# Test 8: Remove-SecureStringFromMemory Function
# =============================================================================
Write-Host ""
Write-Host "Testing Remove-SecureStringFromMemory Function..." -ForegroundColor Yellow

try {
    # Create SecureString by building it character by character (avoids ConvertTo-SecureString issues)
    $testSecure = New-Object System.Security.SecureString
    foreach ($char in "TestPassword".ToCharArray()) {
        $testSecure.AppendChar($char)
    }

    # Verify variable has value before removal
    $hasValueBefore = $null -ne $testSecure -and $testSecure -is [SecureString]

    # Remove the SecureString
    Remove-SecureStringFromMemory -SecureStringVariable ([ref]$testSecure)

    # Verify variable is null after removal
    $isNullAfter = $null -eq $testSecure

    Write-TestResult -TestName "SecureString exists before Remove-SecureStringFromMemory" -Passed $hasValueBefore
    Write-TestResult -TestName "SecureString is null after Remove-SecureStringFromMemory" -Passed $isNullAfter
}
catch {
    Write-TestResult -TestName "Remove-SecureStringFromMemory" -Passed $false -Message $_.Exception.Message
}

# =============================================================================
# Test 9: Error Handling - Invalid Length
# =============================================================================
Write-Host ""
Write-Host "Testing Error Handling..." -ForegroundColor Yellow

try {
    # Test length below minimum (should fail validation)
    $caughtError = $false
    try {
        $tooShort = New-SecureRandomPassword -Length 5
    }
    catch {
        $caughtError = $true
    }
    Write-TestResult -TestName "Rejects password length below minimum (5)" -Passed $caughtError

    # Test length above maximum (should fail validation)
    $caughtError = $false
    try {
        $tooLong = New-SecureRandomPassword -Length 200
    }
    catch {
        $caughtError = $true
    }
    Write-TestResult -TestName "Rejects password length above maximum (200)" -Passed $caughtError
}
catch {
    Write-TestResult -TestName "Error handling tests" -Passed $false -Message $_.Exception.Message
}

# =============================================================================
# Test 10: Integration - Full Secure Credential Lifecycle
# =============================================================================
Write-Host ""
Write-Host "Testing Full Secure Credential Lifecycle..." -ForegroundColor Yellow

try {
    # Step 1: Generate secure password
    $securePassword = New-SecureRandomPassword -Length 24 -IncludeSpecialChars $false
    Write-TestResult -TestName "Step 1: Generate secure password" -Passed ($null -ne $securePassword)

    # Step 2: Convert to plain text only when needed
    $plainText = ConvertFrom-SecureStringToPlainText -SecureString $securePassword
    Write-TestResult -TestName "Step 2: Convert to plain text" -Passed ($plainText.Length -eq 24)

    # Step 3: Use the plain text (simulate writing to script file)
    $simulatedUse = "Password=$plainText"
    Write-TestResult -TestName "Step 3: Use plain text" -Passed ($simulatedUse.Contains($plainText))

    # Step 4: Clear plain text immediately after use
    Clear-PlainTextPassword -PasswordVariable ([ref]$plainText)
    Write-TestResult -TestName "Step 4: Clear plain text after use" -Passed ($null -eq $plainText)

    # Step 5: Dispose SecureString when done
    Remove-SecureStringFromMemory -SecureStringVariable ([ref]$securePassword)
    Write-TestResult -TestName "Step 5: Dispose SecureString" -Passed ($null -eq $securePassword)

    # Clear simulated use variable
    $simulatedUse = $null
}
catch {
    Write-TestResult -TestName "Full lifecycle test" -Passed $false -Message $_.Exception.Message
}

# =============================================================================
# Test Summary
# =============================================================================
Write-Host ""
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host "Total Tests: $($script:PassCount + $script:FailCount)" -ForegroundColor White
Write-Host "Passed: $script:PassCount" -ForegroundColor Green
Write-Host "Failed: $script:FailCount" -ForegroundColor $(if ($script:FailCount -gt 0) { "Red" } else { "Green" })
Write-Host ""

if ($script:FailCount -eq 0) {
    Write-Host "All tests passed!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "Some tests failed. Please review the results above." -ForegroundColor Red
    exit 1
}
