<!-- Gene - Nov, 23, 2026: Add Privacy Policy for Files Utility (Microsoft Store submission requirement) -->
# Privacy Policy for Files Utility

**Publisher:** genexis.dev  
**Effective Date:** November 23, 2026

**Files Utility** is a desktop file operations utility. We respect your privacy and designed the application to operate completely on your own device and the storage locations you configure.

## 1. Data Collection & Telemetry
- **No personal data collection:** Files Utility does **not** collect, transmit, sell, or share personal information, usage analytics, crash reports, advertising identifiers, or telemetry with the developer or any third party.
- **No accounts or tracking:** The application requires no user registration and contains no third-party tracking SDKs or advertisements.

## 2. Local Storage Only
All application data remains strictly on your local machine:
- Profiles, transfer/copy/delete/count/FTP configurations, SQLite run history, checkpoint markers, and plaintext run logs are stored locally under your `Documents/FilesUtility/` directory and OS-managed application preferences (`SharedPreferences`).
- Configured FTP/FTPS/FTPES/SFTP credentials are stored locally on your device in obfuscated form and are masked in run logs and history entries.
- Exported JSON configuration files exclude usernames and passwords so backups can be shared safely.

## 3. Network Access & External Connections
- **User-configured servers & shares:** Network connections are made only when you explicitly run or test operations against local network/SMB/NAS shares or FTP/FTPS/FTPES/SFTP servers that you configure.
- **Software updates:**
  - **Microsoft Store builds:** All updates are delivered and managed exclusively by the Microsoft Store; external update checks are disabled.
  - **Direct GitHub Releases builds:** Checks the public GitHub Releases API (`api.github.com`) at most once every 24 hours (or when manually requested) to compare the installed app version against the latest public release tag. No personal or system identifiers are transmitted beyond standard HTTP request headers (`Files Utility/<version>`).

## 4. Data Retention & Deletion
You retain full control over all locally stored files. You may delete individual profiles inside the app or remove the `Documents/FilesUtility/` folder and uninstall the application at any time to permanently erase all local data.

## 5. Contact & Support
If you have questions about this privacy policy or Files Utility, please open an issue on the project repository:  
[https://github.com/bluegene37/files_utility/issues](https://github.com/bluegene37/files_utility/issues)
