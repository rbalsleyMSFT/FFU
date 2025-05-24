<#
.SYNOPSIS
    This script uses the variables from the AppsScriptVariables hashtable passed to BuildFFUVM.ps1 to run application deployment tasks.

.DESCRIPTION
    By defining the variables in the AppsScriptVariables hashtable, you can customize the application deployment tasks that are run by this script.
    The BuildFFUVM.ps1 script will export the AppsScriptVariables hashtable to a JSON file in the Orchestration folder.
    Include your own custom script here if you want to run it as part of the application deployment tasks.
    Alternatively, you can pass the AppsScriptVariables hashtable directly to this script.
#>

param (
    [hashtable]$AppsScriptVariables
)

# Try to read from the JSON file if it exists and AppsScriptVariables is not provided
$appsScriptVarsJsonPath = Join-Path -Path $PSScriptRoot -ChildPath "AppsScriptVariables.json"
if ((-not $AppsScriptVariables -or $AppsScriptVariables.Count -eq 0) -and (Test-Path -Path $appsScriptVarsJsonPath)) {
    try {
        $jsonContent = Get-Content -Path $appsScriptVarsJsonPath -Raw -ErrorAction Stop
        $jsonObject = $jsonContent | ConvertFrom-Json -ErrorAction Stop
        
        # Convert PSCustomObject to hashtable
        $AppsScriptVariables = @{}
        foreach ($prop in $jsonObject.PSObject.Properties) {
            $AppsScriptVariables[$prop.Name] = $prop.Value
        }
        
        Write-Host "Successfully loaded AppsScriptVariables from $appsScriptVarsJsonPath"
    }
    catch {
        Write-Error "Failed to load AppsScriptVariables from JSON file: $_"
    }
}
else {
    Write-Host "AppsScriptVariables provided directly, skipping JSON file load."
}

# Example of how to use the AppsScriptVariables hashtable to control script execution

# Example: Check if a variable named 'foo' is set to string 'true' and run a script accordingly
# if ($AppsScriptVariables['foo'] -eq 'true') {
#     Write-Host "Foo would have installed"
# }
# else {
#     Write-Host "Foo would not have installed"
# }

# Example: Check if a variable named 'foo' is set to boolean $true and run a script accordingly
# if ($AppsScriptVariables['foo'] -eq $true) {
#     Write-Host "Foo would have been installed"
# }
# else {
#     Write-Host "Foo would not have installed"
# }

# Your code below here

Write-Host 'Invoke-AppsScript.ps1 finished'