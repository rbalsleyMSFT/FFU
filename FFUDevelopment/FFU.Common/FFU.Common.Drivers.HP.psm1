<#
.SYNOPSIS
	Common HP driver catalog and latest-package selection helpers.
#>

function Get-HPDriverCatalogs {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)][System.Xml.XmlElement]$Platform,
		[Parameter(Mandatory)][ValidateSet('x64', 'x86', 'ARM64')][string]$WindowsArch,
		[Parameter(Mandatory)][ValidateSet(10, 11)][int]$WindowsRelease
	)

	$systemId = ([string]$Platform.SystemID).Trim().ToLowerInvariant()
	if ($systemId -notmatch '^[0-9a-f]{4}$') { throw "Invalid HP SystemID '$systemId'." }
	$architecture = switch ($WindowsArch) { 'x64' { '64' } 'x86' { '32' } 'ARM64' { 'arm64' } }
	$release = $WindowsRelease
	$osNodes = @($Platform.OS | Where-Object {
		([string]$_.OSArchitecture -eq $architecture) -and
		(([string]$_.IsWindows11 -eq 'true') -eq ($release -eq 11))
	})
	if ($osNodes.Count -eq 0) {
		$release = if ($WindowsRelease -eq 11) { 10 } else { 11 }
		$osNodes = @($Platform.OS | Where-Object {
			([string]$_.OSArchitecture -eq $architecture) -and
			(([string]$_.IsWindows11 -eq 'true') -eq ($release -eq 11))
		})
		if ($osNodes.Count -eq 0) {
			throw "HP SystemID '$systemId' has no published Windows 10 or Windows 11 catalogs for $WindowsArch."
		}
		WriteLog "HP SystemID '$systemId' has no Windows $WindowsRelease catalogs for $WindowsArch. Using all published Windows $release catalogs for that architecture."
	}

	$catalogs = @{}
	foreach ($osNode in $osNodes) {
		$versions = @(([string]$osNode.OSReleaseIdFilename).Trim() -split '\s+' | Where-Object { $_ })
		if ($versions.Count -eq 0) { throw "HP SystemID '$systemId' has an OS entry without a catalog release ID." }
		foreach ($version in $versions) {
			if ($version -notmatch '^[a-z0-9]+$') { throw "Invalid HP catalog release ID '$version' for SystemID '$systemId'." }
			$name = "$($systemId)_$($architecture)_$($release).0.$($version.ToLowerInvariant())"
			$catalogs[$name] = [pscustomobject]@{
				Name = $name
				SystemId = $systemId
				WindowsRelease = $release
				WindowsVersion = $version
				Url = "https://hpia.hpcloud.hp.com/ref/$systemId/$name.cab"
			}
		}
	}
	return $catalogs.Values | Sort-Object Name
}

function Get-HPDriverPackageMetadata {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)][System.Xml.XmlElement]$Update,
		[Parameter(Mandatory)][string]$HPDriversFolder,
		[pscustomobject]$DriverOperationContext
	)

	$id = ([string]$Update.Id).Trim().ToLowerInvariant()
	if ($id -notmatch '^sp\d+$') { throw "Invalid HP SoftPaq ID '$id'." }
	$cvaUrl = ([string]$Update.CvaUrl).Trim()
	if ([string]::IsNullOrWhiteSpace($cvaUrl)) { throw "HP package '$id' has no CVA URL to resolve its component coverage." }
	if ($cvaUrl -notmatch '^https?://') { $cvaUrl = "https://$cvaUrl" }
	$workspace = New-DriverExtractionWorkspace -Context $DriverOperationContext -DriversFolder $HPDriversFolder `
		-FileName "$id.cva" -FinalPath $HPDriversFolder -CachePath (Join-Path $HPDriversFolder "$id.cva") `
		-ComponentName "HP component metadata $id" -AllowShortName
	try {
		Save-DriverPackageToWorkspace -Workspace $workspace -Source $cvaUrl -ForceDownload
		$sections = @{}
		$section = ''
		foreach ($line in Get-Content -LiteralPath $workspace.InputPath -Encoding UTF8 -ErrorAction Stop) {
			$text = $line.Trim()
			if (-not $text -or $text.StartsWith(';')) { continue }
			if ($text -match '^\[([^\]]+)\]$') {
				$section = $Matches[1]
				if (-not $sections.ContainsKey($section)) { $sections[$section] = @{} }
			}
			elseif ($section -in @('General', 'Softpaq', 'Devices')) {
				if ($text -notmatch '^([^=]+)=(.*)$') { throw "Malformed [$section] entry in HP metadata '$id': $text" }
				$sections[$section][$Matches[1].Trim()] = $Matches[2].Trim()
			}
		}
		if (-not $sections.ContainsKey('CVA File Information') -or
			-not $sections.ContainsKey('Softpaq') -or $sections.Softpaq.SoftpaqNumber -ne $id) {
			throw "HP metadata '$cvaUrl' does not identify SoftPaq '$id'."
		}
		$deviceIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
		if ($sections.ContainsKey('Devices')) {
			foreach ($deviceId in $sections.Devices.Keys) {
				if ($deviceId -notmatch '^[^\\\s]+\\\S+$') { throw "Invalid device ID '$deviceId' in HP metadata '$id'." }
				$null = $deviceIds.Add($deviceId)
			}
		}
		return [pscustomobject]@{
			DeviceIds = $deviceIds
			Version = [string]$sections.General.Version
			Supersedes = @([regex]::Matches([string]$sections.Softpaq.SupersededSoftpaqNumber, '(?i)\bsp\d+\b') |
				ForEach-Object { $_.Value.ToLowerInvariant() })
		}
	}
	catch {
		WriteLog "Unable to read HP component metadata '$id' from '$cvaUrl': $($_.Exception.Message)"
		throw
	}
	finally {
		$null = Remove-DriverExtractionWorkspace -Workspace $workspace
	}
}

