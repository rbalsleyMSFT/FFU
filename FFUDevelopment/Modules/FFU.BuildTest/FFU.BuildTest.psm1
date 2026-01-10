#Requires -Version 7.0
<#
.SYNOPSIS
    FFU.BuildTest module - Build testing and verification for FFU Builder.

.DESCRIPTION
    Provides functions to:
    - Copy FFUDevelopment folder to test drives
    - Execute builds with different configurations (Minimal, Standard, UserConfig)
    - Verify build outputs (FFU files, media)
    - Generate structured verification reports

.NOTES
    Module: FFU.BuildTest
    Version: 1.0.0
    Author: FFU Builder Team
#>

#region Module Variables

$script:ModuleName = 'FFU.BuildTest'
$script:TestConfigPath = Join-Path $PSScriptRoot '..\..\config\test'

#endregion

#region Public Functions

function Get-FFUTestConfiguration {
    <#
    .SYNOPSIS
        Loads a test configuration file for build verification.

    .DESCRIPTION
        Retrieves the specified test configuration (Minimal, Standard, or UserConfig)
        from the test configuration directory.

    .PARAMETER ConfigType
        The type of configuration to load: Minimal, Standard, or UserConfig.

    .PARAMETER FFUDevelopmentPath
        The path to the FFUDevelopment folder. Defaults to parent of module location.

    .OUTPUTS
        [hashtable] The configuration as a hashtable.

    .EXAMPLE
        Get-FFUTestConfiguration -ConfigType Minimal

    .EXAMPLE
        Get-FFUTestConfiguration -ConfigType UserConfig -FFUDevelopmentPath "D:\FFUDevelopment"
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Minimal', 'Standard', 'UserConfig')]
        [string]$ConfigType,

        [Parameter()]
        [string]$FFUDevelopmentPath
    )

    begin {
        if (-not $FFUDevelopmentPath) {
            $FFUDevelopmentPath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        }
    }

    process {
        $configPath = switch ($ConfigType) {
            'Minimal' { Join-Path $FFUDevelopmentPath 'config\test\test-minimal.json' }
            'Standard' { Join-Path $FFUDevelopmentPath 'config\test\test-standard.json' }
            'UserConfig' { Join-Path $FFUDevelopmentPath 'config\FFUConfig.json' }
        }

        if (-not (Test-Path $configPath)) {
            throw "Configuration file not found: $configPath"
        }

        try {
            $content = Get-Content -Path $configPath -Raw -ErrorAction Stop
            $config = $content | ConvertFrom-Json -AsHashtable -ErrorAction Stop

            # Remove comment fields
            $config.Remove('$schema')
            $config.Remove('_comment')
            $config.Remove('_description')

            Write-Verbose "[$script:ModuleName] Loaded $ConfigType configuration from: $configPath"
            return $config
        }
        catch {
            throw "Failed to parse configuration file '$configPath': $_"
        }
    }
}

