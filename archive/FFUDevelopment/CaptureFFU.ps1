#Modify variables
$ISOPath = 'C:\ffu\WinPE_FFU_Capture.iso'

$vms = get-vm _ffu* | ? {$_.state -ne 'running'}


If($null -ne $vms){
    Foreach ($vm in $vms){
        $VMName = $vm.name
        $VMDVDDrive = Get-VMDvdDrive -VMName $VMName
        Set-VMFirmware -VMName $VMName -FirstBootDevice $VMDVDDrive
        Set-VMDvdDrive -VMName $VMName -Path $ISOPath
        $VMSwitch = Get-VMSwitch -name *intel*
        get-vm $VMName | Get-VMNetworkAdapter | Connect-VMNetworkAdapter -SwitchName $VMSwitch.Name
    }
}



