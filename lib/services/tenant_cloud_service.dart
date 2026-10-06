import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/cloud/supabase_bootstrap.dart';
import '../core/cloud/supabase_config.dart';
import '../core/db/app_database.dart';
import '../core/session/operator_session.dart';
import '../data/repositories/security_repository.dart';
import '../data/repositories/tenant_repository.dart';

class TenantCloudService {
  TenantCloudService._();
  static final instance = TenantCloudService._();

  static const _offlineLease = Duration(hours: 72);
  static const _secure = FlutterSecureStorage();
  static const _deviceKeyStorageKey = 'gesapp.cloud.device_key';

  SupabaseClient get _client => SupabaseBootstrap.client;
  final _tenantRepo = TenantRepository(AppDatabase.instance);

  bool get isConfigured =>
      SupabaseConfig.isConfigured && SupabaseBootstrap.isInitialized;
  User? get currentCloudUser => isConfigured ? _client.auth.currentUser : null;
  Session? get currentCloudSession =>
      isConfigured ? _client.auth.currentSession : null;
  Stream<AuthState> get authChanges => _client.auth.onAuthStateChange;

  Future<AuthResponse> signUpAdministratorWithEmail({
    required String email,
    required String password,
  }) async {
    if (!isConfigured) throw StateError('Supabase n’est pas configuré.');
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty || !normalizedEmail.contains('@')) {
      throw ArgumentError('Adresse e-mail invalide.');
    }
    if (password.length < 8) {
      throw ArgumentError(
        'Le mot de passe doit contenir au moins 8 caractères.',
      );
    }
    return _client.auth.signUp(
      email: normalizedEmail,
      password: password,
      emailRedirectTo: SupabaseConfig.emailConfirmationRedirect,
      data: const {'gesapp_role': 'administrator_candidate'},
    );
  }

  Future<AuthResponse> signInAdministratorWithEmail({
    required String email,
    required String password,
  }) async {
    if (!isConfigured) throw StateError('Supabase n’est pas configuré.');
    return _client.auth.signInWithPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
  }

  Future<void> resendAdministratorConfirmation(String email) async {
    if (!isConfigured) throw StateError('Supabase n’est pas configuré.');
    await _client.auth.resend(
      type: OtpType.signup,
      email: email.trim().toLowerCase(),
      emailRedirectTo: SupabaseConfig.emailConfirmationRedirect,
    );
  }

  static String managerSyntheticEmail(
    String organizationCode,
    String username,
  ) {
    String normalize(String value) => value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final org = normalize(organizationCode);
    final user = normalize(username);
    if (org.isEmpty || user.isEmpty) {
      throw ArgumentError('Code établissement et identifiant invalides.');
    }
    return 'manager.$org.$user@auth.gesapp.invalid';
  }

  Future<TenantMembershipCache> signInManager({
    required String organizationCode,
    required String username,
    required String password,
  }) async {
    if (!isConfigured) throw StateError('Supabase n’est pas configuré.');
    final email = managerSyntheticEmail(organizationCode, username);
    final response =
        await _client.auth.signInWithPassword(email: email, password: password);
    if (response.user == null) {
      throw StateError('Connexion gestionnaire impossible.');
    }
    final membership = await loadMyMembership();
    if (membership == null || !membership.isManager) {
      await _client.auth.signOut();
      throw StateError('Ce compte n’est pas un gestionnaire GesApp actif.');
    }
    if (membership.organizationCode.toUpperCase() !=
        organizationCode.trim().toUpperCase()) {
      await _client.auth.signOut();
      throw StateError('Ce compte n’appartient pas à cet établissement.');
    }
    await _cacheLocalCredential(membership, password);
    return membership;
  }

  /// Charge l'appartenance distante sans modifier les tables métier locales.
  ///
  /// La restauration cloud doit décider d'abord si ce poste reçoit un snapshot
  /// existant. Cela évite de fabriquer un faux changement local avant la
  /// première synchronisation d'un nouvel appareil.
  Future<TenantMembershipCache?> loadMyMembership() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    final result = await _client.rpc('get_my_organization');
    if (result == null) return null;
    final dynamic raw =
        result is List ? (result.isEmpty ? null : result.first) : result;
    if (raw is! Map) return null;

    final map = Map<String, dynamic>.from(raw as Map);
    final membership = TenantMembershipCache(
      organizationId: map['organization_id'].toString(),
      organizationCode: map['organization_code'].toString(),
      organizationName: map['organization_name'].toString(),
      cloudUserId: user.id,
      displayName: (map['display_name'] ??
              user.userMetadata?['full_name'] ??
              user.email ??
              'Utilisateur')
          .toString(),
      role: map['role'].toString(),
      username: map['username']?.toString(),
      active: map['active'] == true,
      mustChangePassword: map['must_change_password'] == true,
      backupSecret: map['backup_secret']?.toString(),
      updatedAt: DateTime.now(),
    );
    if (!membership.active) {
      throw StateError('Ce compte a été désactivé par l’administrateur.');
    }

    await _tenantRepo.ensureOrganizationBinding(membership.organizationId);
    await _tenantRepo.cacheMembership(membership);
    _applySession(membership);
    await _registerDeviceBestEffort(membership);
    return membership;
  }

  Future<TenantMembershipCache> bootstrapOrganization({
    required String name,
    String? preferredCode,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError(
        'Connectez d’abord le compte administrateur par e-mail.',
      );
    }
    final result = await _client.rpc('bootstrap_organization', params: {
      'p_name': name.trim(),
      'p_preferred_code':
          preferredCode?.trim().isEmpty == true ? null : preferredCode?.trim(),
      'p_display_name':
          (user.userMetadata?['full_name'] ?? user.email ?? 'Administrateur')
              .toString(),
    });
    if (result == null) {
      throw StateError('Création de l’établissement impossible.');
    }
    return (await loadMyMembership())!;
  }

  Future<List<Map<String, dynamic>>> managers() async {
    final orgId = OperatorSession.organizationId;
    if (orgId == null) return const [];
    final rows = await _client
        .from('organization_members')
        .select(
          'id,user_id,username,display_name,role,active,must_change_password,created_at',
        )
        .eq('organization_id', orgId)
        .eq('role', 'manager')
        .order('display_name');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Map<String, dynamic>> createManager({
    required String username,
    required String displayName,
    required String temporaryPassword,
  }) async {
    if (!OperatorSession.isAdmin) {
      throw StateError('Réservé à l’administrateur.');
    }
    final response = await _client.functions.invoke(
      'admin-create-manager',
      body: {
        'username': username.trim(),
        'display_name': displayName.trim(),
        'temporary_password': temporaryPassword,
      },
    );
    if (response.status < 200 || response.status >= 300) {
      throw StateError(
        'Création du gestionnaire refusée : ${response.data}',
      );
    }
    final data = Map<String, dynamic>.from(response.data as Map);
    final security = SecurityRepository(AppDatabase.instance);
    final localUsers = await security.users();
    if (!localUsers.any(
      (u) => u.username.toLowerCase() == username.trim().toLowerCase(),
    )) {
      await security.createUser(
        username: username,
        displayName: displayName,
        role: 'manager',
        pin: temporaryPassword,
        allowAdminProvisioning: true,
      );
    }
    return data;
  }

  Future<void> setManagerActive(String membershipId, bool active) async {
    if (!OperatorSession.isAdmin) {
      throw StateError('Réservé à l’administrateur.');
    }

    final targetRows = await _client
        .from('organization_members')
        .select('username')
        .eq('id', membershipId)
        .limit(1);
    final username = targetRows.isEmpty
        ? null
        : targetRows.first['username']?.toString().trim().toLowerCase();

    final response = await _client.functions.invoke(
      'admin-disable-manager',
      body: {'membership_id': membershipId, 'active': active},
    );
    if (response.status < 200 || response.status >= 300) {
      throw StateError(
        'Modification du compte refusée : ${response.data}',
      );
    }

    if (username != null && username.isNotEmpty) {
      await AppDatabase.instance.db.update(
        'app_users',
        {
          'active': active ? 1 : 0,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'lower(username) = ? AND role = ?',
        whereArgs: [username, 'manager'],
      );
    }
  }

  Future<void> resetManagerPassword(
    String membershipId,
    String temporaryPassword,
  ) async {
    if (!OperatorSession.isAdmin) {
      throw StateError('Réservé à l’administrateur.');
    }

    final targetRows = await _client
        .from('organization_members')
        .select('username')
        .eq('id', membershipId)
        .limit(1);
    final username = targetRows.isEmpty
        ? null
        : targetRows.first['username']?.toString().trim().toLowerCase();

    final response = await _client.functions.invoke(
      'admin-reset-manager-password',
      body: {
        'membership_id': membershipId,
        'temporary_password': temporaryPassword,
      },
    );
    if (response.status < 200 || response.status >= 300) {
      throw StateError(
        'Réinitialisation refusée : ${response.data}',
      );
    }

    if (username != null && username.isNotEmpty) {
      final security = SecurityRepository(AppDatabase.instance);
      final users = await security.users();
      final matches = users
          .where((u) => u.username.trim().toLowerCase() == username)
          .toList();
      if (matches.isNotEmpty) {
        await security.resetPin(
          userId: matches.first.id,
          newPin: temporaryPassword,
          allowAdminProvisioning: true,
        );
      }
    }
  }

  Future<void> changeOwnPassword(String password) async {
    if (password.length < 8) {
      throw ArgumentError(
        'Le mot de passe doit contenir au moins 8 caractères.',
      );
    }
    await _client.auth.updateUser(UserAttributes(password: password));
    await _client.rpc('mark_password_changed');
    final membership = await loadMyMembership();
    if (membership != null && membership.isManager) {
      await _cacheLocalCredential(membership, password);
    }
  }

  Future<void> signOut() async {
    if (isConfigured) await _client.auth.signOut();
    await _tenantRepo.clearMembership();
  }

  Future<bool> canUnlockCachedManagerOffline() async {
    final cached = await _tenantRepo.cachedMembership();
    if (!_offlineLeaseValid(cached) ||
        cached == null ||
        !cached.active ||
        !cached.isManager) {
      return false;
    }
    final username = cached.username?.trim().toLowerCase();
    if (username == null || username.isEmpty) return false;

    final users =
        await SecurityRepository(AppDatabase.instance).users(activeOnly: true);
    return users.any(
      (user) =>
          user.active &&
          user.role == 'manager' &&
          user.username.trim().toLowerCase() == username,
    );
  }

  Future<TenantMembershipCache?> restoreCachedOrRemoteMembership() async {
    if (!isConfigured) return null;

    if (_client.auth.currentSession != null) {
      try {
        final remote = await loadMyMembership();
        if (remote != null) return remote;

        // Une réponse distante valide sans appartenance active est
        // autoritative : ne jamais retomber silencieusement sur un ancien
        // cache local.
        await _invalidateCachedAuthorization();
        return null;
      } catch (error) {
        if (!_isTransientNetworkError(error)) rethrow;

        final cached = await _tenantRepo.cachedMembership();
        if (_offlineLeaseValid(cached)) {
          _applySession(cached!);
          return cached;
        }
        return null;
      }
    }

    return null;
  }

  bool _offlineLeaseValid(TenantMembershipCache? membership) {
    if (membership == null || !membership.active) return false;
    return DateTime.now().difference(membership.updatedAt) <= _offlineLease;
  }

  bool _isTransientNetworkError(Object error) {
    final raw = error.toString().toLowerCase();
    return raw.contains('socketexception') ||
        raw.contains('failed host lookup') ||
        raw.contains('network is unreachable') ||
        raw.contains('connection refused') ||
        raw.contains('connection reset') ||
        raw.contains('connection closed') ||
        raw.contains('timed out') ||
        raw.contains('timeoutexception') ||
        raw.contains('503') ||
        raw.contains('502') ||
        raw.contains('504');
  }

  Future<void> _invalidateCachedAuthorization() async {
    final cached = await _tenantRepo.cachedMembership();
    final username = cached?.username?.trim().toLowerCase();
    if (username != null && username.isNotEmpty) {
      await AppDatabase.instance.db.update(
        'app_users',
        {
          'active': 0,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'lower(username) = ? AND role = ?',
        whereArgs: [username, 'manager'],
      );
    }
    await _tenantRepo.clearMembership();
    OperatorSession.clear();
  }

  Future<void> _registerDeviceBestEffort(
    TenantMembershipCache membership,
  ) async {
    try {
      var deviceKey = await _secure.read(key: _deviceKeyStorageKey);
      if (deviceKey == null || deviceKey.isEmpty) {
        deviceKey = const Uuid().v4();
        await _secure.write(key: _deviceKeyStorageKey, value: deviceKey);
      }
      final platform =
          kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase();
      await _client.from('devices').upsert(
        {
          'organization_id': membership.organizationId,
          'user_id': membership.cloudUserId,
          'device_key': deviceKey,
          'platform': platform,
          'last_seen_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'organization_id,device_key',
      );
    } catch (_) {
      // L'inventaire des appareils ne doit pas empêcher une connexion valide.
    }
  }

  void _applySession(TenantMembershipCache membership) {
    OperatorSession.authenticate(
      userId: membership.cloudUserId,
      cloudUserId: membership.cloudUserId,
      displayName: membership.displayName,
      role: membership.role,
      organizationId: membership.organizationId,
      organizationCode: membership.organizationCode,
      organizationName: membership.organizationName,
    );
  }

  Future<void> _cacheLocalCredential(
    TenantMembershipCache membership,
    String password,
  ) async {
    if (!membership.isManager) return;
    final security = SecurityRepository(AppDatabase.instance);
    final users = await security.users();
    final username = membership.username ?? 'gestionnaire';
    final found = users
        .where((u) => u.username.toLowerCase() == username.toLowerCase())
        .toList();
    if (found.isEmpty) {
      await security.createUser(
        username: username,
        displayName: membership.displayName,
        role: 'manager',
        pin: password,
        allowAdminProvisioning: true,
      );
    } else {
      if (!found.first.active) {
        await AppDatabase.instance.db.update(
          'app_users',
          {
            'active': 1,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [found.first.id],
        );
      }
      await security.resetPin(
        userId: found.first.id,
        newPin: password,
        allowAdminProvisioning: true,
      );
    }
  }

  String debugIdentity() => jsonEncode({
        'configured': isConfigured,
        'cloud_user_id': currentCloudUser?.id,
        'organization_id': OperatorSession.organizationId,
        'role': OperatorSession.role,
      });
}
