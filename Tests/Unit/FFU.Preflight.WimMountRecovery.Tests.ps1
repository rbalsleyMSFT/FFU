#Requires -Version 7.0
#Requires -Module @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

<#
.SYNOPSIS
    Pester tests for enhanced WimMount failure scenario detection in FFU.Preflight module.

.DESCRIPTION
    Tests the new WimMount helper functions:
    - Test-WimMountDriverIntegrity
    - Test-WimMountAltitudeConflict
    - Test-WimMountSecuritySoftwareBlocking
    - Test-FFUWimMount enhanced detection integration

.NOTES
    Part of Phase 10 (Dependency Resilience) Plan 10-03
#>

BeforeAll {
    # Add module path and import
    $ModulePath = Join-Path $PSScriptRoot '../../FFUDevelopment/Modules'
    if ($env:PSModulePath -notlike "*$ModulePath*") {
        $env:PSModulePath = "$ModulePath;$env:PSModulePath"
    }
    Import-Module FFU.Preflight -Force -ErrorAction Stop
}

Describe 'Test-WimMountDriverIntegrity' -Tag 'WimMountRecovery', 'DriverIntegrity' {

    Context 'When driver exists and is valid' {
        It 'Returns IsCorrupted = $false with hash and size' {
            InModuleScope FFU.Preflight {
                Mock Test-Path { $true }
                Mock Get-Item {
                    [PSCustomObject]@{
                        Length = 25000
                        VersionInfo = [PSCustomObject]@{ FileVersion = '10.0.22621.1' }
                    }
                }
                Mock Get-FileHash {
                    [PSCustomObject]@{ Hash = 'ABC123DEF456' }
                }

                $result = Test-WimMountDriverIntegrity

                $result.IsCorrupted | Should -Be $false
                $result.FileHash | Should -Be 'ABC123DEF456'
                $result.FileSize | Should -Be 25000
                $result.Reason | Should -Match 'not in known-good list'
            }
        }

        It 'Returns verified status for known good hash' {
            InModuleScope FFU.Preflight {
                Mock Test-Path { $true }
                Mock Get-Item {
                    [PSCustomObject]@{ Length = 35000 }
                }
                Mock Get-FileHash {
                    [PSCustomObject]@{ Hash = 'F3A9B8E2D7C6A5B4E3F2D1C0B9A8E7F6D5C4B3A2E1F0D9C8B7A6E5F4D3C2B1A0' }
                }

                $result = Test-WimMountDriverIntegrity

                $result.IsCorrupted | Should -Be $false
                $result.Reason | Should -Match 'Win11-23H2'
            }
        }
    }

    Context 'When driver is suspiciously small' {
        It 'Returns IsCorrupted = $true with size warning' {
            InModuleScope FFU.Preflight {
                Mock Test-Path { $true }
                Mock Get-Item {
                    [PSCustomObject]@{ Length = 500 }
                }

                $result = Test-WimMountDriverIntegrity

                $result.IsCorrupted | Should -Be $true
                $result.Reason | Should -Match 'suspiciously small'
                $result.FileSize | Should -Be 500
            }
        }
    }

    Context 'When driver file is missing' {
        It 'Returns IsCorrupted = $true with missing reason' {
            InModuleScope FFU.Preflight {
                Mock Test-Path { $false }

                $result = Test-WimMountDriverIntegrity

                $result.IsCorrupted | Should -Be $true
                $result.Reason | Should -Match 'missing'
                $result.FileHash | Should -BeNullOrEmpty
            }
        }
    }

    Context 'When hash computation fails' {
        It 'Returns IsCorrupted = $true with error reason' {
            InModuleScope FFU.Preflight {
                Mock Test-Path { $true }
                Mock Get-Item {
                    [PSCustomObject]@{ Length = 30000 }
                }
                Mock Get-FileHash { throw 'Access denied' }

                $result = Test-WimMountDriverIntegrity

                $result.IsCorrupted | Should -Be $true
                $result.Reason | Should -Match 'Failed to verify'
            }
        }
    }
}

