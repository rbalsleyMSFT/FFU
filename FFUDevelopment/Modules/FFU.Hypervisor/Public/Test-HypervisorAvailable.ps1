<#
.SYNOPSIS
    Tests if a specific hypervisor is available on the system

.DESCRIPTION
    Checks whether the specified hypervisor type is installed and functional
    on the current system. Returns availability status and any issues found.

.PARAMETER Type
    The type of hypervisor to check:
    - 'HyperV': Microsoft Hyper-V
    - 'VMware': VMware Workstation Pro
    - 'Any': Check if any supported hypervisor is available

.PARAMETER Detailed
    If specified, returns a detailed hashtable with availability information
    instead of just a boolean.

.EXAMPLE
    Test-HypervisorAvailable -Type 'HyperV'
    # Returns: $true or $false

.EXAMPLE
    Test-HypervisorAvailable -Type 'HyperV' -Detailed
    # Returns: @{
    #     IsAvailable = $true
    #     ProviderName = 'HyperV'
    #     ProviderVersion = '10.0.22631'
    #     Issues = @()
    #     Details = @{ ServiceStatus = 'Running'; ... }
    # }

.OUTPUTS
    System.Boolean or System.Collections.Hashtable (with -Detailed)

.NOTES
    Module: FFU.Hypervisor
    Version: 1.0.0
#>
function Test-HypervisorAvailable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet('HyperV', 'VMware', 'Any')]
        [string]$Type = 'Any',

        [Parameter(Mandatory = $false)]
        [switch]$Detailed
    )

    process {
        $providers = @()

        switch ($Type) {
            'HyperV' {
                $providers = @([HyperVProvider]::new())
            }
            'VMware' {
                # VMware provider will be implemented in Milestone 2
                if ($Detailed) {
                    return @{
                        IsAvailable = $false
                        ProviderName = 'VMware'
                        ProviderVersion = 'N/A'
                        Issues = @('VMware provider is not yet implemented')
                        Details = @{}
                    }
                }
                return $false
            }
            'Any' {
                $providers = @(
                    [HyperVProvider]::new()
                    # VMware would be added here when implemented
                )
            }
        }

        foreach ($provider in $providers) {
            if ($Detailed) {
                $details = $provider.GetAvailabilityDetails()
                if ($details.IsAvailable) {
                    return $details
                }
            }
            else {
                if ($provider.TestAvailable()) {
                    return $true
                }
            }
        }

        if ($Detailed) {
            # Return details for the first provider if none available
            if ($providers.Count -gt 0) {
                return $providers[0].GetAvailabilityDetails()
            }
            return @{
                IsAvailable = $false
                ProviderName = 'None'
                ProviderVersion = 'N/A'
                Issues = @('No supported hypervisor found')
                Details = @{}
            }
        }

        return $false
    }
}
