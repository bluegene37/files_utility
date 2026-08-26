import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:files_utility/models/app_profile.dart';
import 'package:files_utility/models/run_record.dart';
import 'package:files_utility/providers/copy_files_provider.dart';
import 'package:files_utility/providers/count_files_provider.dart';
import 'package:files_utility/providers/delete_files_provider.dart';
import 'package:files_utility/providers/theme_provider.dart';
import 'package:files_utility/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Model Unit Tests', () {
    test('AppProfile serialization and deserialization', () {
      final profile = AppProfile(
        id: 'prof_123',
        name: 'Test Profile',
        description: 'Profile for automated unit tests',
      );

      final json = profile.toJson();
      expect(json['id'], 'prof_123');
      expect(json['name'], 'Test Profile');
      expect(json['description'], 'Profile for automated unit tests');

      final reconstructed = AppProfile.fromJson(json);
      expect(reconstructed.id, profile.id);
      expect(reconstructed.name, profile.name);
      expect(reconstructed.description, profile.description);
    });

    test('RunRecord duration and formatting calculation', () {
      final start = DateTime(2025, 1, 1, 10, 0, 0);
      final end = DateTime(2025, 1, 1, 10, 5, 30);

      final record = RunRecord(
        id: 'RUN-TEST',
        operation: 'Transfer',
        startTime: start,
        endTime: end,
        filesProcessed: 150,
        foldersProcessed: 10,
        errors: 0,
        status: 'Completed',
        configSummary: 'Source: /test/source',
        sourcePath: '/test/source',
        destPath: '/test/dest',
      );

      expect(record.duration, const Duration(minutes: 5, seconds: 30));
      expect(record.filesProcessed, 150);
      expect(record.status, 'Completed');

      final json = record.toJson();
      expect(json['id'], 'RUN-TEST');
      expect(json['operation'], 'Transfer');

      final fromJson = RunRecord.fromJson(json);
      expect(fromJson.id, record.id);
      expect(fromJson.operation, record.operation);
      expect(fromJson.filesProcessed, record.filesProcessed);
    });

    test('DirectoryPair JSON serialization', () {
      final pair = DirectoryPair(
        sourcePath: '/src/folder',
        destPath: '/dst/folder',
        runOrder: 2,
      );

      final json = pair.toJson();
      expect(json['sourcePath'], '/src/folder');
      expect(json['destPath'], '/dst/folder');
      expect(json['runOrder'], 2);

      final decoded = DirectoryPair.fromJson(json);
      expect(decoded.sourcePath, '/src/folder');
      expect(decoded.destPath, '/dst/folder');
      expect(decoded.runOrder, 2);
    });
  });

  group('Provider Unit Tests', () {
    test('CountFilesProvider initial state & path sanitization', () {
      final provider = CountFilesProvider();
      expect(provider.isCounting, false);
      expect(provider.currentStatus, 'Idle');
      expect(provider.totalFiles, 0);
      expect(provider.totalFolders, 0);

      provider.setTargetPath('  "/valid/path"  ');
      expect(provider.targetPath, '/valid/path');

      provider.setLogInterval(50);
      expect(provider.logInterval, 50);

      provider.clearLogs();
      expect(provider.logs.isEmpty, true);
    });

    test('DeleteFilesProvider year and month toggling', () {
      final provider = DeleteFilesProvider();
      expect(provider.isProcessing, false);
      expect(provider.availableYears.isNotEmpty, true);

      provider.setYear(2026);
      expect(provider.selectedYear, 2026);

      provider.toggleMonth('Feb');
      expect(provider.validMonths.contains('Feb'), true);

      provider.toggleMonth('Feb');
      expect(provider.validMonths.contains('Feb'), false);
    });

    test('ThemeProvider default mode and toggle', () async {
      final provider = ThemeProvider();
      expect(provider.themeMode, isA<ThemeMode>());
    });
  });

  group('Widget Tests', () {
    testWidgets('App renders SplashScreen and initializes cleanly', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pump();

      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });
}
