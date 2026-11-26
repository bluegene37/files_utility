import 'dart:async';
import 'dart:io';
// Gene - Nov, 25, 2026: Replaced Dart isolate worker with native Rust count_engine.
// import 'dart:isolate';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
// import 'package:path/path.dart' as p;
import '../services/file_logger.dart';
import '../services/history_service.dart';
import '../services/local_db_service.dart';
// import '../services/path_safety.dart';
import '../services/rust_file_engines.dart';
import '../models/run_record.dart';

// Gene - Nov, 25, 2026: Commented out Dart isolate DTOs after migrating to Rust count_engine.
// class _CountProgress {
//   final int files;
//   final int folders;
//   final int errors;
//   final List<String> logs;
//   final String? currentScanPath;
//   final String? errorLog;
//   final bool isDone;
//
//   _CountProgress({
//     this.files = 0,
//     this.folders = 0,
//     this.errors = 0,
//     this.logs = const [],
//     this.currentScanPath,
//     this.errorLog,
//     this.isDone = false,
//   });
// }
//
// class _CountParams {
//   final String targetPath;
//   final int logInterval;
//   final SendPort sendPort;
//
//   _CountParams({
//     required this.targetPath,
//     required this.logInterval,
//     required this.sendPort,
//   });
// }

// Gene - Nov, 26, 2026: Added CountFileCategory enum with bitmask values matching native Rust count_engine.
enum CountFileCategory {
  images(
    id: 'images',
    label: 'Images',
    mask: 1 << 0,
    extensionsHint:
        '.jpg, .jpeg, .png, .gif, .webp, .svg, .heic, .tif, .bmp, .raw, .psd, ...',
  ),
  documents(
    id: 'documents',
    label: 'Documents',
    mask: 1 << 1,
    extensionsHint:
        '.pdf, .doc, .docx, .xls, .xlsx, .ppt, .pptx, .txt, .csv, .rtf, .md, ...',
  ),
  videos(
    id: 'videos',
    label: 'Videos',
    mask: 1 << 2,
    extensionsHint:
        '.mp4, .mov, .avi, .mkv, .wmv, .webm, .m4v, .mpg, .mpeg, ...',
  ),
  audio(
    id: 'audio',
    label: 'Audio',
    mask: 1 << 3,
    extensionsHint: '.mp3, .wav, .flac, .aac, .ogg, .m4a, .wma, .opus, .aiff, ...',
  ),
  archives(
    id: 'archives',
    label: 'Archives',
    mask: 1 << 4,
    extensionsHint: '.zip, .rar, .7z, .tar, .gz, .bz2, .xz, .iso, .dmg, ...',
  ),
  others(
    id: 'others',
    label: 'Others',
    mask: 1 << 5,
    extensionsHint: 'All other extensions & files without an extension',
  );

  final String id;
  final String label;
  final int mask;
  final String extensionsHint;

  const CountFileCategory({
    required this.id,
    required this.label,
    required this.mask,
    required this.extensionsHint,
  });
}

// Gene - Nov, 26, 2026: Added CountRunMode enum to distinguish Count, Folder Size, and Date Range runs.
enum CountRunMode { count, folderSize, dateRange }

class CountFilesProvider with ChangeNotifier {
  final FileLogger _fileLogger = FileLogger();
  final NumberFormat _numFmt = NumberFormat('#,##0');

  String? targetPath;
  bool isCounting = false;
  List<String> logs = [];
  String currentStatus = 'Idle';
  int totalFiles = 0;
  // Gene - Nov, 26, 2026: Track excluded file count and selected file-type filter categories.
  int excludedFiles = 0;
  Set<CountFileCategory> selectedCategories = Set<CountFileCategory>.from(
    CountFileCategory.values,
  );
  int totalFolders = 0;
  // Gene - Nov, 26, 2026: Track total counted bytes and whether the active/last run is size-only.
  int totalBytes = 0;
  // bool isSizeOnlyRun = false;
  // Gene - Nov, 26, 2026: Track activeRunMode plus oldest/latest file dates and relative paths.
  CountRunMode activeRunMode = CountRunMode.count;
  DateTime? oldestFileDate;
  String? oldestFilePath;
  DateTime? latestFileDate;
  String? latestFilePath;
  int errors = 0;
  int logInterval = 100;
  bool _stopRequested = false;
  // Gene - Nov, 25, 2026: Removed redundant 200ms _refreshTimer; 150ms _pollTimer drives UI updates directly.
  // Timer? _refreshTimer;
  // Gene - Nov, 25, 2026: Track native RustCountJob and poll timer instead of Dart isolate.
  // Isolate? _workerIsolate;
  // ReceivePort? _receivePort;
  RustCountJob? _rustJob;
  Timer? _pollTimer;
  // Gene - Nov, 26, 2026: Added non-blocking stop fallback timer for graceful Count stop().
  Timer? _stopFallbackTimer;

  CountFilesProvider() {
    _loadSettings();
    LocalDbService().addListener(_onProfileChanged);
  }

  void _onProfileChanged() {
    reloadSettings();
  }

  @override
  void dispose() {
    LocalDbService().removeListener(_onProfileChanged);
    // _refreshTimer?.cancel();
    // _stopIsolate();
    _stopRustJob();
    super.dispose();
  }

  // Gene - Nov, 25, 2026: Stop and dispose native RustCountJob cleanly.
  // void _stopIsolate() {
  //   _workerIsolate?.kill(priority: Isolate.immediate);
  //   _workerIsolate = null;
  //   _receivePort?.close();
  //   _receivePort = null;
  // }
  // void _stopRustJob() {
  //   _pollTimer?.cancel();
  //   _pollTimer = null;
  //   _rustJob?.stop();
  //   _rustJob?.dispose();
  //   _rustJob = null;
  // }
  void _stopRustJob() {
    _stopFallbackTimer?.cancel();
    _stopFallbackTimer = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _rustJob?.stop();
    _rustJob?.dispose();
    _rustJob = null;
  }

