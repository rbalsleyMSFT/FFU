<#
.SYNOPSIS
    VMware Workstation implementation of IHypervisorProvider

.DESCRIPTION
    Provides VMware Workstation Pro specific implementation of the hypervisor
    provider interface. Uses vmrest REST API for VM operations and diskpart
    for VHD operations (no Hyper-V dependency).

.NOTES
    Module: FFU.Hypervisor
    Version: 1.0.0
    Dependencies: VMware Workstation Pro 17.x
#>

class VMwareProvider : IHypervisorProvider {

    # VMware-specific properties
    hidden [int]$Port = 8697
    hidden [PSCredential]$Credential
    hidden [string]$VMwarePath
    hidden [bool]$ServiceStarted = $false

    # Constructor
    VMwareProvider() {
        $this.Name = 'VMware'
        $this.Version = $this.GetVMwareVersion()
        $this.Description = 'VMware Workstation Pro hypervisor provider'

        $this.Capabilities = @{
            SupportsTPM = $false                    # vTPM requires encryption (breaks vmrun automation)
            SupportsSecureBoot = $true              # UEFI Secure Boot supported
            SupportsGeneration2 = $true             # Similar to Hyper-V Gen2
            SupportsDynamicMemory = $false          # VMware uses static memory
            SupportsCheckpoints = $true             # Snapshots
            SupportsNestedVirtualization = $true
            SupportedDiskFormats = @('VMDK')        # VMDK required for bootable VMs (VHD not bootable)
            MaxMemoryGB = 128
            MaxProcessors = 32
            # NOTE: VMware vTPM requires VM encryption to function. Encrypted VMs cannot
            # be started with vmrun.exe (causes "operation was canceled" error).
            # For automated FFU builds, TPM is disabled. TPM features work on target hardware.
            TPMNote = 'VMware vTPM requires encryption which breaks automation. Disabled for FFU builds.'
        }

        # Auto-detect VMware installation
        $this.VMwarePath = $this.DetectVMwarePath()
    }

    # Constructor with custom port
    VMwareProvider([int]$Port) {
        $this.Name = 'VMware'
        $this.Version = $this.GetVMwareVersion()
        $this.Description = 'VMware Workstation Pro hypervisor provider'
        $this.Port = $Port

        $this.Capabilities = @{
            SupportsTPM = $false                    # vTPM requires encryption (breaks vmrun automation)
            SupportsSecureBoot = $true              # UEFI Secure Boot supported
            SupportsGeneration2 = $true             # Similar to Hyper-V Gen2
            SupportsDynamicMemory = $false          # VMware uses static memory
            SupportsCheckpoints = $true             # Snapshots
            SupportsNestedVirtualization = $true
            SupportedDiskFormats = @('VMDK')        # VMDK required for bootable VMs (VHD not bootable)
            MaxMemoryGB = 128
            MaxProcessors = 32
            TPMNote = 'VMware vTPM requires encryption which breaks automation. Disabled for FFU builds.'
        }

        $this.VMwarePath = $this.DetectVMwarePath()
    }

    # Detect VMware Workstation installation path
    hidden [string] DetectVMwarePath() {
        $regPaths = @(
            'HKLM:\SOFTWARE\VMware, Inc.\VMware Workstation',
            'HKLM:\SOFTWARE\WOW6432Node\VMware, Inc.\VMware Workstation'
        )

        foreach ($regPath in $regPaths) {
            if (Test-Path $regPath) {
                $installPath = (Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue).InstallPath
                if ($installPath -and (Test-Path $installPath)) {
                    return $installPath
                }
            }
        }

        # Try default paths
        $defaultPaths = @(
            'C:\Program Files (x86)\VMware\VMware Workstation',
            'C:\Program Files\VMware\VMware Workstation'
        )

        foreach ($path in $defaultPaths) {
            if (Test-Path $path) {
                return $path
            }
        }

        return $null
    }

    # Get VMware Workstation version
    hidden [string] GetVMwareVersion() {
        try {
            $installPath = $this.DetectVMwarePath()
            if ($installPath) {
                $vmwareExe = Join-Path $installPath 'vmware.exe'
                if (Test-Path $vmwareExe) {
                    $version = (Get-Item $vmwareExe).VersionInfo.ProductVersion
                    return $version
                }
            }
            return '0.0.0'
        }
        catch {
            return '0.0.0'
        }
    }

