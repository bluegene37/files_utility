# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

<!-- Gene - Nov, 24, 2026: Added v1.2.4 changelog entry covering FTP scheduling enhancements, Store publishing automation, and CI/test fixes -->
## [1.2.4] - 2026-11-24

### Added
- **Per-Source FTP Scheduling, Date Filters & Run Selected**: Added per-source weekly/monthly scheduling, per-source date filter overrides, monthly completion tracking/reset, and a **Run Selected** picker for targeted FTP uploads.
- **Global Weekly Presets & Monthly FTP Schedule**: Added quick weekly schedule presets (Weekdays, Weekends, Sat Only, Sun Only) and once-a-month global FTP scheduling.
- **Automated Microsoft Store MSIX Publishing**: Added automated `msstore` CLI publishing and MSIX content verification in `.github/workflows/release.yml` (with manual `publish_to_store`/`store_draft` `workflow_dispatch` inputs) and documentation in `RELEASING.md`.

### Fixed
- **FTP Settings Cross-Profile Save Guard**: Prevented in-flight `FtpFilesProvider._writeSettings()` writes from leaking settings across profiles or after provider disposal.
- **Deterministic FTP Scan Ordering**: Sorted discovered subdirectories and scanned files alphabetically so upload ordering is consistent across Linux, macOS, and Windows filesystems.
- **Windows Installer Version Parsing & Test Stability**: Anchored the `pubspec.yaml` version regex in `scripts/build_windows_installer.ps1` to ignore commented lines, and hardened FTP provider and path-clearing tests for cross-platform CI stability.

<!-- Gene - Nov, 24, 2026: Added v1.2.2 changelog entry for FTP start/end run-time window and Microsoft Store release pipeline polish -->
## [1.2.2] - 2026-11-24

### Added
- **FTP Start & End Run-Time Window**: Added configurable Start and End run times for scheduled FTP uploads (same-day and overnight midnight-crossover windows), automatic clean shutdown at End time with Repeat re-arming, missed-window handling, `Start == End` unlimited runtime mode, SQLite persistence with legacy migration, and JSON settings export/import support.

### Fixed
- **FTP Screen Layout & Store CI Artifact Isolation**: Wrapped the FTP action/stats bar responsively below `1060px` to prevent overflow at `980x680` when Schedule is enabled; isolated unsigned `windows-store-msix` CI artifacts from public GitHub Releases and guarded `publish-release` to run only on `v*` tag pushes.

<!-- Gene - Nov, 23, 2026: Added v1.2.1 changelog entry for Microsoft Store MSIX release and recent FTP/security updates -->
## [1.2.1] - 2026-11-23

### Added
- **Microsoft Store MSIX Release Pipeline**: Added `scripts/build_windows_store_msix.ps1`, the `build-windows-store` CI job in `.github/workflows/release.yml`, and `PRIVACY.md` for Microsoft Store submissions.
- **Compile-Time Store Update Gate**: Added `STORE_BUILD` support (`AppInfo.isStoreBuild` / `UpdateProvider.updatesDisabled`) to disable GitHub Releases self-update checks and hide the manual update button in Microsoft Store builds.
- **FTP Progress, Reconnect & JSON Import/Export**: Added live per-file FTP upload progress, idle reconnect recovery, configurable log retention pruning, `config.ini`/`.env` migration import, and credential-free JSON Import/Export for FTP and Copy settings.

### Changed
- **Store-Compliant MSIX Icon Scaling**: Switched `msix_config.logo_path` in `pubspec.yaml` from `.ico` to `assets/icon/app_icon.png` (`1024x1024`) for clean Windows Store tile generation.

### Security
- **Zero-Secrets Cleanup**: Removed credentials, personal identities, and internal server names from repository files and settings exports.

<!-- Gene - Nov, 22, 2026: Added v1.2.0 changelog entry -->
## [1.2.0] - 2026-11-22

### Added
- **FTP Upload Module**: Native FTP/FTPS/FTPES/SFTP upload support (`ftpconnect`) with V1 automation, obfuscated credential storage, per-profile settings, and operational window scheduler.
- **Transfer Quick Presets**: Quick date-range presets for configuring file transfer filters faster.
- **Signed & Notarized macOS Packaging**: Apple Developer ID code signing, Hardened Runtime entitlements, and automated Apple Notarization & stapling in `scripts/build_macos_dmg.sh`.

### Changed
- **Modern Soft Neumorphism Theme**: Upgraded light and dark themes across all screens, cards, inputs, tables, and dialogs to a Batterie-matched Soft Slate & Dark Slate neumorphic palette.

