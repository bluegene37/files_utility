# Security Policy

The **Files Utility** maintainers take security and user data integrity seriously. This document outlines supported versions, security architecture principles, and our responsible disclosure process.

---

## 🛡️ Supported Versions

We provide security updates and patches for the following versions:

| Version | Supported          | Notes |
| :--- | :--- | :--- |
| `1.0.x` | :white_check_mark: | Current stable release line |
| `< 1.0.0` | :x:                | Pre-release / unsupported |

---

## 🔒 Security Architecture & Privacy Guarantee

- **Local Execution Only**: Files Utility is designed as a standalone local desktop utility. It does not contain server-side backends or network transmission modules.
- **Zero Telemetry**: No user data, paths, file metadata, or logs are uploaded to any external or cloud servers.
- **Data Retention**: All SQLite databases, run records, and log files are stored exclusively within the local user directory (`~/Documents/FilesUtility/`).
- **Atomic Operations**: File moves across storage volumes utilize temporary `.part` staging files, parity verification, and atomic swap logic to prevent data loss or corruption during power cuts or network disconnects.

---

## 🚨 Reporting a Vulnerability

If you discover a security vulnerability or potential data loss risk in Files Utility, please **do NOT report it publicly** on GitHub Issues.

Instead, please report the vulnerability privately:

1. **Email**: Send detailed vulnerability reports to `security@genexis.dev` (or reach out directly via maintainer contact on GitHub).
2. **Details to Include**:
   - Description of the vulnerability or data corruption vector.
   - Operating system and Files Utility version where the issue was reproduced.
   - Minimal reproduction steps or sample script/folder structure.
   - Potential impact (e.g., unauthorized file deletion, path traversal, privilege escalation).
3. **Response Timeline**:
   - We will acknowledge receipt of your vulnerability report within **48 hours**.
   - A triage status and timeline for a patch will be provided within **5 business days**.
   - Once a fix is verified, a patch release will be published alongside public credit to the reporter (if desired).
