import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:logging/logging.dart';

class LocalDbService {
  static final LocalDbService _instance = LocalDbService._internal();
  factory LocalDbService() => _instance;
  LocalDbService._internal();

  final Logger _log = Logger('LocalDbService');
  Map<String, dynamic> _config = {};
  String _profileId = 'default';

  String get currentProfileId => _profileId;

  Future<File> _getConfigFile() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final appDir = Directory(p.join(docsDir.path, 'FilesUtility'));
    if (!await appDir.exists()) {
      await appDir.create(recursive: true);
    }
    return File(p.join(appDir.path, 'config_$_profileId.json'));
  }

  Future<void> init(String profileId) async {
    _profileId = profileId;
    _config = {}; // Reset config when switching profiles
    try {
      final file = await _getConfigFile();
      if (await file.exists()) {
        final contents = await file.readAsString();
        if (contents.isNotEmpty) {
          _config = jsonDecode(contents) as Map<String, dynamic>;
        }
      }
    } catch (e, stack) {
      _log.severe('Failed to initialize LocalDbService', e, stack);
      _config = {};
    }
  }

  Future<void> _saveConfig() async {
    try {
      final file = await _getConfigFile();
      final contents = const JsonEncoder.withIndent('  ').convert(_config);
      await file.writeAsString(contents);
    } catch (e, stack) {
      _log.severe('Failed to save config', e, stack);
    }
  }

  dynamic get(String key) => _config[key];

  String? getString(String key) => _config[key] as String?;
  
  Future<void> setString(String key, String value) async {
    _config[key] = value;
    await _saveConfig();
  }

  int? getInt(String key) => _config[key] as int?;

  Future<void> setInt(String key, int value) async {
    _config[key] = value;
    await _saveConfig();
  }

  bool? getBool(String key) => _config[key] as bool?;

  Future<void> setBool(String key, bool value) async {
    _config[key] = value;
    await _saveConfig();
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
    await _saveConfig();
  }

  Future<void> remove(String key) async {
    _config.remove(key);
    await _saveConfig();
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
