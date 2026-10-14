import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:gesapp/core/db/app_database.dart';
import 'package:gesapp/core/session/operator_session.dart';
import 'package:gesapp/data/repositories/cash_repository.dart';
import 'package:gesapp/data/repositories/data_integrity_repository.dart';
import 'package:gesapp/data/repositories/finance_repository.dart';
import 'package:gesapp/data/repositories/security_repository.dart';
import 'package:gesapp/data/repositories/settings_repository.dart';
import 'package:gesapp/data/repositories/student_repository.dart';

void main() {
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
  });

  tearDown(() async {
    OperatorSession.clear();
    await AppDatabase.instance.close();
    final path = await AppDatabase.instance.databasePath;
    await databaseFactory.deleteDatabase(path);
  });

  test('smoke pré-production: accès -> élève -> échéance -> paiement -> annulation -> intégrité', () async {
    final security = SecurityRepository(AppDatabase.instance);
    final settings = SettingsRepository(AppDatabase.instance);
    final students = StudentRepository(AppDatabase.instance);
    final finance = FinanceRepository(AppDatabase.instance);
    final cash = CashRepository(AppDatabase.instance);
    final integrity = DataIntegrityRepository(AppDatabase.instance);

    final userId = await security.createUser(
      username: 'smoke-manager',
      displayName: 'Gestionnaire Smoke',
      role: 'manager',
      pin: 'Smoke-Prod-2026',
    );
    final login = await security.authenticate(userId, 'Smoke-Prod-2026');
    expect(login.success, isTrue);
    expect(OperatorSession.isManager, isTrue);

    await settings.saveEstablishment(
      EstablishmentData(
        name: 'École Préproduction',
        schoolYearLabel: '2026-2027',
        schoolYearStart: DateTime(2026, 10, 1),
        schoolYearEnd: DateTime(2027, 7, 31),
      ),
    );

    final cycles = await settings.cycles();
    expect(cycles, isNotEmpty);
    await settings.addClassroom(
      cycleId: cycles.first['id'] as String,
      name: 'Classe Smoke',
      capacity: 30,
    );
    final classroom = (await students.classrooms())
        .singleWhere((item) => item.name == 'Classe Smoke');

    final studentId = await students.add(
      firstName: 'Élève',
      lastName: 'Production',
      classroomId: classroom.id,
    );
    // Le scénario facture octobre : l'inscription doit donc être effective
    // au début de la période, pas à la date d'exécution du test.
    await AppDatabase.instance.db.update(
      'student_enrollments',
      {'effective_from': DateTime(2026, 10, 1).toIso8601String()},
      where: 'student_id = ?',
      whereArgs: [studentId],
    );

    await finance.addFeeCategory(
      name: 'Scolarité smoke',
      periodicity: 'mensuelle',
    );
    final fee = (await finance.feeCategories())
        .singleWhere((item) => item.name == 'Scolarité smoke');
    await finance.addFeeGrid(
      feeId: fee.id,
      cycleId: cycles.first['id'] as String,
      amount: 25000,
      validFrom: DateTime(2026, 10, 1),
    );

    final automatic = await finance.dues();
    expect(automatic, hasLength(9));
    expect(automatic.first.periodKey, '2026-10');

    await cash.open(accountId: 'main_cash', openingAmount: 0);
    final receipt = await finance.recordPayment(
      studentId: studentId,
      amount: 10000,
      method: 'Espèces',
      cashAccountId: 'main_cash',
    );
    expect(receipt, isNotEmpty);

    var due = (await finance.dues()).firstWhere((d) => d.periodKey == '2026-10');
    expect(due.amountPaid, 10000);
    expect(due.status, 'partial');

    final payment = (await finance.recentPayments())
        .singleWhere((item) => item.receiptNumber == receipt);
    await finance.cancelPayment(
      paymentId: payment.id,
      reason: 'Smoke test contre-passation',
    );

    due = (await finance.dues()).firstWhere((d) => d.periodKey == '2026-10');
    expect(due.amountPaid, 0);
    expect(due.status, 'unpaid');

    final report = await integrity.run();
    final financialLabels = <String>{
      'Intégrité SQLite',
      'Clés étrangères',
      'Montants des échéances',
      'Statut des échéances',
      'Affectation des paiements',
      'Solde payé des échéances',
      'Années scolaires financières',
      'Affectations inter-années',
    };
    final financialChecks = report.checks
        .where((check) => financialLabels.contains(check.label))
        .toList();
    expect(financialChecks, hasLength(financialLabels.length));
    expect(
      financialChecks.where((check) => !check.passed),
      isEmpty,
      reason: financialChecks
          .where((check) => !check.passed)
          .map((check) => '${check.label}: ${check.detail}')
          .join(' | '),
    );
  });
}
