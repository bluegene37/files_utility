import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';
import '../models/app_profile.dart';

class GlobalDbService {
  static final GlobalDbService _instance = GlobalDbService._internal();
  factory GlobalDbService() => _instance;
  GlobalDbService._internal();

  final Logger _log = Logger('GlobalDbService');
  List<AppProfile> _profiles = [];
  bool _isInitialized = false;
  String? appDirPath;

  Future<File> _getGlobalConfigFile() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final appDir = Directory(p.join(docsDir.path, 'FilesUtility'));
    if (!await appDir.exists()) {
      await appDir.create(recursive: true);
    }
    appDirPath = appDir.path;
    return File(p.join(appDir.path, 'global_profiles.json'));
  }

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final file = await _getGlobalConfigFile();
      if (await file.exists()) {
        final contents = await file.readAsString();
        if (contents.isNotEmpty) {
          final List<dynamic> jsonList = jsonDecode(contents);
          _profiles = jsonList.map((json) => AppProfile.fromJson(json as Map<String, dynamic>)).toList();
        }
      }
      
      // Ensure at least one default profile exists
      if (_profiles.isEmpty) {
        _profiles.add(AppProfile(id: 'default', name: 'Default Run', description: 'Default configuration'));
        await _saveProfiles();
      }
      
      _isInitialized = true;
    } catch (e, stack) {
      _log.severe('Failed to initialize GlobalDbService', e, stack);
      _profiles = [AppProfile(id: 'default', name: 'Default Run', description: 'Fallback profile')];
      _isInitialized = true;
    }
  }

  Future<void> _saveProfiles() async {
    try {
      final file = await _getGlobalConfigFile();
      final contents = const JsonEncoder.withIndent('  ').convert(_profiles.map((p) => p.toJson()).toList());
      await file.writeAsString(contents);
    } catch (e, stack) {
      _log.severe('Failed to save global profiles', e, stack);
    }
  }

  List<AppProfile> get profiles => _profiles;

  Future<AppProfile> createProfile(String name, String description) async {
    final newProfile = AppProfile(
      id: const Uuid().v4(),
      name: name,
      description: description,
    );
    _profiles.add(newProfile);
    await _saveProfiles();
    return newProfile;
  }

  Future<void> deleteProfile(String id) async {
    if (_profiles.length <= 1) return; // Don't delete the last profile
    _profiles.removeWhere((p) => p.id == id);
    await _saveProfiles();
  }
}
