import 'dart:async';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import '../services/file_logger.dart';
import '../services/local_db_service.dart';
import '../services/history_service.dart';
import '../models/run_record.dart';

class DeleteProcessProvider with ChangeNotifier {
  final Logger _log = Logger('DeleteProcessProvider');
  final FileLogger _fileLogger = FileLogger();
  final NumberFormat _numFmt = NumberFormat('#,##0');

  String? targetPath;
  bool isProcessing = false;
  List<String> logs = [];
  String currentStatus = 'Idle';
  int deletedCount = 0;
  int errorCount = 0;
  bool _stopRequested = false;
  Timer? _refreshTimer;

  int selectedYear = 2025;
  List<String> validMonths = ['Jan'];

  List<String> allMonths = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  List<int> get availableYears {
    List<int> years = [];
    int currentYear = DateTime.now().year;
    for (int i = 2010; i <= currentYear + 5; i++) {
      years.add(i);
    }
    return years.reversed.toList();
  }

  DeleteProcessProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final db = LocalDbService();
    targetPath = db.getString('delete_targetPath');
    selectedYear = db.getInt('delete_selectedYear') ?? 2025;
    final savedMonths = db.getStringList('delete_validMonths');
    if (savedMonths != null && savedMonths.isNotEmpty) {
      validMonths = savedMonths;
    }
    notifyListeners();
  }

  Future<void> _saveSettings() async {
    final db = LocalDbService();
    if (targetPath != null) {
      await db.setString('delete_targetPath', targetPath!);
    }
    await db.setInt('delete_selectedYear', selectedYear);
    await db.setStringList('delete_validMonths', validMonths);
  }

  void setYear(int year) {
    selectedYear = year;
    _saveSettings();
    notifyListeners();
  }

  void toggleMonth(String month) {
    if (validMonths.contains(month)) {
      validMonths.remove(month);
    } else {
      validMonths.add(month);
    }
    _saveSettings();
    notifyListeners();
  }

  void _startTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      notifyListeners();
    });
  }

  void _stopTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    notifyListeners(); // Ensure final state is updated
  }

  void _addLog(String message) {
    final timestamp = DateFormat('HH:mm:ss').format(DateTime.now());
    logs.insert(0, '[$timestamp] $message');
    if (logs.length > 1000) logs.removeLast();
    // notifyListeners();
  }

  Future<void> pickTarget() async {
    final path = await getDirectoryPath(initialDirectory: targetPath);
    if (path != null) {
      setTargetPath(path);
      _addLog('✓ Target selected: $targetPath');
    }
  }

  String? _sanitizePath(String? path) {
    if (path == null) return null;
    final clean = path.replaceAll('"', '').replaceAll("'", "").trim();
    return clean.isEmpty ? null : clean;
  }

  void setTargetPath(String? path) {
    targetPath = _sanitizePath(path);
    _saveSettings();
    notifyListeners();
  }

  void stop() {
    _stopRequested = true;
    currentStatus = '⛔ Stopping...';
    notifyListeners();
  }

  void clearLogs() {
    logs.clear();
    deletedCount = 0;
    errorCount = 0;
    currentStatus = 'Idle';
    notifyListeners();
  }

  /// Formats elapsed time from the file logger's tracked start time.
  String _getElapsedStr() {
    final start = _fileLogger.getStartTime('Delete');
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

  Future<void> deleteFiles() async {
    if (targetPath == null) {
      _addLog('✗ Error: No target directory selected.');
      await _fileLogger.error('Delete', 'No target directory selected.');
      return;
    }

    if (validMonths.isEmpty) {
      _addLog('✗ Error: No months selected. Please select at least one month.');
      await _fileLogger.error('Delete', 'No months selected.');
      return;
    }

    isProcessing = true;
    _stopRequested = false;
    deletedCount = 0;
    errorCount = 0;
    currentStatus = '⏳ Starting deletion...';
    notifyListeners();

    _addLog('⏳ Starting deletion...');
    _addLog('  Target: $targetPath');
    _addLog('  Filter: Year $selectedYear, Months ${validMonths.join(', ')}');

    await _fileLogger.logRunStart(
      operation: 'Delete',
      targetPath: targetPath,
      year: selectedYear,
      months: validMonths,
    );

    _startTimer();

    try {
      final targetDir = Directory(targetPath!);
      if (!await targetDir.exists()) {
        _addLog('✗ Error: Target directory does not exist.');
        await _fileLogger.error('Delete', 'Target directory does not exist: $targetPath');
        return;
      }

      await _processDirectory(targetDir);

      final elapsed = _getElapsedStr();
      if (_stopRequested) {
        _addLog('⛔ Stopped by user. Deleted ${_numFmt.format(deletedCount)} files in $elapsed');
      } else {
        _addLog('🏁 Deletion completed: ${_numFmt.format(deletedCount)} deleted, ${_numFmt.format(errorCount)} errors in $elapsed');
      }
    } catch (e, stack) {
      _addLog('✗ Critical Error: $e');
      _log.severe('Critical error during deletion', e, stack);
      await _fileLogger.error('Delete', 'Critical Error: $e\n$stack');
    } finally {
      // Capture before logRunEnd clears them
      final runId = _fileLogger.getRunId('Delete') ?? 'UNKNOWN';
      final start = _fileLogger.getStartTime('Delete') ?? DateTime.now();

      await _fileLogger.logRunEnd(
        operation: 'Delete',
        filesProcessed: deletedCount,
        errors: errorCount,
        wasStopped: _stopRequested,
      );

      try {
        await HistoryService().saveRecord(RunRecord(
          id: runId,
          operation: 'Delete',
          startTime: start,
          endTime: DateTime.now(),
          filesProcessed: deletedCount,
          errors: errorCount,
          status: _stopRequested ? 'Stopped' : 'Completed',
          configSummary: 'Target: $targetPath, Year: $selectedYear, Months: $validMonths',
        ));
      } catch (_) {}

      isProcessing = false;
      currentStatus = 'Idle';
      _stopTimer();
    }
  }

  Future<void> _processDirectory(Directory dir) async {
    try {
      // Process files first
      await for (final entity in dir.list(
        recursive:
            false, // We will recurse manually to handle post-order directory deletion
        followLinks: false,
      )) {
        if (_stopRequested) return;

        if (entity is File) {
          await _checkAndDeleteFile(entity);
        } else if (entity is Directory) {
          await _processDirectory(entity);
        }
      }

      // Check if directory is empty after processing children
      if (dir.path != targetPath) {
        // Don't delete the root target
        if (await _isEmpty(dir)) {
          try {
            await dir.delete();
            _addLog('✓ Deleted empty folder: ${p.basename(dir.path)}');
          } catch (e) {
            _addLog('✗ Failed to delete folder ${p.basename(dir.path)}: $e');
          }
        }
      }
    } catch (e) {
      _addLog('✗ Error scanning directory: $e');
      await _fileLogger.error('Delete', 'Error scanning directory: $e');
      errorCount++;
    }
  }

  Future<bool> _isEmpty(Directory dir) async {
    try {
      return await dir.list().isEmpty;
    } catch (e) {
      return false;
    }
  }

  Future<void> _checkAndDeleteFile(File file) async {
    try {
      FileStat stats = await file.stat();
      DateTime modified = stats.modified;

      String yearStr = DateFormat('yyyy').format(modified);
      String monthStr = DateFormat('MMM').format(modified);

      // Check filters
      if (int.parse(yearStr) <= selectedYear &&
          validMonths.contains(monthStr)) {
        await _deleteFile(file);
      }
    } catch (e) {
      _addLog('✗ Error checking ${p.basename(file.path)}: $e');
      await _fileLogger.error('Delete', 'Error checking ${file.path}: $e');
      errorCount++;
    }
  }

  Future<void> _deleteFile(File file) async {
    try {
      await file.delete();
      deletedCount++;
      _addLog('✓ Deleted: ${p.basename(file.path)}');
      // notifyListeners();
    } catch (e) {
      _addLog('✗ Failed to delete ${p.basename(file.path)}: $e');
      await _fileLogger.error('Delete', 'Failed to delete ${file.path}: $e');
      errorCount++;
    }
  }
}
