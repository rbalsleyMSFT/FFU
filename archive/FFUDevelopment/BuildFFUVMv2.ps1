#Requires -Modules Hyper-V, Storage
#Requires -PSEdition Desktop

# To do list (will get around to this stuff sometime next week)

# Change from using variables to parameters - this way you don't even need to open the script to edit it.
# Clean up the output it sends to powershell so you know what step you're on
# Do some real logging incase folks get in trouble and need my help
# Edit the WinPECaptureFFUFiles\CaptureFFU.ps1 file within this script instead of doing it manually. 
# Make Capture/Deploy media creation optional
# Change DownloadFFU.xml file to match C:\FFUDevelopment path
# If drivers = true, check if drivers folder exists
# C:\VM\VMFolder isn't being deleted

#Modify Required variables
$ISOPath = "E:\software\ISOs\Windows\Windows 11\en-us_windows_11_consumer_editions_version_22h2_updated_feb_2023_x64_dvd_4fa87138.iso"
$WindowsSKU = 'Pro'
$FFUDevelopmentPath = 'C:\FFUDevelopment'
$AppsISO = "$FFUDevelopmentPath\Apps.iso"
$AppsPath = "$FFUDevelopmentPath\Apps"
$InstallOffice = $true
$InstallApps = $true
$InstallDrivers = $true
$memory = 8GB
$disksize = 30GB
$processors = 4
$VMSwitchName = '*intel*'

#Optional variables
$rand = get-random
$VMName = "_FFU-$rand"
$VMLocation = "c:\VM"
$VMPath = $VMLocation + $VMName
$VHDXPath = "$VMPath\$VMName.vhdx"

#FUNCTIONS
Function Get-ADK {
    # Define the registry key and value name to query
    $adkRegKey = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots"
    $adkRegValueName = "KitsRoot10"

    # Check if the registry key exists
    if (Test-Path $adkRegKey) {
        # Get the registry value for the Windows ADK installation path
        $adkPath = (Get-ItemProperty -Path $adkRegKey -Name $adkRegValueName).$adkRegValueName

        if ($adkPath) {
            return $adkPath
        }
    }
    else {
        throw "Windows ADK is not installed or the installation path could not be found."
    }
}
function Get-ODTURL {

    [String]$MSWebPage = Invoke-RestMethod 'https://www.microsoft.com/en-us/download/confirmation.aspx?id=49117'
  
    $MSWebPage | ForEach-Object {
      if ($_ -match 'url=(https://.*officedeploymenttool.*\.exe)') {
        $matches[1]
      }
    }
}

function Get-Office {
    #Download ODT
    $ODTUrl = Get-ODTURL
    $ODTInstallFile = "$env:TEMP\odtsetup.exe"
    Invoke-WebRequest -Uri $ODTUrl -OutFile $ODTInstallFile

    # Extract ODT
    $ODTPath = "$AppsPath\Office"
    Start-Process -FilePath $ODTInstallFile -ArgumentList "/extract:$ODTPath /quiet" -Wait

    # Run setup.exe with config.xml
    $ConfigXml = "$ODTPath\DownloadFFU.xml"
    #Set-Location $ODTPath
    Start-Process -FilePath "$ODTPath\setup.exe" -ArgumentList "/download $ConfigXml" -Wait

    #Clean up default configuration files
    Remove-Item -Path "$ODTPath\configuration*" -Force
}

function New-AppsISO {
    #Create Apps ISO file
    $OSCDIMG = 'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe'
    Start-Process -FilePath $OSCDIMG -ArgumentList "-n -m -d $Appspath $AppsISO" -wait
    
    #Remove the Office Download and ODT
    if ($InstallOffice) {
        $ODTPath = "$AppsPath\Office"
        $OfficeDownloadPath = "$ODTPath\Office"
        Remove-Item -Path $OfficeDownloadPath -Recurse -Force
        Remove-Item -Path "$ODTPath\setup.exe"
    }
    
}




