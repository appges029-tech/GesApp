import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/cloud/supabase_bootstrap.dart';
import '../core/cloud/supabase_config.dart';
import '../core/db/app_database.dart';
import '../core/session/operator_session.dart';
import '../core/security/manager_password_policy.dart';
import '../core/session/tenant_subscription_access.dart';
import '../data/repositories/security_repository.dart';
import '../data/repositories/tenant_repository.dart';

class TenantCloudService {
  TenantCloudService._();
  static final instance = TenantCloudService._();

  SupabaseClient get _client => SupabaseBootstrap.client;
  final _tenantRepo = TenantRepository(AppDatabase.instance);

  bool get isConfigured => SupabaseConfig.isConfigured && SupabaseBootstrap.isInitialized;
  User? get currentCloudUser => isConfigured ? _client.auth.currentUser : null;
  Session? get currentCloudSession => isConfigured ? _client.auth.currentSession : null;
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
    _requireStrongPassword(password);
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

  static String managerSyntheticEmail(String organizationCode, String username) {
    String normalize(String value) => value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final org = normalize(organizationCode);
    final user = normalize(username);
    if (org.isEmpty || user.isEmpty) throw ArgumentError('Code établissement et identifiant invalides.');
    return 'manager.$org.$user@auth.gesapp.invalid';
  }

  Future<TenantMembershipCache> signInManager({
    required String organizationCode,
    required String username,
    required String password,
  }) async {
    if (!isConfigured) throw StateError('Supabase n’est pas configuré.');
    final email = managerSyntheticEmail(organizationCode, username);
    final response = await _client.auth.signInWithPassword(email: email, password: password);
    if (response.user == null) throw StateError('Connexion gestionnaire impossible.');
    final membership = await loadMyMembership();
    if (membership == null || !membership.isManager) {
      await _client.auth.signOut();
      throw StateError('Ce compte n’est pas un gestionnaire GesApp actif.');
    }
    if (membership.organizationCode.toUpperCase() != organizationCode.trim().toUpperCase()) {
      await _client.auth.signOut();
      throw StateError('Ce compte n’appartient pas à cet établissement.');
    }
    // Never cache a temporary password for offline use.
    if (!membership.mustChangePassword) {
      await _cacheLocalCredential(membership, password);
    }
    return membership;
  }

  Future<Map<String, dynamic>> refreshSubscription() async {
    if (!isConfigured || _client.auth.currentUser == null) {
      throw StateError('Connexion Internet et compte confirmé requis pour actualiser.');
    }
    final result = await _client.rpc('get_my_subscription');
    if (result is! Map) throw StateError('Abonnement introuvable pour ce compte.');
    final info = Map<String, dynamic>.from(result);
    await TenantSubscriptionAccess.instance.applyRemote(info);
    return info;
  }

  Future<Map<String, dynamic>?> myAdministratorRequest() async {
    if (!isConfigured || _client.auth.currentUser == null) return null;
    final results = await _client.from('admin_registration_requests')
        .select('id,school_name,status,created_at,reviewed_at,review_note')
        .eq('user_id', _client.auth.currentUser!.id)
        .order('created_at', ascending: false).limit(1);
    if (results.isEmpty) return null;
    return Map<String, dynamic>.from(results.first);
  }

  Future<void> requestAdministratorApproval({
    required String schoolName,
    String? preferredCode,
    required String displayName,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null || user.email == null) {
      throw StateError('Confirmez votre adresse e-mail avant de soumettre la demande.');
    }
    if (schoolName.trim().length < 3 || displayName.trim().length < 2) {
      throw ArgumentError('Indiquez le nom de votre école et votre nom complet.');
    }
    await _client.from('admin_registration_requests').insert({
      'user_id': user.id,
      'email': user.email!.trim().toLowerCase(),
      'school_name': schoolName.trim(),
      'preferred_code': preferredCode?.trim(),
      'display_name': displayName.trim(),
    });
  }

