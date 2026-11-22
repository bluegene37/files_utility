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
      },
    );
  });
}
