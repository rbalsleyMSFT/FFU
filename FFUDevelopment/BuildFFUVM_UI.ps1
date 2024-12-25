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

            $config = @{
                CustomFFUNameTemplate = ($window.FindName('txtFFUName')).Text
                ISOPath = ($window.FindName('txtISOPath')).Text
                WindowsSKU = $windowsSKU
                VMSwitchName = $vmSwitchName
                VMHostIPAddress = ($window.FindName('txtVMHostIPAddress')).Text
                InstallOffice = ($window.FindName('chkInstallOffice')).IsChecked
                InstallApps = ($window.FindName('chkInstallApps')).IsChecked
                InstallDrivers = ($window.FindName('chkInstallDrivers')).IsChecked
                CopyDrivers = ($window.FindName('chkCopyDrivers')).IsChecked  # Added CopyDrivers to config
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
    $cmbVMSwitchName    = $window.FindName('cmbVMSwitchName')

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
            $window.FindName('txtCustomVMSwitchName').Visibility = 'Visible'
            
            # Optionally, clear the VM Host IP Address field
            $window.FindName('txtVMHostIPAddress').Text = ''
        }
        else {
            # Hide the custom VM Switch Name TextBox
            $window.FindName('txtCustomVMSwitchName').Visibility = 'Collapsed'
            
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
})

# Show the window
[void]$window.ShowDialog()