    # Set credentials for vmrest API authentication
    [void] SetCredential([PSCredential]$Credential) {
        $this.Credential = $Credential
    }

    # Ensure vmrest service is running
    hidden [void] EnsureVMrestRunning() {
        if (-not $this.ServiceStarted) {
            $result = Start-VMrestService -Port $this.Port -VMwarePath $this.VMwarePath -Credential $this.Credential
            if (-not $result.Success) {
                throw "Failed to start vmrest service: $($result.Error)"
            }
            $this.ServiceStarted = $true
        }
    }

    #region VM Lifecycle Methods

    [VMInfo] CreateVM([VMConfiguration]$Config) {
        # Validate configuration
        $validation = $this.ValidateConfiguration($Config)
        if (-not $validation.IsValid) {
            throw "Configuration validation failed: $($validation.Errors -join '; ')"
        }

        try {
            WriteLog "Creating VMware VM: $($Config.Name)"

            # Ensure vmrest is running
            $this.EnsureVMrestRunning()

            # Create VM folder
            $vmPath = $Config.Path
            if (-not (Test-Path $vmPath)) {
                New-Item -Path $vmPath -ItemType Directory -Force | Out-Null
            }

            # Determine disk path - VMware requires VMDK format for bootable VMs
            $diskPath = $Config.VirtualDiskPath
            if ([string]::IsNullOrEmpty($diskPath)) {
                # Always use VMDK for VMware (VHD is not bootable in VMware)
                $diskPath = Join-Path $vmPath "$($Config.Name).vmdk"
            }
            elseif ($diskPath.EndsWith('.vhd', [StringComparison]::OrdinalIgnoreCase)) {
                # Convert VHD path to VMDK - VMware cannot boot from VHD
                WriteLog "WARNING: VMware cannot boot from VHD files. Changing disk format to VMDK."
                $diskPath = [System.IO.Path]::ChangeExtension($diskPath, '.vmdk')
            }

            # Create virtual disk if it doesn't exist
            if (-not (Test-Path $diskPath)) {
                $sizeGB = [int]($Config.DiskSizeBytes / 1GB)
                if ($sizeGB -eq 0) { $sizeGB = 128 }  # Default 128GB

                if ($diskPath.EndsWith('.vmdk', [StringComparison]::OrdinalIgnoreCase)) {
                    # Create VMDK using VMware's vdiskmanager (native format, best performance)
                    WriteLog "Creating VMDK disk for VMware VM: $diskPath ($sizeGB GB)"
                    $diskPath = New-VMDKWithVdiskmanager -Path $diskPath -SizeGB $sizeGB -Type Dynamic -VMwarePath $this.VMwarePath
                }
                else {
                    # Fallback to VHD for non-boot scenarios (should not happen for VMs)
                    WriteLog "WARNING: Creating VHD disk - this is not bootable in VMware"
                    $diskPath = New-VHDWithDiskpart -Path $diskPath -SizeGB $sizeGB -Type Dynamic
                }
            }

            # Create VMX file
            # NOTE: TPM is disabled for VMware VMs because VMware's vTPM requires VM encryption
            # which breaks vmrun.exe automation. TPM features will work on target hardware after
            # FFU deployment. See New-VMwareVMX.ps1 for details.
            $memoryMB = [int]($Config.MemoryBytes / 1MB)

            # Log TPM configuration decision
            if ($Config.EnableTPM) {
                WriteLog "TPM Configuration: Requested=TRUE, Actual=FALSE (VMware vTPM requires encryption)"
                WriteLog "  - VMware vTPM requires full VM encryption to function"
                WriteLog "  - VM encryption breaks vmrun.exe automation (cannot start headless)"
                WriteLog "  - TPM-dependent features (BitLocker, Windows Hello) will work on target hardware"
            }
            else {
                WriteLog "TPM Configuration: Requested=FALSE, Actual=FALSE"
            }

            # Pass EnableTPM to New-VMwareVMX - it will handle the VMware-specific logic
            # and log appropriate warnings about why TPM is disabled
            $vmxPath = New-VMwareVMX -VMName $Config.Name `
                -VMPath $vmPath `
                -MemoryMB $memoryMB `
                -Processors $Config.ProcessorCount `
                -DiskPath $diskPath `
                -ISOPath $Config.ISOPath `
                -NetworkType 'bridged' `
                -EnableTPM $Config.EnableTPM `
                -EnableSecureBoot $Config.EnableSecureBoot

            # Note: We skip VM registration with vmrest/vmrun register
            # VMware VMs can be started directly from VMX path using vmrun start
            # Registration is optional and often fails with "operation not supported"
            WriteLog "VM created with VMX path: $vmxPath (skipping registration - will use direct VMX path)"

            # Create VMInfo with VMX path - no registration ID needed
            $vmInfo = [VMInfo]::new()
            $vmInfo.Name = $Config.Name
            $vmInfo.Id = $Config.Name  # Use name as ID since we're not registering
            $vmInfo.HypervisorType = 'VMware'
            $vmInfo.VMwareId = $Config.Name  # Use name as fallback ID
            $vmInfo.VMXPath = $vmxPath
            $vmInfo.VirtualDiskPath = $diskPath
            $vmInfo.ConfigurationPath = $vmxPath
            $vmInfo.State = [VMState]::Off

            WriteLog "VMware VM created successfully: $($Config.Name)"
            return $vmInfo
        }
        catch {
            WriteLog "ERROR in VMwareProvider.CreateVM: $($_.Exception.Message)"
            throw
        }
    }

