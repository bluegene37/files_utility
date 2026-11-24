// Gene - Nov, 21, 2026: Provider for FTP/FTPS/FTPES/SFTP upload execution, multi-source mapping, per-profile SQLite persistence, and scheduled runs.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import '../models/ftp_upload_source.dart';
import '../models/run_record.dart';
import '../services/credential_obfuscator.dart';
import '../services/file_creation_date.dart';
import '../services/file_logger.dart';
// Gene - Nov, 23, 2026: Import config.ini / .env parser for FTP automation configuration imports.
import '../services/ftp_ini_importer.dart';
import '../services/ftp_transfer_service.dart';
import '../services/history_service.dart';
import '../services/local_db_service.dart';
import '../services/path_safety.dart';

enum FtpDateMode {
  yesterday('Yesterday'),
  today('Today'),
  daysAgo('N Days Ago'),
  specificDate('Specific Date'),
  dateRange('Date Range'),
  allFiles('All Files');

  final String label;
  const FtpDateMode(this.label);

  static FtpDateMode fromStorage(String? value) {
    return FtpDateMode.values.firstWhere(
      (m) => m.name == value,
      orElse: () => FtpDateMode.yesterday,
    );
  }
}

enum FtpDateType {
  creation('Creation Date'),
  modified('Modified Date');

  final String label;
  const FtpDateType(this.label);

  static FtpDateType fromStorage(String? value) {
    return FtpDateType.values.firstWhere(
      (t) => t.name == value,
      orElse: () => FtpDateType.creation,
    );
  }
}

class _SubfolderWorkItem {
  final String rootPath;
  final String localDir;
  final String remoteDir;

  const _SubfolderWorkItem({
    required this.rootPath,
    required this.localDir,
    required this.remoteDir,
  });
}

class _QueuedUploadFile {
  final File file;
  final int size;

  const _QueuedUploadFile({required this.file, required this.size});
}

// Gene - Nov, 23, 2026: Holds both checked file count and matched files from a subfolder scan.
class _SubfolderScanResult {
  final int checkedCount;
  final List<_QueuedUploadFile> matched;

  const _SubfolderScanResult({
    required this.checkedCount,
    required this.matched,
  });
}

class FtpFilesProvider with ChangeNotifier {
  final Logger _log = Logger('FtpFilesProvider');
  final FileLogger _fileLogger = FileLogger();
  final NumberFormat _numFmt = NumberFormat('#,##0');
  final FtpClientAdapter Function(FtpConnectionConfig config) _clientFactory;
  final DateTime Function() _nowProvider;
  final bool _persistSettings;

  // Connection settings
  String host = '';
  int port = 21;
  String username = '';
  String password = '';
  FtpProtocol protocol = FtpProtocol.ftp;
  FtpTransferMode transferMode = FtpTransferMode.passive;
  int timeoutSeconds = 30;

  // Upload source settings
  bool useMultipleSources = false;
  String? sourcePath;
  String subfolders = '';
  String remoteDirectory = '';
  List<FtpUploadSource> uploadSources = [const FtpUploadSource()];

  // Date filter settings
  FtpDateMode dateMode = FtpDateMode.yesterday;
  int daysAgo = 1;
  FtpDateType dateType = FtpDateType.creation;
  DateTime specificDate = DateTime.now();
  DateTime fromDate = DateTime.now();
  DateTime toDate = DateTime.now();

  // Upload & reliability options
  bool includeSubfolders = false;
  bool skipIfExists = true;
  bool verifySizeAfterUpload = true;
  bool dryRun = false;
  int retryCount = 3;
  int retryDelaySeconds = 5;
  int logInterval = 1;
  // Gene - Nov, 23, 2026: Configurable FTP log retention window in days (0 = keep forever).
  int logKeepDays = 30;

  // Schedule settings
  bool enableSchedule = false;
  TimeOfDay runTime = const TimeOfDay(hour: 0, minute: 0);
  // Gene - Nov, 24, 2026: Added configurable runEndTime for FTP scheduled run window (default 06:00).
  TimeOfDay runEndTime = const TimeOfDay(hour: 6, minute: 0);
  Map<int, bool> runDays = {
    1: true,
    2: true,
    3: true,
    4: true,
    5: true,
    6: true,
    7: true,
  };
  String onCompletionAction = 'repeat'; // 'repeat' or 'stop'

  // Runtime state
  bool isUploading = false;
  bool isScheduleArmed = false;
  bool isTestingConnection = false;
  bool get isProcessing => isUploading || isScheduleArmed;
  DateTime? nextScheduledRun;
  String currentStatus = 'Idle';
  List<String> logs = [];

  int filesUploaded = 0;
  int filesSkipped = 0;
  int filesChecked = 0;
  int errors = 0;

  // Gene - Nov, 23, 2026: Live per-file transfer progress fields for UI display only.
  String? activeUploadFileName;
  int activeUploadSentBytes = 0;
  int activeUploadTotalBytes = 0;
  double? activeUploadProgress;
  double activeUploadBytesPerSecond = 0;

  int settingsVersion = 0;

  bool _stopRequested = false;
  // Gene - Nov, 24, 2026: Track scheduled run window expiration separately from manual stop.
  bool _windowExpired = false;
  DateTime? _activeRunWindowEnd;
  bool get _shouldAbortPass => _stopRequested || _windowExpired;
  bool _disposed = false;
  Timer? _scheduleTimer;
  FtpClientAdapter? _activeClient;
  DateTime? _uploadFileStartTime;
  DateTime? _lastProgressNotifyAt;
  bool _saveInFlight = false;
  bool _savePending = false;
  Completer<void>? _saveIdleCompleter;
  String? _loadedProfileId;

  FtpFilesProvider({
    FtpClientAdapter Function(FtpConnectionConfig config)? clientFactory,
    DateTime Function()? nowProvider,
    bool persistSettings = true,
  }) : _clientFactory = clientFactory ?? FtpConnectAdapter.new,
       _nowProvider = nowProvider ?? DateTime.now,
       _persistSettings = persistSettings {
    final now = _nowProvider();
    specificDate = DateTime(now.year, now.month, now.day);
    fromDate = DateTime(now.year, now.month, now.day);
    toDate = DateTime(now.year, now.month, now.day);
    if (_persistSettings) {
      _loadSettings();
      LocalDbService().addListener(_onProfileChanged);
    }
  }

