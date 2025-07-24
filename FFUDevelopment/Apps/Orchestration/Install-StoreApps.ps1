$basePath = "D:\MSStore"
# Check if the base path exists
Write-Host "Installing Store Apps: Checking for $basePath"
if (-not (Test-Path -Path $basePath)) {
    Write-Host "Installing Store Apps: $basePath does not exist."
    exit
}
Write-Host "Installing Store Apps: $basePath exists, installing apps."

# Process each app folder in the base path
foreach ($appFolder in Get-ChildItem -Path $basePath -Directory) {
    $folderPath = $appFolder.FullName
    $dependenciesFolder = Join-Path -Path $folderPath -ChildPath "Dependencies"
    
    # Find main package - exclude Dependencies folder items and xml/yaml files
    $mainPackage = Get-ChildItem -Path $folderPath -File | 
                  Where-Object { 
                      $_.DirectoryName -ne $dependenciesFolder -and 
                      $_.Extension -ne ".xml" -and 
                      $_.Extension -ne ".yaml" 
                  } | Select-Object -First 1
    
    if ($mainPackage) {
        # Build DISM command with main package
        $dismParams = @(
            "/Online"
            "/Add-ProvisionedAppxPackage"
            "/PackagePath:`"$($mainPackage.FullName)`""
            "/Region:all"
            "/StubPackageOption:installfull"
        )
        
        # Add dependency packages if they exist
        if (Test-Path -Path $dependenciesFolder) {
            $dependencies = Get-ChildItem -Path $dependenciesFolder -File
            foreach ($dependency in $dependencies) {
                $dismParams += "/DependencyPackagePath:`"$($dependency.FullName)`""
            }
        }
        
        # Look for license file and add appropriate parameter
        $licenseFile = Get-ChildItem -Path $folderPath -Filter "*.xml" -File | Select-Object -First 1
        if ($licenseFile) {
            $dismParams += "/LicensePath:`"$($licenseFile.FullName)`""
        } else {
            $dismParams += "/SkipLicense"
        }
        
        # Construct final command
        $dismCommand = "DISM " + ($dismParams -join " ")
        
        # Output and execute the command
        Write-Output $dismCommand
        Invoke-Expression -Command $dismCommand
        Write-Output ""
    }
}