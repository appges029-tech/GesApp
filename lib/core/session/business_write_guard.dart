import 'operator_session.dart';
import 'tenant_subscription_access.dart';

abstract final class BusinessWriteGuard {
  static void ensureAllowed([String? operation]) {
    if (!OperatorSession.isAuthenticated) {
      throw StateError(
        'Aucune session authentifiée. Connectez-vous avec un compte Gestionnaire pour modifier les données${operation == null ? '' : ' ($operation)'}.',
      );
    }
    ensureSubscription();
    if (!OperatorSession.isManager) {
      throw StateError(
        'Le compte Administrateur est en lecture seule. '
        'Connectez-vous avec un compte Gestionnaire pour modifier les données${operation == null ? '' : ' ($operation)'}.',
      );
    }
  }

  static void ensureSubscription() {
    if (OperatorSession.organizationId != null &&
        !TenantSubscriptionAccess.instance.isAllowed) {
      throw StateError(TenantSubscriptionAccess.instance.denialReason);
    }
  }

  static void ensureSensitiveDataAccess([String? operation]) {
    ensureAllowed(operation ?? 'données sensibles');
  }

  static void ensureTenantAdmin() {
    ensureSubscription();
    if (!OperatorSession.isAdmin) {
      throw StateError('Cette opération est réservée à l’administrateur de l’établissement.');
    }
  }
}
