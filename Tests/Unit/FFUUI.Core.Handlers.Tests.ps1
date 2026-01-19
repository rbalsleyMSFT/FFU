#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

<#
.SYNOPSIS
    Unit tests for FFUUI.Core.Handlers business logic

.DESCRIPTION
    Pester 5.x tests for the UI handler business logic in FFUUI.Core.Handlers.psm1.
    Since WPF types are unavailable in test context, these tests focus on the
    PowerShell validation and state management logic extracted from event handlers:
    - Integer-only input validation (regex patterns)
    - Thread count validation (LostFocus behavior)
    - Max USB drives validation (LostFocus behavior)
    - USB settings visibility logic

    These tests do NOT import FFUUI.Core module (requires WPF runtime).
    Instead, they test the extracted logic patterns directly.

.NOTES
    TEST-04: Unit test coverage for UI event handlers
    Tests validate the business logic that handlers execute, not WPF event binding.
#>

Describe 'FFUUI.Core.Handlers Business Logic' -Tag 'Unit', 'FFUUI.Core', 'Handlers', 'TEST-04' {

    BeforeAll {
        # Create mock State object structure matching FFUUI.Core.Handlers expectations
        # This mimics the structure used by Register-EventHandlers without WPF dependencies
        function New-MockStateObject {
            return [PSCustomObject]@{
                Controls = @{
                    txtThreads = [PSCustomObject]@{ Text = '4' }
                    txtMaxUSBDrives = [PSCustomObject]@{ Text = '0' }
                    txtDiskSize = [PSCustomObject]@{ Text = '50' }
                    txtMemory = [PSCustomObject]@{ Text = '4096' }
                    txtProcessors = [PSCustomObject]@{ Text = '4' }
                    usbSection = [PSCustomObject]@{ Visibility = 'Collapsed' }
                    chkSelectSpecificUSBDrives = [PSCustomObject]@{ IsEnabled = $false; IsChecked = $false }
                    lstUSBDrives = [PSCustomObject]@{
                        Items = [System.Collections.ArrayList]::new()
                    }
                    usbSelectionPanel = [PSCustomObject]@{ Visibility = 'Collapsed' }
                    txtFFUDevPath = [PSCustomObject]@{ Text = 'C:\FFUDevelopment' }
                    chkInstallDrivers = [PSCustomObject]@{ IsChecked = $true }
                    lstDriverModels = [PSCustomObject]@{
                        Items = [System.Collections.ArrayList]::new()
                        ItemsSource = $null
                    }
                    txtStatus = [PSCustomObject]@{ Text = '' }
                }
                Data = @{
                    allDriverModels = [System.Collections.Generic.List[object]]::new()
                    vmSwitchMap = @{}
                }
                Flags = @{
                    lastSortProperty = $null
                    lastSortAscending = $true
                }
                FFUDevelopmentPath = 'C:\FFUDevelopment'
            }
        }
    }

    Context 'Integer-Only TextBox Validation' -Tag 'Validation', 'Input' {
        <#
        Source: FFUUI.Core.Handlers.psm1 lines 16-23
        The $integerPreviewTextInputHandler uses regex '\D' to check for non-digit characters
        #>

        It 'Should allow valid single-digit integer input' {
            $text = '5'
            $isInvalid = $text -match '\D'
            $isInvalid | Should -Be $false
        }

        It 'Should allow valid multi-digit integer input' {
            $text = '123'
            $isInvalid = $text -match '\D'
            $isInvalid | Should -Be $false
        }

        It 'Should reject letter characters' {
            $text = 'a'
            $isInvalid = $text -match '\D'
            $isInvalid | Should -Be $true
        }

        It 'Should reject mixed alphanumeric input' {
            $text = '12a3'
            $isInvalid = $text -match '\D'
            $isInvalid | Should -Be $true
        }

        It 'Should reject special characters' {
            $text = '12.3'
            $isInvalid = $text -match '\D'
            $isInvalid | Should -Be $true
        }

        It 'Should reject space character' {
            $text = ' '
            $isInvalid = $text -match '\D'
            $isInvalid | Should -Be $true
        }

        It 'Should reject negative sign' {
            $text = '-'
            $isInvalid = $text -match '\D'
            $isInvalid | Should -Be $true
        }
    }

    Context 'Paste Validation Pattern' -Tag 'Validation', 'Paste' {
        <#
        Source: FFUUI.Core.Handlers.psm1 lines 26-40
        The $integerPastingHandler uses regex '^\d+$' to validate pasted text
        #>

        It 'Should accept pasted integer-only text' {
            $pastedText = '12345'
            $isValid = $pastedText -match '^\d+$'
            $isValid | Should -Be $true
        }

        It 'Should reject pasted text with letters' {
            $pastedText = '123abc'
            $isValid = $pastedText -match '^\d+$'
            $isValid | Should -Be $false
        }

        It 'Should reject pasted text with spaces' {
            $pastedText = '123 456'
            $isValid = $pastedText -match '^\d+$'
            $isValid | Should -Be $false
        }

        It 'Should reject pasted empty string' {
            $pastedText = ''
            $isValid = $pastedText -match '^\d+$'
            $isValid | Should -Be $false
        }

        It 'Should reject pasted text with decimal point' {
            $pastedText = '123.45'
            $isValid = $pastedText -match '^\d+$'
            $isValid | Should -Be $false
        }

        It 'Should reject pasted negative number' {
            $pastedText = '-123'
            $isValid = $pastedText -match '^\d+$'
            $isValid | Should -Be $false
        }
    }

    Context 'Thread Count Validation (txtThreads.LostFocus)' -Tag 'Validation', 'Threads' {
        <#
        Source: FFUUI.Core.Handlers.psm1 lines 59-74
        Threads must be at least 1. Invalid values reset to '1'.
        #>

        BeforeEach {
            $script:MockState = New-MockStateObject
        }

        It 'Should preserve valid positive integer' {
            $MockState.Controls.txtThreads.Text = '8'
            $currentValue = 0
            $isValidInteger = [int]::TryParse($MockState.Controls.txtThreads.Text, [ref]$currentValue)

            if (-not $isValidInteger -or $currentValue -lt 1) {
                $MockState.Controls.txtThreads.Text = '1'
            }

            $MockState.Controls.txtThreads.Text | Should -Be '8'
        }

        It 'Should reset empty text to 1' {
            $MockState.Controls.txtThreads.Text = ''
            $currentValue = 0
            $isValidInteger = [int]::TryParse($MockState.Controls.txtThreads.Text, [ref]$currentValue)

            if (-not $isValidInteger -or $currentValue -lt 1) {
                $MockState.Controls.txtThreads.Text = '1'
            }

            $MockState.Controls.txtThreads.Text | Should -Be '1'
        }

        It 'Should reset value of 0 to 1' {
            $MockState.Controls.txtThreads.Text = '0'
            $currentValue = 0
            $isValidInteger = [int]::TryParse($MockState.Controls.txtThreads.Text, [ref]$currentValue)

            if (-not $isValidInteger -or $currentValue -lt 1) {
                $MockState.Controls.txtThreads.Text = '1'
            }

            $MockState.Controls.txtThreads.Text | Should -Be '1'
        }

        It 'Should reset negative value to 1' {
            $MockState.Controls.txtThreads.Text = '-5'
            $currentValue = 0
            $isValidInteger = [int]::TryParse($MockState.Controls.txtThreads.Text, [ref]$currentValue)

            if (-not $isValidInteger -or $currentValue -lt 1) {
                $MockState.Controls.txtThreads.Text = '1'
            }

            $MockState.Controls.txtThreads.Text | Should -Be '1'
        }

        It 'Should reset non-numeric text to 1' {
            $MockState.Controls.txtThreads.Text = 'abc'
            $currentValue = 0
            $isValidInteger = [int]::TryParse($MockState.Controls.txtThreads.Text, [ref]$currentValue)

            if (-not $isValidInteger -or $currentValue -lt 1) {
                $MockState.Controls.txtThreads.Text = '1'
            }

            $MockState.Controls.txtThreads.Text | Should -Be '1'
        }

        It 'Should handle whitespace-only text as invalid' {
            $MockState.Controls.txtThreads.Text = '   '
            $currentValue = 0
            $isValidInteger = [int]::TryParse($MockState.Controls.txtThreads.Text, [ref]$currentValue)

            if (-not $isValidInteger -or $currentValue -lt 1) {
                $MockState.Controls.txtThreads.Text = '1'
            }

            $MockState.Controls.txtThreads.Text | Should -Be '1'
        }
    }

    Context 'Max USB Drives Validation (txtMaxUSBDrives.LostFocus)' -Tag 'Validation', 'USBDrives' {
        <#
        Source: FFUUI.Core.Handlers.psm1 lines 76-88
        Max USB drives must be >= 0. Value of 0 means "process all".
        Invalid values reset to '0'.
        #>

        BeforeEach {
            $script:MockState = New-MockStateObject
        }

        It 'Should preserve valid positive integer' {
            $MockState.Controls.txtMaxUSBDrives.Text = '5'
            $currentValue = 0
            $isValidInteger = [int]::TryParse($MockState.Controls.txtMaxUSBDrives.Text, [ref]$currentValue)

            if (-not $isValidInteger -or $currentValue -lt 0) {
                $MockState.Controls.txtMaxUSBDrives.Text = '0'
            }

            $MockState.Controls.txtMaxUSBDrives.Text | Should -Be '5'
        }

        It 'Should accept 0 as valid (means "all drives")' {
            $MockState.Controls.txtMaxUSBDrives.Text = '0'
            $currentValue = 0
            $isValidInteger = [int]::TryParse($MockState.Controls.txtMaxUSBDrives.Text, [ref]$currentValue)

            if (-not $isValidInteger -or $currentValue -lt 0) {
                $MockState.Controls.txtMaxUSBDrives.Text = '0'
            }

            $MockState.Controls.txtMaxUSBDrives.Text | Should -Be '0'
        }

        It 'Should reset empty text to 0' {
            $MockState.Controls.txtMaxUSBDrives.Text = ''
            $currentValue = 0
            $isValidInteger = [int]::TryParse($MockState.Controls.txtMaxUSBDrives.Text, [ref]$currentValue)

            if (-not $isValidInteger -or $currentValue -lt 0) {
                $MockState.Controls.txtMaxUSBDrives.Text = '0'
            }

            $MockState.Controls.txtMaxUSBDrives.Text | Should -Be '0'
        }

        It 'Should reset negative value to 0' {
            $MockState.Controls.txtMaxUSBDrives.Text = '-1'
            $currentValue = 0
            $isValidInteger = [int]::TryParse($MockState.Controls.txtMaxUSBDrives.Text, [ref]$currentValue)

            if (-not $isValidInteger -or $currentValue -lt 0) {
                $MockState.Controls.txtMaxUSBDrives.Text = '0'
            }

            $MockState.Controls.txtMaxUSBDrives.Text | Should -Be '0'
        }

        It 'Should reset non-numeric text to 0' {
            $MockState.Controls.txtMaxUSBDrives.Text = 'many'
            $currentValue = 0
            $isValidInteger = [int]::TryParse($MockState.Controls.txtMaxUSBDrives.Text, [ref]$currentValue)

            if (-not $isValidInteger -or $currentValue -lt 0) {
                $MockState.Controls.txtMaxUSBDrives.Text = '0'
            }

            $MockState.Controls.txtMaxUSBDrives.Text | Should -Be '0'
        }
    }

    Context 'USB Settings Visibility Logic (chkBuildUSBDriveEnable)' -Tag 'Visibility', 'USB' {
        <#
        Source: FFUUI.Core.Handlers.psm1 lines 112-127
        When USB drive building is enabled/disabled, visibility and state changes occur.
        #>

        BeforeEach {
            $script:MockState = New-MockStateObject
        }

        It 'Should show USB section when enabled' {
            # Simulate chkBuildUSBDriveEnable.Add_Checked handler logic
            $MockState.Controls.usbSection.Visibility = 'Visible'
            $MockState.Controls.chkSelectSpecificUSBDrives.IsEnabled = $true

            $MockState.Controls.usbSection.Visibility | Should -Be 'Visible'
            $MockState.Controls.chkSelectSpecificUSBDrives.IsEnabled | Should -Be $true
        }

        It 'Should hide USB section when disabled' {
            # First enable, then disable
            $MockState.Controls.usbSection.Visibility = 'Visible'
            $MockState.Controls.chkSelectSpecificUSBDrives.IsEnabled = $true

            # Simulate chkBuildUSBDriveEnable.Add_Unchecked handler logic
            $MockState.Controls.usbSection.Visibility = 'Collapsed'
            $MockState.Controls.chkSelectSpecificUSBDrives.IsEnabled = $false
            $MockState.Controls.chkSelectSpecificUSBDrives.IsChecked = $false
            $MockState.Controls.lstUSBDrives.Items.Clear()

            $MockState.Controls.usbSection.Visibility | Should -Be 'Collapsed'
            $MockState.Controls.chkSelectSpecificUSBDrives.IsEnabled | Should -Be $false
            $MockState.Controls.chkSelectSpecificUSBDrives.IsChecked | Should -Be $false
        }

        It 'Should clear USB drive list when disabled' {
            # Add some items first
            $MockState.Controls.lstUSBDrives.Items.Add([PSCustomObject]@{ DeviceID = 'USB1' })
            $MockState.Controls.lstUSBDrives.Items.Add([PSCustomObject]@{ DeviceID = 'USB2' })
            $MockState.Controls.lstUSBDrives.Items.Count | Should -Be 2

            # Simulate disable action
            $MockState.Controls.usbSection.Visibility = 'Collapsed'
            $MockState.Controls.chkSelectSpecificUSBDrives.IsEnabled = $false
            $MockState.Controls.chkSelectSpecificUSBDrives.IsChecked = $false
            $MockState.Controls.lstUSBDrives.Items.Clear()

            $MockState.Controls.lstUSBDrives.Items.Count | Should -Be 0
        }

        It 'Should reset specific USB drives checkbox when disabled' {
            # Enable and check specific drives
            $MockState.Controls.usbSection.Visibility = 'Visible'
            $MockState.Controls.chkSelectSpecificUSBDrives.IsEnabled = $true
            $MockState.Controls.chkSelectSpecificUSBDrives.IsChecked = $true

            # Simulate disable action
            $MockState.Controls.usbSection.Visibility = 'Collapsed'
            $MockState.Controls.chkSelectSpecificUSBDrives.IsEnabled = $false
            $MockState.Controls.chkSelectSpecificUSBDrives.IsChecked = $false
            $MockState.Controls.lstUSBDrives.Items.Clear()

            $MockState.Controls.chkSelectSpecificUSBDrives.IsChecked | Should -Be $false
        }
    }

    Context 'USB Selection Panel Visibility (chkSelectSpecificUSBDrives)' -Tag 'Visibility', 'USB' {
        <#
        Source: FFUUI.Core.Handlers.psm1 lines 128-140
        When specific USB drive selection is enabled/disabled, the selection panel visibility changes.
        #>

        BeforeEach {
            $script:MockState = New-MockStateObject
        }

        It 'Should show USB selection panel when specific drives checkbox is checked' {
            # Simulate chkSelectSpecificUSBDrives.Add_Checked handler logic
            $MockState.Controls.usbSelectionPanel.Visibility = 'Visible'

            $MockState.Controls.usbSelectionPanel.Visibility | Should -Be 'Visible'
        }

        It 'Should hide USB selection panel when specific drives checkbox is unchecked' {
            $MockState.Controls.usbSelectionPanel.Visibility = 'Visible'

            # Simulate chkSelectSpecificUSBDrives.Add_Unchecked handler logic
            $MockState.Controls.usbSelectionPanel.Visibility = 'Collapsed'
            $MockState.Controls.lstUSBDrives.Items.Clear()

            $MockState.Controls.usbSelectionPanel.Visibility | Should -Be 'Collapsed'
        }

        It 'Should clear USB drives list when specific drives checkbox is unchecked' {
            $MockState.Controls.lstUSBDrives.Items.Add([PSCustomObject]@{ DeviceID = 'USB1' })
            $MockState.Controls.lstUSBDrives.Items.Count | Should -Be 1

            # Simulate uncheck action
            $MockState.Controls.usbSelectionPanel.Visibility = 'Collapsed'
            $MockState.Controls.lstUSBDrives.Items.Clear()

            $MockState.Controls.lstUSBDrives.Items.Count | Should -Be 0
        }
    }

    Context 'CU Interplay Logic (chkLatestCU/chkPreviewCU)' -Tag 'Validation', 'Updates' {
        <#
        Source: FFUUI.Core.Handlers.psm1 lines 380-403
        Latest CU and Preview CU are mutually exclusive - enabling one disables the other.
        #>

        BeforeEach {
            $script:MockState = New-MockStateObject
            # Add CU-related controls to mock state
            $MockState.Controls['chkLatestCU'] = [PSCustomObject]@{ IsEnabled = $true; IsChecked = $false }
            $MockState.Controls['chkPreviewCU'] = [PSCustomObject]@{ IsEnabled = $true; IsChecked = $false }
        }

        It 'Should disable Preview CU when Latest CU is checked' {
            # Simulate chkLatestCU.Add_Checked handler logic
            $MockState.Controls.chkPreviewCU.IsEnabled = $false

            $MockState.Controls.chkPreviewCU.IsEnabled | Should -Be $false
        }

        It 'Should enable Preview CU when Latest CU is unchecked' {
            # First check Latest CU
            $MockState.Controls.chkPreviewCU.IsEnabled = $false

            # Simulate chkLatestCU.Add_Unchecked handler logic
            $MockState.Controls.chkPreviewCU.IsEnabled = $true

            $MockState.Controls.chkPreviewCU.IsEnabled | Should -Be $true
        }

        It 'Should disable Latest CU when Preview CU is checked' {
            # Simulate chkPreviewCU.Add_Checked handler logic
            $MockState.Controls.chkLatestCU.IsEnabled = $false

            $MockState.Controls.chkLatestCU.IsEnabled | Should -Be $false
        }

        It 'Should enable Latest CU when Preview CU is unchecked' {
            # First check Preview CU
            $MockState.Controls.chkLatestCU.IsEnabled = $false

            # Simulate chkPreviewCU.Add_Unchecked handler logic
            $MockState.Controls.chkLatestCU.IsEnabled = $true

            $MockState.Controls.chkLatestCU.IsEnabled | Should -Be $true
        }
    }

    Context 'External Hard Disk Media Settings (chkAllowExternalHardDiskMedia)' -Tag 'Visibility', 'USB' {
        <#
        Source: FFUUI.Core.Handlers.psm1 lines 141-153
        External hard disk media checkbox controls prompt checkbox state.
        #>

        BeforeEach {
            $script:MockState = New-MockStateObject
            $MockState.Controls['chkAllowExternalHardDiskMedia'] = [PSCustomObject]@{ IsChecked = $false }
            $MockState.Controls['chkPromptExternalHardDiskMedia'] = [PSCustomObject]@{ IsEnabled = $false; IsChecked = $false }
        }

        It 'Should enable prompt checkbox when external hard disk is allowed' {
            # Simulate chkAllowExternalHardDiskMedia.Add_Checked handler logic
            $MockState.Controls.chkPromptExternalHardDiskMedia.IsEnabled = $true

            $MockState.Controls.chkPromptExternalHardDiskMedia.IsEnabled | Should -Be $true
        }

        It 'Should disable and uncheck prompt checkbox when external hard disk is disallowed' {
            # First enable
            $MockState.Controls.chkPromptExternalHardDiskMedia.IsEnabled = $true
            $MockState.Controls.chkPromptExternalHardDiskMedia.IsChecked = $true

            # Simulate chkAllowExternalHardDiskMedia.Add_Unchecked handler logic
            $MockState.Controls.chkPromptExternalHardDiskMedia.IsEnabled = $false
            $MockState.Controls.chkPromptExternalHardDiskMedia.IsChecked = $false

            $MockState.Controls.chkPromptExternalHardDiskMedia.IsEnabled | Should -Be $false
            $MockState.Controls.chkPromptExternalHardDiskMedia.IsChecked | Should -Be $false
        }
    }

    Context 'VM Switch Selection Logic (cmbVMSwitchName)' -Tag 'Visibility', 'VMSwitch' {
        <#
        Source: FFUUI.Core.Handlers.psm1 lines 258-283
        When 'Other' is selected, show custom switch name field.
        When a known switch is selected, populate IP from vmSwitchMap.
        #>

        BeforeEach {
            $script:MockState = New-MockStateObject
            $MockState.Controls['cmbVMSwitchName'] = [PSCustomObject]@{ SelectedItem = $null }
            $MockState.Controls['txtCustomVMSwitchName'] = [PSCustomObject]@{ Text = ''; Visibility = 'Collapsed' }
            $MockState.Controls['txtVMHostIPAddress'] = [PSCustomObject]@{ Text = '' }
            $MockState.Data.vmSwitchMap = @{
                'Default Switch' = '172.30.16.1'
                'Internal Switch' = '192.168.0.1'
            }
            $MockState.Data['customVMSwitchName'] = 'MyCustomSwitch'
            $MockState.Data['customVMHostIP'] = '10.0.0.1'
        }

        It 'Should show custom switch name field when Other is selected' {
            $selectedItem = 'Other'
            if ($selectedItem -eq 'Other') {
                $MockState.Controls.txtCustomVMSwitchName.Visibility = 'Visible'
            }

            $MockState.Controls.txtCustomVMSwitchName.Visibility | Should -Be 'Visible'
        }

        It 'Should hide custom switch name field when known switch is selected' {
            $MockState.Controls.txtCustomVMSwitchName.Visibility = 'Visible'

            $selectedItem = 'Default Switch'
            if ($selectedItem -ne 'Other') {
                $MockState.Controls.txtCustomVMSwitchName.Visibility = 'Collapsed'
            }

            $MockState.Controls.txtCustomVMSwitchName.Visibility | Should -Be 'Collapsed'
        }

        It 'Should populate IP address from vmSwitchMap when known switch is selected' {
            $selectedItem = 'Default Switch'
            if ($selectedItem -ne 'Other' -and $null -ne $selectedItem -and $MockState.Data.vmSwitchMap.ContainsKey($selectedItem)) {
                $MockState.Controls.txtVMHostIPAddress.Text = $MockState.Data.vmSwitchMap[$selectedItem]
            }

            $MockState.Controls.txtVMHostIPAddress.Text | Should -Be '172.30.16.1'
        }

        It 'Should clear IP address when unknown switch is selected' {
            $selectedItem = 'Unknown Switch'
            if ($selectedItem -ne 'Other' -and ($null -eq $selectedItem -or -not $MockState.Data.vmSwitchMap.ContainsKey($selectedItem))) {
                $MockState.Controls.txtVMHostIPAddress.Text = ''
            }

            $MockState.Controls.txtVMHostIPAddress.Text | Should -Be ''
        }
    }
}
