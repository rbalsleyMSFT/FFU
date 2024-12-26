[CmdletBinding()]
[System.STAThread()] 
param()

# Define FFUDevelopmentPath early
if (-not $FFUDevelopmentPath) {
    $FFUDevelopmentPath = "C:\FFUDevelopment"
}

Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName PresentationCore,PresentationFramework
Add-Type -AssemblyName System.Windows.Forms  # Added to load Windows Forms for OpenFileDialog

# Define the path to the info.png image
$infoImagePath = Join-Path -Path $PSScriptRoot -ChildPath "info.png"

# Load the XAML from the external file
$xamlPath = Join-Path -Path $PSScriptRoot -ChildPath "BuildFFUVM_UI.xaml"
if (-Not (Test-Path $xamlPath)) {
    Write-Error "XAML file not found at path: $xamlPath"
    exit
}

$xamlString = Get-Content -Path $xamlPath -Raw

# Create the XmlReader
$reader = New-Object System.IO.StringReader($xamlString)
$xmlReader = [System.Xml.XmlReader]::Create($reader)

# Load the window
$window = [Windows.Markup.XamlReader]::Load($xmlReader)

# Set the Text property programmatically
$window.FindName('txtFFUName').Text = "{WindowsRelease}_{WindowsVersion}_{SKU}_{yyyy}-{MM}-{dd}_{HH}{mm}"

# Replace the dynamic SKU extraction with a static list
$skuList = @(
    'Home', 'Home N', 'Home Single Language', 'Education', 'Education N', 'Pro',
    'Pro N', 'Pro Education', 'Pro Education N', 'Pro for Workstations',
    'Pro N for Workstations', 'Enterprise', 'Enterprise N', 'Standard',
    'Standard (Desktop Experience)', 'Datacenter', 'Datacenter (Desktop Experience)'
)

# Get the ComboBox control
$cmbWindowsSKU = $window.FindName('cmbWindowsSKU')

# Clear existing items to avoid duplication when re-running the script
$cmbWindowsSKU.Items.Clear()

# Populate the ComboBox with SKUs
foreach ($sku in $skuList) {
    $cmbWindowsSKU.Items.Add($sku) | Out-Null
}

# Set default selection
if ($cmbWindowsSKU.Items.Count -gt 0) {
    $cmbWindowsSKU.SelectedIndex = 0
} else {
    Write-Host "No SKUs available to populate the ComboBox."
}

# Function to set image sources
function Set-ImageSource {
    param (
        [System.Windows.Window]$window,
        [string]$imageName,
        [string]$sourcePath
    )
    $image = $window.FindName($imageName)
    if ($image) {
        $uri = New-Object System.Uri($sourcePath, [System.UriKind]::Absolute)
        $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage($uri)
        $image.Source = $bitmap
    }
}

# List of Image control names
$imageNames = @(
    "imgFFUNameInfo",
    "imgISOPathInfo",
    "imgWindowsSKUInfo",
    "imgVMSwitchNameInfo",
    "imgVMHostIPAddressInfo",
    "imgInstallOfficeInfo",
    "imgInstallAppsInfo",
    "imgInstallDriversInfo",
    "imgCopyDriversInfo"  # Added Image control for Copy Drivers
    # Add any other Image control names here
)

# Set the Source for each Image control
foreach ($imgName in $imageNames) {
    Set-ImageSource -window $window -imageName $imgName -sourcePath $infoImagePath
}

# Optional: Add logging for debugging purposes
# Uncomment the following lines to enable debug output
# Write-Host "Extracted SKU List: $skuList"
# Write-Host "ComboBox Items Count: $($cmbWindowsSKU.Items.Count)"

