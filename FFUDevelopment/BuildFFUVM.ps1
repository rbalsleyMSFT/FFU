#Modify variables
$VMPath = "c:\VM\$VMName"
$ISOPath = "E:\software\ISOs\Windows\Windows 11\en-us_windows_11_consumer_editions_version_22h2_updated_feb_2023_x64_dvd_4fa87138.iso"
$memory = 8GB
$disksize = 30GB
$processors = 4
$rand = get-random
$VMName = "_FFU-$rand"
$VHDPath = "$VMPath\$VMName.vhdx"

# 0. Delete old VMs and remove old certs

$certPath = 'Cert:\LocalMachine\Shielded VM Local Certificates\'
$vms = get-vm _ffu-* | ? {$_.state -ne 'running'}

If($null -ne $vms){
    Foreach ($vm in $vms){
        $OldVMName = $vm.VMName
        Remove-VM -Name $vm.name -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "C:\VM\$OldVMName" -Force -Recurse -ErrorAction SilentlyContinue
        Remove-HgsGuardian -Name $OldVMName
        $certs = Get-ChildItem -Path $certPath -Recurse | Where-Object { $_.Subject -like "*$OldVMName*" }
        foreach ($cert in $Certs){
            Remove-item -Path $cert.PSPath -force
        }
    }
}

# 1. Create Dynamic Hard Disk
mkdir -Path $VMPath -Force
New-VHD -Path $VHDPath -Fixed -SizeBytes $disksize
#New-VHD -path $VHDPath -SizeBytes 128000000000 -LogicalSectorSizeBytes 512 -Dynamic

# 2. Create VM
#     - Name: _FFU
#     - Location: C:\VM\_FFU
#     - Generation: 2
#     - Memory: 4GB static
#     - Networking: Not connected
#     - Connect to existing VHD: c:\VM\_FFU\
#     - Mount ISO
$VM = New-VM -Name $VMName -Path $VMPath -MemoryStartupBytes $memory -VHDPath $VHDPath -Generation 2
Set-VMProcessor -VMName $VMName -Count $processors
Add-VMDvdDrive -VMName $VMName -Path $ISOPath
$VMDVDDrive = Get-VMDvdDrive -VMName $VMName
Set-VMFirmware -VMName $VMName -FirstBootDevice $VMDVDDrive

#Configure TPM
New-HgsGuardian -Name $VMName -GenerateCertificates
$owner = get-hgsguardian -Name $VMName
$kp = New-HgsKeyProtector -Owner $owner -AllowUntrustedRoot
Set-VMKeyProtector -VMName $VMName -KeyProtector $kp.RawData
Enable-VMTPM -VMName $VMName

#Connect to VM
vmconnect $VM.ComputerName $VMName

#Use if creating for MDT/SCCM Builds
#Get-VM $VMName | Get-VMNetworkAdapter | Connect-VMNetworkAdapter -SwitchName "Intel(R) I350 Gigabit Network Connection - Virtual Switch"
#$networkAdapter = Get-VMNetworkAdapter -VMName $VMName