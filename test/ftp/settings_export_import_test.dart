// Gene - Nov, 23, 2026: Unit and widget tests for JSON settings & multi-directory import/export on FTP and Copy screens.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:files_utility/providers/copy_files_provider.dart';
import 'package:files_utility/providers/ftp_files_provider.dart';
import 'package:files_utility/providers/history_provider.dart';
import 'package:files_utility/providers/theme_provider.dart';
import 'package:files_utility/screens/copy_files_screen.dart';
import 'package:files_utility/services/app_sqlite_service.dart';
import 'package:files_utility/services/ftp_transfer_service.dart';
import 'package:files_utility/services/global_db_service.dart';
import 'package:files_utility/services/history_service.dart';
import 'package:files_utility/services/local_db_service.dart';
import 'package:files_utility/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory appRootDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    appRootDir = Directory.systemTemp.createTempSync(
      'files_utility_export_import_',
    );
    AppSqliteService().appDirPath = appRootDir.path;
    await GlobalDbService().init();
    await LocalDbService().init('default');
    HistoryService().init('default');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDownAll(() async {
    await HistoryService().close();
    await AppSqliteService().close();
    try {
      if (appRootDir.existsSync()) appRootDir.deleteSync(recursive: true);
    } on FileSystemException catch (_) {}
  });

  group('FTP Settings & Upload Sources JSON Export/Import', () {
    test(
      'exports and round-trips full FTP settings while excluding username and password',
      () {
        final source = FtpFilesProvider(persistSettings: false);
        addTearDown(source.dispose);

        source
          ..setProtocol(FtpProtocol.ftpes)
          ..setHost('ftp.prod.example.com')
          ..setPort(2121)
          ..setUsername('example_user')
          ..setPassword('placeholder_val')
          ..setTimeoutSeconds(60)
          ..setUseMultipleSources(true)
          ..setSourcePath('/local/single')
          ..setSubfolders('Sub1, Sub2')
          ..setRemoteDirectory('RemoteRoot')
          ..setSourceNameAt(0, 'Backups')
          ..setSourcePathAt(0, r'\\FILESERVER\Backups')
          ..setSourceSubfoldersAt(0, 'SiteA')
          ..setSourceFtpDestAt(0, 'RemoteBackups')
          ..setSourceRunOrderAt(0, 1)
          ..setSourceEnabledAt(0, true)
          ..addUploadSource()
          ..setSourceNameAt(1, 'Testing')
          ..setSourcePathAt(1, '/tmp/testing')
          ..setSourceEnabledAt(1, false)
          ..setSourceRunOrderAt(1, 2)
          ..setDateMode(FtpDateMode.dateRange)
          ..setDateType(FtpDateType.modified)
          ..setFromDate(DateTime(2026, 3, 10))
          ..setToDate(DateTime(2026, 3, 15))
          ..setIncludeSubfolders(true)
          ..setSkipIfExists(false)
          ..setVerifySizeAfterUpload(false)
          ..setDryRun(true)
          ..setRetryCount(5)
          ..setRetryDelaySeconds(15)
          ..setLogInterval(10)
          ..setLogKeepDays(90)
          ..setEnableSchedule(true)
          ..setRunTime(const TimeOfDay(hour: 2, minute: 30))
          ..setRunDay(6, false)
          ..setOnCompletionAction('stop');

        final exportedJson = source.exportSettingsJsonString(
          now: DateTime(2026, 11, 23, 8, 0),
        );

        expect(exportedJson, isNot(contains('example_user')));
        expect(exportedJson, isNot(contains('placeholder_val')));
        final decoded = jsonDecode(exportedJson) as Map<String, dynamic>;
        expect(decoded['type'], 'ftp_settings');
        final conn = decoded['connection'] as Map<String, dynamic>;
        expect(conn.containsKey('username'), isFalse);
        expect(conn.containsKey('password'), isFalse);

        final target = FtpFilesProvider(persistSettings: false);
        addTearDown(target.dispose);
        final msg = target.importFromJsonString(exportedJson);
        expect(msg, contains('2 source(s)'));

        expect(target.protocol, FtpProtocol.ftpes);
        expect(target.host, 'ftp.prod.example.com');
        expect(target.port, 2121);
        expect(target.username, isEmpty);
        expect(target.password, isEmpty);
        expect(target.timeoutSeconds, 60);
        expect(target.useMultipleSources, isTrue);
        expect(target.uploadSources, hasLength(2));
        expect(target.uploadSources[0].name, 'Backups');
        expect(target.uploadSources[0].localPath, r'\\FILESERVER\Backups');
        expect(target.uploadSources[0].subfolders, 'SiteA');
        expect(target.uploadSources[0].ftpDest, 'RemoteBackups');
        expect(target.uploadSources[0].enabled, isTrue);
        expect(target.uploadSources[1].name, 'Testing');
        expect(target.uploadSources[1].enabled, isFalse);
        expect(target.dateMode, FtpDateMode.dateRange);
        expect(target.dateType, FtpDateType.modified);
        expect(target.fromDate, DateTime(2026, 3, 10));
        expect(target.toDate, DateTime(2026, 3, 15));
        expect(target.includeSubfolders, isTrue);
        expect(target.skipIfExists, isFalse);
        expect(target.verifySizeAfterUpload, isFalse);
        expect(target.dryRun, isTrue);
        expect(target.retryCount, 5);
        expect(target.retryDelaySeconds, 15);
        expect(target.logInterval, 10);
        expect(target.logKeepDays, 90);
        expect(target.enableSchedule, isTrue);
        expect(target.runTime, const TimeOfDay(hour: 2, minute: 30));
        expect(target.runDays[6], isFalse);
        expect(target.onCompletionAction, 'stop');
      },
    );

    test(
      'preserves credentials on same-host FTP import and clears both username and password on host change',
      () {
        final provider = FtpFilesProvider(persistSettings: false);
        addTearDown(provider.dispose);

        provider
          ..setHost('same.example.com')
          ..setUsername('keep_user')
          ..setPassword('keep_me');

        final sameHostJson = jsonEncode({
          'type': 'ftp_settings',
          'connection': {'host': 'same.example.com', 'port': 21},
          'sources': {
            'uploadSources': [
              {'name': 'A', 'localPath': '/tmp/a'},
            ],
          },
        });
        provider.importFromJsonString(sameHostJson);
        expect(provider.username, 'keep_user');
        expect(provider.password, 'keep_me');

        final diffHostJson = jsonEncode({
          'type': 'ftp_settings',
          'connection': {'host': 'other.example.com', 'port': 21},
        });
        provider.importFromJsonString(diffHostJson);
        expect(provider.host, 'other.example.com');
        expect(provider.username, isEmpty);
        expect(provider.password, isEmpty);
      },
    );

    test(
      'exports/imports FTP upload sources without overwriting connection or schedule, and accepts full ftp_settings with sourcesOnly',
      () {
        final donor = FtpFilesProvider(persistSettings: false);
        addTearDown(donor.dispose);
        donor
          ..setHost('donor.example.com')
          ..setSourceNameAt(0, 'AppFiles')
          ..setSourcePathAt(0, '/data/app')
          ..setSourceSubfoldersAt(0, 'FolderA, FolderB')
          ..setSourceRunOrderAt(0, 1)
          ..addUploadSource()
          ..setSourceNameAt(1, 'Archive')
          ..setSourcePathAt(1, '/data/archive')
          ..setSourceFtpDestAt(1, 'ArchiveRemote')
          ..setSourceEnabledAt(1, false)
          ..setSourceRunOrderAt(1, 2);

        final sourcesOnlyJson = donor.exportUploadSourcesJsonString();
        final fullSettingsJson = donor.exportSettingsJsonString();

        final recipient = FtpFilesProvider(persistSettings: false);
        addTearDown(recipient.dispose);
        recipient
          ..setHost('recipient.example.com')
          ..setUsername('recipient_user')
          ..setPassword('recipient_pw')
          ..setEnableSchedule(true)
          ..setRunTime(const TimeOfDay(hour: 4, minute: 15));

        final msg = recipient.importFromJsonString(sourcesOnlyJson);
        expect(msg, contains('2 upload source(s)'));
        expect(recipient.useMultipleSources, isTrue);
        expect(recipient.uploadSources, hasLength(2));
        expect(recipient.uploadSources[0].name, 'AppFiles');
        expect(recipient.uploadSources[1].enabled, isFalse);
        // Connection & schedule remain untouched.
        expect(recipient.host, 'recipient.example.com');
        expect(recipient.username, 'recipient_user');
        expect(recipient.password, 'recipient_pw');
        expect(recipient.runTime, const TimeOfDay(hour: 4, minute: 15));

        // Also supports extracting sources from a full ftp_settings JSON when sourcesOnly is true.
        final recipient2 = FtpFilesProvider(persistSettings: false);
        addTearDown(recipient2.dispose);
        recipient2.setHost('stay.example.com');
        recipient2.importFromJsonString(fullSettingsJson, sourcesOnly: true);
        expect(recipient2.host, 'stay.example.com');
        expect(recipient2.uploadSources, hasLength(2));
      },
    );
  });

  group('Copy Settings & Directory Pairs JSON Export/Import', () {
    test(
      'exports and round-trips full Copy settings and clamps invalid values',
      () {
        final source = CopyFilesProvider(persistSettings: false);
        addTearDown(source.dispose);

        source
          ..setUseMultipleDirectories(true)
          ..setSourcePath('/src/single')
          ..setDestPath('/dst/single')
          ..setPairSource(0, '/src/pair1')
          ..setPairDest(0, '/dst/pair1')
          ..setPairRunOrder(0, 1)
          ..addDirectoryPair()
          ..setPairSource(1, '/src/pair2')
          ..setPairDest(1, '/dst/pair2')
          ..setPairRunOrder(1, 3)
          ..setEnableDateRange(true)
          ..setFromDate(DateTime(2026, 5, 1))
          ..setToDate(DateTime(2026, 5, 15))
          ..setLogInterval(25)
          ..setEnableTimeWindow(true)
          ..setRunFromTime(const TimeOfDay(hour: 1, minute: 0))
          ..setRunToTime(const TimeOfDay(hour: 5, minute: 30))
          ..setRunDay(1, true)
          ..setRunDay(5, true)
          ..setOnCompletionAction('stop');

        final exported = source.exportSettingsJsonString(
          now: DateTime(2026, 11, 23, 8, 0),
        );

        final target = CopyFilesProvider(persistSettings: false);
        addTearDown(target.dispose);
        final msg = target.importFromJsonString(exported);
        expect(msg, contains('2 pair(s)'));

        expect(target.useMultipleDirectories, isTrue);
        expect(target.sourcePath, '/src/single');
        expect(target.destPath, '/dst/single');
        expect(target.directoryPairs, hasLength(2));
        expect(target.directoryPairs[0].sourcePath, '/src/pair1');
        expect(target.directoryPairs[0].destPath, '/dst/pair1');
        expect(target.directoryPairs[1].runOrder, 3);
        expect(target.enableDateRange, isTrue);
        expect(target.fromDate, DateTime(2026, 5, 1));
        expect(target.toDate, DateTime(2026, 5, 15));
        expect(target.logInterval, 25);
        expect(target.enableTimeWindow, isTrue);
        expect(target.runFromTime, const TimeOfDay(hour: 1, minute: 0));
        expect(target.runToTime, const TimeOfDay(hour: 5, minute: 30));
        expect(target.runDays[1], isTrue);
        expect(target.runDays[5], isTrue);
        expect(target.onCompletionAction, 'stop');

        // Clamping check on out-of-range values.
        final clamped = CopyFilesProvider(persistSettings: false);
        addTearDown(clamped.dispose);
        clamped.importFromJsonString(
          jsonEncode({
            'type': 'copy_settings',
            'directories': {
              'directoryPairs': [
                {'source': '/a', 'dest': '/b', 'runOrder': 99},
              ],
            },
            'filters': {
              'enableAgeFilter': true,
              'ageFilterUnit': 'Months',
              'ageFilterValue': 999,
            },
            'options': {'logInterval': 777},
          }),
        );
        expect(clamped.directoryPairs.first.runOrder, 10);
        expect(clamped.ageFilterValue, 31);
        expect(clamped.logInterval, 100);
      },
    );

    test(
      'exports/imports Copy directory pairs without overwriting filters or schedule',
      () {
        final donor = CopyFilesProvider(persistSettings: false);
        addTearDown(donor.dispose);
        donor
          ..setPairSource(0, '/p1/src')
          ..setPairDest(0, '/p1/dst')
          ..setPairRunOrder(0, 1)
          ..addDirectoryPair()
          ..setPairSource(1, '/p2/src')
          ..setPairDest(1, '/p2/dst')
          ..setPairRunOrder(1, 2);

        final pairsJson = donor.exportDirectoryPairsJsonString();

        final recipient = CopyFilesProvider(persistSettings: false);
        addTearDown(recipient.dispose);
        recipient
          ..setLogInterval(10)
          ..setOnCompletionAction('stop');

        final msg = recipient.importFromJsonString(pairsJson);
        expect(msg, contains('2 directory pair(s)'));
        expect(recipient.useMultipleDirectories, isTrue);
        expect(recipient.directoryPairs, hasLength(2));
        expect(recipient.directoryPairs[1].destPath, '/p2/dst');
        expect(recipient.logInterval, 10);
        expect(recipient.onCompletionAction, 'stop');
      },
    );

    test('rejects cross-type JSON imports cleanly', () {
      final ftp = FtpFilesProvider(persistSettings: false);
      final copy = CopyFilesProvider(persistSettings: false);
      addTearDown(ftp.dispose);
      addTearDown(copy.dispose);

      expect(
        () => ftp.importFromJsonString(copy.exportSettingsJsonString()),
        throwsFormatException,
      );
      expect(
        () => ftp.importFromJsonString(copy.exportDirectoryPairsJsonString()),
        throwsFormatException,
      );
      expect(
        () => copy.importFromJsonString(ftp.exportSettingsJsonString()),
        throwsFormatException,
      );
      expect(
        () => copy.importFromJsonString(ftp.exportUploadSourcesJsonString()),
        throwsFormatException,
      );
    });
  });

  group('CopyFilesScreen Import/Export UI', () {
    for (final size in const [Size(980, 680), Size(1280, 840)]) {
      testWidgets(
        'renders Copy import/export buttons and Directory Pairs dialog cleanly at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          final copyProvider = CopyFilesProvider(persistSettings: false);
          addTearDown(copyProvider.dispose);

          await tester.pumpWidget(
            MultiProvider(
              providers: [
                // ChangeNotifierProvider(create: (_) => ThemeProvider()),
                // ChangeNotifierProvider(create: (_) => HistoryProvider()),
                // Gene - Nov, 23, 2026: Disable constructor SQLite queries in widget tests to avoid sqflite FakeAsync 10s timer leaks
                ChangeNotifierProvider(
                  create: (_) => ThemeProvider(persistSettings: false),
                ),
                ChangeNotifierProvider(
                  create: (_) => HistoryProvider(loadOnInit: false),
                ),
                ChangeNotifierProvider<CopyFilesProvider>.value(
                  value: copyProvider,
                ),
              ],
              child: MaterialApp(
                theme: AppTheme.lightTheme,
                darkTheme: AppTheme.darkTheme,
                home: const CopyFilesScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(
            find.byKey(const Key('copy_import_settings_btn')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('copy_export_settings_btn')),
            findsOneWidget,
          );

          copyProvider.setUseMultipleDirectories(true);
          await tester.pump();
          await tester.tap(find.text('Edit Pairs'));
          await tester.pumpAndSettle();

          expect(
            find.byKey(const Key('copy_pairs_import_btn')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('copy_pairs_export_btn')),
            findsOneWidget,
          );

          await tester.tap(find.text('Done'));
          await tester.pumpAndSettle();
        },
      );
    }
  });
}
