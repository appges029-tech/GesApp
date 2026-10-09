import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:gesapp/core/db/app_database.dart';
import 'package:gesapp/core/session/operator_session.dart';
import 'package:gesapp/data/repositories/data_integrity_repository.dart';
import 'package:gesapp/data/repositories/cash_repository.dart';
import 'package:gesapp/data/repositories/accounting_repository.dart';
import 'package:gesapp/data/repositories/family_repository.dart';
import 'package:gesapp/data/repositories/finance_repository.dart';
import 'package:gesapp/data/repositories/settings_repository.dart';
import 'package:gesapp/data/repositories/student_repository.dart';

void main() {
  late FinanceRepository finance;
  late StudentRepository students;
  late SettingsRepository settings;
  late FamilyRepository families;
  late DataIntegrityRepository integrity;
  late CashRepository cash;
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
    OperatorSession.authenticate(userId: 'test-manager', displayName: 'Gestionnaire Test', role: 'manager');
    finance = FinanceRepository(AppDatabase.instance);
    students = StudentRepository(AppDatabase.instance);
    settings = SettingsRepository(AppDatabase.instance);
    families = FamilyRepository(AppDatabase.instance);
    integrity = DataIntegrityRepository(AppDatabase.instance);
    cash = CashRepository(AppDatabase.instance);
    accounting = AccountingRepository(AppDatabase.instance);
    await settings.saveEstablishment(EstablishmentData(
      name: 'École Test',
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

  Future<(String cycleId, String classroomId)> createClass(String name) async {
    final cycles = await settings.cycles();
    final cycleId = cycles.first['id'] as String;
    await settings.addClassroom(cycleId: cycleId, name: name, capacity: 50);
    final classrooms = await students.classrooms();
    return (cycleId, classrooms.firstWhere((c) => c.name == name).id);
  }

  test('la configuration initiale active son année scolaire', () async {
    final schoolYear = await settings.activeSchoolYear();

    expect(schoolYear, isNotNull);
    expect(schoolYear!.label, '2026-2027');
    expect(schoolYear.startDate, DateTime(2026, 10, 1));
    expect(schoolYear.endDate, DateTime(2027, 7, 31));
  });

  test('une génération mensuelle ignore les rubriques annuelles', () async {
    final target = await createClass('Test-A');
    await students.add(
      firstName: 'Jean',
      lastName: 'Test',
      classroomId: target.$2,
    );

    await finance.addFeeCategory(name: 'Scolarité', periodicity: 'mensuelle');
    await finance.addFeeCategory(name: 'Inscription annuelle', periodicity: 'annuelle');
    final fees = await finance.feeCategories();
    final monthly = fees.firstWhere((f) => f.name == 'Scolarité');
    final annual = fees.firstWhere((f) => f.name == 'Inscription annuelle');
    final validFrom = DateTime(2026, 8, 1);
    await finance.addFeeGrid(
      feeId: monthly.id,
      cycleId: target.$1,
      amount: 20000,
      validFrom: validFrom,
    );
    await finance.addFeeGrid(
      feeId: annual.id,
      cycleId: target.$1,
      amount: 15000,
      validFrom: validFrom,
    );

    final created = await finance.generateDues(
      periodKey: '2026-10',
      periodicity: 'mensuelle',
      dueDate: DateTime(2026, 10, 10),
    );
    expect(created, 1);
    final dues = await finance.dues();
    expect(dues, hasLength(1));
    expect(dues.single.feeName, 'Scolarité');
    expect(dues.single.amountDue, 20000);
  });


  test('une date limite avant la période est refusée sans écriture', () async {
    final target = await createClass('Test-Reference');
    final studentId = await students.add(
      firstName: 'Référence',
      lastName: 'Tarif',
      classroomId: target.$2,
    );
    await AppDatabase.instance.db.update(
      'student_enrollments',
      {'effective_from': DateTime(2026, 10, 1).toIso8601String()},
      where: 'student_id = ?',
      whereArgs: [studentId],
    );
    await finance.addFeeCategory(name: 'Scolarité octobre', periodicity: 'mensuelle');
    final fee = (await finance.feeCategories()).single;
    await finance.addFeeGrid(
      feeId: fee.id,
      cycleId: target.$1,
      amount: 22000,
      validFrom: DateTime(2026, 10, 1),
    );

    await expectLater(
      finance.generateDues(
        periodKey: '2026-10',
        periodicity: 'mensuelle',
        referenceDate: DateTime(2026, 10, 1),
        dueDate: DateTime(2026, 9, 25),
      ),
      throwsA(isA<StateError>()),
    );
    expect(await finance.dues(), isEmpty);
  });

  test('un forfait individuel remplace le tarif standard', () async {
    final target = await createClass('Test-B');
    await students.add(
      firstName: 'Grâce',
      lastName: 'Forfait',
      classroomId: target.$2,
    );
    final student = (await students.list()).single;

    await finance.addFeeCategory(name: 'Scolarité', periodicity: 'mensuelle');
    final fee = (await finance.feeCategories()).single;
    await finance.addFeeGrid(
      feeId: fee.id,
      cycleId: target.$1,
      amount: 20000,
      validFrom: DateTime(2026, 8, 1),
    );
    await finance.createPackage(
      type: 'individual',
      feeId: fee.id,
      studentId: student.id,
      amount: 12000,
      reason: 'Bourse',
      validFrom: DateTime(2026, 9, 1),
    );

    await finance.generateDues(
      periodKey: '2026-10',
      periodicity: 'mensuelle',
      dueDate: DateTime(2026, 10, 10),
    );
    final dues = await finance.dues();
    expect(dues, hasLength(1));
    expect(dues.single.amountDue, 12000);
  });


  test('un forfait familial et individuel ne peuvent pas se chevaucher sur la même rubrique', () async {
    final target = await createClass('Test-Forfait-Conflit');
    final family = await families.add(name: 'Famille Conflit');
    await students.add(
      firstName: 'Élève',
      lastName: 'Conflit',
      classroomId: target.$2,
      familyId: family.id,
    );
    final student = (await students.list()).single;
    await finance.addFeeCategory(name: 'Scolarité conflit', periodicity: 'mensuelle');
    final fee = (await finance.feeCategories()).single;

    await finance.createPackage(
      type: 'individual',
      feeId: fee.id,
      studentId: student.id,
      amount: 10000,
      validFrom: DateTime(2026, 10, 1),
    );

    await expectLater(
      finance.createPackage(
        type: 'family',
        feeId: fee.id,
        familyId: family.id,
        amount: 15000,
        validFrom: DateTime(2026, 10, 1),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test("un forfait familial ne génère qu'une dette pour deux enfants", () async {
    final target = await createClass('Test-C');
    final family = await families.add(name: 'Famille Test');
    await students.add(
      firstName: 'A',
      lastName: 'Enfant',
      classroomId: target.$2,
      familyId: family.id,
    );
    await students.add(
      firstName: 'B',
      lastName: 'Enfant',
      classroomId: target.$2,
      familyId: family.id,
    );

    await finance.addFeeCategory(name: 'Scolarité', periodicity: 'mensuelle');
    final fee = (await finance.feeCategories()).single;
    await finance.addFeeGrid(
      feeId: fee.id,
      cycleId: target.$1,
      amount: 20000,
      validFrom: DateTime(2026, 8, 1),
    );
    await finance.createPackage(
      type: 'family',
      feeId: fee.id,
      familyId: family.id,
      amount: 30000,
      reason: 'Forfait fratrie',
      validFrom: DateTime(2026, 9, 1),
    );

    final created = await finance.generateDues(
      periodKey: '2026-10',
      periodicity: 'mensuelle',
      dueDate: DateTime(2026, 10, 10),
    );
    expect(created, 1);
    final dues = await finance.dues();
    expect(dues, hasLength(1));
    expect(dues.single.amountDue, 30000);
    expect(dues.single.studentName, contains('Famille'));
  });

  test('annuler un paiement rétablit exactement le solde', () async {
    final target = await createClass('Test-D');
    await students.add(
      firstName: 'Paul',
      lastName: 'Paiement',
      classroomId: target.$2,
    );
    final student = (await students.list()).single;
    await finance.addFeeCategory(name: 'Scolarité', periodicity: 'mensuelle');
    final fee = (await finance.feeCategories()).single;
    await finance.addFeeGrid(
      feeId: fee.id,
      cycleId: target.$1,
      amount: 20000,
      validFrom: DateTime(2026, 8, 1),
    );
    await finance.generateDues(
      periodKey: '2026-10',
      periodicity: 'mensuelle',
      dueDate: DateTime(2026, 10, 10),
    );

    await cash.open(accountId: 'main_cash', openingAmount: 0);
    final receipt = await finance.recordPayment(
      studentId: student.id,
      amount: 7000,
      method: 'Espèces',
      cashAccountId: 'main_cash',
    );
    var due = (await finance.dues()).single;
    expect(due.amountPaid, 7000);
    expect(due.status, 'partial');

    final payment = (await finance.recentPayments()).singleWhere(
      (p) => p.receiptNumber == receipt,
    );
    await finance.cancelPayment(paymentId: payment.id, reason: 'Erreur de saisie');

    due = (await finance.dues()).single;
    expect(due.amountPaid, 0);
    expect(due.status, 'unpaid');
    expect(await finance.outstandingForStudent(student.id), 20000);
    final report = await integrity.run();
    // This scenario deliberately creates a student without the required
    // administrative documents, so the global report can legitimately flag
    // dossier completeness. Verify only the accounting checks exercised by
    // the cancellation instead of coupling this test to unrelated data.
    final paymentChecks = report.checks
        .where(
          (check) => const {
            'Montants des échéances',
            'Statut des échéances',
            'Affectation des paiements',
            'Solde payé des échéances',
          }.contains(check.label),
        )
        .toList();
    expect(paymentChecks, hasLength(4));
    expect(
      paymentChecks.where((check) => !check.passed),
      isEmpty,
      reason: paymentChecks
          .where((check) => !check.passed)
          .map((check) => '${check.label}: ${check.detail}')
          .join(' | '),
    );
  });

  test('un paiement refuse une échéance appartenant à un autre élève', () async {
    final target = await createClass('Test-Payeur');
    await students.add(firstName: 'Alice', lastName: 'A', classroomId: target.$2);
    await students.add(firstName: 'Bob', lastName: 'B', classroomId: target.$2);
    final studentRows = await students.list();
    final alice = studentRows.firstWhere((s) => s.firstName == 'Alice');
    final bob = studentRows.firstWhere((s) => s.firstName == 'Bob');

    await finance.addFeeCategory(name: 'Scolarité payeur', periodicity: 'mensuelle');
    final fee = (await finance.feeCategories()).single;
    await finance.addFeeGrid(
      feeId: fee.id,
      cycleId: target.$1,
      amount: 10000,
      validFrom: DateTime(2026, 10, 1),
    );
    await finance.generateDues(
      periodKey: '2026-10',
      periodicity: 'mensuelle',
      dueDate: DateTime(2026, 10, 10),
    );
    final bobDue = (await finance.dues()).firstWhere((d) => d.studentId == bob.id);
    await cash.open(accountId: 'main_cash', openingAmount: 0);

    await expectLater(
      finance.recordPayment(
        studentId: alice.id,
        amount: 1000,
        method: 'Espèces',
        cashAccountId: 'main_cash',
        dueIds: [bobDue.id],
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('un règlement fournisseur diminue la caisse et respecte le solde disponible', () async {
    await cash.open(accountId: 'main_cash', openingAmount: 10000);
    await accounting.addSupplierInvoice(
      invoiceNumber: 'FOUR-001',
      supplierName: 'Fournisseur Test',
      invoiceDate: DateTime(2026, 10, 2),
      description: 'Fournitures',
      expenseAccountCode: '601000',
      amount: 20000,
    );
    final invoice = (await accounting.supplierInvoices()).single;
    final paymentTime = DateTime.now();
    await accounting.paySupplierInvoice(
      invoiceId: invoice['id'] as String,
      cashAccountId: 'main_cash',
      amount: 3000,
      paidAt: paymentTime,
    );
    final session = await cash.openSession('main_cash');
    expect(session, isNotNull);
    expect(await cash.theoretical(session!['id'] as String), 7000);

    await expectLater(
      accounting.paySupplierInvoice(
        invoiceId: invoice['id'] as String,
        cashAccountId: 'main_cash',
        amount: 8000,
        paidAt: DateTime.now(),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test("la capacité d'une classe est respectée", () async {
    final cycles = await settings.cycles();
    final cycleId = cycles.first['id'] as String;
    await settings.addClassroom(cycleId: cycleId, name: 'Capacité-1', capacity: 1);
    final classroom = (await students.classrooms()).singleWhere(
      (c) => c.name == 'Capacité-1',
    );
    await students.add(
      firstName: 'Premier',
      lastName: 'Élève',
      classroomId: classroom.id,
    );
    await expectLater(
      students.add(
        firstName: 'Deuxième',
        lastName: 'Élève',
        classroomId: classroom.id,
      ),
      throwsA(isA<StateError>()),
    );
  });
}