  Future<TenantMembershipCache?> loadMyMembership() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    final result = await _client.rpc('get_my_organization');
    if (result == null) return null;
    final dynamic raw = result is List ? (result.isEmpty ? null : result.first) : result;
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw as Map);
    final membership = TenantMembershipCache(
      organizationId: map['organization_id'].toString(),
      organizationCode: map['organization_code'].toString(),
      organizationName: map['organization_name'].toString(),
      cloudUserId: user.id,
      displayName: (map['display_name'] ?? user.userMetadata?['full_name'] ?? user.email ?? 'Utilisateur').toString(),
      role: map['role'].toString(),
      username: map['username']?.toString(),
      active: map['active'] == true,
      mustChangePassword: map['must_change_password'] == true,
      backupSecret: map['backup_secret']?.toString(),
      updatedAt: DateTime.now(),
    );
    if (!membership.active) throw StateError('Ce compte a été désactivé par l’administrateur.');
    // Avant TOUT cache, renommage ou lancement de la synchronisation :
    // vérifie que cette installation n'appartient pas déjà à une autre école.
    await _tenantRepo.ensureOrganizationIsolated(membership.organizationId);
    await _tenantRepo.cacheMembership(membership);
    await _tenantRepo.applyOrganizationIdentity(
      organizationId: membership.organizationId,
      organizationName: membership.organizationName,
    );
    try {
      await refreshSubscription();
    } catch (_) {
      // Le cache du droit précédemment délivré permet l'accès hors ligne
      // jusqu'à sa date réelle d'expiration, jamais au-delà.
      await TenantSubscriptionAccess.instance.restore(membership.organizationId);
    }
    _applySession(membership);
    return membership;
  }

  @Deprecated('Toute création nécessite désormais le Super Admin.')
  Future<TenantMembershipCache> bootstrapOrganization({
    required String name,
    String? preferredCode,
  }) async {
    throw StateError(
      'La création directe est désactivée. Envoyez une demande au Super Admin.',
    );
  }

  Future<List<Map<String, dynamic>>> managers() async {
    final orgId = OperatorSession.organizationId;
    if (orgId == null) return const [];
    final rows = await _client
        .from('organization_members')
        .select('id,user_id,username,display_name,role,active,must_change_password,created_at')
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
    if (!OperatorSession.isAdmin) throw StateError('Réservé à l’administrateur.');
    _requireStrongPassword(temporaryPassword);
    final response = await _client.functions.invoke(
      'admin-create-manager',
      body: {
        'username': username.trim(),
        'display_name': displayName.trim(),
        'temporary_password': temporaryPassword,
      },
    );
    if (response.status < 200 || response.status >= 300) {
      throw StateError('Création du gestionnaire refusée : ${response.data}');
    }
    final data = Map<String, dynamic>.from(response.data as Map);
    // A newly created manager must authenticate online on their own device.
    // Never create their offline credentials on the administrator's device.
    return data;
  }

  Future<void> setManagerActive(String membershipId, bool active) async {
    if (!OperatorSession.isAdmin) throw StateError('Réservé à l’administrateur.');
    final response = await _client.functions.invoke(
      'admin-disable-manager',
      body: {'membership_id': membershipId, 'active': active},
    );
    if (response.status < 200 || response.status >= 300) {
      throw StateError('Modification du compte refusée : ${response.data}');
    }
  }

  Future<void> resetManagerPassword(String membershipId, String temporaryPassword) async {
    if (!OperatorSession.isAdmin) throw StateError('Réservé à l’administrateur.');
    _requireStrongPassword(temporaryPassword);
    final response = await _client.functions.invoke(
      'admin-reset-manager-password',
      body: {'membership_id': membershipId, 'temporary_password': temporaryPassword},
    );
    if (response.status < 200 || response.status >= 300 ||
        response.data is! Map || response.data['ok'] != true) {
      throw StateError('Réinitialisation refusée : ${response.data}');
    }
  }

  Future<TenantMembershipCache> changeOwnPassword(String currentPassword, String newPassword) async {
    if (!OperatorSession.isManager) {
      throw StateError('Seul un gestionnaire peut changer ce mot de passe.');
    }
    _requireStrongPassword(newPassword);
    if (newPassword == currentPassword) {
      throw ArgumentError('Le nouveau mot de passe doit être différent de l’ancien.');
    }
    // The server checks the current password, updates Supabase Auth and only
    // then clears must_change_password. No callable client-side flag bypass.
    final response = await _client.functions.invoke(
      'manager-change-password',
      body: {
        'current_password': currentPassword,
        'new_password': newPassword,
      },
    );
    if (response.status < 200 || response.status >= 300 ||
        response.data is! Map || response.data['ok'] != true) {
      throw StateError('Changement du mot de passe refusé : ${response.data}');
    }
    final membership = await loadMyMembership();
    if (membership == null || !membership.isManager || membership.mustChangePassword) {
      throw StateError('Le nouveau mot de passe est enregistré, mais la confirmation du compte a échoué. Reconnectez-vous en ligne.');
    }
    await _cacheLocalCredential(membership, newPassword);
    return membership;
  }

  Future<void> signOut() async {
    if (isConfigured) await _client.auth.signOut();
    await _tenantRepo.clearMembership();
    TenantSubscriptionAccess.instance.clearInMemory();
  }

  Future<bool> canUnlockCachedManagerOffline() async {
    final cached = await _tenantRepo.cachedMembership();
    if (cached == null || !cached.active || !cached.isManager ||
        cached.mustChangePassword) return false;
    // Le code PIN hors ligne doit respecter la même séparation des écoles.
    await _tenantRepo.ensureOrganizationIsolated(cached.organizationId);
    await TenantSubscriptionAccess.instance.restore(cached.organizationId);
    if (!TenantSubscriptionAccess.instance.isAllowed) return false;
    final username = cached.username?.trim().toLowerCase();
    if (username == null || username.isEmpty) return false;

    final users = await SecurityRepository(AppDatabase.instance).users(activeOnly: true);
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
      } catch (error) {
        // Une erreur d'isolation n'est jamais une panne réseau :
        // aucune reconnexion via un cache d'une autre école.
        final details = error.toString();
        if (details.contains('Sécurité :') ||
            details.contains('ancienne base scolaire non attribuée')) {
          rethrow;
        }
        // Hors connexion : le cache ne sera accepté que pour le même userId.
      }
    }
    final cached = await _tenantRepo.cachedMembership();
    if (cached != null &&
        cached.active &&
        _client.auth.currentSession != null &&
        cached.cloudUserId == _client.auth.currentUser?.id) {
      await _tenantRepo.ensureOrganizationIsolated(cached.organizationId);
      await TenantSubscriptionAccess.instance.restore(cached.organizationId);
      _applySession(cached);
      return cached;
    }
    // Ne jamais restaurer l'école A lorsque Supabase est connecté à B.
    OperatorSession.clear();
    return null;
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

  Future<void> _cacheLocalCredential(TenantMembershipCache membership, String password) async {
    if (!membership.isManager) return;
    final security = SecurityRepository(AppDatabase.instance);
    final users = await security.users();
    final username = membership.username ?? 'gestionnaire';
    final found = users.where((u) => u.username.toLowerCase() == username.toLowerCase()).toList();
    if (found.isEmpty) {
      await security.createUser(
        username: username,
        displayName: membership.displayName,
        role: 'manager',
        pin: password,
        allowAdminProvisioning: true,
      );
    } else {
      await security.resetPin(userId: found.first.id, newPin: password, allowAdminProvisioning: true);
    }
  }

  void _requireStrongPassword(String value) {
    if (!ManagerPasswordPolicy.isStrong(value)) {
      throw ArgumentError('Le mot de passe doit contenir au moins 10 caractères, '
          'une majuscule, une minuscule et un chiffre.');
    }
  }

  String debugIdentity() => jsonEncode({
        'configured': isConfigured,
        'cloud_user_id': currentCloudUser?.id,
        'organization_id': OperatorSession.organizationId,
        'role': OperatorSession.role,
      });
}
