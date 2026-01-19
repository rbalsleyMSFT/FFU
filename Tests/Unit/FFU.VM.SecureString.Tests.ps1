<#
.SYNOPSIS
    Pester tests for FFU.VM SecureString handling patterns

.DESCRIPTION
    Validates that FFU.VM module functions:
    1. Accept SecureString for Password parameters
    2. Contain proper BSTR cleanup patterns (ZeroFreeBSTR in finally blocks)
    3. Do not use insecure patterns like ConvertFrom-SecureString with -Key

.NOTES
    These tests validate SOURCE CODE patterns rather than runtime behavior,
    because testing actual SecureString memory behavior is complex and unreliable.
    The goal is to ensure secure coding patterns are maintained.
#>

BeforeAll {
    # Get path to FFU.VM module
    $script:ModulePath = Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules\FFU.VM\FFU.VM.psm1"

    # Verify module exists
    if (-not (Test-Path $script:ModulePath)) {
        throw "FFU.VM module not found at: $script:ModulePath"
    }

    # Read module content for pattern analysis
    $script:ModuleContent = Get-Content $script:ModulePath -Raw

    # Helper function to extract function content by name
    function Get-FunctionContent {
        param([string]$FunctionName)

        # Match from 'function Name' to next 'function' or 'Export-ModuleMember' or end
        $pattern = "function\s+$FunctionName\s*\{[\s\S]*?(?=\nfunction\s|\nExport-ModuleMember|\z)"
        $match = [regex]::Match($script:ModuleContent, $pattern)

        if ($match.Success) {
            return $match.Value
        }
        return $null
    }
}

Describe "FFU.VM SecureString Parameter Types" -Tag 'Security', 'SecureString' {

    Context "New-LocalUserAccount" {
        It "Has Password parameter of type SecureString" {
            $functionContent = Get-FunctionContent -FunctionName 'New-LocalUserAccount'
            $functionContent | Should -Not -BeNullOrEmpty

            # Check parameter block declares SecureString type
            $functionContent | Should -Match '\[SecureString\]\$Password'
        }
    }

    Context "Set-LocalUserPassword" {
        It "Has Password parameter of type SecureString" {
            $functionContent = Get-FunctionContent -FunctionName 'Set-LocalUserPassword'
            $functionContent | Should -Not -BeNullOrEmpty

            # Check parameter block declares SecureString type
            $functionContent | Should -Match '\[SecureString\]\$Password'
        }
    }

    Context "Set-CaptureFFU" {
        It "Has Password parameter of type SecureString" {
            $functionContent = Get-FunctionContent -FunctionName 'Set-CaptureFFU'
            $functionContent | Should -Not -BeNullOrEmpty

            # Check parameter block declares SecureString type
            $functionContent | Should -Match '\[SecureString\]\$Password'
        }
    }

    Context "Update-CaptureFFUScript" {
        It "Has Password parameter (accepts SecureString)" {
            $functionContent = Get-FunctionContent -FunctionName 'Update-CaptureFFUScript'
            $functionContent | Should -Not -BeNullOrEmpty

            # Update-CaptureFFUScript accepts $Password which can be string or SecureString
            # It checks the type at runtime: if ($Password -is [SecureString])
            $functionContent | Should -Match '\$Password'
            $functionContent | Should -Match '\$Password\s+-is\s+\[SecureString\]'
        }
    }
}

