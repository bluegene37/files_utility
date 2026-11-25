// Gene - Nov, 25, 2026: High-level Dart wrappers for Rust Copy, Count, Delete, FTP scanner, and file creation time.
import 'dart:convert';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'rust_transfer_bindings.dart';

const int _kInvalidCreationMs = -9223372036854775808;

List<String> _decodeStringList(dynamic raw) {
  if (raw is! List) return const <String>[];
  return raw.map((e) => e.toString()).toList();
}

// ---------------------------------------------------------------------------
// Copy Engine
// ---------------------------------------------------------------------------

class RustCopySnapshot {
  final int filesCopied;
  final int filesSkipped;
  final int filesAlreadyExist;
  final int errors;
  final int filesInspected;
  final int dirsSkipped;
  final int phase;
  final String currentDirName;
  final String latestCopiedName;
  final bool isDone;
  final String? criticalError;
  final List<String> logs;
  final List<String> errorLogs;

  const RustCopySnapshot({
    required this.filesCopied,
    required this.filesSkipped,
    required this.filesAlreadyExist,
    required this.errors,
    required this.filesInspected,
    required this.dirsSkipped,
    required this.phase,
    required this.currentDirName,
    required this.latestCopiedName,
    required this.isDone,
    required this.criticalError,
    required this.logs,
    required this.errorLogs,
  });

  factory RustCopySnapshot.fromJson(Map<String, dynamic> json) {
    return RustCopySnapshot(
      filesCopied: (json['filesCopied'] as num?)?.toInt() ?? 0,
      filesSkipped: (json['filesSkipped'] as num?)?.toInt() ?? 0,
      filesAlreadyExist: (json['filesAlreadyExist'] as num?)?.toInt() ?? 0,
      errors: (json['errors'] as num?)?.toInt() ?? 0,
      filesInspected: (json['filesInspected'] as num?)?.toInt() ?? 0,
      dirsSkipped: (json['dirsSkipped'] as num?)?.toInt() ?? 0,
      phase: (json['phase'] as num?)?.toInt() ?? 1,
      currentDirName: json['currentDirName'] as String? ?? '',
      latestCopiedName: json['latestCopiedName'] as String? ?? '',
      isDone: json['isDone'] as bool? ?? false,
      criticalError: json['criticalError'] as String?,
      logs: _decodeStringList(json['logs']),
      errorLogs: _decodeStringList(json['errorLogs']),
    );
  }
}

class RustCopyJob {
  Pointer<Void>? _handle;
  bool _disposed = false;

  RustCopyJob._(this._handle);

  static RustCopyJob start({
    required String sourcePath,
    required String destPath,
    String? progressFilePath,
    Set<String> completedDirs = const {},
    Map<String, String> lastProcessedFiles = const {},
    required bool enableAgeFilter,
    required int ageThresholdEpochMs,
    required bool enableDateRange,
    required int fromInclusiveEpochMs,
    required int toExclusiveEpochMs,
    int initialCopied = 0,
    int initialSkipped = 0,
    int initialAlreadyExist = 0,
    int initialErrors = 0,
    int initialInspected = 0,
    int logInterval = 100,
  }) {
    final cfg = calloc<CopyConfigC>();
    final srcPtr = sourcePath.toNativeUtf8();
    final dstPtr = destPath.toNativeUtf8();
    final progressPtr =
        (progressFilePath != null && progressFilePath.isNotEmpty)
        ? progressFilePath.toNativeUtf8()
        : nullptr;
    final completedSerialized = completedDirs.join('\n');
    final completedPtr = completedSerialized.isNotEmpty
        ? completedSerialized.toNativeUtf8()
        : nullptr;
    final lastProcSerialized = lastProcessedFiles.entries
        .map((e) => '${e.key}\t${e.value}')
        .join('\n');
    final lastProcPtr = lastProcSerialized.isNotEmpty
        ? lastProcSerialized.toNativeUtf8()
        : nullptr;

    try {
      cfg.ref.sourcePath = srcPtr;
      cfg.ref.destPath = dstPtr;
      cfg.ref.progressFilePath = progressPtr;
      cfg.ref.completedDirsSerialized = completedPtr;
      cfg.ref.lastProcessedSerialized = lastProcPtr;
      cfg.ref.enableAgeFilter = enableAgeFilter ? 1 : 0;
      cfg.ref.ageThresholdEpochMs = ageThresholdEpochMs;
      cfg.ref.enableDateRange = enableDateRange ? 1 : 0;
      cfg.ref.fromInclusiveEpochMs = fromInclusiveEpochMs;
      cfg.ref.toExclusiveEpochMs = toExclusiveEpochMs;
      cfg.ref.initialCopied = initialCopied;
      cfg.ref.initialSkipped = initialSkipped;
      cfg.ref.initialAlreadyExist = initialAlreadyExist;
      cfg.ref.initialErrors = initialErrors;
      cfg.ref.initialInspected = initialInspected;
      cfg.ref.logInterval = logInterval <= 0 ? 100 : logInterval;

      final handle = copyEngineStart(cfg);
      if (handle == nullptr) {
        throw StateError('Failed to start native Rust copy engine');
      }
      return RustCopyJob._(handle);
    } finally {
      calloc.free(srcPtr);
      calloc.free(dstPtr);
      if (progressPtr != nullptr) calloc.free(progressPtr);
      if (completedPtr != nullptr) calloc.free(completedPtr);
      if (lastProcPtr != nullptr) calloc.free(lastProcPtr);
      calloc.free(cfg);
    }
  }

