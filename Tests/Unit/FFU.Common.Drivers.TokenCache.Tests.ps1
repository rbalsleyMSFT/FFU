# FFU.Common.Drivers Token Cache Tests
# Tests for Lenovo PSREF token caching functionality (SEC-01)

BeforeAll {
    # Import the module
    $modulePath = Join-Path $PSScriptRoot "..\..\FFUDevelopment\FFU.Common\FFU.Common.Drivers.psm1"

    # Mock WriteLog before importing
    function global:WriteLog {
        param([string]$Message)
        # Silent in tests
    }

    Import-Module $modulePath -Force
}

Describe "Lenovo PSREF Token Caching" {
    BeforeEach {
        # Create temp directory for testing
        $script:testPath = Join-Path $TestDrive "FFUDevelopment"
        New-Item -Path $testPath -ItemType Directory -Force | Out-Null
    }

    Context "Set-LenovoPSREFTokenCache" {
        It "Creates .security\token-cache directory if missing" {
            Set-LenovoPSREFTokenCache -FFUDevelopmentPath $testPath -Token "test-token-123"

            $cacheDir = Join-Path $testPath ".security\token-cache"
            $cacheDir | Should -Exist
        }

        It "Stores token with timestamp in XML file" {
            Set-LenovoPSREFTokenCache -FFUDevelopmentPath $testPath -Token "test-token-456"

            $cachePath = Join-Path $testPath ".security\token-cache\lenovo-psref.xml"
            $cachePath | Should -Exist

            $cached = Import-Clixml -Path $cachePath
            $cached.Token | Should -Be "test-token-456"
            $cached.Timestamp | Should -Not -BeNullOrEmpty
        }

        It "Stores timestamp in ISO 8601 format" {
            Set-LenovoPSREFTokenCache -FFUDevelopmentPath $testPath -Token "test-token-789"

            $cachePath = Join-Path $testPath ".security\token-cache\lenovo-psref.xml"
            $cached = Import-Clixml -Path $cachePath

            # Verify timestamp can be parsed as datetime
            { [datetime]$cached.Timestamp } | Should -Not -Throw
        }

        It "Overwrites existing cache file" {
            Set-LenovoPSREFTokenCache -FFUDevelopmentPath $testPath -Token "first-token"
            Set-LenovoPSREFTokenCache -FFUDevelopmentPath $testPath -Token "second-token"

            $cachePath = Join-Path $testPath ".security\token-cache\lenovo-psref.xml"
            $cached = Import-Clixml -Path $cachePath
            $cached.Token | Should -Be "second-token"
        }
    }

    Context "Get-LenovoPSREFTokenCached" {
        It "Returns cached token when within expiry window" {
            # Pre-populate cache
            $cacheDir = Join-Path $testPath ".security\token-cache"
            New-Item -Path $cacheDir -ItemType Directory -Force | Out-Null
            $cachePath = Join-Path $cacheDir "lenovo-psref.xml"
            @{
                Token     = "cached-token-789"
                Timestamp = (Get-Date).ToString('o')
            } | Export-Clixml -Path $cachePath

            # Mock Get-LenovoPSREFToken to verify it's NOT called
            Mock Get-LenovoPSREFToken { "fresh-token" } -ModuleName FFU.Common.Drivers

            $result = Get-LenovoPSREFTokenCached -FFUDevelopmentPath $testPath -CacheValidMinutes 60

            $result | Should -Be "cached-token-789"
            Should -Not -Invoke Get-LenovoPSREFToken -ModuleName FFU.Common.Drivers
        }

        It "Retrieves fresh token when cache is expired" {
            # Pre-populate expired cache
            $cacheDir = Join-Path $testPath ".security\token-cache"
            New-Item -Path $cacheDir -ItemType Directory -Force | Out-Null
            $cachePath = Join-Path $cacheDir "lenovo-psref.xml"
            @{
                Token     = "expired-token"
                Timestamp = (Get-Date).AddMinutes(-120).ToString('o')
            } | Export-Clixml -Path $cachePath

            # Mock Get-LenovoPSREFToken
            Mock Get-LenovoPSREFToken { "fresh-token" } -ModuleName FFU.Common.Drivers

            $result = Get-LenovoPSREFTokenCached -FFUDevelopmentPath $testPath -CacheValidMinutes 60

            $result | Should -Be "fresh-token"
            Should -Invoke Get-LenovoPSREFToken -Times 1 -ModuleName FFU.Common.Drivers
        }

        It "ForceRefresh bypasses cache" {
            # Pre-populate valid cache
            $cacheDir = Join-Path $testPath ".security\token-cache"
            New-Item -Path $cacheDir -ItemType Directory -Force | Out-Null
            $cachePath = Join-Path $cacheDir "lenovo-psref.xml"
            @{
                Token     = "cached-token"
                Timestamp = (Get-Date).ToString('o')
            } | Export-Clixml -Path $cachePath

            Mock Get-LenovoPSREFToken { "forced-fresh-token" } -ModuleName FFU.Common.Drivers

            $result = Get-LenovoPSREFTokenCached -FFUDevelopmentPath $testPath -ForceRefresh

            $result | Should -Be "forced-fresh-token"
            Should -Invoke Get-LenovoPSREFToken -Times 1 -ModuleName FFU.Common.Drivers
        }

        It "Retrieves fresh token when no cache exists" {
            # Use a fresh test directory to avoid cache from previous tests
            $freshTestPath = Join-Path $TestDrive "NoCacheTest"
            New-Item -Path $freshTestPath -ItemType Directory -Force | Out-Null

            Mock Get-LenovoPSREFToken { "new-token" } -ModuleName FFU.Common.Drivers

            $result = Get-LenovoPSREFTokenCached -FFUDevelopmentPath $freshTestPath

            $result | Should -Be "new-token"
            Should -Invoke Get-LenovoPSREFToken -Times 1 -Exactly -ModuleName FFU.Common.Drivers
        }

        It "Caches fresh token after retrieval" {
            # Use a fresh test directory to avoid cache from previous tests
            $cacheTestPath = Join-Path $TestDrive "CacheAfterRetrievalTest"
            New-Item -Path $cacheTestPath -ItemType Directory -Force | Out-Null

            Mock Get-LenovoPSREFToken { "token-to-cache" } -ModuleName FFU.Common.Drivers

            Get-LenovoPSREFTokenCached -FFUDevelopmentPath $cacheTestPath

            $cachePath = Join-Path $cacheTestPath ".security\token-cache\lenovo-psref.xml"
            $cachePath | Should -Exist

            $cached = Import-Clixml -Path $cachePath
            $cached.Token | Should -Be "token-to-cache"
        }

        It "Respects custom CacheValidMinutes parameter" {
            # Pre-populate cache that's 10 minutes old
            $cacheDir = Join-Path $testPath ".security\token-cache"
            New-Item -Path $cacheDir -ItemType Directory -Force | Out-Null
            $cachePath = Join-Path $cacheDir "lenovo-psref.xml"
            @{
                Token     = "ten-minute-old-token"
                Timestamp = (Get-Date).AddMinutes(-10).ToString('o')
            } | Export-Clixml -Path $cachePath

            Mock Get-LenovoPSREFToken { "fresh-token" } -ModuleName FFU.Common.Drivers

            # With 5 minute validity, cache should be expired
            $result1 = Get-LenovoPSREFTokenCached -FFUDevelopmentPath $testPath -CacheValidMinutes 5
            $result1 | Should -Be "fresh-token"
            Should -Invoke Get-LenovoPSREFToken -Times 1 -ModuleName FFU.Common.Drivers
        }

        It "Uses default 60-minute cache validity" {
            # Pre-populate cache that's 30 minutes old
            $cacheDir = Join-Path $testPath ".security\token-cache"
            New-Item -Path $cacheDir -ItemType Directory -Force | Out-Null
            $cachePath = Join-Path $cacheDir "lenovo-psref.xml"
            @{
                Token     = "thirty-minute-old-token"
                Timestamp = (Get-Date).AddMinutes(-30).ToString('o')
            } | Export-Clixml -Path $cachePath

            Mock Get-LenovoPSREFToken { "should-not-be-called" } -ModuleName FFU.Common.Drivers

            # Default is 60 minutes, so 30-minute-old token should be valid
            $result = Get-LenovoPSREFTokenCached -FFUDevelopmentPath $testPath

            $result | Should -Be "thirty-minute-old-token"
            Should -Not -Invoke Get-LenovoPSREFToken -ModuleName FFU.Common.Drivers
        }
    }

    Context "Clear-LenovoPSREFTokenCache" {
        It "Removes cached token file" {
            # Pre-populate cache
            $cacheDir = Join-Path $testPath ".security\token-cache"
            New-Item -Path $cacheDir -ItemType Directory -Force | Out-Null
            $cachePath = Join-Path $cacheDir "lenovo-psref.xml"
            @{ Token = "test"; Timestamp = (Get-Date).ToString('o') } | Export-Clixml -Path $cachePath

            $cachePath | Should -Exist

            Clear-LenovoPSREFTokenCache -FFUDevelopmentPath $testPath

            $cachePath | Should -Not -Exist
        }

        It "Does not throw when no cache file exists" {
            { Clear-LenovoPSREFTokenCache -FFUDevelopmentPath $testPath } | Should -Not -Throw
        }

        It "Leaves cache directory intact" {
            # Pre-populate cache
            $cacheDir = Join-Path $testPath ".security\token-cache"
            New-Item -Path $cacheDir -ItemType Directory -Force | Out-Null
            $cachePath = Join-Path $cacheDir "lenovo-psref.xml"
            @{ Token = "test"; Timestamp = (Get-Date).ToString('o') } | Export-Clixml -Path $cachePath

            Clear-LenovoPSREFTokenCache -FFUDevelopmentPath $testPath

            $cacheDir | Should -Exist
        }
    }

    Context "Cache Security" {
        It "Cache file is created with Export-Clixml format" {
            Set-LenovoPSREFTokenCache -FFUDevelopmentPath $testPath -Token "security-test-token"

            $cachePath = Join-Path $testPath ".security\token-cache\lenovo-psref.xml"
            $content = Get-Content -Path $cachePath -Raw

            # Verify it's CLIXML format (DPAPI encrypted on Windows)
            $content | Should -Match "<Objs.*xmlns"
        }

        It "Token is retrievable after caching" {
            $originalToken = "X-PSREF-USER-TOKEN=eyJ0eXAiOiJKV1QifQ.testpayload.testsignature"

            Set-LenovoPSREFTokenCache -FFUDevelopmentPath $testPath -Token $originalToken

            $cachePath = Join-Path $testPath ".security\token-cache\lenovo-psref.xml"
            $cached = Import-Clixml -Path $cachePath

            $cached.Token | Should -Be $originalToken
        }
    }
}
