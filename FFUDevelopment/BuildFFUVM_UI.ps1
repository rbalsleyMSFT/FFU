<#
.SYNOPSIS
    Launches the FFU Development UI, a WPF application for configuring and running the FFU build process.
.DESCRIPTION
    The BuildFFUVM_UI.ps1 script is the main entry point for the FFU Development user interface. It initializes and displays a WPF-based graphical interface defined in BuildFFUVM_UI.xaml.

    The script is responsible for:
    - Initializing a global state object to manage UI controls, data, and application flags.
    - Importing the required FFU.Common and FFUUI.Core modules which contain the business logic.
    - Ensuring system prerequisites, such as PowerShell 7 and Long Path Support, are met.
    - Loading the XAML window, initializing UI controls with default values, and registering all event handlers.
    - Launching the core build script (BuildFFUVM.ps1) in a background job when the user initiates a build.
    - Providing real-time feedback by monitoring the build log file and updating the UI's progress bar and log viewer.
    - Handling cleanup operations, such as reverting system settings, when the application is closed.

    This script acts as the primary host for the UI, connecting the user interface with the underlying build and logic modules.
#>
#Requires -RunAsAdministrator

[CmdletBinding()]
[System.STAThread()]
param()

# Check PowerShell Version
# Note: FFUBuilder supports both PowerShell 5.1 and 7+ with cross-version compatibility
# - Windows management cmdlets use .NET DirectoryServices APIs for compatibility
# - UI works best in PowerShell 7+ for modern features and performance
# - PowerShell 5.1 is minimum requirement (included with Windows 10/11)
if ($PSVersionTable.PSVersion.Major -lt 5 -or ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -lt 1)) {
    Write-Error "PowerShell 5.1 or later is required to run this script."
    exit 1
}

# FFU Builder Version - loaded from version.json (single source of truth)
$FFUDevelopmentPath = $PSScriptRoot
$script:versionJsonPath = Join-Path $FFUDevelopmentPath "version.json"
if (Test-Path $script:versionJsonPath) {
    $script:versionInfo = Get-Content $script:versionJsonPath -Raw | ConvertFrom-Json
    $script:FFUBuilderVersion = $script:versionInfo.version
    $script:FFUBuilderBuildDate = $script:versionInfo.buildDate
    $script:FFUBuilderModules = $script:versionInfo.modules
}
else {
    # Fallback if version.json not found
    $script:FFUBuilderVersion = "1.2.0"
    $script:FFUBuilderBuildDate = "2025-12-09"
    $script:FFUBuilderModules = $null
    Write-Warning "version.json not found at $script:versionJsonPath - using fallback version"
}

# Creating custom state object to hold UI state and data

$script:uiState = [PSCustomObject]@{
    FFUDevelopmentPath = $FFUDevelopmentPath;
    Window             = $null;
    Controls           = @{
        featureCheckBoxes               = @{};
        UpdateInstallAppsBasedOnUpdates = $null
    };
    Data               = @{
        allDriverModels             = [System.Collections.Generic.List[PSCustomObject]]::new();
        appsScriptVariablesDataList = [System.Collections.Generic.List[PSCustomObject]]::new();
        versionData                 = $null;
        vmSwitchMap                 = @{};
        logData                     = $null;
        logStreamReader             = $null;
        pollTimer                   = $null;
        lastConfigFilePath          = $null
    };
    Flags              = @{
        installAppsForcedByUpdates        = $false;
        prevInstallAppsStateBeforeUpdates = $null;
        installAppsCheckedByOffice        = $false;
        lastSortProperty                  = $null;
        lastSortAscending                 = $true;
        isBuilding                        = $false;
        isCleanupRunning                  = $false
    };
    Defaults           = @{};
    LogFilePath        = "$FFUDevelopmentPath\FFUDevelopment_UI.log";
    Version            = @{
        Number    = $script:FFUBuilderVersion
        BuildDate = $script:FFUBuilderBuildDate
        Modules   = $script:FFUBuilderModules
    }
}

# Remove any existing modules to avoid conflicts
if (Get-Module -Name 'FFU.Common' -ErrorAction SilentlyContinue) {
    Remove-Module -Name 'FFU.Common' -Force
}
if (Get-Module -Name 'FFUUI.Core' -ErrorAction SilentlyContinue) {
    Remove-Module -Name 'FFUUI.Core' -Force
}
# Import Modules
Import-Module "$PSScriptRoot\FFU.Common" -Force
Import-Module "$PSScriptRoot\FFUUI.Core" -Force

# Import ThreadJob module for better credential handling in background jobs
# ThreadJob runs jobs as threads in the current process, preserving network credentials
# This fixes BITS authentication error 0x800704DD (ERROR_NOT_LOGGED_ON)
if (-not (Get-Module -ListAvailable -Name ThreadJob)) {
    WriteLog "ThreadJob module not found. Attempting to install..."
    try {
        Install-Module -Name ThreadJob -Force -Scope CurrentUser -ErrorAction Stop
        WriteLog "ThreadJob module installed successfully."
    }
    catch {
        Write-Warning "Failed to install ThreadJob module: $($_.Exception.Message)"
        Write-Warning "BITS transfers may fail with authentication errors (0x800704DD)."
        Write-Warning "Install ThreadJob manually: Install-Module -Name ThreadJob -Scope CurrentUser"
    }
}

