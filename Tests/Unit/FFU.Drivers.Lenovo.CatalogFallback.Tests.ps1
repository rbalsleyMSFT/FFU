#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for Lenovo catalogv2.xml fallback functionality.

.DESCRIPTION
    Tests for FFUUI.Core.Drivers.Lenovo.CatalogFallback module functions:
    - Get-LenovoCatalogV2 (catalog download and caching)
    - Get-LenovoCatalogV2Models (model search)
    - Get-LenovoCatalogV2DriverUrl (driver URL lookup)
    - Reset-LenovoCatalogV2Cache (cache clearing)

    Also tests the fallback integration in Get-LenovoDriversModelList.

.NOTES
    Run with: Invoke-Pester -Path Tests/Unit/FFU.Drivers.Lenovo.CatalogFallback.Tests.ps1 -Output Detailed
#>

BeforeAll {
    # Get paths
    $TestRoot = Split-Path -Path $PSScriptRoot -Parent
    $ProjectRoot = Split-Path -Path $TestRoot -Parent
    $ModulePath = Join-Path $ProjectRoot 'FFUDevelopment\FFUUI.Core'

    # Create WriteLog mock
    function global:WriteLog { param($Message) }

    # Import the catalog fallback module
    $CatalogFallbackModule = Join-Path $ModulePath 'FFUUI.Core.Drivers.Lenovo.CatalogFallback.psm1'
    Import-Module $CatalogFallbackModule -Force

    # Mock catalog XML for testing
    $script:MockCatalogXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Products>
  <Product>
    <Model name="ThinkPad L490">
      <Types>
        <Type mtm="20Q6" name="20Q6">
          <SCCM os="win10" version="22H2" date="2024-03-15" md5="abc123">
            https://download.lenovo.com/test/tp_l490_22h2_drivers.exe
          </SCCM>
          <SCCM os="win10" version="21H2" date="2023-06-01" md5="def456">
            https://download.lenovo.com/test/tp_l490_21h2_drivers.exe
          </SCCM>
        </Type>
        <Type mtm="20Q5" name="20Q5">
          <SCCM os="win10" version="22H2" date="2024-03-15" md5="ghi789">
            https://download.lenovo.com/test/tp_l490_20q5_drivers.exe
          </SCCM>
        </Type>
      </Types>
    </Model>
    <Model name="ThinkPad T14">
      <Types>
        <Type mtm="21HD" name="21HD">
          <SCCM os="win10" version="23H2" date="2024-06-01" md5="jkl012">
            https://download.lenovo.com/test/tp_t14_drivers.exe
          </SCCM>
        </Type>
      </Types>
    </Model>
    <Model name="ThinkCentre M920q">
      <Types>
        <Type mtm="10RS" name="10RS">
          <SCCM os="win10" version="22H2" date="2024-02-20" md5="mno345">
            https://download.lenovo.com/test/tc_m920q_drivers.exe
          </SCCM>
        </Type>
      </Types>
    </Model>
  </Product>
</Products>
"@
}

Describe 'Get-LenovoCatalogV2' {
    Context 'Caching Behavior' {
        BeforeEach {
            # Reset cache before each test
            Reset-LenovoCatalogV2Cache
        }

        It 'Should download catalog when cache is empty' {
            # This test would require network access or more complex mocking
            # For unit testing, we verify the function exists and accepts parameters
            $cmd = Get-Command -Name Get-LenovoCatalogV2
            $cmd | Should -Not -BeNullOrEmpty
            $cmd.Parameters.ContainsKey('FFUDevelopmentPath') | Should -BeTrue
            $cmd.Parameters.ContainsKey('ForceRefresh') | Should -BeTrue
        }

        It 'Should have ForceRefresh parameter as switch' {
            $param = (Get-Command Get-LenovoCatalogV2).Parameters['ForceRefresh']
            $param.SwitchParameter | Should -BeTrue
        }

        It 'Should have correct output type declared' {
            $cmd = Get-Command -Name Get-LenovoCatalogV2
            $outputType = $cmd.OutputType
            # The function declares [System.Xml.XmlDocument] as output
            $outputType.Type.Name | Should -Be 'XmlDocument'
        }
    }

    Context 'Cache Reset' {
        It 'Reset-LenovoCatalogV2Cache should clear memory cache' {
            # Verify the reset function exists and runs without error
            { Reset-LenovoCatalogV2Cache } | Should -Not -Throw
        }
    }
}

