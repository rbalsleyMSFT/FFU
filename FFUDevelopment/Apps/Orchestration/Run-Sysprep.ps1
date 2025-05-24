#The below lines will remove the unattend.xml that gets the machine into audit mode. If not removed, the OS will get stuck booting to audit mode each time.
#Also kills the sysprep process in order to automate sysprep generalize
# Convert these commands to native powershell
# del c:\windows\panther\unattend\unattend.xml /F /Q
# del c:\windows\panther\unattend.xml /F /Q
# taskkill /IM sysprep.exe
# timeout /t 10
# & c:\windows\system32\sysprep\sysprep.exe /quiet /generalize /oobe

Remove-Item -Path "C:\windows\panther\unattend\unattend.xml" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\windows\panther\unattend.xml" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "sysprep" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 10
& "C:\windows\system32\sysprep\sysprep.exe" /quiet /generalize /oobe
