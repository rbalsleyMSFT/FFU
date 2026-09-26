<#
.SYNOPSIS
    Manages all Winget-related functionality for the 'Applications' tab in the FFU Builder UI.
.DESCRIPTION
    This module provides the business logic for interacting with Winget from the FFU Builder UI. It includes functions for searching for packages, importing and exporting application lists, checking for and installing necessary Winget components (CLI and PowerShell module), and managing the parallel download of selected applications. It works in conjunction with FFU.Common.Winget for lower-level operations and FFU.Common.Parallel for managing concurrent downloads.
#>

# Function to search for Winget apps
function Search-WingetApps {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$State
    )

    $searchQuery = $State.Controls.txtWingetSearch.Text
    if ([string]::IsNullOrWhiteSpace($searchQuery)) { return }
	if ($State.Flags.wingetBusy) {
		$State.Controls.txtStatus.Text = 'Wait for the current WinGet operation to finish.'
		WriteLog $State.Controls.txtStatus.Text
		return
	}

    $State.Controls.txtStatus.Text = "Searching Winget for apps matching query '$searchQuery'..."
    $State.Window.Cursor = [System.Windows.Input.Cursors]::Wait
    $State.Controls.btnWingetSearch.IsEnabled = $false

    try {
		$State.Flags.wingetBusy = $true
		$State.Data.wingetComponentStatus = Get-WinGetComponentStatus
		if ($State.Flags.wingetRestartRequired) {
			throw 'Save your work and restart FFU/PowerShell before using the updated WinGet module.'
		}
		if (-not $State.Data.wingetComponentStatus.Success) {
			throw $State.Data.wingetComponentStatus.ErrorMessage
		}
		Update-WingetVersionFields -State $State

        # Get current items from the ListView
        $currentItemsInListView = @()
        if ($null -ne $State.Controls.lstWingetResults.ItemsSource) {
            $currentItemsInListView = @($State.Controls.lstWingetResults.ItemsSource)
        }
        elseif ($State.Controls.lstWingetResults.HasItems) {
            $currentItemsInListView = @($State.Controls.lstWingetResults.Items)
        }

        # Store selected apps from the current view
        $selectedAppsFromView = @($currentItemsInListView | Where-Object { $_.IsSelected })

        # Get default architecture from the UI
        $defaultArch = $State.Controls.cmbWindowsArch.SelectedItem

        # Search for new apps, which are streamed directly as PSCustomObjects
        # with the required properties for performance.
        $searchedAppResults = Search-WingetPackagesPublic -Query $searchQuery -DefaultArchitecture $defaultArch
        $finalAppList = [System.Collections.Generic.List[object]]::new()
        $addedAppIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

        # Add previously selected apps first
        foreach ($app in $selectedAppsFromView) {
            $finalAppList.Add($app)
            $addedAppIds.Add($app.Id) | Out-Null
        }

        # Add new search results, avoiding duplicates of already added (selected) apps
        $newAppsAddedCount = 0
        foreach ($result in $searchedAppResults) {
            # HashSet.Add returns $true if the item was added, $false if it already existed.
            if ($addedAppIds.Add($result.Id)) {
                $finalAppList.Add($result)
                $newAppsAddedCount++
            }
        }

        # Update the ListView's ItemsSource using the passed-in State object
        $State.Controls.lstWingetResults.ItemsSource = $finalAppList.ToArray()
        Request-ListViewColumnAutoResize -ListView $State.Controls.lstWingetResults

        # Update status text
        $statusText = ""
        if ($newAppsAddedCount -gt 0) {
            $statusText = "Found $newAppsAddedCount new applications. "
        }
        else {
            $statusText = "No new applications found. "
        }
        $statusText += "Displaying $($finalAppList.Count) total applications."
        $State.Controls.txtStatus.Text = $statusText
    }
    catch {
        $errorMessage = "Error searching for apps: $($_.Exception.Message)"
		WriteLog $errorMessage
        $State.Controls.txtStatus.Text = $errorMessage
        [System.Windows.MessageBox]::Show($errorMessage, "Error", "OK", "Error")
    }
    finally {
		$State.Flags.wingetBusy = $false
        $State.Window.Cursor = $null
		Update-WingetVersionFields -State $State
    }
}

