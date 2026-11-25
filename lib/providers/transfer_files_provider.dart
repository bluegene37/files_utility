import 'dart:async';
import 'dart:convert';
import 'dart:io';
// Gene - Nov, 25, 2026: Replaced Dart isolate worker and Dart symlink helper with native Rust transfer_engine.
// import 'dart:isolate';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import '../services/file_logger.dart';
import '../services/history_service.dart';
import '../services/local_db_service.dart';
// import '../services/path_safety.dart';
import '../services/rust_transfer_engine.dart';
import '../models/run_record.dart';
import '../services/global_db_service.dart';

// Gene - Nov, 25, 2026: Replaced Dart isolate control/params/progress structs with native Rust transfer_engine.
// class _TransferControl {
//   final bool pause;
//   final bool resume;
//   final bool stop;
//   _TransferControl({
//     this.pause = false,
//     this.resume = false,
//     this.stop = false,
//   });
// }
//
// class _TransferParams {
//   final String sourcePath;
//   final String destPath;
//   final bool enableAgeFilter;
//   final String ageFilterUnit;
//   final int ageFilterValue;
//   final bool enableDateRange;
//   final int fromEpochMs;
//   final int toEpochMs;
//   final bool excludeSubfolders;
//   final String? lastScannedDir;
//   final SendPort mainSendPort;
//   final int initialFilesMoved;
//   final int initialErrors;
//   final int logInterval;
//
//   _TransferParams({
//     required this.sourcePath,
//     required this.destPath,
//     required this.enableAgeFilter,
//     required this.ageFilterUnit,
//     required this.ageFilterValue,
//     required this.enableDateRange,
//     required this.fromEpochMs,
//     required this.toEpochMs,
//     required this.excludeSubfolders,
//     this.lastScannedDir,
//     required this.mainSendPort,
//     this.initialFilesMoved = 0,
//     this.initialErrors = 0,
//     required this.logInterval,
//   });
// }
//
// class _TransferProgress {
//   final int filesMoved;
//   final int errors;
//   final List<String> logs;
//   final String? currentStatus;
//   final bool isDone;
//   final String? criticalError;
//   final String? saveScannedDir;
//   final SendPort? workerSendPort;
//
//   _TransferProgress({
//     this.filesMoved = 0,
//     this.errors = 0,
//     this.logs = const [],
//     this.currentStatus,
//     this.isDone = false,
//     this.criticalError,
//     this.saveScannedDir,
//     this.workerSendPort,
//   });
// }

class TransferFilesProvider with ChangeNotifier {
  final Logger _log = Logger('TransferFilesProvider');
  final FileLogger _fileLogger = FileLogger();
  final NumberFormat _numFmt = NumberFormat('#,##0');

  // State
  String? sourcePath;
  String? destPath;

  static DateTime get _defaultFromDate {
    final now = DateTime.now();
    return DateTime(now.year, now.month, 1);
  }

