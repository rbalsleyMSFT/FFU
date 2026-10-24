<#
.SYNOPSIS
	Shared Lenovo catalog, INF coverage, and driver download helpers.
#>

$script:lenovoExcludedPackageId = 'dislink1012875'
$script:lenovoExcludedOneLinkPackageId = 'acconelink02gw'
# These are OS builds, not the products.cab download-routing versions.
# https://learn.microsoft.com/windows/release-health/windows11-release-information
$script:lenovoWindowsBuilds = @{
	'21H2' = 22000; '22H2' = 22621; '23H2' = 22631; '24H2' = 26100
	'25H2' = 26200; '26H1' = 28000; '26H2' = 26300
}

function Get-LenovoDriverTarget {
	param([int]$WindowsRelease, [string]$WindowsArch, [string]$WindowsVersion)

	if ($WindowsRelease -notin @(10, 11)) { throw "Unsupported Lenovo Windows release '$WindowsRelease'." }
	if ($WindowsArch -notin @('x64', 'x86', 'ARM64')) { throw "Unsupported Lenovo Windows architecture '$WindowsArch'." }
	$build = 0
	if ($WindowsRelease -eq 11) {
		if ($WindowsArch -eq 'x86') { throw 'Windows 11 Lenovo drivers require x64 or ARM64.' }
		$versionName = ([string]$WindowsVersion).Trim().ToUpperInvariant()
		if (-not $script:lenovoWindowsBuilds.ContainsKey($versionName)) {
			throw "Cannot resolve Lenovo driver target Windows 11 version '$WindowsVersion'. Select a supported Windows version."
		}
		$build = $script:lenovoWindowsBuilds[$versionName]
	}
	return [pscustomobject]@{ Release = $WindowsRelease; Architecture = $WindowsArch; Build = $build }
}

function Test-LenovoDriverCondition {
	param([System.Xml.XmlNode]$Node, [pscustomobject]$Target, [switch]$LegacyOs)

	# Unknown device-specific predicates remain unknown through And/Or/Not.
	if ($null -eq $Node) { return -1 }
	$children = @($Node.ChildNodes | Where-Object NodeType -eq Element)
	switch ($Node.LocalName) {
		{ $_ -in @('Dependencies', 'And', 'Or', 'Not') } {
			$values = @($children | ForEach-Object { Test-LenovoDriverCondition -Node $_ -Target $Target -LegacyOs:$LegacyOs })
			switch ($Node.LocalName) {
				'Or' {
					if ($values -contains 1) { return 1 }
					if ($values -contains -1) { return -1 }
					return 0
				}
				'Not' {
					if ($values.Count -ne 1) { throw 'Invalid Lenovo Not dependency.' }
					if ($values[0] -eq -1) { return -1 }
					return (1 - $values[0])
				}
				default {
					if ($values -contains 0) { return 0 }
					if ($values -contains -1 -or $values.Count -eq 0) { return -1 }
					return 1
				}
			}
		}
		'_OS' {
			$release = if ($LegacyOs) { 10 } else { $Target.Release }
			$names = @($Node.SelectNodes('OS') | ForEach-Object { $_.InnerText.Trim() })
			if ($names.Count -eq 0 -or $names -contains '') { throw 'Invalid Lenovo OS dependency.' }
			return [int](@($names | Where-Object { $_ -match "^WIN$release(?:$|[.*-])" }).Count -gt 0)
		}
		'_CPUAddressWidth' {
			$widths = @($Node.SelectNodes('AddressWidth') | ForEach-Object { $_.InnerText.Trim() })
			if ($widths.Count -eq 0 -or @($widths | Where-Object { $_ -notin @('32', '64') }).Count -gt 0) {
				throw 'Invalid Lenovo CPU address-width dependency.'
			}
			$width = if ($Target.Architecture -eq 'x86') { '32' } else { '64' }
			return [int]($widths -contains $width)
		}
		'_WindowsBuildVersion' {
			if ($LegacyOs) { return -1 }
			$versions = @($Node.SelectNodes('Version'))
			if ($versions.Count -eq 0) { throw 'Missing Lenovo Windows build dependency.' }
			foreach ($versionNode in $versions) {
				$match = [regex]::Match($versionNode.InnerText.Trim(), '^(?:(?<exact>\d+)|(?<minimum>\d*)\s*\^\s*(?<maximum>\d*))$')
				$minimum = 0
				$maximum = [int]::MaxValue
				$minimumText = if ($match.Groups['exact'].Success) { $match.Groups['exact'].Value } else { $match.Groups['minimum'].Value }
				$maximumText = if ($match.Groups['exact'].Success) { $match.Groups['exact'].Value } else { $match.Groups['maximum'].Value }
				if (-not $match.Success -or (-not $minimumText -and -not $maximumText) -or
					($minimumText -and -not [int]::TryParse($minimumText, [ref]$minimum)) -or
					($maximumText -and -not [int]::TryParse($maximumText, [ref]$maximum)) -or $minimum -gt $maximum) {
					throw "Unsupported Lenovo Windows build rule '$($versionNode.InnerText)'."
				}
				if ($Target.Build -ge $minimum -and $Target.Build -le $maximum) { return 1 }
			}
			return 0
		}
		default { return -1 }
	}
}

function Test-LenovoCatalogNotFound {
	param([Exception]$Exception, [string]$Source, [string]$ErrorId)

	$details = Get-DriverDownloadHttpStatus -Exception $Exception -Source $Source -ErrorId $ErrorId
	return $details.StatusCode -eq 404
}

function Confirm-LenovoDriverHash {
	param([string]$Path, [string]$Hash, [string]$Algorithm)

	if ([string]::IsNullOrWhiteSpace($Hash)) { return }
	if ([string]::IsNullOrWhiteSpace($Algorithm)) {
		$Algorithm = switch ($Hash.Length) { 32 { 'MD5' } 40 { 'SHA1' } 64 { 'SHA256' } default { '' } }
	}
	$Algorithm = $Algorithm.Replace('-', '').ToUpperInvariant()
	if ($Algorithm -notin @('MD5', 'SHA1', 'SHA256') -or $Hash -notmatch '^[a-fA-F0-9]+$') {
		throw "Unsupported Lenovo checksum '$Algorithm' for '$Path'."
	}
	$actualHash = (Get-FileHash -LiteralPath $Path -Algorithm $Algorithm -ErrorAction Stop).Hash
	if ($actualHash -ne $Hash) {
		$exception = [IO.InvalidDataException]::new("Lenovo $Algorithm checksum mismatch for '$Path'. Expected '$Hash'; actual '$actualHash'.")
		$exception.Data['LenovoChecksumMismatch'] = $true
		throw $exception
	}
}

