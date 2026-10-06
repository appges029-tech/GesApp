import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:gesapp/core/db/app_database.dart';
import 'package:gesapp/core/platform/platform_database.dart';
import 'package:gesapp/core/session/business_write_guard.dart';
import 'package:gesapp/core/session/operator_session.dart';
import 'package:gesapp/core/sync/sync_maintenance.dart';
import 'package:gesapp/data/repositories/security_repository.dart';
import 'package:gesapp/data/repositories/tenant_repository.dart';

void main() {
  setUpAll(configurePlatformDatabase);

  setUp(() async {
    OperatorSession.clear();
    await AppDatabase.instance.close();
    final path = await AppDatabase.instance.databasePath;
    await platformDatabaseFactory.deleteDatabase(path);
    await AppDatabase.instance.initialize();
  });

  tearDown(() async {
    OperatorSession.clear();
    await AppDatabase.instance.close();
    final path = await AppDatabase.instance.databasePath;
    await platformDatabaseFactory.deleteDatabase(path);
  });

  test('le bootstrap tenant ne fabrique pas une révision métier', () async {
    final tenant = TenantRepository(AppDatabase.instance);
    await tenant.updateSyncState(
      localRevision: 7,
      lastUploadedLocalRevision: 5,
      knownRemoteRevision: 2,
      status: 'idle',
    );

    await tenant.applyOrganizationIdentity(
      organizationId: '11111111-1111-4111-8111-111111111111',
      organizationName: 'École Audit Sync',
    );

    final state = await tenant.syncState();
    expect(state['local_revision'], 7);
    expect(state['last_uploaded_local_revision'], 5);
  });

  test('mettre en cache une session tenant ne salit pas les données métier',
      () async {
    final tenant = TenantRepository(AppDatabase.instance);
    await tenant.updateSyncState(
      localRevision: 4,
      lastUploadedLocalRevision: 4,
      knownRemoteRevision: 3,
      status: 'up_to_date',
    );

    await tenant.cacheMembership(
      TenantMembershipCache(
        organizationId: '22222222-2222-4222-8222-222222222222',
        organizationCode: 'AUDIT-222',
        organizationName: 'École Cache',
        cloudUserId: '33333333-3333-4333-8333-333333333333',
        displayName: 'Gestionnaire',
        role: 'manager',
        username: 'gestionnaire',
        active: true,
        mustChangePassword: false,
        updatedAt: DateTime.now(),
        backupSecret: '0123456789abcdef0123456789abcdef',
      ),
    );

    final state = await tenant.syncState();
    expect(state['local_revision'], 4);
    expect(state['last_uploaded_local_revision'], 4);
  });

  test('les écritures métier sont bloquées pendant une restauration', () async {
    OperatorSession.authenticate(
      userId: 'manager-sync',
      displayName: 'Gestionnaire Sync',
      role: 'manager',
    );

    final entered = Completer<void>();
    final release = Completer<void>();
    final operation = SyncMaintenance.runExclusive(() async {
      entered.complete();
      await release.future;
    });

    await entered.future;
    expect(
      () => BusinessWriteGuard.ensureAllowed('écriture de test'),
      throwsStateError,
    );

    release.complete();
    await operation;

    expect(
      () => BusinessWriteGuard.ensureAllowed('écriture de test'),
      returnsNormally,
    );
  });

  test('un rôle inconnu ne devient jamais gestionnaire', () {
    expect(
      () => OperatorSession.authenticate(
        userId: 'role-test',
        displayName: 'Rôle inconnu',
        role: 'super-manager',
      ),
      throwsStateError,
    );
    expect(OperatorSession.isManager, isFalse);
  });

  test('resetPin refuse une réinitialisation sans session', () async {
    final security = SecurityRepository(AppDatabase.instance);
    final userId = await security.createUser(
      username: 'gestionnaire',
      displayName: 'Gestionnaire',
      role: 'manager',
      pin: 'MotDePasse-123!',
    );
    OperatorSession.clear();

    await expectLater(
      security.resetPin(
        userId: userId,
        newPin: 'NouveauMotDePasse-456!',
      ),
      throwsStateError,
    );
  });
}
