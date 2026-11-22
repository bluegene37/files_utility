// Gene - Nov, 21, 2026: FTP/FTPS/FTPES/SFTP client abstraction and ftpconnect adapter.
import 'dart:io';
import 'package:ftpconnect/ftpconnect.dart';
import 'package:path/path.dart' as p;
import 'credential_obfuscator.dart';

enum FtpProtocol {
  ftp(
    label: 'FTP (Plain)',
    shortLabel: 'FTP',
    scheme: 'ftp',
    defaultPort: 21,
    supportsTransferMode: true,
    storageKey: 'ftp',
  ),
  ftps(
    label: 'FTPS (Implicit TLS)',
    shortLabel: 'FTPS',
    scheme: 'ftps',
    defaultPort: 990,
    supportsTransferMode: true,
    storageKey: 'ftps',
  ),
  ftpes(
    label: 'FTPES (Explicit TLS)',
    shortLabel: 'FTPES',
    scheme: 'ftpes',
    defaultPort: 21,
    supportsTransferMode: true,
    storageKey: 'ftpes',
  ),
  sftp(
    label: 'SFTP (SSH)',
    shortLabel: 'SFTP',
    scheme: 'sftp',
    defaultPort: 22,
    supportsTransferMode: false,
    storageKey: 'sftp',
  );

  final String label;
  final String shortLabel;
  final String scheme;
  final int defaultPort;
  final bool supportsTransferMode;
  final String storageKey;

  const FtpProtocol({
    required this.label,
    required this.shortLabel,
    required this.scheme,
    required this.defaultPort,
    required this.supportsTransferMode,
    required this.storageKey,
  });

  static FtpProtocol fromStorage(String? value) {
    return FtpProtocol.values.firstWhere(
      (p) => p.storageKey == value,
      orElse: () => FtpProtocol.ftp,
    );
  }
}

enum FtpTransferMode {
  passive(label: 'Passive', storageKey: 'passive'),
  active(label: 'Active', storageKey: 'active');

  final String label;
  final String storageKey;

  const FtpTransferMode({required this.label, required this.storageKey});

  static FtpTransferMode fromStorage(String? value) {
    return FtpTransferMode.values.firstWhere(
      (m) => m.storageKey == value,
      orElse: () => FtpTransferMode.passive,
    );
  }
}

class FtpConnectionConfig {
  final String host;
  final int port;
  final String username;
  final String password;
  final FtpProtocol protocol;
  final FtpTransferMode transferMode;
  final int timeoutSeconds;

  const FtpConnectionConfig({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    this.protocol = FtpProtocol.ftp,
    this.transferMode = FtpTransferMode.passive,
    this.timeoutSeconds = 30,
  });

  /// Formats a sanitized endpoint URI for UI, FileLogger, and RunRecord without credentials.
  String displayEndpoint([String? remoteDir]) {
    final trimmedHost = host.trim();
    final cleanDir = remoteDir == null ? '' : joinRemotePath(remoteDir, '');
    final strippedDir = cleanDir.startsWith('/')
        ? cleanDir.substring(1)
        : cleanDir;
    final base = '${protocol.scheme}://$trimmedHost:$port';
    if (strippedDir.isEmpty) return base;
    return '$base/$strippedDir';
  }
}

class FtpTestResult {
  final bool success;
  final String message;

  const FtpTestResult({required this.success, required this.message});
}

