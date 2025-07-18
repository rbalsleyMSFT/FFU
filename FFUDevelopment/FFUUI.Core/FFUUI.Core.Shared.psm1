# Function to update priorities sequentially in a ListView
function Update-ListViewPriorities {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.ListView]$ListView
    )

    $currentPriority = 1
    foreach ($item in $ListView.Items) {
        if ($null -ne $item -and $item.PSObject.Properties['Priority']) {
            $item.Priority = $currentPriority
            $currentPriority++
        }
    }
    $ListView.Items.Refresh()
}

# Function to move selected item to the top
function Move-ListViewItemTop {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.ListView]$ListView
    )

    $selectedItem = $ListView.SelectedItem
    if ($null -eq $selectedItem) { return }

    $currentIndex = $ListView.Items.IndexOf($selectedItem)
    if ($currentIndex -gt 0) {
        $ListView.Items.RemoveAt($currentIndex)
        $ListView.Items.Insert(0, $selectedItem)
        $ListView.SelectedItem = $selectedItem
        Update-ListViewPriorities -ListView $ListView
    }
}

# Function to move selected item up one position
function Move-ListViewItemUp {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.ListView]$ListView
    )

    $selectedItem = $ListView.SelectedItem
    if ($null -eq $selectedItem) { return }

    $currentIndex = $ListView.Items.IndexOf($selectedItem)
    if ($currentIndex -gt 0) {
        $ListView.Items.RemoveAt($currentIndex)
        $ListView.Items.Insert($currentIndex - 1, $selectedItem)
        $ListView.SelectedItem = $selectedItem
        Update-ListViewPriorities -ListView $ListView
    }
}

# Function to move selected item down one position
function Move-ListViewItemDown {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.ListView]$ListView
    )

    $selectedItem = $ListView.SelectedItem
    if ($null -eq $selectedItem) { return }

    $currentIndex = $ListView.Items.IndexOf($selectedItem)
    if ($currentIndex -lt ($ListView.Items.Count - 1)) {
        $ListView.Items.RemoveAt($currentIndex)
        $ListView.Items.Insert($currentIndex + 1, $selectedItem)
        $ListView.SelectedItem = $selectedItem
        Update-ListViewPriorities -ListView $ListView
    }
}

# Function to move selected item to the bottom
function Move-ListViewItemBottom {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.ListView]$ListView
    )

    $selectedItem = $ListView.SelectedItem
    if ($null -eq $selectedItem) { return }

    $currentIndex = $ListView.Items.IndexOf($selectedItem)
    if ($currentIndex -lt ($ListView.Items.Count - 1)) {
        $ListView.Items.RemoveAt($currentIndex)
        $ListView.Items.Add($selectedItem)
        $ListView.SelectedItem = $selectedItem
        Update-ListViewPriorities -ListView $ListView
    }
}

# Function to update status of a specific item in a ListView
function Update-ListViewItemStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$WindowObject, # Changed type to [object]
        [Parameter(Mandatory)]
        [object]$ListView,     # Changed type to [object]
        [Parameter(Mandatory)]
        [string]$IdentifierProperty, 
        [Parameter(Mandatory)]
        [string]$IdentifierValue,
        [Parameter(Mandatory)]
        [string]$StatusProperty,     
        [Parameter(Mandatory)]
        [string]$StatusValue
    )
    
    # Ensure we are in UI mode and objects are of correct WPF types
    if ($WindowObject -is [System.Windows.Window] -and $ListView -is [System.Windows.Controls.ListView]) {
        # Directly update UI elements as this function is now called on the UI thread
        try {
            # Determine which collection to search: ItemsSource (preferred) or Items.
            $collectionToSearch = $null
            if ($null -ne $ListView.ItemsSource) {
                $collectionToSearch = $ListView.ItemsSource
            }
            else {
                $collectionToSearch = $ListView.Items
            }

            $itemToUpdate = $collectionToSearch | Where-Object { $_.$IdentifierProperty -eq $IdentifierValue } | Select-Object -First 1
            if ($null -ne $itemToUpdate) {
                $itemToUpdate.$StatusProperty = $StatusValue
                $ListView.Items.Refresh() # Refresh the view to show the change
            }
            else {
                # Log if item not found (for debugging)
                WriteLog "Update-ListViewItemStatus: Item with $IdentifierProperty '$IdentifierValue' not found in ListView."
            }
        }
        catch {
            WriteLog "Update-ListViewItemStatus: Error updating ListView: $($_.Exception.Message)"
        }
    } # End of if ($WindowObject -is [System.Windows.Window]...)
    else {
        # Log if called in non-UI mode or with incorrect types (should not happen if Invoke-ParallelProcessing $isUiMode is correct)
        WriteLog "Update-ListViewItemStatus: Skipped UI update for $IdentifierValue due to non-UI mode or incorrect object types."
    }
}