# Define event handler with feedback mechanisms and error handling
$runScriptHandler = {
    try {
        # Show progress bar and update status
        $progressBar = $window.FindName('progressBar')
        $txtStatus = $window.FindName('txtStatus')
        $progressBar.Visibility = 'Visible'
        $txtStatus.Text = "Starting FFU build..."

        # Gather user inputs from controls
        $customFFUNameTemplate = $window.FindName('txtFFUName').Text
        $isoPath = $window.FindName('txtISOPath').Text
        $windowsSKU = $cmbWindowsSKU.SelectedItem
        $vmSwitchName = $cmbVMSwitchName.SelectedItem
        if ($vmSwitchName -eq 'Other') {
            $vmSwitchName = $window.FindName('txtCustomVMSwitchName').Text
        }
        $vmHostIPAddress = $window.FindName('txtVMHostIPAddress').Text
        $installOffice = $window.FindName('chkInstallOffice').IsChecked
        $installApps = $window.FindName('chkInstallApps').IsChecked
        $installDrivers = $window.FindName('chkInstallDrivers').IsChecked
        $copyDrivers = $window.FindName('chkCopyDrivers').IsChecked  # Retrieved Copy Drivers value
        $downloadDrivers = $window.FindName('chkDownloadDrivers').IsChecked
        $make = $window.FindName('cmbMake').SelectedItem
        $model = $window.FindName('cmbModel').Text  # Changed from SelectedItem
        $driversFolder = $window.FindName('txtDriversFolder').Text
        $peDriversFolder = $window.FindName('txtPEDriversFolder').Text

        # Validate required fields
        if ($installDrivers -and (-not $driversFolder)) {
            throw "Drivers Folder is required when Install Drivers is checked."
        }
        if ($copyDrivers -and (-not $driversFolder)) {
            throw "Drivers Folder is required when Copy Drivers is checked."
        }
        if ($copyPEDrivers -and (-not $peDriversFolder)) {
            throw "PE Drivers Folder is required when Copy PE Drivers is checked."
        }
        if ($downloadDrivers -and (-not $make)) {
            throw "Make is required when Download Drivers is checked."
        }
        if ($downloadDrivers -and (-not $model)) {
            throw "Model is required when Download Drivers is checked."
        }

        # Create config object
        $config = @{
            CustomFFUNameTemplate = $customFFUNameTemplate
            ISOPath = $isoPath
            WindowsSKU = $windowsSKU
            VMSwitchName = if ($cmbVMSwitchName.SelectedItem -eq 'Other') {
                $window.FindName('txtCustomVMSwitchName').Text
            } else {
                $cmbVMSwitchName.SelectedItem.ToString()  # Convert SelectedItem to string
            }
            VMHostIPAddress = $vmHostIPAddress
            InstallOffice = $installOffice
            InstallApps = $installApps
            InstallDrivers = $installDrivers
            CopyDrivers = $copyDrivers  # Added CopyDrivers to config
            DownloadDrivers = $downloadDrivers
            Make = if ($downloadDrivers) { $make.ToString() } else { $null }
            Model = if ($downloadDrivers) { $model } else { $null }  # Changed from ToString()
            DriversFolder = $driversFolder
            PEDriversFolder = $peDriversFolder
            # ...include other parameters as needed
        }

        # Serialize config to JSON
        $configJson = $config | ConvertTo-Json -Depth 10

        # Save config file
        $configFilePath = "$FFUDevelopmentPath\FFUConfig.json"
        $configJson | Set-Content -Path $configFilePath -Encoding UTF8

        # Update status
        $txtStatus.Text = "Executing BuildFFUVM script with config file..."

        # Call BuildFFUVM.ps1 with -ConfigFile
        & "$PSScriptRoot\BuildFFUVM.ps1" -ConfigFile $configFilePath -Verbose

        # Update status after successful execution
        $txtStatus.Text = "FFU build completed successfully."
    }
    catch {
        # Show error message and update status
        [System.Windows.MessageBox]::Show("An error occurred: $_", "Error", "OK", "Error")
        $txtStatus.Text = "FFU build failed."
    }
    finally {
        # Hide progress bar
        $window.FindName('progressBar').Visibility = 'Collapsed'
    }
}

# Bind the event handler once
$btnRun = $window.FindName('btnRun')
$btnRun.Add_Click($runScriptHandler)

# Bind the Browse button event handler
$btnBrowseISO = $window.FindName('btnBrowseISO')
$btnBrowseISO.Add_Click({
    $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openFileDialog.Filter = "ISO files (*.iso)|*.iso"
    $openFileDialog.Title = "Select Windows ISO File"
    
    if ($openFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $window.FindName('txtISOPath').Text = $openFileDialog.FileName
    }
})

