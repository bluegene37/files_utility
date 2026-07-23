import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'global_db_service.dart';

/// Centralized file logger that writes logs to app log directory.
/// Each run gets a unique Run ID and its own log file.
/// Writes are buffered for performance (flushes every 2s or when buffer hits 50 lines).
class FileLogger {
  static final FileLogger _instance = FileLogger._internal();
  factory FileLogger() => _instance;
  FileLogger._internal();

  static String get _logDirectory {
    final appDir = GlobalDbService().appDirPath ?? p.join(Directory.systemTemp.path, 'file_transfer');
    return p.join(appDir, 'logs');
  }
  static const int _bufferFlushSize = 50;
  static const Duration _bufferFlushInterval = Duration(seconds: 2);

  /// Tracks the log file for each active operation (keyed by operation name).
  final Map<String, File> _activeRunFiles = {};

  /// Tracks the start time for each active run (for elapsed time calculation).
  final Map<String, DateTime> _runStartTimes = {};

  /// Tracks the unique Run ID for each active run.
  final Map<String, String> _runIds = {};

  /// Buffered log lines per operation, flushed periodically or on threshold.
  final Map<String, List<String>> _buffers = {};

  /// Timer per operation for periodic buffer flushing.
  final Map<String, Timer?> _flushTimers = {};

  /// Whether the log directory has been verified to exist.
  bool _directoryVerified = false;

  /// Ensures the log directory exists (cached after first check).
  Future<void> _ensureDirectory() async {
    if (_directoryVerified) return;
    final dir = Directory(_logDirectory);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _directoryVerified = true;
  }