# Function to update overall progress bar and status text label
function Update-OverallProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$WindowObject, # Changed type to [object]
        [Parameter(Mandatory)]
        [int]$CompletedCount,
        [Parameter(Mandatory)]
        [int]$TotalCount,
        [Parameter(Mandatory)]
        [string]$StatusText,
        [Parameter(Mandatory)] 
        [string]$ProgressBarName,
        [Parameter(Mandatory)]
        [string]$StatusLabelName
    )

    # Ensure we are in UI mode and WindowObject is of correct WPF type
    if ($WindowObject -is [System.Windows.Window]) {
        # Directly update UI elements as this function is now called on the UI thread
        try {
            # Find controls by name using the $WindowObject
            $pb = $WindowObject.FindName($ProgressBarName)
            $lbl = $WindowObject.FindName($StatusLabelName)

            if ($null -eq $pb) {
                WriteLog "Update-OverallProgress: ProgressBar '$ProgressBarName' not found."
                return
            }
            if ($null -eq $lbl) {
                WriteLog "Update-OverallProgress: StatusLabel '$StatusLabelName' not found."
                return
            }

            # Update the progress bar
            if ($TotalCount -gt 0) {
                $percentComplete = ($CompletedCount / $TotalCount) * 100
                $pb.Value = $percentComplete
            }
            else {
                $pb.Value = 0 
            }
            
            # Update the status label
            $lbl.Text = $StatusText
            
        }
        catch {
            WriteLog "Update-OverallProgress: Error updating progress: $($_.Exception.Message)"
        }
    } # End of if ($WindowObject -is [System.Windows.Window])
    else {
        # Log if called in non-UI mode or with incorrect types
        WriteLog "Update-OverallProgress: Skipped UI update ($StatusText) due to non-UI mode or incorrect WindowObject type."
    }
}

# Helper function to enqueue progress updates to the UI thread
function Invoke-ProgressUpdate {
    param(
        [Parameter(Mandatory)]
        [System.Collections.Concurrent.ConcurrentQueue[hashtable]]$ProgressQueue,
        [Parameter(Mandatory)]
        [string]$Identifier,
        [Parameter(Mandatory)]
        [string]$Status
    )
    $ProgressQueue.Enqueue(@{ Identifier = $Identifier; Status = $Status })
}

# Add a function to create a sortable list view
function Add-SortableColumn {
    param(
        [System.Windows.Controls.GridView]$gridView,
        [string]$header,
        [string]$binding,
        [int]$width = 'Auto',
        [bool]$isCheckbox = $false,
        [System.Windows.HorizontalAlignment]$headerHorizontalAlignment = [System.Windows.HorizontalAlignment]::Stretch
    )

    $column = New-Object System.Windows.Controls.GridViewColumn
    $commonPadding = New-Object System.Windows.Thickness(5, 2, 5, 2)

    $headerControl = New-Object System.Windows.Controls.GridViewColumnHeader
    $headerControl.Tag = $binding # Used for sorting

    if ($isCheckbox) {
        # Cell template for a column of checkboxes
        $cellTemplate = New-Object System.Windows.DataTemplate
        $gridFactory = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.Grid])

        $checkBoxFactory = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.CheckBox])
        $checkBoxFactory.SetBinding([System.Windows.Controls.CheckBox]::IsCheckedProperty, (New-Object System.Windows.Data.Binding("IsSelected")))
        $checkBoxFactory.SetValue([System.Windows.FrameworkElement]::HorizontalAlignmentProperty, [System.Windows.HorizontalAlignment]::Center)
        $checkBoxFactory.SetValue([System.Windows.FrameworkElement]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Center)

        $checkBoxFactory.AddHandler([System.Windows.Controls.CheckBox]::ClickEvent, [System.Windows.RoutedEventHandler] {
                param($eventSourceLocal, $eventArgsLocal)
                # Sync logic would be needed here if this column had a header checkbox
            })
        $gridFactory.AppendChild($checkBoxFactory)
        $cellTemplate.VisualTree = $gridFactory
        $column.CellTemplate = $cellTemplate
    }
    else {
        # For regular text columns
        $headerControl.HorizontalContentAlignment = $headerHorizontalAlignment
        $headerControl.Content = $header

        $headerTextElementFactory = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.TextBlock])
        $headerTextElementFactory.SetValue([System.Windows.Controls.TextBlock]::TextProperty, $header)
        $headerTextBlockPadding = New-Object System.Windows.Thickness($commonPadding.Left, $commonPadding.Top, $commonPadding.Right, $commonPadding.Bottom)
        $headerTextElementFactory.SetValue([System.Windows.Controls.TextBlock]::PaddingProperty, $headerTextBlockPadding)
        $headerTextElementFactory.SetValue([System.Windows.FrameworkElement]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Center)

        $headerDataTemplate = New-Object System.Windows.DataTemplate
        $headerDataTemplate.VisualTree = $headerTextElementFactory
        $headerControl.ContentTemplate = $headerDataTemplate

        $cellTemplate = New-Object System.Windows.DataTemplate
        $textBlockFactory = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.TextBlock])
        $textBlockFactory.SetBinding([System.Windows.Controls.TextBlock]::TextProperty, (New-Object System.Windows.Data.Binding($binding)))
        # Adjust left padding to 0 for cell text to align with header text
        $cellTextBlockPadding = New-Object System.Windows.Thickness(0, $commonPadding.Top, $commonPadding.Right, $commonPadding.Bottom)
        $textBlockFactory.SetValue([System.Windows.Controls.TextBlock]::PaddingProperty, $cellTextBlockPadding)
        $textBlockFactory.SetValue([System.Windows.FrameworkElement]::HorizontalAlignmentProperty, [System.Windows.HorizontalAlignment]::Left)
        $textBlockFactory.SetValue([System.Windows.FrameworkElement]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Center)

        $cellTemplate.VisualTree = $textBlockFactory
        $column.CellTemplate = $cellTemplate
    }

    $column.Header = $headerControl

    if ($width -ne 'Auto') {
        $column.Width = $width
    }

    $gridView.Columns.Add($column)
}

