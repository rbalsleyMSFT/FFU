function Get-USBDrive() {
    $USBDriveLetter = (Get-Volume | Where-Object { $_.DriveType -eq 'Removable' -and $_.FileSystemType -eq 'NTFS' }).DriveLetter
    if ($null -eq $USBDriveLetter) {
        #Must be using a fixed USB drive - difficult to grab drive letter from win32_diskdrive. Assume user followed instructions and used Deploy as the friendly name for partition
        $USBDriveLetter = (Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.FileSystemType -eq 'NTFS' -and $_.FileSystemLabel -eq 'Deploy' }).DriveLetter
        #If we didn't get the drive letter, stop the script.
        if ($null -eq $USBDriveLetter) {
            $errorMessage = 'Cannot find USB drive letter. If using a fixed USB drive, name the deployment partition "Deploy".'
            WriteLog ($errorMessage + ' Exiting.')
            Stop-Script -Message $errorMessage
        }

    }
    $USBDriveLetter = $USBDriveLetter + ":\"
    return $USBDriveLetter
}

function Get-HardDrive() {
    $systemInfo = Get-CimInstance -Class 'Win32_ComputerSystem'
    $manufacturer = $systemInfo.Manufacturer
    $model = $systemInfo.Model
    WriteLog 'Getting Hard Drive info'
    if ($manufacturer -eq 'Microsoft Corporation' -and $model -eq 'Virtual Machine') {
        WriteLog 'Running in a Hyper-V VM. Getting virtual disk on Index 0 and SCSILogicalUnit 0'
        $diskDriveCandidates = @(Get-CimInstance -Class 'Win32_DiskDrive' | Where-Object { $_.MediaType -eq 'Fixed hard disk media' `
                    -and $_.Model -eq 'Microsoft Virtual Disk' `
                    -and $_.Index -eq 0 `
                    -and $_.SCSILogicalUnit -eq 0
            })
    }
    else {
        WriteLog 'Not running in a VM. Getting physical disk drive'
        $diskDriveCandidates = @(Get-CimInstance -Class 'Win32_DiskDrive' | Where-Object { $_.MediaType -eq 'Fixed hard disk media' -and $_.Model -ne 'Microsoft Virtual Disk' })
    }

    # Return the array of candidates for selection in main script
    return $diskDriveCandidates
}

function WriteLog($LogText) { 
    Add-Content -path $LogFile -value "$((Get-Date).ToString()) $LogText"
}

function Set-DiskpartAnswerFiles($DiskpartFile, $DiskID) {
    (Get-Content $DiskpartFile).Replace('disk 0', "disk $DiskID") | Set-Content -Path $DiskpartFile
}

function Set-Computername($computername) {
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
        [string]$ArgumentList,

        [Parameter()]
        [switch]$IgnoreExitCode,

        [Parameter()]
        [switch]$PassThruExitCode
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
            NoNewWindow            = $true;
        }
        if ($PSCmdlet.ShouldProcess("Process [$($FilePath)]", "Run with args: [$($ArgumentList)]")) {
            $cmd = Start-Process @startProcessParams
            $cmdOutput = Get-Content -Path $stdOutTempFile -Raw
            $cmdError = Get-Content -Path $stdErrTempFile -Raw

            if ($cmd.ExitCode -ne 0) {
                # Non-terminating mode: capture output to Scriptlog and continue
                if ($IgnoreExitCode) {
                    if ([string]::IsNullOrEmpty($cmdOutput) -eq $false) {
                        WriteLog $cmdOutput
                    }
                    if ([string]::IsNullOrEmpty($cmdError) -eq $false) {
                        WriteLog $cmdError
                    }
                    if ($PassThruExitCode) {
                        return $cmd.ExitCode
                    }
                    return
                }

                if ($cmdError) {
                    throw $cmdError.Trim()
                }
                if ($cmdOutput) {
                    throw $cmdOutput.Trim()
                }
                throw "Process failed. ExitCode = $($cmd.ExitCode)."
            }
            else {
                if ([string]::IsNullOrEmpty($cmdOutput) -eq $false) {
                    WriteLog $cmdOutput
                }
            }

            if ($PassThruExitCode) {
                return $cmd.ExitCode
            }
        }
    }
    catch {
        #$PSCmdlet.ThrowTerminatingError($_)
        WriteLog $_
        Write-Host 'Script failed - check scriptlog.txt on the USB drive for more info'
        throw $_

    }
    finally {
        Remove-Item -Path $stdOutTempFile, $stdErrTempFile -Force -ErrorAction Ignore
        
    }
    
}

function Write-SectionHeader($Title) {
    $width = 51
    $leftPad = [math]::Floor(($width - $Title.Length) / 2)
    $rightPad = $width - $Title.Length - $leftPad
    $centeredTitle = (' ' * $leftPad) + $Title + (' ' * $rightPad)

    Write-Host "`n" # Add a newline for spacing
    Write-Host ('-' * $width) -ForegroundColor Yellow
    Write-Host $centeredTitle -ForegroundColor Yellow
    Write-Host ('-' * $width) -ForegroundColor Yellow
}

function Get-NormalizedManufacturer {
    param(
        [string]$Manufacturer
    )

    if ([string]::IsNullOrWhiteSpace($Manufacturer)) {
        return $null
    }

    $normalized = $Manufacturer.Trim().ToUpperInvariant()
    if ($normalized -like '*DELL*') {
        return 'Dell'
    }
    elseif ($normalized -like '*HP*' -or $normalized -like '*HEWLETT*') {
        return 'HP'
    }
    elseif ($normalized -like '*LENOVO*') {
        return 'Lenovo'
    }
    elseif ($normalized -like '*MICROSOFT*' -or $normalized -like '*SURFACE*') {
        return 'Microsoft'
    }
    elseif ($normalized -like '*PANASONIC*') {
        return 'Panasonic Corporation'
    }
    elseif ($normalized -like '*VIGLEN*') {
        return 'Viglen'
    }
    elseif ($normalized -like '*AZW*') {
        return 'AZW'
    }
    elseif ($normalized -like '*FUJITSU*') {
        return 'Fujitsu'
    }
    elseif ($normalized -like '*GETAC*') {
        return 'Getac'
    }
    elseif ($normalized -like '*BYTESPEED*') {
        return 'ByteSpeed'
    }
    elseif ($normalized -like '*INTEL*') {
        return 'Intel'
    }

    return $Manufacturer.Trim()
}

function Get-SystemIdentityMetadata {
    param(
        [Parameter(Mandatory = $true)]
        [Microsoft.Management.Infrastructure.CimInstance]$ComputerSystem,
        [Parameter()]
        [Microsoft.Management.Infrastructure.CimInstance]$ComputerSystemProduct,
        [Parameter()]
        [Microsoft.Management.Infrastructure.CimInstance]$MsSystemInformation
    )

    # Consolidate manufacturer normalization so UI and driver mapping share the same identifiers.
    $normalizedManufacturer = Get-NormalizedManufacturer -Manufacturer $ComputerSystem.Manufacturer
    if (-not $ComputerSystemProduct) {
        $ComputerSystemProduct = Get-CimInstance -Class Win32_ComputerSystemProduct -ErrorAction SilentlyContinue
    }
    $baseBoardInfo = Get-CimInstance -Class Win32_BaseBoard -ErrorAction SilentlyContinue | Select-Object -First 1
    $baseBoardSku = if ($baseBoardInfo -and -not [string]::IsNullOrWhiteSpace($baseBoardInfo.SKU)) { $baseBoardInfo.SKU.Trim() } else { $null }
    $msBaseBoardProduct = if ($MsSystemInformation -and $MsSystemInformation.BaseBoardProduct) { $MsSystemInformation.BaseBoardProduct.Trim() } else { $null }

    $modelCandidate = if ($normalizedManufacturer -eq 'Lenovo' -and $ComputerSystemProduct -and -not [string]::IsNullOrWhiteSpace($ComputerSystemProduct.Version)) {
        $ComputerSystemProduct.Version
    }
    else {
        $ComputerSystem.Model
    }
    if ([string]::IsNullOrWhiteSpace($modelCandidate)) {
        $modelCandidate = $ComputerSystem.Model
    }
    if ($modelCandidate) {
        $modelCandidate = $modelCandidate.Trim()
    }

    $identity = [pscustomobject]@{
        ManufacturerOriginal   = $ComputerSystem.Manufacturer
        ManufacturerNormalized = if ($normalizedManufacturer) { $normalizedManufacturer } else { $ComputerSystem.Manufacturer }
        ModelOriginal          = $modelCandidate
        ModelNormalized        = ConvertTo-ComparableModelName -Text $modelCandidate
        SystemSkuNormalized    = $null
        FallbackSkuNormalized  = $null
        MachineTypeNormalized  = $null
        IdentifierLabel        = 'System ID'
        IdentifierValue        = $null
    }

    if ($MsSystemInformation -and $MsSystemInformation.SystemSku) {
        $identity.SystemSkuNormalized = $MsSystemInformation.SystemSku.Trim().ToUpperInvariant()
    }

    switch ($identity.ManufacturerNormalized) {
        'Dell' {
            if ($MsSystemInformation -and $MsSystemInformation.SystemSku) {
                $identity.SystemSkuNormalized = $MsSystemInformation.SystemSku.Trim().ToUpperInvariant()
            }
            $oemStringArray = $ComputerSystem | Select-Object -ExpandProperty OEMStringArray -ErrorAction SilentlyContinue
            if ($oemStringArray) {
                $joinedOemString = ($oemStringArray -join ' ')
                $fallbackMatches = [regex]::Matches($joinedOemString, '\[\S*]')
                if ($fallbackMatches.Count -gt 0) {
                    $identity.FallbackSkuNormalized = $fallbackMatches[0].Value.TrimStart('[').TrimEnd(']').Trim().ToUpperInvariant()
                }
            }
            if ($identity.FallbackSkuNormalized) {
                $identity.IdentifierValue = $identity.FallbackSkuNormalized
            }
            elseif ($identity.SystemSkuNormalized) {
                $identity.IdentifierValue = $identity.SystemSkuNormalized
            }
            break
        }
        'HP' {
            if ($msBaseBoardProduct) {
                $identity.SystemSkuNormalized = $msBaseBoardProduct.ToUpperInvariant()
            }
            break
        }
        'Lenovo' {
            $modelValue = $ComputerSystem.Model
            if (-not [string]::IsNullOrWhiteSpace($modelValue) -and $modelValue.Length -ge 4) {
                $identity.MachineTypeNormalized = $modelValue.Substring(0, 4).Trim().ToUpperInvariant()
            }
            $identity.IdentifierLabel = 'Machine Type'
            if ($identity.MachineTypeNormalized) {
                $identity.IdentifierValue = $identity.MachineTypeNormalized
            }
            break
        }
        'Panasonic Corporation' {
            $identity.IdentifierLabel = 'System ID'
            if ($msBaseBoardProduct) {
                $identity.SystemSkuNormalized = $msBaseBoardProduct.ToUpperInvariant()
                $identity.IdentifierValue = $msBaseBoardProduct
            }
            break
        }
        'Viglen' {
            $identity.IdentifierLabel = 'System ID'
            if ($baseBoardSku) {
                $identity.SystemSkuNormalized = $baseBoardSku.ToUpperInvariant()
                $identity.IdentifierValue = $baseBoardSku
            }
            break
        }
        'AZW' {
            $identity.IdentifierLabel = 'System ID'
            if ($msBaseBoardProduct) {
                $identity.SystemSkuNormalized = $msBaseBoardProduct.ToUpperInvariant()
                $identity.IdentifierValue = $msBaseBoardProduct
            }
            break
        }
        'Fujitsu' {
            $identity.IdentifierLabel = 'System ID'
            if ($baseBoardSku) {
                $identity.SystemSkuNormalized = $baseBoardSku.ToUpperInvariant()
                $identity.IdentifierValue = $baseBoardSku
            }
            break
        }
        'Getac' {
            $identity.IdentifierLabel = 'System ID'
            if ($msBaseBoardProduct) {
                $identity.SystemSkuNormalized = $msBaseBoardProduct.ToUpperInvariant()
                $identity.IdentifierValue = $msBaseBoardProduct
            }
            break
        }
        'Intel' {
            $identity.IdentifierLabel = 'Model'
            if ($identity.ModelOriginal) {
                $identity.IdentifierValue = $identity.ModelOriginal
            }
            break
        }
        'ByteSpeed' {
            $modelValue = if ($ComputerSystem.Model) { $ComputerSystem.Model.Trim() } else { $null }
            if ($modelValue -and $modelValue -like '*NUC*') {
                $identity.ManufacturerNormalized = 'Intel'
                if ($msBaseBoardProduct) {
                    $identity.ModelOriginal = $msBaseBoardProduct
                    $identity.ModelNormalized = ConvertTo-ComparableModelName -Text $msBaseBoardProduct
                    $identity.IdentifierLabel = 'Model'
                    $identity.IdentifierValue = $msBaseBoardProduct
                }
                elseif ($modelValue) {
                    $identity.IdentifierLabel = 'Model'
                    $identity.IdentifierValue = $modelValue
                }
            }
            else {
                $identity.IdentifierLabel = 'Model'
                if ($modelValue) {
                    $identity.IdentifierValue = $modelValue
                }
            }
            break
        }
        default {
            break
        }
    }

    if ($null -eq $identity.IdentifierValue) {
        if ($identity.MachineTypeNormalized) {
            $identity.IdentifierValue = $identity.MachineTypeNormalized
        }
        elseif ($identity.SystemSkuNormalized) {
            $identity.IdentifierValue = $identity.SystemSkuNormalized
        }
    }

    return $identity
}

function Get-SystemInformation {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$HardDrive
    )

    $computerSystem = Get-CimInstance -Class Win32_ComputerSystem
    $computerSystemProduct = Get-CimInstance -Class Win32_ComputerSystemProduct -ErrorAction SilentlyContinue
    $msSystemInformation = Get-CimInstance -Namespace 'root\WMI' -Class MS_SystemInformation -ErrorAction SilentlyContinue
    $systemIdentity = Get-SystemIdentityMetadata -ComputerSystem $computerSystem -ComputerSystemProduct $computerSystemProduct -MsSystemInformation $msSystemInformation

    $biosInfo = Get-CimInstance -Class Win32_Bios
    $processorInfo = Get-CimInstance -Class Win32_Processor | Select-Object -First 1
    $processor = if ($processorInfo) { $processorInfo.Name } else { 'Unknown' }
    $totalMemory = (Get-CimInstance -Class Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum
    if ($null -eq $totalMemory) {
        $totalMemory = 0
    }
    $totalMemoryGB = [math]::Round(($totalMemory / 1GB), 2)
    $diskSizeGB = [math]::Round(($HardDrive.DiskSize / 1GB), 2)

    $baseBoardManufacturer = if ($msSystemInformation -and $msSystemInformation.BaseBoardManufacturer) { $msSystemInformation.BaseBoardManufacturer.Trim() } else { $null }
    $baseBoardProduct = if ($msSystemInformation -and $msSystemInformation.BaseBoardProduct) { $msSystemInformation.BaseBoardProduct.Trim() } else { $null }
    $baseBoardVersion = if ($msSystemInformation -and $msSystemInformation.BaseBoardVersion) { $msSystemInformation.BaseBoardVersion.Trim() } else { $null }
    $biosMajorRelease = if ($msSystemInformation -and $null -ne $msSystemInformation.BiosMajorRelease) { [string]$msSystemInformation.BiosMajorRelease } else { $null }
    $biosMinorRelease = if ($msSystemInformation -and $null -ne $msSystemInformation.BiosMinorRelease) { [string]$msSystemInformation.BiosMinorRelease } else { $null }
    $biosReleaseDate = $null
    if ($msSystemInformation -and $msSystemInformation.BiosReleaseDate) {
        try {
            $biosReleaseDate = [System.Management.ManagementDateTimeConverter]::ToDateTime($msSystemInformation.BiosReleaseDate).ToString('yyyy-MM-dd HH:mm:ss')
        }
        catch {
            $biosReleaseDate = $msSystemInformation.BiosReleaseDate
        }
    }
    $biosVendor = if ($msSystemInformation -and $msSystemInformation.BiosVendor) { $msSystemInformation.BiosVendor.Trim() } else { $null }
    $biosVersion = if ($msSystemInformation -and $msSystemInformation.BiosVersion) { $msSystemInformation.BiosVersion.Trim() } else { $null }
    $ecFirmwareMajorRelease = if ($msSystemInformation -and $null -ne $msSystemInformation.ECFirmwareMajorRelease) { [string]$msSystemInformation.ECFirmwareMajorRelease } else { $null }
    $ecFirmwareMinorRelease = if ($msSystemInformation -and $null -ne $msSystemInformation.ECFirmwareMinorRelease) { [string]$msSystemInformation.ECFirmwareMinorRelease } else { $null }

    $displayManufacturer = if ($systemIdentity.ManufacturerNormalized) { $systemIdentity.ManufacturerNormalized } else { $computerSystem.Manufacturer }
    $displayModel = if ($systemIdentity.ModelNormalized) { $systemIdentity.ModelNormalized } else { $systemIdentity.ModelOriginal }

    $sysInfoData = [ordered]@{
        "Manufacturer"           = $displayManufacturer
        "Model"                  = $displayModel
        "Serial Number"          = $biosInfo.SerialNumber
        "Processor"              = $processor
        "Memory"                 = "{0} GB" -f $totalMemoryGB
        "Disk Size"              = "{0} GB" -f $diskSizeGB
        "Logical Sector Size"    = "$($HardDrive.BytesPerSector) Bytes"
        "BaseBoardManufacturer"  = if ($baseBoardManufacturer) { $baseBoardManufacturer } else { 'Not Detected' }
        "BaseBoardProduct"       = if ($baseBoardProduct) { $baseBoardProduct } else { 'Not Detected' }
        "BaseBoardVersion"       = if ($baseBoardVersion) { $baseBoardVersion } else { 'Not Detected' }
        "BiosMajorRelease"       = if ($biosMajorRelease) { $biosMajorRelease } else { 'Not Detected' }
        "BiosMinorRelease"       = if ($biosMinorRelease) { $biosMinorRelease } else { 'Not Detected' }
        "BiosReleaseDate"        = if ($biosReleaseDate) { $biosReleaseDate } else { 'Not Detected' }
        "BiosVendor"             = if ($biosVendor) { $biosVendor } else { 'Not Detected' }
        "BiosVersion"            = if ($biosVersion) { $biosVersion } else { 'Not Detected' }
        "ECFirmwareMajorRelease" = if ($ecFirmwareMajorRelease) { $ecFirmwareMajorRelease } else { 'Not Detected' }
        "ECFirmwareMinorRelease" = if ($ecFirmwareMinorRelease) { $ecFirmwareMinorRelease } else { 'Not Detected' }
        "ManufacturerNormalized" = $systemIdentity.ManufacturerNormalized
        "ModelNormalized"        = $systemIdentity.ModelNormalized
        "DriverIdentifierLabel"  = $systemIdentity.IdentifierLabel
        "DriverIdentifierValue"  = $systemIdentity.IdentifierValue
        "SystemSkuNormalized"    = $systemIdentity.SystemSkuNormalized
        "FallbackSkuNormalized"  = $systemIdentity.FallbackSkuNormalized
        "MachineTypeNormalized"  = $systemIdentity.MachineTypeNormalized
    }
    $sysInfoData[$systemIdentity.IdentifierLabel] = if ($systemIdentity.IdentifierValue) { $systemIdentity.IdentifierValue } else { 'Not Detected' }

    return [PSCustomObject]$sysInfoData
}

function Write-SystemInformation {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$SystemInformation
    )

    $hiddenProperties = @(
        'SystemSkuNormalized',
        'FallbackSkuNormalized',
        'MachineTypeNormalized',
        'ManufacturerNormalized',
        'ModelNormalized',
        'DriverIdentifierLabel',
        'DriverIdentifierValue'
    )

    WriteLog '--- System Information ---'
    foreach ($property in $SystemInformation.psobject.Properties) {
        if ($hiddenProperties -contains $property.Name) {
            continue
        }
        WriteLog "$($property.Name): $($property.Value)"
    }
    WriteLog '--- End System Information ---'

    Write-SectionHeader -Title 'System Information'
    $displayData = [ordered]@{}
    foreach ($property in $SystemInformation.psobject.Properties) {
        if ($hiddenProperties -contains $property.Name) {
            continue
        }
        $displayData[$property.Name] = $property.Value
    }
    $consoleOutput = ([pscustomobject]$displayData | Format-List | Out-String)
    Write-Host $consoleOutput.Trim()
    Write-Host
}

function Find-DriverMappingRule {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$SystemInformation,
        [Parameter(Mandatory = $true)]
        [object[]]$DriverMappings
    )

    $normalizedManufacturer = if ($SystemInformation.PSObject.Properties['ManufacturerNormalized']) {
        $SystemInformation.ManufacturerNormalized
    }
    else {
        Get-NormalizedManufacturer -Manufacturer $SystemInformation.Manufacturer
    }
    if ([string]::IsNullOrWhiteSpace($normalizedManufacturer)) {
        WriteLog 'DriverMapping: Unable to determine manufacturer for automatic matching.'
        return $null
    }

    $driverMappingsArray = @()
    foreach ($entry in @($DriverMappings)) {
        if ($null -ne $entry) {
            $driverMappingsArray += $entry
        }
    }
    if ($driverMappingsArray.Count -eq 0) {
        WriteLog 'DriverMapping: Mapping file contained no entries.'
        return $null
    }

    $rulesForMake = @($driverMappingsArray | Where-Object {
            $entryManufacturer = Get-NormalizedManufacturer -Manufacturer $_.Manufacturer
            $entryManufacturer -eq $normalizedManufacturer
        })
    if ($rulesForMake.Count -eq 0) {
        WriteLog "DriverMapping: No entries found for manufacturer '$normalizedManufacturer'."
        return $null
    }

    $systemSkuNormalized = if ($SystemInformation.PSObject.Properties['SystemSkuNormalized']) { $SystemInformation.SystemSkuNormalized } else { $null }
    $fallbackSkuNormalized = if ($SystemInformation.PSObject.Properties['FallbackSkuNormalized']) { $SystemInformation.FallbackSkuNormalized } else { $null }
    $machineTypeNormalized = if ($SystemInformation.PSObject.Properties['MachineTypeNormalized']) { $SystemInformation.MachineTypeNormalized } else { $null }
    $normalizedModel = if ($SystemInformation.PSObject.Properties['ModelNormalized']) { $SystemInformation.ModelNormalized } else { $null }
    if ([string]::IsNullOrWhiteSpace($normalizedModel)) {
        $normalizedModel = ConvertTo-ComparableModelName -Text $SystemInformation.Model
    }

    switch ($normalizedManufacturer) {
        'Dell' {
            if (-not [string]::IsNullOrWhiteSpace($systemSkuNormalized)) {
                $match = $rulesForMake | Where-Object { $_.PSObject.Properties['SystemId'] -and $_.SystemId.Trim().ToUpperInvariant() -eq $systemSkuNormalized } | Select-Object -First 1
                if ($match) {
                    WriteLog "DriverMapping: Dell SystemId '$systemSkuNormalized' matched '$($match.Model)'."
                    return $match
                }
            }
            if (-not [string]::IsNullOrWhiteSpace($fallbackSkuNormalized)) {
                $match = $rulesForMake | Where-Object { $_.PSObject.Properties['SystemId'] -and $_.SystemId.Trim().ToUpperInvariant() -eq $fallbackSkuNormalized } | Select-Object -First 1
                if ($match) {
                    WriteLog "DriverMapping: Dell fallback SKU '$fallbackSkuNormalized' matched '$($match.Model)'."
                    return $match
                }
            }
            WriteLog 'DriverMapping: Dell identifiers did not match any entries.'
            return $null
        }
        'HP' {
            if (-not [string]::IsNullOrWhiteSpace($systemSkuNormalized)) {
                $match = $rulesForMake | Where-Object { $_.PSObject.Properties['SystemId'] -and $_.SystemId.Trim().ToUpperInvariant() -eq $systemSkuNormalized } | Select-Object -First 1
                if ($match) {
                    WriteLog "DriverMapping: HP SystemId '$systemSkuNormalized' matched '$($match.Model)'."
                    return $match
                }
            }
            WriteLog 'DriverMapping: HP SystemId not detected or not present in mapping.'
            return $null
        }
        'Lenovo' {
            if (-not [string]::IsNullOrWhiteSpace($machineTypeNormalized)) {
                $match = $rulesForMake | Where-Object { $_.PSObject.Properties['MachineType'] -and $_.MachineType.Trim().ToUpperInvariant() -eq $machineTypeNormalized } | Select-Object -First 1
                if ($match) {
                    WriteLog "DriverMapping: Lenovo MachineType '$machineTypeNormalized' matched '$($match.Model)'."
                    return $match
                }
            }
            WriteLog 'DriverMapping: Lenovo MachineType not detected or not present in mapping.'
            return $null
        }
        'Microsoft' {
            # Prefer System SKU matching for Microsoft/Surface when available.
            if (-not [string]::IsNullOrWhiteSpace($systemSkuNormalized)) {
                foreach ($rule in $rulesForMake) {
                    if ($rule.PSObject.Properties['SystemSku'] -and $null -ne $rule.SystemSku) {
                        foreach ($sku in @($rule.SystemSku)) {
                            if (-not [string]::IsNullOrWhiteSpace($sku) -and $sku.Trim().ToUpperInvariant() -eq $systemSkuNormalized) {
                                WriteLog "DriverMapping: Microsoft SystemSku '$systemSkuNormalized' matched '$($rule.Model)'."
                                return $rule
                            }
                        }
                    }
                }
            }

            # Fallback to model string comparison (legacy behavior).
            foreach ($rule in $rulesForMake) {
                $ruleModelNorm = ConvertTo-ComparableModelName -Text $rule.Model
                if (-not [string]::IsNullOrWhiteSpace($ruleModelNorm) -and $ruleModelNorm -eq $normalizedModel) {
                    WriteLog "DriverMapping: Microsoft model '$normalizedModel' matched '$($rule.Model)'."
                    return $rule
                }
            }
            WriteLog 'DriverMapping: Microsoft model not present in mapping.'
            return $null
        }
        'Panasonic Corporation' {
            if (-not [string]::IsNullOrWhiteSpace($systemSkuNormalized)) {
                $match = $rulesForMake | Where-Object { $_.PSObject.Properties['SystemId'] -and $_.SystemId.Trim().ToUpperInvariant() -eq $systemSkuNormalized } | Select-Object -First 1
                if ($match) {
                    WriteLog "DriverMapping: Panasonic SystemId '$systemSkuNormalized' matched '$($match.Model)'."
                    return $match
                }
            }
            WriteLog 'DriverMapping: Panasonic SystemId not detected or not present in mapping.'
            return $null
        }
        'Viglen' {
            if (-not [string]::IsNullOrWhiteSpace($systemSkuNormalized)) {
                $match = $rulesForMake | Where-Object { $_.PSObject.Properties['SystemId'] -and $_.SystemId.Trim().ToUpperInvariant() -eq $systemSkuNormalized } | Select-Object -First 1
                if ($match) {
                    WriteLog "DriverMapping: Viglen SystemId '$systemSkuNormalized' matched '$($match.Model)'."
                    return $match
                }
            }
            WriteLog 'DriverMapping: Viglen SystemId not detected or not present in mapping.'
            return $null
        }
        'AZW' {
            if (-not [string]::IsNullOrWhiteSpace($systemSkuNormalized)) {
                $match = $rulesForMake | Where-Object { $_.PSObject.Properties['SystemId'] -and $_.SystemId.Trim().ToUpperInvariant() -eq $systemSkuNormalized } | Select-Object -First 1
                if ($match) {
                    WriteLog "DriverMapping: AZW SystemId '$systemSkuNormalized' matched '$($match.Model)'."
                    return $match
                }
            }
            WriteLog 'DriverMapping: AZW SystemId not detected or not present in mapping.'
            return $null
        }
        'Fujitsu' {
            if (-not [string]::IsNullOrWhiteSpace($systemSkuNormalized)) {
                $match = $rulesForMake | Where-Object { $_.PSObject.Properties['SystemId'] -and $_.SystemId.Trim().ToUpperInvariant() -eq $systemSkuNormalized } | Select-Object -First 1
                if ($match) {
                    WriteLog "DriverMapping: Fujitsu SystemId '$systemSkuNormalized' matched '$($match.Model)'."
                    return $match
                }
            }
            WriteLog 'DriverMapping: Fujitsu SystemId not detected or not present in mapping.'
            return $null
        }
        'Getac' {
            if (-not [string]::IsNullOrWhiteSpace($systemSkuNormalized)) {
                $match = $rulesForMake | Where-Object { $_.PSObject.Properties['SystemId'] -and $_.SystemId.Trim().ToUpperInvariant() -eq $systemSkuNormalized } | Select-Object -First 1
                if ($match) {
                    WriteLog "DriverMapping: Getac SystemId '$systemSkuNormalized' matched '$($match.Model)'."
                    return $match
                }
            }
            WriteLog 'DriverMapping: Getac SystemId not detected or not present in mapping.'
            return $null
        }
        'Intel' {
            foreach ($rule in $rulesForMake) {
                if (-not $rule.PSObject.Properties['Model']) { continue }
                $ruleModelNorm = ConvertTo-ComparableModelName -Text $rule.Model
                if (-not [string]::IsNullOrWhiteSpace($ruleModelNorm) -and $ruleModelNorm -eq $normalizedModel) {
                    WriteLog "DriverMapping: Intel model '$normalizedModel' matched '$($rule.Model)'."
                    return $rule
                }
            }
            WriteLog 'DriverMapping: Intel model not detected or not present in mapping.'
            return $null
        }
        'ByteSpeed' {
            foreach ($rule in $rulesForMake) {
                if (-not $rule.PSObject.Properties['Model']) { continue }
                $ruleModelNorm = ConvertTo-ComparableModelName -Text $rule.Model
                if (-not [string]::IsNullOrWhiteSpace($ruleModelNorm) -and $ruleModelNorm -eq $normalizedModel) {
                    WriteLog "DriverMapping: ByteSpeed model '$normalizedModel' matched '$($rule.Model)'."
                    return $rule
                }
            }
            WriteLog 'DriverMapping: ByteSpeed model not detected or not present in mapping.'
            return $null
        }
        default {
            # Generic fallback for manufacturers without explicit handling
            foreach ($rule in $rulesForMake) {
                if (-not $rule.PSObject.Properties['Model']) { continue }
                $ruleModelNorm = ConvertTo-ComparableModelName -Text $rule.Model
                if (-not [string]::IsNullOrWhiteSpace($ruleModelNorm) -and $ruleModelNorm -eq $normalizedModel) {
                    WriteLog "DriverMapping: Manufacturer '$normalizedManufacturer' model '$normalizedModel' matched '$($rule.Model)'."
                    return $rule
                }
            }
            WriteLog "DriverMapping: No generic match found for manufacturer '$normalizedManufacturer' using model '$normalizedModel'."
            return $null
        }
    }
}

function Stop-Script {
    param(
        [string]$Message
    )
    Write-Host "`n"
    if (-not [string]::IsNullOrWhiteSpace($Message)) {
        Write-Error -Message $Message
    }
    WriteLog "Copying dism log to $USBDrive"
    Invoke-Process xcopy "X:\Windows\logs\dism\dism.log $USBDrive /Y" 
    WriteLog "Copying dism log to $USBDrive succeeded"
    Read-Host "Press Enter to exit"
    Exit
}

function ConvertTo-ComparableModelName {
    [CmdletBinding()]
    param(
        [string]$Text
    )
    # Normalize model strings with HP-specific adjustments.
    # Remove inch unit variants (23.8-in, 23.8 inch, 23inch, 23-in, etc.) keeping only the numeric size.
    # Canonicalize All-in-One variants (All in One, All-in-One, All-in-One PC, AiO, AIO) to 'AIO'.
    # Convert any non-alphanumeric sequence to a single space, collapse whitespace, and trim.
    if ($null -eq $Text) { return '' }
    $original = $Text
    # Remove inch unit variants while preserving the numeric size
    $Text = [regex]::Replace($Text, '(?i)(\d+(?:\.\d+)?)(?:\s*[-]?\s*)(?:in|inch)\b', '$1')
    # Canonicalize All-in-One variants
    $Text = [regex]::Replace($Text, '(?i)\bAll[\s-]*in[\s-]*One(?:\s*PC)?\b', 'AIO')
    $Text = [regex]::Replace($Text, '(?i)\bAiO\b', 'AIO')
    # Generic normalization
    $normalized = ($Text -replace '[^A-Za-z0-9]+', ' ')
    $normalized = ($normalized -replace '\s+', ' ').Trim()
    if ($normalized -ne $original) {
        WriteLog "Normalized model string: Original='$original' -> Normalized='$normalized'"
    }
    return $normalized
}
    
function Test-DriverFolderHasInstallableContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    if (-not (Test-Path -Path $Path -PathType Container)) {
        return $false
    }
    
    try {
        $nonWimFile = Get-ChildItem -Path $Path -File -Recurse -ErrorAction Stop | Where-Object {
            $extension = $_.Extension
            if ([string]::IsNullOrWhiteSpace($extension)) {
                return $true
            }
            return $extension.ToLowerInvariant() -ne '.wim'
        } | Select-Object -First 1
    
        if ($nonWimFile) {
            return $true
        }
    
        return $false
    }
    catch {
        WriteLog "Failed to inspect driver folder '$Path': $($_.Exception.Message)"
        return $false
    }
}
    
