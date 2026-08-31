import 'dart:io';

import 'package:files_utility/app_info.dart';
import 'package:flutter_test/flutter_test.dart';

/// The app version lives in three hand-edited places: `version:` in
/// pubspec.yaml, `msix_config.msix_version`, and [AppInfo.appVersion].
/// Only [AppInfo.appVersion] is compiled into the binary and compared
/// against the latest GitHub release tag by `UpdateService`.
///
/// When it drifts below the released tag, the shipped build reports the old
/// version forever: it downloads the update, installs it, restarts, still
/// reports the old version, and offers the same update again. That is what
/// happened to v1.1.1, which shipped `appVersion = '1.1.0'`.
///
/// The release workflow runs `flutter test` before packaging, so these
/// assertions make a drifted release impossible to build.
void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();

  String pubspecField(String key) {
    final match = RegExp(
      '^\\s*$key:\\s*"?([^"\\s#]+)"?',
      multiLine: true,
    ).firstMatch(pubspec);
    if (match == null) {
      throw StateError('pubspec.yaml has no `$key:` field');
    }
    return match.group(1)!;
  }

  // pubspec versions carry build metadata (`1.2.3+4`); the release version is
  // the part before the `+`.
  final pubspecVersion = pubspecField('version').split('+').first;

  test('AppInfo.appVersion matches the pubspec version', () {
    expect(
      AppInfo.appVersion,
      pubspecVersion,
      reason:
          'lib/app_info.dart says ${AppInfo.appVersion} but pubspec.yaml says '
          '$pubspecVersion. AppInfo.appVersion is what the updater compares '
          'against the release tag, so shipping this build would loop: '
          'update, install, restart, offer the same update again.',
    );
  });

  test('msix_version matches the pubspec version', () {
    expect(
      pubspecField('msix_version'),
      '$pubspecVersion.0',
      reason:
          'msix_config.msix_version must be the pubspec version plus a fourth '
          'segment, or Windows treats the package as unchanged.',
    );
  });

  test('a release tag build matches the pubspec version', () {
    final env = Platform.environment;
    if (env['GITHUB_REF_TYPE'] != 'tag') return; // local run, nothing to check.
    final tag = env['GITHUB_REF_NAME'];
    expect(
      tag,
      'v$pubspecVersion',
      reason:
          'Tag $tag is being released from a tree whose version is '
          '$pubspecVersion. Bump pubspec.yaml, msix_version, and '
          'AppInfo.appVersion before tagging.',
    );
  });
}