  void _addLog(String message) {
    final timestamp = DateFormat('HH:mm:ss').format(DateTime.now());
    logs.insert(0, '[$timestamp] $message');
    if (logs.length > 1000) logs.removeLast();
  }

  Future<void> _loadSettings() async {
    final db = LocalDbService();
    targetPath = db.getString('count_targetPath');
    logInterval = db.getInt('count_logInterval') ?? 100;
    // Gene - Nov, 26, 2026: Restore saved file-type categories (defaulting to all when unset).
    final savedCategories = db.getStringList('count_selectedCategories');
    if (savedCategories != null) {
      final savedIds = savedCategories.toSet();
      selectedCategories = CountFileCategory.values
          .where((c) => savedIds.contains(c.id))
          .toSet();
    } else {
      selectedCategories = Set<CountFileCategory>.from(
        CountFileCategory.values,
      );
    }
    notifyListeners();
  }

  Future<void> reloadSettings() async {
    await _loadSettings();
  }

  Future<void> _saveSettings() async {
    final db = LocalDbService();
    await db.setOrRemoveString('count_targetPath', targetPath);
    await db.setInt('count_logInterval', logInterval);
    // Gene - Nov, 26, 2026: Persist selected file-type categories per profile.
    await db.setStringList(
      'count_selectedCategories',
      CountFileCategory.values
          .where(selectedCategories.contains)
          .map((c) => c.id)
          .toList(),
    );
  }

  // Gene - Nov, 26, 2026: File-type filter helpers and mutators for CountFilesProvider.
  bool get allCategoriesSelected =>
      selectedCategories.length == CountFileCategory.values.length;

  bool get hasAnyCategorySelected => selectedCategories.isNotEmpty;

  bool get canStartCounting => targetPath != null && hasAnyCategorySelected;

