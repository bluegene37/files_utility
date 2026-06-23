import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import '../services/file_logger.dart';
import '../services/history_service.dart';
import '../services/local_db_service.dart';
import '../models/run_record.dart';
import '../services/global_db_service.dart';

class _TransferControl {
  final bool pause;
  final bool resume;
  final bool stop;
  _TransferControl({
    this.pause = false,
    this.resume = false,
    this.stop = false,
  });
}

class _TransferParams {
  final String sourcePath;
  final String destPath;
  final bool enableAgeFilter;
  final String ageFilterUnit;
  final int ageFilterValue;
  final bool enableDateRange;
  final int selectedYear;
  final List<String> validMonths;
  final String? lastParent;
  final String? lastChild;
  final SendPort mainSendPort;
  final int initialFilesMoved;
  final int initialErrors;

  _TransferParams({
    required this.sourcePath,
    required this.destPath,
    required this.enableAgeFilter,
    required this.ageFilterUnit,
    required this.ageFilterValue,
    required this.enableDateRange,
    required this.selectedYear,
    required this.validMonths,
    this.lastParent,
    this.lastChild,
    required this.mainSendPort,
    this.initialFilesMoved = 0,
    this.initialErrors = 0,
  });
}

class _TransferProgress {
  final int filesMoved;
  final int errors;
  final List<String> logs;
  final String? currentStatus;
  final bool isDone;
  final String? criticalError;
  final String? saveParent;
  final String? saveChild;
  final SendPort? workerSendPort;

  _TransferProgress({
    this.filesMoved = 0,
    this.errors = 0,
    this.logs = const [],
    this.currentStatus,
    this.isDone = false,
    this.criticalError,
    this.saveParent,
    this.saveChild,
    this.workerSendPort,
  });
}

class TransferFilesProvider with ChangeNotifier {
  final Logger _log = Logger('TransferFilesProvider');
  final FileLogger _fileLogger = FileLogger();
  final NumberFormat _numFmt = NumberFormat('#,##0');

  // State
  String? sourcePath;
  String? destPath;
  String clientName = 'WaterBrothers'; // Default from script
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

  List<String> availableClients = [
    'WaterBrothers',
    'FRP',
    'Chips',
    'ETS-East',
    'LPS',
    'IGPest',
  ];

  List<int> get availableYears {
    List<int> years = [];
    int currentYear = DateTime.now().year;
    for (int i = 2010; i <= currentYear + 5; i++) {
      years.add(i);
    }
    return years.reversed.toList();
  }

  bool isProcessing = false;
  List<String> logs = [];
  String currentStatus = 'Idle';

  // Age filter
  bool enableAgeFilter = false;
  String ageFilterUnit = 'Days';
  int ageFilterValue = 30;

  // Date range filter for Transfer
  bool enableDateRange = false;

  // Resume state
  String? lastProcessedParent;
  String? lastProcessedChild;

  // Stats
  int filesMoved = 0;
  int errors = 0;

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

  // Pause/Schedule State
  bool isPaused = false;
  Timer? _scheduleTimer;
  Timer? _completionRescheduleTimer;
  Completer<void>? _pauseCompleter;

  // Isolate state
  Isolate? _workerIsolate;
  SendPort? _workerControlPort;

  TransferFilesProvider() {
    _loadSettings();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _scheduleTimer?.cancel();
    _completionRescheduleTimer?.cancel();
    _workerIsolate?.kill(priority: Isolate.immediate);
    super.dispose();
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
    // notifyListeners(); // Throttled
  }

  Future<void> _loadSettings() async {
    final db = LocalDbService();
    sourcePath = db.getString('sourcePath');
    destPath = db.getString('destPath');
    clientName = db.getString('clientName') ?? 'WaterBrothers';
    selectedYear = db.getInt('selectedYear') ?? 2025;
    enableAgeFilter = db.getBool('transfer_enableAgeFilter') ?? false;
    ageFilterUnit = db.getString('transfer_ageFilterUnit') ?? 'Days';
    ageFilterValue = db.getInt('transfer_ageFilterValue') ?? 30;
    enableDateRange = db.getBool('transfer_enableDateRange') ?? false;
    final savedMonths = db.getStringList('transfer_validMonths');
    if (savedMonths != null && savedMonths.isNotEmpty) {
      validMonths = savedMonths;
    }
    _loadProgress();

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

    _detectClientName();
    notifyListeners();
  }

