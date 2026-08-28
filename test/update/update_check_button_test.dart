import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:files_utility/providers/update_provider.dart';
import 'package:files_utility/services/update/update_info.dart';
import 'package:files_utility/services/update/update_service.dart';
import 'package:files_utility/widgets/update_check_button.dart';

UpdateProvider providerWith({String latestTag = 'v1.0.0', Object? error}) {
  return UpdateProvider(
    service: UpdateService(
      currentVersion: '1.0.0',
      platform: UpdatePlatform.macos,
      fetchRelease: (_) async {
        if (error != null) throw error;
        return {
          'tag_name': latestTag,
          'html_url': 'https://example.com/releases/$latestTag',
          'assets': <dynamic>[],
        };
      },
    ),
  );
}

Widget host(UpdateProvider provider) {
  return ChangeNotifierProvider.value(
    value: provider,
    child: const MaterialApp(
      home: Scaffold(body: Center(child: UpdateCheckButton())),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('reports up to date via snackbar', (tester) async {
    await tester.pumpWidget(host(providerWith()));
    await tester.tap(find.byType(UpdateCheckButton));
    await tester.pumpAndSettle();

    expect(find.textContaining('up to date'), findsOneWidget);
  });

  testWidgets('reports failure via snackbar', (tester) async {
    await tester.pumpWidget(host(providerWith(error: Exception('offline'))));
    await tester.tap(find.byType(UpdateCheckButton));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not check for updates'), findsOneWidget);
  });

  testWidgets('stays quiet when an update is found (dialog handles it)', (
    tester,
  ) async {
    await tester.pumpWidget(host(providerWith(latestTag: 'v2.0.0')));
    await tester.tap(find.byType(UpdateCheckButton));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
  });
}