# Bind the Browse buttons for Drivers folders
$btnBrowseDriversFolder = $window.FindName('btnBrowseDriversFolder')
$btnBrowseDriversFolder.Add_Click({
    $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderBrowser.Description = "Select Drivers Folder"
    if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $window.FindName('txtDriversFolder').Text = $folderBrowser.SelectedPath
    }
})

$btnBrowsePEDrivers = $window.FindName('btnBrowsePEDrivers')
$btnBrowsePEDrivers.Add_Click({
    $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderBrowser.Description = "Select PE Drivers Folder"
    if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $window.FindName('txtPEDriversFolder').Text = $folderBrowser.SelectedPath
    }
})

# Bind the Build Config File button event handler
$btnBuildConfig = $window.FindName('btnBuildConfig')
$btnBuildConfig.Add_Click({
    try {
        # Define default save path
        $defaultConfigPath = Join-Path -Path $FFUDevelopmentPath -ChildPath "config"

        # Ensure the config directory exists
        if (-not (Test-Path -Path $defaultConfigPath)) {
            New-Item -Path $defaultConfigPath -ItemType Directory -Force | Out-Null
        }

        # Initialize SaveFileDialog
        $saveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
        $saveFileDialog.Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*"
        $saveFileDialog.Title = "Save Configuration File"
        $saveFileDialog.InitialDirectory = $defaultConfigPath
        $saveFileDialog.FileName = "FFUConfig.json"

        # Show SaveFileDialog
        if ($saveFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $savePath = $saveFileDialog.FileName

            # Gather current configuration from UI controls using $window.FindName
            $windowsSKU = ($window.FindName('cmbWindowsSKU')).SelectedItem
            if (-not $windowsSKU) {
                throw "Windows SKU is not selected."
            }

            $selectedVMSwitch = ($window.FindName('cmbVMSwitchName')).SelectedItem
            if (-not $selectedVMSwitch) {
                throw "VM Switch Name is not selected."
            }

            if ($selectedVMSwitch -eq 'Other') {
                $vmSwitchName = ($window.FindName('txtCustomVMSwitchName')).Text
                if (-not $vmSwitchName) {
                    throw "Custom VM Switch Name is empty."
                }
            }
            else {
                $vmSwitchName = $selectedVMSwitch.ToString()
            }

            $installDrivers = ($window.FindName('chkInstallDrivers')).IsChecked
            $copyDrivers = ($window.FindName('chkCopyDrivers')).IsChecked
            $downloadDrivers = ($window.FindName('chkDownloadDrivers')).IsChecked
            $make = ($window.FindName('cmbMake')).SelectedItem
            $model = ($window.FindName('cmbModel')).Text  # Changed from SelectedItem
            $driversFolder = ($window.FindName('txtDriversFolder')).Text
            $peDriversFolder = ($window.FindName('txtPEDriversFolder')).Text

            # Validate required fields
            if ($installDrivers -and (-not $driversFolder)) {
                throw "Drivers Folder is required when Install Drivers is checked."
            }
            if ($copyDrivers -and (-not $driversFolder)) {
                throw "Drivers Folder is required when Copy Drivers is checked."
            }
            if ($copyPEDrivers -and (-not $peDriversFolder)) {
                throw "PE Drivers Folder is required when Copy PE Drivers is checked."
            }
            if ($downloadDrivers -and (-not $make)) {
                throw "Make is required when Download Drivers is checked."
            }
            if ($downloadDrivers -and (-not $model)) {
                throw "Model is required when Download Drivers is checked."
            }

            $config = @{
                CustomFFUNameTemplate = ($window.FindName('txtFFUName')).Text
                ISOPath = ($window.FindName('txtISOPath')).Text
                WindowsSKU = $windowsSKU
                VMSwitchName = $vmSwitchName
                VMHostIPAddress = ($window.FindName('txtVMHostIPAddress')).Text
                InstallOffice = ($window.FindName('chkInstallOffice')).IsChecked
                InstallApps = ($window.FindName('chkInstallApps')).IsChecked
                InstallDrivers = $installDrivers
                CopyDrivers = $copyDrivers
                DownloadDrivers = $downloadDrivers
                Make = if ($downloadDrivers) { $make.ToString() } else { $null }
                Model = if ($downloadDrivers) { $model } else { $null }  # Changed from ToString()
                DriversFolder = $driversFolder
                PEDriversFolder = $peDriversFolder
                # ...include other parameters as needed
            }

            # Serialize config to JSON
            $configJson = $config | ConvertTo-Json -Depth 10

            # Save the config file
            $configJson | Set-Content -Path $savePath -Encoding UTF8

            # Inform the user of success
            [System.Windows.MessageBox]::Show("Configuration file saved successfully to:`n$savePath", "Success", "OK", "Information")
        }
    }
    catch {
        # Show error message
        [System.Windows.MessageBox]::Show("An error occurred while saving the configuration file:`n$_", "Error", "OK", "Error")
    }
})

