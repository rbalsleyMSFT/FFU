<#
.SYNOPSIS
    Hyper-V implementation of IHypervisorProvider

.DESCRIPTION
    Provides Hyper-V specific implementation of the hypervisor provider interface.
    Wraps native Hyper-V PowerShell cmdlets to provide VM operations.

.NOTES
    Module: FFU.Hypervisor
    Version: 1.0.0
    Dependencies: Hyper-V PowerShell module
#>

class HyperVProvider : IHypervisorProvider {

    # Constructor
    HyperVProvider() {
        $this.Name = 'HyperV'
        $this.Version = $this.GetHyperVVersion()
        $this.Description = 'Microsoft Hyper-V hypervisor provider'

        $this.Capabilities = @{
            SupportsTPM = $true
            SupportsSecureBoot = $true
            SupportsGeneration2 = $true
            SupportsDynamicMemory = $true
            SupportsCheckpoints = $true
            SupportsNestedVirtualization = $true
            SupportedDiskFormats = @('VHD', 'VHDX')
            MaxMemoryGB = 1024  # Depends on host, this is a reasonable max
            MaxProcessors = 64  # Depends on host
        }
    }

    # Get Hyper-V version
    hidden [string] GetHyperVVersion() {
        try {
            $hyperVService = Get-Service -Name vmms -ErrorAction SilentlyContinue
            if ($hyperVService) {
                $version = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuild
                return "10.0.$version"
            }
            return '0.0.0'
        }
        catch {
            return '0.0.0'
        }
    }

    #region VM Lifecycle Methods

