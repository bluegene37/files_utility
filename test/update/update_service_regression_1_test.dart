import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:files_utility/providers/update_provider.dart';
import 'package:files_utility/services/update/update_info.dart';
import 'package:files_utility/services/update/update_service.dart';

// Regression: ISSUE-001 — a corrupt cached release payload threw a
// FormatException straight out of checkForUpdate. UpdateProvider._check only
// has try/finally, and UpdateGate calls checkSilently() without awaiting, so
// the throw became an unhandled async error and the startup update check went
// silently dead for the rest of the 24h throttle window.
// Found by /qa on 2026-08-31
// Report: .gstack/qa-reports/qa-report-files-utility-2026-08-31.md

Map<String, dynamic> release(String tag) => {
  'tag_name': tag,
  'html_url': 'https://github.com/bluegene37/files_utility/releases/tag/$tag',
  'assets': [
    {
      'name': 'FilesUtility-x86_64-Installer.exe',
      'browser_download_url': 'https://example.com/installer.exe',
      'size': 10,
    },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late int fetchCalls;

  UpdateService service({String currentVersion = '1.0.0'}) => UpdateService(
    currentVersion: currentVersion,
    platform: UpdatePlatform.windows,
    now: () => DateTime(2026, 8, 31, 12),
    fetchRelease: (_) async {
      fetchCalls++;
      return release('v1.1.2');
    },
  );

  // Inside the throttle window, so the cached branch is the one exercised.
  void primeCache(String cached) {
    SharedPreferences.setMockInitialValues({
      'update_last_check_epoch_ms': DateTime(
        2026,
        8,
        31,
        11,
      ).millisecondsSinceEpoch,
      'update_cached_release_json': cached,
    });
  }

  setUp(() => fetchCalls = 0);

  const corruptPayloads = <String, String>{
    'truncated JSON': '{"tag_name":"v1.1.2"',
    'not JSON at all': 'not json at all',
    'empty string': '',
    'a JSON list instead of an object': '[]',
    'a JSON string instead of an object': '"v1.1.2"',
  };

  corruptPayloads.forEach((label, payload) {
    test(
      'cached release that is $label refetches instead of throwing',
      () async {
        primeCache(payload);
        final result = await service().checkForUpdate();

        expect(
          result.status,
          UpdateStatus.available,
          reason:
              'a corrupt cache must fall through to the network, not throw '
              'and not hide the pending update',
        );
        expect(result.info!.version.toString(), '1.1.2');
        expect(fetchCalls, 1, reason: 'the bad cache should be refreshed');
      },
    );
  });

  test('the refetch overwrites the corrupt cache so it self-heals', () async {
    primeCache('{"tag_name":"v1.1.2"');
    await service().checkForUpdate();

    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('update_cached_release_json');
    expect(cached, isNotNull);
    expect(
      cached,
      contains('v1.1.2'),
      reason: 'the corrupt payload must be replaced, not left in place',
    );
  });

  test('a valid cache is still served without hitting the network', () async {
    primeCache('{"tag_name":"v1.1.2","html_url":"h","assets":[]}');
    final result = await service().checkForUpdate();

    expect(result.status, UpdateStatus.available);
    expect(fetchCalls, 0, reason: 'the throttle must still hold for good data');
  });

  test('UpdateProvider.checkSilently survives a corrupt cache', () async {
    primeCache('not json at all');
    final provider = UpdateProvider(service: service());

    await expectLater(provider.checkSilently(), completes);
    expect(provider.isChecking, isFalse);
    expect(provider.availableUpdate, isNotNull);
  });
}