function Confirm-LenovoDescriptorSignature {
	param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][uri]$Source)

	Add-Type -AssemblyName System.Security.Cryptography.Xml -ErrorAction Stop
	$document = [xml]::new()
	$document.PreserveWhitespace = $true
	$document.XmlResolver = $null
	$document.Load($Path)
	if ($document.DocumentElement.LocalName -ne 'Package') { throw 'Signed Lenovo metadata has no Package root.' }
	$id = $document.DocumentElement.GetAttribute('id')
	$stem = [IO.Path]::GetFileNameWithoutExtension($Source.AbsolutePath)
	if ($id -notmatch '^[a-zA-Z0-9_.-]+$' -or ($stem -ne $id -and -not $stem.StartsWith($id + '_', [StringComparison]::OrdinalIgnoreCase))) {
		throw "Signed Lenovo package '$id' does not match descriptor URL '$Source'."
	}
	$namespaces = [Xml.XmlNamespaceManager]::new($document.NameTable)
	$namespaces.AddNamespace('ds', [Security.Cryptography.Xml.SignedXml]::XmlDsigNamespaceUrl)
	$signatures = $document.SelectNodes('/Package/ds:Signature', $namespaces)
	if ($signatures.Count -ne 1 -or $document.GetElementsByTagName('Signature', [Security.Cryptography.Xml.SignedXml]::XmlDsigNamespaceUrl).Count -ne 1) {
		throw 'Lenovo metadata must have one signature on the Package root.'
	}
	$signed = [Security.Cryptography.Xml.SignedXml]::new($document)
	$signed.LoadXml($signatures[0])
	$signatureMethods = @(
		'http://www.w3.org/2001/04/xmldsig-more#rsa-sha256'
		'http://www.w3.org/2001/04/xmldsig-more#rsa-sha384'
		'http://www.w3.org/2001/04/xmldsig-more#rsa-sha512'
	)
	$digestMethods = @(
		'http://www.w3.org/2001/04/xmlenc#sha256'
		'http://www.w3.org/2001/04/xmldsig-more#sha384'
		'http://www.w3.org/2001/04/xmlenc#sha512'
	)
	if ($signed.SignedInfo.SignatureMethod -notin $signatureMethods -or $signed.SignedInfo.References.Count -ne 1) {
		throw 'Lenovo metadata requires an RSA SHA-256 or stronger full-document signature.'
	}
	$reference = $signed.SignedInfo.References[0]
	if (-not [string]::IsNullOrEmpty($reference.Uri) -or $reference.DigestMethod -notin $digestMethods) {
		throw 'Lenovo metadata signature must cover the entire document with a SHA-256 or stronger digest.'
	}
	if ($reference.TransformChain.Count -lt 1 -or
		$reference.TransformChain[0].Algorithm -ne [Security.Cryptography.Xml.SignedXml]::XmlDsigEnvelopedSignatureTransformUrl) {
		throw 'Lenovo metadata signature is not an enveloped full-document signature.'
	}
	$canonicalTransforms = @(
		[Security.Cryptography.Xml.SignedXml]::XmlDsigC14NTransformUrl
		[Security.Cryptography.Xml.SignedXml]::XmlDsigC14NWithCommentsTransformUrl
		[Security.Cryptography.Xml.SignedXml]::XmlDsigExcC14NTransformUrl
		[Security.Cryptography.Xml.SignedXml]::XmlDsigExcC14NWithCommentsTransformUrl
	)
	if ($signed.SignedInfo.CanonicalizationMethod -notin $canonicalTransforms) {
		throw 'Lenovo metadata signature uses an unsupported canonicalization method.'
	}
	for ($index = 1; $index -lt $reference.TransformChain.Count; $index++) {
		if ($reference.TransformChain[$index].Algorithm -notin $canonicalTransforms) {
			throw 'Lenovo metadata signature contains a transform that can exclude package content.'
		}
	}
	$certificates = $signatures[0].SelectNodes('ds:KeyInfo/ds:X509Data/ds:X509Certificate', $namespaces)
	if ($certificates.Count -ne 1) { throw 'Lenovo metadata has no unambiguous signing certificate.' }
	$certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new([Convert]::FromBase64String($certificates[0].InnerText))
	try {
		if ($certificate.Subject -notmatch '(?:^|,\s*)O=Lenovo(?:,|$)') { throw 'The metadata signing certificate does not identify Lenovo.' }
		$usages = @($certificate.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.37' } |
			ForEach-Object { $_.EnhancedKeyUsages } | ForEach-Object Value)
		if ('1.3.6.1.5.5.7.3.3' -notin $usages) { throw 'The Lenovo metadata certificate is not valid for code signing.' }
		$keyUsages = @($certificate.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.15' })
		$signingUsages = [Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature -bor
			[Security.Cryptography.X509Certificates.X509KeyUsageFlags]::NonRepudiation
		if ($keyUsages.Count -gt 0 -and ($keyUsages[0].KeyUsages -band $signingUsages) -eq 0) {
			throw 'The Lenovo metadata certificate is not valid for digital signatures.'
		}
		if (-not $signed.CheckSignature($certificate, $true)) { throw 'The Lenovo metadata digital signature is invalid.' }
		$expired = $false
		if (-not $signed.CheckSignature($certificate, $false)) {
			$chain = [Security.Cryptography.X509Certificates.X509Chain]::new()
			try {
				$now = [datetime]::UtcNow
				$chain.ChainPolicy.VerificationFlags = [Security.Cryptography.X509Certificates.X509VerificationFlags]::IgnoreNotTimeValid
				$null = $chain.ChainPolicy.ApplicationPolicy.Add([Security.Cryptography.Oid]::new('1.3.6.1.5.5.7.3.3'))
				$trusted = $chain.Build($certificate)
				$invalidIssuers = @($chain.ChainElements | Select-Object -Skip 1 | Where-Object {
					$_.Certificate.NotBefore.ToUniversalTime() -gt $now -or $_.Certificate.NotAfter.ToUniversalTime() -lt $now
				})
				$expired = $certificate.NotBefore.ToUniversalTime() -le $now -and $certificate.NotAfter.ToUniversalTime() -lt $now
				if (-not $expired -or -not $trusted -or $chain.ChainElements.Count -lt 2 -or $invalidIssuers.Count -gt 0) {
					$details = ($chain.ChainStatus | ForEach-Object { $_.Status.ToString() }) -join ', '
					throw "The Lenovo metadata signing certificate chain is not trusted or currently valid. Chain status: $details"
				}
			}
			finally { $chain.Dispose() }
		}
		return [pscustomobject]@{
			Subject = $certificate.Subject; Thumbprint = $certificate.Thumbprint
			CertificateExpired = $expired; CertificateExpires = $certificate.NotAfter.ToUniversalTime()
		}
	}
	finally { $certificate.Dispose() }
}

function Save-LenovoDriverDescriptor {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)][string]$Source,
		[Parameter(Mandatory)][string]$Path,
		[string]$Hash,
		[string]$Algorithm,
		[pscustomobject]$DriverOperationContext
	)

	$mismatch = $null
	for ($attempt = 1; $attempt -le 2; $attempt++) {
		Save-DriverCatalogFile -Source $Source -Path $Path -DriverOperationContext $DriverOperationContext
		try {
			Confirm-LenovoDriverHash -Path $Path -Hash $Hash -Algorithm $Algorithm
			return
		}
		catch {
			if (-not $_.Exception.Data['LenovoChecksumMismatch']) { throw }
			$mismatch = $_.Exception
			if ($attempt -eq 1) {
				WriteLog "Lenovo descriptor checksum mismatch for '$Source'; downloading it once more. $($mismatch.Message)"
			}
		}
	}
	try { $signer = Confirm-LenovoDescriptorSignature -Path $Path -Source $Source }
	catch {
		throw [IO.InvalidDataException]::new("$($mismatch.Message) Signed metadata recovery failed for '$Source': $($_.Exception.Message)", $_.Exception)
	}
	$message = "Lenovo catalog checksum mismatch persists for '$Source'. Using XML verified by Lenovo's digital signature and trusted certificate chain. Installer checksum validation remains required."
	WriteLog "Warning: $message $($mismatch.Message) Signer: '$($signer.Subject)'; certificate: $($signer.Thumbprint)."
	if ($signer.CertificateExpired) {
		WriteLog "Warning: Lenovo XML signer certificate expired at $($signer.CertificateExpires.ToString('u')); accepted only its expiry. The issuing chain and all other certificate checks passed."
	}
}

function Confirm-LenovoInnoInstaller {
	param([Parameter(Mandatory)][string]$Path)

	$signature = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
	if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or
		$signature.SignerCertificate.Subject -notmatch '(?:^|,\s*)O=Lenovo(?:,|$)') {
		throw "Cannot use Lenovo Inno Setup extraction options: installer '$Path' does not have a valid Lenovo signature."
	}
	$marker = 'Inno Setup Setup Data ('
	$found = $false
	$stream = [IO.File]::OpenRead($Path)
	try {
		$buffer = [byte[]]::new(64KB)
		while ($stream.Position -lt $stream.Length) {
			$start = $stream.Position
			$count = $stream.Read($buffer, 0, $buffer.Length)
			if ($count -lt $marker.Length) { break }
			if ([Text.Encoding]::ASCII.GetString($buffer, 0, $count).Contains($marker, [StringComparison]::Ordinal)) {
				$found = $true
				break
			}
			$stream.Position = $start + $count - $marker.Length + 1
		}
	}
	finally { $stream.Dispose() }
	if (-not $found) { throw "Cannot use Lenovo Inno Setup extraction options: installer '$Path' is not an Inno Setup package." }
}

