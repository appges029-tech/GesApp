import 'package:flutter_test/flutter_test.dart';
import 'package:gesapp/core/session/tenant_subscription_access.dart';

void main() {
  final utc = DateTime.utc(2026, 10, 8, 10, 0);
  final expires = DateTime.utc(2026, 11, 8, 10, 0);

  bool allowed({
    String status = 'active',
    bool organizationActive = true,
    DateTime? now,
    DateTime? lastTrusted,
    DateTime? until,
    String? id = 'tenant-001',
  }) => TenantSubscriptionAccess.evaluate(
    organizationId: id,
    status: status,
    organizationActive: organizationActive,
    expiresAt: until ?? expires,
    nowUtc: now ?? utc,
    lastTrustedUtc: lastTrusted,
  );

  test('un abonnement mensuel est actif avant la date exacte', () {
    expect(allowed(now: expires.subtract(const Duration(milliseconds: 1))), isTrue);
  });

  test('blocage exact à l échéance, même sans réseau', () {
    expect(allowed(now: expires), isFalse);
    expect(allowed(now: expires.add(const Duration(days: 2))), isFalse);
  });

  test('demandes en attente et écoles suspendues sont interdites', () {
    expect(allowed(status: 'pending'), isFalse);
    expect(allowed(status: 'suspended'), isFalse);
    expect(allowed(organizationActive: false), isFalse);
  });

  test('aucun accès sans établissement identifié', () {
    expect(allowed(id: null), isFalse);
  });

  test('le recul de l horloge est détecté', () {
    expect(allowed(lastTrusted: utc.add(const Duration(hours: 2))), isFalse);
  });

  test('les établissements antérieurs restent accessibles jusqu à migration commerciale', () {
    expect(allowed(status: 'legacy', now: expires.add(const Duration(days: 100))), isTrue);
  });

  test('nouvelle activation étend strictement la date autorisée', () {
    expect(allowed(until: DateTime.utc(2027, 10, 8, 10)), isTrue);
  });
}