function Get-AvailableDriveLetter {
    $usedLetters = (Get-PSDrive -PSProvider FileSystem).Name | ForEach-Object { $_.ToUpperInvariant() }
    for ($ascii = [int][char]'Z'; $ascii -ge [int][char]'A'; $ascii--) {
        $candidate = [char]$ascii
        if ($usedLetters -notcontains $candidate) {
            return $candidate
        }
    }
    return $null
}
    
function New-SecureBootDiagnosticsFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$UsbDrive
    )

    # Create a per-run diagnostics folder on the deployment media.
    try {
        $diagnosticsRoot = Join-Path -Path $UsbDrive -ChildPath 'SecureBootDiagnostics'
        New-Item -Path $diagnosticsRoot -ItemType Directory -Force -ErrorAction Stop | Out-Null

        $folderName = 'Run_' + (Get-Date -Format 'yyyyMMdd_HHmmss')
        $diagnosticsPath = Join-Path -Path $diagnosticsRoot -ChildPath $folderName
        $suffix = 1
        while (Test-Path -Path $diagnosticsPath) {
            $diagnosticsPath = Join-Path -Path $diagnosticsRoot -ChildPath ("{0}_{1}" -f $folderName, $suffix)
            $suffix++
        }

        New-Item -Path $diagnosticsPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        WriteLog "Secure Boot diagnostics folder: $diagnosticsPath"
        return $diagnosticsPath
    }
    catch {
        WriteLog "Warning: Failed to create Secure Boot diagnostics folder. $($_.Exception.Message)"
        return $null
    }
}

function New-DiagnosticsStageFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DiagnosticsRoot,
        [Parameter(Mandatory = $true)]
        [string]$StageName
    )

    # Create a stage-specific folder for collected artifacts.
    try {
        if ([string]::IsNullOrWhiteSpace($DiagnosticsRoot)) {
            return $null
        }

        $stagePath = Join-Path -Path $DiagnosticsRoot -ChildPath $StageName
        New-Item -Path $stagePath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        return $stagePath
    }
    catch {
        WriteLog "Warning: Failed to create diagnostics stage folder '$StageName'. $($_.Exception.Message)"
        return $null
    }
}

