import 'dart:async';
import 'dart:io';
// Gene - Nov, 25, 2026: Replaced Dart isolate worker with native Rust delete_engine.
// import 'dart:isolate';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
// import 'package:path/path.dart' as p;
import '../services/file_logger.dart';
import '../services/local_db_service.dart';
// import '../services/path_safety.dart';
import '../services/rust_file_engines.dart';
import '../services/history_service.dart';
import '../models/run_record.dart';

// Gene - Nov, 25, 2026: Commented out Dart isolate DTOs after migrating to Rust delete_engine.
// class _DeleteProgress {
//   final int deleted;
//   final int errors;
//   final List<String> logs;
//   final String? currentStatus;
//   final bool isDone;
//   final String? criticalError;
//
//   _DeleteProgress({
//     this.deleted = 0,
//     this.errors = 0,
//     this.logs = const [],
//     this.currentStatus,
//     this.isDone = false,
//     this.criticalError,
//   });
// }
//
// class _DeleteParams {
//   final String targetPath;
//   final int selectedYear;
//   final List<String> validMonths;
//   final int logInterval;
//   final SendPort sendPort;
//
//   _DeleteParams({
//     required this.targetPath,
//     required this.selectedYear,
//     required this.validMonths,
//     required this.logInterval,
//     required this.sendPort,
//   });
// }

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
  // Gene - Nov, 25, 2026: Track live scanned file count from Rust delete_engine.
  int filesScanned = 0;
  bool _stopRequested = false;
  Timer? _refreshTimer;
  // Isolate? _workerIsolate;
  // ReceivePort? _receivePort;
  RustDeleteJob? _rustJob;
  Timer? _pollTimer;

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
    LocalDbService().addListener(_onProfileChanged);
  }

  void _onProfileChanged() {
    reloadSettings();
  }

  @override
  void dispose() {
    LocalDbService().removeListener(_onProfileChanged);
    _refreshTimer?.cancel();
    // Gene - Nov, 25, 2026: Dispose native RustDeleteJob cleanly.
    // _stopIsolate();
    _stopRustJob();
    super.dispose();
  }

  // void _stopIsolate() {
  //   _workerIsolate?.kill(priority: Isolate.immediate);
  //   _workerIsolate = null;
  //   _receivePort?.close();
  //   _receivePort = null;
  // }
  void _stopRustJob() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _rustJob?.stop();
    _rustJob?.dispose();
    _rustJob = null;
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

  Future<void> reloadSettings() async {
    await _loadSettings();
  }

  Future<void> _saveSettings() async {
    final db = LocalDbService();
    await db.setOrRemoveString('delete_targetPath', targetPath);
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
    // Gene - Nov, 25, 2026: Stop native RustDeleteJob instead of Dart isolate.
    // _stopIsolate();
    _stopRustJob();
    _finishRun(wasStopped: true);
    notifyListeners();
  }

  void clearLogs() {
    logs.clear();
    deletedCount = 0;
    errorCount = 0;
    // Gene - Nov, 25, 2026: Reset scanned counter when clearing logs.
    filesScanned = 0;
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
    // Re-entrancy protection
    if (isProcessing) return;

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
    // Gene - Nov, 25, 2026: Initialize Delete status with live scanning file counter.
    filesScanned = 0;
    // currentStatus = '⏳ Starting deletion...';
    currentStatus = '⏳ Scanning (0 files)...';
    notifyListeners();

    _addLog('⏳ Starting deletion...');
    _addLog('  Target: $targetPath');
    _addLog(
      '  Filter: Files up to Year $selectedYear, Months ${validMonths.join(', ')}',
    );

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
        await _fileLogger.error(
          'Delete',
          'Target directory does not exist: $targetPath',
        );
        _finishRun(wasStopped: false);
        return;
      }

      // Gene - Nov, 25, 2026: Run deletion on native Rust delete_engine instead of Dart isolate.
      // _receivePort?.close();
      // _receivePort = ReceivePort();
      //
      // _workerIsolate = await Isolate.spawn(
      //   _isolateWorker,
      //   _DeleteParams(
      //     targetPath: targetPath!,
      //     selectedYear: selectedYear,
      //     validMonths: validMonths,
      //     logInterval: logInterval,
      //     sendPort: _receivePort!.sendPort,
      //   ),
      // );
      //
      // _receivePort!.listen((message) { ... });
      _stopRustJob();
      _rustJob = RustDeleteJob.start(
        targetPath: targetPath!,
        selectedYear: selectedYear,
        validMonths: validMonths,
        logInterval: logInterval,
      );
      _pollTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        _pollRustJob();
      });
    } catch (e, stack) {
      _addLog('✗ Critical Error: $e');
      _log.severe('Critical error during deletion', e, stack);
      await _fileLogger.error('Delete', 'Critical Error: $e\n$stack');
      // _stopIsolate();
      _stopRustJob();
      _finishRun(wasStopped: false);
    }
  }

  // Gene - Nov, 25, 2026: Poll native Rust delete_engine for live scan/delete progress and logs.
  void _pollRustJob() {
    final job = _rustJob;
    if (job == null || job.isDisposed) return;

    try {
      final snap = job.poll();
      filesScanned = snap.filesScanned;
      deletedCount = snap.deleted;
      errorCount = snap.errors;

      if (!snap.isDone && !_stopRequested) {
        currentStatus = snap.currentDirName.isEmpty
            ? '⏳ Scanning (${_numFmt.format(filesScanned)} files)...'
            : '⏳ Scanning (${_numFmt.format(filesScanned)} files): ${snap.currentDirName}';
      }

      for (final log in snap.logs) {
        _addLog(log);
        if (log.startsWith('✗')) {
          _fileLogger.error('Delete', log);
        }
      }

      for (final err in snap.errorLogs) {
        _addLog(err);
        _fileLogger.error('Delete', err);
      }

      if (snap.criticalError != null) {
        _addLog('✗ Critical Error: ${snap.criticalError}');
        _fileLogger.error('Delete', 'Critical Error: ${snap.criticalError}');
      }

      if (snap.isDone) {
        _stopRustJob();
        if (!_stopRequested) {
          _finishRun(wasStopped: false);
        }
        return;
      }

      notifyListeners();
    } catch (e, stack) {
      _stopRustJob();
      _addLog('✗ Critical Error: $e');
      _log.severe('Critical error polling Rust delete engine', e, stack);
      _fileLogger.error('Delete', 'Critical Error: $e\n$stack');
      _finishRun(wasStopped: false);
    }
  }

  Future<void> _finishRun({required bool wasStopped}) async {
    final elapsed = _getElapsedStr();
    if (wasStopped) {
      _addLog(
        '⛔ Stopped by user. Deleted ${_numFmt.format(deletedCount)} files in $elapsed',
      );
    } else {
      _addLog(
        '🏁 Deletion completed: ${_numFmt.format(deletedCount)} deleted, ${_numFmt.format(errorCount)} errors in $elapsed',
      );
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

    try {
      await HistoryService().saveRecord(
        RunRecord(
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
        ),
      );
    } catch (_) {}

    isProcessing = false;
    currentStatus = 'Idle';
    _stopTimer();
    notifyListeners();
  }

  // Gene - Nov, 25, 2026: Commented out Dart isolate worker after migrating Delete to Rust delete_engine.
  // static Future<void> _isolateWorker(_DeleteParams params) async {
  //   int deletedCount = 0;
  //   int errorCount = 0;
  //   List<String> logBatch = [];
  //   int scanCount = 0;
  //   final Set<String> visitedPaths = {};
  //
  //   void sendProgress(String? status, {bool force = false}) {
  //     if (force ||
  //         status != null ||
  //         logBatch.isNotEmpty ||
  //         scanCount % 10 == 0) {
  //       params.sendPort.send(
  //         _DeleteProgress(
  //           deleted: deletedCount,
  //           errors: errorCount,
  //           logs: List.from(logBatch),
  //           currentStatus: status,
  //         ),
  //       );
  //       logBatch.clear();
  //     }
  //   }
  //
  //   Future<bool> isDirEmpty(Directory dir) async {
  //     try {
  //       return await dir.list().isEmpty;
  //     } catch (e) {
  //       return false;
  //     }
  //   }
  //
  //   Future<void> deleteFile(File file) async {
  //     try {
  //       await file.delete();
  //       deletedCount++;
  //       if (params.logInterval == 1) {
  //         logBatch.add('✓ Deleted: ${p.basename(file.path)}');
  //       } else if (deletedCount % params.logInterval == 0) {
  //         logBatch.add(
  //           '✓ Deleted ${params.logInterval} files (total: $deletedCount) – latest: ${p.basename(file.path)}',
  //         );
  //       }
  //     } catch (e) {
  //       logBatch.add('✗ Failed to delete ${p.basename(file.path)}: $e');
  //       errorCount++;
  //     }
  //   }
  //
  //   Future<void> checkAndDeleteFile(File file) async {
  //     try {
  //       FileStat stats = await file.stat();
  //       DateTime modified = stats.modified;
  //
  //       String yearStr = DateFormat('yyyy').format(modified);
  //       String monthStr = DateFormat('MMM').format(modified);
  //
  //       if (int.parse(yearStr) <= params.selectedYear &&
  //           params.validMonths.contains(monthStr)) {
  //         await deleteFile(file);
  //       }
  //     } catch (e) {
  //       logBatch.add('✗ Error checking ${p.basename(file.path)}: $e');
  //       errorCount++;
  //     }
  //   }
  //
  //   Future<void> processDirectory(Directory dir) async {
  //     String canonicalPath;
  //     try {
  //       canonicalPath = await dir.resolveSymbolicLinks();
  //     } catch (_) {
  //       canonicalPath = p.canonicalize(dir.path);
  //     }
  //
  //     if (visitedPaths.contains(canonicalPath)) {
  //       return;
  //     }
  //     visitedPaths.add(canonicalPath);
  //
  //     try {
  //       await for (final entity in dir.list(
  //         recursive: false,
  //         followLinks: false,
  //       )) {
  //         scanCount++;
  //         if (entity is File) {
  //           await checkAndDeleteFile(entity);
  //         } else if (entity is Directory) {
  //           sendProgress('⏳ Scanning: ${p.basename(entity.path)}');
  //           await processDirectory(entity);
  //         } else if (entity is Link) {
  //           try {
  //             if (!await resolvesWithinRoot(params.targetPath, entity.path)) {
  //               logBatch.add(
  //                 'ℹ Skipped link pointing outside the target: ${p.basename(entity.path)}',
  //               );
  //               sendProgress(null);
  //               continue;
  //             }
  //             final targetType = await FileSystemEntity.type(entity.path);
  //             if (targetType == FileSystemEntityType.directory) {
  //               sendProgress('⏳ Scanning: ${p.basename(entity.path)}');
  //               await processDirectory(Directory(entity.path));
  //             } else if (targetType == FileSystemEntityType.file) {
  //               await checkAndDeleteFile(File(entity.path));
  //             }
  //           } catch (_) {}
  //         }
  //         sendProgress(null);
  //       }
  //
  //       if (dir.path != params.targetPath) {
  //         if (await isDirEmpty(dir)) {
  //           try {
  //             await dir.delete();
  //             logBatch.add('✓ Deleted empty folder: ${p.basename(dir.path)}');
  //           } catch (e) {
  //             logBatch.add(
  //               '✗ Failed to delete folder ${p.basename(dir.path)}: $e',
  //             );
  //           }
  //         }
  //       }
  //     } catch (e) {
  //       logBatch.add('✗ Error scanning directory: $e');
  //       errorCount++;
  //     }
  //   }
  //
  //   try {
  //     await processDirectory(Directory(params.targetPath));
  //     sendProgress('DONE', force: true);
  //     params.sendPort.send(
  //       _DeleteProgress(
  //         isDone: true,
  //         deleted: deletedCount,
  //         errors: errorCount,
  //       ),
  //     );
  //   } catch (e) {
  //     params.sendPort.send(
  //       _DeleteProgress(
  //         criticalError: e.toString(),
  //         isDone: true,
  //         deleted: deletedCount,
  //         errors: errorCount,
  //       ),
  //     );
  //   }
  // }
}
