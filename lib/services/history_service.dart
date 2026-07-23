import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/run_record.dart';
import 'global_db_service.dart';

class HistoryService {
  static final HistoryService _instance = HistoryService._internal();
  factory HistoryService() => _instance;
  HistoryService._internal();

  Database? _db;
  String _profileId = 'default';
  bool _isInitializing = false;

  static String get _baseDirectory {
    final appDir = GlobalDbService().appDirPath ?? p.join(Directory.systemTemp.path, 'file_transfer');
    return p.join(appDir, 'database');
  }

  static String get _legacyLogDirectory {
    final appDir = GlobalDbService().appDirPath ?? p.join(Directory.systemTemp.path, 'file_transfer');
    return p.join(appDir, 'logs');
  }

  void init(String profileId) {
    if (_profileId != profileId) {
      _profileId = profileId;
      _db?.close();
      _db = null;
    }
  }

  Future<Database> _getDatabase() async {
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

      final dir = Directory(_baseDirectory);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final dbPath = p.join(_baseDirectory, 'history_$_profileId.db');
      _db = await openDatabase(
        dbPath,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE run_history (
              id TEXT PRIMARY KEY,
              operation TEXT NOT NULL,
              startTime TEXT NOT NULL,
              endTime TEXT NOT NULL,
              filesProcessed INTEGER NOT NULL,
              foldersProcessed INTEGER NOT NULL,
              errors INTEGER NOT NULL,
              status TEXT NOT NULL,
              configSummary TEXT,
              sourcePath TEXT,
              destPath TEXT
            )
          ''');
          await db.execute('CREATE INDEX idx_operation ON run_history(operation)');
          await db.execute('CREATE INDEX idx_startTime ON run_history(startTime DESC)');
        },
      );

      // Perform automatic one-time migration from legacy JSON file if exists
      await _migrateLegacyJsonHistory(_db!);

      return _db!;
    } finally {
      _isInitializing = false;
    }
  }

  /// Automatically migrates existing JSON history into SQLite database on first load.
  Future<void> _migrateLegacyJsonHistory(Database db) async {
    try {
      final legacyFile = File(p.join(_legacyLogDirectory, 'run_history_$_profileId.json'));
      if (await legacyFile.exists()) {
        final content = await legacyFile.readAsString();
        if (content.trim().isNotEmpty) {
          final List<dynamic> jsonList = jsonDecode(content);
          final batch = db.batch();
          for (final json in jsonList) {
            final record = RunRecord.fromJson(json as Map<String, dynamic>);
            batch.insert(
              'run_history',
              record.toJson(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          await batch.commit(noResult: true);
        }
        // Backup legacy JSON file after successful migration
        await legacyFile.rename('${legacyFile.path}.bak');
      }
    } catch (_) {
      // Fail safely during migration without blocking app start
    }
  }

  /// Loads all history records sorted by startTime descending.
  Future<List<RunRecord>> loadHistory({String operation = 'All'}) async {
    try {
      final db = await _getDatabase();
      List<Map<String, dynamic>> maps;

      if (operation == 'All') {
        maps = await db.query(
          'run_history',
          orderBy: 'startTime DESC',
        );
      } else {
        maps = await db.query(
          'run_history',
          where: 'operation = ?',
          whereArgs: [operation],
          orderBy: 'startTime DESC',
        );
      }

      return maps.map((json) => RunRecord.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Saves a new run record into SQLite database instantly ($O(1)$).
  Future<void> saveRecord(RunRecord record) async {
    try {
      final db = await _getDatabase();
      await db.insert(
        'run_history',
        record.toJson(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {
      // Ignore save failures to prevent disrupting active operations
    }
  }

  /// Clears history from SQLite database.
  Future<void> clearHistory({String operation = 'All'}) async {
    try {
      final db = await _getDatabase();
      if (operation == 'All') {
        await db.delete('run_history');
      } else {
        await db.delete(
          'run_history',
          where: 'operation = ?',
          whereArgs: [operation],
        );
      }
    } catch (_) {
      // Ignore clear failures
    }
  }
}
