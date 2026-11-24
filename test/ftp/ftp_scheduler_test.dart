// Gene - Nov, 21, 2026: Unit tests for FTP scheduler next-run calculation and date filter modes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Gene - Nov, 24, 2026: Import FtpUploadSource to test per-source date filter matching.
import 'package:files_utility/models/ftp_upload_source.dart';
import 'package:files_utility/providers/ftp_files_provider.dart';

Map<int, bool> _days({List<int> enabled = const []}) {
  return {for (int d = 1; d <= 7; d++) d: enabled.contains(d)};
}

void main() {
  group('FtpFilesProvider.computeNextScheduledRun', () {
    test('returns today when today is checked and runTime is still ahead', () {
      // 2026-11-23 is a Monday (weekday == 1).
      final now = DateTime(2026, 11, 23, 8, 15);
      final next = FtpFilesProvider.computeNextScheduledRun(
        now: now,
        runTime: const TimeOfDay(hour: 10, minute: 30),
        runDays: _days(enabled: [1, 3, 5]),
      );
      expect(next, DateTime(2026, 11, 23, 10, 30));
    });

    test('advances to next checked day when today runTime has passed', () {
      // 2026-11-23 is Monday 14:00 -> next checked day is Wednesday (Nov 25).
      final now = DateTime(2026, 11, 23, 14, 0);
      final next = FtpFilesProvider.computeNextScheduledRun(
        now: now,
        runTime: const TimeOfDay(hour: 9, minute: 0),
        runDays: _days(enabled: [1, 3, 5]),
      );
      expect(next, DateTime(2026, 11, 25, 9, 0));
    });

    test('wraps +7 days when only today is checked and time passed', () {
      // 2026-11-23 is Monday 10:00, runTime == 10:00 -> must wrap to next Monday.
      final now = DateTime(2026, 11, 23, 10, 0);
      final next = FtpFilesProvider.computeNextScheduledRun(
        now: now,
        runTime: const TimeOfDay(hour: 10, minute: 0),
        runDays: _days(enabled: [1]),
      );
      expect(next, DateTime(2026, 11, 30, 10, 0));
    });

    test('handles weekend gap from Friday night to Monday morning', () {
      // 2026-11-27 is Friday (weekday == 5).
      final now = DateTime(2026, 11, 27, 22, 0);
      final next = FtpFilesProvider.computeNextScheduledRun(
        now: now,
        runTime: const TimeOfDay(hour: 6, minute: 45),
        runDays: _days(enabled: [1, 2, 3, 4, 5]),
      );
      expect(next, DateTime(2026, 11, 30, 6, 45));
    });

    test('returns null when no weekdays are selected', () {
      final now = DateTime(2026, 11, 23, 8, 0);
      final next = FtpFilesProvider.computeNextScheduledRun(
        now: now,
        runTime: const TimeOfDay(hour: 10, minute: 0),
        runDays: _days(),
      );
      expect(next, isNull);
    });
  });

  // Gene - Nov, 24, 2026: Unit tests for FTP schedule window end and active window (same-day, overnight, and no-cutoff).
  group('FtpFilesProvider.computeWindowEnd & computeActiveWindow', () {
    test('computeWindowEnd handles same-day, overnight, and Start == End', () {
      final start = DateTime(2026, 11, 23, 22, 0);
      expect(
        FtpFilesProvider.computeWindowEnd(
          windowStart: DateTime(2026, 11, 23, 8, 0),
          runTime: const TimeOfDay(hour: 8, minute: 0),
          runEndTime: const TimeOfDay(hour: 17, minute: 30),
        ),
        DateTime(2026, 11, 23, 17, 30),
      );
      expect(
        FtpFilesProvider.computeWindowEnd(
          windowStart: start,
          runTime: const TimeOfDay(hour: 22, minute: 0),
          runEndTime: const TimeOfDay(hour: 6, minute: 0),
        ),
        DateTime(2026, 11, 24, 6, 0),
      );
      expect(
        FtpFilesProvider.computeWindowEnd(
          windowStart: start,
          runTime: const TimeOfDay(hour: 22, minute: 0),
          runEndTime: const TimeOfDay(hour: 22, minute: 0),
        ),
        isNull,
      );
    });

    test('computeActiveWindow matches same-day window [start, end)', () {
      // 2026-11-23 is Monday (weekday == 1).
      const start = TimeOfDay(hour: 9, minute: 0);
      const end = TimeOfDay(hour: 17, minute: 0);
      final days = _days(enabled: [1]);

      expect(
        FtpFilesProvider.computeActiveWindow(
          now: DateTime(2026, 11, 23, 8, 59),
          runTime: start,
          runEndTime: end,
          runDays: days,
        ),
        isNull,
      );
      final atStart = FtpFilesProvider.computeActiveWindow(
        now: DateTime(2026, 11, 23, 9, 0),
        runTime: start,
        runEndTime: end,
        runDays: days,
      );
      expect(atStart?.start, DateTime(2026, 11, 23, 9, 0));
      expect(atStart?.end, DateTime(2026, 11, 23, 17, 0));

      final midDay = FtpFilesProvider.computeActiveWindow(
        now: DateTime(2026, 11, 23, 13, 30),
        runTime: start,
        runEndTime: end,
        runDays: days,
      );
      expect(midDay?.end, DateTime(2026, 11, 23, 17, 0));

      // Exclusive at End time.
      expect(
        FtpFilesProvider.computeActiveWindow(
          now: DateTime(2026, 11, 23, 17, 0),
          runTime: start,
          runEndTime: end,
          runDays: days,
        ),
        isNull,
      );
    });

    test('computeActiveWindow matches overnight midnight-crossover window', () {
      // Only Monday (1) checked, 22:00 -> 06:00 Tuesday.
      const start = TimeOfDay(hour: 22, minute: 0);
      const end = TimeOfDay(hour: 6, minute: 0);
      final days = _days(enabled: [1]);

      final monNight = FtpFilesProvider.computeActiveWindow(
        now: DateTime(2026, 11, 23, 23, 30),
        runTime: start,
        runEndTime: end,
        runDays: days,
      );
      expect(monNight?.start, DateTime(2026, 11, 23, 22, 0));
      expect(monNight?.end, DateTime(2026, 11, 24, 6, 0));

      // Tuesday 02:00 belongs to Monday's overnight window even though Tuesday isn't checked.
      final tueEarly = FtpFilesProvider.computeActiveWindow(
        now: DateTime(2026, 11, 24, 2, 0),
        runTime: start,
        runEndTime: end,
        runDays: days,
      );
      expect(tueEarly?.start, DateTime(2026, 11, 23, 22, 0));
      expect(tueEarly?.end, DateTime(2026, 11, 24, 6, 0));

      // Exclusive at Tuesday 06:00.
      expect(
        FtpFilesProvider.computeActiveWindow(
          now: DateTime(2026, 11, 24, 6, 0),
          runTime: start,
          runEndTime: end,
          runDays: days,
        ),
        isNull,
      );
    });

    test('computeActiveWindow returns null when Start == End', () {
      expect(
        FtpFilesProvider.computeActiveWindow(
          now: DateTime(2026, 11, 23, 10, 0),
          runTime: const TimeOfDay(hour: 10, minute: 0),
          runEndTime: const TimeOfDay(hour: 10, minute: 0),
          runDays: _days(enabled: [1]),
        ),
        isNull,
      );
    });
  });

  group('FtpFilesProvider.matchesDateFilter', () {
    final refNow = DateTime(2026, 11, 21, 9, 30);

    test('matches yesterday, today, and daysAgo relative to referenceNow', () {
      expect(
        FtpFilesProvider.matchesDateFilter(
          fileDate: DateTime(2026, 11, 20, 23, 59),
          dateMode: FtpDateMode.yesterday,
          referenceNow: refNow,
          daysAgo: 1,
          specificDate: refNow,
          fromDate: refNow,
          toDate: refNow,
        ),
        isTrue,
      );
      expect(
        FtpFilesProvider.matchesDateFilter(
          fileDate: DateTime(2026, 11, 21, 0, 1),
          dateMode: FtpDateMode.yesterday,
          referenceNow: refNow,
          daysAgo: 1,
          specificDate: refNow,
          fromDate: refNow,
          toDate: refNow,
        ),
        isFalse,
      );
      expect(
        FtpFilesProvider.matchesDateFilter(
          fileDate: DateTime(2026, 11, 21, 18, 0),
          dateMode: FtpDateMode.today,
          referenceNow: refNow,
          daysAgo: 1,
          specificDate: refNow,
          fromDate: refNow,
          toDate: refNow,
        ),
        isTrue,
      );
      expect(
        FtpFilesProvider.matchesDateFilter(
          fileDate: DateTime(2026, 11, 18, 12, 0),
          dateMode: FtpDateMode.daysAgo,
          referenceNow: refNow,
          daysAgo: 3,
          specificDate: refNow,
          fromDate: refNow,
          toDate: refNow,
        ),
        isTrue,
      );
    });

    test('matches specificDate, inclusive dateRange, and allFiles', () {
      expect(
        FtpFilesProvider.matchesDateFilter(
          fileDate: DateTime(2026, 3, 13, 15, 45),
          dateMode: FtpDateMode.specificDate,
          referenceNow: refNow,
          daysAgo: 1,
          specificDate: DateTime(2026, 3, 13),
          fromDate: refNow,
          toDate: refNow,
        ),
        isTrue,
      );
      expect(
        FtpFilesProvider.matchesDateFilter(
          fileDate: DateTime(2026, 11, 15, 22, 0),
          dateMode: FtpDateMode.dateRange,
          referenceNow: refNow,
          daysAgo: 1,
          specificDate: refNow,
          fromDate: DateTime(2026, 11, 10),
          toDate: DateTime(2026, 11, 15),
        ),
        isTrue,
      );
      expect(
        FtpFilesProvider.matchesDateFilter(
          fileDate: DateTime(2026, 11, 16, 0, 0),
          dateMode: FtpDateMode.dateRange,
          referenceNow: refNow,
          daysAgo: 1,
          specificDate: refNow,
          fromDate: DateTime(2026, 11, 10),
          toDate: DateTime(2026, 11, 15),
        ),
        isFalse,
      );
      expect(
        FtpFilesProvider.matchesDateFilter(
          fileDate: DateTime(2019, 1, 1),
          dateMode: FtpDateMode.allFiles,
          referenceNow: refNow,
          daysAgo: 1,
          specificDate: refNow,
          fromDate: refNow,
          toDate: refNow,
        ),
        isTrue,
      );
    });
  });

  // Gene - Nov, 24, 2026: Unit tests for per-source date filter overrides including inclusive Last N Days boundaries.
  group('FtpFilesProvider.matchesSourceDateFilter', () {
    final refNow = DateTime(2026, 11, 24, 9, 30);

    bool eval(FtpUploadSource source, DateTime fileDate, {FtpDateMode globalMode = FtpDateMode.yesterday}) {
      return FtpFilesProvider.matchesSourceDateFilter(
        fileDate: fileDate,
        source: source,
        globalDateMode: globalMode,
        referenceNow: refNow,
        globalDaysAgo: 1,
        globalSpecificDate: refNow,
        globalFromDate: refNow,
        globalToDate: refNow,
      );
    }

    test('delegates to global filter when useGlobal and supports allFiles/today/yesterday/daysAgo', () {
      const globalSrc = FtpUploadSource(localPath: '/tmp/global');
      expect(eval(globalSrc, DateTime(2026, 11, 23, 18, 0)), isTrue);
      expect(eval(globalSrc, DateTime(2026, 11, 24, 8, 0)), isFalse);

      const allSrc = FtpUploadSource(
        localPath: '/tmp/all',
        dateFilterMode: FtpSourceDateFilterMode.allFiles,
      );
      expect(eval(allSrc, DateTime(2020, 1, 1)), isTrue);

      const todaySrc = FtpUploadSource(
        localPath: '/tmp/today',
        dateFilterMode: FtpSourceDateFilterMode.today,
      );
      expect(eval(todaySrc, DateTime(2026, 11, 24, 23, 59)), isTrue);
      expect(eval(todaySrc, DateTime(2026, 11, 23, 23, 59)), isFalse);

      const yesterdaySrc = FtpUploadSource(
        localPath: '/tmp/yest',
        dateFilterMode: FtpSourceDateFilterMode.yesterday,
      );
      expect(eval(yesterdaySrc, DateTime(2026, 11, 23, 12, 0)), isTrue);
      expect(eval(yesterdaySrc, DateTime(2026, 11, 24, 12, 0)), isFalse);

      const daysAgoSrc = FtpUploadSource(
        localPath: '/tmp/ago',
        dateFilterMode: FtpSourceDateFilterMode.daysAgo,
        dateFilterDays: 3,
      );
      expect(eval(daysAgoSrc, DateTime(2026, 11, 21, 10, 0)), isTrue);
      expect(eval(daysAgoSrc, DateTime(2026, 11, 22, 10, 0)), isFalse);
    });

    test('evaluates lastNDays inclusively for N=1 and N=7 boundaries', () {
      const oneDaySrc = FtpUploadSource(
        localPath: '/tmp/last1',
        dateFilterMode: FtpSourceDateFilterMode.lastNDays,
        dateFilterDays: 1,
      );
      expect(eval(oneDaySrc, DateTime(2026, 11, 24, 1, 0)), isTrue);
      expect(eval(oneDaySrc, DateTime(2026, 11, 23, 23, 59)), isFalse);

      const sevenDaySrc = FtpUploadSource(
        localPath: '/tmp/last7',
        dateFilterMode: FtpSourceDateFilterMode.lastNDays,
        dateFilterDays: 7,
      );
      // refDay = Nov 24 -> [Nov 18 .. Nov 24] inclusive.
      expect(eval(sevenDaySrc, DateTime(2026, 11, 18, 0, 0)), isTrue);
      expect(eval(sevenDaySrc, DateTime(2026, 11, 21, 12, 0)), isTrue);
      expect(eval(sevenDaySrc, DateTime(2026, 11, 24, 23, 59)), isTrue);
      expect(eval(sevenDaySrc, DateTime(2026, 11, 17, 23, 59)), isFalse);
      expect(eval(sevenDaySrc, DateTime(2026, 11, 25, 0, 0)), isFalse);
    });
  });
}
