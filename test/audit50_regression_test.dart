import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:gesapp/core/db/app_database.dart';
import 'package:gesapp/core/session/business_write_guard.dart';
import 'package:gesapp/core/session/operator_session.dart';
import 'package:gesapp/data/repositories/accounting_repository.dart';
import 'package:gesapp/data/repositories/asset_repository.dart';
import 'package:gesapp/data/repositories/cash_repository.dart';
import 'package:gesapp/data/repositories/report_repository.dart';
import 'package:gesapp/data/repositories/settings_repository.dart';

void main() {
  late AssetRepository assets;
  late CashRepository cash;
  late AccountingRepository accounting;
  late ReportRepository reports;
  late SettingsRepository settings;

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
    OperatorSession.authenticate(userId: 'manager-test', displayName: 'Gestionnaire Test', role: 'manager');
    assets = AssetRepository(AppDatabase.instance);
    cash = CashRepository(AppDatabase.instance);
    accounting = AccountingRepository(AppDatabase.instance);
    reports = ReportRepository(AppDatabase.instance);
    settings = SettingsRepository(AppDatabase.instance);
  });

  tearDown(() async {
    OperatorSession.clear();
    await AppDatabase.instance.close();
    final path = await AppDatabase.instance.databasePath;
    await databaseFactory.deleteDatabase(path);
  });

  Future<String> createAsset([String name = 'Ordinateur test']) async {
    final category = (await assets.categories()).first;
    return assets.saveAsset(name: name, categoryId: category.id);
  }

  test('les écritures métier anonymes sont refusées', () {
    OperatorSession.clear();
    expect(() => BusinessWriteGuard.ensureAllowed('test'), throwsA(isA<StateError>()));
  });

  test('l’identité établissement est réellement persistée', () async {
    await settings.saveEstablishment(EstablishmentData(
      name: 'École Audit 50',
      phone: '060000000',
      approvalNumber: 'AGR-50',
      logoPath: '/tmp/logo.png',
      schoolYearLabel: '2026-2027',
      schoolYearStart: DateTime(2026, 10, 1),
      schoolYearEnd: DateTime(2027, 7, 31),
    ));
    final value = await settings.establishment();
    expect(value?.name, 'École Audit 50');
    expect(value?.approvalNumber, 'AGR-50');
    expect(value?.logoPath, '/tmp/logo.png');
  });

  test('la création établissement réutilise une année scolaire déjà active', () async {
    await settings.createSchoolYear(
      label: '2026-2027',
      startDate: DateTime(2026, 9, 1),
      endDate: DateTime(2027, 7, 31),
      activate: true,
    );
    await settings.saveEstablishment(EstablishmentData(
      name: 'École avec année existante',
      schoolYearLabel: 'ne-doit-pas-dupliquer',
      schoolYearStart: DateTime(2020, 1, 1),
      schoolYearEnd: DateTime(2020, 12, 31),
    ));
    final years = await settings.schoolYears();
    expect(years, hasLength(1));
    expect(years.single.label, '2026-2027');
    expect((await settings.establishment())?.schoolYearLabel, '2026-2027');
  });

  test('les données sensibles sont refusées à l’administrateur lecture seule', () {
    OperatorSession.authenticate(userId: 'admin-test', displayName: 'Administrateur Test', role: 'admin');
    expect(() => BusinessWriteGuard.ensureSensitiveDataAccess('export'), throwsA(isA<StateError>()));
  });

  test('un inventaire clôturé ne peut plus être modifié', () async {
    await createAsset();
    final sessionId = await assets.startInventory(label: 'Inventaire verrouillé');
    final item = (await assets.inventoryItems(sessionId)).single;
    await assets.checkInventoryItem(itemId: item['id'] as String, result: 'found');
    await assets.completeInventory(sessionId);
    await expectLater(
      assets.checkInventoryItem(itemId: item['id'] as String, result: 'missing'),
      throwsA(isA<StateError>()),
    );
  });

  test('un bien sorti ne peut pas être réactivé par maintenance', () async {
    final assetId = await createAsset();
    await assets.disposeAsset(assetId: assetId, disposalType: 'reform', disposalDate: DateTime.now());
    await expectLater(
      assets.saveMaintenance(assetId: assetId, maintenanceType: 'corrective', status: 'completed'),
      throwsA(isA<StateError>()),
    );
  });

  test('une vente patrimoniale augmente la caisse et crée une écriture comptable', () async {
    final assetId = await createAsset('Véhicule test');
    await cash.open(accountId: 'main_cash', openingAmount: 100000);
    final session = await cash.openSession('main_cash');
    final before = await cash.theoretical(session!['id'] as String);
    await assets.disposeAsset(
      assetId: assetId,
      disposalType: 'sale',
      disposalDate: DateTime.now(),
      saleAmount: 25000,
      cashAccountId: 'main_cash',
      reference: 'CESS-TEST-001',
    );
    final after = await cash.theoretical(session['id'] as String);
    expect(after - before, 25000);
    final entries = await AppDatabase.instance.db.query(
      'accounting_entries',
      where: "source_type='asset_sale'",
    );
    expect(entries, hasLength(1));
  });

  test('un règlement fournisseur apparaît dans les dépenses de reporting', () async {
    await cash.open(accountId: 'main_cash', openingAmount: 100000);
    await accounting.addSupplierInvoice(
      invoiceNumber: 'FOUR-001',
      supplierName: 'Fournisseur Test',
      invoiceDate: DateTime.now(),
      description: 'Fournitures audit',
      expenseAccountCode: '601000',
      amount: 12000,
    );
    final invoice = (await accounting.supplierInvoices()).single;
    await accounting.paySupplierInvoice(
      invoiceId: invoice['id'] as String,
      cashAccountId: 'main_cash',
      amount: 12000,
      paidAt: DateTime.now(),
      reference: 'REG-001',
    );
    final start = DateTime.now().subtract(const Duration(days: 1));
    final end = DateTime.now().add(const Duration(days: 1));
    final summary = await reports.financialSummary(start: start, end: end);
    expect(summary.expenses, 12000);
    final rows = await reports.expenseReport(filter: ReportFilter(start: start, end: end));
    expect(rows.any((row) => '${row['category']}'.startsWith('Fournisseurs')), isTrue);
  });
}