  static DateTime get _defaultToDate {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  // Date range filter for Transfer
  bool enableDateRange = false;
  DateTime fromDate = _defaultFromDate;
  DateTime toDate = _defaultToDate;

  // Quick date filter: "Today Only" and "Yesterday Only"
  bool todayOnly = false;
  bool yesterdayOnly = false;

  bool isProcessing = false;
  List<String> logs = [];
  String currentStatus = 'Idle';

  bool enableAgeFilter = false;
  String ageFilterUnit = 'Days';
  int ageFilterValue = 30;
  bool excludeSubfolders = false;

  // Log interval: how often to report progress (every N files)
  int logInterval = 100;

  // Resume state
  String? lastScannedDir;

  // Stats
  int filesMoved = 0;
  int errors = 0;
  // Gene - Nov, 25, 2026: Track live scanned files and directories count from the Rust transfer engine.
  int filesScanned = 0;
  int dirsScanned = 0;
  int _sessionStartFilesMoved = 0;
  int _sessionStartErrors = 0;

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

  bool _stopRequested = false;
  Timer? _refreshTimer;
  // Gene - Nov, 25, 2026: Replaced Dart isolate handle/ports with RustTransferJob and polling timer.
  // Timer? _isolateKillTimer;

  // Pause/Schedule State
  bool isPaused = false;
  Timer? _scheduleTimer;
  Timer? _completionRescheduleTimer;
  Completer<void>? _pauseCompleter;

  // Isolate state
  // Isolate? _workerIsolate;
  // SendPort? _workerControlPort;
  RustTransferJob? _rustJob;
  Timer? _pollTimer;
  Timer? _stopFallbackTimer;

  TransferFilesProvider() {
    _loadSettings();
    LocalDbService().addListener(_onProfileChanged);
  }

  void _onProfileChanged() {
    reloadSettings();
  }

  bool _isDisposed = false;

  @override
  void dispose() {
    _isDisposed = true;
    LocalDbService().removeListener(_onProfileChanged);
    _refreshTimer?.cancel();
    _scheduleTimer?.cancel();
    _completionRescheduleTimer?.cancel();
    // Gene - Nov, 25, 2026: Dispose native Rust transfer job and poll/stop timers instead of Dart isolate.
    // _isolateKillTimer?.cancel();
    // _workerIsolate?.kill(priority: Isolate.immediate);
    _pollTimer?.cancel();
    _stopFallbackTimer?.cancel();
    _rustJob?.dispose();
    _rustJob = null;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
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

  Future<void> _loadSettings() async {
    final db = LocalDbService();
    sourcePath = db.getString('sourcePath');
    destPath = db.getString('destPath');

    final fDay = db.getInt('transfer_fromDate_day');
    final fMonth = db.getInt('transfer_fromDate_month');
    final fYear = db.getInt('transfer_fromDate_year');
    if (fDay != null && fMonth != null && fYear != null) {
      fromDate = DateTime(fYear, fMonth, fDay);
    }
    final tDay = db.getInt('transfer_toDate_day');
    final tMonth = db.getInt('transfer_toDate_month');
    final tYear = db.getInt('transfer_toDate_year');
    if (tDay != null && tMonth != null && tYear != null) {
      toDate = DateTime(tYear, tMonth, tDay);
    }

    enableAgeFilter = db.getBool('transfer_enableAgeFilter') ?? false;
    ageFilterUnit = db.getString('transfer_ageFilterUnit') ?? 'Days';
    ageFilterValue = db.getInt('transfer_ageFilterValue') ?? 30;
    enableDateRange = db.getBool('transfer_enableDateRange') ?? false;
    todayOnly = db.getBool('transfer_todayOnly') ?? false;
    yesterdayOnly = db.getBool('transfer_yesterdayOnly') ?? false;
    _applyQuickDateFilter();
    excludeSubfolders = db.getBool('transfer_excludeSubfolders') ?? false;
    logInterval = db.getInt('transfer_logInterval') ?? 100;
    // Awaited: the resume marker and the moved/error counts must be in place
    // before the UI is notified, otherwise a run started immediately after
    // launch reads a null marker and loses its resume point.
    await _loadProgress();

    // Load time window settings
    enableTimeWindow = db.getBool('transfer_enableTimeWindow') ?? false;
    final fromHour = db.getInt('transfer_runFromHour');
    final fromMinute = db.getInt('transfer_runFromMinute');
    if (fromHour != null && fromMinute != null) {
      runFromTime = TimeOfDay(hour: fromHour, minute: fromMinute);
    }
    final toHour = db.getInt('transfer_runToHour');
    final toMinute = db.getInt('transfer_runToMinute');
    if (toHour != null && toMinute != null) {
      runToTime = TimeOfDay(hour: toHour, minute: toMinute);
    }

    // Load run days
    for (int day = 1; day <= 7; day++) {
      runDays[day] = db.getBool('transfer_runDay_$day') ?? false;
    }

    onCompletionAction = db.getString('transfer_onCompletionAction') ?? 'pause';

    notifyListeners();
  }

  Future<void> reloadSettings() async {
    await _loadSettings();
  }

  Future<void> _saveSettings() async {
    final db = LocalDbService();
    await db.setOrRemoveString('sourcePath', sourcePath);
    await db.setOrRemoveString('destPath', destPath);

    await db.setInt('transfer_fromDate_day', fromDate.day);
    await db.setInt('transfer_fromDate_month', fromDate.month);
    await db.setInt('transfer_fromDate_year', fromDate.year);

    await db.setInt('transfer_toDate_day', toDate.day);
    await db.setInt('transfer_toDate_month', toDate.month);
    await db.setInt('transfer_toDate_year', toDate.year);

    await db.setBool('transfer_enableAgeFilter', enableAgeFilter);
    await db.setString('transfer_ageFilterUnit', ageFilterUnit);
    await db.setInt('transfer_ageFilterValue', ageFilterValue);
    await db.setBool('transfer_enableDateRange', enableDateRange);
    await db.setBool('transfer_todayOnly', todayOnly);
    await db.setBool('transfer_yesterdayOnly', yesterdayOnly);
    await db.setBool('transfer_excludeSubfolders', excludeSubfolders);
    await db.setInt('transfer_logInterval', logInterval);

    await db.setBool('transfer_enableTimeWindow', enableTimeWindow);
    await db.setInt('transfer_runFromHour', runFromTime.hour);
    await db.setInt('transfer_runFromMinute', runFromTime.minute);
    await db.setInt('transfer_runToHour', runToTime.hour);
    await db.setInt('transfer_runToMinute', runToTime.minute);

    // Save run days
    for (int day = 1; day <= 7; day++) {
      await db.setBool('transfer_runDay_$day', runDays[day] ?? false);
    }

    await db.setString('transfer_onCompletionAction', onCompletionAction);
  }

  String get _progressFilePath {
    final s = sourcePath?.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_') ?? 'src';
    final d = destPath?.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_') ?? 'dst';
    final profileId = LocalDbService().currentProfileId;
    final appDir =
        GlobalDbService().appDirPath ??
        p.join(Directory.systemTemp.path, 'files_utility');
    return p.join(
      appDir,
      'progress',
      'transfer_progress_${s}_${d}_$profileId.json',
    );
  }

  Future<void> _loadProgress() async {
    lastScannedDir = null;
    filesMoved = 0;
    errors = 0;
    try {
      final file = File(_progressFilePath);
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        lastScannedDir = data['lastScannedDir'];
        filesMoved = data['filesMoved'] ?? 0;
        errors = data['errors'] ?? 0;
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _saveProgress(String? scannedDir, int fMoved, int errs) async {
    if (scannedDir != null) lastScannedDir = scannedDir;
    try {
      final file = File(_progressFilePath);
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      await file.writeAsString(
        jsonEncode({
          'lastScannedDir': lastScannedDir,
          'filesMoved': fMoved,
          'errors': errs,
        }),
      );
    } catch (_) {}
  }

  // Gene - Nov, 25, 2026: Allow _finishRun to clear only the saved resume checkpoint without wiping completed run counters.
  // Future<void> clearProgress() async {
  //   lastScannedDir = null;
  //   filesMoved = 0;
  //   errors = 0;
  //   // Gene - Nov, 25, 2026: Reset scanned counters when clearing progress.
  //   filesScanned = 0;
  //   dirsScanned = 0;
  //   try {
  //     final file = File(_progressFilePath);
  //     if (await file.exists()) await file.delete();
  //   } catch (_) {}
  //   _addLog('✓ Progress cleared.');
  //   notifyListeners();
  // }
  Future<void> clearProgress({bool resetCounters = true}) async {
    lastScannedDir = null;
    if (resetCounters) {
      filesMoved = 0;
      errors = 0;
      filesScanned = 0;
      dirsScanned = 0;
    }
    try {
      final file = File(_progressFilePath);
      if (await file.exists()) await file.delete();
    } catch (_) {}
    if (resetCounters) {
      _addLog('✓ Progress cleared.');
    }
    notifyListeners();
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
    _loadProgress();
    notifyListeners();
  }

  void setDestPath(String? path) {
    destPath = _sanitizePath(path);
    if (destPath != null) {
      LocalDbService().addRecentDirectory(destPath!);
    }
    _saveSettings();
    _loadProgress();
    notifyListeners();
  }

  void setFromDate(DateTime date) {
    fromDate = date;
    if (fromDate.isAfter(toDate)) toDate = fromDate;
    todayOnly = false;
    yesterdayOnly = false;
    _saveSettings();
    notifyListeners();
  }

  void setToDate(DateTime date) {
    toDate = date;
    if (toDate.isBefore(fromDate)) fromDate = toDate;
    todayOnly = false;
    yesterdayOnly = false;
    _saveSettings();
    notifyListeners();
  }

  void setEnableDateRange(bool val) {
    enableDateRange = val;
    if (!val) {
      todayOnly = false;
      yesterdayOnly = false;
    } else {
      enableAgeFilter = false;
    }
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
      fromDate = yesterday;
      toDate = today;
    } else if (todayOnly) {
      fromDate = today;
      toDate = today;
    } else {
      fromDate = yesterday;
      toDate = yesterday;
    }
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

  void setExcludeSubfolders(bool val) {
    excludeSubfolders = val;
    _saveSettings();
    notifyListeners();
  }

  void setLogInterval(int val) {
    logInterval = val;
    _saveSettings();
    notifyListeners();
  }

  Future<void> pickSource() async {
    final path = await getDirectoryPath(initialDirectory: sourcePath);
    if (path != null) setSourcePath(path);
  }

  Future<void> pickDest() async {
    final path = await getDirectoryPath(initialDirectory: destPath);
    if (path != null) setDestPath(path);
  }

  // --- Time window & completion setters ---

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

  void setOnCompletionAction(String action) {
    onCompletionAction = action;
    _saveSettings();
    notifyListeners();
  }

  // --- Schedule helpers ---

  bool _isCurrentlyInTimeWindow() {
    if (!enableTimeWindow) return true;

    // If the day is NOT checked, run the whole day (no time restriction).
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
      // from == to → treat as no restriction.
      return true;
    }
  }

  void _evaluateSchedule() {
    if (!isProcessing) return;

    bool inWindow = _isCurrentlyInTimeWindow();

    if (inWindow && isPaused) {
      // Resume
      isPaused = false;
      // Gene - Nov, 25, 2026: Resume native Rust transfer engine and show scanned file counter.
      // currentStatus = '⏳ Processing...';
      // _addLog('⏳ Time window reached. Resuming transfer...');
      // _workerControlPort?.send(_TransferControl(resume: true));
      currentStatus = '⏳ Scanning (${_numFmt.format(filesScanned)} files)...';
      _addLog('⏳ Time window reached. Resuming transfer...');
      _rustJob?.resume();
      notifyListeners();
      if (_pauseCompleter != null && !_pauseCompleter!.isCompleted) {
        _pauseCompleter!.complete();
      }
    } else if (!inWindow && !isPaused) {
      // Pause
      isPaused = true;
      _pauseCompleter = Completer<void>();
      currentStatus = '⏸ Waiting for time window...';
      _addLog('⏸ Outside allowed time window. Paused until next run window.');
      // Gene - Nov, 25, 2026: Pause native Rust transfer engine.
      // _workerControlPort?.send(_TransferControl(pause: true));
      _rustJob?.pause();
      notifyListeners();
    }
  }

  /// Schedules the next automatic run at the configured `runFromTime`.
  void _scheduleNextRun() {
    _completionRescheduleTimer?.cancel();

    final now = DateTime.now();
    DateTime nextRun = DateTime(
      now.year,
      now.month,
      now.day,
      runFromTime.hour,
      runFromTime.minute,
    );

    if (!nextRun.isAfter(now)) {
      nextRun = nextRun.add(const Duration(days: 1));
    }

    final waitDuration = nextRun.difference(now);
    final formattedNext = DateFormat('dd/MM/yyyy HH:mm').format(nextRun);

    isPaused = true;
    currentStatus = '🏁 Completed. Next run at $formattedNext';
    _addLog(
      '🏁 Transfer complete. Scheduled next run at $formattedNext (in ${waitDuration.inHours}h ${waitDuration.inMinutes % 60}m).',
    );
    notifyListeners();

    _completionRescheduleTimer = Timer(waitDuration, () {
      _completionRescheduleTimer = null;
      _addLog('⏳ Scheduled time reached. Starting new run...');
      isPaused = false;
      startProcessing();
    });
  }

  void stop() {
    if (!isProcessing) return;
    _stopRequested = true;
    _scheduleTimer?.cancel();
    _scheduleTimer = null;
    _completionRescheduleTimer?.cancel();
    _completionRescheduleTimer = null;
    // Gene - Nov, 25, 2026: Stop native Rust transfer job with fallback cleanup timer.
    // _isolateKillTimer?.cancel();
    _stopFallbackTimer?.cancel();

    _saveProgress(lastScannedDir, filesMoved, errors);

    if (_pauseCompleter != null && !_pauseCompleter!.isCompleted) {
      _pauseCompleter!.complete();
    }

    // If the worker is already gone (e.g. transfer completed and is
    // in the scheduled-pause / "next run" state), clean up immediately.
    // if (_workerIsolate == null) {
    //   _cleanupAfterStop();
    //   return;
    // }
    //
    // _workerControlPort?.send(_TransferControl(stop: true));
    //
    // // Cancellable fallback kill if isolate is completely stuck
    // _isolateKillTimer = Timer(const Duration(seconds: 2), () {
    //   if (_workerIsolate != null) {
    //     _workerIsolate?.kill(priority: Isolate.immediate);
    //     _workerIsolate = null;
    //     _cleanupAfterStop();
    //   }
    // });
    if (_rustJob == null) {
      _cleanupAfterStop();
      return;
    }

    _rustJob?.stop();

    _stopFallbackTimer = Timer(const Duration(seconds: 2), () {
      if (_rustJob != null) {
        _pollTimer?.cancel();
        _pollTimer = null;
        _rustJob?.dispose();
        _rustJob = null;
        _cleanupAfterStop();
      }
    });

    isPaused = false;
    currentStatus = '⛔ Stopping...';
    notifyListeners();
  }

  /// Formats elapsed time from the file logger's tracked start time.
  String _getElapsedStr() {
    final start = _fileLogger.getStartTime('Transfer');
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

  Future<void> startProcessing() async {
    // Re-entrancy protection
    if (isProcessing) return;

    // Gene - Nov, 25, 2026: Cancel Rust stop fallback timer instead of isolate kill timer.
    // _isolateKillTimer?.cancel();
    // _isolateKillTimer = null;
    _stopFallbackTimer?.cancel();
    _stopFallbackTimer = null;

    if (sourcePath == null || destPath == null) {
      _addLog('✗ Error: Source or Destination not selected.');
      await _fileLogger.error(
        'Transfer',
        'Source or Destination not selected.',
      );
      return;
    }

    // Validate: source and dest must not be the same
    if (p.equals(sourcePath!, destPath!)) {
      _addLog('✗ Error: Source and Destination cannot be the same folder.');
      _addLog(
        '  ℹ Tip: Choose a different destination, or use a subfolder as the destination.',
      );
      await _fileLogger.error(
        'Transfer',
        'Source and Destination are the same folder: $sourcePath',
      );
      return;
    }

    // Warn if destination is inside source
    final isDestInsideSource = p.isWithin(sourcePath!, destPath!);
    if (isDestInsideSource && !excludeSubfolders) {
      _addLog('⚠ Warning: Destination is inside the Source folder.');
      _addLog(
        '  ℹ Tip: Enable "Source folder only" in Advanced Settings to avoid',
      );
      _addLog(
        '    scanning into the destination subfolder, or choose a destination',
      );
      _addLog('    outside the source folder.');
    }

    _applyQuickDateFilter();

    if (lastScannedDir == null) {
      filesMoved = 0;
      errors = 0;
    }
    // Gene - Nov, 25, 2026: Reset scanned counters and initialize status with live file scan counter.
    filesScanned = 0;
    dirsScanned = 0;
    _sessionStartFilesMoved = filesMoved;
    _sessionStartErrors = errors;

    isProcessing = true;
    _stopRequested = false;
    isPaused = false;
    // currentStatus = '⏳ Starting transfer...';
    currentStatus = '⏳ Scanning (0 files)...';
    notifyListeners();

    _addLog('⏳ Starting transfer...');
    _addLog('  Source: $sourcePath');
    _addLog('  Destination: $destPath');
    _addLog(
      '  Scan mode: ${excludeSubfolders ? "Source folder only (no subfolders)" : "Include subfolders"}',
    );
    if (enableDateRange) {
      final dateFormat = DateFormat('dd/MM/yyyy');
      _addLog(
        '  Date range: ${dateFormat.format(fromDate)} — ${dateFormat.format(toDate)}',
      );
    } else if (enableAgeFilter) {
      _addLog('  Age filter: Older than $ageFilterValue $ageFilterUnit');
    } else {
      _addLog('  File filter: None (all files will be transferred)');
    }
    if (enableTimeWindow) {
      final String formattedFrom =
          '${runFromTime.hour.toString().padLeft(2, '0')}:${runFromTime.minute.toString().padLeft(2, '0')}';
      final String formattedTo =
          '${runToTime.hour.toString().padLeft(2, '0')}:${runToTime.minute.toString().padLeft(2, '0')}';
      _addLog('  Run window: $formattedFrom – $formattedTo');
    }

    await _fileLogger.logRunStart(
      operation: 'Transfer',
      sourcePath: sourcePath,
      destPath: destPath,
    );

    if (lastScannedDir != null) {
      _addLog('⏳ Resuming from directory: [$lastScannedDir]');
      await _fileLogger.info(
        'Transfer',
        'Resuming from directory: [$lastScannedDir]',
      );
    }

    // Setup periodic schedule evaluation
    _scheduleTimer?.cancel();
    _scheduleTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _evaluateSchedule();
    });

    // Check if we're inside the time window before starting.
    if (!_isCurrentlyInTimeWindow()) {
      isPaused = true;
      _pauseCompleter = Completer<void>();
      currentStatus = '⏸ Waiting for time window...';
      _addLog('⏸ Outside allowed time window. Waiting to start...');
      notifyListeners();
      // Wait until schedule timer resumes us
      await _pauseCompleter!.future;
      if (_stopRequested) {
        _cleanupAfterStop();
        return;
      }
    }

    _startTimer();

    try {
      final sourceDir = Directory(sourcePath!);
      if (!await sourceDir.exists()) {
        _addLog('✗ Error: Source directory does not exist.');
        await _fileLogger.error(
          'Transfer',
          'Source directory does not exist: $sourcePath',
        );
        _finishRun(wasStopped: false);
        return;
      }

      // Gene - Nov, 25, 2026: Run file transfer on the native Rust transfer_engine instead of a Dart isolate.
      // final receivePort = ReceivePort();
      //
      // _workerIsolate = await Isolate.spawn(
      //   _isolateWorker,
      //   _TransferParams(
      //     sourcePath: sourcePath!,
      //     destPath: destPath!,
      //     enableAgeFilter: enableAgeFilter,
      //     ageFilterUnit: ageFilterUnit,
      //     ageFilterValue: ageFilterValue,
      //     enableDateRange: enableDateRange,
      //     fromEpochMs: fromDate.millisecondsSinceEpoch,
      //     toEpochMs: toDate.millisecondsSinceEpoch,
      //     excludeSubfolders: excludeSubfolders,
      //     lastScannedDir: lastScannedDir,
      //     mainSendPort: receivePort.sendPort,
      //     initialFilesMoved: filesMoved,
      //     initialErrors: errors,
      //     logInterval: logInterval,
      //   ),
      // );
      //
      // receivePort.listen((message) { ... });
      final int fromInclusiveEpochMs = DateTime(
        fromDate.year,
        fromDate.month,
        fromDate.day,
      ).millisecondsSinceEpoch;
      final int toExclusiveEpochMs = DateTime(
        toDate.year,
        toDate.month,
        toDate.day + 1,
      ).millisecondsSinceEpoch;

      int ageThresholdEpochMs = 0;
      if (enableAgeFilter) {
        final now = DateTime.now();
        final DateTime ageThreshold;
        if (ageFilterUnit == 'Days') {
          ageThreshold = now.subtract(Duration(days: ageFilterValue));
        } else if (ageFilterUnit == 'Months') {
          ageThreshold = DateTime(
            now.year,
            now.month - ageFilterValue,
            now.day,
          );
        } else {
          ageThreshold = DateTime(
            now.year - ageFilterValue,
            now.month,
            now.day,
          );
        }
        ageThresholdEpochMs = ageThreshold.millisecondsSinceEpoch;
      }

      _rustJob?.dispose();
      _rustJob = RustTransferJob.start(
        sourcePath: sourcePath!,
        destPath: destPath!,
        lastScannedDir: lastScannedDir,
        enableAgeFilter: enableAgeFilter,
        ageThresholdEpochMs: ageThresholdEpochMs,
        enableDateRange: enableDateRange,
        fromInclusiveEpochMs: fromInclusiveEpochMs,
        toExclusiveEpochMs: toExclusiveEpochMs,
        excludeSubfolders: excludeSubfolders,
        initialFilesMoved: filesMoved,
        initialErrors: errors,
        logInterval: logInterval,
      );

      if (isPaused) {
        _rustJob?.pause();
      }

      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        _pollRustJob();
      });
    } catch (e, stack) {
      _addLog('✗ Critical Error: $e');
      _log.severe('Critical error during transfer', e, stack);
      await _fileLogger.error('Transfer', 'Critical Error: $e\n$stack');
      _finishRun(wasStopped: false);
    }
  }

