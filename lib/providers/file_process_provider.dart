import 'dart:async';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import '../services/file_logger.dart';
import '../services/history_service.dart';
import '../models/run_record.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FileProcessProvider with ChangeNotifier {
  final Logger _log = Logger('FileProcessProvider');
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

  // Performance: cache for _hasSubdirectories results
  final Map<String, bool> _subdirCache = {};

  // Performance: cache for created destination directories
  final Set<String> _createdDirs = {};

  // Performance: throttle _saveProgress calls
  int _filesSinceLastSave = 0;
  static const int _saveProgressInterval = 20;

  FileProcessProvider() {
    _loadSettings();
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
    final prefs = await SharedPreferences.getInstance();
    sourcePath = prefs.getString('sourcePath');
    destPath = prefs.getString('destPath');
    clientName = prefs.getString('clientName') ?? 'WaterBrothers';
    selectedYear = prefs.getInt('selectedYear') ?? 2025;
    final savedMonths = prefs.getStringList('transfer_validMonths');
    if (savedMonths != null && savedMonths.isNotEmpty) {
      validMonths = savedMonths;
    }
    lastProcessedParent = prefs.getString('lastProcessedParent');
    lastProcessedChild = prefs.getString('lastProcessedChild');

    // Load time window settings
    enableTimeWindow = prefs.getBool('transfer_enableTimeWindow') ?? false;
    final fromHour = prefs.getInt('transfer_runFromHour');
    final fromMinute = prefs.getInt('transfer_runFromMinute');
    if (fromHour != null && fromMinute != null) {
      runFromTime = TimeOfDay(hour: fromHour, minute: fromMinute);
    }
    final toHour = prefs.getInt('transfer_runToHour');
    final toMinute = prefs.getInt('transfer_runToMinute');
    if (toHour != null && toMinute != null) {
      runToTime = TimeOfDay(hour: toHour, minute: toMinute);
    }

    // Load run days
    for (int day = 1; day <= 7; day++) {
      runDays[day] = prefs.getBool('transfer_runDay_$day') ?? false;
    }

    onCompletionAction = prefs.getString('transfer_onCompletionAction') ?? 'pause';

    _detectClientName();
    notifyListeners();
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (sourcePath != null) await prefs.setString('sourcePath', sourcePath!);
    if (destPath != null) await prefs.setString('destPath', destPath!);
    await prefs.setString('clientName', clientName);
    await prefs.setInt('selectedYear', selectedYear);
    await prefs.setStringList('transfer_validMonths', validMonths);

    await prefs.setBool('transfer_enableTimeWindow', enableTimeWindow);
    await prefs.setInt('transfer_runFromHour', runFromTime.hour);
    await prefs.setInt('transfer_runFromMinute', runFromTime.minute);
    await prefs.setInt('transfer_runToHour', runToTime.hour);
    await prefs.setInt('transfer_runToMinute', runToTime.minute);

    // Save run days
    for (int day = 1; day <= 7; day++) {
      await prefs.setBool('transfer_runDay_$day', runDays[day] ?? false);
    }

    await prefs.setString('transfer_onCompletionAction', onCompletionAction);
  }

  Future<void> _saveProgress(String parent, String child) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastProcessedParent', parent);
    await prefs.setString('lastProcessedChild', child);
    lastProcessedParent = parent;
    lastProcessedChild = child;
  }

  Future<void> clearProgress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('lastProcessedParent');
    await prefs.remove('lastProcessedChild');
    lastProcessedParent = null;
    lastProcessedChild = null;
    _addLog('✓ Progress cleared.');
    notifyListeners();
  }

  void setSourcePath(String? path) {
    sourcePath = path;
    _detectClientName();
    _saveSettings();
    notifyListeners();
  }

  void setDestPath(String? path) {
    destPath = path;
    _saveSettings();
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
      notifyListeners();
      // Complete the pause completer to unblock the processing loop
      if (_pauseCompleter != null && !_pauseCompleter!.isCompleted) {
        _pauseCompleter!.complete();
      }
    } else if (!inWindow && !isPaused) {
      // Pause
      isPaused = true;
      _pauseCompleter = Completer<void>();
      currentStatus = '⏸ Waiting for time window...';
      _addLog('⏸ Outside allowed time window. Paused until next run window.');
      notifyListeners();
    }
  }

  /// If currently paused, awaits the completer until the schedule timer
  /// resumes processing. Returns false if stop was requested during pause.
  Future<bool> _awaitIfPaused() async {
    if (isPaused && _pauseCompleter != null && !_pauseCompleter!.isCompleted) {
      await _pauseCompleter!.future;
    }
    return !_stopRequested;
  }

  /// Schedules the next automatic run at the configured `runFromTime`.
  void _scheduleNextRun() {
    _completionRescheduleTimer?.cancel();

    final now = DateTime.now();
    DateTime nextRun = DateTime(
      now.year, now.month, now.day,
      runFromTime.hour, runFromTime.minute,
    );

    if (!nextRun.isAfter(now)) {
      nextRun = nextRun.add(const Duration(days: 1));
    }

    final waitDuration = nextRun.difference(now);
    final formattedNext = DateFormat('dd/MM/yyyy HH:mm').format(nextRun);

    isPaused = true;
    currentStatus = '🏁 Completed. Next run at $formattedNext';
    _addLog('🏁 Transfer complete. Scheduled next run at $formattedNext (in ${waitDuration.inHours}h ${waitDuration.inMinutes % 60}m).');
    notifyListeners();

    _completionRescheduleTimer = Timer(waitDuration, () {
      _completionRescheduleTimer = null;
      _addLog('⏳ Scheduled time reached. Starting new run...');
      isPaused = false;
      startProcessing();
    });
  }

  void stop() {
    _stopRequested = true;
    _scheduleTimer?.cancel();
    _scheduleTimer = null;
    _completionRescheduleTimer?.cancel();
    _completionRescheduleTimer = null;

    // Unblock the pause completer so the processing loop can exit
    if (_pauseCompleter != null && !_pauseCompleter!.isCompleted) {
      _pauseCompleter!.complete();
    }

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
      await _fileLogger.error('Transfer', 'Source or Destination not selected.');
      return;
    }

    isProcessing = true;
    _stopRequested = false;
    isPaused = false;
    filesMoved = 0;
    errors = 0;
    _subdirCache.clear();
    _createdDirs.clear();
    _filesSinceLastSave = 0;
    notifyListeners();

    _addLog('⏳ Starting transfer...');
    _addLog('  Source: $sourcePath');
    _addLog('  Destination: $destPath');
    _addLog('  Filter: Year $selectedYear, Months ${validMonths.join(', ')}');
    if (enableTimeWindow) {
      final String formattedFrom = '${runFromTime.hour.toString().padLeft(2, '0')}:${runFromTime.minute.toString().padLeft(2, '0')}';
      final String formattedTo = '${runToTime.hour.toString().padLeft(2, '0')}:${runToTime.minute.toString().padLeft(2, '0')}';
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
      await _fileLogger.info('Transfer', 'Resuming from Parent: [$lastProcessedParent], Child: [$lastProcessedChild]');
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
        await _fileLogger.error('Transfer', 'Source directory does not exist: $sourcePath');
        return;
      }

      await _processDirectory(sourceDir);

      if (_stopRequested) {
        _addLog('⛔ Stopped by user.');
      } else {
        final elapsed = _getElapsedStr();
        _addLog('🏁 Completed: ${_numFmt.format(filesMoved)} moved, ${_numFmt.format(errors)} errors in $elapsed');
      }
    } catch (e, stack) {
      _addLog('✗ Critical Error: $e');
      _log.severe(e, stack);
      await _fileLogger.error('Transfer', 'Critical Error: $e\n$stack');
    } finally {
      await _fileLogger.logRunEnd(
        operation: 'Transfer',
        filesProcessed: filesMoved,
        errors: errors,
        wasStopped: _stopRequested,
      );
      
      try {
        final start = _fileLogger.getStartTime('Transfer') ?? DateTime.now();
        await HistoryService().saveRecord(RunRecord(
          id: _fileLogger.getRunId('Transfer') ?? 'UNKNOWN',
          operation: 'Transfer',
          startTime: start,
          endTime: DateTime.now(),
          filesProcessed: filesMoved,
          errors: errors,
          status: _stopRequested ? 'Stopped' : 'Completed',
          configSummary: 'Source: $sourcePath, Dest: $destPath',
        ));
      } catch (_) {}

      _stopTimer();
      _scheduleTimer?.cancel();
      _scheduleTimer = null;
      _subdirCache.clear();
      _createdDirs.clear();

      if (!_stopRequested && onCompletionAction == 'pause') {
        // Stay in processing state and schedule next run
        _scheduleNextRun();
      } else {
        // 'stop' or user-stopped → fully stop
        isProcessing = false;
        isPaused = false;
        currentStatus = _stopRequested ? '⛔ Stopped by user.' : 'Idle';
        _completionRescheduleTimer?.cancel();
        _completionRescheduleTimer = null;
      }
      notifyListeners();
    }
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
    _subdirCache.clear();
    _createdDirs.clear();
    notifyListeners();
  }

  Future<void> _processDirectory(Directory rootDir) async {
    bool skippingParents = lastProcessedParent != null;

    // Sort directories to ensure consistent order for resuming
    List<FileSystemEntity> parentEntities = rootDir
        .listSync()
        .whereType<Directory>()
        .toList();
    parentEntities.sort(
      (a, b) => p.basename(a.path).compareTo(p.basename(b.path)),
    );

    for (var entity in parentEntities) {
      if (_stopRequested) return;
      if (!(await _awaitIfPaused())) return;
      if (entity is! Directory) continue;

      String parentName = p.basename(entity.path);

      if (skippingParents) {
        if (parentName == lastProcessedParent) {
          skippingParents =
              false; // Found the parent, stop skipping parents, but might skip children
        } else {
          continue; // Skip this parent
        }
      }

      currentStatus = '⏳ Processing: $parentName';
      // notifyListeners(); // Throttled

      await _processSubDirectories(entity, parentName);

      // If we finished a parent completely without stopping, we can checkpoint here or inside the child loop
      // The original script updated start index after the loop.
    }
  }

  Future<void> _processSubDirectories(
    Directory parentDir,
    String parentName,
  ) async {
    bool skippingChildren =
        lastProcessedChild != null && lastProcessedParent == parentName;

    List<FileSystemEntity> childEntities = parentDir
        .listSync()
        .whereType<Directory>()
        .toList();
    childEntities.sort(
      (a, b) => p.basename(a.path).compareTo(p.basename(b.path)),
    );

    for (var entity in childEntities) {
      if (_stopRequested) return;
      if (!(await _awaitIfPaused())) return;
      if (entity is! Directory) continue;

      String childName = p.basename(entity.path);

      if (skippingChildren) {
        if (childName == lastProcessedChild) {
          skippingChildren = false;
          // We resume *from* this child (re-process it) or *after*?
          // Script logic: "if lNo2 >= startChildIndex". It processes the saved index too.
          // So we should process this one.
        } else {
          continue;
        }
      }

      currentStatus = '⏳ Scanning: $parentName / $childName';
      // Don't notify on every single folder scan to avoid UI stutter, maybe throttle?

      // Throttle progress saves to every N files
      _filesSinceLastSave++;
      if (_filesSinceLastSave >= _saveProgressInterval) {
        await _saveProgress(parentName, childName);
        _filesSinceLastSave = 0;
      } else {
        // Still update in-memory for resume tracking
        lastProcessedParent = parentName;
        lastProcessedChild = childName;
      }

      await _processFiles(entity);
    }

    // After finishing all children of this parent, we reset child progress for next parent?
    // Actually we just set the new parent checkpoint.
  }

  Future<void> _processFiles(Directory dir) async {
    // Current logic: "if len(subdirs) == 0".
    // The script traverses `for path, subdirs, files in os.walk(finalorigin2)`.
    // And checks `if len(subdirs) == 0`. It seems it only processes leaf nodes?
    // Let's emulate that: recurse or just listSync(recursive: true)

    // Using listSync(recursive: true) might be memory intensive for huge trees.
    // Better to just walk.

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (_stopRequested) return;
      if (!(await _awaitIfPaused())) return;
      if (entity is File) {
        // Check if it's in a leaf dir? The script says `if len(subdirs) == 0`.
        // In `os.walk`, `subdirs` is the list of directories in `path`.
        // This implies we only care about files in directories that have no subdirectories.
        // This is a specific constraint.

        // To check this efficiently (now cached):
        Directory fileParent = entity.parent;
        if (await _hasSubdirectories(fileParent)) {
          continue; // Skip files in non-leaf directories
        }

        await _checkAndMoveFile(entity);
      }
    }
  }

  /// Cached check for whether a directory has subdirectories.
  Future<bool> _hasSubdirectories(Directory dir) async {
    final key = dir.path;
    if (_subdirCache.containsKey(key)) {
      return _subdirCache[key]!;
    }

    bool hasSubdirs = false;
    try {
      await for (final entity in dir.list(recursive: false)) {
        if (entity is Directory) {
          hasSubdirs = true;
          break;
        }
      }
    } catch (e) {
      // Access denied or gone
    }
    _subdirCache[key] = hasSubdirs;
    return hasSubdirs;
  }

  Future<void> _checkAndMoveFile(File file) async {
    try {
      FileStat stats = await file.stat();
      DateTime modified = stats.modified;

      String yearStr = DateFormat('yyyy').format(modified);
      String monthStr = DateFormat('MMM').format(modified); // 'Jan', 'Feb'

      // Check filters
      if (int.parse(yearStr) <= selectedYear &&
          validMonths.contains(monthStr)) {
        // Move it
        await _moveFile(file, yearStr, monthStr);
      }
    } catch (e) {
      _addLog('✗ Error accessing ${file.path}: $e');
      await _fileLogger.error('Transfer', 'Error accessing ${file.path}: $e');
      errors++;
    }
  }

  Future<void> _moveFile(File file, String year, String month) async {
    try {
      // Logic from script:
      // initialPath = path.split('\\', 6)  -> based on `origin` depth.
      // filterText = initialPath[6].rsplit('\\', 1)
      // finalFilterText = filterText[0]+'\\'
      // finalMoveTo = os.path.join(moveto,getyear,finalFilterText,filterText[1])

      /*
         Script Origins:
         origin = '\\\\Myflofs2\\apps\\myFloWaterBrothers\\EmailAttachments\\'
         Subdirs1 (Parent) e.g. "SomeParent"
         FinalOrigin = origin/SomeParent
         Subdirs2 (Child) e.g. "SomeChild"
         FinalOrigin2 = origin/SomeParent/SomeChild
         
         Then os.walk(FinalOrigin2).
         Path = origin/SomeParent/SomeChild/.../LeafFolder
         
         split('\\', 6)?
         0: 
         1: 
         2: Myflofs2
         3: apps
         4: myFloWaterBrothers
         5: EmailAttachments
         6: Rest of path starting with Parent/Child/...
         
         This relies heavily on the exact source path structure!
         
         In our generic app, we should probably replicate the *relative path* from Source to the file.
       */

      // Calculate relative path from source
      String relativePath = p.relative(file.parent.path, from: sourcePath!);

      // Construct destination
      // Script: moveto / year / ...
      // Let's use: dest / year / relativePath

      String destDir = p.join(destPath!, year, relativePath);
      String destFilePath = p.join(destDir, p.basename(file.path));

      // Cached directory creation
      if (!_createdDirs.contains(destDir)) {
        await Directory(destDir).create(recursive: true);
        _createdDirs.add(destDir);
      }

      // Move: copy then delete (safe for cross-volume moves)
      await file.copy(destFilePath);
      await file.delete();

      _addLog('✓ Moved [$month-$year]: ${p.basename(file.path)}');
      filesMoved++;
      // notifyListeners(); // Throttled
    } catch (e) {
      _addLog('✗ Failed to move ${file.path}: $e');
      await _fileLogger.error('Transfer', 'Failed to move ${file.path}: $e');
      errors++;
    }
  }
}
