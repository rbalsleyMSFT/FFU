#Requires -Module Pester
<#
.SYNOPSIS
    Pester tests to ensure BuildFFUVM_UI.ps1 avoids direct enum type references.

.DESCRIPTION
    PowerShell enums defined in modules (like FFUMessageLevel in FFU.Messaging) are NOT
    automatically exported when using Import-Module. They are only accessible via:
    - 'using module' statement at parse-time (not runtime)
    - String comparisons (ToString())

    This test suite ensures that BuildFFUVM_UI.ps1 uses string comparisons instead of
    direct enum type references to avoid "Unable to find type" errors at runtime.

.NOTES
    Version: 1.0.0
    Date: 2025-12-10
    Author: FFU Builder Team
    Related Issue: "Unable to find type [FFUMessageLevel]" error in timer tick handler
#>

BeforeAll {
    # Set up paths
    $script:FFUDevelopmentPath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:BuildFFUVMUIPath = Join-Path $script:FFUDevelopmentPath 'FFUDevelopment\BuildFFUVM_UI.ps1'
    $script:MessagingModulePath = Join-Path $script:FFUDevelopmentPath 'FFUDevelopment\Modules\FFU.Messaging'

    # Read file contents for static analysis
    $script:UIContent = Get-Content -Path $script:BuildFFUVMUIPath -Raw
    $script:UILines = Get-Content -Path $script:BuildFFUVMUIPath
}

Describe 'BuildFFUVM_UI.ps1 Enum Type Avoidance' -Tag 'EnumType', 'ModuleExport' {

    Context 'No Direct Enum Type Usage in Executable Code' {

        It 'Should NOT use [FFUMessageLevel]:: in executable code' {
            # Find all lines with [FFUMessageLevel]:: that are NOT comments
            $enumUsageLines = $script:UILines | Where-Object {
                $_ -match '\[FFUMessageLevel\]::' -and
                $_ -notmatch '^\s*#' -and           # Not a comment line
                $_ -notmatch '#.*\[FFUMessageLevel\]'  # Not in a trailing comment
            }
            $enumUsageLines.Count | Should -Be 0 -Because @"
PowerShell enums from modules are not exported via Import-Module.
Found enum usage on lines that are not comments.
Use string comparison instead: `$msg.Level.ToString() -eq 'Progress'
"@
        }

        It 'Should NOT use [FFUBuildState]:: in executable code' {
            # Check for any other enum types from FFU.Messaging
            $enumUsageLines = $script:UILines | Where-Object {
                $_ -match '\[FFUBuildState\]::' -and
                $_ -notmatch '^\s*#' -and
                $_ -notmatch '#.*\[FFUBuildState\]'
            }
            $enumUsageLines.Count | Should -Be 0 -Because "FFUBuildState enum is also not exported via Import-Module"
        }

        It 'Should NOT use [FFUMessage]:: for type casting in executable code' {
            $classUsageLines = $script:UILines | Where-Object {
                $_ -match '\[FFUMessage\]' -and
                $_ -notmatch '^\s*#' -and
                $_ -notmatch '#.*\[FFUMessage\]'
            }
            $classUsageLines.Count | Should -Be 0 -Because "FFUMessage class is also not exported via Import-Module"
        }
    }

    Context 'String Comparison Pattern Used' {

        It 'Should use ToString() for Level comparison' {
            $script:UIContent | Should -Match '\$msg\.Level\.ToString\(\)' -Because "Level should be compared as string"
        }

        It 'Should compare against Progress string value' {
            $script:UIContent | Should -Match "-eq\s+'Progress'" -Because "Should compare against 'Progress' string"
        }

        It 'Should have explanatory comment about enum avoidance' {
            $script:UIContent | Should -Match 'string comparison.*enum|enum.*not exported|Import-Module' -Because "Code should explain why string comparison is used"
        }
    }

    Context 'Module Import Pattern' {

        It 'Should use Import-Module for FFU.Messaging (not using module)' {
            $script:UIContent | Should -Match 'Import-Module.*FFU\.Messaging'
            # Verify we're NOT using 'using module' (which would require it at the very top)
            $firstLines = ($script:UILines | Select-Object -First 30) -join "`n"
            $firstLines | Should -Not -Match 'using module.*FFU\.Messaging'
        }

        It 'Should import FFU.Messaging with -DisableNameChecking' {
            $script:UIContent | Should -Match 'Import-Module.*FFU\.Messaging.*-DisableNameChecking'
        }
    }
}