  // Gene - Nov, 25, 2026: Poll native Rust transfer_engine for live scan/move progress, logs, and completion.
  void _pollRustJob() {
    final job = _rustJob;
    if (job == null || job.isDisposed) return;

    try {
      final snap = job.poll();
      filesScanned = snap.filesScanned;
      dirsScanned = snap.dirsScanned;
      filesMoved = snap.filesMoved;
      errors = snap.errors;

      if (!isPaused && !_stopRequested) {
        if (snap.phase == 1) {
          currentStatus = snap.currentDirName.isEmpty
              ? '⏳ Scanning (${_numFmt.format(filesScanned)} files)...'
              : '⏳ Scanning (${_numFmt.format(filesScanned)} files): ${snap.currentDirName}';
        } else if (snap.phase == 2) {
          currentStatus =
              '⏳ Moving (${_numFmt.format(filesMoved)} moved, ${_numFmt.format(filesScanned)} scanned): ${snap.currentDirName}';
        } else if (snap.phase == 3) {
          currentStatus = '⛔ Stopping...';
        }
      }

      if (snap.saveScannedDir != null) {
        _saveProgress(snap.saveScannedDir!, filesMoved, errors);
      }

      for (final rawLog in snap.logs) {
        if (rawLog.startsWith('__MOVED__|')) {
          final firstSep = rawLog.indexOf('|', 10);
          final secondSep = firstSep == -1
              ? -1
              : rawLog.indexOf('|', firstSep + 1);
          if (firstSep != -1 && secondSep != -1) {
            final movedStr = rawLog.substring(10, firstSep);
            final msStr = rawLog.substring(firstSep + 1, secondSep);
            final fileName = rawLog.substring(secondSep + 1);
            final epochMs = int.tryParse(msStr);
            if (enableDateRange && epochMs != null) {
              final dt = DateTime.fromMillisecondsSinceEpoch(epochMs);
              final yearStr = DateFormat('yyyy').format(dt);
              final monthStr = DateFormat('MMM').format(dt);
              _addLog(
                '✓ Moved $logInterval files (total: $movedStr) – latest [$monthStr-$yearStr]: $fileName',
              );
            } else {
              _addLog(
                '✓ Moved $logInterval files (total: $movedStr) – latest: $fileName',
              );
            }
          }
        } else {
          _addLog(rawLog);
          if (rawLog.startsWith('✗')) {
            _fileLogger.error('Transfer', rawLog);
          }
        }
      }

      if (snap.criticalError != null) {
        _addLog('✗ Critical Error: ${snap.criticalError}');
        _fileLogger.error('Transfer', 'Critical Error: ${snap.criticalError}');
      }

      if (snap.isDone) {
        _pollTimer?.cancel();
        _pollTimer = null;
        _stopFallbackTimer?.cancel();
        _stopFallbackTimer = null;
        job.dispose();
        _rustJob = null;

        if (!_stopRequested && filesMoved == _sessionStartFilesMoved) {
          _addLog('ℹ No files were transferred.');
          if (enableDateRange) {
            final fmt = DateFormat('dd/MM/yyyy');
            _addLog(
              '  ℹ Date filter is active: ${fmt.format(fromDate)} – ${fmt.format(toDate)}',
            );
            _addLog(
              '  ℹ Check that files have modification dates within this range.',
            );
          }
          if (enableAgeFilter) {
            _addLog(
              '  ℹ Age filter is active. Check that files are older than the configured threshold.',
            );
          }
          if (excludeSubfolders) {
            _addLog(
              '  ℹ "Source folder only" is enabled — only files directly in the source folder were checked.',
            );
            _addLog(
              '  ℹ If your files are in subfolders, uncheck this option in Advanced Settings.',
            );
          } else {
            _addLog(
              '  ℹ All subfolders were scanned. Verify the source path contains the expected files.',
            );
          }
        }

        if (!_stopRequested) {
          _finishRun(wasStopped: false);
        } else {
          _cleanupAfterStop();
        }
        return;
      }

      notifyListeners();
    } catch (e, stack) {
      _pollTimer?.cancel();
      _pollTimer = null;
      _stopFallbackTimer?.cancel();
      _stopFallbackTimer = null;
      _rustJob?.dispose();
      _rustJob = null;
      _addLog('✗ Critical Error: $e');
      _log.severe('Critical error polling Rust transfer engine', e, stack);
      _fileLogger.error('Transfer', 'Critical Error: $e\n$stack');
      _finishRun(wasStopped: false);
    }
  }

