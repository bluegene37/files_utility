<div align="center">

<img src="assets/images/app_icon.png" alt="Files Utility Logo" width="128" height="128" />

# Files Utility

**Robust, high-throughput desktop utility for moving, copying, counting, and cleaning up files across network shares, SMB mounts, local drives, and NAS storage.**

[![CI](https://github.com/bluegene37/files_utility/actions/workflows/ci.yml/badge.svg)](https://github.com/bluegene37/files_utility/actions/workflows/ci.yml)
[![Release](https://github.com/bluegene37/files_utility/actions/workflows/release.yml/badge.svg)](https://github.com/bluegene37/files_utility/actions/workflows/release.yml)
[![Flutter](https://img.shields.io/badge/Flutter-%E2%89%A53.10.8-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-%E2%89%A53.0.0-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20macOS%20%7C%20Linux%20%7C%20Web-blue)](#-installation--download-matrix)

</div>

---

## 📖 Overview

**Files Utility** is engineered for reliable, unattended batch operations on high-latency or unstable storage volumes (such as SMB, NFS, NAS, and external drives). 

Unlike standard file managers that freeze or lose state during large directory traversals or network interruptions, Files Utility executes operations inside background Dart isolates, creates real-time checkpoint states for instant resumption, records audit trails in SQLite, and safely validates cross-volume transfers via atomic swap semantics.

---

## ✨ Features & Highlights

- **🚚 Transfer (Move)**:
  - High-performance same-volume renaming (`rename()`) for instant relocations.
  - Safe cross-volume atomic move: copies to a temporary `.part` file, verifies file size parity, swaps into target destination, and only deletes source upon verified transfer.
  - Optional Year/Month folder tree structuring when date-range filters are active.
- **📋 Copy**:
  - Multi-pair directory synchronization with configurable execution order.
  - SMB-friendly concurrency throttling to prevent NAS saturation.
  - Smart collision detection (`skip-if-exists` by exact file name and size matching).
  - Resumable scanning per directory.
- **🗑️ Delete**:
  - Targeted file purging based on modification timestamp matching (selected years and months).
  - Post-delete cleanup passes that automatically prune empty directory trees.
- **📊 Count & Audit**:
  - Rapid dry-run traversal to calculate total file counts, directory depth, and storage consumption without modifying files.
- **🔍 Smart Filtering**:
  - Filter by age threshold ("older than $N$ days/months/years") or custom calendar date ranges.
  - Option to skip recursive subfolders (shallow scans).
- **⏱️ Automated Scheduling**:
  - Restrict execution to off-peak maintenance windows (e.g. `00:00–06:00` on selected days).
  - Automatically pauses outside designated windows and resumes seamlessly when the window re-opens.
  - Continuous re-arming for recurring maintenance cycles.
- **👤 Multi-Profile Isolation**:
  - Store and switch between independent profile configurations (separate paths, filters, schedules, and SQLite history).
- **📝 Resilient State & Logging**:
  - Persistent SQLite history logs per profile with unique `RunID` tracking.
  - Standalone timestamped log files for every run.
  - Continuous directory progress checkpointing so crashes or manual interruptions resume without rescanning from zero.

---

## 📦 Installation & Download Matrix

Precompiled release packages are published on the [GitHub Releases](https://github.com/bluegene37/files_utility/releases) page for each version.

| Platform | Package Format | Distribution File | Notes |
| :--- | :--- | :--- | :--- |
| **Windows** | Inno Setup Installer | `files_utility-setup.exe` | Standard Windows wizard installer with desktop shortcut & uninstaller support. |
| **Windows (Enterprise)** | MSIX Bundle | `files_utility.msix` | Windows package format for enterprise deployment. |
| **macOS** | Apple Disk Image | `Files Utility-<version>.dmg` | Drag-to-`/Applications` image compatible with macOS 11+ (Apple Silicon & Intel). |
| **Linux (Debian/Ubuntu)** | Debian Package | `files-utility_<version>_amd64.deb` | Installs to `/usr/lib/files_utility` with a launcher entry. Requires `libgtk-3-0` and `libsqlite3-0`. |
| **Linux (portable)** | Compressed Bundle | `files_utility-<version>-linux-x64.tar.gz` | Extract anywhere and run `./files_utility`. |
| **Web** | PWA / Static Bundle | `build/web/` | Can be served over any static web host. |

> [!NOTE]
> **macOS First-Launch**: Until an Apple Developer ID signature is attached, Gatekeeper will flag the app on first run. To open: Right-click the app in `/Applications` > select **Open**, or run:
> ```bash
> xattr -dr com.apple.quarantine "/Applications/Files Utility.app"
> ```

---

## 🗂️ App Data & Storage Topology

Files Utility stores all configurations, databases, checkpoints, and logs under the user's `Documents/FilesUtility/` directory:

```text
~/Documents/FilesUtility/
├── files_utility.db       # Global configuration, profile definitions, and active settings
├── database/              # Per-profile SQLite history databases
│   └── history_<profile>.db
├── logs/                  # Detailed per-run log files (<Operation>_<datetime>_<RunID>.log)
└── progress/              # Checkpoint marker files for interrupted scan resumption
```

---

## 🛠️ Local Development & Setup

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (version `^3.10.8` or newer)
- [Dart SDK](https://dart.dev/get-dart) (`^3.0.0`)
- **macOS**: Xcode & Command Line Tools (`xcode-select --install`)
- **Windows**: Visual Studio 2022 (with "Desktop development with C++" workload) and [Inno Setup 6](https://jrsoftware.org/isinfo.php) (`winget install JRSoftware.InnoSetup`)
- **Linux**: GTK3 development headers and Ninja (`sudo apt-get install ninja-build libgtk-3-dev`)

### Quick Start

1. **Clone the repository**:
   ```bash
   git clone https://github.com/bluegene37/files_utility.git
   cd files_utility
   ```

2. **Install dependencies**:
   ```bash
   flutter pub get
   ```

3. **Run static analysis & format check**:
   ```bash
   flutter analyze --fatal-infos
   dart format --output=none --set-exit-if-changed lib test
   ```

4. **Run the test suite**:
   ```bash
   flutter test
   ```

5. **Launch the application in debug mode**:
   ```bash
   # On macOS
   flutter run -d macos

   # On Windows
   flutter run -d windows
   ```

---

## 🚀 Release & Packaging Guide

Full release policies, versioning rules, and signing details are documented in [RELEASING.md](RELEASING.md).

### Build Commands

- **Windows Installer (Inno Setup)**:
  ```bash
  flutter build windows --release
  dart run inno_bundle:build --release --no-app
  # Output: build/windows/x64/installer/
  ```

- **Windows MSIX Bundle**:
  ```bash
  dart run msix:create
  ```

- **macOS DMG Package**:
  ```bash
  ./scripts/build_macos_dmg.sh
  # Output: build/macos/Files Utility-<version>.dmg
  ```

- **Linux Packages (tar.gz + .deb)**:
  ```bash
  ./scripts/build_linux_packages.sh
  # Output: dist/files_utility-<version>-linux-x64.tar.gz
  #         dist/files-utility_<version>_amd64.deb
  ```

- **Update App Icons**:
  ```bash
  # Source master: assets/icon/app_icon.png
  dart run flutter_launcher_icons
  ```

---

## 🛡️ Privacy & Security

- **100% Offline & Local**: Files Utility operates completely on your local machine and local networks.
- **Zero Telemetry**: No analytics, telemetry, tracking tokens, or user data are ever collected or transmitted over the internet.
- **Direct Filesystem Operations**: All SQLite databases, log records, and temporary files remain exclusively in your local `Documents/FilesUtility/` directory.

---

## 🤝 Contributing

Contributions, bug reports, and feature proposals are welcome! Please read our [CONTRIBUTING.md](CONTRIBUTING.md) guide before submitting pull requests, and review our [SECURITY.md](SECURITY.md) for security disclosures.

---

## 📄 License & Credits

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.

Developed & maintained by [genexis.dev](https://github.com/bluegene37).
