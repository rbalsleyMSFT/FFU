$Host.UI.RawUI.WindowTitle = 'Full Flash Update Imaging Tool | May 2024'
#InitializeWinPE
#FUNCTIONS
function Initialize-WinPE {
    param (
        [string]$FilePath = "X:\Windows\System32\wpeinit.exe"
    )
    Start-Process -FilePath $FilePath
    #Write-host "Initializing..." -ForegroundColor Cyan
}

function Get-DeviceInfo {
    $Computersystem = Get-WmiObject -ClassName win32_computersystem
    $Bios = Get-WmiObject -ClassName win32_bios
    $Time = Get-Date
    $SerialNumber = $bios.SerialNumber
    $Manufacturer = $computersystem.Manufacturer
    $SystemFamily = $computersystem.SystemFamily
    $Battery = Get-CimInstance win32_battery
    if($Battery){
        $BatteryStatus = ((($Battery).EstimatedChargeRemaining).ToString())+"%"
    }
    #If Lenovo device only return first 4 characters of model name which is the model type; otherwise return full device model
    if($Manufacturer -eq "LENOVO"){
        $model = ($computersystem.Model).SubString(0,4)
    } else {
        $model = $computersystem.Model
    }
    return $model, $SystemFamily , $Manufacturer , $SerialNumber , $Time , $BatteryStatus
}

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
    $DeviceID = (Get-WmiObject -Class 'Win32_DiskDrive' | Where-Object {$_.MediaType -eq 'Fixed hard disk media' -and $_.Model -ne 'Microsoft Virtual Disk'}).DeviceID
    #Get non USB drives
    $NotUSBDrive = Get-Disk | Where-Object {$_.UniqueId -notmatch "USBSTOR"}
   
    $DriveName = $NotUSBDrive.FriendlyName
    if ($NotUSBDrive -and $DeviceID){
    $DriveDetected = "Yes" 
    return $DriveDetected , $DriveName, $DeviceID
    }else{
    
    
    return $DriveDetected = "No"
}
}

function WriteLog($LogText){ 
    Add-Content -path $LogFile -value "$((Get-Date).ToString()) $LogText"
}

function Set-DiskpartAnswerFiles($DiskpartFile,$DiskID){
    (Get-Content $DiskpartFile).Replace('disk 0', "disk $DiskID") | Set-Content -Path $DiskpartFile
}

