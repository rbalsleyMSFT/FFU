function Get-ODTURL {

    [String]$MSWebPage = Invoke-RestMethod 'https://www.microsoft.com/en-us/download/confirmation.aspx?id=49117'
  
    $MSWebPage | ForEach-Object {
      if ($_ -match 'url=(https://.*officedeploymenttool.*\.exe)') {
        $matches[1]
      }
    }
}

$FFUDevPath = 'C:\FFUDevelopment'
$ODTUrl = Get-ODTURL
$ODTInstallFile = "$env:TEMP\odtsetup.exe"
Invoke-WebRequest -Uri $ODTUrl -OutFile $ODTInstallFile

# Extract Office Deployment Tool
$ODTPath = "$FFUDevPath\Office"
Start-Process -FilePath $ODTInstallFile -ArgumentList "/extract:$ODTPath /quiet" -Wait

# Run setup.exe with config.xml
$ConfigXml = "$FFUDevPath\Office\DownloadFFU.xml"
#Set-Location $ODTPath
Start-Process -FilePath "$FFUDevPath\Office\setup.exe" -ArgumentList "/download $ConfigXml" -Wait

#Make Office ISO
Remove-Item -Path "$ODTPath\configuration*" -Force
$OSCDIMG = 'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe'
$OfficeISO = "$FFUDevPath\office.iso"
Start-Process -FilePath $OSCDIMG -ArgumentList "-n -m $ODTPath $OfficeISO" -wait

#Mount Office ISO to FFU VM
$VMS = get-vm _ffu-* | Where-Object {$_.state -eq 'running'}

foreach ($VM in $VMs) {
    # Check if DVD drive exists
    $DVD = Get-VMDvdDrive -VMName $VM.Name
    if ($DVD) {
        # Attach ISO to existing DVD drive
        Set-VMDvdDrive -VMName $VM.Name -Path $OfficeISO
    }
    else {
        # Add DVD drive and attach ISO
        Add-VMDvdDrive -VMName $VM.Name -Path $OfficeISO
    }
}

#Remove the Office Download and ODT
$OfficeDownloadPath = "$FFUDevPath\Office\Office"
Remove-Item -Path $OfficeDownloadPath -Recurse -Force
Remove-Item -Path "$ODTPath\setup.exe"

