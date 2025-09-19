<#
.SYNOPSIS
    Contains the function for registering all WPF UI event handlers for the FFU Builder application.
.DESCRIPTION
    This module is dedicated to managing user interactions within the FFU Builder UI. It contains the Register-EventHandlers function, which connects UI controls defined in the XAML to their corresponding actions in the PowerShell backend. This includes handling button clicks, text input validation, checkbox state changes, and list view interactions across all tabs, effectively wiring up the application's front-end to its core logic.
#>

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
        param($sender, $pastingEventArgs)
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

    # Build Tab Event Handlers
    $State.Controls.btnBrowseFFUDevPath.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $selectedPath = Invoke-BrowseAction -Type 'Folder' -Title "Select FFU Development Path"
            if ($selectedPath) {
                $localState.Controls.txtFFUDevPath.Text = $selectedPath
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

    # Build USB Drive Settings Event Handlers
    $State.Controls.chkBuildUSBDriveEnable.Add_Checked({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $localState.Controls.usbSection.Visibility = 'Visible'
            $localState.Controls.chkSelectSpecificUSBDrives.IsEnabled = $true
        })
    $State.Controls.chkBuildUSBDriveEnable.Add_Unchecked({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $localState.Controls.usbSection.Visibility = 'Collapsed'
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
    $State.Controls.cmbVMSwitchName.Add_SelectionChanged({
            param($eventSource, $selectionChangedEventArgs)
            # The state object is available via the parent window's Tag property
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag

            $selectedItem = $eventSource.SelectedItem
            if ($selectedItem -eq 'Other') {
                $localState.Controls.txtCustomVMSwitchName.Visibility = 'Visible'
                if ([string]::IsNullOrWhiteSpace($localState.Controls.txtCustomVMSwitchName.Text) -and $null -ne $localState.Data.customVMSwitchName) {
                    $localState.Controls.txtCustomVMSwitchName.Text = $localState.Data.customVMSwitchName
                }
                if ($null -ne $localState.Data.customVMHostIP -and -not [string]::IsNullOrWhiteSpace($localState.Data.customVMHostIP)) {
                    $localState.Controls.txtVMHostIPAddress.Text = $localState.Data.customVMHostIP
                }
            }
            else {
                $localState.Controls.txtCustomVMSwitchName.Visibility = 'Collapsed'
                if ($null -ne $selectedItem -and $localState.Data.vmSwitchMap.ContainsKey($selectedItem)) {
                    $localState.Controls.txtVMHostIPAddress.Text = $localState.Data.vmSwitchMap[$selectedItem]
                }
                else {
                    $localState.Controls.txtVMHostIPAddress.Text = '' # Clear IP if not found or key null
                }
            }
        })

    # Persist custom VM switch name/IP when user edits them while 'Other' is selected
    $State.Controls.txtVMHostIPAddress.Add_LostFocus({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            if ($localState.Controls.cmbVMSwitchName.SelectedItem -eq 'Other') {
                $localState.Data.customVMHostIP = $localState.Controls.txtVMHostIPAddress.Text
            }
        })
    $State.Controls.txtCustomVMSwitchName.Add_LostFocus({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            if ($localState.Controls.cmbVMSwitchName.SelectedItem -eq 'Other') {
                $localState.Data.customVMSwitchName = $localState.Controls.txtCustomVMSwitchName.Text
            }
        })

    # Windows Settings tab Event Handlers
    $State.Controls.txtISOPath.Add_TextChanged({
            param($eventSource, $textChangedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            Get-WindowsSettingsCombos -isoPath $localState.Controls.txtISOPath.Text -State $localState
        })

    $State.Controls.cmbWindowsRelease.Add_SelectionChanged({
            param($eventSource, $selectionChangedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $selectedReleaseValue = 11 # Default if null
            if ($null -ne $localState.Controls.cmbWindowsRelease.SelectedItem) {
                $selectedReleaseValue = $localState.Controls.cmbWindowsRelease.SelectedItem.Value
            }
            Update-WindowsVersionCombo -selectedRelease $selectedReleaseValue -isoPath $localState.Controls.txtISOPath.Text -State $localState
            Update-WindowsSkuCombo -State $localState
            Update-WindowsArchCombo -State $localState
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
            $selectedPath = Invoke-BrowseAction -Type 'OpenFile' -Title "Select AppList.json File" -Filter "JSON files (*.json)|*.json" -AllowNewFile
            if ($selectedPath) { $localState.Controls.txtAppListJsonPath.Text = $selectedPath }
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

            $initialDir = $localState.Controls.txtApplicationPath.Text
            if ([string]::IsNullOrWhiteSpace($initialDir) -or -not (Test-Path $initialDir)) { $initialDir = $localState.FFUDevelopmentPath }
            
            $savePath = Invoke-BrowseAction -Type 'SaveFile' `
                -Title "Save Application List" `
                -Filter "JSON files (*.json)|*.json|All files (*.*)|*.*" `
                -InitialDirectory $initialDir `
                -FileName "UserAppList.json" `
                -DefaultExt ".json"

            if ($savePath) { Save-BYOApplicationList -Path $savePath -State $localState }
        })

    $State.Controls.btnLoadBYOApplications.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag

            $initialDir = $localState.Controls.txtApplicationPath.Text
            if ([string]::IsNullOrWhiteSpace($initialDir) -or -not (Test-Path $initialDir)) { $initialDir = $localState.FFUDevelopmentPath }
            
            $loadPath = Invoke-BrowseAction -Type 'OpenFile' `
                -Title "Import Application List" `
                -Filter "JSON files (*.json)|*.json|All files (*.*)|*.*" `
                -InitialDirectory $initialDir

            if ($loadPath) { 
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