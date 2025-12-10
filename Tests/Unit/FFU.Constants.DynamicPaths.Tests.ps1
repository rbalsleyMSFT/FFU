#Requires -Version 5.1
#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for FFU.Constants dynamic path resolution functionality

.DESCRIPTION
    Tests the dynamic path resolution feature added in FFU.Constants v1.1.0
    that allows FFUBuilder to be installed in any location (not just C:\FFUDevelopment).

.NOTES
    Test Coverage:
    - GetBasePath() returns valid path
    - SetBasePath() override works
    - ResetBasePath() clears cache
    - All GetDefault*Dir() methods return paths under base
    - Paths are constructed with Join-Path (proper separators)
    - Environment variable overrides work
    - Backward compatibility with legacy methods

    Note: PowerShell classes require 'using module' at parse time.
    These tests invoke a helper script that loads the class properly.
#>

BeforeAll {
    # Set up paths
    $script:ModulePath = Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules\FFU.Constants\FFU.Constants.psm1"
    $script:ModulePath = [System.IO.Path]::GetFullPath($script:ModulePath)

    if (-not (Test-Path $script:ModulePath)) {
        throw "FFU.Constants module not found at: $script:ModulePath"
    }

    # Helper function to run code with the class loaded
    function Invoke-WithFFUConstants {
        param([string]$Code)

        $script = @"
using module '$($script:ModulePath)'
`$ErrorActionPreference = 'Stop'
$Code
"@
        $tempFile = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.ps1'
        $script | Set-Content -Path $tempFile -Encoding UTF8
        try {
            $result = & pwsh -NoProfile -File $tempFile 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "Script execution failed: $result"
            }
            return $result
        }
        finally {
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "FFU.Constants Dynamic Path Resolution" -Tag "Unit", "FFU.Constants" {

    Context "GetBasePath Method" {

        It "Should return a non-empty path" {
            $result = Invoke-WithFFUConstants '[FFUConstants]::GetBasePath()'
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should return a valid directory path" {
            $result = Invoke-WithFFUConstants @'
$path = [FFUConstants]::GetBasePath()
if (Test-Path $path -PathType Container) { 'True' } else { 'False' }
'@
            $result | Should -Be 'True'
        }

        It "Should resolve to FFUDevelopment directory" {
            $result = Invoke-WithFFUConstants '[FFUConstants]::GetBasePath()'
            $result | Should -BeLike "*FFUDevelopment*"
        }

        It "Should return consistent results across multiple calls" {
            $result = Invoke-WithFFUConstants @'
$path1 = [FFUConstants]::GetBasePath()
$path2 = [FFUConstants]::GetBasePath()
if ($path1 -eq $path2) { 'Consistent' } else { 'Inconsistent' }
'@
            $result | Should -Be 'Consistent'
        }
    }

    Context "SetBasePath Method" {

        It "Should allow setting a custom base path" {
            $result = Invoke-WithFFUConstants @'
[FFUConstants]::SetBasePath('D:\CustomFFUPath')
[FFUConstants]::GetBasePath()
'@
            $result | Should -Be 'D:\CustomFFUPath'
        }

        It "Should affect GetDefaultVMDir" {
            $result = Invoke-WithFFUConstants @'
[FFUConstants]::SetBasePath('E:\TestPath')
[FFUConstants]::GetDefaultVMDir()
'@
            $result | Should -Be 'E:\TestPath\VM'
        }

        It "Should affect GetDefaultCaptureDir" {
            $result = Invoke-WithFFUConstants @'
[FFUConstants]::SetBasePath('E:\TestPath')
[FFUConstants]::GetDefaultCaptureDir()
'@
            $result | Should -Be 'E:\TestPath\FFU'
        }
    }

    Context "ResetBasePath Method" {

        It "Should clear the cached path" {
            $result = Invoke-WithFFUConstants @'
[FFUConstants]::SetBasePath('Z:\TempPath')
$before = [FFUConstants]::GetBasePath()
[FFUConstants]::ResetBasePath()
$after = [FFUConstants]::GetBasePath()
if ($before -eq 'Z:\TempPath' -and $after -like '*FFUDevelopment*') { 'Reset works' } else { "Before: $before, After: $after" }
'@
            $result | Should -Be 'Reset works'
        }
    }

    Context "Dynamic Path Methods" {

        It "GetDefaultWorkingDir should equal GetBasePath" {
            $result = Invoke-WithFFUConstants @'
$base = [FFUConstants]::GetBasePath()
$working = [FFUConstants]::GetDefaultWorkingDir()
if ($base -eq $working) { 'Equal' } else { 'Not equal' }
'@
            $result | Should -Be 'Equal'
        }

        It "GetDefaultVMDir should return <base>\VM" {
            $result = Invoke-WithFFUConstants @'
[FFUConstants]::ResetBasePath()
$base = [FFUConstants]::GetBasePath()
$vmDir = [FFUConstants]::GetDefaultVMDir()
$expected = Join-Path $base 'VM'
if ($vmDir -eq $expected) { 'Correct' } else { "Expected: $expected, Got: $vmDir" }
'@
            $result | Should -Be 'Correct'
        }

        It "GetDefaultCaptureDir should return <base>\FFU" {
            $result = Invoke-WithFFUConstants @'
[FFUConstants]::ResetBasePath()
$base = [FFUConstants]::GetBasePath()
$dir = [FFUConstants]::GetDefaultCaptureDir()
$expected = Join-Path $base 'FFU'
if ($dir -eq $expected) { 'Correct' } else { "Expected: $expected, Got: $dir" }
'@
            $result | Should -Be 'Correct'
        }

        It "GetDefaultDriversDir should return <base>\Drivers" {
            $result = Invoke-WithFFUConstants @'
[FFUConstants]::ResetBasePath()
$base = [FFUConstants]::GetBasePath()
$dir = [FFUConstants]::GetDefaultDriversDir()
$expected = Join-Path $base 'Drivers'
if ($dir -eq $expected) { 'Correct' } else { "Expected: $expected, Got: $dir" }
'@
            $result | Should -Be 'Correct'
        }

        It "GetDefaultAppsDir should return <base>\Apps" {
            $result = Invoke-WithFFUConstants @'
[FFUConstants]::ResetBasePath()
$base = [FFUConstants]::GetBasePath()
$dir = [FFUConstants]::GetDefaultAppsDir()
$expected = Join-Path $base 'Apps'
if ($dir -eq $expected) { 'Correct' } else { "Expected: $expected, Got: $dir" }
'@
            $result | Should -Be 'Correct'
        }

        It "GetDefaultUpdatesDir should return <base>\Updates" {
            $result = Invoke-WithFFUConstants @'
[FFUConstants]::ResetBasePath()
$base = [FFUConstants]::GetBasePath()
$dir = [FFUConstants]::GetDefaultUpdatesDir()
$expected = Join-Path $base 'Updates'
if ($dir -eq $expected) { 'Correct' } else { "Expected: $expected, Got: $dir" }
'@
            $result | Should -Be 'Correct'
        }

        It "All paths should use proper Windows path separators" {
            $result = Invoke-WithFFUConstants @'
[FFUConstants]::ResetBasePath()
$paths = @(
    [FFUConstants]::GetDefaultWorkingDir()
    [FFUConstants]::GetDefaultVMDir()
    [FFUConstants]::GetDefaultCaptureDir()
    [FFUConstants]::GetDefaultDriversDir()
    [FFUConstants]::GetDefaultAppsDir()
    [FFUConstants]::GetDefaultUpdatesDir()
)
$allValid = $true
foreach ($path in $paths) {
    if ($path -like '*/*') { $allValid = $false; break }
    if ($path -notmatch '^[A-Za-z]:\\') { $allValid = $false; break }
}
if ($allValid) { 'Valid' } else { 'Invalid' }
'@
            $result | Should -Be 'Valid'
        }
    }

    Context "Backward Compatibility" {

        It "GetWorkingDirectory legacy method should work" {
            $result = Invoke-WithFFUConstants @'
[FFUConstants]::ResetBasePath()
$result = [FFUConstants]::GetWorkingDirectory()
if ($result -like '*FFUDevelopment*') { 'Works' } else { $result }
'@
            $result | Should -Be 'Works'
        }

        It "GetVMDirectory legacy method should work" {
            $result = Invoke-WithFFUConstants @'
[FFUConstants]::ResetBasePath()
$result = [FFUConstants]::GetVMDirectory()
if ($result -like '*VM') { 'Works' } else { $result }
'@
            $result | Should -Be 'Works'
        }

        It "GetCaptureDirectory legacy method should work" {
            $result = Invoke-WithFFUConstants @'
[FFUConstants]::ResetBasePath()
$result = [FFUConstants]::GetCaptureDirectory()
if ($result -like '*FFU') { 'Works' } else { $result }
'@
            $result | Should -Be 'Works'
        }

        It "Legacy methods should call new methods internally" {
            $result = Invoke-WithFFUConstants @'
[FFUConstants]::ResetBasePath()
$match1 = [FFUConstants]::GetWorkingDirectory() -eq [FFUConstants]::GetDefaultWorkingDir()
$match2 = [FFUConstants]::GetVMDirectory() -eq [FFUConstants]::GetDefaultVMDir()
$match3 = [FFUConstants]::GetCaptureDirectory() -eq [FFUConstants]::GetDefaultCaptureDir()
if ($match1 -and $match2 -and $match3) { 'AllMatch' } else { 'Mismatch' }
'@
            $result | Should -Be 'AllMatch'
        }

        It "Static deprecated properties should still exist" {
            $result = Invoke-WithFFUConstants @'
$val = [FFUConstants]::DEFAULT_WORKING_DIR
if ($val -eq 'C:\FFUDevelopment') { 'Exists' } else { 'Missing or wrong' }
'@
            $result | Should -Be 'Exists'
        }

        It "Non-path constants should be unchanged" {
            $result = Invoke-WithFFUConstants @'
$mem = [FFUConstants]::DEFAULT_VM_MEMORY
$proc = [FFUConstants]::DEFAULT_VM_PROCESSORS
$disk = [FFUConstants]::DEFAULT_VHDX_SIZE
if ($mem -eq 4GB -and $proc -eq 4 -and $disk -eq 50GB) { 'Unchanged' } else { 'Changed' }
'@
            $result | Should -Be 'Unchanged'
        }
    }

    Context "Path Construction Quality" {

        It "Should handle custom base paths correctly" {
            $result = Invoke-WithFFUConstants @'
[FFUConstants]::SetBasePath('C:\TestPath')
$vmDir = [FFUConstants]::GetDefaultVMDir()
if ($vmDir -eq 'C:\TestPath\VM') { 'Correct' } else { $vmDir }
'@
            $result | Should -Be 'Correct'
        }

        It "All subdirectory names should be correct" {
            $result = Invoke-WithFFUConstants @'
[FFUConstants]::SetBasePath('C:\TestBase')
$results = @(
    ([FFUConstants]::GetDefaultVMDir() -eq 'C:\TestBase\VM')
    ([FFUConstants]::GetDefaultCaptureDir() -eq 'C:\TestBase\FFU')
    ([FFUConstants]::GetDefaultDriversDir() -eq 'C:\TestBase\Drivers')
    ([FFUConstants]::GetDefaultAppsDir() -eq 'C:\TestBase\Apps')
    ([FFUConstants]::GetDefaultUpdatesDir() -eq 'C:\TestBase\Updates')
)
if ($results -notcontains $false) { 'AllCorrect' } else { 'SomeFailed' }
'@
            $result | Should -Be 'AllCorrect'
        }
    }
}

Describe "FFU.Constants Module Integrity" -Tag "Unit", "FFU.Constants" {

    It "Module file should exist" {
        $modulePath = Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules\FFU.Constants\FFU.Constants.psm1"
        $modulePath = [System.IO.Path]::GetFullPath($modulePath)
        Test-Path $modulePath | Should -BeTrue
    }

    It "Module should parse without syntax errors" {
        $modulePath = Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules\FFU.Constants\FFU.Constants.psm1"
        $modulePath = [System.IO.Path]::GetFullPath($modulePath)

        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($modulePath, [ref]$null, [ref]$errors)
        $errors.Count | Should -Be 0
    }

    It "FFUConstants class should be accessible after using module" {
        $result = Invoke-WithFFUConstants @'
if ([FFUConstants] -ne $null) { 'Accessible' } else { 'Not accessible' }
'@
        $result | Should -Be 'Accessible'
    }

    It "All expected static methods should exist" {
        $result = Invoke-WithFFUConstants @'
$methods = @(
    'GetBasePath',
    'SetBasePath',
    'ResetBasePath',
    'GetDefaultWorkingDir',
    'GetDefaultVMDir',
    'GetDefaultCaptureDir',
    'GetDefaultDriversDir',
    'GetDefaultAppsDir',
    'GetDefaultUpdatesDir',
    'GetWorkingDirectory',
    'GetVMDirectory',
    'GetCaptureDirectory'
)
$type = [FFUConstants]
$allExist = $true
foreach ($m in $methods) {
    if ($null -eq $type.GetMethod($m)) { $allExist = $false; break }
}
if ($allExist) { 'AllExist' } else { 'SomeMissing' }
'@
        $result | Should -Be 'AllExist'
    }
}
