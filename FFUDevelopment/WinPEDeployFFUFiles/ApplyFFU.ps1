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

function Read-MenuSelection {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [Parameter(Mandatory = $true)]
        [string]$InvalidInputMessage,

        [Parameter()]
        [int[]]$ValidSelections,

        [Parameter()]
        [int]$Minimum = [int]::MinValue,

        [Parameter()]
        [int]$Maximum = [int]::MaxValue,

        [Parameter()]
        [switch]$AllowSkip
    )

    do {
        $userInput = Read-Host $Prompt
        if ([string]::IsNullOrWhiteSpace($userInput)) {
            Write-Host $InvalidInputMessage
            continue
        }

        $selection = 0
        if (-not [int]::TryParse($userInput, [ref]$selection)) {
            Write-Host $InvalidInputMessage
            continue
        }

        if ($AllowSkip -and $selection -eq 0) {
            return 0
        }

        if ($PSBoundParameters.ContainsKey('ValidSelections')) {
            if ($ValidSelections -notcontains $selection) {
                Write-Host $InvalidInputMessage
                continue
            }
        }
        elseif ($selection -lt $Minimum -or $selection -gt $Maximum) {
            Write-Host $InvalidInputMessage
            continue
        }

        return $selection
    } until ($false)
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

function Get-UnattendComputerNameValue {
    if ($null -eq $UnattendFile) {
        return $null
    }

    [xml]$xml = Get-Content $UnattendFile
    foreach ($component in $xml.unattend.settings.component) {
        if ($component.ComputerName) {
            return [string]$component.ComputerName
        }
    }

    return $null
}

function Get-FFUDataPartitionDriveLetterDeploymentContext {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WindowsPartitionRoot
    )

    $runtimeDirectory = Join-Path -Path $WindowsPartitionRoot -ChildPath 'Windows\Setup\Scripts\FFUDL'
    $runtimeScriptPath = Join-Path -Path $runtimeDirectory -ChildPath 'Apply.ps1'
    $manifestPath = Join-Path -Path $runtimeDirectory -ChildPath 'Manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        if (Test-Path -LiteralPath $runtimeDirectory -PathType Container) {
            throw "Data partition drive-letter runtime directory exists without a manifest at $manifestPath."
        }
        return $null
    }

    if (-not (Test-Path -LiteralPath $runtimeScriptPath -PathType Leaf)) {
        throw "Data partition drive-letter manifest exists without its runtime script at $runtimeScriptPath."
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ([int]$manifest.SchemaVersion -ne 1) {
        throw "Unsupported data partition drive-letter manifest schema version '$($manifest.SchemaVersion)'."
    }
    if (@($manifest.Partitions).Count -eq 0) {
        throw 'Data partition drive-letter manifest does not contain any partitions.'
    }

    $processorArchitecture = ([string]$manifest.ProcessorArchitecture).Trim().ToLowerInvariant()
    if ($processorArchitecture -notin @('amd64', 'arm64')) {
        throw "Unsupported data partition drive-letter processor architecture '$processorArchitecture'."
    }

    WriteLog "Found data partition drive-letter assignment manifest with $(@($manifest.Partitions).Count) partition(s)."
    return [pscustomobject]@{
        RuntimeDirectory      = $runtimeDirectory
        RuntimeScriptPath     = $runtimeScriptPath
        ManifestPath          = $manifestPath
        ProcessorArchitecture = $processorArchitecture
    }
}

function Add-FFUDataPartitionDriveLetterCommandToAppliedUnattend {
    param(
        [Parameter(Mandatory = $true)]
        [string]$UnattendPath,
        [Parameter(Mandatory = $true)]
        [ValidateSet('amd64', 'arm64')]
        [string]$ProcessorArchitecture
    )

    $unattendNamespace = 'urn:schemas-microsoft-com:unattend'
    $wcmNamespace = 'http://schemas.microsoft.com/WMIConfig/2002/State'
    $unattendXml = New-Object System.Xml.XmlDocument
    $unattendXml.PreserveWhitespace = $true
    if (-not (Test-Path -LiteralPath $UnattendPath -PathType Leaf)) {
        throw "Deployment unattend was not found at the expected path $UnattendPath."
    }
    $unattendXml.Load($UnattendPath)

    $unattendRoot = $unattendXml.DocumentElement
    if ($null -eq $unattendRoot -or $unattendRoot.LocalName -ne 'unattend' -or $unattendRoot.NamespaceURI -ne $unattendNamespace) {
        throw "Unattend XML at $UnattendPath does not use the supported unattend root namespace."
    }

    $namespaceManager = New-Object System.Xml.XmlNamespaceManager($unattendXml.NameTable)
    $namespaceManager.AddNamespace('un', $unattendNamespace)
    $specializeSettings = $unattendRoot.SelectSingleNode("un:settings[@pass='specialize']", $namespaceManager)
    if ($null -eq $specializeSettings) {
        $specializeSettings = $unattendXml.CreateElement('settings', $unattendNamespace)
        $null = $specializeSettings.SetAttribute('pass', 'specialize')
        $firstSettingsNode = $unattendRoot.SelectSingleNode('un:settings', $namespaceManager)
        if ($null -ne $firstSettingsNode) {
            $null = $unattendRoot.InsertBefore($specializeSettings, $firstSettingsNode)
        }
        else {
            $null = $unattendRoot.AppendChild($specializeSettings)
        }
    }

    $deploymentComponents = @($specializeSettings.SelectNodes("un:component[@name='Microsoft-Windows-Deployment']", $namespaceManager) |
        Where-Object { $_.GetAttribute('processorArchitecture') -ieq $ProcessorArchitecture })
    if ($deploymentComponents.Count -gt 1) {
        throw "Unattend XML at $UnattendPath contains multiple Microsoft-Windows-Deployment components for $ProcessorArchitecture."
    }
    if ($deploymentComponents.Count -eq 0) {
        $deploymentComponent = $unattendXml.CreateElement('component', $unattendNamespace)
        $null = $deploymentComponent.SetAttribute('name', 'Microsoft-Windows-Deployment')
        $null = $deploymentComponent.SetAttribute('processorArchitecture', $ProcessorArchitecture)
        $null = $deploymentComponent.SetAttribute('publicKeyToken', '31bf3856ad364e35')
        $null = $deploymentComponent.SetAttribute('language', 'neutral')
        $null = $deploymentComponent.SetAttribute('versionScope', 'nonSxS')
        $null = $specializeSettings.AppendChild($deploymentComponent)
    }
    else {
        $deploymentComponent = $deploymentComponents[0]
    }

    $runSynchronous = $deploymentComponent.SelectSingleNode('un:RunSynchronous', $namespaceManager)
    if ($null -eq $runSynchronous) {
        $runSynchronous = $unattendXml.CreateElement('RunSynchronous', $unattendNamespace)
        $null = $deploymentComponent.AppendChild($runSynchronous)
    }

    $existingCommands = @($runSynchronous.SelectNodes('un:RunSynchronousCommand', $namespaceManager))
    $orderedExistingCommands = [System.Collections.Generic.List[pscustomobject]]::new()
    $commandIndex = 0
    foreach ($existingCommand in $existingCommands) {
        $pathNode = $existingCommand.SelectSingleNode('un:Path', $namespaceManager)
        if ($null -ne $pathNode -and $pathNode.InnerText -match '(?i)\\FFUDL\\Apply\.ps1') {
            $null = $runSynchronous.RemoveChild($existingCommand)
            continue
        }

        $orderValue = [int]::MaxValue
        $orderNode = $existingCommand.SelectSingleNode('un:Order', $namespaceManager)
        if ($null -ne $orderNode) {
            $parsedOrder = 0
            if ([int]::TryParse($orderNode.InnerText, [ref]$parsedOrder)) {
                $orderValue = $parsedOrder
            }
        }
        $orderedExistingCommands.Add([pscustomobject]@{ Node = $existingCommand; Order = $orderValue; Index = $commandIndex })
        $commandIndex++
    }

    $nextOrder = 2
    foreach ($existingCommandInfo in @($orderedExistingCommands | Sort-Object -Property Order, Index)) {
        $orderNode = $existingCommandInfo.Node.SelectSingleNode('un:Order', $namespaceManager)
        if ($null -eq $orderNode) {
            $orderNode = $unattendXml.CreateElement('Order', $unattendNamespace)
            $null = $existingCommandInfo.Node.PrependChild($orderNode)
        }
        $orderNode.InnerText = [string]$nextOrder
        $nextOrder++
    }

    $newCommand = $unattendXml.CreateElement('RunSynchronousCommand', $unattendNamespace)
    $actionAttribute = $unattendXml.CreateAttribute('wcm', 'action', $wcmNamespace)
    $actionAttribute.Value = 'add'
    $null = $newCommand.Attributes.Append($actionAttribute)
    $orderElement = $unattendXml.CreateElement('Order', $unattendNamespace)
    $orderElement.InnerText = '1'
    $null = $newCommand.AppendChild($orderElement)
    $descriptionElement = $unattendXml.CreateElement('Description', $unattendNamespace)
    $descriptionElement.InnerText = 'Apply FFU data partition drive letters'
    $null = $newCommand.AppendChild($descriptionElement)
    $pathElement = $unattendXml.CreateElement('Path', $unattendNamespace)
    $specializeCommand = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Windows\Setup\Scripts\FFUDL\Apply.ps1" -ManifestPath "C:\Windows\Setup\Scripts\FFUDL\Manifest.json" -Phase Specialize'
    if ($specializeCommand.Length -gt 259) {
        throw "Data partition drive-letter specialize command exceeds the 259-character unattend Path limit. Length: $($specializeCommand.Length)."
    }
    $pathElement.InnerText = $specializeCommand
    $null = $newCommand.AppendChild($pathElement)
    $willRebootElement = $unattendXml.CreateElement('WillReboot', $unattendNamespace)
    $willRebootElement.InnerText = 'OnRequest'
    $null = $newCommand.AppendChild($willRebootElement)
    if ($null -ne $runSynchronous.FirstChild) {
        $null = $runSynchronous.InsertBefore($newCommand, $runSynchronous.FirstChild)
    }
    else {
        $null = $runSynchronous.AppendChild($newCommand)
    }

    $unattendXml.Save($UnattendPath)
    WriteLog "Merged data partition drive-letter specialize command into $UnattendPath."
}

