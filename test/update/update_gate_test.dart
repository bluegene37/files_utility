import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:files_utility/providers/update_provider.dart';
import 'package:files_utility/services/update/update_info.dart';
import 'package:files_utility/services/update/update_service.dart';
import 'package:files_utility/widgets/update_gate.dart';

Map<String, dynamic> release(String tag) => {
  'tag_name': tag,
  'html_url': 'https://example.com/releases/$tag',
  'assets': <dynamic>[],
};

UpdateProvider providerWith({String latestTag = 'v1.1.0'}) {
  return UpdateProvider(
    service: UpdateService(
      currentVersion: '1.0.0',
      platform: UpdatePlatform.macos,
      fetchRelease: (_) async => release(latestTag),
    ),
  );
}

Widget host(UpdateProvider provider) {
  return ChangeNotifierProvider.value(
    value: provider,
    child: const MaterialApp(
      home: UpdateGate(child: Scaffold(body: Text('app body'))),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows the update dialog when a newer release exists', (
    tester,
  ) async {
    await tester.pumpWidget(host(providerWith()));
    await tester.pumpAndSettle();

    expect(find.text('app body'), findsOneWidget);
    expect(find.text('Update Available'), findsOneWidget);
    expect(find.textContaining('1.1.0'), findsWidgets);
  });

  testWidgets('shows nothing when up to date', (tester) async {
    await tester.pumpWidget(host(providerWith(latestTag: 'v1.0.0')));
    await tester.pumpAndSettle();

    expect(find.text('Update Available'), findsNothing);
  });

  testWidgets('Later closes the dialog for the session', (tester) async {
    final provider = providerWith();
    await tester.pumpWidget(host(provider));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();

    expect(find.text('Update Available'), findsNothing);
    expect(provider.availableUpdate, isNull);
  });

  testWidgets('Skip persists the skipped version', (tester) async {
    final provider = providerWith();
    await tester.pumpWidget(host(provider));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip this version'));
    await tester.pumpAndSettle();

    expect(find.text('Update Available'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('update_skipped_version'), '1.1.0');
  });

  testWidgets('non-Windows platforms offer Download, not silent install', (
    tester,
  ) async {
    await tester.pumpWidget(host(providerWith()));
    await tester.pumpAndSettle();

    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Install & Restart'), findsNothing);
  });
}
