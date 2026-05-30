import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../services/file_logger.dart';
import '../services/history_service.dart';
import '../services/local_db_service.dart';
import '../models/run_record.dart';

class _CountProgress {
  final int files;
  final int folders;
  final int errors;
  final String? currentScanPath;
  final String? errorLog;
  final bool isDone;

  _CountProgress({
    this.files = 0,
    this.folders = 0,
    this.errors = 0,
    this.currentScanPath,
    this.errorLog,
    this.isDone = false,
  });
}

class _CountParams {
  final String targetPath;
  final SendPort sendPort;

  _CountParams({
    required this.targetPath,
    required this.sendPort,
  });
}

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
  Isolate? _workerIsolate;

  CountFilesProvider() {
    _loadSettings();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _workerIsolate?.kill(priority: Isolate.immediate);
    super.dispose();
  }

  void _addLog(String message) {
    final timestamp = DateFormat('HH:mm:ss').format(DateTime.now());
    logs.insert(0, '[$timestamp] $message');
    if (logs.length > 1000) logs.removeLast();
  }

  Future<void> _loadSettings() async {
    final db = LocalDbService();
    targetPath = db.getString('count_targetPath');
    notifyListeners();
  }

  Future<void> _saveSettings() async {
    final db = LocalDbService();
    if (targetPath != null) {
      await db.setString('count_targetPath', targetPath!);
    }
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
    if (!isCounting) return;
    _stopRequested = true;
    currentStatus = '⛔ Stopping...';
    _workerIsolate?.kill(priority: Isolate.immediate);
    _workerIsolate = null;
    _finishRun(wasStopped: true);
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
        _finishRun(wasStopped: false);
        return;
      }

      final receivePort = ReceivePort();
      
      _workerIsolate = await Isolate.spawn(
        _isolateWorker, 
        _CountParams(
          targetPath: targetPath!,
          sendPort: receivePort.sendPort,
        ),
      );

      receivePort.listen((message) {
        if (message is _CountProgress) {
          totalFiles = message.files;
          totalFolders = message.folders;
          errors = message.errors;
          
          if (message.currentScanPath != null) {
            currentStatus = '⏳ Scanning: ${message.currentScanPath}';
          }
          
          if (message.errorLog != null) {
            _addLog('✗ ${message.errorLog}');
            _fileLogger.error('Count', message.errorLog!);
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
    } catch (e) {
      _addLog('✗ Critical Error: $e');
      await _fileLogger.error('Count', 'Critical Error: $e');
      _finishRun(wasStopped: false);
    }
  }

  Future<void> _finishRun({required bool wasStopped}) async {
    final elapsed = _getElapsedStr();
    if (wasStopped) {
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

    // Capture before logRunEnd clears them
    final runId = _fileLogger.getRunId('Count') ?? 'UNKNOWN';
    final start = _fileLogger.getStartTime('Count') ?? DateTime.now();

    await _fileLogger.logRunEnd(
      operation: 'Count',
      filesProcessed: totalFiles,
      errors: errors,
      wasStopped: wasStopped,
    );

    try {
      await HistoryService().saveRecord(RunRecord(
        id: runId,
        operation: 'Count',
        startTime: start,
        endTime: DateTime.now(),
        filesProcessed: totalFiles,
        foldersProcessed: totalFolders,
        errors: errors,
        status: wasStopped ? 'Stopped' : 'Completed',
        configSummary: 'Target: $targetPath',
      ));
    } catch (_) {}

    isCounting = false;
    currentStatus = 'Idle';
    _stopTimer();
    notifyListeners();
  }

  static Future<void> _isolateWorker(_CountParams params) async {
    int files = 0;
    int folders = 0;
    int errors = 0;
    
    Future<void> countDir(Directory dir) async {
      try {
        await for (final entity in dir.list(recursive: false, followLinks: true)) {
          if (FileSystemEntity.isFileSync(entity.path)) {
            files++;
          } else if (FileSystemEntity.isDirectorySync(entity.path)) {
            folders++;
            
            // Throttle progress updates to avoid overwhelming the main thread
            if (folders % 10 == 0) {
              params.sendPort.send(_CountProgress(
                files: files,
                folders: folders,
                errors: errors,
                currentScanPath: entity.path,
              ));
            }
            
            await countDir(Directory(entity.path));
          }
        }
      } catch (e) {
        errors++;
        params.sendPort.send(_CountProgress(
          files: files,
          folders: folders,
          errors: errors,
          errorLog: 'Error accessing: ${dir.path} — $e',
        ));
      }
    }

    try {
      await countDir(Directory(params.targetPath));
      params.sendPort.send(_CountProgress(
        files: files,
        folders: folders,
        errors: errors,
        isDone: true,
      ));
    } catch (e) {
      params.sendPort.send(_CountProgress(
        errorLog: 'Critical Error: $e',
        isDone: true,
      ));
    }
  }
}