function Copy-FFUDevelopmentToTestDrive {
    <#
    .SYNOPSIS
        Copies the FFUDevelopment folder to a test drive for isolated build testing.

    .DESCRIPTION
        Uses Robocopy to efficiently copy the FFUDevelopment folder to a specified
        test drive. Optionally cleans any existing test folder before copying.
        Validates disk space requirements before proceeding.

    .PARAMETER SourcePath
        The path to the FFUDevelopment folder to copy. Defaults to current module's parent.

    .PARAMETER TestDriveLetter
        The drive letter to copy to (e.g., "D", "E"). Must be a single letter A-Z.

    .PARAMETER CleanFirst
        If specified, removes any existing test folder before copying.

    .PARAMETER TargetFolderName
        The name of the target folder on the test drive. Defaults to 'FFUDevelopment_Test'.

    .PARAMETER MinimumSpaceGB
        Minimum required free space in GB on the target drive. Defaults to 50.

    .OUTPUTS
        [string] The full path to the copied FFUDevelopment folder.

    .EXAMPLE
        Copy-FFUDevelopmentToTestDrive -TestDriveLetter "D" -CleanFirst
        # Copies FFUDevelopment to D:\FFUDevelopment_Test after cleaning

    .EXAMPLE
        Copy-FFUDevelopmentToTestDrive -SourcePath "C:\FFU" -TestDriveLetter "E" -TargetFolderName "TestBuild"
        # Copies C:\FFU to E:\TestBuild
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter()]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Z]$')]
        [string]$TestDriveLetter,

        [Parameter()]
        [switch]$CleanFirst,

        [Parameter()]
        [string]$TargetFolderName = 'FFUDevelopment_Test',

        [Parameter()]
        [ValidateRange(10, 500)]
        [int]$MinimumSpaceGB = 50
    )

    begin {
        if (-not $SourcePath) {
            $SourcePath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        }

        $testDrivePath = "${TestDriveLetter}:\"
        $targetPath = Join-Path $testDrivePath $TargetFolderName
    }

    process {
        # Validate test drive exists
        if (-not (Test-Path $testDrivePath)) {
            throw "Test drive not found: $testDrivePath"
        }

        # Check available disk space
        $drive = Get-PSDrive -Name $TestDriveLetter -ErrorAction Stop
        $freeSpaceGB = [math]::Round($drive.Free / 1GB, 2)

        if ($freeSpaceGB -lt $MinimumSpaceGB) {
            throw "Insufficient disk space on $testDrivePath. Required: ${MinimumSpaceGB}GB, Available: ${freeSpaceGB}GB"
        }

        Write-Verbose "[$script:ModuleName] Available space on ${TestDriveLetter}: ${freeSpaceGB}GB"

        # Clean existing folder if requested
        if ($CleanFirst -and (Test-Path $targetPath)) {
            if ($PSCmdlet.ShouldProcess($targetPath, "Remove existing test folder")) {
                Write-Verbose "[$script:ModuleName] Removing existing folder: $targetPath"
                Remove-Item -Path $targetPath -Recurse -Force -ErrorAction Stop
            }
        }

        # Copy using Robocopy for efficiency and long path support
        if ($PSCmdlet.ShouldProcess($targetPath, "Copy FFUDevelopment")) {
            Write-Verbose "[$script:ModuleName] Copying from '$SourcePath' to '$targetPath'"

            $robocopyArgs = @(
                "`"$SourcePath`""
                "`"$targetPath`""
                '/E'           # Copy subdirectories including empty ones
                '/NP'          # No progress (cleaner output)
                '/NFL'         # No file list
                '/NDL'         # No directory list
                '/MT:8'        # Multi-threaded (8 threads)
                '/R:3'         # Retry 3 times
                '/W:5'         # Wait 5 seconds between retries
                '/XD'          # Exclude directories
                'FFU'          # Exclude FFU output folder
                'Logs'         # Exclude logs folder
                '.git'         # Exclude git folder
            )

            $robocopyResult = Start-Process -FilePath 'robocopy.exe' `
                -ArgumentList $robocopyArgs `
                -Wait -PassThru -NoNewWindow

            # Robocopy exit codes: 0-7 are success, 8+ are errors
            if ($robocopyResult.ExitCode -ge 8) {
                throw "Robocopy failed with exit code: $($robocopyResult.ExitCode)"
            }

            Write-Verbose "[$script:ModuleName] Copy completed. Robocopy exit code: $($robocopyResult.ExitCode)"
        }

        return $targetPath
    }
}