function Test-FFUDataPartitionDriveLetterCommandInAppliedUnattend {
    param(
        [Parameter(Mandatory = $true)]
        [string]$UnattendPath,
        [Parameter(Mandatory = $true)]
        [ValidateSet('amd64', 'arm64')]
        [string]$ProcessorArchitecture
    )

    if (-not (Test-Path -LiteralPath $UnattendPath -PathType Leaf)) {
        throw "Data partition drive-letter deployment unattend was not found at $UnattendPath."
    }

    $unattendNamespace = 'urn:schemas-microsoft-com:unattend'
    $wcmNamespace = 'http://schemas.microsoft.com/WMIConfig/2002/State'
    $unattendXml = New-Object System.Xml.XmlDocument
    $unattendXml.Load($UnattendPath)
    if ($null -eq $unattendXml.DocumentElement -or $unattendXml.DocumentElement.NamespaceURI -ne $unattendNamespace) {
        throw "Unattend XML at $UnattendPath does not use the supported unattend root namespace."
    }

    $namespaceManager = New-Object System.Xml.XmlNamespaceManager($unattendXml.NameTable)
    $namespaceManager.AddNamespace('un', $unattendNamespace)
    $deploymentComponents = @($unattendXml.SelectNodes("//un:settings[@pass='specialize']/un:component[@name='Microsoft-Windows-Deployment']", $namespaceManager) |
        Where-Object { $_.GetAttribute('processorArchitecture') -ieq $ProcessorArchitecture })
    if ($deploymentComponents.Count -ne 1) {
        throw "Expected exactly one specialize Microsoft-Windows-Deployment component for $ProcessorArchitecture in $UnattendPath."
    }

    $commands = @($deploymentComponents[0].SelectNodes('un:RunSynchronous/un:RunSynchronousCommand', $namespaceManager))
    $driveLetterCommands = @($commands | Where-Object {
            $pathNode = $_.SelectSingleNode('un:Path', $namespaceManager)
            $null -ne $pathNode -and $pathNode.InnerText -match '(?i)\\FFUDL\\Apply\.ps1'
        })
    if ($driveLetterCommands.Count -ne 1) {
        throw "Expected exactly one data partition drive-letter specialize command in $UnattendPath."
    }

    $driveLetterCommand = $driveLetterCommands[0]
    $pathNode = $driveLetterCommand.SelectSingleNode('un:Path', $namespaceManager)
    $orderNode = $driveLetterCommand.SelectSingleNode('un:Order', $namespaceManager)
    $willRebootNode = $driveLetterCommand.SelectSingleNode('un:WillReboot', $namespaceManager)
    if ($null -eq $pathNode -or $pathNode.InnerText -notmatch '(?i)-WindowStyle\s+Hidden\s+-File(?:\s|$)') {
        throw "Data partition drive-letter specialize command does not use a hidden PowerShell window in $UnattendPath."
    }
    if ($null -eq $orderNode -or $orderNode.InnerText -ne '1') {
        throw "Data partition drive-letter specialize command is not first in $UnattendPath."
    }
    if ($null -eq $willRebootNode -or $willRebootNode.InnerText -ne 'OnRequest') {
        throw "Data partition drive-letter specialize command does not use WillReboot=OnRequest in $UnattendPath."
    }
    if ($driveLetterCommand.GetAttribute('action', $wcmNamespace) -ne 'add') {
        throw "Data partition drive-letter specialize command does not use wcm:action=add in $UnattendPath."
    }
    foreach ($otherCommand in @($commands | Where-Object { $_ -ne $driveLetterCommand })) {
        $otherOrderNode = $otherCommand.SelectSingleNode('un:Order', $namespaceManager)
        $otherOrder = 0
        if ($null -eq $otherOrderNode -or -not [int]::TryParse($otherOrderNode.InnerText, [ref]$otherOrder) -or $otherOrder -le 1) {
            throw "Another specialize command conflicts with first order in $UnattendPath."
        }
    }

    WriteLog "Verified data partition drive-letter specialize command in $UnattendPath."
}

function Test-LegacyPromptComputerName($computername) {
    if ([string]::IsNullOrWhiteSpace($computername)) {
        return $false
    }

    $normalizedName = $computername.Trim().ToLowerInvariant()
    return $normalizedName -in @('mycomputer', 'default')
}

function Get-NormalizedComputerName($computername) {
    if ([string]::IsNullOrWhiteSpace($computername)) {
        throw 'Computer name cannot be empty.'
    }

    $normalizedName = ($computername -replace "\s", '').Trim()
    if ([string]::IsNullOrWhiteSpace($normalizedName)) {
        throw 'Computer name cannot be empty after removing spaces.'
    }

    if ($normalizedName.Length -gt 15) {
        $normalizedName = $normalizedName.Substring(0, 15)
    }

    return $normalizedName
}

function Resolve-ComputerNameTemplate($computerNameTemplate, $serialNumber) {
    if ([string]::IsNullOrWhiteSpace($computerNameTemplate)) {
        throw 'Computer name template cannot be empty.'
    }

    $resolvedName = $computerNameTemplate -replace '(?i)%serial%', $serialNumber
    if ($resolvedName -match '%') {
        throw 'Unsupported device name variable found. Only %serial% is supported.'
    }

    return Get-NormalizedComputerName($resolvedName)
}

