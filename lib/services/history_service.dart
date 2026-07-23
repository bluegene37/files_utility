import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/run_record.dart';
import 'global_db_service.dart';

class HistoryService {
  static final HistoryService _instance = HistoryService._internal();
  factory HistoryService() => _instance;
  HistoryService._internal();

  static String get _logDirectory {
    final appDir = GlobalDbService().appDirPath ?? p.join(Directory.systemTemp.path, 'file_transfer');
    return p.join(appDir, 'logs');
  }
  String _profileId = 'default';

  String get _historyFile => p.join(_logDirectory, 'run_history_$_profileId.json');

  bool _directoryVerified = false;

  void init(String profileId) {
    _profileId = profileId;
    _directoryVerified = false;
  }

  Future<void> _ensureDirectory() async {
    if (_directoryVerified) return;
    final dir = Directory(_logDirectory);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _directoryVerified = true;
  }

  /// Loads all historical run records. Records persist permanently until explicitly cleared.
  Future<List<RunRecord>> loadHistory() async {
    try {
      await _ensureDirectory();
      final file = File(_historyFile);
      if (!await file.exists()) {
        return [];
      }
      
      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];

      final List<dynamic> jsonList = jsonDecode(content);
      return jsonList.map((json) => RunRecord.fromJson(json as Map<String, dynamic>)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Permanently saves a new run record. History is preserved indefinitely.
  Future<void> saveRecord(RunRecord record) async {
    try {
      final history = await loadHistory();
      history.insert(0, record); // prepend newest run
      
      await _ensureDirectory();
      final file = File(_historyFile);
      
      final jsonString = jsonEncode(history.map((r) => r.toJson()).toList());
      await file.writeAsString(jsonString);
    } catch (_) {
      // Ignore write failures to prevent disrupting active operations
    }
  }

  /// Deletes history only when explicitly requested by user.
  Future<void> clearHistory() async {
    try {
      await _ensureDirectory();
      final file = File(_historyFile);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Ignore cleanup errors
    }
  }
}
