import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import '../services/file_logger.dart';
import '../services/local_db_service.dart';
import '../services/history_service.dart';
import '../models/run_record.dart';

class _DeleteProgress {
  final int deleted;
  final int errors;
  final List<String> logs;
  final String? currentStatus;
  final bool isDone;
  final String? criticalError;

  _DeleteProgress({
    this.deleted = 0,
    this.errors = 0,
    this.logs = const [],
    this.currentStatus,
    this.isDone = false,
    this.criticalError,
  });
}

class _DeleteParams {
  final String targetPath;
  final int selectedYear;
  final List<String> validMonths;
  final int logInterval;
  final SendPort sendPort;

  _DeleteParams({
    required this.targetPath,
    required this.selectedYear,
    required this.validMonths,
    required this.logInterval,
    required this.sendPort,
  });
}

class DeleteFilesProvider with ChangeNotifier {
  final Logger _log = Logger('DeleteFilesProvider');
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
  Isolate? _workerIsolate;

  int selectedYear = 2025;
  List<String> validMonths = ['Jan'];
  int logInterval = 100;

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

  DeleteFilesProvider() {
    _loadSettings();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _workerIsolate?.kill(priority: Isolate.immediate);
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final db = LocalDbService();
    targetPath = db.getString('delete_targetPath');
    selectedYear = db.getInt('delete_selectedYear') ?? 2025;
    logInterval = db.getInt('delete_logInterval') ?? 100;
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
    await db.setInt('delete_logInterval', logInterval);
    await db.setStringList('delete_validMonths', validMonths);
  }

  void setLogInterval(int val) {
    logInterval = val;
    _saveSettings();
    notifyListeners();
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
    if (!isProcessing) return;
    _stopRequested = true;
    currentStatus = '⛔ Stopping...';
    _workerIsolate?.kill(priority: Isolate.immediate);
    _workerIsolate = null;
    _finishRun(wasStopped: true);
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
        _finishRun(wasStopped: false);
        return;
      }

      final receivePort = ReceivePort();
      
      _workerIsolate = await Isolate.spawn(
        _isolateWorker,
        _DeleteParams(
          targetPath: targetPath!,
          selectedYear: selectedYear,
          validMonths: validMonths,
          logInterval: logInterval,
          sendPort: receivePort.sendPort,
        ),
      );

