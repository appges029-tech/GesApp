
/// Centralises the school-identity checks for local and cloud backups.
/// Refuses a mismatch rather than trying to merge encrypted tenants.
abstract final class TenantDataIsolation {
  static void requireSameTenant(String requested, String? stored) {
    if (stored != null && stored != requested) {
      throw StateError(
        'Sécurité : données d’un autre établissement. '
        'Changement de tenant interdit dans cette installation.',
      );
    }
  }

  static void validateSnapshot(
    Map<String, dynamic> document,
    String expectedOrganizationId,
  ) {
    final rawTables = document['tables'];
    if (rawTables is! Map) {
      throw StateError('Snapshot rejeté : tables métier absentes.');
    }
    final establishments = rawTables['establishments'];
    if (establishments is! List ||
        establishments.length != 1 ||
        establishments.first is! Map ||
        establishments.first['id']?.toString() != expectedOrganizationId) {
      throw StateError(
        'Snapshot rejeté : données d’un autre établissement ou identité absente.',
      );
    }
    final settings = rawTables['app_settings'];
    if (settings is! List) {
      throw StateError('Snapshot rejeté : réglages métier absents.');
    }
    for (final setting in settings) {
      if (setting is Map &&
          setting['key'] == 'gesapp.cloud.bound_organization_id.v1') {
        requireSameTenant(
          expectedOrganizationId,
          setting['value']?.toString(),
        );
      }
    }
  }
}