Describe 'Test-WimMountAltitudeConflict' -Tag 'WimMountRecovery', 'AltitudeConflict' {

    Context 'When no conflict exists and WimMount is loaded' {
        It 'Returns HasConflict = $false with WimMount loaded' {
            InModuleScope FFU.Preflight {
                Mock fltmc {
                    @(
                        'Filter Name                     Num Instances    Altitude    Frame',
                        '-----------                     -------------    --------    -----',
                        'WimMount                        2                180700      0',
                        'WdFilter                        5                328010      0'
                    )
                }
                Mock Test-Path { $false }  # No registry to check

                $result = Test-WimMountAltitudeConflict

                $result.HasConflict | Should -Be $false
                $result.WimMountLoaded | Should -Be $true
                $result.WimMountAltitude | Should -Be '180700'
                $result.ConflictingFilters | Should -HaveCount 0
            }
        }
    }

    Context 'When another filter uses altitude 180700' {
        It 'Returns HasConflict = $true with conflicting filter details' {
            InModuleScope FFU.Preflight {
                Mock fltmc {
                    @(
                        'Filter Name                     Num Instances    Altitude    Frame',
                        '-----------                     -------------    --------    -----',
                        'SomeOtherFilter                 1                180700      0',
                        'WdFilter                        5                328010      0'
                    )
                }
                Mock Test-Path { $false }

                $result = Test-WimMountAltitudeConflict

                $result.HasConflict | Should -Be $true
                $result.ConflictingFilters | Should -HaveCount 1
                $result.ConflictingFilters[0].Name | Should -Be 'SomeOtherFilter'
                $result.ConflictingFilters[0].Altitude | Should -Be '180700'
            }
        }
    }

    Context 'When registry has wrong altitude' {
        It 'Returns HasConflict = $true with registry misconfiguration' {
            InModuleScope FFU.Preflight {
                Mock fltmc {
                    @(
                        'Filter Name                     Num Instances    Altitude    Frame',
                        '-----------                     -------------    --------    -----',
                        'WdFilter                        5                328010      0'
                    )
                }
                Mock Test-Path { $true }
                Mock Get-ItemProperty {
                    [PSCustomObject]@{ Altitude = '999999' }
                }

                $result = Test-WimMountAltitudeConflict

                $result.HasConflict | Should -Be $true
                $result.ConflictingFilters | Should -HaveCount 1
                $result.ConflictingFilters[0].Name | Should -Match 'registry misconfigured'
                $result.ConflictingFilters[0].Note | Should -Be 'Expected 180700'
            }
        }
    }

    Context 'When WimMount not loaded and no conflicts' {
        It 'Returns HasConflict = $false with WimMountLoaded = $false' {
            InModuleScope FFU.Preflight {
                Mock fltmc {
                    @(
                        'Filter Name                     Num Instances    Altitude    Frame',
                        '-----------                     -------------    --------    -----',
                        'WdFilter                        5                328010      0'
                    )
                }
                Mock Test-Path { $false }

                $result = Test-WimMountAltitudeConflict

                $result.HasConflict | Should -Be $false
                $result.WimMountLoaded | Should -Be $false
            }
        }
    }
}

