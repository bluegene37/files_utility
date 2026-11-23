# Releasing Files Utility

This document outlines the official release procedure, versioning principles, packaging steps, code-signing policies, and continuous delivery pipelines for **Files Utility**.

---

## 🏷️ Application Identity

| Attribute | Value |
| :--- | :--- |
| **Application Name** | `Files Utility` |
| **Publisher** | `genexis.dev` |
| **Bundle / App Identifier** | `dev.genexis.filesutility` |
| **Inno Setup AppId GUID** | `45c1dad5-92eb-46d2-b870-e4db4aaeeadd` *(Immutable)* |
| **Legal Copyright** | `Copyright © 2026 genexis.dev. All rights reserved.` |

> [!WARNING]
> The Inno Setup AppId GUID in `pubspec.yaml` (`inno_bundle.id`) represents the installer's **upgrade identity**. It **must never be altered**, otherwise subsequent installer executions will fail to detect and upgrade existing installations in place.

---

## 🔢 Semantic Versioning & Synchronized Files

Files Utility strictly follows [Semantic Versioning (SemVer 2.0.0)](https://semver.org/):
`MAJOR.MINOR.PATCH+BUILD` (e.g. `1.0.1+2`).

The primary single source of truth is the `version:` field in [`pubspec.yaml`](pubspec.yaml). Whenever a new release is prepared, update the following **three files in a single atomic commit**:

1. **[`pubspec.yaml`](pubspec.yaml)**:
   ```yaml
   version: "1.0.1+2"
   ```
2. **[`pubspec.yaml`](pubspec.yaml)** (`msix_config` block):
   ```yaml
   msix_config:
     msix_version: "1.0.1.0"   # Requires exactly 4 numeric segments (X.Y.Z.0)
   ```
3. **[`lib/app_info.dart`](lib/app_info.dart)**:
   ```dart
   static const String appVersion = '1.0.1';
   ```

*Note: Native Windows (`Runner.rc`) and macOS (`CFBundleShortVersionString` / `CFBundleVersion`) version descriptors are automatically injected by Flutter build tools from `pubspec.yaml`.*

---

## 🚀 Release Step-by-Step Checklist

### 1. Pre-Flight Quality Verification
Run local static analysis, formatting verification, and the unit/widget test suite:
```bash
# 1. Check for lint or analyzer warnings
flutter analyze --fatal-infos

# 2. Check formatting compliance
dart format --output=none --set-exit-if-changed lib test

# 3. Execute automated test suite
flutter test
```

### 2. Update Documentation & Version
- Bump versions in `pubspec.yaml` (both `version` and `msix_version`) and `lib/app_info.dart`.
- Update [`CHANGELOG.md`](CHANGELOG.md) moving items from `[Unreleased]` into the new release header (e.g. `## [1.0.1] - YYYY-MM-DD`).
- Commit changes:
  ```bash
  git add pubspec.yaml lib/app_info.dart CHANGELOG.md
  git commit -m "chore(release): bump version to 1.0.1"
  ```

### 3. Tag and Trigger Automated Build
Push the commit to `main` and push the corresponding Git tag matching `v*`:
```bash
git push origin main
git tag -a v1.0.1 -m "Release v1.0.1"
git push origin v1.0.1
```

---

## 🤖 Automated CI/CD Pipelines

Pushing a tag matching `v*` (or manually executing the `workflow_dispatch` on GitHub) triggers [`.github/workflows/release.yml`](.github/workflows/release.yml):

1. **Windows Runner (`windows-latest`)**:
   - Executes `flutter analyze` & `flutter test`.
   - Compiles Windows x64 release binaries (`flutter build windows --release`).
   - Invokes Inno Setup compiler (`dart run inno_bundle:build --release --no-app`).
   - Uploads `files_utility-setup.exe`.
<!-- Gene - Oct, 07, 2026: Updated macOS Runner pipeline description to include Developer ID code signing, Hardened Runtime, and Apple notarization -->
<!-- Previous implementation:
2. **macOS Runner (`macos-latest`)**:
   - Executes `flutter test`.
   - Compiles macOS release `.app` (`flutter build macos --release`).
   - Packages drag-to-`/Applications` DMG image via [`scripts/build_macos_dmg.sh`](scripts/build_macos_dmg.sh).
   - Uploads `Files Utility-<version>.dmg`.
-->
2. **macOS Runner (`macos-latest`)**:
   - Executes `flutter test`.
   - Imports Apple Developer ID certificate (if secrets are set).
   - Compiles macOS release `.app` (`flutter build macos --release`).
   - Packages and signs drag-to-`/Applications` DMG image with Developer ID & Hardened Runtime via [`scripts/build_macos_dmg.sh`](scripts/build_macos_dmg.sh).
   - Submits to Apple Notary Service (`xcrun notarytool`) and staples tickets if credentials are provided.
   - Uploads `Files Utility-<version>.dmg`.
3. **Publish Step (`ubuntu-latest`)**:
   - Downloads all release artifacts from runners.
   - Generates release notes from merged commits/PRs.
   - Attaches `.exe` and `.dmg` binaries to the official GitHub Release.

---

## 🔄 In-App Update Checker

The app self-reports new versions via `lib/services/update/` (see
`UpdateService`). On launch it queries
`https://api.github.com/repos/bluegene37/files_utility/releases/latest`
(throttled to one network call per 24 hours) and compares the release tag
against `AppInfo.appVersion`.

**Release contract the updater depends on — keep these true:**

1. Release tags must be semver (`v1.2.3`); a non-version tag on the latest
   release disables update prompts until it is fixed.
2. Asset naming per platform:
   - **Windows**: the Inno installer must keep its `-Installer.exe` suffix
     (default `inno_bundle` naming). It is downloaded and executed with
     `/SILENT /CLOSEAPPLICATIONS`, then the app relaunches itself.
   - **macOS**: a `.dmg` asset; the updater opens the release page in the
     browser (silent in-place update requires signing/notarization first).
   - **Linux**: a `.deb` (preferred) or `.tar.gz`; opens the release page.
3. `AppInfo.appVersion` must match `version:` in `pubspec.yaml` — an
   out-of-date constant makes the app re-offer the version it already runs.

Updater state (last check time, cached release, skipped version) lives in
`shared_preferences`, never in the per-profile config database.

---

## ✍️ Enabling Windows Code Signing

`release.yml` already contains the `signtool.exe` steps. They are inert until
two repository secrets exist, so releases keep publishing unsigned until you
supply a certificate — nothing to uncomment, nothing to merge.

| Secret | Value |
| :--- | :--- |
| `WINDOWS_CERT_BASE64` | Your `.pfx` certificate, base64-encoded |
| `WINDOWS_CERT_PASSWORD` | The `.pfx` export password |

Encode the certificate:

```bash
# macOS / Linux
base64 -i certificate.pfx | tr -d '\n' | pbcopy
```

```powershell
# Windows
[Convert]::ToBase64String([IO.File]::ReadAllBytes("certificate.pfx")) | Set-Clipboard
```

Add both under **Settings → Secrets and variables → Actions**. The next tagged
release signs the application executable *and* the Inno installer (SHA-256,
timestamped against `timestamp.digicert.com`, so signatures stay valid after
the certificate expires). The certificate is written to `RUNNER_TEMP` and
deleted in an `if: always()` step.

With no secret set the build logs a `::warning::` naming the consequence and
continues unsigned — a release is never blocked by a missing certificate.

> [!NOTE]
> **EV vs OV certificates.** An EV (Extended Validation) certificate clears
> SmartScreen immediately. A standard OV certificate must first accrue
> download reputation, so early users may still see the warning even though
> the binary is correctly signed.

---

<!-- Gene - Oct, 07, 2026: Added macOS Developer ID Code Signing & Notarization instructions -->
## 🍏 Enabling macOS Code Signing & Notarization

`release.yml` and `scripts/build_macos_dmg.sh` support Apple Developer ID Application code signing, Hardened Runtime, DMG signing, and automated Apple Notarization via `xcrun notarytool`.

### GitHub Actions Secrets

To enable automated signing and notarization on GitHub Releases, configure the following secrets under **Settings → Secrets and variables → Actions**:

| Secret | Value |
| :--- | :--- |
| `MACOS_CERTIFICATE_BASE64` | Your Developer ID Application `.p12` certificate, base64-encoded |
| `MACOS_CERTIFICATE_PASSWORD` | The `.p12` export password |
| `APPLE_ID` | Apple Developer Account email (e.g. `<your-apple-id@example.com>`) |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password generated from appleid.apple.com |
| `APPLE_TEAM_ID` | Apple Developer Team ID (`<YOUR_TEAM_ID>`) |

Encode `.p12` certificate for GitHub Secrets:
```bash
base64 -i cert.p12 | tr -d '\n' | pbcopy
```

With no certificate secret set, the CI workflow falls back gracefully to an ad-hoc signed `.app` and DMG without failing the build.

---

## 💻 Manual / Local Packaging

### Windows Installer & Portable Bundle (Automated Script)
*Requires [Inno Setup 6](https://jrsoftware.org/isinfo.php) installed locally (if packaging the installer).*
```powershell
# Standard unsigned build (creates installer & portable zip in dist/):
.\scripts\build_windows_installer.ps1

# Build and sign with a PFX certificate:
.\scripts\build_windows_installer.ps1 -CertPath "C:\path\to\cert.pfx" -CertPassword "<your-cert-password>"

# Build and test signing with an automated self-signed certificate:
.\scripts\build_windows_installer.ps1 -CreateSelfSigned

# Package existing build without recompiling Flutter:
.\scripts\build_windows_installer.ps1 -SkipBuild
```

### Self-Signed Certificate Generation (For Testing)
Generate a test code-signing certificate (`.pfx` and `.cer`) and base64 credentials for GitHub Secrets:
```powershell
.\scripts\generate_self_signed_cert.ps1
```

### Windows MSIX Bundle
```bash
dart run msix:create
# Output location: build/windows/x64/runner/Release/files_utility.msix
```

<!-- Gene - Nov, 23, 2026: Document Microsoft Store MSIX packaging, CI secrets, STORE_BUILD flag, WACK verification, and runFullTrust justification -->
### Windows Microsoft Store (`.msix`)

Microsoft Store builds are compiled with `--dart-define=STORE_BUILD=true` (disabling the GitHub Releases self-updater to comply with Microsoft Store Policy 10.2) and packaged unsigned via `dart run msix:create --store` so Microsoft can sign the package upon Partner Center ingestion.

#### GitHub Actions Secrets (Store Artifact Pipeline)
Add the following secrets from **Partner Center → Product management → Product identity** under **Settings → Secrets and variables → Actions** to enable the `build-windows-store` job in [`.github/workflows/release.yml`](.github/workflows/release.yml):

| Secret | Value |
| :--- | :--- |
| `MSSTORE_IDENTITY_NAME` | Partner Center `Package/Identity/Name` (e.g. `<YOUR_MSSTORE_IDENTITY_NAME>`) |
| `MSSTORE_PUBLISHER` | Partner Center `Package/Identity/Publisher` (`CN=<YOUR-PUBLISHER-GUID>`) |
| `MSSTORE_DISPLAY_NAME` | Reserved Store display name (default: `Files Utility`) |
| `MSSTORE_PUBLISHER_DISPLAY_NAME` | Partner Center `Package/Properties/PublisherDisplayName` (default: `genexis.dev`) |

When `MSSTORE_IDENTITY_NAME` and `MSSTORE_PUBLISHER` are set, tagged releases automatically build `dist/files_utility-<version>-msstore.msix` and upload it to the **GitHub Actions workflow artifact** (`windows-store-msix`) rather than the public GitHub Release (unsigned `--store` packages cannot be sideloaded directly by end users).

#### Local Microsoft Store MSIX Build (Windows)
```powershell
$env:MSSTORE_IDENTITY_NAME = "<YOUR_MSSTORE_IDENTITY_NAME>"
$env:MSSTORE_PUBLISHER = "CN=<YOUR-PUBLISHER-GUID>"
.\scripts\build_windows_store_msix.ps1
# Output location: dist/files_utility-<version>-msstore.msix
```

#### Partner Center Pre-Submission Checks
- **WACK Verification:** On Windows, run the **Windows App Certification Kit (WACK)** against the built release/package before uploading to Partner Center.
- **`runFullTrust` Justification:** Flutter Windows desktop apps automatically declare the `runFullTrust` restricted capability. Provide a clear explanation in Partner Center notes explaining that Files Utility is a Win32 desktop utility built with Flutter that performs user-initiated operations across local drives, NAS/SMB shares, and FTP/SFTP servers.
- **Privacy Policy URL:** Link to [`PRIVACY.md`](PRIVACY.md) (`https://github.com/bluegene37/files_utility/blob/main/PRIVACY.md`).

### macOS Disk Image (.dmg)
```bash
# Package, sign with Developer ID Application, and create DMG:
./scripts/build_macos_dmg.sh

# Output location: build/macos/Files Utility-<version>.dmg
```

For local automated notarization, store your credentials once in Keychain (and optionally set `MACOS_SIGNING_IDENTITY` / `NOTARY_PROFILE` in your shell):
```bash
xcrun notarytool store-credentials "files-utility-notary" \
  --apple-id "<your-apple-id@example.com>" \
  --team-id "<YOUR_TEAM_ID>" \
  --password "<your-app-specific-password>"
```

### Application Icons
Master source is `assets/icon/app_icon.png`. To regenerate all platform icons:
```bash
dart run flutter_launcher_icons
```

---

## 🔐 Code Signing & Platform Notarization Status

| Platform | Current Status | User Experience & Workaround | Production Remedy |
| :--- | :--- | :--- | :--- |
| **Windows (`.exe`)** | **Unsigned by default — signing wired up, awaiting a certificate** | Microsoft Defender SmartScreen warns "Windows protected your PC / Unknown Publisher". Users click **More info** $\rightarrow$ **Run anyway**. | Add the two repository secrets below; `release.yml` then signs automatically via `signtool.exe`. |
<!-- Gene - Nov, 23, 2026: Distinguish Microsoft Store MSIX signing from local sideloaded MSIX -->
<!-- | **Windows (`.msix`)** | **Self-signed** | Requires installing the publisher certificate into the local `Trusted People` certificate store. | Acquire Microsoft Partner Center certificate or sign with organization CA. | -->
| **Windows Microsoft Store (`.msix`)** | **Signed by Microsoft upon Store ingestion (`--store`)** | Trusted automatically by Windows when installed via Microsoft Store; no manual certificate purchase required. | Configure `MSSTORE_*` GitHub Secrets and upload the `windows-store-msix` CI artifact to Partner Center. |
| **Windows (`.msix`, local sideload)** | **Self-signed / Test certificate** | Requires installing the test certificate into the local `Trusted People` certificate store. | Use Microsoft Store distribution or sign with a trusted organization CA certificate. |
<!-- Gene - Oct, 07, 2026: Updated macOS signing status to Developer ID Application signed with notarization pipeline -->
<!-- Previous implementation:
| **macOS (`.dmg`)** | **Unsigned / Not Notarized** | Apple Gatekeeper blocks untrusted execution on first launch. Users right-click `.app` in `/Applications` $\rightarrow$ **Open**, or run: `xattr -dr com.apple.quarantine "/Applications/Files Utility.app"`. | Join Apple Developer Program, sign with Developer ID Application certificate, and notarize via `xcrun notarytool`. |
-->
| **macOS (`.dmg`)** | **Developer ID Signed & Notarization Pipeline Enabled** | Fully trusted and verified by Apple Gatekeeper when signed with Developer ID Application and notarized. | Configured with `Developer ID Application: <Your Name> (<YOUR_TEAM_ID>)` (via `MACOS_SIGNING_IDENTITY` or local Keychain auto-detection) and Hardened Runtime; automated via `scripts/build_macos_dmg.sh` and CI. |
