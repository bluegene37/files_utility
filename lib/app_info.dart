/// Single source of truth for app identity shown in the UI, window title,
/// and log headers. Keep [appVersion] in sync with the `version:` field in
/// pubspec.yaml when releasing.
class AppInfo {
  AppInfo._();

  static const String appName = 'Files Utility';
  static const String appVersion = '1.1.0';
}
