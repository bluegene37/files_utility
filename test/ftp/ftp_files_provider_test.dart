// Gene - Nov, 21, 2026: Unit tests for FtpFilesProvider upload flow, V1 features, scheduler, history, and redaction.
// Gene - Nov, 24, 2026: Import dart:async for blocking upload / window-end disconnect tests.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:files_utility/providers/ftp_files_provider.dart';
import 'package:files_utility/services/app_sqlite_service.dart';
// Gene - Nov, 23, 2026: Import FileLogger to verify retention pruning and error footer output.
import 'package:files_utility/services/file_logger.dart';
import 'package:files_utility/services/ftp_transfer_service.dart';
import 'package:files_utility/services/global_db_service.dart';
import 'package:files_utility/services/history_service.dart';
import 'package:files_utility/services/local_db_service.dart';

class FakeRemoteServerState {
  int connectCount = 0;
  int disconnectCount = 0;
  final List<String> ensuredDirs = [];
  final List<String> uploadCalls = [];
  final Map<String, Map<String, List<int>>> dirs = {'': {}};

  String? connectErrorMessage;
  int failUploadAttemptsRemaining = 0;
  String? failUploadErrorMessage;
  int wrongReportedSizeAttemptsRemaining = 0;
  // Gene - Nov, 23, 2026: Test hooks for idle disconnect recovery, null SIZE, and upload progress ticks.
  int? failEnsureDirOnCallNumber;
  int ensureDirCallCount = 0;
  bool returnNullRemoteSize = false;
  List<({double percent, int sent, int total})> simulatedProgressTicks =
      const [];
  // Gene - Nov, 24, 2026: Hooks to block a specific file upload until disconnect() simulates mid-transfer socket close.
  String? blockFileName;
  Completer<void>? uploadStartedSignal;
  Completer<void>? _pendingUploadGate;

  String _norm(String raw) {
    final clean = joinRemotePath(raw, '');
    return clean.startsWith('/') ? clean.substring(1) : clean;
  }

  void seedFile(String remoteDir, String fileName, List<int> bytes) {
    final norm = _norm(remoteDir);
    dirs.putIfAbsent(norm, () => {})[fileName] = bytes;
  }

  List<int>? getFile(String remoteDir, String fileName) {
    return dirs[_norm(remoteDir)]?[fileName];
  }
}

class FakeFtpClientAdapter implements FtpClientAdapter {
  final FakeRemoteServerState state;
  String _cwd = '';

  FakeFtpClientAdapter(this.state);

  @override
  Future<void> connect() async {
    state.connectCount++;
    if (state.connectErrorMessage != null) {
      throw Exception(state.connectErrorMessage);
    }
    _cwd = '';
  }

  @override
  Future<void> disconnect() async {
    state.disconnectCount++;
    // Gene - Nov, 24, 2026: Abort any blocked in-flight upload when socket disconnects.
    final gate = state._pendingUploadGate;
    if (gate != null && !gate.isCompleted) {
      gate.completeError(Exception('Simulated socket close on disconnect'));
    }
  }

  @override
  Future<String> currentDirectory() async => '/$_cwd';

  @override
  Future<bool> changeDirectory(String remotePath) async {
    final norm = state._norm(remotePath);
    if (state.dirs.containsKey(norm)) {
      _cwd = norm;
      return true;
    }
    return false;
  }

  @override
  Future<bool> ensureRemoteDirectory(String remotePath) async {
    state.ensureDirCallCount++;
    if (state.failEnsureDirOnCallNumber == state.ensureDirCallCount) {
      throw Exception('Simulated idle disconnect before $remotePath');
    }
    final norm = state._norm(remotePath);
    state.ensuredDirs.add(norm);
    state.dirs.putIfAbsent(norm, () => {});
    _cwd = norm;
    return true;
  }

  @override
  Future<Map<String, int?>?> listRemoteFileSizes() async {
    final entries = state.dirs[_cwd] ?? const {};
    return {for (final e in entries.entries) e.key: e.value.length};
  }

  @override
  Future<int?> getRemoteFileSize(String remoteName) async {
    if (state.returnNullRemoteSize) return null;
    if (state.wrongReportedSizeAttemptsRemaining > 0) {
      state.wrongReportedSizeAttemptsRemaining--;
      return 1;
    }
    return state.dirs[_cwd]?[remoteName]?.length;
  }

  //   @override
  //   Future<bool> uploadFile(File localFile, {String? remoteName}) async {
  //     final name = remoteName ?? p.basename(localFile.path);
  //     final fullRemote = _cwd.isEmpty ? name : '$_cwd/$name';
  //     state.uploadCalls.add(fullRemote);
  //
  //     if (state.failUploadAttemptsRemaining > 0) {
  //       state.failUploadAttemptsRemaining--;
  //       throw Exception(
  //         state.failUploadErrorMessage ?? 'Simulated socket drop during upload',
  //       );
  //     }
  //
  //     final bytes = await localFile.readAsBytes();
  //     state.dirs.putIfAbsent(_cwd, () => {})[name] = bytes;
  //     return true;
  //   }
  // Gene - Nov, 23, 2026: Support FtpUploadProgressCallback in FakeFtpClientAdapter.
  @override
  Future<bool> uploadFile(
    File localFile, {
    String? remoteName,
    FtpUploadProgressCallback? onProgress,
  }) async {
    final name = remoteName ?? p.basename(localFile.path);
    final fullRemote = _cwd.isEmpty ? name : '$_cwd/$name';
    state.uploadCalls.add(fullRemote);

    if (state.failUploadAttemptsRemaining > 0) {
      state.failUploadAttemptsRemaining--;
      throw Exception(
        state.failUploadErrorMessage ?? 'Simulated socket drop during upload',
      );
    }

    if (onProgress != null) {
      for (final tick in state.simulatedProgressTicks) {
        onProgress(tick.percent, tick.sent, tick.total);
      }
    }

    // Gene - Nov, 24, 2026: Allow tests to pause a specific file upload until window expiration disconnects client.
    if (state.blockFileName == name) {
      final gate = Completer<void>();
      state._pendingUploadGate = gate;
      if (state.uploadStartedSignal != null &&
          !state.uploadStartedSignal!.isCompleted) {
        state.uploadStartedSignal!.complete();
      }
      await gate.future;
      state._pendingUploadGate = null;
    }

    final bytes = await localFile.readAsBytes();
    state.dirs.putIfAbsent(_cwd, () => {})[name] = bytes;
    return true;
  }
}

