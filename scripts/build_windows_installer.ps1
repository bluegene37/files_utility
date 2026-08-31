<#
.SYNOPSIS
    Builds, signs (optional), and packages the Windows release installer and portable bundle.

.DESCRIPTION
    This script automates the complete Windows release pipeline for Files Utility:
    1. Compiles the Flutter Windows release binaries (unless -SkipBuild is specified).
    2. Signs the application executable with Authenticode SHA-256 and DigiCert timestamping (if cert provided).
    3. Builds the Inno Setup installer via inno_bundle.
    4. Signs the generated installer executable (if cert provided).
    5. Stages artifacts in dist/ (installer .exe and portable .zip bundle).

.PARAMETER CertPath
    Path to a .pfx code signing certificate file.

.PARAMETER CertPassword
    Password for the .pfx certificate.

.PARAMETER CreateSelfSigned
    Creates a temporary self-signed code signing certificate for local testing.

.PARAMETER SkipBuild
    Skips the `flutter build windows --release` step and packages existing release binaries.

.PARAMETER NoZip
    Skips creating the portable .zip archive in dist/.

.EXAMPLE
    # Build and package without signing:
    .\scripts\build_windows_installer.ps1

.EXAMPLE
    # Build, sign with certificate, and package:
    .\scripts\build_windows_installer.ps1 -CertPath "C:\certs\mycert.pfx" -CertPassword "Secret123!"

.EXAMPLE
    # Build and test signing with a temporary self-signed certificate:
    .\scripts\build_windows_installer.ps1 -CreateSelfSigned
#>

[CmdletBinding()]
param(
    [string]$CertPath = "",
    [string]$CertPassword = "",
    [switch]$CreateSelfSigned,
    [switch]$SkipBuild,
    [switch]$NoZip
)

$ErrorActionPreference = "Stop"

# Navigate to project root
$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

# Extract version and name from pubspec.yaml
$pubspecContent = Get-Content "pubspec.yaml" -Raw
$versionMatch = [regex]::Match($pubspecContent, 'version:\s*"?(?<ver>[0-9]+\.[0-9]+\.[0-9]+(\+[0-9]+)?)')
if (-not $versionMatch.Success) {
    throw "Could not determine version from pubspec.yaml"
}
$versionFull = $versionMatch.Groups['ver'].Value
$version = $versionFull.Split('+')[0]
$appName = "files_utility"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Files Utility - Windows Release Builder & Packager" -ForegroundColor Cyan
Write-Host " Version: $versionFull" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Build Flutter Windows Release
if (-not $SkipBuild) {
    Write-Host "`n==> Building Flutter Windows Release..." -ForegroundColor Green
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw "flutter build windows --release failed with exit code $LASTEXITCODE" }
} else {
    Write-Host "`n==> Skipping Flutter build step (-SkipBuild specified)..." -ForegroundColor Yellow
}

$releaseRunnerDir = "build\windows\x64\runner\Release"
if (-not (Test-Path $releaseRunnerDir)) {
    throw "Release directory '$releaseRunnerDir' not found. Please run without -SkipBuild."
}

# 2. Determine Certificate and Signing Strategy
$tempCertPath = $null
$isTemporaryCert = $false
$signingEnabled = $false

