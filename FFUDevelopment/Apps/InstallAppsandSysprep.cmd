setlocal enabledelayedexpansion
REM Put each app install on a separate line
REM M365 Apps/Office ProPlus
REM d:\Office\setup.exe /configure d:\office\DeployFFU.xml
REM Install Defender Platform Update
REM Install Defender Definitions
REM Install Windows Security Platform Update
REM Install OneDrive Per Machine
REM Install Edge Stable
REM Winget Win32 Apps
REM Add additional apps below here
REM Contoso App (Example)
REM msiexec /i d:\Contoso\setup.msi /qn /norestart
set "INSTALL_STOREAPPS=false"
if /i "%INSTALL_STOREAPPS%"=="false" (
    echo Skipping MS Store installation due to INSTALL_STOREAPPS flag.
    goto :remaining
)
set "basepath=D:\MSStore"
for /d %%D in ("%basepath%\*") do (
    set "appfolder=%%D"
    set "mainpackage="
    set "dependenciesfolder=!appfolder!\Dependencies"
    for %%F in ("!appfolder!\*") do (
        if not "%%~dpF"=="!dependenciesfolder!\" (
            if /i not "%%~xF"==".xml" (
                if /i not "%%~xF"==".yaml" (
                    set "mainpackage=%%F"
                )
            ) 
        )
    )
    if defined mainpackage (
        set "dism_command=DISM /Online /Add-ProvisionedAppxPackage /PackagePath:"!mainpackage!" /Region:all /StubPackageOption:installfull"
        if exist "!dependenciesfolder!" (
            for %%G in ("!dependenciesfolder!\*") do (
                set "dism_command=!dism_command! /DependencyPackagePath:"%%G""
            )
        )
        for %%F in ("!appfolder!\*.xml") do (
        set "licensefile=%%F"
        )
        if defined licensefile (
            set "dism_command=!dism_command! /LicensePath:"!licensefile!""
        ) else (
            set "dism_command=!dism_command! /SkipLicense"
        )
        echo !dism_command!
        !dism_command!
    )
)
:remaining
endlocal
for /r "D:\" %%G in (.) do (
    if exist "%%G\Notepad++" (
        powershell -Command "Remove-AppxPackage -Package NotepadPlusPlus_1.0.0.0_neutral__7njy0v32s6xk6"
    )
)
REM The below lines will remove the unattend.xml that gets the machine into audit mode. If not removed, the OS will get stuck booting to audit mode each time.
REM Also kills the sysprep process in order to automate sysprep generalize
del c:\windows\panther\unattend\unattend.xml /F /Q
del c:\windows\panther\unattend.xml /F /Q
taskkill /IM sysprep.exe
timeout /t 10
REM Run disk cleanup (cleanmgr.exe) with all options enabled: https://learn.microsoft.com/en-us/troubleshoot/windows-server/backup-and-storage/automating-disk-cleanup-tool
set rootkey=HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches
REM Per above doc, the Offline Pages Files subkey does not have stateflags value
for /f "tokens=*" %%K in ('reg query "%rootkey%"') do (
    echo %%K | findstr /i /c:"Offline Pages Files"
    if errorlevel 1 (
        reg add "%%K" /v StateFlags0000 /t REG_DWORD /d 2 /f
    )
)
cleanmgr.exe /sagerun:0
REM Remove the StateFlags0000 registry value
for /f "tokens=*" %%K in ('reg query "%rootkey%"') do (
    echo %%K | findstr /i /c:"Offline Pages Files"
    if errorlevel 1 (
        reg delete "%%K" /v StateFlags0000 /f
    )
)
REM Sysprep/Generalize
c:\windows\system32\sysprep\sysprep.exe /quiet /generalize /oobe