Future<void> _flushDbWrites() async {
  // Let queued SQLite writes settle before reloading or switching profiles.
  await Future<void>.delayed(const Duration(milliseconds: 120));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory appRootDir;
  late Directory tempSourcesDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    appRootDir = Directory.systemTemp.createTempSync('files_utility_ftp_app_');
    tempSourcesDir = Directory.systemTemp.createTempSync(
      'files_utility_ftp_src_',
    );
    AppSqliteService().appDirPath = appRootDir.path;
    await GlobalDbService().init();
  });

  // Gene - Nov, 22, 2026: Close SQLite handles before deleting temp directories to avoid Windows errno 32 file-lock failures in tearDownAll
  // tearDownAll(() {
  //   if (appRootDir.existsSync()) appRootDir.deleteSync(recursive: true);
  //   if (tempSourcesDir.existsSync()) tempSourcesDir.deleteSync(recursive: true);
  // });
  tearDownAll(() async {
    await HistoryService().close();
    await AppSqliteService().close();
    for (final dir in [appRootDir, tempSourcesDir]) {
      try {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      } on FileSystemException catch (_) {}
    }
  });

  FtpFilesProvider buildProvider({
    required FakeRemoteServerState server,
    DateTime Function()? nowProvider,
  }) {
    return FtpFilesProvider(
      clientFactory: (_) => FakeFtpClientAdapter(server),
      nowProvider: nowProvider,
    );
  }

  group('FtpFilesProvider', () {
    test(
      'single-source upload filters dates accurately across all modes',
      () async {
        await LocalDbService().init('ftp_test_dates');
        HistoryService().init('ftp_test_dates');
        await HistoryService().clearHistory(allProfiles: false);

        final src = Directory(p.join(tempSourcesDir.path, 'dates_case'))
          ..createSync(recursive: true);

        final fileYesterday = File(p.join(src.path, 'yesterday.txt'))
          ..writeAsBytesSync([1, 2, 3, 4]);
        final fileToday = File(p.join(src.path, 'today.txt'))
          ..writeAsBytesSync([5, 6, 7]);
        final fileOlder = File(p.join(src.path, 'older.txt'))
          ..writeAsBytesSync([8, 9]);

        final fakeNow = DateTime(2026, 11, 21, 10, 0);
        fileYesterday.setLastModifiedSync(DateTime(2026, 11, 20, 15, 0));
        fileToday.setLastModifiedSync(DateTime(2026, 11, 21, 8, 30));
        fileOlder.setLastModifiedSync(DateTime(2026, 11, 15, 12, 0));

        final server = FakeRemoteServerState();
        final provider = buildProvider(
          server: server,
          nowProvider: () => fakeNow,
        );
        addTearDown(provider.dispose);

        provider
          ..setHost('ftp.example.com')
          ..setPort(21)
          ..setUsername('test_user')
          ..setPassword('test_pass_123')
          ..setSourcePath(src.path)
          ..setRemoteDirectory('DailyDrop')
          ..setDateType(FtpDateType.modified)
          ..setDateMode(FtpDateMode.yesterday);

        await provider.runNow();
        expect(provider.filesUploaded, 1);
        expect(server.getFile('DailyDrop', 'yesterday.txt'), [1, 2, 3, 4]);
        expect(server.getFile('DailyDrop', 'today.txt'), isNull);

        // Today mode picks up today.txt
        provider.setDateMode(FtpDateMode.today);
        await provider.runNow();
        expect(provider.filesUploaded, 1);
        expect(server.getFile('DailyDrop', 'today.txt'), [5, 6, 7]);

        // N Days Ago (6 days before Nov 21 = Nov 15) picks up older.txt
        provider
          ..setDateMode(FtpDateMode.daysAgo)
          ..setDaysAgo(6);
        await provider.runNow();
        expect(provider.filesUploaded, 1);
        expect(server.getFile('DailyDrop', 'older.txt'), [8, 9]);

        // Specific date mode -> clears remote first by targeting a subfolder
        provider
          ..setRemoteDirectory('SpecificDrop')
          ..setDateMode(FtpDateMode.specificDate)
          ..setSpecificDate(DateTime(2026, 11, 15));
        await provider.runNow();
        expect(provider.filesUploaded, 1);
        expect(server.getFile('SpecificDrop', 'older.txt'), [8, 9]);

        // Date range mode
        provider
          ..setRemoteDirectory('RangeDrop')
          ..setDateMode(FtpDateMode.dateRange)
          ..setFromDate(DateTime(2026, 11, 20))
          ..setToDate(DateTime(2026, 11, 21));
        await provider.runNow();
        expect(provider.filesUploaded, 2);
        expect(server.getFile('RangeDrop', 'yesterday.txt'), isNotNull);
        expect(server.getFile('RangeDrop', 'today.txt'), isNotNull);

        // All files mode (and creation date default on freshly created temp files)
        provider
          ..setRemoteDirectory('AllDrop')
          ..setDateMode(FtpDateMode.allFiles)
          ..setDateType(FtpDateType.creation);
        await provider.runNow();
        expect(provider.filesUploaded, 3);
      },
    );

    test(
      'multi-source runOrder, subfolder filter, and custom FTP destination mapping',
      () async {
        await LocalDbService().init('ftp_test_multi');
        HistoryService().init('ftp_test_multi');

        final rootA = Directory(p.join(tempSourcesDir.path, 'multi_a'))
          ..createSync(recursive: true);
        Directory(p.join(rootA.path, 'FolderA')).createSync();
        Directory(p.join(rootA.path, 'FolderB')).createSync();
        Directory(p.join(rootA.path, 'IgnoredFolder')).createSync();

        File(
          p.join(rootA.path, 'FolderA', 'doc1.pdf'),
        ).writeAsBytesSync([10, 20]);
        File(
          p.join(rootA.path, 'FolderB', 'img1.jpg'),
        ).writeAsBytesSync([30, 40]);
        File(
          p.join(rootA.path, 'IgnoredFolder', 'skip.txt'),
        ).writeAsBytesSync([50]);

        final rootB = Directory(p.join(tempSourcesDir.path, 'multi_b'))
          ..createSync(recursive: true);
        Directory(p.join(rootB.path, 'Sub1')).createSync();
        File(
          p.join(rootB.path, 'Sub1', 'backup.bak'),
        ).writeAsBytesSync([99, 100, 101]);

        final server = FakeRemoteServerState();
        final provider = buildProvider(server: server);
        addTearDown(provider.dispose);

        provider
          ..setHost('ftp.example.com')
          ..setUsername('test_user')
          ..setPassword('test_pass_123')
          ..setDateMode(FtpDateMode.allFiles)
          ..setUseMultipleSources(true);

        // Add second source; assign runOrder 2 to rootA and runOrder 1 to rootB.
        provider.addUploadSource();
        provider
          ..setSourceNameAt(0, 'JobFiles')
          ..setSourcePathAt(0, rootA.path)
          ..setSourceSubfoldersAt(0, 'FolderA, FolderB')
          ..setSourceFtpDestAt(0, '')
          ..setSourceRunOrderAt(0, 2)
          ..setSourceNameAt(1, 'BackupsSource')
          ..setSourcePathAt(1, rootB.path)
          ..setSourceSubfoldersAt(1, 'Sub1')
          ..setSourceFtpDestAt(1, 'Backups')
          ..setSourceRunOrderAt(1, 1);

        await provider.runNow();

        expect(provider.errors, 0);
        expect(provider.filesUploaded, 3);
        expect(server.uploadCalls, [
          'Backups/Sub1/backup.bak',
          'FolderA/doc1.pdf',
          'FolderB/img1.jpg',
        ]);
        expect(server.getFile('', 'skip.txt'), isNull);
      },
    );

    test(
      'skipIfExists skips matching sizes and re-uploads mismatched partial files',
      () async {
        await LocalDbService().init('ftp_test_skip');
        HistoryService().init('ftp_test_skip');

        final src = Directory(p.join(tempSourcesDir.path, 'skip_case'))
          ..createSync(recursive: true);
        File(p.join(src.path, 'same.bin')).writeAsBytesSync([1, 2, 3, 4]);
        File(
          p.join(src.path, 'partial.bin'),
        ).writeAsBytesSync([10, 20, 30, 40, 50]);

        final server = FakeRemoteServerState();
        server.seedFile('Target', 'same.bin', [1, 2, 3, 4]); // exact 4 bytes
        server.seedFile('Target', 'partial.bin', [10, 20]); // partial 2 bytes

        final provider = buildProvider(server: server);
        addTearDown(provider.dispose);

        provider
          ..setHost('ftp.example.com')
          ..setSourcePath(src.path)
          ..setRemoteDirectory('Target')
          ..setDateMode(FtpDateMode.allFiles)
          ..setSkipIfExists(true);

        await provider.runNow();

        expect(provider.filesSkipped, 1);
        expect(provider.filesUploaded, 1);
        expect(server.uploadCalls, ['Target/partial.bin']);
        expect(server.getFile('Target', 'partial.bin'), [10, 20, 30, 40, 50]);
      },
    );

    test(
      'retries failed upload and size mismatch with reconnect and succeeds',
      () async {
        await LocalDbService().init('ftp_test_retry');
        HistoryService().init('ftp_test_retry');

        final src = Directory(p.join(tempSourcesDir.path, 'retry_case'))
          ..createSync(recursive: true);
        File(p.join(src.path, 'asset.dat')).writeAsBytesSync([1, 2, 3, 4, 5]);

        // Attempt 1 fails with upload exception; attempt 2 returns wrong size on
        // sizeFile verification; attempt 3 succeeds cleanly.
        final server = FakeRemoteServerState()
          ..failUploadAttemptsRemaining = 1
          ..wrongReportedSizeAttemptsRemaining = 1;

        final provider = buildProvider(server: server);
        addTearDown(provider.dispose);

        provider
          ..setHost('ftp.example.com')
          ..setPassword('test_pass_123')
          ..setSourcePath(src.path)
          ..setRemoteDirectory('RetryDrop')
          ..setDateMode(FtpDateMode.allFiles)
          ..setSkipIfExists(false)
          ..setVerifySizeAfterUpload(true)
          ..setRetryCount(3)
          ..setRetryDelaySeconds(0);

        await provider.runNow();

        expect(provider.errors, 0);
        expect(provider.filesUploaded, 1);
        expect(server.connectCount, 3);
        expect(server.uploadCalls.length, 3);
      },
    );

    test(
      'dryRun scans and logs without uploading or creating remote folders',
      () async {
        await LocalDbService().init('ftp_test_dry');
        HistoryService().init('ftp_test_dry');
        await HistoryService().clearHistory(allProfiles: false);

        final src = Directory(p.join(tempSourcesDir.path, 'dry_case'))
          ..createSync(recursive: true);
        File(p.join(src.path, 'already.txt')).writeAsBytesSync([1, 2, 3]);
        File(p.join(src.path, 'newfile.txt')).writeAsBytesSync([4, 5, 6, 7]);

        final server = FakeRemoteServerState();
        server.seedFile('DryTarget', 'already.txt', [1, 2, 3]);

        final provider = buildProvider(server: server);
        addTearDown(provider.dispose);

        provider
          ..setHost('ftp.example.com')
          ..setSourcePath(src.path)
          ..setRemoteDirectory('DryTarget')
          ..setDateMode(FtpDateMode.allFiles)
          ..setSkipIfExists(true)
          ..setDryRun(true);

        await provider.runNow();

        expect(server.uploadCalls, isEmpty);
        expect(server.ensuredDirs, isEmpty);
        expect(provider.filesSkipped, 1);
        expect(provider.filesUploaded, 1);
        expect(provider.logs.any((l) => l.contains('[DRY RUN]')), isTrue);

        final records = await HistoryService().loadHistory(
          operation: 'FTP',
          allProfiles: false,
        );
        expect(records, hasLength(1));
        expect(records.first.status, 'Completed');
        expect(records.first.configSummary, contains('[DRY RUN]'));
      },
    );

    test(
      'testConnection reports success/failure and redacts password in all outputs',
      () async {
        await LocalDbService().init('ftp_test_conn');

        final server = FakeRemoteServerState();
        server.dirs['Uploads'] = {};
        final provider = buildProvider(server: server);
        addTearDown(provider.dispose);

        provider
          ..setHost('ftp.example.com')
          ..setUsername('test_user')
          ..setPassword('test_pass_123')
          ..setRemoteDirectory('Uploads');

        final okResult = await provider.testConnection();
        expect(okResult.success, isTrue);
        expect(okResult.message, contains('Uploads'));

        // Simulate failure containing secret password in exception message.
        server.connectErrorMessage =
            'Auth failed for test_user with password test_pass_123';
        final failResult = await provider.testConnection();
        expect(failResult.success, isFalse);
        expect(failResult.message, isNot(contains('test_pass_123')));
        expect(failResult.message, contains('***'));
        expect(provider.logs.any((l) => l.contains('test_pass_123')), isFalse);
      },
    );

    test(
      'scheduler lifecycle arms, supports Run Now while armed, repeats/stops, and stops cleanly',
      () async {
        await LocalDbService().init('ftp_test_sched');
        HistoryService().init('ftp_test_sched');

        final src = Directory(p.join(tempSourcesDir.path, 'sched_case'))
          ..createSync(recursive: true);
        File(p.join(src.path, 'daily.txt')).writeAsBytesSync([7, 8, 9]);

        // Start clock on Monday 2026-11-23 at 08:00.
        DateTime clock = DateTime(2026, 11, 23, 8, 0);
        final server = FakeRemoteServerState();
        final provider = buildProvider(
          server: server,
          nowProvider: () => clock,
        );
        addTearDown(provider.dispose);

        provider
          ..setHost('ftp.example.com')
          ..setSourcePath(src.path)
          ..setDateMode(FtpDateMode.allFiles)
          ..setSkipIfExists(false)
          ..setEnableSchedule(true)
          //           ..setRunTime(const TimeOfDay(hour: 10, minute: 0))
          // Gene - Nov, 24, 2026: Bound test schedule window (10:00-10:30) so re-arming at 11:00 waits for next day.
          ..setRunTime(const TimeOfDay(hour: 10, minute: 0))
          ..setRunEndTime(const TimeOfDay(hour: 10, minute: 30))
          ..setOnCompletionAction('repeat');

        provider.startSchedule();
        expect(provider.isScheduleArmed, isTrue);
        expect(provider.nextScheduledRun, DateTime(2026, 11, 23, 10, 0));

        // Run Now while armed keeps schedule armed.
        await provider.runNow();
        expect(provider.filesUploaded, 1);
        expect(provider.isScheduleArmed, isTrue);
        expect(provider.nextScheduledRun, DateTime(2026, 11, 23, 10, 0));

        // Advance clock to 10:00 and trigger schedule tick -> Repeat schedules next day.
        clock = DateTime(2026, 11, 23, 10, 0);
        await provider.triggerScheduleTickForTest();
        expect(provider.filesUploaded, 1);
        expect(provider.isScheduleArmed, isTrue);
        expect(provider.nextScheduledRun, DateTime(2026, 11, 24, 10, 0));

        // Switch completion action to Stop, advance clock, trigger -> disarms.
        provider.setOnCompletionAction('stop');
        clock = DateTime(2026, 11, 24, 10, 0);
        await provider.triggerScheduleTickForTest();
        expect(provider.isScheduleArmed, isFalse);
        expect(provider.nextScheduledRun, isNull);

        // Re-arm and explicitly stop.
        clock = DateTime(2026, 11, 24, 11, 0);
        provider.startSchedule();
        expect(provider.isScheduleArmed, isTrue);
        provider.stop();
        expect(provider.isScheduleArmed, isFalse);
        expect(provider.currentStatus, '⛔ Stopped');
      },
    );

    test(
      'persists History RunRecord without secrets and isolates settings per profile',
      () async {
        await LocalDbService().init('ftp_prof_a');
        HistoryService().init('ftp_prof_a');
        await HistoryService().clearHistory(allProfiles: false);

        final src = Directory(p.join(tempSourcesDir.path, 'persist_case'))
          ..createSync(recursive: true);
        File(p.join(src.path, 'item.txt')).writeAsBytesSync([1, 2]);

        final server = FakeRemoteServerState();
        final provider = buildProvider(server: server);
        addTearDown(provider.dispose);

        provider
          ..setHost('ftp.example.com')
          ..setPort(2121)
          ..setUsername('test_user')
          ..setPassword('test_pass_123')
          ..setSourcePath(src.path)
          ..setRemoteDirectory('Archive')
          ..setDateMode(FtpDateMode.allFiles);

        await provider.runNow();
        await provider.flushSavesForTest();

        final records = await HistoryService().loadHistory(
          operation: 'FTP',
          allProfiles: false,
        );
        expect(records, hasLength(1));
        expect(records.first.operation, 'FTP');
        expect(records.first.filesProcessed, 1);
        expect(records.first.configSummary, isNot(contains('test_pass_123')));
        expect(records.first.destPath, isNot(contains('test_pass_123')));
        expect(
          LocalDbService().getString('ftp_password'),
          isNot(equals('test_pass_123')),
        );

        // Switch to empty Profile B -> isolated clean settings.
        await LocalDbService().init('ftp_prof_b');
        await _flushDbWrites();
        expect(provider.host, isEmpty);
        expect(provider.password, isEmpty);
        expect(provider.sourcePath, isNull);

        // Switch back to Profile A -> restored with decrypted password in memory.
        await LocalDbService().init('ftp_prof_a');
        await _flushDbWrites();
        expect(provider.host, 'ftp.example.com');
        expect(provider.port, 2121);
        expect(provider.password, 'test_pass_123');
      },
    );

    // Gene - Nov, 23, 2026: Unit tests for live upload progress, idle reconnect recovery, error status, null SIZE warning, source toggle, audit logs, and log retention pruning.
    test(
      'live upload progress updates UI state without polluting logs and formatByteSize formats units',
      () async {
        await LocalDbService().init('ftp_test_progress');
        HistoryService().init('ftp_test_progress');

        expect(FtpFilesProvider.formatByteSize(512), '512 B');
        expect(FtpFilesProvider.formatByteSize(1536), '1.5 KB');
        expect(FtpFilesProvider.formatByteSize(5 * 1024 * 1024), '5.0 MB');
        expect(
          FtpFilesProvider.formatByteSize(2 * 1024 * 1024 * 1024),
          '2.0 GB',
        );

        final src = Directory(p.join(tempSourcesDir.path, 'progress_case'))
          ..createSync(recursive: true);
        File(
          p.join(src.path, 'big.bak'),
        ).writeAsBytesSync(List<int>.filled(10, 42));

        final server = FakeRemoteServerState()
          ..simulatedProgressTicks = const [
            (percent: 50.0, sent: 5, total: 10),
            (percent: 100.0, sent: 10, total: 10),
          ];

        final provider = buildProvider(server: server);
        addTearDown(provider.dispose);

        final observedProgress = <double>[];
        final observedStatuses = <String>[];
        provider.addListener(() {
          if (provider.activeUploadProgress != null) {
            observedProgress.add(provider.activeUploadProgress!);
            observedStatuses.add(provider.currentStatus);
          }
        });

        provider
          ..setHost('ftp.example.com')
          ..setSourcePath(src.path)
          ..setDateMode(FtpDateMode.allFiles)
          ..setSkipIfExists(false);

        await provider.runNow();

        expect(observedProgress, containsAll([0.5, 1.0]));
        expect(
          observedStatuses.any((s) => s.contains('50.0%') && s.contains('5 B')),
          isTrue,
        );
        expect(provider.activeUploadProgress, isNull);
        expect(provider.activeUploadFileName, isNull);
        expect(provider.logs.any((l) => l.contains('50.0%')), isFalse);
      },
    );

    test(
      'recovers from idle disconnect between subfolders via automatic reconnect',
      () async {
        await LocalDbService().init('ftp_test_idle_reconn');
        HistoryService().init('ftp_test_idle_reconn');

        final src = Directory(p.join(tempSourcesDir.path, 'idle_reconn_case'))
          ..createSync(recursive: true);
        Directory(p.join(src.path, 'SubA')).createSync();
        Directory(p.join(src.path, 'SubB')).createSync();
        File(p.join(src.path, 'SubA', 'a.txt')).writeAsBytesSync([1, 2]);
        File(p.join(src.path, 'SubB', 'b.txt')).writeAsBytesSync([3, 4]);

        // Call #1 succeeds for SubA; call #2 simulates idle drop entering SubB;
        // call #3 succeeds after reconnect.
        final server = FakeRemoteServerState()..failEnsureDirOnCallNumber = 2;
        final provider = buildProvider(server: server);
        addTearDown(provider.dispose);

        provider
          ..setHost('ftp.example.com')
          ..setSourcePath(src.path)
          ..setSubfolders('SubA, SubB')
          ..setDateMode(FtpDateMode.allFiles)
          ..setSkipIfExists(false);

        await provider.runNow();

        expect(provider.errors, 0);
        expect(provider.filesUploaded, 2);
        expect(server.connectCount, 2);
        expect(server.uploadCalls, ['SubA/a.txt', 'SubB/b.txt']);
        expect(
          provider.logs.any((l) => l.contains('Connection interrupted')),
          isTrue,
        );
      },
    );

    test(
      'records Error status in History, UI status, and FileLogger footer when errors > 0',
      () async {
        await LocalDbService().init('ftp_test_err_status');
        HistoryService().init('ftp_test_err_status');
        await HistoryService().clearHistory(allProfiles: false);

        final src = Directory(p.join(tempSourcesDir.path, 'err_status_case'))
          ..createSync(recursive: true);
        Directory(p.join(src.path, 'Existing')).createSync();
        File(p.join(src.path, 'Existing', 'ok.txt')).writeAsBytesSync([1, 2]);

        final server = FakeRemoteServerState();
        final provider = buildProvider(server: server);
        addTearDown(provider.dispose);

        provider
          ..setHost('ftp.example.com')
          ..setSourcePath(src.path)
          ..setSubfolders('Existing, MissingSub')
          ..setDateMode(FtpDateMode.allFiles)
          ..setSkipIfExists(false);

        await provider.runNow();

        expect(provider.filesUploaded, 1);
        expect(provider.errors, 1);
        expect(provider.currentStatus, contains('Completed with 1 error(s)'));

        final records = await HistoryService().loadHistory(
          operation: 'FTP',
          allProfiles: false,
        );
        expect(records, hasLength(1));
        expect(records.first.status, 'Error');
        expect(records.first.errors, 1);

        final logFiles =
            Directory(FileLogger().logDirectoryPath)
                .listSync()
                .whereType<File>()
                .where((f) => p.basename(f.path).startsWith('FTP_'))
                .toList()
              ..sort(
                (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
              );
        expect(logFiles, isNotEmpty);
        final latestLogContent = logFiles.first.readAsStringSync();
        expect(latestLogContent, contains('COMPLETED WITH ERRORS (1)'));
      },
    );

    test(
      'logs warning when post-upload SIZE verification returns null',
      () async {
        await LocalDbService().init('ftp_test_null_size');
        HistoryService().init('ftp_test_null_size');

        final src = Directory(p.join(tempSourcesDir.path, 'null_size_case'))
          ..createSync(recursive: true);
        File(p.join(src.path, 'doc.pdf')).writeAsBytesSync([1, 2, 3]);

        final server = FakeRemoteServerState()..returnNullRemoteSize = true;
        final provider = buildProvider(server: server);
        addTearDown(provider.dispose);

        provider
          ..setHost('ftp.example.com')
          ..setSourcePath(src.path)
          ..setDateMode(FtpDateMode.allFiles)
          ..setSkipIfExists(false)
          ..setVerifySizeAfterUpload(true);

        await provider.runNow();

        expect(provider.errors, 0);
        expect(provider.filesUploaded, 1);
        expect(
          provider.logs.any((l) => l.contains('Size verification unavailable')),
          isTrue,
        );
      },
    );

    test(
      'skips disabled sources in multi-source mode and logs audit date and zero-match scans',
      () async {
        await LocalDbService().init('ftp_test_disabled_src');
        HistoryService().init('ftp_test_disabled_src');

        final rootDisabled = Directory(
          p.join(tempSourcesDir.path, 'disabled_src'),
        )..createSync(recursive: true);
        File(p.join(rootDisabled.path, 'skip_me.txt')).writeAsBytesSync([9, 9]);

        final rootActive = Directory(p.join(tempSourcesDir.path, 'active_src'))
          ..createSync(recursive: true);
        final oldFile = File(p.join(rootActive.path, 'old.txt'))
          ..writeAsBytesSync([1, 2]);
        oldFile.setLastModifiedSync(DateTime(2026, 11, 10, 9, 0));

        final server = FakeRemoteServerState();
        final provider = buildProvider(
          server: server,
          nowProvider: () => DateTime(2026, 11, 23, 10, 0),
        );
        addTearDown(provider.dispose);

        provider
          ..setHost('ftp.example.com')
          ..setUseMultipleSources(true)
          ..setDateType(FtpDateType.modified)
          ..setDateMode(FtpDateMode.yesterday);

        provider.addUploadSource();
        provider
          ..setSourceNameAt(0, 'DisabledTesting')
          ..setSourcePathAt(0, rootDisabled.path)
          ..setSourceEnabledAt(0, false)
          ..setSourceNameAt(1, 'ActiveSource')
          ..setSourcePathAt(1, rootActive.path)
          ..setSourceEnabledAt(1, true);

        await provider.runNow();

        expect(provider.filesUploaded, 0);
        expect(provider.filesChecked, 1);
        expect(server.uploadCalls, isEmpty);
        // Never connected because 0 files matched across active sources.
        expect(server.connectCount, 0);
        expect(
          provider.logs.any(
            (l) => l.contains('Skipping 1 disabled upload source'),
          ),
          isTrue,
        );
        expect(
          provider.logs.any(
            (l) =>
                l.contains('Target date resolved to: 2026-11-22 (Yesterday)'),
          ),
          isTrue,
        );
        expect(
          provider.logs.any((l) => l.contains('1 checked, 0 matched')),
          isTrue,
        );
      },
    );

    test(
      'FileLogger.pruneOldLogs deletes expired matching logs and respects keepDays == 0',
      () async {
        final logsDir = Directory(FileLogger().logDirectoryPath)
          ..createSync(recursive: true);
        final now = DateTime(2026, 11, 23, 12, 0);

        final oldFtp = File(p.join(logsDir.path, 'FTP_2026-10-01_OLD.log'))
          ..writeAsStringSync('old ftp');
        final recentFtp = File(p.join(logsDir.path, 'FTP_2026-11-20_NEW.log'))
          ..writeAsStringSync('recent ftp');
        final oldTransfer = File(
          p.join(logsDir.path, 'TRANSFER_2026-10-01_OTHER.log'),
        )..writeAsStringSync('old transfer');

        oldFtp.setLastModifiedSync(now.subtract(const Duration(days: 40)));
        recentFtp.setLastModifiedSync(now.subtract(const Duration(days: 3)));
        oldTransfer.setLastModifiedSync(now.subtract(const Duration(days: 40)));

        addTearDown(() {
          for (final f in [oldFtp, recentFtp, oldTransfer]) {
            if (f.existsSync()) f.deleteSync();
          }
        });

        final foreverCount = await FileLogger().pruneOldLogs(
          keepDays: 0,
          operationPrefix: 'FTP',
          now: now,
        );
        expect(foreverCount, 0);
        expect(oldFtp.existsSync(), isTrue);

        final pruned = await FileLogger().pruneOldLogs(
          keepDays: 30,
          operationPrefix: 'FTP',
          now: now,
        );
        expect(pruned, 1);
        expect(oldFtp.existsSync(), isFalse);
        expect(recentFtp.existsSync(), isTrue);
        expect(oldTransfer.existsSync(), isTrue);
      },
    );

    // Gene - Nov, 24, 2026: Comprehensive tests for FTP start/end run-time windows, auto-cutoff, missed windows, manual bypass, and SQLite migration.
    test(
      'startSchedule starts immediately inside active same-day or overnight window',
      () async {
        await LocalDbService().init('ftp_test_active_win');
        HistoryService().init('ftp_test_active_win');

        final src = Directory(p.join(tempSourcesDir.path, 'active_win_case'))
          ..createSync(recursive: true);
        File(p.join(src.path, 'inside.txt')).writeAsBytesSync([1, 2, 3]);

        // Case 1: Same-day active window (Monday 10:15 inside 10:00-10:30).
        final server1 = FakeRemoteServerState();
        final p1 = buildProvider(
          server: server1,
          nowProvider: () => DateTime(2026, 11, 23, 10, 15),
        );
        addTearDown(p1.dispose);
        p1
          ..setHost('ftp.example.com')
          ..setSourcePath(src.path)
          ..setDateMode(FtpDateMode.allFiles)
          ..setSkipIfExists(false)
          ..setEnableSchedule(true)
          ..setRunTime(const TimeOfDay(hour: 10, minute: 0))
          ..setRunEndTime(const TimeOfDay(hour: 10, minute: 30))
          ..setOnCompletionAction('stop');

        p1.startSchedule();
        while (p1.isUploading) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(p1.filesUploaded, 1);
        expect(p1.isScheduleArmed, isFalse);

        // Case 2: Overnight window (Tuesday 02:00 inside Mon 22:00 - Tue 06:00, only Mon checked).
        final server2 = FakeRemoteServerState();
        final p2 = buildProvider(
          server: server2,
          nowProvider: () => DateTime(2026, 11, 24, 2, 0),
        );
        addTearDown(p2.dispose);
        p2
          ..setHost('ftp.example.com')
          ..setSourcePath(src.path)
          ..setDateMode(FtpDateMode.allFiles)
          ..setSkipIfExists(false)
          ..setEnableSchedule(true)
          ..setRunTime(const TimeOfDay(hour: 22, minute: 0))
          ..setRunEndTime(const TimeOfDay(hour: 6, minute: 0))
          ..setOnCompletionAction('repeat');
        for (int d = 1; d <= 7; d++) {
          p2.setRunDay(d, d == 1);
        }

        p2.startSchedule();
        while (p2.isUploading) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(p2.filesUploaded, 1);
        expect(p2.isScheduleArmed, isTrue);
        expect(p2.nextScheduledRun, DateTime(2026, 11, 30, 22, 0));
      },
    );

    test(
      'active scheduled upload stops cleanly at runEndTime without errors and respects repeat vs stop',
      () async {
        await LocalDbService().init('ftp_test_win_cutoff');
        HistoryService().init('ftp_test_win_cutoff');
        await HistoryService().clearHistory(allProfiles: false);

        final src = Directory(p.join(tempSourcesDir.path, 'win_cutoff_case'))
          ..createSync(recursive: true);
        File(p.join(src.path, 'a_first.txt')).writeAsBytesSync([1, 2]);
        File(p.join(src.path, 'b_blocked.txt')).writeAsBytesSync([3, 4]);

        // Start armed at 09:55 for window 10:00 - 10:30 on Repeat.
        DateTime clock = DateTime(2026, 11, 23, 9, 55);
        final startedSignal = Completer<void>();
        final server = FakeRemoteServerState()
          ..blockFileName = 'b_blocked.txt'
          ..uploadStartedSignal = startedSignal;
        final provider = buildProvider(
          server: server,
          nowProvider: () => clock,
        );
        addTearDown(provider.dispose);

        provider
          ..setHost('ftp.example.com')
          ..setSourcePath(src.path)
          ..setDateMode(FtpDateMode.allFiles)
          ..setSkipIfExists(false)
          ..setEnableSchedule(true)
          ..setRunTime(const TimeOfDay(hour: 10, minute: 0))
          ..setRunEndTime(const TimeOfDay(hour: 10, minute: 30))
          ..setOnCompletionAction('repeat');

        provider.startSchedule();
        clock = DateTime(2026, 11, 23, 10, 0);
        final runFuture = provider.triggerScheduleTickForTest();
        await startedSignal.future;
        expect(provider.isUploading, isTrue);

        // Advance clock to 10:30 (End time) and tick -> disconnects cleanly.
        clock = DateTime(2026, 11, 23, 10, 30);
        await provider.triggerScheduleTickForTest();
        await runFuture;

        expect(provider.isUploading, isFalse);
        expect(provider.errors, 0);
        expect(provider.filesUploaded, 1);
        expect(server.uploadCalls, ['a_first.txt', 'b_blocked.txt']);
        expect(server.getFile('', 'a_first.txt'), [1, 2]);
        expect(server.getFile('', 'b_blocked.txt'), isNull);
        expect(provider.isScheduleArmed, isTrue);
        expect(provider.nextScheduledRun, DateTime(2026, 11, 24, 10, 0));
        expect(provider.currentStatus, contains('Window ended (10:30)'));

        final records = await HistoryService().loadHistory(
          operation: 'FTP',
          allProfiles: false,
        );
        expect(records, hasLength(1));
        expect(records.first.status, 'Stopped');
        expect(records.first.errors, 0);
        expect(records.first.configSummary, contains('Window Ended (10:30)'));

        // Repeat the cutoff test with onCompletionAction == 'stop' -> disarms cleanly.
        clock = DateTime(2026, 11, 24, 9, 55);
        final startedSignal2 = Completer<void>();
        server
          ..uploadCalls.clear()
          ..uploadStartedSignal = startedSignal2;
        provider
          ..setOnCompletionAction('stop')
          ..stop()
          ..startSchedule();

        clock = DateTime(2026, 11, 24, 10, 0);
        final runFuture2 = provider.triggerScheduleTickForTest();
        await startedSignal2.future;
        clock = DateTime(2026, 11, 24, 10, 30);
        await provider.triggerScheduleTickForTest();
        await runFuture2;

        expect(provider.errors, 0);
        expect(provider.isScheduleArmed, isFalse);
        expect(provider.nextScheduledRun, isNull);
        expect(provider.currentStatus, '⏰ Window ended (10:30)');
      },
    );

    test(
      'manual runNow ignores runEndTime even outside window, and missed windows skip cleanly',
      () async {
        await LocalDbService().init('ftp_test_manual_missed');
        HistoryService().init('ftp_test_manual_missed');

        final src = Directory(p.join(tempSourcesDir.path, 'manual_missed_case'))
          ..createSync(recursive: true);
        File(p.join(src.path, 'manual.txt')).writeAsBytesSync([5, 6]);

        DateTime clock = DateTime(2026, 11, 23, 14, 0); // Outside 10:00-10:30
        final server = FakeRemoteServerState();
        final provider = buildProvider(
          server: server,
          nowProvider: () => clock,
        );
        addTearDown(provider.dispose);

        provider
          ..setHost('ftp.example.com')
          ..setSourcePath(src.path)
          ..setDateMode(FtpDateMode.allFiles)
          ..setSkipIfExists(false)
          ..setEnableSchedule(true)
          ..setRunTime(const TimeOfDay(hour: 10, minute: 0))
          ..setRunEndTime(const TimeOfDay(hour: 10, minute: 30))
          ..setOnCompletionAction('repeat');

        await provider.runNow();
        expect(provider.filesUploaded, 1);
        expect(provider.errors, 0);

        // Arm before 10:00 next day, jump clock past 10:30 (missed window) -> skips upload & reschedules.
        clock = DateTime(2026, 11, 24, 9, 50);
        server.uploadCalls.clear();
        provider.startSchedule();
        expect(provider.nextScheduledRun, DateTime(2026, 11, 24, 10, 0));

        clock = DateTime(2026, 11, 24, 10, 45);
        await provider.triggerScheduleTickForTest();
        expect(server.uploadCalls, isEmpty);
        expect(provider.isScheduleArmed, isTrue);
        expect(provider.nextScheduledRun, DateTime(2026, 11, 25, 10, 0));

        // Missed window with onCompletionAction == 'stop' disarms schedule.
        provider.setOnCompletionAction('stop');
        clock = DateTime(2026, 11, 25, 11, 0);
        await provider.triggerScheduleTickForTest();
        expect(server.uploadCalls, isEmpty);
        expect(provider.isScheduleArmed, isFalse);
        expect(provider.nextScheduledRun, isNull);
        expect(provider.currentStatus, '⏭ Missed scheduled window');
      },
    );

    test(
      'persists ftp_runEndHour/Minute and migrates legacy profiles missing end time keys',
      () async {
        await LocalDbService().init('ftp_test_end_persist');
        final provider = buildProvider(server: FakeRemoteServerState());
        addTearDown(provider.dispose);

        provider
          ..setEnableSchedule(true)
          ..setRunTime(const TimeOfDay(hour: 1, minute: 15))
          ..setRunEndTime(const TimeOfDay(hour: 5, minute: 45));
        await provider.flushSavesForTest();

        expect(LocalDbService().getInt('ftp_runEndHour'), 5);
        expect(LocalDbService().getInt('ftp_runEndMinute'), 45);

        await provider.reloadSettings();
        expect(provider.runEndTime, const TimeOfDay(hour: 5, minute: 45));

        // Legacy active profile without ftp_runEndHour/Minute preserves no-cutoff (runEndTime == runTime).
        await LocalDbService().init('ftp_test_legacy_active');
        await LocalDbService().setBool('ftp_enableSchedule', true);
        await LocalDbService().setInt('ftp_runHour', 3);
        await LocalDbService().setInt('ftp_runMinute', 20);
        await provider.reloadSettings();
        expect(provider.runTime, const TimeOfDay(hour: 3, minute: 20));
        expect(provider.runEndTime, const TimeOfDay(hour: 3, minute: 20));

        // Legacy inactive profile without ftp_runEndHour/Minute defaults runEndTime to 06:00.
        await LocalDbService().init('ftp_test_legacy_inactive');
        await LocalDbService().setBool('ftp_enableSchedule', false);
        await LocalDbService().setInt('ftp_runHour', 2);
        await LocalDbService().setInt('ftp_runMinute', 0);
        await provider.reloadSettings();
        expect(provider.runTime, const TimeOfDay(hour: 2, minute: 0));
        expect(provider.runEndTime, const TimeOfDay(hour: 6, minute: 0));
      },
    );
  });
}
