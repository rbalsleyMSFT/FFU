<#
.SYNOPSIS
    FFU Builder Windows ADK Management Module

.DESCRIPTION
    Windows Assessment and Deployment Kit (ADK) installation, validation, and management
    functions for FFU Builder. Provides pre-flight validation, automatic installation,
    version checking, and ADK lifecycle management.

.NOTES
    Module: FFU.ADK
    Version: 1.0.0
    Dependencies: FFU.Core (for WriteLog function)
    Requires: Administrator privileges for ADK installation operations
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

function Write-ADKValidationLog {
    <#
    .SYNOPSIS
    Writes structured log messages for ADK validation with severity levels and color coding.

    .DESCRIPTION
    Helper function for ADK pre-flight validation that logs messages with severity indicators,
    timestamps, and optional context data. Outputs to both the main FFU log and console.

    .PARAMETER Severity
    Log severity level: Info, Success, Warning, Error, or Critical

    .PARAMETER Message
    The log message to write

    .PARAMETER Context
    Optional hashtable of additional context data to include in the log

    .EXAMPLE
    Write-ADKValidationLog -Severity Info -Message "Starting validation"

    .EXAMPLE
    Write-ADKValidationLog -Severity Error -Message "Missing file" -Context @{Path = "C:\file.exe"}
    #>
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Critical')]
        [string]$Severity,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter()]
        [hashtable]$Context = @{}
    )

    $timestamp = Get-Date -Format "MM/dd/yyyy HH:mm:ss"
    $severityIcon = switch ($Severity) {
        'Info'     { '[INFO]' }
        'Success'  { '[  OK]' }
        'Warning'  { '[WARN]' }
        'Error'    { '[FAIL]' }
        'Critical' { '[CRIT]' }
    }

    $logMessage = "$timestamp $severityIcon ADK Pre-Flight: $Message"

    # Log to main FFU log
    WriteLog $logMessage

    # Add context data if provided
    if ($Context.Count -gt 0) {
        foreach ($key in $Context.Keys) {
            $contextMsg = "    $key : $($Context[$key])"
            WriteLog $contextMsg
        }
    }

    # Also write to console with color coding
    $color = switch ($Severity) {
        'Info'     { 'Gray' }
        'Success'  { 'Green' }
        'Warning'  { 'Yellow' }
        'Error'    { 'Red' }
        'Critical' { 'Red' }
    }

    Write-Host $logMessage -ForegroundColor $color

    # Write context to console as well
    if ($Context.Count -gt 0) {
        foreach ($key in $Context.Keys) {
            Write-Host "    $key : $($Context[$key])" -ForegroundColor $color
        }
    }
}