    [VMInfo] CreateVM([VMConfiguration]$Config) {
        # Validate configuration
        $validation = $this.ValidateConfiguration($Config)
        if (-not $validation.IsValid) {
            throw "Configuration validation failed: $($validation.Errors -join '; ')"
        }

        $vmCreated = $false
        $guardianCreated = $false

        try {
            # Create new Gen2 VM
            WriteLog "Creating Hyper-V VM: $($Config.Name)"
            $vmParams = @{
                Name = $Config.Name
                Path = $Config.Path
                MemoryStartupBytes = $Config.MemoryBytes
                VHDPath = $Config.VirtualDiskPath
                Generation = $Config.Generation
                ErrorAction = 'Stop'
            }

            $nativeVM = New-VM @vmParams
            $vmCreated = $true
            WriteLog "VM created successfully"

            # Configure processor
            Set-VMProcessor -VMName $Config.Name -Count $Config.ProcessorCount -ErrorAction Stop
            WriteLog "VM processor configured: $($Config.ProcessorCount) cores"

            # Configure memory settings
            if (-not $Config.DynamicMemory) {
                Set-VM -Name $Config.Name -StaticMemory -ErrorAction Stop
            }

            # Disable automatic checkpoints
            if (-not $Config.AutomaticCheckpoints) {
                Set-VM -Name $Config.Name -AutomaticCheckpointsEnabled $false -ErrorAction Stop
            }

            # Mount ISO if provided
            if (-not [string]::IsNullOrEmpty($Config.ISOPath)) {
                Add-VMDvdDrive -VMName $Config.Name -Path $Config.ISOPath -ErrorAction Stop
                WriteLog "ISO mounted: $($Config.ISOPath)"
            }

            # Set Hard Drive as boot device
            $vmHardDiskDrive = Get-VMHarddiskdrive -VMName $Config.Name -ErrorAction Stop
            Set-VMFirmware -VMName $Config.Name -FirstBootDevice $vmHardDiskDrive -ErrorAction Stop
            WriteLog "VM boot configuration set"

            # Configure TPM if enabled and supported
            if ($Config.EnableTPM) {
                try {
                    New-HgsGuardian -Name $Config.Name -GenerateCertificates -ErrorAction Stop
                    $guardianCreated = $true
                    $owner = Get-HgsGuardian -Name $Config.Name -ErrorAction Stop
                    $kp = New-HgsKeyProtector -Owner $owner -AllowUntrustedRoot -ErrorAction Stop
                    Set-VMKeyProtector -VMName $Config.Name -KeyProtector $kp.RawData -ErrorAction Stop
                    Enable-VMTPM -VMName $Config.Name -ErrorAction Stop
                    WriteLog "TPM configured successfully"
                }
                catch {
                    WriteLog "WARNING: TPM configuration failed (non-critical): $($_.Exception.Message)"
                    WriteLog "VM will continue without TPM. Some Windows features may be limited."
                }
            }

            # Connect network adapter to virtual switch if specified
            if (-not [string]::IsNullOrEmpty($Config.NetworkSwitchName)) {
                WriteLog "Configuring network adapter..."
                WriteLog "  Switch name: $($Config.NetworkSwitchName)"

                # Verify switch exists
                $vmSwitch = Get-VMSwitch -Name $Config.NetworkSwitchName -ErrorAction SilentlyContinue
                if (-not $vmSwitch) {
                    throw "Virtual switch '$($Config.NetworkSwitchName)' not found. Please verify the switch name in your configuration."
                }

                # Connect the VM's network adapter to the switch
                $networkAdapter = Get-VMNetworkAdapter -VMName $Config.Name -ErrorAction Stop
                if ($networkAdapter) {
                    Connect-VMNetworkAdapter -VMNetworkAdapter $networkAdapter -SwitchName $Config.NetworkSwitchName -ErrorAction Stop
                    WriteLog "  Network adapter connected to switch: $($Config.NetworkSwitchName)"
                }
                else {
                    WriteLog "  WARNING: No network adapter found on VM - adding one"
                    Add-VMNetworkAdapter -VMName $Config.Name -SwitchName $Config.NetworkSwitchName -ErrorAction Stop
                    WriteLog "  Network adapter added and connected to switch: $($Config.NetworkSwitchName)"
                }
            }
            else {
                WriteLog "No network switch specified - network adapter not connected"
            }

            # Connect to VM console
            WriteLog "Starting vmconnect localhost $($Config.Name)"
            & vmconnect localhost $Config.Name

            # Start VM
            Start-VM -Name $Config.Name -ErrorAction Stop
            WriteLog "VM started successfully"

            # Return VMInfo
            $createdVM = Get-VM -Name $Config.Name -ErrorAction Stop
            return [VMInfo]::new($createdVM)
        }
        catch {
            WriteLog "ERROR in HyperVProvider.CreateVM: $($_.Exception.Message)"

            # Cleanup on failure
            if ($vmCreated) {
                WriteLog "Attempting cleanup of failed VM creation..."
                try {
                    Stop-VM -Name $Config.Name -Force -TurnOff -ErrorAction SilentlyContinue
                    Remove-VM -Name $Config.Name -Force -ErrorAction SilentlyContinue
                    WriteLog "Failed VM removed"
                }
                catch {
                    WriteLog "WARNING: Failed to cleanup VM: $($_.Exception.Message)"
                }
            }

            if ($guardianCreated) {
                try {
                    Remove-HgsGuardian -Name $Config.Name -ErrorAction SilentlyContinue
                    WriteLog "HGS Guardian removed"
                }
                catch {
                    WriteLog "WARNING: Failed to cleanup HGS Guardian: $($_.Exception.Message)"
                }
            }

            throw
        }
    }

    [string] StartVM([VMInfo]$VM) {
        # Default overload - calls with ShowConsole=$false
        return $this.StartVM($VM, $false)
    }

    [string] StartVM([VMInfo]$VM, [bool]$ShowConsole) {
        try {
            # Hyper-V VMs are always visible via Hyper-V Manager
            # ShowConsole parameter is ignored for Hyper-V but logged for visibility
            if ($ShowConsole) {
                WriteLog "Note: ShowConsole=true has no effect for Hyper-V (use Hyper-V Manager to view console)"
            }
            Start-VM -Name $VM.Name -ErrorAction Stop
            WriteLog "VM '$($VM.Name)' started"
            # Hyper-V Start-VM returns immediately, VM is always 'Running' after this
            return 'Running'
        }
        catch {
            WriteLog "ERROR: Failed to start VM '$($VM.Name)': $($_.Exception.Message)"
            throw
        }
    }