# Function to add a selectable GridViewColumn with a "Select All" header CheckBox
function Add-SelectableGridViewColumn {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.ListView]$ListView,
        [Parameter(Mandatory)]
        [psobject]$State,
        [Parameter(Mandatory)]
        [string]$HeaderCheckBoxKeyName,
        [Parameter(Mandatory)]
        [double]$ColumnWidth,
        [string]$IsSelectedPropertyName = "IsSelected"
    )

    # Ensure the ListView has a GridView
    if ($null -eq $ListView.View -or -not ($ListView.View -is [System.Windows.Controls.GridView])) {
        WriteLog "Add-SelectableGridViewColumn: ListView '$($ListView.Name)' does not have a GridView or View is null. Cannot add column."
        return
    }
    $gridView = $ListView.View

    # Create the "Select All" CheckBox for the header
    $headerCheckBox = New-Object System.Windows.Controls.CheckBox
    $headerCheckBox.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
    
    # MODIFICATION: Store the actual ListView object in the header's Tag
    $headerTagObject = [PSCustomObject]@{
        PropertyName    = $IsSelectedPropertyName
        ListViewControl = $ListView # Store the object itself
    }
    $headerCheckBox.Tag = $headerTagObject

    $headerCheckBox.Add_Checked({
            param($senderCheckBoxLocal, $eventArgsCheckedLocal)
            $tagData = $senderCheckBoxLocal.Tag
            $localPropertyName = $tagData.PropertyName
            $actualListView = $tagData.ListViewControl # Get the control directly from the tag

            $collectionToUpdate = if ($null -ne $actualListView.ItemsSource) { $actualListView.ItemsSource } else { $actualListView.Items }
            if ($null -ne $collectionToUpdate) {
                foreach ($item in $collectionToUpdate) { $item.$($localPropertyName) = $true }
                $actualListView.Items.Refresh()
            }
        })

    $headerCheckBox.Add_Unchecked({
            param($senderCheckBoxLocal, $eventArgsUncheckedLocal)
            if ($senderCheckBoxLocal.IsChecked -eq $false) {
                $tagData = $senderCheckBoxLocal.Tag
                $localPropertyName = $tagData.PropertyName
                $actualListView = $tagData.ListViewControl # Get the control directly from the tag

                $collectionToUpdate = if ($null -ne $actualListView.ItemsSource) { $actualListView.ItemsSource } else { $actualListView.Items }
                if ($null -ne $collectionToUpdate) {
                    foreach ($item in $collectionToUpdate) { $item.$($localPropertyName) = $false }
                    $actualListView.Items.Refresh()
                }
            }
        })

    $State.Controls[$HeaderCheckBoxKeyName] = $headerCheckBox
    WriteLog "Add-SelectableGridViewColumn: Stored header checkbox in State.Controls with key '$HeaderCheckBoxKeyName'."

    $selectableColumn = New-Object System.Windows.Controls.GridViewColumn
    $selectableColumn.Header = $headerCheckBox
    $selectableColumn.Width = $ColumnWidth

    $cellTemplate = New-Object System.Windows.DataTemplate
    $borderFactory = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.Border])
    $borderFactory.SetValue([System.Windows.FrameworkElement]::HorizontalAlignmentProperty, [System.Windows.HorizontalAlignment]::Stretch)
    $borderFactory.SetValue([System.Windows.FrameworkElement]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Stretch)

    $checkBoxFactory = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.CheckBox])
    $checkBoxFactory.SetBinding([System.Windows.Controls.CheckBox]::IsCheckedProperty, (New-Object System.Windows.Data.Binding($IsSelectedPropertyName)))
    $checkBoxFactory.SetValue([System.Windows.FrameworkElement]::HorizontalAlignmentProperty, [System.Windows.HorizontalAlignment]::Center)
    $checkBoxFactory.SetValue([System.Windows.FrameworkElement]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Center)

    # MODIFICATION: Store the actual ListView object in the item checkbox's Tag
    $tagObject = [PSCustomObject]@{
        HeaderCheckboxKeyName = $HeaderCheckBoxKeyName
        ListViewControl       = $ListView # Store the object itself
    }
    $checkBoxFactory.SetValue([System.Windows.FrameworkElement]::TagProperty, $tagObject)

    $checkBoxFactory.AddHandler([System.Windows.Controls.CheckBox]::ClickEvent, [System.Windows.RoutedEventHandler] {
            param($eventSourceLocal, $eventArgsLocal)
            $itemCheckBox = $eventSourceLocal -as [System.Windows.Controls.CheckBox]
            $tagData = $itemCheckBox.Tag
            
            $headerCheckboxKeyFromTag = $tagData.HeaderCheckboxKeyName
            $targetListView = $tagData.ListViewControl # Get the control directly from the tag

            # Get the state from the window tag
            $window = [System.Windows.Window]::GetWindow($targetListView)
            if ($null -eq $window -or $null -eq $window.Tag) {
                WriteLog "Add-SelectableGridViewColumn: ERROR - Could not get window or state from window tag."
                return
            }
            $localState = $window.Tag

            WriteLog "Add-SelectableGridViewColumn: Item Click. ListView: '$($targetListView.Name)', HeaderChkKey: '$headerCheckboxKeyFromTag'"

            $headerChk = $localState.Controls[$headerCheckboxKeyFromTag]
            if ($null -ne $headerChk) {
                Update-SelectAllHeaderCheckBoxState -ListView $targetListView -HeaderCheckBox $headerChk
            }
            else {
                WriteLog "Add-SelectableGridViewColumn: Error - Could not retrieve header checkbox from state with key '$headerCheckboxKeyFromTag'."
            }
        })

    $borderFactory.AppendChild($checkBoxFactory)
    $cellTemplate.VisualTree = $borderFactory
    $selectableColumn.CellTemplate = $cellTemplate

    $gridView.Columns.Insert(0, $selectableColumn)
    WriteLog "Add-SelectableGridViewColumn: Successfully added selectable column to '$($ListView.Name)'."
}