function Write-DiagnosticsTextFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [Parameter()]
        [AllowNull()]
        [object]$Content
    )

    # Persist text diagnostics without affecting deployment flow.
    try {
        $directoryPath = Split-Path -Path $FilePath -Parent
        if (-not [string]::IsNullOrWhiteSpace($directoryPath)) {
            New-Item -Path $directoryPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }

        if ($null -eq $Content) {
            $Content = ''
        }

        Set-Content -Path $FilePath -Value $Content -Encoding UTF8 -Force -ErrorAction Stop
    }
    catch {
        WriteLog "Warning: Failed to write diagnostics file '$FilePath'. $($_.Exception.Message)"
    }
}

function Get-ByteArraySha256 {
    [CmdletBinding()]
    param(
        [byte[]]$Bytes
    )

    # Calculate a stable hash for raw EFI variable data.
    if ($null -eq $Bytes) {
        return $null
    }

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return (($sha256.ComputeHash($Bytes) | ForEach-Object { $_.ToString('x2') }) -join '')
    }
    finally {
        $sha256.Dispose()
    }
}

function Get-ByteArrayAsciiMarker {
    [CmdletBinding()]
    param(
        [byte[]]$Bytes
    )

    # Look for obvious ASCII markers inside EFI variable data.
    if ($null -eq $Bytes -or $Bytes.Length -eq 0) {
        return $null
    }

    $asciiText = [System.Text.Encoding]::ASCII.GetString($Bytes)
    $markers = @(
        'Windows UEFI CA 2023',
        'Windows UEFI CA 2011',
        'Microsoft Corporation UEFI CA 2011',
        'Microsoft Corporation KEK CA 2011',
        'Microsoft Windows Production PCA 2011',
        'Microsoft'
    )

    foreach ($marker in $markers) {
        if ($asciiText -match [regex]::Escape($marker)) {
            return $marker
        }
    }

    return $null
}

function Open-EspPartitionAccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$DiskNumber
    )

    # Assign a temporary drive letter to the EFI system partition when needed.
    try {
        $espPartition = Get-Partition -DiskNumber $DiskNumber -ErrorAction Stop | Where-Object {
            $_.Type -eq 'System' -or $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'
        } | Select-Object -First 1

        if ($null -eq $espPartition) {
            WriteLog "Warning: EFI system partition not found on disk $DiskNumber."
            return $null
        }

        if ($espPartition.DriveLetter) {
            $driveLetter = $espPartition.DriveLetter.ToString().ToUpperInvariant()
            return [PSCustomObject]@{
                DiskNumber       = $DiskNumber
                PartitionNumber  = $espPartition.PartitionNumber
                DriveLetter      = $driveLetter
                DrivePath        = "$driveLetter`:\"
                RemoveAccessPath = $false
            }
        }

        $driveLetter = Get-AvailableDriveLetter
        if ($null -eq $driveLetter) {
            WriteLog 'Warning: No drive letters are available to mount the EFI system partition.'
            return $null
        }

        Set-Partition -InputObject $espPartition -NewDriveLetter $driveLetter -ErrorAction Stop
        WriteLog "Assigned temporary drive letter $driveLetter`: to the EFI system partition."

        return [PSCustomObject]@{
            DiskNumber       = $DiskNumber
            PartitionNumber  = $espPartition.PartitionNumber
            DriveLetter      = $driveLetter
            DrivePath        = "$driveLetter`:\"
            RemoveAccessPath = $true
        }
    }
    catch {
        WriteLog "Warning: Failed to access the EFI system partition on disk $DiskNumber. $($_.Exception.Message)"
        return $null
    }
}

function Close-EspPartitionAccess {
    [CmdletBinding()]
    param(
        [Parameter()]
        [pscustomobject]$EspAccess
    )

    # Remove a temporary EFI access path after diagnostics complete.
    if ($null -eq $EspAccess -or $EspAccess.RemoveAccessPath -ne $true) {
        return
    }

    try {
        Get-Partition -DiskNumber $EspAccess.DiskNumber -ErrorAction Stop |
            Where-Object { $_.PartitionNumber -eq $EspAccess.PartitionNumber } |
            Remove-PartitionAccessPath -AccessPath "$($EspAccess.DriveLetter):" -ErrorAction Stop

        WriteLog "Removed temporary drive letter $($EspAccess.DriveLetter): from the EFI system partition."
    }
    catch {
        WriteLog "Warning: Failed to remove temporary EFI access path $($EspAccess.DriveLetter):. $($_.Exception.Message)"
    }
}

function Save-StorageSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$StageName,
        [Parameter(Mandatory = $true)]
        [string]$StagePath,
        [Parameter(Mandatory = $true)]
        [int]$DiskNumber
    )

    # Capture disk, partition, and volume state for the selected target disk.
    try {
        $storagePath = Join-Path -Path $StagePath -ChildPath 'Storage'
        New-Item -Path $storagePath -ItemType Directory -Force -ErrorAction Stop | Out-Null

        $disk = Get-Disk -Number $DiskNumber -ErrorAction Stop
        $partitions = @(Get-Partition -DiskNumber $DiskNumber -ErrorAction Stop | Sort-Object PartitionNumber)
        $partitionTable = @(
            $partitions | Select-Object `
                PartitionNumber,
                DriveLetter,
                Type,
                GptType,
                @{ Name = 'SizeGB'; Expression = { if ($_.Size) { [math]::Round(($_.Size / 1GB), 2) } else { $null } } }
        )

        $volumeRecords = @()
        foreach ($partition in $partitions) {
            $partitionVolume = $null

            if ($partition.DriveLetter) {
                try {
                    $partitionVolume = Get-Volume -DriveLetter $partition.DriveLetter -ErrorAction Stop
                }
                catch {
                    $partitionVolume = $null
                }
            }

            $volumeRecords += [PSCustomObject]@{
                PartitionNumber = $partition.PartitionNumber
                DriveLetter     = $partition.DriveLetter
                FileSystem      = if ($partitionVolume) { $partitionVolume.FileSystem } else { $null }
                FileSystemLabel = if ($partitionVolume) { $partitionVolume.FileSystemLabel } else { $null }
                HealthStatus    = if ($partitionVolume) { $partitionVolume.HealthStatus } else { $null }
                SizeGB          = if ($partitionVolume -and $partitionVolume.Size) { [math]::Round(($partitionVolume.Size / 1GB), 2) } else { $null }
                FreeGB          = if ($partitionVolume -and $partitionVolume.SizeRemaining) { [math]::Round(($partitionVolume.SizeRemaining / 1GB), 2) } else { $null }
            }
        }

        Write-DiagnosticsTextFile -FilePath (Join-Path -Path $storagePath -ChildPath 'disk.txt') -Content (($disk | Format-List * | Out-String).Trim())
        Write-DiagnosticsTextFile -FilePath (Join-Path -Path $storagePath -ChildPath 'partitions.txt') -Content (($partitionTable | Format-Table -AutoSize | Out-String).Trim())
        Write-DiagnosticsTextFile -FilePath (Join-Path -Path $storagePath -ChildPath 'volumes.txt') -Content (($volumeRecords | Format-Table -AutoSize | Out-String).Trim())

        WriteLog "Storage snapshot [$StageName]: Disk=$DiskNumber; Partitions=$($partitions.Count); Volumes=$($volumeRecords.Count)."
    }
    catch {
        WriteLog "Warning: Failed to capture storage snapshot [$StageName] for disk $DiskNumber. $($_.Exception.Message)"
    }
}

function Get-CertificateSha256 {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
    )

    # Hash a certificate's DER bytes for comparison with db/dbx entries.
    if ($null -eq $Certificate) {
        return $null
    }

    return Get-ByteArraySha256 -Bytes $Certificate.RawData
}

function Get-ByteArrayHexString {
    [CmdletBinding()]
    param(
        [byte[]]$Bytes,
        [string]$Delimiter = ''
    )

    # Convert bytes to uppercase hexadecimal for readable reports and comparisons.
    if ($null -eq $Bytes) {
        return $null
    }

    return (($Bytes | ForEach-Object { $_.ToString('X2') }) -join $Delimiter)
}

function Get-EfiGuidString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes,
        [Parameter(Mandatory = $true)]
        [int]$Offset
    )

    # Read an EFI_GUID from a byte array at the specified offset.
    if ($Offset -lt 0 -or ($Offset + 16) -gt $Bytes.Length) {
        return $null
    }

    $guidBytes = [byte[]]::new(16)
    [Array]::Copy($Bytes, $Offset, $guidBytes, 0, 16)

    try {
        return ([System.Guid]::new($guidBytes)).Guid
    }
    catch {
        return $null
    }
}

function Get-EfiSignatureTypeName {
    [CmdletBinding()]
    param(
        [string]$SignatureTypeGuid
    )

    # Map well-known EFI signature type GUIDs to friendly names.
    if ([string]::IsNullOrWhiteSpace($SignatureTypeGuid)) {
        return 'UNKNOWN'
    }

    switch ($SignatureTypeGuid.ToLowerInvariant()) {
        'a5c059a1-94e4-4aa7-87b5-ab155c2bf072' { return 'EFI_CERT_X509' }
        'c1c41626-504c-4092-aca9-41f936934328' { return 'EFI_CERT_SHA256' }
        '3bd2a492-96c0-4079-b420-fcf98ef103ed' { return 'EFI_CERT_X509_SHA256' }
        '826ca512-cf10-4ac9-b187-be01496631bd' { return 'EFI_CERT_SHA1' }
        '67f8444f-8743-48f1-a328-1eaab8736080' { return 'EFI_CERT_SHA224' }
        'ff3e5307-9fd0-48c9-85f1-8ad56c701e01' { return 'EFI_CERT_SHA384' }
        '093e0fae-a6c4-4f50-9f1b-d41e2b89c19a' { return 'EFI_CERT_SHA512' }
        default { return 'UNKNOWN' }
    }
}

function Get-EfiSignatureDatabaseEntries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes,
        [Parameter(Mandatory = $true)]
        [string]$VariableName
    )

    # Parse EFI signature database bytes into typed entries.
    $parsedEntries = [System.Collections.Generic.List[object]]::new()

    if ($null -eq $Bytes -or $Bytes.Length -lt 28) {
        return @()
    }

    $offset = 0
    $listIndex = 0

    while (($offset + 28) -le $Bytes.Length) {
        $listIndex++

        $signatureTypeGuid = Get-EfiGuidString -Bytes $Bytes -Offset $offset
        $signatureListSize = [BitConverter]::ToUInt32($Bytes, $offset + 16)
        $signatureHeaderSize = [BitConverter]::ToUInt32($Bytes, $offset + 20)
        $signatureSize = [BitConverter]::ToUInt32($Bytes, $offset + 24)

        if ([string]::IsNullOrWhiteSpace($signatureTypeGuid) -or $signatureListSize -lt 28 -or $signatureSize -lt 16 -or ($offset + $signatureListSize) -gt $Bytes.Length) {
            break
        }

        $signatureTypeName = Get-EfiSignatureTypeName -SignatureTypeGuid $signatureTypeGuid
        $entryStartOffset = $offset + 28 + $signatureHeaderSize
        $usableBytes = $signatureListSize - 28 - $signatureHeaderSize
        if ($usableBytes -lt 0) {
            break
        }

        $entryCount = if ($signatureSize -gt 0) { [int][math]::Floor($usableBytes / $signatureSize) } else { 0 }

        for ($entryIndex = 0; $entryIndex -lt $entryCount; $entryIndex++) {
            $currentOffset = $entryStartOffset + ($entryIndex * $signatureSize)
            if (($currentOffset + $signatureSize) -gt ($offset + $signatureListSize)) {
                break
            }

            $signatureOwnerGuid = Get-EfiGuidString -Bytes $Bytes -Offset $currentOffset
            $signatureDataLength = [int]$signatureSize - 16
            if ($signatureDataLength -lt 0) {
                continue
            }

            $signatureData = [byte[]]::new($signatureDataLength)
            [Array]::Copy($Bytes, $currentOffset + 16, $signatureData, 0, $signatureDataLength)

            $entry = [ordered]@{
                VariableName         = $VariableName
                SignatureListIndex   = $listIndex
                SignatureEntryIndex  = $entryIndex + 1
                SignatureTypeGuid    = $signatureTypeGuid
                SignatureTypeName    = $signatureTypeName
                SignatureOwnerGuid   = $signatureOwnerGuid
                SignatureDataLength  = $signatureDataLength
                HashHex              = $null
                CertificateSubject   = $null
                CertificateIssuer    = $null
                CertificateNotBefore = $null
                CertificateNotAfter  = $null
                CertificateThumbprint = $null
                CertificateSha256    = $null
                DataSha256           = $null
                EntrySummary         = $null
            }

            switch ($signatureTypeName) {
                'EFI_CERT_X509' {
                    try {
                        $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($signatureData)
                        $entry.CertificateSubject = $certificate.Subject
                        $entry.CertificateIssuer = $certificate.Issuer
                        $entry.CertificateNotBefore = $certificate.NotBefore.ToString('yyyy-MM-dd HH:mm:ss')
                        $entry.CertificateNotAfter = $certificate.NotAfter.ToString('yyyy-MM-dd HH:mm:ss')
                        $entry.CertificateThumbprint = $certificate.Thumbprint
                        $entry.CertificateSha256 = Get-CertificateSha256 -Certificate $certificate
                        $entry.EntrySummary = "CertificateSubject=$($entry.CertificateSubject)"
                    }
                    catch {
                        $entry.DataSha256 = Get-ByteArraySha256 -Bytes $signatureData
                        $entry.EntrySummary = "CertificateParseError=$($_.Exception.Message)"
                    }
                }
                'EFI_CERT_SHA256' {
                    $entry.HashHex = Get-ByteArrayHexString -Bytes $signatureData
                    $entry.EntrySummary = "ImageHash=$($entry.HashHex)"
                }
                'EFI_CERT_X509_SHA256' {
                    $entry.HashHex = Get-ByteArrayHexString -Bytes $signatureData
                    $entry.EntrySummary = "CertificateHash=$($entry.HashHex)"
                }
                default {
                    $entry.DataSha256 = Get-ByteArraySha256 -Bytes $signatureData
                    $entry.EntrySummary = "DataSha256=$($entry.DataSha256)"
                }
            }

            $parsedEntries.Add([PSCustomObject]$entry) | Out-Null
        }

        if ($signatureListSize -le 0) {
            break
        }

        $offset += [int]$signatureListSize
    }

    return @($parsedEntries)
}

function Write-EfiSignatureDatabaseReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VariableName,
        [Parameter(Mandatory = $true)]
        [object[]]$Entries,
        [Parameter(Mandatory = $true)]
        [string]$ReportPath
    )

    # Write a readable parsed report and a smaller summary for EFI signature database entries.
    $summaryPath = Join-Path -Path (Split-Path -Path $ReportPath -Parent) -ChildPath "${VariableName}_summary.txt"
    $typeGroups = @($Entries | Group-Object SignatureTypeName | Sort-Object Name)
    $ownerGroups = @($Entries | Where-Object { -not [string]::IsNullOrWhiteSpace($_.SignatureOwnerGuid) } | Group-Object SignatureOwnerGuid | Sort-Object Name)
    $hashEntries = @($Entries | Where-Object { -not [string]::IsNullOrWhiteSpace($_.HashHex) })
    $uniqueHashCount = @($hashEntries | Select-Object -ExpandProperty HashHex -Unique).Count
    $duplicateHashGroups = @(
        $hashEntries |
            Group-Object HashHex |
            Where-Object { $_.Count -gt 1 } |
            Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, @{ Expression = 'Name'; Descending = $false }
    )
    $duplicateHashValueCount = $duplicateHashGroups.Count
    $duplicateHashEntryCount = if ($duplicateHashGroups.Count -gt 0) { ($duplicateHashGroups | Measure-Object -Property Count -Sum).Sum } else { 0 }

    $reportLines = @(
        "VariableName: $VariableName"
        "ParsedEntryCount: $($Entries.Count)"
        "UniqueHashCount: $uniqueHashCount"
        "DuplicateHashValueCount: $duplicateHashValueCount"
        "DuplicateHashEntryCount: $duplicateHashEntryCount"
        "OwnerGuidCount: $($ownerGroups.Count)"
    )

    $summaryLines = @(
        "VariableName: $VariableName"
        "ParsedEntryCount: $($Entries.Count)"
        "UniqueHashCount: $uniqueHashCount"
        "DuplicateHashValueCount: $duplicateHashValueCount"
        "DuplicateHashEntryCount: $duplicateHashEntryCount"
        "OwnerGuidCount: $($ownerGroups.Count)"
    )

    if ($Entries.Count -gt 0) {
        $reportLines += ''
        $reportLines += 'ParsedTypeCounts:'
        $summaryLines += ''
        $summaryLines += 'ParsedTypeCounts:'
        foreach ($typeGroup in $typeGroups) {
            $reportLines += "$($typeGroup.Name): $($typeGroup.Count)"
            $summaryLines += "$($typeGroup.Name): $($typeGroup.Count)"
        }

        $reportLines += ''
        $reportLines += 'OwnerGuidCounts:'
        $summaryLines += ''
        $summaryLines += 'OwnerGuidCounts:'
        if ($ownerGroups.Count -gt 0) {
            foreach ($ownerGroup in $ownerGroups) {
                $reportLines += "$($ownerGroup.Name): $($ownerGroup.Count)"
                $summaryLines += "$($ownerGroup.Name): $($ownerGroup.Count)"
            }
        }
        else {
            $reportLines += '<none>'
            $summaryLines += '<none>'
        }

        $reportLines += ''
        $reportLines += 'DuplicateHashes:'
        $summaryLines += ''
        $summaryLines += 'DuplicateHashes:'
        if ($duplicateHashGroups.Count -gt 0) {
            foreach ($duplicateHashGroup in $duplicateHashGroups) {
                $reportLines += "$($duplicateHashGroup.Name): $($duplicateHashGroup.Count)"
                $summaryLines += "$($duplicateHashGroup.Name): $($duplicateHashGroup.Count)"
            }
        }
        else {
            $reportLines += '<none>'
            $summaryLines += '<none>'
        }

        $reportLines += ''
        $reportLines += 'Entries:'
        foreach ($entry in $Entries) {
            $reportLines += "[List $($entry.SignatureListIndex), Entry $($entry.SignatureEntryIndex)] Type=$($entry.SignatureTypeName) ($($entry.SignatureTypeGuid))"
            $reportLines += "SignatureOwnerGuid: $($entry.SignatureOwnerGuid)"
            $reportLines += "SignatureDataLength: $($entry.SignatureDataLength)"

            if ($entry.CertificateSubject) {
                $reportLines += "CertificateSubject: $($entry.CertificateSubject)"
                $reportLines += "CertificateIssuer: $($entry.CertificateIssuer)"
                $reportLines += "CertificateNotBefore: $($entry.CertificateNotBefore)"
                $reportLines += "CertificateNotAfter: $($entry.CertificateNotAfter)"
                $reportLines += "CertificateThumbprint: $($entry.CertificateThumbprint)"
                $reportLines += "CertificateSha256: $($entry.CertificateSha256)"
            }
            elseif ($entry.HashHex) {
                $reportLines += "HashHex: $($entry.HashHex)"
            }
            else {
                $reportLines += "DataSha256: $($entry.DataSha256)"
            }

            if ($entry.EntrySummary) {
                $reportLines += "EntrySummary: $($entry.EntrySummary)"
            }

            $reportLines += ''
        }
    }
    else {
        $reportLines += ''
        $reportLines += 'ParsedTypeCounts: <none>'
        $reportLines += ''
        $reportLines += 'OwnerGuidCounts: <none>'
        $reportLines += ''
        $reportLines += 'DuplicateHashes: <none>'
        $reportLines += ''
        $reportLines += 'Entries: <none>'

        $summaryLines += ''
        $summaryLines += 'ParsedTypeCounts: <none>'
        $summaryLines += ''
        $summaryLines += 'OwnerGuidCounts: <none>'
        $summaryLines += ''
        $summaryLines += 'DuplicateHashes: <none>'
    }

    Write-DiagnosticsTextFile -FilePath $ReportPath -Content $reportLines
    Write-DiagnosticsTextFile -FilePath $summaryPath -Content $summaryLines
}

function Save-SecureBootVariableDiagnostics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$StageName,
        [Parameter(Mandatory = $true)]
        [string]$FirmwarePath,
        [Parameter(Mandatory = $true)]
        [string]$VariableName
    )

    # Export raw Secure Boot variable data and parse EFI signature database entries when available.
    $textPath = Join-Path -Path $FirmwarePath -ChildPath "$VariableName.txt"
    $parsedReportPath = Join-Path -Path $FirmwarePath -ChildPath "${VariableName}_parsed.txt"

    if ($null -eq (Get-Command -Name Get-SecureBootUEFI -ErrorAction SilentlyContinue)) {
        Write-DiagnosticsTextFile -FilePath $textPath -Content 'Get-SecureBootUEFI is not available.'
        Write-DiagnosticsTextFile -FilePath $parsedReportPath -Content 'Get-SecureBootUEFI is not available.'
        WriteLog "Secure Boot variable [$StageName] $VariableName unavailable: Get-SecureBootUEFI not available."
        return $null
    }

    try {
        try {
            $variable = Get-SecureBootUEFI -Name $VariableName -ErrorAction Stop
        }
        catch [System.Management.Automation.ParameterBindingException] {
            $variable = Get-SecureBootUEFI $VariableName -ErrorAction Stop
        }

        $bytes = [byte[]]@()

        if ($variable -and $variable.PSObject.Properties['Bytes']) {
            $bytes = [byte[]]$variable.Bytes
        }
        elseif ($variable -and $variable.PSObject.Properties['Content']) {
            $bytes = [byte[]]$variable.Content
        }

        $binPath = Join-Path -Path $FirmwarePath -ChildPath "$VariableName.bin"
        [System.IO.File]::WriteAllBytes($binPath, $bytes)

        $sha256 = Get-ByteArraySha256 -Bytes $bytes
        $marker = Get-ByteArrayAsciiMarker -Bytes $bytes
        $markerText = if ($marker) { $marker } else { '<none>' }
        $parsedEntries = @(Get-EfiSignatureDatabaseEntries -Bytes $bytes -VariableName $VariableName)
        $typeSummaryText = if ($parsedEntries.Count -gt 0) {
            (($parsedEntries | Group-Object SignatureTypeName | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join '; ')
        }
        else {
            '<none>'
        }

        $hashEntries = @($parsedEntries | Where-Object { -not [string]::IsNullOrWhiteSpace($_.HashHex) })
        $uniqueHashCount = @($hashEntries | Select-Object -ExpandProperty HashHex -Unique).Count
        $duplicateHashValueCount = @($hashEntries | Group-Object HashHex | Where-Object { $_.Count -gt 1 }).Count
        $ownerGuidCount = @($parsedEntries | Where-Object { -not [string]::IsNullOrWhiteSpace($_.SignatureOwnerGuid) } | Group-Object SignatureOwnerGuid).Count

        $summaryLines = @(
            "VariableName: $VariableName"
            "ByteCount: $($bytes.Length)"
            "SHA256: $sha256"
            "AsciiMarker: $markerText"
            "ParsedEntryCount: $($parsedEntries.Count)"
            "ParsedTypeCounts: $typeSummaryText"
            "UniqueHashCount: $uniqueHashCount"
            "DuplicateHashValueCount: $duplicateHashValueCount"
            "OwnerGuidCount: $ownerGuidCount"
            ''
            'Details:'
            ($variable | Format-List * | Out-String).TrimEnd()
        )

        Write-DiagnosticsTextFile -FilePath $textPath -Content $summaryLines
        Write-EfiSignatureDatabaseReport -VariableName $VariableName -Entries $parsedEntries -ReportPath $parsedReportPath
        WriteLog "Secure Boot variable [$StageName] $($VariableName): Bytes=$($bytes.Length); SHA256=$sha256; Marker=$markerText; ParsedEntries=$($parsedEntries.Count); ParsedTypes=$typeSummaryText; UniqueHashes=$uniqueHashCount; DuplicateHashValues=$duplicateHashValueCount; OwnerGuidCount=$ownerGuidCount."

        return [PSCustomObject]@{
            VariableName  = $VariableName
            Bytes         = $bytes
            Sha256        = $sha256
            Marker        = $markerText
            ParsedEntries = $parsedEntries
        }
    }
    catch {
        Write-DiagnosticsTextFile -FilePath $textPath -Content "Error: $($_.Exception.Message)"
        Write-DiagnosticsTextFile -FilePath $parsedReportPath -Content "Error: $($_.Exception.Message)"
        WriteLog "Secure Boot variable [$StageName] $($VariableName) unavailable: $($_.Exception.Message)"
        return $null
    }
}

function Save-FirmwareSecureBootDiagnostics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$StageName,
        [Parameter(Mandatory = $true)]
        [string]$StagePath
    )

    # Collect firmware and Secure Boot state without affecting deployment flow.
    $firmwarePath = Join-Path -Path $StagePath -ChildPath 'Firmware'
    try {
        New-Item -Path $firmwarePath -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
    catch {
        WriteLog "Warning: Failed to create firmware diagnostics folder for stage $StageName. $($_.Exception.Message)"
        return $null
    }

    $summaryLines = @(
        "Stage: $StageName"
        "Timestamp: $(Get-Date -Format 's')"
    )

    try {
        $controlValues = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name PEFirmwareType -ErrorAction Stop
        $peFirmwareType = $controlValues.PEFirmwareType
        $peFirmwareTypeText = switch ($peFirmwareType) {
            1 { 'BIOS' }
            2 { 'UEFI' }
            default { 'Unknown' }
        }

        $summaryLines += "PEFirmwareType: $peFirmwareType ($peFirmwareTypeText)"
        WriteLog "Firmware state [$StageName]: PEFirmwareType=$peFirmwareType ($peFirmwareTypeText)."
    }
    catch {
        $summaryLines += 'PEFirmwareType: <unavailable>'
        WriteLog "Firmware state [$StageName]: PEFirmwareType unavailable. $($_.Exception.Message)"
    }

    if ($null -ne (Get-Command -Name Confirm-SecureBootUEFI -ErrorAction SilentlyContinue)) {
        try {
            $confirmResult = Confirm-SecureBootUEFI -ErrorAction Stop
            $summaryLines += "Confirm-SecureBootUEFI: $confirmResult"
            WriteLog "Firmware state [$StageName]: Confirm-SecureBootUEFI=$confirmResult."
        }
        catch {
            $summaryLines += "Confirm-SecureBootUEFI: <error> $($_.Exception.Message)"
            WriteLog "Firmware state [$StageName]: Confirm-SecureBootUEFI failed. $($_.Exception.Message)"
        }
    }
    else {
        $summaryLines += 'Confirm-SecureBootUEFI: <cmdlet unavailable>'
        WriteLog "Firmware state [$StageName]: Confirm-SecureBootUEFI not available."
    }

    Write-DiagnosticsTextFile -FilePath (Join-Path -Path $firmwarePath -ChildPath 'firmware-summary.txt') -Content $summaryLines

    $variableEvidence = [ordered]@{}
    foreach ($variableName in @('PK', 'KEK', 'db', 'dbx')) {
        $currentVariableEvidence = Save-SecureBootVariableDiagnostics -StageName $StageName -FirmwarePath $firmwarePath -VariableName $variableName
        if ($null -ne $currentVariableEvidence) {
            $variableEvidence[$variableName] = $currentVariableEvidence
        }
    }

    return [PSCustomObject]$variableEvidence
}

function Get-CertificateChainEvidence {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
    )

    # Build a best-effort certificate chain and look for 2011 or 2023 markers.
    $result = [PSCustomObject]@{
        Marker                = '<none>'
        BuildSucceeded        = $false
        ChainStatusText       = '<none>'
        ChainElementText      = @()
        ChainCertificateHashes = @()
    }

    if ($null -eq $Certificate) {
        return $result
    }

    $markerCandidates = @(
        'Windows UEFI CA 2023',
        'Windows UEFI CA 2011',
        'Microsoft Corporation UEFI CA 2011',
        'Microsoft Corporation KEK CA 2011',
        'Microsoft Windows Production PCA 2011',
        'Microsoft Windows'
    )

    $chain = [System.Security.Cryptography.X509Certificates.X509Chain]::new()
    try {
        # Avoid revocation/network dependencies in WinPE while still building the local chain.
        $chain.ChainPolicy.RevocationMode = [System.Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
        $chain.ChainPolicy.VerificationFlags = [System.Security.Cryptography.X509Certificates.X509VerificationFlags]::IgnoreEndRevocationUnknown
        $result.BuildSucceeded = $chain.Build($Certificate)

        $chainStatusLines = @()
        foreach ($chainStatus in $chain.ChainStatus) {
            $statusInformation = $chainStatus.StatusInformation
            if (-not [string]::IsNullOrWhiteSpace($statusInformation)) {
                $chainStatusLines += "$($chainStatus.Status): $($statusInformation.Trim())"
            }
        }

        if ($chainStatusLines.Count -gt 0) {
            $result.ChainStatusText = $chainStatusLines -join ' | '
        }

        $elementLines = @()
        $chainCertificateHashes = @()
        $index = 0
        foreach ($chainElement in $chain.ChainElements) {
            $index++
            $chainCertificate = $chainElement.Certificate
            $certificateSha256 = Get-CertificateSha256 -Certificate $chainCertificate
            if ($certificateSha256) {
                $chainCertificateHashes += $certificateSha256
            }

            $elementLines += "[{0}] Subject={1}; Issuer={2}; Thumbprint={3}; NotBefore={4}; NotAfter={5}; CertificateSha256={6}" -f `
                $index, `
                $chainCertificate.Subject, `
                $chainCertificate.Issuer, `
                $chainCertificate.Thumbprint, `
                $chainCertificate.NotBefore.ToString('yyyy-MM-dd HH:mm:ss'), `
                $chainCertificate.NotAfter.ToString('yyyy-MM-dd HH:mm:ss'), `
                $certificateSha256

            if ($result.Marker -eq '<none>') {
                foreach ($markerCandidate in $markerCandidates) {
                    if ($chainCertificate.Subject -match [regex]::Escape($markerCandidate) -or $chainCertificate.Issuer -match [regex]::Escape($markerCandidate)) {
                        $result.Marker = $markerCandidate
                        break
                    }
                }
            }
        }

        $result.ChainElementText = $elementLines
        $result.ChainCertificateHashes = @($chainCertificateHashes)
    }
    catch {
        $result.ChainStatusText = "Error: $($_.Exception.Message)"
    }
    finally {
        $chain.Dispose()
    }

    return $result
}

