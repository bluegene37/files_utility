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
  int runOrder;

  DirectoryPair({this.sourcePath, this.destPath, this.runOrder = 1});

  Map<String, dynamic> toJson() => {'source': sourcePath, 'dest': destPath, 'runOrder': runOrder};

  factory DirectoryPair.fromJson(Map<String, dynamic> json) =>
      DirectoryPair(
        sourcePath: json['source'] as String?,
        destPath: json['dest'] as String?,
        runOrder: (json['runOrder'] as int?) ?? 1,
      );
}

/// Tracks an active worker isolate processing one directory pair.
class _ActiveWorker {
  final int pairIndex;
  final Isolate isolate;
  final ReceivePort receivePort;
  final StreamSubscription subscription;
  Capability? pauseCapability;
  bool isPaused = false;

  _ActiveWorker({
    required this.pairIndex,
    required this.isolate,
    required this.receivePort,
    required this.subscription,
  });
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

  // Completion behavior: 'pause' = wait and re-run at next start time,
  // 'stop' = fully stop when done.
  String onCompletionAction = 'pause'; // 'pause' or 'stop'

  bool isProcessing = false;
  List<String> logs = [];
  String currentStatus = 'Idle';

  // Stats
  int filesCopied = 0;
  int filesSkipped = 0;
  int errors = 0;

  // Active worker isolates
  final List<_ActiveWorker> _activeWorkers = [];
  
  // Pause/Schedule State
  bool isPaused = false;
  Timer? _scheduleTimer;
  Timer? _completionRescheduleTimer;

  // Multi-pair processing state
  // Each entry: { 'source': ..., 'dest': ..., 'runOrder': ..., 'origIndex': ... }
  List<Map<String, dynamic>> _pairsToProcess = [];
  // Run order groups: sorted list of distinct run order values
  List<int> _runOrderGroups = [];
  int _currentGroupIndex = 0;
  int _pairsCompletedInGroup = 0;
  int _totalPairsCompleted = 0;
  // Per-pair accumulated stats
  final Map<int, List<int>> _pairStats = {}; // pairIndex → [copied, skipped, errors]

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

    onCompletionAction = prefs.getString('copy_onCompletionAction') ?? 'pause';

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

    await prefs.setString('copy_onCompletionAction', onCompletionAction);
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

  void setPairRunOrder(int index, int order) {
    if (index >= 0 && index < directoryPairs.length) {
      directoryPairs[index].runOrder = order.clamp(1, 10);
      _saveSettings();
      notifyListeners();
    }
  }

  void setOnCompletionAction(String action) {
    onCompletionAction = action;
    _saveSettings();
    notifyListeners();
  }

  void stop() {
    _killAllWorkers();
    _scheduleTimer?.cancel();
    _scheduleTimer = null;
    _completionRescheduleTimer?.cancel();
    _completionRescheduleTimer = null;
    
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
    if (!isProcessing || _activeWorkers.isEmpty) return;
    
    bool inWindow = _isCurrentlyInTimeWindow();
    
    if (inWindow && isPaused) {
      // If quick date filters are active, the dates may be stale after an
      // overnight pause.  Kill the old isolates and restart with fresh dates.
      if (todayOnly || yesterdayOnly) {
        _addLog('Time window reached. Restarting with updated dates...');
        _killAllWorkers();
        isPaused = false;
        // startProcessing will call _applyQuickDateFilter() and spawn new isolates.
        startProcessing();
        return;
      }

      // Resume all paused workers
      for (final w in _activeWorkers) {
        if (w.isPaused && w.pauseCapability != null) {
          w.isolate.resume(w.pauseCapability!);
          w.isPaused = false;
        }
      }
      isPaused = false;
      currentStatus = 'Copying...';
      _addLog('Time window reached. Resuming copy...');
      notifyListeners();
    } else if (!inWindow && !isPaused) {
      // Pause all active workers
      for (final w in _activeWorkers) {
        if (!w.isPaused) {
          w.pauseCapability = w.isolate.pause();
          w.isPaused = true;
        }
      }
      isPaused = true;
      currentStatus = 'Waiting for time window...';
      _addLog('Outside allowed time window. Paused until next run window.');
      notifyListeners();
    }
  }

  /// Kills all active worker isolates and cleans up their resources without
  /// touching the outer processing state (isProcessing, scheduleTimer, etc.).
  void _killAllWorkers() {
    for (final w in _activeWorkers) {
      w.isolate.kill(priority: Isolate.immediate);
      w.subscription.cancel();
      w.receivePort.close();
    }
    _activeWorkers.clear();
  }

