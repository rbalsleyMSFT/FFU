function Get-USBDrive(){
    $USBDriveLetter = (Get-Volume | Where-Object {$_.DriveType -eq 'Removable' -and $_.FileSystemType -eq 'NTFS'}).DriveLetter
    if ($null -eq $USBDriveLetter){
        #Must be using a fixed USB drive - difficult to grab drive letter from win32_diskdrive. Assume user followed instructions and used Deploy as the friendly name for partition
        $USBDriveLetter = (Get-Volume | Where-Object {$_.DriveType -eq 'Fixed' -and $_.FileSystemType -eq 'NTFS' -and $_.FileSystemLabel -eq 'Deploy'}).DriveLetter
        #If we didn't get the drive letter, stop the script.
        if ($null -eq $USBDriveLetter){
            WriteLog 'Cannot find USB drive letter - most likely using a fixed USB drive. Name the 2nd partition with the FFU files as Deploy so the script can grab the drive letter. Exiting'
            Exit
        }

    }
    $USBDriveLetter = $USBDriveLetter + ":\"
    return $USBDriveLetter
}

function Get-HardDrive(){
    $SystemInfo = Get-WmiObject -Class 'Win32_ComputerSystem'
    $Manufacturer = $SystemInfo.Manufacturer
    $Model = $SystemInfo.Model
    WriteLog "Device Manufacturer: $Manufacturer"
    WriteLog "Device Model: $Model"
    WriteLog 'Getting Hard Drive info'
    if ($Manufacturer -eq 'Microsoft Corporation' -and $Model -eq 'Virtual Machine'){
        WriteLog 'Running in a Hyper-V VM. Getting virtual disk on Index 0 and SCSILogicalUnit 0'
        $DiskDrive = Get-WmiObject -Class 'Win32_DiskDrive' | Where-Object {$_.MediaType -eq 'Fixed hard disk media' `
        -and $_.Model -eq 'Microsoft Virtual Disk' `
        -and $_.Index -eq 0 `
        -and $_.SCSILogicalUnit -eq 0
        }
    }
    else{
        WriteLog 'Not running in a VM. Getting physical disk drive'
        $DiskDrive = Get-WmiObject -Class 'Win32_DiskDrive' | Where-Object {$_.MediaType -eq 'Fixed hard disk media' -and $_.Model -ne 'Microsoft Virtual Disk'}
    }
    $DeviceID = $DiskDrive.DeviceID
    $BytesPerSector = $Diskdrive.BytesPerSector

    # Create a custom object to return both values
    $result = New-Object PSObject -Property @{
        DeviceID = $DeviceID
        BytesPerSector = $BytesPerSector
    }

    return $result
}

function WriteLog($LogText){ 
    Add-Content -path $LogFile -value "$((Get-Date).ToString()) $LogText"
}

function Set-DiskpartAnswerFiles($DiskpartFile,$DiskID){
    (Get-Content $DiskpartFile).Replace('disk 0', "disk $DiskID") | Set-Content -Path $DiskpartFile
}

function Set-Computername($computername){
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
			NoNewWindow            = $false;
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
			} else {
				if ([string]::IsNullOrEmpty($cmdOutput) -eq $false) {
					WriteLog $cmdOutput
				}
			}
		}
	} catch {
		#$PSCmdlet.ThrowTerminatingError($_)
		WriteLog $_
        Write-Host 'Script failed - check scriptlog.txt on the USB drive for more info'
		throw $_

	} finally {
		Remove-Item -Path $stdOutTempFile, $stdErrTempFile -Force -ErrorAction Ignore
		
	}
	
}

#Get USB Drive and create log file
$LogFileName = 'ScriptLog.txt'
$USBDrive = Get-USBDrive
New-item -Path $USBDrive -Name $LogFileName -ItemType "file" -Force | Out-Null
$LogFile = $USBDrive + $LogFilename
$version = '2412.3'
WriteLog 'Begin Logging'
WriteLog "Script version: $version"

#Find PhysicalDrive
# $PhysicalDeviceID = Get-HardDrive
$hardDrive = Get-HardDrive
if($null -eq $hardDrive){
    WriteLog 'No hard drive found. Exiting'
    WriteLog 'Try adding storage drivers to the PE boot image (you can re-create your FFU and USB drive and add the PE drivers to the PEDrivers folder and add -CopyPEDrivers $true to the command line, or manually add them via DISM)'
    Exit
}
$PhysicalDeviceID = $hardDrive.DeviceID
$BytesPerSector = $hardDrive.BytesPerSector
WriteLog "Physical BytesPerSector is $BytesPerSector"
WriteLog "Physical DeviceID is $PhysicalDeviceID"

#Parse DiskID Number
$DiskID = $PhysicalDeviceID.substring($PhysicalDeviceID.length - 1,1)
WriteLog "DiskID is $DiskID"

#Find FFU Files
[array]$FFUFiles = @(Get-ChildItem -Path $USBDrive*.ffu)
$FFUCount = $FFUFiles.Count

#If multiple FFUs found, ask which to install
If ($FFUCount -gt 1) {
    WriteLog "Found $FFUCount FFU Files"
    $array = @()

    for($i=0;$i -le $FFUCount -1;$i++){
        $Properties = [ordered]@{Number = $i + 1 ; FFUFile = $FFUFiles[$i].FullName}
        $array += New-Object PSObject -Property $Properties
    }
    $array | Format-Table -AutoSize -Property Number, FFUFile
    do {
        try {
            $var = $true
            [int]$FFUSelected = Read-Host 'Enter the FFU number to install'
            $FFUSelected = $FFUSelected -1
        }

        catch {
            Write-Host 'Input was not in correct format. Please enter a valid FFU number'
            $var = $false
        }
    } until (($FFUSelected -le $FFUCount -1) -and $var) 

    $FFUFileToInstall = $array[$FFUSelected].FFUFile
    WriteLog "$FFUFileToInstall was selected"
}
elseif ($FFUCount -eq 1) {
    WriteLog "Found $FFUCount FFU File"
    $FFUFileToInstall = $FFUFiles[0].FullName
    WriteLog "$FFUFileToInstall will be installed"
} 
else {
    Writelog 'No FFU files found'
    Write-Host 'No FFU files found'
    Exit
}

#FindAP
$APFolder = $USBDrive + "Autopilot\"
If (Test-Path -Path $APFolder){
    [array]$APFiles = @(Get-ChildItem -Path $APFolder*.json)
    $APFilesCount = $APFiles.Count
    if ($APFilesCount -ge 1){
    $autopilot = $true
    }
}


#FindPPKG
$PPKGFolder = $USBDrive + "PPKG\"
if (Test-Path -Path $PPKGFolder){
    [array]$PPKGFiles = @(Get-ChildItem -Path $PPKGFolder*.ppkg)
    $PPKGFilesCount = $PPKGFiles.Count
    if ($PPKGFilesCount -ge 1){
    $PPKG = $true
    }
}

#FindUnattend
$UnattendFolder = $USBDrive + "unattend\"
$UnattendFilePath = $UnattendFolder + "unattend.xml"
$UnattendPrefixPath = $UnattendFolder + "prefixes.txt"
If (Test-Path -Path $UnattendFilePath){
    $UnattendFile = Get-ChildItem -Path $UnattendFilePath
    If ($UnattendFile){
        $Unattend = $true
    }
}
If (Test-Path -Path $UnattendPrefixPath){
    $UnattendPrefixFile = Get-ChildItem -Path $UnattendPrefixPath
    If ($UnattendPrefixFile){
        $UnattendPrefix = $true
    }
}

#Ask for device name if unattend exists
if ($Unattend -and $UnattendPrefix){
    Writelog 'Unattend file found with prefixes.txt. Getting prefixes.'
    $UnattendPrefixes = @(Get-content $UnattendPrefixFile)
    $UnattendPrefixCount = $UnattendPrefixes.Count
    If ($UnattendPrefixCount -gt 1) {
        WriteLog "Found $UnattendPrefixCount Prefixes"
        $array = @()
        for($i=0;$i -le $UnattendPrefixCount -1;$i++){
            $Properties = [ordered]@{Number = $i + 1 ; DeviceNamePrefix = $UnattendPrefixes[$i]}
            $array += New-Object PSObject -Property $Properties
        }
        $array | Format-Table -AutoSize -Property Number, DeviceNamePrefix
        do {
            try {
                $var = $true
                [int]$PrefixSelected = Read-Host 'Enter the prefix number to use for the device name'
                $PrefixSelected = $PrefixSelected -1
            }
            catch {
                Write-Host 'Input was not in correct format. Please enter a valid prefix number'
                $var = $false
            }
        } until (($PrefixSelected -le $UnattendPrefixCount -1) -and $var) 
        $PrefixToUse = $array[$PrefixSelected].DeviceNamePrefix
        WriteLog "$PrefixToUse was selected"
    }
    elseif ($UnattendPrefixCount -eq 1) {
    WriteLog "Found $UnattendPrefixCount Prefix"
    $PrefixToUse = $UnattendPrefixes[0]
    WriteLog "Will use $PrefixToUse as device name prefix"
    }
    #Get serial number to append. This can make names longer than 15 characters. Trim any leading or trailing whitespace
    $serial = (Get-CimInstance -ClassName win32_bios).SerialNumber.Trim()
    #Combine prefix with serial
    $computername = ($PrefixToUse + $serial) -replace "\s","" # Remove spaces because windows does not support spaces in the computer names
    #If computername is longer than 15 characters, reduce to 15. Sysprep/unattend doesn't like ComputerName being longer than 15 characters even though Windows accepts it
    If ($computername.Length -gt 15){
       $computername = $computername.substring(0,15)
    }
    $computername = Set-Computername($computername)
    Writelog "Computer name set to $computername"
}
elseif($Unattend){
    Writelog 'Unattend file found with no prefixes.txt, asking for name'
    [string]$computername = Read-Host 'Enter device name'
    Set-Computername($computername)
    Writelog "Computer name set to $computername"
}
else {
    WriteLog 'No unattend folder found. Device name will be set via PPKG, AP JSON, or default OS name.'
}

#If both AP and PPKG folder found with files, ask which to use.
If($autopilot -eq $true -and $PPKG -eq $true){
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
    If ($APorPPKG -eq 1){
        $PPKG = $false
    }
    else{
        $autopilot = $false
    } 
}

#If multiple AP json files found, ask which to install
If ($APFilesCount -gt 1 -and $autopilot -eq $true) {
    WriteLog "Found $APFilesCount Autopilot json Files"
    $array = @()

    for($i=0;$i -le $APFilesCount -1;$i++){
        $Properties = [ordered]@{Number = $i + 1 ; APFile = $APFiles[$i].FullName; APFileName = $APFiles[$i].Name}
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
    } until (($APFileSelected -le $APFilesCount -1) -and $var) 

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
    WriteLog "Found $PPKGFilesCount PPKG Files"
    $array = @()

    for($i=0;$i -le $PPKGFilesCount -1;$i++){
        $Properties = [ordered]@{Number = $i + 1 ; PPKGFile = $PPKGFiles[$i].FullName; PPKGFileName = $PPKGFiles[$i].Name}
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
    } until (($PPKGFileSelected -le $PPKGFilesCount -1) -and $var) 

    $PPKGFileToInstall = $array[$PPKGFileSelected].PPKGFile
    WriteLog "$PPKGFileToInstall was selected"
}
elseif ($PPKGFilesCount -eq 1 -and $PPKG -eq $true) {
    WriteLog "Found $PPKGFilesCount PPKG File"
    $PPKGFileToInstall = $PPKGFiles[0].FullName
    WriteLog "$PPKGFileToInstall will be used"
} 
else {
    Writelog 'No PPKG files found or PPKG not selected.'
}

#Find Drivers
$Drivers = $USBDrive + "Drivers"
If (Test-Path -Path $Drivers)
{
    #Check if multiple driver folders found, if so, just select one folder to save time/space
    $DriverFolders = Get-ChildItem -Path $Drivers -directory
    $DriverFoldersCount = $DriverFolders.count
    If ($DriverFoldersCount -gt 1)
    {
        WriteLog "Found $DriverFoldersCount driver folders"
        $array = @()

        for($i=0; $i -le $DriverFoldersCount -1; $i++){
        $Properties = [ordered]@{Number = $i + 1; Drivers = $DriverFolders[$i].FullName}
        $array += New-Object PSObject -Property $Properties
        }
    $array | Format-Table -AutoSize -Property Number, Drivers
    do {
        try {
            $var = $true
            [int]$DriversSelected = Read-Host 'Enter the set of drivers to install'
            $DriversSelected = $DriversSelected - 1
        }

        catch {
            Write-Host 'Input was not in correct format. Please enter a valid driver folder number'
            $var = $false
        }
    } until (($DriversSelected -le $DriverFoldersCount -1) -and $var) 

    $Drivers = $array[$DriversSelected].Drivers
    WriteLog "$Drivers was selected"
    }
    elseif ($DriverFoldersCount -eq 1) {
        WriteLog "Found $DriverFoldersCount driver folder"
        $Drivers = $DriverFolders.FullName
        WriteLog "$Drivers will be installed"
    } 
    else {
        Writelog 'No driver folders found'
    }
}
#Partition drive
Writelog 'Clean Disk'
try {
    $Disk = Get-Disk -Number $DiskID
    if ($Disk.PartitionStyle -ne "RAW") {
        $Disk | clear-disk -RemoveData -RemoveOEM -Confirm:$false
    }
}
catch {
    WriteLog 'Cleaning disk failed. Exiting'
    throw $_
}

Writelog 'Cleaning Disk succeeded'

#Apply FFU
WriteLog "Applying FFU to $PhysicalDeviceID"
WriteLog "Running command dism /apply-ffu /ImageFile:$FFUFileToInstall /ApplyDrive:$PhysicalDeviceID"
#In order for Applying Image progress bar to show up, need to call dism directly. Might be a better way to handle, but must have progress bar show up on screen.
dism /apply-ffu /ImageFile:$FFUFileToInstall /ApplyDrive:$PhysicalDeviceID
$recoveryPartition = Get-Partition -Disk $Disk | Where-Object PartitionNumber -eq 4
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
if($LASTEXITCODE -eq 0){
    WriteLog 'Successfully applied FFU'
}
elseif($LASTEXITCODE -eq 1393){
    WriteLog "Failed to apply FFU - LastExitCode = $LastExitCode"
    WriteLog "This is likely due to a mismatched LogicalSectorByteSize"
    WriteLog "BytesPerSector value from Win32_Diskdrive is $BytesPerSector"
    if ($BytesPerSector -eq 4096){
        WriteLog "The FFU build process by default uses a 512 LogicalSectorByteSize. Rebuild the FFU by adding -LogicalSectorByteSize 4096 to the command line"
    }
    elseif($BytesPerSector -eq 512){
        WriteLog "This FFU was likely built with a LogicalSectorByteSize of 4096. Rebuild the FFU by adding -LogicalSectorByteSize 512 to the command line"
    }
    #Copy DISM log to USBDrive
    invoke-process xcopy.exe "X:\Windows\logs\dism\dism.log $USBDrive /Y"
    exit
}
else{
    Writelog "Failed to apply FFU - LastExitCode = $LASTEXITCODE also check dism.log on the USB drive for more info"
    #Copy DISM log to USBDrive
    invoke-process xcopy.exe "X:\Windows\logs\dism\dism.log $USBDrive /Y"
    exit
}
Get-Disk | Where-Object Number -eq $DiskID | Get-Partition | Where-Object PartitionNumber -eq 3 | Set-Partition -NewDriveLetter W

#Copy modified WinRE if folder exists, else copy inbox WinRE
$WinRE = $USBDrive + "WinRE\winre.wim"
If (Test-Path -Path $WinRE)
{
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
If ($APFileToInstall){
    WriteLog "Copying $APFileToInstall to W:\windows\provisioning\autopilot"
    Invoke-process xcopy.exe "$APFileToInstall W:\Windows\provisioning\autopilot\"
    WriteLog "Copying $APFileToInstall to W:\windows\provisioning\autopilot succeeded"
    # Rename file in W:\Windows\Provisioning\Autopilot to AutoPilotConfigurationFile.json
    try {
        Rename-Item -Path "W:\Windows\Provisioning\Autopilot\$APFileName" -NewName 'W:\Windows\Provisioning\Autopilot\AutoPilotConfigurationFile.json'
        WriteLog "Renamed W:\Windows\Provisioning\Autopilot\$APFilename to W:\Windows\Provisioning\Autopilot\AutoPilotConfigurationFile.json"
    }
    
    catch{
        Writelog "Copying $APFileToInstall to W:\windows\provisioning\autopilot failed with error: $_"
        throw $_
    }
}
#Apply PPKG
If ($PPKGFileToInstall){
    try {
        #Make sure to delete any existing PPKG on the USB drive
        Get-Childitem -Path $USBDrive\*.ppkg | ForEach-Object {
            Remove-item -Path $_.FullName
        }
        WriteLog "Copying $PPKGFileToInstall to $USBDrive"
        Invoke-process xcopy.exe "$PPKGFileToInstall $USBDrive"
        WriteLog "Copying $PPKGFileToInstall to $USBDrive succeeded"
    }

    catch{
        Writelog "Copying $PPKGFileToInstall to $USBDrive failed with error: $_"
        throw $_
    }
}
#Set DeviceName
If ($computername){
    try{
        $PantherDir = 'w:\windows\panther'
        If (Test-Path -Path $PantherDir){
            Writelog "Copying $UnattendFile to $PantherDir"
            Invoke-process xcopy "$UnattendFile $PantherDir /Y"
            WriteLog "Copying $UnattendFile to $PantherDir succeeded"
        }
        else{
            Writelog "$PantherDir doesn't exist, creating it"
            New-Item -Path $PantherDir -ItemType Directory -Force
            Writelog "Copying $UnattendFile to $PantherDir"
            Invoke-Process xcopy.exe "$UnattendFile $PantherDir"
            WriteLog "Copying $UnattendFile to $PantherDir succeeded"
        }
    }
    catch{
        WriteLog "Copying Unattend.xml to name device failed"
        throw $_
    }   
}

#Add Drivers
#Some drivers can sometimes fail to copy and dism ends up with a non-zero error code. Invoke-process will throw and terminate in these instances. 
If (Test-Path -Path $Drivers)
{
    WriteLog 'Copying drivers'
    Write-Warning 'Copying Drivers - dism will pop a window with no progress. This can take a few minutes to complete. This is done so drivers are logged to the scriptlog.txt file. Please be patient.'
    Invoke-process dism.exe "/image:W:\ /Add-Driver /Driver:""$Drivers"" /Recurse"
    WriteLog 'Copying drivers succeeded'
}

WriteLog "Setting Windows Boot Manager to be first in the display order."
Invoke-Process bcdedit.exe "/set {fwbootmgr} displayorder {bootmgr} /addfirst"
WriteLog "Windows Boot Manager has been set to be first in the display order."
WriteLog "Setting default Windows boot loader to be first in the display order."
Invoke-Process bcdedit.exe "/set {bootmgr} displayorder {default} /addfirst"
WriteLog "The default Windows boot loader has been set to be first in the display order."
#Copy DISM log to USBDrive
WriteLog "Copying dism log to $USBDrive"
invoke-process xcopy "X:\Windows\logs\dism\dism.log $USBDrive /Y" 
WriteLog "Copying dism log to $USBDrive succeeded"




