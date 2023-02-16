#Modify variables
$rand = get-random
$VMName = "_FFU-$rand"
$VMPath = "c:\VM\$VMName"
$VHDPath = "$VMPath\$VMName.vhdx"
$ISOPath = "E:\software\ISOs\Windows\Windows 11\22H2\en-us_windows_11_consumer_editions_version_22h2_updated_jan_2023_x64_dvd_aafaf7fa.iso"
$memory = 8GB
$processors = 4

# 0. Delete old VMs

$vms = get-vm _ffu-* | ? {$_.state -ne 'running'}

If($null -ne $vms){
    Foreach ($vm in $vms){
    $OldVMName = $vm.VMName
    Remove-VM -Name $vm.name -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "C:\VM\$OldVMName" -Force -Recurse -ErrorAction SilentlyContinue
    }
}

# 1. Create Dynamic Hard Disk
mkdir -Path $VMPath -Force
#New-VHD -Path $VHDPath -Fixed -SizeBytes 30GB
New-VHD -path $VHDPath -SizeBytes 128000000000 -LogicalSectorSizeBytes 512 -Dynamic

# 2. Create VM
#     - Name: _FFU
#     - Location: C:\VM\_FFU
#     - Generation: 2
#     - Memory: 4GB static
#     - Networking: Not connected
#     - Connect to existing VHD: c:\VM\_FFU\
#     - Mount ISO
New-VM -Name $VMName -Path $VMPath -MemoryStartupBytes $memory -VHDPath $VHDPath -Generation 2
Set-VMProcessor -VMName $VMName -Count $processors
Add-VMDvdDrive -VMName $VMName -Path $ISOPath
$VMDVDDrive = Get-VMDvdDrive -VMName $VMName

#Use for Win11
Set-VMFirmware -VMName $VMName -FirstBootDevice $VMDVDDrive
If(Get-HgsGuardian -Name 'Guardian'){
    Remove-HgsGuardian -Name 'Guardian'
    Get-ChildItem -Path 'Cert:\LocalMachine\Shielded VM Local Certificates\' | Remove-Item
}
New-HgsGuardian -Name 'Guardian' -GenerateCertificates
$owner = get-hgsguardian -Name 'Guardian'
$kp = New-HgsKeyProtector -Owner $owner -AllowUntrustedRoot
Set-VMKeyProtector -VMName $VMName -KeyProtector $kp.RawData
Enable-VMTPM -VMName $VMName

#Use if creating for MDT/SCCM Builds
#Get-VM $VMName | Get-VMNetworkAdapter | Connect-VMNetworkAdapter -SwitchName "Intel(R) I350 Gigabit Network Connection - Virtual Switch"
#$networkAdapter = Get-VMNetworkAdapter -VMName $VMName