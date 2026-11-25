import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../app_info.dart';
import 'global_db_service.dart';
import 'local_db_service.dart';

class WindowService {
  static final WindowService _instance = WindowService._internal();
  factory WindowService() => _instance;
  WindowService._internal();

  bool _initialized = false;
  // Gene - Nov, 25, 2026: Cache last window title to avoid redundant Win32 SetWindowTextW platform calls.
  String? _lastTitle;

  Future<void> init() async {
    if (_initialized || kIsWeb) return;
    try {
      await windowManager.ensureInitialized();

      // Gene - Nov, 22, 2026: Omit backgroundColor and titleBarStyle from WindowOptions so window_manager does not set isOpaque=false and NSColor.clear on macOS (fixes transparent header bar)
      // const windowOptions = WindowOptions(
      //   size: Size(1280, 840),
      //   minimumSize: Size(980, 680),
      //   center: true,
      //   backgroundColor: Colors.transparent,
      //   skipTaskbar: false,
      //   titleBarStyle: TitleBarStyle.normal,
      //   title: AppInfo.appName,
      // );
      const windowOptions = WindowOptions(
        size: Size(1280, 840),
        minimumSize: Size(980, 680),
        center: true,
        skipTaskbar: false,
        title: AppInfo.appName,
      );

      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });

      _initialized = true;
    } catch (_) {}
  }

  // Gene - Nov, 25, 2026: Build clean window title without status/scanning counter.
  static String buildTitle(String screenName, String profileName) =>
      '${AppInfo.appName} — $screenName [$profileName]';

  Future<void> updateTitle(String screenName, {String? status}) async {
    if (kIsWeb) return;
    if (!_initialized) await init();
    try {
      final currentProfileId = LocalDbService().currentProfileId;
      final currentProfile = GlobalDbService().profiles.firstWhere(
        (p) => p.id == currentProfileId,
        orElse: () => GlobalDbService().profiles.first,
      );

      final String title = buildTitle(screenName, currentProfile.name);
      // Gene - Nov, 25, 2026: Remove live scanning/status counter from the top window title bar; counter remains near the Start button.
      // if (status != null && status.isNotEmpty && status != 'Idle') {
      //   title += ' ($status)';
      // }
      if (title == _lastTitle) return;
      _lastTitle = title;

      await windowManager.setTitle(title);
    } catch (_) {}
  }
}
