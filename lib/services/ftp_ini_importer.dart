// Gene - Nov, 23, 2026: Importer for myFLO_FTP_automation.py config.ini and .env configuration files.
import '../models/ftp_upload_source.dart';
import 'ftp_transfer_service.dart';

class FtpIniImportResult {
  final String? host;
  final int? port;
  final String? username;
  final String? password;
  final FtpProtocol? protocol;
  final int? daysAgo;
  final int? timeoutSeconds;
  final int? retryCount;
  final int? retryDelaySeconds;
  final bool? dryRun;
  final int? logKeepDays;
  final List<FtpUploadSource> sources;

  const FtpIniImportResult({
    this.host,
    this.port,
    this.username,
    this.password,
    this.protocol,
    this.daysAgo,
    this.timeoutSeconds,
    this.retryCount,
    this.retryDelaySeconds,
    this.dryRun,
    this.logKeepDays,
    this.sources = const [],
  });

  bool get isEmpty =>
      host == null &&
      port == null &&
      username == null &&
      password == null &&
      protocol == null &&
      daysAgo == null &&
      timeoutSeconds == null &&
      retryCount == null &&
      retryDelaySeconds == null &&
      dryRun == null &&
      logKeepDays == null &&
      sources.isEmpty;
}

class FtpIniImporter {
  FtpIniImporter._();

  static FtpIniImportResult parse({String? iniContent, String? envContent}) {
    String? host;
    String? username;
    String? password;

    if (envContent != null && envContent.trim().isNotEmpty) {
      final envValues = _parseEnv(envContent);
      host = _nonEmpty(envValues['FTP_ADDRESS']);
      username = _nonEmpty(envValues['FTP_USERNAME']);
      password = envValues['FTP_PASSWORD'];
    }

    int? port;
    int? daysAgo;
    bool? useTls;
    int? timeoutSeconds;
    int? retryCount;
    int? retryDelaySeconds;
    bool? dryRun;
    int? logKeepDays;
    final sources = <FtpUploadSource>[];

    if (iniContent != null && iniContent.trim().isNotEmpty) {
      String? currentSection;
      String? currentSourceName;
      final sourceBuffers = <String, Map<String, String>>{};
      final sourceOrder = <String>[];

      for (final rawLine in iniContent.split(RegExp(r'\r?\n'))) {
        final trimmed = rawLine.trim();
        if (trimmed.isEmpty ||
            trimmed.startsWith(';') ||
            trimmed.startsWith('#')) {
          continue;
        }

        if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
          final sectionName = trimmed.substring(1, trimmed.length - 1).trim();
          final lower = sectionName.toLowerCase();
          if (lower.startsWith('source.')) {
            currentSection = 'source';
            currentSourceName = sectionName.substring(7).trim();
            if (currentSourceName.isNotEmpty &&
                !sourceBuffers.containsKey(currentSourceName)) {
              sourceBuffers[currentSourceName] = <String, String>{};
              sourceOrder.add(currentSourceName);
            }
          } else {
            currentSection = lower;
            currentSourceName = null;
          }
          continue;
        }

        final eqIdx = trimmed.indexOf('=');
        if (eqIdx <= 0) continue;
        final key = trimmed.substring(0, eqIdx).trim().toUpperCase();
        final rawValue = trimmed.substring(eqIdx + 1).trim();
        final value = _stripIniValue(rawValue);

        if (currentSection == 'ftp') {
          switch (key) {
            case 'FTP_PORT':
              final parsed = int.tryParse(value);
              if (parsed != null && parsed >= 1 && parsed <= 65535) {
                port = parsed;
              }
            case 'FTP_DAYS_AGO':
              final parsed = int.tryParse(value);
              if (parsed != null && parsed >= 0) {
                daysAgo = parsed;
              }
            case 'FTP_USE_TLS':
              useTls = _parseBool(value);
            case 'FTP_TIMEOUT':
              final parsed = int.tryParse(value);
              if (parsed != null) {
                timeoutSeconds = parsed.clamp(5, 600);
              }
            case 'FTP_RETRY_COUNT':
              final parsed = int.tryParse(value);
              if (parsed != null) {
                retryCount = parsed.clamp(1, 10);
              }
            case 'FTP_RETRY_DELAY':
              final parsed = int.tryParse(value);
              if (parsed != null) {
                retryDelaySeconds = parsed.clamp(0, 120);
              }
            case 'FTP_DRY_RUN':
              dryRun = _parseBool(value);
          }
        } else if (currentSection == 'logging') {
          if (key == 'LOG_KEEP_DAYS') {
            final parsed = int.tryParse(value);
            if (parsed != null) {
              logKeepDays = parsed.clamp(0, 365);
            }
          }
        } else if (currentSection == 'source' && currentSourceName != null) {
          sourceBuffers[currentSourceName]?[key] = value;
        }
      }

      int order = 1;
      for (final name in sourceOrder) {
        final fields = sourceBuffers[name] ?? const {};
        final localPath = _nonEmpty(fields['LOCAL_PATH']);
        if (localPath == null) continue;
        sources.add(
          FtpUploadSource(
            name: name,
            localPath: localPath,
            subfolders: fields['SUBFOLDERS'] ?? '',
            ftpDest: fields['FTP_DEST'] ?? '',
            runOrder: order++,
            enabled: true,
          ),
        );
      }
    }