function Set-ConfiguredComputerName($computername) {
    $normalizedName = Get-NormalizedComputerName($computername)
    $normalizedName = Set-Computername($normalizedName)
    Writelog "Computer name will be set to $normalizedName"
    Write-Host "Computer name will be set to $normalizedName"
    return $normalizedName
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
    
function Test-DriverProvisioningPackage {
	param([string]$Path)

	$file = Get-Item -LiteralPath $Path -ErrorAction Stop
	$header = [byte[]]::new(8)
	$stream = [IO.File]::OpenRead($file.FullName)
	try { $headerBytes = $stream.Read($header, 0, $header.Length) }
	finally { $stream.Dispose() }
	if ($file.Length -le $header.Length -or $headerBytes -ne $header.Length -or
		[Text.Encoding]::ASCII.GetString($header) -ne "MSWIM`0`0`0") {
		throw "Provisioning package is empty or has an invalid container: $Path"
	}
	return $true
}

function Resolve-DriverProvisioningPath {
	param([string]$Root, [string]$RelativePath, [switch]$AllowRootReparsePoint)

	if ([string]::IsNullOrWhiteSpace($RelativePath) -or [IO.Path]::IsPathRooted($RelativePath) -or
		$RelativePath -match '(^|[\\/])\.\.([\\/]|$)|:') {
		throw "Provisioning file path must be relative and remain inside its root: '$RelativePath'."
	}
	$rootPath = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
	$path = [IO.Path]::GetFullPath((Join-Path $rootPath $RelativePath))
	if (-not $path.StartsWith($rootPath, [StringComparison]::OrdinalIgnoreCase)) {
		throw "Provisioning file path escapes '$Root': '$RelativePath'."
	}
	$currentPath = $path
	while ($currentPath.Length -ge $rootPath.TrimEnd('\').Length) {
		# The caller-created image mount may redirect the root, but never its descendants.
		if ($AllowRootReparsePoint -and $currentPath.TrimEnd('\') -eq $rootPath.TrimEnd('\')) { break }
		if (Test-Path -LiteralPath $currentPath) {
			if ((Get-Item -LiteralPath $currentPath -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint) {
				throw "Provisioning file path contains a reparse point: $currentPath"
			}
		}
		$parentPath = [IO.Path]::GetDirectoryName($currentPath.TrimEnd('\'))
		if ([string]::IsNullOrWhiteSpace($parentPath) -or $parentPath -eq $currentPath) { break }
		$currentPath = $parentPath
	}
	return $path
}

function Get-DriverInfOwnedFiles {
	param([string]$ImagePath, [string]$DriverRoot, [IO.FileInfo[]]$Files)

	$watch = [Diagnostics.Stopwatch]::StartNew()
	$owned = @{}
	$referenced = @{}
	$sourceInfs = @{}
	$ownerHashes = @{}
	$ownerInfNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
	$fileHashes = @{}
	$fileLengths = @($Files | ForEach-Object { $_.Length })
	$fileNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
	$candidateInfs = @{}
	$visitedDirectories = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
	$sourceRoot = [IO.Path]::GetFullPath($DriverRoot).TrimEnd('\')
	foreach ($file in $Files) {
		$null = $fileNames.Add($file.Name)
		$hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
		if (-not $fileHashes.ContainsKey($hash)) { $fileHashes[$hash] = @() }
		$fileHashes[$hash] += $file.FullName
		WriteLog "Checking INF ownership near '$($file.FullName)'."
		$directory = $file.Directory
		# An INF's payload is beside it or in its subfolders; do not search sibling components.
		while ($null -ne $directory -and ($directory.FullName.TrimEnd('\') -eq $sourceRoot -or
			$directory.FullName.StartsWith($sourceRoot + '\', [StringComparison]::OrdinalIgnoreCase))) {
			if (-not $visitedDirectories.Add($directory.FullName)) { break }
			foreach ($inf in @(Get-ChildItem -LiteralPath $directory.FullName -Filter *.inf -File -ErrorAction Stop)) {
				$candidateInfs[$inf.FullName] = $inf
			}
			$directory = $directory.Parent
		}
	}
	foreach ($inf in $candidateInfs.Values) {
		$sections = @{}
		$sectionName = ''
		foreach ($line in Get-Content -LiteralPath $inf.FullName -ErrorAction Stop) {
			$line = ($line -split ';', 2)[0].Trim()
			if ($line -match '^\[([^\]]+)\]$') { $sectionName = $matches[1]; if (-not $sections.ContainsKey($sectionName)) { $sections[$sectionName] = [Collections.Generic.List[string]]::new() } }
			elseif ($sectionName -and $line) { $sections[$sectionName].Add($line) }
		}
		$strings = @{}
		foreach ($name in @($sections.Keys | Where-Object { $_ -match '^Strings(?:\.|$)' })) {
			foreach ($line in $sections[$name]) {
				if ($line -match '^([^=]+)=(.*)$') { $strings[$matches[1].Trim()] = $matches[2].Trim().Trim('"') }
			}
		}
		$expandValue = {
			param([string]$Value)
			[regex]::Replace($Value.Trim(), '%([^%]+)%', {
				param($match)
				if ($strings.ContainsKey($match.Groups[1].Value)) { return $strings[$match.Groups[1].Value] }
				return $match.Value
			}).Trim('"')
		}
		$copyNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
		$copySections = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
		foreach ($line in @($sections.Values | ForEach-Object { $_ })) {
			if ($line -notmatch '^CopyFiles\s*=(.*)$') { continue }
			foreach ($copySection in $matches[1] -split ',') {
				$copySection = & $expandValue $copySection
				if (-not $copySections.Add($copySection)) { continue }
				if ($copySection.StartsWith('@')) {
					$copyName = $copySection.Substring(1)
					if ($fileNames.Contains([IO.Path]::GetFileName($copyName))) { $null = $copyNames.Add($copyName) }
					continue
				}
				foreach ($entry in @($sections[$copySection])) {
					if ($null -eq $entry) { continue }
					$fields = $entry -split ','
					$copyName = & $expandValue $(if ($fields.Count -gt 1 -and $fields[1].Trim()) { $fields[1] } else { $fields[0] })
					if ($fileNames.Contains([IO.Path]::GetFileName($copyName))) { $null = $copyNames.Add($copyName) }
				}
			}
		}
		$infReferences = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
		foreach ($copyName in $copyNames) {
			$sourcePaths = @()
			foreach ($name in @($sections.Keys | Where-Object { $_ -match '^SourceDisksFiles(?:\.|$)' })) {
				foreach ($entry in $sections[$name]) {
					if ($entry -notmatch '^([^=]+)=(.*)$') { continue }
					$sourceName = & $expandValue $matches[1]
					$fields = $matches[2] -split ','
					if ($sourceName -ne $copyName) { continue }
					$diskId = & $expandValue $fields[0]
					$diskPath = ''
					foreach ($diskSection in @($sections.Keys | Where-Object { $_ -match '^SourceDisksNames(?:\.|$)' })) {
						foreach ($diskEntry in $sections[$diskSection]) {
							if ($diskEntry -match '^([^=]+)=(.*)$' -and $matches[1].Trim() -eq $diskId) {
								$diskFields = $matches[2] -split ','
								if ($diskFields.Count -gt 3) { $diskPath = & $expandValue $diskFields[3] }
							}
						}
					}
					$subdirectory = if ($fields.Count -gt 1) { & $expandValue $fields[1] } else { '' }
					$relativePath = if ($subdirectory) { Join-Path $subdirectory $sourceName } else { $sourceName }
					if ($diskPath) { $relativePath = Join-Path $diskPath $relativePath }
					$sourcePaths += [IO.Path]::GetFullPath((Join-Path $inf.DirectoryName $relativePath))
				}
			}
			if ($sourcePaths.Count -eq 0) { $sourcePaths = @([IO.Path]::GetFullPath((Join-Path $inf.DirectoryName $copyName))) }
			foreach ($file in $Files) {
				if ($file.FullName -in $sourcePaths) {
					$referenced[$file.FullName] = $inf.FullName
					$null = $infReferences.Add($file.FullName)
				}
			}
		}
		if ($infReferences.Count -gt 0) {
			$hash = (Get-FileHash -LiteralPath $inf.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
			$sourceInfs[$hash] = $inf.FullName
			$null = $ownerInfNames.Add($inf.Name)
			foreach ($sourcePath in $infReferences) {
				if (-not $ownerHashes.ContainsKey($sourcePath)) { $ownerHashes[$sourcePath] = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase) }
				$null = $ownerHashes[$sourcePath].Add($hash)
			}
		}
	}
	$storePath = Join-Path $ImagePath 'Windows\System32\DriverStore\FileRepository'
	if ($sourceInfs.Count -gt 0 -and (Test-Path -LiteralPath $storePath -PathType Container)) {
		WriteLog "Verifying $($sourceInfs.Count) candidate owner INF package(s) in the offline driver store."
		foreach ($infName in $ownerInfNames) {
			foreach ($packageDirectory in @(Get-ChildItem -LiteralPath $storePath -Filter ($infName + '_*') -Directory -ErrorAction Stop)) {
				foreach ($inf in @(Get-ChildItem -LiteralPath $packageDirectory.FullName -Filter $infName -File -ErrorAction Stop)) {
					$hash = (Get-FileHash -LiteralPath $inf.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
					if (-not $sourceInfs.ContainsKey($hash)) { continue }
					foreach ($file in @(Get-ChildItem -LiteralPath $inf.DirectoryName -File -Recurse -ErrorAction Stop)) {
						if ($file.Extension -eq '.inf' -or $file.Extension -eq '.cat') { continue }
						if ($file.Length -notin $fileLengths) { continue }
						$fileHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
						if ($fileHashes.ContainsKey($fileHash)) {
							foreach ($sourcePath in $fileHashes[$fileHash]) {
								if ($ownerHashes.ContainsKey($sourcePath) -and $ownerHashes[$sourcePath].Contains($hash)) { $owned[$sourcePath] = $sourceInfs[$hash] }
							}
						}
					}
				}
			}
		}
	}
	$watch.Stop()
	WriteLog "INF ownership check completed in $([math]::Round($watch.Elapsed.TotalSeconds, 2)) seconds: inspected $($candidateInfs.Count) nearby INF(s), found $($owned.Count) INF-managed file(s)."
	return [pscustomobject]@{ Owned = $owned; Referenced = $referenced }
}

function Get-DriverProvisioningCompanionFiles {
	[CmdletBinding()]
	param([string]$DriverRoot, [string]$ImagePath, [IO.FileInfo[]]$Packages, [switch]$ImageRootIsMountPoint)

	$sourceRoot = [IO.Path]::GetFullPath($DriverRoot).TrimEnd('\') + '\'
	$packagePaths = @{}
	foreach ($package in $Packages) { $packagePaths[$package.FullName] = $true }
	$discovery = [pscustomobject]@{ Copies = @{}; Blocked = @{} }
	$scriptCache = @{}
	$calledScripts = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

	# Resolve literals and known variables without evaluating OEM code.
	function Resolve-InstallerValue {
		param($Value, $Context, [string]$ScriptPath, [switch]$KeepQuotes)

		if ($Value -is [Management.Automation.Language.StringConstantExpressionAst]) { return $Value.Value }
		if ($Value -is [Management.Automation.Language.VariableExpressionAst]) {
			$name = $Value.VariablePath.UserPath
			$isEnvironment = $name -match '^env:'
			$variables = if ($name -match '^env:') { $Context.Environment } else { $Context.Variables }
			$name = $name -replace '^env:', ''
			switch ($name) {
				{ -not $isEnvironment -and $_ -in @('PSScriptRoot', 'PSCommandPath') } {
					if (-not $Context.ContainsKey('PowerShellScriptPath')) { throw "Installer variable '$name' is unavailable in an inline PowerShell command." }
					if ($name -eq 'PSScriptRoot') { return [IO.Path]::GetDirectoryName($Context.PowerShellScriptPath) }
					return $Context.PowerShellScriptPath
				}
				default {
					if ($variables.ContainsKey($name) -and $null -ne $variables[$name]) { return $variables[$name] }
					throw "Unresolved installer variable '$name'."
				}
			}
		}
		if ($Value -is [Management.Automation.Language.ExpandableStringExpressionAst]) {
			foreach ($expression in $Value.NestedExpressions) {
				if ($expression -isnot [Management.Automation.Language.VariableExpressionAst]) { throw 'Calculated installer strings are not supported.' }
			}
			return [regex]::Replace($Value.Value, '\$(?:\{(?<name>[^}]+)\}|(?<name>[\w:]+))', {
				param($match)
				$name = $match.Groups['name'].Value
				$isEnvironment = $name -match '^env:'
				$variables = if ($name -match '^env:') { $Context.Environment } else { $Context.Variables }
				$name = $name -replace '^env:', ''
				if (-not $isEnvironment -and $name -in @('PSScriptRoot', 'PSCommandPath')) {
					if (-not $Context.ContainsKey('PowerShellScriptPath')) { throw "Installer variable '$name' is unavailable in an inline PowerShell command." }
					if ($name -eq 'PSScriptRoot') { return [IO.Path]::GetDirectoryName($Context.PowerShellScriptPath) }
					return $Context.PowerShellScriptPath
				}
				if ($variables.ContainsKey($name) -and $null -ne $variables[$name]) { return $variables[$name] }
				throw "Unresolved installer variable '$name'."
			})
		}
		if ($Value -is [Management.Automation.Language.CommandExpressionAst]) { return Resolve-InstallerValue $Value.Expression $Context $ScriptPath }
		if ($Value -is [Management.Automation.Language.ParenExpressionAst]) { return Resolve-InstallerValue $Value.Pipeline $Context $ScriptPath }
		if ($Value -is [Management.Automation.Language.PipelineAst] -and $Value.PipelineElements.Count -eq 1) {
			return Resolve-InstallerValue $Value.PipelineElements[0] $Context $ScriptPath
		}
		if ($Value -is [Management.Automation.Language.StatementBlockAst] -and $Value.Statements.Count -eq 1) {
			return Resolve-InstallerValue $Value.Statements[0] $Context $ScriptPath
		}
		if ($Value -is [Management.Automation.Language.BinaryExpressionAst] -and $Value.Operator -eq 'Plus') {
			return (Resolve-InstallerValue $Value.Left $Context $ScriptPath) + (Resolve-InstallerValue $Value.Right $Context $ScriptPath)
		}
		if ($Value -is [Management.Automation.Language.CommandAst] -and $Value.GetCommandName() -eq 'Join-Path') {
			$parts = @{}
			$position = 0
			for ($index = 1; $index -lt $Value.CommandElements.Count; $index++) {
				$element = $Value.CommandElements[$index]
				if ($element -is [Management.Automation.Language.CommandParameterAst]) {
					if ($element.ParameterName -notin @('Path', 'ChildPath') -or $null -ne $element.Argument) { throw 'Unsupported installer Join-Path parameter.' }
					$key = $element.ParameterName
					$index++
					if ($index -ge $Value.CommandElements.Count) { throw 'Installer Join-Path argument is missing.' }
					$element = $Value.CommandElements[$index]
				}
				else { $key = @('Path', 'ChildPath')[$position]; $position++ }
				$parts[$key] = Resolve-InstallerValue $element $Context $ScriptPath
			}
			if ($parts.Count -ne 2 -or -not $parts.ContainsKey('Path') -or -not $parts.ContainsKey('ChildPath')) { throw 'Installer Join-Path requires a path and one child path.' }
			return [IO.Path]::Combine($parts.Path, $parts.ChildPath)
		}
		if ($Value -is [Management.Automation.Language.Ast]) { throw "Unsupported installer expression: $($Value.Extent.Text)" }
		$text = ([string]$Value).Trim()
		if (-not $KeepQuotes) { $text = $text.Trim('"') }
		return [regex]::Replace($text, '%~dp0|%~f0|%cd%|%(?<name>[^%]+)%|!(?<name>[^!]+)!', {
			param($match)
			switch -Regex ($match.Value) {
				'^%~dp0$' { return [IO.Path]::GetDirectoryName($ScriptPath).TrimEnd('\') + '\' }
				'^%~f0$' { return $ScriptPath }
				'^%cd%$' {
					if ($null -ne $Context.Directory) { return $Context.Directory }
					throw 'Installer working directory is conditional.'
				}
				default {
					$name = $match.Groups['name'].Value
					if ($Context.Variables.ContainsKey($name)) {
						$value = $Context.Variables[$name]
						if ($value -is [string]) { return $value }
						if ($null -ne $value -and $value.PSObject.Properties['Error']) { throw $value.Error }
					}
					throw "Unresolved installer variable '$name'."
				}
			}
		}, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
	}

	function Resolve-InstallerSource {
		param([string]$Value, $Context)

		if (-not [IO.Path]::IsPathRooted($Value)) {
			if ([string]::IsNullOrWhiteSpace($Context.Directory)) { throw 'Installer working directory is conditional.' }
			$Value = Join-Path $Context.Directory $Value
		}
		$fullPath = [IO.Path]::GetFullPath($Value)
		if ($fullPath.TrimEnd('\') -eq $sourceRoot.TrimEnd('\')) { return $sourceRoot.TrimEnd('\') }
		if (-not $fullPath.StartsWith($sourceRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "Installer source is outside the driver source: $fullPath" }
		return Resolve-DriverProvisioningPath -Root $sourceRoot -RelativePath $fullPath.Substring($sourceRoot.Length)
	}

	function Test-InstallerCommand {
		param([string]$Name, [string]$Text, $Context)

		if ($Name -match '^(?:(?:cmd|powershell|pwsh|copy|xcopy|robocopy|cscript|wscript)(?:\.exe)?|call|cd|chdir|set-location|pushd|push-location|popd|pop-location|install-provisioningpackage|add-provisioningpackage|dism(?:\.exe)?|copy-item|cp|cpi|if|for|else|switch)$|\.(?:cmd|bat|ps1|vbs|js|wsf)$' -or
			$Text -match '\.ppkg\b') { return $true }
		foreach ($name in $Context.Variables.Keys) {
			if ($Context.Variables[$name] -is [string] -and $Context.Variables[$name] -match '\.ppkg$' -and
				$Text -match ('(?i)(?:%|!|\$\{?)' + [regex]::Escape($name) + '(?:%|!|\}?|\b)')) { return $true }
		}
		return $false
	}

	# Track directory changes and collect explicit operations for offline execution.
	function Add-InstallerCommand {
		param([string[]]$Words, $Context, $Trace, $CallStack, [string]$ScriptPath, [int]$LineNumber, [bool]$Uncertain, [string[]]$RawWords = @())

		if ($Words.Count -eq 0) { return }
		$command = [IO.Path]::GetFileName($Words[0]).ToLowerInvariant()
		$origin = "$ScriptPath`:$LineNumber"
		if ($command -match '^(?:echo|rem|write-host|write-output|write-verbose|write-information|out-null|out-file|add-content|set-content)$') { return }
		if ($command -eq 'call' -or $command -match '^cmd(?:\.exe)?$') {
			$skip = 1
			if ($command -ne 'call') {
				if ($Words.Count -gt $skip -and $Words[$skip] -eq '/d') { $skip++ }
				if ($Words.Count -le $skip -or $Words[$skip] -ne '/c') { throw 'Unsupported installer command wrapper.' }
				$skip++
			}
			if ($Words.Count -le $skip) { throw 'Installer command wrapper is empty.' }
			if ($Words[$skip].StartsWith(':')) { throw 'Installer subroutine calls are not supported.' }
			$rawChild = if ($RawWords.Count -eq $Words.Count) { $RawWords[$skip..($RawWords.Count - 1)] } else { @() }
			Add-InstallerCommand -Words $Words[$skip..($Words.Count - 1)] -Context $Context -Trace $Trace -CallStack $CallStack -ScriptPath $ScriptPath -LineNumber $LineNumber -Uncertain $Uncertain -RawWords $rawChild
			return
		}
		if ($command -match '^powershell(?:\.exe)?$|^pwsh(?:\.exe)?$') {
			$fileIndex = [array]::IndexOf([string[]]@($Words | ForEach-Object { $_.ToLowerInvariant() }), '-file')
			if ($fileIndex -ge 0) {
				if ($fileIndex + 1 -ge $Words.Count) { throw 'Installer PowerShell file path is missing.' }
				$child = Resolve-InstallerSource $Words[$fileIndex + 1] $Context
				if ($fileIndex + 2 -ne $Words.Count) { throw 'Parameterized installer scripts are not supported.' }
				$null = $calledScripts.Add($child)
				$childContext = @{ Directory = $Context.Directory; Variables = @{}; Environment = $Context.Environment.Clone(); Directories = [Collections.Generic.Stack[string]]::new() }
				Read-InstallerScript $child $childContext $Trace $CallStack $Uncertain
			}
			else {
				$start = 1
				$explicitCommand = $false
				while ($start -lt $Words.Count -and $Words[$start].StartsWith('-')) {
					if ($Words[$start] -in @('-command', '-c')) { $start++; $explicitCommand = $true; break }
					if ($Words[$start] -in @('-executionpolicy', '-ep')) { $start += 2 }
					elseif ($Words[$start] -in @('-noprofile', '-noninteractive', '-nologo')) { $start++ }
					else { throw "Unsupported installer PowerShell option '$($Words[$start])'." }
				}
				if ($start -ge $Words.Count) { throw 'Installer PowerShell command is missing.' }
				if ($explicitCommand -and $Words.Count -eq $start + 1) { $commandText = $Words[$start] }
				elseif ($RawWords.Count -eq $Words.Count) {
					$commandText = @($RawWords[$start..($RawWords.Count - 1)] | ForEach-Object { Resolve-InstallerValue $_ $Context $ScriptPath -KeepQuotes }) -join ' '
				}
				else {
					$arguments = @($Words[$start])
					foreach ($word in @($Words | Select-Object -Skip ($start + 1))) {
						$arguments += if ($word.StartsWith('-')) { $word } else { "'" + $word.Replace("'", "''") + "'" }
					}
					$commandText = $arguments -join ' '
				}
				$childContext = @{ Directory = $Context.Directory; Variables = @{}; Environment = $Context.Environment.Clone(); Directories = [Collections.Generic.Stack[string]]::new() }
				Read-InstallerPowerShell $commandText $childContext $Trace $CallStack $ScriptPath $Uncertain $LineNumber
			}
			return
		}
		if ($command -match '\.(cmd|bat|ps1)$') {
			if ($Words.Count -ne 1) { throw 'Parameterized installer scripts are not supported.' }
			$child = Resolve-InstallerSource $Words[0] $Context
			$null = $calledScripts.Add($child)
			$childContext = $Context
			if ([IO.Path]::GetExtension($ScriptPath) -eq '.ps1' -or [IO.Path]::GetExtension($child) -eq '.ps1') {
				$variables = if ([IO.Path]::GetExtension($child) -eq '.ps1') { $Context.Variables.Clone() } else { $Context.Environment.Clone() }
				$childContext = @{ Directory = $Context.Directory; Variables = $variables; Environment = $Context.Environment; Directories = [Collections.Generic.Stack[string]]::new() }
			}
			Read-InstallerScript $child $childContext $Trace $CallStack $Uncertain
			if ([IO.Path]::GetExtension($ScriptPath) -eq '.ps1' -and [IO.Path]::GetExtension($child) -eq '.ps1') { $Context.Directory = $childContext.Directory }
			return
		}
		if ($command -in @('cd', 'chdir', 'set-location', 'pushd', 'push-location', 'popd', 'pop-location')) {
			if ($Uncertain) { $Context.Directory = $null; return }
			if ($command -in @('popd', 'pop-location')) {
				if ($Context.Directories.Count -eq 0) { throw 'Installer directory stack is empty.' }
				$Context.Directory = $Context.Directories.Pop()
			}
			else {
				$paths = @($Words | Select-Object -Skip 1 | Where-Object { $_ -notin @('/d', '-path', '-literalpath') })
				if ($paths.Count -ne 1) { throw 'Installer directory command requires one path.' }
				$directory = Resolve-InstallerSource $paths[0] $Context
				if ($command -in @('pushd', 'push-location')) { $Context.Directories.Push($Context.Directory) }
				$Context.Directory = $directory
			}
			return
		}
		$isPackage = $command -in @('install-provisioningpackage', 'add-provisioningpackage') -or
			($command -match '^dism(?:\.exe)?$' -and $Words -contains '/Add-ProvisioningPackage')
		if ($isPackage) {
			$path = $null
			for ($index = 1; $index -lt $Words.Count; $index++) {
				if ($Words[$index] -eq '-PackagePath' -and $index + 1 -lt $Words.Count) { $path = $Words[$index + 1]; break }
				if ($Words[$index] -match '^/PackagePath:(.+)$') { $path = $matches[1].Trim('"'); break }
			}
			if ([string]::IsNullOrWhiteSpace($path)) { throw 'Installer provisioning command requires an explicit package path.' }
			$path = Resolve-InstallerSource $path $Context
			if (-not $packagePaths.ContainsKey($path)) { throw "Installer provisioning package was not found: $path" }
			$Trace.Events.Add([pscustomobject]@{ Kind = 'Package'; Package = $path; Position = $Trace.Events.Count })
			if ($Uncertain) { throw 'Provisioning command depends on unsupported installer control flow.' }
			return
		}
		if ($command -notin @('copy', 'copy.exe', 'xcopy', 'xcopy.exe', 'robocopy', 'robocopy.exe', 'copy-item', 'cp', 'cpi')) {
			if ($command -in @('if', 'for', 'else', 'switch') -or $command -match '^(?:cscript|wscript)(?:\.exe)?$|\.(?:vbs|js|wsf)$' -or ($Words -match '\.ppkg(?:$|["''])')) {
				throw "Unsupported installer command '$command'."
			}
			return
		}
		if ($Uncertain) { throw 'Companion copy depends on unsupported installer control flow.' }
		$operands = [Collections.Generic.List[string]]::new()
		$source = $null
		$destination = $null
		$directoryTarget = $command -match '^robocopy'
		$literalSource = $false
		for ($index = 1; $index -lt $Words.Count; $index++) {
			$word = $Words[$index]
			if ($command -in @('copy-item', 'cp', 'cpi') -and $word.StartsWith('-')) {
				switch ($word) {
					{ $_ -in @('-path', '-literalpath', '-destination') } {
						if ($index + 1 -ge $Words.Count) { throw "Missing installer argument for '$word'." }
						$index++
						if ($word -eq '-destination') { $destination = $Words[$index] }
						else { $source = $Words[$index]; $literalSource = $word -eq '-literalpath' }
					}
					{ $_ -in @('-force', '-passthru') } { }
					'-erroraction' { $index++ }
					default { throw "Unsupported companion copy option '$word'." }
				}
			}
			elseif ($word.StartsWith('/')) {
				$allowed = if ($command -match '^xcopy') { '^/[fhrkyiv]+$' }
				elseif ($command -match '^robocopy') { '^/(?:r:\d+|w:\d+|nfl|ndl|njh|njs|np|v|copy:dat)$' }
				else { '^/[yvb]+$' }
				if ($word -notmatch $allowed) { throw "Unsupported companion copy option '$word'." }
				if ($command -match '^xcopy' -and $word -match 'i') { $directoryTarget = $true }
			}
			else { $operands.Add($word) }
		}
		$masks = @()
		if ($command -match '^robocopy') {
			if ($operands.Count -lt 3) { throw 'Companion robocopy requires a source folder, destination folder, and file names or masks.' }
			$sourceDirectory = Resolve-InstallerSource $operands[0] $Context
			$destination = $operands[1]
			$masks = @($operands | Select-Object -Skip 2)
		}
		else {
			if ($null -eq $source -and $operands.Count -gt 0) { $source = $operands[0]; $operands.RemoveAt(0) }
			if ($null -eq $destination -and $operands.Count -gt 0) { $destination = $operands[0]; $operands.RemoveAt(0) }
			if ($null -eq $source -or $null -eq $destination -or $operands.Count -gt 0) { throw 'Companion copy requires one source and one destination.' }
			$sourcePath = Resolve-InstallerSource $source $Context
			$sourceDirectory = [IO.Path]::GetDirectoryName($sourcePath)
			$masks = @([IO.Path]::GetFileName($sourcePath))
		}
		if ($destination -notmatch '^[a-z]:\\' -or $destination.Substring(2) -match ':|\*|\?' -or
			$destination.StartsWith($sourceRoot, [StringComparison]::OrdinalIgnoreCase)) {
			throw "Companion destination must be an explicit Windows drive path: $destination"
		}
		$directoryTarget = $directoryTarget -or $destination.EndsWith('\')
		$relativeTarget = ([IO.Path]::GetFullPath($destination)).Substring(3)
		$target = if ($relativeTarget) {
			Resolve-DriverProvisioningPath -Root $ImagePath -RelativePath $relativeTarget -AllowRootReparsePoint:$ImageRootIsMountPoint
		}
		else { $directoryTarget = $true; $ImagePath }
		if (Test-Path -LiteralPath $target -PathType Container) { $directoryTarget = $true }
		foreach ($mask in $masks) {
			if ($mask -match '[\\/:]') { throw "Companion file mask must stay in its source folder: $mask" }
			$files = if (-not $literalSource -and $mask -match '[*?]') {
				@(Get-ChildItem -LiteralPath $sourceDirectory -Filter $mask -File -ErrorAction Stop)
			}
			else { @(Get-Item -LiteralPath (Join-Path $sourceDirectory $mask) -ErrorAction Stop) }
			if ($files.Count -eq 0) { throw "Companion source did not match any files: $sourceDirectory\$mask" }
			if ($files.Count -gt 1 -and -not $directoryTarget) { throw 'Multiple companion files require a directory destination.' }
			foreach ($file in $files) {
				if ($file.PSIsContainer) { throw "Companion source is not a file: $($file.FullName)" }
				$null = Resolve-InstallerSource $file.FullName $Context
				$fileTarget = if ($directoryTarget) {
					$relativeFile = if ($relativeTarget) { Join-Path $relativeTarget $file.Name } else { $file.Name }
					Resolve-DriverProvisioningPath -Root $ImagePath -RelativePath $relativeFile -AllowRootReparsePoint:$ImageRootIsMountPoint
				}
				else { $target }
				$Trace.Events.Add([pscustomobject]@{ Kind = 'Copy'; Package = $null; Position = $Trace.Events.Count; Source = $file; Target = $fileTarget; AfterProvisioning = $false; Instruction = $origin })
			}
		}
	}

	function Read-InstallerPowerShell {
		param([string]$Text, $Context, $Trace, $CallStack, [string]$ScriptPath, [bool]$Uncertain, [int]$LineOffset = 1)

		$parseErrors = $null
		$ast = [Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$parseErrors)
		if ($parseErrors.Count -gt 0) { throw "Installer PowerShell syntax error: $($parseErrors[0].Message)" }
		$nodes = $ast.FindAll({
			param($node)
			$node -is [Management.Automation.Language.AssignmentStatementAst] -or $node -is [Management.Automation.Language.CommandAst] -or
			$node -is [Management.Automation.Language.ReturnStatementAst] -or $node -is [Management.Automation.Language.ExitStatementAst] -or
			$node -is [Management.Automation.Language.ThrowStatementAst] -or $node -is [Management.Automation.Language.BreakStatementAst] -or
			$node -is [Management.Automation.Language.ContinueStatementAst]
		}, $true)
		$conditionalExit = $false
		foreach ($node in $nodes) {
			$parent = $node.Parent
			$nested = $false
			$conditional = $Uncertain -or $conditionalExit
			while ($null -ne $parent -and $parent -ne $ast) {
				if ($parent -is [Management.Automation.Language.AssignmentStatementAst] -or $parent -is [Management.Automation.Language.CommandAst]) { $nested = $true; break }
				if (($parent -is [Management.Automation.Language.StatementAst] -and $parent -isnot [Management.Automation.Language.PipelineAst]) -or
					$parent -is [Management.Automation.Language.ParameterAst] -or
					$parent -is [Management.Automation.Language.ScriptBlockExpressionAst]) { $conditional = $true }
				$parent = $parent.Parent
			}
			if ($nested) { continue }
			$lineNumber = $LineOffset + $node.Extent.StartLineNumber - 1
			try {
				if ($node -is [Management.Automation.Language.ReturnStatementAst] -or $node -is [Management.Automation.Language.ExitStatementAst] -or
					$node -is [Management.Automation.Language.ThrowStatementAst] -or $node -is [Management.Automation.Language.BreakStatementAst] -or
					$node -is [Management.Automation.Language.ContinueStatementAst]) {
					if (-not $conditional) { break }
					$conditionalExit = $true
					$Trace.Events.Add([pscustomobject]@{ Kind = 'Issue'; Package = $null; Message = "$ScriptPath`:$lineNumber - Installer can terminate conditionally before completing its companion instructions." })
					continue
				}
				if ($node -is [Management.Automation.Language.AssignmentStatementAst]) {
					if ($node.Left -isnot [Management.Automation.Language.VariableExpressionAst]) { throw 'Unsupported installer assignment.' }
					$name = $node.Left.VariablePath.UserPath
					$value = if (-not $conditional -and $node.Operator -eq 'Equals') { Resolve-InstallerValue $node.Right $Context $ScriptPath } else { $null }
					if ($name -match '^env:') { $Context.Environment[$name.Substring(4)] = $value }
					else { $Context.Variables[$name] = $value }
					continue
				}
				$name = $node.GetCommandName()
				if ($name -match '^(?:Write-|Out-|Add-Content$|Set-Content$)') { continue }
				if ($null -ne $name -and -not (Test-InstallerCommand ([IO.Path]::GetFileName($name)) $node.Extent.Text $Context)) { continue }
				$words = [Collections.Generic.List[string]]::new()
				foreach ($element in $node.CommandElements) {
					if ($element -is [Management.Automation.Language.CommandParameterAst]) {
						$words.Add('-' + $element.ParameterName)
						if ($null -ne $element.Argument) { $words.Add((Resolve-InstallerValue $element.Argument $Context $ScriptPath)) }
					}
					else { $words.Add((Resolve-InstallerValue $element $Context $ScriptPath)) }
				}
				Add-InstallerCommand $words.ToArray() $Context $Trace $CallStack $ScriptPath $lineNumber $conditional
			}
			catch {
				if ($node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left -is [Management.Automation.Language.VariableExpressionAst]) {
					$name = $node.Left.VariablePath.UserPath
					if ($name -match '^env:') { $Context.Environment[$name.Substring(4)] = $null }
					else { $Context.Variables[$name] = $null }
				}
				$Trace.Events.Add([pscustomobject]@{ Kind = 'Issue'; Package = $null; Message = "$ScriptPath`:$lineNumber - $($_.Exception.Message)" })
			}
		}
	}

	function Read-InstallerScript {
		param([string]$Path, $Context, $Trace, $CallStack, [bool]$Uncertain)

		$start = $Trace.Events.Count
		$entered = $false
		try {
			$null = Resolve-InstallerSource $Path $Context
			if (-not $CallStack.Add($Path)) { $Trace.Cycle = $true; throw "Installer script call cycle: $Path" }
			$entered = $true
			if (-not $scriptCache.ContainsKey($Path)) { $scriptCache[$Path] = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop }
			$text = $scriptCache[$Path]
			if ([IO.Path]::GetExtension($Path) -eq '.ps1') {
				$Context.PowerShellScriptPath = $Path
				Read-InstallerPowerShell $text $Context $Trace $CallStack $Path $Uncertain
			}
			else {
				$lines = $text -split '\r?\n'
				$labels = @{}
				for ($index = 0; $index -lt $lines.Count; $index++) {
					if ($lines[$index] -match '^\s*:([^:\s]+)\s*$') { $labels[$matches[1]] = $index }
				}
				$visited = [Collections.Generic.HashSet[int]]::new()
				$depth = 0
				$uncertainTo = -1
				$variableStack = [Collections.Generic.Stack[hashtable]]::new()
				for ($index = 0; $index -lt $lines.Count; $index++) {
					if (-not $visited.Add($index)) { throw "Installer control-flow cycle at line $($index + 1)." }
					$lineNumber = $index + 1
					$line = $lines[$index].Trim().TrimStart('@')
					while ($line.EndsWith('^') -and $index + 1 -lt $lines.Count) { $line = $line.Substring(0, $line.Length - 1) + $lines[++$index].TrimStart() }
					if (-not $line -or $line -match '^(?:::|rem(?:\s|$)|echo(?:\s|\.|$)|:)') { continue }
					if ($line -match '^\)') { $depth = [math]::Max(0, $depth - 1); if ($line -match '\belse\b') { $depth++ }; continue }
					$conditional = $Uncertain -or $depth -gt 0 -or $index -lt $uncertainTo
					if ($line -match '^(?:if|for)\b.*\(\s*$') { $depth++; continue }
					while ($line -match '^if\s+(?:not\s+)?exist\s+("[^"]+"|\S+)\s+(.+)$') {
						$test = $matches[1]
						$body = $matches[2]
						try {
							$testPath = Resolve-InstallerSource (Resolve-InstallerValue $test $Context $Path) $Context
							$exists = Test-Path -LiteralPath $testPath
							if ($line -match '^if\s+not\s+exist\b') { $exists = -not $exists }
							$line = if ($exists) { $body } else { '' }
						}
						catch { $line = $body; $conditional = $true }
						if (-not $line) { break }
					}
					if (-not $line) { continue }
					if ($line -match '^if\b.*?\s((?:goto|call|copy|xcopy|robocopy|powershell(?:\.exe)?|set|cd|pushd|popd|exit)\b.*)$') { $line = $matches[1]; $conditional = $true }
					if ($line -match '^goto\s+:?(\S+)\s*$') {
						$label = $matches[1]
						if ($conditional) {
							$uncertainTo = if ($labels.ContainsKey($label) -and $labels[$label] -gt $index) { [math]::Max($uncertainTo, $labels[$label]) } else { $lines.Count }
						}
						elseif ($label -eq 'eof') { break }
						elseif ($labels.ContainsKey($label)) { $index = $labels[$label]; $depth = 0 }
						else { throw "Installer label was not found: $label" }
						continue
					}
					if ($line -match '^exit(?:\s|$)') { if (-not $conditional) { break }; $uncertainTo = $lines.Count; continue }
					if ($line -match '^setlocal(?:\s|$)') { $variableStack.Push(@{ Variables = $Context.Variables.Clone(); Environment = $Context.Environment.Clone() }); continue }
					if ($line -match '^endlocal(?:\s|$)') {
						if ($variableStack.Count -eq 0) { throw 'Installer variable stack is empty.' }
						$saved = $variableStack.Pop()
						$Context.Variables = $saved.Variables
						$Context.Environment = $saved.Environment
						continue
					}
					if ($line -match '^set\s+"?([^=]+)=(.*?)"?$') {
						$name = $matches[1]
						$value = $matches[2]
						try { $Context.Variables[$name] = if ($conditional) { $null } else { Resolve-InstallerValue $value $Context $Path } }
						catch {
							$Context.Variables[$name] = [pscustomobject]@{ Error = "$Path`:$lineNumber - $($_.Exception.Message)" }
						}
						$Context.Environment[$name] = $Context.Variables[$name]
						continue
					}
					try {
						$commandText = [regex]::Match($line, '^(?:"[^"]*"|[^"><&|])*').Value.TrimEnd()
						$rawWords = @([regex]::Matches($commandText, '(?:"[^"]*"|[^\s"])+') | ForEach-Object { $_.Value })
						if ($rawWords.Count -eq 0) { continue }
						$commandName = [IO.Path]::GetFileName((Resolve-InstallerValue $rawWords[0] $Context $Path))
						if (-not (Test-InstallerCommand $commandName $commandText $Context)) { continue }
						if ($line.Substring($commandText.Length).TrimStart() -match '^[&|]') { throw 'Compound installer commands are not supported.' }
						if ($line.Substring($commandText.Length).TrimStart().StartsWith('>')) { $commandText = $commandText -replace '\s+\d+$', '' }
						$rawWords = @([regex]::Matches($commandText, '(?:"[^"]*"|[^\s"])+') | ForEach-Object { $_.Value })
						$words = @($rawWords | ForEach-Object { Resolve-InstallerValue $_ $Context $Path })
						Add-InstallerCommand $words $Context $Trace $CallStack $Path $lineNumber $conditional -RawWords $rawWords
					}
					catch { $Trace.Events.Add([pscustomobject]@{ Kind = 'Issue'; Package = $null; Message = "$Path`:$lineNumber - $($_.Exception.Message)" }) }
				}
			}
		}
		catch {
			$Trace.Events.Add([pscustomobject]@{ Kind = 'Issue'; Package = $null; Message = "$Path - $($_.Exception.Message)" })
			foreach ($package in $Packages) {
				if ($package.FullName.StartsWith([IO.Path]::GetDirectoryName($Path).TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
					$Trace.Events.Add([pscustomobject]@{ Kind = 'Package'; Package = $package.FullName; Position = $Trace.Events.Count })
				}
			}
		}
		finally { if ($entered) { $null = $CallStack.Remove($Path) } }
		$events = @($Trace.Events | Select-Object -Skip $start)
		$references = @($events | Where-Object { $_.Kind -eq 'Package' })
		if ($references.Count -eq 0 -and @($events | Where-Object { $_.Kind -eq 'Issue' }).Count -gt 0 -and
			$scriptCache.ContainsKey($Path) -and $scriptCache[$Path] -match '\b(?:Install|Add)-ProvisioningPackage\b|/Add-ProvisioningPackage') {
			foreach ($package in $Packages) {
				if ($package.FullName.StartsWith([IO.Path]::GetDirectoryName($Path).TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
					$reference = [pscustomobject]@{ Kind = 'Package'; Package = $package.FullName; Position = $Trace.Events.Count }
					$Trace.Events.Add($reference)
					$references += $reference
				}
			}
		}
		$paths = @($references.Package | Select-Object -Unique)
		foreach ($entry in $events) {
			if ($entry.Kind -eq 'Package' -or $null -ne $entry.Package) { continue }
			if ($paths.Count -eq 1) {
				$entry.Package = $paths[0]
				if ($entry.Kind -eq 'Copy') { $entry.AfterProvisioning = $entry.Position -gt $references[0].Position }
			}
			elseif ($paths.Count -gt 1) {
				foreach ($packagePath in $paths) {
					$Trace.Events.Add([pscustomobject]@{ Kind = 'Issue'; Package = $packagePath; Message = "$Path - Companion instructions reference multiple packages and cannot be associated unambiguously." })
				}
			}
		}
	}

	$traces = @()
	foreach ($scriptFile in @(Get-ChildItem -LiteralPath $sourceRoot -File -Recurse -ErrorAction Stop | Where-Object { $_.Extension -in @('.cmd', '.bat', '.ps1') })) {
		$environment = @{ windir = 'C:\Windows'; systemroot = 'C:\Windows'; systemdrive = 'C:'; programdata = 'C:\ProgramData'; programfiles = 'C:\Program Files'; 'programfiles(x86)' = 'C:\Program Files (x86)' }
		$context = @{
			Directory = $scriptFile.DirectoryName
			Variables = if ($scriptFile.Extension -eq '.ps1') { @{} } else { $environment.Clone() }
			Environment = $environment
			Directories = [Collections.Generic.Stack[string]]::new()
		}
		$trace = [pscustomobject]@{ Path = $scriptFile.FullName; Events = [Collections.Generic.List[object]]::new(); Cycle = $false }
		Read-InstallerScript $scriptFile.FullName $context $trace ([Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)) $false
		$traces += $trace
	}
	# A called script must retain its caller's working directory and variables.
	$roots = @($traces | Where-Object { -not $calledScripts.Contains($_.Path) -or $_.Cycle })
	if ($roots.Count -eq 0) { $roots = $traces }
	foreach ($trace in $roots) {
		foreach ($entry in $trace.Events) {
			if ($null -eq $entry.Package) { continue }
			if ($entry.Kind -eq 'Issue') { $discovery.Blocked[$entry.Package] = $entry.Message }
			elseif ($entry.Kind -eq 'Copy') {
				if (-not $discovery.Copies.ContainsKey($entry.Package)) { $discovery.Copies[$entry.Package] = @() }
				$discovery.Copies[$entry.Package] += $entry
			}
		}
	}
	return $discovery
}

function Add-DriverProvisioningPackages {
	[CmdletBinding()]
	param([Parameter(Mandatory)][string]$ImagePath, [Parameter(Mandatory)][string]$DriverRoot, [switch]$ImageRootIsMountPoint)

	$result = [pscustomobject]@{ InfManaged = 0; Serviced = 0; Copied = 0; Failed = 0 }
	$tempPath = $null
	try {
		$imageRoot = (Get-Item -LiteralPath $ImagePath -ErrorAction Stop).FullName
		$sourceRoot = (Get-Item -LiteralPath $DriverRoot -ErrorAction Stop).FullName
		if (-not (Test-Path -LiteralPath (Join-Path $imageRoot 'Windows\System32') -PathType Container) -or
			[IO.Path]::GetFullPath((Join-Path $imageRoot 'Windows')).TrimEnd('\') -eq $env:SystemRoot.TrimEnd('\')) {
			throw "Driver provisioning requires an offline Windows installation: $ImagePath"
		}
		$null = Resolve-DriverProvisioningPath -Root $imageRoot -RelativePath 'Windows\System32' -AllowRootReparsePoint:$ImageRootIsMountPoint
		$profiles = @(Get-ChildItem -LiteralPath $sourceRoot -Filter *.ppkg -File -Recurse -ErrorAction Stop)
		if ($profiles.Count -eq 0) { WriteLog "No provisioning packages in driver source '$sourceRoot'."; return $result }
		WriteLog "Discovered $($profiles.Count) driver provisioning package(s) in '$sourceRoot'. Checking INF ownership before servicing '$imageRoot'."
		$copies = @{}
		$blocked = @{}
		$declaredPackages = @{}
		$files = @($profiles)
		foreach ($manifestFile in @(Get-ChildItem -LiteralPath $sourceRoot -Filter FFUDriverProvisioning.json -File -Recurse -ErrorAction Stop)) {
			try {
				$manifestRelativePath = $manifestFile.FullName.Substring($sourceRoot.TrimEnd('\').Length).TrimStart('\')
				$null = Resolve-DriverProvisioningPath -Root $sourceRoot -RelativePath $manifestRelativePath
				$manifest = Get-Content -LiteralPath $manifestFile.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
				if ($manifest.SchemaVersion -ne 1 -or $null -eq $manifest.Packages) { throw "Invalid provisioning manifest: $($manifestFile.FullName)" }
				foreach ($package in @($manifest.Packages)) {
					$packagePath = Resolve-DriverProvisioningPath -Root $manifestFile.DirectoryName -RelativePath $package.Path
					if ($packagePath -notin $profiles.FullName) { throw "Manifest package was not found in the driver source: $packagePath" }
					$declaredPackages[$packagePath] = $true
					foreach ($copy in @($package.CompanionFiles)) {
						if ($null -eq $copy) { continue }
						$sourcePath = Resolve-DriverProvisioningPath -Root $manifestFile.DirectoryName -RelativePath $copy.Source
						$targetPath = Resolve-DriverProvisioningPath -Root $imageRoot -RelativePath $copy.Destination -AllowRootReparsePoint:$ImageRootIsMountPoint
						$sourceFile = Get-Item -LiteralPath $sourcePath -ErrorAction Stop
						if ($sourceFile.PSIsContainer) { throw "Companion source is not a file: $sourcePath" }
						if (-not $copies.ContainsKey($packagePath)) { $copies[$packagePath] = @() }
						$copies[$packagePath] += [pscustomobject]@{ Source = $sourceFile; Target = $targetPath; AfterProvisioning = $false; Instruction = $manifestFile.FullName }
						$files += $sourceFile
					}
				}
			}
			catch {
				$result.Failed++
				$manifestRoot = $manifestFile.DirectoryName.TrimEnd('\') + '\'
				foreach ($profile in $profiles) {
					if ($profile.FullName.StartsWith($manifestRoot, [StringComparison]::OrdinalIgnoreCase)) {
						$blocked[$profile.FullName] = $_.Exception.Message
					}
				}
				WriteLog "Warning: Driver provisioning manifest failed: $($_.Exception.Message)"
				Write-Warning "Driver provisioning manifest failed: $($_.Exception.Message)"
			}
		}
		$discovery = Get-DriverProvisioningCompanionFiles -DriverRoot $sourceRoot -ImagePath $imageRoot -Packages $profiles -ImageRootIsMountPoint:$ImageRootIsMountPoint
		foreach ($packagePath in $discovery.Blocked.Keys) {
			if (-not $declaredPackages.ContainsKey($packagePath) -and -not $blocked.ContainsKey($packagePath)) { $blocked[$packagePath] = $discovery.Blocked[$packagePath] }
		}
		foreach ($packagePath in $discovery.Copies.Keys) {
			if ($declaredPackages.ContainsKey($packagePath)) { continue }
			$copies[$packagePath] = $discovery.Copies[$packagePath]
			$files += @($copies[$packagePath] | ForEach-Object { $_.Source })
		}
		$ownership = Get-DriverInfOwnedFiles -ImagePath $imageRoot -DriverRoot $sourceRoot -Files $files
		$declaredDestinations = @{}
		$conflictingDestinations = @{}
		foreach ($packagePath in $copies.Keys) {
			foreach ($copy in $copies[$packagePath]) {
				if ($ownership.Owned.ContainsKey($copy.Source.FullName)) { continue }
				$hash = (Get-FileHash -LiteralPath $copy.Source.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
				if ($declaredDestinations.ContainsKey($copy.Target) -and $declaredDestinations[$copy.Target] -ne $hash) { $conflictingDestinations[$copy.Target] = $true }
				$declaredDestinations[$copy.Target] = $hash
			}
		}
		foreach ($packagePath in $copies.Keys) {
			foreach ($copy in $copies[$packagePath]) {
				if ($conflictingDestinations.ContainsKey($copy.Target)) { $blocked[$packagePath] = "Conflicting companion copies target '$($copy.Target)'." }
			}
		}
		$processed = @{}
		$destinations = @{}
		$copyCompanions = {
			param([IO.FileInfo]$Profile, [bool]$AfterProvisioning)

			foreach ($copy in @($copies[$Profile.FullName])) {
				if ($null -eq $copy -or $copy.AfterProvisioning -ne $AfterProvisioning) { continue }
				if ($ownership.Owned.ContainsKey($copy.Source.FullName)) {
					WriteLog "Companion '$($copy.Source.Name)' is handled by INF '$($ownership.Owned[$copy.Source.FullName])'."
					continue
				}
				if ($ownership.Referenced.ContainsKey($copy.Source.FullName)) { throw "Companion '$($copy.Source.Name)' belongs to an INF whose staged content could not be verified." }
				$hash = (Get-FileHash -LiteralPath $copy.Source.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
				if ($destinations.ContainsKey($copy.Target)) { continue }
				[IO.Directory]::CreateDirectory((Split-Path $copy.Target -Parent)) | Out-Null
				Copy-Item -LiteralPath $copy.Source.FullName -Destination $copy.Target -Force -ErrorAction Stop
				if ((Get-FileHash -LiteralPath $copy.Target -Algorithm SHA256 -ErrorAction Stop).Hash -ne $hash) { throw "Companion copy verification failed: $($copy.Target)" }
				$destinations[$copy.Target] = $hash
				$result.Copied++
				WriteLog "Copied provisioning companion '$($copy.Source.FullName)' to '$($copy.Target)'. Instruction: $($copy.Instruction)"
			}
		}
		foreach ($profile in $profiles) {
			try {
				if ($blocked.ContainsKey($profile.FullName)) { throw "Companion instructions are invalid: $($blocked[$profile.FullName])" }
				$relativePath = $profile.FullName.Substring($sourceRoot.TrimEnd('\').Length).TrimStart('\')
				$null = Resolve-DriverProvisioningPath -Root $sourceRoot -RelativePath $relativePath
				$null = Test-DriverProvisioningPackage -Path $profile.FullName
				if ($ownership.Referenced.ContainsKey($profile.FullName) -and -not $ownership.Owned.ContainsKey($profile.FullName)) {
					throw "INF '$($ownership.Referenced[$profile.FullName])' references '$($profile.Name)', but its native package could not be verified in the offline driver store."
				}
				& $copyCompanions $profile $false
				if ($ownership.Owned.ContainsKey($profile.FullName)) {
					$result.InfManaged++
					WriteLog "Provisioning package '$($profile.Name)' is handled by INF '$($ownership.Owned[$profile.FullName])'."
				}
				else {
					$hash = (Get-FileHash -LiteralPath $profile.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
					if ($processed.ContainsKey($hash)) { WriteLog "Skipping duplicate provisioning package '$($profile.Name)'." }
					else {
						$tempPath = Join-Path $env:TEMP ('FFUPpkg_' + [guid]::NewGuid().ToString('N').Substring(0, 12))
						[IO.Directory]::CreateDirectory($tempPath) | Out-Null
						$nativeLogPath = Join-Path $tempPath 'dism.log'
						# A trailing backslash would escape the closing quote for a drive-root image.
						$dismImagePath = $imageRoot.TrimEnd('\') + '\.'
						$arguments = "/Image:`"$dismImagePath`" /Add-ProvisioningPackage /PackagePath:`"$($profile.FullName)`" /LogPath:`"$nativeLogPath`""
						$catalogPath = [IO.Path]::ChangeExtension($profile.FullName, '.cat')
						if (Test-Path -LiteralPath $catalogPath -PathType Leaf) {
							$null = Resolve-DriverProvisioningPath -Root $sourceRoot -RelativePath $catalogPath.Substring($sourceRoot.TrimEnd('\').Length).TrimStart('\')
							$arguments += " /CatalogPath:`"$catalogPath`""
						}
						WriteLog "Adding standalone provisioning package '$($profile.FullName)'. Command: dism.exe $arguments"
						$exitCode = Invoke-Process -FilePath dism.exe -ArgumentList $arguments -IgnoreExitCode -PassThruExitCode -ErrorAction Stop
						if ($null -eq $exitCode) { throw 'Provisioning servicing did not return an exit code.' }
						if ($exitCode -notin @(0, 3010)) { throw "Provisioning servicing failed with exit code $exitCode." }
						$processed[$hash] = $true
						$result.Serviced++
						WriteLog "Offline provisioning succeeded for '$($profile.Name)'. ExitCode: $exitCode."
					}
				}
				& $copyCompanions $profile $true
			}
			catch {
				$result.Failed++
				WriteLog "Warning: Provisioning package '$($profile.FullName)' failed: $($_.Exception.Message)"
				Write-Warning "Provisioning package '$($profile.Name)' failed: $($_.Exception.Message)"
				if ($tempPath -and (Test-Path -LiteralPath (Join-Path $tempPath 'dism.log'))) {
					WriteLog (Get-Content -LiteralPath (Join-Path $tempPath 'dism.log') -Raw -ErrorAction Stop)
				}
			}
			finally {
				if ($tempPath) {
					try { Remove-Item -LiteralPath $tempPath -Recurse -Force -ErrorAction Stop }
					catch {
						$result.Failed++
						WriteLog "Warning: Provisioning workspace cleanup failed for '$tempPath': $($_.Exception.Message)"
						Write-Warning "Provisioning workspace cleanup failed for '$tempPath': $($_.Exception.Message)"
					}
					$tempPath = $null
				}
			}
		}
	}
	catch {
		$result.Failed++
		WriteLog "Warning: Driver provisioning could not complete: $($_.Exception.Message)"
		Write-Warning "Driver provisioning could not complete: $($_.Exception.Message)"
	}
	WriteLog "Driver provisioning summary: $($result.InfManaged) INF-managed, $($result.Serviced) serviced offline, $($result.Copied) companion copies, $($result.Failed) failure(s)."
	return $result
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
$version = '2609.1'
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

    $diskSelection = Read-MenuSelection -Prompt 'Enter the disk number to apply the FFU to' -InvalidInputMessage 'Invalid disk number. Please select from the available disks.' -ValidSelections $validDiskIndexes

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
    $FFUSelected = Read-MenuSelection -Prompt 'Enter the FFU number to install' -InvalidInputMessage 'Input was not in correct format. Please enter a valid FFU number.' -Minimum 1 -Maximum $FFUCount
    $FFUSelected = $FFUSelected - 1

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
$UnattendSourceFilePath = $UnattendFolder + "unattend.xml"
$UnattendWorkingFilePath = Join-Path -Path $env:TEMP -ChildPath 'unattend.xml'
$UnattendPrefixPath = $UnattendFolder + "prefixes.txt"
$UnattendComputerNamePath = $UnattendFolder + "SerialComputerNames.csv"
If (Test-Path -Path $UnattendSourceFilePath) {
    $UnattendSourceFile = Get-ChildItem -Path $UnattendSourceFilePath
    If ($UnattendSourceFile) {
        try {
            WriteLog "Copying source unattend file $($UnattendSourceFile.FullName) to temporary working file $UnattendWorkingFilePath"
            Copy-Item -Path $UnattendSourceFile.FullName -Destination $UnattendWorkingFilePath -Force -ErrorAction Stop
            $UnattendFile = Get-ChildItem -Path $UnattendWorkingFilePath -ErrorAction Stop
            WriteLog "Using temporary unattend working file $($UnattendFile.FullName)"
            $Unattend = $true
        }
        catch {
            WriteLog "Copying source unattend file to temporary working file failed with error: $_"
            Stop-Script -Message "Copying source unattend file to temporary working file failed with error: $_"
        }
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

$UnattendConfiguredComputerName = $null
$RequiresLegacyDeviceNamePrompt = $false
$RequiresTemplateDeviceName = $false
if ($Unattend) {
    $UnattendConfiguredComputerName = Get-UnattendComputerNameValue
    $RequiresLegacyDeviceNamePrompt = Test-LegacyPromptComputerName($UnattendConfiguredComputerName)
    if (-not [string]::IsNullOrWhiteSpace($UnattendConfiguredComputerName) -and $UnattendConfiguredComputerName -match '(?i)%serial%') {
        $RequiresTemplateDeviceName = $true
    }
}

#Ask for device name if naming is explicitly required
If ($UnattendPrefix -or $UnattendComputerName -or $RequiresTemplateDeviceName -or $RequiresLegacyDeviceNamePrompt) {
    Write-SectionHeader 'Device Name Selection'
    if ($Unattend -and $UnattendPrefix) {
        Writelog 'Unattend file found with prefixes.txt. Getting prefixes.'
        $UnattendPrefixes = @(Get-content $UnattendPrefixFile)
        $UnattendPrefixCount = $UnattendPrefixes.Count
        $skipPrefixSelection = $false
        $PrefixToUse = $null
        If ($UnattendPrefixCount -gt 1) {
            WriteLog "Found $UnattendPrefixCount Prefixes"
            $array = @()
            for ($i = 0; $i -le $UnattendPrefixCount - 1; $i++) {
                $Properties = [ordered]@{Number = $i + 1 ; DeviceNamePrefix = $UnattendPrefixes[$i] }
                $array += New-Object PSObject -Property $Properties
            }
            $array | Format-Table -AutoSize -Property Number, DeviceNamePrefix
            $prefixSelection = Read-MenuSelection -Prompt 'Enter the prefix number to use for the device name (0 to skip)' -InvalidInputMessage 'Input was not in correct format. Please enter 0 to skip or a valid prefix number.' -Minimum 1 -Maximum $UnattendPrefixCount -AllowSkip
            if ($prefixSelection -eq 0) {
                $skipPrefixSelection = $true
                WriteLog 'User chose to skip device name prefix selection. Existing unattend computer name will remain unchanged.'
                Write-Host "`nDevice name prefix selection was skipped. The existing unattend computer name will remain unchanged."
            }
            else {
                $PrefixSelected = $prefixSelection - 1
                $PrefixToUse = $array[$PrefixSelected].DeviceNamePrefix
                WriteLog "$PrefixToUse was selected"
                Write-Host "`n$PrefixToUse was selected as device name prefix"
            }
        }
        elseif ($UnattendPrefixCount -eq 1) {
            WriteLog "Found $UnattendPrefixCount Prefix"
            Write-Host "Found $UnattendPrefixCount Prefix"
            $PrefixToUse = $UnattendPrefixes[0]
            WriteLog "Will use $PrefixToUse as device name prefix"
            Write-Host "Will use $PrefixToUse as device name prefix"
        }
        if (-not $skipPrefixSelection) {
            $serial = (Get-CimInstance -ClassName win32_bios).SerialNumber.Trim()
            $computername = Set-ConfiguredComputerName($PrefixToUse + $serial)
        }
    }
    elseif ($Unattend -and $UnattendComputerName) {
        Writelog 'Unattend file found with SerialComputerNames.csv. Getting name for current computer.'
        $SerialComputerNames = Import-Csv -Path $UnattendComputerNameFile.FullName -Delimiter ","

        $SerialNumber = (Get-CimInstance -Class Win32_Bios).SerialNumber
        $SCName = $SerialComputerNames | Where-Object { $_.SerialNumber -eq $SerialNumber }

        If ($SCName) {
            [string]$computername = Set-ConfiguredComputerName($SCName.ComputerName)
        }
        else {
            Writelog 'No matching serial number found in SerialComputerNames.csv. Setting random computer name to complete setup.'
            Write-Host 'No matching serial number found in SerialComputerNames.csv. Setting random computer name to complete setup.'
            [string]$computername = Set-ConfiguredComputerName(("FFU-" + ( -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 11 | ForEach-Object { [char]$_ }))))
        }
    }
    elseif ($Unattend -and $RequiresTemplateDeviceName) {
        Writelog 'Unattend file found with a %serial% computer name template. Resolving the template.'
        $serialNumber = (Get-CimInstance -ClassName Win32_Bios).SerialNumber.Trim()
        [string]$computername = Set-ConfiguredComputerName((Resolve-ComputerNameTemplate -computerNameTemplate $UnattendConfiguredComputerName -serialNumber $serialNumber))
    }
    elseif ($Unattend -and $RequiresLegacyDeviceNamePrompt) {
        Writelog 'Unattend file found with no prefixes.txt, asking for name'
        Write-Host 'Unattend file found but no prefixes.txt. Please enter a device name.'
        [string]$computername = Set-ConfiguredComputerName((Read-Host 'Enter device name'))
    }
    else {
        WriteLog 'Device naming assets detected without unattend.xml. Skipping device naming prompts.'
    }
}
elseif ($Unattend) {
    WriteLog 'Unattend file found. Device naming is not required, but unattend settings will still be applied.'
}
else {
    WriteLog 'No unattend folder found. Device name will be set via PPKG, AP JSON, or default OS name.'
}

#If both AP and PPKG folder found with files, ask which to use.
If ($autopilot -eq $true -and $PPKG -eq $true) {
    WriteLog 'Both PPKG and Autopilot json files found'
    Write-Host 'Both Autopilot JSON files and Provisioning packages were found.'
    $APorPPKG = Read-MenuSelection -Prompt 'Enter 1 for Autopilot or 2 for Provisioning Package' -InvalidInputMessage 'Incorrect value. Please enter 1 for Autopilot or 2 for Provisioning Package.' -Minimum 1 -Maximum 2
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
    $APFileSelection = Read-MenuSelection -Prompt 'Enter the AP json file number to install (0 to skip)' -InvalidInputMessage 'Input was not in correct format. Please enter 0 to skip or a valid AP json file number.' -Minimum 1 -Maximum $APFilesCount -AllowSkip

    if ($APFileSelection -eq 0) {
        $APFileToInstall = $null
        $APFileName = $null
        WriteLog 'User chose to skip Autopilot JSON selection.'
        Write-Host "`nAutopilot JSON selection was skipped."
    }
    else {
        $APFileSelected = $APFileSelection - 1
        $APFileToInstall = $array[$APFileSelected].APFile
        $APFileName = $array[$APFileSelected].APFileName
        WriteLog "$APFileToInstall was selected"
    }
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
    $PPKGFileSelection = Read-MenuSelection -Prompt 'Enter the PPKG file number to install (0 to skip)' -InvalidInputMessage 'Input was not in correct format. Please enter 0 to skip or a valid PPKG file number.' -Minimum 1 -Maximum $PPKGFilesCount -AllowSkip

    if ($PPKGFileSelection -eq 0) {
        $PPKGFileToInstall = $null
        WriteLog 'User chose to skip Provisioning Package selection.'
        Write-Host "`nProvisioning Package selection was skipped."
    }
    else {
        $PPKGFileSelected = $PPKGFileSelection - 1
        $PPKGFileToInstall = $array[$PPKGFileSelected].PPKGFile
        WriteLog "$PPKGFileToInstall was selected"
        Write-Host "`n$PPKGFileToInstall will be used"
    }
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
                $userSelection = Read-MenuSelection -Prompt 'Enter the number of the driver source to install (0 to skip)' -InvalidInputMessage 'Input was not in correct format. Please enter 0 to skip or a valid number.' -Minimum 1 -Maximum $DriverSourcesCount -AllowSkip
                if ($userSelection -eq 0) {
                    $skipDriverInstall = $true
                }
                else {
                    $DriverSelected = $userSelection - 1
                }

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

function Get-WindowsPartitionFromAppliedDisk {
    param(
        [Parameter(Mandatory)]
        [int]$DiskNumber
    )

    $basicDataPartitions = @(Get-Partition -DiskNumber $DiskNumber | Where-Object { $_.GptType -eq '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}' })
    foreach ($partition in $basicDataPartitions) {
        if ([string]::IsNullOrWhiteSpace($partition.DriveLetter)) { continue }
        $volume = Get-Volume -DriveLetter $partition.DriveLetter -ErrorAction SilentlyContinue
        if ($null -ne $volume -and $volume.FileSystemLabel -eq 'Windows') {
            return $partition
        }
    }

    return $basicDataPartitions | Select-Object -First 1
}

# Verify Windows partition exists and assign drive letter
$windowsPartition = Get-WindowsPartitionFromAppliedDisk -DiskNumber $DiskID
if ($null -eq $windowsPartition) {
    $errorMessage = "Windows partition not found after applying FFU, even though DISM reported success."
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

$dataPartitionDriveLetterDeploymentContext = $null
try {
    $dataPartitionDriveLetterDeploymentContext = Get-FFUDataPartitionDriveLetterDeploymentContext -WindowsPartitionRoot 'W:\'
}
catch {
    WriteLog "Validating data partition drive-letter deployment artifacts failed with error: $_"
    Stop-Script -Message "Validating data partition drive-letter deployment artifacts failed with error: $_"
}

$recoveryPartition = Get-Partition -DiskNumber $DiskID | Where-Object Type -eq Recovery | Select-Object -First 1
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
    if ($null -eq $recoveryPartition) {
        $errorMessage = 'Recovery partition not found after applying FFU. Cannot copy modified WinRE.'
        WriteLog $errorMessage
        Stop-Script -Message $errorMessage
    }
    Set-Partition -InputObject $recoveryPartition -NewDriveLetter R
    Invoke-Process xcopy.exe "/h $WinRE R:\Recovery\WindowsRE\ /Y"
    WriteLog 'Copying WinRE to Recovery directory succeeded'
    WriteLog 'Registering location of recovery tools'
    Invoke-Process W:\Windows\System32\Reagentc.exe "/Setreimage /Path R:\Recovery\WindowsRE /Target W:\Windows"
    Remove-PartitionAccessPath -InputObject $recoveryPartition -AccessPath R:
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
If ($Unattend) {
    $unattendSectionTitle = if ($computername) { 'Applying Computer Name and Unattend Configuration' } else { 'Applying Unattend Configuration' }
    Write-SectionHeader -Title $unattendSectionTitle
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
        WriteLog 'Copying Unattend.xml to Panther failed'
        Stop-Script -Message "Copying Unattend.xml to Panther failed with error: $_"
    }   
}

if ($null -ne $dataPartitionDriveLetterDeploymentContext) {
    $deploymentUnattendPath = 'W:\Windows\Panther\Unattend.xml'
    try {
        if ($Unattend) {
            WriteLog "Merging data partition drive-letter assignment into custom unattend at $deploymentUnattendPath."
            Add-FFUDataPartitionDriveLetterCommandToAppliedUnattend -UnattendPath $deploymentUnattendPath -ProcessorArchitecture $dataPartitionDriveLetterDeploymentContext.ProcessorArchitecture
        }
        else {
            WriteLog "No custom unattend was supplied. Verifying the FFU-embedded data partition drive-letter command at $deploymentUnattendPath."
        }

        Test-FFUDataPartitionDriveLetterCommandInAppliedUnattend -UnattendPath $deploymentUnattendPath -ProcessorArchitecture $dataPartitionDriveLetterDeploymentContext.ProcessorArchitecture
    }
    catch {
        WriteLog "Preparing data partition drive-letter deployment hook failed with error: $_"
        Stop-Script -Message "Preparing data partition drive-letter deployment hook failed with error: $_"
    }
}

# Add Drivers
if ($null -ne $DriverSourcePath) {
    Write-SectionHeader -Title 'Installing Drivers'
    if ($DriverSourceType -eq 'WIM') {
        WriteLog "Installing drivers from WIM: $DriverSourcePath"
        Write-Host "Installing drivers from WIM: $DriverSourcePath"
        $TempDriverDir = "W:\TempDrivers"
		$driverWimMounted = $false
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
			$driverWimMounted = $true
            WriteLog "WIM mount successful."

            # Inject drivers into the offline Windows image; failures here should not stop deployment
            WriteLog "Injecting drivers from $TempDriverDir"
            Write-Host "Injecting drivers from $TempDriverDir"
            Write-Host "This may take a while, please be patient."
			$driverInjectExitCode = 0
			if (Get-ChildItem -LiteralPath $TempDriverDir -Filter *.inf -File -Recurse -ErrorAction Stop | Select-Object -First 1) {
				$driverInjectExitCode = Invoke-Process -FilePath dism.exe -ArgumentList "/image:W:\ /Add-Driver /Driver:""$TempDriverDir"" /Recurse" -IgnoreExitCode -PassThruExitCode
			}
			else { WriteLog 'No INF drivers in the selected WIM; checking standalone provisioning packages.' }
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
			if ($driverWimMounted) {
				$provisioningResult = Add-DriverProvisioningPackages -ImagePath 'W:\' -DriverRoot $TempDriverDir
				if ($provisioningResult.Failed -gt 0) {
					Write-Host "Warning: Driver provisioning completed with $($provisioningResult.Failed) failure(s). Check scriptlog.txt." -ForegroundColor Yellow
				}
			}
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
		$shortDriverPath = $null
        try {
            # Use SUBST to shorten long paths for DISM /Add-Driver
            $substMapping = New-DriverSubstMapping -SourcePath $DriverSourcePath
            $shortDriverPath = $substMapping.DrivePath
            WriteLog "Injecting drivers from folder via SUBST. Source: $DriverSourcePath, Mapped: $($substMapping.DriveName)"
            Write-Host "Injecting drivers from folder: $shortDriverPath"
            Write-Host "This may take a while, please be patient."

            # Inject drivers into the offline Windows image; failures here should not stop deployment
			$driverInjectExitCode = 0
			if (Get-ChildItem -LiteralPath $shortDriverPath -Filter *.inf -File -Recurse -ErrorAction Stop | Select-Object -First 1) {
				$driverInjectExitCode = Invoke-Process -FilePath dism.exe -ArgumentList "/image:W:\ /Add-Driver /Driver:$shortDriverPath /Recurse" -IgnoreExitCode -PassThruExitCode
			}
			else { WriteLog 'No INF drivers in the selected folder; checking standalone provisioning packages.' }
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
			if ($shortDriverPath) {
				$provisioningResult = Add-DriverProvisioningPackages -ImagePath 'W:\' -DriverRoot $shortDriverPath
				if ($provisioningResult.Failed -gt 0) {
					Write-Host "Warning: Driver provisioning completed with $($provisioningResult.Failed) failure(s). Check scriptlog.txt." -ForegroundColor Yellow
				}
			}
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
#Copy DISM log to USBDrive
WriteLog "Copying dism log to $USBDrive"
invoke-process xcopy "X:\Windows\logs\dism\dism.log $USBDrive /Y" 
WriteLog "Copying dism log to $USBDrive succeeded"
