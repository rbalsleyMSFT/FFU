$Host.UI.RawUI.WindowTitle = 'Full Flash Update Imaging Tool USB Creator | 2024.6'
# will partition and format a USB drive and copy the captured FFU to the drive. If you'd like to customize the drive to add drivers, provisioning packages, name prefix, etc. You'll need to do that afterward.
Add-Type -AssemblyName System.Windows.Forms
$FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{ 
InitialDirectory = "C:"
Filter = 'ISO (*.ISO)|'
Title = 'Select an ISO file'
 }
$null = $FileBrowser.ShowDialog()
$DeployISOPath = $FileBrowser.FileName
$DevelopmentPath = $DeployISOPath | Split-Path

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
        #return $currentStep
        #$counter++
        #return $counter
    }

Function Get-USBDrive {
    $USBDrives = (Get-WmiObject -Class Win32_DiskDrive -Filter "MediaType='Removable Media'") 
    If ($USBDrives -and ($null -eq $USBDrives.count)) {
        $USBDrivesCount = 1
    }
    else {
        $USBDrivesCount = $USBDrives.Count
    }
    WriteLog "Found $USBDrivesCount USB drives"

    if ($null -eq $USBDrives) {
        WriteLog "No removable USB drive found. Exiting"
        Write-Error "No removable USB drive found. Exiting"
        exit 1
    }
    return $USBDrives, $USBDrivesCount
}

Function Partition-DeploymentUSB{
      param(
            [Array]$Drives,
            [string]$DrivesCount
            )
                
 foreach ($USBDrive in $Drives) {
        $DiskNumber = $USBDrive.DeviceID.Replace("\\.\PHYSICALDRIVE", "")
        $Model = $USBDrive.model
        $ScriptBlock = {
            param($DiskNumber)
            Clear-Disk -Number $DiskNumber -RemoveData -RemoveOEM -Confirm:$false
            Get-Disk $DiskNumber | Get-Partition | Remove-Partition
            $Disk = Get-Disk -Number $DiskNumber
            $Disk | Set-Disk -PartitionStyle MBR
            $BootPartition = $Disk | New-Partition -Size 2GB -IsActive -AssignDriveLetter
            $DeployPartition = $Disk | New-Partition -UseMaximumSize -AssignDriveLetter
            Format-Volume -Partition $BootPartition -FileSystem FAT32 -NewFileSystemLabel "TempBoot" -Confirm:$false
            Format-Volume -Partition $DeployPartition -FileSystem NTFS -NewFileSystemLabel "TempDeploy" -Confirm:$false
        }
        Write-ProgressLog "Create Imaging Tool" "Partitioning $Model"
        WriteLog 'Partitioning USB Drive'
        Invoke-Command -ScriptBlock $ScriptBlock -ArgumentList $DiskNumber | Out-null
        WriteLog 'Done'
        Write-ProgressLog "Create Imaging Tool" "Completed partitioning $Model"
        $BootPartitionDriveLetter = (Get-WmiObject -Class win32_volume -Filter "Label='TempBoot' AND DriveType=2 AND DriveLetter IS NOT NULL").Name
        $ISOMountPoint = (Mount-DiskImage -ImagePath $DeployISO -PassThru | Get-Volume).DriveLetter + ":\"
        WriteLog "Copying WinPE files to $BootPartitionDriveLetter"
        Write-ProgressLog "Create Imaging Tool" "Copying boot files to $Model"
        robocopy "$ISOMountPoint" "$BootPartitionDriveLetter" /E /COPYALL /R:5 /W:5 /J /NFL /NDL /NJH /NJS /nc /ns /secfix /ETA | Out-Null
        Write-ProgressLog "Create Imaging Tool" "Copying boot files completed"
        Dismount-DiskImage -ImagePath $DeployISO | Out-Null
        $DeployPartitionDriveLetter = (Get-WmiObject -Class win32_volume -Filter "Label='TempDeploy' AND DriveType=2 AND DriveLetter IS NOT NULL").Name
        WriteLog "Create images directory"
        New-Item -Path $DeployPartitionDriveLetter -Name Images -ItemType Directory -Force -Confirm: $false | Out-Null
        WriteLog "Make drivers directory"
        New-Item -Path $DeployPartitionDriveLetter -Name Drivers -ItemType Directory -Force -Confirm: $false | Out-Null
        Write-ProgressLog "Create Imaging Tool" "Creating Images and Driver folders"
        if($Images){
            $Imagescount = $Images.count
            if($Imagescount  -gt 1){
            Write-ProgressLog "Create Imaging Tool" "Copying images to $Model"
            robocopy "$FFUPath" "$DeployPartitionDriveLetter\Images" /E /COPYALL /R:5 /W:5 /J /NFL /NDL /NJH /NJS /nc /ns /secfix /ETA | Out-Null
            Write-ProgressLog "Create Imaging Tool" "Completed copying images to $Model"
            }
            if($Imagescount  -eq 1){
            $imageName = $Images.Name
            Write-ProgressLog "Create Imaging Tool" "Copying $imageName to $Model"
            robocopy "$FFUPath" "$DeployPartitionDriveLetter\Images" /E /COPYALL /R:5 /W:5 /J /NFL /NDL /NJH /NJS /nc /ns /secfix /ETA | Out-Null
            Write-ProgressLog "Create Imaging Tool" "Completed copying $imageName to $Model"
            }
        }
        if($Drivers){
        Write-ProgressLog "Create Imaging Tool" "Copying drivers to $Model"
        robocopy "$DriversPath" "$DeployPartitionDriveLetter\Drivers" /E /COPYALL /R:5 /W:5 /J /NFL /NDL /NJH /NJS /nc /ns /secfix /ETA | Out-Null
        Write-ProgressLog "Create Imaging Tool" "Completed copying drivers to $Model"
        }

         Set-Volume -FileSystemLabel "TempBoot" -NewFileSystemLabel "Boot"
         Set-Volume -FileSystemLabel "TempDeploy" -NewFileSystemLabel "Deploy"
     
    }


}