    FtpProtocol? protocol;
    if (useTls != null) {
      if (useTls) {
        protocol = port == 990 ? FtpProtocol.ftps : FtpProtocol.ftpes;
      } else {
        protocol = FtpProtocol.ftp;
      }
    }

    return FtpIniImportResult(
      host: host,
      port: port,
      username: username,
      password: password,
      protocol: protocol,
      daysAgo: daysAgo,
      timeoutSeconds: timeoutSeconds,
      retryCount: retryCount,
      retryDelaySeconds: retryDelaySeconds,
      dryRun: dryRun,
      logKeepDays: logKeepDays,
      sources: sources,
    );
  }

  static Map<String, String> _parseEnv(String content) {
    final result = <String, String>{};
    for (final rawLine in content.split(RegExp(r'\r?\n'))) {
      final trimmed = rawLine.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final normalized = trimmed.startsWith('export ')
          ? trimmed.substring(7).trimLeft()
          : trimmed;
      final eqIdx = normalized.indexOf('=');
      if (eqIdx <= 0) continue;

      final key = normalized.substring(0, eqIdx).trim().toUpperCase();
      final rawVal = normalized.substring(eqIdx + 1).trim();
      result[key] = _stripEnvValue(rawVal);
    }
    return result;
  }

  static String _stripEnvValue(String raw) {
    if (raw.startsWith('"') || raw.startsWith("'")) {
      final quote = raw[0];
      final endQuoteIdx = raw.indexOf(quote, 1);
      if (endQuoteIdx > 0) {
        final trailing = raw.substring(endQuoteIdx + 1).trim();
        if (trailing.isEmpty || trailing.startsWith('#')) {
          return raw.substring(1, endQuoteIdx);
        }
      }
    }
    final commentMatch = RegExp(r'\s+#').firstMatch(raw);
    if (commentMatch != null) {
      return raw.substring(0, commentMatch.start).trimRight();
    }
    return raw;
  }

  static String _stripIniValue(String raw) {
    if (raw.startsWith('"') || raw.startsWith("'")) {
      final quote = raw[0];
      final endQuoteIdx = raw.indexOf(quote, 1);
      if (endQuoteIdx > 0) {
        final trailing = raw.substring(endQuoteIdx + 1).trim();
        if (trailing.isEmpty ||
            trailing.startsWith(';') ||
            trailing.startsWith('#')) {
          return raw.substring(1, endQuoteIdx).trim();
        }
      }
    }
    final commentMatch = RegExp(r'\s+[;#]').firstMatch(raw);
    if (commentMatch != null) {
      return raw.substring(0, commentMatch.start).trimRight();
    }
    return raw;
  }

  static bool? _parseBool(String value) {
    final lower = value.toLowerCase();
    if (lower == 'true' || lower == '1' || lower == 'yes') return true;
    if (lower == 'false' || lower == '0' || lower == 'no') return false;
    return null;
  }

  static String? _nonEmpty(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
