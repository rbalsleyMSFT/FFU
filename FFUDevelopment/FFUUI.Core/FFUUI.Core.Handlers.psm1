<#
.SYNOPSIS
    Contains the function for registering all WPF UI event handlers for the FFU Builder application.
.DESCRIPTION
    This module is dedicated to managing user interactions within the FFU Builder UI. It contains the Register-EventHandlers function, which connects UI controls defined in the XAML to their corresponding actions in the PowerShell backend. This includes handling button clicks, text input validation, checkbox state changes, and list view interactions across all tabs, effectively wiring up the application's front-end to its core logic.
#>

function Update-VMNetworkingControls {
    param([PSCustomObject]$State)

    $isVmNetworkingEnabled = $true -eq $State.Controls.chkEnableVMNetworking.IsChecked
    $State.Controls.spVMNetworkingSettings.IsEnabled = $isVmNetworkingEnabled

    if (-not $isVmNetworkingEnabled) {
        $State.Controls.txtCustomVMSwitchName.Visibility = 'Collapsed'
        return
    }

    if ($State.Controls.cmbVMSwitchName.SelectedItem -eq 'Other') {
        $State.Controls.txtCustomVMSwitchName.Visibility = 'Visible'
        if ([string]::IsNullOrWhiteSpace($State.Controls.txtCustomVMSwitchName.Text) -and $null -ne $State.Data.customVMSwitchName) {
            $State.Controls.txtCustomVMSwitchName.Text = $State.Data.customVMSwitchName
        }
    }
    else {
        $State.Controls.txtCustomVMSwitchName.Visibility = 'Collapsed'
    }
}

function Get-SelectedDeviceNamingMode {
    param([PSCustomObject]$State)

    if ($true -eq $State.Controls.rbDeviceNamingPrompt.IsChecked) {
        return 'Prompt'
    }

    if ($true -eq $State.Controls.rbDeviceNamingTemplate.IsChecked) {
        return 'Template'
    }

    if ($true -eq $State.Controls.rbDeviceNamingPrefixes.IsChecked) {
        return 'Prefixes'
    }

    return 'None'
}

function Set-DeviceNamingMode {
    param(
        [PSCustomObject]$State,
        [ValidateSet('None', 'Prompt', 'Template', 'Prefixes')]
        [string]$Mode
    )

    $State.Controls.rbDeviceNamingNone.IsChecked = $Mode -eq 'None'
    $State.Controls.rbDeviceNamingPrompt.IsChecked = $Mode -eq 'Prompt'
    $State.Controls.rbDeviceNamingTemplate.IsChecked = $Mode -eq 'Template'
    $State.Controls.rbDeviceNamingPrefixes.IsChecked = $Mode -eq 'Prefixes'
}

function Get-DeviceNamePrefixes {
    param([PSCustomObject]$State)

    if ($null -eq $State.Controls.txtDeviceNamePrefixes) {
        return @()
    }

    return @(
        $State.Controls.txtDeviceNamePrefixes.Text -split "\r?\n" |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_.Trim() }
    )
}