# Function to save selected apps to JSON
function Save-WingetList {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$State
    )
    try {
        $selectedApps = $State.Controls.lstWingetResults.Items | Where-Object { $_.IsSelected }
        if (-not $selectedApps) {
            [System.Windows.MessageBox]::Show("No apps selected to save.", "Warning", "OK", "Warning")
            return
        }

        $appList = @{
            apps = @($selectedApps | ForEach-Object {
                    [ordered]@{
                        name                   = (ConvertTo-SafeName -Name $_.Name)
                        id                     = $_.Id
                        source                 = $_.Source.ToLower()
                        architecture           = $_.Architecture
                        AdditionalExitCodes    = if ($_.PSObject.Properties['AdditionalExitCodes']) { $_.AdditionalExitCodes } else { "" }
                        IgnoreNonZeroExitCodes = if ($_.PSObject.Properties['IgnoreNonZeroExitCodes']) { [bool]$_.IgnoreNonZeroExitCodes } else { $false }
                    }
                })
        }

        # Default the save dialog to the configured Winget app list path.
        $currentPath = $State.Controls.txtAppListJsonPath.Text
        $initialDirectory = if (-not [string]::IsNullOrWhiteSpace($currentPath)) { Split-Path -Path $currentPath -Parent } else { $State.Controls.txtApplicationPath.Text }
        if ([string]::IsNullOrWhiteSpace($initialDirectory) -or -not (Test-Path -Path $initialDirectory -PathType Container)) {
            $initialDirectory = $State.Controls.txtApplicationPath.Text
        }
        $fileName = if (-not [string]::IsNullOrWhiteSpace($currentPath)) { Split-Path -Path $currentPath -Leaf } else { "AppList.json" }

        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Filter = "JSON files (*.json)|*.json"
        $sfd.Title = "Save Winget App List"
        $sfd.InitialDirectory = $initialDirectory
        $sfd.FileName = $fileName

        if ($sfd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $appList | ConvertTo-Json -Depth 10 | Set-Content $sfd.FileName -Encoding UTF8
            $State.Controls.txtAppListJsonPath.Text = $sfd.FileName
            [System.Windows.MessageBox]::Show("Winget app list saved successfully.", "Success", "OK", "Information")
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Error saving Winget app list: $_", "Error", "OK", "Error")
    }
}

# Function to import app list from JSON
function Import-WingetList {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$State
    )
    try {
        # Default the import dialog to the configured Winget app list path.
        $currentPath = $State.Controls.txtAppListJsonPath.Text
        $initialDirectory = if (-not [string]::IsNullOrWhiteSpace($currentPath)) { Split-Path -Path $currentPath -Parent } else { $State.Controls.txtApplicationPath.Text }
        if ([string]::IsNullOrWhiteSpace($initialDirectory) -or -not (Test-Path -Path $initialDirectory -PathType Container)) {
            $initialDirectory = $State.Controls.txtApplicationPath.Text
        }

        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Filter = "JSON files (*.json)|*.json"
        $ofd.Title = "Import Winget App List"
        $ofd.InitialDirectory = $initialDirectory

        if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $importedAppsData = Get-Content $ofd.FileName -Raw | ConvertFrom-Json

            $newAppListForItemsSource = [System.Collections.Generic.List[object]]::new()

            if ($null -ne $importedAppsData.apps) {
                # Get default architecture from the UI for fallback.
                $defaultArch = $State.Controls.cmbWindowsArch.SelectedItem

                foreach ($appInfo in $importedAppsData.apps) {
                    $arch = if ($appInfo.source -eq 'msstore') { 'NA' } else { if ($appInfo.PSObject.Properties['architecture']) { $appInfo.architecture } else { $defaultArch } }
                    $newAppListForItemsSource.Add([PSCustomObject]@{
                            IsSelected               = $true
                            Name                     = $appInfo.name
                            Id                       = $appInfo.id
                            Version                  = ""
                            Source                   = $appInfo.source
                            Architecture             = $arch
                            AdditionalExitCodes      = if ($appInfo.PSObject.Properties['AdditionalExitCodes']) { $appInfo.AdditionalExitCodes } else { "" }
                            IgnoreNonZeroExitCodes   = if ($appInfo.PSObject.Properties['IgnoreNonZeroExitCodes']) { [bool]$appInfo.IgnoreNonZeroExitCodes } else { $false }
                            DownloadStatus           = ""
                        })
                }
            }

            $State.Controls.lstWingetResults.ItemsSource = $newAppListForItemsSource.ToArray()
            Request-ListViewColumnAutoResize -ListView $State.Controls.lstWingetResults
            $State.Controls.txtAppListJsonPath.Text = $ofd.FileName

            [System.Windows.MessageBox]::Show("Winget app list imported successfully.", "Success", "OK", "Information")
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Error importing Winget app list: $_", "Error", "OK", "Error")
    }
}