function Save-BootFileArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$StageName,
        [Parameter(Mandatory = $true)]
        [string]$BootFilesPath,
        [Parameter(Mandatory = $true)]
        [pscustomobject]$BootEntry
    )

    # Capture metadata and a copy of each requested boot-chain file when present.
    $metadataRoot = Join-Path -Path $BootFilesPath -ChildPath 'Metadata'
    $safeFileName = ($BootEntry.CopyRelativePath -replace '[\\/:*?"<>| ]', '_') + '.txt'
    $metadataPath = Join-Path -Path $metadataRoot -ChildPath $safeFileName

    $summaryLines = @(
        "Label: $($BootEntry.Label)"
        "Path: $($BootEntry.Path)"
    )

    if ([string]::IsNullOrWhiteSpace($BootEntry.Path) -or -not (Test-Path -Path $BootEntry.Path -PathType Leaf)) {
        $summaryLines += 'Exists: False'
        Write-DiagnosticsTextFile -FilePath $metadataPath -Content $summaryLines
        WriteLog "Boot file [$StageName] $($BootEntry.CopyRelativePath): Missing."

        return [PSCustomObject]@{
            Label                 = $BootEntry.Label
            CopyRelativePath      = $BootEntry.CopyRelativePath
            Exists                = $false
            FileHash              = $null
            SignatureStatus       = 'Missing'
            CertificateMarker     = '<none>'
            ChainCertificateHashes = @()
        }
    }

    try {
        $fileItem = Get-Item -Path $BootEntry.Path -ErrorAction Stop
        $summaryLines += 'Exists: True'
        $summaryLines += "Size: $($fileItem.Length)"

        $hashValue = $null
        try {
            $hashValue = (Get-FileHash -Path $BootEntry.Path -Algorithm SHA256 -ErrorAction Stop).Hash
        }
        catch {
            $hashValue = $null
        }

        $summaryLines += "SHA256: $(if ($hashValue) { $hashValue } else { '<unavailable>' })"

        $fileVersion = $null
        $productVersion = $null
        if ($fileItem.VersionInfo) {
            $fileVersion = $fileItem.VersionInfo.FileVersion
            $productVersion = $fileItem.VersionInfo.ProductVersion
        }

        $summaryLines += "FileVersion: $(if ($fileVersion) { $fileVersion } else { '<unavailable>' })"
        $summaryLines += "ProductVersion: $(if ($productVersion) { $productVersion } else { '<unavailable>' })"

        $skipSignatureCheck = if ($BootEntry.PSObject.Properties['SkipSignatureCheck']) { [bool]$BootEntry.SkipSignatureCheck } else { $false }

        $signatureStatus = if ($skipSignatureCheck) { '<not applicable>' } else { '<cmdlet unavailable>' }
        $signerSubject = '<none>'
        $signerIssuer = '<none>'
        $signerThumbprint = '<none>'
        $signerNotBefore = '<none>'
        $signerNotAfter = '<none>'
        $certificateMarker = '<none>'
        $chainBuildSucceeded = $false
        $chainStatusText = '<none>'
        $chainElementText = @()
        $chainCertificateHashes = @()

        if (-not $skipSignatureCheck -and $null -ne (Get-Command -Name Get-AuthenticodeSignature -ErrorAction SilentlyContinue)) {
            try {
                $signature = Get-AuthenticodeSignature -FilePath $BootEntry.Path -ErrorAction Stop
                $signatureStatus = [string]$signature.Status

                if ($signature.SignerCertificate) {
                    $signerSubject = $signature.SignerCertificate.Subject
                    $signerIssuer = $signature.SignerCertificate.Issuer
                    $signerThumbprint = $signature.SignerCertificate.Thumbprint
                    $signerNotBefore = $signature.SignerCertificate.NotBefore.ToString('yyyy-MM-dd HH:mm:ss')
                    $signerNotAfter = $signature.SignerCertificate.NotAfter.ToString('yyyy-MM-dd HH:mm:ss')

                    $chainEvidence = Get-CertificateChainEvidence -Certificate $signature.SignerCertificate
                    $certificateMarker = $chainEvidence.Marker
                    $chainBuildSucceeded = $chainEvidence.BuildSucceeded
                    $chainStatusText = $chainEvidence.ChainStatusText
                    $chainElementText = $chainEvidence.ChainElementText
                    $chainCertificateHashes = @($chainEvidence.ChainCertificateHashes | ForEach-Object { $_.ToUpperInvariant() })
                }
            }
            catch {
                $signatureStatus = "<error> $($_.Exception.Message)"
            }
        }

        $summaryLines += "AuthenticodeStatus: $signatureStatus"
        $summaryLines += "SignerSubject: $signerSubject"
        $summaryLines += "SignerIssuer: $signerIssuer"
        $summaryLines += "SignerThumbprint: $signerThumbprint"
        $summaryLines += "SignerNotBefore: $signerNotBefore"
        $summaryLines += "SignerNotAfter: $signerNotAfter"
        $summaryLines += "CertificateMarker: $certificateMarker"
        $summaryLines += "ChainBuildSucceeded: $chainBuildSucceeded"
        $summaryLines += "ChainStatus: $chainStatusText"

        if ($chainElementText.Count -gt 0) {
            $summaryLines += ''
            $summaryLines += 'CertificateChain:'
            $summaryLines += $chainElementText
        }

        $copyPath = Join-Path -Path (Join-Path -Path $BootFilesPath -ChildPath 'Files') -ChildPath $BootEntry.CopyRelativePath
        try {
            New-Item -Path (Split-Path -Path $copyPath -Parent) -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Copy-Item -Path $BootEntry.Path -Destination $copyPath -Force -ErrorAction Stop
            $summaryLines += "CopiedTo: $copyPath"
        }
        catch {
            $summaryLines += 'CopiedTo: <copy failed>'
            $summaryLines += "CopyError: $($_.Exception.Message)"
        }

        Write-DiagnosticsTextFile -FilePath $metadataPath -Content $summaryLines

        $logHash = if ($hashValue) { $hashValue } else { '<unavailable>' }
        WriteLog "Boot file [$StageName] $($BootEntry.CopyRelativePath): Size=$($fileItem.Length); SHA256=$logHash; Signature=$signatureStatus; Marker=$certificateMarker; Signer=$signerSubject."

        return [PSCustomObject]@{
            Label                 = $BootEntry.Label
            CopyRelativePath      = $BootEntry.CopyRelativePath
            Exists                = $true
            FileHash              = if ($hashValue) { $hashValue.ToUpperInvariant() } else { $null }
            SignatureStatus       = $signatureStatus
            CertificateMarker     = $certificateMarker
            ChainCertificateHashes = @($chainCertificateHashes)
        }
    }
    catch {
        $summaryLines += "Error: $($_.Exception.Message)"
        Write-DiagnosticsTextFile -FilePath $metadataPath -Content $summaryLines
        WriteLog "Warning: Failed to inspect boot file [$StageName] $($BootEntry.CopyRelativePath). $($_.Exception.Message)"

        return [PSCustomObject]@{
            Label                 = $BootEntry.Label
            CopyRelativePath      = $BootEntry.CopyRelativePath
            Exists                = $false
            FileHash              = $null
            SignatureStatus       = "<error> $($_.Exception.Message)"
            CertificateMarker     = '<none>'
            ChainCertificateHashes = @()
        }
    }
}

