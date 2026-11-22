// Gene - Nov, 21, 2026: Unit tests for FTP scheduler next-run calculation and date filter modes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
