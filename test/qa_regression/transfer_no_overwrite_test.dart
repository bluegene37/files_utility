// Regression: ISSUE-002 — Transfer moved a file straight onto an existing
// destination file, destroying the destination and then deleting the source.
// Found by /qa on 2026-08-30
// Report: .gstack/qa-reports/qa-report-files-utility-2026-08-30.md
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
        .createTempSync('files_utility_qa_transfer_')
        .path;
    await LocalDbService().init('qa_transfer');
  });

  test('Transfer never destroys an existing destination file', () async {
    final tmp = Directory.systemTemp.createTempSync('qa_transfer_overwrite_');
    addTearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    final source = Directory('${tmp.path}/source')..createSync();
    final dest = Directory('${tmp.path}/dest')..createSync();

    // Same name in both places, different contents. The destination copy is
    // the one that must not be silently destroyed.
    File('${source.path}/report.txt').writeAsStringSync('INCOMING');
    final destFile = File('${dest.path}/report.txt')
      ..writeAsStringSync('ORIGINAL-DESTINATION-CONTENT');

    final provider = TransferFilesProvider();
    await provider.clearProgress();
    provider.setSourcePath(source.path);
    provider.setDestPath(dest.path);
    provider.setOnCompletionAction('stop');
    await Future<void>.delayed(const Duration(milliseconds: 150));

    await provider.startProcessing();
    await _waitUntil(() => !provider.isProcessing);

    expect(
      provider.isProcessing,
      isFalse,
      reason: 'transfer run did not finish within the timeout',
    );

    expect(
      destFile.readAsStringSync(),
      'ORIGINAL-DESTINATION-CONTENT',
      reason: 'Transfer overwrote an existing destination file',
    );
    expect(
      File('${source.path}/report.txt').existsSync(),
      isTrue,
      reason:
          'source file was deleted even though the destination was never '
          'safely written',
    );
  });

  test('Transfer still moves a file when nothing clashes', () async {
    final tmp = Directory.systemTemp.createTempSync('qa_transfer_happy_');
    addTearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    final source = Directory('${tmp.path}/source')..createSync();
    final dest = Directory('${tmp.path}/dest')..createSync();
    File('${source.path}/fresh.txt').writeAsStringSync('MOVE-ME');

    final provider = TransferFilesProvider();
    await provider.clearProgress();
    provider.setSourcePath(source.path);
    provider.setDestPath(dest.path);
    provider.setOnCompletionAction('stop');
    await Future<void>.delayed(const Duration(milliseconds: 150));

    await provider.startProcessing();
    await _waitUntil(() => !provider.isProcessing);

    expect(
      File('${dest.path}/fresh.txt').existsSync(),
      isTrue,
      reason: 'a non-clashing file should still be moved to the destination',
    );
    expect(File('${dest.path}/fresh.txt').readAsStringSync(), 'MOVE-ME');
    expect(
      File('${source.path}/fresh.txt').existsSync(),
      isFalse,
      reason: 'a moved file should no longer be in the source',
    );
  });
}
