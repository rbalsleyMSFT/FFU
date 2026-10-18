<#
.SYNOPSIS
    Provides common functions for driver management, including compression, mapping, and existence checks.

.DESCRIPTION
    The FFU.Common.Drivers module contains a set of shared functions used across the FFU project for handling driver packages.
    This includes compressing driver folders into WIM files for efficient storage and deployment, maintaining a JSON-based mapping
    of downloaded drivers to their respective makes and models, and checking for the pre-existence of driver packages to avoid
    redundant downloads.
#>
function Get-DriverWorkspaceVolume {
	param([Parameter(Mandatory)][string]$Path)

	$existingPath = [IO.Path]::GetFullPath($Path)
	while (-not (Test-Path -LiteralPath $existingPath)) {
		$parentPath = Split-Path -Path $existingPath -Parent
		if ([string]::IsNullOrWhiteSpace($parentPath) -or $parentPath -eq $existingPath) {
			throw "Cannot resolve a volume for '$Path'."
		}
		$existingPath = $parentPath
	}
	$item = Get-Item -LiteralPath $existingPath -ErrorAction Stop
	$driveRoot = [IO.Path]::GetPathRoot($existingPath)
	if ($driveRoot.StartsWith('\\') -or $item.PSDrive.DisplayRoot -like '\\*' -or
		([IO.DriveInfo]::new($driveRoot)).DriveType -eq [IO.DriveType]::Network) {
		$existingPath = "$env:SystemDrive\"
	}
	$volume = Get-Volume -FilePath ($existingPath.TrimEnd('\') + '\') -ErrorAction Stop
	if ($null -eq $volume -or -not $volume.DriveLetter -or $volume.FileSystem -notin @('NTFS', 'ReFS')) {
		throw "Driver staging needs a local NTFS/ReFS volume with a drive letter. Path: '$Path'."
	}
	return $volume
}

function Confirm-DriverOperationActive {
	param([Parameter(Mandatory)][pscustomobject]$Context)

	if ($Context.Cancelled -or (Test-Path -LiteralPath $Context.CancelPath)) {
		throw [OperationCanceledException]::new("Driver operation '$($Context.OperationId)' was cancelled.")
	}
}

function New-DriverOperationContext {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)][string]$FFUDevelopmentPath,
		[Parameter(Mandatory)][string]$DriversFolder,
		[string]$RunStartUtc
	)

	$volume = Get-DriverWorkspaceVolume -Path $DriversFolder
	$operationId = [guid]::NewGuid().ToString('N')
	$ownerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
	$root = "$($volume.DriveLetter):\FFUDrv"
	$operationPath = Join-Path $root $operationId
	$context = [pscustomobject]@{
		OperationId = $operationId
		OwnerSid = $ownerSid
		OwnerPid = $PID
		OwnerStartUtc = [Diagnostics.Process]::GetCurrentProcess().StartTime.ToUniversalTime().ToString('o')
		StartedUtc = [datetime]::UtcNow.ToString('o')
		RunStartUtc = $RunStartUtc
		FFUDevelopmentPath = [IO.Path]::GetFullPath($FFUDevelopmentPath)
		DriversFolder = [IO.Path]::GetFullPath($DriversFolder)
		WorkspaceRoot = $root
		OperationPath = $operationPath
		CancelPath = Join-Path $operationPath 'cancelled'
	}
	$mutex = [Threading.Mutex]::new($false, "Global\FFUDriverWorkspaceRoot_$($volume.DriveLetter)")
	$locked = $false
	$created = $false
	$rootCreated = $false
	try {
		try { $locked = $mutex.WaitOne() }
		catch [Threading.AbandonedMutexException] {
			$locked = $true
			WriteLog 'Recovered an abandoned driver workspace-root lock; validating the directory before reuse.'
		}
		if (-not (Test-Path -LiteralPath $root)) {
			New-Item -Path $root -ItemType Directory -ErrorAction Stop | Out-Null
			$rootCreated = $true
		}
		if ((Get-Item -LiteralPath $root -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint) {
			throw "Refusing a reparse point in the driver workspace root: $root"
		}
		New-Item -Path $operationPath -ItemType Directory -ErrorAction Stop | Out-Null
		$created = $true
		$context | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $operationPath 'operation.json') -Encoding UTF8 -ErrorAction Stop
		$context | Add-Member -NotePropertyMembers @{
			ActiveJobId = $null
			Cancelled = $false
			Workspaces = [Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
		}
		WriteLog "Driver operation workspace: '$operationPath'."
		return $context
	}
	catch {
		WriteLog "Unable to create driver operation '$operationId': $($_.Exception.Message)"
		if ($created -or $rootCreated) {
			try {
				if ($created) {
					$markerPath = Join-Path $operationPath 'operation.json'
					if (Test-Path -LiteralPath $markerPath -PathType Leaf) { Remove-Item -LiteralPath $markerPath -ErrorAction Stop }
					if (-not (Get-ChildItem -LiteralPath $operationPath -Force -ErrorAction Stop)) { [IO.Directory]::Delete($operationPath) }
				}
				Remove-DriverWorkspaceRoot -Path $root
			}
			catch { WriteLog "Unable to clean the new driver operation '$operationPath': $($_.Exception.Message)" }
		}
		throw
	}
	finally {
		if ($locked) { $mutex.ReleaseMutex() }
		$mutex.Dispose()
	}
}

