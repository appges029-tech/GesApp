import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as legacy_crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/cloud/supabase_bootstrap.dart';
import '../core/cloud/supabase_config.dart';
import '../core/security/pattern_policy.dart';

class DeviceUnlockProfile {
  const DeviceUnlockProfile({required this.hasPattern, required this.biometricEnabled});
  final bool hasPattern;
  final bool biometricEnabled;
  bool get enabled => hasPattern || biometricEnabled;
}

class DeviceQuickUnlockService {
  DeviceQuickUnlockService._();
  static final instance = DeviceQuickUnlockService._();

  static const _storage = FlutterSecureStorage();
  static final _kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 180000, bits: 256);
  final _biometrics = LocalAuthentication();

  bool get isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  String _key(String organizationId, String cloudUserId) =>
      'gesapp.device.unlock.v1.${legacy_crypto.sha256.convert(utf8.encode('$organizationId:$cloudUserId'))}';

  Future<Map<String, dynamic>> _load(String orgId, String userId) async {
    if (!isAndroid || orgId.isEmpty || userId.isEmpty) return {};
    try {
      final json = await _storage.read(key: _key(orgId, userId));
      if (json == null) return {};
      final decoded = jsonDecode(json);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      // Fail closed: damaged local profile never silently authorizes an unlock.
      return {};
    }
  }

  Future<void> _write(String orgId, String userId, Map<String, dynamic> values) =>
      _storage.write(key: _key(orgId, userId), value: jsonEncode(values));

  Future<DeviceUnlockProfile> profile(String orgId, String userId) async {
    final values = await _load(orgId, userId);
    return DeviceUnlockProfile(
      hasPattern: values['hash'] is String && values['salt'] is String,
      biometricEnabled: values['biometric'] == true,
    );
  }

  static bool _validIdentity(String orgId, String userId) =>
      orgId.trim().isNotEmpty && userId.trim().isNotEmpty;

  Future<String> _hash(List<int> pattern, String base64Salt) async {
    final secret = await _kdf.deriveKeyFromPassword(
      password: PatternPolicy.normalize(pattern).join('-'),
      nonce: base64Decode(base64Salt),
    );
    return base64Encode(await secret.extractBytes());
  }

  Future<void> setPattern(String orgId, String userId, List<int> input) async {
    if (!isAndroid || !_validIdentity(orgId, userId) || !PatternPolicy.isValid(input)) {
      throw StateError('Le schéma doit comporter au moins 6 points distincts.');
    }
    final random = Random.secure();
    final salt = base64Encode(List<int>.generate(24, (_) => random.nextInt(256)));
    final values = await _load(orgId, userId);
    values['salt'] = salt;
    values['hash'] = await _hash(input, salt);
    values['attempts'] = 0;
    values.remove('locked_until');
    await _write(orgId, userId, values);
  }

  Future<bool> verifyPattern(String orgId, String userId, List<int> input) async {
    if (!isAndroid || !_validIdentity(orgId, userId)) return false;
    final values = await _load(orgId, userId);
    final saved = values['hash'];
    final salt = values['salt'];
    if (saved is! String || salt is! String) return false;
    final block = DateTime.tryParse(values['locked_until']?.toString() ?? '');
    if (block != null && DateTime.now().toUtc().isBefore(block)) {
      throw StateError('Trop de tentatives. Réessayez dans quelques minutes.');
    }
    bool valid = false;
    try {
      final candidate = await _hash(input, salt);
      final a = utf8.encode(candidate), b = utf8.encode(saved);
      if (a.length == b.length) {
        var diff = 0;
        for (var i = 0; i < a.length; i++) { diff |= a[i] ^ b[i]; }
        valid = diff == 0;
      }
    } catch (_) {
      return false;
    }
    if (valid) {
      values['attempts'] = 0;
      values.remove('locked_until');
    } else {
      final attempts = (values['attempts'] as int? ?? 0) + 1;
      values['attempts'] = attempts;
      if (attempts >= 5) {
        values['locked_until'] = DateTime.now().toUtc()
            .add(const Duration(minutes: 5)).toIso8601String();
      }
    }
    await _write(orgId, userId, values);
    return valid;
  }

  Future<bool> canUseBiometrics() async {
    if (!isAndroid) return false;
    try {
      if (!await _biometrics.canCheckBiometrics) return false;
      return (await _biometrics.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _systemBiometricPrompt() async {
    if (!await canUseBiometrics()) return false;
    try {
      return await _biometrics.authenticate(
        localizedReason: 'Déverrouiller GesApp avec la biométrie du téléphone',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> enableBiometrics(String orgId, String userId) async {
    if (!isAndroid || !_validIdentity(orgId, userId)) return false;
    if (!await _systemBiometricPrompt()) return false;
    final values = await _load(orgId, userId);
    values['biometric'] = true;
    await _write(orgId, userId, values);
    return true;
  }

  Future<bool> verifyBiometrics(String orgId, String userId) async {
    if (!isAndroid || !_validIdentity(orgId, userId)) return false;
    final values = await _load(orgId, userId);
    if (values['biometric'] != true) return false;
    return _systemBiometricPrompt();
  }

  Future<void> disableBiometrics(String orgId, String userId) async {
    final values = await _load(orgId, userId);
    values.remove('biometric');
    await _write(orgId, userId, values);
  }

  /// Password rotation invalidates all previously enrolled quick methods.
  Future<void> clearProfile(String orgId, String userId) async {
    if (!isAndroid || !_validIdentity(orgId, userId)) return;
    await _storage.delete(key: _key(orgId, userId));
  }

  Future<void> disablePattern(String orgId, String userId) async {
    final values = await _load(orgId, userId);
    values.remove('salt');
    values.remove('hash');
    values.remove('attempts');
    values.remove('locked_until');
    await _write(orgId, userId, values);
  }

  /// Enrollment/revocation requires the *current* cloud password, verified
  /// with an isolated Supabase client; never changes the app's cloud session.
  Future<bool> verifyCurrentCloudPassword(String password, String cloudUserId) async {
    if (password.isEmpty || !SupabaseBootstrap.isInitialized ||
        !SupabaseConfig.isConfigured) return false;
    final current = SupabaseBootstrap.client.auth.currentUser;
    if (current == null || current.id != cloudUserId || current.email == null) {
      return false; // No new fast-unlock settings while offline.
    }
    final verifier = SupabaseClient(
      SupabaseConfig.url, SupabaseConfig.publishableKey,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    try {
      final result = await verifier.auth.signInWithPassword(
        email: current.email!, password: password);
      return result.user?.id == cloudUserId;
    } catch (_) {
      return false;
    } finally {
      await verifier.auth.signOut();
      verifier.dispose();
    }
  }
}
