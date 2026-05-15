import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/file_logger.dart';

/// Message sent FROM the background isolate TO the main isolate.
class _IsolateProgress {
  final String? logMessage;
  final String? errorMessage;
  final String? status;
  final int filesCopied;
  final int filesSkipped;
  final int filesAlreadyExist;
  final int errors;
  final bool done;
  final String? criticalError;

  _IsolateProgress({
    this.logMessage,
    this.errorMessage,
    this.status,
    this.filesCopied = 0,
    this.filesSkipped = 0,
    this.filesAlreadyExist = 0,
    this.errors = 0,
    this.done = false,
    this.criticalError,
  });
}

/// Parameters sent TO the background isolate.
class _IsolateParams {
  final String sourcePath;
  final String destPath;
  final bool enableDateRange;
  final int fromEpochMs;
  final int toEpochMs;
  final SendPort sendPort;

  _IsolateParams({
    required this.sourcePath,
    required this.destPath,
    required this.enableDateRange,
    required this.fromEpochMs,
    required this.toEpochMs,
    required this.sendPort,
  });
}

/// Mutable counters passed through the recursive walk inside the isolate.
class _CountState {
  int filesCopied = 0;
  int filesSkipped = 0;
  int filesAlreadyExist = 0;
  int errors = 0;
  int directoriesScanned = 0;
}

class _CopyTask {
  final File source;
  final String destFilePath;

  _CopyTask(this.source, this.destFilePath);
}

/// A source→destination directory pair for multi-directory mode.
class DirectoryPair {
  String? sourcePath;
  String? destPath;

  DirectoryPair({this.sourcePath, this.destPath});

  Map<String, String?> toJson() => {'source': sourcePath, 'dest': destPath};

  factory DirectoryPair.fromJson(Map<String, dynamic> json) =>
      DirectoryPair(sourcePath: json['source'] as String?, destPath: json['dest'] as String?);
}


class CopyFilesProvider with ChangeNotifier {
  final Logger _log = Logger('CopyFilesProvider');
  final FileLogger _fileLogger = FileLogger();

  // State
  String? sourcePath;
  String? destPath;

  // Multiple directory pairs
  bool useMultipleDirectories = false;
  List<DirectoryPair> directoryPairs = [DirectoryPair()];

  // Date range filter (from/to inclusive)
  bool enableDateRange = false;
  DateTime fromDate = DateTime(2025, 1, 1);
  DateTime toDate = DateTime(2025, 1, 31);

  // Quick date filter: "Today Only" and "Yesterday Only"
  bool todayOnly = false;
  bool yesterdayOnly = false;

  // Time Schedule Feature
  bool enableTimeWindow = false;
  TimeOfDay runFromTime = const TimeOfDay(hour: 0, minute: 0);
  TimeOfDay runToTime = const TimeOfDay(hour: 6, minute: 0);

  // Run-time days: day-of-week (1=Monday … 7=Sunday).
  // Checked = apply the run-time window on that day.
  // Unchecked = run the whole day.
  Map<int, bool> runDays = {
    1: false, // Monday
    2: false, // Tuesday
    3: false, // Wednesday
    4: false, // Thursday
    5: false, // Friday
    6: false, // Saturday
    7: false, // Sunday
  };

  bool isProcessing = false;
  List<String> logs = [];
  String currentStatus = 'Idle';

  // Stats
  int filesCopied = 0;
  int filesSkipped = 0;
  int errors = 0;

  Isolate? _workerIsolate;
  ReceivePort? _receivePort;
  StreamSubscription? _progressSubscription;
  
  // Pause/Schedule State
  Capability? _pauseCapability;
  bool isPaused = false;
  Timer? _scheduleTimer;

  // Multi-pair processing state
  List<MapEntry<String, String>> _pairsToProcess = [];
  int _currentPairIndex = 0;
  int _accFilesCopied = 0;
  int _accFilesSkipped = 0;
  int _accErrors = 0;

  CopyFilesProvider() {
    _loadSettings();
  }