/// Normalizes and joins two remote path parts using forward slashes while dropping `.` and `..`.
String joinRemotePath(String prefix, String subPath) {
  final trimmedPrefix = prefix.trim();
  final hasLeadingSlash =
      trimmedPrefix.startsWith('/') || trimmedPrefix.startsWith(r'\');
  final combined = <String>[];
  for (final rawPart in [prefix, subPath]) {
    final normalized = rawPart.replaceAll(r'\', '/');
    for (final seg in normalized.split('/')) {
      final trimmed = seg.trim();
      if (trimmed.isEmpty || trimmed == '.' || trimmed == '..') continue;
      combined.add(trimmed);
    }
  }
  final joined = combined.join('/');
  if (joined.isEmpty) {
    return hasLeadingSlash ? '/' : '';
  }
  return hasLeadingSlash ? '/$joined' : joined;
}

abstract class FtpClientAdapter {
  Future<void> connect();
  Future<void> disconnect();
  Future<String> currentDirectory();
  Future<bool> changeDirectory(String remotePath);
  Future<bool> ensureRemoteDirectory(String remotePath);
  Future<Map<String, int?>?> listRemoteFileSizes();
  Future<int?> getRemoteFileSize(String remoteName);
  Future<bool> uploadFile(File localFile, {String? remoteName});
}

class FtpConnectAdapter implements FtpClientAdapter {
  final FtpConnectionConfig config;
  late final FileTransferClient _client;
  String? _initialDirectory;

  FtpConnectAdapter(this.config) {
    _client = _createClient(config);
  }

  static FileTransferClient _createClient(FtpConnectionConfig config) {
    final timeout = config.timeoutSeconds.clamp(5, 600);
    if (config.protocol == FtpProtocol.sftp) {
      return SFTPConnect(
        config.host.trim(),
        port: config.port,
        user: config.username.trim().isEmpty
            ? 'anonymous'
            : config.username.trim(),
        pass: config.password,
        timeout: timeout,
      );
    }

    final SecurityType securityType;
    switch (config.protocol) {
      case FtpProtocol.ftps:
        securityType = SecurityType.ftps;
      case FtpProtocol.ftpes:
        securityType = SecurityType.ftpes;
      case FtpProtocol.ftp:
      case FtpProtocol.sftp:
        securityType = SecurityType.ftp;
    }

    return FTPConnect(
      config.host.trim(),
      port: config.port,
      user: config.username.trim().isEmpty
          ? 'anonymous'
          : config.username.trim(),
      pass: config.password,
      securityType: securityType,
      // ftpconnect 3.0.0 leaves active-mode data sockets unimplemented; always use passive.
      transferMode: TransferMode.passive,
      transferType: TransferType.binary,
      timeout: timeout,
    );
  }

  @override
  Future<void> connect() async {
    try {
      final ok = await _client.connect();
      if (!ok) {
        throw Exception('Failed to connect to ${config.displayEndpoint()}');
      }
      if (_client is FTPConnect) {
        // FTPConnect.connect() resets transferType to auto; force binary mode (TYPE I) like Python storbinary.
        try {
          await _client.setTransferType(TransferType.binary);
        } catch (_) {}
        _initialDirectory = await currentDirectory();
      } else if (_client is SFTPConnect) {
        try {
          final sftp = _client;
          final absHome = await sftp.sftpClient.absolute('.');
          if (absHome.isNotEmpty) {
            _initialDirectory = absHome;
            await sftp.changeDirectory(absHome);
          } else {
            _initialDirectory = await currentDirectory();
          }
        } catch (_) {
          _initialDirectory = await currentDirectory();
        }
      } else {
        _initialDirectory = await currentDirectory();
      }
    } catch (e) {
      throw Exception(
        CredentialObfuscator.redact(e.toString(), config.password),
      );
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await _client.disconnect();
    } catch (_) {}
  }

  @override
  Future<String> currentDirectory() async {
    try {
      return await _client.currentDirectory();
    } catch (_) {
      return _initialDirectory ?? '/';
    }
  }

  Future<void> _resetToBaseDirectory(bool explicitRoot) async {
    if (explicitRoot) {
      try {
        if (await _client.changeDirectory('/')) return;
      } catch (_) {}
    }
    final initial = _initialDirectory;
    if (initial != null && initial.isNotEmpty) {
      try {
        await _client.changeDirectory(initial);
      } catch (_) {}
    }
  }

  List<String> _splitCleanSegments(String remotePath) {
    final normalized = remotePath.replaceAll(r'\', '/');
    return normalized
        .split('/')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && s != '.' && s != '..')
        .toList();
  }

  @override
  Future<bool> changeDirectory(String remotePath) async {
    final trimmed = remotePath.trim();
    final explicitRoot = trimmed.startsWith('/') || trimmed.startsWith(r'\');
    await _resetToBaseDirectory(explicitRoot);

    final segments = _splitCleanSegments(trimmed);
    if (segments.isEmpty) return true;

    for (final seg in segments) {
      final ok = await _client.changeDirectory(seg);
      if (!ok) return false;
    }
    return true;
  }

  @override
  Future<bool> ensureRemoteDirectory(String remotePath) async {
    final trimmed = remotePath.trim();
    final explicitRoot = trimmed.startsWith('/') || trimmed.startsWith(r'\');
    await _resetToBaseDirectory(explicitRoot);

    final segments = _splitCleanSegments(trimmed);
    if (segments.isEmpty) return true;

    for (final seg in segments) {
      if (await _client.changeDirectory(seg)) continue;
      await _client.makeDirectory(seg);
      final entered = await _client.changeDirectory(seg);
      if (!entered) return false;
    }
    return true;
  }

  @override
  Future<Map<String, int?>?> listRemoteFileSizes() async {
    try {
      final entries = await _client.listDirectoryContent();
      final Map<String, int?> result = {};
      for (final entry in entries) {
        if (entry.type == FTPEntryType.file ||
            entry.type == FTPEntryType.unknown) {
          result[entry.name] = entry.size;
        }
      }
      return result;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<int?> getRemoteFileSize(String remoteName) async {
    try {
      final size = await _client.sizeFile(remoteName);
      return size >= 0 ? size : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> uploadFile(File localFile, {String? remoteName}) async {
    final targetName = (remoteName != null && remoteName.isNotEmpty)
        ? remoteName
        : p.basename(localFile.path);
    return _client.uploadFile(localFile, sRemoteName: targetName);
  }
}