function Get-HPDriverSupersedence {
	param([hashtable]$Relationships, [string[]]$CandidateIds)

	$resolved = @{}
	$visiting = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
	function Get-HPPredecessors {
		param([string]$Id)
		if ($visiting.Contains($Id)) { throw "Circular HP supersedence relationship involving '$Id'." }
		if ($resolved.ContainsKey($Id)) { return ,$resolved[$Id] }
		$null = $visiting.Add($Id)
		$predecessors = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
		if ($Relationships.ContainsKey($Id)) {
			foreach ($previousId in $Relationships[$Id]) {
				$null = $predecessors.Add($previousId)
				$predecessors.UnionWith((Get-HPPredecessors -Id $previousId))
			}
		}
		$null = $visiting.Remove($Id)
		$resolved[$Id] = $predecessors
		return ,$predecessors
	}

	$candidateSet = [Collections.Generic.HashSet[string]]::new([string[]]$CandidateIds, [StringComparer]::OrdinalIgnoreCase)
	$supersededBy = @{}
	foreach ($id in $CandidateIds | Sort-Object) {
		foreach ($previousId in (Get-HPPredecessors -Id $id)) {
			if ($candidateSet.Contains($previousId)) { $supersededBy[$previousId] = $id }
		}
	}
	return $supersededBy
}