function Invoke-FFUTestBuild {
    <#
    .SYNOPSIS
        Executes a test build of FFU Builder with specified configuration.

    .DESCRIPTION
        Runs BuildFFUVM.ps1 with a test configuration (Minimal, Standard, or UserConfig)
        on the specified hypervisor. Captures output and verifies build artifacts.

    .PARAMETER ConfigType
        The configuration type to use: Minimal, Standard, or UserConfig.

    .PARAMETER Hypervisor
        The hypervisor to use: HyperV, VMware, or Both.

    .PARAMETER TestDriveLetter
        The drive letter containing the FFUDevelopment_Test folder.

    .PARAMETER VMHostIPAddress
        The IP address of the VM host (required for Standard config).

    .PARAMETER VMSwitchName
        The Hyper-V switch name (required for HyperV builds).

    .PARAMETER VMwareCredential
        Credentials for VMware REST API authentication.

    .PARAMETER ISOPath
        Path to Windows ISO. If not provided, uses auto-download.

    .PARAMETER CleanupOnSuccess
        If specified, removes build artifacts on successful completion.

    .PARAMETER CleanupOnFailure
        If specified, removes build artifacts on failed build.

    .PARAMETER TimeoutMinutes
        Maximum time to wait for build completion. Defaults to 120 minutes.

    .OUTPUTS
        [PSCustomObject] Build result object containing status, output, and metrics.

    .EXAMPLE
        Invoke-FFUTestBuild -ConfigType Minimal -Hypervisor HyperV -TestDriveLetter "D"

    .EXAMPLE
        Invoke-FFUTestBuild -ConfigType Standard -Hypervisor Both `
            -TestDriveLetter "D" `
            -VMHostIPAddress "192.168.1.100" `
            -VMSwitchName "Default Switch"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Minimal', 'Standard', 'UserConfig')]
        [string]$ConfigType,

        [Parameter()]
        [ValidateSet('HyperV', 'VMware', 'Both')]
        [string]$Hypervisor = 'HyperV',

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Z]$')]
        [string]$TestDriveLetter,

        [Parameter()]
        [string]$VMHostIPAddress,

        [Parameter()]
        [string]$VMSwitchName,

        [Parameter()]
        [PSCredential]$VMwareCredential,

        [Parameter()]
        [string]$ISOPath,

        [Parameter()]
        [switch]$CleanupOnSuccess,

        [Parameter()]
        [switch]$CleanupOnFailure,

        [Parameter()]
        [ValidateRange(30, 360)]
        [int]$TimeoutMinutes = 120
    )

    begin {
        $testPath = "${TestDriveLetter}:\FFUDevelopment_Test"
        $buildScript = Join-Path $testPath 'BuildFFUVM.ps1'
        $startTime = Get-Date

        # Validate test path exists
        if (-not (Test-Path $testPath)) {
            throw "Test FFUDevelopment not found at '$testPath'. Run Copy-FFUDevelopmentToTestDrive first."
        }

        if (-not (Test-Path $buildScript)) {
            throw "BuildFFUVM.ps1 not found at '$buildScript'"
        }
    }

    process {
        $hypervisorsToTest = switch ($Hypervisor) {
            'Both' { @('HyperV', 'VMware') }
            default { @($Hypervisor) }
        }

        $results = @()

        foreach ($hv in $hypervisorsToTest) {
            Write-Verbose "[$script:ModuleName] Starting $ConfigType build on $hv"

            # Load and customize configuration
            $config = Get-FFUTestConfiguration -ConfigType $ConfigType -FFUDevelopmentPath $testPath

            # Override hypervisor settings
            $config['HypervisorType'] = $hv

            if ($VMHostIPAddress) {
                $config['VMHostIPAddress'] = $VMHostIPAddress
            }

            if ($VMSwitchName -and $hv -eq 'HyperV') {
                $config['VMSwitchName'] = $VMSwitchName
            }

            if ($ISOPath) {
                $config['ISOPath'] = $ISOPath
            }

            # Create temporary config file
            $tempConfigPath = Join-Path $testPath "config\test\temp-$hv-$(Get-Date -Format 'yyyyMMddHHmmss').json"
            $config | ConvertTo-Json -Depth 10 | Set-Content -Path $tempConfigPath -Encoding UTF8

            try {
                $buildStartTime = Get-Date

                if ($PSCmdlet.ShouldProcess("$ConfigType on $hv", "Execute FFU Build")) {
                    # Execute build
                    $buildArgs = @(
                        '-NoProfile'
                        '-ExecutionPolicy', 'Bypass'
                        '-File', "`"$buildScript`""
                        '-ConfigFile', "`"$tempConfigPath`""
                    )

                    Write-Verbose "[$script:ModuleName] Executing: pwsh $($buildArgs -join ' ')"

                    $process = Start-Process -FilePath 'pwsh' `
                        -ArgumentList $buildArgs `
                        -WorkingDirectory $testPath `
                        -Wait `
                        -PassThru `
                        -NoNewWindow `
                        -RedirectStandardOutput (Join-Path $testPath "Logs\build-$hv-stdout.log") `
                        -RedirectStandardError (Join-Path $testPath "Logs\build-$hv-stderr.log")

                    $buildEndTime = Get-Date
                    $duration = $buildEndTime - $buildStartTime

                    # Check build output
                    $ffuFolder = Join-Path $testPath 'FFU'
                    $ffuFiles = @()
                    if (Test-Path $ffuFolder) {
                        $ffuFiles = Get-ChildItem -Path $ffuFolder -Filter '*.ffu' -ErrorAction SilentlyContinue
                    }

                    $deployMediaPath = Join-Path $testPath 'WinPE\Deploy'
                    $captureMediaPath = Join-Path $testPath 'WinPE\Capture'

                    $result = [PSCustomObject]@{
                        ConfigType      = $ConfigType
                        Hypervisor      = $hv
                        ExitCode        = $process.ExitCode
                        Success         = $process.ExitCode -eq 0
                        StartTime       = $buildStartTime
                        EndTime         = $buildEndTime
                        Duration        = $duration
                        DurationString  = '{0:hh\:mm\:ss}' -f $duration
                        FFUFiles        = $ffuFiles
                        FFUCount        = $ffuFiles.Count
                        DeployMediaExists  = Test-Path $deployMediaPath
                        CaptureMediaExists = Test-Path $captureMediaPath
                        StdOutLog       = Join-Path $testPath "Logs\build-$hv-stdout.log"
                        StdErrLog       = Join-Path $testPath "Logs\build-$hv-stderr.log"
                        TestPath        = $testPath
                        ConfigPath      = $tempConfigPath
                    }

                    $results += $result

                    # Cleanup on success/failure as requested
                    if ($result.Success -and $CleanupOnSuccess) {
                        Write-Verbose "[$script:ModuleName] Cleaning up after successful build"
                        # Keep logs, remove FFU and WinPE folders
                        if (Test-Path $ffuFolder) { Remove-Item -Path $ffuFolder -Recurse -Force }
                    }
                    elseif (-not $result.Success -and $CleanupOnFailure) {
                        Write-Verbose "[$script:ModuleName] Cleaning up after failed build"
                        if (Test-Path $ffuFolder) { Remove-Item -Path $ffuFolder -Recurse -Force }
                    }
                }
            }
            catch {
                $results += [PSCustomObject]@{
                    ConfigType     = $ConfigType
                    Hypervisor     = $hv
                    ExitCode       = -1
                    Success        = $false
                    Error          = $_.Exception.Message
                    StartTime      = $buildStartTime
                    EndTime        = Get-Date
                    Duration       = (Get-Date) - $buildStartTime
                    DurationString = 'N/A'
                    FFUFiles       = @()
                    FFUCount       = 0
                    TestPath       = $testPath
                    ConfigPath     = $tempConfigPath
                }
            }
            finally {
                # Clean up temp config
                if (Test-Path $tempConfigPath) {
                    Remove-Item -Path $tempConfigPath -Force -ErrorAction SilentlyContinue
                }
            }
        }

        return $results
    }
}

