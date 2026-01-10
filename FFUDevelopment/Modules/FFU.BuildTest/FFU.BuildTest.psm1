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
$script:DefaultQueuePath = Join-Path $env:TEMP 'FFUBuildQueue'

#endregion

#region Admin Context Functions

function Test-FFUAdminContext {
    <#
    .SYNOPSIS
        Tests if the current PowerShell session has administrator privileges.

    .DESCRIPTION
        Checks if the current user context has administrator privileges.
        If not, provides guidance on how to start the elevated build listener.

    .PARAMETER Quiet
        If specified, suppresses the guidance messages.

    .OUTPUTS
        [bool] True if running as administrator, False otherwise.

    .EXAMPLE
        Test-FFUAdminContext
        # Returns $true if admin, $false with guidance if not

    .EXAMPLE
        if (-not (Test-FFUAdminContext -Quiet)) { throw "Admin required" }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [switch]$Quiet
    )

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin -and -not $Quiet) {
        Write-Warning "FFU Build operations require administrator privileges."
        Write-Host ""
        Write-Host "To run builds with admin privileges:" -ForegroundColor Yellow
        Write-Host "  1. Open PowerShell as Administrator" -ForegroundColor Cyan
        Write-Host "  2. Run: Import-Module FFU.BuildTest" -ForegroundColor Cyan
        Write-Host "  3. Run: Start-FFUBuildListener" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Or use this quick-start command (will prompt UAC):" -ForegroundColor Yellow
        $modulePath = $PSScriptRoot
        $quickCmd = "Start-Process pwsh -Verb RunAs -ArgumentList '-NoExit','-Command',`"Set-Location ''$modulePath''; Import-Module .\FFU.BuildTest.psd1 -Force; Start-FFUBuildListener`""
        Write-Host "  $quickCmd" -ForegroundColor Green
        Write-Host ""
    }

    return $isAdmin
}

function Start-FFUBuildListener {
    <#
    .SYNOPSIS
        Starts an elevated build listener that accepts commands from non-elevated processes.

    .DESCRIPTION
        Creates a file-based command queue that polls for build requests.
        Must be run in an elevated PowerShell session. Non-elevated processes
        can submit commands via Invoke-FFUBuildElevated which writes to the queue.

    .PARAMETER QueuePath
        The directory path for the command queue. Defaults to $env:TEMP\FFUBuildQueue.

    .PARAMETER PollIntervalSeconds
        How often to check for new commands. Defaults to 2 seconds.

    .PARAMETER AutoExit
        If specified, exits after completing one command (useful for single-shot execution).

    .EXAMPLE
        Start-FFUBuildListener
        # Starts listener in foreground, press Ctrl+C to stop

    .EXAMPLE
        Start-FFUBuildListener -PollIntervalSeconds 5 -AutoExit
        # Process one command then exit

    .NOTES
        This function blocks and runs indefinitely until interrupted.
        Run in a separate elevated PowerShell window.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$QueuePath = $script:DefaultQueuePath,

        [Parameter()]
        [ValidateRange(1, 60)]
        [int]$PollIntervalSeconds = 2,

        [Parameter()]
        [switch]$AutoExit
    )

    # Verify admin context
    if (-not (Test-FFUAdminContext -Quiet)) {
        throw "Start-FFUBuildListener requires administrator privileges. Please run PowerShell as Administrator."
    }

    # Create queue directory
    if (-not (Test-Path $QueuePath)) {
        New-Item -Path $QueuePath -ItemType Directory -Force | Out-Null
    }

    $commandFile = Join-Path $QueuePath 'command.json'
    $resultFile = Join-Path $QueuePath 'result.json'
    $statusFile = Join-Path $QueuePath 'listener.status'

    # Write status file so clients know listener is running
    @{
        Started = (Get-Date).ToString('o')
        PID = $PID
        User = [Environment]::UserName
        IsAdmin = $true
    } | ConvertTo-Json | Set-Content $statusFile -Force

    Write-Host "========================================" -ForegroundColor Green
    Write-Host " FFU Build Listener (Administrator)" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "Queue Path: $QueuePath" -ForegroundColor Cyan
    Write-Host "Poll Interval: ${PollIntervalSeconds}s" -ForegroundColor Cyan
    Write-Host "Press Ctrl+C to stop" -ForegroundColor Yellow
    Write-Host ""

    try {
        while ($true) {
            if (Test-Path $commandFile) {
                try {
                    $command = Get-Content $commandFile -Raw | ConvertFrom-Json
                    Remove-Item $commandFile -Force -ErrorAction SilentlyContinue

                    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Received: $($command.Action)" -ForegroundColor Cyan

                    $result = @{
                        Success = $false
                        Output = ''
                        Error = ''
                        ExitCode = -1
                        StartTime = (Get-Date).ToString('o')
                        EndTime = $null
                    }

                    try {
                        switch ($command.Action) {
                            'BuildVerification' {
                                # Run full build verification
                                $params = $command.Parameters
                                $verifyResult = Invoke-FFUBuildVerification @params
                                $result.Success = $verifyResult.OverallStatus -eq 'PASS'
                                $result.Output = $verifyResult | ConvertTo-Json -Depth 10
                                $result.ExitCode = if ($result.Success) { 0 } else { 1 }
                            }
                            'TestBuild' {
                                # Run test build only
                                $params = $command.Parameters
                                $buildResult = Invoke-FFUTestBuild @params
                                $result.Success = $buildResult.Success
                                $result.Output = $buildResult | ConvertTo-Json -Depth 10
                                $result.ExitCode = $buildResult.ExitCode
                            }
                            'CopyToTestDrive' {
                                # Copy FFUDevelopment to test drive
                                $params = $command.Parameters
                                $targetPath = Copy-FFUDevelopmentToTestDrive @params
                                $result.Success = $true
                                $result.Output = $targetPath
                                $result.ExitCode = 0
                            }
                            'ValidateOutput' {
                                # Validate build output
                                $params = $command.Parameters
                                $validation = Test-FFUBuildOutput @params
                                $result.Success = $validation.OverallStatus -eq 'PASS'
                                $result.Output = $validation | ConvertTo-Json -Depth 10
                                $result.ExitCode = if ($result.Success) { 0 } else { 1 }
                            }
                            'Ping' {
                                # Simple connectivity test
                                $result.Success = $true
                                $result.Output = "Listener is running (PID: $PID)"
                                $result.ExitCode = 0
                            }
                            default {
                                $result.Error = "Unknown action: $($command.Action)"
                                $result.ExitCode = 2
                            }
                        }
                    }
                    catch {
                        $result.Error = $_.Exception.Message
                        $result.ExitCode = 1
                    }

                    $result.EndTime = (Get-Date).ToString('o')
                    $result | ConvertTo-Json -Depth 10 | Set-Content $resultFile -Force

                    $statusColor = if ($result.Success) { 'Green' } else { 'Red' }
                    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Completed: $($command.Action) - $(if ($result.Success) { 'SUCCESS' } else { 'FAILED' })" -ForegroundColor $statusColor

                    if ($AutoExit) {
                        Write-Host "AutoExit enabled, stopping listener." -ForegroundColor Yellow
                        break
                    }
                }
                catch {
                    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Error processing command: $_" -ForegroundColor Red
                    @{
                        Success = $false
                        Error = $_.Exception.Message
                        ExitCode = 1
                        EndTime = (Get-Date).ToString('o')
                    } | ConvertTo-Json | Set-Content $resultFile -Force
                }
            }

            Start-Sleep -Seconds $PollIntervalSeconds
        }
    }
    finally {
        # Clean up status file
        if (Test-Path $statusFile) {
            Remove-Item $statusFile -Force -ErrorAction SilentlyContinue
        }
        Write-Host "Listener stopped." -ForegroundColor Yellow
    }
}

function Invoke-FFUBuildElevated {
    <#
    .SYNOPSIS
        Submits a build command to the elevated listener and waits for results.

    .DESCRIPTION
        Writes a command to the file-based queue monitored by Start-FFUBuildListener.
        Waits for the elevated listener to process the command and return results.
        Use this from non-elevated contexts (like Claude Code) to execute admin operations.

    .PARAMETER Action
        The action to perform: BuildVerification, TestBuild, CopyToTestDrive, ValidateOutput, or Ping.

    .PARAMETER Parameters
        Hashtable of parameters to pass to the action.

    .PARAMETER QueuePath
        The directory path for the command queue. Defaults to $env:TEMP\FFUBuildQueue.

    .PARAMETER TimeoutSeconds
        Maximum time to wait for the command to complete. Defaults to 3600 (1 hour).

    .PARAMETER PollIntervalSeconds
        How often to check for results. Defaults to 5 seconds.

    .OUTPUTS
        [PSCustomObject] The result from the elevated listener.

    .EXAMPLE
        Invoke-FFUBuildElevated -Action Ping
        # Tests connectivity to the listener

    .EXAMPLE
        Invoke-FFUBuildElevated -Action BuildVerification -Parameters @{
            ConfigType = 'Minimal'
            Hypervisor = 'VMware'
            TestDriveLetter = 'D'
        }

    .EXAMPLE
        $result = Invoke-FFUBuildElevated -Action CopyToTestDrive -Parameters @{
            TestDriveLetter = 'D'
            CleanFirst = $true
        }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('BuildVerification', 'TestBuild', 'CopyToTestDrive', 'ValidateOutput', 'Ping')]
        [string]$Action,

        [Parameter()]
        [hashtable]$Parameters = @{},

        [Parameter()]
        [string]$QueuePath = $script:DefaultQueuePath,

        [Parameter()]
        [ValidateRange(30, 7200)]
        [int]$TimeoutSeconds = 3600,

        [Parameter()]
        [ValidateRange(1, 60)]
        [int]$PollIntervalSeconds = 5
    )

    $commandFile = Join-Path $QueuePath 'command.json'
    $resultFile = Join-Path $QueuePath 'result.json'
    $statusFile = Join-Path $QueuePath 'listener.status'

    # Check if listener is running
    if (-not (Test-Path $statusFile)) {
        Write-Error "FFU Build Listener is not running."
        Write-Host ""
        Test-FFUAdminContext  # Show guidance
        return $null
    }

    # Verify listener is responsive
    $listenerStatus = Get-Content $statusFile -Raw | ConvertFrom-Json
    Write-Verbose "Listener started: $($listenerStatus.Started), PID: $($listenerStatus.PID)"

    # Clean up any stale result file
    if (Test-Path $resultFile) {
        Remove-Item $resultFile -Force -ErrorAction SilentlyContinue
    }

    # Submit command
    $command = @{
        Action = $Action
        Parameters = $Parameters
        Timestamp = (Get-Date).ToString('o')
        SubmittedBy = [Environment]::UserName
    }

    $command | ConvertTo-Json -Depth 10 | Set-Content $commandFile -Force

    Write-Host "Command submitted: $Action" -ForegroundColor Cyan
    Write-Host "Waiting for elevated listener to process..." -ForegroundColor Yellow

    # Wait for result
    $startTime = Get-Date
    $dotCount = 0

    while (-not (Test-Path $resultFile)) {
        $elapsed = (Get-Date) - $startTime

        if ($elapsed.TotalSeconds -gt $TimeoutSeconds) {
            Write-Host ""
            Write-Error "Timeout waiting for build result after $TimeoutSeconds seconds"
            return $null
        }

        # Progress indicator
        $dotCount++
        if ($dotCount % 12 -eq 0) {
            $elapsedMin = [math]::Round($elapsed.TotalMinutes, 1)
            Write-Host " [${elapsedMin}m]" -ForegroundColor DarkGray
        }
        else {
            Write-Host "." -NoNewline -ForegroundColor DarkGray
        }

        Start-Sleep -Seconds $PollIntervalSeconds
    }

    Write-Host ""

    # Read and return result
    try {
        $result = Get-Content $resultFile -Raw | ConvertFrom-Json
        Remove-Item $resultFile -Force -ErrorAction SilentlyContinue

        if ($result.Success) {
            Write-Host "Command completed successfully." -ForegroundColor Green
        }
        else {
            Write-Host "Command failed: $($result.Error)" -ForegroundColor Red
        }

        return $result
    }
    catch {
        Write-Error "Failed to read result: $_"
        return $null
    }
}

function Test-FFUBuildListenerRunning {
    <#
    .SYNOPSIS
        Tests if the FFU Build Listener is currently running.

    .PARAMETER QueuePath
        The directory path for the command queue. Defaults to $env:TEMP\FFUBuildQueue.

    .OUTPUTS
        [bool] True if listener is running, False otherwise.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [string]$QueuePath = $script:DefaultQueuePath
    )

    $statusFile = Join-Path $QueuePath 'listener.status'
    return (Test-Path $statusFile)
}

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

function Invoke-FFUBuildVerification {
    <#
    .SYNOPSIS
        Executes a complete FFU build verification workflow.

    .DESCRIPTION
        Performs end-to-end build verification:
        1. Copies FFUDevelopment to test drive
        2. Executes test build with specified configuration
        3. Validates build output
        4. Generates structured verification report

        This is the primary function called by the elevated build listener.

    .PARAMETER ConfigType
        The configuration type to use: Minimal, Standard, or UserConfig.

    .PARAMETER Hypervisor
        The hypervisor to use: HyperV, VMware, or Both.

    .PARAMETER TestDriveLetter
        The drive letter for test execution (e.g., "D", "E").

    .PARAMETER SourcePath
        Path to FFUDevelopment folder. Defaults to module parent.

    .PARAMETER VMHostIPAddress
        The IP address of the VM host (for network builds).

    .PARAMETER VMSwitchName
        The Hyper-V switch name (for HyperV builds).

    .PARAMETER CleanFirst
        If specified, removes existing test folder before copying.

    .PARAMETER SkipCopy
        If specified, skips the copy step (assumes test folder exists).

    .OUTPUTS
        [PSCustomObject] Comprehensive verification result with overall status.

    .EXAMPLE
        Invoke-FFUBuildVerification -ConfigType Minimal -Hypervisor VMware -TestDriveLetter D

    .EXAMPLE
        Invoke-FFUBuildVerification -ConfigType Standard -Hypervisor HyperV -TestDriveLetter E `
            -VMSwitchName "Default Switch" -CleanFirst
    #>
    [CmdletBinding()]
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
        [string]$SourcePath,

        [Parameter()]
        [string]$VMHostIPAddress,

        [Parameter()]
        [string]$VMSwitchName,

        [Parameter()]
        [switch]$CleanFirst,

        [Parameter()]
        [switch]$SkipCopy
    )

    $overallStartTime = Get-Date
    $steps = @()

    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "FFU Build Verification - $ConfigType Config on $Hypervisor" -ForegroundColor Cyan
    Write-Host "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host ""

    # Determine source path
    if (-not $SourcePath) {
        $SourcePath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    }

    $testPath = "${TestDriveLetter}:\FFUDevelopment_Test"

    try {
        # Step 1: Copy to test drive
        if (-not $SkipCopy) {
            Write-Host "Step 1: Copying FFUDevelopment to ${TestDriveLetter}:\FFUDevelopment_Test..." -ForegroundColor Yellow

            $copyParams = @{
                SourcePath = $SourcePath
                TestDriveLetter = $TestDriveLetter
                MinimumSpaceGB = if ($ConfigType -eq 'Standard') { 100 } else { 25 }
            }
            if ($CleanFirst) { $copyParams['CleanFirst'] = $true }

            $copyResult = Copy-FFUDevelopmentToTestDrive @copyParams
            Write-Host "   Copied to: $copyResult" -ForegroundColor Green

            # Create Logs directory if it doesn't exist
            $logsDir = Join-Path $testPath 'Logs'
            if (-not (Test-Path $logsDir)) {
                Write-Host "   Creating Logs directory..." -ForegroundColor Gray
                New-Item -Path $logsDir -ItemType Directory -Force | Out-Null
            }

            $steps += @{ Step = 'Copy'; Status = 'Success'; Path = $copyResult }
        }
        else {
            Write-Host "Step 1: Skipping copy (SkipCopy specified)" -ForegroundColor Gray
            if (-not (Test-Path $testPath)) {
                throw "Test path does not exist and SkipCopy was specified: $testPath"
            }
            $steps += @{ Step = 'Copy'; Status = 'Skipped' }
        }

        # Step 2: Execute build
        Write-Host "Step 2: Executing $ConfigType build on $Hypervisor..." -ForegroundColor Yellow
        Write-Host "   This will take approximately $(if ($ConfigType -eq 'Minimal') { '15-25' } else { '40-60' }) minutes..." -ForegroundColor Gray

        $buildParams = @{
            ConfigType = $ConfigType
            Hypervisor = $Hypervisor
            TestDriveLetter = $TestDriveLetter
        }
        if ($VMHostIPAddress) { $buildParams['VMHostIPAddress'] = $VMHostIPAddress }
        if ($VMSwitchName) { $buildParams['VMSwitchName'] = $VMSwitchName }

        $buildResult = Invoke-FFUTestBuild @buildParams
        $steps += @{ Step = 'Build'; Status = if ($buildResult.Success) { 'Success' } else { 'Failed' }; Result = $buildResult }

        if ($buildResult.Success) {
            Write-Host "   Build completed successfully in $($buildResult.DurationString)" -ForegroundColor Green
        }
        else {
            Write-Host "   Build FAILED with exit code: $($buildResult.ExitCode)" -ForegroundColor Red
            if (Test-Path $buildResult.StdErrLog) {
                Write-Host "   Last 20 lines of stderr:" -ForegroundColor Red
                Get-Content $buildResult.StdErrLog -Tail 20 | ForEach-Object { Write-Host "      $_" -ForegroundColor DarkRed }
            }
        }

        # Step 3: Validate output
        Write-Host "Step 3: Validating build output..." -ForegroundColor Yellow

        $validateParams = @{
            FFUPath = Join-Path $testPath 'FFU'
            TestPath = $testPath
            ExpectedSKU = 'Pro'
        }
        if ($ConfigType -eq 'Standard') {
            $validateParams['ExpectDeployMedia'] = $true
            $validateParams['ExpectCaptureMedia'] = $true
        }
        elseif ($ConfigType -eq 'Minimal') {
            $validateParams['ExpectDeployMedia'] = $true
        }

        $validation = Test-FFUBuildOutput @validateParams
        $steps += @{ Step = 'Validate'; Status = $validation.OverallStatus; Result = $validation }

        Write-Host "   Validation Status: $($validation.OverallStatus)" -ForegroundColor $(if ($validation.OverallStatus -eq 'PASS') { 'Green' } else { 'Red' })
        foreach ($v in $validation.Validations) {
            $prefix = switch ($v.Status) { 'PASS' { '[OK]' } 'WARN' { '[!!]' } 'FAIL' { '[X]' } }
            Write-Host "   - $($v.Check): $($v.Status) - $($v.Details)" -ForegroundColor $(if ($v.Status -eq 'PASS') { 'Gray' } elseif ($v.Status -eq 'WARN') { 'Yellow' } else { 'Red' })
        }

        # Step 4: Generate report
        Write-Host "Step 4: Generating verification report..." -ForegroundColor Yellow
        $report = Get-FFUBuildVerificationReport -BuildResult $buildResult -OutputValidation $validation
        Write-Host $report

        # Determine overall status
        $overallStatus = if ($buildResult.Success -and $validation.OverallStatus -eq 'PASS') { 'PASS' } else { 'FAIL' }
        $overallEndTime = Get-Date
        $totalDuration = $overallEndTime - $overallStartTime

        Write-Host ""
        Write-Host "========================================================" -ForegroundColor $(if ($overallStatus -eq 'PASS') { 'Green' } else { 'Red' })
        Write-Host "Total Verification Time: $("{0:hh\:mm\:ss}" -f $totalDuration)" -ForegroundColor Cyan
        Write-Host "Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
        Write-Host "========================================================" -ForegroundColor $(if ($overallStatus -eq 'PASS') { 'Green' } else { 'Red' })
        Write-Host "OVERALL: $overallStatus" -ForegroundColor $(if ($overallStatus -eq 'PASS') { 'Green' } else { 'Red' })

        return [PSCustomObject]@{
            OverallStatus = $overallStatus
            ConfigType = $ConfigType
            Hypervisor = $Hypervisor
            TestPath = $testPath
            StartTime = $overallStartTime
            EndTime = $overallEndTime
            Duration = $totalDuration
            DurationString = "{0:hh\:mm\:ss}" -f $totalDuration
            Steps = $steps
            BuildResult = $buildResult
            Validation = $validation
            Report = $report
        }
    }
    catch {
        Write-Host "FATAL ERROR: $_" -ForegroundColor Red
        $overallEndTime = Get-Date

        return [PSCustomObject]@{
            OverallStatus = 'FAIL'
            ConfigType = $ConfigType
            Hypervisor = $Hypervisor
            TestPath = $testPath
            StartTime = $overallStartTime
            EndTime = $overallEndTime
            Duration = $overallEndTime - $overallStartTime
            DurationString = "{0:hh\:mm\:ss}" -f ($overallEndTime - $overallStartTime)
            Steps = $steps
            Error = $_.Exception.Message
        }
    }
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    # Admin context functions
    'Test-FFUAdminContext',
    'Start-FFUBuildListener',
    'Invoke-FFUBuildElevated',
    'Test-FFUBuildListenerRunning',
    # Build verification functions
    'Copy-FFUDevelopmentToTestDrive',
    'Invoke-FFUTestBuild',
    'Invoke-FFUBuildVerification',
    'Test-FFUBuildOutput',
    'Get-FFUBuildVerificationReport',
    'Get-FFUTestConfiguration'
)