function Save-BootFileDiagnostics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$StageName,
        [Parameter(Mandatory = $true)]
        [string]$StagePath,
        [Parameter(Mandatory = $true)]
        [int]$DiskNumber,
        [Parameter()]
        [string]$WindowsDrivePath = 'W:\'
    )

    # Inspect EFI and OS boot files using a temporary ESP access path when needed.
    $bootFilesPath = Join-Path -Path $StagePath -ChildPath 'BootFiles'
    try {
        New-Item -Path $bootFilesPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
    catch {
        WriteLog "Warning: Failed to create boot-file diagnostics folder for stage $StageName. $($_.Exception.Message)"
        return @()
    }

    $bootEvidence = @()
    $espAccess = Open-EspPartitionAccess -DiskNumber $DiskNumber
    try {
        $espRoot = if ($null -ne $espAccess) { $espAccess.DrivePath } else { $null }

        $bootEntries = @(
            [PSCustomObject]@{
                Label            = 'ESP Microsoft Boot Manager'
                Path             = if ($espRoot) { Join-Path -Path $espRoot -ChildPath 'EFI\Microsoft\Boot\bootmgfw.efi' } else { $null }
                CopyRelativePath = 'ESP\EFI\Microsoft\Boot\bootmgfw.efi'
            },
            [PSCustomObject]@{
                Label            = 'ESP fallback bootx64'
                Path             = if ($espRoot) { Join-Path -Path $espRoot -ChildPath 'EFI\Boot\bootx64.efi' } else { $null }
                CopyRelativePath = 'ESP\EFI\Boot\bootx64.efi'
            },
            [PSCustomObject]@{
                Label             = 'ESP BCD store'
                Path              = if ($espRoot) { Join-Path -Path $espRoot -ChildPath 'EFI\Microsoft\Boot\BCD' } else { $null }
                CopyRelativePath  = 'ESP\EFI\Microsoft\Boot\BCD'
                SkipSignatureCheck = $true
            }
        )

        if (-not [string]::IsNullOrWhiteSpace($WindowsDrivePath) -and (Test-Path -Path $WindowsDrivePath)) {
            $bootEntries += [PSCustomObject]@{
                Label            = 'Offline Windows winload'
                Path             = Join-Path -Path $WindowsDrivePath -ChildPath 'Windows\System32\winload.efi'
                CopyRelativePath = 'Windows\Windows\System32\winload.efi'
            }
        }
        else {
            WriteLog "Boot file [$StageName]: Skipping offline Windows loader inspection because $WindowsDrivePath is not accessible."
        }

        foreach ($bootEntry in $bootEntries) {
            $bootEvidence += Save-BootFileArtifact -StageName $StageName -BootFilesPath $bootFilesPath -BootEntry $bootEntry
        }
    }
    finally {
        Close-EspPartitionAccess -EspAccess $espAccess
    }

    return @($bootEvidence)
}

function Invoke-DiagnosticsCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [Parameter()]
        [string]$ArgumentList,
        [Parameter(Mandatory = $true)]
        [string]$OutputFilePath,
        [Parameter(Mandatory = $true)]
        [string]$LogLabel
    )

    # Run a diagnostics command, save the full output, and mirror it to ScriptLog.
    $stdOutTempFile = "$env:TEMP\$((New-Guid).Guid)"
    $stdErrTempFile = "$env:TEMP\$((New-Guid).Guid)"

    try {
        $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -RedirectStandardOutput $stdOutTempFile -RedirectStandardError $stdErrTempFile -Wait -PassThru -NoNewWindow -ErrorAction Stop

        $stdOutContent = if (Test-Path -Path $stdOutTempFile) { Get-Content -Path $stdOutTempFile -Raw } else { '' }
        $stdErrContent = if (Test-Path -Path $stdErrTempFile) { Get-Content -Path $stdErrTempFile -Raw } else { '' }

        $outputParts = @()
        if (-not [string]::IsNullOrWhiteSpace($stdOutContent)) {
            $outputParts += $stdOutContent.TrimEnd()
        }
        if (-not [string]::IsNullOrWhiteSpace($stdErrContent)) {
            $outputParts += "STDERR:`r`n$($stdErrContent.TrimEnd())"
        }
        if ($outputParts.Count -eq 0) {
            $outputParts += '<no output>'
        }

        $combinedOutput = $outputParts -join "`r`n`r`n"
        Write-DiagnosticsTextFile -FilePath $OutputFilePath -Content $combinedOutput

        WriteLog "$LogLabel exit code: $($process.ExitCode)"
        foreach ($outputLine in ($combinedOutput -split "`r?`n")) {
            if (-not [string]::IsNullOrWhiteSpace($outputLine)) {
                WriteLog $outputLine
            }
        }

        return $process.ExitCode
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-DiagnosticsTextFile -FilePath $OutputFilePath -Content @(
            "Command: $FilePath $ArgumentList"
            "Error: $errorMessage"
        )
        WriteLog "Warning: $LogLabel failed. $errorMessage"
        return $null
    }
    finally {
        Remove-Item -Path $stdOutTempFile, $stdErrTempFile -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-SecureBootDiagnostics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$StageName,
        [Parameter()]
        [string]$DiagnosticsRoot,
        [Parameter(Mandatory = $true)]
        [int]$DiskNumber,
        [Parameter()]
        [string]$WindowsDrivePath = 'W:\',
        [Parameter()]
        [bool]$IncludeBootFiles = $true
    )

    # Collect firmware and storage telemetry, and optionally collect boot-file telemetry.
    if ([string]::IsNullOrWhiteSpace($DiagnosticsRoot)) {
        WriteLog "Secure Boot diagnostics [$StageName] skipped: diagnostics folder unavailable."
        return $null
    }

    $stagePath = New-DiagnosticsStageFolder -DiagnosticsRoot $DiagnosticsRoot -StageName $StageName
    if ([string]::IsNullOrWhiteSpace($stagePath)) {
        WriteLog "Secure Boot diagnostics [$StageName] skipped: stage folder unavailable."
        return $null
    }

    $firmwareEvidence = Save-FirmwareSecureBootDiagnostics -StageName $StageName -StagePath $stagePath
    Save-StorageSnapshot -StageName $StageName -StagePath $stagePath -DiskNumber $DiskNumber

    $bootFileEvidence = @()
    if ($IncludeBootFiles) {
        $bootFileEvidence = @(Save-BootFileDiagnostics -StageName $StageName -StagePath $stagePath -DiskNumber $DiskNumber -WindowsDrivePath $WindowsDrivePath)
    }
    else {
        WriteLog "Secure Boot diagnostics [$StageName]: Boot-file inspection skipped."
    }

    return [PSCustomObject]@{
        StageName        = $StageName
        StagePath        = $stagePath
        FirmwareEvidence = $firmwareEvidence
        BootFileEvidence = @($bootFileEvidence)
    }
}

function Get-BcdSettingValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BcdOutputPath,
        [Parameter(Mandatory = $true)]
        [string]$SettingName
    )

    # Extract a single setting value from a saved bcdedit output file.
    if (-not (Test-Path -Path $BcdOutputPath -PathType Leaf)) {
        return $null
    }

    try {
        $pattern = '^\s*' + [regex]::Escape($SettingName) + '\s+(.+)$'
        foreach ($line in Get-Content -Path $BcdOutputPath -ErrorAction Stop) {
            $match = [regex]::Match($line, $pattern)
            if ($match.Success) {
                return $match.Groups[1].Value.Trim()
            }
        }
    }
    catch {
        WriteLog "Warning: Failed to parse BCD setting '$SettingName' from $BcdOutputPath. $($_.Exception.Message)"
    }

    return $null
}

function Write-BcdSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$StageName,
        [Parameter(Mandatory = $true)]
        [string]$BcdPath
    )

    # Surface the highest value BCD fields directly in ScriptLog and a summary file.
    $bootMgrPath = Join-Path -Path $BcdPath -ChildPath 'bcdedit_bootmgr_v.txt'
    $defaultPath = Join-Path -Path $BcdPath -ChildPath 'bcdedit_default_v.txt'

    $bootMgrDevice = Get-BcdSettingValue -BcdOutputPath $bootMgrPath -SettingName 'device'
    $bootMgrLoaderPath = Get-BcdSettingValue -BcdOutputPath $bootMgrPath -SettingName 'path'
    $defaultDevice = Get-BcdSettingValue -BcdOutputPath $defaultPath -SettingName 'device'
    $defaultOsDevice = Get-BcdSettingValue -BcdOutputPath $defaultPath -SettingName 'osdevice'
    $defaultLoaderPath = Get-BcdSettingValue -BcdOutputPath $defaultPath -SettingName 'path'

    $summaryObject = [PSCustomObject]@{
        StageName        = $StageName
        BootMgrDevice    = $bootMgrDevice
        BootMgrPath      = $bootMgrLoaderPath
        DefaultDevice    = $defaultDevice
        DefaultOsDevice  = $defaultOsDevice
        DefaultPath      = $defaultLoaderPath
    }

    $summaryLines = @(
        "Stage: $StageName"
        "BootMgrDevice: $(if ($bootMgrDevice) { $bootMgrDevice } else { '<not found>' })"
        "BootMgrPath: $(if ($bootMgrLoaderPath) { $bootMgrLoaderPath } else { '<not found>' })"
        "DefaultDevice: $(if ($defaultDevice) { $defaultDevice } else { '<not found>' })"
        "DefaultOsDevice: $(if ($defaultOsDevice) { $defaultOsDevice } else { '<not found>' })"
        "DefaultPath: $(if ($defaultLoaderPath) { $defaultLoaderPath } else { '<not found>' })"
    )

    Write-DiagnosticsTextFile -FilePath (Join-Path -Path $BcdPath -ChildPath 'bcd_summary.txt') -Content $summaryLines
    WriteLog "BCD [$StageName] Summary: {bootmgr}.device=$(if ($bootMgrDevice) { $bootMgrDevice } else { '<not found>' }); {bootmgr}.path=$(if ($bootMgrLoaderPath) { $bootMgrLoaderPath } else { '<not found>' }); {default}.device=$(if ($defaultDevice) { $defaultDevice } else { '<not found>' }); {default}.osdevice=$(if ($defaultOsDevice) { $defaultOsDevice } else { '<not found>' }); {default}.path=$(if ($defaultLoaderPath) { $defaultLoaderPath } else { '<not found>' })."

    return $summaryObject
}