if (Get-Module -ListAvailable -Name ThreadJob) {
    Import-Module ThreadJob -Force
    WriteLog "ThreadJob module loaded successfully."
}
else {
    Write-Warning "ThreadJob module not available. Using Start-Job (may cause BITS authentication issues)."
}

# Set the log path
Set-CommonCoreLogPath -Path $script:uiState.LogFilePath

# Setting long path support - this prevents issues where some applications have deep directory structures
# and driver extraction fails due to long paths.
$script:uiState.Flags.originalLongPathsValue = $null # Store original value
try {
    $script:uiState.Flags.originalLongPathsValue = Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -ErrorAction SilentlyContinue
}
catch {
    # Key or value might not exist, which is fine.
    WriteLog "Could not read initial LongPathsEnabled value (may not exist)."
}

# Enable long paths if not already enabled
if ($script:uiState.Flags.originalLongPathsValue -ne 1) {
    try {
        WriteLog 'LongPathsEnabled is not set to 1. Setting it to 1 for the duration of this script.'
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Value 1 -Force
        WriteLog 'LongPathsEnabled set to 1.'
    }
    catch {
        WriteLog "Error setting LongPathsEnabled registry key: $($_.Exception.Message). Long path issues might persist."
    }
}
else {
    WriteLog "LongPathsEnabled is already set to 1."
}

if (Test-Path -Path $script:uiState.LogFilePath) {
    Remove-item -Path $script:uiState.LogFilePath -Force
}

Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName PresentationCore, PresentationFramework
Add-Type -AssemblyName System.Windows.Forms

# Load XAML
$xamlPath = Join-Path $PSScriptRoot "BuildFFUVM_UI.xaml"
if (-not (Test-Path $xamlPath)) {
    Write-Error "XAML file not found: $xamlPath"
    return
}
$xamlString = Get-Content $xamlPath -Raw
$reader = New-Object System.IO.StringReader($xamlString)
$xmlReader = [System.Xml.XmlReader]::Create($reader)
$window = [Windows.Markup.XamlReader]::Load($xmlReader)

$window.Add_Loaded({
        # Pass the state object to all initialization functions
        $script:uiState.Window = $window
        $window.Tag = $script:uiState

        # Update window title with version
        $window.Title = "FFU Builder UI v$($script:uiState.Version.Number)"

        Initialize-UIControls -State $script:uiState
        Initialize-UIDefaults -State $script:uiState
        Initialize-DynamicUIElements -State $script:uiState
        Register-EventHandlers -State $script:uiState

        # Initialize About tab
        Initialize-AboutTab -State $script:uiState

        # Attempt automatic load of previous environment (silent)
        try {
            Invoke-AutoLoadPreviousEnvironment -State $script:uiState
        }
        catch {
            WriteLog "Auto-load previous environment failed: $($_.Exception.Message)"
        }
    })