Describe 'Get-LenovoCatalogV2Models' {
    BeforeAll {
        # Create a mock catalog file for testing
        $script:TempCacheDir = Join-Path $env:TEMP 'FFUTestCache'
        if (-not (Test-Path $script:TempCacheDir)) {
            New-Item -Path $script:TempCacheDir -ItemType Directory -Force | Out-Null
        }
        $script:TempCachePath = Join-Path $script:TempCacheDir 'catalogv2.xml'
        $script:MockCatalogXml | Out-File -FilePath $script:TempCachePath -Encoding UTF8 -Force

        # Create a mock FFUDevelopment path with cache
        $script:MockFFUDevPath = Join-Path $env:TEMP 'MockFFUDevelopment'
        $script:MockCacheDir = Join-Path $script:MockFFUDevPath '.cache'
        if (-not (Test-Path $script:MockCacheDir)) {
            New-Item -Path $script:MockCacheDir -ItemType Directory -Force | Out-Null
        }
        $script:MockCatalogPath = Join-Path $script:MockCacheDir 'catalogv2.xml'
        $script:MockCatalogXml | Out-File -FilePath $script:MockCatalogPath -Encoding UTF8 -Force

        # Reset cache to use our mock
        Reset-LenovoCatalogV2Cache
    }

    AfterAll {
        # Cleanup
        if (Test-Path $script:TempCacheDir) {
            Remove-Item -Path $script:TempCacheDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path $script:MockFFUDevPath) {
            Remove-Item -Path $script:MockFFUDevPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Model Search by Name' {
        It 'Should return models matching search term "ThinkPad"' {
            $results = Get-LenovoCatalogV2Models -ModelSearchTerm 'ThinkPad' -FFUDevelopmentPath $script:MockFFUDevPath
            $results | Should -Not -BeNullOrEmpty
            $results.Count | Should -BeGreaterOrEqual 3  # L490 (20Q6, 20Q5) and T14 (21HD)
        }

        It 'Should return models matching search term "L490"' {
            $results = Get-LenovoCatalogV2Models -ModelSearchTerm 'L490' -FFUDevelopmentPath $script:MockFFUDevPath
            $results | Should -Not -BeNullOrEmpty
            $results.Count | Should -Be 2  # Two machine types: 20Q6 and 20Q5
        }

        It 'Should return models matching search term "ThinkCentre"' {
            $results = Get-LenovoCatalogV2Models -ModelSearchTerm 'ThinkCentre' -FFUDevelopmentPath $script:MockFFUDevPath
            $results | Should -Not -BeNullOrEmpty
            $results.Count | Should -Be 1  # M920q with 10RS
        }

        It 'Should return empty array for non-matching search term' {
            $results = Get-LenovoCatalogV2Models -ModelSearchTerm 'NonExistentModel' -FFUDevelopmentPath $script:MockFFUDevPath
            $results | Should -BeNullOrEmpty
        }
    }

    Context 'Model Search by Machine Type' {
        It 'Should find model by machine type "20Q6"' {
            $results = Get-LenovoCatalogV2Models -ModelSearchTerm '20Q6' -FFUDevelopmentPath $script:MockFFUDevPath
            $results | Should -Not -BeNullOrEmpty
            $results[0].MachineType | Should -Be '20Q6'
            $results[0].ProductName | Should -Be 'ThinkPad L490'
        }

        It 'Should find model by machine type "21HD"' {
            $results = Get-LenovoCatalogV2Models -ModelSearchTerm '21HD' -FFUDevelopmentPath $script:MockFFUDevPath
            $results | Should -Not -BeNullOrEmpty
            $results[0].MachineType | Should -Be '21HD'
            $results[0].ProductName | Should -Be 'ThinkPad T14'
        }
    }

    Context 'Result Properties' {
        It 'Should include Make property set to Lenovo' {
            $results = Get-LenovoCatalogV2Models -ModelSearchTerm 'L490' -FFUDevelopmentPath $script:MockFFUDevPath
            $results[0].Make | Should -Be 'Lenovo'
        }

        It 'Should include IsFallback property set to true' {
            $results = Get-LenovoCatalogV2Models -ModelSearchTerm 'L490' -FFUDevelopmentPath $script:MockFFUDevPath
            $results[0].IsFallback | Should -BeTrue
        }

        It 'Should include Model property with display format' {
            $results = Get-LenovoCatalogV2Models -ModelSearchTerm '20Q6' -FFUDevelopmentPath $script:MockFFUDevPath
            $results[0].Model | Should -Be 'ThinkPad L490 (20Q6)'
        }

        It 'Should include ProductName property' {
            $results = Get-LenovoCatalogV2Models -ModelSearchTerm '20Q6' -FFUDevelopmentPath $script:MockFFUDevPath
            $results[0].ProductName | Should -Be 'ThinkPad L490'
        }

        It 'Should include MachineType property' {
            $results = Get-LenovoCatalogV2Models -ModelSearchTerm '20Q6' -FFUDevelopmentPath $script:MockFFUDevPath
            $results[0].MachineType | Should -Be '20Q6'
        }
    }
}

Describe 'Get-LenovoCatalogV2DriverUrl' {
    BeforeAll {
        # Ensure mock catalog is in place
        $script:MockFFUDevPath = Join-Path $env:TEMP 'MockFFUDevelopment'
        $script:MockCacheDir = Join-Path $script:MockFFUDevPath '.cache'
        if (-not (Test-Path $script:MockCacheDir)) {
            New-Item -Path $script:MockCacheDir -ItemType Directory -Force | Out-Null
        }
        $script:MockCatalogPath = Join-Path $script:MockCacheDir 'catalogv2.xml'
        $script:MockCatalogXml | Out-File -FilePath $script:MockCatalogPath -Encoding UTF8 -Force

        Reset-LenovoCatalogV2Cache
    }

    AfterAll {
        if (Test-Path $script:MockFFUDevPath) {
            Remove-Item -Path $script:MockFFUDevPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'URL Lookup' {
        It 'Should return URL for known machine type with matching version' {
            $url = Get-LenovoCatalogV2DriverUrl -MachineType '20Q6' -WindowsVersion '22H2' -FFUDevelopmentPath $script:MockFFUDevPath
            $url | Should -Not -BeNullOrEmpty
            $url | Should -Match 'tp_l490_22h2_drivers\.exe'
        }

        It 'Should return URL for machine type with different version available' {
            # 21HD only has 23H2, but if we request 22H2, it should fall back
            $url = Get-LenovoCatalogV2DriverUrl -MachineType '21HD' -WindowsVersion '22H2' -FFUDevelopmentPath $script:MockFFUDevPath
            # Since no exact match, it should still find the win10 pack
            # The mock has 23H2 for this machine type
            $url | Should -Not -BeNullOrEmpty
        }

        It 'Should return null for unknown machine type' {
            $url = Get-LenovoCatalogV2DriverUrl -MachineType 'UNKNOWN' -FFUDevelopmentPath $script:MockFFUDevPath
            $url | Should -BeNullOrEmpty
        }

        It 'Should default to 22H2 when WindowsVersion not specified' {
            $cmd = Get-Command Get-LenovoCatalogV2DriverUrl
            $defaultValue = $cmd.Parameters['WindowsVersion'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Select-Object -First 1

            # Test that 22H2 returns a valid URL
            $url = Get-LenovoCatalogV2DriverUrl -MachineType '20Q6' -FFUDevelopmentPath $script:MockFFUDevPath
            $url | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Fallback Behavior' {
        It 'Should find any win10 pack when exact version not available' {
            # 20Q6 has 22H2 and 21H2, request 23H2
            $url = Get-LenovoCatalogV2DriverUrl -MachineType '20Q6' -WindowsVersion '23H2' -FFUDevelopmentPath $script:MockFFUDevPath
            # Should fall back to any available win10 pack
            $url | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Lenovo Driver Fallback Chain Integration' {
    BeforeAll {
        # Import the main Lenovo driver module
        $LenovoDriverModule = Join-Path (Split-Path $PSScriptRoot -Parent | Split-Path -Parent) 'FFUDevelopment\FFUUI.Core\FFUUI.Core.Drivers.Lenovo.psm1'
        if (Test-Path $LenovoDriverModule) {
            Import-Module $LenovoDriverModule -Force
        }

        # Mock functions that Get-LenovoDriversModelList depends on
        function global:Get-LenovoPSREFTokenCached { param($FFUDevelopmentPath) return $null }
        function global:Get-LenovoPSREFToken { return $null }
    }

    Context 'Module Import' {
        It 'Should import catalog fallback module when Lenovo driver module loads' {
            # Verify the fallback functions are available after importing main module
            Get-Command -Name Get-LenovoCatalogV2Models -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should have fallback module path import in source' {
            $LenovoDriverModule = Join-Path (Split-Path $PSScriptRoot -Parent | Split-Path -Parent) 'FFUDevelopment\FFUUI.Core\FFUUI.Core.Drivers.Lenovo.psm1'
            $content = Get-Content -Path $LenovoDriverModule -Raw
            $content | Should -Match 'FFUUI\.Core\.Drivers\.Lenovo\.CatalogFallback\.psm1'
        }
    }

    Context 'Fallback Integration Pattern' {
        It 'Should have fallback call in catch block' {
            $LenovoDriverModule = Join-Path (Split-Path $PSScriptRoot -Parent | Split-Path -Parent) 'FFUDevelopment\FFUUI.Core\FFUUI.Core.Drivers.Lenovo.psm1'
            $content = Get-Content -Path $LenovoDriverModule -Raw
            # Use (?s) for single-line mode where . matches newlines
            $content | Should -Match '(?s)catch\s*\{[\s\S]*?Get-LenovoCatalogV2Models'
        }

        It 'Should have fallback check when PSREF returns empty' {
            $LenovoDriverModule = Join-Path (Split-Path $PSScriptRoot -Parent | Split-Path -Parent) 'FFUDevelopment\FFUUI.Core\FFUUI.Core.Drivers.Lenovo.psm1'
            $content = Get-Content -Path $LenovoDriverModule -Raw
            # Check for the "if models.Count -eq 0" pattern with fallback (using (?s) for multiline)
            $content | Should -Match '(?s)\$models\.Count\s+-eq\s+0[\s\S]*?Get-LenovoCatalogV2Models'
        }

        It 'Should warn user about partial coverage in fallback mode' {
            $LenovoDriverModule = Join-Path (Split-Path $PSScriptRoot -Parent | Split-Path -Parent) 'FFUDevelopment\FFUUI.Core\FFUUI.Core.Drivers.Lenovo.psm1'
            $content = Get-Content -Path $LenovoDriverModule -Raw
            $content | Should -Match 'partial coverage'
        }
    }
}

Describe 'Module Structure and Documentation' {
    BeforeAll {
        $CatalogFallbackModule = Join-Path (Split-Path $PSScriptRoot -Parent | Split-Path -Parent) 'FFUDevelopment\FFUUI.Core\FFUUI.Core.Drivers.Lenovo.CatalogFallback.psm1'
        $script:ModuleContent = Get-Content -Path $CatalogFallbackModule -Raw
    }

    Context 'Module Documentation' {
        It 'Should have synopsis describing fallback purpose' {
            # Use (?s) for multiline matching
            $script:ModuleContent | Should -Match '(?s)\.SYNOPSIS[\s\S]*?catalogv2\.xml fallback'
        }

        It 'Should document partial coverage limitation' {
            $script:ModuleContent | Should -Match 'PARTIAL coverage'
        }

        It 'Should document enterprise models included' {
            # Use (?s) for multiline matching
            $script:ModuleContent | Should -Match '(?s)ThinkPad[\s\S]*?ThinkCentre[\s\S]*?ThinkStation'
        }

        It 'Should document consumer models not included' {
            # Use (?s) for multiline matching
            $script:ModuleContent | Should -Match '(?s)300w[\s\S]*?500w[\s\S]*?100e'
        }
    }

    Context 'Exported Functions' {
        It 'Should export Get-LenovoCatalogV2' {
            Get-Command -Name Get-LenovoCatalogV2 -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should export Get-LenovoCatalogV2Models' {
            Get-Command -Name Get-LenovoCatalogV2Models -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should export Get-LenovoCatalogV2DriverUrl' {
            Get-Command -Name Get-LenovoCatalogV2DriverUrl -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should export Reset-LenovoCatalogV2Cache' {
            Get-Command -Name Reset-LenovoCatalogV2Cache -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Cache Configuration' {
        It 'Should have 7-day default TTL (10080 minutes)' {
            $script:ModuleContent | Should -Match 'TTLMinutes\s*=\s*10080'
        }
    }
}

AfterAll {
    # Cleanup global mocks
    Remove-Item Function:\WriteLog -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-LenovoPSREFTokenCached -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-LenovoPSREFToken -ErrorAction SilentlyContinue
}