    [void] StopVM([VMInfo]$VM, [bool]$Force) {
        try {
            if ($Force) {
                Stop-VM -Name $VM.Name -Force -TurnOff -ErrorAction Stop
                WriteLog "VM '$($VM.Name)' force stopped"
            }
            else {
                Stop-VM -Name $VM.Name -ErrorAction Stop
                WriteLog "VM '$($VM.Name)' stopped gracefully"
            }
        }
        catch {
            WriteLog "ERROR: Failed to stop VM '$($VM.Name)': $($_.Exception.Message)"
            throw
        }
    }

    [void] RemoveVM([VMInfo]$VM, [bool]$RemoveDisks) {
        try {
            # Stop VM if running
            $currentVM = Get-VM -Name $VM.Name -ErrorAction SilentlyContinue
            if ($currentVM -and $currentVM.State -eq 'Running') {
                Stop-VM -Name $VM.Name -Force -TurnOff -ErrorAction SilentlyContinue
            }

            # Get VM path before removal
            $vmPath = $currentVM.Path

            # Remove the VM
            Remove-VM -Name $VM.Name -Force -ErrorAction Stop
            WriteLog "VM '$($VM.Name)' removed"

            # Remove HGS Guardian if exists
            try {
                Remove-HgsGuardian -Name $VM.Name -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            }
            catch {
                # Ignore - may not exist
            }

            # Clean up HGS Guardian certificates
            $certPath = 'Cert:\LocalMachine\Shielded VM Local Certificates\'
            if (Test-Path -Path $certPath) {
                $certs = Get-ChildItem -Path $certPath -Recurse -ErrorAction SilentlyContinue |
                    Where-Object { $_.Subject -like "*$($VM.Name)*" }
                foreach ($cert in $certs) {
                    try {
                        Remove-Item -Path $cert.PSPath -Force -ErrorAction SilentlyContinue
                    }
                    catch {
                        WriteLog "WARNING: Failed to remove certificate: $($_.Exception.Message)"
                    }
                }
            }

            # Remove VM folder if RemoveDisks is true
            if ($RemoveDisks -and -not [string]::IsNullOrWhiteSpace($vmPath)) {
                Remove-Item -Path $vmPath -Force -Recurse -ErrorAction SilentlyContinue
                WriteLog "VM files removed from: $vmPath"
            }
        }
        catch {
            WriteLog "ERROR: Failed to remove VM '$($VM.Name)': $($_.Exception.Message)"
            throw
        }
    }

    #endregion

    #region VM Information Methods

    [string] GetVMIPAddress([VMInfo]$VM) {
        try {
            $nativeVM = Get-VM -Name $VM.Name -ErrorAction Stop
            $networkAdapters = Get-VMNetworkAdapter -VM $nativeVM -ErrorAction Stop

            foreach ($adapter in $networkAdapters) {
                $ips = $adapter.IPAddresses | Where-Object { $_ -notmatch ':' } # Filter IPv6
                if ($ips.Count -gt 0) {
                    return $ips[0]
                }
            }

            return $null
        }
        catch {
            WriteLog "WARNING: Failed to get IP for VM '$($VM.Name)': $($_.Exception.Message)"
            return $null
        }
    }

    [VMState] GetVMState([VMInfo]$VM) {
        try {
            $nativeVM = Get-VM -Name $VM.Name -ErrorAction Stop
            return [VMInfo]::ConvertHyperVState($nativeVM.State)
        }
        catch {
            return [VMState]::Unknown
        }
    }

    [VMInfo] GetVM([string]$Name) {
        try {
            $nativeVM = Get-VM -Name $Name -ErrorAction Stop
            return [VMInfo]::new($nativeVM)
        }
        catch {
            return $null
        }
    }

    [VMInfo[]] GetAllVMs() {
        try {
            $vms = Get-VM -ErrorAction Stop
            $results = @()
            foreach ($vm in $vms) {
                $results += [VMInfo]::new($vm)
            }
            return $results
        }
        catch {
            return @()
        }
    }

