#Requires -RunAsAdministrator

# --- CONFIGURATION ---
# Base path where application folders are located. Each subfolder represents one application.
$basePath = "D:\MSStore"
# Path for temporary files (e.g., for extracting archives). This will be created and cleaned up automatically.
$tempBasePath = Join-Path -Path $env:TEMP -ChildPath "StoreAppInstall"

# --- SCRIPT ---

# Helper function to clean up temporary files on exit or error
function Remove-TemporaryFiles {
    if (Test-Path -Path $tempBasePath) {
        Write-Host "Cleaning up temporary directory: $tempBasePath"
        Remove-Item -Path $tempBasePath -Recurse -Force
    }
}

# Ensure temp directory is clean before starting
Remove-TemporaryFiles
New-Item -Path $tempBasePath -ItemType Directory -Force | Out-Null

# 1. Determine applicable dependency architectures based on the OS architecture
$osArchitecture = $env:PROCESSOR_ARCHITECTURE
$applicableArchitectures = switch ($osArchitecture) {
    "AMD64" { 'x64', 'x86' }
    "x86"   { 'x86' }
    "ARM64" { 'arm64', 'arm' }
    default { $osArchitecture.ToLower() }
}
Write-Host "Installing Store Apps: Detected OS Architecture: $osArchitecture."
Write-Host "Applicable dependency architectures: $($applicableArchitectures -join ', ')"

# Check if the base path exists
if (-not (Test-Path -Path $basePath)) {
    Write-Host "Installing Store Apps: Base path '$basePath' does not exist. Exiting."
    exit
}
Write-Host "Installing Store Apps: Base path '$basePath' exists."