Describe "FFU.VM BSTR Cleanup Patterns" -Tag 'Security', 'SecureString' {

    Context "New-LocalUserAccount BSTR handling" {
        BeforeAll {
            $script:FunctionContent = Get-FunctionContent -FunctionName 'New-LocalUserAccount'
        }

        It "Converts SecureString using SecureStringToBSTR" {
            $script:FunctionContent | Should -Match 'SecureStringToBSTR'
        }

        It "Contains ZeroFreeBSTR cleanup" {
            $script:FunctionContent | Should -Match 'ZeroFreeBSTR'
        }

        It "Has finally block for guaranteed cleanup" {
            $script:FunctionContent | Should -Match 'finally\s*\{'
        }

        It "Nulls plainPassword variable after use" {
            $script:FunctionContent | Should -Match '\$plainPassword\s*=\s*\$null'
        }

        It "Contains SECURITY comment documenting pattern" {
            $script:FunctionContent | Should -Match '# SECURITY:'
        }
    }

    Context "Set-LocalUserPassword BSTR handling" {
        BeforeAll {
            $script:FunctionContent = Get-FunctionContent -FunctionName 'Set-LocalUserPassword'
        }

        It "Converts SecureString using SecureStringToBSTR" {
            $script:FunctionContent | Should -Match 'SecureStringToBSTR'
        }

        It "Contains ZeroFreeBSTR cleanup" {
            $script:FunctionContent | Should -Match 'ZeroFreeBSTR'
        }

        It "Has finally block for guaranteed cleanup" {
            $script:FunctionContent | Should -Match 'finally\s*\{'
        }

        It "Nulls plainPassword variable after use" {
            $script:FunctionContent | Should -Match '\$plainPassword\s*=\s*\$null'
        }

        It "Contains SECURITY comment documenting pattern" {
            $script:FunctionContent | Should -Match '# SECURITY:'
        }
    }

    Context "Update-CaptureFFUScript BSTR handling" {
        BeforeAll {
            $script:FunctionContent = Get-FunctionContent -FunctionName 'Update-CaptureFFUScript'
        }

        It "Converts SecureString using SecureStringToBSTR" {
            $script:FunctionContent | Should -Match 'SecureStringToBSTR'
        }

        It "Contains ZeroFreeBSTR cleanup" {
            $script:FunctionContent | Should -Match 'ZeroFreeBSTR'
        }

        It "Has finally block for guaranteed cleanup" {
            $script:FunctionContent | Should -Match 'finally\s*\{'
        }

        It "Nulls plainPassword variable after use" {
            $script:FunctionContent | Should -Match '\$plainPassword\s*=\s*\$null'
        }

        It "Contains SECURITY comment documenting pattern" {
            $script:FunctionContent | Should -Match '# SECURITY:'
        }
    }
}

Describe "FFU.VM No Insecure Patterns" -Tag 'Security', 'SecureString' {

    Context "Module-wide security checks" {

        It "Does not use ConvertFrom-SecureString with -Key (DPAPI export pattern)" {
            # ConvertFrom-SecureString with -Key exports to encrypted string using symmetric key
            # This is insecure for cross-machine scenarios and should not be used
            $script:ModuleContent | Should -Not -Match 'ConvertFrom-SecureString\s+-Key'
        }

        It "Does not use ConvertFrom-SecureString with -SecureKey (DPAPI export pattern)" {
            $script:ModuleContent | Should -Not -Match 'ConvertFrom-SecureString\s+-SecureKey'
        }

        It "Does not store passwords in plain text variables named insecurely" {
            # Check for obvious insecure naming patterns
            # Allowed: $plainPassword (in tight scope with cleanup)
            # Not allowed: $passwordText, $passwordString, $clearPassword, etc.
            $script:ModuleContent | Should -Not -Match '\$passwordText\s*='
            $script:ModuleContent | Should -Not -Match '\$passwordString\s*='
            $script:ModuleContent | Should -Not -Match '\$clearPassword\s*='
            $script:ModuleContent | Should -Not -Match '\$plaintextPassword\s*='
        }
    }
}

Describe "FFU.VM Secure Password Flow Documentation" -Tag 'Security', 'Documentation' {

    Context "Security documentation" {

        It "Contains documentation about WinPE plaintext requirement" {
            # Update-CaptureFFUScript must explain why plaintext is needed
            $functionContent = Get-FunctionContent -FunctionName 'Update-CaptureFFUScript'
            $functionContent | Should -Match 'WinPE'
        }

        It "Contains documentation about BSTR cleanup pattern" {
            $script:ModuleContent | Should -Match 'ZeroFreeBSTR'
            $script:ModuleContent | Should -Match 'BSTR'
        }

        It "Module header documents security considerations" {
            # Check module header contains security-relevant documentation
            $headerSection = $script:ModuleContent.Substring(0, [Math]::Min(2000, $script:ModuleContent.Length))
            # Module should mention Administrator privileges or security-relevant context
            $headerSection | Should -Match '(Administrator|security|credential)'
        }
    }
}
