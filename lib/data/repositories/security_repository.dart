import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as legacy_crypto;
import 'package:cryptography/cryptography.dart';
import 'package:sqflite_common/utils/utils.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/app_database.dart';
import '../../core/session/operator_session.dart';

class AppUser {
  const AppUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.role,
    required this.active,
    required this.failedAttempts,
    this.lockedUntil,
  });

  final String id;
  final String username;
  final String displayName;
  final String role;
  final bool active;
  final int failedAttempts;
  final DateTime? lockedUntil;

  String get roleLabel => role == 'admin' ? 'Administrateur' : 'Gestionnaire';

  factory AppUser.fromMap(Map<String, Object?> map) => AppUser(
        id: map['id'] as String,
        username: map['username'] as String,
        displayName: map['display_name'] as String,
        role: map['role'] as String,
        active: (map['active'] as int? ?? 0) == 1,
        failedAttempts: map['failed_attempts'] as int? ?? 0,
        lockedUntil: map['locked_until'] == null ? null : DateTime.tryParse(map['locked_until'] as String),
      );
}

class LoginResult {
  const LoginResult._({required this.success, this.user, this.message, this.lockedUntil});
  final bool success;
  final AppUser? user;
  final String? message;
  final DateTime? lockedUntil;

  factory LoginResult.success(AppUser user) => LoginResult._(success: true, user: user);
  factory LoginResult.failure(String message, {DateTime? lockedUntil}) => LoginResult._(success: false, message: message, lockedUntil: lockedUntil);
}

class SecurityRepository {
  SecurityRepository(this._database);
  final AppDatabase _database;
  static const _uuid = Uuid();
  static const _roles = {'admin', 'manager'};

  Future<List<AppUser>> users({bool activeOnly = false}) async {
    final rows = await _database.db.query(
      'app_users',
      where: activeOnly ? 'active = 1' : null,
      orderBy: 'display_name COLLATE NOCASE',
    );
    return rows.map(AppUser.fromMap).toList();
  }

  Future<bool> hasUsers() async {
    final count = firstIntValue(await _database.db.rawQuery('SELECT COUNT(*) FROM app_users WHERE active = 1')) ?? 0;
    return count > 0;
  }