function Test-FFUBuildOutput {
    <#
    .SYNOPSIS
        Validates FFU build output artifacts.

    .DESCRIPTION
        Verifies that the FFU file was created, meets size requirements,
        and optional media files exist as expected.

    .PARAMETER FFUPath
        The path to the FFU file or folder containing FFU files.

    .PARAMETER ExpectedSKU
        The expected Windows SKU in the FFU filename (e.g., "Pro").

    .PARAMETER MinSizeBytes
        Minimum expected FFU file size in bytes. Defaults to 3GB.

    .PARAMETER MaxSizeBytes
        Maximum expected FFU file size in bytes. Defaults to 20GB.

    .PARAMETER ExpectDeployMedia
        If true, verifies deployment media was created.

    .PARAMETER ExpectCaptureMedia
        If true, verifies capture media was created.

    .PARAMETER TestPath
        Base path to FFUDevelopment_Test folder.

    .OUTPUTS
        [PSCustomObject] Validation result with pass/fail status and details.

    .EXAMPLE
        Test-FFUBuildOutput -FFUPath "D:\FFUDevelopment_Test\FFU" -ExpectedSKU "Pro"
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$FFUPath,

        [Parameter()]
        [string]$ExpectedSKU,

        [Parameter()]
        [int64]$MinSizeBytes = 3GB,

        [Parameter()]
        [int64]$MaxSizeBytes = 20GB,

        [Parameter()]
        [switch]$ExpectDeployMedia,

        [Parameter()]
        [switch]$ExpectCaptureMedia,

        [Parameter()]
        [string]$TestPath
    )

    process {
        $validations = @()
        $overallPass = $true

        # Find FFU files
        $ffuFiles = @()
        if (Test-Path $FFUPath) {
            if ((Get-Item $FFUPath).PSIsContainer) {
                $ffuFiles = Get-ChildItem -Path $FFUPath -Filter '*.ffu' -ErrorAction SilentlyContinue
            }
            else {
                $ffuFiles = @(Get-Item $FFUPath)
            }
        }

        # Validate FFU exists
        $ffuExists = $ffuFiles.Count -gt 0
        $validations += [PSCustomObject]@{
            Check   = 'FFU File Exists'
            Status  = if ($ffuExists) { 'PASS' } else { 'FAIL' }
            Details = if ($ffuExists) { "Found $($ffuFiles.Count) FFU file(s)" } else { 'No FFU files found' }
        }
        $overallPass = $overallPass -and $ffuExists

        if ($ffuFiles.Count -gt 0) {
            $ffu = $ffuFiles[0]

            # Validate size
            $sizeValid = ($ffu.Length -ge $MinSizeBytes) -and ($ffu.Length -le $MaxSizeBytes)
            $sizeGB = [math]::Round($ffu.Length / 1GB, 2)
            $validations += [PSCustomObject]@{
                Check   = 'FFU File Size'
                Status  = if ($sizeValid) { 'PASS' } else { 'FAIL' }
                Details = "${sizeGB}GB (expected: $([math]::Round($MinSizeBytes/1GB,1))-$([math]::Round($MaxSizeBytes/1GB,1))GB)"
            }
            $overallPass = $overallPass -and $sizeValid

            # Validate SKU in filename
            if ($ExpectedSKU) {
                $skuMatch = $ffu.Name -match $ExpectedSKU
                $validations += [PSCustomObject]@{
                    Check   = 'Expected SKU in Filename'
                    Status  = if ($skuMatch) { 'PASS' } else { 'WARN' }
                    Details = if ($skuMatch) { "Found '$ExpectedSKU' in: $($ffu.Name)" } else { "Expected '$ExpectedSKU' not in: $($ffu.Name)" }
                }
            }
        }

        # Validate deployment media
        if ($ExpectDeployMedia -and $TestPath) {
            $deployPath = Join-Path $TestPath 'WinPE\Deploy'
            $deployExists = Test-Path $deployPath
            $validations += [PSCustomObject]@{
                Check   = 'Deployment Media'
                Status  = if ($deployExists) { 'PASS' } else { 'FAIL' }
                Details = if ($deployExists) { "Found at: $deployPath" } else { "Not found at: $deployPath" }
            }
            $overallPass = $overallPass -and $deployExists
        }

        # Validate capture media
        if ($ExpectCaptureMedia -and $TestPath) {
            $capturePath = Join-Path $TestPath 'WinPE\Capture'
            $captureExists = Test-Path $capturePath
            $validations += [PSCustomObject]@{
                Check   = 'Capture Media'
                Status  = if ($captureExists) { 'PASS' } else { 'FAIL' }
                Details = if ($captureExists) { "Found at: $capturePath" } else { "Not found at: $capturePath" }
            }
            $overallPass = $overallPass -and $captureExists
        }

        return [PSCustomObject]@{
            OverallStatus = if ($overallPass) { 'PASS' } else { 'FAIL' }
            Validations   = $validations
            FFUFiles      = $ffuFiles
            TestPath      = $TestPath
        }
    }
}