  void _addLog(String message) {
    final timestamp = DateFormat('HH:mm:ss').format(DateTime.now());
    logs.insert(0, '[$timestamp] $message');
    if (logs.length > 1000) logs.removeLast();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    sourcePath = prefs.getString('copy_sourcePath');
    destPath = prefs.getString('copy_destPath');

    final fromMs = prefs.getInt('copy_fromDateMs');
    final toMs = prefs.getInt('copy_toDateMs');
    if (fromMs != null) {
      fromDate = DateTime.fromMillisecondsSinceEpoch(fromMs);
    }
    if (toMs != null) {
      toDate = DateTime.fromMillisecondsSinceEpoch(toMs);
    }
    
    enableDateRange = prefs.getBool('copy_enableDateRange') ?? false;
    todayOnly = prefs.getBool('copy_todayOnly') ?? false;
    yesterdayOnly = prefs.getBool('copy_yesterdayOnly') ?? false;

    // Apply quick date filter on load if active
    _applyQuickDateFilter();

    // Load multiple directories
    useMultipleDirectories = prefs.getBool('copy_useMultiDirs') ?? false;
    final pairsJson = prefs.getString('copy_directoryPairs');
    if (pairsJson != null) {
      try {
        final list = jsonDecode(pairsJson) as List;
        directoryPairs = list.map((m) => DirectoryPair.fromJson(Map<String, dynamic>.from(m))).toList();
      } catch (_) {
        directoryPairs = [DirectoryPair()];
      }
    }
    if (directoryPairs.isEmpty) directoryPairs = [DirectoryPair()];

    enableTimeWindow = prefs.getBool('copy_enableTimeWindow') ?? false;
    
    final fromHour = prefs.getInt('copy_runFromHour');
    final fromMinute = prefs.getInt('copy_runFromMinute');
    if (fromHour != null && fromMinute != null) {
      runFromTime = TimeOfDay(hour: fromHour, minute: fromMinute);
    }

    final toHour = prefs.getInt('copy_runToHour');
    final toMinute = prefs.getInt('copy_runToMinute');
    if (toHour != null && toMinute != null) {
      runToTime = TimeOfDay(hour: toHour, minute: toMinute);
    }

    // Load run days
    for (int day = 1; day <= 7; day++) {
      runDays[day] = prefs.getBool('copy_runDay_$day') ?? false;
    }

    notifyListeners();
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (sourcePath != null) {
      await prefs.setString('copy_sourcePath', sourcePath!);
    }
    if (destPath != null) {
      await prefs.setString('copy_destPath', destPath!);
    }
    await prefs.setInt('copy_fromDateMs', fromDate.millisecondsSinceEpoch);
    await prefs.setInt('copy_toDateMs', toDate.millisecondsSinceEpoch);
    await prefs.setBool('copy_enableDateRange', enableDateRange);
    await prefs.setBool('copy_todayOnly', todayOnly);
    await prefs.setBool('copy_yesterdayOnly', yesterdayOnly);

    await prefs.setBool('copy_enableTimeWindow', enableTimeWindow);
    await prefs.setInt('copy_runFromHour', runFromTime.hour);
    await prefs.setInt('copy_runFromMinute', runFromTime.minute);
    await prefs.setInt('copy_runToHour', runToTime.hour);
    await prefs.setInt('copy_runToMinute', runToTime.minute);

    // Save run days
    for (int day = 1; day <= 7; day++) {
      await prefs.setBool('copy_runDay_$day', runDays[day] ?? false);
    }

    // Save multiple directories
    await prefs.setBool('copy_useMultiDirs', useMultipleDirectories);
    final pairsJson = jsonEncode(directoryPairs.map((p) => p.toJson()).toList());
    await prefs.setString('copy_directoryPairs', pairsJson);
  }

  void setSourcePath(String? path) {
    sourcePath = path;
    _saveSettings();
    notifyListeners();
  }

  void setDestPath(String? path) {
    destPath = path;
    _saveSettings();
    notifyListeners();
  }

  void setEnableDateRange(bool val) {
    enableDateRange = val;
    // Uncheck quick filters when manually toggling date range off
    if (!val) {
      todayOnly = false;
      yesterdayOnly = false;
    }
    _saveSettings();
    notifyListeners();
  }

  void setFromDate(DateTime date) {
    fromDate = date;
    if (fromDate.isAfter(toDate)) toDate = fromDate;
    // Manual date pick clears quick filters
    todayOnly = false;
    yesterdayOnly = false;
    _saveSettings();
    notifyListeners();
  }

  void setToDate(DateTime date) {
    toDate = date;
    if (toDate.isBefore(fromDate)) fromDate = toDate;
    // Manual date pick clears quick filters
    todayOnly = false;
    yesterdayOnly = false;
    _saveSettings();
    notifyListeners();
  }

  void setTodayOnly(bool val) {
    todayOnly = val;
    _applyQuickDateFilter();
    _saveSettings();
    notifyListeners();
  }

