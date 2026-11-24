// Gene - Nov, 21, 2026: Model representing a local upload source and its optional subfolder/destination mapping for FTP automation.
import 'package:path/path.dart' as p;

// class FtpUploadSource {
//   final String name;
//   final String? localPath;
//   final String subfolders;
//   final String ftpDest;
//   final int runOrder;
//
//   const FtpUploadSource({
//     this.name = '',
//     this.localPath,
//     this.subfolders = '',
//     this.ftpDest = '',
//     this.runOrder = 1,
//   });
//
//   List<String> get parsedSubfolders => subfolders
//       .split(',')
//       .map((s) => s.trim())
//       .where((s) => s.isNotEmpty)
//       .toList();
//
//   bool get isValid => localPath != null && localPath!.trim().isNotEmpty;
//
//   String get displayName {
//     final trimmed = name.trim();
//     if (trimmed.isNotEmpty) return trimmed;
//     final path = localPath?.trim() ?? '';
//     if (path.isNotEmpty) {
//       final base = p.basename(path);
//       if (base.isNotEmpty) return base;
//     }
//     return 'Source';
//   }
//
//   FtpUploadSource copyWith({
//     String? name,
//     String? localPath,
//     bool clearLocalPath = false,
//     String? subfolders,
//     String? ftpDest,
//     int? runOrder,
//   }) {
//     return FtpUploadSource(
//       name: name ?? this.name,
//       localPath: clearLocalPath ? null : (localPath ?? this.localPath),
//       subfolders: subfolders ?? this.subfolders,
//       ftpDest: ftpDest ?? this.ftpDest,
//       runOrder: runOrder ?? this.runOrder,
//     );
//   }
//
//   Map<String, dynamic> toJson() {
//     return {
//       'name': name,
//       'localPath': localPath,
//       'subfolders': subfolders,
//       'ftpDest': ftpDest,
//       'runOrder': runOrder,
//     };
//   }
//
//   factory FtpUploadSource.fromJson(Map<String, dynamic> json) {
//     return FtpUploadSource(
//       name: json['name'] as String? ?? '',
//       localPath: json['localPath'] as String?,
//       subfolders: json['subfolders'] as String? ?? '',
//       ftpDest: json['ftpDest'] as String? ?? '',
//       runOrder: (json['runOrder'] as num?)?.toInt() ?? 1,
//     );
//   }
// }
// // Gene - Nov, 23, 2026: Add enabled toggle to FtpUploadSource with backwards-compatible JSON deserialization.
// class FtpUploadSource {
//   final String name;
//   final String? localPath;
//   final String subfolders;
//   final String ftpDest;
//   final int runOrder;
//   final bool enabled;
// 
//   const FtpUploadSource({
//     this.name = '',
//     this.localPath,
//     this.subfolders = '',
//     this.ftpDest = '',
//     this.runOrder = 1,
//     this.enabled = true,
//   });
// 
//   List<String> get parsedSubfolders => subfolders
//       .split(',')
//       .map((s) => s.trim())
//       .where((s) => s.isNotEmpty)
//       .toList();
// 
//   bool get isValid => localPath != null && localPath!.trim().isNotEmpty;
// 
//   String get displayName {
//     final trimmed = name.trim();
//     if (trimmed.isNotEmpty) return trimmed;
//     final path = localPath?.trim() ?? '';
//     if (path.isNotEmpty) {
//       final base = p.basename(path);
//       if (base.isNotEmpty) return base;
//     }
//     return 'Source';
//   }
// 
//   FtpUploadSource copyWith({
//     String? name,
//     String? localPath,
//     bool clearLocalPath = false,
//     String? subfolders,
//     String? ftpDest,
//     int? runOrder,
//     bool? enabled,
//   }) {
//     return FtpUploadSource(
//       name: name ?? this.name,
//       localPath: clearLocalPath ? null : (localPath ?? this.localPath),
//       subfolders: subfolders ?? this.subfolders,
//       ftpDest: ftpDest ?? this.ftpDest,
//       runOrder: runOrder ?? this.runOrder,
//       enabled: enabled ?? this.enabled,
//     );
//   }
// 
//   Map<String, dynamic> toJson() {
//     return {
//       'name': name,
//       'localPath': localPath,
//       'subfolders': subfolders,
//       'ftpDest': ftpDest,
//       'runOrder': runOrder,
//       'enabled': enabled,
//     };
//   }
// 
//   factory FtpUploadSource.fromJson(Map<String, dynamic> json) {
//     return FtpUploadSource(
//       name: json['name'] as String? ?? '',
//       localPath: json['localPath'] as String?,
//       subfolders: json['subfolders'] as String? ?? '',
//       ftpDest: json['ftpDest'] as String? ?? '',
//       runOrder: (json['runOrder'] as num?)?.toInt() ?? 1,
//       enabled: json['enabled'] as bool? ?? true,
//     );
//   }
// }
// Gene - Nov, 24, 2026: Add per-source schedule cadence, per-source date filter overrides, and monthly completion tracking to FtpUploadSource.
enum FtpSourceScheduleMode {
  everyRun(label: 'Every Run', storageKey: 'everyRun'),
  weekly(label: 'Weekly', storageKey: 'weekly'),
  monthly(label: 'Monthly', storageKey: 'monthly'),
  manualOnly(label: 'Manual Only', storageKey: 'manualOnly');

