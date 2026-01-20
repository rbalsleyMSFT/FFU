<#
.SYNOPSIS
    VMware Workstation implementation of IHypervisorProvider

.DESCRIPTION
    Provides VMware Workstation Pro specific implementation of the hypervisor
    provider interface. Uses vmrun.exe command-line tool for VM operations
    (with optional vmxtoolkit PowerShell module support) and diskpart for VHD
    operations. No REST API (vmrest) dependency.

.NOTES
    Module: FFU.Hypervisor
    Version: 1.3.0
    Dependencies: VMware Workstation Pro 17.x, vmxtoolkit (optional enhancement)
#>

class VMwareProvider : IHypervisorProvider {

    # VMware-specific properties
    hidden [string]$VMwarePath
    hidden [bool]$VmxToolkitAvailable = $false

    # Constructor
    VMwareProvider() {
        $this.Name = 'VMware'
        $this.Version = $this.GetVMwareVersion()
        $this.Description = 'VMware Workstation Pro hypervisor provider (vmrun/vmxtoolkit)'

        $this.Capabilities = @{
            SupportsTPM = $false                    # vTPM requires encryption (breaks vmrun automation)
            SupportsSecureBoot = $true              # UEFI Secure Boot supported
            SupportsGeneration2 = $true             # Similar to Hyper-V Gen2
            SupportsDynamicMemory = $false          # VMware uses static memory
            SupportsCheckpoints = $true             # Snapshots
            SupportsNestedVirtualization = $true
            SupportedDiskFormats = @('VMDK', 'VHD')  # VMware 10+ supports VHD files directly
            MaxMemoryGB = 128
            MaxProcessors = 32
            # NOTE: VMware vTPM requires VM encryption to function. Encrypted VMs cannot
            # be started with vmrun.exe (causes "operation was canceled" error).
            # For automated FFU builds, TPM is disabled. TPM features work on target hardware.
            TPMNote = 'VMware vTPM requires encryption which breaks automation. Disabled for FFU builds.'
        }

        # Auto-detect VMware installation
        $this.VMwarePath = $this.DetectVMwarePath()

        # Check if vmxtoolkit module is available
        $this.VmxToolkitAvailable = $this.CheckVmxToolkit()
    }

    # Check if vmxtoolkit PowerShell module is available
    hidden [bool] CheckVmxToolkit() {
        try {
            $module = Get-Module -ListAvailable -Name 'vmxtoolkit' -ErrorAction SilentlyContinue
            if ($module) {
                WriteLog "vmxtoolkit module available: v$($module.Version)"
                return $true
            }
            WriteLog "vmxtoolkit module not found - using direct vmrun.exe"
            return $false
        }
        catch {
            return $false
        }
    }

