import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:files_utility/providers/transfer_files_provider.dart';
import 'package:files_utility/services/app_sqlite_service.dart';
import 'package:files_utility/services/local_db_service.dart';

Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 25),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppSqliteService().appDirPath = Directory.systemTemp
        .createTempSync('files_utility_qa_transfer_date_')
        .path;
    await LocalDbService().init('qa_transfer_date');
  });

  test('Transfer with Date Range preserves exact relative path and does not inject year folder', () async {
    final tmp = Directory.systemTemp.createTempSync('qa_transfer_date_path_');
    addTearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    final source = Directory('${tmp.path}/source')..createSync();
    final subfolder = Directory('${source.path}/subfolder')..createSync();
    final dest = Directory('${tmp.path}/dest')..createSync();

    final file1 = File('${source.path}/root_file.txt')..writeAsStringSync('ROOT');
    final file2 = File('${subfolder.path}/sub_file.txt')..writeAsStringSync('SUB');

    final targetDate = DateTime(2026, 5, 15, 12, 0, 0);
    await file1.setLastModified(targetDate);
    await file2.setLastModified(targetDate);

    final provider = TransferFilesProvider();
    addTearDown(() => provider.dispose());
    await provider.clearProgress();
    provider.setSourcePath(source.path);
    provider.setDestPath(dest.path);
    provider.setEnableDateRange(true);
    provider.setFromDate(DateTime(2026, 5, 1));
    provider.setToDate(DateTime(2026, 5, 31));
    provider.setOnCompletionAction('stop');
    await Future<void>.delayed(const Duration(milliseconds: 150));

    await provider.startProcessing();
    await _waitUntil(() => !provider.isProcessing);

    expect(provider.isProcessing, isFalse);

    // Verify files landed in dest directly (preserving relative subfolder structure)
    final movedFile1 = File('${dest.path}/root_file.txt');
    final movedFile2 = File('${dest.path}/subfolder/sub_file.txt');
    expect(movedFile1.existsSync(), isTrue, reason: 'root_file should be in dest root');
    expect(movedFile2.existsSync(), isTrue, reason: 'sub_file should be in dest/subfolder');

    // CRITICAL: Verify NO unexpected year folder (e.g. dest/2026) was created
    final yearFolder = Directory('${dest.path}/2026');
    expect(yearFolder.existsSync(), isFalse, reason: 'Year folder (2026) should NOT be injected into dest path');

    // Verify source files were deleted
    expect(file1.existsSync(), isFalse);
    expect(file2.existsSync(), isFalse);
  });

  test('Transfer with Date Range only moves files inside the date range', () async {
    final tmp = Directory.systemTemp.createTempSync('qa_transfer_date_filter_');
    addTearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    final source = Directory('${tmp.path}/source')..createSync();
    final dest = Directory('${tmp.path}/dest')..createSync();

    // 1 file before range, 1 file in range, 1 file after range
    final oldFile = File('${source.path}/old.txt')..writeAsStringSync('OLD');
    final matchingFile = File('${source.path}/match.txt')..writeAsStringSync('MATCH');
    final newFile = File('${source.path}/new.txt')..writeAsStringSync('NEW');

    await oldFile.setLastModified(DateTime(2026, 4, 10));
    await matchingFile.setLastModified(DateTime(2026, 5, 15));
    await newFile.setLastModified(DateTime(2026, 6, 20));

    final provider = TransferFilesProvider();
    addTearDown(() => provider.dispose());
    await provider.clearProgress();
    provider.setSourcePath(source.path);
    provider.setDestPath(dest.path);
    provider.setEnableDateRange(true);
    provider.setFromDate(DateTime(2026, 5, 1));
    provider.setToDate(DateTime(2026, 5, 31));
    provider.setOnCompletionAction('stop');
    await Future<void>.delayed(const Duration(milliseconds: 150));

    await provider.startProcessing();
    await _waitUntil(() => !provider.isProcessing);

    expect(provider.isProcessing, isFalse);

    // Matching file moved
    expect(File('${dest.path}/match.txt').existsSync(), isTrue);
    expect(matchingFile.existsSync(), isFalse);

    // Non-matching files remained in source
    expect(oldFile.existsSync(), isTrue);
    expect(newFile.existsSync(), isTrue);
    expect(File('${dest.path}/old.txt').existsSync(), isFalse);
    expect(File('${dest.path}/new.txt').existsSync(), isFalse);
  });

  test('Today and Yesterday presets configure dates properly and filter files', () async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final provider = TransferFilesProvider();
    addTearDown(() => provider.dispose());
    provider.setTodayOnly(true);
    expect(provider.enableDateRange, isTrue);
    expect(provider.todayOnly, isTrue);
    expect(provider.yesterdayOnly, isFalse);
    expect(provider.fromDate.year, today.year);
    expect(provider.fromDate.month, today.month);
    expect(provider.fromDate.day, today.day);
    expect(provider.toDate.year, today.year);
    expect(provider.toDate.month, today.month);
    expect(provider.toDate.day, today.day);

    // Setting both Today and Yesterday covers yesterday to today
    provider.setYesterdayOnly(true);
    expect(provider.yesterdayOnly, isTrue);
    expect(provider.todayOnly, isTrue);
    expect(provider.fromDate.year, yesterday.year);
    expect(provider.fromDate.month, yesterday.month);
    expect(provider.fromDate.day, yesterday.day);
    expect(provider.toDate.year, today.year);
    expect(provider.toDate.month, today.month);
    expect(provider.toDate.day, today.day);

    // Unchecking Today leaves only Yesterday
    provider.setTodayOnly(false);
    expect(provider.todayOnly, isFalse);
    expect(provider.yesterdayOnly, isTrue);
    expect(provider.fromDate.day, yesterday.day);
    expect(provider.toDate.day, yesterday.day);
  });
}
