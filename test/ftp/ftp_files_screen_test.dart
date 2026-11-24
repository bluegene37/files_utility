// Gene - Nov, 21, 2026: Widget tests for FtpFilesScreen and MainScreen 5-card dashboard at 980x680 and 1280x840 viewports.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
// Gene - Nov, 24, 2026: Import FtpUploadSource and path for per-source schedule/filter and Run Selected widget tests.
import 'package:path/path.dart' as p;
import 'package:files_utility/models/ftp_upload_source.dart';
import 'package:files_utility/providers/ftp_files_provider.dart';
import 'package:files_utility/providers/history_provider.dart';
import 'package:files_utility/providers/theme_provider.dart';
import 'package:files_utility/providers/update_provider.dart';
import 'package:files_utility/screens/ftp_files_screen.dart';
import 'package:files_utility/screens/main_screen.dart';
import 'package:files_utility/services/app_sqlite_service.dart';
import 'package:files_utility/services/ftp_transfer_service.dart';
import 'package:files_utility/services/global_db_service.dart';
import 'package:files_utility/services/history_service.dart';
import 'package:files_utility/services/local_db_service.dart';
import 'package:files_utility/services/update/update_info.dart';
import 'package:files_utility/services/update/update_service.dart';
import 'package:files_utility/theme/app_theme.dart';

class _NoopFtpClient implements FtpClientAdapter {
  @override
  Future<bool> changeDirectory(String remotePath) async => true;

  @override
  Future<void> connect() async {}

  @override
  Future<String> currentDirectory() async => '/';

  @override
  Future<void> disconnect() async {}

  @override
  Future<bool> ensureRemoteDirectory(String remotePath) async => true;

  @override
  Future<int?> getRemoteFileSize(String remoteName) async => null;

  @override
  Future<Map<String, int?>?> listRemoteFileSizes() async => {};

  //   @override
  //   Future<bool> uploadFile(File localFile, {String? remoteName}) async => true;
  // Gene - Nov, 23, 2026: Update _NoopFtpClient signature for FtpUploadProgressCallback.
  @override
  Future<bool> uploadFile(
    File localFile, {
    String? remoteName,
    FtpUploadProgressCallback? onProgress,
  }) async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory appRootDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    appRootDir = Directory.systemTemp.createTempSync(
      'files_utility_ftp_widget_',
    );
    AppSqliteService().appDirPath = appRootDir.path;
    await GlobalDbService().init();
    await LocalDbService().init('default');
    HistoryService().init('default');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // Gene - Nov, 22, 2026: Close SQLite handles before deleting temp directory to avoid Windows errno 32 file-lock failures in tearDownAll
  // tearDownAll(() {
  //   if (appRootDir.existsSync()) appRootDir.deleteSync(recursive: true);
  // });
  tearDownAll(() async {
    await HistoryService().close();
    await AppSqliteService().close();
    try {
      if (appRootDir.existsSync()) appRootDir.deleteSync(recursive: true);
    } on FileSystemException catch (_) {}
  });