    <#
    .SYNOPSIS
        Wait for VM to reach specified state using event-driven monitoring.
    .DESCRIPTION
        Uses CIM event subscription instead of polling for efficient state monitoring.
        This method delegates to Wait-VMStateChange which subscribes to Msvm_ComputerSystem
        state change events via Register-CimIndicationEvent.
    .PARAMETER VM
        VMInfo object or object with VMName property representing the VM to monitor.
    .PARAMETER TargetState
        Target state to wait for: Running, Off, Paused, Saved.
    .PARAMETER TimeoutSeconds
        Maximum time to wait for state change. Default is 3600 (1 hour).
    .RETURNS
        True if target state reached, False if timeout exceeded.
    .NOTES
        PERF-02: Event-driven VM state monitoring for Hyper-V
    #>
    [bool] WaitForState([object]$VM, [string]$TargetState, [int]$TimeoutSeconds) {
        # Extract VM name - handle VMInfo, native VM objects, or any object with Name/VMName property
        # Using string type check to avoid type resolution issues when Hyper-V module isn't loaded
        $vmType = $VM.GetType().FullName
        $vmName = if ($vmType -like '*HyperV*VirtualMachine*') {
            $VM.Name
        } elseif ($VM.VMName) {
            $VM.VMName
        } else {
            $VM.Name
        }

        # Delegate to event-driven function
        return Wait-VMStateChange -VMName $vmName -TargetState $TargetState -TimeoutSeconds $TimeoutSeconds
    }

    #endregion

    #region Disk Operations

    [string] NewVirtualDisk([string]$Path, [uint64]$SizeBytes, [string]$Format, [string]$Type) {
        try {
            $params = @{
                Path = $Path
                SizeBytes = $SizeBytes
                ErrorAction = 'Stop'
            }

            if ($Type -eq 'Fixed') {
                $params['Fixed'] = $true
            }
            else {
                $params['Dynamic'] = $true
            }

            # Adjust extension based on format
            if ($Format -eq 'VHD' -and $Path -notlike '*.vhd') {
                $Path = [System.IO.Path]::ChangeExtension($Path, '.vhd')
                $params['Path'] = $Path
            }
            elseif ($Format -eq 'VHDX' -and $Path -notlike '*.vhdx') {
                $Path = [System.IO.Path]::ChangeExtension($Path, '.vhdx')
                $params['Path'] = $Path
            }

            New-VHD @params | Out-Null
            WriteLog "Created virtual disk: $Path ($([math]::Round($SizeBytes/1GB, 2))GB $Type)"
            return $Path
        }
        catch {
            WriteLog "ERROR: Failed to create virtual disk: $($_.Exception.Message)"
            throw
        }
    }

