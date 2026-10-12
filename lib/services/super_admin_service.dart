import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/cloud/supabase_bootstrap.dart';

class SuperAdminService {
  SuperAdminService._();
  static final instance = SuperAdminService._();

  SupabaseClient get _client => SupabaseBootstrap.client;
  String? _sessionToken;
  DateTime? _expiresAt;

  bool get isAuthenticated =>
      _sessionToken != null &&
      _expiresAt != null &&
      DateTime.now().isBefore(_expiresAt!);

  Future<void> login({
    required String email,
    required String code,
  }) async {
    final response = await _client.functions.invoke(
      'super-admin-api',
      body: {
        'action': 'login',
        'email': email.trim().toLowerCase(),
        'code': code.trim(),
      },
    );
    final data = _map(response.data);
    if (response.status < 200 || response.status >= 300) {
      throw StateError(_errorMessage(data));
    }
    final token = data['token']?.toString();
    final expiresAt = DateTime.tryParse(data['expires_at']?.toString() ?? '');
    if (token == null || token.isEmpty || expiresAt == null) {
      throw StateError('Session Super Admin invalide.');
    }
    _sessionToken = token;
    _expiresAt = expiresAt;
  }

  Future<Map<String, dynamic>> overview() async {
    return _invoke({'action': 'overview'});
  }

  Future<Map<String, dynamic>> organizationDetail(String organizationId) =>
      _invoke({'action': 'organization_detail', 'organization_id': organizationId});

  Future<Map<String, dynamic>> registrationHistory({int offset = 0}) =>
      _invoke({'action': 'registration_history', 'offset': offset});

  Future<Map<String, dynamic>> activityHistory({
    String? organizationId,
    int offset = 0,
  }) => _invoke({
    'action': 'activity_history',
    'organization_id': organizationId ?? '',
    'offset': offset,
  });

  Future<void> setManagerActive({
    required String organizationId,
    required String memberId,
    required bool active,
  }) async {
    await _invoke({
      'action': 'set_manager_active',
      'organization_id': organizationId,
      'member_id': memberId,
      'active': active,
    });
  }

  Future<void> resetManagerPassword({
    required String organizationId,
    required String memberId,
    required String temporaryPassword,
  }) async {
    if (!_isStrongPassword(temporaryPassword)) {
      throw ArgumentError('Mot de passe temporaire : 10 caractères, une '
          'majuscule, une minuscule et un chiffre sont requis.');
    }
    await _invoke({
      'action': 'reset_manager_password',
      'organization_id': organizationId,
      'member_id': memberId,
      'temporary_password': temporaryPassword,
    });
  }

  Future<Map<String, dynamic>> createSchool({
    required String name,
    String? code,
    required String administratorEmail,
    required String administratorName,
    required String administratorPassword,
    required String managerUsername,
    required String managerName,
    required String managerPassword,
    required String subscriptionCycle,
  }) {
    if (!_isStrongPassword(administratorPassword) ||
        !_isStrongPassword(managerPassword)) {
      throw ArgumentError(
        'Les mots de passe temporaires doivent contenir au moins 10 caractères, '
        'avec une majuscule, une minuscule et un chiffre.',
      );
    }
    return _invoke({
      'action': 'create_school',
      'name': name.trim(),
      'code': code?.trim() ?? '',
      'admin_email': administratorEmail.trim().toLowerCase(),
      'admin_name': administratorName.trim(),
      'admin_password': administratorPassword,
      'manager_username': managerUsername.trim(),
      'manager_name': managerName.trim(),
      'manager_password': managerPassword,
      'subscription_cycle': subscriptionCycle,
    });
  }

  Future<Map<String, dynamic>> approveRequest(String requestId, String cycle) =>
      _invoke({
        'action': 'approve_request',
        'request_id': requestId,
        'subscription_cycle': cycle,
      });

  Future<Map<String, dynamic>> rejectRequest(String requestId, {String note = ''}) =>
      _invoke({
        'action': 'reject_request',
        'request_id': requestId,
        'note': note,
      });

  Future<Map<String, dynamic>> renewSubscription(
    String organizationId,
    String cycle, {
    String reference = '',
  }) => _invoke({
        'action': 'renew_subscription',
        'organization_id': organizationId,
        'subscription_cycle': cycle,
        'reference': reference,
      });

  Future<Map<String, dynamic>> setSchoolActive(
    String organizationId,
    bool active,
  ) {
    return _invoke({
      'action': 'set_school_active',
      'organization_id': organizationId,
      'active': active,
    });
  }

  Future<void> logout() async {
    final token = _sessionToken;
    _sessionToken = null;
    _expiresAt = null;
    if (token == null) return;
    try {
      await _client.functions.invoke(
        'super-admin-api',
        body: const {'action': 'logout'},
        headers: {'X-Super-Admin-Session': token},
      );
    } catch (_) {
      // La session locale est déjà supprimée. Une panne réseau ne doit pas
      // empêcher la fermeture du tableau de bord.
    }
  }

  Future<Map<String, dynamic>> _invoke(Map<String, Object?> body) async {
    final token = _sessionToken;
    if (token == null || !isAuthenticated) {
      _sessionToken = null;
      _expiresAt = null;
      throw StateError('Session Super Admin expirée. Reconnectez-vous.');
    }
    final response = await _client.functions.invoke(
      'super-admin-api',
      body: body,
      headers: {'X-Super-Admin-Session': token},
    );
    final data = _map(response.data);
    if (response.status == 401 || response.status == 403) {
      _sessionToken = null;
      _expiresAt = null;
    }
    if (response.status < 200 || response.status >= 300) {
      throw StateError(_errorMessage(data));
    }
    return data;
  }

  bool _isStrongPassword(String value) =>
      value.length >= 10 &&
      RegExp(r'[a-z]').hasMatch(value) &&
      RegExp(r'[A-Z]').hasMatch(value) &&
      RegExp(r'[0-9]').hasMatch(value);

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return {'error': value?.toString() ?? 'Réponse serveur invalide.'};
  }

  String _errorMessage(Map<String, dynamic> data) {
    final raw = data['error']?.toString() ?? 'Opération refusée.';
    return switch (raw) {
      'identifiants_requis' => 'Renseignez l’identifiant et le code Super Admin.',
      'identifiants_invalides' => 'Identifiant ou code Super Admin incorrect.',
      'compte_temporairement_verrouille' =>
        'Trop de tentatives. L’accès Super Admin est temporairement verrouillé.',
      'session_requise' || 'session_invalide_ou_expiree' =>
        'Session Super Admin expirée. Reconnectez-vous.',
      'acces_refuse' => 'Ce compte n’est pas autorisé comme Super Admin.',
      'donnees_ecole_ou_admin_invalides' =>
        'Vérifiez le nom de l’école, l’administrateur et son mot de passe.',
      'abonnement_invalide' => 'Choisissez un abonnement mensuel ou annuel.',
      'demande_introuvable' => 'Cette demande n’est plus disponible.',
      'email_administrateur_non_confirme' => 'Le candidat doit confirmer son adresse e-mail.',
      'donnees_gestionnaire_invalides' =>
        'Vérifiez l’identifiant, le nom et le mot de passe du gestionnaire.',
      _ => raw,
    };
  }
}