# --------------------------------------------------------------------------
# SECTION: Winget Management Functions (Moved from FFUUI.Core.psm1)
# --------------------------------------------------------------------------
function Search-WingetPackagesPublic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query,
        [Parameter(Mandatory = $true)]
        [string]$DefaultArchitecture
    )

    WriteLog "Searching Winget packages with query: '$Query'"
    try {
		Confirm-WinGetInstallation -WindowsArch $DefaultArchitecture
        # Using ForEach-Object -Parallel can speed up object creation on multi-core systems
        # by distributing the work across multiple threads.
        $results = Microsoft.WinGet.Client\Find-WinGetPackage -Query $Query -ErrorAction Stop
        WriteLog "Found $($results.Count) packages matching query '$Query'."
        WriteLog "Creating output objects for Winget search results, please wait..."
        $output = $results | ForEach-Object -Parallel {
            $arch = if ($_.Source -eq 'msstore') { 'NA' } else { $using:DefaultArchitecture }
            [PSCustomObject]@{
                IsSelected               = [bool]$false
                Name                     = [string]$_.Name
                Id                       = [string]$_.Id
                Version                  = [string]$_.Version
                Source                   = [string]$_.Source
                Architecture             = [string]$arch
                AdditionalExitCodes      = [string]::Empty
                IgnoreNonZeroExitCodes   = [bool]$false
                DownloadStatus           = [string]::Empty
            }
        } -ThrottleLimit 20
        WriteLog "Winget search completed. Created $($output.Count) output objects."
        return $output
    }
    catch {
        WriteLog "Error during Winget search: $($_.Exception.Message)"
		throw
    }
}

function Get-WingetUpdateOptions {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[psobject]$Status,
		[psobject]$Updates
	)

	$cliUpdate = $null -ne $Updates -and $null -ne $Updates.WinGetVersionObject -and (-not $Status.WinGetInstalled -or $Updates.WinGetVersionObject -gt $Status.WinGetVersionObject)
	$moduleUpdate = $null -ne $Updates -and $null -ne $Updates.ModuleVersionObject -and (-not $Status.ModuleInstalled -or $Updates.ModuleVersionObject -gt $Status.ModuleVersionObject)
	$cliTarget = if ($cliUpdate) { $Updates.WinGetVersionObject } else { $Status.WinGetVersionObject }
	$moduleTarget = if ($moduleUpdate) { $Updates.ModuleVersionObject } else { $Status.ModuleVersionObject }
	$requiredModuleVersion = Get-WinGetRequiredModuleVersion -WinGetVersion $cliTarget
	return [pscustomobject]@{
		CliAvailable = $cliUpdate
		ModuleAvailable = $moduleUpdate
		CliTarget = $cliTarget
		ModuleTarget = $moduleTarget
		RequiredModuleVersion = $requiredModuleVersion
		CanUpdateCli = $cliUpdate -and $Status.ModuleInstalled -and -not $Status.ModuleNeedsUpdate -and $Status.ModuleVersionObject -ge $requiredModuleVersion -and $Updates.WinGetVersionObject -ge $Status.RequiredWinGetVersion
		CanUpdateModule = $moduleUpdate -and $Status.WinGetInstalled -and $Updates.ModuleVersionObject -ge $Status.RequiredModuleVersion -and $Status.WinGetVersionObject -ge $Updates.ModuleVersionObject
		CanUpdateBoth = $cliUpdate -and $moduleUpdate -and $moduleTarget -ge $requiredModuleVersion -and $cliTarget -ge $moduleTarget
	}
}

function Show-WingetUpdateDialog {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[psobject]$State,
		[Parameter(Mandatory)]
		[psobject]$UpdateOptions
	)

	$dialogXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
	xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
	Title="Update WinGet" Width="520" SizeToContent="Height" ResizeMode="NoResize"
	WindowStartupLocation="CenterOwner" ShowInTaskbar="False">
	<StackPanel Margin="24">
		<TextBlock Text="Choose what to update" FontSize="18" FontWeight="SemiBold" Margin="0,0,0,12"/>
		<TextBlock x:Name="txtUpdateVersions" TextWrapping="Wrap" Margin="0,0,0,16"/>
		<RadioButton x:Name="rbUpdateBoth" Content="Update both" Tag="Both" GroupName="WinGetUpdates" Margin="0,0,0,8"/>
		<RadioButton x:Name="rbUpdateCli" Content="CLI only" Tag="CLI" GroupName="WinGetUpdates" Margin="0,0,0,8"/>
		<RadioButton x:Name="rbUpdateModule" Content="Module only" Tag="Module" GroupName="WinGetUpdates" Margin="0,0,0,16"/>
		<TextBlock x:Name="txtUpdateGuidance" TextWrapping="Wrap" Margin="0,0,0,12"/>
		<TextBlock Text="Updating a module already in use requires restarting FFU/PowerShell." TextWrapping="Wrap" Margin="0,0,0,20"/>
		<StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
			<Button x:Name="btnConfirmUpdate" Content="Update" IsDefault="True" MinWidth="90" Padding="12,4" Margin="0,0,8,0"/>
			<Button Content="Cancel" IsCancel="True" MinWidth="90" Padding="12,4"/>
		</StackPanel>
	</StackPanel>
