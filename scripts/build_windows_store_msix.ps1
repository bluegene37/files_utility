# Gene - Nov, 23, 2026: Build unsigned Microsoft Store MSIX package with Partner Center identity and STORE_BUILD=true
<#
.SYNOPSIS
    Builds and packages an unsigned Microsoft Store MSIX archive for Files Utility.

.DESCRIPTION
    This script automates the Microsoft Store MSIX packaging flow:
    1. Resolves Partner Center Product Identity values from parameters or environment variables.
    2. Compiles the Flutter Windows release binaries with `--dart-define=STORE_BUILD=true`
       so the GitHub Releases in-app self-updater is disabled (Microsoft Store Policy 10.2).
    3. Invokes `dart run msix:create --store` to generate an unsigned MSIX package in `dist/`
       ready for upload to Microsoft Partner Center (which handles Store code signing).

.PARAMETER IdentityName
    Partner Center Package/Identity/Name (falls back to $env:MSSTORE_IDENTITY_NAME).

.PARAMETER Publisher
    Partner Center Package/Identity/Publisher, e.g. CN=<YOUR-GUID> (falls back to $env:MSSTORE_PUBLISHER).

.PARAMETER DisplayName
    App display name (falls back to $env:MSSTORE_DISPLAY_NAME, then pubspec.yaml msix_config.display_name).

.PARAMETER PublisherDisplayName
    Partner Center PublisherDisplayName (falls back to $env:MSSTORE_PUBLISHER_DISPLAY_NAME, then pubspec.yaml msix_config.publisher_display_name).

.PARAMETER SkipBuild
    Skips `flutter build windows --release --dart-define=STORE_BUILD=true` and packages existing binaries.

.EXAMPLE
    .\scripts\build_windows_store_msix.ps1 -IdentityName "<YOUR_IDENTITY_NAME>" -Publisher "CN=<YOUR-PUBLISHER-GUID>"

.EXAMPLE
    $env:MSSTORE_IDENTITY_NAME = "<YOUR_IDENTITY_NAME>"
    $env:MSSTORE_PUBLISHER = "CN=<YOUR-PUBLISHER-GUID>"
    .\scripts\build_windows_store_msix.ps1
#>

