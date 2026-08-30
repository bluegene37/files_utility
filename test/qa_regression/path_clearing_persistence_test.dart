// Regression: ISSUE-003 — clearing a path field only cleared it in memory, so
// the previous path silently came back on profile switch or app restart.
// Found by /qa on 2026-08-30
// Report: .gstack/qa-reports/qa-report-files-utility-2026-08-30.md
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:files_utility/providers/copy_files_provider.dart';
import 'package:files_utility/providers/count_files_provider.dart';
import 'package:files_utility/providers/delete_files_provider.dart';
import 'package:files_utility/providers/transfer_files_provider.dart';
import 'package:files_utility/services/app_sqlite_service.dart';
import 'package:files_utility/services/local_db_service.dart';

/// Lets the provider's fire-and-forget `_saveSettings()` reach the database.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 150));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppSqliteService().appDirPath = Directory.systemTemp
        .createTempSync('files_utility_qa_paths_')
        .path;
    await LocalDbService().init('qa_default');
  });

  test('Delete target survives being cleared', () async {
    final provider = DeleteFilesProvider();
    provider.setTargetPath('/tmp/qa_delete_target');
    await _settle();
    expect(provider.targetPath, '/tmp/qa_delete_target');

    provider.setTargetPath('');
    await _settle();
    expect(provider.targetPath, isNull);

    await provider.reloadSettings();
    expect(
      provider.targetPath,
      isNull,
      reason: 'cleared Delete target came back from the database',
    );
  });

  test('Count target stays cleared across a reload', () async {
    final provider = CountFilesProvider();
    provider.setTargetPath('/tmp/qa_count_target');
    await _settle();
    provider.setTargetPath('');
    await _settle();

    await provider.reloadSettings();
    expect(
      provider.targetPath,
      isNull,
      reason: 'cleared Count target came back from the database',
    );
  });

  test('Copy source and destination stay cleared across a reload', () async {
    final provider = CopyFilesProvider();
    provider.setSourcePath('/tmp/qa_copy_src');
    provider.setDestPath('/tmp/qa_copy_dst');
    await _settle();

    provider.setSourcePath('');
    provider.setDestPath('');
    await _settle();

    await provider.reloadSettings();
    expect(
      provider.sourcePath,
      isNull,
      reason: 'cleared Copy source came back from the database',
    );
    expect(
      provider.destPath,
      isNull,
      reason: 'cleared Copy destination came back from the database',
    );
  });

  test('Transfer source and destination stay cleared across a reload', () async {
    final provider = TransferFilesProvider();
    provider.setSourcePath('/tmp/qa_transfer_src');
    provider.setDestPath('/tmp/qa_transfer_dst');
    await _settle();

    provider.setSourcePath('');
    provider.setDestPath('');
    await _settle();

    await provider.reloadSettings();
    expect(
      provider.sourcePath,
      isNull,
      reason: 'cleared Transfer source came back from the database',
    );
    expect(
      provider.destPath,
      isNull,
      reason: 'cleared Transfer destination came back from the database',
    );
  });
}