function Confirm-DriverOperationIdentity {
	param([Parameter(Mandatory)][pscustomobject]$Context)

	if ($Context.OperationId -notmatch '^[a-f0-9]{32}$' -or
		$Context.WorkspaceRoot -notmatch '^[A-Za-z]:\\FFUDrv$' -or
		$Context.OwnerSid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) {
		throw 'Invalid driver workspace ownership.'
	}
	$operationPath = Join-Path $Context.WorkspaceRoot $Context.OperationId
	if ($Context.OperationPath -ne $operationPath -or $Context.CancelPath -ne (Join-Path $operationPath 'cancelled')) {
		throw 'Driver operation paths do not match their owner.'
	}
	foreach ($path in @($Context.WorkspaceRoot, $operationPath)) {
		if ((Test-Path -LiteralPath $path) -and
			(Get-Item -LiteralPath $path -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint) {
			throw "Refusing a reparse point in driver operation: $path"
		}
	}
	if (Test-Path -LiteralPath $operationPath) {
		$markerPath = Join-Path $operationPath 'operation.json'
		if ((Get-Item -LiteralPath $markerPath -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint) {
			throw "Refusing a reparse point in driver ownership: $markerPath"
		}
		$marker = Get-Content -LiteralPath $markerPath -Raw -ErrorAction Stop | ConvertFrom-Json -DateKind String -ErrorAction Stop
		foreach ($property in @('OperationId', 'OwnerSid', 'OwnerPid', 'OwnerStartUtc', 'StartedUtc', 'FFUDevelopmentPath', 'DriversFolder', 'RunStartUtc')) {
			if ($marker.$property -ne $Context.$property) { throw "Driver operation ownership does not match: $operationPath" }
		}
	}
}

function Confirm-DriverDestinationPath {
	param(
		[Parameter(Mandatory)][pscustomobject]$Context,
		[Parameter(Mandatory)][string]$Path,
		[switch]$AllowRoot
	)

	$driversRoot = [IO.Path]::GetFullPath($Context.DriversFolder).TrimEnd('\')
	$destination = [IO.Path]::GetFullPath($Path)
	if (($destination.TrimEnd('\') -eq $driversRoot -and -not $AllowRoot) -or
		(-not $destination.StartsWith($driversRoot + '\', [StringComparison]::OrdinalIgnoreCase) -and
			(-not $AllowRoot -or $destination.TrimEnd('\') -ne $driversRoot))) {
		throw "Driver destination is outside the configured Drivers folder: $Path"
	}
	$currentPath = $destination
	while ($currentPath.TrimEnd('\') -ne $driversRoot) {
		if ((Test-Path -LiteralPath $currentPath) -and
			(Get-Item -LiteralPath $currentPath -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint) {
			throw "Refusing a reparse point in driver destination: $currentPath"
		}
		$currentPath = Split-Path $currentPath -Parent
	}
}

function Confirm-DriverWorkspaceOwnership {
	param([Parameter(Mandatory)][pscustomobject]$Workspace)

	$context = $Workspace.Context
	Confirm-DriverOperationIdentity -Context $context
	if ($Workspace.PackageId -notmatch '^[a-f0-9]{12}$') { throw 'Invalid driver workspace package identity.' }
	Confirm-DriverDestinationPath -Context $context -Path $Workspace.FinalPath -AllowRoot
	Confirm-DriverDestinationPath -Context $context -Path $Workspace.CachePath
	$expectedPath = Join-Path (Join-Path $context.WorkspaceRoot $context.OperationId) $Workspace.PackageId
	foreach ($path in @($context.WorkspaceRoot, (Split-Path $expectedPath -Parent))) {
		if ((Test-Path -LiteralPath $path) -and
			(Get-Item -LiteralPath $path -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint) {
			throw "Refusing a reparse point in driver workspace: $path"
		}
	}
	if ($Workspace.Path -ne $expectedPath -or
		$Workspace.OutputPath -ne (Join-Path $expectedPath 'o') -or
		$Workspace.DiagnosticsPath -ne (Join-Path $expectedPath 'd') -or
		(Split-Path $Workspace.InputPath -Parent) -ne (Join-Path $expectedPath 'i')) {
		throw "Driver workspace paths do not match their ownership record: $expectedPath"
	}
	if (Test-Path -LiteralPath $expectedPath) {
		foreach ($path in @($context.WorkspaceRoot, (Split-Path $expectedPath -Parent), $expectedPath)) {
			if ((Get-Item -LiteralPath $path -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint) {
				throw "Refusing a reparse point in driver workspace: $path"
			}
		}
		$reparseItem = Get-ChildItem -LiteralPath $expectedPath -Recurse -Force -ErrorAction Stop |
			Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint } | Select-Object -First 1
		if ($null -ne $reparseItem) { throw "Refusing driver workspace reparse point: $($reparseItem.FullName)" }
	}
}

function Get-DriverPathFreeSpace {
	param([Parameter(Mandatory)][string]$Path, [long]$RequiredBytes)

	$root = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Path))
	$driveName = 'FFUSpace' + [guid]::NewGuid().ToString('N').Substring(0, 12)
	try {
		$drive = New-PSDrive -Name $driveName -PSProvider FileSystem -Root $root -ErrorAction Stop
		$freeBytes = $drive.Free
		if ($null -eq $freeBytes) { throw "Cannot determine free disk space for '$root'." }
		if ($RequiredBytes -gt 0) {
			WriteLog "Driver volume '$root': $freeBytes bytes free; $RequiredBytes known bytes required."
		}
		if ($freeBytes -le 0 -or $freeBytes -lt $RequiredBytes) {
			throw "Insufficient disk space on '$root': $freeBytes bytes free; $RequiredBytes bytes required."
		}
		return [long]$freeBytes
	}
	finally {
		if ($null -ne $drive) { Remove-PSDrive -Name $driveName -ErrorAction Stop }
	}
}

function New-DriverExtractionWorkspace {
	[CmdletBinding()]
	param(
		[pscustomobject]$Context,
		[Parameter(Mandatory)][string]$DriversFolder,
		[Parameter(Mandatory)][string]$FileName,
		[Parameter(Mandatory)][string]$FinalPath,
		[Parameter(Mandatory)][string]$CachePath,
		[string]$ComponentName,
		[switch]$AllowShortName,
		[switch]$RetainInstallerOnFailure
	)

	$ownsOperation = $null -eq $Context
	$workspace = $null
	try {
		if ($ownsOperation) {
			$Context = New-DriverOperationContext -FFUDevelopmentPath (Split-Path $PSScriptRoot -Parent) -DriversFolder $DriversFolder
		}
		Confirm-DriverOperationIdentity -Context $Context
		Confirm-DriverOperationActive -Context $Context
		Confirm-DriverDestinationPath -Context $Context -Path $FinalPath -AllowRoot
		Confirm-DriverDestinationPath -Context $Context -Path $CachePath
		if ($FileName -ne [IO.Path]::GetFileName($FileName) -or $FileName.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
			throw "Invalid driver installer filename: '$FileName'."
		}
		$root = $Context.WorkspaceRoot
		$operationPath = Join-Path $root $Context.OperationId
		$packageId = [guid]::NewGuid().ToString('N').Substring(0, 12)
		$workspacePath = Join-Path $operationPath $packageId
		if (Test-Path -LiteralPath $workspacePath) { throw "Driver workspace collision: $workspacePath" }
		$inputPath = Join-Path (Join-Path $workspacePath 'i') $FileName
		if ($inputPath -match '\s' -or $inputPath.Length -ge 260) {
			if (-not $AllowShortName) {
				throw "Installer '$FileName' needs a short alias, but filename-independent extraction has not been verified for this package."
			}
			$inputPath = Join-Path (Join-Path $workspacePath 'i') ("p" + [IO.Path]::GetExtension($FileName))
		}
		$outputPath = Join-Path $workspacePath 'o'
		if ($outputPath.Length -gt 69 -or $outputPath -match '\s' -or $inputPath.Length -ge 260 -or $inputPath -match '\s') {
			throw "Driver workspace cannot meet the short, space-free path budget: $workspacePath"
		}
		$null = Get-DriverPathFreeSpace -Path $workspacePath
		$workspace = [pscustomobject]@{
			Context = $Context
			PackageId = $packageId
			Path = $workspacePath
			InputPath = $inputPath
			OutputPath = $outputPath
			DiagnosticsPath = Join-Path $workspacePath 'd'
			OriginalFileName = $FileName
			ComponentName = if ([string]::IsNullOrWhiteSpace($ComponentName)) { $FileName } else { $ComponentName }
			FinalPath = [IO.Path]::GetFullPath($FinalPath)
			CachePath = [IO.Path]::GetFullPath($CachePath)
			OwnsOperation = $ownsOperation
			Published = $false
			InputComplete = $false
			RetainInstallerOnFailure = [bool]$RetainInstallerOnFailure
			ExtractionStartedUtc = $null
			ProcessFilePath = $null
			PreserveLogs = $false
		}
		if (-not $Context.Workspaces.TryAdd($packageId, $workspace)) { throw "Driver workspace collision: $workspacePath" }
		New-Item -Path $workspacePath -ItemType Directory -ErrorAction Stop | Out-Null
		foreach ($leaf in @('i', 'o', 'd')) {
			New-Item -Path (Join-Path $workspacePath $leaf) -ItemType Directory -ErrorAction Stop | Out-Null
		}
		WriteLog "Driver workspace for '$($workspace.ComponentName)' ($FileName): '$inputPath' ($($inputPath.Length) characters); output '$outputPath' ($($outputPath.Length)); final '$FinalPath'."
		return $workspace
	}
	catch {
		WriteLog "Unable to prepare driver workspace for '$FileName': $($_.Exception.Message)"
		if ($null -ne $workspace) { $null = Remove-DriverExtractionWorkspace -Workspace $workspace }
		elseif ($ownsOperation -and $null -ne $Context) { Remove-DriverDownloadOperation -Context $Context }
		throw
	}
}

function Save-DriverPackageToWorkspace {
	[CmdletBinding()]
	param([Parameter(Mandatory)][pscustomobject]$Workspace, [Parameter(Mandatory)][string]$Source, [switch]$ForceDownload)

	Confirm-DriverWorkspaceOwnership -Workspace $Workspace
	Confirm-DriverOperationActive -Context $Workspace.Context
	Register-DriverWorkspaceTargets -Workspace $Workspace -Paths @($Workspace.InputPath)
	if (-not $ForceDownload -and (Test-Path -LiteralPath $Workspace.CachePath -PathType Leaf)) {
		$size = (Get-Item -LiteralPath $Workspace.CachePath -ErrorAction Stop).Length
		$null = Get-DriverPathFreeSpace -Path $Workspace.Path -RequiredBytes $size
		Copy-Item -LiteralPath $Workspace.CachePath -Destination $Workspace.InputPath -ErrorAction Stop
		WriteLog "Reused cached driver input '$($Workspace.CachePath)' in '$($Workspace.InputPath)'."
	}
	else {
		$null = Get-DriverPathFreeSpace -Path $Workspace.Path
		WriteLog 'Driver expanded size is not known; free-space checks do not guarantee enough space for extraction.'
		Start-BitsTransferWithRetry -Source $Source -Destination $Workspace.InputPath -ErrorAction Stop
	}
	Confirm-DriverOperationActive -Context $Workspace.Context
	if (-not (Test-Path -LiteralPath $Workspace.InputPath -PathType Leaf) -or
		(Get-Item -LiteralPath $Workspace.InputPath -ErrorAction Stop).Length -eq 0) {
		throw "Driver download produced no input file: $($Workspace.InputPath)"
	}
	$Workspace.InputComplete = $true
}

function Register-DriverWorkspaceTargets {
	param([Parameter(Mandatory)][pscustomobject]$Workspace, [string[]]$Paths)

	if ([string]::IsNullOrWhiteSpace($Workspace.Context.RunStartUtc) -or $Paths.Count -eq 0) { return }
	$manifestPath = Join-Path $Workspace.Context.FFUDevelopmentPath '.session\currentRun.json'
	$additionalPaths = if ($Paths.Count -gt 1) { $Paths[1..($Paths.Count - 1)] } else { @() }
	Register-CurrentRunDownloadTarget -Destination $Paths[0] -AdditionalDestinations $additionalPaths -ManifestPath $manifestPath -ExpectedRunStartUtc $Workspace.Context.RunStartUtc
}

function Test-DriverProvisioningPackage {
	[CmdletBinding()]
	param([Parameter(Mandatory)][string]$Path)

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
						$process = Invoke-Process -FilePath dism.exe -ArgumentList $arguments -Wait $true -CheckExitCode -SuccessExitCodes @(0, 3010) -ErrorAction Stop
						if ($null -eq $process -or $null -eq $process.ExitCode) { throw 'Provisioning servicing did not return an exit code.' }
						if ($process.ExitCode -notin @(0, 3010)) { throw "Provisioning servicing failed with exit code $($process.ExitCode)." }
						$processed[$hash] = $true
						$result.Serviced++
						WriteLog "Offline provisioning succeeded for '$($profile.Name)'. ExitCode: $($process.ExitCode)."
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

function Invoke-DriverExtractionProcess {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)][pscustomobject]$Workspace,
		[string]$FilePath,
		[Parameter(Mandatory)][string[]]$ArgumentList,
		[switch]$HPSoftPaq,
		[switch]$EnableInnoLogging,
		[ValidateSet('Driver', 'Xml', 'SurfaceDockWmi')][string]$ContentType = 'Driver'
	)

	Confirm-DriverWorkspaceOwnership -Workspace $Workspace
	Confirm-DriverOperationActive -Context $Workspace.Context
	if ([string]::IsNullOrWhiteSpace($FilePath)) { $FilePath = $Workspace.InputPath }
	if ($EnableInnoLogging) {
		$arguments = $ArgumentList -join ' '
		if ($arguments -match '(?:^|\s)/(?:VERYSILENT|SILENT)(?:\s|$)' -and $arguments -match '(?:^|\s)/DIR=') {
			$nativeLogPath = Join-Path $Workspace.DiagnosticsPath 'extract.log'
			$arguments = [regex]::Replace($arguments, '(?i)(?<!\S)/LOG(?:=(?:"[^"]*"|\S+))?(?=\s|$)', '').TrimEnd()
			$ArgumentList = @("$arguments /LOG=`"$nativeLogPath`"")
		}
		else {
			WriteLog "Native logging was not added for '$($Workspace.OriginalFileName)': its catalog command does not use the supported Inno Setup extraction options."
		}
	}
	$Workspace.ProcessFilePath = $FilePath
	$Workspace.ExtractionStartedUtc = [datetime]::UtcNow.ToString('o')
	WriteLog "Extracting '$($Workspace.ComponentName)' ($($Workspace.OriginalFileName)). Command: `"$FilePath`" $ArgumentList"
	$null = Get-DriverPathFreeSpace -Path $Workspace.Path
	$successExitCodes = if ($HPSoftPaq) { @(0, 1168) } else { @(0) }
	$processResult = Invoke-Process -FilePath $FilePath -ArgumentList $ArgumentList -Wait $true -CheckExitCode -SuccessExitCodes $successExitCodes -ErrorAction Stop
	Confirm-DriverOperationActive -Context $Workspace.Context
	if ($null -eq $processResult -or $null -eq $processResult.ExitCode) {
		throw "Driver extraction did not return a process exit code: $FilePath"
	}
	if ($processResult.ExitCode -notin $successExitCodes) {
		$exception = [Exception]::new("Driver extraction exited with code $($processResult.ExitCode): $FilePath")
		$exception.Data['ExitCode'] = $processResult.ExitCode
		throw $exception
	}
	if ($HPSoftPaq -and $processResult.ExitCode -eq 1168) {
		$null = Test-DriverExtractionOutput -Path $Workspace.OutputPath -ContentType $ContentType -ComponentName $Workspace.ComponentName
		WriteLog "HP SoftPaq '$($Workspace.OriginalFileName)' returned exit code 1168; accepted after verifying the extracted driver content."
	}
	return $processResult
}

function Reset-DriverExtractionOutput {
	param([Parameter(Mandatory)][pscustomobject]$Workspace)

	Confirm-DriverWorkspaceOwnership -Workspace $Workspace
	Confirm-DriverOperationActive -Context $Workspace.Context
	if (Test-Path -LiteralPath $Workspace.OutputPath) {
		foreach ($logFile in @(Get-ChildItem -LiteralPath $Workspace.Path -Filter *.log -File -Recurse -Force -ErrorAction Stop)) {
			Save-DriverExtractionLog -Workspace $Workspace -LogPath $logFile.FullName -Label $Workspace.OriginalFileName
		}
		Remove-Item -LiteralPath $Workspace.OutputPath -Recurse -Force -ErrorAction Stop
	}
	New-Item -Path $Workspace.OutputPath -ItemType Directory -ErrorAction Stop | Out-Null
}

function Test-DriverExtractionOutput {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)][string]$Path,
		[switch]$RequireInf,
		[switch]$AllowProvisioningPackage,
		[long]$MinimumBytes,
		[string[]]$ExpectedFiles,
		[string]$ComponentName,
		[ValidateSet('Driver', 'Xml', 'SurfaceDockWmi')][string]$ContentType = 'Driver'
	)

	try {
		$items = @(Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction Stop)
		if ((Get-Item -LiteralPath $Path -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint -or
			($items | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })) {
			throw "Extraction output contains a reparse point: $Path"
		}
		$files = @($items | Where-Object { -not $_.PSIsContainer -and $_.Extension -ne '.log' })
		$bytes = [long](($files | Measure-Object -Property Length -Sum).Sum)
		$infFiles = @($files | Where-Object { $_.Extension -eq '.inf' -and $_.Length -gt 0 })
		$profiles = @($files | Where-Object { $_.Extension -eq '.ppkg' })
		foreach ($profile in $profiles) {
			$null = Test-DriverProvisioningPackage -Path $profile.FullName
		}
		$signedDriver = ($files | Where-Object { $_.Extension -eq '.sys' -and $_.Length -gt 0 }) -and
			($files | Where-Object { $_.Extension -eq '.cat' -and $_.Length -gt 0 })
		if ($files.Count -eq 0 -or $bytes -le $MinimumBytes -or ($ContentType -eq 'Driver' -and
			(($RequireInf -and $infFiles.Count -eq 0 -and (-not $AllowProvisioningPackage -or $profiles.Count -eq 0)) -or
			($infFiles.Count -eq 0 -and -not $signedDriver -and $profiles.Count -eq 0)))) {
			throw "No useful driver payload in '$Path' ($($files.Count) non-log files, $bytes bytes, $($infFiles.Count) INF files)."
		}
		if ($ContentType -eq 'Xml') {
			$xmlFiles = @($files | Where-Object { $_.Extension -eq '.xml' })
			if ($xmlFiles.Count -eq 0) { throw "No XML catalog extracted in '$Path'." }
			foreach ($file in $xmlFiles) {
				$document = [xml](Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop)
				if ($null -eq $document.DocumentElement) { throw "Empty XML catalog: $($file.FullName)" }
			}
		}
		if ($ContentType -eq 'SurfaceDockWmi') {
			foreach ($name in @('SurfaceDockWmiInstanceProvider.dll', 'SurfaceDockWmiInstanceProvider.mof', 'SurfaceDockWmiInstanceProvider_Uninstall.mof')) {
				if (-not ($files | Where-Object { $_.Name -eq $name -and $_.Length -gt 0 })) {
					throw "Surface Dock WMI payload is missing or empty: $name"
				}
			}
		}
		foreach ($relativePath in $ExpectedFiles) {
			if ($relativePath -notin @($files | ForEach-Object { [IO.Path]::GetRelativePath($Path, $_.FullName) })) {
				throw "Expected driver file is missing: $relativePath"
			}
		}
		$label = if ([string]::IsNullOrWhiteSpace($ComponentName)) { $Path } else { $ComponentName }
		WriteLog "Verified driver output for '$label': $($files.Count) non-log files, $bytes bytes, $($infFiles.Count) INF files, $($profiles.Count) PPKG files. Path: '$Path'."
		return [pscustomobject]@{ Files = $files; Bytes = $bytes; InfCount = $infFiles.Count; PpkgCount = $profiles.Count }
	}
	catch {
		WriteLog "Driver output validation failed: $($_.Exception.Message)"
		throw
	}
}

function Get-DriverPublicationMutex {
	param([Parameter(Mandatory)][string]$FinalPath, [pscustomobject]$Context)

	$pathHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($FinalPath).TrimEnd('\').ToUpperInvariant())))
	$mutex = [Threading.Mutex]::new($false, "Global\FFUDriverPublish_$($pathHash.Substring(0, 24))")
	try {
		while ($true) {
			if ($null -ne $Context) { Confirm-DriverOperationActive -Context $Context }
			try { if ($mutex.WaitOne(250)) { return $mutex } }
			catch [Threading.AbandonedMutexException] {
				WriteLog "Recovered an abandoned driver lock for '$FinalPath'."
				return $mutex
			}
		}
	}
	catch {
		$mutex.Dispose()
		throw
	}
}

function Publish-DriverExtractionContent {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)][pscustomobject]$Workspace,
		[switch]$RequireInf,
		[switch]$AllowProvisioningPackage,
		[long]$MinimumBytes,
		[ValidateSet('Driver', 'Xml', 'SurfaceDockWmi')][string]$ContentType = 'Driver'
	)

	Confirm-DriverWorkspaceOwnership -Workspace $Workspace
	Confirm-DriverOperationActive -Context $Workspace.Context
	$validation = Test-DriverExtractionOutput -Path $Workspace.OutputPath -RequireInf:$RequireInf -AllowProvisioningPackage:$AllowProvisioningPackage -MinimumBytes $MinimumBytes -ContentType $ContentType -ComponentName $Workspace.ComponentName
	$manifest = @($validation.Files | ForEach-Object {
		[pscustomobject]@{ Path = [IO.Path]::GetRelativePath($Workspace.OutputPath, $_.FullName); Length = $_.Length }
	})
	$mutex = Get-DriverPublicationMutex -FinalPath $Workspace.FinalPath -Context $Workspace.Context
	$newTargets = [Collections.Generic.List[string]]::new()
	try {
		$null = Get-DriverPathFreeSpace -Path $Workspace.FinalPath -RequiredBytes $validation.Bytes
		try {
			foreach ($entry in $manifest) {
				Confirm-DriverOperationActive -Context $Workspace.Context
				$target = Join-Path $Workspace.FinalPath $entry.Path
				Confirm-DriverDestinationPath -Context $Workspace.Context -Path $target
				[IO.Directory]::CreateDirectory((Split-Path $target -Parent)) | Out-Null
				$isNew = -not (Test-Path -LiteralPath $target)
				if ($isNew) { $newTargets.Add($target) }
				[IO.File]::Copy((Join-Path $Workspace.OutputPath $entry.Path), $target, $true)
				if ($isNew) {
					$fileAcl = [Security.AccessControl.FileSecurity]::new()
					$fileAcl.SetAccessRuleProtection($false, $false)
					Set-Acl -LiteralPath $target -AclObject $fileAcl -ErrorAction Stop
				}
			}
		}
		finally {
			Register-DriverWorkspaceTargets -Workspace $Workspace -Paths $newTargets.ToArray()
		}
		Confirm-DriverOperationActive -Context $Workspace.Context
		foreach ($entry in $manifest) {
			$target = Get-Item -LiteralPath (Join-Path $Workspace.FinalPath $entry.Path) -Force -ErrorAction Stop
			if ($target.PSIsContainer -or $target.Length -ne $entry.Length) { throw "Published driver file does not match: $($target.FullName)" }
		}
		$Workspace.Published = $true
		$publishedPaths = @($manifest | ForEach-Object { Join-Path $Workspace.FinalPath $_.Path })
		if ($Workspace.CachePath -notin $publishedPaths -and (Test-Path -LiteralPath $Workspace.CachePath -PathType Leaf)) {
			try { Remove-Item -LiteralPath $Workspace.CachePath -Force -ErrorAction Stop }
			catch {
				WriteLog "Verified drivers were published, but cached installer cleanup failed for '$($Workspace.CachePath)': $($_.Exception.Message)"
				Write-Warning "Unable to remove cached driver installer '$($Workspace.CachePath)'."
			}
		}
		WriteLog "Published verified driver content to '$($Workspace.FinalPath)'."
	}
	catch {
		WriteLog "Driver publication failed for '$($Workspace.FinalPath)': $($_.Exception.Message)"
		throw
	}
	finally {
		$mutex.ReleaseMutex()
		$mutex.Dispose()
	}
}

function Save-DriverExtractionLog {
	param([pscustomobject]$Workspace, [Parameter(Mandatory)][string]$LogPath, [string]$Label)

	try {
		if (-not (Test-Path -LiteralPath $LogPath -PathType Leaf)) {
			WriteLog "Driver extraction log not found for $Label at '$LogPath'."
			return
		}
		$content = Get-Content -LiteralPath $LogPath -Raw -ErrorAction Stop
		WriteLog "Driver extraction log for $Label at '$LogPath':`n$content" -ThrowOnError
		Remove-Item -LiteralPath $LogPath -Force -ErrorAction Stop
	}
	catch {
		if ($null -ne $Workspace) { $Workspace.PreserveLogs = $true }
		WriteLog "Unable to retain driver log for $Label. Keep '$LogPath': $($_.Exception.Message)"
		throw
	}
}

function Stop-DriverWorkspaceProcess {
	param([Parameter(Mandatory)][pscustomobject]$Context)

	$startedUtc = [datetime]::Parse($Context.StartedUtc).ToUniversalTime()
	$operationRoot = $Context.OperationPath + '\'
	$inputPattern = '"' + [regex]::Escape($operationRoot) + '[a-f0-9]{12}\\i\\[^"]+"'
	$processes = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
		$null -ne $_.CreationDate -and $_.CreationDate.ToUniversalTime() -ge $startedUtc -and
		(($_.ExecutablePath -and $_.ExecutablePath.StartsWith($operationRoot, [StringComparison]::OrdinalIgnoreCase)) -or
			($_.Name -in @('msiexec.exe', 'expand.exe') -and $_.CommandLine -match $inputPattern))
	})
	function Stop-OwnedDriverProcess {
		param([Parameter(Mandatory)][object]$ProcessInfo)

		foreach ($child in @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($ProcessInfo.ProcessId)" -ErrorAction Stop |
			Where-Object { $null -ne $_.CreationDate -and $_.CreationDate -ge $ProcessInfo.CreationDate })) {
			Stop-OwnedDriverProcess -ProcessInfo $child
		}
		$process = Get-Process -Id $ProcessInfo.ProcessId -ErrorAction SilentlyContinue
		if ($null -ne $process -and [Math]::Abs(($process.StartTime.ToUniversalTime() - $ProcessInfo.CreationDate.ToUniversalTime()).TotalMilliseconds) -lt 1) {
			WriteLog "Stopping owned driver process $($process.Id) for '$($Context.OperationPath)'."
			Stop-Process -Id $process.Id -Force -ErrorAction Stop
			$process.WaitForExit()
		}
	}
	foreach ($processInfo in $processes) { Stop-OwnedDriverProcess -ProcessInfo $processInfo }
}

function Remove-DriverExtractionWorkspace {
	[CmdletBinding()]
	param([Parameter(Mandatory)][pscustomobject]$Workspace, [switch]$StopProcesses)

	try {
		Confirm-DriverWorkspaceOwnership -Workspace $Workspace
		if ($StopProcesses) { Stop-DriverWorkspaceProcess -Context $Workspace.Context }
		$cancelled = $Workspace.Context.Cancelled -or (Test-Path -LiteralPath $Workspace.Context.CancelPath)
		if (Test-Path -LiteralPath $Workspace.Path) {
			if (-not $Workspace.Published -or $Workspace.PreserveLogs) {
				$logs = @(Get-ChildItem -LiteralPath $Workspace.Path -Filter *.log -File -Recurse -Force -ErrorAction Stop)
				foreach ($logFile in $logs) {
					Save-DriverExtractionLog -Workspace $Workspace -LogPath $logFile.FullName -Label $Workspace.OriginalFileName
				}
				if ($logs.Count -eq 0 -and $Workspace.ExtractionStartedUtc) {
					WriteLog "No native extraction log is available for '$($Workspace.OriginalFileName)'; see the extraction command and error above."
				}
				$Workspace.PreserveLogs = $false
			}
			if (-not $Workspace.Published -and -not $cancelled -and $Workspace.RetainInstallerOnFailure -and $Workspace.InputComplete) {
				if (-not (Test-Path -LiteralPath $Workspace.CachePath -PathType Leaf)) {
					[IO.Directory]::CreateDirectory((Split-Path $Workspace.CachePath -Parent)) | Out-Null
					Copy-Item -LiteralPath $Workspace.InputPath -Destination $Workspace.CachePath -ErrorAction Stop
					Register-DriverWorkspaceTargets -Workspace $Workspace -Paths @($Workspace.CachePath)
				}
				WriteLog "Retained failed driver input at '$($Workspace.CachePath)'."
			}
			Remove-Item -LiteralPath $Workspace.Path -Recurse -Force -ErrorAction Stop
		}
		$removedWorkspace = $null
		$null = $Workspace.Context.Workspaces.TryRemove($Workspace.PackageId, [ref]$removedWorkspace)
		if ($Workspace.OwnsOperation) {
			Remove-DriverDownloadOperation -Context $Workspace.Context
		}
		return $true
	}
	catch {
		WriteLog "Driver workspace cleanup failed; workspace retained at '$($Workspace.Path)': $($_.Exception.Message)"
		Write-Warning "Driver workspace cleanup failed for '$($Workspace.Path)'. See the FFU log and ownership record."
		return $false
	}
}

function Expand-DriverCatalog {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)][string]$Source,
		[Parameter(Mandatory)][string]$CabPath,
		[Parameter(Mandatory)][string]$XmlPath,
		[pscustomobject]$DriverOperationContext,
		[switch]$ForceDownload,
		[switch]$KeepCab
	)

	$driversFolder = Split-Path $CabPath -Parent
	$workspace = New-DriverExtractionWorkspace -Context $DriverOperationContext -DriversFolder $driversFolder -FileName ([IO.Path]::GetFileName($CabPath)) -FinalPath (Split-Path $XmlPath -Parent) -CachePath $CabPath -AllowShortName
	try {
		Save-DriverPackageToWorkspace -Workspace $workspace -Source $Source -ForceDownload:$ForceDownload
		$shortXml = Join-Path $workspace.OutputPath 'c.xml'
		$null = Invoke-DriverExtractionProcess -Workspace $workspace -FilePath 'expand.exe' -ArgumentList "`"$($workspace.InputPath)`" `"$shortXml`""
		$null = Test-DriverExtractionOutput -Path $workspace.OutputPath -ContentType Xml -ExpectedFiles @('c.xml')
		Rename-Item -LiteralPath $shortXml -NewName ([IO.Path]::GetFileName($XmlPath)) -ErrorAction Stop
		Publish-DriverExtractionContent -Workspace $workspace -ContentType Xml
		if ($KeepCab) {
			Copy-Item -LiteralPath $workspace.InputPath -Destination $CabPath -Force -ErrorAction Stop
			Register-DriverWorkspaceTargets -Workspace $workspace -Paths @([IO.Path]::GetFullPath($CabPath))
		}
	}
	finally {
		$null = Remove-DriverExtractionWorkspace -Workspace $workspace
		if ($null -eq $DriverOperationContext) { Remove-DriverDownloadOperation -Context $workspace.Context }
	}
}

