import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import '../services/file_logger.dart';
import '../services/history_service.dart';
import '../services/local_db_service.dart';
import '../models/run_record.dart';

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
  final bool enableAgeFilter;
  final String ageFilterUnit;
  final int ageFilterValue;
  final SendPort sendPort;
  final String? progressFilePath;
  final Set<String> completedDirs;
  final int logInterval;

  _IsolateParams({
    required this.sourcePath,
    required this.destPath,
    required this.enableDateRange,
    required this.fromEpochMs,
    required this.toEpochMs,
    required this.enableAgeFilter,
    required this.ageFilterUnit,
    required this.ageFilterValue,
    required this.sendPort,
    this.progressFilePath,
    this.completedDirs = const {},
    this.logInterval = 100,
  });
}

/// Mutable counters passed through the recursive walk inside the isolate.
class _CountState {
  int filesCopied = 0;
  int filesSkipped = 0;
  int filesAlreadyExist = 0;
  int errors = 0;
  int directoriesScanned = 0;
  int filesInspected = 0;
  int dirsSkipped = 0;
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

/// Semaphore for controlling concurrent copy operations.
class _Semaphore {
  final int maxConcurrent;
  int _current = 0;
  final List<Completer<void>> _waiters = [];

  _Semaphore(this.maxConcurrent);

  Future<void> acquire() async {
    if (_current < maxConcurrent) {
      _current++;
      return;
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    await completer.future;
    _current++;
  }

  void release() {
    _current--;
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
    }
  }
}

class CopyFilesProvider with ChangeNotifier {
  final Logger _log = Logger('CopyFilesProvider');
  final FileLogger _fileLogger = FileLogger();
  final NumberFormat _numFmt = NumberFormat('#,##0');

  static const String _progressDir = r'C:\temp\file transfer';

  /// Returns the progress file path for a given pair index.
  static String _progressFilePath(int pairIndex) =>
      '$_progressDir\\copy_progress_pair$pairIndex.json';

  /// Loads completed directory paths from a progress file.
  /// Returns an empty set if the file doesn't exist or source/dest don't match.
  static Set<String> _loadProgressFile(
      String filePath, String sourcePath, String destPath) {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return {};
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      if (data['sourcePath'] != sourcePath || data['destPath'] != destPath) {
        // Source/dest changed since last run — discard stale progress
        file.deleteSync();
        return {};
      }
      final dirs = (data['completedDirs'] as List).cast<String>();
      return dirs.toSet();
    } catch (_) {
      return {};
    }
  }

  /// Saves completed directory paths to a progress file (called inside isolate).
  static void _saveProgressFile(
      String filePath, String sourcePath, String destPath, Set<String> completedDirs) {
    try {
      final dir = Directory(_progressDir);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final data = {
        'sourcePath': sourcePath,
        'destPath': destPath,
        'completedDirs': completedDirs.toList(),
      };
      File(filePath).writeAsStringSync(jsonEncode(data));
    } catch (_) {
      // Silently fail — don't crash if progress save fails
    }
  }

