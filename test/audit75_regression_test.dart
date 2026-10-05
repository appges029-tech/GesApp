import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:gesapp/core/db/app_database.dart';
import 'package:gesapp/core/session/operator_session.dart';
import 'package:gesapp/data/repositories/expense_repository.dart';
import 'package:gesapp/data/repositories/security_repository.dart';
import 'package:gesapp/data/repositories/settings_repository.dart';
import 'package:gesapp/data/repositories/student_repository.dart';
import 'package:gesapp/features/reports/payment_notices_screen.dart';
import 'package:gesapp/services/local_notification_service.dart';

void main() {
  late SettingsRepository settings;
  late StudentRepository students;
  late ExpenseRepository expenses;
  late SecurityRepository security;

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
    OperatorSession.authenticate(userId: 'manager-75', displayName: 'Gestionnaire Audit 75', role: 'manager');
    settings = SettingsRepository(AppDatabase.instance);
    students = StudentRepository(AppDatabase.instance);
    expenses = ExpenseRepository(AppDatabase.instance);
    security = SecurityRepository(AppDatabase.instance);
    await settings.saveEstablishment(EstablishmentData(
      name: 'École Audit 75',
      schoolYearLabel: '2026-2027',
      schoolYearStart: DateTime(2026, 9, 1),
      schoolYearEnd: DateTime(2027, 7, 31),
    ));
  });

  tearDown(() async {
    OperatorSession.clear();
    await AppDatabase.instance.close();
    final path = await AppDatabase.instance.databasePath;
    await databaseFactory.deleteDatabase(path);
  });

  test('les seuils de notifications sont gardés au niveau repository', () async {
    await settings.saveNotificationThresholds(
      overdueHighDays: 25,
      overdueCriticalDays: 80,
      dueSoonDays: 5,
      capacityPercent: 95,
      backupStaleDays: 10,
    );
    final values = await settings.notificationThresholds();
    expect(values['alert.overdue.high_days'], 25);
    expect(values['alert.overdue.critical_days'], 80);

    OperatorSession.authenticate(userId: 'admin-75', displayName: 'Administrateur', role: 'admin');
    await expectLater(
      settings.saveNotificationThresholds(
        overdueHighDays: 30,
        overdueCriticalDays: 90,
        dueSoonDays: 3,
        capacityPercent: 90,
        backupStaleDays: 7,
      ),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      LocalNotificationService.instance.setEnabled(false),
      throwsA(isA<StateError>()),
    );
  });

  test('un mot de passe fort local est accepté et authentifiable', () async {
    OperatorSession.clear();
    final id = await security.createUser(
      username: 'audit75',
      displayName: 'Audit 75',
      role: 'manager',
      pin: 'GesApp-2026!Solide',
    );
    final result = await security.authenticate(id, 'GesApp-2026!Solide');
    expect(result.success, isTrue);
    expect(OperatorSession.isManager, isTrue);
  });

  test('il reste exactement un responsable principal et le cache élève suit', () async {
    final cycle = (await settings.cycles()).first;
    await settings.addClassroom(cycleId: cycle['id'] as String, name: 'Audit75-A', capacity: 40);
    final classroom = (await students.classrooms()).singleWhere((c) => c.name == 'Audit75-A');
    final studentId = await students.add(firstName: 'Jean', lastName: 'Responsable', classroomId: classroom.id);

    await students.saveGuardian(
      studentId: studentId,
      name: 'Parent A',
      phone: '060000001',
      relationship: 'père',
      isPrimary: true,
    );
    await students.saveGuardian(
      studentId: studentId,
      name: 'Parent B',
      phone: '060000002',
      relationship: 'mère',
    );
    var guardians = await students.guardians(studentId);
    final parentA = guardians.singleWhere((g) => g['name'] == 'Parent A');

    await students.saveGuardian(
      id: parentA['id'] as String,
      studentId: studentId,
      name: 'Parent A',
      phone: '060000001',
      relationship: 'père',
      isPrimary: false,
    );

    guardians = await students.guardians(studentId);
    expect(guardians.where((g) => g['is_primary'] == 1), hasLength(1));
    expect(guardians.singleWhere((g) => g['is_primary'] == 1)['name'], 'Parent B');
    final row = (await AppDatabase.instance.db.query('students', where: 'id=?', whereArgs: [studentId], limit: 1)).single;
    expect(row['guardian_name'], 'Parent B');
    expect(row['guardian_phone'], '060000002');
  });

  test('modifier un modèle récurrent désactivé ne le réactive pas', () async {
    final category = (await expenses.categories()).first;
    await expenses.saveRecurringTemplate(
      name: 'Internet',
      categoryId: category.id,
      amount: 30000,
      frequency: 'monthly',
      dayOfMonth: 5,
      active: false,
    );
    var template = (await expenses.recurringTemplates(includeInactive: true)).singleWhere((r) => r['name'] == 'Internet');
    final oldDue = DateTime.parse(template['next_due_at'] as String);

    await expenses.saveRecurringTemplate(
      id: template['id'] as String,
      name: 'Internet fibre',
      categoryId: category.id,
      amount: 32000,
      frequency: 'quarterly',
      dayOfMonth: 12,
      nextDueAt: oldDue,
    );

    template = (await expenses.recurringTemplates(includeInactive: true)).singleWhere((r) => r['id'] == template['id']);
    expect(template['active'], 0);
    expect(template['frequency'], 'quarterly');
    expect(template['day_of_month'], 12);
    final newDue = DateTime.parse(template['next_due_at'] as String);
    expect(newDue.day, 12);
    expect(newDue.isAfter(DateTime.now()), isTrue);
  });

  test('une classe inactive reste administrable et peut être réactivée', () async {
    final cycle = (await settings.cycles()).first;
    await settings.addClassroom(cycleId: cycle['id'] as String, name: 'Classe dormante', capacity: 30);
    final classroom = (await students.classrooms()).singleWhere((c) => c.name == 'Classe dormante');
    await settings.updateClassroom(id: classroom.id, name: classroom.name, capacity: classroom.capacity, active: false);

    expect((await students.classrooms()).where((c) => c.id == classroom.id), isEmpty);
    final inactive = (await students.classrooms(includeInactive: true)).singleWhere((c) => c.id == classroom.id);
    expect(inactive.active, isFalse);

    await settings.updateClassroom(id: inactive.id, name: inactive.name, capacity: inactive.capacity, active: true);
    expect((await students.classrooms()).any((c) => c.id == classroom.id), isTrue);
  });

  test('un appel à paiement historique conserve le libellé de l’année choisie', () {
    final years = <SchoolYearItem>[
      SchoolYearItem(
        id: '2025',
        label: '2025-2026',
        startDate: DateTime(2025, 9, 1),
        endDate: DateTime(2026, 7, 31),
        isActive: false,
      ),
      SchoolYearItem(
        id: '2026',
        label: '2026-2027',
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2027, 7, 31),
        isActive: true,
      ),
    ];
    expect(
      resolvePaymentNoticeSchoolYearLabel(
        years: years,
        selectedSchoolYearId: '2025',
        establishmentLabel: '2026-2027',
      ),
      '2025-2026',
    );
  });

}
