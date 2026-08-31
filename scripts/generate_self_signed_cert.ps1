<#
.SYNOPSIS
    Generates a self-signed Code Signing Certificate (.pfx and .cer) for local testing and CI setup.

.DESCRIPTION
    This script generates a self-signed X.509 code-signing certificate, exports the private key to a
    password-protected .pfx file, exports the public certificate to a .cer file, and outputs the
    base64-encoded string for configuring GitHub Secrets (WINDOWS_CERT_BASE64).

.PARAMETER OutputDir
    Directory to save the generated .pfx and .cer files. Defaults to current directory.

.PARAMETER Subject
    Subject distinguished name for the certificate. Defaults to "CN=Files Utility Test Signing, O=genexis.dev".

.PARAMETER Password
    Password for the exported .pfx file. If omitted, a secure random password is generated.

.PARAMETER ValidYears
    Number of years the certificate remains valid. Defaults to 2 years.

.EXAMPLE
    .\scripts\generate_self_signed_cert.ps1

.EXAMPLE
    .\scripts\generate_self_signed_cert.ps1 -OutputDir "C:\certs" -Password "MyPassword123!"
#>

[CmdletBinding()]
param(
    [string]$OutputDir = ".",
    [string]$Subject = "CN=Files Utility Test Signing, O=genexis.dev",
    [string]$Password = "",
    [int]$ValidYears = 2
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$resolvedOutputDir = (Resolve-Path $OutputDir).Path
$pfxFile = Join-Path $resolvedOutputDir "files_utility_test_cert.pfx"
$cerFile = Join-Path $resolvedOutputDir "files_utility_test_cert.cer"

if ([string]::IsNullOrWhiteSpace($Password)) {
    $Password = [System.Guid]::NewGuid().ToString("N")
}

$securePassword = ConvertTo-SecureString -String $Password -Force -AsPlainText

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Generating Self-Signed Code Signing Certificate" -ForegroundColor Cyan
Write-Host " Subject: $Subject" -ForegroundColor Cyan
Write-Host " Validity: $ValidYears years" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# Generate certificate
$cert = New-SelfSignedCertificate `
    -Type CodeSigningCert `
    -Subject $Subject `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -KeyUsage DigitalSignature `
    -FriendlyName "Files Utility Code Signing" `
    -NotAfter (Get-Date).AddYears($ValidYears)

try {
    # Export PFX (with private key)
    Export-PfxCertificate -Cert $cert -FilePath $pfxFile -Password $securePassword | Out-Null
    Write-Host "`n[+] Exported Private Certificate (PFX): $pfxFile" -ForegroundColor Green

    # Export CER (public key only)
    Export-Certificate -Cert $cert -FilePath $cerFile | Out-Null
    Write-Host "[+] Exported Public Certificate (CER):  $cerFile" -ForegroundColor Green

    # Generate Base64 representation
    $certBytes = [System.IO.File]::ReadAllBytes($pfxFile)
    $base64Cert = [Convert]::ToBase64String($certBytes)

    Write-Host "`n----------------------------------------------------------" -ForegroundColor Yellow
    Write-Host " Certificate Credentials" -ForegroundColor Yellow
    Write-Host "----------------------------------------------------------" -ForegroundColor Yellow
    Write-Host "PFX Password:" -ForegroundColor White
    Write-Host "  $Password" -ForegroundColor Cyan
    Write-Host "`nThumbprint:" -ForegroundColor White
    Write-Host "  $($cert.Thumbprint)" -ForegroundColor Cyan

    Write-Host "`n----------------------------------------------------------" -ForegroundColor Yellow
    Write-Host " GitHub Actions Repository Secrets Configuration" -ForegroundColor Yellow
    Write-Host "----------------------------------------------------------" -ForegroundColor Yellow
    Write-Host "Set the following secrets under Settings > Secrets > Actions:" -ForegroundColor White
    Write-Host "  WINDOWS_CERT_BASE64   : (Value below)" -ForegroundColor Gray
    Write-Host "  WINDOWS_CERT_PASSWORD : $Password" -ForegroundColor Gray
    Write-Host "`nBase64 Value for WINDOWS_CERT_BASE64:" -ForegroundColor White
    Write-Host $base64Cert -ForegroundColor DarkGray

    # Optional: copy base64 to clipboard if running in an interactive session
    try {
        if ([Environment]::UserInteractive) {
            Set-Clipboard -Value $base64Cert
            Write-Host "`n(Base64 string copied to clipboard)" -ForegroundColor Green
        }
    } catch {}

    Write-Host "`n----------------------------------------------------------" -ForegroundColor Yellow
    Write-Host " Installing for Local Trust (Optional Test Step):" -ForegroundColor Yellow
    Write-Host "----------------------------------------------------------" -ForegroundColor Yellow
    Write-Host "To trust this self-signed cert on your local Windows machine:" -ForegroundColor White
    Write-Host "  Import-Certificate -FilePath `"$cerFile`" -CertStoreLocation Cert:\CurrentUser\Root" -ForegroundColor Cyan
    Write-Host "  Import-Certificate -FilePath `"$cerFile`" -CertStoreLocation Cert:\CurrentUser\TrustedPublisher" -ForegroundColor Cyan
    Write-Host "==========================================================`n" -ForegroundColor Cyan
}
finally {
    # Remove from CurrentUser\My to keep store clean
    Get-ChildItem "Cert:\CurrentUser\My\$($cert.Thumbprint)" -ErrorAction SilentlyContinue | Remove-Item -ErrorAction SilentlyContinue
}