function Save-DriverCatalogFile {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)][string]$Source,
		[Parameter(Mandatory)][string]$Path,
		[pscustomobject]$DriverOperationContext
	)

	$workspace = New-DriverExtractionWorkspace -Context $DriverOperationContext -DriversFolder (Split-Path $Path -Parent) -FileName ([IO.Path]::GetFileName($Path)) -FinalPath (Split-Path $Path -Parent) -CachePath $Path -AllowShortName
	try {
		Save-DriverPackageToWorkspace -Workspace $workspace -Source $Source -ForceDownload
		Copy-Item -LiteralPath $workspace.InputPath -Destination (Join-Path $workspace.OutputPath $workspace.OriginalFileName) -ErrorAction Stop
		Publish-DriverExtractionContent -Workspace $workspace -ContentType Xml
	}
	finally {
		$null = Remove-DriverExtractionWorkspace -Workspace $workspace
		if ($null -eq $DriverOperationContext) { Remove-DriverDownloadOperation -Context $workspace.Context }
	}
}

function Remove-DriverWorkspaceRoot {
	[CmdletBinding()]
	param([Parameter(Mandatory)][string]$Path)

	$driveLetter = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Path)).Substring(0, 1)
	$mutex = [Threading.Mutex]::new($false, "Global\FFUDriverWorkspaceRoot_$driveLetter")
	$locked = $false
	try {
		try { $locked = $mutex.WaitOne() }
		catch [Threading.AbandonedMutexException] {
			$locked = $true
			WriteLog 'Recovered an abandoned driver workspace-root lock; validating the directory before cleanup.'
		}
		if (-not (Test-Path -LiteralPath $Path)) { return }
		$root = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
		if (-not $root.PSIsContainer -or $root.Attributes -band [IO.FileAttributes]::ReparsePoint) {
			throw "Refusing cleanup of an invalid driver workspace root: $Path"
		}
		if (Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop) { return }
		[IO.Directory]::Delete($Path)
		WriteLog "Removed unused driver workspace root '$Path'."
	}
	catch {
		WriteLog "Driver workspace root cleanup failed for '$Path': $($_.Exception.Message)"
		throw
	}
	finally {
		if ($locked) { $mutex.ReleaseMutex() }
		$mutex.Dispose()
	}
}