[CmdletBinding()]
param(
    [string]$IdentityName = "",
    [string]$Publisher = "",
    [string]$DisplayName = "",
    [string]$PublisherDisplayName = "",
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

# Navigate to project root
$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

# Extract version and fallback display metadata from pubspec.yaml (ignoring commented lines)
$pubspecContent = Get-Content "pubspec.yaml" -Raw
$versionMatch = [regex]::Match($pubspecContent, '(?m)^\s*version:\s*"?(?<ver>[0-9]+\.[0-9]+\.[0-9]+)(\+[0-9]+)?')
if (-not $versionMatch.Success) {
    throw "Could not determine version from pubspec.yaml"
}
$version = $versionMatch.Groups['ver'].Value
$msixVersion = "$version.0"

$displayNameMatch = [regex]::Match($pubspecContent, '(?m)^\s*display_name:\s*"?(?<val>[^"\r\n#]+)"?')
$pubspecDisplayName = if ($displayNameMatch.Success) { $displayNameMatch.Groups['val'].Value.Trim() } else { "Files Utility" }

$pubDisplayMatch = [regex]::Match($pubspecContent, '(?m)^\s*publisher_display_name:\s*"?(?<val>[^"\r\n#]+)"?')
$pubspecPublisherDisplayName = if ($pubDisplayMatch.Success) { $pubDisplayMatch.Groups['val'].Value.Trim() } else { "genexis.dev" }

$resolvedIdentityName = if (-not [string]::IsNullOrWhiteSpace($IdentityName)) { $IdentityName } else { $env:MSSTORE_IDENTITY_NAME }
$resolvedPublisher = if (-not [string]::IsNullOrWhiteSpace($Publisher)) { $Publisher } else { $env:MSSTORE_PUBLISHER }
$resolvedDisplayName = if (-not [string]::IsNullOrWhiteSpace($DisplayName)) {
    $DisplayName
} elseif (-not [string]::IsNullOrWhiteSpace($env:MSSTORE_DISPLAY_NAME)) {
    $env:MSSTORE_DISPLAY_NAME
} else {
    $pubspecDisplayName
}
$resolvedPublisherDisplayName = if (-not [string]::IsNullOrWhiteSpace($PublisherDisplayName)) {
    $PublisherDisplayName
} elseif (-not [string]::IsNullOrWhiteSpace($env:MSSTORE_PUBLISHER_DISPLAY_NAME)) {
    $env:MSSTORE_PUBLISHER_DISPLAY_NAME
} else {
    $pubspecPublisherDisplayName
}

if ([string]::IsNullOrWhiteSpace($resolvedIdentityName)) {
    throw "Missing Microsoft Store Identity Name. Pass -IdentityName or set the MSSTORE_IDENTITY_NAME environment variable."
}
if ([string]::IsNullOrWhiteSpace($resolvedPublisher)) {
    throw "Missing Microsoft Store Publisher. Pass -Publisher or set the MSSTORE_PUBLISHER environment variable."
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Files Utility - Microsoft Store MSIX Builder" -ForegroundColor Cyan
Write-Host " Version: $version (MSIX: $msixVersion)" -ForegroundColor Cyan
Write-Host " Display Name: $resolvedDisplayName" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Build Flutter Windows Release with STORE_BUILD=true
if (-not $SkipBuild) {
    Write-Host "`n==> Building Flutter Windows Release (STORE_BUILD=true)..." -ForegroundColor Green
    flutter build windows --release --dart-define=STORE_BUILD=true
    if ($LASTEXITCODE -ne 0) {
        throw "flutter build windows --release --dart-define=STORE_BUILD=true failed with exit code $LASTEXITCODE"
    }
} else {
    Write-Host "`n==> Skipping Flutter build step (-SkipBuild specified)..." -ForegroundColor Yellow
}

$releaseRunnerDir = "build\windows\x64\runner\Release"
if (-not (Test-Path $releaseRunnerDir)) {
    throw "Release directory '$releaseRunnerDir' not found. Please run without -SkipBuild."
}

# 2. Ensure dist/ exists and create unsigned --store MSIX
$distDir = Join-Path $RootDir "dist"
if (-not (Test-Path $distDir)) {
    New-Item -ItemType Directory -Path $distDir | Out-Null
}

$outputName = "files_utility-$version-msstore"
$expectedMsixPath = Join-Path $distDir "$outputName.msix"
if (Test-Path $expectedMsixPath) {
    Remove-Item -Path $expectedMsixPath -Force
}

Write-Host "`n==> Packaging unsigned Microsoft Store MSIX via msix:create --store..." -ForegroundColor Green
dart run msix:create `
    --store `
    --build-windows false `
    --version "$msixVersion" `
    --display-name "$resolvedDisplayName" `
    --publisher-display-name "$resolvedPublisherDisplayName" `
    --identity-name "$resolvedIdentityName" `
    --publisher "$resolvedPublisher" `
    --logo-path "assets/icon/app_icon.png" `
    --output-path "$distDir" `
    --output-name "$outputName"

if ($LASTEXITCODE -ne 0) {
    throw "dart run msix:create failed with exit code $LASTEXITCODE"
}

if (-not (Test-Path $expectedMsixPath)) {
    throw "Expected Store MSIX package was not produced at '$expectedMsixPath'."
}

$msixInfo = Get-Item $expectedMsixPath
$sizeMb = [Math]::Round($msixInfo.Length / 1MB, 2)

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host " Microsoft Store MSIX created successfully!" -ForegroundColor Green
Write-Host " Output: $expectedMsixPath ($sizeMb MB)" -ForegroundColor Green
Write-Host " Note: Upload this unsigned --store package to Partner Center." -ForegroundColor Yellow
Write-Host "       Microsoft signs Store packages automatically upon ingestion;" -ForegroundColor Yellow
Write-Host "       do not sideload this package directly." -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Green
