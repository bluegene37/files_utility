import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';
import '../models/app_profile.dart';
import 'app_sqlite_service.dart';

class GlobalDbService {
  static final GlobalDbService _instance = GlobalDbService._internal();
  factory GlobalDbService() => _instance;
  GlobalDbService._internal();

  final Logger _log = Logger('GlobalDbService');
  List<AppProfile> _profiles = [];
  bool _isInitialized = false;

  String? get appDirPath => AppSqliteService().appDirPath;

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      _profiles = await AppSqliteService().getAllProfiles();
      
      // Ensure at least one default profile exists
      if (_profiles.isEmpty) {
        final defaultProfile = AppProfile(id: 'default', name: 'Default Run', description: 'Default configuration');
        await AppSqliteService().saveProfile(defaultProfile);
        _profiles = [defaultProfile];
      }
      
      _isInitialized = true;
    } catch (e, stack) {
      _log.severe('Failed to initialize GlobalDbService', e, stack);
      _profiles = [AppProfile(id: 'default', name: 'Default Run', description: 'Fallback profile')];
      _isInitialized = true;
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
    await AppSqliteService().saveProfile(newProfile);
    return newProfile;
  }

  Future<void> deleteProfile(String id) async {
    if (_profiles.length <= 1) return; // Don't delete the last profile
    _profiles.removeWhere((p) => p.id == id);
    await AppSqliteService().deleteProfile(id);
  }
}