  final String label;
  final String storageKey;

  const FtpSourceScheduleMode({required this.label, required this.storageKey});

  static FtpSourceScheduleMode fromStorage(String? value) {
    return FtpSourceScheduleMode.values.firstWhere(
      (m) => m.storageKey == value || m.name == value,
      orElse: () => FtpSourceScheduleMode.everyRun,
    );
  }
}

enum FtpSourceDateFilterMode {
  useGlobal(label: 'Use Global', storageKey: 'useGlobal'),
  allFiles(label: 'All Files', storageKey: 'allFiles'),
  today(label: 'Today', storageKey: 'today'),
  yesterday(label: 'Yesterday', storageKey: 'yesterday'),
  daysAgo(label: 'N Days Ago', storageKey: 'daysAgo'),
  lastNDays(label: 'Last N Days', storageKey: 'lastNDays');

  final String label;
  final String storageKey;

  const FtpSourceDateFilterMode({
    required this.label,
    required this.storageKey,
  });

  static FtpSourceDateFilterMode fromStorage(String? value) {
    return FtpSourceDateFilterMode.values.firstWhere(
      (m) => m.storageKey == value || m.name == value,
      orElse: () => FtpSourceDateFilterMode.useGlobal,
    );
  }
}

class FtpUploadSource {
  final String name;
  final String? localPath;
  final String subfolders;
  final String ftpDest;
  final int runOrder;
  final bool enabled;
  final FtpSourceScheduleMode scheduleMode;
  final List<int> weeklyDays;
  final int monthlyDay;
  final FtpSourceDateFilterMode dateFilterMode;
  final int dateFilterDays;
  final String? lastCompletedMonth;
  final String? lastCompletedAt;

  const FtpUploadSource({
    this.name = '',
    this.localPath,
    this.subfolders = '',
    this.ftpDest = '',
    this.runOrder = 1,
    this.enabled = true,
    this.scheduleMode = FtpSourceScheduleMode.everyRun,
    this.weeklyDays = const [7],
    this.monthlyDay = 1,
    this.dateFilterMode = FtpSourceDateFilterMode.useGlobal,
    this.dateFilterDays = 1,
    this.lastCompletedMonth,
    this.lastCompletedAt,
  });

  List<String> get parsedSubfolders => subfolders
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  bool get isValid => localPath != null && localPath!.trim().isNotEmpty;