    [void] StartVM([VMInfo]$VM) {
        # Default overload - runs headless (nogui)
        $this.StartVM($VM, $false)
    }

    [void] StartVM([VMInfo]$VM, [bool]$ShowConsole) {
        try {
            $this.EnsureVMrestRunning()

            $vmId = $this.ResolveVMId($VM)
            $vmxPath = $this.ResolveVMXPath($VM)

            if ($ShowConsole) {
                WriteLog "Starting VM with console window visible (gui mode)"
            }
            else {
                WriteLog "Starting VM in headless mode (nogui) - use -ShowVMConsole `$true to see console"
            }

            Set-VMwarePowerState -VMId $vmId -State 'on' -VMXPath $vmxPath -Port $this.Port -Credential $this.Credential -ShowConsole $ShowConsole

            WriteLog "VMware VM '$($VM.Name)' started"
        }
        catch {
            WriteLog "ERROR: Failed to start VM '$($VM.Name)': $($_.Exception.Message)"
            throw
        }
    }

    [void] StopVM([VMInfo]$VM, [bool]$Force) {
        try {
            $this.EnsureVMrestRunning()

            $vmId = $this.ResolveVMId($VM)
            $vmxPath = $this.ResolveVMXPath($VM)
            $state = if ($Force) { 'off' } else { 'shutdown' }

            Set-VMwarePowerState -VMId $vmId -State $state -VMXPath $vmxPath -Port $this.Port -Credential $this.Credential

            WriteLog "VMware VM '$($VM.Name)' stopped (force=$Force)"
        }
        catch {
            WriteLog "ERROR: Failed to stop VM '$($VM.Name)': $($_.Exception.Message)"
            throw
        }
    }

    [void] RemoveVM([VMInfo]$VM, [bool]$RemoveDisks) {
        try {
            # Stop VM if running (using vmrun - no REST API needed)
            $state = $this.GetVMState($VM)
            if ($state -eq [VMState]::Running) {
                WriteLog "Stopping running VM before removal..."
                $this.StopVM($VM, $true)
                Start-Sleep -Seconds 3
            }

            # Get VMX path for file deletion
            $vmxPath = $this.ResolveVMXPath($VM)

            # Try to unregister from vmrest if we have credentials (optional, may fail with 401)
            # Note: We skip registration in CreateVM, so unregistration may not be needed
            if ($this.Credential) {
                try {
                    $vmId = $this.ResolveVMId($VM)
                    Unregister-VMwareVM -VMId $vmId -Port $this.Port -Credential $this.Credential
                    WriteLog "VM unregistered from vmrest"
                }
                catch {
                    # 401 errors or "not registered" are expected when we skip registration
                    if ($_.Exception.Message -match '401' -or $_.Exception.Message -match 'Unauthorized' -or $_.Exception.Message -match 'not found') {
                        WriteLog "Skipping unregister (VM was not registered or no auth): $($_.Exception.Message)"
                    }
                    else {
                        WriteLog "WARNING: Unregister failed (continuing with file cleanup): $($_.Exception.Message)"
                    }
                }
            }

            # Remove files if requested
            if ($RemoveDisks) {
                $vmFolder = $null
                if (-not [string]::IsNullOrEmpty($vmxPath)) {
                    $vmFolder = Split-Path $vmxPath -Parent
                }
                elseif (-not [string]::IsNullOrEmpty($VM.ConfigurationPath)) {
                    $vmFolder = Split-Path $VM.ConfigurationPath -Parent
                }

                if ($vmFolder -and (Test-Path $vmFolder)) {
                    WriteLog "Removing VM files from: $vmFolder"
                    Remove-Item -Path $vmFolder -Recurse -Force -ErrorAction SilentlyContinue
                    WriteLog "VM files removed successfully"
                }
                else {
                    WriteLog "WARNING: VM folder not found for cleanup: $vmFolder"
                }
            }

            WriteLog "VMware VM '$($VM.Name)' removed"
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
            $this.EnsureVMrestRunning()

            $vmId = $this.ResolveVMId($VM)
            $ip = Get-VMwareVMIPAddress -VMId $vmId -Port $this.Port -Credential $this.Credential -TimeoutSeconds 120

            return $ip
        }
        catch {
            WriteLog "WARNING: Failed to get IP for VM '$($VM.Name)': $($_.Exception.Message)"
            return $null
        }
    }

