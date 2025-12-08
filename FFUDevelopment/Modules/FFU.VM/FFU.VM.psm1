<#
.SYNOPSIS
    FFU Builder Hyper-V Virtual Machine Management Module

.DESCRIPTION
    Hyper-V virtual machine lifecycle management for FFU Builder.
    Provides VM creation, configuration, and cleanup operations for FFU build VMs.
    Handles VM networking, VHDX attachment, and environment validation.

.NOTES
    Module: FFU.VM
    Version: 1.0.0
    Dependencies: FFU.Core (for WriteLog function and common variables)
    Requires: Administrator privileges and Hyper-V feature enabled
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

#region Cross-Version Local User Management Helper Functions
# These functions use .NET DirectoryServices APIs to work in both PowerShell 5.1 and 7+
# Replaces Get-LocalUser, New-LocalUser, Remove-LocalUser cmdlets which have compatibility issues in PowerShell 7

function Get-LocalUserAccount {
    <#
    .SYNOPSIS
    Gets a local user account using .NET DirectoryServices API

    .DESCRIPTION
    Cross-version compatible replacement for Get-LocalUser cmdlet.
    Works in both PowerShell 5.1 (Desktop) and PowerShell 7+ (Core).

    .PARAMETER Username
    Name of the local user account to retrieve

    .EXAMPLE
    $user = Get-LocalUserAccount -Username "ffu_user"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Username
    )

    try {
        Add-Type -AssemblyName System.DirectoryServices.AccountManagement

        $context = [System.DirectoryServices.AccountManagement.PrincipalContext]::new(
            [System.DirectoryServices.AccountManagement.ContextType]::Machine
        )

        $user = [System.DirectoryServices.AccountManagement.UserPrincipal]::FindByIdentity(
            $context,
            [System.DirectoryServices.AccountManagement.IdentityType]::SamAccountName,
            $Username
        )

        $context.Dispose()

        if ($user) {
            # Return user object
            return $user
        }

        return $null
    }
    catch {
        return $null
    }
}

function New-LocalUserAccount {
    <#
    .SYNOPSIS
    Creates a local user account using .NET DirectoryServices API

    .DESCRIPTION
    Cross-version compatible replacement for New-LocalUser cmdlet.
    Works in both PowerShell 5.1 (Desktop) and PowerShell 7+ (Core).
    Avoids TelemetryAPI errors in PowerShell 7.

    .PARAMETER Username
    Name of the local user account to create

    .PARAMETER Password
    SecureString password for the user account

    .PARAMETER FullName
    Full name/display name for the user

    .PARAMETER Description
    Description of the user account

    .EXAMPLE
    $password = ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force
    New-LocalUserAccount -Username "ffu_user" -Password $password -FullName "FFU User" -Description "FFU Capture User"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Username,

        [Parameter(Mandatory = $true)]
        [SecureString]$Password,

        [Parameter(Mandatory = $false)]
        [string]$FullName = "",

        [Parameter(Mandatory = $false)]
        [string]$Description = ""
    )

    try {
        # Convert SecureString to plain text (required for PrincipalContext API)
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
        $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

        try {
            # Create user via DirectoryServices
            Add-Type -AssemblyName System.DirectoryServices.AccountManagement

            $context = [System.DirectoryServices.AccountManagement.PrincipalContext]::new(
                [System.DirectoryServices.AccountManagement.ContextType]::Machine
            )

            $user = [System.DirectoryServices.AccountManagement.UserPrincipal]::new($context)
            $user.Name = $Username
            $user.SetPassword($plainPassword)
            $user.DisplayName = $FullName
            $user.Description = $Description
            $user.UserCannotChangePassword = $false
            $user.PasswordNeverExpires = $true
            $user.Save()

            $context.Dispose()
            $user.Dispose()

            return $true
        }
        finally {
            # Always clear password from memory
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
            if ($plainPassword) {
                $plainPassword = $null
            }
        }
    }
    catch {
        throw "Failed to create local user account: $($_.Exception.Message)"
    }
}

function Remove-LocalUserAccount {
    <#
    .SYNOPSIS
    Removes a local user account using .NET DirectoryServices API

    .DESCRIPTION
    Cross-version compatible replacement for Remove-LocalUser cmdlet.
    Works in both PowerShell 5.1 (Desktop) and PowerShell 7+ (Core).

    .PARAMETER Username
    Name of the local user account to remove

    .EXAMPLE
    Remove-LocalUserAccount -Username "ffu_user"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Username
    )

    try {
        Add-Type -AssemblyName System.DirectoryServices.AccountManagement

        $context = [System.DirectoryServices.AccountManagement.PrincipalContext]::new(
            [System.DirectoryServices.AccountManagement.ContextType]::Machine
        )

        $user = [System.DirectoryServices.AccountManagement.UserPrincipal]::FindByIdentity(
            $context,
            [System.DirectoryServices.AccountManagement.IdentityType]::SamAccountName,
            $Username
        )

        if ($user) {
            $user.Delete()
            $user.Dispose()
        }

        $context.Dispose()

        return $true
    }
    catch {
        throw "Failed to remove local user account: $($_.Exception.Message)"
    }
}