</Window>
'@
	$dialog = [System.Windows.Markup.XamlReader]::Parse($dialogXaml)
	Initialize-FFUDialog -Dialog $dialog -Owner $State.Window

	$status = $State.Data.wingetComponentStatus
	$updates = $State.Data.wingetAvailableUpdates
	$dialog.FindName('txtUpdateVersions').Text = "WinGet CLI: $($status.WinGetVersion) -> $($updates.WinGetVersion)`nMicrosoft.WinGet.Client: $($status.ModuleVersion) -> $($updates.ModuleVersion)"
	$dialog.FindName('rbUpdateBoth').IsEnabled = $UpdateOptions.CanUpdateBoth
	$dialog.FindName('rbUpdateCli').IsEnabled = $UpdateOptions.CanUpdateCli
	$dialog.FindName('rbUpdateModule').IsEnabled = $UpdateOptions.CanUpdateModule
	$defaultChoice = if ($UpdateOptions.CanUpdateBoth) { 'rbUpdateBoth' } elseif ($UpdateOptions.CanUpdateCli) { 'rbUpdateCli' } elseif ($UpdateOptions.CanUpdateModule) { 'rbUpdateModule' }
	if ($null -eq $defaultChoice) {
		throw 'No compatible WinGet update selection is available.'
	}
	$dialog.FindName($defaultChoice).IsChecked = $true
	$guidance = if (-not $UpdateOptions.CanUpdateBoth) {
		if ($UpdateOptions.CanUpdateCli) {
			'The available CLI cannot support the new module yet. You can update the CLI only and leave the module unchanged.'
		}
		else {
			'The available module cannot support the new CLI yet. You can update the module only and leave the CLI unchanged.'
		}
	}
	elseif (-not $UpdateOptions.CanUpdateCli -and -not $UpdateOptions.CanUpdateModule) {
		"The CLI update requires module $($UpdateOptions.RequiredModuleVersion) or later, and the module update requires CLI $($updates.ModuleVersion) or later. Choose Update both."
	}
	elseif (-not $UpdateOptions.CanUpdateCli) {
		"CLI only requires module $($UpdateOptions.RequiredModuleVersion) or later. Choose Update both or update the module first."
	}
	elseif (-not $UpdateOptions.CanUpdateModule) {
		"Module only requires CLI $($updates.ModuleVersion) or later. Choose Update both to update the CLI first."
	}
	else {
		''
	}
	$dialog.FindName('txtUpdateGuidance').Text = $guidance
	$dialog.FindName('txtUpdateGuidance').Visibility = if ([string]::IsNullOrWhiteSpace($guidance)) { 'Collapsed' } else { 'Visible' }
	$dialog.FindName('btnConfirmUpdate').Add_Click({
		param($eventSource, $routedEventArgs)
		$dialogWindow = [System.Windows.Window]::GetWindow($eventSource)
		foreach ($choiceName in @('rbUpdateBoth', 'rbUpdateCli', 'rbUpdateModule')) {
			$choice = $dialogWindow.FindName($choiceName)
			if ($choice.IsChecked -and $choice.IsEnabled) {
				$dialogWindow.Tag = $choice.Tag
				$dialogWindow.DialogResult = $true
				return
			}
		}
		[void](Show-FFUDialog -Owner ($dialogWindow) -Message ('Choose an available update option.') -Title ('Update WinGet') -Buttons ('OK') -Icon ('Information'))
	})
	if ($dialog.ShowDialog() -eq $true) {
		return [string]$dialog.Tag
	}
}

