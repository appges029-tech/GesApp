import '../sync/sync_maintenance.dart';
import 'operator_session.dart';

abstract final class BusinessWriteGuard {
  static void ensureAllowed([String? operation]) {
    if (SyncMaintenance.isActive) {
      throw StateError(
        'Une mise à jour sécurisée des données est en cours. '
        'Attendez quelques secondes avant de recommencer'
        "${operation == null ? '' : ' ($operation)'}.",
      );
    }
    if (!OperatorSession.isAuthenticated) {
      throw StateError(
        'Aucune session authentifiée. Connectez-vous avec un compte Gestionnaire pour modifier les données${operation == null ? '' : ' ($operation)'}.',
      );
    }
    if (!OperatorSession.isManager) {
      throw StateError(
        'Le compte Administrateur est en lecture seule. '
        'Connectez-vous avec un compte Gestionnaire pour modifier les données${operation == null ? '' : ' ($operation)'}.',
      );
    }
  }

  static void ensureSensitiveDataAccess([String? operation]) {
    ensureAllowed(operation ?? 'données sensibles');
  }

  static void ensureTenantAdmin() {
    if (!OperatorSession.isAdmin) {
      throw StateError('Cette opération est réservée à l’administrateur de l’établissement.');
    }
  }
}