  Future<AppUser?> currentUser() async {
    final id = OperatorSession.userId;
    if (id == null) return null;
    final rows = await _database.db.query('app_users', where: 'id = ? AND active = 1', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : AppUser.fromMap(rows.first);
  }

  Future<String> createUser({
    required String username,
    required String displayName,
    required String role,
    required String pin,
    bool allowAdminProvisioning = false,
  }) async {
    final login = username.trim().toLowerCase();
    final name = displayName.trim();
    if (login.length < 3) throw ArgumentError('L’identifiant doit contenir au moins 3 caractères.');
    if (name.isEmpty) throw ArgumentError('Le nom de l’utilisateur est obligatoire.');
    _validateSecret(pin);
    final normalizedRole = _roles.contains(role) ? role : 'manager';

    final existingUsers = await hasUsers();
    if (existingUsers &&
        !allowAdminProvisioning &&
        !OperatorSession.hasPermission('security.manage_users')) {
      throw StateError(
        'La création d’un autre compte local est réservée à l’administrateur.',
      );
    }

    final duplicate = firstIntValue(await _database.db.rawQuery(
          'SELECT COUNT(*) FROM app_users WHERE lower(username) = lower(?)',
          [login],
        )) ??
        0;
    if (duplicate > 0) throw StateError('Cet identifiant existe déjà.');

    final salt = _randomSalt();
    final now = DateTime.now().toIso8601String();
    final id = _uuid.v4();
    await _database.db.transaction((txn) async {
      await txn.insert('app_users', {
        'id': id,
        'username': login,
        'display_name': name,
        'role': normalizedRole,
        'pin_hash': await _pbkdf2(pin, salt),
        'pin_salt': salt,
        'pin_algorithm': 'pbkdf2-sha256',
        'pin_iterations': 120000,
        'active': 1,
        'failed_attempts': 0,
        'locked_until': null,
        'created_at': now,
        'updated_at': now,
      });
      await txn.insert('audit_log', {
        'entity_type': 'app_user',
        'entity_id': id,
        'action': 'create',
        'new_value': '$login/$normalizedRole',
        'operator_name': existingUsers ? OperatorSession.current : name,
        'operator_id': existingUsers ? OperatorSession.userId : id,
        'operator_role': existingUsers ? OperatorSession.role : normalizedRole,
        'created_at': now,
      });
    });
    return id;
  }

  Future<LoginResult> authenticate(String userId, String pin) async {
    final rows = await _database.db.query('app_users', where: 'id = ? AND active = 1', whereArgs: [userId], limit: 1);
    if (rows.isEmpty) return LoginResult.failure('Compte introuvable ou désactivé.');
    final row = rows.first;
    final user = AppUser.fromMap(row);
    final now = DateTime.now();
    if (user.lockedUntil != null && user.lockedUntil!.isAfter(now)) {
      return LoginResult.failure('Compte temporairement verrouillé.', lockedUntil: user.lockedUntil);
    }

    final expected = row['pin_hash'] as String;
    final salt = row['pin_salt'] as String;
    final algorithm = (row['pin_algorithm'] as String?) ?? 'sha256-legacy';
    final computed = algorithm == 'pbkdf2-sha256'
        ? await _pbkdf2(pin, salt, iterations: row['pin_iterations'] as int? ?? 120000)
        : _legacyHash(pin, salt);
    if (computed != expected) {
      final attempts = user.failedAttempts + 1;
      DateTime? lockedUntil;
      if (attempts >= 5) {
        final extraBlocks = ((attempts - 5) ~/ 3).clamp(0, 5);
        final seconds = 30 * (1 << extraBlocks);
        lockedUntil = now.add(Duration(seconds: seconds));
      }
      await _database.db.update(
        'app_users',
        {
          'failed_attempts': attempts,
          'locked_until': lockedUntil?.toIso8601String(),
          'updated_at': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [userId],
      );
      return LoginResult.failure(
        lockedUntil == null ? 'PIN incorrect ($attempts/5).' : 'Trop de tentatives. Compte temporairement verrouillé.',
        lockedUntil: lockedUntil,
      );
    }

    final successValues = <String, Object?>{
      'failed_attempts': 0,
      'locked_until': null,
      'updated_at': now.toIso8601String(),
    };
    if (algorithm != 'pbkdf2-sha256') {
      successValues['pin_hash'] = await _pbkdf2(pin, salt);
      successValues['pin_algorithm'] = 'pbkdf2-sha256';
      successValues['pin_iterations'] = 120000;
    }
    await _database.db.update('app_users', successValues, where: 'id = ?', whereArgs: [userId]);
    final refreshed = AppUser(
      id: user.id,
      username: user.username,
      displayName: user.displayName,
      role: user.role,
      active: user.active,
      failedAttempts: 0,
    );
    final tenantRows = await _database.db.query('cloud_tenant_cache', where: 'active=1', orderBy: 'updated_at DESC', limit: 1);
    final tenant = tenantRows.isEmpty ? null : tenantRows.first;
    OperatorSession.authenticate(
      userId: refreshed.id,
      cloudUserId: tenant?['cloud_user_id'] as String?,
      displayName: refreshed.displayName,
      role: refreshed.role,
      organizationId: tenant?['organization_id'] as String?,
      organizationCode: tenant?['organization_code'] as String?,
      organizationName: tenant?['organization_name'] as String?,
    );
    return LoginResult.success(refreshed);
  }

  Future<AppUser?> authorizeSensitiveAction({required String username, required String pin, required String action, String? entityId}) async {
    final login = username.trim().toLowerCase();
    final rows = await _database.db.query('app_users', where: 'lower(username) = lower(?) AND active = 1', whereArgs: [login], limit: 1);
    if (rows.isEmpty) return null;
    final row = rows.first;
    final user = AppUser.fromMap(row);
    final activeCount = firstIntValue(await _database.db.rawQuery('SELECT COUNT(*) FROM app_users WHERE active = 1')) ?? 0;
    if (activeCount > 1 && user.id == OperatorSession.userId) return null;
    final now = DateTime.now();
    if (user.lockedUntil != null && user.lockedUntil!.isAfter(now)) return null;
    final salt = row['pin_salt'] as String;
    final algorithm = (row['pin_algorithm'] as String?) ?? 'sha256-legacy';
    final expected = row['pin_hash'] as String;
    final computed = algorithm == 'pbkdf2-sha256'
        ? await _pbkdf2(pin, salt, iterations: row['pin_iterations'] as int? ?? 120000)
        : _legacyHash(pin, salt);
    if (computed != expected) return null;
    await _database.db.insert('audit_log', {
      'entity_type': 'sensitive_authorization',
      'entity_id': entityId ?? action,
      'action': action,
      'new_value': 'Autorisé par ${user.displayName}',
      'operator_name': user.displayName,
      'operator_id': user.id,
      'operator_role': user.role,
      'created_at': now.toIso8601String(),
    });
    return user;
  }

  Future<void> resetPin({required String userId, required String newPin, bool allowAdminProvisioning = false}) async {
    if (!allowAdminProvisioning && OperatorSession.isAuthenticated && !OperatorSession.hasPermission('security.manage_users') && OperatorSession.userId != userId) {
      throw StateError('Seul l’administrateur peut réinitialiser le mot de passe d’un autre compte.');
    }
    _validateSecret(newPin);
    final salt = _randomSalt();
    final now = DateTime.now().toIso8601String();
    await _database.db.transaction((txn) async {
      await txn.update('app_users', {
        'pin_hash': await _pbkdf2(newPin, salt),
        'pin_salt': salt,
        'pin_algorithm': 'pbkdf2-sha256',
        'pin_iterations': 120000,
        'failed_attempts': 0,
        'locked_until': null,
        'updated_at': now,
      }, where: 'id = ?', whereArgs: [userId]);
      await txn.insert('audit_log', {
        'entity_type': 'app_user',
        'entity_id': userId,
        'action': 'pin_reset',
        'operator_name': OperatorSession.current,
        'operator_id': OperatorSession.userId,
        'operator_role': OperatorSession.role,
        'created_at': now,
      });
    });
  }

  Future<void> setUserActive(String userId, bool active) async {
    if (!OperatorSession.hasPermission('security.manage_users')) throw StateError('Réservé à l’administrateur.');
    if (OperatorSession.userId == userId && !active) throw StateError('Vous ne pouvez pas désactiver votre propre compte.');
    final rows = await _database.db.query('app_users', where: 'id = ?', whereArgs: [userId], limit: 1);
    if (rows.isEmpty) throw StateError('Utilisateur introuvable.');
    final now = DateTime.now().toIso8601String();
    await _database.db.transaction((txn) async {
      await txn.update('app_users', {'active': active ? 1 : 0, 'updated_at': now}, where: 'id = ?', whereArgs: [userId]);
      await txn.insert('audit_log', {
        'entity_type': 'app_user', 'entity_id': userId, 'action': active ? 'activate' : 'deactivate',
        'operator_name': OperatorSession.current, 'operator_id': OperatorSession.userId,
        'operator_role': OperatorSession.role, 'created_at': now,
      });
    });
  }

  Future<void> updateUserRole(String userId, String role) async {
    if (!OperatorSession.hasPermission('security.manage_users')) throw StateError('Réservé à l’administrateur.');
    final normalizedRole = _roles.contains(role) ? role : 'manager';
    await _database.db.update('app_users', {'role': normalizedRole, 'updated_at': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [userId]);
  }

  void require(String permission) {
    if (!OperatorSession.hasPermission(permission)) {
      throw StateError('Vous n’avez pas l’autorisation requise pour cette opération.');
    }
  }

  // API legacy conservée uniquement pour la migration de l'interface.
  Future<bool> hasPin() => hasUsers();
  Future<String> operatorName() async => OperatorSession.current;
  Future<void> setOperatorName(String name) async => throw StateError('Le nom de l’opérateur provient désormais du compte authentifié.');
  Future<void> setPin(String pin) async {
    final usersList = await users(activeOnly: true);
    if (usersList.isEmpty) {
      await createUser(username: 'gestionnaire', displayName: 'Gestionnaire', role: 'manager', pin: pin, allowAdminProvisioning: true);
    } else {
      await resetPin(userId: usersList.first.id, newPin: pin);
    }
  }
  Future<void> clearPin() async => throw StateError('Désactivez les comptes individuellement au lieu de retirer la sécurité globale.');
  Future<bool> verifyPin(String pin) async {
    final usersList = await users(activeOnly: true);
    if (usersList.length != 1) return false;
    return (await authenticate(usersList.first.id, pin)).success;
  }

  void _validateSecret(String pin) {
    final legacyPin = RegExp(r'^\d{4,8}$').hasMatch(pin);
    final strongPassword = pin.length >= 8 && pin.length <= 64;
    if (!legacyPin && !strongPassword) {
      throw ArgumentError('Le mot de passe doit contenir au moins 8 caractères (les anciens PIN de 4 à 8 chiffres restent acceptés).');
    }
  }

  String _legacyHash(String pin, String salt) => legacy_crypto.sha256.convert(utf8.encode('$salt:$pin')).toString();

  Future<String> _pbkdf2(String pin, String salt, {int iterations = 120000}) async {
    final algorithm = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);
    final key = await algorithm.deriveKeyFromPassword(password: pin, nonce: utf8.encode(salt));
    final bytes = await key.extractBytes();
    return base64UrlEncode(bytes);
  }

  Future<String> generateRecoveryCode(String userId) async {
    final code = List<int>.generate(12, (_) => Random.secure().nextInt(10)).join();
    final salt = _randomSalt();
    final hash = await _pbkdf2(code, salt, iterations: 60000);
    await _database.db.update('app_users', {
      'recovery_code_hash': hash,
      'recovery_code_salt': salt,
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id=?', whereArgs: [userId]);
    return code;
  }

  Future<void> recoverPin({required String userId, required String recoveryCode, required String newPin}) async {
    _validateSecret(newPin);
    final rows = await _database.db.query('app_users', where: 'id=?', whereArgs: [userId], limit: 1);
    if (rows.isEmpty) throw StateError('Gestionnaire introuvable.');
    final hash = rows.first['recovery_code_hash'] as String?;
    final salt = rows.first['recovery_code_salt'] as String?;
    if (hash == null || salt == null) throw StateError('Aucun code de récupération n’a été généré pour ce compte.');
    if (await _pbkdf2(recoveryCode.trim(), salt, iterations: 60000) != hash) throw StateError('Code de récupération invalide.');
    await resetPin(userId: userId, newPin: newPin);
    await _database.db.update('app_users', {'recovery_code_hash': null, 'recovery_code_salt': null}, where: 'id=?', whereArgs: [userId]);
  }

  String _randomSalt() {
    final random = Random.secure();
    return List<int>.generate(16, (_) => random.nextInt(256)).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