function Set-LocalUserPassword {
    <#
    .SYNOPSIS
    Sets the password for an existing local user account using .NET DirectoryServices API

    .DESCRIPTION
    Cross-version compatible function to reset a local user's password.
    Works in both PowerShell 5.1 (Desktop) and PowerShell 7+ (Core).
    This function is used to ensure the ffu_user password matches what's written
    to CaptureFFU.ps1, preventing "Password is incorrect" errors (Error 86).

    .PARAMETER Username
    Name of the local user account to update

    .PARAMETER Password
    New password as SecureString

    .EXAMPLE
    $password = ConvertTo-SecureString "NewP@ssw0rd" -AsPlainText -Force
    Set-LocalUserPassword -Username "ffu_user" -Password $password
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Username,

        [Parameter(Mandatory = $true)]
        [SecureString]$Password
    )

    # Convert SecureString to plain text (required for SetPassword API)
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
    $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

    try {
        Add-Type -AssemblyName System.DirectoryServices.AccountManagement

        $context = [System.DirectoryServices.AccountManagement.PrincipalContext]::new(
            [System.DirectoryServices.AccountManagement.ContextType]::Machine
        )

        $user = [System.DirectoryServices.AccountManagement.UserPrincipal]::FindByIdentity(
            $context,
            [System.DirectoryServices.AccountManagement.IdentityType]::SamAccountName,
            $Username
        )

        if (-not $user) {
            throw "User '$Username' not found"
        }

        # Set the new password
        $user.SetPassword($plainPassword)
        $user.Save()

        $user.Dispose()
        $context.Dispose()

        return $true
    }
    catch {
        throw "Failed to set password for user '$Username': $($_.Exception.Message)"
    }
    finally {
        # Secure cleanup of sensitive data
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        if ($plainPassword) {
            $plainPassword = $null
        }
    }
}

function Set-LocalUserAccountExpiry {
    <#
    .SYNOPSIS
    Sets the account expiration date for a local user account

    .DESCRIPTION
    Cross-version compatible function to set account expiry using .NET DirectoryServices API.
    This is a security measure to ensure temporary accounts are automatically disabled
    even if cleanup fails. Works in both PowerShell 5.1 and 7+.

    .PARAMETER Username
    Name of the local user account to update

    .PARAMETER ExpiryDate
    DateTime when the account should expire. If not specified, defaults to 4 hours from now.

    .PARAMETER ExpiryHours
    Number of hours from now when the account should expire. Ignored if ExpiryDate is specified.
    Default is 4 hours.

    .EXAMPLE
    Set-LocalUserAccountExpiry -Username "ffu_user" -ExpiryHours 2

    .EXAMPLE
    Set-LocalUserAccountExpiry -Username "ffu_user" -ExpiryDate (Get-Date).AddHours(6)

    .NOTES
    SECURITY: This provides a failsafe to ensure temporary FFU capture accounts
    are automatically disabled even if the script fails to clean up properly.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Username,

        [Parameter(Mandatory = $false)]
        [DateTime]$ExpiryDate,

        [Parameter(Mandatory = $false)]
        [int]$ExpiryHours = 4
    )

    try {
        Add-Type -AssemblyName System.DirectoryServices.AccountManagement

        $context = [System.DirectoryServices.AccountManagement.PrincipalContext]::new(
            [System.DirectoryServices.AccountManagement.ContextType]::Machine
        )

        $user = [System.DirectoryServices.AccountManagement.UserPrincipal]::FindByIdentity(
            $context,
            [System.DirectoryServices.AccountManagement.IdentityType]::SamAccountName,
            $Username
        )

        if (-not $user) {
            throw "User '$Username' not found"
        }

        # Calculate expiry date
        if (-not $ExpiryDate) {
            $ExpiryDate = (Get-Date).AddHours($ExpiryHours)
        }

        # Set account expiration
        $user.AccountExpirationDate = $ExpiryDate
        $user.Save()

        $user.Dispose()
        $context.Dispose()

        return $ExpiryDate
    }
    catch {
        throw "Failed to set account expiry for user '$Username': $($_.Exception.Message)"
    }
}

#endregion Cross-Version Local User Management Helper Functions