  Future<void> _finishRun({required bool wasStopped}) async {
    final elapsed = _getElapsedStr();
    final int sessionFilesMoved = filesMoved - _sessionStartFilesMoved;
    final int sessionErrors = errors - _sessionStartErrors;

    if (wasStopped) {
      _addLog('⛔ Stopped by user.');
    } else {
      _addLog(
        '🏁 Completed: ${_numFmt.format(sessionFilesMoved)} moved, ${_numFmt.format(sessionErrors)} errors in $elapsed',
      );
    }

    final runId = _fileLogger.getRunId('Transfer') ?? 'UNKNOWN';
    final start = _fileLogger.getStartTime('Transfer') ?? DateTime.now();

    await _fileLogger.logRunEnd(
      operation: 'Transfer',
      filesProcessed: sessionFilesMoved,
      errors: sessionErrors,
      wasStopped: wasStopped,
    );

    try {
      await HistoryService().saveRecord(
        RunRecord(
          id: runId,
          operation: 'Transfer',
          startTime: start,
          endTime: DateTime.now(),
          filesProcessed: sessionFilesMoved,
          foldersProcessed: 0,
          errors: sessionErrors,
          status: wasStopped
              ? 'Stopped'
              : (sessionErrors > 0 && sessionFilesMoved == 0
                    ? 'Error'
                    : 'Completed'),
          configSummary: 'Source: $sourcePath, Dest: $destPath',
          sourcePath: sourcePath,
          destPath: destPath,
        ),
      );
    } catch (_) {}

    _stopTimer();
    _scheduleTimer?.cancel();
    _scheduleTimer = null;

    if (!wasStopped && onCompletionAction == 'pause') {
      _scheduleNextRun();
    } else {
      isProcessing = false;
      isPaused = false;
      currentStatus = wasStopped
          ? '⛔ Stopped by user.'
          : '🏁 Transfer completed.';
      _completionRescheduleTimer?.cancel();
      _completionRescheduleTimer = null;
      if (!wasStopped) {
        // Gene - Nov, 25, 2026: Keep completed run counters visible after finishing while clearing checkpoint file.
        // await clearProgress();
        await clearProgress(resetCounters: false);
      }
    }
    notifyListeners();
  }

