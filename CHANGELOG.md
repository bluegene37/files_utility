# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **In-App Update Checker**: On launch the app checks GitHub Releases (throttled to once per 24h) and offers new versions in an update dialog, with a manual "Check for updates" button on the dashboard. Windows downloads the Inno installer and silently upgrades in place before relaunching; macOS and Linux open the release download page. Users can defer ("Later") or permanently skip a version.

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

[Unreleased]: https://github.com/bluegene37/files_utility/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/bluegene37/files_utility/releases/tag/v1.0.0
