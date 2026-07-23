import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/app_profile.dart';

class AppSqliteService {
  static final AppSqliteService _instance = AppSqliteService._internal();
  factory AppSqliteService() => _instance;
  AppSqliteService._internal();

  Database? _db;
  bool _isInitializing = false;
  String? appDirPath;

  Future<String> _getAppDirPath() async {
    if (appDirPath != null) return appDirPath!;
    final docsDir = await getApplicationDocumentsDirectory();
    final appDir = Directory(p.join(docsDir.path, 'FilesUtility'));
    if (!await appDir.exists()) {
      await appDir.create(recursive: true);
    }
    appDirPath = appDir.path;
    return appDirPath!;
  }

  Future<Database> get database async {
    if (_db != null && _db!.isOpen) return _db!;
    while (_isInitializing) {
      await Future.delayed(const Duration(milliseconds: 50));
      if (_db != null && _db!.isOpen) return _db!;
    }
    _isInitializing = true;

    try {
      if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }

      final dirPath = await _getAppDirPath();
      final dbPath = p.join(dirPath, 'files_utility.db');
      _db = await openDatabase(
        dbPath,
        version: 1,
        onCreate: (db, version) async {
          // Global Profiles table
          await db.execute('''
            CREATE TABLE profiles (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              description TEXT
            )
          ''');

          // Profile-specific configurations, templates, and settings table
          await db.execute('''
            CREATE TABLE profile_configs (
              profile_id TEXT NOT NULL,
              key TEXT NOT NULL,
              value_type TEXT NOT NULL,
              value TEXT,
              PRIMARY KEY (profile_id, key)
            )
          ''');
        },
      );

      // Automatically migrate legacy JSON files if present
      await _migrateLegacyGlobalProfiles(_db!);
      return _db!;
    } finally {
      _isInitializing = false;
    }
  }

  /// Automatically migrates legacy global_profiles.json to SQLite database.
  Future<void> _migrateLegacyGlobalProfiles(Database db) async {
    try {
      final dirPath = await _getAppDirPath();
      final legacyFile = File(p.join(dirPath, 'global_profiles.json'));
      if (await legacyFile.exists()) {
        final contents = await legacyFile.readAsString();
        if (contents.trim().isNotEmpty) {
          final List<dynamic> jsonList = jsonDecode(contents);
          final batch = db.batch();
          for (final json in jsonList) {
            final profile = AppProfile.fromJson(json as Map<String, dynamic>);
            batch.insert(
              'profiles',
              profile.toJson(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          await batch.commit(noResult: true);
        }
        await legacyFile.rename('${legacyFile.path}.bak');
      }
    } catch (_) {}
  }

  /// Automatically migrates legacy config files to SQLite database.
  Future<void> migrateLegacyProfileConfig(String profileId) async {
    try {
      final db = await database;
      final dirPath = await _getAppDirPath();
      final legacyFile = File(p.join(dirPath, 'config_$profileId.json'));
      if (await legacyFile.exists()) {
        final contents = await legacyFile.readAsString();
        if (contents.trim().isNotEmpty) {
          final Map<String, dynamic> config = jsonDecode(contents) as Map<String, dynamic>;
          final batch = db.batch();
          config.forEach((key, val) {
            String valueType = 'string';
            String valStr = val.toString();

            if (val is int) {
              valueType = 'int';
            } else if (val is bool) {
              valueType = 'bool';
            } else if (val is List || val is Map) {
              valueType = 'json';
              valStr = jsonEncode(val);
            }

            batch.insert(
              'profile_configs',
              {
                'profile_id': profileId,
                'key': key,
                'value_type': valueType,
                'value': valStr,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          });
          await batch.commit(noResult: true);
        }
        await legacyFile.rename('${legacyFile.path}.bak');
      }
    } catch (_) {}
  }

  // --- Profile Operations ---

  Future<List<AppProfile>> getAllProfiles() async {
    final db = await database;
    final maps = await db.query('profiles');
    return maps.map((json) => AppProfile.fromJson(json)).toList();
  }

  Future<void> saveProfile(AppProfile profile) async {
    final db = await database;
    await db.insert(
      'profiles',
      profile.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteProfile(String profileId) async {
    final db = await database;
    await db.delete('profiles', where: 'id = ?', whereArgs: [profileId]);
    await db.delete('profile_configs', where: 'profile_id = ?', whereArgs: [profileId]);
  }

  // --- Profile Config / Template Operations ---

  Future<Map<String, dynamic>> loadProfileConfig(String profileId) async {
    await migrateLegacyProfileConfig(profileId);
    final db = await database;
    final rows = await db.query(
      'profile_configs',
      where: 'profile_id = ?',
      whereArgs: [profileId],
    );

    final Map<String, dynamic> result = {};
    for (final row in rows) {
      final key = row['key'] as String;
      final type = row['value_type'] as String;
      final valStr = row['value'] as String?;

      if (valStr == null) continue;

      if (type == 'int') {
        result[key] = int.tryParse(valStr);
      } else if (type == 'bool') {
        result[key] = valStr.toLowerCase() == 'true';
      } else if (type == 'json') {
        try {
          result[key] = jsonDecode(valStr);
        } catch (_) {
          result[key] = valStr;
        }
      } else {
        result[key] = valStr;
      }
    }
    return result;
  }

  Future<void> setProfileConfigValue(String profileId, String key, dynamic value) async {
    final db = await database;
    if (value == null) {
      await db.delete(
        'profile_configs',
        where: 'profile_id = ? AND key = ?',
        whereArgs: [profileId, key],
      );
      return;
    }

    String valueType = 'string';
    String valStr = value.toString();

    if (value is int) {
      valueType = 'int';
    } else if (value is bool) {
      valueType = 'bool';
    } else if (value is List || value is Map) {
      valueType = 'json';
      valStr = jsonEncode(value);
    }

    await db.insert(
      'profile_configs',
      {
        'profile_id': profileId,
        'key': key,
        'value_type': valueType,
        'value': valStr,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> removeProfileConfigValue(String profileId, String key) async {
    final db = await database;
    await db.delete(
      'profile_configs',
      where: 'profile_id = ? AND key = ?',
      whereArgs: [profileId, key],
    );
  }
}