function Import-DeviceNamePrefixesFile {
    param(
        [PSCustomObject]$State,
        [string]$FilePath
    )

    if ([string]::IsNullOrWhiteSpace($FilePath) -or -not (Test-Path -Path $FilePath -PathType Leaf)) {
        return $false
    }

    $prefixLines = @(Get-Content -Path $FilePath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
    if ($null -ne $State.Controls.txtDeviceNamePrefixesPath) {
        $State.Controls.txtDeviceNamePrefixesPath.Text = $FilePath
    }
    $State.Controls.txtDeviceNamePrefixes.Text = $prefixLines -join [System.Environment]::NewLine
    WriteLog "Imported device name prefixes from $FilePath"
    return $true
}

function Get-DefaultDeviceNamePrefixesPath {
    param([string]$FFUDevelopmentPath)

    if ([string]::IsNullOrWhiteSpace($FFUDevelopmentPath)) {
        return $null
    }

    return Join-Path (Join-Path $FFUDevelopmentPath 'unattend') 'prefixes.txt'
}

function Get-DefaultUnattendFilePath {
    param(
        [string]$FFUDevelopmentPath,
        [ValidateSet('x64', 'arm64')]
        [string]$WindowsArch
    )

    if ([string]::IsNullOrWhiteSpace($FFUDevelopmentPath)) {
        return $null
    }

    $fileName = if ($WindowsArch -ieq 'arm64') { 'unattend_arm64.xml' } else { 'unattend_x64.xml' }
    return Join-Path (Join-Path $FFUDevelopmentPath 'unattend') $fileName
}

function Import-DeviceNamePrefixesFromConfiguredPath {
    param(
        [PSCustomObject]$State,
        [switch]$SkipIfTextPresent
    )

    if ($SkipIfTextPresent -and -not [string]::IsNullOrWhiteSpace($State.Controls.txtDeviceNamePrefixes.Text)) {
        return
    }

    $prefixFilePath = $State.Controls.txtDeviceNamePrefixesPath.Text
    if ([string]::IsNullOrWhiteSpace($prefixFilePath)) {
        $prefixFilePath = Get-DefaultDeviceNamePrefixesPath -FFUDevelopmentPath $State.Controls.txtFFUDevPath.Text
        if (-not [string]::IsNullOrWhiteSpace($prefixFilePath) -and $null -ne $State.Controls.txtDeviceNamePrefixesPath) {
            $State.Controls.txtDeviceNamePrefixesPath.Text = $prefixFilePath
        }
    }

    if (Test-Path -Path $prefixFilePath -PathType Leaf) {
        Import-DeviceNamePrefixesFile -State $State -FilePath $prefixFilePath | Out-Null
    }
}

function Test-DeviceNameTemplateUsesSerialToken {
    param([PSCustomObject]$State)

    return ((Get-SelectedDeviceNamingMode -State $State) -eq 'Template') -and ($State.Controls.txtDeviceNameTemplate.Text -match '(?i)%serial%')
}

function Update-UnattendSelectionControls {
    param([PSCustomObject]$State)

    $selectedDeviceNamingMode = Get-SelectedDeviceNamingMode -State $State
    $isCopyUnattendSelected = $true -eq $State.Controls.chkCopyUnattend.IsChecked
    $isInjectUnattendSelected = $true -eq $State.Controls.chkInjectUnattend.IsChecked
    $deviceNameTemplateUsesSerialToken = Test-DeviceNameTemplateUsesSerialToken -State $State
    $requiresCopiedUnattend = ($selectedDeviceNamingMode -in @('Prompt', 'Prefixes')) -or $deviceNameTemplateUsesSerialToken

    if ($isCopyUnattendSelected -and $isInjectUnattendSelected) {
        if ($requiresCopiedUnattend) {
            $State.Controls.chkInjectUnattend.IsChecked = $false
            $isInjectUnattendSelected = $false
        }
        else {
            $State.Controls.chkCopyUnattend.IsChecked = $false
            $isCopyUnattendSelected = $false
        }
    }

    if ($requiresCopiedUnattend) {
        if (-not $isCopyUnattendSelected) {
            $State.Controls.chkCopyUnattend.IsChecked = $true
            $isCopyUnattendSelected = $true
        }

        if ($isInjectUnattendSelected) {
            $State.Controls.chkInjectUnattend.IsChecked = $false
            $isInjectUnattendSelected = $false
        }

        $State.Controls.chkCopyUnattend.IsEnabled = $false
        $State.Controls.chkInjectUnattend.IsEnabled = $false
        return
    }

    if ($isCopyUnattendSelected) {
        $State.Controls.chkCopyUnattend.IsEnabled = $true
        $State.Controls.chkInjectUnattend.IsEnabled = $false
    }
    elseif ($isInjectUnattendSelected) {
        $State.Controls.chkCopyUnattend.IsEnabled = $false
        $State.Controls.chkInjectUnattend.IsEnabled = $true
    }
    else {
        $State.Controls.chkCopyUnattend.IsEnabled = $true
        $State.Controls.chkInjectUnattend.IsEnabled = $true
    }
}

function Update-DeviceNamingControls {
    param([PSCustomObject]$State)

    if (($true -eq $State.Controls.chkInjectUnattend.IsChecked) -and (($true -eq $State.Controls.rbDeviceNamingPrompt.IsChecked) -or ($true -eq $State.Controls.rbDeviceNamingPrefixes.IsChecked))) {
        $State.Controls.rbDeviceNamingNone.IsChecked = $true
    }

    $selectedDeviceNamingMode = Get-SelectedDeviceNamingMode -State $State
    $State.Controls.deviceNameTemplatePanel.Visibility = if ($selectedDeviceNamingMode -eq 'Template') { 'Visible' } else { 'Collapsed' }
    $State.Controls.deviceNamePrefixesPanel.Visibility = if ($selectedDeviceNamingMode -eq 'Prefixes') { 'Visible' } else { 'Collapsed' }
    $State.Controls.rbDeviceNamingPrompt.IsEnabled = -not ($true -eq $State.Controls.chkInjectUnattend.IsChecked)
    $State.Controls.rbDeviceNamingPrefixes.IsEnabled = -not ($true -eq $State.Controls.chkInjectUnattend.IsChecked)

    if ($selectedDeviceNamingMode -eq 'Prefixes') {
        Import-DeviceNamePrefixesFromConfiguredPath -State $State -SkipIfTextPresent
    }

    Update-UnattendSelectionControls -State $State
}

function Register-EventHandlers {
    param([PSCustomObject]$State)
    WriteLog "Registering UI event handlers..."

    # --------------------------------------------------------------------------
    # SECTION: Shared Input Validation Handlers
    # --------------------------------------------------------------------------
    # Define a shared event handler for TextBoxes that should only accept integer input
    $integerPreviewTextInputHandler = {
        param($eventSource, $textCompositionEventArgs)
        # Use a regex to check if the input text is NOT a digit. \D matches any non-digit character.
        if ($textCompositionEventArgs.Text -match '\D') {
            # If the input is not a digit, mark the event as handled to prevent the character from being entered.
            $textCompositionEventArgs.Handled = $true
        }
    }

    # Define a handler to validate pasted text, ensuring it's only integers
    $integerPastingHandler = {
        param($eventSource, $pastingEventArgs)
        if ($pastingEventArgs.DataObject.GetDataPresent([string])) {
            $pastedText = $pastingEventArgs.DataObject.GetData([string])
            # Check if the pasted text consists ONLY of one or more digits.
            if ($pastedText -notmatch '^\d+$') {
                # If not, cancel the paste operation.
                $pastingEventArgs.CancelCommand()
            }
        }
        else {
            # If the pasted data is not in a string format, cancel it.
            $pastingEventArgs.CancelCommand()
        }
    }

    # List of TextBox controls that require integer-only input
    $integerOnlyTextBoxes = @(
        $State.Controls.txtDiskSize,
        $State.Controls.txtMemory,
        $State.Controls.txtProcessors,
        $State.Controls.txtThreads,
        $State.Controls.txtMaxUSBDrives
    )

    # Attach the handlers to each relevant textbox
    foreach ($textBox in $integerOnlyTextBoxes) {
        if ($null -ne $textBox) {
            $textBox.Add_PreviewTextInput($integerPreviewTextInputHandler)
            [System.Windows.DataObject]::AddPastingHandler($textBox, $integerPastingHandler)
        }
    }

    # Add specific validation for the Threads textbox to ensure it's not empty and is at least 1
    if ($null -ne $State.Controls.txtThreads) {
        $State.Controls.txtThreads.Add_LostFocus({
                param($eventSource, $routedEventArgs)
                $textBox = $eventSource
                $currentValue = 0
                # Try to parse the current text as an integer
                $isValidInteger = [int]::TryParse($textBox.Text, [ref]$currentValue)

                # If the text is not a valid integer OR the value is less than 1, reset it to the default value '1'
                if (-not $isValidInteger -or $currentValue -lt 1) {
                    $textBox.Text = '1'
                    WriteLog "Threads value was invalid or less than 1. Reset to 1."
                }
            })
    }

    # Add specific validation for the Max USB Drives textbox to ensure it's an integer >=0 (allow 0 meaning all)
    if ($null -ne $State.Controls.txtMaxUSBDrives) {
        $State.Controls.txtMaxUSBDrives.Add_LostFocus({
                param($eventSource, $routedEventArgs)
                $textBox = $eventSource
                $currentValue = 0
                $isValidInteger = [int]::TryParse($textBox.Text, [ref]$currentValue)
                if (-not $isValidInteger -or $currentValue -lt 0) {
                    $textBox.Text = '0'
                    WriteLog "Max USB Drives value was invalid or less than 0. Reset to 0 (process all)."
                }
            })
    }

    # Navigation Sidebar Event Handlers
    # Main navigation list - switches content pages based on selected nav item
    if ($null -ne $State.Controls.lstNavigation) {
        $State.Controls.lstNavigation.Add_SelectionChanged({
                param($eventSource, $selectionChangedEventArgs)
                $window = [System.Windows.Window]::GetWindow($eventSource)
                if ($null -eq $window -or $null -eq $window.Tag) {
                    return
                }
                $localState = $window.Tag
                $selectedIndex = $eventSource.SelectedIndex
                if ($selectedIndex -lt 0) { return }

                # Clear Settings selection when main nav is used
                if ($null -ne $localState.Controls.lstNavSettings) {
                    $localState.Controls.lstNavSettings.SelectedIndex = -1
                }

                # Hide all content pages
                foreach ($page in $localState.Controls.navigationPages) {
                    if ($null -ne $page) { $page.Visibility = 'Collapsed' }
                }
                if ($null -ne $localState.Controls.pageSettings) {
                    $localState.Controls.pageSettings.Visibility = 'Collapsed'
                }

                # Show the selected page
                if ($selectedIndex -lt $localState.Controls.navigationPages.Count) {
                    $localState.Controls.navigationPages[$selectedIndex].Visibility = 'Visible'
                }
            
                # Update the shared page title to match the selected navigation item
                if ($null -ne $localState.Controls.txtPageTitle) {
                    $selectedNavigationItem = $eventSource.SelectedItem
                    if ($null -ne $selectedNavigationItem -and -not [string]::IsNullOrWhiteSpace([string]$selectedNavigationItem.Tag)) {
                        $localState.Controls.txtPageTitle.Text = [string]$selectedNavigationItem.Tag
                    }
                }
            })
    }

    # Settings navigation item
    if ($null -ne $State.Controls.lstNavSettings) {
        $State.Controls.lstNavSettings.Add_SelectionChanged({
                param($eventSource, $selectionChangedEventArgs)
                $window = [System.Windows.Window]::GetWindow($eventSource)
                if ($null -eq $window -or $null -eq $window.Tag) {
                    return
                }
                $localState = $window.Tag
                if ($eventSource.SelectedIndex -lt 0) { return }

                # Clear main navigation selection
                if ($null -ne $localState.Controls.lstNavigation) {
                    $localState.Controls.lstNavigation.SelectedIndex = -1
                }

                # Hide all content pages
                foreach ($page in $localState.Controls.navigationPages) {
                    if ($null -ne $page) { $page.Visibility = 'Collapsed' }
                }

                # Show Settings page
                if ($null -ne $localState.Controls.pageSettings) {
                    $localState.Controls.pageSettings.Visibility = 'Visible'
                }
            
                # Update the shared page title to match the selected navigation item
                if ($null -ne $localState.Controls.txtPageTitle) {
                    $selectedNavigationItem = $eventSource.SelectedItem
                    if ($null -ne $selectedNavigationItem -and -not [string]::IsNullOrWhiteSpace([string]$selectedNavigationItem.Tag)) {
                        $localState.Controls.txtPageTitle.Text = [string]$selectedNavigationItem.Tag
                    }
                    else {
                        $localState.Controls.txtPageTitle.Text = 'Settings'
                    }
                }
            })
    }

    # Hyperlink navigation handlers for Home page links
    $hyperlinkNames = @(
        'linkQuickStart',
        'linkDocs',
        'linkGitHub',
        'linkReleases',
        'linkChangelog',
        'linkVideo1',
        'linkDiscussion1',
        'linkDiscussion2',
        'linkDiscussion3',
        'linkDiscussion4',
        'linkDiscussion5',
        'linkDiscussions'
    )
    foreach ($linkName in $hyperlinkNames) {
        $link = $State.Window.FindName($linkName)
        if ($null -ne $link) {
            $link.Add_RequestNavigate({
                    param($eventSource, $requestNavigateEventArgs)
                    Start-Process $requestNavigateEventArgs.Uri.AbsoluteUri
                    $requestNavigateEventArgs.Handled = $true
                })
        }
    }

    # Settings Page Event Handlers
    # Theme mode selector - switches between Light, Dark, and System Fluent themes
    if ($null -ne $State.Controls.cmbThemeMode) {
        $State.Controls.cmbThemeMode.Add_SelectionChanged({
                param($eventSource, $selectionChangedEventArgs)
                $window = [System.Windows.Window]::GetWindow($eventSource)
                if ($null -eq $window -or $null -eq $window.Tag) {
                    return
                }
                $localState = $window.Tag
                if (-not $localState.Flags.isFluentSupported) {
                    return
                }
                $selectedTheme = $eventSource.SelectedItem
                if (-not [string]::IsNullOrWhiteSpace($selectedTheme)) {
                    Initialize-FluentTheme -Window $window -ThemeMode $selectedTheme -State $localState
                }
            })
    }

    # Build Tab Event Handlers
    $State.Controls.btnBrowseFFUDevPath.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $selectedPath = Invoke-BrowseAction -Type 'Folder' -Title "Select FFU Development Path"
            if ($selectedPath) {
                $currentPrefixesPath = $localState.Controls.txtDeviceNamePrefixesPath.Text
                $currentUnattendX64FilePath = $localState.Controls.txtUnattendX64FilePath.Text
                $currentUnattendArm64FilePath = $localState.Controls.txtUnattendArm64FilePath.Text
                $previousDefaultPrefixesPath = Get-DefaultDeviceNamePrefixesPath -FFUDevelopmentPath $localState.Controls.txtFFUDevPath.Text
                $previousDefaultUnattendX64FilePath = Get-DefaultUnattendFilePath -FFUDevelopmentPath $localState.Controls.txtFFUDevPath.Text -WindowsArch 'x64'
                $previousDefaultUnattendArm64FilePath = Get-DefaultUnattendFilePath -FFUDevelopmentPath $localState.Controls.txtFFUDevPath.Text -WindowsArch 'arm64'
                $localState.Controls.txtFFUDevPath.Text = $selectedPath
                $newDefaultPrefixesPath = Get-DefaultDeviceNamePrefixesPath -FFUDevelopmentPath $selectedPath
                $newDefaultUnattendX64FilePath = Get-DefaultUnattendFilePath -FFUDevelopmentPath $selectedPath -WindowsArch 'x64'
                $newDefaultUnattendArm64FilePath = Get-DefaultUnattendFilePath -FFUDevelopmentPath $selectedPath -WindowsArch 'arm64'
                if ([string]::IsNullOrWhiteSpace($currentPrefixesPath) -or $currentPrefixesPath -ieq $previousDefaultPrefixesPath) {
                    $localState.Controls.txtDeviceNamePrefixesPath.Text = $newDefaultPrefixesPath
                }
                if ([string]::IsNullOrWhiteSpace($currentUnattendX64FilePath) -or $currentUnattendX64FilePath -ieq $previousDefaultUnattendX64FilePath) {
                    $localState.Controls.txtUnattendX64FilePath.Text = $newDefaultUnattendX64FilePath
                }
                if ([string]::IsNullOrWhiteSpace($currentUnattendArm64FilePath) -or $currentUnattendArm64FilePath -ieq $previousDefaultUnattendArm64FilePath) {
                    $localState.Controls.txtUnattendArm64FilePath.Text = $newDefaultUnattendArm64FilePath
                }
                Import-DeviceNamePrefixesFromConfiguredPath -State $localState
                Update-DeviceNamingControls -State $localState
            }
        })

    $State.Controls.btnBrowseFFUCaptureLocation.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $selectedPath = Invoke-BrowseAction -Type 'Folder' -Title "Select FFU Capture Location"
            if ($selectedPath) {
                $localState.Controls.txtFFUCaptureLocation.Text = $selectedPath
            }
        })

    $State.Controls.rbDeviceNamingNone.Add_Checked({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            Update-DeviceNamingControls -State $window.Tag
        })
    $State.Controls.rbDeviceNamingPrompt.Add_Checked({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            Update-DeviceNamingControls -State $window.Tag
        })
    $State.Controls.rbDeviceNamingTemplate.Add_Checked({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            Update-DeviceNamingControls -State $window.Tag
        })
    $State.Controls.txtDeviceNameTemplate.Add_TextChanged({
            param($eventSource, $textChangedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            if ($null -ne $window -and $null -ne $window.Tag) {
                Update-DeviceNamingControls -State $window.Tag
            }
        })
    $State.Controls.rbDeviceNamingPrefixes.Add_Checked({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            Update-DeviceNamingControls -State $window.Tag
        })
    $State.Controls.btnBrowseDeviceNamePrefixesPath.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $currentPrefixesPath = $localState.Controls.txtDeviceNamePrefixesPath.Text
            if ([string]::IsNullOrWhiteSpace($currentPrefixesPath)) {
                $currentPrefixesPath = Get-DefaultDeviceNamePrefixesPath -FFUDevelopmentPath $localState.Controls.txtFFUDevPath.Text
            }
            $initialDirectory = if ([string]::IsNullOrWhiteSpace($currentPrefixesPath)) {
                $null
            }
            else {
                Split-Path $currentPrefixesPath -Parent
            }
            $fileName = if ([string]::IsNullOrWhiteSpace($currentPrefixesPath)) { 'prefixes.txt' } else { Split-Path $currentPrefixesPath -Leaf }
            $selectedPath = Invoke-BrowseAction -Type 'OpenFile' -Title 'Select prefixes file path' -Filter 'Text files (*.txt)|*.txt|All files (*.*)|*.*' -InitialDirectory $initialDirectory -FileName $fileName
            if (Import-DeviceNamePrefixesFile -State $localState -FilePath $selectedPath) {
                Update-DeviceNamingControls -State $localState
            }
        })
    $State.Controls.btnBrowseUnattendX64FilePath.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $currentUnattendX64FilePath = $localState.Controls.txtUnattendX64FilePath.Text
            if ([string]::IsNullOrWhiteSpace($currentUnattendX64FilePath)) {
                $currentUnattendX64FilePath = Get-DefaultUnattendFilePath -FFUDevelopmentPath $localState.Controls.txtFFUDevPath.Text -WindowsArch 'x64'
            }
            $initialDirectory = if ([string]::IsNullOrWhiteSpace($currentUnattendX64FilePath)) {
                $null
            }
            else {
                Split-Path $currentUnattendX64FilePath -Parent
            }
            $fileName = if ([string]::IsNullOrWhiteSpace($currentUnattendX64FilePath)) { 'unattend_x64.xml' } else { Split-Path $currentUnattendX64FilePath -Leaf }
            $selectedPath = Invoke-BrowseAction -Type 'OpenFile' -Title 'Select x64 unattend XML file' -Filter 'XML files (*.xml)|*.xml|All files (*.*)|*.*' -InitialDirectory $initialDirectory -FileName $fileName
            if (-not [string]::IsNullOrWhiteSpace($selectedPath)) {
                $localState.Controls.txtUnattendX64FilePath.Text = $selectedPath
            }
        })
    $State.Controls.btnBrowseUnattendArm64FilePath.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $currentUnattendArm64FilePath = $localState.Controls.txtUnattendArm64FilePath.Text
            if ([string]::IsNullOrWhiteSpace($currentUnattendArm64FilePath)) {
                $currentUnattendArm64FilePath = Get-DefaultUnattendFilePath -FFUDevelopmentPath $localState.Controls.txtFFUDevPath.Text -WindowsArch 'arm64'
            }
            $initialDirectory = if ([string]::IsNullOrWhiteSpace($currentUnattendArm64FilePath)) {
                $null
            }
            else {
                Split-Path $currentUnattendArm64FilePath -Parent
            }
            $fileName = if ([string]::IsNullOrWhiteSpace($currentUnattendArm64FilePath)) { 'unattend_arm64.xml' } else { Split-Path $currentUnattendArm64FilePath -Leaf }
            $selectedPath = Invoke-BrowseAction -Type 'OpenFile' -Title 'Select arm64 unattend XML file' -Filter 'XML files (*.xml)|*.xml|All files (*.*)|*.*' -InitialDirectory $initialDirectory -FileName $fileName
            if (-not [string]::IsNullOrWhiteSpace($selectedPath)) {
                $localState.Controls.txtUnattendArm64FilePath.Text = $selectedPath
            }
        })
    $State.Controls.btnSaveDeviceNamePrefixes.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $prefixLines = @(Get-DeviceNamePrefixes -State $localState)

            if ($prefixLines.Count -eq 0) {
                [System.Windows.MessageBox]::Show("Enter at least one prefix before saving the prefixes file.", "Prefixes Required", "OK", "Warning") | Out-Null
                return
            }

            $currentPrefixesPath = $localState.Controls.txtDeviceNamePrefixesPath.Text
            if ([string]::IsNullOrWhiteSpace($currentPrefixesPath)) {
                $currentPrefixesPath = Get-DefaultDeviceNamePrefixesPath -FFUDevelopmentPath $localState.Controls.txtFFUDevPath.Text
                if (-not [string]::IsNullOrWhiteSpace($currentPrefixesPath)) {
                    $localState.Controls.txtDeviceNamePrefixesPath.Text = $currentPrefixesPath
                }
            }

            if ([string]::IsNullOrWhiteSpace($currentPrefixesPath)) {
                [System.Windows.MessageBox]::Show("Select a valid Prefixes File Path before saving prefixes.", "Prefixes File Path Required", "OK", "Warning") | Out-Null
                return
            }

            try {
                $prefixLines | Set-Content -Path $currentPrefixesPath -Encoding UTF8
                $localState.Controls.txtDeviceNamePrefixesPath.Text = $currentPrefixesPath
                WriteLog "Saved device name prefixes to $currentPrefixesPath"
            }
            catch {
                [System.Windows.MessageBox]::Show("Saving prefixes failed for '$currentPrefixesPath'. $($_.Exception.Message)", "Save Prefixes Failed", "OK", "Error") | Out-Null
            }
        })
    $State.Controls.chkCopyUnattend.Add_Checked({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $localState.Controls.chkInjectUnattend.IsChecked = $false
            Update-DeviceNamingControls -State $localState
        })
    $State.Controls.chkCopyUnattend.Add_Unchecked({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            Update-DeviceNamingControls -State $window.Tag
        })
    $State.Controls.chkInjectUnattend.Add_Checked({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $localState.Controls.chkCopyUnattend.IsChecked = $false
            Update-DeviceNamingControls -State $localState
        })
    $State.Controls.chkInjectUnattend.Add_Unchecked({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            Update-DeviceNamingControls -State $window.Tag
        })

    # Build USB Drive Settings Event Handlers
    # The USB Expander is always visible; the checkbox controls child settings only
    $State.Controls.chkBuildUSBDriveEnable.Add_Checked({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $localState.Controls.chkSelectSpecificUSBDrives.IsEnabled = $true
        })
    $State.Controls.chkBuildUSBDriveEnable.Add_Unchecked({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $localState.Controls.chkSelectSpecificUSBDrives.IsEnabled = $false
            $localState.Controls.chkSelectSpecificUSBDrives.IsChecked = $false
            $localState.Controls.lstUSBDrives.Items.Clear()
        })
    $State.Controls.chkSelectSpecificUSBDrives.Add_Checked({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $localState.Controls.usbSelectionPanel.Visibility = 'Visible'
        })
    $State.Controls.chkSelectSpecificUSBDrives.Add_Unchecked({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $localState.Controls.usbSelectionPanel.Visibility = 'Collapsed'
            $localState.Controls.lstUSBDrives.Items.Clear()
        })
    $State.Controls.chkAllowExternalHardDiskMedia.Add_Checked({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $localState.Controls.chkPromptExternalHardDiskMedia.IsEnabled = $true
        })
    $State.Controls.chkAllowExternalHardDiskMedia.Add_Unchecked({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $localState.Controls.chkPromptExternalHardDiskMedia.IsEnabled = $false
            $localState.Controls.chkPromptExternalHardDiskMedia.IsChecked = $false
        })

    if ($null -ne $State.Controls.cmbBitsPriority) {
        $State.Controls.cmbBitsPriority.Add_SelectionChanged({
                param($eventSource, $selectionChangedEventArgs)
                $window = [System.Windows.Window]::GetWindow($eventSource)
                if ($null -eq $window -or $null -eq $window.Tag) {
                    return
                }
                Update-BitsPrioritySetting -State $window.Tag
            })
    }

    # Additional FFU Files events
    $State.Controls.chkCopyAdditionalFFUFiles.Add_Checked({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $localState.Controls.additionalFFUPanel.Visibility = 'Visible'
            Update-AdditionalFFUList -State $localState
        })
    $State.Controls.chkCopyAdditionalFFUFiles.Add_Unchecked({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $localState.Controls.additionalFFUPanel.Visibility = 'Collapsed'
            $localState.Controls.lstAdditionalFFUs.Items.Clear()
            $headerChk = $localState.Controls.chkSelectAllAdditionalFFUs
            if ($null -ne $headerChk) {
                Update-SelectAllHeaderCheckBoxState -ListView $localState.Controls.lstAdditionalFFUs -HeaderCheckBox $headerChk
            }
        })
    $State.Controls.btnRefreshAdditionalFFUs.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            Update-AdditionalFFUList -State $localState
        })
    $State.Controls.lstAdditionalFFUs.Add_PreviewKeyDown({
            param($eventSource, $keyEvent)
            if ($keyEvent.Key -eq 'Space') {
                $window = [System.Windows.Window]::GetWindow($eventSource)
                $localState = $window.Tag
                Invoke-ListViewItemToggle -ListView $eventSource -State $localState -HeaderCheckBoxKeyName 'chkSelectAllAdditionalFFUs'
                $keyEvent.Handled = $true
            }
        })
    $State.Controls.lstAdditionalFFUs.Add_SelectionChanged({
            param($eventSource, $selChangeEvent)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $headerChk = $localState.Controls.chkSelectAllAdditionalFFUs
            if ($null -ne $headerChk) {
                Update-SelectAllHeaderCheckBoxState -ListView $localState.Controls.lstAdditionalFFUs -HeaderCheckBox $headerChk
            }
        })

    $State.Controls.btnCheckUSBDrives.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag

            $localState.Controls.lstUSBDrives.Items.Clear()
            $usbDrives = Get-USBDrives
            foreach ($drive in $usbDrives) {
                $driveObject = [PSCustomObject]$drive
                # Explicitly add and initialize the IsSelected property for each new item.
                $driveObject | Add-Member -MemberType NoteProperty -Name 'IsSelected' -Value $false -Force
                $localState.Controls.lstUSBDrives.Items.Add($driveObject)
            }
            Request-ListViewColumnAutoResize -ListView $localState.Controls.lstUSBDrives
            if ($localState.Controls.lstUSBDrives.Items.Count -gt 0) {
                $localState.Controls.lstUSBDrives.SelectedIndex = 0
            }
            WriteLog "Check USB Drives: Found $($localState.Controls.lstUSBDrives.Items.Count) USB drives."
            # After clearing and repopulating, update the 'Select All' header checkbox state
            $headerChk = $localState.Controls.chkSelectAllUSBDrivesHeader
            if ($null -ne $headerChk) {
                Update-SelectAllHeaderCheckBoxState -ListView $localState.Controls.lstUSBDrives -HeaderCheckBox $headerChk
            }
        })
        

    $State.Controls.lstUSBDrives.Add_PreviewKeyDown({
            param($eventSource, $keyEvent)
            if ($keyEvent.Key -eq 'Space') {
                $window = [System.Windows.Window]::GetWindow($eventSource)
                $localState = $window.Tag
                Invoke-ListViewItemToggle -ListView $eventSource -State $localState -HeaderCheckBoxKeyName 'chkSelectAllUSBDrivesHeader'
                $keyEvent.Handled = $true
            }
        })
    $State.Controls.lstUSBDrives.Add_SelectionChanged({
            param($eventSource, $selChangeEvent)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            # Update the 'Select All' header checkbox state based on current selections
            $headerChk = $localState.Controls.chkSelectAllUSBDrivesHeader
            if ($null -ne $headerChk) {
                Update-SelectAllHeaderCheckBoxState -ListView $localState.Controls.lstUSBDrives -HeaderCheckBox $headerChk
            }
        })

    # Hyper-V tab event handlers
    $State.Controls.chkEnableVMNetworking.Add_Checked({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            Update-VMNetworkingControls -State $localState
        })

    $State.Controls.chkEnableVMNetworking.Add_Unchecked({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            Update-VMNetworkingControls -State $localState
        })

    $State.Controls.cmbVMSwitchName.Add_SelectionChanged({
            param($eventSource, $selectionChangedEventArgs)
            # The state object is available via the parent window's Tag property
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag

            Update-VMNetworkingControls -State $localState
        })

    # Persist custom VM switch name when user edits it while 'Other' is selected
    $State.Controls.txtCustomVMSwitchName.Add_LostFocus({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            if ($localState.Controls.cmbVMSwitchName.SelectedItem -eq 'Other') {
                $localState.Data.customVMSwitchName = $localState.Controls.txtCustomVMSwitchName.Text
            }
        })

    # Windows Settings tab Event Handlers
    # Windows Media Source radio buttons
    if ($null -ne $State.Controls.rbProvideISO) {
        $State.Controls.rbProvideISO.Add_Checked({
                param($eventSource, $routedEventArgs)
                $window = [System.Windows.Window]::GetWindow($eventSource)
                if ($null -eq $window -or $null -eq $window.Tag) { return }
                $localState = $window.Tag
                $localState.Controls.isoPathPanel.Visibility = 'Visible'
                # Use a placeholder .iso path to trigger ISO mode even before a real path is provided
                $isoPath = $localState.Controls.txtISOPath.Text
                if ([string]::IsNullOrWhiteSpace($isoPath)) {
                    $isoPath = 'placeholder.iso'
                }
                Get-WindowsSettingsCombos -isoPath $isoPath -State $localState
            })
        $State.Controls.rbProvideISO.Add_Unchecked({
                param($eventSource, $routedEventArgs)
                $window = [System.Windows.Window]::GetWindow($eventSource)
                if ($null -eq $window -or $null -eq $window.Tag) { return }
                $localState = $window.Tag
                $localState.Controls.isoPathPanel.Visibility = 'Collapsed'
                $localState.Controls.txtISOPath.Text = ''
                Get-WindowsSettingsCombos -isoPath '' -State $localState
            })
    }

    $State.Controls.cmbWindowsRelease.Add_SelectionChanged({
            param($eventSource, $selectionChangedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $selectedReleaseValue = 11 # Default if null
            if ($null -ne $localState.Controls.cmbWindowsRelease.SelectedItem) {
                $selectedReleaseValue = $localState.Controls.cmbWindowsRelease.SelectedItem.Value
            }
            # Determine ISO path based on radio button state
            $isoPath = ''
            if ($null -ne $localState.Controls.rbProvideISO -and $localState.Controls.rbProvideISO.IsChecked) {
                $isoPath = $localState.Controls.txtISOPath.Text
                if ([string]::IsNullOrWhiteSpace($isoPath)) { $isoPath = 'placeholder.iso' }
            }
            Update-WindowsVersionCombo -selectedRelease $selectedReleaseValue -isoPath $isoPath -State $localState
            Update-WindowsSkuCombo -State $localState
            Update-WindowsArchCombo -State $localState

            # Re-evaluate Install Apps dependency when Windows release changes
            Update-InstallAppsState -State $localState
        })

    $State.Controls.cmbWindowsVersion.Add_SelectionChanged({
            param($eventSource, $selectionChangedEventArgs)
            # This event should only fire on user interaction or after Update-WindowsVersionCombo runs.
            # We only need to update the architecture, as SKU is dependent only on Release.
            $window = [System.Windows.Window]::GetWindow($eventSource)
            if ($null -eq $window) { return } # Window might be closing
            $localState = $window.Tag
            Update-WindowsArchCombo -State $localState
        })

    $State.Controls.cmbWindowsSKU.Add_SelectionChanged({
            param($eventSource, $selectionChangedEventArgs)
            # This event should only fire on user interaction or after Update-WindowsSkuCombo runs.
            # We only need to update the architecture.
            $window = [System.Windows.Window]::GetWindow($eventSource)
            if ($null -eq $window) { return } # Window might be closing
            $localState = $window.Tag
            Update-WindowsArchCombo -State $localState
        })

    $State.Controls.btnBrowseISO.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $selectedPath = Invoke-BrowseAction -Type 'OpenFile' -Title "Select Windows ISO File" -Filter "ISO files (*.iso)|*.iso"
            if ($selectedPath) {
                $localState.Controls.txtISOPath.Text = $selectedPath
            }
        })

    # Updates Tab Event Handlers
    # Define a single handler scriptblock for all update checkboxes that affect the main InstallApps checkbox
    $updateCheckboxHandler = {
        param($eventSource, $routedEventArgs)
        $window = [System.Windows.Window]::GetWindow($eventSource)
        if ($null -ne $window) {
            # The function to call now lives in the Applications module
            Update-InstallAppsState -State $window.Tag
        }
    }
        
    # Attach the handler to all relevant update checkboxes
    $State.Controls.chkUpdateLatestDefender.Add_Checked($updateCheckboxHandler)
    $State.Controls.chkUpdateLatestDefender.Add_Unchecked($updateCheckboxHandler)
    $State.Controls.chkUpdateEdge.Add_Checked($updateCheckboxHandler)
    $State.Controls.chkUpdateEdge.Add_Unchecked($updateCheckboxHandler)
    $State.Controls.chkUpdateOneDrive.Add_Checked($updateCheckboxHandler)
    $State.Controls.chkUpdateOneDrive.Add_Unchecked($updateCheckboxHandler)
    $State.Controls.chkUpdateLatestMSRT.Add_Checked($updateCheckboxHandler)
    $State.Controls.chkUpdateLatestMSRT.Add_Unchecked($updateCheckboxHandler)
    $State.Controls.chkUpdateLatestCU.Add_Checked($updateCheckboxHandler)
    $State.Controls.chkUpdateLatestCU.Add_Unchecked($updateCheckboxHandler)
    
    # Also attach the handler to the Office checkbox
    $State.Controls.chkInstallOffice.Add_Checked($updateCheckboxHandler)
    $State.Controls.chkInstallOffice.Add_Unchecked($updateCheckboxHandler)

    # CU Interplay Event Handlers
    $State.Controls.chkLatestCU.Add_Checked({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $localState.Controls.chkPreviewCU.IsEnabled = $false
        })
    $State.Controls.chkLatestCU.Add_Unchecked({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $localState.Controls.chkPreviewCU.IsEnabled = $true
        })
    $State.Controls.chkPreviewCU.Add_Checked({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $localState.Controls.chkLatestCU.IsEnabled = $false
        })
    $State.Controls.chkPreviewCU.Add_Unchecked({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $localState.Controls.chkLatestCU.IsEnabled = $true
        })

    # Applications Tab Event Handlers
    # Define a single handler for interdependent application panel checkboxes
    $appPanelUpdateHandler = {
        param($eventSource, $routedEventArgs)
        $window = [System.Windows.Window]::GetWindow($eventSource)
        if ($null -ne $window) {
            Update-ApplicationPanelVisibility -State $window.Tag -TriggeringControlName $eventSource.Name
        }
    }

    # Attach the handler to all relevant checkboxes
    $State.Controls.chkInstallApps.Add_Checked($appPanelUpdateHandler)
    $State.Controls.chkInstallApps.Add_Unchecked($appPanelUpdateHandler)
    $State.Controls.chkBringYourOwnApps.Add_Checked($appPanelUpdateHandler)
    $State.Controls.chkBringYourOwnApps.Add_Unchecked($appPanelUpdateHandler)
    $State.Controls.chkInstallWingetApps.Add_Checked($appPanelUpdateHandler)
    $State.Controls.chkInstallWingetApps.Add_Unchecked($appPanelUpdateHandler)
            
    $State.Controls.btnBrowseApplicationPath.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $selectedPath = Invoke-BrowseAction -Type 'Folder' -Title "Select Application Path Folder"
            if ($selectedPath) { $localState.Controls.txtApplicationPath.Text = $selectedPath }
        })
            
    $State.Controls.btnBrowseAppListJsonPath.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $selectedPath = Invoke-BrowseAction -Type 'OpenFile' -Title "Select Winget AppList File" -Filter "JSON files (*.json)|*.json" -AllowNewFile
            if ($selectedPath) { $localState.Controls.txtAppListJsonPath.Text = $selectedPath }
        })

    $State.Controls.btnBrowseUserAppListPath.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $selectedPath = Invoke-BrowseAction -Type 'OpenFile' -Title "Select BYO AppList File" -Filter "JSON files (*.json)|*.json" -AllowNewFile
            if ($selectedPath) { $localState.Controls.txtUserAppListPath.Text = $selectedPath }
        })

    $State.Controls.btnBrowseAppSource.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $selectedPath = Invoke-BrowseAction -Type 'Folder' -Title "Select Application Source Folder"
            if ($selectedPath) { $localState.Controls.txtAppSource.Text = $selectedPath }
        })

    $State.Controls.btnAddApplication.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            Add-BYOApplication -State $localState
        })

    $State.Controls.btnEditApplication.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            Start-EditBYOApplication -State $localState
        })

    $State.Controls.btnSaveBYOApplications.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag

            # Default the save dialog to the configured BYO app list path.
            $currentPath = $localState.Controls.txtUserAppListPath.Text
            $initialDir = if (-not [string]::IsNullOrWhiteSpace($currentPath)) { Split-Path -Path $currentPath -Parent } else { $localState.Controls.txtApplicationPath.Text }
            if ([string]::IsNullOrWhiteSpace($initialDir) -or -not (Test-Path $initialDir)) { $initialDir = $localState.FFUDevelopmentPath }
            $fileName = if (-not [string]::IsNullOrWhiteSpace($currentPath)) { Split-Path -Path $currentPath -Leaf } else { "UserAppList.json" }
            
            $savePath = Invoke-BrowseAction -Type 'SaveFile' `
                -Title "Save BYO App List" `
                -Filter "JSON files (*.json)|*.json|All files (*.*)|*.*" `
                -InitialDirectory $initialDir `
                -FileName $fileName `
                -DefaultExt ".json"

            if ($savePath) {
                $localState.Controls.txtUserAppListPath.Text = $savePath
                Save-BYOApplicationList -Path $savePath -State $localState
            }
        })

    $State.Controls.btnLoadBYOApplications.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag

            # Default the import dialog to the configured BYO app list path.
            $currentPath = $localState.Controls.txtUserAppListPath.Text
            $initialDir = if (-not [string]::IsNullOrWhiteSpace($currentPath)) { Split-Path -Path $currentPath -Parent } else { $localState.Controls.txtApplicationPath.Text }
            if ([string]::IsNullOrWhiteSpace($initialDir) -or -not (Test-Path $initialDir)) { $initialDir = $localState.FFUDevelopmentPath }
            
            $loadPath = Invoke-BrowseAction -Type 'OpenFile' `
                -Title "Import BYO App List" `
                -Filter "JSON files (*.json)|*.json|All files (*.*)|*.*" `
                -InitialDirectory $initialDir

            if ($loadPath) {
                $localState.Controls.txtUserAppListPath.Text = $loadPath
                Import-BYOApplicationList -Path $loadPath -State $localState
                Update-CopyButtonState -State $localState
            }
        })

    $State.Controls.btnClearBYOApplications.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag

            # Before clearing, check if we are in edit mode and reset the state
            if ($null -ne $localState.Data.editingBYOApplication) {
                $localState.Data.editingBYOApplication = $null
                $localState.Controls.btnAddApplication.Content = "Add Application"
            }

            Clear-ListViewContent -State $localState `
                -ListViewControl $localState.Controls.lstApplications `
                -ConfirmationTitle "Clear BYO Applications" `
                -ConfirmationMessage "Are you sure you want to clear all 'Bring Your Own' applications?" `
                -StatusMessage "BYO application list cleared." `
                -PostClearAction { 
                Update-CopyButtonState -State $State
                Update-BYOAppsActionButtonsState -State $State 
            }
        })
            
    $State.Controls.btnCopyBYOApps.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            Invoke-CopyBYOApps -State $localState -Button $eventSource
        })

    $State.Controls.btnRemoveSelectedBYOApps.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            Remove-SelectedBYOApplications -State $localState
        })

    $State.Controls.btnMoveTop.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            Move-ListViewItemTop -ListView $localState.Controls.lstApplications
        })

    $State.Controls.btnMoveUp.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            Move-ListViewItemUp -ListView $localState.Controls.lstApplications
        })

    $State.Controls.btnMoveDown.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            Move-ListViewItemDown -ListView $localState.Controls.lstApplications
        })

    $State.Controls.btnMoveBottom.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            Move-ListViewItemBottom -ListView $localState.Controls.lstApplications
        })

    $State.Controls.lstApplications.Add_PreviewKeyDown({
            param($eventSource, $keyEvent)
            if ($keyEvent.Key -eq 'Space') {
                $window = [System.Windows.Window]::GetWindow($eventSource)
                $localState = $window.Tag
                Invoke-ListViewItemToggle -ListView $eventSource -State $localState -HeaderCheckBoxKeyName 'chkSelectAllBYOApps'
                # Update button states after toggle
                Update-BYOAppsActionButtonsState -State $localState
                $keyEvent.Handled = $true
            }
        })

    $State.Controls.lstApplications.Add_SelectionChanged({
            param($eventSource, $selChangeEvent)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $headerChk = $localState.Controls.chkSelectAllBYOApps
            if ($null -ne $headerChk) {
                Update-SelectAllHeaderCheckBoxState -ListView $localState.Controls.lstApplications -HeaderCheckBox $headerChk
            }
            # Update button states based on selection
            Update-BYOAppsActionButtonsState -State $localState
        })

    # Add a routed event handler to catch checkbox clicks within the ListView
    $State.Controls.lstApplications.AddHandler(
        [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent,
        [System.Windows.RoutedEventHandler] {
            param($eventSource, $e)
            # Check if the original source of the click was a CheckBox
            $clickedCheckBox = $e.OriginalSource
            if ($clickedCheckBox -is [System.Windows.Controls.CheckBox]) {
                $window = [System.Windows.Window]::GetWindow($eventSource)
                $localState = $window.Tag
                $dataItem = $clickedCheckBox.DataContext

                if ($null -ne $dataItem) {
                    # Defensively add the 'IsSelected' property if it's missing from the data object.
                    # This can happen in some complex UI scenarios or if the object was created without it.
                    if ($null -eq $dataItem.PSObject.Properties['IsSelected']) {
                        $dataItem | Add-Member -MemberType NoteProperty -Name 'IsSelected' -Value $false
                    }
                    
                    # Now that we're sure the property exists, set its value.
                    $dataItem.IsSelected = $clickedCheckBox.IsChecked
                }

                # Update the state of the action buttons based on the new selection.
                Update-BYOAppsActionButtonsState -State $localState

                # Also, update the header checkbox to reflect the change.
                $headerChk = $localState.Controls.chkSelectAllBYOApps
                if ($null -ne $headerChk) {
                    Update-SelectAllHeaderCheckBoxState -ListView $localState.Controls.lstApplications -HeaderCheckBox $headerChk
                }
            }
        }
    )

    # Apps Script Variables Event Handlers
    # Attach the handler to the script variables checkbox
    $State.Controls.chkDefineAppsScriptVariables.Add_Checked($appPanelUpdateHandler)
    $State.Controls.chkDefineAppsScriptVariables.Add_Unchecked($appPanelUpdateHandler)
    
    $State.Controls.btnAddAppsScriptVariable.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            Add-AppsScriptVariable -State $localState
        })

    $State.Controls.btnRemoveSelectedAppsScriptVariables.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            Remove-SelectedAppsScriptVariable -State $localState
        })

    $State.Controls.btnClearAppsScriptVariables.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag

            $postClearScriptBlock = {
                $headerChk = $localState.Controls.chkSelectAllAppsScriptVariables
                if ($null -ne $headerChk) {
                    Update-SelectAllHeaderCheckBoxState -ListView $localState.Controls.lstAppsScriptVariables -HeaderCheckBox $headerChk
                }
            }

            Clear-ListViewContent -State $localState `
                -ListViewControl $localState.Controls.lstAppsScriptVariables `
                -BackingDataList $localState.Data.appsScriptVariablesDataList `
                -ConfirmationTitle "Clear Apps Script Variables" `
                -ConfirmationMessage "Are you sure you want to clear all Apps Script Variables?" `
                -StatusMessage "Apps Script Variables list cleared." `
                -TextBoxesToClear @($localState.Controls.txtAppsScriptKey, $localState.Controls.txtAppsScriptValue) `
                -PostClearAction $postClearScriptBlock
        })

    $State.Controls.lstAppsScriptVariables.Add_PreviewKeyDown({
            param($eventSource, $keyEvent)
            if ($keyEvent.Key -eq 'Space') {
                $window = [System.Windows.Window]::GetWindow($eventSource)
                $localState = $window.Tag
                Invoke-ListViewItemToggle -ListView $eventSource -State $localState -HeaderCheckBoxKeyName 'chkSelectAllAppsScriptVariables'
                $keyEvent.Handled = $true
            }
        })

    $State.Controls.btnCheckWingetModule.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $buttonSender = $eventSource

            $buttonSender.IsEnabled = $false
            $window.Cursor = [System.Windows.Input.Cursors]::Wait
            # Initial UI update before calling the core function
            Update-WingetVersionFields -State $localState -wingetText "Checking..." -moduleText "Checking..."

            $statusResult = $null
            try {
                # Call the Core function to perform checks and potential install/update
                # Pass the UI update function as a callback
                $statusResult = Confirm-WingetInstallationUI -UiUpdateCallback {
                    param($wingetText, $moduleText)
                    Update-WingetVersionFields -State $localState -wingetText $wingetText -moduleText $moduleText
                }

                # Display appropriate message based on the result
                if ($statusResult.Success -and $statusResult.UpdateAttempted) {
                    # Update attempted and successful
                    [System.Windows.MessageBox]::Show("Winget components installed/updated successfully.", "Winget Installation Complete", "OK", "Information")
                }
                elseif (-not $statusResult.Success) {
                    # Error occurred
                    $errorMessage = if (-not [string]::IsNullOrWhiteSpace($statusResult.Message)) { $statusResult.Message } else { "An unknown error occurred during Winget check/install." }
                    [System.Windows.MessageBox]::Show($errorMessage, "Winget Error", "OK", "Error")
                }
                # If Winget components were already up-to-date ($statusResult.Success -eq $true -and $statusResult.UpdateAttempted -eq $false), no message box is shown.

                # Show search panel only if the final status is successful and checkbox is still checked
                if ($statusResult.Success -and $localState.Controls.chkInstallWingetApps.IsChecked) {
                    $localState.Controls.wingetSearchPanel.Visibility = 'Visible'
                }
                else {
                    $localState.Controls.wingetSearchPanel.Visibility = 'Collapsed' # Hide if not successful or unchecked
                }
            }
            catch {
                # Catch errors from the Confirm-WingetInstallationUI call itself (less likely now)
                Update-WingetVersionFields -State $localState -wingetText "Error" -moduleText "Error"
                [System.Windows.MessageBox]::Show("Unexpected error checking/installing Winget components: $($_.Exception.Message)", "Error", "OK", "Error")
                $localState.Controls.wingetSearchPanel.Visibility = 'Collapsed' # Ensure search is hidden on error
            }
            finally {
                $buttonSender.IsEnabled = $true
                $window.Cursor = $null
            }
        })
        
    $State.Controls.btnWingetSearch.Add_Click({ 
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            Search-WingetApps -State $localState 
        })
        
    $State.Controls.txtWingetSearch.Add_KeyDown({
            param($eventSource, $keyEvent)
            if ($keyEvent.Key -eq 'Return') { 
                $window = [System.Windows.Window]::GetWindow($eventSource)
                $localState = $window.Tag
                Search-WingetApps -State $localState
                $keyEvent.Handled = $true 
            }
        })
        
    $State.Controls.btnSaveWingetList.Add_Click({ 
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            Save-WingetList -State $localState 
        })
        
    $State.Controls.btnImportWingetList.Add_Click({ 
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            Import-WingetList -State $localState 
        })
        
    $State.Controls.btnClearWingetList.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag

            $postClearScriptBlock = {
                $headerChk = $localState.Controls.chkSelectAllWingetResults
                if ($null -ne $headerChk) {
                    Update-SelectAllHeaderCheckBoxState -ListView $localState.Controls.lstWingetResults -HeaderCheckBox $headerChk
                }
            }

            Clear-ListViewContent -State $localState `
                -ListViewControl $localState.Controls.lstWingetResults `
                -ConfirmationTitle "Clear Winget List" `
                -ConfirmationMessage "Are you sure you want to clear the Winget application list and search results?" `
                -StatusMessage "Winget application list cleared." `
                -TextBoxesToClear @($localState.Controls.txtWingetSearch) `
                -PostClearAction $postClearScriptBlock
        })
    $State.Controls.lstWingetResults.Add_PreviewKeyDown({
            param($eventSource, $keyEvent)
            if ($keyEvent.Key -eq 'Space') {
                $window = [System.Windows.Window]::GetWindow($eventSource)
                $localState = $window.Tag
                Invoke-ListViewItemToggle -ListView $eventSource -State $localState -HeaderCheckBoxKeyName 'chkSelectAllWingetResults'
                $keyEvent.Handled = $true
            }
        })
        
    $State.Controls.btnDownloadSelected.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            Invoke-WingetDownload -State $localState -Button $eventSource
        })
        
    # M365 Apps/Office tab Event
    $State.Controls.btnBrowseOfficePath.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $selectedPath = Invoke-BrowseAction -Type 'Folder' -Title "Select Office Path"
            if ($selectedPath) {
                $localState.Controls.txtOfficePath.Text = $selectedPath
            }
        })

    $State.Controls.btnBrowseOfficeConfigXMLFile.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $selectedPath = Invoke-BrowseAction -Type 'OpenFile' -Title "Select Office Configuration XML File" -Filter "XML files (*.xml)|*.xml"
            if ($selectedPath) {
                $localState.Controls.txtOfficeConfigXMLFilePath.Text = $selectedPath
            }
        })

    $State.Controls.chkInstallOffice.Add_Checked({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $localState.Controls.OfficePathStackPanel.Visibility = 'Visible'
            $localState.Controls.OfficePathGrid.Visibility = 'Visible'
            $localState.Controls.CopyOfficeConfigXMLStackPanel.Visibility = 'Visible'
            # Show/hide XML file path based on checkbox state
            $localState.Controls.OfficeConfigurationXMLFileStackPanel.Visibility = if ($localState.Controls.chkCopyOfficeConfigXML.IsChecked) { 'Visible' } else { 'Collapsed' }
            $localState.Controls.OfficeConfigurationXMLFileGrid.Visibility = if ($localState.Controls.chkCopyOfficeConfigXML.IsChecked) { 'Visible' } else { 'Collapsed' }
        })
    $State.Controls.chkInstallOffice.Add_Unchecked({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $localState.Controls.OfficePathStackPanel.Visibility = 'Collapsed'
            $localState.Controls.OfficePathGrid.Visibility = 'Collapsed'
            $localState.Controls.CopyOfficeConfigXMLStackPanel.Visibility = 'Collapsed'
            $localState.Controls.OfficeConfigurationXMLFileStackPanel.Visibility = 'Collapsed'
            $localState.Controls.OfficeConfigurationXMLFileGrid.Visibility = 'Collapsed'
        })
    $State.Controls.chkCopyOfficeConfigXML.Add_Checked({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag

            $localState.Controls.OfficeConfigurationXMLFileStackPanel.Visibility = 'Visible'
            $localState.Controls.OfficeConfigurationXMLFileGrid.Visibility = 'Visible'
        })
    $State.Controls.chkCopyOfficeConfigXML.Add_Unchecked({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag

            $localState.Controls.OfficeConfigurationXMLFileStackPanel.Visibility = 'Collapsed'
            $localState.Controls.OfficeConfigurationXMLFileGrid.Visibility = 'Collapsed'
        })

    # Drivers Tab Event Handlers
    # Define a single handler for interdependent driver checkboxes
    $driverCheckboxHandler = {
        param($eventSource, $routedEventArgs)
        $window = [System.Windows.Window]::GetWindow($eventSource)
        if ($null -ne $window) {
            Update-DriverCheckboxStates -State $window.Tag
        }
    }

    # Attach the handler to all relevant checkboxes
    $State.Controls.chkInstallDrivers.Add_Checked($driverCheckboxHandler)
    $State.Controls.chkInstallDrivers.Add_Unchecked($driverCheckboxHandler)
    $State.Controls.chkCopyDrivers.Add_Checked($driverCheckboxHandler)
    $State.Controls.chkCopyDrivers.Add_Unchecked($driverCheckboxHandler)
    $State.Controls.chkCompressDriversToWIM.Add_Checked($driverCheckboxHandler)
    $State.Controls.chkCompressDriversToWIM.Add_Unchecked($driverCheckboxHandler)
    $State.Controls.chkCopyPEDrivers.Add_Checked($driverCheckboxHandler)
    $State.Controls.chkCopyPEDrivers.Add_Unchecked($driverCheckboxHandler)
    $State.Controls.chkUseDriversAsPEDrivers.Add_Checked($driverCheckboxHandler)
    $State.Controls.chkUseDriversAsPEDrivers.Add_Unchecked($driverCheckboxHandler)

    $State.Controls.btnBrowseDriversFolder.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $initialDir = Join-Path -Path $localState.FFUDevelopmentPath -ChildPath "Drivers"
            $selectedPath = Invoke-BrowseAction -Type 'Folder' -Title "Select Drivers Folder" -InitialDirectory $initialDir
            if ($selectedPath) {
                $localState.Controls.txtDriversFolder.Text = $selectedPath
            }
        })

    $State.Controls.btnBrowsePEDriversFolder.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $selectedPath = Invoke-BrowseAction -Type 'Folder' -Title "Select PE Drivers Folder"
            if ($selectedPath) {
                $localState.Controls.txtPEDriversFolder.Text = $selectedPath
            }
        })

    $State.Controls.btnBrowseDriversJsonPath.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            
            $dialogInitialDirectory = $null
            $currentDriversJsonPath = $localState.Controls.txtDriversJsonPath.Text
            if (-not [string]::IsNullOrWhiteSpace($currentDriversJsonPath)) {
                try {
                    $parentDir = Split-Path -Path $currentDriversJsonPath -Parent -ErrorAction Stop
                    if (Test-Path -Path $parentDir -PathType Container) {
                        $dialogInitialDirectory = $parentDir
                    }
                }
                catch {
                    WriteLog "Could not determine initial directory from '$currentDriversJsonPath'. Using default."
                }
            }

            $selectedPath = Invoke-BrowseAction -Type 'SaveFile' `
                -Title "Select or Create Drivers.json File" `
                -Filter "JSON files (*.json)|*.json|All files (*.*)|*.*" `
                -FileName "Drivers.json" `
                -InitialDirectory $dialogInitialDirectory `
                -AllowNewFile

            if ($selectedPath) {
                $localState.Controls.txtDriversJsonPath.Text = $selectedPath
                WriteLog "User selected or created Drivers.json at: $selectedPath"
            }
            else {
                WriteLog "User cancelled SaveFileDialog for Drivers.json."
            }
        })

    # Define a single handler for the Download Drivers checkbox
    $driverDownloadCheckboxHandler = {
        param($eventSource, $routedEventArgs)
        $window = [System.Windows.Window]::GetWindow($eventSource)
        if ($null -ne $window) {
            Update-DriverDownloadPanelVisibility -State $window.Tag
        }
    }
    $State.Controls.chkDownloadDrivers.Add_Checked($driverDownloadCheckboxHandler)
    $State.Controls.chkDownloadDrivers.Add_Unchecked($driverDownloadCheckboxHandler)

    $State.Controls.btnGetModels.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            Invoke-GetModels -State $localState -Button $eventSource
        })

    $State.Controls.txtModelFilter.Add_TextChanged({
            param($sourceObject, $textChangedEventArgs)
            $window = [System.Windows.Window]::GetWindow($sourceObject)
            $localState = $window.Tag
            Search-DriverModels -filterText $localState.Controls.txtModelFilter.Text -State $localState
        })

    $State.Controls.btnDownloadSelectedDrivers.Add_Click({
            param($buttonSender, $clickEventArgs)
            $window = [System.Windows.Window]::GetWindow($buttonSender)
            $localState = $window.Tag
            Invoke-DownloadSelectedDrivers -State $localState -Button $buttonSender
        })

    $State.Controls.btnClearDriverList.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag

            $postClearScriptBlock = {
                # This scriptblock inherits the $localState variable from its parent scope.
                $headerChk = $localState.Controls.chkSelectAllDriverModels
                if ($null -ne $headerChk) {
                    Update-SelectAllHeaderCheckBoxState -ListView $localState.Controls.lstDriverModels -HeaderCheckBox $headerChk
                }
            }
            
            Clear-ListViewContent -State $localState `
                -ListViewControl $localState.Controls.lstDriverModels `
                -BackingDataList $localState.Data.allDriverModels `
                -ConfirmationTitle "Clear Driver List" `
                -ConfirmationMessage "Are you sure you want to clear the driver list?" `
                -StatusMessage "Driver list cleared." `
                -TextBoxesToClear @($localState.Controls.txtModelFilter)`
                -PostClearAction $postClearScriptBlock
        })

    $State.Controls.lstDriverModels.Add_PreviewKeyDown({
            param($eventSource, $keyEvent)
            if ($keyEvent.Key -eq 'Space') {
                $window = [System.Windows.Window]::GetWindow($eventSource)
                $localState = $window.Tag
                Invoke-ListViewItemToggle -ListView $eventSource -State $localState -HeaderCheckBoxKeyName 'chkSelectAllDriverModels'
                $keyEvent.Handled = $true
            }
        })

    $State.Controls.btnSaveDriversJson.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            Save-DriversJson -State $localState
        })
            
    $State.Controls.btnImportDriversJson.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            Import-DriversJson -State $localState
        })

    $State.Controls.btnLoadConfig.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            Invoke-LoadConfiguration -State $localState
        })
    $State.Controls.btnRestoreDefaults.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            Invoke-RestoreDefaults -State $localState
        })
    $State.Controls.btnBuildConfig.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            Invoke-SaveConfiguration -State $localState
        })

    # Monitor Tab Event Handlers
    $State.Controls.lstLogOutput.Add_KeyDown({
            param($eventSource, $keyEventArgs)
            # Check for Ctrl+C
            if ($keyEventArgs.Key -eq 'C' -and ($keyEventArgs.KeyboardDevice.Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) {
                $listBox = $eventSource
                if ($listBox.SelectedItems.Count -gt 0) {
                    $selectedLines = $listBox.SelectedItems | ForEach-Object { $_.ToString() }
                    $clipboardText = $selectedLines -join [System.Environment]::NewLine
                    
                    try {
                        [System.Windows.Clipboard]::SetText($clipboardText)
                        WriteLog "Copied $($listBox.SelectedItems.Count) log lines to clipboard."
                    }
                    catch {
                        WriteLog "Error copying to clipboard: $($_.Exception.Message)"
                    }
                }
                $keyEventArgs.Handled = $true
            }
        })

    $State.Controls.lstLogOutput.Add_SelectionChanged({
            param($eventSource, $selectionChangedEventArgs)
            $listBox = $eventSource
            $window = [System.Windows.Window]::GetWindow($listBox)
            if ($null -eq $window) { return }
            $localState = $window.Tag

            # If nothing is selected or the list is empty, do nothing.
            if ($listBox.SelectedIndex -eq -1 -or $listBox.Items.Count -eq 0) {
                return
            }

            # Check if the last item is selected
            $isLastItemSelected = ($listBox.SelectedIndex -eq ($listBox.Items.Count - 1))

            # Update the flag
            $localState.Flags.autoScrollLog = $isLastItemSelected
            if ($isLastItemSelected) {
                # WriteLog "Monitor tab autoscroll enabled (last item selected)."
            }
            else {
                WriteLog "Monitor tab autoscroll disabled (user selected item #$($listBox.SelectedIndex))."
            }
        })
}
Export-ModuleMember -Function *