  void setYesterdayOnly(bool val) {
    yesterdayOnly = val;
    _applyQuickDateFilter();
    _saveSettings();
    notifyListeners();
  }

  /// Computes from/to dates based on the Today/Yesterday checkboxes.
  /// Called on load, on toggle, and at each run start to keep dates current.
  void _applyQuickDateFilter() {
    if (!todayOnly && !yesterdayOnly) return;

    enableDateRange = true;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    if (todayOnly && yesterdayOnly) {
      // Both checked → yesterday to today
      fromDate = yesterday;
      toDate = today;
    } else if (todayOnly) {
      fromDate = today;
      toDate = today;
    } else {
      // yesterdayOnly
      fromDate = yesterday;
      toDate = yesterday;
    }
  }

  void setEnableTimeWindow(bool val) {
    enableTimeWindow = val;
    _saveSettings();
    notifyListeners();
    _evaluateSchedule();
  }

  void setRunFromTime(TimeOfDay time) {
    runFromTime = time;
    _saveSettings();
    notifyListeners();
    _evaluateSchedule();
  }

  void setRunToTime(TimeOfDay time) {
    runToTime = time;
    _saveSettings();
    notifyListeners();
    _evaluateSchedule();
  }

  void setRunDay(int day, bool value) {
    runDays[day] = value;
    _saveSettings();
    notifyListeners();
    _evaluateSchedule();
  }

  Future<void> pickSource() async {
    final path = await getDirectoryPath(initialDirectory: sourcePath);
    if (path != null) setSourcePath(path);
  }

  Future<void> pickDest() async {
    final path = await getDirectoryPath(initialDirectory: destPath);
    if (path != null) setDestPath(path);
  }

  // --- Multiple directory pair management ---

  void setUseMultipleDirectories(bool val) {
    useMultipleDirectories = val;
    if (val && directoryPairs.isEmpty) {
      directoryPairs.add(DirectoryPair());
    }
    _saveSettings();
    notifyListeners();
  }

  void addDirectoryPair() {
    directoryPairs.add(DirectoryPair());
    _saveSettings();
    notifyListeners();
  }

  void removeDirectoryPair(int index) {
    if (directoryPairs.length > 1) {
      directoryPairs.removeAt(index);
      _saveSettings();
      notifyListeners();
    }
  }

  Future<void> pickPairSource(int index) async {
    final path = await getDirectoryPath(initialDirectory: directoryPairs[index].sourcePath);
    if (path != null) {
      directoryPairs[index].sourcePath = path;
      _saveSettings();
      notifyListeners();
    }
  }

  Future<void> pickPairDest(int index) async {
    final path = await getDirectoryPath(initialDirectory: directoryPairs[index].destPath);
    if (path != null) {
      directoryPairs[index].destPath = path;
      _saveSettings();
      notifyListeners();
    }
  }

  void stop() {
    _workerIsolate?.kill(priority: Isolate.immediate);
    _workerIsolate = null;
    _progressSubscription?.cancel();
    _progressSubscription = null;
    _receivePort?.close();
    _receivePort = null;
    _scheduleTimer?.cancel();
    _scheduleTimer = null;
    
    _pauseCapability = null;
    isPaused = false;
    currentStatus = 'Stopped by user.';
    _addLog('Stopped by user.');
    isProcessing = false;
    notifyListeners();

    _fileLogger.logRunEnd(
      operation: 'Copy',
      filesProcessed: filesCopied,
      errors: errors,
      wasStopped: true,
    );
  }

  bool _isCurrentlyInTimeWindow() {
    if (!enableTimeWindow) return true;

    // Check if today's day-of-week is checked.
    // If the day is NOT checked, the copy runs the whole day (no time restriction).
    final todayDow = DateTime.now().weekday; // 1=Mon … 7=Sun
    if (runDays[todayDow] != true) {
      return true; // unchecked day → run all day
    }

    // Day is checked → enforce the time window.
    final now = TimeOfDay.now();
    double nowVal = now.hour + now.minute / 60.0;
    double fromVal = runFromTime.hour + runFromTime.minute / 60.0;
    double toVal = runToTime.hour + runToTime.minute / 60.0;

    if (fromVal < toVal) {
      return nowVal >= fromVal && nowVal < toVal;
    } else if (fromVal > toVal) {
      // Midnight crossover
      return nowVal >= fromVal || nowVal < toVal;
    } else {
      // from == to, assume open window for safety or disabled.
      return false;
    }
  }

