REM Put each app install on a separate line
REM M365 Apps/Office ProPlus
d:\Office\setup.exe /configure d:\Office\DeployFFU.xml
REM Add additional apps below here
REM Contoso App (Example)
REM msiexec /i d:\Contoso\setup.msi /qn /norestart
REM The below lines will remove the unattend.xml that gets the machine into audit mode. If not removed, the OS will get stuck booting to audit mode each time.
REM Also kills the sysprep process in order to automate sysprep generalize
del c:\windows\panther\unattend\unattend.xml /F /Q
del c:\windows\panther\unattend.xml /F /Q
taskkill /IM sysprep.exe
timeout /t 5
c:\windows\system32\sysprep\sysprep.exe /quiet /generalize /oobe
