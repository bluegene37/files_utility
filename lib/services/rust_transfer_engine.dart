// Gene - Nov, 25, 2026: High-level Dart wrapper managing the native Rust transfer_engine job lifecycle.
import 'dart:convert';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'rust_transfer_bindings.dart';

class RustTransferSnapshot {
  final int filesScanned;
  final int dirsScanned;
  final int filesMoved;
  final int errors;
  final int phase;
  final String currentDirName;
  final String? saveScannedDir;
  final List<String> logs;
  final bool isDone;
  final String? criticalError;

  const RustTransferSnapshot({
    required this.filesScanned,
    required this.dirsScanned,
    required this.filesMoved,
    required this.errors,
    required this.phase,
    required this.currentDirName,
    required this.saveScannedDir,
    required this.logs,
    required this.isDone,
    required this.criticalError,
  });

  factory RustTransferSnapshot.fromJson(Map<String, dynamic> json) {
    final rawLogs = json['logs'];
    final parsedLogs = rawLogs is List
        ? rawLogs.map((e) => e.toString()).toList()
        : const <String>[];
    return RustTransferSnapshot(
      filesScanned: (json['filesScanned'] as num?)?.toInt() ?? 0,
      dirsScanned: (json['dirsScanned'] as num?)?.toInt() ?? 0,
      filesMoved: (json['filesMoved'] as num?)?.toInt() ?? 0,
      errors: (json['errors'] as num?)?.toInt() ?? 0,
      phase: (json['phase'] as num?)?.toInt() ?? 0,
      currentDirName: json['currentDirName'] as String? ?? '',
      saveScannedDir: json['saveScannedDir'] as String?,
      logs: parsedLogs,
      isDone: json['isDone'] as bool? ?? false,
      criticalError: json['criticalError'] as String?,
    );
  }
}

class RustTransferJob {
  Pointer<Void>? _handle;
  bool _disposed = false;

  RustTransferJob._(this._handle);

  static RustTransferJob start({
    required String sourcePath,
    required String destPath,
    String? lastScannedDir,
    required bool enableAgeFilter,
    required int ageThresholdEpochMs,
    required bool enableDateRange,
    required int fromInclusiveEpochMs,
    required int toExclusiveEpochMs,
    required bool excludeSubfolders,
    int initialFilesMoved = 0,
    int initialErrors = 0,
    int logInterval = 100,
  }) {
    final cfg = calloc<TransferConfigC>();
    final srcPtr = sourcePath.toNativeUtf8();
    final dstPtr = destPath.toNativeUtf8();
    final lastDirPtr = (lastScannedDir != null && lastScannedDir.isNotEmpty)
        ? lastScannedDir.toNativeUtf8()
        : nullptr;

    try {
      cfg.ref.sourcePath = srcPtr;
      cfg.ref.destPath = dstPtr;
      cfg.ref.lastScannedDir = lastDirPtr;
      cfg.ref.enableAgeFilter = enableAgeFilter ? 1 : 0;
      cfg.ref.ageThresholdEpochMs = ageThresholdEpochMs;
      cfg.ref.enableDateRange = enableDateRange ? 1 : 0;
      cfg.ref.fromInclusiveEpochMs = fromInclusiveEpochMs;
      cfg.ref.toExclusiveEpochMs = toExclusiveEpochMs;
      cfg.ref.excludeSubfolders = excludeSubfolders ? 1 : 0;
      cfg.ref.initialFilesMoved = initialFilesMoved;
      cfg.ref.initialErrors = initialErrors;
      cfg.ref.logInterval = logInterval <= 0 ? 100 : logInterval;

      final handle = transferEngineStart(cfg);
      if (handle == nullptr) {
        throw StateError('Failed to start native Rust transfer engine');
      }
      return RustTransferJob._(handle);
    } finally {
      calloc.free(srcPtr);
      calloc.free(dstPtr);
      if (lastDirPtr != nullptr) {
        calloc.free(lastDirPtr);
      }
      calloc.free(cfg);
    }
  }

  bool get isDisposed => _disposed;

  RustTransferSnapshot poll() {
    final handle = _handle;
    if (_disposed || handle == null || handle == nullptr) {
      throw StateError('RustTransferJob has been disposed');
    }
    final jsonPtr = transferEnginePoll(handle);
    if (jsonPtr == nullptr) {
      throw StateError('transfer_engine_poll returned null');
    }
    try {
      final jsonStr = jsonPtr.toDartString();
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      return RustTransferSnapshot.fromJson(decoded);
    } finally {
      transferEngineFreeString(jsonPtr);
    }
  }

  void pause() {
    final handle = _handle;
    if (!_disposed && handle != null && handle != nullptr) {
      transferEnginePause(handle);
    }
  }

  void resume() {
    final handle = _handle;
    if (!_disposed && handle != null && handle != nullptr) {
      transferEngineResume(handle);
    }
  }

  void stop() {
    final handle = _handle;
    if (!_disposed && handle != null && handle != nullptr) {
      transferEngineStop(handle);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final handle = _handle;
    _handle = null;
    if (handle != null && handle != nullptr) {
      transferEngineDestroy(handle);
    }
  }
}
