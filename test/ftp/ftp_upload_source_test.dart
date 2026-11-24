// Gene - Nov, 21, 2026: Unit tests for FtpUploadSource serialization and helpers.
import 'package:flutter_test/flutter_test.dart';
import 'package:files_utility/models/ftp_upload_source.dart';

void main() {
  group('FtpUploadSource', () {
    test('JSON round-trips all fields accurately', () {
      const source = FtpUploadSource(
        name: 'Backups',
        localPath: '/tmp/backups',
        subfolders: 'FolderA, FolderB',
        ftpDest: 'RemoteBackups',
        runOrder: 3,
      );

      final json = source.toJson();
      final decoded = FtpUploadSource.fromJson(json);

      expect(decoded.name, 'Backups');
      expect(decoded.localPath, '/tmp/backups');
      expect(decoded.subfolders, 'FolderA, FolderB');
      expect(decoded.ftpDest, 'RemoteBackups');
      expect(decoded.runOrder, 3);
      expect(decoded.isValid, isTrue);
      expect(decoded.displayName, 'Backups');
    });

    test('parsedSubfolders trims entries and drops blanks', () {
      const source = FtpUploadSource(
        subfolders: ' FolderA , , FolderB,  FolderC , ',
      );
      expect(source.parsedSubfolders, ['FolderA', 'FolderB', 'FolderC']);
    });

    test('displayName falls back to path basename then Source', () {
      const fromPath = FtpUploadSource(localPath: '/var/data/exports');
      expect(fromPath.displayName, 'exports');

      const empty = FtpUploadSource();
      expect(empty.displayName, 'Source');
      expect(empty.isValid, isFalse);
    });

    test('copyWith(clearLocalPath: true) clears localPath', () {
      const source = FtpUploadSource(name: 'Docs', localPath: '/tmp/docs');
      final cleared = source.copyWith(clearLocalPath: true);
      expect(cleared.localPath, isNull);
      expect(cleared.isValid, isFalse);
      expect(cleared.name, 'Docs');
    });

    // Gene - Nov, 23, 2026: Verify enabled flag default, copyWith, serialization, and backwards-compatible JSON decoding.
    test(
      'enabled defaults to true, toggles via copyWith, and decodes legacy JSON',
      () {
        const defaultSrc = FtpUploadSource(localPath: '/tmp/a');
        expect(defaultSrc.enabled, isTrue);

        final disabled = defaultSrc.copyWith(enabled: false);
        expect(disabled.enabled, isFalse);

        final decodedDisabled = FtpUploadSource.fromJson(disabled.toJson());
        expect(decodedDisabled.enabled, isFalse);

        final legacyDecoded = FtpUploadSource.fromJson({
          'name': 'Legacy',
          'localPath': '/tmp/legacy',
          'subfolders': 'Sub1',
          'ftpDest': 'Dest',
          'runOrder': 2,
        });
        expect(legacyDecoded.enabled, isTrue);
        // Gene - Nov, 24, 2026: Legacy JSON defaults for schedule cadence, date filter override, and monthly runtime state.
        expect(legacyDecoded.scheduleMode, FtpSourceScheduleMode.everyRun);
        expect(legacyDecoded.weeklyDays, [7]);
        expect(legacyDecoded.monthlyDay, 1);
        expect(legacyDecoded.dateFilterMode, FtpSourceDateFilterMode.useGlobal);
        expect(legacyDecoded.dateFilterDays, 1);
        expect(legacyDecoded.lastCompletedMonth, isNull);
        expect(legacyDecoded.lastCompletedAt, isNull);
      },
    );

    // Gene - Nov, 24, 2026: Verify schedule/date-filter serialization, runtime state omission, short-month clamping, and monthly due/catch-up logic.
    test(
      'JSON round-trips cadence/filter fields and omits runtime state when includeRuntimeState is false',
      () {
        const source = FtpUploadSource(
          name: 'Database',
          localPath: '/tmp/database',
          ftpDest: 'DBBackups',
          runOrder: 2,
          enabled: true,
          scheduleMode: FtpSourceScheduleMode.monthly,
          weeklyDays: [5, 1, 5],
          monthlyDay: 31,
          dateFilterMode: FtpSourceDateFilterMode.lastNDays,
          dateFilterDays: 30,
          lastCompletedMonth: '2026-11',
          lastCompletedAt: '2026-11-02T00:05:00.000',
        );

        final withRuntime = source.toJson(includeRuntimeState: true);
        expect(withRuntime['lastCompletedMonth'], '2026-11');
        expect(withRuntime['lastCompletedAt'], '2026-11-02T00:05:00.000');

        final decodedRuntime = FtpUploadSource.fromJson(withRuntime);
        expect(decodedRuntime.scheduleMode, FtpSourceScheduleMode.monthly);
        expect(decodedRuntime.weeklyDays, [1, 5]);
        expect(decodedRuntime.monthlyDay, 31);
        expect(
          decodedRuntime.dateFilterMode,
          FtpSourceDateFilterMode.lastNDays,
        );
        expect(decodedRuntime.dateFilterDays, 30);
        expect(decodedRuntime.lastCompletedMonth, '2026-11');
        expect(decodedRuntime.lastCompletedAt, '2026-11-02T00:05:00.000');

        final withoutRuntime = source.toJson(includeRuntimeState: false);
        expect(withoutRuntime.containsKey('lastCompletedMonth'), isFalse);
        expect(withoutRuntime.containsKey('lastCompletedAt'), isFalse);
        final decodedExport = FtpUploadSource.fromJson(withoutRuntime);
        expect(decodedExport.scheduleMode, FtpSourceScheduleMode.monthly);
        expect(decodedExport.monthlyDay, 31);
        expect(decodedExport.dateFilterMode, FtpSourceDateFilterMode.lastNDays);
        expect(decodedExport.dateFilterDays, 30);
        expect(decodedExport.lastCompletedMonth, isNull);
        expect(decodedExport.lastCompletedAt, isNull);

        final cleared = decodedRuntime.copyWith(clearMonthlyCompletion: true);
        expect(cleared.lastCompletedMonth, isNull);
        expect(cleared.lastCompletedAt, isNull);
      },
    );

    test(
      'resolveMonthlyTargetDay clamps short months and handles Last day (0)',
      () {
        const lastDaySrc = FtpUploadSource(
          localPath: '/tmp/db',
          scheduleMode: FtpSourceScheduleMode.monthly,
          monthlyDay: 0,
        );
        expect(lastDaySrc.resolveMonthlyTargetDay(2026, 2), 28);
        expect(lastDaySrc.resolveMonthlyTargetDay(2028, 2), 29);
        expect(lastDaySrc.resolveMonthlyTargetDay(2026, 11), 30);
        expect(lastDaySrc.resolveMonthlyTargetDay(2026, 12), 31);

        const day31Src = FtpUploadSource(
          localPath: '/tmp/db',
          scheduleMode: FtpSourceScheduleMode.monthly,
          monthlyDay: 31,
        );
        expect(day31Src.resolveMonthlyTargetDay(2026, 2), 28);
        expect(day31Src.resolveMonthlyTargetDay(2028, 2), 29);
        expect(day31Src.resolveMonthlyTargetDay(2026, 11), 30);
      },
    );

    test(
      'isDueForScheduledRun evaluates everyRun, manualOnly, weekly, and monthly catch-up/rollover',
      () {
        const everySrc = FtpUploadSource(localPath: '/tmp/every');
        expect(
          everySrc.isDueForScheduledRun(DateTime(2026, 11, 24, 1, 0)),
          isTrue,
        );
        expect(
          everySrc
              .copyWith(enabled: false)
              .isDueForScheduledRun(DateTime(2026, 11, 24, 1, 0)),
          isFalse,
        );

        const manualSrc = FtpUploadSource(
          localPath: '/tmp/manual',
          scheduleMode: FtpSourceScheduleMode.manualOnly,
        );
        expect(
          manualSrc.isDueForScheduledRun(DateTime(2026, 11, 24, 1, 0)),
          isFalse,
        );

        // 2026-11-23 is Monday (1); 2026-11-24 is Tuesday (2).
        const weeklySrc = FtpUploadSource(
          localPath: '/tmp/weekly',
          scheduleMode: FtpSourceScheduleMode.weekly,
          weeklyDays: [1, 5],
        );
        expect(
          weeklySrc.isDueForScheduledRun(DateTime(2026, 11, 23, 2, 0)),
          isTrue,
        );
        expect(
          weeklySrc.isDueForScheduledRun(DateTime(2026, 11, 24, 2, 0)),
          isFalse,
        );

        // Monthly Day 15: before 15th -> false; on/after 15th -> true until completed; next month -> true again.
        const monthlySrc = FtpUploadSource(
          localPath: '/tmp/db',
          scheduleMode: FtpSourceScheduleMode.monthly,
          monthlyDay: 15,
        );
        expect(
          monthlySrc.isDueForScheduledRun(DateTime(2026, 11, 14, 2, 0)),
          isFalse,
        );
        expect(
          monthlySrc.isDueForScheduledRun(DateTime(2026, 11, 15, 2, 0)),
          isTrue,
        );
        expect(
          monthlySrc.isDueForScheduledRun(DateTime(2026, 11, 20, 2, 0)),
          isTrue,
        );

        final completedNov = monthlySrc.copyWith(
          lastCompletedMonth: '2026-11',
          lastCompletedAt: '2026-11-16T01:00:00.000',
        );
        expect(
          completedNov.isDueForScheduledRun(DateTime(2026, 11, 20, 2, 0)),
          isFalse,
        );
        expect(
          completedNov.isDueForScheduledRun(DateTime(2026, 12, 14, 2, 0)),
          isFalse,
        );
        expect(
          completedNov.isDueForScheduledRun(DateTime(2026, 12, 15, 2, 0)),
          isTrue,
        );
      },
    );
  });
}
