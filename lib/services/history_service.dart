import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/run_record.dart';
import 'global_db_service.dart';

class HistoryService {
  static final HistoryService _instance = HistoryService._internal();
  factory HistoryService() => _instance;
  HistoryService._internal();

  Database? _db;
  Future<Database>? _openingDb;
  String _profileId = 'default';

  static String get _baseDirectory {
    final appDir =
        GlobalDbService().appDirPath ??
        p.join(Directory.systemTemp.path, 'files_utility');
    return p.join(appDir, 'database');
  }

  static String get _legacyLogDirectory {
    final appDir =
        GlobalDbService().appDirPath ??
        p.join(Directory.systemTemp.path, 'files_utility');
    return p.join(appDir, 'logs');
  }

  void init(String profileId) {
    if (_profileId != profileId) {
      _profileId = profileId;
      _db?.close();
      _db = null;
    }
  }

  Future<Database> _getDatabase() {
    if (_db != null && _db!.isOpen) return Future.value(_db);
    // Share one opening future so concurrent callers don't race to open
    // the database twice.
    return _openingDb ??= _openDb().whenComplete(() => _openingDb = null);
  }

  Future<Database> _openDb() async {
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
        await db.execute(
          'CREATE INDEX idx_operation ON run_history(operation)',
        );
        await db.execute(
          'CREATE INDEX idx_startTime ON run_history(startTime DESC)',
        );
      },
    );

    // Perform automatic one-time migration from legacy JSON file if exists
    await _migrateLegacyJsonHistory(_db!);

    return _db!;
  }

  /// Automatically migrates existing JSON history into SQLite database on first load.
  Future<void> _migrateLegacyJsonHistory(Database db) async {
    try {
      final legacyFile = File(
        p.join(_legacyLogDirectory, 'run_history_$_profileId.json'),
      );
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

  /// Loads history records sorted by startTime descending across ALL profiles by default.
  Future<List<RunRecord>> loadHistory({
    String operation = 'All',
    bool allProfiles = true,
  }) async {
    try {
      if (!allProfiles) {
        return await _loadSingleProfileHistory(
          _profileId,
          operation: operation,
        );
      }

      final profiles = GlobalDbService().profiles;
      final Set<String> loadedProfileIds = {};
      final List<RunRecord> combinedRecords = [];

      for (final profile in profiles) {
        loadedProfileIds.add(profile.id);
        final recs = await _loadSingleProfileHistory(
          profile.id,
          operation: operation,
        );
        combinedRecords.addAll(recs);
      }

      // Also check any legacy or orphaned profile db files in _baseDirectory
      try {
        final dir = Directory(_baseDirectory);
        if (await dir.exists()) {
          final entities = await dir.list().toList();
          for (final entity in entities) {
            if (entity is File &&
                p.basename(entity.path).startsWith('history_') &&
                entity.path.endsWith('.db')) {
              final filename = p.basename(entity.path);
              final pId = filename.substring(
                'history_'.length,
                filename.length - '.db'.length,
              );
              if (!loadedProfileIds.contains(pId)) {
                loadedProfileIds.add(pId);
                final recs = await _loadSingleProfileHistory(
                  pId,
                  operation: operation,
                );
                combinedRecords.addAll(recs);
              }
            }
          }
        }
      } catch (_) {}

      // Remove duplicates by id if any
      final Map<String, RunRecord> uniqueMap = {};
      for (final r in combinedRecords) {
        uniqueMap[r.id] = r;
      }

      final uniqueRecords = uniqueMap.values.toList();
      uniqueRecords.sort((a, b) => b.startTime.compareTo(a.startTime));
      return uniqueRecords;
    } catch (e) {
      return [];
    }
  }

  Future<List<RunRecord>> _loadSingleProfileHistory(
    String profileId, {
    String operation = 'All',
  }) async {
    try {
      final dbPath = p.join(_baseDirectory, 'history_$profileId.db');
      final file = File(dbPath);
      if (!await file.exists()) return [];

      final db = await openDatabase(dbPath, version: 1);
      List<Map<String, dynamic>> maps;

      if (operation == 'All') {
        maps = await db.query('run_history', orderBy: 'startTime DESC');
      } else {
        maps = await db.query(
          'run_history',
          where: 'operation = ?',
          whereArgs: [operation],
          orderBy: 'startTime DESC',
        );
      }
      await db.close();

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

  /// Clears history from SQLite database across all profiles or specific operation.
  Future<void> clearHistory({
    String operation = 'All',
    bool allProfiles = true,
  }) async {
    try {
      if (allProfiles) {
        final profiles = GlobalDbService().profiles;
        final Set<String> loadedProfileIds = {};
        for (final profile in profiles) {
          loadedProfileIds.add(profile.id);
          await _clearSingleProfileHistory(profile.id, operation: operation);
        }
        try {
          final dir = Directory(_baseDirectory);
          if (await dir.exists()) {
            final entities = await dir.list().toList();
            for (final entity in entities) {
              if (entity is File &&
                  p.basename(entity.path).startsWith('history_') &&
                  entity.path.endsWith('.db')) {
                final filename = p.basename(entity.path);
                final pId = filename.substring(
                  'history_'.length,
                  filename.length - '.db'.length,
                );
                if (!loadedProfileIds.contains(pId)) {
                  loadedProfileIds.add(pId);
                  await _clearSingleProfileHistory(pId, operation: operation);
                }
              }
            }
          }
        } catch (_) {}
      } else {
        await _clearSingleProfileHistory(_profileId, operation: operation);
      }
    } catch (_) {
      // Ignore clear failures
    }
  }

  Future<void> _clearSingleProfileHistory(
    String profileId, {
    String operation = 'All',
  }) async {
    try {
      final dbPath = p.join(_baseDirectory, 'history_$profileId.db');
      final file = File(dbPath);
      if (!await file.exists()) return;

      final db = await openDatabase(dbPath, version: 1);
      if (operation == 'All') {
        await db.delete('run_history');
      } else {
        await db.delete(
          'run_history',
          where: 'operation = ?',
          whereArgs: [operation],
        );
      }
      await db.close();
    } catch (_) {}
  }
}