  /// Generates a short unique Run ID (e.g., "RUN-A7F3").
  String _generateRunId() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random();
    final code = List.generate(4, (_) => chars[rng.nextInt(chars.length)]).join();
    return 'RUN-$code';
  }

  /// Gets the log file for the given operation source.
  File _getLogFile(String source) {
    if (_activeRunFiles.containsKey(source)) {
      return _activeRunFiles[source]!;
    }
    return _createRunFile(source);
  }

  /// Creates a new log file named with operation, date-time, and run ID.
  File _createRunFile(String source) {
    final dateTimeStr = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
    final safeSource = source.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final runId = _runIds[source] ?? _generateRunId();
    return File(p.join(_logDirectory, '${safeSource}_${dateTimeStr}_$runId.log'));
  }

  /// Buffers a log line and flushes if threshold is reached.
  Future<void> _write(String level, String source, String message) async {
    try {
      await _ensureDirectory();
      final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(DateTime.now());
      final runId = _runIds[source] ?? '--------';
      final logLine = '[$timestamp] [$runId] [$level] [$source] $message';

      _buffers.putIfAbsent(source, () => []);
      _buffers[source]!.add(logLine);

      // Start flush timer if not already running
      if (_flushTimers[source] == null) {
        _flushTimers[source] = Timer.periodic(_bufferFlushInterval, (_) {
          _flushBuffer(source);
        });
      }

      // Flush if buffer is full
      if (_buffers[source]!.length >= _bufferFlushSize) {
        await _flushBuffer(source);
      }
    } catch (_) {
      // Silently fail — don't crash the app if logging fails
    }
  }

  /// Flushes the buffered log lines to disk.
  Future<void> _flushBuffer(String source) async {
    final buffer = _buffers[source];
    if (buffer == null || buffer.isEmpty) return;

    try {
      final file = _getLogFile(source);
      final content = '${buffer.join('\r\n')}\r\n';
      buffer.clear();
      await file.writeAsString(content, mode: FileMode.append);
    } catch (_) {
      // Silently fail
    }
  }

  /// Force-flush all buffered writes for an operation. Call on stop/completion.
  Future<void> flush(String source) async {
    await _flushBuffer(source);
    _flushTimers[source]?.cancel();
    _flushTimers[source] = null;
  }

  /// Force-flush all active operations.
  Future<void> flushAll() async {
    for (final source in _buffers.keys.toList()) {
      await flush(source);
    }
  }

  /// Log an informational message.
  Future<void> info(String source, String message) async {
    await _write('INFO', source, message);
  }

  /// Log an error message.
  Future<void> error(String source, String message) async {
    await _write('ERROR', source, message);
  }

  /// Log the start of a run with operation details.
  /// Creates a new log file for this run with a unique Run ID.
  Future<void> logRunStart({
    required String operation,
    String? sourcePath,
    String? destPath,
    String? targetPath,
    int? year,
    List<String>? months,
  }) async {
    // Generate unique run ID
    final runId = _generateRunId();
    _runIds[operation] = runId;
    _runStartTimes[operation] = DateTime.now();

    // Create a new log file for this run
    _activeRunFiles[operation] = _createRunFile(operation);

    // Rich header
    final now = DateTime.now();
    final machineInfo = Platform.localHostname;
    final osInfo = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';

    await info(operation, '╔══════════════════════════════════════════════════════════════');
    await info(operation, '║  RUN STARTED — $runId');
    await info(operation, '║  Operation:  $operation');
    await info(operation, '║  Timestamp:  ${DateFormat('yyyy-MM-dd HH:mm:ss').format(now)}');
    await info(operation, '║  Machine:    $machineInfo');
    await info(operation, '║  OS:         $osInfo');
    await info(operation, '║  App:        Files Utility v1.0.0');
    if (sourcePath != null) await info(operation, '║  Source:     $sourcePath');
    if (destPath != null) await info(operation, '║  Dest:       $destPath');
    if (targetPath != null) await info(operation, '║  Target:     $targetPath');
    if (year != null) await info(operation, '║  Year:       $year');
    if (months != null) await info(operation, '║  Months:     ${months.join(', ')}');
    await info(operation, '╚══════════════════════════════════════════════════════════════');

    // Force-flush the header immediately
    await flush(operation);
  }

  /// Log the end of a run with summary stats and elapsed time.
  Future<void> logRunEnd({
    required String operation,
    required int filesProcessed,
    required int errors,
    required bool wasStopped,
  }) async {
    final startTime = _runStartTimes[operation];
    final runId = _runIds[operation] ?? '--------';
    String elapsedStr = 'N/A';

    if (startTime != null) {
      final elapsed = DateTime.now().difference(startTime);
      elapsedStr = _formatDuration(elapsed);
    }

    final throughput = _calculateThroughput(filesProcessed, startTime);

    await info(operation, '╔══════════════════════════════════════════════════════════════');
    await info(operation, '║  RUN SUMMARY — $runId');
    await info(operation, '║  Files processed:  $filesProcessed');
    if (errors > 0) {
      await error(operation, '║  Errors:           $errors');
    } else {
      await info(operation, '║  Errors:           0');
    }
    await info(operation, '║  Elapsed:          $elapsedStr');
    if (throughput != null) {
      await info(operation, '║  Throughput:        $throughput');
    }
    if (wasStopped) {
      await info(operation, '║  Status:           ⛔ STOPPED BY USER');
    } else {
      await info(operation, '║  Status:           ✅ COMPLETED SUCCESSFULLY');
    }
    await info(operation, '╚══════════════════════════════════════════════════════════════');

    // Force-flush everything and clean up
    await flush(operation);

    _activeRunFiles.remove(operation);
    _runStartTimes.remove(operation);
    _runIds.remove(operation);
    _buffers.remove(operation);
  }

  /// Formats a Duration into a human-readable string.
  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes.remainder(60)}m ${d.inSeconds.remainder(60)}s';
    } else if (d.inMinutes > 0) {
      return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
    } else {
      return '${d.inSeconds}s';
    }
  }

  /// Calculates throughput string (e.g., "3.8 files/sec").
  String? _calculateThroughput(int filesProcessed, DateTime? startTime) {
    if (startTime == null || filesProcessed == 0) return null;
    final elapsed = DateTime.now().difference(startTime);
    if (elapsed.inSeconds == 0) return null;
    final rate = filesProcessed / elapsed.inSeconds;
    return '${rate.toStringAsFixed(1)} files/sec';
  }

  /// Gets the Run ID for an active operation (for in-app display).
  String? getRunId(String operation) => _runIds[operation];

  /// Gets the start time for an active operation (for elapsed time display).
  DateTime? getStartTime(String operation) => _runStartTimes[operation];
}