function Install-WingetComponents {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[psobject]$State
	)

	if ($State.Flags.wingetBusy) {
		$State.Controls.txtStatus.Text = 'Wait for the current WinGet operation to finish.'
		WriteLog $State.Controls.txtStatus.Text
		return
	}
	$updateMessage = ''
	try {
		$status = Get-WinGetComponentStatus
		$State.Data.wingetComponentStatus = $status
		$updates = $State.Data.wingetAvailableUpdates
		if ($State.Flags.wingetRestartRequired -or $status.RestartRequired) {
			throw 'Save your work and restart FFU/PowerShell before updating WinGet again.'
		}
		if ($status.WinGetStatus -eq 'Unable to check') {
			throw $status.ErrorMessage
		}
		if ($null -eq $updates) {
			throw 'Click Check Winget Status before updating WinGet.'
		}

		$updateOptions = Get-WingetUpdateOptions -Status $status -Updates $updates
		$installCli = $updateOptions.CliAvailable
		$installModule = $updateOptions.ModuleAvailable
		if (-not ($installCli -or $installModule)) {
			if ($null -eq $updates.WinGetVersionObject -or $null -eq $updates.ModuleVersionObject) {
				throw 'One or more WinGet update versions are unknown. Click Check Winget Status to try again.'
			}
			$updateMessage = 'No WinGet updates are available.'
			WriteLog $updateMessage
			return
		}
		if (-not ($updateOptions.CanUpdateCli -or $updateOptions.CanUpdateModule -or $updateOptions.CanUpdateBoth)) {
			throw 'No compatible WinGet update is available. Check Winget Status for the required versions and any update-check errors.'
		}

		$State.Flags.wingetBusy = $true
		Update-WingetVersionFields -State $State -Message 'Review the available WinGet updates.'
		$chooseComponents = $installCli -and $installModule
		if ($chooseComponents) {
			$selection = Show-WingetUpdateDialog -State $State -UpdateOptions $updateOptions
			if ($null -eq $selection) {
				$updateMessage = 'WinGet update cancelled. No components were changed.'
				WriteLog $updateMessage
				return
			}
			switch ($selection) {
				'Both' { $installCli = $true; $installModule = $true }
				'CLI' { $installCli = $true; $installModule = $false }
				'Module' { $installCli = $false; $installModule = $true }
				default { throw "Unknown WinGet update selection: $selection" }
			}
		}
		$cliTarget = if ($installCli) { $updates.WinGetVersionObject } else { $status.WinGetVersionObject }
		$moduleTarget = if ($installModule) { $updates.ModuleVersionObject } else { $status.ModuleVersionObject }
		$requiredModuleVersion = Get-WinGetRequiredModuleVersion -WinGetVersion $cliTarget
		if ($null -eq $moduleTarget -or $moduleTarget -lt $requiredModuleVersion) {
			throw "The selected CLI requires Microsoft.WinGet.Client $requiredModuleVersion or later. Select Update and choose Update both, or update the module to a compatible version."
		}
		if ($null -eq $cliTarget -or $cliTarget -lt $moduleTarget) {
			throw "The selected module requires WinGet CLI $moduleTarget or later. Update the CLI first or choose Update both. If no compatible stable CLI is available, leave the module unchanged."
		}

		if (-not $chooseComponents) {
			$changes = [System.Collections.Generic.List[string]]::new()
			if ($installCli) { $changes.Add("WinGet CLI: $($status.WinGetVersion) -> $($updates.WinGetVersion)") }
			if ($installModule) { $changes.Add("Microsoft.WinGet.Client: $($status.ModuleVersion) -> $($updates.ModuleVersion)") }
			$confirmation = ($changes -join "`n") + "`n`nA module already in use will require restarting FFU/PowerShell. Continue?"
			if ((Show-FFUDialog -Owner ($State.Window) -Message ($confirmation) -Title ('Update WinGet Components') -Buttons ('YesNo') -Icon ('Question')) -ne 'Yes') {
				$updateMessage = 'WinGet update cancelled. No components were changed.'
				WriteLog $updateMessage
				return
			}
		}

		$State.Window.Cursor = [System.Windows.Input.Cursors]::Wait
		$bootstrapModule = $installModule -and (-not $status.ModuleInstalled -or $status.ModuleVersionObject -lt (Get-WinGetRequiredModuleVersion))
		$componentOrder = if ($bootstrapModule) { @('Module', 'CLI') } else { @('CLI', 'Module') }
		foreach ($component in $componentOrder) {
			if ($component -eq 'CLI' -and $installCli) {
				$repairStatus = Get-WinGetComponentStatus
				if ($State.Flags.wingetRestartRequired -or $repairStatus.RestartRequired) {
					throw 'The module was installed, but its previous version is still loaded. Save your work, restart FFU/PowerShell, and update the CLI before using WinGet.'
				}
				if (-not $repairStatus.ModuleInstalled) {
					throw 'The WinGet module required to update the CLI is not installed. Select Update and choose Update both.'
				}
				if (-not $installModule -and $repairStatus.ModuleVersionObject -lt $requiredModuleVersion) {
					throw "The CLI update requires Microsoft.WinGet.Client $requiredModuleVersion or later. Check Winget Status again and update both components."
				}
				Update-WingetVersionFields -State $State -Message "Updating WinGet CLI to $($updates.WinGetVersion)..."
				Import-Module -Name $repairStatus.ModulePath -Global -ErrorAction Stop
				Install-WinGet -Version $cliTarget -Architecture $State.Controls.cmbWindowsArch.SelectedItem
			}
			elseif ($component -eq 'Module' -and $installModule) {
				$moduleStatus = Get-WinGetComponentStatus
				if ($moduleStatus.ModuleInstalled -and $moduleStatus.ModuleVersionObject -ge $moduleTarget) {
					WriteLog "Microsoft.WinGet.Client $($moduleStatus.ModuleVersion) already meets the selected update version."
					continue
				}
				if (-not $bootstrapModule -and (-not $moduleStatus.WinGetInstalled -or $moduleStatus.WinGetVersionObject -lt $moduleTarget -or $moduleTarget -lt (Get-WinGetRequiredModuleVersion -WinGetVersion $moduleStatus.WinGetVersionObject))) {
					throw "The installed CLI and selected module version $moduleTarget are no longer compatible. Check Winget Status again before updating."
				}
				$moduleWasLoaded = $moduleStatus.ModuleLoaded
				Update-WingetVersionFields -State $State -Message "Updating Microsoft.WinGet.Client to $($updates.ModuleVersion)..."
				$galleryTrust = (Get-PSRepository -Name PSGallery -ErrorAction Stop).InstallationPolicy
				try {
					if ($galleryTrust -eq 'Untrusted') {
						Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop
					}
					Install-Module -Name Microsoft.WinGet.Client -RequiredVersion $updates.ModuleVersion -Repository PSGallery -Scope AllUsers -Force -ErrorAction Stop
				}
				finally {
					if ($galleryTrust -eq 'Untrusted') {
						Set-PSRepository -Name PSGallery -InstallationPolicy Untrusted -ErrorAction Stop
					}
				}
				$status = Get-WinGetComponentStatus
				if (-not $status.ModuleInstalled -or $status.ModuleVersionObject -lt $moduleTarget) {
					throw "Module update is incomplete. Detected: $($status.ModuleVersion). Required: $moduleTarget."
				}
				if ($moduleWasLoaded) {
					$State.Flags.wingetRestartRequired = $true
				}
				WriteLog "Microsoft.WinGet.Client installation verified: $($status.ModuleVersion)."
			}
		}

		$status = Get-WinGetComponentStatus
		if ($status.NeedsUpdate -or $status.WinGetStatus -eq 'Unable to check') {
			throw "WinGet component update is incomplete. $($status.ErrorMessage)"
		}
		$updateMessage = if ($State.Flags.wingetRestartRequired -or $status.RestartRequired) {
			'Selected updates are installed. Save your work and restart FFU/PowerShell before using WinGet.'
		}
		else {
			'Selected WinGet updates are installed and the versions are compatible.'
		}
		WriteLog $updateMessage
		[void](Show-FFUDialog -Owner ($State.Window) -Message ($updateMessage) -Title ('WinGet Update') -Buttons ('OK') -Icon ('Information'))
	}
	catch {
		$updateMessage = "WinGet update failed: $($_.Exception.Message)"
		WriteLog $updateMessage
		[void](Show-FFUDialog -Owner ($State.Window) -Message ($updateMessage) -Title ('WinGet Update') -Buttons ('OK') -Icon ('Error'))
	}
	finally {
		$State.Flags.wingetBusy = $false
		$State.Window.Cursor = $null
		$State.Data.wingetComponentStatus = Get-WinGetComponentStatus
		if ($State.Data.wingetComponentStatus.RestartRequired) {
			$State.Flags.wingetRestartRequired = $true
		}
		Update-WingetVersionFields -State $State -Message $updateMessage
	}
}