function New-FFUVM {
    <#
    .SYNOPSIS
    Creates a new Generation 2 Hyper-V virtual machine for FFU build process

    .DESCRIPTION
    Creates and configures a new Hyper-V VM with TPM, mounts the Apps ISO,
    configures boot settings, and starts the VM with vmconnect.

    .PARAMETER VMName
    Name of the virtual machine to create

    .PARAMETER VMPath
    Path where the VM configuration files will be stored

    .PARAMETER Memory
    Memory allocation for the VM in bytes (e.g., 8GB = 8589934592)

    .PARAMETER VHDXPath
    Path to the VHDX file to attach to the VM

    .PARAMETER Processors
    Number of virtual processors to assign to the VM

    .PARAMETER AppsISO
    Path to the Apps ISO file to mount to the VM

    .EXAMPLE
    New-FFUVM -VMName "_FFU-Build-Win11" -VMPath "C:\FFU\VM" -Memory 8GB `
              -VHDXPath "C:\FFU\VM\disk.vhdx" -Processors 4 -AppsISO "C:\FFU\Apps\Apps.iso"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMName,

        [Parameter(Mandatory = $true)]
        [string]$VMPath,

        [Parameter(Mandatory = $true)]
        [uint64]$Memory,

        [Parameter(Mandatory = $true)]
        [string]$VHDXPath,

        [Parameter(Mandatory = $true)]
        [int]$Processors,

        [Parameter(Mandatory = $true)]
        [string]$AppsISO
    )

    $VM = $null
    $vmCreated = $false
    $guardianCreated = $false

    try {
        # Create new Gen2 VM
        WriteLog "Creating VM: $VMName"
        try {
            $VM = New-VM -Name $VMName -Path $VMPath -MemoryStartupBytes $Memory -VHDPath $VHDXPath -Generation 2 -ErrorAction Stop
            $vmCreated = $true
            WriteLog "VM created successfully"
        }
        catch {
            throw "Failed to create VM '$VMName': $($_.Exception.Message)"
        }

        # Configure VM processor
        try {
            Set-VMProcessor -VMName $VMName -Count $Processors -ErrorAction Stop
            WriteLog "VM processor configured: $Processors cores"
        }
        catch {
            throw "Failed to configure VM processor: $($_.Exception.Message)"
        }

        # Mount AppsISO
        try {
            Add-VMDvdDrive -VMName $VMName -Path $AppsISO -ErrorAction Stop
            WriteLog "Apps ISO mounted: $AppsISO"
        }
        catch {
            throw "Failed to mount Apps ISO '$AppsISO': $($_.Exception.Message)"
        }

        # Set Hard Drive as boot device
        try {
            $VMHardDiskDrive = Get-VMHarddiskdrive -VMName $VMName -ErrorAction Stop
            Set-VMFirmware -VMName $VMName -FirstBootDevice $VMHardDiskDrive -ErrorAction Stop
            Set-VM -Name $VMName -AutomaticCheckpointsEnabled $false -StaticMemory -ErrorAction Stop
            WriteLog "VM boot configuration set"
        }
        catch {
            throw "Failed to configure VM boot settings: $($_.Exception.Message)"
        }

        # Configure TPM
        try {
            New-HgsGuardian -Name $VMName -GenerateCertificates -ErrorAction Stop
            $guardianCreated = $true
            $owner = Get-HgsGuardian -Name $VMName -ErrorAction Stop
            $kp = New-HgsKeyProtector -Owner $owner -AllowUntrustedRoot -ErrorAction Stop
            Set-VMKeyProtector -VMName $VMName -KeyProtector $kp.RawData -ErrorAction Stop
            Enable-VMTPM -VMName $VMName -ErrorAction Stop
            WriteLog "TPM configured successfully"
        }
        catch {
            # TPM configuration is non-critical - log warning but continue
            WriteLog "WARNING: TPM configuration failed (non-critical): $($_.Exception.Message)"
            WriteLog "VM will continue without TPM. Some Windows features may be limited."
        }

        # Connect to VM
        WriteLog "Starting vmconnect localhost $VMName"
        & vmconnect localhost "$VMName"

        # Start VM
        try {
            Start-VM -Name $VMName -ErrorAction Stop
            WriteLog "VM started successfully"
        }
        catch {
            throw "Failed to start VM '$VMName': $($_.Exception.Message)"
        }

        return $VM
    }
    catch {
        WriteLog "ERROR in New-FFUVM: $($_.Exception.Message)"

        # Cleanup on failure
        if ($vmCreated) {
            WriteLog "Attempting cleanup of failed VM creation..."
            try {
                Stop-VM -Name $VMName -Force -TurnOff -ErrorAction SilentlyContinue
                Remove-VM -Name $VMName -Force -ErrorAction SilentlyContinue
                WriteLog "Failed VM removed"
            }
            catch {
                WriteLog "WARNING: Failed to cleanup VM: $($_.Exception.Message)"
            }
        }

        if ($guardianCreated) {
            try {
                Remove-HgsGuardian -Name $VMName -ErrorAction SilentlyContinue
                WriteLog "HGS Guardian removed"
            }
            catch {
                WriteLog "WARNING: Failed to cleanup HGS Guardian: $($_.Exception.Message)"
            }
        }

        throw
    }
}

function Remove-FFUVM {
    <#
    .SYNOPSIS
    Removes FFU build VM and associated resources

    .DESCRIPTION
    Removes the Hyper-V VM, HGS Guardian, certificates, VHDX files, and cleans up
    orphaned mounted images. Can be called with or without VMName for different
    cleanup scenarios.

    .PARAMETER VMName
    Optional name of the VM to remove. If not specified, only VHDX cleanup is performed.

    .PARAMETER VMPath
    Path to the VM configuration directory to remove

    .PARAMETER InstallApps
    Boolean indicating if apps were installed (affects cleanup behavior)

    .PARAMETER VhdxDisk
    VHDX disk object for cleanup validation

    .PARAMETER FFUDevelopmentPath
    Root FFUDevelopment path for mount folder cleanup

    .PARAMETER Username
    Optional username for FFU capture user cleanup (default: ffu_user)

    .PARAMETER ShareName
    Optional share name for FFU capture share cleanup (default: FFUCaptureShare)

    .EXAMPLE
    Remove-FFUVM -VMName "_FFU-Build-Win11" -VMPath "C:\FFU\VM\_FFU-Build-Win11" `
                 -InstallApps $true -VhdxDisk $disk -FFUDevelopmentPath "C:\FFU" `
                 -Username "ffu_user" -ShareName "FFUCaptureShare"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$VMName,

        [Parameter(Mandatory = $true)]
        [string]$VMPath,

        [Parameter(Mandatory = $true)]
        [bool]$InstallApps,

        [Parameter(Mandatory = $false)]
        $VhdxDisk,

        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath,

        [Parameter(Mandatory = $false)]
        [string]$Username = "ffu_user",

        [Parameter(Mandatory = $false)]
        [string]$ShareName = "FFUCaptureShare"
    )
    #Get the VM object and remove the VM, the HGSGuardian, and the certs
    If ($VMName) {
        $FFUVM = get-vm $VMName | Where-Object { $_.state -ne 'running' }
    }
    If ($null -ne $FFUVM) {
        WriteLog 'Cleaning up VM'
        $certPath = 'Cert:\LocalMachine\Shielded VM Local Certificates\'
        $VMName = $FFUVM.Name
        WriteLog "Removing VM: $VMName"
        Remove-VM -Name $VMName -Force
        WriteLog 'Removal complete'
        WriteLog "Removing $VMPath"
        if (-not [string]::IsNullOrWhiteSpace($VMPath)) {
            Remove-Item -Path $VMPath -Force -Recurse -ErrorAction SilentlyContinue
        }
        WriteLog 'Removal complete'
        WriteLog "Removing HGSGuardian for $VMName"
        Remove-HgsGuardian -Name $VMName -WarningAction SilentlyContinue
        WriteLog 'Removal complete'
        WriteLog 'Cleaning up HGS Guardian certs'
        $certs = Get-ChildItem -Path $certPath -Recurse | Where-Object { $_.Subject -like "*$VMName*" }
        foreach ($cert in $Certs) {
            Remove-item -Path $cert.PSPath -force | Out-Null
        }
        WriteLog 'Cert removal complete'
    }
    #If just building the FFU from vhdx, remove the vhdx path
    If (-not $InstallApps -and $VhdxDisk) {
        WriteLog 'Cleaning up VHDX'
        WriteLog "Removing $VMPath"
        if (-not [string]::IsNullOrWhiteSpace($VMPath)) {
            Remove-Item -Path $VMPath -Force -Recurse -ErrorAction SilentlyContinue | Out-Null
        }
        WriteLog 'Removal complete'
    }

    #Remove orphaned mounted images
    $mountedImages = Get-WindowsImage -Mounted
    if ($mountedImages) {
        foreach ($image in $mountedImages) {
            $mountPath = $image.Path
            WriteLog "Dismounting image at $mountPath"
            Dismount-WindowsImage -Path $mountPath -discard
            WriteLog "Successfully dismounted image at $mountPath"
        }
    }
    #Remove Mount folder if it exists
    If (Test-Path -Path "$FFUDevelopmentPath\Mount") {
        WriteLog "Remove $FFUDevelopmentPath\Mount folder"
        Remove-Item -Path "$FFUDevelopmentPath\Mount" -Recurse -Force -ErrorAction SilentlyContinue
        WriteLog 'Folder removed'
    }
    #Remove unused mountpoints
    WriteLog 'Remove unused mountpoints'
    Invoke-Process cmd "/c mountvol /r" | Out-Null
    WriteLog 'Removal complete'
}

function Get-FFUEnvironment {
    <#
    .SYNOPSIS
    Cleans up FFU build environment after failed or incomplete builds

    .DESCRIPTION
    Performs comprehensive environment cleanup including VMs, VHDXs, mounted images,
    stale downloads, user accounts, and temporary files. Called when dirty.txt is detected
    or when explicit cleanup is requested.

    .PARAMETER FFUDevelopmentPath
    Root FFUDevelopment path

    .PARAMETER CleanupCurrentRunDownloads
    Boolean indicating whether to clean up current run downloads

    .PARAMETER VMLocation
    Path to VM storage location (defaults to FFUDevelopmentPath\VM if not provided)

    .PARAMETER UserName
    FFU user account name to remove

    .PARAMETER RemoveApps
    Boolean indicating whether to remove Apps folder

    .PARAMETER AppsPath
    Path to Apps folder

    .PARAMETER RemoveUpdates
    Boolean indicating whether to remove Updates folder

    .PARAMETER KBPath
    Path to KB updates folder

    .PARAMETER AppsISO
    Path to Apps ISO file

    .EXAMPLE
    Get-FFUEnvironment -FFUDevelopmentPath "C:\FFU" -CleanupCurrentRunDownloads $true `
                       -VMLocation "C:\FFU\VM" -UserName "ffu_user" -RemoveApps $false `
                       -AppsPath "C:\FFU\Apps" -RemoveUpdates $false -KBPath "C:\FFU\KB" `
                       -AppsISO "C:\FFU\Apps\Apps.iso"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath,

        [Parameter(Mandatory = $true)]
        [bool]$CleanupCurrentRunDownloads,

        [Parameter(Mandatory = $false)]
        [string]$VMLocation,

        [Parameter(Mandatory = $true)]
        [string]$UserName,

        [Parameter(Mandatory = $true)]
        [bool]$RemoveApps,

        [Parameter(Mandatory = $true)]
        [string]$AppsPath,

        [Parameter(Mandatory = $true)]
        [bool]$RemoveUpdates,

        [Parameter(Mandatory = $true)]
        [string]$KBPath,

        [Parameter(Mandatory = $true)]
        [string]$AppsISO
    )

    WriteLog 'Dirty.txt file detected. Last run did not complete succesfully. Will clean environment'
    try {
        Remove-InProgressItems -FFUDevelopmentPath $FFUDevelopmentPath `
                              -DriversFolder "$FFUDevelopmentPath\Drivers" `
                              -OfficePath "$FFUDevelopmentPath\Office"
    }
    catch {
        WriteLog "Remove-InProgressItems failed: $($_.Exception.Message)"
    }
    if ($CleanupCurrentRunDownloads) {
        try {
            Cleanup-CurrentRunDownloads -FFUDevelopmentPath $FFUDevelopmentPath `
                                       -AppsPath $AppsPath -DefenderPath "$FFUDevelopmentPath\Defender" `
                                       -MSRTPath "$FFUDevelopmentPath\MSRT" -OneDrivePath "$FFUDevelopmentPath\OneDrive" `
                                       -EdgePath "$FFUDevelopmentPath\Edge" -KBPath $KBPath `
                                       -DriversFolder "$FFUDevelopmentPath\Drivers" `
                                       -orchestrationPath "$FFUDevelopmentPath\Orchestration" `
                                       -OfficePath "$FFUDevelopmentPath\Office"
        }
        catch {
            WriteLog "Cleanup-CurrentRunDownloads failed: $($_.Exception.Message)"
        }
        try {
            Restore-RunJsonBackups -FFUDevelopmentPath $FFUDevelopmentPath `
                                  -DriversFolder "$FFUDevelopmentPath\Drivers" `
                                  -orchestrationPath "$FFUDevelopmentPath\Orchestration"
        }
        catch {
            WriteLog "Restore-RunJsonBackups failed: $($_.Exception.Message)"
        }
    }
    # Check for running VMs that start with '_FFU-' and are in the 'Off' state
    $vms = Get-VM

    # Loop through each VM
    foreach ($vm in $vms) {
        if ($vm.Name.StartsWith("_FFU-")) {
            if ($vm.State -eq 'Running') {
                Stop-VM -Name $vm.Name -TurnOff -Force
            }
            # If conditions are met, delete the VM
            # Note: For old VMs we may not have VMPath, so we derive it
            $vmPath = Join-Path $FFUDevelopmentPath "VM\$($vm.Name)"
            Remove-FFUVM -VMName $vm.Name -VMPath $vmPath -InstallApps $true `
                         -VhdxDisk $null -FFUDevelopmentPath $FFUDevelopmentPath
        }
    }
    # Check for MSFT Virtual disks where location contains FFUDevelopment in the path
    $disks = Get-Disk -FriendlyName *virtual*
    foreach ($disk in $disks) {
        $diskNumber = $disk.Number
        $vhdLocation = $disk.Location
        if ($vhdLocation -like "*FFUDevelopment*") {
            WriteLog "Dismounting Virtual Disk $diskNumber with Location $vhdLocation"
            Dismount-ScratchVhdx -VhdxPath $vhdLocation
            $parentFolder = Split-Path -Parent $vhdLocation
            WriteLog "Removing folder $parentFolder"
            if (-not [string]::IsNullOrWhiteSpace($parentFolder)) {
                Remove-Item -Path $parentFolder -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # Check for mounted DiskImages
    $volumes = Get-Volume | Where-Object { $_.DriveType -eq 'CD-ROM' }
    foreach ($volume in $volumes) {
        $letter = $volume.DriveLetter
        WriteLog "Dismounting DiskImage for volume $letter"
        Get-Volume $letter | Get-DiskImage | Dismount-DiskImage | Out-Null
        WriteLog "Dismounting complete"
    }

    # Remove unused mountpoints
    WriteLog 'Remove unused mountpoints'
    Invoke-Process cmd "/c mountvol /r" | Out-Null
    WriteLog 'Removal complete'

    # Check for content in the VM folder and delete any folders that start with _FFU-
    if ([string]::IsNullOrWhiteSpace($VMLocation)) {
        $VMLocation = Join-Path $FFUDevelopmentPath 'VM'
        WriteLog "VMLocation not set; defaulting to $VMLocation"
    }
    if (Test-Path -Path $VMLocation) {
        $folders = Get-ChildItem -Path $VMLocation -Directory
        foreach ($folder in $folders) {
            if ($folder.Name -like '_FFU-*') {
                WriteLog "Removing folder $($folder.FullName)"
                Remove-Item -Path $folder.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    else {
        WriteLog "VMLocation path $VMLocation not found; skipping VM folder cleanup"
    }

    # Remove orphaned mounted images
    $mountedImages = Get-WindowsImage -Mounted
    if ($mountedImages) {
        foreach ($image in $mountedImages) {
            $mountPath = $image.Path
            WriteLog "Dismounting image at $mountPath"
            try {
                Dismount-WindowsImage -Path $mountPath -discard | Out-null
                WriteLog "Successfully dismounted image at $mountPath"
            }
            catch {
                WriteLog "Failed to dismount image at $mountPath with error: $_"
            }
        }
    }

    # Remove Mount folder if it exists
    if (Test-Path -Path "$FFUDevelopmentPath\Mount") {
        WriteLog "Remove $FFUDevelopmentPath\Mount folder"
        Remove-Item -Path "$FFUDevelopmentPath\Mount" -Recurse -Force -ErrorAction SilentlyContinue
        WriteLog 'Folder removed'
    }

    #Clear any corrupt Windows mount points
    WriteLog 'Clearing any corrupt Windows mount points'
    Clear-WindowsCorruptMountPoint | Out-null
    WriteLog 'Complete'

    #Clean up registry
    if (Test-Path -Path 'HKLM:\FFU') {
        Writelog 'Found HKLM:\FFU, removing it'
        Invoke-Process reg "unload HKLM\FFU" | Out-Null
    }

    #Remove FFU User and Share (using .NET API for PowerShell 7 compatibility)
    $UserExists = Get-LocalUserAccount -Username $Username
    if ($UserExists) {
        WriteLog "Removing FFU User and Share"
        $UserExists.Dispose()
        Remove-FFUUserShare -Username $Username -ShareName $ShareName
        WriteLog 'Removal complete'
    }
    if ($RemoveApps) {
        WriteLog "Removing Apps in $AppsPath"
        Remove-Apps
    }
    # Clean up $KBPath only if RemoveUpdates is true (matches Apps folder behavior)
    If ($RemoveUpdates -and (Test-Path -Path $KBPath)) {
        WriteLog "Removing $KBPath (RemoveUpdates=true)"
        Remove-Item -Path $KBPath -Recurse -Force -ErrorAction SilentlyContinue
        WriteLog 'Removal complete'
    } elseif (Test-Path -Path $KBPath) {
        $kbFiles = Get-ChildItem -Path $KBPath -Recurse -File -ErrorAction SilentlyContinue
        if ($kbFiles -and $kbFiles.Count -gt 0) {
            $kbSize = ($kbFiles | Measure-Object -Property Length -Sum).Sum
            WriteLog "Keeping $KBPath ($($kbFiles.Count) files, $([math]::Round($kbSize/1MB, 2)) MB) for future builds - RemoveUpdates=false"
        }
    }
    # Remove existing Apps.iso
    if (Test-Path -Path $AppsISO) {
        WriteLog "Removing $AppsISO"
        Remove-Item -Path $AppsISO -Force -ErrorAction SilentlyContinue
        WriteLog 'Removal complete'
    }
    # Remove per-run session folder if present (Cancel/-Cleanup scenario)
    $sessionDir = Join-Path $FFUDevelopmentPath '.session'
    if (Test-Path -Path $sessionDir) {
        WriteLog 'Removing .session folder'
        Remove-Item -Path $sessionDir -Recurse -Force -ErrorAction SilentlyContinue
        WriteLog 'Removal complete'
    }
    WriteLog 'Removing dirty.txt file'
    $dirtyPath = Join-Path $FFUDevelopmentPath "dirty.txt"
    if (Test-Path -Path $dirtyPath) {
        Remove-Item -Path $dirtyPath -Force -ErrorAction SilentlyContinue
    }
    WriteLog "Cleanup complete"
}

function Set-CaptureFFU {
    <#
    .SYNOPSIS
    Creates FFU capture user account and network share

    .DESCRIPTION
    Creates a local user account and SMB share for FFU capture operations.
    The share is created with full control permissions for the specified user,
    allowing the FFU VM to write captured FFU files to the host machine.

    .PARAMETER Username
    Name of the local user account to create (default: ffu_user)

    .PARAMETER ShareName
    Name of the SMB share to create (default: FFUCaptureShare)

    .PARAMETER FFUCaptureLocation
    Local path on the host to share for FFU capture

    .PARAMETER Password
    Optional SecureString password for the user account.
    If not provided, a random secure password will be generated.

    .EXAMPLE
    Set-CaptureFFU -Username "ffu_user" -ShareName "FFUCaptureShare" -FFUCaptureLocation "C:\FFU"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Username,

        [Parameter(Mandatory = $true)]
        [string]$ShareName,

        [Parameter(Mandatory = $true)]
        [string]$FFUCaptureLocation,

        [Parameter(Mandatory = $false)]
        [SecureString]$Password
    )

    WriteLog "Setting up FFU capture user and share"

    try {
        # Generate cryptographically secure password if not provided
        # SECURITY: Uses New-SecureRandomPassword which generates directly to SecureString
        # Password never exists as plain text during generation
        if (-not $Password) {
            WriteLog "Generating cryptographically secure password for user $Username"
            $Password = New-SecureRandomPassword -Length 20 -IncludeSpecialChars $true
            WriteLog "Password generated (20 chars, cryptographic RNG, direct to SecureString)"
        }

        # Check if user already exists (using .NET API for PowerShell 7 compatibility)
        $existingUser = Get-LocalUserAccount -Username $Username

        if ($existingUser) {
            WriteLog "User $Username already exists, resetting password to ensure sync with CaptureFFU.ps1"
            $existingUser.Dispose()
            # CRITICAL FIX: Reset the password on existing user to prevent "Password is incorrect" error (Error 86)
            # This ensures the password in CaptureFFU.ps1 always matches the user's actual password
            Set-LocalUserPassword -Username $Username -Password $Password
            WriteLog "Password reset successfully for existing user $Username"
        }
        else {
            WriteLog "Creating local user account: $Username"
            New-LocalUserAccount -Username $Username -Password $Password `
                                -FullName "FFU Capture User" `
                                -Description "User account for FFU capture operations" | Out-Null
            WriteLog "User account $Username created successfully"

            # Register cleanup for user account in case of failure
            if (Get-Command Register-UserAccountCleanup -ErrorAction SilentlyContinue) {
                $null = Register-UserAccountCleanup -Username $Username
                WriteLog "Registered user account cleanup handler"
            }
        }

        # SECURITY: Set account expiry as failsafe (4 hours from now)
        # This ensures the temporary account is automatically disabled even if cleanup fails
        try {
            $expiryDate = Set-LocalUserAccountExpiry -Username $Username -ExpiryHours 4
            WriteLog "SECURITY: Account $Username set to expire at $($expiryDate.ToString('yyyy-MM-dd HH:mm:ss'))"
        }
        catch {
            WriteLog "WARNING: Failed to set account expiry (non-critical): $($_.Exception.Message)"
            # Continue - this is a security enhancement, not a requirement
        }

        # Create FFU capture directory if it doesn't exist
        if (-not (Test-Path $FFUCaptureLocation)) {
            WriteLog "Creating FFU capture directory: $FFUCaptureLocation"
            New-Item -Path $FFUCaptureLocation -ItemType Directory -Force | Out-Null
            WriteLog "Directory created successfully"
        }
        else {
            WriteLog "FFU capture directory already exists: $FFUCaptureLocation"
        }

        # Check if share already exists
        $existingShare = Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue

        if ($existingShare) {
            WriteLog "Share $ShareName already exists, skipping share creation"
        }
        else {
            WriteLog "Creating SMB share: $ShareName pointing to $FFUCaptureLocation"
            New-SmbShare -Name $ShareName -Path $FFUCaptureLocation -FullAccess $Username `
                        -Description "FFU Capture Share" -ErrorAction Stop | Out-Null
            WriteLog "SMB share $ShareName created successfully"

            # Register cleanup for network share in case of failure
            if (Get-Command Register-NetworkShareCleanup -ErrorAction SilentlyContinue) {
                $null = Register-NetworkShareCleanup -ShareName $ShareName
                WriteLog "Registered network share cleanup handler"
            }
        }

        # Grant user full control to the share (in case share already existed)
        WriteLog "Granting $Username full control to share $ShareName"
        Grant-SmbShareAccess -Name $ShareName -AccountName $Username -AccessRight Full -Force -ErrorAction Stop | Out-Null
        WriteLog "Share permissions granted successfully"

        WriteLog "FFU capture user and share setup complete"
        WriteLog "  User: $Username"
        WriteLog "  Share: \\$env:COMPUTERNAME\$ShareName"
        WriteLog "  Path: $FFUCaptureLocation"
    }
    catch {
        WriteLog "ERROR: Failed to set up FFU capture user and share: $($_.Exception.Message)"
        throw $_
    }
}