### Fixed
- **Opaque macOS Header Bar**: Stopped passing `backgroundColor: Colors.transparent` and `titleBarStyle: TitleBarStyle.normal` to `WindowOptions` and explicitly enforced `isOpaque = true`, `titlebarAppearsTransparent = false`, and `NSColor.windowBackgroundColor` in `MainFlutterWindow.swift`.
- **Transfer Date Filter & Update Cache**: Fixed Transfer date filter path nesting and defaults, and ensured corrupt cached release JSON no longer breaks startup update checks.

## [1.1.0] - 2026-08-30

### Added
- **Linux Platform Support**: GTK desktop target with `.tar.gz` and `.deb` packaging (`scripts/build_linux_packages.sh`) and a `.desktop` entry, wired into the CI and release workflows.
- **In-App Update Checker**: On launch the app checks GitHub Releases (throttled to once per 24h) and offers new versions in an update dialog, with a manual "Check for updates" button on the dashboard. Windows downloads the Inno installer and silently upgrades in place before relaunching; macOS and Linux open the release download page. Users can defer ("Later") or permanently skip a version.
- **In-App User Manual**: Searchable manual dialog covering every operation, reachable from a help button on each screen and from the `F1` shortcut, with contextual keyboard shortcuts throughout the app.

### Changed
- Refreshed the theme colour palettes and made light mode the default.

### Fixed
- **Delete/Copy/Transfer/Count no longer escape the folder you selected.** The file walkers list with `followLinks: false` but then re-followed symbolic links by hand, with no check that the target stayed inside the chosen root. A symlink inside a Delete target could cause files *outside* it to be deleted. All five link-handling sites now resolve the real path and skip anything that falls outside the root, failing closed when a path cannot be resolved.
- **Transfer no longer overwrites an existing destination file.** A move wrote straight over the destination and then deleted the source, leaving no copy of the file that was already there. Name clashes are now skipped, logged, and counted so they surface in the run summary.
- **Cleared path fields stay cleared.** Source/Destination/Target were only persisted when non-null, so a field you cleared silently came back from the database on the next profile switch or app start — including the Delete target.
- **Transfer resume state is loaded before the UI reports it**, so a run started immediately after launch no longer reads a null resume marker and loses its resume point.

## [1.0.0] - 2026-08-27

### Added
- **Batch Transfer Engine**: High-performance same-volume renaming and cross-volume verified copy-then-delete with atomic swap and size check.
- **Batch Copy Engine**: Multi-source to multi-destination directory synchronization with configurable execution ordering and SMB rate-limiting.
- **Batch Delete Engine**: Targeted file purging based on modification timestamp matching (selected years and months) with automatic empty folder cleanup.
- **Dry-Run Count Engine**: Fast filesystem traversal auditing file quantities, folder hierarchy, and total volume footprint.
- **Filtering System**: Time-based filtering supporting age threshold ("older than N days/months/years"), custom date intervals, and recursive/shallow scans.
- **Execution Scheduler**: Configurable operational windows (e.g. 00:00–06:00 on designated weekdays) with auto-pause, auto-resume, and cycle re-arming.
- **Profiles Management**: Multiple isolated configurations with dedicated run parameters and independent SQLite history stores.
- **Persistence & Audit Trail**: SQLite per-profile history database recording metrics per `RunID` and timestamped plaintext audit logs.
- **Resumption & Checkpointing**: Real-time progress checkpointing allowing interrupted scans to resume from the last scanned directory.
- **Multi-Platform UI**: Modern desktop interface with warm theme palette, light/dark mode support, responsive layouts, and system tray / window management.
- **Platform Packaging**: Inno Setup Windows installer script (`inno_bundle`), MSIX packaging configuration, and macOS DMG packaging automation script (`scripts/build_macos_dmg.sh`).
- **Continuous Integration & Delivery**: GitHub Actions workflows for multi-platform quality checks (`ci.yml`) and automated binary release publishing (`release.yml`).
- **Community Health**: Issue templates for bug reports and feature requests, pull request checklist, and security policy.

### Changed
- Brand identity synchronized to `genexis.dev` (`dev.genexis.filesutility`) across macOS, Windows, and Web bundle identifiers.
- Generated full-bleed 1024x1024 application icons across macOS `.xcassets`, Windows `.ico`, and Web icons.

### Security
- Complete offline design: zero external network dependencies, zero telemetry, and local-only data persistence in `Documents/FilesUtility/`.

<!-- Gene - Nov, 22, 2026: Updated changelog comparison links for v1.2.0 -->
<!-- [Unreleased]: https://github.com/bluegene37/files_utility/compare/v1.1.0...HEAD -->
[Unreleased]: https://github.com/bluegene37/files_utility/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/bluegene37/files_utility/compare/v1.1.2...v1.2.0
[1.1.0]: https://github.com/bluegene37/files_utility/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/bluegene37/files_utility/releases/tag/v1.0.0
