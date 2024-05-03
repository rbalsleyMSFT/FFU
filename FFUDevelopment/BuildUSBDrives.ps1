# will partition and format a USB drive and copy the captured FFU to the drive. If you'd like to customize the drive to add drivers, provisioning packages, name prefix, etc. You'll need to do that afterward.

Add-Type -AssemblyName System.Windows.Forms
$FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{ 
InitialDirectory = "C:"
Filter = 'ISO (*.ISO)|'
Title = 'Select an ISO file'
 }
$null = $FileBrowser.ShowDialog()

$DeployISOPath = $FileBrowser.FileName
function WriteLog($LogText) { 
$LogFileName = '\ScriptLog.txt'
$LogFile = $PSScriptRoot + $LogFilename
    Add-Content -path $LogFile -value "$((Get-Date).ToString()) $LogText" -Force -ErrorAction SilentlyContinue
    Write-Verbose $LogText
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
Function New-DeploymentUSB {
    param(
        [switch]$CopyFFU,
        [String]$DeployISO,
        [Array]$USBDrives
    )
    WriteLog "CopyFFU is set to $CopyFFU"
    $BuildUSBPath = $PSScriptRoot
    WriteLog "BuildUSBPath is $BuildUSBPath"

    $SelectedFFUFile = $null

    if ($CopyFFU.IsPresent) {
        $FFUFiles = Get-ChildItem -Path "C:\FFUDevelopment\FFU" -Filter "*.ffu"

        if ($FFUFiles.Count -eq 1) {
            $SelectedFFUFile = $FFUFiles.FullName
        }
        elseif ($FFUFiles.Count -gt 1) {
            WriteLog 'Found multiple FFU files'
            for ($i = 0; $i -lt $FFUFiles.Count; $i++) {
           #     WriteLog ("{0}: {1}" -f ($i + 1), $FFUFiles[$i].Name)
            }
            $inputChoice = Read-Host "Enter the number corresponding to the FFU file you want to copy or 'A' to copy all FFU files"
            
            if ($inputChoice -eq 'A') {
                $SelectedFFUFile = $FFUFiles.FullName
            }
            elseif ($inputChoice -ge 1 -and $inputChoice -le $FFUFiles.Count) {
                $selectedIndex = $inputChoice - 1
                $SelectedFFUFile = $FFUFiles[$selectedIndex].FullName
            }
            WriteLog "$SelectedFFUFile was selected"
        }
        else {
            WriteLog "No FFU files found in the current directory."
            Write-Error "No FFU files found in the current directory."
            Return
        }
    }
    $counter = 0

    foreach ($USBDrive in $USBDrives) {
        $Counter++
        WriteLog "Formatting USB drive $Counter out of $USBDrivesCount"
        $DiskNumber = $USBDrive.DeviceID.Replace("\\.\PHYSICALDRIVE", "")
        WriteLog "Physical Disk number is $DiskNumber for USB drive $Counter out of $USBDrivesCount"

        $ScriptBlock = {
            param($DiskNumber)
            Clear-Disk -Number $DiskNumber -RemoveData -RemoveOEM -Confirm:$false
            Get-Disk $DiskNumber | Get-Partition | Remove-Partition
            $Disk = Get-Disk -Number $DiskNumber
            $Disk | Set-Disk -PartitionStyle MBR
            $BootPartition = $Disk | New-Partition -Size 2GB -IsActive -AssignDriveLetter 
            $DeployPartition = $Disk | New-Partition -UseMaximumSize -AssignDriveLetter
            Format-Volume -Partition $BootPartition -FileSystem FAT32 -NewFileSystemLabel "Boot" -Confirm:$false
            Format-Volume -Partition $DeployPartition -FileSystem NTFS -NewFileSystemLabel "Deploy" -Confirm:$false
        }

        WriteLog 'Partitioning USB Drive'
        Invoke-Command -ScriptBlock $ScriptBlock -ArgumentList $DiskNumber | Out-null
        WriteLog 'Done'


        $BootPartitionDriveLetter = (Get-WmiObject -Class win32_volume -Filter "Label='Boot' AND DriveType=2 AND DriveLetter IS NOT NULL").Name
        $ISOMountPoint = (Mount-DiskImage -ImagePath $DeployISO -PassThru | Get-Volume).DriveLetter + ":\"
        WriteLog "Copying WinPE files to $BootPartitionDriveLetter"
        robocopy "$ISOMountPoint" "$BootPartitionDriveLetter" /E /COPYALL /R:5 /W:5 /J
        Dismount-DiskImage -ImagePath $DeployISO | Out-Null
        $DeployPartitionDriveLetter = (Get-WmiObject -Class win32_volume -Filter "Label='Deploy' AND DriveType=2 AND DriveLetter IS NOT NULL").Name
        WriteLog "Create images directory"
        New-Item -Path $DeployPartitionDriveLetter -Name Images -ItemType Directory -Force -Confirm: $false
        WriteLog "Make drivers directory"
        New-Item -Path $DeployPartitionDriveLetter -Name Drivers -ItemType Directory -Force -Confirm: $false

        if ($CopyFFU.IsPresent) {
            if ($null -ne $SelectedFFUFile) {
               # $DeployPartitionDriveLetter = (Get-WmiObject -Class win32_volume -Filter "Label='TempDeploy' AND DriveType=2 AND DriveLetter IS NOT NULL").Name
                if ($SelectedFFUFile -is [array]) {
                    WriteLog "Copying multiple FFU files to $DeployPartitionDriveLetter. This could take a few minutes."
                    foreach ($FFUFile in $SelectedFFUFile) {
                        robocopy $(Split-Path $FFUFile -Parent) "$DeployPartitionDriveLetter\Images" $(Split-Path $FFUFile -Leaf) /COPYALL /R:5 /W:5 /J
                    }
                }
                else {
                    WriteLog ("Copying " + $SelectedFFUFile + " to $DeployPartitionDriveLetter. This could take a few minutes.")
                    robocopy $(Split-Path $SelectedFFUFile -Parent) "$DeployPartitionDriveLetter\Images" $(Split-Path $SelectedFFUFile -Leaf) /COPYALL /R:5 /W:5 /J
                }
                #Copy drivers using robocopy due to potential size
                if ($CopyDrivers) {
                    WriteLog "Copying drivers to $DeployPartitionDriveLetter\Drivers"
                    robocopy "$FFUDevelopmentPath\Drivers" "$DeployPartitionDriveLetter\Drivers" /E /R:5 /W:5 /J
                }
                #Copy Unattend folder in the FFU folder to the USB drive. Can use copy-item as it's a small folder
                if ($CopyUnattend) {
                 #   WriteLog "Copying Unattend folder to $DeployPartitionDriveLetter"
                    Copy-Item -Path "$FFUDevelopmentPath\Unattend" -Destination $DeployPartitionDriveLetter -Recurse -Force
                }  
                #Copy PPKG folder in the FFU folder to the USB drive. Can use copy-item as it's a small folder
                if ($CopyPPKG) {
                  #  WriteLog "Copying PPKG folder to $DeployPartitionDriveLetter"
                    Copy-Item -Path "$FFUDevelopmentPath\PPKG" -Destination $DeployPartitionDriveLetter -Recurse -Force
                }
                #Copy Autopilot folder in the FFU folder to the USB drive. Can use copy-item as it's a small folder
                if ($CopyAutopilot) {
                 #   WriteLog "Copying Autopilot folder to $DeployPartitionDriveLetter"
                    Copy-Item -Path "$FFUDevelopmentPath\Autopilot" -Destination $DeployPartitionDriveLetter -Recurse -Force
                }
            }
            else {
                WriteLog "No FFU file selected. Skipping copy."
            }
        }

       # Set-Volume -FileSystemLabel "TempBoot" -NewFileSystemLabel "Boot"
     #   Set-Volume -FileSystemLabel "TempDeploy" -NewFileSystemLabel "Deploy"

        if ($USBDrivesCount -gt 1) {
            & mountvol $BootPartitionDriveLetter /D
            & mountvol $DeployPartitionDriveLetter /D 
        }

        WriteLog "Drive $counter completed"
    }

    WriteLog "USB Drives completed"
}
#Get USB Drive and create log file
$USBDrive = Get-USBDrive
New-item -Path $PSScriptRoot -Name 'ScriptLog.txt' -ItemType "file" -Force | Out-Null
WriteLog 'Begin Logging'
Write-Host "WILL ERASE ALL CURRENTLY CONNECTED USB DRIVES" -ForegroundColor Red
Pause
$USBDrives, $USBDrivesCount = Get-USBDrive

New-DeploymentUSB -CopyFFU -DeployISO $DeployISOPath -USBDrives $USBDrives
