# Run disk cleanup (cleanmgr.exe) with all options enabled
# Reference: https://learn.microsoft.com/en-us/troubleshoot/windows-server/backup-and-storage/automating-disk-cleanup-tool

$rootKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"

# Set StateFlags0000 to 2 for all subkeys except "Offline Pages Files"
Get-ChildItem -Path $rootKey | ForEach-Object {
    if ($_.PSChildName -ne "Offline Pages Files") {
        Set-ItemProperty -Path $_.PSPath -Name "StateFlags0000" -Type DWord -Value 2 -Force
    }
}

# Run the disk cleanup tool with the specified flags
Start-Process -FilePath "cleanmgr.exe" -ArgumentList "/sagerun:0" -Wait

# Remove the StateFlags0000 registry values that were added
Get-ChildItem -Path $rootKey | ForEach-Object {
    if ($_.PSChildName -ne "Offline Pages Files") {
        Remove-ItemProperty -Path $_.PSPath -Name "StateFlags0000" -Force
    }
}