function Set-Computername($computername){
    [xml]$xml = Get-Content $UnattendFile
    if($xml.unattend.settings.component.Count -ge 2){
        #Assumes that Computername is the first component element
        $xml.unattend.settings.component[0].ComputerName = $computername
    }else{
        $xml.unattend.settings.component.ComputerName = $computername
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

function Color ($bc,$fc) {
$Console = (Get-Host).UI.RawUI
$Console.BackgroundColor = $bc
$Console.ForegroundColor = $fc ; cls}
# This function can be used in instances where battery level might matter (e.g. installing firmware for Surface). The problem is that WinPE doesn't have
# a driver for the battery installed, so you'll need to inject drivers, which can be tricky because just injecting the battery driver might not be enough,
# you might also need other drivers that the battery driver is dependent on. 
# function Get-Battery(){
#     while (($BattLev = (Get-CimInstance win32_battery).EstimatedChargeRemaining) -lt "35")
#     {
#         WriteLog "Battery is currently at $BattLev`%. Waiting for 35`% to proceed..."
#         Write-Host "Battery is currently at $BattLev`%. Waiting for 35`% to proceed..."
#         Start-Sleep 60
#     }

#     WriteLog "Battery level is $BattLev `%, which is greater than 35'% applying FFU"
#     Write-Host "Battery level is $BattLev `%, which is greater than 35'% applying FFU"
# }
#Start Wpeinit to detect hardware
Initialize-WinPE
#Get USB Drive and create log file
$LogFileName = 'ScriptLog.txt'
$USBDrive = Get-USBDrive
New-item -Path $USBDrive -Name $LogFileName -ItemType "file" -Force | Out-Null
$LogFile = $USBDrive + $LogFilename
WriteLog 'Begin Logging'

#Detect PhysicalDrive
$DriveDetected ,$DriveName, $PhysicalDeviceID = Get-HardDrive
WriteLog "Main drive detected: $DriveDetected"
WriteLog "Main drive Name: $DriveName"
WriteLog "Physical DeviceID is $PhysicalDeviceID"
$DrivePresent = switch ($DriveDetected) {
       'No' {
       Write-Output "No drive detected!"
     } 'Yes' {
       Write-Output $DriveName
     } 
 }
if($DriveDetected -eq "No"){
Color -bc red -fc Black
}

#Parse DiskID Number
$DiskID = $PhysicalDeviceID.substring($PhysicalDeviceID.length - 1,1)
WriteLog "DiskID is $DiskID"
#retrieve device info
$model, $SystemFamily , $Manufacturer , $SerialNumber , $time , $BatteryLevel = Get-DeviceInfo
#COMMENT THIS WHOLE BLOCK OUT ONCE FFUPROVIDER FIX IS IN
#Modify diskpart answer files if DiskID not 0
# $UEFIFFUPartitions = 'x:\CreateUEFI-FFU-Partitions.txt'
#$ExtendPartition = 'x:\ExtendPartition-UEFI.txt'

#If ($DiskID -ne '0'){
 #   WriteLog 'DiskID is not 0. Need to modify diskpart answer files'
    # try {
    #     Set-DiskpartAnswerFiles $UEFIFFUPartitions $DiskID
    # }
    # catch {
    #     WriteLog "Modifying $UEFIFFUPartitions failed with error: $_"
    # }
    
   # try {
  #      Set-DiskpartAnswerFiles $ExtendPartition $DiskID
  #  }
 #   catch {
  #      WriteLog "Modifying $ExtendPartition failed with error: $_"
  #  }
#}

#Find FFU Files
$CurrentDate = Get-date
$ImageLastUpdatedMax = 90
$ImagesFolder = $USBDrive + "Images\"
[array]$FFUFiles = @(Get-ChildItem -Path $ImagesFolder*.ffu) # | Where-object {$_.LastWriteTime -le $ImageLastUpdatedMax}
#[array]$ExpiredFFUFiles = @(Get-ChildItem -Path $ImagesFolder*.ffu) | Where-object {$_.LastWriteTime -gt $ImageLastUpdatedMax}

$FFUCount = $FFUFiles.Count
#$ExpiredFFUCount = $ExpiredFFUFiles.count
#If multiple FFUs found, ask which to install
If ($FFUFiles) {
#If ($FFUCount -gt 1) {
    WriteLog "Found $FFUCount FFU Files"
    Write-Host "Device Information:"
    Write-Host "System Time: " -NoNewline -ForegroundColor Cyan
    Write-Host $time
    Write-Host "Serial Number: " -NoNewline -ForegroundColor Cyan
    Write-Host $SerialNumber
    Write-Host "Model: " -NoNewline -ForegroundColor Cyan
    Write-Host $Model
    Write-Host "System Family: " -NoNewline -ForegroundColor Cyan
    Write-Host  $SystemFamily
    Write-Host "Manufacturer: " -NoNewline -ForegroundColor Cyan
    Write-Host  $Manufacturer
    Write-Host "Drive Detected: " -NoNewline -ForegroundColor Cyan
    Write-Host  $DrivePresent
    if($BatteryLevel){
    Write-Host "Current Charge level: " -NoNewline -ForegroundColor Cyan
    Write-Host  $BatteryLevel}
    WriteLog "Device information Shown"
    $array = @()
    #Show list of valid Images
    for($i=0;$i -le $FFUCount -1;$i++){
        $lastWriteTime = $FFUFiles[$i].LastWriteTime
        $LastUpdatedDays = ($CurrentDate - $lastWriteTime).Days
        $UpdatedDaysAgo = "$LastUpdatedDays" + " days ago"
	$Properties = [ordered]@{Number = $i + 1  ; FFUFile = $FFUFiles[$i].FullName ; LastUpdated = $UpdatedDaysAgo } 

        #$Properties.Clear()
        $array += New-Object PSObject -Property $Properties

    }
    $array | Format-Table -AutoSize -Property Number, FFUFile, LastUpdated
    #$array = ""
    #SHow list of Expired FFU Images
       for($i=0;$i -le $ExpiredFFUCount -1;$i++){
        $lastWriteTime = $ExpiredFFUFiles[$i].LastWriteTime
        $LastUpdatedDays = ($CurrentDate - $lastWriteTime).Days
        $UpdatedDaysAgo = "$LastUpdatedDays" + " days ago"
	$ExpiredProperties = [ordered]@{Number = $i + 1  ; FFUFile = $ExpiredFFUFiles[$i].FullName ; LastUpdated = $UpdatedDaysAgo } 

        #$Properties.Clear()
        $Expiredarray += New-Object PSObject -Property $Properties

    }
    $Expiredarray | Format-Table -AutoSize -Property Number, FFUFile, LastUpdated
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
#elseif (!$FFUFiles -and $ExpiredFFUFiles) {
 #   WriteLog "Found $FFUCount FFU File"
  #  $FFUFileToInstall = $FFUFiles[0].FullName
 #   WriteLog "$FFUFileToInstall will be installed"
 #   Writelog 'Expired FFU files found'
#    Write-Host 'Expired FFU files found. FFU files need to be updated less than $ImageLastUpdatedMax days ago. Please load updated FFU files'
#    Pause
#    Exit
#} 
else {
    Writelog 'No FFU files found'
    Write-Host 'No FFU files found.'
    Pause
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
    $computername = $PrefixToUse + $serial
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
#If (Test-Path -Path $Drivers){}
#$Drivers = $USBDrive + "Drivers"
#If (Test-Path -Path $Drivers)
#{
    #Check if multiple driver folders found, if so, just select one folder to save time/space
#    $DriverFolders = Get-ChildItem -Path $Drivers
#    $DriverFoldersCount = $DriverFolders.count
#    If ($DriverFoldersCount -gt 1)
#    {
 #       WriteLog "Found $DriverFoldersCount driver folders"
 #       $array = @()

  #      for($i=0; $i -le $DriverFoldersCount -1; $i++){
  #      $Properties = [ordered]@{Number = $i + 1; Drivers = $DriverFolders[$i].FullName}
    #    $array += New-Object PSObject -Property $Properties
    #    }
   # $array | Format-Table -AutoSize -Property Number, Drivers
   # do {
  #      try {
  #          $var = $true
    ##        [int]$DriversSelected = Read-Host 'Enter the set of drivers to install'
    #        $DriversSelected = $DriversSelected - 1
   #     }
   #
     #   catch {
     #       Write-Host 'Input was not in correct format. Please enter a valid driver folder number'
      #      $var = $false
      #  }
   # } until (($DriversSelected -le $DriverFoldersCount -1) -and $var) 

  #  $Drivers = $array[$DriversSelected].Drivers
  #  WriteLog "$Drivers was selected"
   # }
   # elseif ($DriverFoldersCount -eq 1) {
   #     WriteLog "Found $DriverFoldersCount driver folder"
    #    $Drivers = $DriverFolders.FullName
    #    WriteLog "$Drivers will be installed"
    #} 
  #  else {
  #      Writelog 'No driver folders found'
   # }
#}

#If you want to enable battery level checking, uncomment the line below as well as the Get-Battery function near the top of the script
#Get-Battery

#Partition drive
Writelog 'Clean Disk'
#Start-Process -FilePath diskpart.exe -ArgumentList "/S $UEFIFFUPartitions" -Wait -ErrorAction Stop | Out-File $Logfile -Append
#Invoke-Process diskpart.exe "/S $UEFIFFUPartitions"
try {
    $Disk = Get-Disk -Number $DiskID
    $Disk | Clear-Disk -RemoveData -RemoveOEM -Confirm:$false
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
WriteLog "Waiting for C drive to be initialized"
while (!(Test-Path "C:\")) {
    Set-partition -DiskNumber 0 -PartitionNumber 3 -NewDriveLetter C -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    }
WriteLog "C: drive now initialized."
if($LASTEXITCODE -eq 0){
    WriteLog 'Successfully applied FFU'
}
else{
    Writelog "Failed to apply FFU - LastExitCode = $LASTEXITCODE also check dism.log on the USB drive for more info"
    #Copy DISM log to USBDrive
    invoke-process xcopy.exe "X:\Windows\logs\dism\dism.log $USBDrive /Y"
    exit
}

#Remove recovery partition - this is needed in order to extend the Windows partition so it uses the full disk size. If dism /optimize-ffu worked, this wouldn't be needed
# $disk = get-disk -Number $DiskID
# $RecoveryPartition = $disk | get-partition | Where-Object {$_.type -eq 'Recovery'}
# if ($RecoveryPartition){
#     $RecoveryPartitionNumber = $RecoveryPartition.PartitionNumber
#     if ($RecoveryPartitionNumber -eq 4){
#         try {
#             WriteLog 'Removing recovery partition'
#             Remove-partition -DiskNumber $DiskID -PartitionNumber $RecoveryPartitionNumber -Confirm:$false
#         }
#         catch {
#             WriteLog 'Error removing recovery partition, exiting'
#             throw $_
#         }
#     }
#     else{
#         WriteLog 'Recovery partition not partition 4. Script will exit. Please create the FFU with the recovery partition as the last partition. This is the default and recommended way.'
#         exit
#     }
# }

#COMMENT THIS WHOLE BLOCK OUT AFTER FFUPROVIDER FIX IS IN
# Extend Windows partition and create recovery partition
#Writelog 'Extending Windows partition'
#Invoke-Process diskpart.exe "/S $ExtendPartition"
#if($LASTEXITCODE -eq 0){
#    WriteLog 'Successfully extended Windows partition and created recovery partition'
#}
#else{
#    Writelog "Failed to extend Windows partition and/or create recovery partition - LastExitCode = $LASTEXITCODE"
#}

#UNCOMMENT THIS AFTER FFUPROVIDER FIX IS IN
#Set W: drive letter to Windows partition
#Get-Disk | Where-Object Number -eq $DiskID | Get-Partition | Where-Object PartitionNumber -eq 3 | Set-Partition -NewDriveLetter W

#Copy modified WinRE if folder exists, else copy inbox WinRE
#$WinRE = $USBDrive + "WinRE\winre.wim"
#If (Test-Path -Path $WinRE)
#{
 #   WriteLog 'Copying modified WinRE to Recovery directory'
 #   Invoke-Process xcopy.exe "/h $WinRE R:\Recovery\WindowsRE\ /Y"
 #   WriteLog 'Copying WinRE to Recovery directory succeeded'
 #   WriteLog 'Registering location of recovery tools'
 #   Invoke-Process W:\Windows\System32\Reagentc.exe "/Setreimage /Path R:\Recovery\WindowsRE /Target W:\Windows"
 #   WriteLog 'Registering location of recovery tools succeeded'
#}
# else
# {
#     WriteLog 'Copying default WinRE to Recovery directory'
#     Invoke-Process xcopy.exe "/h W:\Windows\System32\Recovery\Winre.wim R:\Recovery\WindowsRE\ /Y"
#     WriteLog 'Copying WinRE to Recovery directory succeeded'
#     WriteLog 'Registering location of recovery tools'
#     Invoke-process W:\Windows\System32\Reagentc.exe "/Setreimage /Path R:\Recovery\WindowsRE /Target W:\Windows"
#     WriteLog 'Registering location of recovery tools succeeded'
# }

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
If ($PrefixToUse){
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
#If (Test-Path -Path $Drivers)
#{
#    WriteLog 'Copying drivers'
 #   Write-Warning 'Copying Drivers - dism will pop a window with no progress. This can take a few minutes to complete. This is done so drivers are logged to the scriptlog.txt file. Please be patient.'
#    Invoke-process dism.exe "/image:W:\ /Add-Driver /Driver:""$Drivers"" /Recurse"
#    WriteLog 'Copying drivers succeeded'
#}
$DriversPath = $USBDrive + "Drivers\" + $Model
$DriversAvailable = test-path -Path $DriversPath -ErrorAction SilentlyContinue

If ($DriversAvailable){
    WriteLog "Applying drivers: $SystemFamily"
    Dism /Image:C: /Add-Driver /Driver:"$DriversPath" /Recurse 
    #pause
    Wpeutil reboot

}else{
    WriteLog "No drivers for this model found for $SystemFamily"
    Pause
    Wpeutil reboot
    }

#Copy DISM log to USBDrive
WriteLog "Copying dism log to $USBDrive"
invoke-process xcopy "X:\Windows\logs\dism\dism.log $USBDrive /Y" 
WriteLog "Copying dism log to $USBDrive succeeded"




