REM Put each app install on a separate line
REM M365 Apps/Office ProPlus
REM d:\Office\setup.exe /configure d:\office\DeployFFU.xml
REM Install Defender Platform Update
REM Install Defender Definitions
REM Install Windows Security Platform Update
REM Install OneDrive Per Machine
REM Install Edge Stable
REM Add additional apps below here
REM Contoso App (Example)
REM msiexec /i d:\Contoso\setup.msi /qn /norestart
REM The below lines will remove the unattend.xml that gets the machine into audit mode. If not removed, the OS will get stuck booting to audit mode each time.
REM Also kills the sysprep process in order to automate sysprep generalize
del c:\windows\panther\unattend\unattend.xml /F /Q
del c:\windows\panther\unattend.xml /F /Q
taskkill /IM sysprep.exe
timeout /t 10
REM Run Component Cleanup since dism /online /cleanup-image /analyzecomponentcleanup recommends it
REM If adding latest CU, definitely need to do this to keep FFU size smaller
dism /online /cleanup-image /startcomponentcleanup /resetbase
REM Sysprep/Generalize
c:\windows\system32\sysprep\sysprep.exe /quiet /generalize /oobe