  Widget buildFtpTestApp(FtpFilesProvider ftpProvider) {
    return MultiProvider(
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
        ChangeNotifierProvider<FtpFilesProvider>.value(value: ftpProvider),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: const FtpFilesScreen(),
      ),
    );
  }

  Widget buildMainTestApp(FtpFilesProvider ftpProvider) {
    return MultiProvider(
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
        ChangeNotifierProvider<FtpFilesProvider>.value(value: ftpProvider),
        ChangeNotifierProvider(
          create: (_) => UpdateProvider(
            service: UpdateService(
              currentVersion: '1.1.2',
              platform: UpdatePlatform.macos,
              fetchRelease: (_) async => {
                'tag_name': 'v1.1.2',
                'html_url': 'https://example.com/releases/v1.1.2',
                'assets': <dynamic>[],
              },
            ),
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: const MainScreen(),
      ),
    );
  }

  for (final size in const [Size(980, 680), Size(1280, 840)]) {
    testWidgets(
      'MainScreen renders 5 dashboard cards and 5 analytics bars without overflow at ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final provider = FtpFilesProvider(
          clientFactory: (_) => _NoopFtpClient(),
          persistSettings: false,
        );
        addTearDown(provider.dispose);

        await tester.pumpWidget(buildMainTestApp(provider));
        await tester.pumpAndSettle();

        expect(find.text('Transfer Files'), findsOneWidget);
        expect(find.text('Copy Files'), findsOneWidget);
        expect(find.text('Delete Files'), findsOneWidget);
        expect(find.text('Count Files'), findsOneWidget);
        expect(find.text('FTP Upload'), findsOneWidget);
        expect(find.text('FTP'), findsOneWidget);
      },
    );

    testWidgets(
      'FtpFilesScreen renders cleanly without overflow at ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final provider = FtpFilesProvider(
          clientFactory: (_) => _NoopFtpClient(),
          persistSettings: false,
        );
        addTearDown(provider.dispose);

        await tester.pumpWidget(buildFtpTestApp(provider));
        await tester.pumpAndSettle();

        expect(find.text('FTP Connection'), findsOneWidget);
        expect(find.byKey(const Key('ftp_start_upload_btn')), findsOneWidget);
      },
    );
  }

  testWidgets(
    'FtpFilesScreen toggles connection card, password visibility, schedule buttons, dry-run pill, and multi-source dialog',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 840);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final provider = FtpFilesProvider(
        clientFactory: (_) => _NoopFtpClient(),
        persistSettings: false,
      );
      addTearDown(provider.dispose);

      await tester.pumpWidget(buildFtpTestApp(provider));
      await tester.pumpAndSettle();

      // Connection card starts expanded when host is empty.
      expect(find.byKey(const Key('ftp_host_field')), findsOneWidget);

      // Password field starts obscured, then reveals when eye icon is tapped.
      TextField passField = tester.widget<TextField>(
        find.byKey(const Key('ftp_password_field')),
      );
      expect(passField.obscureText, isTrue);

      await tester.tap(find.byKey(const Key('ftp_password_visibility_btn')));
      await tester.pump();
      passField = tester.widget<TextField>(
        find.byKey(const Key('ftp_password_field')),
      );
      expect(passField.obscureText, isFalse);

      // Collapsing FTP Connection hides the form fields.
      await tester.tap(find.byKey(const Key('ftp_connection_header')));
      await tester.pump();
      expect(find.byKey(const Key('ftp_host_field')), findsNothing);

      // Expanding restores the form fields.
      await tester.tap(find.byKey(const Key('ftp_connection_header')));
      await tester.pump();
      expect(find.byKey(const Key('ftp_host_field')), findsOneWidget);

      // Open Advanced Settings and toggle Dry Run + Schedule ON.
      await tester.tap(find.byKey(const Key('ftp_advanced_settings_btn')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Advanced Settings'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('ftp_dry_run_checkbox')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('ftp_enable_schedule_checkbox')));
      await tester.pump();

      // Gene - Nov, 24, 2026: Verify Start and End schedule pickers and window helper text appear in Advanced Settings.
      expect(
        find.byKey(const Key('ftp_schedule_start_time_picker')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('ftp_schedule_end_time_picker')),
        findsOneWidget,
      );
      expect(find.text('Start'), findsOneWidget);
      expect(find.text('End'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // Main screen shows DRY RUN badge, schedule Start – End pill, and Start Schedule + Run Now buttons.
      expect(find.text('DRY RUN'), findsOneWidget);
      expect(find.textContaining('–'), findsWidgets);
      expect(find.byKey(const Key('ftp_start_schedule_btn')), findsOneWidget);
      expect(find.byKey(const Key('ftp_run_now_btn')), findsOneWidget);
      expect(find.byKey(const Key('ftp_start_upload_btn')), findsNothing);

      // Toggle Multiple Sources and open Edit Sources dialog.
      await tester.tap(find.byKey(const Key('ftp_multiple_sources_checkbox')));
      await tester.pump();
      expect(find.text('Edit Sources'), findsOneWidget);

      await tester.tap(find.text('Edit Sources'));
      await tester.pumpAndSettle();
      expect(find.text('Upload Sources'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
    },
  );

  // Gene - Nov, 23, 2026: Verify clicking Test Connection never collapses or expands the FTP Connection card.
  testWidgets(
    'Clicking Test Connection does not collapse or expand the FTP Connection card',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 840);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final provider = FtpFilesProvider(
        clientFactory: (_) => _NoopFtpClient(),
        persistSettings: false,
      );
      addTearDown(provider.dispose);

      await tester.pumpWidget(buildFtpTestApp(provider));
      await tester.pumpAndSettle();

      // Connection card starts expanded when host is empty.
      expect(find.byKey(const Key('ftp_host_field')), findsOneWidget);

      // Tapping Test Connection while disabled (host empty) must not collapse the card.
      await tester.tap(find.byKey(const Key('ftp_test_connection_btn')));
      await tester.pump();
      expect(find.byKey(const Key('ftp_host_field')), findsOneWidget);

      // Enter host so Test Connection becomes enabled, tap it, and verify card stays expanded.
      await tester.enterText(
        find.byKey(const Key('ftp_host_field')),
        'ftp.example.com',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('ftp_test_connection_btn')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ftp_host_field')), findsOneWidget);
      expect(
        provider.logs.any((l) => l.contains('Connected (FTP) — CWD: /')),
        isTrue,
      );
      expect(find.textContaining('Connected (FTP) — CWD: /'), findsWidgets);

      // Collapse the card using the dedicated chevron toggle.
      await tester.tap(find.byKey(const Key('ftp_connection_expand_btn')));
      await tester.pump();
      expect(find.byKey(const Key('ftp_host_field')), findsNothing);

      // Tapping Test Connection while collapsed must not expand the card.
      await tester.tap(find.byKey(const Key('ftp_test_connection_btn')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ftp_host_field')), findsNothing);

      // Re-expand via the header title area.
      await tester.tap(find.byKey(const Key('ftp_connection_header')));
      await tester.pump();
      expect(find.byKey(const Key('ftp_host_field')), findsOneWidget);
    },
  );

  // Gene - Nov, 23, 2026: Verify app bar actions, Log Retention dropdown, per-source enable checkbox, and live progress bar at 980x680 and 1280x840.
  testWidgets(
    'FtpFilesScreen exposes Import/Logs actions, Log Retention, per-source toggle, and live upload progress bar',
    (tester) async {
      tester.view.physicalSize = const Size(980, 680);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final provider = FtpFilesProvider(
        clientFactory: (_) => _NoopFtpClient(),
        persistSettings: false,
      );
      addTearDown(provider.dispose);

      await tester.pumpWidget(buildFtpTestApp(provider));
      await tester.pumpAndSettle();

      // App bar buttons present (including JSON export).
      expect(find.byKey(const Key('ftp_import_ini_btn')), findsOneWidget);
      expect(find.byKey(const Key('ftp_export_settings_btn')), findsOneWidget);
      expect(find.byKey(const Key('ftp_open_logs_btn')), findsOneWidget);

      // Advanced Settings -> Log Retention dropdown (scroll into view on 980x680 viewport).
      final advBtn = find.byKey(const Key('ftp_advanced_settings_btn'));
      await tester.ensureVisible(advBtn);
      await tester.pumpAndSettle();
      await tester.tap(advBtn);
      await tester.pumpAndSettle();
      final retentionDropdown = find.byKey(
        const Key('ftp_log_retention_dropdown'),
      );
      expect(retentionDropdown, findsOneWidget);
      await tester.ensureVisible(retentionDropdown);
      await tester.pumpAndSettle();
      await tester.tap(retentionDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('14 days').last);
      await tester.pumpAndSettle();
      expect(provider.logKeepDays, 14);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // Multiple Sources -> per-source enable checkbox updates active count.
      final multiCheckbox = find.byKey(
        const Key('ftp_multiple_sources_checkbox'),
      );
      await tester.ensureVisible(multiCheckbox);
      await tester.pumpAndSettle();
      await tester.tap(multiCheckbox);
      await tester.pump();
      await tester.tap(find.text('Edit Sources'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ftp_sources_import_btn')), findsOneWidget);
      expect(find.byKey(const Key('ftp_sources_export_btn')), findsOneWidget);
      await tester.tap(find.text('Add Source'));
      await tester.pump();
      expect(find.byKey(const Key('ftp_source_enabled_0')), findsOneWidget);
      await tester.tap(find.byKey(const Key('ftp_source_enabled_0')));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('1/2 sources active'), findsOneWidget);

      // Switch back to single source and verify live progress bar renders without overflow.
      await tester.ensureVisible(multiCheckbox);
      await tester.pumpAndSettle();
      await tester.tap(multiCheckbox);
      await tester.pump();

      provider.setUploadProgressForTest(
        uploading: true,
        fileName: 'large.bak',
        sentBytes: 512,
        totalBytes: 1024,
        progress: 0.5,
        bytesPerSecond: 256,
      );
      await tester.pump();

      expect(find.byKey(const Key('ftp_upload_progress_bar')), findsOneWidget);
      expect(find.textContaining('50.0%'), findsWidgets);

      // Also verify 1280x840 viewport while progress bar is visible.
      tester.view.physicalSize = const Size(1280, 840);
      await tester.pump();
      expect(find.byKey(const Key('ftp_upload_progress_bar')), findsOneWidget);

      provider.setUploadProgressForTest(uploading: false);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ftp_upload_progress_bar')), findsNothing);
    },
  );

  // Gene - Nov, 24, 2026: Verify Start/End schedule pickers render without overflow at 980x680 and pill adapts when Start == End.
  testWidgets(
    'FtpFilesScreen renders Start/End schedule controls at 980x680 without overflow and hides range when Start == End',
    (tester) async {
      tester.view.physicalSize = const Size(980, 680);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final provider =
          FtpFilesProvider(
              clientFactory: (_) => _NoopFtpClient(),
              persistSettings: false,
            )
            ..setEnableSchedule(true)
            ..setRunTime(const TimeOfDay(hour: 22, minute: 0))
            ..setRunEndTime(const TimeOfDay(hour: 6, minute: 0));
      addTearDown(provider.dispose);

      await tester.pumpWidget(buildFtpTestApp(provider));
      await tester.pumpAndSettle();

      // Overnight window range shown on main screen schedule pill.
      expect(find.textContaining('–'), findsWidgets);

      final advBtn = find.byKey(const Key('ftp_advanced_settings_btn'));
      await tester.ensureVisible(advBtn);
      await tester.pumpAndSettle();
      await tester.tap(advBtn);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('ftp_schedule_start_time_picker')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('ftp_schedule_end_time_picker')),
        findsOneWidget,
      );
      expect(find.textContaining('Overnight window'), findsOneWidget);

      // Setting Start == End updates helper copy and removes range separator from pill.
      provider.setRunEndTime(const TimeOfDay(hour: 22, minute: 0));
      await tester.pump();
      expect(find.textContaining('no end cutoff'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.textContaining('–'), findsNothing);
    },
  );

  // Gene - Nov, 24, 2026: Verify per-source schedule/filter UI, monthly Reset button, Run Selected dialog, and 980x680 layout with both Schedule + Multiple Sources.
  testWidgets(
    'FtpFilesScreen renders per-source schedule/filter controls, resets monthly completion, and executes Run Selected without 980x680 overflow',
    (tester) async {
      tester.view.physicalSize = const Size(980, 680);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tempRoot = Directory.systemTemp.createTempSync(
        'files_utility_ftp_screen_sel_',
      );
      addTearDown(() {
        if (tempRoot.existsSync()) {
          tempRoot.deleteSync(recursive: true);
        }
      });
      final dailyDir = Directory(p.join(tempRoot.path, 'daily'))
        ..createSync(recursive: true);
      final dbDir = Directory(p.join(tempRoot.path, 'database'))
        ..createSync(recursive: true);
      final dailyFile = File(p.join(dailyDir.path, 'daily.txt'))
        ..writeAsBytesSync([1, 2]);
      final dbFile = File(p.join(dbDir.path, 'db.bak'))
        ..writeAsBytesSync([3, 4, 5]);
      dailyFile.setLastModifiedSync(DateTime(2026, 11, 24, 8, 0));
      dbFile.setLastModifiedSync(DateTime(2026, 11, 20, 12, 0));

      final uploadedNames = <String>[];
      final fakeClient = _RecordingNoopFtpClient(uploadedNames);

      final provider = FtpFilesProvider(
        clientFactory: (_) => fakeClient,
        nowProvider: () => DateTime(2026, 11, 24, 9, 0),
        persistSettings: false,
      )
        ..setHost('ftp.example.com')
        ..setUseMultipleSources(true)
        ..setEnableSchedule(true)
        ..setSkipIfExists(false)
        ..setDateType(FtpDateType.modified)
        ..setDateMode(FtpDateMode.allFiles)
        ..setSourceNameAt(0, 'Daily')
        ..setSourcePathAt(0, dailyDir.path)
        ..addUploadSource()
        ..setSourceNameAt(1, 'Database')
        ..setSourcePathAt(1, dbDir.path)
        ..setSourceScheduleModeAt(1, FtpSourceScheduleMode.monthly)
        ..setSourceMonthlyDayAt(1, 1)
        ..setSourceDateFilterModeAt(1, FtpSourceDateFilterMode.lastNDays)
        ..setSourceDateFilterDaysAt(1, 30);

      provider.uploadSources[1] = provider.uploadSources[1].copyWith(
        lastCompletedMonth: '2026-11',
        lastCompletedAt: '2026-11-01T00:05:00.000',
      );
      addTearDown(provider.dispose);

      // Pump with BOTH enableSchedule + useMultipleSources active at 980x680 -> no RenderFlex overflow.
      await tester.pumpWidget(buildFtpTestApp(provider));
      await tester.pumpAndSettle();

      expect(find.text('2 sources configured (1 monthly)'), findsOneWidget);
      expect(find.byKey(const Key('ftp_run_selected_btn')), findsOneWidget);
      expect(find.byKey(const Key('ftp_start_schedule_btn')), findsOneWidget);
      expect(find.byKey(const Key('ftp_run_now_btn')), findsOneWidget);

      // Open Edit Sources dialog and verify cadence/filter controls + monthly Done/Reset.
      await tester.tap(find.text('Edit Sources'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ftp_source_schedule_0')), findsOneWidget);
      expect(find.byKey(const Key('ftp_source_date_filter_0')), findsOneWidget);

      final monthlyDayFinder = find.byKey(const Key('ftp_source_monthly_day_1'));
      await tester.ensureVisible(monthlyDayFinder);
      await tester.pumpAndSettle();
      expect(monthlyDayFinder, findsOneWidget);
      expect(find.byKey(const Key('ftp_source_date_days_1')), findsOneWidget);
      expect(find.text('Done Nov 2026'), findsOneWidget);

      final resetBtn = find.byKey(const Key('ftp_source_monthly_reset_1'));
      await tester.ensureVisible(resetBtn);
      await tester.pumpAndSettle();
      await tester.tap(resetBtn);
      await tester.pump();
      expect(provider.uploadSources[1].lastCompletedMonth, isNull);
      expect(find.text('Due now (catch-up)'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // Open Run Selected... dialog, uncheck Daily (0), keep Database (1), and run!
      final runSelectedBtn = find.byKey(const Key('ftp_run_selected_btn'));
      await tester.ensureVisible(runSelectedBtn);
      await tester.pumpAndSettle();
      await tester.tap(runSelectedBtn);
      await tester.pumpAndSettle();

      expect(find.text('Run Selected Sources'), findsOneWidget);
      expect(find.byKey(const Key('ftp_select_source_0')), findsOneWidget);
      expect(find.byKey(const Key('ftp_select_source_1')), findsOneWidget);
      expect(
        find.byKey(const Key('ftp_select_mark_monthly_checkbox')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('ftp_select_source_0')));
      await tester.pump();
      expect(find.text('Upload Selected (1)'), findsOneWidget);

      await tester.tap(find.byKey(const Key('ftp_run_selected_confirm_btn')));
      await tester.pump();
      for (int tick = 0; tick < 50 && provider.isUploading; tick++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(
        uploadedNames,
        ['db.bak'],
        reason:
            'isUploading=${provider.isUploading}, errors=${provider.errors}, logs=${provider.logs}',
      );
      expect(provider.uploadSources[1].lastCompletedMonth, isNull);
    },
  );

  // Gene - Nov, 24, 2026: Verify Weekly presets (Weekends, Sat Only, Sun Only), unchecked-day copy, Monthly frequency controls, and main screen pill at 980x680 without overflow.
  testWidgets(
    'FtpFilesScreen supports weekly presets and global Monthly schedule without 980x680 overflow',
    (tester) async {
      tester.view.physicalSize = const Size(980, 680);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final provider = FtpFilesProvider(
        clientFactory: (_) => _NoopFtpClient(),
        persistSettings: false,
      )
        ..setEnableSchedule(true)
        ..setRunTime(const TimeOfDay(hour: 2, minute: 0))
        ..setRunEndTime(const TimeOfDay(hour: 2, minute: 0));
      addTearDown(provider.dispose);

      await tester.pumpWidget(buildFtpTestApp(provider));
      await tester.pumpAndSettle();

      expect(find.textContaining('Daily (Repeat)'), findsOneWidget);
      expect(find.textContaining('–'), findsNothing);

      final advBtn = find.byKey(const Key('ftp_advanced_settings_btn'));
      await tester.ensureVisible(advBtn);
      await tester.pumpAndSettle();
      await tester.tap(advBtn);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('ftp_schedule_frequency_dropdown')),
        findsOneWidget,
      );
      expect(
        find.textContaining('unchecked days will not run'),
        findsOneWidget,
      );

      // Tap Weekends, Sat Only, Sun Only presets.
      final weekendsChip = find.byKey(
        const Key('ftp_schedule_preset_weekends'),
      );
      await tester.ensureVisible(weekendsChip);
      await tester.pumpAndSettle();
      await tester.tap(weekendsChip);
      await tester.pump();
      expect(provider.runDays[6], isTrue);
      expect(provider.runDays[7], isTrue);
      expect(provider.runDays[1], isFalse);

      await tester.tap(find.byKey(const Key('ftp_schedule_preset_sat')));
      await tester.pump();
      expect(provider.runDays[6], isTrue);
      expect(provider.runDays[7], isFalse);

      await tester.tap(find.byKey(const Key('ftp_schedule_preset_sun')));
      await tester.pump();
      expect(provider.runDays[6], isFalse);
      expect(provider.runDays[7], isTrue);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Sun (Repeat)'), findsOneWidget);

      // Switch Frequency to Monthly (Once a Month) and pick Last day of month.
      await tester.ensureVisible(advBtn);
      await tester.pumpAndSettle();
      await tester.tap(advBtn);
      await tester.pumpAndSettle();

      final freqDropdown = find.byKey(
        const Key('ftp_schedule_frequency_dropdown'),
      );
      await tester.ensureVisible(freqDropdown);
      await tester.pumpAndSettle();
      await tester.tap(freqDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Monthly (Once a Month)').last);
      await tester.pumpAndSettle();

      expect(
        provider.scheduleFrequency,
        FtpScheduleFrequency.monthly,
      );
      expect(find.byKey(const Key('ftp_schedule_day_1')), findsNothing);

      final monthlyDropdown = find.byKey(
        const Key('ftp_schedule_monthly_day_dropdown'),
      );
      expect(monthlyDropdown, findsOneWidget);
      await tester.ensureVisible(monthlyDropdown);
      await tester.pumpAndSettle();
      await tester.tap(monthlyDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Last day of month').last);
      await tester.pumpAndSettle();
      expect(provider.scheduleMonthlyDay, 0);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Monthly (Last day) (Repeat)'), findsOneWidget);
      expect(find.textContaining('–'), findsNothing);
    },
  );
}

class _RecordingNoopFtpClient extends _NoopFtpClient {
  final List<String> uploadedNames;

  _RecordingNoopFtpClient(this.uploadedNames);

  @override
  Future<bool> uploadFile(
    File localFile, {
    String? remoteName,
    FtpUploadProgressCallback? onProgress,
  }) async {
    uploadedNames.add(remoteName ?? p.basename(localFile.path));
    return true;
  }
}