# ADK Validation Error Message Templates
$script:ADKErrorMessageTemplates = @{
    ADKNotInstalled = @"

════════════════════════════════════════════════════════════════════════════════
  CRITICAL ERROR: Windows ADK Not Installed
════════════════════════════════════════════════════════════════════════════════

FFU Builder requires Windows ADK for Windows 11 with the following components:
  - Deployment Tools
  - Windows PE add-on

Installation Instructions:
  1. Download Windows ADK from:
     https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install

  2. Run adksetup.exe and select 'Deployment Tools' feature

  3. Download Windows PE add-on from the same page

  4. Run adkwinpesetup.exe to install WinPE components

  5. Re-run the FFU build script

Alternative: Run with -UpdateADK `$true to attempt automatic installation.

════════════════════════════════════════════════════════════════════════════════
"@

    DeploymentToolsMissing = @"

════════════════════════════════════════════════════════════════════════════════
  CRITICAL ERROR: Deployment Tools Feature Missing
════════════════════════════════════════════════════════════════════════════════

Windows ADK is installed but the Deployment Tools feature is missing.

Resolution Options:
  1. Manual Installation:
     Run: {0} /quiet /features OptionId.DeploymentTools

  2. Automatic Installation:
     Re-run FFU build script with -UpdateADK `$true

════════════════════════════════════════════════════════════════════════════════
"@

    WinPEMissing = @"

════════════════════════════════════════════════════════════════════════════════
  CRITICAL ERROR: Windows PE Add-on Not Installed
════════════════════════════════════════════════════════════════════════════════

The Windows PE add-on is required for creating WinPE boot media.

Resolution Options:
  1. Manual Installation:
     Download from: https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install
     Run adkwinpesetup.exe

  2. Automatic Installation:
     Re-run FFU build script with -UpdateADK `$true

════════════════════════════════════════════════════════════════════════════════
"@

    MissingCriticalFiles = @"

════════════════════════════════════════════════════════════════════════════════
  CRITICAL ERROR: Required ADK Files Missing
════════════════════════════════════════════════════════════════════════════════

The following required ADK files are missing:

{0}

This indicates a corrupted or incomplete ADK installation.

Resolution:
  1. Uninstall Windows ADK and Windows PE add-on from Control Panel

  2. Reboot your system

  3. Re-install both components from:
     https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install

  4. Or run with -UpdateADK `$true for automatic repair

════════════════════════════════════════════════════════════════════════════════
"@

    ArchitectureMismatch = @"

════════════════════════════════════════════════════════════════════════════════
  CRITICAL ERROR: Architecture Tools Missing
════════════════════════════════════════════════════════════════════════════════

ADK architecture tools missing for {0}.

Expected path: {1}

Ensure you have the {0} version of Windows ADK Deployment Tools installed.

════════════════════════════════════════════════════════════════════════════════
"@
}

