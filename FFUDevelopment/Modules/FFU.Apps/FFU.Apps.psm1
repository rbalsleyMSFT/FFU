<#
.SYNOPSIS
    FFU Builder Application Management Module

.DESCRIPTION
    Application installation and management for FFU Builder.
    Handles Office Deployment Tool, application ISO creation, and
    provisioned app removal (bloatware cleanup).

.NOTES
    Module: FFU.Apps
    Version: 1.0.0
    Dependencies: FFU.Core
#>

#Requires -Version 5.1

# Import dependencies
$modulePath = Split-Path -Parent $PSScriptRoot
Import-Module "$modulePath\FFU.Core" -Force

function Get-ODTURL {
    try {
        [String]$ODTPage = Invoke-WebRequest 'https://www.microsoft.com/en-us/download/details.aspx?id=49117' -Headers $Headers -UserAgent $UserAgent -ErrorAction Stop

        # Extract JSON data from the webpage
        if ($ODTPage -match '<script>window\.__DLCDetails__=(.*?)<\/script>') {
            # Parse JSON content
            $jsonContent = $matches[1] | ConvertFrom-Json
            $ODTURL = $jsonContent.dlcDetailsView.downloadFile[0].url

            if ($ODTURL) {
                return $ODTURL
            }
            else {
                WriteLog 'Cannot find the ODT download URL in the JSON content'
                throw 'Cannot find the ODT download URL in the JSON content'
            }
        }
        else {
            WriteLog 'Failed to extract JSON content from the ODT webpage'
            throw 'Failed to extract JSON content from the ODT webpage'
        }
    }
    catch {
        WriteLog $_.Exception.Message
        throw 'An error occurred while retrieving the ODT URL.'
    }
}

function Get-Office {
    # If a custom Office Config XML is provided via config file, use its filename for the installation.
    # The UI script is responsible for copying the file itself to the OfficePath.
    if ((Get-Variable -Name 'OfficeConfigXMLFile' -ErrorAction SilentlyContinue) -and -not([string]::IsNullOrEmpty($OfficeConfigXMLFile))) {
        $script:OfficeInstallXML = Split-Path -Path $OfficeConfigXMLFile -Leaf
        WriteLog "A custom Office configuration file was specified. Using '$($script:OfficeInstallXML)' for installation."
    }
    #Download ODT
    $ODTUrl = Get-ODTURL
    $ODTInstallFile = "$OfficePath\odtsetup.exe"
    WriteLog "Downloading Office Deployment Toolkit from $ODTUrl to $ODTInstallFile"
    $OriginalVerbosePreference = $VerbosePreference
    $VerbosePreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $ODTUrl -OutFile $ODTInstallFile -Headers $Headers -UserAgent $UserAgent
    $VerbosePreference = $OriginalVerbosePreference

    # Extract ODT
    WriteLog "Extracting ODT to $OfficePath"
    Invoke-Process $ODTInstallFile "/extract:$OfficePath /quiet" | Out-Null

    # Run setup.exe with config.xml and modify xml file to download to $OfficePath
    $xmlContent = [xml](Get-Content $OfficeDownloadXML)
    $xmlContent.Configuration.Add.SourcePath = $OfficePath
    $xmlContent.Save($OfficeDownloadXML)
    Mark-DownloadInProgress -FFUDevelopmentPath $FFUDevelopmentPath -TargetPath $OfficePath
    WriteLog "Downloading M365 Apps/Office to $OfficePath"
    Invoke-Process $OfficePath\setup.exe "/download $OfficeDownloadXML" | Out-Null
    Clear-DownloadInProgress -FFUDevelopmentPath $FFUDevelopmentPath -TargetPath $OfficePath

    WriteLog "Cleaning up ODT default config files"
    #Clean up default configuration files
    Remove-Item -Path "$OfficePath\configuration*" -Force

    #Create Install-Office.ps1 in $orchestrationpath
    WriteLog "Creating $orchestrationpath\Install-Office.ps1"
    $installOfficePath = Join-Path -Path $orchestrationpath -ChildPath "Install-Office.ps1"
    # Create the Install-Office.ps1 file
    $installOfficeCommand = "& d:\Office\setup.exe /configure d:\office\$OfficeInstallXML"
    Set-Content -Path $installOfficePath -Value $installOfficeCommand -Force
    WriteLog "Install-Office.ps1 created successfully at $installOfficePath"

    #Remove the ODT setup file
    WriteLog "Removing ODT setup file"
    Remove-Item -Path $ODTInstallFile -Force
    WriteLog "ODT setup file removed"
}

