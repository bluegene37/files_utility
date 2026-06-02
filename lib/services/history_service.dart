import 'dart:convert';
import 'dart:io';
import '../models/run_record.dart';
import 'global_db_service.dart';

class HistoryService {
  static final HistoryService _instance = HistoryService._internal();
  factory HistoryService() => _instance;
  HistoryService._internal();

  static String get _logDirectory {
    final appDir = GlobalDbService().appDirPath ?? r'C:\temp\file transfer';
    return '$appDir\\logs';
  }
  String _profileId = 'default';

  String get _historyFile => '$_logDirectory\\run_history_$_profileId.json';

  bool _directoryVerified = false;

  void init(String profileId) {
    _profileId = profileId;
  }

  Future<void> _ensureDirectory() async {
    if (_directoryVerified) return;
    final dir = Directory(_logDirectory);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _directoryVerified = true;
  }

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
      // If there's a parsing error or missing file, return empty history
      return [];
    }
  }

  Future<void> saveRecord(RunRecord record) async {
    try {
      final history = await loadHistory();
      history.insert(0, record); // add to the beginning (latest first)
      
      await _ensureDirectory();
      final file = File(_historyFile);
      
      final jsonString = jsonEncode(history.map((r) => r.toJson()).toList());
      await file.writeAsString(jsonString);
    } catch (e) {
      // Silently ignore write failures to not disrupt the main app flow
    }
  }

  Future<void> clearHistory() async {
    try {
      await _ensureDirectory();
      final file = File(_historyFile);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      // Ignore errors
    }
  }
}
