class RunRecord {
  final String id;
  final String operation; // 'Transfer', 'Copy', 'Delete', 'Count'
  final DateTime startTime;
  final DateTime endTime;
  final int filesProcessed;
  final int foldersProcessed;
  final int errors;
  final String status; // 'Completed', 'Stopped', 'Error'
  final String configSummary;

  RunRecord({
    required this.id,
    required this.operation,
    required this.startTime,
    required this.endTime,
    required this.filesProcessed,
    this.foldersProcessed = 0,
    required this.errors,
    required this.status,
    required this.configSummary,
  });

  Duration get duration => endTime.difference(startTime);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'operation': operation,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'filesProcessed': filesProcessed,
      'foldersProcessed': foldersProcessed,
      'errors': errors,
      'status': status,
      'configSummary': configSummary,
    };
  }

  factory RunRecord.fromJson(Map<String, dynamic> json) {
    return RunRecord(
      id: json['id'] as String? ?? 'UNKNOWN',
      operation: json['operation'] as String? ?? 'Unknown',
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: DateTime.parse(json['endTime'] as String),
      filesProcessed: json['filesProcessed'] as int? ?? 0,
      foldersProcessed: json['foldersProcessed'] as int? ?? 0,
      errors: json['errors'] as int? ?? 0,
      status: json['status'] as String? ?? 'Unknown',
      configSummary: json['configSummary'] as String? ?? '',
    );
  }
}