function Get-LenovoDriverPackages {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)][ValidatePattern('^[A-Z0-9]{4}$')][string]$MachineType,
		[Parameter(Mandatory)][string]$MetadataPath,
		[Parameter(Mandatory)][ValidateSet(10, 11)][int]$WindowsRelease,
		[Parameter(Mandatory)][ValidateSet('x64', 'x86', 'ARM64')][string]$WindowsArch,
		[string]$WindowsVersion,
		[pscustomobject]$DriverOperationContext
	)

	$target = Get-LenovoDriverTarget -WindowsRelease $WindowsRelease -WindowsArch $WindowsArch -WindowsVersion $WindowsVersion
	$MachineType = $MachineType.ToUpperInvariant()
	$null = New-Item -Path $MetadataPath -ItemType Directory -Force -ErrorAction Stop
	$releases = if ($WindowsRelease -eq 11) { @(11, 10) } else { @(10) }
	$descriptors = @{}
	$available = 0
	foreach ($release in $releases) {
		$url = "https://download.lenovo.com/catalog/$($MachineType)_Win$release.xml"
		$path = Join-Path $MetadataPath "$($MachineType)_Win$release.xml"
		try {
			Save-DriverCatalogFile -Source $url -Path $path -DriverOperationContext $DriverOperationContext
		}
		catch {
			if ($null -ne $DriverOperationContext) { Confirm-DriverOperationActive -Context $DriverOperationContext }
			if (Test-LenovoCatalogNotFound -Exception $_.Exception -Source $url -ErrorId $_.FullyQualifiedErrorId) {
				WriteLog "Lenovo catalog is unavailable (HTTP 404): $url"
				continue
			}
			throw "Unable to download Lenovo catalog '$url': $($_.Exception.Message)"
		}
		try {
			[xml]$document = Get-Content -LiteralPath $path -Raw -Encoding UTF8 -ErrorAction Stop
			if ($document.DocumentElement.LocalName -ne 'packages') { throw 'Missing packages catalog root.' }
			$entries = @($document.SelectNodes('/packages/package'))
			$count = 0
			if (-not [int]::TryParse($document.DocumentElement.GetAttribute('count'), [ref]$count) -or $count -ne $entries.Count) {
				throw 'The Lenovo catalog package count does not match its contents.'
			}
			$available++
			foreach ($entry in $entries) {
				$packageUrl = $null
				if (-not [uri]::TryCreate([string]$entry.location, [UriKind]::Absolute, [ref]$packageUrl) -or
					$packageUrl.Scheme -notin @('http', 'https')) { throw "Invalid package descriptor URL '$($entry.location)'." }
				$leaf = [IO.Path]::GetFileName($packageUrl.AbsolutePath)
				if ($leaf -match "^$($script:lenovoExcludedPackageId)(?:_[^.]*)?\.xml$") { continue }
				if ($leaf -match "^$($script:lenovoExcludedOneLinkPackageId)(?:_\d+_)?\.xml$") {
					WriteLog "Skipping Lenovo package 'ThinkPad OneLink Docks Driver' (ID: $($script:lenovoExcludedOneLinkPackageId)): legacy InstallShield archive is excluded from automatic driver downloads."
					continue
				}
				if ([string]$entry.category -match '^(BIOS|Firmware)') { continue }
				$checksum = $entry.SelectSingleNode('checksum')
				$hash = if ($null -ne $checksum) { $checksum.InnerText.Trim() } else { '' }
				$algorithm = if ($null -ne $checksum) { $checksum.GetAttribute('type') } else { '' }
				$key = $packageUrl.AbsoluteUri
				if ($descriptors.ContainsKey($key)) {
					$previous = $descriptors[$key]
					if ($previous.Hash -ne $hash -or $previous.Algorithm -ne $algorithm) {
						throw "Conflicting Lenovo catalog checksums for '$key'."
					}
					$null = $previous.Sources.Add($release)
				}
				else {
					$descriptors[$key] = [pscustomobject]@{
						Url = $key; Category = [string]$entry.category; Hash = $hash; Algorithm = $algorithm
						Sources = [Collections.Generic.HashSet[int]]::new([int[]]@($release))
					}
				}
			}
			WriteLog "Lenovo catalog '$url': $($entries.Count) entries."
		}
		catch { throw "Unable to read Lenovo catalog '$url': $($_.Exception.Message)" }
	}
	if ($available -eq 0) { throw "No Lenovo driver catalogs are available for machine type '$MachineType'." }

	$payloads = @{}
	$identities = @{}
	$descriptorIndex = 0
	foreach ($descriptor in $descriptors.Values | Sort-Object Url) {
		$descriptorIndex++
		$path = Join-Path $MetadataPath ("p$descriptorIndex.xml")
		try {
			Save-LenovoDriverDescriptor -Source $descriptor.Url -Path $path -Hash $descriptor.Hash `
				-Algorithm $descriptor.Algorithm -DriverOperationContext $DriverOperationContext
			[xml]$document = Get-Content -LiteralPath $path -Raw -Encoding UTF8 -ErrorAction Stop
			$root = $document.DocumentElement
			if ($root.LocalName -ne 'Package') { throw 'Missing Package descriptor root.' }
			$typeNode = $root.SelectSingleNode('PackageType')
			$requiresInfClassification = $null -eq $typeNode
			if (-not $requiresInfClassification) {
				if ($typeNode.GetAttribute('type') -notmatch '^\d+$') { throw 'Invalid PackageType.' }
				if ([int]$typeNode.GetAttribute('type') -ne 2) { continue }
			}
			$id = $root.GetAttribute('id').Trim().ToLowerInvariant()
			if ($id -eq $script:lenovoExcludedPackageId) { continue }
			$nameNode = $root.SelectSingleNode('Files/Installer/File/Name')
			$fileName = if ($null -ne $nameNode) { $nameNode.InnerText.Trim() } else { '' }
			if ($fileName -eq "$($script:lenovoExcludedPackageId).exe") { continue }
			if ($id -eq $script:lenovoExcludedOneLinkPackageId -or $fileName -eq "$($script:lenovoExcludedOneLinkPackageId).exe") {
				WriteLog "Skipping Lenovo package 'ThinkPad OneLink Docks Driver' (ID: $($script:lenovoExcludedOneLinkPackageId)): legacy InstallShield archive is excluded from automatic driver downloads."
				continue
			}
			if ($requiresInfClassification -and $null -eq $root.SelectSingleNode(
				'Dependencies//_PnPID | DetectInstall//_Driver/HardwareID | DetectVersion[@type="Inf"]/_PnPID')) {
				WriteLog "Skipping legacy Lenovo package '$id' without PackageType: no hardware-driver targeting metadata."
				continue
			}
			$titleNode = $root.SelectSingleNode('Title/Desc[@id="EN"] | Title/Desc[1] | title')
			$extractNode = $root.SelectSingleNode('ExtractCommand')
			$hashNode = $root.SelectSingleNode('Files/Installer/File/CRC')
			$version = $root.GetAttribute('version').Trim()
			$title = if ($null -ne $titleNode) { $titleNode.InnerText.Trim() } else { '' }
			$title = $title -replace '\s+-\s+(?:Windows\s+)?(?:11|10|8(?:\.1)?|7|Vista|XP)(?=$|\s|/|\[|\().*$', ''
			$extract = if ($null -ne $extractNode) { $extractNode.InnerText.Trim() } else { '' }
			$hash = if ($null -ne $hashNode) { $hashNode.InnerText.Trim().ToUpperInvariant() } else { '' }
			if ($hash -and ($hash.Length -notin @(32, 40, 64) -or $hash -notmatch '^[A-F0-9]+$')) {
				throw "Invalid Lenovo installer checksum for '$id'."
			}
			if ($id -notmatch '^[a-z0-9_.-]+$' -or -not $version -or -not $title -or -not $fileName) {
				throw 'Missing driver identity, version, title, or installer.'
			}
			if ($fileName -ne [IO.Path]::GetFileName($fileName) -or $fileName.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
				throw "Invalid Lenovo installer filename '$fileName'."
			}
			# Lenovo Support DS103508 publishes the correct SHA256 for this exact stale XML entry.
			# https://support.lenovo.com/us/en/downloads/ds103508-integrated-camera-driver-720p-1m-for-windows-10-version-1703-or-older
			if ($id -eq 'jec609ww_chi' -and $version -eq '10.0.10240.11138' -and $fileName -eq 'jec609ww.exe' -and
				$hash -eq '0C88DC8CD09DCD781309F0E1B773E5E5E87A638304B08C34A657E4D9B67680DE') {
				$hash = '2D5F130BFF4A6DCB4C6E127A2B5D877ACF25E9AF1455421CB4DFB8B4D67E3A7E'
				WriteLog "Correcting known Lenovo installer checksum for '$title' (version $version; ID: $id): using SHA256 '$hash' published by Lenovo Support DS103508."
			}
			$requiresInnoValidation = $false
			if (-not $extract) {
				$vendor = $root.SelectSingleNode('Vendor')
				$install = $root.SelectSingleNode('Install/Cmdline[@id="EN"] | Install/Cmdline[1]')
				$installerPattern = '%PACKAGEPATH%\\' + [regex]::Escape($fileName)
				$installPattern = '^(?:"' + $installerPattern + '"|' + $installerPattern +
					')\s+/VERYSILENT\s+/DIR=(?:"%PACKAGEPATH%\\TMP"|%PACKAGEPATH%\\TMP)\s*$'
				if ($null -eq $vendor -or $vendor.InnerText.Trim() -ne 'Lenovo' -or
					[IO.Path]::GetExtension($fileName) -ne '.exe' -or $null -eq $install -or
					$install.InnerText.Trim() -notmatch $installPattern) {
					throw "Package '$id' has no extraction command or recognized Lenovo Inno Setup install metadata."
				}
				$extract = "$fileName /VERYSILENT /DIR=%PACKAGEPATH% /EXTRACT=`"YES`""
				$requiresInnoValidation = $true
				WriteLog "Lenovo package '$id' has no extraction command; the standard Lenovo Inno Setup extraction options require installer signature and format verification."
			}
			if ($requiresInfClassification -and $extract -notmatch '(?:^|\s)/EXTRACT=(?:"YES"|YES)(?:\s|$)') {
				WriteLog "Skipping legacy Lenovo package '$id' without PackageType: no recognized driver extraction-only command."
				continue
			}
			$driverUrl = [uri]::new([uri]$descriptor.Url, $fileName).AbsoluteUri
			if ($identities.ContainsKey($id) -and $identities[$id] -ne "$driverUrl|$hash") {
				throw "Conflicting Lenovo installer metadata for package '$id'."
			}
			$identities[$id] = "$driverUrl|$hash"
			$dependencies = $root.SelectSingleNode('Dependencies')
			$declaresWin11 = @($root.SelectNodes('Dependencies//_OS/OS') | Where-Object { $_.InnerText -match '^WIN11(?:$|[.*-])' }).Count -gt 0
			$legacy = $WindowsRelease -eq 11 -and -not $declaresWin11
			if ($WindowsRelease -eq 11 -and (Test-LenovoDriverCondition -Node $dependencies -Target $target -LegacyOs:$legacy) -eq 0) {
				WriteLog "Skipping Lenovo package '$title' (version $version; ID: $id): descriptor target rules do not apply to Windows 11 build $($target.Build) / $WindowsArch."
				continue
			}
			if ($requiresInfClassification) {
				WriteLog "Legacy Lenovo package '$id' has no PackageType; driver INF files are required before publication."
			}
			$preferred = $WindowsRelease -eq 10 -or $descriptor.Sources.Contains(11)
			if ($WindowsRelease -eq 11 -and $preferred -and $legacy) {
				WriteLog "Lenovo package '$id' is offered in the Windows 11 catalog with legacy OS metadata; checking its INF applicability."
			}
			$alias = [pscustomobject]@{
				Id = $id; Version = $version; Url = $descriptor.Url; Sources = [int[]]@($descriptor.Sources)
				Dependencies = $dependencies; Preferred = $preferred
			}
			$key = if ($hash) { "hash:$hash" } else { "url:$driverUrl" }
			$normalizedExtract = $extract.Replace($fileName, '', [StringComparison]::OrdinalIgnoreCase).Trim()
			if ($payloads.ContainsKey($key)) {
				$package = $payloads[$key]
				if ($package.NormalizedExtract -ne $normalizedExtract) { throw "Conflicting extraction commands for shared Lenovo installer '$fileName'." }
				$package.Aliases.Add($alias)
				if ($preferred) { $package.Preferred = $true }
				if ($requiresInnoValidation) { $package.RequiresInnoValidation = $true }
				if (-not $requiresInfClassification) { $package.RequiresInfClassification = $false }
			}
			else {
				$payloads[$key] = [pscustomobject]@{
					Key = $key; Id = $id; Version = $version; Title = $title; Category = $descriptor.Category
					FileName = $fileName; Url = $driverUrl; Hash = $hash; ExtractCommand = $extract
					NormalizedExtract = $normalizedExtract; Preferred = $preferred
					RequiresInnoValidation = $requiresInnoValidation
					RequiresInfClassification = $requiresInfClassification
					Aliases = [Collections.Generic.List[object]]::new(); Workspace = $null; InfMetadata = $null; Reused = $false
				}
				$payloads[$key].Aliases.Add($alias)
			}
		}
		catch { throw "Unable to read Lenovo package '$($descriptor.Url)': $($_.Exception.Message)" }
	}
	if ($payloads.Count -eq 0) { throw "Lenovo catalogs for '$MachineType' contain no eligible driver candidates." }
	WriteLog "Lenovo '$MachineType': $available catalogs, $($payloads.Count) distinct driver installers."
	return $payloads.Values | Sort-Object @{ Expression = 'Preferred'; Descending = $true }, Id
}

