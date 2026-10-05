import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:gesapp/core/db/app_database.dart';
import 'package:gesapp/core/session/operator_session.dart';
import 'package:gesapp/data/repositories/asset_repository.dart';
import 'package:gesapp/data/repositories/hr_repository.dart';
import 'package:gesapp/data/repositories/security_repository.dart';
import 'package:gesapp/data/repositories/finance_repository.dart';
import 'package:gesapp/data/repositories/expense_repository.dart';

void main() {
  late SecurityRepository security;
  late HrRepository hr;
  late AssetRepository assets;
  late FinanceRepository finance;
  late ExpenseRepository expenses;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    OperatorSession.clear();
    await AppDatabase.instance.close();
    final path = await AppDatabase.instance.databasePath;
    await databaseFactory.deleteDatabase(path);
    await AppDatabase.instance.initialize();
    security = SecurityRepository(AppDatabase.instance);
    hr = HrRepository(AppDatabase.instance);
    assets = AssetRepository(AppDatabase.instance);
    finance = FinanceRepository(AppDatabase.instance);
    expenses = ExpenseRepository(AppDatabase.instance);
    OperatorSession.authenticate(userId: 'test-manager', displayName: 'Gestionnaire Test', role: 'manager');
  });

  tearDown(() async {
    OperatorSession.clear();
    await AppDatabase.instance.close();
    final path = await AppDatabase.instance.databasePath;
    await databaseFactory.deleteDatabase(path);
  });

  test('le premier gestionnaire est authentifié sans stocker le PIN en clair',
      () async {
    final id = await security.createUser(
      username: 'admin',
      displayName: 'Gestionnaire Test',
      role: 'manager',
      pin: '4826',
    );

    final row = (await AppDatabase.instance.db.query(
      'app_users',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    ))
        .single;
    expect(row['pin_hash'], isNot('4826'));
    expect(row['pin_algorithm'], 'pbkdf2-sha256');

    final failure = await security.authenticate(id, '0000');
    expect(failure.success, isFalse);
    final success = await security.authenticate(id, '4826');
    expect(success.success, isTrue);
    expect(OperatorSession.isAuthenticated, isTrue);
  });

  test('cinq PIN incorrects verrouillent temporairement le compte', () async {
    final id = await security.createUser(
      username: 'securite',
      displayName: 'Sécurité',
      role: 'manager',
      pin: '1357',
    );

    LoginResult? result;
    for (var attempt = 0; attempt < 5; attempt++) {
      result = await security.authenticate(id, '9999');
    }
    expect(result!.success, isFalse);
    expect(result.lockedUntil, isNotNull);
  });

  test('une opération sensible exige un autre gestionnaire lorsqu’ils sont plusieurs', () async {
    final firstId = await security.createUser(
      username: 'gestion1',
      displayName: 'Gestionnaire Un',
      role: 'manager',
      pin: '1234',
    );
    await security.createUser(
      username: 'gestion2',
      displayName: 'Gestionnaire Deux',
      role: 'manager',
      pin: '5678',
    );
    expect((await security.authenticate(firstId, '1234')).success, isTrue);
    expect(await security.authorizeSensitiveAction(username: 'gestion1', pin: '1234', action: 'test'), isNull);
    final approval = await security.authorizeSensitiveAction(username: 'gestion2', pin: '5678', action: 'test');
    expect(approval?.username, 'gestion2');
  });

  test('un administrateur ne peut pas annuler un lot ni modifier un modèle récurrent', () async {
    OperatorSession.authenticate(
      userId: 'admin-test',
      displayName: 'Administrateur Test',
      role: 'admin',
    );

    await expectLater(
      finance.cancelBillingBatch('lot-inexistant'),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      expenses.setRecurringTemplateActive('modele-inexistant', false),
      throwsA(isA<StateError>()),
    );
  });

  test('un employé conserve son historique de statut et sa présence',
      () async {
    final employeeId = await hr.saveEmployee(
      firstName: 'Alice',
      lastName: 'Mabiala',
      hireDate: DateTime(2026, 9, 1),
    );
    await hr.saveEmployee(
      id: employeeId,
      firstName: 'Alice',
      lastName: 'Mabiala',
      hireDate: DateTime(2026, 9, 1),
      status: 'suspended',
    );
    await hr.setAttendance(
      employeeId: employeeId,
      date: DateTime(2026, 9, 8),
      status: 'present',
      arrivalTime: '07:30',
    );

    final history = await hr.employeeStatusHistory(employeeId);
    expect(history, hasLength(2));
    expect(history.first['new_status'], 'suspended');
    final attendance = await hr.attendance(DateTime(2026, 9, 8));
    expect(attendance.single.status, 'present');
  });

  test('un bien est créé, tracé puis déplacé sans perdre son historique',
      () async {
    final category = (await assets.categories()).first;
    final locations = await assets.locations();
    final source = locations.first;
    await assets.saveLocation(name: 'Salle Test', type: 'room');
    final destination = (await assets.locations())
        .firstWhere((location) => location.name == 'Salle Test');

    final assetId = await assets.saveAsset(
      name: 'Ordinateur test',
      categoryId: category.id,
      acquisitionValue: 350000,
      locationId: source.id,
    );
    await assets.moveAsset(
      assetId: assetId,
      toLocationId: destination.id,
      movementType: 'transfer',
      reason: 'Test de transfert',
    );

    final item = await assets.assetDetails(assetId);
    expect(item!['current_location_id'], destination.id);
    expect(await assets.movements(assetId), hasLength(2));
  });
}
