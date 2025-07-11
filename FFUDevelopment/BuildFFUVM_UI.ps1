[CmdletBinding()]
[System.STAThread()]
param()

# Check PowerShell Version
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Error "PowerShell 7 or later is required to run this script."
    exit 1
}

# Creating custom state object to hold UI state and data
$FFUDevelopmentPath = 'C:\FFUDevelopment' # hard coded for testing

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
        pollTimer                   = $null
    };
    Flags              = @{
        installAppsForcedByUpdates        = $false;
        prevInstallAppsStateBeforeUpdates = $null;
        installAppsCheckedByOffice        = $false;
        lastSortProperty                  = $null;
        lastSortAscending                 = $true
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
    })


# Button: Build FFU
$script:uiState.Controls.btnRun = $window.FindName('btnRun')
$script:uiState.Controls.btnRun.Add_Click({
        # Get a local reference to the button for convenience in this handler
        $btnRun = $script:uiState.Controls.btnRun
        try {
            # Disable button to prevent multiple clicks
            $btnRun.IsEnabled = $false

            # Switch to Monitor Tab
            $script:uiState.Controls.MainTabControl.SelectedItem = $script:uiState.Controls.MonitorTab
            
            # Clear previous log data
            if ($null -ne $script:uiState.Data.logData) {
                $script:uiState.Data.logData.Clear()
            }

            $progressBar = $script:uiState.Controls.pbOverallProgress
            $txtStatus = $script:uiState.Controls.txtStatus
            $progressBar.Visibility = 'Visible'
            $txtStatus.Text = "Starting FFU build..."
            
            # Gather config on the UI thread before starting the job
            $config = Get-UIConfig -State $script:uiState
            $configFilePath = Join-Path $config.FFUDevelopmentPath "\config\FFUConfig.json"
            $config | ConvertTo-Json -Depth 10 | Set-Content -Path $configFilePath -Encoding UTF8
            
            if ($config.InstallOffice -and $config.OfficeConfigXMLFile) {
                Copy-Item -Path $config.OfficeConfigXMLFile -Destination $config.OfficePath -Force
                WriteLog "Office Configuration XML file copied successfully."
            }
            
            $txtStatus.Text = "Executing BuildFFUVM.ps1 in the background..."
            WriteLog "Executing BuildFFUVM.ps1 in the background..."

            # Prepare parameters for splatting
            $buildParams = @{
                ConfigFile = $configFilePath
            }
            if ($config.Verbose) {
                $buildParams['Verbose'] = $true
            }

            # Define the script block to run in the background job
            $scriptBlock = {
                param($buildParams, $PSScriptRoot)
                
                # This script runs in a new process. BuildFFUVM.ps1 is expected to handle its own module imports.
                & "$PSScriptRoot\BuildFFUVM.ps1" @buildParams
            }

            # Start the job and store it in the shared state object
            $script:uiState.Data.currentBuildJob = Start-Job -ScriptBlock $scriptBlock -ArgumentList @($buildParams, $PSScriptRoot)

            # Open a stream reader to the main log file
            $mainLogPath = "$($config.FFUDevelopmentPath)\FFUDevelopment.log"
            # Wait a moment for the file to be created by the new process
            Start-Sleep -Seconds 1
            if (Test-Path $mainLogPath) {
                $fileStream = [System.IO.File]::Open($mainLogPath, 'Open', 'Read', 'ReadWrite')
                $script:uiState.Data.logStreamReader = [System.IO.StreamReader]::new($fileStream)
            }
            else {
                WriteLog "Warning: Main log file not found at $mainLogPath. Monitor tab will not update."
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
                            $script:uiState.Data.logData.Add($line)
                            # Auto-scroll to the new item
                            $script:uiState.Controls.lstLogOutput.ScrollIntoView($line)
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
                            while ($null -ne ($line = $script:uiState.Data.logStreamReader.ReadLine())) {
                                $script:uiState.Data.logData.Add($line)
                            }
                            $script:uiState.Data.logStreamReader.Close()
                            $script:uiState.Data.logStreamReader.Dispose()
                            $script:uiState.Data.logStreamReader = $null
                        }

                        $finalStatusText = "FFU build completed successfully."
                        if ($currentJob.State -eq 'Failed') {
                            $reason = $currentJob.JobStateInfo.Reason.Message
                            $finalStatusText = "FFU build failed. Check FFUDevelopment.log for details."
                            WriteLog "BuildFFUVM.ps1 job failed. Reason: $reason"
                            [System.Windows.MessageBox]::Show("The build process failed. Please check the log file for details.`n`nError: $reason", "Build Error", "OK", "Error") | Out-Null
                        }
                        else {
                            WriteLog "BuildFFUVM.ps1 job completed successfully."
                        }

                        # Update UI elements
                        $script:uiState.Controls.txtStatus.Text = $finalStatusText
                        $script:uiState.Controls.pbOverallProgress.Visibility = 'Collapsed'
                        $script:uiState.Controls.btnRun.IsEnabled = $true

                        # Clean up the job object
                        $currentJob | Receive-Job -ErrorAction SilentlyContinue | Out-Null
                        Remove-Job -Job $currentJob -Force
                        
                        # Clear the job from the state
                        $script:uiState.Data.currentBuildJob = $null
                    }
                })
            
            # Start the timer
            $script:uiState.Data.pollTimer.Start()
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