  void _onProfileChanged() {
    _savePending = false;
    reloadSettings();
  }

  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _savePending = false;
    LocalDbService().removeListener(_onProfileChanged);
    _scheduleTimer?.cancel();
    _scheduleTimer = null;
    unawaited(_activeClient?.disconnect());
    super.dispose();
  }

  // --- Validation & Derived Helpers ---

  bool get hasValidConnection =>
      host.trim().isNotEmpty && port >= 1 && port <= 65535;

  //   bool get hasValidSources {
  //     if (useMultipleSources) {
  //       return uploadSources.any((s) => s.isValid);
  //     }
  //     return sourcePath != null && sourcePath!.trim().isNotEmpty;
  //   }
  // Gene - Nov, 23, 2026: Require at least one enabled and valid source when Multiple Sources is active.
  bool get hasValidSources {
    if (useMultipleSources) {
      return uploadSources.any((s) => s.enabled && s.isValid);
    }
    return sourcePath != null && sourcePath!.trim().isNotEmpty;
  }

  bool get hasCheckedScheduleDays => runDays.values.any((checked) => checked);

  // Gene - Nov, 24, 2026: Helpers for checking whether a run end-time cutoff is active and formatting 24h times.
  bool get hasEndTimeLimit =>
      runTime.hour != runEndTime.hour || runTime.minute != runEndTime.minute;

  static String _formatTime24(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  bool get canRunNow =>
      !isUploading &&
      !isTestingConnection &&
      hasValidConnection &&
      hasValidSources;

  bool get canArmSchedule =>
      !isProcessing &&
      !isTestingConnection &&
      enableSchedule &&
      hasValidConnection &&
      hasValidSources &&
      hasCheckedScheduleDays;

  FtpConnectionConfig get connectionConfig => FtpConnectionConfig(
    host: host.trim(),
    port: port,
    username: username.trim(),
    password: password,
    protocol: protocol,
    transferMode: transferMode,
    timeoutSeconds: timeoutSeconds,
  );

  // --- Pure Static Helpers (Testable) ---

  /// Returns the earliest future DateTime matching [runTime] on a checked [runDays] weekday.
  static DateTime? computeNextScheduledRun({
    required DateTime now,
    required TimeOfDay runTime,
    required Map<int, bool> runDays,
  }) {
    final hasAnyDay = runDays.values.any((checked) => checked);
    if (!hasAnyDay) return null;

    for (int offset = 0; offset <= 7; offset++) {
      final candidateDay = DateTime(
        now.year,
        now.month,
        now.day,
      ).add(Duration(days: offset));
      if (runDays[candidateDay.weekday] != true) continue;

      final candidate = DateTime(
        candidateDay.year,
        candidateDay.month,
        candidateDay.day,
        runTime.hour,
        runTime.minute,
      );
      if (candidate.isAfter(now)) {
        return candidate;
      }
    }
    return null;
  }

  // Gene - Nov, 24, 2026: Compute scheduled window end timestamp and active run window (including overnight midnight crossover).
  /// Computes the closing timestamp for a window starting at [windowStart].
  /// Returns `null` when [runTime] and [runEndTime] match (no end cutoff).
  static DateTime? computeWindowEnd({
    required DateTime windowStart,
    required TimeOfDay runTime,
    required TimeOfDay runEndTime,
  }) {
    final startMin = runTime.hour * 60 + runTime.minute;
    final endMin = runEndTime.hour * 60 + runEndTime.minute;
    if (startMin == endMin) return null;

    if (endMin > startMin) {
      return DateTime(
        windowStart.year,
        windowStart.month,
        windowStart.day,
        runEndTime.hour,
        runEndTime.minute,
      );
    }
    // Overnight / midnight crossover: calendar day + 1 avoids DST hour-shift bugs.
    return DateTime(
      windowStart.year,
      windowStart.month,
      windowStart.day + 1,
      runEndTime.hour,
      runEndTime.minute,
    );
  }

  /// Returns the currently active `(start, end)` scheduled window containing [now],
  /// checking both today and yesterday (for overnight windows), or `null` when
  /// outside the window or when [runTime] == [runEndTime] (single trigger point).
  static ({DateTime start, DateTime end})? computeActiveWindow({
    required DateTime now,
    required TimeOfDay runTime,
    required TimeOfDay runEndTime,
    required Map<int, bool> runDays,
  }) {
    final startMin = runTime.hour * 60 + runTime.minute;
    final endMin = runEndTime.hour * 60 + runEndTime.minute;
    if (startMin == endMin) return null;

    final todayStart = DateTime(
      now.year,
      now.month,
      now.day,
      runTime.hour,
      runTime.minute,
    );
    if (runDays[todayStart.weekday] == true) {
      final todayEnd = computeWindowEnd(
        windowStart: todayStart,
        runTime: runTime,
        runEndTime: runEndTime,
      )!;
      if (!now.isBefore(todayStart) && now.isBefore(todayEnd)) {
        return (start: todayStart, end: todayEnd);
      }
    }

    if (endMin < startMin) {
      final prevStart = DateTime(
        now.year,
        now.month,
        now.day - 1,
        runTime.hour,
        runTime.minute,
      );
      if (runDays[prevStart.weekday] == true) {
        final prevEnd = computeWindowEnd(
          windowStart: prevStart,
          runTime: runTime,
          runEndTime: runEndTime,
        )!;
        if (!now.isBefore(prevStart) && now.isBefore(prevEnd)) {
          return (start: prevStart, end: prevEnd);
        }
      }
    }

    return null;
  }

  /// Checks whether [fileDate] satisfies [dateMode] relative to [referenceNow].
  static bool matchesDateFilter({
    required DateTime fileDate,
    required FtpDateMode dateMode,
    required DateTime referenceNow,
    required int daysAgo,
    required DateTime specificDate,
    required DateTime fromDate,
    required DateTime toDate,
  }) {
    if (dateMode == FtpDateMode.allFiles) return true;

    final target = DateTime(fileDate.year, fileDate.month, fileDate.day);
    final refDay = DateTime(
      referenceNow.year,
      referenceNow.month,
      referenceNow.day,
    );

    switch (dateMode) {
      case FtpDateMode.today:
        return target == refDay;
      case FtpDateMode.yesterday:
        return target == refDay.subtract(const Duration(days: 1));
      case FtpDateMode.daysAgo:
        final safeDays = daysAgo < 0 ? 0 : daysAgo;
        return target == refDay.subtract(Duration(days: safeDays));
      case FtpDateMode.specificDate:
        final spec = DateTime(
          specificDate.year,
          specificDate.month,
          specificDate.day,
        );
        return target == spec;
      case FtpDateMode.dateRange:
        final from = DateTime(fromDate.year, fromDate.month, fromDate.day);
        final to = DateTime(toDate.year, toDate.month, toDate.day);
        return !target.isBefore(from) && !target.isAfter(to);
      case FtpDateMode.allFiles:
        return true;
    }
  }

  // Gene - Nov, 23, 2026: Human-readable byte size formatting and resolved target date description helpers.
  static String formatByteSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes < 1024 * 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    return '${(bytes / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(2)} TB';
  }

  static String describeTargetDate({
    required FtpDateMode dateMode,
    required DateTime referenceNow,
    required int daysAgo,
    required DateTime specificDate,
    required DateTime fromDate,
    required DateTime toDate,
  }) {
    final fmt = DateFormat('yyyy-MM-dd');
    final refDay = DateTime(
      referenceNow.year,
      referenceNow.month,
      referenceNow.day,
    );
    switch (dateMode) {
      case FtpDateMode.today:
        return '${fmt.format(refDay)} (Today)';
      case FtpDateMode.yesterday:
        return '${fmt.format(refDay.subtract(const Duration(days: 1)))} (Yesterday)';
      case FtpDateMode.daysAgo:
        final safeDays = daysAgo < 0 ? 0 : daysAgo;
        return '${fmt.format(refDay.subtract(Duration(days: safeDays)))} ($safeDays days ago)';
      case FtpDateMode.specificDate:
        final spec = DateTime(
          specificDate.year,
          specificDate.month,
          specificDate.day,
        );
        return '${fmt.format(spec)} (Specific Date)';
      case FtpDateMode.dateRange:
        final from = DateTime(fromDate.year, fromDate.month, fromDate.day);
        final to = DateTime(toDate.year, toDate.month, toDate.day);
        return '${fmt.format(from)} to ${fmt.format(to)}';
      case FtpDateMode.allFiles:
        return 'All dates';
    }
  }

  void _clearActiveUploadProgress() {
    activeUploadFileName = null;
    activeUploadSentBytes = 0;
    activeUploadTotalBytes = 0;
    activeUploadProgress = null;
    activeUploadBytesPerSecond = 0;
    _uploadFileStartTime = null;
    _lastProgressNotifyAt = null;
  }

  // --- Logging ---

  void _addLog(String message) {
    final safeMessage = CredentialObfuscator.redact(message, password);
    final timestamp = DateFormat('HH:mm:ss').format(_nowProvider());
    logs.insert(0, '[$timestamp] $safeMessage');
    if (logs.length > 1000) logs.removeLast();
  }

  void clearLogs() {
    logs.clear();
    notifyListeners();
  }

  // --- Persistence ---

  Future<void> _loadSettings() async {
    final db = LocalDbService();
    final profileId = db.currentProfileId;
    _loadedProfileId = profileId;

    host = db.getString('ftp_host') ?? '';
    protocol = FtpProtocol.fromStorage(db.getString('ftp_protocol'));
    port = db.getInt('ftp_port') ?? protocol.defaultPort;
    username = db.getString('ftp_username') ?? '';
    final storedPass = db.getString('ftp_password') ?? '';
    password = CredentialObfuscator.decode(storedPass, profileId: profileId);
    transferMode = FtpTransferMode.fromStorage(
      db.getString('ftp_transferMode'),
    );
    timeoutSeconds = db.getInt('ftp_timeoutSeconds') ?? 30;

    useMultipleSources = db.getBool('ftp_useMultipleSources') ?? false;
    sourcePath = db.getString('ftp_sourcePath');
    subfolders = db.getString('ftp_subfolders') ?? '';
    remoteDirectory = db.getString('ftp_remoteDirectory') ?? '';

    final sourcesJson = db.getString('ftp_uploadSources');
    if (sourcesJson != null && sourcesJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(sourcesJson) as List;
        uploadSources = decoded
            .map(
              (item) => FtpUploadSource.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
      } catch (_) {
        uploadSources = [const FtpUploadSource()];
      }
    } else {
      uploadSources = [const FtpUploadSource()];
    }
    if (uploadSources.isEmpty) {
      uploadSources = [const FtpUploadSource()];
    }

    dateMode = FtpDateMode.fromStorage(db.getString('ftp_dateMode'));
    daysAgo = db.getInt('ftp_daysAgo') ?? 1;
    dateType = FtpDateType.fromStorage(db.getString('ftp_dateType'));

    final now = _nowProvider();
    final sYear = db.getInt('ftp_specificDate_year');
    final sMonth = db.getInt('ftp_specificDate_month');
    final sDay = db.getInt('ftp_specificDate_day');
    specificDate = (sYear != null && sMonth != null && sDay != null)
        ? DateTime(sYear, sMonth, sDay)
        : DateTime(now.year, now.month, now.day);

    final fYear = db.getInt('ftp_fromDate_year');
    final fMonth = db.getInt('ftp_fromDate_month');
    final fDay = db.getInt('ftp_fromDate_day');
    fromDate = (fYear != null && fMonth != null && fDay != null)
        ? DateTime(fYear, fMonth, fDay)
        : DateTime(now.year, now.month, now.day);

    final tYear = db.getInt('ftp_toDate_year');
    final tMonth = db.getInt('ftp_toDate_month');
    final tDay = db.getInt('ftp_toDate_day');
    toDate = (tYear != null && tMonth != null && tDay != null)
        ? DateTime(tYear, tMonth, tDay)
        : DateTime(now.year, now.month, now.day);

    includeSubfolders = db.getBool('ftp_includeSubfolders') ?? false;
    skipIfExists = db.getBool('ftp_skipIfExists') ?? true;
    verifySizeAfterUpload = db.getBool('ftp_verifySizeAfterUpload') ?? true;
    dryRun = db.getBool('ftp_dryRun') ?? false;
    retryCount = db.getInt('ftp_retryCount') ?? 3;
    retryDelaySeconds = db.getInt('ftp_retryDelaySeconds') ?? 5;
    logInterval = db.getInt('ftp_logInterval') ?? 1;
    // Gene - Nov, 23, 2026: Load persisted FTP log retention days (default 30).
    logKeepDays = (db.getInt('ftp_logKeepDays') ?? 30).clamp(0, 365);

    enableSchedule = db.getBool('ftp_enableSchedule') ?? false;
    final runHour = db.getInt('ftp_runHour');
    final runMinute = db.getInt('ftp_runMinute');
    runTime = (runHour != null && runMinute != null)
        ? TimeOfDay(hour: runHour, minute: runMinute)
        : const TimeOfDay(hour: 0, minute: 0);
    // Gene - Nov, 24, 2026: Load persisted ftp_runEndHour/Minute; preserve no-cutoff behavior for legacy active schedules.
    final runEndHour = db.getInt('ftp_runEndHour');
    final runEndMinute = db.getInt('ftp_runEndMinute');
    if (runEndHour != null && runEndMinute != null) {
      runEndTime = TimeOfDay(
        hour: runEndHour.clamp(0, 23),
        minute: runEndMinute.clamp(0, 59),
      );
    } else if (enableSchedule) {
      runEndTime = runTime;
    } else {
      runEndTime = const TimeOfDay(hour: 6, minute: 0);
    }

    for (int day = 1; day <= 7; day++) {
      runDays[day] = db.getBool('ftp_runDay_$day') ?? true;
    }

    onCompletionAction = db.getString('ftp_onCompletionAction') ?? 'repeat';

    settingsVersion++;
    notifyListeners();
  }

  Future<void> reloadSettings() async {
    await _loadSettings();
  }

  Future<void> _saveSettings() {
    if (!_persistSettings || _disposed) return Future.value();
    _savePending = true;
    _saveIdleCompleter ??= Completer<void>();
    if (!_saveInFlight) {
      _saveInFlight = true;
      Future.microtask(_drainSaveQueue);
    }
    return _saveIdleCompleter!.future;
  }

  Future<void> _drainSaveQueue() async {
    try {
      while (_savePending && !_disposed) {
        _savePending = false;
        await _writeSettings();
      }
    } catch (_) {
    } finally {
      _saveInFlight = false;
      final completer = _saveIdleCompleter;
      _saveIdleCompleter = null;
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }
    }
  }

  @visibleForTesting
  Future<void> flushSavesForTest() async {
    await Future<void>.delayed(Duration.zero);
    if (_saveIdleCompleter != null) {
      await _saveIdleCompleter!.future;
    }
  }

  // Gene - Nov, 23, 2026: Test hook to drive live upload progress UI state in widget tests without real disk/SQLite I/O.
  @visibleForTesting
  void setUploadProgressForTest({
    required bool uploading,
    String? fileName,
    int sentBytes = 0,
    int totalBytes = 0,
    double? progress,
    double bytesPerSecond = 0,
  }) {
    isUploading = uploading;
    activeUploadFileName = fileName;
    activeUploadSentBytes = sentBytes;
    activeUploadTotalBytes = totalBytes;
    activeUploadProgress = progress;
    activeUploadBytesPerSecond = bytesPerSecond;
    notifyListeners();
  }

  Future<void> _writeSettings() async {
    final db = LocalDbService();
    final expectedProfileId = _loadedProfileId ?? db.currentProfileId;
    bool isAborted() => _disposed || db.currentProfileId != expectedProfileId;
    if (isAborted()) return;

    final writes = <Future<void> Function()>[
      () => db.setOrRemoveString('ftp_host', _nullIfEmpty(host)),
      () => db.setString('ftp_protocol', protocol.storageKey),
      () => db.setInt('ftp_port', port),
      () => db.setOrRemoveString('ftp_username', _nullIfEmpty(username)),
      () => password.isEmpty
          ? db.setOrRemoveString('ftp_password', null)
          : db.setString(
              'ftp_password',
              CredentialObfuscator.encode(
                password,
                profileId: expectedProfileId,
              ),
            ),
      () => db.setString('ftp_transferMode', transferMode.storageKey),
      () => db.setInt('ftp_timeoutSeconds', timeoutSeconds),
      () => db.setBool('ftp_useMultipleSources', useMultipleSources),
      () => db.setOrRemoveString('ftp_sourcePath', sourcePath),
      () => db.setOrRemoveString('ftp_subfolders', _nullIfEmpty(subfolders)),
      () => db.setOrRemoveString(
        'ftp_remoteDirectory',
        _nullIfEmpty(remoteDirectory),
      ),
      () => db.setString(
        'ftp_uploadSources',
        jsonEncode(uploadSources.map((s) => s.toJson()).toList()),
      ),
      () => db.setString('ftp_dateMode', dateMode.name),
      () => db.setInt('ftp_daysAgo', daysAgo),
      () => db.setString('ftp_dateType', dateType.name),
      () => db.setInt('ftp_specificDate_year', specificDate.year),
      () => db.setInt('ftp_specificDate_month', specificDate.month),
      () => db.setInt('ftp_specificDate_day', specificDate.day),
      () => db.setInt('ftp_fromDate_year', fromDate.year),
      () => db.setInt('ftp_fromDate_month', fromDate.month),
      () => db.setInt('ftp_fromDate_day', fromDate.day),
      () => db.setInt('ftp_toDate_year', toDate.year),
      () => db.setInt('ftp_toDate_month', toDate.month),
      () => db.setInt('ftp_toDate_day', toDate.day),
      () => db.setBool('ftp_includeSubfolders', includeSubfolders),
      () => db.setBool('ftp_skipIfExists', skipIfExists),
      () => db.setBool('ftp_verifySizeAfterUpload', verifySizeAfterUpload),
      () => db.setBool('ftp_dryRun', dryRun),
      () => db.setInt('ftp_retryCount', retryCount),
      () => db.setInt('ftp_retryDelaySeconds', retryDelaySeconds),
      () => db.setInt('ftp_logInterval', logInterval),
      // Gene - Nov, 23, 2026: Persist FTP log retention days.
      () => db.setInt('ftp_logKeepDays', logKeepDays),
      () => db.setBool('ftp_enableSchedule', enableSchedule),
      () => db.setInt('ftp_runHour', runTime.hour),
      () => db.setInt('ftp_runMinute', runTime.minute),
      // Gene - Nov, 24, 2026: Persist schedule window end time.
      () => db.setInt('ftp_runEndHour', runEndTime.hour),
      () => db.setInt('ftp_runEndMinute', runEndTime.minute),
      for (int day = 1; day <= 7; day++)
        () => db.setBool('ftp_runDay_$day', runDays[day] ?? true),
      () => db.setString('ftp_onCompletionAction', onCompletionAction),
    ];

    for (final write in writes) {
      if (isAborted()) return;
      await write();
    }
  }

  String? _nullIfEmpty(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _sanitizePath(String? path) {
    if (path == null) return null;
    final clean = path.replaceAll('"', '').replaceAll("'", '').trim();
    return clean.isEmpty ? null : clean;
  }

  // --- Setters ---

  void setHost(String value) {
    host = value.trim();
    _saveSettings();
    notifyListeners();
  }

  void setPort(int value) {
    if (value >= 1 && value <= 65535) {
      port = value;
      _saveSettings();
      notifyListeners();
    }
  }

  void setUsername(String value) {
    username = value.trim();
    _saveSettings();
    notifyListeners();
  }

  void setPassword(String value) {
    password = value;
    _saveSettings();
    notifyListeners();
  }

  void setProtocol(FtpProtocol newProtocol) {
    if (port == protocol.defaultPort) {
      port = newProtocol.defaultPort;
    }
    protocol = newProtocol;
    _saveSettings();
    notifyListeners();
  }

  void setTransferMode(FtpTransferMode mode) {
    transferMode = mode;
    _saveSettings();
    notifyListeners();
  }

  void setTimeoutSeconds(int seconds) {
    timeoutSeconds = seconds.clamp(5, 600);
    _saveSettings();
    notifyListeners();
  }

  void setUseMultipleSources(bool val) {
    useMultipleSources = val;
    if (val && uploadSources.isEmpty) {
      uploadSources = [const FtpUploadSource()];
    }
    _saveSettings();
    notifyListeners();
  }

  Future<void> pickSource() async {
    final path = await getDirectoryPath(initialDirectory: sourcePath);
    if (path != null) setSourcePath(path);
  }

  void setSourcePath(String? path) {
    sourcePath = _sanitizePath(path);
    if (sourcePath != null) {
      LocalDbService().addRecentDirectory(sourcePath!);
    }
    _saveSettings();
    notifyListeners();
  }

  void setSubfolders(String value) {
    subfolders = value.trim();
    _saveSettings();
    notifyListeners();
  }

  void setRemoteDirectory(String value) {
    remoteDirectory = value.trim();
    _saveSettings();
    notifyListeners();
  }

  void addUploadSource() {
    uploadSources.add(FtpUploadSource(runOrder: uploadSources.length + 1));
    _saveSettings();
    notifyListeners();
  }

  void removeUploadSource(int index) {
    if (uploadSources.length > 1 &&
        index >= 0 &&
        index < uploadSources.length) {
      uploadSources.removeAt(index);
      _saveSettings();
      notifyListeners();
    }
  }

  Future<void> pickSourceAt(int index) async {
    if (index < 0 || index >= uploadSources.length) return;
    final path = await getDirectoryPath(
      initialDirectory: uploadSources[index].localPath,
    );
    if (path != null) setSourcePathAt(index, path);
  }

  void setSourceNameAt(int index, String name) {
    if (index < 0 || index >= uploadSources.length) return;
    uploadSources[index] = uploadSources[index].copyWith(name: name.trim());
    _saveSettings();
    notifyListeners();
  }

  void setSourcePathAt(int index, String? path) {
    if (index < 0 || index >= uploadSources.length) return;
    final clean = _sanitizePath(path);
    uploadSources[index] = clean == null
        ? uploadSources[index].copyWith(clearLocalPath: true)
        : uploadSources[index].copyWith(localPath: clean);
    if (clean != null) {
      LocalDbService().addRecentDirectory(clean);
    }
    _saveSettings();
    notifyListeners();
  }

  void setSourceSubfoldersAt(int index, String value) {
    if (index < 0 || index >= uploadSources.length) return;
    uploadSources[index] = uploadSources[index].copyWith(
      subfolders: value.trim(),
    );
    _saveSettings();
    notifyListeners();
  }

  void setSourceFtpDestAt(int index, String value) {
    if (index < 0 || index >= uploadSources.length) return;
    uploadSources[index] = uploadSources[index].copyWith(ftpDest: value.trim());
    _saveSettings();
    notifyListeners();
  }

  void setSourceRunOrderAt(int index, int order) {
    if (index < 0 || index >= uploadSources.length) return;
    uploadSources[index] = uploadSources[index].copyWith(
      runOrder: order.clamp(1, 20),
    );
    _saveSettings();
    notifyListeners();
  }

  // Gene - Nov, 23, 2026: Toggle individual source active state without removing its configuration.
  void setSourceEnabledAt(int index, bool enabled) {
    if (index < 0 || index >= uploadSources.length) return;
    uploadSources[index] = uploadSources[index].copyWith(enabled: enabled);
    _saveSettings();
    notifyListeners();
  }

  void setDateMode(FtpDateMode mode) {
    dateMode = mode;
    _saveSettings();
    notifyListeners();
  }

  void setDaysAgo(int days) {
    daysAgo = days.clamp(0, 365);
    _saveSettings();
    notifyListeners();
  }

  void setDateType(FtpDateType type) {
    dateType = type;
    _saveSettings();
    notifyListeners();
  }

  void setSpecificDate(DateTime date) {
    specificDate = DateTime(date.year, date.month, date.day);
    _saveSettings();
    notifyListeners();
  }

  void setFromDate(DateTime date) {
    fromDate = DateTime(date.year, date.month, date.day);
    if (fromDate.isAfter(toDate)) {
      toDate = fromDate;
    }
    _saveSettings();
    notifyListeners();
  }

  void setToDate(DateTime date) {
    toDate = DateTime(date.year, date.month, date.day);
    if (toDate.isBefore(fromDate)) {
      fromDate = toDate;
    }
    _saveSettings();
    notifyListeners();
  }

  void setIncludeSubfolders(bool val) {
    includeSubfolders = val;
    _saveSettings();
    notifyListeners();
  }

  void setSkipIfExists(bool val) {
    skipIfExists = val;
    _saveSettings();
    notifyListeners();
  }

  void setVerifySizeAfterUpload(bool val) {
    verifySizeAfterUpload = val;
    _saveSettings();
    notifyListeners();
  }

  void setDryRun(bool val) {
    dryRun = val;
    _saveSettings();
    notifyListeners();
  }

  void setRetryCount(int count) {
    retryCount = count.clamp(1, 10);
    _saveSettings();
    notifyListeners();
  }

  void setRetryDelaySeconds(int seconds) {
    retryDelaySeconds = seconds.clamp(0, 120);
    _saveSettings();
    notifyListeners();
  }

  void setLogInterval(int interval) {
    logInterval = interval;
    _saveSettings();
    notifyListeners();
  }

  // Gene - Nov, 23, 2026: Log retention setter, config.ini/.env importer, and OS logs folder launcher.
  void setLogKeepDays(int days) {
    logKeepDays = days.clamp(0, 365);
    _saveSettings();
    notifyListeners();
  }

  String applyImportedConfig(FtpIniImportResult imported) {
    final changes = <String>[];

    if (imported.host != null) {
      host = imported.host!;
      changes.add('host');
    }
    if (imported.protocol != null) {
      protocol = imported.protocol!;
      if (imported.port == null) {
        port = protocol.defaultPort;
      }
      changes.add('protocol (${protocol.shortLabel})');
    }
    if (imported.port != null) {
      port = imported.port!;
      changes.add('port $port');
    }
    if (imported.username != null) {
      username = imported.username!;
      changes.add('username');
    }
    if (imported.password != null) {
      password = imported.password!;
      changes.add('password');
    }
    if (imported.daysAgo != null) {
      final d = imported.daysAgo!;
      if (d == 0) {
        dateMode = FtpDateMode.today;
      } else if (d == 1) {
        dateMode = FtpDateMode.yesterday;
      } else {
        dateMode = FtpDateMode.daysAgo;
        daysAgo = d.clamp(0, 365);
      }
      changes.add('daysAgo=$d');
    }
    if (imported.timeoutSeconds != null) {
      timeoutSeconds = imported.timeoutSeconds!.clamp(5, 600);
    }
    if (imported.retryCount != null) {
      retryCount = imported.retryCount!.clamp(1, 10);
    }
    if (imported.retryDelaySeconds != null) {
      retryDelaySeconds = imported.retryDelaySeconds!.clamp(0, 120);
    }
    if (imported.dryRun != null) {
      dryRun = imported.dryRun!;
    }
    if (imported.logKeepDays != null) {
      logKeepDays = imported.logKeepDays!.clamp(0, 365);
      changes.add('logKeepDays=$logKeepDays');
    }

    if (imported.sources.isNotEmpty) {
      if (imported.sources.length > 1) {
        useMultipleSources = true;
        uploadSources = List<FtpUploadSource>.from(imported.sources);
      } else {
        final single = imported.sources.first;
        useMultipleSources = false;
        sourcePath = single.localPath;
        subfolders = single.subfolders;
        remoteDirectory = single.ftpDest;
        uploadSources = List<FtpUploadSource>.from(imported.sources);
      }
      if (imported.sources.any((s) => s.parsedSubfolders.isEmpty)) {
        includeSubfolders = true;
      }
      changes.add('${imported.sources.length} source(s)');
    }

    settingsVersion++;
    _saveSettings();

    final summary = changes.isEmpty ? 'settings updated' : changes.join(', ');
    _addLog('📥 Imported configuration: $summary');
    notifyListeners();
    return 'Imported: $summary';
  }

  //   Future<String?> importConfigFromDisk() async {
  //     final picked = await openFile();
  //     if (picked == null) return null;
  //
  //     try {
  //       final content = await File(picked.path).readAsString();
  //       final baseName = p.basename(picked.path).toLowerCase();
  //       final parentDir = p.dirname(picked.path);
  //
  //       String? iniContent;
  //       String? envContent;
  //       if (baseName == '.env' || baseName.endsWith('.env')) {
  //         envContent = content;
  //         final siblingIni = File(p.join(parentDir, 'config.ini'));
  //         if (await siblingIni.exists()) {
  //           iniContent = await siblingIni.readAsString();
  //         }
  //       } else {
  //         iniContent = content;
  //         final siblingEnv = File(p.join(parentDir, '.env'));
  //         if (await siblingEnv.exists()) {
  //           envContent = await siblingEnv.readAsString();
  //         }
  //       }
  //
  //       final parsed = FtpIniImporter.parse(
  //         iniContent: iniContent,
  //         envContent: envContent,
  //       );
  //       if (parsed.isEmpty) {
  //         return 'No recognizable FTP settings found in ${p.basename(picked.path)}.';
  //       }
  //       return applyImportedConfig(parsed);
  //     } catch (e) {
  //       return 'Failed to import config: ${CredentialObfuscator.redact(e.toString(), password)}';
  //     }
  //   }
  // Gene - Nov, 23, 2026: Add lossless JSON settings & upload sources export/import (without passwords) alongside config.ini/.env support.
  Map<String, dynamic> exportSettingsJson({DateTime? now}) {
    final dateFmt = DateFormat('yyyy-MM-dd');
    return {
      'app': 'Files Utility',
      'type': 'ftp_settings',
      'schemaVersion': 1,
      'exportedAt': (now ?? _nowProvider()).toIso8601String(),
      //       'connection': {
      //         'protocol': protocol.storageKey,
      //         'host': host,
      //         'port': port,
      //         'username': username,
      //         'transferMode': transferMode.storageKey,
      //         'timeoutSeconds': timeoutSeconds,
      //       },
      // Gene - Nov, 23, 2026: Exclude both username and password from exported FTP settings JSON.
      'connection': {
        'protocol': protocol.storageKey,
        'host': host,
        'port': port,
        'transferMode': transferMode.storageKey,
        'timeoutSeconds': timeoutSeconds,
      },
      'sources': {
        'useMultipleSources': useMultipleSources,
        'sourcePath': sourcePath,
        'subfolders': subfolders,
        'remoteDirectory': remoteDirectory,
        'uploadSources': uploadSources.map((s) => s.toJson()).toList(),
      },
      'filters': {
        'dateMode': dateMode.name,
        'daysAgo': daysAgo,
        'dateType': dateType.name,
        'specificDate': dateFmt.format(specificDate),
        'fromDate': dateFmt.format(fromDate),
        'toDate': dateFmt.format(toDate),
      },
      'options': {
        'includeSubfolders': includeSubfolders,
        'skipIfExists': skipIfExists,
        'verifySizeAfterUpload': verifySizeAfterUpload,
        'dryRun': dryRun,
        'retryCount': retryCount,
        'retryDelaySeconds': retryDelaySeconds,
        'logInterval': logInterval,
        'logKeepDays': logKeepDays,
      },
      //       'schedule': {
      //         'enableSchedule': enableSchedule,
      //         'runHour': runTime.hour,
      //         'runMinute': runTime.minute,
      //         'runDays': {for (int d = 1; d <= 7; d++) '$d': runDays[d] ?? true},
      //         'onCompletionAction': onCompletionAction,
      //       },
      // Gene - Nov, 24, 2026: Export schedule runEndHour and runEndMinute in FTP settings JSON.
      'schedule': {
        'enableSchedule': enableSchedule,
        'runHour': runTime.hour,
        'runMinute': runTime.minute,
        'runEndHour': runEndTime.hour,
        'runEndMinute': runEndTime.minute,
        'runDays': {for (int d = 1; d <= 7; d++) '$d': runDays[d] ?? true},
        'onCompletionAction': onCompletionAction,
      },
    };
  }

  Map<String, dynamic> exportUploadSourcesJson({DateTime? now}) {
    return {
      'app': 'Files Utility',
      'type': 'ftp_sources',
      'schemaVersion': 1,
      'exportedAt': (now ?? _nowProvider()).toIso8601String(),
      'uploadSources': uploadSources.map((s) => s.toJson()).toList(),
    };
  }

  String exportSettingsJsonString({DateTime? now}) =>
      const JsonEncoder.withIndent('  ').convert(exportSettingsJson(now: now));

  String exportUploadSourcesJsonString({DateTime? now}) =>
      const JsonEncoder.withIndent(
        '  ',
      ).convert(exportUploadSourcesJson(now: now));

  List<FtpUploadSource> _parseUploadSourcesList(dynamic rawList) {
    if (rawList is! List) return const [];
    final parsed = <FtpUploadSource>[];
    for (final entry in rawList) {
      if (entry is! Map) continue;
      final src = FtpUploadSource.fromJson(Map<String, dynamic>.from(entry));
      parsed.add(
        FtpUploadSource(
          name: src.name.trim(),
          localPath: _sanitizePath(src.localPath),
          subfolders: src.subfolders.trim(),
          ftpDest: src.ftpDest.trim(),
          runOrder: src.runOrder.clamp(1, 20),
          enabled: src.enabled,
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

  String importFromJsonString(String jsonStr, {bool sourcesOnly = false}) {
    final dynamic decoded = jsonDecode(jsonStr);
    if (decoded is List) {
      final parsedSources = _parseUploadSourcesList(decoded);
      if (parsedSources.isEmpty) {
        throw const FormatException('No upload sources found in file.');
      }
      uploadSources = parsedSources;
      useMultipleSources = true;
      settingsVersion++;
      _saveSettings();
      final msg = 'Imported ${parsedSources.length} upload source(s).';
      _addLog('📥 $msg');
      notifyListeners();
      return msg;
    }

    if (decoded is! Map) {
      throw const FormatException('Invalid JSON structure.');
    }

    final map = Map<String, dynamic>.from(decoded);
    final rawType = map['type'] as String?;
    if (rawType == 'copy_settings' || rawType == 'copy_pairs') {
      throw const FormatException(
        'This file is a Copy Files export, not an FTP export.',
      );
    }
    if (rawType != null &&
        rawType != 'ftp_settings' &&
        rawType != 'ftp_sources') {
      throw FormatException('Unsupported export file type: $rawType');
    }

    final sourcesMap = map['sources'] is Map
        ? Map<String, dynamic>.from(map['sources'] as Map)
        : null;
    final rawSources = map['uploadSources'] ?? sourcesMap?['uploadSources'];
    final parsedSources = _parseUploadSourcesList(rawSources);

    if (sourcesOnly || rawType == 'ftp_sources') {
      if (parsedSources.isEmpty) {
        throw const FormatException('No upload sources found in file.');
      }
      uploadSources = parsedSources;
      useMultipleSources = true;
      settingsVersion++;
      _saveSettings();
      final msg = 'Imported ${parsedSources.length} upload source(s).';
      _addLog('📥 $msg');
      notifyListeners();
      return msg;
    }

    if (rawType == null &&
        map['connection'] == null &&
        sourcesMap == null &&
        map['filters'] == null &&
        map['options'] == null &&
        map['schedule'] == null &&
        rawSources == null) {
      throw const FormatException('Unrecognized FTP JSON structure.');
    }

    final conn = map['connection'] is Map
        ? Map<String, dynamic>.from(map['connection'] as Map)
        : null;
    if (conn != null) {
      final previousHost = host.trim();
      if (conn.containsKey('protocol')) {
        protocol = FtpProtocol.fromStorage(conn['protocol'] as String?);
      }
      if (conn.containsKey('host')) {
        host = (conn['host'] as String? ?? '').trim();
      }
      if (conn.containsKey('port')) {
        final pVal = (conn['port'] as num?)?.toInt();
        if (pVal != null && pVal >= 1 && pVal <= 65535) {
          port = pVal;
        }
      }
      //       if (conn.containsKey('username')) {
      //         username = (conn['username'] as String? ?? '').trim();
      //       }
      //       if (conn.containsKey('transferMode')) {
      //         transferMode = FtpTransferMode.fromStorage(
      //           conn['transferMode'] as String?,
      //         );
      //       }
      //       if (conn.containsKey('timeoutSeconds')) {
      //         final tVal = (conn['timeoutSeconds'] as num?)?.toInt();
      //         if (tVal != null) {
      //           timeoutSeconds = tVal.clamp(5, 600);
      //         }
      //       }
      //       // Clear cached password if importing settings for a different server host.
      //       if (host.isNotEmpty && previousHost.isNotEmpty && host != previousHost) {
      //         password = '';
      //       }
      // Gene - Nov, 23, 2026: Never import username from JSON exports and clear both username and password when switching hosts.
      if (conn.containsKey('transferMode')) {
        transferMode = FtpTransferMode.fromStorage(
          conn['transferMode'] as String?,
        );
      }
      if (conn.containsKey('timeoutSeconds')) {
        final tVal = (conn['timeoutSeconds'] as num?)?.toInt();
        if (tVal != null) {
          timeoutSeconds = tVal.clamp(5, 600);
        }
      }
      // Clear cached credentials if importing settings for a different server host.
      if (host.isNotEmpty && previousHost.isNotEmpty && host != previousHost) {
        username = '';
        password = '';
      }
    }

    if (sourcesMap != null) {
      if (sourcesMap.containsKey('useMultipleSources')) {
        useMultipleSources =
            sourcesMap['useMultipleSources'] as bool? ?? useMultipleSources;
      }
      if (sourcesMap.containsKey('sourcePath')) {
        sourcePath = _sanitizePath(sourcesMap['sourcePath'] as String?);
      }
      if (sourcesMap.containsKey('subfolders')) {
        subfolders = (sourcesMap['subfolders'] as String? ?? '').trim();
      }
      if (sourcesMap.containsKey('remoteDirectory')) {
        remoteDirectory = (sourcesMap['remoteDirectory'] as String? ?? '')
            .trim();
      }
    }
    if (rawSources != null) {
      uploadSources = parsedSources.isNotEmpty
          ? parsedSources
          : [const FtpUploadSource()];
    }

    final filters = map['filters'] is Map
        ? Map<String, dynamic>.from(map['filters'] as Map)
        : null;
    if (filters != null) {
      if (filters.containsKey('dateMode')) {
        dateMode = FtpDateMode.fromStorage(filters['dateMode'] as String?);
      }
      if (filters.containsKey('daysAgo')) {
        final dVal = (filters['daysAgo'] as num?)?.toInt();
        if (dVal != null) daysAgo = dVal.clamp(0, 365);
      }
      if (filters.containsKey('dateType')) {
        dateType = FtpDateType.fromStorage(filters['dateType'] as String?);
      }
      final spec = _parseIsoCalendarDate(filters['specificDate']);
      if (spec != null) specificDate = spec;
      final fDate = _parseIsoCalendarDate(filters['fromDate']);
      if (fDate != null) fromDate = fDate;
      final tDate = _parseIsoCalendarDate(filters['toDate']);
      if (tDate != null) toDate = tDate;
      if (fromDate.isAfter(toDate)) {
        toDate = fromDate;
      }
    }

    final options = map['options'] is Map
        ? Map<String, dynamic>.from(map['options'] as Map)
        : null;
    if (options != null) {
      if (options.containsKey('includeSubfolders')) {
        includeSubfolders =
            options['includeSubfolders'] as bool? ?? includeSubfolders;
      }
      if (options.containsKey('skipIfExists')) {
        skipIfExists = options['skipIfExists'] as bool? ?? skipIfExists;
      }
      if (options.containsKey('verifySizeAfterUpload')) {
        verifySizeAfterUpload =
            options['verifySizeAfterUpload'] as bool? ?? verifySizeAfterUpload;
      }
      if (options.containsKey('dryRun')) {
        dryRun = options['dryRun'] as bool? ?? dryRun;
      }
      if (options.containsKey('retryCount')) {
        final rVal = (options['retryCount'] as num?)?.toInt();
        if (rVal != null) retryCount = rVal.clamp(1, 10);
      }
      if (options.containsKey('retryDelaySeconds')) {
        final rdVal = (options['retryDelaySeconds'] as num?)?.toInt();
        if (rdVal != null) retryDelaySeconds = rdVal.clamp(0, 120);
      }
      if (options.containsKey('logInterval')) {
        final liVal = (options['logInterval'] as num?)?.toInt();
        const allowedIntervals = [1, 5, 10, 25, 50, 100];
        if (liVal != null) {
          logInterval = allowedIntervals.contains(liVal) ? liVal : 1;
        }
      }
      if (options.containsKey('logKeepDays')) {
        final lkVal = (options['logKeepDays'] as num?)?.toInt();
        if (lkVal != null) logKeepDays = lkVal.clamp(0, 365);
      }
    }

    final schedule = map['schedule'] is Map
        ? Map<String, dynamic>.from(map['schedule'] as Map)
        : null;
    //     if (schedule != null) {
    //       if (schedule.containsKey('enableSchedule')) {
    //         enableSchedule = schedule['enableSchedule'] as bool? ?? enableSchedule;
    //       }
    //       final runHour = (schedule['runHour'] as num?)?.toInt();
    //       final runMinute = (schedule['runMinute'] as num?)?.toInt();
    //       if (runHour != null && runMinute != null) {
    //         runTime = TimeOfDay(
    //           hour: runHour.clamp(0, 23),
    //           minute: runMinute.clamp(0, 59),
    //         );
    //       }
    //       if (schedule['runDays'] is Map) {
    //         final rawDays = Map<String, dynamic>.from(schedule['runDays'] as Map);
    //         for (int day = 1; day <= 7; day++) {
    //           final val = rawDays['$day'];
    //           if (val is bool) {
    //             runDays[day] = val;
    //           }
    //         }
    //       }
    //       final action = schedule['onCompletionAction'];
    //       if (action == 'repeat' || action == 'stop') {
    //         onCompletionAction = action as String;
    //       }
    //     }
    // Gene - Nov, 24, 2026: Import schedule runEndHour/runEndMinute with legacy start-only fallback.
    if (schedule != null) {
      if (schedule.containsKey('enableSchedule')) {
        enableSchedule = schedule['enableSchedule'] as bool? ?? enableSchedule;
      }
      final runHour = (schedule['runHour'] as num?)?.toInt();
      final runMinute = (schedule['runMinute'] as num?)?.toInt();
      if (runHour != null && runMinute != null) {
        runTime = TimeOfDay(
          hour: runHour.clamp(0, 23),
          minute: runMinute.clamp(0, 59),
        );
      }
      final runEndHour = (schedule['runEndHour'] as num?)?.toInt();
      final runEndMinute = (schedule['runEndMinute'] as num?)?.toInt();
      if (runEndHour != null && runEndMinute != null) {
        runEndTime = TimeOfDay(
          hour: runEndHour.clamp(0, 23),
          minute: runEndMinute.clamp(0, 59),
        );
      } else if (runHour != null && runMinute != null) {
        // Legacy JSON export with only start time: preserve no-cutoff behavior.
        runEndTime = runTime;
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
      if (action == 'repeat' || action == 'stop') {
        onCompletionAction = action as String;
      }
    }

    settingsVersion++;
    _saveSettings();
    //     final msg =
    //         'Imported FTP settings (${uploadSources.length} source(s)). Re-enter FTP password if needed.';
    // Gene - Nov, 23, 2026: Prompt user to enter both FTP username and password after JSON settings import.
    final msg =
        'Imported FTP settings (${uploadSources.length} source(s)). Enter FTP username and password in Connection settings.';
    _addLog('📥 $msg');
    notifyListeners();
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
        suggestedName: 'ftp_settings.json',
        jsonContent: exportSettingsJsonString(),
      );
      if (outPath == null) return null;
      //       _addLog('📤 Exported FTP settings (without password) to $outPath');
      //       notifyListeners();
      //       return 'Exported FTP settings (without password) to ${p.basename(outPath)}';
      // Gene - Nov, 23, 2026: Update export message to reflect username and password exclusion.
      _addLog(
        '📤 Exported FTP settings (without username/password) to $outPath',
      );
      notifyListeners();
      return 'Exported FTP settings (without username/password) to ${p.basename(outPath)}';
    } catch (e) {
      return 'Failed to export settings: ${CredentialObfuscator.redact(e.toString(), password)}';
    }
  }

  Future<String?> exportUploadSourcesToDisk() async {
    try {
      final outPath = await _writeJsonExportFile(
        suggestedName: 'ftp_upload_sources.json',
        jsonContent: exportUploadSourcesJsonString(),
      );
      if (outPath == null) return null;
      _addLog(
        '📤 Exported ${uploadSources.length} upload source(s) to $outPath',
      );
      notifyListeners();
      return 'Exported ${uploadSources.length} upload source(s) to ${p.basename(outPath)}';
    } catch (e) {
      return 'Failed to export upload sources: ${CredentialObfuscator.redact(e.toString(), password)}';
    }
  }

  Future<String?> importConfigFromDisk() async {
    final picked = await openFile();
    if (picked == null) return null;

    try {
      final content = await File(picked.path).readAsString();
      final baseName = p.basename(picked.path).toLowerCase();
      final trimmedStart = content.trimLeft();

      if (baseName.endsWith('.json') ||
          trimmedStart.startsWith('{') ||
          trimmedStart.startsWith('[')) {
        return importFromJsonString(content);
      }

      final parentDir = p.dirname(picked.path);
      String? iniContent;
      String? envContent;
      if (baseName == '.env' || baseName.endsWith('.env')) {
        envContent = content;
        final siblingIni = File(p.join(parentDir, 'config.ini'));
        if (await siblingIni.exists()) {
          iniContent = await siblingIni.readAsString();
        }
      } else {
        iniContent = content;
        final siblingEnv = File(p.join(parentDir, '.env'));
        if (await siblingEnv.exists()) {
          envContent = await siblingEnv.readAsString();
        }
      }

      final parsed = FtpIniImporter.parse(
        iniContent: iniContent,
        envContent: envContent,
      );
      if (parsed.isEmpty) {
        return 'No recognizable FTP settings found in ${p.basename(picked.path)}.';
      }
      return applyImportedConfig(parsed);
    } catch (e) {
      return 'Failed to import config: ${CredentialObfuscator.redact(e.toString(), password)}';
    }
  }

  Future<String?> importUploadSourcesFromDisk() async {
    final picked = await openFile();
    if (picked == null) return null;

    try {
      final content = await File(picked.path).readAsString();
      final baseName = p.basename(picked.path).toLowerCase();
      final trimmedStart = content.trimLeft();

      if (baseName.endsWith('.json') ||
          trimmedStart.startsWith('{') ||
          trimmedStart.startsWith('[')) {
        return importFromJsonString(content, sourcesOnly: true);
      }

      final parsed = FtpIniImporter.parse(iniContent: content);
      if (parsed.sources.isEmpty) {
        return 'No [source.*] sections found in ${p.basename(picked.path)}.';
      }
      uploadSources = List<FtpUploadSource>.from(parsed.sources);
      useMultipleSources = true;
      settingsVersion++;
      _saveSettings();
      final msg = 'Imported ${parsed.sources.length} upload source(s).';
      _addLog('📥 $msg');
      notifyListeners();
      return msg;
    } catch (e) {
      return 'Failed to import upload sources: ${CredentialObfuscator.redact(e.toString(), password)}';
    }
  }

  Future<bool> openLogsFolder() => _fileLogger.openLogDirectory();

  void setEnableSchedule(bool val) {
    enableSchedule = val;
    _saveSettings();
    notifyListeners();
  }

  void setRunTime(TimeOfDay time) {
    runTime = time;
    _saveSettings();
    if (isScheduleArmed && !isUploading) {
      _recomputeArmedNextRun();
    } else {
      notifyListeners();
    }
  }

  // Gene - Nov, 24, 2026: Added setter for scheduled run window end time.
  void setRunEndTime(TimeOfDay time) {
    runEndTime = time;
    _saveSettings();
    if (isScheduleArmed && !isUploading) {
      _recomputeArmedNextRun();
    } else {
      notifyListeners();
    }
  }

  void setRunDay(int day, bool value) {
    runDays[day] = value;
    _saveSettings();
    if (isScheduleArmed && !isUploading) {
      if (!hasCheckedScheduleDays) {
        _scheduleTimer?.cancel();
        _scheduleTimer = null;
        isScheduleArmed = false;
        nextScheduledRun = null;
        currentStatus = 'Idle';
        _addLog('⚠️ Schedule disarmed because no run days remain selected.');
      } else {
        _recomputeArmedNextRun();
        return;
      }
    }
    notifyListeners();
  }

  void setOnCompletionAction(String action) {
    onCompletionAction = action;
    _saveSettings();
    notifyListeners();
  }

  //   void _recomputeArmedNextRun() {
  //     final next = computeNextScheduledRun(
  //       now: _nowProvider(),
  //       runTime: runTime,
  //       runDays: runDays,
  //     );
  //     nextScheduledRun = next;
  //     if (next != null) {
  //       final formatted = DateFormat('dd/MM/yyyy HH:mm').format(next);
  //       currentStatus = '⏰ Scheduled — Next run: $formatted';
  //       _addLog('⏰ Schedule updated — next run at $formatted.');
  //     }
  //     notifyListeners();
  //   }
  // Gene - Nov, 24, 2026: Include optional end-time window suffix in recomputed schedule status and log.
  void _recomputeArmedNextRun() {
    final next = computeNextScheduledRun(
      now: _nowProvider(),
      runTime: runTime,
      runDays: runDays,
    );
    nextScheduledRun = next;
    if (next != null) {
      final formatted = DateFormat('dd/MM/yyyy HH:mm').format(next);
      final windowSuffix = hasEndTimeLimit
          ? ' (until ${_formatTime24(runEndTime)})'
          : '';
      currentStatus = '⏰ Scheduled — Next run: $formatted$windowSuffix';
      _addLog('⏰ Schedule updated — next run at $formatted$windowSuffix.');
    }
    notifyListeners();
  }

  // --- Connection Test ---

  Future<FtpTestResult> testConnection() async {
    if (!hasValidConnection) {
      return const FtpTestResult(
        success: false,
        message: 'Enter a valid server host and port (1-65535) first.',
      );
    }
    if (isTestingConnection || isUploading) {
      return const FtpTestResult(
        success: false,
        message: 'Another FTP operation is already in progress.',
      );
    }

    isTestingConnection = true;
    final previousStatus = currentStatus;
    currentStatus = '🔌 Testing connection...';
    final config = connectionConfig;
    _addLog('🔌 Testing connection to ${config.displayEndpoint()}...');
    notifyListeners();

    final client = _clientFactory(config);
    try {
      await client.connect();
      final cwd = await client.currentDirectory();
      String message = 'Connected (${config.protocol.shortLabel}) — CWD: $cwd';

      if (!useMultipleSources && remoteDirectory.trim().isNotEmpty) {
        final target = joinRemotePath(remoteDirectory, '');
        final ok = await client.changeDirectory(target);
        if (ok) {
          message += ' | Remote folder "$target" accessible';
        } else {
          message +=
              ' | Remote folder "$target" does not exist yet (will be created on upload)';
        }
      }

      _addLog('✅ $message');
      return FtpTestResult(success: true, message: message);
    } catch (e) {
      final safeErr = CredentialObfuscator.redact(e.toString(), password);
      _addLog('❌ Connection test failed: $safeErr');
      return FtpTestResult(success: false, message: safeErr);
    } finally {
      await client.disconnect();
      isTestingConnection = false;
      currentStatus = previousStatus;
      notifyListeners();
    }
  }

  // --- Scheduling & Execution Controls ---

  //   void startSchedule() {
  //     if (!canArmSchedule) return;
  //
  //     final next = computeNextScheduledRun(
  //       now: _nowProvider(),
  //       runTime: runTime,
  //       runDays: runDays,
  //     );
  //     if (next == null) {
  //       _addLog('⚠️ Select at least one weekday before starting the schedule.');
  //       notifyListeners();
  //       return;
  //     }
  //
  //     _stopRequested = false;
  //     isScheduleArmed = true;
  //     nextScheduledRun = next;
  //
  //     final formatted = DateFormat('dd/MM/yyyy HH:mm').format(next);
  //     currentStatus = '⏰ Scheduled — Next run: $formatted';
  //     _addLog('⏰ Schedule armed. Waiting for $formatted...');
  //     notifyListeners();
  //
  //     _ensureScheduleTimerRunning();
  //   }
  //
  //   void _ensureScheduleTimerRunning() {
  //     _scheduleTimer?.cancel();
  //     _scheduleTimer = Timer.periodic(const Duration(seconds: 15), (_) {
  //       _checkScheduleTick();
  //     });
  //   }
  //
  //   Future<void> _checkScheduleTick() async {
  //     if (!isScheduleArmed || isUploading || _stopRequested) return;
  //     final dueAt = nextScheduledRun;
  //     if (dueAt == null) return;
  //
  //     final now = _nowProvider();
  //     if (!now.isBefore(dueAt)) {
  //       nextScheduledRun = null;
  //       _addLog(
  //         '⏳ Scheduled run time reached (${DateFormat('dd/MM/yyyy HH:mm').format(dueAt)}). Starting upload...',
  //       );
  //       await _executeUploadPass(isScheduledRun: true);
  //     }
  //   }
  //
  //   @visibleForTesting
  //   Future<void> triggerScheduleTickForTest() => _checkScheduleTick();
  //
  //   Future<void> runNow() async {
  //     if (!canRunNow) return;
  //     await _executeUploadPass(isScheduledRun: false);
  //   }
  //
  //   void stop() {
  //     if (!isProcessing) return;
  //     _stopRequested = true;
  //     _scheduleTimer?.cancel();
  //     _scheduleTimer = null;
  //     isScheduleArmed = false;
  //     nextScheduledRun = null;
  //
  //     if (isUploading) {
  //       currentStatus = '⛔ Stopping...';
  //       _addLog('⛔ Stop requested by user. Closing active FTP connection...');
  //       unawaited(_activeClient?.disconnect());
  //     } else {
  //       currentStatus = '⛔ Stopped';
  //       _addLog('⛔ FTP schedule stopped by user.');
  //     }
  //     notifyListeners();
  //   }
  // Gene - Nov, 24, 2026: Support start/end run window activation, missed-window handling, and automatic clean stop at runEndTime.
  bool _checkWindowExpiration() {
    if (!isUploading || _activeRunWindowEnd == null || _stopRequested) {
      return _windowExpired;
    }
    if (_windowExpired) return true;
    final now = _nowProvider();
    if (!now.isBefore(_activeRunWindowEnd!)) {
      _windowExpired = true;
      final endLabel = _formatTime24(runEndTime);
      currentStatus = '⏰ End time ($endLabel) reached. Stopping...';
      _addLog(
        '⏰ Scheduled end time ($endLabel) reached. Stopping active upload cleanly...',
      );
      unawaited(_activeClient?.disconnect());
      notifyListeners();
      return true;
    }
    return false;
  }

  void startSchedule() {
    if (!canArmSchedule) return;

    final now = _nowProvider();
    final activeWindow = computeActiveWindow(
      now: now,
      runTime: runTime,
      runEndTime: runEndTime,
      runDays: runDays,
    );
    if (activeWindow != null) {
      _stopRequested = false;
      _windowExpired = false;
      isScheduleArmed = true;
      nextScheduledRun = null;

      final startLabel = _formatTime24(runTime);
      final endLabel = _formatTime24(runEndTime);
      final endFmt = DateFormat('dd/MM/yyyy HH:mm').format(activeWindow.end);
      currentStatus =
          '⏰ Inside schedule window ($startLabel – $endLabel). Starting...';
      _addLog(
        '⏰ Inside active run window ($startLabel – $endLabel). Starting upload immediately (stops at $endFmt)...',
      );
      notifyListeners();

      _ensureScheduleTimerRunning();
      unawaited(
        _executeUploadPass(isScheduledRun: true, windowEnd: activeWindow.end),
      );
      return;
    }

    final next = computeNextScheduledRun(
      now: now,
      runTime: runTime,
      runDays: runDays,
    );
    if (next == null) {
      _addLog('⚠️ Select at least one weekday before starting the schedule.');
      notifyListeners();
      return;
    }

    _stopRequested = false;
    _windowExpired = false;
    isScheduleArmed = true;
    nextScheduledRun = next;

    final formatted = DateFormat('dd/MM/yyyy HH:mm').format(next);
    final windowSuffix = hasEndTimeLimit
        ? ' (until ${_formatTime24(runEndTime)})'
        : '';
    currentStatus = '⏰ Scheduled — Next run: $formatted$windowSuffix';
    _addLog('⏰ Schedule armed. Waiting for $formatted$windowSuffix...');
    notifyListeners();

    _ensureScheduleTimerRunning();
  }

  void _ensureScheduleTimerRunning() {
    _scheduleTimer?.cancel();
    _scheduleTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _checkScheduleTick();
    });
  }

  Future<void> _checkScheduleTick() async {
    if (isUploading && !_stopRequested) {
      _checkWindowExpiration();
      return;
    }
    if (!isScheduleArmed || _stopRequested) return;
    final dueAt = nextScheduledRun;
    if (dueAt == null) return;

    final now = _nowProvider();
    if (!now.isBefore(dueAt)) {
      final windowEnd = computeWindowEnd(
        windowStart: dueAt,
        runTime: runTime,
        runEndTime: runEndTime,
      );
      if (windowEnd != null && !now.isBefore(windowEnd)) {
        final missedFmt = DateFormat('dd/MM/yyyy HH:mm').format(dueAt);
        final endFmt = DateFormat('dd/MM/yyyy HH:mm').format(windowEnd);
        _addLog('⏭ Missed scheduled window ($missedFmt – $endFmt).');
        nextScheduledRun = null;

        if (onCompletionAction == 'repeat' &&
            enableSchedule &&
            hasCheckedScheduleDays) {
          final activeNow = computeActiveWindow(
            now: now,
            runTime: runTime,
            runEndTime: runEndTime,
            runDays: runDays,
          );
          if (activeNow != null) {
            _addLog(
              '⏰ Inside current run window (${_formatTime24(runTime)} – ${_formatTime24(runEndTime)}). Starting upload...',
            );
            await _executeUploadPass(
              isScheduledRun: true,
              windowEnd: activeNow.end,
            );
            return;
          }

          final next = computeNextScheduledRun(
            now: now,
            runTime: runTime,
            runDays: runDays,
          );
          nextScheduledRun = next;
          if (next != null) {
            final formatted = DateFormat('dd/MM/yyyy HH:mm').format(next);
            final windowSuffix = hasEndTimeLimit
                ? ' (until ${_formatTime24(runEndTime)})'
                : '';
            currentStatus = '⏰ Scheduled — Next run: $formatted$windowSuffix';
            _addLog('⏰ Rescheduled for next window: $formatted$windowSuffix.');
          } else {
            isScheduleArmed = false;
            _scheduleTimer?.cancel();
            _scheduleTimer = null;
            currentStatus = '⏭ Missed scheduled window';
          }
        } else {
          isScheduleArmed = false;
          _scheduleTimer?.cancel();
          _scheduleTimer = null;
          currentStatus = '⏭ Missed scheduled window';
        }
        notifyListeners();
        return;
      }

      nextScheduledRun = null;
      final stopSuffix = windowEnd != null
          ? ' — stops at ${_formatTime24(runEndTime)}'
          : '';
      _addLog(
        '⏳ Scheduled run time reached (${DateFormat('dd/MM/yyyy HH:mm').format(dueAt)}$stopSuffix). Starting upload...',
      );
      await _executeUploadPass(isScheduledRun: true, windowEnd: windowEnd);
    }
  }

  @visibleForTesting
  Future<void> triggerScheduleTickForTest() => _checkScheduleTick();

  Future<void> runNow() async {
    if (!canRunNow) return;
    await _executeUploadPass(isScheduledRun: false);
  }

  void stop() {
    if (!isProcessing) return;
    _stopRequested = true;
    _windowExpired = false;
    _activeRunWindowEnd = null;
    _scheduleTimer?.cancel();
    _scheduleTimer = null;
    isScheduleArmed = false;
    nextScheduledRun = null;

    if (isUploading) {
      currentStatus = '⛔ Stopping...';
      _addLog('⛔ Stop requested by user. Closing active FTP connection...');
      unawaited(_activeClient?.disconnect());
    } else {
      currentStatus = '⛔ Stopped';
      _addLog('⛔ FTP schedule stopped by user.');
    }
    notifyListeners();
  }

  // --- Upload Engine ---

  //   List<FtpUploadSource> _getOrderedSources() {
  //     if (!useMultipleSources) {
  //       return [
  //         FtpUploadSource(
  //           name: 'Default',
  //           localPath: sourcePath,
  //           subfolders: subfolders,
  //           ftpDest: remoteDirectory,
  //           runOrder: 1,
  //         ),
  //       ];
  //     }
  //
  //     final valid = uploadSources.where((s) => s.isValid).toList();
  //     // Sort stably by runOrder while preserving insertion order for ties.
  //     final indexed = valid.asMap().entries.toList()
  //       ..sort((a, b) {
  //         final cmp = a.value.runOrder.compareTo(b.value.runOrder);
  //         return cmp != 0 ? cmp : a.key.compareTo(b.key);
  //       });
  //     return indexed.map((e) => e.value).toList();
  //   }
  // Gene - Nov, 23, 2026: Skip disabled multi-source entries while preserving runOrder sorting.
  List<FtpUploadSource> _getOrderedSources() {
    if (!useMultipleSources) {
      return [
        FtpUploadSource(
          name: 'Default',
          localPath: sourcePath,
          subfolders: subfolders,
          ftpDest: remoteDirectory,
          runOrder: 1,
        ),
      ];
    }

    final valid = uploadSources.where((s) => s.enabled && s.isValid).toList();
    // Sort stably by runOrder while preserving insertion order for ties.
    final indexed = valid.asMap().entries.toList()
      ..sort((a, b) {
        final cmp = a.value.runOrder.compareTo(b.value.runOrder);
        return cmp != 0 ? cmp : a.key.compareTo(b.key);
      });
    return indexed.map((e) => e.value).toList();
  }

  Future<List<_SubfolderWorkItem>> _buildWorkItems(
    FtpUploadSource source,
  ) async {
    final basePath = source.localPath!.trim();
    final baseDir = Directory(basePath);
    if (!await baseDir.exists()) {
      _addLog('❌ Source directory not found: $basePath');
      await _fileLogger.error('FTP', 'Source directory not found: $basePath');
      errors++;
      return [];
    }

    final selectedSubs = source.parsedSubfolders;
    final items = <_SubfolderWorkItem>[];

    if (selectedSubs.isNotEmpty) {
      for (final rawSub in selectedSubs) {
        final subParts = rawSub
            .replaceAll(r'\', '/')
            .split('/')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty && s != '.' && s != '..')
            .toList();
        if (subParts.isEmpty) continue;

        final subLocalPath = p.joinAll([basePath, ...subParts]);
        final subDir = Directory(subLocalPath);
        if (!await subDir.exists()) {
          _addLog('⚠️ Subfolder not found: $subLocalPath');
          await _fileLogger.error('FTP', 'Subfolder not found: $subLocalPath');
          errors++;
          continue;
        }
        if (!await resolvesWithinRoot(basePath, subLocalPath)) {
          _addLog('⚠️ Skipped symlink outside source root: $subLocalPath');
          continue;
        }

        final remoteBase = joinRemotePath(source.ftpDest, subParts.join('/'));
        if (!includeSubfolders) {
          items.add(
            _SubfolderWorkItem(
              rootPath: basePath,
              localDir: subLocalPath,
              remoteDir: remoteBase,
            ),
          );
        } else {
          await _collectDirectoriesIterative(
            rootPath: basePath,
            startDir: subLocalPath,
            remotePrefix: remoteBase,
            out: items,
          );
        }
      }
      return items;
    }

    final remoteBase = joinRemotePath(source.ftpDest, '');
    if (!includeSubfolders) {
      items.add(
        _SubfolderWorkItem(
          rootPath: basePath,
          localDir: basePath,
          remoteDir: remoteBase,
        ),
      );
    } else {
      await _collectDirectoriesIterative(
        rootPath: basePath,
        startDir: basePath,
        remotePrefix: remoteBase,
        out: items,
      );
    }
    return items;
  }

  Future<void> _collectDirectoriesIterative({
    required String rootPath,
    required String startDir,
    required String remotePrefix,
    required List<_SubfolderWorkItem> out,
  }) async {
    final queue = <String>[startDir];
    //     while (queue.isNotEmpty && !_stopRequested) {
    // Gene - Nov, 24, 2026: Abort iterative directory scan when scheduled end time is reached.
    while (queue.isNotEmpty && !_shouldAbortPass && !_checkWindowExpiration()) {
      final currentPath = queue.removeAt(0);
      final rel = p.relative(currentPath, from: startDir);
      final mappedRemote = (rel == '.' || rel.isEmpty)
          ? remotePrefix
          : joinRemotePath(remotePrefix, rel);
      out.add(
        _SubfolderWorkItem(
          rootPath: rootPath,
          localDir: currentPath,
          remoteDir: mappedRemote,
        ),
      );

      try {
        await for (final entity in Directory(
          currentPath,
        ).list(recursive: false, followLinks: false)) {
          //           if (_stopRequested) break;
          // Gene - Nov, 24, 2026: Abort directory listing on stop or run-window expiration.
          if (_shouldAbortPass || _checkWindowExpiration()) break;
          if (entity is Directory) {
            if (await resolvesWithinRoot(rootPath, entity.path)) {
              queue.add(entity.path);
            }
          }
        }
      } catch (e) {
        final safeErr = CredentialObfuscator.redact(e.toString(), password);
        _addLog('⚠️ Unable to list directory $currentPath: $safeErr');
        await _fileLogger.error(
          'FTP',
          'Unable to list directory $currentPath: $safeErr',
        );
        errors++;
      }
    }
  }

  //   Future<List<_QueuedUploadFile>> _scanSubfolderFiles(
  //     _SubfolderWorkItem item,
  //     DateTime referenceNow,
  //   ) async {
  //     final candidateFiles = <File>[];
  //     final statsByPath = <String, FileStat>{};
  //
  //     try {
  //       await for (final entity in Directory(
  //         item.localDir,
  //       ).list(recursive: false, followLinks: false)) {
  //         if (_stopRequested) break;
  //         if (entity is File) {
  //           if (!await resolvesWithinRoot(item.rootPath, entity.path)) {
  //             continue;
  //           }
  //           try {
  //             final stats = await entity.stat();
  //             if (stats.type == FileSystemEntityType.file) {
  //               candidateFiles.add(entity);
  //               statsByPath[entity.path] = stats;
  //             }
  //           } catch (e) {
  //             errors++;
  //             _addLog('⚠️ Failed to stat ${entity.path}: $e');
  //           }
  //         }
  //       }
  //     } catch (e) {
  //       errors++;
  //       final safeErr = CredentialObfuscator.redact(e.toString(), password);
  //       _addLog('⚠️ Failed scanning ${item.localDir}: $safeErr');
  //       await _fileLogger.error(
  //         'FTP',
  //         'Failed scanning ${item.localDir}: $safeErr',
  //       );
  //       return [];
  //     }
  //
  //     if (candidateFiles.isEmpty) return [];
  //
  //     Map<String, DateTime> creationDates = const {};
  //     if (dateType == FtpDateType.creation) {
  //       creationDates = await getCreationDatesForFiles(
  //         candidateFiles,
  //         statsByPath,
  //       );
  //     }
  //
  //     final matched = <_QueuedUploadFile>[];
  //     for (final file in candidateFiles) {
  //       if (_stopRequested) break;
  //       final stats = statsByPath[file.path]!;
  //       filesChecked++;
  //       final fileDate = dateType == FtpDateType.creation
  //           ? (creationDates[file.path] ?? stats.changed)
  //           : stats.modified;
  //
  //       if (matchesDateFilter(
  //         fileDate: fileDate,
  //         dateMode: dateMode,
  //         referenceNow: referenceNow,
  //         daysAgo: daysAgo,
  //         specificDate: specificDate,
  //         fromDate: fromDate,
  //         toDate: toDate,
  //       )) {
  //         matched.add(_QueuedUploadFile(file: file, size: stats.size));
  //       }
  //     }
  //     return matched;
  //   }
  // Gene - Nov, 23, 2026: Return per-subfolder checked counts alongside matched files for clearer audit logs.
  Future<_SubfolderScanResult> _scanSubfolderFiles(
    _SubfolderWorkItem item,
    DateTime referenceNow,
  ) async {
    final candidateFiles = <File>[];
    final statsByPath = <String, FileStat>{};

    try {
      await for (final entity in Directory(
        item.localDir,
      ).list(recursive: false, followLinks: false)) {
        //         if (_stopRequested) break;
        // Gene - Nov, 24, 2026: Abort file scan on stop or run-window expiration.
        if (_shouldAbortPass || _checkWindowExpiration()) break;
        if (entity is File) {
          if (!await resolvesWithinRoot(item.rootPath, entity.path)) {
            continue;
          }
          try {
            final stats = await entity.stat();
            if (stats.type == FileSystemEntityType.file) {
              candidateFiles.add(entity);
              statsByPath[entity.path] = stats;
            }
          } catch (e) {
            errors++;
            _addLog('⚠️ Failed to stat ${entity.path}: $e');
          }
        }
      }
    } catch (e) {
      errors++;
      final safeErr = CredentialObfuscator.redact(e.toString(), password);
      _addLog('⚠️ Failed scanning ${item.localDir}: $safeErr');
      await _fileLogger.error(
        'FTP',
        'Failed scanning ${item.localDir}: $safeErr',
      );
      return const _SubfolderScanResult(checkedCount: 0, matched: []);
    }

    if (candidateFiles.isEmpty) {
      return const _SubfolderScanResult(checkedCount: 0, matched: []);
    }

    Map<String, DateTime> creationDates = const {};
    if (dateType == FtpDateType.creation) {
      creationDates = await getCreationDatesForFiles(
        candidateFiles,
        statsByPath,
      );
    }

    int checkedInFolder = 0;
    final matched = <_QueuedUploadFile>[];
    for (final file in candidateFiles) {
      //       if (_stopRequested) break;
      // Gene - Nov, 24, 2026: Abort date-filter scan loop on stop or run-window expiration.
      if (_shouldAbortPass || _checkWindowExpiration()) break;
      final stats = statsByPath[file.path]!;
      checkedInFolder++;
      filesChecked++;
      final fileDate = dateType == FtpDateType.creation
          ? (creationDates[file.path] ?? stats.changed)
          : stats.modified;

      if (matchesDateFilter(
        fileDate: fileDate,
        dateMode: dateMode,
        referenceNow: referenceNow,
        daysAgo: daysAgo,
        specificDate: specificDate,
        fromDate: fromDate,
        toDate: toDate,
      )) {
        matched.add(_QueuedUploadFile(file: file, size: stats.size));
      }
    }
    return _SubfolderScanResult(
      checkedCount: checkedInFolder,
      matched: matched,
    );
  }

  //   Future<void> _executeUploadPass({required bool isScheduledRun}) async {
  //     if (isUploading) return;
  //
  //     _stopRequested = false;
  //     isUploading = true;
  //     filesUploaded = 0;
  //     filesSkipped = 0;
  //     filesChecked = 0;
  //     errors = 0;
  //
  //     final startTime = _nowProvider();
  //     final runRefNow = startTime;
  //     final config = connectionConfig;
  //     final sources = _getOrderedSources();
  //
  //     currentStatus = dryRun
  //         ? '🧪 Dry run: connecting to ${config.host}...'
  //         : '🔌 Connecting to ${config.host}...';
  //
  //     final sourceSummary = useMultipleSources
  //         ? '${sources.length} sources (${sources.first.displayName}...)'
  //         : (sourcePath ?? '');
  //     final endpointSummary = useMultipleSources
  //         ? config.displayEndpoint()
  //         : config.displayEndpoint(remoteDirectory);
  //
  //     await _fileLogger.logRunStart(
  //       operation: 'FTP',
  //       sourcePath: sourceSummary,
  //       destPath: endpointSummary,
  //     );
  //
  //     _addLog(
  //       dryRun
  //           ? '🧪 Starting DRY RUN -> $endpointSummary (Mode: ${dateMode.label}, Date: ${dateType.label})'
  //           : '🚀 Starting FTP upload -> $endpointSummary (Mode: ${dateMode.label}, Date: ${dateType.label})',
  //     );
  //     notifyListeners();
  //
  //     bool hadFatalError = false;
  //     int foldersProcessed = 0;
  //     FtpClientAdapter? client;
  //
  //     try {
  //       final needsConnection = !dryRun || skipIfExists;
  //       if (needsConnection) {
  //         client = _clientFactory(config);
  //         _activeClient = client;
  //         await client.connect();
  //         _addLog('✅ Connected to ${config.displayEndpoint()}');
  //         await _fileLogger.info(
  //           'FTP',
  //           'Connected to ${config.displayEndpoint()}',
  //         );
  //       }
  //
  //       for (final source in sources) {
  //         if (_stopRequested) break;
  //         final workItems = await _buildWorkItems(source);
  //
  //         for (final workItem in workItems) {
  //           if (_stopRequested) break;
  //           foldersProcessed++;
  //           currentStatus = dryRun
  //               ? '🧪 Scanning ${p.basename(workItem.localDir)}...'
  //               : '⏳ Scanning ${p.basename(workItem.localDir)}...';
  //           notifyListeners();
  //
  //           // Step A: Local scan of current subfolder.
  //           final miniQueue = await _scanSubfolderFiles(workItem, runRefNow);
  //           if (miniQueue.isEmpty || _stopRequested) {
  //             continue;
  //           }
  //
  //           final remoteDisplay = workItem.remoteDir.isEmpty
  //               ? '/'
  //               : '/${workItem.remoteDir.startsWith('/') ? workItem.remoteDir.substring(1) : workItem.remoteDir}';
  //           _addLog(
  //             '📂 ${workItem.localDir} -> ${miniQueue.length} file(s) matched (target: $remoteDisplay)',
  //           );
  //           await _fileLogger.info(
  //             'FTP',
  //             '${workItem.localDir} -> ${miniQueue.length} matched for $remoteDisplay',
  //           );
  //
  //           // Step B: Prepare remote directory and upload mini queue immediately.
  //           Map<String, int?>? remoteSizes;
  //           if (needsConnection && client == null) {
  //             client = _clientFactory(config);
  //             _activeClient = client;
  //             await client.connect();
  //           }
  //           if (client != null) {
  //             if (!dryRun) {
  //               final dirReady = await client.ensureRemoteDirectory(
  //                 workItem.remoteDir,
  //               );
  //               if (!dirReady) {
  //                 errors++;
  //                 final msg =
  //                     '❌ Cannot access or create remote directory "$remoteDisplay"';
  //                 _addLog(msg);
  //                 await _fileLogger.error('FTP', msg);
  //                 continue;
  //               }
  //               if (skipIfExists) {
  //                 remoteSizes = await client.listRemoteFileSizes();
  //               }
  //             } else if (skipIfExists) {
  //               final dirExists = await client.changeDirectory(
  //                 workItem.remoteDir,
  //               );
  //               remoteSizes = dirExists
  //                   ? await client.listRemoteFileSizes()
  //                   : <String, int?>{};
  //             }
  //           }
  //
  //           for (final item in miniQueue) {
  //             if (_stopRequested) break;
  //             final fileName = p.basename(item.file.path);
  //
  //             if (skipIfExists && client != null) {
  //               bool existsRemotely = false;
  //               int? existingSize;
  //
  //               if (remoteSizes != null) {
  //                 existsRemotely = remoteSizes.containsKey(fileName);
  //                 existingSize = remoteSizes[fileName];
  //                 if (existsRemotely && existingSize == null) {
  //                   existingSize = await client.getRemoteFileSize(fileName);
  //                 }
  //               } else {
  //                 existingSize = await client.getRemoteFileSize(fileName);
  //                 existsRemotely = existingSize != null;
  //               }
  //
  //               if (existsRemotely) {
  //                 if (existingSize == item.size) {
  //                   filesSkipped++;
  //                   final skipMsg = dryRun
  //                       ? '🧪 [DRY RUN] Would skip (already on FTP): $fileName'
  //                       : '⏭ Skipped (already on FTP): $fileName';
  //                   if (dryRun ||
  //                       logInterval <= 1 ||
  //                       filesSkipped % logInterval == 0) {
  //                     _addLog(skipMsg);
  //                   }
  //                   await _fileLogger.info('FTP', skipMsg);
  //                   notifyListeners();
  //                   continue;
  //                 } else {
  //                   final diffMsg = dryRun
  //                       ? '🧪 [DRY RUN] Would re-upload (size differs: remote=${existingSize ?? "?"}, local=${item.size}): $fileName'
  //                       : '🔄 Size differs (remote=${existingSize ?? "?"}, local=${item.size}) — re-uploading: $fileName';
  //                   _addLog(diffMsg);
  //                   await _fileLogger.info('FTP', diffMsg);
  //                 }
  //               }
  //             }
  //
  //             if (dryRun) {
  //               filesUploaded++;
  //               final dryMsg =
  //                   '🧪 [DRY RUN] Would upload: $fileName (${_numFmt.format(item.size)} bytes) -> $remoteDisplay';
  //               _addLog(dryMsg);
  //               await _fileLogger.info('FTP', dryMsg);
  //               notifyListeners();
  //               continue;
  //             }
  //
  //             currentStatus = '⬆️ Uploading $fileName...';
  //             notifyListeners();
  //
  //             final maxAttempts = retryCount.clamp(1, 10);
  //             for (int attempt = 1; attempt <= maxAttempts; attempt++) {
  //               if (_stopRequested) break;
  //               try {
  //                 if (client == null) {
  //                   final freshClient = _clientFactory(config);
  //                   _activeClient = freshClient;
  //                   await freshClient.connect();
  //                   final dirOk = await freshClient.ensureRemoteDirectory(
  //                     workItem.remoteDir,
  //                   );
  //                   if (!dirOk) {
  //                     await freshClient.disconnect();
  //                     throw Exception(
  //                       'Failed to enter remote folder "$remoteDisplay" after reconnect',
  //                     );
  //                   }
  //                   client = freshClient;
  //                 }
  //
  //                 final uploaded = await client.uploadFile(
  //                   item.file,
  //                   remoteName: fileName,
  //                 );
  //                 if (!uploaded) {
  //                   throw Exception('Server rejected upload of $fileName');
  //                 }
  //
  //                 if (verifySizeAfterUpload) {
  //                   final remoteSize = await client.getRemoteFileSize(fileName);
  //                   if (remoteSize != null &&
  //                       remoteSize >= 0 &&
  //                       remoteSize != item.size) {
  //                     throw Exception(
  //                       'Size verification mismatch for $fileName (local=${item.size}, remote=$remoteSize)',
  //                     );
  //                   }
  //                 }
  //
  //                 filesUploaded++;
  //                 if (logInterval <= 1 || filesUploaded % logInterval == 0) {
  //                   _addLog(
  //                     '✅ Uploaded ($filesUploaded): $fileName (${_numFmt.format(item.size)} bytes)',
  //                   );
  //                 }
  //                 await _fileLogger.info(
  //                   'FTP',
  //                   'Uploaded $fileName (${item.size} bytes) to $remoteDisplay',
  //                 );
  //                 notifyListeners();
  //                 break;
  //               } catch (e) {
  //                 if (_stopRequested) break;
  //                 final safeErr = CredentialObfuscator.redact(
  //                   e.toString(),
  //                   password,
  //                 );
  //
  //                 if (attempt < maxAttempts) {
  //                   final warnMsg =
  //                       '⚠️ Attempt $attempt/$maxAttempts failed for $fileName: $safeErr. Retrying in ${retryDelaySeconds}s...';
  //                   _addLog(warnMsg);
  //                   await _fileLogger.error('FTP', warnMsg);
  //                   notifyListeners();
  //
  //                   await _cancellableDelay(Duration(seconds: retryDelaySeconds));
  //                   if (_stopRequested) break;
  //
  //                   // Reconnect before retrying in case the socket dropped mid-transfer.
  //                   await client?.disconnect();
  //                   client = null;
  //                   _activeClient = null;
  //                   try {
  //                     final nextClient = _clientFactory(config);
  //                     _activeClient = nextClient;
  //                     await nextClient.connect();
  //                     final dirOk = await nextClient.ensureRemoteDirectory(
  //                       workItem.remoteDir,
  //                     );
  //                     if (!dirOk) {
  //                       await nextClient.disconnect();
  //                       throw Exception(
  //                         'Failed to re-enter remote folder "$remoteDisplay" after reconnect',
  //                       );
  //                     }
  //                     client = nextClient;
  //                   } catch (reconnectErr) {
  //                     final safeReconnectErr = CredentialObfuscator.redact(
  //                       reconnectErr.toString(),
  //                       password,
  //                     );
  //                     final reconnectMsg =
  //                         '⚠️ Reconnect failed before attempt ${attempt + 1}: $safeReconnectErr';
  //                     _addLog(reconnectMsg);
  //                     await _fileLogger.error('FTP', reconnectMsg);
  //                     client = null;
  //                     _activeClient = null;
  //                   }
  //                 } else {
  //                   errors++;
  //                   final failMsg =
  //                       '❌ Failed uploading $fileName after $maxAttempts attempt(s): $safeErr';
  //                   _addLog(failMsg);
  //                   await _fileLogger.error('FTP', failMsg);
  //                   notifyListeners();
  //                 }
  //               }
  //             }
  //           }
  //         }
  //       }
  //     } catch (e, stack) {
  //       if (!_stopRequested) {
  //         hadFatalError = true;
  //         errors++;
  //         final safeErr = CredentialObfuscator.redact(e.toString(), password);
  //         _log.severe('FTP upload critical error: $safeErr', stack);
  //         _addLog('❌ FTP Error: $safeErr');
  //         await _fileLogger.error('FTP', 'Critical Error: $safeErr');
  //       }
  //     } finally {
  //       _activeClient = null;
  //       await client?.disconnect();
  //       isUploading = false;
  //
  //       final endTime = _nowProvider();
  //       final runId = _fileLogger.getRunId('FTP') ?? 'RUN-FTP';
  //       await _fileLogger.logRunEnd(
  //         operation: 'FTP',
  //         filesProcessed: filesUploaded,
  //         errors: errors,
  //         wasStopped: _stopRequested,
  //       );
  //
  //       final statusLabel = _stopRequested
  //           ? 'Stopped'
  //           : (hadFatalError ? 'Error' : 'Completed');
  //       final summaryPrefix = dryRun ? '[DRY RUN] ' : '';
  //       final configSummary =
  //           '$summaryPrefix${config.protocol.shortLabel} | Date: ${dateMode.label} (${dateType.label}) | Checked: ${_numFmt.format(filesChecked)} | Skipped: ${_numFmt.format(filesSkipped)}';
  //
  //       await HistoryService().saveRecord(
  //         RunRecord(
  //           id: runId,
  //           operation: 'FTP',
  //           startTime: startTime,
  //           endTime: endTime,
  //           filesProcessed: filesUploaded,
  //           foldersProcessed: foldersProcessed,
  //           errors: errors,
  //           status: statusLabel,
  //           configSummary: configSummary,
  //           sourcePath: sourceSummary,
  //           destPath: endpointSummary,
  //         ),
  //       );
  //
  //       if (_stopRequested) {
  //         _scheduleTimer?.cancel();
  //         _scheduleTimer = null;
  //         isScheduleArmed = false;
  //         nextScheduledRun = null;
  //         currentStatus = '⛔ Stopped';
  //         _addLog(
  //           '⛔ Run stopped. Uploaded: ${_numFmt.format(filesUploaded)}, Skipped: ${_numFmt.format(filesSkipped)}, Errors: ${_numFmt.format(errors)}.',
  //         );
  //       } else if (isScheduledRun) {
  //         if (onCompletionAction == 'repeat' &&
  //             enableSchedule &&
  //             hasCheckedScheduleDays) {
  //           final next = computeNextScheduledRun(
  //             now: _nowProvider(),
  //             runTime: runTime,
  //             runDays: runDays,
  //           );
  //           nextScheduledRun = next;
  //           if (next != null) {
  //             final formatted = DateFormat('dd/MM/yyyy HH:mm').format(next);
  //             currentStatus = '🏁 Completed. Next run at $formatted';
  //             _addLog(
  //               '🏁 ${dryRun ? "Dry run" : "Upload"} complete (Uploaded: $filesUploaded, Skipped: $filesSkipped, Errors: $errors). Next scheduled run: $formatted.',
  //             );
  //             _ensureScheduleTimerRunning();
  //           } else {
  //             isScheduleArmed = false;
  //             _scheduleTimer?.cancel();
  //             _scheduleTimer = null;
  //             currentStatus = hadFatalError ? '❌ Error' : '✅ Completed';
  //           }
  //         } else {
  //           isScheduleArmed = false;
  //           nextScheduledRun = null;
  //           _scheduleTimer?.cancel();
  //           _scheduleTimer = null;
  //           currentStatus = hadFatalError ? '❌ Error' : '✅ Completed';
  //           _addLog(
  //             '✅ Scheduled ${dryRun ? "dry run" : "upload"} complete (Uploaded: $filesUploaded, Skipped: $filesSkipped, Errors: $errors).',
  //           );
  //         }
  //       } else {
  //         if (isScheduleArmed) {
  //           final next = computeNextScheduledRun(
  //             now: _nowProvider(),
  //             runTime: runTime,
  //             runDays: runDays,
  //           );
  //           nextScheduledRun = next;
  //           if (next != null) {
  //             final formatted = DateFormat('dd/MM/yyyy HH:mm').format(next);
  //             currentStatus = '⏰ Scheduled — Next run: $formatted';
  //             _addLog(
  //               '✅ Manual run finished (Uploaded: $filesUploaded, Skipped: $filesSkipped, Errors: $errors). Schedule remains armed for $formatted.',
  //             );
  //           }
  //         } else {
  //           currentStatus = hadFatalError
  //               ? '❌ Error'
  //               : (dryRun ? '✅ Dry Run Completed' : '✅ Completed');
  //           _addLog(
  //             '✅ ${dryRun ? "Dry run" : "Upload"} finished! Checked: $filesChecked, Uploaded: $filesUploaded, Skipped: $filesSkipped, Errors: $errors.',
  //           );
  //         }
  //       }
  //
  //       notifyListeners();
  //     }
  //   }
  // Gene - Nov, 23, 2026: Added log retention pruning, audit date/scan logging, lazy connect + idle reconnect recovery, live progress, SIZE warning, and error status tracking.
  Future<({bool ok, Map<String, int?>? sizes})> _prepareRemoteFolder(
    FtpClientAdapter activeClient,
    String remoteDir,
  ) async {
    if (!dryRun) {
      final dirReady = await activeClient.ensureRemoteDirectory(remoteDir);
      if (!dirReady) {
        return (ok: false, sizes: null);
      }
      final sizes = skipIfExists
          ? await activeClient.listRemoteFileSizes()
          : null;
      return (ok: true, sizes: sizes);
    } else if (skipIfExists) {
      final dirExists = await activeClient.changeDirectory(remoteDir);
      final sizes = dirExists
          ? await activeClient.listRemoteFileSizes()
          : <String, int?>{};
      return (ok: true, sizes: sizes);
    }
    return (ok: true, sizes: null);
  }

  //   Future<void> _executeUploadPass({required bool isScheduledRun}) async {
  //     if (isUploading) return;
  //
  //     _stopRequested = false;
  //     isUploading = true;
  // Gene - Nov, 24, 2026: Accept optional windowEnd for scheduled runs to enforce end-time cutoff.
  Future<void> _executeUploadPass({
    required bool isScheduledRun,
    DateTime? windowEnd,
  }) async {
    if (isUploading) return;

    _stopRequested = false;
    _windowExpired = false;
    _activeRunWindowEnd = isScheduledRun ? windowEnd : null;
    isUploading = true;
    filesUploaded = 0;
    filesSkipped = 0;
    filesChecked = 0;
    errors = 0;
    _clearActiveUploadProgress();

    final startTime = _nowProvider();
    final runRefNow = startTime;
    final config = connectionConfig;
    final sources = _getOrderedSources();

    currentStatus = dryRun
        ? '🧪 Dry run: scanning sources...'
        : '⏳ Scanning sources...';

    final sourceSummary = useMultipleSources
        ? (sources.isEmpty
              ? '0 active sources'
              : '${sources.length} sources (${sources.first.displayName}...)')
        : (sourcePath ?? '');
    final endpointSummary = useMultipleSources
        ? config.displayEndpoint()
        : config.displayEndpoint(remoteDirectory);

    await _fileLogger.logRunStart(
      operation: 'FTP',
      sourcePath: sourceSummary,
      destPath: endpointSummary,
    );

    final prunedLogs = await _fileLogger.pruneOldLogs(
      keepDays: logKeepDays,
      operationPrefix: 'FTP',
      now: startTime,
    );
    if (prunedLogs > 0) {
      final pruneMsg =
          '🧹 Pruned $prunedLogs old FTP log file(s) older than $logKeepDays day(s).';
      _addLog(pruneMsg);
      await _fileLogger.info('FTP', pruneMsg);
    }

    _addLog(
      dryRun
          ? '🧪 Starting DRY RUN -> $endpointSummary (Mode: ${dateMode.label}, Date: ${dateType.label})'
          : '🚀 Starting FTP upload -> $endpointSummary (Mode: ${dateMode.label}, Date: ${dateType.label})',
    );

    final resolvedDateDesc = describeTargetDate(
      dateMode: dateMode,
      referenceNow: runRefNow,
      daysAgo: daysAgo,
      specificDate: specificDate,
      fromDate: fromDate,
      toDate: toDate,
    );
    final targetDateMsg =
        '📅 Target date resolved to: $resolvedDateDesc (${dateType.label})';
    _addLog(targetDateMsg);
    await _fileLogger.info('FTP', targetDateMsg);

    if (useMultipleSources) {
      final disabledCount = uploadSources
          .where((s) => !s.enabled && s.isValid)
          .length;
      if (disabledCount > 0) {
        final skipSrcMsg =
            '⏭ Skipping $disabledCount disabled upload source(s).';
        _addLog(skipSrcMsg);
        await _fileLogger.info('FTP', skipSrcMsg);
      }
    }
    // Gene - Nov, 24, 2026: Log active scheduled run window bounds at start of pass.
    if (isScheduledRun && _activeRunWindowEnd != null) {
      final windowMsg =
          '⏰ Active run window: ${_formatTime24(runTime)} – ${_formatTime24(runEndTime)} (stops at ${DateFormat('dd/MM/yyyy HH:mm').format(_activeRunWindowEnd!)})';
      _addLog(windowMsg);
      await _fileLogger.info('FTP', windowMsg);
    }
    notifyListeners();

    bool hadFatalError = false;
    int foldersProcessed = 0;
    FtpClientAdapter? client;

    try {
      final needsConnection = !dryRun || skipIfExists;

      for (final source in sources) {
        //         if (_stopRequested) break;
        // Gene - Nov, 24, 2026: Stop upload pass when user stops or scheduled run window ends.
        if (_shouldAbortPass || _checkWindowExpiration()) break;

        final subFilterLabel = source.parsedSubfolders.isEmpty
            ? (includeSubfolders ? 'ALL (nested)' : 'Root only')
            : source.parsedSubfolders.join(', ');
        final destLabel = source.ftpDest.trim().isEmpty
            ? '/'
            : '/${joinRemotePath(source.ftpDest, '').replaceFirst(RegExp(r'^/'), '')}';
        _addLog(
          '─── Source: ${source.displayName} (${source.localPath}) [Subfolders: $subFilterLabel -> $destLabel] ───',
        );
        await _fileLogger.info(
          'FTP',
          'Source ${source.displayName} (${source.localPath}) | Subfolders: $subFilterLabel | Dest: $destLabel',
        );

        final workItems = await _buildWorkItems(source);

        for (final workItem in workItems) {
          //           if (_stopRequested) break;
          // Gene - Nov, 24, 2026: Stop work-item loop on stop or run-window expiration.
          if (_shouldAbortPass || _checkWindowExpiration()) break;
          foldersProcessed++;
          currentStatus = dryRun
              ? '🧪 Scanning ${p.basename(workItem.localDir)}...'
              : '⏳ Scanning ${p.basename(workItem.localDir)}...';
          notifyListeners();

          // Step A: Local scan of current subfolder.
          final scanResult = await _scanSubfolderFiles(workItem, runRefNow);
          //           if (_stopRequested) break;
          // Gene - Nov, 24, 2026: Stop before connecting or uploading if scan aborted by stop or window end.
          if (_shouldAbortPass || _checkWindowExpiration()) break;

          final miniQueue = scanResult.matched;
          if (miniQueue.isEmpty) {
            final emptyMsg =
                '📂 ${workItem.localDir} -> ${scanResult.checkedCount} checked, 0 matched — skipping';
            _addLog(emptyMsg);
            await _fileLogger.info('FTP', emptyMsg);
            continue;
          }

          final remoteDisplay = workItem.remoteDir.isEmpty
              ? '/'
              : '/${workItem.remoteDir.startsWith('/') ? workItem.remoteDir.substring(1) : workItem.remoteDir}';
          _addLog(
            '📂 ${workItem.localDir} -> ${scanResult.checkedCount} checked, ${miniQueue.length} matched (target: $remoteDisplay)',
          );
          await _fileLogger.info(
            'FTP',
            '${workItem.localDir} -> ${scanResult.checkedCount} checked, ${miniQueue.length} matched for $remoteDisplay',
          );

          // Step B: Connect lazily if needed, prepare remote directory (with 1-time reconnect recovery), and upload immediately.
          Map<String, int?>? remoteSizes;
          if (needsConnection) {
            if (client == null) {
              currentStatus = dryRun
                  ? '🧪 Dry run: connecting to ${config.host}...'
                  : '🔌 Connecting to ${config.host}...';
              notifyListeners();
              client = _clientFactory(config);
              _activeClient = client;
              await client.connect();
              _addLog('✅ Connected to ${config.displayEndpoint()}');
              await _fileLogger.info(
                'FTP',
                'Connected to ${config.displayEndpoint()}',
              );
            }

            bool folderReady = false;
            try {
              final prep = await _prepareRemoteFolder(
                client,
                workItem.remoteDir,
              );
              if (!prep.ok) {
                throw Exception(
                  'Cannot access or create remote directory "$remoteDisplay"',
                );
              }
              remoteSizes = prep.sizes;
              folderReady = true;
            } catch (dirErr) {
              //               if (_stopRequested) break;
              // Gene - Nov, 24, 2026: Break cleanly without reconnect or error when aborted by stop or window end.
              if (_shouldAbortPass || _checkWindowExpiration()) break;
              final safeDirErr = CredentialObfuscator.redact(
                dirErr.toString(),
                password,
              );
              final reconnWarn =
                  '⚠️ Connection interrupted before "$remoteDisplay" ($safeDirErr) — reconnecting...';
              _addLog(reconnWarn);
              await _fileLogger.error('FTP', reconnWarn);

              await client.disconnect();
              client = null;
              _activeClient = null;

              try {
                final freshClient = _clientFactory(config);
                _activeClient = freshClient;
                await freshClient.connect();
                client = freshClient;
                final retryPrep = await _prepareRemoteFolder(
                  client,
                  workItem.remoteDir,
                );
                if (!retryPrep.ok) {
                  throw Exception(
                    'Cannot access or create remote directory "$remoteDisplay"',
                  );
                }
                remoteSizes = retryPrep.sizes;
                folderReady = true;
              } catch (retryErr) {
                // Gene - Nov, 24, 2026: Skip error logging if reconnect aborted by stop or run-window expiration.
                if (_shouldAbortPass || _checkWindowExpiration()) break;
                final safeRetryErr = CredentialObfuscator.redact(
                  retryErr.toString(),
                  password,
                );
                final msg =
                    '❌ Cannot access or create remote directory "$remoteDisplay": $safeRetryErr';
                _addLog(msg);
                await _fileLogger.error('FTP', msg);
                await client?.disconnect();
                client = null;
                _activeClient = null;
                errors++;
              }
            }

            //             if (!folderReady || _stopRequested) {
            // Gene - Nov, 24, 2026: Break or skip folder cleanly when aborted by stop or window expiration.
            if (_shouldAbortPass || _checkWindowExpiration()) {
              break;
            }
            if (!folderReady) {
              continue;
            }
          }

          for (final item in miniQueue) {
            //             if (_stopRequested) break;
            // Gene - Nov, 24, 2026: Check stop or run-window expiration before each file.
            if (_shouldAbortPass || _checkWindowExpiration()) break;
            final fileName = p.basename(item.file.path);

            if (skipIfExists && client != null) {
              bool existsRemotely = false;
              int? existingSize;

              if (remoteSizes != null) {
                existsRemotely = remoteSizes.containsKey(fileName);
                existingSize = remoteSizes[fileName];
                if (existsRemotely && existingSize == null) {
                  existingSize = await client.getRemoteFileSize(fileName);
                }
              } else {
                existingSize = await client.getRemoteFileSize(fileName);
                existsRemotely = existingSize != null;
              }
              // Gene - Nov, 24, 2026: Abort cleanly if window expired during remote size check.
              if (_shouldAbortPass || _checkWindowExpiration()) break;

              if (existsRemotely) {
                if (existingSize == item.size) {
                  filesSkipped++;
                  final skipMsg = dryRun
                      ? '🧪 [DRY RUN] Would skip (already on FTP): $fileName'
                      : '⏭ Skipped (already on FTP): $fileName';
                  if (dryRun ||
                      logInterval <= 1 ||
                      filesSkipped % logInterval == 0) {
                    _addLog(skipMsg);
                  }
                  await _fileLogger.info('FTP', skipMsg);
                  notifyListeners();
                  continue;
                } else {
                  final diffMsg = dryRun
                      ? '🧪 [DRY RUN] Would re-upload (size differs: remote=${existingSize ?? "?"}, local=${item.size}): $fileName'
                      : '🔄 Size differs (remote=${existingSize ?? "?"}, local=${item.size}) — re-uploading: $fileName';
                  _addLog(diffMsg);
                  await _fileLogger.info('FTP', diffMsg);
                }
              }
            }

            if (dryRun) {
              filesUploaded++;
              final dryMsg =
                  '🧪 [DRY RUN] Would upload: $fileName (${_numFmt.format(item.size)} bytes) -> $remoteDisplay';
              _addLog(dryMsg);
              await _fileLogger.info('FTP', dryMsg);
              notifyListeners();
              continue;
            }

            activeUploadFileName = fileName;
            activeUploadSentBytes = 0;
            activeUploadTotalBytes = item.size;
            activeUploadProgress = item.size == 0 ? 1.0 : 0.0;
            activeUploadBytesPerSecond = 0;
            _uploadFileStartTime = DateTime.now();
            _lastProgressNotifyAt = null;
            currentStatus = '⬆️ Uploading $fileName...';
            notifyListeners();

            try {
              final maxAttempts = retryCount.clamp(1, 10);
              for (int attempt = 1; attempt <= maxAttempts; attempt++) {
                //                 if (_stopRequested) break;
                // Gene - Nov, 24, 2026: Abort retry attempts if stop requested or run window ended.
                if (_shouldAbortPass || _checkWindowExpiration()) break;
                try {
                  if (client == null) {
                    final freshClient = _clientFactory(config);
                    _activeClient = freshClient;
                    await freshClient.connect();
                    final dirOk = await freshClient.ensureRemoteDirectory(
                      workItem.remoteDir,
                    );
                    if (!dirOk) {
                      await freshClient.disconnect();
                      throw Exception(
                        'Failed to enter remote folder "$remoteDisplay" after reconnect',
                      );
                    }
                    client = freshClient;
                  }

                  _uploadFileStartTime = DateTime.now();
                  _lastProgressNotifyAt = null;
                  final uploaded = await client.uploadFile(
                    item.file,
                    remoteName: fileName,
                    onProgress: (percent, sent, total) {
                      //                       if (_stopRequested) return;
                      // Gene - Nov, 24, 2026: Check run-window expiration during live upload progress ticks.
                      if (_shouldAbortPass || _checkWindowExpiration()) return;
                      final effectiveTotal = total > 0 ? total : item.size;
                      final normalizedProgress = effectiveTotal > 0
                          ? (sent / effectiveTotal).clamp(0.0, 1.0)
                          : (percent / 100.0).clamp(0.0, 1.0);
                      final elapsedMs = _uploadFileStartTime == null
                          ? 0
                          : DateTime.now()
                                .difference(_uploadFileStartTime!)
                                .inMilliseconds;
                      final bps = elapsedMs > 0
                          ? (sent * 1000.0) / elapsedMs
                          : 0.0;

                      activeUploadFileName = fileName;
                      activeUploadSentBytes = sent;
                      activeUploadTotalBytes = effectiveTotal;
                      activeUploadProgress = normalizedProgress;
                      activeUploadBytesPerSecond = bps;

                      final pctLabel = (normalizedProgress * 100)
                          .toStringAsFixed(1);
                      currentStatus =
                          '⬆️ Uploading $fileName ($pctLabel% • ${formatByteSize(sent)} / ${formatByteSize(effectiveTotal)})';

                      final nowTick = DateTime.now();
                      final shouldNotify =
                          _lastProgressNotifyAt == null ||
                          sent >= effectiveTotal ||
                          nowTick.difference(_lastProgressNotifyAt!) >=
                              const Duration(milliseconds: 200);
                      if (shouldNotify) {
                        _lastProgressNotifyAt = nowTick;
                        notifyListeners();
                      }
                    },
                  );
                  // Gene - Nov, 24, 2026: Break immediately before rejection/verification checks if aborted during upload.
                  if (_shouldAbortPass || _checkWindowExpiration()) break;
                  if (!uploaded) {
                    throw Exception('Server rejected upload of $fileName');
                  }

                  if (verifySizeAfterUpload) {
                    final remoteSize = await client.getRemoteFileSize(fileName);
                    // Gene - Nov, 24, 2026: Break cleanly if window ended during post-upload SIZE check.
                    if (_shouldAbortPass || _checkWindowExpiration()) break;
                    if (remoteSize == null) {
                      final warnMsg =
                          '⚠️ Size verification unavailable for $fileName (server did not return remote size)';
                      _addLog(warnMsg);
                      await _fileLogger.info('FTP', warnMsg);
                    } else if (remoteSize >= 0 && remoteSize != item.size) {
                      throw Exception(
                        'Size verification mismatch for $fileName (local=${item.size}, remote=$remoteSize)',
                      );
                    }
                  }

                  filesUploaded++;
                  if (logInterval <= 1 || filesUploaded % logInterval == 0) {
                    _addLog(
                      '✅ Uploaded ($filesUploaded): $fileName (${_numFmt.format(item.size)} bytes)',
                    );
                  }
                  await _fileLogger.info(
                    'FTP',
                    'Uploaded $fileName (${item.size} bytes) to $remoteDisplay',
                  );
                  notifyListeners();
                  break;
                } catch (e) {
                  //                   if (_stopRequested) break;
                  // Gene - Nov, 24, 2026: Skip error recording and retries when aborted by stop or window expiration.
                  if (_shouldAbortPass || _checkWindowExpiration()) break;
                  final safeErr = CredentialObfuscator.redact(
                    e.toString(),
                    password,
                  );

                  if (attempt < maxAttempts) {
                    final warnMsg =
                        '⚠️ Attempt $attempt/$maxAttempts failed for $fileName: $safeErr. Retrying in ${retryDelaySeconds}s...';
                    _addLog(warnMsg);
                    await _fileLogger.error('FTP', warnMsg);
                    notifyListeners();

                    await _cancellableDelay(
                      Duration(seconds: retryDelaySeconds),
                    );
                    //                     if (_stopRequested) break;
                    // Gene - Nov, 24, 2026: Break out of retry delay if stop requested or run window expired.
                    if (_shouldAbortPass || _checkWindowExpiration()) break;

                    // Reconnect before retrying in case the socket dropped mid-transfer.
                    await client?.disconnect();
                    client = null;
                    _activeClient = null;
                    try {
                      final nextClient = _clientFactory(config);
                      _activeClient = nextClient;
                      await nextClient.connect();
                      final dirOk = await nextClient.ensureRemoteDirectory(
                        workItem.remoteDir,
                      );
                      if (!dirOk) {
                        await nextClient.disconnect();
                        throw Exception(
                          'Failed to re-enter remote folder "$remoteDisplay" after reconnect',
                        );
                      }
                      client = nextClient;
                    } catch (reconnectErr) {
                      // Gene - Nov, 24, 2026: Break without reconnect warning if aborted by stop or window end.
                      if (_shouldAbortPass || _checkWindowExpiration()) break;
                      final safeReconnectErr = CredentialObfuscator.redact(
                        reconnectErr.toString(),
                        password,
                      );
                      final reconnectMsg =
                          '⚠️ Reconnect failed before attempt ${attempt + 1}: $safeReconnectErr';
                      _addLog(reconnectMsg);
                      await _fileLogger.error('FTP', reconnectMsg);
                      client = null;
                      _activeClient = null;
                    }
                  } else {
                    errors++;
                    final failMsg =
                        '❌ Failed uploading $fileName after $maxAttempts attempt(s): $safeErr';
                    _addLog(failMsg);
                    await _fileLogger.error('FTP', failMsg);
                    notifyListeners();
                  }
                }
              }
            } finally {
              _clearActiveUploadProgress();
            }
          }
        }
      }
    } catch (e, stack) {
      //       if (!_stopRequested) {
      // Gene - Nov, 24, 2026: Suppress critical-error logging when connection closed due to window expiration.
      if (!_shouldAbortPass && !_checkWindowExpiration()) {
        hadFatalError = true;
        errors++;
        final safeErr = CredentialObfuscator.redact(e.toString(), password);
        _log.severe('FTP upload critical error: $safeErr', stack);
        _addLog('❌ FTP Error: $safeErr');
        await _fileLogger.error('FTP', 'Critical Error: $safeErr');
      }
    } finally {
      //       _clearActiveUploadProgress();
      //       _activeClient = null;
      //       await client?.disconnect();
      //       isUploading = false;
      //
      //       final endTime = _nowProvider();
      //       final runId = _fileLogger.getRunId('FTP') ?? 'RUN-FTP';
      //       await _fileLogger.logRunEnd(
      //         operation: 'FTP',
      //         filesProcessed: filesUploaded,
      //         errors: errors,
      //         wasStopped: _stopRequested,
      //       );
      //
      //       final hasErrors = hadFatalError || errors > 0;
      //       final statusLabel = _stopRequested
      //           ? 'Stopped'
      //           : (hasErrors ? 'Error' : 'Completed');
      //       final summaryPrefix = dryRun ? '[DRY RUN] ' : '';
      //       final configSummary =
      //           '$summaryPrefix${config.protocol.shortLabel} | Date: ${dateMode.label} (${dateType.label}) | Checked: ${_numFmt.format(filesChecked)} | Skipped: ${_numFmt.format(filesSkipped)}';
      //
      //       await HistoryService().saveRecord(
      //         RunRecord(
      //           id: runId,
      //           operation: 'FTP',
      //           startTime: startTime,
      //           endTime: endTime,
      //           filesProcessed: filesUploaded,
      //           foldersProcessed: foldersProcessed,
      //           errors: errors,
      //           status: statusLabel,
      //           configSummary: configSummary,
      //           sourcePath: sourceSummary,
      //           destPath: endpointSummary,
      //         ),
      //       );
      //
      //       if (_stopRequested) {
      //         _scheduleTimer?.cancel();
      //         _scheduleTimer = null;
      //         isScheduleArmed = false;
      //         nextScheduledRun = null;
      //         currentStatus = '⛔ Stopped';
      //         _addLog(
      //           '⛔ Run stopped. Uploaded: ${_numFmt.format(filesUploaded)}, Skipped: ${_numFmt.format(filesSkipped)}, Errors: ${_numFmt.format(errors)}.',
      //         );
      //       } else if (isScheduledRun) {
      //         if (onCompletionAction == 'repeat' &&
      //             enableSchedule &&
      //             hasCheckedScheduleDays) {
      //           final next = computeNextScheduledRun(
      //             now: _nowProvider(),
      //             runTime: runTime,
      //             runDays: runDays,
      //           );
      //           nextScheduledRun = next;
      //           if (next != null) {
      //             final formatted = DateFormat('dd/MM/yyyy HH:mm').format(next);
      //             currentStatus = hasErrors
      //                 ? '⚠️ Completed with $errors error(s). Next run at $formatted'
      //                 : '🏁 Completed. Next run at $formatted';
      //             _addLog(
      //               '🏁 ${dryRun ? "Dry run" : "Upload"} complete (Uploaded: $filesUploaded, Skipped: $filesSkipped, Errors: $errors). Next scheduled run: $formatted.',
      //             );
      //             _ensureScheduleTimerRunning();
      //           } else {
      //             isScheduleArmed = false;
      //             _scheduleTimer?.cancel();
      //             _scheduleTimer = null;
      //             currentStatus = hadFatalError
      //                 ? '❌ Error'
      //                 : (errors > 0
      //                       ? '⚠️ Completed with $errors error(s)'
      //                       : '✅ Completed');
      //           }
      //         } else {
      //           isScheduleArmed = false;
      //           nextScheduledRun = null;
      //           _scheduleTimer?.cancel();
      //           _scheduleTimer = null;
      //           currentStatus = hadFatalError
      //               ? '❌ Error'
      //               : (errors > 0
      //                     ? '⚠️ Completed with $errors error(s)'
      //                     : '✅ Completed');
      //           _addLog(
      //             '✅ Scheduled ${dryRun ? "dry run" : "upload"} complete (Uploaded: $filesUploaded, Skipped: $filesSkipped, Errors: $errors).',
      //           );
      //         }
      //       } else {
      //         if (isScheduleArmed) {
      //           final next = computeNextScheduledRun(
      //             now: _nowProvider(),
      //             runTime: runTime,
      //             runDays: runDays,
      //           );
      //           nextScheduledRun = next;
      //           if (next != null) {
      //             final formatted = DateFormat('dd/MM/yyyy HH:mm').format(next);
      //             currentStatus = hasErrors
      //                 ? '⚠️ Finished with $errors error(s) — Next run: $formatted'
      //                 : '⏰ Scheduled — Next run: $formatted';
      //             _addLog(
      //               '✅ Manual run finished (Uploaded: $filesUploaded, Skipped: $filesSkipped, Errors: $errors). Schedule remains armed for $formatted.',
      //             );
      //           }
      //         } else {
      //           currentStatus = hadFatalError
      //               ? '❌ Error'
      //               : (errors > 0
      //                     ? '⚠️ Completed with $errors error(s)'
      //                     : (dryRun ? '✅ Dry Run Completed' : '✅ Completed'));
      //           _addLog(
      //             '✅ ${dryRun ? "Dry run" : "Upload"} finished! Checked: $filesChecked, Uploaded: $filesUploaded, Skipped: $filesSkipped, Errors: $errors.',
      //           );
      //         }
      //       }
      //
      //       notifyListeners();
      // Gene - Nov, 24, 2026: Handle window-ended shutdown separately from manual stop, preserving Repeat re-arming and clean History status.
      final stoppedByWindow = _windowExpired && !_stopRequested;
      _activeRunWindowEnd = null;
      _windowExpired = false;
      _clearActiveUploadProgress();
      _activeClient = null;
      await client?.disconnect();
      //       isUploading = false;
      // Gene - Nov, 24, 2026: Keep isUploading true until run-end logging, History persistence, and schedule disarm/re-arm complete.
      try {
        final endTime = _nowProvider();
        final runId = _fileLogger.getRunId('FTP') ?? 'RUN-FTP';
        await _fileLogger.logRunEnd(
          operation: 'FTP',
          filesProcessed: filesUploaded,
          errors: errors,
          wasStopped: _stopRequested || stoppedByWindow,
        );

        final hasErrors = hadFatalError || errors > 0;
        final statusLabel = (_stopRequested || stoppedByWindow)
            ? 'Stopped'
            : (hasErrors ? 'Error' : 'Completed');
        final summaryPrefix = dryRun ? '[DRY RUN] ' : '';
        final windowSuffixSummary = stoppedByWindow
            ? ' | Window Ended (${_formatTime24(runEndTime)})'
            : '';
        final configSummary =
            '$summaryPrefix${config.protocol.shortLabel} | Date: ${dateMode.label} (${dateType.label}) | Checked: ${_numFmt.format(filesChecked)} | Skipped: ${_numFmt.format(filesSkipped)}$windowSuffixSummary';

        await HistoryService().saveRecord(
          RunRecord(
            id: runId,
            operation: 'FTP',
            startTime: startTime,
            endTime: endTime,
            filesProcessed: filesUploaded,
            foldersProcessed: foldersProcessed,
            errors: errors,
            status: statusLabel,
            configSummary: configSummary,
            sourcePath: sourceSummary,
            destPath: endpointSummary,
          ),
        );

        final windowSuffix = hasEndTimeLimit
            ? ' (until ${_formatTime24(runEndTime)})'
            : '';

        if (_stopRequested) {
          _scheduleTimer?.cancel();
          _scheduleTimer = null;
          isScheduleArmed = false;
          nextScheduledRun = null;
          currentStatus = '⛔ Stopped';
          _addLog(
            '⛔ Run stopped. Uploaded: ${_numFmt.format(filesUploaded)}, Skipped: ${_numFmt.format(filesSkipped)}, Errors: ${_numFmt.format(errors)}.',
          );
        } else if (stoppedByWindow) {
          final endLabel = _formatTime24(runEndTime);
          if (isScheduledRun &&
              onCompletionAction == 'repeat' &&
              enableSchedule &&
              hasCheckedScheduleDays) {
            final next = computeNextScheduledRun(
              now: _nowProvider(),
              runTime: runTime,
              runDays: runDays,
            );
            nextScheduledRun = next;
            if (next != null) {
              final formatted = DateFormat('dd/MM/yyyy HH:mm').format(next);
              currentStatus =
                  '⏸ Window ended ($endLabel). Next run at $formatted';
              _addLog(
                '⏰ Run window ended at $endLabel (Uploaded: $filesUploaded, Skipped: $filesSkipped, Errors: $errors). Next scheduled run: $formatted$windowSuffix.',
              );
              _ensureScheduleTimerRunning();
            } else {
              isScheduleArmed = false;
              _scheduleTimer?.cancel();
              _scheduleTimer = null;
              currentStatus = '⏰ Window ended ($endLabel)';
              _addLog(
                '⏰ Run window ended at $endLabel (Uploaded: $filesUploaded, Skipped: $filesSkipped, Errors: $errors).',
              );
            }
          } else {
            isScheduleArmed = false;
            nextScheduledRun = null;
            _scheduleTimer?.cancel();
            _scheduleTimer = null;
            currentStatus = '⏰ Window ended ($endLabel)';
            _addLog(
              '⏰ Run window ended at $endLabel (Uploaded: $filesUploaded, Skipped: $filesSkipped, Errors: $errors).',
            );
          }
        } else if (isScheduledRun) {
          if (onCompletionAction == 'repeat' &&
              enableSchedule &&
              hasCheckedScheduleDays) {
            final next = computeNextScheduledRun(
              now: _nowProvider(),
              runTime: runTime,
              runDays: runDays,
            );
            nextScheduledRun = next;
            if (next != null) {
              final formatted = DateFormat('dd/MM/yyyy HH:mm').format(next);
              currentStatus = hasErrors
                  ? '⚠️ Completed with $errors error(s). Next run at $formatted'
                  : '🏁 Completed. Next run at $formatted';
              _addLog(
                '🏁 ${dryRun ? "Dry run" : "Upload"} complete (Uploaded: $filesUploaded, Skipped: $filesSkipped, Errors: $errors). Next scheduled run: $formatted$windowSuffix.',
              );
              _ensureScheduleTimerRunning();
            } else {
              isScheduleArmed = false;
              _scheduleTimer?.cancel();
              _scheduleTimer = null;
              currentStatus = hadFatalError
                  ? '❌ Error'
                  : (errors > 0
                        ? '⚠️ Completed with $errors error(s)'
                        : '✅ Completed');
            }
          } else {
            isScheduleArmed = false;
            nextScheduledRun = null;
            _scheduleTimer?.cancel();
            _scheduleTimer = null;
            currentStatus = hadFatalError
                ? '❌ Error'
                : (errors > 0
                      ? '⚠️ Completed with $errors error(s)'
                      : '✅ Completed');
            _addLog(
              '✅ Scheduled ${dryRun ? "dry run" : "upload"} complete (Uploaded: $filesUploaded, Skipped: $filesSkipped, Errors: $errors).',
            );
          }
        } else {
          if (isScheduleArmed) {
            final next = computeNextScheduledRun(
              now: _nowProvider(),
              runTime: runTime,
              runDays: runDays,
            );
            nextScheduledRun = next;
            if (next != null) {
              final formatted = DateFormat('dd/MM/yyyy HH:mm').format(next);
              currentStatus = hasErrors
                  ? '⚠️ Finished with $errors error(s) — Next run: $formatted$windowSuffix'
                  : '⏰ Scheduled — Next run: $formatted$windowSuffix';
              _addLog(
                '✅ Manual run finished (Uploaded: $filesUploaded, Skipped: $filesSkipped, Errors: $errors). Schedule remains armed for $formatted$windowSuffix.',
              );
            }
          } else {
            currentStatus = hadFatalError
                ? '❌ Error'
                : (errors > 0
                      ? '⚠️ Completed with $errors error(s)'
                      : (dryRun ? '✅ Dry Run Completed' : '✅ Completed'));
            _addLog(
              '✅ ${dryRun ? "Dry run" : "Upload"} finished! Checked: $filesChecked, Uploaded: $filesUploaded, Skipped: $filesSkipped, Errors: $errors.',
            );
          }
        }
      } finally {
        isUploading = false;
      }

      notifyListeners();
    }
  }

  //   Future<void> _cancellableDelay(Duration duration) async {
  //     final deadline = DateTime.now().add(duration);
  //     while (DateTime.now().isBefore(deadline) && !_stopRequested) {
  //       await Future<void>.delayed(const Duration(milliseconds: 200));
  //     }
  //   }
  // Gene - Nov, 24, 2026: Cancel retry delay early when scheduled run window expires.
  Future<void> _cancellableDelay(Duration duration) async {
    final deadline = DateTime.now().add(duration);
    while (DateTime.now().isBefore(deadline) &&
        !_shouldAbortPass &&
        !_checkWindowExpiration()) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }
}