function Remove-FFUUserShare {
    <#
    .SYNOPSIS
    Removes FFU capture user account and network share

    .DESCRIPTION
    Cleans up the local user account and SMB share created by Set-CaptureFFU.
    This function is called during cleanup to remove temporary resources.

    .PARAMETER Username
    Name of the local user account to remove

    .PARAMETER ShareName
    Name of the SMB share to remove

    .EXAMPLE
    Remove-FFUUserShare -Username "ffu_user" -ShareName "FFUCaptureShare"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Username,

        [Parameter(Mandatory = $true)]
        [string]$ShareName
    )

    WriteLog "Cleaning up FFU capture user and share"

    try {
        # Remove SMB share if it exists
        $existingShare = Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue

        if ($existingShare) {
            WriteLog "Removing SMB share: $ShareName"
            Remove-SmbShare -Name $ShareName -Force -ErrorAction Stop
            WriteLog "SMB share removed successfully"
        }
        else {
            WriteLog "SMB share $ShareName does not exist, skipping removal"
        }

        # Remove local user if it exists (using .NET API for PowerShell 7 compatibility)
        $existingUser = Get-LocalUserAccount -Username $Username

        if ($existingUser) {
            WriteLog "Removing local user account: $Username"
            $existingUser.Dispose()
            Remove-LocalUserAccount -Username $Username
            WriteLog "User account removed successfully"
        }
        else {
            WriteLog "User $Username does not exist, skipping removal"
        }

        WriteLog "FFU capture user and share cleanup complete"
    }
    catch {
        WriteLog "WARNING: Failed to clean up FFU capture user and share: $($_.Exception.Message)"
        # Don't throw - cleanup failures shouldn't break the build
    }
}