# Button: Build FFU
$script:uiState.Controls.btnRun = $window.FindName('btnRun')
$script:uiState.Controls.btnRun.Add_Click({
        # Get a local reference to the button for convenience in this handler
        $btnRun = $script:uiState.Controls.btnRun
        try {
            # If a build is running and cleanup is not already running, treat this click as Cancel
            if ($script:uiState.Flags.isBuilding -and -not $script:uiState.Flags.isCleanupRunning) {
                $btnRun.IsEnabled = $false
                $script:uiState.Controls.txtStatus.Text = "Cancel requested. Stopping build..."
                WriteLog "Cancel requested by user. Stopping background build job."

                # Stop the timer
                if ($null -ne $script:uiState.Data.pollTimer) {
                    $script:uiState.Data.pollTimer.Stop()
                    $script:uiState.Data.pollTimer = $null
                }

                # Close the log stream
                if ($null -ne $script:uiState.Data.logStreamReader) {
                    $script:uiState.Data.logStreamReader.Close()
                    $script:uiState.Data.logStreamReader.Dispose()
                    $script:uiState.Data.logStreamReader = $null
                }

                # Stop and remove the running build job
                $jobToStop = $script:uiState.Data.currentBuildJob
                $script:uiState.Data.currentBuildJob = $null
                if ($null -ne $jobToStop) {
                    try {
                        # Attempt graceful stop first
                        Stop-Job -Job $jobToStop -ErrorAction SilentlyContinue
                        Wait-Job -Job $jobToStop -Timeout 5 -ErrorAction SilentlyContinue | Out-Null
                    }
                    catch {
                        WriteLog "Stop-Job threw: $($_.Exception.Message)"
                    }

                    # If the job's hosting process is still alive, kill its process tree to stop child tools like DISM
                    try {
                        $jobProcId = $null
                        if ($null -ne $jobToStop.ChildJobs -and $jobToStop.ChildJobs.Count -gt 0) {
                            $jobProcId = $jobToStop.ChildJobs[0].ProcessId
                        }
                        if ($jobProcId) {
                            # Recursively terminate the job process and any children
                            function Stop-ProcessTree {
                                param([int]$parentPid)
                                $children = Get-CimInstance Win32_Process -Filter "ParentProcessId=$parentPid" -ErrorAction SilentlyContinue
                                foreach ($child in $children) {
                                    Stop-ProcessTree -parentPid $child.ProcessId
                                }
                                try { Stop-Process -Id $parentPid -Force -ErrorAction SilentlyContinue } catch {}
                            }
                            Stop-ProcessTree -parentPid $jobProcId
                        }
                    }
                    catch {
                        WriteLog "Error terminating job process tree: $($_.Exception.Message)"
                    }

                    # Safety net: kill any active DISM capture still running
                    try {
                        $dismCaptures = Get-CimInstance Win32_Process -Filter "Name='DISM.EXE'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match '/Capture-FFU' }
                        foreach ($p in $dismCaptures) {
                            try { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
                        }
                    }
                    catch {
                        WriteLog "Error stopping DISM capture processes: $($_.Exception.Message)"
                    }

                    # Also stop Office ODT setup.exe if running (to avoid recreating files after cleanup)
                    try {
                        $officePathForKill = $null

                        # Prefer explicit UI path
                        $uiOfficePath = $script:uiState.Controls.txtOfficePath.Text
                        if (-not [string]::IsNullOrWhiteSpace($uiOfficePath)) {
                            $officePathForKill = $uiOfficePath
                        }
                        else {
                            # Fall back to the last config path only if known
                            $lastConfigPathLocal = $script:uiState.Data.lastConfigFilePath
                            if (-not [string]::IsNullOrWhiteSpace($lastConfigPathLocal)) {
                                $ffuDevRoot = Split-Path (Split-Path $lastConfigPathLocal -Parent) -Parent
                                if (-not [string]::IsNullOrWhiteSpace($ffuDevRoot)) {
                                    $officePathForKill = Join-Path $ffuDevRoot 'Apps\Office'
                                }
                            }
                        }

                        # Only proceed when a valid Office folder exists
                        if ($officePathForKill -and (Test-Path -LiteralPath $officePathForKill -PathType Container)) {
                            $setupProcs = Get-CimInstance Win32_Process -Filter "Name='setup.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.ExecutablePath -like "$officePathForKill*" }
                            foreach ($p in $setupProcs) {
                                try { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
                            }
                        }
                    }
                    catch {
                        WriteLog "Error stopping Office setup.exe processes: $($_.Exception.Message)"
                    }

                    try {
                        Remove-Job -Job $jobToStop -Force -ErrorAction SilentlyContinue
                        WriteLog "Background build job stopped and removed."
                    }
                    catch {
                        WriteLog "Error removing background build job: $($_.Exception.Message)"
                    }
                }

                # Start cleanup using the same BuildFFUVM.ps1 via -Cleanup short-circuit
                $lastConfigPath = $script:uiState.Data.lastConfigFilePath
                if ([string]::IsNullOrWhiteSpace($lastConfigPath)) {
                    WriteLog "No stored config file path found. Cleanup cannot proceed."
                    $script:uiState.Controls.txtStatus.Text = "Build canceled. No config found for cleanup."
                    $script:uiState.Flags.isBuilding = $false
                    $script:uiState.Flags.isCleanupRunning = $false
                    $btnRun.Content = "Build FFU"
                    $btnRun.IsEnabled = $true
                    return
                }

                $ffuDevPath = Split-Path (Split-Path $lastConfigPath -Parent) -Parent
                $mainLogPath = Join-Path $ffuDevPath "FFUDevelopment.log"

                WriteLog "Starting cleanup without deleting FFUDevelopment.log (will append new entries)."

                $script:uiState.Controls.txtStatus.Text = "Cancel in progress... Cleaning environment..."
                WriteLog "Starting cleanup job (BuildFFUVM.ps1 -Cleanup)."

                # Prepare parameters for cleanup
                # Inform user: in-progress items will be removed; ask whether to also remove other items downloaded during this run
                $removeCurrentRunToo = $false
                $promptText = "Cancel requested.`n`nWe'll remove the download currently in progress to avoid partial/corrupt content.`n`nDo you also want to remove other items downloaded during this run? Previously downloaded items will be kept."
                $result = [System.Windows.MessageBox]::Show($promptText, "Cancel cleanup options", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
                if ($result -eq [System.Windows.MessageBoxResult]::Yes) { $removeCurrentRunToo = $true }

                $cleanupParams = @{
                    ConfigFile                 = $lastConfigPath
                    Cleanup                    = $true
                    # Avoid wiping all user content on cancel
                    RemoveApps                 = $false
                    RemoveUpdates              = $false
                    CleanupDrivers             = $false
                    # Scoped removal to current run only (optional per user choice)
                    CleanupCurrentRunDownloads = $removeCurrentRunToo
                }

                $cleanupScriptBlock = {
                    param($buildParams, $PSScriptRoot)
                    & "$PSScriptRoot\BuildFFUVM.ps1" @buildParams
                }

                # Start cleanup job using ThreadJob for credential inheritance
                # ThreadJob preserves network credentials, preventing BITS error 0x800704DD
                if (Get-Command Start-ThreadJob -ErrorAction SilentlyContinue) {
                    $script:uiState.Data.currentBuildJob = Start-ThreadJob -ScriptBlock $cleanupScriptBlock -ArgumentList @($cleanupParams, $PSScriptRoot)
                    WriteLog "Cleanup job started using ThreadJob (with network credential inheritance)."
                }
                else {
                    $script:uiState.Data.currentBuildJob = Start-Job -ScriptBlock $cleanupScriptBlock -ArgumentList @($cleanupParams, $PSScriptRoot)
                    WriteLog "WARNING: Cleanup job started using Start-Job (network credentials may not be available for BITS transfers)."
                }

                # Wait for log file to appear (or open immediately if it exists)
                $logWaitTimeout = 60
                $watch = [System.Diagnostics.Stopwatch]::StartNew()
                while (-not (Test-Path $mainLogPath) -and $watch.Elapsed.TotalSeconds -lt $logWaitTimeout) {
                    Start-Sleep -Milliseconds 250
                }
                $watch.Stop()

                # Open log stream for cleanup (tail to end to avoid re-reading the whole file)
                if (Test-Path $mainLogPath) {
                    $fileStream = [System.IO.File]::Open($mainLogPath, 'Open', 'Read', 'ReadWrite')
                    [void]$fileStream.Seek(0, [System.IO.SeekOrigin]::End)
                    $script:uiState.Data.logStreamReader = [System.IO.StreamReader]::new($fileStream)
                }
                else {
                    WriteLog "Warning: Main log file not found at $mainLogPath after waiting. Monitor tab will not update during cleanup."
                }

                # Create a timer to poll the cleanup job
                $script:uiState.Data.pollTimer = New-Object System.Windows.Threading.DispatcherTimer
                $script:uiState.Data.pollTimer.Interval = [TimeSpan]::FromSeconds(1)
                $script:uiState.Flags.isCleanupRunning = $true

                $script:uiState.Data.pollTimer.Add_Tick({
                        param($sender, $e)
                        $currentJob = $script:uiState.Data.currentBuildJob

                        # Read new lines from log
                        if ($null -ne $script:uiState.Data.logStreamReader) {
                            while ($null -ne ($line = $script:uiState.Data.logStreamReader.ReadLine())) {
                                $script:uiState.Data.logData.Add($line)
                                if ($script:uiState.Flags.autoScrollLog) {
                                    $script:uiState.Controls.lstLogOutput.ScrollIntoView($line)
                                    $script:uiState.Controls.lstLogOutput.SelectedIndex = $script:uiState.Controls.lstLogOutput.Items.Count - 1
                                }
                            }
                        }

                        if ($null -eq $currentJob -or $null -eq $script:uiState.Data.pollTimer) {
                            if ($null -ne $sender) { $sender.Stop() }
                            $script:uiState.Data.pollTimer = $null
                            return
                        }

                        if ($currentJob.State -in 'Completed', 'Failed', 'Stopped') {
                            if ($null -ne $sender) { $sender.Stop() }
                            $script:uiState.Data.pollTimer = $null

                            if ($null -ne $script:uiState.Data.logStreamReader) {
                                $lastLine = $null
                                while ($null -ne ($line = $script:uiState.Data.logStreamReader.ReadLine())) {
                                    $script:uiState.Data.logData.Add($line)
                                    $lastLine = $line
                                }
                                if ($script:uiState.Flags.autoScrollLog -and $null -ne $lastLine) {
                                    $script:uiState.Controls.lstLogOutput.ScrollIntoView($lastLine)
                                    $script:uiState.Controls.lstLogOutput.SelectedIndex = $script:uiState.Controls.lstLogOutput.Items.Count - 1
                                }
                                $script:uiState.Data.logStreamReader.Close()
                                $script:uiState.Data.logStreamReader.Dispose()
                                $script:uiState.Data.logStreamReader = $null
                            }

                            $script:uiState.Controls.txtStatus.Text = "Build canceled. Environment cleaned."
                            $script:uiState.Controls.pbOverallProgress.Visibility = 'Collapsed'
                            $script:uiState.Controls.pbOverallProgress.Value = 0

                            # Receive and remove cleanup job
                            $currentJob | Receive-Job -ErrorAction SilentlyContinue | Out-Null
                            Remove-Job -Job $currentJob -Force
                            $script:uiState.Data.currentBuildJob = $null

                            # Reset flags and button
                            $script:uiState.Flags.isCleanupRunning = $false
                            $script:uiState.Flags.isBuilding = $false
                            $btn = $script:uiState.Controls.btnRun
                            $btn.Content = "Build FFU"
                            $btn.IsEnabled = $true
                        }
                    })

                $script:uiState.Data.pollTimer.Start()
                return
            }

            # Not currently building: start a new build
            $btnRun.IsEnabled = $false

            # Switch to Monitor Tab
            $script:uiState.Controls.MainTabControl.SelectedItem = $script:uiState.Controls.MonitorTab
            
            # Clear previous log data and reset autoscroll
            if ($null -ne $script:uiState.Data.logData) {
                $script:uiState.Data.logData.Clear()
                $script:uiState.Flags.autoScrollLog = $true
            }

            # Close any existing StreamReader from previous builds to release file handle
            if ($null -ne $script:uiState.Data.logStreamReader) {
                try {
                    $script:uiState.Data.logStreamReader.Close()
                    $script:uiState.Data.logStreamReader.Dispose()
                }
                catch {
                    # Ignore errors when closing stale reader
                }
                $script:uiState.Data.logStreamReader = $null
            }

            $progressBar = $script:uiState.Controls.pbOverallProgress
            $txtStatus = $script:uiState.Controls.txtStatus
            $progressBar.Visibility = 'Visible'
            $txtStatus.Text = "Starting FFU build..."
            
            # Gather config on the UI thread before starting the job
            $config = Get-UIConfig -State $script:uiState

            # Validate Additional FFU selection if enabled
            if ($config.BuildUSBDrive -and $config.CopyAdditionalFFUFiles -and (($null -eq $config.AdditionalFFUFiles) -or ($config.AdditionalFFUFiles.Count -eq 0))) {
                [System.Windows.MessageBox]::Show("Please select at least one additional FFU file to copy, or uncheck 'Copy Additional FFU Files'.", "Selection Required", "OK", "Warning") | Out-Null
                $btnRun.IsEnabled = $true
                $script:uiState.Controls.txtStatus.Text = "Build canceled: Additional FFU selection required."
                return
            }

            # PRE-FLIGHT VALIDATION: Verify FFUDevelopmentPath exists and is valid
            $ffuDevPath = $config.FFUDevelopmentPath
            if ([string]::IsNullOrWhiteSpace($ffuDevPath)) {
                [System.Windows.MessageBox]::Show("FFU Development Path is not set. Please specify a valid path in the Build tab.", "Configuration Error", "OK", "Error") | Out-Null
                $btnRun.IsEnabled = $true
                $script:uiState.Controls.txtStatus.Text = "Build canceled: FFU Development Path not set."
                return
            }

            # Check if path exists
            if (-not (Test-Path -LiteralPath $ffuDevPath -PathType Container)) {
                $msgResult = [System.Windows.MessageBox]::Show(
                    "FFU Development Path does not exist:`n`n$ffuDevPath`n`nBuildFFUVM.ps1 will fail immediately with parameter validation error.`n`nDo you want to create this directory?",
                    "Path Not Found",
                    "YesNo",
                    "Warning"
                )
                if ($msgResult -eq [System.Windows.MessageBoxResult]::Yes) {
                    try {
                        New-Item -ItemType Directory -Path $ffuDevPath -Force | Out-Null
                        WriteLog "Created FFU Development Path: $ffuDevPath"
                    }
                    catch {
                        [System.Windows.MessageBox]::Show("Failed to create directory:`n`n$($_.Exception.Message)", "Error", "OK", "Error") | Out-Null
                        $btnRun.IsEnabled = $true
                        $script:uiState.Controls.txtStatus.Text = "Build canceled: Could not create FFU Development Path."
                        return
                    }
                }
                else {
                    $btnRun.IsEnabled = $true
                    $script:uiState.Controls.txtStatus.Text = "Build canceled: FFU Development Path does not exist."
                    return
                }
            }

            # Ensure config subdirectory exists (required for saving build configuration)
            $configDir = Join-Path $ffuDevPath "config"
            if (-not (Test-Path -LiteralPath $configDir -PathType Container)) {
                try {
                    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
                    WriteLog "Created config subdirectory: $configDir"
                }
                catch {
                    [System.Windows.MessageBox]::Show("Failed to create config subdirectory:`n`n$($_.Exception.Message)`n`nThe build cannot proceed without this directory.", "Error", "OK", "Error") | Out-Null
                    $btnRun.IsEnabled = $true
                    $script:uiState.Controls.txtStatus.Text = "Build canceled: Could not create config subdirectory."
                    return
                }
            }

            # Warn if FFUDevelopmentPath doesn't match where UI is running from
            $expectedPath = $script:uiState.FFUDevelopmentPath
            if ($ffuDevPath -ne $expectedPath) {
                WriteLog "WARNING: FFU Development Path ($ffuDevPath) does not match UI script location ($expectedPath)"
                WriteLog "This may indicate a configuration loaded from a different installation location."
                $msgResult = [System.Windows.MessageBox]::Show(
                    "WARNING: FFU Development Path mismatch detected.`n`n" +
                    "Configured Path: $ffuDevPath`n" +
                    "UI Location: $expectedPath`n`n" +
                    "This usually means you loaded a configuration file from a different FFUBuilder installation.`n`n" +
                    "Using a mismatched path may cause builds to fail or produce unexpected results.`n`n" +
                    "Do you want to continue anyway?",
                    "Path Mismatch Warning",
                    "YesNo",
                    "Warning"
                )
                if ($msgResult -eq [System.Windows.MessageBoxResult]::No) {
                    $btnRun.IsEnabled = $true
                    $script:uiState.Controls.txtStatus.Text = "Build canceled: Path mismatch."
                    return
                }
            }

            $configFilePath = Join-Path $config.FFUDevelopmentPath "\config\FFUConfig.json"
            # Sort top-level keys alphabetically for consistent output
            $sortedConfig = [ordered]@{}
            foreach ($k in ($config.Keys | Sort-Object)) { $sortedConfig[$k] = $config[$k] }

            # Save config file with error handling
            try {
                $sortedConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $configFilePath -Encoding UTF8 -ErrorAction Stop
                $script:uiState.Data.lastConfigFilePath = $configFilePath
                WriteLog "Build configuration saved to: $configFilePath"
            }
            catch {
                $errorMsg = "Failed to save build configuration file:`n`n$($_.Exception.Message)`n`nPath: $configFilePath`n`nPlease verify write permissions and disk space."
                WriteLog "ERROR: $errorMsg"
                [System.Windows.MessageBox]::Show($errorMsg, "Configuration Save Error", "OK", "Error") | Out-Null
                $btnRun.IsEnabled = $true
                $script:uiState.Controls.txtStatus.Text = "Build canceled: Could not save configuration."
                return
            }
            
            if ($config.InstallOffice -and $config.OfficeConfigXMLFile) {
                Copy-Item -Path $config.OfficeConfigXMLFile -Destination $config.OfficePath -Force
                WriteLog "Office Configuration XML file copied successfully."
            }
            
            $txtStatus.Text = "Executing BuildFFUVM.ps1 in the background..."
            WriteLog "Executing BuildFFUVM.ps1 in the background..."

            # Define main log path for monitoring (matches cleanup flow definition)
            $mainLogPath = Join-Path $ffuDevPath "FFUDevelopment.log"

            # Prepare parameters for splatting
            $buildParams = @{
                ConfigFile = $configFilePath
            }
            if ($config.Verbose) {
                $buildParams['Verbose'] = $true
            }

            # Define the script block to run in the background job
            $scriptBlock = {
                param($buildParams, $ScriptRoot)

                # Set working directory to the script's location
                # This ensures BuildFFUVM.ps1 runs with the correct working directory context.
                # ThreadJobs start in the user's Documents folder, not the script's directory.
                # Setting location here provides defense-in-depth for any relative path operations.
                Set-Location $ScriptRoot

                # This script runs in a new process. BuildFFUVM.ps1 is expected to handle its own module imports.
                & "$ScriptRoot\BuildFFUVM.ps1" @buildParams
            }

            # FIX: Delete old log file BEFORE starting the background job to prevent race condition
            # where the UI's StreamReader opens the old log file before the background job deletes it.
            # This prevents stale log entries from appearing in the Monitor tab.
            if (Test-Path $mainLogPath) {
                try {
                    Remove-Item -Path $mainLogPath -Force -ErrorAction Stop
                    WriteLog "Removed previous log file to prevent race condition."
                    # Small delay to ensure file system operation completes
                    Start-Sleep -Milliseconds 100
                }
                catch {
                    # Log warning but don't fail the build - the background job will handle it
                    WriteLog "Warning: Could not remove old log file: $($_.Exception.Message)"
                }
            }

            # Start the job and store it in the shared state object
            # Use ThreadJob for credential inheritance (fixes BITS error 0x800704DD)
            if (Get-Command Start-ThreadJob -ErrorAction SilentlyContinue) {
                $script:uiState.Data.currentBuildJob = Start-ThreadJob -ScriptBlock $scriptBlock -ArgumentList @($buildParams, $PSScriptRoot)
                WriteLog "Build job started using ThreadJob (with network credential inheritance)."
            }
            else {
                $script:uiState.Data.currentBuildJob = Start-Job -ScriptBlock $scriptBlock -ArgumentList @($buildParams, $PSScriptRoot)
                WriteLog "WARNING: Build job started using Start-Job (network credentials may not be available for BITS transfers)."
            }

            # Wait for the new log file to be created by the background job.
            $logWaitTimeout = 15 # seconds
            $watch = [System.Diagnostics.Stopwatch]::StartNew()
            while (-not (Test-Path $mainLogPath) -and $watch.Elapsed.TotalSeconds -lt $logWaitTimeout) {
                Start-Sleep -Milliseconds 250
            }
            $watch.Stop()

            # Open a stream reader to the main log file
            if (Test-Path $mainLogPath) {
                $fileStream = [System.IO.File]::Open($mainLogPath, 'Open', 'Read', 'ReadWrite')
                $script:uiState.Data.logStreamReader = [System.IO.StreamReader]::new($fileStream)
            }
            else {
                WriteLog "Warning: Main log file not found at $mainLogPath after waiting. Monitor tab will not update."
            }

            # Create a timer to poll the job status from the UI thread
            $script:uiState.Data.pollTimer = New-Object System.Windows.Threading.DispatcherTimer
            $script:uiState.Data.pollTimer.Interval = [TimeSpan]::FromSeconds(1)
            
            # Add the Tick event handler
            $script:uiState.Data.pollTimer.Add_Tick({
                    param($sender, $e)
                    # This scriptblock runs on the UI thread, so it can safely access script-scoped variables
                    $currentJob = $script:uiState.Data.currentBuildJob
                    
                    # Read from log stream
                    if ($null -ne $script:uiState.Data.logStreamReader) {
                        while ($null -ne ($line = $script:uiState.Data.logStreamReader.ReadLine())) {
                            # Add the full line to the log view first to maintain consistency
                            $script:uiState.Data.logData.Add($line)
                            if ($script:uiState.Flags.autoScrollLog) {
                                $script:uiState.Controls.lstLogOutput.ScrollIntoView($line)
                                $script:uiState.Controls.lstLogOutput.SelectedIndex = $script:uiState.Controls.lstLogOutput.Items.Count - 1
                            }

                            # Now, check if it's a progress line and update the UI accordingly
                            if ($line -match '\[PROGRESS\] (\d{1,3}) \| (.*)') {
                                $percentage = [double]$matches[1]
                                $message = $matches[2]
                                
                                # Update progress bar and status text
                                $script:uiState.Controls.pbOverallProgress.Value = $percentage
                                $script:uiState.Controls.txtStatus.Text = $message
                            }
                        }
                    }

                    # If job is somehow null or the timer has been nulled out, stop the timer
                    if ($null -eq $currentJob -or $null -eq $script:uiState.Data.pollTimer) {
                        if ($null -ne $sender) {
                            $sender.Stop()
                        }
                        $script:uiState.Data.pollTimer = $null
                        return
                    }

                    # Check if the job has reached a terminal state
                    if ($currentJob.State -in 'Completed', 'Failed', 'Stopped') {
                        # Stop the timer, we're done polling
                        if ($null -ne $sender) {
                            $sender.Stop()
                        }
                        $script:uiState.Data.pollTimer = $null
                        
                        # Final read of the log stream
                        if ($null -ne $script:uiState.Data.logStreamReader) {
                            $lastLine = $null
                            while ($null -ne ($line = $script:uiState.Data.logStreamReader.ReadLine())) {
                                # Add the full line to the log view first
                                $script:uiState.Data.logData.Add($line)
                                $lastLine = $line

                                # Now, check if it's a progress line and update the UI accordingly
                                if ($line -match '\[PROGRESS\] (\d{1,3}) \| (.*)') {
                                    $percentage = [double]$matches[1]
                                    $message = $matches[2]
                                    
                                    $script:uiState.Controls.pbOverallProgress.Value = $percentage
                                    $script:uiState.Controls.txtStatus.Text = $message
                                }
                            }
                            
                            # After the final read, scroll to the last line if autoscroll is enabled
                            if ($script:uiState.Flags.autoScrollLog -and $null -ne $lastLine) {
                                $script:uiState.Controls.lstLogOutput.ScrollIntoView($lastLine)
                                $script:uiState.Controls.lstLogOutput.SelectedIndex = $script:uiState.Controls.lstLogOutput.Items.Count - 1
                            }

                            $script:uiState.Data.logStreamReader.Close()
                            $script:uiState.Data.logStreamReader.Dispose()
                            $script:uiState.Data.logStreamReader = $null
                        }

                        # Determine final status based on job result and error output
                        # Even "Completed" jobs can have errors (e.g., parameter validation failures)
                        $jobOutput = Receive-Job -Job $currentJob -Keep -ErrorVariable jobErrors -ErrorAction SilentlyContinue

                        # Check for explicit success marker FIRST
                        # BuildFFUVM.ps1 outputs a PSCustomObject with FFUBuildSuccess=$true on successful completion
                        # This takes priority over non-terminating errors in the error stream
                        $successMarker = $null
                        if ($jobOutput) {
                            $successMarker = $jobOutput | Where-Object {
                                $_ -is [PSCustomObject] -and $_.PSObject.Properties['FFUBuildSuccess'] -and $_.FFUBuildSuccess -eq $true
                            } | Select-Object -Last 1
                        }

                        if ($successMarker) {
                            # Explicit success marker found - build completed successfully
                            # Ignore any non-terminating errors that may have been captured
                            $hasErrors = $false
                            WriteLog "Success marker detected: $($successMarker.Message)"
                        }
                        else {
                            # No success marker - fall back to error stream check
                            $hasErrors = ($jobErrors.Count -gt 0) -or ($currentJob.State -eq 'Failed') -or ($currentJob.State -eq 'Stopped')
                        }

                        # Additional check: if log file was never created, the job likely failed early
                        # NOTE: Use script-scoped uiState.FFUDevelopmentPath (not $config which is out of scope in this timer handler)
                        $mainLogPath = Join-Path $script:uiState.FFUDevelopmentPath "FFUDevelopment.log"
                        if (-not (Test-Path -LiteralPath $mainLogPath)) {
                            $hasErrors = $true
                        }

                        if ($hasErrors) {
                            $reason = $null

                            # Try to get error message from various sources
                            if ($null -ne $jobErrors -and $jobErrors.Count -gt 0) {
                                $reason = ($jobErrors | Select-Object -Last 1).ToString()
                            }

                            if ([string]::IsNullOrWhiteSpace($reason) -and $currentJob.JobStateInfo.Reason) {
                                $reason = $currentJob.JobStateInfo.Reason.Message
                            }

                            if ([string]::IsNullOrWhiteSpace($reason) -and $jobOutput) {
                                # Check job output for error messages
                                $errorLines = $jobOutput | Where-Object { $_ -match '(error|exception|failed|fatal)' } | Select-Object -Last 5
                                if ($errorLines) {
                                    $reason = ($errorLines -join "`n")
                                }
                            }

                            if ([string]::IsNullOrWhiteSpace($reason)) {
                                if (-not (Test-Path -LiteralPath $mainLogPath)) {
                                    $reason = "Build failed before creating log file. This usually indicates a parameter validation error or missing directory. Check that FFUDevelopmentPath exists and all parameters are valid."
                                }
                                else {
                                    $reason = "An unknown error occurred. The job failed without a specific reason."
                                }
                            }

                            $finalStatusText = "FFU build failed. Check FFUDevelopment.log for details."
                            WriteLog "BuildFFUVM.ps1 job failed. State: $($currentJob.State). Reason: $reason"

                            # Show error details to user
                            $errorMsg = "The build process failed.`n`n"
                            if (Test-Path -LiteralPath $mainLogPath) {
                                $errorMsg += "Please check the log file for details:`n$mainLogPath`n`n"
                            }
                            else {
                                $errorMsg += "No log file was created (expected at $mainLogPath).`nThis usually indicates an early failure before logging started.`n`n"
                            }
                            $errorMsg += "Error: $reason"

                            [System.Windows.MessageBox]::Show($errorMsg, "Build Error", "OK", "Error") | Out-Null
                            $script:uiState.Controls.pbOverallProgress.Visibility = 'Collapsed'
                        }
                        else {
                            # Job completed successfully with no errors
                            WriteLog "BuildFFUVM.ps1 job completed successfully."
                            $finalStatusText = "FFU build completed successfully."
                            $script:uiState.Controls.pbOverallProgress.Value = 100
                        }

                        # Update UI elements
                        $script:uiState.Controls.txtStatus.Text = $finalStatusText

                        # Receive & remove job and clear state
                        $currentJob | Receive-Job -ErrorAction SilentlyContinue | Out-Null
                        Remove-Job -Job $currentJob -Force
                        $script:uiState.Data.currentBuildJob = $null

                        # Reset button and flags for next run
                        $script:uiState.Flags.isBuilding = $false
                        $script:uiState.Flags.isCleanupRunning = $false
                        $script:uiState.Controls.btnRun.Content = "Build FFU"
                        $script:uiState.Controls.btnRun.IsEnabled = $true
                    }
                })
            
            # Start the timer
            $script:uiState.Data.pollTimer.Start()

            # Mark building and toggle button to Cancel
            $script:uiState.Flags.isBuilding = $true
            $btnRun.Content = "Cancel"
            $btnRun.IsEnabled = $true
        }
        catch {
            # This catch block handles errors during the setup of the job (e.g., Get-UIConfig fails)
            $errorMessage = "An error occurred before starting the build job: $_"
            WriteLog $errorMessage
            [System.Windows.MessageBox]::Show($errorMessage, "Error", "OK", "Error")
            
            # Clean up stream reader if it was opened
            if ($null -ne $script:uiState.Data.logStreamReader) {
                $script:uiState.Data.logStreamReader.Close()
                $script:uiState.Data.logStreamReader.Dispose()
                $script:uiState.Data.logStreamReader = $null
            }

            # Re-enable UI elements
            $script:uiState.Controls.txtStatus.Text = "FFU build failed to start."
            $script:uiState.Controls.pbOverallProgress.Visibility = 'Collapsed'
            if ($null -ne $script:uiState.Controls.btnRun) {
                $script:uiState.Controls.btnRun.IsEnabled = $true
                $script:uiState.Controls.btnRun.Content = "Build FFU"
                $script:uiState.Flags.isBuilding = $false
                $script:uiState.Flags.isCleanupRunning = $false
            }
        }
    })

# Add handler for Remove button clicks
$window.Add_SourceInitialized({
        $listView = $window.FindName('lstApplications')
        $listView.AddHandler(
            [System.Windows.Controls.Button]::ClickEvent,
            [System.Windows.RoutedEventHandler] {
                param($buttonSender, $clickEventArgs)
                if ($clickEventArgs.OriginalSource -is [System.Windows.Controls.Button] -and $clickEventArgs.OriginalSource.Content -eq "Remove") {
                    Remove-Application -priority $clickEventArgs.OriginalSource.Tag -State $script:uiState
                }
            }
        )
    })

# Register cleanup to reclaim memory and revert LongPathsEnabled setting when the UI window closes
$window.Add_Closed({
        # Stop any running build job if the window is closed
        if ($null -ne $script:uiState.Data.currentBuildJob) {
            WriteLog "UI closing, stopping background build job."
            
            # Stop the timer
            if ($null -ne $script:uiState.Data.pollTimer) {
                $script:uiState.Data.pollTimer.Stop()
                $script:uiState.Data.pollTimer = $null
            }

            # Close the log stream
            if ($null -ne $script:uiState.Data.logStreamReader) {
                $script:uiState.Data.logStreamReader.Close()
                $script:uiState.Data.logStreamReader.Dispose()
                $script:uiState.Data.logStreamReader = $null
            }

            # Stop and remove the job
            $jobToStop = $script:uiState.Data.currentBuildJob
            $script:uiState.Data.currentBuildJob = $null # Clear it from state first
            
            try {
                Stop-Job -Job $jobToStop
                Remove-Job -Job $jobToStop
                WriteLog "Background job stopped and removed."
            }
            catch {
                WriteLog "Error stopping or removing background job: $($_.Exception.Message)"
            }
        }

        # Revert LongPathsEnabled registry setting if it was changed by this script
        if ($script:uiState.Flags.originalLongPathsValue -ne 1) {
            # Only revert if we changed it from something other than 1
            try {
                $currentValue = Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -ErrorAction SilentlyContinue
                if ($currentValue -eq 1) {
                    # Double-check it's still 1 before reverting
                    $revertValue = if ($null -eq $script:uiState.Flags.originalLongPathsValue) { 0 } else { $script:uiState.Flags.originalLongPathsValue } # Revert to original or 0 if it didn't exist
                    WriteLog "Reverting LongPathsEnabled registry key back to original value ($revertValue)."
                    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Value $revertValue -Force
                    WriteLog "LongPathsEnabled reverted."
                }
            }
            catch {
                WriteLog "Error reverting LongPathsEnabled registry key: $($_.Exception.Message)."
            }
        }

        # # Garbage collection
        # [System.GC]::Collect()
        # [System.GC]::WaitForPendingFinalizers()
    })

[void]$window.ShowDialog()
