#Requires -Modules Pester
<#
.SYNOPSIS
    Unit tests for BuildFFUVM.ps1 cancellation checkpoint implementation.

.DESCRIPTION
    Verifies that BuildFFUVM.ps1 contains the required cancellation checkpoints
    at phase boundaries, using source code pattern analysis. Tests validate:
    - Checkpoint count (minimum 8)
    - Checkpoint pattern compliance (-InvokeCleanup, -PhaseName, -MessagingContext)
    - Required phase coverage
    - Cleanup registry finalization

.NOTES
    These tests use source code analysis rather than execution to verify
    implementation patterns without requiring full build environment.
#>

BeforeAll {
    $script:BuildScriptPath = "$PSScriptRoot/../../FFUDevelopment/BuildFFUVM.ps1"

    if (-not (Test-Path $script:BuildScriptPath)) {
        throw "BuildFFUVM.ps1 not found at: $script:BuildScriptPath"
    }

    $script:BuildScriptContent = Get-Content -Path $script:BuildScriptPath -Raw
}

Describe 'BuildFFUVM.ps1 Cancellation Implementation' {

    Context 'Cancellation Checkpoint Count' {
        It 'Contains at least 8 Test-BuildCancellation calls' {
            $matches = [regex]::Matches($script:BuildScriptContent, 'Test-BuildCancellation\s+-MessagingContext')
            $matches.Count | Should -BeGreaterOrEqual 8 -Because 'At least 8 cancellation checkpoints should exist at major phase boundaries'
        }
    }

    Context 'Cancellation Checkpoint Pattern Compliance' {
        BeforeAll {
            # Extract all checkpoint patterns (multiline to capture full call)
            $script:CheckpointPattern = 'if\s*\(\s*Test-BuildCancellation[^)]+\)'
            $script:CheckpointMatches = [regex]::Matches($script:BuildScriptContent, $script:CheckpointPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
        }

        It 'All checkpoints use -InvokeCleanup switch' {
            foreach ($cp in $script:CheckpointMatches) {
                $cp.Value | Should -Match '-InvokeCleanup' -Because "All checkpoints should trigger cleanup on cancellation"
            }
        }

        It 'All checkpoints specify -PhaseName parameter' {
            foreach ($cp in $script:CheckpointMatches) {
                $cp.Value | Should -Match '-PhaseName' -Because "All checkpoints should identify their phase"
            }
        }

        It 'All checkpoints pass -MessagingContext parameter' {
            foreach ($cp in $script:CheckpointMatches) {
                $cp.Value | Should -Match '-MessagingContext\s+\$MessagingContext' -Because "All checkpoints should use the script MessagingContext variable"
            }
        }
    }

    Context 'Checkpoint Control Flow' {
        It 'Checkpoints are followed by return statements within braces' {
            # Pattern: if (Test-BuildCancellation...) { ... return }
            $pattern = 'if\s*\(\s*Test-BuildCancellation[^)]+\)\s*\{[^}]*return[^}]*\}'
            $matches = [regex]::Matches($script:BuildScriptContent, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
            $matches.Count | Should -BeGreaterOrEqual 8 -Because 'Checkpoints should exit on cancellation'
        }

        It 'Checkpoints log cancellation before returning' {
            # Pattern: WriteLog with cancellation message before return
            $pattern = 'if\s*\(\s*Test-BuildCancellation[^)]+\)\s*\{[^}]*WriteLog[^}]*cancel[^}]*return'
            $matches = [regex]::Matches($script:BuildScriptContent, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            $matches.Count | Should -BeGreaterOrEqual 8 -Because 'Checkpoints should log before exiting'
        }
    }

    Context 'Required Phase Checkpoints' {
        It 'Has checkpoint for Pre-flight Validation phase' {
            $script:BuildScriptContent | Should -Match 'Test-BuildCancellation.*PhaseName\s*=?\s*[''"]Pre-flight' -Because 'Pre-flight validation should have a cancellation checkpoint'
        }

        It 'Has checkpoint for Driver Download phase' {
            $script:BuildScriptContent | Should -Match 'Test-BuildCancellation.*PhaseName\s*=?\s*[''"]Driver' -Because 'Driver download should have a cancellation checkpoint'
        }

        It 'Has checkpoint for VHDX Creation phase' {
            $script:BuildScriptContent | Should -Match 'Test-BuildCancellation.*PhaseName\s*=?\s*[''"]VHDX' -Because 'VHDX creation should have a cancellation checkpoint'
        }

        It 'Has checkpoint for VM Setup phase' {
            $script:BuildScriptContent | Should -Match 'Test-BuildCancellation.*PhaseName\s*=?\s*[''"]VM Setup' -Because 'VM setup should have a cancellation checkpoint'
        }

        It 'Has checkpoint for VM Start phase' {
            $script:BuildScriptContent | Should -Match 'Test-BuildCancellation.*PhaseName\s*=?\s*[''"]VM Start' -Because 'VM start should have a cancellation checkpoint'
        }

        It 'Has checkpoint for FFU Capture phase' {
            $script:BuildScriptContent | Should -Match 'Test-BuildCancellation.*PhaseName\s*=?\s*[''"]FFU Capture' -Because 'FFU capture should have a cancellation checkpoint'
        }

        It 'Has checkpoint for Deployment Media phase' {
            $script:BuildScriptContent | Should -Match 'Test-BuildCancellation.*PhaseName\s*=?\s*[''"]Deployment Media' -Because 'Deployment media creation should have a cancellation checkpoint'
        }

        It 'Has checkpoint for USB Drive Creation phase' {
            $script:BuildScriptContent | Should -Match 'Test-BuildCancellation.*PhaseName\s*=?\s*[''"]USB Drive' -Because 'USB drive creation should have a cancellation checkpoint'
        }
    }

    Context 'Cleanup Registry Finalization' {
        It 'Calls Clear-CleanupRegistry on successful completion' {
            $script:BuildScriptContent | Should -Match 'Clear-CleanupRegistry' -Because 'Cleanup registry should be cleared after successful build'
        }

        It 'Clear-CleanupRegistry is called near end of script' {
            # Find the position of Clear-CleanupRegistry
            $clearMatch = [regex]::Match($script:BuildScriptContent, 'Clear-CleanupRegistry')
            $clearPosition = $clearMatch.Index
            $scriptLength = $script:BuildScriptContent.Length

            # Should be in the last 5% of the script
            $percentPosition = ($clearPosition / $scriptLength) * 100
            $percentPosition | Should -BeGreaterThan 95 -Because 'Clear-CleanupRegistry should be near end of successful execution path'
        }
    }

    Context 'Resource Cleanup Registration' {
        It 'Registers VM for cleanup' {
            $script:BuildScriptContent | Should -Match 'Register-VMCleanup' -Because 'VM resources should be registered for cleanup'
        }

        It 'Registers VHDX for cleanup' {
            $script:BuildScriptContent | Should -Match 'Register-VHDXCleanup' -Because 'VHDX files should be registered for cleanup'
        }

        It 'Has at least 3 Register-*Cleanup calls' {
            $matches = [regex]::Matches($script:BuildScriptContent, 'Register-\w+Cleanup')
            $matches.Count | Should -BeGreaterOrEqual 3 -Because 'Multiple resources should be registered for cleanup'
        }
    }

    Context 'Checkpoint Comment Documentation' {
        It 'Checkpoints have descriptive comments' {
            # Each checkpoint should have a comment header
            $pattern = '#\s*===\s*CANCELLATION CHECKPOINT\s*\d+:'
            $matches = [regex]::Matches($script:BuildScriptContent, $pattern)
            $matches.Count | Should -BeGreaterOrEqual 8 -Because 'Each checkpoint should have a numbered comment header'
        }
    }
}
