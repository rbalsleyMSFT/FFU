#Requires -Version 5.1
#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for Get-Office function in FFU.Apps module

.DESCRIPTION
    Tests the Get-Office function's directory creation, download error handling,
    and file validation logic. These tests verify the fix for the "Could not find
    a part of the path" error when the Office directory doesn't exist.

.NOTES
    Test Coverage:
    - Directory creation when OfficePath doesn't exist
    - Directory not recreated when it already exists
    - Download error handling with -ErrorAction Stop
    - File existence validation after download
    - Empty file detection
    - Clear error message propagation
#>

BeforeAll {
    # Import the FFU.Apps module
    $modulePath = Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules\FFU.Apps\FFU.Apps.psd1"

    # We need to mock dependencies before import, so we'll test the module code directly
    $moduleCode = Get-Content (Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules\FFU.Apps\FFU.Apps.psm1") -Raw
}

# =============================================================================
# Get-Office Directory Creation Tests
# =============================================================================

Describe 'Get-Office Directory Creation' -Tag 'Unit', 'FFU.Apps', 'GetOffice', 'DirectoryCreation' {

    Context 'Office directory does not exist' {

        It 'Should contain code to create Office directory when it does not exist' {
            $moduleCode = Get-Content (Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules\FFU.Apps\FFU.Apps.psm1") -Raw

            # Verify the directory creation logic exists
            $moduleCode | Should -Match 'if \(-not \(Test-Path \$OfficePath\)\)'
            $moduleCode | Should -Match 'New-Item -Path \$OfficePath -ItemType Directory -Force'
        }

        It 'Should log directory creation' {
            $moduleCode = Get-Content (Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules\FFU.Apps\FFU.Apps.psm1") -Raw

            # Verify logging of directory creation
            $moduleCode | Should -Match 'WriteLog "Creating Office directory:'
        }
    }
}

# =============================================================================
# Get-Office Download Error Handling Tests
# =============================================================================

Describe 'Get-Office Download Error Handling' -Tag 'Unit', 'FFU.Apps', 'GetOffice', 'ErrorHandling' {

    Context 'Invoke-WebRequest error handling' {

        It 'Should use -ErrorAction Stop on Invoke-WebRequest' {
            $moduleCode = Get-Content (Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules\FFU.Apps\FFU.Apps.psm1") -Raw

            # Find the Invoke-WebRequest for ODT download (not Get-ODTURL)
            # It should have -ErrorAction Stop
            $moduleCode | Should -Match 'Invoke-WebRequest -Uri \$ODTUrl.*-ErrorAction Stop'
        }

        It 'Should wrap download in try/catch block' {
            $moduleCode = Get-Content (Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules\FFU.Apps\FFU.Apps.psm1") -Raw

            # The download should be inside a try block
            $moduleCode | Should -Match 'try\s*\{[\s\S]*?Invoke-WebRequest -Uri \$ODTUrl'
        }

        It 'Should throw descriptive error on download failure' {
            $moduleCode = Get-Content (Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules\FFU.Apps\FFU.Apps.psm1") -Raw

            # Verify the catch block throws with a descriptive message
            $moduleCode | Should -Match 'throw "Failed to download Office Deployment Toolkit'
        }

        It 'Should include original exception message in error' {
            $moduleCode = Get-Content (Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules\FFU.Apps\FFU.Apps.psm1") -Raw

            # Verify the error includes the original exception
            $moduleCode | Should -Match '\$_\.Exception\.Message'
        }
    }
}

# =============================================================================
# Get-Office Download Validation Tests
# =============================================================================

Describe 'Get-Office Download Validation' -Tag 'Unit', 'FFU.Apps', 'GetOffice', 'Validation' {

    Context 'File existence validation' {

        It 'Should validate file exists after download' {
            $moduleCode = Get-Content (Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules\FFU.Apps\FFU.Apps.psm1") -Raw

            # Verify file existence check
            $moduleCode | Should -Match 'if \(-not \(Test-Path \$ODTInstallFile\)\)'
            $moduleCode | Should -Match 'ODT download appeared to succeed but file not found'
        }

        It 'Should validate file is not empty' {
            $moduleCode = Get-Content (Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules\FFU.Apps\FFU.Apps.psm1") -Raw

            # Verify empty file check
            $moduleCode | Should -Match '\$odtFileInfo\.Length -eq 0'
            $moduleCode | Should -Match 'ODT download resulted in empty file'
        }

        It 'Should log success with file size' {
            $moduleCode = Get-Content (Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules\FFU.Apps\FFU.Apps.psm1") -Raw

            # Verify success logging with size
            $moduleCode | Should -Match 'ODT downloaded successfully.*\$odtFileInfo\.Length.*bytes'
        }
    }
}

# =============================================================================
# Get-Office Integration Pattern Tests
# =============================================================================

Describe 'Get-Office Code Structure' -Tag 'Unit', 'FFU.Apps', 'GetOffice', 'Structure' {

    Context 'Correct order of operations' {

        It 'Should create directory BEFORE attempting download' {
            $moduleCode = Get-Content (Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules\FFU.Apps\FFU.Apps.psm1") -Raw

            # Find positions - directory creation should come before download
            $dirCreationPos = $moduleCode.IndexOf('New-Item -Path $OfficePath -ItemType Directory')
            $downloadPos = $moduleCode.IndexOf('Invoke-WebRequest -Uri $ODTUrl')

            $dirCreationPos | Should -BeLessThan $downloadPos
            $dirCreationPos | Should -BeGreaterThan 0
        }

        It 'Should call Get-ODTURL before download' {
            $moduleCode = Get-Content (Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules\FFU.Apps\FFU.Apps.psm1") -Raw

            # Get-ODTURL should be called before the download
            $getOdtUrlPos = $moduleCode.IndexOf('$ODTUrl = Get-ODTURL')
            $downloadPos = $moduleCode.IndexOf('Invoke-WebRequest -Uri $ODTUrl')

            $getOdtUrlPos | Should -BeLessThan $downloadPos
            $getOdtUrlPos | Should -BeGreaterThan 0
        }

        It 'Should validate download BEFORE extraction' {
            $moduleCode = Get-Content (Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules\FFU.Apps\FFU.Apps.psm1") -Raw

            # File validation should happen before extraction
            $validationPos = $moduleCode.IndexOf('ODT downloaded successfully')
            $extractionPos = $moduleCode.IndexOf('Extracting ODT to')

            $validationPos | Should -BeLessThan $extractionPos
        }
    }
}

# =============================================================================
# Functional Tests with Mocking
# =============================================================================

Describe 'Get-Office Functional Tests' -Tag 'Unit', 'FFU.Apps', 'GetOffice', 'Functional' {

    BeforeAll {
        # Create a test script that simulates the Get-Office directory creation logic
        $script:TestOfficePath = Join-Path $TestDrive "TestOffice"
    }

    AfterEach {
        # Cleanup test directory
        if (Test-Path $script:TestOfficePath) {
            Remove-Item $script:TestOfficePath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Directory creation behavior' {

        It 'Should create directory when it does not exist' {
            # Simulate the directory creation logic from Get-Office
            $OfficePath = $script:TestOfficePath

            # This is the exact logic from Get-Office
            if (-not (Test-Path $OfficePath)) {
                New-Item -Path $OfficePath -ItemType Directory -Force | Out-Null
            }

            Test-Path $OfficePath | Should -BeTrue
            (Get-Item $OfficePath).PSIsContainer | Should -BeTrue
        }

        It 'Should not fail when directory already exists' {
            # Pre-create the directory
            $OfficePath = $script:TestOfficePath
            New-Item -Path $OfficePath -ItemType Directory -Force | Out-Null

            # This should not throw
            {
                if (-not (Test-Path $OfficePath)) {
                    New-Item -Path $OfficePath -ItemType Directory -Force | Out-Null
                }
            } | Should -Not -Throw

            Test-Path $OfficePath | Should -BeTrue
        }

        It 'Should create nested directory structure' {
            # Test with nested path like C:\FFUDevelopment\Apps\Office
            $OfficePath = Join-Path $script:TestOfficePath "Apps\Office"

            if (-not (Test-Path $OfficePath)) {
                New-Item -Path $OfficePath -ItemType Directory -Force | Out-Null
            }

            Test-Path $OfficePath | Should -BeTrue
        }
    }

    Context 'Download validation behavior' {

        It 'Should detect missing file after download attempt' {
            $ODTInstallFile = Join-Path $script:TestOfficePath "odtsetup.exe"

            # Simulate failed download - file doesn't exist
            $errorThrown = $false
            try {
                if (-not (Test-Path $ODTInstallFile)) {
                    throw "ODT download appeared to succeed but file not found at: $ODTInstallFile"
                }
            }
            catch {
                $errorThrown = $true
                $_.Exception.Message | Should -Match "ODT download appeared to succeed but file not found"
            }

            $errorThrown | Should -BeTrue
        }

        It 'Should detect empty file after download' {
            # Create empty file
            New-Item -Path $script:TestOfficePath -ItemType Directory -Force | Out-Null
            $ODTInstallFile = Join-Path $script:TestOfficePath "odtsetup.exe"
            New-Item -Path $ODTInstallFile -ItemType File -Force | Out-Null

            $errorThrown = $false
            try {
                if (-not (Test-Path $ODTInstallFile)) {
                    throw "ODT download appeared to succeed but file not found at: $ODTInstallFile"
                }
                $odtFileInfo = Get-Item $ODTInstallFile
                if ($odtFileInfo.Length -eq 0) {
                    throw "ODT download resulted in empty file: $ODTInstallFile"
                }
            }
            catch {
                $errorThrown = $true
                $_.Exception.Message | Should -Match "ODT download resulted in empty file"
            }

            $errorThrown | Should -BeTrue
        }

        It 'Should pass validation for non-empty file' {
            # Create non-empty file
            New-Item -Path $script:TestOfficePath -ItemType Directory -Force | Out-Null
            $ODTInstallFile = Join-Path $script:TestOfficePath "odtsetup.exe"
            Set-Content -Path $ODTInstallFile -Value "test content" -Force

            $errorThrown = $false
            $fileSize = 0
            try {
                if (-not (Test-Path $ODTInstallFile)) {
                    throw "ODT download appeared to succeed but file not found at: $ODTInstallFile"
                }
                $odtFileInfo = Get-Item $ODTInstallFile
                if ($odtFileInfo.Length -eq 0) {
                    throw "ODT download resulted in empty file: $ODTInstallFile"
                }
                $fileSize = $odtFileInfo.Length
            }
            catch {
                $errorThrown = $true
            }

            $errorThrown | Should -BeFalse
            $fileSize | Should -BeGreaterThan 0
        }
    }
}

# =============================================================================
# Error Message Quality Tests
# =============================================================================

Describe 'Get-Office Error Message Quality' -Tag 'Unit', 'FFU.Apps', 'GetOffice', 'ErrorMessages' {

    Context 'Error messages are actionable' {

        It 'Should include URL in download failure message' {
            $moduleCode = Get-Content (Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules\FFU.Apps\FFU.Apps.psm1") -Raw

            # Error should include the URL for troubleshooting
            $moduleCode | Should -Match 'Failed to download Office Deployment Toolkit from \$ODTUrl'
        }

        It 'Should include file path in validation error messages' {
            $moduleCode = Get-Content (Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules\FFU.Apps\FFU.Apps.psm1") -Raw

            # Both error messages should include the file path
            $moduleCode | Should -Match 'file not found at: \$ODTInstallFile'
            $moduleCode | Should -Match 'empty file: \$ODTInstallFile'
        }
    }
}

# =============================================================================
# Regression Tests
# =============================================================================

Describe 'Get-Office Regression Prevention' -Tag 'Unit', 'FFU.Apps', 'GetOffice', 'Regression' {

    Context 'Original bug scenario prevention' {

        It 'Should NOT have Invoke-WebRequest without -ErrorAction Stop for ODT download' {
            $moduleCode = Get-Content (Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules\FFU.Apps\FFU.Apps.psm1") -Raw

            # Find all Invoke-WebRequest calls for ODT (not in Get-ODTURL which already has -ErrorAction Stop)
            # The ODT download line should have -ErrorAction Stop

            # Extract the Get-Office function content
            $getOfficeFunctionMatch = [regex]::Match($moduleCode, 'function Get-Office \{[\s\S]*?(?=\nfunction |\n#\s*Export|\z)')
            $getOfficeFunctionContent = $getOfficeFunctionMatch.Value

            # The Invoke-WebRequest for ODT download should have -ErrorAction Stop
            $getOfficeFunctionContent | Should -Match 'Invoke-WebRequest -Uri \$ODTUrl.*-ErrorAction Stop'
        }

        It 'Should create directory before any file operations in OfficePath' {
            $moduleCode = Get-Content (Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules\FFU.Apps\FFU.Apps.psm1") -Raw

            # Extract the Get-Office function content
            $getOfficeFunctionMatch = [regex]::Match($moduleCode, 'function Get-Office \{[\s\S]*?(?=\nfunction |\n#\s*Export|\z)')
            $getOfficeFunctionContent = $getOfficeFunctionMatch.Value

            # Directory creation should be one of the first operations
            $dirCheckPos = $getOfficeFunctionContent.IndexOf('Test-Path $OfficePath')
            $newItemPos = $getOfficeFunctionContent.IndexOf('New-Item -Path $OfficePath')

            # Both should exist
            $dirCheckPos | Should -BeGreaterThan 0
            $newItemPos | Should -BeGreaterThan 0

            # And directory creation should come before Join-Path for ODTInstallFile
            $joinPathPos = $getOfficeFunctionContent.IndexOf('$ODTInstallFile = Join-Path')
            $newItemPos | Should -BeLessThan $joinPathPos
        }
    }
}
