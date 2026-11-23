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
  // Gene - Nov, 23, 2026: Bump appVersion to 1.2.1 for Microsoft Store release and gate external updates on STORE_BUILD
  // Gene - Nov, 24, 2026: Bump appVersion to 1.2.2 to stay synchronized with pubspec.yaml
  // static const String appVersion = '1.2.1';
  // static const String appVersion = '1.2.0';
  static const String appVersion = '1.2.2';

  // Gene - Nov, 23, 2026: Support compile-time STORE_BUILD flag to disable external self-updates in Microsoft Store builds
  static const bool isStoreBuild = bool.fromEnvironment(
    'STORE_BUILD',
    defaultValue: false,
  );
}
