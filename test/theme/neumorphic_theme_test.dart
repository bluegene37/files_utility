// Gene - Nov, 22, 2026: Regression and verification tests for Batterie-matched soft Neumorphism themes and post-merge UI layouts.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:files_utility/providers/history_provider.dart';
import 'package:files_utility/providers/theme_provider.dart';
import 'package:files_utility/providers/transfer_files_provider.dart';
import 'package:files_utility/providers/update_provider.dart';
import 'package:files_utility/screens/main_screen.dart';
import 'package:files_utility/screens/transfer_files_screen.dart';
import 'package:files_utility/services/app_sqlite_service.dart';
import 'package:files_utility/services/global_db_service.dart';
import 'package:files_utility/services/history_service.dart';
import 'package:files_utility/services/local_db_service.dart';
import 'package:files_utility/services/update/update_info.dart';
import 'package:files_utility/services/update/update_service.dart';
import 'package:files_utility/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory appRootDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    appRootDir = Directory.systemTemp.createTempSync(
      'files_utility_theme_test_',
    );
    AppSqliteService().appDirPath = appRootDir.path;
    await GlobalDbService().init();
    await LocalDbService().init('default');
    HistoryService().init('default');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDownAll(() {
    if (appRootDir.existsSync()) appRootDir.deleteSync(recursive: true);
  });

  group('Batterie-matched Neumorphic Theme Tokens', () {
    test('lightTheme uses Soft Slate #E0E5EC and Royal Blue #2563EB', () {
      final theme = AppTheme.lightTheme;
      expect(theme.brightness, Brightness.light);
      expect(theme.scaffoldBackgroundColor, const Color(0xFFE0E5EC));
      expect(theme.colorScheme.surface, const Color(0xFFE0E5EC));
      expect(theme.colorScheme.primary, const Color(0xFF2563EB));
    });

    test('darkTheme uses Dark Slate #1E222A and Electric Blue #3B82F6', () {
      final theme = AppTheme.darkTheme;
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, const Color(0xFF1E222A));
      expect(theme.colorScheme.surface, const Color(0xFF1E222A));
      expect(theme.colorScheme.primary, const Color(0xFF3B82F6));
    });

    testWidgets(
      'NeumorphicTheme.raisedShadows and softShadows emit dual highlight/shadow lists in light and dark modes',
      (tester) async {
        late List<BoxShadow> lightRaised;
        late List<BoxShadow> lightSoft;
        late List<BoxShadow> darkRaised;
        late List<BoxShadow> darkSoft;

        await tester.pumpWidget(
          Column(
            children: [
              Theme(
                data: AppTheme.lightTheme,
                child: Builder(
                  builder: (ctx) {
                    lightRaised = NeumorphicTheme.raisedShadows(ctx);
                    lightSoft = NeumorphicTheme.softShadows(ctx);
                    return const SizedBox.shrink();
                  },
                ),
              ),
              Theme(
                data: AppTheme.darkTheme,
                child: Builder(
                  builder: (ctx) {
                    darkRaised = NeumorphicTheme.raisedShadows(ctx);
                    darkSoft = NeumorphicTheme.softShadows(ctx);
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ],
          ),
        );

        expect(lightRaised, hasLength(2));
        expect(lightSoft, hasLength(2));
        expect(lightRaised.first.offset.dx, lessThan(0));
        expect(lightRaised.last.offset.dx, greaterThan(0));

        expect(darkRaised, hasLength(2));
        expect(darkSoft, hasLength(2));
        expect(darkRaised.first.offset.dx, lessThan(0));
        expect(darkRaised.last.offset.dx, greaterThan(0));
      },
    );
  });

  group('Screen Layouts Across Themes and Viewports', () {
    for (final brightness in const [Brightness.light, Brightness.dark]) {
      for (final size in const [Size(980, 680), Size(1280, 840)]) {
        testWidgets(
          'MainScreen renders cleanly in ${brightness.name} mode at ${size.width.toInt()}x${size.height.toInt()}',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            late ThemeProvider themeProvider;
            late HistoryProvider historyProvider;
            late UpdateProvider updateProvider;

            await tester.runAsync(() async {
              themeProvider = ThemeProvider();
              historyProvider = HistoryProvider();
              updateProvider = UpdateProvider(
                service: UpdateService(
                  currentVersion: '1.1.2',
                  platform: UpdatePlatform.macos,
                  fetchRelease: (_) async => {
                    'tag_name': 'v1.1.2',
                    'html_url': 'https://example.com/releases/v1.1.2',
                    'assets': <dynamic>[],
                  },
                ),
              );
              await Future<void>.delayed(const Duration(milliseconds: 80));
            });

            addTearDown(themeProvider.dispose);
            addTearDown(historyProvider.dispose);
            addTearDown(updateProvider.dispose);

            await tester.pumpWidget(
              MultiProvider(
                providers: [
                  ChangeNotifierProvider<ThemeProvider>.value(
                    value: themeProvider,
                  ),
                  ChangeNotifierProvider<HistoryProvider>.value(
                    value: historyProvider,
                  ),
                  ChangeNotifierProvider<UpdateProvider>.value(
                    value: updateProvider,
                  ),
                ],
                child: MaterialApp(
                  theme: AppTheme.lightTheme,
                  darkTheme: AppTheme.darkTheme,
                  themeMode: brightness == Brightness.dark
                      ? ThemeMode.dark
                      : ThemeMode.light,
                  home: const MainScreen(),
                ),
              ),
            );
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 50)),
            );
            await tester.pumpAndSettle();

            expect(find.text('Files Utility'), findsOneWidget);
            expect(find.text('Transfer Files'), findsOneWidget);
            expect(find.text('Copy Files'), findsOneWidget);
            expect(find.text('Delete Files'), findsOneWidget);
            expect(find.text('Count Files'), findsOneWidget);
            expect(find.text('FTP Upload'), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );

        testWidgets(
          'TransferFilesScreen active filter pills render with theme-aware colors in ${brightness.name} mode at ${size.width.toInt()}x${size.height.toInt()}',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            late ThemeProvider themeProvider;
            late HistoryProvider historyProvider;
            late TransferFilesProvider transferProvider;

            await tester.runAsync(() async {
              themeProvider = ThemeProvider();
              historyProvider = HistoryProvider();
              transferProvider = TransferFilesProvider();
              await Future<void>.delayed(const Duration(milliseconds: 80));
              transferProvider.setEnableDateRange(true);
              transferProvider.setExcludeSubfolders(true);
              await Future<void>.delayed(const Duration(milliseconds: 50));
            });

            addTearDown(themeProvider.dispose);
            addTearDown(historyProvider.dispose);
            addTearDown(transferProvider.dispose);

            await tester.pumpWidget(
              MultiProvider(
                providers: [
                  ChangeNotifierProvider<ThemeProvider>.value(
                    value: themeProvider,
                  ),
                  ChangeNotifierProvider<HistoryProvider>.value(
                    value: historyProvider,
                  ),
                  ChangeNotifierProvider<TransferFilesProvider>.value(
                    value: transferProvider,
                  ),
                ],
                child: MaterialApp(
                  theme: AppTheme.lightTheme,
                  darkTheme: AppTheme.darkTheme,
                  themeMode: brightness == Brightness.dark
                      ? ThemeMode.dark
                      : ThemeMode.light,
                  home: const TransferFilesScreen(),
                ),
              ),
            );
            await tester.pumpAndSettle();

            final expectedPrimary = brightness == Brightness.dark
                ? const Color(0xFF3B82F6)
                : const Color(0xFF2563EB);

            final dateChipFinder = find.textContaining('Date: ');
            expect(dateChipFinder, findsOneWidget);
            expect(find.text('Source folder only'), findsOneWidget);
            final dateText = tester.widget<Text>(dateChipFinder);
            expect(dateText.style?.color, expectedPrimary);

            // Note: enableDateRange and enableAgeFilter are mutually exclusive in TransferFilesProvider.
            await tester.runAsync(() async {
              transferProvider.setEnableAgeFilter(true);
              await Future<void>.delayed(const Duration(milliseconds: 50));
            });
            await tester.pumpAndSettle();

            final ageChipFinder = find.textContaining('Age: > ');
            expect(ageChipFinder, findsOneWidget);
            final ageText = tester.widget<Text>(ageChipFinder);
            expect(ageText.style?.color, expectedPrimary);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });
}
