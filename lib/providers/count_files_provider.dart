import 'dart:async';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/file_logger.dart';
import '../services/history_service.dart';
import '../models/run_record.dart';

class CountFilesProvider with ChangeNotifier {
  final FileLogger _fileLogger = FileLogger();
  final NumberFormat _numFmt = NumberFormat('#,##0');

  String? targetPath;
  bool isCounting = false;
  List<String> logs = [];
  String currentStatus = 'Idle';
  int totalFiles = 0;
  int totalFolders = 0;
  int errors = 0;
  bool _stopRequested = false;
  Timer? _refreshTimer;

  CountFilesProvider() {
    _loadSettings();
  }

  void _addLog(String message) {
    final timestamp = DateFormat('HH:mm:ss').format(DateTime.now());
    logs.insert(0, '[$timestamp] $message');
    if (logs.length > 1000) logs.removeLast();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    targetPath = prefs.getString('count_targetPath');
    notifyListeners();
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (targetPath != null) {
      await prefs.setString('count_targetPath', targetPath!);
    }
  }

  Future<void> pickTarget() async {
    final path = await getDirectoryPath(initialDirectory: targetPath);
    if (path != null) {
      targetPath = path;
      _saveSettings();
      _addLog('✓ Target selected: $targetPath');
      notifyListeners();
    }
  }

  void stop() {
    _stopRequested = true;
    currentStatus = '⛔ Stopping...';
    notifyListeners();
  }

  void clearLogs() {
    logs.clear();
    totalFiles = 0;
    totalFolders = 0;
    errors = 0;
    currentStatus = 'Idle';
    notifyListeners();
  }

  void _startTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      notifyListeners();
    });
  }

  void _stopTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    notifyListeners();
  }

  /// Formats elapsed time from the file logger's tracked start time.
  String _getElapsedStr() {
    final start = _fileLogger.getStartTime('Count');
    if (start == null) return '';
    final elapsed = DateTime.now().difference(start);
    if (elapsed.inHours > 0) {
      return '${elapsed.inHours}h ${elapsed.inMinutes.remainder(60)}m ${elapsed.inSeconds.remainder(60)}s';
    } else if (elapsed.inMinutes > 0) {
      return '${elapsed.inMinutes}m ${elapsed.inSeconds.remainder(60)}s';
    } else {
      return '${elapsed.inSeconds}s';
    }
  }

  Future<void> startCounting() async {
    if (targetPath == null) {
      _addLog('✗ Error: No target directory selected.');
      return;
    }

    isCounting = true;
    _stopRequested = false;
    totalFiles = 0;
    totalFolders = 0;
    errors = 0;
    currentStatus = '⏳ Counting...';
    notifyListeners();

    _addLog('⏳ Starting file count...');
    _addLog('  Target: $targetPath');

    await _fileLogger.logRunStart(
      operation: 'Count',
      targetPath: targetPath,
    );

    _startTimer();

    try {
      final targetDir = Directory(targetPath!);
      if (!await targetDir.exists()) {
        _addLog('✗ Error: Target directory does not exist.');
        await _fileLogger.error('Count', 'Target directory does not exist: $targetPath');
        return;
      }

      await _countDirectory(targetDir);

      final elapsed = _getElapsedStr();
      if (_stopRequested) {
        _addLog('⛔ Stopped by user.');
        _addLog('  Count so far — Files: ${_numFmt.format(totalFiles)}, Folders: ${_numFmt.format(totalFolders)} in $elapsed');
      } else {
        _addLog('🏁 Count completed in $elapsed');
        _addLog('  Total Files: ${_numFmt.format(totalFiles)}');
        _addLog('  Total Folders: ${_numFmt.format(totalFolders)}');
      }

      await _fileLogger.info('Count', 'Total Files: $totalFiles');
      await _fileLogger.info('Count', 'Total Folders: $totalFolders');
      if (errors > 0) {
        await _fileLogger.error('Count', 'Errors encountered: $errors');
      }
    } catch (e) {
      _addLog('✗ Critical Error: $e');
      await _fileLogger.error('Count', 'Critical Error: $e');
    } finally {
      await _fileLogger.logRunEnd(
        operation: 'Count',
        filesProcessed: totalFiles,
        errors: errors,
        wasStopped: _stopRequested,
      );

      try {
        final start = _fileLogger.getStartTime('Count') ?? DateTime.now();
        await HistoryService().saveRecord(RunRecord(
          id: _fileLogger.getRunId('Count') ?? 'UNKNOWN',
          operation: 'Count',
          startTime: start,
          endTime: DateTime.now(),
          filesProcessed: totalFiles,
          foldersProcessed: totalFolders,
          errors: errors,
          status: _stopRequested ? 'Stopped' : 'Completed',
          configSummary: 'Target: $targetPath',
        ));
      } catch (_) {}

      isCounting = false;
      currentStatus = 'Idle';
      _stopTimer();
    }
  }

  Future<void> _countDirectory(Directory dir) async {
    try {
      await for (final entity in dir.list(recursive: false, followLinks: false)) {
        if (_stopRequested) return;

        if (entity is File) {
          totalFiles++;
        } else if (entity is Directory) {
          totalFolders++;
          currentStatus = '⏳ Scanning: ${entity.path}';
          await _countDirectory(entity);
        }
      }
    } catch (e) {
      _addLog('✗ Error accessing: ${dir.path} — $e');
      await _fileLogger.error('Count', 'Error accessing: ${dir.path} — $e');
      errors++;
    }
  }
}
