// Regression: ISSUE-001 — Delete followed symlinks out of the selected target
// folder and deleted matching files anywhere on the machine.
// Found by /qa on 2026-08-30
// Report: .gstack/qa-reports/qa-report-files-utility-2026-08-30.md
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:files_utility/providers/delete_files_provider.dart';
import 'package:files_utility/services/app_sqlite_service.dart';

/// Waits until [predicate] holds or the timeout expires.
Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppSqliteService().appDirPath = Directory.systemTemp
        .createTempSync('files_utility_qa_')
        .path;
  });

  test('Delete never escapes the target folder through a symlink', () async {
    final tmp = Directory.systemTemp.createTempSync('qa_delete_symlink_');
    addTearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    // The folder the user actually selected.
    final target = Directory('${tmp.path}/target')..createSync();
    // A completely separate folder that must never be touched.
    final outside = Directory('${tmp.path}/outside')..createSync();

    final oldDate = DateTime(2020, 1, 15);

    final insideFile = File('${target.path}/inside.txt')
      ..writeAsStringSync('inside');
    insideFile.setLastModifiedSync(oldDate);

    final outsideFile = File('${outside.path}/precious.txt')
      ..writeAsStringSync('precious');
    outsideFile.setLastModifiedSync(oldDate);

    // A symlink inside the target pointing at the unrelated folder.
    Link('${target.path}/escape_hatch').createSync(outside.path);

    final provider = DeleteFilesProvider();
    provider.setTargetPath(target.path);
    provider.selectedYear = 2020;
    provider.validMonths = ['Jan'];

    await provider.deleteFiles();
    await _waitUntil(() => !provider.isProcessing);

    expect(
      provider.isProcessing,
      isFalse,
      reason: 'delete run did not finish within the timeout',
    );

    // The in-scope file is a genuine match and should be gone.
    expect(
      insideFile.existsSync(),
      isFalse,
      reason: 'file inside the selected target should have been deleted',
    );

    // The out-of-scope file must survive: the user never selected that folder.
    expect(
      outsideFile.existsSync(),
      isTrue,
      reason:
          'Delete escaped the selected target through a symlink and deleted a '
          'file outside it',
    );
  });
}
