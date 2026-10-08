import 'package:flutter/foundation.dart';

import 'tenant_subscription_access.dart';

/// Session authentifiée courante.
///
/// Depuis GesApp 2.1, chaque session appartient à un établissement (tenant).
/// - `admin` : propriétaire/superviseur de l'établissement, lecture seule sur
///   toutes les données métier mais autorisé à gérer les comptes gestionnaires.
/// - `manager` : utilisateur opérationnel autorisé à modifier les données
///   métier, sans pouvoir administrer les comptes du tenant.
abstract final class OperatorSession {
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static String? _userId;
  static String _displayName = 'Système';
  static String _role = 'anonymous';
  static String? _organizationId;
  static String? _organizationCode;
  static String? _organizationName;
  static String? _cloudUserId;

  static String? get userId => _userId;
  static String get current => _displayName;
  static String get role => _role;
  static String? get organizationId => _organizationId;
  static String? get organizationCode => _organizationCode;
  static String? get organizationName => _organizationName;
  static String? get cloudUserId => _cloudUserId;

  static bool get isAuthenticated => _userId != null || _cloudUserId != null;
  static bool get isAdmin => isAuthenticated && _role == 'admin';
  static bool get isManager => isAuthenticated && _role == 'manager';
  static bool get isReadOnly => isAdmin;

  // Compatibilité avec l'ancien code.
  static bool get isDirector => isAdmin;
  static bool get isCashier => false;

  static bool hasPermission(String permission) {
    if (!isAuthenticated ||
        (organizationId != null && !TenantSubscriptionAccess.instance.isAllowed)) return false;
    if (permission == 'security.manage_users' || permission == 'tenant.manage') {
      return isAdmin;
    }
    if (permission.endsWith('.view') || permission == 'reports.view' || permission == 'audit.view') {
      return true;
    }
    // Toute permission d'écriture métier est réservée aux gestionnaires.
    return isManager;
  }

  static void authenticate({
    String? userId,
    required String displayName,
    required String role,
    String? organizationId,
    String? organizationCode,
    String? organizationName,
    String? cloudUserId,
  }) {
    final normalizedRole = role == 'admin' ? 'admin' : 'manager';
    _userId = userId;
    _displayName = displayName.trim().isEmpty
        ? (normalizedRole == 'admin' ? 'Administrateur' : 'Gestionnaire')
        : displayName.trim();
    _role = normalizedRole;
    _organizationId = organizationId;
    _organizationCode = organizationCode;
    _organizationName = organizationName;
    _cloudUserId = cloudUserId;
    changes.value++;
  }

  static void clear() {
    _userId = null;
    _displayName = 'Système';
    _role = 'anonymous';
    _organizationId = null;
    _organizationCode = null;
    _organizationName = null;
    _cloudUserId = null;
    changes.value++;
  }

  static void set(String name) {
    _displayName = name.trim().isEmpty ? 'Gestionnaire' : name.trim();
    changes.value++;
  }
}
