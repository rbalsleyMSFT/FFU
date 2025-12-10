@{
    RootModule = 'FFU.Common.Logging.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'b8c4e5f6-7a8b-9c0d-e1f2-345678901234'
    Author = 'FFU Team'
    CompanyName = 'FFU Project'
    Copyright = '(c) FFU Project. All rights reserved.'
    Description = 'Structured logging module for FFU Builder with log levels, JSON output, and session correlation.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Initialize-FFULogging',
        'Write-FFULog',
        'Write-FFUDebug',
        'Write-FFUInfo',
        'Write-FFUSuccess',
        'Write-FFUWarning',
        'Write-FFUError',
        'Write-FFUCritical',
        'Get-FFULogSession',
        'Close-FFULogging'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('Logging', 'FFU', 'Structured')
        }
    }
}
