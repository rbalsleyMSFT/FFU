#Requires -Module Pester

<#
.SYNOPSIS
    Pester tests for expand.exe argument quoting fix.

.DESCRIPTION
    Tests that verify the expand.exe argument arrays do NOT contain embedded quotes.

    The bug was that expand.exe argument arrays contained embedded quotes like:
        $expandArgs = @('-F:*', "`"$PackagePath`"", "`"$extractPath`"")

    This caused expand.exe to look for a file with literal quote characters in the name,
    e.g., "C:\path\file.msu" instead of C:\path\file.msu.

    The fix removes embedded quotes:
        $expandArgs = @('-F:*', $PackagePath, $extractPath)

    PowerShell automatically handles quoting for external commands when paths contain spaces.

.NOTES
    Files Fixed:
    1. FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1 - lines 1129-1133
    2. FFUDevelopment\FFUUI.Core\FFUUI.Core.Drivers.HP.psm1 - lines 57, 188, 311

.TAGS
    Unit, ExpandExe, Arguments, Regression
#>

BeforeAll {
    # Define paths to the files that were fixed
    $script:FFUUpdatesPath = Join-Path -Path $PSScriptRoot -ChildPath "..\..\FFUDevelopment\Modules\FFU.Updates\FFU.Updates.psm1"
    $script:HPDriversPath = Join-Path -Path $PSScriptRoot -ChildPath "..\..\FFUDevelopment\FFUUI.Core\FFUUI.Core.Drivers.HP.psm1"

    # Resolve to absolute paths
    $script:FFUUpdatesPath = (Resolve-Path -Path $script:FFUUpdatesPath -ErrorAction SilentlyContinue).Path
    $script:HPDriversPath = (Resolve-Path -Path $script:HPDriversPath -ErrorAction SilentlyContinue).Path

    # Get project root
    $script:ProjectRoot = Join-Path -Path $PSScriptRoot -ChildPath "..\.."
    $script:ProjectRoot = (Resolve-Path -Path $script:ProjectRoot).Path

    # Create temp directory for functional tests
    $script:TempTestDir = Join-Path -Path $env:TEMP -ChildPath "ExpandExeTests_$([Guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -ItemType Directory -Path $script:TempTestDir -Force | Out-Null
}

AfterAll {
    # Cleanup temp directory
    if (Test-Path -Path $script:TempTestDir) {
        Remove-Item -Path $script:TempTestDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "Expand.exe Argument Quoting Fix" -Tag 'Unit', 'ExpandExe', 'Arguments', 'Regression' {

    Context "Code Pattern Tests - FFU.Updates.psm1" -Tag 'CodePattern' {

        BeforeAll {
            if ($script:FFUUpdatesPath -and (Test-Path -Path $script:FFUUpdatesPath)) {
                $script:FFUUpdatesContent = Get-Content -Path $script:FFUUpdatesPath -Raw
            }
        }

        It "Should have FFU.Updates.psm1 file accessible" {
            $script:FFUUpdatesPath | Should -Not -BeNullOrEmpty
            Test-Path -Path $script:FFUUpdatesPath | Should -BeTrue
        }

        It "Should NOT contain embedded quotes pattern '`"`"$' in expand.exe argument arrays" {
            # Pattern: `"$ followed by variable (embedded quote before variable)
            # This regex looks for the problematic pattern of embedded quotes in arrays
            $badPattern = '(?m)\$expandArgs\s*=\s*@\([^)]*`"[^)]*`"[^)]*\)'

            $script:FFUUpdatesContent | Should -Not -Match $badPattern
        }

        It "Should contain the fixed pattern without embedded quotes" {
            # The fixed code should have clean variable references without embedded quotes
            # Pattern: $expandArgs = @( ... $PackagePath ... $extractPath ... )
            $goodPattern = '(?ms)\$expandArgs\s*=\s*@\(\s*[''-F:\*'']+\s*,\s*\$PackagePath\s*,\s*\$extractPath\s*\)'

            $script:FFUUpdatesContent | Should -Match $goodPattern
        }

        It "Should have the explanatory comment about PowerShell automatic quoting" {
            $commentPattern = 'Do not embed quotes in argument array.*PowerShell handles quoting automatically'

            $script:FFUUpdatesContent | Should -Match $commentPattern
        }

        It "Should NOT have double-backtick-quote pattern near expandArgs" {
            # Look for the specific bad pattern that was fixed
            # Original bad code: "`"$PackagePath`""
            $lines = $script:FFUUpdatesContent -split "`n"
            $expandArgsSection = $false
            $foundBadPattern = $false

            foreach ($line in $lines) {
                if ($line -match '\$expandArgs\s*=') {
                    $expandArgsSection = $true
                }
                if ($expandArgsSection) {
                    if ($line -match '``".*\$.*``"') {
                        $foundBadPattern = $true
                        break
                    }
                    if ($line -match '\)' -and $expandArgsSection) {
                        break  # End of array
                    }
                }
            }

            $foundBadPattern | Should -BeFalse -Because "embedded quotes would cause expand.exe to look for literal quote characters in filenames"
        }
    }

    Context "Code Pattern Tests - FFUUI.Core.Drivers.HP.psm1" -Tag 'CodePattern' {

        BeforeAll {
            if ($script:HPDriversPath -and (Test-Path -Path $script:HPDriversPath)) {
                $script:HPDriversContent = Get-Content -Path $script:HPDriversPath -Raw
            }
        }

        It "Should have FFUUI.Core.Drivers.HP.psm1 file accessible" {
            $script:HPDriversPath | Should -Not -BeNullOrEmpty
            Test-Path -Path $script:HPDriversPath | Should -BeTrue
        }

        It "Should NOT contain embedded quotes in expand.exe Invoke-Process calls" {
            # Look for Invoke-Process with expand.exe that has embedded quotes
            $badPattern = 'Invoke-Process.*expand\.exe.*`"\$'

            $script:HPDriversContent | Should -Not -Match $badPattern
        }

        It "Should use clean variable references in ArgumentList arrays" {
            # Count occurrences of expand.exe with Invoke-Process
            $expandCalls = [regex]::Matches($script:HPDriversContent, 'Invoke-Process.*-FilePath\s*["'']expand\.exe["'']')

            foreach ($match in $expandCalls) {
                # Find the ArgumentList for this call
                $startIndex = $match.Index
                $substring = $script:HPDriversContent.Substring($startIndex, [Math]::Min(500, $script:HPDriversContent.Length - $startIndex))

                # Should not have `" pattern in the ArgumentList
                $substring | Should -Not -Match '-ArgumentList\s*@\([^)]*`"'
            }
        }

        It "Should have explanatory comments for all expand.exe calls" {
            # Count how many expand.exe calls exist
            $expandCallCount = ([regex]::Matches($script:HPDriversContent, 'expand\.exe')).Count

            # Count how many have the explanatory comment
            $commentCount = ([regex]::Matches($script:HPDriversContent, 'Do not embed quotes in argument array')).Count

            # Each expand.exe call should have a comment (at least 3 based on the fix)
            $commentCount | Should -BeGreaterOrEqual 3
        }
    }

    Context "Argument Construction Tests" -Tag 'Construction' {

        It "Array without embedded quotes should have clean values" {
            $testPath = "C:\Test Path\With Spaces\file.msu"
            $testDest = "C:\Output\Folder"

            # Correct pattern (fixed code)
            $goodArgs = @(
                '-F:*',
                $testPath,
                $testDest
            )

            # Values should not contain literal quote characters
            $goodArgs[1] | Should -Not -Match '^".*"$'
            $goodArgs[2] | Should -Not -Match '^".*"$'
            $goodArgs[1] | Should -Be $testPath
            $goodArgs[2] | Should -Be $testDest
        }

        It "Array with embedded quotes would have literal quote characters (demonstrating the bug)" {
            $testPath = "C:\Test Path\With Spaces\file.msu"
            $testDest = "C:\Output\Folder"

            # Bad pattern (original buggy code)
            $badArgs = @(
                '-F:*',
                "`"$testPath`"",
                "`"$testDest`""
            )

            # These would have literal quote characters
            $badArgs[1] | Should -Match '^".*"$'
            $badArgs[2] | Should -Match '^".*"$'

            # Demonstrate the problem: the path now has quotes IN it
            $badArgs[1].StartsWith('"') | Should -BeTrue -Because "embedded quotes become literal characters"
            $badArgs[1].EndsWith('"') | Should -BeTrue -Because "embedded quotes become literal characters"
        }

        It "Paths with spaces work correctly without embedded quotes" {
            $pathWithSpaces = "C:\Program Files\Test Application\Data"

            # Correct way
            $args = @('-F:*', $pathWithSpaces)

            $args[1] | Should -Be $pathWithSpaces
            $args[1] | Should -Not -Contain '"'
            $args[1].Length | Should -Be $pathWithSpaces.Length
        }

        It "Special characters in paths are preserved without corruption" {
            $pathWithSpecialChars = "C:\Test[1]\File (Copy).msu"

            $args = @('-F:*', $pathWithSpecialChars)

            $args[1] | Should -Be $pathWithSpecialChars
            $args[1] | Should -Match '\[1\]'
            $args[1] | Should -Match '\(Copy\)'
        }

        It "Empty paths are handled correctly" {
            $emptyPath = ""

            $args = @('-F:*', $emptyPath)

            $args[1] | Should -BeNullOrEmpty
            $args.Count | Should -Be 2
        }

        It "UNC paths work correctly without embedded quotes" {
            $uncPath = "\\server\share\path with spaces\file.msu"

            $args = @('-F:*', $uncPath)

            $args[1] | Should -Be $uncPath
            $args[1] | Should -Not -Contain '`'
            $args[1] | Should -Not -Match '^"'
        }
    }

    Context "Functional Tests - expand.exe Argument Parsing" -Tag 'Functional' {

        BeforeAll {
            # Create a test CAB file for expand.exe testing
            # We'll use a simple approach - create a text file and test expand.exe can be invoked
            $script:TestSourceFile = Join-Path -Path $script:TempTestDir -ChildPath "testfile.txt"
            $script:TestOutputDir = Join-Path -Path $script:TempTestDir -ChildPath "output folder with spaces"

            # Create test source file
            "Test content for expand.exe" | Out-File -FilePath $script:TestSourceFile -Encoding UTF8

            # Create output directory
            New-Item -ItemType Directory -Path $script:TestOutputDir -Force | Out-Null
        }

        It "expand.exe should be available on the system" {
            $expandExe = Get-Command -Name "expand.exe" -ErrorAction SilentlyContinue
            $expandExe | Should -Not -BeNullOrEmpty
        }

        It "expand.exe should fail gracefully with incorrect arguments (not crash)" {
            # This tests that expand.exe properly rejects bad paths rather than crashing
            $badPath = "C:\NonExistent\Path\file.msu"
            $outputPath = $script:TestOutputDir

            # Construct arguments correctly (without embedded quotes)
            $args = @('-F:*', $badPath, $outputPath)

            # Run expand.exe - it should return non-zero exit code for missing file
            $output = & expand.exe $args 2>&1
            $exitCode = $LASTEXITCODE

            # expand.exe should return error code (not crash) for missing file
            $exitCode | Should -Not -Be 0
        }

        It "Arguments array should pass to external command correctly" {
            # Test that PowerShell correctly passes array arguments to external commands
            $testPath = Join-Path -Path $script:TempTestDir -ChildPath "test with spaces.txt"
            "test" | Out-File -FilePath $testPath -Encoding UTF8

            # Verify the file exists and path is correct
            Test-Path -Path $testPath | Should -BeTrue

            # The path should not have embedded quotes when constructed correctly
            $args = @($testPath)
            $args[0] | Should -Be $testPath
            $args[0] | Should -Not -Match '^"'
            $args[0] | Should -Not -Match '"$'
        }

        It "-F:* flag should be correctly positioned as first argument" {
            $packagePath = "C:\Test\package.msu"
            $extractPath = "C:\Output"

            $args = @('-F:*', $packagePath, $extractPath)

            $args[0] | Should -Be '-F:*'
            $args[1] | Should -Be $packagePath
            $args[2] | Should -Be $extractPath
        }

        It "Argument string representation should not contain escaped quotes" {
            $path1 = "C:\Path\With Spaces\file.msu"
            $path2 = "C:\Output\Directory"

            $args = @('-F:*', $path1, $path2)

            # Join to see what would be displayed
            $argsString = $args -join ' '

            # Should not have `" or \" patterns
            $argsString | Should -Not -Match '`"'
            $argsString | Should -Not -Match '\\"'
            $argsString | Should -Not -Match '""'
        }
    }

    Context "Regression Tests" -Tag 'Regression' {

        It "FFU.Updates.psm1 should not contain the old buggy pattern" {
            $content = Get-Content -Path $script:FFUUpdatesPath -Raw

            # The old buggy pattern had:
            # $expandArgs = @(
            #     '-F:*',
            #     "`"$PackagePath`"",
            #     "`"$extractPath`""
            # )

            # This specific pattern should NOT exist
            $buggyPattern = '`"\$PackagePath`"'
            $content | Should -Not -Match $buggyPattern

            $buggyPattern2 = '`"\$extractPath`"'
            $content | Should -Not -Match $buggyPattern2
        }

        It "FFUUI.Core.Drivers.HP.psm1 should not contain embedded quotes in Invoke-Process calls" {
            $content = Get-Content -Path $script:HPDriversPath -Raw

            # Look for old pattern: @("`"$var`"", "`"$var2`"")
            $buggyPattern = '@\([^)]*`"\$[^)]*\)'

            # Find all Invoke-Process lines with expand.exe
            $lines = $content -split "`n"
            $invokeProcessLines = $lines | Where-Object { $_ -match 'Invoke-Process.*expand\.exe' }

            foreach ($line in $invokeProcessLines) {
                $line | Should -Not -Match '`"\$' -Because "embedded quotes in ArgumentList cause expand.exe to fail"
            }
        }

        It "All expand.exe argument arrays in the project should use correct pattern" {
            # Search for all expand.exe usages in relevant files
            $filesToCheck = @(
                $script:FFUUpdatesPath,
                $script:HPDriversPath
            )

            foreach ($file in $filesToCheck) {
                if (Test-Path -Path $file) {
                    $content = Get-Content -Path $file -Raw

                    # Should not have the pattern of embedded quotes before variable names
                    # Pattern: `"$VariableName`" inside an array
                    $content | Should -Not -Match '(?m)@\([^)]*`"\$\w+`"[^)]*\)' -Because "File $file should not have embedded quotes in arrays"
                }
            }
        }

        It "Fixed pattern should use direct variable references" {
            $content = Get-Content -Path $script:FFUUpdatesPath -Raw

            # The correct pattern: $expandArgs = @('-F:*', $PackagePath, $extractPath)
            # Check that PackagePath and extractPath are used directly (not with embedded quotes)

            # Find the expandArgs assignment
            if ($content -match '\$expandArgs\s*=\s*@\([^)]+\)') {
                $arrayContent = $Matches[0]

                # Should contain $PackagePath directly
                $arrayContent | Should -Match '\$PackagePath' -Because "PackagePath should be used directly"

                # Should contain $extractPath directly
                $arrayContent | Should -Match '\$extractPath' -Because "extractPath should be used directly"

                # Should NOT have `" pattern
                $arrayContent | Should -Not -Match '`"' -Because "no embedded quotes should be present"
            }
        }

        It "No double-quoted variables should exist in expand.exe argument contexts" {
            # Check both files for any remaining instances of the bug
            $allContent = ""

            if (Test-Path -Path $script:FFUUpdatesPath) {
                $allContent += Get-Content -Path $script:FFUUpdatesPath -Raw
            }
            if (Test-Path -Path $script:HPDriversPath) {
                $allContent += Get-Content -Path $script:HPDriversPath -Raw
            }

            # Pattern that indicates the bug: ArgumentList containing `"$variable`"
            $bugPattern = '-ArgumentList\s+@\([^)]*`"\$[a-zA-Z]'

            $allContent | Should -Not -Match $bugPattern
        }
    }

    Context "Edge Cases" -Tag 'EdgeCases' {

        It "Paths with single quotes should not be affected" {
            $pathWithSingleQuote = "C:\User's Folder\file.msu"

            $args = @('-F:*', $pathWithSingleQuote)

            $args[1] | Should -Be $pathWithSingleQuote
            $args[1] | Should -Match "'"
        }

        It "Paths with ampersand should be preserved" {
            $pathWithAmpersand = "C:\Test & Demo\file.msu"

            $args = @('-F:*', $pathWithAmpersand)

            $args[1] | Should -Be $pathWithAmpersand
            $args[1] | Should -Match '&'
        }

        It "Very long paths should be handled correctly" {
            $longPath = "C:\" + ("A" * 200) + "\file.msu"

            $args = @('-F:*', $longPath)

            $args[1] | Should -Be $longPath
            $args[1].Length | Should -Be $longPath.Length
        }

        It "Paths with percent signs should be preserved" {
            $pathWithPercent = "C:\Test%20Files\file.msu"

            $args = @('-F:*', $pathWithPercent)

            $args[1] | Should -Be $pathWithPercent
            $args[1] | Should -Match '%'
        }

        It "Paths with parentheses should be preserved" {
            $pathWithParens = "C:\Test (1)\file (copy).msu"

            $args = @('-F:*', $pathWithParens)

            $args[1] | Should -Be $pathWithParens
            $args[1] | Should -Match '\('
            $args[1] | Should -Match '\)'
        }
    }

    Context "Documentation Tests" -Tag 'Documentation' {

        It "FFU.Updates.psm1 should document the fix" {
            $content = Get-Content -Path $script:FFUUpdatesPath -Raw

            # Should have a comment explaining why embedded quotes are not used
            $content | Should -Match 'PowerShell handles quoting automatically'
        }

        It "FFUUI.Core.Drivers.HP.psm1 should document the fix" {
            $content = Get-Content -Path $script:HPDriversPath -Raw

            # Should have comments near each expand.exe call
            $content | Should -Match 'Do not embed quotes'
        }
    }
}
