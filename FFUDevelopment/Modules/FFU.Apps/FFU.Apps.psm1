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

#Requires -Version 7.0

# Import dependencies
$modulePath = Split-Path -Parent $PSScriptRoot
Import-Module "$modulePath\FFU.Core" -Force

function Get-ODTURL {
    <#
    .SYNOPSIS
    Retrieves the download URL for the Microsoft Office Deployment Tool (ODT)

    .DESCRIPTION
    Scrapes the Microsoft download page to extract the current ODT download URL
    from embedded JSON data. Returns the direct download link for officedeploymenttool.exe.

    .PARAMETER Headers
    HTTP headers hashtable for web requests (includes session cookies and metadata)

    .PARAMETER UserAgent
    User agent string to identify the client making the request

    .EXAMPLE
    $url = Get-ODTURL -Headers $headers -UserAgent $userAgent

    .OUTPUTS
    System.String - Direct download URL for the Office Deployment Tool executable
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,

        [Parameter(Mandatory = $true)]
        [string]$UserAgent
    )
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
    <#
    .SYNOPSIS
    Downloads and configures Microsoft 365 Apps (Office) for FFU deployment

    .DESCRIPTION
    Downloads Office Deployment Tool (ODT), extracts it, configures download settings,
    downloads Office files, and creates installation script for VM orchestration.

    .PARAMETER OfficePath
    Destination folder for Office files (e.g., "C:\FFUDevelopment\Apps\Office")

    .PARAMETER OfficeDownloadXML
    Path to XML configuration file for Office download

    .PARAMETER OfficeInstallXML
    Name of XML configuration file for Office installation (default: "DeployFFU.xml")

    .PARAMETER OrchestrationPath
    Path to orchestration folder where Install-Office.ps1 will be created

    .PARAMETER FFUDevelopmentPath
    Root FFUDevelopment path for download progress tracking

    .PARAMETER Headers
    HTTP headers hashtable for web requests

    .PARAMETER UserAgent
    User agent string for web requests

    .PARAMETER OfficeConfigXMLFile
    Optional custom Office configuration XML file path

    .EXAMPLE
    Get-Office -OfficePath "C:\FFU\Apps\Office" -OfficeDownloadXML "C:\FFU\Apps\Office\Download.xml" `
               -OrchestrationPath "C:\FFU\Apps\Orchestration" -FFUDevelopmentPath "C:\FFU" `
               -Headers @{} -UserAgent "Mozilla/5.0"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OfficePath,

        [Parameter(Mandatory = $true)]
        [string]$OfficeDownloadXML,

        [Parameter(Mandatory = $false)]
        [string]$OfficeInstallXML = "DeployFFU.xml",

        [Parameter(Mandatory = $true)]
        [string]$OrchestrationPath,

        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath,

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,

        [Parameter(Mandatory = $true)]
        [string]$UserAgent,

        [Parameter(Mandatory = $false)]
        [string]$OfficeConfigXMLFile
    )

    # If a custom Office Config XML is provided, use its filename for installation
    if (-not [string]::IsNullOrEmpty($OfficeConfigXMLFile)) {
        $OfficeInstallXML = Split-Path -Path $OfficeConfigXMLFile -Leaf
        WriteLog "A custom Office configuration file was specified. Using '$OfficeInstallXML' for installation."
    }

    # Ensure Office directory exists
    if (-not (Test-Path $OfficePath)) {
        WriteLog "Creating Office directory: $OfficePath"
        New-Item -Path $OfficePath -ItemType Directory -Force | Out-Null
    }

    # Download ODT with proper error handling
    $ODTUrl = Get-ODTURL -Headers $Headers -UserAgent $UserAgent
    $ODTInstallFile = Join-Path $OfficePath "odtsetup.exe"
    WriteLog "Downloading Office Deployment Toolkit from $ODTUrl to $ODTInstallFile"

    try {
        $OriginalVerbosePreference = $VerbosePreference
        $VerbosePreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $ODTUrl -OutFile $ODTInstallFile -Headers $Headers -UserAgent $UserAgent -ErrorAction Stop
        $VerbosePreference = $OriginalVerbosePreference

        # Validate download succeeded
        if (-not (Test-Path $ODTInstallFile)) {
            throw "ODT download appeared to succeed but file not found at: $ODTInstallFile"
        }
        $odtFileInfo = Get-Item $ODTInstallFile
        if ($odtFileInfo.Length -eq 0) {
            throw "ODT download resulted in empty file: $ODTInstallFile"
        }
        WriteLog "ODT downloaded successfully ($($odtFileInfo.Length) bytes)"
    }
    catch {
        throw "Failed to download Office Deployment Toolkit from $ODTUrl : $($_.Exception.Message)"
    }

    # Extract ODT
    WriteLog "Extracting ODT to $OfficePath"
    Invoke-Process $ODTInstallFile "/extract:$OfficePath /quiet" | Out-Null

    # Run setup.exe with config.xml and modify xml file to download to $OfficePath
    $xmlContent = [xml](Get-Content $OfficeDownloadXML)
    $xmlContent.Configuration.Add.SourcePath = $OfficePath
    $xmlContent.Save($OfficeDownloadXML)
    Set-DownloadInProgress -FFUDevelopmentPath $FFUDevelopmentPath -TargetPath $OfficePath
    WriteLog "Downloading M365 Apps/Office to $OfficePath"
    $setupExe = Join-Path $OfficePath "setup.exe"
    Invoke-Process $setupExe "/download $OfficeDownloadXML" | Out-Null
    Clear-DownloadInProgress -FFUDevelopmentPath $FFUDevelopmentPath -TargetPath $OfficePath

    WriteLog "Cleaning up ODT default config files"
    # Clean up default configuration files - use ErrorAction to prevent non-terminating errors
    Remove-Item -Path "$OfficePath\configuration*" -Force -ErrorAction SilentlyContinue

    # Create Install-Office.ps1 in orchestration folder
    $installOfficePath = Join-Path -Path $OrchestrationPath -ChildPath "Install-Office.ps1"
    WriteLog "Creating $installOfficePath"

    # Create the Install-Office.ps1 file
    $installOfficeCommand = "& d:\Office\setup.exe /configure d:\office\$OfficeInstallXML"
    Set-Content -Path $installOfficePath -Value $installOfficeCommand -Force
    WriteLog "Install-Office.ps1 created successfully at $installOfficePath"

    # Remove the ODT setup file
    WriteLog "Removing ODT setup file"
    if (-not [string]::IsNullOrWhiteSpace($ODTInstallFile)) {
        Remove-Item -Path $ODTInstallFile -Force -ErrorAction SilentlyContinue
    }
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
    New-AppsISO -ADKPath $adkPath -AppsPath "C:\FFUDevelopment\Apps" -AppsISO "C:\FFUDevelopment\Apps\Apps.iso"
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
        Remove-Item -Path "$AppsPath\Win32" -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -Path "$AppsPath\MSStore" -PathType Container) {
        WriteLog "Cleaning up MSStore folder"
        Remove-Item -Path "$AppsPath\MSStore" -Recurse -Force -ErrorAction SilentlyContinue
    }

    #Remove the Office Download and ODT
    if ($InstallOffice) {
        $ODTPath = "$AppsPath\Office"
        $OfficeDownloadPath = "$ODTPath\Office"
        WriteLog 'Removing Office and ODT download'
        if (-not [string]::IsNullOrWhiteSpace($OfficeDownloadPath)) {
            Remove-Item -Path $OfficeDownloadPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -Path "$ODTPath\setup.exe" -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$orchestrationPath\Install-Office.ps1" -Force -ErrorAction SilentlyContinue
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