    [VMState] GetVMState([VMInfo]$VM) {
        try {
            $this.EnsureVMrestRunning()

            $vmId = $this.ResolveVMId($VM)

            # Try REST API first if we have credentials
            if ($this.Credential) {
                try {
                    $powerState = Get-VMwarePowerState -VMId $vmId -Port $this.Port -Credential $this.Credential
                    return [VMInfo]::ConvertVMwareState($powerState)
                }
                catch {
                    # Check if this is a 401 Unauthorized - fall back to vmrun
                    if ($_.Exception.Message -match '401' -or $_.Exception.Message -match 'Unauthorized') {
                        WriteLog "REST API returned 401 for GetVMState - falling back to vmrun"
                    }
                    else {
                        throw  # Re-throw non-401 errors
                    }
                }
            }

            # Fallback to vmrun.exe (doesn't require authentication)
            $vmxPath = $this.ResolveVMXPath($VM)
            if (-not $vmxPath) {
                WriteLog "WARNING: Cannot determine VMX path for vmrun fallback"
                return [VMState]::Unknown
            }

            $powerState = Get-VMwarePowerStateWithVmrun -VMXPath $vmxPath
            return [VMInfo]::ConvertVMwareState($powerState)
        }
        catch {
            WriteLog "WARNING: GetVMState failed: $($_.Exception.Message)"
            return [VMState]::Unknown
        }
    }

    [VMInfo] GetVM([string]$Name) {
        try {
            $this.EnsureVMrestRunning()

            $vms = Get-VMwareVMList -Port $this.Port -Credential $this.Credential

            foreach ($vm in $vms) {
                # VMware REST API returns path, we need to match by name
                $vmxPath = $vm.path
                if ($vmxPath) {
                    $vmName = [System.IO.Path]::GetFileNameWithoutExtension($vmxPath)
                    if ($vmName -eq $Name) {
                        $vmInfo = [VMInfo]::new()
                        $vmInfo.Name = $vmName
                        $vmInfo.Id = $vm.id
                        $vmInfo.HypervisorType = 'VMware'
                        $vmInfo.VMwareId = $vm.id
                        $vmInfo.VMXPath = $vmxPath
                        $vmInfo.ConfigurationPath = $vmxPath

                        # Get power state
                        $powerState = Get-VMwarePowerState -VMId $vm.id -Port $this.Port -Credential $this.Credential
                        $vmInfo.State = [VMInfo]::ConvertVMwareState($powerState)

                        # Get IP if running
                        if ($vmInfo.State -eq [VMState]::Running) {
                            $ip = Get-VMwareVMIPAddress -VMId $vm.id -Port $this.Port -Credential $this.Credential -TimeoutSeconds 10
                            if ($ip) {
                                $vmInfo.IPAddress = $ip
                            }
                        }

                        return $vmInfo
                    }
                }
            }

            return $null
        }
        catch {
            return $null
        }
    }