Function New-DeploymentUSB {
    param(
        [String]$FFUDevelopmentPath = $DevelopmentPath ,
        [String]$DeployISO,
        [Array]$Drives,
        [int]$Count,
        [String]$FFUPath = "$FFUDevelopmentPath\FFU",
        [String]$DriversPath = "$FFUDevelopmentPath\Drivers"
    )
    
    $Images = Get-ChildItem -Path $FFUPath -Filter "*.ffu" -File -Recurse
    $Drivers = Get-ChildItem -Path $DriversPath -Recurse
    $SelectedFFUFile = $null
    $Drivelist = @()
    writelog "Creating list of USB drives"
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
            writelog "drive $DriveSelected selected"
            }

        catch {
            Write-Host 'Input was not in correct format. Please enter a valid FFU number'
            $var = $false
        }
    } until (($DriveSelected -le $Count -1 -or $last) -and $var) 
    #Autoplay setting
    WriteLog "Disabling autoplay for all drives"
    # Set the registry key to disable autoplay for all drives
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers" -Name "DisableAutoplay" -Value 1 -Type DWORD
    WriteLog "Closing all MMC windows to prevent drive lock errors"
    Stop-Process -Name mmc -ErrorAction SilentlyContinue
    WriteLog "Closing all Diskpart windows to prevent drive lock errors"
    Stop-Process -Name diskpart -ErrorAction SilentlyContinue
    $Selection = $Drivelist[$DriveSelected].Number
    
    if($Selection -eq $last){
    $totalSteps = (($Count * 9)+3)
    Read-Host -Prompt "ALL DRIVES SELECTED! WILL ERASE ALL CURRENTLY CONNECTED USB DRIVES!! Press ENTER to continue"
    Write-ProgressLog "Create Imaging Tool" "Partitioning USB Drives..." 
    Partition-DeploymentUSB -Drives $Drives -DrivesCount $Count
    }else{
    $totalSteps = (9+3)
    Read-Host -Prompt "Drive number $Selection was selected. Press ENTER to continue"
    Write-ProgressLog "Create Imaging Tool" "Partitioning $DriveModel"
    Partition-DeploymentUSB -Drives $Drives[$DriveSelected] -DrivesCount $Count 
    }
    #autoplay setting
    WriteLog "Disabling autoplay for all drives"
    #Set the registry key to enable autoplay for all drives
    Write-ProgressLog "Create Imaging Tool" "Enabling Autoplay"
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers" -Name "DisableAutoplay" -Value 0 -Type DWORD
    Write-ProgressLog "Create Imaging Tool" "Completed!"
         
 }   
   
#Get USB Drive and create log file
if(Test-Path "$DevelopmentPath\Script.log"){
Remove-Item -Path "$DevelopmentPath\Script.log" -Force -Confirm:$false
New-item -Path $DevelopmentPath -Name 'Script.log' -ItemType "file" -Force | Out-Null
}
WriteLog 'Begin Logging'
$usbDrives, $USBDrivesCount = Get-USBDrive
$currentStep = 1 

New-DeploymentUSB -DeployISO $DeployISOPath -Drives $USBDrives -Count $USBDrivesCount -FFUDevelopmentPath $DevelopmentPath
read-host -Prompt "USB drive creation complete. Press ENTER to exit"
Exit