try {
    if ($CertPath -and (Test-Path $CertPath)) {
        $resolvedCertPath = (Resolve-Path $CertPath).Path
        $resolvedCertPass = $CertPassword
        $signingEnabled = $true
        Write-Host "==> Using certificate file: $resolvedCertPath" -ForegroundColor Green
    }
    elseif ($env:WINDOWS_CERT_BASE64) {
        $tempDir = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [System.IO.Path]::GetTempPath() }
        $tempCertPath = Join-Path $tempDir "files_utility_signing_cert_$([System.Guid]::NewGuid().ToString('N')).pfx"
        [IO.File]::WriteAllBytes($tempCertPath, [Convert]::FromBase64String($env:WINDOWS_CERT_BASE64))
        $resolvedCertPath = $tempCertPath
        $resolvedCertPass = $env:WINDOWS_CERT_PASSWORD
        $isTemporaryCert = $true
        $signingEnabled = $true
        Write-Host "==> Imported certificate from environment variable." -ForegroundColor Green
    }
    elseif ($CreateSelfSigned) {
        Write-Host "==> Generating temporary self-signed code signing certificate for local test..." -ForegroundColor Yellow
        $tempDir = [System.IO.Path]::GetTempPath()
        $tempCertPath = Join-Path $tempDir "files_utility_selfsigned_$([System.Guid]::NewGuid().ToString('N')).pfx"
        $certPass = [System.Guid]::NewGuid().ToString('N')
        $securePass = ConvertTo-SecureString -String $certPass -Force -AsPlainText

        $cert = New-SelfSignedCertificate `
            -Type CodeSigningCert `
            -Subject "CN=Files Utility Test Signing, O=genexis.dev" `
            -CertStoreLocation "Cert:\CurrentUser\My" `
            -KeyUsage DigitalSignature `
            -FriendlyName "Files Utility Test Signing" `
            -NotAfter (Get-Date).AddDays(30)

        Export-PfxCertificate -Cert $cert -FilePath $tempCertPath -Password $securePass | Out-Null
        # Remove from local store after export
        Get-ChildItem Cert:\CurrentUser\My\$($cert.Thumbprint) | Remove-Item

        $resolvedCertPath = $tempCertPath
        $resolvedCertPass = $certPass
        $isTemporaryCert = $true
        $signingEnabled = $true
        Write-Host "==> Temporary self-signed certificate created." -ForegroundColor Green
    }
    else {
        Write-Host "==> No signing certificate provided. Release will be UNSIGNED." -ForegroundColor Yellow
        Write-Host "    (To sign, pass -CertPath and -CertPassword, set WINDOWS_CERT_BASE64, or use -CreateSelfSigned for testing)" -ForegroundColor Gray
    }

    # Find signtool.exe if signing is enabled
    $signtool = $null
    if ($signingEnabled) {
        $signtoolCandidates = @(
            (Get-ChildItem "C:\Program Files (x86)\Windows Kits\10\bin\*\x64\signtool.exe" -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1),
            (Get-ChildItem "C:\Program Files\Windows Kits\10\bin\*\x64\signtool.exe" -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1),
            (Get-ChildItem "C:\Program Files (x86)\Windows Kits\*\bin\*\x64\signtool.exe" -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1)
        )
        foreach ($candidate in $signtoolCandidates) {
            if ($candidate -and (Test-Path $candidate.FullName)) {
                $signtool = $candidate.FullName
                break
            }
        }
        if (-not $signtool) {
            # Check PATH
            $signtoolInPath = Get-Command "signtool.exe" -ErrorAction SilentlyContinue
            if ($signtoolInPath) { $signtool = $signtoolInPath.Source }
        }

        if (-not $signtool) {
            Write-Warning "signtool.exe was not found on this system. Signing will be skipped. Install the Windows SDK to enable signing."
            $signingEnabled = $false
        } else {
            Write-Host "==> Found signtool.exe at: $signtool" -ForegroundColor Green
        }
    }

    # Function to sign a file
    function Sign-File([string]$filePath) {
        if (-not $signingEnabled) { return }
        Write-Host "    Signing: $filePath" -ForegroundColor Cyan
        
        $signArgs = @("sign", "/f", "$resolvedCertPath")
        if ($resolvedCertPass) {
            $signArgs += @("/p", "$resolvedCertPass")
        }
        $signArgs += @("/fd", "sha256", "/tr", "http://timestamp.digicert.com", "/td", "sha256", "$filePath")

        & "$signtool" $signArgs
        if ($LASTEXITCODE -ne 0) {
            # Try without timestamping if timestamp server is unreachable
            Write-Warning "Timestamped signing failed. Retrying without timestamp server..."
            $fallbackArgs = @("sign", "/f", "$resolvedCertPath")
            if ($resolvedCertPass) { $fallbackArgs += @("/p", "$resolvedCertPass") }
            $fallbackArgs += @("/fd", "sha256", "$filePath")
            & "$signtool" $fallbackArgs
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to sign file: $filePath (Exit code: $LASTEXITCODE)"
            }
        }
    }

    # 3. Sign Application Binaries
    if ($signingEnabled) {
        Write-Host "`n==> Signing Application Executable(s)..." -ForegroundColor Green
        $appExes = Get-ChildItem -Path $releaseRunnerDir -Filter *.exe
        if (-not $appExes) { throw "No application .exe found in $releaseRunnerDir" }
        foreach ($exe in $appExes) {
            Sign-File $exe.FullName
        }
    }

    # 4. Build Inno Setup Installer
    Write-Host "`n==> Packaging Inno Setup Installer..." -ForegroundColor Green
    dart run inno_bundle:build --release --no-app
    if ($LASTEXITCODE -ne 0) { throw "Inno Setup packaging failed with exit code $LASTEXITCODE" }

    # 5. Sign Inno Setup Installer(s)
    if ($signingEnabled) {
        Write-Host "`n==> Signing Inno Setup Installer(s)..." -ForegroundColor Green
        $installers = Get-ChildItem -Path "build\windows\x64\installer" -Recurse -Filter *.exe
        if (-not $installers) { throw "No installer .exe found in build\windows\x64\installer" }
        foreach ($inst in $installers) {
            Sign-File $inst.FullName
        }
    }

    # 6. Stage Artifacts in dist/
    Write-Host "`n==> Staging artifacts in dist/..." -ForegroundColor Green
    $distDir = Join-Path $RootDir "dist"
    if (-not (Test-Path $distDir)) { New-Item -ItemType Directory -Path $distDir | Out-Null }

    $installerFiles = Get-ChildItem -Path "build\windows\x64\installer" -Recurse -Filter *.exe
    foreach ($inst in $installerFiles) {
        $dest = Join-Path $distDir $inst.Name
        Copy-Item -Path $inst.FullName -Destination $dest -Force
        Write-Host "    Copied installer: $dest" -ForegroundColor Cyan
    }

    # 7. Create Portable Zip Bundle
    if (-not $NoZip) {
        $zipName = "$appName-$version-windows-x64.zip"
        $zipPath = Join-Path $distDir $zipName
        Write-Host "`n==> Creating portable zip bundle: $zipPath..." -ForegroundColor Green
        if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
        Compress-Archive -Path "$releaseRunnerDir\*" -DestinationPath $zipPath -Force
        Write-Host "    Created portable zip: $zipPath" -ForegroundColor Cyan
    }

    Write-Host "`n==========================================================" -ForegroundColor Green
    Write-Host " Build and packaging completed successfully!" -ForegroundColor Green
    Write-Host " Output directory: $distDir" -ForegroundColor Green
    Get-ChildItem -Path $distDir | Format-Table Name, Length, LastWriteTime
    Write-Host "==========================================================" -ForegroundColor Green
}
finally {
    # Clean up temporary certificate if generated or imported
    if ($isTemporaryCert -and $tempCertPath -and (Test-Path $tempCertPath)) {
        Remove-Item -Path $tempCertPath -Force -ErrorAction SilentlyContinue
    }
}
