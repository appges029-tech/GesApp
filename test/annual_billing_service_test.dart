import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gesapp/core/db/app_database.dart';
import 'package:gesapp/core/session/operator_session.dart';
import 'package:gesapp/data/repositories/finance_repository.dart';
import 'package:gesapp/data/repositories/settings_repository.dart';
import 'package:gesapp/data/repositories/student_repository.dart';
import 'package:gesapp/services/annual_billing_service.dart';

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

  test('inscription : neuf mensualités créées une seule fois', () async {
    await setupCalendar();
    final id=await students.add(firstName:'Jean',lastName:'Test',
      classroomId:classroomId);
    final dues=await finance.dues();
    expect(dues.length,9);
    expect(dues.first.periodKey,'2026-10');
    expect(dues.last.periodKey,'2027-06');
    expect(dues.every((d)=>d.amountDue==30000),isTrue);
    expect(await finance.outstandingForStudent(id),270000);
    final state=await AppDatabase.instance.db.query('student_billing_state',
      where:'student_id=?',whereArgs:[id]);
    expect(state.single['status'],'ready');
    final rerun=await AppDatabase.instance.db.transaction((tx)=>
      const AnnualBillingService().createForEnrollment(tx,
        studentId:id,schoolYearId:state.single['school_year_id'] as String,
        classroomId:classroomId,enrolledAt:DateTime(2026,10,9)));
    expect(rerun.created,0);
    expect((await finance.dues()).length,9);
  });

  test('sans calendrier : état incomplet, sans fausse dette nulle', () async {
    final id=await students.add(firstName:'Marie',
      lastName:'Sans calendrier',classroomId:classroomId);
    expect(await finance.dues(),isEmpty);
    var state=await AppDatabase.instance.db.query('student_billing_state',
      where:'student_id=?',whereArgs:[id]);
    expect(state.single['status'],'pending_configuration');
    await setupCalendar();
    final result=await calendar.completePending();
    expect(result.created,9);
    expect(result.completed,1);
    state=await AppDatabase.instance.db.query('student_billing_state',
      where:'student_id=?',whereArgs:[id]);
    expect(state.single['status'],'ready');
  });

  test('admission en cours de mois : option de période suivante', () async {
    await setupCalendar(admissionPolicy:'next_period');
    await students.add(firstName:'Aline',lastName:'Test',
      classroomId:classroomId);
    final dues=await finance.dues();
    expect(dues.length,8);
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
}
