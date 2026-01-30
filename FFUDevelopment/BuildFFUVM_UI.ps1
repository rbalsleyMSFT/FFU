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
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Error "PowerShell 7 or later is required to run this script."
    exit 1
}

# Creating custom state object to hold UI state and data
$FFUDevelopmentPath = $PSScriptRoot

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
        currentBuildProcess         = $null;
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
    LogFilePath        = "$FFUDevelopmentPath\FFUDevelopment_UI.log"
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
        Initialize-UIControls -State $script:uiState
        Initialize-UIDefaults -State $script:uiState
        Initialize-DynamicUIElements -State $script:uiState
        Register-EventHandlers -State $script:uiState

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
                WriteLog "Cancel requested by user. Stopping background build process."

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

                # Stop the running build process
                $processToStop = $script:uiState.Data.currentBuildProcess
                $script:uiState.Data.currentBuildProcess = $null

                if ($null -ne $processToStop) {
                    # Recursively terminate the build process and any children (DISM, setup tools, etc.)
                    function Stop-ProcessTree {
                        param([int]$parentPid)
                        $children = Get-CimInstance Win32_Process -Filter "ParentProcessId=$parentPid" -ErrorAction SilentlyContinue
                        foreach ($child in $children) {
                            Stop-ProcessTree -parentPid $child.ProcessId
                        }
                        try { Stop-Process -Id $parentPid -Force -ErrorAction SilentlyContinue } catch {}
                    }

                    try {
                        Stop-ProcessTree -parentPid $processToStop.Id
                        WriteLog "Background build process stopped (PID: $($processToStop.Id))."
                    }
                    catch {
                        WriteLog "Error terminating build process tree: $($_.Exception.Message)"
                    }
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

                # Start cleanup in a separate pwsh process so the UI stays responsive
                $pwshPath = Join-Path -Path $PSHOME -ChildPath 'pwsh.exe'
                if (-not (Test-Path -Path $pwshPath)) {
                    $pwshPath = 'pwsh'
                }

                $cleanupScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'BuildFFUVM.ps1'

                # Build argument list for cleanup.
                # -Cleanup is a [switch] in BuildFFUVM.ps1, so do not pass a value after it.
                # Use -Param:$true/$false syntax for boolean parameters to avoid argument transformation errors.
                $cleanupArgs = @(
                    '-NoProfile',
                    '-ExecutionPolicy', 'Bypass',
                    '-File', $cleanupScriptPath,
                    '-ConfigFile', $cleanupParams.ConfigFile,
                    '-Cleanup',
                    "-RemoveApps:$($cleanupParams.RemoveApps)",
                    "-RemoveUpdates:$($cleanupParams.RemoveUpdates)",
                    "-CleanupDrivers:$($cleanupParams.CleanupDrivers)",
                    "-CleanupCurrentRunDownloads:$($cleanupParams.CleanupCurrentRunDownloads)"
                )

                $startCleanupParams = @{
                    FilePath     = $pwshPath
                    ArgumentList = $cleanupArgs
                    PassThru     = $true
                }
                if ($Host.Name -eq 'ConsoleHost') {
                    $startCleanupParams['NoNewWindow'] = $true
                }

                $script:uiState.Data.currentBuildProcess = Start-Process @startCleanupParams

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

                # Create a timer to poll the cleanup process
                $script:uiState.Data.pollTimer = New-Object System.Windows.Threading.DispatcherTimer
                $script:uiState.Data.pollTimer.Interval = [TimeSpan]::FromSeconds(1)
                $script:uiState.Flags.isCleanupRunning = $true

                $script:uiState.Data.pollTimer.Add_Tick({
                        param($sender, $e)
                        $currentProcess = $script:uiState.Data.currentBuildProcess

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

                        if ($null -eq $currentProcess -or $null -eq $script:uiState.Data.pollTimer) {
                            if ($null -ne $sender) { $sender.Stop() }
                            $script:uiState.Data.pollTimer = $null
                            return
                        }

                        if ($currentProcess.HasExited) {
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

                            # Clear cleanup process state
                            $script:uiState.Data.currentBuildProcess = $null

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

            $configFilePath = Join-Path $config.FFUDevelopmentPath "\config\FFUConfig.json"
            # Sort top-level keys alphabetically for consistent output
            $sortedConfig = [ordered]@{}
            foreach ($k in ($config.Keys | Sort-Object)) { $sortedConfig[$k] = $config[$k] }
            $sortedConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $configFilePath -Encoding UTF8
            $script:uiState.Data.lastConfigFilePath = $configFilePath
            
            if ($config.InstallOffice -and $config.OfficeConfigXMLFile) {
                Copy-Item -Path $config.OfficeConfigXMLFile -Destination $config.OfficePath -Force
                WriteLog "Office Configuration XML file copied successfully."
            }
            
            $txtStatus.Text = "Executing BuildFFUVM.ps1 in the background..."
            WriteLog "Executing BuildFFUVM.ps1 in the background..."

            # Start BuildFFUVM.ps1 in a separate pwsh process.
            # This keeps the UI responsive and restores console interaction (Write-Host / Read-Host) when available.
            $pwshPath = Join-Path -Path $PSHOME -ChildPath 'pwsh.exe'
            if (-not (Test-Path -Path $pwshPath)) {
                $pwshPath = 'pwsh'
            }

            $buildScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'BuildFFUVM.ps1'
            $pwshArgs = @(
                '-NoProfile',
                '-ExecutionPolicy', 'Bypass',
                '-File', $buildScriptPath,
                '-ConfigFile', $configFilePath
            )
            if ($config.Verbose) {
                $pwshArgs += '-Verbose'
            }

            # Delete the old log file before starting the build process to ensure we don't read stale content.
            $mainLogPath = Join-Path $config.FFUDevelopmentPath "FFUDevelopment.log"
            if (Test-Path $mainLogPath) {
                WriteLog "Removing old FFUDevelopment.log file."
                Remove-Item -Path $mainLogPath -Force
            }

            $startBuildParams = @{
                FilePath     = $pwshPath
                ArgumentList = $pwshArgs
                PassThru     = $true
            }
            if ($Host.Name -eq 'ConsoleHost') {
                $startBuildParams['NoNewWindow'] = $true
            }

            # Start the build process and store it in the shared state object
            $script:uiState.Data.currentBuildProcess = Start-Process @startBuildParams

            # Wait for the new log file to be created by the background process.
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
                    $currentProcess = $script:uiState.Data.currentBuildProcess
                    
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

                    # If process is somehow null or the timer has been nulled out, stop the timer
                    if ($null -eq $currentProcess -or $null -eq $script:uiState.Data.pollTimer) {
                        if ($null -ne $sender) {
                            $sender.Stop()
                        }
                        $script:uiState.Data.pollTimer = $null
                        return
                    }

                    # Check if the build process has exited
                    if ($currentProcess.HasExited) {
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

                        $exitCode = $currentProcess.ExitCode

                        # Determine final status based on process exit code
                        $finalStatusText = "FFU build completed successfully."
                        if ($exitCode -ne 0) {
                            $finalStatusText = "FFU build failed. Check FFUDevelopment.log for details."
                            WriteLog "BuildFFUVM.ps1 process failed with exit code: $exitCode"
                            [System.Windows.MessageBox]::Show("The build process failed. Please check the $FFUDevelopmentPath\FFUDevelopment.log file for details.`n`nExit code: $exitCode", "Build Error", "OK", "Error") | Out-Null
                            $script:uiState.Controls.pbOverallProgress.Visibility = 'Collapsed'
                        }
                        else {
                            WriteLog "BuildFFUVM.ps1 process completed successfully."
                            $script:uiState.Controls.pbOverallProgress.Value = 100
                        }

                        # Update UI elements
                        $script:uiState.Controls.txtStatus.Text = $finalStatusText

                        # Clear process state
                        $script:uiState.Data.currentBuildProcess = $null

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
        # Stop any running build process if the window is closed
        if ($null -ne $script:uiState.Data.currentBuildProcess) {
            WriteLog "UI closing, stopping background build process."
            
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

            $processToStop = $script:uiState.Data.currentBuildProcess
            $script:uiState.Data.currentBuildProcess = $null

            try {
                # Terminate the build process and any children
                function Stop-ProcessTree {
                    param([int]$parentPid)
                    $children = Get-CimInstance Win32_Process -Filter "ParentProcessId=$parentPid" -ErrorAction SilentlyContinue
                    foreach ($child in $children) {
                        Stop-ProcessTree -parentPid $child.ProcessId
                    }
                    try { Stop-Process -Id $parentPid -Force -ErrorAction SilentlyContinue } catch {}
                }

                if ($null -ne $processToStop -and -not $processToStop.HasExited) {
                    Stop-ProcessTree -parentPid $processToStop.Id
                }

                WriteLog "Background process stopped."
            }
            catch {
                WriteLog "Error stopping background build process: $($_.Exception.Message)"
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
