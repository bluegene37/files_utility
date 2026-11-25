// Gene - Nov, 25, 2026: End-to-end regression tests verifying native Rust engines for
// CopyFilesProvider, CountFilesProvider, DeleteFilesProvider, and FTP scanning/creation dates.
import 'dart:io';

import 'package:files_utility/providers/copy_files_provider.dart';
import 'package:files_utility/providers/count_files_provider.dart';
import 'package:files_utility/providers/delete_files_provider.dart';
import 'package:files_utility/providers/transfer_files_provider.dart';
import 'package:files_utility/services/app_sqlite_service.dart';
import 'package:files_utility/services/file_creation_date.dart';
import 'package:files_utility/services/local_db_service.dart';
import 'package:files_utility/services/rust_file_engines.dart';
import 'package:files_utility/services/window_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
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
        .createTempSync('files_utility_qa_rust_engines_')
        .path;
    await LocalDbService().init('qa_rust_engines');
  });

  test(
    'CopyFilesProvider via Rust engine copies matching files, skips existing/filtered, and supports multi-pair run orders',
    () async {
      final tmp = Directory.systemTemp.createTempSync('qa_rust_copy_');
      addTearDown(() {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      final src1 = Directory('${tmp.path}/src1')..createSync();
      final sub1 = Directory('${src1.path}/nested')..createSync();
      final dst1 = Directory('${tmp.path}/dst1')..createSync();
      final dst1Sub = Directory('${dst1.path}/nested')..createSync();

      final src2 = Directory('${tmp.path}/src2')..createSync();
      final dst2 = Directory('${tmp.path}/dst2')..createSync();

      final targetDate = DateTime(2026, 5, 15, 12, 0);
      final oldDate = DateTime(2025, 1, 10, 12, 0);

      final fMatch = File('${sub1.path}/copy_me.txt')..writeAsStringSync('NEW');
      final fExist = File('${sub1.path}/already.txt')
        ..writeAsStringSync('SAME');
      final fOld = File('${sub1.path}/skip_old.txt')..writeAsStringSync('OLD');
      final fDstExist = File('${dst1Sub.path}/already.txt')
        ..writeAsStringSync('SAME');
      final fOrder2 = File('${src2.path}/second.txt')
        ..writeAsStringSync('ORDER2');

      await fMatch.setLastModified(targetDate);
      await fExist.setLastModified(targetDate);
      await fOld.setLastModified(oldDate);
      await fDstExist.setLastModified(targetDate);
      await fOrder2.setLastModified(targetDate);

      final provider = CopyFilesProvider(persistSettings: false);
      addTearDown(() => provider.dispose());
      await provider.clearProgress();

      provider.setUseMultipleDirectories(true);
      provider.setPairSource(0, src1.path);
      provider.setPairDest(0, dst1.path);
      provider.setPairRunOrder(0, 1);
      provider.addDirectoryPair();
      provider.setPairSource(1, src2.path);
      provider.setPairDest(1, dst2.path);
      provider.setPairRunOrder(1, 2);

      provider.setEnableDateRange(true);
      provider.setFromDate(DateTime(2026, 5, 1));
      provider.setToDate(DateTime(2026, 5, 31));
      provider.setOnCompletionAction('stop');

      await provider.startProcessing();
      await _waitUntil(() => !provider.isProcessing);

      expect(provider.isProcessing, isFalse);
      expect(provider.filesScanned, equals(4));
      expect(provider.filesCopied, equals(2));
      expect(provider.filesAlreadyExist, equals(1));
      expect(provider.filesSkipped, equals(1));
      expect(
        File('${dst1Sub.path}/copy_me.txt').readAsStringSync(),
        equals('NEW'),
      );
      expect(File('${dst1Sub.path}/skip_old.txt').existsSync(), isFalse);
      expect(
        File('${dst2.path}/second.txt').readAsStringSync(),
        equals('ORDER2'),
      );
    },
  );

  test(
    'CountFilesProvider via Rust engine counts files/folders, respects symlink boundary, and updates scanning status',
    () async {
      final tmp = Directory.systemTemp.createTempSync('qa_rust_count_');
      addTearDown(() {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      final target = Directory('${tmp.path}/target')..createSync();
      final sub = Directory('${target.path}/sub')..createSync();
      final outside = Directory('${tmp.path}/outside')..createSync();

      File('${target.path}/a.txt').writeAsStringSync('A');
      File('${sub.path}/b.txt').writeAsStringSync('B');
      File('${sub.path}/c.txt').writeAsStringSync('C');
      File('${outside.path}/secret.txt').writeAsStringSync('SECRET');
      Link('${target.path}/escape').createSync(outside.path);

      final provider = CountFilesProvider();
      addTearDown(() => provider.dispose());
      provider.setTargetPath(target.path);

      final statuses = <String>[];
      provider.addListener(() {
        statuses.add(provider.currentStatus);
      });

      await provider.startCounting();
      await _waitUntil(() => !provider.isCounting);

      expect(provider.isCounting, isFalse);
      expect(provider.totalFiles, equals(3));
      expect(provider.totalFolders, equals(1));
      expect(provider.errors, equals(0));
      expect(
        statuses.any((s) => s.contains('Scanning (') && s.contains('files)')),
        isTrue,
      );
    },
  );

  test(
    'DeleteFilesProvider via Rust engine deletes matching year/month files, removes empty folders, and updates scanning status',
    () async {
      final tmp = Directory.systemTemp.createTempSync('qa_rust_delete_');
      addTearDown(() {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      final target = Directory('${tmp.path}/target')..createSync();
      final emptyAfter = Directory('${target.path}/empty_after')..createSync();
      final keepDir = Directory('${target.path}/keep_dir')..createSync();

      final matchFile = File('${emptyAfter.path}/old.txt')
        ..writeAsStringSync('OLD');
      final keepFile = File('${keepDir.path}/new.txt')
        ..writeAsStringSync('NEW');

      await matchFile.setLastModified(DateTime(2020, 1, 15));
      await keepFile.setLastModified(DateTime(2026, 6, 15));

      final provider = DeleteFilesProvider();
      addTearDown(() => provider.dispose());
      provider.setTargetPath(target.path);
      provider.selectedYear = 2020;
      provider.validMonths = ['Jan'];

      final statuses = <String>[];
      provider.addListener(() {
        statuses.add(provider.currentStatus);
      });

      await provider.deleteFiles();
      await _waitUntil(() => !provider.isProcessing);

      expect(provider.isProcessing, isFalse);
      expect(provider.filesScanned, equals(2));
      expect(provider.deletedCount, equals(1));
      expect(emptyAfter.existsSync(), isFalse);
      expect(keepFile.existsSync(), isTrue);
      expect(
        statuses.any((s) => s.contains('Scanning (') && s.contains('files)')),
        isTrue,
      );
    },
  );

  test(
    'RustFtpScanner and native getCreationDatesForFiles return sorted in-root metadata',
    () async {
      final tmp = Directory.systemTemp.createTempSync('qa_rust_ftp_scan_');
      addTearDown(() {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      final root = Directory(p.join(tmp.path, 'root'))..createSync();
      final sub = Directory(p.join(root.path, 'sub'))..createSync();
      final outside = Directory(p.join(tmp.path, 'outside'))..createSync();

      final f1 = File(p.join(sub.path, 'b.txt'))..writeAsStringSync('BB');
      final f2 = File(p.join(sub.path, 'a.txt'))..writeAsStringSync('AAA');
      final secret = File(p.join(outside.path, 'secret.txt'))
        ..writeAsStringSync('NOPE');
      Link(p.join(sub.path, 'escape.txt')).createSync(secret.path);

      final scanRes = await RustFtpScanner.scanDirectoryAsync(
        dirPath: sub.path,
        rootPath: root.path,
        includeCreationTime: true,
      );

      expect(scanRes.errors, isEmpty);
      expect(scanRes.files.length, equals(2));
      expect(p.normalize(scanRes.files[0].path), equals(p.normalize(f2.path)));
      expect(scanRes.files[0].size, equals(3));
      expect(p.normalize(scanRes.files[1].path), equals(p.normalize(f1.path)));
      expect(scanRes.files[1].size, equals(2));

      final statsByPath = {f1.path: f1.statSync(), f2.path: f2.statSync()};
      final creationDates = await getCreationDatesForFiles([
        f1,
        f2,
      ], statsByPath);
      expect(creationDates.containsKey(f1.path), isTrue);
      expect(creationDates.containsKey(f2.path), isTrue);
    },
  );

  test(
    'Parallel Rust engines process 100+ nested files cleanly across Transfer, Copy, Count, and Delete',
    () async {
      final tmp = Directory.systemTemp.createTempSync('qa_rust_parallel_');
      addTearDown(() {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      final src = Directory('${tmp.path}/src')..createSync();
      final copyDst = Directory('${tmp.path}/copy_dst')..createSync();
      final moveDst = Directory('${tmp.path}/move_dst')..createSync();

      final oldDate = DateTime(2020, 1, 15, 12, 0);
      for (int d = 0; d < 5; d++) {
        final sub = Directory('${src.path}/dir_$d')..createSync();
        for (int f = 0; f < 24; f++) {
          final file = File('${sub.path}/file_$f.txt')
            ..writeAsStringSync('DATA_${d}_$f');
          await file.setLastModified(oldDate);
        }
      }

      // 1. Count 120 files across 5 directories
      final countProvider = CountFilesProvider();
      addTearDown(() => countProvider.dispose());
      countProvider.setTargetPath(src.path);
      await countProvider.startCounting();
      await _waitUntil(() => !countProvider.isCounting);
      expect(countProvider.totalFiles, equals(120));
      expect(countProvider.totalFolders, equals(5));

      // 2. Copy 120 files
      final copyProvider = CopyFilesProvider(persistSettings: false);
      addTearDown(() => copyProvider.dispose());
      copyProvider.setSourcePath(src.path);
      copyProvider.setDestPath(copyDst.path);
      copyProvider.setOnCompletionAction('stop');
      await copyProvider.startProcessing();
      await _waitUntil(() => !copyProvider.isProcessing);
      expect(copyProvider.filesCopied, equals(120));
      expect(copyProvider.errors, equals(0));

      // 3. Transfer 120 files from src -> moveDst
      final txProvider = TransferFilesProvider();
      addTearDown(() => txProvider.dispose());
      await txProvider.clearProgress();
      txProvider.setSourcePath(src.path);
      txProvider.setDestPath(moveDst.path);
      txProvider.setEnableDateRange(false);
      txProvider.setEnableAgeFilter(false);
      txProvider.setOnCompletionAction('stop');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await txProvider.startProcessing();
      await _waitUntil(() => !txProvider.isProcessing);
      expect(txProvider.filesMoved, equals(120));
      expect(txProvider.errors, equals(0));
      expect(File('${src.path}/dir_4/file_23.txt').existsSync(), isFalse);
      expect(File('${moveDst.path}/dir_4/file_23.txt').existsSync(), isTrue);

      // 4. Delete all 120 files + empty folders in moveDst
      final delProvider = DeleteFilesProvider();
      addTearDown(() => delProvider.dispose());
      delProvider.setTargetPath(moveDst.path);
      delProvider.selectedYear = 2020;
      delProvider.validMonths = ['Jan'];
      await delProvider.deleteFiles();
      await _waitUntil(() => !delProvider.isProcessing);
      expect(delProvider.deletedCount, equals(120));
      expect(Directory('${moveDst.path}/dir_4').existsSync(), isFalse);
    },
  );

  test('WindowService.buildTitle omits live status/scanning counter', () {
    final title = WindowService.buildTitle('Transfer Files', 'Default');
    expect(title, equals('Files Utility — Transfer Files [Default]'));
    expect(title.contains('Scanning'), isFalse);
  });
}