function Get-WimFromISO {
    # Mount the ISO file using Mount-DiskImage cmdlet
    $mountResult = Mount-DiskImage -ImagePath $isoPath -PassThru

    # Get the drive letter of the mounted ISO
    $driveLetter = ($mountResult | Get-Volume).DriveLetter

    # Construct the path to the install.wim file
    $wimPath = $driveLetter + ":\sources\install.wim"

    # Display the path to the install.wim file
    Write-Host "The path to the install.wim file is: $wimPath"

    return $wimpath

}

function Get-WimIndex {
    [Parameter(Mandatory = $true)]
    [string]$WindowsSKU

    $wimindex = switch ($WindowsSKU) {
        Home { 1 }
        Home_N { 2 }
        Home_SL { 3 }
        EDU { 4 }
        EDU_N { 5 }
        Pro { 6 }
        Pro_N { 7 }
        Pro_EDU { 8 }
        Pro_Edu_N { 9 }
        Pro_WKS { 10 }
        Pro_WKS_N { 11 }
        Default { 6 }
    }
    Return $WimIndex
}

#Build VHDX
#Create VHDX
function New-ScratchVhdx {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VhdxPath,
        [uint64]$SizeBytes = 30GB,
        [ValidateSet(512, 4096)]
        [uint32]$LogicalSectorSizeBytes = 512,
        [switch]$Dynamic,
        [Microsoft.PowerShell.Cmdletization.GeneratedTypes.Disk.PartitionStyle]$PartitionStyle = [Microsoft.PowerShell.Cmdletization.GeneratedTypes.Disk.PartitionStyle]::GPT
    )

    Write-Host "Creating new Scratch VHDX..."

    $newVHDX = New-VHD -Path $VhdxPath -SizeBytes $disksize -LogicalSectorSizeBytes $LogicalSectorSizeBytes -Fixed:$true
    $toReturn = $newVHDX | Mount-VHD -Passthru | Initialize-Disk -PassThru -PartitionStyle GPT

    #Remove auto-created system partition so we can create the correct partition layout
    remove-partition $toreturn.DiskNumber -PartitionNumber 1 -Confirm:$False

    Write-Host "Done."
    return $toReturn
}
#Add System Partition
function New-SystemPartition {
    param(
        [Parameter(Mandatory = $true)]
        [ciminstance]$VhdxDisk,
        [uint64]$SystemPartitionSize = 256MB
    )

    Write-Host "Creating System partition..."

    $sysPartition = $VhdxDisk | New-Partition -AssignDriveLetter -Size $SystemPartitionSize -GptType "{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}" -IsHidden
    $sysPartition | Format-Volume -FileSystem FAT32 -Force -NewFileSystemLabel "System"

    Write-Host "Done. System partition at drive $($sysPartition.DriveLetter):"
    return $sysPartition.DriveLetter
}
#Add MSRPartition - skip this initially unless needed
function New-MSRPartition {
    param(
        [Parameter(Mandatory = $true)]
        [ciminstance]$VhdxDisk
    )

    Write-Host "Creating MSR partition..."

    $toReturn = $VhdxDisk | New-Partition -AssignDriveLetter -Size 16MB -GptType "{e3c9e316-0b5c-4db8-817d-f92df00215ae}" -IsHidden

    Write-Host "Done."

    return $toReturn
}
#Add OS Partition
function New-OSPartition {
    param(
        [Parameter(Mandatory = $true)]
        [ciminstance]$VhdxDisk,
        [Parameter(Mandatory = $true)]
        [string]$WimPath,
        [uint32]$WimIndex,
        [uint64]$OSPartitionSize = 0
    )

    Write-Host "Creating OS partition..."

    if ($OSPartitionSize -gt 0) {
        $osPartition = $vhdxDisk | New-Partition -AssignDriveLetter -Size $OSPartitionSize
    }
    else {
        $osPartition = $vhdxDisk | New-Partition -AssignDriveLetter -UseMaximumSize
    }

    $osPartition | Format-Volume -FileSystem NTFS -Confirm:$false -Force -NewFileSystemLabel "Windows"
    Write-Host "Done. OS partition at drive $($osPartition.DriveLetter):"

    Write-Host "Writing WIM at $WimPath to OS partition at drive $($osPartition.DriveLetter):..."
    
    #Server 2019 is missing the Windows Overlay Filter (wof.sys), likely other Server SKUs are missing it as well. Script will error if trying to use the -compact switch on Server OSes
    if ((Get-CimInstance Win32_OperatingSystem).Caption -match "Server") {
        Write-Host (Expand-WindowsImage -ImagePath $WimPath -Index $WimIndex -ApplyPath "$($osPartition.DriveLetter):\")
    }
    else {
        Write-Host (Expand-WindowsImage -ImagePath $WimPath -Index $WimIndex -ApplyPath "$($osPartition.DriveLetter):\" -Compact)
    }
    
    Write-Host "Done."
    
    return $osPartition
}

#Add Recovery partition
function New-RecoveryPartition {
    param(
        [Parameter(Mandatory = $true)]
        [ciminstance]$VhdxDisk,
        [Parameter(Mandatory = $true)]
        $OsPartition,
        [uint64]$RecoveryPartitionSize = 0,
        [ciminstance]$DataPartition
    )

    Write-Host "Creating empty Recovery partition (to be filled on first boot automatically)..."
    
    $calculatedRecoverySize = 0
    $recoveryPartition = $null

    if ($RecoveryPartitionSize -gt 0) {
        $calculatedRecoverySize = $RecoveryPartitionSize
    }
    else {
        $winReWim = Get-ChildItem "$($OsPartition.DriveLetter):\Windows\System32\Recovery\Winre.wim"

        if (($null -ne $winReWim) -and ($winReWim.Count -eq 1)) {
            # Wim size + 52MB is minimum WinRE partition size.
            # NTFS and other partitioning size differences account for about 17MB of space that's unavailable.
            # Adding 32MB as a buffer to ensure there's enough space.
            $calculatedRecoverySize = $winReWim.Length + 52MB + 32MB

            Write-Host "Calculated space needed for recovery in bytes: $calculatedRecoverySize"

            if ($null -ne $DataPartition) {
                $DataPartition | Resize-Partition -Size ($DataPartition.Size - $calculatedRecoverySize)
                Write-Host "Data partition shrunk by $calculatedRecoverySize bytes for Recovery partition."
            }
            else {
                $OsPartition | Resize-Partition -Size ($OsPartition.Size - $calculatedRecoverySize)
                Write-Host "OS partition shrunk by $calculatedRecoverySize bytes for Recovery partition."
            }

            $recoveryPartition = $VhdxDisk | New-Partition -AssignDriveLetter -UseMaximumSize -GptType "{de94bba4-06d1-4d40-a16a-bfd50179d6ac}" `
            | Format-Volume -FileSystem NTFS -Confirm:$false -Force -NewFileSystemLabel "WinRE"

            Write-Host "Done. Recovery partition at drive $($recoveryPartition.DriveLetter):"
        }
        else {
            Write-Host "No WinRE.WIM found in the OS partition under \Windows\System32\Recovery."
            Write-Host "Skipping creating the Recovery partition."
            Write-Host "If a Recovery partition is desired, please re-run the script setting the -RecoveryPartitionSize flag as appropriate."
        }
    }

    return $recoveryPartition
}
#Add boot files
function Add-BootFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OsPartitionDriveLetter,
        [Parameter(Mandatory = $true)]
        [string]$SystemPartitionDriveLetter,
        [string]$FirmwareType = 'UEFI'
    )

    Write-Host "Adding boot files for `"$($OsPartitionDriveLetter):\Windows`" to System partition `"$($SystemPartitionDriveLetter):`"..."

    bcdboot "$($OsPartitionDriveLetter):\Windows" /S "$($SystemPartitionDriveLetter):" /F "$FirmwareType"

    Write-Host "Done."
}

#Dismount VHDX
function Dismount-ScratchVhdx {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VhdxPath
    )

    if (Test-Path $VhdxPath) {
        Write-Host "Dismounting scratch VHDX..."
        Dismount-VHD -Path $VhdxPath
        Write-Host "Done."
    }
}

#Delete old VMs and remove old certs
function Remove-FFUVM {
    $certPath = 'Cert:\LocalMachine\Shielded VM Local Certificates\'
    $OLDFFUVMs = get-vm _ffu-* | Where-Object { $_.state -ne 'running' }

    If ($null -ne $OLDFFUVMs) {
        Foreach ($OLDFFUVM in $OLDFFUVMs) {
            $OldVMName = $OLDFFUVM.VMName
            Remove-VM -Name $OLDFFUVM.name -Force -ErrorAction SilentlyContinue
            #Remove-Item -Path "C:\VM\$OldVMName" -Force -Recurse -ErrorAction SilentlyContinue
            Remove-Item -Path "$VMLocation\$OLDVMName"  -Force -Recurse -ErrorAction SilentlyContinue
            Remove-HgsGuardian -Name $OldVMName
            $certs = Get-ChildItem -Path $certPath -Recurse | Where-Object { $_.Subject -like "*$OldVMName*" }
            foreach ($cert in $Certs) {
                Remove-item -Path $cert.PSPath -force
            }
        }
    }
}

function New-FFUVM {
    #Create new Gen2 VM
    $VM = New-VM -Name $VMName -Path $VMPath -MemoryStartupBytes $memory -VHDPath $VHDXPath -Generation 2
    Set-VMProcessor -VMName $VMName -Count $processors
    #Mount Office ISO
    Add-VMDvdDrive -VMName $VMName -Path $AppsISO
    $VMHardDiskDrive = Get-VMHarddiskdrive -VMName $VMName 
    Set-VMFirmware -VMName $VMName -FirstBootDevice $VMHardDiskDrive
    Set-VM -Name $VMName -AutomaticCheckpointsEnabled $false -StaticMemory

    #Configure TPM
    New-HgsGuardian -Name $VMName -GenerateCertificates
    $owner = get-hgsguardian -Name $VMName
    $kp = New-HgsKeyProtector -Owner $owner -AllowUntrustedRoot
    Set-VMKeyProtector -VMName $VMName -KeyProtector $kp.RawData
    Enable-VMTPM -VMName $VMName

    #Connect to VM
    vmconnect $VM.ComputerName $VMName

    #Start VM
    Start-VM -Name $VMName
    return $VM
}
function New-PEMedia {
    param (
        [Parameter()]
        [switch]
        $Capture,
        [Parameter()]
        [switch]
        $Deploy
    )
    #Need to use the Demployment and Imaging tools environment to create winPE media
    $DandIEnv = "$adkPath`Assessment and Deployment Kit\Deployment Tools\DandISetEnv.bat"
    $WinPEFFUPath = "$FFUDevelopmentPath\WinPE"

    If (Test-path -Path "$WinPEFFUPath") {
        #Dismount-WindowsImage -Path "$WinPEFFUPath\mount" -discard
        Remove-Item -Path "$WinPEFFUPath" -Recurse -Force
    }

    & cmd /c """$DandIEnv"" && copype amd64 $WinPEFFUPath"
    Mount-WindowsImage -ImagePath "$WinPEFFUPath\media\sources\boot.wim" -Index 1 -Path "$WinPEFFUPath\mount"

    $Packages = @(
        "WinPE-WMI.cab",
        "en-us\WinPE-WMI_en-us.cab",
        "WinPE-NetFX.cab",
        "en-us\WinPE-NetFX_en-us.cab",
        "WinPE-Scripting.cab",
        "en-us\WinPE-Scripting_en-us.cab",
        "WinPE-PowerShell.cab",
        "en-us\WinPE-PowerShell_en-us.cab",
        "WinPE-StorageWMI.cab",
        "en-us\WinPE-StorageWMI_en-us.cab",
        "WinPE-DismCmdlets.cab",
        "en-us\WinPE-DismCmdlets_en-us.cab"
    )

    $PackagePathBase = "$adkPath`Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs\"

    foreach ($Package in $Packages) {
        $PackagePath = Join-Path $PackagePathBase $Package
        Add-WindowsPackage -Path "$WinPEFFUPath\mount" -PackagePath $PackagePath | Out-Null
    }
    If($Capture){
        Copy-Item -Path "$FFUDevelopmentPath\WinPECaptureFFUFiles\*" -Destination "$WinPEFFUPath\mount" -Recurse -Force
        #Remove Bootfix.bin if capturing from BIOS systems
        Remove-Item -Path "$WinPEFFUPath\media\boot\bootfix.bin" -Force
    }
    If($Deploy){
        Copy-Item -Path "$FFUDevelopmentPath\WinPEDeployFFUFiles\*" -Destination "$WinPEFFUPath\mount" -Recurse -Force
        # If you need to add drivers (storage/keyboard most likely), remove the '#' from the below line and change the /Driver:Path to a folder of drivers
        # & dism /image:$WinPEFFUPath\mount /Add-Driver /Driver:<Path to Drivers folder e.g c:\drivers> /Recurse
    } 
    Dismount-WindowsImage -Path "$WinPEFFUPath\mount" -Save
    #Make ISO
    $OSCDIMGPath = "$adkPath`Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg"
    $OSCDIMG = "$OSCDIMGPath\oscdimg.exe"
    & "$OSCDIMG" -m -o -u2 -udfver102 -bootdata:2`#p0,e,b$OSCDIMGPath\etfsboot.com`#pEF,e,b$OSCDIMGPath\Efisys_noprompt.bin $WinPEFFUPath\media $FFUDevelopmentPath\WinPE_FFU_Capture.iso
    Remove-Item -Path "$WinPEFFUPath" -Recurse -Force
}
function New-FFU {
    #Need to use the Demployment and Imaging tools environment to use dism from the Insider ADK to optimize the FFU. This is only needed until Windows 23H2.
    $DandIEnv = "$adkPath`Assessment and Deployment Kit\Deployment Tools\DandISetEnv.bat"
    #Mount the Capture ISO to the VM

    $CaptureISOPath = "$FFUDevelopmentPath\WinPE_FFU_Capture.iso"
    $FFUVMs = get-vm _ffu-* | Where-Object { $_.state -ne 'running' }

    If ($null -ne $FFUVMs) {
        Foreach ($FFUVM in $FFUVMs) {
            $VMName = $FFUVM.name
            $VMDVDDrive = Get-VMDvdDrive -VMName $VMName
            Set-VMFirmware -VMName $VMName -FirstBootDevice $VMDVDDrive
            Set-VMDvdDrive -VMName $VMName -Path $CaptureISOPath
            $VMSwitch = Get-VMSwitch -name $VMSwitchName
            get-vm $VMName | Get-VMNetworkAdapter | Connect-VMNetworkAdapter -SwitchName $VMSwitch.Name
            #vmconnect $FFUVM.ComputerName $VMName
        }
    }
    #Start VM
    Start-VM -Name $VMName

    # Wait for the VM to turn off
    do {
        $FFUVM = Get-VM -Name $VMName
        Start-Sleep -Seconds 5
    } while ($FFUVM.State -ne 'Off')

    # Check for .ffu files in the FFUDevelopment folder
    $FFUFiles = Get-ChildItem -Path $FFUDevelopmentPath -Filter "*.ffu" -File

    # If there's more than one .ffu file, get the most recent and store its path in $FFUFile
    if ($FFUFiles.Count -gt 0) {
        $FFUFile = ($FFUFiles | Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1).FullName
        Write-Host "Most recent .ffu file: $FFUFile"
    }
    else {
        Write-Host "No .ffu files found in $FFUFolderPath"
    }
    #Add drivers
    If ($InstallDrivers){
        New-Item -Path "$FFUDevelopmentPath\Mount" -ItemType Directory -Force
        Mount-WindowsImage -ImagePath $FFUFile -Index 1 -Path "$FFUDevelopmentPath\Mount"
        Add-WindowsDriver -Path "$FFUDevelopmentPath\Mount" -Driver "$FFUDevelopmentPath\Drivers" -Recurse
        Dismount-WindowsImage -Path "$FFUDevelopmentPath\Mount" -Save
        Remove-Item -Path "$FFUDevelopmentPath\Mount" -Recurse -Force
    }
    #Optimize FFU
    & cmd /c """$DandIEnv"" && dism /optimize-ffu /imagefile:$FFUFile"
}




try {
    #Check if the Windows ADK is installed
    $adkPath = Get-ADK
}
catch {
    throw $_
}

#Build ISO for Office and Apps
try{
    if($InstallOffice){
        Get-Office
    }
    if($InstallApps){
        New-AppsISO
    }
}
catch {
    Write-Host "Getting Office and/or building the AppsISO failed"
    throw $_
}

#Create VHDX
try {
    $wimPath = Get-WimFromISO

    $WimIndex = Get-WimIndex
    
    $vhdxDisk = New-ScratchVhdx -VhdxPath $VHDXPath -SizeBytes $disksize -Dynamic:$true

    $systemPartitionDriveLetter = New-SystemPartition -VhdxDisk $vhdxDisk
    
    New-MSRPartition -VhdxDisk $vhdxDisk
    
    $osPartition = New-OSPartition -VhdxDisk $vhdxDisk -OSPartitionSize $OSPartitionSize -WimPath $WimPath -WimIndex $WimIndex[1]
    $osPartitionDriveLetter = $osPartition[1].DriveLetter

    $recoveryPartition = New-RecoveryPartition -VhdxDisk $vhdxDisk -OsPartition $osPartition[1] -RecoveryPartitionSize $RecoveryPartitionSize -DataPartition $dataPartition

    Write-Host "All necessary partitions created."

    Add-BootFiles -OsPartitionDriveLetter $osPartitionDriveLetter -SystemPartitionDriveLetter $systemPartitionDriveLetter[1]
    New-Item -Path "$($osPartitionDriveLetter):\Windows\Panther\unattend" -ItemType Directory
    Copy-Item -Path "$FFUDevelopmentPath\BuildFFUUnattend\unattend.xml" -Destination "$($osPartitionDriveLetter):\Windows\Panther\Unattend\Unattend.xml" -Force
}
finally {
    Dismount-ScratchVhdx -VhdxPath $VHDXPath
    Dismount-DiskImage -ImagePath $ISOPath
}

#Clean up old VMs
try {
    Remove-FFUVM
}
catch {
    Write-Host "VM cleanup failed"
    throw $_
}

#Create VM and attach VHDX
try {
    $FFUVM = New-FFUVM
}
catch {
    Write-Host 'VM creation failed'
    throw $_
}
#Create Capture Media
try{
    #This should happen while the FFUVM is building
    New-PEMedia -Capture
}
catch{
    throw $_
}
#Capture FFU file
try {
    #Check if VM is done provisioning
    do {
        $FFUVM = Get-VM -Name $FFUVM.Name
        Start-Sleep -Seconds 10
    } while ($FFUVM.State -ne 'Off')

    #Capture FFU file
    New-FFU
}
Catch {
    throw $_
}