function Remove-DriverDownloadOperation {
	[CmdletBinding()]
	param(
		[pscustomobject]$Context,
		[string]$FFUDevelopmentPath,
		[string]$DriversFolder,
		[string]$RunStartUtc,
		[switch]$Cancel,
		[switch]$CancelOnly
	)

	if ($CancelOnly -and -not $Cancel) { throw 'CancelOnly requires an explicit cancellation request.' }
	if ($null -eq $Context) {
		if ([string]::IsNullOrWhiteSpace($FFUDevelopmentPath) -or [string]::IsNullOrWhiteSpace($RunStartUtc) -or
			[string]::IsNullOrWhiteSpace($DriversFolder)) {
			throw 'Driver cleanup needs an explicit operation or build-run identity.'
		}
		$volume = Get-DriverWorkspaceVolume -Path $DriversFolder
		$root = "$($volume.DriveLetter):\FFUDrv"
		if (Test-Path -LiteralPath $root) {
			if ((Get-Item -LiteralPath $root -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint) {
				throw "Refusing cleanup through a reparse point: $root"
			}
			foreach ($directory in @(Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction Stop |
				Where-Object { $_.Name -match '^[a-f0-9]{32}$' })) {
				if ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Refusing cleanup through a reparse point: $($directory.FullName)" }
				$markerPath = Join-Path $directory.FullName 'operation.json'
				$operation = Get-Content -LiteralPath $markerPath -Raw -ErrorAction Stop | ConvertFrom-Json -DateKind String -ErrorAction Stop
				if ($operation.RunStartUtc -eq $RunStartUtc -and $operation.FFUDevelopmentPath -eq [IO.Path]::GetFullPath($FFUDevelopmentPath)) {
					if ($operation.OperationPath -ne $directory.FullName) { throw "Driver ownership path does not match: $markerPath" }
					Remove-DriverDownloadOperation -Context $operation -Cancel:$Cancel -CancelOnly:$CancelOnly
				}
			}
		}
		if (-not $CancelOnly) { Remove-DriverWorkspaceRoot -Path $root }
		return
	}
	Confirm-DriverOperationIdentity -Context $Context
	$operationPath = $Context.OperationPath
	if ($Cancel) { $Context | Add-Member -NotePropertyName Cancelled -NotePropertyValue $true -Force }
	if (-not (Test-Path -LiteralPath $operationPath)) {
		if (-not $CancelOnly) { Remove-DriverWorkspaceRoot -Path $Context.WorkspaceRoot }
		return
	}
	if ($Cancel) {
		Set-Content -LiteralPath $Context.CancelPath -Value 'Cancelled' -Encoding UTF8 -ErrorAction Stop
		Stop-DriverWorkspaceProcess -Context $Context
	}
	if ($CancelOnly) { return }
	if ($null -ne $Context.Workspaces) {
		foreach ($workspace in @($Context.Workspaces.Values)) {
			$workspace.OwnsOperation = $false
			$null = Remove-DriverExtractionWorkspace -Workspace $workspace
		}
		if ($Context.Workspaces.Count -gt 0) {
			throw "Driver workspaces could not be cleaned. Keep '$operationPath' and see the FFU log."
		}
	}
	if (-not (Test-Path -LiteralPath $operationPath)) {
		Remove-DriverWorkspaceRoot -Path $Context.WorkspaceRoot
		return
	}
	Confirm-DriverOperationIdentity -Context $Context
	$items = @(Get-ChildItem -LiteralPath $operationPath -Recurse -Force -ErrorAction Stop)
	if ($items | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) { throw "Refusing cleanup of driver reparse points: $operationPath" }
	foreach ($package in @(Get-ChildItem -LiteralPath $operationPath -Directory -Force -ErrorAction Stop)) {
		if (-not $Cancel -or $package.Name -notmatch '^[a-f0-9]{12}$') { throw "Unfinished or unknown driver workspace retained: $($package.FullName)" }
		foreach ($log in @(Get-ChildItem -LiteralPath $package.FullName -Filter *.log -File -Recurse -Force -ErrorAction Stop)) {
			Save-DriverExtractionLog -LogPath $log.FullName -Label 'cancelled driver operation'
		}
		Remove-Item -LiteralPath $package.FullName -Recurse -Force -ErrorAction Stop
	}
	$unknownFiles = @(Get-ChildItem -LiteralPath $operationPath -Force -ErrorAction Stop | Where-Object { $_.Name -notin @('operation.json', 'cancelled') })
	if ($unknownFiles.Count -gt 0) { throw "Unknown files retained in driver operation: $operationPath" }
	if (Test-Path -LiteralPath $Context.CancelPath) { Remove-Item -LiteralPath $Context.CancelPath -ErrorAction Stop }
	Remove-Item -LiteralPath (Join-Path $operationPath 'operation.json') -ErrorAction Stop
	[IO.Directory]::Delete($operationPath)
	Remove-DriverWorkspaceRoot -Path $Context.WorkspaceRoot
}

function Set-DriverModelDownloadState {
	param(
		[Parameter(Mandatory)][string]$ModelPath,
		[Parameter(Mandatory)][ValidateSet('Incomplete', 'Complete')][string]$State,
		[pscustomobject]$Context
	)

	$modelRoot = [IO.Path]::GetFullPath($ModelPath).TrimEnd('\')
	$markerPath = "$modelRoot.ffu-incomplete"
	try {
		if ([string]::IsNullOrWhiteSpace([IO.Path]::GetFileName($modelRoot))) { throw "Invalid driver model path: $ModelPath" }
		if ($null -ne $Context) {
			Confirm-DriverOperationActive -Context $Context
			Confirm-DriverDestinationPath -Context $Context -Path $markerPath
		}
		if ((Test-Path -LiteralPath $markerPath) -and
			(Get-Item -LiteralPath $markerPath -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint) {
			throw "Refusing a reparse point in driver model marker: $markerPath"
		}
		if ($State -eq 'Incomplete') {
			[IO.Directory]::CreateDirectory((Split-Path $markerPath -Parent)) | Out-Null
			Set-Content -LiteralPath $markerPath -Value 'Driver download is incomplete. Download this model again.' -Encoding UTF8 -ErrorAction Stop
		}
		elseif (Test-Path -LiteralPath $markerPath) {
			Remove-Item -LiteralPath $markerPath -Force -ErrorAction Stop
		}
		WriteLog "Driver model '$ModelPath': $State."
	}
	catch {
		WriteLog "Unable to mark driver model '$ModelPath' as ${State}: $($_.Exception.Message)"
		throw
	}
}

function Test-DriverModelIncomplete {
	param([Parameter(Mandatory)][string]$ModelPath)

	return (Test-Path -LiteralPath "$([IO.Path]::GetFullPath($ModelPath).TrimEnd('\')).ffu-incomplete" -ErrorAction Stop)
}

function Invoke-DriverMsiExtraction {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)][pscustomobject]$Workspace,
		[System.Collections.Concurrent.ConcurrentQueue[hashtable]]$ProgressQueue,
		[string]$Identifier,
		[ValidateSet('Driver', 'SurfaceDockWmi')][string]$ContentType = 'Driver'
	)

	$mutex = [Threading.Mutex]::new($false, 'Global\FFUDevelopmentMSIExtractionMutex')
	$locked = $false
	try {
		while (-not $locked) {
			Confirm-DriverOperationActive -Context $Workspace.Context
			if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $Identifier -Status 'Waiting for MSI lock...' }
			try { $locked = $mutex.WaitOne(250) }
			catch [Threading.AbandonedMutexException] {
				$locked = $true
				WriteLog 'Recovered an abandoned FFU MSI lock; checking system MSI activity before extraction.'
			}
		}
		while ($true) {
			Confirm-DriverOperationActive -Context $Workspace.Context
			try {
				$systemMutex = [Threading.Mutex]::OpenExisting('Global\_MSIExecute')
				$systemMutex.Dispose()
				WriteLog "Waiting for system MSI activity before extracting '$($Workspace.OriginalFileName)'."
				Start-Sleep -Seconds 5
				continue
			}
			catch [Threading.WaitHandleCannotBeOpenedException] {
				WriteLog 'System MSI mutex clear.'
			}
			catch {
				WriteLog "Warning: System MSI mutex check failed; proceeding with the existing extraction policy: $($_.Exception.Message)"
			}
			if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $Identifier -Status 'Extracting MSI...' }
			$msiLogPath = Join-Path $Workspace.DiagnosticsPath 'msi.log'
			$arguments = "/a `"$($Workspace.InputPath)`" /qn TARGETDIR=`"$($Workspace.OutputPath)`" /L*v `"$msiLogPath`""
			try {
				$null = Invoke-DriverExtractionProcess -Workspace $Workspace -FilePath 'msiexec.exe' -ArgumentList $arguments
			}
			catch {
				if ($_.Exception.Data['ExitCode'] -eq 1618) {
					WriteLog "MSI busy (1618) for '$($Workspace.OriginalFileName)'; waiting before retry."
					Reset-DriverExtractionOutput -Workspace $Workspace
					Start-Sleep -Seconds 5
					continue
				}
				throw
			}
			try {
				$null = Test-DriverExtractionOutput -Path $Workspace.OutputPath -RequireInf -AllowProvisioningPackage -ContentType $ContentType -ComponentName $Workspace.ComponentName
				break
			}
			catch {
				$payloadItems = @(Get-ChildItem -LiteralPath $Workspace.OutputPath -File -Recurse -ErrorAction Stop |
					Where-Object { $_.Extension -notin @('.log', '.msi') })
				if ($payloadItems.Count -gt 0) { throw }
				WriteLog "MSI extraction has no useful driver content; retrying '$($Workspace.OriginalFileName)'."
				Reset-DriverExtractionOutput -Workspace $Workspace
				Start-Sleep -Seconds 5
			}
		}
		if ([IO.Path]::GetFileName($Workspace.InputPath) -ne $Workspace.OriginalFileName) {
			$administrativeMsi = Join-Path $Workspace.OutputPath ([IO.Path]::GetFileName($Workspace.InputPath))
			if (Test-Path -LiteralPath $administrativeMsi -PathType Leaf) {
				Rename-Item -LiteralPath $administrativeMsi -NewName $Workspace.OriginalFileName -ErrorAction Stop
			}
		}
	}
	finally {
		if ($locked) { $mutex.ReleaseMutex() }
		$mutex.Dispose()
	}
}

