# External Integrations

**Analysis Date:** 2026-01-16

## APIs & External Services

**Microsoft Windows Update:**
- Service: Microsoft Update Catalog and Windows Update Service
- Used for: Downloading Windows updates (CU, Defender, .NET, MSRT)
- Endpoints:
  - `https://catalog.update.microsoft.com/Search.aspx` - Update search
  - `https://catalog.update.microsoft.com/DownloadDialog.aspx` - Download URLs
  - `https://fe3.delivery.mp.microsoft.com/UpdateMetadataService/` - Products.cab metadata
- Implementation: `FFUDevelopment/Modules/FFU.Updates/FFU.Updates.psm1`
- Auth: None (public API)

**Microsoft Office Deployment:**
- Service: Microsoft Office CDN
- Used for: Downloading Office Deployment Tool and Office installation files
- Implementation: `FFUDevelopment/Modules/FFU.Apps/FFU.Apps.psm1`
- Auth: None (public CDN)

**Microsoft Surface Drivers:**
- Service: Microsoft Support Page
- Endpoint: `https://support.microsoft.com/en-us/surface/download-drivers-and-firmware-for-surface-*`
- Used for: Surface device driver catalogs
- Implementation: `FFUDevelopment/Modules/FFU.Drivers/FFU.Drivers.psm1` (Get-MicrosoftDrivers)
- Auth: None (public web scraping)

## OEM Driver Catalogs

**Dell Drivers:**
- Catalog URL: `http://downloads.dell.com/catalog/CatalogPC.cab` (client), `https://downloads.dell.com/catalog/Catalog.cab` (server)
- Used for: Dell device driver downloads
- Implementation: `FFUDevelopment/Modules/FFU.Drivers/FFU.Drivers.psm1` (Get-DellDrivers)
- Auth: None

**HP Drivers:**
- Catalog URL: `https://hpia.hpcloud.hp.com/ref/platformList.cab`
- Driver Package URL: `https://hpia.hpcloud.hp.com/ref/{SystemID}/{ModelRelease}.cab`
- Download URL: `https://ftp.hp.com/pub/softpaq/sp*`
- Implementation: `FFUDevelopment/Modules/FFU.Drivers/FFU.Drivers.psm1` (Get-HPDrivers)
- Auth: None

**Lenovo Drivers:**
- PSREF API: `https://psref.lenovo.com/api/search/DefinitionFilterAndSearch/Suggest`
- Catalog URL: `https://download.lenovo.com/catalog/{ModelRelease}.xml`
- Used for: Lenovo device driver catalogs
- Implementation: `FFUDevelopment/Modules/FFU.Drivers/FFU.Drivers.psm1` (Get-LenovoDrivers)
- Auth: JWT token via PSREF (hardcoded, may expire)
- Note: Uses Edge DevTools Protocol for token refresh

**Intel Network Drivers:**
- Source: Intel Download Center
- Used for: e1000e drivers for VMware WinPE network support
- Implementation: `FFUDevelopment/Modules/FFU.Drivers/FFU.Drivers.psm1` (Get-IntelEthernetDrivers)
- Auth: None (requires browser-like headers)

## Hypervisor Integration

**Hyper-V (Primary):**
- Interface: PowerShell cmdlets (`Hyper-V` module)
- Functions: New-VM, Start-VM, Stop-VM, Remove-VM, Get-VM, etc.
- Implementation: `FFUDevelopment/Modules/FFU.Hypervisor/Providers/HyperVProvider.ps1`
- Auth: Windows administrative rights

**VMware Workstation Pro (Alternative):**
- Interface: vmrun.exe command-line tool
- Commands: `vmrun -T ws start/stop/list/register`
- VMX File Generation: `FFUDevelopment/Modules/FFU.Hypervisor/Private/New-VMwareVMX.ps1`
- Implementation: `FFUDevelopment/Modules/FFU.Hypervisor/Providers/VMwareProvider.ps1`
- Auth: None (file-based VM control)
- Note: vmrest REST API was removed in v1.2.0 due to authentication issues

## Data Storage

**Databases:**
- None - All data stored in local filesystem

