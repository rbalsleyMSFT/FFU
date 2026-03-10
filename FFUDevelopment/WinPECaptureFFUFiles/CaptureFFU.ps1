$VMHostIPAddress = '192.168.1.158'
$ShareName = 'FFUCaptureShare'
$UserName = 'ffu_user'
$Password = '23202eb4-10c3-47e9-b389-f0c462663a23'
$CustomFFUNameTemplate = '{WindowsRelease}_{WindowsVersion}_{SKU}_{yyyy}-{MM}-{dd}_{HH}{mm}'

$netuseCommand = "net use W: \\$VMHostIPAddress\$ShareName /user:$UserName $Password 2>&1"

# Connect to network share
try {
    Write-Host "Connecting to network share via $netuseCommand"
    $netUseResult = net use W: "\\$VMHostIPAddress\$ShareName" "/user:$UserName" "$Password" 2>&1
    
    # Check if the result contains an error
    if ($LASTEXITCODE -ne 0) {
        # Extract the error code from the Exception Message
        # Example message format: "System error 53 has occurred."
        $message = $netUseResult.Exception.Message
        $regex = [regex]'System error (\d+)'
        $match = $regex.Match($message)
        if ($match.Success) {
            $errorCode = [int]$match.Groups[1].Value
            
            $errorMessage = switch ($errorCode) {
                53 { "Network path not found. Verify the IP address is correct and the server is accessible." }
                67 { "Network name cannot be found. Verify the share name exists on the server." }
                86 { "Password is incorrect for the specified username." }
                1219 { "Multiple connections to the share exist."}
                1326 { "Logon failure: unknown username or bad password." }
                1385 { "Logon failure: the user has not been granted the requested logon type at this computer. 
                This is likely due to changes to the User Rights Assignment: Access this computer from the network local security policy
                See: https://github.com/rbalsleyMSFT/FFU/issues/122 for more info" }
                1792 { "Unable to connect. Verify the server is running and accepting connections." }
                2250 { "Network connection attempt timed out." }
                default { "Network connection failed with error code: $errorCode. Details: $message" }
            }
            # Write-Error $errorMessage
            throw $errorMessage
        }
    }
} catch {
    Write-Error "Failed to connect to network share: Error code: $errorcode $_"
    Write-Host "Some things to try:"
    Write-Host '1. If not using an external switch, change to using an external switch'
    Write-Host '2. Make sure the VMHostIPAddress is correct for the VMSwitch that is being used'
    Write-Host '3. Try disabling the Windows Firewall on the host machine as a test only. If that helps, there is a Windows firewall rule that is blocking SMB 445 into the VM host'
    Write-Host '4. If this is a machine that is managed by your organization, try using another machine that is not managed. There could be security policies in place that are blocking the connection to the share.'
    Write-Host '5. You can also try disabling Hyper-V and re-enabling it. This has helped some users in the past.'
    Write-Host '6. If all else fails, open an issue on the github repo and attach screenshots of this message, your FFUDevelopment.log, your command line that you used to build the FFU, and/or the config file you used (if you used one).'
    pause
    throw
}

$AssignDriveLetter = 'x:\AssignDriveLetter.txt'
try {
    Write-Host 'Assigning M: as Windows drive letter'
    Start-Process -FilePath diskpart.exe -ArgumentList "/S $AssignDriveLetter" -Wait -ErrorAction Stop | Out-Null
}
catch {
    Write-Error "Failed to assign drive letter using diskpart: $_"
    
}

#Load Registry Hive
$Software = 'M:\Windows\System32\config\software'
try {
    Write-Host "Loading software registry hive to $Software"
    if (-not (Test-Path -Path $Software)) {
        throw "Software registry hive not found at $Software"
    }
    $regResult = reg load "HKLM\FFU" $Software 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Registry load failed with exit code $($LASTEXITCODE): $regResult"
    }
    Write-Host "Successfully loaded software registry hive."
}
catch {
    Write-Error "Failed to load registry hive: $_"
    
}