function Test-ADKPrerequisites {
    <#
    .SYNOPSIS
    Validates Windows ADK installation and required components for FFU build operations.

    .DESCRIPTION
    Performs comprehensive pre-flight checks for:
    - ADK installation via registry
    - Deployment Tools feature installation
    - WinPE add-on installation
    - Critical executable files (copype.cmd, oscdimg.exe, DandISetEnv.bat)
    - Critical boot files (etfsboot.com, Efisys.bin, etc.)

    .PARAMETER WindowsArch
    Target architecture (x64 or arm64) to validate architecture-specific files

    .PARAMETER AutoInstall
    When $true, attempts automatic ADK installation if missing (respects -UpdateADK parameter)

    .PARAMETER ThrowOnFailure
    When $true, throws terminating error on validation failure. When $false, returns validation object.

    .OUTPUTS
    PSCustomObject with validation results including IsValid, ADKPath, errors, warnings, and missing files

    .EXAMPLE
    Test-ADKPrerequisites -WindowsArch 'x64' -ThrowOnFailure $true

    .EXAMPLE
    $validation = Test-ADKPrerequisites -WindowsArch 'x64' -AutoInstall $true -ThrowOnFailure $false
    if (-not $validation.IsValid) {
        Write-Warning "ADK validation failed: $($validation.Errors -join '; ')"
    }
    #>

    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('x64', 'arm64')]
        [string]$WindowsArch,

        [Parameter()]
        [bool]$AutoInstall = $false,

        [Parameter()]
        [bool]$ThrowOnFailure = $true
    )

    # Initialize result object
    $result = [PSCustomObject]@{
        IsValid = $true
        ADKInstalled = $false
        ADKPath = $null
        ADKVersion = $null
        DeploymentToolsInstalled = $false
        WinPEAddOnInstalled = $false
        MissingFiles = @()
        MissingExecutables = @()
        Errors = @()
        Warnings = @()
        ValidationTimestamp = Get-Date
    }

    Write-ADKValidationLog -Severity Info -Message "Starting ADK pre-flight validation for architecture: $WindowsArch"

    # CHECK 1: ADK Registry Key and Installation Path
    try {
        $adkPathKey = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots"
        $adkPathName = "KitsRoot10"

        $adkPathValue = Get-ItemProperty -Path $adkPathKey -Name $adkPathName -ErrorAction Stop

        if ($adkPathValue -and $adkPathValue.$adkPathName) {
            $result.ADKInstalled = $true
            $result.ADKPath = $adkPathValue.$adkPathName

            # Verify the path actually exists
            if (Test-Path -Path $result.ADKPath -PathType Container) {
                Write-ADKValidationLog -Severity Success -Message "ADK installation found" -Context @{
                    Path = $result.ADKPath
                }
            }
            else {
                $result.IsValid = $false
                $result.ADKInstalled = $false
                $result.Errors += "ADK registry path exists but directory not found: $($result.ADKPath)"
                Write-ADKValidationLog -Severity Error -Message "ADK path in registry does not exist on disk" -Context @{
                    Path = $result.ADKPath
                }
            }
        }
    }
    catch {
        $result.IsValid = $false
        $result.Errors += "ADK not installed: Registry key not found"
        Write-ADKValidationLog -Severity Critical -Message "ADK installation not found in registry"

        if ($AutoInstall) {
            Write-ADKValidationLog -Severity Info -Message "Attempting automatic ADK installation..."
            try {
                Install-ADK -ADKOption "Windows ADK"
                Write-ADKValidationLog -Severity Success -Message "ADK installation completed, retrying validation..."

                # Retry validation after installation
                $retryValidation = Test-ADKPrerequisites -WindowsArch $WindowsArch -AutoInstall $false -ThrowOnFailure $false
                return $retryValidation
            }
            catch {
                $result.Errors += "Auto-install failed: $($_.Exception.Message)"
                Write-ADKValidationLog -Severity Error -Message "Automatic ADK installation failed" -Context @{
                    Error = $_.Exception.Message
                }
            }
        }
    }

    # Only continue with component checks if ADK is installed
    if ($result.ADKInstalled) {

        # CHECK 2: Get ADK Version
        try {
            $adkRegKey = Get-InstalledProgramRegKey -DisplayName "Windows Assessment and Deployment Kit"
            if ($adkRegKey) {
                $result.ADKVersion = $adkRegKey.GetValue("DisplayVersion")
                Write-ADKValidationLog -Severity Info -Message "ADK version: $($result.ADKVersion)"
            }
        }
        catch {
            $result.Warnings += "Could not retrieve ADK version: $($_.Exception.Message)"
        }

        # CHECK 3: Deployment Tools
        try {
            $deploymentToolsKey = Get-InstalledProgramRegKey -DisplayName "Windows Deployment Tools"
            if ($deploymentToolsKey) {
                $result.DeploymentToolsInstalled = $true
                Write-ADKValidationLog -Severity Success -Message "Deployment Tools feature installed"
            }
            else {
                $result.IsValid = $false
                $result.Errors += "Deployment Tools feature not installed"
                Write-ADKValidationLog -Severity Error -Message "Deployment Tools feature missing"

                if ($AutoInstall) {
                    Write-ADKValidationLog -Severity Info -Message "Attempting to install Deployment Tools feature..."
                    try {
                        $adkRegKey = Get-InstalledProgramRegKey -DisplayName "Windows Assessment and Deployment Kit"
                        $adkBundleCachePath = $adkRegKey.GetValue("BundleCachePath")
                        if ($adkBundleCachePath) {
                            $adkInstallPath = $result.ADKPath.TrimEnd('\')
                            Invoke-Process $adkBundleCachePath "/quiet /installpath ""$adkInstallPath"" /features OptionId.DeploymentTools" | Out-Null
                            Write-ADKValidationLog -Severity Success -Message "Deployment Tools installed successfully"
                            $result.DeploymentToolsInstalled = $true
                            $result.IsValid = $true
                            $result.Errors = $result.Errors | Where-Object { $_ -notlike "*Deployment Tools*" }
                        }
                    }
                    catch {
                        Write-ADKValidationLog -Severity Error -Message "Failed to install Deployment Tools" -Context @{
                            Error = $_.Exception.Message
                        }
                    }
                }
            }
        }
        catch {
            $result.Warnings += "Error checking Deployment Tools: $($_.Exception.Message)"
        }

        # CHECK 4: WinPE Add-On
        try {
            $winPEKey = Get-InstalledProgramRegKey -DisplayName "Windows Assessment and Deployment Kit Windows Preinstallation Environment Add-ons"
            if ($winPEKey) {
                $result.WinPEAddOnInstalled = $true
                Write-ADKValidationLog -Severity Success -Message "WinPE add-on installed"
            }
            else {
                $result.IsValid = $false
                $result.Errors += "WinPE add-on not installed"
                Write-ADKValidationLog -Severity Error -Message "WinPE add-on missing"

                if ($AutoInstall) {
                    Write-ADKValidationLog -Severity Info -Message "Attempting to install WinPE add-on..."
                    try {
                        Install-ADK -ADKOption "WinPE add-on"
                        Write-ADKValidationLog -Severity Success -Message "WinPE add-on installed successfully"
                        $result.WinPEAddOnInstalled = $true
                        $result.IsValid = $true
                        $result.Errors = $result.Errors | Where-Object { $_ -notlike "*WinPE add-on*" }
                    }
                    catch {
                        Write-ADKValidationLog -Severity Error -Message "Failed to install WinPE add-on" -Context @{
                            Error = $_.Exception.Message
                        }
                    }
                }
            }
        }
        catch {
            $result.Warnings += "Error checking WinPE add-on: $($_.Exception.Message)"
        }

        # CHECK 5: Critical Files
        $filesToCheck = @()

        # DandISetEnv.bat
        $filesToCheck += @{
            Path = "$($result.ADKPath)Assessment and Deployment Kit\Deployment Tools\DandISetEnv.bat"
            Description = "Deployment and Imaging environment setup"
            Critical = $true
        }

        # Architecture-specific paths
        $archPath = if ($WindowsArch -eq 'x64') { 'amd64' } else { 'arm64' }
        $oscdimgPath = "$($result.ADKPath)Assessment and Deployment Kit\Deployment Tools\$archPath\Oscdimg"

        # oscdimg.exe
        $filesToCheck += @{
            Path = "$oscdimgPath\oscdimg.exe"
            Description = "ISO creation tool (oscdimg.exe)"
            Critical = $true
            IsExecutable = $true
        }

        # Boot files for x64
        if ($WindowsArch -eq 'x64') {
            $filesToCheck += @{
                Path = "$oscdimgPath\etfsboot.com"
                Description = "BIOS boot file (etfsboot.com)"
                Critical = $true
            }
        }

        # Boot files for both architectures
        $filesToCheck += @{
            Path = "$oscdimgPath\Efisys.bin"
            Description = "EFI boot file with prompt (Efisys.bin)"
            Critical = $true
        }

        $filesToCheck += @{
            Path = "$oscdimgPath\Efisys_noprompt.bin"
            Description = "EFI boot file no prompt (Efisys_noprompt.bin)"
            Critical = $true
        }

        # copype.cmd
        $filesToCheck += @{
            Path = "$($result.ADKPath)Assessment and Deployment Kit\Windows Preinstallation Environment\copype.cmd"
            Description = "WinPE media creation script (copype.cmd)"
            Critical = $true
        }

        # Validate each file
        foreach ($fileCheck in $filesToCheck) {
            if (-not (Test-Path -Path $fileCheck.Path -PathType Leaf)) {
                $result.MissingFiles += $fileCheck.Path
                $result.IsValid = $false

                if ($fileCheck.Critical) {
                    $result.Errors += "Missing critical file: $($fileCheck.Description)"

                    if ($fileCheck.IsExecutable) {
                        $result.MissingExecutables += $fileCheck.Path
                    }

                    Write-ADKValidationLog -Severity Error -Message "Missing: $($fileCheck.Description)" -Context @{
                        Path = $fileCheck.Path
                    }
                }
            }
            else {
                Write-ADKValidationLog -Severity Success -Message "Found: $($fileCheck.Description)"
            }
        }

        # CHECK 6: Version Check (non-critical)
        if ($result.DeploymentToolsInstalled -and $result.WinPEAddOnInstalled) {
            try {
                $isLatest = Confirm-ADKVersionIsLatest -ADKOption "Windows ADK"
                if (-not $isLatest) {
                    $result.Warnings += "ADK version is not the latest. Consider updating for bug fixes and new features."
                    Write-ADKValidationLog -Severity Warning -Message "ADK version is outdated (non-critical)"
                }
                else {
                    Write-ADKValidationLog -Severity Success -Message "ADK version is up to date"
                }
            }
            catch {
                $result.Warnings += "Could not verify if ADK version is latest: $($_.Exception.Message)"
                Write-ADKValidationLog -Severity Warning -Message "Could not verify ADK version currency"
            }
        }
    }

    # Final evaluation and reporting
    if ($result.IsValid) {
        Write-ADKValidationLog -Severity Success -Message "=== ADK pre-flight validation PASSED ==="

        if ($result.Warnings.Count -gt 0) {
            Write-ADKValidationLog -Severity Warning -Message "$($result.Warnings.Count) warning(s) detected (non-blocking)"
            foreach ($warning in $result.Warnings) {
                Write-ADKValidationLog -Severity Warning -Message "  - $warning"
            }
        }
    }
    else {
        Write-ADKValidationLog -Severity Critical -Message "=== ADK pre-flight validation FAILED ==="
        Write-ADKValidationLog -Severity Error -Message "$($result.Errors.Count) error(s) detected"

        # Display detailed error report based on failure type
        if (-not $result.ADKInstalled) {
            Write-Host $script:ADKErrorMessageTemplates.ADKNotInstalled -ForegroundColor Red
        }
        elseif (-not $result.DeploymentToolsInstalled) {
            try {
                $adkRegKey = Get-InstalledProgramRegKey -DisplayName "Windows Assessment and Deployment Kit"
                $bundlePath = $adkRegKey.GetValue("BundleCachePath")
                Write-Host ($script:ADKErrorMessageTemplates.DeploymentToolsMissing -f $bundlePath) -ForegroundColor Red
            }
            catch {
                Write-Host ($script:ADKErrorMessageTemplates.DeploymentToolsMissing -f "<ADK installer path not found>") -ForegroundColor Red
            }
        }
        elseif (-not $result.WinPEAddOnInstalled) {
            Write-Host $script:ADKErrorMessageTemplates.WinPEMissing -ForegroundColor Red
        }
        elseif ($result.MissingFiles.Count -gt 0) {
            $missingFilesList = ($result.MissingFiles | ForEach-Object { "  - $_" }) -join "`n"
            Write-Host ($script:ADKErrorMessageTemplates.MissingCriticalFiles -f $missingFilesList) -ForegroundColor Red
        }

        if ($ThrowOnFailure) {
            throw "ADK pre-flight validation failed. See detailed errors above."
        }
    }

    return $result
}

