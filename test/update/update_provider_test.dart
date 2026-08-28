import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:files_utility/providers/update_provider.dart';
import 'package:files_utility/services/update/update_info.dart';
import 'package:files_utility/services/update/update_service.dart';

Map<String, dynamic> release(String tag) => {
  'tag_name': tag,
  'html_url': 'https://example.com/releases/$tag',
  'assets': <dynamic>[],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  UpdateService service({String latestTag = 'v1.1.0', Object? fetchError}) {
    return UpdateService(
      currentVersion: '1.0.0',
      platform: UpdatePlatform.macos,
      fetchRelease: (_) async {
        if (fetchError != null) throw fetchError;
        return release(latestTag);
      },
    );
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('silent check exposes an available update and notifies', () async {
    final provider = UpdateProvider(service: service());
    var notified = 0;
    provider.addListener(() => notified++);

    await provider.checkSilently();

    expect(provider.availableUpdate, isNotNull);
    expect(provider.availableUpdate!.version.toString(), '1.1.0');
    expect(notified, greaterThan(0));
  });

  test('silent check stays quiet when up to date', () async {
    final provider = UpdateProvider(service: service(latestTag: 'v1.0.0'));
    await provider.checkSilently();
    expect(provider.availableUpdate, isNull);
    expect(provider.lastResult!.status, UpdateStatus.upToDate);
  });

  test('silent check swallows failures without exposing an update', () async {
    final provider = UpdateProvider(
      service: service(fetchError: Exception('offline')),
    );
    await provider.checkSilently();
    expect(provider.availableUpdate, isNull);
    expect(provider.lastResult!.status, UpdateStatus.failed);
  });

  test('manual check resurfaces a skipped version', () async {
    final s = service();
    final provider = UpdateProvider(service: s);
    await provider.checkSilently();
    await provider.skipAvailableVersion();
    expect(provider.availableUpdate, isNull);

    // Automatic checks respect the skip...
    await provider.checkSilently();
    expect(provider.availableUpdate, isNull);

    // ...but an explicit user-triggered check shows it again.
    await provider.checkManually();
    expect(provider.availableUpdate, isNotNull);
  });

  test('dismiss hides the update for this session only', () async {
    final provider = UpdateProvider(service: service());
    await provider.checkSilently();
    provider.dismiss();
    expect(provider.availableUpdate, isNull);
    // Not persisted as skipped: a fresh silent check surfaces it again.
    await provider.checkManually();
    expect(provider.availableUpdate, isNotNull);
  });

  test('isChecking toggles during a check', () async {
    final provider = UpdateProvider(service: service());
    final future = provider.checkManually();
    expect(provider.isChecking, isTrue);
    await future;
    expect(provider.isChecking, isFalse);
  });
}