  /// Schedules the next automatic run at the configured `runFromTime`.
  /// Used when `onCompletionAction == 'pause'` to keep re-running daily.
  void _scheduleNextRun() {
    _completionRescheduleTimer?.cancel();

    final now = DateTime.now();
    // Determine the next run time based on runFromTime
    DateTime nextRun = DateTime(
      now.year, now.month, now.day,
      runFromTime.hour, runFromTime.minute,
    );

    // If the next run time is in the past (or now), schedule for tomorrow
    if (!nextRun.isAfter(now)) {
      nextRun = nextRun.add(const Duration(days: 1));
    }

    final waitDuration = nextRun.difference(now);
    final formattedNext = DateFormat('dd/MM/yyyy HH:mm').format(nextRun);

    isPaused = true;
    currentStatus = 'Completed. Next run at $formattedNext';
    _addLog('Copy complete. Scheduled next run at $formattedNext (in ${waitDuration.inHours}h ${waitDuration.inMinutes % 60}m).');
    notifyListeners();

    _completionRescheduleTimer = Timer(waitDuration, () {
      _completionRescheduleTimer = null;
      _addLog('Scheduled time reached. Starting new run...');
      isPaused = false;
      startProcessing();
    });
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
      for (int i = 0; i < directoryPairs.length; i++) {
        final pair = directoryPairs[i];
        if (pair.sourcePath != null && pair.destPath != null) {
          _pairsToProcess.add({
            'source': pair.sourcePath!,
            'dest': pair.destPath!,
            'runOrder': pair.runOrder,
            'origIndex': i,
          });
        }
      }
    } else {
      if (sourcePath == null || destPath == null) {
        _addLog('Error: Source or Destination not selected.');
        await _fileLogger.error('Copy', 'Source or Destination not selected.');
        return;
      }
      _pairsToProcess.add({
        'source': sourcePath!,
        'dest': destPath!,
        'runOrder': 1,
        'origIndex': 0,
      });
    }

    if (_pairsToProcess.isEmpty) {
      _addLog('Error: No valid directory pairs configured.');
      return;
    }

    // Build sorted run order groups
    final orderSet = _pairsToProcess.map((p) => p['runOrder'] as int).toSet().toList()..sort();
    _runOrderGroups = orderSet;
    _currentGroupIndex = 0;
    _pairsCompletedInGroup = 0;
    _totalPairsCompleted = 0;
    _pairStats.clear();

    isProcessing = true;
    currentStatus = 'Scanning...';
    filesCopied = 0;
    filesSkipped = 0;
    errors = 0;
    isPaused = false;
    notifyListeners();