function Get-ADKURL {
    param (
        [ValidateSet("Windows ADK", "WinPE add-on")]
        [string]$ADKOption
    )

    # Define base pattern for URL scraping
    $basePattern = '<li><a href="(https://[^"]+)" data-linktype="external">Download the '

    # Define specific URL patterns based on ADK options
    $ADKUrlPattern = @{
        "Windows ADK"  = $basePattern + "Windows ADK"
        "WinPE add-on" = $basePattern + "Windows PE add-on for the Windows ADK"
    }[$ADKOption]

    try {
        # Retrieve content of Microsoft documentation page
        $OriginalVerbosePreference = $VerbosePreference
        $VerbosePreference = 'SilentlyContinue'
        $ADKWebPage = Invoke-RestMethod "https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install" -Headers $Headers -UserAgent $UserAgent
        $VerbosePreference = $OriginalVerbosePreference

        # Extract download URL based on specified pattern
        $ADKMatch = [regex]::Match($ADKWebPage, $ADKUrlPattern)

        if (-not $ADKMatch.Success) {
            WriteLog "Failed to retrieve ADK download URL. Pattern match failed."
            return
        }

        # Extract FWlink from the matched pattern
        $ADKFWLink = $ADKMatch.Groups[1].Value

        if ($null -eq $ADKFWLink) {
            WriteLog "FWLink for $ADKOption not found."
            return
        }

        # Let Invoke-WebRequest handle the redirect and get the final URL.
        try {
            $OriginalVerbosePreference = $VerbosePreference
            $VerbosePreference = 'SilentlyContinue'
            # Allow one redirection to get the final URL from the fwlink
            $response = Invoke-WebRequest -Uri $ADKFWLink -Method Head -MaximumRedirection 1 -Headers $Headers -UserAgent $UserAgent
            $VerbosePreference = $OriginalVerbosePreference

            # The final URL after redirection is in the ResponseUri property of the BaseResponse's RequestMessage.
            $ADKUrl = $response.BaseResponse.RequestMessage.RequestUri.AbsoluteUri

            if ($null -eq $ADKUrl) {
                WriteLog "Could not determine final ADK download URL after redirection."
                return $null
            }

            WriteLog "Resolved ADK download URL to: $ADKUrl"
            return $ADKUrl
        }
        catch {
            WriteLog "An error occurred while resolving the ADK FWLink: $($_.Exception.Message)"
            throw
        }
    }
    catch {
        WriteLog $_
        Write-Error "Error occurred while retrieving ADK download URL"
        throw $_
    }
}

