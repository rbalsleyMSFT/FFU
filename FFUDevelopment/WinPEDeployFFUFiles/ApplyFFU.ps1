function Get-USBDrive() {
    $USBDriveLetter = (Get-Volume | Where-Object { $_.DriveType -eq 'Removable' -and $_.FileSystemType -eq 'NTFS' }).DriveLetter
    if ($null -eq $USBDriveLetter) {
        #Must be using a fixed USB drive - difficult to grab drive letter from win32_diskdrive. Assume user followed instructions and used Deploy as the friendly name for partition
        $USBDriveLetter = (Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.FileSystemType -eq 'NTFS' -and $_.FileSystemLabel -eq 'Deploy' }).DriveLetter
        #If we didn't get the drive letter, stop the script.
        if ($null -eq $USBDriveLetter) {
            $errorMessage = 'Cannot find USB drive letter. If using a fixed USB drive, name the deployment partition "Deploy".'
            WriteLog ($errorMessage + ' Exiting.')
            Stop-Script -Message $errorMessage
        }

    }
    $USBDriveLetter = $USBDriveLetter + ":\"
    return $USBDriveLetter
}

function Get-HardDrive() {
    $systemInfo = Get-CimInstance -Class 'Win32_ComputerSystem'
    $manufacturer = $systemInfo.Manufacturer
    $model = $systemInfo.Model
    WriteLog 'Getting Hard Drive info'
    if ($manufacturer -eq 'Microsoft Corporation' -and $model -eq 'Virtual Machine') {
        WriteLog 'Running in a Hyper-V VM. Getting virtual disk on Index 0 and SCSILogicalUnit 0'
        $diskDrive = Get-CimInstance -Class 'Win32_DiskDrive' | Where-Object { $_.MediaType -eq 'Fixed hard disk media' `
                -and $_.Model -eq 'Microsoft Virtual Disk' `
                -and $_.Index -eq 0 `
                -and $_.SCSILogicalUnit -eq 0
        }
    }
    else {
        WriteLog 'Not running in a VM. Getting physical disk drive'
        $diskDrive = Get-CimInstance -Class 'Win32_DiskDrive' | Where-Object { $_.MediaType -eq 'Fixed hard disk media' -and $_.Model -ne 'Microsoft Virtual Disk' }
    }
    $deviceID = $diskDrive.DeviceID
    $bytesPerSector = $diskDrive.BytesPerSector
    $diskSize = $diskDrive.Size

    # Create a custom object to return values
    $result = [PSCustomObject]@{
        DeviceID       = $deviceID
        BytesPerSector = $bytesPerSector
        DiskSize       = $diskSize
    }

    return $result
}

function WriteLog($LogText) { 
    Add-Content -path $LogFile -value "$((Get-Date).ToString()) $LogText"
}

function Set-DiskpartAnswerFiles($DiskpartFile, $DiskID) {
    (Get-Content $DiskpartFile).Replace('disk 0', "disk $DiskID") | Set-Content -Path $DiskpartFile
}

function Set-Computername($computername) {
    [xml]$xml = Get-Content $UnattendFile
    $components = $xml.unattend.settings.component
    $found = $false
    foreach ($component in $components) {
        if ($component.ComputerName) {
            $component.ComputerName = $computername
            $found = $true
            break
        }
    }
    if (-not $found) {
        WriteLog 'ComputerName element not found in unattend.xml.'
        throw 'ComputerName element not found in unattend.xml.'
    }
    $xml.Save($UnattendFile)
    return $computername
}

function Invoke-Process {
    [CmdletBinding(SupportsShouldProcess)]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ArgumentList
    )

    $ErrorActionPreference = 'Stop'

    try {
        $stdOutTempFile = "$env:TEMP\$((New-Guid).Guid)"
        $stdErrTempFile = "$env:TEMP\$((New-Guid).Guid)"

        $startProcessParams = @{
            FilePath               = $FilePath
            ArgumentList           = $ArgumentList
            RedirectStandardError  = $stdErrTempFile
            RedirectStandardOutput = $stdOutTempFile
            Wait                   = $true;
            PassThru               = $true;
            NoNewWindow            = $true;
        }
        if ($PSCmdlet.ShouldProcess("Process [$($FilePath)]", "Run with args: [$($ArgumentList)]")) {
            $cmd = Start-Process @startProcessParams
            $cmdOutput = Get-Content -Path $stdOutTempFile -Raw
            $cmdError = Get-Content -Path $stdErrTempFile -Raw
            if ($cmd.ExitCode -ne 0) {
                if ($cmdError) {
                    throw $cmdError.Trim()
                }
                if ($cmdOutput) {
                    throw $cmdOutput.Trim()
                }
            }
            else {
                if ([string]::IsNullOrEmpty($cmdOutput) -eq $false) {
                    WriteLog $cmdOutput
                }
            }
        }
    }
    catch {
        #$PSCmdlet.ThrowTerminatingError($_)
        WriteLog $_
        Write-Host 'Script failed - check scriptlog.txt on the USB drive for more info'
        throw $_

    }
    finally {
        Remove-Item -Path $stdOutTempFile, $stdErrTempFile -Force -ErrorAction Ignore
        
    }
    
}

function Write-SectionHeader($Title) {
    $width = 51
    $leftPad = [math]::Floor(($width - $Title.Length) / 2)
    $rightPad = $width - $Title.Length - $leftPad
    $centeredTitle = (' ' * $leftPad) + $Title + (' ' * $rightPad)

    Write-Host "`n" # Add a newline for spacing
    Write-Host ('-' * $width) -ForegroundColor Yellow
    Write-Host $centeredTitle -ForegroundColor Yellow
    Write-Host ('-' * $width) -ForegroundColor Yellow
}

function Write-SystemInformation($hardDrive) {
    # Gather all information first
    $systemManufacturer = (Get-CimInstance -Class Win32_ComputerSystem).Manufacturer
    $systemModel = if ($systemManufacturer -like '*LENOVO*') {
        (Get-CimInstance -Class Win32_ComputerSystemProduct).Version
    }
    else {
        (Get-CimInstance -Class Win32_ComputerSystem).Model
    }
    $biosInfo = Get-CimInstance -Class Win32_Bios
    $processor = (Get-CimInstance -Class Win32_Processor).Name
    $totalMemory = (Get-CimInstance -Class Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum
    $totalMemoryGB = [math]::Round($totalMemory / 1GB, 2)
    $diskSizeGB = [math]::Round($hardDrive.DiskSize / 1GB, 2)

    # Create a custom object for structured data
    $sysInfoObject = [PSCustomObject]@{
        "Manufacturer"        = $systemManufacturer
        "Model"               = $systemModel
        "BIOS Version"        = $biosInfo.Version
        "Serial Number"       = $biosInfo.SerialNumber
        "Processor"           = $processor
        "Memory"              = "$($totalMemoryGB) GB"
        "Disk Size"           = "$($diskSizeGB) GB"
        "Logical Sector Size" = "$($hardDrive.BytesPerSector) Bytes"
    }

    # Log information line-by-line
    WriteLog "--- System Information ---"
    $sysInfoObject.psobject.Properties | ForEach-Object {
        WriteLog "$($_.Name): $($_.Value)"
    }
    WriteLog "--- End System Information ---"

    # Console output
    Write-SectionHeader -Title 'System Information'
    
    # Format for console using Format-List for better readability
    $consoleOutput = $sysInfoObject | Format-List | Out-String
    Write-Host $consoleOutput.Trim()
    Write-Host # Adds a blank line for spacing after the block 
}

function Stop-Script {
    param(
        [string]$Message
    )
    Write-Host "`n"
    if (-not [string]::IsNullOrWhiteSpace($Message)) {
        Write-Error -Message $Message
    }
    WriteLog "Copying dism log to $USBDrive"
    Invoke-Process xcopy "X:\Windows\logs\dism\dism.log $USBDrive /Y" 
    WriteLog "Copying dism log to $USBDrive succeeded"
    Read-Host "Press Enter to exit"
    Exit
}
#Get USB Drive and create log file
$LogFileName = 'ScriptLog.txt'
$USBDrive = Get-USBDrive
New-item -Path $USBDrive -Name $LogFileName -ItemType "file" -Force | Out-Null
$LogFile = $USBDrive + $LogFilename
$version = '2507.1'
WriteLog 'Begin Logging'
WriteLog "Script version: $version"

# Display banner and version
$banner = @"

███████╗███████╗██╗   ██╗    ██████╗ ██╗   ██╗██╗██╗     ██████╗ ███████╗██████╗ 
██╔════╝██╔════╝██║   ██║    ██╔══██╗██║   ██║██║██║     ██╔══██╗██╔════╝██╔══██╗
█████╗  █████╗  ██║   ██║    ██████╔╝██║   ██║██║██║     ██║  ██║█████╗  ██████╔╝
██╔══╝  ██╔══╝  ██║   ██║    ██╔══██╗██║   ██║██║██║     ██║  ██║██╔══╝  ██╔══██╗
██║     ██║     ╚██████╔╝    ██████╔╝╚██████╔╝██║███████╗██████╔╝███████╗██║  ██║
╚═╝     ╚═╝      ╚═════╝     ╚═════╝  ╚═════╝ ╚═╝╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝
                                                                                                                                                                
"@
Write-Host $banner -ForegroundColor Cyan
Write-Host "Version $version" -ForegroundColor Cyan

#Find PhysicalDrive
# $PhysicalDeviceID = Get-HardDrive
$hardDrive = Get-HardDrive
if ($null -eq $hardDrive) {
    $errorMessage = 'No hard drive found. You may need to add storage drivers to the WinPE image.'
    WriteLog ($errorMessage + ' Exiting.')
    WriteLog 'To add drivers, place them in the PEDrivers folder and re-run the creation script with -CopyPEDrivers $true, or add them manually via DISM.'
    Stop-Script -Message $errorMessage
}
$PhysicalDeviceID = $hardDrive.DeviceID
$BytesPerSector = $hardDrive.BytesPerSector
WriteLog "Physical DeviceID is $PhysicalDeviceID"

#Parse DiskID Number
$DiskID = $PhysicalDeviceID.substring($PhysicalDeviceID.length - 1, 1)
WriteLog "DiskID is $DiskID"

# Write System Information to console and log
Write-SystemInformation -hardDrive $hardDrive

#Find FFU Files
Write-SectionHeader 'FFU File Selection'
[array]$FFUFiles = @(Get-ChildItem -Path $USBDrive*.ffu)
$FFUCount = $FFUFiles.Count

#If multiple FFUs found, ask which to install
If ($FFUCount -gt 1) {
    WriteLog "Found $FFUCount FFU Files"
    Write-Host "Found $FFUCount FFU Files"
    $array = @()

    for ($i = 0; $i -le $FFUCount - 1; $i++) {
        $Properties = [ordered]@{Number = $i + 1 ; FFUFile = $FFUFiles[$i].FullName }
        $array += New-Object PSObject -Property $Properties
    }
    $array | Format-Table -AutoSize -Property Number, FFUFile
    do {
        try {
            $var = $true
            [int]$FFUSelected = Read-Host 'Enter the FFU number to install'
            $FFUSelected = $FFUSelected - 1
        }

        catch {
            Write-Host 'Input was not in correct format. Please enter a valid FFU number'
            $var = $false
        }
    } until (($FFUSelected -le $FFUCount - 1) -and $var) 

    $FFUFileToInstall = $array[$FFUSelected].FFUFile
    WriteLog "$FFUFileToInstall was selected"
}
elseif ($FFUCount -eq 1) {
    WriteLog "Found $FFUCount FFU File"
    Write-Host "Found $FFUCount FFU File"
    $FFUFileToInstall = $FFUFiles[0].FullName
    WriteLog "$FFUFileToInstall will be installed"
    Write-Host "$FFUFileToInstall will be installed"
} 
else {
    $errorMessage = 'No FFU files found.'
    Writelog $errorMessage
    Stop-Script -Message $errorMessage
}

#FindAP
$APFolder = $USBDrive + "Autopilot\"
If (Test-Path -Path $APFolder) {
    [array]$APFiles = @(Get-ChildItem -Path $APFolder*.json)
    $APFilesCount = $APFiles.Count
    if ($APFilesCount -ge 1) {
        $autopilot = $true
    }
}


#FindPPKG
$PPKGFolder = $USBDrive + "PPKG\"
if (Test-Path -Path $PPKGFolder) {
    [array]$PPKGFiles = @(Get-ChildItem -Path $PPKGFolder*.ppkg)
    $PPKGFilesCount = $PPKGFiles.Count
    if ($PPKGFilesCount -ge 1) {
        $PPKG = $true
    }
}

#FindUnattend
$UnattendFolder = $USBDrive + "unattend\"
$UnattendFilePath = $UnattendFolder + "unattend.xml"
$UnattendPrefixPath = $UnattendFolder + "prefixes.txt"
$UnattendComputerNamePath = $UnattendFolder + "SerialComputerNames.csv"
If (Test-Path -Path $UnattendFilePath) {
    $UnattendFile = Get-ChildItem -Path $UnattendFilePath
    If ($UnattendFile) {
        $Unattend = $true
    }
}
If (Test-Path -Path $UnattendPrefixPath) {
    $UnattendPrefixFile = Get-ChildItem -Path $UnattendPrefixPath
    If ($UnattendPrefixFile) {
        $UnattendPrefix = $true
    }
}
If (Test-Path -Path $UnattendComputerNamePath) {
    $UnattendComputerNameFile = Get-ChildItem -Path $UnattendComputerNamePath
    If ($UnattendComputerNameFile) {
        $UnattendComputerName = $true
    }
}

#Ask for device name if unattend exists
if ($Unattend -and $UnattendPrefix) {
    Write-SectionHeader 'Device Name Selection'
    Writelog 'Unattend file found with prefixes.txt. Getting prefixes.'
    $UnattendPrefixes = @(Get-content $UnattendPrefixFile)
    $UnattendPrefixCount = $UnattendPrefixes.Count
    If ($UnattendPrefixCount -gt 1) {
        WriteLog "Found $UnattendPrefixCount Prefixes"
        $array = @()
        for ($i = 0; $i -le $UnattendPrefixCount - 1; $i++) {
            $Properties = [ordered]@{Number = $i + 1 ; DeviceNamePrefix = $UnattendPrefixes[$i] }
            $array += New-Object PSObject -Property $Properties
        }
        $array | Format-Table -AutoSize -Property Number, DeviceNamePrefix
        do {
            try {
                $var = $true
                [int]$PrefixSelected = Read-Host 'Enter the prefix number to use for the device name'
                $PrefixSelected = $PrefixSelected - 1
            }
            catch {
                Write-Host 'Input was not in correct format. Please enter a valid prefix number'
                $var = $false
            }
        } until (($PrefixSelected -le $UnattendPrefixCount - 1) -and $var) 
        $PrefixToUse = $array[$PrefixSelected].DeviceNamePrefix
        WriteLog "$PrefixToUse was selected"
        Write-Host "`n$PrefixToUse was selected as device name prefix"
    }
    elseif ($UnattendPrefixCount -eq 1) {
        WriteLog "Found $UnattendPrefixCount Prefix"
        Write-Host "Found $UnattendPrefixCount Prefix"
        $PrefixToUse = $UnattendPrefixes[0]
        WriteLog "Will use $PrefixToUse as device name prefix"
        Write-Host "Will use $PrefixToUse as device name prefix"
    }
    #Get serial number to append. This can make names longer than 15 characters. Trim any leading or trailing whitespace
    $serial = (Get-CimInstance -ClassName win32_bios).SerialNumber.Trim()
    #Combine prefix with serial
    $computername = ($PrefixToUse + $serial) -replace "\s", "" # Remove spaces because windows does not support spaces in the computer names
    #If computername is longer than 15 characters, reduce to 15. Sysprep/unattend doesn't like ComputerName being longer than 15 characters even though Windows accepts it
    If ($computername.Length -gt 15) {
        $computername = $computername.substring(0, 15)
    }
    $computername = Set-Computername($computername)
    Writelog "Computer name set to $computername"
    Write-Host "Computer name set to $computername"
}
elseif ($Unattend -and $UnattendComputerName) {
    Write-SectionHeader 'Device Name Selection'
    Writelog 'Unattend file found with SerialComputerNames.csv. Getting name for current computer.'
    $SerialComputerNames = Import-Csv -Path $UnattendComputerNameFile.FullName -Delimiter ","

    $SerialNumber = (Get-CimInstance -Class Win32_Bios).SerialNumber
    $SCName = $SerialComputerNames | Where-Object { $_.SerialNumber -eq $SerialNumber }

    If ($SCName) {
        [string]$computername = $SCName.ComputerName
        $computername = Set-Computername($computername)
        Writelog "Computer name set to $computername"
        Write-Host "Computer name set to $computername"
    }
    else {
        Writelog 'No matching serial number found in SerialComputerNames.csv. Setting random computer name to complete setup.'
        Write-Host 'No matching serial number found in SerialComputerNames.csv. Setting random computer name to complete setup.'
        [string]$computername = ("FFU-" + ( -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 11 | ForEach-Object { [char]$_ })))
        $computername = Set-Computername($computername)
        Writelog "Computer name set to $computername"
        Write-Host "Computer name set to $computername"
    }
}
elseif ($Unattend) {
    Writelog 'Unattend file found with no prefixes.txt, asking for name'
    Write-Host 'Unattend file found but no prefixes.txt. Please enter a device name.'
    [string]$computername = Read-Host 'Enter device name'
    Set-Computername($computername)
    Writelog "Computer name set to $computername"
    Write-Host "Computer name set to $computername"
}
else {
    WriteLog 'No unattend folder found. Device name will be set via PPKG, AP JSON, or default OS name.'
}

#If both AP and PPKG folder found with files, ask which to use.
If ($autopilot -eq $true -and $PPKG -eq $true) {
    WriteLog 'Both PPKG and Autopilot json files found'
    Write-Host 'Both Autopilot JSON files and Provisioning packages were found.'
    do {
        try {
            $var = $true
            [int]$APorPPKG = Read-Host 'Enter 1 for Autopilot or 2 for Provisioning Package'
        }

        catch {
            Write-Host 'Incorrect value. Please enter 1 for Autopilot or 2 for Provisioning Package'
            $var = $false
        }
    } until (($APorPPKG -gt 0 -and $APorPPKG -lt 3) -and $var)
    If ($APorPPKG -eq 1) {
        $PPKG = $false
    }
    else {
        $autopilot = $false
    } 
}

#If multiple AP json files found, ask which to install
If ($APFilesCount -gt 1 -and $autopilot -eq $true) {
    WriteLog "Found $APFilesCount Autopilot json Files"
    $array = @()

    for ($i = 0; $i -le $APFilesCount - 1; $i++) {
        $Properties = [ordered]@{Number = $i + 1 ; APFile = $APFiles[$i].FullName; APFileName = $APFiles[$i].Name }
        $array += New-Object PSObject -Property $Properties
    }
    $array | Format-Table -AutoSize -Property Number, APFileName
    do {
        try {
            $var = $true
            [int]$APFileSelected = Read-Host 'Enter the AP json file number to install'
            $APFileSelected = $APFileSelected - 1
        }

        catch {
            Write-Host 'Input was not in correct format. Please enter a valid AP json file number'
            $var = $false
        }
    } until (($APFileSelected -le $APFilesCount - 1) -and $var) 

    $APFileToInstall = $array[$APFileSelected].APFile
    $APFileName = $array[$APFileSelected].APFileName
    WriteLog "$APFileToInstall was selected"
}
elseif ($APFilesCount -eq 1 -and $autopilot -eq $true) {
    WriteLog "Found $APFilesCount AP File"
    $APFileToInstall = $APFiles[0].FullName
    $APFileName = $APFiles[0].Name
    WriteLog "$APFileToInstall will be copied"
} 
else {
    Writelog 'No AP files found or AP was not selected'
}

#If multiple PPKG files found, ask which to install
If ($PPKGFilesCount -gt 1 -and $PPKG -eq $true) {
    Write-SectionHeader -Title 'Provisioning Package Selection'
    WriteLog "Found $PPKGFilesCount PPKG Files"
    $array = @()

    for ($i = 0; $i -le $PPKGFilesCount - 1; $i++) {
        $Properties = [ordered]@{Number = $i + 1 ; PPKGFile = $PPKGFiles[$i].FullName; PPKGFileName = $PPKGFiles[$i].Name }
        $array += New-Object PSObject -Property $Properties
    }
    $array | Format-Table -AutoSize -Property Number, PPKGFileName
    do {
        try {
            $var = $true
            [int]$PPKGFileSelected = Read-Host 'Enter the PPKG file number to install'
            $PPKGFileSelected = $PPKGFileSelected - 1
        }

        catch {
            Write-Host 'Input was not in correct format. Please enter a valid PPKG file number'
            $var = $false
        }
    } until (($PPKGFileSelected -le $PPKGFilesCount - 1) -and $var) 

    $PPKGFileToInstall = $array[$PPKGFileSelected].PPKGFile
    WriteLog "$PPKGFileToInstall was selected"
    Write-Host "`n$PPKGFileToInstall will be used"
}
elseif ($PPKGFilesCount -eq 1 -and $PPKG -eq $true) {
    Write-SectionHeader -Title 'Provisioning Package Selection'
    WriteLog "Found $PPKGFilesCount PPKG File"
    Write-Host "Found $PPKGFilesCount PPKG File"
    $PPKGFileToInstall = $PPKGFiles[0].FullName
    WriteLog "$PPKGFileToInstall will be used"
    Write-Host "`n$PPKGFileToInstall will be used"
} 
else {
    Writelog 'No PPKG files found or PPKG not selected.'
}

#Find Drivers
$DriversPath = $USBDrive + "Drivers"
$DriverSourcePath = $null
$DriverSourceType = $null # Will be 'WIM' or 'Folder'
$driverMappingPath = Join-Path -Path $DriversPath -ChildPath "DriverMapping.json"

If (Test-Path -Path $DriversPath) {
    Write-SectionHeader -Title 'Drivers Selection'
}

# --- Automatic Driver Detection using DriverMapping.json ---
if (Test-Path -Path $driverMappingPath -PathType Leaf) {
    WriteLog "DriverMapping.json found at $driverMappingPath. Attempting automatic driver selection."
    Write-Host "DriverMapping.json found. Attempting automatic driver selection."
    try {
        # Get system information
        $systemManufacturer = (Get-CimInstance -Class Win32_ComputerSystem).Manufacturer
        # Lenovo uses a different property for the model name
        $systemModel = if ($systemManufacturer -like '*LENOVO*') {
            (Get-CimInstance -Class Win32_ComputerSystemProduct).Version
        }
        else {
            (Get-CimInstance -Class Win32_ComputerSystem).Model
        }
        WriteLog "Detected System: Manufacturer='$systemManufacturer', Model='$systemModel'"

        # Load and parse the mapping file, ensuring it's always an array
        $driverMappings = @(Get-Content -Path $driverMappingPath -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue)

        # Find all matching rules and select the most specific one
        $matchingRules = @()
        foreach ($rule in $driverMappings) {
            # Use -like for wildcard matching.
            # This checks if the system model starts with the rule model, or vice-versa, for flexibility.
            if ($systemManufacturer -like "$($rule.Manufacturer)*" -and ($systemModel -like "$($rule.Model)*" -or $rule.Model -like "$systemModel*")) {
                $matchingRules += $rule
            }
        }

        # Select the best match
        $matchedRule = $null
        if ($matchingRules.Count -gt 0) {
            WriteLog "Found $($matchingRules.Count) potential driver mapping rule(s)."
            Write-Host "Found $($matchingRules.Count) potential driver mapping rule(s)."
            foreach ($rule in $matchingRules) {
                WriteLog "  - Potential Match: Manufacturer='$($rule.Manufacturer)', Model='$($rule.Model)', Path='$($rule.DriverPath)'"
                Write-Host "  - Potential Match: Manufacturer='$($rule.Manufacturer)', Model='$($rule.Model)', Path='$($rule.DriverPath)'"
            
            }
            # Sort by model name length, descending, to find the most specific match
            $matchedRule = $matchingRules | Sort-Object -Property @{Expression = { $_.Model.Length } } -Descending | Select-Object -First 1
        }

        if ($null -ne $matchedRule) {
            WriteLog "Automatic match found: Manufacturer='$($matchedRule.Manufacturer)', Model='$($matchedRule.Model)'"
            Write-Host "Automatic match found: Manufacturer='$($matchedRule.Manufacturer)', Model='$($matchedRule.Model)'"
            $potentialDriverPath = Join-Path -Path $DriversPath -ChildPath $matchedRule.DriverPath
            
            if (Test-Path -Path $potentialDriverPath) {
                $DriverSourcePath = $potentialDriverPath
                # Determine if it's a WIM or a Folder
                if ($DriverSourcePath -like '*.wim') {
                    $DriverSourceType = 'WIM'
                }
                else {
                    $DriverSourceType = 'Folder'
                }
                WriteLog "Automatically selected driver source. Type: $DriverSourceType, Path: $DriverSourcePath"
                Write-Host "Automatically selected driver source. Type: $DriverSourceType, Path: $DriverSourcePath"
            }
            else {
                WriteLog "Matched driver path '$potentialDriverPath' not found. Falling back to manual selection."
                Write-Host "Matched driver path '$potentialDriverPath' not found. Falling back to manual selection."
            }
        }
        else {
            WriteLog "No matching driver rule found in DriverMapping.json for this system. Falling back to manual selection."
            Write-Host "No matching driver rule found in DriverMapping.json for this system. Falling back to manual selection."
        }
    }
    catch {
        WriteLog "An error occurred during automatic driver detection: $($_.Exception.Message). Falling back to manual selection."
        Write-Host "An error occurred during automatic driver detection: $($_.Exception.Message). Falling back to manual selection."
    }
}
else {
    WriteLog "DriverMapping.json not found. Proceeding with manual driver selection."
}

# --- Manual Driver Selection (Fallback) ---
if ($null -eq $DriverSourcePath) {
    If (Test-Path -Path $DriversPath) {
        WriteLog "Searching for driver WIMs and folders in $DriversPath"
    
        # Get all WIM files
        $WimFiles = Get-ChildItem -Path $DriversPath -Filter *.wim -Recurse
        
        # Get all top-level driver folders
        $DriverFolders = Get-ChildItem -Path $DriversPath -Directory

        # Create a combined list
        $DriverSources = @()
        $WimFiles | ForEach-Object {
            $DriverSources += [PSCustomObject]@{
                Type = 'WIM'
                Path = $_.FullName
            }
        }
        $DriverFolders | ForEach-Object {
            $DriverSources += [PSCustomObject]@{
                Type = 'Folder'
                Path = $_.FullName
            }
        }

        $DriverSourcesCount = $DriverSources.Count

        if ($DriverSourcesCount -gt 0) {
            WriteLog "Found $DriverSourcesCount total driver sources (WIMs and folders)."
            if ($DriverSourcesCount -eq 1) {
                $DriverSourcePath = $DriverSources[0].Path
                $DriverSourceType = $DriverSources[0].Type
                WriteLog "Single driver source found. Type: $DriverSourceType, Path: $DriverSourcePath"
                Write-Host "Single driver source found. Type: $DriverSourceType, Path: $DriverSourcePath"
            }
            else {
                # Multiple sources found, prompt user
                WriteLog "Multiple driver sources found. Prompting for selection."
                $displayArray = @()
                for ($i = 0; $i -lt $DriverSourcesCount; $i++) {
                    $displayArray += [PSCustomObject]@{
                        Number = $i + 1
                        Type   = $DriverSources[$i].Type
                        Path   = $DriverSources[$i].Path
                    }
                }
                $displayArray | Format-Table -AutoSize
                
                do {
                    try {
                        $var = $true
                        [int]$DriverSelected = Read-Host 'Enter the number of the driver source to install'
                        $DriverSelected = $DriverSelected - 1
                    }
                    catch {
                        Write-Host 'Input was not in correct format. Please enter a valid number.'
                        $var = $false
                    }
                } until (($DriverSelected -ge 0) -and ($DriverSelected -lt $DriverSourcesCount) -and $var)
                
                $DriverSourcePath = $DriverSources[$DriverSelected].Path
                $DriverSourceType = $DriverSources[$DriverSelected].Type
                WriteLog "User selected Type: $DriverSourceType, Path: $DriverSourcePath"
                Write-Host "`nUser selected Type: $DriverSourceType, Path: $DriverSourcePath"
            }
        }
        else {
            WriteLog "No driver WIMs or folders found in Drivers directory."
            Write-Host "No driver WIMs or folders found in Drivers directory."
        }
    }
    else {
        WriteLog "Drivers folder not found at $DriversPath. Skipping driver installation."
    }
}
#Partition drive
Writelog 'Clean Disk'
$originalProgressPreference = $ProgressPreference
try {
    $ProgressPreference = 'SilentlyContinue'
    $Disk = Get-Disk -Number $DiskID
    if ($Disk.PartitionStyle -ne "RAW") {
        $Disk | clear-disk -RemoveData -RemoveOEM -Confirm:$false
    }
}
catch {
    WriteLog 'Cleaning disk failed. Exiting'
    throw $_
}
finally {
    $ProgressPreference = $originalProgressPreference
}

Writelog 'Cleaning Disk succeeded'

#Apply FFU
Write-SectionHeader -Title 'Applying FFU'
WriteLog "Applying FFU to $PhysicalDeviceID"
WriteLog "Running command dism /apply-ffu /ImageFile:$FFUFileToInstall /ApplyDrive:$PhysicalDeviceID"
#In order for Applying Image progress bar to show up, need to call dism directly. Might be a better way to handle, but must have progress bar show up on screen.
dism /apply-ffu /ImageFile:$FFUFileToInstall /ApplyDrive:$PhysicalDeviceID
$dismExitCode = $LASTEXITCODE

if ($dismExitCode -ne 0) {
    $errorMessage = "Failed to apply FFU. LastExitCode = $dismExitCode."
    if ($dismExitCode -eq 1393) {
        WriteLog "Failed to apply FFU - LastExitCode = $dismExitCode"
        WriteLog "This is likely due to a mismatched LogicalSectorSizeBytes"
        WriteLog "BytesPerSector value from Win32_Diskdrive is $BytesPerSector"
        if ($BytesPerSector -eq 4096) {
            WriteLog "The FFU build process by default uses a 512 LogicalSectorSizeBytes. Rebuild the FFU by adding -LogicalSectorSizeBytes 4096 to the command line"
        }
        elseif ($BytesPerSector -eq 512) {
            WriteLog "This FFU was likely built with a LogicalSectorSizeBytes of 4096. Rebuild the FFU by adding -LogicalSectorSizeBytes 512 to the command line"
        }
        $errorMessage += " This is likely due to a mismatched logical sector size. Check logs for details."
    }
    else {
        Writelog "Failed to apply FFU - LastExitCode = $dismExitCode also check dism.log on the USB drive for more info"
        $errorMessage += " Check dism.log on the USB drive for more info."
    }
    Stop-Script -Message $errorMessage
}

WriteLog 'Successfully applied FFU'

# Verify Windows partition exists and assign drive letter
$windowsPartition = Get-Partition -DiskNumber $DiskID | Where-Object { $_.PartitionNumber -eq 3 }
if ($null -eq $windowsPartition) {
    $errorMessage = "Windows partition (Partition 3) not found after applying FFU, even though DISM reported success."
    WriteLog $errorMessage
    Stop-Script -Message $errorMessage
}

WriteLog "Assigning drive letter 'W' to Windows partition."
Set-Partition -InputObject $windowsPartition -NewDriveLetter W

# Verify the drive letter was set
$windowsVolume = Get-Volume -DriveLetter W -ErrorAction SilentlyContinue
if ($null -eq $windowsVolume) {
    $errorMessage = "Failed to assign drive letter 'W' to the Windows partition after applying FFU."
    WriteLog $errorMessage
    Stop-Script -Message $errorMessage
}
WriteLog "Successfully assigned drive letter 'W'."

$recoveryPartition = Get-Partition -DiskNumber $DiskID | Where-Object PartitionNumber -eq 4
if ($recoveryPartition) {
    WriteLog 'Setting recovery partition attributes'
    $diskpartScript = @(
        "SELECT DISK $($Disk.Number)",
        "SELECT PARTITION $($recoveryPartition.PartitionNumber)",
        "GPT ATTRIBUTES=0x8000000000000001",
        "EXIT"
    )
    $diskpartScript | diskpart.exe | Out-Null
    WriteLog 'Setting recovery partition attributes complete'
}

#Copy modified WinRE if folder exists, else copy inbox WinRE
$WinRE = $USBDrive + "WinRE\winre.wim"
If (Test-Path -Path $WinRE) {
    WriteLog 'Copying modified WinRE to Recovery directory'
    Get-Disk | Where-Object Number -eq $DiskID | Get-Partition | Where-Object Type -eq Recovery | Set-Partition -NewDriveLetter R
    Invoke-Process xcopy.exe "/h $WinRE R:\Recovery\WindowsRE\ /Y"
    WriteLog 'Copying WinRE to Recovery directory succeeded'
    WriteLog 'Registering location of recovery tools'
    Invoke-Process W:\Windows\System32\Reagentc.exe "/Setreimage /Path R:\Recovery\WindowsRE /Target W:\Windows"
    Get-Disk | Where-Object Number -eq $DiskID | Get-Partition | Where-Object Type -eq Recovery | Remove-PartitionAccessPath -AccessPath R:
    WriteLog 'Registering location of recovery tools succeeded'
}
#Autopilot JSON
If ($APFileToInstall) {
    Write-SectionHeader -Title 'Applying Autopilot Configuration'
    WriteLog "Copying $APFileToInstall to W:\windows\provisioning\autopilot"
    Invoke-process xcopy.exe "$APFileToInstall W:\Windows\provisioning\autopilot\"
    WriteLog "Copying $APFileToInstall to W:\windows\provisioning\autopilot succeeded"
    # Rename file in W:\Windows\Provisioning\Autopilot to AutoPilotConfigurationFile.json
    try {
        Rename-Item -Path "W:\Windows\Provisioning\Autopilot\$APFileName" -NewName 'W:\Windows\Provisioning\Autopilot\AutoPilotConfigurationFile.json'
        WriteLog "Renamed W:\Windows\Provisioning\Autopilot\$APFilename to W:\Windows\Provisioning\Autopilot\AutoPilotConfigurationFile.json"
    }
    
    catch {
        Writelog "Copying $APFileToInstall to W:\windows\provisioning\autopilot failed with error: $_"
        throw $_
    }
}
#Apply PPKG
If ($PPKGFileToInstall) {
    Write-SectionHeader -Title 'Applying Provisioning Package'
    try {
        #Make sure to delete any existing PPKG on the USB drive
        Get-Childitem -Path $USBDrive\*.ppkg | ForEach-Object {
            Remove-item -Path $_.FullName
        }
        WriteLog "Copying $PPKGFileToInstall to $USBDrive"
        Write-Host "Copying $PPKGFileToInstall to $USBDrive"
        Invoke-process xcopy.exe "$PPKGFileToInstall $USBDrive"
        WriteLog "Copying $PPKGFileToInstall to $USBDrive succeeded"
        Write-Host "Copying $PPKGFileToInstall to $USBDrive succeeded"
    }

    catch {
        Writelog "Copying $PPKGFileToInstall to $USBDrive failed with error: $_"
        Write-Host "Copying $PPKGFileToInstall to $USBDrive failed with error: $_"
        throw $_
    }
}
#Set DeviceName
If ($computername) {
    Write-SectionHeader -Title 'Applying Computer Name and Unattend Configuration'
    try {
        $PantherDir = 'w:\windows\panther'
        If (Test-Path -Path $PantherDir) {
            Writelog "Copying $UnattendFile to $PantherDir"
            Write-Host "Copying $UnattendFile to $PantherDir"
            Invoke-process xcopy "$UnattendFile $PantherDir /Y"
            WriteLog "Copying $UnattendFile to $PantherDir succeeded"
            Write-Host "Copying $UnattendFile to $PantherDir succeeded"
        }
        else {
            Writelog "$PantherDir doesn't exist, creating it"
            New-Item -Path $PantherDir -ItemType Directory -Force
            Writelog "Copying $UnattendFile to $PantherDir"
            Write-Host "Copying $UnattendFile to $PantherDir"
            Invoke-Process xcopy.exe "$UnattendFile $PantherDir"
            WriteLog "Copying $UnattendFile to $PantherDir succeeded"
            Write-Host "Copying $UnattendFile to $PantherDir succeeded"
        }
    }
    catch {
        WriteLog "Copying Unattend.xml to name device failed"
        Stop-Script -Message "Copying Unattend.xml to name device failed with error: $_"
    }   
}

#Add Drivers
if ($null -ne $DriverSourcePath) {
    Write-SectionHeader -Title 'Installing Drivers'
    if ($DriverSourceType -eq 'WIM') {
        WriteLog "Installing drivers from WIM: $DriverSourcePath"
        Write-Host "Installing drivers from WIM: $DriverSourcePath"
        $TempDriverDir = "W:\TempDrivers"
        try {
            WriteLog "Creating temporary directory for drivers at $TempDriverDir"
            New-Item -Path $TempDriverDir -ItemType Directory -Force | Out-Null
            
            WriteLog "Mounting WIM contents to $TempDriverDir"
            Write-Host "Mounting WIM contents to $TempDriverDir"
            # For some reason can't use /mount-image with invoke-process, so using dism.exe directly
            dism.exe /Mount-Image /ImageFile:$DriverSourcePath /Index:1 /MountDir:$TempDriverDir /ReadOnly /optimize
            WriteLog "WIM mount successful."

            WriteLog "Injecting drivers from $TempDriverDir"
            Write-Host "Injecting drivers from $TempDriverDir"
            Write-Host "This may take a while, please be patient."
            Invoke-Process dism.exe "/image:W:\ /Add-Driver /Driver:""$TempDriverDir"" /Recurse"
            WriteLog "Driver injection from WIM succeeded."
            Write-Host "Driver injection from WIM succeeded."

        }
        catch {
            WriteLog "An error occurred during WIM driver installation: $_"
            # Copy DISM log to USBDrive for debugging
            invoke-process xcopy.exe "X:\Windows\logs\dism\dism.log $USBDrive /Y"
            throw $_
        }
        finally {
            if (Test-Path -Path $TempDriverDir) {
                WriteLog "Unmounting WIM from $TempDriverDir"
                Write-Host "Unmounting WIM from $TempDriverDir"
                Invoke-Process dism.exe "/Unmount-Image /MountDir:""$TempDriverDir"" /Discard"
                WriteLog "Unmount successful."
                Write-Host "Unmount successful."
                WriteLog "Cleaning up temporary driver directory: $TempDriverDir"
                Write-Host "Cleaning up temporary driver directory: $TempDriverDir"
                Remove-Item -Path $TempDriverDir -Recurse -Force
                WriteLog "Cleanup successful."
                Write-Host "Cleanup successful."
            }
        }
    }
    elseif ($DriverSourceType -eq 'Folder') {
        WriteLog "Injecting drivers from folder: $DriverSourcePath"
        Invoke-Process dism.exe "/image:W:\ /Add-Driver /Driver:""$DriverSourcePath"" /Recurse"
        WriteLog "Driver injection from folder succeeded."
    }
}
else {
    WriteLog "No drivers to install."
}
Write-SectionHeader -Title 'Setting Boot Configuration'
WriteLog "Setting Windows Boot Manager to be first in the firmware display order."
Write-Host "Setting Windows Boot Manager to be first in the firmware display order."
Invoke-Process bcdedit.exe "/set {fwbootmgr} displayorder {bootmgr} /addfirst"
WriteLog "Setting Windows Boot Manager to be first in the default display order."
Write-Host "Setting Windows Boot Manager to be first in the default display order."
Invoke-Process bcdedit.exe "/set {bootmgr} displayorder {default} /addfirst"
#Copy DISM log to USBDrive
WriteLog "Copying dism log to $USBDrive"
invoke-process xcopy "X:\Windows\logs\dism\dism.log $USBDrive /Y" 
WriteLog "Copying dism log to $USBDrive succeeded"