function Confirm-WingetInstallationUI {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[psobject]$State
	)

	if ($State.Flags.wingetBusy) {
		$State.Controls.txtStatus.Text = 'Wait for the current WinGet operation to finish.'
		WriteLog $State.Controls.txtStatus.Text
		return
	}
	try {
		$State.Flags.wingetBusy = $true
		$State.Window.Cursor = [System.Windows.Input.Cursors]::Wait
		$State.Data.wingetComponentStatus = Get-WinGetComponentStatus
		Update-WingetVersionFields -State $State -Message 'Checking available WinGet updates...'
		$State.Data.wingetAvailableUpdates = Get-WinGetAvailableUpdates
		return $State.Data.wingetComponentStatus
	}
	catch {
		WriteLog "Unable to check WinGet status: $($_.Exception.Message)"
		[void](Show-FFUDialog -Owner ($State.Window) -Message ($_.Exception.Message) -Title ('WinGet Status') -Buttons ('OK') -Icon ('Error'))
	}
	finally {
		$State.Flags.wingetBusy = $false
		$State.Window.Cursor = $null
		Update-WingetVersionFields -State $State
	}
}

# Note: Start-WingetAppDownloadTask has been moved to FFU.Common.Winget.psm1
# to enable code reuse between UI and CLI builds. It is imported via the FFU.Common module.