function Remove-SensitiveCaptureMedia {
    <#
    .SYNOPSIS
    Securely removes sensitive data from capture media files

    .DESCRIPTION
    After FFU capture is complete, this function removes or sanitizes files
    that contain sensitive credentials (passwords) from the capture media
    and working directories. This is a security best practice to minimize
    credential exposure.

    SECURITY NOTE: The CaptureFFU.ps1 script on capture media contains
    plain text credentials required for WinPE to connect to the FFU share.
    This function should be called after capture is complete to sanitize
    these files.

    .PARAMETER FFUDevelopmentPath
    Path to the FFU development folder

    .PARAMETER SanitizeScript
    If true, overwrites credentials in CaptureFFU.ps1 with placeholder values.
    If false, deletes backup files but leaves the main script intact.
    Default is $true.

    .PARAMETER RemoveBackups
    If true, removes backup files of CaptureFFU.ps1 that may contain credentials.
    Default is $true.

    .EXAMPLE
    Remove-SensitiveCaptureMedia -FFUDevelopmentPath "C:\FFUDevelopment"

    .EXAMPLE
    Remove-SensitiveCaptureMedia -FFUDevelopmentPath "C:\FFUDevelopment" -SanitizeScript $true -RemoveBackups $true

    .NOTES
    SECURITY: This function helps minimize credential exposure by cleaning up
    sensitive data after the FFU capture process is complete.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath,

        [Parameter(Mandatory = $false)]
        [bool]$SanitizeScript = $true,

        [Parameter(Mandatory = $false)]
        [bool]$RemoveBackups = $true
    )

    WriteLog "SECURITY: Starting sensitive capture media cleanup"

    try {
        $captureScriptPath = Join-Path $FFUDevelopmentPath "WinPECaptureFFUFiles\CaptureFFU.ps1"
        $cleanupCount = 0

        # Remove backup files that may contain credentials
        if ($RemoveBackups) {
            $backupPattern = Join-Path $FFUDevelopmentPath "WinPECaptureFFUFiles\CaptureFFU.ps1.backup-*"
            $backupFiles = Get-ChildItem -Path $backupPattern -ErrorAction SilentlyContinue

            foreach ($backup in $backupFiles) {
                try {
                    # Overwrite with random data before deleting (secure delete)
                    $randomData = -join ((1..($backup.Length / 2)) | ForEach-Object { [char](Get-Random -Minimum 32 -Maximum 127) })
                    Set-Content -Path $backup.FullName -Value $randomData -Force -ErrorAction SilentlyContinue
                    Remove-Item -Path $backup.FullName -Force -ErrorAction Stop
                    $cleanupCount++
                    WriteLog "SECURITY: Removed backup file: $($backup.Name)"
                }
                catch {
                    WriteLog "WARNING: Failed to remove backup file $($backup.Name): $($_.Exception.Message)"
                }
            }
        }

        # Sanitize the main script by replacing credentials with placeholders
        if ($SanitizeScript -and (Test-Path $captureScriptPath)) {
            WriteLog "SECURITY: Sanitizing credentials in CaptureFFU.ps1"

            try {
                $scriptContent = Get-Content -Path $captureScriptPath -Raw

                # Replace password with placeholder
                $scriptContent = $scriptContent -replace "(\`$Password\s*=\s*)['\`"][^'\`"]*['\`"]", "`$1'CREDENTIAL_REMOVED_FOR_SECURITY'"

                # Replace IP address with placeholder (optional, for extra privacy)
                # $scriptContent = $scriptContent -replace "(\`$VMHostIPAddress\s*=\s*)['\`"][^'\`"]*['\`"]", "`$1'0.0.0.0'"

                Set-Content -Path $captureScriptPath -Value $scriptContent -Force
                $cleanupCount++
                WriteLog "SECURITY: CaptureFFU.ps1 credentials sanitized"
            }
            catch {
                WriteLog "WARNING: Failed to sanitize CaptureFFU.ps1: $($_.Exception.Message)"
            }
        }

        WriteLog "SECURITY: Capture media cleanup complete ($cleanupCount items processed)"
    }
    catch {
        WriteLog "WARNING: Capture media cleanup encountered errors: $($_.Exception.Message)"
        # Don't throw - cleanup failures shouldn't break the build
    }
}

