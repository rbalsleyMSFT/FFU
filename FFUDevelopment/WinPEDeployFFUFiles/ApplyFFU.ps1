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
        $diskDrive = Get-CimInstance -Class 'Win32_DiskDrive' | Where-Object { $_.MediaType -eq 'Fixed hard disk media' `
                -and $_.Model -eq 'Microsoft Virtual Disk' `
                -and $_.Index -eq 0 `
                -and $_.SCSILogicalUnit -eq 0
        }
    }
    else {
        WriteLog 'Not running in a VM. Getting physical disk drive'
        $diskDrive = Get-CimInstance -Class 'Win32_DiskDrive' | Where-Object { $_.MediaType -eq 'Fixed hard disk media' -and $_.Model -ne 'Microsoft Virtual Disk' }
    }
    $deviceID = $diskDrive.DeviceID
    $bytesPerSector = $diskDrive.BytesPerSector
    $diskSize = $diskDrive.Size

    # Create a custom object to return values
    $result = [PSCustomObject]@{
        DeviceID       = $deviceID
        BytesPerSector = $bytesPerSector
        DiskSize       = $diskSize
    }

    return $result
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
            NoNewWindow            = $true;
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
            }
            else {
                if ([string]::IsNullOrEmpty($cmdOutput) -eq $false) {
                    WriteLog $cmdOutput
                }
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
    
#Get USB Drive and create log file
$LogFileName = 'ScriptLog.txt'
$USBDrive = Get-USBDrive
New-item -Path $USBDrive -Name $LogFileName -ItemType "file" -Force | Out-Null
$LogFile = $USBDrive + $LogFilename
$version = '2509.1Preview'
WriteLog 'Begin Logging'
WriteLog "Script version: $version"

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
# $PhysicalDeviceID = Get-HardDrive
$hardDrive = Get-HardDrive
if ($null -eq $hardDrive) {
    $errorMessage = 'No hard drive found. You may need to add storage drivers to the WinPE image.'
    WriteLog ($errorMessage + ' Exiting.')
    WriteLog 'To add drivers, place them in the PEDrivers folder and re-run the creation script with -CopyPEDrivers $true, or add them manually via DISM.'
    Stop-Script -Message $errorMessage
}
$PhysicalDeviceID = $hardDrive.DeviceID
$BytesPerSector = $hardDrive.BytesPerSector
WriteLog "Physical DeviceID is $PhysicalDeviceID"

#Parse DiskID Number
$DiskID = $PhysicalDeviceID.substring($PhysicalDeviceID.length - 1, 1)
WriteLog "DiskID is $DiskID"

# Gather and write system information
$sysInfoObject = Get-SystemInformation -HardDrive $hardDrive
Write-SystemInformation -SystemInformation $sysInfoObject

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
    $array | Format-Table -AutoSize -Property Number, FFUFile
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
    
        # Get all WIM files
        $WimFiles = Get-ChildItem -Path $DriversPath -Filter *.wim -Recurse
        
        # Build folder list that surfaces Manufacturer\Model entries
        $DriverFolders = Get-ChildItem -Path $DriversPath -Directory
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
                    return $relativeSegment
                }
                return $normalizedPath
            }
            catch {
                return $candidatePath
            }
        }

        # Create a combined list
        $DriverSources = @()
        foreach ($wimFile in $WimFiles) {
            $relativePath = & $relativePathResolver -candidatePath $wimFile.FullName -rootPath $driversRootFullPath
            $DriverSources += [PSCustomObject]@{
                Type         = 'WIM'
                Path         = $wimFile.FullName
                RelativePath = $relativePath
            }
        }
        foreach ($driverFolder in $DriverFolders) {
            $childModelFolders = Get-ChildItem -Path $driverFolder.FullName -Directory -ErrorAction SilentlyContinue
            if (($childModelFolders.Count -gt 0) -and ($driverFolder.Parent.FullName -eq $driversRootFullPath)) {
                foreach ($modelFolder in $childModelFolders) {
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
            else {
                if (-not (Test-DriverFolderHasInstallableContent -Path $driverFolder.FullName)) {
                    WriteLog "Skipping driver folder '$($driverFolder.FullName)' because no installable files were found."
                    continue
                }
                $relativePath = & $relativePathResolver -candidatePath $driverFolder.FullName -rootPath $driversRootFullPath
                $DriverSources += [PSCustomObject]@{
                    Type         = 'Folder'
                    Path         = $driverFolder.FullName
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
                
                do {
                    try {
                        $var = $true
                        [int]$DriverSelected = Read-Host 'Enter the number of the driver source to install'
                        $DriverSelected = $DriverSelected - 1
                    }
                    catch {
                        Write-Host 'Input was not in correct format. Please enter a valid number.'
                        $var = $false
                    }
                } until (($DriverSelected -ge 0) -and ($DriverSelected -lt $DriverSourcesCount) -and $var)
                
                $DriverSourcePath = $DriverSources[$DriverSelected].Path
                $DriverSourceType = $DriverSources[$DriverSelected].Type
                $selectedRelativePath = $DriverSources[$DriverSelected].RelativePath
                WriteLog "User selected Type: $DriverSourceType, Path: $DriverSourcePath, RelativePath: $selectedRelativePath"
                Write-Host "`nUser selected Type: $DriverSourceType, RelativePath: $selectedRelativePath"
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
        Invoke-process xcopy.exe "$PPKGFileToInstall $USBDrive"
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
            WriteLog "Creating temporary directory for drivers at $TempDriverDir"
            New-Item -Path $TempDriverDir -ItemType Directory -Force | Out-Null
            
            WriteLog "Mounting WIM contents to $TempDriverDir"
            Write-Host "Mounting WIM contents to $TempDriverDir"
            # For some reason can't use /mount-image with invoke-process, so using dism.exe directly
            dism.exe /Mount-Image /ImageFile:$DriverSourcePath /Index:1 /MountDir:$TempDriverDir /ReadOnly /optimize
            WriteLog "WIM mount successful."

            WriteLog "Injecting drivers from $TempDriverDir"
            Write-Host "Injecting drivers from $TempDriverDir"
            Write-Host "This may take a while, please be patient."
            Invoke-Process dism.exe "/image:W:\ /Add-Driver /Driver:""$TempDriverDir"" /Recurse"
            WriteLog "Driver injection from WIM succeeded."
            Write-Host "Driver injection from WIM succeeded."

        }
        catch {
            WriteLog "An error occurred during WIM driver installation: $_"
            # Copy DISM log to USBDrive for debugging
            invoke-process xcopy.exe "X:\Windows\logs\dism\dism.log $USBDrive /Y"
            throw $_
        }
        finally {
            if (Test-Path -Path $TempDriverDir) {
                WriteLog "Unmounting WIM from $TempDriverDir"
                Write-Host "Unmounting WIM from $TempDriverDir"
                Invoke-Process dism.exe "/Unmount-Image /MountDir:""$TempDriverDir"" /Discard"
                WriteLog "Unmount successful."
                Write-Host "Unmount successful."
                WriteLog "Cleaning up temporary driver directory: $TempDriverDir"
                Write-Host "Cleaning up temporary driver directory: $TempDriverDir"
                Remove-Item -Path $TempDriverDir -Recurse -Force
                WriteLog "Cleanup successful."
                Write-Host "Cleanup successful."
            }
        }
    }
    elseif ($DriverSourceType -eq 'Folder') {
        WriteLog "Injecting drivers from folder: $DriverSourcePath"
        Write-Host "Injecting drivers from folder: $DriverSourcePath"
        Write-Host "This may take a while, please be patient."
        Invoke-Process dism.exe "/image:W:\ /Add-Driver /Driver:""$DriverSourcePath"" /Recurse"
        WriteLog "Driver injection from folder succeeded."
        Write-Host "Driver injection from folder succeeded."
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
#Copy DISM log to USBDrive
WriteLog "Copying dism log to $USBDrive"
invoke-process xcopy "X:\Windows\logs\dism\dism.log $USBDrive /Y" 
WriteLog "Copying dism log to $USBDrive succeeded"




