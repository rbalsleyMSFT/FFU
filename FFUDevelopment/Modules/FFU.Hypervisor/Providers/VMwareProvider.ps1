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
            SupportsTPM = $true                     # Virtual TPM supported
            SupportsSecureBoot = $true              # UEFI Secure Boot supported
            SupportsGeneration2 = $true             # Similar to Hyper-V Gen2
            SupportsDynamicMemory = $false          # VMware uses static memory
            SupportsCheckpoints = $true             # Snapshots
            SupportsNestedVirtualization = $true
            SupportedDiskFormats = @('VHD', 'VMDK') # VHD supported with some limitations
            MaxMemoryGB = 128
            MaxProcessors = 32
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
            SupportsTPM = $true
            SupportsSecureBoot = $true
            SupportsGeneration2 = $true
            SupportsDynamicMemory = $false
            SupportsCheckpoints = $true
            SupportsNestedVirtualization = $true
            SupportedDiskFormats = @('VHD', 'VMDK')
            MaxMemoryGB = 128
            MaxProcessors = 32
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

    # Ensure vmrest service is running
    hidden [void] EnsureVMrestRunning() {
        if (-not $this.ServiceStarted) {
            $result = Start-VMrestService -Port $this.Port -VMwarePath $this.VMwarePath
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

            # Determine disk path and format
            $diskPath = $Config.VirtualDiskPath
            if ([string]::IsNullOrEmpty($diskPath)) {
                $diskPath = Join-Path $vmPath "$($Config.Name).vhd"
            }

            # Create virtual disk if it doesn't exist
            if (-not (Test-Path $diskPath)) {
                $sizeGB = [int]($Config.DiskSizeBytes / 1GB)
                if ($sizeGB -eq 0) { $sizeGB = 128 }  # Default 128GB
                $diskPath = New-VHDWithDiskpart -Path $diskPath -SizeGB $sizeGB -Type Dynamic
            }

            # Create VMX file
            $memoryMB = [int]($Config.MemoryBytes / 1MB)
            $vmxPath = New-VMwareVMX -VMName $Config.Name `
                -VMPath $vmPath `
                -MemoryMB $memoryMB `
                -Processors $Config.ProcessorCount `
                -DiskPath $diskPath `
                -ISOPath $Config.ISOPath `
                -NetworkType 'bridged' `
                -EnableTPM $Config.EnableTPM `
                -EnableSecureBoot $Config.EnableSecureBoot

            # Register VM with vmrest
            $registration = Register-VMwareVM -VMXPath $vmxPath -VMName $Config.Name -Port $this.Port -Credential $this.Credential

            if (-not $registration -or -not $registration.id) {
                throw "Failed to register VM with vmrest"
            }

            WriteLog "VM registered with ID: $($registration.id)"

            # Get VM info
            $vmInfo = $this.GetVM($Config.Name)
            if (-not $vmInfo) {
                # Create VMInfo manually
                $vmInfo = [VMInfo]::new()
                $vmInfo.Name = $Config.Name
                $vmInfo.Id = $registration.id
                $vmInfo.HypervisorType = 'VMware'
                $vmInfo.VMwareId = $registration.id
                $vmInfo.VMXPath = $vmxPath
                $vmInfo.VirtualDiskPath = $diskPath
                $vmInfo.ConfigurationPath = $vmxPath
                $vmInfo.State = [VMState]::Off
            }

            WriteLog "VMware VM created successfully: $($Config.Name)"
            return $vmInfo
        }
        catch {
            WriteLog "ERROR in VMwareProvider.CreateVM: $($_.Exception.Message)"
            throw
        }
    }

    [void] StartVM([VMInfo]$VM) {
        try {
            $this.EnsureVMrestRunning()

            $vmId = $this.ResolveVMId($VM)
            Set-VMwarePowerState -VMId $vmId -State 'on' -Port $this.Port -Credential $this.Credential

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
            $state = if ($Force) { 'off' } else { 'shutdown' }

            Set-VMwarePowerState -VMId $vmId -State $state -Port $this.Port -Credential $this.Credential

            WriteLog "VMware VM '$($VM.Name)' stopped (force=$Force)"
        }
        catch {
            WriteLog "ERROR: Failed to stop VM '$($VM.Name)': $($_.Exception.Message)"
            throw
        }
    }

    [void] RemoveVM([VMInfo]$VM, [bool]$RemoveDisks) {
        try {
            $this.EnsureVMrestRunning()

            # Stop VM if running
            $state = $this.GetVMState($VM)
            if ($state -eq [VMState]::Running) {
                $this.StopVM($VM, $true)
                Start-Sleep -Seconds 3
            }

            $vmId = $this.ResolveVMId($VM)

            # Unregister from vmrest
            Unregister-VMwareVM -VMId $vmId -Port $this.Port -Credential $this.Credential

            # Remove files if requested
            if ($RemoveDisks -and -not [string]::IsNullOrEmpty($VM.ConfigurationPath)) {
                $vmFolder = Split-Path $VM.ConfigurationPath -Parent
                if (Test-Path $vmFolder) {
                    Remove-Item -Path $vmFolder -Recurse -Force -ErrorAction SilentlyContinue
                    WriteLog "VM files removed from: $vmFolder"
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
            $powerState = Get-VMwarePowerState -VMId $vmId -Port $this.Port -Credential $this.Credential

            return [VMInfo]::ConvertVMwareState($powerState)
        }
        catch {
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
        $configPath = Join-Path $env:USERPROFILE '.vmrestCfg'
        if (-not (Test-Path $configPath)) {
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

        # Check TPM requirements
        if ($Config.EnableTPM) {
            # VMware 17+ supports vTPM, but requires encryption
            $result.Warnings += "vTPM in VMware requires VM encryption. Ensure VMware Workstation supports this."
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