try {
    #Find Windows version values
    Write-Host "Retrieving Windows information from the registry..."
    $SKU = Get-ItemPropertyValue -Path 'HKLM:\FFU\Microsoft\Windows NT\CurrentVersion\' -Name 'EditionID'
    Write-Host "SKU: $SKU"
    [int]$CurrentBuild = Get-ItemPropertyValue -Path 'HKLM:\FFU\Microsoft\Windows NT\CurrentVersion\' -Name 'CurrentBuild'
    Write-Host "CurrentBuild: $CurrentBuild"
    if ($CurrentBuild -notin 14393, 17763) {
        Write-Host "CurrentBuild is not 14393 or 17763, retrieving WindowsVersion..."
        $WindowsVersion = Get-ItemPropertyValue -Path 'HKLM:\FFU\Microsoft\Windows NT\CurrentVersion\' -Name 'DisplayVersion'
        Write-Host "WindowsVersion: $WindowsVersion"
    }
    $InstallationType = Get-ItemPropertyValue -Path 'HKLM:\FFU\Microsoft\Windows NT\CurrentVersion\' -Name 'InstallationType'
    Write-Host "InstallationType: $InstallationType"
    $BuildDate = Get-Date -uformat %b%Y
    Write-Host "BuildDate: $BuildDate"

$SKU = switch ($SKU) {
    Core { 'Home' }
    CoreN { 'Home_N' }
    CoreSingleLanguage { 'Home_SL' }
    Professional { 'Pro' }
    ProfessionalN { 'Pro_N' }
    ProfessionalEducation { 'Pro_Edu' }
    ProfessionalEducationN { 'Pro_Edu_N' }
    Enterprise { 'Ent' }
    EnterpriseN { 'Ent_N' }
    EnterpriseS { 'Ent_LTSC' }
    EnterpriseSN { 'Ent_N_LTSC' }
    IoTEnterpriseS { 'IoT_Ent_LTSC' }
    Education { 'Edu' }
    EducationN { 'Edu_N' }
    ProfessionalWorkstation { 'Pro_Wks' }
    ProfessionalWorkstationN { 'Pro_Wks_N' }
    ServerStandard { 'Srv_Std' }
    ServerDatacenter { 'Srv_Dtc' }
}

    if ($InstallationType -eq "Client") {
        if ($CurrentBuild -ge 22000) {
            $WindowsRelease = 'Win11'
            Write-Host "WindowsRelease: $WindowsRelease"
        }
        else {
            $WindowsRelease = 'Win10'
            Write-Host "WindowsRelease: $WindowsRelease"
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
        Write-Host "WindowsRelease: $WindowsRelease"
        if ($InstallationType -eq "Server Core") {
            $SKU += "_Core"
            Write-Host "InstallType is Server Core, changing SKU to: $SKU"
        }
    }

    if ($CustomFFUNameTemplate) {
        Write-Host 'Using custom FFU name template...'
        $FFUFileName = $CustomFFUNameTemplate
        $FFUFileName = $FFUFileName -replace '{WindowsRelease}', $WindowsRelease
        $FFUFileName = $FFUFileName -replace '{WindowsVersion}', $WindowsVersion
        $FFUFileName = $FFUFileName -replace '{SKU}', $SKU
        $FFUFileName = $FFUFileName -replace '{BuildDate}', $BuildDate
        $FFUFileName = $FFUFileName -replace '{yyyy}', (Get-Date -UFormat '%Y')
        $FFUFileName = $FFUFileName -creplace '{MM}', (Get-Date -UFormat '%m')
        $FFUFileName = $FFUFileName -replace '{dd}', (Get-Date -UFormat '%d')
        $FFUFileName = $FFUFileName -creplace '{HH}', (Get-Date -UFormat '%H')
        $FFUFileName = $FFUFileName -creplace '{hh}', (Get-Date -UFormat '%I')
        $FFUFileName = $FFUFileName -creplace '{mm}', (Get-Date -UFormat '%M')
        $FFUFileName = $FFUFileName -replace '{tt}', (Get-Date -UFormat '%p')
        Write-Host "FFU File Name: $FFUFileName"
        #If the custom FFU name template does not end with .ffu, append it
        if ($FFUFileName -notlike '*.ffu') {
            $FFUFileName += '.ffu'
            Write-Host "Appended .ffu to FFU file name: $FFUFileName"
        }
        $dismArgs = "/capture-ffu /imagefile=W:\$FFUFileName /capturedrive=\\.\PhysicalDrive0 /name:$WindowsRelease$WindowsVersion$SKU /Compress:Default"
        Write-Host "DISM arguments for capture: $dismArgs"
    }
    else {
        #If Office is installed, modify the file name of the FFU
        $Office = Get-ChildItem -Path 'M:\Program Files\Microsoft Office' -ErrorAction SilentlyContinue
        if ($Office) {
            $ffuFilePath = "W:\$WindowsRelease`_$WindowsVersion`_$SKU`_Office`_$BuildDate.ffu"
            Write-Host "Office is installed, using modified FFU file name: $ffuFilePath"
        }
        else {
            $ffuFilePath = "W:\$WindowsRelease`_$WindowsVersion`_$SKU`_Apps`_$BuildDate.ffu"
            Write-Host "Office is not installed, using modified FFU file name: $ffuFilePath"
        }
        $dismArgs = "/capture-ffu /imagefile=$ffuFilePath /capturedrive=\\.\PhysicalDrive0 /name:$WindowsRelease$WindowsVersion$SKU /Compress:Default"
        Write-Host "DISM arguments for capture: $dismArgs"
    }

    #Unload Registry
    Set-Location X:\
    Remove-Variable SKU
    Remove-Variable CurrentBuild
    if ($CurrentBuild -notin 14393, 17763) {
        Remove-Variable WindowsVersion
    }
    if ($Office) {
        Remove-Variable Office
    }

    try {
        Write-Host "Unloading registry hive HKLM\FFU..."
        $regUnloadResult = reg unload "HKLM\FFU" 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Registry unload failed with exit code $($LASTEXITCODE): $regUnloadResult"
        }
        Write-Host "Successfully unloaded registry hive."
    }
    catch {
        Write-Error "Failed to unload registry hive: $_"
        
    }

    Write-Host "Sleeping for 60 seconds to allow registry to unload prior to capture"
    Start-sleep 60

    try {
        Write-Host "Starting DISM FFU capture..."
        $dismProcess = Start-Process -FilePath dism.exe -ArgumentList $dismArgs -Wait -PassThru -ErrorAction Stop
        if ($dismProcess.ExitCode -ne 0) {
            throw "DISM capture failed with exit code $($dismProcess.ExitCode)"
        }
        Write-Host "DISM FFU capture completed successfully."
    }
    catch {
        Write-Error "FFU capture failed: $_"
        
    }

    try {
        Write-Host "Copying DISM log to network share..."
        xcopy X:\Windows\logs\dism\dism.log W:\ /Y | Out-Null
    }
    catch {
        Write-Warning "Failed to copy DISM log: $_"
    }
    Write-Host "DISM log copied to network share, shutting down..."
    wpeutil Shutdown

}
catch {
    Write-Error "An unexpected error occurred: $_"
    
}
