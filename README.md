# Files Utility

A Flutter desktop app for moving, copying, counting, and cleaning up files
between servers, network shares, and NAS locations. Built for long-running,
unattended runs over SMB/network paths: work happens in background isolates,
progress is checkpointed so interrupted runs resume, and every run writes a
tagged log file plus a history record.

## Features

- **Transfer (move)** — moves files from a source tree to a destination,
  preserving the folder structure. Fast rename when source and destination are
  on the same volume; otherwise a verified copy-then-delete (copy to a `.part`
  temp file, size check, swap into place, only then delete the source).
  Optional year/month organization when a date range filter is active.
- **Copy** — one or many source→destination directory pairs with run ordering,
  concurrency limited to be gentle on SMB shares, and skip-if-already-exists
  detection (name + size). Resumable per directory.
- **Delete** — removes files whose modified date falls in a selected year/month
  set, then prunes empty folders.
- **Count** — dry-run style inventory of files/folders under a target path.
- **Filters** — age ("older than N days/months/years") or date-range, per
  operation, with an option to skip subfolders.
- **Scheduling** — optional run window (e.g. only 00:00–06:00 on selected
  weekdays). Runs pause outside the window and resume automatically; completed
  runs can re-arm for the next window.
- **Profiles** — independent configurations (paths, filters, schedules) with
  their own run history, selectable at startup.
- **History & logs** — every run gets a Run ID; summary records go to SQLite
  and detailed logs to per-run log files.
- **Progress resume** — long scans checkpoint the last scanned directory so a
  crash or stop doesn't restart from zero.

## App data locations

All app data lives under `Documents/FilesUtility/`:

| Path         | Contents                                    |
| ------------ | ------------------------------------------- |
| `files_utility.db` | Profiles, per-profile settings, global settings |
| `database/`  | Per-profile run history (`history_<profile>.db`) |
| `logs/`      | Per-run log files (`<Operation>_<datetime>_<RunID>.log`) |
| `progress/`  | Resume checkpoints for interrupted runs     |

## Development

```bash
flutter pub get
flutter analyze
dart format --set-exit-if-changed lib test
flutter test
flutter run -d windows   # or -d macos
```

## Releasing (Windows)

Version lives in two places — keep them in sync:

1. `pubspec.yaml` → `version:` (and `msix_version` for MSIX)
2. `lib/app_info.dart` → `AppInfo.appVersion` (shown in the UI and log headers)

Build the app and the Inno Setup installer (requires
[Inno Setup](https://jrsoftware.org/isinfo.php) installed on the build machine):

```bash
flutter build windows --release
dart run inno_bundle:build --release --no-app
```

The installer lands in `build/windows/x64/installer/`. Alternatively build an
MSIX package for store/enterprise distribution:

```bash
dart run msix:create
```

Regenerate the Windows app icon after changing `assets/images/app_icon.png`:

```bash
dart run flutter_launcher_icons
```

Tagging a release as `v*` (e.g. `v1.1.0`) triggers the GitHub Actions release
workflow, which builds the Windows app + installer and attaches the installer
to a GitHub Release.