function Install-ADK {
    param (
        [ValidateSet("Windows ADK", "WinPE add-on")]
        [string]$ADKOption
    )

    try {
        $ADKUrl = Get-ADKURL -ADKOption $ADKOption

        if ($null -eq $ADKUrl) {
            throw "Failed to retrieve URL for $ADKOption. Please manually install it."
        }

        # Select the installer based on the ADK option specified
        $installer = @{
            "Windows ADK"  = "adksetup.exe"
            "WinPE add-on" = "adkwinpesetup.exe"
        }[$ADKOption]

        # Select the feature based on the ADK option specified
        $feature = @{
            "Windows ADK"  = "OptionId.DeploymentTools"
            "WinPE add-on" = "OptionId.WindowsPreinstallationEnvironment"
        }[$ADKOption]

        $installerLocation = Join-Path $env:TEMP $installer

        WriteLog "Downloading $ADKOption from $ADKUrl to $installerLocation"
        Start-BitsTransferWithRetry -Source $ADKUrl -Destination $installerLocation -ErrorAction Stop
        WriteLog "$ADKOption downloaded to $installerLocation"

        WriteLog "Installing $ADKOption with $feature enabled"
        Invoke-Process $installerLocation "/quiet /installpath ""%ProgramFiles(x86)%\Windows Kits\10"" /features $feature" | Out-Null

        WriteLog "$ADKOption installation completed."
        WriteLog "Removing $installer from $installerLocation"
        # Clean up downloaded installation file
        Remove-Item -Path $installerLocation -Force -ErrorAction SilentlyContinue
    }
    catch {
        WriteLog $_
        Write-Error "Error occurred while installing $ADKOption. Please manually install it."
        throw $_
    }
}

