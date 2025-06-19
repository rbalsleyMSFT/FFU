function Register-EventHandlers {
    param([PSCustomObject]$State)
    WriteLog "Registering UI event handlers..."

    # Build Tab Event Handlers
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
        

    $State.Controls.lstUSBDrives.Add_KeyDown({
            param($eventSource, $keyEvent)
            if ($keyEvent.Key -eq 'Space') {
                $window = [System.Windows.Window]::GetWindow($eventSource)
                $localState = $window.Tag
                $selectedItem = $localState.Controls.lstUSBDrives.SelectedItem
                if ($selectedItem) {
                    $selectedItem.IsSelected = -not $selectedItem.IsSelected
                    $localState.Controls.lstUSBDrives.Items.Refresh()
                    # After toggling, update the 'Select All' header checkbox state
                    $headerChk = $localState.Controls.chkSelectAllUSBDrivesHeader
                    if ($null -ne $headerChk) {
                        Update-SelectAllHeaderCheckBoxState -ListView $localState.Controls.lstUSBDrives -HeaderCheckBox $headerChk
                    }
                }
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
                $localState.Controls.txtVMHostIPAddress.Text = '' # Clear IP for custom
            }
            else {
                $localState.Controls.txtCustomVMSwitchName.Visibility = 'Collapsed'
                if ($localState.Data.vmSwitchMap.ContainsKey($selectedItem)) {
                    $localState.Controls.txtVMHostIPAddress.Text = $localState.Data.vmSwitchMap[$selectedItem]
                }
                else {
                    $localState.Controls.txtVMHostIPAddress.Text = '' # Clear IP if not found in map
                }
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
            # Only need to update the Version combo when Release changes
            Update-WindowsVersionCombo -selectedRelease $selectedReleaseValue -isoPath $localState.Controls.txtISOPath.Text -State $localState
            # Also update the SKU combo (now derives values internally)
            Update-WindowsSkuCombo -State $localState
        })

    $State.Controls.btnBrowseISO.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $ofd = New-Object System.Windows.Forms.OpenFileDialog
            $ofd.Filter = "ISO files (*.iso)|*.iso"
            $ofd.Title = "Select Windows ISO File"
            if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $localState.Controls.txtISOPath.Text = $ofd.FileName }
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
    $State.Controls.chkInstallApps.Add_Checked({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $localState.Controls.chkInstallWingetApps.Visibility = 'Visible'
            $localState.Controls.applicationPathPanel.Visibility = 'Visible'
            $localState.Controls.appListJsonPathPanel.Visibility = 'Visible'
            $localState.Controls.chkBringYourOwnApps.Visibility = 'Visible'
            $localState.Controls.chkDefineAppsScriptVariables.Visibility = 'Visible'
        })
    $State.Controls.chkInstallApps.Add_Unchecked({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $localState.Controls.chkInstallWingetApps.IsChecked = $false
            $localState.Controls.chkBringYourOwnApps.IsChecked = $false
            $localState.Controls.chkInstallWingetApps.Visibility = 'Collapsed'
            $localState.Controls.applicationPathPanel.Visibility = 'Collapsed'
            $localState.Controls.appListJsonPathPanel.Visibility = 'Collapsed'
            $localState.Controls.chkBringYourOwnApps.Visibility = 'Collapsed'
            $localState.Controls.wingetPanel.Visibility = 'Collapsed'
            $localState.Controls.wingetSearchPanel.Visibility = 'Collapsed'
            $localState.Controls.byoApplicationPanel.Visibility = 'Collapsed'
            $localState.Controls.chkDefineAppsScriptVariables.IsChecked = $false
            $localState.Controls.chkDefineAppsScriptVariables.Visibility = 'Collapsed'
            $localState.Controls.appsScriptVariablesPanel.Visibility = 'Collapsed'
        })
            
    $State.Controls.btnBrowseApplicationPath.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $selectedPath = Show-ModernFolderPicker -Title "Select Application Path Folder"
            if ($selectedPath) { $localState.Controls.txtApplicationPath.Text = $selectedPath }
        })
            
    $State.Controls.btnBrowseAppListJsonPath.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $ofd = New-Object System.Windows.Forms.OpenFileDialog
            $ofd.Filter = "JSON files (*.json)|*.json"
            $ofd.Title = "Select AppList.json File"
            $ofd.CheckFileExists = $false
            if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $localState.Controls.txtAppListJsonPath.Text = $ofd.FileName }
        })
            
    $State.Controls.chkBringYourOwnApps.Add_Checked({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $localState.Controls.byoApplicationPanel.Visibility = 'Visible'
        })
    $State.Controls.chkBringYourOwnApps.Add_Unchecked({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $localState.Controls.byoApplicationPanel.Visibility = 'Collapsed'
            $localState.Controls.txtAppName.Text = ''
            $localState.Controls.txtAppCommandLine.Text = ''
            $localState.Controls.txtAppArguments.Text = ''
            $localState.Controls.txtAppSource.Text = ''
        })
            
    $State.Controls.chkInstallWingetApps.Add_Checked({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $localState.Controls.wingetPanel.Visibility = 'Visible'
        })
    $State.Controls.chkInstallWingetApps.Add_Unchecked({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $localState.Controls.wingetPanel.Visibility = 'Collapsed'
            $localState.Controls.wingetSearchPanel.Visibility = 'Collapsed'
        })

    $State.Controls.btnClearBYOApplications.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag

            Clear-ListViewContent -State $localState `
                -ListViewControl $localState.Controls.lstApplications `
                -ConfirmationTitle "Clear BYO Applications" `
                -ConfirmationMessage "Are you sure you want to clear all 'Bring Your Own' applications?" `
                -StatusMessage "BYO application list cleared." `
                -PostClearAction { Update-CopyButtonState -State $State }
        })

    $State.Controls.btnClearAppsScriptVariables.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag

            $postClearScriptBlock = {
                $headerChk = $State.Controls.chkSelectAllAppsScriptVariables
                if ($null -ne $headerChk) {
                    Update-SelectAllHeaderCheckBoxState -ListView $ListViewControl -HeaderCheckBox $headerChk
                }
            }

            Clear-ListViewContent -State $localState `
                -ListViewControl $localState.Controls.lstAppsScriptVariables `
                -BackingDataList $localState.Data.appsScriptVariablesDataList `
                -ConfirmationTitle "Clear Apps Script Variables" `
                -ConfirmationMessage "Are you sure you want to clear all Apps Script Variables?" `
                -StatusMessage "Apps Script Variables list cleared." `
                -PostClearAction $postClearScriptBlock
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
                $headerChk = $State.Controls.chkSelectAllWingetResults
                if ($null -ne $headerChk) {
                    Update-SelectAllHeaderCheckBoxState -ListView $ListViewControl -HeaderCheckBox $headerChk
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
        
    $State.Controls.btnDownloadSelected.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            Invoke-WingetDownload -State $localState -Button $eventSource
        })
        
    # M365 Apps/Office tab Event
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
    $State.Controls.chkDownloadDrivers.Add_Checked({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $localState.Controls.cmbMake.Visibility = 'Visible'
            $localState.Controls.btnGetModels.Visibility = 'Visible'
            $localState.Controls.spMakeSection.Visibility = 'Visible'
            $localState.Controls.spModelFilterSection.Visibility = 'Visible'
            $localState.Controls.lstDriverModels.Visibility = 'Visible'
            $localState.Controls.spDriverActionButtons.Visibility = 'Visible'
        })
    $State.Controls.chkDownloadDrivers.Add_Unchecked({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            $localState.Controls.cmbMake.Visibility = 'Collapsed'
            $localState.Controls.btnGetModels.Visibility = 'Collapsed'
            $localState.Controls.spMakeSection.Visibility = 'Collapsed'
            $localState.Controls.spModelFilterSection.Visibility = 'Collapsed'
            $localState.Controls.lstDriverModels.Visibility = 'Collapsed'
            $localState.Controls.spDriverActionButtons.Visibility = 'Collapsed'
            $localState.Controls.lstDriverModels.ItemsSource = $null
            $localState.Data.allDriverModels.Clear()
            $localState.Controls.txtModelFilter.Text = ""
        })

    $State.Controls.btnGetModels.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag

            $selectedMake = $localState.Controls.cmbMake.SelectedItem
            $localState.Controls.txtStatus.Text = "Getting models for $selectedMake..."
            $window.Cursor = [System.Windows.Input.Cursors]::Wait
            $eventSource.IsEnabled = $false
            try {
                # Get ALL previously selected models to preserve them, regardless of make.
                $allPreviouslySelectedModels = @($localState.Data.allDriverModels | Where-Object { $_.IsSelected })

                # Get newly fetched models for the current make
                $newlyFetchedStandardizedModels = Get-ModelsForMake -SelectedMake $selectedMake -State $localState

                $combinedModelsList = [System.Collections.Generic.List[PSCustomObject]]::new()
                $modelIdentifiersInCombinedList = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

                # Add all previously selected models first to preserve their 'IsSelected' state.
                foreach ($item in $allPreviouslySelectedModels) {
                    $combinedModelsList.Add($item)
                    $modelIdentifiersInCombinedList.Add("$($item.Make)::$($item.Model)") | Out-Null
                }

                # Add newly fetched models, but only if they are not already in the list.
                # This prevents overwriting a selected model with an unselected one.
                $addedNewCount = 0
                foreach ($item in $newlyFetchedStandardizedModels) {
                    if ($modelIdentifiersInCombinedList.Add("$($item.Make)::$($item.Model)")) {
                        $combinedModelsList.Add($item)
                        $addedNewCount++
                    }
                }

                # Sort the combined list
                $sortedModels = $combinedModelsList | Sort-Object @{Expression = { $_.IsSelected }; Descending = $true }, Make, Model

                # Create a new list object from the sorted results. This is safer than modifying the existing list
                # that the UI is bound to, which can cause inconsistency errors.
                $newList = [System.Collections.Generic.List[PSCustomObject]]::new()
                if ($null -ne $sortedModels) {
                    # Sort-Object can return a single object or an array. Ensure it's always treated as a collection.
                    foreach ($model in @($sortedModels)) {
                        $newList.Add($model)
                    }
                }
                $localState.Data.allDriverModels = $newList
                
                # Update the UI ItemsSource to point to the new list and clear the filter
                $localState.Controls.lstDriverModels.ItemsSource = $localState.Data.allDriverModels
                $localState.Controls.txtModelFilter.Text = ""

                if ($localState.Data.allDriverModels.Count -gt 0) {
                    $localState.Controls.spModelFilterSection.Visibility = 'Visible'
                    $localState.Controls.lstDriverModels.Visibility = 'Visible'
                    $localState.Controls.spDriverActionButtons.Visibility = 'Visible'
                    $statusText = "Displaying $($localState.Data.allDriverModels.Count) models."
                    if ($newlyFetchedStandardizedModels.Count -gt 0 -and $addedNewCount -eq 0 -and $allPreviouslySelectedModels.Count -gt 0) {
                        $statusText = "Fetched $($newlyFetchedStandardizedModels.Count) models for $selectedMake; all were already in the selected list. Displaying $($localState.Data.allDriverModels.Count) total selected models."
                    }
                    elseif ($addedNewCount -gt 0) {
                        $statusText = "Added $addedNewCount new models for $selectedMake. Displaying $($localState.Data.allDriverModels.Count) total models."
                    }
                    elseif ($newlyFetchedStandardizedModels.Count -eq 0 -and $selectedMake -eq 'Lenovo' ) {
                        $statusText = if ($allPreviouslySelectedModels.Count -gt 0) { "No new models found for $selectedMake. Displaying $($allPreviouslySelectedModels.Count) previously selected models." } else { "No models found for $selectedMake." }
                    }
                    elseif ($newlyFetchedStandardizedModels.Count -eq 0) {
                        $statusText = "No new models found for $selectedMake. Displaying $($localState.Data.allDriverModels.Count) previously selected models."
                    }
                    $localState.Controls.txtStatus.Text = $statusText
                }
                else {
                    $localState.Controls.spModelFilterSection.Visibility = 'Collapsed'
                    $localState.Controls.lstDriverModels.Visibility = 'Collapsed'
                    $localState.Controls.spDriverActionButtons.Visibility = 'Collapsed'
                    $localState.Controls.txtStatus.Text = "No models to display for $selectedMake."
                }
            }
            catch {
                $localState.Controls.txtStatus.Text = "Error getting models: $($_.Exception.Message)"
                [System.Windows.MessageBox]::Show("Error getting models: $($_.Exception.Message)", "Error", "OK", "Error")
                if ($null -eq $localState.Data.allDriverModels -or $localState.Data.allDriverModels.Count -eq 0) {
                    $localState.Controls.spModelFilterSection.Visibility = 'Collapsed'
                    $localState.Controls.lstDriverModels.Visibility = 'Collapsed'
                    $localState.Controls.spDriverActionButtons.Visibility = 'Collapsed'
                    $localState.Controls.lstDriverModels.ItemsSource = $null
                    $localState.Controls.txtModelFilter.Text = ""
                }
            }
            finally {
                $window.Cursor = $null
                $eventSource.IsEnabled = $true
            }
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

            $selectedDrivers = @($localState.Controls.lstDriverModels.Items | Where-Object { $_.IsSelected })
            if (-not $selectedDrivers) {
                [System.Windows.MessageBox]::Show("No drivers selected to download.", "Download Drivers", "OK", "Information")
                return
            }

            $buttonSender.IsEnabled = $false
            $localState.Controls.pbOverallProgress.Visibility = 'Visible'
            $localState.Controls.pbOverallProgress.Value = 0
            $localState.Controls.txtStatus.Text = "Preparing driver downloads..."

            # Define common necessary task-specific variables locally
            # Ensure required selections are made
            if ($null -eq $localState.Controls.cmbWindowsRelease.SelectedItem) {
                [System.Windows.MessageBox]::Show("Please select a Windows Release.", "Missing Information", "OK", "Warning")
                $buttonSender.IsEnabled = $true
                $localState.Controls.pbOverallProgress.Visibility = 'Collapsed'
                $localState.Controls.txtStatus.Text = "Driver download cancelled."
                return
            }
            if ($null -eq $localState.Controls.cmbWindowsArch.SelectedItem) {
                [System.Windows.MessageBox]::Show("Please select a Windows Architecture.", "Missing Information", "OK", "Warning")
                $buttonSender.IsEnabled = $true
                $localState.Controls.pbOverallProgress.Visibility = 'Collapsed'
                $localState.Controls.txtStatus.Text = "Driver download cancelled."
                return
            }
            if (($selectedDrivers | Where-Object { $_.Make -eq 'HP' }) -and $null -ne $localState.Controls.cmbWindowsVersion -and $null -eq $localState.Controls.cmbWindowsVersion.SelectedItem) {
                [System.Windows.MessageBox]::Show("HP drivers are selected. Please select a Windows Version.", "Missing Information", "OK", "Warning")
                $buttonSender.IsEnabled = $true
                $localState.Controls.pbOverallProgress.Visibility = 'Collapsed'
                $localState.Controls.txtStatus.Text = "Driver download cancelled."
                return
            }

            $localDriversFolder = $localState.Controls.txtDriversFolder.Text
            $localWindowsRelease = $localState.Controls.cmbWindowsRelease.SelectedItem.Value
            $localWindowsArch = $localState.Controls.cmbWindowsArch.SelectedItem
            $localWindowsVersion = if ($null -ne $localState.Controls.cmbWindowsVersion -and $null -ne $localState.Controls.cmbWindowsVersion.SelectedItem) { $localState.Controls.cmbWindowsVersion.SelectedItem } else { $null }
            $coreStaticVars = Get-CoreStaticVariables
            $localHeaders = $coreStaticVars.Headers
            $localUserAgent = $coreStaticVars.UserAgent
            $compressDrivers = $localState.Controls.chkCompressDriversToWIM.IsChecked

            $localState.Controls.txtStatus.Text = "Processing all selected drivers..."
            WriteLog "Processing all selected drivers: $($selectedDrivers.Model -join ', ')"

            $taskArguments = @{
                DriversFolder  = $localDriversFolder
                WindowsRelease = $localWindowsRelease
                WindowsArch    = $localWindowsArch
                WindowsVersion = $localWindowsVersion
                Headers        = $localHeaders
                UserAgent      = $localUserAgent
                CompressToWim  = $compressDrivers
            }

            Invoke-ParallelProcessing -ItemsToProcess $selectedDrivers `
                -ListViewControl $localState.Controls.lstDriverModels `
                -IdentifierProperty 'Model' `
                -StatusProperty 'DownloadStatus' `
                -TaskType 'DownloadDriverByMake' `
                -TaskArguments $taskArguments `
                -CompletedStatusText 'Completed' `
                -ErrorStatusPrefix 'Error: ' `
                -WindowObject $window `
                -MainThreadLogPath $localState.LogFilePath

            $overallSuccess = $true
            # Check if any item has an error status after processing
            # We iterate over $localState.Controls.lstDriverModels.Items because their DownloadStatus property was updated by Invoke-ParallelProcessing
            foreach ($item in ($localState.Controls.lstDriverModels.Items | Where-Object { $_.IsSelected })) {
                # Check only originally selected items
                if ($item.DownloadStatus -like 'Error:*') {
                    $overallSuccess = $false
                    WriteLog "Error detected for model $($item.Model) (Make: $($item.Make)): $($item.DownloadStatus)"
                    # No break here, log all errors
                }
            }

            $localState.Controls.pbOverallProgress.Visibility = 'Collapsed'
            $buttonSender.IsEnabled = $true
            if ($overallSuccess) {
                $localState.Controls.txtStatus.Text = "All selected driver downloads processed."
                [System.Windows.MessageBox]::Show("All selected driver downloads processed. Check status column for details.", "Download Process Finished", "OK", "Information")
            }
            else {
                $localState.Controls.txtStatus.Text = "Driver downloads processed with some errors. Check status column and log."
                [System.Windows.MessageBox]::Show("Driver downloads processed, but some errors occurred. Please check the status column for each driver and the log file for details.", "Download Process Finished with Errors", "OK", "Warning")
            }
        })

    $State.Controls.btnClearDriverList.Add_Click({
            param($eventSource, $routedEventArgs)
            $window = [System.Windows.Window]::GetWindow($eventSource)
            $localState = $window.Tag
            
            Clear-ListViewContent -State $localState `
                -ListViewControl $localState.Controls.lstDriverModels `
                -BackingDataList $localState.Data.allDriverModels `
                -ConfirmationTitle "Clear Driver List" `
                -ConfirmationMessage "Are you sure you want to clear the driver list?" `
                -StatusMessage "Driver list cleared." `
                -TextBoxesToClear @($localState.Controls.txtModelFilter)
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
}
Export-ModuleMember -Function *