function Update-CaptureFFUScript {
    <#
    .SYNOPSIS
    Updates CaptureFFU.ps1 script with runtime configuration values

    .DESCRIPTION
    Replaces placeholder values in the CaptureFFU.ps1 template script with actual
    runtime values (VMHostIPAddress, ShareName, Username, Password, etc.).
    This function should be called after Set-CaptureFFU and before New-PEMedia
    to ensure the WinPE capture script has the correct connection parameters.

    .PARAMETER VMHostIPAddress
    IP address of the Hyper-V host that will host the FFU capture share

    .PARAMETER ShareName
    Name of the SMB share for FFU capture (e.g., FFUCaptureShare)

    .PARAMETER Username
    Username for authenticating to the FFU capture share

    .PARAMETER Password
    Password for authenticating to the FFU capture share (plain text or SecureString)

    .PARAMETER FFUDevelopmentPath
    Path to the FFU development folder containing WinPECaptureFFUFiles

    .PARAMETER CustomFFUNameTemplate
    Optional custom FFU naming template with placeholders

    .EXAMPLE
    # Using SecureString for password (recommended)
    $securePassword = New-SecureRandomPassword
    Update-CaptureFFUScript -VMHostIPAddress "192.168.1.100" -ShareName "FFUCaptureShare" `
                            -Username "ffu_user" -Password $securePassword `
                            -FFUDevelopmentPath "C:\FFUDevelopment"

    .EXAMPLE
    # Using Read-Host for interactive password entry
    $securePassword = Read-Host -Prompt "Enter password" -AsSecureString
    Update-CaptureFFUScript -VMHostIPAddress "192.168.1.100" -ShareName "FFUCaptureShare" `
                            -Username "ffu_user" -Password $securePassword `
                            -FFUDevelopmentPath "C:\FFUDevelopment"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMHostIPAddress,

        [Parameter(Mandatory = $true)]
        [string]$ShareName,

        [Parameter(Mandatory = $true)]
        [string]$Username,

        [Parameter(Mandatory = $true)]
        $Password,  # Can be string or SecureString

        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath,

        [Parameter(Mandatory = $false)]
        [string]$CustomFFUNameTemplate
    )

    WriteLog "Updating CaptureFFU.ps1 script with runtime configuration"

    try {
        # Construct path to CaptureFFU.ps1 script
        $captureFFUScriptPath = Join-Path $FFUDevelopmentPath "WinPECaptureFFUFiles\CaptureFFU.ps1"

        # Validate script file exists
        if (-not (Test-Path -Path $captureFFUScriptPath -PathType Leaf)) {
            $errorMsg = "CaptureFFU.ps1 script not found at expected location: $captureFFUScriptPath"
            WriteLog "ERROR: $errorMsg"
            throw $errorMsg
        }

        WriteLog "Found CaptureFFU.ps1 at: $captureFFUScriptPath"

        # Create backup of original script (for safety)
        $backupPath = "$captureFFUScriptPath.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        WriteLog "Creating backup: $backupPath"
        Copy-Item -Path $captureFFUScriptPath -Destination $backupPath -Force
        WriteLog "Backup created successfully"

        # Read current script content
        WriteLog "Reading current script content"
        $scriptContent = Get-Content -Path $captureFFUScriptPath -Raw

        # Validate script contains expected placeholder variables
        $requiredVariables = @('$VMHostIPAddress', '$ShareName', '$UserName', '$Password')
        $missingVariables = @()

        foreach ($variable in $requiredVariables) {
            if ($scriptContent -notmatch [regex]::Escape($variable)) {
                $missingVariables += $variable
            }
        }

        if ($missingVariables.Count -gt 0) {
            $errorMsg = "CaptureFFU.ps1 is missing expected placeholder variables: $($missingVariables -join ', ')"
            WriteLog "WARNING: $errorMsg"
            WriteLog "Script may have been modified. Proceeding with update but results may be unexpected."
        }

        # Convert SecureString password to plain text if needed
        if ($Password -is [SecureString]) {
            WriteLog "Converting SecureString password to plain text for script injection"
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
            try {
                $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            }
            finally {
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            }
        }
        else {
            $plainPassword = $Password
        }

        # Perform replacements using regex to match variable assignment pattern
        WriteLog "Replacing placeholder values with runtime configuration:"
        WriteLog "  VMHostIPAddress: $VMHostIPAddress"
        WriteLog "  ShareName: $ShareName"
        WriteLog "  Username: $Username"
        WriteLog "  Password: [REDACTED - length $($plainPassword.Length)]"

        # Replace each variable assignment (pattern: $VarName = 'value' or $VarName = "value")
        $scriptContent = $scriptContent -replace '(\$VMHostIPAddress\s*=\s*)[''"].*?[''"]', "`$1'$VMHostIPAddress'"
        $scriptContent = $scriptContent -replace '(\$ShareName\s*=\s*)[''"].*?[''"]', "`$1'$ShareName'"
        $scriptContent = $scriptContent -replace '(\$UserName\s*=\s*)[''"].*?[''"]', "`$1'$Username'"
        $scriptContent = $scriptContent -replace '(\$Password\s*=\s*)[''"].*?[''"]', "`$1'$plainPassword'"

        # Update CustomFFUNameTemplate if provided
        if (![string]::IsNullOrEmpty($CustomFFUNameTemplate)) {
            WriteLog "  CustomFFUNameTemplate: $CustomFFUNameTemplate"
            $scriptContent = $scriptContent -replace '(\$CustomFFUNameTemplate\s*=\s*)[''"].*?[''"]', "`$1'$CustomFFUNameTemplate'"
        }

        # Write updated content back to script file
        WriteLog "Writing updated script content to: $captureFFUScriptPath"
        Set-Content -Path $captureFFUScriptPath -Value $scriptContent -Force -Encoding UTF8

        WriteLog "CaptureFFU.ps1 script updated successfully"

        # Verify the update by re-reading and checking values
        WriteLog "Verifying script update..."
        $verifyContent = Get-Content -Path $captureFFUScriptPath -Raw

        $verificationPassed = $true
        if ($verifyContent -notmatch [regex]::Escape($VMHostIPAddress)) {
            WriteLog "WARNING: VMHostIPAddress not found in updated script"
            $verificationPassed = $false
        }
        if ($verifyContent -notmatch [regex]::Escape($ShareName)) {
            WriteLog "WARNING: ShareName not found in updated script"
            $verificationPassed = $false
        }
        if ($verifyContent -notmatch [regex]::Escape($Username)) {
            WriteLog "WARNING: Username not found in updated script"
            $verificationPassed = $false
        }

        if ($verificationPassed) {
            WriteLog "Script update verification PASSED"
        }
        else {
            WriteLog "WARNING: Script update verification had issues. Check the script manually."
        }

        WriteLog "Update-CaptureFFUScript completed successfully"
    }
    catch {
        WriteLog "ERROR: Failed to update CaptureFFU.ps1 script: $($_.Exception.Message)"
        WriteLog "Stack trace: $($_.ScriptStackTrace)"
        throw $_
    }
}

# Export module members
Export-ModuleMember -Function @(
    'Get-LocalUserAccount',
    'New-LocalUserAccount',
    'Remove-LocalUserAccount',
    'Set-LocalUserPassword',
    'Set-LocalUserAccountExpiry',
    'New-FFUVM',
    'Remove-FFUVM',
    'Get-FFUEnvironment',
    'Set-CaptureFFU',
    'Remove-FFUUserShare',
    'Update-CaptureFFUScript',
    'Remove-SensitiveCaptureMedia'
)