# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/bluegene37/files_utility/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/bluegene37/files_utility/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/bluegene37/files_utility/releases/tag/v1.0.0
