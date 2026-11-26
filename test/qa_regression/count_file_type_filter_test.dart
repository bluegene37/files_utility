// Gene - Nov, 26, 2026: Regression and widget tests for Count Files file-type category checkboxes, persistence, and Rust filtering.
import 'dart:io';

import 'package:files_utility/providers/count_files_provider.dart';
import 'package:files_utility/providers/theme_provider.dart';
import 'package:files_utility/screens/count_files_screen.dart';
import 'package:files_utility/services/app_sqlite_service.dart';
import 'package:files_utility/services/global_db_service.dart';
import 'package:files_utility/services/local_db_service.dart';
import 'package:files_utility/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 25),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppSqliteService().appDirPath = Directory.systemTemp
        .createTempSync('files_utility_qa_count_filter_')
        .path;
    await GlobalDbService().init();
    await LocalDbService().init('default');
  });

  setUp(() async {
    await LocalDbService().remove('count_selectedCategories');
    await LocalDbService().remove('count_targetPath');
  });

  group('CountFilesProvider file-type filter state & persistence', () {
    test(
      'defaults to all categories, toggles individual/All, and persists selection',
      () async {
        final provider = CountFilesProvider();
        addTearDown(() => provider.dispose());
        await provider.reloadSettings();

        expect(provider.allCategoriesSelected, isTrue);
        expect(provider.hasAnyCategorySelected, isTrue);
        expect(provider.filterSummary, equals('All Files'));
        expect(provider.excludedSummary, isEmpty);

        provider.toggleCategory(CountFileCategory.videos);
        expect(provider.allCategoriesSelected, isFalse);
        expect(
          provider.isCategorySelected(CountFileCategory.videos),
          isFalse,
        );
        expect(provider.excludedSummary, equals('Videos'));

        // Tapping All when partially selected selects everything again.
        provider.toggleAllCategories();
        expect(provider.allCategoriesSelected, isTrue);

        // Tapping All when all selected clears everything.
        provider.toggleAllCategories();
        expect(provider.hasAnyCategorySelected, isFalse);
        expect(provider.filterSummary, equals('None'));
        expect(provider.canStartCounting, isFalse);

        provider.toggleCategory(CountFileCategory.images);
        provider.toggleCategory(CountFileCategory.documents);
        expect(provider.filterSummary, equals('Images, Documents'));
        expect(
          provider.excludedSummary,
          equals('Videos, Audio, Archives, Others'),
        );

        await _waitUntil(
          () =>
              LocalDbService()
                  .getStringList('count_selectedCategories')
                  ?.length ==
              2,
        );

        final reloaded = CountFilesProvider();
        addTearDown(() => reloaded.dispose());
        await reloaded.reloadSettings();
        expect(
          reloaded.selectedCategories,
          equals({CountFileCategory.images, CountFileCategory.documents}),
        );
      },
    );

    test('guards startCounting when zero categories are selected', () async {
      final provider = CountFilesProvider();
      addTearDown(() => provider.dispose());
      provider.setTargetPath(Directory.systemTemp.path);
      provider.setAllCategories(false);

      expect(provider.canStartCounting, isFalse);
      await provider.startCounting();

      expect(provider.isCounting, isFalse);
      expect(
        provider.logs.any(
          (l) => l.contains('Select at least one file type to count'),
        ),
        isTrue,
      );
    });

    // Gene - Nov, 26, 2026: Verify byte-size formatting across B, KB, MB, GB, and TB units.
    test('formatByteSize formats B, KB, MB, GB, and TB accurately', () {
      expect(CountFilesProvider.formatByteSize(0), equals('0 B'));
      expect(CountFilesProvider.formatByteSize(512), equals('512 B'));
      expect(CountFilesProvider.formatByteSize(1536), equals('1.5 KB'));
      expect(
        CountFilesProvider.formatByteSize(2 * 1024 * 1024),
        equals('2.00 MB'),
      );
      expect(
        CountFilesProvider.formatByteSize(3 * 1024 * 1024 * 1024),
        equals('3.00 GB'),
      );
      expect(
        CountFilesProvider.formatByteSize(2 * 1024 * 1024 * 1024 * 1024),
        equals('2.00 TB'),
      );
    });
  });

  group('CountFilesProvider end-to-end Rust category filtering', () {
    test('counts included files and tracks excluded files accurately', () async {
      final tmp = Directory.systemTemp.createTempSync('qa_count_types_');
      addTearDown(() {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      final sub = Directory(p.join(tmp.path, 'sub'))..createSync();
      File(p.join(tmp.path, 'photo.jpg')).writeAsStringSync('1');
      File(p.join(sub.path, 'diagram.PNG')).writeAsStringSync('2');
      File(p.join(tmp.path, 'report.pdf')).writeAsStringSync('3');
      File(p.join(sub.path, 'notes.docx')).writeAsStringSync('4');
      File(p.join(tmp.path, 'clip.mp4')).writeAsStringSync('5');
      File(p.join(sub.path, 'track.mp3')).writeAsStringSync('6');
      File(p.join(tmp.path, 'bundle.zip')).writeAsStringSync('7');
      File(p.join(sub.path, 'firmware.bin')).writeAsStringSync('8');
      File(p.join(tmp.path, 'README')).writeAsStringSync('9');

      final provider = CountFilesProvider();
      addTearDown(() => provider.dispose());
      provider.setTargetPath(tmp.path);

      Future<void> runAndVerify({
        required Set<CountFileCategory> categories,
        required int expectedFiles,
        required int expectedExcluded,
      }) async {
        provider.setAllCategories(false);
        for (final c in categories) {
          provider.toggleCategory(c, true);
        }
        await provider.startCounting();
        await _waitUntil(() => !provider.isCounting);
        expect(provider.totalFiles, equals(expectedFiles));
        expect(provider.excludedFiles, equals(expectedExcluded));
        expect(provider.totalFolders, equals(1));
        expect(provider.errors, equals(0));
      }

      await runAndVerify(
        categories: CountFileCategory.values.toSet(),
        expectedFiles: 9,
        expectedExcluded: 0,
      );
      await runAndVerify(
        categories: {CountFileCategory.images},
        expectedFiles: 2,
        expectedExcluded: 7,
      );
      await runAndVerify(
        categories: {CountFileCategory.documents},
        expectedFiles: 2,
        expectedExcluded: 7,
      );
      await runAndVerify(
        categories: {CountFileCategory.images, CountFileCategory.documents},
        expectedFiles: 4,
        expectedExcluded: 5,
      );
      await runAndVerify(
        categories: {CountFileCategory.others},
        expectedFiles: 2,
        expectedExcluded: 7,
      );
    });

    // Gene - Nov, 26, 2026: Verify Count Files totals size (all & filtered) and Get Folder Size ignores filters and skips per-file logs.
    test(
      'calculates exact totalBytes for Count Files and full-folder size in Get Folder Size mode',
      () async {
        final tmp = Directory.systemTemp.createTempSync('qa_count_size_');
        addTearDown(() {
          try {
            tmp.deleteSync(recursive: true);
          } catch (_) {}
        });

        final sub = Directory(p.join(tmp.path, 'sub'))..createSync();
        File(p.join(tmp.path, 'photo.jpg')).writeAsBytesSync(List.filled(20, 1));
        File(p.join(sub.path, 'banner.png')).writeAsBytesSync(List.filled(30, 2));
        File(p.join(tmp.path, 'report.pdf')).writeAsBytesSync(List.filled(150, 3));
        File(p.join(sub.path, 'clip.mp4')).writeAsBytesSync(List.filled(800, 4));

        final provider = CountFilesProvider();
        addTearDown(() => provider.dispose());
        provider.setTargetPath(tmp.path);
        provider.setLogInterval(1);

        // 1. All categories selected -> totalBytes == 1000
        provider.setAllCategories(true);
        await provider.startCounting();
        await _waitUntil(() => !provider.isCounting);
        expect(provider.totalFiles, equals(4));
        expect(provider.totalFolders, equals(1));
        expect(provider.totalBytes, equals(1000));
        expect(provider.formattedTotalSize, equals('1000 B'));
        expect(provider.logs.any((l) => l.contains('Total Size:')), isTrue);

        // 2. Filtered to Images only -> totalBytes == 50
        provider.setAllCategories(false);
        provider.toggleCategory(CountFileCategory.images, true);
        await provider.startCounting();
        await _waitUntil(() => !provider.isCounting);
        expect(provider.totalFiles, equals(2));
        expect(provider.excludedFiles, equals(2));
        expect(provider.totalBytes, equals(50));

        // 3. Get Folder Size with zero categories checked -> sums entire folder & emits zero per-file logs
        provider.clearLogs();
        provider.setAllCategories(false);
        expect(provider.canStartCounting, isFalse);
        expect(provider.canGetFolderSize, isTrue);
        await provider.startFolderSize();
        await _waitUntil(() => !provider.isCounting);
        expect(provider.isSizeOnlyRun, isTrue);
        expect(provider.totalFiles, equals(4));
        expect(provider.excludedFiles, equals(0));
        expect(provider.totalFolders, equals(1));
        expect(provider.totalBytes, equals(1000));
        expect(provider.logs.any((l) => l.contains('Folder Size:')), isTrue);
        expect(provider.logs.any((l) => l.contains('✓ Counted')), isFalse);
      },
    );
  });

  group('CountFilesScreen widget tests', () {
    testWidgets(
      'renders filter checkboxes, toggles All/Images/Documents, and shows Excluded badge',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final countProvider = CountFilesProvider();
        final themeProvider = ThemeProvider(persistSettings: false);
        addTearDown(() => countProvider.dispose());
        addTearDown(() => themeProvider.dispose());
        await tester.runAsync(() async {
          await countProvider.reloadSettings();
          countProvider.setTargetPath('/tmp/sample_folder');
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
              ChangeNotifierProvider<CountFilesProvider>.value(
                value: countProvider,
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: const CountFilesScreen(),
            ),
          ),
        );
        await tester.pump();

        expect(find.byKey(const Key('count_filter_all')), findsOneWidget);
        for (final cat in CountFileCategory.values) {
          expect(
            find.byKey(Key('count_filter_${cat.id}')),
            findsOneWidget,
          );
        }
        expect(
          find.text('Counting all file types (nothing excluded)'),
          findsOneWidget,
        );
        expect(find.textContaining('Excluded:'), findsNothing);

        // Uncheck All -> disables Count Files, keeps Get Folder Size enabled, and displays warning prompt.
        await tester.tap(find.byKey(const Key('count_filter_all')));
        await tester.pump();
        expect(countProvider.hasAnyCategorySelected, isFalse);
        expect(
          find.text('Select at least one file type to count'),
          findsOneWidget,
        );
        final countBtnDisabled = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Count Files'),
        );
        expect(countBtnDisabled.onPressed, isNull);
        final sizeBtn = tester.widget<OutlinedButton>(
          find.byKey(const Key('count_get_folder_size_btn')),
        );
        expect(sizeBtn.onPressed, isNotNull);
        expect(find.byKey(const Key('count_size_badge')), findsOneWidget);
        expect(find.text('Size: 0 B'), findsOneWidget);

        // Select Images and Documents only -> enables Count Files and shows Excluded badge.
        await tester.tap(find.byKey(const Key('count_filter_images')));
        await tester.tap(find.byKey(const Key('count_filter_documents')));
        await tester.pump();

        final countBtnEnabled = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Count Files'),
        );
        expect(countBtnEnabled.onPressed, isNotNull);
        expect(find.text('Excluded: 0'), findsOneWidget);
        expect(
          find.textContaining('Counting: Images, Documents', findRichText: true),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            'Excluding: Videos, Audio, Archives, Others',
            findRichText: true,
          ),
          findsOneWidget,
        );

        // Verify responsive Wrap layout does not overflow at minimum 980x680 window size.
        tester.view.physicalSize = const Size(980, 680);
        await tester.pump();
        expect(tester.takeException(), isNull);

        // Drain any sqflite lock timers created inside FakeAsync by tap handlers.
        await tester.pump(const Duration(seconds: 11));
      },
    );
  });
}