function Get-InstalledProgramRegKey {
    param (
        [string]$DisplayName
    )

    $uninstallRegPath = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    $uninstallRegKeys = Get-ChildItem -Path $uninstallRegPath -Recurse

    foreach ($regKey in $uninstallRegKeys) {
        try {
            $regValue = $regKey.GetValue("DisplayName")
            if ($regValue -eq $DisplayName) {
                return $regKey
            }
        }
        catch {
            WriteLog $_
            throw "Error retrieving installed program info for $DisplayName : $_"
        }
    }
}

function Uninstall-ADK {
    param (
        [ValidateSet("Windows ADK", "WinPE add-on")]
        [string]$ADKOption
    )

    # Match name as it appears in the registry
    $displayName = switch ($ADKOption) {
        "Windows ADK" { "Windows Assessment and Deployment Kit" }
        "WinPE add-on" { "Windows Assessment and Deployment Kit Windows Preinstallation Environment Add-ons" }
    }

    try {
        $adkRegKey = Get-InstalledProgramRegKey -DisplayName $displayName

        if (-not $adkRegKey) {
            WriteLog "$ADKOption is not installed."
            return
        }

        $adkBundleCachePath = $adkRegKey.GetValue("BundleCachePath")
        WriteLog "Uninstalling $ADKOption..."
        Invoke-Process $adkBundleCachePath "/uninstall /quiet" | Out-Null
        WriteLog "$ADKOption uninstalled successfully."
    }
    catch {
        WriteLog $_
        Write-Error "Error occurred while uninstalling $ADKOption. Please manually uninstall it."
        throw $_
    }
}

