import 'package:flutter_test/flutter_test.dart';
import 'package:gesapp/core/db/app_database.dart';
import 'package:gesapp/data/repositories/tenant_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  const schoolA = 'b38efacc-4fa1-4ffe-8989-e936a90fc197';
  const schoolB = '98286bee-529c-4f00-8272-3b5b178105b3';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await AppDatabase.instance.close();
    final path = await AppDatabase.instance.databasePath;
    await databaseFactory.deleteDatabase(path);
    await AppDatabase.instance.initialize();
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    final path = await AppDatabase.instance.databasePath;
    await databaseFactory.deleteDatabase(path);
  });

  test('bind first school and persist the binding in SQLite', () async {
    final repo = TenantRepository(AppDatabase.instance);
    await repo.ensureOrganizationIsolated(schoolA);
    await repo.ensureOrganizationIsolated(schoolA);

    final settings = await AppDatabase.instance.db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['gesapp.cloud.bound_organization_id.v1'],
    );
    expect(settings, hasLength(1));
    expect(settings.single['value'], schoolA);
  });

  test('a second school is rejected without modifying the original binding', () async {
    final repo = TenantRepository(AppDatabase.instance);
    await repo.ensureOrganizationIsolated(schoolA);

    await expectLater(
      repo.ensureOrganizationIsolated(schoolB),
      throwsStateError,
    );

    final settings = await AppDatabase.instance.db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['gesapp.cloud.bound_organization_id.v1'],
    );
    expect(settings.single['value'], schoolA);
  });

  test('unbound local school data cannot be claimed by another school', () async {
    final now = DateTime(2026, 10, 1).toIso8601String();
    await AppDatabase.instance.db.insert('establishments', {
      'id': schoolA,
      'name': 'Ecole A',
      'currency': 'XAF',
      'school_year_label': '2026-2027',
      'school_year_start': now,
      'school_year_end': now,
      'created_at': now,
      'updated_at': now,
    });

    final repo = TenantRepository(AppDatabase.instance);
    await expectLater(
      repo.ensureOrganizationIsolated(schoolB),
      throwsStateError,
    );
    final binding = await AppDatabase.instance.db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['gesapp.cloud.bound_organization_id.v1'],
    );
    expect(binding, isEmpty);
  });
}
