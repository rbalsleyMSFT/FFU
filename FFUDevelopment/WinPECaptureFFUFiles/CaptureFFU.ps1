#Modify the net use W: \\192.168.1.158\FFUCaptureShare /user:ffu_user ddb1f077-3eed-433c-b4d9-7b8cd54ce727
net use W: \\192.168.1.158\FFUCaptureShare /user:ffu_user ddb1f077-3eed-433c-b4d9-7b8cd54ce727

$AssignDriveLetter = 'x:\AssignDriveLetter.txt'
Start-Process -FilePath diskpart.exe -ArgumentList "/S $AssignDriveLetter" -Wait -ErrorAction Stop | Out-Null
#Load Registry Hive
$Software = 'M:\Windows\System32\config\software'
reg load "HKLM\FFU" $Software

#Find Windows version values

$SKU = Get-ItemPropertyValue -Path 'HKLM:\FFU\Microsoft\Windows NT\CurrentVersion\' -Name 'EditionID'
[int]$CurrentBuild = Get-ItemPropertyValue -Path 'HKLM:\FFU\Microsoft\Windows NT\CurrentVersion\' -Name 'CurrentBuild'
$DisplayVersion = Get-ItemPropertyValue -Path 'HKLM:\FFU\Microsoft\Windows NT\CurrentVersion\' -Name 'DisplayVersion'
$InstallationType = Get-ItemPropertyValue -Path 'HKLM:\FFU\Microsoft\Windows NT\CurrentVersion\' -Name 'InstallationType'
$BuildDate = Get-Date -uformat %b%Y

$SKU = switch ($SKU) {
    Core { 'Home' }
    CoreN { 'HomeN'}
    CoreSingleLanguage { 'HomeSL'}
    Professional { 'Pro' }
    ProfessionalN { 'ProN'}
    ProfessionalEducation { 'Pro_Edu' }
    ProfessionalEducationN { 'Pro_EduN' }
    Enterprise { 'Ent' }
    EnterpriseN { 'EntN'}
    Education { 'Edu' }
    EducationN { 'EduN'}
    ProfessionalWorkstation { 'Pro_Wks' }
    ProfessionalWorkstationN { 'Pro_WksN' }
    ServerStandard { 'Srv_Std' }
    ServerDatacenter { 'Srv_Dtc' }
}

if ($InstallationType -eq "Client") {
    if ($CurrentBuild -ge 22000) {
        $Name = 'Win11'
    }
    else {
        $Name = 'Win10'
    }
} else {
    $Name = switch ($CurrentBuild) {
        26100 { '2025' }
        20348 { '2022' }
        17763 { '2019' }
        Default { $DisplayVersion }
    }
    if ($InstallationType -eq "Server Core") {
        $SKU += "_Core"
    }
}

#If Office is installed, modify the file name of the FFU
#$Office = Get-childitem -Path 'M:\Program Files\Microsoft Office' -ErrorAction SilentlyContinue | Out-Null
$Office = Get-childitem -Path 'M:\Program Files\Microsoft Office' -ErrorAction SilentlyContinue
if($Office){
    $ffuFilePath = "W:\$Name`_$DisplayVersion`_$SKU`_Office`_$BuildDate.ffu"
    $dismArgs = "/capture-ffu /imagefile=$ffuFilePath /capturedrive=\\.\PhysicalDrive0 /name:$Name$DisplayVersion$SKU /Compress:Default"
    
    
}
else{
    $ffuFilePath = "W:\$Name`_$DisplayVersion`_$SKU`_Apps`_$BuildDate.ffu"
    $dismArgs = "/capture-ffu /imagefile=$ffuFilePath /capturedrive=\\.\PhysicalDrive0 /name:$Name$DisplayVersion$SKU /Compress:Default"
    
}

#Unload Registry
Set-Location X:\
Remove-Variable SKU
Remove-Variable CurrentBuild
Remove-Variable DisplayVersion
Remove-Variable Office
reg unload "HKLM\FFU"
#This prevents Critical Process Died errors you can have during deployment of the FFU - may not happen during capture from WinPE, but adding here to be consistent with VHDX capture
Write-Host "Sleeping for 60 seconds to allow registry to unload prior to capture"
Start-sleep 60
Start-Process -FilePath dism.exe -ArgumentList $dismArgs -Wait -PassThru -ErrorAction Stop | Out-Null
#Copy DISM log to Host
xcopy X:\Windows\logs\dism\dism.log W:\ /Y | Out-Null

wpeutil Shutdown