function Write-BootExpectationSummary {
    [CmdletBinding()]
    param(
        [Parameter()]
        [pscustomobject]$PostApplyDiagnostics,
        [Parameter()]
        [pscustomobject]$BcdDiagnostics
    )

    # Decide whether the device should boot based on parsed dbx, boot files, and BCD evidence.
    if ($null -eq $PostApplyDiagnostics -or $null -eq $BcdDiagnostics) {
        WriteLog 'Boot expectation: Unable to evaluate because required diagnostics were not available.'
        return
    }

    $bootEvidence = @($PostApplyDiagnostics.BootFileEvidence)
    $bootMgrEvidence = @($bootEvidence | Where-Object { $_.CopyRelativePath -eq 'ESP\EFI\Microsoft\Boot\bootmgfw.efi' }) | Select-Object -First 1
    $fallbackEvidence = @($bootEvidence | Where-Object { $_.CopyRelativePath -eq 'ESP\EFI\Boot\bootx64.efi' }) | Select-Object -First 1
    $winloadEvidence = @($bootEvidence | Where-Object { $_.CopyRelativePath -eq 'Windows\Windows\System32\winload.efi' }) | Select-Object -First 1

    $dbxVariableEvidence = if ($PostApplyDiagnostics.FirmwareEvidence -and $PostApplyDiagnostics.FirmwareEvidence.PSObject.Properties['dbx']) {
        $PostApplyDiagnostics.FirmwareEvidence.dbx
    }
    else {
        $null
    }

    $dbxEntries = if ($dbxVariableEvidence -and $dbxVariableEvidence.PSObject.Properties['ParsedEntries']) {
        @($dbxVariableEvidence.ParsedEntries)
    }
    else {
        @()
    }

    $dbxImageHashEntries = @($dbxEntries | Where-Object {
            $_.SignatureTypeName -eq 'EFI_CERT_SHA256' -and -not [string]::IsNullOrWhiteSpace($_.HashHex)
        })

    $dbxCertificateHashEntries = @($dbxEntries | Where-Object {
            ($_.SignatureTypeName -eq 'EFI_CERT_X509_SHA256' -and -not [string]::IsNullOrWhiteSpace($_.HashHex)) -or
            ($_.SignatureTypeName -eq 'EFI_CERT_X509' -and -not [string]::IsNullOrWhiteSpace($_.CertificateSha256))
        })

    $dbxImageHashes = @($dbxImageHashEntries | ForEach-Object { $_.HashHex.ToUpperInvariant() } | Select-Object -Unique)
    $dbxCertificateHashes = @($dbxCertificateHashEntries | ForEach-Object {
            if (-not [string]::IsNullOrWhiteSpace($_.HashHex)) {
                $_.HashHex.ToUpperInvariant()
            }
            elseif (-not [string]::IsNullOrWhiteSpace($_.CertificateSha256)) {
                $_.CertificateSha256.ToUpperInvariant()
            }
        } | Select-Object -Unique)

    $bootExpectation = 'ExpectedToBootBasedOnCollectedEvidence'
    $reasonLines = [System.Collections.Generic.List[string]]::new()
    $warningLines = [System.Collections.Generic.List[string]]::new()
    $bootComparisonLines = [System.Collections.Generic.List[string]]::new()

    if ($null -eq $bootMgrEvidence -or -not $bootMgrEvidence.Exists) {
        $bootExpectation = 'LikelyNotBootable'
        $reasonLines.Add('ESP bootmgfw.efi is missing.') | Out-Null
    }
    elseif ($bootMgrEvidence.SignatureStatus -ne 'Valid') {
        $bootExpectation = 'LikelyNotBootable'
        $reasonLines.Add("ESP bootmgfw.efi signature status is $($bootMgrEvidence.SignatureStatus).") | Out-Null
    }

    if ($null -eq $winloadEvidence -or -not $winloadEvidence.Exists) {
        $bootExpectation = 'LikelyNotBootable'
        $reasonLines.Add('Windows winload.efi is missing.') | Out-Null
    }
    elseif ($winloadEvidence.SignatureStatus -ne 'Valid') {
        $bootExpectation = 'LikelyNotBootable'
        $reasonLines.Add("Windows winload.efi signature status is $($winloadEvidence.SignatureStatus).") | Out-Null
    }

    if ($null -ne $fallbackEvidence -and -not $fallbackEvidence.Exists) {
        $warningLines.Add('ESP bootx64.efi is missing, so fallback boot relies on the Windows Boot Manager firmware entry.') | Out-Null
    }

    foreach ($currentEvidence in @($bootMgrEvidence, $fallbackEvidence, $winloadEvidence)) {
        if ($null -eq $currentEvidence) {
            continue
        }

        $matchingImageEntries = @()
        $matchingImageEntryRefs = @()
        if ($currentEvidence.Exists -and -not [string]::IsNullOrWhiteSpace($currentEvidence.FileHash)) {
            $matchingImageEntries = @($dbxImageHashEntries | Where-Object { $_.HashHex.ToUpperInvariant() -eq $currentEvidence.FileHash.ToUpperInvariant() })
            $matchingImageEntryRefs = @($matchingImageEntries | ForEach-Object { "List $($_.SignatureListIndex), Entry $($_.SignatureEntryIndex)" } | Select-Object -Unique)
        }

        $matchingCertificateEntries = @()
        $matchingCertificateEntryRefs = @()
        foreach ($chainCertificateHash in @($currentEvidence.ChainCertificateHashes)) {
            if ([string]::IsNullOrWhiteSpace($chainCertificateHash)) {
                continue
            }

            $matchingCertificateEntries += @($dbxCertificateHashEntries | Where-Object {
                    $candidateHash = if (-not [string]::IsNullOrWhiteSpace($_.HashHex)) {
                        $_.HashHex
                    }
                    else {
                        $_.CertificateSha256
                    }

                    -not [string]::IsNullOrWhiteSpace($candidateHash) -and $candidateHash.ToUpperInvariant() -eq $chainCertificateHash.ToUpperInvariant()
                })
        }

        if ($matchingCertificateEntries.Count -gt 0) {
            $matchingCertificateEntryRefs = @($matchingCertificateEntries | ForEach-Object { "List $($_.SignatureListIndex), Entry $($_.SignatureEntryIndex)" } | Select-Object -Unique)
        }

        $matchedDbxImage = $matchingImageEntryRefs.Count -gt 0
        $matchedDbxCertificate = $matchingCertificateEntryRefs.Count -gt 0

        if ($matchedDbxImage) {
            $bootExpectation = 'LikelyBlockedByDbx'
            $reasonLines.Add("$($currentEvidence.CopyRelativePath) hash matches dbx EFI_CERT_SHA256 entry or entries: $($matchingImageEntryRefs -join '; ').") | Out-Null
        }

        if ($matchedDbxCertificate) {
            $bootExpectation = 'LikelyBlockedByDbx'
            $reasonLines.Add("$($currentEvidence.CopyRelativePath) certificate chain hash matches dbx certificate entry or entries: $($matchingCertificateEntryRefs -join '; ').") | Out-Null
        }

        $bootComparisonLines.Add("$($currentEvidence.CopyRelativePath): Exists=$($currentEvidence.Exists); SignatureStatus=$($currentEvidence.SignatureStatus); FileHash=$(if ($currentEvidence.FileHash) { $currentEvidence.FileHash } else { '<none>' }); MatchedDbxImage=$matchedDbxImage; MatchedDbxCertificate=$matchedDbxCertificate; MatchingDbxImageEntries=$(if ($matchingImageEntryRefs.Count -gt 0) { $matchingImageEntryRefs -join '; ' } else { '<none>' }); MatchingDbxCertificateEntries=$(if ($matchingCertificateEntryRefs.Count -gt 0) { $matchingCertificateEntryRefs -join '; ' } else { '<none>' })") | Out-Null
    }

    $bcdSummary = if ($BcdDiagnostics.PSObject.Properties['Summary']) { $BcdDiagnostics.Summary } else { $null }
    if ($null -eq $bcdSummary) {
        if ($bootExpectation -eq 'ExpectedToBootBasedOnCollectedEvidence') {
            $bootExpectation = 'Inconclusive'
        }
        $reasonLines.Add('BCD summary was not available.') | Out-Null
    }
    else {
        if ([string]::IsNullOrWhiteSpace($bcdSummary.BootMgrDevice)) {
            $bootExpectation = 'LikelyNotBootable'
            $reasonLines.Add('{bootmgr}.device is missing.') | Out-Null
        }
        if ([string]::IsNullOrWhiteSpace($bcdSummary.BootMgrPath) -or $bcdSummary.BootMgrPath -ne '\EFI\Microsoft\Boot\bootmgfw.efi') {
            $bootExpectation = 'LikelyNotBootable'
            $reasonLines.Add("{bootmgr}.path is '$($bcdSummary.BootMgrPath)' instead of '\EFI\Microsoft\Boot\bootmgfw.efi'.") | Out-Null
        }
        if ([string]::IsNullOrWhiteSpace($bcdSummary.DefaultDevice)) {
            $bootExpectation = 'LikelyNotBootable'
            $reasonLines.Add('{default}.device is missing.') | Out-Null
        }
        if ([string]::IsNullOrWhiteSpace($bcdSummary.DefaultOsDevice)) {
            $bootExpectation = 'LikelyNotBootable'
            $reasonLines.Add('{default}.osdevice is missing.') | Out-Null
        }
        if ([string]::IsNullOrWhiteSpace($bcdSummary.DefaultPath) -or $bcdSummary.DefaultPath -ne '\Windows\system32\winload.efi') {
            $bootExpectation = 'LikelyNotBootable'
            $reasonLines.Add("{default}.path is '$($bcdSummary.DefaultPath)' instead of '\Windows\system32\winload.efi'.") | Out-Null
        }
    }

    if ($reasonLines.Count -eq 0) {
        $reasonLines.Add('No direct dbx image-hash or certificate-hash matches were found for bootmgfw.efi, bootx64.efi, or winload.efi, and the collected BCD paths point to bootmgfw.efi and winload.efi.') | Out-Null
        $warningLines.Add('OEM-specific UEFI behavior can still prevent boot even when the collected evidence looks correct.') | Out-Null
    }

    $expectationLines = @(
        "ExpectedBootOutcome: $bootExpectation"
        "DbxImageHashEntryCount: $($dbxImageHashes.Count)"
        "DbxCertificateEntryCount: $($dbxCertificateHashes.Count)"
        "WindowsBootManagerSignatureStatus: $(if ($bootMgrEvidence) { $bootMgrEvidence.SignatureStatus } else { '<missing>' })"
        "WindowsLoaderSignatureStatus: $(if ($winloadEvidence) { $winloadEvidence.SignatureStatus } else { '<missing>' })"
        "WindowsFallbackBootSignatureStatus: $(if ($fallbackEvidence) { $fallbackEvidence.SignatureStatus } else { '<missing>' })"
    )

    if ($bootComparisonLines.Count -gt 0) {
        $expectationLines += ''
        $expectationLines += 'BootFileComparison:'
        $expectationLines += @($bootComparisonLines)
    }

    if ($reasonLines.Count -gt 0) {
        $expectationLines += ''
        $expectationLines += 'Reasons:'
        $expectationLines += @($reasonLines)
    }

    if ($warningLines.Count -gt 0) {
        $expectationLines += ''
        $expectationLines += 'Warnings:'
        $expectationLines += @($warningLines)
    }

    Write-DiagnosticsTextFile -FilePath (Join-Path -Path $BcdDiagnostics.BcdPath -ChildPath 'boot_expectation.txt') -Content $expectationLines
    WriteLog "Boot expectation: $bootExpectation. $($reasonLines -join ' ')"
}

