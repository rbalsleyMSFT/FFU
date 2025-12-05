# Quick test to verify XAML parses correctly
Add-Type -AssemblyName PresentationFramework

$xamlPath = Join-Path $PSScriptRoot "..\FFUDevelopment\BuildFFUVM_UI.xaml"
Write-Host "Testing XAML: $xamlPath"

try {
    $xaml = Get-Content $xamlPath -Raw
    $reader = New-Object System.IO.StringReader($xaml)
    $xmlReader = [System.Xml.XmlReader]::Create($reader)
    $window = [Windows.Markup.XamlReader]::Load($xmlReader)

    # Check for About tab
    $aboutTab = $window.FindName("AboutTab")
    if ($aboutTab) {
        Write-Host "[PASS] About tab found in XAML" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] About tab not found" -ForegroundColor Red
    }

    # Check for version text block
    $txtAboutVersion = $window.FindName("txtAboutVersion")
    if ($txtAboutVersion) {
        Write-Host "[PASS] Version text block found" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] Version text block not found" -ForegroundColor Red
    }

    # Check for hyperlinks
    $lnkGitHub = $window.FindName("lnkGitHub")
    $lnkDocs = $window.FindName("lnkDocs")
    $lnkIssues = $window.FindName("lnkIssues")

    if ($lnkGitHub -and $lnkDocs -and $lnkIssues) {
        Write-Host "[PASS] All hyperlinks found" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] Some hyperlinks missing" -ForegroundColor Red
    }

    Write-Host "`nXAML parsed successfully!" -ForegroundColor Green
    exit 0
}
catch {
    Write-Host "[FAIL] XAML parse error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
