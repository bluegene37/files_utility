// Gene - Nov, 23, 2026: Unit tests for FtpIniImporter parsing and FtpFilesProvider.applyImportedConfig.
import 'package:flutter_test/flutter_test.dart';
import 'package:files_utility/providers/ftp_files_provider.dart';
import 'package:files_utility/services/ftp_ini_importer.dart';
import 'package:files_utility/services/ftp_transfer_service.dart';

void main() {
  group('FtpIniImporter', () {
    test('parses .env credentials and config.ini multi-source settings', () {
      const env = '''
# FTP SECRETS
FTP_ADDRESS=192.0.2.70
FTP_USERNAME="myflouser" # inline comment ignored
FTP_PASSWORD='s#cret!Pass=1'
''';

      const ini = '''
; FTP Automation config
[ftp]
FTP_PORT = 21
FTP_DAYS_AGO = 1
FTP_USE_TLS = false
FTP_TIMEOUT = 45
FTP_RETRY_COUNT = 4
FTP_RETRY_DELAY = 10
FTP_DRY_RUN = true

[logging]
LOG_DIR = C:\\temp
LOG_KEEP_DAYS = 14

; [source.Testing]
; LOCAL_PATH = C:\\temp\\ftpTest
; SUBFOLDERS = test, test2

[source.DBBackup]
LOCAL_PATH = \\\\ENETSNAS1\\SQLBackups\\2019-Full
SUBFOLDERS = ETS-East
FTP_DEST = DB_BackUp

[source.JobFiles]
LOCAL_PATH = \\\\myflofs1\\Apps4\\myFloETS-East
SUBFOLDERS = JobImages, JobDocuments, JobInvoice
FTP_DEST =
''';

      final result = FtpIniImporter.parse(iniContent: ini, envContent: env);

      expect(result.isEmpty, isFalse);
      expect(result.host, '192.0.2.70');
      expect(result.username, 'myflouser');
      expect(result.password, 's#cret!Pass=1');
      expect(result.port, 21);
      expect(result.protocol, FtpProtocol.ftp);
      expect(result.daysAgo, 1);
      expect(result.timeoutSeconds, 45);
      expect(result.retryCount, 4);
      expect(result.retryDelaySeconds, 10);
      expect(result.dryRun, isTrue);
      expect(result.logKeepDays, 14);

      // Commented-out [source.Testing] must be excluded.
      expect(result.sources, hasLength(2));
      expect(result.sources[0].name, 'DBBackup');
      expect(result.sources[0].localPath, r'\\ENETSNAS1\SQLBackups\2019-Full');
      expect(result.sources[0].subfolders, 'ETS-East');
      expect(result.sources[0].ftpDest, 'DB_BackUp');
      expect(result.sources[0].runOrder, 1);
      expect(result.sources[0].enabled, isTrue);

      expect(result.sources[1].name, 'JobFiles');
      expect(
        result.sources[1].subfolders,
        'JobImages, JobDocuments, JobInvoice',
      );
      expect(result.sources[1].ftpDest, isEmpty);
      expect(result.sources[1].runOrder, 2);
    });

    test('maps FTP_USE_TLS with port 21 to FTPES and port 990 to FTPS', () {
      final explicitTls = FtpIniImporter.parse(
        iniContent: '[ftp]\nFTP_PORT = 21\nFTP_USE_TLS = true\n',
      );
      expect(explicitTls.protocol, FtpProtocol.ftpes);
      expect(explicitTls.port, 21);

      final implicitTls = FtpIniImporter.parse(
        iniContent: '[ftp]\nFTP_PORT = 990\nFTP_USE_TLS = true\n',
      );
      expect(implicitTls.protocol, FtpProtocol.ftps);
      expect(implicitTls.port, 990);
    });

    test(
      'applyImportedConfig updates provider safely without leaking password',
      () {
        final provider = FtpFilesProvider(persistSettings: false);
        addTearDown(provider.dispose);

        final multi = FtpIniImporter.parse(
          envContent:
              'FTP_ADDRESS=ftp.example.com\nFTP_USERNAME=u1\nFTP_PASSWORD=top_secret_pw\n',
          iniContent: '''
[ftp]
FTP_PORT = 2121
FTP_DAYS_AGO = 5
FTP_USE_TLS = true
[logging]
LOG_KEEP_DAYS = 7
[source.One]
LOCAL_PATH = /tmp/one
SUBFOLDERS =
FTP_DEST = RemoteOne
''',
        );

        final versionBefore = provider.settingsVersion;
        final summary = provider.applyImportedConfig(multi);

        expect(provider.settingsVersion, versionBefore + 1);
        expect(provider.host, 'ftp.example.com');
        expect(provider.port, 2121);
        expect(provider.protocol, FtpProtocol.ftpes);
        expect(provider.username, 'u1');
        expect(provider.password, 'top_secret_pw');
        expect(provider.dateMode, FtpDateMode.daysAgo);
        expect(provider.daysAgo, 5);
        expect(provider.logKeepDays, 7);
        expect(provider.useMultipleSources, isFalse);
        expect(provider.sourcePath, '/tmp/one');
        expect(provider.remoteDirectory, 'RemoteOne');
        // Blank SUBFOLDERS sets includeSubfolders = true to match script guide.
        expect(provider.includeSubfolders, isTrue);
        expect(summary, isNot(contains('top_secret_pw')));
        expect(provider.logs.any((l) => l.contains('top_secret_pw')), isFalse);

        // Now apply a 2-source config with FTP_DAYS_AGO = 0 -> today & multiple sources.
        final twoSources = FtpIniImporter.parse(
          iniContent: '''
[ftp]
FTP_DAYS_AGO = 0
[source.A]
LOCAL_PATH = /tmp/a
SUBFOLDERS = SubA
[source.B]
LOCAL_PATH = /tmp/b
SUBFOLDERS = SubB
''',
        );
        provider.applyImportedConfig(twoSources);
        expect(provider.dateMode, FtpDateMode.today);
        expect(provider.useMultipleSources, isTrue);
        expect(provider.uploadSources, hasLength(2));
      },
    );
  });
}
