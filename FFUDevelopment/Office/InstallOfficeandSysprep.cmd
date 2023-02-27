d:\setup.exe /configure d:\DeployFFU.xml
taskkill /IM sysprep.exe
timeout /t 5
c:\windows\system32\sysprep\sysprep.exe /quiet /generalize /oobe