  void _evaluateSchedule() {
    if (!isProcessing || _workerIsolate == null) return;
    
    bool inWindow = _isCurrentlyInTimeWindow();
    
    if (inWindow && isPaused) {
      // If quick date filters are active, the dates may be stale after an
      // overnight pause.  Kill the old isolate and restart with fresh dates.
      if (todayOnly || yesterdayOnly) {
        _addLog('Time window reached. Restarting with updated dates...');
        _killWorker();
        isPaused = false;
        _pauseCapability = null;
        // startProcessing will call _applyQuickDateFilter() and spawn a new isolate.
        startProcessing();
        return;
      }

      if (_pauseCapability != null) {
        _workerIsolate?.resume(_pauseCapability!);
        isPaused = false;
        currentStatus = 'Copying...';
        _addLog('Time window reached. Resuming copy...');
        notifyListeners();
      }
    } else if (!inWindow && !isPaused) {
      _pauseCapability = _workerIsolate?.pause();
      isPaused = true;
      currentStatus = 'Waiting for time window...';
      _addLog('Outside allowed time window. Paused until next run window.');
      notifyListeners();
    }
  }

  /// Kills the worker isolate and cleans up its resources without touching
  /// the outer processing state (isProcessing, scheduleTimer, etc.).
  void _killWorker() {
    _workerIsolate?.kill(priority: Isolate.immediate);
    _workerIsolate = null;
    _progressSubscription?.cancel();
    _progressSubscription = null;
    _receivePort?.close();
    _receivePort = null;
  }

  static Future<void> _processBatch(
    List<_CopyTask> batch,
    _IsolateParams params,
    _CountState counts,
  ) async {
    final futures = batch.map((task) async {
      try {
        await task.source.copy(task.destFilePath);
        counts.filesCopied++;

        if (counts.filesCopied % 10 == 0) {
          params.sendPort.send(_IsolateProgress(
            logMessage: 'Copied: ${p.basename(task.source.path)}',
            status: 'Copying: ${p.basename(task.source.path)}',
            filesCopied: counts.filesCopied,
            filesSkipped: counts.filesSkipped,
            filesAlreadyExist: counts.filesAlreadyExist,
            errors: counts.errors,
          ));
        }
      } catch (e) {
        counts.errors++;
        params.sendPort.send(_IsolateProgress(
          errorMessage: 'Failed to copy ${p.basename(task.source.path)}: $e',
          errors: counts.errors,
          filesCopied: counts.filesCopied,
          filesSkipped: counts.filesSkipped,
          filesAlreadyExist: counts.filesAlreadyExist,
        ));
      }
    });

    await Future.wait(futures);
  }

