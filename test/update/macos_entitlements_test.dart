import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The macOS app runs inside the App Sandbox
/// (`com.apple.security.app-sandbox`). Under the sandbox every outbound
/// connection needs `com.apple.security.network.client`; without it
/// `connect()` fails with EPERM, Dart surfaces a SocketException, and the
/// update check reports "Could not check for updates. Are you online?" even
/// on a healthy network. Both build configurations must grant it.
void main() {
  const entitlementFiles = [
    'macos/Runner/DebugProfile.entitlements',
    'macos/Runner/Release.entitlements',
  ];

  for (final path in entitlementFiles) {
    test('$path allows outbound network (sandboxed update check)', () {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path is missing');

      final xml = file.readAsStringSync();
      if (!xml.contains('com.apple.security.app-sandbox')) {
        // No sandbox, no entitlement needed.
        return;
      }

      final clientKey = RegExp(
        r'<key>com\.apple\.security\.network\.client</key>\s*<true\s*/>',
      );
      expect(
        clientKey.hasMatch(xml),
        isTrue,
        reason:
            'Sandboxed build without com.apple.security.network.client: '
            'the GitHub update check will always fail as if offline.',
      );
    });
  }
}
