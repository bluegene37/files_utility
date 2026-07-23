import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';
import 'global_db_service.dart';
import 'local_db_service.dart';

class WindowService {
  static final WindowService _instance = WindowService._internal();
  factory WindowService() => _instance;
  WindowService._internal();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized || kIsWeb) return;
    try {
      await windowManager.ensureInitialized();
      _initialized = true;
    } catch (_) {}
  }

  Future<void> updateTitle(String screenName, {String? status}) async {
    if (kIsWeb) return;
    if (!_initialized) await init();
    try {
      final currentProfileId = LocalDbService().currentProfileId;
      final currentProfile = GlobalDbService().profiles.firstWhere(
        (p) => p.id == currentProfileId,
        orElse: () => GlobalDbService().profiles.first,
      );

      String title = 'Files Utility — $screenName [${currentProfile.name}]';
      if (status != null && status.isNotEmpty && status != 'Idle') {
        title += ' ($status)';
      }

      await windowManager.setTitle(title);
    } catch (_) {}
  }
}