function New-AppsISO {
    <#
    .SYNOPSIS
    Creates an ISO file from the Apps folder for deployment

    .DESCRIPTION
    Uses oscdimg.exe from Windows ADK to create a bootable ISO containing
    applications from the Apps folder. The ISO can be mounted in VMs for
    application installation during FFU build.

    .PARAMETER ADKPath
    Path to Windows ADK installation (e.g., "C:\Program Files (x86)\Windows Kits\10\")

    .PARAMETER AppsPath
    Path to the Apps folder containing application files

    .PARAMETER AppsISO
    Output path for the ISO file

    .EXAMPLE
    New-AppsISO -ADKPath $adkPath -AppsPath "C:\FFUDevelopment\Apps" -AppsISO "C:\FFUDevelopment\Apps.iso"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ADKPath,

        [Parameter(Mandatory = $true)]
        [string]$AppsPath,

        [Parameter(Mandatory = $true)]
        [string]$AppsISO
    )

    # Construct path to oscdimg.exe in ADK
    $OSCDIMG = Join-Path $ADKPath "Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"

    if (-not (Test-Path $OSCDIMG)) {
        throw "oscdimg.exe not found at: $OSCDIMG. Ensure Windows ADK Deployment Tools are installed."
    }

    # Adding Long Path support for AppsPath to prevent issues with oscdimg
    $AppsPathLong = '\\?\' + $AppsPath

    WriteLog "Creating ISO from $AppsPath to $AppsISO"
    WriteLog "Using oscdimg: $OSCDIMG"

    Invoke-Process $OSCDIMG "-n -m -d $AppsPathLong $AppsISO" | Out-Null
}

function Remove-Apps {

    # Check if the file exists before attempting to clear it
    if (Test-Path -Path $wingetWin32jsonFile) {
        WriteLog "Removing $wingetWin32jsonFile"
        Remove-Item -Path $wingetWin32jsonFile -Force -ErrorAction SilentlyContinue
        WriteLog 'Removal complete'
    }
    # Clean up Win32 and MSStore folders
    if (Test-Path -Path "$AppsPath\Win32" -PathType Container) {
        WriteLog "Cleaning up Win32 folder"
        Remove-Item -Path "$AppsPath\Win32" -Recurse -Force
    }
    if (Test-Path -Path "$AppsPath\MSStore" -PathType Container) {
        WriteLog "Cleaning up MSStore folder"
        Remove-Item -Path "$AppsPath\MSStore" -Recurse -Force
    }

    #Remove the Office Download and ODT
    if ($InstallOffice) {
        $ODTPath = "$AppsPath\Office"
        $OfficeDownloadPath = "$ODTPath\Office"
        WriteLog 'Removing Office and ODT download'
        Remove-Item -Path $OfficeDownloadPath -Recurse -Force
        Remove-Item -Path "$ODTPath\setup.exe"
        Remove-Item -Path "$orchestrationPath\Install-Office.ps1"
        WriteLog 'Removal complete'
    }

    #Remove AppsISO
    if ($CleanupAppsISO) {
        WriteLog "Removing $AppsISO"
        Remove-Item -Path $AppsISO -Force -ErrorAction SilentlyContinue
        WriteLog 'Removal complete'
    }
}

