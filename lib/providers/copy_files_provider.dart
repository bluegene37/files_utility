import 'dart:async';
import 'dart:convert';
import 'dart:io';
// Gene - Nov, 25, 2026: Replaced Dart isolate copy worker with native Rust copy_engine.
// import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import '../services/file_logger.dart';
import '../services/history_service.dart';
import '../services/local_db_service.dart';
// import '../services/path_safety.dart';
import '../services/rust_file_engines.dart';
import '../models/run_record.dart';
import '../services/global_db_service.dart';

// Gene - Nov, 25, 2026: Commented out Dart isolate DTOs after migrating Copy to Rust copy_engine.
// class _IsolateProgress {
//   final String? logMessage;
//   final String? errorMessage;
//   final String? status;
//   final int filesCopied;
//   final int filesSkipped;
//   final int filesAlreadyExist;
//   final int errors;
//   final int filesInspected;
//   final bool done;
//   final String? criticalError;
//
//   _IsolateProgress({
//     this.logMessage,
//     this.errorMessage,
//     this.status,
//     this.filesCopied = 0,
//     this.filesSkipped = 0,
//     this.filesAlreadyExist = 0,
//     this.errors = 0,
//     this.filesInspected = 0,
//     this.done = false,
//     this.criticalError,
//   });
// }
//
// class _IsolateParams {
//   final String sourcePath;
//   final String destPath;
//   final bool enableDateRange;
//   final int fromEpochMs;
//   final int toEpochMs;
//   final bool enableAgeFilter;
//   final String ageFilterUnit;
//   final int ageFilterValue;
//   final SendPort sendPort;
//   final String? progressFilePath;
//   final Set<String> completedDirs;
//   final Map<String, String> lastProcessedFiles;
//   final int logInterval;
//   final int initialCopied;
//   final int initialSkipped;
//   final int initialAlreadyExist;
//   final int initialErrors;
//   final int initialInspected;
//
//   _IsolateParams({
//     required this.sourcePath,
//     required this.destPath,
//     required this.enableDateRange,
//     required this.fromEpochMs,
//     required this.toEpochMs,
//     required this.enableAgeFilter,
//     required this.ageFilterUnit,
//     required this.ageFilterValue,
//     required this.sendPort,
//     this.progressFilePath,
//     this.completedDirs = const {},
//     this.lastProcessedFiles = const {},
//     this.logInterval = 100,
//     this.initialCopied = 0,
//     this.initialSkipped = 0,
//     this.initialAlreadyExist = 0,
//     this.initialErrors = 0,
//     this.initialInspected = 0,
//   });
// }
//
// class _CountState {
//   int filesCopied = 0;
//   int filesSkipped = 0;
//   int filesAlreadyExist = 0;
//   int errors = 0;
//   int directoriesScanned = 0;
//   int filesInspected = 0;
//   int dirsSkipped = 0;
//   int lastStatusEmitMs = 0;
// }
//
// class _CopyTask {
//   final File source;
//   final String destFilePath;
//   final DateTime modified;
//
//   _CopyTask(this.source, this.destFilePath, this.modified);
// }

/// A source→destination directory pair for multi-directory mode.
class DirectoryPair {
  String? sourcePath;
  String? destPath;
  int runOrder;

  DirectoryPair({this.sourcePath, this.destPath, this.runOrder = 1});

  Map<String, dynamic> toJson() => {
    'source': sourcePath,
    'dest': destPath,
    'runOrder': runOrder,
  };

  factory DirectoryPair.fromJson(Map<String, dynamic> json) => DirectoryPair(
    sourcePath: json['source'] as String?,
    destPath: json['dest'] as String?,
    runOrder: (json['runOrder'] as int?) ?? 1,
  );
}

/// Tracks an active Rust worker processing one directory pair.
// Gene - Nov, 25, 2026: Replaced Dart Isolate/ReceivePort fields in _ActiveWorker with RustCopyJob and Timer.
// class _ActiveWorker {
//   final int pairIndex;
//   final Isolate isolate;
//   final ReceivePort receivePort;
//   final StreamSubscription subscription;
//   Capability? pauseCapability;
//   bool isPaused = false;
//
//   _ActiveWorker({
//     required this.pairIndex,
//     required this.isolate,
//     required this.receivePort,
//     required this.subscription,
//   });
// }
//
// class _Semaphore {
//   final int maxConcurrent;
//   int _current = 0;
//   final List<Completer<void>> _waiters = [];
//
//   _Semaphore(this.maxConcurrent);
//
//   Future<void> acquire() async {
//     if (_current < maxConcurrent) {
//       _current++;
//       return;
//     }
//     final completer = Completer<void>();
//     _waiters.add(completer);
//     await completer.future;
//     _current++;
//   }
//
//   void release() {
//     _current--;
//     if (_waiters.isNotEmpty) {
//       _waiters.removeAt(0).complete();
//     }
//   }
// }
class _ActiveWorker {
  final int pairIndex;
  final RustCopyJob job;
  Timer? pollTimer;
  bool isPaused = false;
  bool isPolling = false;

  _ActiveWorker({required this.pairIndex, required this.job});
}

class CopyFilesProvider with ChangeNotifier {
  final Logger _log = Logger('CopyFilesProvider');
  final FileLogger _fileLogger = FileLogger();
  final NumberFormat _numFmt = NumberFormat('#,##0');

  static String get _progressDir {
    final appDir =
        GlobalDbService().appDirPath ??
        p.join(Directory.systemTemp.path, 'files_utility');
    return p.join(appDir, 'progress');
  }

  /// Returns the progress file path for a given pair index.
  static String _progressFilePath(int pairIndex) {
    final profileId = LocalDbService().currentProfileId;
    return p.join(
      _progressDir,
      'copy_progress_pair${pairIndex}_$profileId.json',
    );
  }