Describe 'Test-WimMountSecuritySoftwareBlocking' -Tag 'WimMountRecovery', 'SecuritySoftware' {

    Context 'When no security software detected' {
        It 'Returns BlockingLikely = $false with empty DetectedSoftware' {
            InModuleScope FFU.Preflight {
                Mock Get-Service { $null }
                Mock fltmc {
                    @(
                        'Filter Name                     Num Instances    Altitude    Frame',
                        '-----------                     -------------    --------    -----',
                        'WimMount                        2                180700      0'
                    )
                }

                $result = Test-WimMountSecuritySoftwareBlocking

                $result.BlockingLikely | Should -Be $false
                $result.DetectedSoftware | Should -HaveCount 0
                $result.Recommendations | Should -HaveCount 0
            }
        }
    }

    Context 'When CrowdStrike service is running' {
        It 'Returns BlockingLikely = $true with CrowdStrike details' {
            InModuleScope FFU.Preflight {
                Mock Get-Service {
                    param($Name)
                    if ($Name -eq 'CSFalconService') {
                        [PSCustomObject]@{ Status = 'Running' }
                    }
                    else {
                        $null
                    }
                }
                Mock fltmc {
                    @(
                        'Filter Name                     Num Instances    Altitude    Frame',
                        '-----------                     -------------    --------    -----',
                        'CSAgent                         5                385201      0'
                    )
                }

                $result = Test-WimMountSecuritySoftwareBlocking

                $result.BlockingLikely | Should -Be $true
                $result.DetectedSoftware.Count | Should -BeGreaterThan 0

                # Should detect both service and filter
                $serviceMatch = $result.DetectedSoftware | Where-Object { $_.DisplayName -eq 'CrowdStrike Falcon' }
                $filterMatch = $result.DetectedSoftware | Where-Object { $_.FilterName -eq 'CSAgent' }

                $serviceMatch | Should -Not -BeNullOrEmpty
                $filterMatch | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'When Windows Defender filter detected' {
        It 'Returns BlockingLikely = $true with WdFilter details' {
            InModuleScope FFU.Preflight {
                Mock Get-Service { $null }
                Mock fltmc {
                    @(
                        'Filter Name                     Num Instances    Altitude    Frame',
                        '-----------                     -------------    --------    -----',
                        'WdFilter                        5                328010      0',
                        'WimMount                        2                180700      0'
                    )
                }

                $result = Test-WimMountSecuritySoftwareBlocking

                $result.BlockingLikely | Should -Be $true
                $filterMatch = $result.DetectedSoftware | Where-Object { $_.FilterName -eq 'WdFilter' }
                $filterMatch | Should -Not -BeNullOrEmpty
                $result.Recommendations | Should -HaveCount 3
                $result.Recommendations[1] | Should -Match 'whitelist'
            }
        }
    }

    Context 'When multiple security products detected' {
        It 'Returns all detected products in recommendations' {
            InModuleScope FFU.Preflight {
                Mock Get-Service {
                    param($Name)
                    switch ($Name) {
                        'SentinelAgent' { [PSCustomObject]@{ Status = 'Running' } }
                        'CbDefense' { [PSCustomObject]@{ Status = 'Running' } }
                        default { $null }
                    }
                }
                Mock fltmc { @() }

                $result = Test-WimMountSecuritySoftwareBlocking

                $result.BlockingLikely | Should -Be $true
                $result.DetectedSoftware.Count | Should -BeGreaterThan 1
                $result.Recommendations[0] | Should -Match 'SentinelOne|Carbon Black'
            }
        }
    }
}

Describe 'Test-FFUWimMount Enhanced Detection Integration' -Tag 'WimMountRecovery', 'Integration' {

    Context 'When WimMount is healthy' {
        It 'Returns Passed status with minimal diagnostics' {
            InModuleScope FFU.Preflight {
                Mock fltmc {
                    @(
                        'Filter Name                     Num Instances    Altitude    Frame',
                        '-----------                     -------------    --------    -----',
                        'WimMount                        2                180700      0'
                    )
                }

                $result = Test-FFUWimMount

                $result.Status | Should -Be 'Passed'
                $result.Message | Should -Match 'loaded and functional'
            }
        }
    }

    Context 'When WimMount not loaded with no remediation' {
        It 'Returns Failed status with enhanced diagnostic details' {
            InModuleScope FFU.Preflight {
                # WimMount not in filter list
                Mock fltmc {
                    param([string]$Command)
                    @(
                        'Filter Name                     Num Instances    Altitude    Frame',
                        '-----------                     -------------    --------    -----',
                        'WdFilter                        5                328010      0'
                    )
                }

                # Driver exists but not loaded
                Mock Test-Path { param($Path) $Path -notlike '*HKLM*' -and $Path -like '*wimmount*' }
                Mock Get-Item {
                    [PSCustomObject]@{
                        Length = 25000
                        VersionInfo = [PSCustomObject]@{ FileVersion = '10.0.22621.1' }
                    }
                }
                Mock Get-FileHash {
                    [PSCustomObject]@{ Hash = 'TESTHASH123' }
                }
                Mock Get-Service { $null }
                Mock sc.exe { 'SERVICE_NAME: wimmount' }
                Mock Set-ItemProperty {}
                Mock New-Item {}
                Mock Start-Sleep {}

                $result = Test-FFUWimMount -AttemptRemediation:$false

                $result.Status | Should -Be 'Failed'
                $result.Details.WimMountFilterLoaded | Should -Be $false
                $result.Details.WimMountDriverHash | Should -Be 'TESTHASH123'
                $result.Details.WimMountDriverSize | Should -Be 25000
                $result.Details.SecurityBlockingLikely | Should -Be $true  # WdFilter detected
            }
        }
    }

    Context 'When altitude conflict detected' {
        It 'Includes altitude conflict in details' {
            InModuleScope FFU.Preflight {
                # Another filter at WimMount's altitude
                Mock fltmc {
                    @(
                        'Filter Name                     Num Instances    Altitude    Frame',
                        '-----------                     -------------    --------    -----',
                        'AcronisFilter                   1                180700      0'
                    )
                }

                Mock Test-Path { param($Path) $Path -notlike '*HKLM*' }
                Mock Get-Item { [PSCustomObject]@{ Length = 30000 } }
                Mock Get-FileHash { [PSCustomObject]@{ Hash = 'HASH' } }
                Mock Get-Service { $null }
                Mock sc.exe { '' }

                $result = Test-FFUWimMount -AttemptRemediation:$false

                $result.Status | Should -Be 'Failed'
                $result.Details.AltitudeConflict | Should -Be $true
                $result.Details.ConflictingFilters | Should -HaveCount 1
                $result.Details.ConflictingFilters[0].Name | Should -Be 'AcronisFilter'
            }
        }
    }

    Context 'When driver integrity issue detected' {
        It 'Includes driver integrity issue in details' {
            InModuleScope FFU.Preflight {
                Mock fltmc { @() }

                # Suspiciously small driver
                Mock Test-Path { param($Path) $Path -notlike '*HKLM*' -and $Path -like '*wimmount*' }
                Mock Get-Item { [PSCustomObject]@{ Length = 100 } }
                Mock Get-Service { $null }
                Mock sc.exe { '' }

                $result = Test-FFUWimMount -AttemptRemediation:$false

                $result.Status | Should -Be 'Failed'
                $result.Details.DriverIntegrityIssue | Should -Match 'suspiciously small'
            }
        }
    }
}

Describe 'Test-FFUWimMount Remediation Messages' -Tag 'WimMountRecovery', 'Remediation' {

    It 'Includes driver integrity remediation when driver issue detected' {
        InModuleScope FFU.Preflight {
            Mock fltmc { @() }
            Mock Test-Path { $false }  # Driver missing
            Mock Get-Service { $null }
            Mock sc.exe { '' }

            $result = Test-FFUWimMount -AttemptRemediation:$false

            $result.Remediation | Should -Match 'sfc /scannow'
            $result.Remediation | Should -Match 'DISM /Online /Cleanup-Image'
        }
    }

    It 'Includes altitude conflict remediation when conflict detected' {
        InModuleScope FFU.Preflight {
            Mock fltmc {
                @(
                    'Filter Name                     Num Instances    Altitude    Frame',
                    'ConflictFilter                  1                180700      0'
                )
            }
            Mock Test-Path { param($Path) $Path -notlike '*HKLM*' }
            Mock Get-Item { [PSCustomObject]@{ Length = 30000 } }
            Mock Get-FileHash { [PSCustomObject]@{ Hash = 'HASH' } }
            Mock Get-Service { $null }
            Mock sc.exe { '' }

            $result = Test-FFUWimMount -AttemptRemediation:$false

            $result.Remediation | Should -Match 'altitude conflict'
            $result.Remediation | Should -Match 'Acronis|Ghost'
        }
    }

    It 'Includes security software remediation when EDR detected' {
        InModuleScope FFU.Preflight {
            Mock fltmc {
                @(
                    'Filter Name                     Num Instances    Altitude    Frame',
                    'CSAgent                         5                385201      0'
                )
            }
            Mock Test-Path { param($Path) $Path -notlike '*HKLM*' }
            Mock Get-Item { [PSCustomObject]@{ Length = 30000 } }
            Mock Get-FileHash { [PSCustomObject]@{ Hash = 'HASH' } }
            Mock Get-Service { $null }
            Mock sc.exe { '' }

            $result = Test-FFUWimMount -AttemptRemediation:$false

            $result.Remediation | Should -Match 'security software'
            $result.Remediation | Should -Match 'whitelist'
        }
    }
}

AfterAll {
    # Cleanup
    Remove-Module FFU.Preflight -ErrorAction SilentlyContinue
}