function Remove-DisabledArtifacts {
    <#
    .SYNOPSIS
    Removes artifacts for features disabled via command-line flags

    .DESCRIPTION
    Cleans up downloaded artifacts (Office, Defender, MSRT, OneDrive, Edge) when
    the corresponding install/update flags are disabled. Prevents unnecessary
    artifacts from being included in the final FFU image.

    .EXAMPLE
    Remove-DisabledArtifacts
    #>
    [CmdletBinding()]
    param()

    # Remove Office artifacts if Install Office is disabled
    if (-not $InstallOffice) {
        $removed = $false
        if (Test-Path -Path $installOfficePath) {
            WriteLog "Install Office disabled - removing $installOfficePath"
            Remove-Item -Path $installOfficePath -Force -ErrorAction SilentlyContinue
            $removed = $true
        }
        if (Test-Path -Path $OfficePath) {
            WriteLog 'Removing Office and ODT download'
            $OfficeDownloadPath = "$OfficePath\Office"
            Remove-Item -Path $OfficeDownloadPath -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path "$OfficePath\setup.exe" -Recurse -Force -ErrorAction SilentlyContinue
            $removed = $true
        }
        if ($removed) { WriteLog 'Removal complete' }
    }


    # Remove Defender artifacts if Defender update is disabled
    if (-not $UpdateLatestDefender) {
        $removed = $false
        if (Test-Path -Path $installDefenderPath) {
            WriteLog "Update Defender disabled - removing $installDefenderPath"
            Remove-Item -Path $installDefenderPath -Force -ErrorAction SilentlyContinue
            $removed = $true
        }
        if (Test-Path -Path $DefenderPath) {
            WriteLog "Update Defender disabled - removing $DefenderPath"
            Remove-Item -Path $DefenderPath -Recurse -Force -ErrorAction SilentlyContinue
            $removed = $true
        }
        if ($removed) { WriteLog 'Removal complete' }
    }

    # Remove MSRT artifacts if MSRT update is disabled
    if (-not $UpdateLatestMSRT) {
        $removed = $false
        if (Test-Path -Path $installMSRTPath) {
            WriteLog "Update MSRT disabled - removing $installMSRTPath"
            Remove-Item -Path $installMSRTPath -Force -ErrorAction SilentlyContinue
            $removed = $true
        }
        if (Test-Path -Path $MSRTPath) {
            WriteLog "Update MSRT disabled - removing $MSRTPath"
            Remove-Item -Path $MSRTPath -Recurse -Force -ErrorAction SilentlyContinue
            $removed = $true
        }
        if ($removed) { WriteLog 'Removal complete' }
    }

    # Remove OneDrive artifacts if OneDrive update is disabled
    if (-not $UpdateOneDrive) {
        $removed = $false
        if (Test-Path -Path $installODPath) {
            WriteLog "Update OneDrive disabled - removing $installODPath"
            Remove-Item -Path $installODPath -Force -ErrorAction SilentlyContinue
            $removed = $true
        }
        if (Test-Path -Path $OneDrivePath) {
            WriteLog "Update OneDrive disabled - removing $OneDrivePath"
            Remove-Item -Path $OneDrivePath -Recurse -Force -ErrorAction SilentlyContinue
            $removed = $true
        }
        if ($removed) { WriteLog 'Removal complete' }
    }

    # Remove Edge artifacts if Edge update is disabled
    if (-not $UpdateEdge) {
        $removed = $false
        if (Test-Path -Path $installEdgePath) {
            WriteLog "Update Edge disabled - removing $installEdgePath"
            Remove-Item -Path $installEdgePath -Force -ErrorAction SilentlyContinue
            $removed = $true
        }
        if (Test-Path -Path $EdgePath) {
            WriteLog "Update Edge disabled - removing $EdgePath"
            Remove-Item -Path $EdgePath -Recurse -Force -ErrorAction SilentlyContinue
            $removed = $true
        }
        if ($removed) { WriteLog 'Removal complete' }
    }
}

# Export module members
Export-ModuleMember -Function @(
    'Get-ODTURL',
    'Get-Office',
    'New-AppsISO',
    'Remove-Apps',
    'Remove-DisabledArtifacts'
)