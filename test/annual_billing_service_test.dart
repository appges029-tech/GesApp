import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gesapp/core/db/app_database.dart';
import 'package:gesapp/core/session/operator_session.dart';
import 'package:gesapp/data/repositories/finance_repository.dart';
import 'package:gesapp/data/repositories/cash_repository.dart';
import 'package:gesapp/data/repositories/settings_repository.dart';
import 'package:gesapp/data/repositories/student_repository.dart';
import 'package:gesapp/services/annual_billing_service.dart';
import 'package:gesapp/services/json_schema.dart';

void main() {
  late SettingsRepository settings;
  late StudentRepository students;
  late FinanceRepository finance;
  late BillingCalendarRepository calendar;
  late String classroomId, cycleId, feeId;

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
      userId:'billing-test-manager', displayName:'Gestionnaire',
      role:'manager');
    settings = SettingsRepository(AppDatabase.instance);
    students = StudentRepository(AppDatabase.instance);
    finance = FinanceRepository(AppDatabase.instance);
    calendar = BillingCalendarRepository(AppDatabase.instance);
    await settings.saveEstablishment(EstablishmentData(
      name:'École Test', schoolYearLabel:'2026-2027',
      schoolYearStart:DateTime(2026,10,1),
      schoolYearEnd:DateTime(2027,7,31)));
    cycleId = (await settings.cycles()).first['id'] as String;
    await settings.addClassroom(cycleId:cycleId,
      name:'Terminale Test',capacity:100);
    classroomId=(await students.classrooms()).firstWhere(
      (c)=>c.name=='Terminale Test').id;
    await finance.addFeeCategory(name:'Scolarité',periodicity:'mensuelle');
    feeId=(await finance.feeCategories()).single.id;
    await finance.addFeeGrid(feeId:feeId,cycleId:cycleId,
      amount:30000,validFrom:DateTime(2026,9,1));
  });
  tearDown(() async {
    OperatorSession.clear();
    await AppDatabase.instance.close();
    await databaseFactory.deleteDatabase(
      await AppDatabase.instance.databasePath);
  });

  Future<void> setupCalendar({String admissionPolicy='current_period'}) =>
      calendar.saveRule(
        feeId:feeId,startDate:DateTime(2026,10,1),
        endDate:DateTime(2027,6,30),dueDay:10,
        admissionPolicy:admissionPolicy,graceDays:0);

  test('inscription : dix mois en terminale, y compris juillet', () async {
    await setupCalendar();
    final id=await students.add(firstName:'Jean',lastName:'Test',
      classroomId:classroomId);
    final dues=await finance.dues();
    expect(dues.length,10);
    expect(dues.first.periodKey,'2026-10');
    expect(dues.last.periodKey,'2027-07');
    expect(dues.every((d)=>d.amountDue==30000),isTrue);
    expect(await finance.outstandingForStudent(id),300000);
    final state=await AppDatabase.instance.db.query('student_billing_state',
      where:'student_id=?',whereArgs:[id]);
    expect(state.single['status'],'ready');
    final rerun=await AppDatabase.instance.db.transaction((tx)=>
      const AnnualBillingService().createForEnrollment(tx,
        studentId:id,schoolYearId:state.single['school_year_id'] as String,
        classroomId:classroomId,enrolledAt:DateTime(2026,10,9)));
    expect(rerun.created,0);
    expect((await finance.dues()).length,10);
  });

  test('sans calendrier : les obligations naissent automatiquement du tarif', () async {
    final id = await students.add(
      firstName: 'Marie', lastName: 'Sans calendrier', classroomId: classroomId);
    final dues = await finance.unpaidForPayer(studentId: id);
    expect(dues.length, 10); // Terminale : octobre à juillet inclus.
    expect(dues.first.periodKey, '2026-10');
    expect(dues.last.periodKey, '2027-07');
    final state = await AppDatabase.instance.db.query('student_billing_state',
      where: 'student_id=?', whereArgs: [id]);
    expect(state.single['status'], 'ready');
    final reconciled = await calendar.completePending(includeReady: true);
    expect(reconciled.created, 0);
    expect((await finance.unpaidForPayer(studentId: id)).length, 10);
  });


  test('admission en cours de mois : option de période suivante', () async {
    await setupCalendar(admissionPolicy:'next_period');
    await students.add(firstName:'Aline',lastName:'Test',
      classroomId:classroomId);
    final dues=await finance.dues();
    expect(dues.length,9);
    expect(dues.first.periodKey,'2026-11');
  });

  test('une réconciliation ne modifie pas une échéance partiellement réglée', () async {
    await setupCalendar();
    final id=await students.add(firstName:'Paul',lastName:'Test',
      classroomId:classroomId);
    final d=(await finance.dues()).first;
    await AppDatabase.instance.db.update('dues',
      {'amount_paid':10000,'status':'partial'},
      where:'id=?',whereArgs:[d.id]);
    final yearId=(await calendar.load()).yearId;
    await AppDatabase.instance.db.transaction((tx)=>
      const AnnualBillingService().createForEnrollment(tx,
        studentId:id,schoolYearId:yearId,
        classroomId:classroomId,enrolledAt:DateTime(2026,10,9)));
    final again=(await finance.dues()).firstWhere((x)=>x.id==d.id);
    expect(again.amountDue,30000);
    expect(again.amountPaid,10000);
    expect(again.status,'partial');
  });

  test('échéance hors année scolaire : simulation interdite', () async {
    await expectLater(finance.previewDues(
      periodKey:'2027-10',periodicity:'mensuelle',
      dueDate:DateTime(2027,10,10),
      referenceDate:DateTime(2027,10,1)),
      throwsA(isA<StateError>()));
  });

  test('calendrier configuré : générateur historique désactivé', () async {
    await setupCalendar();
    await expectLater(finance.previewDues(
      periodKey:'2026-10',periodicity:'mensuelle',
      dueDate:DateTime(2026,10,10),
      referenceDate:DateTime(2026,10,1)),
      throwsA(isA<StateError>()));
  });
  test('sauvegarde V29 complète acceptée, sauvegarde tronquée refusée', () {
    final olderNames = gesAppPortableTables.where(
      (name) => name != 'billing_calendar_rules' &&
                name != 'student_billing_state').toList();
    final legacy = <String, dynamic>{
      for (final name in olderNames) name: <Map<String,Object?>>[],
    };
    expect(() => validateCompletePortableExport(
      sourceSchemaVersion:29,currentSchemaVersion:30,
      currentPortableTables:gesAppPortableTables,
      sourceTables:legacy,tableManifest:olderNames),returnsNormally);
    final incomplete = Map<String,dynamic>.from(legacy)..remove('dues');
    expect(() => validateCompletePortableExport(
      sourceSchemaVersion:29,currentSchemaVersion:30,
      currentPortableTables:gesAppPortableTables,
      sourceTables:incomplete,tableManifest:olderNames),
      throwsA(isA<FormatException>()));
  });

  test('dates facultatives : elles adaptent les délais sans supprimer les mois', () async {
    await calendar.saveMonthlyDeadlines({
      '2026-10': DateTime(2026, 10, 17),
      '2026-12': DateTime(2026, 12, 5),
    });
    final id = await students.add(
      firstName: 'Octave', lastName: 'Dates réelles', classroomId: classroomId);
    final dues = await finance.unpaidForPayer(studentId: id);
    expect(dues.length, 10);
    final october = dues.firstWhere((d) => d.periodKey == '2026-10');
    final december = dues.firstWhere((d) => d.periodKey == '2026-12');
    expect(october.dueDate, DateTime(2026, 10, 17));
    expect(december.dueDate, DateTime(2026, 12, 5));
    expect(dues.any((d) => d.periodKey == '2027-07'), isTrue);
  });


  test('ajouter un calendrier après inscription ne recrée aucune dette', () async {
    final id = await students.add(
      firstName: 'Dany', lastName: 'Inscrit avant dates',
      classroomId: classroomId);
    expect((await finance.unpaidForPayer(studentId: id)).length, 10);
    await calendar.saveMonthlyDeadlines({
      '2026-11': DateTime(2026, 11, 14),
    });
    final dues = await finance.unpaidForPayer(studentId: id);
    expect(dues.length, 10);
    final again = await calendar.completePending(includeReady: true);
    expect(again.created, 0);
    expect((await finance.unpaidForPayer(studentId: id)).length, 10);
  });


  test('période soldée reste visible mais ne peut être encaissée deux fois', () async {
    await calendar.saveMonthlyDeadlines({
      '2026-10': DateTime(2026, 10, 17),
      '2026-11': DateTime(2026, 11, 10),
    });
    final id = await students.add(
      firstName: 'Zoé', lastName: 'Soldée', classroomId: classroomId);
    final initial = await finance.unpaidForPayer(studentId: id);
    // Les dates facultatives ne suppriment pas les mensualités dues.
    expect(initial, hasLength(10));
    final october = initial.firstWhere((d) => d.periodKey == '2026-10');
    final november = initial.firstWhere((d) => d.periodKey == '2026-11');
    expect(october.dueDate, DateTime(2026, 10, 17));
    expect(november.dueDate, DateTime(2026, 11, 10));

    await CashRepository(AppDatabase.instance).open(
      accountId: 'main_cash', openingAmount: 0);
    final receipt = await finance.recordPayment(
      studentId: id, amount: 30000, method: 'Espèces',
      cashAccountId: 'main_cash', dueIds: [october.id]);
    expect(receipt, isNotEmpty);

    final all = await finance.unpaidForPayer(
      studentId: id, includePaid: true);
    final dueOnly = await finance.unpaidForPayer(studentId: id);
    expect(all, hasLength(10));
    expect(dueOnly, hasLength(9));
    expect(all.firstWhere((d) => d.id == october.id).balance, 0);
    expect(all.firstWhere((d) => d.id == october.id).status, 'paid');
    expect(dueOnly.any((d) => d.id == october.id), isFalse);
    expect(await finance.outstandingForStudent(id), 270000);

    // Une échéance soldée ne peut plus être sélectionnée pour un nouvel
    // encaissement, même si les neuf autres restent impayées.
    await expectLater(
      finance.recordPayment(
        studentId: id, amount: 30000, method: 'Espèces',
        cashAccountId: 'main_cash', dueIds: [october.id]),
      throwsA(isA<StateError>()));
    final payments = await AppDatabase.instance.db.query(
      'payments', where: 'student_id=?', whereArgs: [id]);
    expect(payments, hasLength(1));
    expect(await finance.availableCredit(studentId: id), 0);
  });

  test('un calendrier mensuel rejette une date limite hors période', () async {
    await expectLater(calendar.saveMonthlyDeadlines({
      '2026-10':DateTime(2026,11,1),
    }),throwsA(isA<StateError>()));
  });

  test('nouvelle rubrique tarifée : obligations automatiques pour élèves inscrits', () async {
    final id = await students.add(
      firstName: 'Awa', lastName: 'Nouveau tarif',
      classroomId: classroomId);
    expect((await finance.unpaidForPayer(studentId: id)).length, 10);
    await finance.addFeeCategory(
      name: 'Fournitures mensuelles', periodicity: 'mensuelle');
    final newFee = (await finance.feeCategories()).firstWhere(
      (fee) => fee.name == 'Fournitures mensuelles');
    await finance.addFeeGrid(
      feeId: newFee.id, cycleId: cycleId,
      amount: 4000, validFrom: DateTime(2026, 10, 1));
    final dues = await finance.unpaidForPayer(studentId: id);
    expect(dues.length, 20);
    expect(dues.where((d) => d.feeId == newFee.id).length, 10);
    expect(dues.fold<int>(0, (sum, d) => sum + d.balance), 340000);
  });


  test('génération manuelle refusée si dates mensuelles automatiques en service', () async {
    await calendar.saveMonthlyDeadlines({
      '2026-10':DateTime(2026,10,10),
    });
    await expectLater(finance.previewDues(
      periodKey:'2026-10',periodicity:'mensuelle',
      dueDate:DateTime(2026,10,10),
      referenceDate:DateTime(2026,10,1)),
      throwsA(isA<StateError>()));
  });

  test('rubrique trimestrielle : trois périodes, frais uniques : une seule', () async {
    final id = await students.add(
      firstName: 'Rosine', lastName: 'Différents frais',
      classroomId: classroomId);
    await finance.addFeeCategory(
      name: 'Frais trimestriels', periodicity: 'trimestrielle');
    await finance.addFeeCategory(
      name: 'Écusson', periodicity: 'unique');
    final fees = await finance.feeCategories();
    final quarter = fees.firstWhere((f) => f.name == 'Frais trimestriels');
    final single = fees.firstWhere((f) => f.name == 'Écusson');
    await finance.addFeeGrid(
      feeId: quarter.id, cycleId: cycleId,
      amount: 10000, validFrom: DateTime(2026, 9, 1));
    await finance.addFeeGrid(
      feeId: single.id, cycleId: cycleId,
      amount: 2500, validFrom: DateTime(2026, 9, 1));
    final dues = await finance.unpaidForPayer(
      studentId: id, includePaid: true);
    final quarters = dues.where((d) => d.feeId == quarter.id).toList();
    final unique = dues.where((d) => d.feeId == single.id).toList();
    expect(quarters.map((d) => d.periodKey).toList(),
      ['2026-T1', '2026-T2', '2026-T3']);
    expect(unique, hasLength(1));
    expect(unique.single.amountDue, 2500);
    expect((await calendar.completePending(includeReady: true)).created, 0);
  });

  test('TA : versement de 20000 sur octobre et novembre à 15000/mois', () async {
    await finance.addFeeGrid(
      feeId: feeId, cycleId: cycleId,
      amount: 15000, validFrom: DateTime(2026, 9, 2));
    final id = await students.add(
      firstName: 'Élève', lastName: 'TA', classroomId: classroomId);
    final dues = await finance.unpaidForPayer(studentId: id, includePaid: true);
    expect(dues.length, 10);
    final october = dues.firstWhere((d) => d.periodKey == '2026-10');
    final november = dues.firstWhere((d) => d.periodKey == '2026-11');

    await CashRepository(AppDatabase.instance).open(
      accountId: 'main_cash', openingAmount: 0);
    final receipt = await finance.recordPayment(
      studentId: id, amount: 20000,
      method: 'Espèces', cashAccountId: 'main_cash',
      dueIds: [october.id, november.id],
    );
    expect(receipt, isNotEmpty);
    final receiptLines = await finance.paymentReceiptLines(receipt);
    expect(receiptLines.map((line) => line['period_key']).toList(),
      ['2026-10', '2026-11']);
    expect(receiptLines.map((line) => line['amount']).toList(),
      [15000, 5000]);
    final after = await finance.unpaidForPayer(
      studentId: id, includePaid: true);
    expect(after.firstWhere((d) => d.id == october.id).amountPaid, 15000);
    expect(after.firstWhere((d) => d.id == october.id).status, 'paid');
    expect(after.firstWhere((d) => d.id == november.id).amountPaid, 5000);
    expect(after.firstWhere((d) => d.id == november.id).balance, 10000);

    final year = await calendar.load();
    final reconciled = await AppDatabase.instance.db.transaction((tx) =>
      const AnnualBillingService().createForEnrollment(
        tx, studentId: id, schoolYearId: year.yearId,
        classroomId: classroomId, enrolledAt: DateTime(2026, 10, 1)));
    expect(reconciled.created, 0);
    final stable = await finance.unpaidForPayer(
      studentId: id, includePaid: true);
    expect(stable.where((d) => d.periodKey == '2026-11').single.amountPaid, 5000);

    await finance.recordPayment(
      studentId: id, amount: 10000, method: 'Espèces',
      cashAccountId: 'main_cash', dueIds: [november.id]);
    final settled = await finance.unpaidForPayer(
      studentId: id, includePaid: true);
    expect(settled.firstWhere((d) => d.id == november.id).status, 'paid');
    expect(settled.firstWhere((d) => d.id == november.id).balance, 0);
  });


}