# Function to update the IsChecked state of a "Select All" header CheckBox
function Update-SelectAllHeaderCheckBoxState {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.ListView]$ListView,
        [Parameter(Mandatory)]
        [System.Windows.Controls.CheckBox]$HeaderCheckBox
    )

    $collectionToInspect = $null
    if ($null -ne $ListView.ItemsSource) {
        $collectionToInspect = @($ListView.ItemsSource)
    }
    elseif ($ListView.HasItems) {
        # Check if Items collection has items and ItemsSource is null
        $collectionToInspect = @($ListView.Items)
    }

    # If no items to inspect (either ItemsSource was null and Items was empty, or ItemsSource was empty)
    if ($null -eq $collectionToInspect -or $collectionToInspect.Count -eq 0) {
        $HeaderCheckBox.IsChecked = $false
        return
    }

    $selectedCount = ($collectionToInspect | Where-Object { $_.IsSelected }).Count
    WriteLog "Update-SelectAllHeaderCheckBoxState: Selected count is $selectedCount for ListView '$($ListView.Name)'."
    $totalItemCount = $collectionToInspect.Count # Get the total count from the collection being inspected
    WriteLog "Update-SelectAllHeaderCheckBoxState: Total item count is $totalItemCount for ListView '$($ListView.Name)'."

    if ($totalItemCount -eq 0) {
        # Handle empty list case specifically
        $HeaderCheckBox.IsChecked = $false
    }
    elseif ($selectedCount -eq $totalItemCount) {
        $HeaderCheckBox.IsChecked = $true
    }
    elseif ($selectedCount -eq 0) {
        $HeaderCheckBox.IsChecked = $false
    }
    else {
        # Indeterminate state
        $HeaderCheckBox.IsChecked = $null
    }
}