  bool get isDisposed => _disposed;

  RustCopySnapshot poll() {
    final handle = _handle;
    if (_disposed || handle == null || handle == nullptr) {
      throw StateError('RustCopyJob has been disposed');
    }
    final jsonPtr = copyEnginePoll(handle);
    if (jsonPtr == nullptr) {
      throw StateError('copy_engine_poll returned null');
    }
    try {
      final decoded =
          jsonDecode(jsonPtr.toDartString()) as Map<String, dynamic>;
      return RustCopySnapshot.fromJson(decoded);
    } finally {
      transferEngineFreeString(jsonPtr);
    }
  }

  void pause() {
    final handle = _handle;
    if (!_disposed && handle != null && handle != nullptr) {
      copyEnginePause(handle);
    }
  }

  void resume() {
    final handle = _handle;
    if (!_disposed && handle != null && handle != nullptr) {
      copyEngineResume(handle);
    }
  }

  void stop() {
    final handle = _handle;
    if (!_disposed && handle != null && handle != nullptr) {
      copyEngineStop(handle);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final handle = _handle;
    _handle = null;
    if (handle != null && handle != nullptr) {
      copyEngineDestroy(handle);
    }
  }
}

// ---------------------------------------------------------------------------
// Count Engine
// ---------------------------------------------------------------------------

// Gene - Nov, 26, 2026: Default bitmask including all 6 file-type categories in Rust count engine.
const int kCountCategoryAllMask = 0x3F;

// class RustCountSnapshot {
//   final int files;
//   final int folders;
//   final int errors;
//   final String currentDirName;
//   final bool isDone;
//   final String? criticalError;
//   final List<String> logs;
//   final List<String> errorLogs;
//
//   const RustCountSnapshot({
//     required this.files,
//     required this.folders,
//     required this.errors,
//     required this.currentDirName,
//     required this.isDone,
//     required this.criticalError,
//     required this.logs,
//     required this.errorLogs,
//   });
//
//   factory RustCountSnapshot.fromJson(Map<String, dynamic> json) {
//     return RustCountSnapshot(
//       files: (json['files'] as num?)?.toInt() ?? 0,
//       folders: (json['folders'] as num?)?.toInt() ?? 0,
//       errors: (json['errors'] as num?)?.toInt() ?? 0,
//       currentDirName: json['currentDirName'] as String? ?? '',
//       isDone: json['isDone'] as bool? ?? false,
//       criticalError: json['criticalError'] as String?,
//       logs: _decodeStringList(json['logs']),
//       errorLogs: _decodeStringList(json['errorLogs']),
//     );
//   }
// }
// Gene - Nov, 26, 2026: Added excludedFiles count to RustCountSnapshot and includeMask to RustCountJob.start.
class RustCountSnapshot {
  final int files;
  final int excludedFiles;
  final int folders;
  final int errors;
  final String currentDirName;
  final bool isDone;
  final String? criticalError;
  final List<String> logs;
  final List<String> errorLogs;

  const RustCountSnapshot({
    required this.files,
    this.excludedFiles = 0,
    required this.folders,
    required this.errors,
    required this.currentDirName,
    required this.isDone,
    required this.criticalError,
    required this.logs,
    required this.errorLogs,
  });

  factory RustCountSnapshot.fromJson(Map<String, dynamic> json) {
    return RustCountSnapshot(
      files: (json['files'] as num?)?.toInt() ?? 0,
      excludedFiles: (json['excludedFiles'] as num?)?.toInt() ?? 0,
      folders: (json['folders'] as num?)?.toInt() ?? 0,
      errors: (json['errors'] as num?)?.toInt() ?? 0,
      currentDirName: json['currentDirName'] as String? ?? '',
      isDone: json['isDone'] as bool? ?? false,
      criticalError: json['criticalError'] as String?,
      logs: _decodeStringList(json['logs']),
      errorLogs: _decodeStringList(json['errorLogs']),
    );
  }
}

class RustCountJob {
  Pointer<Void>? _handle;
  bool _disposed = false;