    # Search filesystem for VMX files when vmxtoolkit is unavailable
    # This enables VM discovery even without vmxtoolkit by scanning common VM storage locations
    hidden [string[]] SearchVMXFilesystem([string]$VMName = $null) {
        $searchPaths = @()

        # VMware default VM directory from preferences
        $prefsPath = Join-Path $env:APPDATA 'VMware\preferences.ini'
        if (Test-Path $prefsPath) {
            $prefs = Get-Content $prefsPath -ErrorAction SilentlyContinue
            $defaultVMPath = $prefs | Where-Object { $_ -match 'prefvmx\.defaultVMPath\s*=\s*"([^"]+)"' } |
                ForEach-Object { $Matches[1] }
            if ($defaultVMPath -and (Test-Path $defaultVMPath)) {
                $searchPaths += $defaultVMPath
            }
        }

        # Common default locations
        $commonPaths = @(
            (Join-Path $env:USERPROFILE 'Documents\Virtual Machines'),
            (Join-Path $env:USERPROFILE 'Virtual Machines'),
            'C:\VMs',
            'D:\VMs'
        )
        $searchPaths += $commonPaths | Where-Object { Test-Path $_ }

        # Search for VMX files
        $vmxFiles = @()
        foreach ($path in ($searchPaths | Select-Object -Unique)) {
            $found = Get-ChildItem -Path $path -Filter '*.vmx' -Recurse -Depth 2 -ErrorAction SilentlyContinue
            if ($VMName) {
                $found = $found | Where-Object { $_.BaseName -eq $VMName }
            }
            $vmxFiles += $found.FullName
        }

        return $vmxFiles
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

    #region VM Lifecycle Methods

    [VMInfo] CreateVM([VMConfiguration]$Config) {
        # Validate configuration
        $validation = $this.ValidateConfiguration($Config)
        if (-not $validation.IsValid) {
            throw "Configuration validation failed: $($validation.Errors -join '; ')"
        }

        try {
            WriteLog "Creating VMware VM: $($Config.Name)"

            # Create VM folder
            $vmPath = $Config.Path
            if (-not (Test-Path $vmPath)) {
                New-Item -Path $vmPath -ItemType Directory -Force | Out-Null
            }

            # Determine disk path
            # NOTE: VMware Workstation 10+ supports VHD files directly as virtual disks.
            # The FFU build creates a VHD with Windows pre-installed, so we use it as-is.
            $diskPath = $Config.VirtualDiskPath
            if ([string]::IsNullOrEmpty($diskPath)) {
                # No disk path specified - create a new VMDK
                $diskPath = Join-Path $vmPath "$($Config.Name).vmdk"
            }

            # Check if disk exists (VHD or VMDK)
            if (-not (Test-Path $diskPath)) {
                # Disk doesn't exist at specified path
                # For FFU builds, the VHD should already exist from New-ScratchVhd
                $sizeGB = [int]($Config.DiskSizeBytes / 1GB)
                if ($sizeGB -eq 0) { $sizeGB = 128 }  # Default 128GB

                if ($diskPath.EndsWith('.vmdk', [StringComparison]::OrdinalIgnoreCase)) {
                    # Create VMDK using VMware's vdiskmanager
                    WriteLog "Creating VMDK disk for VMware VM: $diskPath ($sizeGB GB)"
                    $diskPath = New-VMDKWithVdiskmanager -Path $diskPath -SizeGB $sizeGB -Type Dynamic -VMwarePath $this.VMwarePath
                }
                elseif ($diskPath.EndsWith('.vhd', [StringComparison]::OrdinalIgnoreCase)) {
                    # VHD not found - this is an error for FFU builds since VHD should exist
                    throw "VHD file not found: $diskPath. The VHD should have been created by New-ScratchVhd during the build process."
                }
                else {
                    # Unknown format - create VHD as fallback
                    WriteLog "WARNING: Creating VHD disk: $diskPath"
                    $diskPath = New-VHDWithDiskpart -Path $diskPath -SizeGB $sizeGB -Type Dynamic
                }
            }
            else {
                WriteLog "Using existing disk: $diskPath"
                $fileSize = (Get-Item $diskPath).Length
                WriteLog "  Disk size: $([math]::Round($fileSize / 1GB, 2)) GB"
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

    [string] StartVM([VMInfo]$VM) {
        # Default overload - runs headless (nogui)
        return $this.StartVM($VM, $false)
    }

    [string] StartVM([VMInfo]$VM, [bool]$ShowConsole) {
        <#
        .SYNOPSIS
            Start the VM and return its status

        .DESCRIPTION
            Starts the VM using vmrun.exe. Returns the status of the VM after startup:
            - 'Running': VM started and is currently running
            - 'Completed': VM started, ran to completion, and shut down (GUI mode only)

            In GUI mode (ShowConsole=true), vmrun blocks until the VM shuts down.
            If the VM completes its work and shuts down, 'Completed' is returned.
            This allows the caller to skip the shutdown polling loop.

        .OUTPUTS
            String: 'Running' or 'Completed'
        #>
        try {
            $vmxPath = $this.ResolveVMXPath($VM)

            if ([string]::IsNullOrEmpty($vmxPath)) {
                throw "Cannot start VM '$($VM.Name)': VMX path not found"
            }

            if ($ShowConsole) {
                WriteLog "Starting VM with console window visible (gui mode)"
                WriteLog "NOTE: vmrun gui blocks until VM shuts down"
            }
            else {
                WriteLog "Starting VM in headless mode (nogui) - use -ShowVMConsole `$true to see console"
            }

            # Use vmxtoolkit if available, otherwise direct vmrun
            # Both paths now return a result with Status property
            $result = $null
            if ($this.VmxToolkitAvailable) {
                $result = $this.StartVMWithVmxToolkit($vmxPath, $ShowConsole)
            }
            else {
                $result = Set-VMwarePowerStateWithVmrun -VMXPath $vmxPath -State 'on' -ShowConsole $ShowConsole
            }

            # Check if VM completed during startup (GUI mode behavior)
            if ($result -and $result.Status -eq 'Completed') {
                WriteLog "VMware VM '$($VM.Name)' started, ran, and completed during vmrun wait"
                return 'Completed'
            }

            WriteLog "VMware VM '$($VM.Name)' started and is running"
            return 'Running'
        }
        catch {
            WriteLog "ERROR: Failed to start VM '$($VM.Name)': $($_.Exception.Message)"
            throw
        }
    }

    # Start VM using vmxtoolkit module
    hidden [hashtable] StartVMWithVmxToolkit([string]$VMXPath, [bool]$ShowConsole) {
        try {
            Import-Module vmxtoolkit -ErrorAction Stop

            $vmx = Get-VMX -Path (Split-Path $VMXPath -Parent) -ErrorAction Stop |
                   Where-Object { $_.VMXPath -eq $VMXPath } |
                   Select-Object -First 1

            if (-not $vmx) {
                WriteLog "vmxtoolkit: VM not found, falling back to direct vmrun"
                return Set-VMwarePowerStateWithVmrun -VMXPath $VMXPath -State 'on' -ShowConsole $ShowConsole
            }

            # vmxtoolkit's Start-VMX doesn't support gui/nogui - use vmrun for better control
            # but we can still use vmxtoolkit for other operations
            WriteLog "vmxtoolkit: Starting VM using vmrun for gui/nogui control"
            return Set-VMwarePowerStateWithVmrun -VMXPath $VMXPath -State 'on' -ShowConsole $ShowConsole
        }
        catch {
            WriteLog "vmxtoolkit start failed: $($_.Exception.Message) - falling back to vmrun"
            return Set-VMwarePowerStateWithVmrun -VMXPath $VMXPath -State 'on' -ShowConsole $ShowConsole
        }
    }

    [void] StopVM([VMInfo]$VM, [bool]$Force) {
        try {
            $vmxPath = $this.ResolveVMXPath($VM)

            if ([string]::IsNullOrEmpty($vmxPath)) {
                throw "Cannot stop VM '$($VM.Name)': VMX path not found"
            }

            $state = if ($Force) { 'off' } else { 'shutdown' }

            # Use vmxtoolkit if available, otherwise direct vmrun
            if ($this.VmxToolkitAvailable) {
                $this.StopVMWithVmxToolkit($vmxPath, $Force)
            }
            else {
                Set-VMwarePowerStateWithVmrun -VMXPath $vmxPath -State $state
            }

            WriteLog "VMware VM '$($VM.Name)' stopped (force=$Force)"
        }
        catch {
            WriteLog "ERROR: Failed to stop VM '$($VM.Name)': $($_.Exception.Message)"
            throw
        }
    }

    # Stop VM using vmxtoolkit module
    hidden [void] StopVMWithVmxToolkit([string]$VMXPath, [bool]$Force) {
        try {
            Import-Module vmxtoolkit -ErrorAction Stop

            $vmx = Get-VMX -Path (Split-Path $VMXPath -Parent) -ErrorAction Stop |
                   Where-Object { $_.VMXPath -eq $VMXPath } |
                   Select-Object -First 1

            if (-not $vmx) {
                WriteLog "vmxtoolkit: VM not found, falling back to direct vmrun"
                $state = if ($Force) { 'off' } else { 'shutdown' }
                Set-VMwarePowerStateWithVmrun -VMXPath $VMXPath -State $state
                return
            }

            # vmxtoolkit's Stop-VMX always does hard stop
            # For soft shutdown, use vmrun directly
            if ($Force) {
                Stop-VMX -VMX $vmx -ErrorAction Stop | Out-Null
                WriteLog "vmxtoolkit: VM stopped (hard)"
            }
            else {
                WriteLog "vmxtoolkit: Using vmrun for graceful shutdown"
                Set-VMwarePowerStateWithVmrun -VMXPath $VMXPath -State 'shutdown'
            }
        }
        catch {
            WriteLog "vmxtoolkit stop failed: $($_.Exception.Message) - falling back to vmrun"
            $state = if ($Force) { 'off' } else { 'shutdown' }
            Set-VMwarePowerStateWithVmrun -VMXPath $VMXPath -State $state
        }
    }

    [void] RemoveVM([VMInfo]$VM, [bool]$RemoveDisks) {
        try {
            # Stop VM if running
            $state = $this.GetVMState($VM)
            if ($state -eq [VMState]::Running) {
                WriteLog "Stopping running VM before removal..."
                $this.StopVM($VM, $true)
                Start-Sleep -Seconds 3
            }

            # Get VMX path for file deletion
            $vmxPath = $this.ResolveVMXPath($VM)

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
        # Note: VM IP discovery is NOT used in the FFU build process.
        # The build uses the HOST's IP address for network shares.
        # This method is provided for completeness but may return null.
        try {
            $vmxPath = $this.ResolveVMXPath($VM)

            # Try vmxtoolkit if available
            if ($this.VmxToolkitAvailable) {
                try {
                    Import-Module vmxtoolkit -ErrorAction Stop
                    $vmx = Get-VMX -Path (Split-Path $vmxPath -Parent) -ErrorAction SilentlyContinue |
                           Where-Object { $_.VMXPath -eq $vmxPath } |
                           Select-Object -First 1

                    if ($vmx) {
                        $ipInfo = Get-VMXIPAddress -VMX $vmx -ErrorAction SilentlyContinue
                        if ($ipInfo -and $ipInfo.IPAddress) {
                            return $ipInfo.IPAddress
                        }
                    }
                }
                catch {
                    WriteLog "vmxtoolkit IP lookup failed: $($_.Exception.Message)"
                }
            }

            # vmrun doesn't have a direct IP query - VMware Tools guest info required
            WriteLog "WARNING: IP address discovery requires VMware Tools in guest OS"
            return $null
        }
        catch {
            WriteLog "WARNING: Failed to get IP for VM '$($VM.Name)': $($_.Exception.Message)"
            return $null
        }
    }

    [VMState] GetVMState([VMInfo]$VM) {
        try {
            $vmxPath = $this.ResolveVMXPath($VM)

            if ([string]::IsNullOrEmpty($vmxPath)) {
                WriteLog "WARNING: Cannot determine VMX path for state check"
                return [VMState]::Unknown
            }

            # Use nvram file lock detection (most reliable method)
            $powerState = Get-VMwarePowerStateWithVmrun -VMXPath $vmxPath
            return [VMInfo]::ConvertVMwareState($powerState)
        }
        catch {
            WriteLog "WARNING: GetVMState failed: $($_.Exception.Message)"
            return [VMState]::Unknown
        }
    }

    [VMInfo] GetVM([string]$Name) {
        # Search for VM by name using vmxtoolkit or file system
        try {
            # Try vmxtoolkit first if available
            if ($this.VmxToolkitAvailable) {
                try {
                    Import-Module vmxtoolkit -ErrorAction Stop
                    $vmx = Get-VMX -ErrorAction SilentlyContinue | Where-Object { $_.VMXName -eq $Name }

                    if ($vmx) {
                        $vmInfo = [VMInfo]::new()
                        $vmInfo.Name = $Name
                        $vmInfo.Id = $Name
                        $vmInfo.HypervisorType = 'VMware'
                        $vmInfo.VMwareId = $Name
                        $vmInfo.VMXPath = $vmx.VMXPath
                        $vmInfo.ConfigurationPath = $vmx.VMXPath

                        # Get power state
                        $powerState = Get-VMwarePowerStateWithVmrun -VMXPath $vmx.VMXPath
                        $vmInfo.State = [VMInfo]::ConvertVMwareState($powerState)

                        return $vmInfo
                    }
                }
                catch {
                    WriteLog "vmxtoolkit GetVM failed: $($_.Exception.Message)"
                }
            }

            # Fallback: Use vmrun list to find running VMs matching the name
            $vmrunPath = Get-VmrunPath
            if ($vmrunPath) {
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = $vmrunPath
                $psi.Arguments = "-T ws list"
                $psi.UseShellExecute = $false
                $psi.RedirectStandardOutput = $true
                $psi.CreateNoWindow = $true

                $process = [System.Diagnostics.Process]::Start($psi)
                $output = $process.StandardOutput.ReadToEnd()
                $process.WaitForExit()

                $lines = $output -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '^Total running VMs:' }

                foreach ($vmxPath in $lines) {
                    $vmName = [System.IO.Path]::GetFileNameWithoutExtension($vmxPath)
                    if ($vmName -eq $Name) {
                        $vmInfo = [VMInfo]::new()
                        $vmInfo.Name = $vmName
                        $vmInfo.Id = $vmName
                        $vmInfo.HypervisorType = 'VMware'
                        $vmInfo.VMwareId = $vmName
                        $vmInfo.VMXPath = $vmxPath
                        $vmInfo.ConfigurationPath = $vmxPath
                        $vmInfo.State = [VMState]::Running  # It's in vmrun list, so it's running

                        return $vmInfo
                    }
                }
            }

            # Fallback: Search filesystem for VMX files (finds stopped VMs without vmxtoolkit)
            $vmxPaths = $this.SearchVMXFilesystem($Name)
            if ($vmxPaths) {
                $vmxPath = $vmxPaths | Select-Object -First 1
                $vmInfo = [VMInfo]::new()
                $vmInfo.Name = $Name
                $vmInfo.Id = $Name
                $vmInfo.HypervisorType = 'VMware'
                $vmInfo.VMwareId = $Name
                $vmInfo.VMXPath = $vmxPath
                $vmInfo.ConfigurationPath = $vmxPath

                # Check power state
                $powerState = Get-VMwarePowerStateWithVmrun -VMXPath $vmxPath
                $vmInfo.State = [VMInfo]::ConvertVMwareState($powerState)

                WriteLog "Found VM '$Name' via filesystem search: $vmxPath"
                return $vmInfo
            }

            return $null
        }
        catch {
            WriteLog "WARNING: GetVM failed: $($_.Exception.Message)"
            return $null
        }
    }

    [VMInfo[]] GetAllVMs() {
        # Get all VMs using vmxtoolkit or vmrun list
        try {
            $results = @()

            # Try vmxtoolkit first if available
            if ($this.VmxToolkitAvailable) {
                try {
                    Import-Module vmxtoolkit -ErrorAction Stop
                    $vms = Get-VMX -ErrorAction SilentlyContinue

                    foreach ($vmx in $vms) {
                        $vmInfo = [VMInfo]::new()
                        $vmInfo.Name = $vmx.VMXName
                        $vmInfo.Id = $vmx.VMXName
                        $vmInfo.HypervisorType = 'VMware'
                        $vmInfo.VMwareId = $vmx.VMXName
                        $vmInfo.VMXPath = $vmx.VMXPath
                        $vmInfo.ConfigurationPath = $vmx.VMXPath

                        $results += $vmInfo
                    }

                    return $results
                }
                catch {
                    WriteLog "vmxtoolkit GetAllVMs failed: $($_.Exception.Message)"
                }
            }

            # Fallback: Use vmrun list to get running VMs only
            $vmrunPath = Get-VmrunPath
            if ($vmrunPath) {
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = $vmrunPath
                $psi.Arguments = "-T ws list"
                $psi.UseShellExecute = $false
                $psi.RedirectStandardOutput = $true
                $psi.CreateNoWindow = $true

                $process = [System.Diagnostics.Process]::Start($psi)
                $output = $process.StandardOutput.ReadToEnd()
                $process.WaitForExit()

                $lines = $output -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '^Total running VMs:' }

                foreach ($vmxPath in $lines) {
                    $vmInfo = [VMInfo]::new()
                    $vmInfo.Name = [System.IO.Path]::GetFileNameWithoutExtension($vmxPath)
                    $vmInfo.Id = $vmInfo.Name
                    $vmInfo.HypervisorType = 'VMware'
                    $vmInfo.VMwareId = $vmInfo.Name
                    $vmInfo.VMXPath = $vmxPath
                    $vmInfo.ConfigurationPath = $vmxPath
                    $vmInfo.State = [VMState]::Running

                    $results += $vmInfo
                }
            }

            # Add VMs found via filesystem that aren't already in results (finds stopped VMs)
            $vmxPaths = $this.SearchVMXFilesystem()
            foreach ($vmxPath in $vmxPaths) {
                $vmName = [System.IO.Path]::GetFileNameWithoutExtension($vmxPath)

                # Skip if already found via vmrun list
                if ($results | Where-Object { $_.VMXPath -eq $vmxPath }) {
                    continue
                }

                $vmInfo = [VMInfo]::new()
                $vmInfo.Name = $vmName
                $vmInfo.Id = $vmName
                $vmInfo.HypervisorType = 'VMware'
                $vmInfo.VMwareId = $vmName
                $vmInfo.VMXPath = $vmxPath
                $vmInfo.ConfigurationPath = $vmxPath

                # Check power state (likely Off since not in vmrun list)
                $powerState = Get-VMwarePowerStateWithVmrun -VMXPath $vmxPath
                $vmInfo.State = [VMInfo]::ConvertVMwareState($powerState)

                $results += $vmInfo
            }

            return $results
        }
        catch {
            WriteLog "WARNING: GetAllVMs failed: $($_.Exception.Message)"
            return @()
        }
    }

    # Helper to resolve VM ID from VMInfo
    # Note: With vmxtoolkit/vmrun approach, we use VM name as ID
    hidden [string] ResolveVMId([VMInfo]$VM) {
        if (-not [string]::IsNullOrEmpty($VM.VMwareId)) {
            return $VM.VMwareId
        }

        if (-not [string]::IsNullOrEmpty($VM.Id)) {
            return $VM.Id
        }

        if (-not [string]::IsNullOrEmpty($VM.Name)) {
            return $VM.Name
        }

        throw "Cannot resolve VMware VM ID for VM"
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
            WriteLog "=== Configuring capture boot for VMware VM ==="
            WriteLog "  VM Name: $($VM.Name)"
            WriteLog "  ISO Path: $ISOPath"

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
            WriteLog "  VMX Path: $vmxPath"

            # CRITICAL: Delete NVRAM file to reset boot order
            # VMware caches boot order in NVRAM from first boot. When the VM boots Windows
            # the first time (hdd,cdrom), NVRAM records "boot from HDD". Even when we change
            # the VMX bios.bootOrder to "cdrom,hdd", VMware uses the NVRAM cached value.
            # By deleting NVRAM, VMware is forced to read boot order from the VMX file.
            $vmFolder = Split-Path $vmxPath -Parent
            $vmName = [System.IO.Path]::GetFileNameWithoutExtension($vmxPath)
            $nvramPath = Join-Path $vmFolder "$vmName.nvram"

            if (Test-Path $nvramPath) {
                WriteLog "  Deleting NVRAM file to reset boot order: $nvramPath"
                Remove-Item -Path $nvramPath -Force
                WriteLog "  NVRAM deleted - VMware will read boot order from VMX on next boot"
            }
            else {
                WriteLog "  No NVRAM file found (VMware 25.0.0+ may not create one)"
            }

            # Set-VMwareBootISO logs before/after boot order internally
            WriteLog "  Step 1: Configuring boot ISO and boot order..."
            Set-VMwareBootISO -VMXPath $vmxPath -ISOPath $ISOPath
            WriteLog "  Step 1 COMPLETE: VMX file updated"

            # Verify changes persisted to disk
            WriteLog "  Step 2: Verifying VMX configuration persisted..."
            $vmxContent = Get-Content $vmxPath -Raw

            # Check boot order
            $bootOrderVerified = $false
            if ($vmxContent -match 'bios\.bootOrder\s*=\s*"([^"]*)"') {
                $bootOrder = $Matches[1]
                WriteLog "  AFTER - Boot order in VMX: $bootOrder"
                if ($bootOrder -like 'cdrom*') {
                    WriteLog "  VERIFIED: Boot order starts with 'cdrom'"
                    $bootOrderVerified = $true
                }
                else {
                    WriteLog "  WARNING: Boot order does not start with 'cdrom'!"
                    WriteLog "  WARNING: Expected 'cdrom,hdd' but found '$bootOrder'"
                }
            }
            else {
                WriteLog "  WARNING: Could not find bios.bootOrder in VMX file"
            }

            # Check ISO path is set
            $isoPathVerified = $false
            if ($vmxContent -match 'sata0:0\.fileName\s*=\s*"([^"]*)"') {
                $vmxIsoPath = $Matches[1]
                WriteLog "  AFTER - ISO path in VMX: $vmxIsoPath"
                if ($vmxIsoPath -eq $ISOPath) {
                    WriteLog "  VERIFIED: ISO path matches expected value"
                    $isoPathVerified = $true
                }
                else {
                    WriteLog "  WARNING: ISO path mismatch!"
                    WriteLog "  WARNING: Expected '$ISOPath' but found '$vmxIsoPath'"
                }
            }
            else {
                WriteLog "  WARNING: Could not find sata0:0.fileName in VMX file"
            }

            # Check CD-ROM is connected
            if ($vmxContent -match 'sata0:0\.startConnected\s*=\s*"([^"]*)"') {
                $startConnected = $Matches[1]
                WriteLog "  AFTER - CD-ROM startConnected: $startConnected"
                if ($startConnected -ne 'TRUE') {
                    WriteLog "  WARNING: CD-ROM startConnected is not TRUE!"
                }
            }

            # Final verification summary
            if ($bootOrderVerified -and $isoPathVerified) {
                WriteLog "  VERIFIED: VM will boot from capture ISO (WinPE)"
            }
            else {
                WriteLog "  WARNING: Boot configuration may not be correct - check VM console during boot"
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

            # Check vmrun exists (required for all operations)
            $vmrunPath = Join-Path $this.VMwarePath 'vmrun.exe'
            if (-not (Test-Path $vmrunPath)) {
                return $false
            }

            # Note: vmrest is no longer required - we use vmrun/vmxtoolkit

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

        # Check vmrun (required)
        if ($this.VMwarePath) {
            $vmrunPath = Join-Path $this.VMwarePath 'vmrun.exe'
            if (-not (Test-Path $vmrunPath)) {
                $result.Issues += "vmrun.exe not found (required for VM operations)"
            }
            else {
                $result.Details['vmrun'] = 'Available'
            }
        }

        # Check vmxtoolkit (optional enhancement)
        if ($this.VmxToolkitAvailable) {
            $module = Get-Module -ListAvailable -Name 'vmxtoolkit' -ErrorAction SilentlyContinue
            $result.Details['vmxtoolkit'] = "v$($module.Version)"
        }
        else {
            $result.Details['vmxtoolkit'] = 'Not installed (optional)'
        }

        # Check version
        if ($this.Version -ne '0.0.0') {
            $result.Details['Version'] = $this.Version

            # Check minimum version (17.0 recommended)
            $majorVersion = [int]($this.Version.Split('.')[0])
            if ($majorVersion -lt 17) {
                $result.Issues += "VMware Workstation 17.x or later recommended (found: $($this.Version))"
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
    [CmdletBinding()]
    [OutputType([VMwareProvider])]
    param()

    return [VMwareProvider]::new()
}
