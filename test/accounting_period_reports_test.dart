import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:gesapp/core/db/app_database.dart';
import 'package:gesapp/core/session/operator_session.dart';
import 'package:gesapp/data/repositories/accounting_repository.dart';

void main() {
  late AccountingRepository accounting;

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
      userId: 'accounting-test',
      displayName: 'Comptable Test',
      role: 'manager',
    );
    accounting = AccountingRepository(AppDatabase.instance);
  });

  tearDown(() async {
    OperatorSession.clear();
    await AppDatabase.instance.close();
    final path = await AppDatabase.instance.databasePath;
    await databaseFactory.deleteDatabase(path);
  });

  Future<void> record({
    required DateTime date,
    required String reference,
    required String debitAccount,
    required String creditAccount,
    required int amount,
  }) async {
    await accounting.createManualEntry(
      date: date,
      journalCode: 'OD',
      reference: reference,
      description: 'Contrôle report',
      lines: [
        {'account_code': debitAccount, 'debit': amount, 'credit': 0},
        {'account_code': creditAccount, 'debit': 0, 'credit': amount},
      ],
    );
  }

  test('la balance conserve les soldes d ouverture et de clôture', () async {
    await record(
      date: DateTime(2026, 9, 10),
      reference: 'REC-SEP',
      debitAccount: '571000',
      creditAccount: '706100',
      amount: 12000,
    );
    await record(
      date: DateTime(2026, 10, 15),
      reference: 'DEP-OCT',
      debitAccount: '601000',
      creditAccount: '571000',
      amount: 3000,
    );

    final rows = await accounting.trialBalance(
      start: DateTime(2026, 10, 1),
      end: DateTime(2026, 11, 1),
    );
    final cash = rows.singleWhere((r) => r['code'] == '571000');
    final revenue = rows.singleWhere((r) => r['code'] == '706100');
    final expense = rows.singleWhere((r) => r['code'] == '601000');

    expect(cash['opening_balance'], 12000);
    expect(cash['debit'], 0);
    expect(cash['credit'], 3000);
    expect(cash['balance'], 9000);
    expect(revenue['opening_balance'], -12000);
    expect(revenue['balance'], -12000);
    expect(expense['opening_balance'], 0);
    expect(expense['balance'], 3000);

    final totalOpening = rows.fold<int>(
      0, (sum, r) => sum + (r['opening_balance'] as num).toInt());
    final totalDebit = rows.fold<int>(
      0, (sum, r) => sum + (r['debit'] as num).toInt());
    final totalCredit = rows.fold<int>(
      0, (sum, r) => sum + (r['credit'] as num).toInt());
    final totalClosing = rows.fold<int>(
      0, (sum, r) => sum + (r['balance'] as num).toInt());

    expect(totalOpening, 0);
    expect(totalDebit, totalCredit);
    expect(totalClosing, 0);
  });

  test('le grand-livre affiche le report avant les mouvements', () async {
    await record(
      date: DateTime(2026, 9, 10),
      reference: 'REC-SEP',
      debitAccount: '571000',
      creditAccount: '706100',
      amount: 12000,
    );
    await record(
      date: DateTime(2026, 10, 15),
      reference: 'DEP-OCT',
      debitAccount: '601000',
      creditAccount: '571000',
      amount: 3000,
    );
    final ledger = await accounting.generalLedger(
      start: DateTime(2026, 10, 1),
      end: DateTime(2026, 11, 1),
    );
    final cash = ledger.where((r) => r['account_code'] == '571000').toList();
    expect(cash, hasLength(2));
    expect(cash.first['reference'], 'REPORT');
    expect(cash.first['debit'], 0);
    expect(cash.first['credit'], 0);
    expect(cash.first['balance'], 12000);
    expect(cash.last['reference'], 'DEP-OCT');
    expect(cash.last['balance'], 9000);

    final revenue = ledger.where((r) => r['account_code'] == '706100').toList();
    expect(revenue, hasLength(1));
    expect(revenue.single['reference'], 'REPORT');
    expect(revenue.single['balance'], -12000);
  });

  test('une période sans mouvements ne perd pas les reports', () async {
    await record(
      date: DateTime(2026, 9, 10),
      reference: 'REC-SEP',
      debitAccount: '571000',
      creditAccount: '706100',
      amount: 12000,
    );
    final rows = await accounting.trialBalance(
      start: DateTime(2026, 11, 1),
      end: DateTime(2026, 12, 1),
    );
    expect(rows, hasLength(2));
    expect(rows.every((r) => r['debit'] == 0 && r['credit'] == 0), isTrue);
    final ledger = await accounting.generalLedger(
      start: DateTime(2026, 11, 1),
      end: DateTime(2026, 12, 1),
    );
    expect(ledger, hasLength(2));
    expect(ledger.every((r) => r['reference'] == 'REPORT'), isTrue);
  });
}