  // Gene - Nov, 26, 2026: Format byte counts into human-readable B, KB, MB, GB, or TB strings.
  static String formatByteSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const int kb = 1024;
    const int mb = kb * 1024;
    const int gb = mb * 1024;
    const int tb = gb * 1024;
    if (bytes < kb) return '$bytes B';
    if (bytes < mb) return '${(bytes / kb).toStringAsFixed(1)} KB';
    if (bytes < gb) return '${(bytes / mb).toStringAsFixed(2)} MB';
    if (bytes < tb) return '${(bytes / gb).toStringAsFixed(2)} GB';
    return '${(bytes / tb).toStringAsFixed(2)} TB';
  }

  // Gene - Nov, 26, 2026: Added date range formatting and mode getters on CountFilesProvider.
  bool get isSizeOnlyRun => activeRunMode == CountRunMode.folderSize;
  bool get isDateRangeRun => activeRunMode == CountRunMode.dateRange;
  bool get hasDateRange => oldestFileDate != null && latestFileDate != null;

  static String formatDateShort(DateTime dt) =>
      DateFormat('dd/MM/yyyy').format(dt);

  static String formatDateTime(DateTime dt) =>
      DateFormat('dd/MM/yyyy HH:mm').format(dt);

  String get formattedDateRange => hasDateRange
      ? '${formatDateShort(oldestFileDate!)} – ${formatDateShort(latestFileDate!)}'
      : '—';

  String get formattedOldestDate =>
      oldestFileDate == null ? '—' : formatDateTime(oldestFileDate!);

  String get formattedLatestDate =>
      latestFileDate == null ? '—' : formatDateTime(latestFileDate!);

  String get formattedTotalSize => formatByteSize(totalBytes);
  bool get canGetFolderSize => targetPath != null && !isCounting;
  bool get canCheckDateRange => targetPath != null && !isCounting;

  int get categoryIncludeMask =>
      selectedCategories.fold<int>(0, (acc, c) => acc | c.mask);

  bool isCategorySelected(CountFileCategory category) =>
      selectedCategories.contains(category);

  String get filterSummary {
    if (allCategoriesSelected) return 'All Files';
    if (!hasAnyCategorySelected) return 'None';
    return CountFileCategory.values
        .where(selectedCategories.contains)
        .map((c) => c.label)
        .join(', ');
  }

  String get excludedSummary {
    return CountFileCategory.values
        .where((c) => !selectedCategories.contains(c))
        .map((c) => c.label)
        .join(', ');
  }

  void setAllCategories(bool selected) {
    if (isCounting) return;
    selectedCategories = selected
        ? Set<CountFileCategory>.from(CountFileCategory.values)
        : <CountFileCategory>{};
    _saveSettings();
    notifyListeners();
  }

  void toggleAllCategories() {
    setAllCategories(!allCategoriesSelected);
  }

  void toggleCategory(CountFileCategory category, [bool? value]) {
    if (isCounting) return;
    final shouldSelect = value ?? !selectedCategories.contains(category);
    if (shouldSelect) {
      selectedCategories.add(category);
    } else {
      selectedCategories.remove(category);
    }
    _saveSettings();
    notifyListeners();
  }

  void setLogInterval(int val) {
    logInterval = val;
    _saveSettings();
    notifyListeners();
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

  // Gene - Nov, 26, 2026: Make stop() non-blocking on UI thread using signal + 2s fallback timer.
  // void stop() {
  //   if (!isCounting) return;
  //   _stopRequested = true;
  //   currentStatus = '⛔ Stopping...';
  //   // Gene - Nov, 25, 2026: Stop native RustCountJob instead of Dart isolate.
  //   // _stopIsolate();
  //   _stopRustJob();
  //   _finishRun(wasStopped: true);
  //   notifyListeners();
  // }
  void stop() {
    if (!isCounting) return;
    _stopRequested = true;
    currentStatus = '⛔ Stopping...';
    _stopFallbackTimer?.cancel();

    final job = _rustJob;
    if (job == null) {
      _stopRustJob();
      _finishRun(wasStopped: true);
      notifyListeners();
      return;
    }

    job.stop();
    _stopFallbackTimer = Timer(const Duration(seconds: 2), () {
      if (_rustJob != null && isCounting) {
        _stopRustJob();
        _finishRun(wasStopped: true);
      }
    });
    notifyListeners();
  }

//   void clearLogs() {
//     logs.clear();
//     totalFiles = 0;
//     totalFolders = 0;
//     errors = 0;
//     currentStatus = 'Idle';
//     notifyListeners();
//   }
  // Gene - Nov, 26, 2026: Reset totalBytes and isSizeOnlyRun alongside counts when clearing logs.
  // void clearLogs() {
  //   logs.clear();
  //   totalFiles = 0;
  //   excludedFiles = 0;
  //   totalFolders = 0;
  //   errors = 0;
  //   currentStatus = 'Idle';
  //   notifyListeners();
  // }
  // Gene - Nov, 26, 2026: Reset activeRunMode and oldest/latest file date bounds in clearLogs.
  // void clearLogs() {
  //   logs.clear();
  //   totalFiles = 0;
  //   excludedFiles = 0;
  //   totalFolders = 0;
  //   totalBytes = 0;
  //   isSizeOnlyRun = false;
  //   errors = 0;
  //   currentStatus = 'Idle';
  //   notifyListeners();
  // }
  void clearLogs() {
    logs.clear();
    totalFiles = 0;
    excludedFiles = 0;
    totalFolders = 0;
    totalBytes = 0;
    activeRunMode = CountRunMode.count;
    oldestFileDate = null;
    oldestFilePath = null;
    latestFileDate = null;
    latestFilePath = null;
    errors = 0;
    currentStatus = 'Idle';
    notifyListeners();
  }

  // Gene - Nov, 25, 2026: Removed redundant _startTimer/_stopTimer; _pollTimer notifies listeners on change.
  // void _startTimer() {
  //   _refreshTimer?.cancel();
  //   _refreshTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
  //     notifyListeners();
  //   });
  // }
  //
  // void _stopTimer() {
  //   _refreshTimer?.cancel();
  //   _refreshTimer = null;
  //   notifyListeners();
  // }

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

  // Gene - Nov, 26, 2026: Added startFolderSize() and totalBytes tracking/logging for both Count and Get Folder Size runs.
  // Future<void> startCounting() async {
  //   if (isCounting) return;
  //
  //   if (targetPath == null) {
  //     _addLog('✗ Error: No target directory selected.');
  //     return;
  //   }
  //
  //   // Gene - Nov, 26, 2026: Require at least one file-type category and log filter selection.
  //   if (!hasAnyCategorySelected) {
  //     _addLog('✗ Error: Select at least one file type to count.');
  //     notifyListeners();
  //     return;
  //   }
  //
  //   isCounting = true;
  //   _stopRequested = false;
  //   totalFiles = 0;
  //   excludedFiles = 0;
  //   totalFolders = 0;
  //   errors = 0;
  //   // Gene - Nov, 25, 2026: Initialize Count status with live scanning file counter.
  //   // currentStatus = '⏳ Counting...';
  //   currentStatus = '⏳ Scanning (0 files)...';
  //   notifyListeners();
  //
  //   _addLog('⏳ Starting file count...');
  //   _addLog('  Target: $targetPath');
  //   _addLog('  Counting: $filterSummary');
  //   if (!allCategoriesSelected) {
  //     _addLog('  Excluding: $excludedSummary');
  //   }
  //
  //   await _fileLogger.logRunStart(operation: 'Count', targetPath: targetPath);
  //
  //   // _startTimer();
  //
  //   try {
  //     final targetDir = Directory(targetPath!);
  //     if (!await targetDir.exists()) {
  //       _addLog('✗ Error: Target directory does not exist.');
  //       await _fileLogger.error(
  //         'Count',
  //         'Target directory does not exist: $targetPath',
  //       );
  //       _finishRun(wasStopped: false);
  //       return;
  //     }
  //
  //     // Gene - Nov, 25, 2026: Run directory counting on native Rust count_engine instead of Dart isolate.
  //     _stopRustJob();
  //     // _rustJob = RustCountJob.start(
  //     //   targetPath: targetPath!,
  //     //   logInterval: logInterval,
  //     // );
  //     // Gene - Nov, 26, 2026: Pass selected category includeMask to native Rust count engine.
  //     _rustJob = RustCountJob.start(
  //       targetPath: targetPath!,
  //       logInterval: logInterval,
  //       includeMask: categoryIncludeMask,
  //     );
  //     // Gene - Nov, 25, 2026: Poll every 150ms instead of 100ms.
  //     // _pollTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
  //     _pollTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
  //       _pollRustJob();
  //     });
  //   } catch (e) {
  //     _addLog('✗ Critical Error: $e');
  //     await _fileLogger.error('Count', 'Critical Error: $e');
  //     // _stopIsolate();
  //     _stopRustJob();
  //     _finishRun(wasStopped: false);
  //   }
  // }
  //
  // // Gene - Nov, 25, 2026: Poll native Rust count_engine for live file/folder counts, logs, and completion.
  // void _pollRustJob() {
  //   final job = _rustJob;
  //   if (job == null || job.isDisposed) return;
  //
  //   try {
  //     final prevFiles = totalFiles;
  //     // Gene - Nov, 26, 2026: Track excludedFiles updates from Rust snapshot.
  //     final prevExcluded = excludedFiles;
  //     final prevFolders = totalFolders;
  //     final prevErrors = errors;
  //     final prevStatus = currentStatus;
  //
  //     final snap = job.poll();
  //     totalFiles = snap.files;
  //     excludedFiles = snap.excludedFiles;
  //     totalFolders = snap.folders;
  //     errors = snap.errors;
  //
  //     if (!snap.isDone && !_stopRequested) {
  //       currentStatus = snap.currentDirName.isEmpty
  //           ? '⏳ Scanning (${_numFmt.format(totalFiles)} files)...'
  //           : '⏳ Scanning (${_numFmt.format(totalFiles)} files): ${snap.currentDirName}';
  //     }
  //
  //     for (final log in snap.logs) {
  //       _addLog(log);
  //     }
  //
  //     for (final err in snap.errorLogs) {
  //       _addLog('✗ $err');
  //       _fileLogger.error('Count', err);
  //     }
  //
  //     if (snap.criticalError != null) {
  //       _addLog('✗ Critical Error: ${snap.criticalError}');
  //       _fileLogger.error('Count', 'Critical Error: ${snap.criticalError}');
  //     }
  //
  //     if (snap.isDone) {
  //       _stopRustJob();
  //       if (!_stopRequested) {
  //         _finishRun(wasStopped: false);
  //       }
  //       return;
  //     }
  //
  //     if (prevFiles != totalFiles ||
  //         prevExcluded != excludedFiles ||
  //         prevFolders != totalFolders ||
  //         prevErrors != errors ||
  //         prevStatus != currentStatus ||
  //         snap.logs.isNotEmpty ||
  //         snap.errorLogs.isNotEmpty ||
  //         snap.criticalError != null) {
  //       notifyListeners();
  //     }
  //   } catch (e) {
  //     _stopRustJob();
  //     _addLog('✗ Critical Error: $e');
  //     _fileLogger.error('Count', 'Critical Error: $e');
  //     _finishRun(wasStopped: false);
  //   }
  // }
  //
  // Future<void> _finishRun({required bool wasStopped}) async {
  //   final elapsed = _getElapsedStr();
  //   if (wasStopped) {
  //     _addLog('⛔ Stopped by user.');
  //     _addLog(
  //       '  Count so far — Files: ${_numFmt.format(totalFiles)}, Folders: ${_numFmt.format(totalFolders)} in $elapsed',
  //     );
  //     // Gene - Nov, 26, 2026: Log excluded files count when filtering is active.
  //     if (!allCategoriesSelected || excludedFiles > 0) {
  //       _addLog('  Excluded Files: ${_numFmt.format(excludedFiles)}');
  //     }
  //   } else {
  //     _addLog('🏁 Count completed in $elapsed');
  //     _addLog('  Total Files: ${_numFmt.format(totalFiles)}');
  //     if (!allCategoriesSelected || excludedFiles > 0) {
  //       _addLog('  Excluded Files: ${_numFmt.format(excludedFiles)}');
  //     }
  //     _addLog('  Total Folders: ${_numFmt.format(totalFolders)}');
  //   }
  //
  //   await _fileLogger.info('Count', 'Total Files: $totalFiles');
  //   if (!allCategoriesSelected || excludedFiles > 0) {
  //     await _fileLogger.info('Count', 'Excluded Files: $excludedFiles');
  //   }
  //   await _fileLogger.info('Count', 'Total Folders: $totalFolders');
  //   if (errors > 0) {
  //     await _fileLogger.error('Count', 'Errors encountered: $errors');
  //   }
  //
  //   // Capture before logRunEnd clears them
  //   final runId = _fileLogger.getRunId('Count') ?? 'UNKNOWN';
  //   final start = _fileLogger.getStartTime('Count') ?? DateTime.now();
  //
  //   await _fileLogger.logRunEnd(
  //     operation: 'Count',
  //     filesProcessed: totalFiles,
  //     errors: errors,
  //     wasStopped: wasStopped,
  //   );
  //
  //   try {
  //     await HistoryService().saveRecord(
  //       RunRecord(
  //         id: runId,
  //         operation: 'Count',
  //         startTime: start,
  //         endTime: DateTime.now(),
  //         filesProcessed: totalFiles,
  //         foldersProcessed: totalFolders,
  //         errors: errors,
  //         status: wasStopped
  //             ? 'Stopped'
  //             : (errors > 0 && totalFiles == 0 && totalFolders == 0
  //                   ? 'Error'
  //                   : 'Completed'),
  //         // configSummary: 'Target: $targetPath, Log Every: $logInterval',
  //         // Gene - Nov, 26, 2026: Include active file-type filter summary in Count run history.
  //         configSummary:
  //             'Target: $targetPath, Types: $filterSummary, Log Every: $logInterval',
  //         sourcePath: targetPath,
  //       ),
  //     );
  //   } catch (_) {}
  //
  //   isCounting = false;
  //   currentStatus = 'Idle';
  //   // _stopTimer();
  //   notifyListeners();
  // }

  // Gene - Nov, 26, 2026: Replaced isSizeOnlyRun boolean with CountRunMode and added startDateRangeCheck() + oldest/latest date tracking.
  // Future<void> startCounting() => _startRun(sizeOnly: false);
  //
  // Future<void> startFolderSize() => _startRun(sizeOnly: true);
  //
  // Future<void> _startRun({required bool sizeOnly}) async {
  //   if (isCounting) return;
  //
  //   if (targetPath == null) {
  //     _addLog('✗ Error: No target directory selected.');
  //     return;
  //   }
  //
  //   if (!sizeOnly && !hasAnyCategorySelected) {
  //     _addLog('✗ Error: Select at least one file type to count.');
  //     notifyListeners();
  //     return;
  //   }
  //
  //   isCounting = true;
  //   isSizeOnlyRun = sizeOnly;
  //   _stopRequested = false;
  //   totalFiles = 0;
  //   excludedFiles = 0;
  //   totalFolders = 0;
  //   totalBytes = 0;
  //   errors = 0;
  //   currentStatus = sizeOnly
  //       ? '⏳ Calculating size (0 B)...'
  //       : '⏳ Scanning (0 files)...';
  //   notifyListeners();
  //
  //   if (sizeOnly) {
  //     _addLog('⏳ Calculating folder size...');
  //     _addLog('  Target: $targetPath (all files)');
  //   } else {
  //     _addLog('⏳ Starting file count...');
  //     _addLog('  Target: $targetPath');
  //     _addLog('  Counting: $filterSummary');
  //     if (!allCategoriesSelected) {
  //       _addLog('  Excluding: $excludedSummary');
  //     }
  //   }
  //
  //   await _fileLogger.logRunStart(operation: 'Count', targetPath: targetPath);
  //
  //   try {
  //     final targetDir = Directory(targetPath!);
  //     if (!await targetDir.exists()) {
  //       _addLog('✗ Error: Target directory does not exist.');
  //       await _fileLogger.error(
  //         'Count',
  //         'Target directory does not exist: $targetPath',
  //       );
  //       _finishRun(wasStopped: false);
  //       return;
  //     }
  //
  //     _stopRustJob();
  //     _rustJob = RustCountJob.start(
  //       targetPath: targetPath!,
  //       logInterval: sizeOnly ? 0 : logInterval,
  //       includeMask: sizeOnly ? kCountCategoryAllMask : categoryIncludeMask,
  //       sizeOnly: sizeOnly,
  //     );
  //     _pollTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
  //       _pollRustJob();
  //     });
  //   } catch (e) {
  //     _addLog('✗ Critical Error: $e');
  //     await _fileLogger.error('Count', 'Critical Error: $e');
  //     _stopRustJob();
  //     _finishRun(wasStopped: false);
  //   }
  // }
  //
  // void _pollRustJob() {
  //   final job = _rustJob;
  //   if (job == null || job.isDisposed) return;
  //
  //   try {
  //     final prevFiles = totalFiles;
  //     final prevExcluded = excludedFiles;
  //     final prevFolders = totalFolders;
  //     final prevBytes = totalBytes;
  //     final prevErrors = errors;
  //     final prevStatus = currentStatus;
  //
  //     final snap = job.poll();
  //     totalFiles = snap.files;
  //     excludedFiles = snap.excludedFiles;
  //     totalFolders = snap.folders;
  //     totalBytes = snap.totalBytes;
  //     errors = snap.errors;
  //
  //     if (!snap.isDone && !_stopRequested) {
  //       if (isSizeOnlyRun) {
  //         currentStatus = snap.currentDirName.isEmpty
  //             ? '⏳ Calculating size ($formattedTotalSize)...'
  //             : '⏳ Calculating size ($formattedTotalSize): ${snap.currentDirName}';
  //       } else {
  //         currentStatus = snap.currentDirName.isEmpty
  //             ? '⏳ Scanning (${_numFmt.format(totalFiles)} files) • $formattedTotalSize...'
  //             : '⏳ Scanning (${_numFmt.format(totalFiles)} files) • $formattedTotalSize: ${snap.currentDirName}';
  //       }
  //     }
  //
  //     for (final log in snap.logs) {
  //       _addLog(log);
  //     }
  //
  //     for (final err in snap.errorLogs) {
  //       _addLog('✗ $err');
  //       _fileLogger.error('Count', err);
  //     }
  //
  //     if (snap.criticalError != null) {
  //       _addLog('✗ Critical Error: ${snap.criticalError}');
  //       _fileLogger.error('Count', 'Critical Error: ${snap.criticalError}');
  //     }
  //
  //     if (snap.isDone) {
  //       _stopRustJob();
  //       if (!_stopRequested) {
  //         _finishRun(wasStopped: false);
  //       }
  //       return;
  //     }
  //
  //     if (prevFiles != totalFiles ||
  //         prevExcluded != excludedFiles ||
  //         prevFolders != totalFolders ||
  //         prevBytes != totalBytes ||
  //         prevErrors != errors ||
  //         prevStatus != currentStatus ||
  //         snap.logs.isNotEmpty ||
  //         snap.errorLogs.isNotEmpty ||
  //         snap.criticalError != null) {
  //       notifyListeners();
  //     }
  //   } catch (e) {
  //     _stopRustJob();
  //     _addLog('✗ Critical Error: $e');
  //     _fileLogger.error('Count', 'Critical Error: $e');
  //     _finishRun(wasStopped: false);
  //   }
  // }
  //
  // Future<void> _finishRun({required bool wasStopped}) async {
  //   final elapsed = _getElapsedStr();
  //   final sizeStr = formattedTotalSize;
  //   final exactBytes = _numFmt.format(totalBytes);
  //
  //   if (wasStopped) {
  //     _addLog('⛔ Stopped by user.');
  //     _addLog(
  //       '  ${isSizeOnlyRun ? 'Size so far' : 'Count so far'} — Files: ${_numFmt.format(totalFiles)}, Folders: ${_numFmt.format(totalFolders)}, Size: $sizeStr in $elapsed',
  //     );
  //     if (!isSizeOnlyRun && (!allCategoriesSelected || excludedFiles > 0)) {
  //       _addLog('  Excluded Files: ${_numFmt.format(excludedFiles)}');
  //     }
  //   } else if (isSizeOnlyRun) {
  //     _addLog('🏁 Folder size calculated in $elapsed');
  //     _addLog('  Folder Size: $sizeStr ($exactBytes bytes)');
  //     _addLog('  Total Files: ${_numFmt.format(totalFiles)}');
  //     _addLog('  Total Folders: ${_numFmt.format(totalFolders)}');
  //   } else {
  //     _addLog('🏁 Count completed in $elapsed');
  //     _addLog('  Total Files: ${_numFmt.format(totalFiles)}');
  //     if (!allCategoriesSelected || excludedFiles > 0) {
  //       _addLog('  Excluded Files: ${_numFmt.format(excludedFiles)}');
  //     }
  //     _addLog('  Total Folders: ${_numFmt.format(totalFolders)}');
  //     _addLog('  Total Size: $sizeStr ($exactBytes bytes)');
  //   }
  //
  //   await _fileLogger.info('Count', 'Total Files: $totalFiles');
  //   if (!isSizeOnlyRun && (!allCategoriesSelected || excludedFiles > 0)) {
  //     await _fileLogger.info('Count', 'Excluded Files: $excludedFiles');
  //   }
  //   await _fileLogger.info('Count', 'Total Folders: $totalFolders');
  //   await _fileLogger.info('Count', 'Total Size: $sizeStr ($totalBytes bytes)');
  //   if (errors > 0) {
  //     await _fileLogger.error('Count', 'Errors encountered: $errors');
  //   }
  //
  //   // Capture before logRunEnd clears them
  //   final runId = _fileLogger.getRunId('Count') ?? 'UNKNOWN';
  //   final start = _fileLogger.getStartTime('Count') ?? DateTime.now();
  //
  //   await _fileLogger.logRunEnd(
  //     operation: 'Count',
  //     filesProcessed: totalFiles,
  //     errors: errors,
  //     wasStopped: wasStopped,
  //   );
  //
  //   try {
  //     await HistoryService().saveRecord(
  //       RunRecord(
  //         id: runId,
  //         operation: 'Count',
  //         startTime: start,
  //         endTime: DateTime.now(),
  //         filesProcessed: totalFiles,
  //         foldersProcessed: totalFolders,
  //         errors: errors,
  //         status: wasStopped
  //             ? 'Stopped'
  //             : (errors > 0 && totalFiles == 0 && totalFolders == 0
  //                   ? 'Error'
  //                   : 'Completed'),
  //         configSummary: isSizeOnlyRun
  //             ? 'Mode: Folder Size, Target: $targetPath, Size: $sizeStr'
  //             : 'Target: $targetPath, Types: $filterSummary, Size: $sizeStr, Log Every: $logInterval',
  //         sourcePath: targetPath,
  //       ),
  //     );
  //   } catch (_) {}
  //
  //   isCounting = false;
  //   currentStatus = 'Idle';
  //   notifyListeners();
  // }
  Future<void> startCounting() => _startRun(mode: CountRunMode.count);

  Future<void> startFolderSize() => _startRun(mode: CountRunMode.folderSize);

  Future<void> startDateRangeCheck() => _startRun(mode: CountRunMode.dateRange);

  Future<void> _startRun({required CountRunMode mode}) async {
    if (isCounting) return;

    if (targetPath == null) {
      _addLog('✗ Error: No target directory selected.');
      return;
    }

    if (mode == CountRunMode.count && !hasAnyCategorySelected) {
      _addLog('✗ Error: Select at least one file type to count.');
      notifyListeners();
      return;
    }

    final isFastFullScan = mode != CountRunMode.count;
    isCounting = true;
    activeRunMode = mode;
    _stopRequested = false;
    totalFiles = 0;
    excludedFiles = 0;
    totalFolders = 0;
    totalBytes = 0;
    oldestFileDate = null;
    oldestFilePath = null;
    latestFileDate = null;
    latestFilePath = null;
    errors = 0;
    switch (mode) {
      case CountRunMode.folderSize:
        currentStatus = '⏳ Calculating size (0 B)...';
      case CountRunMode.dateRange:
        currentStatus = '⏳ Checking date range (0 files)...';
      case CountRunMode.count:
        currentStatus = '⏳ Scanning (0 files)...';
    }
    notifyListeners();

    switch (mode) {
      case CountRunMode.folderSize:
        _addLog('⏳ Calculating folder size...');
        _addLog('  Target: $targetPath (all files)');
      case CountRunMode.dateRange:
        _addLog('⏳ Checking file date range (oldest & latest)...');
        _addLog('  Target: $targetPath (all files)');
      case CountRunMode.count:
        _addLog('⏳ Starting file count...');
        _addLog('  Target: $targetPath');
        _addLog('  Counting: $filterSummary');
        if (!allCategoriesSelected) {
          _addLog('  Excluding: $excludedSummary');
        }
    }

    await _fileLogger.logRunStart(operation: 'Count', targetPath: targetPath);

    try {
      final targetDir = Directory(targetPath!);
      if (!await targetDir.exists()) {
        _addLog('✗ Error: Target directory does not exist.');
        await _fileLogger.error(
          'Count',
          'Target directory does not exist: $targetPath',
        );
        _finishRun(wasStopped: false);
        return;
      }

      _stopRustJob();
      _rustJob = RustCountJob.start(
        targetPath: targetPath!,
        logInterval: isFastFullScan ? 0 : logInterval,
        includeMask: isFastFullScan
            ? kCountCategoryAllMask
            : categoryIncludeMask,
        sizeOnly: isFastFullScan,
      );
      _pollTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
        _pollRustJob();
      });
    } catch (e) {
      _addLog('✗ Critical Error: $e');
      await _fileLogger.error('Count', 'Critical Error: $e');
      _stopRustJob();
      _finishRun(wasStopped: false);
    }
  }

  void _pollRustJob() {
    final job = _rustJob;
    if (job == null || job.isDisposed) return;

    try {
      final prevFiles = totalFiles;
      final prevExcluded = excludedFiles;
      final prevFolders = totalFolders;
      final prevBytes = totalBytes;
      final prevOldestMs = oldestFileDate?.millisecondsSinceEpoch;
      final prevOldestPath = oldestFilePath;
      final prevLatestMs = latestFileDate?.millisecondsSinceEpoch;
      final prevLatestPath = latestFilePath;
      final prevErrors = errors;
      final prevStatus = currentStatus;

      final snap = job.poll();
      totalFiles = snap.files;
      excludedFiles = snap.excludedFiles;
      totalFolders = snap.folders;
      totalBytes = snap.totalBytes;
      oldestFileDate = snap.oldestFileMs != null
          ? DateTime.fromMillisecondsSinceEpoch(snap.oldestFileMs!)
          : null;
      oldestFilePath = snap.oldestFilePath;
      latestFileDate = snap.latestFileMs != null
          ? DateTime.fromMillisecondsSinceEpoch(snap.latestFileMs!)
          : null;
      latestFilePath = snap.latestFilePath;
      errors = snap.errors;

      if (!snap.isDone && !_stopRequested) {
        switch (activeRunMode) {
          case CountRunMode.folderSize:
            currentStatus = snap.currentDirName.isEmpty
                ? '⏳ Calculating size ($formattedTotalSize)...'
                : '⏳ Calculating size ($formattedTotalSize): ${snap.currentDirName}';
          case CountRunMode.dateRange:
            if (hasDateRange) {
              currentStatus = snap.currentDirName.isEmpty
                  ? '⏳ Checking dates ($formattedDateRange)...'
                  : '⏳ Checking dates ($formattedDateRange): ${snap.currentDirName}';
            } else {
              currentStatus = snap.currentDirName.isEmpty
                  ? '⏳ Checking date range (${_numFmt.format(totalFiles)} files)...'
                  : '⏳ Checking date range (${_numFmt.format(totalFiles)} files): ${snap.currentDirName}';
            }
          case CountRunMode.count:
            currentStatus = snap.currentDirName.isEmpty
                ? '⏳ Scanning (${_numFmt.format(totalFiles)} files) • $formattedTotalSize...'
                : '⏳ Scanning (${_numFmt.format(totalFiles)} files) • $formattedTotalSize: ${snap.currentDirName}';
        }
      }

      for (final log in snap.logs) {
        _addLog(log);
      }

      for (final err in snap.errorLogs) {
        _addLog('✗ $err');
        _fileLogger.error('Count', err);
      }

      if (snap.criticalError != null) {
        _addLog('✗ Critical Error: ${snap.criticalError}');
        _fileLogger.error('Count', 'Critical Error: ${snap.criticalError}');
      }

      // Gene - Nov, 26, 2026: Finish run with wasStopped: _stopRequested so graceful stop drains final stats.
      // if (snap.isDone) {
      //   _stopRustJob();
      //   if (!_stopRequested) {
      //     _finishRun(wasStopped: false);
      //   }
      //   return;
      // }
      if (snap.isDone) {
        _stopRustJob();
        _finishRun(wasStopped: _stopRequested);
        return;
      }

      if (prevFiles != totalFiles ||
          prevExcluded != excludedFiles ||
          prevFolders != totalFolders ||
          prevBytes != totalBytes ||
          prevOldestMs != oldestFileDate?.millisecondsSinceEpoch ||
          prevOldestPath != oldestFilePath ||
          prevLatestMs != latestFileDate?.millisecondsSinceEpoch ||
          prevLatestPath != latestFilePath ||
          prevErrors != errors ||
          prevStatus != currentStatus ||
          snap.logs.isNotEmpty ||
          snap.errorLogs.isNotEmpty ||
          snap.criticalError != null) {
        notifyListeners();
      }
    } catch (e) {
      _stopRustJob();
      _addLog('✗ Critical Error: $e');
      _fileLogger.error('Count', 'Critical Error: $e');
      _finishRun(wasStopped: false);
    }
  }

  Future<void> _finishRun({required bool wasStopped}) async {
    final elapsed = _getElapsedStr();
    final sizeStr = formattedTotalSize;
    final exactBytes = _numFmt.format(totalBytes);

    if (wasStopped) {
      _addLog('⛔ Stopped by user.');
      final modeLabel = switch (activeRunMode) {
        CountRunMode.folderSize => 'Size so far',
        CountRunMode.dateRange => 'Date check so far',
        CountRunMode.count => 'Count so far',
      };
      _addLog(
        '  $modeLabel — Files: ${_numFmt.format(totalFiles)}, Folders: ${_numFmt.format(totalFolders)}, Size: $sizeStr in $elapsed',
      );
      if (activeRunMode == CountRunMode.count &&
          (!allCategoriesSelected || excludedFiles > 0)) {
        _addLog('  Excluded Files: ${_numFmt.format(excludedFiles)}');
      }
      if (hasDateRange) {
        _addLog('  Date Range (Modified): $formattedDateRange');
        _addLog('  Oldest File: $formattedOldestDate — ${oldestFilePath ?? ''}');
        _addLog('  Latest File: $formattedLatestDate — ${latestFilePath ?? ''}');
      }
    } else if (activeRunMode == CountRunMode.dateRange) {
      _addLog('🏁 Date range checked in $elapsed');
      if (hasDateRange) {
        _addLog('  Date Range (Modified): $formattedDateRange');
        _addLog('  Oldest File: $formattedOldestDate — ${oldestFilePath ?? ''}');
        _addLog('  Latest File: $formattedLatestDate — ${latestFilePath ?? ''}');
      } else {
        _addLog('  Date Range (Modified): No files found');
      }
      _addLog('  Total Files: ${_numFmt.format(totalFiles)}');
      _addLog('  Total Folders: ${_numFmt.format(totalFolders)}');
      _addLog('  Total Size: $sizeStr ($exactBytes bytes)');
    } else if (activeRunMode == CountRunMode.folderSize) {
      _addLog('🏁 Folder size calculated in $elapsed');
      _addLog('  Folder Size: $sizeStr ($exactBytes bytes)');
      _addLog('  Total Files: ${_numFmt.format(totalFiles)}');
      _addLog('  Total Folders: ${_numFmt.format(totalFolders)}');
      if (hasDateRange) {
        _addLog('  Date Range (Modified): $formattedDateRange');
        _addLog('  Oldest File: $formattedOldestDate — ${oldestFilePath ?? ''}');
        _addLog('  Latest File: $formattedLatestDate — ${latestFilePath ?? ''}');
      }
    } else {
      _addLog('🏁 Count completed in $elapsed');
      _addLog('  Total Files: ${_numFmt.format(totalFiles)}');
      if (!allCategoriesSelected || excludedFiles > 0) {
        _addLog('  Excluded Files: ${_numFmt.format(excludedFiles)}');
      }
      _addLog('  Total Folders: ${_numFmt.format(totalFolders)}');
      _addLog('  Total Size: $sizeStr ($exactBytes bytes)');
      if (hasDateRange) {
        _addLog('  Date Range (Modified): $formattedDateRange');
        _addLog('  Oldest File: $formattedOldestDate — ${oldestFilePath ?? ''}');
        _addLog('  Latest File: $formattedLatestDate — ${latestFilePath ?? ''}');
      }
    }

    await _fileLogger.info('Count', 'Total Files: $totalFiles');
    if (activeRunMode == CountRunMode.count &&
        (!allCategoriesSelected || excludedFiles > 0)) {
      await _fileLogger.info('Count', 'Excluded Files: $excludedFiles');
    }
    await _fileLogger.info('Count', 'Total Folders: $totalFolders');
    await _fileLogger.info('Count', 'Total Size: $sizeStr ($totalBytes bytes)');
    if (hasDateRange) {
      await _fileLogger.info('Count', 'Date Range (Modified): $formattedDateRange');
      await _fileLogger.info(
        'Count',
        'Oldest File: $formattedOldestDate — ${oldestFilePath ?? ''}',
      );
      await _fileLogger.info(
        'Count',
        'Latest File: $formattedLatestDate — ${latestFilePath ?? ''}',
      );
    }
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

    final historyConfigSummary = switch (activeRunMode) {
      CountRunMode.dateRange =>
        'Mode: Date Range, Target: $targetPath, Range: ${hasDateRange ? formattedDateRange : 'None'}',
      CountRunMode.folderSize =>
        'Mode: Folder Size, Target: $targetPath, Size: $sizeStr',
      CountRunMode.count =>
        'Target: $targetPath, Types: $filterSummary, Size: $sizeStr, Log Every: $logInterval${hasDateRange ? ', Range: $formattedDateRange' : ''}',
    };

    try {
      await HistoryService().saveRecord(
        RunRecord(
          id: runId,
          operation: 'Count',
          startTime: start,
          endTime: DateTime.now(),
          filesProcessed: totalFiles,
          foldersProcessed: totalFolders,
          errors: errors,
          status: wasStopped
              ? 'Stopped'
              : (errors > 0 && totalFiles == 0 && totalFolders == 0
                    ? 'Error'
                    : 'Completed'),
          configSummary: historyConfigSummary,
          sourcePath: targetPath,
        ),
      );
    } catch (_) {}

    isCounting = false;
    currentStatus = 'Idle';
    notifyListeners();
  }

  // Gene - Nov, 25, 2026: Commented out Dart isolate worker after migrating Count to Rust count_engine.
  // static Future<void> _isolateWorker(_CountParams params) async {
  //   int files = 0;
  //   int folders = 0;
  //   int errors = 0;
  //   List<String> logBatch = [];
  //   final Set<String> visitedPaths = {};
  //
  //   void sendProgress(String? currentScanPath, {bool force = false}) {
  //     if (force ||
  //         logBatch.isNotEmpty ||
  //         files % 100 == 0 ||
  //         folders % 10 == 0) {
  //       params.sendPort.send(
  //         _CountProgress(
  //           files: files,
  //           folders: folders,
  //           errors: errors,
  //           logs: List.from(logBatch),
  //           currentScanPath: currentScanPath,
  //         ),
  //       );
  //       logBatch.clear();
  //     }
  //   }
  //
  //   Future<void> countDir(Directory dir) async {
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
  //         if (entity is File) {
  //           files++;
  //           if (params.logInterval == 1) {
  //             logBatch.add('✓ Counted: ${p.basename(entity.path)}');
  //           } else if (files % params.logInterval == 0) {
  //             logBatch.add(
  //               '✓ Counted ${params.logInterval} files (total: $files) – latest: ${p.basename(entity.path)}',
  //             );
  //           }
  //           sendProgress(entity.path);
  //         } else if (entity is Directory) {
  //           folders++;
  //           sendProgress(entity.path);
  //           await countDir(entity);
  //         } else if (entity is Link) {
  //           try {
  //             if (!await resolvesWithinRoot(params.targetPath, entity.path)) {
  //               continue;
  //             }
  //             final targetType = await FileSystemEntity.type(entity.path);
  //             if (targetType == FileSystemEntityType.directory) {
  //               folders++;
  //               sendProgress(entity.path);
  //               await countDir(Directory(entity.path));
  //             } else if (targetType == FileSystemEntityType.file) {
  //               files++;
  //               sendProgress(entity.path);
  //             }
  //           } catch (_) {}
  //         }
  //       }
  //     } catch (e) {
  //       errors++;
  //       params.sendPort.send(
  //         _CountProgress(
  //           files: files,
  //           folders: folders,
  //           errors: errors,
  //           errorLog: 'Error accessing: ${dir.path} — $e',
  //         ),
  //       );
  //     }
  //   }
  //
  //   try {
  //     await countDir(Directory(params.targetPath));
  //     sendProgress(null, force: true);
  //     params.sendPort.send(
  //       _CountProgress(
  //         files: files,
  //         folders: folders,
  //         errors: errors,
  //         isDone: true,
  //       ),
  //     );
  //   } catch (e) {
  //     params.sendPort.send(
  //       _CountProgress(
  //         errorLog: 'Critical Error: $e',
  //         isDone: true,
  //         files: files,
  //         folders: folders,
  //         errors: errors,
  //       ),
  //     );
  //   }
  // }
}