    final dateFormat = DateFormat('dd/MM/yyyy');
    _addLog('Starting copy process... (${_pairsToProcess.length} pair(s), ${_runOrderGroups.length} group(s))');
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
      sourcePath: _pairsToProcess.first['source'] as String,
      destPath: _pairsToProcess.first['dest'] as String,
    );

    // Setup periodic schedule evaluation
    _scheduleTimer?.cancel();
    _scheduleTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _evaluateSchedule();
    });

    // Start the first run order group
    await _startCurrentGroup();
  }

  /// Recomputes the aggregate stats from all per-pair stats.
  void _recalcStats() {
    int totalCopied = 0, totalSkipped = 0, totalErrors = 0;
    for (final stats in _pairStats.values) {
      totalCopied += stats[0];
      totalSkipped += stats[1];
      totalErrors += stats[2];
    }
    filesCopied = totalCopied;
    filesSkipped = totalSkipped;
    errors = totalErrors;
  }

  /// Starts all pairs belonging to the current run order group simultaneously.
  Future<void> _startCurrentGroup() async {
    if (_currentGroupIndex >= _runOrderGroups.length) return;
    final currentOrder = _runOrderGroups[_currentGroupIndex];
    final groupPairs = <int>[]; // indices into _pairsToProcess
    for (int i = 0; i < _pairsToProcess.length; i++) {
      if (_pairsToProcess[i]['runOrder'] == currentOrder) {
        groupPairs.add(i);
      }
    }
    _pairsCompletedInGroup = 0;
    _addLog('=== Starting Run Order $currentOrder (${groupPairs.length} pair(s)) ===');
    currentStatus = 'Run Order $currentOrder: Starting...';
    notifyListeners();

    for (final idx in groupPairs) {
      await _startWorkerForPair(idx);
    }
  }

  /// Spawns an isolate for the given pair index and listens for progress.
  /// When done, checks if the current group is complete to start the next.
  Future<void> _startWorkerForPair(int pairIndex) async {
    final pairData = _pairsToProcess[pairIndex];
    final source = pairData['source'] as String;
    final dest = pairData['dest'] as String;
    final origIdx = pairData['origIndex'] as int;
    final runOrder = pairData['runOrder'] as int;
    _addLog('--- Pair ${origIdx + 1} (Order $runOrder): $source → $dest ---');
    if (_activeWorkers.isEmpty) {
      currentStatus = 'Pair ${origIdx + 1}: Scanning...';
    } else {
      currentStatus = 'Running ${_activeWorkers.length + 1} pair(s) (Order $runOrder)...';
    }
    _pairStats[pairIndex] = [0, 0, 0]; // [copied, skipped, errors]
    notifyListeners();

    final receivePort = ReceivePort();

    final params = _IsolateParams(
      sourcePath: source,
      destPath: dest,
      enableDateRange: enableDateRange,
      fromEpochMs: fromDate.millisecondsSinceEpoch,
      toEpochMs: toDate.millisecondsSinceEpoch,
      sendPort: receivePort.sendPort,
    );

    final isolate = await Isolate.spawn(_copyWorker, params);

    late final _ActiveWorker worker;
    final subscription = receivePort.listen((message) async {
      if (message is _IsolateProgress) {
        // Update this pair's running stats
        _pairStats[pairIndex] = [
          message.filesCopied,
          message.filesSkipped,
          message.errors,
        ];
        _recalcStats();

        if (message.status != null && !isPaused) {
          if (_activeWorkers.length == 1) {
            currentStatus = 'P${origIdx + 1}: ${message.status!}';
          } else {
            currentStatus = '${_activeWorkers.length} pairs (Order $runOrder) – P${origIdx + 1}: ${message.status!}';
          }
        }

        if (message.logMessage != null) {
          _addLog('[P${origIdx + 1}] ${message.logMessage!}');
        }

        if (message.errorMessage != null) {
          _addLog('[P${origIdx + 1}] ${message.errorMessage!}');
          await _fileLogger.error('Copy', message.errorMessage!);
        }

        if (message.criticalError != null) {
          _log.severe('Isolate critical error (pair ${origIdx + 1}): ${message.criticalError}');
          await _fileLogger.error(
              'Copy', 'Critical Error (pair ${origIdx + 1}): ${message.criticalError}');
        }

        if (message.done) {
          _addLog('[P${origIdx + 1}] Done: ${message.filesCopied} copied, ${message.filesAlreadyExist} exist, ${message.filesSkipped} skipped, ${message.errors} errors');

          // Clean up this worker
          worker.isolate.kill(priority: Isolate.immediate);
          worker.subscription.cancel();
          worker.receivePort.close();
          _activeWorkers.remove(worker);
          _totalPairsCompleted++;
          _pairsCompletedInGroup++;

          _recalcStats();

          // Check if all pairs in the current group are done
          final currentOrder = _runOrderGroups[_currentGroupIndex];
          final groupSize = _pairsToProcess.where((p) => p['runOrder'] == currentOrder).length;
          if (_pairsCompletedInGroup >= groupSize) {
            _addLog('=== Run Order $currentOrder complete ===');
            _currentGroupIndex++;
            if (_currentGroupIndex < _runOrderGroups.length) {
              // Start next group
              await _startCurrentGroup();
            }
          }

          // Check if ALL pairs are finished
          if (_totalPairsCompleted >= _pairsToProcess.length) {
            _addLog('All ${_pairsToProcess.length} pair(s) completed. Total: $filesCopied copied, $errors errors.');

            await _fileLogger.logRunEnd(
              operation: 'Copy',
              filesProcessed: filesCopied,
              errors: errors,
              wasStopped: false,
            );

            if (onCompletionAction == 'pause') {
              // Stay in processing state and wait for next run time
              _scheduleTimer?.cancel();
              _scheduleTimer = null;
              _scheduleNextRun();
            } else {
              // 'stop' – fully stop
              isProcessing = false;
              currentStatus = 'Idle';
              _scheduleTimer?.cancel();
              _scheduleTimer = null;
            }
          }
        }

        notifyListeners();
      }
    });

    worker = _ActiveWorker(
      pairIndex: pairIndex,
      isolate: isolate,
      receivePort: receivePort,
      subscription: subscription,
    );
    _activeWorkers.add(worker);
    _evaluateSchedule();
  }
}