function Compress-DriverFolderToWim {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -Path $_ -PathType Container })]
        [string]$SourceFolderPath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationWimPath,

        [Parameter()]
        [string]$WimName, # Optional, defaults to folder name

        [Parameter()]
        [string]$WimDescription, # Optional, defaults to folder name

        [Parameter()]
        [bool]$PreserveSource = $false # When $true, do not delete source folder; create marker for deferred cleanup
    )

    WriteLog "Starting compression of folder '$SourceFolderPath' to '$DestinationWimPath'."

    # Default WIM Name and Description to the source folder name if not provided
    $sourceFolderName = Split-Path -Path $SourceFolderPath -Leaf
    if ([string]::IsNullOrWhiteSpace($WimName)) {
        $WimName = $sourceFolderName
        WriteLog "WIM Name not provided, defaulting to source folder name: '$WimName'."
    }
    if ([string]::IsNullOrWhiteSpace($WimDescription)) {
        $WimDescription = $sourceFolderName
        WriteLog "WIM Description not provided, defaulting to source folder name: '$WimDescription'."
    }

    # Ensure destination directory exists
    $destinationDir = Split-Path -Path $DestinationWimPath -Parent
    if (-not (Test-Path -Path $destinationDir -PathType Container)) {
        WriteLog "Creating destination directory: $destinationDir"
        try {
            New-Item -Path $destinationDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        catch {
            WriteLog "Failed to create destination directory '$destinationDir': $($_.Exception.Message)"
            return $false # Indicate failure
        }
    }

    if ($PSCmdlet.ShouldProcess("Folder '$SourceFolderPath'", "Compress to WIM '$DestinationWimPath'")) {
        try {
            # Construct arguments for dism.exe
            $dismArgs = "/Capture-Image /ImageFile:`"$DestinationWimPath`" /CaptureDir:`"$SourceFolderPath`" /Name:`"$WimName`" /Description:`"$WimDescription`" /Compress:Max /CheckIntegrity /Quiet"
            
            WriteLog "Executing dism.exe via Invoke-Process with arguments:"
            WriteLog "dism.exe $dismArgs"

            # Call Invoke-Process (assumed to be available from FFUUI.Core.psm1 or another imported module)
            # Invoke-Process is expected to throw an exception for non-zero exit codes.
            Invoke-Process -FilePath "dism.exe" -ArgumentList $dismArgs -Wait $true
            
            WriteLog "Successfully compressed '$SourceFolderPath' to '$DestinationWimPath' using dism.exe."
            
            # Remove the source folder after successful compression
            if ($PreserveSource) {
                WriteLog "Preserving source driver folder for deferred WinPE driver harvesting: $SourceFolderPath"
                try {
                    $markerFile = Join-Path -Path $SourceFolderPath -ChildPath '__PreservedForPEDrivers.txt'
                    if (-not (Test-Path -Path $markerFile -PathType Leaf)) {
                        New-Item -Path $markerFile -ItemType File -Force | Out-Null
                        WriteLog "Created preservation marker file: $markerFile"
                    }
                }
                catch {
                    WriteLog "Warning: Failed to create preservation marker in $SourceFolderPath. Error: $($_.Exception.Message)"
                }
            }
            else {
                WriteLog "Removing source driver folder: $SourceFolderPath"
                try {
                    Remove-Item -Path $SourceFolderPath -Recurse -Force -ErrorAction Stop
                    WriteLog "Successfully removed source folder '$SourceFolderPath'."
                }
                catch {
                    WriteLog "Warning: Failed to remove source folder '$SourceFolderPath'. Error: $($_.Exception.Message)"
                    # Do not fail the whole operation, just log a warning.
                }
            }

            return $true # Indicate success
        }
        catch {
            WriteLog "Failed to compress folder '$SourceFolderPath' to WIM '$DestinationWimPath' using dism.exe."
            WriteLog "Error details: $($_.Exception.Message)"
            # Check if the error message contains details about the DISM log (dism.exe output might be in the exception)
            if ($_.Exception.Message -match 'DISM log file can be found at (.*)') {
                $dismLogPath = $matches[1].Trim()
                WriteLog "Check the DISM log for more details: $dismLogPath"
            }
            return $false # Indicate failure
        }
    }
    else {
        WriteLog "Compression operation skipped due to -WhatIf."
        return $false # Indicate skipped operation
    }
}

# --------------------------------------------------------------------------
# SECTION: Driver Mapping Function
# --------------------------------------------------------------------------

function Update-DriverMappingJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$DownloadedDrivers, # Array of PSCustomObjects with Make, Model, DriverPath

        [Parameter(Mandatory = $true)]
        [string]$DriversFolder # Base drivers folder (e.g., C:\FFUDevelopment\Drivers)
    )

    $mappingFilePath = Join-Path -Path $DriversFolder -ChildPath "DriverMapping.json"
    WriteLog "Updating driver mapping file at: $mappingFilePath"

    # Load existing mapping file or create a new list
    $mappingList = [System.Collections.Generic.List[PSCustomObject]]::new()
    if (Test-Path -Path $mappingFilePath -PathType Leaf) {
        try {
            $existingJson = Get-Content -Path $mappingFilePath -Raw | ConvertFrom-Json
            # Ensure it's a collection before adding to the list
            if ($existingJson -is [array]) {
                # Iterate through the array to avoid type conversion issues with AddRange
                foreach ($item in $existingJson) {
                    $mappingList.Add($item)
                }
            }
            else {
                $mappingList.Add($existingJson)
            }
            WriteLog "Loaded $($mappingList.Count) existing entries from $mappingFilePath"
        }
        catch {
            WriteLog "Warning: Could not read or parse existing DriverMapping.json. A new file will be created. Error: $($_.Exception.Message)"
        }
    }

    $updatedCount = 0
    $addedCount = 0

    $hpSystemIdCache = @{}
    $normalizeHpName = {
        param([string]$text)

        if ([string]::IsNullOrWhiteSpace($text)) {
            return $null
        }

        return ([regex]::Replace($text.ToLowerInvariant(), '[^a-z0-9]', ''))
    }
    $getHpSystemId = {
        param([string]$modelName)

        if ([string]::IsNullOrWhiteSpace($modelName)) {
            return $null
        }

        if ($hpSystemIdCache.ContainsKey($modelName)) {
            return $hpSystemIdCache[$modelName]
        }

        $hpFolder = Join-Path -Path $DriversFolder -ChildPath 'HP'
        if (-not (Test-Path -Path $hpFolder -PathType Container)) {
            $hpSystemIdCache[$modelName] = $null
            return $null
        }

        $platformListXml = Join-Path -Path $hpFolder -ChildPath 'PlatformList.xml'
        $platformListCab = Join-Path -Path $hpFolder -ChildPath 'platformList.cab'
        if (-not (Test-Path -Path $platformListXml -PathType Leaf)) {
            try {
                WriteLog "Attempting to refresh HP PlatformList.xml for SystemID lookup."
                Start-BitsTransferWithRetry -Source 'https://hpia.hpcloud.hp.com/ref/platformList.cab' -Destination $platformListCab -ErrorAction Stop
                if (Test-Path -Path $platformListXml) { Remove-Item -Path $platformListXml -Force -ErrorAction SilentlyContinue }
                Invoke-Process -FilePath "expand.exe" -ArgumentList @("`"$platformListCab`"", "`"$platformListXml`"") -ErrorAction Stop | Out-Null
                if (Test-Path -Path $platformListCab) { Remove-Item -Path $platformListCab -Force -ErrorAction SilentlyContinue }
            }
            catch {
                WriteLog "Failed to refresh HP PlatformList.xml: $($_.Exception.Message)"
                $hpSystemIdCache[$modelName] = $null
                return $null
            }
        }

        try {
            [xml]$platformListContent = Get-Content -Path $platformListXml -Raw -Encoding UTF8 -ErrorAction Stop

            $targetName = $modelName.Trim()
            $normalizedTarget = & $normalizeHpName $targetName

            $modelMatch = $platformListContent.ImagePal.Platform | Where-Object {
                [string]::Equals($_.ProductName.'#text'.Trim(), $targetName, [System.StringComparison]::OrdinalIgnoreCase)
            } | Select-Object -First 1

            if (-not $modelMatch -and $normalizedTarget) {
                $modelMatch = $platformListContent.ImagePal.Platform | Where-Object {
                    $candidateName = $_.ProductName.'#text'
                    $normalizedCandidate = & $normalizeHpName $candidateName
                    $normalizedCandidate -eq $normalizedTarget
                } | Select-Object -First 1
            }

            if (-not $modelMatch -and $normalizedTarget) {
                $modelMatch = $platformListContent.ImagePal.Platform | Where-Object {
                    $candidateName = $_.ProductName.'#text'
                    $normalizedCandidate = & $normalizeHpName $candidateName
                    ($normalizedCandidate -like "*$normalizedTarget*") -or ($normalizedTarget -like "*$normalizedCandidate*")
                } | Select-Object -First 1
            }

            if ($modelMatch -and -not [string]::IsNullOrWhiteSpace($modelMatch.SystemID)) {
                $resolvedId = $modelMatch.SystemID.Trim().ToUpperInvariant()
                $hpSystemIdCache[$modelName] = $resolvedId
                return $resolvedId
            }
            else {
                WriteLog "HP SystemId lookup: no match found in PlatformList.xml for model '$modelName'."
            }
        }
        catch {
            WriteLog "Failed to parse HP PlatformList.xml for model '$modelName': $($_.Exception.Message)"
        }

        $hpSystemIdCache[$modelName] = $null
        return $null
    }

    foreach ($driver in $DownloadedDrivers) {
        if (-not $driver.PSObject.Properties['Make'] -or -not $driver.PSObject.Properties['Model'] -or -not $driver.PSObject.Properties['DriverPath'] -or [string]::IsNullOrWhiteSpace($driver.DriverPath)) {
            WriteLog "Skipping driver entry due to missing or empty Make, Model, or DriverPath. Details: $(($driver | ConvertTo-Json -Compress -Depth 3))"
            continue
        }

        $systemIdValue = $null
        $machineTypeValue = $null

        if ($driver.PSObject.Properties['SystemId'] -and -not [string]::IsNullOrWhiteSpace($driver.SystemId)) {
            $systemIdValue = $driver.SystemId.Trim().ToUpperInvariant()
        }
        if ($driver.PSObject.Properties['MachineType'] -and -not [string]::IsNullOrWhiteSpace($driver.MachineType)) {
            $machineTypeValue = $driver.MachineType.Trim()
        }

        switch ($driver.Make) {
            'Dell' {
                if (-not $systemIdValue -and $driver.Model -match '\(([^)]+)\)\s*$') {
                    $systemIdValue = $matches[1].Trim().ToUpperInvariant()
                }
            }
            'HP' {
                if (-not $systemIdValue) {
                    $systemIdValue = & $getHpSystemId $driver.Model
                }
            }
            'Lenovo' {
                if (-not $machineTypeValue -and $driver.Model -match '\(([^)]+)\)\s*$') {
                    $machineTypeValue = $matches[1].Trim()
                }
            }
        }

        # Microsoft Surface: resolve System SKU list (best-effort) using Sources A + C and cached results
        $surfaceSystemSkuList = @()
        if ($driver.Make -eq 'Microsoft') {
            if ($driver.PSObject.Properties['Link'] -and -not [string]::IsNullOrWhiteSpace($driver.Link)) {
                try {
                    $surfaceSystemSkuList = Get-SurfaceSystemSkuListForMicrosoftDriver -DriversFolder $DriversFolder -ModelName $driver.Model -ModelLink $driver.Link
                }
                catch {
                    WriteLog "Warning: Failed to resolve Surface SystemSku list for '$($driver.Model)'. Error: $($_.Exception.Message)"
                    $surfaceSystemSkuList = @()
                }
            }
        }

        $existingEntry = $mappingList | Where-Object { $_.Manufacturer -eq $driver.Make -and $_.Model -eq $driver.Model } | Select-Object -First 1

        if ($null -ne $existingEntry) {
            $entryUpdated = $false
            if ($existingEntry.DriverPath -ne $driver.DriverPath) {
                WriteLog "Updating driver path for '$($driver.Make) - $($driver.Model)' from '$($existingEntry.DriverPath)' to '$($driver.DriverPath)'."
                $existingEntry.DriverPath = $driver.DriverPath
                $entryUpdated = $true
            }

            if ($driver.Make -in @('HP', 'Dell') -and -not [string]::IsNullOrWhiteSpace($systemIdValue)) {
                if ($existingEntry.PSObject.Properties['SystemId']) {
                    if ($existingEntry.SystemId -ne $systemIdValue) {
                        WriteLog "Updating SystemId for '$($driver.Make) - $($driver.Model)' to '$systemIdValue'."
                        $existingEntry.SystemId = $systemIdValue
                        $entryUpdated = $true
                    }
                }
                else {
                    WriteLog "Adding SystemId '$systemIdValue' for '$($driver.Make) - $($driver.Model)'."
                    $existingEntry | Add-Member -NotePropertyName SystemId -NotePropertyValue $systemIdValue
                    $entryUpdated = $true
                }
            }

            if ($driver.Make -eq 'Lenovo' -and -not [string]::IsNullOrWhiteSpace($machineTypeValue)) {
                if ($existingEntry.PSObject.Properties['MachineType']) {
                    if ($existingEntry.MachineType -ne $machineTypeValue) {
                        WriteLog "Updating MachineType for '$($driver.Make) - $($driver.Model)' to '$machineTypeValue'."
                        $existingEntry.MachineType = $machineTypeValue
                        $entryUpdated = $true
                    }
                }
                else {
                    WriteLog "Adding MachineType '$machineTypeValue' for '$($driver.Make) - $($driver.Model)'."
                    $existingEntry | Add-Member -NotePropertyName MachineType -NotePropertyValue $machineTypeValue
                    $entryUpdated = $true
                }
            }

            if ($driver.Make -eq 'Microsoft' -and $surfaceSystemSkuList -and $surfaceSystemSkuList.Count -gt 0) {
                $desiredSkus = @($surfaceSystemSkuList | Sort-Object -Unique)
                if ($existingEntry.PSObject.Properties['SystemSku']) {
                    $currentSkus = @($existingEntry.SystemSku)
                    $currentNormalized = @($currentSkus | ForEach-Object { if ($null -ne $_) { $_.ToString().Trim().ToUpperInvariant() } }) | Sort-Object -Unique
                    $desiredNormalized = @($desiredSkus | ForEach-Object { if ($null -ne $_) { $_.ToString().Trim().ToUpperInvariant() } }) | Sort-Object -Unique

                    if (($currentNormalized -join '|') -ne ($desiredNormalized -join '|')) {
                        WriteLog "Updating SystemSku list for 'Microsoft - $($driver.Model)'."
                        $existingEntry.SystemSku = $desiredSkus
                        $entryUpdated = $true
                    }
                }
                else {
                    WriteLog "Adding SystemSku list for 'Microsoft - $($driver.Model)'."
                    $existingEntry | Add-Member -NotePropertyName SystemSku -NotePropertyValue $desiredSkus
                    $entryUpdated = $true
                }
            }

            if ($entryUpdated) {
                $updatedCount++
            }
        }
        else {
            $newEntry = [PSCustomObject]@{
                Manufacturer = $driver.Make
                Model        = $driver.Model
                DriverPath   = $driver.DriverPath
            }

            if ($driver.Make -in @('HP', 'Dell') -and -not [string]::IsNullOrWhiteSpace($systemIdValue)) {
                $newEntry | Add-Member -NotePropertyName SystemId -NotePropertyValue $systemIdValue
            }
            if ($driver.Make -eq 'Lenovo' -and -not [string]::IsNullOrWhiteSpace($machineTypeValue)) {
                $newEntry | Add-Member -NotePropertyName MachineType -NotePropertyValue $machineTypeValue
            }
            if ($driver.Make -eq 'Microsoft' -and $surfaceSystemSkuList -and $surfaceSystemSkuList.Count -gt 0) {
                $newEntry | Add-Member -NotePropertyName SystemSku -NotePropertyValue @($surfaceSystemSkuList | Sort-Object -Unique)
            }

            $mappingList.Add($newEntry)
            WriteLog "Adding new mapping for '$($driver.Make) - $($driver.Model)' with path '$($driver.DriverPath)'."
            $addedCount++
        }
    }

    if ($updatedCount -gt 0 -or $addedCount -gt 0) {
        try {
            # Sort the list for consistency before saving
            $sortedList = $mappingList | Sort-Object -Property Manufacturer, Model
            $sortedList | ConvertTo-Json -Depth 5 | Set-Content -Path $mappingFilePath -Encoding UTF8
            WriteLog "Successfully saved DriverMapping.json with $addedCount new entries and $updatedCount updated entries."
        }
        catch {
            WriteLog "Error saving updated DriverMapping.json: $($_.Exception.Message)"
            throw "Failed to save driver mapping file."
        }
    }
    else {
        WriteLog "No changes needed for DriverMapping.json."
    }
}