  /// Manual recursive walk using async lists for maximum performance.
  static Future<void> _walkAndCopy(
    Directory dir,
    _IsolateParams params,
    _CountState counts,
    Set<String> createdDirs,
    List<_CopyTask> batch,
  ) async {
    List<FileSystemEntity> entities;
    try {
      entities = await dir.list(followLinks: false).toList();
    } catch (e) {
      counts.errors++;
      params.sendPort.send(_IsolateProgress(
        errorMessage: 'Cannot access: ${dir.path} ($e)',
        errors: counts.errors,
        filesCopied: counts.filesCopied,
        filesSkipped: counts.filesSkipped,
        filesAlreadyExist: counts.filesAlreadyExist,
      ));
      return; 
    }

    counts.directoriesScanned++;

    if (counts.directoriesScanned % 20 == 0) {
      params.sendPort.send(_IsolateProgress(
        status: 'Scanning: ${p.basename(dir.path)}',
        filesCopied: counts.filesCopied,
        filesSkipped: counts.filesSkipped,
        filesAlreadyExist: counts.filesAlreadyExist,
        errors: counts.errors,
      ));
    }

    final fromDate = DateTime.fromMillisecondsSinceEpoch(params.fromEpochMs);
    final toDate = DateTime.fromMillisecondsSinceEpoch(params.toEpochMs);

    final files = entities.whereType<File>().toList();
    
    // Process files in concurrency batches of 50
    for (var i = 0; i < files.length; i += 50) {
      final chunk = files.skip(i).take(50);
      
      final futures = chunk.map((entity) async {
        try {
          bool withinDateRange = true;
          int sourceSize = -1;

          if (params.enableDateRange) {
            FileStat stats = await entity.stat();
            sourceSize = stats.size;
            DateTime modified = stats.modified;
            
            final fileDate = DateTime(modified.year, modified.month, modified.day);
            final from = DateTime(fromDate.year, fromDate.month, fromDate.day);
            final to = DateTime(toDate.year, toDate.month, toDate.day);
            if (fileDate.isBefore(from) || fileDate.isAfter(to)) {
              withinDateRange = false;
            }
          }

          if (withinDateRange) {
            String relativePath = p.relative(entity.parent.path, from: params.sourcePath);
            String destDir = p.join(params.destPath, relativePath);
            String destFilePath = p.join(destDir, p.basename(entity.path));
            
            bool shouldCopy = true;
            
            if (sourceSize == -1) {
              sourceSize = await entity.length();
            }

            File destFile = File(destFilePath);
            FileStat destStat = await destFile.stat();
            if (destStat.type != FileSystemEntityType.notFound && destStat.size == sourceSize) {
                shouldCopy = false;
            }

            if (shouldCopy) {
              if (!createdDirs.contains(destDir)) {
                createdDirs.add(destDir);
                await Directory(destDir).create(recursive: true);
              }
              batch.add(_CopyTask(entity, destFilePath));
            } else {
              counts.filesAlreadyExist++;
            }
          } else {
            counts.filesSkipped++;
          }
        } catch (e) {
          counts.errors++;
          params.sendPort.send(_IsolateProgress(
            errorMessage: 'Failed to inspect/copy ${p.basename(entity.path)}: $e',
            errors: counts.errors,
            filesCopied: counts.filesCopied,
            filesSkipped: counts.filesSkipped,
            filesAlreadyExist: counts.filesAlreadyExist,
          ));
        }
      });

      await Future.wait(futures);

      if (batch.length >= 20) {
         final tasksToRun = List<_CopyTask>.from(batch);
         batch.clear();
         await _processBatch(tasksToRun, params, counts);
         await Future.delayed(Duration.zero);
      }
    }

    // Then recurse into subdirectories
    for (final entity in entities) {
      if (entity is Directory) {
        await _walkAndCopy(entity, params, counts, createdDirs, batch);
      }
    }
  }

  /// Top-level isolate entry point.
  static Future<void> _copyWorker(_IsolateParams params) async {
    final counts = _CountState();
    final createdDirs = <String>{};
    final batch = <_CopyTask>[];

    try {
      final sourceDir = Directory(params.sourcePath);
      if (!sourceDir.existsSync()) {
        params.sendPort.send(_IsolateProgress(
          errorMessage: 'Error: Source directory does not exist.',
          done: true,
          errors: 1,
        ));
        return;
      }

      await _walkAndCopy(sourceDir, params, counts, createdDirs, batch);
      
      // Process remaining tasks in the final batch
      if (batch.isNotEmpty) {
        await _processBatch(batch, params, counts);
        batch.clear();
      }

      params.sendPort.send(_IsolateProgress(
        logMessage: 'Copy completed successfully.',
        status: 'Done',
        done: true,
        filesCopied: counts.filesCopied,
        filesSkipped: counts.filesSkipped,
        filesAlreadyExist: counts.filesAlreadyExist,
        errors: counts.errors,
      ));
    } catch (e) {
      params.sendPort.send(_IsolateProgress(
        logMessage: 'Critical Error: $e',
        criticalError: e.toString(),
        done: true,
        filesCopied: counts.filesCopied,
        filesSkipped: counts.filesSkipped,
        filesAlreadyExist: counts.filesAlreadyExist,
        errors: counts.errors,
      ));
    }
  }