  /// Deletes the progress file for a pair (called on successful completion).
  static void _deleteProgressFile(String filePath) {
    try {
      final file = File(filePath);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }

  // State
  String? sourcePath;
  String? destPath;

  // Multiple directory pairs
  bool useMultipleDirectories = false;
  List<DirectoryPair> directoryPairs = [DirectoryPair()];

  // Log interval: how often to report progress (every N files)
  // Available options: 1, 5, 10, 25, 50, 100
  int logInterval = 100;

  // Age filter
  bool enableAgeFilter = false;
  String ageFilterUnit = 'Days';
  int ageFilterValue = 30;

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
  int filesAlreadyExist = 0;
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

  @override
  void dispose() {
    _scheduleTimer?.cancel();
    _completionRescheduleTimer?.cancel();
    for (final worker in _activeWorkers) {
      worker.isolate.kill(priority: Isolate.immediate);
      worker.subscription.cancel();
      worker.receivePort.close();
    }
    super.dispose();
  }

  void _addLog(String message) {
    final timestamp = DateFormat('HH:mm:ss').format(DateTime.now());
    logs.insert(0, '[$timestamp] $message');
    if (logs.length > 1000) logs.removeLast();
  }

  /// Formats elapsed time from the file logger's tracked start time.
  String _getElapsedStr() {
    final start = _fileLogger.getStartTime('Copy');
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

  Future<void> _loadSettings() async {
    final db = LocalDbService();
    sourcePath = db.getString('copy_sourcePath');
    destPath = db.getString('copy_destPath');

    final fDay = db.getInt('copy_fromDate_day');
    final fMonth = db.getInt('copy_fromDate_month');
    final fYear = db.getInt('copy_fromDate_year');
    if (fDay != null && fMonth != null && fYear != null) {
      fromDate = DateTime(fYear, fMonth, fDay);
    }
    final tDay = db.getInt('copy_toDate_day');
    final tMonth = db.getInt('copy_toDate_month');
    final tYear = db.getInt('copy_toDate_year');
    if (tDay != null && tMonth != null && tYear != null) {
      toDate = DateTime(tYear, tMonth, tDay);
    }
    
    enableAgeFilter = db.getBool('copy_enableAgeFilter') ?? false;
    ageFilterUnit = db.getString('copy_ageFilterUnit') ?? 'Days';
    ageFilterValue = db.getInt('copy_ageFilterValue') ?? 30;

    enableDateRange = db.getBool('copy_enableDateRange') ?? false;
    todayOnly = db.getBool('copy_todayOnly') ?? false;
    yesterdayOnly = db.getBool('copy_yesterdayOnly') ?? false;

    logInterval = db.getInt('copy_logInterval') ?? 100;

    // Apply quick date filter on load if active
    _applyQuickDateFilter();

    // Load multiple directories
    useMultipleDirectories = db.getBool('copy_useMultiDirs') ?? false;
    final pairsJson = db.getString('copy_directoryPairs');
    if (pairsJson != null) {
      try {
        final list = jsonDecode(pairsJson) as List;
        directoryPairs = list.map((m) => DirectoryPair.fromJson(Map<String, dynamic>.from(m))).toList();
      } catch (_) {
        directoryPairs = [DirectoryPair()];
      }
    }
    if (directoryPairs.isEmpty) directoryPairs = [DirectoryPair()];

    enableTimeWindow = db.getBool('copy_enableTimeWindow') ?? false;
    
    final fromHour = db.getInt('copy_runFromHour');
    final fromMinute = db.getInt('copy_runFromMinute');
    if (fromHour != null && fromMinute != null) {
      runFromTime = TimeOfDay(hour: fromHour, minute: fromMinute);
    }

    final toHour = db.getInt('copy_runToHour');
    final toMinute = db.getInt('copy_runToMinute');
    if (toHour != null && toMinute != null) {
      runToTime = TimeOfDay(hour: toHour, minute: toMinute);
    }

    // Load run days
    for (int day = 1; day <= 7; day++) {
      runDays[day] = db.getBool('copy_runDay_$day') ?? false;
    }

    onCompletionAction = db.getString('copy_onCompletionAction') ?? 'pause';

    notifyListeners();
  }

  Future<void> _saveSettings() async {
    final db = LocalDbService();
    if (sourcePath != null) {
      await db.setString('copy_sourcePath', sourcePath!);
    }
    if (destPath != null) {
      await db.setString('copy_destPath', destPath!);
    }
    await db.setInt('copy_fromDate_day', fromDate.day);
    await db.setInt('copy_fromDate_month', fromDate.month);
    await db.setInt('copy_fromDate_year', fromDate.year);
    
    await db.setInt('copy_toDate_day', toDate.day);
    await db.setInt('copy_toDate_month', toDate.month);
    await db.setInt('copy_toDate_year', toDate.year);

    await db.setBool('copy_enableAgeFilter', enableAgeFilter);
    await db.setString('copy_ageFilterUnit', ageFilterUnit);
    await db.setInt('copy_ageFilterValue', ageFilterValue);

    await db.setBool('copy_enableDateRange', enableDateRange);
    await db.setBool('copy_todayOnly', todayOnly);
    await db.setBool('copy_yesterdayOnly', yesterdayOnly);

    await db.setInt('copy_logInterval', logInterval);

    await db.setBool('copy_enableTimeWindow', enableTimeWindow);
    await db.setInt('copy_runFromHour', runFromTime.hour);
    await db.setInt('copy_runFromMinute', runFromTime.minute);
    await db.setInt('copy_runToHour', runToTime.hour);
    await db.setInt('copy_runToMinute', runToTime.minute);

    // Save run days
    for (int day = 1; day <= 7; day++) {
      await db.setBool('copy_runDay_$day', runDays[day] ?? false);
    }

    // Save multiple directories
    await db.setBool('copy_useMultiDirs', useMultipleDirectories);
    final pairsJson = jsonEncode(directoryPairs.map((p) => p.toJson()).toList());
    await db.setString('copy_directoryPairs', pairsJson);

    await db.setString('copy_onCompletionAction', onCompletionAction);
  }

  String? _sanitizePath(String? path) {
    if (path == null) return null;
    final clean = path.replaceAll('"', '').replaceAll("'", "").trim();
    return clean.isEmpty ? null : clean;
  }

  void setSourcePath(String? path) {
    sourcePath = _sanitizePath(path);
    if (sourcePath != null) {
      LocalDbService().addRecentDirectory(sourcePath!);
    }
    _saveSettings();
    notifyListeners();
  }

  void setDestPath(String? path) {
    destPath = _sanitizePath(path);
    if (destPath != null) {
      LocalDbService().addRecentDirectory(destPath!);
    }
    _saveSettings();
    notifyListeners();
  }

  void setLogInterval(int val) {
    logInterval = val;
    _saveSettings();
    notifyListeners();
  }

  void setEnableAgeFilter(bool val) {
    enableAgeFilter = val;
    if (val) {
      enableDateRange = false;
      todayOnly = false;
      yesterdayOnly = false;
    }
    _saveSettings();
    notifyListeners();
  }

  void setAgeFilterUnit(String unit) {
    ageFilterUnit = unit;
    _saveSettings();
    notifyListeners();
  }

  void setAgeFilterValue(int val) {
    ageFilterValue = val;
    _saveSettings();
    notifyListeners();
  }

  void setEnableDateRange(bool val) {
    enableDateRange = val;
    // Uncheck quick filters when manually toggling date range off
    if (!val) {
      todayOnly = false;
      yesterdayOnly = false;
    } else {
      enableAgeFilter = false;
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
    if (val) enableAgeFilter = false;
    _applyQuickDateFilter();
    _saveSettings();
    notifyListeners();
  }

  void setYesterdayOnly(bool val) {
    yesterdayOnly = val;
    if (val) enableAgeFilter = false;
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
    if (path != null) setPairSource(index, path);
  }

  Future<void> pickPairDest(int index) async {
    final path = await getDirectoryPath(initialDirectory: directoryPairs[index].destPath);
    if (path != null) setPairDest(index, path);
  }

  void setPairSource(int index, String? path) {
    if (index < 0 || index >= directoryPairs.length) return;
    final sanitized = _sanitizePath(path);
    directoryPairs[index].sourcePath = sanitized;
    if (sanitized != null) {
      LocalDbService().addRecentDirectory(sanitized);
    }
    _saveSettings();
    notifyListeners();
  }

  void setPairDest(int index, String? path) {
    if (index < 0 || index >= directoryPairs.length) return;
    final sanitized = _sanitizePath(path);
    directoryPairs[index].destPath = sanitized;
    if (sanitized != null) {
      LocalDbService().addRecentDirectory(sanitized);
    }
    _saveSettings();
    notifyListeners();
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

  /// Clears all saved resume progress. Call this to force a full re-scan.
  Future<void> clearProgress() async {
    for (int i = 0; i < 20; i++) {
      _deleteProgressFile(_progressFilePath(i));
    }
    _addLog('✓ Resume progress cleared. Next run will scan from scratch.');
    notifyListeners();
  }

  void stop() {
    _killAllWorkers();
    _scheduleTimer?.cancel();
    _scheduleTimer = null;
    _completionRescheduleTimer?.cancel();
    _completionRescheduleTimer = null;
    
    isPaused = false;
    currentStatus = '⛔ Stopped. Progress saved — will resume on next start.';
    _addLog('⛔ Stopped by user. Progress saved — next start will resume where it left off.');
    isProcessing = false;
    notifyListeners();

    // Capture before logRunEnd clears them
    final runId = _fileLogger.getRunId('Copy') ?? 'UNKNOWN';
    final start = _fileLogger.getStartTime('Copy') ?? DateTime.now();

    _fileLogger.logRunEnd(
      operation: 'Copy',
      filesProcessed: filesCopied,
      errors: errors,
      wasStopped: true,
    );

    try {
      HistoryService().saveRecord(RunRecord(
        id: runId,
        operation: 'Copy',
        startTime: start,
        endTime: DateTime.now(),
        filesProcessed: filesCopied,
        errors: errors,
        status: 'Stopped',
        configSummary: 'Pairs: ${_pairsToProcess.length}, Dest: ${destPath ?? "Multiple"}',
      ));
    } catch (_) {}
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
      // from == to → treat as no restriction (run freely).
      return true;
    }
  }

  void _evaluateSchedule() {
    if (!isProcessing) return;
    
    bool inWindow = _isCurrentlyInTimeWindow();
    
    if (inWindow && isPaused) {
      // If quick date filters are active, the dates may be stale after an
      // overnight pause.  Kill the old isolates and restart with fresh dates.
      if (todayOnly || yesterdayOnly) {
        _addLog('⏳ Time window reached. Restarting with updated dates...');
        _killAllWorkers();
        isPaused = false;
        // startProcessing will call _applyQuickDateFilter() and spawn new isolates.
        startProcessing();
        return;
      }

      if (_activeWorkers.isEmpty) {
        // Workers haven't been spawned yet (started outside the time window).
        // Now that we're inside the window, spawn them.
        isPaused = false;
        currentStatus = '⏳ Copying...';
        _addLog('⏳ Time window reached. Starting copy...');
        notifyListeners();
        _startCurrentGroup();
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
      currentStatus = '⏳ Copying...';
      _addLog('⏳ Time window reached. Resuming copy...');
      notifyListeners();
    } else if (!inWindow && !isPaused) {
      if (_activeWorkers.isEmpty) return; // Nothing to pause yet
      // Pause all active workers
      for (final w in _activeWorkers) {
        if (!w.isPaused) {
          w.pauseCapability = w.isolate.pause();
          w.isPaused = true;
        }
      }
      isPaused = true;
      currentStatus = '⏸ Waiting for time window...';
      _addLog('⏸ Outside allowed time window. Paused until next run window.');
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
    currentStatus = '🏁 Completed. Next run at $formattedNext';
    _addLog('🏁 Copy complete. Scheduled next run at $formattedNext (in ${waitDuration.inHours}h ${waitDuration.inMinutes % 60}m).');
    notifyListeners();

    _completionRescheduleTimer = Timer(waitDuration, () {
      _completionRescheduleTimer = null;
      _addLog('⏳ Scheduled time reached. Starting new run...');
      isPaused = false;
      startProcessing();
    });
  }

  /// Process a batch of copy tasks with controlled concurrency (max 6 parallel).
  static Future<void> _processBatch(
    List<_CopyTask> batch,
    _IsolateParams params,
    _CountState counts,
  ) async {
    final semaphore = _Semaphore(6); // Max 6 concurrent network copies

    final futures = batch.map((task) async {
      await semaphore.acquire();
      try {
        await task.source.copy(task.destFilePath);
        counts.filesCopied++;

        if (counts.filesCopied % params.logInterval == 0) {
          params.sendPort.send(_IsolateProgress(
            logMessage: '✓ Copied ${params.logInterval} files (total: ${counts.filesCopied}) – latest: ${p.basename(task.source.path)}',
            status: 'Copying: ${p.basename(task.source.path)} (${counts.filesCopied} copied)',
            filesCopied: counts.filesCopied,
            filesSkipped: counts.filesSkipped,
            filesAlreadyExist: counts.filesAlreadyExist,
            errors: counts.errors,
          ));
        }
      } catch (e) {
        counts.errors++;
        params.sendPort.send(_IsolateProgress(
          errorMessage: '✗ Failed to copy ${p.basename(task.source.path)}: $e',
          errors: counts.errors,
          filesCopied: counts.filesCopied,
          filesSkipped: counts.filesSkipped,
          filesAlreadyExist: counts.filesAlreadyExist,
        ));
      } finally {
        semaphore.release();
      }
    });

    await Future.wait(futures);
  }

  /// Manual recursive walk optimised for network shares.
  ///
  /// Key optimisations vs the previous version:
  /// 1. Single stat() per source file (gets both size & modified date).
  /// 2. Pre-lists the destination directory once to build a name→size map,
  ///    replacing N individual stat() calls with 1 directory listing.
  /// 3. Reduced concurrent file inspection from 50 to 8 to avoid
  ///    overwhelming SMB connections.
  /// 4. Progress reported every 5 directories (was 20) with a running
  ///    file count so the UI never looks frozen.
  static Future<void> _walkAndCopy(
    Directory dir,
    _IsolateParams params,
    _CountState counts,
    Set<String> createdDirs,
    List<_CopyTask> batch,
    Set<String> completedDirs,
  ) async {
    // ── Resume: skip directories that were fully processed in a prior run ──
    final String relPath = p.relative(dir.path, from: params.sourcePath);
    if (completedDirs.contains(relPath)) {
      counts.dirsSkipped++;
      return;
    }
    List<FileSystemEntity> entities;
    try {
      entities = await dir.list(followLinks: true).toList();
    } catch (e) {
      counts.errors++;
      params.sendPort.send(_IsolateProgress(
        errorMessage: '✗ Cannot access: ${dir.path} ($e)',
        errors: counts.errors,
        filesCopied: counts.filesCopied,
        filesSkipped: counts.filesSkipped,
        filesAlreadyExist: counts.filesAlreadyExist,
      ));
      return;
    }

    counts.directoriesScanned++;

    // Report scanning progress based on logInterval
    // For interval 1-10, report every directory; for larger intervals, every 5 dirs
    final dirReportInterval = params.logInterval <= 10 ? 1 : 5;
    if (counts.directoriesScanned % dirReportInterval == 0) {
      params.sendPort.send(_IsolateProgress(
        status: '⏳ Scanning: ${p.basename(dir.path)} (${counts.filesInspected} files checked, ${counts.filesAlreadyExist} already exist)',
        filesCopied: counts.filesCopied,
        filesSkipped: counts.filesSkipped,
        filesAlreadyExist: counts.filesAlreadyExist,
        errors: counts.errors,
      ));
    }

    final files = entities.where((e) => FileSystemEntity.isFileSync(e.path)).toList();

    // If no files in this directory, skip straight to subdirectories
    if (files.isEmpty) {
      for (final entity in entities) {
        if (FileSystemEntity.isDirectorySync(entity.path)) {
          await _walkAndCopy(Directory(entity.path), params, counts, createdDirs, batch, completedDirs);
        }
      }
      return;
    }

    // ── Pre-compute date boundaries once per directory ──────────────
    late final DateTime from;
    late final DateTime to;
    if (params.enableDateRange) {
      final fd = DateTime.fromMillisecondsSinceEpoch(params.fromEpochMs);
      final td = DateTime.fromMillisecondsSinceEpoch(params.toEpochMs);
      from = DateTime(fd.year, fd.month, fd.day);
      to   = DateTime(td.year, td.month, td.day);
    }

    late final DateTime ageThreshold;
    if (params.enableAgeFilter) {
      final now = DateTime.now();
      if (params.ageFilterUnit == 'Days') {
        ageThreshold = now.subtract(Duration(days: params.ageFilterValue));
      } else if (params.ageFilterUnit == 'Months') {
        ageThreshold = DateTime(now.year, now.month - params.ageFilterValue, now.day);
      } else {
        ageThreshold = DateTime(now.year - params.ageFilterValue, now.month, now.day);
      }
    }

    // ── Pre-list destination directory ──────────────────────────────
    // Build a name→size map with a single dir listing instead of
    // stat()-ing each destination file individually (huge win on SMB).
    final String destDirPath = p.join(params.destPath, relPath);
    final Map<String, int> existingDestFiles = {};
    try {
      final destDir = Directory(destDirPath);
      if (await destDir.exists()) {
        await for (final e in destDir.list(followLinks: true)) {
          if (FileSystemEntity.isFileSync(e.path)) {
            try {
              existingDestFiles[p.basename(e.path)] = await File(e.path).length();
            } catch (_) {}
          }
        }
      }
    } catch (_) {
      // Destination dir doesn't exist yet — all files will need copying
    }

    // ── Process source files in small batches of 8 ─────────────────
    // Was 50, which created I/O storms on network shares.
    for (var i = 0; i < files.length; i += 8) {
      final chunk = files.skip(i).take(8);

      final futures = chunk.map((fsEntity) async {
        final entity = File(fsEntity.path);
        try {
          counts.filesInspected++;

          // Single stat() gets both size and modified date — avoids the
          // old pattern of conditional stat() + separate length() call.
          final FileStat stats = await entity.stat();
          final int sourceSize = stats.size;

          // Age filter
          if (params.enableAgeFilter) {
            if (stats.modified.isAfter(ageThreshold)) {
              counts.filesSkipped++;
              return;
            }
          }

          // Date-range filter
          if (params.enableDateRange) {
            final m = stats.modified;
            final fileDate = DateTime(m.year, m.month, m.day);
            if (fileDate.isBefore(from) || fileDate.isAfter(to)) {
              counts.filesSkipped++;
              return;
            }
          }

          final String fileName = p.basename(entity.path);

          // Fast map lookup instead of per-file destination stat()
          final int? destSize = existingDestFiles[fileName];
          if (destSize != null && destSize == sourceSize) {
            counts.filesAlreadyExist++;

            // Log "already exist" progress at the configured interval
            if (counts.filesAlreadyExist % params.logInterval == 0) {
              params.sendPort.send(_IsolateProgress(
                logMessage: '⏭ ${counts.filesAlreadyExist} files already exist at destination (skipping)',
                status: '⏭ Checking: ${p.basename(dir.path)} – ${counts.filesAlreadyExist} already exist, ${counts.filesCopied} copied',
                filesCopied: counts.filesCopied,
                filesSkipped: counts.filesSkipped,
                filesAlreadyExist: counts.filesAlreadyExist,
                errors: counts.errors,
              ));
            }
            return;
          }

          // File needs copying — ensure destination directory exists
          if (!createdDirs.contains(destDirPath)) {
            createdDirs.add(destDirPath);
            await Directory(destDirPath).create(recursive: true);
          }
          batch.add(_CopyTask(entity, p.join(destDirPath, fileName)));
        } catch (e) {
          counts.errors++;
          params.sendPort.send(_IsolateProgress(
            errorMessage: '✗ Failed to inspect ${p.basename(entity.path)}: $e',
            errors: counts.errors,
            filesCopied: counts.filesCopied,
            filesSkipped: counts.filesSkipped,
            filesAlreadyExist: counts.filesAlreadyExist,
          ));
        }
      });

      await Future.wait(futures);

      // Extra progress pulse for large directories
      final pulseInterval = params.logInterval <= 10 ? 8 : 24;
      if (i > 0 && i % pulseInterval == 0) {
        params.sendPort.send(_IsolateProgress(
          status: '⏳ Scanning: ${p.basename(dir.path)} (${counts.filesInspected} files checked, ${counts.filesAlreadyExist} already exist)',
          filesCopied: counts.filesCopied,
          filesSkipped: counts.filesSkipped,
          filesAlreadyExist: counts.filesAlreadyExist,
          errors: counts.errors,
        ));
      }

      // Flush the batch when it reaches 50 tasks
      if (batch.length >= 50) {
        final tasksToRun = List<_CopyTask>.from(batch);
        batch.clear();
        await _processBatch(tasksToRun, params, counts);
        await Future.delayed(Duration.zero);
      }
    }

    // Then recurse into subdirectories
    for (final entity in entities) {
      if (FileSystemEntity.isDirectorySync(entity.path)) {
        await _walkAndCopy(Directory(entity.path), params, counts, createdDirs, batch, completedDirs);
      }
    }

    // Mark this directory as fully completed (files + all subdirs done)
    completedDirs.add(relPath);

    // Periodically save progress to disk (every 100 completed directories)
    if (params.progressFilePath != null && completedDirs.length % 100 == 0) {
      _saveProgressFile(
        params.progressFilePath!, params.sourcePath, params.destPath, completedDirs);
    }
  }

  /// Top-level isolate entry point.
  static Future<void> _copyWorker(_IsolateParams params) async {
    final counts = _CountState();
    final createdDirs = <String>{};
    final batch = <_CopyTask>[];
    // Mutable copy of completed dirs — will grow as we process
    final completedDirs = Set<String>.from(params.completedDirs);
    final isResuming = completedDirs.isNotEmpty;

    try {
      final sourceDir = Directory(params.sourcePath);
      if (!sourceDir.existsSync()) {
        params.sendPort.send(_IsolateProgress(
          errorMessage: '✗ Error: Source directory does not exist.',
          done: true,
          errors: 1,
        ));
        return;
      }

      if (isResuming) {
        params.sendPort.send(_IsolateProgress(
          logMessage: '⏩ Resuming — ${completedDirs.length} directories already completed, skipping...',
          status: '⏩ Resuming from last position...',
        ));
      }

      await _walkAndCopy(sourceDir, params, counts, createdDirs, batch, completedDirs);

      // Process remaining tasks in the final batch
      if (batch.isNotEmpty) {
        await _processBatch(batch, params, counts);
        batch.clear();
      }

      // Save final progress before sending done
      if (params.progressFilePath != null) {
        _saveProgressFile(
          params.progressFilePath!, params.sourcePath, params.destPath, completedDirs);
      }

      final resumeNote = isResuming ? ' (${counts.dirsSkipped} dirs skipped via resume)' : '';
      params.sendPort.send(_IsolateProgress(
        logMessage: '🏁 Copy completed successfully.$resumeNote',
        status: 'Done',
        done: true,
        filesCopied: counts.filesCopied,
        filesSkipped: counts.filesSkipped,
        filesAlreadyExist: counts.filesAlreadyExist,
        errors: counts.errors,
      ));

      // Delete progress file on successful completion
      if (params.progressFilePath != null) {
        _deleteProgressFile(params.progressFilePath!);
      }
    } catch (e) {
      // Save progress even on crash so next run can resume
      if (params.progressFilePath != null) {
        _saveProgressFile(
          params.progressFilePath!, params.sourcePath, params.destPath, completedDirs);
      }
      params.sendPort.send(_IsolateProgress(
        logMessage: '✗ Critical Error: $e',
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
        _addLog('✗ Error: Source or Destination not selected.');
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
      _addLog('✗ Error: No valid directory pairs configured.');
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
    currentStatus = '⏳ Scanning...';
    filesCopied = 0;
    filesSkipped = 0;
    filesAlreadyExist = 0;
    errors = 0;
    isPaused = false;
    notifyListeners();

    final dateFormat = DateFormat('dd/MM/yyyy');
    _addLog('⏳ Starting copy process... (${_pairsToProcess.length} pair(s), ${_runOrderGroups.length} group(s))');
    if (enableDateRange) {
      _addLog('  Date range: ${dateFormat.format(fromDate)} — ${dateFormat.format(toDate)}');
    }
    if (enableTimeWindow) {
      final String formattedFrom = '${runFromTime.hour.toString().padLeft(2, '0')}:${runFromTime.minute.toString().padLeft(2, '0')}';
      final String formattedTo = '${runToTime.hour.toString().padLeft(2, '0')}:${runToTime.minute.toString().padLeft(2, '0')}';
      _addLog('  Run window: $formattedFrom – $formattedTo');
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

    // Check if we're inside the time window before spawning workers.
    // If outside, set paused and wait — the periodic timer will start
    // workers when the window opens.
    if (!_isCurrentlyInTimeWindow()) {
      isPaused = true;
      currentStatus = '⏸ Waiting for time window...';
      _addLog('⏸ Outside allowed time window. Waiting to start...');
      notifyListeners();
      return;
    }

    // Start the first run order group
    await _startCurrentGroup();
  }

  /// Recomputes the aggregate stats from all per-pair stats.
  void _recalcStats() {
    int totalCopied = 0, totalSkipped = 0, totalAlreadyExist = 0, totalErrors = 0;
    for (final stats in _pairStats.values) {
      totalCopied += stats[0];
      totalSkipped += stats[1];
      totalErrors += stats[2];
      totalAlreadyExist += stats.length > 3 ? stats[3] : 0;
    }
    filesCopied = totalCopied;
    filesSkipped = totalSkipped;
    filesAlreadyExist = totalAlreadyExist;
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
    _addLog('═══ Starting Run Order $currentOrder (${groupPairs.length} pair(s)) ═══');
    currentStatus = '⏳ Run Order $currentOrder: Starting...';
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
    _addLog('── Pair ${origIdx + 1} (Order $runOrder): $source → $dest');
    if (_activeWorkers.isEmpty) {
      currentStatus = '⏳ Pair ${origIdx + 1}: Scanning...';
    } else {
      currentStatus = '⏳ Running ${_activeWorkers.length + 1} pair(s) (Order $runOrder)...';
    }
    _pairStats[pairIndex] = [0, 0, 0, 0]; // [copied, skipped, errors, alreadyExist]
    notifyListeners();

    final receivePort = ReceivePort();

    // Load resume progress for this pair (if any)
    final progressPath = _progressFilePath(origIdx);
    final resumeDirs = _loadProgressFile(progressPath, source, dest);
    if (resumeDirs.isNotEmpty) {
      _addLog('[P${origIdx + 1}] ⏩ Resuming: ${resumeDirs.length} directories already completed');
    }

    final params = _IsolateParams(
      sourcePath: source,
      destPath: dest,
      enableDateRange: enableDateRange,
      fromEpochMs: fromDate.millisecondsSinceEpoch,
      toEpochMs: toDate.millisecondsSinceEpoch,
      enableAgeFilter: enableAgeFilter,
      ageFilterUnit: ageFilterUnit,
      ageFilterValue: ageFilterValue,
      sendPort: receivePort.sendPort,
      progressFilePath: progressPath,
      completedDirs: resumeDirs,
      logInterval: logInterval,
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
          message.filesAlreadyExist,
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
          _addLog('[P${origIdx + 1}] 🏁 Done: ${_numFmt.format(message.filesCopied)} copied, ${_numFmt.format(message.filesAlreadyExist)} exist, ${_numFmt.format(message.filesSkipped)} skipped, ${_numFmt.format(message.errors)} errors');

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
            _addLog('═══ Run Order $currentOrder complete ═══');
            _currentGroupIndex++;
            if (_currentGroupIndex < _runOrderGroups.length) {
              // Start next group
              await _startCurrentGroup();
            }
          }

          // Check if ALL pairs are finished
          if (_totalPairsCompleted >= _pairsToProcess.length) {
            final elapsed = _getElapsedStr();
            _addLog('🏁 All ${_pairsToProcess.length} pair(s) completed. Total: ${_numFmt.format(filesCopied)} copied, ${_numFmt.format(errors)} errors in $elapsed');

            // Capture before logRunEnd clears them
            final runId = _fileLogger.getRunId('Copy') ?? 'UNKNOWN';
            final start = _fileLogger.getStartTime('Copy') ?? DateTime.now();

            await _fileLogger.logRunEnd(
              operation: 'Copy',
              filesProcessed: filesCopied,
              errors: errors,
              wasStopped: false,
            );

            try {
              await HistoryService().saveRecord(RunRecord(
                id: runId,
                operation: 'Copy',
                startTime: start,
                endTime: DateTime.now(),
                filesProcessed: filesCopied,
                errors: errors,
                status: 'Completed',
                configSummary: 'Pairs: ${_pairsToProcess.length}, Dest: ${destPath ?? "Multiple"}',
              ));
            } catch (_) {}

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

    // If the provider is already in paused state (e.g., a previous worker in
    // this group triggered the pause), immediately pause this new worker too.
    if (isPaused) {
      worker.pauseCapability = worker.isolate.pause();
      worker.isPaused = true;
    } else {
      _evaluateSchedule();
    }
  }
}
