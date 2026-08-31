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
  static const String appVersion = '1.1.2';
}