function Save-BcdDiagnostics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$StageName,
        [Parameter()]
        [string]$DiagnosticsRoot,
        [Parameter(Mandatory = $true)]
        [int]$DiskNumber
    )

    # Capture the final BCD state after boot order configuration.
    if ([string]::IsNullOrWhiteSpace($DiagnosticsRoot)) {
        WriteLog "BCD diagnostics [$StageName] skipped: diagnostics folder unavailable."
        return $null
    }

    $stagePath = New-DiagnosticsStageFolder -DiagnosticsRoot $DiagnosticsRoot -StageName $StageName
    if ([string]::IsNullOrWhiteSpace($stagePath)) {
        WriteLog "BCD diagnostics [$StageName] skipped: stage folder unavailable."
        return $null
    }

    $bcdPath = Join-Path -Path $stagePath -ChildPath 'BCD'
    try {
        New-Item -Path $bcdPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
    catch {
        WriteLog "Warning: Failed to create BCD diagnostics folder for stage $StageName. $($_.Exception.Message)"
        return $null
    }

    $commands = @(
        [PSCustomObject]@{
            Label     = 'fwbootmgr'
            Arguments = '/enum {fwbootmgr} /v'
            FileName  = 'bcdedit_fwbootmgr_v.txt'
        },
        [PSCustomObject]@{
            Label     = 'bootmgr'
            Arguments = '/enum {bootmgr} /v'
            FileName  = 'bcdedit_bootmgr_v.txt'
        },
        [PSCustomObject]@{
            Label     = 'default'
            Arguments = '/enum {default} /v'
            FileName  = 'bcdedit_default_v.txt'
        },
        [PSCustomObject]@{
            Label     = 'firmware'
            Arguments = '/enum firmware /v'
            FileName  = 'bcdedit_firmware_v.txt'
        }
    )

    foreach ($command in $commands) {
        Invoke-DiagnosticsCommand -FilePath 'bcdedit.exe' -ArgumentList $command.Arguments -OutputFilePath (Join-Path -Path $bcdPath -ChildPath $command.FileName) -LogLabel "BCD [$StageName] $($command.Label)" | Out-Null
    }

    $espAccess = Open-EspPartitionAccess -DiskNumber $DiskNumber
    try {
        $espBcdPath = if ($null -ne $espAccess) { Join-Path -Path $espAccess.DrivePath -ChildPath 'EFI\Microsoft\Boot\BCD' } else { $null }
        $storeOutputPath = Join-Path -Path $bcdPath -ChildPath 'bcdedit_store_all_v.txt'

        if ($espBcdPath -and (Test-Path -Path $espBcdPath -PathType Leaf)) {
            $storeArguments = "/store `"$espBcdPath`" /enum all /v"
            Invoke-DiagnosticsCommand -FilePath 'bcdedit.exe' -ArgumentList $storeArguments -OutputFilePath $storeOutputPath -LogLabel "BCD [$StageName] store_all" | Out-Null
        }
        else {
            Write-DiagnosticsTextFile -FilePath $storeOutputPath -Content 'ESP BCD store not found.'
            WriteLog "BCD [$StageName] ESP store enumeration skipped: offline ESP BCD not found."
        }
    }
    finally {
        Close-EspPartitionAccess -EspAccess $espAccess
    }

    $summaryObject = Write-BcdSummary -StageName $StageName -BcdPath $bcdPath

    return [PSCustomObject]@{
        StageName = $StageName
        StagePath = $stagePath
        BcdPath   = $bcdPath
        Summary   = $summaryObject
    }
}

function New-DriverSubstMapping {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath
    )
    
    $resolvedPath = (Resolve-Path -Path $SourcePath -ErrorAction Stop).Path
    $driveLetter = Get-AvailableDriveLetter
    if ($null -eq $driveLetter) {
        throw 'No drive letters are available for SUBST mapping.'
    }
    $driveName = "$driveLetter`:"
    $mappedPath = "$driveLetter`:\"
    WriteLog "Mapping driver folder '$resolvedPath' to $driveName with SUBST."
    $escapedPath = $resolvedPath -replace '"', '""'
    $arguments = "/c subst $driveName `"$escapedPath`""
    Invoke-Process -FilePath cmd.exe -ArgumentList $arguments
    return [PSCustomObject]@{
        DriveLetter = $driveLetter
        DriveName   = $driveName
        DrivePath   = $mappedPath
    }
}
    
function Remove-DriverSubstMapping {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DriveLetter
    )
    
    $driveName = "$DriveLetter`:"
    WriteLog "Removing SUBST drive $driveName"
    try {
        $arguments = "/c subst $driveName /d"
        Invoke-Process -FilePath cmd.exe -ArgumentList $arguments
    }
    catch {
        WriteLog "Failed to remove SUBST drive $($driveName): $_"
    }
}
        
#Get USB Drive and create log file
$LogFileName = 'ScriptLog.txt'
$USBDrive = Get-USBDrive
New-item -Path $USBDrive -Name $LogFileName -ItemType "file" -Force | Out-Null
$LogFile = $USBDrive + $LogFilename
$version = '2603.2'
WriteLog 'Begin Logging'
WriteLog "Script version: $version"

# Create the per-run diagnostics folder used for Secure Boot telemetry.
$secureBootDiagnosticsPath = New-SecureBootDiagnosticsFolder -UsbDrive $USBDrive

# Display banner and version
$banner = @"

███████╗███████╗██╗   ██╗    ██████╗ ██╗   ██╗██╗██╗     ██████╗ ███████╗██████╗ 
██╔════╝██╔════╝██║   ██║    ██╔══██╗██║   ██║██║██║     ██╔══██╗██╔════╝██╔══██╗
█████╗  █████╗  ██║   ██║    ██████╔╝██║   ██║██║██║     ██║  ██║█████╗  ██████╔╝
██╔══╝  ██╔══╝  ██║   ██║    ██╔══██╗██║   ██║██║██║     ██║  ██║██╔══╝  ██╔══██╗
██║     ██║     ╚██████╔╝    ██████╔╝╚██████╔╝██║███████╗██████╔╝███████╗██║  ██║
╚═╝     ╚═╝      ╚═════╝     ╚═════╝  ╚═════╝ ╚═╝╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝
                                                                                                                                                                
"@
Write-Host $banner -ForegroundColor Cyan
Write-Host "Version $version" -ForegroundColor Cyan

#Find PhysicalDrive
Write-SectionHeader -Title 'Target Disk Selection'
$diskDriveCandidates = @(Get-HardDrive)
$diskCount = $diskDriveCandidates.Count
if ($diskCount -eq 0) {
    $errorMessage = 'No hard drive found. You may need to add storage drivers to the WinPE image.'
    WriteLog ($errorMessage + ' Exiting.')
    WriteLog 'To add drivers, place them in the PEDrivers folder and re-run the creation script with -CopyPEDrivers $true, or add them manually via DISM.'
    Stop-Script -Message $errorMessage
}

# Select target disk - prompt user if multiple disks found
if ($diskCount -eq 1) {
    $selectedDisk = $diskDriveCandidates[0]
    WriteLog "Single fixed disk detected: DiskNumber=$($selectedDisk.Index), Model=$($selectedDisk.Model)"
    Write-Host "Single fixed disk detected: $($selectedDisk.Model)"
}
else {
    WriteLog "Found $diskCount fixed disks. Prompting for selection."
    Write-Host "Found $diskCount fixed disks"
    
    # Build list of available disk indexes for validation
    $validDiskIndexes = @($diskDriveCandidates | ForEach-Object { $_.Index })
    
    # Display disk list using actual disk index as the selection value
    $displayList = @()
    foreach ($currentDisk in $diskDriveCandidates) {
        $sizeGB = [math]::Round(($currentDisk.Size / 1GB), 2)
        $displayList += [PSCustomObject]@{
            Disk        = $currentDisk.Index
            'Size (GB)' = $sizeGB
            'Sector'    = $currentDisk.BytesPerSector
            'Bus Type'  = $currentDisk.InterfaceType
            Model       = $currentDisk.Model
        }
    }
    $displayList | Format-Table -AutoSize -Property Disk, 'Size (GB)', Sector, 'Bus Type', Model

    do {
        try {
            $var = $true
            [int]$diskSelection = Read-Host 'Enter the disk number to apply the FFU to'
        }
        catch {
            Write-Host 'Input was not in correct format. Please enter a valid disk number'
            $var = $false
        }
        # Validate selected disk is in the list of available disks
        if ($var -and $validDiskIndexes -notcontains $diskSelection) {
            Write-Host "Invalid disk number. Please select from the available disks."
            $var = $false
        }
    } until ($var)

    $selectedDisk = $diskDriveCandidates | Where-Object { $_.Index -eq $diskSelection }
    WriteLog "Disk selection: DiskNumber=$($selectedDisk.Index), Model=$($selectedDisk.Model), SizeGB=$([math]::Round(($selectedDisk.Size / 1GB), 2)), BusType=$($selectedDisk.InterfaceType)"
    Write-Host "`nDisk $($selectedDisk.Index) selected: $($selectedDisk.Model)"
}

# Set variables from selected disk
$PhysicalDeviceID = $selectedDisk.DeviceID
$BytesPerSector = $selectedDisk.BytesPerSector
$DiskID = $selectedDisk.Index
$diskSizeGB = [math]::Round(($selectedDisk.Size / 1GB), 2)

# Create hardDrive object for Get-SystemInformation compatibility
$hardDrive = [PSCustomObject]@{
    DeviceID       = $PhysicalDeviceID
    BytesPerSector = $BytesPerSector
    DiskSize       = $selectedDisk.Size
    DiskNumber     = $DiskID
}

WriteLog "Physical DeviceID is $PhysicalDeviceID"
WriteLog "DiskNumber is $DiskID with size $diskSizeGB GB"

# Gather and write system information
$sysInfoObject = Get-SystemInformation -HardDrive $hardDrive
Write-SystemInformation -SystemInformation $sysInfoObject

# Capture baseline Secure Boot and storage diagnostics before the target disk is wiped.
$null = Invoke-SecureBootDiagnostics -StageName 'Baseline' -DiagnosticsRoot $secureBootDiagnosticsPath -DiskNumber $DiskID -IncludeBootFiles $false

#Find FFU Files
Write-SectionHeader 'FFU File Selection'
[array]$FFUFiles = @(Get-ChildItem -Path $USBDrive*.ffu)
$FFUCount = $FFUFiles.Count

#If multiple FFUs found, ask which to install
If ($FFUCount -gt 1) {
    WriteLog "Found $FFUCount FFU Files"
    Write-Host "Found $FFUCount FFU Files"
    $array = @()

    for ($i = 0; $i -le $FFUCount - 1; $i++) {
        $Properties = [ordered]@{Number = $i + 1 ; FFUFile = $FFUFiles[$i].FullName }
        $array += New-Object PSObject -Property $Properties
    }
    $array | Format-Table -AutoSize -Property Number, FFUFile | Out-Host
    do {
        try {
            $var = $true
            [int]$FFUSelected = Read-Host 'Enter the FFU number to install'
            $FFUSelected = $FFUSelected - 1
        }

        catch {
            Write-Host 'Input was not in correct format. Please enter a valid FFU number'
            $var = $false
        }
    } until (($FFUSelected -le $FFUCount - 1) -and $var) 

    $FFUFileToInstall = $array[$FFUSelected].FFUFile
    WriteLog "$FFUFileToInstall was selected"
}
elseif ($FFUCount -eq 1) {
    WriteLog "Found $FFUCount FFU File"
    Write-Host "Found $FFUCount FFU File"
    $FFUFileToInstall = $FFUFiles[0].FullName
    WriteLog "$FFUFileToInstall will be installed"
    Write-Host "$FFUFileToInstall will be installed"
} 
else {
    $errorMessage = 'No FFU files found.'
    Writelog $errorMessage
    Stop-Script -Message $errorMessage
}

#FindAP
$APFolder = $USBDrive + "Autopilot\"
If (Test-Path -Path $APFolder) {
    [array]$APFiles = @(Get-ChildItem -Path $APFolder*.json)
    $APFilesCount = $APFiles.Count
    if ($APFilesCount -ge 1) {
        $autopilot = $true
    }
}


#FindPPKG
$PPKGFolder = $USBDrive + "PPKG\"
if (Test-Path -Path $PPKGFolder) {
    [array]$PPKGFiles = @(Get-ChildItem -Path $PPKGFolder*.ppkg)
    $PPKGFilesCount = $PPKGFiles.Count
    if ($PPKGFilesCount -ge 1) {
        $PPKG = $true
    }
}

#FindUnattend
$UnattendFolder = $USBDrive + "unattend\"
$UnattendFilePath = $UnattendFolder + "unattend.xml"
$UnattendPrefixPath = $UnattendFolder + "prefixes.txt"
$UnattendComputerNamePath = $UnattendFolder + "SerialComputerNames.csv"
If (Test-Path -Path $UnattendFilePath) {
    $UnattendFile = Get-ChildItem -Path $UnattendFilePath
    If ($UnattendFile) {
        $Unattend = $true
    }
}
If (Test-Path -Path $UnattendPrefixPath) {
    $UnattendPrefixFile = Get-ChildItem -Path $UnattendPrefixPath
    If ($UnattendPrefixFile) {
        $UnattendPrefix = $true
    }
}
If (Test-Path -Path $UnattendComputerNamePath) {
    $UnattendComputerNameFile = Get-ChildItem -Path $UnattendComputerNamePath
    If ($UnattendComputerNameFile) {
        $UnattendComputerName = $true
    }
}

#Ask for device name if unattend exists
If ($Unattend -or $UnattendPrefix -or $UnattendComputerName) {
    Write-SectionHeader 'Device Name Selection'
    if ($Unattend -and $UnattendPrefix) {
        Writelog 'Unattend file found with prefixes.txt. Getting prefixes.'
        $UnattendPrefixes = @(Get-content $UnattendPrefixFile)
        $UnattendPrefixCount = $UnattendPrefixes.Count
        If ($UnattendPrefixCount -gt 1) {
            WriteLog "Found $UnattendPrefixCount Prefixes"
            $array = @()
            for ($i = 0; $i -le $UnattendPrefixCount - 1; $i++) {
                $Properties = [ordered]@{Number = $i + 1 ; DeviceNamePrefix = $UnattendPrefixes[$i] }
                $array += New-Object PSObject -Property $Properties
            }
            $array | Format-Table -AutoSize -Property Number, DeviceNamePrefix
            do {
                try {
                    $var = $true
                    [int]$PrefixSelected = Read-Host 'Enter the prefix number to use for the device name'
                    $PrefixSelected = $PrefixSelected - 1
                }
                catch {
                    Write-Host 'Input was not in correct format. Please enter a valid prefix number'
                    $var = $false
                }
            } until (($PrefixSelected -le $UnattendPrefixCount - 1) -and $var) 
            $PrefixToUse = $array[$PrefixSelected].DeviceNamePrefix
            WriteLog "$PrefixToUse was selected"
            Write-Host "`n$PrefixToUse was selected as device name prefix"
        }
        elseif ($UnattendPrefixCount -eq 1) {
            WriteLog "Found $UnattendPrefixCount Prefix"
            Write-Host "Found $UnattendPrefixCount Prefix"
            $PrefixToUse = $UnattendPrefixes[0]
            WriteLog "Will use $PrefixToUse as device name prefix"
            Write-Host "Will use $PrefixToUse as device name prefix"
        }
        #Get serial number to append. This can make names longer than 15 characters. Trim any leading or trailing whitespace
        $serial = (Get-CimInstance -ClassName win32_bios).SerialNumber.Trim()
        #Combine prefix with serial
        $computername = ($PrefixToUse + $serial) -replace "\s", "" # Remove spaces because windows does not support spaces in the computer names
        #If computername is longer than 15 characters, reduce to 15. Sysprep/unattend doesn't like ComputerName being longer than 15 characters even though Windows accepts it
        If ($computername.Length -gt 15) {
            $computername = $computername.substring(0, 15)
        }
        $computername = Set-Computername($computername)
        Writelog "Computer name will be set to $computername"
        Write-Host "Computer name will be set to $computername"
    }
    elseif ($Unattend -and $UnattendComputerName) {
        Writelog 'Unattend file found with SerialComputerNames.csv. Getting name for current computer.'
        $SerialComputerNames = Import-Csv -Path $UnattendComputerNameFile.FullName -Delimiter ","

        $SerialNumber = (Get-CimInstance -Class Win32_Bios).SerialNumber
        $SCName = $SerialComputerNames | Where-Object { $_.SerialNumber -eq $SerialNumber }

        If ($SCName) {
            [string]$computername = $SCName.ComputerName
            $computername = Set-Computername($computername)
            Writelog "Computer name will be set to $computername"
            Write-Host "Computer name will be set to $computername"
        }
        else {
            Writelog 'No matching serial number found in SerialComputerNames.csv. Setting random computer name to complete setup.'
            Write-Host 'No matching serial number found in SerialComputerNames.csv. Setting random computer name to complete setup.'
            [string]$computername = ("FFU-" + ( -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 11 | ForEach-Object { [char]$_ })))
            $computername = Set-Computername($computername)
            Writelog "Computer name will be set to $computername"
            Write-Host "Computer name will be set to $computername"
        }
    }
    elseif ($Unattend) {
        Writelog 'Unattend file found with no prefixes.txt, asking for name'
        Write-Host 'Unattend file found but no prefixes.txt. Please enter a device name.'
        [string]$computername = Read-Host 'Enter device name'
        $computername = Set-Computername($computername)
        Writelog "Computer name will be set to $computername"
        Write-Host "Computer name will be set to $computername"
    }
    else {
        WriteLog 'Device naming assets detected without unattend.xml. Skipping device naming prompts.'
    }
}
else {
    WriteLog 'No unattend folder found. Device name will be set via PPKG, AP JSON, or default OS name.'
}

#If both AP and PPKG folder found with files, ask which to use.
If ($autopilot -eq $true -and $PPKG -eq $true) {
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
    If ($APorPPKG -eq 1) {
        $PPKG = $false
    }
    else {
        $autopilot = $false
    } 
}

#If multiple AP json files found, ask which to install
If ($APFilesCount -gt 1 -and $autopilot -eq $true) {
    WriteLog "Found $APFilesCount Autopilot json Files"
    $array = @()

    for ($i = 0; $i -le $APFilesCount - 1; $i++) {
        $Properties = [ordered]@{Number = $i + 1 ; APFile = $APFiles[$i].FullName; APFileName = $APFiles[$i].Name }
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
    } until (($APFileSelected -le $APFilesCount - 1) -and $var) 

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
    Write-SectionHeader -Title 'Provisioning Package Selection'
    WriteLog "Found $PPKGFilesCount PPKG Files"
    $array = @()

    for ($i = 0; $i -le $PPKGFilesCount - 1; $i++) {
        $Properties = [ordered]@{Number = $i + 1 ; PPKGFile = $PPKGFiles[$i].FullName; PPKGFileName = $PPKGFiles[$i].Name }
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
    } until (($PPKGFileSelected -le $PPKGFilesCount - 1) -and $var) 

    $PPKGFileToInstall = $array[$PPKGFileSelected].PPKGFile
    WriteLog "$PPKGFileToInstall was selected"
    Write-Host "`n$PPKGFileToInstall will be used"
}
elseif ($PPKGFilesCount -eq 1 -and $PPKG -eq $true) {
    Write-SectionHeader -Title 'Provisioning Package Selection'
    WriteLog "Found $PPKGFilesCount PPKG File"
    Write-Host "Found $PPKGFilesCount PPKG File"
    $PPKGFileToInstall = $PPKGFiles[0].FullName
    WriteLog "$PPKGFileToInstall will be used"
    Write-Host "`n$PPKGFileToInstall will be used"
} 
else {
    Writelog 'No PPKG files found or PPKG not selected.'
}

#Find Drivers
$DriversPath = $USBDrive + "Drivers"
$DriverSourcePath = $null
$DriverSourceType = $null # Will be 'WIM' or 'Folder'
$driverMappingPath = Join-Path -Path $DriversPath -ChildPath "DriverMapping.json"

If (Test-Path -Path $DriversPath) {
    Write-SectionHeader -Title 'Drivers Selection'
}

# --- Automatic Driver Detection using DriverMapping.json ---
if (Test-Path -Path $driverMappingPath -PathType Leaf) {
    WriteLog "DriverMapping.json found at $driverMappingPath. Attempting automatic driver selection."
    Write-Host "DriverMapping.json found. Attempting automatic driver selection."
    try {
        $driverMappings = Get-Content -Path $driverMappingPath | Out-String | ConvertFrom-Json -ErrorAction Stop
        $driverMappings = @($driverMappings) | Where-Object { $null -ne $_ }
        if ($driverMappings.Count -eq 0) {
            throw "DriverMapping.json does not contain any entries."
        }

        if ($null -eq $sysInfoObject) {
            $sysInfoObject = Get-SystemInformation -HardDrive $hardDrive
        }

        $identifierLabelForLog = $null
        $identifierValueForLog = $null
        if ($sysInfoObject.PSObject.Properties['Machine Type'] -and -not [string]::IsNullOrWhiteSpace($sysInfoObject.'Machine Type')) {
            $identifierLabelForLog = 'Machine Type'
            $identifierValueForLog = $sysInfoObject.'Machine Type'
        }
        elseif ($sysInfoObject.PSObject.Properties['System ID'] -and -not [string]::IsNullOrWhiteSpace($sysInfoObject.'System ID')) {
            $identifierLabelForLog = 'System ID'
            $identifierValueForLog = $sysInfoObject.'System ID'
        }
        else {
            $identifierLabelForLog = 'System ID'
            $identifierValueForLog = 'Not Detected'
        }
        WriteLog ("Detected System: Manufacturer='{0}', Model='{1}', {2}='{3}'" -f $sysInfoObject.Manufacturer, $sysInfoObject.Model, $identifierLabelForLog, $identifierValueForLog)
        Write-Host ("Detected System: Manufacturer='{0}', Model='{1}'" -f $sysInfoObject.Manufacturer, $sysInfoObject.Model)

        $matchedRule = Find-DriverMappingRule -SystemInformation $sysInfoObject -DriverMappings $driverMappings

        if ($null -ne $matchedRule) {
            WriteLog "Automatic match found: Manufacturer='$($matchedRule.Manufacturer)', Model='$($matchedRule.Model)'"
            Write-Host "Automatic match found: Manufacturer='$($matchedRule.Manufacturer)', Model='$($matchedRule.Model)'"
            $potentialDriverPath = Join-Path -Path $DriversPath -ChildPath $matchedRule.DriverPath

            if (Test-Path -Path $potentialDriverPath) {
                $DriverSourcePath = $potentialDriverPath
                if ($DriverSourcePath -like '*.wim') {
                    $DriverSourceType = 'WIM'
                }
                else {
                    $DriverSourceType = 'Folder'
                }
                WriteLog "Automatically selected driver source. Type: $DriverSourceType, Path: $DriverSourcePath"
                Write-Host "Automatically selected driver source. Type: $DriverSourceType, Path: $DriverSourcePath"
            }
            else {
                WriteLog "Matched driver path '$potentialDriverPath' not found. Falling back to manual selection."
                Write-Host "Matched driver path '$potentialDriverPath' not found. Falling back to manual selection."
            }
        }
        else {
            WriteLog "No automatic driver mapping rule matched identifiers for this system. Falling back to manual selection."
            Write-Host "No matching driver mapping rule was found for this system. Falling back to manual selection."
        }
    }
    catch {
        WriteLog "An error occurred during automatic driver detection: $($_.Exception.Message). Falling back to manual selection."
        Write-Host "An error occurred during automatic driver detection: $($_.Exception.Message). Falling back to manual selection."
    }
}
else {
    WriteLog "DriverMapping.json not found. Proceeding with manual driver selection."
}

# --- Manual Driver Selection (Fallback) ---
if ($null -eq $DriverSourcePath) {
    If (Test-Path -Path $DriversPath) {
        WriteLog "Searching for driver WIMs and folders in $DriversPath"
    
        # Collect all WIM-based driver sources anywhere under Drivers
        $wimFiles = Get-ChildItem -Path $DriversPath -Filter *.wim -File -Recurse -ErrorAction SilentlyContinue
        
        # Treat each immediate child folder as a manufacturer container (supports known and unknown vendors)
        $manufacturerFolders = Get-ChildItem -Path $DriversPath -Directory -ErrorAction SilentlyContinue
        $driversRootFullPath = (Get-Item -Path $DriversPath).FullName.TrimEnd('\')
        $relativePathResolver = {
            param(
                [string]$candidatePath,
                [string]$rootPath
            )
            try {
                $normalizedPath = [System.IO.Path]::GetFullPath($candidatePath)
                if ($normalizedPath.StartsWith($rootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $relativeSegment = $normalizedPath.Substring($rootPath.Length).TrimStart('\', '/')
                    if ([string]::IsNullOrWhiteSpace($relativeSegment)) {
                        return Split-Path -Path $normalizedPath -Leaf
                    }
                    return $relativePath = $relativeSegment
                }
                return $normalizedPath
            }
            catch {
                return $candidatePath
            }
        }

        # Create a combined list
        $DriverSources = @()
        foreach ($wimFile in $wimFiles) {
            $relativePath = & $relativePathResolver -candidatePath $wimFile.FullName -rootPath $driversRootFullPath
            $DriverSources += [PSCustomObject]@{
                Type         = 'WIM'
                Path         = $wimFile.FullName
                RelativePath = $relativePath
            }
        }
        foreach ($manufacturerFolder in $manufacturerFolders) {
            $modelFolders = Get-ChildItem -Path $manufacturerFolder.FullName -Directory -ErrorAction SilentlyContinue

            if ($null -eq $modelFolders -or $modelFolders.Count -eq 0) {
                if (Test-DriverFolderHasInstallableContent -Path $manufacturerFolder.FullName) {
                    $relativePath = & $relativePathResolver -candidatePath $manufacturerFolder.FullName -rootPath $driversRootFullPath
                    $DriverSources += [PSCustomObject]@{
                        Type         = 'Folder'
                        Path         = $manufacturerFolder.FullName
                        RelativePath = $relativePath
                    }
                    WriteLog "Using manufacturer folder '$($manufacturerFolder.FullName)' as a driver source because it contains installable content."
                }
                else {
                    WriteLog "Skipping '$($manufacturerFolder.FullName)' because it has no model folders with installable content."
                }
                continue
            }

            foreach ($modelFolder in $modelFolders) {
                if (-not (Test-DriverFolderHasInstallableContent -Path $modelFolder.FullName)) {
                    WriteLog "Skipping driver folder '$($modelFolder.FullName)' because no installable files were found."
                    continue
                }
                $relativePath = & $relativePathResolver -candidatePath $modelFolder.FullName -rootPath $driversRootFullPath
                $DriverSources += [PSCustomObject]@{
                    Type         = 'Folder'
                    Path         = $modelFolder.FullName
                    RelativePath = $relativePath
                }
            }
        }

        $DriverSourcesCount = $DriverSources.Count

        if ($DriverSourcesCount -gt 0) {
            WriteLog "Found $DriverSourcesCount total driver sources (WIMs and folders)."
            if ($DriverSourcesCount -eq 1) {
                $DriverSourcePath = $DriverSources[0].Path
                $DriverSourceType = $DriverSources[0].Type
                $selectedRelativePath = $DriverSources[0].RelativePath
                WriteLog "Single driver source found. Type: $DriverSourceType, Path: $DriverSourcePath, RelativePath: $selectedRelativePath"
                Write-Host "Single driver source found. Type: $DriverSourceType, RelativePath: $selectedRelativePath"
            }
            else {
                # Multiple sources found, prompt user
                WriteLog "Multiple driver sources found. Prompting for selection."
                $displayArray = @()
                for ($i = 0; $i -lt $DriverSourcesCount; $i++) {
                    $displayArray += [PSCustomObject]@{
                        Number       = $i + 1
                        Type         = $DriverSources[$i].Type
                        RelativePath = $DriverSources[$i].RelativePath
                        Path         = $DriverSources[$i].Path
                    }
                }
                $displayArray | Format-Table -Property Number, Type, RelativePath -AutoSize
                
                $DriverSelected = -1
                $skipDriverInstall = $false
                do {
                    try {
                        $var = $true
                        [int]$userSelection = Read-Host 'Enter the number of the driver source to install (0 to skip)'
                        if ($userSelection -eq 0) {
                            $skipDriverInstall = $true
                            break
                        }
                        $DriverSelected = $userSelection - 1
                    }
                    catch {
                        Write-Host 'Input was not in correct format. Please enter a valid number.'
                        $var = $false
                    }
                } until ((($DriverSelected -ge 0 -and $DriverSelected -lt $DriverSourcesCount) -or $skipDriverInstall) -and $var)
                
                if ($skipDriverInstall) {
                    $DriverSourcePath = $null
                    $DriverSourceType = $null
                    $selectedRelativePath = $null
                    WriteLog 'User chose to skip driver installation.'
                    Write-Host "`nDriver installation was skipped."
                }
                else {
                    $DriverSourcePath = $DriverSources[$DriverSelected].Path
                    $DriverSourceType = $DriverSources[$DriverSelected].Type
                    $selectedRelativePath = $DriverSources[$DriverSelected].RelativePath
                    WriteLog "User selected Type: $DriverSourceType, Path: $DriverSourcePath, RelativePath: $selectedRelativePath"
                    Write-Host "`nUser selected Type: $DriverSourceType, RelativePath: $selectedRelativePath"
                }
            }
        }
        else {
            WriteLog "No driver WIMs or folders found in Drivers directory."
            Write-Host "No driver WIMs or folders found in Drivers directory."
        }
    }
    else {
        WriteLog "Drivers folder not found at $DriversPath. Skipping driver installation."
    }
}
#Partition drive
Writelog 'Clean Disk'
$originalProgressPreference = $ProgressPreference
try {
    $ProgressPreference = 'SilentlyContinue'
    $Disk = Get-Disk -Number $DiskID
    if ($Disk.PartitionStyle -ne "RAW") {
        $Disk | clear-disk -RemoveData -RemoveOEM -Confirm:$false
    }
}
catch {
    WriteLog 'Cleaning disk failed. Exiting'
    throw $_
}
finally {
    $ProgressPreference = $originalProgressPreference
}

Writelog 'Cleaning Disk succeeded'

#Apply FFU
Write-SectionHeader -Title 'Applying FFU'
WriteLog "Applying FFU to $PhysicalDeviceID"
WriteLog "Running command dism /apply-ffu /ImageFile:$FFUFileToInstall /ApplyDrive:$PhysicalDeviceID"
#In order for Applying Image progress bar to show up, need to call dism directly. Might be a better way to handle, but must have progress bar show up on screen.
dism /apply-ffu /ImageFile:$FFUFileToInstall /ApplyDrive:$PhysicalDeviceID
$dismExitCode = $LASTEXITCODE

if ($dismExitCode -ne 0) {
    $errorMessage = "Failed to apply FFU. LastExitCode = $dismExitCode."
    if ($dismExitCode -eq 1393) {
        WriteLog "Failed to apply FFU - LastExitCode = $dismExitCode"
        WriteLog "This is likely due to a mismatched LogicalSectorSizeBytes"
        WriteLog "BytesPerSector value from Win32_Diskdrive is $BytesPerSector"
        if ($BytesPerSector -eq 4096) {
            WriteLog "The FFU build process by default uses a 512 LogicalSectorSizeBytes. Rebuild the FFU by adding -LogicalSectorSizeBytes 4096 to the command line"
        }
        elseif ($BytesPerSector -eq 512) {
            WriteLog "This FFU was likely built with a LogicalSectorSizeBytes of 4096. Rebuild the FFU by adding -LogicalSectorSizeBytes 512 to the command line"
        }
        $errorMessage += " This is likely due to a mismatched logical sector size. Check logs for details."
    }
    else {
        Writelog "Failed to apply FFU - LastExitCode = $dismExitCode also check dism.log on the USB drive for more info"
        $errorMessage += " Check dism.log on the USB drive for more info."
    }
    Stop-Script -Message $errorMessage
}

WriteLog 'Successfully applied FFU'

# Verify Windows partition exists and assign drive letter
$windowsPartition = Get-Partition -DiskNumber $DiskID | Where-Object { $_.PartitionNumber -eq 3 }
if ($null -eq $windowsPartition) {
    $errorMessage = "Windows partition (Partition 3) not found after applying FFU, even though DISM reported success."
    WriteLog $errorMessage
    Stop-Script -Message $errorMessage
}

WriteLog "Assigning drive letter 'W' to Windows partition."
Set-Partition -InputObject $windowsPartition -NewDriveLetter W

# Verify the drive letter was set
$windowsVolume = Get-Volume -DriveLetter W -ErrorAction SilentlyContinue
if ($null -eq $windowsVolume) {
    $errorMessage = "Failed to assign drive letter 'W' to the Windows partition after applying FFU."
    WriteLog $errorMessage
    Stop-Script -Message $errorMessage
}
WriteLog "Successfully assigned drive letter 'W'."

$recoveryPartition = Get-Partition -DiskNumber $DiskID | Where-Object PartitionNumber -eq 4
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

#Copy modified WinRE if folder exists, else copy inbox WinRE
$WinRE = $USBDrive + "WinRE\winre.wim"
If (Test-Path -Path $WinRE) {
    WriteLog 'Copying modified WinRE to Recovery directory'
    Get-Disk | Where-Object Number -eq $DiskID | Get-Partition | Where-Object Type -eq Recovery | Set-Partition -NewDriveLetter R
    Invoke-Process xcopy.exe "/h $WinRE R:\Recovery\WindowsRE\ /Y"
    WriteLog 'Copying WinRE to Recovery directory succeeded'
    WriteLog 'Registering location of recovery tools'
    Invoke-Process W:\Windows\System32\Reagentc.exe "/Setreimage /Path R:\Recovery\WindowsRE /Target W:\Windows"
        Get-Disk | Where-Object Number -eq $DiskID | Get-Partition | Where-Object Type -eq Recovery | Remove-PartitionAccessPath -AccessPath R:
        WriteLog 'Registering location of recovery tools succeeded'
    }
    
    # Capture post-apply Secure Boot, storage, and boot-chain diagnostics.
    $postApplyDiagnostics = Invoke-SecureBootDiagnostics -StageName 'PostApply' -DiagnosticsRoot $secureBootDiagnosticsPath -DiskNumber $DiskID -WindowsDrivePath 'W:\'
    
    #Autopilot JSON
If ($APFileToInstall) {
    Write-SectionHeader -Title 'Applying Autopilot Configuration'
    WriteLog "Copying $APFileToInstall to W:\windows\provisioning\autopilot"
    Invoke-process xcopy.exe "$APFileToInstall W:\Windows\provisioning\autopilot\"
    WriteLog "Copying $APFileToInstall to W:\windows\provisioning\autopilot succeeded"
    # Rename file in W:\Windows\Provisioning\Autopilot to AutoPilotConfigurationFile.json
    try {
        Rename-Item -Path "W:\Windows\Provisioning\Autopilot\$APFileName" -NewName 'W:\Windows\Provisioning\Autopilot\AutoPilotConfigurationFile.json'
        WriteLog "Renamed W:\Windows\Provisioning\Autopilot\$APFilename to W:\Windows\Provisioning\Autopilot\AutoPilotConfigurationFile.json"
    }
    
    catch {
        Writelog "Copying $APFileToInstall to W:\windows\provisioning\autopilot failed with error: $_"
        throw $_
    }
}
#Apply PPKG
If ($PPKGFileToInstall) {
    Write-SectionHeader -Title 'Applying Provisioning Package'
    try {
        #Make sure to delete any existing PPKG on the USB drive
        Get-Childitem -Path $USBDrive\*.ppkg | ForEach-Object {
            Remove-item -Path $_.FullName
        }
        WriteLog "Copying $PPKGFileToInstall to $USBDrive"
        Write-Host "Copying $PPKGFileToInstall to $USBDrive"
        # Quote paths to handle PPKG filenames with spaces
        Invoke-process xcopy.exe """$PPKGFileToInstall"" ""$USBDrive"""
        WriteLog "Copying $PPKGFileToInstall to $USBDrive succeeded"
        Write-Host "Copying $PPKGFileToInstall to $USBDrive succeeded"
    }

    catch {
        Writelog "Copying $PPKGFileToInstall to $USBDrive failed with error: $_"
        Write-Host "Copying $PPKGFileToInstall to $USBDrive failed with error: $_"
        throw $_
    }
}
#Set DeviceName
If ($computername) {
    Write-SectionHeader -Title 'Applying Computer Name and Unattend Configuration'
    try {
        $PantherDir = 'w:\windows\panther'
        If (Test-Path -Path $PantherDir) {
            Writelog "Copying $UnattendFile to $PantherDir"
            Write-Host "Copying $UnattendFile to $PantherDir"
            Invoke-process xcopy "$UnattendFile $PantherDir /Y"
            WriteLog "Copying $UnattendFile to $PantherDir succeeded"
            Write-Host "Copying $UnattendFile to $PantherDir succeeded"
        }
        else {
            Writelog "$PantherDir doesn't exist, creating it"
            New-Item -Path $PantherDir -ItemType Directory -Force
            Writelog "Copying $UnattendFile to $PantherDir"
            Write-Host "Copying $UnattendFile to $PantherDir"
            Invoke-Process xcopy.exe "$UnattendFile $PantherDir"
            WriteLog "Copying $UnattendFile to $PantherDir succeeded"
            Write-Host "Copying $UnattendFile to $PantherDir succeeded"
        }
    }
    catch {
        WriteLog "Copying Unattend.xml to name device failed"
        Stop-Script -Message "Copying Unattend.xml to name device failed with error: $_"
    }   
}

# Add Drivers
if ($null -ne $DriverSourcePath) {
    Write-SectionHeader -Title 'Installing Drivers'
    if ($DriverSourceType -eq 'WIM') {
        WriteLog "Installing drivers from WIM: $DriverSourcePath"
        Write-Host "Installing drivers from WIM: $DriverSourcePath"
        $TempDriverDir = "W:\TempDrivers"
        try {
            # Create working folder for WIM-based drivers
            WriteLog "Creating temporary directory for drivers at $TempDriverDir"
            New-Item -Path $TempDriverDir -ItemType Directory -Force | Out-Null
            
            # Mount the driver WIM read-only so DISM can recurse the extracted INF tree
            WriteLog "Mounting WIM contents to $TempDriverDir"
            Write-Host "Mounting WIM contents to $TempDriverDir"
            # For some reason can't use /mount-image with invoke-process, so using dism.exe directly
            dism.exe /Mount-Image /ImageFile:$DriverSourcePath /Index:1 /MountDir:$TempDriverDir /ReadOnly /optimize
            $mountExitCode = $LASTEXITCODE
            if ($mountExitCode -ne 0) {
                throw "DISM WIM mount failed. LastExitCode = $mountExitCode."
            }
            WriteLog "WIM mount successful."

            # Inject drivers into the offline Windows image; failures here should not stop deployment
            WriteLog "Injecting drivers from $TempDriverDir"
            Write-Host "Injecting drivers from $TempDriverDir"
            Write-Host "This may take a while, please be patient."
            $driverInjectExitCode = Invoke-Process -FilePath dism.exe -ArgumentList "/image:W:\ /Add-Driver /Driver:""$TempDriverDir"" /Recurse" -IgnoreExitCode -PassThruExitCode
            if ($driverInjectExitCode -ne 0) {
                $warningMessage = "Warning: One or more drivers failed to inject from WIM. ExitCode = $driverInjectExitCode. Continuing deployment."
                WriteLog $warningMessage
                Write-Host $warningMessage -ForegroundColor Yellow

                # Copy setupapi.offline.log to the USB drive when driver injection fails

                $setupApiLogPath = 'W:\Windows\INF\setupapi.offline.log'
                if (Test-Path -Path $setupApiLogPath) {
                    try {
                        Invoke-Process xcopy.exe """$setupApiLogPath"" ""$USBDrive"" /Y"
                    }
                    catch {
                        WriteLog "Warning: Failed to copy setupapi.offline.log to $USBDrive. "
                    }
                }
                else {
                    WriteLog "Warning: setupapi.offline.log not found at $setupApiLogPath"
                }
            }
            else {
                WriteLog "Driver injection from WIM succeeded."
                Write-Host "Driver injection from WIM succeeded."
            }
        }
        catch {
            $warningMessage = "Warning: An error occurred during WIM driver installation. Continuing deployment."
            WriteLog $warningMessage
            Write-Host $warningMessage -ForegroundColor Yellow

            # Copy troubleshooting logs to the USB drive when driver installation fails
            try {
                Invoke-Process cmd.exe "/c copy /Y ""X:\Windows\logs\dism\dism.log"" ""$($USBDrive)dism_driverinject.log"""
            }
            catch {
                WriteLog "Warning: Failed to copy dism.log to $USBDrive."
            }

            $setupApiLogPath = 'W:\Windows\INF\setupapi.offline.log'
            if (Test-Path -Path $setupApiLogPath) {
                try {
                    Invoke-Process xcopy.exe """$setupApiLogPath"" ""$USBDrive"" /Y"
                }
                catch {
                    WriteLog "Warning: Failed to copy setupapi.offline.log to $USBDrive."
                }
            }
            else {
                WriteLog "Warning: setupapi.offline.log not found at $setupApiLogPath"
            }
        }
        finally {
            if (Test-Path -Path $TempDriverDir) {
                # Always attempt to unmount and clean up; unmount failures should not stop deployment
                WriteLog "Unmounting WIM from $TempDriverDir"
                Write-Host "Unmounting WIM from $TempDriverDir"
                try {
                    Invoke-Process dism.exe "/Unmount-Image /MountDir:""$TempDriverDir"" /Discard"
                    WriteLog "Unmount successful."
                    Write-Host "Unmount successful."
                }
                catch {
                    $warningMessage = "Warning: Failed to unmount WIM from $TempDriverDir. Continuing cleanup."
                    WriteLog $warningMessage
                    Write-Host $warningMessage -ForegroundColor Yellow
                }

                WriteLog "Cleaning up temporary driver directory: $TempDriverDir"
                Write-Host "Cleaning up temporary driver directory: $TempDriverDir"
                try {
                    Remove-Item -Path $TempDriverDir -Recurse -Force
                    WriteLog "Cleanup successful."
                    Write-Host "Cleanup successful."
                }
                catch {
                    $warningMessage = "Warning: Failed to clean up temporary driver directory: $TempDriverDir."
                    WriteLog $warningMessage
                    Write-Host $warningMessage -ForegroundColor Yellow
                }
            }
        }
    }
    elseif ($DriverSourceType -eq 'Folder') {
        $substMapping = $null
        try {
            # Use SUBST to shorten long paths for DISM /Add-Driver
            $substMapping = New-DriverSubstMapping -SourcePath $DriverSourcePath
            $shortDriverPath = $substMapping.DrivePath
            WriteLog "Injecting drivers from folder via SUBST. Source: $DriverSourcePath, Mapped: $($substMapping.DriveName)"
            Write-Host "Injecting drivers from folder: $shortDriverPath"
            Write-Host "This may take a while, please be patient."

            # Inject drivers into the offline Windows image; failures here should not stop deployment
            $driverInjectExitCode = Invoke-Process -FilePath dism.exe -ArgumentList "/image:W:\ /Add-Driver /Driver:$shortDriverPath /Recurse" -IgnoreExitCode -PassThruExitCode
            if ($driverInjectExitCode -ne 0) {
                $warningMessage = "Warning: One or more drivers failed to inject from folder. ExitCode = $driverInjectExitCode. Continuing deployment."
                WriteLog $warningMessage
                Write-Host $warningMessage -ForegroundColor Yellow

                # Copy setupapi.offline.log to the USB drive when driver injection fails
                $setupApiLogPath = 'W:\Windows\INF\setupapi.offline.log'
                if (Test-Path -Path $setupApiLogPath) {
                    try {
                        Invoke-Process xcopy.exe """$setupApiLogPath"" ""$USBDrive"" /Y"
                    }
                    catch {
                        WriteLog "Warning: Failed to copy setupapi.offline.log to $USBDrive. "
                    }
                }
                else {
                    WriteLog "Warning: setupapi.offline.log not found at $setupApiLogPath"
                }
            }
            else {
                WriteLog "Driver injection from folder succeeded."
                Write-Host "Driver injection from folder succeeded."
            }
        }
        catch {
            $warningMessage = "Warning: An error occurred during folder driver installation. Continuing deployment."
            WriteLog $warningMessage
            Write-Host $warningMessage -ForegroundColor Yellow

            # Copy troubleshooting logs to the USB drive when driver installation fails
            try {
                Invoke-Process xcopy.exe "X:\Windows\logs\dism\dism.log $USBDrive /Y"
            }
            catch {
                WriteLog "Warning: Failed to copy dism.log to $USBDrive."
            }

            $setupApiLogPath = 'W:\Windows\INF\setupapi.offline.log'
            if (Test-Path -Path $setupApiLogPath) {
                try {
                    Invoke-Process xcopy.exe """$setupApiLogPath"" ""$USBDrive"" /Y"
                }
                catch {
                    WriteLog "Warning: Failed to copy setupapi.offline.log to $USBDrive."
                }
            }
            else {
                WriteLog "Warning: setupapi.offline.log not found at $setupApiLogPath"
            }
        }
        finally {
            # Always attempt to remove SUBST mapping; failures here should not stop deployment
            if ($null -ne $substMapping) {
                try {
                    Remove-DriverSubstMapping -DriveLetter $substMapping.DriveLetter
                }
                catch {
                    $warningMessage = "Warning: Failed to remove SUBST mapping $($substMapping.DriveLetter). Continuing deployment."
                    WriteLog $warningMessage
                    Write-Host $warningMessage -ForegroundColor Yellow
                }
            }
        }
    }
}
else {
    WriteLog "No drivers to install."
}
Write-SectionHeader -Title 'Setting Boot Configuration'
WriteLog "Setting Windows Boot Manager to be first in the firmware display order."
Write-Host "Setting Windows Boot Manager to be first in the firmware display order."
Invoke-Process bcdedit.exe "/set {fwbootmgr} displayorder {bootmgr} /addfirst"
WriteLog "Setting Windows Boot Manager to be first in the default display order."
Write-Host "Setting Windows Boot Manager to be first in the default display order."
Invoke-Process bcdedit.exe "/set {bootmgr} displayorder {default} /addfirst"

# Capture final BCD telemetry after the display order changes are applied.
$finalBcdDiagnostics = Save-BcdDiagnostics -StageName 'FinalBcd' -DiagnosticsRoot $secureBootDiagnosticsPath -DiskNumber $DiskID
Write-BootExpectationSummary -PostApplyDiagnostics $postApplyDiagnostics -BcdDiagnostics $finalBcdDiagnostics

#Copy DISM log to USBDrive
WriteLog "Copying dism log to $USBDrive"
invoke-process xcopy "X:\Windows\logs\dism\dism.log $USBDrive /Y" 
WriteLog "Copying dism log to $USBDrive succeeded"