# After loading the window:
$window.Add_Loaded({
    $script:vmSwitchMap = @{} 
    $script:cmbVMSwitchName    = $window.FindName('cmbVMSwitchName')

    $allSwitches = Get-VMSwitch -ErrorAction SilentlyContinue
    foreach ($sw in $allSwitches) {
        $cmbVMSwitchName.Items.Add($sw.Name)
        
        # Use partial match in the NetAdapter Name
        $netAdapter = Get-NetAdapter -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "*($($sw.Name))*" }
        if ($netAdapter) {
            # Use InterfaceIndex for accurate matching
            $netIPs = Get-NetIPAddress -InterfaceIndex $netAdapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
            $validIPs = $netIPs | Where-Object { $_.IPAddress -notlike '169.254.*' -and $_.IPAddress }

            if ($validIPs) {
                $script:vmSwitchMap[$sw.Name] = ($validIPs | Select-Object -First 1).IPAddress
            }
        }
    }

    # Add "Other" option to cmbVMSwitchName
    $cmbVMSwitchName.Items.Add('Other') | Out-Null

    # Force a default selection if any items exist
    if ($cmbVMSwitchName.Items.Count -gt 0) {
        # Select the first VM Switch if available, else select 'Other'
        if ($allSwitches.Count -gt 0) {
            $cmbVMSwitchName.SelectedIndex = 0
            if ($cmbVMSwitchName.SelectedItem) {
                $preSelected = $cmbVMSwitchName.SelectedItem.ToString()  # Converted to string
                if ($script:vmSwitchMap.ContainsKey($preSelected)) {
                    $window.FindName('txtVMHostIPAddress').Text = $script:vmSwitchMap[$preSelected]
                }
                else {
                    $window.FindName('txtVMHostIPAddress').Text = ''
                }
            }
        }
        else {
            # If no VM Switches exist, select 'Other' by default
            $cmbVMSwitchName.SelectedItem = 'Other'
            $window.FindName('txtCustomVMSwitchName').Visibility = 'Visible'
        }
    }

    # Update IP on selection change using the prebuilt mapping
    $cmbVMSwitchName.Add_SelectionChanged({
        param($sender, $eventArgs)  # Define parameters for the event handler

        if ($sender.SelectedItem -eq 'Other') {
            # Show the custom VM Switch Name TextBox
            $window.FindName('txtCustomVMSwitchName').Visibility = [System.Windows.Visibility]::Visible
            
            # Optionally, clear the VM Host IP Address field
            $window.FindName('txtVMHostIPAddress').Text = ''
        }
        else {
            # Hide the custom VM Switch Name TextBox
            $window.FindName('txtCustomVMSwitchName').Visibility = [System.Windows.Visibility]::Collapsed
            
            # Update VM Host IP Address based on selection
            if ($sender.SelectedItem) {
                $selectedSwitch = $sender.SelectedItem.ToString()
                if ($script:vmSwitchMap.ContainsKey($selectedSwitch)) {
                    $ipAddress = $script:vmSwitchMap[$selectedSwitch]
                    $window.FindName('txtVMHostIPAddress').Text = $ipAddress
                }
                else {
                    $window.FindName('txtVMHostIPAddress').Text = ''
                }
            }
            else {
                $window.FindName('txtVMHostIPAddress').Text = ''
            }
        }
    })

    # Cast to WPF CheckBox and ComboBoxes
    $script:chkDownloadDrivers = [System.Windows.Controls.CheckBox]$window.FindName('chkDownloadDrivers')
    $script:cmbMake = [System.Windows.Controls.ComboBox]$window.FindName('cmbMake')
    $script:cmbModel = [System.Windows.Controls.TextBox]$window.FindName('cmbModel')  # Cast cmbModel as TextBox instead of ComboBox

    # Cast to WPF TextBlocks for label visibility
    $script:txtMakeLabel = [System.Windows.Controls.TextBlock]$window.FindName('txtMakeLabel')
    $script:txtModelLabel = [System.Windows.Controls.TextBlock]$window.FindName('txtModelLabel')

    # Set initial visibility based on the checkbox state
    if ($chkDownloadDrivers.IsChecked) {
        $script:cmbMake.Visibility = [System.Windows.Visibility]::Visible
        $script:cmbModel.Visibility = [System.Windows.Visibility]::Visible
        $script:txtMakeLabel.Visibility = [System.Windows.Visibility]::Visible
        $script:txtModelLabel.Visibility = [System.Windows.Visibility]::Visible
    }
    else {
        $script:cmbMake.Visibility = [System.Windows.Visibility]::Collapsed
        $script:cmbModel.Visibility = [System.Windows.Visibility]::Collapsed
        $script:txtMakeLabel.Visibility = [System.Windows.Visibility]::Collapsed
        $script:txtModelLabel.Visibility = [System.Windows.Visibility]::Collapsed
    }

    $chkDownloadDrivers.Add_Checked({
        $script:cmbMake.Visibility = [System.Windows.Visibility]::Visible
        $script:cmbModel.Visibility = [System.Windows.Visibility]::Visible
        $script:txtMakeLabel.Visibility = [System.Windows.Visibility]::Visible
        $script:txtModelLabel.Visibility = [System.Windows.Visibility]::Visible
    })

    $chkDownloadDrivers.Add_Unchecked({
        $script:cmbMake.Visibility = [System.Windows.Visibility]::Collapsed
        $script:cmbModel.Visibility = [System.Windows.Visibility]::Collapsed
        $script:txtMakeLabel.Visibility = [System.Windows.Visibility]::Collapsed
        $script:txtModelLabel.Visibility = [System.Windows.Visibility]::Collapsed
    })

    # Remove or comment out the ComboBox population logic for cmbModel
    # $script:cmbMake.Add_SelectionChanged({
    #     param($sender, $eventArgs)
    #
    #     $selectedMake = $sender.SelectedItem  # Changed from $sender.SelectedItem.Content
    #
    #     $script:cmbModel.Items.Clear()
    #
    #     switch ($selectedMake) {
    #         'Microsoft' {
    #             $script:cmbModel.Items.Add('Surface Pro')
    #             $script:cmbModel.Items.Add('Surface Laptop')
    #             # Add more Microsoft models
    #         }
    #         'Dell' {
    #             $script:cmbModel.Items.Add('XPS 13')
    #             $script:cmbModel.Items.Add('Inspiron 15')
    #             # Add more Dell models
    #         }
    #         'HP' {
    #             $script:cmbModel.Items.Add('Spectre x360')
    #             $script:cmbModel.Items.Add('Envy 13')
    #             # Add more HP models
    #         }
    #         'Lenovo' {
    #             $script:cmbModel.Items.Add('ThinkPad X1')
    #             $script:cmbModel.Items.Add('Yoga 7i')
    #             # Add more Lenovo models
    #         }
    #         default {
    #             # Handle unexpected Make selections
    #         }
    #     }
    # })

    # Populate cmbMake ComboBox with Make options
    $makeList = @('Microsoft', 'Dell', 'HP', 'Lenovo')  # Add more manufacturers as needed
    foreach ($make in $makeList) {
        $cmbMake.Items.Add($make) | Out-Null
    }

    if ($cmbMake.Items.Count -gt 0) {
        $cmbMake.SelectedIndex = 0
    }
})

# Show the window
[void]$window.ShowDialog()
