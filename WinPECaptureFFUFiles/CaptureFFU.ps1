#Modify the net use path to map the W: drive to the location you want to copy the FFU file to
net use W: \\192.168.1.2\c$\temp /user:administrator p@ssw0rd

$AssignDriveLetter = 'x:\AssignDriveLetter.txt'
Start-Process -FilePath diskpart.exe -ArgumentList "/S $AssignDriveLetter" -Wait -ErrorAction Stop | Out-Null
#Load Registry Hive
$Software = 'M:\Windows\System32\config\software'
reg load "HKLM\FFU" $Software

#Find Windows version values

$SKU = Get-ItemPropertyValue -Path 'HKLM:\FFU\Microsoft\Windows NT\CurrentVersion\' -Name 'EditionID'
[int]$CurrentBuild = Get-ItemPropertyValue -Path 'HKLM:\FFU\Microsoft\Windows NT\CurrentVersion\' -Name 'CurrentBuild'
$DisplayVersion = Get-ItemPropertyValue -Path 'HKLM:\FFU\Microsoft\Windows NT\CurrentVersion\' -Name 'DisplayVersion'
$BuildDate = Get-Date -uformat %b%Y

$SKU = switch ($SKU){
    Home {'Home'}
    Professional {'Pro'}
    ProfessionalEducation {'Pro_Edu'}
    Enterprise {'Ent'}
}

if($CurrentBuild -ge 22000){
    $Name = 'Win11'
}
else{
    $Name = 'Win10'
}

#If Office is installed, modify the file name of the FFU
$Office = Get-childitem -Path 'M:\Program Files\Microsoft Office' -ErrorAction SilentlyContinue | Out-Null
if($Office){
    $ffuFilePath = "W:\$Name`_$DisplayVersion`_$SKU`_Office`_$BuildDate.ffu"
    $dismArgs = "/capture-ffu /imagefile=$ffuFilePath /capturedrive=\\.\PhysicalDrive0 /name:$Name$DisplayVersion$SKU /Compress:Default"
    
    
}
else{
    $ffuFilePath = "W:\$Name`_$DisplayVersion`_$SKU`_$BuildDate.ffu"
    $dismArgs = "/capture-ffu /imagefile=$ffuFilePath /capturedrive=\\.\PhysicalDrive0 /name:$Name$DisplayVersion$SKU /Compress:Default"
    
}

#Unload Registry
Set-Location X:\
Remove-Variable SKU
Remove-Variable CurrentBuild
Remove-Variable DisplayVersion
Remove-Variable Office
reg unload "HKLM\FFU"

Start-Process -FilePath dism.exe -ArgumentList $dismArgs -Wait -PassThru -ErrorAction Stop | Out-Null
$dismOptArgs = "/optimize-ffu /imagefile:$ffuFilePath"
Start-Process -FilePath dism.exe -ArgumentList $dismOptArgs -Wait -PassThru -ErrorAction Stop | Out-Null
#Copy DISM log to Host
xcopy X:\Windows\logs\dism\dism.log W:\ /Y | Out-Null
shutdown /p
