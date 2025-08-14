#The below lines will remove the unattend.xml that gets the machine into audit mode. If not removed, the OS will get stuck booting to audit mode each time.
#Also kills the sysprep process in order to automate sysprep generalize

Write-Host "Removing existing unattend.xml files and stopping sysprep process if running..."
Remove-Item -Path "C:\windows\panther\unattend\unattend.xml" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\windows\panther\unattend.xml" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "sysprep" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 10
# If an Unattend.xml has been provided on the mounted Apps ISO (D:\Unattend\Unattend.xml),
# pass it to sysprep; otherwise, run without /unattend.
$unattendOnAppsIso = "D:\Unattend\Unattend.xml"
if (Test-Path -Path $unattendOnAppsIso) {
    Write-Host "Using $unattendOnAppsIso from Apps ISO..."
    & "C:\windows\system32\sysprep\sysprep.exe" /quiet /generalize /oobe /unattend:$unattendOnAppsIso
}
else {
    & "C:\windows\system32\sysprep\sysprep.exe" /quiet /generalize /oobe
}