  String get displayName {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty) return trimmed;
    final path = localPath?.trim() ?? '';
    if (path.isNotEmpty) {
      final base = p.basename(path);
      if (base.isNotEmpty) return base;
    }
    return 'Source';
  }

  static String formatMonthKey(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}';

  static int daysInMonth(int year, int month) =>
      DateTime(year, month + 1, 0).day;

  int resolveMonthlyTargetDay(int year, int month) {
    final lastDay = daysInMonth(year, month);
    return (monthlyDay <= 0 || monthlyDay > lastDay) ? lastDay : monthlyDay;
  }

  bool isCompletedForMonth(DateTime now) =>
      lastCompletedMonth == formatMonthKey(now);

  bool isDueForScheduledRun(DateTime now) {
    if (!enabled || !isValid) return false;
    switch (scheduleMode) {
      case FtpSourceScheduleMode.everyRun:
        return true;
      case FtpSourceScheduleMode.manualOnly:
        return false;
      case FtpSourceScheduleMode.weekly:
        return weeklyDays.contains(now.weekday);
      case FtpSourceScheduleMode.monthly:
        return now.day >= resolveMonthlyTargetDay(now.year, now.month) &&
            !isCompletedForMonth(now);
    }
  }

  String get scheduleSummary {
    switch (scheduleMode) {
      case FtpSourceScheduleMode.everyRun:
        return 'Every Run';
      case FtpSourceScheduleMode.manualOnly:
        return 'Manual Only';
      case FtpSourceScheduleMode.weekly:
        const dayNames = {
          1: 'Mon',
          2: 'Tue',
          3: 'Wed',
          4: 'Thu',
          5: 'Fri',
          6: 'Sat',
          7: 'Sun',
        };
        final sorted =
            weeklyDays.where((d) => d >= 1 && d <= 7).toSet().toList()..sort();
        if (sorted.isEmpty) return 'Weekly (None)';
        return 'Weekly (${sorted.map((d) => dayNames[d]!).join(', ')})';
      case FtpSourceScheduleMode.monthly:
        return monthlyDay <= 0
            ? 'Monthly (Last day)'
            : 'Monthly (Day $monthlyDay)';
    }
  }

  String get dateFilterSummary {
    switch (dateFilterMode) {
      case FtpSourceDateFilterMode.useGlobal:
        return 'Global';
      case FtpSourceDateFilterMode.allFiles:
        return 'All Files';
      case FtpSourceDateFilterMode.today:
        return 'Today';
      case FtpSourceDateFilterMode.yesterday:
        return 'Yesterday';
      case FtpSourceDateFilterMode.daysAgo:
        return '${dateFilterDays < 0 ? 0 : dateFilterDays}d ago';
      case FtpSourceDateFilterMode.lastNDays:
        return 'Last ${dateFilterDays < 1 ? 1 : dateFilterDays}d';
    }
  }

  FtpUploadSource copyWith({
    String? name,
    String? localPath,
    bool clearLocalPath = false,
    String? subfolders,
    String? ftpDest,
    int? runOrder,
    bool? enabled,
    FtpSourceScheduleMode? scheduleMode,
    List<int>? weeklyDays,
    int? monthlyDay,
    FtpSourceDateFilterMode? dateFilterMode,
    int? dateFilterDays,
    String? lastCompletedMonth,
    String? lastCompletedAt,
    bool clearMonthlyCompletion = false,
  }) {
    return FtpUploadSource(
      name: name ?? this.name,
      localPath: clearLocalPath ? null : (localPath ?? this.localPath),
      subfolders: subfolders ?? this.subfolders,
      ftpDest: ftpDest ?? this.ftpDest,
      runOrder: runOrder ?? this.runOrder,
      enabled: enabled ?? this.enabled,
      scheduleMode: scheduleMode ?? this.scheduleMode,
      weeklyDays: weeklyDays ?? this.weeklyDays,
      monthlyDay: monthlyDay ?? this.monthlyDay,
      dateFilterMode: dateFilterMode ?? this.dateFilterMode,
      dateFilterDays: dateFilterDays ?? this.dateFilterDays,
      lastCompletedMonth: clearMonthlyCompletion
          ? null
          : (lastCompletedMonth ?? this.lastCompletedMonth),
      lastCompletedAt: clearMonthlyCompletion
          ? null
          : (lastCompletedAt ?? this.lastCompletedAt),
    );
  }

  Map<String, dynamic> toJson({bool includeRuntimeState = true}) {
    final map = <String, dynamic>{
      'name': name,
      'localPath': localPath,
      'subfolders': subfolders,
      'ftpDest': ftpDest,
      'runOrder': runOrder,
      'enabled': enabled,
      'scheduleMode': scheduleMode.storageKey,
      'weeklyDays': List<int>.from(weeklyDays),
      'monthlyDay': monthlyDay,
      'dateFilterMode': dateFilterMode.storageKey,
      'dateFilterDays': dateFilterDays,
    };
    if (includeRuntimeState) {
      if (lastCompletedMonth != null) {
        map['lastCompletedMonth'] = lastCompletedMonth;
      }
      if (lastCompletedAt != null) {
        map['lastCompletedAt'] = lastCompletedAt;
      }
    }
    return map;
  }

  factory FtpUploadSource.fromJson(Map<String, dynamic> json) {
    List<int> parsedWeeklyDays = const [7];
    if (json['weeklyDays'] is List) {
      parsedWeeklyDays =
          (json['weeklyDays'] as List)
              .map((e) => (e as num?)?.toInt())
              .whereType<int>()
              .where((d) => d >= 1 && d <= 7)
              .toSet()
              .toList()
            ..sort();
    }
    final rawMonth = json['lastCompletedMonth'] as String?;
    final rawCompletedAt = json['lastCompletedAt'] as String?;
    final cleanMonth = (rawMonth != null && rawMonth.trim().isNotEmpty)
        ? rawMonth.trim()
        : null;
    final cleanCompletedAt =
        (rawCompletedAt != null && rawCompletedAt.trim().isNotEmpty)
        ? rawCompletedAt.trim()
        : null;
    return FtpUploadSource(
      name: json['name'] as String? ?? '',
      localPath: json['localPath'] as String?,
      subfolders: json['subfolders'] as String? ?? '',
      ftpDest: json['ftpDest'] as String? ?? '',
      runOrder: ((json['runOrder'] as num?)?.toInt() ?? 1).clamp(1, 20),
      enabled: json['enabled'] as bool? ?? true,
      scheduleMode: FtpSourceScheduleMode.fromStorage(
        json['scheduleMode'] as String?,
      ),
      weeklyDays: parsedWeeklyDays,
      monthlyDay: ((json['monthlyDay'] as num?)?.toInt() ?? 1).clamp(0, 31),
      dateFilterMode: FtpSourceDateFilterMode.fromStorage(
        json['dateFilterMode'] as String?,
      ),
      dateFilterDays: ((json['dateFilterDays'] as num?)?.toInt() ?? 1).clamp(
        0,
        3650,
      ),
      lastCompletedMonth: cleanMonth,
      lastCompletedAt: cleanCompletedAt,
    );
  }
}