    [VMInfo[]] GetAllVMs() {
        try {
            $this.EnsureVMrestRunning()

            $vms = Get-VMwareVMList -Port $this.Port -Credential $this.Credential
            $results = @()

            foreach ($vm in $vms) {
                $vmInfo = [VMInfo]::new()
                $vmInfo.Id = $vm.id
                $vmInfo.HypervisorType = 'VMware'
                $vmInfo.VMwareId = $vm.id

                if ($vm.path) {
                    $vmInfo.Name = [System.IO.Path]::GetFileNameWithoutExtension($vm.path)
                    $vmInfo.VMXPath = $vm.path
                    $vmInfo.ConfigurationPath = $vm.path
                }

                $results += $vmInfo
            }

            return $results
        }
        catch {
            return @()
        }
    }

    # Helper to resolve VM ID from VMInfo
    hidden [string] ResolveVMId([VMInfo]$VM) {
        if (-not [string]::IsNullOrEmpty($VM.VMwareId)) {
            return $VM.VMwareId
        }

        if (-not [string]::IsNullOrEmpty($VM.Id)) {
            return $VM.Id
        }

        # Try to find by name
        $foundVM = $this.GetVM($VM.Name)
        if ($foundVM -and $foundVM.VMwareId) {
            return $foundVM.VMwareId
        }

        throw "Cannot resolve VMware VM ID for '$($VM.Name)'"
    }

    # Helper to resolve VMX path from VMInfo (needed for vmrun.exe fallback)
    hidden [string] ResolveVMXPath([VMInfo]$VM) {
        if (-not [string]::IsNullOrEmpty($VM.VMXPath)) {
            return $VM.VMXPath
        }

        if (-not [string]::IsNullOrEmpty($VM.ConfigurationPath)) {
            return $VM.ConfigurationPath
        }

        # Try to find by name
        $foundVM = $this.GetVM($VM.Name)
        if ($foundVM -and $foundVM.VMXPath) {
            return $foundVM.VMXPath
        }

        WriteLog "WARNING: Cannot resolve VMX path for '$($VM.Name)'. vmrun.exe fallback will not work."
        return $null
    }

    #endregion

    #region Disk Operations

    [string] NewVirtualDisk([string]$Path, [uint64]$SizeBytes, [string]$Format, [string]$Type) {
        try {
            $sizeGB = [int]($SizeBytes / 1GB)
            if ($sizeGB -lt 1) { $sizeGB = 1 }

            # For VMware, prefer VMDK but support VHD for compatibility
            if ($Format -eq 'VHD' -or $Path.EndsWith('.vhd', [StringComparison]::OrdinalIgnoreCase)) {
                $vhdPath = New-VHDWithDiskpart -Path $Path -SizeGB $sizeGB -Type $Type
                WriteLog "Created VHD disk: $vhdPath ($sizeGB GB)"
                return $vhdPath
            }
            else {
                # For VMDK, use vmware-vdiskmanager
                throw "VMDK creation not yet implemented. Please use VHD format."
            }
        }
        catch {
            WriteLog "ERROR: Failed to create virtual disk: $($_.Exception.Message)"
            throw
        }
    }

    [string] MountVirtualDisk([string]$Path) {
        try {
            $driveLetter = Mount-VHDWithDiskpart -Path $Path
            WriteLog "Mounted virtual disk $Path at $driveLetter"
            return $driveLetter
        }
        catch {
            WriteLog "ERROR: Failed to mount virtual disk: $($_.Exception.Message)"
            throw
        }
    }

    [void] DismountVirtualDisk([string]$Path) {
        try {
            Dismount-VHDWithDiskpart -Path $Path
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
            if (-not (Test-Path $ISOPath)) {
                throw "ISO file not found: $ISOPath"
            }

            # Update VMX file with ISO
            $vmxPath = $VM.VMXPath
            if ([string]::IsNullOrEmpty($vmxPath)) {
                $vmxPath = $VM.ConfigurationPath
            }

            if ([string]::IsNullOrEmpty($vmxPath) -or -not (Test-Path $vmxPath)) {
                throw "VMX file not found for VM '$($VM.Name)'"
            }

            Set-VMwareBootISO -VMXPath $vmxPath -ISOPath $ISOPath
            WriteLog "Attached ISO to VM '$($VM.Name)': $ISOPath"
        }
        catch {
            WriteLog "ERROR: Failed to attach ISO: $($_.Exception.Message)"
            throw
        }
    }