  /// Loads progress data from a progress file.
  /// Returns null if the file doesn't exist or source/dest don't match.
  static Map<String, dynamic>? _loadProgressData(
    String filePath,
    String sourcePath,
    String destPath,
  ) {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return null;
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      if (data['sourcePath'] != sourcePath || data['destPath'] != destPath) {
        // Source/dest changed since last run — discard stale progress
        file.deleteSync();
        return null;
      }
      return data;
    } catch (_) {
      return null;
    }
  }

  // Gene - Nov, 25, 2026: Progress saving is now handled directly inside the native Rust copy_engine.
  // static void _saveProgressFile(
  //   String filePath,
  //   String sourcePath,
  //   String destPath,
  //   Set<String> completedDirs,
  //   Map<String, String> lastProcessedFiles,
  //   _CountState counts,
  // ) {
  //   try {
  //     final dir = Directory(_progressDir);
  //     if (!dir.existsSync()) dir.createSync(recursive: true);
  //     final data = {
  //       'sourcePath': sourcePath,
  //       'destPath': destPath,
  //       'completedDirs': completedDirs.toList(),
  //       'lastProcessedFiles': lastProcessedFiles,
  //       'filesCopied': counts.filesCopied,
  //       'filesSkipped': counts.filesSkipped,
  //       'filesAlreadyExist': counts.filesAlreadyExist,
  //       'errors': counts.errors,
  //       'filesInspected': counts.filesInspected,
  //     };
  //     File(filePath).writeAsStringSync(jsonEncode(data));
  //   } catch (_) {}
  // }

  /// Deletes the progress file (called when pair completes).
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
  // Gene - Nov, 25, 2026: Track live scanned file count across active Copy workers.
  int filesScanned = 0;

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
  final Map<int, List<int>> _pairStats =
      {}; // pairIndex → [copied, skipped, errors]

  //   CopyFilesProvider() {
  //     _loadSettings();
  //     LocalDbService().addListener(_onProfileChanged);
  //   }
  //
  //   void _onProfileChanged() {
  //     reloadSettings();
  //   }
  //
  //   @override
  //   void dispose() {
  //     LocalDbService().removeListener(_onProfileChanged);
  // Gene - Nov, 23, 2026: Support optional persistSettings flag for isolated unit and widget tests.
  final bool _persistSettings;

  CopyFilesProvider({bool persistSettings = true})
    : _persistSettings = persistSettings {
    if (_persistSettings) {
      _loadSettings();
      LocalDbService().addListener(_onProfileChanged);
    }
  }

  void _onProfileChanged() {
    reloadSettings();
  }

  @override
  void dispose() {
    if (_persistSettings) {
      LocalDbService().removeListener(_onProfileChanged);
    }
    _scheduleTimer?.cancel();
    _completionRescheduleTimer?.cancel();
    for (final worker in _activeWorkers) {
      // Gene - Nov, 25, 2026: Dispose native RustCopyJob and pollTimer instead of Dart isolate.
      // worker.isolate.kill(priority: Isolate.immediate);
      // worker.subscription.cancel();
      // worker.receivePort.close();
      worker.pollTimer?.cancel();
      worker.pollTimer = null;
      worker.job.stop();
      worker.job.dispose();
    }
    _activeWorkers.clear();
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
        directoryPairs = list
            .map((m) => DirectoryPair.fromJson(Map<String, dynamic>.from(m)))
            .toList();
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

  Future<void> reloadSettings() async {
    await _loadSettings();
  }

  //   Future<void> _saveSettings() async {
  //     final db = LocalDbService();
  // Gene - Nov, 23, 2026: Skip DB writes when _persistSettings is false.
  Future<void> _saveSettings() async {
    if (!_persistSettings) return;
    final db = LocalDbService();
    await db.setOrRemoveString('copy_sourcePath', sourcePath);
    await db.setOrRemoveString('copy_destPath', destPath);
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
    final pairsJson = jsonEncode(
      directoryPairs.map((p) => p.toJson()).toList(),
    );
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
    if (_persistSettings && sourcePath != null) {
      LocalDbService().addRecentDirectory(sourcePath!);
    }
    _saveSettings();
    notifyListeners();
  }

  void setDestPath(String? path) {
    destPath = _sanitizePath(path);
    if (_persistSettings && destPath != null) {
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
    final path = await getDirectoryPath(
      initialDirectory: directoryPairs[index].sourcePath,
    );
    if (path != null) setPairSource(index, path);
  }

  Future<void> pickPairDest(int index) async {
    final path = await getDirectoryPath(
      initialDirectory: directoryPairs[index].destPath,
    );
    if (path != null) setPairDest(index, path);
  }

  void setPairSource(int index, String? path) {
    if (index < 0 || index >= directoryPairs.length) return;
    final sanitized = _sanitizePath(path);
    directoryPairs[index].sourcePath = sanitized;
    if (_persistSettings && sanitized != null) {
      LocalDbService().addRecentDirectory(sanitized);
    }
    _saveSettings();
    notifyListeners();
  }

  void setPairDest(int index, String? path) {
    if (index < 0 || index >= directoryPairs.length) return;
    final sanitized = _sanitizePath(path);
    directoryPairs[index].destPath = sanitized;
    if (_persistSettings && sanitized != null) {
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

  // Gene - Nov, 23, 2026: JSON export and import for Copy Files settings and multi-directory pairs.
  Map<String, dynamic> exportSettingsJson({DateTime? now}) {
    final dateFmt = DateFormat('yyyy-MM-dd');
    return {
      'app': 'Files Utility',
      'type': 'copy_settings',
      'schemaVersion': 1,
      'exportedAt': (now ?? DateTime.now()).toIso8601String(),
      'directories': {
        'useMultipleDirectories': useMultipleDirectories,
        'sourcePath': sourcePath,
        'destPath': destPath,
        'directoryPairs': directoryPairs.map((pair) => pair.toJson()).toList(),
      },
      'filters': {
        'enableAgeFilter': enableAgeFilter,
        'ageFilterUnit': ageFilterUnit,
        'ageFilterValue': ageFilterValue,
        'enableDateRange': enableDateRange,
        'fromDate': dateFmt.format(fromDate),
        'toDate': dateFmt.format(toDate),
        'todayOnly': todayOnly,
        'yesterdayOnly': yesterdayOnly,
      },
      'options': {'logInterval': logInterval},
      'schedule': {
        'enableTimeWindow': enableTimeWindow,
        'runFromHour': runFromTime.hour,
        'runFromMinute': runFromTime.minute,
        'runToHour': runToTime.hour,
        'runToMinute': runToTime.minute,
        'runDays': {for (int d = 1; d <= 7; d++) '$d': runDays[d] ?? false},
        'onCompletionAction': onCompletionAction,
      },
    };
  }

  Map<String, dynamic> exportDirectoryPairsJson({DateTime? now}) {
    return {
      'app': 'Files Utility',
      'type': 'copy_pairs',
      'schemaVersion': 1,
      'exportedAt': (now ?? DateTime.now()).toIso8601String(),
      'directoryPairs': directoryPairs.map((pair) => pair.toJson()).toList(),
    };
  }

  String exportSettingsJsonString({DateTime? now}) =>
      const JsonEncoder.withIndent('  ').convert(exportSettingsJson(now: now));

  String exportDirectoryPairsJsonString({DateTime? now}) =>
      const JsonEncoder.withIndent(
        '  ',
      ).convert(exportDirectoryPairsJson(now: now));

  List<DirectoryPair> _parseDirectoryPairsList(dynamic rawList) {
    if (rawList is! List) return const [];
    final parsed = <DirectoryPair>[];
    for (final entry in rawList) {
      if (entry is! Map) continue;
      final pair = DirectoryPair.fromJson(Map<String, dynamic>.from(entry));
      parsed.add(
        DirectoryPair(
          sourcePath: _sanitizePath(pair.sourcePath),
          destPath: _sanitizePath(pair.destPath),
          runOrder: pair.runOrder.clamp(1, 10),
        ),
      );
    }
    return parsed;
  }

  DateTime? _parseIsoCalendarDate(dynamic raw) {
    if (raw is! String || raw.trim().isEmpty) return null;
    final parsed = DateTime.tryParse(raw.trim());
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  String importFromJsonString(String jsonStr, {bool pairsOnly = false}) {
    final dynamic decoded = jsonDecode(jsonStr);
    if (decoded is List) {
      final parsedPairs = _parseDirectoryPairsList(decoded);
      if (parsedPairs.isEmpty) {
        throw const FormatException('No directory pairs found in file.');
      }
      directoryPairs = parsedPairs;
      useMultipleDirectories = true;
      _saveSettings();
      final msg = 'Imported ${parsedPairs.length} directory pair(s).';
      _addLog('📥 $msg');
      notifyListeners();
      return msg;
    }

    if (decoded is! Map) {
      throw const FormatException('Invalid JSON structure.');
    }

    final map = Map<String, dynamic>.from(decoded);
    final rawType = map['type'] as String?;
    if (rawType == 'ftp_settings' || rawType == 'ftp_sources') {
      throw const FormatException(
        'This file is an FTP export, not Copy Files settings.',
      );
    }
    if (rawType != null &&
        rawType != 'copy_settings' &&
        rawType != 'copy_pairs') {
      throw FormatException('Unsupported export file type: $rawType');
    }

    final dirsMap = map['directories'] is Map
        ? Map<String, dynamic>.from(map['directories'] as Map)
        : null;
    final rawPairs = map['directoryPairs'] ?? dirsMap?['directoryPairs'];
    final parsedPairs = _parseDirectoryPairsList(rawPairs);

    if (pairsOnly || rawType == 'copy_pairs') {
      if (parsedPairs.isEmpty) {
        throw const FormatException('No directory pairs found in file.');
      }
      directoryPairs = parsedPairs;
      useMultipleDirectories = true;
      _saveSettings();
      final msg = 'Imported ${parsedPairs.length} directory pair(s).';
      _addLog('📥 $msg');
      notifyListeners();
      return msg;
    }

    if (rawType == null &&
        dirsMap == null &&
        map['filters'] == null &&
        map['options'] == null &&
        map['schedule'] == null &&
        rawPairs == null) {
      throw const FormatException('Unrecognized Copy Files JSON structure.');
    }

    if (dirsMap != null) {
      if (dirsMap.containsKey('useMultipleDirectories')) {
        useMultipleDirectories =
            dirsMap['useMultipleDirectories'] as bool? ??
            useMultipleDirectories;
      }
      if (dirsMap.containsKey('sourcePath')) {
        sourcePath = _sanitizePath(dirsMap['sourcePath'] as String?);
      }
      if (dirsMap.containsKey('destPath')) {
        destPath = _sanitizePath(dirsMap['destPath'] as String?);
      }
    }
    if (rawPairs != null) {
      directoryPairs = parsedPairs.isNotEmpty ? parsedPairs : [DirectoryPair()];
    }

    final filters = map['filters'] is Map
        ? Map<String, dynamic>.from(map['filters'] as Map)
        : null;
    if (filters != null) {
      if (filters.containsKey('enableAgeFilter')) {
        enableAgeFilter =
            filters['enableAgeFilter'] as bool? ?? enableAgeFilter;
      }
      final unit = filters['ageFilterUnit'];
      if (unit == 'Days' || unit == 'Months' || unit == 'Years') {
        ageFilterUnit = unit as String;
      }
      final ageVal = (filters['ageFilterValue'] as num?)?.toInt();
      if (ageVal != null) {
        ageFilterValue = ageVal.clamp(1, 31);
      }

      if (filters.containsKey('enableDateRange')) {
        enableDateRange =
            filters['enableDateRange'] as bool? ?? enableDateRange;
      }
      if (filters.containsKey('todayOnly')) {
        todayOnly = filters['todayOnly'] as bool? ?? todayOnly;
      }
      if (filters.containsKey('yesterdayOnly')) {
        yesterdayOnly = filters['yesterdayOnly'] as bool? ?? yesterdayOnly;
      }

      final fDate = _parseIsoCalendarDate(filters['fromDate']);
      if (fDate != null) fromDate = fDate;
      final tDate = _parseIsoCalendarDate(filters['toDate']);
      if (tDate != null) toDate = tDate;
      if (fromDate.isAfter(toDate)) {
        toDate = fromDate;
      }

      if (enableAgeFilter) {
        enableDateRange = false;
        todayOnly = false;
        yesterdayOnly = false;
      } else if (todayOnly || yesterdayOnly) {
        _applyQuickDateFilter();
      }
    }

    final options = map['options'] is Map
        ? Map<String, dynamic>.from(map['options'] as Map)
        : null;
    if (options != null && options.containsKey('logInterval')) {
      final liVal = (options['logInterval'] as num?)?.toInt();
      const allowedIntervals = [1, 5, 10, 25, 50, 100];
      if (liVal != null) {
        logInterval = allowedIntervals.contains(liVal) ? liVal : 100;
      }
    }

    final schedule = map['schedule'] is Map
        ? Map<String, dynamic>.from(map['schedule'] as Map)
        : null;
    if (schedule != null) {
      if (schedule.containsKey('enableTimeWindow')) {
        enableTimeWindow =
            schedule['enableTimeWindow'] as bool? ?? enableTimeWindow;
      }
      final fromHour = (schedule['runFromHour'] as num?)?.toInt();
      final fromMinute = (schedule['runFromMinute'] as num?)?.toInt();
      if (fromHour != null && fromMinute != null) {
        runFromTime = TimeOfDay(
          hour: fromHour.clamp(0, 23),
          minute: fromMinute.clamp(0, 59),
        );
      }
      final toHour = (schedule['runToHour'] as num?)?.toInt();
      final toMinute = (schedule['runToMinute'] as num?)?.toInt();
      if (toHour != null && toMinute != null) {
        runToTime = TimeOfDay(
          hour: toHour.clamp(0, 23),
          minute: toMinute.clamp(0, 59),
        );
      }
      if (schedule['runDays'] is Map) {
        final rawDays = Map<String, dynamic>.from(schedule['runDays'] as Map);
        for (int day = 1; day <= 7; day++) {
          final val = rawDays['$day'];
          if (val is bool) {
            runDays[day] = val;
          }
        }
      }
      final action = schedule['onCompletionAction'];
      if (action == 'pause' || action == 'stop') {
        onCompletionAction = action as String;
      }
    }

    _saveSettings();
    final msg = 'Imported Copy settings (${directoryPairs.length} pair(s)).';
    _addLog('📥 $msg');
    notifyListeners();
    _evaluateSchedule();
    return msg;
  }

  Future<String?> _writeJsonExportFile({
    required String suggestedName,
    required String jsonContent,
  }) async {
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'JSON', extensions: ['json']),
      ],
    );
    if (location == null) return null;

    var outPath = location.path;
    if (!outPath.toLowerCase().endsWith('.json')) {
      outPath = '$outPath.json';
    }
    await File(outPath).writeAsString(jsonContent);
    return outPath;
  }

  Future<String?> exportSettingsToDisk() async {
    try {
      final outPath = await _writeJsonExportFile(
        suggestedName: 'copy_settings.json',
        jsonContent: exportSettingsJsonString(),
      );
      if (outPath == null) return null;
      _addLog('📤 Exported Copy settings to $outPath');
      notifyListeners();
      return 'Exported Copy settings to ${p.basename(outPath)}';
    } catch (e) {
      return 'Failed to export settings: $e';
    }
  }

  Future<String?> exportDirectoryPairsToDisk() async {
    try {
      final outPath = await _writeJsonExportFile(
        suggestedName: 'copy_directory_pairs.json',
        jsonContent: exportDirectoryPairsJsonString(),
      );
      if (outPath == null) return null;
      _addLog(
        '📤 Exported ${directoryPairs.length} directory pair(s) to $outPath',
      );
      notifyListeners();
      return 'Exported ${directoryPairs.length} directory pair(s) to ${p.basename(outPath)}';
    } catch (e) {
      return 'Failed to export directory pairs: $e';
    }
  }

  Future<String?> importSettingsFromDisk() async {
    final picked = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'JSON', extensions: ['json']),
      ],
    );
    if (picked == null) return null;

    try {
      final content = await File(picked.path).readAsString();
      return importFromJsonString(content);
    } catch (e) {
      return 'Failed to import settings: $e';
    }
  }

  Future<String?> importDirectoryPairsFromDisk() async {
    final picked = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'JSON', extensions: ['json']),
      ],
    );
    if (picked == null) return null;

    try {
      final content = await File(picked.path).readAsString();
      return importFromJsonString(content, pairsOnly: true);
    } catch (e) {
      return 'Failed to import directory pairs: $e';
    }
  }

  void setOnCompletionAction(String action) {
    onCompletionAction = action;
    _saveSettings();
    notifyListeners();
  }

  /// Checks if there is any saved progress.
  bool get hasSavedProgress {
    for (int i = 0; i < 20; i++) {
      if (File(_progressFilePath(i)).existsSync()) return true;
    }
    return false;
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
    _addLog(
      '⛔ Stopped by user. Progress saved — next start will resume where it left off.',
    );
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
      HistoryService().saveRecord(
        RunRecord(
          id: runId,
          operation: 'Copy',
          startTime: start,
          endTime: DateTime.now(),
          filesProcessed: filesCopied,
          errors: errors,
          status: 'Stopped',
          configSummary:
              'Source: ${sourcePath ?? "Multiple"}, Dest: ${destPath ?? "Multiple"} (Pairs: ${_pairsToProcess.length}, Exist: $filesAlreadyExist, Skipped: $filesSkipped)',
          sourcePath: sourcePath,
          destPath: destPath,
        ),
      );
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
        // Gene - Nov, 25, 2026: Resume native RustCopyJob.
        // if (w.isPaused && w.pauseCapability != null) {
        //   w.isolate.resume(w.pauseCapability!);
        //   w.isPaused = false;
        // }
        if (w.isPaused) {
          w.job.resume();
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
        // Gene - Nov, 25, 2026: Pause native RustCopyJob.
        // if (!w.isPaused) {
        //   w.pauseCapability = w.isolate.pause();
        //   w.isPaused = true;
        // }
        if (!w.isPaused) {
          w.job.pause();
          w.isPaused = true;
        }
      }
      isPaused = true;
      currentStatus = '⏸ Waiting for time window...';
      _addLog('⏸ Outside allowed time window. Paused until next run window.');
      notifyListeners();
    }
  }

  /// Stops and disposes all active Rust workers without
  /// touching the outer processing state (isProcessing, scheduleTimer, etc.).
  void _killAllWorkers() {
    for (final w in _activeWorkers) {
      // Gene - Nov, 25, 2026: Stop and dispose native RustCopyJob cleanly.
      // w.isolate.kill(priority: Isolate.immediate);
      // w.subscription.cancel();
      // w.receivePort.close();
      w.pollTimer?.cancel();
      w.pollTimer = null;
      w.job.stop();
      w.job.dispose();
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
      now.year,
      now.month,
      now.day,
      runFromTime.hour,
      runFromTime.minute,
    );

    // If the next run time is in the past (or now), schedule for tomorrow
    if (!nextRun.isAfter(now)) {
      nextRun = nextRun.add(const Duration(days: 1));
    }

    final waitDuration = nextRun.difference(now);
    final formattedNext = DateFormat('dd/MM/yyyy HH:mm').format(nextRun);

    isPaused = true;
    currentStatus = '🏁 Completed. Next run at $formattedNext';
    _addLog(
      '🏁 Copy complete. Scheduled next run at $formattedNext (in ${waitDuration.inHours}h ${waitDuration.inMinutes % 60}m).',
    );
    notifyListeners();

    _completionRescheduleTimer = Timer(waitDuration, () {
      _completionRescheduleTimer = null;
      _addLog('⏳ Scheduled time reached. Starting new run...');
      isPaused = false;
      startProcessing();
    });
  }

  // Gene - Nov, 25, 2026: Commented out Dart isolate copy worker after migrating to native Rust copy_engine.
  // static final NumberFormat _isolateNumFmt = NumberFormat('#,##0');
  // static String _formatCount(int n) => _isolateNumFmt.format(n);
  //
  // static Future<void> _processBatch(
  //   List<_CopyTask> batch,
  //   _IsolateParams params,
  //   _CountState counts,
  // ) async {
  //   final semaphore = _Semaphore(6);
  //
  //   final futures = batch.map((task) async {
  //     await semaphore.acquire();
  //     try {
  //       final tempPath = '${task.destFilePath}.part';
  //       try {
  //         await task.source.copy(tempPath);
  //         try {
  //           await File(tempPath).setLastModified(task.modified);
  //         } catch (_) {}
  //         await File(tempPath).rename(task.destFilePath);
  //       } catch (copyErr) {
  //         try {
  //           await File(tempPath).delete();
  //         } catch (_) {}
  //         rethrow;
  //       }
  //       counts.filesCopied++;
  //
  //       if (counts.filesCopied % params.logInterval == 0) {
  //         params.sendPort.send(
  //           _IsolateProgress(
  //             logMessage:
  //                 '✓ Copied ${params.logInterval} files (total: ${counts.filesCopied}) – latest: ${p.basename(task.source.path)}',
  //             status:
  //                 'Copying: ${p.basename(task.source.path)} (${_formatCount(counts.filesCopied)} copied, ${_formatCount(counts.filesInspected)} scanned)',
  //             filesCopied: counts.filesCopied,
  //             filesSkipped: counts.filesSkipped,
  //             filesAlreadyExist: counts.filesAlreadyExist,
  //             errors: counts.errors,
  //             filesInspected: counts.filesInspected,
  //           ),
  //         );
  //       }
  //     } catch (e) {
  //       counts.errors++;
  //       params.sendPort.send(
  //         _IsolateProgress(
  //           errorMessage:
  //               '✗ Failed to copy ${p.basename(task.source.path)}: $e',
  //           errors: counts.errors,
  //           filesCopied: counts.filesCopied,
  //           filesSkipped: counts.filesSkipped,
  //           filesAlreadyExist: counts.filesAlreadyExist,
  //           filesInspected: counts.filesInspected,
  //         ),
  //       );
  //     } finally {
  //       semaphore.release();
  //     }
  //   });
  //
  //   await Future.wait(futures);
  // }
  //
  // static Future<void> _walkAndCopy(
  //   Directory dir,
  //   _IsolateParams params,
  //   _CountState counts,
  //   Set<String> createdDirs,
  //   List<_CopyTask> batch,
  //   Set<String> completedDirs,
  //   Map<String, String> lastProcessedFiles, [
  //   Set<String>? visitedCanonicalPaths,
  // ]) async {
  //   final visited = visitedCanonicalPaths ?? <String>{};
  //   String canonicalPath;
  //   try {
  //     canonicalPath = await dir.resolveSymbolicLinks();
  //   } catch (_) {
  //     canonicalPath = p.canonicalize(dir.path);
  //   }
  //   if (visited.contains(canonicalPath)) {
  //     return;
  //   }
  //   visited.add(canonicalPath);
  //
  //   final String relPath = p.relative(dir.path, from: params.sourcePath);
  //   if (completedDirs.contains(relPath)) {
  //     counts.dirsSkipped++;
  //     return;
  //   }
  //   List<FileSystemEntity> entities;
  //   try {
  //     entities = await dir.list(followLinks: false).toList();
  //   } catch (e) {
  //     counts.errors++;
  //     params.sendPort.send(
  //       _IsolateProgress(
  //         errorMessage: '✗ Cannot access: ${dir.path} ($e)',
  //         errors: counts.errors,
  //         filesCopied: counts.filesCopied,
  //         filesSkipped: counts.filesSkipped,
  //         filesAlreadyExist: counts.filesAlreadyExist,
  //         filesInspected: counts.filesInspected,
  //       ),
  //     );
  //     return;
  //   }
  //
  //   counts.directoriesScanned++;
  //
  //   final nowMs = DateTime.now().millisecondsSinceEpoch;
  //   if (counts.directoriesScanned == 1 ||
  //       nowMs - counts.lastStatusEmitMs >= 150) {
  //     counts.lastStatusEmitMs = nowMs;
  //     params.sendPort.send(
  //       _IsolateProgress(
  //         status:
  //             '⏳ Scanning (${_formatCount(counts.filesInspected)} files): ${p.basename(dir.path)}',
  //         filesCopied: counts.filesCopied,
  //         filesSkipped: counts.filesSkipped,
  //         filesAlreadyExist: counts.filesAlreadyExist,
  //         errors: counts.errors,
  //         filesInspected: counts.filesInspected,
  //       ),
  //     );
  //   }
  //
  //   final files = entities.whereType<File>().toList();
  //   files.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
  //
  //   int startIndex = 0;
  //   if (lastProcessedFiles.containsKey(relPath)) {
  //     final lastName = lastProcessedFiles[relPath]!;
  //     int idx = files.indexWhere((f) => p.basename(f.path) == lastName);
  //     if (idx != -1) {
  //       startIndex = idx + 1;
  //     }
  //   }
  //
  //   if (files.isEmpty || startIndex >= files.length) {
  //     for (final entity in entities) {
  //       if (entity is Directory) {
  //         await _walkAndCopy(
  //           entity,
  //           params,
  //           counts,
  //           createdDirs,
  //           batch,
  //           completedDirs,
  //           lastProcessedFiles,
  //           visited,
  //         );
  //       } else if (entity is Link) {
  //         try {
  //           if (!await resolvesWithinRoot(params.sourcePath, entity.path)) {
  //             continue;
  //           }
  //           final targetType = await FileSystemEntity.type(entity.path);
  //           if (targetType == FileSystemEntityType.directory) {
  //             await _walkAndCopy(
  //               Directory(entity.path),
  //               params,
  //               counts,
  //               createdDirs,
  //               batch,
  //               completedDirs,
  //               lastProcessedFiles,
  //               visited,
  //             );
  //           }
  //         } catch (_) {}
  //       }
  //     }
  //     return;
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
  //   final String destDirPath = p.join(params.destPath, relPath);
  //
  //   for (var i = startIndex; i < files.length; i += 8) {
  //     final chunk = files.skip(i).take(8);
  //
  //     final futures = chunk.map((fsEntity) async {
  //       final entity = File(fsEntity.path);
  //       try {
  //         counts.filesInspected++;
  //
  //         final FileStat stats = await entity.stat();
  //         final int sourceSize = stats.size;
  //
  //         if (params.enableAgeFilter) {
  //           if (stats.modified.isAfter(ageThreshold)) {
  //             counts.filesSkipped++;
  //             return;
  //           }
  //         }
  //
  //         if (params.enableDateRange) {
  //           final m = stats.modified;
  //           final fileDate = DateTime(m.year, m.month, m.day);
  //           if (fileDate.isBefore(from) || fileDate.isAfter(to)) {
  //             counts.filesSkipped++;
  //             return;
  //           }
  //         }
  //
  //         final String fileName = p.basename(entity.path);
  //
  //         final destFile = File(p.join(destDirPath, fileName));
  //         try {
  //           final destStats = await destFile.stat();
  //           if (destStats.type == FileSystemEntityType.file &&
  //               destStats.size == sourceSize) {
  //             counts.filesAlreadyExist++;
  //
  //             if (counts.filesAlreadyExist % params.logInterval == 0) {
  //               params.sendPort.send(
  //                 _IsolateProgress(
  //                   logMessage:
  //                       '⏭ ${counts.filesAlreadyExist} files already exist at destination (skipping)',
  //                   status:
  //                       '⏭ Checking: ${p.basename(dir.path)} – ${counts.filesAlreadyExist} already exist, ${counts.filesCopied} copied',
  //                   filesCopied: counts.filesCopied,
  //                   filesSkipped: counts.filesSkipped,
  //                   filesAlreadyExist: counts.filesAlreadyExist,
  //                   errors: counts.errors,
  //                   filesInspected: counts.filesInspected,
  //                 ),
  //               );
  //             }
  //             return;
  //           }
  //         } catch (_) {}
  //
  //         if (!createdDirs.contains(destDirPath)) {
  //           createdDirs.add(destDirPath);
  //           await Directory(destDirPath).create(recursive: true);
  //         }
  //         batch.add(
  //           _CopyTask(entity, p.join(destDirPath, fileName), stats.modified),
  //         );
  //       } catch (e) {
  //         counts.errors++;
  //         params.sendPort.send(
  //           _IsolateProgress(
  //             errorMessage:
  //                 '✗ Failed to inspect ${p.basename(entity.path)}: $e',
  //             errors: counts.errors,
  //             filesCopied: counts.filesCopied,
  //             filesSkipped: counts.filesSkipped,
  //             filesAlreadyExist: counts.filesAlreadyExist,
  //             filesInspected: counts.filesInspected,
  //           ),
  //         );
  //       }
  //     });
  //
  //     await Future.wait(futures);
  //
  //     final chunkNowMs = DateTime.now().millisecondsSinceEpoch;
  //     if (chunkNowMs - counts.lastStatusEmitMs >= 150) {
  //       counts.lastStatusEmitMs = chunkNowMs;
  //       params.sendPort.send(
  //         _IsolateProgress(
  //           status:
  //               '⏳ Scanning (${_formatCount(counts.filesInspected)} files): ${p.basename(dir.path)}',
  //           filesCopied: counts.filesCopied,
  //           filesSkipped: counts.filesSkipped,
  //           filesAlreadyExist: counts.filesAlreadyExist,
  //           errors: counts.errors,
  //           filesInspected: counts.filesInspected,
  //         ),
  //       );
  //     }
  //
  //     if (batch.length >= 50) {
  //       final tasksToRun = List<_CopyTask>.from(batch);
  //       batch.clear();
  //       await _processBatch(tasksToRun, params, counts);
  //       await Future.delayed(Duration.zero);
  //     }
  //
  //     if (batch.isEmpty) {
  //       lastProcessedFiles[relPath] = p.basename(chunk.last.path);
  //     }
  //   }
  //
  //   if (batch.isEmpty && files.isNotEmpty) {
  //     lastProcessedFiles[relPath] = p.basename(files.last.path);
  //   }
  //
  //   for (final entity in entities) {
  //     if (entity is Directory) {
  //       await _walkAndCopy(
  //         entity,
  //         params,
  //         counts,
  //         createdDirs,
  //         batch,
  //         completedDirs,
  //         lastProcessedFiles,
  //         visited,
  //       );
  //     } else if (entity is Link) {
  //       try {
  //         if (!await resolvesWithinRoot(params.sourcePath, entity.path)) {
  //           continue;
  //         }
  //         final targetType = await FileSystemEntity.type(entity.path);
  //         if (targetType == FileSystemEntityType.directory) {
  //           await _walkAndCopy(
  //             Directory(entity.path),
  //             params,
  //             counts,
  //             createdDirs,
  //             batch,
  //             completedDirs,
  //             lastProcessedFiles,
  //             visited,
  //           );
  //         }
  //       } catch (_) {}
  //     }
  //   }
  //
  //   completedDirs.add(relPath);
  //   lastProcessedFiles.remove(relPath);
  //
  //   if (params.progressFilePath != null && completedDirs.length % 100 == 0) {
  //     _saveProgressFile(
  //       params.progressFilePath!,
  //       params.sourcePath,
  //       params.destPath,
  //       completedDirs,
  //       lastProcessedFiles,
  //       counts,
  //     );
  //   }
  // }
  //
  // static Future<void> _copyWorker(_IsolateParams params) async {
  //   final counts = _CountState()
  //     ..filesCopied = params.initialCopied
  //     ..filesSkipped = params.initialSkipped
  //     ..filesAlreadyExist = params.initialAlreadyExist
  //     ..errors = params.initialErrors
  //     ..filesInspected = params.initialInspected;
  //   final createdDirs = <String>{};
  //   final batch = <_CopyTask>[];
  //   final completedDirs = Set<String>.from(params.completedDirs);
  //   final lastProcessedFiles = Map<String, String>.from(
  //     params.lastProcessedFiles,
  //   );
  //   final isResuming =
  //       completedDirs.isNotEmpty || lastProcessedFiles.isNotEmpty;
  //
  //   Timer? saveTimer;
  //   if (params.progressFilePath != null) {
  //     saveTimer = Timer.periodic(const Duration(seconds: 1), (_) {
  //       _saveProgressFile(
  //         params.progressFilePath!,
  //         params.sourcePath,
  //         params.destPath,
  //         completedDirs,
  //         lastProcessedFiles,
  //         counts,
  //       );
  //     });
  //   }
  //
  //   try {
  //     if (isResuming) {
  //       params.sendPort.send(
  //         _IsolateProgress(
  //           status:
  //               '▶ Resuming copy (${completedDirs.length} folders already completed)...',
  //           filesCopied: counts.filesCopied,
  //           filesSkipped: counts.filesSkipped,
  //           filesAlreadyExist: counts.filesAlreadyExist,
  //           errors: counts.errors,
  //           filesInspected: counts.filesInspected,
  //         ),
  //       );
  //     }
  //
  //     await _walkAndCopy(
  //       Directory(params.sourcePath),
  //       params,
  //       counts,
  //       createdDirs,
  //       batch,
  //       completedDirs,
  //       lastProcessedFiles,
  //       {},
  //     );
  //
  //     if (batch.isNotEmpty) {
  //       await _processBatch(batch, params, counts);
  //       batch.clear();
  //     }
  //
  //     if (params.progressFilePath != null) {
  //       _saveProgressFile(
  //         params.progressFilePath!,
  //         params.sourcePath,
  //         params.destPath,
  //         completedDirs,
  //         lastProcessedFiles,
  //         counts,
  //       );
  //     }
  //
  //     final resumeNote = isResuming
  //         ? ' (${counts.dirsSkipped} dirs skipped via resume)'
  //         : '';
  //     params.sendPort.send(
  //       _IsolateProgress(
  //         logMessage: '🏁 Copy completed successfully.$resumeNote',
  //         status: 'Done',
  //         done: true,
  //         filesCopied: counts.filesCopied,
  //         filesSkipped: counts.filesSkipped,
  //         filesAlreadyExist: counts.filesAlreadyExist,
  //         errors: counts.errors,
  //         filesInspected: counts.filesInspected,
  //       ),
  //     );
  //
  //     if (params.progressFilePath != null) {
  //       _deleteProgressFile(params.progressFilePath!);
  //     }
  //   } catch (e) {
  //     if (params.progressFilePath != null) {
  //       _saveProgressFile(
  //         params.progressFilePath!,
  //         params.sourcePath,
  //         params.destPath,
  //         completedDirs,
  //         lastProcessedFiles,
  //         counts,
  //       );
  //     }
  //     params.sendPort.send(
  //       _IsolateProgress(
  //         logMessage: '✗ Critical Error: $e',
  //         criticalError: e.toString(),
  //         done: true,
  //         filesCopied: counts.filesCopied,
  //         filesSkipped: counts.filesSkipped,
  //         filesAlreadyExist: counts.filesAlreadyExist,
  //         errors: counts.errors,
  //         filesInspected: counts.filesInspected,
  //       ),
  //     );
  //   } finally {
  //     saveTimer?.cancel();
  //   }
  // }

  Future<void> startProcessing() async {
    // Re-entrancy protection
    if (isProcessing) return;

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
    final orderSet =
        _pairsToProcess.map((p) => p['runOrder'] as int).toSet().toList()
          ..sort();
    _runOrderGroups = orderSet;
    _currentGroupIndex = 0;
    _pairsCompletedInGroup = 0;
    _totalPairsCompleted = 0;
    _pairStats.clear();

    isProcessing = true;
    // Gene - Nov, 25, 2026: Initialize Copy status with live scanning file counter.
    // currentStatus = '⏳ Scanning...';
    currentStatus = '⏳ Scanning (0 files)...';
    filesCopied = 0;
    filesSkipped = 0;
    filesAlreadyExist = 0;
    errors = 0;
    filesScanned = 0;
    isPaused = false;
    notifyListeners();

    final dateFormat = DateFormat('dd/MM/yyyy');
    _addLog(
      '⏳ Starting copy process... (${_pairsToProcess.length} pair(s), ${_runOrderGroups.length} group(s))',
    );
    if (enableDateRange) {
      _addLog(
        '  Date range: ${dateFormat.format(fromDate)} — ${dateFormat.format(toDate)}',
      );
    }
    if (enableTimeWindow) {
      final String formattedFrom =
          '${runFromTime.hour.toString().padLeft(2, '0')}:${runFromTime.minute.toString().padLeft(2, '0')}';
      final String formattedTo =
          '${runToTime.hour.toString().padLeft(2, '0')}:${runToTime.minute.toString().padLeft(2, '0')}';
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
    int totalCopied = 0,
        totalSkipped = 0,
        totalAlreadyExist = 0,
        totalErrors = 0,
        totalScanned = 0;
    for (final stats in _pairStats.values) {
      totalCopied += stats[0];
      totalSkipped += stats[1];
      totalErrors += stats[2];
      totalAlreadyExist += stats.length > 3 ? stats[3] : 0;
      // Gene - Nov, 25, 2026: Aggregate scanned/inspected file count across active pairs.
      totalScanned += stats.length > 4 ? stats[4] : 0;
    }
    filesCopied = totalCopied;
    filesSkipped = totalSkipped;
    filesAlreadyExist = totalAlreadyExist;
    errors = totalErrors;
    filesScanned = totalScanned;
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
    _addLog(
      '═══ Starting Run Order $currentOrder (${groupPairs.length} pair(s)) ═══',
    );
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
    // Gene - Nov, 25, 2026: Show live file counter in initial worker status.
    // if (_activeWorkers.isEmpty) {
    //   currentStatus = '⏳ Pair ${origIdx + 1}: Scanning...';
    // } else {
    //   currentStatus =
    //       '⏳ Running ${_activeWorkers.length + 1} pair(s) (Order $runOrder)...';
    // }
    if (_activeWorkers.isEmpty) {
      currentStatus = useMultipleDirectories
          ? '⏳ Pair ${origIdx + 1}: Scanning (0 files)...'
          : '⏳ Scanning (0 files)...';
    } else {
      currentStatus =
          '⏳ Running ${_activeWorkers.length + 1} pair(s) (Order $runOrder)...';
    }
    // Gene - Nov, 25, 2026: Replaced Dart Isolate.spawn with native RustCopyJob and 100ms polling.
    // final receivePort = ReceivePort();

    // Load resume progress for this pair (if any)
    final progressPath = _progressFilePath(origIdx);
    final progressData = _loadProgressData(progressPath, source, dest);
    Set<String> resumeDirs = {};
    Map<String, String> lastProcessedFiles = {};
    int initialCopied = 0;
    int initialSkipped = 0;
    int initialAlreadyExist = 0;
    int initialErrors = 0;
    int initialInspected = 0;

    if (progressData != null) {
      resumeDirs = (progressData['completedDirs'] as List)
          .cast<String>()
          .toSet();
      if (progressData['lastProcessedFiles'] != null) {
        lastProcessedFiles = Map<String, String>.from(
          progressData['lastProcessedFiles'] as Map,
        );
      }
      initialCopied = progressData['filesCopied'] as int? ?? 0;
      initialSkipped = progressData['filesSkipped'] as int? ?? 0;
      initialAlreadyExist = progressData['filesAlreadyExist'] as int? ?? 0;
      initialErrors = progressData['errors'] as int? ?? 0;
      initialInspected = progressData['filesInspected'] as int? ?? 0;

      if (resumeDirs.isNotEmpty || initialInspected > 0) {
        _addLog(
          '[P${origIdx + 1}] ⏩ Resuming: ${resumeDirs.length} dirs completed. Stats restored.',
        );
      }
    }

    _pairStats[pairIndex] = [
      initialCopied,
      initialSkipped,
      initialErrors,
      initialAlreadyExist,
      // Gene - Nov, 25, 2026: Track initial inspected file count per pair.
      initialInspected,
    ];
    _recalcStats();
    notifyListeners();

    // final params = _IsolateParams( ... );
    // final isolate = await Isolate.spawn(_copyWorker, params);
    // late final _ActiveWorker worker;
    // final subscription = receivePort.listen((message) async { ... });
    // worker = _ActiveWorker(...);
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
        ageThreshold = DateTime(now.year, now.month - ageFilterValue, now.day);
      } else {
        ageThreshold = DateTime(now.year - ageFilterValue, now.month, now.day);
      }
      ageThresholdEpochMs = ageThreshold.millisecondsSinceEpoch;
    }

    final job = RustCopyJob.start(
      sourcePath: source,
      destPath: dest,
      progressFilePath: progressPath,
      completedDirs: resumeDirs,
      lastProcessedFiles: lastProcessedFiles,
      enableAgeFilter: enableAgeFilter,
      ageThresholdEpochMs: ageThresholdEpochMs,
      enableDateRange: enableDateRange,
      fromInclusiveEpochMs: fromInclusiveEpochMs,
      toExclusiveEpochMs: toExclusiveEpochMs,
      initialCopied: initialCopied,
      initialSkipped: initialSkipped,
      initialAlreadyExist: initialAlreadyExist,
      initialErrors: initialErrors,
      initialInspected: initialInspected,
      logInterval: logInterval,
    );

    final worker = _ActiveWorker(pairIndex: pairIndex, job: job);
    _activeWorkers.add(worker);

    // Gene - Nov, 25, 2026: Poll every 150ms to minimize UI churn while keeping the scanning counter responsive.
    // worker.pollTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
    worker.pollTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      _pollCopyWorker(worker, pairIndex, origIdx, runOrder);
    });

    // If the provider is already in paused state (e.g., a previous worker in
    // this group triggered the pause), immediately pause this new worker too.
    if (isPaused) {
      worker.job.pause();
      worker.isPaused = true;
    } else {
      _evaluateSchedule();
    }
  }

  // Gene - Nov, 25, 2026: Poll native Rust copy_engine for live stats, scanning counter, logs, and completion.
  Future<void> _pollCopyWorker(
    _ActiveWorker worker,
    int pairIndex,
    int origIdx,
    int runOrder,
  ) async {
    if (worker.isPolling || worker.job.isDisposed) return;
    worker.isPolling = true;
    try {
      final snap = worker.job.poll();

      _pairStats[pairIndex] = [
        snap.filesCopied,
        snap.filesSkipped,
        snap.errors,
        snap.filesAlreadyExist,
        snap.filesInspected,
      ];
      _recalcStats();

      if (!isPaused) {
        String rawStatus;
        if (snap.phase == 2 && snap.latestCopiedName.isNotEmpty) {
          rawStatus =
              'Copying: ${snap.latestCopiedName} (${_numFmt.format(snap.filesCopied)} copied, ${_numFmt.format(snap.filesInspected)} scanned)';
        } else if (snap.phase == 3) {
          rawStatus =
              '⏭ Checking: ${snap.currentDirName} – ${_numFmt.format(snap.filesAlreadyExist)} already exist, ${_numFmt.format(snap.filesCopied)} copied';
        } else {
          rawStatus = snap.currentDirName.isEmpty
              ? '⏳ Scanning (${_numFmt.format(snap.filesInspected)} files)...'
              : '⏳ Scanning (${_numFmt.format(snap.filesInspected)} files): ${snap.currentDirName}';
        }

        if (!useMultipleDirectories) {
          currentStatus = rawStatus;
        } else if (_activeWorkers.length == 1) {
          currentStatus = 'P${origIdx + 1}: $rawStatus';
        } else {
          currentStatus =
              '${_activeWorkers.length} pairs (Order $runOrder) – P${origIdx + 1}: $rawStatus';
        }
      }

      for (final log in snap.logs) {
        _addLog('[P${origIdx + 1}] $log');
      }

      for (final err in snap.errorLogs) {
        _addLog('[P${origIdx + 1}] $err');
        await _fileLogger.error('Copy', err);
      }

      if (snap.criticalError != null) {
        _log.severe(
          'Rust copy critical error (pair ${origIdx + 1}): ${snap.criticalError}',
        );
        await _fileLogger.error(
          'Copy',
          'Critical Error (pair ${origIdx + 1}): ${snap.criticalError}',
        );
      }

      if (snap.isDone) {
        _addLog(
          '[P${origIdx + 1}] 🏁 Done: ${_numFmt.format(snap.filesCopied)} copied, ${_numFmt.format(snap.filesAlreadyExist)} exist, ${_numFmt.format(snap.filesSkipped)} skipped, ${_numFmt.format(snap.errors)} errors',
        );

        worker.pollTimer?.cancel();
        worker.pollTimer = null;
        worker.job.dispose();
        _activeWorkers.remove(worker);
        _totalPairsCompleted++;
        _pairsCompletedInGroup++;

        _recalcStats();

        final currentOrder = _runOrderGroups[_currentGroupIndex];
        final groupSize = _pairsToProcess
            .where((p) => p['runOrder'] == currentOrder)
            .length;
        if (_pairsCompletedInGroup >= groupSize) {
          _addLog('═══ Run Order $currentOrder complete ═══');
          _currentGroupIndex++;
          if (_currentGroupIndex < _runOrderGroups.length) {
            await _startCurrentGroup();
          }
        }

        if (_totalPairsCompleted >= _pairsToProcess.length) {
          final elapsed = _getElapsedStr();
          _addLog(
            '🏁 All ${_pairsToProcess.length} pair(s) completed. Total: ${_numFmt.format(filesCopied)} copied, ${_numFmt.format(errors)} errors in $elapsed',
          );

          final runId = _fileLogger.getRunId('Copy') ?? 'UNKNOWN';
          final start = _fileLogger.getStartTime('Copy') ?? DateTime.now();

          await _fileLogger.logRunEnd(
            operation: 'Copy',
            filesProcessed: filesCopied,
            errors: errors,
            wasStopped: false,
          );

          try {
            await HistoryService().saveRecord(
              RunRecord(
                id: runId,
                operation: 'Copy',
                startTime: start,
                endTime: DateTime.now(),
                filesProcessed: filesCopied,
                errors: errors,
                status: errors > 0 && filesCopied == 0 ? 'Error' : 'Completed',
                configSummary:
                    'Source: ${sourcePath ?? "Multiple"}, Dest: ${destPath ?? "Multiple"} (Pairs: ${_pairsToProcess.length}, Exist: $filesAlreadyExist, Skipped: $filesSkipped)',
                sourcePath: sourcePath,
                destPath: destPath,
              ),
            );
          } catch (_) {}

          if (onCompletionAction == 'pause') {
            _scheduleTimer?.cancel();
            _scheduleTimer = null;
            _scheduleNextRun();
          } else {
            isProcessing = false;
            currentStatus = 'Idle';
            _scheduleTimer?.cancel();
            _scheduleTimer = null;
          }
        }
      }

      notifyListeners();
    } catch (e, stack) {
      _log.severe(
        'Error polling Rust copy worker (pair ${origIdx + 1})',
        e,
        stack,
      );
      worker.pollTimer?.cancel();
      worker.pollTimer = null;
      worker.job.dispose();
      _activeWorkers.remove(worker);
      isProcessing = false;
      currentStatus = 'Idle';
      notifyListeners();
    } finally {
      worker.isPolling = false;
    }
  }
}
