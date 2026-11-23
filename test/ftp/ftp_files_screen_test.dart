// Gene - Nov, 21, 2026: Widget tests for FtpFilesScreen and MainScreen 5-card dashboard at 980x680 and 1280x840 viewports.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
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
}
