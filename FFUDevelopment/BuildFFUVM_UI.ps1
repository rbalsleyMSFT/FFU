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
$infoImagePath = "$PSScriptRoot\info.png"

# Replace the XAML string with one that uses ToolTips instead of Popups and adjusts their placement
$xamlString = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="FFU Builder UI"
        Height="600" Width="900">
    
    <!-- Define ToolTip Style to offset from mouse pointer -->
    <Window.Resources>
        <Style TargetType="ToolTip">
            <Setter Property="Placement" Value="Mouse"/>
            <Setter Property="HorizontalOffset" Value="10"/>
            <Setter Property="VerticalOffset" Value="-30"/> <!-- Changed from -20 to -30 -->
            <!-- Removed OverridesDefaultStyle setter to allow default ToolTip styling -->
        </Style>
    </Window.Resources>
    
    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/> <!-- New row for Custom VM Switch Name -->
        </Grid.RowDefinitions>
        <TabControl TabStripPlacement="Left" VerticalAlignment="Stretch" HorizontalAlignment="Stretch" FontSize="14" Padding="10" Grid.Row="0">
            <TabItem Header="Basic Information" Padding="20">
                <Grid Margin="10">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/> <!-- Row 0: FFU Name -->
                        <RowDefinition Height="Auto"/> <!-- Row 1: ISO Path -->
                        <RowDefinition Height="Auto"/> <!-- Row 2: Windows SKU -->
                        <RowDefinition Height="Auto"/> <!-- Row 3: VM Switch Name -->
                        <RowDefinition Height="Auto"/> <!-- Row 4: Custom VM Switch Name -->
                        <RowDefinition Height="Auto"/> <!-- Row 5: VM Host IP Address -->
                    </Grid.RowDefinitions>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="150"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>

                    <!-- FFU Name -->
                    <StackPanel Grid.Row="0" Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center" Margin="0,5">
                        <TextBlock Text="FFU Name:"/>
                        <Image x:Name="imgFFUNameInfo" Source="$infoImagePath" Width="16" Height="16" Margin="5,0,0,0" Cursor="Arrow" 
                               Focusable="True" 
                               ToolTip="Enter a unique name for the FFU. Example format: {WindowsRelease}_{WindowsVersion}_{SKU}_{yyyy}-{MM}-{dd}_{HH}{mm}" />
                    </StackPanel>
                    <TextBox x:Name="txtFFUName" Grid.Row="0" Grid.Column="1" Margin="5" VerticalAlignment="Center" HorizontalAlignment="Stretch"/>
                    
                    <!-- ISO Path -->
                    <StackPanel Grid.Row="1" Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center" Margin="0,5">
                        <TextBlock Text="ISO Path:"/>
                        <Image x:Name="imgISOPathInfo" Source="$infoImagePath" Width="16" Height="16" Margin="5,0,0,0" Cursor="Arrow" 
                               Focusable="True" 
                               ToolTip="Specify the full path to the Windows ISO file you wish to use." />
                    </StackPanel>
                    <!-- Replace StackPanel with Grid for better alignment -->
                    <Grid Grid.Row="1" Grid.Column="1" Margin="5">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*" />
                            <ColumnDefinition Width="Auto" />
                        </Grid.ColumnDefinitions>
                        <TextBox x:Name="txtISOPath" Grid.Column="0" VerticalAlignment="Center" HorizontalAlignment="Stretch" />
                        <Button x:Name="btnBrowseISO" Grid.Column="1" Content="Browse..." Width="80" Margin="5,0,0,0" VerticalAlignment="Center" ToolTip="Browse for a Windows ISO file."/>
                    </Grid>
                    
                    <!-- Windows SKU -->
                    <StackPanel Grid.Row="2" Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center" Margin="0,5">
                        <TextBlock Text="Windows SKU:"/>
                        <Image x:Name="imgWindowsSKUInfo" Source="$infoImagePath" Width="16" Height="16" Margin="5,0,0,0" Cursor="Arrow" 
                               Focusable="True" 
                               ToolTip="Select the edition of Windows you want to install (e.g., Pro, Enterprise)." />
                    </StackPanel>
                    <ComboBox x:Name="cmbWindowsSKU" Grid.Row="2" Grid.Column="1" Margin="5" VerticalAlignment="Center" HorizontalAlignment="Stretch"/>
                    
                    <!-- VM Switch Name -->
                    <StackPanel Grid.Row="3" Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center" Margin="0,5">
                        <TextBlock Text="VM Switch Name:"/>
                        <Image x:Name="imgVMSwitchNameInfo" Source="$infoImagePath" Width="16" Height="16" Margin="5,0,0,0" Cursor="Arrow" 
                               Focusable="True" 
                               ToolTip="Enter the name of the Hyper-V virtual switch to be used for the VM." />
                    </StackPanel>
                    <!-- Replace TextBox with ComboBox for listing VM Switches -->
                    <ComboBox x:Name="cmbVMSwitchName" Grid.Row="3" Grid.Column="1" Margin="5"
                              VerticalAlignment="Center" HorizontalAlignment="Stretch" />
                    <!-- Add a new TextBox for custom VM Switch Name, initially hidden -->
                    <TextBox x:Name="txtCustomVMSwitchName" Grid.Row="4" Grid.Column="1" Margin="5" 
                             VerticalAlignment="Center" HorizontalAlignment="Stretch" 
                             Visibility="Collapsed" 
                             ToolTip="Enter your custom VM Switch Name." />

                    <!-- VM Host IP Address -->
                    <StackPanel Grid.Row="5" Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center" Margin="0,5">
                        <TextBlock Text="VM Host IP Address:"/>
                        <Image x:Name="imgVMHostIPAddressInfo" Source="$infoImagePath" Width="16" Height="16" Margin="5,0,0,0" Cursor="Arrow" 
                               Focusable="True" 
                               ToolTip="Provide the IP address of the Hyper-V host machine." />
                    </StackPanel>
                    <TextBox x:Name="txtVMHostIPAddress" Grid.Row="5" Grid.Column="1" Margin="5" VerticalAlignment="Center" HorizontalAlignment="Stretch"/>
                </Grid>
            </TabItem>
            <TabItem Header="Application Information" Padding="20">
                <Grid Margin="10">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="150"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>

                    <!-- Install Office -->
                    <StackPanel Grid.Row="0" Grid.Column="0" Orientation="Horizontal" Margin="5">
                        <CheckBox x:Name="chkInstallOffice" Content="Install Office" Margin="0,0,5,0"/>
                        <Image x:Name="imgInstallOfficeInfo" Source="$infoImagePath" Width="16" Height="16" Cursor="Arrow" 
                               Focusable="True" 
                               ToolTip="Check to install Microsoft Office as part of the FFU." />
                    </StackPanel>

                    <!-- Install Apps -->
                    <StackPanel Grid.Row="1" Grid.Column="0" Orientation="Horizontal" Margin="5">
                        <CheckBox x:Name="chkInstallApps" Content="Install Apps" Margin="0,0,5,0"/>
                        <Image x:Name="imgInstallAppsInfo" Source="$infoImagePath" Width="16" Height="16" Cursor="Arrow" 
                               Focusable="True" 
                               ToolTip="Check to include additional applications in the FFU." />
                    </StackPanel>

                    <!-- Install Drivers -->
                    <StackPanel Grid.Row="2" Grid.Column="0" Orientation="Horizontal" Margin="5">
                        <CheckBox x:Name="chkInstallDrivers" Content="Install Drivers" Margin="0,0,5,0"/>
                        <Image x:Name="imgInstallDriversInfo" Source="$infoImagePath" Width="16" Height="16" Cursor="Arrow" 
                               Focusable="True" 
                               ToolTip="Check to include device drivers in the FFU." />
                    </StackPanel>
                    <!-- Add more application-related controls here using the Grid for alignment -->
                </Grid>
            </TabItem>
        </TabControl>
        
        <!-- Progress Bar -->
        <ProgressBar x:Name="progressBar" Height="20" Margin="0,10,0,0" Grid.Row="1" Visibility="Collapsed" 
        />
        
        <!-- Status Text -->
        <TextBlock x:Name="txtStatus" Grid.Row="2" Text="" Margin="0,5,0,0" 
        />
        
        <!-- Run Button Row -->
        <StackPanel Grid.Row="3" Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,0,20,20">
            <!-- New Build Config File Button -->
            <Button x:Name="btnBuildConfig" Content="Build Config File" Width="150" 
                    VerticalAlignment="Bottom" Margin="0,0,10,0" FontSize="14" Padding="10,5"/>
            
            <!-- Existing Build FFU Button -->
            <Button x:Name="btnRun" Content="Build FFU" Width="120" 
                    VerticalAlignment="Bottom" FontSize="14" Padding="10,5"/>
        </StackPanel>
    </Grid>
</Window>
"@

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
