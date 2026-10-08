import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Etat d'abonnement reçu du serveur et mis en cache dans le coffre du système.
/// Aucune donnée de facturation n'est stockée dans la base métier/snapshot.
class TenantSubscriptionAccess {
  TenantSubscriptionAccess._();
  static final instance = TenantSubscriptionAccess._();

  static const _storage = FlutterSecureStorage();
  final ValueNotifier<int> changes = ValueNotifier<int>(0);
  String? _organizationId;
  String _status = 'pending';
  String? _cycle;
  DateTime? _expiresAt;
  DateTime? _lastTrustedUtc;
  bool _organizationActive = false;
  DateTime? _lastPersistedUtc;

  String get status => _status;
  String? get cycle => _cycle;
  DateTime? get expiresAt => _expiresAt;
  String? get organizationId => _organizationId;

  static bool evaluate({
    required String? organizationId,
    required String status,
    required bool organizationActive,
    required DateTime? expiresAt,
    required DateTime nowUtc,
    required DateTime? lastTrustedUtc,
  }) {
    if (organizationId == null || !organizationActive) return false;
    if (lastTrustedUtc != null &&
        nowUtc.isBefore(lastTrustedUtc.subtract(const Duration(minutes: 5)))) {
      return false;
    }
    if (status == 'legacy') return true; // Établissement antérieur à la migration.
    return status == 'active' && expiresAt != null &&
        nowUtc.isBefore(expiresAt);
  }

  bool get isAllowed => evaluate(
        organizationId: _organizationId,
        status: _status,
        organizationActive: _organizationActive,
        expiresAt: _expiresAt,
        nowUtc: DateTime.now().toUtc(),
        lastTrustedUtc: _lastTrustedUtc,
      );

  String get denialReason {
    if (_organizationId == null) return 'Aucun établissement reconnu.';
    if (!_organizationActive || _status == 'suspended') {
      return "L'établissement est suspendu par le Super Admin.";
    }
    if (_status == 'pending') return 'Abonnement en attente de validation.';
    if (_lastTrustedUtc != null &&
        DateTime.now().toUtc().isBefore(
          _lastTrustedUtc!.subtract(const Duration(minutes: 5)),
        )) {
      return "La date de l'appareil semble avoir été reculée. Reconnectez-vous pour la vérifier.";
    }
    return 'Abonnement expiré. Le Super Admin doit confirmer votre renouvellement.';
  }

  String _key(String id) => 'gesapp.subscription.v1.$id';

  Future<void> restore(String organizationId) async {
    _organizationId = organizationId;
    _status = 'pending'; // Jamais de droit implicite en absence de cache.
    _organizationActive = false;
    _cycle = null;
    _expiresAt = null;
    _lastTrustedUtc = null;
    _lastPersistedUtc = null;
    try {
      final raw = await _storage.read(key: _key(organizationId));
      if (raw != null) {
        final payload = jsonDecode(raw);
        if (payload is Map &&
            payload['organization_id']?.toString() == organizationId) {
          _status = payload['status']?.toString() ?? 'pending';
          _organizationActive = payload['organization_active'] == true;
          _cycle = payload['cycle']?.toString();
          _expiresAt = DateTime.tryParse(
            payload['expires_at']?.toString() ?? '',
          )?.toUtc();
          _lastTrustedUtc = DateTime.tryParse(
            payload['last_trusted_utc']?.toString() ?? '',
          )?.toUtc();
        }
      }
    } catch (_) {
      // Données corrompues : verrouiller sans jamais effacer les données métier.
    }
    changes.value++;
  }

  Future<void> applyRemote(Map<String, dynamic> data) async {
    final id = data['organization_id']?.toString() ?? '';
    if (id.isEmpty) throw StateError('Réponse abonnement invalide.');
    final serverNow = DateTime.tryParse(data['server_now']?.toString() ?? '')?.toUtc();
    if (serverNow == null) throw StateError('Heure serveur indisponible.');
    if (_organizationId != id) await restore(id);

    // L'heure serveur peut corriger un poste mal réglé sans lever les droits
    // tant que l'application n'a pas été synchronisée.
    _lastTrustedUtc = serverNow; // L'heure du serveur rétablit une horloge corrigée.
    _organizationId = id;
    _status = data['status']?.toString() ?? 'pending';
    _cycle = data['cycle']?.toString();
    _organizationActive = data['organization_active'] == true;
    _expiresAt = DateTime.tryParse(data['expires_at']?.toString() ?? '')?.toUtc();

    await _persist();
    _lastPersistedUtc = serverNow;
    changes.value++;
  }

  Future<void> _persist() async {
    final id = _organizationId;
    if (id == null) return;
    await _storage.write(
      key: _key(id),
      value: jsonEncode({
        'organization_id': id,
        'status': _status,
        'cycle': _cycle,
        'organization_active': _organizationActive,
        'expires_at': _expiresAt?.toIso8601String(),
        'last_trusted_utc': _lastTrustedUtc?.toIso8601String(),
      }),
    );
  }

  /// Un rappel régulier garantit le blocage en cours d'utilisation, sans réseau.
  Future<void> tick() async {
    if (_organizationId == null) return;
    final now = DateTime.now().toUtc();
    if (_lastTrustedUtc == null || now.isAfter(_lastTrustedUtc!)) {
      _lastTrustedUtc = now;
      if (_lastPersistedUtc == null ||
          now.difference(_lastPersistedUtc!) >= const Duration(minutes: 1)) {
        await _persist();
        _lastPersistedUtc = now;
      }
    }
    changes.value++;
  }

  void clearInMemory() {
    _organizationId = null;
    _status = 'pending';
    _cycle = null;
    _expiresAt = null;
    _lastTrustedUtc = null;
    _organizationActive = false;
    changes.value++;
  }
}