function Get-HPLatestDriverUpdates {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)][System.Xml.XmlElement]$Platform,
		[Parameter(Mandatory)][string]$HPDriversFolder,
		[Parameter(Mandatory)][ValidateSet('x64', 'x86', 'ARM64')][string]$WindowsArch,
		[Parameter(Mandatory)][ValidateSet(10, 11)][int]$WindowsRelease,
		[pscustomobject]$DriverOperationContext
	)

	$catalogs = @(Get-HPDriverCatalogs -Platform $Platform -WindowsArch $WindowsArch -WindowsRelease $WindowsRelease)
	$systemId = $catalogs[0].SystemId
	$catalogMutex = Get-DriverPublicationMutex -FinalPath (Join-Path $HPDriversFolder "$systemId.catalogs") -Context $DriverOperationContext
	try {
		$candidates = @{}
		$relationships = @{}
		foreach ($catalog in $catalogs) {
			$cabPath = Join-Path $HPDriversFolder "$($catalog.Name).cab"
			$xmlPath = Join-Path $HPDriversFolder "$($catalog.Name).xml"
			try {
				Expand-DriverCatalog -Source $catalog.Url -CabPath $cabPath -XmlPath $xmlPath `
					-DriverOperationContext $DriverOperationContext -ForceDownload
				[xml]$document = Get-Content -LiteralPath $xmlPath -Raw -Encoding UTF8 -ErrorAction Stop
				if ($null -eq $document.SelectSingleNode('/ImagePal/Solutions')) { throw 'The HP catalog has no ImagePal/Solutions element.' }
				$driverCount = 0
				foreach ($update in $document.SelectNodes('/ImagePal/Solutions/UpdateInfo | /ImagePal/Solutions-Superseded/UpdateInfo')) {
					$id = ([string]$update.Id).Trim().ToLowerInvariant()
					if ($id -notmatch '^sp\d+$') { throw "Invalid HP SoftPaq ID '$id'." }
					if (-not $relationships.ContainsKey($id)) {
						$relationships[$id] = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
					}
					foreach ($previousId in [regex]::Matches([string]$update.Supersedes, '(?i)\bsp\d+\b')) {
						$null = $relationships[$id].Add($previousId.Value.ToLowerInvariant())
					}
					if ($update.ParentNode.LocalName -ne 'Solutions' -or $update.Category -notmatch '^Driver') { continue }
					$driverCount++
					foreach ($field in @('Name', 'Version', 'Url')) {
						if ([string]::IsNullOrWhiteSpace([string]$update.$field)) { throw "HP package '$id' is missing '$field'." }
					}
					$releaseDate = [datetime]::MinValue
					if (-not [datetime]::TryParseExact([string]$update.DateReleased, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture,
						[Globalization.DateTimeStyles]::None, [ref]$releaseDate)) {
						throw "HP package '$id' has an invalid release date '$($update.DateReleased)'."
					}
					if ($candidates.ContainsKey($id)) {
						$existing = $candidates[$id].Update
						if ([string]$existing.Url -ne [string]$update.Url -or
							($existing.SHA256 -and $update.SHA256 -and [string]$existing.SHA256 -ne [string]$update.SHA256)) {
							throw "Conflicting download metadata for HP package '$id'."
						}
						if ($candidates[$id].ReleaseDate -ge $releaseDate) { continue }
					}
					$candidates[$id] = [pscustomobject]@{ Id = $id; Update = $update; ReleaseDate = $releaseDate }
				}
				WriteLog "HP catalog '$($catalog.Name)' contains $driverCount active driver packages."
			}
			catch { throw "Unable to read HP catalog '$($catalog.Url)': $($_.Exception.Message)" }
			finally {
				if (Test-Path -LiteralPath $xmlPath) { Remove-Item -LiteralPath $xmlPath -Force -ErrorAction Stop }
			}
		}
		if ($candidates.Count -eq 0) { throw "HP catalogs for SystemID '$systemId' contain no driver packages." }
		WriteLog "HP SystemID '$systemId': $($catalogs.Count) catalogs, $($candidates.Count) distinct driver candidates."

		# Combine historical replacement links before resolving packages with overlapping component coverage.
		$supersededBy = Get-HPDriverSupersedence -Relationships $relationships -CandidateIds @($candidates.Keys)
		$remaining = @($candidates.Values | Where-Object { -not $supersededBy.ContainsKey($_.Id) })
		$groups = @($remaining | Group-Object {
			(([string]$_.Update.Category).Trim() + '|' + (([string]$_.Update.Name).Trim() -replace '\s+', ' '))
		} | Where-Object Count -GT 1)
		$groups += @($remaining | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Update.ColId) } |
			Group-Object { ([string]$_.Update.Category).Trim() + '|' + [string]$_.Update.ColId } | Where-Object Count -GT 1)
		$metadata = @{}
		foreach ($group in $groups) {
			foreach ($candidate in $group.Group) {
				if ($metadata.ContainsKey($candidate.Id)) { continue }
				$details = Get-HPDriverPackageMetadata -Update $candidate.Update -HPDriversFolder $HPDriversFolder -DriverOperationContext $DriverOperationContext
				$metadata[$candidate.Id] = $details
				foreach ($previousId in $details.Supersedes) { $null = $relationships[$candidate.Id].Add($previousId) }
			}
		}
		$supersededBy = Get-HPDriverSupersedence -Relationships $relationships -CandidateIds @($candidates.Keys)
		$selected = @{}
		foreach ($id in $candidates.Keys) {
			if ($supersededBy.ContainsKey($id)) {
				$replacementId = $supersededBy[$id]
				while ($supersededBy.ContainsKey($replacementId)) { $replacementId = $supersededBy[$replacementId] }
				WriteLog "Skipping HP package '$id': superseded by '$replacementId'."
			}
			else { $selected[$id] = $candidates[$id] }
		}

		foreach ($group in $groups) {
			$members = @($group.Group | Where-Object { $selected.ContainsKey($_.Id) } | Sort-Object ReleaseDate -Descending)
			if ($members.Count -lt 2) { continue }
			foreach ($candidate in $members) {
				if ($metadata[$candidate.Id].DeviceIds.Count -eq 0) {
					throw "HP package '$($candidate.Id)' has no device coverage metadata to resolve overlapping component packages."
				}
			}
			foreach ($candidate in $members) {
				if (-not $selected.ContainsKey($candidate.Id)) { continue }
				$coveredDevices = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
				$newerIds = [Collections.Generic.List[string]]::new()
				foreach ($other in $members) {
					if ($other.Id -eq $candidate.Id -or -not $selected.ContainsKey($other.Id) -or $other.ReleaseDate -lt $candidate.ReleaseDate) { continue }
					if (-not $metadata[$candidate.Id].DeviceIds.Overlaps($metadata[$other.Id].DeviceIds)) { continue }
					if ($other.ReleaseDate -eq $candidate.ReleaseDate) {
						$candidateVersion = $null
						$otherVersion = $null
						if (-not [version]::TryParse($metadata[$candidate.Id].Version, [ref]$candidateVersion) -or
							-not [version]::TryParse($metadata[$other.Id].Version, [ref]$otherVersion) -or $candidateVersion -eq $otherVersion) {
							throw "Cannot determine the latest HP component package between '$($candidate.Id)' and '$($other.Id)': release dates are equal and package versions do not establish a replacement."
						}
						if ($otherVersion -lt $candidateVersion) { continue }
					}
					$coveredDevices.UnionWith($metadata[$other.Id].DeviceIds)
					$newerIds.Add($other.Id)
				}
				if ($metadata[$candidate.Id].DeviceIds.IsSubsetOf($coveredDevices)) {
					$selected.Remove($candidate.Id)
					WriteLog "Skipping HP package '$($candidate.Id)': newer component packages '$($newerIds -join ', ')' cover all its device IDs."
				}
				elseif ($newerIds.Count -gt 0) {
					WriteLog "Keeping HP package '$($candidate.Id)': it supplies device IDs not covered by the newer component packages."
				}
			}
		}
		if ($selected.Count -eq 0) { throw "HP driver selection for SystemID '$systemId' produced no packages." }
		WriteLog "Selected $($selected.Count) HP driver packages for SystemID '$systemId': $(($selected.Keys | Sort-Object) -join ', ')."
		return $selected.Values | Sort-Object { [string]$_.Update.Name }, Id | ForEach-Object { $_.Update }
	}
	catch {
		WriteLog "HP driver selection failed for SystemID '$systemId': $($_.Exception.Message)"
		throw
	}
	finally {
		$catalogMutex.ReleaseMutex()
		$catalogMutex.Dispose()
	}
}

function Expand-HPDriverPackage {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)][pscustomobject]$Workspace,
		[Parameter(Mandatory)][string[]]$ArgumentList
	)

	try { return Invoke-DriverExtractionProcess -Workspace $Workspace -ArgumentList $ArgumentList -HPSoftPaq }
	catch {
		if ($_.Exception.Data['ExitCode'] -ne -2144337645) { throw }
		$extractionError = $_
		WriteLog "HP SoftPaq '$($Workspace.OriginalFileName)' reported compression error 0x80300113. Checking for an embedded Windows cabinet."
	}

	$cabinets = @(Export-DriverEmbeddedCabinets -Path $Workspace.InputPath -DestinationPath (Split-Path $Workspace.InputPath -Parent))
	if ($cabinets.Count -eq 0) {
		WriteLog "HP SoftPaq '$($Workspace.OriginalFileName)' has no valid embedded Windows cabinet for extraction fallback."
		throw $extractionError
	}
	$cabinetPath = $cabinets[0]

	Reset-DriverExtractionOutput -Workspace $Workspace
	$result = Invoke-DriverExtractionProcess -Workspace $Workspace -FilePath 'expand.exe' `
		-ArgumentList "-R `"$cabinetPath`" -F:* `"$($Workspace.OutputPath)`""
	$null = Test-DriverExtractionOutput -Path $Workspace.OutputPath -RequireInf -ComponentName $Workspace.ComponentName
	WriteLog "HP SoftPaq '$($Workspace.OriginalFileName)' was extracted from its embedded Windows cabinet and verified to contain driver INFs."
	return $result
}

Export-ModuleMember -Function Get-HPDriverCatalogs, Get-HPDriverPackageMetadata, Get-HPLatestDriverUpdates, Expand-HPDriverPackage