  RustCountJob._(this._handle);

  // static RustCountJob start({
  //   required String targetPath,
  //   int logInterval = 100,
  // }) {
  //   final cfg = calloc<CountConfigC>();
  //   final targetPtr = targetPath.toNativeUtf8();
  //   try {
  //     cfg.ref.targetPath = targetPtr;
  //     cfg.ref.logInterval = logInterval <= 0 ? 100 : logInterval;
  static RustCountJob start({
    required String targetPath,
    int logInterval = 100,
    int includeMask = kCountCategoryAllMask,
  }) {
    final cfg = calloc<CountConfigC>();
    final targetPtr = targetPath.toNativeUtf8();
    try {
      cfg.ref.targetPath = targetPtr;
      cfg.ref.logInterval = logInterval <= 0 ? 100 : logInterval;
      cfg.ref.includeMask = includeMask;

      final handle = countEngineStart(cfg);
      if (handle == nullptr) {
        throw StateError('Failed to start native Rust count engine');
      }
      return RustCountJob._(handle);
    } finally {
      calloc.free(targetPtr);
      calloc.free(cfg);
    }
  }

  bool get isDisposed => _disposed;

  RustCountSnapshot poll() {
    final handle = _handle;
    if (_disposed || handle == null || handle == nullptr) {
      throw StateError('RustCountJob has been disposed');
    }
    final jsonPtr = countEnginePoll(handle);
    if (jsonPtr == nullptr) {
      throw StateError('count_engine_poll returned null');
    }
    try {
      final decoded =
          jsonDecode(jsonPtr.toDartString()) as Map<String, dynamic>;
      return RustCountSnapshot.fromJson(decoded);
    } finally {
      transferEngineFreeString(jsonPtr);
    }
  }