function Invoke-WingetDownload {
    param(
        [psobject]$State,
        [object]$Button
    )
	if ($State.Flags.wingetBusy) {
		$State.Controls.txtStatus.Text = 'Wait for the current WinGet operation to finish.'
		WriteLog $State.Controls.txtStatus.Text
		return
	}
    try {
        $selectedApps = $State.Controls.lstWingetResults.Items | Where-Object { $_.IsSelected }
        if (-not $selectedApps) {
            [System.Windows.MessageBox]::Show("No applications selected to download.", "Download Winget Apps", "OK", "Information")
            return
        }

		if ($State.Flags.wingetRestartRequired) {
			throw 'Save your work and restart FFU/PowerShell before using the updated WinGet module.'
		}
		$State.Data.wingetComponentStatus = Get-WinGetComponentStatus
		$wingetStatus = Confirm-WinGetInstallation -WindowsArch $State.Controls.cmbWindowsArch.SelectedItem -PassThru
		$State.Flags.wingetBusy = $true
		Update-WingetVersionFields -State $State
        $Button.IsEnabled = $false
        $State.Controls.pbOverallProgress.Visibility = 'Visible'
        $State.Controls.pbOverallProgress.Value = 0
        $State.Controls.txtStatus.Text = "Starting Winget app downloads..."

        # Define necessary task-specific variables locally
        $localAppsPath = $State.Controls.txtApplicationPath.Text
        $localAppListJsonPath = $State.Controls.txtAppListJsonPath.Text
        $localWindowsArch = $State.Controls.cmbWindowsArch.SelectedItem
        $localOrchestrationPath = Join-Path -Path $State.Controls.txtApplicationPath.Text -ChildPath "Orchestration"

        # Create hashtable for task-specific arguments to pass to Invoke-ParallelProcessing
        # UI downloads skip WinGetWin32Apps.json creation - it's generated at build time
        $taskArguments = @{
            AppsPath            = $localAppsPath
            AppListJsonPath     = $localAppListJsonPath
            OrchestrationPath   = $localOrchestrationPath
            WindowsArch         = $localWindowsArch
            SkipWin32Json       = $true
            WingetModulePath    = $wingetStatus.ModulePath
            WingetModuleVersion = $wingetStatus.ModuleVersion
        }

        # Select only necessary properties before passing to Invoke-ParallelProcessing
        $itemsToProcess = $selectedApps | Select-Object Name, Id, Source, Version, Architecture # Include Version and Architecture if needed

        # Before downloading, persist the selected apps to AppList.json including exit-code fields (parity with Save-WingetList)
        try {
            # Determine AppList.json path; default if empty
            if ([string]::IsNullOrWhiteSpace($localAppListJsonPath)) {
                $localAppListJsonPath = Join-Path -Path $localAppsPath -ChildPath "AppList.json"
                $taskArguments.AppListJsonPath = $localAppListJsonPath
                WriteLog "AppListJsonPath was empty. Defaulting to: $localAppListJsonPath"
            }

            # Build apps payload from current selection, preserving AdditionalExitCodes/IgnoreNonZeroExitCodes
            $appListToSave = @{
                apps = @($selectedApps | ForEach-Object {
                        [ordered]@{
                            name                   = (ConvertTo-SafeName -Name $_.Name)
                            id                     = $_.Id
                            source                 = $_.Source.ToLower()
                            architecture           = $_.Architecture
                            AdditionalExitCodes    = if ($_.PSObject.Properties['AdditionalExitCodes']) { $_.AdditionalExitCodes } else { "" }
                            IgnoreNonZeroExitCodes = if ($_.PSObject.Properties['IgnoreNonZeroExitCodes']) { [bool]$_.IgnoreNonZeroExitCodes } else { $false }
                        }
                    })
            }

            # Ensure destination directory exists and write AppList.json
            $destDir = Split-Path -Parent $localAppListJsonPath
            if (-not (Test-Path -LiteralPath $destDir)) {
                [void][System.IO.Directory]::CreateDirectory($destDir)
            }
            $appListToSave | ConvertTo-Json -Depth 10 | Set-Content -Path $localAppListJsonPath -Encoding UTF8
            WriteLog "Persisted AppList.json with selected apps and exit-code fields to: $localAppListJsonPath"
        }
        catch {
            WriteLog "Warning: Failed to persist AppList.json prior to download. Error: $($_.Exception.Message)"
        }

        # Invoke the centralized parallel processing function
        # Pass task type and task-specific arguments
        $parallelResults = Invoke-ParallelProcessing -ItemsToProcess $itemsToProcess `
            -ListViewControl $State.Controls.lstWingetResults `
            -IdentifierProperty 'Id' `
            -StatusProperty 'DownloadStatus' `
            -TaskType 'WingetDownload' `
            -TaskArguments $taskArguments `
            -CompletedStatusText "Completed" `
            -ErrorStatusPrefix "Error: " `
            -WindowObject $State.Window `
            -MainThreadLogPath $State.LogFilePath `
            -ThrottleLimit $State.Controls.txtThreads.Text

        # Final status update is handled by Invoke-ParallelProcessing, but we need to re-enable the button
        $State.Controls.pbOverallProgress.Visibility = 'Collapsed'
        $Button.IsEnabled = $true
    }
    catch {
        WriteLog "FATAL Error in Invoke-WingetDownload: $($_.Exception.ToString())"
        [System.Windows.MessageBox]::Show("A critical error occurred while starting the Winget download: $($_.Exception.Message)", "Error", "OK", "Error")
        # Reset UI state on error
        if ($Button) { $Button.IsEnabled = $true }
        if ($State.Controls.pbOverallProgress) { $State.Controls.pbOverallProgress.Visibility = 'Collapsed' }
        if ($State.Controls.txtStatus) { $State.Controls.txtStatus.Text = "Winget download failed to start." }
    }
	finally {
		$State.Flags.wingetBusy = $false
		Update-WingetVersionFields -State $State
	}
}