  Future<void> startProcessing() async {
    // Auto-update quick date filters to the current day before starting
    _applyQuickDateFilter();

    // Build list of pairs to process
    _pairsToProcess = [];
    if (useMultipleDirectories) {
      for (final pair in directoryPairs) {
        if (pair.sourcePath != null && pair.destPath != null) {
          _pairsToProcess.add(MapEntry(pair.sourcePath!, pair.destPath!));
        }
      }
    } else {
      if (sourcePath == null || destPath == null) {
        _addLog('Error: Source or Destination not selected.');
        await _fileLogger.error('Copy', 'Source or Destination not selected.');
        return;
      }
      _pairsToProcess.add(MapEntry(sourcePath!, destPath!));
    }

    if (_pairsToProcess.isEmpty) {
      _addLog('Error: No valid directory pairs configured.');
      return;
    }

    _currentPairIndex = 0;
    _accFilesCopied = 0;
    _accFilesSkipped = 0;
    _accErrors = 0;

    isProcessing = true;
    currentStatus = 'Scanning...';
    filesCopied = 0;
    filesSkipped = 0;
    errors = 0;
    isPaused = false;
    _pauseCapability = null;
    notifyListeners();

    final dateFormat = DateFormat('dd/MM/yyyy');
    _addLog('Starting copy process... (${_pairsToProcess.length} pair(s))');
    if (enableDateRange) {
      _addLog('Date range: ${dateFormat.format(fromDate)} — ${dateFormat.format(toDate)}');
    }
    if (enableTimeWindow) {
      final String formattedFrom = '${runFromTime.hour.toString().padLeft(2, '0')}:${runFromTime.minute.toString().padLeft(2, '0')}';
      final String formattedTo = '${runToTime.hour.toString().padLeft(2, '0')}:${runToTime.minute.toString().padLeft(2, '0')}';
      _addLog('Run window bounds: $formattedFrom to $formattedTo');
    }

    await _fileLogger.logRunStart(
      operation: 'Copy',
      sourcePath: _pairsToProcess.first.key,
      destPath: _pairsToProcess.first.value,
    );

    // Setup periodic schedule evaluation
    _scheduleTimer?.cancel();
    _scheduleTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _evaluateSchedule();
    });

    await _startCurrentPair();
  }

  /// Spawns an isolate for the current pair and listens for progress.
  /// When done, advances to the next pair or finishes.
  Future<void> _startCurrentPair() async {
    final pair = _pairsToProcess[_currentPairIndex];
    _addLog('--- Pair ${_currentPairIndex + 1}/${_pairsToProcess.length}: ${pair.key} → ${pair.value} ---');
    currentStatus = 'Pair ${_currentPairIndex + 1}: Scanning...';
    notifyListeners();

    _receivePort = ReceivePort();

    final params = _IsolateParams(
      sourcePath: pair.key,
      destPath: pair.value,
      enableDateRange: enableDateRange,
      fromEpochMs: fromDate.millisecondsSinceEpoch,
      toEpochMs: toDate.millisecondsSinceEpoch,
      sendPort: _receivePort!.sendPort,
    );

    _workerIsolate = await Isolate.spawn(_copyWorker, params);
    _evaluateSchedule();

    _progressSubscription = _receivePort!.listen((message) async {
      if (message is _IsolateProgress) {
        // Update stats (accumulated + current pair)
        filesCopied = _accFilesCopied + message.filesCopied;
        filesSkipped = _accFilesSkipped + message.filesSkipped;
        errors = _accErrors + message.errors;

        if (message.status != null && !isPaused) {
          currentStatus = 'Pair ${_currentPairIndex + 1}: ${message.status!}';
        }

        if (message.logMessage != null) {
          _addLog(message.logMessage!);
        }

        if (message.errorMessage != null) {
          _addLog(message.errorMessage!);
          await _fileLogger.error('Copy', message.errorMessage!);
        }

        if (message.criticalError != null) {
          _log.severe('Isolate critical error: ${message.criticalError}');
          await _fileLogger.error(
              'Copy', 'Critical Error: ${message.criticalError}');
        }

        if (message.done) {
          // Accumulate this pair's stats
          _accFilesCopied += message.filesCopied;
          _accFilesSkipped += message.filesSkipped;
          _accErrors += message.errors;
          filesCopied = _accFilesCopied;
          filesSkipped = _accFilesSkipped;
          errors = _accErrors;

          _addLog('Pair ${_currentPairIndex + 1} done: ${message.filesCopied} copied, ${message.filesAlreadyExist} exist, ${message.filesSkipped} skipped, ${message.errors} errors');

          _killWorker();
          _currentPairIndex++;

          if (_currentPairIndex < _pairsToProcess.length) {
            // Start next pair
            await _startCurrentPair();
          } else {
            // All pairs finished
            _addLog('All ${_pairsToProcess.length} pair(s) completed. Total: $filesCopied copied, $errors errors.');

            await _fileLogger.logRunEnd(
              operation: 'Copy',
              filesProcessed: filesCopied,
              errors: errors,
              wasStopped: false,
            );

            isProcessing = false;
            currentStatus = 'Idle';
            _scheduleTimer?.cancel();
            _scheduleTimer = null;
          }
        }

        notifyListeners();
      }
    });
  }
}
