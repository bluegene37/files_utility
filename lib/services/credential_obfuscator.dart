// Gene - Nov, 21, 2026: Pure-Dart salted credential obfuscation for per-profile SQLite persistence and log redaction.
import 'dart:convert';
import 'dart:math';

class CredentialObfuscator {
  CredentialObfuscator._();

  static const String _prefix = 'v1:';
  static const int _saltLength = 16;
  static const String _pepper = 'FilesUtility_LocalCredential_2026_v1';

  static String encode(String plainText, {required String profileId}) {
    if (plainText.isEmpty) return '';

    final rng = Random.secure();
    final salt = List<int>.generate(_saltLength, (_) => rng.nextInt(256));
    final plainBytes = utf8.encode(plainText);
    final stream = _deriveKeystream(salt, profileId, plainBytes.length);

    final encrypted = List<int>.generate(
      plainBytes.length,
      (i) => plainBytes[i] ^ stream[i],
    );
    final combined = <int>[...salt, ...encrypted];
    return '$_prefix${base64Encode(combined)}';
  }

  static String decode(String stored, {required String profileId}) {
    if (stored.isEmpty) return '';
    if (!stored.startsWith(_prefix)) return stored;

    try {
      final raw = base64Decode(stored.substring(_prefix.length));
      if (raw.length < _saltLength) return '';

      final salt = raw.sublist(0, _saltLength);
      final encrypted = raw.sublist(_saltLength);
      if (encrypted.isEmpty) return '';

      final stream = _deriveKeystream(salt, profileId, encrypted.length);
      final plainBytes = List<int>.generate(
        encrypted.length,
        (i) => encrypted[i] ^ stream[i],
      );
      return utf8.decode(plainBytes);
    } catch (_) {
      return '';
    }
  }

  static String redact(String text, String? secret) {
    if (secret == null || secret.isEmpty) return text;
    return text.replaceAll(secret, '***');
  }

  static List<int> _deriveKeystream(
    List<int> salt,
    String profileId,
    int length,
  ) {
    final seedBytes = <int>[
      ...utf8.encode(_pepper),
      0x1F,
      ...utf8.encode(profileId),
      0x1E,
      ...salt,
    ];

    final state = List<int>.generate(32, (i) {
      final b = seedBytes[i % seedBytes.length];
      return (b + i * 31) & 0xFF;
    });

    // Warm up mixing state across full seed material.
    for (int round = 0; round < 3; round++) {
      for (int i = 0; i < seedBytes.length; i++) {
        final idx = i & 31;
        final prev = state[(idx - 1) & 31];
        final mixed = (state[idx] + seedBytes[i] + prev + round * 17) & 0xFF;
        state[idx] = ((mixed << 3) | (mixed >> 5)) & 0xFF;
      }
    }

    final output = List<int>.filled(length, 0);
    int acc = 0xA5;
    for (int i = 0; i < length; i++) {
      final idx = i & 31;
      final nextIdx = (i + 13) & 31;
      acc = (acc + state[idx] + (i & 0xFF) + 0x5A) & 0xFF;
      state[idx] = ((state[idx] ^ acc) + state[nextIdx]) & 0xFF;
      output[i] = (state[idx] ^ state[nextIdx] ^ acc) & 0xFF;
    }
    return output;
  }
}