# 2. Process and install each main application
Write-Host "Starting main application installation process..."
foreach ($appFolder in Get-ChildItem -Path $basePath -Directory) {
    Write-Host "--- Processing application in folder: $($appFolder.Name) ---"
    
    # Find the main application package (.appx/.msix/.appxbundle) in the app's root folder
    $mainPackage = Get-ChildItem -Path $appFolder.FullName -File |
                   Where-Object { $_.Extension -in '.appx', '.msix', '.appxbundle', '.msixbundle' } |
                   Select-Object -First 1

    if (-not $mainPackage) {
        Write-Warning "No main application package found in '$($appFolder.Name)'. Skipping."
        Write-Output ""
        continue
    }
    Write-Host "Found main package: $($mainPackage.Name)"

    # Extract and parse AppxManifest.xml from the main package
    $manifestTempPath = Join-Path -Path $tempBasePath -ChildPath "AppxManifest.xml"
    if (Test-Path $manifestTempPath) { Remove-Item $manifestTempPath -Force }
    
    $requiredDependencies = $null
    try {
        [System.Reflection.Assembly]::LoadWithPartialName("System.IO.Compression.FileSystem") | Out-Null
        
        # Logic for handling bundles vs. single packages
        if ($mainPackage.Extension -in '.appxbundle', '.msixbundle') {
            Write-Host "Processing bundle. Searching for architecture-specific package..."
            $bundleArchive = [System.IO.Compression.ZipFile]::OpenRead($mainPackage.FullName)
            try {
                # Find the best matching .appx/.msix package inside the bundle
                $primaryArch = if ($osArchitecture -eq 'AMD64') { 'x64' } else { $osArchitecture.ToLower() }
                $packageEntries = $bundleArchive.Entries | Where-Object { ($_.Name.EndsWith('.appx') -or $_.Name.EndsWith('.msix')) -and $_.Name -notlike "*_language-*" }
                
                # Prioritize the primary architecture, then x86 (on x64), then neutral
                $bestPackageEntry = $packageEntries | Where-Object { $_.Name -imatch "[._]${primaryArch}\.(appx|msix)$" } | Select-Object -First 1
                if (-not $bestPackageEntry -and $primaryArch -eq 'x64') {
                    $bestPackageEntry = $packageEntries | Where-Object { $_.Name -imatch "[._]x86\.(appx|msix)$" } | Select-Object -First 1
                }
                if (-not $bestPackageEntry) {
                    $bestPackageEntry = $packageEntries | Where-Object { $_.Name -imatch "[._]neutral\.(appx|msix)$" } | Select-Object -First 1
                }

                if ($bestPackageEntry) {
                    Write-Host "Found inner package: $($bestPackageEntry.Name). Extracting to read its manifest."
                    $innerPackageTempPath = Join-Path -Path $tempBasePath -ChildPath $bestPackageEntry.Name
                    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($bestPackageEntry, $innerPackageTempPath, $true)
                    
                    $innerPackageArchive = [System.IO.Compression.ZipFile]::OpenRead($innerPackageTempPath)
                    try {
                        $manifestEntry = $innerPackageArchive.Entries | Where-Object { $_.Name -eq 'AppxManifest.xml' } | Select-Object -First 1
                        if ($manifestEntry) {
                            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($manifestEntry, $manifestTempPath, $true)
                        }
                    } finally {
                        $innerPackageArchive.Dispose()
                    }
                } else {
                    Write-Error "Could not find a suitable architecture-specific package inside '$($mainPackage.Name)'."
                }
            } finally {
                $bundleArchive.Dispose()
            }
        } else { # It's a regular .appx or .msix
            $zipArchive = [System.IO.Compression.ZipFile]::OpenRead($mainPackage.FullName)
            try {
                $manifestEntry = $zipArchive.Entries | Where-Object { $_.Name -eq 'AppxManifest.xml' } | Select-Object -First 1
                if ($manifestEntry) {
                    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($manifestEntry, $manifestTempPath, $true)
                }
            } finally {
                $zipArchive.Dispose()
            }
        }

        # Common manifest parsing logic
        if (Test-Path $manifestTempPath) {
            [xml]$manifest = Get-Content -Path $manifestTempPath
            $nsm = [System.Xml.XmlNamespaceManager]::new($manifest.NameTable)
            $nsm.AddNamespace("def", "http://schemas.microsoft.com/appx/manifest/foundation/windows10")
            
            $dependenciesNode = $manifest.SelectSingleNode("//def:Dependencies", $nsm)
            if ($dependenciesNode) {
                $requiredDependencies = $dependenciesNode.SelectNodes("def:PackageDependency", $nsm)
            }
        } else {
            Write-Error "Could not find or extract AppxManifest.xml from '$($mainPackage.FullName)'."
        }
    } catch {
        Write-Error "Failed to read or parse manifest from '$($mainPackage.FullName)'. Error: $($_.Exception.Message)"
    }

    # Scan for and resolve dependencies only if the manifest lists actual package dependencies.
    $resolvedDependencyPaths = [System.Collections.Generic.List[string]]::new()

    if ($null -ne $requiredDependencies -and $requiredDependencies.Count -gt 0) {
        $appDependenciesPath = Join-Path -Path $appFolder.FullName -ChildPath "Dependencies"
        
        if (Test-Path -Path $appDependenciesPath) {
            Write-Host "Scanning for dependencies in '$appDependenciesPath'..."
            $appSpecificDependencies = @{}
            $dependencyFoldersToScan = [System.Collections.Generic.List[string]]::new()
            $dependencyFoldersToScan.Add($appDependenciesPath)

            # Handle zipped dependencies by extracting them to a temp location
            Get-ChildItem -Path $appDependenciesPath -Filter "*.zip" -File | ForEach-Object {
                $zipFile = $_
                # Ensure unique extract path per app to avoid conflicts
                $extractPath = Join-Path -Path $tempBasePath -ChildPath "$($appFolder.Name)_$($zipFile.BaseName)"
                Write-Host "Extracting zipped dependencies from '$($zipFile.FullName)' to '$extractPath'..."
                try {
                    Expand-Archive -Path $zipFile.FullName -DestinationPath $extractPath -Force
                    $dependencyFoldersToScan.Add($extractPath)
                }
                catch {
                    Write-Error "Failed to extract '$($zipFile.FullName)'. Error: $($_.Exception.Message)"
                }
            }

            # Regex to parse package filenames
            $packageFileRegex = '^(?<Name>.+?)_(?<Version>(?:\d+\.){2,3}\d+)_(?:[^_]+_)*(?<Arch>x64|x86|arm|arm64|neutral)(?:__.*)?$'

            # Catalog all package files found in the dependency folders for this app
            foreach ($folder in $dependencyFoldersToScan.ToArray() | Select-Object -Unique) {
                Get-ChildItem -Path $folder -Recurse -File | Where-Object { $_.Extension -in '.appx', '.msix', '.appxbundle' } | ForEach-Object {
                    $file = $_
                    $match = $file.BaseName -imatch $packageFileRegex
                    if ($match) {
                        $dependencyName = $matches.Name
                        try {
                            $dependencyVersion = [System.Version]$matches.Version
                            $dependencyArch = $matches.Arch

                            if (-not $appSpecificDependencies.ContainsKey($dependencyName)) {
                                $appSpecificDependencies[$dependencyName] = [System.Collections.Generic.List[object]]::new()
                            }
                            $appSpecificDependencies[$dependencyName].Add([pscustomobject]@{
                                Name    = $dependencyName
                                Version = $dependencyVersion
                                Arch    = $dependencyArch
                                Path    = $file.FullName
                            })
                        }
                        catch {
                            Write-Warning "Could not parse version for file '$($file.Name)'. Skipping."
                        }
                    }
                }
            }
            Write-Host "Dependency scan for '$($appFolder.Name)' complete."

            # Resolve all required dependencies using the app-specific catalog
            foreach ($req in $requiredDependencies) {
                $reqName = $req.Name
                $reqMinVersion = [System.Version]$req.MinVersion
                Write-Host "Resolving dependency: $reqName (MinVersion: $reqMinVersion)"

                if ($appSpecificDependencies.ContainsKey($reqName)) {
                    # Find all available packages that meet the minimum version and architecture requirements
                    $candidates = $appSpecificDependencies[$reqName] | Where-Object {
                        $_.Version -ge $reqMinVersion -and
                        $_.Arch -in ($applicableArchitectures + 'neutral')
                    }

                    if ($candidates) {
                        # Group by architecture and find the single latest version for each applicable arch
                        $bestCandidates = $candidates | Group-Object -Property Arch | ForEach-Object {
                            $_.Group | Sort-Object -Property Version -Descending | Select-Object -First 1
                        }
                        
                        foreach($best in $bestCandidates) {
                            Write-Host "  - Found best match: $($best.Path.Replace($basePath, '...'))"
                            $resolvedDependencyPaths.Add($best.Path)
                        }
                    } else {
                        Write-Warning "  - No suitable package found for dependency '$reqName' with MinVersion '$reqMinVersion' for applicable architectures."
                    }
                } else {
                    Write-Warning "  - Dependency '$reqName' not found in this app's dependency folder."
                }
            }
        }
        else {
            Write-Warning "Dependencies are required by manifest, but no 'Dependencies' folder found for '$($appFolder.Name)'."
        }
    }
    else {
        Write-Host "No actual package dependencies listed in manifest for '$($appFolder.Name)'. Proceeding without dependency resolution."
    }

    # Build the DISM command
    $dismParams = @(
        "/Online"
        "/Add-ProvisionedAppxPackage"
        "/PackagePath:`"$($mainPackage.FullName)`""
        "/Region:all"
        # "/StubPackageOption:installfull"
    )

    # Add resolved dependencies, ensuring no duplicates
    $resolvedDependencyPaths.ToArray() | Select-Object -Unique | ForEach-Object {
        $dismParams += "/DependencyPackagePath:`"$_`""
    }

    # Find and add the license file, or skip if not found
    $licenseFile = Get-ChildItem -Path $appFolder.FullName -Filter "*.xml" -File | Select-Object -First 1
    if ($licenseFile) {
        $dismParams += "/LicensePath:`"$($licenseFile.FullName)`""
    } else {
        $dismParams += "/SkipLicense"
    }

    # Execute the DISM command
    $dismCommand = "DISM.exe " + ($dismParams -join " ")
    Write-Host "Constructed DISM command:"
    Write-Output $dismCommand
    
    try {
        Invoke-Expression -Command $dismCommand -ErrorAction Stop
        Write-Host "Successfully installed $($mainPackage.Name)."
    } catch {
        Write-Error "DISM command failed for $($mainPackage.Name). Error: $($_.Exception.Message)"
    }
    Write-Output ""
}

# Final cleanup
Write-Host "Installation process finished."
Remove-TemporaryFiles