  void stop() {
    final handle = _handle;
    if (!_disposed && handle != null && handle != nullptr) {
      countEngineStop(handle);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final handle = _handle;
    _handle = null;
    if (handle != null && handle != nullptr) {
      countEngineDestroy(handle);
    }
  }
}

// ---------------------------------------------------------------------------
// Delete Engine
// ---------------------------------------------------------------------------

List<int> buildLocalYearMonthRanges(
  int selectedYear,
  List<String> validMonths,
) {
  const monthNames = [
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
  final validSet = validMonths.toSet();
  final flat = <int>[];
  if (validSet.isEmpty || selectedYear < 1900) return flat;

  for (int year = 1900; year <= selectedYear; year++) {
    for (int month = 1; month <= 12; month++) {
      if (!validSet.contains(monthNames[month - 1])) continue;
      final startMs = DateTime(year, month, 1).millisecondsSinceEpoch;
      final endMs = DateTime(year, month + 1, 1).millisecondsSinceEpoch;
      if (flat.length >= 2 && flat.last == startMs) {
        flat[flat.length - 1] = endMs;
      } else {
        flat.add(startMs);
        flat.add(endMs);
      }
    }
  }
  return flat;
}

class RustDeleteSnapshot {
  final int filesScanned;
  final int deleted;
  final int errors;
  final String currentDirName;
  final bool isDone;
  final String? criticalError;
  final List<String> logs;
  final List<String> errorLogs;

  const RustDeleteSnapshot({
    required this.filesScanned,
    required this.deleted,
    required this.errors,
    required this.currentDirName,
    required this.isDone,
    required this.criticalError,
    required this.logs,
    required this.errorLogs,
  });

  factory RustDeleteSnapshot.fromJson(Map<String, dynamic> json) {
    return RustDeleteSnapshot(
      filesScanned: (json['filesScanned'] as num?)?.toInt() ?? 0,
      deleted: (json['deleted'] as num?)?.toInt() ?? 0,
      errors: (json['errors'] as num?)?.toInt() ?? 0,
      currentDirName: json['currentDirName'] as String? ?? '',
      isDone: json['isDone'] as bool? ?? false,
      criticalError: json['criticalError'] as String?,
      logs: _decodeStringList(json['logs']),
      errorLogs: _decodeStringList(json['errorLogs']),
    );
  }
}

class RustDeleteJob {
  Pointer<Void>? _handle;
  bool _disposed = false;

  RustDeleteJob._(this._handle);

  static RustDeleteJob start({
    required String targetPath,
    required int selectedYear,
    required List<String> validMonths,
    int logInterval = 100,
  }) {
    final flatRanges = buildLocalYearMonthRanges(selectedYear, validMonths);
    final pairCount = flatRanges.length ~/ 2;
    final cfg = calloc<DeleteConfigC>();
    final targetPtr = targetPath.toNativeUtf8();
    final rangesPtr = flatRanges.isNotEmpty
        ? calloc<Int64>(flatRanges.length)
        : nullptr;
    if (rangesPtr != nullptr) {
      for (int i = 0; i < flatRanges.length; i++) {
        rangesPtr[i] = flatRanges[i];
      }
    }

    try {
      cfg.ref.targetPath = targetPtr;
      cfg.ref.logInterval = logInterval <= 0 ? 100 : logInterval;
      cfg.ref.rangesPtr = rangesPtr;
      cfg.ref.rangesLen = pairCount;

      final handle = deleteEngineStart(cfg);
      if (handle == nullptr) {
        throw StateError('Failed to start native Rust delete engine');
      }
      return RustDeleteJob._(handle);
    } finally {
      calloc.free(targetPtr);
      if (rangesPtr != nullptr) calloc.free(rangesPtr);
      calloc.free(cfg);
    }
  }

  bool get isDisposed => _disposed;

  RustDeleteSnapshot poll() {
    final handle = _handle;
    if (_disposed || handle == null || handle == nullptr) {
      throw StateError('RustDeleteJob has been disposed');
    }
    final jsonPtr = deleteEnginePoll(handle);
    if (jsonPtr == nullptr) {
      throw StateError('delete_engine_poll returned null');
    }
    try {
      final decoded =
          jsonDecode(jsonPtr.toDartString()) as Map<String, dynamic>;
      return RustDeleteSnapshot.fromJson(decoded);
    } finally {
      transferEngineFreeString(jsonPtr);
    }
  }

  void stop() {
    final handle = _handle;
    if (!_disposed && handle != null && handle != nullptr) {
      deleteEngineStop(handle);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final handle = _handle;
    _handle = null;
    if (handle != null && handle != nullptr) {
      deleteEngineDestroy(handle);
    }
  }
}

// ---------------------------------------------------------------------------
// FTP Local Scanner & Native File Creation Time
// ---------------------------------------------------------------------------

class RustFtpScannedFile {
  final String path;
  final int size;
  final DateTime modified;
  final DateTime created;

  const RustFtpScannedFile({
    required this.path,
    required this.size,
    required this.modified,
    required this.created,
  });
}

class RustFtpScanResult {
  final List<RustFtpScannedFile> files;
  final List<String> errors;

  const RustFtpScanResult({required this.files, required this.errors});
}

class RustFtpScanner {
  static Future<RustFtpScanResult> scanDirectoryAsync({
    required String dirPath,
    required String rootPath,
    required bool includeCreationTime,
    bool Function()? isCancelled,
  }) async {
    final dirPtr = dirPath.toNativeUtf8();
    final rootPtr = rootPath.toNativeUtf8();
    Pointer<Void> job = nullptr;
    try {
      job = ftpScanStart(dirPtr, rootPtr, includeCreationTime ? 1 : 0);
    } finally {
      calloc.free(dirPtr);
      calloc.free(rootPtr);
    }

    if (job == nullptr) {
      throw StateError('Failed to start native Rust FTP directory scan');
    }

    try {
      while (true) {
        if (isCancelled != null && isCancelled()) {
          return const RustFtpScanResult(files: [], errors: []);
        }
        final jsonPtr = ftpScanPoll(job);
        if (jsonPtr != nullptr) {
          try {
            final decoded =
                jsonDecode(jsonPtr.toDartString()) as Map<String, dynamic>;
            final rawFiles = decoded['files'] as List? ?? const [];
            final parsedFiles = rawFiles.map((raw) {
              final m = raw as Map<String, dynamic>;
              final modMs = (m['modifiedMs'] as num?)?.toInt() ?? 0;
              final creMs = (m['createdMs'] as num?)?.toInt() ?? modMs;
              return RustFtpScannedFile(
                path: m['path'] as String? ?? '',
                size: (m['size'] as num?)?.toInt() ?? 0,
                modified: DateTime.fromMillisecondsSinceEpoch(modMs),
                created: DateTime.fromMillisecondsSinceEpoch(creMs),
              );
            }).toList();
            return RustFtpScanResult(
              files: parsedFiles,
              errors: _decodeStringList(decoded['errors']),
            );
          } finally {
            transferEngineFreeString(jsonPtr);
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 15));
      }
    } finally {
      ftpScanDestroy(job);
    }
  }
}

DateTime? nativeFileCreationDate(String path) {
  final pathPtr = path.toNativeUtf8();
  try {
    final ms = nativeFileCreationMs(pathPtr);
    if (ms == _kInvalidCreationMs) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  } finally {
    calloc.free(pathPtr);
  }
}
