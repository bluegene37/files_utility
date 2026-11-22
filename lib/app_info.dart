/// Single source of truth for app identity shown in the UI, window title,
/// and log headers.
///
/// [appVersion] is also the version `UpdateService` compares against the
/// latest GitHub release tag, so it must equal the `version:` field in
/// pubspec.yaml. When it lags, the shipped build installs an update,
/// restarts, still reports the old version, and offers the same update
/// again. `test/update/version_consistency_test.dart` enforces the match.
class AppInfo {
  AppInfo._();

  static const String appName = 'Files Utility';
  // Gene - Nov, 22, 2026: Bump appVersion to 1.2.0 to stay synchronized with pubspec.yaml
  // static const String appVersion = '1.1.2';
  static const String appVersion = '1.2.0';
}