Describe 'FFU.Messaging Module Enum Definition' -Tag 'EnumType', 'Module' {

    Context 'Enum Structure Verification' {

        BeforeAll {
            $script:MessagingContent = Get-Content -Path (Join-Path $script:MessagingModulePath 'FFU.Messaging.psm1') -Raw
        }

        It 'FFUMessageLevel enum should exist in module' {
            $script:MessagingContent | Should -Match 'enum FFUMessageLevel'
        }

        It 'FFUMessageLevel should include Progress value' {
            $script:MessagingContent | Should -Match 'Progress\s*='
        }

        It 'FFUMessage class should use FFUMessageLevel for Level property' {
            $script:MessagingContent | Should -Match '\[FFUMessageLevel\]\$Level'
        }
    }

    Context 'Runtime Behavior Verification' {

        BeforeAll {
            Import-Module $script:MessagingModulePath -Force -DisableNameChecking -ErrorAction Stop
        }

        AfterAll {
            Remove-Module 'FFU.Messaging' -Force -ErrorAction SilentlyContinue
        }

        It 'Message Level should be convertible to string' {
            $context = New-FFUMessagingContext
            Write-FFUInfo -Context $context -Message "Test"
            $messages = Read-FFUMessages -Context $context -MaxMessages 1

            $messages.Count | Should -Be 1
            $messages[0].Level.ToString() | Should -BeOfType [string]
        }

        It 'Progress message Level.ToString() should equal "Progress"' {
            $context = New-FFUMessagingContext
            Write-FFUProgress -Context $context -Activity "Testing" -PercentComplete 50
            $messages = Read-FFUMessages -Context $context -MaxMessages 1

            $messages.Count | Should -Be 1
            $messages[0].Level.ToString() | Should -Be 'Progress'
        }

        It 'String comparison should work for message filtering' {
            $context = New-FFUMessagingContext

            # Write different message types
            Write-FFUInfo -Context $context -Message "Info message"
            Write-FFUProgress -Context $context -Activity "Progress" -PercentComplete 25
            Write-FFUWarning -Context $context -Message "Warning message"
            Write-FFUProgress -Context $context -Activity "More Progress" -PercentComplete 50

            $messages = Read-FFUMessages -Context $context -MaxMessages 10

            # Filter using string comparison (same as UI code)
            $progressMessages = $messages | Where-Object { $_.Level.ToString() -eq 'Progress' }

            $progressMessages.Count | Should -Be 2 -Because "Should find both progress messages via string comparison"
        }
    }
}

Describe 'Prevention of Future Enum Type Usage' -Tag 'EnumType', 'Regression' {

    Context 'Code Pattern Enforcement' {

        It 'Any mention of [FFUMessageLevel] should be in comments only' {
            $nonCommentMatches = $script:UILines | Where-Object {
                $_ -match '\[FFUMessageLevel\]' -and
                $_ -notmatch '^\s*#' -and
                $_ -notmatch '#.*\[FFUMessageLevel\]'
            }

            if ($nonCommentMatches.Count -gt 0) {
                $lineNumbers = @()
                for ($i = 0; $i -lt $script:UILines.Count; $i++) {
                    if ($script:UILines[$i] -match '\[FFUMessageLevel\]' -and
                        $script:UILines[$i] -notmatch '^\s*#' -and
                        $script:UILines[$i] -notmatch '#.*\[FFUMessageLevel\]') {
                        $lineNumbers += ($i + 1)
                    }
                }
                Write-Warning "Found [FFUMessageLevel] in executable code at lines: $($lineNumbers -join ', ')"
            }

            $nonCommentMatches.Count | Should -Be 0 -Because @"
[FFUMessageLevel] enum type cannot be used directly because it's not exported via Import-Module.
Use string comparison: `$msg.Level.ToString() -eq 'Progress'
"@
        }

        It 'Documentation comment should explain the workaround' {
            $script:UIContent | Should -Match 'not exported via Import-Module|would require.*using module|parse-time'
        }
    }
}