  /// Cleanup helper after stop is requested during pause-wait.
  void _cleanupAfterStop() {
    final runId = _fileLogger.getRunId('Transfer') ?? 'UNKNOWN';
    final start = _fileLogger.getStartTime('Transfer') ?? DateTime.now();
    final int sessionFilesMoved = filesMoved - _sessionStartFilesMoved;
    final int sessionErrors = errors - _sessionStartErrors;

    _fileLogger.logRunEnd(
      operation: 'Transfer',
      filesProcessed: sessionFilesMoved,
      errors: sessionErrors,
      wasStopped: true,
    );

    try {
      HistoryService().saveRecord(
        RunRecord(
          id: runId,
          operation: 'Transfer',
          startTime: start,
          endTime: DateTime.now(),
          filesProcessed: sessionFilesMoved,
          foldersProcessed: 0,
          errors: sessionErrors,
          status: 'Stopped',
          configSummary: 'Source: $sourcePath, Dest: $destPath',
          sourcePath: sourcePath,
          destPath: destPath,
        ),
      );
    } catch (_) {}

    isProcessing = false;
    isPaused = false;
    currentStatus = '⛔ Stopped by user.';
    _addLog('⛔ Stopped by user.');
    _stopTimer();
    notifyListeners();
  }

  // Gene - Nov, 25, 2026: Replaced Dart isolate worker with native Rust transfer_engine.
  // static Future<void> _isolateWorker(_TransferParams params) async {
  //   final workerReceivePort = ReceivePort();
  //   params.mainSendPort.send(
  //     _TransferProgress(workerSendPort: workerReceivePort.sendPort),
  //   );
  //
  //   bool isPaused = false;
  //   bool stopRequested = false;
  //   Completer<void>? pauseCompleter;
  //
  //   Future<bool> awaitIfPaused() async {
  //     if (isPaused && pauseCompleter != null && !pauseCompleter!.isCompleted) {
  //       await pauseCompleter!.future;
  //     }
  //     return !stopRequested;
  //   }
  //
  //   int filesMoved = params.initialFilesMoved;
  //   int errors = params.initialErrors;
  //   List<String> logBatch = [];
  //   int scanCount = 0;
  //   final Set<String> createdDirs = {};
  //
  //   int filesSinceLastSave = 0;
  //   const int saveProgressInterval = 20;
  //
  //   void flushProgress(
  //     String? status, {
  //     bool force = false,
  //     String? scannedDir,
  //   }) {
  //     if (force ||
  //         status != null ||
  //         logBatch.isNotEmpty ||
  //         scanCount % 10 == 0 ||
  //         scannedDir != null) {
  //       params.mainSendPort.send(
  //         _TransferProgress(
  //           filesMoved: filesMoved,
  //           errors: errors,
  //           logs: List.from(logBatch),
  //           currentStatus: status,
  //           saveScannedDir: scannedDir,
  //         ),
  //       );
  //       logBatch.clear();
  //     }
  //   }
  //
  //   workerReceivePort.listen((message) {
  //     if (message is _TransferControl) {
  //       if (message.stop) {
  //         stopRequested = true;
  //         flushProgress('⛔ Stopping...', force: true);
  //         if (pauseCompleter != null && !pauseCompleter!.isCompleted) {
  //           pauseCompleter!.complete();
  //         }
  //       } else if (message.pause) {
  //         isPaused = true;
  //         pauseCompleter = Completer<void>();
  //       } else if (message.resume) {
  //         isPaused = false;
  //         if (pauseCompleter != null && !pauseCompleter!.isCompleted) {
  //           pauseCompleter!.complete();
  //         }
  //       }
  //     }
  //   });
  //
  //   Future<void> moveFile(
  //     File file,
  //     String year,
  //     String month, {
  //     DateTime? modified,
  //   }) async {
  //     try {
  //       String relativePath = p.relative(
  //         file.parent.path,
  //         from: params.sourcePath,
  //       );
  //       String destDir = p.join(params.destPath, relativePath);
  //       String destFilePath = p.join(destDir, p.basename(file.path));
  //
  //       if (!createdDirs.contains(destDir)) {
  //         await Directory(destDir).create(recursive: true);
  //         createdDirs.add(destDir);
  //       }
  //
  //       if (await File(destFilePath).exists()) {
  //         logBatch.add(
  //           '⚠ Skipped ${p.basename(file.path)}: a file with that name already exists at the destination',
  //         );
  //         errors++;
  //         return;
  //       }
  //
  //       try {
  //         await file.rename(destFilePath);
  //       } on FileSystemException {
  //         final tempPath = '$destFilePath.part';
  //         try {
  //           await file.copy(tempPath);
  //           final srcLen = await file.length();
  //           final dstLen = await File(tempPath).length();
  //           if (srcLen != dstLen) {
  //             throw FileSystemException(
  //               'Incomplete copy ($dstLen of $srcLen bytes)',
  //               tempPath,
  //             );
  //           }
  //           if (modified != null) {
  //             try {
  //               await File(tempPath).setLastModified(modified);
  //             } catch (_) {}
  //           }
  //           await File(tempPath).rename(destFilePath);
  //           try {
  //             await file.delete();
  //           } catch (delErr) {
  //             logBatch.add(
  //               '⚠ Copied to destination, but could not delete source: ${file.path} ($delErr)',
  //             );
  //           }
  //         } catch (copyErr) {
  //           try {
  //             await File(tempPath).delete();
  //           } catch (_) {}
  //           rethrow;
  //         }
  //       }
  //
  //       filesMoved++;
  //       if (filesMoved % params.logInterval == 0) {
  //         if (year.isNotEmpty) {
  //           logBatch.add(
  //             '✓ Moved ${params.logInterval} files (total: $filesMoved) – latest [$month-$year]: ${p.basename(file.path)}',
  //           );
  //         } else {
  //           logBatch.add(
  //             '✓ Moved ${params.logInterval} files (total: $filesMoved) – latest: ${p.basename(file.path)}',
  //           );
  //         }
  //         flushProgress('⏳ Moving files ($filesMoved moved)...', force: true);
  //       }
  //     } catch (e) {
  //       logBatch.add('✗ Failed to move ${file.path}: $e');
  //       errors++;
  //     }
  //   }
  //
  //   late final DateTime from;
  //   late final DateTime to;
  //   if (params.enableDateRange) {
  //     final fd = DateTime.fromMillisecondsSinceEpoch(params.fromEpochMs);
  //     final td = DateTime.fromMillisecondsSinceEpoch(params.toEpochMs);
  //     from = DateTime(fd.year, fd.month, fd.day);
  //     to = DateTime(td.year, td.month, td.day);
  //   }
  //
  //   late final DateTime ageThreshold;
  //   if (params.enableAgeFilter) {
  //     final now = DateTime.now();
  //     if (params.ageFilterUnit == 'Days') {
  //       ageThreshold = now.subtract(Duration(days: params.ageFilterValue));
  //     } else if (params.ageFilterUnit == 'Months') {
  //       ageThreshold = DateTime(
  //         now.year,
  //         now.month - params.ageFilterValue,
  //         now.day,
  //       );
  //     } else {
  //       ageThreshold = DateTime(
  //         now.year - params.ageFilterValue,
  //         now.month,
  //         now.day,
  //       );
  //     }
  //   }
  //
  //   Future<void> checkAndMoveFile(File file) async {
  //     try {
  //       FileStat stats = await file.stat();
  //       DateTime modified = stats.modified;
  //
  //       if (params.enableAgeFilter) {
  //         if (modified.isAfter(ageThreshold)) return;
  //       }
  //
  //       if (params.enableDateRange) {
  //         final fileDate = DateTime(
  //           modified.year,
  //           modified.month,
  //           modified.day,
  //         );
  //         if (fileDate.isBefore(from) || fileDate.isAfter(to)) {
  //           return;
  //         }
  //
  //         String yearStr = DateFormat('yyyy').format(modified);
  //         String monthStr = DateFormat('MMM').format(modified);
  //         await moveFile(file, yearStr, monthStr, modified: modified);
  //       } else {
  //         await moveFile(file, '', '', modified: modified);
  //       }
  //     } catch (e) {
  //       logBatch.add('✗ Error accessing ${file.path}: $e');
  //       errors++;
  //     }
  //   }
  //
  //   Future<void> processDirectoryTree(
  //     Directory currentDir, {
  //     required bool recursive,
  //   }) async {
  //     bool skippingDirs = params.lastScannedDir != null;
  //     final Set<String> visitedDirs = {};
  //
  //     List<Directory> dirsToProcess = [currentDir];
  //
  //     while (dirsToProcess.isNotEmpty) {
  //       if (stopRequested) return;
  //       if (!(await awaitIfPaused())) return;
  //
  //       Directory dir = dirsToProcess.removeAt(0);
  //       String dirName = p.basename(dir.path);
  //
  //       if (p.equals(dir.path, params.destPath) ||
  //           p.isWithin(params.destPath, dir.path)) {
  //         logBatch.add('ℹ Skipping destination folder: $dirName');
  //         flushProgress(null);
  //         continue;
  //       }
  //
  //       String canonicalPath;
  //       try {
  //         canonicalPath = await dir.resolveSymbolicLinks();
  //       } catch (_) {
  //         canonicalPath = p.canonicalize(dir.path);
  //       }
  //
  //       if (visitedDirs.contains(canonicalPath)) {
  //         continue;
  //       }
  //       visitedDirs.add(canonicalPath);
  //
  //       if (skippingDirs && params.lastScannedDir != null) {
  //         if (p.equals(dir.path, params.lastScannedDir!)) {
  //           skippingDirs = false;
  //         }
  //       }
  //
  //       scanCount++;
  //       filesSinceLastSave++;
  //
  //       if (filesSinceLastSave >= saveProgressInterval) {
  //         filesSinceLastSave = 0;
  //         flushProgress('⏳ Scanning: $dirName', scannedDir: dir.path);
  //       } else {
  //         flushProgress('⏳ Scanning: $dirName');
  //       }
  //
  //       try {
  //         List<FileSystemEntity> entities = await dir
  //             .list(recursive: false, followLinks: false)
  //             .toList();
  //         entities.sort(
  //           (a, b) => p.basename(a.path).compareTo(p.basename(b.path)),
  //         );
  //
  //         for (var entity in entities) {
  //           if (stopRequested) return;
  //           if (!(await awaitIfPaused())) return;
  //
  //           if (entity is File) {
  //             await checkAndMoveFile(entity);
  //           } else if (entity is Directory && recursive) {
  //             dirsToProcess.add(entity);
  //           } else if (entity is Link) {
  //             try {
  //               if (!await resolvesWithinRoot(params.sourcePath, entity.path)) {
  //                 logBatch.add(
  //                   'ℹ Skipped link pointing outside the source: ${p.basename(entity.path)}',
  //                 );
  //                 continue;
  //               }
  //               final targetType = await FileSystemEntity.type(entity.path);
  //               if (targetType == FileSystemEntityType.directory && recursive) {
  //                 dirsToProcess.add(Directory(entity.path));
  //               } else if (targetType == FileSystemEntityType.file) {
  //                 await checkAndMoveFile(File(entity.path));
  //               }
  //             } catch (_) {}
  //           }
  //         }
  //       } catch (e) {
  //         logBatch.add('✗ Error reading directory ${dir.path}: $e');
  //       }
  //     }
  //   }
  //
  //   try {
  //     await processDirectoryTree(
  //       Directory(params.sourcePath),
  //       recursive: !params.excludeSubfolders,
  //     );
  //
  //     if (filesMoved == params.initialFilesMoved) {
  //       logBatch.add('ℹ No files were transferred.');
  //       if (params.enableDateRange) {
  //         final fd = DateTime.fromMillisecondsSinceEpoch(params.fromEpochMs);
  //         final td = DateTime.fromMillisecondsSinceEpoch(params.toEpochMs);
  //         logBatch.add(
  //           '  ℹ Date filter is active: ${DateFormat('dd/MM/yyyy').format(fd)} – ${DateFormat('dd/MM/yyyy').format(td)}',
  //         );
  //         logBatch.add(
  //           '  ℹ Check that files have modification dates within this range.',
  //         );
  //       }
  //       if (params.enableAgeFilter) {
  //         logBatch.add(
  //           '  ℹ Age filter is active. Check that files are older than the configured threshold.',
  //         );
  //       }
  //       if (params.excludeSubfolders) {
  //         logBatch.add(
  //           '  ℹ "Source folder only" is enabled — only files directly in the source folder were checked.',
  //         );
  //         logBatch.add(
  //           '  ℹ If your files are in subfolders, uncheck this option in Advanced Settings.',
  //         );
  //       } else {
  //         logBatch.add(
  //           '  ℹ All subfolders were scanned. Verify the source path contains the expected files.',
  //         );
  //       }
  //     }
  //
  //     flushProgress('DONE', force: true);
  //     params.mainSendPort.send(
  //       _TransferProgress(isDone: true, filesMoved: filesMoved, errors: errors),
  //     );
  //   } catch (e) {
  //     params.mainSendPort.send(
  //       _TransferProgress(
  //         criticalError: e.toString(),
  //         isDone: true,
  //         filesMoved: filesMoved,
  //         errors: errors,
  //       ),
  //     );
  //   }
  // }
}