function Get-FFUBuildVerificationReport {
    <#
    .SYNOPSIS
        Generates a structured verification report from build results.

    .DESCRIPTION
        Creates a formatted report suitable for parsing by automated systems,
        following the structured output format required by verify-app.

    .PARAMETER BuildResult
        The result object from Invoke-FFUTestBuild.

    .PARAMETER Hypervisor
        The hypervisor used for the build.

    .PARAMETER ConfigType
        The configuration type used.

    .PARAMETER OutputValidation
        Optional output from Test-FFUBuildOutput.

    .OUTPUTS
        [string] Formatted verification report.

    .EXAMPLE
        $result = Invoke-FFUTestBuild -ConfigType Minimal -Hypervisor HyperV -TestDriveLetter "D"
        Get-FFUBuildVerificationReport -BuildResult $result
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject]$BuildResult,

        [Parameter()]
        [string]$Hypervisor,

        [Parameter()]
        [string]$ConfigType,

        [Parameter()]
        [PSCustomObject]$OutputValidation
    )

    process {
        $hv = $Hypervisor ?? $BuildResult.Hypervisor
        $ct = $ConfigType ?? $BuildResult.ConfigType
        $status = if ($BuildResult.Success) { 'PASS' } else { 'FAIL' }

        $report = @"
================================================================================
BUILD_VERIFICATION_STATUS: $status
================================================================================

BUILD_CONFIGURATION:
- Config Type: $ct
- Hypervisor: $hv
- Test Drive: $($BuildResult.TestPath.Substring(0,2))
- FFUDevelopmentPath: $($BuildResult.TestPath)

BUILD_EXECUTION:
- Start Time: $($BuildResult.StartTime.ToString('yyyy-MM-dd HH:mm:ss'))
- End Time: $($BuildResult.EndTime.ToString('yyyy-MM-dd HH:mm:ss'))
- Duration: $($BuildResult.DurationString)
- Exit Code: $($BuildResult.ExitCode)

BUILD_OUTPUT:
- FFU Files: $($BuildResult.FFUCount) created
- Deploy Media: $(if ($BuildResult.DeployMediaExists) { 'Created' } else { 'Not Created' })
- Capture Media: $(if ($BuildResult.CaptureMediaExists) { 'Created' } else { 'Not Created' })

"@

        if ($BuildResult.FFUFiles.Count -gt 0) {
            $report += "FFU_FILES:`n"
            foreach ($ffu in $BuildResult.FFUFiles) {
                $sizeGB = [math]::Round($ffu.Length / 1GB, 2)
                $report += "- $($ffu.Name) (${sizeGB}GB)`n"
            }
            $report += "`n"
        }

        if ($OutputValidation) {
            $report += "BUILD_VALIDATIONS:`n"
            foreach ($v in $OutputValidation.Validations) {
                $checkmark = switch ($v.Status) {
                    'PASS' { '[OK]' }
                    'WARN' { '[!!]' }
                    'FAIL' { '[X]' }
                }
                $report += "$checkmark $($v.Check): $($v.Details)`n"
            }
            $report += "`n"
        }

        if (-not $BuildResult.Success) {
            $report += "ERRORS:`n"
            if ($BuildResult.Error) {
                $report += "1. $($BuildResult.Error)`n"
            }
            elseif (Test-Path $BuildResult.StdErrLog) {
                $stderr = Get-Content -Path $BuildResult.StdErrLog -Tail 10 -ErrorAction SilentlyContinue
                if ($stderr) {
                    $report += ($stderr -join "`n") + "`n"
                }
            }
            $report += "`n"
        }

        $recommendation = if ($BuildResult.Success) { 'Continue' } else { 'Fix Required' }
        $report += @"
RECOMMENDATION: $recommendation
================================================================================
"@

        return $report
    }
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Copy-FFUDevelopmentToTestDrive',
    'Invoke-FFUTestBuild',
    'Test-FFUBuildOutput',
    'Get-FFUBuildVerificationReport',
    'Get-FFUTestConfiguration'
)