      receivePort.listen((message) {
        if (message is _DeleteProgress) {
          deletedCount = message.deleted;
          errorCount = message.errors;
          
          if (message.currentStatus != null) {
            currentStatus = message.currentStatus!;
          }
          
          for (final log in message.logs) {
            _addLog(log);
            // Optionally send errors to FileLogger if marked specifically, 
            // but for simplicity we rely on the isolate's text logs for now.
            if (log.startsWith('✗')) {
              _fileLogger.error('Delete', log);
            }
          }

          if (message.criticalError != null) {
            _addLog('✗ Critical Error: ${message.criticalError}');
            _fileLogger.error('Delete', 'Critical Error: ${message.criticalError}');
          }

          if (message.isDone) {
            receivePort.close();
            _workerIsolate = null;
            if (!_stopRequested) {
              _finishRun(wasStopped: false);
            }
          }
        }
      });
    } catch (e, stack) {
      _addLog('✗ Critical Error: $e');
      _log.severe('Critical error during deletion', e, stack);
      await _fileLogger.error('Delete', 'Critical Error: $e\n$stack');
      _finishRun(wasStopped: false);
    }
  }

  Future<void> _finishRun({required bool wasStopped}) async {
    final elapsed = _getElapsedStr();
    if (wasStopped) {
      _addLog('⛔ Stopped by user. Deleted ${_numFmt.format(deletedCount)} files in $elapsed');
    } else {
      _addLog('🏁 Deletion completed: ${_numFmt.format(deletedCount)} deleted, ${_numFmt.format(errorCount)} errors in $elapsed');
    }

    // Capture before logRunEnd clears them
    final runId = _fileLogger.getRunId('Delete') ?? 'UNKNOWN';
    final start = _fileLogger.getStartTime('Delete') ?? DateTime.now();

    await _fileLogger.logRunEnd(
      operation: 'Delete',
      filesProcessed: deletedCount,
      errors: errorCount,
      wasStopped: wasStopped,
    );

      await HistoryService().saveRecord(RunRecord(
        id: runId,
        operation: 'Delete',
        startTime: start,
        endTime: DateTime.now(),
        filesProcessed: deletedCount,
        errors: errorCount,
        status: wasStopped
            ? 'Stopped'
            : (errorCount > 0 && deletedCount == 0 ? 'Error' : 'Completed'),
        configSummary:
            'Target: $targetPath, Filter: Year $selectedYear, Months: ${validMonths.join(", ")}',
        sourcePath: targetPath,
      ));

    isProcessing = false;
    currentStatus = 'Idle';
    _stopTimer();
    notifyListeners();
  }

  static Future<void> _isolateWorker(_DeleteParams params) async {
    int deletedCount = 0;
    int errorCount = 0;
    List<String> logBatch = [];
    int scanCount = 0;

    void sendProgress(String? status, {bool force = false}) {
      if (force || logBatch.isNotEmpty || scanCount % 10 == 0) {
        params.sendPort.send(_DeleteProgress(
          deleted: deletedCount,
          errors: errorCount,
          logs: List.from(logBatch),
          currentStatus: status,
        ));
        logBatch.clear();
      }
    }

    Future<bool> isEmpty(Directory dir) async {
      try {
        return await dir.list().isEmpty;
      } catch (e) {
        return false;
      }
    }

    Future<void> deleteFile(File file) async {
      try {
        await file.delete();
        deletedCount++;
        if (params.logInterval == 1) {
          logBatch.add('✓ Deleted: ${p.basename(file.path)}');
        } else if (deletedCount % params.logInterval == 0) {
          logBatch.add(
            '✓ Deleted ${params.logInterval} files (total: $deletedCount) – latest: ${p.basename(file.path)}',
          );
        }
      } catch (e) {
        logBatch.add('✗ Failed to delete ${p.basename(file.path)}: $e');
        errorCount++;
      }
    }

    Future<void> checkAndDeleteFile(File file) async {
      try {
        FileStat stats = await file.stat();
        DateTime modified = stats.modified;

        String yearStr = DateFormat('yyyy').format(modified);
        String monthStr = DateFormat('MMM').format(modified);

        if (int.parse(yearStr) <= params.selectedYear &&
            params.validMonths.contains(monthStr)) {
          await deleteFile(file);
        }
      } catch (e) {
        logBatch.add('✗ Error checking ${p.basename(file.path)}: $e');
        errorCount++;
      }
    }

    Future<void> processDirectory(Directory dir) async {
      try {
        await for (final entity in dir.list(recursive: false, followLinks: true)) {
          scanCount++;
          if (entity is File) {
            await checkAndDeleteFile(entity);
          } else if (entity is Directory) {
            sendProgress('⏳ Scanning: ${p.basename(entity.path)}');
            await processDirectory(entity);
          }
          sendProgress(null);
        }

        if (dir.path != params.targetPath) {
          if (await isEmpty(dir)) {
            try {
              await dir.delete();
              logBatch.add('✓ Deleted empty folder: ${p.basename(dir.path)}');
            } catch (e) {
              logBatch.add('✗ Failed to delete folder ${p.basename(dir.path)}: $e');
            }
          }
        }
      } catch (e) {
        logBatch.add('✗ Error scanning directory: $e');
        errorCount++;
      }
    }
    try {
      await processDirectory(Directory(params.targetPath));
      sendProgress('DONE', force: true);
      params.sendPort.send(_DeleteProgress(
        isDone: true,
        deleted: deletedCount,
        errors: errorCount,
      ));
    } catch (e) {
      params.sendPort.send(_DeleteProgress(
        criticalError: e.toString(),
        isDone: true,
        deleted: deletedCount,
        errors: errorCount,
      ));
    }
  }
}