function Confirm-ADKVersionIsLatest {
    <#
    .SYNOPSIS
    Checks if installed ADK version matches the latest available version

    .DESCRIPTION
    Compares the installed Windows ADK or WinPE add-on version against the
    latest version published on Microsoft documentation. Used to determine
    if ADK updates are needed.

    .PARAMETER ADKOption
    Component to check: "Windows ADK" or "WinPE add-on"

    .PARAMETER Headers
    HTTP headers hashtable for web requests to Microsoft documentation

    .PARAMETER UserAgent
    User agent string for web requests

    .EXAMPLE
    $isLatest = Confirm-ADKVersionIsLatest -ADKOption "Windows ADK" `
                                           -Headers $headers -UserAgent $userAgent

    .OUTPUTS
    System.Boolean - $true if installed version is latest, $false otherwise
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet("Windows ADK", "WinPE add-on")]
        [string]$ADKOption,

        [Parameter(Mandatory = $false)]
        [hashtable]$Headers,

        [Parameter(Mandatory = $false)]
        [string]$UserAgent
    )

    # If Headers or UserAgent not provided, skip version check (non-critical)
    if (-not $Headers -or -not $UserAgent) {
        WriteLog "Headers or UserAgent not provided. Skipping ADK version check (non-critical)."
        return $false
    }

    $displayName = switch ($ADKOption) {
        "Windows ADK" { "Windows Assessment and Deployment Kit" }
        "WinPE add-on" { "Windows Assessment and Deployment Kit Windows Preinstallation Environment Add-ons" }
    }

    try {
        $adkRegKey = Get-InstalledProgramRegKey -DisplayName $displayName

        if (-not $adkRegKey) {
            return $false
        }

        $installedADKVersion = $adkRegKey.GetValue("DisplayVersion")

        # Retrieve content of Microsoft documentation page
        $adkWebPage = Invoke-RestMethod "https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install" -Headers $Headers -UserAgent $UserAgent
        # Specify regex pattern for ADK version
        $adkVersionPattern = 'ADK\s+(\d+(\.\d+)+)'
        # Check for regex pattern match
        $adkVersionMatch = [regex]::Match($adkWebPage, $adkVersionPattern)

        if (-not $adkVersionMatch.Success) {
            WriteLog "Failed to retrieve latest ADK version from web page."
            return $false
        }

        # Extract ADK version from the matched pattern
        $latestADKVersion = $adkVersionMatch.Groups[1].Value

        if ($installedADKVersion -eq $latestADKVersion) {
            WriteLog "Installed $ADKOption version $installedADKVersion is the latest."
            return $true
        }
        else {
            WriteLog "Installed $ADKOption version $installedADKVersion is not the latest ($latestADKVersion)"
            return $false
        }
    }
    catch {
        WriteLog "An error occurred while confirming the ADK version: $_"
        return $false
    }
}

function Get-ADK {
    <#
    .SYNOPSIS
    Retrieves Windows ADK installation path and ensures required components are installed

    .DESCRIPTION
    Locates the Windows ADK installation path from registry. Optionally checks for and installs
    the latest ADK and Windows PE add-on versions. Validates that Windows Deployment Tools
    feature is installed and automatically installs it if missing.

    .PARAMETER UpdateADK
    If $true, checks for latest ADK and WinPE versions and updates if necessary.
    If $false, only retrieves existing ADK path and validates Deployment Tools installation.

    .EXAMPLE
    $adkPath = Get-ADK -UpdateADK $true
    Returns ADK path after ensuring latest versions are installed

    .EXAMPLE
    $adkPath = Get-ADK -UpdateADK $false
    Returns ADK path without checking for updates

    .OUTPUTS
    System.String - Full path to the Windows ADK installation directory
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$UpdateADK
    )
    # Check if latest ADK and WinPE add-on are installed
    if ($UpdateADK) {
        WriteLog "Checking if latest ADK and WinPE add-on are installed"
        $latestADKInstalled = Confirm-ADKVersionIsLatest -ADKOption "Windows ADK"
        $latestWinPEInstalled = Confirm-ADKVersionIsLatest -ADKOption "WinPE add-on"

        # Uninstall older versions and install latest versions if necessary
        if (-not $latestADKInstalled) {
            Uninstall-ADK -ADKOption "Windows ADK"
            Install-ADK -ADKOption "Windows ADK"
        }

        if (-not $latestWinPEInstalled) {
            Uninstall-ADK -ADKOption "WinPE add-on"
            Install-ADK -ADKOption "WinPE add-on"
        }
    }

    # Define registry path
    $adkPathKey = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots"
    $adkPathName = "KitsRoot10"

    # Check if ADK installation path exists in registry
    $adkPathNameExists = (Get-ItemProperty -Path $adkPathKey -Name $adkPathName -ErrorAction SilentlyContinue)

    if ($adkPathNameExists) {
        # Get the ADK installation path
        WriteLog 'Get ADK Path'
        $adkPath = (Get-ItemProperty -Path $adkPathKey -Name $adkPathName).$adkPathName
        WriteLog "ADK located at $adkPath"
    }
    else {
        throw "Windows ADK installation path could not be found."
    }

    # If ADK was already installed, then check if the Windows Deployment Tools feature is also installed
    $deploymentToolsRegKey = Get-InstalledProgramRegKey -DisplayName "Windows Deployment Tools"

    if (-not $deploymentToolsRegKey) {
        WriteLog "ADK is installed, but the Windows Deployment Tools feature is not installed."
        $adkRegKey = Get-InstalledProgramRegKey -DisplayName "Windows Assessment and Deployment Kit"
        $adkBundleCachePath = $adkRegKey.GetValue("BundleCachePath")
        if ($adkBundleCachePath) {
            WriteLog "Installing Windows Deployment Tools..."
            $adkInstallPath = $adkPath.TrimEnd('\')
            Invoke-Process $adkBundleCachePath "/quiet /installpath ""$adkInstallPath"" /features OptionId.DeploymentTools" | Out-Null
            WriteLog "Windows Deployment Tools installed successfully."
        }
        else {
            throw "Failed to retrieve path to adksetup.exe to install the Windows Deployment Tools. Please manually install it."
        }
    }
    return $adkPath
}

# Export module members
Export-ModuleMember -Function @(
    'Write-ADKValidationLog',
    'Test-ADKPrerequisites',
    'Get-ADKURL',
    'Install-ADK',
    'Get-InstalledProgramRegKey',
    'Uninstall-ADK',
    'Confirm-ADKVersionIsLatest',
    'Get-ADK'
)