# --------------------------------------------------------------------------
# SECTION: Driver Existence Check Function
# --------------------------------------------------------------------------
function Test-ExistingDriver {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Make,

        [Parameter(Mandatory = $true)]
        [string]$Model,

        [Parameter(Mandatory = $true)]
        [string]$DriversFolder,

        [Parameter(Mandatory = $true)]
        [string]$Identifier,

        [Parameter()]
        [System.Collections.Concurrent.ConcurrentQueue[hashtable]]$ProgressQueue = $null
    )

    $makeDriversPath = Join-Path -Path $DriversFolder -ChildPath $Make
    $modelPath = Join-Path -Path $makeDriversPath -ChildPath $Model
    $driverRelativePath = Join-Path -Path $Make -ChildPath $Model

	if (Test-DriverModelIncomplete -ModelPath $modelPath) {
		WriteLog "Driver model '$Identifier' is incomplete; retrying its full driver list."
		return $null
	}

    # Check for WIM file first
    $wimFilePath = Join-Path -Path $makeDriversPath -ChildPath "$($Model).wim"
    if (Test-Path -Path $wimFilePath -PathType Leaf) {
        $status = "Already downloaded (WIM)"
        WriteLog "Driver WIM for '$Identifier' already exists at '$wimFilePath'."
        if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $Identifier -Status $status }
        $wimRelativePath = Join-Path -Path $Make -ChildPath "$($Model).wim"
        return [PSCustomObject]@{
            Model      = $Identifier # Return original identifier
            Status     = $status
            Success    = $true
            DriverPath = $wimRelativePath
        }
    }

    # Check for existing driver folder
    if (Test-Path -Path $modelPath -PathType Container) {
        $folderSize = (Get-ChildItem -Path $modelPath -Recurse | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        if ($folderSize -gt 1MB) {
            $status = "Already downloaded"
            WriteLog "Drivers for '$Identifier' already exist in '$modelPath'."
            if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $Identifier -Status $status }
            return [PSCustomObject]@{
                Model      = $Identifier # Return original identifier
                Status     = $status
                Success    = $true
                DriverPath = $driverRelativePath
            }
        }
        else {
            WriteLog "Driver folder '$modelPath' for '$Identifier' exists but is empty or very small. Re-downloading."
        }
    }

    # If neither WIM nor a valid folder exists, return null
    return $null
}

