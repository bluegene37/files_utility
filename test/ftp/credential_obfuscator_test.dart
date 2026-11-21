// Gene - Nov, 21, 2026: Unit tests for CredentialObfuscator encode/decode/redact behavior.
import 'package:flutter_test/flutter_test.dart';
import 'package:files_utility/services/credential_obfuscator.dart';

void main() {
  group('CredentialObfuscator', () {
    test('round-trips ASCII, symbols, and Unicode passwords', () {
      const secrets = [
        'simplePass',
        'P@ssw0rd!#\$%^&*()_+-=[]{}|;:",.<>/?',
        'kaffee-crème-🔐-2026',
      ];

      for (final secret in secrets) {
        final encoded = CredentialObfuscator.encode(
          secret,
          profileId: 'prof_1',
        );
        expect(encoded, startsWith('v1:'));
        expect(encoded, isNot(contains(secret)));
        final decoded = CredentialObfuscator.decode(
          encoded,
          profileId: 'prof_1',
        );
        expect(decoded, secret);
      }
    });

    test('uses a random salt so repeated encodes differ', () {
      final first = CredentialObfuscator.encode(
        'test_pass_123',
        profileId: 'prof_1',
      );
      final second = CredentialObfuscator.encode(
        'test_pass_123',
        profileId: 'prof_1',
      );
      expect(first, isNot(equals(second)));
      expect(
        CredentialObfuscator.decode(first, profileId: 'prof_1'),
        'test_pass_123',
      );
      expect(
        CredentialObfuscator.decode(second, profileId: 'prof_1'),
        'test_pass_123',
      );
    });

    test('binds encoded value to profileId', () {
      final encoded = CredentialObfuscator.encode(
        'secret_value_99',
        profileId: 'profile_alpha',
      );
      expect(
        CredentialObfuscator.decode(encoded, profileId: 'profile_beta'),
        isNot(equals('secret_value_99')),
      );
    });

    test('handles empty, malformed, and legacy unprefixed strings safely', () {
      expect(CredentialObfuscator.encode('', profileId: 'default'), '');
      expect(CredentialObfuscator.decode('', profileId: 'default'), '');
      expect(
        CredentialObfuscator.decode('v1:not-valid-base64!!!', profileId: 'p1'),
        '',
      );
      expect(CredentialObfuscator.decode('v1:AA==', profileId: 'p1'), '');
      expect(
        CredentialObfuscator.decode('legacy_plain', profileId: 'p1'),
        'legacy_plain',
      );
    });

    test('redact replaces non-empty secrets and ignores empty/null secrets', () {
      expect(
        CredentialObfuscator.redact(
          'Login failed for user with test_pass_123 at host (test_pass_123)',
          'test_pass_123',
        ),
        'Login failed for user with *** at host (***)',
      );
      expect(
        CredentialObfuscator.redact('Plain message', ''),
        'Plain message',
      );
      expect(
        CredentialObfuscator.redact('Plain message', null),
        'Plain message',
      );
    });
  });
}
