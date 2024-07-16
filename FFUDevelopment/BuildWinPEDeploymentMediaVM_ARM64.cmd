rd c:\FFUDevelopment\WinPE /S /Q
cmd /c copype arm64 c:\FFUDevelopment\WinPE 
Dism /Mount-Image /ImageFile:"c:\FFUDevelopment\WinPE\media\sources\boot.wim" /Index:1 /MountDir:"c:\FFUDevelopment\WinPE\mount"
Dism /Add-Package /Image:"c:\FFUDevelopment\WinPE\mount" /PackagePath:"C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\arm64\WinPE_OCs\WinPE-WMI.cab"
Dism /Add-Package /Image:"c:\FFUDevelopment\WinPE\mount" /PackagePath:"C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\arm64\WinPE_OCs\en-us\WinPE-WMI_en-us.cab"
Dism /Add-Package /Image:"c:\FFUDevelopment\WinPE\mount" /PackagePath:"C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\arm64\WinPE_OCs\WinPE-NetFX.cab"
Dism /Add-Package /Image:"c:\FFUDevelopment\WinPE\mount" /PackagePath:"C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\arm64\WinPE_OCs\en-us\WinPE-NetFX_en-us.cab"
Dism /Add-Package /Image:"c:\FFUDevelopment\WinPE\mount" /PackagePath:"C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\arm64\WinPE_OCs\WinPE-Scripting.cab"
Dism /Add-Package /Image:"c:\FFUDevelopment\WinPE\mount" /PackagePath:"C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\arm64\WinPE_OCs\en-us\WinPE-Scripting_en-us.cab"
Dism /Add-Package /Image:"c:\FFUDevelopment\WinPE\mount" /PackagePath:"C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\arm64\WinPE_OCs\WinPE-PowerShell.cab"
Dism /Add-Package /Image:"c:\FFUDevelopment\WinPE\mount" /PackagePath:"C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\arm64\WinPE_OCs\en-us\WinPE-PowerShell_en-us.cab"
Dism /Add-Package /Image:"c:\FFUDevelopment\WinPE\mount" /PackagePath:"C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\arm64\WinPE_OCs\WinPE-StorageWMI.cab"
Dism /Add-Package /Image:"c:\FFUDevelopment\WinPE\mount" /PackagePath:"C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\arm64\WinPE_OCs\en-us\WinPE-StorageWMI_en-us.cab"
Dism /Add-Package /Image:"c:\FFUDevelopment\WinPE\mount" /PackagePath:"C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\arm64\WinPE_OCs\WinPE-DismCmdlets.cab"
Dism /Add-Package /Image:"c:\FFUDevelopment\WinPE\mount" /PackagePath:"C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\arm64\WinPE_OCs\en-us\WinPE-DismCmdlets_en-us.cab"
xcopy "C:\FFUDevelopment\WinPEDeployFFUFilesVM" c:\FFUDevelopment\WinPE\mount /Y /E
REM If you need to add drivers, remove the REM from the below line and change the /Driver:Path to a folder of drivers
REM dism /image:C:\FFUDevelopment\WinPE\mount /Add-Driver /Driver:<Path to Drivers folder e.g c:\drivers> /Recurse
Dism /Unmount-Image /MountDir:c:\FFUDevelopment\WinPE\mount /Commit
MakeWinPEMedia /ISO /F c:\FFUDevelopment\WinPE "c:\FFUDevelopment\WinPE_FFU_Deploy_VM_ARM64.iso"
rd c:\FFUDevelopment\WinPE /S /Q