    [string] MountVirtualDisk([string]$Path) {
        try {
            $disk = Mount-VHD -Path $Path -Passthru -ErrorAction Stop
            $partitions = $disk | Get-Disk | Get-Partition | Where-Object { $_.Type -ne 'Reserved' }

            $driveLetter = $null
            $maxRetries = 3

            foreach ($partition in $partitions) {
                if ($partition.DriveLetter) {
                    $driveLetter = $partition.DriveLetter
                    break
                }
            }

            # No drive letter assigned, try to assign one with retry logic
            if (-not $driveLetter) {
                $partition = $partitions | Select-Object -First 1
                if ($partition) {
                    $retryDelay = 500

                    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
                        try {
                            # Prefer W, fallback to Z-downward
                            $preferredLetters = @('W') + (90..68 | ForEach-Object { [char]$_ })
                            $availableLetter = $preferredLetters |
                                Where-Object { -not (Test-Path "$($_):") } | Select-Object -First 1

                            if ($availableLetter) {
                                WriteLog "Assigning drive letter $availableLetter (attempt $attempt/$maxRetries)"
                                Set-Partition -DiskNumber $partition.DiskNumber -PartitionNumber $partition.PartitionNumber `
                                    -NewDriveLetter $availableLetter -ErrorAction Stop
                                $driveLetter = $availableLetter
                                break
                            }
                        }
                        catch {
                            WriteLog "WARNING: Drive letter assignment attempt $attempt failed: $($_.Exception.Message)"
                            if ($attempt -lt $maxRetries) {
                                Start-Sleep -Milliseconds $retryDelay
                                $retryDelay *= 2  # Exponential backoff
                            }
                        }
                    }
                }
            }

            if (-not $driveLetter) {
                throw "Unable to assign drive letter to mounted VHD after $maxRetries attempts"
            }

            # Verify drive letter is accessible
            $drivePath = "$($driveLetter):\"
            if (-not (Test-Path $drivePath)) {
                WriteLog "WARNING: Drive letter assigned but path not accessible, waiting..."
                Start-Sleep -Milliseconds 500
                if (-not (Test-Path $drivePath)) {
                    throw "Drive letter $driveLetter assigned but path $drivePath not accessible"
                }
            }

            WriteLog "Mounted virtual disk $Path at $drivePath (verified accessible)"
            return $drivePath
        }
        catch {
            WriteLog "ERROR: Failed to mount virtual disk: $($_.Exception.Message)"
            throw
        }
    }

    [void] DismountVirtualDisk([string]$Path) {
        try {
            Dismount-VHD -Path $Path -ErrorAction Stop
            WriteLog "Dismounted virtual disk: $Path"
        }
        catch {
            WriteLog "ERROR: Failed to dismount virtual disk: $($_.Exception.Message)"
            throw
        }
    }

    #endregion

    #region Media Operations

    [void] AttachISO([VMInfo]$VM, [string]$ISOPath) {
        try {
            WriteLog "=== Configuring capture boot for Hyper-V VM ==="
            WriteLog "  VM Name: $($VM.Name)"
            WriteLog "  ISO Path: $ISOPath"

            # 1. Log current boot configuration before changes
            $currentFirmware = Get-VMFirmware -VMName $VM.Name -ErrorAction SilentlyContinue
            if ($currentFirmware) {
                $firstBoot = $currentFirmware.FirstBootDevice
                if ($firstBoot) {
                    $deviceType = $firstBoot.GetType().Name
                    WriteLog "  BEFORE - First boot device type: $deviceType"
                    if ($firstBoot.Path) {
                        WriteLog "  BEFORE - First boot device path: $($firstBoot.Path)"
                    }
                }
                else {
                    WriteLog "  BEFORE - No explicit first boot device set"
                }
            }

            # 2. Add DVD drive with capture ISO
            WriteLog "  Step 1: Adding DVD drive with capture ISO..."
            Add-VMDvdDrive -VMName $VM.Name -Path $ISOPath -ErrorAction Stop
            WriteLog "  Step 1 COMPLETE: DVD drive added successfully"

            # 3. Get the DVD drive we just added
            WriteLog "  Step 2: Retrieving DVD drive for boot configuration..."
            $dvdDrive = Get-VMDvdDrive -VMName $VM.Name -ErrorAction Stop | Where-Object { $_.Path -eq $ISOPath }
            if (-not $dvdDrive) {
                # Fallback: get the first DVD drive with any path set
                $dvdDrive = Get-VMDvdDrive -VMName $VM.Name -ErrorAction Stop | Where-Object { $_.Path } | Select-Object -First 1
            }
            if (-not $dvdDrive) {
                throw "Failed to retrieve DVD drive after adding it. Cannot set boot order."
            }
            WriteLog "  Step 2 COMPLETE: DVD drive found at Controller $($dvdDrive.ControllerNumber), Location $($dvdDrive.ControllerLocation)"

            # 4. CRITICAL: Set DVD as first boot device
            WriteLog "  Step 3: Setting DVD drive as FIRST boot device (CRITICAL for capture)..."
            Set-VMFirmware -VMName $VM.Name -FirstBootDevice $dvdDrive -ErrorAction Stop
            WriteLog "  Step 3 COMPLETE: Boot order configured - DVD is now first boot device"

            # 5. Verify boot configuration change
            WriteLog "  Step 4: Verifying boot configuration..."
            $newFirmware = Get-VMFirmware -VMName $VM.Name -ErrorAction SilentlyContinue
            if ($newFirmware -and $newFirmware.FirstBootDevice) {
                $newFirstBoot = $newFirmware.FirstBootDevice
                $newDeviceType = $newFirstBoot.GetType().Name
                WriteLog "  AFTER - First boot device type: $newDeviceType"
                if ($newFirstBoot.Path) {
                    WriteLog "  AFTER - First boot device path: $($newFirstBoot.Path)"
                }

                # Check if it's actually a DVD drive
                if ($newDeviceType -like '*DvdDrive*' -or $newDeviceType -like '*DVD*') {
                    WriteLog "  VERIFIED: VM will boot from DVD/ISO (capture media)"
                }
                elseif ($newFirstBoot.Path -eq $ISOPath) {
                    WriteLog "  VERIFIED: First boot device path matches capture ISO"
                }
                else {
                    WriteLog "  WARNING: First boot device may not be the DVD drive!"
                    WriteLog "  WARNING: Device type is: $newDeviceType"
                }
            }
            else {
                WriteLog "  WARNING: Could not verify boot configuration after change"
            }

            WriteLog "=== Capture boot configuration complete ==="
            WriteLog "Attached ISO to VM '$($VM.Name)': $ISOPath"
        }
        catch {
            WriteLog "ERROR: Failed to configure capture boot: $($_.Exception.Message)"
            WriteLog "ERROR: Stack trace: $($_.ScriptStackTrace)"
            throw
        }
    }

    [void] DetachISO([VMInfo]$VM) {
        try {
            $dvdDrives = Get-VMDvdDrive -VMName $VM.Name -ErrorAction Stop
            foreach ($drive in $dvdDrives) {
                Remove-VMDvdDrive -VMName $VM.Name -ControllerNumber $drive.ControllerNumber `
                    -ControllerLocation $drive.ControllerLocation -ErrorAction Stop
            }
            WriteLog "Detached all ISO drives from VM '$($VM.Name)'"
        }
        catch {
            WriteLog "ERROR: Failed to detach ISO: $($_.Exception.Message)"
            throw
        }
    }

    #endregion

    #region Availability Methods

    [bool] TestAvailable() {
        try {
            # Check if Hyper-V service is running
            $service = Get-Service -Name vmms -ErrorAction SilentlyContinue
            if (-not $service -or $service.Status -ne 'Running') {
                return $false
            }

            # Check if Hyper-V module is available
            $module = Get-Module -Name Hyper-V -ListAvailable -ErrorAction SilentlyContinue
            if (-not $module) {
                return $false
            }

            # Try to execute a simple Hyper-V command
            $null = Get-VM -ErrorAction Stop
            return $true
        }
        catch {
            return $false
        }
    }

    [hashtable] GetAvailabilityDetails() {
        $result = @{
            IsAvailable = $false
            ProviderName = $this.Name
            ProviderVersion = $this.Version
            Issues = @()
            Details = @{}
        }

        # Check service
        $service = Get-Service -Name vmms -ErrorAction SilentlyContinue
        if (-not $service) {
            $result.Issues += "Hyper-V Virtual Machine Management service (vmms) not found"
        }
        elseif ($service.Status -ne 'Running') {
            $result.Issues += "Hyper-V service is not running (current status: $($service.Status))"
        }
        else {
            $result.Details['ServiceStatus'] = 'Running'
        }

        # Check module
        $module = Get-Module -Name Hyper-V -ListAvailable -ErrorAction SilentlyContinue
        if (-not $module) {
            $result.Issues += "Hyper-V PowerShell module not installed"
        }
        else {
            $result.Details['ModuleVersion'] = $module.Version.ToString()
        }

        # Check feature
        try {
            $feature = Get-WindowsOptionalFeature -FeatureName Microsoft-Hyper-V -Online -ErrorAction Stop
            if ($feature.State -ne 'Enabled') {
                $result.Issues += "Hyper-V feature not enabled"
            }
            else {
                $result.Details['FeatureState'] = 'Enabled'
            }
        }
        catch {
            $result.Issues += "Unable to check Hyper-V feature state: $($_.Exception.Message)"
        }

        $result.IsAvailable = ($result.Issues.Count -eq 0)
        return $result
    }

    #endregion
}

# Helper function to create HyperV provider instance
function New-HyperVProvider {
    return [HyperVProvider]::new()
}