function ConvertTo-LenovoPSREFSigningKey {
    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$SigningSecret
    )

    if ([string]::IsNullOrWhiteSpace($SigningSecret)) {
        throw 'Lenovo PSREF authentication returned an empty signing key.'
    }
    if ($SigningSecret -notmatch '^(?:[0-9a-fA-F]{2})+$') {
        throw 'Lenovo PSREF authentication returned an unsupported signing-key representation.'
    }

    $signingKey = [byte[]]::new($SigningSecret.Length / 2)
    for ($characterIndex = 0; $characterIndex -lt $SigningSecret.Length; $characterIndex += 2) {
        $signingKey[$characterIndex / 2] = [Convert]::ToByte($SigningSecret.Substring($characterIndex, 2), 16)
    }

    return $signingKey
}

$script:LenovoPSREFAuthContext = $null

function Get-LenovoPSREFRequestHeaders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('GET', 'POST', 'PUT', 'DELETE', 'PATCH')]
        [string]$Method,
        [Parameter(Mandatory = $true)]
        [uri]$Uri,
        [Parameter()]
        [AllowEmptyString()]
        [string]$Body = '',
        [Parameter()]
        [hashtable]$Headers = @{},
        [Parameter()]
        [string]$UserAgent
    )

    $currentUnixTime = [long][Math]::Floor(([DateTime]::UtcNow - [DateTime]'1970-01-01').TotalSeconds)
    if ($null -eq $script:LenovoPSREFAuthContext -or
        $script:LenovoPSREFAuthContext.ExpiresAt - $currentUnixTime -le 120 -or
        $script:LenovoPSREFAuthContext.UserAgent -ne $UserAgent) {
        $authRequestParameters = @{
            Uri         = 'https://psref.lenovo.com/api/home/auth/issue'
            Method      = 'Post'
            ContentType = 'application/json'
            Body        = '{}'
            Headers     = @{
                Accept           = 'application/json, text/plain, */*'
                Origin           = 'https://psref.lenovo.com'
                Referer          = 'https://psref.lenovo.com/'
                'Sec-Fetch-Dest' = 'empty'
                'Sec-Fetch-Mode' = 'cors'
                'Sec-Fetch-Site' = 'same-origin'
            }
            ErrorAction = 'Stop'
        }
        if (-not [string]::IsNullOrWhiteSpace($UserAgent)) {
            $authRequestParameters.UserAgent = $UserAgent
        }

        WriteLog 'Requesting a Lenovo PSREF API access token.'
        $authResponse = Invoke-RestMethod @authRequestParameters
        $accessToken = [string]$authResponse.access_token
        if ([string]::IsNullOrWhiteSpace($accessToken)) {
            throw 'Lenovo PSREF authentication returned an empty access token.'
        }

        $tokenParts = $accessToken.Split('.')
        if ($tokenParts.Count -ne 3) {
            throw 'Lenovo PSREF authentication returned an invalid access token.'
        }

        $payloadSegment = $tokenParts[1].Replace('-', '+').Replace('_', '/')
        switch ($payloadSegment.Length % 4) {
            2 { $payloadSegment += '==' }
            3 { $payloadSegment += '=' }
            1 { throw 'Lenovo PSREF authentication returned an invalid token payload.' }
        }

        try {
            $payloadBytes = [Convert]::FromBase64String($payloadSegment)
            $tokenPayload = [Text.Encoding]::UTF8.GetString($payloadBytes) | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            throw "Unable to decode the Lenovo PSREF access token: $($_.Exception.Message)"
        }

        $signingKeyProperty = $tokenPayload.PSObject.Properties['rk']
        if ($null -eq $signingKeyProperty) {
            $signingKeyProperty = $tokenPayload.PSObject.Properties['ss']
        }
        if ($null -eq $signingKeyProperty) {
            throw 'Lenovo PSREF authentication token is missing a supported signing-key claim.'
        }
        if ($signingKeyProperty.Value -isnot [string]) {
            throw 'Lenovo PSREF authentication returned an unsupported signing-key type.'
        }

        [byte[]]$signingKey = ConvertTo-LenovoPSREFSigningKey -SigningSecret $signingKeyProperty.Value
        $expiresAt = [long]$tokenPayload.exp
        if ($expiresAt -le $currentUnixTime) {
            throw 'Lenovo PSREF authentication returned an expired access token.'
        }

        $script:LenovoPSREFAuthContext = [PSCustomObject]@{
            AccessToken = $accessToken
            SigningKey  = $signingKey
            ExpiresAt   = $expiresAt
            UserAgent   = $UserAgent
        }
        WriteLog 'Lenovo PSREF API access token acquired.'
    }

    $requestHeaders = @{}
    foreach ($key in $Headers.Keys) {
        if ($key -notmatch '^(Accept|Authorization|Cookie|Priority|Sec-|Upgrade-Insecure-Requests|X-)') {
            $requestHeaders[$key] = $Headers[$key]
        }
    }
    $requestHeaders.Accept = 'application/json, text/plain, */*'
    $requestHeaders.Referer = 'https://psref.lenovo.com/'
    $requestHeaders['Sec-Fetch-Dest'] = 'empty'
    $requestHeaders['Sec-Fetch-Mode'] = 'cors'
    $requestHeaders['Sec-Fetch-Site'] = 'same-origin'

    $bodyHash = ''
    if (-not [string]::IsNullOrEmpty($Body)) {
        $sha256 = [Security.Cryptography.SHA256]::Create()
        try {
            $bodyHashBytes = $sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($Body))
            $bodyHash = -join ($bodyHashBytes | ForEach-Object { $_.ToString('x2') })
        }
        finally {
            $sha256.Dispose()
        }
    }

    $timestamp = [long][Math]::Floor(([DateTime]::UtcNow - [DateTime]'1970-01-01').TotalSeconds)
    $nonce = [guid]::NewGuid().ToString()
    $canonicalRequest = "$($Method.ToUpperInvariant())|$($Uri.PathAndQuery)|$bodyHash|$timestamp|$nonce"
    $hmac = [Security.Cryptography.HMACSHA256]::new($script:LenovoPSREFAuthContext.SigningKey)
    try {
        $signatureBytes = $hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($canonicalRequest))
        $signature = -join ($signatureBytes | ForEach-Object { $_.ToString('x2') })
    }
    finally {
        $hmac.Dispose()
    }

    $requestHeaders.Authorization = "Bearer $($script:LenovoPSREFAuthContext.AccessToken)"
    $requestHeaders['X-Ts'] = $timestamp.ToString()
    $requestHeaders['X-Nonce'] = $nonce
    $requestHeaders['X-Sig'] = $signature
    return $requestHeaders
}

