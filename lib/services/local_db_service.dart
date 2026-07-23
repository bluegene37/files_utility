import 'package:logging/logging.dart';
import 'app_sqlite_service.dart';

class LocalDbService {
  static final LocalDbService _instance = LocalDbService._internal();
  factory LocalDbService() => _instance;
  LocalDbService._internal();

  final Logger _log = Logger('LocalDbService');
  Map<String, dynamic> _config = {};
  String _profileId = 'default';

  String get currentProfileId => _profileId;

  Future<void> init(String profileId) async {
    _profileId = profileId;
    _config = {}; // Reset config when switching profiles
    try {
      _config = await AppSqliteService().loadProfileConfig(_profileId);
    } catch (e, stack) {
      _log.severe('Failed to initialize LocalDbService', e, stack);
      _config = {};
    }
  }

  dynamic get(String key) => _config[key];

  String? getString(String key) => _config[key] as String?;
  
  Future<void> setString(String key, String value) async {
    _config[key] = value;
    await AppSqliteService().setProfileConfigValue(_profileId, key, value);
  }

  int? getInt(String key) => _config[key] as int?;

  Future<void> setInt(String key, int value) async {
    _config[key] = value;
    await AppSqliteService().setProfileConfigValue(_profileId, key, value);
  }

  bool? getBool(String key) => _config[key] as bool?;

  Future<void> setBool(String key, bool value) async {
    _config[key] = value;
    await AppSqliteService().setProfileConfigValue(_profileId, key, value);
  }

  List<String>? getStringList(String key) {
    final list = _config[key];
    if (list is List) {
      return list.map((e) => e.toString()).toList();
    }
    return null;
  }

  Future<void> setStringList(String key, List<String> value) async {
    _config[key] = value;
    await AppSqliteService().setProfileConfigValue(_profileId, key, value);
  }

  Future<void> remove(String key) async {
    _config.remove(key);
    await AppSqliteService().removeProfileConfigValue(_profileId, key);
  }

  List<String> getRecentDirectories() {
    return getStringList('recent_directories') ?? [];
  }

  Future<void> addRecentDirectory(String path) async {
    if (path.trim().isEmpty) return;
    final recent = getRecentDirectories();
    if (recent.contains(path)) {
      recent.remove(path);
    }
    recent.insert(0, path);
    if (recent.length > 20) {
      recent.removeLast();
    }
    await setStringList('recent_directories', recent);
  }
}