    [void] DetachISO([VMInfo]$VM) {
        try {
            $vmxPath = $VM.VMXPath
            if ([string]::IsNullOrEmpty($vmxPath)) {
                $vmxPath = $VM.ConfigurationPath
            }

            if ([string]::IsNullOrEmpty($vmxPath) -or -not (Test-Path $vmxPath)) {
                throw "VMX file not found for VM '$($VM.Name)'"
            }

            Remove-VMwareBootISO -VMXPath $vmxPath
            WriteLog "Detached ISO from VM '$($VM.Name)'"
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
            # Check VMware Workstation installation
            if ([string]::IsNullOrEmpty($this.VMwarePath) -or -not (Test-Path $this.VMwarePath)) {
                return $false
            }

            # Check vmrun exists
            $vmrunPath = Join-Path $this.VMwarePath 'vmrun.exe'
            if (-not (Test-Path $vmrunPath)) {
                return $false
            }

            # Check vmrest exists
            $vmrestPath = Join-Path $this.VMwarePath 'vmrest.exe'
            if (-not (Test-Path $vmrestPath)) {
                return $false
            }

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

        # Check installation
        if ([string]::IsNullOrEmpty($this.VMwarePath)) {
            $result.Issues += "VMware Workstation Pro not found in registry or default locations"
        }
        elseif (-not (Test-Path $this.VMwarePath)) {
            $result.Issues += "VMware Workstation installation path not found: $($this.VMwarePath)"
        }
        else {
            $result.Details['InstallPath'] = $this.VMwarePath
        }

        # Check vmrun
        if ($this.VMwarePath) {
            $vmrunPath = Join-Path $this.VMwarePath 'vmrun.exe'
            if (-not (Test-Path $vmrunPath)) {
                $result.Issues += "vmrun.exe not found"
            }
            else {
                $result.Details['vmrun'] = 'Available'
            }
        }

        # Check vmrest
        if ($this.VMwarePath) {
            $vmrestPath = Join-Path $this.VMwarePath 'vmrest.exe'
            if (-not (Test-Path $vmrestPath)) {
                $result.Issues += "vmrest.exe not found (required for REST API)"
            }
            else {
                $result.Details['vmrest'] = 'Available'
            }
        }

        # Check vmrest credentials
        # VMware 17.x uses 'vmrest.cfg', older versions use '.vmrestCfg'
        $configPaths = @(
            (Join-Path $env:USERPROFILE 'vmrest.cfg'),
            (Join-Path $env:USERPROFILE '.vmrestCfg')
        )
        $credentialsFound = $configPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $credentialsFound) {
            $result.Issues += "vmrest credentials not configured. Run 'vmrest.exe -C' to set up."
        }
        else {
            $result.Details['vmrestCredentials'] = 'Configured'
        }

        # Check version
        if ($this.Version -ne '0.0.0') {
            $result.Details['Version'] = $this.Version

            # Check minimum version (17.0 required)
            $majorVersion = [int]($this.Version.Split('.')[0])
            if ($majorVersion -lt 17) {
                $result.Issues += "VMware Workstation 17.x or later required (found: $($this.Version))"
            }
        }

        $result.IsAvailable = ($result.Issues.Count -eq 0)
        return $result
    }

    #endregion

    #region Override ValidateConfiguration

    [hashtable] ValidateConfiguration([VMConfiguration]$Config) {
        # Call base validation
        $result = ([IHypervisorProvider]$this).ValidateConfiguration($Config)

        # VMware-specific validation

        # Check disk format - VMware prefers VMDK but supports VHD
        if ($Config.DiskFormat -eq 'VHDX') {
            $result.IsValid = $false
            $result.Errors += "VHDX format not supported by VMware. Use VHD or VMDK."
        }

        # Check TPM requirements - VMware vTPM requires encryption which breaks automation
        if ($Config.EnableTPM) {
            # VMware vTPM requires VM encryption which breaks vmrun.exe automation
            # We'll disable TPM in the VMX but log a warning here
            $result.Warnings += @(
                "VMware vTPM requires VM encryption which breaks vmrun.exe automation.",
                "TPM will be disabled for this VMware VM build.",
                "TPM-dependent features (BitLocker, Windows Hello) will work on target hardware after FFU deployment."
            )
        }

        return $result
    }

    #endregion
}

# Helper function to create VMware provider instance
function New-VMwareProvider {
    param(
        [int]$Port = 8697
    )
    return [VMwareProvider]::new($Port)
}