function Get-LenovoInfSections {
	param([string]$Path)

	$sections = @{}
	$section = ''
	$continued = ''
	foreach ($rawLine in Get-Content -LiteralPath $Path -ErrorAction Stop) {
		$line = $rawLine
		if ($line.Contains(';')) {
			$quoted = $false
			for ($index = 0; $index -lt $line.Length; $index++) {
				if ($line[$index] -eq '"') { $quoted = -not $quoted }
				elseif ($line[$index] -eq ';' -and -not $quoted) { $line = $line.Substring(0, $index); break }
			}
		}
		$line = $line.Trim()
		if (-not $line) { continue }
		$line = $continued + $line
		if ($line.EndsWith('\')) { $continued = $line.Substring(0, $line.Length - 1); continue }
		$continued = ''
		$match = [regex]::Match($line, '^\[([^\]]+)\]$')
		if ($match.Success) {
			$section = $match.Groups[1].Value.Trim()
			if (-not $sections.ContainsKey($section)) { $sections[$section] = [Collections.Generic.List[string]]::new() }
		}
		elseif ($section) { $sections[$section].Add($line) }
	}
	if ($continued) { throw "Unterminated INF continuation in '$Path'." }
	return $sections
}

function Get-LenovoInfValues {
	param([string[]]$Lines)

	$values = @{}
	foreach ($line in $Lines) {
		$position = $line.IndexOf('=')
		if ($position -lt 1) { throw "Invalid INF assignment '$line'." }
		$values[$line.Substring(0, $position).Trim()] = $line.Substring($position + 1).Trim()
	}
	return $values
}

function Expand-LenovoInfValue {
	param([string]$Value, [hashtable]$Strings)

	for ($pass = 0; $pass -lt 10; $pass++) {
		if ($Value -notmatch '%[^%]+%') { return $Value.Trim().Trim('"') }
		$Value = [regex]::Replace($Value, '%([^%]+)%', {
			param($match)
			$key = $match.Groups[1].Value
			if (-not $Strings.ContainsKey($key)) { throw "Unresolved INF string '$key'." }
			return $Strings[$key].Trim('"')
		})
	}
	throw "Circular INF string reference '$Value'."
}

function Get-LenovoInfTargetRank {
	param([string]$Decoration, [string]$WindowsArch, [int]$WindowsBuild)

	$parts = $Decoration.ToUpperInvariant().Split('.')
	$architecture = switch ($WindowsArch) { x64 { 'NTAMD64' } ARM64 { 'NTARM64' } x86 { 'NTX86' } }
	if ($parts[0] -notin @('NT', $architecture)) { return }
	if ($parts.Count -gt 6) { throw "Unsupported INF target decoration '$Decoration'." }
	$numbers = @(0, 0, 0, 0, 0)
	for ($index = 1; $index -lt $parts.Count; $index++) {
		[uint32]$number = 0
		if ($parts[$index]) {
			$digits = $parts[$index]
			$style = [Globalization.NumberStyles]::None
			if ($digits.StartsWith('0X', [StringComparison]::Ordinal)) {
				$digits = $digits.Substring(2)
				$style = [Globalization.NumberStyles]::AllowHexSpecifier
			}
			if (-not [uint32]::TryParse($digits, $style, [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
				throw "Invalid INF target decoration '$Decoration'."
			}
		}
		$numbers[$index - 1] = $number
	}
	$major, $minor, $product, $suite, $build = $numbers
	if ($major -gt 10 -or ($major -eq 10 -and $minor -gt 0) -or $product -notin @(0, 1)) { return }
	if ($major -eq 10 -and $minor -eq 0 -and $build -gt $WindowsBuild) { return }
	# Datacenter, Blade, Storage, Compute, and Home Server suites cannot match a client target.
	if (($suite -band 0xE480) -ne 0) {
		WriteLog "Skipping INF target '$Decoration': its suite mask requires a Windows Server edition."
		return
	}
	if ($suite -ne 0) { throw "Cannot resolve suite-qualified INF target '$Decoration' without a Windows suite target." }
	return [pscustomobject]@{
		Decoration = $Decoration; Major = $major; Minor = $minor; Product = $product; Build = $build
		Architecture = [int]($parts[0] -eq $architecture)
	}
}

function Get-LenovoInfDriverVersion {
	param([string]$Value, [hashtable]$Strings = @{})

	$Value = Expand-LenovoInfValue -Value $Value -Strings $Strings
	$parts = @($Value.Split(',') | ForEach-Object { $_.Trim() })
	$date = [datetime]::MinValue
	$version = $null
	$formats = [string[]]@('MM/dd/yyyy', 'M/d/yyyy', 'MM/d/yyyy', 'M/dd/yyyy', 'MM-dd-yyyy', 'M-d-yyyy', 'MM-d-yyyy', 'M-dd-yyyy')
	if ($parts.Count -ne 2 -or -not [datetime]::TryParseExact($parts[0], $formats,
		[Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$date) -or
		-not [version]::TryParse($parts[1], [ref]$version)) { throw "Invalid INF DriverVer '$Value'." }
	return [pscustomobject]@{ Date = $date; Version = $version }
}

function Get-LenovoDriverInfMetadata {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)][string]$Path,
		[Parameter(Mandatory)][ValidateSet('x64', 'x86', 'ARM64')][string]$WindowsArch,
		[Parameter(Mandatory)][int]$WindowsBuild,
		[int]$ProvisioningPackageCount
	)

	$coverage = [Collections.Generic.List[object]]::new()
	$opaque = $ProvisioningPackageCount -gt 0
	$applicable = 0
	$files = @(Get-ChildItem -LiteralPath $Path -Filter '*.inf' -File -Recurse -ErrorAction Stop)
	foreach ($file in $files) {
		try {
			$sections = Get-LenovoInfSections -Path $file.FullName
			if (-not $sections.ContainsKey('Version')) {
				if ($sections.ContainsKey('Autorun') -and -not $sections.ContainsKey('Manufacturer')) {
					WriteLog "Ignoring installer autorun INF '$($file.FullName)'; it is not a driver INF."
					continue
				}
				throw 'Missing INF Version section.'
			}
			$versionFields = Get-LenovoInfValues -Lines $sections.Version
			$strings = @{}
			foreach ($name in @('Strings', 'Strings.0409')) {
				if ($sections.ContainsKey($name)) {
					$localized = Get-LenovoInfValues -Lines $sections[$name]
					foreach ($key in $localized.Keys) { $strings[$key] = $localized[$key] }
				}
			}
			if (-not $sections.ContainsKey('Manufacturer')) {
				$defaults = @($sections.Keys | Where-Object { $_ -match '^DefaultInstall(?:\.|$)' -and $_ -notmatch '\.(?:Services|HW|CoInstallers|Wdf)$' })
				foreach ($name in $defaults) {
					$decoration = $name -replace '^DefaultInstall\.?', ''
					if (-not $decoration -or $null -ne (Get-LenovoInfTargetRank -Decoration $decoration -WindowsArch $WindowsArch -WindowsBuild $WindowsBuild)) {
						$opaque = $true; $applicable++; break
					}
				}
				continue
			}
			$modelSections = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
			foreach ($line in $sections.Manufacturer) {
				$position = $line.IndexOf('=')
				if ($position -lt 1) { throw "Invalid Manufacturer entry '$line'." }
				$values = @(($line.Substring($position + 1) -split ',') | ForEach-Object { Expand-LenovoInfValue -Value $_ -Strings $strings })
				$base = $values[0]
				if ($values.Count -eq 1) { $null = $modelSections.Add($base); continue }
				$targets = @(foreach ($decoration in $values[1..($values.Count - 1)]) {
					Get-LenovoInfTargetRank -Decoration $decoration -WindowsArch $WindowsArch -WindowsBuild $WindowsBuild
				})
				$best = $targets | Sort-Object Major, Minor, Product, Build, Architecture -Descending | Select-Object -First 1
				if ($null -ne $best) { $null = $modelSections.Add("$base.$($best.Decoration)") }
			}
			if ($modelSections.Count -eq 0) { continue }
			$models = [Collections.Generic.List[string]]::new()
			foreach ($name in $modelSections) {
				if (-not $sections.ContainsKey($name)) { throw "Missing declared INF model section '$name'." }
				foreach ($line in $sections[$name]) { $models.Add($line) }
			}
			if ($models.Count -eq 0) { continue }
			$globalVersion = Get-LenovoInfDriverVersion -Value ([string]$versionFields.DriverVer) -Strings $strings
			$installVersions = @{}
			$class = Expand-LenovoInfValue -Value ([string]$versionFields.ClassGuid) -Strings $strings
			if (-not $class) { $class = Expand-LenovoInfValue -Value ([string]$versionFields.Class) -Strings $strings }
			$provider = Expand-LenovoInfValue -Value ([string]$versionFields.Provider) -Strings $strings
			$extension = Expand-LenovoInfValue -Value ([string]$versionFields.ExtensionId) -Strings $strings
			if (-not $class -or -not $provider) { throw 'Missing INF class or provider identity.' }
			if ($versionFields.Class -eq 'Extension' -and -not $extension) { throw 'Missing INF ExtensionId.' }
			$component = "$class|$provider|$extension".ToUpperInvariant()
			foreach ($line in $models) {
				$position = $line.IndexOf('=')
				if ($position -lt 1) { throw "Invalid INF model entry '$line'." }
				$values = @($line.Substring($position + 1) -split ',')
				if ($values.Count -lt 2) { throw "Missing hardware ID in INF model entry '$line'." }
				$install = Expand-LenovoInfValue -Value $values[0] -Strings $strings
				if (-not $installVersions.ContainsKey($install)) {
					$installVersions[$install] = $globalVersion
					$installTargets = @(foreach ($name in $sections.Keys) {
						if ($name -eq $install) { $decoration = 'NT' }
						elseif ($name.StartsWith("$install.", [StringComparison]::OrdinalIgnoreCase)) {
							$decoration = $name.Substring($install.Length + 1)
							if ($decoration -notmatch '^NT(?:amd64|arm64|x86)?(?:\.(?:\d+|0x[0-9a-f]+)?)*$') { continue }
						}
						else { continue }
						$rank = Get-LenovoInfTargetRank -Decoration $decoration -WindowsArch $WindowsArch -WindowsBuild $WindowsBuild
						if ($null -ne $rank) {
							$rank | Add-Member -NotePropertyName SectionName -NotePropertyValue $name
							$rank | Add-Member -NotePropertyName Qualified -NotePropertyValue ([int]($name -ne $install))
							$rank
						}
					})
					$installTarget = $installTargets | Sort-Object Major, Minor, Product, Build, Architecture, Qualified -Descending | Select-Object -First 1
					if ($null -ne $installTarget) {
						$versionLines = @($sections[$installTarget.SectionName] | Where-Object { $_ -match '^DriverVer\s*=' })
						$installFields = Get-LenovoInfValues -Lines $versionLines
						if ($installFields.ContainsKey('DriverVer')) {
							$installVersions[$install] = Get-LenovoInfDriverVersion -Value $installFields.DriverVer -Strings $strings
						}
					}
				}
				$driverVersion = $installVersions[$install]
				$hasDeviceId = $false
				for ($index = 1; $index -lt $values.Count; $index++) {
					$id = (Expand-LenovoInfValue -Value $values[$index] -Strings $strings).ToUpperInvariant()
					if (-not $id) { continue }
					if ($id -notmatch '^(?:[^\s,"]| )+$') { throw "Invalid INF device ID '$id'." }
					$hasDeviceId = $true
					$coverage.Add([pscustomobject]@{
						Key = "$component|$id"; DeviceId = $id; MatchRank = $index - 1
						Date = $driverVersion.Date; Version = $driverVersion.Version; Inf = $file.Name
					})
				}
				if (-not $hasDeviceId) { throw "Missing hardware or compatible ID in INF model entry '$line'." }
			}
			$applicable++
		}
		catch { throw "Unable to evaluate Lenovo INF '$($file.FullName)': $($_.Exception.Message)" }
	}
	return [pscustomobject]@{ Coverage = $coverage.ToArray(); Opaque = $opaque; InfCount = $files.Count; ApplicableInfCount = $applicable }
}

function Get-LenovoCoverageKeys {
	param([pscustomobject]$Record)

	$Record.Key
	$id = [string]$Record.DeviceId
	$base = [regex]::Match($id, '^PCI\\VEN_[0-9A-F]{4}&DEV_[0-9A-F]{4}(?:&|$)', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
	if (-not $base.Success) { return }
	$minimumLength = $base.Value.TrimEnd('&').Length
	$component = $Record.Key.Substring(0, $Record.Key.LastIndexOf('|'))
	while ($id.LastIndexOf('&') -ge $minimumLength) {
		$id = $id.Substring(0, $id.LastIndexOf('&'))
		"$component|$id"
	}
}

function Select-LenovoDriverPackages {
	[CmdletBinding()]
	param([Parameter(Mandatory)][object[]]$Packages)

	$selected = @{}
	$byDevice = @{}
	foreach ($package in $Packages) {
		$metadata = $package.InfMetadata
		if ($metadata.Coverage.Count -eq 0 -and (-not $package.Preferred -or -not $metadata.Opaque)) {
			WriteLog "Skipping Lenovo package '$($package.Title)' (version $($package.Version); ID: $($package.Id)): no applicable device coverage for this Windows target."
			continue
		}
		$selected[$package.Key] = $package
		foreach ($record in $metadata.Coverage) {
			if (-not $byDevice.ContainsKey($record.Key)) { $byDevice[$record.Key] = [Collections.Generic.List[object]]::new() }
			$byDevice[$record.Key].Add([pscustomobject]@{ Package = $package; Driver = $record })
		}
	}
	foreach ($package in $Packages | Sort-Object @{ Expression = 'Preferred'; Descending = $true }, Id) {
		if (-not $selected.ContainsKey($package.Key) -or ($package.Preferred -and $package.InfMetadata.Opaque)) { continue }
		$covered = $true
		foreach ($record in $package.InfMetadata.Coverage) {
			$replacement = $false
			foreach ($coverageKey in @(Get-LenovoCoverageKeys -Record $record)) {
				foreach ($other in $byDevice[$coverageKey]) {
					if ($other.Package.Key -eq $package.Key -or -not $selected.ContainsKey($other.Package.Key) -or
						$other.Driver.MatchRank -gt $record.MatchRank) { continue }
					$better = if ($other.Package.Preferred -ne $package.Preferred) { $other.Package.Preferred }
					else { $other.Driver.Date -gt $record.Date -or ($other.Driver.Date -eq $record.Date -and $other.Driver.Version -gt $record.Version) }
					if ($better) { $replacement = $true; break }
				}
				if ($replacement) { break }
			}
			if (-not $replacement) { $covered = $false; break }
		}
		if ($covered) {
			$selected.Remove($package.Key)
			WriteLog "Skipping Lenovo package '$($package.Title)' (version $($package.Version); ID: $($package.Id)): fully covered by selected Windows 11 packages or newer drivers."
		}
	}
	if ($selected.Count -eq 0) { throw 'Lenovo driver selection produced no applicable packages.' }
	foreach ($package in $selected.Values | Sort-Object Id) {
		if (-not $package.Preferred) {
			WriteLog "Selected Lenovo Windows 10 fallback '$($package.Title)' (version $($package.Version); ID: $($package.Id))."
		}
		else { WriteLog "Selected Lenovo Windows 11 package '$($package.Title)' (version $($package.Version); ID: $($package.Id))." }
	}
	return $selected.Values | Sort-Object Id
}

function Export-LenovoMsiCabinets {
	param([string]$Path, [string]$DestinationPath)

	$installer = $null
	$database = $null
	$view = $null
	$record = $null
	$cabinets = [Collections.Generic.List[string]]::new()
	try {
		$installer = New-Object -ComObject WindowsInstaller.Installer
		$database = $installer.OpenDatabase($Path, 0)
		$view = $database.OpenView('SELECT `Name` FROM `_Streams`')
		$null = $view.Execute()
		$names = [Collections.Generic.List[string]]::new()
		while ($null -ne ($record = $view.Fetch())) {
			$name = [string]$record.StringData(1)
			if ($name.EndsWith('.cab', [StringComparison]::OrdinalIgnoreCase)) { $names.Add($name) }
			$null = [Runtime.InteropServices.Marshal]::ReleaseComObject($record)
			$record = $null
		}
		$null = $view.Close()
		$null = [Runtime.InteropServices.Marshal]::ReleaseComObject($view)
		$view = $null
		foreach ($name in $names) {
			$view = $database.OpenView("SELECT ``Data`` FROM ``_Streams`` WHERE ``Name``='$($name.Replace("'", "''"))'")
			$null = $view.Execute()
			$record = $view.Fetch()
			if ($null -eq $record) { throw "MSI cabinet stream '$name' is missing from '$Path'." }
			$null = Get-DriverPathFreeSpace -Path $DestinationPath -RequiredBytes $record.DataSize(1)
			$cabinetPath = Join-Path $DestinationPath "stream$($cabinets.Count).cab"
			$output = [IO.File]::Create($cabinetPath)
			try {
				do {
					# ReadStream format 1 preserves one byte per BSTR character, including zero bytes.
					[string]$chunk = $record.ReadStream(1, 64KB, 1)
					if ($chunk.Length -gt 0) {
						$bytes = [byte[]][char[]]$chunk
						$output.Write($bytes, 0, $bytes.Length)
					}
				} while ($chunk.Length -gt 0)
			}
			finally { $output.Dispose() }
			$cabinets.Add($cabinetPath)
			$null = [Runtime.InteropServices.Marshal]::ReleaseComObject($record)
			$record = $null
			$null = $view.Close()
			$null = [Runtime.InteropServices.Marshal]::ReleaseComObject($view)
			$view = $null
		}
	}
	finally {
		if ($null -ne $record) { $null = [Runtime.InteropServices.Marshal]::ReleaseComObject($record) }
		if ($null -ne $view) { $null = $view.Close(); $null = [Runtime.InteropServices.Marshal]::ReleaseComObject($view) }
		if ($null -ne $database) { $null = [Runtime.InteropServices.Marshal]::ReleaseComObject($database) }
		if ($null -ne $installer) { $null = [Runtime.InteropServices.Marshal]::ReleaseComObject($installer) }
	}
	return $cabinets.ToArray()
}

function Export-LenovoMsiResources {
	param([string]$Path, [string]$DestinationPath)

	$stream = [IO.File]::OpenRead($Path)
	$reader = $null
	$resources = [Collections.Generic.List[string]]::new()
	try {
		$reader = [Reflection.PortableExecutable.PEReader]::new($stream)
		$directory = $reader.PEHeaders.PEHeader.ResourceTableDirectory
		if ($directory.Size -eq 0) { return }
		$data = [byte[]]$reader.GetSectionData($directory.RelativeVirtualAddress).GetContent(0, $directory.Size)
		$pending = [Collections.Generic.Queue[int]]::new()
		$pending.Enqueue(0)
		$seen = [Collections.Generic.HashSet[int]]::new()
		while ($pending.Count -gt 0) {
			$offset = $pending.Dequeue()
			if (-not $seen.Add($offset)) { continue }
			if ($offset -lt 0 -or $offset + 16 -gt $data.Length) { throw "Invalid resource directory in '$Path'." }
			$count = [int][BitConverter]::ToUInt16($data, $offset + 12) + [int][BitConverter]::ToUInt16($data, $offset + 14)
			if ($offset + 16 + $count * 8 -gt $data.Length) { throw "Invalid resource entries in '$Path'." }
			for ($index = 0; $index -lt $count; $index++) {
				$entry = [BitConverter]::ToUInt32($data, $offset + 16 + $index * 8 + 4)
				$target = [int]($entry -band 0x7fffffff)
				if (($entry -band 0x80000000L) -ne 0) { $pending.Enqueue($target); continue }
				if ($target + 16 -gt $data.Length) { throw "Invalid resource data entry in '$Path'." }
				$rva = [BitConverter]::ToInt32($data, $target)
				$size = [BitConverter]::ToInt32($data, $target + 4)
				if ($size -lt 8) { continue }
				$block = $reader.GetSectionData($rva)
				if ($size -gt $block.Length) { throw "Resource data exceeds the executable bounds in '$Path'." }
				$signature = [byte[]]$block.GetContent(0, 8)
				if ([Convert]::ToHexString($signature) -ne 'D0CF11E0A1B11AE1') { continue }
				$destination = Join-Path $DestinationPath "resource$($resources.Count).msi"
				$null = Get-DriverPathFreeSpace -Path $DestinationPath -RequiredBytes $size
				[IO.File]::WriteAllBytes($destination, [byte[]]$block.GetContent(0, $size))
				$resources.Add($destination)
			}
		}
	}
	finally {
		if ($null -ne $reader) { $reader.Dispose() }
		$stream.Dispose()
	}
	return $resources.ToArray()
}

function Export-LenovoCompressedSetupPayloads {
	param([string]$Path, [string]$DestinationPath)

	$archiveStream = [IO.File]::OpenRead($Path)
	$pe = $null
	$msiFiles = [Collections.Generic.List[string]]::new()
	try {
		$pe = [Reflection.PortableExecutable.PEReader]::new($archiveStream)
		$overlayStart = [long](($pe.PEHeaders.SectionHeaders | ForEach-Object {
			[long]$_.PointerToRawData + $_.SizeOfRawData
		} | Measure-Object -Maximum).Maximum)
		$archiveEnd = [long]$pe.PEHeaders.PEHeader.CertificateTableDirectory.RelativeVirtualAddress
		if ($archiveEnd -eq 0) { $archiveEnd = $archiveStream.Length }
		if ($overlayStart -le 0 -or $archiveEnd -gt $archiveStream.Length -or $archiveEnd - $overlayStart -lt 64) {
			throw "Invalid Intel setup archive bounds in '$Path'."
		}
		$tail = [byte[]]::new(64)
		$archiveStream.Position = $archiveEnd - $tail.Length
		$archiveStream.ReadExactly($tail, 0, $tail.Length)
		# Intel's trailer indexes independent zlib records before the Authenticode certificate.
		$marker = '#---+---+---+---#'
		$markerOffset = [Text.Encoding]::ASCII.GetString($tail).LastIndexOf($marker, [StringComparison]::Ordinal)
		if ($markerOffset -lt 16) { throw "Unsupported Intel compressed setup archive '$Path'." }
		$footer = $archiveEnd - $tail.Length + $markerOffset - 16
		$tableStart = [BitConverter]::ToInt64($tail, $markerOffset - 16)
		if ([BitConverter]::ToInt64($tail, $markerOffset - 8) -ne $footer + 8 -or
			$tableStart -lt $overlayStart -or $tableStart -gt $footer - 16 -or
			@($tail | Select-Object -Skip ($markerOffset + $marker.Length) | Where-Object { $_ -ne 0 }).Count -gt 0) {
			throw "Invalid Intel setup archive footer in '$Path'."
		}
		$archiveStream.Position = $tableStart
		$header = [byte[]]::new(16)
		$archiveStream.ReadExactly($header, 0, $header.Length)
		$count = [BitConverter]::ToUInt32($header, 4)
		if ([BitConverter]::ToUInt32($header, 0) -ne 16 -or $count -eq 0 -or
			$tableStart + 16 + [long]$count * 24 -ne $footer) {
			throw "Invalid Intel setup archive index in '$Path'."
		}
		$entries = [Collections.Generic.List[object]]::new()
		$previousEnd = $overlayStart
		for ($index = 0; $index -lt $count; $index++) {
			$entry = [byte[]]::new(24)
			$archiveStream.ReadExactly($entry, 0, $entry.Length)
			$type = [BitConverter]::ToUInt32($entry, 0)
			$offset = [BitConverter]::ToInt64($entry, 4)
			$compressedSize = [BitConverter]::ToUInt32($entry, 12)
			$expandedSize = [BitConverter]::ToUInt32($entry, 16)
			if ($type -notin @(1, 2) -or $offset -ne $previousEnd -or $compressedSize -eq 0 -or
				$compressedSize -gt [int]::MaxValue -or $offset + $compressedSize -gt $tableStart -or
				($type -eq 1 -and ($expandedSize -lt 54 -or [BitConverter]::ToUInt32($entry, 20) -ne 0x1111))) {
				throw "Invalid Intel setup archive entry in '$Path'."
			}
			$entries.Add([pscustomobject]@{ Type = $type; Offset = $offset; CompressedSize = $compressedSize; Size = $expandedSize })
			$previousEnd = $offset + $compressedSize
		}
		if ($previousEnd -ne $tableStart) { throw "Intel setup archive index does not cover its payload in '$Path'." }
		$root = [IO.Path]::GetFullPath($DestinationPath).TrimEnd('\')
		$null = New-Item -Path $root -ItemType Directory -Force -ErrorAction Stop
		$encoding = [Text.UTF8Encoding]::new($false, $true)
		foreach ($entry in $entries) {
			if ($entry.Type -ne 1) { continue }
			$archiveStream.Position = $entry.Offset
			$compressed = [byte[]]::new([int]$entry.CompressedSize)
			$archiveStream.ReadExactly($compressed, 0, $compressed.Length)
			$buffer = [IO.MemoryStream]::new($compressed, $false)
			$inflater = [IO.Compression.ZLibStream]::new($buffer, [IO.Compression.CompressionMode]::Decompress)
			try {
				$record = [byte[]]::new(50)
				$inflater.ReadExactly($record, 0, $record.Length)
				$fileSize = [BitConverter]::ToUInt32($record, 38)
				$nameLength = [BitConverter]::ToUInt32($record, 42)
				$directoryLength = [long]$entry.Size - $fileSize - 50 - $nameLength
				if ([BitConverter]::ToUInt32($record, 0) -ne 1 -or
					[BitConverter]::ToUInt32($record, 4) -ne $entry.Size -or
					[BitConverter]::ToUInt32($record, 8) -ne $entry.Size -or [BitConverter]::ToUInt16($record, 12) -ne 0x1111 -or
					$nameLength -eq 0 -or $nameLength -gt 64KB -or $directoryLength -lt 1 -or $directoryLength -gt 64KB) {
					throw "Invalid Intel setup file record in '$Path'."
				}
				$nameBytes = [byte[]]::new([int]$nameLength)
				$directoryBytes = [byte[]]::new([int]$directoryLength)
				$inflater.ReadExactly($nameBytes, 0, $nameBytes.Length)
				$inflater.ReadExactly($directoryBytes, 0, $directoryBytes.Length)
				$name = $encoding.GetString($nameBytes).TrimEnd([char]0)
				$directory = $encoding.GetString($directoryBytes).TrimEnd([char]0)
				if (-not $name -or $name -ne [IO.Path]::GetFileName($name) -or
					$name.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or $directory.Contains([char]0) -or
					[IO.Path]::IsPathRooted($directory)) { throw "Invalid Intel setup payload path '$directory\$name'." }
				$relative = if ($directory) { Join-Path $directory $name } else { $name }
				$target = [IO.Path]::GetFullPath((Join-Path $root $relative))
				if (-not $target.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
					throw "Invalid Intel setup payload path '$relative'."
				}
				$extension = [IO.Path]::GetExtension($name).ToLowerInvariant()
				if ($extension -notin @('.msi', '.cab')) { continue }
				if ($fileSize -lt 8 -or (Test-Path -LiteralPath $target)) { throw "Invalid or conflicting Intel setup payload '$relative'." }
				$null = Get-DriverPathFreeSpace -Path $root -RequiredBytes $fileSize
				$signature = [byte[]]::new(8)
				$inflater.ReadExactly($signature, 0, $signature.Length)
				if (($extension -eq '.msi' -and [Convert]::ToHexString($signature) -ne 'D0CF11E0A1B11AE1') -or
					($extension -eq '.cab' -and [Text.Encoding]::ASCII.GetString($signature, 0, 4) -ne 'MSCF')) {
					throw "Invalid Intel setup $extension signature for '$relative'."
				}
				$null = New-Item -Path (Split-Path $target -Parent) -ItemType Directory -Force -ErrorAction Stop
				$output = [IO.File]::Open($target, [IO.FileMode]::CreateNew)
				try {
					$output.Write($signature, 0, $signature.Length)
					$remaining = [long]$fileSize - $signature.Length
					$chunk = [byte[]]::new(64KB)
					while ($remaining -gt 0) {
						$length = [int][Math]::Min($chunk.Length, $remaining)
						$inflater.ReadExactly($chunk, 0, $length)
						$output.Write($chunk, 0, $length)
						$remaining -= $length
					}
					if ($inflater.ReadByte() -ne -1) { throw "Intel setup payload size mismatch for '$relative'." }
				}
				finally { $output.Dispose() }
				if ($extension -eq '.msi') { $msiFiles.Add($target) }
			}
			finally { $inflater.Dispose(); $buffer.Dispose() }
		}
	}
	finally {
		if ($null -ne $pe) { $pe.Dispose() }
		$archiveStream.Dispose()
	}
	return $msiFiles.ToArray()
}

function Expand-LenovoDriverMsiPackages {
	param([pscustomobject]$Workspace, [string[]]$MsiPaths, [string]$DriversFolder, [string]$RootDirectoryProperty = 'TARGETDIR')

	$index = 0
	foreach ($resource in $MsiPaths) {
		while (Test-Path -LiteralPath (Join-Path $Workspace.OutputPath "msi$index")) { $index++ }
		$fileName = [IO.Path]::GetFileName($resource)
		if ([IO.Path]::GetExtension($fileName) -ne '.msi') { $fileName = "package$index.msi" }
		$nested = New-DriverExtractionWorkspace -Context $Workspace.Context -DriversFolder $DriversFolder `
			-FileName $fileName -FinalPath $Workspace.FinalPath `
			-CachePath (Join-Path $Workspace.FinalPath $fileName) -ComponentName $Workspace.ComponentName -AllowShortName
		$extracted = $false
		try {
			Copy-Item -LiteralPath $resource -Destination $nested.InputPath -ErrorAction Stop
			foreach ($cabinet in @(Get-ChildItem -LiteralPath (Split-Path $resource -Parent) -Filter '*.cab' -File -ErrorAction Stop)) {
				Copy-Item -LiteralPath $cabinet.FullName -Destination (Join-Path (Split-Path $nested.InputPath -Parent) $cabinet.Name) -ErrorAction Stop
			}
			$nested.InputComplete = $true
			Invoke-DriverMsiExtraction -Workspace $nested -RootDirectoryProperty $RootDirectoryProperty
			Confirm-DriverOperationActive -Context $Workspace.Context
			Copy-Item -LiteralPath $nested.OutputPath -Destination (Join-Path $Workspace.OutputPath "msi$index") -Recurse -ErrorAction Stop
			$extracted = $true
			$index++
		}
		finally { $null = Remove-DriverExtractionWorkspace -Workspace $nested -Discard:$extracted }
	}
}

function Expand-LenovoFingerprintResources {
	param([pscustomobject]$Workspace, [string]$Path, [string]$DriversFolder)

	$resources = @(Export-LenovoMsiResources -Path $Path -DestinationPath (Split-Path $Workspace.InputPath -Parent))
	if ($resources.Count -eq 0) { throw "No embedded MSI resources were found in Lenovo fingerprint wrapper '$Path'." }
	Reset-DriverExtractionOutput -Workspace $Workspace
	Expand-LenovoDriverMsiPackages -Workspace $Workspace -MsiPaths $resources -DriversFolder $DriversFolder
}

function Restore-LenovoBundlePayloads {
	param([string]$Path)

	$files = @(Get-ChildItem -LiteralPath $Path -File -Recurse -ErrorAction Stop)
	$payloadRoot = [IO.Path]::GetFullPath((Join-Path $Path 'payloads'))
	foreach ($file in @($files | Where-Object Name -eq '0')) {
		$reader = [IO.StreamReader]::new($file.FullName, [Text.Encoding]::UTF8, $true)
		try {
			$prefix = [char[]]::new(64)
			$count = $reader.Read($prefix, 0, $prefix.Length)
			if ([string]::new($prefix, 0, $count) -notmatch '^\s*<\?xml\b') { continue }
		}
		finally { $reader.Dispose() }
		[xml]$manifest = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop
		if ($manifest.DocumentElement.LocalName -ne 'BurnManifest') { continue }
		$payloads = @($manifest.SelectNodes('//*[local-name()="Payload"]'))
		$groups = @(
			foreach ($package in $manifest.SelectNodes('//*[local-name()="Chain"]/*')) {
				$id = $package.GetAttribute('Id')
				if ($id -notmatch '^[a-zA-Z0-9_.-]+$') { throw "Invalid Lenovo bundle package identity '$id'." }
				$ids = @($package.SelectNodes('*[local-name()="PayloadRef"]') | ForEach-Object { $_.GetAttribute('Id') })
				[pscustomobject]@{ Name = $id; Payloads = @($payloads | Where-Object { $_.GetAttribute('Id') -in $ids }) }
			}
		)
		if ($groups.Count -eq 0) { $groups = @([pscustomobject]@{ Name = ''; Payloads = $payloads }) }
		foreach ($group in $groups) {
			$groupRoot = if ($group.Name) { Join-Path $payloadRoot $group.Name } else { $payloadRoot }
			foreach ($payload in $group.Payloads) {
				if ($payload.GetAttribute('Packaging') -ne 'embedded') { continue }
				$sourceName = $payload.GetAttribute('SourcePath')
				$relativePath = $payload.GetAttribute('FilePath')
				$target = [IO.Path]::GetFullPath((Join-Path $groupRoot $relativePath))
				if (-not $sourceName -or -not $relativePath -or -not $target.StartsWith($groupRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
					throw "Invalid Lenovo bundle payload path '$relativePath'."
				}
				$sources = @($files | Where-Object Name -eq $sourceName)
				if ($sources.Count -ne 1) { throw "Cannot uniquely resolve Lenovo bundle payload '$sourceName'." }
				$hash = $payload.GetAttribute('Hash')
				Confirm-LenovoDriverHash -Path $sources[0].FullName -Hash $hash
				if (Test-Path -LiteralPath $target -PathType Leaf) {
					if ((Get-FileHash -LiteralPath $target -Algorithm SHA256 -ErrorAction Stop).Hash -ne
						(Get-FileHash -LiteralPath $sources[0].FullName -Algorithm SHA256 -ErrorAction Stop).Hash) {
						throw "Conflicting Lenovo bundle payload destination '$relativePath'."
					}
					continue
				}
				$null = New-Item -Path (Split-Path $target -Parent) -ItemType Directory -Force -ErrorAction Stop
				Copy-Item -LiteralPath $sources[0].FullName -Destination $target -ErrorAction Stop
			}
		}
	}
}

function Expand-LenovoEmbeddedCabinets {
	param([pscustomobject]$Workspace, [string]$Path)

	$cabinets = @(Export-DriverEmbeddedCabinets -Path $Path -DestinationPath (Split-Path $Workspace.InputPath -Parent) -All)
	if ($cabinets.Count -eq 0) { throw "The embedded Lenovo driver bundle has no readable Windows cabinets: '$Path'." }
	Reset-DriverExtractionOutput -Workspace $Workspace
	$pending = [Collections.Generic.Queue[string]]::new()
	foreach ($cabinet in $cabinets) { $pending.Enqueue($cabinet) }
	$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
	$seenMsi = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
	$index = 0
	$msiIndex = 0
	while ($pending.Count -gt 0) {
		$cabinet = $pending.Dequeue()
		$hash = (Get-FileHash -LiteralPath $cabinet -Algorithm SHA256 -ErrorAction Stop).Hash
		if (-not $seen.Add($hash)) { continue }
		$destination = Join-Path $Workspace.OutputPath "cab$index"
		$index++
		$null = New-Item -Path $destination -ItemType Directory -ErrorAction Stop
		$null = Invoke-DriverExtractionProcess -Workspace $Workspace -FilePath 'expand.exe' `
			-ArgumentList "-R `"$cabinet`" -F:* `"$destination`""
		foreach ($file in @(Get-ChildItem -LiteralPath $destination -File -Recurse -ErrorAction Stop)) {
			if ($file.Length -lt 8) { continue }
			$stream = [IO.File]::OpenRead($file.FullName)
			try {
				$signature = [byte[]]::new(8)
				$stream.ReadExactly($signature, 0, 8)
			}
			finally { $stream.Dispose() }
			if ([Text.Encoding]::ASCII.GetString($signature, 0, 4) -eq 'MSCF') { $pending.Enqueue($file.FullName) }
			elseif ([Convert]::ToHexString($signature) -eq 'D0CF11E0A1B11AE1') {
				$msiHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
				if (-not $seenMsi.Add($msiHash)) { continue }
				$msiDestination = Join-Path $Workspace.OutputPath "streams$msiIndex"
				$msiIndex++
				$null = New-Item -Path $msiDestination -ItemType Directory -ErrorAction Stop
				foreach ($embedded in @(Export-LenovoMsiCabinets -Path $file.FullName -DestinationPath $msiDestination)) {
					$pending.Enqueue($embedded)
				}
			}
		}
	}
	Restore-LenovoBundlePayloads -Path $Workspace.OutputPath
	$null = Test-DriverExtractionOutput -Path $Workspace.OutputPath -RequireInf -ComponentName $Workspace.ComponentName
}

function Save-LenovoDriverPackages {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)][ValidatePattern('^[A-Z0-9]{4}$')][string]$MachineType,
		[Parameter(Mandatory)][string]$ModelPath,
		[Parameter(Mandatory)][string]$DriversFolder,
		[Parameter(Mandatory)][ValidateSet(10, 11)][int]$WindowsRelease,
		[Parameter(Mandatory)][ValidateSet('x64', 'x86', 'ARM64')][string]$WindowsArch,
		[string]$WindowsVersion,
		[string]$Identifier,
		[pscustomobject]$DriverOperationContext,
		[System.Collections.Concurrent.ConcurrentQueue[hashtable]]$ProgressQueue,
		[switch]$RetryIncomplete,
		[switch]$RenameLiteonFolders,
		[switch]$RetainInstallerOnFailure,
		[bool]$IgnoreDriverDownloadErrors = $false,
		[Collections.Generic.List[object]]$FailedDrivers
	)

	if ($null -eq $FailedDrivers) { $FailedDrivers = [Collections.Generic.List[object]]::new() }
	$usablePackages = [Collections.Generic.List[object]]::new()
	$target = Get-LenovoDriverTarget -WindowsRelease $WindowsRelease -WindowsArch $WindowsArch -WindowsVersion $WindowsVersion
	$metadataPath = Join-Path $DriversFolder ("_TEMP_$($MachineType)_$([guid]::NewGuid().ToString('N').Substring(0, 8))")
	$workspaces = [Collections.Generic.List[object]]::new()
	$discarded = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
	$metadataOwned = $false
	$ownsOperation = $null -eq $DriverOperationContext
	try {
		if ($ownsOperation) {
			$DriverOperationContext = New-DriverOperationContext -FFUDevelopmentPath (Split-Path $PSScriptRoot -Parent) -DriversFolder $DriversFolder
		}
		if (Test-Path -LiteralPath $metadataPath) { throw "Lenovo metadata workspace collision: '$metadataPath'." }
		$null = New-Item -Path $metadataPath -ItemType Directory -ErrorAction Stop
		$metadataOwned = $true
		$packages = @(Get-LenovoDriverPackages -MachineType $MachineType -MetadataPath $metadataPath -WindowsRelease $WindowsRelease `
			-WindowsArch $WindowsArch -WindowsVersion $WindowsVersion -DriverOperationContext $DriverOperationContext)
		$index = 0
		foreach ($package in $packages) {
			Confirm-DriverOperationActive -Context $DriverOperationContext
			$index++
			if ($null -ne $ProgressQueue) {
				$ProgressQueue.Enqueue(@{ Identifier = $Identifier; Status = "$index/$($packages.Count) Downloading $($package.Title)" })
			}
			$category = $package.Category -replace '[\\/:"*?<>|]', '_'
			if ($category -eq 'Motherboard Devices Backplanes core chipset onboard video PCIe switches') { $category = 'Motherboard Devices' }
			$title = $package.Title -replace '[\\/:"*?<>|]', '_' -replace ' - .*', ''
			$downloadFolder = Join-Path (Join-Path $ModelPath $category) $title
			$finalPath = Join-Path $downloadFolder ([IO.Path]::GetFileNameWithoutExtension($package.FileName))
			$outputPath = $finalPath
			$validation = $null
			if (-not $RetryIncomplete -and (Test-Path -LiteralPath $finalPath -PathType Container)) {
				try {
					$validation = Test-DriverExtractionOutput -Path $finalPath -RequireInf `
						-AllowProvisioningPackage:(-not $package.RequiresInfClassification) -ComponentName "$Identifier | $title"
					$package.Reused = $true
				}
				catch { WriteLog "Re-extracting incomplete Lenovo package '$($package.Id)': $($_.Exception.Message)" }
			}
			try {
			if (-not $package.Reused) {
				$workspace = New-DriverExtractionWorkspace -Context $DriverOperationContext -DriversFolder $DriversFolder `
					-FileName $package.FileName -FinalPath $finalPath -CachePath (Join-Path $downloadFolder $package.FileName) `
					-ComponentName "$Identifier | $title" -RetainInstallerOnFailure:$RetainInstallerOnFailure
				$workspaces.Add($workspace)
				$package.Workspace = $workspace
				$cached = Test-Path -LiteralPath $workspace.CachePath -PathType Leaf
				Save-DriverPackageToWorkspace -Workspace $workspace -Source $package.Url
				try { Confirm-LenovoDriverHash -Path $workspace.InputPath -Hash $package.Hash }
				catch {
					if (-not $cached) { throw }
					WriteLog "Cached Lenovo installer '$($package.FileName)' failed checksum validation; downloading the current package. $($_.Exception.Message)"
					Save-DriverPackageToWorkspace -Workspace $workspace -Source $package.Url -ForceDownload
					Confirm-LenovoDriverHash -Path $workspace.InputPath -Hash $package.Hash
				}
				if ($package.RequiresInnoValidation) { Confirm-LenovoInnoInstaller -Path $workspace.InputPath }
				try {
				$arguments = $package.ExtractCommand.Replace('%PACKAGEPATH%', "`"$($workspace.OutputPath)`"", [StringComparison]::OrdinalIgnoreCase)
				if ($null -ne $ProgressQueue) {
					$ProgressQueue.Enqueue(@{ Identifier = $Identifier; Status = "$index/$($packages.Count) Extracting $($package.Title)" })
				}
				try { $null = Invoke-DriverExtractionProcess -Workspace $workspace -ArgumentList $arguments -EnableInnoLogging }
				catch {
					if ($_.Exception.Data['ExitCode'] -ne 1001 -or
						$arguments -notmatch '(?:^|\s)/(?:VERYSILENT|SILENT)(?:\s|$)' -or
						$arguments -notmatch '(?:^|\s)/DIR=' -or
						$arguments -notmatch '(?:^|\s)/EXTRACT=(?:"YES"|YES)(?:\s|$)') { throw }
					Confirm-DriverOperationActive -Context $DriverOperationContext
					$nativeLog = Join-Path $workspace.DiagnosticsPath 'extract.log'
					if (-not (Test-Path -LiteralPath $nativeLog -PathType Leaf) -or
						[IO.File]::ReadAllText($nativeLog) -notmatch '(?m)^\S+\s+\S+\s+Installation process succeeded\.\s*$') { throw }
					Confirm-LenovoInnoInstaller -Path $workspace.InputPath
					$null = Test-DriverExtractionOutput -Path $workspace.OutputPath -RequireInf -ComponentName "$Identifier | $title"
					WriteLog "Accepted Lenovo extraction exit code 1001 for '$($package.Title)' (ID: $($package.Id)): verified Lenovo Inno installer, successful native extraction log, and driver INF output."
				}
				$chipsetSetup = Join-Path $workspace.OutputPath 'SetupChipset.exe'
				$driverInfs = @(Get-ChildItem -LiteralPath $workspace.OutputPath -Filter '*.inf' -File -Recurse -ErrorAction Stop | Where-Object Name -ne 'autorun.inf')
				if ($driverInfs.Count -eq 0 -and (Test-Path -LiteralPath $chipsetSetup -PathType Leaf) -and
					@(Get-ChildItem -LiteralPath $workspace.OutputPath -Filter '*.ppkg' -File -Recurse -ErrorAction Stop).Count -eq 0) {
					$infPath = Join-Path $workspace.OutputPath 'inf'
					$null = New-Item -Path $infPath -ItemType Directory -Force -ErrorAction Stop
					WriteLog "Extracting the embedded Intel chipset driver files for Lenovo package '$($package.Id)'."
					$null = Invoke-DriverExtractionProcess -Workspace $workspace -FilePath $chipsetSetup `
						-ArgumentList "-extract `"$infPath`" -s -norestart -log `"$($workspace.DiagnosticsPath)\chipset.log`""
					if (@(Get-ChildItem -LiteralPath $infPath -Filter '*.inf' -File -Recurse -ErrorAction Stop).Count -eq 0) {
						WriteLog "Intel chipset extraction returned no INFs; using native cabinet extraction for Lenovo package '$($package.Id)'."
						Expand-LenovoEmbeddedCabinets -Workspace $workspace -Path $chipsetSetup
					}
				}
				$driverInfs = @(Get-ChildItem -LiteralPath $workspace.OutputPath -Filter '*.inf' -File -Recurse -ErrorAction Stop | Where-Object Name -ne 'autorun.inf')
				if ($driverInfs.Count -eq 0 -and @(Get-ChildItem -LiteralPath $workspace.OutputPath -Filter '*.ppkg' -File -Recurse -ErrorAction Stop).Count -eq 0) {
					$fingerprintWrappers = @(Get-ChildItem -LiteralPath $workspace.OutputPath -Filter 'WBFDDKSetup*.exe' -File -ErrorAction Stop)
					$setupPath = Join-Path $workspace.OutputPath 'Setup.exe'
					$setupInfo = if (Test-Path -LiteralPath $setupPath -PathType Leaf) { [Diagnostics.FileVersionInfo]::GetVersionInfo($setupPath) } else { $null }
					if ($null -ne $setupInfo -and $setupInfo.CompanyName -eq 'Intel Corporation' -and $setupInfo.ProductName -match '\bWiDi\b') {
						WriteLog "Reading compressed Intel WiDi MSI and cabinet payloads for Lenovo package '$($package.Id)' without executing the nested setup."
						$archivePath = Join-Path (Split-Path $workspace.InputPath -Parent) 'intel-setup'
						$resources = @(Export-LenovoCompressedSetupPayloads -Path $setupPath -DestinationPath $archivePath)
						if ($resources.Count -eq 0) { throw "No MSI payloads were found in Intel WiDi setup '$setupPath'." }
						Reset-DriverExtractionOutput -Workspace $workspace
						Expand-LenovoDriverMsiPackages -Workspace $workspace -MsiPaths $resources -DriversFolder $DriversFolder -RootDirectoryProperty SRCDIR
					}
					elseif ($fingerprintWrappers.Count -eq 1) {
						WriteLog "Extracting embedded fingerprint MSI resources for Lenovo package '$($package.Id)' using administrative extraction."
						Expand-LenovoFingerprintResources -Workspace $workspace -Path $fingerprintWrappers[0].FullName -DriversFolder $DriversFolder
					}
					else {
						$msiFiles = @(Get-ChildItem -LiteralPath $workspace.OutputPath -Filter '*.msi' -File -Recurse -ErrorAction Stop)
						if ($msiFiles.Count -gt 0) {
							WriteLog "Administratively extracting Lenovo driver MSI payloads for '$($package.Id)'."
							Expand-LenovoDriverMsiPackages -Workspace $workspace -MsiPaths @($msiFiles.FullName) -DriversFolder $DriversFolder
						}
						else {
							$intelBundles = @(Get-ChildItem -LiteralPath $workspace.OutputPath -File -ErrorAction Stop |
								Where-Object Name -in @('SetupME.exe', 'SetupTXE.exe', 'WirelessSetup.exe'))
							if ($intelBundles.Count -eq 1) {
								WriteLog "Extracting embedded Intel driver cabinets for Lenovo package '$($package.Id)'."
								Expand-LenovoEmbeddedCabinets -Workspace $workspace -Path $intelBundles[0].FullName
							}
						}
					}
				}
				$validation = Test-DriverExtractionOutput -Path $workspace.OutputPath -RequireInf `
					-AllowProvisioningPackage:(-not $package.RequiresInfClassification) -ComponentName $workspace.ComponentName
				$outputPath = $workspace.OutputPath
				}
				catch [OperationCanceledException] { throw }
				catch {
					Confirm-DriverOperationActive -Context $DriverOperationContext
					$_.Exception.Data['DriverFailureStage'] = 'Extraction'
					throw
				}
			}
			if ($WindowsRelease -eq 11) {
				$package.InfMetadata = Get-LenovoDriverInfMetadata -Path $outputPath -WindowsArch $WindowsArch -WindowsBuild $target.Build -ProvisioningPackageCount $validation.PpkgCount
			}
			$usablePackages.Add($package)
			}
			catch {
				if ($null -eq $package.Workspace) { throw }
				$FailedDrivers.Add((Resolve-DriverPackageFailure -ErrorRecord $_ -IgnoreErrors $IgnoreDriverDownloadErrors `
					-Workspace $package.Workspace -Make Lenovo -Model $Identifier -DriverName $package.Title -Source $package.Url `
					-ValidationParameters @{ RequireInf = $true; AllowProvisioningPackage = -not $package.RequiresInfClassification }))
				if (Remove-DriverExtractionWorkspace -Workspace $package.Workspace) {
					$null = $workspaces.Remove($package.Workspace)
					$package.Workspace = $null
				}
			}
		}
		if ($usablePackages.Count -eq 0) { throw "No usable drivers remain for Lenovo model '$Identifier'." }
		$selected = if ($WindowsRelease -eq 11) { @(Select-LenovoDriverPackages -Packages $usablePackages.ToArray()) } else { $usablePackages.ToArray() }
		if ($selected.Count -eq 0) { throw "No usable drivers were selected for Lenovo model '$Identifier'." }
		$selectedKeys = [Collections.Generic.HashSet[string]]::new([string[]]@($selected | ForEach-Object Key), [StringComparer]::OrdinalIgnoreCase)
		foreach ($package in $usablePackages) {
			if ($null -ne $package.Workspace -and -not $selectedKeys.Contains($package.Key)) {
				$null = $discarded.Add($package.Workspace.PackageId)
			}
		}
		foreach ($package in $selected) {
			Confirm-DriverOperationActive -Context $DriverOperationContext
			if ($package.Reused) { continue }
			$workspace = $package.Workspace
			if ($RenameLiteonFolders) {
				foreach ($item in @(Get-ChildItem -LiteralPath $workspace.OutputPath -Directory -ErrorAction Stop | Where-Object Name -like '*Liteon*')) {
					do { $name = "Liteon_$(Get-Random -Minimum 1000 -Maximum 9999)" }
					while (Test-Path -LiteralPath (Join-Path $workspace.OutputPath $name))
					Rename-Item -LiteralPath $item.FullName -NewName $name -ErrorAction Stop
				}
			}
			Publish-DriverExtractionContent -Workspace $workspace -RequireInf -AllowProvisioningPackage:(-not $package.RequiresInfClassification)
		}
		WriteLog "Lenovo '$MachineType': published or reused $($selected.Count) selected packages from $($packages.Count) candidates."
		return [pscustomobject]@{ SuccessfulPackageCount = $selected.Count; FailedDrivers = $FailedDrivers.ToArray() }
	}
	catch {
		WriteLog "Lenovo driver selection/download failed for '$MachineType': $($_.Exception.Message)"
		throw
	}
	finally {
		foreach ($workspace in $workspaces) {
			$null = Remove-DriverExtractionWorkspace -Workspace $workspace -Discard:$discarded.Contains($workspace.PackageId)
		}
		try {
			if ($metadataOwned -and (Test-Path -LiteralPath $metadataPath)) { Remove-Item -LiteralPath $metadataPath -Recurse -Force -ErrorAction Stop }
		}
		finally {
			if ($ownsOperation -and $null -ne $DriverOperationContext) { Remove-DriverDownloadOperation -Context $DriverOperationContext }
		}
	}
}

Export-ModuleMember -Function Get-LenovoDriverPackages, Save-LenovoDriverPackages
