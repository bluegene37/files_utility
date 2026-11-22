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
// Gene - Nov, 23, 2026: Add enabled toggle to FtpUploadSource with backwards-compatible JSON deserialization.
class FtpUploadSource {
  final String name;
  final String? localPath;
  final String subfolders;
  final String ftpDest;
  final int runOrder;
  final bool enabled;

  const FtpUploadSource({
    this.name = '',
    this.localPath,
    this.subfolders = '',
    this.ftpDest = '',
    this.runOrder = 1,
    this.enabled = true,
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

  FtpUploadSource copyWith({
    String? name,
    String? localPath,
    bool clearLocalPath = false,
    String? subfolders,
    String? ftpDest,
    int? runOrder,
    bool? enabled,
  }) {
    return FtpUploadSource(
      name: name ?? this.name,
      localPath: clearLocalPath ? null : (localPath ?? this.localPath),
      subfolders: subfolders ?? this.subfolders,
      ftpDest: ftpDest ?? this.ftpDest,
      runOrder: runOrder ?? this.runOrder,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'localPath': localPath,
      'subfolders': subfolders,
      'ftpDest': ftpDest,
      'runOrder': runOrder,
      'enabled': enabled,
    };
  }

  factory FtpUploadSource.fromJson(Map<String, dynamic> json) {
    return FtpUploadSource(
      name: json['name'] as String? ?? '',
      localPath: json['localPath'] as String?,
      subfolders: json['subfolders'] as String? ?? '',
      ftpDest: json['ftpDest'] as String? ?? '',
      runOrder: (json['runOrder'] as num?)?.toInt() ?? 1,
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}