function Update-WingetVersionFields {
	param(
		[psobject]$State,
		[string]$Message
	)
	$State.Window.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Normal, [Action] {
		$status = $State.Data.wingetComponentStatus
		$updates = $State.Data.wingetAvailableUpdates
		$busy = [bool]$State.Flags.wingetBusy
		$State.Controls.btnCheckWingetModule.IsEnabled = -not $busy
		$State.Controls.btnUpdateWinget.IsEnabled = $false
		$State.Controls.btnUpdateWinget.Visibility = 'Collapsed'
		$State.Controls.btnWingetSearch.IsEnabled = $false
		$State.Controls.btnDownloadSelected.IsEnabled = $false
		if ($null -eq $status) {
			$State.Controls.txtWingetComponentStatus.Text = 'Click Check Winget Status before searching or downloading apps.'
			return
		}

		$State.Controls.txtWingetVersion.Text = $status.WinGetVersion
		$State.Controls.txtWingetModuleVersion.Text = $status.ModuleVersion
		$State.Controls.txtLatestWingetVersion.Text = if ($null -ne $updates) { $updates.WinGetVersion } else { 'Not checked' }
		$State.Controls.txtLatestWingetModuleVersion.Text = if ($null -ne $updates) { $updates.ModuleVersion } else { 'Not checked' }
		$restartRequired = $State.Flags.wingetRestartRequired -or $status.RestartRequired
		$ready = $status.Success -and -not $restartRequired -and -not $busy
		$State.Controls.btnWingetSearch.IsEnabled = $ready
		$State.Controls.btnDownloadSelected.IsEnabled = $ready
		if ($State.Controls.chkInstallApps.IsChecked -and $State.Controls.chkInstallWingetApps.IsChecked -and ($status.Success -or $State.Controls.lstWingetResults.HasItems)) {
			$State.Controls.wingetSearchPanel.Visibility = 'Visible'
		}
		else {
			$State.Controls.wingetSearchPanel.Visibility = 'Collapsed'
		}

		$messages = [System.Collections.Generic.List[string]]::new()
		if ($restartRequired) {
			$messages.Add("Save your work and restart FFU/PowerShell before using WinGet. Loaded module: $($status.LoadedModuleVersion).")
		}
		elseif ($status.Success) {
			$messages.Add('Installed versions are compatible. Updates are optional.')
		}
		else {
			$messages.Add($status.ErrorMessage)
		}
		if ($null -ne $updates) {
			$updateOptions = Get-WingetUpdateOptions -Status $status -Updates $updates
			$canUpdate = -not $busy -and -not $restartRequired -and $status.WinGetStatus -ne 'Unable to check'
			$State.Controls.btnUpdateWinget.IsEnabled = $canUpdate -and ($updateOptions.CanUpdateCli -or $updateOptions.CanUpdateModule -or $updateOptions.CanUpdateBoth)
			if ($updateOptions.CliAvailable -or $updateOptions.ModuleAvailable) {
				$State.Controls.btnUpdateWinget.Visibility = 'Visible'
				if ($updateOptions.CanUpdateCli -or $updateOptions.CanUpdateModule -or $updateOptions.CanUpdateBoth) {
					$messages.Add('Updates are available. Select Update to continue.')
				}
				else {
					$messages.Add('Updates are available, but no compatible update combination was found.')
				}
			}
			if ($updateOptions.CliAvailable -and (-not $status.ModuleInstalled -or $status.ModuleVersionObject -lt $updateOptions.RequiredModuleVersion)) {
				$messages.Add("CLI $($updates.WinGetVersion) requires module $($updateOptions.RequiredModuleVersion) or later.")
			}
			if ($updateOptions.ModuleAvailable -and (-not $status.WinGetInstalled -or $status.WinGetVersionObject -lt $updates.ModuleVersionObject)) {
				$messages.Add("Module $($updates.ModuleVersion) requires CLI $($updates.ModuleVersion) or later.")
			}
			if ($updateOptions.CanUpdateBoth -and -not $updateOptions.CanUpdateCli -and -not $updateOptions.CanUpdateModule) {
				$messages.Add('Select Update and choose Update both to keep the versions compatible.')
			}
			if ($null -ne $updateOptions.CliTarget -and $null -ne $updateOptions.ModuleTarget -and $updateOptions.CliTarget -lt $updateOptions.ModuleTarget) {
				$messages.Add('No compatible CLI update was found. Leave the module unchanged and check again after a suitable CLI is released.')
			}
			if ($null -ne $updateOptions.CliTarget -and $null -ne $updateOptions.ModuleTarget -and $updateOptions.ModuleTarget -lt $updateOptions.RequiredModuleVersion) {
				$messages.Add('No compatible module update was found. Leave the CLI unchanged and check again after a suitable module is released.')
			}
			if (-not [string]::IsNullOrWhiteSpace($updates.WinGetError)) {
				$messages.Add("Unable to check CLI updates: $($updates.WinGetError)")
			}
			if (-not [string]::IsNullOrWhiteSpace($updates.ModuleError)) {
				$messages.Add("Unable to check module updates: $($updates.ModuleError)")
			}
		}
		if (-not [string]::IsNullOrWhiteSpace($Message)) {
			$messages.Insert(0, $Message)
		}
		$State.Controls.txtWingetComponentStatus.Text = $messages -join "`n"
		[System.Windows.Forms.Application]::DoEvents()
	})
}

Export-ModuleMember -Function *