function Get-LenovoPSREFToken {

    <# 
        .DESCRIPTION
        Retrieves the Lenovo PSREF token from the Edge browser's local storage.

        .NOTES

        Lenovo's PSREF site creates a cookie/token via javascript when navigating to the PSREF site. This cookie only needs
        to be retrieved once on a single machine, and every machine within the same network will be able to access the PSREF API. 

        Using Invoke-Webrequest with sessionvariable or websession doesn't work because the token is created by javascript.
        Using edge in headless mode with remote debugging enabled allows for the retrieval of the token via the DevTools protocol.

        You couldn't be more unhappy about this solution than I am, but it works.

        Why use PSREF and not catalogv2.xml? Catalogv2.xml doesn't include all models. PSREF provides an API that can be used to retrieve
        the friendly model and machine type information for both business and consumer models. Many EDU devices are deemed consumer. 

        System Update and other tools rely on the user to input machine type and model information, but finding the machine type is difficult for some.
        Our solution makes it easier to simply type the model name and you can match the machine type to the model name.

        If you have a better solution, please submit a PR or open a discussion on Github. Happy to consider alternatives. An easy way to test
        if your alternative works is to see if you can retrieve 100e, 300w, 500w, etc. These don't show up in catalogv2.xml, but they do in PSREF.
    #>

    $token = $null
    $socket = $null
    $edgeProcess = $null
    $tempProfile = $null
    $port = $null

    function Get-FreeLocalTcpPort {
        $listener = $null
        try {
            $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
            $listener.Start()
            $endpoint = [System.Net.IPEndPoint]$listener.LocalEndpoint
            return $endpoint.Port
        }
        finally {
            if ($null -ne $listener) {
                $listener.Stop()
            }
        }
    }

    function Get-EdgeDevToolsPageTarget {
        param(
            [Parameter(Mandatory = $true)][int]$Port,
            [int]$MaxAttempts = 20,
            [int]$DelayMilliseconds = 500,
            [string]$UrlContains
        )

        for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
            try {
                $targets = Invoke-RestMethod -Uri "http://localhost:$Port/json" -ErrorAction Stop
                if ($null -ne $targets) {
                    if ($targets -isnot [System.Array]) { $targets = @($targets) }
                    $pageTargets = $targets | Where-Object { $_.type -eq 'page' }
                    if (-not [string]::IsNullOrWhiteSpace($UrlContains)) {
                        $pageTargets = $pageTargets | Where-Object {
                            -not [string]::IsNullOrWhiteSpace($_.url) -and $_.url -like "*$UrlContains*"
                        }
                    }

                    $target = $pageTargets | Select-Object -First 1
                    if ($null -ne $target) {
                        return $target
                    }

                    WriteLog "DevTools endpoint on port $Port returned targets but no page matched the criteria (attempt $attempt of $MaxAttempts)."
                }
                else {
                    WriteLog "DevTools endpoint on port $Port returned no targets (attempt $attempt of $MaxAttempts)."
                }
            }
            catch {
                WriteLog "DevTools endpoint on port $Port not ready (attempt $attempt of $MaxAttempts). Error: $($_.Exception.Message)"
            }

            Start-Sleep -Milliseconds $DelayMilliseconds
        }

        throw "Edge DevTools endpoint on port $Port did not expose a matching page target after $MaxAttempts attempts."
    }

    try {
        $ffuDevelopmentRoot = Split-Path -Path $PSScriptRoot -Parent
        WriteLog "Derived FFUDevelopmentPath from module path: $ffuDevelopmentRoot"

        if ([string]::IsNullOrWhiteSpace($ffuDevelopmentRoot)) {
            throw "FFUDevelopmentPath could not be resolved. Unable to create Edge profile."
        }

        if (-not (Test-Path -Path $ffuDevelopmentRoot -PathType Container)) {
            throw "Resolved FFUDevelopmentPath '$ffuDevelopmentRoot' does not exist."
        }

        $tempProfile = Join-Path -Path $ffuDevelopmentRoot -ChildPath ("edge-psref-" + [guid]::NewGuid())
        WriteLog "Creating temporary Edge profile at $tempProfile."
        New-Item -ItemType Directory -Path $tempProfile -Force | Out-Null

        $edgeExe = "$Env:ProgramFiles (x86)\Microsoft\Edge\Application\msedge.exe"
        $uri = 'https://psref.lenovo.com'
        $port = Get-FreeLocalTcpPort
        WriteLog "Using Edge DevTools port $port for Lenovo PSREF token retrieval."

        $flags = "--headless=new --disable-gpu --remote-debugging-port=$port $uri --user-data-dir=`"$tempProfile`""
        $edgeProcess = Start-Process -FilePath $edgeExe -ArgumentList $flags -PassThru
        WriteLog "Edge process started with PID: $($edgeProcess.Id)."

        $pageTarget = Get-EdgeDevToolsPageTarget -Port $port -MaxAttempts 40 -DelayMilliseconds 500 -UrlContains 'psref.lenovo.com'
        if (-not [string]::IsNullOrWhiteSpace($pageTarget.url)) {
            WriteLog "Selected DevTools target URL: $($pageTarget.url)"
        }

        $wsUrl = $pageTarget.webSocketDebuggerUrl
        if ([string]::IsNullOrWhiteSpace($wsUrl)) {
            throw "Edge DevTools page target on port $port did not provide a WebSocket URL."
        }

        $socket = [System.Net.WebSockets.ClientWebSocket]::new()
        $socket.ConnectAsync($wsUrl, [Threading.CancellationToken]::None).Wait()

        function Send-DevToolsCommand {
            param([int]$id, [string]$method, [hashtable]$params = @{})
            $cmd = @{ id = $id; method = $method; params = $params } | ConvertTo-Json -Compress
            $data = [Text.Encoding]::UTF8.GetBytes($cmd)
            $socket.SendAsync([ArraySegment[byte]]$data, 'Text', $true, [Threading.CancellationToken]::None).Wait()
        }

        $buffer = New-Object byte[] 8192

        function Invoke-DevToolsValue {
            param(
                [Parameter(Mandatory = $true)][int]$CommandId,
                [Parameter(Mandatory = $true)][string]$Expression,
                [int]$MaxPolls = 25
            )

            Send-DevToolsCommand -id $CommandId -method 'Runtime.evaluate' -params @{
                expression    = $Expression
                returnByValue = $true
                awaitPromise  = $true
            }

            for ($poll = 1; $poll -le $MaxPolls; $poll++) {
                $localStream = $null
                try {
                    $localStream = New-Object System.IO.MemoryStream
                    do {
                        $segment = [ArraySegment[byte]]::new($buffer)
                        $result = $socket.ReceiveAsync($segment, [Threading.CancellationToken]::None).Result
                        $localStream.Write($buffer, 0, $result.Count)
                    } until ($result.EndOfMessage)

                    $jsonBytes = $localStream.ToArray()
                    $jsonText = [Text.Encoding]::UTF8.GetString($jsonBytes)
                    $previewPayload = $jsonText
                    if (-not [string]::IsNullOrEmpty($previewPayload) -and $previewPayload.Length -gt 500) {
                        $previewPayload = $previewPayload.Substring(0, 500) + '...'
                    }
                    WriteLog "DevTools eval payload (cmd $CommandId, poll $poll): $previewPayload"

                    $message = $null
                    try {
                        $message = $jsonText | ConvertFrom-Json
                    }
                    catch {
                        WriteLog "Failed to parse DevTools eval payload for command id $CommandId (poll $poll): $($_.Exception.Message)"
                        continue
                    }

                    if ($message.PSObject.Properties['id'] -and $message.id -eq $CommandId) {
                        if ($message.PSObject.Properties['error']) {
                            $errorMessage = $message.error.message
                            throw "Edge DevTools reported an error for expression '$Expression': $errorMessage"
                        }

                        if ($message.PSObject.Properties['result'] -and $message.result.PSObject.Properties['result']) {
                            $innerResult = $message.result.result
                            return [PSCustomObject]@{
                                Value   = $innerResult.value
                                Type    = $innerResult.type
                                Subtype = $innerResult.subtype
                            }
                        }

                        $serializedMessage = $message | ConvertTo-Json -Compress -Depth 5
                        WriteLog "DevTools response for command id $CommandId lacked result data. Message: $serializedMessage"
                        return $null
                    }

                    if ($message.PSObject.Properties['method']) {
                        WriteLog "Received DevTools event '$($message.method)' while waiting for command id $CommandId."
                    }
                    else {
                        WriteLog "Received DevTools message without id or method while waiting for command id $CommandId."
                    }
                }
                finally {
                    if ($null -ne $localStream) {
                        $localStream.Dispose()
                    }
                }
            }

            throw "No DevTools response received for command id $CommandId after $MaxPolls polls."
        }

        WriteLog "Waiting for PSREF page to initialize local storage context."
        Start-Sleep -Seconds 2

        $commandCounter = 1000
        $rawToken = $null
        $maxTokenAttempts = 12
        for ($attempt = 1; $attempt -le $maxTokenAttempts -and [string]::IsNullOrWhiteSpace($rawToken); $attempt++) {
            $commandCounter++
            $tokenResponse = Invoke-DevToolsValue -CommandId $commandCounter -Expression "window.localStorage?.getItem('asut')" -MaxPolls 25
            if ($null -ne $tokenResponse -and -not [string]::IsNullOrWhiteSpace($tokenResponse.Value)) {
                $rawToken = $tokenResponse.Value
                WriteLog "DevTools response for command id $commandCounter returned token length $($rawToken.Length)."
                break
            }

            WriteLog "Lenovo PSREF token not yet available (attempt $attempt of $maxTokenAttempts)."

            $commandCounter++
            $keysResponse = Invoke-DevToolsValue -CommandId $commandCounter -Expression "JSON.stringify(Object.keys(window.localStorage || {}))" -MaxPolls 10
            if ($null -ne $keysResponse -and -not [string]::IsNullOrWhiteSpace($keysResponse.Value)) {
                WriteLog "Current localStorage keys: $($keysResponse.Value)"
            }

            $commandCounter++
            $cookieResponse = Invoke-DevToolsValue -CommandId $commandCounter -Expression "document.cookie" -MaxPolls 10
            if ($null -ne $cookieResponse -and -not [string]::IsNullOrWhiteSpace($cookieResponse.Value)) {
                WriteLog "document.cookie contents: $($cookieResponse.Value)"
                $cookieEntry = ($cookieResponse.Value -split ';') | ForEach-Object { $_.Trim() } | Where-Object { $_ -like 'asut=*' } | Select-Object -First 1
                if ($cookieEntry) {
                    $rawToken = $cookieEntry.Substring($cookieEntry.IndexOf('=') + 1)
                    WriteLog "Extracted Lenovo PSREF token from cookies with length $($rawToken.Length)."
                    break
                }
            }

            Start-Sleep -Milliseconds 750
        }

        if ([string]::IsNullOrWhiteSpace($rawToken)) {
            throw "Received empty Lenovo PSREF token from Edge DevTools after $maxTokenAttempts attempts."
        }

        $token = "X-PSREF-USER-TOKEN=$rawToken"
        WriteLog "Retrieved Lenovo PSREF token: $token"
    }
    catch {
        WriteLog "Failed to retrieve Lenovo PSREF token. Error: $($_.Exception.Message)"
        throw
    }
    finally {
        if ($null -ne $socket) {
            try {
                $socket.Dispose()
                WriteLog "Edge DevTools WebSocket disposed."
            }
            catch {
                WriteLog "Error disposing Edge DevTools WebSocket: $($_.Exception.Message)"
            }
        }

        $listeningPid = $null
        if ($null -ne $port) {
            try {
                $netstatOutput = netstat -ano -p TCP | Where-Object { $_ -match "127\.0\.0\.1:$port.*LISTENING" }
                if ($netstatOutput) {
                    $listeningPid = ($netstatOutput -split '\s+')[-1]
                    WriteLog "Found Edge process PID $listeningPid listening on port $port."
                }
                else {
                    WriteLog "No process reported as listening on port $port."
                }
            }
            catch {
                WriteLog "Could not run netstat to find listening PID for port $port. Error: $($_.Exception.Message)"
            }
        }

        $pidToKill = $null
        if ($null -ne $listeningPid) {
            $pidToKill = $listeningPid
        }
        elseif ($null -ne $edgeProcess -and -not $edgeProcess.HasExited) {
            $pidToKill = $edgeProcess.Id
            WriteLog "Falling back to initial Edge process PID $pidToKill for termination."
        }

        if ($null -ne $pidToKill) {
            try {
                taskkill /PID $pidToKill /T /F | Out-Null
                WriteLog "Issued termination command for Edge process tree with PID: $pidToKill."
            }
            catch {
                WriteLog "Failed to terminate Edge process tree with PID: $pidToKill. Error: $($_.Exception.Message)"
            }
        }
        else {
            WriteLog "No active Edge process found to terminate."
        }

        if ($null -ne $edgeProcess) {
            try {
                $edgeProcess.WaitForExit(3000) | Out-Null
            }
            catch {
                WriteLog "Error while waiting for Edge process PID $($edgeProcess.Id) to exit: $($_.Exception.Message)"
            }
        }

        Start-Sleep -Milliseconds 250

        if (-not [string]::IsNullOrWhiteSpace($tempProfile) -and (Test-Path -Path $tempProfile -PathType Container)) {
            $maxRemoveAttempts = 5
            $originalProgressPreference = $ProgressPreference
            try {
                $ProgressPreference = 'SilentlyContinue'
                for ($removeAttempt = 1; $removeAttempt -le $maxRemoveAttempts; $removeAttempt++) {
                    try {
                        Remove-Item -Path $tempProfile -Recurse -Force -ErrorAction Stop
                        WriteLog "Removed temporary Edge profile at $tempProfile."
                        break
                    }
                    catch {
                        if ($removeAttempt -eq $maxRemoveAttempts) {
                            WriteLog "Failed to remove temporary Edge profile at $tempProfile after $maxRemoveAttempts attempts. Error: $($_.Exception.Message)"
                        }
                        else {
                            WriteLog "Temporary Edge profile still locked (attempt $removeAttempt of $maxRemoveAttempts). Retrying..."
                            Start-Sleep -Milliseconds 500
                        }
                    }
                }
            }
            finally {
                $ProgressPreference = $originalProgressPreference
            }
        }
    }

    return $token
}


# --------------------------------------------------------------------------
# SECTION: Module Export
# --------------------------------------------------------------------------

Export-ModuleMember -Function `
	New-DriverOperationContext, `
	New-DriverExtractionWorkspace, `
	Save-DriverPackageToWorkspace, `
	Get-DriverPathFreeSpace, `
	Test-DriverProvisioningPackage, `
	Resolve-DriverProvisioningPath, `
	Get-DriverInfOwnedFiles, `
	Add-DriverProvisioningPackages, `
	Invoke-DriverExtractionProcess, `
	Reset-DriverExtractionOutput, `
	Test-DriverExtractionOutput, `
	Publish-DriverExtractionContent, `
	Save-DriverExtractionLog, `
	Remove-DriverExtractionWorkspace, `
	Remove-DriverDownloadOperation, `
	Confirm-DriverOperationActive, `
	Get-DriverPublicationMutex, `
	Set-DriverModelDownloadState, `
	Test-DriverModelIncomplete, `
	Invoke-DriverMsiExtraction, `
	Expand-DriverCatalog, `
	Save-DriverCatalogFile, `
    Compress-DriverFolderToWim, `
    Update-DriverMappingJson, `
    Test-ExistingDriver, `
    Get-LenovoPSREFRequestHeaders, `
    Get-LenovoPSREFToken