  Future<void> _saveSettings() async {
    final db = LocalDbService();
    if (sourcePath != null) await db.setString('sourcePath', sourcePath!);
    if (destPath != null) await db.setString('destPath', destPath!);
    await db.setString('clientName', clientName);
    await db.setInt('selectedYear', selectedYear);
    await db.setBool('transfer_enableAgeFilter', enableAgeFilter);
    await db.setString('transfer_ageFilterUnit', ageFilterUnit);
    await db.setInt('transfer_ageFilterValue', ageFilterValue);
    await db.setBool('transfer_enableDateRange', enableDateRange);
    await db.setStringList('transfer_validMonths', validMonths);

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
    final appDir = GlobalDbService().appDirPath ?? r'C:\temp\file transfer';
    return '$appDir\\progress\\transfer_progress_${s}_${d}_$profileId.json';
  }

  Future<void> _loadProgress() async {
    lastProcessedParent = null;
    lastProcessedChild = null;
    filesMoved = 0;
    errors = 0;
    try {
      final file = File(_progressFilePath);
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        lastProcessedParent = data['parent'];
        lastProcessedChild = data['child'];
        filesMoved = data['filesMoved'] ?? 0;
        errors = data['errors'] ?? 0;
      }
    } catch (_) {}
  }

  Future<void> _saveProgress(
    String? parent,
    String? child,
    int fMoved,
    int errs,
  ) async {
    if (parent != null) lastProcessedParent = parent;
    if (child != null) lastProcessedChild = child;
    try {
      final file = File(_progressFilePath);
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      await file.writeAsString(
        jsonEncode({
          'parent': lastProcessedParent,
          'child': lastProcessedChild,
          'filesMoved': fMoved,
          'errors': errs,
        }),
      );
    } catch (_) {}
  }

  Future<void> clearProgress() async {
    lastProcessedParent = null;
    lastProcessedChild = null;
    filesMoved = 0;
    errors = 0;
    try {
      final file = File(_progressFilePath);
      if (await file.exists()) await file.delete();
    } catch (_) {}
    _addLog('✓ Progress cleared.');
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
    _detectClientName();
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

  void _detectClientName() {
    if (sourcePath == null) {
      clientName = 'Unknown';
      return;
    }

    String? detected;

    // Check for "myFlo" prefixed folder in the path
    List<String> segments = p.split(sourcePath!);
    for (String segment in segments) {
      if (segment.toLowerCase().startsWith('myflo') && segment.length > 5) {
        // Extract client name after "myFlo"
        detected = segment.substring(5);
        break;
      }
    }

    // Fallback to containment check if no "myFlo" folder found
    if (detected == null) {
      for (var client in availableClients) {
        if (sourcePath!.toLowerCase().contains(client.toLowerCase())) {
          detected = client;
          break;
        }
      }
    }

    clientName = detected ?? 'Unknown';
  }

  // Removed manual setClientName as it's now auto-detected
  // void setClientName(String name) { ... }

  void setYear(int year) {
    selectedYear = year;
    _saveSettings();
    notifyListeners();
  }

  void setEnableDateRange(bool val) {
    enableDateRange = val;
    if (val) enableAgeFilter = false;
    _saveSettings();
    notifyListeners();
  }

  void setEnableAgeFilter(bool val) {
    enableAgeFilter = val;
    if (val) enableDateRange = false;
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

  void toggleMonth(String month) {
    if (validMonths.contains(month)) {
      validMonths.remove(month);
    } else {
      validMonths.add(month);
    }
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
      currentStatus = '⏳ Processing...';
      _addLog('⏳ Time window reached. Resuming transfer...');
      _workerControlPort?.send(_TransferControl(resume: true));
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
      _workerControlPort?.send(_TransferControl(pause: true));
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

    _saveProgress(lastProcessedParent, lastProcessedChild, filesMoved, errors);

    if (_pauseCompleter != null && !_pauseCompleter!.isCompleted) {
      _pauseCompleter!.complete();
    }

    // If the worker isolate is already gone (e.g. transfer completed and is
    // in the scheduled-pause / "next run" state), clean up immediately.
    if (_workerIsolate == null) {
      _cleanupAfterStop();
      return;
    }

    _workerControlPort?.send(_TransferControl(stop: true));

    // Fallback kill if isolate is completely stuck
    Future.delayed(const Duration(seconds: 2), () {
      if (_workerIsolate != null) {
        _workerIsolate?.kill(priority: Isolate.immediate);
        _workerIsolate = null;
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
    if (sourcePath == null || destPath == null) {
      _addLog('✗ Error: Source or Destination not selected.');
      await _fileLogger.error(
        'Transfer',
        'Source or Destination not selected.',
      );
      return;
    }

    isProcessing = true;
    _stopRequested = false;
    isPaused = false;
    // Initial filesMoved and errors are kept from _loadProgress()
    notifyListeners();

    _addLog('⏳ Starting transfer...');
    _addLog('  Source: $sourcePath');
    _addLog('  Destination: $destPath');
    if (enableDateRange) {
      _addLog('  Filter: Year $selectedYear, Months ${validMonths.join(', ')}');
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
      year: selectedYear,
      months: validMonths,
    );

    if (lastProcessedParent != null) {
      _addLog(
        '⏳ Resuming from Parent: [$lastProcessedParent], Child: [$lastProcessedChild]',
      );
      await _fileLogger.info(
        'Transfer',
        'Resuming from Parent: [$lastProcessedParent], Child: [$lastProcessedChild]',
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

      final receivePort = ReceivePort();

      _workerIsolate = await Isolate.spawn(
        _isolateWorker,
        _TransferParams(
          sourcePath: sourcePath!,
          destPath: destPath!,
          enableAgeFilter: enableAgeFilter,
          ageFilterUnit: ageFilterUnit,
          ageFilterValue: ageFilterValue,
          enableDateRange: enableDateRange,
          selectedYear: selectedYear,
          validMonths: validMonths,
          lastParent: lastProcessedParent,
          lastChild: lastProcessedChild,
          mainSendPort: receivePort.sendPort,
          initialFilesMoved: filesMoved,
          initialErrors: errors,
        ),
      );

      receivePort.listen((message) {
        if (message is _TransferProgress) {
          if (message.workerSendPort != null) {
            _workerControlPort = message.workerSendPort;
            if (isPaused) {
              _workerControlPort?.send(_TransferControl(pause: true));
            }
            return;
          }

          filesMoved = message.filesMoved;
          errors = message.errors;

          if (message.currentStatus != null) {
            currentStatus = message.currentStatus!;
          }

          if (message.saveParent != null && message.saveChild != null) {
            _saveProgress(
              message.saveParent!,
              message.saveChild!,
              filesMoved,
              errors,
            );
          }

          for (final log in message.logs) {
            _addLog(log);
            if (log.startsWith('✗')) {
              _fileLogger.error('Transfer', log);
            }
          }

          if (message.criticalError != null) {
            _addLog('✗ Critical Error: ${message.criticalError}');
            _fileLogger.error(
              'Transfer',
              'Critical Error: ${message.criticalError}',
            );
          }

          if (message.isDone) {
            receivePort.close();
            _workerIsolate = null;
            _workerControlPort = null;
            if (!_stopRequested) {
              _finishRun(wasStopped: false);
            } else {
              _cleanupAfterStop();
            }
          }
        }
      });
    } catch (e, stack) {
      _addLog('✗ Critical Error: $e');
      _log.severe('Critical error during transfer', e, stack);
      await _fileLogger.error('Transfer', 'Critical Error: $e\n$stack');
      _finishRun(wasStopped: false);
    }
  }

  Future<void> _finishRun({required bool wasStopped}) async {
    final elapsed = _getElapsedStr();
    if (wasStopped) {
      _addLog('⛔ Stopped by user.');
    } else {
      _addLog(
        '🏁 Completed: ${_numFmt.format(filesMoved)} moved, ${_numFmt.format(errors)} errors in $elapsed',
      );
    }

    final runId = _fileLogger.getRunId('Transfer') ?? 'UNKNOWN';
    final start = _fileLogger.getStartTime('Transfer') ?? DateTime.now();

    await _fileLogger.logRunEnd(
      operation: 'Transfer',
      filesProcessed: filesMoved,
      errors: errors,
      wasStopped: wasStopped,
    );

    try {
      await HistoryService().saveRecord(
        RunRecord(
          id: runId,
          operation: 'Transfer',
          startTime: start,
          endTime: DateTime.now(),
          filesProcessed: filesMoved,
          errors: errors,
          status: wasStopped ? 'Stopped' : 'Completed',
          configSummary: 'Source: $sourcePath, Dest: $destPath',
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
      currentStatus = wasStopped ? '⛔ Stopped by user.' : 'Idle';
      _completionRescheduleTimer?.cancel();
      _completionRescheduleTimer = null;
    }
    notifyListeners();
  }

  /// Cleanup helper after stop is requested during pause-wait.
  void _cleanupAfterStop() {
    _fileLogger.logRunEnd(
      operation: 'Transfer',
      filesProcessed: filesMoved,
      errors: errors,
      wasStopped: true,
    );
    isProcessing = false;
    isPaused = false;
    currentStatus = '⛔ Stopped by user.';
    _addLog('⛔ Stopped by user.');
    _stopTimer();
    notifyListeners();
  }

  static Future<void> _isolateWorker(_TransferParams params) async {
    final workerReceivePort = ReceivePort();
    params.mainSendPort.send(
      _TransferProgress(workerSendPort: workerReceivePort.sendPort),
    );

    bool isPaused = false;
    bool stopRequested = false;
    Completer<void>? pauseCompleter;

    Future<bool> awaitIfPaused() async {
      if (isPaused && pauseCompleter != null && !pauseCompleter!.isCompleted) {
        await pauseCompleter!.future;
      }
      return !stopRequested;
    }

    int filesMoved = params.initialFilesMoved;
    int errors = params.initialErrors;
    List<String> logBatch = [];
    int scanCount = 0;
    final Map<String, bool> subdirCache = {};
    final Set<String> createdDirs = {};

    int filesSinceLastSave = 0;
    const int saveProgressInterval = 20;

    void flushProgress(
      String? status, {
      bool force = false,
      String? sParent,
      String? sChild,
    }) {
      if (force ||
          logBatch.isNotEmpty ||
          scanCount % 10 == 0 ||
          sParent != null) {
        params.mainSendPort.send(
          _TransferProgress(
            filesMoved: filesMoved,
            errors: errors,
            logs: List.from(logBatch),
            currentStatus: status,
            saveParent: sParent,
            saveChild: sChild,
          ),
        );
        logBatch.clear();
      }
    }

    workerReceivePort.listen((message) {
      if (message is _TransferControl) {
        if (message.stop) {
          stopRequested = true;
          flushProgress('⛔ Stopping...', force: true);
          if (pauseCompleter != null && !pauseCompleter!.isCompleted) {
            pauseCompleter!.complete();
          }
        } else if (message.pause) {
          isPaused = true;
          pauseCompleter = Completer<void>();
        } else if (message.resume) {
          isPaused = false;
          if (pauseCompleter != null && !pauseCompleter!.isCompleted) {
            pauseCompleter!.complete();
          }
        }
      }
    });

    Future<bool> hasSubdirectories(Directory dir) async {
      final key = dir.path;
      if (subdirCache.containsKey(key)) return subdirCache[key]!;

      bool hasSubdirs = false;
      try {
        await for (final entity in dir.list(recursive: false)) {
          if (entity is Directory) {
            hasSubdirs = true;
            break;
          }
        }
      } catch (e) {
        // Ignored
      }
      subdirCache[key] = hasSubdirs;
      return hasSubdirs;
    }

    Future<void> moveFile(File file, String year, String month) async {
      try {
        String relativePath = p.relative(
          file.parent.path,
          from: params.sourcePath,
        );
        // Only organize into year-based subdirectories when date range is enabled
        String destDir;
        if (params.enableDateRange && year.isNotEmpty) {
          destDir = p.join(params.destPath, year, relativePath);
        } else {
          destDir = p.join(params.destPath, relativePath);
        }
        String destFilePath = p.join(destDir, p.basename(file.path));

        if (!createdDirs.contains(destDir)) {
          await Directory(destDir).create(recursive: true);
          createdDirs.add(destDir);
        }

        await file.copy(destFilePath);
        await file.delete();

        if (year.isNotEmpty) {
          logBatch.add('✓ Moved [$month-$year]: ${p.basename(file.path)}');
        } else {
          logBatch.add('✓ Moved: ${p.basename(file.path)}');
        }
        filesMoved++;
      } catch (e) {
        logBatch.add('✗ Failed to move ${file.path}: $e');
        errors++;
      }
    }

    Future<void> checkAndMoveFile(File file) async {
      try {
        FileStat stats = await file.stat();
        DateTime modified = stats.modified;

        if (params.enableAgeFilter) {
          DateTime threshold;
          final now = DateTime.now();
          if (params.ageFilterUnit == 'Days') {
            threshold = now.subtract(Duration(days: params.ageFilterValue));
          } else if (params.ageFilterUnit == 'Months') {
            threshold = DateTime(
              now.year,
              now.month - params.ageFilterValue,
              now.day,
            );
          } else {
            threshold = DateTime(
              now.year - params.ageFilterValue,
              now.month,
              now.day,
            );
          }
          if (modified.isAfter(threshold)) return;
        }

        if (params.enableDateRange) {
          // Date range filter is enabled: check year/month and organize by year
          String yearStr = DateFormat('yyyy').format(modified);
          String monthStr = DateFormat('MMM').format(modified);

          if (int.parse(yearStr) == params.selectedYear &&
              params.validMonths.contains(monthStr)) {
            await moveFile(file, yearStr, monthStr);
          }
        } else {
          // No date range filter: move all files, no year-based organization
          await moveFile(file, '', '');
        }
      } catch (e) {
        logBatch.add('✗ Error accessing ${file.path}: $e');
        errors++;
      }
    }

    Future<void> processFiles(Directory dir) async {
      int filesInDir = 0;
      await for (final entity in dir.list(recursive: true, followLinks: true)) {
        if (stopRequested) return;
        if (!(await awaitIfPaused())) return;

        if (entity is File) {
          filesInDir++;
          if (filesInDir % 1000 == 0) {
            flushProgress(
              '⏳ Scanning files in ${p.basename(dir.path)}: $filesInDir files checked',
              force: true,
            );
          }

          Directory fileParent = entity.parent;
          if (await hasSubdirectories(fileParent)) continue;

          await checkAndMoveFile(entity);
        }
      }
    }

    Future<void> processSubDirectories(
      Directory parentDir,
      String parentName,
    ) async {
      bool skippingChildren =
          params.lastChild != null && params.lastParent == parentName;

      List<FileSystemEntity> childEntities = [];
      await for (final e in parentDir.list(recursive: false)) {
        if (e is Directory) childEntities.add(e);
      }
      childEntities.sort(
        (a, b) => p.basename(a.path).compareTo(p.basename(b.path)),
      );

      for (var entity in childEntities) {
        if (stopRequested) return;
        if (!(await awaitIfPaused())) return;

        String childName = p.basename(entity.path);

        if (skippingChildren) {
          if (childName == params.lastChild) {
            skippingChildren = false;
          } else {
            continue;
          }
        }

        scanCount++;

        filesSinceLastSave++;
        if (filesSinceLastSave >= saveProgressInterval) {
          filesSinceLastSave = 0;
          flushProgress(
            '⏳ Scanning: $parentName / $childName',
            sParent: parentName,
            sChild: childName,
          );
        } else {
          flushProgress('⏳ Scanning: $parentName / $childName');
        }

        await processFiles(Directory(entity.path));
      }
    }

    Future<void> processDirectory(Directory rootDir) async {
      bool skippingParents = params.lastParent != null;

      List<FileSystemEntity> parentEntities = [];
      await for (final e in rootDir.list(recursive: false)) {
        if (e is Directory) parentEntities.add(e);
      }
      parentEntities.sort(
        (a, b) => p.basename(a.path).compareTo(p.basename(b.path)),
      );

      for (var entity in parentEntities) {
        if (stopRequested) return;
        if (!(await awaitIfPaused())) return;

        String parentName = p.basename(entity.path);

        if (skippingParents) {
          if (parentName == params.lastParent) {
            skippingParents = false;
          } else {
            continue;
          }
        }

        flushProgress('⏳ Processing: $parentName');
        await processSubDirectories(Directory(entity.path), parentName);
      }
    }

    try {
      await processDirectory(Directory(params.sourcePath));
      flushProgress('DONE', force: true);
      params.mainSendPort.send(_TransferProgress(isDone: true));
    } catch (e) {
      params.mainSendPort.send(
        _TransferProgress(criticalError: e.toString(), isDone: true),
      );
    }
  }
}
