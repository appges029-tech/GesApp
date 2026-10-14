import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:gesapp/core/db/app_database.dart';
import 'package:gesapp/core/session/operator_session.dart';
import 'package:gesapp/data/repositories/accounting_repository.dart';
import 'package:gesapp/data/repositories/cash_repository.dart';
import 'package:gesapp/data/repositories/finance_repository.dart';
import 'package:gesapp/data/repositories/settings_repository.dart';
import 'package:gesapp/data/repositories/student_repository.dart';

void main() {
  late AccountingRepository accounting;
  late FinanceRepository finance;
  late CashRepository cash;
  late StudentRepository students;
  late SettingsRepository settings;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await AppDatabase.instance.close();
    final path = await AppDatabase.instance.databasePath;
    await databaseFactory.deleteDatabase(path);
    await AppDatabase.instance.initialize();
    OperatorSession.authenticate(
      userId: 'reversal-test',
      displayName: 'Gestionnaire Test',
      role: 'manager',
    );
    accounting = AccountingRepository(AppDatabase.instance);
    finance = FinanceRepository(AppDatabase.instance);
    cash = CashRepository(AppDatabase.instance);
    students = StudentRepository(AppDatabase.instance);
    settings = SettingsRepository(AppDatabase.instance);
    await settings.saveEstablishment(EstablishmentData(
      name: 'École Comptable Test',
      schoolYearLabel: '2026-2027',
      schoolYearStart: DateTime(2026, 10, 1),
      schoolYearEnd: DateTime(2027, 7, 31),
    ));
  });

  tearDown(() async {
    OperatorSession.clear();
    await AppDatabase.instance.close();
    final path = await AppDatabase.instance.databasePath;
    await databaseFactory.deleteDatabase(path);
  });

  Future<String> createAllocatedPayment() async {
    final cycleId = (await settings.cycles()).first['id'] as String;
    await settings.addClassroom(
      cycleId: cycleId,
      name: 'Classe de test',
      capacity: 50,
    );
    final classroom = (await students.classrooms()).single;
    await students.add(
      firstName: 'Élève', lastName: 'Comptable',
      classroomId: classroom.id,
    );
    final student = (await students.list()).single;
    await finance.createFeeWithTariff(
      name: 'Frais de test', periodicity: 'mensuelle',
      amount: 15000, cycleId: cycleId,
      validFrom: DateTime(2026, 10, 1),
    );
    await cash.open(accountId: 'main_cash', openingAmount: 0);
    final receipt = await finance.recordPayment(
      studentId: student.id,
      amount: 7000,
      method: 'Espèces',
      cashAccountId: 'main_cash',
    );
    final payment = (await finance.recentPayments())
        .singleWhere((p) => p.receiptNumber == receipt);
    return payment.id;
  }

  Future<String?> creditedAccount(String sourceType) async {
    final rows = await AppDatabase.instance.db.rawQuery('''
      SELECT l.account_code FROM accounting_entries e
      JOIN accounting_entry_lines l ON l.entry_id = e.id
      WHERE e.source_type = ? AND l.credit > 0 LIMIT 1
    ''', [sourceType]);
    return rows.isEmpty ? null : rows.single['account_code'] as String?;
  }

  Future<String?> debitedAccount(String sourceType) async {
    final rows = await AppDatabase.instance.db.rawQuery('''
      SELECT l.account_code FROM accounting_entries e
      JOIN accounting_entry_lines l ON l.entry_id = e.id
      WHERE e.source_type = ? AND l.debit > 0 LIMIT 1
    ''', [sourceType]);
    return rows.isEmpty ? null : rows.single['account_code'] as String?;
  }

  test('annulation après comptabilisation : débite le compte crédité', () async {
    final id = await createAllocatedPayment();
    await accounting.synchronize();
    expect(await creditedAccount('payment'), '411100');
    await finance.cancelPayment(paymentId: id, reason: 'Erreur de saisie');
    await accounting.synchronize();
    expect(await debitedAccount('payment_cancel'), '411100');
    expect(await creditedAccount('payment_cancel'), '571000');
  });

  test('annulation avant la première synchronisation conserve la nature', () async {
    final id = await createAllocatedPayment();
    await finance.cancelPayment(paymentId: id, reason: 'Correction');
    await accounting.synchronize();
    expect(await creditedAccount('payment'), '411100');
    expect(await debitedAccount('payment_cancel'), '411100');
  });

  test('remboursement intégral : allocation effacée sans changer le compte', () async {
    final id = await createAllocatedPayment();
    await accounting.synchronize();
    expect(await creditedAccount('payment'), '411100');
    await finance.refundPayment(
      paymentId: id, amount: 7000, reason: 'Trop payé',
    );
    await accounting.synchronize();
    expect(await debitedAccount('refund'), '411100');
    expect(await creditedAccount('refund'), '571000');
  });
}
