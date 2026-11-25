// Gene - Nov, 25, 2026: Regression tests for live scanning file counter in Transfer & Copy
// and Rust transfer_engine integration (filtering, pause/resume/stop, symlink containment).
import 'dart:io';

import 'package:files_utility/providers/copy_files_provider.dart';
import 'package:files_utility/providers/transfer_files_provider.dart';
import 'package:files_utility/services/app_sqlite_service.dart';
import 'package:files_utility/services/local_db_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
        .createTempSync('files_utility_qa_scan_counter_')
        .path;
    await LocalDbService().init('qa_scan_counter');
  });

  test(
    'TransferFilesProvider updates filesScanned and emits live scanning counter in status',
    () async {
      final tmp = Directory.systemTemp.createTempSync('qa_tx_scan_counter_');
      addTearDown(() {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      final source = Directory('${tmp.path}/source')..createSync();
      final sub = Directory('${source.path}/alpha_folder')..createSync();
      final dest = Directory('${tmp.path}/dest')..createSync();

      // Create files outside date range so scanning traverses them and reports count.
      for (int i = 0; i < 6; i++) {
        final f = File('${sub.path}/doc_$i.txt')..writeAsStringSync('DATA_$i');
        await f.setLastModified(DateTime(2025, 1, 10));
      }
      final match = File('${sub.path}/match.txt')..writeAsStringSync('MATCH');
      await match.setLastModified(DateTime(2026, 5, 15));

      final provider = TransferFilesProvider();
      addTearDown(() => provider.dispose());
      await provider.clearProgress();
      provider.setSourcePath(source.path);
      provider.setDestPath(dest.path);
      provider.setEnableDateRange(true);
      provider.setFromDate(DateTime(2026, 5, 1));
      provider.setToDate(DateTime(2026, 5, 31));
      provider.setOnCompletionAction('stop');

      final observedStatuses = <String>[];
      provider.addListener(() {
        observedStatuses.add(provider.currentStatus);
      });

      await Future<void>.delayed(const Duration(milliseconds: 100));
      await provider.startProcessing();
      await _waitUntil(() => !provider.isProcessing);

      expect(provider.isProcessing, isFalse);
      expect(provider.filesScanned, equals(7));
      expect(provider.filesMoved, equals(1));
      expect(File('${dest.path}/alpha_folder/match.txt').existsSync(), isTrue);
      expect(File('${sub.path}/doc_0.txt').existsSync(), isTrue);

      expect(
        observedStatuses.any(
          (s) => s.contains('Scanning (') && s.contains('files)'),
        ),
        isTrue,
        reason:
            'Expected a live scanning status with file count, got: $observedStatuses',
      );
    },
  );

  test(
    'TransferFilesProvider stops cleanly and skips symlinks escaping source root',
    () async {
      final tmp = Directory.systemTemp.createTempSync('qa_tx_symlink_stop_');
      addTearDown(() {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      final source = Directory('${tmp.path}/source')..createSync();
      final outside = Directory('${tmp.path}/outside')..createSync();
      final dest = Directory('${tmp.path}/dest')..createSync();

      final secret = File('${outside.path}/secret.txt')
        ..writeAsStringSync('KEEP_ME');
      final link = Link('${source.path}/escape.txt')..createSync(secret.path);
      expect(link.existsSync(), isTrue);

      final provider = TransferFilesProvider();
      addTearDown(() => provider.dispose());
      await provider.clearProgress();
      provider.setSourcePath(source.path);
      provider.setDestPath(dest.path);
      provider.setEnableDateRange(false);
      provider.setEnableAgeFilter(false);
      provider.setOnCompletionAction('stop');

      await Future<void>.delayed(const Duration(milliseconds: 100));
      await provider.startProcessing();
      await _waitUntil(() => !provider.isProcessing);

      expect(secret.existsSync(), isTrue);
      expect(File('${dest.path}/escape.txt').existsSync(), isFalse);
      expect(provider.filesMoved, equals(0));
      expect(
        provider.logs.any(
          (l) => l.contains('Skipped link pointing outside the source'),
        ),
        isTrue,
      );
    },
  );

  test(
    'CopyFilesProvider updates filesScanned and emits live scanning counter in status',
    () async {
      final tmp = Directory.systemTemp.createTempSync('qa_copy_scan_counter_');
      addTearDown(() {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      final source = Directory('${tmp.path}/source')..createSync();
      final sub = Directory('${source.path}/beta_folder')..createSync();
      final dest = Directory('${tmp.path}/dest')..createSync();

      for (int i = 0; i < 5; i++) {
        final f = File('${sub.path}/skip_$i.txt')..writeAsStringSync('SKIP_$i');
        await f.setLastModified(DateTime(2025, 1, 10));
      }
      final match = File('${sub.path}/keep.txt')..writeAsStringSync('KEEP');
      await match.setLastModified(DateTime(2026, 5, 15));

      final provider = CopyFilesProvider(persistSettings: false);
      addTearDown(() => provider.dispose());
      provider.setSourcePath(source.path);
      provider.setDestPath(dest.path);
      provider.setEnableDateRange(true);
      provider.setFromDate(DateTime(2026, 5, 1));
      provider.setToDate(DateTime(2026, 5, 31));
      provider.setOnCompletionAction('stop');

      final observedStatuses = <String>[];
      provider.addListener(() {
        observedStatuses.add(provider.currentStatus);
      });

      await provider.startProcessing();
      await _waitUntil(() => !provider.isProcessing);

      expect(provider.isProcessing, isFalse);
      expect(provider.filesScanned, equals(6));
      expect(provider.filesCopied, equals(1));
      expect(provider.filesSkipped, equals(5));
      expect(File('${dest.path}/beta_folder/keep.txt').existsSync(), isTrue);

      expect(
        observedStatuses.any(
          (s) => s.contains('Scanning (') && s.contains('files)'),
        ),
        isTrue,
        reason:
            'Expected Copy status to include live scanning counter, got: $observedStatuses',
      );
    },
  );
}
