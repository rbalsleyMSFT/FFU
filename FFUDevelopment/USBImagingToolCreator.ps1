[CmdletBinding()]
param(
    [Parameter(Mandatory = $True, Position = 0)]
    $DeployISOPath,
    [Switch]$DisableAutoPlay
)
$Host.UI.RawUI.WindowTitle = 'Imaging Tool USB Creator'

if($DeployISOPath){
$DevelopmentPath = $DeployISOPath | Split-Path
$ImagesPath = "$DevelopmentPath\Images"
function WriteLog($LogText) { 
$LogFileName = '\Script.log'
$LogFile = $DevelopmentPath + $LogFilename
    Add-Content -path $LogFile -value "$((Get-Date).ToString()) $LogText" -Force -ErrorAction SilentlyContinue
    Write-Verbose $LogText
}

function Write-ProgressLog {
        param(
            [string]$Activity,
            [string]$Status
        )
        Write-Progress -Activity $Activity -Status $Status -PercentComplete (($currentStep / $totalSteps) * 100)
        WriteLog $Status
        $script:currentStep++
      
    }
Function Get-RemovableDrive {
writelog "Get information for all removable drives"
$USBDrives = Get-WmiObject Win32_DiskDrive | Where-Object {$_.MediaType -eq "Removable media"} 
If($USBDrives -and ($null -eq $USBDrives.count)) {
        $USBDrivesCount = 1
    }
    else {
        $USBDrivesCount = $USBDrives.Count
    }
    WriteLog "Found $USBDrivesCount USB drives"

    if ($null -eq $USBDrives) {
        WriteLog "No removable USB drive found. Exiting"
        Write-Error "No removable USB drive found. Exiting"
        Pause
        exit 1
    }
  return $USBDrives, $USBDrivesCount
  }
  
Function Build-DeploymentUSB{
      param(
            [Array]$Drives       
            )
            writelog "Creating list of FFU image files"
            $Images = Get-ChildItem -Path $ImagesPath -Filter "*.ffu" -File -Recurse
            writelog "Checking if drivers are present in the drivers folder"
            $Drivers = Get-ChildItem -Path $DriversPath -Recurse
            $DrivesCount = $Drives.Count
            Write-ProgressLog "Create Imaging Tool" "Creating partitions..."
            writelog "Create job to partition each usb drive"
            foreach ($USBDrive in $Drives) {
            $DriveNumber = $USBDrive.DeviceID.Replace("\\.\PHYSICALDRIVE", "")
            $Model = $USBDrive.model
            $ScriptBlock = {
            param($DriveNumber)
            Clear-Disk -Number $DriveNumber -RemoveData -RemoveOEM -Confirm:$false
            $Disk = Get-Disk -Number $DriveNumber
            $PartitionStyle = $Disk.PartitionStyle
            if($PartitionStyle -ne 'MBR'){
            $Disk | Set-Disk -PartitionStyle MBR
            }
            $BootPartition = New-Partition -DiskNumber $DriveNumber -Size 2GB -IsActive -AssignDriveLetter
            $DeployPartition = New-Partition -DiskNumber $DriveNumber -UseMaximumSize -AssignDriveLetter
            Format-Volume -Partition $BootPartition -FileSystem FAT32 -NewFileSystemLabel "Boot" -Confirm:$false
            Format-Volume -Partition $DeployPartition -FileSystem NTFS -NewFileSystemLabel "Deploy" -Confirm:$false
        }
        WriteLog "Start job to create BOOT and Deploy partitions on drive number $DriveNumber"
        Start-Job -ScriptBlock $ScriptBlock -ArgumentList $DriveNumber | Out-Null
    }
    writelog "Wait for partitioning jobs to complete"
    Get-Job | Wait-Job | Out-Null
    if($DrivesCount -gt 1){
    writelog "Get file system information for all drives"
    $Partitions = Get-Partition | Get-Volume
    }else{
    writelog "Get file system information for drive number $DiskNumber"
    $Partitions = Get-Partition -DiskNumber $DriveNumber | Get-Volume
    }
writelog "Get drive letter for all volumes labeled:BOOT"
$BootDrives = ($Partitions | Where-Object { $_.FileSystemLabel -eq "BOOT"}).DriveLetter
writelog "Get drive letter for all volumes labeled:Deploy"
$DeployDrives = ($Partitions | Where-Object { $_.FileSystemLabel -eq "Deploy"}).DriveLetter
writelog "Mount Deployment .iso image"
$ISOMountPoint = (Mount-DiskImage -ImagePath "$DeployISOPath" -PassThru | Get-Volume).DriveLetter + ":\"
writelog "Copying boot files to all drives labeled BOOT concurrently"
foreach ($Drive in $BootDrives) {
$Destination = $Drive + ":\"
    $jobScriptBlock = {
        param (
            [string]$SFolder,
            [string]$DFolder
        )
        Robocopy $SFolder $DFolder /E /COPYALL /R:5 /W:5 /J
    }
    WriteLog "Start job to copy all boot files to $Destination"
    Start-Job -ScriptBlock $jobScriptBlock -ArgumentList $ISOMountPoint, $Destination | Out-Null
}
if($Images){
writelog "Copying FFU image files to all drives labeled deploy concurrently"
foreach ($Drive in $DeployDrives) {
$Destination = $Drive + ":\Images"
    $jobScriptBlock = {
        param (
            [string]$SFolder,
            [string]$DFolder
        )
        New-Item -Path $DFolder -ItemType Directory -Force -Confirm: $false | Out-Null
        Robocopy $SFolder $DFolder /E /COPYALL /R:5 /W:5 /J
    }

    WriteLog "Start job to copy all FFU files to $Destination"
    Start-Job -ScriptBlock $jobScriptBlock -ArgumentList $ImagesPath, $Destination | Out-Null
    }
}
if(!($Images)){
    foreach ($Drive in $DeployDrives) {
        WriteLog "Create images directory"
        $drivepath = $Drive + ":\"
        New-Item -Path "$drivepath" -Name Images -ItemType Directory -Force -Confirm: $false | Out-Null
        }
}
if($Drivers){
writelog "Copying driver files to all drives labeled deploy concurrently"
foreach ($Drive in $DeployDrives) {
$Destination = $Drive + ":\Drivers"
    $jobScriptBlock = {
        param (
            [string]$SFolder,
            [string]$DFolder
        )
        New-Item -Path $DFolder -ItemType Directory -Force -Confirm: $false | Out-Null
        Robocopy $SFolder $DFolder /E /COPYALL /R:5 /W:5 /J
    }
    WriteLog "Start job to copy all drivers to $Destination"
    Start-Job -ScriptBlock $jobScriptBlock -ArgumentList $DriversPath, $Destination | Out-Null
}
}
if(!($Drivers)){
   foreach ($Drive in $DeployDrives) {
        WriteLog "Create drivers directory"
        $drivepath = $Drive + ":\"
        New-Item -Path "$drivepath" -Name Drivers -ItemType Directory -Force -Confirm: $false | Out-Null
        }
}
if($DrivesCount -gt 1){
Write-ProgressLog "Create Imaging Tool" "Building $DrivesCount drives concurrently...Please be patient..."
}else{
Write-ProgressLog "Create Imaging Tool" "Building the imaging tool on $model...Please be patient..."
}
Get-Job | Wait-Job | Out-Null

Dismount-DiskImage -ImagePath $DeployISOPath | Out-Null
Write-ProgressLog "Create Imaging Tool" "Drive creation jobs completed..."
}

Function New-DeploymentUSB {
    param(
        [Array]$Drives,
        [int]$Count,
        [String]$FFUPath = "$DevelopmentPath\FFU",
        [String]$DriversPath = "$DevelopmentPath\Drivers"
        
    )
  
    $Drivelist = @()
    writelog "Creating a USB drive selection list"
    for($i=0;$i -le $Count -1;$i++){
        $DriveModel = $Drives[$i].Model
        $DriveSize = [math]::round($Drives[$i].size/1GB, 2)
        $DiskNumber = $Drives[$i].DeviceID.Replace("\\.\PHYSICALDRIVE", "")
	    $Properties = [ordered]@{Number = $i + 1  ; DriveNumber = $DiskNumber ; DriveModel = $driveModel ; 'Size (GB)' = $DriveSize} 
        
        $Drivelist += New-Object PSObject -Property $Properties
        }
        if($Count -gt 1){
        $Last = $Count+1
        $Drivelist += New-Object -TypeName PSObject -Property @{ Number = "$last"; DriveModel = "Select this option to use all ($count) inserted USB Drives" }       
        }
        $Drivelist | Format-Table -AutoSize -Property Number, DriveModel , 'Size (GB)'
        do {
        try {
            $var = $true
            $DriveSelected = Read-Host 'Enter the drive number to apply the .iso to'
            $DriveSelected = ($DriveSelected -as [int]) -1
            writelog "Drive $DriveSelected selected"
            }

        catch {
            Write-Host 'Input was not in correct format. Please enter a valid FFU number'
            $var = $false
        }
    } until (($DriveSelected -le $Count -1 -or $last) -and $var)
    if($DisableAutoPlay){ 
    WriteLog "Setting the registry key to disable autoplay for all drives"
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers" -Name "DisableAutoplay" -Value 1 -Type DWORD
    }
    WriteLog "Closing all MMC windows to prevent drive lock errors"
    Stop-Process -Name mmc -ErrorAction SilentlyContinue
    WriteLog "Closing all Diskpart windows to prevent drive lock errors"
    Stop-Process -Name diskpart -ErrorAction SilentlyContinue
    $Selection = $Drivelist[$DriveSelected].Number
    $totalSteps = 5
    if($Selection -eq $last){
    Read-Host -Prompt "ALL DRIVES SELECTED! WILL ERASE ALL CURRENTLY CONNECTED USB DRIVES!! Press ENTER to continue"
    Build-DeploymentUSB -Drives $Drives
    }else{
    Read-Host -Prompt "Drive number $Selection was selected. Press ENTER to continue"
    Build-DeploymentUSB -Drives $Drives[$DriveSelected]
    }
    WriteLog "Setting the registry key to re-enable autoplay for all drives"
    if($DisableAutoPlay){
    Write-ProgressLog "Create Imaging Tool" "Enabling Autoplay"
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers" -Name "DisableAutoplay" -Value 0 -Type DWORD
    }
    Write-ProgressLog "Create Imaging Tool" "Completed!"
}    
#Get USB Drive and create log file
if(Test-Path "$DevelopmentPath\Script.log"){
Remove-Item -Path "$DevelopmentPath\Script.log" -Force -Confirm:$false
New-item -Path $DevelopmentPath -Name 'Script.log' -ItemType "file" -Force | Out-Null
}
WriteLog 'Begin Logging'
WriteLog 'Getting USB drive information and usb drive count'
$USBDrives,$USBDrivesCount = Get-RemovableDrive
WriteLog 'Setting first step for percentage progress bar'
$currentStep = 1 
New-DeploymentUSB -Drives $USBDrives -Count $USBDrivesCount

read-host -Prompt "USB drive creation complete. Press ENTER to exit"

Exit
}else{
Write-Host "No .ISO file selected..."
read-host "Press ENTER to Exit..."
Exit
}
