#Modify the net use W: \\192.168.1.158\FFUCaptureShare /user:ffu_user ddb1f077-3eed-433c-b4d9-7b8cd54ce727
net use W: \\192.168.1.158\FFUCaptureShare /user:ffu_user ddb1f077-3eed-433c-b4d9-7b8cd54ce727
#Custom naming placeholder

$AssignDriveLetter = 'x:\AssignDriveLetter.txt'
Start-Process -FilePath diskpart.exe -ArgumentList "/S $AssignDriveLetter" -Wait -ErrorAction Stop | Out-Null
#Load Registry Hive
$Software = 'M:\Windows\System32\config\software'
reg load "HKLM\FFU" $Software

#Find Windows version values

$SKU = Get-ItemPropertyValue -Path 'HKLM:\FFU\Microsoft\Windows NT\CurrentVersion\' -Name 'EditionID'
[int]$CurrentBuild = Get-ItemPropertyValue -Path 'HKLM:\FFU\Microsoft\Windows NT\CurrentVersion\' -Name 'CurrentBuild'
if ($CurrentBuild -notin 14393, 17763) {
    $WindowsVersion = Get-ItemPropertyValue -Path 'HKLM:\FFU\Microsoft\Windows NT\CurrentVersion\' -Name 'DisplayVersion'
}
$InstallationType = Get-ItemPropertyValue -Path 'HKLM:\FFU\Microsoft\Windows NT\CurrentVersion\' -Name 'InstallationType'
$BuildDate = Get-Date -uformat %b%Y

$SKU = switch ($SKU) {
    Core { 'Home' }
    CoreN { 'HomeN' }
    CoreSingleLanguage { 'HomeSL' }
    Professional { 'Pro' }
    ProfessionalN { 'ProN' }
    ProfessionalEducation { 'Pro_Edu' }
    ProfessionalEducationN { 'Pro_EduN' }
    Enterprise { 'Ent' }
    EnterpriseN { 'EntN' }
    Education { 'Edu' }
    EducationN { 'EduN' }
    ProfessionalWorkstation { 'Pro_Wks' }
    ProfessionalWorkstationN { 'Pro_WksN' }
    ServerStandard { 'Srv_Std' }
    ServerDatacenter { 'Srv_Dtc' }
}

if ($InstallationType -eq "Client") {
    if ($CurrentBuild -ge 22000) {
        $WindowsRelease = 'Win11'
    }
    else {
        $WindowsRelease = 'Win10'
    }
}
else {
    $WindowsRelease = switch ($CurrentBuild) {
        26100 { '2025' }
        20348 { '2022' }
        17763 { '2019' }
        14393 { '2016' }
        Default { $WindowsVersion }
    }
    if ($InstallationType -eq "Server Core") {
        $SKU += "_Core"
    }
}

if ($CustomFFUNameTemplate) {
    $CustomFFUNameTemplate = $CustomFFUNameTemplate -replace '{WindowsRelease}', $WindowsRelease
    $CustomFFUNameTemplate = $CustomFFUNameTemplate -replace '{WindowsVersion}', $WindowsVersion
    $CustomFFUNameTemplate = $CustomFFUNameTemplate -replace '{SKU}', $SKU
    $CustomFFUNameTemplate = $CustomFFUNameTemplate -replace '{BuildDate}', $BuildDate
    $CustomFFUNameTemplate = $CustomFFUNameTemplate -replace '{yyyy}', (Get-Date -UFormat '%Y')
    $CustomFFUNameTemplate = $CustomFFUNameTemplate -creplace '{MM}', (Get-Date -UFormat '%m')
    $CustomFFUNameTemplate = $CustomFFUNameTemplate -replace '{dd}', (Get-Date -UFormat '%d')
    $CustomFFUNameTemplate = $CustomFFUNameTemplate -creplace '{HH}', (Get-Date -UFormat '%H')
    $CustomFFUNameTemplate = $CustomFFUNameTemplate -creplace '{hh}', (Get-Date -UFormat '%I')
    $CustomFFUNameTemplate = $CustomFFUNameTemplate -creplace '{mm}', (Get-Date -UFormat '%M')
    $CustomFFUNameTemplate = $CustomFFUNameTemplate -replace '{tt}', (Get-Date -UFormat '%p')
    if($CustomFFUNameTemplate -notlike '*.ffu') {
        $CustomFFUNameTemplate += '.ffu'
    }
    $dismArgs = "/capture-ffu /imagefile=W:\$CustomFFUNameTemplate /capturedrive=\\.\PhysicalDrive0 /name:$WindowsRelease$WindowsVersion$SKU /Compress:Default"
} else {
    #If Office is installed, modify the file name of the FFU
    #$Office = Get-childitem -Path 'M:\Program Files\Microsoft Office' -ErrorAction SilentlyContinue | Out-Null
    $Office = Get-ChildItem -Path 'M:\Program Files\Microsoft Office' -ErrorAction SilentlyContinue
    if ($Office) {
        $ffuFilePath = "W:\$WindowsRelease`_$WindowsVersion`_$SKU`_Office`_$BuildDate.ffu"
    } else {
        $ffuFilePath = "W:\$WindowsRelease`_$WindowsVersion`_$SKU`_Apps`_$BuildDate.ffu"
    }
    $dismArgs = "/capture-ffu /imagefile=$ffuFilePath /capturedrive=\\.\PhysicalDrive0 /name:$WindowsRelease$WindowsVersion$SKU /Compress:Default"
}

#Unload Registry
Set-Location X:\
Remove-Variable SKU
if ($CurrentBuild -notin 14393, 17763) {
    Remove-Variable WindowsVersion
}
Remove-Variable CurrentBuild
Remove-Variable Office
reg unload "HKLM\FFU"
#This prevents Critical Process Died errors you can have during deployment of the FFU - may not happen during capture from WinPE, but adding here to be consistent with VHDX capture
Write-Host "Sleeping for 60 seconds to allow registry to unload prior to capture"
Start-sleep 60
Start-Process -FilePath dism.exe -ArgumentList $dismArgs -Wait -PassThru -ErrorAction Stop | Out-Null
#Copy DISM log to Host
xcopy X:\Windows\logs\dism\dism.log W:\ /Y | Out-Null
wpeutil Shutdown