**File Storage:**
- Local filesystem only
- Working directory: `C:\FFUDevelopment\` (configurable via `FFUDevelopmentPath`)
- FFU output: `{FFUDevelopmentPath}\FFU\`
- Drivers cache: `{FFUDevelopmentPath}\Drivers\`
- VHDX cache: `{FFUDevelopmentPath}\VHDXCache\`
- Logs: `{FFUDevelopmentPath}\Logs\`

**Caching:**
- VHDX caching (optional): `AllowVHDXCaching` config option
- Driver downloads cached locally
- Windows Update packages cached locally

## Authentication & Identity

**Auth Provider:**
- Windows local accounts only
- Implementation: Custom via .NET DirectoryServices APIs
- Functions in `FFUDevelopment/Modules/FFU.Core/FFU.Core.psm1`:
  - `New-SecureRandomPassword` - Cryptographic password generation
  - `ConvertFrom-SecureStringToPlainText` - Secure conversion
  - `Clear-PlainTextPassword` - Memory cleanup

**FFU Capture Share Authentication:**
- Temporary local user account created: `ffu_user` (configurable via `Username`)
- Auto-generated secure password
- Account and share removed after build completes
- SMB share: `FFUCaptureShare` (configurable via `ShareName`)

## Download Methods

**Multi-Method Download System** (`FFUDevelopment/FFU.Common/FFU.Common.Download.psm1`):

| Priority | Method | Use Case |
|----------|--------|----------|
| 1 | BITS (Start-BitsTransfer) | Primary, handles interruptions |
| 2 | Invoke-WebRequest | PowerShell native fallback |
| 3 | System.Net.WebClient | .NET fallback |
| 4 | curl.exe | Windows native fallback |

**Proxy Support:**
- `[FFUNetworkConfiguration]::DetectProxySettings()` - Auto-detection
- Environment variables: `HTTP_PROXY`, `HTTPS_PROXY`
- WinHTTP proxy settings respected

## Monitoring & Observability

**Error Tracking:**
- None (external service)
- Local logging only

**Logs:**
- File-based logging via `WriteLog` function
- Log file: `{FFUDevelopmentPath}\{VMName}_{timestamp}.log`
- Structured logging: `FFU.Common.Logging` module supports JSON output
- Session correlation IDs supported

**Real-time UI Updates:**
- ConcurrentQueue-based messaging (`FFU.Messaging` module)
- DispatcherTimer polling (50ms interval)

## CI/CD & Deployment

**Hosting:**
- Local Windows machine (no cloud hosting)
- Physical device deployment via USB boot media

**CI Pipeline:**
- None (manual execution)
- Pester tests available: `Tests/Unit/Invoke-PesterTests.ps1`

## Network Connectivity Requirements

**Pre-flight Network Check** (`FFUDevelopment/Modules/FFU.Preflight/FFU.Preflight.psm1`):

Required Endpoints:
- `https://catalog.update.microsoft.com` - Windows Updates
- `https://downloads.dell.com` - Dell drivers
- `https://hpia.hpcloud.hp.com` - HP drivers
- `https://download.lenovo.com` - Lenovo drivers
- `https://support.microsoft.com` - Microsoft Surface drivers
- `https://downloadcenter.intel.com` - Intel drivers

## Environment Configuration

**Required env vars:**
- None required (all config via JSON or parameters)

**Optional env vars:**
- `HTTP_PROXY` - Proxy server for HTTP
- `HTTPS_PROXY` - Proxy server for HTTPS
- `PSModulePath` - Module search path (auto-configured)

**Secrets location:**
- No persistent secrets
- Temporary credentials stored in SecureString during runtime
- Credentials cleared from memory after use

## Webhooks & Callbacks

**Incoming:**
- None

**Outgoing:**
- None

## WinGet Integration

**Windows Package Manager:**
- Service: Microsoft WinGet
- Used for: Installing applications in FFU image
- PowerShell Module: `Microsoft.WinGet.Client`
- App lists: `FFUDevelopment/Apps/AppList_Sample.json`
- Implementation: `FFUDevelopment/FFU.Common/FFU.Common.Winget.psm1`

## Edge DevTools Protocol (Lenovo)

**Purpose:** Lenovo PSREF requires JavaScript execution for authentication

**Implementation:** `FFUDevelopment/FFU.Common/FFU.Common.Drivers.psm1`
- Launches headless Edge browser
- Connects via CDP (Chrome DevTools Protocol)
- Endpoint: `http://localhost:{port}/json`
- Used to extract authentication tokens for Lenovo API

---

*Integration audit: 2026-01-16*