# Function to toggle the IsSelected state of the currently selected ListView item
function Invoke-ListViewItemToggle {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.ListView]$ListView,
        [Parameter(Mandatory)]
        [psobject]$State,
        [Parameter(Mandatory)]
        [string]$HeaderCheckBoxKeyName
    )

    $selectedItem = $ListView.SelectedItem
    if ($null -eq $selectedItem) { return }

    # Store the current index to restore focus later
    $currentIndex = $ListView.SelectedIndex

    # Toggle the IsSelected property
    $selectedItem.IsSelected = -not $selectedItem.IsSelected
    $ListView.Items.Refresh()

    # Update the 'Select All' header checkbox state
    $headerChk = $State.Controls[$HeaderCheckBoxKeyName]
    if ($null -ne $headerChk) {
        Update-SelectAllHeaderCheckBoxState -ListView $ListView -HeaderCheckBox $headerChk
    }

    # Restore selection and focus to the item that was just toggled
    if ($currentIndex -ge 0 -and $ListView.Items.Count -gt $currentIndex) {
        $ListView.SelectedIndex = $currentIndex
        
        # Ensure the UI is updated before trying to find the container
        $ListView.UpdateLayout()
        
        $listViewItem = $ListView.ItemContainerGenerator.ContainerFromIndex($currentIndex)
        if ($null -ne $listViewItem) {
            $listViewItem.Focus()
        }
    }
}

# Function to sort ListView items
function Invoke-ListViewSort {
    param(
        [System.Windows.Controls.ListView]$listView,
        [string]$property,
        [PSCustomObject]$State
    )

    # Ensure $State.Flags is a hashtable and contains the required sort properties
    if ($State.Flags -is [hashtable]) {
        if (-not $State.Flags.ContainsKey('lastSortProperty')) {
            $State.Flags['lastSortProperty'] = $null
        }
        if (-not $State.Flags.ContainsKey('lastSortAscending')) {
            $State.Flags['lastSortAscending'] = $true # Default to ascending
        }
    }
    else {
        Write-Warning "Invoke-ListViewSort: \$State.Flags is not a hashtable or is null. Sort state may not work correctly."
        # Attempt to initialize if $State.Flags is null or unexpectedly not a hashtable,
        # though this might indicate a deeper issue with $State.Flags initialization.
        if ($null -eq $State.Flags) { $State.Flags = @{} }
        if ($State.Flags -is [hashtable]) { # Check again after potential initialization
            if (-not $State.Flags.ContainsKey('lastSortProperty')) { $State.Flags['lastSortProperty'] = $null }
            if (-not $State.Flags.ContainsKey('lastSortAscending')) { $State.Flags['lastSortAscending'] = $true }
        }
    }

    # Toggle sort direction if clicking the same column
    if ($State.Flags.lastSortProperty -eq $property) {
        $State.Flags.lastSortAscending = -not $State.Flags.lastSortAscending
    }
    else {
        $State.Flags.lastSortAscending = $true
    }
    $State.Flags.lastSortProperty = $property

    # Get items from ItemsSource or Items collection
    $currentItemsSource = $listView.ItemsSource
    $itemsToSort = @()
    if ($null -ne $currentItemsSource) {
        $itemsToSort = @($currentItemsSource)
    }
    else {
        $itemsToSort = @($listView.Items)
    }

    if ($itemsToSort.Count -eq 0) {
        return
    }

    $selectedItems = @($itemsToSort | Where-Object { $_.IsSelected })
    $unselectedItems = @($itemsToSort | Where-Object { -not $_.IsSelected })

    # Define the primary sort criterion
    $primarySortDefinition = @{
        Expression = {
            $val = $_.$property
            if ($null -eq $val) { '' } else { $val }
        }
        Ascending  = $State.Flags.lastSortAscending
    }

    $sortCriteria = [System.Collections.Generic.List[hashtable]]::new()
    $sortCriteria.Add($primarySortDefinition)

    # Determine secondary sort property based on the ListView
    $secondarySortPropertyName = $null
    if ($listView.Name -eq 'lstDriverModels') {
        $secondarySortPropertyName = "Model"
    }
    elseif ($listView.Name -eq 'lstWingetResults') {
        $secondarySortPropertyName = "Name"
    }
    elseif ($listView.Name -eq 'lstAppsScriptVariables') {
        if ($property -eq "Key") {
            $secondarySortPropertyName = "Value"
        }
        elseif ($property -eq "Value") {
            $secondarySortPropertyName = "Key"
        }
        else {
            # Default secondary sort for IsSelected or other properties
            $secondarySortPropertyName = "Key"
        }
    }

    if ($null -ne $secondarySortPropertyName -and $property -ne $secondarySortPropertyName) {
        $itemsHaveSecondaryProperty = $false
        if ($unselectedItems.Count -gt 0) {
            if ($null -ne $unselectedItems[0].PSObject.Properties[$secondarySortPropertyName]) {
                $itemsHaveSecondaryProperty = $true
            }
        }
        elseif ($selectedItems.Count -gt 0) {
            if ($null -ne $selectedItems[0].PSObject.Properties[$secondarySortPropertyName]) {
                $itemsHaveSecondaryProperty = $true
            }
        }

        if ($itemsHaveSecondaryProperty) {
            # Create a scriptblock for the secondary sort expression dynamically
            $expressionScriptBlock = [scriptblock]::Create("`$_.$secondarySortPropertyName")

            $secondarySortDefinition = @{
                Expression = {
                    $val = Invoke-Command -ScriptBlock $expressionScriptBlock -ArgumentList $_
                    if ($null -eq $val) { '' } else { $val }
                }
                Ascending  = $true # Secondary sort always ascending
            }
            $sortCriteria.Add($secondarySortDefinition)
        }
    }

    $sortedUnselected = $unselectedItems | Sort-Object -Property $sortCriteria.ToArray()
    # Ensure $sortedUnselected is not null before attempting to add its range
    if ($null -eq $sortedUnselected) {
        $sortedUnselected = @()
    }

    # Combine sorted items: selected items first, then sorted unselected items
    $newSortedList = [System.Collections.Generic.List[object]]::new()
    $newSortedList.AddRange($selectedItems)
    $newSortedList.AddRange($sortedUnselected)

    # Set the new sorted list as the ItemsSource
    # Try nulling out ItemsSource first to force a more complete refresh
    $listView.ItemsSource = $null
    $listView.ItemsSource = $newSortedList.ToArray()
}

