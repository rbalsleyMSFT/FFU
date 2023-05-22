#Modify variables
$ISOPath = 'C:\FFUDevelopment\WinPE_FFU_Capture.iso'
$VMSwitchName = '*intel*'

$vms = get-vm _ffu-* | ? {$_.state -ne 'running'}


If($null -ne $vms){
    Foreach ($vm in $vms){
        $VMName = $vm.name
        $VMDVDDrive = Get-VMDvdDrive -VMName $VMName
        Set-VMFirmware -VMName $VMName -FirstBootDevice $VMDVDDrive
        Set-VMDvdDrive -VMName $VMName -Path $ISOPath
        $VMSwitch = Get-VMSwitch -name $VMSwitchName
        get-vm $VMName | Get-VMNetworkAdapter | Connect-VMNetworkAdapter -SwitchName $VMSwitch.Name
        vmconnect $vm.ComputerName $VMName
    }
}



