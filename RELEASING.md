# Releasing Files Utility

Files Utility ships for **Windows** (Inno Setup installer, optional MSIX) and
**macOS** (DMG). Releases are built by CI on tag push and attached to a GitHub
Release.

## App identity

| Field | Value |
|---|---|
| Display name | Files Utility |
| Publisher | genexis.dev |
| Bundle / application ID | `dev.genexis.filesutility` |
| Copyright | Copyright © 2026 genexis.dev. All rights reserved. |

The Inno Setup AppId GUID in `pubspec.yaml` (`inno_bundle.id`) is the
installer's **upgrade identity — it must never change**, or existing installs
stop upgrading in place.

## Versioning

`pubspec.yaml` `version:` is the **single source of truth** (`1.0.0+1` =
semantic version `+` build number). When bumping it, also update — all in the
same commit:

1. `pubspec.yaml` → `version:`
2. `pubspec.yaml` → `msix_config.msix_version` (four segments: `1.0.0` → `"1.0.0.0"`)
3. `lib/app_info.dart` → `AppInfo.appVersion` (shown in the UI, window title, and log headers)

The Windows executable's file/product version and the macOS
`CFBundleShortVersionString`/`CFBundleVersion` are injected automatically from
`pubspec.yaml` by the Flutter build — nothing to edit there.

If this app is ever submitted to a store (Microsoft Store, App Store), the
build number (the part after `+`) must **increase monotonically forever**;
never reuse one.

## Release flow (tag push)

```bash
# 1. Bump the version (all three spots above), commit on main.
# 2. Tag and push:
git tag v1.0.1
git push origin main v1.0.1
```

Pushing a `v*` tag triggers `.github/workflows/release.yml`:

- **windows-latest**: `flutter analyze` + `flutter test`, then
  `flutter build windows --release` and `dart run inno_bundle:build --release
  --no-app` (ISCC is preinstalled on the runner) → `setup.exe`
- **macos-latest**: `flutter test`, then `scripts/build_macos_dmg.sh` →
  `Files Utility-<version>.dmg`
- **release job**: attaches both artifacts to the GitHub Release via
  `softprops/action-gh-release`.

`.github/workflows/ci.yml` separately runs analyze/format/test plus a Windows
release build on every push/PR to `main`.

## Local builds

### Windows (on a Windows machine)

Requires [Inno Setup 6](https://jrsoftware.org/isinfo.php)
(`winget install JRSoftware.InnoSetup`) for the installer step.

```bash
flutter build windows --release
dart run inno_bundle:build --release --no-app
```

Installer output: `build/windows/x64/installer/`.

Optional MSIX (for store/enterprise deployment):

```bash
dart run msix:create
```

### macOS

```bash
./scripts/build_macos_dmg.sh
```

Builds the release `.app` and packages `build/macos/Files Utility-<version>.dmg`
with a drag-to-`/Applications` layout.

### Icons

Icon source of truth is `assets/icon/app_icon.png` (a full-bleed processed copy
of `assets/images/app_icon.png`). After changing it:

```bash
dart run flutter_launcher_icons
```

## Signing status

| Platform | Status | Implication |
|---|---|---|
| Windows setup.exe | **Unsigned** | SmartScreen shows "unrecognized app" on first run; users click "More info → Run anyway". Fix: an Authenticode / EV code-signing certificate. |
| Windows MSIX | **Test-signed only** | `msix:create` uses a test certificate; machines must trust it before install. Fine for internal/enterprise deployment with a trusted cert, not for public distribution. |
| macOS DMG | **Unsigned, not notarized** | Gatekeeper blocks the app on other Macs with "cannot be opened because the developer cannot be verified". Users must right-click → Open once, or run `xattr -dr com.apple.quarantine "/Applications/Files Utility.app"`. Fix: Apple Developer ID certificate + notarization (`codesign` + `notarytool`). |

## Pre-release checklist

- [ ] Version bumped in all three spots (pubspec `version:`, `msix_version`, `AppInfo.appVersion`)
- [ ] `flutter analyze --fatal-infos` clean
- [ ] `dart format --output=none --set-exit-if-changed lib test` clean
- [ ] `flutter test` passes
- [ ] CI green on `main`
- [ ] Smoke-test a release build on at least one platform (window title, About header, version string)
- [ ] Changelog / release notes drafted (release notes are auto-generated from PRs, edit after publish if needed)
- [ ] Remember: persisted config keys (`shared_preferences` / SQLite) are live user data — any renamed key needs a migration
- [ ] Tag pushed; verify both artifacts attached to the GitHub Release