# --------------------------------------------------------------------------
# SECTION: Modern Folder Picker
# --------------------------------------------------------------------------

# 1) Define a C# class that uses the correct GUIDs for IFileDialog, IFileOpenDialog, and FileOpenDialog,
#    while omitting conflicting "GetResults/GetSelectedItems" from IFileDialog.
if (-not ("ModernFolderBrowser" -as [type])) {
    $modernFolderBrowserCode = @"
    using System;
    using System.Runtime.InteropServices;

    public static class ModernFolderBrowser
    {
        // Flags for IFileDialog
        [Flags]
        private enum FileDialogOptions : uint
        
        {
            OverwritePrompt      = 0x00000002,
            StrictFileTypes      = 0x00000004,
            NoChangeDir          = 0x00000008,
            PickFolders          = 0x00000020,
            ForceFileSystem      = 0x00000040,
            AllNonStorageItems   = 0x00000080,
            NoValidate           = 0x00000100,
            AllowMultiSelect     = 0x00000200,
            PathMustExist        = 0x00000800,
            FileMustExist        = 0x00001000,
            CreatePrompt         = 0x00002000,
            ShareAware           = 0x00004000,
            NoReadOnlyReturn     = 0x00008000,
            NoTestFileCreate     = 0x00010000,
            DontAddToRecent      = 0x02000000,
            ForceShowHidden      = 0x10000000
        }

        // IFileDialog (GUID from Windows SDK)
        //  - Omitting GetResults / GetSelectedItems to avoid overshadow.
        [ComImport]
        [Guid("42F85136-DB7E-439C-85F1-E4075D135FC8")]
        [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IFileDialog
        {
            [PreserveSig]
            int Show(IntPtr parent);

            void SetFileTypes(uint cFileTypes, IntPtr rgFilterSpec);
            void SetFileTypeIndex(uint iFileType);
            void GetFileTypeIndex(out uint piFileType);
            void Advise(IntPtr pfde, out uint pdwCookie);
            void Unadvise(uint dwCookie);
            void SetOptions(FileDialogOptions fos);
            void GetOptions(out FileDialogOptions pfos);
            void SetDefaultFolder(IShellItem psi);
            void SetFolder(IShellItem psi);
            void GetFolder(out IShellItem ppsi);
            void GetCurrentSelection(out IShellItem ppsi);
            void SetFileName([MarshalAs(UnmanagedType.LPWStr)] string pszName);
            void GetFileName(out IntPtr pszName);
            void SetTitle([MarshalAs(UnmanagedType.LPWStr)] string pszTitle);
            void SetOkButtonLabel([MarshalAs(UnmanagedType.LPWStr)] string pszText);
            void SetFileNameLabel([MarshalAs(UnmanagedType.LPWStr)] string pszLabel);
            void GetResult(out IShellItem ppsi);
            void AddPlace(IShellItem psi, int fdap);
            void SetDefaultExtension([MarshalAs(UnmanagedType.LPWStr)] string pszDefaultExtension);
            void Close(int hr);
            void SetClientGuid(ref Guid guid);
            void ClearClientData();
            void SetFilter(IntPtr pFilter);

            // NOTE: We intentionally do NOT define GetResults and GetSelectedItems here,
            // because they cause overshadow warnings in IFileOpenDialog.
        }

        // IFileOpenDialog extends IFileDialog by adding 2 new methods with the same name,
        // which otherwise cause overshadow warnings. We'll define them only here.
        [ComImport]
        [Guid("D57C7288-D4AD-4768-BE02-9D969532D960")]
        [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IFileOpenDialog : IFileDialog
        {
            // These two come after the parent's vtable:
            void GetResults(out IntPtr ppenum);
            void GetSelectedItems(out IntPtr ppsai);
        }

        // The coclass for creating an IFileOpenDialog
        [ComImport]
        [Guid("DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7")]
        private class FileOpenDialog
        {
        }

        // IShellItem
        [ComImport]
        [Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE")]
        [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IShellItem
        {
            void BindToHandler(IntPtr pbc, ref Guid bhid, ref Guid riid, out IntPtr ppv);
            void GetParent(out IShellItem ppsi);
            void GetDisplayName(uint sigdnName, out IntPtr ppszName);
            void GetAttributes(uint sfgaoMask, out uint psfgaoAttribs);
            void Compare(IShellItem psi, uint hint, out int piOrder);
        }

        [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern int SHCreateItemFromParsingName([MarshalAs(UnmanagedType.LPWStr)] string pszPath, IntPtr pbc, ref Guid riid, [MarshalAs(UnmanagedType.Interface, IidParameterIndex = 2)] out IShellItem ppv);

        private const uint SIGDN_FILESYSPATH = 0x80058000;
        private static readonly Guid IID_IShellItem = new Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE");

        public static string ShowDialog(string title, IntPtr parentHandle, string initialDirectory)
        {
            // Create COM dialog instance
            IFileOpenDialog dialog = (IFileOpenDialog)(new FileOpenDialog());

            // Get current options
            FileDialogOptions opts;
            dialog.GetOptions(out opts);

            // Add flags for picking folders
            opts |= FileDialogOptions.PickFolders | FileDialogOptions.PathMustExist | FileDialogOptions.ForceFileSystem;
            dialog.SetOptions(opts);

            // Set initial directory if provided
            if (!string.IsNullOrEmpty(initialDirectory))
            {
                try
                {
                    Guid iid = IID_IShellItem; // Create a local copy to pass by ref
                    if (SHCreateItemFromParsingName(initialDirectory, IntPtr.Zero, ref iid, out IShellItem initialFolder) == 0)
                    {
                        dialog.SetFolder(initialFolder);
                        Marshal.ReleaseComObject(initialFolder);
                    }
                }
                catch
                {
                    // Ignore errors in setting initial directory (e.g., path doesn't exist)
                }
            }

            // Set title
            if (!string.IsNullOrEmpty(title))
            {
                dialog.SetTitle(title);
            }

            // Show the dialog
            int hr = dialog.Show(parentHandle);
            // 0 = S_OK. 1 or 0x800704C7 often means user canceled. Return null if so.
            if (hr != 0)
            {
                if ((uint)hr == 0x800704C7 || hr == 1)
                {
                    return null; // Canceled
                }
                else
                {
                    Marshal.ThrowExceptionForHR(hr);
                }
            }

            // Retrieve the selection (IShellItem)
            IShellItem shellItem;
            dialog.GetResult(out shellItem);
            if (shellItem == null) return null;

            // Convert to file system path
            IntPtr pszPath = IntPtr.Zero;
            shellItem.GetDisplayName(SIGDN_FILESYSPATH, out pszPath);
            if (pszPath == IntPtr.Zero) return null;

            string folderPath = Marshal.PtrToStringAuto(pszPath);
            Marshal.FreeCoTaskMem(pszPath);

            return folderPath;
        }
    }
"@
    Add-Type -TypeDefinition $modernFolderBrowserCode -Language CSharp
}

# 2) Define a PowerShell function that invokes our C# wrapper
function Show-ModernFolderPicker {
    param(
        [string]$Title = "Select a folder",
        [string]$InitialDirectory
    )
    # For a simple test, pass IntPtr.Zero as the parent window handle
    return [ModernFolderBrowser]::ShowDialog($Title, [IntPtr]::Zero, $InitialDirectory)
}

function Invoke-BrowseAction {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Folder', 'OpenFile', 'SaveFile')]
        [string]$Type,

        [string]$Title,
        [string]$Filter,
        [string]$InitialDirectory,
        [string]$FileName,
        [string]$DefaultExt,
        [switch]$AllowNewFile
    )

    switch ($Type) {
        'Folder' {
            return Show-ModernFolderPicker -Title $Title -InitialDirectory $InitialDirectory
        }
        'OpenFile' {
            $dialog = New-Object Microsoft.Win32.OpenFileDialog
            $dialog.Title = $Title
            if (-not [string]::IsNullOrWhiteSpace($Filter)) { $dialog.Filter = $Filter }
            if ($AllowNewFile) { $dialog.CheckFileExists = $false }
            if (-not [string]::IsNullOrWhiteSpace($InitialDirectory)) {
                $dialog.InitialDirectory = $InitialDirectory
            }
            if ($dialog.ShowDialog()) {
                return $dialog.FileName
            }
        }
        'SaveFile' {
            $dialog = New-Object Microsoft.Win32.SaveFileDialog
            $dialog.Title = $Title
            if (-not [string]::IsNullOrWhiteSpace($Filter)) { $dialog.Filter = $Filter }
            if ($AllowNewFile) { $dialog.CheckFileExists = $false } # This property is obsolete but used in existing code.
            if (-not [string]::IsNullOrWhiteSpace($InitialDirectory)) {
                $dialog.InitialDirectory = $InitialDirectory
            }
            if (-not [string]::IsNullOrWhiteSpace($FileName)) {
                $dialog.FileName = $FileName
            }
            if (-not [string]::IsNullOrWhiteSpace($DefaultExt)) {
                $dialog.DefaultExt = $DefaultExt
            }
            if ($dialog.ShowDialog()) {
                return $dialog.FileName
            }
        }
    }
    return $null
}

function Clear-ListViewContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$State,

        [Parameter(Mandatory = $true)]
        [System.Windows.Controls.ListView]$ListViewControl,

        [Parameter(Mandatory = $true)]
        [string]$ConfirmationTitle,

        [Parameter(Mandatory = $true)]
        [string]$ConfirmationMessage,
        
        [Parameter(Mandatory = $false)]
        [System.Collections.IList]$BackingDataList,

        [Parameter(Mandatory = $false)]
        [string]$StatusMessage,

        [Parameter(Mandatory = $false)]
        [System.Windows.Controls.TextBox[]]$TextBoxesToClear,

        [Parameter(Mandatory = $false)]
        [scriptblock]$PostClearAction
    )

    $result = [System.Windows.MessageBox]::Show($ConfirmationMessage, $ConfirmationTitle, [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
    if ($result -ne [System.Windows.MessageBoxResult]::Yes) {
        return
    }

    try {
        # If a backing data list is provided, clear it and rebind. This is the preferred method.
        if ($null -ne $BackingDataList) {
            $BackingDataList.Clear()
            $ListViewControl.ItemsSource = $BackingDataList.ToArray()
        }
        # If no backing list, determine how to clear the control.
        else {
            # If ItemsSource is in use, the only valid way to clear is to set it to null or an empty collection.
            if ($null -ne $ListViewControl.ItemsSource) {
                $ListViewControl.ItemsSource = $null
            }
            # If ItemsSource is NOT in use, we can safely clear the Items collection directly (for BYO Apps).
            elseif ($null -ne $ListViewControl.Items) {
                $ListViewControl.Items.Clear()
            }
        }
        
        $ListViewControl.Items.Refresh()

        # Clear any specified textboxes
        if ($null -ne $TextBoxesToClear) {
            foreach ($textBox in $TextBoxesToClear) {
                $textBox.Clear()
            }
        }

        # Update the status message if provided
        if (-not [string]::IsNullOrWhiteSpace($StatusMessage) -and $null -ne $State.Controls.txtStatus) {
            $State.Controls.txtStatus.Text = $StatusMessage
        }

        # Execute any post-clear custom actions. The scriptblock will have access to the $State and $ListViewControl variables from this function's scope.
        if ($null -ne $PostClearAction) {
            & $PostClearAction
        }
    }
    catch {
        WriteLog "Error in Clear-ListViewContent for $($ListViewControl.Name): $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show("An error occurred while clearing the list: $($_.Exception.Message)", "Error", "OK", "Error")
    }
}

Export-ModuleMember -Function *